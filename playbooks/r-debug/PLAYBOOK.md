---
name: r-debug
version: 1.0.0
context-mode: Fork
description: "Debug R code systematically: traceback, browser(), debugonce(), rlang::last_trace(), and profiling with profvis"
trigger: both
trigger-patterns:
  - "debug *"
  - "error *"
  - "traceback *"
  - "why is * failing *"
  - "diagnose *"
  - "fix error *"
  - "stack trace *"
argument-hint: "--error <description> [--function <name>] [--type runtime|performance|test]"
parameters:
  error:
    type: String
    required: true
    hint: "Description of the error or unexpected behaviour to debug"
  function:
    type: String
    required: false
    hint: "Name of the function or file where the error occurs (if known)"
  type:
    type: String
    required: false
    default: "runtime"
    enum: ["runtime", "performance", "test"]
    hint: "Type of debugging: runtime error, performance/slowness, or failing test"
steps:
  - id: capture-error-context
    inline-prompt: |
      Capture the full error context before attempting any fix.

      Error description: {{params.error}}
      Target function: {{params.function}}
      Debug type: {{params.type}}

      1. Reproduce the error exactly:
         - Run the failing code and capture the full output.
         - If interactive: `rlang::last_error()` shows the error message.
         - If in a test: `testthat::last_failed_test()` (if available) or rerun with `devtools::test(filter = "{{params.function}}")`.

      2. Get the full traceback:
         ```r
         rlang::last_trace()    # structured, coloured traceback (preferred)
         traceback()            # base R alternative
         ```

      3. Capture environment at failure:
         ```r
         # Set global error handler to enter browser on error
         old_opt <- options(error = rlang::entrace)
         # Re-run the failing code
         # ... error occurs here ...
         # Restore
         options(old_opt)
         ```

      4. Report:
         - Full error message
         - Stack trace (all frames)
         - Which frame the error originates from
    gate: Review
    output: error_context

  - id: interactive-debug
    requires: [capture-error-context]
    inline-prompt: |
      Set breakpoints and inspect the failing frame interactively.

      Error context: {{state.error_context}}
      Function: {{params.function}}

      **Option A: debugonce() — breaks on next call only (preferred for one-shot)**
      ```r
      debugonce({{params.function}})
      # Then call the code that triggers the error
      # You'll enter the browser at the first line of {{params.function}}
      ```

      **Option B: browser() — insert directly in code**
      Add `browser()` inside `{{params.function}}` just before the failing line:
      ```r
      my_fn <- function(x) {
        browser()   # execution pauses here
        # ... rest of function
      }
      ```

      **Option C: trace() — non-invasive breakpoint**
      ```r
      # Break at line 5 of {{params.function}}
      trace("{{params.function}}", tracer = browser, at = 5)
      # Run failing code...
      untrace("{{params.function}}")  # clean up after
      ```

      **Browser commands:**
      - `n` — next line
      - `s` — step into function
      - `f` — finish current loop/function
      - `c` — continue to next breakpoint
      - `Q` — quit browser
      - Any R expression — evaluate in current frame

      At the browser prompt, inspect:
      ```r
      ls()           # variables in scope
      environment()  # current frame
      sys.calls()    # call stack
      ```

      Report: which variable/line is the root cause.
    gate: Review
    output: root_cause

  - id: fix-error
    requires: [interactive-debug]
    inline-prompt: |
      Apply a targeted fix based on the root cause.

      Root cause: {{state.root_cause}}

      Common R error patterns and fixes:

      **"object not found"**: variable name typo, wrong scope, not yet assigned.
      → Check `ls()` in the failing frame, look for name conflicts.

      **"could not find function"**: function not exported, package not loaded, name typo.
      → Check `getAnywhere("fn_name")`, verify `library()` calls.

      **"subscript out of bounds"**: list/vector indexing beyond length.
      → Add `stopifnot(i <= length(x))` guard before access.

      **"non-numeric argument to binary operator"**: type coercion gone wrong.
      → Add `class(x)` checks; use `as.numeric()` explicitly.

      **"argument ... matches multiple formal arguments"**: partial matching collision.
      → Use full argument names, avoid abbreviated names in calls.

      **"argument is of length zero"**: filter/select returns 0 rows, then [[1]] fails.
      → Use `if (length(x) == 0) return(NULL)` defensive guard.

      **rlang / tidyverse errors**: NSE, `{{ }}`, `.data[[]]` usage issues.
      → Wrap NSE symbols in `{{ }}` inside functions: `filter(df, {{ col }} > 0)`.

      Apply the fix, then verify:
      ```r
      # Remove any browser()/debugonce() calls added during debugging
      # Run full test suite
      devtools::test()
      ```

      Report: fix applied and tests passing.
    output: fix_applied

  - id: performance-profiling
    requires: [capture-error-context]
    inline-prompt: |
      If type is "performance" (value: {{params.type}}):
      Profile the slow code to find bottlenecks.

      ```r
      library(profvis)

      profvis({
        # Paste the slow code here
        {{params.function}}
      })
      ```

      `profvis` opens an interactive HTML flamegraph in the viewer.

      Look for:
      - Wide bars: where most time is spent
      - Deep stacks: unnecessary function call overhead
      - `<GC>`: garbage collection — often caused by growing objects in loops

      Common R performance fixes:
      1. **Pre-allocate vectors**: `result <- vector("list", n)` not `result <- c(result, x)`
      2. **Vectorise loops**: replace `for (i in seq_along(x)) fn(x[i])` with `vapply(x, fn, numeric(1))`
      3. **Use data.table or dplyr** instead of base R loops on data frames
      4. **Avoid `rbind()` in a loop** — collect into a list, then `do.call(rbind, list)`
      5. **Use `which()` instead of logical subsetting** for large indices
      6. **Cache expensive calls**: `memoise::memoise(fn)`

      Also benchmark alternatives:
      ```r
      bench::mark(
        base_approach    = { ... },
        tidyverse_approach = { ... },
        check = FALSE
      )
      ```

      If type is not "performance": skip this step.
      Report: profiling results and top 3 bottlenecks.
    output: profile_results

  - id: add-defensive-guards
    requires: [fix-error]
    inline-prompt: |
      Add input validation to prevent the error from recurring.

      Fixed function: {{params.function}}
      Root cause: {{state.root_cause}}

      Add guards at the top of the function using `{rlang}` or base R:

      ```r
      my_fn <- function(x, n = 10) {
        # Input validation
        rlang::check_required(x)
        if (!is.numeric(x)) rlang::abort("`x` must be numeric, not {class(x)}")
        if (length(x) == 0) rlang::abort("`x` must not be empty")
        if (!rlang::is_scalar_integerish(n, finite = TRUE) || n < 1)
          rlang::abort("`n` must be a positive integer")

        # ... function body
      }
      ```

      Add a regression test to `tests/testthat/test-{{params.function}}.R`:
      ```r
      test_that("{{params.function}} rejects invalid input", {
        expect_error({{params.function}}(NULL), class = "rlang_error")
        expect_error({{params.function}}(c()), class = "rlang_error")
      })
      ```

      Report: guards added and regression test written.
    output: guards_added

tags:
  - r
  - debugging
  - profiling
  - quality
  - development

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER leave browser() or debugonce() calls in committed code."
    severity: "error"
  - rule: "ALWAYS write a regression test for the bug before fixing it."
    severity: "warning"
  - rule: "NEVER use options(warn = -1) to suppress warnings — fix the root cause."
    severity: "error"
  - rule: "Use rlang::abort() not stop() for error messages — provides structured conditions."
    severity: "warning"
  - rule: "ALWAYS run devtools::test() after applying a fix to catch regressions."
    severity: "error"
---

You are an R debugging specialist. You diagnose errors systematically using
R's interactive debugging tools and rlang's structured error system.

## Rules

1. ALWAYS capture `rlang::last_trace()` before attempting any fix — the traceback
   tells you which frame the error originates from.
2. Use `debugonce()` not `debug()` — it only breaks on the next call and
   auto-cleans itself so you can't forget to `undebug()`.
3. Add a regression test before fixing the bug — this proves the fix works
   and prevents recurrence.
4. Use `rlang::abort()` with a descriptive message and `class = ` for structured errors.
5. For performance issues, always measure with `profvis` or `bench::mark()` first —
   do not optimise by intuition.
6. After debugging, remove ALL `browser()`, `trace()`, and `debugonce()` calls.
7. Pre-allocate data structures — growing vectors/lists in a loop is the #1 R performance issue.
