#!/bin/bash
# launch_all.sh — Deploy scripts and start overnight benchmarks on all servers
# Run from your Mac: bash scripts/launch_all.sh
# Then go to sleep. Check progress with: bash scripts/check_status.sh

set -e

SSH_KEY="$HOME/.ssh/your_ssh_key"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SERVERS=(
  "bench-1:YOUR_SERVER_IP"
  "bench-2:YOUR_SERVER_IP"
  "bench-3:YOUR_SERVER_IP"
)

echo "=============================================="
echo "  LocalLM Research — Launching Overnight Run  "
echo "  $(date)"
echo "=============================================="

# === Step 1: Upload scripts to all servers ===
echo ""
echo ">>> Step 1: Uploading scripts to all servers..."
for entry in "${SERVERS[@]}"; do
  role="${entry%%:*}"
  ip="${entry##*:}"
  echo "  Uploading to $role ($ip)..."
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@$ip "mkdir -p /scripts" 2>/dev/null
  scp -i "$SSH_KEY" -q "$SCRIPT_DIR/lib.sh" root@$ip:/scripts/
  scp -i "$SSH_KEY" -q "$SCRIPT_DIR/download_models.sh" root@$ip:/scripts/
  scp -i "$SSH_KEY" -q "$SCRIPT_DIR/run_single_bench.sh" root@$ip:/scripts/
  scp -i "$SSH_KEY" -q "$SCRIPT_DIR/orchestrator.sh" root@$ip:/scripts/
  scp -i "$SSH_KEY" -q "$SCRIPT_DIR/run_quality_eval.sh" root@$ip:/scripts/
  scp -i "$SSH_KEY" -q "$SCRIPT_DIR/install_extra_engines.sh" root@$ip:/scripts/
  ssh -i "$SSH_KEY" root@$ip "chmod +x /scripts/*.sh" 2>/dev/null
  echo "  ✓ $role ready"
done

# === Step 2: Install missing tools ===
echo ""
echo ">>> Step 2: Installing missing tools (stress, bc, sysstat)..."
for entry in "${SERVERS[@]}"; do
  role="${entry%%:*}"
  ip="${entry##*:}"
  echo "  Installing on $role ($ip)..."
  ssh -i "$SSH_KEY" root@$ip "apt-get install -y -qq stress bc sysstat psutil 2>/dev/null; pip3 install psutil 2>/dev/null || /opt/bench-env/bin/pip install psutil 2>/dev/null; source /opt/bench-env/bin/activate && pip install psutil 2>/dev/null" &
done
wait
echo "  ✓ All tools installed"

# === Step 3: Install extra engines on bench-3 ===
echo ""
echo ">>> Step 3: Installing extra engines on bench-3 (llamafile, bitnet.cpp, PowerInfer, lm-eval)..."
BENCH3_IP="YOUR_SERVER_IP"
ssh -i "$SSH_KEY" root@$BENCH3_IP "nohup bash /scripts/install_extra_engines.sh > /logs/install_extra.log 2>&1" &
INSTALL_PID=$!
echo "  Installing in background (PID $INSTALL_PID)..."
echo "  Waiting for install to complete (may take 10-15 minutes)..."
wait $INSTALL_PID 2>/dev/null
echo "  ✓ Extra engines installation attempted on bench-3"

# === Step 4: Start benchmarks on all servers ===
echo ""
echo ">>> Step 4: Starting orchestrator on all servers..."
for entry in "${SERVERS[@]}"; do
  role="${entry%%:*}"
  ip="${entry##*:}"
  echo "  Starting $role ($ip)..."
  ssh -i "$SSH_KEY" root@$ip "
    mkdir -p /logs /results /metrics /models
    # Kill any previous run
    pkill -f orchestrator.sh 2>/dev/null || true
    sleep 1
    # Start in background with nohup
    nohup bash /scripts/orchestrator.sh $role > /logs/orchestrator_stdout.log 2>&1 &
    echo \"PID: \$!\"
    echo \$! > /logs/orchestrator.pid
  "
  echo "  ✓ $role started"
done

echo ""
echo "=============================================="
echo "  ALL SERVERS RUNNING"
echo "=============================================="
echo ""
echo "Experiments running in background on 3 servers."
echo "Estimated completion: ~14 hours"
echo ""
echo "Monitor progress:"
echo "  bash scripts/check_status.sh"
echo ""
echo "View live logs:"
echo "  ssh -i ~/.ssh/your_ssh_key root@YOUR_SERVER_IP 'tail -f /logs/bench.log'"
echo "  ssh -i ~/.ssh/your_ssh_key root@YOUR_SERVER_IP 'tail -f /logs/bench.log'"
echo "  ssh -i ~/.ssh/your_ssh_key root@YOUR_SERVER_IP 'tail -f /logs/bench.log'"
echo ""
echo "Collect results when done:"
echo "  bash scripts/collect_results.sh"
echo ""
