---
name: r-ml-validate
version: 1.0.0
context-mode: Fork
description: "Validate and explain ML models: cross-validation diagnostics, residual analysis, calibration plots, DALEX model explanations, vip variable importance, shapviz SHAP values, fairness assessment, and model comparison framework"
trigger: both
trigger-patterns:
  - "validate model *"
  - "model validation *"
  - "explain model *"
  - "model explainability *"
  - "fairness check *"
  - "bias check *"
  - "dalex *"
  - "vip *"
  - "shap *"
  - "model diagnostics *"
argument-hint: "--model <path|vetiver> [--explainer dalex|vip|shap|all] [--fairness true|false] [--compare <model2>]"
parameters:
  model:
    type: String
    required: true
    hint: "Path to trained model (.rds), vetiver pin name, or workflow object name"
  explainer:
    type: String
    required: false
    default: "all"
    enum: ["dalex", "vip", "shap", "all"]
    hint: "Explainability method: DALEX (comprehensive), vip (variable importance), shapviz (SHAP values), or all"
  fairness:
    type: Boolean
    required: false
    default: false
    hint: "Run fairness/bias assessment across protected attributes (gender, race, age, etc.)"
  compare:
    type: String
    required: false
    hint: "Path to second model for comparison (model selection framework)"
steps:
  - id: load-and-inspect-model
    inline-prompt: |
      Load the trained model and inspect its structure.

      Model: {{params.model}}

      1. **Load the model:**
         ```r
         # If a file path:
         fit <- readRDS("{{params.model}}")

         # If a vetiver pin:
         library(pins)
         board <- board_folder("models")
         v <- vetiver_pin_read(board, "{{params.model}}")
         fit <- v$model

         # If a workflow:
         # fit is already the workflow object
         ```

      2. **Inspect the model:**
         ```r
         # Model type and engine
         fit$spec$engine
         fit$spec$mode

         # Features used
         fit$pre$mold$predictors |> names()

         # Training metrics (if available)
         fit$pre$mold$blueprint

         # For parsnip models, extract the underlying fit:
         fit |>
           workflows::extract_fit_parsnip() |>
           print()
         ```

      3. **Identify the training data:**
         - If the workflow was trained with a recipe, extract the prepped recipe
         - Load the original training data or a representative sample
         - The training data is needed for explainability methods

      Report: model structure, features, engine, and training context.
    gate: Confirm
    output: model_inspection

  - id: validate-performance
    requires: [load-and-inspect-model]
    inline-prompt: |
      Run comprehensive model validation and diagnostics.

      1. **Residual analysis** (regression):
         ```r
         library(yardstick)
         library(ggplot2)

         # Get predictions on test data
         predictions <- predict(fit, test_data) |>
           bind_cols(test_data)

         # Residual plot
         predictions |>
           mutate(residual = .pred - <target_column>) |>
           ggplot(aes(x = .pred, y = residual)) +
           geom_point(alpha = 0.5) +
           geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
           geom_smooth(se = TRUE) +
           labs(title = "Residuals vs Fitted", x = "Fitted", y = "Residual")

         # Q-Q plot for normality
         predictions |>
           ggplot(aes(sample = residual)) +
           geom_qq() + geom_qq_line(color = "red") +
           labs(title = "Normal Q-Q Plot")

         # Scale-location plot (heteroscedasticity check)
         predictions |>
           mutate(
             residual = .pred - <target_column>,
             sqrt_abs_resid = sqrt(abs(residual))
           ) |>
           ggplot(aes(x = .pred, y = sqrt_abs_resid)) +
           geom_point(alpha = 0.5) +
           geom_smooth(se = TRUE) +
           labs(title = "Scale-Location", x = "Fitted", y = expression(sqrt("|Residual|")))
         ```

      2. **Calibration plot** (classification):
         ```r
         # Probability calibration
         predictions |>
           cal_plot_breaks(truth = <target_column>, estimate = .pred_class)
         # Or: probably::cal_plot_breaks()
         ```

      3. **Confusion matrix and per-class metrics** (classification):
         ```r
         predictions |>
           conf_mat(truth = <target_column>, estimate = .pred_class) |>
           autoplot(type = "heatmap")

         predictions |>
           metrics(truth = <target_column>, estimate = .pred_class) |>
           filter(.metric %in% c("accuracy", "precision", "recall", "f_meas"))
         ```

      4. **Learning curve** (overfitting check):
         ```r
         # Train on increasing fractions of data, plot error
         # If test error is much higher than train error → overfitting
         # If both are high → underfitting
         ```

      5. **Cross-validation fold diagnostics:**
         ```r
         # Check variability across CV folds
         tune_results |>
           collect_metrics() |>
           ggplot(aes(x = .metric, y = mean)) +
           geom_point() +
           geom_errorbar(aes(ymin = mean - std_err, ymax = mean + std_err)) +
           facet_wrap(~.metric, scales = "free_y")
         ```

      Report: validation diagnostics with plots and interpretation.
    gate: Review
    output: validation_diagnostics

  - id: explain-model
    requires: [load-and-inspect-model]
    inline-prompt: |
      Generate model explanations using {{params.explainer}} method(s).

      **DALEX (comprehensive model-agnostic explanations):**
      ```r
      library(DALEX)
      library(DALEXtra)

      # Create explainer
      explainer <- explain_tidymodels(
        fit,
        data = training_data |> select(-<target_column>),
        y = training_data$<target_column>,
        label = "{{params.model}}"
      )

      # Model performance
      mp <- model_performance(explainer)
      plot(mp)

      # Variable importance (permutation-based)
      vi <- model_parts(explainer)
      plot(vi)  # Shows which features matter most

      # Partial Dependence Profiles
      pdp_age <- model_profile(explainer, variables = "age")
      plot(pdp_age)  # How predictions change with age

      # Accumulated Local Effects (more robust than PDP for correlated features)
      ale <- model_profile(explainer, variables = "age", type = "accumulated")
      plot(ale)

      # Break-down plot (single prediction explanation)
      bd <- predict_parts(explainer, new_observation = test_data[1, ])
      plot(bd)  # Which features contributed to this specific prediction

      # Shapley values via DALEX
      shap <- predict_parts(explainer, new_observation = test_data[1, ], type = "shap")
      plot(shap)
      ```

      **vip (lightweight variable importance):**
      ```r
      library(vip)

      # Extract the underlying model
      model_fit <- fit |> extract_fit_parsnip()

      # Variable importance
      vip(model_fit, num_features = 20) +
        labs(title = "Variable Importance")
      ```

      **shapviz (dedicated SHAP visualizations):**
      ```r
      library(shapviz)

      # For xgboost models:
      # shap <- shapviz(fit$fit$fit, X_pred = as.matrix(training_data))

      # SHAP summary plot
      sv_importance(shap, kind = "bee")

      # SHAP dependence plot
      sv_dependence(shap, v = "age", color_var = "income")

      # Waterfall plot for single prediction
      sv_waterfall(shap, row_id = 1)
      ```

      **Compare explanations across models** (if {{params.compare}} provided):
      ```r
      # Create explainers for both models
      explainer_1 <- explain_tidymodels(fit_1, data, y, label = "Model A")
      explainer_2 <- explain_tidymodels(fit_2, data, y, label = "Model B")

      # Compare performance
      mp_1 <- model_performance(explainer_1)
      mp_2 <- model_performance(explainer_2)
      plot(mp_1, mp_2)

      # Compare variable importance
      vi_1 <- model_parts(explainer_1)
      vi_2 <- model_parts(explainer_2)
      plot(vi_1, vi_2)
      ```

      Report: explanation plots and key insights.
    gate: Review
    output: explanations

  - id: assess-fairness
    requires: [load-and-inspect-model]
    inline-prompt: |
      Assess model fairness across protected attributes.

      Fairness enabled: {{params.fairness}}

      If fairness is false, skip this step.

      1. **Identify protected attributes** in your data:
         - Gender, race, ethnicity, age group, disability status
         - Geographic location (redlining concerns)
         - Any attribute where disparate impact is a concern

      2. **Fairness metrics with DALEX:**
         ```r
         library(DALEX)
         library(fairmodels)

         # Create fairness object
         fairness_obj <- fairness_check(
           explainer,
           protected = training_data$gender,
           privileged = "male"  # specify the privileged group
         )

         # Fairness metrics
         plot(fairness_obj)

         # Metric scores:
         # - Statistical Parity Difference: P(pred=1|unprivileged) - P(pred=1|privileged)
         # - Equal Opportunity Difference: TPR(unprivileged) - TPR(privileged)
         # - Predictive Parity Difference: PPV(unprivileged) - PPV(privileged)

         # Detailed fairness check per protected attribute
         fairness_obj |>
           plot() +
           labs(title = "Fairness Assessment Across Groups")

         # Check fairness across multiple protected attributes
         fobject <- fairness_check(
           explainer,
           protected = training_data$gender,
           privileged = "male"
         )
         fobject <- fairness_check(
           explainer,
           protected = training_data$age_group,
           privileged = "25-40",
           fairness_object = fobject  # add to existing
         )
         plot(fobject)
         ```

      3. **Interpret fairness results:**
         - **Statistical Parity Difference** ≈ 0: similar prediction rates across groups
         - **Equal Opportunity Difference** ≈ 0: similar true positive rates
         - Values far from 0 indicate potential bias
         - However: fairness metrics must be interpreted in business context
         - A difference doesn't automatically mean discrimination — investigate

      4. **Mitigation strategies** (if bias is detected):
         - Add protected attributes as features (include not ignore)
         - Resample training data for balanced representation
         - Use fairness-aware models (e.g., `fairml`)
         - Post-process predictions for equalized odds
         - Document why differences exist (legitimate vs. illegitimate factors)

      Report: fairness metrics, flagged disparities, and recommended actions.
    gate: Review
    output: fairness_assessment

  - id: generate-validation-report
    requires: [validate-performance, explain-model, assess-fairness]
    inline-prompt: |
      Generate a comprehensive model validation report.

      Model: {{params.model}}
      Diagnostics: {{state.validation_diagnostics}}
      Explanations: {{state.explanations}}
      Fairness: {{state.fairness_assessment}}

      ```
      📊 MODEL VALIDATION REPORT
      ==========================
      Model:      {{params.model}}
      Task:       <regression/classification>
      Engine:     <xgboost/ranger/glmnet>
      Date:       <today>

      ────────────────────────────────────────
      📈 PERFORMANCE METRICS
      ────────────────────────────────────────
      | Metric     | Train  | CV (mean ± SE) | Test   |
      |------------|--------|----------------|--------|
      | RMSE       | 0.123  | 0.156 ± 0.012  | 0.167  |
      | MAE        | 0.098  | 0.121 ± 0.009  | 0.134  |
      | R²         | 0.89   | 0.84 ± 0.02    | 0.82   |

      ────────────────────────────────────────
      🔍 RESIDUAL DIAGNOSTICS
      ────────────────────────────────────────
      - Normality:     <OK / concerns>
      - Homoscedasticity: <OK / heteroscedasticity detected>
      - Outliers:      <N> observations with |residual| > 3σ
      - Overfitting:   <test RMSE is N% higher than train — acceptable / concerning>

      ────────────────────────────────────────
      🧠 MODEL EXPLAINABILITY
      ────────────────────────────────────────
      **Top 5 Most Important Features:**
      1. feature_1: <importance_score>
      2. feature_2: <importance_score>
      3. feature_3: <importance_score>
      4. feature_4: <importance_score>
      5. feature_5: <importance_score>

      **Key PDP Insights:**
      - <feature> has a monotonic positive relationship with predictions
      - <feature> shows non-linear behavior above threshold X
      - <feature> has minimal impact — candidate for removal

      ────────────────────────────────────────
      ⚖️ FAIRNESS ASSESSMENT
      ────────────────────────────────────────
      | Protected Attribute | Metric               | Value  | Flag |
      |---------------------|----------------------|--------|------|
      | gender              | Stat Parity Diff     | 0.03   | ✅   |
      | gender              | Equal Opp Diff       | -0.02  | ✅   |
      | age_group           | Stat Parity Diff     | 0.15   | ⚠️   |

      ✅ No significant fairness concerns detected / ⚠️ Disparities found in age_group

      ────────────────────────────────────────
      🎯 RECOMMENDATIONS
      ────────────────────────────────────────
      1. <recommendation based on residuals>
      2. <recommendation based on explainability>
      3. <recommendation based on fairness>
      4. <recommendation for next model iteration>
      ```

      Save the report:
      ```r
      # Write report to Markdown or HTML
      # Pin alongside the model for audit trail
      ```

      Report: validation report generated and saved.
    gate: Approve
    output: validation_report

tags:
  - r
  - ml
  - validation
  - explainability
  - fairness
  - dalex
  - shap
  - vip

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER evaluate a model solely on training data metrics — always use held-out test data."
    severity: "error"
  - rule: "NEVER ignore fairness concerns — if protected attributes exist in the data, assess them."
    severity: "error"
  - rule: "ALWAYS provide both global (importance) and local (single-prediction) explanations."
    severity: "warning"
  - rule: "NEVER treat fairness metrics as definitive proof of bias — they are flags for investigation."
    severity: "warning"
  - rule: "Use DALEX for comprehensive model-agnostic explanations — it works with any model type."
    severity: "warning"
---

You are an ML model validation and explainability specialist. You rigorously
validate model performance, generate explanations, and assess fairness —
following responsible AI best practices.

## Validation Philosophy

1. **TEST DATA IS SACRED**: Evaluate on held-out test data that was never used
   during training or hyperparameter tuning. This is the only honest metric.
2. **EXPLAINABILITY IS NOT OPTIONAL**: In 2026, model explanations are a
   regulatory requirement (EU AI Act, GDPR, EEOC). Stakeholders need to
   understand WHY a model made a prediction.
3. **FAIRNESS IS EVERYONE'S RESPONSIBILITY**: If your model makes decisions
   about people, you have an ethical and legal obligation to assess bias.
4. **ONE METRIC IS NOT ENOUGH**: Report multiple metrics (RMSE + MAE + R²;
   accuracy + precision + recall + F1 + ROC AUC). A model can excel at one
   metric while being terrible at another.
5. **EXPLANATIONS GUIDE IMPROVEMENT**: The point of explainability is not
   just transparency — it's identifying which features drive predictions so
   you can improve the model.

## R Explainability Ecosystem

| Package | What It Does | Best For |
|---------|-------------|----------|
| `DALEX` | Comprehensive model-agnostic explanations | Any model type, full audit trail |
| `vip` | Lightweight variable importance | Quick feature ranking |
| `shapviz` | SHAP value visualizations | Tree models, detailed local explanations |
| `fairmodels` | Fairness assessment and visualization | Bias detection, regulatory compliance |
| `pdp` | Partial dependence plots | Understanding feature-prediction relationships |
| `ALEPlot` | Accumulated Local Effects | Correlated features (more robust than PDP) |
