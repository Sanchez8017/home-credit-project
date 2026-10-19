# Reusable infrastructure for the Home Credit modeling notebook.
# Model specifications and preprocessing recipes will be added only after their
# notebook sections have been discussed and approved.

payment_difficulty_level <- "payment_difficulty"
no_payment_difficulty_level <- "no_payment_difficulty"

#' Load and validate prepared Home Credit modeling artifacts
#'
#' @param processed_dir Folder containing the preparation outputs.
#' @return A named list containing train, test, predictors, and recipe_path.
#' @details This function reads the artifacts but does not treat every prepared
#'   column as a predictor. predictor_names.rds is the authoritative allow-list.
load_modeling_artifacts <- function(processed_dir) {
  required_files <- c(
    train = "train_prepared.rds",
    test = "test_prepared.rds",
    predictors = "predictor_names.rds",
    recipe = "prep_recipe.rds"
  )

  paths <- stats::setNames(
    file.path(processed_dir, unname(required_files)),
    names(required_files)
  )
  missing <- required_files[!file.exists(paths)]

  if (length(missing) > 0) {
    stop(
      "Missing required modeling artifact(s): ",
      paste(unname(missing), collapse = ", "),
      call. = FALSE
    )
  }

  artifacts <- list(
    train = readRDS(paths[["train"]]),
    test = readRDS(paths[["test"]]),
    predictors = readRDS(paths[["predictors"]]),
    recipe_path = paths[["recipe"]]
  )

  validate_modeling_artifacts(
    artifacts$train,
    artifacts$test,
    artifacts$predictors
  )

  artifacts
}

#' Validate modeling roles and train/test compatibility
#'
#' @param train Prepared training data frame.
#' @param test Prepared scoring data frame.
#' @param predictors Character vector of approved predictor names.
#' @param id_col Applicant identifier.
#' @param outcome_col Binary outcome.
#' @return TRUE invisibly; otherwise stops with the failed checks.
validate_modeling_artifacts <- function(
    train,
    test,
    predictors,
    id_col = "SK_ID_CURR",
    outcome_col = "TARGET") {
  checks <- c(
    "training ID is missing" = id_col %in% names(train),
    "test ID is missing" = id_col %in% names(test),
    "training outcome is missing" = outcome_col %in% names(train),
    "test contains the outcome" = !outcome_col %in% names(test),
    "predictor manifest is empty" = length(predictors) > 0,
    "predictor names are duplicated" = !anyDuplicated(predictors),
    "training ID contains missing values" = !anyNA(train[[id_col]]),
    "test ID contains missing values" = !anyNA(test[[id_col]]),
    "training ID is duplicated" = !anyDuplicated(train[[id_col]]),
    "test ID is duplicated" = !anyDuplicated(test[[id_col]]),
    "train and test IDs overlap" =
      length(intersect(train[[id_col]], test[[id_col]])) == 0,
    "ID appears in predictor manifest" = !id_col %in% predictors,
    "outcome appears in predictor manifest" = !outcome_col %in% predictors,
    "training predictors are missing" = all(predictors %in% names(train)),
    "test predictors are missing" = all(predictors %in% names(test)),
    "train/test columns are incompatible" = setequal(
      setdiff(names(train), outcome_col),
      names(test)
    ),
    "outcome is not binary 0/1" = setequal(
      sort(unique(train[[outcome_col]])),
      c(0, 1)
    )
  )

  if (!all(checks)) {
    stop(
      "Modeling artifact validation failed: ",
      paste(names(checks)[!checks], collapse = "; "),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

#' Convert TARGET to an explicitly ordered outcome factor
#'
#' @param data Modeling data frame.
#' @param outcome_col Name of the numeric 0/1 outcome.
#' @return Data with payment difficulty as the first factor level.
#' @details yardstick treats the first factor level as the event by default.
prepare_model_outcome <- function(data, outcome_col = "TARGET") {
  if (!outcome_col %in% names(data)) {
    stop("Outcome column is missing: ", outcome_col, call. = FALSE)
  }

  observed <- data[[outcome_col]]
  if (anyNA(observed) || !setequal(sort(unique(observed)), c(0, 1))) {
    stop("Outcome must be complete and contain only 0 and 1.", call. = FALSE)
  }

  data[[outcome_col]] <- factor(
    observed,
    levels = c(1, 0),
    labels = c(payment_difficulty_level, no_payment_difficulty_level)
  )

  data
}

#' Create reproducible stratified cross-validation folds
#'
#' @param data Modeling data with a factor outcome.
#' @param outcome_col Outcome used for stratification.
#' @param v Number of folds.
#' @param seed Random seed.
#' @return An rsample vfold_cv object.
create_stratified_folds <- function(
    data,
    outcome_col = "TARGET",
    v = 3L,
    seed = 20261008L) {
  if (!requireNamespace("rsample", quietly = TRUE)) {
    stop("Package 'rsample' is required.", call. = FALSE)
  }
  if (!outcome_col %in% names(data)) {
    stop("Outcome column is missing: ", outcome_col, call. = FALSE)
  }
  if (!is.factor(data[[outcome_col]])) {
    stop("Outcome must be a factor before creating folds.", call. = FALSE)
  }
  if (!identical(levels(data[[outcome_col]])[1], payment_difficulty_level)) {
    stop("Payment difficulty must be the first outcome level.", call. = FALSE)
  }
  if (v < 2L) {
    stop("v must be at least 2.", call. = FALSE)
  }

  set.seed(seed)
  rsample::vfold_cv(
    data,
    v = as.integer(v),
    strata = !!rlang::sym(outcome_col)
  )
}

#' Validate fold coverage, separation, and stratification inputs
#'
#' @param folds An rsample vfold_cv object.
#' @param id_col Unique applicant identifier.
#' @param outcome_col Factor outcome.
#' @param expected_v Expected number of folds.
#' @return TRUE invisibly; otherwise stops with the failed checks.
validate_cv_folds <- function(
    folds,
    id_col = "SK_ID_CURR",
    outcome_col = "TARGET",
    expected_v = 3L) {
  if (!inherits(folds, "vfold_cv")) {
    stop("folds must be an rsample vfold_cv object.", call. = FALSE)
  }

  source_data <- folds$splits[[1]]$data
  source_ids <- source_data[[id_col]]
  assessment_ids <- lapply(
    folds$splits,
    function(split) rsample::assessment(split)[[id_col]]
  )
  analysis_ids <- lapply(
    folds$splits,
    function(split) rsample::analysis(split)[[id_col]]
  )
  all_assessment_ids <- unlist(assessment_ids, use.names = FALSE)
  assessment_frequency <- table(all_assessment_ids)

  checks <- c(
    "unexpected number of folds" = nrow(folds) == expected_v,
    "source IDs are incomplete" = !anyNA(source_ids),
    "source IDs are duplicated" = !anyDuplicated(source_ids),
    "analysis and assessment overlap" = all(vapply(
      seq_along(assessment_ids),
      function(i) length(intersect(analysis_ids[[i]], assessment_ids[[i]])) == 0,
      logical(1)
    )),
    "an assessment fold contains duplicate IDs" = all(vapply(
      assessment_ids,
      function(ids) !anyDuplicated(ids),
      logical(1)
    )),
    "assessment folds do not cover every applicant" = setequal(
      all_assessment_ids,
      source_ids
    ),
    "an applicant appears in multiple assessment folds" = all(
      assessment_frequency == 1L
    ),
    "outcome is missing from fold data" = outcome_col %in% names(source_data),
    "payment difficulty is not the event level" = identical(
      levels(source_data[[outcome_col]])[1],
      payment_difficulty_level
    )
  )

  if (!all(checks)) {
    stop(
      "Cross-validation fold validation failed: ",
      paste(names(checks)[!checks], collapse = "; "),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

#' Summarize cross-validation fold sizes and event prevalence
#'
#' @param folds Validated rsample folds.
#' @param outcome_col Factor outcome.
#' @return Data frame with analysis and assessment counts and event rates.
summarize_cv_folds <- function(folds, outcome_col = "TARGET") {
  summaries <- lapply(seq_len(nrow(folds)), function(i) {
    analysis_data <- rsample::analysis(folds$splits[[i]])
    assessment_data <- rsample::assessment(folds$splits[[i]])

    data.frame(
      fold = folds$id[[i]],
      analysis_applicants = nrow(analysis_data),
      assessment_applicants = nrow(assessment_data),
      analysis_events = sum(
        analysis_data[[outcome_col]] == payment_difficulty_level
      ),
      assessment_events = sum(
        assessment_data[[outcome_col]] == payment_difficulty_level
      ),
      analysis_event_rate = mean(
        analysis_data[[outcome_col]] == payment_difficulty_level
      ),
      assessment_event_rate = mean(
        assessment_data[[outcome_col]] == payment_difficulty_level
      )
    )
  })

  do.call(rbind, summaries)
}

#' Define the common model-comparison metrics
#'
#' @return A yardstick metric set containing ROC-AUC and accuracy.
model_metric_set <- function() {
  if (!requireNamespace("yardstick", quietly = TRUE)) {
    stop("Package 'yardstick' is required.", call. = FALSE)
  }

  yardstick::metric_set(yardstick::roc_auc, yardstick::accuracy)
}

#' Summarize fold-level candidate metrics
#'
#' @param metrics Data frame containing .metric and .estimate.
#' @return One row per metric with mean, standard deviation, and standard error.
summarize_resample_metrics <- function(metrics) {
  required <- c(".metric", ".estimate")
  if (!all(required %in% names(metrics))) {
    stop(
      "metrics must contain columns: ",
      paste(required, collapse = ", "),
      call. = FALSE
    )
  }

  metrics |>
    dplyr::group_by(.data$.metric) |>
    dplyr::summarise(
      mean = mean(.data$.estimate),
      std_error = stats::sd(.data$.estimate) / sqrt(dplyr::n()),
      folds = dplyr::n(),
      .groups = "drop"
    )
}

#' Confirm candidate results use the expected resample IDs
#'
#' @param results Named list of result data frames containing a resample ID column.
#' @param expected_ids Character vector of approved resample IDs.
#' @param id_col Resample ID column name.
#' @return TRUE invisibly; otherwise stops with incompatible candidate names.
assert_common_resamples <- function(results, expected_ids, id_col = "id") {
  if (!length(results)) {
    stop("results must contain at least one candidate result.", call. = FALSE)
  }

  valid <- vapply(results, function(result) {
    id_col %in% names(result) &&
      setequal(unique(result[[id_col]]), expected_ids)
  }, logical(1))

  if (!all(valid)) {
    labels <- names(results)
    if (is.null(labels)) labels <- paste0("candidate_", seq_along(results))
    stop(
      "Candidate results do not use the approved resamples: ",
      paste(labels[!valid], collapse = ", "),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

#' Evaluate the majority-class benchmark on approved resamples
#'
#' @param folds Stratified rsample folds.
#' @param outcome_col Factor outcome with payment difficulty first.
#' @return Fold-level ROC-AUC and accuracy in tidymodels metric format.
evaluate_majority_benchmark <- function(folds, outcome_col = "TARGET") {
  if (!requireNamespace("yardstick", quietly = TRUE)) {
    stop("Package 'yardstick' is required.", call. = FALSE)
  }

  results <- lapply(seq_len(nrow(folds)), function(i) {
    analysis_data <- rsample::analysis(folds$splits[[i]])
    assessment_data <- rsample::assessment(folds$splits[[i]])
    event_rate <- mean(
      analysis_data[[outcome_col]] == payment_difficulty_level
    )
    predicted_class <- factor(
      rep(no_payment_difficulty_level, nrow(assessment_data)),
      levels = levels(assessment_data[[outcome_col]])
    )

    data.frame(
      id = folds$id[[i]],
      .metric = c("roc_auc", "accuracy"),
      .estimator = "binary",
      .estimate = c(
        yardstick::roc_auc_vec(
          truth = assessment_data[[outcome_col]],
          estimate = rep(event_rate, nrow(assessment_data)),
          event_level = "first"
        ),
        yardstick::accuracy_vec(
          truth = assessment_data[[outcome_col]],
          estimate = predicted_class
        )
      )
    )
  })

  do.call(rbind, results)
}

#' Fit one workflow on approved resamples
#'
#' @param workflow A parsnip workflow.
#' @param folds Approved resamples.
#' @param metrics Yardstick metric set.
#' @param seed Seed used by any stochastic engine operations.
#' @param save_pred Whether to retain out-of-fold predictions.
#' @return A tune resample-results object.
fit_resampled_workflow <- function(
    workflow,
    folds,
    metrics = model_metric_set(),
    seed = 20261008L,
    save_pred = FALSE) {
  required <- c("tune", "workflows")
  missing <- required[
    !vapply(required, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing)) {
    stop(
      "Missing resampling package(s): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  set.seed(seed)
  tune::fit_resamples(
    workflow,
    resamples = folds,
    metrics = metrics,
    control = tune::control_resamples(
      save_pred = save_pred,
      verbose = FALSE,
      parallel_over = "resamples"
    )
  )
}

#' Extract fold-level metrics from resample results
#'
#' @param resample_result A tune resample-results object.
#' @param model_label Label added to the output.
#' @return Data frame with model, resample ID, metric, and estimate.
collect_fold_metrics <- function(resample_result, model_label) {
  metrics <- tune::collect_metrics(resample_result, summarize = FALSE)
  required <- c("id", ".metric", ".estimate")
  if (!all(required %in% names(metrics))) {
    stop("Resample results lack required fold-level metrics.", call. = FALSE)
  }

  data.frame(
    model = model_label,
    id = metrics$id,
    .metric = metrics$.metric,
    .estimate = metrics$.estimate,
    stringsAsFactors = FALSE
  )
}

#' Run and validate one candidate model workflow
#'
#' @param model_label Human-readable candidate name.
#' @param model_spec A parsnip model specification.
#' @param recipe An unprepped recipes recipe.
#' @param folds Approved resamples.
#' @param metrics Yardstick metric set.
#' @param seed Reproducibility seed.
#' @param retain_predictions Whether to retain out-of-fold predictions.
#' @return A compact list containing fold metrics, out-of-fold predictions,
#'   elapsed seconds, and notes.
run_candidate_model <- function(
    model_label,
    model_spec,
    recipe,
    folds,
    metrics = model_metric_set(),
    seed = 20261008L,
    retain_predictions = FALSE) {
  if (!requireNamespace("workflows", quietly = TRUE)) {
    stop("Package 'workflows' is required.", call. = FALSE)
  }

  workflow <- workflows::workflow() |>
    workflows::add_recipe(recipe) |>
    workflows::add_model(model_spec)

  timing <- system.time({
    result <- fit_resampled_workflow(
      workflow = workflow,
      folds = folds,
      metrics = metrics,
      seed = seed,
      save_pred = retain_predictions
    )
  })

  notes <- tune::collect_notes(result)
  error_notes <- if (nrow(notes)) notes[notes$type == "error", , drop = FALSE] else notes
  if (nrow(error_notes)) {
    stop(
      "Candidate '", model_label, "' failed in one or more resamples: ",
      paste(unique(error_notes$note), collapse = "; "),
      call. = FALSE
    )
  }

  fold_metrics <- collect_fold_metrics(result, model_label)
  if (!setequal(unique(fold_metrics$id), folds$id)) {
    stop(
      "Candidate '", model_label, "' did not return every approved fold.",
      call. = FALSE
    )
  }

  list(
    model = model_label,
    metrics = fold_metrics,
    predictions = if (retain_predictions) tune::collect_predictions(result) else NULL,
    elapsed_seconds = unname(timing[["elapsed"]]),
    notes = notes
  )
}

#' Combine candidate metrics and runtimes
#'
#' @param candidate_runs Named or unnamed list returned by run_candidate_model().
#' @return List with fold_metrics and runtime data frames.
combine_candidate_runs <- function(candidate_runs) {
  if (!length(candidate_runs)) {
    stop("candidate_runs must not be empty.", call. = FALSE)
  }

  list(
    fold_metrics = dplyr::bind_rows(lapply(candidate_runs, `[[`, "metrics")),
    runtime = data.frame(
      model = vapply(candidate_runs, `[[`, character(1), "model"),
      elapsed_seconds = vapply(
        candidate_runs, `[[`, numeric(1), "elapsed_seconds"
      ),
      row.names = NULL
    )
  )
}

#' Draw a reproducible stratified tuning sample
#'
#' @param data Full modeling data.
#' @param size Approximate number of rows to retain.
#' @param outcome_col Outcome used for stratification.
#' @param seed Reproducibility seed.
#' @return Stratified sample preserving the original row columns.
create_tuning_sample <- function(
    data,
    size = 5000L,
    outcome_col = "TARGET",
    seed = 20261008L) {
  if (size < 2L || size >= nrow(data)) {
    stop("size must be at least 2 and smaller than the full data.", call. = FALSE)
  }
  if (!outcome_col %in% names(data)) {
    stop("Outcome column is missing: ", outcome_col, call. = FALSE)
  }

  set.seed(seed)
  split <- rsample::initial_split(
    data,
    prop = size / nrow(data),
    strata = !!rlang::sym(outcome_col)
  )
  rsample::training(split)
}

#' Run a compact randomized tuning search
#'
#' @param workflow Workflow containing tuneable model parameters.
#' @param folds Approved tuning resamples.
#' @param grid Data frame of candidate parameter combinations.
#' @param metrics Yardstick metric set.
#' @param seed Reproducibility seed.
#' @param selection_metric Metric used to choose the best configuration.
#' @return Compact list of summary/fold metrics, best parameters, notes, and runtime.
run_randomized_tuning <- function(
    workflow,
    folds,
    grid,
    metrics = model_metric_set(),
    seed = 20261008L,
    selection_metric = "roc_auc") {
  set.seed(seed)
  timing <- system.time({
    result <- tune::tune_grid(
      workflow,
      resamples = folds,
      grid = grid,
      metrics = metrics,
      control = tune::control_grid(
        save_pred = FALSE,
        verbose = FALSE,
        parallel_over = "resamples"
      )
    )
  })

  notes <- tune::collect_notes(result)
  error_notes <- if (nrow(notes)) notes[notes$type == "error", , drop = FALSE] else notes
  if (nrow(error_notes)) {
    stop(
      "Randomized tuning produced fit errors: ",
      paste(unique(error_notes$note), collapse = "; "),
      call. = FALSE
    )
  }

  list(
    summary_metrics = tune::collect_metrics(result, summarize = TRUE),
    fold_metrics = tune::collect_metrics(result, summarize = FALSE),
    best_parameters = tune::select_best(result, metric = selection_metric),
    notes = notes,
    elapsed_seconds = unname(timing[["elapsed"]])
  )
}

#' Fit, save, reload, and verify a final workflow
#'
#' @param workflow Locked workflow specification.
#' @param training_data Complete development data.
#' @param verification_data Small training-only data frame for round-trip checks.
#' @param model_path Destination RDS path for the fitted workflow.
#' @param metadata_path Destination RDS path for compact model metadata.
#' @param metadata Named list of pre-fit metadata.
#' @return Fitted workflow, completed metadata, and verification probabilities.
fit_save_verify_final_workflow <- function(
    workflow,
    training_data,
    verification_data,
    model_path,
    metadata_path,
    metadata = list()) {
  model_dir <- dirname(model_path)
  metadata_dir <- dirname(metadata_path)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(metadata_dir, recursive = TRUE, showWarnings = FALSE)

  timing <- system.time({
    fitted_workflow <- generics::fit(workflow, data = training_data)
  })

  probabilities_before <- predict(
    fitted_workflow,
    new_data = verification_data,
    type = "prob"
  )

  completed_metadata <- c(
    metadata,
    list(
      fitted_at = Sys.time(),
      training_rows = nrow(training_data),
      training_columns = ncol(training_data),
      elapsed_seconds = unname(timing[["elapsed"]]),
      r_version = R.version.string,
      package_versions = vapply(
        c("recipes", "workflows", "parsnip", "xgboost"),
        function(package) as.character(utils::packageVersion(package)),
        character(1)
      )
    )
  )

  saveRDS(fitted_workflow, model_path)
  saveRDS(completed_metadata, metadata_path)

  reloaded_workflow <- readRDS(model_path)
  reloaded_metadata <- readRDS(metadata_path)
  probabilities_after <- predict(
    reloaded_workflow,
    new_data = verification_data,
    type = "prob"
  )

  checks <- c(
    "model artifact was not written" = file.exists(model_path),
    "metadata artifact was not written" = file.exists(metadata_path),
    "reloaded predictions differ" = isTRUE(all.equal(
      probabilities_before,
      probabilities_after,
      tolerance = 0
    )),
    "reloaded metadata differs" = identical(
      completed_metadata,
      reloaded_metadata
    )
  )
  if (!all(checks)) {
    stop(
      "Final-model artifact validation failed: ",
      paste(names(checks)[!checks], collapse = "; "),
      call. = FALSE
    )
  }

  list(
    fitted_workflow = reloaded_workflow,
    metadata = reloaded_metadata,
    verification_probabilities = probabilities_after,
    checks = checks
  )
}

#' Load and verify an existing fitted-workflow artifact
#'
#' Used during development renders to avoid duplicating large fitted workflows
#' in the result cache or refitting an unchanged final model.
load_verify_final_workflow <- function(
    model_path,
    metadata_path,
    verification_data) {
  if (!requireNamespace("workflows", quietly = TRUE)) {
    stop("Package 'workflows' is required to load the fitted workflow.", call. = FALSE)
  }
  if (!file.exists(model_path) || !file.exists(metadata_path)) {
    stop("Saved model or metadata artifact is missing.", call. = FALSE)
  }

  fitted_workflow <- readRDS(model_path)
  metadata <- readRDS(metadata_path)
  probabilities <- predict(
    fitted_workflow,
    new_data = verification_data,
    type = "prob"
  )

  checks <- c(
    "model artifact was not readable" = inherits(fitted_workflow, "workflow"),
    "metadata artifact was not readable" = is.list(metadata),
    "reloaded predictions contain missing values" = !anyNA(probabilities),
    "metadata training-row count is invalid" =
      is.numeric(metadata$training_rows) &&
      length(metadata$training_rows) == 1L &&
      metadata$training_rows >= nrow(verification_data)
  )
  if (!all(checks)) {
    stop(
      "Saved final-model validation failed: ",
      paste(names(checks)[!checks], collapse = "; "),
      call. = FALSE
    )
  }

  list(
    fitted_workflow = fitted_workflow,
    metadata = metadata,
    verification_probabilities = probabilities,
    checks = checks
  )
}

#' Run resampling while retaining out-of-fold probabilities
#'
#' @param model_label Human-readable model label.
#' @param workflow Locked workflow.
#' @param folds Approved resamples.
#' @param metrics Yardstick metric set.
#' @param seed Reproducibility seed.
#' @return Compact metrics, out-of-fold predictions, notes, and runtime.
run_oof_workflow <- function(
    model_label,
    workflow,
    folds,
    metrics = model_metric_set(),
    seed = 20261008L) {
  set.seed(seed)
  timing <- system.time({
    result <- tune::fit_resamples(
      workflow,
      resamples = folds,
      metrics = metrics,
      control = tune::control_resamples(
        save_pred = TRUE,
        verbose = FALSE,
        parallel_over = "resamples"
      )
    )
  })

  notes <- tune::collect_notes(result)
  error_notes <- if (nrow(notes)) notes[notes$type == "error", , drop = FALSE] else notes
  if (nrow(error_notes)) {
    stop(
      "Out-of-fold run for '", model_label, "' produced errors: ",
      paste(unique(error_notes$note), collapse = "; "),
      call. = FALSE
    )
  }

  list(
    model = model_label,
    metrics = tune::collect_metrics(result, summarize = FALSE),
    predictions = tune::collect_predictions(result),
    notes = notes,
    elapsed_seconds = unname(timing[["elapsed"]])
  )
}

#' Assign a broad business theme to baked predictor names
#'
#' @param feature Character vector of baked feature names.
#' @return Character vector of business-oriented feature groups.
classify_feature_theme <- function(feature) {
  dplyr::case_when(
    grepl("^EXT_SOURCE", feature) ~ "External risk score",
    grepl(
      "annuity_to_income|credit_to_income|financing_to_goods|^AMT_(INCOME|CREDIT|ANNUITY|GOODS)",
      feature
    ) ~ "Affordability and requested financing",
    grepl(
      "^(bureau_|prev_|inst_|pos_|has_credit_card|has_unmatched_history|has_bureau|has_previous_application|has_installments|has_pos|sources_present|no_history_any_source)",
      feature
    ) ~ "Supplementary credit and repayment history",
    grepl("CONTRACT_TYPE|FLAG_OWN|employment|registration|phone_change", feature) ~
      "Application and product information",
    TRUE ~ "Other approved application information"
  )
}

#' Summarize out-of-fold performance within one subgroup field
#'
#' @param data Data frame containing group, truth, and probability columns.
#' @param group_col Subgroup column name.
#' @param truth_col Factor outcome column name.
#' @param probability_col Event-probability column name.
#' @param min_applicants Minimum group size for performance estimates.
#' @param min_events Minimum event count for performance estimates.
#' @return One row per group with descriptive and guarded performance metrics.
summarize_subgroup_performance <- function(
    data,
    group_col,
    truth_col = "TARGET",
    probability_col = ".pred_payment_difficulty",
    min_applicants = 1000L,
    min_events = 100L) {
  required <- c(group_col, truth_col, probability_col)
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop(
      "Subgroup data are missing: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  group_value <- as.character(data[[group_col]])
  group_value[is.na(group_value) | group_value == ""] <- "(Missing)"
  groups <- sort(unique(group_value))

  rows <- lapply(groups, function(group) {
    index <- group_value == group
    truth <- data[[truth_col]][index]
    probability <- data[[probability_col]][index]
    applicants <- sum(index)
    events <- sum(truth == payment_difficulty_level)
    eligible <- applicants >= min_applicants &&
      events >= min_events &&
      length(unique(truth)) == 2L

    data.frame(
      audit_dimension = group_col,
      group = group,
      applicants = applicants,
      events = events,
      observed_event_rate = mean(truth == payment_difficulty_level),
      mean_predicted_risk = mean(probability),
      roc_auc = if (eligible) {
        yardstick::roc_auc_vec(
          truth = truth,
          estimate = probability,
          event_level = "first"
        )
      } else {
        NA_real_
      },
      brier_score = if (eligible) {
        yardstick::brier_class_vec(
          truth = truth,
          estimate = probability,
          event_level = "first"
        )
      } else {
        NA_real_
      },
      performance_status = if (eligible) "Reported" else "Suppressed",
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}
