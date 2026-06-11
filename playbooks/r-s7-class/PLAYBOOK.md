---
name: r-s7-class
version: 1.0.0
context-mode: Fork
description: "Define an S7 class (R's new OOP system) with typed properties, generic functions, and methods — the modern alternative to S3/S4/R6. Usable in packages, Shiny modules, or Plumber serialization"
trigger: both
trigger-patterns:
  - "S7 *"
  - "class *"
  - "S7 class *"
  - "create S7 *"
  - "define class *"
  - "new class *"
argument-hint: "--name <ClassName> [--properties <prop1:type,prop2:type>]"
parameters:
  name:
    type: String
    required: true
    hint: "Class name (PascalCase, e.g., Person, DataPipeline)"
  properties:
    type: String
    required: false
    hint: "Comma-separated properties with types (e.g., name:character,age:integer)"
  parent:
    type: String
    required: false
    hint: "Parent class name for inheritance (optional)"
steps:
  - id: install-s7
    inline-prompt: |
      Install and verify the S7 package:

      ```r
      if (!requireNamespace("S7", quietly = TRUE)) {
        pak::pak("S7")
      }
      library(S7)
      packageVersion("S7")
      ```
    output: s7-version
  - id: design-class
    inline-prompt: |
      Design the S7 class `{{params.name}}`.

      Plan the class structure:
      1. **Properties** with types and defaults
      2. **Validator** for invariants
      3. **Constructor** for object creation
      4. **Generics** that this class will implement methods for

      Property types available in S7:
      - `class_character`, `class_logical`, `class_integer`, `class_double`, `class_numeric`, `class_complex`
      - `class_factor`, `class_Date`, `class_POSIXct`
      - `class_list`, `class_environment`, `class_function`, `class_expression`, `class_call`
      - `class_data.frame`, `class_matrix`, `class_array`
      - `new_union()` for union types
      - `new_any` for any type

      From the properties `{{params.properties}}`:
      - Parse each prop:type pair
      - If a parent class is specified (`{{params.parent}}`), design for inheritance
      - Design a validator that checks business logic invariants

      Report: class design with properties, parent, validator rules, and generics to implement.
    output: class-design
    gate: Review
  - id: implement-class
    inline-prompt: |
      Implement the S7 class in `R/{{params.name}}.R`:

      ```r
      library(S7)

      #' Class definition
      #' @export
      {{params.name}} <- new_class(
        name = "{{params.name}}",
        package = "<pkg_name>",
        properties = list(
          # Parse {{params.properties}} into property definitions
          # Example:
          # id = class_character,
          # value = class_numeric,
          # timestamp = new_property(class = class_POSIXct, default = Sys.time())
          # name = new_property(
          #   class = class_character,
          #   validator = function(value) {
          #     if (nchar(value) == 0) "name must not be empty"
          #   }
          # ),
        ),
        validator = function(self) {
          # Business logic validation
          # if (length(self@id) != 1) return("id must be length 1")
          # if (self@value < 0) return("value must be non-negative")
          NULL  # NULL means valid
        }
      )

      #' @title Create a {{params.name}}
      #' @param ... Property values
      #' @return A {{params.name}} object
      #' @export

      #' @title Print method
      #' @param x A {{params.name}} object
      #' @export
      method(print, {{params.name}}) <- function(x) {
        cat("<{{params.name}}>\n")
        # Print properties
        invisible(x)
      }
      ```

      If a parent class is specified (`{{params.parent}}`), add `parent = {{params.parent}}` to the new_class() call.

      For the generics, define at least:
      1. A constructor method that validates input
      2. A `print` or `format` method for display
      3. An accessor generic for key properties

      Write the class to the appropriate file. Update NAMESPACE via roxygen2 `@export` tags.
    requires:
      - design-class
    output: class-file
    gate: Review
  - id: implement-generics
    inline-prompt: |
      Define generics and methods for `{{params.name}}`:

      ```r
      #' @title Summary method
      #' @param object A {{params.name}} object
      #' @export
      method(summary, {{params.name}}) <- function(object) {
        # Compute and return summary statistics
      }

      #' @title Comparison method
      #' @param e1 Left object
      #' @param e2 Right object
      #' @export
      method(`==`, list({{params.name}}, {{params.name}})) <- function(e1, e2) {
        # Implement equality check
      }
      ```

      If there are domain-specific operations, define new generics:
      ```r
      # Define a new generic
      process <- new_generic("process", "x",
        dispatch_args = "x"
      )

      # Implement method for this class
      method(process, {{params.name}}) <- function(x) {
        # Domain-specific processing
      }
      ```

      Add methods to the class file.
    requires:
      - implement-class
    output: generics-file
  - id: write-tests
    inline-prompt: |
      Write tests for the S7 class in `tests/testthat/test-{{params.name}}.R`:

      ```r
      library(S7)
      library(testthat)

      describe("{{params.name}}", {
        it("constructs with valid properties", {
          obj <- {{params.name}}(# valid properties)
          expect_true(S7::S7_inherits(obj, "{{params.name}}"))
        })

        it("rejects invalid properties", {
          expect_error({{params.name}}(# invalid), "must be non-negative")
        })

        it("validates required properties", {
          expect_error({{params.name}}(), "is required")
        })

        it("supports print method", {
          obj <- {{params.name}}(# valid)
          expect_output(print(obj), "{{params.name}}")
        })

        it("supports comparison", {
          a <- {{params.name}}(# ...)
          b <- {{params.name}}(# same)
          expect_true(a == b)
        })
      })
      ```

      Run the tests:
      ```r
      devtools::test(filter = "{{params.name}}")
      ```

      Report: test results, any failures, coverage gaps.
    requires:
      - implement-generics
    output: test-results
    gate: Review
tags:
  - r
  - oop
  - S7
  - architecture
constraints:
  - rule: "ALWAYS validate property types in the constructor — use S7 property validators to enforce type invariants."
    severity: "error"
  - rule: "Register generics with new_generic() and attach methods via method() dispatch — NEVER use S3 dispatch for S7 classes."
    severity: "error"
  - rule: "Use parent = <class> in new_class() for inheritance and call super's methods via super() where applicable."
    severity: "warning"
  - rule: "ALWAYS use class_character, class_double, new_union() etc. for property type constraints — never leave properties untyped."
    severity: "error"
  - rule: "Place one S7 class per file in R/ClassName.R with roxygen2 @export tags for the class, generics, and methods."
    severity: "warning"
allowed-tools:
  - "*"
---

# R S7 OOP Playbook

You are an expert in R object-oriented programming. Use `S7`: the modern OOP system designed for R (successor to R7, S3, S4).

## S7 vs Other R OOP Systems

| System | Best For                                             | Drawbacks                              |
| ------ | ---------------------------------------------------- | -------------------------------------- |
| **S3** | Simple polymorphism, method dispatch on one argument | No formal class defs, no validation    |
| **S4** | Formal classes, multiple dispatch (legacy)           | Complex, verbose, performance overhead |
| **S7** | Modern formal OOP with validation, multiple dispatch | Newer ecosystem                        |
| **R6** | Mutable objects, reference semantics                 | No method dispatch, manual cloning     |

### When to Choose S7

- ✅ Need formal class definitions with property validation
- ✅ Multiple dispatch (different behavior based on multiple arguments)
- ✅ Want clean, modern syntax designed for R
- ✅ Building a package with well-defined data types
- ✅ Migrating from S4 (S7 is the successor)

### When NOT to Choose S7

- ❌ Simple polymorphism on one argument → S3 is fine
- ❌ Mutable state with reference semantics → R6
- ❌ Quick prototyping → S3 or just lists

### Class Convention

- Class names: PascalCase (e.g., `Person`, `DataPipeline`)
- File: `R/ClassName.R`: one class per file
- Properties: snake_case
- Methods: verb*\* for actions, noun*\* for accessors
