---
name: r-pkg-release
version: 1.0.0
context-mode: Fork
description: "Execute a full R package release: bump version with usethis, run all checks, update NEWS.md, create a git tag, and prepare for CRAN submission or GitHub release"
trigger: auto
trigger-patterns:
  - "release *"
  - "version bump *"
  - "CRAN release *"
  - "package release *"
  - "publish package *"
argument-hint: "--bump patch|minor|major [--message <release msg>] [--dry-run true|false] [--push true|false]"
parameters:
  bump:
    type: String
    required: true
    enum: ["patch", "minor", "major", "dev"]
    hint: "SemVer bump type: patch (0.0.x), minor (0.x.0), major (x.0.0), dev (add .9000)"
  message:
    type: String
    required: false
    hint: "Override the generated commit message subject line"
  dry-run:
    type: Boolean
    required: false
    default: false
    hint: "Run all checks but do not commit, tag, or push"
  push:
    type: Boolean
    required: false
    default: false
    hint: "Push to remote after tagging (default: false for safety)"
  cran:
    type: Boolean
    required: false
    default: false
    hint: "Also prepare for CRAN submission (build tar.gz, check URLs, etc.)"
steps:
  - id: pre-flight
    inline-prompt: |
      Run pre-release safety checks:

      1. Verify we are in an R package directory (DESCRIPTION exists).
      2. Run: `git status --porcelain`: the working tree MUST be clean.
         If dirty, abort and tell the user to commit or stash changes.
      3. Run: `git branch --show-current`: warn if not on main/master.
      4. Read current version from DESCRIPTION: `desc::desc_get_version()`
      5. Read current NEWS.md if it exists.
      6. Report: package name, current version, branch, git status.

      Abort if the working tree is not clean.
    output: preflight

  - id: determine-version
    requires: [pre-flight]
    inline-prompt: |
      Calculate the new version number.

      Current version from DESCRIPTION: extract from {{state.preflight}}
      Bump type: {{params.bump}}

      Rules:
      - patch: increment the patch digit (1.2.3 → 1.2.4)
      - minor: increment minor, reset patch (1.2.3 → 1.3.0)
      - major: increment major, reset minor and patch (1.2.3 → 2.0.0)
      - dev: append .9000 for dev version (1.2.3 → 1.2.3.9000)

      Also determine the git tag:
      - For release versions: v<version> (e.g., v1.3.0)
      - For dev versions: no tag

      Report: old version → new version, tag (if any).
    gate: Confirm
    output: version_info

  - id: update-news
    requires: [determine-version]
    inline-prompt: |
      Update NEWS.md with the new version.

      New version: {{state.version_info}}

      1. Read current NEWS.md (create it if it doesn't exist).
      2. Read the git log since the last tag:
         Run: `git log $(git describe --tags --abbrev=0 2>/dev/null || echo "")..HEAD --oneline --no-merges`
      3. Categorize commits as:
         - New features (feat:)
         - Bug fixes (fix:)
         - Documentation (docs:)
         - Internal (chore:, refactor:, style:, test:)
         - Breaking changes (commits with BREAKING CHANGE in body)
      4. Prepend a new section to NEWS.md:
         ```
         # {{params.name}} <new-version>

         ## New Features
         - ...

         ## Bug Fixes
         - ...

         ## Breaking Changes
         - (if any)
         ```
      5. If NEWS.md is empty, create it with proper header.

      If dry-run mode, show the proposed NEWS.md entry but do not write.
      Report: the NEWS.md entry.
    gate: Review
    output: news_entry

  - id: update-version
    requires: [update-news]
    inline-prompt: |
      Update the package version in DESCRIPTION:

      1. Parse the new version from {{state.version_info}}.
      2. Use: `desc::desc_set_version("<new-version>")` to update DESCRIPTION.
      3. Verify the version was updated correctly.
      4. Do NOT commit yet.

      Report: version updated.
    output: version_updated

  - id: run-checks
    requires: [update-version]
    inline-prompt: |
      Run the full quality gate. Run the r-pkg-check playbook:
      `/run_playbook r-pkg-check --as-cran true`

      This will execute comprehensive checks including documenting, linting,
      testing, coverage analysis, R CMD check with --as-cran, URL checks,
      spell checks, and pkgdown validation.

      Alternatively, run these checks manually:
      1. `devtools::document()`: regenerate docs
      2. `devtools::test()`: run all tests
      3. `devtools::check(args = c("--as-cran", "--no-manual"))`: full check

      If any check fails:
      - Report the failure
      - If dry-run, list it and continue
      - If not dry-run, abort and tell the user to fix issues first

      Report: check results summary.
    gate: Review
    output: check_summary

  - id: build-readme
    requires: [run-checks]
    inline-prompt: |
      Build/refresh the README:

      1. If `README.Rmd` exists, run: `devtools::build_readme()`
      2. Verify `README.md` was generated/updated.
      3. Report: README built.
    output: readme_status

  - id: check-cran-readiness
    requires: [build-readme]
    inline-prompt: |
      Check CRAN submission readiness:

      1. Run: `rhub::check_for_cran()` to validate the package against CRAN policies.
      2. Run: `urlchecker::url_check()` to detect any broken URLs in docs.
      3. Optionally, run: `pkgcheck::pkgcheck()` for rOpenSci pre-submission check.
      4. Create a reproducible dependency lockfile:
         Run: `pak::lockfile_create("pkg.lock")` for production reproducibility.
      5. Report: CRAN readiness results, URL check status, lockfile created.
    output: cran_readiness

  - id: build-pkgdown
    requires: [check-cran-readiness]
    inline-prompt: |
      Build pkgdown site before tagging:

      1. If `_pkgdown.yml` exists, run: `pkgdown::build_site()`
      2. Verify the `docs/` directory is up-to-date.
      3. Stage pkgdown docs: `git add docs/` if changed.
      4. Report: pkgdown site built and staged.

      If no pkgdown config exists, skip and report: no pkgdown site.
    output: pkgdown_status

  - id: commit-release
    requires: [build-pkgdown]
    inline-prompt: |
      Commit the release changes.

      Files changed: DESCRIPTION, NEWS.md, README.md, possibly man/ files.

      1. Run: `git status` to see all changed files.
      2. Stage the changes: `git add DESCRIPTION NEWS.md README.md`
      3. Also stage any updated documentation: `git add man/` if changed.
      4. Commit message: Use the user-provided message ({{params.message}}) if set,
         otherwise "chore: bump version to <new-version>".

      If dry-run mode, show the diff and proposed commit message but don't commit.
      Report: commit hash (if created) or proposed commit.
    gate: Approve
    output: release_commit

  - id: tag-release
    requires: [commit-release]
    inline-prompt: |
      Create the git tag for the release.

      Tag from {{state.version_info}}.

      1. Create an annotated tag: `git tag -a <tag> -m "Release <tag>"`
       # Consider `git tag -s <tag>` for GPG-signed tags
      2. Verify: `git tag -l --format='%(refname:short) %(taggerdate:short)'`

      If this is a dev version (params.bump == "dev"), skip tagging.
      If dry-run mode, show the proposed tag but don't create it.

      Report: tag created or skipped.
    gate: Approve
    output: tag_info

  - id: push-release
    requires: [tag-release]
    inline-prompt: |
      If the user specified 'push' as true (value: {{params.push}}):
      Push the release to remote:

      1. Run: `git push origin HEAD`: push the commit
      2. Run: `git push origin <tag>`: push the tag
      3. If pushing to main/master, add safety confirmation.

      WARNING: This pushes to the remote repository. Ensure all checks passed.

      If the user specified 'push' as false: Push is disabled.
      Tell the user to manually push with:
      ```
      git push origin HEAD
      git push origin <tag>
      ```

      Report: push status or manual instructions.
    gate: Approve
    output: push_status

  - id: cran-prep
    requires: [tag-release, check-cran-readiness]
    inline-prompt: |
      Prepare for CRAN submission when `cran` is true.

      When cran is true:
      1. Run: `devtools::build()`: create the source tarball (.tar.gz)
      2. Run: `devtools::check_rhub()` or list the interactive URL.
      3. Run: `devtools::check_win_devel()` or list the URL.
      4. Run: `urlchecker::url_check()` to validate all URLs.
      5. Report:
         - Path to .tar.gz file
         - Size of the tarball
         - URL check results
         - Link to rhub builder
         - Link to win-builder
      6. Remind the user about CRAN submission policies:
         - Only submit if all checks pass
         - Include a well-written submission comment
         - Mention any NOTE that is a false positive

      When cran is false, skip CRAN preparation and report: skipped.
    output: cran_status

tags:
  - r
  - package
  - release
  - versioning
  - git

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

You are an R package release manager. Your job is to safely guide a package
through the release process: version bumping, quality checks, changelog
generation, git tagging, and optional CRAN submission.

## Rules

1. NEVER proceed with a dirty working tree. Abort immediately.
2. NEVER skip R CMD check: it must pass with 0 ERRORs and 0 WARNINGs.
3. ALWAYS require user confirmation before git operations (commit, tag, push).
4. NEVER push to remote without explicit user approval (gate: Approve).
5. ALWAYS update NEWS.md before bumping the version.
6. Release commits should use `chore:` conventional commit prefix.
7. Annotated tags only: never lightweight tags.
8. When preparing for CRAN, check all URLs are valid and accessible.
9. The package must build without warnings on R release and R devel.
10. Use `desc::desc_set_version()` not manual DESCRIPTION editing.
