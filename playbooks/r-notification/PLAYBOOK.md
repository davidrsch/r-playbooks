---
name: r-notification
version: 1.0.0
context-mode: Fork
description: "Send email and alert notifications from R applications: blastula for styled emails, Slack/Teams webhooks, pipeline status alerts, monitoring notifications, and scheduled report delivery"
trigger: both
trigger-patterns:
  - "notification *"
  - "send email *"
  - "email alert *"
  - "slack notification *"
  - "blastula *"
  - "alert * pipeline *"
  - "notify *"
  - "email report *"
  - "pipeline notification *"
argument-hint: "--channel email|slack|teams [--trigger pipeline|monitoring|custom] [--format html|text]"
parameters:
  channel:
    type: String
    required: false
    default: "email"
    enum: ["email", "slack", "teams"]
    hint: "Notification channel: blastula email, Slack webhook, or Microsoft Teams webhook"
  trigger:
    type: String
    required: false
    default: "pipeline"
    enum: ["pipeline", "monitoring", "release", "custom"]
    hint: "Trigger context: pipeline completion/failure, monitoring alert, package release, or custom event"
  format:
    type: String
    required: false
    default: "html"
    enum: ["html", "text"]
    hint: "Email format: styled HTML (blastula) or plain text"
steps:
  - id: set-up-blastula
    inline-prompt: |
      Configure blastula for sending styled emails from R.

      Channel: {{params.channel}}
      Format: {{params.format}}

      `blastula` (Posit/RStudio) is the standard R package for sending HTML emails
      with inline CSS, images, and attachments. Uses SMTP or external services.

      1. **Install blastula:**
         ```r
         install.packages("blastula")
         ```

      2. **Create SMTP credentials** (one-time setup):
         ```r
         library(blastula)

         # Create credentials file (never commit to git)
         create_smtp_creds_file(
           file = "~/.blastula/smtp_creds",
           user = Sys.getenv("SMTP_USER"),
           provider = "gmail",  # or: office365, outlook, yahoo, other
           host = Sys.getenv("SMTP_HOST"),
           port = 587,
           use_ssl = TRUE
         )

         # For Gmail, use an App Password (not your regular password)
         # Enable 2FA → App Passwords → Generate for "Mail"
         ```

      3. **Verify email configuration:**
         ```r
         # Send a test email
         blastula::smtp_send(
           email = compose_email(
             body = md("✅ Blastula is configured correctly!")
           ),
           to = "you@example.com",
           from = "notifications@yourdomain.com",
           subject = "Test from blastula",
           credentials = creds_file("~/.blastula/smtp_creds")
         )
         ```

      4. **For production: use environment variables, never hardcode paths:**
         ```r
         creds <- blastula::creds_env(
           user = Sys.getenv("SMTP_USER"),
           pass = Sys.getenv("SMTP_PASS"),
           provider = Sys.getenv("SMTP_PROVIDER", "gmail"),
           host = Sys.getenv("SMTP_HOST"),
           port = as.integer(Sys.getenv("SMTP_PORT", "587")),
           use_ssl = TRUE
         )
         ```

      Report: blastula configured and test email sent.
    gate: Confirm
    output: blastula_setup

  - id: create-notification-functions
    requires: [set-up-blastula]
    inline-prompt: |
      Create reusable notification functions for {{params.trigger}} context.

      Trigger: {{params.trigger}}
      Channel: {{params.channel}}

      **Standard notification wrapper** (`R/notify.R`):
      ```r
      library(blastula)
      library(glue)
      library(logger)

      # ── Email Notification ─────────────────────────────────────────────

      notify_email <- function(subject, body_md, success = TRUE, to = NULL,
                               attachment = NULL) {
        status_icon <- if (success) "✅" else "❌"
        status_color <- if (success) "#28a745" else "#dc3545"

        email <- blastula::compose_email(
          header = md(glue("## {status_icon} {subject}")),
          body = md(body_md),
          footer = md(glue(
            "<small>Sent at {Sys.time()} | {Sys.info()['nodename']}</small>"
          ))
        )

        # Attach file if provided (e.g., pipeline log, report PDF)
        if (!is.null(attachment) && file.exists(attachment)) {
          email <- blastula::add_attachment(email, attachment)
        }

        blastula::smtp_send(
          email = email,
          to = to %||% Sys.getenv("NOTIFY_EMAIL_TO"),
          from = Sys.getenv("NOTIFY_EMAIL_FROM", "notifications@yourdomain.com"),
          subject = glue("{status_icon} {subject}"),
          credentials = blastula::creds_env(
            user = Sys.getenv("SMTP_USER"),
            pass = Sys.getenv("SMTP_PASS"),
            provider = Sys.getenv("SMTP_PROVIDER", "gmail"),
            host = Sys.getenv("SMTP_HOST"),
            port = as.integer(Sys.getenv("SMTP_PORT", "587")),
            use_ssl = TRUE
          )
        )

        log_info("Email sent: {subject}")
      }

      # ── Slack Notification ─────────────────────────────────────────────

      notify_slack <- function(message, success = TRUE, fields = list()) {
        webhook_url <- Sys.getenv("SLACK_WEBHOOK_URL")
        if (webhook_url == "") {
          log_warn("SLACK_WEBHOOK_URL not set — Slack notification skipped")
          return(invisible(NULL))
        }

        color <- if (success) "good" else "danger"
        icon <- if (success) "✅" else "❌"

        httr2::request(webhook_url) |>
          httr2::req_body_json(list(
            text = glue("{icon} {message}"),
            attachments = list(list(
              color = color,
              fields = c(
                list(
                  list(title = "Host", value = Sys.info()["nodename"], short = TRUE),
                  list(title = "Time", value = as.character(Sys.time()), short = TRUE)
                ),
                fields
              )
            ))
          )) |>
          httr2::req_perform()

        log_info("Slack notification sent: {message}")
      }

      # ── Microsoft Teams Notification ───────────────────────────────────

      notify_teams <- function(message, success = TRUE) {
        webhook_url <- Sys.getenv("TEAMS_WEBHOOK_URL")
        if (webhook_url == "") {
          log_warn("TEAMS_WEBHOOK_URL not set — Teams notification skipped")
          return(invisible(NULL))
        }

        color <- if (success) "28a745" else "dc3545"
        icon <- if (success) "✅" else "❌"

        httr2::request(webhook_url) |>
          httr2::req_body_json(list(
            `@type` = "MessageCard",
            `@context` = "https://schema.org/extensions",
            themeColor = color,
            title = glue("{icon} {message}"),
            text = glue("Time: {Sys.time()}\nHost: {Sys.info()['nodename']}")
          )) |>
          httr2::req_perform()

        log_info("Teams notification sent: {message}")
      }

      # ── Unified Notification Router ────────────────────────────────────

      notify <- function(subject, body, success = TRUE, channel = "{{params.channel}}",
                         attachment = NULL, fields = list()) {
        switch(channel,
          email = notify_email(subject, body, success, attachment = attachment),
          slack = notify_slack(subject, success, fields),
          teams = notify_teams(subject, success),
          notify_email(subject, body, success)  # default
        )
      }
      ```

      Report: notification functions created and tested.
    gate: Review
    output: notification_functions

  - id: integrate-pipeline-notifications
    requires: [create-notification-functions]
    inline-prompt: |
      Integrate notifications into pipeline/workflow execution (when trigger is pipeline or release).

      Trigger: {{params.trigger}}

      If trigger is not `pipeline` or `release`, skip to the appropriate section.

      **For targets pipelines:**

      ```r
      # R/run-pipeline.R
      library(targets)
      library(logger)

      source("R/notify.R")

      run_pipeline <- function(pipeline_name = basename(getwd())) {
        start_time <- Sys.time()

        tryCatch({
          targets::tar_make()

          # Send success notification
          elapsed <- difftime(Sys.time(), start_time, units = "mins")
          tar_count <- nrow(targets::tar_progress())

          notify(
            subject = glue("{pipeline_name}: Pipeline completed"),
            body = glue(
              "**Pipeline:** {pipeline_name}\n",
              "**Status:** ✅ Completed successfully\n",
              "**Duration:** {round(elapsed, 1)} minutes\n",
              "**Targets built:** {tar_count}\n\n",
              "**Next scheduled run:** <next_run>"
            ),
            success = TRUE
          )
        }, error = function(e) {
          elapsed <- difftime(Sys.time(), start_time, units = "mins")

          # Capture last error details
          tar_errors <- targets::tar_meta() |>
            dplyr::filter(!is.na(error))

          error_details <- ""
          if (nrow(tar_errors) > 0) {
            error_details <- glue(
              "**Failed targets:**\n",
              paste("-", tar_errors$name, ":", tar_errors$error, collapse = "\n")
            )
          }

          notify(
            subject = glue("{pipeline_name}: Pipeline FAILED"),
            body = glue(
              "**Pipeline:** {pipeline_name}\n",
              "**Status:** ❌ FAILED after {round(elapsed, 1)} minutes\n",
              "**Error:** {conditionMessage(e)}\n\n",
              "{error_details}"
            ),
            success = FALSE
          )

          stop(e)
        })
      }

      run_pipeline()
      ```

      **For package release notifications:**
      ```r
      notify_release <- function(pkg_name, old_version, new_version, release_notes) {
        notify(
          subject = glue("{pkg_name} v{new_version} released"),
          body = glue(
            "**Package:** {pkg_name}\n",
            "**Version:** {old_version} → **{new_version}**\n\n",
            "## Changes\n{release_notes}\n\n",
            "**CRAN status:** [check results](<cran_url>)"
          ),
          success = TRUE
        )
      }
      ```

      **For monitoring alerts:**
      ```r
      notify_monitoring <- function(metric, value, threshold, status) {
        severity <- if (status == "critical") "❌" else "⚠️"

        notify(
          subject = glue("{severity} {metric} alert: {value}"),
          body = glue(
            "**Metric:** {metric}\n",
            "**Value:** {value}\n",
            "**Threshold:** {threshold}\n",
            "**Status:** {status}\n\n",
            "Investigate: <dashboard_url>"
          ),
          success = status != "critical"
        )
      }
      ```

      Report: notification integration tested with a manual trigger.
    gate: Review
    output: integration_result

  - id: configure-scheduled-reports
    requires: [create-notification-functions]
    inline-prompt: |
      Set up automated email delivery of scheduled reports (optional).

      1. **Create a report delivery function:**
         ```r
         deliver_report <- function(report_path, recipients, subject = NULL) {
           if (!file.exists(report_path)) {
             stop("Report file not found: ", report_path)
           }

           report_name <- basename(report_path)
           subject <- subject %||% glue("Report: {report_name} — {Sys.Date()}")

           notify_email(
             subject = subject,
             body_md = glue(
               "Your scheduled report **{report_name}** is attached.\n\n",
               "**Date:** {Sys.Date()}\n",
               "**Generated at:** {Sys.time()}"
             ),
             success = TRUE,
             to = recipients,
             attachment = report_path
           )
         }

         # Example usage:
         # deliver_report(
         #   "reports/daily_sales.html",
         #   c("team@company.com"),
         #   "Daily Sales Report — June 10, 2026"
         # )
         ```

      2. **Schedule with cronR** (for recurring report delivery):
         ```r
         cronR::cron_add(
           command = "Rscript -e 'source(\"R/deliver_reports.R\"); deliver_all_reports()'",
           frequency = "daily",
           at = "07:00",
           description = "Daily report delivery"
         )
         ```

      3. **For Quarto/HTML reports**, render before delivering:
         ```r
         deliver_quarto_report <- function(qmd_file, recipients) {
           # Render Quarto to HTML
           quarto::quarto_render(qmd_file)

           # Deliver the rendered output
           html_file <- gsub("\\.qmd$", ".html", qmd_file)
           deliver_report(html_file, recipients)
         }
         ```

      Report: scheduled report delivery configured.
    gate: Review
    output: report_delivery

tags:
  - r
  - notifications
  - email
  - blastula
  - slack
  - monitoring

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER commit SMTP credentials to git — use environment variables or keyring."
    severity: "error"
  - rule: "NEVER send sensitive data (passwords, tokens, PII) in notification bodies."
    severity: "error"
  - rule: "ALWAYS include failure notifications — silent failures in production are unacceptable."
    severity: "error"
  - rule: "ALWAYS test notification delivery before deploying to production — verify emails arrive."
    severity: "warning"
  - rule: "Use blastula for styled HTML emails — it's the Posit standard for R email."
    severity: "warning"
---

You are an R notification specialist. You set up email, Slack, and Teams
notifications for R applications, pipelines, and monitoring — using
`blastula` (Posit's R email package) and webhook-based alerting.

## Notification Philosophy

1. **FAILURE MUST BE LOUD**: A silent pipeline failure that goes unnoticed for
   days is worse than a pipeline that fails with immediate notification.
2. **SUCCESS IS QUIET**: Don't spam the team with "everything is fine" emails.
   Send success notifications only for notable events (release, milestone).
3. **CONTEXT MATTERS**: Every notification should include: what happened, when,
   where (which host/pipeline), and a link to investigate further.
4. **REUSABLE FUNCTIONS**: Build a single `notify()` function that routes to
   email, Slack, or Teams based on configuration. Don't scatter channel logic.
5. **SECRETS ARE ENVIRONMENT VARIABLES**: SMTP credentials, webhook URLs, and
   API keys live in environment variables — never in source code.

## Channel Decision Matrix

| Scenario | Channel | Why |
|----------|---------|-----|
| Pipeline failed at 3am | Slack + Email | Immediate + persistent |
| Daily report delivery | Email | Attachments, offline reading |
| Model drift detected | Slack | Real-time alert, needs attention |
| Package released to CRAN | Email | Announcement with details |
| Monitoring threshold breached | Slack | Real-time urgency |
| Weekly summary | Email | Rich HTML formatting |
