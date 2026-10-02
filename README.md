# Pooling KN189 and KN564 ODM with yamaa

This folder holds three draft pooled datasets, built directly from the two
ODM exports in `submissions-pilot7-synthetic-data`:

| Dataset | Spec | Decisions | Rows |
|---|---|---|---|
| DM, one row per subject | `dm_pooled.yaml` | [`decisions.md`](decisions.md) | 1,610 subjects (616 + 994) |
| AE, one row per adverse event | `ae_pooled.yaml` | [`decisions_ae.md`](decisions_ae.md) | 9,137 events (6,869 + 2,268) |
| LB, one row per lab result | `lb_pooled.yaml` | [`decisions_lb.md`](decisions_lb.md) | 510,912 results (206,485 + 304,427) |

Each spec is the only file to edit for its dataset; both routes below read
it.

## R route

yamaa has no R engine yet. The `yamaa` R package that the benchmarks'
`run.R` files expect is still planned (issue #200), and `R/cdiscbuilder`
does not read yamaa specs. So the R route uses these scripts:

| File | Purpose |
|---|---|
| `convert_odm.R` | Turns each `*_odm.tar.gz` into a yamaa ODM input (`input/kn189_odm.parquet`, `input/kn564_odm.parquet`) that holds the 11 fixed fields, all as text. This is the R twin of `yamaa.odm.write_odm_parquet`. All three specs read these inputs. |
| `yamaa_mini.R` | A minimal R runner for **only the verbs the three specs use**. Rows: grouped or record-driven templates over ODM, with an optional `filter` (`=`, `<>`, `[NOT] IN`, `IS [NOT] NULL`, joined by `AND`); `literal`, `source`, `odm`, `str_extract`. Columns: `literal`, `source`, `mapping`, `cut`, `str_case`, `row_number`, and the `value` wrapper with `unconvertible`. Types: `str`, `int`, `float`, `date`. Checks: keys, `not_missing`, `allowed_values`, `unique`, `implies`. It reads every item binding and recoding table from the YAML, and stops on anything else rather than guess. |
| `dm_pooled.R` | Runs `dm_pooled.yaml` and writes `dm_pooled_r.csv`, then checks it against `reference/`. |
| `ae_pooled.R` | Runs `ae_pooled.yaml` and writes `ae_pooled_r.csv`, then checks it against `reference/`. It also checks that every AE subject is in `dm_pooled_r.csv`. |
| `lb_pooled.R` | Runs `lb_pooled.yaml` and writes `lb_pooled_r.csv`, then checks it against `reference/`. It also checks that every LB subject is in `dm_pooled_r.csv`. |
| `example_questions.R` | An example analysis of the three pooled CSVs (dplyr, readr): immune-related AE rates by study and arm, and highest TSH by hypothyroidism status. Run it after the three `*_pooled.R` scripts. |

```r
install.packages(c("xml2", "arrow", "yaml"))   # once
```

Then, from this folder:

```bash
Rscript convert_odm.R   # ~35 s; ~1-2 GB RAM per ODM while parsing
Rscript dm_pooled.R     # ~5 s
Rscript ae_pooled.R     # ~8 s; run after dm_pooled.R for the subject check
Rscript lb_pooled.R     # ~100 s; also after dm_pooled.R
```

`source()` from an R session in this folder works too. Every script stops
with a clear message if it is run from another folder. LB is slow because
each of its 13 record-driven templates evaluates its derivations on every
ODM record before its filter, as the rules define (REQ-0036).

Every run checks its own output. Each one prints its counts and compares
its CSV with the matching file in `reference/`, which comes from an
independent Python simulation of the spec. A good run ends like this:

```
1610 rows -> dm_pooled_r.csv
              Control Pembrolizumab
  MK-3475-189     189           427
  MK-3475-564     477           517
R runner matches reference/dm_pooled_simulated.csv

9137 rows -> ae_pooled_r.csv
            events subjects serious grade3plus related
MK-3475-189   6869      606     932       1147    6229
MK-3475-564   2268      878     137        137    1358
every AE subject is in dm_pooled_r.csv
R runner matches reference/ae_pooled_simulated.csv

510912 rows -> lb_pooled_r.csv
            results subjects tests graded numeric
MK-3475-189  206485      616    22  36210  199276
MK-3475-564  304427      994    23      0  284495
every LB subject is in dm_pooled_r.csv
R runner matches reference/lb_pooled_simulated.csv
```

The AE and LB references are reproducible. With polars installed, run:

- `python reference/simulate_ae.py`, which rewrites
  `reference/ae_pooled_simulated.csv`. It also checks that the derived AESEQ
  equals the one KN189 collected.
- `python reference/simulate_lb.py`, which rewrites
  `reference/lb_pooled_simulated.csv`.

On Linux or macOS, if `reticulate` and the Python yamaa package are both
installed, each `*_pooled.R` script also runs the real engine on the same
spec and reports whether the two outputs agree. They skip that step on
Windows (see below).

## Python route (the yamaa engine)

| File | Purpose |
|---|---|
| `convert_odm.py` | Same inputs as `convert_odm.R`, written with `yamaa.odm.write_odm_parquet`. Replaces any earlier output. |
| `run.py` | Runs the specs through the yamaa engine and writes `dm_pooled.csv`, `ae_pooled.csv` and `lb_pooled.csv`. `python run.py dm` (or `ae`, `lb`) runs one spec. |

```bash
pip install "../yamaa/python"   # Python >= 3.12
python convert_odm.py
python run.py
```

**The engine does not run on native Windows.** It opens files with
`os.open(dir_fd=...)` and `O_NOFOLLOW`, which Windows Python lacks, so it
stops with "component-safe project resource resolution is unavailable".
`run.py` checks for this and says so. Use Linux, macOS or WSL for this
route. `convert_odm.py` does work on Windows.

Two Windows install notes:

- Behind a TLS-inspecting proxy, pip fails with `CERTIFICATE_VERIFY_FAILED`.
  Add `--use-feature=truststore` so pip uses the Windows certificate store.
- pyarrow fails with `WinError 206` (path too long) if the venv path is
  deep. Keep the venv path short, for example `..\.venv`.

`convert_odm.py` writes 30 columns, and `convert_odm.R` writes 11. The extra
19 (`FormName`, `ItemName`, `SourceOrdinal`, ...) are vendor fields, which
an `odm` read never exposes (REQ-1267). The 11 schema fields are identical,
row for row, in both studies, and the R runner gives the same result on
either input.

## Why the specs are shaped this way

The two ODMs cannot share one item binding:

- Every OID carries the study's NCT number (`IT.NCT02578680.DM.SEX` vs
  `IT.NCT03142334.DM.SEX`), and an `odm` read names one exact `ItemOID`.
- The two studies don't collect the same items. In DM, KN189 has
  `AGEU`/`DMDTC` but no `SUBJID`, and KN564 has `SUBJID`/`RFSTDTC`/`REGIONUS`
  but no `AGEU`. In AE, only KN189 has `AESEQ` and `AEDTC`. In LB, the test
  items are named differently (`GLUCOSE` vs `GLUC`, `PT_INR` vs `INR`), and
  only KN189 has toxicity grades.
- They code values differently (see the decision logs).

So each spec splits into two layers:

1. **Row templates per study** (`rows: kn189`, `rows: kn564`; for LB, one
   per study and form). Each one
   reads its own ODM input and binds that study's items into shared columns,
   or into neutral `*_RAW` columns where the values need recoding.
   Templates are concatenated in order (REQ-0043). Every row-derived column
   has to appear in both templates (REQ-0200), so a study that lacks an item
   writes a `literal` instead (`AGEU: YEARS` for KN564).
2. **Column-level harmonization, shared by both studies.** `mapping` (and
   for AE, `str_case`) recodes the `*_RAW` columns once. No `unmapped`
   handler is given, so any new value stops the run instead of being
   silently recoded.

The three datasets differ mainly in how a template builds its rows:

- **DM** groups by `StudyOID` + `SubjectKey`, so each subject gives one row.
- **AE** groups by all eight ODM hierarchy fields, so each item-group
  occurrence gives one candidate row. A `filter` on the template's `FORM`
  column keeps only the AE item group. That is the pattern of the yamaa
  benchmark `sdtm-ae-odm-repeated`. A grouped filter runs after the
  template's derivations and may read only columns the template derives
  (REQ-0038, REQ-0068), which is why `FORM` is a column. `AESEQ` is then
  numbered with `row_number` within each subject, in collection order.
- **LB** has no `group_by`: each template is record-driven, so each ODM
  record (one lab result item) gives one candidate row. The labs are
  collected wide, one item per test, and the ODM input is already long, so
  nothing has to be reshaped. A record-driven row's `odm` reads see the other
  items of its own form occurrence (REQ-1269), which is how each result gets
  its own date, study day and grade. The filter reads the driver's
  `ItemGroupOID` and `ItemOID` directly and drops only the form's known
  non-result items, so a new test item stops the run at the strict
  `LBTESTCD` mapping instead of disappearing. That is the pattern of the yamaa
  benchmarks `schema-odm-item-sample` and `sdtm-fa-odm-multitest`.

The source ODM files are never rewritten. Each study keeps its own file, and
the pooling happens inside the specs, where it can be reviewed.

## Harmonization decisions (please review)

Every decision is listed in [`decisions.md`](decisions.md) (DM),
[`decisions_ae.md`](decisions_ae.md) (AE) and
[`decisions_lb.md`](decisions_lb.md) (LB). There is one row per variable,
with its evidence and its status (assumption, choice, or mechanical). Each
log includes the handler policy. These are the decisions that most need a
reviewer.

DM:

- **TRTPOOL** puts KN189's placebo + chemotherapy arm and KN564's placebo
  arm together as "Control". That is fine for pooled safety, but not for
  efficacy.
- **AGEGR1** uses a `<65` / `>=65` cut that was picked without an SAP.
- **RACE** keeps `OTHER` (KN189) and `MULTIPLE` (KN564) as-is, because no
  detail was collected to resolve them.
- **Missing values:** only SEX has a `missing` handler (missing becomes
  `U`). A missing RACE, ETHNIC, COUNTRY or AGE stops the run.
- **Codelists:** the declared ODM codelists don't match the stored data in
  either study. The dictionaries follow the data.

AE:

- **AESEV:** KN189's `LIFE-THREATENING` (571 records, all grade 4) becomes
  `SEVERE`, the top value of the CDISC codelist. `AETOXGR` keeps the grade.
- **AERELGR1** (new) counts KN189's `POSSIBLY RELATED` as related. This
  needs the SAP.
- **AEDECOD** is upper-cased for both studies. KN189 codes PTs in upper case
  and KN564 in MedDRA's mixed case, so MedDRA's own case is lost.
- **Possible duplicates:** 16 KN189 records repeat another record's subject,
  term and start date. They are kept as separate records.
- **AESTDTC** is typed `date`, so a partial start date in a later cut stops
  the run.

LB:

- **Units are inferred.** Neither ODM declares a unit. The value ranges
  agree between the studies test by test and match conventional US units,
  and KN564's item descriptions confirm five of them. Even so, the data
  providers should confirm the units.
- **FT3 vs T3:** KN189 measures free T3 and KN564 total T3. They keep
  separate test codes and are not pooled.
- **LBTOXGR** carries KN189's collected grades (ANC, HGB, PLT only). For
  pooled analyses, derive grades the same way for both studies in ADaM.
- **LBSPEC** (serum, plasma, blood, urine) is inferred from the form.

Data findings to raise with the data providers:

- **KN189's screening labs and screening AEs carry the C1D1 date**, while
  their study day says -28. Every other visit is consistent. This blocks a
  baseline derivation until it is resolved.
- **KN189's screening coagulation sample** is dated 3 days before the other
  screening labs. That is plausible, and the spec handles it, because each
  result reads its own form's date.

## Going further

- **Same pattern, one pooled spec per domain.** Repeated records (CM, MH)
  follow the AE pattern: group by the ODM hierarchy and filter to the form.
  Wide findings forms (VS, EG) follow the LB pattern: record-driven
  templates, one per study and form.
- **Pooled ADAE.** Two pieces are still missing. A treatment-emergent flag
  needs each subject's first-dose date, from EX, because KN189 has no
  `RFSTDTC`. `TRTPOOL` has to be merged from DM. See the end of
  [`decisions_ae.md`](decisions_ae.md).
- **Pooled ADLB.** This needs a baseline flag (blocked by the KN189
  screening dates), grades derived with one CTCAE version, and `TRTPOOL`.
  See the end of [`decisions_lb.md`](decisions_lb.md).
- **Submission-grade route.** Build per-study SDTM first, then pool at ADaM.
  - Put the shared columns, labels, types, and CT dicts in one parent layer.
  - Each study's `spec/yamaa/dm.yaml` lists `parents: ../../../common/dm.yaml`
    and adds only its `odm` item bindings. Columns compose field by field
    (REQ-0630).
  - A pooled ADSL then reads each study's finished output through
    `schema:` links (REQ-0520), so each study's contract is checked before
    stacking, and stacks them with the same `rows` pattern.

  This keeps the per-study SDTM a submission requires, and is how
  integrated safety (ISS) pooling is usually done.

## Status

**The R route has run end to end for DM, AE and LB.** The runs on
2026-10-01 used R 4.5.2 on Windows 11, with xml2, arrow 25.0.1 and yaml.

| Check | Result |
|---|---|
| `convert_odm.R` | KN189: 908,490 records, 616 subjects. KN564: 886,621 records, 994 subjects. |
| `convert_odm.R` vs yamaa's `write_odm_parquet` | The 11 schema fields are identical, row for row, in both studies. |
| `dm_pooled.R` | 1,610 rows, 14 columns. No `odm_not_unique` reads, no unmapped or missing values, unique keys. |
| `dm_pooled_r.csv` vs `reference/dm_pooled_simulated.csv` | Equal (`all.equal` is `TRUE`). This was re-checked after the runner moved into `yamaa_mini.R`. |
| `ae_pooled.R` | 9,137 rows, 16 columns. No `odm_not_unique` reads, no unmapped or missing values, unique keys, every check passes, and every AE subject is in DM. |
| `ae_pooled_r.csv` vs `reference/ae_pooled_simulated.csv` | Equal. The derived AESEQ also equals KN189's collected AESEQ for all 6,869 records. |
| `lb_pooled.R` | 510,912 rows, 17 columns. No `odm_not_unique` reads, no unmapped or missing values, unique keys, both `implies` checks pass, and every LB subject is in DM. |
| `lb_pooled_r.csv` vs `reference/lb_pooled_simulated.csv` | Equal (LBSTRESN compared as numbers). The simulation joins each result to its form's date and grade instead of using templates and scopes. |
| DM and AE after the LB runner changes | Both still equal to their references. |
| Strictness | Six deliberately broken specs each stopped with a clear message. For AE: a value missing from a dictionary, a value outside `allowed_values`, and an unsupported filter. For LB: a test item missing from `LBTESTCD`, a urinalysis value outside the `implies` list, and a missing `unconvertible`. |
| Counts in the decision logs | All re-derived from the R output and confirmed. |

**The yamaa engine itself has not run on these specs.** It cannot run on
native Windows (see "Python route"), so `run.py` and the engine
cross-checks are still to be run on Linux, macOS or WSL. Until then, the
evidence that each spec means what the R runner does is the following:

- Each spec was checked against the rules and against the closest
  benchmark: `schema-odm-column-override` for DM, `sdtm-ae-odm-repeated`
  for AE, and `schema-odm-item-sample` and `sdtm-fa-odm-multitest` for LB.
  Three examples:
  - `cut.right` defaults to `false` (left-closed), so age 65 falls in
    `>=65`.
  - `allowed_values` lets a missing value pass (REQ-0376), so a column that
    must be present also declares `not_missing`.
  - A record-driven template's derivations run on every ODM record before
    its filter (REQ-0036), so LB keeps its strict recodes at column level,
    where only the kept rows reach them.
- Two independent implementations agree for each dataset: the R runner and
  a Python simulation.

The R runner covers only the verbs these specs use. When a spec gains a new
verb, the runner stops with "not supported by this runner" rather than
guessing.
