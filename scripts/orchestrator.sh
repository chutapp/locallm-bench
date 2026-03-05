#!/bin/bash
# orchestrator.sh — Master script that runs ALL experiments for this server
# Usage: nohup ./orchestrator.sh <server_role> >> /logs/orchestrator.log 2>&1 &
# The script runs unattended overnight. Check /logs/status.json for progress.

source /scripts/lib.sh

SERVER_ROLE="${1:-unknown}"
START_TIME=$(date +%s)
TOTAL_EXPERIMENTS=0
COMPLETED=0
FAILED=0
SKIPPED=0

log_info "=============================================="
log_info "ORCHESTRATOR START — Role: $SERVER_ROLE"
log_info "=============================================="

start_heartbeat
update_status "starting" "Orchestrator initializing"

# === Phase 0: Download models ===
log_info "=== PHASE 0: Downloading models ==="
update_status "downloading" "Phase 0: Model downloads"
bash /scripts/download_models.sh "$SERVER_ROLE" 2>&1 | tee -a "$LOGS_DIR/download.log"
log_info "Downloads complete"

# === Helper: run a bench and track stats ===
run_experiment() {
  local model_path="$1"
  local engine="$2"
  local mem_gb="$3"
  local ctx="$4"
  local test_type="$5"

  TOTAL_EXPERIMENTS=$((TOTAL_EXPERIMENTS + 1))

  local exp_name="$(basename $model_path .gguf)_${engine}_${mem_gb}GB_ctx${ctx}"
  log_info "--- Experiment $TOTAL_EXPERIMENTS: $exp_name ---"
  update_status "running" "Exp #$TOTAL_EXPERIMENTS: $exp_name (done=$COMPLETED, fail=$FAILED, skip=$SKIPPED)"

  bash /scripts/run_single_bench.sh "$model_path" "$engine" "$mem_gb" "$ctx" "$test_type"
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    COMPLETED=$((COMPLETED + 1))
  else
    # Check if it was skipped (already done)
    local result_file=$(ls -t "$RESULTS_DIR"/*"$(basename $model_path .gguf)"*"${engine}"*"${mem_gb}"* 2>/dev/null | head -1)
    if [ -n "$result_file" ] && grep -q '"completed": true' "$result_file" 2>/dev/null; then
      SKIPPED=$((SKIPPED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  fi

  # Brief pause between experiments to let system settle
  sleep 5
}

# === Phase 1: Quick Benchmarks (all model/quant/tier/engine combos) ===
log_info "=== PHASE 1: Quick Benchmarks ==="
update_status "phase1" "Quick benchmarks"

MEMORY_TIERS=(12 14 15.5)

case "$SERVER_ROLE" in
  bench-1)
    MODELS=(
      "/models/Qwen3.5-35B-A3B-Q2_K.gguf"
      "/models/Qwen3.5-35B-A3B-Q3_K_M.gguf"
      "/models/Qwen3.5-35B-A3B-Q4_K_M.gguf"
      "/models/Qwen3.5-35B-A3B-Q5_K_M.gguf"
      "/models/Llama-4-Scout-17B-16E-Instruct-UD-IQ1_M.gguf"
    )
    ;;
  bench-2)
    MODELS=(
      "/models/GLM-4.7-Flash-Q2_K.gguf"
      "/models/GLM-4.7-Flash-Q3_K_M.gguf"
      "/models/GLM-4.7-Flash-Q4_K_M.gguf"
      "/models/GLM-4.7-Flash-Q5_K_M.gguf"
      "/models/Nemotron-3-Nano-30B-A3B-Q2_K.gguf"
      "/models/Nemotron-3-Nano-30B-A3B-Q3_K_M.gguf"
      "/models/Nemotron-3-Nano-30B-A3B-Q4_K_M.gguf"
      "/models/Nemotron-3-Nano-30B-A3B-Q5_K_M.gguf"
      "/models/Ministral-3-14B-Reasoning-2512-Q4_K_M.gguf"
      "/models/Ministral-3-14B-Reasoning-2512-Q5_K_M.gguf"
      "/models/Ministral-3-14B-Reasoning-2512-Q8_0.gguf"
    )
    ;;
  bench-3)
    MODELS=(
      "/models/gemma-3-27b-it-Q2_K.gguf"
      "/models/gemma-3-27b-it-Q3_K_M.gguf"
      "/models/gemma-3-27b-it-Q4_K_M.gguf"
      "/models/Mistral-Small-24B-Instruct-2501-Q2_K.gguf"
      "/models/Mistral-Small-24B-Instruct-2501-Q3_K_M.gguf"
      "/models/Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf"
      "/models/DeepSeek-R1-Distill-Qwen-32B-Q2_K.gguf"
      "/models/DeepSeek-R1-Distill-Qwen-32B-Q3_K_M.gguf"
      "/models/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf"
      "/models/Falcon-H1R-7B-Q4_K_M.gguf"
      "/models/Falcon-H1R-7B-Q8_0.gguf"
    )
    ;;
esac

# Run llama.cpp engine across all memory tiers
for model in "${MODELS[@]}"; do
  [ ! -f "$model" ] && { log_warn "Model not found, skipping: $model"; continue; }
  for tier in "${MEMORY_TIERS[@]}"; do
    run_experiment "$model" "llama.cpp" "$tier" 2048 "quick"
  done
done

log_info "Phase 1 llama.cpp complete."

# === Phase 1b: Extra engines on bench-3 ===
if [ "$SERVER_ROLE" = "bench-3" ]; then
  log_info "=== PHASE 1b: Extra Engines (llamafile, bitnet.cpp, PowerInfer) ==="
  update_status "phase1b" "Extra engine benchmarks"

  # llamafile — test on all GGUF models assigned to bench-3
  if [ -f "/opt/llamafile/llamafile" ]; then
    log_info "--- llamafile engine ---"
    for model in "${MODELS[@]}"; do
      [ ! -f "$model" ] && continue
      for tier in "${MEMORY_TIERS[@]}"; do
        run_experiment "$model" "llamafile" "$tier" 2048 "quick"
      done
    done
  else
    log_warn "llamafile not installed, skipping"
  fi

  # bitnet.cpp — test on ternary models
  if [ -f "/opt/BitNet/build/bin/llama-cli" ]; then
    log_info "--- bitnet.cpp engine ---"
    TERNARY_MODELS=(
      "/models/bitnet-b1.58-2B-4T"
    )
    for model_dir in "${TERNARY_MODELS[@]}"; do
      if [ -d "$model_dir" ]; then
        # Find the model file inside the directory
        model_file=$(find "$model_dir" -name "*.bin" -o -name "*.gguf" -o -name "*.safetensors" 2>/dev/null | head -1)
        if [ -n "$model_file" ]; then
          for tier in "${MEMORY_TIERS[@]}"; do
            run_experiment "$model_file" "bitnet.cpp" "$tier" 2048 "quick"
          done
        else
          log_warn "No model file found in $model_dir"
        fi
      else
        log_warn "Ternary model dir not found: $model_dir"
      fi
    done
  else
    log_warn "bitnet.cpp not installed, skipping"
  fi

  # PowerInfer — test on GGUF models (works on ReLU-based models)
  if [ -f "/opt/PowerInfer/build/bin/main" ]; then
    log_info "--- PowerInfer engine ---"
    for model in "${MODELS[@]}"; do
      [ ! -f "$model" ] && continue
      # PowerInfer works best with specific models, try all and let it fail gracefully
      for tier in "${MEMORY_TIERS[@]}"; do
        run_experiment "$model" "powerinfer" "$tier" 2048 "quick"
      done
    done
  else
    log_warn "PowerInfer not installed, skipping"
  fi

  log_info "Phase 1b extra engines complete."
fi

# === Phase 2: Context Scaling (models that passed Phase 1) ===
log_info "=== PHASE 2: Context Scaling ==="
update_status "phase2" "Context scaling tests"

CONTEXT_SIZES=(512 1024 2048 4096 8192)

# Find models that FITS at 14GB tier
PASSING_MODELS=$(grep -l '"outcome": "FITS"' "$RESULTS_DIR"/quick_*_llama.cpp_14GB.json 2>/dev/null | while read f; do
  python3 -c "import json; d=json.load(open('$f')); print(d['metadata']['model_file'])" 2>/dev/null
done | sort -u)

for model_file in $PASSING_MODELS; do
  model_path="$MODELS_DIR/$model_file"
  [ ! -f "$model_path" ] && continue
  for ctx in "${CONTEXT_SIZES[@]}"; do
    run_experiment "$model_path" "llama.cpp" "14" "$ctx" "context_scaling"
  done
done

# === Phase 3: Long-Running Stability (top 3 by tok/s) ===
log_info "=== PHASE 3: Long-Running Stability ==="
update_status "phase3" "Stability tests"

TOP_MODELS=$(python3 << 'PYEOF'
import json, glob, os

results = []
for f in glob.glob("/results/quick_*_llama.cpp_14GB.json"):
    try:
        with open(f) as fh:
            d = json.load(fh)
        if d.get("outcome") == "FITS":
            results.append({
                "model_file": d["metadata"]["model_file"],
                "tg": d["speed"]["tokens_per_sec_generation"]
            })
    except:
        pass

results.sort(key=lambda x: x["tg"], reverse=True)
for r in results[:3]:
    print(r["model_file"])
PYEOF
)

for model_file in $TOP_MODELS; do
  model_path="$MODELS_DIR/$model_file"
  [ ! -f "$model_path" ] && continue

  log_info "Stability test: $model_file (30 min continuous)"
  update_status "phase3_stability" "30min: $model_file"

  STAB_RESULT="$RESULTS_DIR/stability_$(basename $model_file .gguf).json"
  STAB_LOG="$LOGS_DIR/stability_$(basename $model_file .gguf).log"

  # Generate continuously for 30 minutes, sampling every 30 seconds
  python3 << PYEOF > "$STAB_RESULT" 2>"$STAB_LOG"
import subprocess, time, json, os, re

model_path = "$model_path"
ctx_size = 2048
duration_sec = 1800  # 30 minutes
sample_interval = 30

samples = []
start_time = time.time()

prompt = "Write a very long and detailed story about a space exploration mission to discover new civilizations. Include character development, plot twists, and scientific details. The story should be engaging and creative."

while time.time() - start_time < duration_sec:
    sample_start = time.time()

    # Run a short generation
    try:
        result = subprocess.run(
            ["llama-cli", "-m", model_path, "--ctx-size", str(ctx_size),
             "--threads", str(os.cpu_count()), "--no-mmap", "--single-turn",
             "--prompt", prompt, "--n-predict", "100", "--log-disable"],
            capture_output=True, text=True, timeout=120
        )
        output = result.stderr + result.stdout

        # Parse tok/s
        # New format: "[ Prompt: X t/s | Generation: Y t/s ]"
        tg_match = re.findall(r'Generation:\s*(\d+\.\d+)', output)
        if not tg_match:
            tg_match = re.findall(r'(\d+\.\d+)\s*tokens per sec', output)
        tg = float(tg_match[-1]) if tg_match else 0

        # Memory
        mem = {}
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    parts = line.split()
                    if parts[0] in ("MemTotal:", "MemAvailable:", "MemFree:"):
                        mem[parts[0].rstrip(":")] = int(parts[1]) // 1024
        except:
            pass

        # CPU temp
        cpu_temp = None
        try:
            for root, dirs, files in os.walk("/sys/class/thermal/"):
                for d in dirs:
                    if "thermal_zone" in d:
                        with open(os.path.join(root, d, "temp")) as f:
                            t = int(f.read().strip()) / 1000
                            if cpu_temp is None or t > cpu_temp:
                                cpu_temp = t
        except:
            pass

        # CPU freq
        cpu_freq = None
        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if "cpu MHz" in line:
                        cpu_freq = float(line.split(":")[1].strip())
                        break
        except:
            pass

        elapsed = time.time() - start_time
        samples.append({
            "elapsed_sec": round(elapsed, 1),
            "minute": round(elapsed / 60, 1),
            "tokens_per_sec": tg,
            "mem_available_mb": mem.get("MemAvailable", 0),
            "mem_used_mb": mem.get("MemTotal", 0) - mem.get("MemAvailable", 0),
            "cpu_temp_c": cpu_temp,
            "cpu_freq_mhz": cpu_freq,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        })

    except subprocess.TimeoutExpired:
        samples.append({
            "elapsed_sec": round(time.time() - start_time, 1),
            "error": "timeout",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        })
    except Exception as e:
        samples.append({
            "elapsed_sec": round(time.time() - start_time, 1),
            "error": str(e),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        })

    # Wait for next sample
    elapsed_sample = time.time() - sample_start
    if elapsed_sample < sample_interval:
        time.sleep(sample_interval - elapsed_sample)

# Compute summary
tg_values = [s["tokens_per_sec"] for s in samples if "tokens_per_sec" in s and s["tokens_per_sec"] > 0]
mem_values = [s.get("mem_used_mb", 0) for s in samples if s.get("mem_used_mb", 0) > 0]
temp_values = [s.get("cpu_temp_c") for s in samples if s.get("cpu_temp_c") is not None]

result = {
    "completed": True,
    "test_type": "stability_30min",
    "model": os.path.basename(model_path),
    "duration_sec": duration_sec,
    "num_samples": len(samples),
    "summary": {
        "tg_start": tg_values[0] if tg_values else 0,
        "tg_end": tg_values[-1] if tg_values else 0,
        "tg_min": min(tg_values) if tg_values else 0,
        "tg_max": max(tg_values) if tg_values else 0,
        "tg_avg": sum(tg_values)/len(tg_values) if tg_values else 0,
        "tg_degradation_pct": round((1 - tg_values[-1]/tg_values[0]) * 100, 1) if tg_values and tg_values[0] > 0 else 0,
        "mem_start_mb": mem_values[0] if mem_values else 0,
        "mem_end_mb": mem_values[-1] if mem_values else 0,
        "mem_leak_mb": (mem_values[-1] - mem_values[0]) if len(mem_values) >= 2 else 0,
        "temp_start_c": temp_values[0] if temp_values else None,
        "temp_peak_c": max(temp_values) if temp_values else None,
        "thermal_throttle_detected": (max(temp_values) - temp_values[0] > 15) if len(temp_values) >= 2 else False
    },
    "samples": samples
}
print(json.dumps(result, indent=2))
PYEOF

  log_done "Stability test complete: $model_file"
done

# === Phase 4: Multi-turn Conversation (top 3) ===
log_info "=== PHASE 4: Multi-turn Conversation ==="
update_status "phase4" "Multi-turn tests"

for model_file in $TOP_MODELS; do
  model_path="$MODELS_DIR/$model_file"
  [ ! -f "$model_path" ] && continue

  TURN_RESULT="$RESULTS_DIR/multiturn_$(basename $model_file .gguf).json"

  python3 << PYEOF > "$TURN_RESULT" 2>"$LOGS_DIR/multiturn_$(basename $model_file .gguf).log"
import subprocess, time, json, os, re

model_path = "$model_path"
turns = []
conversation = ""

prompts = [
    "What is machine learning?",
    "How does it differ from deep learning?",
    "Can you give me an example with neural networks?",
    "What about transformer architecture specifically?",
    "How do attention mechanisms work?",
    "What is self-attention vs cross-attention?",
    "Explain the concept of positional encoding.",
    "How does BERT use transformers differently than GPT?",
    "What are the main challenges in training large language models?",
    "Summarize everything we discussed in 3 bullet points."
]

for i, prompt in enumerate(prompts):
    conversation += f"User: {prompt}\nAssistant: "

    start = time.time()
    try:
        result = subprocess.run(
            ["llama-cli", "-m", model_path, "--ctx-size", "4096",
             "--threads", str(os.cpu_count()), "--no-mmap", "--single-turn",
             "--prompt", conversation, "--n-predict", "150", "--log-disable"],
            capture_output=True, text=True, timeout=180
        )
        elapsed = time.time() - start
        output = result.stderr + result.stdout

        # New format: "[ Prompt: X t/s | Generation: Y t/s ]"
        tg_match = re.findall(r'Generation:\s*(\d+\.\d+)', output)
        if not tg_match:
            tg_match = re.findall(r'(\d+\.\d+)\s*tokens per sec', output)
        tg = float(tg_match[-1]) if tg_match else 0

        ttft_match = re.findall(r'prompt eval time\s*=\s*(\d+\.\d+)', output)
        ttft = float(ttft_match[0]) if ttft_match else 0

        # Add response to conversation
        response_text = result.stdout[-500:] if result.stdout else ""
        conversation += response_text + "\n"

        turns.append({
            "turn": i + 1,
            "prompt": prompt,
            "tokens_per_sec": tg,
            "ttft_ms": ttft,
            "wall_time_sec": round(elapsed, 2),
            "conversation_length_chars": len(conversation)
        })
    except Exception as e:
        turns.append({"turn": i + 1, "error": str(e)})

tg_values = [t["tokens_per_sec"] for t in turns if "tokens_per_sec" in t and t["tokens_per_sec"] > 0]

result = {
    "completed": True,
    "test_type": "multi_turn",
    "model": os.path.basename(model_path),
    "num_turns": len(turns),
    "summary": {
        "tg_turn_1": tg_values[0] if tg_values else 0,
        "tg_turn_5": tg_values[4] if len(tg_values) > 4 else 0,
        "tg_turn_10": tg_values[9] if len(tg_values) > 9 else 0,
        "degradation_pct": round((1 - tg_values[-1]/tg_values[0]) * 100, 1) if len(tg_values) >= 2 and tg_values[0] > 0 else 0
    },
    "turns": turns
}
print(json.dumps(result, indent=2))
PYEOF

  log_done "Multi-turn test complete: $model_file"
done

# === Phase 5: Concurrent Load (top 3) ===
log_info "=== PHASE 5: Concurrent Load ==="
update_status "phase5" "Concurrent load tests"

for model_file in $TOP_MODELS; do
  model_path="$MODELS_DIR/$model_file"
  [ ! -f "$model_path" ] && continue

  CONC_RESULT="$RESULTS_DIR/concurrent_$(basename $model_file .gguf).json"

  # Run with stress in background
  stress --cpu 2 --timeout 120 &
  STRESS_PID=$!
  sleep 5  # Let stress warm up

  run_experiment "$model_path" "llama.cpp" "14" 2048 "concurrent"

  kill $STRESS_PID 2>/dev/null || true
  wait $STRESS_PID 2>/dev/null || true

  log_done "Concurrent load test complete: $model_file"
done

# === Phase 6: Quality Evaluation ===
log_info "=== PHASE 6: Quality Evaluation ==="
update_status "phase6" "Quality evaluations"

# Run quality eval on top 3 passing models at 15.5GB (best quality tier)
QUALITY_MODELS=$(python3 << 'PYEOF'
import json, glob

results = []
for f in glob.glob("/results/quick_*_llama.cpp_14GB.json") + glob.glob("/results/quick_*_llama.cpp_15.5GB.json"):
    try:
        with open(f) as fh:
            d = json.load(fh)
        if d.get("outcome") == "FITS":
            model_file = d["metadata"]["model_file"]
            tg = d["speed"]["tokens_per_sec_generation"]
            # Deduplicate by model, keep best
            results.append({"model_file": model_file, "tg": tg})
    except:
        pass

# Deduplicate
seen = {}
for r in results:
    mf = r["model_file"]
    if mf not in seen or r["tg"] > seen[mf]["tg"]:
        seen[mf] = r

ranked = sorted(seen.values(), key=lambda x: x["tg"], reverse=True)
for r in ranked[:5]:
    print(r["model_file"])
PYEOF
)

for model_file in $QUALITY_MODELS; do
  model_path="$MODELS_DIR/$model_file"
  [ ! -f "$model_path" ] && continue

  log_info "Quality eval: $model_file"
  TOTAL_EXPERIMENTS=$((TOTAL_EXPERIMENTS + 1))
  update_status "phase6_quality" "Quality: $model_file (done=$COMPLETED, fail=$FAILED)"

  bash /scripts/run_quality_eval.sh "$model_path" "llama.cpp" 2>&1 | tee -a "$LOGS_DIR/quality_eval.log"
  if [ $? -eq 0 ]; then
    COMPLETED=$((COMPLETED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
  sleep 5
done

# Also quality-eval ternary models on bench-3
if [ "$SERVER_ROLE" = "bench-3" ]; then
  for model_dir in "/models/bitnet-b1.58-2B-4T"; do
    if [ -d "$model_dir" ]; then
      model_file=$(find "$model_dir" -name "*.bin" -o -name "*.gguf" -o -name "*.safetensors" 2>/dev/null | head -1)
      if [ -n "$model_file" ]; then
        log_info "Quality eval (ternary): $model_file"
        TOTAL_EXPERIMENTS=$((TOTAL_EXPERIMENTS + 1))
        bash /scripts/run_quality_eval.sh "$model_file" "bitnet.cpp" 2>&1 | tee -a "$LOGS_DIR/quality_eval.log"
        if [ $? -eq 0 ]; then COMPLETED=$((COMPLETED + 1)); else FAILED=$((FAILED + 1)); fi
      fi
    fi
  done
fi

log_info "Phase 6 quality evaluation complete."

# === Phase 7: Recovery & Burst Testing ===
log_info "=== PHASE 7: Recovery & Burst Testing ==="
update_status "phase7" "Recovery and burst tests"

# Test 1: OOM recovery — load a model that OOMs at 12GB, then load a smaller one
# This tests whether the system recovers cleanly after OOM
RECOVERY_RESULT="$RESULTS_DIR/recovery_${SERVER_ROLE}.json"

python3 << 'PYEOF' > "$RECOVERY_RESULT" 2>"$LOGS_DIR/recovery_${SERVER_ROLE}.log"
import subprocess, time, json, glob, os

results = {"test_type": "recovery", "completed": True, "tests": []}

# Find a model that OOM'd at 12GB
oom_models = []
for f in glob.glob("/results/quick_*_12GB.json"):
    try:
        with open(f) as fh:
            d = json.load(fh)
        if d.get("outcome") == "OOM":
            oom_models.append(d["metadata"]["model_file"])
    except:
        pass

# Find a model that FITS at 12GB
fit_models = []
for f in glob.glob("/results/quick_*_12GB.json"):
    try:
        with open(f) as fh:
            d = json.load(fh)
        if d.get("outcome") == "FITS":
            fit_models.append(d["metadata"]["model_file"])
    except:
        pass

if oom_models and fit_models:
    oom_model = f"/models/{oom_models[0]}"
    fit_model = f"/models/{fit_models[0]}"

    # Step 1: Trigger OOM
    print(f"Step 1: Triggering OOM with {oom_models[0]}...")
    result = subprocess.run(
        ["bash", "/scripts/run_single_bench.sh", oom_model, "llama.cpp", "12", "2048", "recovery_oom"],
        capture_output=True, text=True, timeout=300
    )
    oom_exit = result.returncode

    # Step 2: Wait briefly, then try loading a working model
    time.sleep(5)
    print(f"Step 2: Recovery — loading {fit_models[0]}...")
    start = time.time()
    result = subprocess.run(
        ["bash", "/scripts/run_single_bench.sh", fit_model, "llama.cpp", "12", "2048", "recovery_fit"],
        capture_output=True, text=True, timeout=300
    )
    recovery_time = time.time() - start

    results["tests"].append({
        "name": "oom_recovery",
        "oom_model": oom_models[0],
        "fit_model": fit_models[0],
        "oom_exit_code": oom_exit,
        "recovery_exit_code": result.returncode,
        "recovery_time_sec": round(recovery_time, 2),
        "recovered": result.returncode == 0
    })
else:
    results["tests"].append({"name": "oom_recovery", "skipped": True, "reason": "no OOM/FIT pair found"})

# Test 2: Burst test — run 3 quick inferences back-to-back with no cooldown
if fit_models:
    fit_model = f"/models/{fit_models[0]}"
    burst_times = []
    print(f"Burst test: 3 rapid inferences with {fit_models[0]}...")
    for i in range(3):
        start = time.time()
        result = subprocess.run(
            ["llama-cli", "-m", fit_model, "--ctx-size", "2048",
             "--threads", str(os.cpu_count()), "--no-mmap", "--single-turn",
             "--prompt", "What is 2+2?", "--n-predict", "50", "--log-disable"],
            capture_output=True, text=True, timeout=120
        )
        elapsed = time.time() - start
        burst_times.append(round(elapsed, 2))

    results["tests"].append({
        "name": "burst_3x",
        "model": fit_models[0],
        "times_sec": burst_times,
        "first_vs_third_ratio": round(burst_times[2] / burst_times[0], 2) if burst_times[0] > 0 else None
    })

# Test 3: Cold start vs warm start
if fit_models:
    fit_model = f"/models/{fit_models[0]}"
    print(f"Cold vs warm start test with {fit_models[0]}...")

    # Cold start (drop caches first)
    subprocess.run(["sync"], check=False)
    with open("/proc/sys/vm/drop_caches", "w") as f:
        f.write("3")
    time.sleep(2)

    cold_start = time.time()
    subprocess.run(
        ["llama-cli", "-m", fit_model, "--ctx-size", "2048",
         "--threads", str(os.cpu_count()), "--no-mmap", "--single-turn",
         "--prompt", "Hello", "--n-predict", "10", "--log-disable"],
        capture_output=True, text=True, timeout=120
    )
    cold_time = time.time() - cold_start

    # Warm start (caches populated)
    warm_start = time.time()
    subprocess.run(
        ["llama-cli", "-m", fit_model, "--ctx-size", "2048",
         "--threads", str(os.cpu_count()), "--no-mmap", "--single-turn",
         "--prompt", "Hello", "--n-predict", "10", "--log-disable"],
        capture_output=True, text=True, timeout=120
    )
    warm_time = time.time() - warm_start

    results["tests"].append({
        "name": "cold_vs_warm",
        "model": fit_models[0],
        "cold_start_sec": round(cold_time, 2),
        "warm_start_sec": round(warm_time, 2),
        "speedup_ratio": round(cold_time / warm_time, 2) if warm_time > 0 else None
    })

print(json.dumps(results, indent=2))
PYEOF

TOTAL_EXPERIMENTS=$((TOTAL_EXPERIMENTS + 1))
COMPLETED=$((COMPLETED + 1))
log_done "Phase 7 recovery & burst tests complete."

# === Final Summary ===
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_HOURS=$(echo "scale=1; $DURATION / 3600" | bc)

log_info "=============================================="
log_info "ORCHESTRATOR COMPLETE — Role: $SERVER_ROLE"
log_info "Duration: ${DURATION_HOURS}h (${DURATION}s)"
log_info "Total: $TOTAL_EXPERIMENTS | Done: $COMPLETED | Failed: $FAILED | Skipped: $SKIPPED"
log_info "=============================================="

stop_heartbeat

update_status "complete" "All done. Total=$TOTAL_EXPERIMENTS Done=$COMPLETED Failed=$FAILED Skipped=$SKIPPED Duration=${DURATION_HOURS}h"

# Final system snapshot
capture_system_snapshot "final_${SERVER_ROLE}"
