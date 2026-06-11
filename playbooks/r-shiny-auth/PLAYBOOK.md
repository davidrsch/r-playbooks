---
name: r-shiny-auth
version: 1.0.0
context-mode: Fork
description: "Add authentication and authorization to Shiny apps: credentials-based auth with shinymanager, OAuth/SSO with polished (Auth0), role-based access control, session timeouts, and secure credential storage — never hardcode passwords"
trigger: both
trigger-patterns:
  - "shiny auth *"
  - "authentication *"
  - "login * shiny *"
  - "add auth *"
  - "shinymanager *"
  - "polished auth *"
  - "secure shiny *"
  - "oauth shiny *"
  - "sso shiny *"
  - "user login *"
argument-hint: "--method shinymanager|polished [--auth-type credentials|oauth|ldap|sso] [--roles true|false] [--timeout 30]"
parameters:
  method:
    type: String
    required: false
    default: "shinymanager"
    enum: ["shinymanager", "polished"]
    hint: "Auth framework: shinymanager (credentials/SQL/LDAP, simpler) or polished (Auth0/SSO/OAuth, enterprise)"
  auth-type:
    type: String
    required: false
    default: "credentials"
    enum: ["credentials", "oauth", "ldap", "sso"]
    hint: "Authentication type: local credentials, OAuth (Google/GitHub), LDAP/Active Directory, or SSO (Auth0)"
  roles:
    type: Boolean
    required: false
    default: false
    hint: "Enable role-based access control (admin, editor, viewer)"
  timeout:
    type: Integer
    required: false
    default: 30
    min: 5
    max: 480
    hint: "Session timeout in minutes (inactivity before auto-logout)"
steps:
  - id: choose-auth-approach
    inline-prompt: |
      Assess the app and recommend the best authentication approach.

      Method: {{params.method}}
      Auth type: {{params.auth-type}}

      1. **Read the Shiny app structure:**
         - Locate `app.R` or `ui.R` + `server.R`
         - Identify all UI outputs and reactive expressions
         - Map which parts need authentication vs. which are public
         - If using golem or rhino, note the module structure

      2. **Recommendation matrix:**

         | Scenario | Recommended Method | Why |
         |----------|-------------------|-----|
         | Internal tool, < 50 users | `shinymanager` + credentials | Simplest setup, no external dependencies |
         | Internal tool, LDAP/AD | `shinymanager` + LDAP | Integrates with corporate directory |
         | External users, multiple orgs | `polished` + Auth0 SSO | Enterprise SSO, social login, MFA |
         | SaaS product, paying customers | `polished` + Auth0 OAuth | Multi-tenant, subscription tiers |
         | Open-source demo, optional auth | Either | Both support optional auth patterns |

      3. **Confirm the approach with the user** before implementing.

      Report: recommended approach with rationale.
    gate: Confirm
    output: auth_plan

  - id: implement-shinymanager
    requires: [choose-auth-approach]
    inline-prompt: |
      Implement authentication using `shinymanager` (Posit ecosystem).

      Auth plan: {{state.auth_plan}}
      Auth type: {{params.auth-type}}
      Roles enabled: {{params.roles}}
      Timeout: {{params.timeout}} minutes

      If method is not `shinymanager`, skip this step.

      1. **Install and set up shinymanager:**
         ```r
         install.packages("shinymanager")
         ```

      2. **Secure the app with credentials-based auth:**

         ```r
         # app.R
         library(shiny)
         library(shinymanager)

         # ── Credentials Database ────────────────────────────────────────
         # NEVER hardcode passwords in source code.
         # Use environment variables or a secure SQL database.

         credentials <- data.frame(
           user = c(Sys.getenv("ADMIN_USER"), "editor1", "viewer1"),
           password = c(
             Sys.getenv("ADMIN_PASS"),
             Sys.getenv("EDITOR_PASS"),
             Sys.getenv("VIEWER_PASS")
           ),
           # Password will be hashed automatically
           admin = c(TRUE, FALSE, FALSE),
           stringsAsFactors = FALSE
         )

         # ── UI ──────────────────────────────────────────────────────────
         ui <- secure_app(
           head_auth = tags$li(
             class = "dropdown",
             style = "position: absolute; right: 20px; top: 10px;",
             actionButton("logout", "Logout", class = "btn-danger")
           ),
           # Your existing UI goes here
           fluidPage(
             h1("My Secure App"),
             textOutput("welcome")
           )
         )

         # ── Server ──────────────────────────────────────────────────────
         server <- function(input, output, session) {
           # Auth is handled automatically by shinymanager
           # Access current user info anywhere:
           # reactiveValuesToList(session)$shinymanager_where

           result_auth <- secure_server(check_credentials = check_credentials(credentials))

           output$welcome <- renderText({
             paste("Welcome,", result_auth$user)
           })

           # Logout handler
           observeEvent(input$logout, {
             session$reload()
           })

           # Session timeout
           observe({
             invalidateLater({{params.timeout}} * 60000)  # minutes to ms
             session$reload()
           })
         }

         shinyApp(ui, server)
         ```

      3. **For SQL-backed credentials** (production-ready):
         ```r
         # Connect to a database for user management
         pool <- pool::dbPool(
           RSQLite::SQLite(),
           dbname = "users.sqlite"
         )

         # Create users table (run once)
         DBI::dbExecute(pool, "
           CREATE TABLE IF NOT EXISTS users (
             user TEXT PRIMARY KEY,
             password TEXT NOT NULL,
             admin INTEGER DEFAULT 0
           )
         ")

         # Use SQL as credentials source
         check_credentials_db <- function(user, password) {
           result <- DBI::dbGetQuery(pool,
             "SELECT user, password, admin FROM users WHERE user = ?",
             params = list(user)
           )
           if (nrow(result) == 1 && sodium::password_verify(result$password, password)) {
             list(result = "granted", user_info = list(user = user, admin = result$admin))
           } else {
             list(result = "refused")
           }
         }
         ```

      4. **For LDAP/Active Directory auth:**
         ```r
         # Use the keyring package to store bind credentials
         # LDAP auth via the ldapr package or RCurl
         check_credentials_ldap <- function(user, password) {
           # Bind to LDAP with user credentials
           # If bind succeeds, user is authenticated
           ldap_url <- Sys.getenv("LDAP_URL")
           base_dn <- Sys.getenv("LDAP_BASE_DN")

           # Use curl or RCurl to attempt LDAP bind
           # Return list(result = "granted") or list(result = "refused")
         }
         ```

      5. **Role-based access control** (if {{params.roles}} is true):
         ```r
         # In server:
         observe({
           user_role <- result_auth$admin  # from credentials

           # Show/hide UI elements based on role
           if (isTRUE(user_role)) {
             show("admin_panel")
           } else {
             hide("admin_panel")
           }
         })
         ```

      Report: shinymanager authentication implemented and tested.
    gate: Review
    output: shinymanager_impl

  - id: implement-polished
    requires: [choose-auth-approach]
    inline-prompt: |
      Implement authentication using `polished` (Appsilon/enterprise).

      Auth plan: {{state.auth_plan}}
      Auth type: {{params.auth-type}}

      If method is not `polished`, skip this step.

      `polished` provides enterprise authentication for Shiny with Auth0, OAuth,
      SSO, and social login. It requires an Auth0 account (free tier available).

      1. **Set up polished:**
         ```r
         install.packages("polished")
         # Or: remotes::install_github("tychobra/polished")
         ```

      2. **Configure Auth0:**
         - Create an Auth0 account at https://auth0.com
         - Create a "Regular Web Application"
         - Set callback URL: `http://localhost:3838`
         - Note: Client ID, Client Secret, and Domain

      3. **Secure the Shiny app:**
         ```r
         # app.R or global.R
         library(shiny)
         library(polished)

         # Configure polished with Auth0 credentials
         polished::global_sessions_config(
           app_name = "My Secure App",
           api_key = Sys.getenv("AUTH0_CLIENT_SECRET"),
           auth0_config = auth0::auth0_config(
             client_id = Sys.getenv("AUTH0_CLIENT_ID"),
             client_secret = Sys.getenv("AUTH0_CLIENT_SECRET"),
             auth0_domain = Sys.getenv("AUTH0_DOMAIN")
           )
         )

         # ── UI ──────────────────────────────────────────────────────────
         ui <- polished::secure_ui(
           # Your existing UI
           fluidPage(
             h1("Enterprise App"),
             textOutput("user_info")
           )
         )

         # ── Server ──────────────────────────────────────────────────────
         server <- function(input, output, session) {
           # polished handles the auth flow automatically
           user_metadata <- polished::get_user_metadata(session)

           output$user_info <- renderText({
             paste("Logged in as:", user_metadata$email)
           })

           # Role-based access from Auth0 app_metadata
           output$admin_panel <- renderUI({
             roles <- user_metadata$app_metadata$roles %||% c()
             if ("admin" %in% roles) {
               # Admin-only UI elements
             }
           })

           # Session timeout
           polished::set_session_timeout({{params.timeout}})
         }

         shinyApp(ui, server)
         ```

      4. **Configure social login providers** (Auth0 dashboard):
         - Google: Set up Google OAuth2 credentials
         - GitHub: Set up GitHub OAuth App
         - Microsoft: Azure AD enterprise SSO
         - All managed through Auth0 — no code changes needed

      5. **Multi-tenant setup** (SaaS pattern):
         Use Auth0 Organizations for tenant isolation:
         ```r
         polished::global_sessions_config(
           app_name = "My SaaS App",
           api_key = Sys.getenv("AUTH0_CLIENT_SECRET"),
           is_invite_required = FALSE,
           auth0_config = auth0::auth0_config(...)
         )
         ```

      Report: polished authentication implemented with Auth0.
    gate: Review
    output: polished_impl

  - id: test-authentication
    requires: [implement-shinymanager, implement-polished]
    inline-prompt: |
      Test the authentication implementation thoroughly.

      1. **Test basic login flow:**
         - [ ] Login with valid credentials → granted
         - [ ] Login with invalid credentials → refused with message
         - [ ] Login with empty fields → validation error
         - [ ] Logout → session cleared, redirected to login

      2. **Test role-based access (if {{params.roles}}):**
         ```r
         library(shinytest2)

         app <- AppDriver$new(
           app_dir = ".",
           name = "auth-test-admin"
         )
         # Simulate admin login
         app$set_inputs(user = "admin", password = "admin_pass")
         app$click("login_button")
         app$expect_text("#welcome", "Welcome, admin")
         app$expect_visible("#admin_panel")

         app$click("logout")

         # Simulate viewer login
         app$set_inputs(user = "viewer1", password = "viewer_pass")
         app$click("login_button")
         app$expect_text("#welcome", "Welcome, viewer1")
         app$expect_hidden("#admin_panel")

         app$stop()
         ```

      3. **Test session timeout:**
         - Login, wait for timeout period, verify auto-logout
         - Test activity resets the timeout counter

      4. **Test security boundaries:**
         - [ ] Cannot access protected pages without login
         - [ ] Session token is invalid after logout
         - [ ] Passwords are never logged or displayed
         - [ ] Failed login attempts are rate-limited (check)
         - [ ] Brute force protection (account lockout after N attempts — if configured)

      5. **Run your existing Shiny tests:**
         ```r
         devtools::test()
         ```
         Verify auth integration didn't break existing functionality.

      Report: test results and any issues found.
    gate: Review
    output: auth_tests

tags:
  - r
  - shiny
  - authentication
  - security
  - shinymanager
  - polished

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER hardcode passwords or secrets in source code — use environment variables, keyring, or a secure database."
    severity: "error"
  - rule: "NEVER log credentials or session tokens — passwords must never appear in logs."
    severity: "error"
  - rule: "ALWAYS use HTTPS in production — authentication without TLS is insecure."
    severity: "error"
  - rule: "ALWAYS implement session timeout — inactive sessions are a security risk."
    severity: "warning"
  - rule: "Use sodium::password_verify() for password checking — never compare passwords in plaintext."
    severity: "warning"
  - rule: "Test both successful AND failed login flows — don't just test the happy path."
    severity: "warning"
---

You are a Shiny authentication specialist. You add secure authentication and
authorization to Shiny apps using `shinymanager` (Posit ecosystem) or `polished`
(Appsilon/enterprise) — following OWASP authentication best practices.

## Authentication Philosophy

1. **NEVER ROLL YOUR OWN**: Use battle-tested frameworks (`shinymanager`,
   `polished`). Custom auth code is the #1 security vulnerability in Shiny apps.
2. **SECRETS IN ENVIRONMENT**: Credentials live in environment variables,
   keyring, or a secure database — never in source code.
3. **HTTPS MANDATORY**: Authentication without TLS encryption sends passwords
   in plaintext over the network. Always deploy behind HTTPS.
4. **SESSION TIMEOUT**: Inactive sessions are a security risk. Auto-logout
   after a configurable period of inactivity.
5. **LEAST PRIVILEGE**: Users should see only what their role permits. Implement
   role-based access control from day one.

## Framework Comparison

| Feature | shinymanager | polished |
|---------|-------------|----------|
| Setup complexity | Low | Medium |
| Credential storage | SQLite, SQL DB, LDAP | Auth0 (managed) |
| Social login (Google, GitHub) | ❌ | ✅ (via Auth0) |
| Enterprise SSO (Azure AD, Okta) | ❌ | ✅ (via Auth0) |
| Multi-factor auth | ❌ | ✅ (via Auth0) |
| Multi-tenancy | ❌ | ✅ |
| Free tier | ✅ (open source) | ✅ (Auth0 free tier) |
| Best for | Internal tools, small orgs | SaaS products, enterprise |
| R package | `shinymanager` (CRAN) | `polished` (GitHub) |
