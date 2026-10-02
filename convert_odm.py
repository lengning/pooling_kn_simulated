"""Write each study's ODM export as a yamaa ODM input (Parquet long table).

Run once from this folder:  python convert_odm.py
Needs the yamaa Python package (Python >= 3.12):
    pip install "../yamaa/python"
"""

from pathlib import Path

from yamaa.odm import write_odm_parquet

HERE = Path(__file__).resolve().parent
PILOT7 = HERE.parent / "submissions-pilot7-synthetic-data"
OUT = HERE / "input"
OUT.mkdir(exist_ok=True)

for study in ("kn189", "kn564"):
    archive = PILOT7 / study / "data" / "odm" / f"{study}_odm.tar.gz"
    target = OUT / f"{study}_odm.parquet"
    # The helper refuses to overwrite; replace any earlier output, as
    # convert_odm.R does.
    target.unlink(missing_ok=True)
    # The archive also holds index.html and macOS "._" files; the helper
    # skips "._" members, so the one odm.xml is selected automatically.
    result = write_odm_parquet(archive, target)
    print(study, result)
