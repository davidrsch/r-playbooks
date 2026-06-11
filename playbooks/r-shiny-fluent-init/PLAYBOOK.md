---
name: r-shiny-fluent-init
version: 1.0.0
context-mode: Fork
description: "Scaffold a Shiny app with Microsoft Fluent UI (Appsilon): fluentPage shell, ThemeProvider, Stack layout, Fluent inputs, and tests — the Bootstrap-free alternative for enterprise Shiny"
trigger: both
trigger-patterns:
  - "fluent *"
  - "shiny fluent *"
  - "fluent ui *"
  - "init fluent *"
  - "scaffold fluent *"
  - "new fluent *"
  - "fluent app *"
  - "fluent shiny *"
  - "microsoft fluent *"
argument-hint: "--name <app> [--theme default|custom] [--primary <hex>] [--layout header-nav|nav-only|minimal] [--dark-mode true|false]"
parameters:
  name:
    type: String
    required: true
    hint: "Application name (snake_case, used as directory name)"
  theme:
    type: String
    required: false
    default: "default"
    enum: ["default", "custom"]
    hint: "Theme: default (Fluent design system defaults) or custom (brand-configured tokens)"
  primary:
    type: String
    required: false
    default: "#0078D4"
    hint: "Primary brand color as hex code (used when theme=custom)"
  layout:
    type: String
    required: false
    default: "header-nav"
    enum: ["header-nav", "nav-only", "minimal"]
    hint: "Layout pattern: header with top nav, sidebar nav only, or minimal single-page"
  dark-mode:
    type: Boolean
    required: false
    default: false
    hint: "Enable dark mode support (adds theme toggle)"
steps:
  - id: install-dependencies
    inline-prompt: |
      Install shiny.fluent and its dependencies.

      1. Install core packages:
         ```r
         install.packages(c("shiny.fluent", "shiny.react", "shiny"))
         # shiny.fluent v0.4.0+ requires shiny.react v0.4.0+
         ```

      2. Verify installation:
         ```r
         library(shiny.fluent)
         library(shiny.react)
         packageVersion("shiny.fluent")  # >= 0.4.0
         packageVersion("shiny.react")   # >= 0.4.0
         ```

      3. Install optional companion packages:
         ```r
         # For client-side routing (recommended):
         install.packages("shiny.router")
         # For internationalization:
         install.packages("shiny.i18n")
         # For icons beyond Fluent's built-in set:
         # shiny.fluent bundles Fluent UI icons; no extra package needed
         ```

      4. Initialize renv for reproducibility:
         ```r
         renv::init(project = "{{params.name}}")
         ```

      Report: packages installed and versions confirmed.
    output: deps_installed

  - id: create-app-structure
    requires: [install-dependencies]
    inline-prompt: |
      Create the Fluent UI Shiny app structure.

      Name: {{params.name}}
      Layout: {{params.layout}}

      1. **Create project directory:**
         ```
         {{params.name}}/
         ├── app.R              # Main app entry point
         ├── R/
         │   ├── ui.R           # UI definition (Fluent components)
         │   ├── server.R       # Server logic
         │   └── theme.R        # ThemeProvider configuration
         ├── www/               # Static assets (empty — Fluent uses JS, not CSS files)
         ├── tests/
         │   └── testthat/
         │       └── test-app.R
         └── renv.lock
         ```

      2. **Create `app.R` — entry point:**
         ```r
         library(shiny)
         library(shiny.fluent)

         source("R/theme.R")
         source("R/ui.R")
         source("R/server.R")

         shinyApp(ui, server)
         ```

      3. **Create `R/ui.R` — Fluent UI shell** based on layout ({{params.layout}}):

         **header-nav layout** (default):
         ```r
         ui <- fluentPage(
           # Header with CommandBar
           div(class = "ms-Grid", style = "height: 100vh; display: flex; flex-direction: column;",
             CommandBar(
               items = list(
                 CommandBarItem("Home", "Home", icon = "Home"),
                 CommandBarItem("Reports", "Reports", icon = "BarChartVertical"),
                 CommandBarItem("Settings", "Settings", icon = "Settings")
               ),
               farItems = list(
                 CommandBarItem("", "theme", icon = if ({{params.dark-mode}}) "Sunny" else "ClearNight",
                   onClick = JS("() => Shiny.setInputValue('toggle_theme', Math.random())"))
               ),
               style = list(borderBottom = "1px solid #edebe9")
             ),
             # Main content area
             div(style = "flex: 1; overflow: auto; padding: 20px;",
               h1("{{params.name}}"),
               Text("Welcome to your Fluent UI application."),
               Stack(
                 tokens = list(childrenGap = 15),
                 PrimaryButton("action_btn", "Get Started"),
                 reactOutput("content_area")
               )
             )
           )
         )
         ```

         **nav-only layout:**
         ```r
         ui <- fluentPage(
           Nav(
             groups = list(
               list(name = "Navigation", links = list(
                 list(name = "Home", url = "#!/home", icon = "Home", key = "home"),
                 list(name = "Reports", url = "#!/reports", icon = "BarChartVertical", key = "reports"),
                 list(name = "Settings", url = "#!/settings", icon = "Settings", key = "settings")
               ))
             ),
             selectedKey = "home",
             style = list(width = 250, height = "100vh", position = "fixed")
           ),
           div(style = "margin-left: 250px; padding: 20px;",
             reactOutput("page_content")
           )
         )
         ```

         **minimal layout:**
         ```r
         ui <- fluentPage(
           div(style = "max-width: 800px; margin: 0 auto; padding: 40px 20px;",
             h1("{{params.name}}"),
             Text("A focused Fluent UI application."),
             reactOutput("main")
           )
         )
         ```

      Report: project structure created with the selected layout.
    gate: Confirm
    output: app_structure

  - id: configure-theme
    requires: [create-app-structure]
    inline-prompt: |
      Configure Fluent UI theming with ThemeProvider.

      Theme: {{params.theme}}
      Primary color: {{params.primary}}
      Dark mode: {{params.dark-mode}}

      1. **Create `R/theme.R`:**

         **Default theme:**
         ```r
         # R/theme.R — Default Fluent design system theme
         # No custom tokens needed; Fluent UI defaults are production-ready.
         # ThemeProvider is used automatically by fluentPage().
         ```

         **Custom theme:**
         ```r
         # R/theme.R — Brand-configured Fluent UI theme
         library(shiny.fluent)

         # Design tokens: https://developer.microsoft.com/en-us/fluentui#/styles/web/colors/theme-slots
         custom_theme <- list(
           palette = list(
             themePrimary   = "{{params.primary}}",
             themeLighterAlt = "<lighter_variant>",
             themeDark      = "<darker_variant>",
             neutralLighter = "#faf9f8",
             neutralLight   = "#edebe9",
             neutralPrimary = "#323130",
             white          = "#ffffff",
             black          = "#000000"
           ),
           fonts = list(
             medium = list(
               fontFamily = "'Segoe UI', 'Segoe UI Web (West European)', -apple-system, sans-serif",
               fontSize = 14
             )
           ),
           spacing = list(
             s1 = 4, s2 = 8, m = 16, l1 = 20, l2 = 32
           )
         )

         # Parse into Fluent-compatible theme object
         fluent_theme <- shiny.fluent::parseTheme(custom_theme)
         ```

         **With dark mode:**
         ```r
         # R/theme.R — Light + dark mode support
         library(shiny.fluent)

         light_theme <- shiny.fluent::parseTheme(list(
           palette = list(themePrimary = "{{params.primary}}")
         ))

         dark_theme <- shiny.fluent::parseTheme(list(
           palette = list(
             themePrimary   = "<lighter_variant>",
             neutralLighter = "#1b1a19",
             neutralLight   = "#323130",
             neutralPrimary = "#faf9f8"
           ),
           isInverted = TRUE
         ))
         ```

      2. **Wrap UI with ThemeProvider** (update `R/ui.R`):
         ```r
         ui <- fluentPage(
           # Wrap everything in ThemeProvider
           ThemeProvider(
             theme = fluent_theme,
             div(id = "app_root",
               # ... existing UI from step 2 ...
             )
           )
         )
         ```

      3. **Add dark mode toggle in server** (if {{params.dark-mode}} is true):
         ```r
         # R/server.R
         server <- function(input, output, session) {
           dark_mode <- reactiveVal(FALSE)

           observeEvent(input$toggle_theme, {
             dark_mode(!dark_mode())
             session$sendCustomMessage("setTheme",
               if (dark_mode()) dark_theme else light_theme
             )
           })
         }
         ```

      Report: theme configured. If custom, note the brand tokens applied.
    gate: Review
    output: theme_config

  - id: configure-server
    requires: [create-app-structure]
    inline-prompt: |
      Set up the server logic with Fluent-compatible Shiny bindings.

      1. **Create `R/server.R`:**
         ```r
         library(shiny)
         library(shiny.fluent)

         server <- function(input, output, session) {

           # ── Reactive state ──────────────────────────────────────────
           # Fluent inputs use input$<id> just like base Shiny inputs
           # The .shinyInput() suffix is only in the UI; server reads input$<id>

           # ── Fluent Output Patterns ──────────────────────────────────

           # Pattern A: reactOutput + renderReact (for dynamic Fluent content)
           output$content_area <- renderReact({
             if (is.null(input$action_btn) || input$action_btn == 0) {
               Text("Click the button to load data.")
             } else {
               Stack(
                 tokens = list(childrenGap = 10),
                 Text("Data loaded successfully!", variant = "medium"),
                 ProgressIndicator(
                   label = "Processing...",
                   percentComplete = 0.67
                 )
               )
             }
           })

           # Pattern B: Standard Shiny outputs (plot, table, text)
           # These work unchanged with Fluent UI — use renderPlot, renderText, etc.

           # Pattern C: Fluent-specific updates
           # Use Shiny's observe + update pattern for Fluent inputs:
           observeEvent(input$reset_btn, {
             # Reset a Fluent dropdown
             session$sendInputMessage("my_dropdown", list(selectedKey = NULL))
           })

           # ── Navigation (if using Nav or Pivot) ──────────────────────
           observeEvent(input$page_selection, {
             output$page_content <- renderReact({
               switch(input$page_selection,
                 home = Text("Home page content"),
                 reports = Text("Reports page content"),
                 settings = Text("Settings page content"),
                 Text("Select a page")
               )
             })
           })

         }
         ```

      2. **Verify the app loads:**
         ```r
         shiny::runApp("{{params.name}}")
         ```
         The app should render in the browser with the Fluent UI shell.

      Report: server configured and app verified working.
    gate: Review
    output: server_config

  - id: add-tests
    requires: [configure-server]
    inline-prompt: |
      Set up test infrastructure for the Fluent UI app.

      1. **Unit tests with testthat:**
         ```r
         # tests/testthat.R
         library(testthat)
         library(shiny)
         test_check("{{params.name}}")
         ```

         ```r
         # tests/testthat/test-server.R
         test_that("server initializes without errors", {
           testServer(server, {
             expect_true(TRUE)  # smoke test
           })
         })
         ```

      2. **E2E tests with shinytest2:**
         ```r
         # tests/testthat/test-e2e.R
         library(shinytest2)

         test_that("app loads and renders Fluent UI shell", {
           app <- AppDriver$new(app_dir = ".", name = "smoke-test")
           app$expect_text("h1", "{{params.name}}")
           app$stop()
         })

         test_that("Fluent button click triggers action", {
           app <- AppDriver$new(app_dir = ".", name = "button-test")
           # Fluent buttons use Shiny input bindings — click works normally
           app$click("action_btn")
           app$wait_for_idle()
           # Verify the expected output appeared
           app$stop()
         })
         ```

      3. **Run tests:**
         ```r
         testthat::test_dir("tests/testthat/")
         ```

      Report: tests created and passing.
    gate: Review
    output: test_results

tags:
  - r
  - shiny
  - fluent
  - appsilon
  - init
  - scaffold

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER load bslib or shinythemes alongside shiny.fluent — Bootstrap CSS conflicts with Fluent UI styling even though fluentPage() suppresses Bootstrap by default."
    severity: "error"
  - rule: "ALWAYS use fluentPage() as the page shell, not fluidPage() or navbarPage() — Fluent UI has its own layout and navigation system."
    severity: "error"
  - rule: "NEVER use shinythemes or bslib alongside shiny.fluent — theme via ThemeProvider, not Sass variables."
    severity: "error"
  - rule: "ALWAYS verify shiny.fluent >= 0.4.0 and shiny.react >= 0.4.0 are installed before scaffolding."
    severity: "warning"
  - rule: "Use reactOutput() + renderReact() for dynamic Fluent content, not renderUI() — reactOutput preserves React state."
    severity: "warning"
  - rule: "Fluent inputs use .shinyInput() suffix in UI but are accessed as input$<id> in server — no .shinyInput in server code."
    severity: "warning"
---

You are a Shiny + Fluent UI init specialist. You scaffold production-ready
Shiny applications using Microsoft Fluent UI (shiny.fluent, Appsilon) — the
Bootstrap-free design system for enterprise Shiny.

## Fluent UI vs Bootstrap Shiny

| Concern | Bootstrap Shiny | Fluent UI Shiny |
|---------|----------------|-----------------|
| Page shell | `fluidPage()`, `navbarPage()` | `fluentPage()` |
| Layout | `fluidRow()` + `column()` grid | `Stack()` (horizontal/vertical) |
| Inputs | `textInput()`, `selectInput()` | `TextField.shinyInput()`, `Dropdown.shinyInput()` |
| Buttons | `actionButton()` | `PrimaryButton()`, `DefaultButton()`, `CommandBarButton()` |
| Theming | `bslib::bs_theme()` (Sass) | `ThemeProvider()` (design tokens) |
| Navigation | `tabsetPanel()`, `navbarMenu()` | `Pivot()`, `Nav()`, `CommandBar()` |
| Data display | `DT`, `reactable` | `DetailsList()` |
| React state | Not preserved on re-render | Preserved via `reactOutput()` |
| Dark mode | `bslib` v5 support | `ThemeProvider` with `isInverted: TRUE` |

## shiny.fluent Architecture

shiny.fluent wraps Microsoft's Fluent UI React components via shiny.react. Each
component is an R function that generates a React element:

```
R: PrimaryButton("btn", "Click Me")
 → JS: <PrimaryButton onClick={Shiny.setInputValue("btn", ...)}>Click Me</PrimaryButton>
 → Shiny: input$btn increments on click
```

Key principles:
- `.shinyInput()` suffix on inputs: `Dropdown.shinyInput("id", ...)` → `input$id`
- `update*()` functions for server-side control: `updateDropdown(session, "id", ...)`
- `reactOutput()` + `renderReact()` for dynamic Fluent content
- `JS()` for literal JavaScript in props
- Bootstrap is suppressed automatically — do not load bslib or shinythemes
