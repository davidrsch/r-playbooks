---
name: r-shiny-e2e-test
version: 1.0.0
context-mode: Fork
description: "Add end-to-end tests for a Shiny app using shinytest2 (R-native, headless) or Cypress (JavaScript, real browser). For unit tests or TDD, use r-tdd-feature or r-rhino-test instead"
trigger: auto
trigger-patterns:
  - "shiiny *"
  - "e2e test *"
  - "shinytest2 *"
  - "cypress *"
  - "end-to-end test *"
parameters:
  app_path:
    type: String
    required: false
    default: "."
    hint: "Path to the Shiny app directory"
  framework:
    type: String
    required: false
    default: "shinytest2"
    enum: ["shinytest2", "cypress"]
    hint: "Test framework: shinytest2 (R-native) or cypress (JavaScript)"
  scenarios:
    type: Array
    required: false
    default: ["default"]
    hint: "Comma-separated test scenario descriptions"
tags:
  - r
  - shiny
  - testing
  - e2e
  - cypress
allowed-tools:
  - "*"
constraints:
  - rule: "NEVER let E2E tests hit live external APIs — use cy.intercept() or mock servers to avoid flakiness."
    severity: "error"
  - rule: "NEVER use hardcoded wait times (cy.wait(N) or Sys.sleep()) — wait for DOM state or network responses instead."
    severity: "error"
  - rule: "ALWAYS use data-cy or data-testid selectors — never CSS classes, IDs, or XPath."
    severity: "error"
  - rule: "ALWAYS use app$wait_for_idle() after app$set_inputs() in shinytest2 to wait for reactive recalculation."
    severity: "error"
  - rule: "ALWAYS run tests in headless mode in CI — never depend on headed browser availability."
    severity: "warning"
  - rule: "ALWAYS clean up test fixtures and app state between tests to ensure isolation."
    severity: "warning"
steps:
  - id: install-tools
    inline-prompt: |
      Install test dependencies for {{params.framework}}.

      **shinytest2**:
      ```r
      if (!requireNamespace("shinytest2", quietly = TRUE)) {
        renv::install("shinytest2")
      }
      ```

      **cypress** (requires Node.js):
      ```bash
      npx cypress install
      npm install --save-dev cypress @cypress/code-coverage
      ```

      For cypress with Shiny, also install:
      ```r
      if (!requireNamespace("shiny", quietly = TRUE)) {
        renv::install("shiny")
      }
      ```
    output: installed-tools
  - id: create-test-structure
    requires:
      - install-tools
    inline-prompt: |
      Set up the test structure for {{params.framework}}.

      **shinytest2**:
      ```r
      shinytest2::use_shinytest2(app_dir = "{{params.app_path}}")
      ```
      This creates `tests/testthat/` with setup-shinytest2.R and a test skeleton.

      **cypress**:
      ```bash
      npx cypress open
      ```
      This creates `cypress/` directory with e2e/, fixtures/, support/.

      If using rhino: `rhino::test_e2e()` initializes Cypress for the project.

      Test organization by scenario type. For the scenarios `{{params.scenarios}}`, create:
      - shinytest2: one test file per feature area
      - cypress: one spec file per feature area
    output: test-structure
    gate: Review
  - id: record-test
    requires:
      - create-test-structure
    inline-prompt: |
      For shinytest2, record a baseline test using the record_test() recorder:

      ```r
      # Launch the app in record mode
      shinytest2::record_test("{{params.app_path}}")
      ```

      This opens the app with a recording sidebar. Perform the user interactions:
      1. Navigate through the app as a user would
      2. Click buttons, fill forms, select dropdowns
      3. Verify outputs update correctly
      4. Save the recording

      The recorder generates:
      - test file with `app$expect_values()` snapshot assertions
      - Expected screenshot snapshots

      Always call `app$wait_for_idle()` after `app$set_inputs()` to wait for
      reactive recalculation:
      ```r
      app$set_inputs(x = "42")
      app$wait_for_idle()  # Wait for reactive recalculation
      ```

      For cypress, use Cypress Studio or write specs manually:
      ```javascript
      // cypress/e2e/app-navigation.cy.js
      describe('App Navigation', () => {
        beforeEach(() => {
          cy.visit('/')
          // Ensure Shiny app is fully rendered before interacting
          cy.get('[data-cy="main-title"]', { timeout: 10000 }).should('be.visible')
        })

        it('loads the default view', () => {
          cy.get('[data-cy="main-title"]').should('contain', 'My App')
        })

        it('responds to user interaction', () => {
          cy.get('[data-cy="input-x"]').type('42')
          cy.get('[data-cy="calculate-btn"]').click()
          cy.get('[data-cy="result"]').should('contain', '84')
        })

        it('shows validation error for empty input', () => {
          cy.get('[data-cy="calculate-btn"]').click()
          cy.get('[data-cy="error-message"]').should('be.visible')
        })
      })
      ```

      ### Selector Best Practices

      - ✅ Use `data-cy` or `data-testid` attributes: `cy.get('[data-cy="submit-btn"]')`
      - ❌ CSS IDs: `cy.get('#submit')`: IDs change with UI refactors
      - ❌ CSS classes: `cy.get('.btn-primary')`: classes are for styling
      - ❌ XPath or complex DOM traversal: fragile to DOM changes

      To add `data-cy` attributes in Shiny:
      ```r
      actionButton("calculate", "Calculate", `data-cy` = "calculate-btn")
      textOutput("result", `data-cy` = "result")
      ```

      ### Network Stubbing

      For tests that depend on backend API responses, use `cy.intercept()`:

      ```javascript
      beforeEach(() => {
        cy.intercept('POST', '/session/*/dataobj/predict', {
          statusCode: 200,
          body: { prediction: 42 }
        }).as('predictCall')
      })
      ```

      NEVER let E2E tests hit live external APIs: they become flaky and non-deterministic.
    output: recorded-tests
    gate: Review
  - id: run-tests
    requires:
      - record-test
    inline-prompt: |
      Run the e2e tests.

      **shinytest2**:
      ```r
      # Run all tests
      shinytest2::test_app("{{params.app_path}}")

      # Or run a specific test file
      testthat::test_file("tests/testthat/test-default.R")
      ```

      **cypress**:
      ```bash
      npx cypress run
      # Or headed mode for debugging:
      npx cypress open
      ```

      Interpret results:
      - shinytest2: snapshot comparison: new snapshots need review
      - cypress: pass/fail assertions with screenshots on failure

      If shinytest2 tests show snapshot differences:
      ```r
      shinytest2::snapshot_review()
      ```
      Review each diff. Only accept if the change is intentional:
      ```r
      testthat::snapshot_accept("test-name")
      ```

      NEVER blindly accept all snapshots: review each one.
    output: test-results
  - id: add-ci-config
    requires:
      - run-tests
    inline-prompt: |
      Add E2E tests to CI configuration.

      **shinytest2 in GitHub Actions**:
      ```yaml
      - name: E2E Tests
        run: |
          shinytest2::test_app()
        shell: Rscript {0}
      ```

      **cypress in GitHub Actions**:
      ```yaml
      - name: Cypress E2E Tests
        uses: cypress-io/github-action@v6
        with:
          start: Rscript -e "shiny::runApp()"
          wait-on: 'http://localhost:3838'
          browser: chrome

      - name: Upload Cypress Screenshots (on failure)
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: cypress-screenshots
          path: cypress/screenshots/

      - name: Upload Cypress Videos
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: cypress-videos
          path: cypress/videos/
      ```

      Add the configuration to the project's CI file.
    output: ci-config
---

# R Shiny E2E Testing Playbook

You are an expert in end-to-end testing for R Shiny applications. Use `shinytest2` for R-native testing or Cypress for JavaScript-based testing.

## Framework Selection Guide

| Criterion            | shinytest2      | Cypress                |
| -------------------- | --------------- | ---------------------- |
| Language             | R               | JavaScript             |
| Learning curve       | Low for R users | Moderate (JS required) |
| Snapshot testing     | ✅ Built-in     | ❌ Manual              |
| Complex interactions | Good            | Excellent              |
| CI speed             | Moderate        | Fast                   |
| Rhino integration    | Manual setup    | `rhino::test_e2e()`    |
| Debugging            | R debugger      | Time-travel debugger   |

### When to use shinytest2

- Team is primarily R developers
- Need snapshot regression testing
- Simple to moderate user interactions
- Quick setup without Node.js dependency

### When to use Cypress

- Complex multi-step user journeys
- Need time-travel debugging
- Testing loading states and animations
- Already using rhino framework
- Team has JavaScript experience

### Test Organization

- One test file per feature area (not per page)
- Descriptive test names that explain the user journey
- Use `describe`/`it` blocks for logical grouping
- Screenshots on failure for CI debugging

### Anti-patterns

- ❌ Testing implementation details (test user-visible behavior)
- ❌ Hardcoded wait times (`cy.wait(5000)`): flaky and slow
- ✅ Wait for DOM state: `cy.get('[data-cy="spinner"]').should('not.exist')`
- ✅ Wait for network: `cy.intercept('POST', '/api/*').as('apiCall'); cy.wait('@apiCall')`
- ❌ Blindly accepting all snapshot changes
- ❌ Tests that depend on external services (mock them)
