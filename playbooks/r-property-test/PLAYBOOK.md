---
name: r-property-test
version: 1.0.0
context-mode: Fork
description: "Property-based testing for R: define invariants that must hold for all inputs, generate random test cases, shrink failing cases to minimal counterexamples, and add them as regression tests"
trigger: both
trigger-patterns:
  - "property test *"
  - "property based test *"
  - "property testing *"
  - "invariant test *"
  - "fuzz test *"
  - "quickcheck *"
  - "generative test *"
argument-hint: "--function <name> [--properties <list>] [--iterations 100] [--seed 123]"
parameters:
  function:
    type: String
    required: true
    hint: "Name of the function to property-test (must exist in R/)"
  properties:
    type: Array
    required: false
    default: []
    hint: "List of properties/invariants to test (e.g., 'idempotent', 'commutative', 'roundtrip')"
  iterations:
    type: Number
    required: false
    default: 100
    min: 10
    max: 10000
    hint: "Number of random test cases to generate per property"
  seed:
    type: Number
    required: false
    default: 123
    hint: "Random seed for reproducible test generation"
steps:
  - id: analyze-function
    inline-prompt: |
      Analyze the target function to identify testable properties.

      Function: {{params.function}}
      Provided properties: {{params.properties}}

      1. Read the function source: `R/{{params.function}}.R`
      2. Understand its:
         - Input types and domains (what are valid inputs?)
         - Output type
         - Side effects (if any)
         - Error conditions (what should throw?)
      3. Read existing tests: `tests/testthat/test-{{params.function}}.R`
      4. Identify the function's category for property suggestions:
         - **Pure computation** (math, string ops, data transforms)
         - **Serialization** (to/from JSON, RDS, arrow, CSV)
         - **Encoding/Decoding** (base64, hash, compression)
         - **Validation** (input checking, type assertions)
         - **Collection ops** (filter, sort, group, join)
         - **State machine** (transitions, invariants)

      Report: function analysis and candidate properties.
    gate: Confirm
    output: function_analysis

  - id: define-properties
    requires: [analyze-function]
    inline-prompt: |
      Define specific, testable properties for {{params.function}}.

      Function analysis: {{state.function_analysis}}

      If {{params.properties}} were provided, use those. Otherwise, identify
      properties from the common categories below:

      **1. IDEMPOTENCE**: `f(f(x)) == f(x)` for all x
         - Normalization, cleaning, formatting functions
         - Example: `trimws(trimws(x)) == trimws(x)`

      **2. ROUNDTRIP**: `decode(encode(x)) == x` for all x
         - Serialization/deserialization pairs
         - Example: `fromJSON(toJSON(x)) == x`

      **3. INVOLUTION**: `f(f(x)) == x` for all x (f is its own inverse)
         - Negation, reversal, complement
         - Example: `rev(rev(x)) == x`

      **4. COMMUTATIVITY**: `f(x, y) == f(y, x)` for all x, y
         - Symmetric operations
         - Example: `sum(x, y) == sum(y, x)`

      **5. ASSOCIATIVITY**: `f(f(x, y), z) == f(x, f(y, z))` for all x, y, z
         - Combining operations
         - Example: `paste(paste(x, y), z) == paste(x, paste(y, z))`

      **6. MONOTONICITY**: if `x <= y` then `f(x) <= f(y)` for all x, y
         - Sorting, cumulative operations
         - Example: `cumsum()` is monotonic for non-negative inputs

      **7. CONSISTENCY WITH REFERENCE**: `f(x)` matches a simpler implementation
         for all x where the simpler implementation is known correct.
         - Example: custom `my_mean(x) == mean(x)` for all numeric x

      **8. NO-OP BOUNDARY**: `f(x, 0)` or `f(x, identity_value) == x`
         - Operations with identity elements
         - Example: `x + 0 == x`, `x * 1 == x`

      **9. LENGTH PRESERVATION**: `length(f(x)) == length(x)` for all x
         - Element-wise transformations
         - Example: `length(toupper(x)) == length(x)`

      **10. ERROR INVARIANT**: For all invalid inputs, f throws an error of
          the expected class with a descriptive message.

      For each property, define:
      - Property name and description
      - Input generator strategy (what random values to generate)
      - How to verify the property holds
      - Expected failure modes (where might it not hold?)

      Report: 3-7 concrete, testable properties with generator strategies.
    gate: Confirm
    output: property_definitions

  - id: generate-generators
    requires: [define-properties]
    inline-prompt: |
      Write input generators for property-based testing of {{params.function}}.

      Property definitions: {{state.property_definitions}}

      Create `tests/testthat/test-property-{{params.function}}.R`.

      **Primary approach — use `hedgehog` (CRAN) for integrated generation + shrinking:**

      ```r
      library(hedgehog)
      library(testthat)

      # ── Property Tests with hedgehog ──────────────────────────────────

      # hedgehog::forall() generates random inputs and tests a property.
      # If a counterexample is found, hedgehog SHRINKS it automatically
      # to the minimal failing case.

      test_that("property: <property name 1>", {
        # Define a generator for valid inputs to {{params.function}}
        # Use hedgehog's gen.*() combinators to build domain-specific generators:
        #
        # gen.element(1:100)         — random element from a vector
        # gen.sample(1:100, 5)       — random sample of given size
        # gen.c(of = 10, gen.int(4))  — constant value
        # gen.int(10)                 — random integer 1-10
        # gen.double(10)              — random double (symmetric)
        # gen.unif(0, 1)              — uniform distribution
        # gen.element(c(TRUE, FALSE)) — boolean
        # gen.character()             — random strings
        # gen.list(gen.element(1:10)) — list generator
        # gen.map(gen)                — apply a generator to each element

        hedgehog::forall(
          gen.c(
            x = <generator for x>,   # e.g., gen.element(1:100)
            y = <generator for y>    # e.g., gen.int(10)
          ),
          function(x, y) {
            result <- {{params.function}}(x, y)
            # Assert the property holds
            expect_true(<property assertion>)
          },
          tests = {{params.iterations}}
        )
      })

      test_that("property: edge cases don't crash", {
        # Test specific edge cases separately
        edges <- list(
          empty = <empty input>,
          zero = 0,
          na = NA,
          null = NULL,
          infinity = Inf
        )
        for (edge in edges) {
          result <- tryCatch(
            {{params.function}}(edge),
            error = function(e) NULL  # documented errors are OK
          )
          if (!is.null(result)) {
            expect_true(<validity check on result>)
          }
        }
      })
      ```

      **Alternative — use `quickcheck` (CRAN) for lightweight testing:**

      ```r
      library(quickcheck)
      # quickcheck uses a simpler interface without integrated shrinking
      # See ?quickcheck::qc_fun for function-based property testing
      ```

      **Fallback — manual generators (if hedgehog/quickcheck generators don't
      cover the domain):**

      If the input type requires custom logic that hedgehog's gen.*()
      combinators can't express (rare), fall back to manual generators with
      `set.seed()` + `purrr::map()` + custom distribution sampling. Note that
      manual generators require MANUAL shrinking of counterexamples.

      For all approaches:
      - Cover the full input domain (happy path, edge cases, invalid inputs)
      - Include typical, atypical, and boundary values
      - Be reproducible (set.seed or hedgehog's seed parameter)
      - Generate enough cases for statistical confidence ({{params.iterations}})

      Run the initial test — it may fail, which is expected before shrinking.
    gate: Review
    output: generator_code

  - id: run-and-shrink
    requires: [generate-generators]
    inline-prompt: |
      Run property tests and shrink any failures to minimal counterexamples.

      1. Run the property tests:
         ```r
         devtools::test(filter = "property-{{params.function}}")
         ```

      2. If all properties pass for {{params.iterations}} iterations:
         ✅ Property tests pass: confidence increases with iteration count.
         Report: all N properties hold for {{params.iterations}} random inputs.

      3. If any property FAILS:
         🔴 Found a counterexample. Now SHRINK it:

         **If using hedgehog**: shrinking is AUTOMATIC. `hedgehog::forall()` shrinks
         counterexamples to minimal form by default — the reported failing input is
         already the simplest case. No manual work needed.

         **If using quickcheck or manual generators**: shrink manually:
         - Take the failing input
         - Systematically reduce its complexity:
           - For numbers: try 0, then successively halve the value
           - For strings: try "", then remove characters one at a time
           - For vectors: try c(), then successively shorter subsets
           - For data frames: try 0 rows, then 1 row, then remove columns
         - At each step, check if the property still fails
         - Stop when no further simplification is possible
         - The result is the MINIMAL counterexample

         Report:
         ```
         🔴 PROPERTY FAILURE:
         Property: <property name>
         Original input: <the random input that failed>
         Minimal counterexample: <simplest input that still fails>
         Expected: <what the property asserts>
         Actual: <what actually happened>
         ```

      Report: all property test results with counterexamples (if any).
    gate: Review
    output: property_results

  - id: add-regression-tests
    requires: [run-and-shrink]
    inline-prompt: |
      Add regression tests from property test findings.

      Property results: {{state.property_results}}

      **If properties passed:**
      Add the property test file as ongoing regression protection:
      1. The property tests in `tests/testthat/test-property-{{params.function}}.R`
         serve as ongoing regression tests — they will catch future violations.
      2. Consider reducing iterations for CI speed (keep at {{params.iterations}}
         for local, use 20-50 for CI with `skip_on_ci()` guards on heavy tests).
      3. Tag slow property tests with `skip_on_cran()`.

      **If properties failed:**
      For each counterexample found:
      1. Add a specific regression test to `tests/testthat/test-{{params.function}}.R`:
         ```r
         test_that("regression: <property> fails for minimal input", {
           expect_equal(
             {{params.function}}(<minimal_counterexample>),
             <expected_value>
           )
         })
         ```
      2. Fix the function implementation to make the property hold.
         - If the counterexample reveals a genuine bug: fix it.
         - If the property was too strict: refine the property, not the function.
         - If the counterexample is an undocumented edge case: decide whether
           to support it or document it as invalid input.
      3. Re-run property tests after fixing:
         ```r
         devtools::test(filter = "property-{{params.function}}")
         ```
         Must pass now.

      **Finalize:**
      4. Run full test suite: `devtools::test()`
      5. Commit the property test file and any fixes:
         ```bash
         git add tests/testthat/test-property-{{params.function}}.R \
                 tests/testthat/test-{{params.function}}.R
         git commit -m "test: add property-based tests for {{params.function}}
      
         Properties tested: <list properties>
         Iterations: {{params.iterations}} per property
         Seed: {{params.seed}}"
         ```

      Report: regression tests added and all property tests passing.
    gate: Review
    output: final_results

tags:
  - r
  - testing
  - property-testing
  - quality
  - fuzzing

allowed-tools:
  - "*"

constraints:
  - rule: "ALWAYS set a seed for reproducibility — property tests must be deterministic."
    severity: "error"
  - rule: "NEVER fix a property failure by weakening the property — investigate the function first."
    severity: "error"
  - rule: "ALWAYS shrink counterexamples to minimal form — report the simplest failing case."
    severity: "warning"
  - rule: "ALWAYS add regression tests for any counterexample found — prevent recurrence."
    severity: "warning"
  - rule: "Cover edge cases explicitly: NULL, NA, empty, zero-length, Inf, NaN."
    severity: "warning"
---

You are an R property-based testing specialist. You identify invariants and
properties of R functions, generate random inputs to test them, shrink failures
to minimal counterexamples, and cement findings as regression tests.

## What is Property-Based Testing?

Instead of writing specific test cases (`expect_equal(f(3), 7)`), you define
PROPERTIES that must hold for ALL valid inputs (`f(x) == f(f(x))` for all x).
The test framework generates random inputs and verifies the property.

## Why Property Testing?

1. **Finds bugs example-based tests miss**: Random generation explores inputs
   you wouldn't think to test manually.
2. **Better coverage per test**: One property test covers infinitely many cases.
3. **Documents invariants**: Properties express what the function guarantees.
4. **Shrinking produces perfect bug reports**: Minimal counterexamples are
   far easier to diagnose than "it fails with some large random input."

## Common R Properties

| Function Type | Properties to Test |
|---------------|-------------------|
| Math (log, sqrt, abs) | Monotonicity, sign preservation, domain validity |
| String (tolower, trimws) | Idempotence, length preservation, encoding roundtrip |
| Data transform (mutate, filter) | Row count constraints, column set preservation |
| Serialization (jsonlite, arrow) | Roundtrip: `fromJSON(toJSON(x)) == x` |
| Sorting (sort, arrange) | Permutation of input, monotonic output |
| Aggregation (sum, mean, sd) | NA handling, empty input behavior |
| Validation (check_*) | Returns TRUE for valid, error for invalid |

## Generator Strategies

- **Numeric**: `rnorm()`, `runif()`, `rexp()`, `rpois()` with varied parameters
- **Integer**: `sample(1:1000, n, TRUE)`, including 0 and negative
- **Character**: `stringi::stri_rand_strings(n, 1:50)`, including `""`, `NA`
- **Logical**: `sample(c(TRUE, FALSE, NA), n, TRUE)`
- **Date/POSIXct**: `as.Date("2000-01-01") + sample(-10000:10000, n, TRUE)`
- **Factor**: `factor(sample(letters[1:5], n, TRUE))`
- **Data frame**: `tibble::tibble(x = gen_x(n), y = gen_y(n))`
- **List**: Recursive list generators with varying depth

## R Property Testing Packages

- **hedgehog** (CRAN): Full property-based testing with integrated shrinking.
  ```r
  hedgehog::forall(hedgehog::gen.element(1:100), function(x) x == x)
  ```
- **quickcheck** (CRAN): Lightweight QuickCheck port.
- **testthat + custom generators**: Manual approach shown in this playbook.
  More flexible but requires manual shrinking.
