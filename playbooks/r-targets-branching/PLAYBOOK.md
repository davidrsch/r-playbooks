---
name: r-targets-branching
version: 1.0.0
context-mode: Fork
description: Add static branching (tar_map) or dynamic branching (tar_rep, pattern=map/cross) to a targets pipeline
trigger: both
trigger-patterns:
  - "add branching *"
  - "static branching *"
  - "dynamic branching *"
  - "tar_map *"
  - "tar_rep *"
  - "branching targets *"
argument-hint: "--strategy static|dynamic [--mapping <field1,field2>] [--replications <n>] [--batches <n>]"
parameters:
  strategy:
    type: String
    required: true
    enum: ["static", "dynamic"]
    hint: "Branching strategy: static (tar_map) or dynamic (pattern = map/cross)"
  target:
    type: String
    required: false
    hint: "Target to branch (e.g., clean_data, fit_model). If omitted, analyze pipeline to find candidates."
  mapping:
    type: Array
    required: false
    default: []
    hint: "For static branching: fields to map as parameter columns (comma-separated). For dynamic: upstream target names."
  pattern:
    type: String
    required: false
    enum: ["map", "cross"]
    default: "map"
    hint: "Dynamic branching pattern: map (one branch per element) or cross (all combinations)"
  replications:
    type: Number
    required: false
    default: 1
    hint: "Number of Monte Carlo replications for tar_rep()"
  batches:
    type: Number
    required: false
    default: 1
    hint: "Number of batches for tar_rep() (splits replications across batches)"
  workers:
    type: Number
    required: false
    default: 4
    hint: "Number of parallel workers for crew backend"
steps:
  - id: analyze-pipeline
    inline-prompt: |
      Analyze the existing `_targets.R` pipeline to understand current targets and identify branching opportunities:

      1. Read the full `_targets.R` file to understand the pipeline structure.
      2. Run: `tar_manifest(callr_function = NULL)` to list all targets with their commands and patterns.
      3. Run: `tar_visnetwork(callr_function = NULL)` to see the DAG (if available).
      4. Identify targets that could benefit from branching:
         - Targets with repetitive parameter logic (static branching candidates).
         - Targets operating on multi-element inputs where each element should be processed independently (dynamic branching candidates).
         - Targets doing simulation/replication (tar_rep candidates).
      5. If a specific target {{params.target}} was provided, focus analysis on that target.
         Otherwise, list all branching candidates ranked by impact.
      6. Report: pipeline structure summary, identified branching opportunities, target dependencies.
    output: pipeline_context

  - id: design-branching
    requires: [analyze-pipeline]
    inline-prompt: |
      Design the branching strategy for the targets pipeline.

      Pipeline context: {{state.pipeline_context}}
      Strategy: {{params.strategy}}
      Pattern: {{params.pattern}}
      Replications: {{params.replications}}

      ## Static Branching (tar_map)
      Use when: You know the parameter combinations ahead of time and want explicit target names.

      Design pattern:
      ```r
      library(tarchetypes)

      values <- tibble::tibble(
        field1 = c(...),
        field2 = c(...)
      )

      tar_map(
        values = values,
        names = tidyselect::any_of(c("field1", "field2")),
        tar_target(result, do_work(data, field1, field2))
      )
      ```

      ## Dynamic Branching (pattern = map / cross)
      Use when: The number of branches is determined at runtime by upstream target output.

      Design pattern:
      ```r
      tar_target(
        name = branched_results,
        command = process_one(data, element),
        pattern = map(element)   # one branch per element of 'element'
      )

      tar_target(
        name = combined_results,
        command = process_pair(data, x, y),
        pattern = cross(x, y)    # all combinations of x and y
      )
      ```

      ## Monte Carlo Replication (tar_rep)
      Use when: You need to run the same computation N times with different random seeds.

      Design pattern:
      ```r
      tar_rep(
        name = simulation_results,
        command = run_simulation(n = 100),
        batches = {{params.batches}},
        reps = {{params.replications}}
      )
      ```

      Report the chosen design with:
      1. Branching approach and rationale.
      2. New/modified target definitions.
      3. Parameter mapping (static) or upstream dependency (dynamic).
      4. Expected number of branches.
      5. Changes needed in `_targets.R`.
    gate: Confirm
    output: branching_design

  - id: implement-branching
    requires: [design-branching]
    inline-prompt: |
      Implement the branching strategy in `_targets.R` based on the approved design.

      Design: {{state.branching_design}}

      Implementation steps:
      1. Ensure `library(tarchetypes)` is loaded at the top of `_targets.R`.
         If not present, add it.
      2. For **static branching**:
         - Create the `values` tibble with parameter combinations.
         - Replace the original `tar_target()` with `tar_map()`.
         - Use `names =` to control how branch names are generated from parameter values.
         - Add `tar_combine()` if downstream targets need to aggregate branches.
      3. For **dynamic branching**:
         - Ensure the upstream target produces an iterable object (list, vector).
         - Add `pattern = map(upstream_target)` or `pattern = cross(x, y)` to the target.
         - Add `iteration = "list"` if the branched target returns non-atomic objects.
      4. For **tar_rep**:
         - Wrap the simulation command in `tar_rep()` with `batches` and `reps`.
         - Use `tar_rep2()` if the simulation depends on upstream targets.
      5. Run: `tar_manifest(callr_function = NULL)` to validate the new pipeline structure.
      6. Report: the modified `_targets.R` sections, new target count, and manifest validation result.
    gate: Approve
    output: implementation

  - id: verify-branching
    requires: [implement-branching]
    inline-prompt: |
      Verify that the branching structure works correctly:

      1. Run: `tar_manifest(callr_function = NULL)` to confirm all branched targets appear.
      2. Run: `tar_visnetwork(callr_function = NULL, targets_only = TRUE)` to visualize and save the branching DAG.
         Check that:
         - Branches fan out and combine correctly.
         - No orphaned branches.
         - No circular dependencies.
      3. Run: `tar_outdated(callr_function = NULL)` to check which targets need to run.
      4. If using crew for parallel execution, verify controller configuration:
         ```r
         tar_option_set(controller = crew_controller_local(workers = {{params.workers}}, tasks_max = 100, seconds_idle = 60))
         ```
      5. Run a small subset to validate: `tar_make(names = <a few branch targets>)`.
      6. Report:
         - Total branches created.
         - DAG visualization result (cycles? orphans?).
         - Parallel backend status.
         - Any warnings or errors from manifest check.
    gate: Review
    output: verification

tags:
  - r
  - targets
  - branching
  - pipeline
  - tarchetypes

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER edit the _targets/ store manually."
    severity: "error"
  - rule: "NEVER use setwd() in pipeline functions — use here::here()."
    severity: "error"
  - rule: "ALWAYS test pipeline functions independently before running the pipeline."
    severity: "warning"
  - rule: "Use memory = 'transient' for large pipelines."
    severity: "warning"
---

You are an R pipeline engineer specializing in the {targets} ecosystem with deep
knowledge of {tarchetypes} for branching patterns.

## Rules

1. ALWAYS load `library(tarchetypes)` in `_targets.R` when using any branching.
2. ALWAYS use `tar_map()` for static branching (known parameter grid ahead of time).
3. ALWAYS use `pattern = map()` for 1:1 dynamic branching, `pattern = cross()` for all combinations.
4. ALWAYS use `tar_rep()` (or `tar_rep2()`) for Monte Carlo replication: NEVER write manual for-loops.
5. PREFER static branching when parameter combinations are known and enumerable.
6. USE dynamic branching when branches depend on upstream target output size.
7. ALWAYS set `iteration = "list"` when a dynamically-branched target returns non-data-frame objects.
8. ALWAYS use `tar_combine()` to aggregate static branch results for downstream targets.
9. ALWAYS run `tar_manifest()` and `tar_visnetwork()` after modifying `_targets.R`.
10. RECOMMEND crew parallel backend for large branching pipelines (see r-targets-crew playbook).
11. PREFER `format = "qs"` for branched targets to improve serialization speed and reduce storage size.
12. NEVER create targets with `tar_target_raw()` for branching: use the DSL.
13. When using `tar_rep()`, set batches > 1 for resilience to worker failures.
14. Use `tar_age()` to invalidate targets based on time thresholds (e.g., re-fetch data older than 24h) ;
    ensures freshness without manual `tar_invalidate()`.
