---
name: r-targets-crew
version: 1.0.0
context-mode: Fork
description: Configure the crew parallel backend for a targets pipeline (mirai-based, replaces future)
trigger: both
trigger-patterns:
  - "configure crew *"
  - "crew backend *"
  - "set up crew *"
  - "add crew *"
  - "parallel backend *"
  - "switch to crew *"
  - "migrate to crew *"
argument-hint: "[--workers <n>] [--migrate-from future|sequential] [--launcher local|slurm|sge|pbs]"
parameters:
  workers:
    type: Number
    required: false
    default: 4
    hint: "Number of parallel workers (default: 4, use detectCores() - 1 for max)"
  migrate:
    type: String
    required: false
    default: "sequential"
    enum: ["sequential", "future"]
    hint: "Current backend to migrate from: sequential (default) or future"
  launcher:
    type: String
    required: false
    default: "local"
    enum: ["local", "slurm", "sge", "pbs"]
    hint: "Scheduler/launcher type: local for single machine, slurm/sge/pbs for HPC clusters"
steps:
  - id: install-crew
    inline-prompt: |
      Install and verify the crew package and its dependencies:

      1. Install crew and mirai via renv:
         ```r
         renv::install(c("crew", "mirai", "nanonext"))
         ```


      2. Verify installation:
         ```r
         packageVersion("crew")   # should be >= 0.9.0
         packageVersion("mirai")  # should be >= 0.13.0
         ```

      3. Test a basic crew controller:
         ```r
         library(crew)
         controller <- crew_controller_local(workers = 2)
         controller$start()
         controller$push(name = "test", command = Sys.sleep(1); Sys.info()[["user"]])
         controller$wait()
         result <- controller$pop()$result
         controller$terminate()
         print(result)
         ```

      Report: installed versions, test result.
    output: install_status

  - id: configure-controller
    requires: [install-crew]
    inline-prompt: |
      Configure the crew controller in `_targets.R`.

      Workers: {{params.workers}}
      Launcher: {{params.launcher}}

      ## Local Workers
      Add to the top of `_targets.R` (after `library(targets)`):
      ```r
      library(crew)
      tar_option_set(
        controller = crew_controller_local(
          workers = {{params.workers}},
          tasks_max = 100,
          seconds_idle = 60
        )
      )
      ```

      Controller options explained:
      - `workers`: Number of persistent mirai daemons.
      - `tasks_max`: Max tasks per worker before recycling (prevents memory leaks).
      - `seconds_idle`: Seconds of idle time before terminating idle workers.
      - `seconds_launch`: Max time to wait for worker startup.
      - `seconds_wall`: Soft wall time limit per worker.

      ## HPC Launchers
      If {{params.launcher}} is not "local":
      ```r
      tar_option_set(
        controller = crew_controller_group(
          crew_controller_local(workers = 1),  # local fallback for lightweight targets
          crew_controller_slurm(               # or sge, pbs
            workers = {{params.workers}},
            script_lines = paste0(
              "#SBATCH --mem=8G",
              "#SBATCH --cpus-per-task=2",
              "#SBATCH --time=04:00:00"
            )
          )
        )
      )
      ```

      1. Read the existing `_targets.R` to check for any existing `tar_option_set()`.
         If one exists, merge the `controller` setting into the existing call.
         Do NOT create duplicate `tar_option_set()` calls.
      2. Add `library(crew)` if not already present.
      3. Run: `targets::tar_config_set(store = "_targets")` to ensure store path.
      4. Report: the controller configuration and modified sections of `_targets.R`.
    gate: Confirm
    output: controller_config

  - id: migrate-from-future
    requires: [configure-controller]
    inline-prompt: |
      Handle migration from the future backend if applicable.

      Current backend: {{params.migrate}}

      If {{params.migrate}} is "sequential": Skip migration. Report: no migration needed (clean setup).

      If {{params.migrate}} is "future":
      1. Read `_targets.R` and identify future-specific code:
         - `library(future)` or `library(future.callr)`
         - `tar_option_set(backends = future::plan(...))`
         - Any `future::plan(multisession)` or similar.
      2. Remove or comment out:
         - `library(future)` and `library(future.callr)`
         - `tar_option_set(backends = ...)` — replaced by crew controller.
      3. The crew controller from the previous step already handles parallel execution.
         No further changes needed.
      4. Clean up the targets store from old future artifacts:
         ```r
         targets::tar_destroy(ask = FALSE)
         ```
         WARNING: This deletes the targets metadata store. Make sure this is what the user wants.
      5. Validate the migration by running:
         ```r
         tar_manifest(callr_function = NULL)
         ```
      6. Report:
         - What future code was removed.
         - Whether the store was destroyed.
         - Manifest validation result.

      Key differences crew vs future:
      - crew uses persistent workers (mirai daemons); future spawns per-task.
      - crew has zero-copy data transfer via nanonext; future serializes.
      - crew has built-in OTEL tracing via mirai 2.5+.
      - crew auto-scales workers; future has fixed plan.
    gate: Approve
    output: migration_result

  - id: verify-parallel
    requires: [migrate-from-future, configure-controller]
    inline-prompt: |
      Verify parallel execution with the crew backend:

      1. Run the pipeline with crew:
         ```r
         targets::tar_make(callr_function = NULL, reporter = "crew")
         ```
         Observe that multiple workers are active simultaneously.

      2. Verify worker activity:
         ```r
         library(crew)
         ctrl <- crew_controller_local(workers = {{params.workers}})
         ctrl$start()
         # Push a diagnostic task to each worker
         for (i in seq_len({{params.workers}})) {
           ctrl$push(
             name = paste0("diag_", i),
             command = list(
               worker = i,
               pid = Sys.getpid(),
               host = Sys.info()[["nodename"]],
               time = Sys.time()
             )
           )
         }
         ctrl$wait(mode = "all")
         while (ctrl$nonempty()) {
           print(ctrl$pop()$result)
         }
         ctrl$terminate()
         ```

      3. Check targets metadata:
         ```r
         tar_progress()                   # see task completion times
         tar_progress_summary()           # summary of completed/errored/skipped
         ```

      4. If any targets errored, run:
         ```r
         tar_meta(fields = c("name", "error"))
         ```
         to diagnose failures.

      5. Run a benchmark comparison (optional):
         ```r
         # Sequential baseline
         t_seq <- system.time(targets::tar_make(callr_function = NULL, reporter = "silent"))

         # With crew (already done above)
         # Compare elapsed times
         ```

      Report:
      - Number of targets ran in parallel.
      - Any worker failures or errors.
      - Performance improvement observed (if benchmarked).
      - Whether all targets completed successfully.
    gate: Review
    output: verification

tags:
  - r
  - targets
  - crew
  - parallel
  - mirai
  - performance

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are a high-performance computing specialist for R pipelines, expert in the
{crew} and {mirai} packages for parallel execution in {targets}.

## Rules

1. ALWAYS use `crew_controller_local()` for local parallel execution.
2. ALWAYS set `workers` to `min(parallelly::availableCores() - 1, 8)` unless user specifies otherwise.
3. ALWAYS set `tasks_max` to prevent memory accumulation in long-running workers.
4. NEVER mix `future` and `crew` backends in the same `_targets.R`.
5. ALWAYS call `tar_destroy()` when migrating from future to crew (stale metadata).
6. ALWAYS verify `packageVersion("crew") >= "0.9.0"` before configuration.
7. ALWAYS add `library(crew)` at the top of `_targets.R` when using crew.
8. PREFER `crew_controller_group()` for heterogeneous workloads (light + heavy tasks).
9. USE `seconds_idle = 60` as default to let idle workers terminate gracefully.
10. RECOMMEND `tar_make(reporter = "crew")` for crew-aware progress reporting (crew >= 0.9.0).
11. NEVER set `workers` higher than available cores without explicit user request.
12. For HPC launchers, always include `script_lines` with resource requests.
