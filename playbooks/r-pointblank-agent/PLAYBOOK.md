---
name: r-pointblank-agent
version: 1.0.0
context-mode: Fork
description: Set up automated data validation with pointblank agents: create validation rules, generate reports, and integrate with CI
trigger: both
trigger-patterns:
  - "pointblank *"
  - "validate data with pointblank *"
  - "create validation *"
  - "data validation * pointblank"
  - "set up pointblank *"
  - "* pointblank agent"
argument-hint: "--data <dataframe_name> [--output report|yaml|html] [--ci true|false]"
parameters:
  data:
    type: String
    required: true
    hint: "Name of the data.frame/tibble to validate (must exist in current R session or file path)"
  output:
    type: String
    required: false
    default: "report"
    enum: ["report", "yaml", "html", "all"]
    hint: "Output format: report (console), yaml (validation plan), html (email-ready), all"
  ci:
    type: Boolean
    required: false
    default: false
    hint: "Set up CI integration with GitHub Actions to run validation on schedule"
steps:
  - id: install-pointblank
    inline-prompt: |
      Install and verify pointblank in the current R environment:

      1. Run: `pak::pak("pointblank")`
      2. Verify installation: `library(pointblank)`
      3. Report the version: `packageVersion("pointblank")`
      4. Verify key features are available:
         - `create_agent()`: agent creation
         - `interrogate()`: running validation
         - `draft_validation()`: AI-assisted rule generation
         - `get_sundered_data()`: extracting failed rows
      5. Check optional dependencies for rich output:
         - `gt` for table output
         - `ggplot2` for visual reports
      6. Confirm `pointblank::info_agent()` works.

      If pointblank cannot be installed, abort with clear error message.
    output: install_status

  - id: analyze-data
    requires: [install-pointblank]
    inline-prompt: |
      Analyze the target data for `{{params.data}}` to determine appropriate validation rules:

      1. Load the data:
         - If {{params.data}} is a file path (ends in .csv, .rds, .parquet, .tsv, etc.),
           read it with the appropriate reader:
           - `.csv` → `readr::read_csv()` or `data.table::fread()`
           - `.rds` → `readRDS()`
           - `.parquet` → `arrow::read_parquet()`
           - `.tsv` → `readr::read_tsv()`
         - If {{params.data}} is a name, assume it's in the current R environment.

      2. Run structural analysis:
         ```r
         nrow(data)
         ncol(data)
         names(data)
         sapply(data, class)
         sapply(data, function(x) sum(is.na(x)))
         sapply(data, function(x) length(unique(x)))
         ```

      3. For numeric columns, compute:
         - Min, max, mean, median, standard deviation
         - Number of zeros, number of negative values
         - Quantiles: 1st, 5th, 95th, 99th percentiles
         - Any values at extreme boundaries (machine limits)

      4. For character columns, report:
         - Min/max string length
         - Number of empty strings `""`
         - Numbers of distinct values vs total rows (cardinality)
         - Character pattern hints: do values look like emails? URLs? IDs?

      5. For date/datetime columns, report:
         - Min and max dates
         - Any dates in the future (vs `Sys.Date()`)
         - Date range span

      6. Run `pointblank::scan_data({{params.data}})` to get a comprehensive
         summary report of the data structure, types, and statistics.

      7. Run AI-assisted rule suggestions:
         > **Prerequisite:** `draft_validation()` requires an OpenAI API key
         > set as the `OPENAI_API_KEY` environment variable.
         ```r
         pointblank::draft_validation({{params.data}})
         ```
         This generates initial rule suggestions based on data patterns.
         Review the suggestions and report them: they'll drive rule creation.

      8. Report a comprehensive data profile:
         - Dimensions
         - Column-by-column summary with types, ranges, missing patterns
         - draft_validation() suggestions
    output: data_profile

  - id: create-agent
    requires: [analyze-data]
    inline-prompt: |
      Build a comprehensive pointblank agent for `{{params.data}}`.

      Data profile: {{state.data_profile}}

      Use the pointblank agent chain API. Create validation steps in this order:

      **Schema validation (every table must pass these):**
      ```r
      agent <- {{params.data}} |>
        create_agent(
          tbl_name = "{{params.data}}",
          label = "Validation for {{params.data}}",
          actions = action_levels(warn_at = 0.05, stop_at = 0.10)
        ) |>
        # 1. Column existence
        col_exists(columns = vars(<all_columns>))
      ```

      **Type validation:**
      ```r
        # 2. Column types: one rule per typed column
        col_is_numeric(columns = vars(<numeric_cols>)) |>
        col_is_character(columns = vars(<char_cols>)) |>
        col_is_logical(columns = vars(<lgl_cols>)) |>
        col_is_date(columns = vars(<date_cols>)) |>
        col_is_factor(columns = vars(<fct_cols>))
      ```

      **Completeness validation:**
      ```r
        # 3. Required columns have no NULL/NA
        col_vals_not_null(columns = vars(<required_cols>)) |>
        # 4. Key columns must be complete
        col_vals_not_null(columns = vars(<id_cols>))
      ```

      **Uniqueness validation:**
      ```r
        # 5. Primary key uniqueness
        rows_distinct(columns = vars(<pk_cols>)) |>
        # 6. No duplicate rows (if every row should be unique)
        rows_complete()  # or rows_distinct() for subset
      ```

      **Value range validation (numeric columns):**
      ```r
        # 7. Value ranges: one per numeric column, use data profile for bounds
        col_vals_between(
          columns = vars(<col>), left = <min>, right = <max>
        )
        # 8. Non-negative columns
        col_vals_gt(columns = vars(<nonneg_cols>), value = 0)
        # 9. Positive-only columns
        col_vals_gte(columns = vars(<pos_cols>), value = 0.001)
      ```

      **Set membership (categorical columns):**
      ```r
        # 10. Valid categories
        col_vals_in_set(
          columns = vars(<cat_col>),
          set = c(<valid_values>)
        )
      ```

      **Pattern validation (string columns):**
      ```r
        # 11. Email format (if applicable)
        col_vals_regex(
          columns = vars(email_col),
          pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        )
        # 12. No empty strings where values are expected
        col_vals_not_equal(
          columns = vars(<char_cols>),
          value = ""
        )
      ```

      **Cross-column validation (logical relationships):**
      ```r
        # 13. Date ordering
        col_vals_gte(
          columns = vars(end_date),
          value = vars(start_date)
        )
        # 14. Column relationships using conjointly()
        conjointly(
          ~ col_vals_gte(., columns = vars(end_date), value = vars(start_date)),
          ~ col_vals_lt(., columns = vars(discount), value = vars(price))
        )
      ```

      **Conditional validation using serially():**
      ```r
        # 15. Apply validations only when a condition is met
        serially(
          ~ rows_complete(.),
          ~ col_vals_between(., columns = vars(score), left = 0, right = 100)
        )
      ```

      **Statistical checks:**
      ```r
        # 16. Distribution-based checks
        col_vals_within_spec(
          columns = vars(<col>),
          spec = "<mean> +/- <3*sd>"
        )
      ```

      **Finalize the agent but do NOT interrogate yet:**
      ```r
      agent  # preview (not interrogated yet)
      ```

      Use the exact column names and value ranges from the data profile.
      Be SPECIFIC: no placeholder text in final output.
      Every column should have at least one validation step.
      Document what each step checks with `label = "..."` in each step function.

      Report the complete agent definition.
    gate: Confirm
    output: agent_definition

  - id: interrogate
    requires: [create-agent]
    inline-prompt: |
      Run the pointblank agent interrogation and analyze results.

      Agent definition: {{state.agent_definition}}

      1. Execute the agent:
         ```r
         agent <- <agent_from_definition> |>
           interrogate()
         ```

      2. Print the agent to see the validation table:
         ```r
         agent
         ```

      3. Generate a detailed report:
         ```r
         pointblank::get_agent_report(agent, title = "Validation Report: {{params.data}}")
         ```

      4. Analyze results:
         - Total validation steps: count
         - Passed: count and percentage
         - Failed: count and percentage
         - For each FAILED step, report:
           - Step number and label
           - Number of failing rows
           - Failure proportion (e.g., "5% of rows failed")
           - The rule that was violated

      5. Extract failed data for investigation:
         ```r
         # Extract rows that failed ANY validation
         failed_data <- pointblank::get_sundered_data(agent, type = "fail")
         # Or extract rows that passed ALL validations
         passed_data <- pointblank::get_sundered_data(agent, type = "pass")
         ```

      6. Analyze failure patterns:
         - Are failures clustered in specific columns?
         - Are there systemic issues (e.g., one bad data source)?
         - Do failures suggest a data pipeline bug vs. expected outliers?

      7. Produce a pass/fail summary with actionable recommendations.
    gate: Review
    output: interrogation_results

  - id: automate
    requires: [interrogate]
    inline-prompt: |
      Set up reusable and automated validation for `{{params.data}}`.

      Interrogation results: {{state.interrogation_results}}
      Output format: {{params.output}}
      CI mode: {{params.ci}}

      **Step 1: Save the validation plan as YAML**

      Create a reusable validation plan file:
      ```r
      # Read the YAML representation of the agent
      agent_yaml <- pointblank::yaml_write(
        agent,
        filename = "validation-plan.yaml"
      )
      ```

      The YAML file contains the full validation specification
      and can be replayed on new data:
      ```r
      new_agent <- pointblank::yaml_read_agent("validation-plan.yaml")
      new_agent <- pointblank::set_tbl(new_agent, new_data) |>
        interrogate()
      ```

      **Step 2: Generate output files**

      Based on {{params.output}}:

      When output is `report` or `all`:
      - Console report: `agent` (print to console)

      When output is `html` or `all`:
      - HTML email report:
        > **Prerequisite:** Sending emails via `email_create()` requires the
        > `blastula` package and SMTP credentials configured via
        > `blastula::create_smtp_creds_key()`.
        ```r
        pointblank::email_create(agent) |>
          pointblank::email_send(
            to = "data-team@example.com",
            subject = "Data Validation Report"
          )
        ```
        Or save to file:
        ```r
        pointblank::get_agent_report(agent, display_table = FALSE) |>
          htmltools::save_html("validation-report.html")
        ```

      When output is `yaml` or `all`:
      - YAML plan: already saved above.

      **Step 3: CI integration (when {{params.ci}} is true)**

      Create a `.github/workflows/pointblank-validate.yaml` file:

      ```yaml
      name: Pointblank Data Validation
      on:
        schedule:
          - cron: '0 6 * * *'  # Daily at 6 AM UTC
        push:
          branches: [main]
        pull_request:
          branches: [main]
      jobs:
        validate:
          runs-on: ubuntu-latest
          steps:
            - uses: actions/checkout@v4
            - uses: r-lib/actions/setup-r@v2
            - uses: r-lib/actions/setup-r-dependencies@v2
              with:
                packages: pointblank
            - name: Run validation
              run: |
                Rscript -e '
                  library(pointblank)
                  agent <- yaml_read_agent("validation-plan.yaml")
                  agent <- agent |> set_tbl(<load_data>) |> interrogate()
                  if (pointblank::all_passed(agent)) {
                    cat("All validations passed\\n")
                  } else {
                    cat("Validation failures detected\\n")
                    print(agent)
                    # Upload artifact with failure details
                    saveRDS(agent, "validation-agent.rds")
                    quit(status = 1)
                  }
                '
            - name: Upload validation artifact on failure
              if: failure()
              uses: actions/upload-artifact@v4
              with:
                name: validation-results
                path: validation-agent.rds
                retention-days: 7
      ```

      The CI pipeline will:
      - Run validation on every push to main
      - Run validation daily on schedule
      - Fail the CI check if any validation fails
      - Alert the team via GitHub notifications

      **Step 4: Summary**

      Report:
      - YAML plan saved to: `validation-plan.yaml`
      - Files generated: list paths
      - CI workflow: created or skipped
      - Next steps: how to rerun validation manually, how to update rules
      - Schedule: if CI is enabled, the validation frequency
    gate: Approve
    output: automation_results

tags:
  - r
  - pointblank
  - data-validation
  - quality
  - ci

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are a data quality engineer using the `pointblank` package to
create automated, repeatable data validation pipelines for R.

## pointblank Agent API

The core workflow:

```r
library(pointblank)

agent <- data |>
  create_agent(tbl_name = "data", label = "My Validation") |>
  # Add validation steps...
  col_vals_gt(columns = vars(age), value = 0) |>
  col_vals_not_null(columns = vars(id)) |>
  rows_distinct(columns = vars(id)) |>
  # Run the validation
  interrogate()
```

## Validation Step Types

### Column-level (`col_vals_*`)

| Function                            | Checks                           |
| ----------------------------------- | -------------------------------- |
| `col_vals_gt(value)`                | Column > value                   |
| `col_vals_gte(value)`               | Column >= value                  |
| `col_vals_lt(value)`                | Column < value                   |
| `col_vals_lte(value)`               | Column <= value                  |
| `col_vals_equal(value)`             | Column == value                  |
| `col_vals_not_equal(value)`         | Column != value                  |
| `col_vals_between(left, right)`     | left <= col <= right             |
| `col_vals_not_between(left, right)` | col < left OR col > right        |
| `col_vals_in_set(set)`              | col in {allowed values}          |
| `col_vals_not_in_set(set)`          | col not in {forbidden values}    |
| `col_vals_null()`                   | Expect NULL/NA                   |
| `col_vals_not_null()`               | No NULL/NA                       |
| `col_vals_regex(pattern)`           | String matches regex             |
| `col_vals_within_spec(spec)`        | Within statistical specification |

### Type checks

| Function             | Checks                 |
| -------------------- | ---------------------- |
| `col_is_numeric()`   | Column is numeric      |
| `col_is_integer()`   | Column is integer      |
| `col_is_character()` | Column is character    |
| `col_is_logical()`   | Column is logical      |
| `col_is_factor()`    | Column is factor       |
| `col_is_date()`      | Column is Date         |
| `col_is_posix()`     | Column is POSIXct      |
| `col_exists()`       | Column exists in table |

### Row-level

| Function                   | Checks                            |
| -------------------------- | --------------------------------- |
| `rows_distinct()`          | Row (or column combo) is unique   |
| `rows_complete()`          | No NA values in any column        |
| `row_count_match(count)`   | Table has exactly `count` rows    |
| `col_schema_match(schema)` | Columns match a schema definition |

### Multi-step

| Function          | Purpose                                   |
| ----------------- | ----------------------------------------- |
| `conjointly(...)` | Multiple steps must ALL pass              |
| `serially(...)`   | Steps run in order; stop at first failure |

## Interrogation & Reporting

After `interrogate()`, the agent object displays:

- A color-coded validation table (green = pass, red/orange = fail)
- Statistics: pass rate, failure count, warning count
- Per-step: number of failing units, proportion failed

### Extracting failed data

```r
# Rows that failed ANY validation step
fail <- get_sundered_data(agent, type = "fail")

# Rows that passed ALL validation steps
pass <- get_sundered_data(agent, type = "pass")
```

### Reports and output

```r
# Console-friendly report
get_agent_report(agent)

# HTML email report
email_create(agent) |> email_send(to = "...")

# Save to file
yaml_write(agent, "plan.yaml")

# Read from file
agent <- yaml_read_agent("plan.yaml")
```

## draft_validation(): AI-Assisted Rules

```r
draft_validation(data)
```

This inspects the data and suggests validation rules based on
column types, ranges, and patterns. It's a starting point ;
always review and customize the suggestions.

## The Six Validation Workflows (VALID-I through VALID-VI)

From the pointblank documentation, there are six validation workflows
ranging from ad-hoc to fully automated:

| Workflow  | Mode        | Schedule | Reporting   | Storage   |
| --------- | ----------- | -------- | ----------- | --------- |
| VALID-I   | Interactive | Ad-hoc   | Console     | None      |
| VALID-II  | Interactive | Ad-hoc   | HTML        | None      |
| VALID-III | Scripted    | Manual   | Console     | YAML plan |
| VALID-IV  | Scripted    | Manual   | HTML email  | YAML plan |
| VALID-V   | Automated   | CI/CD    | Console/Log | YAML plan |
| VALID-VI  | Scheduled   | Cron/CI  | Email/Slack | YAML plan |

This playbook guides you from VALID-I (interactive exploration) through
VALID-VI (fully automated scheduled validation).

## CI Integration Pattern

When CI mode is enabled, add a GitHub Actions workflow that:

1. Loads the YAML validation plan
2. Loads the target data
3. Runs `interrogate()`
4. Fails the workflow if any validation fails (`quit(status = 1)`)
5. Optionally sends an email report

This turns data validation from a manual chore into an automated quality gate.

## Best Practices

- Start with `draft_validation()` for quick rule suggestions
- Always save the validation plan as YAML for reuse
- Use `label = "..."` on every step for readable reports
- Set `actions = warn_on_fail()` during development
- Set `actions = stop_on_fail()` in CI/production
- Review failure patterns: one bad data source can cause many failures
- Keep validation plans version-controlled alongside the data pipeline code
