---
name: r-quarto-website
version: 1.0.0
context-mode: Fork
description: "Scaffold a Quarto website with navbar, sidebar, listings, and GitHub Pages deployment"
trigger: both
trigger-patterns:
  - "quarto website *"
  - "quarto site *"
  - "create website *"
  - "build website *"
  - "quarto blog *"
argument-hint: "--name <slug> --title <title> [--type website|blog|book] [--theme cosmo|flatly] [--deploy gh-pages|netlify|none]"
parameters:
  name:
    type: String
    required: true
    hint: "Project directory name (e.g. 'my-site')"
  title:
    type: String
    required: true
    hint: "Site title shown in the navbar"
  type:
    type: String
    required: false
    default: "website"
    enum: ["website", "blog", "book"]
    hint: "Quarto project type"
  theme:
    type: String
    required: false
    default: "flatly"
    enum: ["cosmo", "flatly", "darkly", "lux", "minty", "pulse", "sandstone", "solar", "superhero", "yeti"]
    hint: "Bootstrap theme"
  deploy:
    type: String
    required: false
    default: "gh-pages"
    enum: ["gh-pages", "netlify", "none"]
    hint: "Deployment target"
  author:
    type: String
    required: false
    hint: "Default author name for pages and posts"
steps:
  - id: create-project
    inline-prompt: |
      Create the Quarto website project scaffold.

      Project name: {{params.name}}
      Type: {{params.type}}

      Run:
      ```r
      quarto::quarto_create_project(
        name = "{{params.name}}",
        type = "{{params.type}}",
        open  = FALSE
      )
      ```

      If quarto::quarto_create_project fails (older Quarto), create manually:
      ```bash
      quarto create project {{params.type}} {{params.name}}
      ```

      Verify that `_quarto.yml`, `index.qmd`, and `about.qmd` (or `posts/` for blog) were created.
      Report: directory listing of `{{params.name}}/`.
    gate: Confirm
    output: project_path

  - id: configure-quarto-yml
    requires: [create-project]
    inline-prompt: |
      Write the `_quarto.yml` configuration file.

      Title: {{params.title}}
      Theme: {{params.theme}}
      Type: {{params.type}}
      Author: {{params.author}}

      **For type "website":**
      ```yaml
      project:
        type: website
        output-dir: _site

      website:
        title: "{{params.title}}"
        navbar:
          left:
            - href: index.qmd
              text: Home
            - href: about.qmd
              text: About
          right:
            - icon: github
              href: ""
        sidebar: false
        page-footer:
          center: "© {{params.author}} — Built with [Quarto](https://quarto.org)"

      format:
        html:
          theme: {{params.theme}}
          css: styles.css
          toc: true
          toc-depth: 3
      ```

      **For type "blog":**
      Replace `website.navbar.left` with:
      ```yaml
            - href: index.qmd
              text: Home
            - href: about.qmd
              text: About
            - href: posts.qmd
              text: Blog
      ```
      And add:
      ```yaml
        listing:
          posts:
            type: default
            sort: "date desc"
            categories: true
            feed: true
      ```

      **For type "book":**
      ```yaml
      project:
        type: book

      book:
        title: "{{params.title}}"
        author: "{{params.author}}"
        chapters:
          - index.qmd
          - intro.qmd
          - summary.qmd
          - references.qmd
      ```

      Write the file and report its contents.
    output: quarto_yml

  - id: create-pages
    requires: [configure-quarto-yml]
    inline-prompt: |
      Create the initial content pages.

      Type: {{params.type}}
      Author: {{params.author}}

      **For "website" or "blog":**
      Create `index.qmd`:
      ```markdown
      ---
      title: "{{params.title}}"
      ---

      Welcome to {{params.title}}. This site is built with [Quarto](https://quarto.org).
      ```

      Create `about.qmd`:
      ```markdown
      ---
      title: "About"
      ---

      This site is maintained by {{params.author}}.
      ```

      **For "blog"**, also create `posts/first-post/index.qmd`:
      ```markdown
      ---
      title: "First Post"
      author: "{{params.author}}"
      date: today
      categories: [news]
      ---

      This is the first blog post.
      ```

      **For "book"**, create `intro.qmd`, `summary.qmd`, `references.qmd` stubs.

      Also create `styles.css` (empty, for custom CSS later).
      Report: pages created.
    output: pages

  - id: add-gitignore
    requires: [create-pages]
    inline-prompt: |
      Create a `.gitignore` for the Quarto project:

      ```
      /.quarto/
      /_site/
      /_freeze/
      /_book/
      *.html
      *.pdf
      ```

      Also initialise a git repository if one doesn't exist:
      ```bash
      cd {{params.name}}
      git init
      git add .
      git commit -m "feat: initial Quarto {{params.type}} scaffold"
      ```

      Report: git status after commit.
    output: git_init

  - id: setup-deployment
    requires: [add-gitignore]
    inline-prompt: |
      Set up deployment for target: {{params.deploy}}

      **gh-pages:**
      Create `.github/workflows/publish.yml`:
      ```yaml
      name: Publish Quarto Site

      on:
        push:
          branches: [main]
        workflow_dispatch:

      jobs:
        build-deploy:
          runs-on: ubuntu-latest
          permissions:
            contents: write
          steps:
            - uses: actions/checkout@v4
            - uses: r-lib/actions/setup-r@v2
            - uses: r-lib/actions/setup-renv@v2
              if: hashFiles('renv.lock') != ''
            - uses: quarto-dev/quarto-actions/setup@v2
            - uses: quarto-dev/quarto-actions/publish@v2
              with:
                target: gh-pages
              env:
                GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      ```

      **netlify:**
      Create `netlify.toml`:
      ```toml
      [build]
        command = "quarto render"
        publish = "_site"

      [build.environment]
        QUARTO_VERSION = "1.5.0"
      ```

      **none:** skip deployment setup.
      Report: deployment configuration created.
    gate: Review
    output: deploy_config

  - id: render-preview
    requires: [setup-deployment]
    inline-prompt: |
      Render the site locally to verify it builds without errors.

      ```r
      setwd("{{params.name}}")
      quarto::quarto_render()
      ```

      Check:
      - No YAML errors
      - All pages render
      - Navigation links work
      - Theme applied correctly

      Run `quarto::quarto_preview()` to open a live preview in the browser.
      Report: render output and any warnings.
    gate: Review
    output: render_status

tags:
  - r
  - quarto
  - website
  - blog
  - reporting
  - deployment

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER commit _site/, /_freeze/, or /.quarto/ to git."
    severity: "error"
  - rule: "ALWAYS use quarto-dev/quarto-actions for GitHub Actions publishing."
    severity: "warning"
  - rule: "NEVER use absolute paths in content — always use relative links."
    severity: "warning"
  - rule: "For blogs, always include date: and categories: in post YAML."
    severity: "warning"
---

You are a Quarto website builder. You scaffold production-ready Quarto websites,
blogs, and books following Quarto 1.4+ conventions.

## Rules

1. `_quarto.yml` is the single source of truth for site structure and theme.
2. Never hard-code HTML — use Quarto shortcodes and divs (`::: {.class}`) instead.
3. Use `freeze: auto` in `_quarto.yml` for sites with expensive computations.
4. For blogs, use `listing:` in index to auto-generate post cards.
5. For GitHub Pages, enable gh-pages branch in repo Settings before pushing.
6. Use `quarto::quarto_preview()` for live reload during development.
7. Use callout blocks (`::: {.callout-note}`) for structured admonitions.
