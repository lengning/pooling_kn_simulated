"""Run the pooled specs:  python run.py [dm|ae|lb]  (after convert_odm.py).

With no argument, runs all three: dm_pooled.yaml, ae_pooled.yaml, then
lb_pooled.yaml.
"""

import os
import sys
from pathlib import Path

import yamaa

HERE = Path(__file__).resolve().parent
SPECS = {"dm": "dm_pooled.yaml", "ae": "ae_pooled.yaml", "lb": "lb_pooled.yaml"}
SUMMARY = {
    "dm": ["STUDYID", "TRTPOOL"],
    "ae": ["STUDYID", "AESEV"],
    "lb": ["STUDYID", "LBCAT"],
}

if os.name == "nt":
    # The engine resolves files with os.open(dir_fd=...) and O_NOFOLLOW,
    # which native Windows lacks; it would stop with "component-safe
    # project resource resolution is unavailable".
    raise SystemExit(
        "The yamaa engine needs Linux, macOS or WSL. On Windows, use the R route."
    )

for name in sys.argv[1:] or list(SPECS):
    run = yamaa.yamaa_domain(
        HERE / SPECS[name],
        # The spec sits outside the yamaa repo, so name its schema bundle.
        schema_root=HERE.parent / "yamaa" / "yaml",
    )
    out = run.output
    if out is None:
        # Validation or execution stopped; each issue names the rule (REQ-NNNN).
        print(run.issues)
        raise SystemExit(1)

    print(run.save())  # writes the spec's output path beside the spec
    print(out.group_by(SUMMARY[name]).len().sort(SUMMARY[name]))
