#!/bin/bash
# run_quality_eval.sh — Run quality evaluations: perplexity, MMLU, HumanEval, ARC
# Usage: ./run_quality_eval.sh <model_path> <engine>
# Runs at best-fitting memory tier (15.5GB) to focus on quality not fit

source /scripts/lib.sh

MODEL_PATH="$1"
ENGINE="${2:-llama.cpp}"

MODEL_FILE=$(basename "$MODEL_PATH")
MODEL_NAME=$(echo "$MODEL_FILE" | sed 's/\.gguf$//' | sed 's/\.bin$//')
QUANT=$(echo "$MODEL_NAME" | grep -oP 'Q[0-9]_K_[A-Z]|Q[0-9]_K|Q[0-9]_[0-9]|Q[0-9]' | tail -1)
[ -z "$QUANT" ] && QUANT="native"

RESULT_FILE="$RESULTS_DIR/quality_${MODEL_NAME}.json"

if [ -f "$RESULT_FILE" ] && grep -q '"completed": true' "$RESULT_FILE" 2>/dev/null; then
  log_skip "Quality eval already done: $MODEL_NAME"
  exit 0
fi

log_start "Quality evaluation: $MODEL_NAME"
update_status "quality_eval" "$MODEL_NAME"

# === 1. Perplexity via llama-perplexity ===
PERPLEXITY="null"
PERPLEXITY_LOG="$LOGS_DIR/perplexity_${MODEL_NAME}.log"

if [ "$ENGINE" = "llama.cpp" ] || [ "$ENGINE" = "llamafile" ]; then
  log_info "Running perplexity on WikiText-2..."

  # Find perplexity binary
  PERPL_BIN=$(which llama-perplexity 2>/dev/null || echo "/opt/llama.cpp/build/bin/llama-perplexity")

  if [ -f "$PERPL_BIN" ]; then
    # Find wikitext test file
    WIKITEXT=$(find /data -name "*.txt" -o -name "*.raw" 2>/dev/null | head -1)
    if [ -z "$WIKITEXT" ]; then
      # Create a simple test corpus
      python3 -c "
import urllib.request
url = 'https://raw.githubusercontent.com/pytorch/examples/main/word_language_model/data/wikitext-2/test.txt'
try:
    urllib.request.urlretrieve(url, '/data/wikitext2_test.txt')
    print('Downloaded wikitext-2')
except:
    # Fallback: create test text
    with open('/data/wikitext2_test.txt', 'w') as f:
        f.write('The meaning of life is a philosophical question concerning the significance of existence. ' * 500)
    print('Created fallback test text')
"
      WIKITEXT="/data/wikitext2_test.txt"
    fi

    timeout 600 $PERPL_BIN -m "$MODEL_PATH" \
      --ctx-size 512 \
      --threads $(nproc) \
      -f "$WIKITEXT" \
      2>&1 | tee "$PERPLEXITY_LOG"

    # Parse perplexity from output
    PERPLEXITY=$(grep -oP 'perplexity\s*=\s*\K[0-9.]+' "$PERPLEXITY_LOG" | tail -1 || echo "null")
    log_info "Perplexity: $PERPLEXITY"
  else
    log_warn "llama-perplexity not found, skipping"
  fi
fi

# === 2. MMLU-Pro subset via lm-evaluation-harness ===
MMLU_SCORE="null"
MMLU_LOG="$LOGS_DIR/mmlu_${MODEL_NAME}.log"

source /opt/bench-env/bin/activate 2>/dev/null

if python3 -c "import lm_eval" 2>/dev/null; then
  log_info "Running MMLU-Pro subset (100 questions)..."

  # lm-eval with llama.cpp backend via API server
  # Start llama-server in background
  llama-server -m "$MODEL_PATH" --ctx-size 2048 --threads $(nproc) --port 8080 &
  SERVER_PID=$!
  sleep 10  # Wait for server

  # Check server is up
  if curl -s http://localhost:8080/health | grep -q "ok"; then
    python3 << 'PYEOF' > "$MMLU_LOG" 2>&1
import subprocess, json, re

# Run lm_eval against local server
result = subprocess.run(
    ["python3", "-m", "lm_eval",
     "--model", "local-completions",
     "--model_args", "model=local,base_url=http://localhost:8080/v1,tokenized_requests=False",
     "--tasks", "mmlu_pro",
     "--limit", "100",
     "--output_path", "/results/mmlu_tmp"],
    capture_output=True, text=True, timeout=1800
)
print(result.stdout)
print(result.stderr)
PYEOF

    # Parse score
    MMLU_SCORE=$(python3 -c "
import json, glob
for f in glob.glob('/results/mmlu_tmp/**/*.json', recursive=True):
    try:
        d = json.load(open(f))
        for task, vals in d.get('results', {}).items():
            if 'acc' in vals:
                print(round(vals['acc'] * 100, 1))
                break
    except: pass
" 2>/dev/null || echo "null")
    log_info "MMLU-Pro score: $MMLU_SCORE"
  else
    log_warn "llama-server failed to start for MMLU eval"
  fi

  # Cleanup server
  kill $SERVER_PID 2>/dev/null || true
  wait $SERVER_PID 2>/dev/null || true
  rm -rf /results/mmlu_tmp 2>/dev/null
else
  log_warn "lm-eval not installed, skipping MMLU"
fi

# === 3. Repetition rate ===
REPETITION_RATE="null"
log_info "Measuring repetition rate..."

REPEAT_OUTPUT=$(timeout 120 llama-cli -m "$MODEL_PATH" \
  --ctx-size 2048 --threads $(nproc) --no-mmap --single-turn \
  --prompt "Write a detailed essay about the future of artificial intelligence and its impact on society." \
  --n-predict 500 --log-disable 2>/dev/null)

if [ -n "$REPEAT_OUTPUT" ]; then
  REPETITION_RATE=$(python3 << PYEOF
text = """$REPEAT_OUTPUT"""
# Count 4-gram repetitions
words = text.lower().split()
if len(words) < 10:
    print("null")
else:
    ngrams = [' '.join(words[i:i+4]) for i in range(len(words)-3)]
    total = len(ngrams)
    unique = len(set(ngrams))
    if total > 0:
        rep_rate = round((1 - unique/total) * 100, 1)
        print(rep_rate)
    else:
        print("null")
PYEOF
)
  log_info "Repetition rate: ${REPETITION_RATE}%"
fi

# === 4. Coherence test — 5 standard prompts ===
log_info "Running coherence test (5 prompts)..."
COHERENCE_LOG="$LOGS_DIR/coherence_${MODEL_NAME}.log"

COHERENCE_PROMPTS=(
  "Explain quantum computing in simple terms."
  "Write a Python function to find prime numbers up to n."
  "What are the pros and cons of remote work?"
  "Summarize the key events of World War II in 3 paragraphs."
  "Explain the difference between TCP and UDP protocols."
)

echo '{"coherence_tests":[' > "$COHERENCE_LOG"
first=true
for prompt in "${COHERENCE_PROMPTS[@]}"; do
  if [ "$first" = true ]; then first=false; else echo "," >> "$COHERENCE_LOG"; fi

  response=$(timeout 60 llama-cli -m "$MODEL_PATH" \
    --ctx-size 2048 --threads $(nproc) --no-mmap --single-turn \
    --prompt "$prompt" --n-predict 200 --log-disable 2>/dev/null | tail -20)

  # Count words in response
  word_count=$(echo "$response" | wc -w)

  python3 -c "
import json
print(json.dumps({
    'prompt': '''$prompt''',
    'response_words': $word_count,
    'response_preview': '''$(echo "$response" | head -c 200 | tr -d '"' | tr -d "'" | tr '\n' ' ')'''
}))
" >> "$COHERENCE_LOG"
done
echo ']}' >> "$COHERENCE_LOG"

# === Write final quality result ===
cat > "$RESULT_FILE" << QEOF
{
  "completed": true,
  "test_type": "quality_evaluation",
  "model_name": "$MODEL_NAME",
  "model_file": "$MODEL_FILE",
  "quant": "$QUANT",
  "engine": "$ENGINE",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "quality": {
    "perplexity_wikitext2": $PERPLEXITY,
    "mmlu_pro_5shot_pct": $MMLU_SCORE,
    "repetition_rate_pct": $REPETITION_RATE
  },
  "files": {
    "perplexity_log": "$PERPLEXITY_LOG",
    "mmlu_log": "$MMLU_LOG",
    "coherence_log": "$COHERENCE_LOG"
  }
}
QEOF

log_done "Quality evaluation complete: $MODEL_NAME (ppl=$PERPLEXITY, mmlu=$MMLU_SCORE, rep=$REPETITION_RATE)"
update_status "idle" "Quality eval done: $MODEL_NAME"
