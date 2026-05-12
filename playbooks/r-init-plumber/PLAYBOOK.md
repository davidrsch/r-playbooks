---
name: r-init-plumber
version: 1.0.0
context-mode: Fork
description: "Scaffold a Plumber API project with entrypoint, route files, middleware, health checks, testthat tests, and optional Dockerfile — ready for CI/CD and Connect deployment"
trigger: auto
trigger-patterns:
  - "plumber *"
  - "api *"
  - "init plumber *"
  - "scaffold api *"
  - "create plumber *"
  - "new api *"
  - "initialize api *"
argument-hint: "--name <api_name> [--port <8080>] [--renv true|false] [--docker true|false]"
parameters:
  name:
    type: String
    required: true
    hint: "API project name (lowercase, letters/numbers/underscores only)"
  port:
    type: Number
    required: false
    default: 8080
    min: 1024
    max: 65535
    hint: "Default port for the API"
  renv:
    type: Boolean
    required: false
    default: true
    hint: "Initialize renv for dependency management"
  docker:
    type: Boolean
    required: false
    default: true
    hint: "Generate a Dockerfile for containerized deployment"
steps:
  - id: create-structure
    inline-prompt: |
      Create the Plumber API project structure for "{{params.name}}":

      ```
      {{params.name}}/
      ├── plumber.R          # Entrypoint: registers routes and middleware
      ├── R/
      │   ├── routes/
      │   │   ├── health.R  # Health check endpoint
      │   │   └── root.R    # Root endpoint with API info
      │   ├── middleware/
      │   │   └── logger.R  # Request logging middleware
      │   └── utils.R       # Helper functions
      ├── tests/
      │   └── testthat/
      │       └── test-api.R
      ├── data/              # API data files (if any)
      ├── .Rbuildignore
      └── README.md
      ```

      Create the files with appropriate content:

      1. `plumber.R`:
         ```r
         library(plumber)
         library(logger)

         pr() |>
           # Error handler (called on errors in filters/routes)
           pr_set_error_handler(function(req, res, err) {
             res$status <- 500
             list(error = "Internal server error")
           }) |>
           # Filters: must be added BEFORE routes
           pr_filter("logger", function(req, res) {
             log_info("Request: {req$REQUEST_METHOD} {req$PATH_INFO}")
             forward()
           }) |>
           # Body size limit
           pr_setMaxBodySize(5 * 1024 * 1024) |>
           # Route files
           pr("R/routes/root.R") |>
           pr("R/routes/health.R") |>
           # API spec
           pr_set_api_spec(function(spec) {
             spec$info$title <- "{{params.name}} API"
             spec$info$description <- "Auto-generated Plumber API"
             spec
           }) |>
           # Post-route hook
           pr_hook("preroute", function(req, res) {
             log_info("Response: {res$status}")
           })
         ```

      2. `R/routes/root.R`:
         ```r
         #* @get /
         #* @param req The request object (auto-populated by Plumber)
         #* @serializer unboxedJSON
         function(req) {
           list(
             name = "{{params.name}}",
             version = "0.1.0",
             status = "ok",
             endpoints = c("/", "/health", "/ping")
           )
         }
         ```

      3. `R/routes/health.R`:
         ```r
         #* Health check endpoint
         #* @get /health
         #* @serializer unboxedJSON
         function() {
           list(status = "healthy", timestamp = as.character(Sys.time()))
         }

         #* Liveness probe (minimal, no dependency checks)
         #* @get /ping
         #* @serializer unboxedJSON
         function() {
           list(status = "alive")
         }
         ```

      Report: directory structure created, files listed.
    gate: Confirm
    output: structure

  - id: setup-renv
    requires: [create-structure]
    inline-prompt: |
      If the user specified 'renv' as true (value: {{params.renv}}):
      Initialize renv in {{params.name}}/:

      1. Run: `renv::init(project = "{{params.name}}", bare = TRUE)`
      2. Install plumber: `renv::install("plumber")`
      3. Run: `renv::snapshot(type = "explicit")` to record dependencies.
      4. Verify renv.lock created.

      Report: renv initialized with plumber.

      If the user specified 'renv' as false: Skip renv.
      Report: skipped.
    gate: Confirm
    output: renv_status

  - id: setup-testing
    requires: [create-structure]
    inline-prompt: |
      Set up API testing with testthat:

      1. Create `tests/testthat.R`:
         ```r
         library(testthat)
         library(plumber)
         testthat::test_dir("tests/testthat/")
         ```
      2. Create `tests/testthat/test-api.R`:
         ```r
         library(plumber)
         library(testthat)

         test_that("root endpoint returns API info", {
           # Load the API as a plumber object: use pr() directly, not library(pkg)
           pr <- plumber::pr("plumber.R")

           # Test the / endpoint via route execution
           res <- pr$routes$get("/")$exec(req = list(), res = list())
           expect_equal(res$name, "{{params.name}}")
           expect_equal(res$status, "ok")
         })

         test_that("health endpoint returns healthy", {
           pr <- plumber::pr("plumber.R")
           res <- pr$routes$get("/health")$exec(req = list(), res = list())
           expect_equal(res$status, "healthy")
         })
         ```

      Report: test files created.
    output: test_status

  - id: setup-docker
    requires: [create-structure]
    inline-prompt: |
      If the user specified 'docker' as true (value: {{params.docker}}):
      Create a Dockerfile for the API:

      Create `{{params.name}}/Dockerfile`:
      ```dockerfile
      FROM rocker/r-ver:4.4

      RUN apt-get update && apt-get install -y \\
        libcurl4-openssl-dev \\
        libssl-dev \\
        libxml2-dev \\
        && rm -rf /var/lib/apt/lists/*

      RUN R -e "pak::pak(c('plumber', 'renv'))"

      WORKDIR /app
      COPY . /app

      RUN adduser --disabled-password --gecos '' appuser && chown -R appuser:appuser /app
      USER appuser

      RUN R -e "renv::restore()"

      HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \\
        CMD R -e "httr::GET('http://localhost:{{params.port}}/ping')$status == 200"

      EXPOSE {{params.port}}

      CMD ["R", "-e", "plumber::pr_run(plumber::pr('plumber.R'), host='0.0.0.0', port={{params.port}})"]
      ```

      Also create `.dockerignore`:
      ```
      renv/library/
      .Rproj.user/
      .Rhistory
      .RData
      .git/
      ```

      Report: Dockerfile created.

      If the user specified 'docker' as false: Skip Docker.
      Report: skipped.
    output: docker_status

tags:
  - r
  - plumber
  - api
  - init
  - scaffold

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER expose internal error details in API responses."
    severity: "error"
  - rule: "ALWAYS validate and sanitize request parameters."
    severity: "error"
  - rule: "NEVER use eval/parse on user-supplied input."
    severity: "error"
  - rule: "Use structured error responses with status codes."
    severity: "warning"
  - rule: "Always include health check endpoints."
    severity: "warning"
---

You are a Plumber API architect specializing in RESTful API design
with R. You follow the Plumber best practices for route organization,
middleware, error handling, and testing.

## Rules

1. Organize routes in `R/routes/`: one file per resource or endpoint group.
2. Organize middleware in `R/middleware/`: filters for logging, auth, CORS, etc.
3. Use `#* @serializer unboxedJSON` for JSON endpoints to avoid array wrapping.
4. Use `#* @param` annotations to document all endpoint parameters.
5. Use `#* @get`, `#* @post`, `#* @put`, `#* @delete` for HTTP method routing.
6. Return structured lists (not data.frames) from endpoints: they serialize better.
7. Handle errors with `plumber::abort()` with appropriate HTTP status codes.
8. Always include a `/health` endpoint for monitoring.
9. Test endpoints with `plumber::pr()` + route execution in testthat.
10. Use `{{params.port}}` as the default port: configurable via `PORT` env var.
