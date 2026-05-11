---
name: r-quarto-render
version: 1.0.0
context-mode: Fork
description: Render a Quarto document or project with parameters, profiling, and output validation
trigger: both
trigger-patterns:
  - "render quarto *"
  - "render * qmd"
  - "quarto render *"
  - "build quarto *"
  - "publish quarto *"
argument-hint: "--file <path.qmd> [--format html|pdf|docx|revealjs] [--params <key=value,...>] [--profile <profile>]"
parameters:
  file:
    type: String
    required: false
    hint: "Path to .qmd file or _quarto.yml project (default: current directory)"
  format:
    type: String
    required: false
    default: "html"
    enum: ["html", "pdf", "docx", "revealjs", "dashboard", "all"]
    hint: "Output format(s) to render"
  params:
    type: Array
    required: false
    default: []
    hint: "Key=value pairs to pass as Quarto parameters"
  profile:
    type: String
    required: false
    hint: "Quarto project profile to use (e.g., production, development)"
steps:
  - id: detect-project
    inline-prompt: |
      Detect the Quarto project structure:

      1. Determine what to render:
         - If {{params.file}} is specified: render that file
         - If `_quarto.yml` exists: render the project
         - If a single .qmd file exists: render it
      2. Read `_quarto.yml` if it exists:
         - Project type (website, book, default)
         - Output directory
         - Available profiles
      3. List all .qmd files in the project.
      4. Detect parameterized reports: `params:` in YAML frontmatter.
      5. Report: project type, files to render, output config.
    output: project_info

  - id: validate-params
    requires: [detect-project]
    inline-prompt: |
      Validate and resolve Quarto parameters.

      Provided params: {{params.params}}
      Project: {{state.project_info}}

      1. If parameters are defined in the document/project YAML, validate:
         - Required params are provided
         - Type checking (string, number, boolean)
         - Enum values if defined
         - Example: `if (!param %in% c("a", "b", "c")) stop("param must be one of: a, b, c")`
      2. If no parameters are defined but params were provided, warn.
      3. Construct the quarto render command parameters:
         ```
         -P key1:value1 -P key2:value2
         ```
      4. Report: validated params, render command.

      If a required parameter is missing, report and abort.
    gate: Confirm
    output: render_command

  - id: render
    requires: [validate-params]
    inline-prompt: |
      Render the Quarto document/project.

      Command: {{state.render_command}}
      Profile: {{params.profile}}

      1. Construct the full quarto render command:
         ```bash
         quarto render {{params.file}} --to {{params.format}}
         (If a profile was specified: --profile {{params.profile}})
         (For each validated parameter: -P key:value)
         # Use --freeze to skip re-execution of unchanged computations in large projects
         ```
      2. Execute the render.
      3. Monitor for errors:
         - R execution errors (missing packages, data not found)
         - Syntax errors in .qmd files
         - LaTeX errors (for PDF output)
      4. If render fails, diagnose the error:
         - Check which .qmd file caused the error
         - Find the specific chunk or line
         - Identify the root cause
      5. Report:
         - Success: output file(s) path, size
         - Failure: error location and cause
    gate: Review
    output: render_output

  - id: validate-output
    requires: [render]
    inline-prompt: |
      Validate the rendered output.

      Render result: {{state.render_output}}

      1. Verify output file(s) exist and have non-zero size.
      2. Check for common rendering issues:
         - "??" in cross-references (unresolved): use `grep -rn '??' <output_dir>` to find
         - Missing figures or images
         - Overflow boxes (tables/code extending beyond page width)
         - Broken links (if HTML output)
      3. For HTML output:
         - Check all internal links resolve
         - Verify images have alt text
         - Check responsive layout on narrow screens (if applicable)
      4. For PDF output:
         - Check page breaks are sensible
         - Verify fonts are embedded
         - Check for any LaTeX overfull/underfull warnings
      5. Report:
         ```
         ✅ RENDER VALIDATION:
         Output: <path> (<size>)
         Format: {{params.format}}
         Status: ✅ OK / ⚠️ Issues found
         Issues: <list if any>
         ```
    output: validation

  - id: optimize-assets
    requires: [validate-output]
    inline-prompt: |
      Optimize rendered assets for production:

      1. Check output size:
         - HTML: if > 5MB, suggest splitting into chapters or lazy-loading images
         - PDF: if > 10MB, suggest compressing images
      2. Check for:
         - Unnecessarily high-res images (> 2x screen resolution)
         - Embedded data in HTML output
         - Unused CSS in HTML output
      3. If this is a website/book, suggest:
         - `quarto publish` commands
         - Netlify/GitHub Pages deployment
      4. Report optimization opportunities.
    output: optimizations

tags:
  - r
  - quarto
  - reporting
  - rendering
  - publishing

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are a Quarto publishing specialist. You render, validate, and
optimize Quarto documents for production.

## Rules

1. ALWAYS detect the project structure before rendering.
2. Validate parameters before executing: Quarto errors are cryptic.
3. NEVER modify .qmd files without user confirmation (gate: Confirm/Review).
4. If rendering fails, diagnose the root cause precisely.
5. Check for `renv` before installing missing packages.
6. For parameterized reports, ensure output filenames include parameter values
   to prevent overwriting.
7. Use `--profile` for environment-specific configurations.
8. For large projects, suggest `--freeze` to speed up re-renders.
9. Cross-reference syntax: `@fig-label`, `@tbl-label`, `@eq-label`.
10. `execute:` options: `echo`, `warning`, `message`, `include`, `eval`.
