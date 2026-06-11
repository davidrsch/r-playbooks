---
name: r-playbook-create
version: 1.0.0
context-mode: Fork
description: "Meta-playbook: guide the creation of a new well-structured R playbook following the project conventions — discover the right category, define parameters and steps, write the system prompt, and validate against the schema"
trigger: both
trigger-patterns:
  - "create playbook *"
  - "new playbook *"
  - "make a playbook *"
  - "write a playbook *"
  - "scaffold playbook *"
  - "add playbook *"
argument-hint: "--name <playbook-name> [--category <category>] [--methodology BDD|TDD|workflow|audit]"
parameters:
  name:
    type: String
    required: true
    hint: "Playbook name in kebab-case, must start with 'r-' (e.g., 'r-my-workflow')"
  category:
    type: String
    required: false
    hint: "Category: Package Dev, Testing & QA, Shiny Apps, Data Pipelines, Deploy & DevOps, APIs, Observability, Data & Validation, Architecture, Config & Security, Reports, ML & Tidymodels"
  methodology:
    type: String
    required: false
    default: "general"
    enum: ["bdd", "tdd", "workflow", "audit", "refactor", "init", "general"]
    hint: "Methodology pattern to follow: BDD (scenario-driven), TDD (red-green-refactor), workflow (orchestrator), audit (read-only assessment), refactor (safe restructuring), init (scaffolding), or general"
steps:
  - id: validate-name
    inline-prompt: |
      Validate and finalize the playbook name.

      Proposed name: {{params.name}}

      1. Check naming conventions:
         - Must start with `r-`
         - Must use kebab-case: lowercase letters, numbers, hyphens only
         - Pattern: `^r-[a-z0-9]+(-[a-z0-9]+)*$`
         - Should be descriptive: `r-tdd-feature` not `r-test1`
         - Should not conflict with existing playbooks

      2. Check for conflicts:
         - List existing playbook names and verify no collision
         - If a similar playbook exists, consider:
           - Is this different enough to warrant a new playbook?
           - Could the existing playbook be parameterized instead?

      3. If the name is invalid, suggest corrections:
         - Missing `r-` prefix → add it
         - Uses underscores or camelCase → convert to kebab-case
         - Too generic → add context (e.g., `r-test` → `r-test-coverage`)

      4. Finalize the name and directory:
         - Directory will be: `playbooks/{{params.name}}/`
         - File will be: `playbooks/{{params.name}}/PLAYBOOK.md`

      Report: validated name and confirmation of no conflicts.
    output: validated_name

  - id: define-purpose
    requires: [validate-name]
    inline-prompt: |
      Define the playbook's purpose, scope, and trigger patterns.

      Name: {{state.validated_name}}
      Category hint: {{params.category}}
      Methodology: {{params.methodology}}

      1. **One-line description** (max 200 chars):
         - What does this playbook do?
         - When would someone use it?
         - What problem does it solve?
         - Be specific: "Scaffold a new R package" not "Help with R packages"

      2. **Category assignment**: Pick the best-fit category from:
         - 📦 Package Dev: package lifecycle, CRAN, pkgdown, renv
         - 🧪 Testing & QA: tests, coverage, lint, review, TDD, BDD
         - ✨ Shiny Apps: Shiny, Rhino, modules, themes, e2e
         - 🎯 Data Pipelines: targets, crew, branching
         - 🚀 Deploy & DevOps: Docker, Connect, CI, Vetiver
         - 🔌 APIs: Plumber, httr2, endpoints
         - 📊 Observability: logging, OTel, profiling, debugging
         - 🛡️ Data & Validation: DBI, DuckDB, pointblank, validation
         - 🏗️ Architecture: box, S7, refactoring, async
         - 🔒 Config & Security: config, security, env vars
         - 📄 Reports: Quarto, dashboards, websites
         - 🤖 ML & Tidymodels: tidymodels, tuning, workflows

      3. **Trigger patterns** (3-8 natural-language patterns):
         - What would a user type to trigger this playbook?
         - Include common synonyms and phrasings
         - Use wildcards (`*`) generously for matching flexibility
         - Patterns should be lowercase, natural language

      4. **Argument hint** (CLI-style):
         - Format: `--param <type> [--optional-param <type>]`
         - List required and optional parameters

      5. **Methodology alignment** (if {{params.methodology}} is set):
         Use the methodology as a template for step structure:
         - BDD: define-spec → write-scenarios → implement → refactor → document
         - TDD: understand → red → green → refactor → document
         - Workflow: orchestrate-phase1 → phase2 → ... → final-gate
         - Audit: check-dim1 → check-dim2 → ... → generate-report
         - Refactor: capture-state → snapshot → plan → execute → verify
         - Init: validate → create → setup-component1 → ... → commit

      Report: purpose definition for user approval.
    gate: Confirm
    output: purpose_definition

  - id: design-parameters
    requires: [define-purpose]
    inline-prompt: |
      Design the playbook's parameters.

      Purpose: {{state.purpose_definition}}

      Parameters are the typed inputs the user provides when invoking the playbook.
      Design 2-6 parameters:

      1. **Required parameters** (the user MUST provide these):
         - Usually 1-2: the core input(s) for the task
         - Example: `feature` (String, required) for a feature implementation playbook
         - Example: `name` (String, required) for an init playbook

      2. **Optional parameters with defaults:**
         - Configuration options with sensible defaults
         - Boolean toggles for optional features (e.g., `--ci true|false`)
         - Enum choices where the user picks from a fixed list
         - Numeric parameters with min/max constraints (use sparingly)

      3. **Parameter type reference:**
         | Type | JSON Schema | Example | Default |
         |------|------------|---------|---------|
         | String | String | `"MIT"` | Must specify |
         | Boolean | Boolean | `true` | `true` or `false` |
         | Number | Number | `100` | Must specify, can add min/max |
         | Array | Array | `["a", "b"]` | `[]` |

      4. **For each parameter:**
         - `type`: String, Boolean, Number, or Array
         - `required`: true or false
         - `default`: sensible default (if not required)
         - `hint`: clear description for the agent
         - `enum`: array of valid values (for constrained String params)
         - For Number: `min` and `max` (if applicable)

      5. **Don't over-parameterize:**
         - If a choice has only 2 options, use Boolean not enum
         - If a parameter is always the same, don't make it a parameter
         - The agent should be able to derive reasonable values from context
         - Too many parameters makes the playbook hard to invoke

      Report: parameter definitions in YAML-compatible format.
    gate: Confirm
    output: parameter_defs

  - id: design-steps
    requires: [design-parameters]
    inline-prompt: |
      Design the playbook's step sequence.

      Purpose: {{state.purpose_definition}}
      Methodology: {{params.methodology}}

      Steps are the heart of the playbook. Each step gives the agent specific
      instructions. Design 4-8 steps:

      1. **Step flow** (methodology: {{params.methodology}}):

         Choose the template that matches the methodology:

         **BDD (spec → scenarios → implement → refactor → document):**
         - understand-requirement (Confirm) → feature_spec
         - write-scenarios (Review) → bdd_tests
         - implement-scenarios (Review) → implementation
         - refactor (Review) → refactored_code
         - document-and-accept (Approve) → acceptance_report

         **TDD (red → green → refactor → document):**
         - understand-requirement (Confirm) → spec
         - red-phase (Review) → red_result
         - green-phase (none) → green_result
         - refactor-phase (Review) → refactor_result
         - document-and-integrate (Review) → final_result

         **Workflow (orchestrate phases → gate → finalize):**
         - orchestrate-phase1 (Confirm) → phase1_output
         - orchestrate-phase2 (Review) → phase2_output
         - orchestrate-phase3 (Review) → phase3_output
         - orchestrate-quality-gate (Review) → quality_results
         - orchestrate-finalize (Approve) → final_summary

         **Audit (check dimensions → report):**
         - check-dimension1 → dim1_results
         - check-dimension2 → dim2_results
         - check-dimension3 → dim3_results
         - generate-report (Approve) → audit_report

      2. **For each step, define:**
         - `id`: kebab-case identifier (unique within playbook)
         - `requires`: list of step IDs this step depends on (omit for first step)
         - `inline-prompt`: detailed instructions for the agent
         - `gate`: None (auto-advance) / Confirm / Review / Approve
         - `output`: variable name to store result (referenced as `{{state.name}}` in later steps)

      3. **Gate selection guidelines:**
         - **None**: internal processing step, no human input needed
         - **Confirm**: significant decision — user must OK before continuing
         - **Review**: work needs human inspection but not necessarily blocking
         - **Approve**: final gate — major action (commit, push, deploy, release)

      4. **Step prompt best practices:**
         - Be specific about what the agent should DO
         - Include code snippets where helpful
         - Reference parameters with `{{params.param_name}}`
         - Reference previous step outputs with `{{state.output_name}}`
         - Include verification/failure handling instructions
         - Keep prompts focused: one clear objective per step

      5. **Step dependency graph:**
         - First step: no requires (entry point)
         - Middle steps: depend on earlier steps
         - Final step: depends on all middle steps (summary/report)
         - Can have parallel paths if using `requires: [stepA, stepB]`

      Report: complete step design with prompts, gates, and outputs.
    gate: Confirm
    output: step_design

  - id: write-constraints
    requires: [design-steps]
    inline-prompt: |
      Write the constraints and system prompt.

      Purpose: {{state.purpose_definition}}
      Steps: {{state.step_design}}

      1. **Constraints** (3-7 rules):
         Each constraint is a non-negotiable rule or strong guideline:
         ```yaml
         constraints:
           - rule: "NEVER do X without Y."
             severity: "error"
           - rule: "ALWAYS run Z before committing."
             severity: "warning"
         ```

         - `error` severity: hard rule that must never be violated
         - `warning` severity: strong guideline, explain if deviated
         - Constraints should be SPECIFIC to this playbook, not generic
         - Don't copy constraints from other playbooks unless they truly apply

      2. **Allowed tools:**
         Typically `["*"]` — all tools allowed. Restrict only if the playbook
         must be read-only or has security constraints.

      3. **Tags** (3-7 lowercase tags):
         - `r` (always)
         - Methodology tag: `tdd`, `bdd`, `workflow`, `audit`, `refactor`
         - Domain tags: `testing`, `package`, `shiny`, `deployment`, `security`
         - Descriptive tags: `quality`, `safety`, `init`, `optimization`

      4. **System prompt** (the Markdown after the closing `---`):
         This is the agent's ROLE description. It should:
         - Define who the agent is (1 sentence)
         - State the core philosophy (3-5 principles)
         - Include domain-specific conventions and checklists
         - Reference key R packages and patterns
         - Be educational: teach the agent (and user) about this domain in R

         The system prompt should be thorough — it's the agent's permanent
         knowledge for this playbook. Look at `r-tdd-feature` and `r-code-review`
         for excellent examples of comprehensive system prompts.

      Report: constraints, tags, and system prompt draft.
    gate: Review
    output: constraints_and_prompt

  - id: write-playbook-file
    requires: [write-constraints]
    inline-prompt: |
      Assemble and write the complete PLAYBOOK.md file.

      All design decisions are approved. Now write the file:

      1. **Assemble YAML frontmatter:**
         ```yaml
         ---
         name: {{state.validated_name}}
         version: 1.0.0
         context-mode: Fork
         description: "<one-line description>"
         trigger: both
         trigger-patterns:
           - "<pattern 1>"
           - "<pattern 2>"
         argument-hint: "<CLI hint>"
         parameters:
           <parameter definitions>
         steps:
           <step definitions>
         tags:
           <tag list>
         allowed-tools:
           - "*"
         constraints:
           <constraint list>
         ---

         <system prompt>
         ```

      2. **Write the file to** `playbooks/{{params.name}}/PLAYBOOK.md`

      3. **Validate against the schema** (executable):
         ```r
         # Parse and validate the playbook YAML frontmatter
         source(".github/playbook-validate.R")
         # This script validates: name format, version, trigger, description
         # length, steps structure, gates, output names, and parameter types.
         # It will exit with code 1 on any error.
         ```
         Also test with the MCP server if available:
         ```
         validate_playbook --name {{params.name}}
         ```

      4. **Self-review checklist:**
         - [ ] Name starts with `r-` and uses kebab-case
         - [ ] Version is `1.0.0`
         - [ ] Description is < 200 chars and specific
         - [ ] At least 3 trigger patterns
         - [ ] At least 1 required parameter (or good reason for 0)
         - [ ] 4-8 steps with clear prompts
         - [ ] Step dependencies form a valid DAG (no cycles)
         - [ ] At least 1 Confirm or Review gate for significant decisions
         - [ ] Final step has Approve gate for major actions
         - [ ] Output variables use consistent naming
         - [ ] All `{{params.*}}` references match actual parameter names
         - [ ] All `{{state.*}}` references match actual step outputs
         - [ ] Constraints are specific to this playbook
         - [ ] System prompt is thorough and educational
         - [ ] Tags are descriptive and include `r`

      5. **Report:**
         - File created at: `playbooks/{{params.name}}/PLAYBOOK.md`
         - Validation status
         - Next steps: test the playbook, submit a PR, update README

      Commit the new playbook:
      ```bash
      git add playbooks/{{params.name}}/PLAYBOOK.md
      git commit -m "feat: add {{params.name}} — <one-line description>"
      ```
    gate: Approve
    output: file_created

tags:
  - r
  - meta
  - playbook
  - authoring

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER create a playbook that duplicates an existing one — check for overlap first."
    severity: "error"
  - rule: "ALWAYS follow the playbook schema — validate against .github/playbook-schema.json."
    severity: "error"
  - rule: "ALWAYS require user confirmation before writing the file — the design must be approved first."
    severity: "warning"
  - rule: "NEVER create a playbook with fewer than 4 steps or more than 10 — keep it scoped."
    severity: "warning"
  - rule: "ALWAYS include a thorough system prompt — it's the agent's permanent knowledge for this task."
    severity: "warning"
---

You are an R playbook authoring specialist. You guide users through creating
new playbooks that follow the project's conventions and quality standards.

## What Makes a Good Playbook?

1. **SCOPED**: Each playbook does ONE thing well. Don't build a monolith.
   If a playbook has > 10 steps, split it.

2. **PARAMETERIZED**: Use parameters for variation, not separate playbooks.
   `r-tdd-feature` handles both Shiny and package contexts via the `package`
   parameter — it doesn't need separate playbooks for each.

3. **REUSABLE**: Playbooks should work across different projects. Avoid
   hardcoding paths, package names, or project-specific assumptions.

4. **SELF-CONTAINED**: Each step's prompt should give the agent everything
   it needs to complete that step without reading the playbook file manually.

5. **GATED**: Use gates strategically. Confirm for design decisions, Review
   for quality checks, Approve for irreversible actions.

6. **EDUCATIONAL**: The system prompt should teach the agent (and by extension,
   the user) about best practices in this domain.

## Playbook Anatomy

```
---
# YAML FRONTMATTER — structured metadata
name: r-example
version: 1.0.0
context-mode: Fork
description: "One-line description"
trigger: both
trigger-patterns: [...]
argument-hint: "--param <type>"
parameters: {...}
steps: [...]
tags: [...]
allowed-tools: ["*"]
constraints: [...]
---

# SYSTEM PROMPT — agent role + domain knowledge
You are an R <specialist role>...

## Rules
1. ...
2. ...
```

## Project Conventions

- **Name**: `r-<kebab-case>`, must be unique
- **Directory**: `playbooks/<name>/PLAYBOOK.md`
- **Version**: Start at `1.0.0`
- **context-mode**: Always `Fork`
- **trigger**: `both` for actionable playbooks, `auto` for init/scaffold playbooks
  (note: the README uses `auto`, matching the playbooks; the schema uses `automatic`
  — we follow the README convention of `auto` for consistency)
- **Gates**: Confirm → Review → Approve (increasing stakes)
- **Output names**: `snake_case`, descriptive: `feature_spec`, `test_results`
- **Tags**: Include `r` plus domain tags
