# Roadmap

## Phase 1: Complete v1

Fix the gaps in our first round of experiments. Nothing else makes sense until these are solid.

- [ ] Fix the context scaling dedup bug in `orchestrator.sh`
- [ ] Re-run context scaling on all passing models (ctx 512 / 1K / 2K / 4K / 8K)
- [ ] Pull raw perplexity logs from the servers and parse WikiText-2 scores
- [ ] Backfill quality JSON files with extracted perplexity data
- [ ] Analyze the llamafile results already collected on bench-3
- [ ] Debug Falcon-H1R-7B — figure out if it was a download failure or engine issue
- [ ] Debug BitNet 2B4T — check if bitnet.cpp was installed, get it running
- [ ] Publish updated analysis with the fixed data

## Phase 2: Engine & Quantization Comparison

Test whether different engines or quantization methods change the picture.

- [ ] Install llamafile on a test server, run head-to-head vs llama.cpp on the same models
- [ ] Test i-quants (IQ4_XS, IQ3_M) — reportedly beat standard quants at smaller size
- [ ] Test Unsloth Dynamic 2.0 adaptive per-layer quantization on GLM-4.7-Flash
- [ ] Compare i-quant and Dynamic 2.0 quality against uniform Q2_K at the same file size
- [ ] Test KV cache quantization (`--cache-type-k q4_0 --cache-type-v q4_0`) — does freed RAM let us use Q3_K_M without OOM?

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

## Phase 5: Real Hardware & User Profiles

Our EPYC servers have better memory bandwidth than most consumer PCs. Validate on real hardware.

- [ ] Test on a budget consumer PC (DDR4, AMD Ryzen 5 or Intel i5, 16GB)
- [ ] Measure the gap vs EPYC — how much slower is real consumer hardware?
- [ ] Test 8GB configurations — what (if anything) is usable for the 8GB crowd?
- [ ] Test AMD Ryzen AI / NPU acceleration if available
- [ ] Build user profiles mapping use cases to recommended setups:
  - [ ] Developer, 16GB — code assistant config
  - [ ] Lawyer / journalist, 16GB — private document Q&A config
  - [ ] Student, 8GB laptop — what's possible
  - [ ] Offline / air-gapped user — full self-contained setup

## Phase 6: Ship It

- [ ] Build a one-command installer that detects hardware and sets up the right model
- [ ] Build a recommendation CLI — input specs, get back best setup with expected performance
- [ ] Submit results to LocalScore for community visibility
- [ ] Publish updated paper with task benchmarks and optimization results
- [ ] Write up findings as blog posts for broader reach
