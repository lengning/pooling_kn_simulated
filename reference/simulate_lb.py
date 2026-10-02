"""Independent simulation of lb_pooled.yaml, for checking an R or engine run.

Run from the pooling folder, after convert_odm.R or convert_odm.py:
    python reference/simulate_lb.py
Needs polars. Writes reference/lb_pooled_simulated.csv.

It is written from the data and decisions_lb.md, not from yamaa_mini.R:
results are separated from their date, study-day and grade items by name,
and joined back to them on the item group occurrence.
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
# Item name (without form) -> test code. FT3 is free T3, T3 is total T3.
TESTCD = {
    "ALB": "ALB", "ALT": "ALT", "AST": "AST", "CALC": "CA", "CRCL": "CREATCLR",
    "CREAT": "CREAT", "GLUC": "GLUC", "GLUCOSE": "GLUC", "POTAS": "K",
    "POTASSIUM": "K", "SODIUM": "SODIUM", "TBIL": "BILI", "APTT": "APTT",
    "INR": "INR", "PT_INR": "INR", "ANC": "NEUT", "HGB": "HGB",
    "LYMPH": "LYMPH", "PLT": "PLAT", "WBC": "WBC", "FT3": "T3FR",
    "FT4": "T4FR", "T3": "T3", "TSH": "TSH", "UABLOOD": "OCCBLD",
    "UBLOOD": "OCCBLD", "UAGLUC": "GLUC", "UGLU": "GLUC", "UAPROT": "PROT",
    "UPRO": "PROT",
}
TEST = {
    "ALB": "Albumin", "ALT": "Alanine Aminotransferase",
    "APTT": "Activated Partial Thromboplastin Time",
    "AST": "Aspartate Aminotransferase", "BILI": "Bilirubin", "CA": "Calcium",
    "CREAT": "Creatinine", "CREATCLR": "Creatinine Clearance",
    "GLUC": "Glucose", "HGB": "Hemoglobin",
    "INR": "Prothrombin Intl. Normalized Ratio", "K": "Potassium",
    "LYMPH": "Lymphocytes", "NEUT": "Neutrophils", "OCCBLD": "Occult Blood",
    "PLAT": "Platelets", "PROT": "Protein", "SODIUM": "Sodium",
    "T3": "Triiodothyronine", "T3FR": "Triiodothyronine, Free",
    "T4FR": "Thyroxine, Free", "TSH": "Thyrotropin", "WBC": "Leukocytes",
}
CAT = {"LB_CHEM": "CHEMISTRY", "LB_COAG": "COAGULATION",
       "LB_HEM": "HEMATOLOGY", "LB_THY": "THYROID", "LB_UA": "URINALYSIS"}
SPEC = {"LB_CHEM": "SERUM", "LB_COAG": "PLASMA", "LB_HEM": "BLOOD",
        "LB_THY": "SERUM", "LB_UA": "URINE"}
# Unit by test code for the numeric tests; INR and urinalysis have none.
UNIT = {
    "ALB": "g/dL", "ALT": "U/L", "AST": "U/L", "CA": "mg/dL",
    "CREATCLR": "mL/min", "CREAT": "mg/dL", "GLUC": "mg/dL", "K": "mmol/L",
    "SODIUM": "mmol/L", "BILI": "mg/dL", "APTT": "sec", "NEUT": "10^9/L",
    "HGB": "g/dL", "LYMPH": "10^9/L", "PLAT": "10^9/L", "WBC": "10^9/L",
    "T3FR": "pg/mL", "T4FR": "ng/dL", "T3": "ng/dL", "TSH": "mIU/L",
}
ORDINAL = ["NEGATIVE", "TRACE", "1+", "2+", "3+", "4+"]

frames = []
for study, (nct, studyid) in STUDIES.items():
    odm = (
        pl.read_parquet(HERE / "input" / f"{study}_odm.parquet")
        .with_row_index("ROW")
        .filter(pl.col("ItemGroupOID").str.starts_with(f"IG.{nct}.LB_"))
        .with_columns(
            pl.col("ItemGroupOID").str.strip_prefix(f"IG.{nct}.").alias("FORM"),
            pl.col("ItemOID").str.extract(r"\.([^.]+)$").alias("NAME"),
            pl.col("Value").replace("", None),
        )
    )
    side = odm.filter(
        pl.col("NAME").is_in(["LBDTC", "LBDY"]) | pl.col("NAME").str.ends_with("_GRADE")
    )
    results = odm.join(side.select("ROW"), on="ROW", how="anti")

    def sibling(name: str, alias: str) -> pl.DataFrame:
        s = side.filter(pl.col("NAME") == name).select(*OCCURRENCE, pl.col("Value").alias(alias))
        assert s.select(OCCURRENCE).is_unique().all(), f"{study}: {name} repeats"
        return s

    # Date and study day per occurrence; a form without LBDY gets none.
    out = results.join(sibling("LBDTC", "LBDTC"), on=OCCURRENCE, how="left", nulls_equal=True)
    out = out.join(sibling("LBDY", "LBDY"), on=OCCURRENCE, how="left", nulls_equal=True)
    # Grade: the item named <result>_GRADE in the same occurrence.
    grades = side.filter(pl.col("NAME").str.ends_with("_GRADE")).select(
        *OCCURRENCE, pl.col("NAME").str.strip_suffix("_GRADE"), pl.col("Value").alias("LBTOXGR")
    )
    out = out.join(grades, on=[*OCCURRENCE, "NAME"], how="left", nulls_equal=True)
    frames.append(out.with_columns(pl.lit(studyid).alias("STUDYID")))

lb = pl.concat(frames, how="diagonal_relaxed")
unknown = set(lb["NAME"].unique()) - set(TESTCD)
assert not unknown, f"unmapped items: {unknown}"

lb = lb.with_columns(
    pl.col("NAME").replace_strict(TESTCD).alias("LBTESTCD"),
    pl.col("FORM").replace_strict(CAT).alias("LBCAT"),
    pl.col("FORM").replace_strict(SPEC).alias("LBSPEC"),
).with_columns(
    pl.col("LBTESTCD").replace_strict(TEST).alias("LBTEST"),
    pl.when(pl.col("LBCAT") != "URINALYSIS")
    .then(pl.col("LBTESTCD").replace_strict(UNIT, default=None))
    .alias("LBORRESU"),
    pl.col("Value").cast(pl.Float64, strict=False).alias("LBSTRESN"),
)

# Checks the spec makes.
assert lb["Value"].null_count() == 0 and lb["LBDTC"].null_count() == 0
assert lb["LBDTC"].str.to_date("%Y-%m-%d", strict=True).null_count() == 0
assert lb.filter(pl.col("LBCAT") != "URINALYSIS")["LBSTRESN"].null_count() == 0
assert lb.filter(pl.col("LBCAT") == "URINALYSIS")["Value"].is_in(ORDINAL).all()
assert lb.select("STUDYID", "SubjectKey", "StudyEventOID", "LBCAT", "LBTESTCD").is_unique().all()
assert lb["LBTOXGR"].drop_nulls().is_in([str(g) for g in range(6)]).all()

# LBSEQ: by date, category and test within subject; a tie keeps document
# order, which here is the order of the visits.
lb = lb.sort("STUDYID", "SubjectKey", "LBDTC", "LBCAT", "LBTESTCD", "ROW").with_columns(
    pl.int_range(1, pl.len() + 1).over("STUDYID", "SubjectKey").alias("LBSEQ")
)
ties = lb.select("STUDYID", "SubjectKey", "LBDTC", "LBCAT", "LBTESTCD").is_duplicated().sum()
print(f"rows tied on date, category and test (ordered by visit): {ties}")

out = lb.select(
    "STUDYID",
    pl.lit("LB").alias("DOMAIN"),
    pl.col("SubjectKey").alias("USUBJID"),
    "LBSEQ", "LBTESTCD", "LBTEST", "LBCAT", "LBSPEC",
    pl.col("Value").alias("LBORRES"),
    "LBORRESU",
    pl.col("Value").alias("LBSTRESC"),
    "LBSTRESN",
    pl.col("LBORRESU").alias("LBSTRESU"),
    "LBTOXGR",
    pl.col("StudyEventOID").str.extract(r"([^.]+)$").alias("VISIT"),
    "LBDTC",
    pl.col("LBDY").cast(pl.Int64, strict=True),
).sort("STUDYID", "USUBJID", "LBSEQ")

target = HERE / "reference" / "lb_pooled_simulated.csv"
out.write_csv(target)
print(f"{out.height} rows -> {target.relative_to(HERE)}")
