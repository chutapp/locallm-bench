# LocalLM Research — Experiment Plan v3

> **Goal**: Can a 30B+ quality model run usably (>5 tok/s, acceptable quality) on a 16GB x86 PC with no GPU?

> **Date**: March 4, 2026 (updated with latest models)

> **Principle**: Collect EVERYTHING. We decide later what matters. Missing data = rerunning experiments.

---

## Infrastructure

| Server | Type | Specs | Cost |
|--------|------|-------|------|
| locallm-bench-1 | CCX23 | 4 dedicated AMD EPYC cores, 16GB, no swap, 160GB SSD | €0.038/hr |
| locallm-bench-2 | CCX23 | same | same |
| locallm-bench-3 | CX43 (shared) | 8 shared AMD EPYC cores, 16GB, no swap, 160GB SSD | €0.024/hr |

**Total cost estimate**: 2×€0.038 + 1×€0.024 = €0.10/hr × ~14 hours ≈ **€1.40 total**

---

## Models Under Test (all latest as of March 2026)

### Category A: MoE Sparse (Best candidates — 30B+ total, few active params)

| # | Model | Total Params | Active Params | Released | Why |
|---|-------|-------------|---------------|---------|-----|
| 1 | **Qwen3.5-35B-A3B** | 35B | 3B | Feb 2026 | Latest Qwen MoE, 262K ctx, multimodal |
| 2 | **Llama 4 Scout 17B-16E** | 109B | 17B | Apr 2025 | Meta's MoE, 16 experts, 10M ctx — stress test |
| 3 | **GLM-4.7-Flash** | 30B | 3B | Jan 2026 | Strong coding, interleaved thinking |
| 4 | **Nemotron-3-Nano-30B-A3B** | 30B | 3.6B | 2026 | Hybrid Mamba-2 + MoE, 1M ctx, NVIDIA |

### Category B: Dense (Baseline comparisons)

| # | Model | Params | Released | Why |
|---|-------|--------|---------|-----|
| 5 | **Gemma-3-27B** | 27B | Mar 2025 | Latest Gemma (no Gemma 4 yet), vision |
| 6 | **Mistral-Small-24B-2501** | 24B | Jan 2025 | Biggest Mistral dense model |
| 7 | **DeepSeek-R1-Distill-32B** | 32B | Jan 2025 | Reasoning model (R1-0528 update) |

### Category C: Ternary / Hybrid (Radical efficiency)

| # | Model | Params | Architecture | Released | Why |
|---|-------|--------|-------------|---------|-----|
| 8 | **BitNet b1.58 2B4T** | 2B | 1.58-bit ternary | Apr 2025 (Jan 2026 CPU update) | Microsoft reference, CPU-native |
| 9 | **Falcon-H1R-7B** | 7B | Hybrid Mamba-Transformer | Jan 2026 | Latest Falcon, 256K ctx, reasoning |

### Category D: Control (Known to fit, baseline reference)

| # | Model | Params | Released | Why |
|---|-------|--------|---------|-----|
| 10 | **Ministral-3-14B-Reasoning** | 14B | Dec 2025 | Latest small reasoning model, should fit easily |

**Dropped from v2**: Qwen3-30B-A3B (superseded by Qwen3.5-35B-A3B), Llama-3.1-8B (superseded by Llama 4 Scout), Falcon-Edge-3B & Falcon3-10B-1.58bit (superseded by Falcon-H1R-7B)

---

## Quantization Levels

| Level | Bits | Notes |
|-------|------|-------|
| Q2_K | 2 | Most aggressive, worst quality |
| Q3_K_M | 3 | Aggressive but usable? |
| Q4_K_M | 4 | Sweet spot for most |
| Q5_K_M | 5 | Better quality, more RAM |
| Q8_0 | 8 | Near-lossless, huge — **skipped for 30B+ models** (33GB > 16GB RAM = guaranteed OOM) |

*Notes:*
- *Ternary models (Category C) skip quantization — they're already 1.58-bit natively.*
- *Q8_0 only tested on 14B and smaller models (Ministral, Falcon-H1R) where file fits in RAM.*

---

## Inference Engines

| Engine | Version | Where | What it tests |
|--------|---------|-------|---------------|
| **llama.cpp** | b8201 | All servers | Raw CPU inference baseline (primary engine) |
| **llamafile** | Latest | bench-3 only | Single-file portability, CPU optimizations |
| **bitnet.cpp** | Latest | bench-3 only | Native 1-bit engine (BitNet ternary model only) |
| **PowerInfer** | Latest | bench-3 only | Neuron sparsity (limited model support — ReLU only) |

*Ollama dropped — same GGUF engine as llama.cpp, adds only API overhead. Not worth the complexity.*

---

## Memory Tiers (Simulating real user conditions)

| Tier | Limit | Simulates | Enforced via |
|------|-------|-----------|-------------|
| **A** | 12 GB | Windows user + browser + apps | `systemd-run --scope -p MemoryMax=12G` |
| **B** | 14 GB | Linux user, light usage | `systemd-run --scope -p MemoryMax=14G` |
| **C** | 15.5 GB | Best case, almost nothing running | No limit (full server RAM) |

---

## Metrics Collected Per Experiment — COMPLETE LIST

### A. Memory Metrics (Does it fit? How tight?)

| Metric | Tool | What it tells us |
|--------|------|-----------------|
| **Peak RSS (Resident Set)** | `/proc/PID/status` → VmRSS max | Actual physical RAM used |
| **Peak Virtual Memory** | `/proc/PID/status` → VmPeak | Total memory mapped (incl. mmap) |
| **RAM at model load** | Sample before first token | Memory just to load the model |
| **RAM at 512 tokens generated** | Sample during generation | Growth after short conversation |
| **RAM at 2048 tokens generated** | Sample during generation | Growth with medium context |
| **RAM at 4096 tokens generated** | Sample during generation | Near-limit behavior |
| **KV cache size** | Estimate from context × layers × dims | How much context costs in RAM |
| **Memory growth rate** | Delta RSS over time | Detecting memory leaks |
| **Outcome** | Custom script | **FITS** / **THRASHES** / **OOM** |

### B. Speed Metrics (Is it usable?)

| Metric | Tool | What it tells us |
|--------|------|-----------------|
| **Tokens/sec generation (tg)** | `llama-bench` / custom | Output speed — main usability metric |
| **Tokens/sec prompt processing (pp)** | `llama-bench` / custom | How fast it reads your input |
| **Time to first token (TTFT)** | Timestamp diff | How long user waits after pressing Enter |
| **Inter-token latency (ITL) mean** | Per-token timestamps | Average gap between tokens |
| **Inter-token latency P95** | Per-token timestamps | Worst-case stutter (95th percentile) |
| **Inter-token latency P99** | Per-token timestamps | Extreme stutter |
| **ITL std deviation** | Per-token timestamps | Consistency — is it smooth or jerky? |
| **Model load time** | Time from launch to ready | Cold start penalty |
| **Total wall time for 500 tokens** | Stopwatch | End-to-end real-world time |

### C. Speed at Different Context Lengths (Does it slow down?)

| Metric | Context Size | What it tells us |
|--------|-------------|-----------------|
| **tg at context 512** | 512 tokens | Short conversation speed |
| **tg at context 1024** | 1K tokens | Medium conversation |
| **tg at context 2048** | 2K tokens | Longer conversation |
| **tg at context 4096** | 4K tokens | Long context — still usable? |
| **tg at context 8192** | 8K tokens | Stress test (will it OOM?) |
| **TTFT at context 512** | 512 tokens | First token with short prompt |
| **TTFT at context 2048** | 2K tokens | First token with long prompt |
| **TTFT at context 4096** | 4K tokens | First token with very long prompt |

### D. Long-Running Stability (Does it degrade over time?)

| Metric | Tool | What it tells us |
|--------|------|-----------------|
| **tok/s at minute 0** | Sample at start | Baseline speed |
| **tok/s at minute 5** | Sample after 5 min | Early degradation? |
| **tok/s at minute 15** | Sample after 15 min | Thermal throttling kicking in? |
| **tok/s at minute 30** | Sample after 30 min | Sustained performance |
| **CPU temperature over time** | `sensors` / `/sys/class/thermal/` | Thermal throttling detection |
| **CPU frequency over time** | `/proc/cpuinfo` or `turbostat` | Is CPU downclocking? |
| **RSS over time (30 min)** | Sampled every 30s | Memory leak detection |
| **Disk I/O over time** | `iostat` sampled every 10s | mmap thrashing pattern |

### E. Quality Metrics (Is the output good?)

| Metric | Tool | What it tells us |
|--------|------|-----------------|
| **Perplexity (WikiText-2)** | `llama-perplexity` | Overall language quality |
| **MMLU-Pro (5-shot subset)** | `lm-evaluation-harness` (if installed) | Knowledge/reasoning ability |
| **Repetition rate** | 4-gram analysis on 500-token generation | Does aggressive quant cause loops? |
| **Coherence (5 prompts)** | Word count + preview on standard prompts | Does it produce sensible output? |

### F. System Resource Metrics (What's happening under the hood?)

| Metric | Tool | What it tells us |
|--------|------|-----------------|
| **CPU utilization %** | `mpstat` / `/proc/stat` | Are all cores used? |
| **CPU utilization per core** | `mpstat -P ALL` | Load balance across cores |
| **Context switches/sec** | `/proc/PID/status` | OS scheduling overhead |
| **Disk read MB/s during inference** | `iostat -x 1` | mmap page faults = thrashing |
| **Disk read IOPS** | `iostat -x 1` | Random vs sequential access pattern |
| **Page faults (major)** | `/proc/PID/stat` | Pages loaded from disk (slow) |
| **Page faults (minor)** | `/proc/PID/stat` | Pages from cache (fast) |
| **GGUF file size on disk** | `ls -la` | Download size for users |
| **CPU instruction set used** | Check AVX2/AVX-512 usage | Is the engine optimizing for this CPU? |

### G. User Experience Metrics (Would a real person use this?)

| Metric | How | What it tells us |
|--------|-----|-----------------|
| **"Usable" threshold** | tg > 5 tok/s AND TTFT < 5s | Binary: yes/no for chat |
| **"Good" threshold** | tg > 10 tok/s AND TTFT < 2s | Comfortable experience |
| **"Excellent" threshold** | tg > 20 tok/s AND TTFT < 1s | Feels instant |
| **Time to generate 100-word reply** | Wall clock | Real-world answer time |
| **Time to generate 500-word reply** | Wall clock | Long answer time |
| **Multi-turn penalty** | tg at turn 1 vs turn 5 vs turn 10 | Does conversation get slower? |
| **Recovery after long prompt** | TTFT after pasting 2K tokens | Simulates "paste a document + ask question" |
| **Concurrent with stress** | Run with `stress --cpu 2` background | Simulates user running other apps |

### H. Model Metadata (For analysis)

| Metric | Source | Why |
|--------|--------|-----|
| **Model name** | Config | Identification |
| **Architecture** | Config | Dense / MoE / Ternary |
| **Total parameters** | Config | Full model size |
| **Active parameters** | Config | MoE activated params |
| **Quantization level** | Filename | Q2/Q3/Q4/Q5/Q8 |
| **GGUF file size** | Disk | Download burden |
| **Vocabulary size** | Config | Affects memory |
| **Max context window** | Config | Advertised capability |
| **Number of layers** | Config | Architecture depth |
| **Number of experts (MoE)** | Config | MoE structure |
| **Active experts per token** | Config | MoE efficiency |
| **Inference engine** | Test config | llama.cpp / Ollama / etc. |
| **Engine version** | Test config | Reproducibility |
| **Memory tier** | Test config | 12GB / 14GB / 15.5GB |

---

## Total Metrics Per Experiment: ~70+ data points

---

## Experiment Matrix

### What gets tested

```
Category A (MoE):     4 models × 4 quants × 3 tiers × 1 engine = 48 experiments
  + Llama 4 Scout IQ1_M × 3 tiers = 3 experiments (boundary test)
Category B (Dense):   3 models × 3 quants × 3 tiers × 1 engine = 27 experiments
Category C (Ternary): 2 models × 1 quant  × 3 tiers × 1 engine = 6 experiments
Category D (Control): 1 model  × 3 quants × 3 tiers × 1 engine = 9 experiments
Extra engines bench-3: ~11 models × 3 tiers × 3 engines = ~99 experiments (llamafile/bitnet/PowerInfer)
```

### Subtract impossible combos
- Dense 27-32B at Q4+ likely OOM at 12GB → recorded as OOM data (still run)
- PowerInfer only supports ReLU models (very limited) → many will fail gracefully
- Llama 4 Scout is 35GB even at IQ1_M → guaranteed OOM but proves boundary

### Total: ~190 quick benchmarks (Phase 1) + ~100 deep tests (Phases 2-7)

### Time estimate

| Phase | Count | Time each | Total time |
|-------|-------|-----------|------------|
| Phase 0: Model downloads | — | — | ~2-3 hours (parallel) |
| Phase 1: Quick benchmarks | ~90 per server | ~2 min | ~3 hours |
| Phase 1b: Extra engines (bench-3) | ~99 | ~2 min | ~3.5 hours |
| Phase 2: Context scaling | ~20 (passing models) | ~10 min | ~3.5 hours |
| Phase 3: 30-min stability | 3 (top models) | 30 min | ~1.5 hours |
| Phase 4: Multi-turn (10 turns) | 3 | ~15 min | ~45 min |
| Phase 5: Concurrent load | 3 | ~5 min | ~15 min |
| Phase 6: Quality evaluation | ~5 | ~20 min | ~1.5 hours |
| Phase 7: Recovery & burst | 1 per server | ~5 min | ~5 min |
| **Total per server** | | | **~14 hours** |
| **On 3 servers parallel** | | | **~14 hours** |
| **Cost: 3 × 14hr × €0.038** | | | **~€1.60** |

---

## Server Assignment

| Server | Models | Disk Budget | Est. Experiments |
|--------|--------|-------------|-----------------|
| **bench-1** | Qwen3.5-35B-A3B (Q2-Q5) + Llama 4 Scout IQ1_M | 102 GB | ~51 quick + deep tests |
| **bench-2** | GLM-4.7-Flash (Q2-Q5) + Nemotron-3-Nano (Q2+Q3 only) + Ministral-14B (Q4/Q5/Q8) | 126 GB | ~79 quick + deep tests |
| **bench-3** | Gemma-27B (Q2-Q4) + Mistral-24B (Q2-Q4) + DeepSeek-32B (Q2-Q4) + Falcon-H1R-7B (Q4/Q8) + BitNet 2B4T | 127 GB | ~99 quick + extra engines |

*bench-3 also runs llamafile, bitnet.cpp, and PowerInfer on all its models.*

---

## Perplexity Testing (Quality Measurement)

Run separately on a subset (best-fitting configs per model):
- Dataset: WikiText-2 test set
- For each model: test Q2_K vs Q3_K_M vs Q4_K_M vs native (if available)
- This tells us: "at what quant level does this model become useless?"

---

## Test Procedures

### Test 1: Quick Benchmark (per model/quant/engine/tier combo — ~5 min)
- Load model
- Record load time, initial RAM
- Generate 500 tokens with 512-token prompt → measure tg, pp, TTFT, ITL, RAM
- Record outcome: FITS / THRASHES / OOM
- Record all system metrics during run

### Test 2: Context Scaling (per model that passes Test 1 — ~10 min)
- Same model, increase context: 512 → 1024 → 2048 → 4096 → 8192
- At each level: measure tg, TTFT, RAM, disk I/O
- Stop when OOM or tg < 1 tok/s

### Test 3: Long-Running Stability (top 5 best combos only — ~30 min each)
- Run continuous generation for 30 minutes
- Sample tok/s, RAM, CPU temp, CPU freq every 30 seconds
- Detect: thermal throttling, memory leaks, speed degradation

### Test 4: Multi-Turn Conversation (top 5 best combos — ~15 min each)
- Simulate 10-turn conversation (user prompt → model reply → user prompt → ...)
- Measure tok/s and TTFT at each turn
- Detect: does it slow down as conversation grows?

### Test 5: Concurrent Load (top 5 best combos — ~10 min each)
- Run model + `stress --cpu 2` in background (simulates user's other apps)
- Measure tok/s drop compared to clean run
- How much does "real world" hurt performance?

### Test 6: Quality Evaluation (per model at best-fitting quant — ~20 min each)
- Perplexity on WikiText-2 (via `llama-perplexity`)
- MMLU-Pro 5-shot subset (100 questions, via `lm-evaluation-harness` if installed)
- Repetition rate measurement (4-gram repetition in 500-token generation)
- 5 coherence prompts (response length and preview)
- Compare across quant levels for same model

### Test 7: Recovery & Burst (1 per server — ~5 min each)
- **OOM recovery**: Load model that OOMs at 12GB, then load one that fits — measure recovery time
- **Burst test**: 3 rapid inferences back-to-back with no cooldown — measure consistency
- **Cold vs warm start**: Drop caches, load model (cold), then load again (warm) — measure speedup ratio

---

## Output Format

Every experiment produces one JSON file with full data:

```json
{
  "metadata": {
    "model": "Qwen3.5-35B-A3B",
    "architecture": "MoE",
    "total_params_b": 35,
    "active_params_b": 3,
    "quant": "Q4_K_M",
    "gguf_size_gb": 12.3,
    "engine": "llama.cpp",
    "engine_version": "b4567",
    "memory_tier": "12GB",
    "server": "locallm-bench-1",
    "timestamp": "2026-03-04T14:30:00Z",
    "num_layers": 64,
    "num_experts": 128,
    "active_experts": 8,
    "vocab_size": 152064,
    "max_context": 32768
  },
  "memory": {
    "outcome": "FITS",
    "ram_at_load_mb": 9800,
    "ram_at_512_tokens_mb": 10100,
    "ram_at_2048_tokens_mb": 10800,
    "ram_at_4096_tokens_mb": 11400,
    "peak_rss_mb": 11400,
    "peak_virtual_mb": 14200,
    "kv_cache_estimate_mb": 600,
    "memory_growth_mb_per_1k_tokens": 150,
    "major_page_faults": 12,
    "minor_page_faults": 340000
  },
  "speed": {
    "model_load_time_sec": 4.2,
    "tokens_per_sec_generation": 8.3,
    "tokens_per_sec_prompt": 12.1,
    "ttft_ms": 1200,
    "itl_mean_ms": 120,
    "itl_p95_ms": 145,
    "itl_p99_ms": 210,
    "itl_std_ms": 18,
    "wall_time_500_tokens_sec": 62,
    "time_100_word_reply_sec": 15,
    "time_500_word_reply_sec": 75
  },
  "context_scaling": {
    "tg_at_ctx_512": 8.3,
    "tg_at_ctx_1024": 7.9,
    "tg_at_ctx_2048": 7.1,
    "tg_at_ctx_4096": 5.8,
    "tg_at_ctx_8192": null,
    "ttft_at_ctx_512_ms": 1200,
    "ttft_at_ctx_2048_ms": 3400,
    "ttft_at_ctx_4096_ms": 6800,
    "max_working_context": 4096
  },
  "stability": {
    "tg_at_min_0": 8.3,
    "tg_at_min_5": 8.1,
    "tg_at_min_15": 7.8,
    "tg_at_min_30": 7.7,
    "cpu_temp_start_c": 42,
    "cpu_temp_peak_c": 68,
    "cpu_freq_start_mhz": 2800,
    "cpu_freq_min_mhz": 2400,
    "rss_at_min_0_mb": 10100,
    "rss_at_min_30_mb": 10150,
    "memory_leak_detected": false,
    "thermal_throttle_detected": false
  },
  "multi_turn": {
    "tg_turn_1": 8.3,
    "tg_turn_3": 7.5,
    "tg_turn_5": 6.8,
    "tg_turn_10": 5.2,
    "ttft_turn_1_ms": 1200,
    "ttft_turn_5_ms": 2800,
    "ttft_turn_10_ms": 5100,
    "degradation_pct_by_turn_10": 37
  },
  "concurrent_load": {
    "tg_clean": 8.3,
    "tg_with_stress_cpu_2": 5.1,
    "performance_drop_pct": 38.5
  },
  "quality": {
    "perplexity_wikitext2": 7.82,
    "perplexity_delta_vs_fp16": 0.45,
    "mmlu_pro_5shot_pct": 72.3,
    "humaneval_pass_at_1_pct": 45.2,
    "arc_challenge_pct": 68.1,
    "repetition_rate_pct": 1.2
  },
  "system": {
    "cpu_utilization_pct": 98,
    "cpu_per_core_pct": [99, 98, 97, 98],
    "context_switches_per_sec": 1200,
    "disk_read_mb_sec_avg": 0.2,
    "disk_read_mb_sec_peak": 1.1,
    "disk_iops_avg": 15,
    "cpu_instruction_set": "AVX2"
  },
  "user_experience": {
    "usable": true,
    "good": false,
    "excellent": false,
    "recovery_ttft_after_2k_paste_ms": 4500
  }
}
```

All results aggregated into `results/` directory, one JSON per experiment + combined `results.jsonl`.

---

## Success Criteria

After all experiments, we answer:

| Question | Data used |
|----------|-----------|
| Which model+quant gives best quality at 12GB? | Lowest perplexity that FITS at 12GB |
| Is MoE actually better than dense for 16GB? | Compare same-quality MoE vs dense (perplexity + tok/s) |
| Does llamafile really beat Ollama 3-4x on CPU? | Direct comparison same model/quant/tier |
| Are ternary models ready to replace quantized? | BitNet quality vs Q4 of larger model at same RAM |
| What's the max usable context on 16GB? | Context scaling data — where does tg drop below 5 |
| Does it degrade over 30 min? | Stability test — tok/s at min 0 vs min 30 |
| Is it usable while running other apps? | Concurrent load — tok/s drop with stress |
| Does conversation slow down over 10 turns? | Multi-turn degradation % |
| What's the real download size users need? | GGUF file sizes |
| Where is the gap for our novel contribution? | Whatever doesn't work well enough |

---

## Phase 2: After Results

Based on data, identify the most promising research direction:
1. MoE expert offloading optimization
2. Hybrid ternary-MoE architecture
3. Adaptive per-layer quantization
4. KV cache compression for long context on 16GB
5. Something we haven't thought of yet

---

## Notes

- bench-1 and bench-2 are CCX23 (4 dedicated AMD EPYC cores) — directly comparable
- bench-3 is CX43 (8 shared AMD EPYC cores) — results comparable for same-server comparisons only
- No swap on any server — honest OOM behavior (cgroup MemorySwapMax=0)
- All models downloaded from HuggingFace (GGUF format from bartowski, unsloth, mistralai, tiiuae)
- Ternary models use bitnet.cpp native format (Microsoft BitNet b1.58-2B-4T)
- PowerInfer has LIMITED model support (ReLU activation only) — may only work for a few tests
- Peak RSS measured from llama.cpp's own memory breakdown report (b8199+ format)
- Raw logs kept under 1KB per experiment (stderr + last 10 lines of stdout only)
- All experiments have skip-if-completed logic — safe to restart after failures
