# Two Trials, One Spec

*Field notes on agents and clinical data · October 2026 · DM, AE, LB · KEYNOTE-189 + KEYNOTE-564, simulated data*

I asked an AI agent to pool demographics, adverse events and lab results from two simulated oncology trials. It wrote the specifications in a language called yamaa, ran them, checked its own output, and handed back a short list of decisions that needed a person. Here is how that went, step by step.

> **Simulated data.** Everything in this post uses simulated data. The two studies are synthetic datasets modelled on the KEYNOTE-189 and KEYNOTE-564 protocols and published by the R Consortium Submissions Working Group (Pilot 7). They contain no real patient data, and none of the results here say anything about pembrolizumab.

## Why pool, and why it hurts

A single trial answers the question it was designed for. Pooled data answers the questions that cut across trials. Does an immune-related adverse event show up at the same rate in lung cancer and in kidney cancer? Do patients who report hypothyroidism also show it in their TSH? Is a lab shift in one study a drug effect, or a quirk of that study's population? Safety reviewers, clinicians and regulators all ask questions like these, and they almost always start from three datasets: demographics (DM), adverse events (AE) and labs (LB).

The trouble is that no two studies collect data the same way. Item names differ. Code lists differ. One study records a toxicity grade and the other doesn't. So pooling has always been a loop, and a slow one. Most of the time in that loop goes into discovering the data: finding out that one study writes `GLUCOSE` and the other `GLUC`, that one codes preferred terms in upper case, that a date sits on a different form than you expected. Each discovery sends you back to the spec.

I wanted to see what happens when an agent runs that loop. I gave Claude Code, Anthropic's coding agent, the raw EDC exports of two studies and a specification language called yamaa, and asked it to pool DM, then AE, then LB.

**The usual way**

1. Draft a spec for each study
2. Agree how the studies will be pooled
3. Program it and look at each study's data
4. Find surprises in the data and revise the spec

↺ back to step 2, for weeks

**With an agent**

1. The agent reads the language rules, worked examples and both studies' data
2. It drafts the specs, with a decision log for each domain
3. It runs them and checks the output several independent ways
4. It hands back a short list of decisions that need a person

↺ people decide; the agent edits the spec and reruns

The loop doesn't go away. The agent runs the discovery part of it, and people get the decisions.

The data come from the R Consortium Submissions Working Group's Pilot 7, which publishes simulated trials modelled on real protocols:

- **KEYNOTE-189** (NCT02578680): pembrolizumab plus pemetrexed and platinum, against placebo plus the same chemotherapy, in metastatic non-squamous non-small cell lung cancer. 616 simulated subjects.
- **KEYNOTE-564** (NCT03142334): adjuvant pembrolizumab against placebo after surgery for renal cell carcinoma. 994 simulated subjects.

Different indications, different control arms, different case report forms. That makes for a realistic pooling problem.

*Every subject, event and lab value below is simulated. The numbers show how the workflow behaves and say nothing about pembrolizumab.*

## Four decisions, up close

Before the details of yamaa, here is what an agent decision looks like in practice. Each one follows the same path. A query turns up evidence in the data, the agent makes a call, the call becomes a few lines of the spec, and the decision log records it with a status. The agent made the first three on its own. It implemented the fourth provisionally and handed it back to a person. The YAML is explained in the next section; for now, read each snippet as a lookup table.

### Decided by the agent: race, one study's term becomes the CDISC term

**Found.** KEYNOTE-189 records race as `BLACK` (18 subjects); KEYNOTE-564 records `BLACK OR AFRICAN AMERICAN` (12). KEYNOTE-189 also has `OTHER` (14) and KEYNOTE-564 has `MULTIPLE` (13), with no detail collected for either. Neither study's declared codelist matches its stored values, so the dictionary follows the data.

**Decided.** Map `BLACK` to the CDISC term. Keep `OTHER` and `MULTIPLE` as they are, because there is nothing to resolve them with.

**Implemented.**

```yaml
- name: RACE
  derivation:
    mapping:
      source: RACE_RAW
      dict:
        BLACK: BLACK OR AFRICAN AMERICAN                       # KEYNOTE-189
        BLACK OR AFRICAN AMERICAN: BLACK OR AFRICAN AMERICAN   # KEYNOTE-564
        OTHER: OTHER                                           # KEYNOTE-189
        MULTIPLE: MULTIPLE                                     # KEYNOTE-564
        # ...plus WHITE, ASIAN, AMERICAN INDIAN OR ALASKA NATIVE, UNKNOWN
```

**Logged as.** Mechanical for `BLACK`; Choice for keeping `OTHER` and `MULTIPLE`.

### Decided by the agent: glucose, four item names, two specimens, one test code

**Found.** Serum glucose is the item `GLUCOSE` in KEYNOTE-189 and `GLUC` in KEYNOTE-564. Both sit on the same scale (medians 102 and 98), which fits mg/dL. Urine glucose is two more items, `UGLU` and `UAGLUC`, and every result is `NEGATIVE`. Neither ODM declares a unit.

**Decided.** All four items become test code `GLUC`. The category and specimen columns tell serum from urine. Serum results get mg/dL; urine results get no unit.

**Implemented.**

```yaml
# LBTESTCD
LB_CHEM.GLUCOSE: GLUC     # KEYNOTE-189, serum
LB_CHEM.GLUC: GLUC        # KEYNOTE-564, serum
LB_UA.UGLU: GLUC          # KEYNOTE-189, urine
LB_UA.UAGLUC: GLUC        # KEYNOTE-564, urine

# LBORRESU
LB_CHEM.GLUCOSE: mg/dL
LB_CHEM.GLUC: mg/dL
LB_UA.UGLU: null
LB_UA.UAGLUC: null
```

**Logged as.** Mechanical for the test code; Assumption for the unit.

### Decided by the agent: age unit, an item one study never collected

**Found.** KEYNOTE-189 collects an age unit, `YEARS` for all 616 subjects. KEYNOTE-564's demographics form has no age-unit item; its ages run from 19 to 88.

**Decided.** KEYNOTE-564's AGEU is the literal `YEARS`. Every row template must produce the same columns (REQ-0200), so the missing item has to be filled somehow, and that age range only makes sense in years.

**Implemented.**

```yaml
# KEYNOTE-189 template: read the collected item
AGEU: {odm: ODM189.IT.NCT02578680.DM.AGEU}

# KEYNOTE-564 template: no item to read
AGEU: {literal: YEARS}
```

**Logged as.** Assumption.

### Handed back to a person: pooled treatment group, what counts as "Control"?

**Found.** Both studies have a pembrolizumab arm (427 and 517 subjects). Their controls differ: placebo plus pemetrexed and platinum in KEYNOTE-189 (189 subjects), placebo alone in KEYNOTE-564 (477).

**Drafted.** A provisional answer, so the pipeline could run: both control arms become "Control".

**Implemented.**

```yaml
- name: TRTPOOL
  derivation:
    mapping:
      source: ARMCD
      dict:
        PEMBRO: Pembrolizumab
        CONTROL: Control          # KEYNOTE-189: placebo + chemotherapy
        PBO: Control              # KEYNOTE-564: placebo alone
```

**Logged as.** Choice, needs SAP. The log says: "Control" therefore mixes two different comparators. That is fine for pooled safety or demographics, but not for efficacy.

**Handed back.** **The agent put it first in its list of decisions that most need a reviewer.** A statistician decides whether one Control group is right for the planned analyses, or whether the two controls stay apart. The agent did not stop and wait for the answer. Changing it later is one line of YAML.

## yamaa in five minutes

yamaa is a domain-specific language for clinical data standardization. You write a specification in YAML that says what each column of a dataset is and how it is derived; an engine reads the raw data and builds the dataset. The input is the ODM XML that an EDC system exports, and the outputs are CDISC SDTM and ADaM datasets. It is open source under the MIT license, at [github.com/elong0527/yamaa](https://github.com/elong0527/yamaa).

Four ideas cover most of it.

**A spec is a list of columns.** Each column has a name, a type and a derivation. Derivations come from a closed set of verbs: `source` copies a value, `mapping` recodes through a dictionary, `cut` bins a number, `row_number` numbers rows within a group, and so on. Here is the column that harmonizes sex across our two studies:

```yaml
- name: SEX
  type: str
  label: Sex
  derivation:
    mapping:
      source: SEX_RAW
      dict: {M: M, F: F}
      missing: U
```

*From `dm_pooled.yaml`*

**Rows come from templates.** A `rows` section says how the output rows are built. A template can group input records (one row per subject) or take them one at a time (one row per lab result). A spec can hold several templates, and their rows are stacked in order. This turns out to be the key to pooling.

**It refuses to guess.** The project's founding rule reads:

> A yamaa specification has exactly one execution. Where it would have two, yamaa fails instead of choosing.

In practice, the sex mapping above has no `unmapped:` entry, so a value other than `M` or `F` stops the run and names the value. It does have `missing: U`, so a missing sex becomes `U`. The race mapping in the previous section has no `missing:` entry, so a missing race stops the run. Leaving out a handler makes its condition fatal (REQ-0344). That strictness matters later, because it is how a spec keeps asking questions after the agent has finished.

**Every behavior has a numbered rule.** The rules directory holds more than 1,200 numbered requirements, from when a template's filter runs (REQ-0038) to what happens when an item is recorded twice (REQ-1272). About 300 runnable benchmark specs show the rules in use. For an agent this is ideal. It can look up what a construct means instead of guessing, and cite the rule in a comment for the human who reviews it.

### What the input looks like

yamaa reads ODM as one long table: one row per recorded item, together with the study, visit, form and item group it belongs to. The table always has the same eleven fields. These rows are taken directly from the simulated KEYNOTE-189 export, for one subject:

| SubjectKey | StudyEventOID | ItemGroupOID | Repeat | ItemOID | Value |
|---|---|---|---|---|---|
| KEYNOTE189_SIM-SITE001-0028 | SE.NCT02578680.SCREENING | IG.NCT02578680.DM | | IT.NCT02578680.DM.ARMCD | PEMBRO |
| KEYNOTE189_SIM-SITE001-0028 | SE.NCT02578680.SCREENING | IG.NCT02578680.DM | | IT.NCT02578680.DM.ARM | Pembrolizumab + Pemetrexed + Platinum |
| KEYNOTE189_SIM-SITE001-0028 | SE.NCT02578680.C1D1 | IG.NCT02578680.AE | 1 | IT.NCT02578680.AE.AETERM | Neutropenia |
| KEYNOTE189_SIM-SITE001-0028 | SE.NCT02578680.C1D1 | IG.NCT02578680.AE | 1 | IT.NCT02578680.AE.AEDECOD | NEUTROPENIA |
| KEYNOTE189_SIM-SITE001-0028 | SE.NCT02578680.C2D1 | IG.NCT02578680.LB_CHEM | | IT.NCT02578680.LB_CHEM.LBDTC | 2016-04-19 |
| KEYNOTE189_SIM-SITE001-0028 | SE.NCT02578680.C2D1 | IG.NCT02578680.LB_CHEM | | IT.NCT02578680.LB_CHEM.ALT | 22 |

*Six of the eleven fields. The others are StudyOID, MetaDataVersionOID, StudyEventRepeatKey, FormOID and FormRepeatKey.*

Every identifier carries the study's NCT number. That small detail shapes the whole design, because a spec that reads `IT.NCT02578680.DM.SEX` cannot read KEYNOTE-564's sex item, which is `IT.NCT03142334.DM.SEX`.

## What the agent did, step by step

### Step 1. Read before writing

Before it wrote any YAML, the agent read. It looked up the yamaa rules for each construct it planned to use, found the closest benchmark spec for each domain, and profiled both studies with short queries. Which forms exist? Which items does each form hold? Does any item repeat inside a form? How are the values coded, and what ranges do the numbers fall in? Almost every decision later in this post traces back to one of those queries.

### Step 2. Turn ODM XML into yamaa input

A short R script converts each study's ODM XML into the eleven-field table: 908,490 item records for KEYNOTE-189 and 886,621 for KEYNOTE-564. The agent then ran yamaa's own Python converter on the same files and compared the two. The eleven fields matched row for row in both studies.

### Step 3. Get a runner

yamaa's Python engine needs POSIX file APIs that Windows Python lacks, and I work on Windows. The yamaa R package is still being built. So the agent wrote a small R runner, `yamaa_mini.R`, that implements only the verbs these specs use and stops with "not supported by this runner" on anything else. The runner grew a little with each domain: grouped templates for DM, filters and `row_number` for AE, record-driven templates and numeric conversion for LB.

Running the R route takes one command per step:

```bash
Rscript convert_odm.R   # ODM XML to input/*.parquet, about 35 s
Rscript dm_pooled.R     # writes dm_pooled_r.csv, about 5 s
Rscript ae_pooled.R     # writes ae_pooled_r.csv, about 8 s
Rscript lb_pooled.R     # writes lb_pooled_r.csv, about 100 s
```

*Each script prints its counts and ends by comparing its output with the reference simulation.*

Each verb in the runner is small. The `odm` read, which every DM, AE and LB template relies on, is about 20 lines. It finds the records for the named item and looks up each output row by its place in the ODM hierarchy: its subject or form occurrence for DM and AE, its own form occurrence for LB. If an item was recorded twice in one place, the read stops (REQ-1272).

On Linux or macOS, the official engine runs the same spec from Python:

```python
import yamaa

run = yamaa.yamaa_domain("lb_pooled.yaml", schema_root="../yamaa/yaml")
if run.output is None:
    print(run.issues)   # validation or execution stopped; each issue names its rule
else:
    run.save()          # writes lb_pooled.csv, the path the spec declares
```

*Condensed from `run.py`*

That shortcut has a cost, which I come back to in the section on quality: the official engine has not run these specs yet.

### Step 4. DM: one row per subject

The two studies cannot share item bindings. Their item OIDs differ, they collect different items (KEYNOTE-189 records an age unit but no subject ID; KEYNOTE-564 the reverse), and they code values differently. So the spec has two layers:

| Layer | What it does |
|---|---|
| KEYNOTE-189 template | Reads `kn189_odm`, one row per subject, binds its items to `*_RAW` columns |
| KEYNOTE-564 template | Reads `kn564_odm`, one row per subject, binds its items to `*_RAW` columns |
| Shared columns | One mapping per variable recodes the `*_RAW` values for both studies |
| Checks | Types, unique keys, allowed values; any surprise stops the run |

The study templates absorb the differences; the shared layer holds every pooling rule once.

The first layer is one row template per study. Each reads its own ODM table, groups by subject, and binds that study's items into neutral columns:

```yaml
rows:
  - id: kn189
    dataset: ODM189
    group_by: [ODM189.StudyOID, ODM189.SubjectKey]
    derivations:
      STUDYID: {literal: MK-3475-189}
      USUBJID: ODM189.SubjectKey
      SEX_RAW: {odm: ODM189.IT.NCT02578680.DM.SEX}
      RACE_RAW: {odm: ODM189.IT.NCT02578680.DM.RACE}
      AGEU: {odm: ODM189.IT.NCT02578680.DM.AGEU}

  - id: kn564
    dataset: ODM564
    group_by: [ODM564.StudyOID, ODM564.SubjectKey]
    derivations:
      STUDYID: {literal: MK-3475-564}
      USUBJID: ODM564.SubjectKey
      SEX_RAW: {odm: ODM564.IT.NCT03142334.DM.SEX}
      RACE_RAW: {odm: ODM564.IT.NCT03142334.DM.RACE}
      # KEYNOTE-564 collects no age unit
      AGEU: {literal: YEARS}
```

*Excerpt from `dm_pooled.yaml`*

The second layer is shared. Column derivations such as the race and sex mappings shown earlier recode the raw values once, for both studies. Every template must produce the same columns (REQ-0200), so a study that lacks an item writes a literal instead, as KEYNOTE-564 does for `AGEU`.

An earlier agent session had drafted this DM spec in a sandbox with no R, so it had never run. Here it ran on the first try: 1,610 subjects, identical to a reference file that the earlier session had produced with a separate simulation. Here is one subject from each study:

| STUDYID | USUBJID | AGE | AGEGR1 | SEX | RACE | ETHNIC | COUNTRY | ARMCD | TRTPOOL |
|---|---|---:|---|---|---|---|---|---|---|
| MK-3475-189 | KEYNOTE189_SIM-SITE001-0028 | 73 | >=65 | M | WHITE | NOT HISPANIC OR LATINO | USA | PEMBRO | Pembrolizumab |
| MK-3475-564 | KEYNOTE564-S001-0011 | 50 | <65 | M | WHITE | NOT HISPANIC OR LATINO | JPN | PBO | Control |

*From `dm_pooled_r.csv`; SUBJID, SITEID, AGEU and ARM omitted. KEYNOTE-564 collects its country as "Japan"; the shared mapping turned it into JPN.*

### Step 5. AE: one row per event

Adverse events repeat. A subject can report several at one visit, each in its own repeat of the AE form. The agent followed yamaa's AE benchmark: each template groups by all eight ODM hierarchy fields, so every form occurrence becomes a candidate row, and a filter keeps only the AE form.

```yaml
  - id: kn189
    dataset: ODM189
    group_by:
      - ODM189.StudyOID
      - ODM189.SubjectKey
      - ODM189.StudyEventOID
      # ...and the other five hierarchy fields
    filter: "FORM = 'IG.NCT02578680.AE'"
    derivations:
      FORM: ODM189.ItemGroupOID
      AETERM: {odm: ODM189.IT.NCT02578680.AE.AETERM}
      AESEV_RAW: {odm: ODM189.IT.NCT02578680.AE.AESEV}
```

*Excerpt from `ae_pooled.yaml`*

The sequence number comes from a window function. With no `order_by`, ties keep the order in which the rows were built, which here is visit order (REQ-1123):

```yaml
  - name: AESEQ
    type: int
    derivation:
      row_number:
        window:
          group_by: [STUDYID, USUBJID]
```

That choice could be checked. KEYNOTE-189 collects its own AESEQ, and the derived one matched it for all 6,869 events. KEYNOTE-564 collects none, so one rule now covers both studies.

Most of the judgment in AE went into harmonization. KEYNOTE-189 codes preferred terms in upper case (`NEUTROPENIA`) and KEYNOTE-564 in MedDRA's mixed case (`Cough`). KEYNOTE-189 also has a `LIFE-THREATENING` severity that isn't in the CDISC codelist, a `POSSIBLY RELATED` causality, and `DOSE INTERRUPTED` where CDISC says `DRUG INTERRUPTED`. Each of these got a rule in the spec and an entry in the log. The result is 9,137 events. Here are the same two subjects:

| USUBJID | AESEQ | AETERM | AEDECOD | AESEV | AESER | AEREL | AERELGR1 | AETOXGR | AESTDTC | AEDY |
|---|---:|---|---|---|---|---|---|---|---|---:|
| KEYNOTE189_SIM-SITE001-0028 | 1 | Neutropenia | NEUTROPENIA | MODERATE | N | RELATED | RELATED | 2 | 2016-04-01 | 1 |
| KEYNOTE189_SIM-SITE001-0028 | 2 | Neutropenia | NEUTROPENIA | SEVERE | Y | RELATED | RELATED | 4 | 2016-04-11 | 11 |
| KEYNOTE189_SIM-SITE001-0028 | 3 | Nausea | NAUSEA | MILD | N | POSSIBLY RELATED | RELATED | 1 | 2016-04-03 | 3 |
| KEYNOTE564-S001-0011 | 1 | COUGH | COUGH | MILD | N | NOT RELATED | NOT RELATED | 1 | 2018-09-01 | 102 |
| KEYNOTE564-S001-0011 | 2 | HYPOTHYROIDISM | HYPOTHYROIDISM | MILD | N | RELATED | RELATED | 1 | 2018-11-29 | 191 |

*From `ae_pooled_r.csv`; STUDYID, DOMAIN, AEBODSYS, AEACN and AEOUT omitted. The first subject has 8 events; the first three are shown.*

Three decisions are visible in these rows. AEDECOD is upper case for both studies, while AETERM keeps each study's own case. KEYNOTE-189's "possibly related" nausea counts as related in AERELGR1. And AESEQ follows collection order, so the nausea that began on 3 April is event 3, after a neutropenia that began on 11 April. The second neutropenia is grade 4, which KEYNOTE-189 recorded as `LIFE-THREATENING`; AESEV now says `SEVERE`.

### Step 6. LB: one row per result

Labs are collected wide: one item per test on five forms (chemistry, coagulation, hematology, thyroid, urinalysis), with the sample date as another item on the same form. SDTM wants one row per test. Because the ODM table already holds one record per item, nothing has to be reshaped. Each LB template is record-driven: every ODM record becomes a candidate row, and the filter keeps the form's results and drops its date and study-day items.

The interesting part is the date. A record-driven row can read the other items of its own form occurrence (REQ-1269), so each result reads the date from its own form:

```yaml
  - id: kn189-coag
    dataset: ODM189
    filter: "ODM189.ItemGroupOID = 'IG.NCT02578680.LB_COAG' AND
      ODM189.ItemOID <> 'IT.NCT02578680.LB_COAG.LBDTC'"
    derivations:
      ITEM: {str_extract: {source: ODM189.ItemOID, pattern: '[^.]+\.[^.]+$'}}
      LBORRES: ODM189.Value
      # the date item of this result's own form occurrence
      LBDTC: {odm: ODM189.IT.NCT02578680.LB_COAG.LBDTC}
```

*Excerpt from `lb_pooled.yaml`, comment added*

This turned out to matter. While profiling, the agent found that every KEYNOTE-189 subject's screening coagulation sample was drawn three days before the other screening labs. A design that took one date per visit would have misdated those 616 results.

The two studies name their tests differently, so one shared mapping turns item names into CDISC test codes:

```yaml
  - name: LBTESTCD
    derivation:
      mapping:
        source: ITEM
        dict:
          LB_CHEM.GLUCOSE: GLUC     # KEYNOTE-189
          LB_CHEM.GLUC: GLUC        # KEYNOTE-564
          LB_COAG.PT_INR: INR       # KEYNOTE-189
          LB_COAG.INR: INR          # KEYNOTE-564
          LB_THY.FT3: T3FR          # free T3, KEYNOTE-189 only
          LB_THY.T3: T3             # total T3, KEYNOTE-564 only
```

*Excerpt from `lb_pooled.yaml`, comments added; the full dictionary has 30 entries*

KEYNOTE-189 also records toxicity grades for three hematology tests. Each of those tests got its own template so its results could read their own grade item. In all, the LB spec has 13 templates and produces 510,912 results. Here are four of the first subject's screening results:

| LBSEQ | LBTESTCD | LBCAT | LBORRES | LBORRESU | LBSTRESN | LBTOXGR | VISIT | LBDTC | LBDY |
|---:|---|---|---|---|---:|---|---|---|---:|
| 1 | APTT | COAGULATION | 26.3 | sec | 26.3 | | SCREENING | 2016-03-29 | |
| 5 | ALT | CHEMISTRY | 27 | U/L | 27 | | SCREENING | 2016-04-01 | -28 |
| 25 | NEUT | HEMATOLOGY | 2.41 | 10^9/L | 2.41 | 0 | SCREENING | 2016-04-01 | -28 |
| 41 | PROT | URINALYSIS | 1+ | | | | SCREENING | 2016-04-01 | |

*From `lb_pooled_r.csv`, subject KEYNOTE189_SIM-SITE001-0028; STUDYID, DOMAIN, USUBJID, LBTEST, LBSPEC, LBSTRESC and LBSTRESU omitted.*

Each row shows a decision from this step. The coagulation result carries its own form's date, three days before the others, and has no study day because its form has none. The neutrophil count carries KEYNOTE-189's collected grade. The urine protein result has no unit and no numeric value. The other screening rows also show the date problem described further down: they are dated 1 April, the same day as this subject's C1D1 visit, with a study day of −28.

### Step 7. Ask the questions

With three pooled datasets, the questions from the top of this post take one join and one group-by each, run on the three CSVs the runner wrote. The analysis script, `example_questions.R`, is in the project folder and reproduces both tables below in about 3 seconds.

Hypothyroidism, an immune-related adverse event, shows up in both indications at similar rates on pembrolizumab:

| Preferred term | KN-189 pembro (N=427) | KN-189 control (N=189) | KN-564 pembro (N=517) | KN-564 placebo (N=477) |
|---|---:|---:|---:|---:|
| Hypothyroidism | 64 (15.0%) | 0 | 91 (17.6%) | 16 (3.4%) |
| Hyperthyroidism | 21 (4.9%) | 0 | 59 (11.4%) | 1 (0.2%) |
| Pneumonitis | 36 (8.4%) | 0 | 3 (0.6%) | 0 |
| Colitis | 25 (5.9%) | 0 | 3 (0.6%) | 0 |
| Hepatitis | 17 (4.0%) | 0 | 2 (0.4%) | 1 (0.2%) |

*Subjects with at least one event. Simulated data; the KEYNOTE-189 control arm has none of these terms.*

Subjects with a hypothyroidism event also had higher TSH during the study:

| Study | Hypothyroidism AE | Subjects | Median of highest TSH (mIU/L) | Highest TSH > 10 |
|---|---|---:|---:|---:|
| KEYNOTE-189 | No | 552 | 3.64 | 0.0% |
| KEYNOTE-189 | Yes | 64 | 7.28 | 4.7% |
| KEYNOTE-564 | No | 887 | 2.17 | 0.0% |
| KEYNOTE-564 | Yes | 107 | 13.96 | 77.6% |

*AE joined to LB on study and subject. The TSH unit is one the agent inferred; see below.*

One subject shows the same pattern over time. KEYNOTE564-S001-0011, from the two subjects above, is in the placebo arm and reported hypothyroidism on day 191. Their TSH results, in the order LBSEQ gives them:

| LBSEQ | VISIT | LBDTC | LBDY | TSH (mIU/L) |
|---:|---|---|---:|---:|
| 20 | SCRN | 2018-04-25 | -28 | 2.59 |
| 41 | C1D1 | 2018-05-23 | 1 | 2.55 |
| 77 | C3D1 | 2018-07-03 | 42 | 2.79 |
| 113 | C5D1 | 2018-08-17 | 87 | 2.81 |
| 146 | C7D1 | 2018-09-27 | 128 | 2.48 |
| 182 | C9D1 | 2018-11-06 | 168 | 2.63 |
| 218 | C11D1 | 2018-12-18 | 210 | 6.54 |
| 251 | C13D1 | 2019-01-28 | 251 | 8.65 |
| 287 | C15D1 | 2019-03-10 | 292 | 9.40 |
| 320 | C17D1 | 2019-04-23 | 336 | 12.43 |

*From `lb_pooled_r.csv`, LBTESTCD = TSH. The hypothyroidism event starts between the C9D1 and C11D1 samples. Simulated data.*

Read all three tables as a test of the plumbing. With simulated data, they show that the pooled datasets join cleanly and answer cross-study questions. They don't show anything about the drug.

## What the agent decided on its own

The agent made a lot of decisions without asking me. What made that acceptable is that it wrote every one of them down. Each domain has a decision log: a plain markdown table with one row per decision, giving what was decided, the evidence from the data, and a status.

- **Mechanical**: follows from the data or from CDISC conventions. KEYNOTE-189's `BLACK` becomes `BLACK OR AFRICAN AMERICAN`.
- **Choice**: a reasonable option among several, with the alternatives named. The age cut at 65.
- **Assumption**: something the data cannot confirm. KEYNOTE-564's age unit is years.

The three logs hold 57 entries: 28 mechanical, 23 choices and 6 assumptions. A sample:

| Domain | Decision | Evidence | Status |
|---|---|---|---|
| DM | KEYNOTE-189 has no subject ID item, so SUBJID is the trailing digits of the subject key. | In KEYNOTE-564 the collected SUBJID equals its key's trailing digits. | Assumption |
| DM | KEYNOTE-189's `BLACK` becomes `BLACK OR AFRICAN AMERICAN`. | KEYNOTE-189 collects BLACK (18 subjects); KEYNOTE-564 uses the CDISC term (12). | Mechanical |
| AE | AESEQ numbers events in collection order. | Reproduces KEYNOTE-189's collected AESEQ for all 6,869 events. | Choice |
| AE | Preferred terms are upper-cased for both studies. | 27 and 30 terms with no exact overlap; 16 shared after upper-casing, each with the same organ class. | Choice |
| LB | Free T3 (KEYNOTE-189) and total T3 (KEYNOTE-564) stay separate tests. | Medians of 3.1 and 119: different analytes on different scales. | Mechanical |
| LB | Units are inferred from value ranges. | Neither ODM declares a unit; the ranges agree test by test between the studies. | Assumption |

*From `decisions.md`, `decisions_ae.md` and `decisions_lb.md`*

Two properties make this reviewable. Every entry cites evidence a reviewer can check: a count, a codelist, a rule number. And every decision is a line or two of YAML, so changing one is cheap. The agent never edited the source data. All of the pooling happens inside the specs, where it can be read and diffed.

## Where the agent handed decisions back

In this run the agent never stopped mid-task to ask me a question. I set the scope and the order (DM, then AE, then LB), and at the end I asked for a review list. In between, it made provisional calls and logged them. The decisions it handed back fall into four groups. Each item that needs a person is in bold.

**Statistical choices that belong to the analysis plan.** The agent drafted these and put them first in its review list. The logs mark the first three "needs SAP".

- **Pooled treatment group.** KEYNOTE-189's control arm is placebo plus chemotherapy; KEYNOTE-564's is placebo alone. Both became "Control". That works for pooled safety and is wrong for efficacy.
- **Age groups.** The `<65` and `>=65` cut was picked without an SAP.
- **Pooled causality.** A new variable counts "possibly related" as related, the usual conservative rule for safety.
- **Severity.** KEYNOTE-189's "life-threatening" became "severe" to fit the CDISC codelist, with grade 4 kept in the toxicity grade.

**Facts only the data providers know.**

- **Lab units.** Neither ODM declares a single unit. The agent inferred them from the value ranges, which agree test by test between the studies, and found five confirmed in KEYNOTE-564's item descriptions. The rest are an inference.
- **KEYNOTE-189's screening dates.** Every subject's screening labs carry the same date as day 1, while their study day says −28. Every other visit is consistent. The 76 adverse events recorded at screening show the same pattern. Until someone resolves this, a lab baseline can't be derived.
- **Possible duplicate AEs.** 16 KEYNOTE-189 events repeat another event's subject, term and start date.

**Terminology to spot-check.** **The CDISC test codes it assigned** (CREATCLR, T3FR, OCCBLD and others), the AE action-taken mapping, and the hand-built country codes.

**Questions the spec will ask later.** No dictionary in these specs has an `unmapped` handler. When a later data cut brings a new race value, a new lab test or a new severity, the run stops and names the value. A person then decides what it means and adds one line to the dictionary. The spec keeps asking questions after the agent is gone.

Was batch review the right call? For pooling, I think so. The choices were cheap to change, and easier to judge side by side with their evidence than one interruption at a time. The units question is the exception. It affects every lab result, and I would rather the agent had raised it the moment it saw that no units were declared.

## How the agent checked its own work

No single check would have convinced me. What made me trust the output was the number of independent ways it was tested.

| Check | What it catches | Result |
|---|---|---|
| **Checks inside the spec**: unique keys, required values, allowed values, and `implies` rules such as "every non-urinalysis lab result converts to a number" | Bad values, duplicates, malformed numbers | All pass in all three specs |
| **No catch-all handlers** | Values nobody has reviewed | No unmapped or missing value in the current data |
| **Converter cross-check** against yamaa's own converter | A broken XML parser | 11 fields identical, row for row, in both studies |
| **A second implementation**: a Python simulation of each spec that builds the dataset another way, with pivots and joins instead of templates | Bugs in one implementation | 0 differing rows: DM 1,610, AE 9,137, LB 510,912 |
| **Known answers** | Wrong ordering or date logic | Derived AESEQ matches 6,869 collected values; KEYNOTE-564's study days match its dates for every AE, and for every lab form that records a study day |
| **Cross-domain** | Subjects in AE or LB but missing from DM | None |
| **Break-it tests**: six deliberately broken specs, such as a dictionary entry removed or a handler dropped | Checks that never fire | All six stopped with a clear message |
| **Recount** | Stale numbers in the decision logs | Every count re-derived from the output |

The consistency checks did more than confirm the output. Testing each study day against its date is how the agent found the screening-date problem in KEYNOTE-189.

There are also limits to what these checks prove:

- **The official yamaa engine has not run these specs.** It needs Linux, macOS or WSL, and that run is the one fully independent test left.
- The R runner and the Python simulations agree, but the same agent wrote both. A misreading of a rule could sit in both.
- The runner is the agent's reading of the rules. Where a rule was ambiguous, it took the stricter reading.

## What changes for the programmer

The work moved. I wrote no derivation code. My time went into setting the scope, reading decision logs and deciding the bolded items, which is the part of pooling that needs a person anyway. The agent did the data discovery that used to fill most of the loop.

If you try this, these are the things that made the difference for me:

- Ask for a decision log with a status on every entry. Without one, a spec is just output.
- Keep the spec strict. Leave out catch-all handlers and let unexpected values stop the run.
- Ask for a second implementation, and compare the two row for row.
- Ask the agent to break its own spec and show that every check fails loudly.
- Ask for a ranked review list at the end, and read it before anything else.

## By the numbers

| | |
|---|---:|
| ODM item records read | 1,795,111 |
| Subjects (DM rows) | 1,610 |
| Adverse events (AE rows) | 9,137 |
| Lab results (LB rows) | 510,912 |
| Row templates in DM, AE, LB | 2, 2, 13 |
| Decision-log entries: mechanical, choice, assumption | 28, 23, 6 |
| Broken specs that stopped | 6 of 6 |
| Rows that differ from the second implementation | 0 |

---

Data: simulated KEYNOTE-189 and KEYNOTE-564 datasets from the R Consortium Submissions Working Group, Pilot 7. No real patient data were used. Specification language: [yamaa](https://github.com/elong0527/yamaa). Agent: Claude Code.

The project folder holds the three specs (`dm_pooled.yaml`, `ae_pooled.yaml`, `lb_pooled.yaml`), their decision logs, the R runner `yamaa_mini.R`, the analysis code `example_questions.R`, and the reference simulations under `reference/`.
