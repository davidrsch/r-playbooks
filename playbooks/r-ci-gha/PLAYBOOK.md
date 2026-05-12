---
name: r-ci-gha
version: 1.0.0
context-mode: Fork
description: "Set up GitHub Actions CI for an R package: R CMD check, test coverage, pkgdown, and linting"
trigger: auto
trigger-patterns:
  - "ci *"
  - "github actions *"
  - "CI setup *"
  - "continuous integration *"
  - "CI/CD *"
argument-hint: "[--r-versions release,devel,oldrel] [--coverage true|false] [--pkgdown true|false] [--lint true|false] [--multiversion true|false]"
parameters:
  r-versions:
    type: Array
    required: false
    default: ["release"]
    hint: "R versions to test against (release, devel, oldrel, 4.4, 4.3, etc.)"
  coverage:
    type: Boolean
    required: false
    default: true
    hint: "Add a codecov test coverage workflow"
  pkgdown:
    type: Boolean
    required: false
    default: true
    hint: "Add a pkgdown site build-and-deploy workflow"
  lint:
    type: Boolean
    required: false
    default: true
    hint: "Add a lintr linting workflow"
  multiversion:
    type: Boolean
    required: false
    default: false
    hint: "Run matrix across ubuntu, macOS, and Windows"
steps:
  - id: analyze-project
    inline-prompt: |
      Analyze the R package to determine CI needs:

      1. Read DESCRIPTION:
         - Package name
         - SystemRequirements (if any: these need apt/pacman/brew packages)
         - Imports/Suggests
         - Is renv in use?
      2. Check if tests exist: `tests/testthat/` directory.
      3. Check if pkgdown is configured: `_pkgdown.yml` exists.
      4. Check if lintr config exists: `.lintr` exists.
      5. Report: CI requirements based on project state.
    output: project_analysis

  - id: create-r-cmd-check
    requires: [analyze-project]
    inline-prompt: |
      Create `.github/workflows/R-CMD-check.yaml`:

      Based on project: {{state.project_analysis}}

      ```yaml
      name: R CMD Check
      on:
        push:
          branches: [main, master]
        pull_request:
          branches: [main, master]
      concurrency:
        group: ${{ github.workflow }}-${{ github.ref }}
        cancel-in-progress: true
      permissions:
        contents: read
      jobs:
        check:
          runs-on: ${{ matrix.os }}
          timeout-minutes: 30
          strategy:
            fail-fast: false
            matrix:
              os: [ubuntu-latest]
              r: [release]
          env:
            R_REMOTES_NO_ERRORS_FROM_WARNINGS: true
            RSPM: https://packagemanager.rstudio.com/all/latest
            OTEL_SERVICE_NAME: r-pkg-check
            OTEL_EXPORTER_OTLP_ENDPOINT: ${{ secrets.OTEL_EXPORTER_OTLP_ENDPOINT }}
          steps:
            - uses: actions/checkout@v4
            - uses: r-lib/actions/setup-r@v2
              with:
                r-version: ${{ matrix.r }}
            - uses: r-lib/actions/setup-pak@v2
            - name: Install dependencies
              run: pak::local_install_dev_deps()
              shell: Rscript {0}
            - uses: r-lib/actions/check-r-package@v2
            - name: Upload check results on failure
              if: failure()
              uses: actions/upload-artifact@v4
              with:
                name: check-results-${{ matrix.os }}-${{ matrix.r }}
                path: check/
      ```

      If multiversion is enabled, expand the matrix to include macOS-latest
      and windows-latest, and test against multiple R versions.

      If renv is in use, add an renv cache step to speed up restoration:
      ```yaml
            - name: Cache renv packages
              uses: actions/cache@v4
              with:
                path: renv/library
                key: renv-${{ runner.os }}-${{ hashFiles('renv.lock') }}
                restore-keys: renv-${{ runner.os }}-
      ```

      If SystemRequirements are listed in DESCRIPTION, add apt-get steps
      for ubuntu and brew steps for macOS.

      Create the file and report: workflow created.
    gate: Review
    output: check_workflow

  - id: create-coverage
    requires: [analyze-project]
    inline-prompt: |
      Create `.github/workflows/test-coverage.yaml` when coverage is enabled.

      If coverage is disabled, skip and report: skipped.

      When coverage is enabled:

      ```yaml
      name: Test Coverage
      on:
        push:
          branches: [main, master]
        pull_request:
          branches: [main, master]
      jobs:
        coverage:
          runs-on: ubuntu-latest
          env:
            RSPM: https://packagemanager.rstudio.com/all/latest
          steps:
            - uses: actions/checkout@v4
            - uses: r-lib/actions/setup-r@v2
              with:
                r-version: release
            - uses: r-lib/actions/setup-r-dependencies@v2
              with:
                extra-packages: any::covr
            - name: Run coverage
              run: covr::codecov()
              shell: Rscript {0}
      ```

      Report: coverage workflow created.
    gate: Review
    output: coverage_workflow

  - id: create-pkgdown
    requires: [analyze-project]
    inline-prompt: |
      Create `.github/workflows/pkgdown.yaml` when pkgdown is enabled.

      If pkgdown is disabled, skip and report: skipped.

      When pkgdown is enabled:

      ```yaml
      name: pkgdown
      on:
        push:
          branches: [main, master]
        workflow_dispatch:
      permissions:
        contents: write
        pages: write
      jobs:
        pkgdown:
          runs-on: ubuntu-latest
          env:
            RSPM: https://packagemanager.rstudio.com/all/latest
          steps:
            - uses: actions/checkout@v4
            - uses: r-lib/actions/setup-r@v2
              with:
                r-version: release
            - uses: r-lib/actions/setup-r-dependencies@v2
              with:
                extra-packages: any::pkgdown
            - name: Build site
              run: pkgdown::build_site_github_pages(new_process = FALSE, install = FALSE)
              shell: Rscript {0}
            - name: Deploy to GitHub Pages
              uses: peaceiris/actions-gh-pages@v3
              with:
                github_token: ${{ secrets.GITHUB_TOKEN }}
                publish_dir: ./docs
      ```

      Report: pkgdown workflow created.
    gate: Review
    output: pkgdown_workflow

  - id: create-lint
    requires: [analyze-project]
    inline-prompt: |
      Create `.github/workflows/lint.yaml` when lint is enabled.

      If lint is disabled, skip and report: skipped.

      When lint is enabled:

      ```yaml
      name: Lint
      on:
        push:
          branches: [main, master]
        pull_request:
          branches: [main, master]
      jobs:
        lint:
          runs-on: ubuntu-latest
          env:
            RSPM: https://packagemanager.rstudio.com/all/latest
          steps:
            - uses: actions/checkout@v4
            - uses: r-lib/actions/setup-r@v2
              with:
                r-version: release
            - uses: r-lib/actions/setup-r-dependencies@v2
              with:
                extra-packages: any::lintr
            - name: Lint
              run: lintr::lint_package()
              shell: Rscript {0}
      ```

      Report: lint workflow created.
    gate: Review
    output: lint_workflow

  - id: add-badges
    requires: [create-r-cmd-check]
    inline-prompt: |
      Generate README badges for the CI workflows.

      Add to README.Rmd (or README.md) below the title:

      ```markdown
      <!-- badges: start -->
      [![R CMD check](https://github.com/<owner>/<repo>/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/<owner>/<repo>/actions/workflows/R-CMD-check.yaml)
      <!-- badges: end -->
      ```

      If coverage is enabled, also add a Codecov badge.
      If pkgdown is enabled, note the pkgdown site will be at
      `https://<owner>.github.io/<repo>/`.

      Note the user needs to replace `<owner>/<repo>` with their actual repository.

      Report: badge code generated.
    output: badge_code

tags:
  - r
  - ci
  - github-actions
  - devops
  - automation

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER hardcode secrets or tokens in workflow files — use GitHub Secrets."
    severity: "error"
  - rule: "ALWAYS include HEALTHCHECK in Dockerfiles."
    severity: "warning"
  - rule: "Never expose ports without proper security configuration."
    severity: "warning"
  - rule: "Use multi-stage Docker builds to minimize image size."
    severity: "warning"
---

You are a CI/CD specialist for R packages using GitHub Actions.
You use the r-lib/actions ecosystem for reliable R CI workflows.

## Rules

1. ALWAYS use `r-lib/actions/setup-r@v2` and `r-lib/actions/setup-r-dependencies@v2`.
2. Use `RSPM` (RStudio Package Manager) for faster package installation on Linux.
3. Set `R_REMOTES_NO_ERRORS_FROM_WARNINGS: true` to be strict.
4. Use `fail-fast: false` in test matrices so one platform doesn't cancel others.
5. For packages with compiled code, test on ubuntu, macOS, and Windows.
6. Use `actions/checkout@v4` (latest v4).
7. Cache R packages with `r-lib/actions/setup-r-dependencies@v2` (handles caching internally).
8. pkgdown should deploy only on push to main/master, not on PRs.
9. Coverage should be calculated on ubuntu-latest with R release.
10. Never hardcode tokens or secrets in workflow files.
