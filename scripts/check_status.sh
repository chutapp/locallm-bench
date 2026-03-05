#!/bin/bash
# check_status.sh — Check progress of overnight benchmark run
# Run from your Mac: bash scripts/check_status.sh

SSH_KEY="$HOME/.ssh/your_ssh_key"

SERVERS=(
  "bench-1:YOUR_SERVER_IP"
  "bench-2:YOUR_SERVER_IP"
  "bench-3:YOUR_SERVER_IP"
)

echo "=============================================="
echo "  LocalLM Research — Status Check"
echo "  $(date)"
echo "=============================================="

for entry in "${SERVERS[@]}"; do
  role="${entry%%:*}"
  ip="${entry##*:}"

  echo ""
  echo "--- $role ($ip) ---"

  # Check if server is reachable
  if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$ip "echo ok" 2>/dev/null | grep -q ok; then
    echo "  ⚠ UNREACHABLE (server down or network issue)"
    continue
  fi

  ssh -i "$SSH_KEY" root@$ip bash << 'REMOTE'
    # Status file
    if [ -f /logs/status.json ]; then
      echo "  Status: $(python3 -c "import json; d=json.load(open('/logs/status.json')); print(f'{d[\"status\"]} — {d[\"detail\"]}')" 2>/dev/null || echo "unknown")"
      echo "  Experiments done: $(python3 -c "import json; d=json.load(open('/logs/status.json')); print(d['experiments_done'])" 2>/dev/null || echo "?")"
    else
      echo "  Status: no status file yet"
    fi

    # Orchestrator running?
    if [ -f /logs/orchestrator.pid ] && kill -0 $(cat /logs/orchestrator.pid) 2>/dev/null; then
      echo "  Orchestrator: RUNNING (PID $(cat /logs/orchestrator.pid))"
    else
      echo "  Orchestrator: NOT RUNNING"
    fi

    # Count results
    TOTAL=$(ls /results/*.json 2>/dev/null | wc -l)
    FITS=$(grep -l '"outcome": "FITS"' /results/*.json 2>/dev/null | wc -l)
    OOM=$(grep -l '"outcome": "OOM"' /results/*.json 2>/dev/null | wc -l)
    THRASH=$(grep -l '"outcome": "THRASHES"' /results/*.json 2>/dev/null | wc -l)
    ERR=$(grep -l '"outcome": "ERROR"' /results/*.json 2>/dev/null | wc -l)
    echo "  Results: $TOTAL total | $FITS fits | $OOM oom | $THRASH thrash | $ERR errors"

    # Last log entry
    echo "  Last log: $(tail -1 /logs/bench.log 2>/dev/null || echo 'no logs yet')"

    # Disk space
    echo "  Disk: $(df -h / | awk 'NR==2{print $4}') free"

    # RAM
    echo "  RAM: $(free -h | awk '/Mem:/{print $3}') used / $(free -h | awk '/Mem:/{print $2}') total"
REMOTE
done

echo ""
echo "=============================================="
echo "  Quick commands:"
echo "  Live logs:  ssh -i ~/.ssh/your_ssh_key root@YOUR_SERVER_IP 'tail -20 /logs/bench.log'"
echo "  Collect:    bash scripts/collect_results.sh"
echo "=============================================="
