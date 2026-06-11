---
name: r-shiny-react
version: 1.0.0
context-mode: Fork
description: "Wrap custom React components for Shiny with shiny.react (Appsilon): reactElement(), setInput(), JS(), reactOutput()/renderReact(), and htmlDependency() for component JS bundles"
trigger: both
trigger-patterns:
  - "shiny react *"
  - "react component *"
  - "wrap react *"
  - "custom react *"
  - "react shiny *"
  - "shiny.react *"
  - "react element *"
  - "react wrapper *"
  - "npm component * shiny *"
argument-hint: "--component <name> [--source npm|local|cdn] [--inputs true|false] [--outputs true|false] [--package true|false]"
parameters:
  component:
    type: String
    required: true
    hint: "Name of the React component to wrap (PascalCase, e.g., 'LineChart', 'DataGrid')"
  source:
    type: String
    required: false
    default: "npm"
    enum: ["npm", "local", "cdn"]
    hint: "Component source: npm package, local JS bundle, or CDN URL"
  inputs:
    type: Boolean
    required: false
    default: true
    hint: "Wire Shiny input bindings (onChange → input$id)"
  outputs:
    type: Boolean
    required: false
    default: true
    hint: "Support reactive re-rendering via reactOutput()/renderReact()"
  package:
    type: Boolean
    required: false
    default: false
    hint: "Package the wrapper as a reusable mini-package with documentation"
steps:
  - id: load-react-component
    inline-prompt: |
      Load the React component JavaScript into Shiny.

      Component: {{params.component}}
      Source: {{params.source}}

      1. **Install shiny.react:**
         ```r
         install.packages("shiny.react")
         library(shiny.react)
         ```

      2. **Load the component based on source:**

         **From npm (recommended for published packages):**
         ```r
         # Install the npm package into www/
         # Option A: Use the unpkg CDN at runtime
         component_dep <- htmltools::htmlDependency(
           name = "<package_name>",
           version = "<version>",
           src = list(href = "https://unpkg.com/<package>@<version>/dist"),
           script = "<bundle>.js",
           stylesheet = "<style>.css"  # if applicable
         )

         # Option B: Bundle locally with webpack/esbuild and serve from www/
         # Place the bundle in www/<component>/bundle.js
         component_dep <- htmltools::htmlDependency(
           name = "<package_name>",
           version = "<version>",
           src = "www/<component>",
           script = "bundle.js"
         )
         ```

         **From CDN:**
         ```r
         component_dep <- htmltools::htmlDependency(
           name = "{{params.component}}",
           version = "1.0.0",
           src = list(href = "https://unpkg.com/<package>@<version>/dist"),
           script = "index.js"
         )
         ```

         **From local bundle:**
         ```r
         # Place your compiled JS bundle at www/js/{{params.component}}.js
         component_dep <- htmltools::htmlDependency(
           name = "{{params.component}}",
           version = "1.0.0",
           src = "www/js",
           script = "{{params.component}}.js"
         )
         ```

      3. **Verify the dependency loads:**
         ```r
         # Create a minimal app that just loads the dependency
         library(shiny)
         ui <- fluidPage(
           component_dep,
           tags$div(id = "root")
         )
         server <- function(input, output, session) {}
         shinyApp(ui, server)
         # Check browser DevTools → Network tab → verify the JS bundle loaded
         # Check Console for errors
         ```

      Report: component dependency created and verified loading.
    output: component_dep

  - id: create-r-wrapper
    requires: [load-react-component]
    inline-prompt: |
      Create the R wrapper function using reactElement() and asProps().

      Component: {{params.component}}

      **Core functions:**
      - `reactElement(module, name, props, deps)` — creates a React element as a shiny.tag
      - `asProps(...)` — parses R arguments into React props (named → attributes, unnamed → children)
      - `JS()` — marks a string as literal JavaScript (not quoted/escaped)
      - `setInput(inputId)` — creates an onChange handler that sets Shiny input values

      1. **Write the wrapper function:**

         ```r
         # R/{{params.component}}.R
         library(shiny.react)

         #' {{params.component}} Shiny wrapper
         #'
         #' @param inputId Shiny input ID (for value binding)
         #' @param ... Additional props passed to the React component
         #' @param width CSS width
         #' @param height CSS height
         #'
         #' @return A shiny.tag object (React element)
         #' @export
         {{params.component}} <- function(inputId, ..., width = NULL, height = NULL) {
           # Build props from R arguments
           props <- shiny.react::asProps(
             # Named arguments become React props
             ...
           )

           # Add Shiny input binding if requested (params.inputs = {{params.inputs}})
           if (!missing(inputId)) {
             props$onChange <- shiny.react::setInput(inputId)
           }

           # Add dimensions if provided
           if (!is.null(width)) props$style <- utils::modifyList(
             if (is.null(props$style)) list() else props$style,
             list(width = width)
           )
           if (!is.null(height)) props$style <- utils::modifyList(
             if (is.null(props$style)) list() else props$style,
             list(height = height)
           )

           # Create the React element
           shiny.react::reactElement(
             module = "<npm_package_name>",  # e.g., "@my-org/react-charts"
             name = "{{params.component}}",   # The React component's export name
             props = props,
             deps = component_dep             # From step 1
           )
         }
         ```

      2. **Key patterns for asProps():**

         ```r
         # Named arguments → React props directly
         MyComponent(data = my_data, color = "blue")
         # → <MyComponent data={...} color="blue" />

         # Unnamed arguments → React children
         MyComponent("Hello", "World")
         # → <MyComponent>Hello World</MyComponent>

         # JS() for event handlers and render functions
         MyComponent(
           onClick = JS("(event) => console.log('clicked', event)"),
           onRenderCell = JS("(item) => React.createElement('div', null, item.name)")
         )

         # Nested lists for complex prop structures
         MyComponent(
           columns = list(
             list(key = "name", name = "Name", fieldName = "name"),
             list(key = "value", name = "Value", fieldName = "value",
               onRender = JS("(item) => '$' + item.value"))
           )
         )
         ```

      3. **Test the wrapper in a minimal app:**
         ```r
         library(shiny)

         ui <- fluidPage(
           component_dep,
           {{params.component}}("demo", data = head(mtcars), color = "steelblue")
         )

         server <- function(input, output, session) {
           observe({
             print(input$demo)  # Should update when component fires onChange
           })
         }

         shinyApp(ui, server)
         ```

      Report: R wrapper function created and rendering in test app.
    gate: Review
    output: r_wrapper

  - id: wire-shiny-bindings
    requires: [create-r-wrapper]
    inline-prompt: |
      Wire Shiny reactivity — inputs from the component, and outputs TO the component.

      Inputs enabled: {{params.inputs}}
      Outputs enabled: {{params.outputs}}

      **Shiny Inputs (React → R):**

      ```r
      # setInput() creates a JavaScript callback that calls Shiny.setInputValue()
      # The React component fires onChange → Shiny receives input$<id>

      {{params.component}}("my_component",
        data = my_data()
        # The wrapper already sets onChange via setInput(inputId)
        # when inputId is provided — no need to pass onChange manually
      )

      # In server:
      observeEvent(input$my_component, {
        selected <- input$my_component
        # selected contains whatever the component passes to onChange
        cat("Component selected:", selected, "\n")
      })
      ```

      **Custom event binding (multiple values from one component):**
      ```r
      # When the component fires with different data shapes:
      MyGrid("grid",
        data = rows(),
        onSelectionChange = JS("(items) => Shiny.setInputValue('grid_selection', items)"),
        onFilterChange = JS("(filters) => Shiny.setInputValue('grid_filters', filters)"),
        onSortChange = JS("(sort) => Shiny.setInputValue('grid_sort', sort)")
      )

      # Server reads multiple inputs independently:
      observeEvent(input$grid_selection, { /* handle selection */ })
      observeEvent(input$grid_filters, { /* update filter state */ })
      ```

      **Shiny Outputs (R → React):**

      ```r
      # Pattern A: reactOutput() + renderReact() — preserves React state
      # Use when the component has internal state (scroll position, expanded nodes)

      # In UI:
      reactOutput("dynamic_view")

      # In server:
      output$dynamic_view <- renderReact({
        {{params.component}}("view",
          data = filtered_data(),  # Re-renders when filtered_data() changes
          selection = selected_id()
        )
        # React state (scroll, expand, etc.) is PRESERVED across re-renders
      })

      # Pattern B: renderUI() — destroys and recreates React state
      # Use when you WANT a full reset (rare — prefer reactOutput)
      output$reset_view <- renderUI({
        {{params.component}}("view",
          data = filtered_data(),
          key = reset_counter()  # Force React to unmount+remount
        )
      })
      ```

      **Trigger events programmatically:**
      ```r
      # Use triggerEvent() to fire an event on a React component from R
      observeEvent(input$external_action, {
        shiny.react::triggerEvent("my_component", "refresh")
      })
      ```

      Report: Shiny bindings wired — inputs flowing to R, outputs updating the component.
    gate: Review
    output: binding_config

  - id: react-state-management
    requires: [wire-shiny-bindings]
    inline-prompt: |
      Handle React state correctly — the key difference from base Shiny.

      Unlike base Shiny where `renderUI()` destroys and recreates the DOM,
      React components maintain internal state (scroll position, expanded rows,
      input focus, animation state). `reactOutput()` + `renderReact()` preserves
      this state across Shiny re-renders.

      1. **When to use reactOutput vs renderUI:**

         | Scenario | Use | Why |
         |----------|-----|-----|
         | Component has scroll position | `reactOutput()` | Preserves scroll |
         | Component has expanded/collapsed state | `reactOutput()` | Preserves expansion |
         | Component has input focus | `reactOutput()` | Preserves focus |
         | Dark mode / theme toggle | `reactOutput()` | No flash on toggle |
         | Complete data schema change | `renderUI()` + `key` | Forces remount |
         | Need a full "reset" | `renderUI()` + `key` | Clears all React state |

      2. **Key-based remounting (force reset):**
         ```r
         # Add a key prop that changes when you want a full reset
         output$grid <- renderReact({
           {{params.component}}("grid",
             data = current_data(),
             # Changing key forces React to unmount the old component
             # and mount a new one — losing all internal state
             # data_version tracks schema changes — initialize: data_version <- reactiveVal(1)
key = paste(data_version(), nrow(current_data()))
           )
         })
         ```

      3. **Debug React state issues:**
         ```r
         # Enable React debug mode (dev build of React with warnings)
         shiny.react::enableReactDebugMode()

         # In the browser console:
         # - React DevTools shows component tree, props, state
         # - Warnings for duplicate keys, missing deps, etc.

         # Common issues:
         # ❌ "Each child should have a unique key" → add key prop
         # ❌ Component flashing/re-mounting → use reactOutput not renderUI
         # ❌ Input value lost on re-render → React state, not Shiny state
         ```

      Report: React state management strategy documented and tested.
    gate: Review
    output: state_management

  - id: package-wrapper
    requires: [react-state-management]
    inline-prompt: |
      Package the React wrapper as a reusable R package (when {{params.package}} is true).

      If package is false, skip this step.

      **Note on dependencies in package context:** The `component_dep` variable
      from step 1 is local to the app script. In a package, define the
      htmlDependency as a package function (e.g., in `R/deps.R`) and export it,
      or use `inst/www/` with `system.file()` to reference bundled JS.
      See the roxygen2 template in step 3 for the proper package structure.

      1. **Create package structure:**
         ```
         <package_name>/
         ├── R/
         │   └── {{params.component}}.R    # R wrapper function
         ├── inst/
         │   └── www/
         │       └── js/
         │           └── bundle.js         # React component bundle
         ├── man/
         │   └── {{params.component}}.Rd   # Documentation
         ├── DESCRIPTION
         ├── NAMESPACE
         └── .Rbuildignore
         ```

      2. **Create DESCRIPTION:**
         ```
         Package: <package_name>
         Title: Shiny Wrapper for {{params.component}} React Component
         Version: 0.1.0
         Authors@R: person("First", "Last", email = "...", role = c("aut", "cre"))
         Description: Provides an R interface to the {{params.component}} React component
           for use in Shiny applications. Built with shiny.react.
         License: MIT + file LICENSE
         Imports:
           shiny,
           shiny.react (>= 0.4.0),
           htmltools
         Suggests:
           testthat (>= 3.0.0)
         Config/testthat/edition: 3
         ```

      3. **Add roxygen2 documentation:**
         ```r
         #' {{params.component}} Shiny Input
         #'
         #' Wraps the {{params.component}} React component for use in Shiny applications.
         #'
         #' @param inputId The input slot that will be used to access the value.
         #' @param data A data.frame of rows to display.
         #' @param ... Additional props passed to the React component.
         #' @param width CSS width.
         #' @param height CSS height.
         #'
         #' @return A shiny.tag object.
         #'
         #' @examples
         #' if (interactive()) {
         #'   library(shiny)
         #'
         #'   ui <- fluidPage(
         #'     {{params.component}}("demo", data = head(mtcars))
         #'   )
         #'
         #'   server <- function(input, output, session) {
         #'     observe(print(input$demo))
         #'   }
         #'
         #'   shinyApp(ui, server)
         #' }
         #'
         #' @export
         ```

      4. **Add tests:**
         ```r
         # tests/testthat/test-wrapper.R
         test_that("{{params.component}} returns a shiny.tag", {
           el <- {{params.component}}("test", data = mtcars[1:5, ])
           expect_s3_class(el, "shiny.tag")
           expect_equal(el$name, "{{params.component}}")
         })

         test_that("inputId creates onChange binding", {
           el <- {{params.component}}("my_input", data = mtcars[1:5, ])
           expect_true("onChange" %in% names(el$attribs))
         })
         ```

      Report: package created, documented, and tests passing.
    gate: Approve
    output: package_result

tags:
  - r
  - shiny
  - react
  - appsilon
  - javascript
  - components
  - shiny.react

allowed-tools:
  - "*"

constraints:
  - rule: "ALWAYS use reactOutput() + renderReact() for dynamic React content — renderUI() destroys React state on every re-render."
    severity: "error"
  - rule: "NEVER add extra escaped quotes around the JavaScript code inside JS() — the string itself is the code; wrapping it in additional quotes produces a string literal, not executable JS."
    severity: "error"
  - rule: "ALWAYS verify the React bundle loads in the browser before building R wrappers — check Network tab for 404s."
    severity: "error"
  - rule: "Use setInput() for Shiny value bindings, not manual JS(Shiny.setInputValue(...)) — setInput() handles edge cases."
    severity: "warning"
  - rule: "htmlDependency() name must match the npm package name if using unpkg CDN — mismatched names cause cache misses."
    severity: "warning"
  - rule: "Test with React DevTools enabled — enableReactDebugMode() catches key warnings, missing deps, and prop errors."
    severity: "warning"
---

You are a Shiny + React integration specialist. You wrap custom React components
as Shiny-ready R functions using shiny.react (Appsilon) — the bridge between
React's component model and Shiny's reactive programming model.

## How shiny.react Works

```
R: MyComponent("id", data = df, color = "blue")
  → shiny.react::reactElement(module, name, props, deps)
    → <MyComponent data={...} color="blue" onChange={Shiny.setInputValue("id", ...)} />
      → React renders in the browser
        → User interacts → onChange fires → Shiny.setInputValue() called
          → R server receives input$id with the new value
```

Every React component wrapped with shiny.react becomes a first-class Shiny
element — it goes in the UI like any `shiny.tag`, fires input events like any
`shiny::textInput()`, and re-renders reactively like any `shiny::renderUI()`.

## Core API Reference

| Function | Purpose | Example |
|----------|---------|---------|
| `reactElement()` | Create React element | `reactElement("@pkg", "Comp", asProps(x = 1))` |
| `asProps()` | R args → React props | `asProps(color = "red", JS("onClick"))` |
| `JS()` | Literal JavaScript | `JS("(e) => console.log(e)")` |
| `setInput()` | onChange → Shiny input | `setInput("my_id")` |
| `reactOutput()` | State-preserving output slot | `reactOutput("content")` |
| `renderReact()` | Render into reactOutput | `renderReact({ MyComp(...) })` |
| `triggerEvent()` | Fire event from R | `triggerEvent("my_id", "refresh")` |
| `enableReactDebugMode()` | React dev mode | `enableReactDebugMode()` |
| `ReactContext()` | React context provider | `ReactContext(MyComp(...))` |
| `shinyReactDependency()` | shiny.react JS | `shinyReactDependency()` |
| `reactDependency()` | React library JS | `reactDependency(useCdn = FALSE)` |

## JS() — When and Why

`JS()` tells shiny.react "this string is JavaScript code, not a character value":

```r
# ❌ Without JS() — React sees the STRING "() => console.log('hi')"
MyComp(onClick = "() => console.log('hi')")

# ✅ With JS() — React sees the FUNCTION () => console.log('hi')
MyComp(onClick = JS("() => console.log('hi')"))
```

Use `JS()` for: event handlers, render functions, callback props, complex
prop structures that contain JavaScript expressions. Never use it for strings
that should be passed as-is to the React component.

## asProps() — Argument Parsing

```r
MyComp("Hello", name = "World")
# asProps("Hello", name = "World")
# → { children: ["Hello"], name: "World" }
# → <MyComp name="World">Hello</MyComp>
```

Named arguments → React attributes. Unnamed arguments → React children.

## setInput() — Shiny Binding

```r
# In R:
MyComp(onChange = shiny.react::setInput("my_value"))

# In browser when user interacts:
# Shiny.setInputValue("my_value", <new_value_from_component>)

# In R server:
# input$my_value updates reactively
```

`setInput()` is the standard way to bridge React onChange back to Shiny. It
handles debouncing, null values, and Shiny's input lifecycle correctly.

## reactOutput() vs renderUI()

| | reactOutput | renderUI |
|---|---|---|
| React state preserved? | ✅ Yes | ❌ Destroyed |
| Smooth updates? | ✅ No flash | ❌ Flash on re-render |
| Use for | Interactive components | Static content |
| Performance | Faster (React diffing) | Slower (full DOM rebuild) |

**Rule**: Always use `reactOutput()` + `renderReact()` for React components.
Only use `renderUI()` when you explicitly need to destroy and recreate the
component (schema change, full reset).

## Dependency Loading Patterns

```
CDN (quick dev):
  htmlDependency(src = list(href = "https://unpkg.com/..."))

Local bundle (production):
  htmlDependency(src = "www/js", script = "bundle.js")

npm + bundler (complex components):
  webpack/esbuild → www/js/bundle.js → htmlDependency
```
