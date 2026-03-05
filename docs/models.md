# Model Selection

Why we chose these 10 models and what we expected from each.

## Selection Criteria

1. **30B+ total parameters** (or architecturally interesting smaller models)
2. **Open weights** with permissive license
3. **GGUF format available** on HuggingFace
4. **Released within the last 12 months** (as of March 2026)

## Models Tested

### Category A: MoE (Best Candidates)

These models have many total parameters but activate only a fraction per token. In theory, they should give 30B+ intelligence at sub-5B memory bandwidth cost.

| Model | Total | Active | Released | Rationale |
|-------|-------|--------|----------|-----------|
| Qwen3.5-35B-A3B | 35B | 3B | Feb 2026 | Latest Qwen MoE, 262K context |
| GLM-4.7-Flash | 30B | 3B | Jan 2026 | Strong coding, interleaved thinking |
| Nemotron-3-Nano-30B-A3B | 30B | 3.6B | 2026 | Hybrid Mamba-2 + MoE, 1M context |
| Llama 4 Scout 17B-16E | 109B | 17B | Apr 2025 | Stress test -- 16 experts, 10M context |

**What happened**: GLM-4.7-Flash was the standout. Qwen3.5 worked but slower. Nemotron's Q2_K was 17GB (too large to load). Llama 4 Scout at 33GB was impossible.

### Category B: Dense (Baselines)

Standard transformer models at the largest sizes that might conceivably fit in 16GB.

| Model | Params | Released | Rationale |
|-------|--------|----------|-----------|
| Gemma-3-27B | 27B | Mar 2025 | Latest Gemma, good benchmarks |
| Mistral-Small-24B | 24B | Jan 2025 | Biggest Mistral dense model |
| DeepSeek-R1-Distill-32B | 32B | Jan 2025 | Reasoning model |

**What happened**: All required Q2_K to fit. Mistral-Small was fastest of the dense models at 4.2 tok/s but still below usability.

### Category C: Ternary / Hybrid

Architecturally different approaches to efficiency.

| Model | Params | Architecture | Rationale |
|-------|--------|-------------|-----------|
| BitNet b1.58 2B4T | 2B | 1.58-bit ternary | Microsoft reference, integer-only math |
| Falcon-H1R-7B | 7B | Hybrid Mamba-Transformer | 256K context, reasoning |

**What happened**: Neither produced results. BitNet likely needed bitnet.cpp (not llama.cpp). Falcon may have had download issues.

### Category D: Control

| Model | Params | Rationale |
|-------|--------|-----------|
| Ministral-14B-Reasoning | 14B | Known to fit, baseline reference |

**What happened**: Fit comfortably at Q4_K_M (2.9GB RAM). 4.2 tok/s. Good baseline showing that a 14B model is fast enough to be borderline usable.

## Models We Considered But Dropped

| Model | Why Dropped |
|-------|------------|
| Qwen3-30B-A3B | Superseded by Qwen3.5-35B-A3B |
| Llama-3.1-8B | Too small, not interesting for 16GB research |
| Falcon-Edge-3B | Superseded by Falcon-H1R-7B |
| Falcon3-10B-1.58bit | Superseded by Falcon-H1R-7B |

## Where to Download

All models were downloaded from HuggingFace in GGUF format:

- bartowski's quantizations: https://huggingface.co/bartowski
- Unsloth quantizations: https://huggingface.co/unsloth
- Official repos for some models (Mistral, Google)

Use `huggingface-cli download` with `--resume-download` for reliable transfers.
