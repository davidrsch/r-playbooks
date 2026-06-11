---
name: r-ml-init
version: 1.0.0
context-mode: Fork
description: "Scaffold a complete ML project with tidymodels: project structure, feature engineering with recipes, train/validate/test split strategy, cross-validation setup, vetiver deployment config, and CI/CD for model training"
trigger: both
trigger-patterns:
  - "ml project *"
  - "init ml *"
  - "scaffold ml *"
  - "machine learning project *"
  - "tidymodels project *"
  - "new ml project *"
  - "ml init *"
  - "start ml project *"
argument-hint: "--name <project> [--task regression|classification] [--engine xgboost|ranger|glmnet|auto] [--target <col>] [--data <path>]"
parameters:
  name:
    type: String
    required: true
    hint: "Project name (snake_case)"
  task:
    type: String
    required: false
    default: "regression"
    enum: ["regression", "classification"]
    hint: "ML task type: regression (numeric target) or classification (categorical target)"
  engine:
    type: String
    required: false
    default: "auto"
    enum: ["xgboost", "ranger", "glmnet", "auto"]
    hint: "Default modeling engine: xgboost, ranger (random forest), glmnet (regularized regression), or auto (agent selects)"
  target:
    type: String
    required: false
    hint: "Name of target/prediction column in the dataset"
  data:
    type: String
    required: false
    hint: "Path to training data (CSV, Parquet, or database table)"
steps:
  - id: scaffold-project
    inline-prompt: |
      Create the ML project directory structure.

      Project name: {{params.name}}
      Task: {{params.task}}
      Engine: {{params.engine}}

      1. **Create the project structure:**
         ```
         {{params.name}}/
         ├── R/
         │   ├── preprocess.R       # Feature engineering (recipes)
         │   ├── model.R             # Model specification (parsnip)
         │   ├── train.R             # Training workflow
         │   ├── evaluate.R          # Model evaluation
         │   ├── explain.R           # Model explainability
         │   └── utils.R             # Shared utilities
         ├── data/
         │   ├── raw/                # Raw data (never modified)
         │   ├── processed/          # Cleaned/feature-engineered data
         │   └── predictions/        # Model outputs
         ├── models/                 # Saved model objects (.rds)
         ├── reports/                # Quarto analysis reports
         ├── tests/
         │   └── testthat/
         │       ├── test-preprocess.R
         │       ├── test-model.R
         │       └── test-train.R
         ├── DESCRIPTION            # Optional: make it an R package
         ├── renv.lock              # Dependency lock
         ├── _targets.R             # Optional: targets pipeline
         └── README.md
         ```

      2. **Initialize with renv:**
         ```r
         renv::init(project = "{{params.name}}")
         ```

      3. **Install core ML dependencies:**
         ```r
         install.packages(c(
           "tidymodels", "tidyverse", "vip", "vetiver", "pins",
           "skimr", "GGally", "gt", "patchwork"
         ))
         # Engine-specific:
         # "xgboost", "ranger", "glmnet", "brulee", "LiblineaR"
         ```

      4. **Create `R/preprocess.R` — feature engineering with recipes:**
         ```r
         library(recipes)
         library(embed)  # for target encoding
         library(textrecipes)  # if NLP features

         #' Build preprocessing recipe for {{params.name}}
         #' @param data Training data frame
         #' @return A recipe object
         build_recipe <- function(data) {
           recipe({{params.target}} ~ ., data = data) |>
             # Handle missing values
             step_impute_median(all_numeric_predictors()) |>
             step_impute_mode(all_nominal_predictors()) |>
             # Encode categorical variables
             step_dummy(all_nominal_predictors(), one_hot = TRUE) |>
             # Remove near-zero variance predictors
             step_nzv(all_predictors()) |>
             # Remove highly correlated predictors
             step_corr(all_numeric_predictors(), threshold = 0.9) |>
             # Normalize numeric predictors
             step_normalize(all_numeric_predictors())
             # Add task-specific steps:
             # Regression: step_log(target, offset = 1) if skewed
             # Classification: step_smote(target) if imbalanced
         }
         ```

      Report: project scaffolded with dependencies installed.
    gate: Confirm
    output: project_structure

  - id: configure-model
    requires: [scaffold-project]
    inline-prompt: |
      Configure the model specification and training workflow.

      Task: {{params.task}}
      Engine: {{params.engine}}

      1. **Create `R/model.R` — model specification:**
         ```r
         library(parsnip)
         library(workflows)

         #' Build model specification for {{params.name}}
         #' @param engine Modeling engine ({{params.engine}})
         #' @return A model specification
         build_model <- function(engine = "{{params.engine}}") {
           if ({{params.task}} == "regression") {
             spec <- rand_forest(mtry = tune(), trees = tune(), min_n = tune()) |>
               set_engine(engine) |>
               set_mode("regression")
           } else {
             spec <- rand_forest(mtry = tune(), trees = tune(), min_n = tune()) |>
               set_engine(engine) |>
               set_mode("classification")
           }

           # For linear models:
           # spec <- linear_reg(penalty = tune(), mixture = tune()) |>
           #   set_engine("glmnet") |>
           #   set_mode("<mode>")

           # For boosted trees:
           # spec <- boost_tree(
           #   trees = tune(), tree_depth = tune(),
           #   learn_rate = tune(), min_n = tune()
           # ) |>
           #   set_engine("xgboost") |>
           #   set_mode("<mode>")

           spec
         }
         ```

      2. **Create `R/train.R` — training workflow:**
         ```r
         library(tidymodels)
         library(workflows)
         library(tune)
         library(yardstick)

         #' Train model for {{params.name}}
         #' @param data Training data
         #' @param recipe Preprocessing recipe
         #' @param model Model specification
         #' @return Trained workflow
         train_model <- function(data, recipe, model) {
           set.seed(123)

           # 1. Split data
           split <- initial_split(data, prop = 0.8, strata = {{params.target}})
           train_data <- training(split)
           test_data  <- testing(split)

           # 2. Create cross-validation folds
           folds <- vfold_cv(train_data, v = 5, strata = {{params.target}})
           # For time series: folds <- rolling_origin(train_data, initial = ..., assess = ...)

           # 3. Build workflow
           wf <- workflow() |>
             add_recipe(recipe) |>
             add_model(model)

           # 4. Tune hyperparameters
           # Use Bayesian optimization for expensive models, grid search for fast ones
           tune_results <- wf |>
             tune_grid(
               resamples = folds,
               grid = 20,       # number of hyperparameter combinations
               metrics = metric_set(
                 # Regression: rmse, mae, rsq   |   Classification: accuracy, roc_auc, f_meas
                 # Select based on task type: {{params.task}}
                 <choose_metrics_for_{{params.task}}>
               ),
               control = control_grid(save_pred = TRUE, parallel_over = "resamples")
             )

           # 5. Select best model
           best_params <- tune_results |>
             # For regression: select_best(metric = "rmse")
            # For classification: select_best(metric = "roc_auc")
            select_best(metric = <primary_metric_for_{{params.task}}>)

           # 6. Finalize workflow with best parameters
           final_wf <- wf |> finalize_workflow(best_params)
           final_fit <- final_wf |> fit(train_data)

           # 7. Evaluate on test set
           predictions <- final_fit |>
             predict(test_data) |>
             bind_cols(test_data)

           test_metrics <- predictions |>
             metrics(truth = {{params.target}}, estimate = .pred)

           list(
             workflow = final_wf,
             fit = final_fit,
             tune_results = tune_results,
             test_metrics = test_metrics,
             split = split
           )
         }
         ```

      3. **Select metrics and best-model criteria** based on task type
         ({{params.task}}: regression uses rmse/mae/rsq; classification uses
         accuracy/roc_auc/f_meas). Replace placeholder metric names above.

      Report: model specification and training workflow created.
    gate: Review
    output: model_config

  - id: set-up-vetiver-deployment
    requires: [configure-model]
    inline-prompt: |
      Configure vetiver for model versioning and deployment.

      1. **Create `R/deploy.R` — vetiver deployment setup:**
         ```r
         library(vetiver)
         library(pins)

         #' Deploy trained model with vetiver
         #' @param model_result Output from train_model()
         #' @param board pins board for model versioning
         deploy_model <- function(model_result, board = pins::board_folder("models")) {
           # Create vetiver model
           v <- vetiver_model(
             model_result$fit,
             model_name = "{{params.name}}",
             description = "<model_description>",
             metadata = list(
               task = "{{params.task}}",
               engine = "{{params.engine}}",
               target = "{{params.target}}",
               trained_at = Sys.time(),
               metrics = model_result$test_metrics
             )
           )

           # Pin the model for versioning
           vetiver_pin_write(board, v)

           # Generate Plumber API endpoint
           vetiver_write_plumber(board, "{{params.name}}", plumber_file = "plumber.R")

           # Generate Dockerfile
           vetiver_write_docker(v)

           v
         }
         ```

      2. **Set up CI for automated training** (`.github/workflows/train-model.yaml`):
         ```yaml
         name: Train and Deploy Model
         on:
           schedule:
             - cron: '0 3 * * 1'  # Weekly on Monday
           workflow_dispatch:

         jobs:
           train:
             runs-on: ubuntu-latest
             steps:
               - uses: actions/checkout@v4
               - uses: r-lib/actions/setup-r@v2
               - uses: r-lib/actions/setup-renv@v2
               - name: Train model
                 run: Rscript -e 'source("R/train.R"); source("R/deploy.R")'
               - name: Commit updated model
                 run: |
                   git add models/
                   git commit -m "chore: update model — $(date +%Y-%m-%d)" || true
                   git push
         ```

      Report: vetiver deployment configured, model pin board initialized.
    gate: Review
    output: deployment_config

  - id: create-ml-tests
    requires: [configure-model]
    inline-prompt: |
      Create tests for the ML pipeline.

      1. **`tests/testthat/test-preprocess.R`:**
         ```r
         test_that("recipe handles missing values", {
           data <- tibble::tibble(
             x = c(1, 2, NA, 4, 5),
             y = c("a", "b", "a", NA, "b"),
             target = c(10, 20, 30, 40, 50)
           )
           recipe <- build_recipe(data)
           baked <- recipe |> prep() |> bake(new_data = NULL)
           expect_false(any(is.na(baked)))
         })

         test_that("recipe preserves row count", {
           data <- mtcars
           recipe <- build_recipe(data)
           baked <- recipe |> prep() |> bake(new_data = NULL)
           expect_equal(nrow(baked), nrow(data))
         })

         test_that("recipe removes near-zero variance predictors", {
           data <- tibble::tibble(
             constant = rep(1, 100),
             varying = rnorm(100),
             target = rnorm(100)
           )
           recipe <- build_recipe(data)
           baked <- recipe |> prep() |> bake(new_data = NULL)
           expect_false("constant" %in% names(baked))
         })
         ```

      2. **`tests/testthat/test-model.R`:**
         ```r
         test_that("model specification has correct mode", {
           model <- build_model()
           expect_equal(model$mode, "{{params.task}}")
         })

         test_that("model trains without error on small data", {
           data <- mtcars
           recipe <- build_recipe(data)
           model <- build_model()
           result <- train_model(data, recipe, model)
           expect_s3_class(result$fit, "workflow")
         })

         test_that("predictions are within valid range", {
           data <- mtcars
           recipe <- build_recipe(data)
           model <- build_model()
           result <- train_model(data, recipe, model)
           preds <- predict(result$fit, head(data))
           # All predictions should be finite
           expect_true(all(is.finite(preds$.pred)))
         })
         ```

      3. **`tests/testthat/test-train.R`:**
         ```r
         test_that("train/test split preserves data", {
           data <- mtcars
           split <- initial_split(data, prop = 0.8)
           expect_equal(nrow(training(split)) + nrow(testing(split)), nrow(data))
         })

         test_that("cross-validation creates expected folds", {
           data <- mtcars
           folds <- vfold_cv(data, v = 5)
           expect_equal(nrow(folds), 5)
         })
         ```

      Run tests:
      ```r
      devtools::test()
      ```

      Report: ML tests created and passing.
    gate: Review
    output: ml_tests

tags:
  - r
  - ml
  - tidymodels
  - init
  - scaffold
  - vetiver

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER train on test data — always split BEFORE any preprocessing."
    severity: "error"
  - rule: "ALWAYS set a seed for reproducibility — ML workflows must be reproducible."
    severity: "error"
  - rule: "NEVER deploy a model without validation metrics — always report RMSE/accuracy on held-out test data."
    severity: "error"
  - rule: "ALWAYS version models with vetiver + pins — never save models with random filenames."
    severity: "warning"
  - rule: "Use stratified sampling for classification tasks — prevents class imbalance in splits."
    severity: "warning"
  - rule: "Preprocess WITHIN the recipe, not manually — the recipe encapsulates the full pipeline."
    severity: "warning"
---

You are an ML project init specialist. You scaffold production-ready machine
learning projects using the `tidymodels` ecosystem (Posit) with `vetiver` for
model deployment and `pins` for versioning.

## ML Project Philosophy

1. **RECIPE IS THE PIPELINE**: All preprocessing (imputation, encoding,
   normalization) lives inside a `recipes::recipe()`. Never preprocess manually
   outside the recipe — it creates train/serve skew.
2. **SPLIT BEFORE TOUCHING**: `initial_split()` before any data exploration.
   Test data is sacred — never look at it until final evaluation.
3. **VERSION EVERYTHING**: Models go in `pins`. Code goes in git. Data goes
   in DVC or a data lake. Nothing is "the model" — the model is the code +
   data + hyperparameters that produced it.
4. **REPRODUCIBLE BY DEFAULT**: `set.seed()`, `renv.lock`, pinned training data.
   Anyone should be able to reproduce your model exactly.
5. **DEPLOY FROM DAY ONE**: Set up `vetiver` before the first training run.
   Deploying a dummy model is better than deploying nothing — it validates
   the deployment pipeline.

## Project Structure Rationale

| Directory | Purpose |
|-----------|---------|
| `R/preprocess.R` | Feature engineering recipe — one function, tested |
| `R/model.R` | Model specification — one function per model type |
| `R/train.R` | Training workflow — split → tune → fit → evaluate |
| `R/evaluate.R` | Model evaluation on test set, calibration, diagnostics |
| `R/explain.R` | DALEX/vip explanations, SHAP values, PDPs |
| `data/raw/` | Original data — never modified, gitignored |
| `data/processed/` | Post-recipe data — for debugging the pipeline |
| `models/` | Pinned vetiver models — versioned |
| `reports/` | Quarto reports — EDA, model comparison, final report |

## Where to Go Next

After scaffolding with this playbook, continue with:

| Stage | Playbook |
|-------|----------|
| Train your first model | `/run_playbook r-tidymodels-workflow --outcome <target> --task {{params.task}}` |
| Tune hyperparameters | `/run_playbook r-tidymodels-tune` |
| Validate and explain | `/run_playbook r-ml-validate --model <model_path> --explainer all` |
| Deploy as API | `/run_playbook r-vetiver-deploy` |
| Monitor in production | `/run_playbook r-model-monitor` |
