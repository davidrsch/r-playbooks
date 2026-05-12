---
name: r-pkgdown-site
version: 1.0.0
context-mode: Fork
description: Set up and deploy a pkgdown documentation site with Bootstrap 5, reference index, articles, and GitHub Pages
trigger: both
trigger-patterns:
  - "pkgdown *"
  - "documentation *"
  - "pkgdown site *"
  - "set up pkgdown *"
  - "build pkgdown *"
  - "documentation site *"
  - "deploy pkgdown *"
  - "pkgdown deploy *"
argument-hint: "[--url <site_url>] [--template bootswatch] [--deploy true|false] [--articles true|false]"
parameters:
  url:
    type: String
    required: false
    hint: "Site URL (e.g., https://org.github.io/pkg). Auto-detected from DESCRIPTION if not provided."
  template:
    type: String
    required: false
    default: "default"
    enum: ["default", "bootswatch", "bslib"]
    hint: "Template theming: default (Bootstrap 5), bootswatch, or bslib custom theme"
  bootswatch:
    type: String
    required: false
    default: "flatly"
    enum:
      [
        "default",
        "cerulean",
        "cosmo",
        "cyborg",
        "darkly",
        "flatly",
        "journal",
        "litera",
        "lumen",
        "lux",
        "materia",
        "minty",
        "morph",
        "pulse",
        "quartz",
        "sandstone",
        "simplex",
        "sketchy",
        "slate",
        "solar",
        "spacelab",
        "superhero",
        "united",
        "vapor",
        "yeti",
        "zephyr",
      ]
    hint: "Bootswatch theme name (only used when template is bootswatch)"
  deploy:
    type: Boolean
    required: false
    default: false
    hint: "Set up GitHub Actions to auto-deploy to GitHub Pages"
  articles:
    type: Boolean
    required: false
    default: true
    hint: "Build and include vignettes/articles"
steps:
  - id: configure-pkgdown
    inline-prompt: |
      Create or update `_pkgdown.yml` to configure the documentation site.

      1. If `_pkgdown.yml` already exists, read it and preserve existing settings.
      2. Determine the site URL:
         - If {{params.url}} is provided, use it.
         - Otherwise, check DESCRIPTION for `URL:` field.
         - If neither exists, prompt to set one (required for canonical URLs).
      3. Create/update `_pkgdown.yml`:

      ```yaml
      url: <site_url>
      title: <package_title>

      template:
        bootstrap: 5
        {% if {{params.template}} == "bootswatch" %}
        bootswatch: {{params.bootswatch}}
        {% elif {{params.template}} == "bslib" %}
        bslib:
          primary: "#0055AA"
          heading_font:
            google: "Fira Sans"
          code_font:
            google: "Fira Code"
        {% endif %}

      development:
        mode: auto
        destination: dev
        version_label: danger
        version_tooltip: "Development version"

      navbar:
        structure:
          left: [intro, reference, articles, news]
          right: [search, github, lightswitch]
        components:
          lightswitch:
            icon: fa-sun

      reference:
        - title: "Core Functions"
          desc: "Primary functions for package users"
          contents:
            - has_concept("core")
        - title: "Utilities"
          desc: "Helper and internal functions"
          contents:
            - has_concept("internal")
        - title: "All Functions"
          desc: "Complete function index"
          contents:
            - matches(".*")

      articles:
        - title: "Getting Started"
          navbar: "Getting Started"
          contents:
            - starts_with("getting-started")
        - title: "Advanced Topics"
          contents:
            - starts_with("advanced")

      search:
        exclude: ['news/index.html']

      news:
        releases:
          text: "CHANGELOG"
        cran_dates: true
      ```

      4. If the package uses `box::` modules, add:
         ```yaml
         reference:
           - title: "Box Modules"
             contents:
               - starts_with("mod_")
         ```

      5. Report:
         - Which fields were added vs preserved.
         - Detected URL.
         - Template configuration.
         - Reference structure (number of sections/categories).
    gate: Confirm
    output: pkgdown_config

  - id: build-site
    requires: [configure-pkgdown]
    inline-prompt: |
      Build the pkgdown documentation site.

      1. Install pkgdown if not already installed:
         ```r
         renv::install("pkgdown")
         ```

      2. Run the build:
         ```r
         pkgdown::build_site(
           preview = FALSE,
           new_process = TRUE,
           devel = FALSE
         )
         ```

      3. Inspect the generated site:
         - `docs/` directory created at project root.
         - `docs/index.html`: landing page.
         - `docs/reference/index.html`: function reference.
         - `docs/articles/`: vignettes/articles.
         - `docs/news/`: changelog/news.

      4. For Bootstrap 5 theming, verify:
         - Light/dark mode toggle appears on each page.
         - Code syntax highlighting works.
         - Search bar is functional.

      5. If articles are enabled ({{params.articles}}):
         - Ensure all vignettes in `vignettes/` were built.
         - Check that article navigation works.

      6. Report:
         - Number of pages generated.
         - Any build warnings or errors.
         - Dark mode toggle status.
         - Article build status.
    gate: Review
    output: build_result

  - id: check-site
    requires: [build-site]
    inline-prompt: |
      Verify the pkgdown site quality:

      1. Run pkgdown checks:
         ```r
         pkgdown::check_pkgdown()
         ```
         This verifies:
         - All internal links resolve.
         - All reference topics have documentation.
         - Navbar structure is valid.

      2. Check for broken URLs:
         ```r
         # Install urlchecker if not available
         if (!requireNamespace("urlchecker", quietly = TRUE)) {
           renv::install("urlchecker")
         }
         urlchecker::url_check()
         ```
         Fix or report any broken external links.

      3. Check for common issues:
         - Orphaned `.Rd` files (documented but not in reference index).
         - Functions exported but not documented.
         - Missing `@examples` sections.
         - Missing `@return` tags.

      4. Run R CMD check to ensure consistent documentation:
         ```r
         devtools::check(
           args = c("--no-manual", "--no-vignettes", "--as-cran"),
           quiet = TRUE
         )
         ```

      5. Verify the site renders correctly:
         - Open `docs/index.html` in a browser or serve locally:
           ```r
           servr::httd("docs")
           ```
         - Check: nav links, search, mobile responsiveness, code copy buttons.

      Report:
      - pkgdown check result (errors/warnings).
      - URL check result (broken links count).
      - R CMD check result.
      - Manual review items.
    output: check_result

  - id: deploy-gh-pages
    requires: [check-site]
    inline-prompt: |
      Set up automated deployment to GitHub Pages.

      Deploy requested: {{params.deploy}}

      If {{params.deploy}} is false: Skip deployment setup. Report manual deploy instructions:
      ```r
      # Manual deploy
      usethis::use_pkgdown_github_pages()
      # Or manually:
      # git checkout --orphan gh-pages
      # copy docs/* to root, commit, push
      # Settings → Pages → Source: Deploy from branch → gh-pages → /(root)
      ```

      If {{params.deploy}} is true:

      ## Step 1: Run usethis helper
      ```r
      usethis::use_pkgdown_github_pages()
      ```
      This creates/updates `.github/workflows/pkgdown.yaml`.

      ## Step 2: Verify the workflow
      The generated workflow should contain:
      ```yaml
      on:
        push:
          branches: [main, master]
        pull_request:
          branches: [main, master]
        workflow_dispatch:

      name: pkgdown

      jobs:
        pkgdown:
          runs-on: ubuntu-latest
          env:
            GITHUB_PAT: ${{ '{{' }} secrets.GITHUB_TOKEN }}
          permissions:
            contents: write
          steps:
            - uses: actions/checkout@v4

            - uses: r-lib/actions/setup-pandoc@v2

            - uses: r-lib/actions/setup-r@v2
              with:
                use-public-rspm: true

            - uses: r-lib/actions/setup-r-dependencies@v2
              with:
                extra-packages: any::pkgdown, local::.
                needs: website

            - name: Build site
              run: pkgdown::build_site_github_pages(new_process = FALSE, install = FALSE)
              shell: Rscript {0}

            - name: Upload pkgdown artifacts on failure
              if: failure()
              uses: actions/upload-artifact@v4
              with:
                name: pkgdown-build-logs
                path: |
                  docs/
                  *.Rcheck/
                retention-days: 7

            - name: Deploy to GitHub Pages
              if: github.event_name != 'pull_request'
              uses: peaceiris/actions-gh-pages@v4
              with:
                github_token: ${{ '{{' }} secrets.GITHUB_TOKEN }}
                publish_dir: ./docs
      ```

      ## Step 3: Configure GitHub Pages
      - Go to repository Settings → Pages.
      - Source: "Deploy from a branch".
      - Branch: `gh-pages` → `/ (root)`.
      - Or: use GitHub Actions as the source.

      ## Step 4: Trigger initial deploy
      - Commit and push the workflow file.
      - The first deploy will run automatically.
      - Or trigger manually: Actions → pkgdown → Run workflow.

      Report:
      - Workflow file created/updated.
      - GitHub Pages configuration instructions.
      - First deploy trigger method.
    gate: Review
    output: deploy_setup

  - id: verify-deploy
    requires: [deploy-gh-pages]
    inline-prompt: |
      Verify the deployed pkgdown site.

      1. Determine the deployed URL:
         - From `_pkgdown.yml`: the `url` field.
         - Or from GitHub Pages: `https://<owner>.github.io/<repo>/`.

      2. Visit the deployed site and verify:
         - Home page loads.
         - Reference index lists all exported functions.
         - Each function page shows title, description, usage, arguments, examples.
         - Articles/vignettes load correctly.
         - News/Changelog is accessible.
         - Search returns relevant results.
         - Light/dark mode toggle works.
         - Mobile layout is responsive.
         - All internal links resolve (no 404s).

      3. Check SEO basics:
         - `<title>` tags are populated.
         - Meta description is present.
         - Canonical URLs are set correctly.
         - `robots.txt` is generated (if search exclusion configured).

      4. Run link checker on live site:
         ```r
         urlchecker::url_check()
         ```

      5. Report:
         - Site URL.
         - Page load status (all pages accessible).
         - Any broken links or rendering issues.
         - SEO checklist results.
    gate: Review
    output: deploy_verification

tags:
  - r
  - pkgdown
  - documentation
  - site
  - github-pages
  - bootstrap

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER modify NAMESPACE manually — roxygen2 manages it."
    severity: "error"
  - rule: "NEVER commit to main without passing R CMD check."
    severity: "error"
  - rule: "ALWAYS run devtools::document() after changing roxygen comments."
    severity: "warning"
  - rule: "NEVER use install.packages() in scripts — use renv or DESCRIPTION."
    severity: "error"
  - rule: "ALWAYS run devtools::test() before committing."
    severity: "warning"
  - rule: "Use rlang::abort() or cli::cli_abort() over stop() for errors."
    severity: "warning"
---

You are an R documentation specialist, expert in {pkgdown} for building
Bootstrap-based documentation websites for R packages.

## Rules

1. ALWAYS run `pkgdown::build_site()` with `new_process = TRUE` for clean builds.
2. ALWAYS set `url` in `_pkgdown.yml` for canonical URL generation.
3. ALWAYS use Bootstrap 5 via `template.bootstrap: 5` in `_pkgdown.yml`.
4. ALWAYS add `lightswitch` to the navbar for dark mode support.
5. ALWAYS configure `reference` with explicit title/contents sections: not just `- has_concept(...)`.
6. ALWAYS run `pkgdown::check_pkgdown()` before deploying.
7. ALWAYS use `usethis::use_pkgdown_github_pages()` for GitHub Pages setup.
8. ALWAYS build articles from `vignettes/` directory: they are the primary user guides.
9. NEVER deploy without running URL checks first.
10. PREFER `bootswatch` themes for quick, polished theming.
11. PREFER `bslib` for custom color/font theming beyond Bootswatch presets.
12. ALWAYS verify the deployed site loads all pages without 404 errors.
