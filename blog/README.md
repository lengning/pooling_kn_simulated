# Two Trials, One Spec

*Field notes on agents and clinical data | October 2026 | KEYNOTE-189 + KEYNOTE-564, simulated data*

I asked Claude Code to pool demographics (DM), adverse events (AE) and lab results (LB) from two simulated oncology trials. It read the raw exports, wrote specifications using the [yamaa framework](https://github.com/elong0527/yamaa), ran them, checked the output and returned a list of decisions that needed a person. The result was three draft datasets: 1,610 subjects, 9,137 adverse events and 510,912 lab results.

Pooling starts with a question that crosses study boundaries. Do subjects who report hypothyroidism also show a change in their thyroid-stimulating hormone (TSH)? Answering that means joining demographics, events and labs across studies whose forms, item names and codes differ.

The two studies made a useful test. KEYNOTE-189 has 616 simulated subjects with metastatic lung cancer; KEYNOTE-564 has 994 with kidney cancer after surgery. Their control arms differ, their lab tests use different names, and one study collects items the other does not. Even a familiar variable such as race needs a harmonization rule.

Usually, these differences emerge while someone programs the datasets, sending the work back to the specification. I wanted to see what happened when an agent ran that discovery loop. I set the scope and the order (DM, then AE, then LB) and reviewed the decisions it returned.

> **Simulated data.** The [synthetic datasets](https://github.com/RConsortium/submissions-pilot7-synthetic-data) follow the KEYNOTE-189 and KEYNOTE-564 protocols and were provided by the R Consortium Submissions Working Group (Pilot 7) in collaboration with BBSW. They contain no real patient data. The results below illustrate the workflow and say nothing about pembrolizumab.

The [technical appendix](technical-appendix.md) contains the execution commands, longer YAML examples and detailed output tables.

## How the pooling works

yamaa expresses a clinical-data specification in YAML: what rows a dataset contains, what its columns mean and how their values are derived. These specs start from the Operational Data Model (ODM) XML exported by an electronic data capture (EDC) system. A converter makes a long table with one record per collected item, carrying its study, subject, visit and form identifiers.

The pooling design has three parts:

- **Study-specific templates** read each study's items into common columns. Where values need recoding, they first go into neutral columns such as `RACE_RAW`.
- **Shared derivations** apply the pooling rules once, across both studies. A dictionary can turn two collected terms into one output term.
- **Strict checks** stop the run when a value or structure falls outside the specification. The agent has to resolve a surprise explicitly before the run can continue.

The distinction between templates and shared derivations matters because the studies cannot share one item binding. KEYNOTE-189's race item is `IT.NCT02578680.DM.RACE`; KEYNOTE-564's is `IT.NCT03142334.DM.RACE`. Each template reads its own item into the same intermediate column:

```yaml
rows:
  - id: kn189
    dataset: ODM189
    group_by: [ODM189.StudyOID, ODM189.SubjectKey]
    derivations:
      RACE_RAW: {odm: ODM189.IT.NCT02578680.DM.RACE}

  - id: kn564
    dataset: ODM564
    group_by: [ODM564.StudyOID, ODM564.SubjectKey]
    derivations:
      RACE_RAW: {odm: ODM564.IT.NCT03142334.DM.RACE}
```

*Excerpt from [dm_pooled.yaml](../dm_pooled.yaml), showing only the race bindings.*

The templates' rows are stacked, then the shared race mapping runs over all of them. A reviewer can inspect the study bindings separately from the pooling rule. Adding another study would mean adding its bindings and reviewing any new values against the shared dictionaries.

The agent followed a simple cycle: **profile -> specify -> run -> check**. Before writing YAML, it read the relevant yamaa rules and worked examples, then queried both studies. Which forms existed? Which items repeated? What values were actually stored? The last question mattered: the declared race codelists did not match the collected values, so the mapping had to follow the data.

The three domains used the same design, with different rules for building rows:

**DM: one row per subject.** Each study's template groups records by subject and reads its demographic items. Shared mappings harmonize race, sex and country. Every template must supply the same columns; KEYNOTE-564 has no age-unit item, so its template supplies the provisional literal `YEARS`.

**AE: one row per event.** Each occurrence of the repeating adverse-event form becomes a row. Shared rules harmonize preferred-term case, severity and action taken. A sequence number follows collection order within each subject. That choice had a useful check: it reproduced all 6,869 sequence numbers collected in KEYNOTE-189, while also supplying numbers for KEYNOTE-564, which collected none.

**LB: one row per result.** Each lab-test item becomes a row and reads its date and, where present, its grade from its own form occurrence. This avoided a subtle error: KEYNOTE-189's screening coagulation samples were dated three days before the other screening labs. Taking one date per visit would have misdated those 616 results. Shared mappings harmonize test names while preserving distinctions such as free T3 versus total T3.

Once the three datasets were built, the agent joined AE and LB by study and subject to compare TSH results for subjects with and without a hypothyroidism event. The [analysis example](technical-appendix.md#cross-domain-analysis-examples) demonstrates that the datasets connect and support a cross-domain question. Its numbers come from simulated data, and the TSH unit was inferred.

## Two decisions, up close

The useful output was more than the datasets. Each domain had a decision log recording the rule, the evidence and a status:

- **Mechanical:** follows from the data or a convention.
- **Choice:** one reasonable option among several.
- **Assumption:** something the available data cannot confirm.

The three logs contain 57 entries: 28 mechanical, 23 choices and 6 assumptions. These labels make the review queue easier to read, but they do not settle whether a decision is acceptable. Two examples show the difference between a straightforward recode and an analysis choice.

### Race: a term that can be harmonized

KEYNOTE-189 records `BLACK`; KEYNOTE-564 records `BLACK OR AFRICAN AMERICAN`. The agent mapped both to the CDISC term. KEYNOTE-189 also has `OTHER`, and KEYNOTE-564 has `MULTIPLE`, with no detail collected to resolve either. It kept those values as collected.

The study templates above supply `RACE_RAW`. The shared derivation contains the decision:

```yaml
- name: RACE
  derivation:
    mapping:
      source: RACE_RAW
      dict:
        BLACK: BLACK OR AFRICAN AMERICAN
        BLACK OR AFRICAN AMERICAN: BLACK OR AFRICAN AMERICAN
        OTHER: OTHER
        MULTIPLE: MULTIPLE
        # Other observed values are listed in the full spec.
```

The log calls the `BLACK` recode Mechanical and the handling of `OTHER` and `MULTIPLE` a Choice. A reviewer can see both the evidence and the boundary of what the agent resolved: it standardized a term, while keeping categories for which the source offered no further detail.

There is no catch-all mapping. A new race value in a later data cut will stop the run and name the value. A missing race also stops it. This makes the dictionary a continuing point of review, rather than a rule that quietly absorbs whatever arrives.

### Treatment: a grouping that needs an analysis plan

Both studies have a pembrolizumab arm, but their controls are different. KEYNOTE-189's control is placebo plus pemetrexed and platinum; KEYNOTE-564's is placebo alone. The agent provisionally put both under one label so the pipeline could run:

```yaml
- name: TRTPOOL
  derivation:
    mapping:
      source: ARMCD
      dict:
        PEMBRO: Pembrolizumab
        CONTROL: Control   # KEYNOTE-189: placebo + chemotherapy
        PBO: Control       # KEYNOTE-564: placebo alone
```

The log marks this **Choice, needs SAP** (statistical analysis plan). The agent put it first in its ranked review list. A statistician still needs to decide whether that grouping suits the intended analysis or whether the controls should remain separate. The shared word "Control" does not establish that the comparators are interchangeable.

The original study and arm columns are retained, so a reviewer can trace the grouping back to its sources. Changing the pooled labels means editing the mapping and rerunning the spec. The agent did not need to rewrite the source data to make its provisional choice executable.

Smaller decisions followed the same pattern. `GLUCOSE` and `GLUC` became one serum glucose test code, while urine glucose remained distinguishable by category and specimen. The agent inferred mg/dL for serum glucose from the values because neither export declared a unit. It also supplied `YEARS` for KEYNOTE-564's missing age-unit item. Those are logged assumptions, with [the detailed examples in the appendix](technical-appendix.md#additional-mapping-examples).

The logs are what make these choices reviewable. A finished dataset does not reveal why two values were combined or why a missing item was filled. A log ties the output rule to evidence and tells the reviewer where the agent had to go beyond it.

## How the output was checked

The agent tested several different parts of the workflow. Some checks tested the specification's constraints; others compared implementations or used collected values as known answers.

| Check | Result in this run |
|---|---|
| Specification checks: keys, required values, allowed values and numeric conversion | All passed for DM, AE and LB. |
| R converter compared with yamaa's own converter | The 11 schema fields matched row for row in both studies. |
| R output compared with separate Python simulations using pivots and joins | Zero differing rows across all three datasets. |
| Known answers and cross-domain links | All 6,869 collected KEYNOTE-189 AE sequence numbers matched; every AE and LB subject was present in DM. |
| Six deliberately broken specs | All six stopped with a clear message. |

The break-it tests mattered because a passing run alone cannot show that a check will catch an error. The agent removed dictionary entries, introduced a value outside an allowed list and removed a numeric-conversion handler. The runs stopped, demonstrating that those constraints were active.

Date checks also found a source-data problem. KEYNOTE-564's study days agreed with its dates. In KEYNOTE-189, screening dates and study days disagreed for several lab forms and 76 adverse events. The agent preserved the collected values and put the discrepancy on the review list.

**Agreement between the implementations is useful evidence, with limits.** The same agent wrote the R runner and Python simulations. They build the outputs differently, but a shared misunderstanding of a yamaa rule could survive both. The R runner implements a subset of the framework and reflects the agent's reading of those rules.

The remaining execution check is to run the specs through the official engine on Linux, macOS or WSL and compare the outputs. Even that would test execution rather than resolve the provisional treatment grouping or confirm inferred lab units. Those questions need review of the evidence and the intended analysis.

The [full validation table](technical-appendix.md#detailed-validation) records the additional checks and their limits. The datasets remain drafts while these execution and review questions are open.

## What still needs a person

I set the scope and asked for a ranked review list at the end. In between, the agent made provisional decisions and logged them without stopping to ask questions. The final handback concentrated attention on the items below.

| Review item | What needs to be decided or confirmed |
|---|---|
| Treatment grouping | Whether combining the two control arms fits the planned analysis. |
| Other analysis choices | The age cut at 65, counting "possibly related" as related, and the severity mapping. |
| Lab units and specimens | Confirm the inferred units and specimen assignments with the data providers. |
| Screening dates and possible duplicate AEs | Resolve the date discrepancy and review 16 events sharing another event's subject, term and start date. |
| Terminology | Spot-check the lab test codes, AE action-taken mapping and country codes. |

Two items deserve more than a table row.

**Lab units affect the interpretation of every result.** Neither ODM export declares units. The agent inferred them from value ranges that agreed between studies and found five supported by KEYNOTE-564's item descriptions. The remaining assignments still need confirmation. Similar scales are evidence for an assumption; they do not make the unit a collected fact. The specimen assignments also come from the forms rather than collected specimen values.

**The screening-date discrepancy blocks the planned lab baseline derivation.** KEYNOTE-189's screening chemistry, hematology, thyroid and urinalysis forms carry the same dates as day 1. Where a study day is collected, it says -28. The screening coagulation dates are a separate finding, three days earlier. Until the providers resolve the conflict, a date-based rule cannot reliably distinguish screening from day 1 for the affected results.

The review list also separates an analysis choice from the source value. KEYNOTE-189's `LIFE-THREATENING` severity became `SEVERE`, with the collected grade 4 retained in the toxicity-grade column. "Possibly related" remains in the collected causality column while a new grouping variable counts it as related. A reviewer can inspect the proposed grouping alongside the information it summarizes.

Batch review worked well for choices that were easy to change and easier to judge together. The units question is the exception: I would rather the agent had raised it as soon as it discovered the missing metadata. Finishing the pipeline did not make that assumption less important.

The full evidence remains in the [DM](../decisions.md), [AE](../decisions_ae.md) and [LB](../decisions_lb.md) decision logs. Each entry gives a reviewer something to check (a count, a collected value or a rule) and a place to change the specification. The source exports remain intact.

## What changes for the programmer

The work moved. I wrote no derivation code. My time went into setting the scope, reading the evidence and deciding which provisional rules were suitable for the intended analysis. The agent did the data discovery and repeated runs that usually consume much of the pooling loop.

Three practices made that useful:

1. **Require a decision log with evidence and status.** It turns a completed spec into a set of decisions someone can review.
2. **Keep the spec strict and test its failures.** Unexpected values should stop the run; deliberately broken inputs show whether the checks work.
3. **Ask for a ranked handback and name the remaining checks.** Review the assumptions and analysis choices, compare implementations, and keep any unperformed engine check visible.

The next data cut will bring its own surprises. A strict spec will stop at an unfamiliar value, and its decision log will give the reviewer the context for adding the next rule. The discovery loop continues, with more of its work captured in artifacts a person can inspect and revise.
