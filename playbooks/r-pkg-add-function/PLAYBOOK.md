---
name: r-pkg-add-function
version: 1.0.0
context-mode: Fork
description: "Add a new exported function to an R package with roxygen2 documentation, testthat tests, and NAMESPACE export — follows TDD workflow"
trigger: both
trigger-patterns:
  - "function *"
  - "add function *"
  - "add a function *"
  - "create function *"
  - "new function *"
  - "new function *"
argument-hint: "--name <function_name> [--file <R/filename.R>] [--export true|false] [--tdd true|false]"
parameters:
  name:
    type: String
    required: true
    hint: "Function name (snake_case, e.g., calculate_mean)"
  file:
    type: String
    required: false
    hint: "R source file to add the function to (default: R/<name>.R)"
  export:
    type: Boolean
    required: false
    default: true
    hint: "Whether to @export the function for public use"
  tdd:
    type: Boolean
    required: false
    default: true
    hint: "Use TDD approach: write tests first, then implement"
  description:
    type: String
    required: false
    hint: "Natural language description of what the function should do"
steps:
  - id: analyze-context
    inline-prompt: |
      Analyze the current package context to prepare for adding `{{params.name}}`:

      1. Read the DESCRIPTION file to understand the package purpose and existing dependencies.
      2. List the contents of `R/` to see existing function files.
      3. List the contents of `tests/testthat/` to see existing tests.
      4. If a file path {{params.file}} was specified, check if it exists.
      5. Run `devtools::load_all()` to ensure the package loads.
      6. Check for name conflicts:
         - Does `{{params.name}}` conflict with base R functions?
         - Does it conflict with recommended packages (stats, utils, graphics)?
         - Does it conflict with functions in the package's own NAMESPACE?
         - Search R/ for any private helper with the same name.
      7. Report: package purpose, existing related functions (if any), test patterns used,
         any name conflicts found.

      Package: {{env.CWD}}
    output: context

  - id: design-interface
    requires: [analyze-context]
    inline-prompt: |
      Design the function interface for `{{params.name}}`.

      Based on: {{state.context}}

      Description provided: {{params.description}}

      Design and report:
      1. Function signature: `{{params.name}}(<args>)`: parameter names, types, defaults
      2. Return value: what it returns (type, structure)
      3. Side effects: any (files written, plots, messages, etc.)
      4. Error conditions: what inputs should cause errors
      5. Edge cases: NA, NULL, empty, zero-length inputs
      6. Dependencies: which packages it will use (check against DESCRIPTION)

      Follow tidyverse design principles:
      - One function, one responsibility
      - Consistent naming with existing package functions
      - Use rlang for error handling if the package already uses it
      - Vectorize where appropriate (respect recycling rules)

      Report the design as structured text.
    gate: Confirm
    output: design

  - id: write-tests
    requires: [design-interface]
    inline-prompt: |
      Write testthat tests for `{{params.name}}` following the design:

      {{state.design}}

      Create or use file: `tests/testthat/test-{{params.name}}.R`

      Write comprehensive tests covering:
      1. **Happy path**: expected inputs produce expected outputs
      2. **Edge cases**: empty, NA, NULL, zero-length, boundary values
      3. **Error conditions**: invalid inputs that should throw errors
      4. **Type stability**: outputs maintain expected types
      5. **Snapshot tests**: use `expect_snapshot()` for error messages and formatted
         output to catch unintended changes:
         ```r
         test_that("error messages are stable", {
           expect_snapshot({{params.name}}("bad_input"), error = TRUE)
         })
         test_that("output format is stable", {
           expect_snapshot({{params.name}}(c(1, 2, 3)))
         })
         ```

      Use testthat 3rd edition conventions:
      ```r
      test_that("descriptive name", {
        expect_equal({{params.name}}(c(1, 2, 3)), <expected>)
      })
      ```

      After writing, run: `devtools::test(filter = "{{params.name}}")` 
      Tests SHOULD FAIL at this point if TDD mode is on: that's expected (Red phase).

      Report: number of tests written, which pass/fail.
    gate: Review
    output: test_results

  - id: implement-function
    requires: [write-tests]
    inline-prompt: |
      Implement the function `{{params.name}}` based on the design and tests.

      Design: {{state.design}}
      Test file: `tests/testthat/test-{{params.name}}.R`

      Target file: {{params.file}} or `R/{{params.name}}.R`

      Implementation checklist:
      1. Use `roxygen2` documentation above the function:
         - `#' @title`: one-line description
         - `#' @description`: detailed description
         - `#' @param <name>`: for each parameter
         - `#' @returns`: what it returns
         - `#' @family`: related functions group (e.g., "data-transform", "plotting")
         - `#' @examples`: working examples
         - `#' @examplesIf`: conditional examples (e.g., `@examplesIf interactive()`)
         - `#' @export`: if {{params.export}}
      2. Use input validation at the top of the function
      3. Follow existing package conventions for error handling
      4. Handle edge cases from the design

      After writing, run: `devtools::test(filter = "{{params.name}}")`
      All tests should PASS (Green phase).

      Then run: `devtools::document()` to update NAMESPACE and man/ files.

      Report: function implementation summary, test results (all passing?), files modified.
    gate: Approve
    output: implementation

  - id: verify-integration
    requires: [implement-function]
    inline-prompt: |
      Verify the new function integrates correctly:

      1. Run: `devtools::load_all()`
      2. Run: `devtools::test()`: all tests, not just the new ones
      3. Run: `devtools::check(args = c("--no-manual", "--no-vignettes"))`: quick check
      4. Verify NAMESPACE was updated correctly by roxygen2
      5. If {{params.export}} is true, confirm the function appears in NAMESPACE exports
      6. Check for any NOTE/WARNING/ERROR from R CMD check
      7. Verify all `@param` tags match function signature: no missing or extra params
      8. Verify `@examples` are self-contained and run without error:
         run the examples manually or via `devtools::run_examples()`
      9. If lintr is configured, run: `lintr::lint_package()` and fix any issues

      Report: integration check results, any issues found.
    gate: Review
    output: verification

tags:
  - r
  - package
  - function
  - tdd

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER modify NAMESPACE manually — roxygen2 manages it."
    severity: "error"
  - rule: "NEVER commit to main without passing R CMD check."
    severity: "error"
  - rule: "ALWAYS run devtools::document() after changing roxygen comments."
    severity: "warning"
  - rule: "NEVER use install.packages() in scripts — use renv or DESCRIPTION."
    severity: "error"
  - rule: "ALWAYS run devtools::test() before committing."
    severity: "warning"
  - rule: "Use rlang::abort() or cli::cli_abort() over stop() for errors."
    severity: "warning"
---

You are an R package developer specializing in clean, well-tested, well-documented
function design following tidyverse conventions.

## Rules

1. ALWAYS use snake_case for function and file names.
2. ALWAYS validate inputs at the top of each function.
3. PREFER `rlang::abort()` or `cli::cli_abort()` over `stop()` for error messages.
   `cli::cli_abort()` supports rich formatting: `cli::cli_abort("Bad value {.val {x}}")`.
4. PREFER `cli::cli_alert_info()` for informational messages.
5. NEVER use `return()` explicitly at the end of a function: R returns the
   last expression by default. Only use `return()` for early exits.
6. ALWAYS run `devtools::document()` after modifying roxygen comments.
7. Follow the R Packages book style: https://r-pkgs.org
8. If the package uses `%>%` or `|>`, use the native pipe `|>` for R >= 4.1.
9. Write examples that are self-contained and don't require internet access.
10. When in TDD mode, tests MUST be written before implementation.
11. Every exported function must have `@examples`.
12. Every parameter must have a `@param` tag.
13. Internal helpers (not exported) should use `#' @noRd` to skip .Rd generation.
    Exported functions MUST generate .Rd documentation.
14. Use `@family` to group related functions (e.g., `@family data-transform`).
    This adds "See also" links in .Rd files.

## TDD Mode vs Full TDD Workflow

When `tdd: true`, this playbook follows a single-cycle TDD pattern suitable for
straightforward functions. For complex features requiring multiple red-green-refactor
cycles, strict refactoring review, or non-package contexts (Shiny modules, Plumber
endpoints, standalone scripts), use the dedicated TDD playbook instead:

`/run_playbook r-tdd-feature --feature "<description>" --function "{{params.name}}" --max-cycles 3`

This playbook adds value beyond r-tdd-feature by handling:
- Name conflict checking against base R and existing NAMESPACE
- Interface design before test writing (design the signature first)
- Package-specific verification (@param matching, NAMESPACE exports)
- Non-TDD mode for trivial utility functions

Use r-pkg-add-function when you want quick, well-integrated package functions.
Use r-tdd-feature when you want rigorous TDD discipline across multiple cycles.
