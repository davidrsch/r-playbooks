---
name: r-profile
version: 1.0.0
context-mode: Fork
description: Profile R code for performance bottlenecks using profvis, bench, and rprof: produces a report, never auto-modifies code
trigger: both
trigger-patterns:
  - "profile *"
  - "profvis *"
  - "performance *"
  - "slow *"
  - "optimize *"
  - "benchmark *"
argument-hint: "--code <expression> [--tool profvis|bench|rprof|both] [--iterations 10]"
parameters:
  code:
    type: String
    required: true
    hint: "R expression or function call to profile (e.g., 'my_function(data)')"
  tool:
    type: String
    required: false
    default: "profvis"
    enum: ["profvis", "bench", "rprof", "both"]
    hint: "Profiling tool: profvis (flame graph), bench (timing), rprof (sampling), both (profvis + bench)"
  iterations:
    type: Number
    required: false
    default: 5
    min: 1
    max: 1000
    hint: "Number of iterations for bench timing (more = more stable estimates)"
steps:
  - id: analyze-code
    inline-prompt: |
      Analyze the code to be profiled before running:

      1. Read the source of the function(s) involved: `{{params.code}}`
      2. Identify:
         - Loops that could be vectorized
         - Repeated computations that could be cached
         - Data I/O (file reads, database queries)
         - Memory allocations (growing vectors in loops)
         - Package boundary crossings (.Call, .C, .Fortran)
         - S4/R6/RC method dispatch overhead
      3. Note the expected complexity: O(n), O(n²), etc.
      4. Run `tracemem()` on key objects to detect copy-on-write triggers:
         `tracemem(x); y <- x; y[1] <- 999`: if tracemem reports a duplicate,
         you've found a copy-on-write that can be avoided.
      5. Use `lobstr::obj_size()` to inspect deep memory usage of objects.
      6. Report: code structure analysis, potential bottlenecks.
    output: code_analysis

  - id: run-profvis
    requires: [analyze-code]
    inline-prompt: |
      The user selected tool: {{params.tool}}.
      If the tool is "profvis" or "both", run profvis to generate a flame graph and performance profile.

      1. Run: `profvis::profvis({ {{params.code}} })`
         To profile a specific section interactively:
         `profvis::pause()` / `profvis::resume()` to toggle profiling on/off.
         For memory profiling, use: `profvis::profvis({ {{params.code}} }, prof_output = "memory")`
      2. Analyze the output:
         - **Flame Graph tab**: which functions consume the most time?
         - **Data tab**: memory allocations and garbage collection
         - Identify:
           - Top 5 functions by time (exclusive time, not just total)
           - Any function taking > 50% of total time
           - GC time: if > 10%, memory pressure is an issue
           - Functions called unexpectedly many times
      3. Report:
         ```
         🔥 PROFVIS RESULTS:
         Total time: <X>ms
         GC time: <Y>ms (<Z>%)

         Top time consumers:
         1. <function>: <time>ms (<percent>%)
            Called <N> times, memory: <M> MB
         2. ...

         🐌 BOTTLENECKS:
         - <specific finding>
         ```

      If the tool is "bench" or "rprof" (not profvis or both): Skip profvis.
      Report: Skipping profvis; using {{params.tool}} instead.
    output: profvis_results

  - id: run-bench
    requires: [analyze-code]
    inline-prompt: |
      The user selected tool: {{params.tool}}.
      If the tool is "bench" or "both", run precise timing benchmarks with bench::mark().

      1. Run:
         ```r
         bench::mark(
           {{params.code}},
           iterations = {{params.iterations}},
           check = FALSE
         )
         ```
      2. Report:
         ```
         ⏱️ BENCHMARK RESULTS:
         Min: <time>
         Median: <time>
         Mean: <time>
         Max: <time>
         Iterations: <N>
         Memory allocated: <size>
         GC/sec: <rate>
         ```
      3. If GC/sec is high, memory allocation is a bottleneck.
      4. If iterations is low relative to {{params.iterations}}, the code
         is too slow for interactive work.

      If the tool is "profvis" or "rprof" (not bench or both): Skip bench.
      Report: Skipping bench; using {{params.tool}} instead.
    output: bench_results

  - id: run-rprof
    requires: [analyze-code]
    inline-prompt: |
      The user selected tool: {{params.tool}}.
      If the tool is "rprof", run R's built-in sampling profiler.

      1. Run:
         ```r
         Rprof(filename = "Rprof.out", interval = 0.02)
         {{params.code}}
         Rprof(NULL)
         summaryRprof("Rprof.out")
         ```
      2. Analyze the output:
         - `by.self`: time spent in each function alone (exclusive)
         - `by.total`: time spent in each function + its callees (inclusive)
         - `sampling.time`: total profiling duration
      3. Report the top 10 functions by self-time.
      4. Clean up: remove the `Rprof.out` file after reporting.

      If the tool is not "rprof": Skip Rprof.
      Report: Skipping Rprof; using {{params.tool}} instead.
    output: rprof_results

  - id: recommend-optimizations
    requires: [run-profvis, run-bench, run-rprof]
    inline-prompt: |
      Analyze the profiling results and produce a REPORT of optimization recommendations.
      DO NOT modify any production code. This step produces a report only.

      Profvis: {{state.profvis_results}}
      Bench: {{state.bench_results}}
      Rprof: {{state.rprof_results}}
      Code analysis: {{state.code_analysis}}

      For each bottleneck found, recommend:

      1. **Slow function calls**:
         - Can the function be vectorized?
         - Can memoisation/caching help? (memoise package)
         - Is there a faster package alternative? (data.table vs dplyr, etc.)

      2. **Memory issues**:
         - Pre-allocate vectors instead of growing
         - Use `data.table` for large in-memory operations
         - Consider `arrow` or `duckdb` for out-of-memory data

      3. **Loops**:
         - Vectorize with base R `apply` family or `purrr::map_*`
         - Use `Rcpp` for tight loops with simple operations
         - Parallelize with `furrr::future_map()` or `parallel::mclapply()`

      4. **I/O**:
         - Use `data.table::fread()` / `fwrite()` instead of base `read.csv()`
         - Use `arrow::read_parquet()` for compressed columnar storage
         - Cache repeated file reads

      Prioritize by impact: high-time × easy-to-fix first.

      Produce a formatted optimization report with:
      - Ranked optimization opportunities
      - Estimated impact for each
      - Implementation difficulty (easy/medium/hard)
      - Suggested code changes (in prose: do NOT modify files)

      The user will review this report and decide which optimizations to apply.
    gate: Review
    output: optimization_plan

tags:
  - r
  - performance
  - profiling
  - optimization

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are an R performance specialist. You use profiling tools (profvis,
bench, Rprof) to identify and recommend fixes for performance
bottlenecks in R code. You produce reports, not code changes.

## Rules

1. NEVER optimize without profiling first: data drives decisions.
2. NEVER modify production code directly. Produce a report with
   recommendations and let the user decide.
3. PREFER algorithmic improvements over micro-optimizations.
4. Document the estimated impact for every recommendation.
5. If an optimization would make the code significantly harder to read,
   flag it for user decision.
6. Target the biggest bottleneck first (biggest time consumer).
7. Use bench::mark() not microbenchmark: bench provides richer output.
8. Memory allocation reduction is often more impactful than CPU optimization.
9. Never recommend `<<-` as a performance optimization.

## R Performance Patterns

| Problem                    | Solution                                    |
| -------------------------- | ------------------------------------------- |
| Growing vector in loop     | Pre-allocate with `vector("list", N)`       |
| Slow data.frame subsetting | Use `data.table` or `collapse` package      |
| Repeated function calls    | `memoise::memoise()`                        |
| Slow group-by operations   | `data.table` or `dplyr` with `collapse`     |
| Large CSV reading          | `data.table::fread()` or `vroom::vroom()`   |
| Many small file reads      | `arrow::open_dataset()`                     |
| GC pressure                | Reduce intermediate allocations             |
| Slow plotting              | `ragg` device, `scales` for pre-computation |
