---
name: r-renv-manage
version: 1.0.0
context-mode: Fork
description: "Manage an renv project: snapshot, restore, update packages, clean unused packages, repair broken lockfiles, and upgrade renv itself"
trigger: both
trigger-patterns:
  - "renv *"
  - "lockfile *"
  - "restore packages *"
  - "update renv *"
  - "renv snapshot *"
  - "renv restore *"
  - "dependency lockfile *"
argument-hint: "--action snapshot|restore|update|clean|repair|upgrade [--package <name>] [--confirm true|false]"
parameters:
  action:
    type: String
    required: true
    enum: ["snapshot", "restore", "update", "clean", "repair", "upgrade", "status"]
    hint: "renv operation to perform"
  package:
    type: String
    required: false
    hint: "Specific package name (for update action only)"
  confirm:
    type: Boolean
    required: false
    default: true
    hint: "Require confirmation before making changes to the lockfile"
steps:
  - id: check-status
    inline-prompt: |
      Check the current renv status before any operation.

      Action: {{params.action}}

      ```r
      library(renv)

      # Show current status
      renv::status()
      ```

      This reports:
      - Packages in renv.lock but not installed (out of sync)
      - Installed packages not in renv.lock (unrecorded)
      - Version mismatches between lockfile and installed

      Also check:
      ```r
      renv::diagnostics()  # deeper check: R version, library paths, cache location
      ```

      Report: current sync status and any discrepancies.
    output: current_status

  - id: run-action
    requires: [check-status]
    inline-prompt: |
      Execute the requested renv action.

      Action: {{params.action}}
      Package: {{params.package}}
      Current status: {{state.current_status}}

      **snapshot** — record current installed packages into renv.lock:
      ```r
      renv::snapshot(type = "explicit")  # only packages in DESCRIPTION Imports/Suggests
      # or
      renv::snapshot(type = "all")       # all installed packages
      ```
      Use `type = "explicit"` for package projects; `type = "all"` for scripts/analyses.

      **restore** — install packages to match renv.lock exactly:
      ```r
      renv::restore()
      # Force reinstall even if versions match:
      # renv::restore(rebuild = TRUE)
      ```

      **update** — update a specific package or all packages:
      ```r
      if (nchar("{{params.package}}") > 0) {
        renv::update("{{params.package}}")
      } else {
        renv::update()  # updates all packages; interactive confirmation
      }
      # After updating, snapshot to lock new versions:
      renv::snapshot()
      ```

      **clean** — remove packages installed but not used:
      ```r
      renv::clean(confirm = {{params.confirm}})
      ```

      **repair** — fix broken package installations:
      ```r
      renv::repair()
      # If a package fails to install, try rebuilding from source:
      # renv::install("<package>", rebuild = TRUE)
      ```

      **upgrade** — upgrade renv itself to the latest version:
      ```r
      renv::upgrade()
      # Inspect the new renv bootstrap in .Rprofile after upgrade
      ```

      **status** — report only (already done in check-status):
      Report the output of `renv::status()` with recommendations.

      Report: action completed and lockfile state after.
    gate: Confirm
    output: action_result

  - id: verify-lockfile
    requires: [run-action]
    inline-prompt: |
      Verify the lockfile is in a clean state after the operation.

      Action was: {{params.action}}

      ```r
      # Should report "No issues found" after snapshot/restore/clean
      renv::status()
      ```

      Check:
      1. `renv.lock` reflects the intended package set.
      2. No packages flagged as "not recorded" or "out of sync".
      3. `renv/library/` directory exists with installed packages.
      4. `.Rprofile` contains `source("renv/activate.R")` (renv bootstrap).

      If this was an update, also check that package tests still pass:
      ```r
      devtools::test()  # if in a package
      ```

      For restore after a fresh clone:
      ```r
      renv::status()  # should be clean
      library(<package>)  # verify the package loads
      ```

      Report: final lockfile status — clean or issues remaining.
    output: verification

  - id: commit-lockfile
    requires: [verify-lockfile]
    inline-prompt: |
      Commit the updated renv.lock to version control.

      Only if the action modified the lockfile (snapshot, update, repair, upgrade).

      ```r
      # Check what changed in renv.lock
      system2("git", c("diff", "--stat", "renv.lock"))
      system2("git", c("diff", "renv.lock"))
      ```

      If changes are expected and correct:
      ```bash
      git add renv.lock
      git commit -m "chore: update renv.lock ({{params.action}})"
      ```

      Do NOT commit:
      - `renv/library/` — this is rebuilt from the lockfile
      - `renv/local/` — local package cache
      - `.Rprofile` unless renv changed the bootstrap

      Verify `.gitignore` contains:
      ```
      renv/library/
      renv/local/
      renv/cellar/
      renv/staging/
      renv/sandbox/
      ```

      Report: git commit hash and files changed.
    output: commit_hash

tags:
  - r
  - renv
  - dependencies
  - reproducibility
  - package

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER commit renv/library/ to git — it is rebuilt from renv.lock."
    severity: "error"
  - rule: "ALWAYS run renv::status() before and after any renv operation."
    severity: "warning"
  - rule: "ALWAYS commit renv.lock after snapshot or update — it is the reproducibility contract."
    severity: "error"
  - rule: "Use renv::snapshot(type = 'explicit') for packages — records only DESCRIPTION dependencies."
    severity: "warning"
  - rule: "NEVER run install.packages() in a project using renv — use renv::install()."
    severity: "error"
---

You are an R dependency management specialist using {renv} for reproducible environments.

## Rules

1. `renv.lock` is the source of truth for the project's R package environment.
2. NEVER use `install.packages()` in renv projects — use `renv::install()` so the
   lockfile is updated consistently.
3. `renv/library/` is a build artefact — add it to `.gitignore`, never commit it.
4. After any `renv::update()`, run the full test suite before committing the lockfile.
5. Use `type = "explicit"` for package projects (reads DESCRIPTION) and
   `type = "all"` for analysis scripts.
6. `renv::repair()` rebuilds damaged installations without changing the lockfile.
7. For CI/CD, use `renv::restore()` to reproduce the exact environment from the lockfile.
8. Keep renv itself up to date with `renv::upgrade()` — each version improves resolver accuracy.
