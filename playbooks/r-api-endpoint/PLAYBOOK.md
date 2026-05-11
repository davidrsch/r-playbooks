---
name: r-api-endpoint
version: 1.0.0
context-mode: Fork
description: Add a new Plumber endpoint with parameter docs, input validation, error handling, and tests
trigger: both
trigger-patterns:
  - "add endpoint *"
  - "new endpoint *"
  - "api endpoint *"
  - "add api *"
  - "create endpoint *"
argument-hint: "--path <endpoint_path> --method GET|POST|PUT|DELETE [--resource <resource_name>] [--description <text>]"
parameters:
  path:
    type: String
    required: true
    hint: "Endpoint path (e.g., '/users', '/items/<id>')"
  method:
    type: String
    required: true
    enum: ["GET", "POST", "PUT", "DELETE", "PATCH"]
    hint: "HTTP method for this endpoint"
  resource:
    type: String
    required: false
    hint: "Resource name for organizing routes (creates R/routes/<resource>.R)"
  description:
    type: String
    required: false
    hint: "What this endpoint does: inputs, processing, outputs"
  response:
    type: String
    required: false
    enum: ["json", "csv", "html", "png", "pdf", "raw"]
    hint: "Response content type (determines serializer)"
steps:
  - id: analyze-api
    inline-prompt: |
      Analyze the existing Plumber API:

      1. Read `plumber.R` to understand the registered routes and filters.
      2. List existing route files in `R/routes/`.
      3. Read related route files to understand conventions.
      4. Identify serializer conventions (unboxedJSON, html, csv, etc.).
      5. Check if the resource file `R/routes/{{params.resource}}.R` already exists.
      6. Report: existing routes, conventions to follow, file to modify/create.
    output: api_context

  - id: design-endpoint
    requires: [analyze-api]
    inline-prompt: |
      Design the endpoint interface:

      Path: {{params.path}}
      Method: {{params.method}}
      Description: {{params.description}}
      Response type: {{params.response}}

      Design and report:
      1. **Function signature**: parameter names, types, defaults, required/optional
      2. **Request validation**: what checks to perform on inputs
      3. **Response structure**: exactly what the endpoint returns
      4. **Error responses**: what errors can occur and their HTTP status codes.
         Use a structured error format with a `details` field:
         `list(error = "message", details = "specific_info")`
      5. **Serializer**: based on {{params.response}}:
         - json → `@serializer unboxedJSON`
         - csv → `@serializer csv`
         - html → `@serializer html`
         - png/pdf → `@serializer png` / `@serializer pdf`
         - raw → no serializer annotation
      6. **Side effects**: database writes, file operations, external API calls
      7. **Auth filter**: If the endpoint requires authentication, add a
         `@preempt` filter annotation (e.g., `@preempt auth_filter`) to run
         the auth filter before the endpoint handler.

      If the path has dynamic segments (e.g., `/users/<id>`), plan for the
      `<id>` parameter. Protect against path traversal by validating dynamic
      segments do not contain `..`, `/`, or `\`.
    gate: Confirm
    output: endpoint_design

  - id: implement-endpoint
    requires: [design-endpoint]
    inline-prompt: |
      Implement the endpoint based on the design.

      Design: {{state.endpoint_design}}
      API context: {{state.api_context}}

      Target file: `R/routes/{{params.resource}}.R` (or create if new)

      Write the endpoint with proper Plumber annotations:

      ```r
      box::use(
        logger[log_info, log_error, log_warn],
        jsonvalidate[json_validator = json_validator],
      )

      #* {{params.description}}
      #* @serializer unboxedJSON list
      #* @param <param_name>:<type> <description>
      #* @get {{params.path}}
      #* @post {{params.path}}
      function(req, res, param1, param2 = "default") {
        log_info("Request received", path = "{{params.path}}")

        # Input validation — MANDATORY on every endpoint
        # schema <- json_validator(schema = "validation_schema.json")
        # if (!schema(req$postBody)) { ... }

        if (is.null(param1) || param1 == "") {
          log_error("Missing required parameter", param = "param1")
          plumber::abort(400, "param1 is required")
        }

        # Business logic
        result <- list(
          data = ...,
          count = length(...)
        )

        log_info("Request completed", path = "{{params.path}}")
        result
      }
      ```

      If the endpoint needs CORS support, set the `Access-Control-Allow-Origin` header
      on the response via `res$setHeader("Access-Control-Allow-Origin", "*")`.

      Checklist:
      ✅ Proper `#*` annotations for method and path
      ✅ `@param` for every parameter with type (`:str`, `:int`, `:dbl`, `:bool`)
      ✅ Input validation with appropriate HTTP errors
      ✅ Returns structured list (not data.frame)
      ✅ Uses `plumber::abort(status, message)` for errors
      ✅ Serializer annotation matches expected response type
      ✅ `pr_setMaxBodySize(10 * 1024 * 1024)` called in plumber.R to limit payload size

      Also: Update `plumber.R` to register the new route file if needed and
      call `pr_setMaxBodySize(10 * 1024 * 1024)` (10 MB limit) at initialization.

      Report: file modified, endpoint details.
    gate: Review
    output: implementation

  - id: write-tests
    requires: [implement-endpoint]
    inline-prompt: |
      Write tests for the new endpoint.

      Update or create `tests/testthat/test-{{params.resource}}.R`:

      ```r
      test_that("{{params.method}} {{params.path}} returns expected structure", {
        pr <- plumber::pr("plumber.R")

        # Test successful request
        res <- pr$routes$get("{{params.path}}")$exec(
          req = list(QUERY_STRING = "param1=value1"),
          res = list()
        )
        expect_type(res, "list")
        expect_named(res, c("expected", "fields"))
      })

      test_that("{{params.method}} {{params.path}} handles missing params", {
        pr <- plumber::pr("plumber.R")
        expect_error(
          pr$routes$get("{{params.path}}")$exec(req = list(), res = list()),
          "400"
        )
      })
      ```

      Run: `devtools::test(filter = "{{params.resource}}")`

      Report: tests written and results.
    output: test_results

tags:
  - r
  - plumber
  - api
  - endpoint

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are a Plumber API developer specializing in RESTful endpoint design.
You follow strict conventions for annotation, validation, error handling,
and serialization.

## Rules

1. EVERY endpoint must have a `#*` description comment on the line before
   the `@get`/`@post`/etc. annotation.
2. EVERY parameter must have `@param name:type Description` with the
   correct R type shorthand: `:str`, `:int`, `:dbl`, `:bool`.
3. ALWAYS validate inputs at the top of the function. For complex objects,
   use JSON schema validation via `jsonvalidate` or `pointblank`.
4. Use structured logging with `logger::log_info()`, `logger::log_error()`,
   and `logger::log_warn()` at entry and exit of each endpoint.
5. Return structured lists, not data.frames — they serialize more predictably.
6. For JSON responses, use `@serializer unboxedJSON list` to avoid array
   wrapping of single-element lists. For CSV, use `@serializer csv`.
   For HTML, use `@serializer html`. For images, use `@serializer png` or `@serializer pdf`.
7. For dynamic paths (`/items/<id>`), use `<id>` in the path annotation.
8. Route files should group related endpoints under the same resource.
9. NEVER do heavy computation in the endpoint handler — delegate to
   helper functions imported via `box::use()` from `R/utils.R` or `R/services/`.
10. Register new route files in `plumber.R` with `pr("R/routes/file.R")`.
11. Plumber2 auto-traces all requests. For production, set `OTEL_SERVICE_NAME`
    and `OTEL_EXPORTER_OTLP_ENDPOINT` env vars for distributed tracing.
12. Handle CORS if the API is called from browser clients — set appropriate
    response headers via `res$setHeader()`.
