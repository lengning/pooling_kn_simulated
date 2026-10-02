# Decision log: pooled DM (KN189 + KN564)

Every choice `dm_pooled.yaml` makes beyond copying a collected value. All
entries are **drafts by Claude, not yet reviewed**. Each one is a proposal
for the study team or the SAP to confirm or change. Counts come from the
full ODM exports (KN189: 616 subjects, KN564: 994). On 2026-10-01 every count
here was re-derived from the R run's output, `dm_pooled_r.csv`, and all of
them matched.

Status key: **Assumption** means the data cannot confirm it. **Choice**
means a reasonable option among several. **Mechanical** means it follows
from the data or CDISC conventions.

## Identifiers

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| STUDYID | Literal `MK-3475-189` / `MK-3475-564`, from `ProtocolName`. The ODM `StudyOID` (`ST.NCT02578680`) is not used. | A protocol number is the usual STUDYID. The ODM OID is a file identifier. | Choice |
| USUBJID | The ODM `SubjectKey` as-is (`KEYNOTE189_SIM-SITE001-0028`, `KEYNOTE564-S001-0011`). | It is already unique across both studies (1,610 distinct values). The common `STUDYID-SITEID-SUBJID` form was **not** built. If per-study SDTM uses a different USUBJID, this must match it. | Choice |
| SUBJID | KN189: the trailing digits of `SubjectKey` (`0028`). KN564: the collected `DM.SUBJID` item. | KN189 has no SUBJID item. For KN564, the collected value equals the key's trailing digits. | Assumption (KN189) |
| SITEID | As collected. | The formats differ (`SITE001` vs `S001`), and a site number is unique only within its STUDYID. No pooled site grouping was made. | Mechanical |

## Demographics

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| AGE | As collected (integer). A missing age stops the run. | Present for all subjects in both studies. | Mechanical |
| AGEU | KN189: collected (`YEARS` for all 616). KN564: literal `YEARS`. | KN564 collects no age unit; `YEARS` is assumed. | Assumption |
| AGEGR1 | `<65` / `>=65`, left-closed, so age 65 falls in `>=65`. | A common pooled-safety cut, chosen without an SAP. Split: KN189 365 / 251, KN564 751 / 243. | Choice, needs SAP |
| SEX | `M` and `F` kept as-is; missing becomes `U`. | Data: KN189 M 380 / F 236, KN564 M 684 / F 310, none missing. SEX is the **only** variable given a `missing` handler; see "Handler policy". | Choice |
| RACE | `BLACK` becomes `BLACK OR AFRICAN AMERICAN`. `WHITE`, `ASIAN`, `AMERICAN INDIAN OR ALASKA NATIVE`, `OTHER`, `MULTIPLE` and `UNKNOWN` are kept. | KN189 collects `BLACK` (18 subjects); KN564 collects the CDISC term (12). | Mechanical (BLACK) |
| RACE: `OTHER` | Kept as `OTHER`. | 14 KN189 subjects. No "specify" text was collected, so there is nothing to map them to. | Choice |
| RACE: `MULTIPLE` | Kept as `MULTIPLE`. | 13 KN564 subjects. The individual races are not on the DM form, so SUPPDM `RACE1`, `RACE2`... cannot be built. | Choice |
| RACE: `UNKNOWN` | Kept as `UNKNOWN`. | 81 KN564 subjects; KN189 has none. It was not merged with "Not reported". | Choice |
| ETHNIC | Both values kept as-is. | Both studies collect `HISPANIC OR LATINO` / `NOT HISPANIC OR LATINO`, none missing. Split: KN189 38 / 578, KN564 135 / 859. | Mechanical |
| COUNTRY | Mapped to ISO 3166-1 alpha-3. KN189 already collects alpha-3 (10 countries). KN564 collects names (12), mapped by hand: Australia AUS, Canada CAN, China CHN, France FRA, Germany DEU, Italy ITA, Japan JPN, "Korea, Republic of" KOR, Russian Federation RUS, Spain ESP, United Kingdom GBR, United States USA. | SDTM COUNTRY uses alpha-3. | Mechanical, please spot-check |

## Treatment

| Variable | Decision | Why / evidence | Status |
|---|---|---|---|
| ARMCD, ARM | As collected, not harmonized. | They are study-specific: KN189 `PEMBRO` / `CONTROL`, KN564 `PEMBRO` / `PBO`. | Mechanical |
| TRTPOOL (new) | `PEMBRO` becomes `Pembrolizumab`; `CONTROL` and `PBO` become `Control`. | KN189 control is placebo + pemetrexed + platinum (189); KN564 control is placebo alone (477). "Control" therefore mixes two different comparators. That is fine for pooled safety or demographics, but not for efficacy. | Choice, needs SAP |

## Handler policy (applies to every recoding)

- **No `unmapped` handler anywhere.** A value not in a dictionary stops the
  run. New or unexpected codes surface instead of being silently recoded.
- **A `missing` handler only on SEX** (missing becomes `U`). RACE, ETHNIC,
  COUNTRY and AGE have none, so a missing value stops the run. No subject
  is missing any of them today. This asymmetry is a choice: decide whether
  RACE should also default (for example to `NOT REPORTED`) or stay strict.

## Items not carried into the pooled dataset

| Study | Items | Note |
|---|---|---|
| KN189 | `DM.DMDTC` | Demographics collection date. |
| KN564 | `DM.RFSTDTC`, `DM.REGIONUS` | RFSTDTC exists only in KN564. For KN189 it would have to come from first EX dose. REGIONUS is a KN564 stratification factor. |

## Data findings behind these decisions

The ODM codelists don't match the stored data, so every dictionary in the
spec was built from the values **actually observed**, not from the declared
codelists:

- KN189's SEX codelist declares `UNDIFFERENTIATED, F, M, U`, and the data
  use only `M` and `F`.
- KN189's RACE codelist declares title-case subcategories (`Chinese`,
  `Japanese`, `Arab`, `Prefer not to answer`, ...). The data use `WHITE`,
  `ASIAN`, `BLACK` and `OTHER`, none of which appear in that codelist.
- KN564's SEX codelist declares `Male, Female, Unknown`, and the data use
  `M` and `F`.
- KN564's RACE codelist is title case and has no `MULTIPLE`. The data are
  upper case and include `MULTIPLE` (13 subjects).

If a later data cut uses the declared codelist values, the run will stop on
them. That is intentional; add the dictionary entries once they are reviewed.
