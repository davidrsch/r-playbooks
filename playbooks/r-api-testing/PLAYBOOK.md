---
name: r-api-testing
version: 1.0.0
context-mode: Fork
description: "API testing for R: consumer-driven contract testing with pact, HTTP request/response mocking with httptest2, integration testing for Plumber APIs, and load/stress testing with vegeta or shinyloadtest"
trigger: both
trigger-patterns:
  - "api test *"
  - "contract test *"
  - "pact test *"
  - "api testing *"
  - "httptest2 *"
  - "mock api *"
  - "mock http *"
  - "load test *"
  - "stress test * api *"
  - "integration test * api *"
argument-hint: "[--scope contract|mock|integration|load|all] [--api-type plumber|client|both] [--rps 100]"
parameters:
  scope:
    type: String
    required: false
    default: "all"
    enum: ["contract", "mock", "integration", "load", "all"]
    hint: "Test scope: contract (pact), mock (httptest2), integration (real), load (vegeta), or all"
  api-type:
    type: String
    required: false
    default: "plumber"
    enum: ["plumber", "client", "both"]
    hint: "API type: Plumber API (server-side testing), client (httr2 client testing), or both"
  rps:
    type: Integer
    required: false
    default: 100
    min: 10
    max: 10000
    hint: "Target requests per second for load testing"
steps:
  - id: set-up-httptest2
    inline-prompt: |
      Set up HTTP request/response mocking with httptest2.

      Scope: {{params.scope}}

      `httptest2` (Posit/r-lib) records and replays HTTP interactions so tests
      run offline, deterministically, and without hitting real APIs.

      1. **Install httptest2:**
         ```r
         install.packages("httptest2")
         ```

      2. **Configure testthat for mocked HTTP:**
         ```r
         # tests/testthat/setup.R
         library(httptest2)

         # Set the mock directory
         options(httptest2.mock.path = testthat::test_path("fixtures"))

         # Turn on mocking for all tests in this file
         # httptest2 auto-detects httr2/httr requests and intercepts them
         ```

      3. **Write mocked API client tests:**
         ```r
         # tests/testthat/test-api-client.R
         library(httr2)
         library(httptest2)

         # Wrap tests in with_mock_dir() to record/replay
         test_that("api client fetches user data", {
           with_mock_dir("api-user", {
             # This request will be RECORDED on first run,
             # then REPLAYED from fixtures on subsequent runs
             resp <- request("https://api.example.com") |>
               req_url_path("/users/1") |>
               req_perform()

             result <- resp_body_json(resp)

             expect_equal(result$id, 1)
             expect_type(result$name, "character")
             expect_type(result$email, "character")
           })
         })

         test_that("api client handles errors gracefully", {
           with_mock_dir("api-error", {
             # Mock a 404 response
             resp <- request("https://api.example.com") |>
               req_url_path("/users/99999") |>
               req_error(is_error = ~ FALSE) |>  # don't throw on HTTP errors
               req_perform()

             expect_equal(resp_status(resp), 404)
           })
         })

         test_that("api client handles rate limiting", {
           with_mock_dir("api-ratelimit", {
             # Mock a 429 Too Many Requests response
             resp <- request("https://api.example.com") |>
               req_url_path("/users/1") |>
               req_error(is_error = ~ FALSE) |>
               req_perform()

             expect_true(resp_status(resp) %in% c(200, 429))
           })
         })
         ```

      4. **Mock directory structure:**
         ```
         tests/testthat/fixtures/
         ├── api-user/
         │   ├── <hash>.R         # Recorded request
         │   └── <hash>.json      # Recorded response
         └── api-error/
             └── ...
         ```

      Report: httptest2 configured, mocked tests running.
    gate: Review
    output: httptest2_setup

  - id: contract-testing-pact
    requires: [set-up-httptest2]
    inline-prompt: |
      Set up consumer-driven contract testing.

      Scope: {{params.scope}}

      Contract testing verifies that an API provider fulfills the expectations
      of its consumers. The consumer defines a "pact" (expected request + response),
      and the provider verifies it can fulfill that pact.

      1. **For API client (consumer) tests,** capture expected interactions:

         ```r
         library(pact)

         # Define a consumer pact
         consumer_pact <- pact(
           consumer = "my-r-client",
           provider = "user-api",
           pact_dir = "tests/pacts"
         )

         # Record expected interactions
         consumer_pact |>
           interaction(
             description = "get user by ID",
             given = "a user with ID 1 exists",
             upon_receiving = "GET /users/1",
             with_request = list(
               method = "GET",
               path = "/users/1",
               headers = list(Accept = "application/json")
             ),
             will_respond_with = list(
               status = 200,
               headers = list(`Content-Type` = "application/json"),
               body = list(
                 id = 1,
                 name = "Alice",
                 email = "alice@example.com"
               )
             )
           )

         # Write the pact file
         write_pact(consumer_pact)
         ```
         This generates `tests/pacts/my-r-client-user-api.json`.

      2. **For Plumber API (provider) tests,** verify against consumer pacts:

         ```r
         library(plumber)
         library(pact)

         # Load the pact file
         provider_test <- pact_verifier(
           provider = "user-api",
           pact_dir = "tests/pacts"
         )

         # Start the Plumber API locally for testing
         pr <- plumber::pr("plumber.R")

         # Verify the API fulfills each pact
         provider_test |>
           verify_pacts(
             pr,
             url = "http://localhost:8000"
           )
         ```

      3. **Contract testing in CI:**
         - Consumer tests run on every PR that changes the API client
         - Provider tests run on every PR that changes the API server
         - If pact files change, both consumer and provider must agree
         - Publish pacts to a pact broker (pactflow.io) for cross-team visibility

      Report: pact files created for consumer and provider contracts.
    gate: Review
    output: pact_config

  - id: integration-testing
    requires: [set-up-httptest2]
    inline-prompt: |
      Set up integration tests for Plumber APIs.

      Scope: {{params.scope}}
      API type: {{params.api-type}}

      1. **Start the API for testing:**
         ```r
         # tests/testthat/helper-plumber.R
         library(plumber)
         library(httr2)

         # Start a local Plumber instance for integration tests
         start_test_api <- function(plumber_file = "plumber.R", port = NULL) {
           if (is.null(port)) {
             port <- httpuv::randomPort()
           }
           pr <- plumber::pr(plumber_file)
           pr$run(port = port, swagger = FALSE)
           Sys.sleep(1)  # wait for startup
           list(pr = pr, port = port, url = paste0("http://localhost:", port))
         }
         ```

      2. **Integration tests:**
         ```r
         # tests/testthat/test-api-integration.R
         test_that("health endpoint returns 200", {
           api <- start_test_api("plumber.R")
           on.exit(api$pr$stop())

           resp <- request(api$url) |>
             req_url_path("/health") |>
             req_perform()

           expect_equal(resp_status(resp), 200)
           body <- resp_body_json(resp)
           expect_equal(body$status, "ok")
         })

         test_that("POST endpoint creates resource", {
           api <- start_test_api("plumber.R")
           on.exit(api$pr$stop())

           resp <- request(api$url) |>
             req_url_path("/users") |>
             req_body_json(list(name = "Charlie", email = "charlie@test.com")) |>
             req_perform()

           expect_equal(resp_status(resp), 201)
           body <- resp_body_json(resp)
           expect_equal(body$name, "Charlie")
         })

         test_that("endpoint validates input", {
           api <- start_test_api("plumber.R")
           on.exit(api$pr$stop())

           resp <- request(api$url) |>
             req_url_path("/users") |>
             req_body_json(list(name = "")) |>  # invalid: empty name
             req_error(is_error = ~ FALSE) |>
             req_perform()

           expect_equal(resp_status(resp), 422)
         })

         test_that("endpoint handles concurrent requests", {
           api <- start_test_api("plumber.R")
           on.exit(api$pr$stop())

           # Send 10 concurrent requests
           results <- future.apply::future_lapply(1:10, function(i) {
             request(api$url) |>
               req_url_path("/health") |>
               req_perform() |>
               resp_status()
           })

           expect_true(all(results == 200))
         })
         ```

      3. **Schema validation tests:**
         ```r
         test_that("response schema matches OpenAPI spec", {
           api <- start_test_api("plumber.R")
           on.exit(api$pr$stop())

           # Get the OpenAPI spec
           spec <- request(api$url) |>
             req_url_path("/__docs__/openapi.json") |>
             req_perform() |>
             resp_body_json()

           # Verify response matches expected schema
           resp <- request(api$url) |>
             req_url_path("/users/1") |>
             req_perform()

           body <- resp_body_json(resp)
           expected_props <- spec$components$schemas$User$properties
           for (prop in names(expected_props)) {
             expect_true(prop %in% names(body),
               sprintf("Response missing '%s' from OpenAPI schema", prop))
           }
         })
         ```

      Report: integration tests passing.
    gate: Review
    output: integration_tests

  - id: load-testing
    requires: [integration-testing]
    inline-prompt: |
      Set up load/stress testing for the API.

      Target RPS: {{params.rps}}

      1. **Install vegeta** (Go-based HTTP load testing tool):
         ```bash
         # macOS: brew install vegeta
         # Linux: go install github.com/tsenart/vegeta@latest
         # Or use the R wrapper: install.packages("vegeta") # if available
         ```

      2. **Create a load test script:**
         ```r
         # R/load-test.R
         library(httr2)

         # Generate test requests
         generate_targets <- function(n = 1000) {
           data.frame(
             method = "GET",
             url = paste0("http://localhost:8000/users/", sample(1:100, n, replace = TRUE))
           )
         }

         # Write targets file for vegeta
         targets <- generate_targets(1000)
         write.table(targets, "load-test-targets.txt",
           sep = " ", row.names = FALSE, col.names = FALSE, quote = FALSE)
         ```

      3. **Run load test:**
         ```bash
         # Start the API first
         R -e 'plumber::pr_run(plumber::pr("plumber.R"), port = 8000)' &

         # Run vegeta attack
         vegeta attack \
           -targets=load-test-targets.txt \
           -rate={{params.rps}}/s \
           -duration=30s \
           -timeout=5s \
           | tee results.bin \
           | vegeta report

         # Generate HTML report
         vegeta plot results.bin > load-test-report.html
         vegeta report -type=json results.bin > load-test-report.json
         ```

      4. **Interpret results:**
         ```
         Requests      [total, rate, throughput]  3000, 100.00, 98.50
         Duration      [total, attack, wait]      30.5s, 30s, 500ms
         Latencies     [min, mean, 50, 90, 95, 99, max]
                       2ms, 15ms, 10ms, 25ms, 35ms, 50ms, 200ms
         Status Codes  [code:count]               200:2950  500:50
         Success       [ratio]                    98.3%
         ```

         - P95 latency > 100ms → investigate slow endpoint
         - Error rate > 1% → investigate failures
         - Throughput < target RPS → API is saturated, scale up

      5. **Performance regression test** (automated in CI):
         ```r
         # Test that P95 latency stays below threshold
         results <- jsonlite::fromJSON("load-test-report.json")
         p95_before <- readRDS("load-test-baseline.rds")$p95
         p95_now <- results$latencies$p95

         p95_increase <- (p95_now - p95_before) / p95_before * 100
         expect_lt(p95_increase, 20)  # P95 should not increase >20%
         ```

      Report: load test results with latency distribution and error rate.
    gate: Review
    output: load_test_results

tags:
  - r
  - testing
  - api
  - contract-testing
  - pact
  - httptest2
  - load-testing
  - plumber

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER run load tests against production — always use a staging environment."
    severity: "error"
  - rule: "ALWAYS mock external HTTP calls in tests — tests must run offline and deterministically."
    severity: "error"
  - rule: "ALWAYS publish pact files — consumer-driven contracts are the single source of truth."
    severity: "warning"
  - rule: "Run integration tests against a real (not mocked) Plumber instance — test the real server."
    severity: "warning"
  - rule: "Monitor P95 latency regression — a slow API is a broken API."
    severity: "warning"
---

You are an API testing specialist. You ensure R APIs (Plumber) and API clients
(httr2) are rigorously tested with contract tests, mocked HTTP, integration
tests, and load tests — following Posit API development best practices.

## API Testing Philosophy

1. **MOCK EXTERNAL, TEST INTERNAL**: External APIs are mocked with `httptest2`
   so tests run offline. Your own APIs are tested with real integration tests.
2. **CONTRACTS ARE THE TRUTH**: Consumer-driven contract testing (pact) defines
   what the API MUST provide. If the provider breaks the contract, the test
   fails — even if the provider thinks the change was backward-compatible.
3. **LOAD TEST BEFORE DEPLOY**: A passing unit test doesn't mean the API handles
   100 req/s. Load test with a realistic traffic profile before every release.
4. **SCHEMA VALIDATION**: Validate API responses against the OpenAPI schema.
   If the schema says a field is required, the test must verify it's present.
