#!/bin/bash
# lib.sh — Shared functions for all benchmark scripts
# Source this in every script: source /scripts/lib.sh

set -o pipefail

# === Directories ===
MODELS_DIR="/models"
RESULTS_DIR="/results"
LOGS_DIR="/logs"
METRICS_DIR="/metrics"
mkdir -p "$MODELS_DIR" "$RESULTS_DIR" "$LOGS_DIR" "$METRICS_DIR"

# === Server identity ===
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_NAME=$(hostname)

# === Logging ===
log() {
  local level="$1"; shift
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$level] [$SERVER_NAME] $*" | tee -a "$LOGS_DIR/bench.log"
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }
log_start() { log "START" "$@"; }
log_done()  { log "DONE"  "$@"; }
log_skip()  { log "SKIP"  "$@"; }
log_fail()  { log "FAIL"  "$@"; }
log_oom()   { log "OOM"   "$@"; }

# === Retry logic ===
retry() {
  local max_attempts="$1"; shift
  local delay="$1"; shift
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if "$@" 2>&1; then
      return 0
    fi
    log_warn "Attempt $attempt/$max_attempts failed: $*"
    attempt=$((attempt + 1))
    [ $attempt -le $max_attempts ] && sleep "$delay"
  done
  log_error "All $max_attempts attempts failed: $*"
  return 1
}

# === Memory enforcement ===
# Uses systemd-run to cap memory. Process gets killed if it exceeds.
run_with_memory_limit() {
  local limit_gb="$1"; shift
  systemd-run --scope -p MemoryMax="${limit_gb}G" -p MemorySwapMax=0 --quiet "$@"
}

# === System snapshot ===
# Captures full system state at a point in time
capture_system_snapshot() {
  local label="$1"
  local output_file="$METRICS_DIR/snapshot_${label}_$(date +%s).json"
  # Use /proc directly — no psutil dependency
  python3 << 'PYEOF' > "$output_file" 2>/dev/null || echo '{"error":"snapshot failed"}' > "$output_file"
import json, time, os

def read_file(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except:
        return ""

# Memory from /proc/meminfo
meminfo = {}
for line in read_file("/proc/meminfo").split("\n"):
    parts = line.split()
    if len(parts) >= 2:
        meminfo[parts[0].rstrip(":")] = int(parts[1]) // 1024  # KB to MB

# Load average
loadavg = read_file("/proc/loadavg").split()

snapshot = {
    "label": os.environ.get("SNAP_LABEL", "unknown"),
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "memory": {
        "total_mb": meminfo.get("MemTotal", 0),
        "available_mb": meminfo.get("MemAvailable", 0),
        "used_mb": meminfo.get("MemTotal", 0) - meminfo.get("MemAvailable", 0),
        "buffers_mb": meminfo.get("Buffers", 0),
        "cached_mb": meminfo.get("Cached", 0)
    },
    "cpu": {
        "load_avg_1m": float(loadavg[0]) if loadavg else 0,
        "load_avg_5m": float(loadavg[1]) if len(loadavg) > 1 else 0
    }
}
print(json.dumps(snapshot, indent=2))
PYEOF
  echo "$output_file"
}

# === Process monitoring ===
# Runs in background, samples PID metrics every N seconds
monitor_process() {
  local pid="$1"
  local interval="$2"
  local output_file="$3"

  echo '{"samples":[' > "$output_file"
  local first=true

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$first" = true ]; then first=false; else echo "," >> "$output_file"; fi
    python3 << PYEOF >> "$output_file"
import json, time, os

pid = $pid
try:
    with open(f"/proc/{pid}/status") as f:
        status = f.read()
    with open(f"/proc/{pid}/stat") as f:
        stat = f.read().split()

    def get_field(text, field):
        for line in text.split('\n'):
            if line.startswith(field):
                return line.split(':')[1].strip().split()[0]
        return "0"

    rss_kb = int(get_field(status, "VmRSS"))
    peak_kb = int(get_field(status, "VmPeak"))
    vm_size_kb = int(get_field(status, "VmSize"))
    threads = int(get_field(status, "Threads"))
    major_faults = int(stat[11])
    minor_faults = int(stat[9])

    sample = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "epoch": time.time(),
        "rss_mb": rss_kb // 1024,
        "peak_mb": peak_kb // 1024,
        "vm_size_mb": vm_size_kb // 1024,
        "threads": threads,
        "major_page_faults": major_faults,
        "minor_page_faults": minor_faults
    }
    print(json.dumps(sample))
except Exception as e:
    print(json.dumps({"error": str(e), "epoch": time.time()}))
PYEOF
    sleep "$interval"
  done

  echo '],"pid":'$pid'}' >> "$output_file"
}

# === Disk I/O monitoring ===
monitor_disk_io() {
  local duration="$1"
  local interval="$2"
  local output_file="$3"
  iostat -x -d "$interval" "$((duration / interval))" -o JSON > "$output_file" 2>/dev/null || \
    iostat -x -d "$interval" "$((duration / interval))" > "$output_file" 2>/dev/null || \
    echo '{"error":"iostat not available"}' > "$output_file"
}

# === OOM detection ===
check_oom() {
  local since="$1"  # timestamp
  dmesg --since "$since" 2>/dev/null | grep -i "oom\|killed process\|out of memory" || true
}

# === Result file naming ===
result_filename() {
  local model="$1"
  local quant="$2"
  local engine="$3"
  local tier="$4"
  local test_type="$5"
  # Sanitize
  local safe_model=$(echo "$model" | tr '/' '_' | tr ' ' '_')
  echo "${test_type}_${safe_model}_${quant}_${engine}_${tier}GB"
}

# === Status file (for remote monitoring) ===
update_status() {
  local status="$1"
  local detail="$2"
  cat > "$LOGS_DIR/status.json" << STATUSEOF
{
  "server": "$SERVER_NAME",
  "ip": "$SERVER_IP",
  "status": "$status",
  "detail": "$detail",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "experiments_done": $(ls "$RESULTS_DIR"/*.json 2>/dev/null | wc -l),
  "experiments_failed": $(grep -c '\[FAIL\]\|\[OOM\]' "$LOGS_DIR/bench.log" 2>/dev/null || echo 0),
  "uptime": "$(uptime -p 2>/dev/null || uptime)"
}
STATUSEOF
}

# === Heartbeat (background) ===
start_heartbeat() {
  while true; do
    update_status "running" "heartbeat"
    sleep 60
  done &
  HEARTBEAT_PID=$!
  echo "$HEARTBEAT_PID" > "$LOGS_DIR/heartbeat.pid"
}

stop_heartbeat() {
  [ -f "$LOGS_DIR/heartbeat.pid" ] && kill "$(cat $LOGS_DIR/heartbeat.pid)" 2>/dev/null || true
}

log_info "lib.sh loaded"
