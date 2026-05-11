# 🎯 R Playbooks

A collection of **40+ AI-assisted playbooks** for common R development workflows — package development, testing, Shiny apps, data pipelines, deployment, APIs, observability, and more.

> [**Browse the playbook gallery**](https://davidrsch.github.io/r-playbooks/)

## What are playbooks?

Playbooks are structured, step-by-step guides designed for AI coding agents. Each playbook defines a specific R development task with clearly scoped steps, inputs, outputs, validations, and safety boundaries. They help ensure AI-assisted coding is predictable, repeatable, and aligned with best practices.

## Categories

| Category | Playbooks |
|---|---|
| 📦 **Package Dev** | `r-init-package`, `r-pkg-add-function`, `r-pkg-check`, `r-pkg-release`, `r-pkgcheck-review`, `r-pkgdown-site`, `r-pak-lockfile` |
| 🧪 **Testing & QA** | `r-lint`, `r-tdd-feature`, `r-tdd-bugfix`, `r-bdd-feature`, `r-testthat-snapshot`, `r-code-review` |
| ✨ **Shiny Apps** | `r-init-shiny`, `r-shiny-module`, `r-shiny-theme-bslib`, `r-shiny-e2e-test`, `r-rhino-init` |
| 🎯 **Data Pipelines** | `r-init-targets`, `r-targets-add-target`, `r-targets-branching`, `r-targets-crew` |
| 🚀 **Deploy & DevOps** | `r-docker-build`, `r-connect-deploy`, `r-vetiver-deploy`, `r-ci-gha` |
| 🔌 **APIs** | `r-init-plumber`, `r-api-endpoint` |
| 📊 **Observability** | `r-logger-setup`, `r-otel-instrument`, `r-profile` |
| 🛡️ **Data & Validation** | `r-data-validate`, `r-pointblank-agent` |
| 🏗️ **Architecture** | `r-box-module`, `r-s7-class`, `r-refactor`, `r-async-mirai` |
| 🔒 **Config & Security** | `r-config-env`, `r-security` |
| 📄 **Reports** | `r-quarto-render` |

## Playbook structure

Each playbook lives in `playbooks/<name>/PLAYBOOK.md` and follows a consistent YAML + Markdown format:

```yaml
---
name: r-playbook-name
version: 1.0.0
description: What this playbook does
trigger: manual | auto | both
parameters:
  - name: param1
    description: ...
    type: string
    required: true
---

# Playbook steps...
```

## Using playbooks

1. **Browse** the [gallery](https://davidrsch.github.io/r-playbooks/) to find the right playbook
2. **Select** playbooks and download them as a ZIP bundle
3. **Share** the PLAYBOOK.md with your AI coding agent (e.g., Copilot, Claude, etc.)
4. The agent follows the structured steps with built-in safety checks

## Contributing

See the [playbook schema](.github/playbook-schema.json) for the expected format. Validation runs automatically on every push via GitHub Actions.

## License

MIT — see individual playbooks for details.
