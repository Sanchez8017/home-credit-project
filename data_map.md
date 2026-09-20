---
title: "Home Credit Data Map Report"
author: "Alejo Sanchez"
date: last-modified
---

[← Back to reports overview](reports.qmd){.btn .btn-primary}

**Data map** · [Feature report](feature_report.md) · [EDA plan](eda_plan.md)

This report uses the CSVs in `data/raw/` and the supplied data dictionary, `data/raw/HomeCredit_columns_description.csv` (219 dictionary rows). No `docs/` directory is present in the workspace. The checks below are structural only; no exploratory or target analysis was performed.

“Train coverage” is the percentage of the 307,511 `application_train` applicants having at least one matching source row. Coverage for `bureau_balance` is measured indirectly through `bureau.SK_ID_BUREAU`. Cardinality is stated child-to-parent.

## Table summary

| Table | Grain and row count | Primary key and uniqueness | Foreign keys and cardinality | Train applicants with ≥1 row |
|---|---|---|---|---:|
| `application_train` | One training application; **307,511** rows | `SK_ID_CURR`; unique and nonmissing | None | **100.00%** (307,511) |
| `application_test` | One scoring application; **48,744** rows | `SK_ID_CURR`; unique and nonmissing | None | **0.00%** (0); train and test IDs are disjoint |
| `bureau` | One external bureau credit record; **1,716,428** rows | `SK_ID_BUREAU`; unique and nonmissing | `SK_ID_CURR` → current applications (`application_train` ∪ `application_test`), many-to-one; 0 unmatched rows | **85.69%** (263,491) |
| `bureau_balance` | One bureau credit record-month; **27,299,925** rows | Proposed composite key (`SK_ID_BUREAU`, `MONTHS_BALANCE`); unique and complete | `SK_ID_BUREAU` → `bureau`, many-to-one; 3,120,184 rows / 43,041 keys unmatched | **29.99%** (92,231), via `bureau` |
| `previous_application` | One previous Home Credit application; **1,670,214** rows | `SK_ID_PREV`; unique and nonmissing | `SK_ID_CURR` → current applications, many-to-one; 0 unmatched rows | **94.65%** (291,057) |
| `POS_CASH_balance` | One previous POS/cash loan-month; **10,001,358** rows | Proposed composite key (`SK_ID_PREV`, `MONTHS_BALANCE`); unique and complete | `SK_ID_PREV` → `previous_application`, many-to-one (340,561 rows / 37,422 keys unmatched); `SK_ID_CURR` → current applications, many-to-one (0 unmatched) | **94.12%** (289,444) |
| `credit_card_balance` | One previous credit-card account-month; **3,840,312** rows | Proposed composite key (`SK_ID_PREV`, `MONTHS_BALANCE`); unique and complete | `SK_ID_PREV` → `previous_application`, many-to-one (1,082,816 rows / 11,372 keys unmatched); `SK_ID_CURR` → current applications, many-to-one (0 unmatched) | **28.26%** (86,905) |
| `installments_payments` | One recorded installment-payment transaction; **13,605,401** rows | No supplied transaction-level primary key. (`SK_ID_PREV`, `NUM_INSTALMENT_VERSION`, `NUM_INSTALMENT_NUMBER`) is **not unique**: 653,483 excess rows, maximum group size 12; components are nonmissing. This grouping identifies a scheduled installment, not necessarily one payment transaction. | `SK_ID_PREV` → `previous_application`, many-to-one (1,250,826 rows / 38,847 keys unmatched); `SK_ID_CURR` → current applications, many-to-one (0 unmatched) | **94.84%** (291,643) |
| `sample_submission` | One test application prediction placeholder; **48,744** rows | `SK_ID_CURR`; unique and nonmissing | `SK_ID_CURR` → `application_test`, one-to-one; 0 unmatched rows | **0.00%** (0) |
| `HomeCredit_columns_description` | One documented field; **219** rows | No declared primary key; the first column is a source row/index value, not a data-table key | None | Not applicable |

The unmatched historical keys may reflect scope differences in the supplied parent files and do not automatically mean the data is invalid. They should be reviewed before relational joins are used. Direct `SK_ID_CURR` links in the three payment/balance tables all match the combined current-application population.

## Values that contradict or are not represented by the dictionary

The clearest contradictions are numeric sentinel values stored in fields the dictionary describes as relative day counts:

| Table | Column | Conflicting observed value | Rows | Why it conflicts |
|---|---|---:|---:|---|
| `application_train` | `DAYS_EMPLOYED` | 365,243 | 55,374 | The dictionary says days before the current application; the positive ~1,000-year value is an undocumented sentinel, not a plausible relative day count. |
| `application_test` | `DAYS_EMPLOYED` | 365,243 | 9,274 | Same conflict. |
| `previous_application` | `DAYS_FIRST_DRAWING` | 365,243 | 934,444 | Undocumented sentinel in a relative-time field. |
| `previous_application` | `DAYS_FIRST_DUE` | 365,243 | 40,645 | Undocumented sentinel in a relative-time field. |
| `previous_application` | `DAYS_LAST_DUE_1ST_VERSION` | 365,243 | 93,864 | Undocumented sentinel in a relative-time field. Other positive values can legitimately denote dates after the application. |
| `previous_application` | `DAYS_LAST_DUE` | 365,243 | 211,221 | Undocumented sentinel in a relative-time field. |
| `previous_application` | `DAYS_TERMINATION` | 365,243 | 225,913 | Undocumented sentinel in a relative-time field. |
| `bureau` | `DAYS_CREDIT_UPDATE` | Positive values (maximum 372) | 17 | The dictionary describes days **before** the current application; positive values place the update after it. |

The files also use literal `XNA` as an undocumented unknown/not-applicable category. These values are inconsistent with the dictionary’s plain-language categorical descriptions, which neither list nor explain the code:

| Table | Columns containing `XNA` (row count) |
|---|---|
| `application_train` | `CODE_GENDER` (4) |
| `previous_application` | `NAME_CONTRACT_TYPE` (346), `NAME_CLIENT_TYPE` (1,941), `NAME_PORTFOLIO` (372,230), `NAME_PRODUCT_TYPE` (1,063,666), `NAME_YIELD_GROUP` (517,215) |
| `POS_CASH_balance` | `NAME_CONTRACT_STATUS` (2) |

No other tested relative-time columns conflict with their dictionary descriptions. In particular, positive `DAYS_CREDIT_ENDDATE` and non-sentinel positive `DAYS_LAST_DUE_1ST_VERSION` values can represent scheduled events after an application and are therefore not contradictions.

## Join interpretation

- The modeling base remains one row per `application_train.SK_ID_CURR`.
- `bureau`, `previous_application`, and all balance/payment tables are one-to-many from an applicant and must be aggregated before applicant-level joins.
- `bureau_balance` must first join or aggregate through `bureau.SK_ID_BUREAU`.
- The historical tables’ unmatched `SK_ID_PREV`/`SK_ID_BUREAU` values should be retained or handled explicitly; silently inner-joining them would discard source rows.
