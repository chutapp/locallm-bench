#!/bin/bash
# run_single_bench.sh — Run ONE benchmark experiment with full metrics collection
# Usage: ./run_single_bench.sh <model_path> <engine> <memory_limit_gb> <context_size> <test_type>
# Example: ./run_single_bench.sh /models/Qwen3.5-35B-A3B-Q4_K_M.gguf llama.cpp 12 2048 quick

source /scripts/lib.sh

MODEL_PATH="$1"
ENGINE="$2"
MEM_LIMIT_GB="$3"
CTX_SIZE="${4:-2048}"
TEST_TYPE="${5:-quick}"

# Extract model info from filename
MODEL_FILE=$(basename "$MODEL_PATH")
MODEL_NAME=$(echo "$MODEL_FILE" | sed 's/\.gguf$//' | sed 's/\.bin$//')
QUANT=$(echo "$MODEL_NAME" | grep -oP 'Q[0-9]_K_[A-Z]|Q[0-9]_K|Q[0-9]_[0-9]|Q[0-9]' | tail -1)
[ -z "$QUANT" ] && QUANT="native"

EXPERIMENT_ID=$(result_filename "$MODEL_NAME" "$QUANT" "$ENGINE" "$MEM_LIMIT_GB" "$TEST_TYPE")
RESULT_FILE="$RESULTS_DIR/${EXPERIMENT_ID}.json"
MONITOR_FILE="$METRICS_DIR/${EXPERIMENT_ID}_process.json"
DISKIO_FILE="$METRICS_DIR/${EXPERIMENT_ID}_diskio.json"
RAWLOG_FILE="$LOGS_DIR/${EXPERIMENT_ID}_raw.log"

# Skip if already completed
if [ -f "$RESULT_FILE" ] && grep -q '"completed": true' "$RESULT_FILE" 2>/dev/null; then
  log_skip "Already completed: $EXPERIMENT_ID"
  exit 0
fi

log_start "Experiment: $EXPERIMENT_ID"
update_status "running" "$EXPERIMENT_ID"

# === Pre-flight checks ===
if [ ! -f "$MODEL_PATH" ]; then
  log_fail "Model file not found: $MODEL_PATH"
  echo '{"error":"model_not_found","model":"'$MODEL_PATH'","completed":false}' > "$RESULT_FILE"
  exit 1
fi

GGUF_SIZE_BYTES=$(stat -c%s "$MODEL_PATH" 2>/dev/null || stat -f%z "$MODEL_PATH" 2>/dev/null)
GGUF_SIZE_MB=$((GGUF_SIZE_BYTES / 1024 / 1024))
log_info "Model file size: ${GGUF_SIZE_MB}MB"

# === Capture pre-run system state ===
PRE_SNAPSHOT=$(capture_system_snapshot "pre_${EXPERIMENT_ID}")
PRE_DMESG_TS=$(date '+%Y-%m-%dT%H:%M:%S')

# Drop caches for clean measurement
sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
sleep 2

# === Define prompts for testing ===
SHORT_PROMPT="Explain the theory of relativity in simple terms."
MEDIUM_PROMPT="Write a detailed analysis of the economic impacts of artificial intelligence on the global workforce over the next decade. Consider both positive and negative effects, including job displacement, new job creation, productivity gains, wage effects, and the role of government policy in managing the transition. Provide specific examples from different industries."
LONG_PROMPT=$(python3 -c "print('Summarize this text: ' + 'The quick brown fox jumps over the lazy dog. ' * 200)")

# === RUN BENCHMARK ===
OUTCOME="UNKNOWN"
TOKENS_PER_SEC=0
TTFT_MS=0
PROMPT_TOK_SEC=0
ITL_SAMPLES=""
GENERATION_OUTPUT=""
LOAD_TIME_SEC=0
PEAK_RSS_MB=0

run_llamacpp_bench() {
  local prompt="$1"
  local n_predict="${2:-256}"
  local output_file="$RAWLOG_FILE"

  local start_ts=$(date +%s%N)

  # Start disk I/O monitor in background
  monitor_disk_io 300 2 "$DISKIO_FILE" &
  local diskio_pid=$!

  # Run with memory limit
  local cmd_start=$(date +%s%N)

  # stderr → output_file (memory breakdown, diagnostics)
  # stdout → pipe through tail to capture only last 10 lines (timing summary)
  # This keeps logs to <2KB instead of 100s of MB of generated text
  # Disable errexit for the pipeline so OOM exit codes don't kill the script
  # Pipeline exit code handling
  if [ "$MEM_LIMIT_GB" != "15.5" ] && [ "$MEM_LIMIT_GB" != "16" ]; then
    timeout 300 systemd-run --scope -p MemoryMax="${MEM_LIMIT_GB}G" -p MemorySwapMax=0 --quiet \
      llama-cli -m "$MODEL_PATH" \
        --ctx-size "$CTX_SIZE" \
        --threads $(nproc) \
        --no-mmap \
        --single-turn \
        --prompt "$prompt" \
        --n-predict "$n_predict" \
        --log-disable \
        2>"$output_file" | tail -10 >> "$output_file"
  else
    timeout 300 llama-cli -m "$MODEL_PATH" \
      --ctx-size "$CTX_SIZE" \
      --threads $(nproc) \
      --no-mmap \
      --single-turn \
      --prompt "$prompt" \
      --n-predict "$n_predict" \
      --log-disable \
      2>"$output_file" | tail -10 >> "$output_file"
  fi
  local exit_code=${PIPESTATUS[0]}
  # Continue after pipeline

  local cmd_end=$(date +%s%N)
  local wall_time_ms=$(( (cmd_end - cmd_start) / 1000000 ))

  # Stop disk I/O monitor
  kill $diskio_pid 2>/dev/null || true
  wait $diskio_pid 2>/dev/null || true

  # Check for OOM
  if [ $exit_code -eq 137 ] || [ $exit_code -eq 139 ]; then
    local oom_log=$(check_oom "$PRE_DMESG_TS")
    if [ -n "$oom_log" ]; then
      OUTCOME="OOM"
      log_oom "$EXPERIMENT_ID — killed by OOM (exit $exit_code)"
      return 1
    fi
  fi

  if [ $exit_code -ne 0 ]; then
    OUTCOME="ERROR"
    log_fail "$EXPERIMENT_ID — exit code $exit_code"
    return 1
  fi

  # Parse llama.cpp output for timing info
  if [ -f "$output_file" ]; then
    # New format (b8199+): "[ Prompt: 11.7 t/s | Generation: 3.7 t/s ]"
    PROMPT_TOK_SEC=$(grep -oP 'Prompt:\s*\K[0-9.]+' "$output_file" | tail -1 || echo "0")
    TOKENS_PER_SEC=$(grep -oP 'Generation:\s*\K[0-9.]+' "$output_file" | tail -1 || echo "0")

    # Fallback to old format if new format not found
    if [ "$TOKENS_PER_SEC" = "0" ] || [ -z "$TOKENS_PER_SEC" ]; then
      TOKENS_PER_SEC=$(grep -oP 'eval time.*\(\s*\K[0-9.]+(?=\s*tokens per sec)' "$output_file" | tail -1 || echo "0")
      PROMPT_TOK_SEC=$(grep -oP 'eval time.*\(\s*\K[0-9.]+(?=\s*tokens per sec)' "$output_file" | head -1 || echo "0")
    fi

    # Load time (old format, may not be present in new builds)
    LOAD_TIME_SEC=$(grep -oP 'load time\s*=\s*\K[0-9.]+' "$output_file" | head -1 || echo "0")

    # TTFT from old format
    TTFT_MS=$(grep -oP 'prompt eval time\s*=\s*\K[0-9.]+' "$output_file" | head -1 || echo "0")

    # Memory from new format: "Host | 12426 = 11857 + 72 + 497"
    if [ "$TTFT_MS" = "0" ] || [ -z "$TTFT_MS" ]; then
      # Estimate TTFT from wall time if not available
      TTFT_MS="0"
    fi
  fi

  OUTCOME="FITS"
  return 0
}

run_llamafile_bench() {
  local prompt="$1"
  local n_predict="${2:-256}"
  local output_file="$RAWLOG_FILE"

  # llamafile uses same CLI as llama.cpp but via its own binary
  local llamafile_bin="/opt/llamafile/llamafile"
  if [ ! -f "$llamafile_bin" ]; then
    log_fail "llamafile binary not found at $llamafile_bin"
    OUTCOME="ERROR"
    return 1
  fi

  local cmd_start=$(date +%s%N)

  monitor_disk_io 300 2 "$DISKIO_FILE" &
  local diskio_pid=$!

  # Pipeline exit code handling
  if [ "$MEM_LIMIT_GB" != "15.5" ] && [ "$MEM_LIMIT_GB" != "16" ]; then
    timeout 300 systemd-run --scope -p MemoryMax="${MEM_LIMIT_GB}G" -p MemorySwapMax=0 --quiet \
      $llamafile_bin -m "$MODEL_PATH" \
        --ctx-size "$CTX_SIZE" \
        --threads $(nproc) \
        --no-mmap \
        --single-turn \
        --prompt "$prompt" \
        --n-predict "$n_predict" \
        --log-disable \
        2>"$output_file" | tail -10 >> "$output_file"
  else
    timeout 300 $llamafile_bin -m "$MODEL_PATH" \
      --ctx-size "$CTX_SIZE" \
      --threads $(nproc) \
      --no-mmap \
      --single-turn \
      --prompt "$prompt" \
      --n-predict "$n_predict" \
      --log-disable \
      2>"$output_file" | tail -10 >> "$output_file"
  fi
  local exit_code=${PIPESTATUS[0]}
  # Continue after pipeline

  local cmd_end=$(date +%s%N)
  kill $diskio_pid 2>/dev/null || true
  wait $diskio_pid 2>/dev/null || true

  if [ $exit_code -eq 137 ] || [ $exit_code -eq 139 ]; then
    local oom_log=$(check_oom "$PRE_DMESG_TS")
    if [ -n "$oom_log" ]; then
      OUTCOME="OOM"
      log_oom "$EXPERIMENT_ID — llamafile OOM (exit $exit_code)"
      return 1
    fi
  fi

  if [ $exit_code -ne 0 ]; then
    OUTCOME="ERROR"
    log_fail "$EXPERIMENT_ID — llamafile exit $exit_code"
    return 1
  fi

  # Parse output (same format as llama.cpp)
  if [ -f "$output_file" ]; then
    PROMPT_TOK_SEC=$(grep -oP 'Prompt:\s*\K[0-9.]+' "$output_file" | tail -1 || echo "0")
    TOKENS_PER_SEC=$(grep -oP 'Generation:\s*\K[0-9.]+' "$output_file" | tail -1 || echo "0")
    if [ "$TOKENS_PER_SEC" = "0" ] || [ -z "$TOKENS_PER_SEC" ]; then
      TOKENS_PER_SEC=$(grep -oP 'eval time.*\(\s*\K[0-9.]+(?=\s*tokens per sec)' "$output_file" | tail -1 || echo "0")
      PROMPT_TOK_SEC=$(grep -oP 'eval time.*\(\s*\K[0-9.]+(?=\s*tokens per sec)' "$output_file" | head -1 || echo "0")
    fi
    LOAD_TIME_SEC=$(grep -oP 'load time\s*=\s*\K[0-9.]+' "$output_file" | head -1 || echo "0")
    TTFT_MS=$(grep -oP 'prompt eval time\s*=\s*\K[0-9.]+' "$output_file" | head -1 || echo "0")
  fi

  OUTCOME="FITS"
  return 0
}

run_bitnet_bench() {
  local prompt="$1"
  local n_predict="${2:-256}"
  local output_file="$RAWLOG_FILE"

  local bitnet_bin="/opt/BitNet/build/bin/llama-cli"
  if [ ! -f "$bitnet_bin" ]; then
    log_fail "bitnet.cpp binary not found at $bitnet_bin"
    OUTCOME="ERROR"
    return 1
  fi

  local cmd_start=$(date +%s%N)

  monitor_disk_io 300 2 "$DISKIO_FILE" &
  local diskio_pid=$!

  # Pipeline exit code handling
  if [ "$MEM_LIMIT_GB" != "15.5" ] && [ "$MEM_LIMIT_GB" != "16" ]; then
    timeout 300 systemd-run --scope -p MemoryMax="${MEM_LIMIT_GB}G" -p MemorySwapMax=0 --quiet \
      $bitnet_bin -m "$MODEL_PATH" \
        --ctx-size "$CTX_SIZE" \
        --threads $(nproc) \
        --prompt "$prompt" \
        --n-predict "$n_predict" \
        2>"$output_file" | tail -10 >> "$output_file"
  else
    timeout 300 $bitnet_bin -m "$MODEL_PATH" \
      --ctx-size "$CTX_SIZE" \
      --threads $(nproc) \
      --prompt "$prompt" \
      --n-predict "$n_predict" \
      2>"$output_file" | tail -10 >> "$output_file"
  fi
  local exit_code=${PIPESTATUS[0]}
  # Continue after pipeline

  local cmd_end=$(date +%s%N)
  kill $diskio_pid 2>/dev/null || true
  wait $diskio_pid 2>/dev/null || true

  if [ $exit_code -eq 137 ] || [ $exit_code -eq 139 ]; then
    OUTCOME="OOM"
    log_oom "$EXPERIMENT_ID — bitnet.cpp OOM (exit $exit_code)"
    return 1
  fi

  if [ $exit_code -ne 0 ]; then
    OUTCOME="ERROR"
    log_fail "$EXPERIMENT_ID — bitnet.cpp exit $exit_code"
    return 1
  fi

  # Parse output (may use old or new llama.cpp format)
  if [ -f "$output_file" ]; then
    PROMPT_TOK_SEC=$(grep -oP 'Prompt:\s*\K[0-9.]+' "$output_file" | tail -1 || echo "0")
    TOKENS_PER_SEC=$(grep -oP 'Generation:\s*\K[0-9.]+' "$output_file" | tail -1 || echo "0")
    if [ "$TOKENS_PER_SEC" = "0" ] || [ -z "$TOKENS_PER_SEC" ]; then
      TOKENS_PER_SEC=$(grep -oP 'eval time.*\(\s*\K[0-9.]+(?=\s*tokens per sec)' "$output_file" | tail -1 || echo "0")
      PROMPT_TOK_SEC=$(grep -oP 'eval time.*\(\s*\K[0-9.]+(?=\s*tokens per sec)' "$output_file" | head -1 || echo "0")
    fi
    LOAD_TIME_SEC=$(grep -oP 'load time\s*=\s*\K[0-9.]+' "$output_file" | head -1 || echo "0")
    TTFT_MS=$(grep -oP 'prompt eval time\s*=\s*\K[0-9.]+' "$output_file" | head -1 || echo "0")
  fi

  OUTCOME="FITS"
  return 0
}

run_powerinfer_bench() {
  local prompt="$1"
  local n_predict="${2:-256}"
  local output_file="$RAWLOG_FILE"

  local pi_bin="/opt/PowerInfer/build/bin/main"
  if [ ! -f "$pi_bin" ]; then
    log_fail "PowerInfer binary not found at $pi_bin"
    OUTCOME="ERROR"
    return 1
  fi

  local cmd_start=$(date +%s%N)

  monitor_disk_io 300 2 "$DISKIO_FILE" &
  local diskio_pid=$!

  # Pipeline exit code handling
  if [ "$MEM_LIMIT_GB" != "15.5" ] && [ "$MEM_LIMIT_GB" != "16" ]; then
    timeout 300 systemd-run --scope -p MemoryMax="${MEM_LIMIT_GB}G" -p MemorySwapMax=0 --quiet \
      $pi_bin -m "$MODEL_PATH" \
        --ctx-size "$CTX_SIZE" \
        --threads $(nproc) \
        --prompt "$prompt" \
        --n-predict "$n_predict" \
        2>"$output_file" | tail -10 >> "$output_file"
  else
    timeout 300 $pi_bin -m "$MODEL_PATH" \
      --ctx-size "$CTX_SIZE" \
      --threads $(nproc) \
      --prompt "$prompt" \
      --n-predict "$n_predict" \
      2>"$output_file" | tail -10 >> "$output_file"
  fi
  local exit_code=${PIPESTATUS[0]}
  # Continue after pipeline

  local cmd_end=$(date +%s%N)
  kill $diskio_pid 2>/dev/null || true
  wait $diskio_pid 2>/dev/null || true

  if [ $exit_code -eq 137 ] || [ $exit_code -eq 139 ]; then
    OUTCOME="OOM"
    log_oom "$EXPERIMENT_ID — PowerInfer OOM (exit $exit_code)"
    return 1
  fi

  if [ $exit_code -ne 0 ]; then
    OUTCOME="ERROR"
    log_fail "$EXPERIMENT_ID — PowerInfer exit $exit_code"
    return 1
  fi

  if [ -f "$output_file" ]; then
    PROMPT_TOK_SEC=$(grep -oP 'Prompt:\s*\K[0-9.]+' "$output_file" | tail -1 || echo "0")
    TOKENS_PER_SEC=$(grep -oP 'Generation:\s*\K[0-9.]+' "$output_file" | tail -1 || echo "0")
    if [ "$TOKENS_PER_SEC" = "0" ] || [ -z "$TOKENS_PER_SEC" ]; then
      TOKENS_PER_SEC=$(grep -oP 'eval time.*\(\s*\K[0-9.]+(?=\s*tokens per sec)' "$output_file" | tail -1 || echo "0")
      PROMPT_TOK_SEC=$(grep -oP 'eval time.*\(\s*\K[0-9.]+(?=\s*tokens per sec)' "$output_file" | head -1 || echo "0")
    fi
    LOAD_TIME_SEC=$(grep -oP 'load time\s*=\s*\K[0-9.]+' "$output_file" | head -1 || echo "0")
    TTFT_MS=$(grep -oP 'prompt eval time\s*=\s*\K[0-9.]+' "$output_file" | head -1 || echo "0")
  fi

  OUTCOME="FITS"
  return 0
}

# === Main execution ===
log_info "Running: model=$MODEL_NAME engine=$ENGINE mem=${MEM_LIMIT_GB}GB ctx=$CTX_SIZE test=$TEST_TYPE"

BENCH_EXIT=0
case "$ENGINE" in
  llama.cpp)
    run_llamacpp_bench "$SHORT_PROMPT" 256 || BENCH_EXIT=$?
    ;;
  llamafile)
    run_llamafile_bench "$SHORT_PROMPT" 256 || BENCH_EXIT=$?
    ;;
  bitnet.cpp)
    run_bitnet_bench "$SHORT_PROMPT" 256 || BENCH_EXIT=$?
    ;;
  powerinfer)
    run_powerinfer_bench "$SHORT_PROMPT" 256 || BENCH_EXIT=$?
    ;;
  *)
    log_error "Unknown engine: $ENGINE"
    exit 1
    ;;
esac

# === Capture post-run system state ===
POST_SNAPSHOT=$(capture_system_snapshot "post_${EXPERIMENT_ID}")

# === Check for disk thrashing ===
DISK_READ_AVG=0
if [ -f "$DISKIO_FILE" ]; then
  DISK_READ_AVG=$(python3 -c "
import json, sys
try:
    with open('$DISKIO_FILE') as f:
        data = f.read()
    # Simple average of read MB/s
    import re
    reads = re.findall(r'rMB/s[\":\s]+([0-9.]+)', data)
    if reads:
        avg = sum(float(r) for r in reads) / len(reads)
        print(f'{avg:.2f}')
    else:
        print('0')
except:
    print('0')
" 2>/dev/null || echo "0")
fi

# Detect thrashing: >50MB/s sustained disk read during inference
if [ "$OUTCOME" = "FITS" ] && [ "$(echo "$DISK_READ_AVG > 50" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
  OUTCOME="THRASHES"
  log_warn "$EXPERIMENT_ID — disk thrashing detected: ${DISK_READ_AVG}MB/s avg read"
fi

# === Check OOM in dmesg ===
OOM_LOG=$(check_oom "$PRE_DMESG_TS")
if [ -n "$OOM_LOG" ] && [ "$OUTCOME" != "OOM" ]; then
  OUTCOME="OOM"
  log_oom "$EXPERIMENT_ID — OOM detected in dmesg"
fi

# === Peak RSS — parse from llama.cpp's own memory report ===
# b8199+ prints: "Host  |  12456 = 11857 + 102 + 497" (MiB)
if [ -f "$RAWLOG_FILE" ]; then
  HOST_MEM=$(grep 'Host' "$RAWLOG_FILE" 2>/dev/null | grep -oP '\d+\s*=' | head -1 | grep -oP '\d+')
  if [ -n "$HOST_MEM" ] && [ "$HOST_MEM" -gt 10 ] 2>/dev/null; then
    PEAK_RSS_MB=$HOST_MEM
  fi
fi

# === Write final result ===
cat > "$RESULT_FILE" << RESULTEOF
{
  "completed": true,
  "experiment_id": "$EXPERIMENT_ID",
  "metadata": {
    "model_name": "$MODEL_NAME",
    "model_file": "$MODEL_FILE",
    "quant": "$QUANT",
    "gguf_size_mb": $GGUF_SIZE_MB,
    "engine": "$ENGINE",
    "memory_tier_gb": $MEM_LIMIT_GB,
    "context_size": $CTX_SIZE,
    "test_type": "$TEST_TYPE",
    "server": "$SERVER_NAME",
    "server_ip": "$SERVER_IP",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "cpu_model": "$(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)",
    "cpu_cores": $(nproc),
    "total_ram_mb": $(free -m | awk '/Mem:/{print $2}')
  },
  "outcome": "$OUTCOME",
  "speed": {
    "tokens_per_sec_generation": $TOKENS_PER_SEC,
    "tokens_per_sec_prompt": $PROMPT_TOK_SEC,
    "ttft_ms": $TTFT_MS,
    "model_load_time_sec": $LOAD_TIME_SEC
  },
  "memory": {
    "peak_rss_mb": $PEAK_RSS_MB,
    "gguf_size_mb": $GGUF_SIZE_MB
  },
  "disk_io": {
    "avg_read_mb_sec": $DISK_READ_AVG
  },
  "user_experience": {
    "usable": $([ "$OUTCOME" = "FITS" ] && python3 -c "print('true' if $TOKENS_PER_SEC > 5 else 'false')" || echo "false"),
    "good": $([ "$OUTCOME" = "FITS" ] && python3 -c "print('true' if $TOKENS_PER_SEC > 10 else 'false')" || echo "false"),
    "excellent": $([ "$OUTCOME" = "FITS" ] && python3 -c "print('true' if $TOKENS_PER_SEC > 20 else 'false')" || echo "false")
  },
  "files": {
    "raw_log": "$RAWLOG_FILE",
    "process_monitor": "$MONITOR_FILE",
    "disk_io_log": "$DISKIO_FILE",
    "pre_snapshot": "$PRE_SNAPSHOT",
    "post_snapshot": "$POST_SNAPSHOT"
  }
}
RESULTEOF

if [ "$OUTCOME" = "FITS" ]; then
  log_done "$EXPERIMENT_ID — ${TOKENS_PER_SEC} tok/s, ${PEAK_RSS_MB}MB RAM, TTFT ${TTFT_MS}ms"
elif [ "$OUTCOME" = "OOM" ]; then
  log_oom "$EXPERIMENT_ID — Out of memory at ${MEM_LIMIT_GB}GB limit"
elif [ "$OUTCOME" = "THRASHES" ]; then
  log_warn "$EXPERIMENT_ID — Thrashing: ${DISK_READ_AVG}MB/s disk read, ${TOKENS_PER_SEC} tok/s"
else
  log_fail "$EXPERIMENT_ID — $OUTCOME"
fi

update_status "idle" "Completed: $EXPERIMENT_ID"
