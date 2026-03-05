# Roadmap

## Phase 1: Fix & Complete

The v1 benchmarks have gaps. These need fixing before we build on top.

1. **Re-run context scaling** — test all passing models at ctx 512/1K/2K/4K/8K. The dedup bug in the orchestrator skipped everything after ctx 512. Fix the bug, re-run.
2. **Fix perplexity extraction** — the logs exist on the servers, the parser just didn't extract the scores. Pull the raw logs, parse WikiText-2 perplexity, backfill the quality JSON files.
3. **Debug Falcon-H1R & BitNet** — zero results from either model. Figure out if it was a download failure, engine incompatibility, or something else. Get them running.
4. **Install & benchmark llamafile** — proper head-to-head comparison vs llama.cpp on the same models, same hardware.
5. **Analyze bench-3 llamafile data** — there are already some llamafile results in the bench-3 data. Include them in the published analysis.

## Phase 2: Optimization Experiments

We know GLM-4.7-Flash works. Can we make it faster?

6. **Speculative decoding** — pair a small draft model (Qwen3-0.6B or similar) with GLM-4.7-Flash. Measure the actual speedup on 16GB hardware.
7. **Unsloth Dynamic 2.0 quants** — test adaptive per-layer quantization. Compare output quality against uniform Q2_K at the same file size.
8. **KV cache quantization** — run GLM with `--cache-type-k q4_0 --cache-type-v q4_0`. See if the freed RAM lets us use Q3_K_M without OOM.
9. **Combined stack** — speculative decoding + KV cache quant + best quantization together. What's the actual ceiling on 16GB?

## Phase 3: Real-World Task Benchmarks

Speed without quality data is half the story. We need to test whether these models can do useful work at aggressive quantization levels.

10. **RAG (Retrieval-Augmented Generation)** — build a test set: 5 documents (1-3 pages each), 20 questions with known answers. Score accuracy at each quant level. Test with 2K and 4K context windows. This is the killer use case for local LLMs — private docs, no cloud.
11. **Code assistant** — 10 real code tasks (explain, refactor, debug, complete). Score correctness. Measure TTFT since that's what developers actually feel when they hit Enter.
12. **Summarization** — 10 long texts (emails, articles, meeting notes). Compare generated summaries against reference summaries. This tests prompt processing speed with 2K+ token inputs.
13. **Data extraction** — 10 invoices and forms, extract structured JSON output. Measure field-level accuracy. The question: does Q2_K hallucinate field values?
14. **Multi-turn chat** — 20-turn realistic conversations (not ML trivia). Measure output quality degradation alongside the speed degradation we already captured.

## Phase 4: Real Hardware & User Profiles

Our EPYC servers have good memory bandwidth. Real consumer PCs will be slower.

15. **Test on actual consumer hardware** — cheap Dell or Lenovo with DDR4, AMD Ryzen 5, 16GB RAM. How much worse is it compared to EPYC?
16. **Build user profiles** — map use cases to recommended configurations:
    - "Developer, 16GB, wants code help" -> model X, quant Y, engine Z
    - "Lawyer, 16GB, needs private doc Q&A" -> model X, quant Y, RAG setup
    - "Student, 8GB laptop" -> what's possible at all?
17. **Test 8GB configurations** — a big chunk of the audience has 8GB machines. What (if anything) works there?

## Phase 5: Ship It

18. **One-command installer** — detect hardware, download the right model, configure everything automatically.
19. **Recommendation CLI** — input your specs, get back your best setup with expected performance numbers.
20. **Publish updated findings** — revised paper with task benchmarks and optimization results.

## Priority

Phase 1 first (fixes credibility). Then Phase 3 items 10-11 in parallel with Phase 2 items 6-7 — these answer the two biggest open questions: "is it actually useful?" and "can we make it faster?" Phase 4 when we have clear winners. Phase 5 when we have a story worth shipping.
