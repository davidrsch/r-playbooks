---
name: r-cran-submission
version: 1.0.0
context-mode: Fork
description: "Full CRAN submission workflow: rhub checks on all platforms, CRAN policy compliance, devtools::release(), and post-submission monitoring"
trigger: both
trigger-patterns:
  - "cran *"
  - "submit cran *"
  - "cran submission *"
  - "publish cran *"
  - "release cran *"
argument-hint: "--package <name> [--bump patch|minor|major] [--first-submission true|false]"
parameters:
  package:
    type: String
    required: true
    hint: "Package name (must match the Name field in DESCRIPTION)"
  bump:
    type: String
    required: false
    default: "patch"
    enum: ["patch", "minor", "major"]
    hint: "Version component to bump before submission"
  first-submission:
    type: Boolean
    required: false
    default: false
    hint: "Is this the first CRAN submission for this package?"
steps:
  - id: pre-flight-checks
    inline-prompt: |
      Run a complete pre-submission check suite.

      Package: {{params.package}}

      1. Verify the working directory is the package root (DESCRIPTION present).
      2. Run R CMD check with CRAN flags:
         ```r
         devtools::check(
           cran = TRUE,
           args = c("--as-cran", "--no-manual"),
           error_on = "warning"
         )
         ```
         MUST have 0 errors, 0 warnings, ≤ 1 NOTE (and that NOTE must be acceptable).

      3. Run spell check:
         ```r
         devtools::spell_check()
         ```

      4. Check URL validity:
         ```r
         urlchecker::url_check()
         ```

      5. Check package size:
         ```r
         devtools::build() |> file.size() / 1e6  # must be < 5 MB
         ```

      6. Verify DESCRIPTION fields:
         - Title: title case, no period at end, ≤ 65 chars
         - Description: complete sentences, includes what the package does
         - License: valid CRAN license (MIT, GPL-3, Apache-2.0, etc.)
         - URL and BugReports fields are present
         - All authors have ORCID if available

      Report: check results and any issues to fix.
    gate: Review
    output: preflight_results

  - id: bump-version
    requires: [pre-flight-checks]
    inline-prompt: |
      Bump the version and update NEWS.md.

      Bump type: {{params.bump}}

      1. Bump version:
         ```r
         usethis::use_version("{{params.bump}}")
         ```

      2. Verify DESCRIPTION has the new version and today's date.

      3. Update `NEWS.md`:
         - Add a new section: `# {{params.package}} <new_version>`
         - List all user-visible changes since the last CRAN version
         - Format: bullet points, grouped by type (New features, Bug fixes, Breaking changes)
         - Example:
           ```
           # mypkg 1.2.0

           ## New features
           - Added `new_function()` for doing X (#42)

           ## Bug fixes
           - Fixed off-by-one error in `existing_fn()` (#38)
           ```

      Report: new version and NEWS.md summary.
    gate: Confirm
    output: version_bump

  - id: rhub-checks
    requires: [bump-version]
    inline-prompt: |
      Run cross-platform checks via R-hub v2.

      ```r
      # R-hub v2 (GitHub Actions based)
      rhub::rhub_check(
        platforms = c(
          "linux",          # Ubuntu LTS, R release
          "windows",        # Windows, R release
          "macos",          # macOS, R release
          "macos-arm64",    # Apple Silicon, R release
          "atlas",          # R-devel with ATLAS BLAS
          "clang-asan"      # Address/Undefined Sanitizer
        )
      )
      ```

      Monitor results at: https://github.com/r-hub/actions/actions
      (rhub v2 submits GitHub Actions workflows in the rhub org)

      Also run win-builder for R-devel:
      ```r
      devtools::check_win_devel()
      devtools::check_win_release()
      ```

      Wait for all checks to complete (may take 20-40 minutes).
      Report: URL of GitHub Actions run and any failures.
    gate: Review
    output: rhub_results

  - id: cran-policy-review
    requires: [rhub-checks]
    inline-prompt: |
      Review CRAN policies for compliance.

      First submission: {{params.first-submission}}

      Check the following CRAN policy points:
      1. **Writing to disk**: Only write to `tempdir()` or locations the user explicitly specifies.
         Grep for `write`, `save`, `download.file`, `file.create` outside of tempdir.
      2. **Internet access**: `download.file()`, `httr::GET()` etc. must be wrapped in
         `if (interactive())` or guarded. Use `skip_on_cran()` in tests.
      3. **Parallel computing**: Never set workers > 2 in examples or tests.
      4. **\dontrun{}**: Use `\dontrun{}` for examples that require internet or auth.
      5. **::: operator**: Never use `:::` in exported functions.
      6. **Deprecated base functions**: Check for `T`/`F` instead of `TRUE`/`FALSE`,
         `setwd()`, `options()` without restoring.
      7. **Check time**: Examples + tests must run in < 10 minutes on CRAN machines.
      8. **No `cat()` output** in non-interactive functions (use `message()` instead).

      If first submission, also check:
      - cran-comments.md exists and explains any NOTEs
      - Package has been tested on at least 3 platforms

      Report: any policy violations found.
    gate: Review
    output: policy_review

  - id: write-cran-comments
    requires: [cran-policy-review]
    inline-prompt: |
      Write or update `cran-comments.md` to accompany the submission.

      R-hub results: {{state.rhub_results}}
      Policy review: {{state.policy_review}}
      First submission: {{params.first-submission}}

      Template:
      ```markdown
      ## R CMD check results

      0 errors | 0 warnings | 1 note

      * This is a new submission. (if first-submission)
      * NOTE: "New submission" — first time on CRAN.

      ## Platforms tested

      - Ubuntu 22.04 (R release, via R-hub)
      - Windows Server 2022 (R release, via win-builder)
      - macOS 14 (R release, via R-hub)
      - macOS 14 arm64 (R release, via R-hub)
      - R-devel (win-builder)

      ## Downstream dependencies

      There are currently no downstream dependencies for this package.
      (or: "We checked X reverse dependencies and found no new issues.")
      ```

      Adapt to actual check results.
      Report: cran-comments.md written.
    output: cran_comments

  - id: final-check-and-submit
    requires: [write-cran-comments]
    inline-prompt: |
      Run a final local check and submit to CRAN.

      1. Final local check:
         ```r
         devtools::check(cran = TRUE, error_on = "warning")
         ```

      2. Build the package:
         ```r
         pkg_file <- devtools::build(manual = FALSE)
         cat("Built:", pkg_file, "\n")
         ```

      3. Submit to CRAN:
         ```r
         devtools::submit_cran()
         ```
         This will:
         - Run a final check
         - Build the package
         - Upload to https://cran.r-project.org/submit.html
         - Send a confirmation email

      4. Create a git tag for this version:
         ```r
         ver <- desc::desc_get_version()
         system2("git", c("tag", paste0("v", ver), "-m", paste0("CRAN v", ver)))
         system2("git", c("push", "--tags"))
         ```

      Report: submission confirmation and git tag.
    gate: Approve
    output: submission_result

  - id: post-submission
    requires: [final-check-and-submit]
    inline-prompt: |
      Track the submission and prepare for CRAN review.

      1. Check incoming submission status at:
         https://cran.r-project.org/web/checks/check_results_{{params.package}}.html

      2. Monitor for CRAN auto-check email (usually within 24 hours):
         - If FAILURE: fix the issue and resubmit
         - If human review required: watch for email from CRAN team (up to 10 business days)

      3. While waiting, update the pkgdown site if applicable:
         ```r
         pkgdown::build_site()
         ```

      4. Draft a release announcement for the community:
         - R-bloggers post
         - Posit Community post
         - Social media (Mastodon/LinkedIn #rstats)

      5. After CRAN acceptance, create a GitHub Release:
         - Tag: v{{bump_version}}
         - Body: copy from NEWS.md
         - Attach built .tar.gz

      Report: post-submission checklist status.
    output: post_submission

tags:
  - r
  - cran
  - release
  - package
  - publishing

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER submit to CRAN with R CMD check errors or warnings."
    severity: "error"
  - rule: "ALWAYS run rhub checks on at least Linux, Windows, and macOS before submitting."
    severity: "error"
  - rule: "NEVER write outside tempdir() in package code without explicit user permission."
    severity: "error"
  - rule: "ALWAYS use skip_on_cran() for tests that require internet or long-running computations."
    severity: "error"
  - rule: "NEVER use ::: in exported functions — only in internal code."
    severity: "error"
  - rule: "ALWAYS update NEWS.md with user-visible changes before version bump."
    severity: "warning"
---

You are an R package submission specialist guiding a package through the full CRAN submission
process following the official CRAN Repository Policy and the R Packages book (r-pkgs.org).

## Rules

1. Zero errors and zero warnings in R CMD check are non-negotiable before submission.
2. A single NOTE for "new submission" or "installed package size" is acceptable.
3. Always check on multiple platforms — CRAN runs on Linux, Windows, and macOS.
4. Use rhub v2 (GitHub Actions based) for platform checks — rhub v1 is deprecated.
5. cran-comments.md must explain every NOTE from the check results.
6. Read the CRAN policy at https://cran.r-project.org/web/packages/policies.html before every submission.
7. After acceptance, update the pkgdown site and announce on #rstats channels.
8. If CRAN rejects, fix all issues promptly and resubmit within 2 weeks.
