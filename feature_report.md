---
title: "Repayment-Risk Features for Thin-File Applicants"
author: "Alejo Sanchez"
date: last-modified
---

[← Back to reports overview](reports.qmd){.btn .btn-primary}

[Data map](data_map.md) · **Feature report** · [EDA plan](eda_plan.md)

## Scope and interpretation

A thin-file applicant has too little conventional credit-bureau history to support a robust traditional score. Lenders do not therefore rely on one universal “thin-file feature set.” They combine any available conventional evidence with application data, internal account performance, and—where legally and operationally appropriate—alternative data.

The evidence base used here is limited to regulator guidance, an official lender disclosure filed with a regulator, World Bank guidance, and peer-reviewed research:

- The OCC describes repayment-capacity assessment through income, disposable income, payment-to-income, monthly debt-service-to-income, and total-debt-to-income measures, alongside credit history and loan terms ([OCC, *Retail Lending: Comptroller's Handbook*](https://www.occ.treas.gov/publications-and-resources/publications/comptrollers-handbook/files/retail-lending/pub-ch-retail-lending.pdf)).
- The World Bank lists loan amount/type/maturity, collateral, payment performance, arrears, amounts owed, length of history, new credit, and credit type as traditional scoring data. For limited-file borrowers it also identifies transactional, utility, mobile, online, and behavioral data as potential alternatives ([World Bank, *Credit Scoring Approaches Guidelines*](https://thedocs.worldbank.org/en/doc/935891585869698451-0130022020/render/CREDITSCORINGAPPROACHESGUIDELINESFINALWEB.pdf)).
- U.S. regulators recognize consumer-permissioned bank-account cash flow as alternative underwriting data that may help assess consumers outside mainstream credit, subject to consumer-protection controls ([Federal regulators’ joint statement](https://www.consumerfinance.gov/archive/newsroom/federal-regulators-issue-joint-statement-use-alternative-data-credit-underwriting/)).
- The CFPB's formal 2017 Request for Information identifies cash-flow and asset information, stability measures, rental and utility payments, mobile-phone payment patterns, and web/device behavior as alternative-data categories used or contemplated in credit decisions; it also identifies accuracy, transparency, privacy, and discrimination risks ([CFPB, *Request for Information Regarding Use of Alternative Data and Modeling Techniques in the Credit Process*](https://files.consumerfinance.gov/f/documents/20170214_cfpb_Alt-Data-RFI.pdf)).
- Upstart disclosed using traditional credit score and income together with education and employment history. This is evidence of lender practice, not regulatory endorsement of those variables ([Upstart 2020 CFPB filing](https://files.consumerfinance.gov/f/documents/cfpb_upstart-network-inc_no-action-letter-application_2020-11.pdf)).
- Berg et al. find that website-access and registration footprints can complement bureau scores and retain predictive information for unscorable consumers ([Berg et al., 2020, *Review of Financial Studies*](https://scholars.duke.edu/publication/1331342)).

This report assesses whether the supplied Home Credit data can construct each feature family. “Buildable” means the necessary raw fields exist; it does not mean the feature is valid, decision-time eligible, fair, or predictive. No feature values were computed.

## Feature feasibility in the Home Credit data

### 1. Income level and income source

**Why lenders use it:** Income is a direct input to repayment-capacity analysis. Income source can help establish whether reported resources are recurring, although it requires verification and careful treatment.

**Feasibility: Buildable, with limitations.**

- `application_train`: `AMT_INCOME_TOTAL`, `NAME_INCOME_TYPE`
- Same fields are available in `application_test` for future scoring.

These fields support reported-income and income-source features. The files do not contain pay stubs, tax records, payroll transactions, income frequency, or a verified/unverified indicator. `DAYS_EMPLOYED = 365243` is an undocumented sentinel and must not be interpreted as actual tenure; it should be separated and reviewed against `NAME_INCOME_TYPE`.

### 2. Employment stability and occupational profile

**Why lenders use it:** Employment history is used by some lenders as nontraditional application information, including in the Upstart disclosure cited above.

**Feasibility: Partially buildable.**

- `application_train`: `DAYS_EMPLOYED`, `NAME_INCOME_TYPE`, `OCCUPATION_TYPE`, `ORGANIZATION_TYPE`, `FLAG_EMP_PHONE`

The data can represent reported tenure, employment category, occupation, and employer-organization type. It cannot establish employer identity, continuous work history, job changes, pay volatility, or verified employment. Occupation and organization fields also warrant missingness, stability, proxy-discrimination, and explainability review.

### 3. Proposed-loan payment burden

**Why lenders use it:** The OCC identifies payment-to-income as a common repayment-capacity measure.

**Feasibility: Buildable as a proxy, not a complete affordability test.**

- `application_train`: `AMT_ANNUITY`, `AMT_INCOME_TOTAL`
- Construction: current-loan payment burden from `AMT_ANNUITY / AMT_INCOME_TOTAL`, subject to confirming compatible time units.

The data does not document income periodicity clearly enough to call this a conventional monthly payment-to-income ratio without validation.

### 4. Total debt burden and debt-to-income

**Why lenders use it:** The OCC discusses monthly debt-service-to-income and total debt owed relative to income.

**Feasibility: Partially buildable.**

- `application_train`: `AMT_INCOME_TOTAL`
- `bureau`, aggregated by `SK_ID_CURR`: `AMT_CREDIT_SUM_DEBT`, `AMT_CREDIT_SUM`, `AMT_ANNUITY`, `CREDIT_ACTIVE`
- Possible proxy: summed reported bureau debt divided by reported income.

The files do not provide complete required monthly payments for every obligation, housing expense, or all off-bureau debts. A conventional DTI cannot be built reliably. Applicants with no matched bureau row must remain distinct from applicants whose reported debt is zero.

### 5. Requested amount, product, term, purpose, and borrower contribution

**Why lenders use it:** Loan amount, type, maturity, purpose, collateral, and borrower equity affect exposure and affordability.

**Feasibility: Mostly buildable for the requested Home Credit loan.**

- `application_train`: `NAME_CONTRACT_TYPE`, `AMT_CREDIT`, `AMT_ANNUITY`, `AMT_GOODS_PRICE`
- `previous_application`: `NAME_CONTRACT_TYPE`, `AMT_APPLICATION`, `AMT_CREDIT`, `AMT_ANNUITY`, `AMT_DOWN_PAYMENT`, `RATE_DOWN_PAYMENT`, `AMT_GOODS_PRICE`, `CNT_PAYMENT`, `NAME_CASH_LOAN_PURPOSE`, `NAME_GOODS_CATEGORY`, `NAME_PORTFOLIO`, `NAME_PRODUCT_TYPE`, `PRODUCT_COMBINATION`

Current-loan amount and product features are available, as are credit-to-income and financing-to-goods-price proxies. The current application table has no explicit maturity, interest rate, down payment, or loan-purpose field. Those fields exist only for previous applications and describe prior—not current—requests. No reliable collateral valuation is supplied.

### 6. Conventional bureau payment history and delinquency

**Why lenders use it:** Historical late payment, arrears, and default performance are core traditional credit-risk features.

**Feasibility: Buildable only for applicants with usable matched bureau history.**

- `bureau`: `CREDIT_DAY_OVERDUE`, `AMT_CREDIT_MAX_OVERDUE`, `AMT_CREDIT_SUM_OVERDUE`, `CREDIT_ACTIVE`, `DAYS_ENDDATE_FACT`
- `bureau_balance`, joined on `SK_ID_BUREAU`: `MONTHS_BALANCE`, `STATUS`
- Link to the applicant through `bureau.SK_ID_CURR`.

These fields can support delinquency occurrence, severity, recency, and monthly-status-history features after aggregation. They are unavailable for true thin-file applicants with no bureau records. Unmatched `bureau_balance.SK_ID_BUREAU` rows cannot be assigned to an applicant through the supplied `bureau` table and should not be silently included or discarded.

### 7. Amounts owed, revolving limits, and external utilization proxies

**Why lenders use it:** Amounts owed and revolving exposure indicate leverage and capacity pressure.

**Feasibility: Partially buildable.**

- `bureau`: `AMT_CREDIT_SUM`, `AMT_CREDIT_SUM_DEBT`, `AMT_CREDIT_SUM_LIMIT`, `AMT_CREDIT_SUM_OVERDUE`, `AMT_ANNUITY`, `CREDIT_ACTIVE`, `CREDIT_TYPE`

The fields support balances, debt, limits, overdue amounts, and debt-to-limit proxies where applicable. The dictionary and data do not establish that `AMT_CREDIT_SUM_LIMIT` is populated consistently for every revolving account, so the result should not be treated as a universal utilization measure.

### 8. Credit-history depth, age, recency, and product mix

**Why lenders use it:** Length and depth of history, active-account counts, and types of credit are standard bureau dimensions.

**Feasibility: Buildable for bureau-covered applicants.**

- `bureau`: `SK_ID_BUREAU`, `DAYS_CREDIT`, `DAYS_CREDIT_ENDDATE`, `DAYS_ENDDATE_FACT`, `DAYS_CREDIT_UPDATE`, `CREDIT_ACTIVE`, `CREDIT_TYPE`, `CNT_CREDIT_PROLONG`
- `bureau_balance`: `MONTHS_BALANCE`

Applicant-level features can count accounts and credit types and summarize oldest/newest records, status, and prolongations. The small population with positive `DAYS_CREDIT_UPDATE` values must be reviewed because those records appear to postdate the current application. No usable calendar dates are available.

### 9. New-credit demand and inquiries

**Why lenders use it:** Recent applications for credit may indicate additional borrowing demand, although comparison shopping complicates interpretation.

**Feasibility: Buildable.**

- `application_train`: `AMT_REQ_CREDIT_BUREAU_HOUR`, `AMT_REQ_CREDIT_BUREAU_DAY`, `AMT_REQ_CREDIT_BUREAU_WEEK`, `AMT_REQ_CREDIT_BUREAU_MON`, `AMT_REQ_CREDIT_BUREAU_QRT`, `AMT_REQ_CREDIT_BUREAU_YEAR`

The fields support time-window inquiry counts. They do not identify inquiry purpose, lender, approval outcome, or whether several inquiries were rate shopping for one loan.

### 10. Internal prior-application and approval history

**Why lenders use it:** A lender’s own relationship data can supplement a thin external file with observed demand, prior decisions, and product history.

**Feasibility: Buildable.**

- `previous_application`: `SK_ID_PREV`, `DAYS_DECISION`, `NAME_CONTRACT_STATUS`, `CODE_REJECT_REASON`, `NAME_CLIENT_TYPE`, `FLAG_LAST_APPL_PER_CONTRACT`, `NFLAG_LAST_APPL_IN_DAY`, plus the product and amount fields listed in feature 5
- Aggregate to the applicant with `SK_ID_CURR`.

The fields support counts and recency of prior requests, approvals/refusals/cancellations, prior requested-versus-granted amounts, and prior product mix. They do not prove why a decision was made beyond the supplied coded rejection reason. `XNA` and the `365243` date sentinel require status-specific treatment.

### 11. Internal installment-payment performance

**Why lenders use it:** Actual on-time payment and amount behavior is direct repayment evidence and can be especially useful when bureau history is sparse.

**Feasibility: Buildable after transaction-level validation.**

- `installments_payments`: `SK_ID_PREV`, `SK_ID_CURR`, `NUM_INSTALMENT_VERSION`, `NUM_INSTALMENT_NUMBER`, `DAYS_INSTALMENT`, `DAYS_ENTRY_PAYMENT`, `AMT_INSTALMENT`, `AMT_PAYMENT`

These fields support lateness (`DAYS_ENTRY_PAYMENT` relative to `DAYS_INSTALMENT`), underpayment (`AMT_PAYMENT` relative to `AMT_INSTALMENT`), frequency, severity, and recency features. The grouping (`SK_ID_PREV`, `NUM_INSTALMENT_VERSION`, `NUM_INSTALMENT_NUMBER`) is not unique; distinct payment events must be distinguished from duplicate loads before selecting sum, count, or last-payment aggregation. Only information known by the current-application date is decision-time eligible.

### 12. Internal monthly delinquency and remaining-term behavior

**Why lenders use it:** Monthly account performance supplies repeated evidence of arrears, cures, and repayment progression.

**Feasibility: Buildable.**

- `POS_CASH_balance`: `MONTHS_BALANCE`, `CNT_INSTALMENT`, `CNT_INSTALMENT_FUTURE`, `NAME_CONTRACT_STATUS`, `SK_DPD`, `SK_DPD_DEF`, linked by `SK_ID_CURR` and `SK_ID_PREV`

These fields support days-past-due, delinquency frequency/severity, remaining-installment, recency, and status-transition features. Month `0` requires timing review. The direct `SK_ID_CURR` permits applicant aggregation even when `SK_ID_PREV` is unmatched to `previous_application`, subject to validation.

### 13. Internal credit-card utilization, payment, and drawing behavior

**Why lenders use it:** Revolving utilization, minimum-payment behavior, drawings, and delinquency describe debt pressure and account management.

**Feasibility: Buildable.**

- `credit_card_balance`: `MONTHS_BALANCE`, `AMT_BALANCE`, `AMT_CREDIT_LIMIT_ACTUAL`, `AMT_DRAWINGS_ATM_CURRENT`, `AMT_DRAWINGS_CURRENT`, `AMT_DRAWINGS_OTHER_CURRENT`, `AMT_DRAWINGS_POS_CURRENT`, `AMT_INST_MIN_REGULARITY`, `AMT_PAYMENT_CURRENT`, `AMT_PAYMENT_TOTAL_CURRENT`, `AMT_RECEIVABLE_PRINCIPAL`, `AMT_RECIVABLE`, `AMT_TOTAL_RECEIVABLE`, `CNT_DRAWINGS_ATM_CURRENT`, `CNT_DRAWINGS_CURRENT`, `CNT_DRAWINGS_OTHER_CURRENT`, `CNT_DRAWINGS_POS_CURRENT`, `CNT_INSTALMENT_MATURE_CUM`, `NAME_CONTRACT_STATUS`, `SK_DPD`, `SK_DPD_DEF`
- Aggregate by `SK_ID_CURR`; retain `SK_ID_PREV` for account-level sequencing.

The data can build utilization, payment-to-balance, drawing mix/frequency, delinquency, and recency features for customers with prior Home Credit card activity. It is not a complete view of all external cards.

### 14. Rent, utility, mobile-phone, and cable payment history

**Why lenders use it for thin files:** Timely recurring non-credit obligations can provide payment evidence when formal loan history is absent; the CFPB and World Bank identify these sources explicitly.

**Feasibility: Not buildable.**

- `application_train.NAME_HOUSING_TYPE` describes housing arrangement but not rent amount or payment performance.
- `FLAG_MOBIL`, `FLAG_PHONE`, `FLAG_WORK_PHONE`, `FLAG_CONT_MOBILE`, and `FLAG_EMAIL` indicate contact-channel presence, not bill payment.

No rent ledger, utility account, telecommunications balance, due date, or payment record exists.

### 15. Consumer-permissioned bank-account cash flow

**Why lenders use it for thin files:** Deposits, withdrawals, balances, income regularity, expense burden, overdrafts, and residual cash flow can provide current capacity evidence beyond a bureau file.

**Feasibility: Not buildable.**

No table contains deposit-account transactions, running balances, payroll deposits, withdrawals, transfers, overdrafts, recurring bills, or cash reserves. `AMT_INCOME_TOTAL` is a reported application value and cannot substitute for transaction-level cash flow.

### 16. Education and occupation as alternative application data

**Why lenders use it:** The CFPB identifies education and occupation as alternative data considered by some lenders, and Upstart disclosed education and employment history in its model.

**Feasibility: Partially buildable, with elevated governance risk.**

- `application_train`: `NAME_EDUCATION_TYPE`, `OCCUPATION_TYPE`, `NAME_INCOME_TYPE`, `DAYS_EMPLOYED`, `ORGANIZATION_TYPE`

Education level and current occupational/employment descriptors are present, but school identity, degree field, graduation date, full employment history, and verification are absent. These fields can proxy for protected or socioeconomic characteristics; availability is not evidence that they should be used.

### 17. Digital footprint and online behavioral data

**Why lenders use it for thin files:** Peer-reviewed evidence shows that device and website-access/registration metadata can complement bureau information, including for unscorable consumers.

**Feasibility: Not buildable as a genuine digital footprint.**

- Superficially related fields are `application_train.WEEKDAY_APPR_PROCESS_START`, `HOUR_APPR_PROCESS_START`, `FLAG_EMAIL`, and the phone flags; `previous_application` also has `WEEKDAY_APPR_PROCESS_START`, `HOUR_APPR_PROCESS_START`, and `CHANNEL_TYPE`.

These fields do not provide device type, operating system, browser, referral source, email-domain characteristics, browsing path, session behavior, typing/form-filling behavior, geolocation, social-media activity, or e-commerce transactions. Application timing or channel may be analyzed under strict decision-time and fairness review, but should not be mislabeled as the digital footprint studied by Berg et al.

### 18. Housing, property, and asset indicators

**Why lenders use it:** Housing expense, collateral, and assets can inform capacity or loss protection, depending on product and jurisdiction.

**Feasibility: Partially buildable.**

- `application_train`: `FLAG_OWN_REALTY`, `FLAG_OWN_CAR`, `OWN_CAR_AGE`, `NAME_HOUSING_TYPE`, `DAYS_REGISTRATION`
- Property descriptors: `APARTMENTS_*`, `BASEMENTAREA_*`, `YEARS_BEGINEXPLUATATION_*`, `YEARS_BUILD_*`, `COMMONAREA_*`, `ELEVATORS_*`, `ENTRANCES_*`, `FLOORSMAX_*`, `FLOORSMIN_*`, `LANDAREA_*`, `LIVINGAPARTMENTS_*`, `LIVINGAREA_*`, `NONLIVINGAPARTMENTS_*`, `NONLIVINGAREA_*`, `FONDKAPREMONT_MODE`, `HOUSETYPE_MODE`, `TOTALAREA_MODE`, `WALLSMATERIAL_MODE`, `EMERGENCYSTATE_MODE`

The data supports ownership, housing-type, vehicle-age, residence-registration-tenure, and property-condition proxies. It does not provide verified market value, equity, liens, rent/mortgage expense, liquid savings, or proof that the property secures the requested loan. Property and neighborhood proxies require fairness review.

### 19. Household burden and dependents

**Why lenders use it:** Dependents and household size may affect disposable income when lenders conduct residual-income analysis.

**Feasibility: Partially buildable.**

- `application_train`: `CNT_CHILDREN`, `CNT_FAM_MEMBERS`, `NAME_FAMILY_STATUS`, `NAME_TYPE_SUITE`

The data can create household-size or income-per-household-member proxies. It lacks verified household expenses, other household income, child-care costs, support obligations, and shared debt responsibility. Family-status variables may raise fairness and jurisdiction-specific compliance concerns.

### 20. Third-party scores

**Why lenders use it:** Lenders often combine application information with external credit or risk scores.

**Feasibility: Available as opaque inputs, but not reconstructable.**

- `application_train`: `EXT_SOURCE_1`, `EXT_SOURCE_2`, `EXT_SOURCE_3`

The columns can be used only as supplied scores. Their providers, input data, construction, timing, scale semantics, and thin-file behavior are not documented in the supplied dictionary. The dataset therefore cannot rebuild them or establish whether they use permissible, decision-time information.

## Overall conclusion

The data is strongest for four thin-file complements: reported application capacity, the lender’s own previous decisions, internal installment/POS/card repayment behavior, and limited education/employment/housing descriptors. It also contains conventional bureau features where records exist, but those features do not solve the information gap for applicants with no bureau match.

The data cannot build the alternative sources most directly associated with thin-file underwriting in regulator guidance: bank-account cash flow, rent/utilities/telecommunications payment history, or genuine mobile/web behavioral footprints. Contact flags and application timestamps are not substitutes for those sources.

All historical tables must be aggregated to `SK_ID_CURR` before joining to the application grain. Decision-time filtering, unmatched-key handling, sentinel/placeholder treatment, data provenance, explainability, and fairness review are prerequisites to modeling; raw availability alone does not justify feature use.
