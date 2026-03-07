# Benchmarking Local LLM Inference on 16GB x86 Hardware (Linux, Server-Grade CPUs)

*March 2026*

## Abstract

We ran 150 experiments to find out which open-weight LLMs actually work on 16GB x86 Linux servers with no GPU. We tested 10 models at 5 quantization levels across 3 memory tiers on Hetzner Cloud (AMD EPYC Milan). Only one configuration crossed the 5 tok/s usability threshold: GLM-4.7-Flash (30B total, 3B active MoE) at Q2_K, hitting 7.2 tok/s. Every dense model 24B+ topped out at 4.2 tok/s — too slow for conversation. All raw data, scripts, and analysis are open source.

**Scope**: Linux only, on server-grade EPYC Milan CPUs (2.0 GHz, no boost) — slower per-thread than consumer CPUs like the i5-13400 or Ryzen 5 7600. Our numbers are probably a conservative floor. We haven't tested on consumer hardware yet. We did some exploratory Windows tests on different hardware (see Appendix A), but that data can't be compared to our Linux results — different CPU, different engine.

## 1. Introduction

The promise of running LLMs locally — for privacy, latency, and cost reasons — runs headfirst into a hardware wall. The average PC ships with 16GB of RAM, no dedicated GPU, and a mid-range CPU. Model providers publish benchmarks on A100s and M-series Macs with unified memory. Nobody publishes numbers for a $500 Dell with an AMD Ryzen and DDR4.

We set out to answer a concrete question: **which open-weight model gives the best experience on 16GB x86 hardware, CPU-only, running Linux?**

"Best experience" means sustained generation above 5 tokens/sec (roughly readable speed) with time-to-first-token under 5 seconds. We don't care about peak throughput on a warmup run. We care about what happens on the fifth turn of a conversation, or after 30 minutes of continuous use.

**What this study does NOT answer**: We do not yet know how these results translate to Windows, to consumer CPUs, or to user-facing tools like Ollama and LM Studio. Those are planned for future work (see Roadmap).

## 2. Related Work

Most LLM benchmarking focuses on GPU throughput (vLLM, TensorRT-LLM), Apple Silicon unified memory (MLX, llama.cpp Metal), or theoretical analysis. CPU-only benchmarks are scarce and usually limited to a single model on a single machine.

llama.cpp's built-in `llama-bench` provides per-model speed numbers but doesn't test multi-turn degradation, memory pressure, or concurrent load. LM Studio and Ollama publish usability-focused benchmarks but on high-end hardware.

We ran a controlled comparison of multiple models on deliberately constrained hardware, testing real-world usage patterns that other benchmarks skip.

## 3. Experimental Setup

### 3.1 Hardware

We used Hetzner Cloud servers with dedicated x86 CPUs:

- **bench-1, bench-2**: CCX23 — 4 dedicated AMD EPYC Milan cores, 16GB RAM, 160GB SSD
- **bench-3**: CX43 — 8 shared AMD EPYC Rome cores, 16GB RAM, 160GB SSD

All servers ran Ubuntu 24.04 with **no swap** configured. This is deliberate: if a model doesn't fit in RAM, the kernel kills the process. No silent thrashing, no misleading speed numbers from swapping to disk.

**About the CPUs**: EPYC Milan in these VMs runs at ~2.0 GHz with no turbo boost. That's slow compared to consumer CPUs — an i5-13400 boosts to 4.6 GHz, a Ryzen 5 7600 to 5.1 GHz. CPU inference cares about single-thread speed and memory bandwidth, so consumer hardware should do better than our numbers. How much better? We don't know yet — that's a gap we plan to close.

Total compute cost: approximately EUR 2.50.

### 3.2 Models

We selected 10 models across four architectural categories:

**MoE (Mixture of Experts)** — models with many total parameters but few active per token:
- Qwen3.5-35B-A3B (35B total, 3B active)
- GLM-4.7-Flash (30B total, 3B active)
- Nemotron-3-Nano-30B-A3B (30B total, 3.6B active)
- Llama 4 Scout 17B-16E (109B total, 17B active)

**Dense** — standard transformer models:
- Gemma-3-27B
- Mistral-Small-24B
- DeepSeek-R1-Distill-32B

**Control** — known to fit, baseline reference:
- Ministral-14B-Reasoning

**Ternary / Hybrid** — radical efficiency architectures:
- BitNet b1.58 2B4T
- Falcon-H1R-7B

### 3.3 Quantization

All models were obtained in GGUF format from HuggingFace (bartowski, unsloth, official repos). We tested five quantization levels: Q2_K (2-bit), Q3_K_M (3-bit), Q4_K_M (4-bit), Q5_K_M (5-bit), and Q8_0 (8-bit). Q8_0 was only tested on models under 14B parameters — for larger models, the GGUF file alone exceeds 16GB.

### 3.4 Inference Engine

All experiments used llama.cpp built from source, with `--no-mmap` to force full model loading into RAM (no memory-mapped I/O from disk). This gives honest memory measurements and avoids inflated speed numbers from OS page caching.

### 3.5 Memory Tiers

To simulate different levels of system load, we tested each configuration at three memory limits using `systemd-run --scope -p MemoryMax=XG`:

- **12 GB**: Simulates significant background usage
- **14 GB**: Simulates light background usage
- **15.5 GB**: Best case, almost nothing else running

Note: These tiers simulate available RAM, not OS-specific overhead. Windows typically uses ~2.2 GB at idle vs Linux ~0.5 GB, so the 12 GB tier is roughly what a Windows user with a browser open would have available. But we did not test on Windows for this data.

## 4. Results

### 4.1 What Fits

Of 96 quick benchmark runs (model + quantization + memory tier combinations), 31 completed successfully ("FITS"), 26 were killed by the OOM killer, and 39 errored because the GGUF file itself was larger than available RAM.

The breakdown by architecture:

| Architecture | Configs Tested | FITS | OOM | Too Large |
|-------------|---------------|------|-----|-----------|
| MoE | 30 | 8 | 10 | 12 |
| Dense | 54 | 19 | 14 | 21 |
| Control | 9 | 9 | 0 | 0 |
| Ternary/Hybrid | 3 | 0 | 0 | 3 |

Note: Falcon-H1R and BitNet produced no results due to engine/download issues (see Section 6).

### 4.2 Speed Ranking

Among configurations that fit in RAM, sorted by generation speed:

| Model | Quant | Best tok/s | Peak RAM | Architecture |
|-------|-------|-----------|----------|-------------|
| GLM-4.7-Flash | Q2_K | 7.2 | 10.7 GB | MoE |
| GLM-4.7-Flash | Q3_K_M | 6.6 | 11.4 GB | MoE |
| Mistral-Small-24B | Q2_K | 4.2 | 9.0 GB | Dense |
| Ministral-14B | Q4_K_M | 4.2 | 2.9 GB | Dense |
| Qwen3.5-35B-A3B | Q2_K | 3.8 | 12.5 GB | MoE |
| Mistral-Small-24B | Q3_K_M | 3.3 | 7.6 GB | Dense |
| Ministral-14B | Q5_K_M | 3.1 | 9.8 GB | Dense |
| Gemma-3-27B | Q2_K | 3.0 | 11.3 GB | Dense |
| DeepSeek-R1-32B | Q2_K | 2.8 | 12.4 GB | Dense |
| Mistral-Small-24B | Q4_K_M | 2.7 | 4.2 GB | Dense |

Only GLM-4.7-Flash exceeds our 5 tok/s usability threshold.

### 4.3 The MoE Advantage

GLM-4.7-Flash and Qwen3.5-35B-A3B are both MoE models with ~3B active parameters. GLM outperforms Qwen by nearly 2x despite similar architecture. The likely explanation: GLM's GGUF at Q2_K is 10.7GB vs Qwen's 12.5GB, leaving more headroom for KV cache and OS overhead.

Compared to dense models of similar intelligence (Mistral-Small-24B, Gemma-3-27B), MoE models are consistently faster because they only read ~3B parameters worth of weights from memory per token, while dense models read all 24-27B.

On memory-bandwidth-limited hardware like this (CPU inference), MoE's sparse activation pattern matters more than anything else.

### 4.4 Stability Over Time

Seven models were tested with 30 minutes of continuous generation, sampling speed and memory every 30 seconds.

| Model | tok/s at start | tok/s at 30 min | Degradation | Memory Leak |
|-------|---------------|----------------|-------------|-------------|
| GLM-4.7-Flash Q2_K | 7.1 | 7.2 | 0% | None |
| GLM-4.7-Flash Q3_K_M | 6.7 | 6.7 | 0% | None |
| Mistral-Small-24B Q2_K | 4.2 | 4.0 | 5% | None |
| Mistral-Small-24B Q3_K_M | 3.2 | 3.4 | 0% | None |
| Gemma-3-27B Q2_K | 2.8 | 2.9 | 0% | None |
| Ministral-14B Q4_K_M | 4.0 | 4.1 | 0% | None |
| Qwen3.5-35B-A3B Q2_K | 3.7 | 3.7 | 0% | None |

No model showed meaningful degradation. CPU inference on these servers is thermally stable — no throttling, no memory leaks, nothing interesting happened for 30 minutes straight.

### 4.5 Multi-Turn Degradation

We simulated 10-turn conversations (user question, model response, user follow-up, etc.) to measure how growing context affects speed.

| Model | Turn 1 | Turn 5 | Turn 10 | Degradation |
|-------|--------|--------|---------|------------|
| GLM-4.7-Flash Q2_K | 6.7 | 6.2 | 5.5 | 18% |
| GLM-4.7-Flash Q3_K_M | 6.5 | 5.7 | 5.1 | 22% |
| Qwen3.5-35B-A3B Q2_K | 3.7 | 3.6 | 3.6 | 3% |
| Mistral-Small-24B Q2_K | 4.0 | 4.1 | 3.8 | 5% |
| Ministral-14B Q4_K_M | 4.1 | 4.0 | — | 7% |

GLM-4.7-Flash degrades the most (18-22%), likely because the growing KV cache competes with its large model weights for the 16GB RAM budget. At turn 10 it drops to 5.1-5.5 tok/s — still above the usability line, but only just. Qwen3.5 barely degrades but starts below the threshold.

### 4.6 Concurrent Load

Running `stress --cpu 2` in the background (simulating browser tabs and system services) had minimal impact:

| Model | Clean | Under Stress | Drop |
|-------|-------|-------------|------|
| GLM-4.7-Flash Q2_K | 7.2 | 7.1 | 1% |
| GLM-4.7-Flash Q3_K_M | 6.6 | 6.6 | 0% |
| Mistral-Small-24B Q2_K | 4.2 | 4.0 | 5% |
| Ministral-14B Q4_K_M | 4.2 | 4.1 | 2% |

The bottleneck for CPU inference is memory bandwidth (reading model weights from DRAM), not CPU compute. Stealing CPU cores barely matters because inference is already waiting on memory most of the time.

## 5. Discussion

### The 16GB Wall

The fundamental constraint is not compute — it's memory capacity. A 30B dense model at Q4_K_M (the "sweet spot" quantization) produces a GGUF file of 15-18GB. It physically cannot fit in 16GB of RAM alongside the operating system.

MoE models sidestep this partially: the full model is large, but the active parameter set is small enough to keep the memory bandwidth requirement low. However, the full model still needs to be loaded into RAM. MoE helps with speed (less data to read per token) but not with the loading problem.

### The Quality Question

The only usable configurations need Q2_K quantization (2-bit). At this level, quality takes a real hit. We measured 4-6% 4-gram repetition rates — the models get stuck in loops. Our perplexity measurements failed (see Section 6), so we cannot precisely quantify the quality loss.

This is the core tension: **you can fit it in 16GB, but you have to destroy quality to get there.**

### Hardware Representativeness

Our EPYC Milan CPUs run at ~2.0 GHz with no boost. That's well below modern consumer CPUs:

| CPU | Single-Thread (est.) | Context |
|-----|---------------------|---------|
| AMD EPYC Milan (ours) | ~85-90 | Server, 2.0 GHz base |
| Intel i5-13400 | ~105 | Consumer mid-range |
| AMD Ryzen 5 7600 | ~110 | Consumer mid-range |
| Intel i5-12400 | ~95 | Budget consumer |

CPU inference speed tracks single-thread performance and memory bandwidth pretty closely, so our tok/s numbers are probably a **lower bound**. A Ryzen 5 or i5 might do 15-25% better — which would put GLM-4.7-Flash around 8-9 tok/s and might push borderline models like Mistral-Small Q2_K (4.2 tok/s) over the 5 tok/s line. But we haven't tested this, so take these estimates with salt.

### What Would Change the Game

Three developments could break through the 16GB wall:

1. **Larger natively ternary models.** Microsoft's BitNet b1.58 architecture uses {-1, 0, 1} weights with integer-only arithmetic. A 100B BitNet model would be ~12.5GB. But only a 2B model exists today.

2. **Better quantization.** Unsloth's Dynamic 2.0 does per-layer adaptive quantization using KL divergence — important layers stay at 6-8 bit while filler layers get crushed to 1.58-bit. This could preserve quality at lower average bit-width.

3. **Smarter KV cache.** Techniques like RocketKV (400x compression) and llama.cpp's Q4 KV cache could free enough RAM to use higher-quality quantization for the model weights.

## 6. Limitations

**Server CPUs, not consumer hardware.** EPYC Milan at 2.0 GHz is slower per-thread than a typical desktop i5 or Ryzen 5. Our numbers are a floor. We need to test on consumer hardware to know what real users would get.

**Linux only.** All 150 experiments ran on Ubuntu 24.04. We don't know how Windows or macOS compares on the same hardware. We did some Windows tests on a different, weaker CPU (see Appendix A) — Windows eats ~2.2 GB for the OS and GLM-4.7-Flash thrashed — but we can't compare those numbers to our Linux data because too many variables changed.

**Context scaling data is incomplete.** A bug in our skip-if-completed logic caused the orchestrator to test only ctx=512 for all models instead of scaling from 512 to 8192. We know from multi-turn tests that speed degrades with context, but we lack precise per-context-length data.

**Two models produced no results.** Falcon-H1R-7B (hybrid Mamba-Transformer) and BitNet b1.58-2B-4T (ternary) were assigned to bench-3 but neither appears in our results. Likely causes: model download failure, engine incompatibility, or the alternative engines (bitnet.cpp, llamafile) were not successfully installed.

**Perplexity failed to parse.** All WikiText-2 perplexity evaluations returned null. The runs completed (logs exist on the servers) but our parser didn't extract the scores. The repetition rate measurements worked, but perplexity would have given a much clearer picture of quality degradation at each quantization level.

**No engine comparison.** We intended to compare llama.cpp against llamafile, bitnet.cpp, and PowerInfer. These weren't installed in time. This is a significant gap — llamafile in particular claims 3-4x speedups on some CPU architectures.

**Shared cores on bench-3.** bench-3 used shared (not dedicated) CPU cores. Its results are slightly noisy and not directly comparable to bench-1/bench-2, though the trends are consistent.

## 7. Conclusion

On 16GB x86 Linux servers with no GPU, exactly one model provides a usable chat experience: **GLM-4.7-Flash at Q2_K quantization, generating 7.2 tokens per second.** This is the only configuration we tested that crosses the 5 tok/s usability threshold.

We tested on EPYC Milan servers, which are slower per-thread than consumer desktops — so real-world speeds should be somewhat higher. We haven't measured how much.

The architectural point holds regardless of CPU: **MoE is the only way to get 30B+ running on 16GB.** Dense models read all their parameters on every token, and that's too much data to move through memory. Faster CPUs won't fix that — it's a bandwidth problem.

MoE plus better quantization is the way forward. Dense models are a dead end at this memory budget. Things that could change the picture:

- Larger natively ternary (BitNet-style) models
- Adaptive per-layer quantization that keeps quality at low average bit-width
- KV cache compression to free RAM for better model quants
- Engine optimizations (llamafile, specialized CPU kernels) that might push borderline models over the line
- Actually testing on consumer hardware and Windows

All 150 experiment results, scripts, and analysis are on GitHub.

## Appendix A: Exploratory Windows Testing

We conducted exploratory tests on an Azure D4s_v3 VM (Intel Xeon Platinum 8272CL @ 2.60GHz, 4 vCPU, 16GB RAM) running Windows 11 Pro. These results are **not comparable** to our Linux data because:

1. **Different CPU**: Xeon 8272CL (Cascade Lake, 2019) vs EPYC Milan (Zen 3, 2021)
2. **Different inference engine**: Ollama vs llama.cpp
3. **Different models tested**: 1.7B-12B (Windows) vs 24-30B (Linux)

### What we measured

**Windows OS overhead**: 2.17 GB (13.78 GB available from 15.95 GB total at clean boot).

**Small model sweep via Ollama** (Q4_K_M defaults, 300 tokens, ctx 2048):

| Model | Params | tok/s | Verdict |
|-------|--------|-------|---------|
| Qwen3 1.7B | 1.7B | 8.3 | Usable |
| Llama 3.2 3B | 3B | 5.3 | Usable |
| Phi-4 Mini | 3.8B | 4.4 | Borderline |
| Qwen3 4B | 4B | 4.2 | Borderline |
| Gemma3 4B | 4B | 4.3 | Borderline |
| Qwen3 8B | 8B | 2.3 | No |
| Llama 3.1 8B | 8B | 2.4 | No |
| Mistral 7B | 7B | 2.7 | No |
| Gemma3 12B | 12B | 1.5 | No |

**GLM-4.7-Flash 30B MoE via llama.cpp**: Could not produce a single token in 30+ minutes (thrashing). This may be due to the weaker CPU, Windows memory management, or both — we cannot isolate the cause.

### What this data tells us

- Windows 11 consumes ~2.2 GB at idle, leaving ~13.8 GB for models
- On a 2019 Xeon, small models (1.7-3B) are usable via Ollama on Windows
- GLM-4.7-Flash 30B MoE does not work on this specific Windows+Xeon combination

### What this data does NOT tell us

- How Windows compares to Linux on the same hardware (not tested)
- What Windows users with modern consumer CPUs would experience
- Whether the GLM-4.7-Flash thrashing is a Windows issue or a CPU issue

A real cross-OS comparison needs the same hardware, same engine, and same models on both operating systems. That's next on the list.

## References

1. llama.cpp — https://github.com/ggml-org/llama.cpp
2. GLM-4.7-Flash — https://huggingface.co/THUDM/GLM-4.7-Flash
3. Qwen3.5-35B-A3B — https://huggingface.co/Qwen/Qwen3.5-35B-A3B
4. BitNet b1.58 — https://github.com/microsoft/BitNet
5. Unsloth Dynamic 2.0 — https://unsloth.ai/blog/dynamic-v2
6. RocketKV — https://arxiv.org/html/2502.14051v3
7. RWKV-7 — https://arxiv.org/abs/2503.14456
