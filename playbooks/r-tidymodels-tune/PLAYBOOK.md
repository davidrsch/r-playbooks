---
name: r-tidymodels-tune
version: 1.0.0
context-mode: Fork
description: "Hyperparameter tuning for an existing tidymodels workflow: Bayesian optimisation or racing methods, with parallel execution via {finetune} or {tune}"
trigger: both
trigger-patterns:
  - "tune *"
  - "hyperparameter *"
  - "optimize model *"
  - "bayesian tuning *"
  - "tidymodels tune *"
argument-hint: "--workflow <obj> --metric roc_auc|rmse [--method grid|bayes|racing] [--budget <n>]"
parameters:
  metric:
    type: String
    required: true
    enum: ["roc_auc", "accuracy", "rmse", "rsq", "mae", "f_meas"]
    hint: "Primary metric to optimise"
  method:
    type: String
    required: false
    default: "bayes"
    enum: ["grid", "bayes", "racing"]
    hint: "Tuning strategy: Latin hypercube grid, Bayesian optimisation, or ANOVA racing"
  budget:
    type: Integer
    required: false
    default: 30
    min: 10
    max: 200
    hint: "Number of candidate models to evaluate (grid size or Bayesian iterations)"
  cv-folds:
    type: Integer
    required: false
    default: 5
    min: 3
    max: 10
    hint: "Number of cross-validation folds"
  parallel:
    type: Boolean
    required: false
    default: false
    hint: "Enable parallel execution via {future} / {doFuture}"
steps:
  - id: inspect-workflow
    inline-prompt: |
      Inspect the existing tidymodels workflow and identify tunable parameters.

      1. Load the workflow object (look for `wf`, `workflow_obj`, or ask the user for the variable name).
      2. Run:
         ```r
         library(tidymodels)
         extract_parameter_set_dials(wf)
         ```
      3. List all tunable parameters with their ranges.
      4. Check current recipe and model engine.
      5. If no tunable parameters found (`tune()` placeholders missing), report which
         parameters can be added: e.g., `mtry = tune()`, `min_n = tune()`, `learn_rate = tune()`.

      Report: workflow summary and list of tunable parameters.
    gate: Confirm
    output: tune_params

  - id: setup-resamples
    requires: [inspect-workflow]
    inline-prompt: |
      Create cross-validation resamples for tuning.

      Folds: {{params.cv-folds}}
      Metric: {{params.metric}}

      ```r
      set.seed(42)
      # Detect outcome column from workflow
      outcome_var <- wf |> extract_preprocessor() |> rlang::f_lhs() |> as.character()
      task_mode   <- wf |> extract_spec_parsnip() |> purrr::pluck("mode")

      folds <- vfold_cv(train, v = {{params.cv-folds}}, strata = outcome_var)

      metrics <- if (task_mode == "classification")
        metric_set(roc_auc, accuracy, f_meas)
      else
        metric_set(rmse, rsq, mae)
      ```

      Report: resample plan and metric set.
    output: resamples

  - id: setup-parallel
    requires: [setup-resamples]
    inline-prompt: |
      If parallel is true (value: {{params.parallel}}):
      Set up parallel execution via {future}.

      ```r
      library(future)
      library(doFuture)
      plan(multisession, workers = parallel::detectCores() - 1)
      registerDoFuture()
      cat("Parallel workers:", nbrOfWorkers(), "\n")
      ```

      If parallel is false: skip.
      Report: parallel setup status.
    output: parallel_status

  - id: run-tuning
    requires: [setup-parallel]
    inline-prompt: |
      Run hyperparameter tuning using method: {{params.method}}.

      Tunable parameters: {{state.tune_params}}
      Budget: {{params.budget}}

      **Method: grid** (Latin hypercube):
      ```r
      grid <- grid_latin_hypercube(
        extract_parameter_set_dials(wf),
        size = {{params.budget}}
      )
      ctrl <- control_grid(save_pred = TRUE, verbose = TRUE, allow_par = {{params.parallel}})

      tune_res <- tune_grid(wf, resamples = folds, grid = grid,
                            metrics = metrics, control = ctrl)
      ```

      **Method: bayes** (Bayesian optimisation via {tune}):
      ```r
      ctrl <- control_bayes(save_pred = TRUE, verbose = TRUE, no_improve = 10,
                            allow_par = {{params.parallel}})

      tune_res <- tune_bayes(wf, resamples = folds,
                             iter = {{params.budget}},
                             metrics = metrics,
                             initial = 8,
                             control = ctrl)
      ```

      **Method: racing** (ANOVA racing via {finetune}):
      ```r
      library(finetune)
      ctrl <- control_race(save_pred = TRUE, verbose_elim = TRUE,
                           allow_par = {{params.parallel}})

      tune_res <- tune_race_anova(wf, resamples = folds,
                                  grid = {{params.budget}},
                                  metrics = metrics,
                                  control = ctrl)
      ```

      After tuning, run:
      ```r
      autoplot(tune_res)
      show_best(tune_res, metric = "{{params.metric}}", n = 5)
      ```

      Report: best 5 candidates and convergence status.
    gate: Review
    output: tune_results

  - id: select-finalise
    requires: [run-tuning]
    inline-prompt: |
      Select the best parameters and finalise the workflow.

      Tune results: {{state.tune_results}}
      Primary metric: {{params.metric}}

      ```r
      best <- select_best(tune_res, metric = "{{params.metric}}")
      cat("Best parameters:\n")
      print(best)

      final_wf <- finalize_workflow(wf, best)

      # Fit final model on full training data, evaluate on test set
      final_fit <- last_fit(final_wf, split)

      cat("\nTest set metrics:\n")
      collect_metrics(final_fit)
      ```

      Compare primary metric before and after tuning (if baseline exists).
      Save the finalised workflow:
      ```r
      saveRDS(extract_workflow(final_fit), "model_tuned.rds")
      ```

      Report: best parameters, test set metrics, and comparison to defaults.
    gate: Approve
    output: final_metrics

tags:
  - r
  - ml
  - tidymodels
  - tuning
  - hyperparameter
  - optimization

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER select hyperparameters based on test set performance — use CV only."
    severity: "error"
  - rule: "ALWAYS use last_fit() for the final evaluation on the test set."
    severity: "error"
  - rule: "NEVER tune more parameters than your budget can explore — prefer fewer, wider ranges."
    severity: "warning"
  - rule: "Use racing (finetune) for large grids (>50 candidates) to eliminate poor configs early."
    severity: "warning"
  - rule: "ALWAYS set.seed() before creating resamples and before tune_bayes()."
    severity: "error"
---

You are an R ML engineer specialising in hyperparameter optimisation with tidymodels.

## Rules

1. CV is for model selection; the test set is for final reporting only.
2. Bayesian optimisation (`tune_bayes`) is default because it is more efficient
   than grid search for > 2 tunable parameters.
3. Racing (`tune_race_anova`) is fastest for large grids with many candidates.
4. Use `no_improve = 10` in Bayesian control to stop early if no improvement.
5. Always plot `autoplot(tune_res)` to visualise the tuning landscape.
6. Use `select_by_one_std_err()` as an alternative to `select_best()` for
   simpler models with comparable performance.
7. Shut down parallel workers after tuning: `plan(sequential)`.
