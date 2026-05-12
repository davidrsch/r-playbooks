---
name: r-duckdb-pipeline
version: 1.0.0
context-mode: Fork
description: "Build an analytical data pipeline using {duckdb} and {arrow}: in-process OLAP queries, Parquet I/O, and dplyr/SQL on large files without loading into memory"
trigger: both
trigger-patterns:
  - "duckdb *"
  - "arrow *"
  - "parquet *"
  - "analytical pipeline *"
  - "olap *"
  - "large data *"
argument-hint: "--source <path> [--format csv|parquet|json|arrow] [--output parquet|csv] [--persist true|false]"
parameters:
  source:
    type: String
    required: true
    hint: "Path to input data file(s) — supports glob patterns (e.g. 'data/*.parquet')"
  format:
    type: String
    required: false
    default: "parquet"
    enum: ["csv", "parquet", "json", "arrow", "feather"]
    hint: "Input file format"
  output:
    type: String
    required: false
    default: "parquet"
    enum: ["parquet", "csv", "arrow"]
    hint: "Output format for pipeline results"
  persist:
    type: Boolean
    required: false
    default: false
    hint: "Persist DuckDB database to disk (true) vs. use in-memory (false)"
  db-path:
    type: String
    required: false
    hint: "Path for persistent DuckDB file (only used when persist: true, e.g. 'pipeline.duckdb')"
steps:
  - id: setup-packages
    inline-prompt: |
      Install required packages for the DuckDB + Arrow pipeline.

      ```r
      pak::pak(c("duckdb", "arrow", "dplyr", "dbplyr", "tidyr", "readr"))
      ```

      Verify versions:
      ```r
      packageVersion("duckdb")   # should be >= 0.10.0
      packageVersion("arrow")    # should be >= 14.0.0
      ```

      DuckDB and Arrow integrate natively — no format conversion needed between them.
      Report: packages installed and versions.
    output: packages_installed

  - id: open-connection
    requires: [setup-packages]
    inline-prompt: |
      Open a DuckDB connection.

      Persist: {{params.persist}}
      DB path: {{params.db-path}}

      ```r
      library(duckdb)
      library(arrow)
      library(dplyr)

      # In-memory (ephemeral, fast):
      con <- dbConnect(duckdb())

      # Persistent (survives session):
      # con <- dbConnect(duckdb("{{params.db-path}}"))
      ```

      Use in-memory if `{{params.persist}}` is false, persistent if true.

      Enable Arrow scan extension (built-in in modern duckdb):
      ```r
      dbExecute(con, "INSTALL arrow; LOAD arrow;")
      ```

      Report: connection opened, DuckDB version, extensions loaded.
    output: connection

  - id: read-source-data
    requires: [open-connection]
    inline-prompt: |
      Register the source data as a DuckDB view (zero-copy for Arrow/Parquet).

      Source: {{params.source}}
      Format: {{params.format}}

      **Parquet / Parquet glob:**
      ```r
      # DuckDB reads Parquet natively — no need to load into R memory
      dbExecute(con, "
        CREATE OR REPLACE VIEW source_data AS
        SELECT * FROM read_parquet('{{params.source}}', union_by_name = TRUE)
      ")
      ```

      **CSV:**
      ```r
      dbExecute(con, "
        CREATE OR REPLACE VIEW source_data AS
        SELECT * FROM read_csv_auto('{{params.source}}', header = TRUE)
      ")
      ```

      **Arrow / Feather (via arrow package):**
      ```r
      arrow_tbl <- arrow::open_dataset("{{params.source}}")
      duckdb::duckdb_register_arrow(con, "source_data", arrow_tbl)
      ```

      **JSON:**
      ```r
      dbExecute(con, "
        CREATE OR REPLACE VIEW source_data AS
        SELECT * FROM read_json_auto('{{params.source}}')
      ")
      ```

      Inspect the schema:
      ```r
      dbGetQuery(con, "DESCRIBE source_data")
      dbGetQuery(con, "SELECT COUNT(*) FROM source_data")
      ```

      Report: row count, column schema, estimated size.
    gate: Confirm
    output: data_schema

  - id: build-transformations
    requires: [read-source-data]
    inline-prompt: |
      Build the transformation pipeline using dplyr or SQL.

      Schema: {{state.data_schema}}

      **Option A: dplyr syntax (lazy evaluation, runs in DuckDB):**
      ```r
      result <- tbl(con, "source_data") |>
        filter(!is.na(<key_column>)) |>
        mutate(
          year  = year(as.Date(<date_col>)),
          month = month(as.Date(<date_col>))
        ) |>
        group_by(year, month, <category_col>) |>
        summarise(
          n       = n(),
          total   = sum(<value_col>, na.rm = TRUE),
          mean_val = mean(<value_col>, na.rm = TRUE),
          .groups = "drop"
        ) |>
        arrange(desc(year), desc(month))
      ```

      Preview without collecting:
      ```r
      show_query(result)   # see generated SQL
      result |> head(10) |> collect()
      ```

      **Option B: raw SQL (for complex operations):**
      ```r
      result_sql <- dbGetQuery(con, "
        SELECT
          YEAR(CAST(<date_col> AS DATE))  AS year,
          MONTH(CAST(<date_col> AS DATE)) AS month,
          <category_col>,
          COUNT(*)                         AS n,
          SUM(<value_col>)                 AS total
        FROM source_data
        WHERE <key_column> IS NOT NULL
        GROUP BY 1, 2, 3
        ORDER BY 1 DESC, 2 DESC
      ")
      ```

      Adapt column names to the actual schema.
      Report: transformation SQL and row count of result.
    gate: Review
    output: transform_query

  - id: write-output
    requires: [build-transformations]
    inline-prompt: |
      Write the pipeline output to disk.

      Output format: {{params.output}}

      **Parquet (recommended — columnar, compressed, fast):**
      ```r
      dbExecute(con, "
        COPY ({{ transformation_sql }}) TO 'output.parquet'
        (FORMAT PARQUET, COMPRESSION ZSTD, ROW_GROUP_SIZE 100000)
      ")

      # Or via dplyr + arrow:
      result |>
        collect() |>
        arrow::write_parquet("output.parquet", compression = "zstd")
      ```

      **Partitioned Parquet (for large datasets):**
      ```r
      result |>
        collect() |>
        arrow::write_dataset("output/", partitioning = c("year", "month"),
                             format = "parquet", compression = "zstd")
      ```

      **CSV:**
      ```r
      dbExecute(con, "
        COPY ({{ transformation_sql }}) TO 'output.csv' (HEADER, DELIMITER ',')
      ")
      ```

      **Arrow IPC / Feather:**
      ```r
      result |>
        collect() |>
        arrow::write_feather("output.arrow", compression = "zstd")
      ```

      Verify output:
      ```r
      arrow::read_parquet("output.parquet") |> dplyr::glimpse()
      file.info("output.parquet")$size / 1e6  # MB
      ```

      Report: output file path and size.
    output: output_path

  - id: close-cleanup
    requires: [write-output]
    inline-prompt: |
      Close the DuckDB connection and report pipeline summary.

      ```r
      duckdb::dbDisconnect(con, shutdown = TRUE)
      ```

      Pipeline summary:
      - Input: {{params.source}} ({{params.format}})
      - Output: {{state.output_path}} ({{params.output}})
      - Rows processed: (from transform step)
      - Output file size: (from write step)

      If persist is true (value: {{params.persist}}), the DuckDB database at
      `{{params.db-path}}` is retained on disk for reuse.

      Report: connection closed and pipeline summary.
    output: pipeline_summary

tags:
  - r
  - duckdb
  - arrow
  - parquet
  - data
  - pipeline
  - analytics

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER use collect() before all transformations are applied — keep data in DuckDB."
    severity: "error"
  - rule: "ALWAYS use ZSTD compression for Parquet output — it is faster than SNAPPY and smaller."
    severity: "warning"
  - rule: "ALWAYS call duckdb::dbDisconnect(con, shutdown = TRUE) to flush WAL and release the file lock."
    severity: "error"
  - rule: "NEVER use read.csv() or readr::read_csv() for large files — use DuckDB read_csv_auto() or arrow::open_dataset()."
    severity: "warning"
  - rule: "Use write_dataset() with partitioning for datasets > 1 GB."
    severity: "warning"
---

You are an R data engineer specialising in analytical pipelines with DuckDB and Arrow.
You process data at scale without loading it into R memory, using DuckDB's in-process
OLAP engine for SQL transformations and Arrow for zero-copy I/O.

## Rules

1. Keep data in DuckDB as long as possible — `collect()` only when needed for R operations.
2. Use `show_query()` to inspect generated SQL before running expensive transformations.
3. DuckDB reads Parquet, CSV, JSON, and Arrow natively — prefer these over R data frames for large files.
4. Use `read_parquet()` with glob patterns (`data/*.parquet`) to process multiple files as one table.
5. Use `write_dataset()` with `partitioning` for outputs > 1 GB to enable partition pruning.
6. DuckDB is embedded (no server) — one R process owns the connection; use a persistent file for sharing.
7. Prefer ZSTD compression for Parquet (better ratio than SNAPPY, faster than GZIP).
8. For streaming ingestion, use DuckDB's COPY FROM with Parquet streaming.
