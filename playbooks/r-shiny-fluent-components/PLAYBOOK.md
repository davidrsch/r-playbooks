---
name: r-shiny-fluent-components
version: 1.0.0
context-mode: Fork
description: "Build Fluent UI Shiny UIs (Appsilon): inputs with .shinyInput(), DetailsList, Pivot/CommandBar/Nav, Stack layout, MessageBar/Spinner feedback, and Modal/Panel overlays"
trigger: both
trigger-patterns:
  - "fluent component *"
  - "fluent input *"
  - "detailslist *"
  - "fluent pivot *"
  - "fluent commandbar *"
  - "shiny fluent * component *"
  - "fluent ui component *"
  - "add fluent *"
argument-hint: "[--components inputs|data|navigation|layout|feedback|all] [--data-source <path>]"
parameters:
  components:
    type: String
    required: false
    default: "all"
    enum: ["inputs", "data", "navigation", "layout", "feedback", "all"]
    hint: "Component category: inputs (form controls), data (DetailsList), navigation (Pivot/CommandBar), layout (Stack/Panel/Modal), feedback (MessageBar/Spinner), or all"
  data-source:
    type: String
    required: false
    hint: "Path to data file for DetailsList/DocumentCard examples (CSV, Parquet, or RDS)"
steps:
  - id: inputs
    inline-prompt: |
      Build form inputs with Fluent UI controls.

      Components: {{params.components}}

      Fluent inputs use `.shinyInput()` suffix to bridge React onChange → Shiny
      input values. In the server, access them as `input$<id>` (no `.shinyInput`).

      **Text inputs:**
      ```r
      # Single-line text
      TextField.shinyInput("username", label = "Username", placeholder = "Enter name")

      # Multi-line
      TextField.shinyInput("notes", label = "Notes", multiline = TRUE, rows = 4)

      # Masked (password)
      TextField.shinyInput("password", label = "Password", type = "password",
        canRevealPassword = TRUE)

      # With validation
      TextField.shinyInput("email", label = "Email",
        errorMessage = if (!is_valid) "Invalid email format",
        underlined = TRUE)
      ```

      **Selection inputs:**
      ```r
      # Dropdown (single select)
      Dropdown.shinyInput("region", value = "west",
        options = list(
          list(key = "west", text = "West Region"),
          list(key = "east", text = "East Region"),
          list(key = "central", text = "Central Region")
        ),
        label = "Region")

      # Multi-select Dropdown
      Dropdown.shinyInput("products", value = c("a", "b"),
        options = list(
          list(key = "a", text = "Product A"),
          list(key = "b", text = "Product B"),
          list(key = "c", text = "Product C")
        ),
        multiSelect = TRUE,
        label = "Products")

      # ComboBox (editable dropdown with search)
      ComboBox.shinyInput("city",
        options = list(
          list(key = "nyc", text = "New York"),
          list(key = "lax", text = "Los Angeles"),
          list(key = "chi", text = "Chicago")
        ),
        label = "City", allowFreeform = TRUE)
      ```

      **Toggle, checkbox, radio:**
      ```r
      # Toggle switch
      Toggle.shinyInput("notifications", value = TRUE,
        label = "Enable notifications", onText = "On", offText = "Off")

      # Checkbox
      Checkbox.shinyInput("agree", value = FALSE, label = "I agree to the terms")

      # ChoiceGroup (radio buttons)
      ChoiceGroup.shinyInput("plan", value = "pro",
        options = list(
          list(key = "basic", text = "Basic"),
          list(key = "pro", text = "Pro"),
          list(key = "enterprise", text = "Enterprise")
        ),
        label = "Subscription Plan")
      ```

      **Date and time:**
      ```r
      # Date picker
      DatePicker.shinyInput("start_date", value = Sys.Date(),
        label = "Start Date", minDate = Sys.Date())

      # Calendar (larger, shows month view)
      Calendar.shinyInput("event_date", value = Sys.Date())
      ```

      **Numbers and sliders:**
      ```r
      # Slider
      Slider.shinyInput("budget", value = 50, min = 0, max = 100, step = 5,
        label = "Budget (%)", showValue = TRUE)

      # SpinButton (precise numeric entry)
      SpinButton.shinyInput("quantity", value = 1, min = 1, max = 100, step = 1,
        label = "Quantity")

      # Rating
      Rating.shinyInput("satisfaction", value = 3, max = 5,
        label = "Satisfaction")
      ```

      **Search and filter:**
      ```r
      # Search box
      SearchBox.shinyInput("search", placeholder = "Search customers...",
        underlined = TRUE)
      ```

      **Server-side updates:**
      ```r
      # Update Fluent inputs programmatically
      observeEvent(input$reset_form, {
        updateTextField(session, "username", value = "")
        updateDropdown(session, "region", value = list(key = "west"))
        updateToggle(session, "notifications", value = FALSE)
        updateSlider(session, "budget", value = 30)
      })
      ```

      Report: Fluent inputs added to the UI, wired to server reactives.
    gate: Review
    output: input_config

  - id: data-display
    requires: [inputs]
    inline-prompt: |
      Display data with DetailsList, the primary Fluent UI data table.

      Components: {{params.components}}
      Data source: {{params.data-source}}

      If components is not 'data' or 'all', skip this step.

      **DetailsList — the Fluent data table:**
      ```r
      # R/ui.R
      library(shiny.fluent)

      # In UI:
      reactOutput("sales_table")

      # R/server.R
      library(dplyr)

      output$sales_table <- renderReact({
        # Load data (use actual path or fallback)
        data_path <- if (nchar("{{params.data-source}}") > 0) "{{params.data-source}}" else "data/sales.rds"
        data <- readRDS(data_path)

        # Convert to list of rows (DetailsList expects data as a list)
        items <- apply(data, 1, as.list, simplify = FALSE)

        DetailsList(
          items = items,
          columns = list(
            list(key = "customer", name = "Customer", fieldName = "customer",
              minWidth = 150, maxWidth = 300, isResizable = TRUE),
            list(key = "amount", name = "Amount", fieldName = "amount",
              minWidth = 100, maxWidth = 150, isResizable = TRUE,
              onRender = JS("(item) => '$' + item.amount.toLocaleString()")),
            list(key = "date", name = "Date", fieldName = "date",
              minWidth = 100, maxWidth = 150, isResizable = TRUE,
              onRender = JS("(item) => new Date(item.date).toLocaleDateString()")),
            list(key = "status", name = "Status", fieldName = "status",
              minWidth = 100, maxWidth = 150)
          ),
          # Selection
          selectionMode = 1,  # 0=none, 1=single, 2=multiple
          onActiveItemChanged = JS("(item) => Shiny.setInputValue('selected_row', item)"),
          # Sorting
          isHeaderVisible = TRUE,
          # Styling
          compact = FALSE,
          layoutMode = 1  # 0=fixed columns, 1=justified columns
        )
      })
      ```

      **With loading shimmer:**
      ```r
      # data_ready is a reactiveVal — initialize in server:
      # data_ready <- reactiveVal(FALSE)
      output$sales_table <- renderReact({
        if (is.null(data_ready()) || !data_ready()) {
          ShimmeredDetailsList(
            items = list(),
            columns = list(/* same columns */),
            shimmerLines = 20,
            enableShimmer = TRUE
          )
        } else {
          DetailsList(items = items(), columns = columns)
        }
      })
      ```

      **GroupedList for hierarchical data:**
      ```r
      # Group sales by region
      groups <- list(
        list(key = "west", name = "West Region", count = sum(data$region == "west"),
          startIndex = 0, level = 0, isCollapsed = FALSE),
        list(key = "east", name = "East Region", count = sum(data$region == "east"),
          startIndex = sum(data$region == "west"), level = 0, isCollapsed = FALSE)
      )

      GroupedList(
        items = items,
        groups = groups,
        onRenderCell = JS("(nestingDepth, item, itemIndex) => {
          return React.createElement('div', { style: { padding: '8px 16px' } },
            item.customer + ' — $' + item.amount
          );
        }")
      )
      ```

      **DocumentCard for rich item display:**
      ```r
      DocumentCard(
        DocumentCardImage(imageSource = "/path/to/image.png"),
        DocumentCardDetails(
          DocumentCardTitle(title = "Customer Report", shouldTruncate = TRUE),
          DocumentCardStatus(status = "Completed")
        )
      )
      ```

      **Persona with data:**
      ```r
      Persona(
        text = "Alice Johnson",
        secondaryText = "Sales Lead",
        imageUrl = "/avatars/alice.png",
        size = 3  # 0-9, 3 = medium
      )
      ```

      Report: data display components added with sample data.
    gate: Review
    output: data_display_config

  - id: navigation
    requires: [inputs]
    inline-prompt: |
      Add navigation with Pivot, CommandBar, and Nav.

      Components: {{params.components}}

      If components is not 'navigation' or 'all', skip this step.

      **Pivot — tab-based navigation:**
      ```r
      # In UI:
      Pivot(
        PivotItem(headerText = "Overview", itemKey = "overview",
          reactOutput("overview_tab")),
        PivotItem(headerText = "Details", itemKey = "details",
          reactOutput("details_tab")),
        PivotItem(headerText = "Settings", itemKey = "settings",
          reactOutput("settings_tab")),
        onLinkClick = JS("(item) => Shiny.setInputValue('active_tab', item.props.itemKey)")
      )

      # In server:
      observeEvent(input$active_tab, {
        output[[paste0(input$active_tab, "_tab")]] <- renderReact({
          switch(input$active_tab,
            overview = Text("Overview content"),
            details = Text("Details content"),
            settings = Text("Settings content")
          )
        })
      })
      ```

      **CommandBar — toolbar with actions:**
      ```r
      CommandBar(
        items = list(
          CommandBarItem("New", "new", icon = "Add",
            onClick = JS("() => Shiny.setInputValue('cmd_new', Math.random())")),
          CommandBarItem("Edit", "edit", icon = "Edit",
            onClick = JS("() => Shiny.setInputValue('cmd_edit', Math.random())")),
          CommandBarItem("Delete", "delete", icon = "Delete",
            onClick = JS("() => Shiny.setInputValue('cmd_delete', Math.random())"))
        ),
        farItems = list(
          CommandBarItem("Refresh", "refresh", icon = "Refresh",
            onClick = JS("() => Shiny.setInputValue('cmd_refresh', Math.random())"))
        ),
        overflowItems = list(
          CommandBarItem("Export CSV", "export_csv", icon = "Download"),
          CommandBarItem("Print", "print", icon = "Print")
        )
      )

      # In server — handle CommandBar clicks:
      observeEvent(input$cmd_new, { /* open new form modal */ })
      observeEvent(input$cmd_refresh, { /* refetch data */ })
      ```

      **Nav — sidebar navigation:**
      ```r
      Nav(
        groups = list(
          list(name = "Main", links = list(
            list(name = "Dashboard", url = "#!/", icon = "Home", key = "dashboard"),
            list(name = "Customers", url = "#!/customers", icon = "People", key = "customers"),
            list(name = "Orders", url = "#!/orders", icon = "Shop", key = "orders"),
            list(name = "Analytics", url = "#!/analytics", icon = "Chart", key = "analytics")
          )),
          list(name = "Admin", links = list(
            list(name = "Users", url = "#!/users", icon = "Settings", key = "users"),
            list(name = "Audit Log", url = "#!/audit", icon = "Document", key = "audit")
          ))
        ),
        initialSelectedKey = "dashboard",
        onLinkClick = JS("(ev, item) => {
          Shiny.setInputValue('nav_page', item.key);
          return false;  // prevent page reload
        }")
      )
      ```

      **Breadcrumb — location trail:**
      ```r
      Breadcrumb(
        items = list(
          list(text = "Home", key = "home"),
          list(text = "Customers", key = "customers"),
          list(text = "Alice Johnson", key = "alice", isCurrentItem = TRUE)
        ),
        onItemClick = JS("(ev, item) => Shiny.setInputValue('breadcrumb_click', item.key)")
      )
      ```

      Report: navigation components added and wired to server.
    gate: Review
    output: navigation_config

  - id: layout-feedback
    requires: [inputs]
    inline-prompt: |
      Compose layouts with Stack, Modal, Panel and add feedback with MessageBar, Spinner.

      Components: {{params.components}}

      **Stack — the primary Fluent layout primitive:**
      ```r
      # Horizontal stack (form row)
      Stack(
        horizontal = TRUE,
        tokens = list(childrenGap = 15),
        Stack.Item(grow = 1,
          TextField.shinyInput("first_name", label = "First Name")),
        Stack.Item(grow = 1,
          TextField.shinyInput("last_name", label = "Last Name"))
      )

      # Vertical stack (page section)
      Stack(
        tokens = list(childrenGap = 20, padding = "20px 0"),
        Text("Customer Details", variant = "xLarge"),
        Separator(),
        reactOutput("customer_form")
      )

      # Nested stacks for complex layouts
      Stack(
        horizontal = TRUE,
        tokens = list(childrenGap = 20),
        Stack.Item(grow = 2,  # 2/3 width
          reactOutput("main_content")
        ),
        Stack.Item(grow = 1,  # 1/3 width
          reactOutput("sidebar")
        )
      )
      ```

      **Modal — dialog overlay:**
      ```r
      # In server:
      show_modal <- reactiveVal(FALSE)

      observeEvent(input$cmd_new, { show_modal(TRUE) })

      output$new_item_modal <- renderReact({
        if (!show_modal()) return(NULL)
        Modal(
          isOpen = TRUE,
          isBlocking = TRUE,
          titleAriaId = "modal_title",
          div(
            h2("Create New Item", id = "modal_title"),
            TextField.shinyInput("new_name", label = "Name"),
            Dropdown.shinyInput("new_type", label = "Type", options = list(
              list(key = "a", text = "Type A"),
              list(key = "b", text = "Type B")
            )),
            Stack(
              horizontal = TRUE,
              tokens = list(childrenGap = 10),
              style = "margin-top: 20px;",
              PrimaryButton("modal_save", "Save"),
              DefaultButton("modal_cancel", "Cancel")
            )
          ),
          onDismiss = JS("() => Shiny.setInputValue('modal_dismiss', Math.random())")
        )
      })

      observeEvent(input$modal_cancel, { show_modal(FALSE) })
      observeEvent(input$modal_dismiss, { show_modal(FALSE) })
      ```

      **Panel — slide-in sidebar:**
      ```r
      Panel(
        headerText = "Filters",
        isOpen = TRUE,
        isLightDismiss = TRUE,
        Stack(
          tokens = list(childrenGap = 15, padding = "16px"),
          DatePicker.shinyInput("filter_date", label = "Date"),
          Dropdown.shinyInput("filter_status", label = "Status", options = list(
            list(key = "all", text = "All"),
            list(key = "active", text = "Active"),
            list(key = "inactive", text = "Inactive")
          ))
        )
      )
      ```

      **MessageBar — status banners:**
      ```r
      # Initialize reactive values in server:
      # error_state <- reactiveVal(FALSE)
      # warning_state <- reactiveVal(FALSE)
      # success_state <- reactiveVal(FALSE)
      output$status_bar <- renderReact({
        if (error_state()) {
          MessageBar(
            messageBarType = 1,  # 1=error, 2=warning, 3=info, 4=blocked, 5=severeWarning, 0=success
            isMultiline = FALSE,
            truncated = TRUE,
            dismissButtonAriaLabel = "Close",
            paste("Error:", error_message())
          )
        } else if (warning_state()) {
          MessageBar(
            messageBarType = 2,
            warning_message()
          )
        } else if (success_state()) {
          MessageBar(
            messageBarType = 0,
            "Operation completed successfully."
          )
        }
      })
      ```

      **Spinner — loading indicator:**
      ```r
      # is_loading is a reactiveVal — initialize in server:
      # is_loading <- reactiveVal(FALSE)
      output$loading <- renderReact({
        if (is_loading()) {
          Spinner(
            label = "Loading data...",
            size = 3,  # 0-3, 3=large
            labelPosition = 3  # 0=top, 1=right, 2=bottom, 3=left
          )
        }
      })
      ```

      **ProgressIndicator — determinate progress:**
      ```r
      output$progress <- renderReact({
        ProgressIndicator(
          label = sprintf("Processing %d of %d records", processed(), total()),
          percentComplete = processed() / total(),
          barHeight = 4
        )
      })
      ```

      **TeachingBubble — onboarding tooltip:**
      ```r
      TeachingBubbleContent(
        headline = "Welcome to the Dashboard",
        hasCloseButton = TRUE,
        primaryButtonProps = list(children = "Got it"),
        "Use the CommandBar above to create, edit, and manage your data."
      )
      ```

      Report: layout composed, feedback components configured.
    gate: Review
    output: layout_feedback_config

tags:
  - r
  - shiny
  - fluent
  - appsilon
  - components
  - ui

allowed-tools:
  - "*"

constraints:
  - rule: "ALWAYS use .shinyInput() suffix on Fluent inputs in the UI — without it, Shiny input bindings won't work."
    severity: "error"
  - rule: "NEVER use .shinyInput() suffix in server code — access as input$<id>, not input$<id>.shinyInput."
    severity: "error"
  - rule: "ALWAYS use reactOutput() + renderReact() for dynamic Fluent content — renderUI() destroys React state on re-render."
    severity: "error"
  - rule: "NEVER mix base Shiny inputs (textInput, selectInput) with Fluent inputs in the same form — inconsistent styling."
    severity: "warning"
  - rule: "Use JS() for literal JavaScript in props (onClick, onRender) — strings are treated as static text."
    severity: "warning"
  - rule: "DetailsList items must be a list of lists, not a data.frame — convert with apply(data, 1, as.list, simplify = FALSE)."
    severity: "warning"
---

You are a Shiny + Fluent UI component specialist. You build rich UIs using
Microsoft Fluent UI components wrapped for R by Appsilon's shiny.fluent package.

## Component Architecture

```
R function call
  → shiny.react::reactElement()
    → React.createElement() in the browser
      → Fluent UI React component renders
        → onChange/focus/click fire
          → Shiny.setInputValue() bridges back to R
            → input$<id> updates in server
```

## Input Binding Pattern

Every Fluent input has two forms:
- **UI side**: `Component.shinyInput("my_id", ...)` — creates the React element + Shiny binding
- **Server side**: `input$my_id` — read the value (NO `.shinyInput` suffix)
- **Update function**: `updateComponent(session, "my_id", ...)` — change value from server

## Component Quick Reference

| Category | Key Components |
|----------|---------------|
| **Text** | TextField, MaskedTextField, TextField(multiline=TRUE) |
| **Selection** | Dropdown, ComboBox, ChoiceGroup, Checkbox, Toggle |
| **Date/Time** | DatePicker, Calendar |
| **Numbers** | Slider, SpinButton, Rating |
| **Search** | SearchBox |
| **Color** | ColorPicker, SwatchColorPicker |
| **Data** | DetailsList, GroupedList, DocumentCard, ShimmeredDetailsList |
| **Navigation** | Pivot, Nav, CommandBar, Breadcrumb |
| **Layout** | Stack, Stack.Item, Modal, Panel, Dialog |
| **Feedback** | MessageBar, Spinner, ProgressIndicator, TeachingBubble |
| **People** | Persona, Facepile, PeoplePicker, NormalPeoplePicker |

## Fluent vs Base Shiny Equivalents

| Base Shiny | Fluent UI |
|-----------|-----------|
| `textInput()` | `TextField.shinyInput()` |
| `selectInput()` | `Dropdown.shinyInput()` |
| `radioButtons()` | `ChoiceGroup.shinyInput()` |
| `checkboxInput()` | `Checkbox.shinyInput()` + `Toggle.shinyInput()` |
| `dateInput()` | `DatePicker.shinyInput()` |
| `sliderInput()` | `Slider.shinyInput()` |
| `actionButton()` | `PrimaryButton()` / `DefaultButton()` |
| `tabsetPanel()` | `Pivot()` |
| `navbarPage()` | `Nav()` + `CommandBar()` |
| `modalDialog()` | `Modal()` |
| `renderUI()` | `renderReact()` (preserves React state) |
| `DT::datatable()` | `DetailsList()` |
