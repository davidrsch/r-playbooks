# 🎯 R Playbooks

A collection of **75 AI-assisted playbooks** for common R development workflows: package development, testing, Shiny apps, data pipelines, deployment, APIs, observability, ML, cloud, notifications, and more. Includes orchestrators, planners, auditors, auth, model monitoring, contract testing, load testing, database migration, Kubernetes deployment, cloud SDKs, Observable/WebR integration, and meta-playbooks for end-to-end feature delivery.

> [**Browse the playbook gallery**](https://davidrsch.github.io/r-playbooks/)

## Runtime

These playbooks are designed for the **[playbooks-mcp](https://github.com/davidrsch/playbooks-mcp)** MCP server — a TypeScript/Node.js server that executes PLAYBOOK.md files with typed parameters, step dependencies, human-in-the-loop gates, and checkpoint/resume. Any MCP-compatible agent (Claude, Cline, Continue, Cursor) can use these playbooks once the server is installed.

## What are playbooks?

Playbooks are structured, step-by-step guides designed for AI coding agents. Each playbook defines a specific R development task with clearly scoped steps, inputs, outputs, validations, and safety boundaries. They help ensure AI-assisted coding is predictable, repeatable, and aligned with best practices.

## Categories

| Category                 | Playbooks                                                                                                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 📦 **Package Dev**       | `r-init-package`, `r-pkg-add-function`, `r-pkg-check`, `r-pkg-release`, `r-pkgcheck-review`, `r-pkgdown-site`, `r-pak-lockfile`, `r-renv-manage`, `r-cran-submission`, `r-dependency-upgrade` |
| 🧪 **Testing & QA**      | `r-lint`, `r-tdd-feature`, `r-tdd-bugfix`, `r-bdd-feature`, `r-testthat-snapshot`, `r-code-review`, `r-package-audit`, `r-property-test`, `r-mutation-test`, `r-test-database` |
| ✨ **Shiny Apps**        | `r-init-shiny`, `r-shiny-module`, `r-shiny-theme-bslib`, `r-shiny-e2e-test`, `r-rhino-init`, `r-rhino-add-module`, `r-rhino-build`, `r-rhino-check`, `r-rhino-test`, `r-shiny-auth`, `r-shiny-perf` |
| 🎯 **Data Pipelines**    | `r-init-targets`, `r-targets-add-target`, `r-targets-branching`, `r-targets-crew`, `r-schedule-pipeline` |
| 🚀 **Deploy & DevOps**   | `r-docker-build`, `r-connect-deploy`, `r-vetiver-deploy`, `r-ci-gha`, `r-deploy-kubernetes`, `r-cloud-sdk` |
| 🔌 **APIs**              | `r-init-plumber`, `r-api-endpoint`, `r-httr2-client`, `r-api-testing` |
| 📊 **Observability**     | `r-logger-setup`, `r-otel-instrument`, `r-profile`, `r-debug`, `r-performance-benchmark` |
| 🛡️ **Data & Validation** | `r-data-validate`, `r-pointblank-agent`, `r-dbi-setup`, `r-duckdb-pipeline`, `r-database-migrate` |
| 🏗️ **Architecture**      | `r-box-module`, `r-s7-class`, `r-refactor`, `r-async-mirai`, `r-workflow-feature`, `r-plan-feature`, `r-playbook-create` |
| 🔔 **Notifications**     | `r-notification` |
| 🔒 **Config & Security** | `r-config-env`, `r-security` |
| 📄 **Reports**           | `r-quarto-render`, `r-quarto-website`, `r-quarto-dashboard`, `r-observable` |
| 🤖 **ML & Tidymodels**   | `r-tidymodels-workflow`, `r-tidymodels-tune`, `r-model-monitor`, `r-ml-init`, `r-ml-validate` |

### Workflow Playbooks (New)

These playbooks orchestrate end-to-end development workflows, plan before coding, and audit quality:

| Type | Playbook | Description |
|------|----------|-------------|
| 🎯 **Orchestrator** | `r-workflow-feature` | End-to-end feature delivery: BDD spec → TDD impl → Code Review → Quality Gate → Release |
| 📋 **Planner** | `r-plan-feature` | Architectural planning before coding: analyze context, design approach, identify files, estimate effort |
| 🔍 **Auditor** | `r-package-audit` | Comprehensive package health check: R CMD check + tests + coverage + lint + deps + docs + CI |
| 🧬 **Mutation Testing** | `r-mutation-test` | Mutation testing with `muttest` (Appsilon): inject bugs, measure test kill rate, strengthen weak tests |
| 🎲 **Property Testing** | `r-property-test` | Property-based testing with `hedgehog`/: define invariants, generate random inputs, shrink counterexamples |
| 🔄 **Dependency Upgrade** | `r-dependency-upgrade` | Safe dependency upgrades: one-at-a-time, test after each, git checkpoints, auto-rollback |
| ⚡ **Performance** | `r-performance-benchmark` | Systematic performance work: profvis profiling → bench::mark benchmarking → optimize → re-benchmark |
| 🛠️ **Meta** | `r-playbook-create` | Create new playbooks following project conventions |
| 📊 **Model Monitor** | `r-model-monitor` | ML model monitoring: data drift (KS, PSI) + concept drift (datadriftR PDD) + performance tracking (vetiver) |
| 🗄️ **DB Migration** | `r-database-migrate` | Safe database schema migration: version-controlled up/down, dry-run, transaction rollback |
| ⏰ **Pipeline Scheduler** | `r-schedule-pipeline` | Production scheduling for targets pipelines: cronR, GHA scheduled, checkpoint/resume, notifications |
| ☸️ **Kubernetes Deploy** | `r-deploy-kubernetes` | Deploy R apps to Kubernetes/Cloud Run/ECS: Helm, health checks, HPA, secrets, blue-green |
| 🧪 **DB Testing** | `r-test-database` | Database testing patterns: fixtures, transaction rollback, query correctness, SQL injection, perf regression |
| 🔐 **Shiny Auth** | `r-shiny-auth` | Authentication for Shiny: shinymanager (credentials/LDAP) or polished (Auth0/SSO/OAuth) + RBAC |
| 📬 **Notifications** | `r-notification` | Email (blastula) + Slack/Teams webhook notifications for pipelines, monitoring, and releases |
| 🤖 **ML Init** | `r-ml-init` | ML project scaffolding with tidymodels: feature engineering, train/val/test, vetiver deployment |
| 🧪 **ML Validate** | `r-ml-validate` | Model validation & explainability: DALEX, vip, shapviz, fairness (fairmodels), model comparison |
| 🔌 **API Testing** | `r-api-testing` | API contract (pact), mock (httptest2), integration, and load testing for Plumber APIs |
| ⚡ **Shiny Perf** | `r-shiny-perf` | Shiny performance: reactlog, profvis, shinyloadtest, bindCache, performance regression tests |
| ☁️ **Cloud SDK** | `r-cloud-sdk` | Cloud integration: AWS (paws), GCP (bigrquery/googleCloudStorageR), Azure (AzureStor) |
| 📊 **Observable** | `r-observable` | R + Observable/WebR interactive documents: Quarto OJS, WebR (client-side R), Observable Framework |

### Key Tools

Playbooks reference tools from the **Posit** ecosystem (testthat, roxygen2, devtools, usethis, pkgdown, shiny, shinytest2, shinyloadtest, blastula, shinymanager, reactlog, pak, renv, profvis, bench, vetiver, plumber, targets, tidymodels, rlang, cli, otel, otelsdk, pointblank, pins, config, DBI, odbc, httptest2, quarto) and **Appsilon** (rhino, muttest, polished). See individual playbooks for tool-specific workflows.

### R Telemetry & Observability (OpenTelemetry)

The `r-otel-instrument` playbook and `r-deploy-kubernetes` playbook leverage the **Posit `otel` and `otelsdk` packages** for OpenTelemetry in R:

- **`otel`** (v0.2.0, 2025-08-29) — Zero-dependency OpenTelemetry API. Instrument R code with spans, metrics, and logs. Supports zero-code auto-instrumentation via `OTEL_R_INSTRUMENT_PKGS` environment variable.
- **`otelsdk`** (v0.2.4, 2026-04-08) — OTLP exporters for traces, metrics, and logs. Export telemetry to OTLP collectors (Grafana, Jaeger, Datadog) via environment variable configuration.

All three pillars (traces, metrics, logs) are supported, currently in development status. See the [otel.r-lib.org](https://otel.r-lib.org) and [otelsdk.r-lib.org](https://otelsdk.r-lib.org) sites for the latest API.

## Playbook structure

Each playbook lives in `playbooks/<name>/PLAYBOOK.md` and follows a consistent YAML + Markdown format:

```yaml
---
name: r-playbook-name
version: 1.0.0
description: What this playbook does
trigger: manual | auto | both
trigger-patterns:
  - "init package *"
parameters:
  param1:
    type: String        # String | Boolean | Integer | Float | Array
    required: true
    hint: "Description shown to the agent"
  param2:
    type: String
    required: false
    default: "MIT"
    enum: ["MIT", "GPL-3", "Apache-2.0"]
steps:
  - id: step-one
    inline-prompt: |
      Instructions for the agent at this step.
      References: {{params.param1}}, {{state.previous_output}}
    gate: Confirm       # None | Confirm | Review | Approve
    output: step_result
---
You are an R specialist. [System prompt / role description here]
```

## Using playbooks

1. **Install** the [playbooks-mcp](https://github.com/davidrsch/playbooks-mcp) MCP server in your agent
2. **Browse** the [gallery](https://davidrsch.github.io/r-playbooks/) to find the right playbook
3. **Select** playbooks and download them as a ZIP bundle into `.openmono/playbooks/` in your project
4. **Run** via your agent: `run_playbook("r-init-package", { name: "mypkg" })` — the MCP server handles step execution, gates, and state

## Contributing

See the [playbook schema](.github/playbook-schema.json) for the expected format. Validation runs automatically on every push via GitHub Actions.

## License

MIT: see individual playbooks for details.
