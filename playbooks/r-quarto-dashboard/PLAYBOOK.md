---
name: r-quarto-dashboard
version: 1.0.0
context-mode: Fork
description: "Create a Quarto 1.4+ Dashboard with rows, columns, value boxes, plots, and interactive widgets (Shiny or Observable JS)"
trigger: both
trigger-patterns:
  - "quarto dashboard *"
  - "dashboard *"
  - "create dashboard *"
  - "build dashboard *"
argument-hint: "--name <slug> [--title <title>] [--theme cosmo|flatly|darkly] [--interactive shiny|ojs|none]"
parameters:
  name:
    type: String
    required: true
    hint: "File/project name slug (e.g. 'sales-dashboard', becomes sales-dashboard.qmd)"
  title:
    type: String
    required: false
    hint: "Dashboard title shown in the header"
  theme:
    type: String
    required: false
    default: "flatly"
    enum: ["cosmo", "flatly", "darkly", "cerulean", "lux", "pulse", "sandstone", "sketchy", "solar", "spacelab", "superhero", "yeti"]
    hint: "Bootstrap theme for the dashboard"
  interactive:
    type: String
    required: false
    default: "none"
    enum: ["shiny", "ojs", "none"]
    hint: "Interactivity engine: Shiny (server-side R), Observable JS (client-side), or none (static)"
  data:
    type: String
    required: false
    hint: "Path to data file or name of built-in dataset to use in examples"
steps:
  - id: scaffold-file
    inline-prompt: |
      Create the Quarto dashboard file `{{params.name}}.qmd`.

      Title: {{params.title}}
      Theme: {{params.theme}}
      Interactive: {{params.interactive}}

      YAML front matter:
      ```yaml
      ---
      title: "{{params.title}}"
      format:
        dashboard:
          theme: {{params.theme}}
          scrolling: false
          logo: ""
          nav-buttons:
            - icon: github
              href: ""
      ```

      Add the interactivity server declaration:
      - shiny:  `server: shiny`
      - ojs:    (no extra field — just use `{ojs}` chunks)
      - none:   (omit server field)

      Close the YAML block with `---`.

      After the YAML, add a skeleton with one tab and two rows:
      ```
      # Overview {.tabset}

      ## Row {height=30%}

      ### Value boxes {width=1/3}
      ### Value boxes {width=1/3}
      ### Value boxes {width=1/3}

      ## Row {height=70%}

      ### Chart A
      ### Chart B
      ```

      Report: file created at `{{params.name}}.qmd`.
    gate: Confirm
    output: qmd_path

  - id: add-data-setup
    requires: [scaffold-file]
    inline-prompt: |
      Add a setup chunk to load data and shared libraries.

      Data source: {{params.data}}

      ````r
      ```{{r}}
      #| label: setup
      #| include: false
      library(tidyverse)
      library(plotly)
      library(gt)
      library(bslib)

      # Load data
      data <- if (!is.null("{{params.data}}") && nchar("{{params.name}}") > 0) {
        readr::read_csv("{{params.data}}")  # or readRDS / built-in
      } else {
        ggplot2::diamonds  # placeholder dataset
      }
      ```
      ````

      Place this chunk right after the YAML front matter, before any layout.
      Report: setup chunk added.
    output: setup_chunk

  - id: add-value-boxes
    requires: [add-data-setup]
    inline-prompt: |
      Add three value boxes in the first row.

      Value boxes use `bslib::value_box()` inside a `{r}` chunk with `#| content: valuebox`.

      Example pattern for three KPIs derived from the data:
      ````
      ```{{r}}
      #| content: valuebox
      #| title: "Total Records"
      list(
        icon  = "table",
        color = "primary",
        value = nrow(data)
      )
      ```

      ```{{r}}
      #| content: valuebox
      #| title: "Mean Value"
      list(
        icon  = "bar-chart",
        color = "success",
        value = scales::comma(mean(data[[1]], na.rm = TRUE), accuracy = 0.1)
      )
      ```

      ```{{r}}
      #| content: valuebox
      #| title: "Missing (%)"
      list(
        icon  = "exclamation-triangle",
        color = "warning",
        value = paste0(round(mean(is.na(data)) * 100, 1), "%")
      )
      ```
      ````

      Adapt the KPI labels and columns to the actual dataset columns.
      Report: value boxes added.
    output: value_boxes

  - id: add-charts
    requires: [add-value-boxes]
    inline-prompt: |
      Add two interactive charts in the second row.

      Prefer `plotly` for interactivity. Use `ggplotly()` to convert ggplots.

      Chart A — distribution or time-series:
      ````
      ```{{r}}
      p1 <- ggplot(data, aes(x = <numeric_col>)) +
        geom_histogram(fill = "#0d6efd", bins = 30) +
        theme_minimal() +
        labs(title = "Distribution of <col>")
      ggplotly(p1)
      ```
      ````

      Chart B — comparison or scatter:
      ````
      ```{{r}}
      p2 <- ggplot(data, aes(x = <col1>, y = <col2>, color = <cat_col>)) +
        geom_point(alpha = 0.6) +
        theme_minimal() +
        labs(title = "<col1> vs <col2>")
      ggplotly(p2)
      ```
      ````

      Adapt column names to the actual dataset.
      For `interactive: ojs`, additionally add an Observable JS filter control:
      ````
      ```{{ojs}}
      viewof selected = Inputs.select(["A", "B", "C"], {label: "Filter"})
      ```
      ````

      Report: charts added.
    gate: Review
    output: charts

  - id: add-shiny-controls
    requires: [add-charts]
    inline-prompt: |
      If interactive is "shiny" (value: {{params.interactive}}):
      Add a Shiny sidebar with input controls and a reactive output.

      Add a sidebar section before the rows:
      ```
      ## {.sidebar}

      ```{{r}}
      selectInput("var", "Variable", choices = names(data))
      sliderInput("n", "Bins", min = 5, max = 100, value = 30)
      ```
      ```

      Wire up a reactive chart using `renderPlotly()`:
      ```{{r}}
      #| context: server
      output$reactive_chart <- renderPlotly({
        req(input$var)
        p <- ggplot(data, aes(x = .data[[input$var]])) +
          geom_histogram(bins = input$n, fill = "#0d6efd") +
          theme_minimal()
        ggplotly(p)
      })
      ```

      Add `plotlyOutput("reactive_chart")` in the layout panel.

      If not shiny: skip this step.
      Report: Shiny controls added (or skipped).
    output: shiny_controls

  - id: render-verify
    requires: [add-shiny-controls]
    inline-prompt: |
      Render the dashboard to verify it builds correctly.

      ```r
      quarto::quarto_render("{{params.name}}.qmd")
      ```

      Check for:
      - No YAML parse errors
      - No chunk errors
      - All value boxes display correct values
      - Charts render (plotly objects visible)
      - For shiny mode: `quarto serve` produces a live dashboard

      If there are errors, fix them before marking complete.
      Report: render status and any warnings.
    gate: Review
    output: render_status

tags:
  - r
  - quarto
  - dashboard
  - reporting
  - visualization

allowed-tools:
  - "*"

constraints:
  - rule: "ALWAYS use Quarto 1.4+ format: 'dashboard' not 'html' for dashboard output."
    severity: "error"
  - rule: "NEVER mix Shiny server chunks with OJS chunks in the same dashboard."
    severity: "error"
  - rule: "ALWAYS set #| label: setup on the setup chunk to prevent duplication errors."
    severity: "warning"
  - rule: "Use plotly or htmlwidgets for interactive charts — static ggplots will not respond to Shiny inputs."
    severity: "warning"
---

You are a Quarto Dashboard specialist. You create responsive, interactive dashboards
using the Quarto 1.4+ `format: dashboard` output type with bslib Bootstrap themes.

## Rules

1. Dashboard layout uses markdown headings: `#` = page/tab, `##` = row, `###` = card.
2. Use `{height=N%}` and `{width=N/N}` on row/column headers to control layout.
3. Value boxes require `#| content: valuebox` and a `list(icon, color, value)` return.
4. For static dashboards, `plotly` gives interactivity without a server.
5. For reactive dashboards, add `server: shiny` to YAML and use `renderPlotly()`.
6. Use `#| context: server` for Shiny server-side chunks.
7. Dashboard pages are defined by top-level `#` headings.
8. Always render with `quarto::quarto_render()` to catch errors early.
