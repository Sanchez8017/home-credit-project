---
title: "Dependency-Ordered EDA Plan"
author: "Alejo Sanchez"
date: last-modified
---

[← Back to reports overview](reports.qmd){.btn .btn-primary}

[Data map](data_map.md) · [Feature report](feature_report.md) · **EDA plan**

## Scope and approval gate

This document is a plan only. No analysis code or data checks have been run. Implementation will begin only after approval.

The six standing checks are: **target distribution; missingness and its relationship to the target; impossible values; keys, duplicates, and table grain; temporal direction; and train/test consistency in columns and category levels**.

## Coverage of the six standing checks

| Standing check | Coverage in the submitted questions | Assessment |
|---|---|---|
| Target distribution | The generic “primary metrics” question does not explicitly require `TARGET` | Not explicitly covered; a dedicated question is `[added]` |
| Missingness: amount and relationship to target | The submitted missingness question asks about amount and patterns, but not specifically association with `TARGET` | Partially covered; the question is sharpened below |
| Impossible values | Outlier/range and dictionary-contradiction questions | Covered; dictionary/schema completeness is added as a prerequisite |
| Keys, duplicates, and table grain | Primary-key/grain and duplicate questions | Covered |
| Temporal direction | Not asked in the submitted list | Not covered; a dedicated question is `[added]` |
| Train/test consistency in columns and category levels | Category standardization mentions slicers but not a complete train/test comparison | Not fully covered; a dedicated question is `[added]` |

## Ordered questions and methods

The questions are ordered so that schema knowledge and row identity are established before joins, missingness, validity checks, or descriptive summaries. Question numbers below describe execution order, not the order in which the questions were submitted.

### 1. [added] Does the supplied dictionary cover every raw column, and do the raw schemas support the documented field interpretations?

**Why first:** Dictionary contradictions cannot be assessed until dictionary coverage and table-to-field mappings are known.

**Method:**

- Inventory every raw CSV, its column names, and inferred storage types without calculating distributions.
- Normalize dictionary table labels such as `application_{train|test}.csv` to their corresponding raw tables.
- Compare raw columns with the 219 dictionary rows.
- Classify fields as documented, undocumented, documented-but-absent, or ambiguously mapped.
- Treat inferred CSV types as ingestion types, not proof of business meaning.

**Tables needed:** All CSV schemas in `data/raw/`; `HomeCredit_columns_description.csv`.

**Output:** A dictionary-coverage table with `table`, `column`, `raw type`, `dictionary match`, `dictionary description`, and `review status`, plus counts of each match status by table.

**Answerability:** Answerable. This is a structural prerequisite added to complete the validity check.

### 2. Do the unique row counts at the primary-key level align with the expected grain of the data?

**Method:**

- Test declared or proposed keys against each table’s stated grain.
- Compare row count, distinct-key count, missing-key count, and maximum rows per key.
- Use `SK_ID_CURR` for application tables, `SK_ID_BUREAU` for `bureau`, `SK_ID_PREV` for `previous_application`, and the proposed account-month composite keys for monthly tables.
- Treat (`SK_ID_PREV`, `NUM_INSTALMENT_VERSION`, `NUM_INSTALMENT_NUMBER`) in `installments_payments` as a scheduled-installment grouping, not an assumed transaction primary key.

**Tables needed:** All analytical CSVs and `sample_submission`; grain definitions from `01_data_map.qmd` and `data_map.md`.

**Output:** A key-audit table with `table`, `expected grain`, `candidate key`, `rows`, `distinct keys`, `missing-key rows`, `maximum group size`, and `pass/review`.

**Answerability:** Answerable. This is a structural question, not outcome analysis.

### 3. Are there any duplicate records that should not exist?

**Method:**

- Check exact full-row duplicates in every analytical table.
- Check repeated candidate keys separately from exact duplicates.
- For monthly tables, classify repeated account-month keys as violations of the proposed grain.
- For `installments_payments`, compare all fields within repeated scheduled-installment groups to distinguish potentially separate payments from exact duplicate loads; do not automatically delete either.

**Tables needed:** All analytical CSVs.

**Output:** A duplicate-audit table showing exact duplicate groups/rows and repeated-key groups/excess rows, plus a separate review table for non-unique installment groups.

**Answerability:** Answerable, although business intent may be needed to decide whether non-exact repeated installment rows are erroneous.

### 4. Are there any orphaned foreign keys that could break or bias data-model relationships?

**Method:**

- Test `SK_ID_CURR` against the union of `application_train` and `application_test`.
- Test `bureau_balance.SK_ID_BUREAU` against `bureau.SK_ID_BUREAU`.
- Test `SK_ID_PREV` in the POS, credit-card, and installment tables against `previous_application.SK_ID_PREV`.
- Report unmatched rows and distinct keys rather than treating them automatically as invalid.
- Compare direct `SK_ID_CURR` and parent-mediated join routes where both exist.

**Tables needed:** `application_train`, `application_test`, `bureau`, `bureau_balance`, `previous_application`, `POS_CASH_balance`, `credit_card_balance`, `installments_payments`, and `sample_submission`.

**Output:** A relationship matrix with child table/key, parent table/key, cardinality, unmatched rows, unmatched keys, and recommended join route. A small relationship diagram may accompany the table.

**Answerability:** Answerable. The data can identify orphans, but may not reveal why their parent records are absent.

### 5. [added] What is the distribution of `TARGET` in the training population?

**Why here:** Row identity and applicant grain must be confirmed before the outcome is counted. Later missingness and segment questions depend on this baseline.

**Method:**

- Confirm that `TARGET` is evaluated once per unique `application_train.SK_ID_CURR`.
- Report the count and share of each documented target class and any null or undocumented values.
- Treat this as the observed Home Credit payment-difficulty outcome, not a universal regulatory default rate.

**Tables needed:** `application_train`; target definition from `HomeCredit_columns_description.csv`.

**Output:** A target-frequency table and a simple count/percentage bar chart, accompanied by the documented target definition and class-imbalance note.

**Answerability:** Answerable. This is a descriptive standing check, not a causal question.

### 6. Are the categorical variables standardized enough to be used as clean drop-down slicers?

**Method:**

- Enumerate distinct labels per categorical field after schema and key checks.
- Compare trimmed and case-normalized versions to detect whitespace, capitalization, punctuation, or spelling variants.
- Identify null, blank, `XNA`, `XAP`, `Unknown`, and similar placeholder levels separately.
- Compare shared fields across train/test and related tables without automatically combining semantically different categories.
- Flag high-cardinality fields and levels too rare to function as useful slicers; do not impose a minimum-frequency rule until stakeholders define it.

**Tables needed:** All analytical tables; especially `application_train`, `application_test`, `previous_application`, `bureau`, `POS_CASH_balance`, and `credit_card_balance`; dictionary for meaning.

**Output:** A categorical-domain catalog with raw level, normalized candidate level, frequency, placeholder status, train/test presence, proposed display label, and review flag. A separate slicer-readiness summary will classify each field as ready, needs mapping, high-cardinality, or unsuitable.

**Answerability:** Answerable. “Clean enough” requires an explicit acceptance rule; the proposed output supports that decision rather than silently recoding values.

### 7. Which columns have a high percentage of null or missing values, and does missingness relate to `TARGET`?

**Method:**

- Calculate null, blank, and documented/undocumented placeholder rates separately.
- Profile missingness by table and, where appropriate, by contract/product/status category.
- Examine co-missingness and structural non-applicability.
- Distinguish no history, unmatched history, not applicable, not collected, and genuinely unknown wherever the schema permits.
- For `application_train` fields, compare `TARGET` rates for missing versus observed values, subject to minimum group-size reporting rules.
- For historical fields, first create applicant-level “has history” or “field observed” indicators, then compare those indicators with `TARGET`; do not join raw one-to-many rows directly to the target.
- Define “high” before implementation; otherwise report ranked rates without an arbitrary pass/fail cutoff.

**Tables needed:** All analytical tables, dictionary, and relationship results from Question 4.

**Output:** Ranked field-level completeness table, table-by-field heatmap, co-missingness summary, classification of likely structural versus unexplained missingness, and applicant-level missing-versus-observed `TARGET` comparison table.

**Answerability:** Partially answerable. Rates and associations are observable; the reason a value is missing is often not documented and must be labeled as a hypothesis.

### 8. Are there values in the dataset that explicitly contradict the provided data dictionary?

**Method:**

- Use only documented constraints or unambiguous semantic claims from the dictionary.
- Test relative-date signs and known sentinels, including `365243`, while distinguishing legitimate scheduled future dates from impossible values.
- Review placeholder categories per column rather than assuming `XNA` has one universal meaning.
- Test cross-field logic where dictionary meanings establish an ordering, such as due-date sequences.
- Keep “not documented” separate from “contradicts the dictionary.”

**Tables needed:** All documented analytical tables and `HomeCredit_columns_description.csv`; dictionary-coverage results from Question 1.

**Output:** Exception log with `table`, `column`, `observed value or rule`, `dictionary statement`, `exception count/rate`, `severity`, and `interpretation`. Undocumented fields/codes will appear in a separate list.

**Answerability:** Answerable only where the dictionary states a testable meaning or constraint. The dictionary is not a complete codebook, so silence is not evidence of contradiction.

### 9. [added] Which fields and historical records were known at the current-application decision time?

**Why here:** Timing rules require valid field meanings and sentinel handling from Questions 1 and 8. All later feature summaries must exclude or flag future realized information.

**Method:**

- Use the current application as time zero.
- Classify fields as known, unavailable, ambiguous, or not applicable at decision time.
- Apply table-specific timing anchors: `DAYS_CREDIT`/`DAYS_CREDIT_UPDATE`, `MONTHS_BALANCE`, `DAYS_DECISION`, `DAYS_INSTALMENT`, and `DAYS_ENTRY_PAYMENT`.
- Distinguish scheduled future obligations that may have been known from future realized payments, balances, terminations, or updates that would constitute leakage.
- Review month `0`, positive relative dates, and the `365243` sentinel separately rather than applying a blanket sign rule.

**Tables needed:** All analytical tables; dictionary; relative-time rules documented in `03_eda_plan.qmd`.

**Output:** Field-level decision-time inventory plus a table-level record audit showing records that pass, fail, or remain ambiguous under each timing rule.

**Answerability:** Partially answerable. Relative timing can be checked, but some fields remain ambiguous because exact event definitions and reporting lags are not supplied.

### 10. [added] Are training and test schemas, category levels, and missingness patterns consistent?

**Why here:** Schema and category domains must be established first. This check must precede any recommendation for production encoding or scoring transformations.

**Method:**

- Compare column names and inferred types between `application_train` and `application_test`, allowing only the expected absence of `TARGET` from test.
- Identify categorical levels exclusive to train or test and compare level frequencies.
- Compare missingness rates and numeric ranges/robust quantiles using the same field definitions.
- Flag unseen test levels, material category shifts, incompatible types, and transformation rules that cannot be applied identically.
- Describe differences as possible population, product, policy, or collection changes; do not automatically merge or remove levels.

**Tables needed:** `application_train`, `application_test`, and the dictionary/schema results from Question 1.

**Output:** Schema-difference table, train/test category-level matrix, missingness comparison, numeric-comparison table, and an encoding-readiness issue log.

**Answerability:** Answerable for the supplied populations. The data cannot establish the business cause of any observed difference.

### 11. Are there severe outliers or mixed distributions that will inflate variance and require adjustment later?

**Method:**

- Review valid numeric fields using ranges, robust quantiles, interquartile ranges, zero mass, skewness, and distribution plots.
- Separate sentinel/placeholder values before characterizing continuous distributions.
- Segment multimodal fields by product or status when mixtures may reflect real subpopulations.
- Document potential transformations, winsorization, stratification, or robust estimators without applying them in the initial audit.

**Tables needed:** All analytical tables after Questions 1–10 establish valid fields, codes, timing eligibility, and comparable train/test definitions.

**Output:** Numeric-profile table, flagged-field list, histograms/boxplots for reviewed fields, and an adjustment decision log.

**Answerability:** Partially answerable. Outliers and mixtures can be described. The reference to **CUPED is not answerable or appropriate from these files alone**: CUPED requires an experiment, treatment assignment, a defined outcome, and a pre-treatment covariate measured for the same experimental units. None is supplied. This question should therefore end at variance diagnostics and candidate preprocessing unless an experiment design is later provided.

### 12. What does the baseline distribution of primary business metrics look like?

**Method:**

- First define metrics that actually exist in this lending dataset.
- Reuse the `TARGET` baseline from Question 5 rather than recalculating it here.
- For the training population, describe `AMT_CREDIT`, `AMT_ANNUITY`, `AMT_INCOME_TOTAL`, `AMT_GOODS_PRICE`, and approved project-specific burden ratios.
- Show counts, missingness, robust summaries, and distributions overall and by relevant loan product.
- Do not use historical transaction rows as if they were independent applicants; aggregate them first if included.

**Tables needed:** Primarily `application_train`; historical tables only for separately approved applicant-level aggregate metrics.

**Output:** Metric-definition catalog followed by a baseline scorecard and one distribution figure per approved metric.

**Answerability:** **Not answerable as written for ARPU or ARPPU.** The dataset contains loan applications and credit/payment records, not users, payer status, or recognized revenue. ARPU/ARPPU cannot be constructed. The rewritten lending-metric version above is answerable.

**Classification:** This is a descriptive analysis question (“what does it look like?”), not a causal or inferential question.

### 13. Do sample sizes across applicant segments meet the thresholds needed for statistical significance?

**Method:**

- Define the candidate segments only after categorical cleanup and the modeling population only after key/join decisions.
- Report applicant counts, outcome counts, and proportions per segment using `SK_ID_CURR` as the unit.
- Conduct a prospective power/minimum-detectable-effect analysis only after specifying the comparison, outcome, baseline rate, effect size, significance level, desired power, and multiple-testing policy.
- Avoid treating a universal row-count threshold as proof of significance.

**Tables needed:** `application_train` for `TARGET`-based comparisons; cleaned category definitions from Question 6; applicant-level historical aggregates only if a later hypothesis requires them.

**Output:** Segment-size table and, after statistical assumptions are approved, a power/MDE table for each planned comparison. No significance tests belong in this initial adequacy check.

**Answerability:** **Not fully answerable as written.** Segment counts are answerable, but adequacy for statistical significance cannot be determined until hypotheses, effect sizes, alpha, power, and multiplicity rules are supplied.

## Questions requiring revision or external input

| Submitted question | Issue | Proposed disposition |
|---|---|---|
| Baseline ARPU/ARPPU distribution | Revenue and payer concepts are absent | Replace with explicitly defined lending metrics, or supply a revenue dataset |
| Outliers requiring CUPED | No experiment, assignment, or pre-treatment experimental metric exists | Perform variance/outlier diagnostics only; revisit CUPED if experiment data are supplied |
| Segment sample-size thresholds | Statistical adequacy depends on an estimand and power assumptions | Report segment counts first; approve hypotheses and power parameters before judging adequacy |
| Baseline distribution question | Descriptive rather than inferential | Retain as a clearly labeled descriptive baseline |

All other submitted items are genuine, answerable data-quality questions, although some causes—such as why a parent key or value is missing—may remain unknown from the supplied files.

## Approval sequence

After this plan is approved, implementation should proceed in the numbered order. Proposed recodes, row exclusions, imputations, outlier treatments, joins, and aggregation rules should be reported for approval rather than applied silently.
