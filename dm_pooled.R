# Run dm_pooled.yaml in R:  Rscript dm_pooled.R   (after convert_odm.R)
# Needs: yaml, arrow. Optional: reticulate + the Python yamaa package, for a
# cross-check against the real engine (Linux, macOS or WSL only).
#
# The runner itself is yamaa_mini.R, shared with ae_pooled.R. It covers only
# the verbs the two specs use and stops on anything else.

if (!file.exists("yamaa_mini.R")) {
  stop("run this script from the pooling-kn189-kn564 folder", call. = FALSE)
}
source("yamaa_mini.R")

out_path <- "dm_pooled_r.csv" # the yamaa engine writes dm_pooled.csv
dm <- run_spec("dm_pooled.yaml", out_path)
print(table(dm$STUDYID, dm$TRTPOOL))

compare_reference(out_path, file.path("reference", "dm_pooled_simulated.csv"))
engine_cross_check("dm_pooled.yaml", out_path)
