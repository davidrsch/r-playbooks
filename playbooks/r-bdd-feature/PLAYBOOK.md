---
name: r-bdd-feature
version: 1.0.0
context-mode: Fork
description: BDD (Behavior-Driven Development): define a feature with Gherkin scenarios, then implement with testthat
trigger: manual
argument-hint: "--feature <description> [--gherkin true|false]"
parameters:
  feature:
    type: String
    required: true
    hint: "Feature name in Gherkin format: 'As a <role>, I want <goal> so that <benefit>'"
  gherkin:
    type: Boolean
    required: false
    default: false
    hint: "Write Gherkin .feature files (requires testthat + behaviour package)"
  scenarios:
    type: Array
    required: false
    default: []
    hint: "Comma-separated list of scenario names to implement"
steps:
  - id: define-feature
    inline-prompt: |
      Define the feature using structured specification.

      Feature: {{params.feature}}

      1. Break down the feature into user stories:
         ```
         Feature: <feature name>
           As a <role>
           I want <goal>
           So that <benefit>
         ```
      2. Identify acceptance criteria:
         - What must be true for this feature to be "done"?
         - List 3-5 specific, testable criteria.
      3. Define scenarios for each acceptance criterion:
         ```
         Scenario: <scenario name>
           Given <precondition>
           When <action>
           Then <expected outcome>
         ```

      Output the feature specification in a structured format.
      If scenarios were provided ({{params.scenarios}}), include those.
    gate: Confirm
    output: feature_spec

  - id: write-gherkin
    requires: [define-feature]
    inline-prompt: |
      If the user specified 'gherkin' as true (value: {{params.gherkin}}):
      Write Gherkin .feature files.

      Feature spec: {{state.feature_spec}}

      1. Create `tests/features/<feature-slug>.feature`:
         ```gherkin
         Feature: <feature name>
           As a <role>
           I want <goal>
           So that <benefit>

           Scenario: <scenario 1>
             Given <precondition>
             When <action>
             Then <expected outcome>

           Scenario: <scenario 2>
             Given <precondition>
             When <action>
             Then <expected outcome>
         ```
      2. Create step definitions in `tests/testthat/test-bdd-<feature-slug>.R`.
      3. Use testthat's `describe()` and `it()` (from testthat 3e) to structure
         BDD-style tests even without a Gherkin parser.

      Report: .feature file and step definitions created.

      If the user specified 'gherkin' as false: Write BDD-style tests using
      testthat's `describe()`/`it()`:

      Feature spec: {{state.feature_spec}}

      Create `tests/testthat/test-bdd-<feature-slug>.R`:
      ```r
      describe("<feature name>", {
        it("should <acceptance criterion 1>", {
          # Given
          input <- ...
          # When
          result <- <function>(input)
          # Then
          expect_equal(result, ...)
        })

        it("should <acceptance criterion 2>", {
          # Given
          # When
          # Then
        })
      })
      ```

      Report: BDD test file created with scenarios.
    gate: Review
    output: bdd_tests

  - id: implement-feature
    requires: [write-gherkin]
    inline-prompt: |
      Implement the feature to pass the BDD scenarios.

      Feature spec: {{state.feature_spec}}
      Tests: {{state.bdd_tests}}

      1. For each scenario, implement the code needed.
      2. Start with the simplest (highest-priority) scenario.
      3. After each scenario, run the corresponding test.
      4. When all scenarios pass, run the full test suite.
      5. Implement in this order:
         - Functions that don't exist yet
         - Logic to make "Given" preconditions true
         - Logic for "When" actions
         - Logic for "Then" assertions to pass
      6. Report for each scenario:
         ```
         ✅ Scenario: <name>: PASSING
            Implementation: <what was added/modified>
         ```
      7. Final report: M/N scenarios passing.

      After all scenarios pass:
      - Add roxygen2 documentation
      - Run: `devtools::document()`
      - Run: `devtools::test()` (full suite)
    gate: Review
    output: implementation

  - id: verify-acceptance
    requires: [implement-feature]
    inline-prompt: |
      Verify all acceptance criteria are met.

      1. Re-read the feature specification: {{state.feature_spec}}
      2. For each acceptance criterion, confirm it is implemented and tested.
      3. Run full quality checks:
         - `devtools::test()`: all tests
         - `devtools::check(args = c("--as-cran", "--no-manual"))`: R CMD check
         - `lintr::lint_package()`: style (if configured)
      4. Generate acceptance report:
         ```
         ✅ FEATURE ACCEPTANCE REPORT:
         Feature: <name>
         Scenarios: <M/N> passing
         Acceptance Criteria:
           ✅ Criterion 1
           ✅ Criterion 2
           ...
         Quality:
           🧪 Tests: <M>/<N> passing
           📦 R CMD check: <status>
           📝 Lint: <status>
         ```

      If any criterion is NOT met, go back to implementation.
    gate: Review
    output: acceptance_report

tags:
  - r
  - bdd
  - testing
  - methodology
  - specification

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are an R developer practicing Behavior-Driven Development (BDD).
You translate user stories into executable specifications using Gherkin
syntax and testthat-based step definitions.

## BDD Rules

1. **SPECIFICATION FIRST**: Define acceptance criteria before writing code.
2. **UBIQUITOUS LANGUAGE**: Use the same terms in specs, tests, and code.
3. **ONE SCENARIO AT A TIME**: Implement and verify each scenario independently.
4. **GIVEN-WHEN-THEN**: Every scenario follows this structure:
   - **Given**: The preconditions / setup
   - **When**: The action / trigger
   - **Then**: The expected outcome / assertion
5. **STAKEHOLDER READABLE**: Scenarios should be readable by non-programmers.
6. **TEST THE BEHAVIOR, NOT THE CODE**: Scenarios describe WHAT, not HOW.

## R-Specific BDD Practices

- Use `describe()` and `it()` from testthat 3e for BDD-style test organization.
- Use `withr::local_*()` helpers or `testthat::local_mocked_bindings()` for Given preconditions instead of `setup()`/`teardown()`.
- Keep scenarios at the function/feature level, not at the code level.
- Use snapshot tests (`expect_snapshot()`) wrapped in `local_reproducible_output()` for complex outputs.
- Use `skip_on_ci()` or `skip_on_cran()` for scenarios that require specific environments
  (e.g., local database, browser automation, specific OS features).
