# Roadmap

## Status of What's Done

### Completed (Phase 1 — Linux on Server Hardware)
- [x] 150 experiments on 3 Hetzner servers (EPYC Milan/Rome, 16GB, no swap)
- [x] 10 models, 5 quantization levels, 3 memory tiers
- [x] 7 test types: quick bench, context scaling, stability, multi-turn, concurrent, quality, recovery
- [x] Finding: GLM-4.7-Flash 30B MoE at Q2_K = 7.2 tok/s — only model above 5 tok/s
- [x] Finding: MoE is the only viable architecture for 30B+ on 16GB
- [x] Paper and raw data published

### Completed (Exploratory — Windows on Different Hardware)
- [x] Windows 11 OS overhead measured: 2.17 GB
- [x] 9 small models tested via Ollama on Azure D4s_v3 (Xeon 8272CL)
- [x] GLM-4.7-Flash 30B confirmed thrashing on Windows+Xeon combo
- [x] Data labeled as exploratory (different CPU, different engine — not comparable to Linux results)

### Known Bugs from Phase 1
- [ ] Context scaling dedup bug — only ctx=512 tested for most models
- [ ] Perplexity parser broken — all WikiText-2 scores came back null
- [ ] Falcon-H1R-7B and BitNet 2B4T produced no results
- [ ] bench-3 alternative engines (llamafile, bitnet.cpp, PowerInfer) not installed

---

## Phase 2: Fix Phase 1 Gaps

Low-cost fixes using existing infrastructure.

- [ ] Fix context scaling dedup bug in `orchestrator.sh`
- [ ] Re-run context scaling on passing models (ctx 512 / 1K / 2K / 4K / 8K)
- [ ] Pull raw perplexity logs and fix the parser regex
- [ ] Debug Falcon-H1R-7B and BitNet 2B4T failures
- [ ] Analyze any llamafile results already collected on bench-3

## Phase 3: Cross-OS Comparison (Same Hardware)

**Why**: We cannot make any Linux vs Windows speed claims without testing both on identical hardware with the same engine and same models. This is the most important gap.

**Approach**: Use a single cloud VM type that offers both Linux and Windows images.

- [ ] Provision two Azure D4s_v3 VMs (or equivalent): one Ubuntu, one Windows 11
- [ ] Install Ollama on both (same version, same engine)
- [ ] Run identical test suite: same 9+ models, same prompts, same config (300 tokens, ctx 2048, temp 0.7, seed 42)
- [ ] Also test GLM-4.7-Flash 30B via llama.cpp on both
- [ ] Measure: generation tok/s, prompt tok/s, TTFT, model load time, RAM consumed
- [ ] Publish results with honest comparison — the Xeon 8272CL is a 2019 server CPU, so this tells us the OS delta on old hardware, not what consumers get
- [ ] Delete both VMs when done (estimated cost: ~$2-4)

**What this will answer**: The exact speed penalty of Windows vs Linux on identical (server) hardware.

**What this will NOT answer**: Consumer performance. That requires Phase 4.

## Phase 4: Consumer Hardware Validation

**Why**: Our EPYC Milan (2.0 GHz) has lower single-thread than consumer CPUs (i5-13400, Ryzen 5 7600). We need to verify our results hold and measure the speed difference.

**Options** (in order of preference):
1. **Hetzner AX42 dedicated server** — Ryzen 7 PRO 8700GE, ~105 single-thread score, genuinely consumer-representative. Run Linux tests, compare to EPYC results. ~EUR 50/month, need a few hours.
2. **Physical hardware** — Borrow or buy a budget 16GB PC (i5-13400 + DDR4). Run both Linux and Windows. Most realistic but requires physical access.
3. **Cloud gaming / remote desktop** — Services like Shadow PC provide consumer-grade hardware (Ryzen, GeForce). Could test Windows on real consumer CPU. Availability and cost varies.

- [ ] Choose approach and provision hardware
- [ ] Run same test suite as Phase 1 (all models that fit, all quant levels)
- [ ] Compare to EPYC results — measure the actual speed gap
- [ ] If using dual-boot or two machines: run same tests on Windows for true consumer cross-OS comparison
- [ ] Publish updated paper with consumer-validated numbers

## Phase 5: Engine & Quantization Comparison

Test whether different engines or quantization methods change the picture.

- [ ] llamafile head-to-head vs llama.cpp on same models
- [ ] Test i-quants (IQ4_XS, IQ3_M) — reportedly beat standard quants at smaller size
- [ ] Test Unsloth Dynamic 2.0 adaptive per-layer quantization on GLM-4.7-Flash
- [ ] Test KV cache quantization (`--cache-type-k q4_0 --cache-type-v q4_0`)
- [ ] Test Ollama vs llama.cpp on Linux (quantify the convenience vs speed tradeoff)

## Phase 6: Speed Optimization

Push the winner (GLM-4.7-Flash) further.

- [ ] Test speculative decoding with a small draft model paired with GLM-4.7-Flash
- [ ] Combine best quantization + speculative decoding — what's the ceiling on 16GB?
- [ ] Test any new MoE models released since Phase 1

## Phase 7: Real-World Task Benchmarks

Speed alone doesn't tell us if the output is useful.

- [ ] RAG: 5 documents, 20 questions with known answers, score accuracy per quant level
- [ ] Code assistant: 10 real tasks, score correctness, measure TTFT
- [ ] Summarization: 10 long texts, compare against reference summaries
- [ ] Multi-turn chat: 20 turns, measure quality + speed degradation together

## Phase 8: Ship It

- [ ] One-command installer per OS (bash for Linux/macOS, PowerShell for Windows)
- [ ] Recommendation CLI — input specs + OS, get back best setup
- [ ] Updated paper covering all platforms and consumer hardware
- [ ] Blog posts for broader reach
