---
name: r-schedule-pipeline
version: 1.0.0
context-mode: Fork
description: "Schedule targets pipelines for production: configure cron-based execution with cronR or GHA scheduled workflows, set up checkpoint/resume, failure notifications, logging, and pipeline health monitoring"
trigger: both
trigger-patterns:
  - "schedule pipeline *"
  - "schedule targets *"
  - "production pipeline *"
  - "cron pipeline *"
  - "deploy pipeline *"
  - "run targets * production *"
  - "pipeline schedule *"
  - "automate pipeline *"
argument-hint: "[--schedule daily|weekly|hourly] [--method cronr|gha|airflow] [--notify email|slack|none] [--checkpoint true|false]"
parameters:
  schedule:
    type: String
    required: false
    default: "daily"
    enum: ["hourly", "daily", "weekly"]
    hint: "Execution frequency: hourly, daily, or weekly"
  method:
    type: String
    required: false
    default: "cronr"
    enum: ["cronr", "gha", "airflow"]
    hint: "Scheduling method: cronR (local/on-prem), GHA (GitHub Actions scheduled), or Airflow (enterprise)"
  notify:
    type: String
    required: false
    default: "none"
    enum: ["email", "slack", "none"]
    hint: "Failure notification channel"
  checkpoint:
    type: Boolean
    required: false
    default: true
    hint: "Enable automatic pipeline checkpointing for resume after interruption"
steps:
  - id: assess-pipeline
    inline-prompt: |
      Assess the targets pipeline and determine scheduling requirements.

      1. **Read the pipeline definition:**
         ```r
         library(targets)
         tar_manifest()     # list all targets and their commands
         tar_visnetwork()   # visualize the pipeline DAG
         tar_glimpse()      # summary of pipeline status
         ```

      2. **Measure pipeline runtime:**
         ```r
         # If pipeline has been run before:
         tar_progress() %>%
           dplyr::filter(type == "stem") %>%
           dplyr::summarise(
             total_seconds = sum(seconds, na.rm = TRUE),
             total_minutes = sum(seconds, na.rm = TRUE) / 60
           )
         ```
         Pipeline runtime determines scheduling feasibility:
         - < 5 min → hourly possible
         - < 1 hour → hourly/daily possible
         - < 6 hours → daily/nightly
         - > 6 hours → daily (off-peak) or weekly

      3. **Identify external dependencies:**
         - Database connections (are they available 24/7?)
         - API endpoints (rate limits, availability windows)
         - File drops (when do upstream files arrive?)
         - Network access (VPN required? corporate network?)
         - Credential expiration (OAuth tokens, temporary keys)

      4. **Check existing scheduling:**
         - Is there already a cron job for this pipeline?
         - Is there already a GHA workflow with a schedule trigger?
         - Check for existing monitoring on pipeline outputs.

      5. **Identify output consumers:**
         - Dashboards that depend on pipeline outputs?
         - Downstream models that consume pipeline results?
         - Reports that are generated from pipeline outputs?
         → Schedule must complete before consumers need fresh data.

      Report: pipeline summary, runtime estimate, dependencies, and scheduling
      constraints.
    gate: Confirm
    output: pipeline_assessment

  - id: configure-scheduling
    requires: [assess-pipeline]
    inline-prompt: |
      Configure the scheduling method for the pipeline.

      Schedule: {{params.schedule}}
      Method: {{params.method}}
      Pipeline assessment: {{state.pipeline_assessment}}

      **Method A: cronR (local/on-prem server)**

      ```r
      library(cronR)

      # Create the pipeline run script
      script_path <- "R/run-pipeline.R"
      writeLines(c(
        'library(targets)',
        'library(logger)',
        '',
        'log_info("Pipeline run started at {Sys.time()}")',
        '',
        'tryCatch({',
        '  targets::tar_make()',
        '  log_info("Pipeline completed successfully")',
        '}, error = function(e) {',
        '  log_error("Pipeline FAILED: {conditionMessage(e)}")',
        '  # Send notification',
        '  quit(status = 1)',
        '})'
      ), script_path)

      # Schedule with cronR
      cronR::cron_add(
        command = sprintf("Rscript %s", script_path),
        frequency = "{{params.schedule}}",
        at = if ("{{params.schedule}}" == "daily") "03:00" else NULL,
        days_of_week = if ("{{params.schedule}}" == "weekly") 1 else NULL,  # Monday
        description = "targets pipeline: <pipeline_name>"
      )

      # Verify the cron job was added
      cronR::cron_ls()

      # To remove: cronR::cron_rm("<id>")
      ```

      **Method B: GitHub Actions scheduled workflow**

      Create `.github/workflows/pipeline-scheduled.yaml`:
      ```yaml
      name: Scheduled Pipeline
      on:
        schedule:
          # Adjust schedule as needed: daily, hourly, or weekly per {{params.schedule}}
          - cron: '0 3 * * *'
        workflow_dispatch:  # Allow manual trigger

      jobs:
        run-pipeline:
          runs-on: ubuntu-latest
          steps:
            - uses: actions/checkout@v4

            - uses: r-lib/actions/setup-r@v2
              with:
                r-version: 'renv'

            - uses: r-lib/actions/setup-renv@v2

            - name: Run targets pipeline
              run: |
                Rscript -e '
                targets::tar_make()
                '

            - name: Notify on failure
              if: failure()
              uses: slackapi/slack-github-action@v1
              with:
                payload: |
                  {
                    "text": "❌ Pipeline FAILED: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
                  }
              env:
                SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
      ```

      **Method C: Airflow (enterprise orchestration)**

      For Airflow DAG definitions, create a Python DAG that calls the R pipeline:
      ```python
      # dags/r_pipeline_dag.py
      from airflow import DAG
      from airflow.operators.bash import BashOperator
      from datetime import datetime, timedelta

      with DAG(
          'r_targets_pipeline',
          schedule_interval='0 3 * * *',  # daily at 3am
          start_date=datetime(2026, 1, 1),
          catchup=False,
          tags=['R', 'targets'],
      ) as dag:
          run_pipeline = BashOperator(
              task_id='run_targets',
              bash_command='cd /path/to/project && Rscript -e "targets::tar_make()"',
          )
      ```

      Report: scheduling configuration created and verified.
    gate: Review
    output: scheduling_config

  - id: configure-checkpointing
    requires: [configure-scheduling]
    inline-prompt: |
      Set up checkpoint/resume for long-running pipelines.

      Checkpoint enabled: {{params.checkpoint}}

      If checkpoint is false, skip this step.

      targets has built-in checkpointing — if a pipeline is interrupted, running
      `tar_make()` again resumes from the last completed target. No additional
      configuration is needed for basic resume. However, for production robustness:

      1. **Configure crew for parallel execution with resume:**
         ```r
         # _targets.R
         library(targets)
         library(crew)

         tar_option_set(
           controller = crew::crew_controller_local(workers = 4),
           memory = "transient",   # don't keep targets in memory
           garbage_collection = TRUE,
           error = "null"          # null: skip errored targets, continue others
         )
         ```

      2. **Add pipeline heartbeat monitoring:**
         ```r
         # In your _targets.R or run script:
         heartbeat_file <- file.path(tempdir(), "pipeline_heartbeat.txt")
         writeLines(as.character(Sys.time()), heartbeat_file)

         # A separate monitoring script can check heartbeat_file age
         # and alert if the pipeline appears stuck (> expected runtime * 2)
         ```

      3. **Set up automatic retry on transient errors:**
         ```r
         # In _targets.R:
         tar_option_set(
           retries = 3,          # retry each target up to 3 times
           error = "continue",   # continue on error, report failures at end
           # For specific targets that can fail transiently:
           # tar_target(
           #   name = api_data,
           #   command = tryCatch(
           #     fetch_api_data(),
           #     error = function(e) {
           #       Sys.sleep(60)  # wait and retry
           #       fetch_api_data()
           #     }
           #   ),
           #   retries = 5
           # )
         )
         ```

      4. **Set a maximum runtime to prevent hung pipelines:**
         ```r
         # In the scheduling script:
         setTimeLimit(elapsed = 21600)  # 6 hours max for daily pipeline
         # If exceeded, R will throw an error, triggering the failure handler
         ```

      5. **Log checkpoint events:**
         ```r
         library(logger)
         log_formatter(logger::formatter_glue)

         tar_make_with_logging <- function() {
           log_info("Pipeline starting at {Sys.time()}")
           start_time <- Sys.time()

           tryCatch({
             tar_make()
             elapsed <- difftime(Sys.time(), start_time, units = "mins")
             log_info("Pipeline completed in {round(elapsed, 1)} minutes")
           }, error = function(e) {
             elapsed <- difftime(Sys.time(), start_time, units = "mins")
             log_error("Pipeline failed after {round(elapsed, 1)} minutes: {conditionMessage(e)}")
             stop(e)
           })
         }
         ```

      Report: checkpointing and retry configuration.
    gate: Review
    output: checkpoint_config

  - id: configure-notifications
    requires: [configure-scheduling]
    inline-prompt: |
      Configure failure notifications and pipeline health alerts.

      Notification method: {{params.notify}}

      If notification is 'none', create a minimal log-based notification and skip
      external integrations.

      **Email notifications (if notify = email):**
      ```r
      library(gmailr)    # Gmail API
      # Or: library(emayili)   # SMTP-based
      # Or: library(blastula)  # Posit's email package

      notify_email <- function(subject, body, success = TRUE) {
        library(blastula)

        email <- compose_email(
          body = md(body)
        )

        smtp_send(
          email,
          to = "data-team@company.com",
          from = "pipeline-bot@company.com",
          subject = sprintf("[%s] %s", if (success) "OK" else "FAIL", subject),
          credentials = creds_env(
            user = Sys.getenv("SMTP_USER"),
            pass = Sys.getenv("SMTP_PASS"),
            provider = "gmail"
          )
        )
      }
      ```

      **Slack notifications (if notify = slack):**
      ```r
      notify_slack <- function(message, success = TRUE) {
        webhook_url <- Sys.getenv("SLACK_WEBHOOK_URL")

        payload <- list(
          text = sprintf("%s %s",
            if (success) "✅" else "❌",
            message
          ),
          attachments = list(list(
            color = if (success) "good" else "danger",
            fields = list(
              list(title = "Pipeline", value = basename(getwd()), short = TRUE),
              list(title = "Time", value = as.character(Sys.time()), short = TRUE)
            )
          ))
        )

        httr2::request(webhook_url) %>%
          httr2::req_body_json(payload) %>%
          httr2::req_perform()
      }
      ```

      **Integrated notification wrapper:**
      ```r
      run_pipeline_with_notifications <- function(pipeline_name) {
        start_time <- Sys.time()

        tryCatch({
          targets::tar_make()

          # Success notification
          elapsed <- difftime(Sys.time(), start_time, units = "mins")
          msg <- sprintf("Pipeline '%s' completed successfully in %.1f min", pipeline_name, elapsed)

          # Send notification based on configured method ({{params.notify}}):
          #   email → notify_email(msg, msg, success = TRUE)
          #   slack → notify_slack(msg, success = TRUE)

          log_info(msg)

        }, error = function(e) {
          # Failure notification
          elapsed <- difftime(Sys.time(), start_time, units = "mins")
          msg <- sprintf("Pipeline '%s' FAILED after %.1f min: %s", pipeline_name, elapsed, conditionMessage(e))

          # Send failure notification based on configured method ({{params.notify}}):
          #   email → notify_email(msg, msg, success = FALSE)
          #   slack → notify_slack(msg, success = FALSE)

          log_error(msg)
          quit(status = 1)
        })
      }
      ```

      Report: notification configuration tested (send a test message).
    gate: Review
    output: notification_config

  - id: validate-schedule
    requires: [configure-checkpointing, configure-notifications]
    inline-prompt: |
      Validate the complete scheduling setup with a test run.

      1. **Run a manual test of the scheduled pipeline:**
         ```bash
         Rscript R/run-pipeline.R
         ```
         Verify:
         - [ ] Pipeline completes without errors
         - [ ] Log file is written with expected output
         - [ ] Notifications are sent (check email/Slack for test message)
         - [ ] Output targets are up-to-date
         - [ ] No unexpected warnings or notes

      2. **Verify the cron job / GHA workflow / Airflow DAG:**
         ```r
         # cronR
         cronR::cron_ls()

         # GHA
         # Push the workflow file and check Actions tab for the scheduled trigger
         # Use workflow_dispatch to test manually:
         # gh workflow run pipeline-scheduled.yaml
         ```

      3. **Set up pipeline health monitoring:**
         ```r
         # Monitor script: R/monitor-pipeline.R
         # - Check if outputs are fresh (last modified within expected window)
         # - Check if heartbeat file exists and is recent
         # - Check log file for errors
         # - Run pointblank validation on key outputs

         check_pipeline_health <- function(pipeline_dir, max_age_hours = 25) {
           # Check output freshness
           meta <- targets::tar_meta()
           completed <- meta[meta$progress == "built", ]
           last_run <- max(completed$time, na.rm = TRUE)

           if (is.na(last_run)) {
             stop("No completed targets found — has the pipeline ever run?")
           }

           age_hours <- as.numeric(difftime(Sys.time(), last_run, units = "hours"))
           if (age_hours > max_age_hours) {
             stop(sprintf("Pipeline outputs are %.1f hours old (threshold: %d hours)",
               age_hours, max_age_hours))
           }

           cat(sprintf("✅ Pipeline healthy: last run %.1f hours ago\n", age_hours))
         }

         check_pipeline_health(".")
         ```

      4. **Simulate a failure to verify notifications work:**
         Temporarily introduce an error in one target, run the pipeline,
         verify that failure notifications are sent, then revert.

      Report: validation results for all components.
    gate: Approve
    output: validation_results

tags:
  - r
  - targets
  - scheduling
  - cron
  - production
  - pipeline
  - crew

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER schedule a pipeline without first testing it manually — verify it completes successfully."
    severity: "error"
  - rule: "ALWAYS configure failure notifications — silent pipeline failures corrupt downstream data."
    severity: "error"
  - rule: "NEVER schedule overlapping runs — ensure pipeline runtime < scheduling interval."
    severity: "error"
  - rule: "ALWAYS set a maximum runtime limit — hung pipelines waste resources and block subsequent runs."
    severity: "warning"
  - rule: "Use targets built-in checkpointing (tar_make resume) — it works out of the box."
    severity: "warning"
  - rule: "Monitor pipeline output freshness — stale outputs are silent failures."
    severity: "warning"
---

You are a targets pipeline production scheduling specialist. You configure
targets pipelines for unattended production execution with checkpoint/resume,
failure notifications, and health monitoring — following Posit professional
data engineering practices.

## Scheduling Philosophy

1. **MANUAL BEFORE AUTOMATIC**: Always run the pipeline manually first. If it
   doesn't work interactively, it won't work scheduled.
2. **FAILURE IS INEVITABLE**: Every pipeline will fail eventually. The key is
   knowing about it immediately via notifications, not discovering it days later.
3. **CHECKPOINT EVERYTHING**: targets has built-in checkpointing — if a pipeline
   is interrupted, `tar_make()` resumes from the last completed target. Use it.
4. **MONITOR FRESHNESS**: The most common silent failure is stale outputs.
   Monitor when outputs were last updated, not just whether the process ran.
5. **NO OVERLAPPING RUNS**: Ensure pipeline runtime < scheduling interval.
   A daily pipeline that takes 30 hours will cascade.

## Scheduling Methods Comparison

| Method | Best For | Setup Complexity | Monitoring | Cost |
|--------|----------|-----------------|------------|------|
| cronR | On-prem servers, Linux/macOS | Low | Manual logs | Free |
| GHA scheduled | GitHub-hosted projects, cloud | Low | Built-in logs | Free (limits apply) |
| Airflow | Enterprise, multi-pipeline DAGs | High | Built-in UI | Infrastructure |

## targets Production Patterns

- **crew for parallel execution**: `crew::crew_controller_local(workers = N)`
  for parallel target execution within the scheduled run.
- **memory = "transient"**: Don't keep targets in memory after completion.
  Reduces memory footprint for long-running pipelines.
- **retries**: `tar_option_set(retries = 3)` for transient errors.
- **error = "continue"**: Don't stop the whole pipeline on one target failure.
- **tar_meta() for monitoring**: Check `tar_meta()` output for target ages,
  errors, and warnings programmatically.
