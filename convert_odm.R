# Write each study's ODM export as a yamaa ODM input (Parquet long table).
#
# Run once from this folder:  Rscript convert_odm.R
# Needs: xml2, arrow.
#
# This is the R twin of convert_odm.py (yamaa.odm.write_odm_parquet). It
# writes the eleven fields of the fixed ODM input schema (REQ-1266), all as
# text, one row per ItemData in document order (REQ-0514):
#   StudyOID, MetaDataVersionOID, SubjectKey, StudyEventOID,
#   StudyEventRepeatKey, FormOID, FormRepeatKey, ItemGroupOID,
#   ItemGroupRepeatKey, ItemOID, Value
# Like the Python helper, an absent repeat key stays missing (it is not
# defaulted to "1"), and an empty <Value/> is kept as "".
#
# Supported layout: ODM 2.0 without FormData, where an outer ItemGroupData
# carries the form and an inner ItemGroupData carries the item group. That
# is how both KN189 and KN564 are exported. Anything else stops the script.

suppressPackageStartupMessages({
  library(xml2)
  library(arrow)
})

pilot7 <- file.path("..", "submissions-pilot7-synthetic-data")
if (!dir.exists(pilot7)) {
  stop("run this script from the pooling-kn189-kn564 folder, beside ",
    "submissions-pilot7-synthetic-data",
    call. = FALSE
  )
}
out_dir <- "input"
dir.create(out_dir, showWarnings = FALSE)

ns <- c(odm = "http://www.cdisc.org/ns/odm/v2.0")

# The archive also holds index.html and macOS "._" files; take the one
# real .xml member.
extract_odm_xml <- function(archive, exdir) {
  untar_any <- function(...) {
    tryCatch(
      utils::untar(archive, ..., tar = "internal"),
      error = function(e) utils::untar(archive, ..., tar = Sys.which("tar"))
    )
  }
  members <- untar_any(list = TRUE)
  xml <- members[grepl("\\.xml$", members, ignore.case = TRUE) &
    !startsWith(basename(members), "._")]
  if (length(xml) != 1) {
    stop("expected exactly one XML member in ", archive, call. = FALSE)
  }
  untar_any(files = xml, exdir = exdir)
  file.path(exdir, xml)
}

# Number of `child` elements under each node, in node order.
child_count <- function(nodes, child) {
  xpath <- sprintf("count(odm:%s)", child)
  vapply(seq_along(nodes), function(i) {
    xml_find_num(nodes[[i]], xpath, ns)
  }, numeric(1))
}

odm_long_table <- function(xml_path) {
  doc <- read_xml(xml_path, options = "HUGE")
  if (xml_find_num(doc, "count(/odm:ODM)", ns) != 1) {
    stop("root is not an ODM 2.0 <ODM> element", call. = FALSE)
  }
  if (xml_find_num(doc, "count(//odm:FormData)", ns) > 0) {
    stop("FormData layout is not handled here; use convert_odm.py",
      call. = FALSE
    )
  }

  cd <- xml_find_all(doc, "/odm:ODM/odm:ClinicalData", ns)
  if (length(cd) != 1) stop("expected one ClinicalData", call. = FALSE)

  p_subj <- "/odm:ODM/odm:ClinicalData/odm:SubjectData"
  p_event <- paste0(p_subj, "/odm:StudyEventData")
  p_form <- paste0(p_event, "/odm:ItemGroupData")
  p_group <- paste0(p_form, "/odm:ItemGroupData")
  p_item <- paste0(p_group, "/odm:ItemData")

  subj <- xml_find_all(doc, p_subj, ns)
  event <- xml_find_all(doc, p_event, ns)
  form <- xml_find_all(doc, p_form, ns)
  group <- xml_find_all(doc, p_group, ns)
  item <- xml_find_all(doc, p_item, ns)

  # Every ItemData must sit at exactly that depth.
  if (length(item) != xml_find_num(doc, "count(//odm:ItemData)", ns)) {
    stop("some ItemData sit outside SubjectData/StudyEventData/",
      "ItemGroupData/ItemGroupData",
      call. = FALSE
    )
  }

  # Nodes at one depth come back in document order, grouped by parent, so
  # repeating each parent's attribute by its child count lines it up with
  # the children.
  n_event <- child_count(subj, "StudyEventData")
  n_form <- child_count(event, "ItemGroupData")
  n_group <- child_count(form, "ItemGroupData")
  n_item <- child_count(group, "ItemData")
  stopifnot(
    sum(n_event) == length(event), sum(n_form) == length(form),
    sum(n_group) == length(group), sum(n_item) == length(item)
  )
  down <- function(x, ...) {
    for (n in list(...)) x <- rep(x, n)
    x
  }

  # Value: the attribute form or the single <Value> child (REQ-1265).
  if (xml_find_num(doc, "count(//odm:ItemData[@Value])", ns) == 0 &&
    xml_find_num(doc, "count(//odm:ItemData[count(odm:Value) != 1])", ns) ==
      0) {
    value <- xml_text(xml_find_all(doc, paste0(p_item, "/odm:Value"), ns))
  } else {
    value <- xml_attr(item, "Value")
    child <- xml_text(xml_find_first(item, "odm:Value", ns))
    value[is.na(value)] <- child[is.na(value)]
  }
  stopifnot(length(value) == length(item))

  out <- data.frame(
    StudyOID = rep(xml_attr(cd, "StudyOID"), length(item)),
    MetaDataVersionOID = rep(xml_attr(cd, "MetaDataVersionOID"), length(item)),
    SubjectKey = down(xml_attr(subj, "SubjectKey"),
      n_event, n_form, n_group, n_item),
    StudyEventOID = down(xml_attr(event, "StudyEventOID"),
      n_form, n_group, n_item),
    StudyEventRepeatKey = down(xml_attr(event, "StudyEventRepeatKey"),
      n_form, n_group, n_item),
    FormOID = down(xml_attr(form, "ItemGroupOID"), n_group, n_item),
    FormRepeatKey = down(xml_attr(form, "ItemGroupRepeatKey"),
      n_group, n_item),
    ItemGroupOID = down(xml_attr(group, "ItemGroupOID"), n_item),
    ItemGroupRepeatKey = down(xml_attr(group, "ItemGroupRepeatKey"), n_item),
    ItemOID = xml_attr(item, "ItemOID"),
    Value = value,
    stringsAsFactors = FALSE
  )

  # Identifiers an ODM input record must carry (REQ-1268).
  required <- c(
    "StudyOID", "MetaDataVersionOID", "SubjectKey", "StudyEventOID",
    "FormOID", "ItemGroupOID", "ItemOID"
  )
  for (field in required) {
    if (anyNA(out[[field]])) {
      stop(field, " is missing on some records", call. = FALSE)
    }
  }
  out
}

for (study in c("kn189", "kn564")) {
  archive <- file.path(pilot7, study, "data", "odm",
    paste0(study, "_odm.tar.gz"))
  tmp <- tempfile(study)
  xml_path <- extract_odm_xml(archive, tmp)
  long <- odm_long_table(xml_path)
  target <- file.path(out_dir, paste0(study, "_odm.parquet"))
  write_parquet(long, target)
  message(sprintf(
    "%s: %d records, %d subjects -> %s", study, nrow(long),
    length(unique(long$SubjectKey)), target
  ))
  unlink(tmp, recursive = TRUE)
  rm(long)
  invisible(gc())
}
