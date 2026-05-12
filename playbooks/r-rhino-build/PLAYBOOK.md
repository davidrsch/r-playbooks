---
name: r-rhino-build
version: 1.0.0
context-mode: Fork
description: "Build rhino project assets: Sass → CSS compilation, JavaScript bundling, and static asset preparation for deployment"
trigger: both
trigger-patterns:
  - "rhino *"
  - "shiny *"
  - "rhino build *"
  - "build rhino *"
  - "rhino sass *"
  - "build sass *"
  - "compile sass *"
  - "rhino js *"
argument-hint: "[--watch false] [--production true|false]"
parameters:
  watch:
    type: Boolean
    required: false
    default: false
    hint: "Watch Sass files for changes and auto-rebuild (dev mode)"
  production:
    type: Boolean
    required: false
    default: true
    hint: "Production mode: minify CSS/JS output"
steps:
  - id: validate-rhino-project
    inline-prompt: |
      Verify this is a valid rhino project for building:

      1. Check for `.rhino.yml` in the project root.
         If not found, abort: "Not a rhino project."
      2. Read `.rhino.yml` to get build configuration:
         - Sass entry point (typically `app/styles/main.scss`)
         - Output directory for compiled CSS (typically `app/static/` or `www/`)
         - JS entry point, if configured
      3. Verify `app/styles/` directory exists with `.scss` files.
      4. Check Node.js is available: `node --version`
         If not installed, abort: "Node.js >= 16 required for Sass compilation."
      5. Verify npm packages are installed: `npm ls sass` or check `node_modules/`.
         If missing, run: `npm install`
      6. Report: rhino version, Node version, Sass config, output directory.
    output: project-info

  - id: build-sass
    requires:
      - validate-rhino-project
    inline-prompt: |
      Compile Sass (.scss) to CSS:

      1. Run: `rhino::build_sass()`
         This compiles all `.scss` files from `app/styles/` to the configured output dir.
      2. Verify compilation succeeded:
         - No errors in output
         - CSS file(s) generated in the expected output directory
         - Check output file sizes (non-zero)
      3. Report for each compiled file:
         - Source: `app/styles/<name>.scss`
         - Output: `<output-dir>/<name>.css`
         - Size: original vs compiled
      4. If compilation fails:
         - Parse the Sass error message
         - Common issues:
           - Missing `@import` or `@use` paths (check Bootstrap import)
           - Syntax errors in `.scss` files
           - Missing variables or mixins
           - Unclosed brackets or semicolons
         - Suggest specific fixes for each error

      Rhino Sass conventions:
      - Entry point: `app/styles/main.scss`
      - Bootstrap import (if using bslib): `@import "bootstrap/scss/bootstrap";`
      - Custom variables override Bootstrap's: define before the import
      - Module-specific styles: one `.scss` per module in `app/styles/`
      - Use `@use` for partials: `@use "variables" as *;`
    output: sass-results
    gate: Review

  - id: build-js
    requires:
      - validate-rhino-project
    inline-prompt: |
      Bundle JavaScript assets (if applicable):

      1. Check if `app/js/` directory exists and contains `.js` files.
      2. If no JS files exist, report: "No JavaScript to build — skipped."
      3. If JS files exist:
         - Check for bundler config (`webpack.config.js`, `rollup.config.js`, etc.)
         - Read `.rhino.yml` for JS build configuration
         - Run: `rhino::build_js()` if available (rhino >= 1.6)
         - Alternatively, run the configured bundler: `npm run build`
         - Verify output JS file(s) generated
         - Report: source files, output bundle, size
      4. If bundler not configured but JS files exist:
         - Suggest setting up a bundler (webpack/esbuild recommended)
         - For small projects, note that individual `.js` files work without bundling

      Note: Most rhino projects have minimal JS. Complex JS is typically
      bundled with webpack or esbuild.
    output: js-results

  - id: copy-static-assets
    requires:
      - build-sass
    inline-prompt: |
      Ensure static assets are in place for deployment:

      1. Check for static asset directories:
         - `app/static/` (rhino >= 1.10 preferred)
         - `www/` (legacy location)
      2. Verify CSS files are in the right location.
      3. Check for any additional static files the app needs:
         - Images: `.png`, `.jpg`, `.svg` in `app/static/img/`
         - Fonts: `.woff`, `.woff2` in `app/static/fonts/`
         - Favicon: `favicon.ico` in `app/static/`
         - Downloadable files: `.csv`, `.pdf` in `app/static/files/`
      4. Verify `.gitignore` correctly handles built assets:
         - `app/static/css/` should be gitignored (built from Sass)
         - `app/static/js/` should be gitignored (built from bundler)
         - `node_modules/` must be gitignored
      5. Run: `rhino::build_sass()` one more time to confirm final state.
      6. Report: all static assets accounted for, gitignore verified.
    output: static-assets

  - id: verify-build
    requires:
      - build-sass
      - build-js
      - copy-static-assets
    inline-prompt: |
      Verify the build is ready for deployment:

      1. Start the app to verify CSS loads correctly:
         - rhino >= 1.11: `rhino::devmode()`
         - rhino < 1.11: `shiny::runApp("app")`
      2. In the browser, verify:
         - Styles are loading (no unstyled content)
         - Custom CSS classes are applied
         - No 404 errors for CSS/JS files
         - Dark mode works if using bslib theming
      3. If any issues:
         - Check CSS path in `app/main.R` or module files
         - Verify `bslib::bs_theme()` includes the compiled CSS
         - Check for cache issues (try hard refresh)
      4. Stop the app.
      5. If watch mode was requested, start watcher:
         ```r
         rhino::build_sass(watch = TRUE)
         ```
         This auto-rebuilds on .scss changes.
      6. Report: build verification passed/failed, any issues found.
    output: verification
    gate: Review

  - id: build-summary
    requires:
      - build-sass
      - build-js
      - copy-static-assets
      - verify-build
    inline-prompt: |
      Produce a build summary:

      ```
      🦏 Rhino Build Report
      ======================
      Project: <name>
      Mode: <development/production>

      ┌──────────────────┬────────┬──────────────────────────────┐
      │ Asset            │ Status │ Details                      │
      ├──────────────────┼────────┼──────────────────────────────┤
      │ Sass → CSS       │ ✅/❌  │ <n> files compiled           │
      │ JavaScript       │ ✅/⚠️  │ <n> files (skipped)          │
      │ Static Assets    │ ✅/⚠️  │ <n> files verified           │
      │ App Verification │ ✅/❌  │ <status>                     │
      └──────────────────┴────────┴──────────────────────────────┘

      Output directory: <path>
      Build duration: <time>
      ```

      If production mode, note: CSS/JS minified for production.
      If watch mode, note: Watcher is running for Sass changes.
    output: build-report

tags:
  - r
  - shiny
  - rhino
  - build
  - sass
  - css

constraints:
  - rule: "NEVER commit compiled CSS/JS to git — build during CI/CD."
    severity: "warning"
  - rule: "ALWAYS rebuild Sass before deployment."
    severity: "error"
  - rule: "ALWAYS verify Node.js is installed before Sass compilation."
    severity: "error"

allowed-tools:
  - "*"
---

# R Rhino Build Playbook

You are a build engineer for rhino (Appsilon's enterprise Shiny framework) projects.
This playbook compiles Sass to CSS and bundles JavaScript for production deployment.

## Build Architecture

```
app/styles/*.scss  ──[sass compiler]──▶  app/static/css/*.css
app/js/*.js        ──[bundler]───────▶  app/static/js/*.js
```

## Key Commands

| Command                         | Purpose                           |
| ------------------------------- | --------------------------------- |
| `rhino::build_sass()`           | Compile Sass → CSS                |
| `rhino::build_sass(watch=TRUE)` | Watch and auto-rebuild on changes |
| `rhino::build_js()`             | Bundle JavaScript (rhino >= 1.6)  |
| `npm run build`                 | Run custom build script           |
| `npm install`                   | Install Node.js dependencies      |

## Sass Conventions

```scss
// app/styles/main.scss — Entry point

// 1. Bootstrap overrides (before import)
$primary: #0055a4;
$font-family-sans-serif: "Inter", sans-serif;

// 2. Bootstrap import
@import "bootstrap/scss/bootstrap";

// 3. Custom styles
@use "components/cards";
@use "components/tables";
@use "layouts/sidebar";

// 4. Module-specific (one per module)
// app/styles/components/_cards.scss
.card-custom {
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
}
```

## Gitignore (required)

```
# Built assets (compiled from source)
app/static/css/
app/static/js/

# Node.js
node_modules/
package-lock.json

# Rhino
.rhino.yml (may contain secrets — check before committing)
```

## CI/CD Integration

```yaml
# .github/workflows/build.yml
- name: Build Sass
  run: Rscript -e 'rhino::build_sass()'
- name: Build JS
  run: npm run build --if-present
```
