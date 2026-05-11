---
name: r-async-mirai
version: 1.0.0
context-mode: Fork
description: Add async parallel processing with mirai for non-blocking execution
trigger: both
trigger-patterns:
  - "add async *"
  - "mirai *"
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
    type: Number
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
  - id: implement-async-patterns
    inline-prompt: |
      Implement async patterns for {{params.target}}.

      **shiny** — Non-blocking computation:
      ```r
      # In server function
      output$result <- renderTable({
        # Launch async task — returns immediately
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

      **targets** — Use crew (mirai-native):
      ```r
      tar_option_set(
        controller = crew::crew_controller_local(workers = {{params.workers}})
      )
      tar_target(processed, expensive_operation(raw_data))
      # tar_make() runs targets in parallel via mirai daemons
      ```

      **script** — Parallel map pattern:
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
  file: ../_shared/constraints-r.md
allowed-tools:
  - "*"
---

# R Mirai Async Playbook

You are an expert in async/parallel R programming. Use `mirai` — the modern, lightweight async framework that replaces `future`/`promises` for new R code.

## Mirai vs Future

| Feature           | mirai                           | future                         |
| ----------------- | ------------------------------- | ------------------------------ |
| Mental model      | Fire-and-collect tasks          | Abstract futures with backends |
| Global state      | None (clean isolated processes) | plan() manages global state    |
| Shiny integration | call_mirai() in server          | future + promises pipe         |
| OTEL tracing      | Native (mirai 2.5+)             | Not native                     |
| Performance       | Lower overhead                  | Higher overhead                |
| targets backend   | Via `crew`                      | Via `future.batchtools`        |

### When to use mirai directly

- New async Shiny features (Shiny 1.12+ recommendation)
- Parallel processing in scripts
- Any code where you want clean process isolation

### When to bridge from future

- Existing code using `future`/`promises` → use `future.mirai` as drop-in
- `plan(mirai_multisession)` — keeps future API, uses mirai workers

## Safety Rules

1. **Always shut down daemons** when done: `daemons(0)`
2. **Never share mutable state** between tasks — mirai runs in isolated processes
3. **Set reasonable timeouts** for call_mirai() calls in Shiny
4. **Use `is_error_value()`** to check for task failures
5. **Set a reproducible RNG seed** in each mirai task if randomness matters
6. **mirai inherits NO packages** from the parent — include library() calls inside tasks

## OpenTelemetry

mirai 2.5+ exports traces natively. Set these env vars for observability:

- `OTEL_SERVICE_NAME=my-app`
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317`
