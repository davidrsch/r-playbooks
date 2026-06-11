---
name: r-database-migrate
version: 1.0.0
context-mode: Fork
description: "Safe database schema migration for R projects: version-controlled migrations with DBI+dm, up/down scripts, seed data, dry-run validation against staging, and rollback procedures"
trigger: both
trigger-patterns:
  - "database migration *"
  - "schema migration *"
  - "db migration *"
  - "migrate database *"
  - "migrate schema *"
  - "database schema *"
  - "db schema *"
  - "add table *"
  - "alter table *"
  - "database change *"
argument-hint: "--action up|down|status|create [--name <migration>] [--target staging|production] [--dry-run true|false]"
parameters:
  action:
    type: String
    required: true
    enum: ["up", "down", "status", "create"]
    hint: "Migration action: up (apply), down (rollback), status (check), create (scaffold new migration)"
  name:
    type: String
    required: false
    hint: "Migration name in snake_case (required for 'create' action, e.g., 'add_user_email_index')"
  target:
    type: String
    required: false
    default: "staging"
    enum: ["staging", "production"]
    hint: "Target environment (production requires explicit Approve gates)"
  dry-run:
    type: Boolean
    required: false
    default: true
    hint: "Validate migration without applying (recommended: true for production)"
steps:
  - id: assess-current-schema
    inline-prompt: |
      Assess the current database schema and migration state.

      Action: {{params.action}}
      Migration name: {{params.name}}
      Target: {{params.target}}

      1. **Connect to the database:**
         ```r
         library(DBI)
         library(dm)

         # Read connection config (never hardcode credentials)
         config <- config::get(config = "{{params.target}}")

         con <- DBI::dbConnect(
           odbc::odbc(),
           driver   = config$driver,
           server   = config$server,
           database = config$database,
           uid      = config$uid,
           pwd      = config$pwd
         )
         # Or: con <- DBI::dbConnect(RPostgres::Postgres(), ...)
         # Or: con <- DBI::dbConnect(RSQLite::SQLite(), "db.sqlite")
         ```

      2. **Discover the current schema:**
         ```r
         # List all tables
         tables <- DBI::dbListTables(con)

         # Get column info for each table
         for (table in tables) {
           cols <- DBI::dbListFields(con, table)
           cat(sprintf("\n## %s (%d columns)\n", table, length(cols)))
           for (col in cols) {
             # Get column type via dbGetQuery with LIMIT 0 + dbColumnInfo
             res <- DBI::dbSendQuery(con, sprintf("SELECT \"%s\" FROM \"%s\" LIMIT 0", col, table))
             info <- DBI::dbColumnInfo(res)
             DBI::dbClearResult(res)
             cat(sprintf("  %s: %s\n", col, info$type))
           }
         }

         # Get indexes
         # PostgreSQL: SELECT * FROM pg_indexes WHERE schemaname = 'public'
         # SQLite: PRAGMA index_list('table_name')
         ```

      3. **Create a dm object for schema documentation:**
         ```r
         # Build a relational data model with dm
         schema_dm <- dm::dm_from_con(con, learn_keys = TRUE)

         # Visualize the schema
         dm::dm_draw(schema_dm)

         # Export schema for version control
         dm::dm_decompress(schema_dm)  # show all tables and keys
         ```

      4. **Check if a migrations table exists:**
         ```r
         if ("schema_migrations" %in% DBI::dbListTables(con)) {
           applied <- DBI::dbGetQuery(con, "SELECT * FROM schema_migrations ORDER BY applied_at")
           print(applied)
         } else {
           cat("No migrations table found — first run. Will create schema_migrations.\n")
         }
         ```

      5. **Identify the database engine:**
         ```r
         db_type <- class(con)[1]
         # Different engines need different SQL dialects for migrations
         # PostgreSQL: SERIAL, TEXT, TIMESTAMPTZ
         # SQLite: INTEGER PRIMARY KEY AUTOINCREMENT, TEXT, DATETIME
         # MySQL/MariaDB: INT AUTO_INCREMENT, TEXT, TIMESTAMP
         ```

      Report: current schema summary, applied migrations, and database engine.
    gate: Confirm
    output: schema_assessment

  - id: create-migration
    requires: [assess-current-schema]
    inline-prompt: |
      Scaffold a new migration file (when action is 'create').

      Action: {{params.action}}
      Migration name: {{params.name}}
      Current schema: {{state.schema_assessment}}

      If action is not 'create', skip this step.

      1. **Create the migrations directory:**
         ```
         migrations/
         ├── 001_initial_schema.sql
         ├── 002_add_user_email_index.sql
         ├── 003_create_orders_table.sql
         └── ...
         ```

      2. **Generate migration file** `migrations/<NNN>_{{params.name}}.sql`:
         Determine the next sequence number from existing migrations.

         ```sql
         -- Migration: {{params.name}}
         -- Created:  <date>
         -- Database: <engine from schema assessment>
         --
         -- Description: <what this migration does>

         -- ============================================================
         -- UP (apply migration)
         -- ============================================================

         -- Example: Add a new column
         ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE;

         -- Example: Create an index
         CREATE INDEX idx_users_email ON users (email);

         -- Example: Create a new table
         -- CREATE TABLE orders (
         --   id SERIAL PRIMARY KEY,
         --   user_id INTEGER NOT NULL REFERENCES users(id),
         --   amount DECIMAL(10, 2) NOT NULL,
         --   created_at TIMESTAMPTZ DEFAULT NOW()
         -- );

         -- ============================================================
         -- DOWN (rollback migration)
         -- ============================================================

         -- Reverse the UP operations in reverse order
         DROP INDEX IF EXISTS idx_users_email;
         ALTER TABLE users DROP COLUMN IF EXISTS email_verified;
         ```

      3. **Also create a paired R migration script** for complex logic:
         `migrations/<NNN>_{{params.name}}.R`:
         ```r
         # R-based migration for {{params.name}}
         # Handles data transformations that SQL alone cannot express

         migrate_up <- function(con) {
           # Data migration logic
           # e.g., transform existing data, populate new columns, etc.
           DBI::dbExecute(con, "UPDATE users SET email_verified = FALSE")
         }

         migrate_down <- function(con) {
           # Reverse the data transformation
         }
         ```

      4. **Migration file naming conventions:**
         - Sequential numbering: `001_`, `002_`, `003_`, ...
         - Descriptive snake_case names
         - `.sql` for DDL (schema changes)
         - `.R` for DML (data transformations)
         - Never renumber existing migrations — always append

      Report: migration file created at `migrations/<NNN>_{{params.name}}.sql`.
    gate: Confirm
    output: migration_file

  - id: validate-migration
    requires: [create-migration]
    inline-prompt: |
      Validate the migration against a staging database before applying.

      Dry-run: {{params.dry-run}}

      1. **Connect to staging database** (separate from production):
         ```r
         con_staging <- DBI::dbConnect(...)
         ```

      2. **Run migration in a transaction, then rollback (dry-run):**
         ```r
         validate_migration <- function(con, migration_file) {
           # Read the UP section of the migration
           sql <- readLines(migration_file)
           up_start <- grep("^-- UP", sql) + 1
           up_end <- grep("^-- DOWN", sql) - 1
           up_sql <- paste(sql[up_start:up_end], collapse = "\n")

           # Begin transaction
           DBI::dbBegin(con)

           tryCatch({
             # Execute each statement
             statements <- strsplit(up_sql, ";")[[1]]
             for (stmt in statements) {
               stmt <- trimws(stmt)
               if (nchar(stmt) > 0) {
                 DBI::dbExecute(con, stmt)
               }
             }

             # Verify the migration worked:
             # - Check new columns exist
             # - Check new tables exist
             # - Check indexes created
             # - Run any validation queries

             # ROLLBACK — this was a dry run
             DBI::dbRollback(con)

             cat("✅ Migration validated successfully\n")
             TRUE
           }, error = function(e) {
             DBI::dbRollback(con)
             cat(sprintf("❌ Migration validation FAILED: %s\n", e$message))
             FALSE
           })
         }

         validate_migration(con_staging, "{{state.migration_file}}")
         ```

      3. **Validation checks:**
         - [ ] SQL syntax is valid for the target database engine
         - [ ] No locking issues (long-running ALTER TABLE on large tables)
         - [ ] Indexes are created correctly
         - [ ] Foreign key constraints are valid
         - [ ] Default values are appropriate
         - [ ] NOT NULL columns have defaults or data backfill
         - [ ] DOWN migration reverses UP correctly (run UP, then DOWN, verify schema matches pre-migration state)

      4. **If dry-run fails:** fix the migration and re-validate. Do NOT proceed.

      Report: validation result (pass/fail with details).
    gate: Review
    output: validation_result

  - id: apply-migration
    requires: [validate-migration]
    inline-prompt: |
      Apply the migration to the target database.

      Target: {{params.target}}
      Dry-run: {{params.dry-run}}
      Validation: {{state.validation_result}}

      ⚠️ PRODUCTION WARNING: If target is 'production', this step requires
      extra caution. The Approve gate will be enforced.

      1. **Pre-flight checks:**
         - [ ] Backup confirmed? (production: always; staging: recommended)
         - [ ] Validation passed on staging? ({{state.validation_result}})
         - [ ] Estimated downtime communicated? (if applicable)
         - [ ] Rollback plan documented and tested?

      2. **For production migrations, create a backup:**
         ```r
         # PostgreSQL
         # pg_dump database_name > backup_$(date +%Y%m%d_%H%M%S).sql

         # SQLite
         # file.copy("db.sqlite", sprintf("backup_%s.sqlite", Sys.Date()))
         ```

      3. **Apply the migration:**
         ```r
         apply_migration <- function(con, migration_file, migration_name) {
           sql <- readLines(migration_file)
           up_start <- grep("^-- UP", sql) + 1
           up_end <- grep("^-- DOWN", sql) - 1
           up_sql <- paste(sql[up_start:up_end], collapse = "\n")

           DBI::dbBegin(con)

           tryCatch({
             statements <- strsplit(up_sql, ";")[[1]]
             for (stmt in statements) {
               stmt <- trimws(stmt)
               if (nchar(stmt) > 0) {
                 DBI::dbExecute(con, stmt)
               }
             }

             # Record migration in schema_migrations table
             # Create the table if it doesn't exist (first migration)
             DBI::dbExecute(con, "
               CREATE TABLE IF NOT EXISTS schema_migrations (
                 id SERIAL PRIMARY KEY,
                 name TEXT NOT NULL UNIQUE,
                 applied_at TIMESTAMPTZ DEFAULT NOW(),
                 applied_by TEXT DEFAULT CURRENT_USER
               )
             ")

             DBI::dbExecute(con,
               sprintf("INSERT INTO schema_migrations (name) VALUES ('%s')", migration_name)
             )

             DBI::dbCommit(con)
             cat(sprintf("✅ Migration '%s' applied successfully\n", migration_name))
             TRUE
           }, error = function(e) {
             DBI::dbRollback(con)
             cat(sprintf("❌ Migration FAILED: %s\n", e$message))
             cat("Database has been rolled back to pre-migration state.\n")
             FALSE
           })
         }

         apply_migration(con, "{{state.migration_file}}", "{{params.name}}")
         ```

      4. **Post-migration verification:**
         ```r
         # Verify the migration is recorded
         DBI::dbGetQuery(con, "SELECT * FROM schema_migrations ORDER BY applied_at DESC LIMIT 5")

         # Verify schema is as expected
         tables <- DBI::dbListTables(con)
         cat("Tables after migration:", paste(tables, collapse = ", "), "\n")

         # Run any post-migration smoke tests
         # e.g., SELECT COUNT(*) FROM new_table
         ```

      Report: migration applied successfully with verification.
    gate: Approve
    output: apply_result

  - id: rollback-migration
    requires: [assess-current-schema]
    inline-prompt: |
      Rollback the most recent migration (when action is 'down').

      Action: {{params.action}}

      If action is not 'down', skip this step.

      1. **Identify the last applied migration:**
         ```r
         last_migration <- DBI::dbGetQuery(con,
           "SELECT name FROM schema_migrations ORDER BY applied_at DESC LIMIT 1"
         )
         cat(sprintf("Rolling back: %s\n", last_migration$name))
         ```

      2. **Find and execute the DOWN section:**
         ```r
         migration_file <- sprintf("migrations/%s.sql", last_migration$name)
         # Extract the numeric prefix: e.g., "003_add_index" → "migrations/003_add_index.sql"

         sql <- readLines(migration_file)
         down_start <- grep("^-- DOWN", sql) + 1
         down_sql <- paste(sql[down_start:length(sql)], collapse = "\n")

         DBI::dbBegin(con)

         tryCatch({
           statements <- strsplit(down_sql, ";")[[1]]
           for (stmt in statements) {
             stmt <- trimws(stmt)
             if (nchar(stmt) > 0) {
               DBI::dbExecute(con, stmt)
             }
           }

           # Remove from migrations table
           DBI::dbExecute(con,
             sprintf("DELETE FROM schema_migrations WHERE name = '%s'", last_migration$name)
           )

           DBI::dbCommit(con)
           cat(sprintf("✅ Rolled back: %s\n", last_migration$name))
         }, error = function(e) {
           DBI::dbRollback(con)
           cat(sprintf("❌ Rollback FAILED: %s\n", e$message))
         })
         ```

      3. **Verify schema is restored:**
         Compare against the previous migration's expected schema.

      Report: rollback result.
    gate: Approve
    output: rollback_result

tags:
  - r
  - database
  - migration
  - dbi
  - schema
  - devops

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER apply a migration to production without a validated backup and an explicit Approve gate."
    severity: "error"
  - rule: "ALWAYS run migrations in a transaction — if any statement fails, rollback the entire migration."
    severity: "error"
  - rule: "NEVER modify an already-applied migration file — create a NEW migration to fix issues."
    severity: "error"
  - rule: "ALWAYS validate migrations against staging before production — staging must match production schema."
    severity: "error"
  - rule: "NEVER hardcode database credentials in migration scripts — use config::get() or environment variables."
    severity: "error"
  - rule: "ALWAYS include both UP and DOWN sections in every migration — rollback must be possible."
    severity: "warning"
  - rule: "Test that DOWN reverses UP exactly — run UP, then DOWN, and verify schema matches pre-migration state."
    severity: "warning"
---

You are an R database migration specialist. You manage safe, version-controlled
database schema changes using DBI and dm, following patterns from the Posit
professional database development ecosystem.

## Migration Philosophy

1. **EVERY MIGRATION IS REVERSIBLE**: Every UP must have a corresponding DOWN.
   If you can't reverse it, you shouldn't apply it.
2. **TRANSACTIONAL**: Migrations run in a database transaction. If anything
   fails, everything rolls back. No partially-applied migrations.
3. **VALIDATE FIRST**: Always dry-run against staging before production.
   Staging must mirror production schema.
4. **VERSION CONTROL**: Migration files live in the repository alongside code.
   Schema changes and code changes are deployed together.
5. **ONE CONCERN PER MIGRATION**: Each migration does one thing — add a column,
   create a table, add an index. Don't bundle unrelated changes.
6. **NEVER MODIFY HISTORY**: Applied migrations are immutable. Fix issues with
   a new migration, never by editing an applied one.

## Migration File Structure

```
migrations/
├── 001_initial_schema.sql    # CREATE TABLE statements
├── 001_initial_schema.R      # (optional) R-based data seeding
├── 002_add_user_index.sql    # ALTER TABLE, CREATE INDEX
├── 003_create_orders.sql     # New tables
└── schema_migrations         # Auto-created tracking table
```

## R Database Tools

- **DBI** (Posit/R Consortium) — Universal database interface. Use `dbExecute()`
  for DDL, `dbGetQuery()` for verification.
- **dm** (cynkra/Posit) — Relational data model management. `dm_from_con()` to
  discover schema, `dm_draw()` to visualize, `dm_decompress()` to inspect keys.
- **config** (Posit) — Environment-specific configuration. Never hardcode
  credentials in migration scripts.
- **pool** (Posit) — Connection pooling for applications (not needed for
  migration scripts which are short-lived).
- **odbc** (Posit) — ODBC driver interface for SQL Server, PostgreSQL, MySQL.
- **RPostgres**, **RSQLite**, **RMariaDB** — Native database drivers.

## Database Engine Considerations

| Engine | Auto-increment | Timestamp | Schema Namespace | Transaction DDL |
|--------|---------------|-----------|-----------------|-----------------|
| PostgreSQL | SERIAL / BIGSERIAL | TIMESTAMPTZ | schema.table | ✅ Full support |
| SQLite | INTEGER PRIMARY KEY AUTOINCREMENT | DATETIME | main.table | ✅ With caveats |
| MySQL/MariaDB | INT AUTO_INCREMENT | TIMESTAMP | database.table | ⚠️ Implicit commit on DDL |
| SQL Server | INT IDENTITY(1,1) | DATETIME2 | schema.table | ⚠️ Use with caution |
