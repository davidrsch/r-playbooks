---
name: r-shiny-module
version: 1.0.0
context-mode: Fork
description: Create a new Shiny module (UI + server) with reactive testing in an existing app or golem project
trigger: both
trigger-patterns:
  - "shiny module *"
  - "add module *"
  - "new shiny module *"
  - "create module *"
argument-hint: "--name <module_name> [--framework golem|minimal] [--with-test true|false]"
parameters:
  name:
    type: String
    required: true
    hint: "Module name (snake_case, e.g., data_table, file_upload)"
  framework:
    type: String
    required: false
    default: "golem"
    enum: ["golem", "minimal"]
    hint: "Project framework: golem or minimal Shiny app"
  with-test:
    type: Boolean
    required: false
    default: true
    hint: "Create a testthat test for the module server function"
  description:
    type: String
    required: false
    hint: "Purpose of the module, e.g., 'Data table with filtering and export for sales records'"
steps:
  - id: analyze-context
    inline-prompt: |
      Analyze the existing Shiny project to understand module conventions:

      1. Check if in a golem project (has `golem::` in DESCRIPTION or dev/ folder).
         Override framework: {{params.framework}}
      2. List existing modules: `R/mod_*.R` files.
      3. Read one existing module to understand the naming and structure conventions.
      4. Read `R/app_ui.R` (golem) or `app.R` (minimal) to understand where modules
         are called and how they connect.
      5. Check for name collisions:
         - Does `mod_{{params.name}}` already exist?
         - Does the name conflict with any Shiny built-in IDs (e.g., `navbar`, `sidebar`)?
         - Verify the module name does not shadow a Shiny function name.
      6. Report:
         - Framework detected: golem / minimal
         - Existing modules: list
         - Module prefix convention (e.g., `mod_`)
         - Naming patterns: how are UI/server functions named
         - Current app structure (which modules call which)
    output: context

  - id: design-module
    requires: [analyze-context]
    inline-prompt: |
      Design the module interface for `mod_{{params.name}}`.

      Context: {{state.context}}
      Description: {{params.description}}

      Design and report:
      1. **Module file**: `R/mod_{{params.name}}.R`
      2. **UI function**: `mod_{{params.name}}_ui(id, ...)` — what it renders
      3. **Server function**: `mod_{{params.name}}_server(id, ...)` — reactive logic
      4. **Inputs**: What UI inputs does the module provide?
      5. **Outputs**: What reactive outputs does it produce?
      6. **Parameters**: Additional arguments beyond `id` (e.g., data, config)
      7. **Return value**: What the server function returns (reactive or list of reactives)
      8. **Dependencies**: Packages needed (bslib, DT, plotly, etc.)

      Follow golem/module conventions:
      - UI returns `tagList()` of Shiny UI elements
      - Server uses `moduleServer(id, function(input, output, session) {...})`
      - Return reactive values, not rendered output
      - Use `ns <- NS(id)` for input/output IDs
    gate: Confirm
    output: design

  - id: implement-module
    requires: [design-module]
    inline-prompt: |
      Implement the module based on the design.

      Design: {{state.design}}

      Create or update `R/mod_{{params.name}}.R`:

      ```r
      box::use(
        shiny[moduleServer, NS, tagList, reactiveVal, req],
        bslib[card, card_header, card_body, navset_card_tab, value_box],
        logger[log_info, log_error],
      )

      #' @title <Module Title>
      #'
      #' @description <What this module does>
      #'
      #' @param id Module ID for namespacing
      #' @param ... Additional parameters as designed
      #'
      #' @return <What the server function returns>
      #'
      #' @export
      mod_{{params.name}}_ui <- function(id, ...) {
        ns <- NS(id)
        log_info("Module UI loaded", module = "{{params.name}}")
        tagList(
          # Use bslib components for consistent theming
          card(
            id = ns("main_card"),
            card_header("Module Title"),
            card_body(
              # Module UI elements here using ns()
            )
          )
        )
      }

      #' @rdname mod_{{params.name}}_ui
      #' @export
      mod_{{params.name}}_server <- function(id, ...) {
        moduleServer(id, function(input, output, session) {
          log_info("Module server loaded", module = "{{params.name}}")
          # Module reactive logic here
          # For long-running operations, use mirai::mirai() for non-blocking async execution
          # For expensive reactive outputs, use bindCache() to cache results:
          #   output$plot <- renderPlot({...}) |> bindCache(input$var)
          # Return reactive values
        })
      }
      ```

      Implementation checklist:
      ✅ UI function creates namespaced elements with ns()
      ✅ Server function wraps logic in moduleServer()
      ✅ Server returns reactive values (not renders)
      ✅ No `<<-` superassignment
      ✅ Uses `req()` for required inputs
      ✅ Handles NULL/empty inputs gracefully
      ✅ Uses `session$onSessionEnded()` to clean up reactivePoll/reactiveFileReader observers
      ✅ Consistent with existing module conventions

      If the framework is golem, run: `golem::document_and_reload()` to update NAMESPACE.
      For non-golem projects, manually source the module file or use `box::use()`.

      After module creation, run `styler::style_file("R/mod_{{params.name}}.R")`
      to ensure consistent formatting.
    gate: Review
    output: implementation

  - id: write-test
    requires: [implement-module]
    inline-prompt: |
      Write a test for the module server function when `with-test` is enabled.

      If with-test is false, skip test creation and report: skipped.

      When with-test is true, create `tests/testthat/test-mod_{{params.name}}.R`:

      Use `testServer()` from Shiny to test the server function:

      ```r
      test_that("mod_{{params.name}}_server works", {
        testServer(mod_{{params.name}}_server, args = list(), {
          # Set inputs
          session$setInputs(...)

          # Check outputs
          expect_equal(output$..., ...)
        })
      })

      test_that("mod_{{params.name}}_server handles edge cases", {
        testServer(mod_{{params.name}}_server, args = list(), {
          # Test with NULL/empty inputs
          session$setInputs(...)
          expect_error(output$..., NA)
        })
      })

      # Use session$returned to inspect the module's return value
      expect_equal(session$returned()$my_reactive(), expected_value)
      ```

      Run: `devtools::test(filter = "mod_{{params.name}}")`

      Also consider adding a `shinytest2` integration test that records
      and replays the full Shiny app interaction with the new module:
      ```r
      # tests/testthat/test-shinytest2-mod_{{params.name}}.R
      test_that("module integrates in full app", {
        app <- shinytest2::AppDriver$new(test_path("../../"))
        app$set_inputs(`{{params.name}}_1-input_id` = "test value")
        app$wait_for_idle()
        expect_equal(app$get_value(output = "{{params.name}}_1-output_id"), "expected")
      })
      ```

      Report: tests written and results.

      If with-test is false, this step reports: skipped.
    gate: Review
    output: test_result

  - id: integrate
    requires: [implement-module]
    inline-prompt: |
      Provide integration instructions for the new module.

      1. Show how to call the module from `app_ui.R` or `app.R`:
         ```r
         mod_{{params.name}}_ui("{{params.name}}_1")
         ```
      2. Show how to call the server from `app_server.R` or `app.R`:
         ```r
         result <- mod_{{params.name}}_server("{{params.name}}_1")
         ```
      3. If there are parameters, show example with parameter values.
      4. Remind the user to reload the package/app before using the module.
      5. If golem framework, run: `golem::document_and_reload()` then `devtools::check()`
         (R CMD check) to verify module integrates cleanly.

      Report: integration code snippet.
    gate: Confirm
    output: integration_guide

tags:
  - r
  - shiny
  - module
  - component

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are a Shiny module developer specializing in composable, testable
UI components following the Mastering Shiny module design patterns.

## Rules

1. ALWAYS use `box::use()` for imports — never `source()` or `library()` in module files.
2. ALWAYS use `moduleServer(id, function(input, output, session) {...})`.
3. ALWAYS use `ns <- NS(id)` in the UI function for input/output namespacing.
4. Module UI functions return `tagList(...)` or a single tag, not `fluidPage()`.
   Prefer `{bslib}` components (card, value_box, navset_card_tab) over base Shiny UI
   for consistent theming.
5. Module server functions return reactive values, NOT rendered outputs.
6. NEVER use `<<-` in modules — use `reactiveValues()` or return values.
7. Use `req()` to guard against missing/uninitialized inputs.
8. Module file names: `mod_<name>.R` with UI and server in the same file.
9. Export module functions with `@export` so golem can find them.
10. Test modules with `testServer()` — it provides isolated server context.
11. Document module parameters with roxygen2 `@param` tags.
12. Use `logger::log_info()` and `logger::log_error()` for structured logging within modules.
13. For long-running operations in the server function, use `mirai::mirai()` for non-blocking
    async execution.
14. For production Shiny apps, set `OTEL_SERVICE_NAME` and `OTEL_EXPORTER_OTLP_ENDPOINT`
    env vars for automatic distributed tracing (Shiny 1.12+).
