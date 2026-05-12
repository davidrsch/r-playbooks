---
name: r-box-module
version: 1.0.0
context-mode: Fork
description: "Create a module using the box package with explicit @export declarations, clean namespace isolation, and proper file structure. Core pattern in rhino, golem, and Shiny apps — distinct from Shiny modules (UI+server)"
trigger: both
trigger-patterns:
  - "box *"
  - "module *"
  - "box module *"
  - "create module *"
  - "add module *"
argument-hint: "--name <module_name> [--directory <R/>] [--functions <func1,func2>]"
parameters:
  name:
    type: String
    required: true
    hint: "Module name (file name without extension, e.g., utils, data_io)"
  directory:
    type: String
    required: false
    default: R
    hint: "Where to create the module (relative to project root)"
  functions:
    type: String
    required: false
    hint: "Comma-separated function names to scaffold (default: single placeholder)"
steps:
  - id: create-module
    inline-prompt: |
      Create a new box module at {{params.directory}}/{{params.name}}.r.

      Use the `box` package conventions:
      1. Use `box::use()` for imports (NOT `library()` or `source()`)
      2. Use `#' @export` roxygen tags for public functions
      3. Private functions should NOT have `@export`
      4. Use fully qualified names within the module

      Write module scaffolding with:
      - Module-level documentation header with `@description` and `@export`
      - `box::use()` imports at the top
      - One exported function per requested function name
      - Each function with roxygen docs (`@title`, `@description`, `@param`, `@return`, `@export`, `@examples`)
      - Input validation using `stopifnot()` or `rlang::abort()`
      - snake_case function names (Tidyverse convention)

      If the user did not specify functions, create a single placeholder exported function.

      Project root: {{env.CWD}}
    output: module-file
    gate: Review

  - id: create-test
    requires: [create-module]
    inline-prompt: |
      Create a test file at tests/testthat/test-{{params.name}}.r.

      Use testthat edition 3 conventions:
      1. `box::use()` to import the module under test
      2. Write one describe/it block per exported function
      3. Cover: happy path, edge cases, error conditions, empty/missing inputs
      4. Use `expect_snapshot()` for complex output
      5. Test that private functions are NOT accessible (encapsulation check)

      Test file structure:
      ```r
      box::use(../../{{params.directory}}/{{params.name}})

      describe("{{params.name}}", {
        it("should handle valid input", {
          result <- {{params.name}}$exported_function(valid_input)
          expect_s3_class(result, "data.frame")
        })

        it("should error on invalid input", {
          expect_error({{params.name}}$exported_function(NULL))
        })
      })
      ```

      Project root: {{env.CWD}}
    output: test-file
    gate: Review

  - id: verify-build
    requires: [create-test]
    inline-prompt: |
      Verify the module builds correctly:

      1. Source the module with `box::use(./{{params.directory}}/{{params.name}})`
      2. Confirm all exported functions are accessible
      3. Run the tests: `testthat::test_file("tests/testthat/test-{{params.name}}.r")`
      4. Run lintr on the module: `lintr::lint("{{params.directory}}/{{params.name}}.r")`

      Report: exported function count, test results, lint issues (if any).

      Project root: {{env.CWD}}
    output: verification-report

tags:
  - r
  - module
  - box
  - architecture

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER export internal implementation details."
    severity: "error"
  - rule: "ALWAYS use explicit imports with box::use()."
    severity: "warning"
  - rule: "Use S7 for formal class systems in new code."
    severity: "warning"
  - rule: "NEVER block the main thread with synchronous I/O."
    severity: "error"
---

You are an expert in modern R module architecture using the `box` package by
Konrad Rudolph. The `box` module system replaces `source()` and `library()` for
internal code organization, providing proper encapsulation, explicit exports,
and namespace isolation.

## Rules

1. ALWAYS use `box::use()` for imports inside modules: NEVER `source()` or `library()`.
2. Selectively import only needed functions: `box::use(dplyr[filter, mutate])`.
3. Use `#' @export` roxygen tags to declare public API; omit for private functions.
4. Private functions cannot be accessed from outside the module: enforce this in tests.
5. Each module has its own scope: no shared mutable state.
6. The module namespace is the basename of the `.r` file.
7. ALWAYS use snake_case for function and file names.
8. ALWAYS validate inputs at the top of each exported function.
9. PREFER `rlang::abort()` over `stop()` for error messages.
10. NEVER use `<<-` or `assign()` to leak state out of a module.

## Box Module File Structure

```r
#' Module title
#' @description Module description
#' @export
box::use(
  dplyr[filter, mutate, select],
  stringr[str_replace_all],
)

#' @title Function title
#' @description What it does
#' @param x Description
#' @return Description
#' @export
#' @examples
#' my_function(1:10)
my_function <- function(x) {
  stopifnot(is.numeric(x))
  # Use box::file() for relative paths to data files within the module
  # e.g., data_path <- box::file("data/input.csv")
  # implementation
}

# Private function (no @export)
helper <- function(x) {
  # internal
}

# Self-reference: box::name() returns the current module name
# Useful for logging or error messages
```

## box::reexport() Pattern

To re-export functions from another module or package:

```r
#' @export
box::use(
  ./R/utils[clean_data, validate_input],
  dplyr[filter],
)

# Re-export for consumers
#' @export
box::reexport(./R/utils, dplyr[filter])
```

## Anti-patterns to NEVER use

- ❌ `source("R/utils.R")`: use `box::use(./R/utils)`
- ❌ `library(tidyverse)` inside a module: use `box::use(dplyr[...], ggplot2[...])`
- ❌ Assigning to global environment with `<<-` or `assign()`
- ❌ `attach()`: never use
