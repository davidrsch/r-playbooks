---
name: r-refactor
version: 1.0.0
context-mode: Fork
description: "Safe refactoring of R code: capture current behavior with tests as a safety net, then restructure the code (extract functions, rename, reorganize) and verify nothing broke"
trigger: both
trigger-patterns:
  - "refactor *"
  - "clean up *"
  - "restructure *"
  - "reorganize *"
argument-hint: "--target <function|file> [--reason <text>] [--snapshot true|false]"
parameters:
  target:
    type: String
    required: true
    hint: "Function name or file path to refactor"
  reason:
    type: String
    required: false
    hint: "Why the refactor is needed (DRY, readability, performance, etc.)"
  snapshot:
    type: Boolean
    required: false
    default: true
    hint: "Use snapshot tests to lock in current behavior before refactoring"
steps:
  - id: capture-state
    inline-prompt: |
      Capture the current state before refactoring.

      Target: {{params.target}}

      1. If target is a function name:
         - Read the source file containing the function.
         - List all callers: `grep -r "{{params.target}}(" R/ tests/`
         - Run existing tests: `devtools::test()`
      2. If target is a file path:
         - Read the file.
         - List all files that `source()` or depend on it.
      3. Create a git checkpoint:
         - `git stash` or note the current HEAD.
      4. Snapshot the renv state: `renv::snapshot(type = "explicit")` to lock package versions
         before refactoring.
      5. Report:
         - Current state summary
         - All callers/dependents
         - Test status (all passing?)
         - Git checkpoint: commit hash or stash reference
    output: pre_state

  - id: add-snapshot-tests
    requires: [capture-state]
    inline-prompt: |
      If the user specified 'snapshot' as true (value: {{params.snapshot}}):
      Add snapshot tests to lock in current behavior.

      1. Create or update `tests/testthat/test-snapshot-{{params.target}}.R`:
         ```r
         test_that("snapshot of {{params.target}} behavior", {
           local_reproducible_output()
           # Test with representative inputs
           expect_snapshot({{params.target}}(<input1>))
           expect_snapshot({{params.target}}(<input2>))
           expect_snapshot({{params.target}}(<edge_case_input>))
         })

         test_that("snapshot of {{params.target}} output structure", {
           local_reproducible_output()
           expect_snapshot(str({{params.target}}(<input>)))
         })
         ```
      2. Run: `devtools::test(filter = "snapshot-{{params.target}}")`
      3. Review and accept snapshots: `testthat::snapshot_accept()`
      4. The snapshots now record EXACTLY what the function outputs.
         During refactoring, if the output changes, the snapshot test will fail.

      **Snapshot formatting guidance:**
      - For numeric output with floating-point variance, use `tolerance`:
        `expect_snapshot(x, tolerance = 1e-4)`
      - For data frame snapshots, prefer `style = "json2"` for diff-friendly output:
        `expect_snapshot(df, style = "json2")`

      Report: snapshot tests added, N snapshots recorded.

      If the user specified 'snapshot' as false: Skip snapshot tests.
      Report: relying on existing tests only.
    output: snapshot_status

  - id: plan-refactor
    requires: [add-snapshot-tests]
    inline-prompt: |
      Plan the refactoring changes.

      Target: {{params.target}}
      Reason: {{params.reason}}
      Current state: {{state.pre_state}}

      Plan the refactoring by identifying:
      1. **Code smells** to address:
         - Long functions (> 50 lines)
         - Duplicated code
         - Deep nesting (> 3 levels)
         - Too many parameters (> 5)
         - Mixed levels of abstraction
         - Magic numbers/strings
      2. **Refactoring techniques** to apply:
         - Extract function (break into smaller functions)
         - Rename variable/function
         - Simplify conditional
         - Remove dead code
         - Introduce parameter object
         - Replace loop with vectorized operation
      3. **Order of operations**: what to do first, second, etc.
      4. **Risk assessment**: which changes are low-risk vs. high-risk

      Report the refactoring plan with estimated impact.
    gate: Confirm
    output: refactor_plan

  - id: execute-refactor
    requires: [plan-refactor]
    inline-prompt: |
      Execute the refactoring plan step by step.

      Plan: {{state.refactor_plan}}

      For EACH refactoring step:
      1. Make the change
      2. Run tests: `devtools::test()` (or targeted tests)
      3. If any test fails:
         - If it's a snapshot test: the behavior changed: REVERT and reconsider
         - If it's a regular test: fix the refactored code, not the test
         - If you can't fix within 1 minute, REVERT the last change
      4. If all tests pass, move to the next step.

      Report progress after each step:
      ```
      ✅ Step 1: <description>: Tests: PASS
      ✅ Step 2: <description>: Tests: PASS
      ...
      ```

      After all steps:
      - Run: `devtools::document()` if any roxygen comments changed
      - Run: `devtools::test()`: full suite
      - Run: `lintr::lint_package()` to check style didn't regress

      If at any point you're unsure, STOP and ask for guidance.
    gate: Review
    output: refactor_results

  - id: verify-refactor
    requires: [execute-refactor]
    inline-prompt: |
      Verify the refactoring is complete and correct.

      1. Review the diff: `git diff` (if available)
      2. Confirm:
         ✅ All tests pass (including snapshot tests)
         ✅ No behavior changes (snapshot tests confirm this)
         ✅ Code is simpler / more readable
         ✅ No new lints introduced
         ✅ R CMD check passes
      3. If snapshot tests were used:
         - The snapshots confirm zero behavior change
         - If the refactor intentionally changed behavior (e.g., bug fix),
           update the snapshots: `testthat::snapshot_accept()`
         - Document why behavior changed
      4. Report:
         ```
         🔵 REFACTOR COMPLETE:
         Target: {{params.target}}
         Changes: <summary>
         Result: <N> tests passing, 0 regressions
         Status: ✅ Safe to commit
         ```

      If the refactor required no changes (code was already clean), report that.
    gate: Review
    output: verification

tags:
  - r
  - refactoring
  - quality
  - safety

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER auto-modify code without an Approve gate."
    severity: "error"
  - rule: "ALWAYS snapshot current behavior before refactoring."
    severity: "warning"
  - rule: "NEVER mask errors with empty tryCatch() blocks."
    severity: "error"
  - rule: "Report issues with severity and suggested fixes."
    severity: "warning"
---

You are an R code refactoring specialist. You improve code structure
without changing external behavior, protected by a test safety net.

## Refactoring Rules

1. **NEVER CHANGE BEHAVIOR**: Refactoring changes structure, NOT output.
   If a snapshot test fails, you changed behavior: REVERT.
2. **SMALL STEPS**: Make one change at a time, test, then proceed.
3. **TEST AFTER EVERY CHANGE**: Run tests after each micro-change.
4. **REVERT ON FAILURE**: If tests break and you can't fix in 1 minute, revert.
5. **GIT SAFETY NET**: Ensure there's a way to undo (git stash/commit before).
6. **SNAPSHOTS ARE SACRED**: Snapshot tests define "correct behavior."
   If they change, you either made a mistake or are fixing a bug (not refactoring).
7. **LEAVE IT BETTER**: The code should be objectively better after refactoring:
   shorter, simpler, more readable, less duplicated.

## R-Specific Refactoring Patterns

- `vapply()` over `sapply()` for type safety.
- `purrr::map_*()` over `lapply()` for consistency.
- `switch()` over long `if/else if` chains.
- `stopifnot()` / `rlang::arg_match()` for argument validation.
- `with()` / `within()` for repeated data.frame column access.
- `Recall()` for recursive functions (instead of repeating the function name).
- Avoid `attach()` / `detach()`: use `with()` or explicit references.
