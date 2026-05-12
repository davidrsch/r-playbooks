---
name: r-init-package
version: 1.0.0
context-mode: Fork
description: Scaffold a new R package with usethis, renv, testthat, roxygen2, pkgdown, and CI
trigger: auto
trigger-patterns:
  - "package *"
  - "init package *"
  - "scaffold package *"
  - "create package *"
  - "new R package *"
  - "initialize package *"
argument-hint: "--name <pkg> [--license MIT|GPL-3|Apache-2.0] [--ci true|false] [--use-renv true|false]"
parameters:
  name:
    type: String
    required: true
    hint: "Package name (lowercase, letters/numbers/dots only)"
  owner:
    type: String
    required: false
    hint: "GitHub owner/org for CI badges and repo references"
  license:
    type: String
    required: false
    default: "MIT"
    enum: ["MIT", "GPL-3", "Apache-2.0", "CC0", "file LICENSE"]
    hint: "License type for the package"
  ci:
    type: Boolean
    required: false
    default: true
    hint: "Set up GitHub Actions CI (test-coverage, R CMD check, pkgdown)"
  use-renv:
    type: Boolean
    required: false
    default: true
    hint: "Initialize renv for dependency management"
  pkgdown:
    type: Boolean
    required: false
    default: true
    hint: "Set up pkgdown documentation site"
  lintr:
    type: Boolean
    required: false
    default: true
    hint: "Configure lintr for code style checking"
steps:
  - id: validate-name
    inline-prompt: |
      Validate that "{{params.name}}" is a valid R package name:
      - Lowercase letters, numbers, and dots only
      - Starts with a letter
      - Does not end with a dot
      - Not already taken on CRAN or Bioconductor
      Run: `available::available("{{params.name}}", browse = FALSE)` if the package is installed.
      Report: valid/invalid with reasoning.
    output: name_check

  - id: create-structure
    requires: [validate-name]
    inline-prompt: |
      Create the R package structure using usethis:

      1. Run: `usethis::create_package("{{params.name}}", open = FALSE)`
      2. Run: `usethis::proj_set("{{params.name}}")`
      3. Create the standard directory layout:
         - R/           (function files)
         - tests/testthat/ (test files)
         - man/         (documentation, roxygen-generated)
         - vignettes/   (long-form guides)
         - data-raw/    (data generation scripts)
         - inst/        (external files)

      Report: package path and directory listing.
    gate: Confirm
    output: pkg_path

  - id: setup-license
    requires: [create-structure]
    inline-prompt: |
      Set the package license.

      1. Run: `usethis::use_{{params.license}}_license()` in the package directory at {{state.pkg_path}}
         Map CC0 → `use_cc0_license()`, file LICENSE → `use_proprietary_license()`
         For GPL-3, use `use_gpl3_license()`; for Apache-2.0, use `use_apache_license()`

      Report: license file created.
    output: license_info

  - id: setup-renv
    requires: [create-structure]
    inline-prompt: |
      If the user specified 'use-renv' as true (value: {{params.use-renv}}):
      Initialize renv for reproducible dependency management:

      1. Run: `renv::init(project = "{{state.pkg_path}}")` to create a minimal renv.lock
      2. Verify `renv.lock` and `.Rprofile` were created
      3. Add `renv.lock` to git tracking, ensure `renv/` is in `.gitignore`
      4. Run: `renv::snapshot(type = "explicit")` to lock exact package versions.
      5. Ensure `renv.lock` is committed to git.

      Report: renv initialized and files created.

      If the user specified 'use-renv' as false: Skip renv initialization.
      Report: skipped by user preference.
    output: renv_status
    gate: Confirm

  - id: setup-testthat
    requires: [create-structure]
    inline-prompt: |
      Set up the testthat testing framework:

      1. Run: `usethis::use_testthat(edition = 3)` in the package at {{state.pkg_path}}
      2. Verify `tests/testthat.R` exists with `library({{params.name}})` and appropriate testthat config
      3. Ensure `tests/testthat/setup.R` includes:
         ```r
         library(testthat)
         local_reproducible_output(width = 80)
         ```
      4. Create an initial test file: `tests/testthat/test-example.R` with:
         ```r
         test_that("package loads correctly", {
           library({{params.name}})
           expect_true(TRUE)
         })
         ```
      5. Run: `devtools::test()` to verify tests pass

      Report: test framework status and test results.
    output: test_status

  - id: setup-roxygen
    requires: [create-structure]
    inline-prompt: |
      Configure roxygen2 documentation:

      1. Run: `usethis::use_roxygen_md()` to use Markdown in roxygen docs
      2. Verify `man/` directory is in `.Rbuildignore` (roxygen generates it)
      3. Create a package-level doc file at `R/{{params.name}}-package.R`:
         ```r
         #' {{params.name}}: What the Package Does (Title Case)
         #'
         #' A one-paragraph description of what the package does.
         #'
         #' @docType package
         #' @name {{params.name}}-package
         #' @keywords internal
         #'
         #' Use `@returns` to document return values for all exported functions.
         #' Use `@family <group>` to group related functions in pkgdown reference.
         #' Use `@noRd` for internal helper functions that should not appear in documentation.
         "_PACKAGE"
         ```
      4. Run: `devtools::document()` and verify `man/` files are generated

      Report: roxygen configuration complete.
    output: roxygen_status

  - id: setup-pkgdown
    requires: [setup-roxygen]
    inline-prompt: |
      If the user specified 'pkgdown' as true (value: {{params.pkgdown}}):
      Set up pkgdown documentation site:

      1. Run: `usethis::use_pkgdown()` in {{state.pkg_path}}
      2. Verify `_pkgdown.yml` and `pkgdown/` were created
      3. Add `docs/` to `.gitignore` and `.Rbuildignore`
      4. Configure `_pkgdown.yml` with:
         ```yaml
         template:
           bootstrap: 5
         reference:
           - title: "Core Functions"
             contents:
               - has_concept("core")
         ```

      Report: pkgdown configured.

      If the user specified 'pkgdown' as false: Skip pkgdown.
      Report: skipped by user preference.
    output: pkgdown_status

  - id: setup-lintr
    requires: [create-structure]
    inline-prompt: |
      If the user specified 'lintr' as true (value: {{params.lintr}}):
      Configure code style tools:

      1. Run: `usethis::use_lintr()`: creates `.lintr` config with tidyverse defaults
      2. Create or verify `.Rproj` file exists for the package

      Report: lintr configured.

      If the user specified 'lintr' as false: Skip lintr.
      Report: skipped by user preference.
    output: lintr_status

  - id: setup-community
    requires: [create-structure]
    inline-prompt: |
      Set up community files for the package at {{state.pkg_path}}:

      1. Run: `usethis::use_spell_check()`: configure spell checking for docs
      2. Run: `usethis::use_tidy_contributing()`: create CONTRIBUTING.md
      3. Run: `usethis::use_tidy_coc()`: create CODE_OF_CONDUCT.md

      Report: community files created.
    output: community_status

  - id: setup-readme
    requires: [create-structure]
    inline-prompt: |
      Create a README for the package:

      1. Run: `usethis::use_readme_rmd(open = FALSE)` in {{state.pkg_path}}
      2. Edit `README.Rmd` to include:
         - Package name and one-line description
         - Installation instructions: `remotes::install_github("owner/{{params.name}}")`
         - Minimal usage example
         - License badge
         - R CMD check status badge (if ci is enabled)
      3. Remove the default `README.md` if it conflicts
      4. Do NOT render the README yet (leave that for a separate step)

      Report: README.Rmd created.
    output: readme_status

  - id: initial-commit
    requires:
      [
        setup-renv,
        setup-license,
        setup-testthat,
        setup-roxygen,
        setup-pkgdown,
        setup-lintr,
        setup-readme,
        setup-community,
      ]
    inline-prompt: |
      Verify the package before initial commit:

      1. Change to {{state.pkg_path}}
      2. Run `devtools::check(args = c("--no-manual", "--no-vignettes", "--as-cran"))`
         R CMD check MUST pass with 0 errors before commit
      3. Fix any errors or warnings before proceeding
      4. Run: `pak::lockfile_create("pkg.lock")` to generate SBOM/manifest
      5. Make the initial git commit:
         Run: `git commit -m "feat: initial package scaffold for {{params.name}}"`

      Report: commit hash and summary.
    gate: Review
    output: commit_hash

  - id: setup-ci
    requires: [initial-commit]
    inline-prompt: |
      If the user specified 'ci' as true (value: {{params.ci}}):
      Set up GitHub Actions CI for the package. Invoke the `r-ci-gha` playbook
      or manually create the workflow file:

      1. Create `.github/workflows/R-CMD-check.yaml` with:
         - R CMD check on ubuntu-latest, macOS-latest, windows-latest
         - Matrix of R versions: release, devel
         - renv restore step (if renv is enabled)
      2. Create `.github/workflows/test-coverage.yaml` with:
         - covr::codecov() upload
         - Run on ubuntu-latest, R release only
      3. Create `.github/workflows/pkgdown.yaml` with:
         - Build pkgdown site on push to main
         - Deploy to gh-pages branch

      Commit the workflow files and push.

      Report: CI workflows created and pushed.

      If the user specified 'ci' as false: Skip CI setup.
      Report: skipped by user preference.
    gate: Review
    output: ci_status

  - id: setup-precommit
    requires: [initial-commit]
    inline-prompt: |
      Suggest pre-commit hook setup for ongoing quality:

      1. Recommend installing the `pre-commit` Python package:
         ```bash
         pip install pre-commit
         # or brew install pre-commit
         ```
      2. Create a `.pre-commit-config.yaml` with R-specific hooks:
         ```yaml
         repos:
           - repo: https://github.com/lorenzwalthert/precommit
             rev: v0.4.0
             hooks:
               - id: style-files
               - id: parsable-R
               - id: no-browser-statement
               - id: no-debug-statement
               - id: lintr
               - id: roxygenize
         ```
      3. Run: `pre-commit install` to activate the hooks

      Report: pre-commit configuration suggested.
    output: precommit_status

tags:
  - r
  - package
  - init
  - scaffold

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

You are an R package initialization specialist. Your role is to scaffold
production-ready R packages following the tidyverse conventions and best
practices from the R Packages book (r-pkgs.org).

## Rules

1. Always validate the package name before creating anything.
2. Use `usethis` functions whenever available: never manually create
   files that usethis can generate.
3. Every step that creates or modifies files should report what was
   created and where.
4. If a usethis function fails, diagnose the error and suggest a fix.
5. All paths should be relative to the working directory unless
   stated otherwise.
6. The package at {{state.pkg_path}} must pass R CMD check with
   0 errors and 0 warnings before this playbook is complete.
7. Use `here::here()` for all path construction within the package.
8. Do NOT use `setwd()`: use `usethis::proj_set()` or pass paths explicitly.
