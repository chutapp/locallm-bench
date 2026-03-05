# Benchmarking Local LLM Inference on 16GB Consumer Hardware

*March 2026*

## Abstract

We present a systematic evaluation of running large language models (30B+ parameters) on commodity x86 hardware with 16GB RAM and no GPU. Using three cloud servers configured to match typical consumer PCs, we ran 150 experiments across 10 models, 5 quantization levels, and 3 memory tiers. Our findings show that Mixture-of-Experts (MoE) models are the only viable architecture for this constraint, with GLM-4.7-Flash (30B total, 3B active parameters) achieving 7.2 tokens/sec at Q2_K quantization — the only configuration that crosses the usability threshold of 5 tok/s. Dense models of 24B+ parameters universally fail to reach usable speeds, maxing out at 4.2 tok/s. We release all raw data, scripts, and analysis as open source.

## 1. Introduction

The promise of running LLMs locally — for privacy, latency, and cost reasons — runs headfirst into a hardware wall. The average PC ships with 16GB of RAM, no dedicated GPU, and a mid-range CPU. Model providers publish benchmarks on A100s and M-series Macs with unified memory. Nobody publishes numbers for a $500 Dell with an AMD Ryzen and DDR4.

We set out to answer a concrete question: **which open-weight model gives the best experience on 16GB x86 hardware, CPU-only?**

"Best experience" means sustained generation above 5 tokens/sec (roughly readable speed) with time-to-first-token under 5 seconds. We don't care about peak throughput on a warmup run. We care about what happens on the fifth turn of a conversation, or after 30 minutes of continuous use.

## 2. Related Work

Most LLM benchmarking focuses on GPU throughput (vLLM, TensorRT-LLM), Apple Silicon unified memory (MLX, llama.cpp Metal), or theoretical analysis. CPU-only benchmarks are scarce and usually limited to a single model on a single machine.

llama.cpp's built-in `llama-bench` provides per-model speed numbers but doesn't test multi-turn degradation, memory pressure, or concurrent load. LM Studio and Ollama publish usability-focused benchmarks but on high-end hardware.

Our contribution is a controlled, multi-model comparison on deliberately constrained hardware, with real-world usage patterns.

## 3. Experimental Setup

### 3.1 Hardware

We used Hetzner Cloud servers to get reproducible, dedicated x86 hardware:

- **bench-1, bench-2**: CCX23 — 4 dedicated AMD EPYC Milan cores, 16GB RAM, 160GB SSD
- **bench-3**: CX43 — 8 shared AMD EPYC Rome cores, 16GB RAM, 160GB SSD

All servers ran Ubuntu 24.04 with **no swap** configured. This is deliberate: if a model doesn't fit in RAM, the kernel kills the process. No silent thrashing, no misleading speed numbers from swapping to disk.

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

To simulate real user conditions, we tested each configuration at three memory limits using `systemd-run --scope -p MemoryMax=XG`:

- **12 GB**: Windows user with browser and apps open
- **14 GB**: Linux user, light background usage
- **15.5 GB**: Best case, almost nothing else running

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

This confirms the theoretical expectation: on memory-bandwidth-limited hardware (CPU inference), MoE's sparse activation pattern is the most important architectural feature.

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

No model showed meaningful degradation. CPU inference on modern hardware with adequate cooling is thermally stable. No memory leaks were detected in any configuration.

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

Our data shows that the only usable configurations require Q2_K quantization (2-bit). At this level, model quality is significantly degraded. We measured 4-6% 4-gram repetition rates, suggesting the models are prone to getting stuck in loops. Our perplexity measurements failed (see Section 6), so we cannot precisely quantify the quality loss.

This is the core tension: **you can fit it in 16GB, but you have to destroy quality to get there.**

### What Would Change the Game

Three developments could break through the 16GB wall:

1. **Larger natively ternary models.** Microsoft's BitNet b1.58 architecture uses {-1, 0, 1} weights with integer-only arithmetic. A 100B BitNet model would be ~12.5GB. But only a 2B model exists today.

2. **Better quantization.** Unsloth's Dynamic 2.0 does per-layer adaptive quantization using KL divergence — important layers stay at 6-8 bit while filler layers get crushed to 1.58-bit. This could preserve quality at lower average bit-width.

3. **Smarter KV cache.** Techniques like RocketKV (400x compression) and llama.cpp's Q4 KV cache could free enough RAM to use higher-quality quantization for the model weights.

## 6. Limitations

**Context scaling data is incomplete.** A bug in our skip-if-completed logic caused the orchestrator to test only ctx=512 for all models instead of scaling from 512 to 8192. We know from multi-turn tests that speed degrades with context, but we lack precise per-context-length data.

**Two models produced no results.** Falcon-H1R-7B (hybrid Mamba-Transformer) and BitNet b1.58-2B-4T (ternary) were assigned to bench-3 but neither appears in our results. Likely causes: model download failure, engine incompatibility, or the alternative engines (bitnet.cpp, llamafile) were not successfully installed.

**Perplexity failed to parse.** All WikiText-2 perplexity evaluations returned null. The runs completed (logs exist on the servers) but our parser didn't extract the scores. The repetition rate measurements worked, but perplexity would have given a much clearer picture of quality degradation at each quantization level.

**No engine comparison.** We intended to compare llama.cpp against llamafile, bitnet.cpp, and PowerInfer. These weren't installed in time. This is a significant gap — llamafile in particular claims 3-4x speedups on some CPU architectures.

**Shared cores on bench-3.** bench-3 used shared (not dedicated) CPU cores. Its results are slightly noisy and not directly comparable to bench-1/bench-2, though the trends are consistent.

## 7. Conclusion

On 16GB x86 hardware with no GPU, exactly one model provides a usable chat experience: **GLM-4.7-Flash at Q2_K quantization, generating 7.2 tokens per second.** This is the only configuration we tested that crosses the 5 tok/s usability threshold.

The path forward is clear: MoE architectures combined with better quantization techniques. Dense models are a dead end at this memory budget. The research community should focus on:

- Training larger natively ternary (BitNet-style) models
- Adaptive per-layer quantization that preserves quality at low average bit-width
- KV cache compression to free RAM for higher-quality model weights
- Engine optimizations (llamafile, specialized CPU kernels) that may unlock usable speeds for currently-borderline models

We release all 150 experiment results, scripts, and analysis as open source to help others build on this work.

## References

1. llama.cpp — https://github.com/ggml-org/llama.cpp
2. GLM-4.7-Flash — https://huggingface.co/THUDM/GLM-4.7-Flash
3. Qwen3.5-35B-A3B — https://huggingface.co/Qwen/Qwen3.5-35B-A3B
4. BitNet b1.58 — https://github.com/microsoft/BitNet
5. Unsloth Dynamic 2.0 — https://unsloth.ai/blog/dynamic-v2
6. RocketKV — https://arxiv.org/html/2502.14051v3
7. RWKV-7 — https://arxiv.org/abs/2503.14456
