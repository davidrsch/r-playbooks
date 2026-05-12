---
name: r-rhino-test
version: 1.0.0
context-mode: Fork
description: "Run rhino test suites — R unit tests, Cypress E2E tests (on by default), and snapshot reviews — with auto-fix for common test issues"
trigger: both
trigger-patterns:
  - "rhino *"
  - "test *"
  - "rhino test *"
  - "test rhino *"
  - "run rhino tests *"
  - "rhino unit tests *"
  - "rhino e2e *"
  - "run cypress *"
  - "cypress test *"
argument-hint: "[--e2e true|false] [--coverage true|false] [--auto-fix true|false]"
parameters:
  e2e:
    type: Boolean
    required: false
    default: true
    hint: "Also run Cypress E2E tests (requires Node.js)"
  coverage:
    type: Boolean
    required: false
    default: true
    hint: "Run test coverage analysis on R tests"
  auto-fix:
    type: Boolean
    required: false
    default: true
    hint: "Auto-fix snapshot tests and common test infrastructure issues"
steps:
  - id: validate-rhino-project
    inline-prompt: |
      Verify this is a valid rhino project:

      1. Check for `.rhino.yml` in the project root.
         If not found, abort: "Not a rhino project."
      2. Check rhino is installed: `packageVersion("rhino")`
      3. Verify `tests/testthat/` directory exists.
      4. List existing test files: `list.files("tests/testthat/", pattern = "\\.R$")`
      5. Report: rhino version, test file count, project name.
    output: project-info

  - id: pre-flight
    requires:
      - validate-rhino-project
    inline-prompt: |
      Run pre-flight checks before testing:

      1. Verify renv is active and dependencies are installed: `renv::status()`
      2. Check for uncommitted changes in test files:
         `git status --porcelain -- tests/`
      3. Build Sass before tests (tests may depend on CSS): `rhino::build_sass()`
      4. Verify `tests/testthat.R` entry point exists and is properly configured.
         It should contain:
         ```r
         library(testthat)
         library(rhino)
         test_check("rhino")
         ```
      5. Report: renv status, any uncommitted test changes, Sass build status.
    output: preflight

  - id: run-unit-tests
    requires:
      - pre-flight
    inline-prompt: |
      Run all R unit tests:

      1. Run: `rhino::test_r()`
         This runs all tests in `tests/testthat/`.
      2. Parse the testthat output. Report:
         - Number of test files run
         - Total tests, passed, failed, skipped, warnings
      3. For EACH failure, report:
         ```
         ❌ File: tests/testthat/test-<name>.R
            Test: "<test description>"
            Line: <line number>
            Error: <full error message>
         ```
      4. If auto-fix is enabled and failures are due to:
         - **Snapshot changes**: Review and run `testthat::snapshot_accept("tests/testthat/_snaps/<file>.md")`
           BUT only if the change looks intentional. Ask for confirmation first.
         - **Missing packages**: Add to DESCRIPTION or dependencies.R
         - **Styling**: Run `styler::style_dir("tests/")`
         DO NOT auto-modify test logic or assertions.
      5. Report: summary of all failures and auto-fixes applied.

      Rhino test conventions:
      - Tests use `box::use()` for module imports
      - Modules are tested with `testServer()` (Shiny) or directly (logic)
      - Snapshots use testthat 3e snapshot testing
      - Each `.R` file in `tests/testthat/` tests one module
    output: unit-test-results
    gate: Review

  - id: snapshot-review
    requires:
      - run-unit-tests
    inline-prompt: |
      Review testthat snapshot files for intentional changes:

      1. Check if any snapshot files were created/modified during testing:
         ```r
         list.files("tests/testthat/_snaps/", recursive = TRUE)
         ```
      2. If no snapshot changes, report: "No snapshot changes — skipped."
      3. If snapshot changes exist, for each changed snapshot:
         - Show a diff of the old vs new snapshot
         - Describe what changed (text, HTML, values)
         - Mark as "intentional" or "unexpected"
      4. For intentional changes:
         - Run `testthat::snapshot_accept("tests/testthat/_snaps/<file>.md")`
         to accept the new snapshots
      5. For unexpected changes:
         - Flag for manual review
         - Suggest reverting the changes with `testthat::snapshot_reject()`

      Verify with the user before accepting any snapshots.
    gate: Confirm
    output: snapshot-results

  - id: e2e-tests
    requires:
      - run-unit-tests
    inline-prompt: |
      Run Cypress E2E tests (when e2e is enabled):

      If e2e is disabled, skip and report: "E2E tests skipped."

      When e2e is enabled:
      1. Check prerequisites:
         - Node.js >= 16: `node --version`
         - Cypress installed: `npx cypress version`
         If Cypress not installed: `rhino::test_e2e()` initializes it.
      2. Start the Shiny app in background:
         - rhino >= 1.11: `rhino::devmode()` (unified dev server)
         - rhino < 1.11: `shiny::runApp("app", port = 3838)`
      3. Run Cypress tests: `npx cypress run`
         Or use: `rhino::test_e2e(interactive = FALSE)`
      4. Parse results. Report:
         - Total specs, passed, failed, skipped
         - For each failure: spec file, test name, error message
      5. If tests failed, DO NOT auto-modify. List failures for manual review.
      6. Stop the background Shiny app.

      Note: E2E tests require a running app. If the app fails to start,
      fix app issues before running E2E tests.
    output: e2e-results
    gate: Review

  - id: coverage
    requires:
      - run-unit-tests
    inline-prompt: |
      Run test coverage analysis (if coverage is enabled):

      If coverage is disabled, skip and report: "Coverage skipped."

      When coverage is enabled:
      1. Run: `covr::package_coverage(type = "all", path = "app/")`
         Since rhino projects aren't R packages, use `path = "app/"`.
      2. Report:
         - Overall line coverage percentage
         - Files with < 80% coverage, listed by coverage %
         - Any `app/logic/` files with 0% coverage (critical untested logic)
         - Top 5 least-covered files
      3. Flag:
         - CRITICAL: overall < 50%
         - NEEDS IMPROVEMENT: overall < 80%
         - GOOD: overall >= 90%
      4. Suggest specific areas needing more test coverage.

      Focus coverage improvement on:
      - `app/logic/`: Business logic (should be near 100%)
      - `app/view/`: UI modules (acceptable to be lower, test with testServer)
    output: coverage-results
    gate: Review

  - id: test-summary
    requires:
      - run-unit-tests
      - snapshot-review
      - e2e-tests
      - coverage
    inline-prompt: |
      Produce a comprehensive test report:

      ```
      🦏 Rhino Test Report
      ====================
      Project: <name>

      ┌────────────────────────┬────────┬────────────────────────────┐
      │ Suite                  │ Status │ Details                    │
      ├────────────────────────┼────────┼────────────────────────────┤
      │ R Unit Tests           │ ✅/❌  │ <n>/<n> passed             │
      │ Snapshots              │ ✅/⚠️  │ <n> changed                │
      │ E2E Tests (Cypress)    │ ✅/❌  │ <n>/<n> passed (skipped)   │
      │ Coverage               │ ✅/⚠️  │ <n>% overall               │
      └────────────────────────┴────────┴────────────────────────────┘

      Overall: ✅ ALL PASSING / ⚠️ WARNINGS / ❌ FAILURES
      ```

      If failures exist, list the top 3 priority fixes.
      If all pass, celebrate: "🦏 All rhino tests passing!"
    gate: Approve
    output: test-report

tags:
  - r
  - shiny
  - rhino
  - test
  - testthat
  - cypress

constraints:
  - rule: "NEVER modify test assertions during auto-fix."
    severity: "error"
  - rule: "ALWAYS ask for confirmation before accepting snapshots."
    severity: "error"
  - rule: "NEVER use source() inside test files."
    severity: "error"
  - rule: "ALWAYS stop background Shiny app after E2E tests."
    severity: "warning"

allowed-tools:
  - "*"
---

# R Rhino Test Playbook

You are a testing expert for rhino (Appsilon's enterprise Shiny framework) projects.
Rhino uses testthat for R unit tests and Cypress for E2E tests.

## Testing Architecture

```
tests/
├── testthat.R           # Entry point: test_check("rhino")
├── testthat/
│   ├── test-<module>.R  # Unit tests for each module
│   ├── _snaps/          # Snapshot files (auto-generated)
│   └── helper.R         # Test fixtures, mocks
└── cypress/
    ├── integration/     # E2E test specs
    ├── fixtures/        # Test data
    └── support/         # Cypress plugins
```

## Test Conventions

### Unit Test (testthat)

```r
box::use(
  testthat[...],
  app / logic / data_processing[process_data],
)

test_that("process_data handles empty input", {
  expect_equal(process_data(data.frame()), data.frame())
  expect_error(process_data(NULL), "Input must be a data.frame")
})

test_that("process_data computes correctly", {
  result <- process_data(data.frame(x = 1:3, y = 4:6))
  expect_equal(nrow(result), 3)
  expect_named(result, c("x", "y", "z"))
})
```

### Snapshot Testing

```r
test_that("UI snapshot matches", {
  expect_snapshot(mod_chart_ui("test"))
})
```

### Shiny Module Testing

```r
test_that("module server logic works", {
  shiny::testServer(mod_filter_server, args = list(data = reactive(mtcars)), {
    session$setInputs(cyl = 6)
    expect_equal(nrow(session$returned()), 7)
  })
})
```

## Key Commands

| Command                       | Purpose                          |
| ----------------------------- | -------------------------------- |
| `rhino::test_r()`             | Run all R unit tests             |
| `rhino::test_e2e()`           | Initialize/run Cypress E2E tests |
| `npx cypress run`             | Run Cypress headlessly           |
| `npx cypress open`            | Open Cypress interactive runner  |
| `testthat::snapshot_accept()` | Accept new snapshots             |
| `testthat::snapshot_reject()` | Reject snapshot changes          |
