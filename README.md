# 🎯 R Playbooks

A collection of **40+ AI-assisted playbooks** for common R development workflows: package development, testing, Shiny apps, data pipelines, deployment, APIs, observability, and more.

> [**Browse the playbook gallery**](https://davidrsch.github.io/r-playbooks/)

## Runtime

These playbooks are designed for the **[playbooks-mcp](https://github.com/davidrsch/playbooks-mcp)** MCP server — a TypeScript/Node.js server that executes PLAYBOOK.md files with typed parameters, step dependencies, human-in-the-loop gates, and checkpoint/resume. Any MCP-compatible agent (Claude, Cline, Continue, Cursor) can use these playbooks once the server is installed.

## What are playbooks?

Playbooks are structured, step-by-step guides designed for AI coding agents. Each playbook defines a specific R development task with clearly scoped steps, inputs, outputs, validations, and safety boundaries. They help ensure AI-assisted coding is predictable, repeatable, and aligned with best practices.

## Categories

| Category                 | Playbooks                                                                                                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 📦 **Package Dev**       | `r-init-package`, `r-pkg-add-function`, `r-pkg-check`, `r-pkg-release`, `r-pkgcheck-review`, `r-pkgdown-site`, `r-pak-lockfile`, `r-renv-manage`, `r-cran-submission` |
| 🧪 **Testing & QA**      | `r-lint`, `r-tdd-feature`, `r-tdd-bugfix`, `r-bdd-feature`, `r-testthat-snapshot`, `r-code-review`                                                                 |
| ✨ **Shiny Apps**        | `r-init-shiny`, `r-shiny-module`, `r-shiny-theme-bslib`, `r-shiny-e2e-test`, `r-rhino-init`, `r-rhino-add-module`, `r-rhino-build`, `r-rhino-check`, `r-rhino-test` |
| 🎯 **Data Pipelines**    | `r-init-targets`, `r-targets-add-target`, `r-targets-branching`, `r-targets-crew`                                                                                  |
| 🚀 **Deploy & DevOps**   | `r-docker-build`, `r-connect-deploy`, `r-vetiver-deploy`, `r-ci-gha`                                                                                               |
| 🔌 **APIs**              | `r-init-plumber`, `r-api-endpoint`, `r-httr2-client`                                                                                                               |
| 📊 **Observability**     | `r-logger-setup`, `r-otel-instrument`, `r-profile`, `r-debug`                                                                                                      |
| 🛡️ **Data & Validation** | `r-data-validate`, `r-pointblank-agent`, `r-dbi-setup`, `r-duckdb-pipeline`                                                                                        |
| 🏗️ **Architecture**      | `r-box-module`, `r-s7-class`, `r-refactor`, `r-async-mirai`                                                                                                        |
| 🔒 **Config & Security** | `r-config-env`, `r-security`                                                                                                                                        |
| 📄 **Reports**           | `r-quarto-render`, `r-quarto-website`, `r-quarto-dashboard`                                                                                                         |
| 🤖 **ML & Tidymodels**   | `r-tidymodels-workflow`, `r-tidymodels-tune`                                                                                                                        |

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
    type: String        # String | Number | Boolean | Array
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
