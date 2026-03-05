# Server Setup Guide

How to provision and configure a benchmark server from scratch.

## Requirements

- Any x86_64 Linux server with 16GB RAM
- No swap (we want honest OOM behavior)
- Ubuntu 22.04+ or Debian 12+
- Root access
- ~160GB disk (models are large)

## Cloud Provider Options

Any provider with 16GB dedicated-CPU VPS works. We used Hetzner:

| Provider | Instance Type | Specs | Approx. Cost |
|----------|--------------|-------|-------------|
| Hetzner | CCX23 | 4 dedicated cores, 16GB | EUR 0.038/hr |
| DigitalOcean | c-4-16gib | 4 dedicated cores, 16GB | $0.089/hr |
| AWS | c6a.xlarge | 4 vCPUs, 8GB (needs c6a.2xlarge for 16GB) | $0.153/hr |
| Vultr | Dedicated CPU | 4 cores, 16GB | $0.060/hr |

## Provisioning

### 1. Create the server

```bash
# Hetzner example
hcloud server create \
  --name locallm-bench \
  --type ccx23 \
  --image ubuntu-24.04 \
  --ssh-key your-key-name \
  --location nbg1
```

### 2. Disable swap

```bash
ssh root@YOUR_IP

# Check if swap exists
swapon --show

# If it does, disable it
swapoff -a
sed -i '/swap/d' /etc/fstab
```

### 3. Install dependencies

```bash
apt update && apt install -y \
  build-essential cmake git wget curl \
  python3 python3-pip python3-venv \
  htop iotop sysstat stress-ng \
  jq bc
```

### 4. Build llama.cpp from source

```bash
cd /opt
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# Install binaries
cp build/bin/llama-cli /usr/local/bin/
cp build/bin/llama-bench /usr/local/bin/
cp build/bin/llama-server /usr/local/bin/
cp build/bin/llama-quantize /usr/local/bin/
cp build/bin/llama-perplexity /usr/local/bin/
```

### 5. Set up Python environment

```bash
python3 -m venv /opt/bench-env
source /opt/bench-env/bin/activate
pip install huggingface-hub
```

### 6. Create directories

```bash
mkdir -p /models /results /logs /scripts
```

### 7. Download models

```bash
source /opt/bench-env/bin/activate

# Example: GLM-4.7-Flash at various quantizations
huggingface-cli download bartowski/GLM-4.7-Flash-GGUF \
  GLM-4.7-Flash-Q2_K.gguf --local-dir /models/ --resume-download

huggingface-cli download bartowski/GLM-4.7-Flash-GGUF \
  GLM-4.7-Flash-Q3_K_M.gguf --local-dir /models/ --resume-download

# See scripts/download_models.sh for the full list
```

### 8. Upload and run scripts

```bash
# From your local machine
scp -r scripts/ root@YOUR_IP:/scripts/

# On the server
chmod +x /scripts/*.sh
nohup bash /scripts/orchestrator.sh bench-1 >> /logs/orchestrator.log 2>&1 &
```

## Monitoring

```bash
# Check progress
cat /logs/status.json | python3 -m json.tool

# Live logs
tail -f /logs/bench.log

# System resources
htop
iostat -x 1
```

## Cost Management

Shut down servers when not benchmarking. Disk storage costs are negligible; CPU hours are what adds up.

```bash
# From your local machine
hcloud server shutdown locallm-bench
# Start again later
hcloud server poweron locallm-bench
```
