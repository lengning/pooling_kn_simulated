"""Independent simulation of ae_pooled.yaml, for checking an R or engine run.

Run from the pooling folder, after convert_odm.R or convert_odm.py:
    python reference/simulate_ae.py
Needs polars. Writes reference/ae_pooled_simulated.csv.

It is written from the data and decisions_ae.md, not from yamaa_mini.R, so
the two implementations check each other. It also checks that the derived
AESEQ equals the AESEQ KN189 collected.
"""

from pathlib import Path

import polars as pl

HERE = Path(__file__).resolve().parent.parent
STUDIES = {
    "kn189": ("NCT02578680", "MK-3475-189"),
    "kn564": ("NCT03142334", "MK-3475-564"),
}
OCCURRENCE = [
    "SubjectKey", "StudyEventOID", "StudyEventRepeatKey", "FormOID",
    "FormRepeatKey", "ItemGroupOID", "ItemGroupRepeatKey",
]


def recode(col: str, dict_: dict[str, str]) -> pl.Expr:
    """Strict recode: an unseen or missing value is an error."""
    return pl.col(col).replace_strict(dict_, return_dtype=pl.String)


frames = []
for study, (nct, studyid) in STUDIES.items():
    odm = pl.read_parquet(HERE / "input" / f"{study}_odm.parquet")
    ae = (
        odm.with_row_index("ROW")
        .filter(pl.col("ItemGroupOID") == f"IG.{nct}.AE")
        .with_columns(
            pl.col("ItemOID").str.strip_prefix(f"IT.{nct}.AE."),
            pl.col("Value").replace("", None),
        )
    )
    # One record per occurrence, in document order of its first item.
    wide = (
        ae.group_by(OCCURRENCE, maintain_order=True)
        .agg(
            pl.col("ROW").min(),
            *[
                pl.col("Value").filter(pl.col("ItemOID") == item).first().alias(item)
                for item in ae["ItemOID"].unique().sort()
            ],
            pl.col("ItemOID").is_duplicated().any().alias("REPEATED_ITEM"),
        )
        .sort("ROW")
    )
    assert not wide["REPEATED_ITEM"].any(), f"{study}: an item repeats"
    wide = wide.with_columns(
        pl.lit(studyid).alias("STUDYID"),
        pl.int_range(1, pl.len() + 1).over("SubjectKey").alias("AESEQ"),
    )
    if "AESEQ" in ae["ItemOID"].unique().to_list():
        collected = ae.filter(pl.col("ItemOID") == "AESEQ")
        assert collected.height == wide.height
        # wide.AESEQ is the derived one; compare with the collected item.
        check = wide.join(
            collected.select(*OCCURRENCE, pl.col("Value").cast(pl.Int64).alias("C")),
            on=OCCURRENCE,
            nulls_equal=True,
        )
        assert (check["AESEQ"] == check["C"]).all(), "derived AESEQ != collected"
        print(f"{study}: derived AESEQ equals the collected AESEQ")
    frames.append(wide.select(
        "STUDYID", pl.col("SubjectKey").alias("USUBJID"), "AESEQ",
        "AETERM", "AEDECOD", "AEBODSYS", "AESEV", "AESER", "AEACN", "AEREL",
        "AEOUT", "AETOXGR", "AESTDTC", "AEDY",
    ))

ae = pl.concat(frames)
for col in ("AETERM", "AEBODSYS", "AESER", "AEREL", "AESTDTC"):
    assert ae[col].null_count() == 0, f"{col} is missing"
assert ae["AESTDTC"].str.to_date("%Y-%m-%d", strict=True).null_count() == 0

out = ae.select(
    "STUDYID",
    pl.lit("AE").alias("DOMAIN"),
    "USUBJID",
    "AESEQ",
    "AETERM",
    pl.col("AEDECOD").str.to_uppercase(),
    "AEBODSYS",
    recode("AESEV", {"MILD": "MILD", "MODERATE": "MODERATE",
                     "SEVERE": "SEVERE", "LIFE-THREATENING": "SEVERE"}),
    recode("AESER", {"Y": "Y", "N": "N"}),
    recode("AEACN", {"DOSE NOT CHANGED": "DOSE NOT CHANGED",
                     "DRUG WITHDRAWN": "DRUG WITHDRAWN",
                     "DOSE INTERRUPTED": "DRUG INTERRUPTED"}),
    "AEREL",
    "AEOUT",
    "AETOXGR",
    "AESTDTC",
    pl.col("AEDY").cast(pl.Int64, strict=True),
    recode("AEREL", {"RELATED": "RELATED", "POSSIBLY RELATED": "RELATED",
                     "NOT RELATED": "NOT RELATED"}).alias("AERELGR1"),
).sort("STUDYID", "USUBJID", "AESEQ")

assert out.select("STUDYID", "USUBJID", "AESEQ").is_unique().all()
assert out["AETOXGR"].is_in(["1", "2", "3", "4", "5"]).all()
target = HERE / "reference" / "ae_pooled_simulated.csv"
out.write_csv(target)
print(f"{out.height} rows -> {target.relative_to(HERE)}")
