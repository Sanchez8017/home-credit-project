# Home Credit Default Risk Project

This repository contains my work on a consumer-finance project focused on predicting default risk using traditional and alternative customer information.

The project covers business framing, industry research, data mapping, data-quality assessment, exploratory analysis, predictive modeling, model evaluation, and communication of business recommendations. It also serves as part of my professional data analytics portfolio.

## Project Objective

The objective is to identify information that can support accurate and responsible default-risk prediction while translating the analytical findings into practical business value.

## Tools and Technologies

- **Development environment:** [Positron](https://github.com/posit-dev/positron)
- **Programming language:** R
- **Reporting framework:** Quarto
- **Version control:** Git and GitHub
- **Publishing:** GitHub Pages

## Repository Structure

```text
MSBA Capstone/
|-- _quarto.yml
|-- index.qmd
|-- 01_data_map.qmd
|-- 02_industry_context.qmd
|-- 03_eda_plan.qmd
|-- R/
|-- data/
|   |-- raw/
|   `-- processed/
|-- outputs/
|   |-- 01_eda.qmd
|   |-- 02_data_preparation.qmd
|   `-- 03_modeling.qmd
|-- README.md
`-- .gitignore
```

The modeling notebook contains the model comparisons, final validation, and Kaggle submission workflow.

## Data

The project uses the Home Credit Default Risk dataset. Raw and processed datasets are stored locally and excluded from GitHub because of their size.

The dataset includes current applications, previous applications, external bureau records, monthly account histories, installment payments, and supporting metadata.

## Current Status

Industry research, data mapping, exploratory analysis, data preparation, and modeling are complete. The selected model and validated Kaggle submission achieved ROC-AUC scores of **0.76189** on the public leaderboard and **0.75758** on the private leaderboard.

## Modeling Results

The modeling analysis is in [`outputs/03_modeling.qmd`](outputs/03_modeling.qmd). All model comparisons use the same three stratified cross-validation folds and ROC-AUC as the primary selection metric.

Models and experiments included:

- a majority-class classifier and a small application-only logistic regression as benchmarks;
- ridge logistic regression using application-only and full-history predictor sets;
- random forest using the full-history predictors;
- XGBoost using application-only and full-history predictors;
- full-history XGBoost with median imputation and missingness indicators versus native missing-value routing;
- class-weighted, downsampled, and SMOTE versions of XGBoost; and
- a 20-configuration randomized XGBoost search on a 5,000-row sample, followed by confirmation on the full-data folds.

The principal full-data comparisons were:

| Model | Predictor set / missing-value treatment | Mean 3-fold ROC-AUC | Result |
|---|---|---:|---|
| Majority-class benchmark | No predictors | 0.5000 | No-skill reference |
| Simple logistic benchmark | Selected application fields; median imputation and indicators | 0.7331 | Established a useful interpretable benchmark |
| Ridge logistic | Application only | 0.7451 | Improved on simple logistic |
| Ridge logistic | Full history | 0.7522 | Supplementary history improved ridge |
| Random forest | Full history | 0.7292 | Trailed the logistic and XGBoost candidates |
| XGBoost | Application only | 0.7513 | Competitive without supplementary history |
| XGBoost | Full history; median imputation and indicators | 0.7657 | Strongest main candidate and baseline for later experiments |
| XGBoost | Full history; native missing-value routing | 0.7661 | Best full-data fold-mean ROC-AUC; selected |

The selected model is **unadjusted, full-history XGBoost with native missing-value routing**. Its pooled out-of-fold ROC-AUC was **0.7660**, and its fold-mean ROC-AUC was **0.7661** (standard error **0.0011**), the highest full-data validation result among the evaluated models. Native routing slightly outperformed the otherwise identical median-imputation recipe, allowing XGBoost to learn the appropriate branch for missing numeric values. The tested class weighting, downsampling, and SMOTE adjustments did not improve ROC-AUC. Randomized tuning improved performance on the 5,000-row tuning sample, but the locked configuration trailed untuned full-history XGBoost by 0.0034 ROC-AUC when confirmed on the full-data folds; therefore neither an imbalance adjustment nor the tuned configuration was carried into the final model.

The generated [`outputs/submission.csv`](outputs/submission.csv) contains probabilities for all 48,744 test applicants and passes the notebook's schema, ID, row-count, missing-value, probability-range, and plain-decimal-format checks. It achieved Kaggle ROC-AUC scores of **0.76189 public** and **0.75758 private**.

## Data Preparation and Feature Engineering

The data-preparation script is [`outputs/02_data_preparation.qmd`](outputs/02_data_preparation.qmd). It converts the eight Home Credit source tables into modeling-ready train and test tables with exactly one row per `SK_ID_CURR`, while preserving separate ID, audit, and data-quality fields.

The preparation follows the decisions documented in [`outputs/01_eda.qmd`](outputs/01_eda.qmd). The rendered reports are [`outputs/01_eda.html`](outputs/01_eda.html) and [`outputs/02_data_preparation.html`](outputs/02_data_preparation.html).

## What the script does and how it implements the EDA

| Preparation step and resulting features | EDA decision implemented |
|---|---|
| Recode the `DAYS_EMPLOYED = 365243` sentinel to missing and add `DAYS_EMPLOYED_SENTINEL`. Convert relative-day fields to positive-year features such as `age_years`, `employment_years`, `registration_years`, `id_publish_years`, and `phone_change_years`. | EDA Q8/Q11 found an invalid duration sentinel and recommended interpretable units while retaining a flag for its information. |
| Replace application-level `XNA` placeholders with field-specific unknown levels and retain audit indicators. Flag, but do not delete or overwrite, `OWN_CAR_AGE > 50`. | EDA Q6/Q11 required field-specific placeholder treatment and sensitivity review rather than indiscriminate row deletion. |
| Add `AMT_REQ_CREDIT_BUREAU_MISSING`, leaving the original missing values for later imputation. | EDA Q7 found that missing inquiry history had a different target rate from a genuine zero, so the two states must remain distinguishable. |
| Create `annuity_to_income`, `credit_to_income`, and `financing_to_goods`, returning missing for a zero or missing denominator. | EDA Q12 approved these as repayment-capacity proxies, with the caveat that reported income is unverified and these are not conventional DTI measures. |
| Filter bureau, bureau-balance, prior-application, installment, POS, and card histories to information observable at application time, then aggregate each source to `SK_ID_CURR`. | EDA Q3/Q9 identified the applicant as the modeling grain and prohibited post-application information leakage. |
| Create history depth/count, debt, payment-timing, shortfall, prior-status, coverage, source-presence, unmatched-history, and delinquency features. Delinquency states distinguish `no_history`, `history_no_delinquency`, `delinquent`, and, where needed, `history_delinquency_unmeasured`. | EDA Q4/Q7 showed that history coverage and delinquency were informative, but no history, no measured delinquency, and unmeasured delinquency are not equivalent. Credit-card history is retained as presence only because its EDA delinquency direction was reversed. |
| Left-join applicant aggregates, convert true no-history counts to zero, and retain missing amounts/timings for train-learned imputation. | EDA Q4 required retaining every application; Q7 distinguished a known count of zero from an unknown measurement. |
| Add train-learned 1st/99th-percentile caps and `log1p` amount variants, a train-quantile `financing_to_goods_bin`, missingness indicators, categorical dummies, and revolving-loan-by-affordability interactions. | EDA Q7/Q10/Q11/Q12 called for preserving missingness signals, comparing raw/log/capped skewed amounts, learning rather than inventing bin cutoffs, and testing contract-specific affordability effects. |
| Assign sensitive or potentially proxying fields—including gender, age, family, occupation, organization, education, housing, and geography—to an audit-only role. Save the allowed predictor names separately. | EDA Q13 required fairness and governance review before these fields could be used as predictors. |

### EDA ideas deliberately not implemented

- `EXT_SOURCE` summaries, a document-flag count, and an employment-to-age ratio were not created because the EDA did not provide evidence for them.
- Rare categorical levels were not lumped because EDA Q6 called for preserving recorded labels. Truly unseen test labels instead map to an explicit `OTHER_UNSEEN` level.
- Credit-card delinquency measures were not promoted to predictors because their target relationship ran opposite to the other delinquency sources; only card-history presence is retained.
- Applicants and unusual values are not deleted. Examples such as cars older than 50 years are flagged for later sensitivity analysis because the EDA did not justify removal.
- Several fields remain audit-only pending the fairness review required by EDA Q13. The employment-sentinel feature remains a predictor because Q8 explicitly required it, but its overlap with pensioner/age proxies must be evaluated during validation.

## Train/test consistency and leakage control

Row-level cleaning, feature formulas, time filters, aggregations, and joins use fixed rules and learn no population-level parameters. All estimated preprocessing is contained in one `recipes` recipe fitted with `prep(..., training = train_in)` on training data only. The fitted recipe is then reused unchanged with `bake()` for test data.

The training-only learned parameters are:

- 1st/99th-percentile amount caps;
- quantile cutoffs for `financing_to_goods_bin`;
- numeric imputation medians;
- observed categorical levels, dummy encoding, and the protected `OTHER_UNSEEN` level; and
- zero-variance decisions.

The fitted object is saved as `data/processed/prep_recipe.rds`. Model tuning should fit the unprepared recipe again within each resample rather than using this full-training fitted recipe inside cross-validation.

The pipeline validates the data before writing any output. The original results were generated on September 23, 2026 from the same notebook version later committed as `4d83219` on September 24, 2026. After the unused `sample_submission.csv` requirement was removed, the full pipeline was rerun on September 24, 2026; every dimension and validation count below was reproduced unchanged.

| Check | Observed result |
|---|---|
| Train/test columns | **Passed:** 235 shared columns in identical order; train has exactly one additional column, `TARGET`. |
| Applicant grain | **Passed:** 307,511 train rows and 307,511 unique train IDs; 48,744 test rows and 48,744 unique test IDs--one row per `SK_ID_CURR`. |
| Row preservation | **Passed:** row counts, applicant IDs, and row order match the application inputs. |
| Types and categories | **Passed:** shared column classes and factor levels are identical. |
| Missing predictors | **Passed:** no missing values remain in the 212 predictor columns in either output. |
| Target isolation | **Passed:** `TARGET` is absent from test. |
| Audit isolation | **Passed:** all 21 audit columns occur in both outputs and none is a predictor. |

## Inputs, outputs, and how to run

From the project root, place these Kaggle CSV files in `data/raw/`:

| Input file | Rows | Use |
|---|---:|---|
| `application_train.csv` | 307,511 | Training applications and `TARGET` |
| `application_test.csv` | 48,744 | Scoring applications |
| `bureau.csv` | 1,716,428 | External credit records |
| `bureau_balance.csv` | 27,299,925 | Monthly external-credit history |
| `previous_application.csv` | 1,670,214 | Previous Home Credit applications |
| `POS_CASH_balance.csv` | 10,001,358 | Monthly POS/cash-loan history |
| `credit_card_balance.csv` | 3,840,312 | Monthly credit-card history |
| `installments_payments.csv` | 13,605,401 | Installment payment events |

Required R packages are `DBI`, `duckdb`, `dplyr`, `recipes`, and `knitr`. Quarto must also be installed. The optional `arrow` package enables Parquet output; otherwise the script writes CSV files instead.

Run the complete pipeline from the project root:

```powershell
quarto render outputs/02_data_preparation.qmd
```

The notebook also exposes `run_pipeline(con, out_dir)` for an interactive R session after its setup and function-definition chunks have run. It validates first and then writes to `data/processed/`:

| Output | Dimensions / contents |
|---|---|
| `train_prepared.rds` and `train_prepared.parquet` | **307,511 x 236**, including `TARGET` |
| `test_prepared.rds` and `test_prepared.parquet` | **48,744 x 235**, with no `TARGET` |
| `predictor_names.rds` | Character vector naming **212 predictors**; modeling code should select these explicitly |
| `prep_recipe.rds` | Fitted training recipe containing caps, bin cutoffs, medians, category levels, and encoding decisions |
| `outputs/02_data_preparation.html` | Rendered preparation report, validation tables, and learned-parameter evidence |

If `arrow` is unavailable, `train_prepared.csv` and `test_prepared.csv` replace the two Parquet files with the same table dimensions. The RDS versions are always written and preserve exact R column types.

## Known limitations

- Installment rows with no payment date are treated as "no payment observed" and contribute to shortfall, but not delinquency; the EDA did not establish their exact meaning, so this assumption requires validation.
- Decision-time filters make history coverage and installment populations differ slightly from the EDA's broader descriptive tables.
- Raw, capped, and log-transformed amounts coexist so modeling can compare them; the modeling stage should not automatically use all correlated versions together.
- The custom `step_cap_quantile` methods must be defined (by running the relevant notebook chunk) before baking the saved recipe in a new R session.

Raw and processed datasets are excluded from Git because of their size.
