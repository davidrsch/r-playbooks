---
name: r-shiny-theme-bslib
version: 1.0.0
context-mode: Fork
description: Apply a custom Bootstrap 5 theme to a Shiny app using bslib with Sass customization and Bootswatch themes
trigger: both
trigger-patterns:
  - "shiny theme *"
  - "bslib theme *"
  - "bootstrap theme *"
  - "theme shiny *"
  - "custom theme *"
  - "apply theme *"
  - "shiny theming *"
  - "bslib *"
argument-hint: "[--preset shiny|minty|flatly|darkly] [--primary <color>] [--font <google_font>] [--dark-mode true|false]"
parameters:
  preset:
    type: String
    required: false
    default: "shiny"
    enum:
      [
        "shiny",
        "minty",
        "flatly",
        "darkly",
        "litera",
        "lumen",
        "pulse",
        "sandstone",
        "united",
        "cosmo",
        "journal",
        "solar",
        "superhero",
      ]
    hint: "Bootswatch preset or 'shiny' for bslib default (Bootstrap 5 + shiny theme)"
  primary:
    type: String
    required: false
    default: "#007bc2"
    hint: "Primary accent color (hex, e.g., #007bc2 for Bootstrap blue)"
  secondary:
    type: String
    required: false
    default: "#6c757d"
    hint: "Secondary color (hex, default: Bootstrap secondary gray)"
  font:
    type: String
    required: false
    default: ""
    hint: "Google Font for headings (e.g., 'Fira Sans', 'Inter', 'Roboto'). Leave empty for system fonts."
  code_font:
    type: String
    required: false
    default: ""
    hint: "Google Font for code blocks (e.g., 'Fira Code', 'JetBrains Mono'). Leave empty for default monospace."
  font_scale:
    type: Number
    required: false
    default: 1.0
    hint: "Global font size scale factor (0.8 for compact, 1.2 for larger text)"
  dark_mode:
    type: Boolean
    required: false
    default: true
    hint: "Enable automatic dark mode toggle"
steps:
  - id: analyze-ui
    inline-prompt: |
      Analyze the current Shiny app UI to identify theming touchpoints:

      1. Locate the main app file: `app.R`, `ui.R`, or `R/app_ui.R` (golem).
      2. Read the UI definition to identify:
         - Current page layout type: `fluidPage()`, `navbarPage()`, `bootstrapPage()`, `page_navbar()`, `page_sidebar()`, etc.
         - Current Bootstrap version in use (likely Bootstrap 3 if using `fluidPage()` without bslib).
         - Existing theme usage: any `shinythemes::shinytheme()`, `bslib::bs_theme()`, or manual CSS.
         - Custom CSS files loaded via `includeCSS()` or `tags$head()`.
         - Any inline styles (`style = "..."`, `tags$style(...)`).
      3. List all UI components that will be affected by theming:
         - Navigation bars, sidebars, cards, value boxes.
         - Tables (DT, reactable), plots (plotly, ggplot2), inputs.
         - Custom HTML/CSS that overrides Bootstrap defaults.
      4. Report:
         - Current Bootstrap version and page layout.
         - Existing theme configuration.
         - Components needing theme adaptation.
         - Potential conflicts with inline styles.
    output: ui_analysis

  - id: create-theme
    requires: [analyze-ui]
    inline-prompt: |
      Create a custom bslib Bootstrap 5 theme.

      ## Step 1: Build the bs_theme() definition
      Based on parameters:
      - Preset: {{params.preset}}
      - Primary color: {{params.primary}}
      - Secondary color: {{params.secondary}}
      - Heading font: {{params.font}}
      - Code font: {{params.code_font}}
      - Font scale: {{params.font_scale}}
      - Dark mode: {{params.dark_mode}}

      ```r
      library(bslib)

      my_theme <- bs_theme(
        version = 5,
        preset = "{{params.preset}}",
        bg = "#ffffff",
        fg = "#333333",
        primary = "{{params.primary}}",
        secondary = "{{params.secondary}}",
        success = "#28a745",
        info = "#17a2b8",
        warning = "#ffc107",
        danger = "#dc3545",
        base_font = bslib::font_google("{{params.font}}"),
        heading_font = bslib::font_google("{{params.font}}"),
        code_font = bslib::font_google("{{params.code_font}}"),
        # NOTE: font_google() requires internet at render time. For offline/CI use,
        # bundle fonts locally or use system fonts when no internet is available.
        font_scale = {{params.font_scale}}
      )

      # Preview the theme
      bs_theme_preview(my_theme)
      ```

      ## Step 2: Explore the theme's Sass variables
      ```r
      # See all theme variables
      vars <- bs_get_variables(my_theme)
      head(vars, 20)

      # See specific variable groups
      bs_get_variables(my_theme, "^body-")
      bs_get_variables(my_theme, "^navbar-")
      bs_get_variables(my_theme, "^card-")
      ```

      ## Step 3: Verify contrast and accessibility
      ```r
      # Programmatic WCAG contrast check using bslib
      if (requireNamespace("bslib", quietly = TRUE)) {
        contrast <- bs_get_contrast(my_theme, bg = "#ffffff", fg = "#333333")
        # Check primary color contrast
        primary_contrast <- bs_get_contrast(my_theme, bg = "#ffffff", fg = "{{params.primary}}")
      }
      ```

      Report:
      - Theme definition.
      - Bootswatch preset used (or custom).
      - Fonts configured.
      - Color palette summary.
    gate: Confirm
    output: theme_definition

  - id: apply-theme
    requires: [create-theme]
    inline-prompt: |
      Apply the bslib theme to the Shiny app.

      Theme: {{state.theme_definition}}
      Dark mode: {{params.dark_mode}}

      ## Modern page layouts (recommended)
      Choose the appropriate modern layout:

      ### page_navbar(): Multi-page app with top nav
      ```r
      library(bslib)
      library(shiny)

      ui <- page_navbar(
        theme = my_theme,
        title = "App Title",
        id = "nav",

        # Dark mode toggle in the navbar
        nav_spacer(),
        nav_item(input_dark_mode()),

        nav_panel("Home",
          page_sidebar(
            sidebar = sidebar("Sidebar content"),
            layout_column_wrap(
              width = 1/3,
              value_box("Revenue", "$12,345", showcase = bsicons::bs_icon("graph-up")),
              value_box("Users", "1,234", showcase = bsicons::bs_icon("people")),
              value_box("Conversion", "3.2%", showcase = bsicons::bs_icon("percent"))
            ),
            card(
              card_header("Main Content"),
              plotOutput("main_plot")
            )
          )
        ),

        nav_panel("Settings",
          card(
            card_header("Settings"),
            # Settings UI here
          )
        )
      )
      ```

      ### page_sidebar(): Dashboard with sidebar
      ```r
      ui <- page_sidebar(
        theme = my_theme,
        title = "Dashboard",
        sidebar = sidebar(
          bg = "#f8f9fa",
          selectInput("var", "Variable", choices = names(mtcars))
        ),
        layout_column_wrap(
          width = "250px",
          value_box(
            title = "KPI 1",
            value = textOutput("kpi1"),
            showcase = bsicons::bs_icon("speedometer2")
          )
        ),
        navset_card_tab(
          nav_panel("Plot", plotOutput("plot")),
          nav_panel("Table", tableOutput("table"))
        )
      )
      ```

      ### Legacy upgrade path: bootstrapPage() / fluidPage()
      For existing apps not ready to switch to page_navbar/page_sidebar:
      ```r
      ui <- fluidPage(
        theme = my_theme,
        # For dark mode toggle, add to the page:
        input_dark_mode(),
        # ... existing UI ...
      )
      ```

      ## Implementation steps:
      1. Replace the existing UI layout with the bslib-powered version.
      2. Replace `shinythemes::shinytheme("...")` with `theme = my_theme`.
      3. Replace `navbarPage()` with `page_navbar()`.
      4. Replace `sidebarLayout()` with `page_sidebar()`.
      5. Replace `box()` (shinydashboard) with `card()`.
      6. Replace `infoBox()` / `valueBox()` with `value_box()`.
      7. If dark mode is enabled ({{params.dark_mode}}), add `input_dark_mode()`.

      Report: the modified UI code, which components were replaced, and the new layout.
    gate: Approve
    output: applied_theme

  - id: customize-sass
    requires: [apply-theme]
    inline-prompt: |
      Add custom Sass rules for advanced styling beyond the theme variables.

      ## Add custom Sass rules
      ```r
      # NOTE: bs_add_variables() (Sass variables) MUST come BEFORE bs_add_rules() (CSS rules)
      # in the theme pipeline. Variables define values; rules consume them.
      my_theme <- my_theme |>
        bs_add_rules(
          # Custom card styling
          ".card { border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }",

          # Custom navbar
          ".navbar { backdrop-filter: blur(10px); }",

          # Custom button styles
          ".btn-primary { font-weight: 600; letter-spacing: 0.5px; }",

          # Improve table readability
          ".table { font-size: 0.9rem; }",

          # Custom value box styling
          ".bslib-value-box { transition: transform 0.2s; }",
          ".bslib-value-box:hover { transform: translateY(-2px); }",

          # Better code blocks
          "pre, code { border-radius: 6px; }"
        )
      ```

      ## Add/override specific Bootstrap Sass variables
      ```r
      my_theme <- my_theme |>
        bs_add_variables(
          "body-bg" = "#fafbfc",
          "navbar-light-bg" = "#ffffff",
          "card-cap-bg" = "#ffffff",
          "border-radius" = "0.5rem",
          "border-radius-lg" = "0.75rem",
          "input-btn-padding-y" = "0.5rem",
          "input-btn-padding-x" = "1rem",
          "btn-border-radius" = "0.375rem",
          "headings-font-weight" = "600"
        )
      ```

      ## Preview changes live
      ```r
      bs_theme_preview(my_theme)
      ```

      ## Considerations:
      1. Use `bs_add_rules()` for CSS overrides that don't map to Bootstrap variables.
      2. Use `bs_add_variables()` for Bootstrap-specific Sass variables.
      3. Keep custom rules minimal: prefer Bootstrap utilities and variables.
      4. Test dark mode with custom rules: use data attribute selectors:
         ```css
         [data-bs-theme="dark"] .custom-class { ... }
         ```

      5. Report:
         - Custom rules added and their purpose.
         - Sass variables overridden.
         - Dark mode compatibility notes.
    gate: Review
    output: sass_customizations

  - id: verify-theme
    requires: [customize-sass]
    inline-prompt: |
      Verify the theme is correctly applied and visually polished.

      ## Step 1: Run the app
      ```r
      shiny::runApp()
      ```
      The app should launch with the new bslib theme applied.

      ## Step 2: Use bs_themer() for interactive tuning
      In the R console (while the app is NOT running):
      ```r
      library(bslib)
      bs_themer()
      shiny::runApp()
      ```

      This adds a "Theme" gear icon in the app that opens an interactive editor for:
      - Main colors (primary, secondary, success, etc.).
      - Font selections (base, heading, code).
      - Font scale.
      - Spacing options.

      ## Step 3: Verify theme components checklist
      ✅ Page layout renders correctly with new theme.
      ✅ Navbar/sidebar uses theme colors and fonts.
      ✅ Cards have proper borders, shadows, and padding.
      ✅ Value boxes display correctly with icons.
      ✅ Dark mode toggle switches themes without visual glitches.
      ✅ Form inputs (select, text, numeric) are themed.
      ✅ Tables (DT, reactable) match the theme.
      ✅ Plotly/ggplot2 outputs blend with the theme background.
      ✅ Code blocks have correct syntax highlighting in both modes.
      ✅ Mobile responsive: sidebar collapses, navbar adapts.
      ✅ Fonts load correctly (Google Fonts reachable).
      ✅ No console errors or CSS warnings.

      ## Step 4: Run existing tests
      If the app has testthat or shinytest2 tests:
      ```r
      devtools::test()
      ```
      Ensure no tests break due to UI changes.

      ## Step 5: Collect theme settings for reproducibility
      ```r
      # Save the final theme R code
      dput(my_theme)

      # Or save as RDS for later use
      saveRDS(my_theme, "inst/theme.rds")

      # For RMarkdown / Quarto: set theme dependencies explicitly
      # bslib::bs_theme_deps(my_theme)
      ```

      Report:
      - Visual verification results.
      - Any issues with dark mode.
      - Test pass/fail status.
      - Final theme code for reproducibility.
    gate: Review
    output: verification

tags:
  - r
  - shiny
  - bslib
  - bootstrap
  - theme
  - sass
  - ui

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER use global variables for app state — use reactiveValues."
    severity: "error"
  - rule: "NEVER use source() inside reactive expressions."
    severity: "error"
  - rule: "ALWAYS validate user inputs server-side, not just client-side."
    severity: "warning"
  - rule: "Use Shiny modules for reusable UI components."
    severity: "warning"
  - rule: "Use logger package for structured logging, not print() or cat()."
    severity: "warning"
---

You are a Shiny UI/UX specialist, expert in {bslib} for theming Shiny applications
with Bootstrap 5, Sass customization, and Bootswatch presets.

## Rules

1. ALWAYS use `bs_theme(version = 5)`: Bootstrap 5 is the current standard.
2. ALWAYS use `page_navbar()` or `page_sidebar()` for new apps instead of `fluidPage()`.
3. ALWAYS use `value_box()` for KPI/metric cards instead of `shinydashboard::valueBox()`.
4. ALWAYS use `card()` and `card_header()` instead of `shinydashboard::box()`.
5. ALWAYS add `input_dark_mode()` when dark mode support is needed.
6. ALWAYS use `font_google()` for heading/code fonts: it auto-handles Google Fonts imports.
7. ALWAYS use `bs_add_rules()` for custom CSS, not inline `tags$style()`.
8. ALWAYS use `bs_add_variables()` for Bootstrap Sass variable overrides.
9. ALWAYS run `bs_themer()` to interactively tune the theme before finalizing.
10. PREFER `preset = "shiny"` (the bslib default) for general apps: it's already polished.
11. USE Bootswatch presets for quick alternative looks without custom CSS.
12. NEVER use `shinythemes` alongside bslib: bslib replaces it entirely.
13. ALWAYS test dark mode with all custom rules: CSS must use `[data-bs-theme="dark"]` selectors.
14. ALWAYS verify Google Fonts load correctly (internet required at render time).
15. PREFER `layout_column_wrap()` over `fluidRow()` + `column()` for responsive grids.
