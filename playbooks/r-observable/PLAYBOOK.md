---
name: r-observable
version: 1.0.0
context-mode: Fork
description: "Create interactive R-powered documents and dashboards with Observable JS and WebR: client-side R execution via WebR in Quarto, Observable Plot for interactive visualization, and Observable Framework for data apps"
trigger: both
trigger-patterns:
  - "observable *"
  - "webR *"
  - "interactive document *"
  - "observable plot *"
  - "observable js *"
  - "quarto observable *"
  - "client side r *"
  - "web r *"
  - "observable framework *"
argument-hint: "[--type quarto-ojs|webr|framework] [--engine webR|observable|both]"
parameters:
  type:
    type: String
    required: false
    default: "quarto-ojs"
    enum: ["quarto-ojs", "webr", "framework"]
    hint: "Type: Quarto + Observable JS integration, WebR (client-side R), or Observable Framework project"
  engine:
    type: String
    required: false
    default: "both"
    enum: ["webR", "observable", "both"]
    hint: "Engine: WebR (run R in browser), Observable JS, or both combined"
steps:
  - id: quarto-observable-integration
    inline-prompt: |
      Add Observable JS to Quarto documents.

      Type: {{params.type}}

      Quarto has first-class support for Observable JS via `{ojs}` code blocks
      and the `@observablehq/plot` library.

      1. **Basic Observable JS in Quarto:**
         ```markdown
         ---
         title: "Interactive Dashboard"
         format: html
         ---

         ```{r}
         # R code to prepare data
         library(tidyverse)
         data <- mpg |>
           group_by(manufacturer) |>
           summarise(avg_hwy = mean(hwy), .groups = "drop")
         ```

         ```{ojs}
         // Observable JS — reactive, runs in the browser
         // Access R variables with `transpose()`
         input_data = transpose(data)
         ```

         ```{ojs}
         // Observable Plot visualization
         Plot.plot({
           marks: [
             Plot.barX(input_data, {
               x: "avg_hwy",
               y: "manufacturer",
               sort: { y: "x", reverse: true },
               fill: "steelblue"
             })
           ],
           marginLeft: 100,
           x: { label: "Average Highway MPG" }
         })
         ```
         ```

      2. **Reactive Observable JS with R data:**
         ```markdown
         ```{ojs}
         // This updates automatically when R re-renders
         viewof selected_manufacturer = Inputs.select(
           input_data.map(d => d.manufacturer),
           { label: "Manufacturer", value: input_data[0].manufacturer }
         )
         ```

         ```{ojs}
         // Filtered data based on user selection
         filtered = input_data.filter(
           d => d.manufacturer === selected_manufacturer
         )
         ```
         ```

      3. **Observable Plot chart types:**
         ```javascript
         // Scatter plot
         Plot.dot(data, { x: "hp", y: "mpg", fill: "cyl" })

         // Line chart
         Plot.line(data, { x: "date", y: "value", stroke: "series" })

         // Area chart
         Plot.areaY(data, { x: "date", y: "value" })

         // Heatmap
         Plot.cell(data, { x: "day", y: "hour", fill: "count" })

         // Interactive: crosshair, tooltips, zoom
         Plot.plot({
           marks: [
             Plot.dot(data, { x: "x", y: "y", title: "name" }),
             Plot.crosshair(data, { x: "x", y: "y" })
           ]
         })
         ```

      4. **Use Observable's Inputs for interactivity:**
         ```javascript
         // Dropdown
         viewof x = Inputs.select(["a", "b", "c"], { label: "Choice" })

         // Slider
         viewof n = Inputs.range([0, 100], { step: 1, label: "N" })

         // Checkbox
         viewof show = Inputs.toggle({ label: "Show details" })

         // Text input
         viewof search = Inputs.text({ label: "Search", placeholder: "Type..." })

         // Table
         Inputs.table(filtered_data)
         ```

      Report: Observable JS integration working in Quarto.
    gate: Review
    output: quarto_ojs_result

  - id: webr-setup
    requires: [quarto-observable-integration]
    inline-prompt: |
      Set up WebR for client-side R execution in the browser.

      Engine: {{params.engine}}

      WebR runs a compiled version of R in the browser (WebAssembly), enabling
      R code to execute client-side without a server. This is revolutionary for
      interactive R documents and educational content.

      1. **Add WebR to a Quarto document:**
         ```markdown
         ---
         title: "WebR Interactive Document"
         format: html
         engine: knitr
         webr: true
         ---

         This is server-rendered R.

         ```{r}
         library(ggplot2)
         ggplot(mpg, aes(displ, hwy)) + geom_point()
         ```

         This is client-side R (WebR):

         ```{webr-r}
         # Runs in the user's browser — no R server needed!
         library(ggplot2)

         # WebR has access to many CRAN packages
         ggplot(mpg, aes(displ, hwy, color = class)) +
           geom_point() +
           labs(title = "Interactive — hover to see class")
         ```
         ```

      2. **Interactive WebR with Observable JS:**
         ```markdown
         ```{webr-r}
         # Define a reactive R computation
         result <- lm(mpg ~ hp + wt, data = mtcars)
         summary(result)
         ```

         ```{ojs}
         // Access WebR results in Observable
         // The R output is available as a JavaScript object
         ```
         ```

      3. **WebR + Observable Plot (R data → browser viz):**
         ```markdown
         ```{webr-r}
         # Prepare data in R (client-side!)
         library(dplyr)
         plot_data <- mtcars |>
           mutate(car = rownames(mtcars)) |>
           select(car, mpg, hp, wt, cyl)
         ```

         ```{ojs}
         // Visualize with Observable Plot (client-side!)
         data = transpose(plot_data)
         Plot.plot({
           marks: [
             Plot.dot(data, {
               x: "hp", y: "mpg",
               fill: "cyl",
               r: "wt",
               title: "car"
             })
           ],
           grid: true
         })
         ```
         ```

      4. **WebR package support:**
         WebR can install packages from its binary repository:
         ```r
         # In a {webr-r} block:
         install.packages("ggplot2")
         install.packages("dplyr")
         install.packages("tidymodels")  # many packages work!
         ```
         Not all CRAN packages are available — those with compiled C/C++/Fortran
         code need to be compiled for WebAssembly. Check availability at
         https://repo.r-wasm.org.

      Report: WebR running in browser, interactive R code executing client-side.
    gate: Review
    output: webr_result

  - id: observable-framework
    requires: [quarto-observable-integration]
    inline-prompt: |
      Create an Observable Framework project (when type is 'framework').

      Type: {{params.type}}

      Observable Framework is a static site generator for data apps, dashboards,
      and reports built on Observable JS and Markdown. It's distinct from Quarto —
      pure Observable/JavaScript with data loaders in any language (R, Python, SQL).

      1. **Initialize an Observable Framework project:**
         ```bash
         npm init @observablehq
         # Follow prompts to create project structure:
         # observable-project/
         # ├── src/
         # │   ├── index.md
         # │   ├── data/
         # │   │   └── sales.csv
         # │   └── components/
         # │       └── chart.js
         # ├── observablehq.config.js
         # └── package.json
         ```

      2. **Use an R data loader:**
         Framework supports data loaders in any language. Create an R data loader:
         ```r
         # src/data/sales.json.R
         # This runs during build, not in the browser
         library(tidyverse)

         sales <- read_csv("src/data/sales.csv") |>
           group_by(date) |>
           summarise(
             revenue = sum(amount),
             orders = n(),
             .groups = "drop"
           )

         # Output JSON to stdout
         jsonlite::stream_out(sales)
         ```
         Mark it executable: `chmod +x src/data/sales.json.R`

      3. **Use the data in Observable JS:**
         ```javascript
         // src/index.md
         ```js
         const sales = FileAttachment("data/sales.json").json()
         ```

         ```js
         Plot.plot({
           y: { grid: true },
           marks: [
             Plot.line(sales, { x: "date", y: "revenue" }),
             Plot.ruleY([0])
           ]
         })
         ```
         ```

      4. **Build and deploy:**
         ```bash
         npm run build       # Build static site to dist/
         npm run deploy      # Deploy to Observable Cloud
         # Or deploy dist/ to any static host (Netlify, GitHub Pages, S3)
         ```

      Report: Observable Framework project created and building.
    gate: Review
    output: framework_result

  - id: combine-r-observable
    requires: [webr-setup, observable-framework]
    inline-prompt: |
      Combine R and Observable JS for a complete interactive document.

      1. **Architecture decision matrix:**

         | Scenario | Recommended Approach |
         |----------|---------------------|
         | R-heavy, interactive charts needed | Quarto + Observable JS (`{ojs}`) |
         | Serverless interactive R | Quarto + WebR (`{webr-r}`) |
         | Pure data app with R backend | Observable Framework + R data loaders |
         | R training/education | Quarto + WebR (no server needed!) |
         | Production dashboard with R | Quarto + Observable JS + Connect |
         | Static report with interactive charts | Quarto + Observable JS (no server!) |

      2. **Full example: R → Observable → WebR hybrid:**
         ```markdown
         ---
         title: "R + Observable + WebR Dashboard"
         format: html
         ---

         ## Data Overview (server-rendered R)
         ```{r}
         summary(mpg)
         ```

         ## Interactive Chart (Observable JS)
         ```{ojs}
         Plot.plot({
           marks: [Plot.dot(transpose(mpg), { x: "displ", y: "hwy" })]
         })
         ```

         ## Interactive Analysis (WebR — client-side R)
         ```{webr-r}
         install.packages("ggplot2")
         library(ggplot2)
         ggplot(mpg, aes(class, hwy)) + geom_boxplot()
         ```
         ```

      Report: hybrid document working with R, Observable JS, and WebR.
    gate: Review
    output: hybrid_result

tags:
  - r
  - observable
  - webr
  - quarto
  - interactive
  - visualization

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER use WebR for sensitive computation — client-side R runs in the user's browser and code is visible."
    severity: "error"
  - rule: "NEVER load large datasets with WebR — WebAssembly has memory limits (~4GB max, slower than native R)."
    severity: "warning"
  - rule: "ALWAYS provide fallback for non-JavaScript browsers — Observable JS requires JS enabled."
    severity: "warning"
  - rule: "Use Observable Plot for interactive charts, not ggplot2 + plotly in the browser — Plot is native to Observable JS."
    severity: "warning"
---

You are an R + Observable integration specialist. You create interactive,
serverless R-powered documents and dashboards using Quarto's Observable JS
integration, WebR (R in the browser via WebAssembly), and Observable Framework
for data apps — following Posit's modern visualization and publishing best practices.

## Observable + R Philosophy

1. **RIGHT TOOL FOR THE JOB**: Use server-rendered R for heavy computation and
   data preparation. Use Observable JS for interactive browser-side charts.
   Use WebR for lightweight interactive R in the browser.
2. **SERVERLESS IS THE FUTURE**: WebR enables R to run client-side with zero
   server infrastructure. This transforms educational content, documentation,
   and interactive articles.
3. **OBSERVABLE PLOT OVER D3**: Observable Plot provides a high-level grammar
   for visualization that's more intuitive than raw D3 and more interactive
   than ggplot2. Use it for browser-native charts.
4. **HYBRID ARCHITECTURES**: The best solutions combine server-rendered R
   (for heavy computation) with client-side Observable JS (for interactivity)
   and WebR (for lightweight R interaction).

## R + Observable Ecosystem

| Technology | Runs Where | Best For | R Integration |
|-----------|-----------|----------|---------------|
| Quarto + `{ojs}` | Browser | Interactive charts in R docs | `transpose()` to pass R data to JS |
| Quarto + WebR | Browser | Client-side R execution | Full R environment in the browser |
| Observable Framework | Browser + Build | Data apps with R backend | R data loaders (JSON via stdout) |
| Observable Plot | Browser | Interactive charts | Works with any data source |
| Shiny | Server | Full R interactivity | Server-side R with reactive UI |
