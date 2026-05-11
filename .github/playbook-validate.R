#!/usr/bin/env Rscript
# playbook-validate.R — Validate all PLAYBOOK.md files against the schema
#
# Usage: Rscript .github/playbook-validate.R
# Returns: Exit code 0 on success, 1 on any validation error

library(yaml)
library(jsonlite)

SCHEMA_FILE <- ".github/playbook-schema.json"
PLAYBOOKS_DIR <- "playbooks"

cat("🔍 R Playbooks Validator\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━\n\n")

# ── 1. Load schema ──────────────────────────────────────────
schema <- fromJSON(SCHEMA_FILE, simplifyVector = FALSE)

# ── 2. Discover playbooks ───────────────────────────────────
dirs <- list.dirs(PLAYBOOKS_DIR, recursive = FALSE)
if (length(dirs) == 0) {
  cat("❌ No playbook directories found in", PLAYBOOKS_DIR, "\n")
  quit(status = 1)
}

errors <- list()
warnings <- list()

# ── 3. Validate each playbook ──────────────────────────────
for (dir in sort(dirs)) {
  playbook_name <- basename(dir)
  md_file <- file.path(dir, "PLAYBOOK.md")

  # 3a. File existence
  if (!file.exists(md_file)) {
    errors[[playbook_name]] <- c(
      errors[[playbook_name]],
      "Missing PLAYBOOK.md"
    )
    cat(sprintf("❌ %-35s %s\n", playbook_name, "Missing PLAYBOOK.md"))
    next
  }

  # 3b. Read YAML frontmatter
  content <- readLines(md_file, warn = FALSE)
  dashes <- which(trimws(content) == "---")
  if (length(dashes) < 2) {
    errors[[playbook_name]] <- c(
      errors[[playbook_name]],
      "Missing YAML frontmatter (--- delimiters)"
    )
    cat(sprintf("❌ %-35s %s\n", playbook_name, "Missing YAML frontmatter"))
    next
  }

  yaml_text <- paste(
    content[(dashes[1] + 1):(dashes[2] - 1)],
    collapse = "\n"
  )
  yaml <- tryCatch(yaml.load(yaml_text), error = function(e) {
    errors[[playbook_name]] <- c(
      errors[[playbook_name]],
      sprintf("YAML parse error: %s", e$message)
    )
    cat(sprintf(
      "❌ %-35s %s\n",
      playbook_name,
      sprintf("YAML error: %s", e$message)
    ))
    return(NULL)
  })
  if (is.null(yaml)) {
    next
  }

  # 3c. Validate required top-level fields
  for (field in c("name", "version", "description", "trigger", "steps")) {
    if (is.null(yaml[[field]])) {
      errors[[playbook_name]] <- c(
        errors[[playbook_name]],
        sprintf("Missing required field: '%s'", field)
      )
    }
  }

  # 3d. Validate name matches directory
  if (!is.null(yaml$name) && yaml$name != playbook_name) {
    errors[[playbook_name]] <- c(
      errors[[playbook_name]],
      sprintf(
        "Name mismatch: '%s' in YAML vs directory '%s'",
        yaml$name,
        playbook_name
      )
    )
  }

  # 3e. Validate name format (r- prefix, kebab-case)
  if (!is.null(yaml$name) && !grepl("^r-[a-z0-9]+(-[a-z0-9]+)*$", yaml$name)) {
    errors[[playbook_name]] <- c(
      errors[[playbook_name]],
      sprintf(
        "Name '%s' must be kebab-case starting with 'r-'",
        yaml$name
      )
    )
  }

  # 3f. Validate version (semver)
  if (
    !is.null(yaml$version) &&
      !grepl("^\\d+\\.\\d+\\.\\d+$", as.character(yaml$version))
  ) {
    errors[[playbook_name]] <- c(
      errors[[playbook_name]],
      sprintf("Version '%s' is not valid semver (X.Y.Z)", yaml$version)
    )
  }

  # 3g. Validate trigger
  valid_triggers <- c("manual", "automatic", "both")
  if (!is.null(yaml$trigger) && !yaml$trigger %in% valid_triggers) {
    errors[[playbook_name]] <- c(
      errors[[playbook_name]],
      sprintf(
        "Trigger '%s' must be one of: %s",
        yaml$trigger,
        paste(valid_triggers, collapse = ", ")
      )
    )
  }

  # 3h. Validate description length
  if (!is.null(yaml$description)) {
    desc_len <- nchar(yaml$description)
    if (desc_len < 10) {
      errors[[playbook_name]] <- c(
        errors[[playbook_name]],
        sprintf(
          "Description too short (%d chars, minimum 10)",
          desc_len
        )
      )
    }
    if (desc_len > 200) {
      warnings[[playbook_name]] <- c(
        warnings[[playbook_name]],
        sprintf(
          "Description is %d chars (recommended max 200)",
          desc_len
        )
      )
    }
  }

  # 3i. Validate context-mode
  valid_modes <- c("Fork", "Same", "Sandbox")
  if (
    !is.null(yaml[["context-mode"]]) &&
      !yaml[["context-mode"]] %in% valid_modes
  ) {
    errors[[playbook_name]] <- c(
      errors[[playbook_name]],
      sprintf(
        "context-mode '%s' must be one of: %s",
        yaml[["context-mode"]],
        paste(valid_modes, collapse = ", ")
      )
    )
  }

  # 3j. Validate steps
  if (!is.null(yaml$steps) && is.list(yaml$steps)) {
    step_ids <- character()
    for (i in seq_along(yaml$steps)) {
      step <- yaml$steps[[i]]
      step_label <- sprintf("step[%d]", i)

      # Step requires id
      if (is.null(step$id)) {
        errors[[playbook_name]] <- c(
          errors[[playbook_name]],
          sprintf("%s: missing 'id'", step_label)
        )
        next
      }

      # Step id format
      if (!grepl("^[a-z][a-z0-9]*(-[a-z][a-z0-9]*)*$", step$id)) {
        errors[[playbook_name]] <- c(
          errors[[playbook_name]],
          sprintf(
            "%s '%s': invalid id format (kebab-case)",
            step_label,
            step$id
          )
        )
      }

      # Check for duplicate ids
      if (step$id %in% step_ids) {
        errors[[playbook_name]] <- c(
          errors[[playbook_name]],
          sprintf("%s '%s': duplicate step id", step_label, step$id)
        )
      }
      step_ids <- c(step_ids, step$id)

      # Step requires inline-prompt
      if (is.null(step$`inline-prompt`)) {
        errors[[playbook_name]] <- c(
          errors[[playbook_name]],
          sprintf(
            "%s '%s': missing 'inline-prompt'",
            step_label,
            step$id
          )
        )
      } else if (nchar(step$`inline-prompt`) < 10) {
        errors[[playbook_name]] <- c(
          errors[[playbook_name]],
          sprintf(
            "%s '%s': inline-prompt too short (%d chars)",
            step_label,
            step$id,
            nchar(step$`inline-prompt`)
          )
        )
      }

      # Validate requires references
      if (!is.null(step$requires)) {
        for (req in step$requires) {
          if (!req %in% step_ids) {
            warnings[[playbook_name]] <- c(
              warnings[[playbook_name]],
              sprintf(
                "%s '%s': requires '%s' but that step hasn't been defined yet (forward reference?)",
                step_label,
                step$id,
                req
              )
            )
          }
        }
      }

      # Validate output format
      if (
        !is.null(step$output) &&
          !grepl("^[a-z][a-z0-9_]*$", step$output)
      ) {
        errors[[playbook_name]] <- c(
          errors[[playbook_name]],
          sprintf(
            "%s '%s': output '%s' must be snake_case",
            step_label,
            step$id,
            step$output
          )
        )
      }

      # Validate gate value
      if (!is.null(step$gate) && step$gate != "Confirm") {
        errors[[playbook_name]] <- c(
          errors[[playbook_name]],
          sprintf(
            "%s '%s': gate must be 'Confirm', got '%s'",
            step_label,
            step$id,
            step$gate
          )
        )
      }
    }
  }

  # 3k. Validate tags if present
  if (!is.null(yaml$tags)) {
    if (!is.character(yaml$tags) || length(yaml$tags) == 0) {
      errors[[playbook_name]] <- c(
        errors[[playbook_name]],
        "tags must be a non-empty array of strings"
      )
    } else if (length(yaml$tags) > 10) {
      warnings[[playbook_name]] <- c(
        warnings[[playbook_name]],
        sprintf("tags: %d tags (recommended max 10)", length(yaml$tags))
      )
    }
  }

  # Success
  cat(sprintf(
    "✅ %-35s v%-8s %d steps\n",
    playbook_name,
    yaml$version %||% "?",
    length(yaml$steps) %||% 0
  ))
}

# ── 4. Report ───────────────────────────────────────────────
cat("\n━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat(sprintf("Total: %d playbooks\n", length(dirs)))

total_errors <- if (length(errors) > 0) sum(sapply(errors, length)) else 0L
total_warnings <- if (length(warnings) > 0) {
  sum(sapply(warnings, length))
} else {
  0L
}

if (total_errors > 0) {
  cat(sprintf("\n❌ %d error(s) found:\n\n", total_errors))
  for (name in names(errors)) {
    cat(sprintf("  %s:\n", name))
    for (e in errors[[name]]) {
      cat(sprintf("    - %s\n", e))
    }
  }
}

if (total_warnings > 0) {
  cat(sprintf("\n⚠️  %d warning(s):\n\n", total_warnings))
  for (name in names(warnings)) {
    cat(sprintf("  %s:\n", name))
    for (w in warnings[[name]]) {
      cat(sprintf("    - %s\n", w))
    }
  }
}

if (total_errors == 0) {
  cat("\n✅ All playbooks valid!\n")
} else {
  cat(sprintf("\n❌ Validation failed with %d error(s)\n", total_errors))
  quit(status = 1)
}
