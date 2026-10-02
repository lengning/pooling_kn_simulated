# Run lb_pooled.yaml in R:  Rscript lb_pooled.R   (after convert_odm.R)
# Needs: yaml, arrow. Optional: reticulate + the Python yamaa package, for a
# cross-check against the real engine (Linux, macOS or WSL only).
#
# The runner itself is yamaa_mini.R, shared with dm_pooled.R and ae_pooled.R.
# It covers only the verbs the specs use and stops on anything else.

if (!file.exists("yamaa_mini.R")) {
  stop("run this script from the pooling-kn189-kn564 folder", call. = FALSE)
}
source("yamaa_mini.R")

out_path <- "lb_pooled_r.csv" # the yamaa engine writes lb_pooled.csv
lb <- run_spec("lb_pooled.yaml", out_path)

counts <- do.call(rbind, lapply(split(lb, lb$STUDYID), function(x) {
  data.frame(
    results = nrow(x), subjects = length(unique(x$USUBJID)),
    tests = length(unique(paste(x$LBCAT, x$LBTESTCD))),
    graded = sum(!is.na(x$LBTOXGR)), numeric = sum(!is.na(x$LBSTRESN))
  )
}))
print(counts)
print(table(lb$LBCAT, lb$STUDYID))

# Every LB subject must be a DM subject. This is a check of this script,
# not of the spec: the spec reads no DM data.
dm_path <- "dm_pooled_r.csv"
if (file.exists(dm_path)) {
  dm <- read.csv(dm_path, colClasses = "character")
  orphan <- setdiff(
    paste(lb$STUDYID, lb$USUBJID),
    paste(dm$STUDYID, dm$USUBJID)
  )
  if (length(orphan) > 0) {
    stop(length(orphan), " LB subject(s) are not in ", dm_path, ": ",
      paste(head(orphan, 3), collapse = ", "),
      call. = FALSE
    )
  }
  message("every LB subject is in ", dm_path)
}

compare_reference(out_path, file.path("reference", "lb_pooled_simulated.csv"),
  numeric = "LBSTRESN"
)
engine_cross_check("lb_pooled.yaml", out_path)
