---
name: r-shiny-perf
version: 1.0.0
context-mode: Fork
description: "Shiny performance profiling and optimization: reactlog reactivity graph analysis, profvis server profiling, shinyloadtest multi-user load simulation, bindCache/memoise caching strategies, and performance regression testing"
trigger: both
trigger-patterns:
  - "shiny perf *"
  - "shiny performance *"
  - "shiny slow *"
  - "shiny optimize *"
  - "reactlog *"
  - "shinyloadtest *"
  - "load test * shiny *"
  - "speed up shiny *"
  - "shiny reactive *"
  - "shiny cache *"
argument-hint: "[--scope reactlog|server|load|all] [--users 50] [--duration 60] [--cache true|false]"
parameters:
  scope:
    type: String
    required: false
    default: "all"
    enum: ["reactlog", "server", "load", "cache", "all"]
    hint: "Profiling scope: reactlog (reactivity), server (profvis), load (shinyloadtest), cache (bindCache), or all"
  users:
    type: Integer
    required: false
    default: 50
    min: 5
    max: 1000
    hint: "Number of simulated concurrent users for load testing"
  duration:
    type: Integer
    required: false
    default: 60
    min: 30
    max: 600
    hint: "Load test duration in seconds"
  cache:
    type: Boolean
    required: false
    default: true
    hint: "Analyze and optimize caching strategy (bindCache, memoise)"
steps:
  - id: reactlog-profiling
    inline-prompt: |
      Enable reactlog to visualize and analyze Shiny reactivity.

      Scope: {{params.scope}}

      `reactlog` (Posit) records every reactive read, write, and invalidation
      and renders an interactive D3 graph to identify unnecessary reactivity.

      1. **Enable reactlog:**
         ```r
         library(shiny)
         library(reactlog)

         # Enable recording before running the app
         reactlog_enable()

         # Run your app
         shiny::runApp("app.R")

         # After interacting with the app, view the reactlog:
         shiny::reactlogShow()
         ```

      2. **What to look for in the reactlog:**
         - **Red edges**: invalidations. Too many red edges = reactivity cascades.
         - **Too many dependencies**: a reactive depends on 10+ inputs →
           it recalculates unnecessarily often.
         - **Diamond dependencies**: two reactives depend on the same source →
           use `reactive()` to share the computation.
         - **Long rectangles**: slow reactives. They're blocking the UI.
         - **Observer chains**: observer A triggers observer B triggers observer C →
           this is usually a bug.

      3. **Common reactive anti-patterns and fixes:**

         | Anti-Pattern | Symptom | Fix |
         |-------------|---------|-----|
         | Reactive depends on reactive that depends on reactive | Cascade of invalidation | Flatten with `reactiveValues()` |
         | `renderPlot()` recomputes on any input change | Slow plot redraws | `bindCache()` on plot |
         | `observeEvent()` triggers `updateSelectInput()` which triggers another `observeEvent()` | Infinite loop | Use `freezeReactiveValue()` or `observe(..., priority = )` |
         | `reactive()` calls `dbGetQuery()` | Slow reactive blocks UI | Use `future` + `promises` for async |
         | Output reads `input$x` but doesn't use it | Unnecessary dependency | Remove unused inputs from reactive |

      4. **Fix the top 3 reactivity issues** identified in the reactlog.

      Report: reactlog analysis with top issues and fixes applied.
    gate: Review
    output: reactlog_analysis

  - id: server-profiling
    requires: [reactlog-profiling]
    inline-prompt: |
      Profile the Shiny server function with profvis.

      Scope: {{params.scope}}

      1. **Profile the server function:**
         ```r
         library(profvis)

         # Profile a specific user session
         profvis({
           shiny::runApp("app.R")
         })
         ```

      2. **Profile specific server operations:**
         ```r
         # Profile a single reactive
         profvis({
           my_data <- slow_data_processing(input_data)
           result <- complex_model(my_data)
         })

         # Profile database queries
         library(DBI)
         con <- dbConnect(...)
         profvis({
           data <- DBI::dbGetQuery(con, "SELECT * FROM large_table")
         })
         ```

      3. **Common server bottlenecks:**

         | Bottleneck | Profvis Signature | Fix |
         |-----------|-------------------|-----|
         | Large data load | `read.csv()` dominates time | Use `data.table::fread()` or `arrow::read_parquet()` |
         | Repeated DB query | Same query in many reactives | Cache result with `bindCache()` or `reactivePoll()` |
         | Image rendering | `ggplot2::ggsave()` slow | Use `Cairo` device, reduce DPI, cache rendered plot |
         | Data transformation | `dplyr::mutate()` on large df repeated | Pre-compute in `global.R` or `bindCache()` |
         | Session creation | Heavy `global.R` | Lazy-load data, use `memoise::memoise()` |

      4. **Optimize based on profiling:**
         - Extract slow operations to `future` + `promises` for non-blocking execution
         - Cache expensive computations with `bindCache()`
         - Pre-process data outside the server function

      Report: profiling results with before/after timing for each optimization.
    gate: Review
    output: server_profile

  - id: load-testing-shinyloadtest
    requires: [server-profiling]
    inline-prompt: |
      Run multi-user load testing with shinyloadtest.

      Users: {{params.users}}
      Duration: {{params.duration}}s

      `shinyloadtest` (Posit) simulates multiple concurrent users and records
      session metrics to identify scaling limits.

      1. **Install shinyloadtest:**
         ```r
         install.packages("shinyloadtest")
         ```

      2. **Record a user session** (the "script" that will be replayed):
         ```r
         library(shinyloadtest)

         # Start recording
         shinycannon::record_session(
           app_url = "http://localhost:3838",
           output_file = "recording.log",
           duration = 120  # record 2 minutes of interaction
         )
         # Interact with the app normally during recording
         ```

      3. **Run the load test:**
         ```bash
         # Use the shinycannon CLI tool
         # Install: https://rstudio.github.io/shinyloadtest/#shinycannon

         shinycannon recording.log \
           --workers {{params.users}} \
           --loaded-duration-minutes $(({{params.duration}} / 60)) \
           --output-dir load-test-results \
           http://localhost:3838
         ```

      4. **Analyze results:**
         ```r
         library(shinyloadtest)

         results <- load_runs("load-test-results")

         # Summary report
         shinyloadtest_report(results, "load-test-report.html")
         # Opens an interactive HTML report

         # Key metrics:
         # - Session duration (should be stable as users increase)
         # - Time to first byte (should be < 500ms)
         # - HTTP errors (should be 0)
         # - WebSocket latency (should be < 100ms)
         ```

      5. **Interpret scaling limits:**
         - Sessions take > 2x longer with {{params.users}} users than with 5 users →
           app doesn't scale linearly
         - HTTP errors increase > 0 at N users → you've hit the scaling limit
         - WebSocket latency spikes → server is saturated
         - Memory usage grows linearly with users → no memory leak (good)

      6. **Scaling recommendations:**
         - Vertical: increase CPU/memory per instance
         - Horizontal: add more Shiny server instances behind a load balancer
           (requires sticky sessions for Shiny's stateful model)
         - Async: move slow operations to `future` + `promises` to free up R processes

      Report: load test results with scaling recommendations.
    gate: Review
    output: load_test_results

  - id: caching-strategy
    requires: [server-profiling]
    inline-prompt: |
      Optimize Shiny caching with bindCache and memoise.

      Cache analysis enabled: {{params.cache}}

      If cache is false, skip this step.

      1. **Identify cache candidates:**
         Look for computations that:
         - Are called with the same inputs repeatedly (different users see same output)
         - Take > 500ms to compute
         - Don't need real-time freshness (can be stale for minutes)

      2. **Apply bindCache to reactive outputs:**
         ```r
         server <- function(input, output, session) {

           # Before: recomputes on every input change
           output$plot <- renderPlot({
             expensive_plot(input$dataset, input$date_range)
           })

           # After: caches based on input values
           output$plot <- renderPlot({
             expensive_plot(input$dataset, input$date_range)
           }) |>
             bindCache(input$dataset, input$date_range)

           # Cache with time-based expiry (5 minutes)
           output$plot <- renderPlot({
             expensive_plot(input$dataset, input$date_range)
           }) |>
             bindCache(input$dataset, input$date_range,
               cache = "session", cache_scope = "app")

           # Use a shared cache across sessions
           # cache <- cachem::cache_disk("cache/", max_size = 500 * 1024^2)  # 500 MB
           # bindCache(..., cache = cache)
         }
         ```

      3. **Apply memoise to expensive functions:**
         ```r
         library(memoise)

         # Wrap an expensive database query
         get_user_data <- memoise::memoise(
           function(user_id, date_range) {
             DBI::dbGetQuery(con, sprintf(
               "SELECT * FROM events WHERE user_id = %d AND date BETWEEN '%s' AND '%s'",
               user_id, date_range[1], date_range[2]
             ))
           },
           cache = cachem::cache_mem(max_size = 100 * 1024^2)  # 100 MB
         )

         # Time-based expiry (10 minutes)
         get_user_data <- memoise::memoise(get_user_data_impl,
           cache = cachem::cache_mem(max_age = 600)
         )
         ```

      4. **Use reactivePoll for periodic updates** (instead of polling in a reactive):
         ```r
         # Instead of: invalidating every second
         # Better: check for changes every 30 seconds
         latest_data <- reactivePoll(
           intervalMillis = 30000,
           session = session,
           checkFunc = function() {
             DBI::dbGetQuery(con, "SELECT MAX(updated_at) FROM events")
           },
           valueFunc = function() {
             DBI::dbGetQuery(con, "SELECT * FROM events")
           }
         )
         ```

      5. **Cache validation:**
         - Verify cached and non-cached outputs are identical
         - Measure before/after timing
         - Document cache invalidation strategy (when should cache be cleared?)

      Report: caching optimizations applied with before/after timings.
    gate: Review
    output: cache_optimizations

  - id: performance-regression-tests
    requires: [load-testing-shinyloadtest, caching-strategy]
    inline-prompt: |
      Set up automated performance regression testing.

      1. **Create performance test suite:**
         ```r
         # tests/testthat/test-perf.R
         library(bench)

         test_that("homepage renders within 500ms", {
           app <- shinytest2::AppDriver$new(app_dir = ".")
           time <- system.time({
             app$expect_text("#title", "My App")
           })
           expect_lt(time["elapsed"], 0.5,
             sprintf("Homepage took %.2fs, expected < 0.5s", time["elapsed"]))
           app$stop()
         })

         test_that("data table filters within 200ms", {
           app <- shinytest2::AppDriver$new(app_dir = ".")
           time <- system.time({
             app$set_inputs(filter = "Alice")
           })
           expect_lt(time["elapsed"], 0.2,
             sprintf("Filter took %.2fs, expected < 0.2s", time["elapsed"]))
           app$stop()
         })

         test_that("no reactivity cascade on single input change", {
           app <- shinytest2::AppDriver$new(app_dir = ".")
           # Change one input
           app$set_inputs(dataset = "mtcars")
           # Wait for outputs to settle
           app$wait_for_idle()
           # Check that only the expected outputs updated
           app$stop()
         })
         ```

      2. **Set up performance CI** (`.github/workflows/perf-test.yaml`):
         ```yaml
         name: Performance Tests
         on:
           pull_request:
             paths:
               - 'R/**'
               - 'app.R'
               - 'server.R'
               - 'ui.R'
         jobs:
           perf:
             runs-on: ubuntu-latest
             steps:
               - uses: actions/checkout@v4
               - uses: r-lib/actions/setup-r@v2
               - name: Run performance tests
                 run: Rscript -e 'testthat::test_file("tests/testthat/test-perf.R")'
         ```

      3. **Performance budget:**
         | Metric | Budget | Alert |
         |--------|--------|-------|
         | Homepage load | < 500ms | > 1s = failure |
         | Filter response | < 200ms | > 500ms = failure |
         | Plot render | < 1s | > 3s = failure |
         | Session start | < 2s | > 5s = failure |
         | Memory per session | < 50MB | > 200MB = failure |

      Report: performance test suite created and performance budget defined.
    gate: Review
    output: perf_regression_tests

tags:
  - r
  - shiny
  - performance
  - profiling
  - reactlog
  - shinyloadtest
  - caching

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER run shinyloadtest against production — always use a staging instance."
    severity: "error"
  - rule: "ALWAYS profile BEFORE optimizing — never guess what's slow."
    severity: "error"
  - rule: "NEVER cache sensitive user data — cache scoping must respect data privacy."
    severity: "error"
  - rule: "ALWAYS verify cached outputs match uncached outputs — caching bugs are silent and dangerous."
    severity: "warning"
  - rule: "Use bindCache() for renderPlot/renderTable, memoise for functions — they solve different problems."
    severity: "warning"
---

You are a Shiny performance specialist. You profile and optimize Shiny apps
using Posit's performance tooling (reactlog, profvis, shinyloadtest) and
caching strategies (bindCache, memoise).

## Shiny Performance Philosophy

1. **PROFILE FIRST, OPTIMIZE SECOND**: Don't guess. Use reactlog to see the
   reactivity graph and profvis to see where CPU time goes.
2. **THE USER EXPERIENCES LATENCY**: A Shiny app that takes 5 seconds to respond
   feels broken. Target < 500ms for interactive elements.
3. **SCALE WITH USERS**: An app that works for 1 user may fail for 50.
   shinyloadtest reveals scaling limits before users do.
4. **CACHE AGGRESSIVELY, INVALIDATE CAREFULLY**: Caching is the most impactful
   optimization in Shiny — but stale cache data is worse than slow computation.
5. **ASYNC IS NOT FREE**: `future` + `promises` improve concurrency but add
   complexity. Use them for I/O-bound work (DB queries, API calls), not for
   CPU-bound work (which just moves the problem to a different process).
6. **SHARE LARGE DATA WITH MORI**: For Shiny apps running on a single server with
   large reference datasets (>100 MB), use `mori::share()` to place the data in
   OS-level shared memory. All R sessions (mirai workers, Shiny processes) map
   the same physical region via ALTREP references — 200 MB becomes 824 bytes per
   process. Requires same-machine deployment (not Kubernetes multi-pod).

## Shiny Performance Tooling

| Tool | What It Measures | Output |
|------|-----------------|--------|
| `reactlog` | Reactive dependency graph, invalidation cascades | Interactive D3 graph |
| `profvis` | CPU time and memory per function call | Flame graph |
| `shinyloadtest` | Multi-user session metrics | HTML report with latency distributions |
| `bench::mark()` | Precise timing of individual operations | Median, memory, iterations/sec |
| `bindCache()` | Output caching (built into Shiny ≥ 1.7) | Automatic cache hits |
| `memoise` | Function-level memoization | Time-based or size-based cache |
