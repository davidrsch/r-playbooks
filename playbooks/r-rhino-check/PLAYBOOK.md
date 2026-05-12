---
name: r-rhino-check
version: 1.0.0
context-mode: Fork
description: "Run rhino quality checks: lint, diagnostics, build, and tests — the universal quality gate for rhino projects"
trigger: both
trigger-patterns:
  - "rhino *"
  - "shiny *"
  - "rhino check *"
  - "check rhino *"
  - "rhino lint *"
  - "rhino diagnostics *"
  - "run rhino checks *"
argument-hint: "[--auto-fix true|false] [--coverage true|false]"
parameters:
  auto-fix:
    type: Boolean
    required: false
    default: true
    hint: "Automatically fix lint and styling issues"
  coverage:
    type: Boolean
    required: false
    default: true
    hint: "Also run test coverage analysis"
steps:
  - id: validate-rhino-project
    inline-prompt: |
      Verify this is a valid rhino project:

      1. Check for `.rhino.yml` in the project root.
         If not found, abort: "Not a rhino project. Use r-rhino-init to create one."
      2. Check rhino is installed: `packageVersion("rhino")`
         If not installed: `renv::install("rhino", repos = "https://appsilon.github.io/rhino/")`
      3. Read `.rhino.yml` to understand project configuration.
      4. Verify the expected directory structure exists:
         - `app/main.R`
         - `app/view/`
         - `app/logic/`
         - `app/styles/`
         - `tests/testthat/`
         - `tests/cypress/`
      5. Check that renv is active: `renv::status()`
      6. Report: rhino version, project structure, renv status.
    output: project-info

  - id: lint-r
    requires:
      - validate-rhino-project
    inline-prompt: |
      Lint R code in the rhino project:

      1. Run: `rhino::lint_r()`
         This checks all R files in `app/` and `tests/testthat/` for code quality issues.
      2. If lints are found and auto-fix is enabled:
         - Run: `styler::style_dir("app/")` to auto-fix style issues
         - Run: `rhino::format_r()` if available (rhino >= 1.5)
         - Re-run: `rhino::lint_r()` to verify fixes
      3. Report:
         - Number of lints found (by severity)
         - Files with violations
         - Fixed count (if auto-fix enabled)
      4. If lints persist after auto-fix, list them for manual resolution.

      Common rhino lint issues:
      - Use of `source()` instead of `box::use()`
      - Use of `library()` inside modules
      - Missing `@export` tags on module functions
      - `print()`/`cat()` instead of `logger::log_*()`
      - Global variable assignment (`<<-`)
    output: lint-results
    gate: Review

  - id: lint-js
    requires:
      - validate-rhino-project
    inline-prompt: |
      Lint JavaScript files in the rhino project (if any exist):

      1. Check if `app/js/` directory exists and has `.js` files.
      2. If no JS files exist, report: "No JavaScript files found — skipped."
      3. If JS files exist:
         - Check if ESLint is configured (`package.json` with eslint)
         - Run: `npx eslint app/js/` if available
         - If no ESLint config, suggest adding one: `npm init @eslint/config`
         - Report any JS lint issues found

      Rhino projects often have minimal JS; this step may be skipped.
    output: lint-js-results

  - id: rhino-diagnostics
    requires:
      - validate-rhino-project
    inline-prompt: |
      Run rhino diagnostics to check for common issues:

      1. Run: `rhino::diagnostics()`
         This checks:
         - Module naming conventions
         - Missing box imports
         - Unused dependencies
         - Configuration file issues
         - Duplicate function names across modules
         - Reactlog issues (missing reactive dependencies)
      2. Parse the output. Report:
         - Total diagnostics messages
         - Errors found (blocking issues)
         - Warnings found (potential issues)
         - Suggestions
      3. If errors are found, list each with the file and line number.
      4. Suggest fixes for common issues.

      Common diagnostics findings:
      - "Function X is not exported" → add `@export` tag
      - "Module Y has no box::use()" → add imports
      - "Duplicate function name Z" → rename one of the functions
    output: diagnostics-results
    gate: Review

  - id: build-sass
    requires:
      - lint-r
    inline-prompt: |
      Build Sass stylesheets to verify they compile:

      1. Run: `rhino::build_sass()`
         This compiles `.scss` files from `app/styles/` to `app/static/` (or `www/`).
      2. Verify compilation succeeded (no errors).
      3. Check the output CSS exists in `app/static/` or `www/`.
      4. If compilation fails, report the error and suggest fixes:
         - Check for syntax errors in `.scss` files
         - Verify Bootstrap is imported: `@import "bootstrap/scss/bootstrap";`
         - Check for missing variables or mixins
      5. Report: status, compiled files, CSS size.
    output: sass-results
    gate: Review

  - id: test-r
    requires:
      - rhino-diagnostics
      - build-sass
    inline-prompt: |
      Run R unit tests:

      1. Run: `rhino::test_r()`
         This runs all testthat tests in `tests/testthat/`.
      2. Parse results:
         - Total tests, passed, failed, skipped, warnings
         - For each failure: file, line, test name, error message
      3. If any tests fail, list them for manual review.
         DO NOT auto-modify test expectations — only style/infrastructure fixes.
      4. If auto-fix is enabled and failures are due to styling (e.g., trailing whitespace),
         run `styler::style_dir("tests/")` and re-test.
      5. Report: test results summary.
    output: test-r-results
    gate: Review

  - id: test-coverage
    requires:
      - test-r
    inline-prompt: |
      Run test coverage analysis (if coverage is enabled):

      If coverage is disabled, skip and report: "Coverage skipped."

      When coverage is enabled:
      1. Run: `covr::package_coverage(type = "all", path = "app/")`
         (Note: rhino projects aren't packages, so use path.)
      2. Alternatively, use: `rhino::test_r()` with coverage flag if available.
      3. Report:
         - Overall line coverage percentage
         - Files with < 80% coverage, listed by coverage %
         - Any files with 0% coverage (untested)
      4. If overall coverage < 50%, flag as CRITICAL.
      5. If overall coverage < 80%, flag as NEEDS IMPROVEMENT.
      6. If overall coverage >= 90%, flag as GOOD.

      Note: Coverage analysis in non-package projects is limited.
      Focus on `app/logic/` files — they should have high coverage.
    output: coverage-results

  - id: summary-report
    requires:
      - lint-r
      - lint-js
      - rhino-diagnostics
      - build-sass
      - test-r
      - test-coverage
    inline-prompt: |
      Produce a comprehensive quality report:

      ```
      🦏 Rhino Quality Gate Report
      ============================
      Project: <name from .rhino.yml>
      Rhino version: <version>

      ┌─────────────────────┬────────┬──────────────────────────────┐
      │ Check               │ Status │ Details                      │
      ├─────────────────────┼────────┼──────────────────────────────┤
      │ R Linting           │ ✅/⚠️  │ <n> lints, <n> fixed         │
      │ JS Linting          │ ✅/⚠️  │ <n> issues                   │
      │ Diagnostics         │ ✅/⚠️  │ <n> errors, <n> warnings     │
      │ Sass Build          │ ✅/❌  │ <status>                     │
      │ R Tests             │ ✅/❌  │ <n>/<n> passed               │
      │ Coverage            │ ✅/⚠️  │ <n>%                         │
      └─────────────────────┴────────┴──────────────────────────────┘

      Overall: ✅ PASS / ⚠️ WARNINGS / ❌ FAILURES
      ```

      If any check failed, list remediation steps.
      If all passed, celebrate: "🦏 All rhino checks passed!"
    gate: Approve
    output: quality-report

tags:
  - r
  - shiny
  - rhino
  - quality
  - lint
  - test

constraints:
  - rule: "NEVER modify test expectations during auto-fix."
    severity: "error"
  - rule: "NEVER use source() inside reactive expressions."
    severity: "error"
  - rule: "ALWAYS verify .rhino.yml exists before running checks."
    severity: "error"
  - rule: "Use logger package for structured logging, not print() or cat()."
    severity: "warning"

allowed-tools:
  - "*"
---

# R Rhino Check Playbook

You are an expert in rhino project quality assurance. Rhino is Appsilon's enterprise Shiny framework
that enforces production-grade conventions. This playbook runs the complete quality gate.

## Rhino Quality Commands

| Command                | What it checks                         |
| ---------------------- | -------------------------------------- |
| `rhino::lint_r()`      | R code style and anti-patterns         |
| `rhino::diagnostics()` | Module conventions, imports, structure |
| `rhino::test_r()`      | Unit tests with testthat               |
| `rhino::build_sass()`  | Sass → CSS compilation                 |

## Anti-patterns to Catch

- ❌ `source()`: use `box::use(./path/module)`
- ❌ `library()` inside modules: use `box::use(pkg[...])`
- ❌ Hardcoded configuration: use `config::get()`
- ❌ `print()`/`cat()` for debugging: use `logger::log_debug()`
- ❌ Global variables: use `reactiveValues()`
- ❌ Server-side input validation missing
- ❌ Duplicate function names across modules

## Project Structure (expected)

```
├── .rhino.yml
├── app/
│   ├── main.R
│   ├── view/          # UI modules
│   ├── logic/         # Server logic modules
│   └── styles/        # Sass (.scss)
├── tests/
│   ├── testthat/      # R unit tests
│   └── cypress/       # E2E tests
└── renv.lock
```
