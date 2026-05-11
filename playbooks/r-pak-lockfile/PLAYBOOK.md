---
name: r-pak-lockfile
version: 1.0.0
context-mode: Fork
description: Create and use a pak lockfile for reproducible R package installations
trigger: both
trigger-patterns:
  - "pak lockfile *"
  - "create lockfile *"
  - "lockfile *"
  - "pak lock *"
  - "reproducible install *"
  - "freeze dependencies *"
argument-hint: "[--file <lockfile_path>] [--action create|restore|verify] [--ci true|false]"
parameters:
  file:
    type: String
    required: false
    default: "pkg.lock"
    hint: "Path to the lockfile (default: pkg.lock in project root)"
  action:
    type: String
    required: false
    default: "create"
    enum: ["create", "restore", "verify"]
    hint: "Action: create lockfile, restore from lockfile, or verify lockfile freshness"
  ci:
    type: Boolean
    required: false
    default: false
    hint: "Generate GitHub Actions CI integration alongside the lockfile"
steps:
  - id: install-pak
    inline-prompt: |
      Install and verify the pak package manager:

      1. Install pak if not already installed:
         ```r
         install.packages("pak", repos = sprintf(
           "https://r-lib.github.io/p/pak/devel/%s/%s/%s",
           .Platform$pkgType, R.Version()$arch, R.Version()$os
         ))
         ```

      2. Verify installation and check version:
         ```r
         packageVersion("pak")  # should be >= 0.7.0
         library(pak)

         # Verify pak is functional
         pak::pkg_status()
         ```

      3. If using renv, install pak into the project library:
         ```r
         renv::install("pak")
         ```

      4. Report: pak version, installation status, any warnings.
    output: install_status

  - id: create-lockfile
    requires: [install-pak]
    inline-prompt: |
      Create a pak lockfile from the current project dependencies.

      Lockfile path: {{params.file}}

      ## Step 1: Understand current dependencies
      1. Read `DESCRIPTION` to identify all package dependencies (Imports, Suggests, Depends, LinkingTo).
      2. Check for Remotes in DESCRIPTION (non-CRAN packages).
      3. If using renv, run: `renv::status()` to check for consistency.
      4. Report: total number of direct dependencies found.

      ## Step 2: Create the lockfile
      Run:
      ```r
      pak::lockfile_create(
        pkg = ".",
        lockfile = "{{params.file}}",
        upgrade = FALSE,
        dependencies = TRUE
      )
      ```

      This resolves the full dependency tree and records:
      - Every package name and exact version.
      - Repository source (CRAN, BioC, GitHub, local).
      - Package hashes for integrity verification.
      - System requirements (sysreqs).

      ## Step 3: Inspect the lockfile
      Read the generated `{{params.file}}` (it's JSON):
      - Count total packages captured.
      - List any packages from non-CRAN sources.
      - Check for system requirements: `pak::pkg_sysreqs(".")`

      ## Step 4: Visualize the dependency tree
      ```r
      pak::pkg_deps_tree(".")
      ```

      Report:
      - Number of packages locked.
      - Sources represented (CRAN, GitHub, BioC, etc.).
      - System requirements needed.
      - Dependency tree summary.
    gate: Review
    output: lockfile_result

  - id: restore-lockfile
    requires: [create-lockfile]
    inline-prompt: |
      Restore packages from the pak lockfile to reproduce the exact environment.

      Lockfile: {{params.file}}
      Action: {{params.action}}

      If {{params.action}} is "create": Skip restore. Report: lockfile created, ready for restore.
      Proceed to the CI integration step if {{params.ci}} is true.

      If {{params.action}} is "restore" or "verify":

      ## Step 1: Verify lockfile integrity
      ```r
      # Check the lockfile is valid JSON and has expected structure
      lock <- jsonlite::read_json("{{params.file}}")
      cat("Packages locked:", length(lock), "\n")

      # Verify against current DESCRIPTION
      verify_result <- pak::lockfile_verify("{{params.file}}")
      if (!isTRUE(verify_result)) {
        stop("Lockfile verification failed: ", verify_result)
      }
      cat("Lockfile is up to date.\n")
      ```

      ## Step 2: Restore from lockfile
      ```r
      pak::lockfile_install("{{params.file}}")
      ```

      This installs the EXACT versions specified in the lockfile, from the
      original sources, with hash verification.

      ## Step 3: Validate the restore
      ```r
      pak::pkg_status()         # all packages should be current
      pak::lockfile_verify("{{params.file}}")  # should report "up to date"
      ```

      ## Step 4: If using renv
      After restoring with pak, sync renv:
      ```r
      renv::snapshot(type = "explicit")
      renv::status()
      ```

      Report:
      - Number of packages installed.
      - Any version mismatches found.
      - Verify result: up-to-date or discrepancies.
    output: restore_result

  - id: integrate-ci
    requires: [create-lockfile]
    inline-prompt: |
      Set up continuous integration to use the pak lockfile in GitHub Actions.

      CI enabled: {{params.ci}}

      If {{params.ci}} is false: Skip CI integration. Report the manual command:
      ```
      pak::lockfile_install("{{params.file}}")
      ```

      If {{params.ci}} is true:

      ## Step 1: Create or update the GHA workflow
      Create `.github/workflows/R-CMD-check.yaml` (or update existing):

      ```yaml
      on:
        push:
          branches: [main, master]
        pull_request:
          branches: [main, master]
        workflow_dispatch:
        schedule:
          - cron: '0 6 * * 1'  # Weekly on Monday at 6 AM UTC

      name: R-CMD-check

      concurrency:
        group: ${{ '{{' }} github.workflow }}-${{ '{{' }} github.ref }}
        cancel-in-progress: true

      jobs:
        R-CMD-check:
          runs-on: ubuntu-latest
          env:
            GITHUB_PAT: ${{ '{{' }} secrets.GITHUB_TOKEN }}
            R_KEEP_PKG_SOURCE: yes

          steps:
            - uses: actions/checkout@v4

            - uses: r-lib/actions/setup-r@v2
              with:
                use-public-rspm: true

            - uses: r-lib/actions/setup-pak@v2

            - name: Install system dependencies
              run: |
                pak::local_install_dev_deps()
                pak::pkg_sysreqs(".") |>
                  system()
              shell: Rscript {0}

            - name: Restore packages from lockfile
              run: pak::lockfile_install("{{params.file}}")
              shell: Rscript {0}

            - name: Check package
              uses: r-lib/actions/check-r-package@v2
              with:
                upload-snapshots: true
                build_args: 'c("--no-manual", "--compact-vignettes=gs+qpdf")'

            - name: Upload lockfile artifact
              uses: actions/upload-artifact@v4
              with:
                name: lockfile
                path: "{{params.file}}"
      ```

      ## Step 2: Add system dependencies handling
      If the project has system dependencies:
      ```r
      pak::pkg_sysreqs(".")   # list them
      ```
      Add `apt-get install` commands before the R steps if on ubuntu-latest.

      ## Step 3: Lockfile freshness check
      Add a CI step that verifies the lockfile is up to date:
      ```yaml
      - name: Verify lockfile is current
        run: pak::lockfile_verify("{{params.file}}")
        shell: Rscript {0}
      ```

      Report:
      - CI workflow file created/updated.
      - System requirements included.
      - Verify step included.
    gate: Review
    output: ci_setup

tags:
  - r
  - pak
  - lockfile
  - reproducible
  - ci
  - dependencies

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are an R package management specialist, expert in the {pak} package manager
for fast, reproducible R package installation.

## Rules

1. ALWAYS use `pak::lockfile_create()` to create lockfiles — NEVER write them by hand.
2. ALWAYS use `pak::lockfile_install()` to restore — NEVER `install.packages()` for locked deps.
3. ALWAYS include the lockfile in version control (it's JSON, human-readable).
4. ALWAYS run `pak::lockfile_verify()` before committing changes to ensure freshness.
5. PREFER pak over renv for CI because pak resolves and installs faster (parallel downloads).
6. ALWAYS use `r-lib/actions/setup-pak@v2` in GitHub Actions for pak CI integration.
7. ALWAYS run `pak::pkg_sysreqs()` to identify system-level dependencies.
8. NEVER use `remotes::install_deps()` when a pak lockfile exists — use pak instead.
9. Store the lockfile at the project root as `pkg.lock` unless specified otherwise.
10. Use `pak::pkg_deps_tree()` to visualize dependency relationships before locking.
11. For non-CRAN packages, ensure Remotes are in DESCRIPTION so pak can resolve them.
12. Re-create the lockfile after adding/removing/updating any dependency.
