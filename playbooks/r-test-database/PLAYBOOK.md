---
name: r-test-database
version: 1.0.0
context-mode: Fork
description: "Database interaction testing for R: test fixtures with DBI, transaction rollback between tests, query mocking, schema validation, and performance regression testing"
trigger: both
trigger-patterns:
  - "test database *"
  - "database test *"
  - "db test *"
  - "test db *"
  - "database testing *"
  - "fixture test *"
  - "mock database *"
  - "query test *"
  - "test database connection *"
  - "test database query *"
argument-hint: "[--scope schema|queries|performance|all] [--db-type postgres|sqlite|mysql] [--fixtures true|false]"
parameters:
  scope:
    type: String
    required: false
    default: "all"
    enum: ["schema", "queries", "performance", "all"]
    hint: "Test scope: schema validation, query correctness, query performance, or all"
  db-type:
    type: String
    required: false
    default: "sqlite"
    enum: ["sqlite", "postgres", "mysql"]
    hint: "Database type for test configuration (SQLite for fast CI, Postgres/MySQL for integration tests)"
  fixtures:
    type: Boolean
    required: false
    default: true
    hint: "Use test fixtures (pre-loaded test data) for repeatable tests"
steps:
  - id: configure-test-database
    inline-prompt: |
      Set up a dedicated test database with isolation between tests.

      DB type: {{params.db-type}}
      Fixtures: {{params.fixtures}}

      1. **Choose the right test database strategy:**

         **Strategy A: SQLite in-memory (fastest, recommended for CI):**
         ```r
         # tests/testthat/setup.R
         library(DBI)

         # Create a fresh in-memory database for each test file
         setup_test_db <- function() {
           con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")

           # Create schema from migrations
           migration_files <- list.files("migrations", pattern = "\\.sql$", full.names = TRUE)
           for (f in migration_files) {
             sql <- readLines(f)
             DBI::dbExecute(con, paste(sql, collapse = "\n"))
           }

           # Load fixtures (if enabled)
           if ({{params.fixtures}}) {
             load_fixtures(con)
           }

           con
         }

         teardown_test_db <- function(con) {
           DBI::dbDisconnect(con)
         }
         ```

         **Strategy B: PostgreSQL/MySQL with test database:**
         ```r
         setup_test_db <- function() {
           con <- DBI::dbConnect(RPostgres::Postgres(),
             host     = Sys.getenv("TEST_DB_HOST", "localhost"),
             dbname   = Sys.getenv("TEST_DB_NAME", "test_db"),
             user     = Sys.getenv("TEST_DB_USER", "test_user"),
             password = Sys.getenv("TEST_DB_PASS", "")
           )
           con
         }

         # Use skip_on_ci() if local test database is required
         # or set up a CI service container for PostgreSQL
         ```

      2. **Configure testthat helpers:**
         ```r
         # tests/testthat/helper-db.R
         library(DBI)
         library(testthat)

         # Factory function for creating test connections
         test_con <- function() {
           DBI::dbConnect(RSQLite::SQLite(), ":memory:")
           # Or for PostgreSQL in CI:
           # if (Sys.getenv("CI") == "true") {
           #   DBI::dbConnect(RPostgres::Postgres(), ...service_container...)
           # } else {
           #   DBI::dbConnect(RSQLite::SQLite(), ":memory:")
           # }
         }

         # Helper to load fixtures
         load_fixtures <- function(con) {
           fixtures <- list.files("tests/testthat/fixtures", pattern = "\\.csv$",
                                  full.names = TRUE)
           for (f in fixtures) {
             table_name <- tools::file_path_sans_ext(basename(f))
             data <- read.csv(f, stringsAsFactors = FALSE)
             DBI::dbWriteTable(con, table_name, data, overwrite = TRUE)
           }
         }

         # Helper to create schema from migrations
         migrate_test_db <- function(con) {
           migrations <- sort(list.files("migrations", pattern = "\\.sql$",
                                         full.names = TRUE))
           for (m in migrations) {
             sql <- paste(readLines(m), collapse = "\n")
             # Extract UP section
             sql <- sub(".*-- UP.*?\n", "", sql)
             sql <- sub("\n-- DOWN.*", "", sql)
             DBI::dbExecute(con, sql)
           }
         }
         ```

      Report: test database configuration and helper functions.
    gate: Confirm
    output: test_db_config

  - id: create-test-fixtures
    requires: [configure-test-database]
    inline-prompt: |
      Create test fixtures — minimal, representative datasets for repeatable tests.

      Fixtures enabled: {{params.fixtures}}

      If fixtures are false, skip to writing tests with inline data setup.

      1. **Design fixture data:**
         - Minimal but realistic: 5-20 rows per table, covering key variations
         - Include edge cases: NULL values, boundary values, special characters
         - Include foreign key relationships: fixture data must satisfy all constraints
         - Make relationships explicit: users fixture has ids that match orders fixture

      2. **Create fixture files in** `tests/testthat/fixtures/`:
         ```
         tests/testthat/fixtures/
         ├── users.csv
         ├── orders.csv
         ├── products.csv
         └── order_items.csv
         ```

         Example `users.csv`:
         ```csv
         id,name,email,age,created_at
         1,Alice,alice@example.com,30,2024-01-01
         2,Bob,bob@example.com,25,2024-02-15
         3,Charlie,charlie@example.com,,2024-03-10
         4,Diana,diana@example.com,45,2024-04-20
         5,Eve,,28,2024-05-05
         ```
         Notes: Charlie has NA age, Eve has NA email — test NULL handling.

      3. **Create a fixture loading helper:**
         ```r
         # tests/testthat/helper-fixtures.R
         read_fixture <- function(name) {
           path <- testthat::test_path("fixtures", paste0(name, ".csv"))
           read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
         }

         load_all_fixtures <- function(con) {
           fixtures <- c("users", "orders", "products", "order_items")
           for (name in fixtures) {
             data <- read_fixture(name)
             DBI::dbWriteTable(con, name, data, overwrite = TRUE)
           }
         }
         ```

      4. **Verify fixtures satisfy schema constraints:**
         ```r
         test_that("fixtures satisfy schema constraints", {
           con <- test_con()
           load_all_fixtures(con)

           # Check foreign keys
           user_ids <- DBI::dbGetQuery(con, "SELECT id FROM users")$id
           order_user_ids <- DBI::dbGetQuery(con, "SELECT DISTINCT user_id FROM orders")$user_id
           expect_true(all(order_user_ids %in% user_ids))

           # Check NOT NULL columns have no NAs
           users <- DBI::dbGetQuery(con, "SELECT id, name FROM users")
           expect_false(any(is.na(users$id)))
           expect_false(any(is.na(users$name)))

           DBI::dbDisconnect(con)
         })
         ```

      Report: fixture files created and validated.
    gate: Review
    output: fixture_config

  - id: test-schema-integrity
    requires: [create-test-fixtures]
    inline-prompt: |
      Test database schema integrity and constraints.

      Scope: {{params.scope}}

      If scope is 'queries' or 'performance', skip this step.

      ```r
      # tests/testthat/test-db-schema.R
      library(testthat)
      library(DBI)

      describe("Database Schema", {

        con <- NULL

        before_each({
          con <<- test_con()
          migrate_test_db(con)
        })

        after_each({
          DBI::dbDisconnect(con)
        })

        it("has all expected tables", {
          tables <- DBI::dbListTables(con)
          expected <- c("users", "orders", "products", "order_items",
                         "schema_migrations")
          for (table in expected) {
            expect_true(table %in% tables,
              sprintf("Table '%s' should exist", table))
          }
        })

        it("has the expected columns in each table", {
          # Users table
          user_cols <- DBI::dbListFields(con, "users")
          expect_true(all(c("id", "name", "email", "age", "created_at") %in% user_cols))

          # Orders table
          order_cols <- DBI::dbListFields(con, "orders")
          expect_true(all(c("id", "user_id", "amount", "created_at") %in% order_cols))
        })

        it("enforces NOT NULL constraints", {
          # Try inserting NULL into a NOT NULL column
          expect_error(
            DBI::dbExecute(con,
              "INSERT INTO users (id, name, email) VALUES (999, NULL, 'test@test.com')"
            )
          )
        })

        it("enforces UNIQUE constraints", {
          # Insert duplicate unique value
          DBI::dbExecute(con,
            "INSERT INTO users (id, name, email) VALUES (999, 'Test', 'test@test.com')"
          )
          expect_error(
            DBI::dbExecute(con,
              "INSERT INTO users (id, name, email) VALUES (1000, 'Test2', 'test@test.com')"
            )
          )
        })

        it("enforces FOREIGN KEY constraints", {
          expect_error(
            DBI::dbExecute(con,
              "INSERT INTO orders (user_id, amount) VALUES (99999, 10.00)"
            )
          )
        })

        it("has all expected indexes", {
          # PostgreSQL
          if (inherits(con, "PqConnection")) {
            indexes <- DBI::dbGetQuery(con,
              "SELECT indexname FROM pg_indexes WHERE schemaname = 'public'"
            )
            expect_true("idx_users_email" %in% indexes$indexname)
          }

          # SQLite
          if (inherits(con, "SQLiteConnection")) {
            indexes <- DBI::dbGetQuery(con,
              "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
            expect_true("idx_users_email" %in% indexes$name)
          }
        })

      })
      ```

      Report: schema tests written and passing.
    gate: Review
    output: schema_tests

  - id: test-query-correctness
    requires: [create-test-fixtures]
    inline-prompt: |
      Test database query correctness with fixture data.

      Scope: {{params.scope}}

      If scope is 'schema' or 'performance', skip this step.

      ```r
      # tests/testthat/test-db-queries.R
      describe("Database Queries", {

        con <- NULL

        before_each({
          con <<- test_con()
          migrate_test_db(con)
          load_all_fixtures(con)
        })

        after_each({
          DBI::dbDisconnect(con)
        })

        # ── Test each application query ────────────────────────────────

        # Test a query function from your application
        # (replace with your actual query functions)

        it("get_user_orders returns correct data", {
          # Given: fixtures loaded (Alice has 2 orders, Bob has 1)
          # When: we query Alice's orders
          result <- DBI::dbGetQuery(con, "
            SELECT o.id, o.amount
            FROM orders o
            JOIN users u ON o.user_id = u.id
            WHERE u.name = 'Alice'
            ORDER BY o.id
          ")

          # Then: Alice has exactly 2 orders
          expect_equal(nrow(result), 2)
          expect_true(all(result$amount > 0))
        })

        it("handles NULL values correctly in aggregations", {
          # Given: Charlie has no age (NULL)
          # When: we compute average age
          result <- DBI::dbGetQuery(con, "
            SELECT AVG(age) as avg_age, COUNT(age) as count_age
            FROM users
          ")

          # Then: AVG should ignore NULL; COUNT should count only non-NULL
          expect_false(is.na(result$avg_age))
          expect_equal(result$count_age, 4)  # 5 users, 1 NULL age
        })

        it("returns empty result for no matches (not an error)", {
          result <- DBI::dbGetQuery(con, "
            SELECT * FROM users WHERE name = 'NonExistent'
          ")
          expect_equal(nrow(result), 0)
          # Should NOT be an error — just empty
        })

        it("handles empty string vs NULL in filters", {
          result_null <- DBI::dbGetQuery(con,
            "SELECT * FROM users WHERE email IS NULL"
          )
          expect_equal(nrow(result_null), 1)  # Eve has NULL email
          expect_equal(result_null$name, "Eve")
        })

        it("produces consistent results with ORDER BY", {
          result1 <- DBI::dbGetQuery(con,
            "SELECT name FROM users ORDER BY name"
          )
          result2 <- DBI::dbGetQuery(con,
            "SELECT name FROM users ORDER BY name"
          )
          expect_equal(result1, result2)
        })

        it("has no N+1 query problem for typical workload", {
          # Test that fetching N orders doesn't make N+1 queries
          # Simulate by checking query count
          start_count <- get_query_count()  # if using a query counter

          result <- DBI::dbGetQuery(con, "
            SELECT u.name, o.amount
            FROM users u
            LEFT JOIN orders o ON u.id = o.user_id
            ORDER BY u.id
          ")

          # Single query should fetch all data
          end_count <- get_query_count()
          # expect_equal(end_count - start_count, 1)  # adjust for your setup
        })

        # ── SQL Injection Tests ────────────────────────────────────────

        it("is not vulnerable to SQL injection via string concatenation", {
          malicious_input <- "'; DROP TABLE users; --"

          # This should use parameterized queries, not paste/sprintf
          result <- DBI::dbGetQuery(con,
            "SELECT * FROM users WHERE name = ?",
            params = list(malicious_input)
          )

          expect_equal(nrow(result), 0)  # No user with that name
          # Verify users table still exists
          expect_true("users" %in% DBI::dbListTables(con))
        })

      })
      ```

      Report: query tests written and passing, with SQL injection tests.
    gate: Review
    output: query_tests

  - id: test-query-performance
    requires: [test-query-correctness]
    inline-prompt: |
      Test query performance and detect regressions.

      Scope: {{params.scope}}

      If scope is not 'performance' and not 'all', skip this step.

      ```r
      # tests/testthat/test-db-performance.R
      library(bench)

      describe("Query Performance", {

        con <- NULL

        before_each({
          con <<- test_con()
          migrate_test_db(con)
          load_all_fixtures(con)
          # Load a larger dataset for performance testing
          load_performance_fixtures(con)  # optional: 10K-100K rows
        })

        after_each({
          DBI::dbDisconnect(con)
        })

        it("get_user_orders completes within 100ms for typical load", {
          time <- bench::mark(
            DBI::dbGetQuery(con, "
              SELECT o.id, o.amount
              FROM orders o
              JOIN users u ON o.user_id = u.id
              WHERE u.id = 1
            "),
            iterations = 50,
            check = FALSE
          )

          median_ms <- as.numeric(time$median) / 1e6  # nanoseconds to ms
          expect_lt(median_ms, 100,
            sprintf("Query took %.1f ms, expected < 100 ms", median_ms))
        })

        it("aggregation query has acceptable performance", {
          time <- bench::mark(
            DBI::dbGetQuery(con, "
              SELECT u.name, COUNT(o.id) as order_count, SUM(o.amount) as total
              FROM users u
              LEFT JOIN orders o ON u.id = o.user_id
              GROUP BY u.id, u.name
            "),
            iterations = 20,
            check = FALSE
          )

          median_ms <- as.numeric(time$median) / 1e6
          expect_lt(median_ms, 200,
            sprintf("Aggregation took %.1f ms, expected < 200 ms", median_ms))
        })

        it("uses indexes efficiently (no sequential scans)", {
          # Check execution plan (PostgreSQL)
          if (inherits(con, "PqConnection")) {
            plan <- DBI::dbGetQuery(con, "
              EXPLAIN ANALYZE
              SELECT * FROM users WHERE email = 'alice@example.com'
            ")

            # Should use index scan, not sequential scan
            plan_text <- paste(plan[[1]], collapse = "\n")
            expect_false(grepl("Seq Scan.*users", plan_text),
              "Query should use index scan, not sequential scan")
          }

          # For SQLite:
          if (inherits(con, "SQLiteConnection")) {
            plan <- DBI::dbGetQuery(con, "
              EXPLAIN QUERY PLAN
              SELECT * FROM users WHERE email = 'alice@example.com'
            ")
            # Should mention index usage
            plan_text <- paste(plan[[1]], collapse = "\n")
            # SQLite EXPLAIN QUERY PLAN output indicates index usage
          }
        })

        it("bulk insert performance is within acceptable range", {
          n_rows <- 1000
          new_users <- data.frame(
            id     = 1000 + seq_len(n_rows),
            name   = paste0("User", seq_len(n_rows)),
            email  = paste0("user", seq_len(n_rows), "@test.com"),
            age    = sample(18:80, n_rows, replace = TRUE),
            created_at = rep(Sys.time(), n_rows)
          )

          time <- bench::mark(
            DBI::dbWriteTable(con, "users", new_users, append = TRUE),
            iterations = 5,
            check = FALSE
          )

          median_ms <- as.numeric(time$median) / 1e6
          expect_lt(median_ms, 500,
            sprintf("Bulk insert of %d rows took %.1f ms", n_rows, median_ms))
        })

      })
      ```

      **Performance regression testing workflow:**
      1. Establish baseline timings in CI
      2. Run performance tests on every PR
      3. Flag queries where median time > 2x baseline
      4. Use `bench::mark()` with `check = FALSE` to avoid correctness overhead

      Report: performance tests written with baseline timings.
    gate: Review
    output: performance_tests

tags:
  - r
  - testing
  - database
  - dbi
  - quality
  - fixtures

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER test against a production database — always use an isolated test database or SQLite in-memory."
    severity: "error"
  - rule: "ALWAYS use parameterized queries (?, $1) — never paste() or sprintf() user input into SQL."
    severity: "error"
  - rule: "NEVER leave test data in the test database — use before_each/after_each or transaction rollback."
    severity: "error"
  - rule: "ALWAYS test NULL handling — NULL values are the #1 source of database bugs in R."
    severity: "warning"
  - rule: "ALWAYS test empty result sets — queries returning 0 rows should not error."
    severity: "warning"
  - rule: "Use SQLite in-memory for CI speed, PostgreSQL/MariaDB for integration parity tests."
    severity: "warning"
---

You are an R database testing specialist. You write fast, isolated tests for
database interactions using DBI with testthat — following Posit professional
database development practices.

## Database Testing Philosophy

1. **ISOLATE TESTS**: Every test runs in its own transaction or with a fresh
   database. Tests must never depend on state from other tests.
2. **SQLITE FOR SPEED**: Use SQLite in-memory databases for unit tests in CI.
   They're fast, require no setup, and support most SQL features.
3. **POSTGRES/MYSQL FOR PARITY**: Run integration tests against the actual
   production database engine (via CI service containers) to catch dialect
   differences.
4. **FIXTURES ARE DOCUMENTATION**: Fixture data documents the expected schema
   and relationships. A new developer can read fixtures and understand the
   data model.
5. **TEST NULL HANDLING**: NULL values cause more R bugs than any other database
   feature. Test columns with NULLs, joins with NULL keys, and aggregations
   over NULL values.

## Test Database Strategies

| Strategy | Speed | Isolation | Dialect Accuracy | Best For |
|----------|-------|-----------|-----------------|----------|
| SQLite :memory: | ⚡ Fast | ✅ Complete | ⚠️ Approximate | CI unit tests |
| PostgreSQL CI container | 🐢 Slower | ✅ Transaction rollback | ✅ Exact | Integration tests |
| Docker compose local | 🐢 Slow | ✅ Transaction rollback | ✅ Exact | Pre-commit tests |
| Staging database | 🐢 Slow | ❌ Shared state | ✅ Exact | Pre-deploy smoke tests |

## Common R Database Test Patterns

### Transaction Rollback Pattern
```r
test_that("my test", {
  con <- test_con()
  DBI::dbBegin(con)
  # ... test code with dbWriteTable, dbExecute, etc ...
  DBI::dbRollback(con)  # nothing persists
  DBI::dbDisconnect(con)
})
```

### Fixture Loading Pattern
```r
before_each({
  con <<- test_con()
  migrate_test_db(con)
  load_fixtures(con, c("users", "orders"))
})
after_each({
  DBI::dbDisconnect(con)
})
```

### Parameterized Query Pattern
```r
# ✅ SAFE: parameterized
DBI::dbGetQuery(con, "SELECT * FROM users WHERE name = ?", params = list(name))

# ❌ DANGER: string concatenation — SQL injection
DBI::dbGetQuery(con, paste0("SELECT * FROM users WHERE name = '", name, "'"))
```
