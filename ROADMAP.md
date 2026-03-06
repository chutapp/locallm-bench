# Roadmap

## Phase 1: Complete v1 & Cross-Platform

Fix the gaps from our first round and test on the OS most people actually use.

### v1 Fixes
- [ ] Fix the context scaling dedup bug in `orchestrator.sh`
- [ ] Re-run context scaling on all passing models (ctx 512 / 1K / 2K / 4K / 8K)
- [ ] Pull raw perplexity logs from the servers and parse WikiText-2 scores
- [ ] Backfill quality JSON files with extracted perplexity data
- [ ] Analyze the llamafile results already collected on bench-3
- [ ] Debug Falcon-H1R-7B — figure out if it was a download failure or engine issue
- [ ] Debug BitNet 2B4T — check if bitnet.cpp was installed, get it running

### Windows Testing (priority — most users run Windows)
- [ ] Set up a Windows 10/11 test environment with 16GB RAM (real hardware or Azure/AWS VM)
- [ ] Measure actual available RAM after Windows + typical background apps (browser, antivirus, services)
- [ ] Run the same top models from v1 (GLM-4.7-Flash Q2_K/Q3_K_M, Mistral-Small Q2_K, Ministral Q4_K_M)
- [ ] Test through tools real users use: Ollama, LM Studio, GPT4All — not just raw llama-cli
- [ ] Compare Windows vs Linux performance on identical hardware
- [ ] Measure model loading time on NTFS vs ext4
- [ ] Test with a browser + typical apps running (real user scenario, not clean boot)
- [ ] Document the Windows-specific setup and gotchas

### macOS Testing
- [ ] Test on an Intel Mac with 16GB (not Apple Silicon — that's a different story with unified memory)
- [ ] Test through Ollama and LM Studio on macOS

### Publish
- [ ] Updated analysis covering all three operating systems
- [ ] OS comparison table: same model, same hardware, Linux vs Windows vs macOS

## Phase 2: Engine & Quantization Comparison

Test whether different engines or quantization methods change the picture.

- [ ] Install llamafile on a test server, run head-to-head vs llama.cpp on the same models
- [ ] Test i-quants (IQ4_XS, IQ3_M) — reportedly beat standard quants at smaller size
- [ ] Test Unsloth Dynamic 2.0 adaptive per-layer quantization on GLM-4.7-Flash
- [ ] Compare i-quant and Dynamic 2.0 quality against uniform Q2_K at the same file size
- [ ] Test KV cache quantization (`--cache-type-k q4_0 --cache-type-v q4_0`) — does freed RAM let us use Q3_K_M without OOM?
- [ ] Test engine performance differences across operating systems (does llamafile close the gap on Windows?)

## Phase 3: Speed Optimization

Push the winner (GLM-4.7-Flash) further. Can we get from 7 tok/s to 12+?

- [ ] Test speculative decoding with a small draft model (Qwen3-0.6B or similar) paired with GLM-4.7-Flash
- [ ] Measure speculative decoding speedup at different draft lengths
- [ ] Combine the best from Phase 2 + speculative decoding — what's the actual ceiling on 16GB?
- [ ] Test any new MoE models released since v1 (SmallThinker-21B, newer GLM, etc.)

## Phase 4: Real-World Task Benchmarks

Speed alone doesn't tell us if the output is useful. Test actual tasks people would run locally.

### RAG (Private Document Q&A)
- [ ] Build a test set: 5 documents (1-3 pages each), 20 questions with known answers
- [ ] Score answer accuracy at each quant level (Q2_K, Q3_K_M, i-quants, Dynamic 2.0)
- [ ] Test at 2K and 4K context windows
- [ ] Measure how RAG context length affects speed and quality together

### Code Assistant
- [ ] Create 10 real code tasks (explain, refactor, debug, complete)
- [ ] Score correctness of outputs
- [ ] Measure TTFT — that's what developers feel when they hit Enter

### Summarization
- [ ] Collect 10 long texts (emails, articles, meeting notes)
- [ ] Generate summaries, compare against reference summaries
- [ ] Measure prompt processing speed with 2K+ token inputs

### Data Extraction
- [ ] Collect 10 invoices and forms
- [ ] Extract structured JSON, measure field-level accuracy
- [ ] Answer the question: does Q2_K hallucinate field values?

### Multi-Turn Chat
- [ ] Run 20-turn realistic conversations (not ML trivia)
- [ ] Measure output quality degradation alongside speed degradation
- [ ] Compare quality at turn 1 vs turn 10 vs turn 20

### Cross-Platform Task Comparison
- [ ] Run all task benchmarks on Windows and Linux
- [ ] Check if task quality differs across OS (it shouldn't, but verify)
- [ ] Measure TTFT and throughput differences per OS per task

## Phase 5: Real Hardware & User Profiles

Our EPYC servers have better memory bandwidth than most consumer PCs. Validate on real hardware.

- [ ] Test on a budget consumer PC (DDR4, AMD Ryzen 5 or Intel i5, 16GB, Windows 11)
- [ ] Test on a budget consumer PC running Linux for direct comparison
- [ ] Measure the gap vs EPYC — how much slower is real consumer hardware?
- [ ] Test 8GB configurations — what (if anything) is usable for the 8GB crowd?
- [ ] Test 8GB on Windows specifically — after OS overhead, is anything left?
- [ ] Test AMD Ryzen AI / NPU acceleration if available
- [ ] Build user profiles mapping use cases to recommended setups:
  - [ ] Developer on Windows, 16GB — code assistant config
  - [ ] Developer on Linux, 16GB — code assistant config
  - [ ] Lawyer / journalist on Windows, 16GB — private document Q&A config
  - [ ] Student on Windows, 8GB laptop — what's possible
  - [ ] Offline / air-gapped user — full self-contained setup per OS

## Phase 6: Ship It

- [ ] Build a one-command installer per OS (bash for Linux/macOS, PowerShell for Windows)
- [ ] Build a recommendation CLI — input specs + OS, get back best setup with expected performance
- [ ] Submit results to LocalScore for community visibility
- [ ] Publish updated paper with cross-platform task benchmarks and optimization results
- [ ] Write up findings as blog posts for broader reach
