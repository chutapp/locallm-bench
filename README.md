# Can You Run a 30B LLM on 16GB RAM? We Tested It.

**150 experiments. 10 models. 3 servers. No GPU. Here's what actually works.**

We wanted to know if a regular 16GB PC — the kind most people own — can run large language models locally without a GPU. Not marketing benchmarks, not "it technically loads." We mean: can you actually have a conversation with it?

We rented three Hetzner Cloud servers with 4-core AMD EPYC CPUs and 16GB RAM (no swap, no GPU), downloaded every promising open-weight model we could find, quantized them to various levels, and ran them through a gauntlet of real-world tests.

The short answer: **one model crosses the usability line.** The rest are too slow or too big.

---

## Results at a Glance

| Model | Architecture | Params | Quant | tok/s | RAM Used | Usable? |
|-------|-------------|--------|-------|-------|----------|---------|
| GLM-4.7-Flash | MoE (3B active) | 30B | Q2_K | **7.2** | 10.7 GB | Yes |
| GLM-4.7-Flash | MoE (3B active) | 30B | Q3_K_M | **6.6** | 11.4 GB | Yes |
| Mistral-Small-24B | Dense | 24B | Q2_K | 4.2 | 9.0 GB | Borderline |
| Ministral-14B | Dense | 14B | Q4_K_M | 4.2 | 2.9 GB | Borderline |
| Qwen3.5-35B-A3B | MoE (3B active) | 35B | Q2_K | 3.8 | 12.5 GB | No |
| Mistral-Small-24B | Dense | 24B | Q3_K_M | 3.3 | 7.6 GB | No |
| Gemma-3-27B | Dense | 27B | Q2_K | 3.0 | 11.3 GB | No |
| DeepSeek-R1-32B | Dense | 32B | Q2_K | 2.8 | 12.4 GB | No |
| Gemma-3-27B | Dense | 27B | Q3_K_M | 2.4 | 9.4 GB | No |

**Usability threshold**: >5 tokens/sec with <5 second time-to-first-token.

Full results (all 150 experiments as JSON): [`results/`](results/)

---

## What We Learned

### 1. MoE models are the only path to 30B+ on 16GB

GLM-4.7-Flash has 30 billion total parameters but only activates 3 billion per token. This is the only architecture that crossed our 5 tok/s usability threshold. Dense models of similar size are 2-3x slower because they touch every parameter on every token.

### 2. Even MoE needs aggressive quantization

GLM-4.7-Flash only works at Q2_K (2-bit) and Q3_K_M (3-bit). At Q4_K_M it OOMs. This means the model fits, but the quality is compromised — we measured 4-6% 4-gram repetition rates, which suggests the aggressive quantization is hurting coherence.

### 3. Most "30B" models simply do not fit

| Model | Smallest GGUF | Why it fails |
|-------|--------------|-------------|
| Nemotron-3-Nano-30B | 17.2 GB at Q2_K | File larger than RAM |
| Llama 4 Scout (109B) | 33.4 GB at IQ1_M | Way too large |
| Qwen3.5-35B at Q5_K_M | 23.7 GB | File larger than RAM |
| DeepSeek-R1-32B at Q3_K_M | 15.2 GB | Loads but OOMs during inference |

### 4. Speed is rock-solid over time

Every model we tested maintained constant throughput over 30 minutes of continuous generation. No thermal throttling, no memory leaks, no degradation. CPU inference on modern hardware is boring in the best way.

### 5. Multi-turn conversations cost ~15-20% speed

After 10 turns of back-and-forth, GLM-4.7-Flash slowed from 6.7 to 5.5 tok/s (18% drop). It stays above the usability line, but just barely. Dense models showed similar degradation.

### 6. Background CPU load barely matters

Running `stress --cpu 2` alongside inference (simulating a browser and other apps) caused only a 0-5% speed drop. The bottleneck on CPU inference is memory bandwidth, not compute.

---

## Methodology

### Hardware

Three Hetzner Cloud servers, deliberately chosen to match typical consumer PCs:

| Server | CPU | Cores | RAM | Swap | GPU |
|--------|-----|-------|-----|------|-----|
| bench-1 | AMD EPYC Milan | 4 dedicated | 16 GB | None | None |
| bench-2 | AMD EPYC Milan | 4 dedicated | 16 GB | None | None |
| bench-3 | AMD EPYC Rome | 8 shared | 16 GB | None | None |

No swap on any server. If a model doesn't fit, the process gets OOM-killed. Honest results.

### Software

- **Inference engine**: llama.cpp (latest build from source)
- **Model format**: GGUF (from HuggingFace — bartowski, unsloth, official repos)
- **Quantization levels tested**: Q2_K, Q3_K_M, Q4_K_M, Q5_K_M, Q8_0

### Memory tiers

We tested each model at three simulated memory limits to see how they perform when the OS and other apps take some RAM:

| Tier | Available RAM | Simulates |
|------|--------------|-----------|
| 12 GB | Windows user with browser + apps |
| 14 GB | Linux user, light usage |
| 15.5 GB | Best case, almost nothing running |

Enforced via `systemd-run --scope -p MemoryMax=XG`.

### Test phases

1. **Quick benchmark** (96 runs) — Load model, generate 500 tokens, measure speed/RAM/outcome
2. **Context scaling** (12 runs) — Test at context lengths 512 to 8192
3. **30-minute stability** (7 runs) — Continuous generation, sample every 30 seconds
4. **Multi-turn conversation** (7 runs) — 10-turn dialogue, measure degradation
5. **Concurrent load** (7 runs) — Inference while `stress --cpu 2` runs
6. **Quality evaluation** (12 runs) — Repetition rate, coherence tests
7. **Recovery & burst** (3 runs) — OOM recovery, cold vs warm start

Total: **150 experiments**, each producing a structured JSON file with ~70 data points.

### What we measured per experiment

Every run captured: tokens/sec (generation and prompt processing), time-to-first-token, inter-token latency stats, peak RSS, virtual memory, model load time, CPU utilization, disk I/O, page faults, and more. See [`docs/metrics.md`](docs/metrics.md) for the complete list.

---

## How to Reproduce

### Option 1: Use our scripts on any 16GB Linux machine

```bash
# Install llama.cpp
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp && cmake -B build && cmake --build build -j$(nproc)
sudo cp build/bin/llama-* /usr/local/bin/

# Download a model (example: GLM-4.7-Flash Q2_K)
pip install huggingface-hub
huggingface-cli download bartowski/GLM-4.7-Flash-GGUF GLM-4.7-Flash-Q2_K.gguf --local-dir ./models/

# Run a quick benchmark
bash scripts/run_single_bench.sh ./models/GLM-4.7-Flash-Q2_K.gguf llama.cpp 15.5 2048 quick
```

### Option 2: Run the full suite on cloud servers

```bash
# Provision a Hetzner CCX23 (or any 16GB VPS)
# Upload scripts to server
scp -r scripts/ root@YOUR_SERVER:/scripts/

# Run the orchestrator
ssh root@YOUR_SERVER 'nohup bash /scripts/orchestrator.sh bench-1 >> /logs/orchestrator.log 2>&1 &'

# Check progress
bash scripts/check_status.sh
```

See [`docs/setup.md`](docs/setup.md) for detailed server provisioning instructions.

---

## Known Gaps

We're sharing these results as-is, warts and all:

- **Context scaling data is thin.** A deduplication bug in our orchestrator meant only ctx=512 was tested for most models. We know speed degrades with context but can't quantify it precisely.
- **Falcon-H1R-7B and BitNet 2B4T produced no results.** Likely download or engine compatibility issues on bench-3. These need re-testing.
- **Perplexity scores failed to parse.** The quality evaluation captured repetition rates but WikiText-2 perplexity came back null for all models. The perplexity runs may have timed out or the log parser had a regex mismatch.
- **No engine comparison.** We planned to test llamafile, bitnet.cpp, and PowerInfer alongside llama.cpp, but these weren't installed on bench-3 in time.

If you re-run any of these and get better data, please open a PR.

---

## Project Structure

```
.
├── README.md                   # This file
├── PAPER.md                    # Detailed writeup of findings
├── results/
│   ├── bench-1/                # Raw JSON results from server 1
│   ├── bench-2/                # Raw JSON results from server 2
│   └── bench-3/                # Raw JSON results from server 3
├── scripts/
│   ├── orchestrator.sh         # Master script — runs all phases
│   ├── run_single_bench.sh     # Single experiment runner
│   ├── run_quality_eval.sh     # Quality evaluation (perplexity, coherence)
│   ├── download_models.sh      # Model downloader with resume support
│   ├── check_status.sh         # Monitor running experiments
│   ├── collect_results.sh      # Pull results from remote servers
│   ├── launch_all.sh           # Deploy and start on multiple servers
│   ├── install_extra_engines.sh# Install llamafile, bitnet.cpp, etc.
│   └── lib.sh                  # Shared functions (logging, metrics)
├── docs/
│   ├── setup.md                # Server provisioning guide
│   ├── metrics.md              # Complete list of collected metrics
│   └── models.md               # Model selection rationale
├── EXPERIMENT_PLAN.md          # Original experiment design
└── LICENSE                     # MIT
```

---

## Contributing

This is a living research project. Contributions welcome:

- **Re-run experiments** on different hardware and share results
- **Fix the context scaling bug** and submit longer-context data
- **Test models we missed** (Falcon-H1R, BitNet, newer releases)
- **Engine comparisons** (llamafile, PowerInfer, bitnet.cpp)
- **Quality evaluation** improvements (working perplexity, MMLU)

Please open an issue first to discuss what you'd like to work on.

---

## Citation

If you use this data in your work:

```
@misc{locallm-bench-2026,
  title={Can You Run a 30B LLM on 16GB RAM? Benchmarking Local LLM Inference on Consumer Hardware},
  author={chutapp},
  year={2026},
  url={https://github.com/chutapp/locallm-bench}
}
```

---

## License

MIT. Use the data, use the scripts, build on this work. If you find something interesting, let us know.
