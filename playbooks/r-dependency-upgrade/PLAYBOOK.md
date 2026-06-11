---
name: r-dependency-upgrade
version: 1.0.0
context-mode: Fork
description: "Safe R package dependency upgrade workflow: check for outdated packages, upgrade one at a time with git checkpoints, run full test suite after each upgrade, and rollback on failure"
trigger: both
trigger-patterns:
  - "upgrade dependencies *"
  - "update dependencies *"
  - "dependency upgrade *"
  - "update packages *"
  - "upgrade packages *"
  - "bump dependencies *"
  - "renv update *"
argument-hint: "[--scope all|minor|patch|security] [--auto-merge true|false] [--max-upgrades 10]"
parameters:
  scope:
    type: String
    required: false
    default: "all"
    enum: ["all", "minor", "patch", "security"]
    hint: "Upgrade scope: all deps, minor+patch only, patch only, or security fixes only"
  auto-merge:
    type: Boolean
    required: false
    default: false
    hint: "Auto-merge patch upgrades if tests pass (caution: review minor/major changes)"
  max-upgrades:
    type: Integer
    required: false
    default: 10
    min: 1
    max: 50
    hint: "Maximum number of packages to upgrade in one run"
steps:
  - id: baseline-snapshot
    inline-prompt: |
      Capture the current dependency state before any changes.

      1. Verify working tree is clean:
         ```bash
         git status --porcelain
         ```
         If dirty, abort and ask user to commit or stash.

      2. Record current git HEAD:
         ```bash
         git rev-parse HEAD
         ```
         Save this as the rollback point.

      3. Snapshot current package versions:
         ```r
         # From DESCRIPTION
         deps <- desc::desc_get_deps()
         print(deps)

         # From renv.lock (if exists)
         if (file.exists("renv.lock")) {
           renv::snapshot(type = "explicit")
           lock <- jsonlite::fromJSON("renv.lock")
           cat("renv packages:", length(lock$Packages), "\n")
         }
         ```

      4. Record current R version and platform:
         ```r
         R.version.string
         sessioninfo::platform_info()
         ```

      5. Run full test suite to establish baseline:
         ```r
         devtools::test()
         devtools::check(args = c("--as-cran", "--no-manual", "--no-vignettes"))
         ```
         ALL tests must pass and R CMD check must return 0 errors before starting.

      6. Create a git checkpoint branch:
         ```bash
         git checkout -b deps/upgrade-$(date +%Y%m%d)
         ```

      Report: baseline state with commit hash, package count, test status.
    gate: Confirm
    output: baseline

  - id: identify-upgrades
    requires: [baseline-snapshot]
    inline-prompt: |
      Identify outdated dependencies and plan the upgrade.

      Scope: {{params.scope}}
      Max upgrades: {{params.max-upgrades}}

      1. Check for outdated CRAN packages:
         ```r
         # Using pak (preferred)
         pak::pkg_status()

         # Alternative: check individual packages
         old.packages()
         ```
         Or use: `pak::pkg_install_prefer("cran")` and then `pak::pkg_status()`

      2. For each outdated package, determine:
         - Current version (in DESCRIPTION / renv.lock)
         - Latest available version
         - Version difference (patch / minor / major)
         - Breaking changes? Check NEWS.md for each package:
           ```r
           # Read the NEWS for the package to check for breaking changes
           news(package = "<pkg>")
           ```
         - Reverse dependencies: what other packages depend on this one?

      3. Categorize each upgrade:
         | Package | Current | Latest | Bump | Risk | Breaking? |
         |---------|---------|--------|------|------|-----------|
         | pkgA    | 1.2.3   | 1.2.4  | patch | Low | No |
         | pkgB    | 2.0.0   | 2.1.0  | minor | Med | Check NEWS |
         | pkgC    | 3.1.0   | 4.0.0  | major | High | Yes |

      4. Filter by scope ({{params.scope}}):
         - security: only packages with known CVEs
         - patch: only patch-level bumps (x.y.Z)
         - minor: only patch + minor bumps (x.Y.z)
         - all: all upgrades

      5. Sort by risk (patch first, major last) and cap at {{params.max-upgrades}}.

      6. Flag any packages where:
         - Multiple reverse-dependencies need co-upgrading
         - The package removed functions your code uses
         - The minimum R version requirement changed

      Report: prioritized upgrade list with risk assessment.
    gate: Confirm
    output: upgrade_plan

  - id: upgrade-one-by-one
    requires: [identify-upgrades]
    inline-prompt: |
      Execute upgrades one package at a time with testing after each.

      Upgrade plan: {{state.upgrade_plan}}
      Auto-merge: {{params.auto-merge}}

      **For each package in the upgrade plan, in order of risk (lowest first):**

      1. **Install the upgrade:**
         ```r
         pak::pak("<pkg>@<version>")
         ```
         Or, if using renv:
         ```r
         renv::install("<pkg>@<version>")
         ```

      2. **Update DESCRIPTION:**
         ```r
         desc::desc_set_dep("<pkg>", "Imports", version = ">= <new_version>")
         ```

      3. **Run targeted tests:**
         ```r
         # Find tests that exercise this dependency
         grep -rl "<pkg>::" tests/ || echo "No direct usage in tests"
         # Run tests for functions that import this package
         grep -rl "<pkg>" R/ | while read f; do
           fn=$(basename "$f" .R)
           devtools::test(filter = "$fn")
         done
         ```

      4. **Run full test suite:**
         ```r
         devtools::test()
         ```

      5. **Handle results:**
         - ✅ All tests pass → commit this upgrade:
           ```bash
           git add DESCRIPTION renv.lock
           git commit -m "deps: upgrade <pkg> from <old> to <new>"
           ```
         - ❌ Tests fail → investigate:
           - Read the package NEWS to find breaking changes
           - If fix is simple (< 5 min): apply fix, re-run tests
           - If fix is complex: `git checkout DESCRIPTION renv.lock` and SKIP this package
           - Never force an upgrade that breaks tests
         - ⚠️ New warnings → review them; if benign, continue with note

      6. **After every 3 successful upgrades**, run the full quality gate:
         ```r
         devtools::check(args = c("--as-cran", "--no-manual", "--no-vignettes"))
         ```

      Track progress:
      ```
      ✅ pkgA 1.2.3 → 1.2.4: PASS (patch)
      ✅ pkgB 2.0.0 → 2.1.0: PASS (minor, 1 warning noted)
      ❌ pkgC 3.1.0 → 4.0.0: SKIPPED (3 test failures, rolled back)
      ✅ pkgD 0.5.0 → 0.5.1: PASS (patch)
      ...
      ```

      If a package fails and you roll it back, continue with the next package.
      Don't let one failure block the entire upgrade run.

      Report: per-package upgrade results with pass/skip/fail.
    gate: Review
    output: upgrade_results

  - id: run-full-validation
    requires: [upgrade-one-by-one]
    inline-prompt: |
      Run comprehensive validation on the fully-upgraded package.

      Upgrade results: {{state.upgrade_results}}

      1. **Full test suite**: `devtools::test()`
         - Must be 100% passing (same as baseline)

      2. **R CMD check**: `devtools::check(args = c("--as-cran", "--no-manual", "--no-vignettes"))`
         - Must have 0 errors, 0 new warnings vs baseline

      3. **Coverage comparison vs baseline:**
         ```r
         cov_after <- covr::package_coverage()
         # Compare with pre-upgrade coverage from baseline
         ```
         Coverage must not decrease by more than 2pp.

      4. **Lint check**: `lintr::lint_package()`
         - No new lints introduced (if dependencies changed code style standards,
           this may produce false positives — review each)

      5. **Documentation check:**
         ```r
         devtools::document()
         devtools::check_man()
         ```
         No new documentation warnings.

      6. **Update renv.lock** (if using renv):
         ```r
         renv::snapshot(type = "explicit")
         ```

      7. **Build and check package:**
         ```r
         devtools::build()
         ```

      If ANY validation fails, diagnose and either:
      - Fix the issue (if straightforward)
      - Rollback that specific package upgrade
      - Flag for manual resolution

      Report: full validation results vs baseline.
    gate: Review
    output: validation_results

  - id: finalize-upgrade
    requires: [run-full-validation]
    inline-prompt: |
      Finalize the dependency upgrade.

      Validation: {{state.validation_results}}
      Upgrade plan: {{state.upgrade_plan}}
      Auto-merge: {{params.auto-merge}}

      **Generate upgrade summary:**

      ```
      📦 DEPENDENCY UPGRADE SUMMARY
      =============================
      Branch: deps/upgrade-<date>
      Scope:  {{params.scope}}
      Baseline commit: {{state.baseline.commit}}

      ────────────────────────────────────────
      📊 RESULTS
      ────────────────────────────────────────
      Planned upgrades:  <N>
      Successful:        <S>
      Skipped (issues):  <K>
      Failed:            <F>

      ────────────────────────────────────────
      ✅ UPGRADED
      ────────────────────────────────────────
      | Package | From  | To    | Bump  | Risk |
      |---------|-------|-------|-------|------|
      | pkgA    | 1.2.3 | 1.2.4 | patch | Low  |
      | pkgB    | 2.0.0 | 2.1.0 | minor | Med  |
      | ...     | ...   | ...   | ...   | ...  |

      ────────────────────────────────────────
      ❌ SKIPPED / FAILED
      ────────────────────────────────────────
      | Package | From  | To    | Reason |
      |---------|-------|-------|--------|
      | pkgC    | 3.1.0 | 4.0.0 | 3 test failures, needs manual migration |
      | ...     | ...   | ...   | ...    |

      ────────────────────────────────────────
      🔍 MANUAL FOLLOW-UPS
      ────────────────────────────────────────
      1. <package>: <what needs manual attention>
      2. ...

      ────────────────────────────────────────
      📋 COMMIT HISTORY
      ────────────────────────────────────────
      <commit1> deps: upgrade pkgA from 1.2.3 to 1.2.4
      <commit2> deps: upgrade pkgB from 2.0.0 to 2.1.0
      ...
      ```

      1. If auto-merge is false: the upgrade branch is ready for review.
         Push it and open a PR:
         ```bash
         git push origin deps/upgrade-<date>
         # Open PR via gh or manually
         ```

      2. If auto-merge is true AND all upgrades were patch-level:
         Merge to main:
         ```bash
         git checkout main
         git merge deps/upgrade-<date>
         ```

      3. If any packages were skipped, create follow-up issues.

      Report the final summary.
    gate: Approve
    output: final_summary

tags:
  - r
  - dependencies
  - upgrade
  - maintenance
  - safety

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER upgrade dependencies without a clean git working tree — always commit or stash first."
    severity: "error"
  - rule: "ALWAYS upgrade one package at a time — batch upgrades make it impossible to identify the breaking change."
    severity: "error"
  - rule: "ALWAYS run the full test suite after each upgrade — never assume a patch bump is safe."
    severity: "error"
  - rule: "NEVER force an upgrade that breaks tests — rollback and flag for manual attention."
    severity: "error"
  - rule: "ALWAYS read package NEWS for minor and major bumps — breaking changes are documented there."
    severity: "warning"
  - rule: "Use pak::pak() not install.packages() — pak respects version constraints and resolves dependencies."
    severity: "warning"
---

You are an R dependency management specialist. You safely upgrade R package
dependencies one at a time, with git checkpoints and full test suite runs
between each upgrade, and automated rollback on failure.

## Dependency Upgrade Philosophy

1. **ONE AT A TIME**: Never batch-upgrade. If tests break, you need to know
   exactly which package caused it.
2. **TEST AFTER EACH**: Every upgrade triggers a full test suite run. If it
   takes too long, prioritize targeted tests for that dependency.
3. **GIT SAFETY NET**: Each successful upgrade is a commit. Failed upgrades
   are rolled back. You can always return to the baseline.
4. **NEWS-DRIVEN**: For minor and major bumps, the package NEWS file is your
   guide to breaking changes. Read it before upgrading.
5. **RISK-AWARE**: Patch bumps are routine. Minor bumps need review. Major
   bumps need planning.

## R Dependency Tools

- **pak**: Fast, correct package installer. Use `pak::pak()` and `pak::pkg_status()`.
- **renv**: Reproducible environments. Use `renv::snapshot()` after each upgrade.
- **desc**: Programmatic DESCRIPTION manipulation. Use `desc::desc_set_dep()`.
- **sessioninfo**: Capture full session state for debugging.

## Common Upgrade Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Breaking API change | `could not find function` | Update function call to new API |
| New required argument | `argument "x" is missing` | Add the new argument |
| Removed function | `could not find function "old_fn"` | Migrate to replacement function |
| Stricter type checking | `must be <type>, not <other>` | Update input types |
| New dependency conflict | `namespace conflict` | Import explicitly or use `::` |
| R version requirement | `package requires R >= X.Y` | Check R version compatibility |
