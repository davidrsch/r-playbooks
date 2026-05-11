---
name: r-data-validate
version: 1.0.0
context-mode: Fork
description: Validate data quality with pointblank/validate — schema checks, value ranges, completeness, uniqueness
trigger: both
trigger-patterns:
  - "validate data *"
  - "check data *"
  - "data quality *"
  - "validate * data"
argument-hint: "--data <dataframe> [--framework pointblank|validate] [--output report|json|rds]"
parameters:
  data:
    type: String
    required: true
    hint: "Name of the data.frame/tibble to validate (in current environment)"
  framework:
    type: String
    required: false
    default: "pointblank"
    enum: ["pointblank", "validate"]
    hint: "Validation framework: pointblank (rich reporting) or validate (rule-based)"
  output:
    type: String
    required: false
    default: "report"
    enum: ["report", "json", "rds", "inline"]
    hint: "Output format for validation results"
steps:
  - id: analyze-data
    inline-prompt: |
      Analyze the data structure of `{{params.data}}`:

      1. Run: `pointblank::scan_data({{params.data}})` for an interactive data profile.
      2. Run: `glimpse({{params.data}})` or `str({{params.data}})` to see structure.
      3. Run: `summary({{params.data}})` for numeric summaries.
      3. For each column, determine:
         - Column name, type (chr, int, dbl, lgl, date, fct)
         - Number of missing values (NAs)
         - Number of unique values
         - For numeric: min, max, mean, number of zeros/negatives
         - For character: min/max string length, common patterns
         - For dates: min/max date range
      4. Report: data dimensions, column summary.

      This analysis drives what validation rules to create.
    output: data_profile

  - id: generate-checks
    requires: [analyze-data]
    inline-prompt: |
      Generate comprehensive validation rules based on the data profile.

      Data profile: {{state.data_profile}}
      Framework: {{params.framework}}

      For EVERY column, generate appropriate checks:

      **Schema checks (all columns):**
      - Column exists
      - Column type is correct

      **Completeness checks:**
      - No unexpected NULL/NA values
      - Minimum completeness threshold (e.g., < 10% missing acceptable)

      **Value range checks (numeric columns):**
      - Within expected min/max
      - No unexpected negative values (if applicable)
      - No unexpected zeros (if applicable)

      **Uniqueness checks (ID/key columns):**
      - No duplicate values in ID columns
      - Composite keys (if applicable): unique combinations

      **Pattern checks (string columns):**
      - Email format (if applicable)
      - Phone format (if applicable)
      - URL format (if applicable)
      - No invalid characters

      **Category checks (factor/character columns):**
      - Values in predefined set
      - No empty strings ""

      **Date checks:**
      - Valid date ranges
      - No future dates (if applicable)
      - Chronological ordering (if applicable)

      **Cross-column checks:**
      - start_date <= end_date
      - total = sum(parts)
      - Referential integrity (if multiple tables)

      Report the full validation plan before creating code.
    gate: Confirm
    output: validation_plan

  - id: implement-validation
    requires: [generate-checks]
    inline-prompt: |
      Implement the validation rules.

      Plan: {{state.validation_plan}}
      Framework: {{params.framework}}

      When framework is `pointblank`, create the validation script using the
      pointblank agent pattern:

      ```r
      library(pointblank)

      agent <- {{params.data}} |>
        create_agent(
          tbl_name = "{{params.data}}",
          label = "Data quality validation for {{params.data}}",
          actions = action_levels(stop_at = 0.1, warn_at = 0.05, notify_at = 0.01)
        ) |>
        # Schema checks
        col_exists(columns = vars(column_name)) |>
        col_is_numeric(columns = vars(numeric_col)) |>
        col_is_character(columns = vars(char_col)) |>
        # Completeness
        col_vals_not_null(columns = vars(key_column)) |>
        col_vals_gt(columns = vars(numeric_col), value = 0) |>
        # Schema (use x_list for reusable column lists)
        cols <- x_list(col_a, col_b, col_c)
        col_schema(schema = col_schema(
          col_a = "numeric",
          col_b = "character",
          col_c = "Date"
        )) |>
        # Uniqueness
        rows_distinct(columns = vars(id_column)) |>
        # Value ranges
        col_vals_between(columns = vars(numeric_col), left = 0, right = 100) |>
        # Patterns
        col_vals_regex(columns = vars(email_col), pattern = "^[^@]+@[^@]+$") |>
        # Interrogate
        interrogate()

      agent
      ```

      Tip: Use `pointblank::draft_validation()` to get AI-assisted suggestions
      for validation rules based on the data profile.

      When framework is `validate`, create the validation script using validate:

      ```r
      library(validate)

      rules <- validator(
        # Schema
        is.numeric(column_a),
        is.character(column_b),
        # Ranges
        column_a >= 0,
        column_a <= 100,
        # Completeness
        !is.na(column_a),
        # Uniqueness
        is_unique(id_column),
        # Cross-column
        start_date <= end_date
      )

      results <- confront({{params.data}}, rules)
      summary(results)
      plot(results)
      ```

      For output format:
      - When output is `report`, use `export_report(agent, filename = "validation_report.html")`
        to create an HTML report.
      - When output is `json`, use `get_agent_report(agent, display_table = FALSE)`
        to export results as JSON.
      - When output is `rds`, save the agent object: `saveRDS(agent, "validation_agent.rds")`
      - When output is `inline`, print results to console.

      For pointblank, also generate a report of failed validations:
      ```r
      # Extract rows that failed validation for further investigation
      failed_data <- get_sundered_data(agent)
      ```

      Report: validation script written, results summary.
    gate: Review
    output: validation_results

  - id: report-findings
    requires: [implement-validation]
    inline-prompt: |
      Summarize the validation findings:

      Results: {{state.validation_results}}

      Produce a clear report:

      ```
      📊 DATA VALIDATION REPORT
      ========================
      Dataset: {{params.data}}
      Framework: {{params.framework}}

      📋 Summary:
      ✅ Passing: <N>/<M> checks
      ❌ Failing: <N>/<M> checks
      ⚠️  Warnings: <N>

      ❌ FAILED CHECKS (action required):
      - <column>: <rule description>
        Expected: <expected>
        Actual: <actual>
        Affected rows: <N>

      ✅ PASSED CHECKS:
      - ...

      📈 Data Quality Score: <X>%
      ```

      For each failure, provide:
      - Column/rule that failed
      - What was expected vs. actual
      - Number/percentage of rows affected
      - Suggested remediation

      For large-scale or CI validation, provide a YAML config example
      for storing reusable validation rules:

      ```yaml
      # validation_rules.yaml
      data_source: {{params.data}}
      rules:
        - column: id
          type: col_vals_not_null
        - column: age
          type: col_vals_between
          left: 0
          right: 120
        - column: email
          type: col_vals_regex
          pattern: "^[^@]+@[^@]+$"
      ```

      The YAML rules can be loaded and applied programmatically for
      repeatable CI validation workflows.
    output: final_report

tags:
  - r
  - data
  - validation
  - quality
  - pointblank

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are an R data quality specialist. You validate data using pointblank
or validate frameworks to ensure data meets quality standards.

## Rules

1. ALWAYS profile the data FIRST before writing validation rules.
2. Generate checks for EVERY column — don't skip any.
3. Use the appropriate framework:
   - `pointblank` for rich HTML/email reports and pipelines (preferred)
   - `validate` for rule-based validation in ETL/CI contexts
4. Be specific about expected values — don't just check for "not NULL".
5. Use `pointblank::draft_validation()` to get AI-assisted rule suggestions.
6. Extract failed rows with `pointblank::get_sundered_data()` for remediation.
7. Store reusable rules as YAML config for repeatable CI validation.
8. Report both PASS and FAIL results clearly.
9. For failures, always include:
   - Which column/rule failed
   - How many rows are affected
   - What the expected range/value is
10. NEVER assume a column's type — verify it.
11. For date columns, always check chronological consistency.
12. For ID columns, always check uniqueness.
13. The validation script should be reproducible and re-runnable.
