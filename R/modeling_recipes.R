# Fold-safe feature manifests and preprocessing recipes for Home Credit models.
# Fixed decision-time cleaning and aggregation occur in data preparation. Every
# data-learned operation in this file is estimated when recipes::prep() runs.

required_recipe_packages <- c("recipes", "rlang", "tibble", "tidyselect")
missing_recipe_packages <- required_recipe_packages[
  !vapply(required_recipe_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_recipe_packages) > 0) {
  stop(
    "Missing recipe package(s): ",
    paste(missing_recipe_packages, collapse = ", "),
    call. = FALSE
  )
}

#' Train-learned quantile capping as a recipes step
#'
#' Adds capped copies while retaining the original columns. Quantiles are learned
#' only in prep(), so resampling workflows estimate them from each analysis fold.
step_cap_quantile <- function(
    recipe,
    ...,
    role = "predictor",
    trained = FALSE,
    lower = 0.01,
    upper = 0.99,
    caps = NULL,
    suffix = "_cap",
    skip = FALSE,
    id = recipes::rand_id("cap_quantile")) {
  recipes::add_step(
    recipe,
    step_cap_quantile_new(
      terms = rlang::enquos(...),
      role = role,
      trained = trained,
      lower = lower,
      upper = upper,
      caps = caps,
      suffix = suffix,
      skip = skip,
      id = id
    )
  )
}

step_cap_quantile_new <- function(
    terms, role, trained, lower, upper, caps, suffix, skip, id) {
  recipes::step(
    subclass = "cap_quantile",
    terms = terms,
    role = role,
    trained = trained,
    lower = lower,
    upper = upper,
    caps = caps,
    suffix = suffix,
    skip = skip,
    id = id
  )
}

prep.step_cap_quantile <- function(x, training, info = NULL, ...) {
  col_names <- recipes::recipes_eval_select(x$terms, training, info)
  recipes::check_type(training[, col_names], types = c("double", "integer"))
  caps <- lapply(col_names, function(column) {
    stats::quantile(
      training[[column]],
      probs = c(x$lower, x$upper),
      na.rm = TRUE,
      names = FALSE
    )
  })
  names(caps) <- col_names

  step_cap_quantile_new(
    terms = x$terms,
    role = x$role,
    trained = TRUE,
    lower = x$lower,
    upper = x$upper,
    caps = caps,
    suffix = x$suffix,
    skip = x$skip,
    id = x$id
  )
}

bake.step_cap_quantile <- function(object, new_data, ...) {
  col_names <- names(object$caps)
  recipes::check_new_data(col_names, object, new_data)

  for (column in col_names) {
    limits <- object$caps[[column]]
    new_data[[paste0(column, object$suffix)]] <- pmin(
      pmax(new_data[[column]], limits[1]),
      limits[2]
    )
  }
  new_data
}

print.step_cap_quantile <- function(
    x,
    width = max(20, options()$width - 35),
    ...) {
  title <- sprintf(
    "Quantile caps (%.0f%% / %.0f%%, analysis-fold learned) for ",
    100 * x$lower,
    100 * x$upper
  )
  recipes::print_step(names(x$caps), x$terms, x$trained, title, width)
  invisible(x)
}

tidy.step_cap_quantile <- function(x, ...) {
  if (recipes::is_trained(x)) {
    result <- tibble::tibble(
      terms = names(x$caps),
      lower_prob = x$lower,
      upper_prob = x$upper,
      lower_cap = vapply(x$caps, `[[`, numeric(1), 1),
      upper_cap = vapply(x$caps, `[[`, numeric(1), 2)
    )
  } else {
    result <- tibble::tibble(
      terms = recipes::sel2char(x$terms),
      lower_prob = x$lower,
      upper_prob = x$upper,
      lower_cap = NA_real_,
      upper_cap = NA_real_
    )
  }
  result$id <- x$id
  result
}

required_pkgs.step_cap_quantile <- function(x, ...) c("recipes", "stats")

registerS3method(
  "prep", "step_cap_quantile", prep.step_cap_quantile,
  envir = asNamespace("recipes")
)
registerS3method(
  "bake", "step_cap_quantile", bake.step_cap_quantile,
  envir = asNamespace("recipes")
)
registerS3method("print", "step_cap_quantile", print.step_cap_quantile)
registerS3method(
  "tidy", "step_cap_quantile", tidy.step_cap_quantile,
  envir = asNamespace("generics")
)
registerS3method(
  "required_pkgs", "step_cap_quantile", required_pkgs.step_cap_quantile,
  envir = asNamespace("generics")
)

#' Identify fields reserved for governance and subgroup auditing
#'
#' @param data Joined, pre-recipe applicant data.
#' @return Character vector of audit-only field names present in data.
get_audit_fields <- function(data) {
  audit_fixed <- c(
    "CODE_GENDER", "CODE_GENDER_XNA", "DAYS_BIRTH", "age_years",
    "NAME_FAMILY_STATUS", "CNT_CHILDREN", "CNT_FAM_MEMBERS",
    "OCCUPATION_TYPE", "ORGANIZATION_TYPE", "ORGANIZATION_TYPE_XNA",
    "NAME_EDUCATION_TYPE", "NAME_HOUSING_TYPE"
  )
  audit_geography <- grep(
    "^(REGION_|REG_REGION_|REG_CITY_|LIVE_REGION_|LIVE_CITY_)",
    names(data),
    value = TRUE
  )
  intersect(c(audit_fixed, audit_geography), names(data))
}

#' Identify fixed supplementary-history fields
#'
#' @param data Joined, pre-recipe applicant data.
#' @return Character vector of supplementary feature names present in data.
get_supplementary_fields <- function(data) {
  pattern <- paste0(
    "^(bureau_|prev_|inst_|pos_|has_credit_card$|has_unmatched_history$|",
    "has_bureau$|has_previous_application$|has_installments$|has_pos$|",
    "sources_present$|no_history_any_source$)"
  )
  grep(pattern, names(data), value = TRUE)
}

#' Create reproducible application-only and full-history source manifests
#'
#' @param data Joined, pre-recipe applicant data.
#' @param id_col Applicant identifier.
#' @param outcome_col Outcome name.
#' @return Named list with application, supplementary, and full predictor names.
build_feature_manifests <- function(
    data,
    id_col = "SK_ID_CURR",
    outcome_col = "TARGET") {
  audit <- get_audit_fields(data)
  quality <- intersect("inst_schedule_conflict", names(data))
  excluded <- c(id_col, outcome_col, audit, quality)
  full <- setdiff(names(data), excluded)
  supplementary <- intersect(get_supplementary_fields(data), full)
  application <- setdiff(full, supplementary)

  if (!length(application) || !length(supplementary)) {
    stop(
      "Both application and supplementary manifests must be non-empty.",
      call. = FALSE
    )
  }

  list(
    application = application,
    supplementary = supplementary,
    full = full,
    audit = audit,
    quality_check = quality
  )
}

#' Build an untrained, fold-safe preprocessing recipe
#'
#' @param data Joined, pre-recipe training data.
#' @param feature_set Either "application" or "full".
#' @return An unprepped recipes recipe. No parameters are estimated here.
build_model_recipe <- function(data, feature_set = c("application", "full")) {
  feature_set <- match.arg(feature_set)
  manifests <- build_feature_manifests(data)
  selected_predictors <- if (feature_set == "application") {
    manifests$application
  } else {
    manifests$full
  }

  retained_nonpredictors <- c(
    "SK_ID_CURR", "TARGET", manifests$audit,
    if (feature_set == "full") manifests$quality_check else character(0)
  )
  recipe_data <- data[unique(c(retained_nonpredictors, selected_predictors))]

  amount_vars <- c(
    "AMT_INCOME_TOTAL", "AMT_CREDIT", "AMT_ANNUITY", "AMT_GOODS_PRICE"
  )

  recipe <- recipes::recipe(TARGET ~ ., data = recipe_data) |>
    recipes::update_role(SK_ID_CURR, new_role = "id")

  audit_in_recipe <- intersect(manifests$audit, names(recipe_data))
  if (length(audit_in_recipe)) {
    recipe <- recipes::update_role(
      recipe,
      tidyselect::all_of(audit_in_recipe),
      new_role = "audit"
    )
  }

  if (feature_set == "full" && length(manifests$quality_check)) {
    recipe <- recipes::update_role(
      recipe,
      tidyselect::all_of(manifests$quality_check),
      new_role = "quality_check"
    )
  }

  recipe |>
    step_cap_quantile(
      !!!rlang::syms(amount_vars),
      lower = 0.01,
      upper = 0.99,
      id = "cap_amounts"
    ) |>
    recipes::step_mutate(
      AMT_INCOME_TOTAL_log1p = log1p(AMT_INCOME_TOTAL),
      AMT_CREDIT_log1p = log1p(AMT_CREDIT),
      AMT_ANNUITY_log1p = log1p(AMT_ANNUITY),
      AMT_GOODS_PRICE_log1p = log1p(AMT_GOODS_PRICE),
      id = "log1p_amounts"
    ) |>
    recipes::step_mutate(
      financing_to_goods_bin = financing_to_goods,
      id = "copy_financing_to_goods"
    ) |>
    recipes::step_discretize(
      financing_to_goods_bin,
      num_breaks = 5,
      min_unique = 10,
      id = "bin_financing_to_goods"
    ) |>
    recipes::step_indicate_na(
      EXT_SOURCE_1, EXT_SOURCE_2, EXT_SOURCE_3, OWN_CAR_AGE,
      id = "indicate_missing"
    ) |>
    recipes::step_impute_median(
      recipes::all_numeric_predictors(),
      id = "impute_median"
    ) |>
    recipes::step_novel(
      recipes::all_nominal_predictors(),
      new_level = "OTHER_UNSEEN",
      id = "novel_level"
    ) |>
    recipes::step_unknown(
      recipes::all_nominal_predictors(),
      new_level = "unknown",
      id = "unknown_level"
    ) |>
    recipes::step_dummy(
      recipes::all_nominal_predictors(),
      id = "dummy"
    ) |>
    recipes::step_interact(
      terms = ~ tidyselect::starts_with("NAME_CONTRACT_TYPE_Revolving"):
        annuity_to_income +
        tidyselect::starts_with("NAME_CONTRACT_TYPE_Revolving"):
          credit_to_income +
        tidyselect::starts_with("NAME_CONTRACT_TYPE_Revolving"):
          financing_to_goods,
      id = "contract_interactions"
    ) |>
    recipes::step_zv(
      recipes::all_predictors(),
      -tidyselect::contains("OTHER_UNSEEN"),
      id = "zero_variance"
    )
}

#' Validate baked analysis and assessment outputs
#'
#' @param prepped_recipe Trained recipe.
#' @param analysis_baked Baked analysis-fold data.
#' @param assessment_baked Baked assessment-fold data.
#' @return TRUE invisibly; otherwise stops with failed checks.
validate_baked_fold <- function(
    prepped_recipe,
    analysis_baked,
    assessment_baked) {
  roles <- summary(prepped_recipe)
  predictors <- roles$variable[roles$role == "predictor"]
  audit <- roles$variable[roles$role == "audit"]

  checks <- c(
    "analysis and assessment columns differ" = identical(
      names(analysis_baked), names(assessment_baked)
    ),
    "analysis predictors contain missing values" = !anyNA(
      analysis_baked[predictors]
    ),
    "assessment predictors contain missing values" = !anyNA(
      assessment_baked[predictors]
    ),
    "analysis predictors are not all numeric" = all(vapply(
      analysis_baked[predictors], is.numeric, logical(1)
    )),
    "assessment predictors are not all numeric" = all(vapply(
      assessment_baked[predictors], is.numeric, logical(1)
    )),
    "ID became a predictor" = !"SK_ID_CURR" %in% predictors,
    "outcome became a predictor" = !"TARGET" %in% predictors,
    "audit field became a predictor" = !any(audit %in% predictors),
    "analysis IDs are duplicated" = !anyDuplicated(analysis_baked$SK_ID_CURR),
    "assessment IDs are duplicated" = !anyDuplicated(assessment_baked$SK_ID_CURR)
  )

  if (!all(checks)) {
    stop(
      "Baked-fold validation failed: ",
      paste(names(checks)[!checks], collapse = "; "),
      call. = FALSE
    )
  }

  invisible(TRUE)
}

#' Build the simple application-only logistic benchmark recipe
#'
#' @param data Joined, pre-recipe training data.
#' @return An unprepped recipe using a small business-grounded predictor set.
#' @details Amounts are capped within each analysis fold and the capped copies
#'   replace the raw amount columns. No supplementary or audit fields are used.
build_simple_logistic_recipe <- function(data) {
  amount_vars <- c(
    "AMT_INCOME_TOTAL", "AMT_CREDIT", "AMT_ANNUITY", "AMT_GOODS_PRICE"
  )
  benchmark_predictors <- c(
    "EXT_SOURCE_1", "EXT_SOURCE_2", "EXT_SOURCE_3",
    amount_vars,
    "annuity_to_income", "credit_to_income", "financing_to_goods",
    "NAME_CONTRACT_TYPE", "employment_years"
  )
  required <- c("SK_ID_CURR", "TARGET", benchmark_predictors)
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop(
      "Simple benchmark fields are missing: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  recipes::recipe(
    TARGET ~ .,
    data = data[required]
  ) |>
    recipes::update_role(SK_ID_CURR, new_role = "id") |>
    step_cap_quantile(
      !!!rlang::syms(amount_vars),
      lower = 0.01,
      upper = 0.99,
      id = "benchmark_cap_amounts"
    ) |>
    recipes::step_rm(tidyselect::all_of(amount_vars)) |>
    recipes::step_indicate_na(
      EXT_SOURCE_1, EXT_SOURCE_2, EXT_SOURCE_3,
      id = "benchmark_indicate_missing"
    ) |>
    recipes::step_impute_median(
      recipes::all_numeric_predictors(),
      id = "benchmark_impute_median"
    ) |>
    recipes::step_novel(
      recipes::all_nominal_predictors(),
      new_level = "OTHER_UNSEEN",
      id = "benchmark_novel_level"
    ) |>
    recipes::step_unknown(
      recipes::all_nominal_predictors(),
      new_level = "unknown",
      id = "benchmark_unknown_level"
    ) |>
    recipes::step_dummy(
      recipes::all_nominal_predictors(),
      id = "benchmark_dummy"
    ) |>
    recipes::step_zv(
      recipes::all_predictors(),
      -tidyselect::contains("OTHER_UNSEEN"),
      id = "benchmark_zero_variance"
    )
}

#' Add an analysis-fold-only imbalance strategy to a recipe
#'
#' @param recipe Unprepped classification recipe.
#' @param strategy One of "none", "downsample", or "smote".
#' @param outcome Outcome column selected by the themis step.
#' @param seed Reproducibility seed for stochastic sampling.
#' @param under_ratio Majority/minority ratio retained by downsampling.
#' @param over_ratio Minority/majority ratio produced by SMOTE.
#' @return Recipe with the requested sampling step appended.
#' @details Both sampling steps use skip = TRUE. They alter analysis data during
#'   prep/juice but are never applied when assessment or scoring data are baked.
add_imbalance_strategy <- function(
    recipe,
    strategy = c("none", "downsample", "smote"),
    outcome = "TARGET",
    seed = 20261008L,
    under_ratio = 1,
    over_ratio = 0.5) {
  strategy <- match.arg(strategy)
  if (strategy == "none") return(recipe)
  if (!requireNamespace("themis", quietly = TRUE)) {
    stop("Package 'themis' is required for sampling strategies.", call. = FALSE)
  }

  if (strategy == "downsample") {
    return(themis::step_downsample(
      recipe,
      !!!rlang::syms(outcome),
      under_ratio = under_ratio,
      replacement = FALSE,
      skip = TRUE,
      seed = seed,
      id = "downsample_analysis"
    ))
  }

  themis::step_smote(
    recipe,
    !!!rlang::syms(outcome),
    over_ratio = over_ratio,
    neighbors = 5,
    skip = TRUE,
    seed = seed,
    id = "smote_analysis"
  )
}
