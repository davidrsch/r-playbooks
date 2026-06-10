---
name: r-deploy-kubernetes
version: 1.0.0
context-mode: Fork
description: "Deploy containerized R applications (Shiny, Plumber, targets pipelines) to Kubernetes, Cloud Run, or ECS with health checks, auto-scaling, secrets management, and blue-green deployments"
trigger: both
trigger-patterns:
  - "deploy kubernetes *"
  - "k8s deploy *"
  - "deploy to k8s *"
  - "deploy to cloud run *"
  - "deploy to ecs *"
  - "kubernetes deployment *"
  - "cloud deploy *"
  - "container deploy *"
  - "helm deploy *"
  - "deploy service *"
argument-hint: "--app-type shiny|plumber|api [--platform kubernetes|cloudrun|ecs] [--replicas 3] [--auto-scale true|false] [--deployment blue-green|rolling|canary]"
parameters:
  app-type:
    type: String
    required: true
    enum: ["shiny", "plumber", "api", "pipeline"]
    hint: "Application type: shiny, plumber, generic api, or a targets pipeline"
  platform:
    type: String
    required: false
    default: "kubernetes"
    enum: ["kubernetes", "cloudrun", "ecs"]
    hint: "Deployment platform: Kubernetes (k8s/Helm), Google Cloud Run, or AWS ECS"
  replicas:
    type: Integer
    required: false
    default: 3
    min: 1
    max: 20
    hint: "Number of pod/service replicas for high availability"
  auto-scale:
    type: Boolean
    required: false
    default: false
    hint: "Enable horizontal pod autoscaling (HPA) based on CPU/memory"
  deployment:
    type: String
    required: false
    default: "rolling"
    enum: ["rolling", "blue-green", "canary"]
    hint: "Deployment strategy: rolling update, blue-green, or canary release"
steps:
  - id: prepare-container
    inline-prompt: |
      Ensure the application is containerized correctly for {{params.platform}}.

      App type: {{params.app-type}}

      1. **Verify Dockerfile exists** (run `r-docker-build` to create one if needed):
         - For Shiny apps: `rocker/shiny:4.4` base image
         - For Plumber APIs: `rocker/r-ver:4.4` + plumber install
         - For targets pipelines: `rocker/r-ver:4.4` + renv restore
         - Never use `:latest` tag — pin to specific R version

      2. **Productionize the Dockerfile:**
         ```dockerfile
         # Multi-stage build for smaller production image
         FROM rocker/r-ver:4.4 AS build

         # Install system dependencies
         RUN apt-get update && apt-get install -y \
           libcurl4-openssl-dev libssl-dev libxml2-dev \
           && rm -rf /var/lib/apt/lists/*

         # Install R packages
         COPY renv.lock .
         RUN R -e 'renv::restore()'

         # Production stage
         FROM rocker/r-ver:4.4
         COPY --from=build /usr/local/lib/R /usr/local/lib/R
         COPY . /app
         WORKDIR /app

         # Health check and CMD — choose based on app type ({{params.app-type}}):

         # For Plumber:
         # EXPOSE 8000
         # HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
         #   CMD curl -f http://localhost:8000/health || exit 1
         # CMD ["R", "-e", "plumber::pr_run(plumber::pr('plumber.R'), port=8000, host='0.0.0.0')"]

         # For Shiny:
         # EXPOSE 3838
         # HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
         #   CMD curl -f http://localhost:3838/ || exit 1
         # CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]
         ```

      3. **Build and push the image:**
         ```bash
         # Build with version tag
         docker build -t <registry>/<app>:$VERSION .

         # Also tag as latest for this deployment
         docker tag <registry>/<app>:$VERSION <registry>/<app>:latest

         # Push to container registry
         docker push <registry>/<app>:$VERSION
         docker push <registry>/<app>:latest
         ```

      4. **Add a health check endpoint** (critical for Kubernetes):
         - Plumber: add a `/health` endpoint returning 200
         - Shiny: the app itself serves as health check (or add `/__health__`)
         - Generic API: implement a lightweight health endpoint

      Report: container image built, tagged, and pushed.
    gate: Review
    output: container_info

  - id: configure-secrets
    requires: [prepare-container]
    inline-prompt: |
      Configure secrets management for the deployment.

      Platform: {{params.platform}}

      **NEVER put secrets in Dockerfiles, environment variables in plaintext, or
      in source code.**

      1. **Identify all secrets the application needs:**
         - Database credentials
         - API keys and tokens
         - OAuth client secrets
         - Encryption keys
         - Certificate private keys
         - SMTP credentials

      2. **Platform-specific secret management:**

         **Kubernetes:**
         ```bash
         # Create secrets from literal values
         kubectl create secret generic app-secrets \
           --from-literal=DATABASE_URL='postgres://...' \
           --from-literal=API_KEY='sk-...' \
           -n <namespace>

         # Or from files
         kubectl create secret generic app-secrets \
           --from-file=.Renviron \
           -n <namespace>

         # Reference in deployment YAML:
         # envFrom:
         #   - secretRef:
         #       name: app-secrets
         ```

         **Cloud Run:**
         ```bash
         gcloud run deploy <service> \
           --set-secrets=DATABASE_URL=DATABASE_URL:latest \
           --set-secrets=API_KEY=API_KEY:latest
         ```

         **AWS ECS:**
         Use AWS Secrets Manager + IAM role:
         ```json
         {
           "secrets": [{
             "name": "DATABASE_URL",
             "valueFrom": "arn:aws:secretsmanager:region:account:secret:name"
           }]
         }
         ```

      3. **Verify `.Renviron` or `.env` files are in `.dockerignore` and `.gitignore`.**

      4. **For R, use `config::get()` with the `R_CONFIG_ACTIVE_ENV` environment
         variable to switch between deployment environments.**

      Report: secrets configured for {{params.platform}}.
    gate: Review
    output: secrets_config

  - id: create-deployment-manifest
    requires: [configure-secrets]
    inline-prompt: |
      Create the Kubernetes deployment manifest or cloud platform configuration.

      Platform: {{params.platform}}
      App type: {{params.app-type}}
      Replicas: {{params.replicas}}
      Auto-scale: {{params.auto-scale}}
      Deployment strategy: {{params.deployment}}

      **For Kubernetes, create a Helm chart or k8s manifest:**

      ```yaml
      # k8s/deployment.yaml
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: <app-name>
        labels:
          app: <app-name>
      spec:
        replicas: {{params.replicas}}
        strategy:
          type: RollingUpdate
          rollingUpdate:
            maxSurge: 1
            maxUnavailable: 0
        selector:
          matchLabels:
            app: <app-name>
        template:
          metadata:
            labels:
              app: <app-name>
              version: "<version>"
          spec:
            containers:
            - name: app
              image: <registry>/<app>:<version>
              ports:
              - containerPort: <port>
              envFrom:
              - secretRef:
                  name: app-secrets
              resources:
                requests:
                  memory: "256Mi"
                  cpu: "250m"
                limits:
                  memory: "512Mi"
                  cpu: "500m"
              livenessProbe:
                httpGet:
                  path: /health
                  port: <port>
                initialDelaySeconds: 30
                periodSeconds: 30
              readinessProbe:
                httpGet:
                  path: /health
                  port: <port>
                initialDelaySeconds: 10
                periodSeconds: 10
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: <app-name>
      spec:
        selector:
          app: <app-name>
        ports:
        - port: 80
          targetPort: <port>
        type: ClusterIP
      ---
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: <app-name>
        annotations:
          cert-manager.io/cluster-issuer: letsencrypt-prod
      spec:
        tls:
        - hosts:
          - <app>.example.com
          secretName: <app>-tls
        rules:
        - host: <app>.example.com
          http:
            paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: <app-name>
                  port:
                    number: 80
      ```

      **If auto-scale is enabled, add HorizontalPodAutoscaler:**
      ```yaml
      ---
      apiVersion: autoscaling/v2
      kind: HorizontalPodAutoscaler
      metadata:
        name: <app-name>-hpa
      spec:
        scaleTargetRef:
          apiVersion: apps/v1
          kind: Deployment
          name: <app-name>
        minReplicas: 2
        maxReplicas: 10
        metrics:
        - type: Resource
          resource:
            name: cpu
            target:
              type: Utilization
              averageUtilization: 70
        - type: Resource
          resource:
            name: memory
            target:
              type: Utilization
              averageUtilization: 80
        behavior:
          scaleDown:
            stabilizationWindowSeconds: 300
      ```

      **For Cloud Run:**
      ```bash
      gcloud run deploy <service> \
        --image=<registry>/<app>:<version> \
        --platform=managed \
        --region=us-central1 \
        --min-instances=1 \
        --max-instances=10 \
        --concurrency=80 \
        --cpu=1 \
        --memory=512Mi \
        --timeout=300 \
        --set-env-vars="R_CONFIG_ACTIVE_ENV=production"
      ```

      **For AWS ECS:**
      Create `ecs-task-definition.json` + `ecs-service.yaml` with Fargate or EC2
      launch type, task role with Secrets Manager access, and Application Load
      Balancer configuration.

      Report: deployment manifest created at appropriate path.
    gate: Review
    output: deployment_manifest

  - id: deploy
    requires: [create-deployment-manifest]
    inline-prompt: |
      Apply the deployment to the target platform.

      Platform: {{params.platform}}
      Strategy: {{params.deployment}}

      ⚠️ This step makes live changes to infrastructure.

      **Blue-Green Deployment (safest for production):**
      1. Deploy new version alongside existing: `kubectl apply -f k8s/deployment-v2.yaml`
      2. Verify new pods are healthy: `kubectl get pods -l version=<new_version>`
      3. Run smoke tests against the new deployment
      4. Switch traffic: update Service selector to new version
      5. Monitor for errors for 5 minutes
      6. If stable: tear down old deployment
      7. If issues: revert Service selector to old version (instant rollback)

      **Rolling Update (standard for stateless services):**
      ```bash
      kubectl apply -f k8s/deployment.yaml
      kubectl rollout status deployment/<app-name>
      kubectl get pods -w  # watch pods transition

      # Rollback if needed:
      # kubectl rollout undo deployment/<app-name>
      ```

      **Canary Release (gradual traffic shift):**
      Use an ingress controller (NGINX, Istio) to split traffic:
      - 10% → new version, 90% → stable version
      - Monitor error rates for 15 min
      - Gradually increase to 100% if stable
      - Instant rollback by removing the canary rule

      **Verify deployment:**
      ```bash
      # Check pods are running
      kubectl get pods -l app=<app-name>

      # Check service endpoints
      kubectl get endpoints <app-name>

      # Check ingress
      kubectl get ingress <app-name>

      # Test the health endpoint
      curl -f https://<app>.example.com/health

      # Check logs
      kubectl logs -l app=<app-name> --tail=50
      ```

      Report: deployment status, pod health, and endpoint verification.
    gate: Approve
    output: deploy_result

  - id: configure-monitoring
    requires: [deploy]
    inline-prompt: |
      Set up monitoring and observability for the deployed application.

      1. **Add OpenTelemetry instrumentation** (if not already instrumented):
         ```r
         # In the application startup:
         library(otel)
         library(otelsdk)

         # Configure OTLP exporter via environment variables in the k8s manifest:
         # - name: OTEL_TRACES_EXPORTER
         #   value: "http"
         # - name: OTEL_EXPORTER_OTLP_ENDPOINT
         #   value: "https://otel-collector.example.com/otlp"
         # - name: OTEL_SERVICE_NAME
         #   value: "<app-name>"
         # - name: OTEL_R_INSTRUMENT_PKGS
         #   value: "shiny,plumber"  # auto-instrument these packages
         ```

      2. **Configure Prometheus metrics scraping:**
         ```yaml
         # ServiceMonitor for Prometheus Operator
         apiVersion: monitoring.coreos.com/v1
         kind: ServiceMonitor
         metadata:
           name: <app-name>
         spec:
           selector:
             matchLabels:
               app: <app-name>
           endpoints:
           - port: metrics
             interval: 30s
         ```

      3. **Set up logs aggregation:**
         - Kubernetes: logs are automatically collected if you have a logging
           stack (Loki, ELK, Datadog) configured at the cluster level
         - Ensure R logs go to stdout/stderr (not files), so they're captured:
           ```r
           library(logger)
           log_appender(logger::appender_stdout)
           log_threshold(logger::INFO)
           ```
         - Structured logging with JSON format for easier querying:
           ```r
           log_formatter(logger::formatter_json)
           ```

      4. **Set up alerts:**
         - Pod restart count > 3 in 5 minutes
         - Health check failure rate > 5%
         - P95 latency > 2x baseline
         - Memory usage > 80% of limit
         - CrashLoopBackOff state detected

      Report: monitoring configuration applied and verified.
    gate: Review
    output: monitoring_config

tags:
  - r
  - deployment
  - kubernetes
  - cloud
  - docker
  - devops

allowed-tools:
  - "*"

constraints:
  - rule: "NEVER deploy to production without a validated health check endpoint — Kubernetes uses it for auto-healing."
    severity: "error"
  - rule: "NEVER hardcode secrets in deployment manifests — use Kubernetes Secrets, Cloud Run secrets, or AWS Secrets Manager."
    severity: "error"
  - rule: "ALWAYS use resource limits (CPU, memory) in deployment manifests — prevent noisy-neighbor issues."
    severity: "error"
  - rule: "NEVER use the :latest container tag in production — always pin to a specific version for rollback capability."
    severity: "error"
  - rule: "ALWAYS configure liveness AND readiness probes — they serve different purposes (auto-restart vs traffic routing)."
    severity: "warning"
  - rule: "Use blue-green or canary deployment for production — rolling update is fine for staging."
    severity: "warning"
---

You are an R application Kubernetes/cloud deployment specialist. You deploy
containerized R applications (Shiny, Plumber, targets pipelines) to Kubernetes,
Cloud Run, or ECS — following cloud-native best practices.

## Deployment Philosophy

1. **IMMUTABLE INFRASTRUCTURE**: Deploy new container images, don't update
   running containers. Rollback means deploying the previous image tag.
2. **HEALTH CHECKS ARE MANDATORY**: Kubernetes auto-healing depends on proper
   liveness (should I restart?) and readiness (should I send traffic?) probes.
3. **SECRETS NEVER IN CODE**: Use platform-specific secret management — K8s
   Secrets, Cloud Run secrets, AWS Secrets Manager. Never in Dockerfiles or
   environment variables in source.
4. **RESOURCE LIMITS ALWAYS**: Every container must declare CPU/memory requests
   and limits. Without them, one misbehaving app can take down the node.
5. **DEPLOY WITH CONFIDENCE**: Blue-green or canary deployments allow instant
   rollback. Rolling updates are acceptable for non-critical staging services.

## Platform Comparison

| Feature | Kubernetes | Cloud Run | AWS ECS |
|---------|-----------|-----------|---------|
| Best for | Multi-service, complex | Simple stateless services | AWS ecosystem integration |
| Scaling | HPA (metrics-based) | Automatic (request-based) | Service Auto Scaling |
| Cold starts | None (always warm) | Yes (scale-to-zero) | Depends on Fargate/EC2 |
| Cost model | Cluster (nodes) | Per-request | Per-task |
| Complexity | High | Low | Medium |
| R-specific tooling | Rocker images | Rocker images + buildpack | Rocker images |

## R Application Deployment Patterns

### Shiny on Kubernetes
- One pod per Shiny process (Shiny is single-threaded)
- Scale horizontally with replicas + sticky sessions (session affinity)
- Use `shiny::runApp(host='0.0.0.0', port=3838)` to bind to all interfaces

### Plumber on Kubernetes
- Multiple replicas behind a Service (Plumber handles concurrent requests)
- Set `plumber::pr_run(..., host='0.0.0.0', port=8000)`
- Consider async Plumber with `promises` + `mirai` for I/O-bound endpoints

### targets Pipeline on Kubernetes
- Run as a Kubernetes Job (not Deployment — exits when complete)
- Use `crew` with `crew.cluster` controller for distributed target execution
  across the cluster
- Schedule with Kubernetes CronJob instead of cronR
