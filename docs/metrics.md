# Metrics Collected Per Experiment

Every experiment produces a structured JSON file with the following data points.

## Memory

| Metric | Source | What it tells us |
|--------|--------|-----------------|
| Peak RSS (Resident Set) | `/proc/PID/status` VmRSS | Actual physical RAM used |
| Peak Virtual Memory | `/proc/PID/status` VmPeak | Total memory mapped |
| RAM at model load | Sampled before first token | Memory just to load the model |
| RAM at 512 tokens | Sampled during generation | Growth after short conversation |
| KV cache size | Estimate from context x layers x dims | How much context costs in RAM |
| Memory growth rate | Delta RSS over time | Detecting memory leaks |
| Outcome | Custom script | FITS / THRASHES / OOM |
| Major page faults | `/proc/PID/stat` | Pages loaded from disk (slow) |
| Minor page faults | `/proc/PID/stat` | Pages from cache (fast) |

## Speed

| Metric | Source | What it tells us |
|--------|--------|-----------------|
| Tokens/sec generation (tg) | llama.cpp output | Output speed -- main usability metric |
| Tokens/sec prompt processing (pp) | llama.cpp output | How fast it reads your input |
| Time to first token (TTFT) | Timestamp diff | How long user waits after pressing Enter |
| Inter-token latency mean | Per-token timestamps | Average gap between tokens |
| Inter-token latency P95 | Per-token timestamps | Worst-case stutter |
| Inter-token latency P99 | Per-token timestamps | Extreme stutter |
| ITL std deviation | Per-token timestamps | Consistency |
| Model load time | Time from launch to ready | Cold start penalty |
| Wall time for 500 tokens | Stopwatch | End-to-end real-world time |

## System Resources

| Metric | Source | What it tells us |
|--------|--------|-----------------|
| CPU utilization % | `mpstat` / `/proc/stat` | Are all cores used? |
| CPU utilization per core | `mpstat -P ALL` | Load balance across cores |
| Context switches/sec | `/proc/PID/status` | OS scheduling overhead |
| Disk read MB/s | `iostat -x 1` | mmap thrashing indicator |
| Disk IOPS | `iostat -x 1` | Random vs sequential access |
| GGUF file size on disk | `ls -la` | Download size for users |
| CPU instruction set | Check AVX2/AVX-512 | Engine optimization level |

## Quality

| Metric | Source | What it tells us |
|--------|--------|-----------------|
| Perplexity (WikiText-2) | `llama-perplexity` | Overall language quality |
| Repetition rate | 4-gram analysis | Does aggressive quant cause loops? |
| Coherence (5 prompts) | Word count + preview | Does it produce sensible output? |

## Model Metadata

| Field | Why |
|-------|-----|
| Model name, architecture | Identification |
| Total / active parameters | Size comparison |
| Quantization level | Q2/Q3/Q4/Q5/Q8 |
| GGUF file size | Download burden |
| Inference engine + version | Reproducibility |
| Memory tier | 12GB / 14GB / 15.5GB |
| Server specs | Hardware context |
