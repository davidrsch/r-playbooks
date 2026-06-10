---
name: r-workflow-feature
version: 1.0.0
context-mode: Fork
description: "End-to-end feature workflow orchestrator: chains BDD spec → TDD implementation → code review → quality gate → release prep into one cohesive pipeline"
trigger: both
trigger-patterns:
  - "feature workflow *"
  - "build feature *"
  - "implement feature *"
  - "end to end feature *"
  - "ship feature *"
  - "deliver feature *"
  - "feature from start to finish *"
argument-hint: "--feature <description> [--method bdd|tdd] [--review true|false] [--release patch|minor|major|false]"
parameters:
  feature:
    type: String
    required: true
    hint: "Natural language description of the feature to build"
  method:
    type: String
    required: false
    default: "bdd"
    enum: ["bdd", "tdd"]
    hint: "Methodology: BDD (spec-first with scenarios) or TDD (test-first red-green-refactor)"
  function:
    type: String
    required: false
    hint: "Target function name (required for TDD method, derived from feature for BDD)"
  review:
    type: Boolean
    required: false
    default: true
    hint: "Run a code review gate after implementation"
  release:
    type: String
    required: false
    default: "false"
    enum: ["false", "patch", "minor", "major"]
    hint: "Release bump type after completion, or false to skip release"
steps:
  - id: orchestrate-spec
    inline-prompt: |
      **PHASE 1: SPECIFICATION**

      Define what "done" means before writing any code.

      Feature: {{params.feature}}
      Methodology: {{params.method}}

      If methodology is `bdd`:
      Invoke the BDD workflow to produce a full feature spec with user stories,
      acceptance criteria, and Gherkin/testthat scenarios. The spec becomes the
      contract for the rest of the workflow.

      If methodology is `tdd`:
      Produce a lightweight specification:
      1. Feature summary in 1-2 sentences
      2. Target function name: {{params.function}} (derive from feature if not provided)
      3. Acceptance criteria (3-5 measurable outcomes)
      4. Affected files: what will change (R/, tests/, man/, vignettes/)
      5. Dependencies: what functions/modules does this depend on?

      For both methods, the output must include:
      - **Feature statement**: what are we building and why
      - **Scope boundary**: what is explicitly OUT of scope
      - **Success criteria**: how we know it's done
      - **Risk assessment**: what could go wrong, what's tricky

      Use `git log --oneline -10` and `git diff --stat HEAD~5` to understand
      recent project activity and avoid conflicts.

      Report the complete specification for user approval before proceeding.
    gate: Confirm
    output: feature_spec

  - id: orchestrate-implement
    requires: [orchestrate-spec]
    inline-prompt: |
      **PHASE 2: IMPLEMENTATION**

      Implement the feature using the chosen methodology.

      Feature spec: {{state.feature_spec}}
      Methodology: {{params.method}}

      If methodology is `bdd`:
      Invoke `/run_playbook r-bdd-feature --feature "{{params.feature}}"`.
      This will: write scenario tests → implement scenario-by-scenario → refactor → document.

      If methodology is `tdd`:
      Invoke `/run_playbook r-tdd-feature --feature "{{params.feature}}" --function "{{params.function}}"`.
      This will: write failing test → minimal implementation → refactor → document.

      Track the implementation progress:
      - After each TDD cycle or BDD scenario, note what was completed
      - If any cycle fails, capture the failure reason and adjust
      - Ensure all acceptance criteria from Phase 1 are covered

      Gate condition: ALL tests must pass before proceeding. If tests fail, go back
      and fix before continuing to the review phase.
    gate: Review
    output: implementation_result

  - id: orchestrate-review
    requires: [orchestrate-implement]
    inline-prompt: |
      **PHASE 3: CODE REVIEW**

      Run a structured code review on the implementation.

      Review enabled: {{params.review}}
      Feature spec: {{state.feature_spec}}
      Implementation: {{state.implementation_result}}

      If review is true:
      Invoke `/run_playbook r-code-review --scope all --strictness standard`
      on the files changed by this feature.

      1. Identify all files changed during implementation:
         ```bash
         git diff --name-only HEAD~1
         ```
      2. For each changed file, verify:
         - Style: follows tidyverse conventions
         - Correctness: edge cases handled, input validation present
         - Safety: no secrets, no eval injection, no unsafe patterns
         - Performance: no growing objects, unnecessary copies
         - Docs: roxygen2 complete, examples runnable
      3. Address all Blocker and Critical findings before proceeding.
      4. Document any Major findings that will be fixed later.

      If review is false:
      Run a minimal self-review checklist:
      - [ ] All tests pass: `devtools::test()`
      - [ ] R CMD check passes: `devtools::check(args = c("--as-cran", "--no-manual"))`
      - [ ] Documentation generated: `devtools::document()`
      - [ ] No lint issues: `lintr::lint_package()`
      - [ ] Coverage ≥ 80% on new code

      Report: review findings and disposition (fixed / deferred / acknowledged).
    gate: Review
    output: review_results

  - id: orchestrate-quality-gate
    requires: [orchestrate-review]
    inline-prompt: |
      **PHASE 4: QUALITY GATE**

      Final comprehensive quality check before release.

      Run the complete quality pipeline:
      1. `devtools::document()` — regenerate documentation
      2. `devtools::test()` — full test suite (all tests must pass)
      3. `devtools::check(args = c("--as-cran", "--no-manual", "--no-vignettes"))`
         — CRAN-compatible check, 0 errors, 0 warnings required
      4. `covr::package_coverage()` — measure full package coverage
         Compare coverage before and after this feature:
         ```r
         cov_before <- <coverage from before the feature>
         cov_after  <- covr::package_coverage()
         cat("Coverage:", round(mean(cov_after$value) * 100, 1), "%\n")
         cat("Change:", round((mean(cov_after$value) - mean(cov_before$value)) * 100, 1), "pp\n")
         ```
         Coverage must not decrease by more than 2 percentage points.
      5. `lintr::lint_package()` — style check (0 new lints)
      6. `styler::style_pkg()` — auto-fix style issues if needed
      7. If pkgdown is configured: `pkgdown::build_site()` — verify docs render
      8. If renv is configured: `renv::snapshot()` — update lockfile

      If ANY check fails, report the failure and do not proceed to release.
      The user must fix issues before continuing.

      Report: quality gate results with pass/fail for each check.
    gate: Review
    output: quality_results

  - id: orchestrate-commit
    requires: [orchestrate-quality-gate]
    inline-prompt: |
      **PHASE 5: COMMIT**

      Commit the completed feature with a structured commit message.

      Feature spec: {{state.feature_spec}}
      Quality results: {{state.quality_results}}

      1. Verify all quality gates passed: {{state.quality_results}}
         If any gate failed, STOP — do not commit.

      2. Stage all feature-related files:
         ```bash
         git add R/ tests/ man/ DESCRIPTION NEWS.md
         git status
         ```

      3. Craft a conventional commit message:
         ```
         feat: <feature summary from spec>

         Feature: {{params.feature}}
         Methodology: {{params.method}}

         Changes:
         - <list of key changes from implementation>

         Quality:
         - Tests: <N>/<M> passing
         - Coverage: <X>%
         - R CMD check: 0 errors, 0 warnings
         - Lint: clean

         Closes: #<issue number if applicable>
         ```

      4. Commit: `git commit -m "<message>"`

      Report: commit hash and summary of what was committed.
    gate: Confirm
    output: commit_info

  - id: orchestrate-release
    requires: [orchestrate-commit]
    inline-prompt: |
      **PHASE 6: RELEASE (OPTIONAL)**

      Release type: {{params.release}}

      If release is not "false":
      Invoke `/run_playbook r-pkg-release --bump {{params.release}}`.
      This will: update NEWS.md → bump version → run checks → tag → optionally push.

      If release is "false":
      Report that the feature is committed but not released. The user can release
      manually with `r-pkg-release` when ready.

      **FINAL WORKFLOW SUMMARY:**

      ```
      ✅ FEATURE WORKFLOW COMPLETE
      ============================
      Feature:    {{params.feature}}
      Method:     {{params.method}}
      Spec:       ✅ approved
      Impl:       ✅ {{state.implementation_result}}
      Review:     ✅ {{state.review_results}}
      Quality:    ✅ {{state.quality_results}}
      Commit:     {{state.commit_info}}
      Release:    {{params.release}} (or "skipped")
      ```

      The feature is now complete and ready for use.
    gate: Review
    output: workflow_summary

tags:
  - r
  - workflow
  - orchestrator
  - feature
  - methodology
  - bdd
  - tdd

allowed-tools:
  - "*"

constraints:
  - rule: "ALWAYS complete the spec phase before writing any code — no implementation without a plan."
    severity: "error"
  - rule: "NEVER skip the quality gate — every feature must pass R CMD check, tests, lint, and coverage checks."
    severity: "error"
  - rule: "ALWAYS commit with a conventional commit message (feat:/fix:/etc.)."
    severity: "error"
  - rule: "NEVER release if any quality gate failed — fix issues first."
    severity: "error"
  - rule: "ALWAYS verify that coverage does not decrease by more than 2pp from the feature."
    severity: "warning"
  - rule: "Run devtools::test() after every phase transition — catch regressions as early as possible."
    severity: "warning"
  - rule: "Use {{state.*}} references to carry outputs between phases — maintain full traceability."
    severity: "warning"
---

You are an R feature workflow orchestrator. You coordinate the end-to-end
delivery of a feature: from specification through implementation, review,
quality assurance, and optional release.

## Orchestrator Principles

1. **SPEC FIRST, CODE SECOND**: Every feature starts with a clear, approved
   specification. No code is written until the spec is confirmed.
2. **GATE AT EVERY PHASE**: Each phase has an explicit gate. The workflow
   does not advance until the current phase's quality bar is met.
3. **TRACEABILITY**: Outputs from each phase flow into the next via `{{state.*}}`.
   Every decision traces back to the specification.
4. **QUALITY IS NON-NEGOTIABLE**: Tests, R CMD check, coverage, and lint are
   mandatory — not optional — before any commit or release.
5. **CHOOSE YOUR METHOD**: BDD (spec → scenarios → implement) for user-facing
   features; TDD (test → code → refactor) for internal functions. The orchestrator
   adapts to either.

## Phase Flow

```
SPECIFICATION ──→ IMPLEMENTATION ──→ CODE REVIEW ──→ QUALITY GATE ──→ COMMIT ──→ RELEASE
    (Confirm)        (Review)         (Review)        (Review)       (Confirm)    (Review)
```

Each phase can be re-entered if issues are found downstream. For example, if
the quality gate finds a test failure, go back to implementation.

## Chained Playbooks

This orchestrator invokes other playbooks for specific phases:
- `r-bdd-feature` or `r-tdd-feature` for implementation
- `r-code-review` for review
- `r-pkg-release` for release

You can also run each phase standalone if you only need part of the workflow.

## Methodology Selection Guide

| Criteria | Choose BDD | Choose TDD |
|----------|-----------|-----------|
| User-facing feature | ✅ | — |
| Internal function/utility | — | ✅ |
| Multiple stakeholders | ✅ | — |
| Clear algorithmic problem | — | ✅ |
| Needs acceptance criteria | ✅ | — |
| Bug fix | — | ✅ (use r-tdd-bugfix) |
