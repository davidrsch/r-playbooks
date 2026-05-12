---
name: r-init-shiny
version: 1.0.0
context-mode: Fork
description: "Scaffold a new Shiny application with golem or minimal structure, plus testthat unit tests, Cypress E2E test setup, renv dependency management, and Posit Connect deployment config"
trigger: auto
trigger-patterns:
  - "shiny *"
  - "init shiny *"
  - "scaffold shiny *"
  - "create shiny app *"
  - "new shiny app *"
  - "initialize shiny *"
argument-hint: "--name <app_name> [--framework golem|minimal] [--renv true|false] [--modules true|false]"
parameters:
  name:
    type: String
    required: true
    hint: "Application name (lowercase, letters/numbers/underscores/dots; must start with letter)"
  framework:
    type: String
    required: false
    default: "golem"
    enum: ["golem", "minimal"]
    hint: "Framework: golem (production-grade) or minimal (single app.R)"
  renv:
    type: Boolean
    required: false
    default: true
    hint: "Initialize renv for dependency management"
  modules:
    type: Boolean
    required: false
    default: true
    hint: "Set up Shiny module structure (R/mod_*.R)"
steps:
  - id: validate-name
    inline-prompt: |
      Validate the app name "{{params.name}}":
      - Lowercase letters, numbers, and underscores only
      - Does not conflict with existing R packages
      - Not already a directory in the current workspace
      Report: valid/invalid.
    output: name_check

  - id: scaffold
    requires: [validate-name]
    inline-prompt: |
      The user chose framework: {{params.framework}}.
      If the framework is "golem", scaffold a golem-based Shiny application:

      1. Run: `golem::create_golem("{{params.name}}", open = FALSE)`
      2. Verify the directory structure:
         - `R/`: modules (mod_*.R), app_server.R, app_ui.R, run_app.R
         - `inst/`: www/, app/www/
         - `dev/`: run_dev.R, 01_start.R, 02_dev.R, 03_deploy.R
         - `DESCRIPTION` and `NAMESPACE`
      3. The golem app is also an R package: verify it can be loaded.
      4. Run: `golem::add_module("main")` to create the default module.
      5. Run: `golem::add_external_resources()` to configure external resources.

      Report: directory created, structure verified.

      If the framework is "minimal", scaffold a minimal Shiny application:

      1. Create directory `{{params.name}}/`
      2. Create `app.R` with:
         ```r
         library(shiny)

         ui <- fluidPage(theme = bslib::bs_theme(version = 5),
           titlePanel("{{params.name}}"),
           sidebarLayout(
             sidebarPanel(
               h3("Controls"),
               # Add inputs here
             ),
             mainPanel(
               h3("Output"),
               # Add outputs here
             )
           )
         )

         server <- function(input, output, session) {
           # Add server logic here
         }

         shinyApp(ui, server)
         ```
      3. Create `R/` directory for helper functions and modules.
      4. Create `www/` directory for static assets (CSS, JS, images).
      5. Create `data/` directory for app data.

      Report: files created.
    gate: Confirm
    output: scaffold_result

  - id: setup-renv
    requires: [scaffold]
    inline-prompt: |
      If the user specified 'renv' as true (value: {{params.renv}}):
      Initialize renv in the app directory:

      1. Run: `renv::init(project = "{{params.name}}")`
      2. If golem, the DESCRIPTION already has dependencies: run `renv::hydrate()`.
      3. Verify renv.lock and .Rprofile were created.
      4. Run: `renv::snapshot(type = "explicit")` to lock exact package versions.

      Report: renv status.

      If the user specified 'renv' as false: Skip renv.
      Report: skipped.
    output: renv_status

  - id: setup-modules
    requires: [scaffold]
    inline-prompt: |
      If the user specified 'modules' as true (value: {{params.modules}}):

      The framework is: {{params.framework}}.
      If framework is "golem": Golem already creates a module structure. Verify:

      1. Check `R/mod_*.R` files exist.
      2. Run `golem::add_module("main")` to create a main module if not present.
      3. Report existing modules.

      If framework is "minimal": Create a module structure for the minimal app:

      1. Create `R/mod_main.R`:
         ```r
         #' Main UI module
         #' @param id Module ID
         mod_main_ui <- function(id) {
           ns <- NS(id)
           tagList(
             # Module UI here
           )
         }

         #' Main server module
         #' @param id Module ID
         mod_main_server <- function(id) {
           moduleServer(id, function(input, output, session) {
             # Module logic here
           })
         }
         ```
      2. Create a template module file `R/mod_template.R` for future modules.
      3. Document the module structure in a comment at the top of each file.

      If the user specified 'modules' as false: Skip module setup.
      Report: skipped.
    output: module_status

  - id: setup-testing
    requires: [scaffold]
    inline-prompt: |
      Set up testing for the Shiny application:

      The framework is: {{params.framework}}.

      1. Ensure testthat edition 3 is configured.
         Run: `usethis::use_testthat(edition = 3)` if not already set up.
         Create `tests/testthat/setup.R` with:
         ```r
         library(testthat)
         local_reproducible_output(width = 80)
         ```
      2. If framework is "golem": Golem includes testthat.
         Run: `golem::use_recommended_tests()` to verify.
         Check that `tests/testthat/` exists with test-golem-recommended.R.
         If framework is "minimal": Create `tests/testthat.R` and
         `tests/testthat/` directory. Create `tests/testthat/test-server.R`
         with a basic testServer test.
      2. Add `shinytest2` support:
         - Create `tests/testthat/test-shinytest2.R` with a basic app test:
           ```r
           library(shinytest2)

           test_that("app loads and responds", {
             app <- AppDriver$new(test_path("../../"),
               variant = platform_variant(),
               screenshot_args = FALSE)
             app$wait_for_idle()
             app$expect_values()
           })
           ```
         - Use `shinytest2::AppDriver` to test the full app.
      3. Verify testing infrastructure exists.
      4. Report: test files created and testing setup status.

      If shinytest2 or testthat are not installed, note them as dependencies.
    output: test_status

  - id: create-readme
    requires: [scaffold]
    inline-prompt: |
      Create a README for the Shiny app:

      1. Create `README.md` with:
         - App name and one-line description
         - Screenshot placeholder
         - Requirements: R, required packages
         - How to run: `shiny::runApp()` or `golem::run_dev()`
         - Project structure overview
         - Deployment instructions placeholder
      2. Report: README created.
    output: readme_status

tags:
  - r
  - shiny
  - init
  - scaffold
  - web

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER use global variables for app state — use reactiveValues."
    severity: "error"
  - rule: "NEVER use source() inside reactive expressions."
    severity: "error"
  - rule: "ALWAYS validate user inputs server-side, not just client-side."
    severity: "warning"
  - rule: "Use Shiny modules for reusable UI components."
    severity: "warning"
  - rule: "Use logger package for structured logging, not print() or cat()."
    severity: "warning"
---

You are a Shiny application architect specializing in production-grade
application scaffolding following the Mastering Shiny and Engineering
Production-Grade Shiny Apps conventions.

## Rules

1. PREFER golem for production applications: it provides package structure,
   testing, and deployment tooling.
2. Use Shiny modules (`moduleServer()` + `NS()`) to organize complex apps.
3. ALWAYS set up testing (testthat + shinytest2) from the start.
4. Use `renv` for reproducible dependency management.
5. Keep `app.R` or `run_app.R` minimal: delegate logic to modules.
6. Use `bslib` for theming (Bootstrap 5) in new applications.
7. NEVER use `<<-` in Shiny reactive contexts.
8. PREFER `reactive()` + `observe()` over `reactiveValues()` for state.
9. Include `global.R` only when golem is not used.
10. All paths should use `here::here()` relative to the app root.
