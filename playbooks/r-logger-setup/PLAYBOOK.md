---
name: r-logger-setup
version: 1.0.0
context-mode: Fork
description: Configure structured logging with the logger package for any R application
trigger: both
trigger-patterns:
  - "add logging *"
  - "setup logger *"
  - "configure logs *"
  - "structured logging *"
argument-hint: "--target <shiny|plumber|targets|package> [--format <json|colored|plain>] [--level <INFO>]"
parameters:
  format:
    type: String
    required: false
    default: json
    hint: "Log output format: json (production), colored (local dev), or plain (CI/file)"
  level:
    type: String
    required: false
    default: INFO
    enum: ["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"]
    hint: "Minimum log level: TRACE, DEBUG, INFO, WARN, ERROR, or FATAL"
  target:
    type: String
    required: true
    hint: "Application type: shiny, plumber, targets, or package"
steps:
  - id: install-logger
    inline-prompt: |
      Ensure the logger package is installed and available:

      ```r
      if (!requireNamespace("logger", quietly = TRUE)) {
        renv::install("logger")
      }
      library(logger)
      packageVersion("logger")
      ```

      Report the installed logger version.

      Project root: {{env.CWD}}
    output: logger-version

  - id: configure-logger
    requires: [install-logger]
    inline-prompt: |
      Set up logger configuration for a {{params.target}} application.

      Configuration rules:
      1. Set the log threshold to {{params.level}}
      2. For JSON format (`json`): use `logger::log_layout(logger::layout_json())`
         This produces structured JSON output with fields: level, time, msg, ns, and any custom fields
         Compatible with ELK stack, Grafana Loki, Datadog, OpenTelemetry collectors
      3. For colored format (`colored`): use `logger::log_layout(logger::layout_glue_colors)`
         Best for local development: color-coded by severity
      4. For plain format (`plain`): use `logger::log_layout(logger::layout_glue)`
         Best for CI logs or file output

      Application-specific setup:
      - **shiny**: Configure in global.R, add session ID to all logs.
        ```r
        logger::log_formatter(logger::formatter_glue)
        logger::log_threshold(logger::{{params.level}})
        logger::log_namespace("shiny")
        # Production: add log rotation to prevent disk exhaustion
        # logger::log_appender(logger::appender_file("logs/app.log", max_lines = 10000))
        ```
        Add a request logger in server function:
        ```r
        log_info("Session started", session_id = session$token, correlation_id = uuid::UUIDgenerate())
        ```
      - **plumber**: Configure in entrypoint.R, add request/response logging middleware.
        Use `#* @plumber` annotation for a logger filter.
        ```r
        #* @filter logger
        function(req, res) {
          log_info("Request", method = req$REQUEST_METHOD, path = req$PATH_INFO)
          forward()
          log_info("Response", status = res$status)
        }
        ```
      - **targets**: Configure in _targets.R, log pipeline progress.
        ```r
        log_info("Pipeline started", timestamp = Sys.time())
        ```
      - **package**: Configure inst/logger.yml, log in .onLoad().

      Project root: {{env.CWD}}
    output: logger-config
    gate: Review

  - id: add-sampling
    requires: [configure-logger]
    inline-prompt: |
      Create a helper file that wraps logger functions with sampling/monitoring.

      Create the file at an appropriate location for the target type:
      - shiny: R/logger.R
      - plumber: R/logger.R
      - targets: R/logger.R
      - package: R/logger.R

      Include:
      ```r
      #' @title Log with sampling support
      #' @param message Log message
      #' @param rate Sampling rate (0-1, 1 = always log)
      #' @param ... Additional fields passed to log_info
      #' @noRd
      log_sampled <- function(message, rate = 1, ...) {
        if (runif(1) <= rate) {
          logger::log_info(message, ...)
        }
      }
      ```

      Also create log level shortcuts:
      ```r
      log_trace <- logger::log_trace
      log_debug <- logger::log_debug
      log_info  <- logger::log_info
      log_warn  <- logger::log_warn
      log_error <- logger::log_error
      log_fatal <- logger::log_fatal
      ```

      Project root: {{env.CWD}}
    output: logger-helpers

  - id: verify-logging
    requires: [add-sampling]
    inline-prompt: |
      Verify the logging setup:

      1. Source the configuration
      2. Call `log_info("Test message", component = "verification")`
      3. For JSON format: verify output is valid JSON with `jsonlite::validate()`
      4. Confirm all log levels work: TRACE, DEBUG, INFO, WARN, ERROR, FATAL
      5. Verify the log threshold is respected (messages below threshold are suppressed)

      Report: format, level, file location, test results.

      Project root: {{env.CWD}}
    output: verification-report

tags:
  - r
  - logging
  - observability
  - production

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are an expert in R application observability and structured logging.
Use the `logger` package to set up production-grade logging for any R
application type.

## Rules

1. ALWAYS log in JSON for production: enables log aggregation and search.
2. Include correlation IDs: session_id, request_id, pipeline_run_id.
3. Log meaningful context: user_id, input sizes, operation duration.
4. NEVER log secrets: filter out passwords, tokens, API keys.
5. Use log sampling for high-volume paths: `runif(1) <= rate` pattern.
6. Log at boundaries: application entry/exit, external service calls, error handlers.
7. Log pipeline progress in targets: target start/completion/failure.
8. JSON logs can be ingested directly by ELK, Grafana Loki, Datadog.
9. Use `logger::layout_json()` for structured output.
10. Include `ns` (namespace) field for log source identification.

## Log Levels Guide

| Level | When to Use                                                         |
| ----- | ------------------------------------------------------------------- |
| TRACE | Extremely detailed debugging (function entry/exit, variable values) |
| DEBUG | Development-time diagnostic information                             |
| INFO  | Normal application events (startup, config loaded, user actions)    |
| WARN  | Unexpected but handled conditions (retry, fallback, deprecation)    |
| ERROR | Operation failures that need attention                              |
| FATAL | Application-crashing errors                                         |
