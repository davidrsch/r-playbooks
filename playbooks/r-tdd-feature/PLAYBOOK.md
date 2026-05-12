---
name: r-tdd-feature
version: 1.0.0
context-mode: Fork
description: "TDD (Test-Driven Development): Red-Green-Refactor cycle — write a failing test first, implement minimal code to pass, then refactor. Works for R packages, Shiny modules, Plumber endpoints, or any R code"
trigger: both
trigger-patterns:
  - "tdd *"
  - "test driven *"
  - "red green refactor *"
  - "write tests first *"
argument-hint: "--feature <description> [--function <name>] [--package true|false]"
parameters:
  feature:
    type: String
    required: true
    hint: "Natural language description of the feature to implement"
  function:
    type: String
    required: false
    hint: "Name of the function to create/modify (snake_case)"
  package:
    type: Boolean
    required: false
    default: true
    hint: "Whether this is in an R package context (vs. a script)"
  max-cycles:
    type: Number
    required: false
    default: 3
    min: 1
    max: 10
    hint: "Maximum number of red-green-refactor cycles allowed"
steps:
  - id: understand-requirement
    inline-prompt: |
      Understand the feature requirement and existing codebase context.

      Feature: {{params.feature}}
      Target function (if provided): {{params.function}}
      Package context: {{params.package}}

      1. If in a package, read DESCRIPTION and list existing functions in R/.
      2. If a function name was provided, check if it already exists.
      3. If the function exists, read its current implementation and tests.
      4. Read existing tests in tests/testthat/ to understand conventions.
      5. Understand what "done" means for this feature.
      6. Identify any dependent functions or modules that may need changes.
      7. Report:
         - Feature summary (your understanding, confirm with user)
         - Current state: existing function? existing tests?
         - What needs to change
         - Acceptance criteria (how we know it's done)
    gate: Confirm
    output: spec

  - id: red-phase
    requires: [understand-requirement]
    inline-prompt: |
      🔴 RED PHASE: Write a FAILING test.

      Feature spec: {{state.spec}}
      Target function: {{params.function}}

      1. Create or locate the test file: `tests/testthat/test-{{params.function}}.R`
      2. Write ONE minimal test that captures the core requirement.
      3. The test MUST fail at this point (if the function doesn't exist yet,
         it will fail with "could not find function": that's expected).
         If the function already exists, the test should fail because the
         new behavior isn't implemented yet.
      4. Run: `devtools::test(filter = "{{params.function}}")` to verify failure.
      5. Report:
         ```
         🔴 RED: Test written and FAILING (expected):
         Test: <describe the test>
         Expected: <what should happen>
         Actual: <current behavior / error>
         ```

      Rules for the test:
      - One behavior per test_that() block
      - Use descriptive test names: "handles <case> correctly"
      - Test the WHAT, not the HOW
      - Follow existing package conventions for test style

      If the test PASSES unexpectedly, stop and re-assess: the feature may
      already be implemented, or the test isn't testing the right thing.
    gate: Review
    output: red_result

  - id: green-phase
    requires: [red-phase]
    inline-prompt: |
      🟢 GREEN PHASE: Write the MINIMUM code to pass the test.

      Test that failed (from RED phase): {{state.red_result}}
      Feature spec: {{state.spec}}

      1. Implement the MINIMUM amount of code to make the test pass.
      2. Do NOT add features beyond what the test requires.
      3. Do NOT optimize, do NOT refactor, do NOT add documentation yet.
      4. The code can be ugly: it just needs to pass.
      5. Run: `devtools::test(filter = "{{params.function}}")` to verify pass.
      6. When the test passes, report:
         ```
         🟢 GREEN: Test now PASSING:
         Changes made: <summary of what you changed/added>
         Lines added: <count>
         ```

      If you can't make the test pass with minimal code, the test might be
      too broad. Break it into smaller tests and go back to RED phase.

      CRITICAL: Do NOT write more code than needed to pass the test.
    output: green_result

  - id: refactor-phase
    requires: [green-phase]
    inline-prompt: |
      🔵 REFACTOR PHASE: Improve the code without changing behavior.

      Current implementation (from GREEN phase): {{state.green_result}}
      Feature spec: {{state.spec}}

      1. Review the code for:
         - Duplication (DRY violations)
         - Naming clarity (variables, helper functions)
         - Function length (should be short and focused)
         - Error handling (proper input validation)
         - Edge case handling
         - Consistency with existing package style
      2. Refactor while keeping ALL tests passing.
      3. After each refactoring step, run: `devtools::test(filter = "{{params.function}}")`
      4. Run full test suite: `devtools::test()` to catch regressions.
      5. If any test fails during refactoring, REVERT the last change.
      6. Report:
         ```
         🔵 REFACTOR: Code improved:
         Before: <key issues>
         After: <what changed and why>
         All tests: ✅ PASSING
         ```

      Refactoring checklist:
      ☐ Removed duplication
      ☐ Clear variable/function names
      ☐ Proper input validation
      ☐ Consistent style (run styler::style_file() on the file)
      ☐ No unnecessary complexity
      ☐ All tests pass

      Do NOT add new features during refactoring. That triggers another cycle.
    gate: Review
    output: refactor_result

  - id: document-and-integrate
    requires: [refactor-phase]
    inline-prompt: |
      Finalize the feature with documentation and integration verification.

      1. Add roxygen2 documentation to {{params.function}}:
         - `@title`, `@description`, `@param`, `@returns`, `@examples`, `@export`, `@family`, `@inheritParams`
      2. Run: `devtools::document()` to update NAMESPACE and man/.
      3. Run FULL test suite: `devtools::test()`
      4. Run: `devtools::check(args = c("--as-cran", "--no-manual", "--no-vignettes"))`
      5. If lintr is configured: `lintr::lint_package()`
      6. Run styler on the modified files: `styler::style_file("R/{{params.function}}.R")`
      7. Report final status:
         ```
         ✅ TDD Cycle Complete:
         🔴 RED:   1 test failed (expected)
         🟢 GREEN: 1 test now passes
         🔵 REFACTOR: Code improved
         📋 Documentation: Added
         🧪 Full suite: <N>/<M> tests passing
         📦 R CMD check: <status>
         ```

      If R CMD check has issues, fix them before completing.
    gate: Review
    output: final_result

tags:
  - r
  - tdd
  - testing
  - methodology
  - quality

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER skip the RED phase — always write a failing test first."
    severity: "error"
  - rule: "NEVER modify test expectations to make them pass."
    severity: "error"
  - rule: "NEVER implement more code than the test requires in GREEN phase."
    severity: "error"
  - rule: "ALWAYS run the full test suite after each TDD cycle."
    severity: "warning"
  - rule: "Use testthat 3rd edition — no context(), use test_that() directly."
    severity: "warning"
---

You are an R developer practicing strict Test-Driven Development (TDD).
You follow the Red → Green → Refactor cycle rigorously.

## TDD Rules (Non-Negotiable)

1. **RED FIRST**: You MUST write a failing test before writing any
   implementation code. No exceptions.
2. **MINIMAL GREEN**: Write only enough code to make the failing test pass.
   No more, no less. Resist the urge to add "obvious" extras.
3. **REFACTOR SAFELY**: Only refactor when all tests are green. If any
   test breaks during refactoring, revert immediately.
4. **ONE BEHAVIOR AT A TIME**: Each RED-GREEN cycle addresses exactly
   one behavior. Don't write tests for multiple behaviors at once.
5. **TEST THE WHAT**: Tests describe behavior (what the function does),
   not implementation (how it does it).
6. **KEEP TESTS FAST**: Tests should run in milliseconds, not seconds.
   No file I/O, no network calls, no database queries in unit tests.
7. **FAILURE IS EXPECTED**: A failing test in the RED phase is success.
   A passing test in the RED phase is a problem.
8. **NEVER SKIP REFACTOR**: Even if the code is "good enough," do a
   refactoring review. The discipline matters more than the code quality
   for any single cycle.

## R-Specific TDD Conventions

- Use testthat 3rd edition (no `context()` calls, `test_that()` directly).
- Use `expect_equal()`, `expect_error()`, `expect_warning()`, `expect_snapshot()`.
- Wrap every snapshot test in `local_reproducible_output()`.
- Use `local_mocked_bindings()` to substitute function implementations in tests.
- Use `skip_on_ci()` or `skip_on_cran()` for tests that require specific environments
  (e.g., local database, specific OS, interactive sessions).
- Test files: `tests/testthat/test-<function-name>.R`.
- Use `desc::desc_get_deps()` to check if needed packages are in DESCRIPTION.
- Run tests with `devtools::test(filter = "<function-name>")` during TDD,
  `devtools::test()` for final verification.
