# Decision log: pooled LB (KN189 + KN564)

This log lists every choice `lb_pooled.yaml` makes beyond copying a
collected value. All entries are **drafts by Claude, not yet reviewed**.
Each one is a proposal for the study team or the SAP to confirm or change.

The counts come from the full ODM exports:

- KN189 has 206,485 results: 22 tests, 616 subjects, 37 visits.
- KN564 has 304,427 results: 23 tests, 994 subjects, 18 visits.
- The pooled output has 510,912 rows, and the 2026-10-01 R run reproduced
  every count below.

Status key: **Assumption** means the data cannot confirm it. **Choice**
means a reasonable option among several. **Mechanical** means it follows
from the data or CDISC conventions.

## Record structure

| Decision | Why / evidence | Status |
|---|---|---|
| One row per collected result item. | Both studies collect labs wide: one item per test on each of five forms (`LB_CHEM`, `LB_COAG`, `LB_HEM`, `LB_THY`, `LB_UA`), plus a date item and, on some forms, a study-day item. The ODM input already holds one record per item, so the row templates are record-driven, with no reshaping. | Mechanical |
| Each result takes its date, study day and grade from **its own form occurrence**. | A record-driven row's ODM scope is its item-group occurrence (REQ-1269). This matters: KN189's screening coagulation sample is dated 3 days before the other screening labs for all 616 subjects, so one date per visit would be wrong for it. | Mechanical |
| One row template per study and form; KN189's hematology form is split four ways. | An `odm` read names one fixed item, so a template can read only one grade item. KN189 grades ANC, HGB and PLT, so each of those tests gets its own template, and LYMPH and WBC share one. That gives 13 templates in all. | Mechanical |
| Each filter drops only the form's **known** non-result items (date, study day, grades). | The yamaa benchmark `schema-odm-item-sample` instead keeps rows whose test mapping succeeds, with `unmapped: null`. That would silently drop a new test in a later cut. Here a new item becomes a row, and the strict `LBTESTCD` mapping stops the run. | Choice |
| Every form occurs once per subject and visit. | Both studies: no repeated occurrence and no repeated item. The spec checks this with `unique: [STUDYID, USUBJID, VISIT, LBCAT, LBTESTCD]`. | Mechanical |

## Identifiers and visits

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| STUDYID, USUBJID | The same as `dm_pooled.yaml`. | LB has to link to DM. `lb_pooled.R` checks that every LB subject is in `dm_pooled_r.csv`. | Mechanical |
| LBSEQ | `row_number` within subject, ordered by `LBDTC`, then `LBCAT`, then `LBTESTCD`. A remaining tie keeps visit order (REQ-1123). | Neither study collects a sequence. 24,640 KN189 rows tie on all three terms: SCREENING and C1D1 carry the same date for every subject (see "Data findings"). Visit order puts screening first. | Choice |
| VISIT | The study's own visit name (`SCREENING`, `C1D1`, ... in KN189; `SCRN`, `C1D1`, ... in KN564), not harmonized. | Visit schedules are study-specific. No `VISITNUM` was built, because it would need a per-study visit table. | Choice |

## Tests

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| LBTESTCD | Mapped from the item name to the CDISC LBTESTCD term. Where the item names differ, both map to one code: GLUCOSE/GLUC → `GLUC`, POTASSIUM/POTAS → `K`, PT_INR/INR → `INR`, UBLOOD/UABLOOD → `OCCBLD`, UGLU/UAGLUC → `GLUC`, UPRO/UAPROT → `PROT`. The other codes are ANC → `NEUT`, PLT → `PLAT`, TBIL → `BILI`, CRCL → `CREATCLR`, CALC → `CA`, FT3 → `T3FR`, FT4 → `T4FR`. | There is no `unmapped` handler, so a new item stops the run. | Mechanical, please spot-check the codes against current CT |
| FT3 (KN189) vs T3 (KN564) | Kept as **different tests**: `T3FR` and `T3`. | KN189 measures free T3 (median 3.1, about pg/mL); KN564 measures total T3 (median 119, about ng/dL). They are different analytes and must not be pooled. | Mechanical |
| CA | Calcium is KN564 only. | KN189 collects no calcium. | Mechanical |
| LBTEST | From LBTESTCD, using CDISC test names. | | Mechanical |
| LBCAT | From the form: CHEMISTRY, COAGULATION, HEMATOLOGY, THYROID, URINALYSIS. | `THYROID` is a sponsor category; some sponsors file these tests under CHEMISTRY. | Choice |
| LBSPEC | From the form: SERUM (chemistry, thyroid), PLASMA (coagulation), BLOOD (hematology), URINE (urinalysis). | No specimen is collected. Serum versus plasma for chemistry cannot be confirmed. LBSPEC also tells urine glucose from serum glucose. | Assumption |

## Results and units

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| LBORRES | As collected; required. | KN564 writes some whole numbers with a decimal (`100.0`); KN189 does not (`100`). | Mechanical |
| LBORRESU | Inferred from the values: g/dL (ALB, HGB), U/L (ALT, AST), mg/dL (CREAT, BILI, GLUC, CA), mL/min (CREATCLR), mmol/L (K, SODIUM), sec (APTT), 10^9/L (NEUT, LYMPH, PLAT, WBC), pg/mL (T3FR), ng/dL (T4FR, T3), mIU/L (TSH). No unit for INR or urinalysis. | **Neither ODM declares any unit.** The value ranges agree between the studies test by test (for example ALB median 3.9 vs 4.2, HGB 12.3 vs 14.0, PLT 242 vs 251, CREAT 1.03 vs 1.28), and each matches the conventional US unit. KN564's item descriptions confirm HGB (g/dL), WBC (x10^3/mcL = 10^9/L), PLT (1000/mcL = 10^9/L), CREAT and CA (mg/dL). The rest is inferred. | Assumption, **needs confirmation from the data providers** |
| LBSTRESC, LBSTRESU | Copied from LBORRES and LBORRESU. | Both studies use the same units, so nothing is converted. Conversion to SI units, if the SAP wants it, is a separate step. | Choice |
| LBSTRESN | LBORRES as a number. Urinalysis results (`NEGATIVE`, `TRACE`, `1+`, `2+`) stay missing, through the `value` wrapper's `unconvertible: null`. | An `implies` check requires every non-urinalysis result to convert, so a malformed number stops the run instead of turning missing. | Mechanical |
| Urinalysis results | Checked against `NEGATIVE`, `TRACE`, `1+` ... `4+`. | KN189: protein NEGATIVE 1,644, TRACE 454, 1+ 250, 2+ 55; blood NEGATIVE 2,348, 1+ 55; glucose all NEGATIVE. KN564: protein NEGATIVE 5,613, TRACE 1,031; blood NEGATIVE 5,982, TRACE 662; glucose all NEGATIVE. | Mechanical |
| LBTOXGR | KN189's `ANC_GRADE`, `HGB_GRADE` and `PLT_GRADE`, attached to their tests (36,210 results). Missing everywhere else. | KN564 collects no grades. The grade's criteria (CTCAE version) are not stated. For pooled analyses, derive grades the same way for both studies in ADaM rather than use KN189's. | Choice |
| LBNRIND, reference ranges | Not derived. | No normal ranges were collected. | Mechanical |

## Timing

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| LBDTC | The date item of the result's own form, typed `date` (complete), and required. | All dates are complete. A partial date in a later cut stops the run. | Choice |
| LBDY | As collected where the form has it; missing otherwise. | No study-day item exists on the coagulation forms (both studies) or KN189's urinalysis form, so 8,441 KN189 rows and 1,988 KN564 rows have no LBDY. KN564's LBDY equals `LBDTC - RFSTDTC + 1` for all 49,981 dated occurrences. | Mechanical |

## Handler policy

This is the same policy as DM and AE:

- **No `unmapped` handler anywhere.** A new item, form or test code stops
  the run.
- **No `missing` handler anywhere.** `not_missing` guards LBORRES and LBDTC.
- **One `unconvertible` handler:** on LBSTRESN, so urinalysis text stays
  missing. The `implies` check above limits it to urinalysis.

## Data findings behind these decisions

- **KN189's screening labs carry the C1D1 date.** For every subject, the
  screening chemistry, hematology, thyroid and urinalysis forms carry the same
  date as C1D1, but their LBDY is -28. At every other visit, LBDY agrees with
  LBDTC when C1D1 is day 1. The same holds in AE: the 76 KN189 events with
  AEDY -28 carry a C1D1 start date. Either the screening dates or their study
  days are wrong in the export (the synthetic generator seems to have dated
  screening at day 1). The pooled data keep both as collected. **Raise this
  with the data providers before any baseline derivation**, because
  "last value on or before first dose" cannot tell screening from C1D1 here.
- **No units are declared** in either ODM (see LBORRESU).

## Going further (ADLB)

- **Baseline flag.** This needs each subject's first-dose date (from EX) and
  a fix for the KN189 screening dates above.
- **Toxicity grades.** Derive them from LBSTRESN with one CTCAE version for
  both studies.
- **Pooled treatment group.** Merge `TRTPOOL` from DM, as for ADAE.
