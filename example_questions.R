# Two cross-study questions on the pooled data (simulated data).
# Run from this folder after dm_pooled.R, ae_pooled.R and lb_pooled.R:
#   Rscript example_questions.R
# Needs: dplyr, readr.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

dm <- read_csv("dm_pooled_r.csv", col_types = cols(.default = "c"))
ae <- read_csv("ae_pooled_r.csv", col_types = cols(.default = "c"))
lb <- read_csv("lb_pooled_r.csv",
  col_types = cols(.default = "c", LBSTRESN = "d")
)

# 1. Do immune-related AEs show up at similar rates in both indications?
#    Subjects with at least one event, by study and pooled arm. An arm with
#    no event gets no row.
n_arm <- count(dm, STUDYID, TRTPOOL, name = "N")

irae <- ae |>
  filter(AEDECOD %in% c(
    "HYPOTHYROIDISM", "HYPERTHYROIDISM", "PNEUMONITIS", "COLITIS", "HEPATITIS"
  )) |>
  inner_join(select(dm, STUDYID, USUBJID, TRTPOOL),
    by = c("STUDYID", "USUBJID")
  ) |>
  distinct(STUDYID, TRTPOOL, AEDECOD, USUBJID) |>
  count(STUDYID, TRTPOOL, AEDECOD, name = "n") |>
  left_join(n_arm, by = c("STUDYID", "TRTPOOL")) |>
  mutate(pct = round(100 * n / N, 1)) |>
  arrange(AEDECOD, STUDYID, TRTPOOL)
print(irae, n = Inf)

# 2. Do subjects with a hypothyroidism AE show it in their TSH?
#    Each subject's highest TSH, by study and hypothyroidism status.
hypo <- ae |>
  filter(AEDECOD == "HYPOTHYROIDISM") |>
  distinct(STUDYID, USUBJID) |>
  mutate(HYPO = "Y")

tsh <- lb |>
  filter(LBTESTCD == "TSH") |>
  group_by(STUDYID, USUBJID) |>
  summarise(max_tsh = max(LBSTRESN), .groups = "drop") |>
  left_join(hypo, by = c("STUDYID", "USUBJID")) |>
  mutate(HYPO = coalesce(HYPO, "N"))

tsh |>
  group_by(STUDYID, HYPO) |>
  summarise(
    subjects = n(),
    median_max_tsh = median(max_tsh),
    pct_over_10 = round(100 * mean(max_tsh > 10), 1),
    .groups = "drop"
  ) |>
  print()
