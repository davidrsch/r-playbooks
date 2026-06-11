---
name: r-shiny-fluent-theme
version: 1.0.0
context-mode: Fork
description: "Theme Fluent UI Shiny apps (Appsilon): brand tokens via ThemeProvider, custom colors and typography, dark mode toggle, WCAG accessibility verification"
trigger: both
trigger-patterns:
  - "fluent theme *"
  - "fluent theming *"
  - "fluent dark mode *"
  - "theme fluent *"
  - "customize fluent *"
  - "fluent brand *"
  - "fluent design tokens *"
  - "theming fluent *"
argument-hint: "[--primary <hex>] [--dark-mode true|false] [--font default|segoe|system] [--spacing compact|default|comfortable] [--accessibility WCAG-AA|WCAG-AAA]"
parameters:
  primary:
    type: String
    required: false
    default: "#0078D4"
    hint: "Primary brand color as hex code"
  dark-mode:
    type: Boolean
    required: false
    default: false
    hint: "Implement dark mode with theme toggle"
  font:
    type: String
    required: false
    default: "default"
    enum: ["default", "segoe", "system"]
    hint: "Font family: default (Segoe UI), segoe (explicit), or system (native OS font stack)"
  spacing:
    type: String
    required: false
    default: "default"
    enum: ["compact", "default", "comfortable"]
    hint: "Spacing density: compact (dense data), default, or comfortable (more whitespace)"
  accessibility:
    type: String
    required: false
    default: "WCAG-AA"
    enum: ["WCAG-AA", "WCAG-AAA"]
    hint: "Accessibility compliance target"
steps:
  - id: design-tokens
    inline-prompt: |
      Define Fluent UI design tokens for the brand theme.

      Primary color: {{params.primary}}
      Dark mode: {{params.dark-mode}}
      Font: {{params.font}}
      Spacing: {{params.spacing}}

      1. **Understand the Fluent theming model:**
         Fluent UI uses design tokens, not CSS variables or Sass. Tokens are
         JavaScript objects applied via `ThemeProvider`. `parseTheme()` converts
         R lists into the expected token format.

         Key token categories:
         - **palette**: semantic colors (themePrimary, themeDark, neutral*)
         - **fonts**: size, family, weight per text variant
         - **spacing**: numeric scale (s1, s2, m, l1, l2)
         - **effects**: elevation, rounded corners
         - **isInverted**: boolean for dark mode

      2. **Create the light theme** (`R/theme.R`):
         ```r
         library(shiny.fluent)

         light_theme <- shiny.fluent::parseTheme(list(
           palette = list(
             # Primary brand
             themePrimary   = "{{params.primary}}",
             themeDark      = "<darker_20%>",
             themeDarker    = "<darker_40%>",
             themeLight     = "<lighter_20%>",
             themeLighter   = "<lighter_40%>",
             themeLighterAlt = "<lighter_60%>",

             # Neutral grays
             black          = "#000000",
             neutralDark    = "#201f1e",
             neutralPrimary = "#323130",
             neutralSecondary = "#605e5c",
             neutralTertiary = "#a19f9d",
             neutralLight   = "#edebe9",
             neutralLighter = "#faf9f8",
             white          = "#ffffff",

             # Semantic colors
             redDark        = "#a80000",
             greenDark      = "#0b6a0b",
             yellowDark     = "#8a6d00",
             blueDark       = "#004578"
           ),

           fonts = list(
             tiny   = list(fontSize = 10),
             small  = list(fontSize = 12),
             medium = list(
               # Font family based on params.font ({{params.font}}):
               # "default"/"segoe" → Segoe UI; "system" → native OS font stack
               fontFamily = "<choose_based_on_{{params.font}}>",
               fontSize = 14
             ),
             large  = list(fontSize = 18),
             xLarge = list(fontSize = 20, fontWeight = "bold"),
             xxLarge = list(fontSize = 28, fontWeight = "bold")
           ),

           spacing = list(
             # Spacing scale based on params.spacing ({{params.spacing}}):
             # "compact" → s1=2, s2=4, m=8, l1=12, l2=20
             # "default" → s1=4, s2=8, m=16, l1=20, l2=32
             # "comfortable" → s1=8, s2=12, m=20, l1=28, l2=40
             s1 = 4, s2 = 8, m = 16, l1 = 20, l2 = 32
           ),

           effects = list(
             roundedCorner4 = 4
           )
         ))
         ```

      3. **Create the dark theme** (if {{params.dark-mode}} is true):
         ```r
         dark_theme <- shiny.fluent::parseTheme(list(
           palette = list(
             themePrimary   = "<lighter_primary_for_dark>",
             themeDark      = "<lighter_variant>",
             themeDarker    = "<lighter_variant>",
             themeLight     = "<darker_variant>",
             themeLighter   = "<darker_variant>",
             themeLighterAlt = "<darkest_variant>",

             black          = "#faf9f8",
             neutralDark    = "#faf9f8",
             neutralPrimary = "#f3f2f1",
             neutralSecondary = "#c8c6c4",
             neutralTertiary = "#979593",
             neutralLight   = "#323130",
             neutralLighter = "#1b1a19",
             white          = "#1b1a19"
           ),
           isInverted = TRUE
         ))
         ```

      Report: theme tokens defined and theme objects created.
    gate: Confirm
    output: theme_tokens

  - id: apply-theme
    requires: [design-tokens]
    inline-prompt: |
      Apply the theme to the Fluent UI app via ThemeProvider.

      1. **Wrap the app in ThemeProvider** (update `R/ui.R` or `app.R`):
         ```r
         library(shiny.fluent)
         source("R/theme.R")

         ui <- fluentPage(
           ThemeProvider(
             theme = light_theme,
             div(id = "app_root",
               # All Fluent components inherit the theme automatically
               # No per-component styling needed
               CommandBar(items = list(...)),
               Stack(
                 tokens = list(childrenGap = 20, padding = "20px"),
                 reactOutput("main_content")
               )
             )
           )
         )
         ```

         ThemeProvider applies the token values to every Fluent component
         descendant — buttons, inputs, text, all inherit the brand colors,
         fonts, and spacing automatically.

      2. **Verify theme application:**
         - Run the app: `shiny::runApp()`
         - Buttons should use `{{params.primary}}` as their accent color
         - Text should use the configured font family
         - Spacing should match the density setting ({{params.spacing}})
         - Links, focus rings, and selection highlights should all use the
           theme primary color consistently

      Report: theme applied and visually verified.
    gate: Review
    output: theme_applied

  - id: dark-mode
    requires: [apply-theme]
    inline-prompt: |
      Implement dark mode toggle (when {{params.dark-mode}} is true).

      If dark-mode is false, skip this step.

      1. **Add theme state management** (update `R/server.R`):
         ```r
         # Theme state — initialize reactive values
         is_dark <- reactiveVal(FALSE)
         current_theme <- reactiveVal(light_theme)

         # Toggle handler
         observeEvent(input$toggle_theme, {
           is_dark(!is_dark())
           current_theme(if (is_dark()) dark_theme else light_theme)
         })

         # The entire app UI must be wrapped in reactOutput + renderReact
         # so the theme change triggers a re-render with the new theme
         ```

      2. **Wrap the entire app in reactOutput** (update `R/ui.R`):
         ```r
         ui <- fluentPage(
           reactOutput("themed_app")
         )
         ```

         **Render the app with the current theme** (update `R/server.R`):
         ```r
         output$themed_app <- renderReact({
           ThemeProvider(
             theme = current_theme(),
             div(id = "app_root",
               # All existing UI goes here — CommandBar, Stack, content, etc.
             )
           )
         })
         ```
         This pattern re-renders the entire app with the new theme when
         `current_theme()` changes. `reactOutput` preserves React state
         (scroll, focus, input values) across theme switches.

      3. **Toggle button in the UI:**
         ```r
         # In CommandBar farItems:
         CommandBarItem(
           "", "theme_toggle",
           icon = "Sunny",
           iconOnly = TRUE,
           tooltip = "Toggle dark mode",
           onClick = JS("() => Shiny.setInputValue('toggle_theme', Math.random())")
         )
         ```

      4. **Persist theme preference:**
         ```r
         # Store in shiny cookie or localStorage
         observe({
           shiny::updateQueryString(paste0("?theme=", if (is_dark()) "dark" else "light"),
             mode = "replace")
         })

         # Read on startup
         observe({
           query <- parseQueryString(session$clientData$url_search)
           if (!is.null(query$theme) && query$theme == "dark") {
             is_dark(TRUE)
             current_theme(dark_theme)
           }
         })
         ```

      Report: dark mode toggle working with theme persistence.
    gate: Review
    output: dark_mode_config

  - id: accessibility-check
    requires: [apply-theme]
    inline-prompt: |
      Verify WCAG accessibility compliance.

      Target: {{params.accessibility}}

      1. **Color contrast check:**
         Verify all text/background combinations meet {{params.accessibility}}:
         - AA: 4.5:1 for normal text, 3:1 for large text
         - AAA: 7:1 for normal text, 4.5:1 for large text

         ```r
         # Test primary color against white
         library(colorspace)
         contrast_ratio(
           hex2RGB("{{params.primary}}"),
           hex2RGB("#ffffff")
         )
         # Should be >= 4.5 for WCAG AA on normal text
         ```

         Key combinations to test:
         - Primary button text on primary button background
         - Body text on page background
         - Placeholder text on input background
         - Link text on page background
         - Focus ring visibility

      2. **Keyboard navigation:**
         - [ ] Tab order follows visual layout (left→right, top→bottom)
         - [ ] Focus ring is visible on all interactive elements
         - [ ] Modal traps focus (Tab doesn't escape)
         - [ ] Escape closes Modal/Panel/Dialog
         - [ ] Enter/Space activates buttons
         - [ ] Arrow keys navigate Dropdown/ComboBox options

         Fluent UI components handle most keyboard patterns natively —
         verify they work correctly in the Shiny integration.

      3. **Screen reader support:**
         - [ ] All images have alt text (via `imageAlt` prop)
         - [ ] Form inputs have associated labels
         - [ ] Error messages use `aria-describedby` or `aria-errormessage`
         - [ ] Modal has `titleAriaId` set
         - [ ] Dynamic content changes are announced (use `Announced()`)

         ```r
         # Accessible TextField
         TextField.shinyInput("email",
           label = "Email address",
           ariaLabel = "Enter your email address",
           errorMessage = if (!valid) "Invalid email format"
         )

         # Accessible Modal
         Modal(
           isOpen = TRUE,
           titleAriaId = "dialog_title",
           div(
             h2("Confirm Delete", id = "dialog_title"),
             Text("Are you sure? This action cannot be undone.")
           )
         )

         # Announce dynamic changes
         Announced(
           message = sprintf("Loaded %d records", nrow(data)),
           announcementId = "data_load_announcement"
         )
         ```

      4. **Run automated checks:**
         ```bash
         # Use axe-core or Lighthouse in CI
         npx @axe-core/cli http://localhost:3838 --tags wcag2a,wcag2aa
         ```

      Report: accessibility audit results with any violations and fixes applied.
    gate: Review
    output: accessibility_results

tags:
  - r
  - shiny
  - fluent
  - appsilon
  - theming
  - accessibility
  - design

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER use Bootstrap theming (bslib, shinythemes) with Fluent UI — theme via ThemeProvider and design tokens only."
    severity: "error"
  - rule: "ALWAYS verify WCAG AA contrast ratios for primary brand color against white — button text must be legible."
    severity: "error"
  - rule: "NEVER apply inline CSS colors directly to Fluent components — use theme tokens for consistency."
    severity: "error"
  - rule: "ALWAYS test both light and dark themes — Fluent components may render differently in each mode."
    severity: "warning"
  - rule: "Use parseTheme() to convert R lists to Fluent theme objects — manual theme construction may miss required tokens."
    severity: "warning"
  - rule: "Semantic colors (redDark, greenDark, yellowDark) should convey meaning — red for errors, green for success, not decoration."
    severity: "warning"
---

You are a Fluent UI theming specialist. You design and apply Microsoft Fluent UI
themes to Shiny applications using shiny.fluent (Appsilon) — brand tokens,
design system customization, dark mode, and accessibility compliance.

## Fluent Theming Model

Fluent UI uses a **design token** system, not CSS variables or Sass:

```
Design Tokens (R list)
  → parseTheme() (shiny.fluent)
    → ThemeProvider (React context)
      → Every Fluent component inherits tokens automatically
```

Unlike bslib's Sass-based theming, Fluent tokens are JavaScript objects applied
at runtime. No CSS compilation needed. Tokens cascade through React context —
change them at the ThemeProvider level and every descendant component updates.

## Token Reference

| Category | Key Tokens | Purpose |
|----------|-----------|---------|
| Brand | `themePrimary`, `themeDark`, `themeDarker`, `themeLight`, `themeLighter` | Primary color scale |
| Neutral | `black`, `white`, `neutralPrimary`, `neutralSecondary`, `neutralLight`, `neutralLighter` | Text and backgrounds |
| Semantic | `redDark`, `greenDark`, `yellowDark`, `blueDark` | Error, success, warning, info |
| Fonts | `tiny`, `small`, `medium`, `large`, `xLarge`, `xxLarge` | Text sizing |
| Spacing | `s1`, `s2`, `m`, `l1`, `l2` | Padding and gaps |
| Effects | `roundedCorner4` | Border radius |

## ThemeProvider Pattern

```r
# One ThemeProvider at the app root
ui <- fluentPage(
  ThemeProvider(
    theme = my_theme,
    # ALL Fluent components inside inherit the theme
    div(id = "app", ...)
  )
)
```

Components read tokens from React context — no per-component theme props needed.

## Accessibility Requirements

| Standard | Text Contrast | Large Text | UI Components |
|----------|-------------|-----------|---------------|
| WCAG AA | 4.5:1 | 3:1 | 3:1 |
| WCAG AAA | 7:1 | 4.5:1 | 3:1 |

Fluent UI components are built with accessibility in mind (ARIA attributes,
focus management, keyboard navigation). The theming layer must not break these
— always verify contrast ratios for custom brand colors.
