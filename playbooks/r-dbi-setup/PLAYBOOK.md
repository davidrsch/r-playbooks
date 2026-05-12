---
name: r-dbi-setup
version: 1.0.0
context-mode: Fork
description: "Set up a DBI database connection with connection pooling ({pool}), parameterised queries, and safe credential management via environment variables"
trigger: both
trigger-patterns:
  - "database *"
  - "dbi *"
  - "sql *"
  - "connect database *"
  - "database connection *"
  - "postgres *"
  - "mysql *"
  - "sqlite *"
argument-hint: "--driver postgres|mysql|sqlite|odbc [--pool true|false] [--host <host>] [--dbname <db>]"
parameters:
  driver:
    type: String
    required: true
    enum: ["postgres", "mysql", "sqlite", "odbc"]
    hint: "Database driver to use"
  pool:
    type: Boolean
    required: false
    default: true
    hint: "Use {pool} for connection pooling (recommended for Shiny/Plumber apps)"
  host:
    type: String
    required: false
    hint: "Database host (leave blank for SQLite or env-var-based config)"
  dbname:
    type: String
    required: false
    hint: "Database name or SQLite file path"
  schema:
    type: String
    required: false
    hint: "Default schema to use (PostgreSQL/MySQL)"
steps:
  - id: install-packages
    inline-prompt: |
      Install the required DBI driver packages.

      Driver: {{params.driver}}

      ```r
      pkgs <- c("DBI")

      if ("{{params.driver}}" == "postgres") {
        pkgs <- c(pkgs, "RPostgres")
      } else if ("{{params.driver}}" == "mysql") {
        pkgs <- c(pkgs, "RMySQL")
      } else if ("{{params.driver}}" == "sqlite") {
        pkgs <- c(pkgs, "RSQLite")
      } else if ("{{params.driver}}" == "odbc") {
        pkgs <- c(pkgs, "odbc")
      }

      if ({{params.pool}}) pkgs <- c(pkgs, "pool")

      pak::pak(pkgs)
      ```

      Report: packages installed successfully.
    output: packages_installed

  - id: configure-credentials
    requires: [install-packages]
    inline-prompt: |
      Set up secure credential management using environment variables.

      NEVER hardcode credentials in R scripts. Use one of:

      **Option A: .Renviron (local development)**
      Add to `~/.Renviron` (never commit this file):
      ```
      DB_HOST={{params.host}}
      DB_NAME={{params.dbname}}
      DB_USER=your_username
      DB_PASSWORD=your_password
      DB_PORT=5432
      DB_SCHEMA={{params.schema}}
      ```
      Reload: `readRenviron("~/.Renviron")`

      **Option B: {config} package (multi-environment)**
      Create `config.yml`:
      ```yaml
      default:
        database:
          host: !expr Sys.getenv("DB_HOST")
          dbname: !expr Sys.getenv("DB_NAME")
          user: !expr Sys.getenv("DB_USER")
          password: !expr Sys.getenv("DB_PASSWORD")
          port: 5432

      production:
        inherits: default
        database:
          host: prod-db.example.com
      ```

      **Option C: {keyring} (secure OS keychain)**
      ```r
      keyring::key_set("db_password", username = "myapp")
      # Retrieve: keyring::key_get("db_password", username = "myapp")
      ```

      Verify `.Renviron` and `config.yml` are in `.gitignore`.
      Report: credential strategy chosen and configured.
    gate: Confirm
    output: credential_strategy

  - id: create-connection
    requires: [configure-credentials]
    inline-prompt: |
      Create a database connection helper function.

      Driver: {{params.driver}}
      Pool: {{params.pool}}

      Create `R/db_connection.R` (or `db_connection.R` for scripts):

      **Without pool:**
      ```r
      db_connect <- function() {
        DBI::dbConnect(
          drv = {{driver_class}},
          host     = Sys.getenv("DB_HOST"),
          dbname   = Sys.getenv("DB_NAME"),
          user     = Sys.getenv("DB_USER"),
          password = Sys.getenv("DB_PASSWORD"),
          port     = as.integer(Sys.getenv("DB_PORT", "5432"))
        )
      }

      db_disconnect <- function(con) DBI::dbDisconnect(con)
      ```

      Use `{{driver_class}}`:
      - postgres → `RPostgres::Postgres()`
      - mysql    → `RMySQL::MySQL()`
      - sqlite   → `RSQLite::SQLite()`
      - odbc     → `odbc::odbc(), dsn = Sys.getenv("DB_DSN")`

      **With pool (for Shiny/Plumber):**
      ```r
      db_pool <- function() {
        pool::dbPool(
          drv      = {{driver_class}},
          host     = Sys.getenv("DB_HOST"),
          dbname   = Sys.getenv("DB_NAME"),
          user     = Sys.getenv("DB_USER"),
          password = Sys.getenv("DB_PASSWORD"),
          port     = as.integer(Sys.getenv("DB_PORT", "5432")),
          minSize  = 1,
          maxSize  = 10,
          idleTimeout = 300
        )
      }

      # In app shutdown: pool::poolClose(pool)
      ```

      Test the connection:
      ```r
      con <- db_connect()
      DBI::dbIsValid(con)
      DBI::dbListTables(con)
      DBI::dbDisconnect(con)
      ```

      Report: connection function created and connection verified.
    gate: Review
    output: connection_fn

  - id: parameterised-queries
    requires: [create-connection]
    inline-prompt: |
      Add helper functions for safe, parameterised query patterns.

      Create query helpers in `R/db_queries.R`:

      ```r
      # SAFE: parameterised query (prevents SQL injection)
      db_query <- function(con, sql, params = list()) {
        DBI::dbGetQuery(con, DBI::sqlInterpolate(con, sql, .dots = params))
      }

      # SAFE: insert rows from a data frame
      db_insert <- function(con, table, df, append = TRUE) {
        DBI::dbWriteTable(con, table, df, append = append, row.names = FALSE)
      }

      # SAFE: execute a statement (DDL or DML)
      db_execute <- function(con, sql, params = list()) {
        DBI::dbExecute(con, DBI::sqlInterpolate(con, sql, .dots = params))
      }

      # SAFE: read a full table
      db_read_table <- function(con, table) {
        DBI::dbReadTable(con, table)
      }
      ```

      Usage examples:
      ```r
      # Correct: parameterised
      db_query(con, "SELECT * FROM users WHERE id = ?id", params = list(id = 42))

      # WRONG: never do this
      # DBI::dbGetQuery(con, paste("SELECT * FROM users WHERE id =", user_id))
      ```

      If using dplyr + dbplyr (ORM-style):
      ```r
      tbl(con, "users") |>
        filter(id == 42) |>
        collect()
      ```

      Report: query helpers created.
    output: query_helpers

  - id: connection-test
    requires: [parameterised-queries]
    inline-prompt: |
      Run a comprehensive connection test.

      ```r
      con <- db_connect()

      # 1. Verify connection is valid
      stopifnot(DBI::dbIsValid(con))

      # 2. List tables
      tables <- DBI::dbListTables(con)
      cat("Tables found:", length(tables), "\n")
      cat(paste("-", tables, collapse = "\n"), "\n")

      # 3. Run a trivial safe query
      result <- db_query(con, "SELECT 1 AS ping")
      stopifnot(result$ping == 1)
      cat("Query ping: OK\n")

      # 4. Check schema if specified
      if (nchar("{{params.schema}}") > 0) {
        DBI::dbExecute(con, paste0("SET search_path TO ", "{{params.schema}}"))
      }

      DBI::dbDisconnect(con)
      cat("Connection test PASSED\n")
      ```

      Report: all checks pass.
    gate: Review
    output: test_results

tags:
  - r
  - database
  - dbi
  - sql
  - data

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER hardcode passwords or connection strings in R source files."
    severity: "error"
  - rule: "ALWAYS use DBI::sqlInterpolate() or parameterised queries — never paste() SQL."
    severity: "error"
  - rule: "NEVER commit .Renviron, config.yml with secrets, or .RData containing connection objects."
    severity: "error"
  - rule: "ALWAYS call DBI::dbDisconnect() or pool::poolClose() when done."
    severity: "warning"
  - rule: "Use {pool} for any long-running process (Shiny, Plumber) to manage connection lifecycle."
    severity: "warning"
---

You are an R database engineer following DBI best practices.
You prevent SQL injection, manage credentials safely, and use connection pooling
where appropriate.

## Rules

1. NEVER build SQL strings with `paste()`, `sprintf()`, or `glue()` from user input.
2. ALWAYS use `DBI::sqlInterpolate()` with `?name` placeholders for user-supplied values.
3. Store ALL credentials in environment variables or the OS keychain, never in code.
4. Use `{pool}` for Shiny and Plumber apps — they outlive a single request cycle.
5. Use `tryCatch()` around connection setup to provide helpful error messages.
6. Use `dbplyr` / `dplyr` for complex queries — it generates safe SQL automatically.
7. Index your filter columns in the database for query performance.
8. Call `DBI::dbDisconnect()` in `on.exit()` to ensure cleanup on errors.
