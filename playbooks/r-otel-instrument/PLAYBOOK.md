---
name: r-otel-instrument
version: 1.0.0
context-mode: Fork
description: "Add OpenTelemetry observability to R applications: zero-code-change for Shiny 1.12+/plumber2"
trigger: auto
trigger-patterns:
  - "otel *"
  - "opentelemetry *"
  - "observability *"
  - "tracing *"
  - "instrument *"
argument-hint: "--target <shiny|plumber|targets|package> [--exporter <http://localhost:4317>] [--service_name <my-r-app>]"
parameters:
  target:
    type: String
    required: true
    hint: "Application type: shiny, plumber, targets, or package"
  exporter:
    type: String
    required: false
    default: "http://localhost:4317"
    hint: "OTLP exporter endpoint URL"
  service_name:
    type: String
    required: false
    default: my-r-app
    hint: "Service name for traces in the observability backend"
steps:
  - id: install-otel
    inline-prompt: |
      Ensure the OpenTelemetry R SDK is available:

      ```r
      if (!requireNamespace("otel", quietly = TRUE)) {
        renv::install("otel", repos = c("https://r-otel.r-universe.dev", getOption("repos")))
      }
      packageVersion("otel")
      ```

      Check that pre-instrumented packages are available at compatible versions:
      - Shiny >= 1.12 (for native reactive graph tracing)
      - plumber >= 2.0 or plumber2 (for auto-request tracing)
      - mirai >= 2.5 (for async task tracing)
      - httr2 (for HTTP client tracing)
      - testthat (for test trace correlation)

      Report installed versions of otel and any pre-instrumented packages.

      Project root: {{env.CWD}}
    output: otel-versions

  - id: configure-otel-env
    requires: [install-otel]
    inline-prompt: |
      Set OpenTelemetry environment variables for {{params.target}}.

      Required env vars (add to .Renviron or deployment config):
      ```
      OTEL_SERVICE_NAME={{params.service_name}}
      OTEL_EXPORTER_OTLP_ENDPOINT={{params.exporter}}
      OTEL_EXPORTER_OTLP_PROTOCOL=grpc
      OTEL_TRACES_SAMPLER=parentbased_traceidratio
      OTEL_TRACES_SAMPLER_ARG=0.1
      ```

      Application-specific additional vars:
      - **shiny**: `OTEL_SHINY_TRACE_REACTIVES=TRUE` (trace reactive graph)
      - **plumber**: `OTEL_PLUMBER_TRACE_REQUESTS=TRUE` (trace all endpoints)
      - **targets**: `OTEL_TARGETS_TRACE_TARGETS=TRUE` (trace pipeline targets)
      - **package**: No additional vars needed: instrument manually

      Create `.Renviron` file with these variables.
      Create `.Renviron.local` (gitignored) for local development overrides.

      Add `.Renviron.local` to `.gitignore`:
      ```
      echo ".Renviron.local" >> .gitignore
      ```

      Project root: {{env.CWD}}
    output: otel-env-config
    gate: Review

  - id: add-manual-instrumentation
    requires: [configure-otel-env]
    inline-prompt: |
      For {{params.target}}, add custom spans for key operations.

      **R package or targets**:
      ```r
      add_instrumentation <- function() {
        # Wrap key functions with spans
        trace_key_operation <- function(x) {
          span <- otel::start_span("key_operation",
            attributes = list(input_size = length(x)))
          on.exit(span$end())
          # ... original operation ...
          span$add_event("completed",
            attributes = list(result_count = nrow(result),
              trace_id = SpanContext$trace_id(),
              span_id = SpanContext$span_id()))
          span$set_status("OK")
          result
        }
        # Correlate logs with traces: include trace_id/span_id in log messages
        logger::log_info("operation completed", trace_id = SpanContext$trace_id(), span_id = SpanContext$span_id())
      }

      # Span with error handling:
      safe_operation <- function(x) {
        span <- otel::start_span("safe_operation")
        tryCatch({
          result <- risky_computation(x)
          span$set_status("OK")
          result
        }, error = function(e) {
          span$set_status("ERROR", description = e$message)
          span$record_exception(e)
          stop(e)
        }, finally = {
          span$end()
        })
      }
      ```

      **Shiny** (additional to auto-tracing):
      ```r
      # In server function, trace long-running operations
      observeEvent(input$calculate, {
        span <- otel::start_span("calculate_heavy")
        on.exit(span$end())
        # ... heavy computation ...
      })
      ```

      **Plumber** (additional to auto-tracing):
      ```r
      #* @plumber
      #* @filter custom-tracing
      function(req, res) {
        span <- otel::start_span("business_logic",
          attributes = list(user_id = req$HTTP_X_USER_ID))
        on.exit(span$end())
        forward()
      }
      ```

      Add instrumentation to the main entry point for the target type.

      Project root: {{env.CWD}}
    output: instrumented-code

  - id: verify-traces
    requires: [add-manual-instrumentation]
    inline-prompt: |
      Verify OpenTelemetry is working:

      1. Ensure an OTLP collector is running (or use a local Jaeger for testing):
         ```bash
         docker run -d --name jaeger -p 16686:16686 -p 4317:4317 jaegertracing/all-in-one:latest
         ```
      2. Start the {{params.target}} application
      3. Trigger some operations (make requests, run pipeline, etc.)
      4. Check traces at http://localhost:16686 (Jaeger UI)
      5. Confirm spans include: service name, operation name, duration, attributes

      If no collector is available, verify the env vars are set:
      ```r
      Sys.getenv("OTEL_SERVICE_NAME")
      Sys.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
      ```

      Report: env vars configured, packages instrumented, collector status, test trace result.

      Project root: {{env.CWD}}
    output: verification-report

tags:
  - r
  - observability
  - opentelemetry
  - production
  - devops

allowed-tools:
  - "*"

constraints:
  - rule: "ALWAYS set OTEL_SERVICE_NAME to identify your app in distributed traces — a missing service name breaks span correlation."
    severity: "error"
  - rule: "ALWAYS end spans with on.exit(span$end()) or withr::defer() — unclosed spans leak memory and corrupt traces."
    severity: "error"
  - rule: "Set OTEL_TRACES_SAMPLER and OTEL_TRACES_SAMPLER_ARG to control sampling rates — NEVER trace every request in production."
    severity: "warning"
  - rule: "Configure OTEL_EXPORTER_OTLP_ENDPOINT to point to a collector (Jaeger, Grafana Tempo, Datadog) — never export directly to a backend."
    severity: "warning"
  - rule: "Correlate logs with traces by including trace_id and span_id in log messages for cross-signal debugging."
    severity: "warning"
---

You are an expert in R application observability and distributed tracing.
Use the `otel` R package and OpenTelemetry protocol to add production-grade
observability.

## Rules

1. Set `OTEL_SERVICE_NAME`: identifies your app in distributed traces.
2. Use meaningful span names: `"calculate_portfolio_risk"` not `"operation_1"`.
3. Add attributes for filtering: user_id, input_size, error_type.
4. ALWAYS end spans: use `on.exit(span$end())` or `withr::defer()`.
5. Do NOT trace everything: use sampling for high-volume paths.
6. Correlate logs with traces: include trace_id and span_id in log messages.
7. Export to a collector: Jaeger (dev), Grafana Tempo, Datadog, Honeycomb (prod).
8. Shiny 1.12+, plumber2, mirai 2.5+, httr2, knitr, testthat, DBI are pre-instrumented.
9. Simply set env vars and traces flow automatically: NO code changes needed for pre-instrumented packages.
10. Use `on.exit()` pattern for span lifecycle in manual instrumentation.

## The Three Signals

1. **Traces**: The path of a request through the system (spans = individual operations)
2. **Metrics**: Numeric measurements over time (latency, error rate, throughput)
3. **Logs**: Structured event records (complement traces, not replace them)

## Span Hierarchy

```
Request Span (root)
├── Database Query Span (child)
│   └── Cache Check Span (grandchild)
├── Business Logic Span (child)
└── Response Span (child)
```

## Collector Options

- **Jaeger** (all-in-one Docker): great for development
- **Grafana Tempo** + Grafana: production observability stack
- **Datadog Agent**: if using Datadog
- **OTLP Collector**: vendor-neutral, send to any backend
