---
name: r-vetiver-deploy
description: "Version, deploy, and monitor an ML model with vetiver: pin, create Plumber API, deploy to Connect or Docker"
version: 1.0.0
context-mode: Fork
trigger: both
trigger-patterns:
  - "deploy model *"
  - "vetiver *"
  - "version model *"
  - "pin model *"
parameters:
  model_object:
    type: String
    required: true
    hint: "Variable name of the fitted model object in the current R environment"
  model_name:
    type: String
    required: false
    default: "my-model"
    hint: "Name for the model (used as API endpoint name and pin identifier)"
  board:
    type: String
    required: false
    default: "local"
    enum: ["local", "rsconnect", "s3"]
    hint: "Pin board destination: local (filesystem), rsconnect (Posit Connect), or s3 (AWS)"
  deploy:
    type: Boolean
    required: false
    default: false
    hint: "Whether to deploy the model API after pinning (true/false)"
  rsconnect_account:
    type: String
    required: false
    hint: "Posit Connect account name (required if deploying to Connect)"
  rsconnect_server:
    type: String
    required: false
    hint: "Posit Connect server URL (required if deploying to Connect)"
tags:
  - r
  - mlops
  - deployment
  - model
  - vetiver
constraints:
  - rule: "NEVER deploy without version pinning."
    severity: "error"
  - rule: "ALWAYS test the API health endpoint after deployment."
    severity: "warning"
  - rule: "Use vetiver for model versioning and deployment."
    severity: "warning"
  - rule: "Always include model metadata (version, date, metrics)."
    severity: "warning"
allowed-tools:
  - "*"
steps:
  - id: prepare-model
    inline-prompt: |
      Version the model with vetiver.

      First, check if vetiver is installed:
      ```r
      if (!requireNamespace("vetiver", quietly = TRUE)) {
        renv::install("vetiver")
      }
      ```

      Wrap the model object `{{params.model_object}}`:
      ```r
      library(vetiver)
      v <- vetiver_model({{params.model_object}}, "{{params.model_name}}")

      # Inspect the prototype (records input schema)
      print(v$prototype)

      # Check model metadata
      print(v$description)
      print(v$metadata$required_pkgs)
      ```
      Confirm the model type, required packages, and input schema are correct.

      ### Validate Prototype Against Production Data

      Before deploying, confirm the prototype matches real input:

      ```r
      # Load a sample of production data
      production_sample <- readRDS("data/production-sample.rds")

      # Verify column names and types match the prototype
      stopifnot(all(names(v$prototype) %in% names(production_sample)))
      for (col in names(v$prototype)) {
        stopifnot(typeof(production_sample[[col]]) == typeof(v$prototype[[col]]))
      }

      # Test a prediction end-to-end
      predict(v, production_sample[1, ])
      ```

      NEVER deploy a model without validating the prototype against real input data.
    output: model-versioned
    gate: Review
  - id: store-model
    requires:
      - prepare-model
    inline-prompt: |
      Store (pin) the versioned model.

      For board `{{params.board}}`:

      **local**:
      ```r
      model_board <- pins::board_local()
      vetiver_pin_write(model_board, v)
      # List pinned versions
      pins::pin_search(model_board, "{{params.model_name}}")
      ```

      **rsconnect** (Posit Connect):
      ```r
      model_board <- pins::board_rsconnect()
      vetiver_pin_write(model_board, v)
      ```

      **s3**:
      ```r
      model_board <- pins::board_s3("my-bucket")
      vetiver_pin_write(model_board, v)
      ```

      Verify the model version was written and can be read back.
    output: model-pinned
  - id: compare-performance
    requires:
      - prepare-model
    inline-prompt: |
      Compare the new model's performance against the currently pinned version.

      ```r
      holdout <- readRDS("data/holdout.rds")
      new_preds <- predict(v, holdout)

      tryCatch({
        old_v <- vetiver_pin_read(model_board, "{{params.model_name}}")
        old_preds <- predict(old_v, holdout)
        new_rmse <- sqrt(mean((holdout$target - new_preds$.pred)^2))
        old_rmse <- sqrt(mean((holdout$target - old_preds$.pred)^2))
        cat(sprintf("Old RMSE: %.4f\nNew RMSE: %.4f\nDelta: %.4f\n", old_rmse, new_rmse, new_rmse - old_rmse))
        stopifnot(new_rmse <= old_rmse * 1.05)
      }, error = function(e) {
        if (!grepl("not found", e$message)) stop(e)
        message("No previous version: proceeding with initial deployment")
      })
      ```

      ONLY pin the model if performance meets or exceeds baseline.
    output: performance-comparison
    gate: Review
  - id: create-api
    requires:
      - store-model
    inline-prompt: |
      Create a Plumber API for the model:
      ```r
      # Generate the Plumber API file
      vetiver_write_plumber(
        model_board,
        "{{params.model_name}}",
        file = "plumber.R"
      )

      # Generate Docker artifacts if deploying with Docker
      vetiver_prepare_docker(
        model_board,
        "{{params.model_name}}",
        path = "."
      )
      ```

      This creates:
      - `plumber.R`: API entry point with /predict endpoint and OpenAPI spec
      - `Dockerfile`: Container configuration (generated by vetiver)
      - `renv.lock`: Exact package versions for reproducibility

      The API automatically:
      - Validates input against the prototype schema
      - Returns predictions with the correct format
      - Includes a /pin-url endpoint for model metadata
      - Generates OpenAPI documentation
    output: api-files
    gate: Review
  - id: deploy-model
    requires:
      - create-api
    inline-prompt: |
      Deploy the model API. Only proceed if `{{params.deploy}}` is `true`.

      **Posit Connect**:
      ```r
      vetiver_deploy_rsconnect(
        model_board,
        "{{params.model_name}}",
        account = "{{params.rsconnect_account}}",
        server = "{{params.rsconnect_server}}"
      )
      ```

      The model will be available at:
      `https://<connect-server>/content/<app-id>/predict`

      **Docker**:
      ```bash
      docker build -t {{params.model_name}}:latest .
      docker run -p 8000:8000 \
        --memory=2g \
        --cpus=2 \
        --restart=unless-stopped \
        {{params.model_name}}:latest
      ```

      Test the deployed model:
      ```r
      # Get prototype from pinned model
      v <- vetiver_pin_read(model_board, "{{params.model_name}}")
      test_input <- v$prototype

      # Test prediction
      endpoint <- vetiver_endpoint("http://localhost:8000/predict")
      predict(endpoint, test_input)
      ```
    output: deployment-result
    gate: Approve
  - id: verify-deployment
    requires:
      - deploy-model
    inline-prompt: |
      Verify the deployed model:
      1. Call the /ping endpoint: should return 200
      2. Call the /metadata endpoint: should return model metadata
      3. Send a test prediction request with prototype-compatible input
      4. Verify the response format matches expectations
      5. Check that the OpenAPI spec at /__docs__/ is accessible

      Run monitoring check:
      ```r
      # Check all pinned model versions
      vetiver_pin_versions(model_board, "{{params.model_name}}")
      ```

      Report: endpoint URL, model version, test prediction result, OpenAPI URL.

      ### Rollback Procedure

      If a deployed model needs to be rolled back:

      1. List available versions:
      ```r
      vetiver_pin_versions(model_board, "{{params.model_name}}")
      ```

      2. Read the previous stable version:
      ```r
      previous_v <- vetiver_pin_read(model_board, "{{params.model_name}}", version = "<version_hash>")
      ```

      3. Re-deploy previous version to Connect:
      ```r
      vetiver_deploy_rsconnect(model_board, "{{params.model_name}}", version = "<version_hash>")
      ```

      ALWAYS keep at least 3 previous versions pinned for quick rollback.
    output: verification-report
---

# R Vetiver MLOps Playbook

You are an expert in MLOps for R. Use the `vetiver` package (Posit) for model versioning, API generation, and deployment.

## Vetiver Workflow

```
fit model → vetiver_model() → vetiver_pin_write() → vetiver_write_plumber() → deploy
```

### Key Concepts

- **Prototype**: Vetiver records the input data schema (column names, types) and validates all incoming prediction requests
- **Pin**: A versioned, immutable snapshot of the model stored on a board (local, Connect, S3)
- **Plumber API**: Auto-generated from the model: `/predict` endpoint with input validation
- **Docker support**: `vetiver_prepare_docker()` generates complete deployment artifacts

### Supported Model Types

- tidymodels (parsnip workflows)
- lm/glm (base R)
- xgboost, ranger, keras, torch
- Custom models via `vetiver_model()` wrapper
- Python models via vetiver-python

### Board Options

- `board_local()`: local folder, good for development
- `board_rsconnect()`: Posit Connect, production-grade
- `board_s3()`: AWS S3, cloud storage
- `board_folder()`: network/remote folder

### Monitoring

Monitor these metrics post-deployment:

| Metric                      | What to Watch                | Alert If                             |
| --------------------------- | ---------------------------- | ------------------------------------ |
| **Prediction latency**      | p50, p95, p99 response times | p95 > 500ms or doubles from baseline |
| **Error rate**              | 4xx/5xx count per minute     | >1% of total requests                |
| **Schema violations**       | Prototype-mismatch errors    | Any non-zero count                   |
| **Prediction distribution** | Mean, stddev of predictions  | Drift >2σ from baseline              |

For Posit Connect: use the built-in metrics dashboard.
For Docker: expose `/metrics` with `prometheus` package.

### Best Practices

1. Pin every model version: never overwrite
2. Test the prototype before deployment: `v$prototype` should match expected input
3. Use `vetiver_prepare_docker()` for reproducible container images
4. Version your renv.lock alongside the model
5. Monitor model performance metrics post-deployment
