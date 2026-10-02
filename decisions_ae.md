# Decision log: pooled AE (KN189 + KN564)

This log lists every choice `ae_pooled.yaml` makes beyond copying a
collected value. All entries are **drafts by Claude, not yet reviewed**.
Each one is a proposal for the study team or the SAP to confirm or change.

The counts come from the full ODM exports. KN189 has 6,869 AE records from
606 of its 616 subjects; KN564 has 2,268 from 878 of its 994. The pooled
output has 9,137 rows, and the 2026-10-01 R run reproduced every count
below.

Status key: **Assumption** means the data cannot confirm it. **Choice**
means a reasonable option among several. **Mechanical** means it follows
from the data or CDISC conventions.

## Record structure

| Decision | Why / evidence | Status |
|---|---|---|
| One AE per item-group occurrence of the AE form (subject, visit, repeat). | In both studies every occurrence carries each AE item exactly once (13 items in KN189, 11 in KN564), with no empty values. The template groups on all eight ODM hierarchy fields, so an item recorded twice in one occurrence stops the run (`odm_not_unique`). | Mechanical |
| Occurrences are never merged. | Sixteen KN189 records repeat another record's subject, `AETERM` and `AESTDTC`, which may be the same event recorded at two visits. They are kept as separate records, like the yamaa benchmark `sdtm-ae-odm-repeated`. KN564 has no such pairs. **Please review the 16.** | Choice |

## Identifiers

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| STUDYID, USUBJID | The same as `dm_pooled.yaml`: a literal protocol number, and the ODM `SubjectKey`. | AE has to link to DM. `ae_pooled.R` checks that every AE subject is in `dm_pooled_r.csv`. | Mechanical |
| AESEQ | Derived for both studies with `row_number` within subject, in collection order (visit, then repeat within the visit). KN189's collected `AESEQ` is not read. | KN189's collected AESEQ is exactly this order; the reference simulation checks that the two are equal for all 6,869 records. KN564 collects no AESEQ, so one rule now covers both studies. The ODM's visit order is chronological (`SCREENING`, `C1D1`, `C1D8`, ...). The alternative is to order by `AESTDTC`, which would not match KN189's collected sequence. | Choice |

## Terms and coding

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| AETERM | As collected, verbatim. | It is the reported term, so it is not recoded. The case differs by study: KN189 `Anaemia`, KN564 `COUGH`. | Mechanical |
| AEDECOD | Upper case (`str_case: upper`) for both studies. | KN189 codes PTs in upper case (`NEUTROPENIA`), and KN564 in MedDRA's mixed case (`Cough`). There are 27 and 30 PTs, with no exact overlap; after upper-casing, 16 are shared. Upper case works for any PT a later cut brings. Restoring MedDRA case would need a dictionary that stops on every new PT, or sentence case, which breaks PTs such as `HIV infection`. MedDRA's own case is lost. | Choice |
| AEBODSYS | As collected. | Both studies use MedDRA's mixed-case SOC names (13 each, 10 shared). Each of the 16 shared PTs has the same SOC in both studies. | Mechanical |
| MedDRA version | Not checked. | Neither ODM states a MedDRA version. If the studies were coded on different versions, a PT or its SOC may differ for that reason. | Assumption |

## Severity and grade

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| AESEV | `MILD`, `MODERATE` and `SEVERE` kept. KN189's `LIFE-THREATENING` becomes `SEVERE`. | `LIFE-THREATENING` (571 KN189 records) is not in the CDISC AESEV codelist (MILD, MODERATE, SEVERE). In both studies AESEV and AETOXGR agree one to one (MILD 1, MODERATE 2, SEVERE 3, LIFE-THREATENING 4), so AETOXGR still holds grade 4. KN189 SEVERE is now 576 + 571 = 1,147; KN564 SEVERE is 137. | Choice |
| AESLIFE | Not derived. | "Life-threatening" here is a severity grade, not the seriousness criterion AESLIFE records. | Choice |
| AETOXGR | As collected, as text. It must be `1` to `5`. | KN189 uses 1 to 4, and KN564 uses 1 to 3. KN564's declared codelist also allows `0`, which the check rejects: grade 0 is not a CTCAE AE grade. | Choice |

## Seriousness, causality, action, outcome

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| AESER | As collected; must be `Y` or `N` and present. | KN189 Y 932 / N 5,937, KN564 Y 137 / N 2,131. No seriousness criteria (AESDTH, AESHOSP, ...) were collected. | Mechanical |
| AEREL | As collected, including KN189's `POSSIBLY RELATED`. | AEREL uses sponsor-defined terms. KN189: RELATED 4,845, POSSIBLY RELATED 1,384, NOT RELATED 640. KN564: RELATED 1,358, NOT RELATED 910. | Mechanical |
| AERELGR1 (new) | `RELATED` and `POSSIBLY RELATED` become `RELATED`; `NOT RELATED` stays. | This is the usual conservative rule for pooled safety, where "possibly" counts as related. Pooled related events: KN189 6,229, KN564 1,358. | Choice, needs SAP |
| AEACN | KN189's `DOSE INTERRUPTED` becomes `DRUG INTERRUPTED`. `DOSE NOT CHANGED` and `DRUG WITHDRAWN` are kept. | `DRUG INTERRUPTED` is the CDISC ACN term. KN189: DOSE NOT CHANGED 6,044, DOSE INTERRUPTED 682, DRUG WITHDRAWN 143. KN564: DOSE NOT CHANGED 2,190, DRUG WITHDRAWN 78. | Mechanical, please spot-check |
| AEOUT | As collected; checked against the full CDISC OUT codelist. | KN189: RECOVERED/RESOLVED 5,722, RECOVERING/RESOLVING 1,147. KN564: RECOVERING/RESOLVING for all 2,268 records, which looks like a quirk of the synthetic data. | Mechanical |

## Timing

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| AESTDTC | As collected, typed `date`, and required. | All 9,137 values are complete dates. A `date` must be a complete date (REQ-0539, REQ-0544), so a partial start date in a later cut stops the run. Switch the type to `str` if partial dates must pass. | Choice |
| AEDY | As collected (integer). | KN564's AEDY equals `AESTDTC - RFSTDTC + 1` for every record. KN189 collects no RFSTDTC; taking its C1D1 lab date as day 1 (as KN189's LBDY does), 6,793 of 6,869 records agree. The other 76 all have AEDY -28 but an AESTDTC equal to the C1D1 date: the same screening-date defect `decisions_lb.md` describes. Kept as collected; **raise with the data providers**. | Assumption (KN189) |

## Handler policy

This is the same policy as `dm_pooled.yaml`:

- **No `unmapped` handler anywhere.** A value not in a dictionary stops the
  run. New or unexpected codes surface instead of being silently recoded.
- **No `missing` handler anywhere.** A missing AEDECOD, AESEV or AEACN, and
  a missing AETERM, AEBODSYS, AESER, AEREL or AESTDTC (`not_missing`),
  stop the run. No record is missing any of them today.
- **Checked, not recoded:** AESER, AEOUT and AETOXGR have `allowed_values`.
  AEOUT's list is the full CDISC codelist, so any valid outcome passes even
  if it has not been seen yet.

## Items not carried into the pooled dataset

| Study | Items | Note |
|---|---|---|
| KN189 | `AE.AEDTC` | It equals `AESTDTC` for all 6,869 records. |
| KN189 | `AE.AESEQ` | Replaced by the derived AESEQ, which equals it. |
| Both | `AE.AEENDTC` | Declared in both ODMs, but no value was ever collected, so no end date exists. |

## Going further (ADAE)

- **Treatment-emergent flag.** This needs each subject's first-dose date.
  KN564 has `RFSTDTC` in DM, but KN189 does not. Derive it from EX first,
  then compare it with `AESTDTC`.
- **Pooled treatment group.** `TRTPOOL` lives in `dm_pooled`. A pooled ADAE
  would merge it by `STUDYID` + `USUBJID`. Remember that "Control" mixes
  placebo + chemotherapy (KN189) with placebo alone (KN564).
