---
name: r-docker-build
version: 1.0.0
context-mode: Fork
description: Build a Docker image for an R project: package, Shiny app, or Plumber API
trigger: manual
argument-hint: "--type package|shiny|plumber|quarto [--image-name <name>] [--r-version 4.4] [--port <8080>]"
parameters:
  type:
    type: String
    required: true
    enum: ["package", "shiny", "plumber", "quarto"]
    hint: "Type of R project to containerize"
  image-name:
    type: String
    required: false
    hint: "Docker image name (default: directory name)"
  r-version:
    type: String
    required: false
    default: "4.4"
    hint: "R version for the base image (e.g., 4.4, 4.3, devel)"
  port:
    type: Number
    required: false
    default: 3838
    min: 1024
    max: 65535
    hint: "Port to expose (3838 for Shiny, 8080 for Plumber)"
  renv:
    type: Boolean
    required: false
    default: true
    hint: "Use renv.lock for dependency installation"
steps:
  - id: analyze-project
    inline-prompt: |
      Analyze the project to determine Docker requirements:

      1. Determine project type: {{params.type}}
      2. Read DESCRIPTION (if package) or check for `app.R`/`plumber.R`.
      3. Check for renv.lock: `renv` usage: {{params.renv}}
      4. Identify:
         - Base image needed (rocker/r-ver, rocker/shiny, rocker/plumber)
         - System dependencies (libcurl, libssl, libxml2, etc.)
         - Entrypoint / startup command
         - Port to expose
      5. Report: base image, system deps, entrypoint, port.
    output: docker_requirements

  - id: create-dockerfile
    requires: [analyze-project]
    inline-prompt: |
      Create a `Dockerfile` based on the project analysis.

      Requirements: {{state.docker_requirements}}
      Project type: {{params.type}}
      Renv enabled: {{params.renv}}

      The Dockerfile template depends on the project type. Below are the four
      type-specific templates. Generate the appropriate one for type={{params.type}}.

      **For type "package":**
      ```dockerfile
      FROM rocker/r-ver:{{params.r-version}}
      RUN apt-get update && apt-get install -y --no-install-recommends \
        make \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        && rm -rf /var/lib/apt/lists/*
      ```

      If renv is enabled for a package, add:
      ```dockerfile
      RUN R -e "pak::pak('renv')"
      COPY . /app
      WORKDIR /app
      RUN R -e "renv::restore()"
      RUN R CMD INSTALL .
      ```
      If renv is disabled for a package, add instead:
      ```dockerfile
      COPY . /app
      WORKDIR /app
      RUN R -e "pak::local_install(dependencies = TRUE)"
      ```
      End with:
      ```
      HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD ["R", "-e", "TRUE"]
      USER rstudio
      CMD ["R"]
      ```

      **For type "shiny":**
      ```dockerfile
      FROM rocker/shiny:{{params.r-version}}
      RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        && rm -rf /var/lib/apt/lists/*
      COPY . /srv/shiny-server/
      ```
      If renv is enabled for shiny, add: `RUN R -e "renv::restore()"`
      Add: `EXPOSE 3838`
      End with:
      ```
      HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD curl -f http://localhost:3838/ || exit 1
      USER rstudio
      CMD ["/usr/bin/shiny-server"]
      ```

      **For type "plumber":**
      ```dockerfile
      FROM rocker/r-ver:{{params.r-version}}
      RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        && rm -rf /var/lib/apt/lists/*
      COPY . /app
      WORKDIR /app
      ```
      If renv is enabled for plumber, add:
      `RUN R -e "pak::pak('renv'); renv::restore()"`
      If renv is disabled for plumber, add instead:
      `RUN R -e "pak::pak('plumber')"`
      Add: `EXPOSE {{params.port}}`
      End with:
      ```
      HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD curl -f http://localhost:{{params.port}}/__docs__/ || exit 1
      USER rstudio
      CMD ["R", "-e", "plumber::pr_run(plumber::pr('plumber.R'), host='0.0.0.0', port={{params.port}})"]
      ```

      **For type "quarto":**
      ```dockerfile
      FROM rocker/verse:{{params.r-version}}
      RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        && rm -rf /var/lib/apt/lists/*
      RUN curl -fsSL https://quarto.org/download/latest/quarto-linux-amd64.deb -o quarto.deb \
        && dpkg -i quarto.deb \
        && rm quarto.deb
      ```
      If renv is enabled for quarto, add:
      ```
      COPY . /app
      WORKDIR /app
      RUN R -e "renv::restore()"
      ```
      End with:
      ```
      USER rstudio
      CMD ["quarto", "render"]
      ```

      Report: Dockerfile created for type {{params.type}}.
    gate: Review
    output: dockerfile

  - id: create-dockerignore
    requires: [create-dockerfile]
    inline-prompt: |
      Create a `.dockerignore` file to exclude unnecessary files:

      ```
      # R
      .Rproj.user/
      .Rhistory
      .RData
      .Ruserdata

      # renv
      renv/library/
      renv/local/
      renv/cellar/
      renv/sandbox/
      renv/staging/

      # Git
      .git/
      .gitignore
      .gitattributes

      # targets
      _targets/

      # Docker
      Dockerfile
      .dockerignore
      docker-compose.yml

      # Tests
      tests/
      # Package-specific: exclude docs/ for package builds
      docs/
      ```

      Report: .dockerignore created.
    output: dockerignore

  - id: build-instructions
    requires: [create-dockerfile]
    inline-prompt: |
      Provide build and run instructions for project type {{params.type}}.

      ```bash
      # Build the image
      docker build -t {{params.image-name}} .
      ```

      If the type is "shiny", add:
      ```bash
      # Run the Shiny app
      docker run -d -p {{params.port}}:3838 --memory=2g --cpus=2 {{params.image-name}}
      ```

      If the type is "plumber", add:
      ```bash
      # Run the Plumber API
      docker run -d -p {{params.port}}:{{params.port}} --memory=2g --cpus=2 {{params.image-name}}
      ```

      If the type is "package", add:
      ```bash
      # Run R interactively in the container
      docker run -it --rm --memory=2g --cpus=2 {{params.image-name}} R
      ```

      If the type is "quarto", add:
      ```bash
      # Render a Quarto project
      docker run --rm -v $(pwd):/app --memory=2g --cpus=2 {{params.image-name}} render
      ```

      Also create a `docker-compose.yml` suggestion for multi-service setups.

      Report: build/run instructions.
    output: instructions

tags:
  - r
  - docker
  - deployment
  - devops

allowed-tools:
  - "*"

constraints:
  file: ../_shared/constraints-r.md
---

You are an R DevOps specialist focused on containerization with Docker.
You use the Rocker project's Docker images for R.

## Rules

1. ALWAYS use Rocker images: `rocker/r-ver` (base), `rocker/shiny`, `rocker/plumber`.
2. NEVER use `:latest` tag: always pin the R version (e.g., `:4.4`).
3. Combine `apt-get update && install && rm -rf /var/lib/apt/lists/*` in one RUN.
4. Install system dependencies before R packages.
5. Use `.dockerignore` to keep images small.
6. Set `RENV_CONFIG_CACHE_ENABLED = FALSE` in CI builds.
7. Never copy `renv/library/` into the image: let renv restore it.
8. For Shiny, use `rocker/shiny` which has Shiny Server pre-configured.
9. For Plumber, use `rocker/r-ver` and install plumber via renv or install.packages.
10. Always EXPOSE the correct port and document it.
11. For production: use multi-stage builds to separate build dependencies from runtime. Copy only necessary artifacts from builder stage.
