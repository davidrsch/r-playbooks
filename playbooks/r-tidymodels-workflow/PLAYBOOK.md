---
name: r-tidymodels-workflow
version: 1.0.0
context-mode: Fork
description: "Build a complete tidymodels ML workflow: recipe, model spec, workflow object, train/test split, fit, and evaluation with yardstick metrics"
trigger: both
trigger-patterns:
  - "tidymodels *"
  - "machine learning *"
  - "ml workflow *"
  - "train model *"
  - "fit model *"
  - "classification *"
  - "regression *"
argument-hint: "--outcome <col> --task classification|regression [--model linear|rf|xgboost|logistic] [--data <path>]"
parameters:
  outcome:
    type: String
    required: true
    hint: "Name of the outcome/target column in the dataset"
  task:
    type: String
    required: true
    enum: ["classification", "regression"]
    hint: "Type of supervised ML task"
  model:
    type: String
    required: false
    default: "rf"
    enum: ["linear", "logistic", "rf", "xgboost", "svm"]
    hint: "Model type: linear/logistic regression, random forest, XGBoost, or SVM"
  data:
    type: String
    required: false
    hint: "Path to the dataset CSV/RDS, or name of a built-in dataset (e.g. 'mtcars', 'penguins')"
  test-split:
    type: Float
    required: false
    default: 0.2
    min: 0.1
    max: 0.4
    hint: "Proportion of data held out for testing (default: 0.2)"
  cv-folds:
    type: Integer
    required: false
    default: 5
    min: 3
    max: 10
    hint: "Number of cross-validation folds for resampling"
steps:
  - id: load-explore-data
    inline-prompt: |
      Load and explore the dataset to understand its structure.

      Data source: {{params.data}}
      Outcome column: {{params.outcome}}
      Task type: {{params.task}}

      1. Load the data:
         - If a file path: `data <- readr::read_csv("{{params.data}}")` or `readRDS("{{params.data}}")`
         - If a named dataset: `data <- {{params.data}}` (e.g., palmerpenguins::penguins)
         - If no data specified: ask the user to provide a dataset
      2. Run `dplyr::glimpse(data)` and `skimr::skim(data)`
      3. Check for:
         - Missing values per column
         - Class imbalance (for classification)
         - Numeric vs. categorical predictors
         - Near-zero variance columns
      4. Report:
         - Rows × columns
         - Outcome distribution (class counts or summary stats)
         - Top predictors by expected relevance
         - Issues to address in the recipe
    gate: Confirm
    output: data_summary

  - id: train-test-split
    requires: [load-explore-data]
    inline-prompt: |
      Create a stratified train/test split.

      Outcome: {{params.outcome}}
      Test proportion: {{params.test-split}}

      ```r
      library(tidymodels)
      set.seed(42)

      split <- initial_split(data, prop = 1 - {{params.test-split}},
                             strata = {{params.outcome}})
      train <- training(split)
      test  <- testing(split)

      cat("Train rows:", nrow(train), "\nTest rows:", nrow(test), "\n")
      ```

      Report: train/test sizes and outcome distribution in each set.
    output: split_info

  - id: build-recipe
    requires: [train-test-split]
    inline-prompt: |
      Build a preprocessing recipe tailored to the data profile.

      Data summary: {{state.data_summary}}
      Outcome: {{params.outcome}}
      Task: {{params.task}}

      Start from this skeleton and add appropriate steps:
      ```r
      rec <- recipe({{params.outcome}} ~ ., data = train) |>
        step_impute_median(all_numeric_predictors()) |>
        step_impute_mode(all_nominal_predictors()) |>
        step_novel(all_nominal_predictors()) |>
        step_dummy(all_nominal_predictors(), one_hot = TRUE) |>
        step_zv(all_predictors()) |>
        step_normalize(all_numeric_predictors())
      ```

      Add extra steps based on data profile:
      - High cardinality categoricals: `step_other()` before `step_dummy()`
      - Date columns: `step_date()`, `step_rm()`
      - Skewed numerics (regression): `step_log()` or `step_YeoJohnson()`
      - Class imbalance (classification): `step_smote()` from themis package
      - Highly correlated features: `step_corr(threshold = 0.9)`

      Run `prep(rec) |> juice() |> dplyr::glimpse()` to verify the baked data.

      Report: final recipe steps and baked column count.
    gate: Review
    output: recipe_code

  - id: specify-model
    requires: [build-recipe]
    inline-prompt: |
      Specify the model engine based on the requested model type.

      Model: {{params.model}}
      Task: {{params.task}}

      Choose the appropriate parsnip spec:

      **linear** (regression only):
      ```r
      spec <- linear_reg() |> set_engine("lm")
      ```

      **logistic** (classification only):
      ```r
      spec <- logistic_reg() |> set_engine("glm")
      ```

      **rf** (random forest — works for both):
      ```r
      spec <- rand_forest(mtry = tune(), trees = 500, min_n = tune()) |>
        set_engine("ranger", importance = "impurity") |>
        set_mode("{{params.task}}")
      ```

      **xgboost**:
      ```r
      spec <- boost_tree(trees = tune(), learn_rate = tune(), tree_depth = tune()) |>
        set_engine("xgboost") |>
        set_mode("{{params.task}}")
      ```

      **svm**:
      ```r
      spec <- svm_rbf(cost = tune(), rbf_sigma = tune()) |>
        set_engine("kernlab") |>
        set_mode("{{params.task}}")
      ```

      Ensure required packages are installed via `pak::pak(c("ranger", "xgboost", ...))`.

      Report: model spec and tunable parameters.
    output: model_spec

  - id: build-workflow
    requires: [specify-model]
    inline-prompt: |
      Combine the recipe and model into a workflow object.

      Recipe: {{state.recipe_code}}
      Model spec: {{state.model_spec}}

      ```r
      wf <- workflow() |>
        add_recipe(rec) |>
        add_model(spec)

      print(wf)
      ```

      Report: workflow summary showing preprocessor and model layers.
    output: workflow_obj

  - id: cross-validate
    requires: [build-workflow]
    inline-prompt: |
      Set up cross-validation resamples and tune hyperparameters (if any).

      CV folds: {{params.cv-folds}}
      Task: {{params.task}}

      ```r
      set.seed(42)
      folds <- vfold_cv(train, v = {{params.cv-folds}}, strata = {{params.outcome}})
      ```

      If the model has tunable parameters, run a grid search:
      ```r
      grid <- grid_latin_hypercube(extract_parameter_set_dials(wf), size = 20)

      ctrl <- control_resamples(save_pred = TRUE, verbose = TRUE)

      tune_res <- tune_grid(
        wf,
        resamples = folds,
        grid = grid,
        metrics = if ("{{params.task}}" == "classification")
          metric_set(roc_auc, accuracy, f_meas)
        else
          metric_set(rmse, rsq, mae),
        control = ctrl
      )

      autoplot(tune_res)
      show_best(tune_res, metric = if ("{{params.task}}" == "classification") "roc_auc" else "rmse")
      ```

      If no tunable parameters, use `fit_resamples()` instead of `tune_grid()`.

      Report: best hyperparameter set and CV metric summary.
    gate: Review
    output: cv_results

  - id: finalise-fit
    requires: [cross-validate]
    inline-prompt: |
      Finalise the workflow with the best parameters and fit on the full training set.

      CV results: {{state.cv_results}}

      ```r
      best_params <- select_best(tune_res,
        metric = if ("{{params.task}}" == "classification") "roc_auc" else "rmse")

      final_wf <- finalize_workflow(wf, best_params)

      final_fit <- last_fit(final_wf, split)
      ```

      Report: finalised workflow and training set fit summary.
    output: final_fit

  - id: evaluate
    requires: [finalise-fit]
    inline-prompt: |
      Evaluate the final model on the held-out test set.

      Final fit: {{state.final_fit}}
      Task: {{params.task}}

      ```r
      # Test set metrics
      collect_metrics(final_fit)

      # Predictions
      preds <- collect_predictions(final_fit)
      ```

      For classification, also produce:
      ```r
      conf_mat(preds, truth = {{params.outcome}}, estimate = .pred_class)
      roc_curve(preds, {{params.outcome}}, .pred_<positive_class>) |> autoplot()
      ```

      For regression:
      ```r
      ggplot(preds, aes(x = {{params.outcome}}, y = .pred)) +
        geom_point(alpha = 0.4) +
        geom_abline(lty = 2) +
        coord_obs_pred() +
        labs(title = "Observed vs. Predicted")
      ```

      Variable importance (if engine supports it):
      ```r
      extract_fit_parsnip(final_fit) |>
        vip::vip(num_features = 15)
      ```

      Report full metrics table and interpretation.
    gate: Review
    output: eval_report

  - id: save-model
    requires: [evaluate]
    inline-prompt: |
      Save the fitted workflow for later use or deployment.

      ```r
      # Save as RDS (portable, R-only)
      saveRDS(extract_workflow(final_fit), "model.rds")

      # Or use butcher to trim memory (removes training data from model object)
      # install.packages("butcher")
      butchered <- butcher::butcher(extract_workflow(final_fit))
      saveRDS(butchered, "model_butchered.rds")

      # For vetiver deployment, use the r-vetiver-deploy playbook next
      ```

      Report: file size of saved model and reload verification:
      ```r
      m <- readRDS("model.rds")
      predict(m, new_data = test[1:3, ])
      ```
    output: model_path

tags:
  - r
  - ml
  - tidymodels
  - modeling
  - classification
  - regression

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER use base R predict() directly on a workflow — always use predict(workflow, new_data = ...)."
    severity: "error"
  - rule: "ALWAYS set.seed() before splits and resampling for reproducibility."
    severity: "error"
  - rule: "NEVER evaluate on the test set more than once — use CV for model selection."
    severity: "error"
  - rule: "ALWAYS use last_fit() to fit on the full training set and evaluate on the test set in one step."
    severity: "warning"
  - rule: "NEVER impute the outcome column."
    severity: "error"
  - rule: "Use step_novel() before step_dummy() to handle unseen factor levels at prediction time."
    severity: "warning"
---

You are an R machine learning engineer using the tidymodels framework.
You follow tidy principles: consistent APIs, reproducible splits, and
pipeline-based preprocessing that prevents data leakage.

## Rules

1. ALL preprocessing goes in the recipe — never transform data outside it.
2. ALWAYS use `last_fit()` for the final train-and-evaluate step to prevent
   accidental test-set leakage during model selection.
3. Use `tune()` placeholders for any hyperparameter that might benefit
   from optimization — even if the default is reasonable.
4. Use `set.seed()` before every random operation.
5. For classification, default metrics are `roc_auc` + `accuracy` + `f_meas`.
   For regression: `rmse` + `rsq` + `mae`.
6. Prefer `ranger` for random forests (faster than `randomForest`).
7. Prefer `xgboost` for gradient boosting (faster than `gbm`).
8. Use `vip::vip()` for variable importance after fitting.
9. Use `butcher::butcher()` to strip large training objects before saving.
10. For deployment, pipe the saved workflow into the `r-vetiver-deploy` playbook.
