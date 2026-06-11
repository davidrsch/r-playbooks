---
name: r-async-mirai
version: 1.0.0
context-mode: Fork
description: "Add asynchronous parallel processing to R code using the mirai package: launch non-blocking background tasks, collect results, and handle errors. Use mori for zero-copy shared memory to eliminate serialization overhead on large data. Ideal for API calls, file I/O, or heavy computation in Shiny, Plumber, targets pipelines, or R packages"
trigger: both
trigger-patterns:
  - "add async *"
  - "mirai *"
  - "mori *"
  - "shared memory *"
  - "parallelize *"
  - "async process *"
argument-hint: "--target <shiny|targets|script> [--workers <n>]"
parameters:
  target:
    type: String
    required: true
    enum: ["shiny", "targets", "script", "package"]
    hint: "Where the async code runs (shiny app, targets pipeline, standalone script)"
  workers:
    type: Integer
    required: false
    default: 4
    hint: "Number of parallel workers (daemons)"
steps:
  - id: install-mirai
    inline-prompt: |
      Install mirai and verify:

      ```r
      if (!requireNamespace("mirai", quietly = TRUE)) {
        renv::install("mirai")
      }
      library(mirai)
      packageVersion("mirai")

      # Check daemon status
      status()
      # Should show 0 connections (no daemons running yet)
      ```
    output: mirai-version
  - id: configure-daemons
    inline-prompt: |
      Set up mirai daemons for {{params.target}}.

      ```r
      library(mirai)

      # Start daemons (persistent background R processes)
      daemons({{params.workers}})
      status()

      Sys.setenv(OTEL_SERVICE_NAME = "{{params.target}}-async")
      Sys.setenv(OTEL_EXPORTER_OTLP_ENDPOINT = Sys.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317"))
      ```

      For {{params.target}}:

      **shiny**: Launch daemons in global.R so they're available for all sessions:
      ```r
      # global.R
      library(mirai)
      daemons(4)
      shiny::onStop(function() { mirai::daemons(0) })
      ```

      **targets**: Use crew (mirai-based) for targets parallel backend:
      ```r
      library(crew)
      tar_option_set(controller = crew_controller_local(workers = {{params.workers}}))
      ```

      **script**: Launch daemons at script start:
      ```r
      library(mirai)
      daemons(n = {{params.workers}}, dispatcher = FALSE)
      withr::defer(daemons(0), envir = parent.frame())
      ```

      **package**: Wrap daemon lifecycle in .onLoad/.onUnload:
      ```r
      .onLoad <- function(libname, pkgname) {
        if (requireNamespace("mirai", quietly = TRUE)) {
          mirai::daemons({{params.workers}})
        }
      }
      .onUnload <- function(libpath) {
        mirai::daemons(0)
      }
      ```

      Verify daemons are running: `status()` shows {{params.workers}} connections.
    requires:
      - install-mirai
    output: daemon-config
    gate: Review
  - id: share-data-with-mori
    inline-prompt: |
      Set up zero-copy data sharing with `mori` for large objects passed to workers.

      `mori` (v0.2.1+, Charlie Gao, CRAN) provides shared memory for R objects.
      Without `mori`, every mirai worker deserializes a full copy of each object
      passed to it. With `mori`, all workers map the same physical memory region
      via ALTREP references — **200 MB becomes 824 bytes per worker**.

      Only apply this when passing large data (>100 MB) to multiple workers.

      1. **Install mori:**
         ```r
         install.packages("mori")
         library(mori)
         ```

      2. **Share data before passing to workers:**
         ```r
         library(mori)
         library(mirai)

         daemons({{params.workers}})

         # The large dataset — only ONE copy in RAM
         large_data <- readRDS("data/large_dataset.rds")
         shared_data <- mori::share(large_data)

         # Verify sharing worked
         mori::shared_name(shared_data)
         # "/mori_d04e_1"
         ```

      3. **Use mirai_map with shared data:**
         ```r
         # Without mori: each worker deserializes a full copy (~200 MB each)
         # With mori:    each worker gets an 824 B ALTREP reference
         results <- mirai_map(
           1:{{params.workers}},
           function(i, data) {
             # data is a zero-copy reference to shared memory
             # Only columns actually accessed are loaded (lazy)
             colMeans(data[sample(nrow(data), replace = TRUE), ])
           },
           .args = list(data = shared_data)
         )
         ```

      4. **For the script pattern (manual tasks):**
         ```r
         # Pass shared data into individual mirai calls
         tasks <- lapply(1:{{params.workers}}, function(i) {
           mirai(
             { process_chunk(i, data) },
             i = i,
             data = shared_data   # serializes as 124 bytes, not the full object
           )
         })
         results <- lapply(tasks, call_mirai)
         ```

      5. **Lazy access — workers only load what they read:**
         ```r
         # 100-column data frame: worker reading only 3 columns loads only 3
         shared_df <- mori::share(big_df)
         # Worker accessing shared_df[[50]] → only column 50 is materialized
         ```

      6. **Copy-on-write safety:**
         Shared data is mapped read-only. Modifying a shared object creates a
         local copy in the worker — the shared region is never corrupted.
         ```r
         # Safe: local copy, shared region unchanged
         shared_data[1, 1] <- 999
         ```

      7. **Cleanup:**
         Shared memory is managed by R's garbage collector. When no references
         remain (or the session exits cleanly), memory is freed automatically.
         For orphaned regions (killed/crashed workers), use:
         ```r
         mori::prune_shared()
         ```

      ⚠️ **Constraint**: Workers must run on the SAME MACHINE. `mori` uses OS-level
      shared memory (POSIX/Win32), not network transfer. For multi-machine clusters,
      fall back to standard serialization (without `mori`).

      Report: data shared, memory savings verified with `lobstr::obj_size()`.
    requires:
      - configure-daemons
    output: mori-setup
    gate: Review
  - id: implement-async-patterns
    inline-prompt: |
      Implement async patterns for {{params.target}}.

      If large data was shared via `mori` in the previous step, use
      `mirai_map(.args = list(data = shared_data))` to pass zero-copy references.

      **shiny**: Non-blocking computation:
      ```r
      # In server function
      output$result <- renderTable({
        # Launch async task: returns immediately
        m <- mirai({
          # Heavy computation runs in separate process
          Sys.sleep(2)  # Simulating work
          result <- expensive_calculation(input$params)
          result
        })

        # Wait for result (non-blocking for Shiny session)
        call_mirai(m)$data
      })
      ```

      For multiple parallel tasks:
      ```r
      # Launch multiple async tasks
      tasks <- lapply(1:{{params.workers}}, function(i) {
        mirai({ process_chunk(i, data) }, i = i, data = large_data)
      })

      # Collect results
      results <- lapply(tasks, call_mirai)
      ```

      **targets**: Use crew (mirai-native):
      ```r
      tar_option_set(
        controller = crew::crew_controller_local(workers = {{params.workers}})
      )
      tar_target(processed, expensive_operation(raw_data))
      # tar_make() runs targets in parallel via mirai daemons
      ```

      **script**: Parallel map pattern:
      ```r
      library(mirai)
      daemons({{params.workers}})

      # Parallel lapply
      tasks <- lapply(items, function(item) {
        mirai({ process_item(item) }, item = item)
      })
      results <- lapply(tasks, call_mirai)

      # Clean shutdown
      daemons(0)
      ```

      Add the appropriate pattern to the {{params.target}} codebase.
    requires:
      - configure-daemons
      - share-data-with-mori
    output: async-code
    gate: Review
  - id: verify-async
    inline-prompt: |
      Verify async execution works correctly:

      1. Test a single async task: `m <- mirai({ 1 + 1 }); call_mirai(m)$data` → should be 2
      2. Test parallel execution:
         ```r
         tasks <- lapply(1:{{params.workers}}, function(i) mirai({ Sys.getpid() }))
         pids <- unique(sapply(tasks, function(m) call_mirai(m)$data))
         length(pids)  # Should equal {{params.workers}} (each task ran in different process)
         ```
      3. Test error handling:
         ```r
         m <- mirai({ stop("test error") })
         result <- call_mirai(m)
         is_error_value(result)  # Should be TRUE

         # Error recovery pattern:
         tasks <- lapply(1:{{params.workers}}, function(i) mirai({ tryCatch(process(i), error = function(e) list(error = e$message)) }))
         results <- lapply(tasks, call_mirai)
         errors <- Filter(function(r) !is.null(r$error), lapply(results, `[[`, "data"))
         if (length(errors) > 0) warning("Some tasks failed: ", length(errors), " of ", length(tasks))
         ```
      4. For shiny: verify the app remains responsive during async computation
      5. For targets: verify `tar_make()` uses {{params.workers}} workers

      Report: worker count verified, error handling works, app/responsiveness confirmed.
    requires:
      - implement-async-patterns
    output: verification-report
tags:
  - r
  - async
  - mirai
  - parallel
  - performance
constraints:
  - rule: "NEVER block the main thread with synchronous I/O — use mirai for all long-running operations."
    severity: "error"
  - rule: "ALWAYS shut down daemons when done — daemons(0) in onStop, onUnload, or withr::defer."
    severity: "error"
  - rule: "NEVER share mutable state between tasks — mirai runs in isolated processes."
    severity: "error"
  - rule: "ALWAYS use mori::share() for large data (>100 MB) passed to workers — zero-copy shared memory."
    severity: "warning"
  - rule: "Use is_error_value() to check for task failures — don't assume all tasks succeed."
    severity: "warning"
  - rule: "mirai inherits NO packages from the parent — include library() calls inside mirai tasks."
    severity: "warning"
allowed-tools:
  - "*"
---

# R Mirai + Mori Async Playbook

You are an expert in async/parallel R programming. Use `mirai` (the modern,
lightweight async framework) and `mori` (zero-copy shared memory) together:
`mirai` handles computation, `mori` eliminates data copying between workers.

## Mirai vs Future

| Feature           | mirai                           | future                         |
| ----------------- | ------------------------------- | ------------------------------ |
| Mental model      | Fire-and-collect tasks          | Abstract futures with backends |
| Global state      | None (clean isolated processes) | plan() manages global state    |
| Shiny integration | call_mirai() in server          | future + promises pipe         |
| OTEL tracing      | Native (mirai 2.5+)             | Not native                     |
| Performance       | Lower overhead                  | Higher overhead                |
| targets backend   | Via `crew`                      | Via `future.batchtools`        |

## Mori: Zero-Copy Shared Memory

`mori` (v0.2.1, Charlie Gao) uses OS-level shared memory so workers read from
one physical region instead of deserializing individual copies:

```
Without mori:  [data] → serialize → [w1: 200MB] [w2: 200MB] [w3: 200MB]
With mori:     [data in shared memory] ← [w1: 824B] [w2: 824B] [w3: 824B]
```

- `mori::share(obj)` — write object into shared memory, return ALTREP wrapper
- `mori::shared_name(obj)` — get the shared memory region name
- `mori::map_shared(name)` — open a region by name in another process
- `mori::prune_shared()` — reclaim orphaned regions from killed processes

**Constraints**: Same-machine only (POSIX/Win32 shared memory, not network).
Workers on different hosts must use standard serialization.

## When to use mirai directly

- New async Shiny features (Shiny 1.12+ recommendation)
- Parallel processing in scripts
- Any code where you want clean process isolation

## When to bridge from future

- Existing code using `future`/`promises` → use `future.mirai` as drop-in
- `plan(mirai_multisession)`: keeps future API, uses mirai workers

## Safety Rules

1. **Always shut down daemons** when done: `daemons(0)`
2. **Never share mutable state** between tasks: mirai runs in isolated processes
3. **Set reasonable timeouts** for call_mirai() calls in Shiny
4. **Use `is_error_value()`** to check for task failures
5. **Set a reproducible RNG seed** in each mirai task if randomness matters
6. **mirai inherits NO packages** from the parent: include library() calls inside tasks
7. **Use mori::share() for data >100 MB** passed to multiple workers — the serialization savings are dramatic

## OpenTelemetry

mirai 2.5+ exports traces natively. Set these env vars for observability:

- `OTEL_SERVICE_NAME=my-app`
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317`
