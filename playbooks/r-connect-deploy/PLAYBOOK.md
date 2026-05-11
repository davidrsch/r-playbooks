---
name: r-connect-deploy
version: 1.0.0
context-mode: Fork
description: Deploy an R application to Posit Connect with manifest and git-backed deployment
trigger: both
trigger-patterns:
  - "deploy to connect *"
  - "connect deploy *"
  - "publish to connect *"
  - "rsconnect deploy *"
argument-hint: "--app <path> --server <url> [--account <name>] [--title <title>]"
parameters:
  app:
    type: String
    required: true
    hint: "Path to the application directory (Shiny app, Plumber API, Quarto doc)"
  server:
    type: String
    required: true
    hint: "Posit Connect server URL (e.g., https://connect.example.com)"
  account:
    type: String
    required: false
    hint: "Connect account name (if not set, uses default)"
  title:
    type: String
    required: false
    hint: "Display title on Connect (defaults to app name)"
steps:
  - id: validate-connect-access
    inline-prompt: |
      Verify Posit Connect access and configuration:

      1. Check rsconnect is installed:
         ```r
         if (!requireNamespace("rsconnect", quietly = TRUE)) {
            renv::install("rsconnect")
          }
         packageVersion("rsconnect")
         ```

      2. Verify Connect server is reachable:
         ```bash
         curl -s {{params.server}}/__api__/v1/server_settings | head -20
         ```

      3. Verify account configuration:
         ```r
         rsconnect::accounts()
         # Should list the {{params.server}} server
         ```

      4. If account not configured, set it up:
         ```r
         rsconnect::setAccountInfo(
           name = "{{params.account}}",
           token = Sys.getenv("CONNECT_API_KEY"),
           secret = Sys.getenv("CONNECT_SECRET"),
           server = "{{params.server}}"
         )
         ```

      Report: rsconnect version, server reachable, account configured.
    output: connect-access
  - id: write-manifest
    inline-prompt: |
      Generate manifest.json for {{params.app}}:

      ```r
      # Generate manifest capturing R version, packages, and app metadata
      rsconnect::writeManifest(appDir = "{{params.app}}")

      manifest <- jsonlite::read_json("{{params.app}}/manifest.json")
      cat("App mode:", manifest$metadata$appmode %||% "not set: Connect will auto-detect")
      ```

      This creates `{{params.app}}/manifest.json` containing:
      - R version (PEP 440 format)
      - All R package dependencies with source repositories
      - App metadata (entrypoint, app mode)

      Review the manifest:
      ```r
      manifest <- jsonlite::read_json("{{params.app}}/manifest.json")
      # Check packages list
      names(manifest$packages)
      # Check R version
      manifest$platform

      for (pkg in names(manifest$packages)) {
        pkg_info <- manifest$packages[[pkg]]
        if (is.null(pkg_info$Repository)) {
          message("WARNING: ", pkg, " has no Repository: may fail on Connect")
        }
      }
      ```

      Commit manifest.json to git:
      ```bash
      git add {{params.app}}/manifest.json
      git commit -m "Add Connect manifest.json for {{params.app}}"
      ```

      Note: manifest.json should be committed to git for git-backed deployment.
    requires:
      - validate-connect-access
    output: manifest-file
    gate: Review
  - id: deploy-app
    inline-prompt: |
      Deploy the application to Posit Connect:

      ```r
      rsconnect::deployApp(
        appDir = "{{params.app}}",
        appTitle = "{{params.title}}",
        account = "{{params.account}}",
        server = "{{params.server}}",
        forceUpdate = TRUE,
        launch.browser = FALSE
      )
      ```

      The deployment process:
      1. Archives the app directory (including manifest.json)
      2. Uploads to Connect
      3. Connect reads manifest.json and restores the R environment
      4. Connect deploys the app

      Record the app URL from the deployment output.
      Format: `https://<server>/content/<app-id>/`

      If using git-backed deployment, Connect will automatically:
      - Pull from the git repository on push to the configured branch
      - Restore the R environment from manifest.json
      - Deploy the updated app
    requires:
      - write-manifest
    output: deployment-result
    gate: Approve
  - id: verify-deployment
    inline-prompt: |
      Verify the deployed application:

      1. Check app status via Connect API:
         ```bash
         curl -H "Authorization: Key ${CONNECT_API_KEY}" \
           {{params.server}}/__api__/v1/content | grep {{params.title}}
         ```

      2. Visit the app URL in browser: confirm it loads without errors.

      3. Check logs on Connect:
         - Visit `{{params.server}}/connect/#/apps/<app-id>/logs`
         - Confirm no startup errors
         - Verify all packages resolved correctly

      4. Test key functionality:
         - Shiny: interact with inputs, verify outputs
         - Plumber: hit the /__docs__/ endpoint, test a prediction
         - Quarto: verify the rendered document loads

      Report: app URL, status, log check, functionality test.
    requires:
      - deploy-app
    output: verification-report
tags:
  - r
  - deployment
  - connect
  - production
  - devops
constraints:
  - rule: "NEVER hardcode secrets or tokens in workflow files — use GitHub Secrets."
    severity: "error"
  - rule: "ALWAYS include HEALTHCHECK in Dockerfiles."
    severity: "warning"
  - rule: "Never expose ports without proper security configuration."
    severity: "warning"
  - rule: "Use multi-stage Docker builds to minimize image size."
    severity: "warning"
allowed-tools:
  - "*"
---

# R Posit Connect Deployment Playbook

You are an expert in deploying R applications to Posit Connect. Use rsconnect for deployment with manifest.json for reproducible environments.

## Connect Deployment Concepts

### manifest.json

- Generated by `rsconnect::writeManifest()`
- Captures exact R version and all package sources
- Must be committed to git for git-backed deployment
- Connect reads it to restore the R environment

### Deployment Modes

1. **Push-button** (`rsconnect::deployApp()`): Direct upload from local
2. **Git-backed**: Connect polls git repo; on push, auto-deploys
3. **Programmatic**: Connect API for automated CI/CD deployment

### Connect URL Structure

```
https://<server>/content/<app-id>/        → Application
https://<server>/content/<app-id>/__docs__/ → API docs (Plumber)
https://<server>/connect/#/apps/<app-id>/   → Admin dashboard
```

## Best Practices

### Before Deploying

1. **Write manifest.json**: always update before deploying
2. **Commit manifest.json**: for git-backed deployment
3. **Test locally**: verify app runs correctly
4. **Check renv.lock**: dependencies should be reproducible
5. **Set R_CONFIG_ACTIVE**: for environment-specific config

### Security

1. **Never hardcode API keys** in connect manifests
2. **Use Connect environment variables** for secrets
3. **Set `CONNECT_API_KEY`** via env var, not in code
4. **Restrict access** via Connect's user/group permissions

### CI/CD Pattern

```yaml
- name: Deploy to Connect
  run: |
    Rscript -e 'rsconnect::writeManifest("app")'
    Rscript -e 'rsconnect::deployApp("app", server = "${{ secrets.CONNECT_SERVER }}")'
  env:
    CONNECT_API_KEY: ${{ secrets.CONNECT_API_KEY }}
```
