#!/bin/bash
# download_models.sh — Download assigned models for this server
# Usage: ./download_models.sh <server_role>
# Strategy: Download ALL models upfront that fit on disk.
# Q8_0 for 30B+ models is dropped (33GB file > 16GB RAM = guaranteed OOM, not useful data)
# Ollama pulls are skipped — we import GGUF files into Ollama instead.

source /scripts/lib.sh

SERVER_ROLE="${1:-unknown}"
log_info "Starting model downloads for role: $SERVER_ROLE"

download_gguf() {
  local repo="$1"
  local filename="$2"           # local filename to save as
  local remote_name="${3:-$2}"   # remote filename on HF (defaults to same as local)
  local output_path="$MODELS_DIR/$filename"

  if [ -f "$output_path" ]; then
    log_skip "Already exists: $filename"
    return 0
  fi

  # Check disk space before downloading (need at least 20GB free)
  local free_gb=$(df -BG /models | awk 'NR==2{print int($4)}')
  if [ "$free_gb" -lt 20 ]; then
    log_warn "Low disk space (${free_gb}GB free), skipping: $filename"
    return 1
  fi

  log_start "Downloading $filename from $repo (${free_gb}GB free)"
  update_status "downloading" "$filename"

  local url="https://huggingface.co/${repo}/resolve/main/${remote_name}"

  retry 3 30 wget -q --show-progress -c -O "$output_path.tmp" "$url"
  if [ $? -eq 0 ] && [ -f "$output_path.tmp" ]; then
    # Verify file is not empty or tiny (failed download)
    local size_bytes=$(stat -c%s "$output_path.tmp" 2>/dev/null || stat -f%z "$output_path.tmp" 2>/dev/null)
    if [ "$size_bytes" -lt 1000000 ]; then
      log_fail "Download too small (${size_bytes} bytes), likely failed: $filename"
      rm -f "$output_path.tmp"
      return 1
    fi
    mv "$output_path.tmp" "$output_path"
    local size=$(du -h "$output_path" | awk '{print $1}')
    log_done "Downloaded $filename ($size)"
  else
    log_fail "Failed to download $filename"
    rm -f "$output_path.tmp"
    return 1
  fi
}

# ===================================================================
# MODEL ASSIGNMENTS PER SERVER
# Disk budget: ~130GB usable per server
# Strategy: Q2_K + Q3_K_M + Q4_K_M + Q5_K_M (skip Q8_0 for 30B+ — too big)
# ===================================================================

case "$SERVER_ROLE" in
  bench-1)
    log_info "=== bench-1: Qwen3.5-35B-A3B + Llama 4 Scout ==="
    # Disk estimate: 12+14+17+19 = 62GB (Qwen) + 35GB (Scout) = 97GB — fits

    # Qwen3.5-35B-A3B (MoE: 35B total, 3B active) — latest Feb 2026
    download_gguf "bartowski/Qwen_Qwen3.5-35B-A3B-GGUF" "Qwen3.5-35B-A3B-Q2_K.gguf" "Qwen_Qwen3.5-35B-A3B-Q2_K.gguf"
    download_gguf "bartowski/Qwen_Qwen3.5-35B-A3B-GGUF" "Qwen3.5-35B-A3B-Q3_K_M.gguf" "Qwen_Qwen3.5-35B-A3B-Q3_K_M.gguf"
    download_gguf "bartowski/Qwen_Qwen3.5-35B-A3B-GGUF" "Qwen3.5-35B-A3B-Q4_K_M.gguf" "Qwen_Qwen3.5-35B-A3B-Q4_K_M.gguf"
    download_gguf "bartowski/Qwen_Qwen3.5-35B-A3B-GGUF" "Qwen3.5-35B-A3B-Q5_K_M.gguf" "Qwen_Qwen3.5-35B-A3B-Q5_K_M.gguf"
    # Q8_0 SKIPPED — 33GB file, guaranteed OOM at 16GB RAM

    # Llama 4 Scout (MoE: 109B/17B active) — IQ1_M is 35GB, will OOM but proves boundary
    download_gguf "unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF" "Llama-4-Scout-17B-16E-Instruct-UD-IQ1_M.gguf"
    ;;

  bench-2)
    log_info "=== bench-2: GLM-4.7-Flash + Nemotron-3-Nano + Ministral-3-14B ==="
    # Disk estimate: 61GB (GLM) + 35GB (Nemotron Q2+Q3 only) + 30GB (Ministral) = 126GB — fits 138GB usable

    # GLM-4.7-Flash (MoE)
    download_gguf "bartowski/zai-org_GLM-4.7-Flash-GGUF" "GLM-4.7-Flash-Q2_K.gguf" "zai-org_GLM-4.7-Flash-Q2_K.gguf"
    download_gguf "bartowski/zai-org_GLM-4.7-Flash-GGUF" "GLM-4.7-Flash-Q3_K_M.gguf" "zai-org_GLM-4.7-Flash-Q3_K_M.gguf"
    download_gguf "bartowski/zai-org_GLM-4.7-Flash-GGUF" "GLM-4.7-Flash-Q4_K_M.gguf" "zai-org_GLM-4.7-Flash-Q4_K_M.gguf"
    download_gguf "bartowski/zai-org_GLM-4.7-Flash-GGUF" "GLM-4.7-Flash-Q5_K_M.gguf" "zai-org_GLM-4.7-Flash-Q5_K_M.gguf"
    # Q8_0 SKIPPED

    # Nemotron-3-Nano-30B-A3B (hybrid Mamba-2 + MoE)
    # Only Q2_K + Q3_K_M — Q4_K_M (23G) and Q5_K_M (24G) dropped to fit 138GB usable disk
    download_gguf "bartowski/nvidia_Nemotron-3-Nano-30B-A3B-GGUF" "Nemotron-3-Nano-30B-A3B-Q2_K.gguf" "nvidia_Nemotron-3-Nano-30B-A3B-Q2_K.gguf"
    download_gguf "bartowski/nvidia_Nemotron-3-Nano-30B-A3B-GGUF" "Nemotron-3-Nano-30B-A3B-Q3_K_M.gguf" "nvidia_Nemotron-3-Nano-30B-A3B-Q3_K_M.gguf"

    # Ministral-3-14B-Reasoning (dense control — only Q4/Q5/Q8 available)
    download_gguf "mistralai/Ministral-3-14B-Reasoning-2512-GGUF" "Ministral-3-14B-Reasoning-2512-Q4_K_M.gguf"
    download_gguf "mistralai/Ministral-3-14B-Reasoning-2512-GGUF" "Ministral-3-14B-Reasoning-2512-Q5_K_M.gguf"
    download_gguf "mistralai/Ministral-3-14B-Reasoning-2512-GGUF" "Ministral-3-14B-Reasoning-2512-Q8_0.gguf"
    ;;

  bench-3)
    log_info "=== bench-3: Dense models + Ternary/Hybrid ==="
    # Disk estimate: ~40GB (Gemma) + ~35GB (Mistral) + ~40GB (DeepSeek) + ~10GB (Falcon) + 1GB (BitNet) = 126GB — fits

    # Gemma-3-27B (dense)
    download_gguf "bartowski/google_gemma-3-27b-it-GGUF" "gemma-3-27b-it-Q2_K.gguf" "google_gemma-3-27b-it-Q2_K.gguf"
    download_gguf "bartowski/google_gemma-3-27b-it-GGUF" "gemma-3-27b-it-Q3_K_M.gguf" "google_gemma-3-27b-it-Q3_K_M.gguf"
    download_gguf "bartowski/google_gemma-3-27b-it-GGUF" "gemma-3-27b-it-Q4_K_M.gguf" "google_gemma-3-27b-it-Q4_K_M.gguf"

    # Mistral-Small-24B (dense)
    download_gguf "bartowski/Mistral-Small-24B-Instruct-2501-GGUF" "Mistral-Small-24B-Instruct-2501-Q2_K.gguf"
    download_gguf "bartowski/Mistral-Small-24B-Instruct-2501-GGUF" "Mistral-Small-24B-Instruct-2501-Q3_K_M.gguf"
    download_gguf "bartowski/Mistral-Small-24B-Instruct-2501-GGUF" "Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf"

    # DeepSeek-R1-Distill-Qwen-32B (dense reasoning)
    download_gguf "bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF" "DeepSeek-R1-Distill-Qwen-32B-Q2_K.gguf"
    download_gguf "bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF" "DeepSeek-R1-Distill-Qwen-32B-Q3_K_M.gguf"
    download_gguf "bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF" "DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf"

    # Falcon-H1R-7B (hybrid Mamba-Transformer, Jan 2026)
    download_gguf "tiiuae/Falcon-H1R-7B-GGUF" "Falcon-H1R-7B-Q4_K_M.gguf"
    download_gguf "tiiuae/Falcon-H1R-7B-GGUF" "Falcon-H1R-7B-Q8_0.gguf"

    # BitNet b1.58 2B4T (ternary, ~0.4GB)
    if [ ! -d "$MODELS_DIR/bitnet-b1.58-2B-4T" ]; then
      log_start "Downloading BitNet b1.58-2B-4T..."
      source /opt/bench-env/bin/activate 2>/dev/null
      python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('microsoft/bitnet-b1.58-2B-4T', local_dir='$MODELS_DIR/bitnet-b1.58-2B-4T')
print('BitNet 2B4T downloaded')
" 2>&1 | tail -5 || log_warn "BitNet 2B4T download failed"
    else
      log_skip "BitNet b1.58-2B-4T already exists"
    fi
    ;;

  *)
    log_error "Unknown server role: $SERVER_ROLE"
    exit 1
    ;;
esac

log_done "All model downloads complete for $SERVER_ROLE"
update_status "downloads_complete" "All models downloaded"

# Report disk usage
log_info "Disk usage after downloads:"
du -sh $MODELS_DIR 2>/dev/null
df -h / | awk 'NR==2{print "  Free:", $4, "of", $2}'
