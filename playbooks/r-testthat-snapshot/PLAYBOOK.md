---
name: r-testthat-snapshot
description: "Add snapshot tests to an R package with testthat edition 3: output, value, error, and file snapshots"
version: 1.0.0
context-mode: Fork
trigger: both
trigger-patterns:
  - "add snapshot tests *"
  - "snapshot test *"
  - "expect_snapshot *"
parameters:
  function_name:
    type: String
    required: true
    hint: "Function name to add snapshot tests for (e.g., 'my_function')"
  type:
    type: String
    required: false
    default: "output"
    enum: ["output", "value", "error", "all"]
    hint: "Snapshot type: output (console), value (return), error (error messages), or all"
tags:
  - r
  - testing
  - testthat
  - snapshot
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
allowed-tools:
  - "*"
steps:
  - id: analyze-function
    inline-prompt: |
      Analyze the function `{{params.function_name}}` to determine snapshot test candidates.

      Read the function source code and identify:
      1. What it prints to the console (messages, warnings, cat(), print())
      2. What it returns (data structure, dimensions, types)
      3. What errors it throws for invalid inputs
      4. What edge cases exist (empty input, NA, NULL, extreme values, boundary conditions)

      Use:
      ```r
      # View function source
      print({{params.function_name}})

      # Check documentation
      ?{{params.function_name}}

      # Find existing tests
      list.files("tests/testthat", pattern = "{{params.function_name}}", full.names = TRUE)
      ```

      Report the analysis: function signature, output types, error conditions, edge cases found.
    output: function-analysis
    gate: Review
  - id: write-snapshot-tests
    requires:
      - analyze-function
    inline-prompt: |
      Write snapshot tests in `tests/testthat/test-{{params.function_name}}-snapshot.R`.

      Use testthat edition 3 conventions (testthat >= 3.0.0).

      If `{{params.type}}` includes `output` or is `all`:
      ```r
      test_that("{{params.function_name}} prints expected output", {
        local_reproducible_output(width = 80)
        expect_snapshot({{params.function_name}}(test_input))
      })
      ```

      If `{{params.type}}` includes `error` or is `all`:
      ```r
      test_that("{{params.function_name}} errors on invalid input", {
        # Use transform to normalize error paths
        expect_snapshot(
          {{params.function_name}}(invalid_input),
          error = TRUE,
          cran = TRUE,
          transform = function(x) gsub(getwd(), "<wd>", x, fixed = TRUE)
        )
      })
      ```

      If `{{params.type}}` includes `value` or is `all`:
      ```r
      test_that("{{params.function_name}} returns expected value", {
        result <- {{params.function_name}}(test_input)
        expect_snapshot_value(result, style = "json2", tolerance = 1e-6)
      })
      ```

      For numeric return values, always set a tolerance to prevent floating-point
      differences across platforms from causing spurious failures:

      ```r
      expect_snapshot_value(result, style = "json2", tolerance = 1e-6)
      ```

      Typical tolerances:
      - `1e-6` for general numeric work
      - `1e-4` for optimization/convergence results
      - `1e-8` for high-precision computations

      Best practices for snapshot content:
      - Use `local_reproducible_output()` to control console width and encoding
      - Normalize variable content with `transform`: paths, timestamps, memory addresses
      - For errors: `transform = ~ gsub(getwd(), "<wd>", ., fixed = TRUE)`
      - For printed tibbles: limit rows with `dplyr::slice_head(n = 5)` before snapshotting
      - For plots: use `vdiffr::expect_doppelganger()` NOT `expect_snapshot()` on plot internals

      Include test cases for:
      1. Typical/representative input
      2. Empty input (if valid, e.g., empty vector, zero-row dataframe)
      3. Boundary values (min, max, 0, negative)
      4. NA handling (if function should handle NAs gracefully)
      5. Error messages for invalid input
    output: test-file
    gate: Review
  - id: run-and-accept-snapshots
    requires:
      - write-snapshot-tests
    inline-prompt: |
      Run the snapshot tests and review generated snapshots.

      ```r
      # Run the snapshot tests
      testthat::test_file("tests/testthat/test-{{params.function_name}}-snapshot.R")
      ```

      If tests pass on first run (existing snapshots): great, tests are verifying correctly.

      If tests create new snapshots (first run):
      ```r
      # Review each new snapshot
      testthat::snapshot_review()
      ```
      This opens an interactive diff viewer. For each snapshot:
      1. Read the captured output carefully
      2. Verify it matches expected behavior: correct values, format, error messages
      3. Confirm no PII, secrets, or environment-specific content leaked
      4. Accept ONLY if the output is correct:
         ```r
         testthat::snapshot_accept("test-name")
         ```

      NEVER blindly accept all snapshots. Each one must be reviewed.

      If tests fail (snapshot mismatch):
      1. Review the diff to understand what changed
      2. Is the change intentional? → `snapshot_accept()`
      3. Is the change a bug? → Fix the code, then re-run
      4. Is the change environment-specific? → Add `transform` to normalize

      Generated files:
      - `tests/testthat/_snaps/{{params.function_name}}-snapshot.md` (text snapshots)
      - `tests/testthat/_snaps/{{params.function_name}}-snapshot/` (value snapshots)
      Both should be committed to git.
    output: snapshot-results
  - id: add-shuffle-test
    requires:
      - run-and-accept-snapshots
    inline-prompt: |
      Add a shuffle test to ensure test isolation:
      ```r
      # In a separate test file or the CI script:
      testthat::test_dir("tests/testthat", shuffle = TRUE)
      ```

      Shuffle testing randomizes test execution order to find hidden dependencies between tests. If any test depends on another test running first, shuffle mode will reveal it.

      Add this to the project's CI script or Makefile as a `test-shuffle` target.

      Also verify existing tests aren't broken:
      ```r
      devtools::test()
      ```

      Report: all tests pass, snapshot files created, shuffle test result.
    output: verification-report
---

# R Snapshot Testing Playbook

You are an expert in R testthat snapshot testing. Use testthat edition 3 (testthat >= 3.0.0) for all new snapshot tests.

## Snapshot Test Types

### `expect_snapshot()`: Console Output

Captures what the function prints, messages, warns, or errors. Use `local_reproducible_output()` for consistency.

### `expect_snapshot_value()`: Return Values

Captures the return value. Use `style = "json2"` for data frames, `style = "serialize"` for complex objects.

### `expect_snapshot_file()`: File Output

For functions that generate files (plots, reports, data exports).

## Rules of Snapshot Testing

### What Snapshots ARE

- ✅ Human-readable verification of behavior
- ✅ Golden files that document expected output
- ✅ Regression detection: did behavior change?
- ✅ Committed to git for version history

### What Snapshots ARE NOT

- ❌ A replacement for unit tests: they complement, not replace
- ❌ Generated automatically without review
- ❌ To be blindly accepted on mismatch
- ❌ For testing implementation details

### When NOT to use snapshots

- ❌ **Random/unseeded output**: snapshot will change every run
- ❌ **Large data frames**: snapshots over 20 rows are unreadable; use `expect_equal()` instead
- ❌ **Timestamps that can't be fully normalized**: CI timezone differences cause flaky failures
- ❌ **External API responses**: mock the API, snapshot the mock
- ❌ **Performance-critical code paths**: snapshot serialization adds overhead
- ❌ **Functions where exact output format is NOT a contract**: snapshots freeze format; use `expect_equal()` for logic-only checks

**Rule of thumb**: If you wouldn't want a PR review comment every time the output changes by a single space, don't snapshot it.

### Normalization Rules

Always normalize environment-specific content:

- File paths → `gsub(getwd(), "<wd>", ., fixed = TRUE)`
- Timestamps → `gsub("\\d{4}-\\d{2}-\\d{2}", "<date>", .)`
- Memory addresses → `gsub("0x[0-9a-f]+", "<address>", .)`
- Unicode → `local_reproducible_output(unicode = FALSE)`

### Snapshot Lifecycle

1. Write test with `expect_snapshot()`
2. Run test → new snapshots created in `_snaps/`
3. Review in `snapshot_review()` interactive viewer
4. Accept if output is correct → `snapshot_accept()`
5. Commit snapshots to git
6. On subsequent runs: test compares to committed snapshots
7. If behavior changes intentionally → re-accept

### Graphics Testing

DON'T snapshot plot internals. Use `vdiffr::expect_doppelganger()` for visual comparison.

### CI Configuration for Snapshots

Snapshots are sensitive to locale, encoding, and R version. Configure CI to be deterministic:

```yaml
# In GitHub Actions
env:
  LANGUAGE: en
  LC_COLLATE: C
```

In your test setup file:

```r
options(
  testthat.snapshot_accept = FALSE,  # NEVER auto-accept on CI
  cli.unicode = FALSE,
  width = 80
)
```

NEVER set `testthat.snapshot_accept = TRUE` on CI: it silently overwrites snapshots.
