---
name: r-bdd-feature
version: 1.1.0
context-mode: Fork
description: "BDD (Behavior-Driven Development): define a feature with user stories, acceptance criteria, and Gherkin scenarios; then implement scenario-by-scenario with testthat describe()/it() tests. Works for R packages, Shiny apps, Plumber APIs, or any R project"
trigger: auto
trigger-patterns:
  - "bdd *"
  - "behavior driven *"
  - "behaviour driven *"
  - "gherkin *"
  - "feature spec *"
  - "user story *"
  - "acceptance criteria *"
argument-hint: "--feature <description> [--context package|shiny|plumber|script] [--gherkin true|false]"
parameters:
  feature:
    type: String
    required: true
    hint: "Feature name or user story: 'As a <role>, I want <goal> so that <benefit>'"
  context:
    type: String
    required: false
    default: "package"
    enum: ["package", "shiny", "plumber", "script"]
    hint: "Project type — affects which testing tools are used"
  gherkin:
    type: Boolean
    required: false
    default: false
    hint: "Write .feature files in Gherkin syntax (true) or use testthat describe()/it() directly (false)"
  scenarios:
    type: Array
    required: false
    default: []
    hint: "Comma-separated list of scenario names to implement (optional — agent will derive them)"
steps:
  - id: define-feature
    inline-prompt: |
      Define the feature using structured BDD specification.

      Feature: {{params.feature}}
      Provided scenarios: {{params.scenarios}}

      0. Verify the R environment is functional:
         ```r
         stopifnot(
           requireNamespace("devtools", quietly = TRUE),
           requireNamespace("testthat", quietly = TRUE)
         )
         if ({{params.context}} == "package") stopifnot(file.exists("DESCRIPTION"))
         ```

      1. Write the feature statement in user-story format:
         ```
         Feature: <feature name>
           As a <role>
           I want <goal>
           So that <benefit>
         ```

      2. Identify 3–5 concrete acceptance criteria.
         Each criterion must be:
         - Specific and measurable ("calculates the mean of numeric input")
         - Testable at the API/behaviour level
         - Written in business language, not implementation language

      3. For each acceptance criterion, write a Gherkin scenario:
         ```
         Scenario: <concise scenario name>
           Given <precondition / initial state>
           When  <action taken>
           Then  <expected observable outcome>
         ```
         Cover: the happy path, at least one edge case, and at least one error case.

      4. If {{params.scenarios}} were provided, use them as the scenario list.

      5. Identify which functions / modules / endpoints this feature touches:
         - For package context: function names in R/
         - For Shiny context: module IDs, input/output IDs, reactive triggers
         - For Plumber context: endpoint paths and HTTP verbs

      Report: complete feature spec with all scenarios clearly numbered.
    gate: Confirm
    output: feature_spec

  - id: write-scenarios
    requires: [define-feature]
    inline-prompt: |
      Translate the feature spec into executable test scenarios.

      Feature spec: {{state.feature_spec}}
      Context: {{params.context}}
      Gherkin mode: {{params.gherkin}}

      **If gherkin is false (standard testthat — recommended):**

      Create `tests/testthat/test-bdd-<feature-slug>.R` using `describe()`/`it()`:

      ```r
      describe("<Feature name>", {

        # Happy path
        it("should <acceptance criterion 1>", {
          # Given
          <setup code — create objects, mock dependencies>
          # When
          result <- <function_or_action>(<inputs>)
          # Then
          expect_equal(result, <expected_value>)
        })

        # Edge case
        it("should handle <edge case>", {
          # Given
          <edge case setup>
          # When / Then
          expect_equal(<function>(<edge_input>), <expected>)
        })

        # Error case
        it("should signal an error when <bad condition>", {
          expect_error(<function>(<bad_input>), class = "rlang_error")
        })

      })
      ```

      For Shiny context (`{{params.context}} == "shiny"`), use shinytest2:
      ```r
      library(shinytest2)

      describe("<Feature name> — Shiny", {
        it("should <acceptance criterion> when user interacts", {
          app <- AppDriver$new(app_dir = ".", name = "bdd-<feature>")
          app$set_inputs(<input_id> = <value>)
          app$expect_values(output = list(<output_id> = <expected>))
          app$stop()
        })
      })
      ```

      **If gherkin is true (Gherkin .feature files):**

      Create `tests/features/<feature-slug>.feature`:
      ```gherkin
      Feature: <feature name>
        As a <role>
        I want <goal>
        So that <benefit>

        Scenario: <scenario 1 name>
          Given <precondition>
          When  <action>
          Then  <expected outcome>

        Scenario: <scenario 2 name>
          Given <precondition>
          When  <action>
          Then  <expected outcome>
      ```

      Then write the step bindings in `tests/testthat/test-bdd-<feature-slug>.R`
      using `describe()`/`it()` manually mapping each Given/When/Then to R code.

      Run the tests immediately — ALL must FAIL (functions not yet implemented):
      ```r
      devtools::test(filter = "bdd-<feature-slug>")
      ```

      Report: test file created, N scenarios failing (expected at this stage).
    output: bdd_tests

  - id: implement-scenarios
    requires: [write-scenarios]
    inline-prompt: |
      Implement the feature one scenario at a time.

      Feature spec: {{state.feature_spec}}
      BDD tests: {{state.bdd_tests}}
      Context: {{params.context}}

      Work through each scenario in order — happy path first:

      For each scenario:
      1. Run only that scenario's test to confirm it fails:
         ```r
         devtools::test(filter = "bdd-<feature-slug>")
         ```
      2. Write the MINIMUM code to make that scenario pass.
         - Do not implement code for the next scenario yet.
         - For Shiny: add the UI element + server logic for this specific behaviour.
         - For Plumber: add or update the endpoint for this specific route.
      3. Run the scenario test again — it must pass.
      4. Run ALL tests to confirm no regressions:
         ```r
         devtools::test()
         ```
      5. Report:
         ```
         ✅ Scenario: <name>: PASSING
            Code added: <summary of what was implemented>
            Full suite: <N>/<M> passing
         ```

      Repeat for each scenario. Do NOT proceed to the next scenario if any
      previous scenario's test fails.

      After all scenarios pass, report:
      ```
      🟢 ALL SCENARIOS PASSING: <N>/<N>
      Ready for refactoring.
      ```
    gate: Review
    output: implementation

  - id: refactor
    requires: [implement-scenarios]
    inline-prompt: |
      Improve the implementation without changing any observable behaviour.

      Implementation: {{state.implementation}}

      Review the code just written across all scenarios and apply clean-up:

      1. **Remove duplication**: if multiple scenarios share setup logic,
         extract it into a helper function or use `withr::local_*()` fixtures.
      2. **Improve naming**: rename any variables named during rapid implementation
         (`tmp`, `res`, `x1`) to intention-revealing names.
      3. **Simplify conditionals**: replace nested `if/else` with `switch()` or
         early returns where appropriate.
      4. **Extract helpers**: any block > ~10 lines that has a clear single purpose
         should become a named internal function.
      5. **Ensure consistency**: the new code should follow the same style as the
         rest of the project (run `styler::style_file()` on modified files).

      After EACH change, run:
      ```r
      devtools::test(filter = "bdd-<feature-slug>")
      ```
      If any scenario test fails, REVERT the last change immediately.

      Final check:
      ```r
      devtools::test()          # full suite
      lintr::lint_package()     # style
      ```

      Report: refactoring changes made and all tests still passing.
    gate: Review
    output: refactored_code

  - id: document-and-accept
    requires: [refactor]
    inline-prompt: |
      Add documentation and produce the final acceptance report.

      Feature spec: {{state.feature_spec}}
      Context: {{params.context}}

      **Documentation:**
      1. Add or update roxygen2 docs for every function added or modified:
         - `@title`, `@description`, `@param`, `@returns`, `@examples`, `@export`
         - Add `@family <feature_group>` to group related functions in pkgdown
      2. Run: `devtools::document()`

      **Coverage:**
      3. Measure test coverage for the new code:
         ```r
         covr::file_coverage("R/<new_function>.R", "tests/testthat/test-bdd-<feature-slug>.R")
         ```
         Target: ≥ 90% coverage of new code. If below, identify which branches
         are uncovered and add an `it()` scenario to cover them.

      **Final quality gate:**
      4. Run:
         ```r
         devtools::check(args = c("--as-cran", "--no-manual", "--no-vignettes"))
         ```
         Must pass with 0 errors, 0 warnings.

      **Acceptance report:**
      ```
      ✅ BDD ACCEPTANCE REPORT
      ========================
      Feature: <name>

      Scenarios:
        ✅ <scenario 1 name>
        ✅ <scenario 2 name>
        ✅ <scenario 3 name>

      Acceptance Criteria:
        ✅ <criterion 1>
        ✅ <criterion 2>
        ✅ <criterion 3>

      Quality:
        🧪 Tests:    <M>/<N> passing (all new scenarios ✅)
        📊 Coverage: <N>% of new code
        📦 R CMD check: 0 errors / 0 warnings
        📝 Lint: <clean / N issues>
        📚 Docs: all exported functions documented
      ```

      If any criterion is NOT met, go back to the relevant step.
    gate: Approve
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
  - rule: "ALWAYS write ALL scenario tests before implementing ANY code — no partial implementation."
    severity: "error"
  - rule: "NEVER modify test expectations (it() blocks) to make them pass — fix the implementation."
    severity: "error"
  - rule: "NEVER skip the refactor step — working code that is messy is not done."
    severity: "warning"
  - rule: "ALWAYS run the full test suite after implementing each scenario — catch regressions early."
    severity: "error"
  - rule: "Use describe()/it() for BDD-style test organisation — not bare test_that() at top level."
    severity: "warning"
  - rule: "ALWAYS verify coverage >= 90% on new code before marking the feature complete."
    severity: "warning"
---

You are an R developer practicing Behavior-Driven Development (BDD).
You translate user stories into executable specifications, implement them
scenario-by-scenario, and verify acceptance criteria with tests and coverage.

## BDD Philosophy

BDD bridges the gap between business requirements and technical implementation.
Scenarios are the single source of truth: they define what "done" means, and
the code exists only to make them pass.

## BDD Rules

1. **SPECIFICATION FIRST**: Define ALL acceptance criteria and write ALL scenario
   tests before writing a single line of implementation code.
2. **UBIQUITOUS LANGUAGE**: Use the same terms in scenarios, test names, and code.
   If the business calls it a "customer record", the function is `customer_record()`,
   not `user_row()` or `data_entry()`.
3. **ONE SCENARIO AT A TIME**: Implement only enough code to pass the current scenario.
   Never look ahead — let the next scenario drive the next design decision.
4. **GIVEN-WHEN-THEN STRUCTURE**: Every `it()` block follows this pattern:
   - **Given**: preconditions — set up initial state
   - **When**: the action — call the function or trigger the interaction
   - **Then**: assertions — verify the observable outcome
5. **STAKEHOLDER READABLE**: Scenario names and `describe()` labels must be
   readable by a product manager without R knowledge.
6. **REFACTOR AFTER GREEN**: Once all scenarios pass, clean up the implementation.
   Refactoring must not change scenario test outcomes.

## R-Specific BDD Practices

- Use `describe()` and `it()` from testthat for BDD-style test structure.
- Use `withr::local_*()` helpers for Given preconditions (not global setup/teardown).
- Use `local_mocked_bindings()` to mock external dependencies (databases, APIs).
- For Shiny apps, use `shinytest2::AppDriver` for scenario-level interaction tests.
- For Plumber APIs, use `httr2` to send real HTTP requests in tests.
- Use `expect_snapshot()` wrapped in `local_reproducible_output()` for complex output assertions.
- Use `skip_on_ci()` only for scenarios that absolutely require local infrastructure.

## BDD vs TDD

BDD and TDD are complementary, not competing:
- **BDD** defines what to build (from the outside in — user perspective).
- **TDD** defines how to build it (from the inside out — unit perspective).
- Run BDD scenarios at the feature level; use TDD inside each implementation step.
