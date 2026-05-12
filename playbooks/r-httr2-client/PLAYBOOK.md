---
name: r-httr2-client
version: 1.0.0
context-mode: Fork
description: "Build a typed R API client package using {httr2}: OAuth2/API-key auth, retry logic, rate limiting, mocked tests, and httr2 request/response helpers"
trigger: both
trigger-patterns:
  - "api client *"
  - "httr2 *"
  - "rest client *"
  - "http client *"
  - "build api client *"
  - "wrap api *"
argument-hint: "--api-name <name> --base-url <url> [--auth apikey|oauth2|bearer|none] [--package true|false]"
parameters:
  api-name:
    type: String
    required: true
    hint: "Short name of the API (e.g. 'github', 'stripe') — used for function prefixes"
  base-url:
    type: String
    required: true
    hint: "Base URL of the API (e.g. 'https://api.github.com')"
  auth:
    type: String
    required: false
    default: "apikey"
    enum: ["apikey", "oauth2", "bearer", "none"]
    hint: "Authentication method"
  package:
    type: Boolean
    required: false
    default: true
    hint: "Build as an R package (true) or a standalone script (false)"
  rate-limit:
    type: Boolean
    required: false
    default: true
    hint: "Add rate limiting / retry logic"
steps:
  - id: scaffold-structure
    inline-prompt: |
      Set up the project structure for the API client.

      API name: {{params.api-name}}
      Package: {{params.package}}

      If package is true:
      1. Create a new package: `usethis::create_package("{{params.api-name}}r")` (or chosen name)
      2. Install httr2: `pak::pak("httr2")`
      3. Add to DESCRIPTION Imports: `usethis::use_package("httr2")`
      4. Create `R/client.R` — the base request builder

      If package is false:
      1. Create `{{params.api-name}}_client.R`
      2. Add `library(httr2)` at the top

      Report: structure created.
    gate: Confirm
    output: structure

  - id: build-base-request
    requires: [scaffold-structure]
    inline-prompt: |
      Create the base request builder function.

      API name: {{params.api-name}}
      Base URL: {{params.base-url}}
      Auth method: {{params.auth}}
      Rate limit: {{params.rate-limit}}

      Create `R/client.R`:

      ```r
      #' Build a base httr2 request for the {{params.api-name}} API
      #'
      #' @param path API path (e.g. "/users/42")
      #' @return An httr2 request object
      #' @export
      {{params.api-name}}_request <- function(path = "") {
        base <- "{{params.base-url}}"

        req <- httr2::request(paste0(base, path)) |>
          httr2::req_user_agent("{{params.api-name}}r/0.1.0 (https://github.com/author/{{params.api-name}}r)")
      ```

      Add auth header based on {{params.auth}}:

      **apikey:**
      ```r
          req <- req |>
            httr2::req_auth_bearer_token(
              Sys.getenv("{{params.api-name|upper}}_API_KEY")
            )
      ```

      **bearer:**
      ```r
          req <- req |>
            httr2::req_auth_bearer_token(
              Sys.getenv("{{params.api-name|upper}}_TOKEN")
            )
      ```

      **oauth2:**
      ```r
          oauth_client <- httr2::oauth_client(
            id     = Sys.getenv("{{params.api-name|upper}}_CLIENT_ID"),
            secret = Sys.getenv("{{params.api-name|upper}}_CLIENT_SECRET"),
            token_url = paste0(base, "/oauth/token")
          )
          req <- req |>
            httr2::req_oauth_client_credentials(oauth_client)
      ```

      Add rate limiting and retry if rate-limit is true:
      ```r
          req <- req |>
            httr2::req_retry(
              max_tries = 3,
              is_transient = \(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504),
              backoff = \(i) 2^i  # exponential backoff: 2s, 4s, 8s
            ) |>
            httr2::req_throttle(rate = 60 / 60)  # 60 req/min
      ```

      Close the function:
      ```r
        req
      }
      ```

      Report: base request function created.
    output: base_request

  - id: add-endpoint-helpers
    requires: [build-base-request]
    inline-prompt: |
      Add typed endpoint helper functions.

      API name: {{params.api-name}}
      Base URL: {{params.base-url}}

      Create `R/endpoints.R` with at least two example endpoints inferred from the API:

      ```r
      #' List resources from {{params.api-name}}
      #'
      #' @param page Page number (default: 1)
      #' @param per_page Items per page (default: 30)
      #' @return A list parsed from the JSON response
      #' @export
      {{params.api-name}}_list <- function(page = 1L, per_page = 30L) {
        {{params.api-name}}_request("/items") |>
          httr2::req_url_query(page = page, per_page = per_page) |>
          httr2::req_perform() |>
          httr2::resp_body_json(simplifyVector = TRUE)
      }

      #' Get a single resource by ID
      #'
      #' @param id Resource ID
      #' @return A list parsed from the JSON response
      #' @export
      {{params.api-name}}_get <- function(id) {
        rlang::check_required(id)
        {{params.api-name}}_request(paste0("/items/", id)) |>
          httr2::req_perform() |>
          httr2::resp_body_json()
      }

      #' Create a new resource
      #'
      #' @param body Named list of fields to create
      #' @return Created resource as a list
      #' @export
      {{params.api-name}}_create <- function(body) {
        rlang::check_required(body)
        {{params.api-name}}_request("/items") |>
          httr2::req_method("POST") |>
          httr2::req_body_json(body) |>
          httr2::req_perform() |>
          httr2::resp_body_json()
      }
      ```

      Add a response error handler:
      ```r
      # In client.R — add after req_throttle():
          req <- req |>
            httr2::req_error(body = function(resp) {
              err <- httr2::resp_body_json(resp)
              err$message %||% paste("HTTP", httr2::resp_status(resp))
            })
      ```

      Report: endpoint helpers created.
    gate: Review
    output: endpoints

  - id: add-pagination
    requires: [add-endpoint-helpers]
    inline-prompt: |
      Add automatic pagination support for list endpoints.

      Use `httr2::req_perform_iterative()` for cursor/page-based pagination:

      ```r
      #' List ALL resources (auto-paginated)
      #'
      #' @param max_pages Maximum pages to fetch (default: Inf)
      #' @return A data frame with all results combined
      #' @export
      {{params.api-name}}_list_all <- function(max_pages = Inf) {
        pages <- httr2::req_perform_iterative(
          {{params.api-name}}_request("/items") |>
            httr2::req_url_query(per_page = 100),
          next_req = httr2::iterate_with_link_url("next"),  # for Link header pagination
          max_reqs = max_pages
        )

        # Combine all pages into one data frame
        purrr::map(pages, httr2::resp_body_json, simplifyVector = TRUE) |>
          purrr::list_rbind()
      }
      ```

      For offset pagination (page number), use `iterate_with_offset_page("page")`.
      For cursor pagination, implement a custom `next_req` function that reads the
      next cursor from the response body.

      Report: pagination helper created.
    output: pagination

  - id: write-tests
    requires: [add-pagination]
    inline-prompt: |
      Write unit tests using httr2's request mocking.

      Create `tests/testthat/test-{{params.api-name}}.R`:

      ```r
      test_that("{{params.api-name}}_request builds correct base URL", {
        req <- {{params.api-name}}_request("/items")
        expect_equal(req$url, "{{params.base-url}}/items")
      })

      test_that("{{params.api-name}}_list returns parsed JSON", {
        local_mocked_bindings(
          req_perform = function(req, ...) {
            httr2::response(
              status_code = 200L,
              headers = list("Content-Type" = "application/json"),
              body = charToRaw('[{"id": 1, "name": "test"}]')
            )
          },
          .package = "httr2"
        )

        result <- {{params.api-name}}_list()
        expect_equal(nrow(result), 1L)
        expect_equal(result$id, 1L)
      })

      test_that("{{params.api-name}}_get handles 404 gracefully", {
        local_mocked_bindings(
          req_perform = function(req, ...) {
            httr2::response(status_code = 404L,
              headers = list("Content-Type" = "application/json"),
              body = charToRaw('{"message": "Not found"}'))
          },
          .package = "httr2"
        )
        expect_error({{params.api-name}}_get(99999), "Not found|404")
      })
      ```

      Run tests: `devtools::test()`
      Report: test results.
    gate: Review
    output: test_results

  - id: document-and-finalise
    requires: [write-tests]
    inline-prompt: |
      Add documentation and finalise the package.

      1. Create a package-level roxygen doc in `R/{{params.api-name}}r-package.R`:
         ```r
         #' {{params.api-name}}r: R client for the {{params.api-name}} API
         #'
         #' Provides typed R functions to interact with the {{params.api-name}} REST API.
         #'
         #' @section Authentication:
         #' Set the `{{params.api-name|upper}}_API_KEY` environment variable before use.
         #' Use [{{params.api-name}}_request()] to build authenticated requests.
         #'
         #' @docType package
         #' @name {{params.api-name}}r-package
         "_PACKAGE"
         ```

      2. Run `devtools::document()` to generate NAMESPACE and man/ files.
      3. Run `devtools::check(cran = TRUE)` — target 0 errors, 0 warnings.
      4. Add a `README.md` with installation and quick-start example.

      Report: documentation complete and check results.
    output: documentation

tags:
  - r
  - httr2
  - api
  - http
  - client
  - rest

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER hardcode API keys in source code — always use Sys.getenv()."
    severity: "error"
  - rule: "ALWAYS include req_retry() with exponential backoff for transient HTTP errors."
    severity: "warning"
  - rule: "ALWAYS use local_mocked_bindings() in tests — never make real HTTP calls in tests."
    severity: "error"
  - rule: "ALWAYS include a req_user_agent() identifying the package and version."
    severity: "warning"
  - rule: "NEVER export internal helpers — only export user-facing endpoint functions."
    severity: "warning"
---

You are an R API client developer using {httr2}. You build robust, well-tested
R packages that wrap REST APIs with proper auth, retry logic, and pagination.

## Rules

1. All API keys go in environment variables, never in source code.
2. Always set a User-Agent header identifying the package (`req_user_agent()`).
3. Always add retry logic for 429, 5xx errors with exponential backoff.
4. Use `req_throttle()` to respect API rate limits.
5. Mock all HTTP calls in tests using `local_mocked_bindings()` — tests must be
   offline-capable (skip_on_cran() if any test does require internet).
6. Use `req_perform_iterative()` for auto-pagination — do not implement manual loops.
7. Use `req_error(body = ...)` to extract meaningful error messages from API responses.
8. For OAuth2, use httr2's built-in OAuth flows — do not implement the exchange manually.
