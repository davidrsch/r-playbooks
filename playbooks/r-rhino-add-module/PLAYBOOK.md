---
name: r-rhino-add-module
version: 1.0.0
context-mode: Fork
description: "Add a new box module (view/logic) to an existing rhino project following enterprise conventions"
trigger: both
trigger-patterns:
  - "rhino *"
  - "shiny *"
  - "rhino module *"
  - "add rhino module *"
  - "new rhino module *"
  - "create rhino module *"
  - "rhino box module *"
argument-hint: "--name <module_name> --type view|logic|both [--with-test true|false] [--description <purpose>]"
parameters:
  name:
    type: String
    required: true
    hint: "Module name in snake_case, e.g., 'sales_table' or 'patient_filter'"
  type:
    type: String
    required: false
    default: "both"
    enum: ["view", "logic", "both"]
    hint: "Module type: view (UI), logic (server processing), or both"
  with-test:
    type: Boolean
    required: false
    default: true
    hint: "Create a testthat test file for the module"
  description:
    type: String
    required: false
    hint: "Purpose of the module, e.g., 'Sortable, filterable data table for sales records with CSV export'"
steps:
  - id: validate-rhino-project
    inline-prompt: |
      Verify this is a valid rhino project:

      1. Check for `.rhino.yml` in the project root.
         If not found, abort: "Not a rhino project. Use r-rhino-init to create one."
      2. Read `.rhino.yml` for project configuration.
      3. Verify rhino is installed: `packageVersion("rhino")`
      4. Verify the expected directory structure exists:
         - `app/view/` (for view modules)
         - `app/logic/` (for logic modules)
      5. List existing modules to avoid name collisions:
         ```r
         list.files("app/view/", pattern = "\\.R$")
         list.files("app/logic/", pattern = "\\.R$")
         ```
      6. Check for name collision: does a module named {{params.name}} already exist?
         If yes, abort or ask to update instead.
      7. Report: project name, existing modules, name available.
    output: project-info

  - id: analyze-conventions
    requires:
      - validate-rhino-project
    inline-prompt: |
      Analyze existing module conventions to match style:

      1. Read 1-2 existing view modules from `app/view/` to understand:
         - Import style (which packages are commonly used: bslib, DT, plotly, etc.)
         - Function naming convention
         - UI structure (cards, navs, layouts)
         - Return value conventions
         - Logging patterns
      2. Read 1-2 existing logic modules from `app/logic/` to understand:
         - Data processing patterns
         - Error handling conventions
         - Reactive patterns (reactive(), reactiveVal(), reactiveValues())
      3. Read `app/main.R` to understand:
         - How modules are assembled
         - The app's overall structure
         - Any shared reactive data sources
      4. Report:
         - View conventions summarized
         - Logic conventions summarized
         - Packages commonly used
         - How the new module fits into the existing structure
    output: conventions

  - id: design-module
    requires:
      - analyze-conventions
    inline-prompt: |
      Design the module interface based on the description.

      Type: {{params.type}}
      Description: {{params.description}}

      Design and report:
      1. **View module** (if type is view or both):
         - File: `app/view/{{params.name}}.R`
         - UI function: `ui <- function(id, ...)`
         - What Shiny elements it renders
         - Parameters beyond `id`
         - What the user sees (describe layout)

      2. **Logic module** (if type is logic or both):
         - File: `app/logic/{{params.name}}.R`
         - Logic function: `server <- function(id, data, ...)`
         - What it processes/computes
         - Parameters (data sources, config)
         - Return value (reactive, list of reactives, etc.)
         - Error handling strategy

      3. **Dependencies**: New packages needed (add to DESCRIPTION/dependencies.R)

      Follow rhino conventions:
      - View exports `ui` function: returns Shiny tags
      - Logic exports `server` function: returns reactive values
      - View may use logic: `box::use(app/logic/{{params.name}}[server = logic_server])`
      - Communicate via parameters and return values, NEVER via global state
    gate: Confirm
    output: design

  - id: create-view-module
    requires:
      - design-module
    inline-prompt: |
      Create the view module when type is view or both.

      If type is logic only, skip and report: "View module skipped (logic-only)."

      Create `app/view/{{params.name}}.R`:

      ```r
      box::use(
        shiny[moduleServer, NS, tagList, reactiveVal, req, observeEvent],
        bslib[card, card_header, card_body, value_box],
        logger[log_info, log_error, log_debug],
        app / logic / {{params.name}}[server =
          if (exists("{{params.name}}_server")) {
            {{params.name}}_server
          }
        ],
      )

      #' @title <Module Title>
      #'
      #' @description {{params.description}}
      #'
      #' @param id Module ID for namespacing.
      #' @param ... Additional arguments passed to the logic server.
      #'
      #' @export
      ui <- function(id, ...) {
        ns <- NS(id)
        log_info("Loading {{params.name}} view module", module = "{{params.name}}")

        tagList(
          card(
            id = ns("main_card"),
            full_screen = TRUE,
            card_header("<Module Title>"),
            card_body(
              # Module UI elements here — use ns() for all IDs
              # Example: shiny::textOutput(ns("result"))
            )
          )
        )
      }

      #' @rdname ui
      #' @export
      server <- function(id, ...) {
        moduleServer(id, function(input, output, session) {
          log_info("Initializing {{params.name}} server module", module = "{{params.name}}")

          # Call logic module if applicable
          # result <- logic_server(id, ...)

          # Reactive outputs
          # output$result <- renderText({ ... })

          # Clean up observers
          session$onSessionEnded(function() {
            log_info("Cleaning up {{params.name}} observers", module = "{{params.name}}")
          })
        })
      }
      ```

      Implementation checklist:
      ✅ Use `box::use()` for ALL imports (no library() or source())
      ✅ Use `NS(id)` for input/output namespacing in UI
      ✅ Use `req()` to guard against missing inputs
      ✅ Use `logger::log_*()` for structured logging
      ✅ No `<<-` superassignment
      ✅ `@export` roxygen tag on both ui and server functions
      ✅ Clean up observers in session$onSessionEnded

      After creation, format: `styler::style_file("app/view/{{params.name}}.R")`
    output: view-file

  - id: create-logic-module
    requires:
      - design-module
    inline-prompt: |
      Create the logic module when type is logic or both.

      If type is view only, skip and report: "Logic module skipped (view-only)."

      Create `app/logic/{{params.name}}.R`:

      ```r
      box::use(
        dplyr[filter, mutate, select, group_by, summarise, n, arrange],
        logger[log_info, log_error, log_debug, log_warn],
        stats[median, sd],
      )

      #' @title <Logic Module Title>
      #'
      #' @description {{params.description}}
      #'
      #' @param data A reactive data.frame to process.
      #' @param ... Additional parameters.
      #'
      #' @return A reactive containing the processed result.
      #'
      #' @export
      server <- function(id, data, ...) {
        log_info("Initializing {{params.name}} logic module", module = "{{params.name}}")

        # Input validation
        stopifnot("data must be a reactive" = shiny::is.reactive(data))

        # Reactive processing
        result <- reactive({
          req(data())

          log_debug("Processing data in {{params.name}}", module = "{{params.name}}",
                    rows = nrow(data()))

          data() |>
            # Data processing pipeline here
            identity()
        }) |>
          shiny::bindCache(data())

        return(result)
      }
      ```

      Implementation checklist:
      ✅ Input validation with stopifnot() or custom checks
      ✅ Use req() for reactive dependencies
      ✅ Return reactive values, not static values
      ✅ Use bindCache() for expensive computations
      ✅ Use logger for all logging
      ✅ Handle edge cases: NULL, empty, missing columns
      ✅ Consistent with existing logic module patterns

      After creation, format: `styler::style_file("app/logic/{{params.name}}.R")`
    output: logic-file

  - id: create-test
    requires:
      - create-view-module
      - create-logic-module
    inline-prompt: |
      Create a test file when with-test is enabled.

      If with-test is false, skip and report: "Test creation skipped."

      Create `tests/testthat/test-{{params.name}}.R`:

      ```r
      box::use(
        testthat[...],
        shiny[testServer, reactiveVal],
      )

      box::use(
        app / logic / {{params.name}}[logic_server = server],
      )

      test_that("{{params.name}} logic handles empty input", {
        test_data <- reactiveVal(data.frame())
        result <- logic_server("test", data = test_data)
        expect_s3_class(result(), "data.frame")
        expect_equal(nrow(result()), 0)
      })

      test_that("{{params.name}} logic handles NULL input", {
        test_data <- reactiveVal(NULL)
        expect_error(logic_server("test", data = test_data))
      })

      test_that("{{params.name}} logic computes correctly", {
        test_data <- reactiveVal(data.frame(x = 1:5, y = 6:10))
        result <- logic_server("test", data = test_data)
        expect_s3_class(result(), "data.frame")
        # Add specific expectations based on the module's purpose
      })

      # View module tests (when view module exists)
      # test_that("{{params.name}} view renders", {
      #   testServer(app/view/{{params.name}}[server], args = list(), {
      #     session$setInputs(...)
      #     expect_s3_class(output$..., "shiny.render.function")
      #   })
      # })

      # Snapshot test for UI
      # test_that("{{params.name}} UI snapshot", {
      #   expect_snapshot(app/view/{{params.name}}[ui]("test"))
      # })
      ```

      Run the test: `rhino::test_r()`
      Verify all tests pass before reporting.
    output: test-file

  - id: integrate-module
    requires:
      - create-view-module
      - create-logic-module
      - create-test
    inline-prompt: |
      Provide integration instructions and update the app's main.R:

      1. Show how to call the module from `app/main.R`:

         ```r
         # app/main.R
         box::use(
           shiny[...],
           bslib[...],
           logger[log_info, log_threshold],
           app / view / {{params.name}}[{{params.name}}_ui = ui, {{params.name}}_server = server],
         )

         #' @export
         ui <- function(id) {
           ns <- NS(id)
           tagList(
             {{params.name}}_ui(ns("{{params.name}}"))
           )
         }

         #' @export
         server <- function(id) {
           moduleServer(id, function(input, output, session) {
             {{params.name}}_server("{{params.name}}")
           })
         }
         ```

      2. For logic-only modules, show how to import and use:
         ```r
         box::use(
           app / logic / {{params.name}}[{{params.name}}_server = server],
         )
         result <- {{params.name}}_server("id", data = my_data)
         ```

      3. If new packages were added, remind to:
         - Add to `dependencies.R`: `library(<pkg>)`
         - Run: `renv::install()` to install new deps
         - Run: `renv::snapshot()` to update lockfile

      4. Verify the app runs: `rhino::devmode()` or `shiny::runApp("app")`
      5. Report: integration code, any manual steps needed.
    gate: Confirm
    output: integration-guide

tags:
  - r
  - shiny
  - rhino
  - module
  - box
  - enterprise

constraints:
  - rule: "NEVER use global variables for module state — communicate via parameters and return values."
    severity: "error"
  - rule: "NEVER use source() or library() in module files — use box::use()."
    severity: "error"
  - rule: "ALWAYS export ui and server functions with @export."
    severity: "error"
  - rule: "ALWAYS validate inputs in logic modules."
    severity: "warning"
  - rule: "Use logger package for structured logging, not print() or cat()."
    severity: "warning"
  - rule: "Use bindCache() for expensive reactive computations."
    severity: "warning"

allowed-tools:
  - "*"
---

# R Rhino Add Module Playbook

You are an expert rhino module developer. Rhino (Appsilon's enterprise Shiny framework) uses
`box::use()` modules following a strict view/logic separation pattern.

## Module Architecture

```
app/
├── main.R              # Entry point — assembles modules
├── view/               # UI modules (what users see)
│   └── <feature>.R     # exports: ui(), server()
├── logic/              # Server logic modules (business rules, data processing)
│   └── <feature>.R     # exports: server()
├── styles/             # Sass (.scss) stylesheets
│   └── main.scss       # Import Bootstrap + custom styles
└── static/             # Compiled CSS/JS (gitignored)
```

## View Module Pattern

```r
# app/view/<name>.R
box::use(
  shiny[moduleServer, NS, tagList, ...],
  bslib[card, card_header, card_body, ...],
  logger[log_info, log_error],
)

#' @export
ui <- function(id, ...) {
  ns <- NS(id)
  tagList(
    card(...)
  )
}

#' @export
server <- function(id, ...) {
  moduleServer(id, function(input, output, session) {
    # Reactive outputs
    # Return reactive values
  })
}
```

## Logic Module Pattern

```r
# app/logic/<name>.R
box::use(
  dplyr[...],
  logger[log_info, log_error],
)

#' @export
server <- function(id, data, ...) {
  stopifnot("data must be a reactive" = shiny::is.reactive(data))

  result <- reactive({
    req(data())
    # Process data
  }) |> shiny::bindCache(data())

  return(result)
}
```

## Key Conventions

1. **Imports**: ALWAYS `box::use()`, NEVER `library()` or `source()`
2. **View modules**: Located in `app/view/`, export `ui()` and `server()`
3. **Logic modules**: Located in `app/logic/`, export `server()` only (or processing functions)
4. **Communication**: Via function parameters and return values, NEVER global state
5. **Logging**: Use `logger::log_info()`, `logger::log_debug()`, `logger::log_error()`
6. **Error handling**: Validate inputs with `stopifnot()`, use `req()` for reactive guards
7. **Performance**: `bindCache()` for expensive computations, `mirai::mirai()` for async
8. **Testing**: testthat with `testServer()` for server logic, `expect_snapshot()` for UI
