---
name: r-rhino-init
version: 1.0.0
context-mode: Fork
description: Initialize an enterprise Shiny application with Appsilon's rhino framework
trigger: manual
argument-hint: "--name <app_name> [--directory <path>]"
parameters:
  name:
    type: String
    required: true
    hint: "Application name in snake_case, e.g., 'sales_dashboard' or 'patient_registry'"
  directory:
    type: String
    required: false
    default: "."
    hint: "Directory to create the project in (defaults to current)"
steps:
  - id: validate-prerequisites
    inline-prompt: |
      Verify that prerequisites are met for rhino initialization:

      1. Check R is installed: `R --version`
      2. Check Node.js is installed (required for Sass/JS): `node --version` (>= 16)
      3. Install rhino if not present: `renv::install("rhino", repos = "https://appsilon.github.io/rhino/")`
      4. Verify rhino version: `packageVersion("rhino")`
      5. Check that the target directory exists or can be created

      Report: R version, Node version, rhino version, target directory.
    output: prerequisites
  - id: scaffold-rhino
    inline-prompt: |
      Initialize the rhino project at {{params.directory}}/{{params.name}}:

      ```r
      rhino::init("{{params.name}}")
      ```

      This creates the full enterprise Shiny structure:
      ```
      {{params.name}}/
      ├── app/
      │   ├── main.R          # Entry point
      │   ├── view/           # UI modules (box::use() pattern)
      │   ├── logic/          # Server logic modules
      │   └── styles/         # Sass (.scss) stylesheets
      ├── tests/
      │   ├── testthat/       # Unit tests with testthat
      │   └── cypress/        # E2E tests with Cypress
      ├── .rhino.yml           # Rhino configuration
      ├── .Renviron            # Environment variables
      ├── config.yml           # Environment config (default/dev/prod)
      ├── dependencies.R      # R package dependencies (renv)
      ├── renv.lock           # Locked package versions
      └── Dockerfile          # Production Docker image (uses non-root USER and HEALTHCHECK)
      ```

      Key files created:
      - `app/main.R`: App entry point using `box::use()` for module imports
      - `app/view/`: UI modules with `box::use(shiny[...], bslib[...])`
      - `app/logic/`: Server logic modules with `box::use(stats[...], dplyr[...])`
      - `app/styles/main.scss`: Sass stylesheet entry point
      - `tests/cypress/`: Cypress E2E test specs

      Verify the scaffold completed successfully and all directories exist.
    requires:
      - validate-prerequisites
    output: project-structure
    gate: Review
  - id: configure-renv
    inline-prompt: |
      Set up dependency management with renv:

      1. Activate renv: `renv::activate()`
      2. Install dependencies from dependencies.R: `renv::install()`
      3. Take initial snapshot: `renv::snapshot(type = "explicit")`
      4. Verify status: `renv::status()`

      The `dependencies.R` file includes:
      ```r
      library(shiny)
      library(bslib)
      library(ggplot2)
      library(dplyr)
      library(logger)
      library(config)
      library(box)
      library(shinytest2)
      library(testthat)
      ```

      Confirm renv.lock was created and all packages resolved.
    requires:
      - scaffold-rhino
    output: renv-status
    gate: Review
  - id: configure-ci
    inline-prompt: |
      Set up CI/CD for the rhino project:

      1. Create `.github/workflows/rhino-ci.yml`:

      The workflow should include:
      - **R CMD check** (or equivalent for Shiny app): linting with lintr
      - **Unit tests**: `rhino::test_r()` which runs testthat tests
      - **E2E tests**: `rhino::test_e2e()` which runs Cypress tests
      - **Build check**: `rhino::build_sass()` to verify Sass compiles

      ```yaml
      name: rhino-ci
      on:
        push:
          branches: [main, master]
        pull_request:
          branches: [main, master]
      jobs:
        test:
          runs-on: ubuntu-latest
          steps:
            - uses: actions/checkout@v4
            - uses: r-lib/actions/setup-r@v2
            - uses: r-lib/actions/setup-renv@v2
              env:
                RENV_CONFIG_CACHE_ENABLED: false
            - uses: actions/setup-node@v4
              with:
                node-version: '18'
            - name: Run R tests
              run: Rscript -e 'rhino::test_r()'
            - name: Run E2E tests
              run: npx cypress run
            - name: Upload Cypress artifacts (on failure)
              if: failure()
              uses: actions/upload-artifact@v4
              with:
                name: cypress-screenshots
                path: tests/cypress/screenshots/
      ```

      2. Add `.github/workflows/deploy.yml` (placeholder for Connect deployment).

      3. Verify `.gitignore` contains critical entries:
         - `.Renviron` (MUST be gitignored: contains secrets)
         - `renv/library/` (managed by renv)
         - `node_modules/` (managed by npm)
         - `www/` (Sass output, if generated)
         - `.Rproj.user/` (IDE-specific)

      Report: CI files created, workflow configured, .gitignore verified.
    requires:
      - configure-renv
    output: ci-files
    gate: Review
  - id: verify-rhino
    inline-prompt: |
      Verify the rhino project is ready for development:

      1. Lint the code: `rhino::lint_r()`
      2. Build Sass: `rhino::build_sass()`
      3. Run rhino diagnostics: `rhino::diagnostics()`
      4. Format code: `styler::style_pkg()` or `rhino::format_r()`
      5. Run R unit tests: `rhino::test_r()`
      5. Run the app locally to verify it starts:
         - rhino >= 1.11: `rhino::devmode()` (unified dev server)
         - rhino < 1.11: `shiny::runApp("app")`

      Check the app loads at http://127.0.0.1:PORT and shows the default rhino page.

      Report: lint results, Sass build status, format applied, test results, app running.
    requires:
      - configure-ci
    output: verification-report
tags:
  - r
  - shiny
  - rhino
  - enterprise
  - init
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
allowed-tools:
  - "*"
---

# R Rhino Init Playbook

You are an expert in enterprise Shiny application architecture using Appsilon's rhino framework. Rhino enforces production-grade conventions: box modules, structured logging, environment config, Cypress E2E, Sass styling.

## Rhino Architecture

### Three Pillars

1. **Clear Code**: box::use() modules, Shiny modules, separation of view/logic
2. **Quality**: Unit tests (testthat), E2E tests (Cypress), linting, logging
3. **Automation**: rhino CLI, CI/CD templates, dependency management

### Directory Convention

```
app/main.R       → Entry point, calls modules from view/ and logic/
app/view/        → UI modules (one file per feature)
app/logic/       → Server logic modules (business logic, data processing)
app/styles/      → Sass (.scss) styles, compiled to www/
tests/testthat/  → R unit tests
tests/cypress/   → Cypress E2E specs
```

### Module Convention (box::use() pattern)

```r
# app/view/feature.R
box::use(
  shiny[moduleServer, NS, tagList, div, h2, textOutput, renderText],
  bslib[card, card_header, card_body],
  logger[log_info, log_debug],
)

#' @export
ui <- function(id) {
  ns <- NS(id)
  card(
    card_header(h2("Feature Title")),
    card_body(textOutput(ns("result")))
  )
}

#' @export
server <- function(id, data) {
  moduleServer(id, function(input, output, session) {
    log_info("Feature module loaded", module = "feature")
    output$result <- renderText({
      paste("Processing", nrow(data()), "rows")
    })
  })
}
```

### Anti-patterns

- ❌ `source()`: use `box::use(./path/module)`
- ❌ `library()` inside modules: use `box::use(pkg[...])`
- ❌ Hardcoded configuration: use `config::get()`
- ❌ `print()`/`cat()` for debugging: use `logger::log_debug()`
