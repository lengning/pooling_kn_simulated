# Run ae_pooled.yaml in R:  Rscript ae_pooled.R   (after convert_odm.R)
# Needs: yaml, arrow. Optional: reticulate + the Python yamaa package, for a
# cross-check against the real engine (Linux, macOS or WSL only).
#
# The runner itself is yamaa_mini.R, shared with dm_pooled.R. It covers only
# the verbs the two specs use and stops on anything else.

if (!file.exists("yamaa_mini.R")) {
  stop("run this script from the pooling-kn189-kn564 folder", call. = FALSE)
}
source("yamaa_mini.R")

out_path <- "ae_pooled_r.csv" # the yamaa engine writes ae_pooled.csv
ae <- run_spec("ae_pooled.yaml", out_path)

counts <- do.call(rbind, lapply(split(ae, ae$STUDYID), function(x) {
  data.frame(
    events = nrow(x), subjects = length(unique(x$USUBJID)),
    serious = sum(x$AESER == "Y"), grade3plus = sum(as.integer(x$AETOXGR) >= 3),
    related = sum(x$AERELGR1 == "RELATED")
  )
}))
print(counts)

# Every AE subject must be a DM subject. This is a check of this script,
# not of the spec: the spec reads no DM data.
dm_path <- "dm_pooled_r.csv"
if (file.exists(dm_path)) {
  dm <- read.csv(dm_path, colClasses = "character")
  orphan <- setdiff(
    paste(ae$STUDYID, ae$USUBJID),
    paste(dm$STUDYID, dm$USUBJID)
  )
  if (length(orphan) > 0) {
    stop(length(orphan), " AE subject(s) are not in ", dm_path, ": ",
      paste(head(orphan, 3), collapse = ", "),
      call. = FALSE
    )
  }
  message("every AE subject is in ", dm_path)
}

compare_reference(out_path, file.path("reference", "ae_pooled_simulated.csv"))
engine_cross_check("ae_pooled.yaml", out_path)
