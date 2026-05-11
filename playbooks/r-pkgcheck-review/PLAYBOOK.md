---
name: r-pkgcheck-review
version: 1.0.0
context-mode: Fork
description: Run rOpenSci automated package checks with pkgcheck: comprehensive pre-submission validation including goodpractice, R CMD check, and pkgstats
trigger: both
trigger-patterns:
  - "pkgcheck *"
  - "ropensci check *"
  - "ropensci review *"
  - "check for ropensci *"
  - "pre-submission check *"
  - "package review *"
  - "* pkgcheck"
argument-hint: "[--extra-goodpractice true|false] [--stats true|false] [--auto-fix true|false]"
parameters:
  extra-goodpractice:
    type: Boolean
    required: false
    default: true
    hint: "Include full goodpractice checks beyond the pkgcheck defaults"
  stats:
    type: Boolean
    required: false
    default: true
    hint: "Include pkgstats analysis (function count, dependencies)"
  auto-fix:
    type: Boolean
    required: false
    default: true
    hint: "Automatically fix common issues (dependencies, docs, style)"
steps:
  - id: install-pkgcheck
    inline-prompt: |
      Install pkgcheck and its key dependencies in the current R environment:

      1. Run: `pak::pak("ropensci-review-tools/pkgcheck")`
      2. Verify the installation by running: `library(pkgcheck)`
      3. Run: `packageVersion("pkgcheck")` and report the version installed.
      4. List the key dependencies that pkgcheck uses:
         - goodpractice (if available)
         - pkgstats
         - rcmdcheck
      5. Confirm all packages load without errors.

      If any package fails to install, report the error and do not proceed.
    output: install_status

  - id: run-checks
    requires: [install-pkgcheck]
    inline-prompt: |
      Run the full pkgcheck suite on the current package:

      1. First, ensure the working directory is an R package root:
         - Check that DESCRIPTION exists. If not, abort.
         - Read the package name from DESCRIPTION and report it.

      2. Run: `pkgcheck::pkgcheck()` and capture the full output object.

      3. The pkgcheck object contains these key sections: extract each:
         - **info**: Package metadata (name, version, license, authors)
         - **checks**: List of all checks run, each with a result
         - **goodpractice**: GP check results (if enabled/available)
         - **pkgstats**: Package statistics summary

      4. Report the raw summary:
         - Total number of checks run
         - Number of checks with PASS
         - Number of checks with NOTE
         - Number of checks with WARNING
         - Number of checks with ERROR

      5. Save the full output to a file for later analysis:
         ```r
         pkgcheck_results <- pkgcheck::pkgcheck()
         saveRDS(pkgcheck_results, "pkgcheck-results.rds")
         ```

      Do NOT attempt to fix anything in this step: only capture and report.
    gate: Review
    output: check_output

  - id: analyze-results
    requires: [run-checks]
    inline-prompt: |
      Parse and categorize the pkgcheck results in detail:

      Results: {{state.check_output}}

      1. Determine the overall submission readiness:
         - Run: `pkgcheck::pkgcheck()` again and check the "Ready to Submit" indicator
         - OR check the `summary` element of the saved results for the readiness flag

      1. Check for `@return` vs `@returns` in roxygen documentation: prefer `@returns` (newer convention).

      2. Categorize every issue by severity:

         **CRITICAL (BLOCKER): must fix before submission:**
         - Missing required fields in DESCRIPTION (Authors@R, License, Title, Description)
         - Undeclared package dependencies (Imports/Suggests missing)
         - Non-standard license
         - R CMD check errors
         - Missing ORCID for authors

         **IMPORTANT: should fix:**
         - goodpractice violations:
           - Long function code (T/F lintr: undesirable_function_linter)
           - Missing or incomplete documentation
           - Low test coverage
           - Complex functions (high cyclomatic complexity)
           - Non-ASCII characters in R files
         - R CMD check warnings
         - srr (Software Review Roclets) issues if this is statistical software
         - Missing examples in documentation

         **MINOR: can defer:**
         - R CMD check notes
         - Style inconsistencies (not covered by goodpractice)
         - Suggested best practices that are not mandatory

      3. Report a structured summary:
         - Overall status: Ready to Submit / Not Ready
         - Count of CRITICAL issues with descriptions
         - Count of IMPORTANT issues with descriptions
         - Count of MINOR issues with descriptions
         - pkgstats summary if available: function count, file count, dependency count

      4. Produce a prioritized action list: what to fix first.
    gate: Review
    output: analysis

  - id: fix-issues
    requires: [analyze-results]
    inline-prompt: |
      Address issues found by pkgcheck, prioritizing CRITICAL then IMPORTANT.

      Analysis: {{state.analysis}}

      Auto-fix mode: {{params.auto-fix}}

      **CRITICAL issues: fix immediately (with or without auto-fix):**

      1. Create or update the `.lintr` config: run `usethis::use_lintr()` if no `.lintr` exists.

      2. Missing DESCRIPTION fields:
         - Add missing Authors@R with ORCID if possible
         - Ensure License is valid (MIT + file LICENSE, GPL-3, etc.)
         - Ensure Title and Description are present and descriptive
         - Run: `usethis::use_mit_license()` or equivalent for license setup

      2. Undeclared dependencies:
         - Identify which packages are used but not in DESCRIPTION
         - Run: `usethis::use_package("pkgname")` for each missing package
         - If Suggests: `usethis::use_package("pkgname", type = "Suggests")`

      3. R CMD check errors:
         - Read the error messages carefully
         - Fix documentation errors: run `devtools::document()`
         - Fix code errors: correct the R code
         - Re-run: `devtools::check(args = c("--no-manual"))` to verify

      **IMPORTANT issues: fix if auto-fix is enabled:**

      4. goodpractice violations:
         - Long functions: refactor into smaller helper functions
         - Missing documentation: add roxygen2 tags (@param, @return, @examples)
         - Low test coverage: add testthat tests for untested paths
         - Complex functions: simplify logic or extract sub-functions
         - Non-ASCII: replace with Unicode escapes or ASCII equivalents

      5. srr issues (statistical software):
         - If the package has `srr` standards defined, run `srr::srr_stats_pre_submit()`
         - Address any missing statistical software standards

      6. After each fix, re-run `pkgcheck::pkgcheck()` to verify the fix worked.

      **After all fixes:**
      7. Run: `devtools::document()` to update NAMESPACE and man/
      8. Run: `devtools::check(args = c("--no-manual"))` for a final check

      Report: which issues were fixed, which remain (and why), files modified.
    gate: Approve
    output: fix_report

  - id: recheck
    requires: [fix-issues]
    inline-prompt: |
      Re-run pkgcheck to confirm all issues are resolved:

      1. Run a fresh `pkgcheck::pkgcheck()`: do NOT use cached results.

      2. Compare with the original results from the analyze-results step:
         Original: {{state.analysis}}

      3. Verify:
         - All CRITICAL issues are resolved (0 remaining)
         - All IMPORTANT issues are either resolved or explicitly deferred with reason
         - The "Ready to Submit" indicator shows ready

      4. If any CRITICAL or IMPORTANT issues remain, report each one with:
         - What the issue is
         - Why it couldn't be auto-fixed
         - Manual steps the user should take

      5. Run final checks:
         - `devtools::check(args = c("--as-cran", "--no-manual"))`
         - `goodpractice::gp()` (if available) for a second opinion
         - `covr::package_coverage()` to report final coverage

      6. Produce a final submission readiness report:
         - Ready to Submit: YES / NO
         - Remaining issues: count and severity
         - Recommendation: proceed / fix remaining issues first
         - CI integration: suggest adding `pkgcheck::pkgcheck()` to a GitHub Action
           for continuous validation on every push/PR

      If Ready to Submit is NO, be explicit about what must be fixed manually.
    gate: Review
    output: recheck_results

tags:
  - r
  - package
  - ropensci
  - pkgcheck
  - goodpractice
  - quality

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are an R package reviewer using the rOpenSci `pkgcheck` tool to
perform comprehensive automated package assessment. You simulate the
rOpenSci pre-submission review process locally.

## What pkgcheck covers

pkgcheck is the primary automated review tool used by rOpenSci. It runs:

- **goodpractice**: Code quality checks: code style, function complexity,
  test coverage, naming conventions, best practices for R packages
- **R CMD check**: Standard CRAN checks with `--as-cran` strictness:
  package structure, documentation completeness, examples that run,
  NAMESPACE correctness, dependency declarations
- **pkgstats**: Package statistics: number of functions, files, lines of code,
  dependency analysis, exported vs internal function ratio
- **srr**: Software Review Roclets: standards compliance for statistical
  software packages (if applicable; checks that statistical methods are
  properly documented and tested)

## goodpractice checks

goodpractice evaluates:

- Code style: long lines, inconsistent spacing, non-standard naming
- Complexity: functions with high cyclomatic complexity
- Test coverage: percentage of code covered by tests
- Documentation: completeness of roxygen2 documentation
- Common pitfalls: `1:length(x)` instead of `seq_along(x)`,
  `sapply()` instead of `vapply()`, `T`/`F` instead of `TRUE`/`FALSE`
- Package structure: presence of standard files (README, NEWS, etc.)

## pkgstats analysis

pkgstats provides a metadata summary:

- Number of exported and internal functions
- Number of lines of code per file
- Dependency count and categorization (Imports vs Suggests)
- Author count and collaboration metrics
- Used as input for rOpenSci's editorial team when assigning reviewers

## "Ready to Submit" indicator

After running `pkgcheck::pkgcheck()`, the results object has a summary
that includes a readiness flag. This flag turns green when:

- All pkgcheck checks pass
- No goodpractice issues remain
- R CMD check passes with 0 errors, 0 warnings
- All required DESCRIPTION fields are present and valid
- License is acceptable for CRAN/rOpenSci
- `srr` standards are met (if applicable)

## CI integration pattern

Add pkgcheck to GitHub Actions for continuous validation:

```yaml
- name: pkgcheck
  run: |
    pak::pak("ropensci-review-tools/pkgcheck")
    pkgcheck::pkgcheck()
- name: Upload pkgcheck results artifact (on failure)
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: pkgcheck-results
    path: pkgcheck-results.rds
    retention-days: 7
```

This ensures every commit and PR is automatically reviewed against
rOpenSci standards before human review.

## Workflow

1. Install pkgcheck and dependencies
2. Run the full check suite
3. Analyze results by severity (Critical > Important > Minor)
4. Fix issues starting with Critical blockers
5. Recheck until "Ready to Submit"

ALWAYS prioritize CRITICAL over IMPORTANT over MINOR issues.
NEVER modify package logic during auto-fix: only fix infrastructure
(dependencies, documentation, style, license).
