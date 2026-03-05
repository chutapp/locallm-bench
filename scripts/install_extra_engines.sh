#!/bin/bash
# install_extra_engines.sh — Install llamafile, bitnet.cpp, PowerInfer, lm-evaluation-harness
# Run on bench-3 (or any server that needs these)
set -e

echo "=== Installing extra engines ==="

# === 1. llamafile ===
echo ">>> Installing llamafile..."
mkdir -p /opt/llamafile
cd /opt/llamafile

# Download latest llamafile binary
LLAMAFILE_VERSION="0.9.3"
wget -q --show-progress -c "https://github.com/Mozilla-Ocho/llamafile/releases/download/${LLAMAFILE_VERSION}/llamafile-${LLAMAFILE_VERSION}" -O llamafile || \
wget -q --show-progress -c "https://github.com/mozilla-ai/llamafile/releases/latest/download/llamafile" -O llamafile || \
  echo "WARNING: llamafile download failed — will try alternate URL"

if [ -f llamafile ]; then
  chmod +x llamafile
  ln -sf /opt/llamafile/llamafile /usr/local/bin/llamafile
  echo "llamafile installed: $(llamafile --version 2>&1 | head -1 || echo 'binary ready')"
else
  echo "ERROR: llamafile not installed"
fi

# === 2. bitnet.cpp ===
echo ">>> Installing bitnet.cpp..."
cd /opt
if [ ! -d "BitNet" ]; then
  git clone --depth 1 https://github.com/microsoft/BitNet.git
fi
cd BitNet

# Install Python deps
source /opt/bench-env/bin/activate
pip install -q -r requirements.txt 2>/dev/null || pip install -q torch numpy 2>/dev/null

# Build
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release 2>/dev/null || cmake .. 2>/dev/null
cmake --build . --config Release -j$(nproc) 2>&1 | tail -5

if [ -f bin/llama-cli ]; then
  echo "bitnet.cpp installed: bin/llama-cli exists"
else
  # Try the python-based setup
  cd /opt/BitNet
  python setup_env.py --hf-repo microsoft/bitnet-b1.58-2B-4T -q i2_s 2>&1 | tail -5 || echo "WARNING: bitnet setup_env failed"
fi

# === 3. PowerInfer ===
echo ">>> Installing PowerInfer..."
cd /opt
if [ ! -d "PowerInfer" ]; then
  git clone --depth 1 https://github.com/SJTU-IPADS/PowerInfer.git
fi
cd PowerInfer

# Build PowerInfer (it's a fork of llama.cpp)
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release 2>/dev/null
cmake --build . --config Release -j$(nproc) 2>&1 | tail -5

if [ -f bin/main ]; then
  echo "PowerInfer installed: bin/main exists"
  ln -sf /opt/PowerInfer/build/bin/main /usr/local/bin/powerinfer
else
  echo "WARNING: PowerInfer build may have failed — checking alternatives"
  ls bin/ 2>/dev/null || echo "No binaries found"
fi

# === 4. lm-evaluation-harness (for MMLU, HumanEval, ARC) ===
echo ">>> Installing lm-evaluation-harness..."
source /opt/bench-env/bin/activate
pip install -q lm-eval 2>&1 | tail -3
echo "lm-eval installed: $(python3 -c 'import lm_eval; print(lm_eval.__version__)' 2>/dev/null || echo 'checking...')"

# === 5. Download ternary model (BitNet) ===
echo ">>> Downloading BitNet ternary model..."
cd /models

# BitNet b1.58 2B4T (still latest ternary model, Jan 2026 CPU update)
if [ ! -d "bitnet-b1.58-2B-4T" ]; then
  echo "Downloading BitNet b1.58 2B4T..."
  source /opt/bench-env/bin/activate
  python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('microsoft/bitnet-b1.58-2B-4T', local_dir='/models/bitnet-b1.58-2B-4T')
print('BitNet 2B downloaded')
" 2>&1 | tail -3
fi

# NOTE: Old Falcon-Edge-3B and Falcon3-10B 1.58bit superseded by Falcon-H1R-7B
# Falcon-H1R-7B is downloaded as GGUF in download_models.sh

# === 6. Download WikiText-2 for perplexity ===
echo ">>> Downloading WikiText-2 for perplexity tests..."
mkdir -p /data
if [ ! -f "/data/wikitext-2-raw/wiki.test.raw" ]; then
  cd /data
  wget -q "https://huggingface.co/datasets/Salesforce/wikitext/resolve/main/wikitext-2-raw-v1/test-00000-of-00001.parquet" -O wikitext2_test.parquet 2>/dev/null || \
  wget -q "https://raw.githubusercontent.com/pytorch/examples/main/word_language_model/data/wikitext-2/test.txt" -O wikitext2_test.txt 2>/dev/null || \
  echo "WARNING: WikiText-2 download needs alternate source"
fi

echo ""
echo "=== Installation Summary ==="
echo "llamafile: $(which llamafile 2>/dev/null && echo OK || echo MISSING)"
echo "bitnet.cpp: $(ls /opt/BitNet/build/bin/llama-cli 2>/dev/null && echo OK || echo MISSING)"
echo "PowerInfer: $(ls /opt/PowerInfer/build/bin/main 2>/dev/null && echo OK || echo MISSING)"
echo "lm-eval: $(source /opt/bench-env/bin/activate && python3 -c 'import lm_eval; print("OK")' 2>/dev/null || echo MISSING)"
echo "BitNet-2B model: $(ls /models/bitnet-b1.58-2B-4T/ 2>/dev/null | head -1 && echo OK || echo MISSING)"
echo "=== Done ==="
