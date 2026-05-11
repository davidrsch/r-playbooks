---
name: r-config-env
version: 1.0.0
context-mode: Fork
description: Set up environment-specific configuration with the config package
trigger: both
trigger-patterns:
  - "add config *"
  - "setup config *"
  - "configure environment *"
argument-hint: "--target <shiny|plumber|targets|package> [--environments <default,development,production>]"
parameters:
  target:
    type: String
    required: true
    hint: "Application type: shiny, plumber, targets, or package"
  environments:
    type: String
    required: false
    default: "default,development,production"
    hint: "Comma-separated environment names"
steps:
  - id: create-config-yml
    inline-prompt: |
      Create a config.yml file in the project root.

      Use the `config` package conventions:
      1. `default` section: base configuration inherited by all environments
      2. Environment-specific sections override defaults
      3. Use `!expr` for R code evaluation
      4. Use `Sys.getenv()` for secrets: NEVER hardcode credentials
      5. Nested YAML structure for organized settings

      Generate a config.yml tailored for {{params.target}}:

      **For shiny**:
      ```yaml
      default:
        app:
          title: "My App"
          port: 3838
        database:
          host: "localhost"
          port: 5432
          name: "app_db"
      production:
        database:
          host: !expr Sys.getenv("DB_HOST", "prod-db.example.com")
          port: !expr as.integer(Sys.getenv("DB_PORT", "5432"))
        logging:
          level: "INFO"
      ```

      **For plumber**:
      ```yaml
      default:
        api:
          host: "0.0.0.0"
          port: 8000
        rate_limit:
          requests_per_minute: 60
      ```

      **For targets**:
      ```yaml
      default:
        pipeline:
          parallel: true
          workers: 4
        storage:
          format: "parquet"
      ```

      **For package**:
      ```yaml
      default:
        api:
          base_url: "https://api.example.com"
          timeout: 30
      ```

      Project root: {{env.CWD}}
    output: config-file
    gate: Review

  - id: setup-renv-config
    requires: [create-config-yml]
    inline-prompt: |
      Warning: Unsetting `R_CONFIG_ACTIVE` will revert to the `default` environment. Ensure your deployment platform sets this variable persistently.

      Set up environment-specific dependency management:

      1. Run `renv::activate()` if not already active
      2. Create `renv/profiles/` directory
      3. Add each environment profile with `renv::profile("{{params.environments}}")`

      Update .Renviron to set the active config:
      ```
      R_CONFIG_ACTIVE=default
      ```

      Add .Renviron.production with:
      ```
      R_CONFIG_ACTIVE=production
      ```

      Add gitignore for .Renviron files:
      ```
      echo ".Renviron.production" >> .gitignore && echo ".Renviron.local" >> .gitignore
      ```

      Project root: {{env.CWD}}
    output: renv-config

  - id: add-config-accessors
    requires: [setup-renv-config]
    inline-prompt: |
      Create a helper file to load and access configuration.

      Include these accessor functions:
      ```r
      #' @title Load application configuration
      #' @return Config list for the active environment
      #' @export
      load_config <- function() {
        config::get()
      }

      #' @title Get a specific config value
      #' @param ... Key path (e.g., "database", "host")
      #' @return Config value
      #' @export
      get_config <- function(...) {
        config::get(file = "config.yml", ...)
      }
      ```

      Create or update the main entry point to call `load_config()` early:
      - shiny: in global.R or app.R, before ui/server
      - plumber: in entrypoint.R, before pr()
      - targets: in _targets.R, before tar_option_set()
      - package: in .onLoad() or the main function

      Add a startup message showing which config is active:
      ```r
      message("Config active: ", Sys.getenv("R_CONFIG_ACTIVE", "default"))
      message("Is default? ", config::is_active("default"))
      message("Is production? ", config::is_active("production"))
      ```

      Project root: {{env.CWD}}
    output: config-accessors

  - id: verify-config
    requires: [add-config-accessors]
    inline-prompt: |
      Verify the configuration works:

      1. Check default config: `Sys.setenv(R_CONFIG_ACTIVE = "default"); config::get()`
      2. Check production config: `Sys.setenv(R_CONFIG_ACTIVE = "production"); config::get()`
      3. Verify all environment sections inherit from default
      4. Check that `!expr` values evaluate correctly
      5. Confirm no hardcoded secrets in the config file

      Run: `grep -i "password\|secret\|token\|api_key" config.yml`: there should be NO matches (only `!expr Sys.getenv()` references).

      Production config validation checklist:
      - [ ] `R_CONFIG_ACTIVE=production` is set in deployment environment
      - [ ] All `!expr Sys.getenv()` calls reference existing env vars
      - [ ] Production database URLs/hosts are correct
      - [ ] Logging level is appropriate for production (INFO or WARN)
      - [ ] No development-only endpoints or features enabled
      - [ ] `.Renviron.production` is not committed to git

      Report: environments loaded, inheritance verified, secret scan result.

      Project root: {{env.CWD}}
    output: verification-report

tags:
  - r
  - config
  - deployment
  - production

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER log secrets, passwords, tokens, or credentials."
    severity: "error"
  - rule: "ALWAYS include service name and trace ID in log entries."
    severity: "warning"
  - rule: "Use structured logging (JSON format) for production."
    severity: "warning"
  - rule: "Never store config in source code — use environment variables."
    severity: "error"
---

You are an expert in R deployment configuration and environment management.
Use the `config` package (r-lib) to manage environment-specific settings.

## Rules

1. `default` is the base: all other environments inherit from it.
2. Environment sections override: `production` overrides only what differs from `default`.
3. Nest related settings: group by domain (database._, api._, logging.\*).
4. Use `!expr` for dynamic values: R code that runs at config load time.
5. Secrets via env vars ONLY: `password: !expr Sys.getenv("DB_PASS")`.
6. `R_CONFIG_ACTIVE` controls which environment config is loaded.
7. Set `R_CONFIG_ACTIVE` in .Renviron, Dockerfile, or deployment platform.
8. NEVER hardcode credentials in config.yml: use `!expr Sys.getenv()`.
9. NEVER use different config files per environment: use one file with sections.
10. NEVER use `source()` to load config: use `config::get()`.
11. NEVER use `.Rprofile` for config values: use `.Renviron`.

## Access Pattern

```r
config <- config::get()
db_host <- config$database$host
api_key <- Sys.getenv("API_KEY")  # Secrets from env, NOT config
```

## Environment Strategy

- `default`: local development (localhost, debug logging)
- `development`: shared dev environment
- `staging`: pre-production testing
- `production`: live deployment (INFO+ logging, real credentials from env vars)
