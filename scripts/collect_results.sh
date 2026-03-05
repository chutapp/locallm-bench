#!/bin/bash
# collect_results.sh — Download all results + logs from all servers to local machine
# Run from your Mac: bash scripts/collect_results.sh

SSH_KEY="$HOME/.ssh/your_ssh_key"
LOCAL_DIR="."

SERVERS=(
  "bench-1:YOUR_SERVER_IP"
  "bench-2:YOUR_SERVER_IP"
  "bench-3:YOUR_SERVER_IP"
)

echo "=============================================="
echo "  Collecting results from all servers"
echo "  $(date)"
echo "=============================================="

mkdir -p "$LOCAL_DIR/results"
mkdir -p "$LOCAL_DIR/logs"
mkdir -p "$LOCAL_DIR/metrics"

for entry in "${SERVERS[@]}"; do
  role="${entry%%:*}"
  ip="${entry##*:}"

  echo ""
  echo "--- Downloading from $role ($ip) ---"

  # Results
  mkdir -p "$LOCAL_DIR/results/$role"
  scp -i "$SSH_KEY" -r root@$ip:/results/* "$LOCAL_DIR/results/$role/" 2>/dev/null
  echo "  Results: $(ls "$LOCAL_DIR/results/$role/"*.json 2>/dev/null | wc -l) files"

  # Logs
  mkdir -p "$LOCAL_DIR/logs/$role"
  scp -i "$SSH_KEY" -r root@$ip:/logs/* "$LOCAL_DIR/logs/$role/" 2>/dev/null
  echo "  Logs: $(ls "$LOCAL_DIR/logs/$role/"* 2>/dev/null | wc -l) files"

  # Metrics
  mkdir -p "$LOCAL_DIR/metrics/$role"
  scp -i "$SSH_KEY" -r root@$ip:/metrics/* "$LOCAL_DIR/metrics/$role/" 2>/dev/null
  echo "  Metrics: $(ls "$LOCAL_DIR/metrics/$role/"* 2>/dev/null | wc -l) files"
done

# Combine all results into one file
echo ""
echo "--- Combining results ---"
find "$LOCAL_DIR/results" -name "*.json" -type f | while read f; do
  cat "$f"
  echo ""
done | python3 -c "
import sys, json

results = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        results.append(json.loads(line))
    except:
        pass

# Sort by outcome then tok/s
results.sort(key=lambda x: (
    0 if x.get('outcome') == 'FITS' else 1 if x.get('outcome') == 'THRASHES' else 2,
    -(x.get('speed', {}).get('tokens_per_sec_generation', 0))
))

with open('$LOCAL_DIR/results/ALL_RESULTS.json', 'w') as f:
    json.dump(results, f, indent=2)

print(f'Combined {len(results)} results into ALL_RESULTS.json')

# Quick summary
fits = sum(1 for r in results if r.get('outcome') == 'FITS')
oom = sum(1 for r in results if r.get('outcome') == 'OOM')
thrash = sum(1 for r in results if r.get('outcome') == 'THRASHES')
errors = sum(1 for r in results if r.get('outcome') in ('ERROR', 'UNKNOWN'))
print(f'FITS: {fits} | OOM: {oom} | THRASH: {thrash} | ERROR: {errors}')
" 2>/dev/null

echo ""
echo "=============================================="
echo "  All results saved to: $LOCAL_DIR/results/"
echo "  Combined file: $LOCAL_DIR/results/ALL_RESULTS.json"
echo "  Logs: $LOCAL_DIR/logs/"
echo "=============================================="
