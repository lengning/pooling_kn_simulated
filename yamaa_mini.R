# A minimal R runner for the yamaa verbs that dm_pooled.yaml,
# ae_pooled.yaml and lb_pooled.yaml use, and nothing more. Needs: yaml,
# arrow.
#
#   source("yamaa_mini.R")
#   out <- run_spec("ae_pooled.yaml", "ae_pooled_r.csv")
#
# yamaa has no R engine yet: the benchmarks' run.R files target a planned
# `yamaa` R package (issue #200), and R/cdiscbuilder does not read yamaa
# specifications. This runner covers:
#
#   rows:     grouped or record-driven over an ODM input, with an optional
#             filter; literal, source, odm, str_extract
#   columns:  literal, source, mapping, cut, str_case, row_number; the
#             `value` wrapper with `unconvertible`
#   types:    str, int, float, date
#   filters:  =, <>, [NOT] IN, IS [NOT] NULL, joined by AND
#   checks:   keys present and unique; column not_missing and
#             allowed_values; dataset unique and implies
#
# Every item binding and every recoding table is read from the YAML, so the
# YAML stays the single place to edit. Anything else in a spec stops with
# "not supported by this runner" rather than being guessed at.

suppressPackageStartupMessages({
  library(yaml)
  library(arrow)
})

fail <- function(...) stop(paste0(...), call. = FALSE)
`%||%` <- function(x, y) if (is.null(x)) y else x

# yamaa reads YAML 1.2, where only true/false are booleans. The yaml package
# reads YAML 1.1, where Y, N, yes, no, on and off are booleans too; keep
# those as the strings they were written as.
yaml12_bool <- function(x) {
  low <- tolower(x)
  if (low %in% c("true", "false")) low == "true" else x
}
read_spec <- function(path) {
  read_yaml(path, handlers = list(
    "bool#yes" = yaml12_bool, "bool#no" = yaml12_bool
  ))
}

split_qualified <- function(x) {
  dot <- regexpr(".", x, fixed = TRUE)
  if (dot < 1) fail("expected DATASET.VARIABLE, got ", x)
  c(dataset = substr(x, 1, dot - 1), variable = substr(x, dot + 1, nchar(x)))
}

# One string per row; missing equals missing (REQ-0037, REQ-0293).
row_key <- function(df, vars) {
  parts <- lapply(unname(as.list(df[vars])), function(x) {
    x <- as.character(x)
    x[is.na(x)] <- "\001"
    x
  })
  do.call(paste, c(parts, sep = "\r"))
}

ascii_upper <- function(x) chartr(paste(letters, collapse = ""),
  paste(LETTERS, collapse = ""), x)
ascii_lower <- function(x) chartr(paste(LETTERS, collapse = ""),
  paste(letters, collapse = ""), x)

# A missing source with no `missing` handler stops the run (REQ-0344).
handle_missing <- function(out, x, arg, where) {
  if (anyNA(x)) {
    if (!("missing" %in% names(arg))) {
      fail(where, ": missing source with no `missing` handler")
    }
    out[is.na(x)] <- arg$missing %||% NA
  }
  out
}

# ---- Inputs -----------------------------------------------------------------

read_input <- function(decl, spec_dir) {
  if (is.character(decl)) decl <- list(path = decl)
  if (!grepl("\\.parquet$", decl$path, ignore.case = TRUE)) {
    fail(decl$path, ": only Parquet inputs are supported by this runner")
  }
  path <- file.path(spec_dir, decl$path)
  if (!file.exists(path)) fail(path, " does not exist; run convert_odm.R")
  df <- as.data.frame(read_parquet(path))
  # Empty-string convention, `missing` by default (REQ-1158, REQ-1159).
  if ((decl$empty_string %||% "missing") == "missing") {
    for (v in names(df)) {
      if (is.character(df[[v]])) df[[v]][!is.na(df[[v]]) & df[[v]] == ""] <- NA
    }
  }
  df
}

# ---- Types ------------------------------------------------------------------

# Conversion to the declared type when a column completes. A value that
# does not convert stops the run, unless the derivation's `value` wrapper
# declares `unconvertible`, whose literal replaces it (REQ-0359, REQ-0363).
# A missing value is not converted, so `unconvertible` never fires for it.
as_declared <- function(x, col, where, columns, handler = NULL) {
  type <- columns[[col]]$type
  if (is.null(type)) fail(where, ": column ", col, " is not declared")
  replace_bad <- function(x, bad, what) {
    if (!any(bad)) {
      return(x)
    }
    if (is.null(handler)) {
      fail(where, ": cannot convert to ", what, ": ",
        paste(head(unique(x[bad]), 5), collapse = ", "))
    }
    x[bad] <- handler$replacement %||% NA
    x
  }
  if (type == "str") {
    return(as.character(x))
  }
  if (type == "int") {
    if (is.numeric(x)) {
      if (any(!is.na(x) & x != round(x))) fail(where, ": not an integer")
      return(as.integer(x))
    }
    x <- as.character(x)
    x <- replace_bad(x, !is.na(x) & !grepl("^[+-]?[0-9]+$", x), "int")
    return(as.integer(x))
  }
  if (type == "float") {
    if (is.numeric(x)) {
      return(as.numeric(x))
    }
    x <- as.character(x)
    number <- "^[+-]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?$"
    x <- replace_bad(x, !is.na(x) & !grepl(number, x), "float")
    return(as.numeric(x))
  }
  if (type == "date") {
    # A date is a complete calendar date (REQ-0539); a partial date is not
    # a value of the type (REQ-0544). It is kept as its ISO 8601 text.
    x <- as.character(x)
    ok <- is.na(x) | (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x) &
      !is.na(as.Date(x, format = "%Y-%m-%d")))
    return(replace_bad(x, !ok, "a complete date"))
  }
  fail(where, ": type ", type, " is not supported by this runner")
}

# ---- Row filter -------------------------------------------------------------

# A conjunction (AND) of `NAME = 'text'`, `NAME <> 'text'`,
# `NAME [NOT] IN ('a', 'b', ...)`, `NAME IS NULL` and `NAME IS NOT NULL`,
# where NAME may be qualified (DATASET.FIELD). A comparison with a missing
# value is UNKNOWN (REQ-0173, REQ-0175); R's `&` and `!` are three-valued the
# same way. Returns TRUE, FALSE or NA for each row.
eval_predicate <- function(expr, read_column, n, where) {
  name <- "([A-Za-z_][A-Za-z0-9_]*(?:[.][A-Za-z_][A-Za-z0-9_]*)?)"
  text <- "'((?:[^']|'')*)'"
  is_null <- paste0("^", name, "\\s+IS\\s+(NOT\\s+)?NULL$")
  compare <- paste0("^", name, "\\s*(=|<>)\\s*", text, "$")
  in_list <- paste0("^", name, "\\s+(NOT\\s+)?IN\\s*\\((.*)\\)$")
  unquote <- function(x) gsub("''", "'", x, fixed = TRUE)
  result <- rep(TRUE, n)
  for (term in trimws(strsplit(expr, "\\s+AND\\s+", perl = TRUE)[[1]])) {
    if (grepl(is_null, term, perl = TRUE)) {
      m <- regmatches(term, regexec(is_null, term, perl = TRUE))[[1]]
      x <- read_column(m[2])
      value <- if (nzchar(m[3])) !is.na(x) else is.na(x)
    } else if (grepl(compare, term, perl = TRUE)) {
      m <- regmatches(term, regexec(compare, term, perl = TRUE))[[1]]
      x <- as.character(read_column(m[2]))
      value <- if (m[3] == "=") x == unquote(m[4]) else x != unquote(m[4])
    } else if (grepl(in_list, term, perl = TRUE)) {
      m <- regmatches(term, regexec(in_list, term, perl = TRUE))[[1]]
      # Only quoted text literals, separated by commas.
      if (!grepl(paste0("^\\s*", text, "(\\s*,\\s*", text, ")*\\s*$"), m[4],
        perl = TRUE
      )) {
        fail(where, ": IN list `", m[4], "` is not supported by this runner")
      }
      items <- regmatches(m[4], gregexpr(text, m[4], perl = TRUE))[[1]]
      items <- unquote(substr(items, 2, nchar(items) - 1))
      x <- as.character(read_column(m[2]))
      value <- ifelse(is.na(x), NA, x %in% items)
      if (nzchar(m[3])) value <- !value
    } else {
      fail(where, ": filter term `", term, "` is not supported by this runner")
    }
    result <- result & value
  }
  result
}

# A row filter keeps only TRUE (REQ-0036, REQ-0038).
eval_filter <- function(expr, read_column, n, where) {
  keep <- eval_predicate(expr, read_column, n, where)
  !is.na(keep) & keep
}

# ---- Row templates ----------------------------------------------------------

odm_hierarchy <- c(
  "StudyOID", "SubjectKey", "StudyEventOID", "StudyEventRepeatKey",
  "FormOID", "FormRepeatKey", "ItemGroupOID", "ItemGroupRepeatKey"
)

# The fields an ODM input exposes (REQ-1266); any other stored field is a
# vendor field that no expression reads (REQ-1267).
odm_fields <- c(odm_hierarchy, "MetaDataVersionOID", "ItemOID", "Value")

# Row keys over one input's fields, computed once per input and field set:
# the ODM inputs hold close to a million records, and every template over
# the same input needs the same occurrence keys.
cached_key <- function(cache, dataset, df, vars) {
  id <- paste(c(dataset, vars), collapse = "|")
  if (is.null(cache[[id]])) cache[[id]] <- row_key(df, vars)
  cache[[id]]
}

build_template <- function(tpl, inputs, columns, cache) {
  where0 <- paste0("row ", tpl$id)
  driver <- inputs[[tpl$dataset %||% ""]]
  if (is.null(driver)) fail(where0, ": unknown dataset ", tpl$dataset)
  grouped <- !is.null(tpl$group_by)

  if (grouped) {
    gvars <- vapply(unlist(tpl$group_by), function(v) {
      q <- split_qualified(v)
      if (q[["dataset"]] != tpl$dataset) {
        fail(where0, ": group_by ", v, " is not qualified to ", tpl$dataset)
      }
      q[["variable"]]
    }, character(1), USE.NAMES = FALSE)
    if (!all(gvars %in% odm_hierarchy)) {
      fail(where0, ": this runner groups only on ODM hierarchy fields")
    }
    # One row per group, in first-appearance order (REQ-0038).
    dkey <- cached_key(cache, tpl$dataset, driver, gvars)
    rows <- driver[!duplicated(dkey), gvars, drop = FALSE]
    rownames(rows) <- NULL
    rkey <- row_key(rows, gvars)
  } else {
    # Record-driven: one candidate row per driver record, in driver order
    # (REQ-0036, REQ-0039). Its ODM scope is the records equal to it on all
    # eight hierarchy fields, i.e. its own item group occurrence (REQ-1269).
    gvars <- odm_hierarchy
    rows <- driver
    rkey <- cached_key(cache, tpl$dataset, driver, gvars)
  }
  readable <- if (grouped) gvars else intersect(names(driver), odm_fields)

  # A variable read in row context: a readable field of the driver (a
  # group_by variable when grouped, any ODM field when record-driven), or a
  # column this template has already derived.
  row_variable <- function(name, where) {
    if (grepl(".", name, fixed = TRUE)) {
      q <- split_qualified(name)
      if (q[["dataset"]] != tpl$dataset || !(q[["variable"]] %in% readable)) {
        fail(where, ": ", name, if (grouped) " is not in group_by (REQ-0107)"
        else " is not a field of the driver")
      }
      return(rows[[q[["variable"]]]])
    }
    if (is.null(derived[[name]])) fail(where, ": ", name, " is not derived yet")
    derived[[name]]
  }

  # odm read (REQ-1269 to REQ-1272): the row's scope is its group, or its
  # own occurrence; no record gives missing, one gives its Value, two or
  # more fail.
  odm_read <- function(arg, where) {
    if (is.list(arg)) {
      if (length(setdiff(names(arg), "item")) > 0) {
        fail(where, ": odm event/form/item_group/filter are not supported ",
          "by this runner")
      }
      arg <- arg$item
    }
    q <- split_qualified(arg)
    if (q[["dataset"]] != tpl$dataset) {
      fail(where, ": odm reads another dataset than the template's driver")
    }
    hits <- driver[driver$ItemOID == q[["variable"]], c(gvars, "Value"),
      drop = FALSE]
    hkey <- row_key(hits, gvars)
    if (anyDuplicated(hkey) > 0) {
      fail(where, ": odm_not_unique for ", q[["variable"]], " at ",
        gsub("\r", " / ", hkey[duplicated(hkey)][1], fixed = TRUE))
    }
    hits$Value[match(rkey, hkey)]
  }

  derived <- list()
  for (col in names(tpl$derivations)) {
    where <- paste0(where0, ", column ", col)
    d <- tpl$derivations[[col]]
    if (is.character(d)) d <- list(source = d) # source shorthand (REQ-0319)
    if (!is.list(d) || length(d) != 1) {
      fail(where, ": a derivation holds exactly one keyword")
    }
    arg <- d[[1]]
    value <- switch(names(d),
      literal = rep(if (is.null(arg)) NA else arg, nrow(rows)),
      source = row_variable(arg, where),
      odm = odm_read(arg, where),
      str_extract = {
        x <- as.character(row_variable(arg$source, where))
        if (!is.null(arg$group) && arg$group != 0) {
          fail(where, ": str_extract.group is not supported by this runner")
        }
        # yamaa regexes are ECMA-262; PCRE agrees for simple patterns.
        m <- regexpr(arg$pattern, x, perl = TRUE)
        out <- ifelse(m > 0, substr(x, m, m + attr(m, "match.length") - 1),
          NA_character_)
        out <- handle_missing(out, x, arg, where)
        no_match <- !is.na(x) & m < 1
        if (any(no_match)) {
          if (!("no_match" %in% names(arg))) {
            fail(where, ": pattern does not match ", x[no_match][1])
          }
          out[no_match] <- arg$no_match %||% NA
        }
        out
      },
      fail(where, ": `", names(d), "` is not supported by this runner")
    )
    derived[[col]] <- as_declared(value, col, where, columns)
  }
  out <- data.frame(derived, check.names = FALSE, stringsAsFactors = FALSE)

  # The filter runs after the template's derivations. It reads the columns
  # this template derives; a record-driven filter may also read the driver
  # record's own fields, a grouped one may not (REQ-0036, REQ-0038,
  # REQ-0068).
  if (!is.null(tpl$filter)) {
    read_column <- function(name) {
      if (grepl(".", name, fixed = TRUE)) {
        if (grouped) {
          fail(where0, ": a grouped filter names the qualified ", name,
            " (REQ-0068)")
        }
        return(row_variable(name, where0))
      }
      if (!(name %in% names(derived))) {
        fail(where0, ": filter names ", name, ", which this template does ",
          "not derive (REQ-0068)")
      }
      derived[[name]]
    }
    keep <- eval_filter(tpl$filter, read_column, nrow(out), where0)
    out <- out[keep, , drop = FALSE]
    rownames(out) <- NULL
  }
  out
}

# ---- The run ----------------------------------------------------------------

run_spec <- function(spec_path, out_path) {
  spec <- read_spec(spec_path)
  spec_dir <- dirname(spec_path)
  inputs <- lapply(spec$input, read_input, spec_dir = spec_dir)
  columns <- spec$columns
  names(columns) <- vapply(columns, function(c) c$name, character(1))

  templates <- spec$rows
  if (length(templates) == 0) fail("this runner needs `rows`")
  row_cols <- names(templates[[1]]$derivations)
  for (tpl in templates) {
    if (!setequal(names(tpl$derivations), row_cols)) {
      fail("row ", tpl$id, ": every template must derive the same columns ",
        "(REQ-0200)")
    }
  }
  # Sections concatenate in specification order (REQ-0043).
  cache <- new.env()
  data <- do.call(rbind, lapply(templates, function(tpl) {
    build_template(tpl, inputs, columns, cache)[row_cols]
  }))
  rownames(data) <- NULL
  rm(cache, inputs)
  invisible(gc())

  # ---- Column-level derivations, in declaration order ----

  column_variable <- function(name, where) {
    if (grepl(".", name, fixed = TRUE)) {
      fail(where, ": qualified reads at column level are not supported ",
        "by this runner")
    }
    if (is.null(data[[name]])) {
      fail(where, ": ", name, " is not derived yet; declare it earlier")
    }
    data[[name]]
  }

  for (col in names(columns)) {
    d <- columns[[col]]$derivation
    where <- paste0("column ", col)
    if (is.null(d)) {
      if (!(col %in% row_cols)) fail(where, ": no derivation anywhere")
      next
    }
    if (col %in% row_cols) {
      fail(where, ": row templates overriding a column default are not ",
        "supported by this runner")
    }
    if (is.character(d)) d <- list(source = d)
    # A result wrapper: `value` holds the expression and `unconvertible` the
    # literal for a failed conversion (REQ-0219, REQ-0359).
    handler <- NULL
    if ("value" %in% names(d)) {
      extra <- setdiff(names(d), c("value", "unconvertible"))
      if (length(extra) > 0) {
        fail(where, ": `", extra[1], "` beside `value` is not supported by ",
          "this runner")
      }
      if ("unconvertible" %in% names(d)) {
        handler <- list(replacement = d$unconvertible)
      }
      d <- d$value
      if (is.character(d)) d <- list(source = d)
    }
    if (length(d) != 1) fail(where, ": a derivation holds exactly one keyword")
    arg <- d[[1]]
    value <- switch(names(d),
      literal = rep(if (is.null(arg)) NA else arg, nrow(data)),
      source = column_variable(arg, where),
      mapping = {
        x <- as.character(column_variable(arg$source, where))
        if (!isTRUE(arg$case_sensitive %||% TRUE)) {
          fail(where, ": case_sensitive: false is not supported by this runner")
        }
        if (!is.list(arg$dict)) {
          fail(where, ": a dict file is not supported by this runner")
        }
        # A dictionary value may be null: that key maps to missing.
        dict <- vapply(arg$dict, function(v) {
          if (is.null(v)) NA_character_ else as.character(v)
        }, character(1))
        out <- unname(dict[x])
        unmapped <- !is.na(x) & !(x %in% names(dict))
        if (any(unmapped)) {
          if (!("unmapped" %in% names(arg))) {
            fail(where, ": unmapped value(s): ",
              paste(unique(x[unmapped]), collapse = ", "))
          }
          out[unmapped] <- arg$unmapped %||% NA
        }
        handle_missing(out, x, arg, where)
      },
      cut = {
        x <- column_variable(arg$source, where)
        if (!is.numeric(x)) fail(where, ": cut source is not numeric")
        breaks <- as.numeric(unlist(arg$breaks))
        labels <- as.character(unlist(arg$labels))
        if (length(labels) != length(breaks) + 1) {
          fail(where, ": cut needs one more label than breaks")
        }
        out <- as.character(cut(x, c(-Inf, breaks, Inf),
          labels = labels,
          right = isTRUE(arg$right)
        ))
        handle_missing(out, x, arg, where)
      },
      # ASCII-only case change (REQ-0706, REQ-0707, REQ-1240).
      str_case = {
        x <- column_variable(arg$source, where)
        if (!is.character(x)) fail(where, ": str_case source is not a string")
        out <- switch(arg$to %||% "",
          upper = ascii_upper(x),
          lower = ascii_lower(x),
          sentence = paste0(ascii_upper(substr(x, 1, 1)),
            ascii_lower(substring(x, 2))),
          fail(where, ": str_case to: ", arg$to,
            " is not supported by this runner")
        )
        out[is.na(x)] <- NA
        handle_missing(out, x, arg, where)
      },
      # Numbers rows from 1 within each partition. Ties keep row-template
      # order, then driver order (REQ-1123), which is the row order here.
      row_number = {
        w <- arg$window
        if (!is.list(w)) {
          fail(where, ": named windows are not supported by this runner")
        }
        if (!is.null(w$filter)) {
          fail(where, ": window filters are not supported by this runner")
        }
        gb <- as.character(unlist(w$group_by))
        ob <- w$order_by
        if (!is.null(ob) && !is.character(unlist(ob, recursive = FALSE))) {
          fail(where, ": order_by mappings are not supported by this runner")
        }
        ob <- as.character(unlist(ob))
        for (v in c(gb, ob)) column_variable(v, where)
        for (v in ob) {
          if (anyNA(data[[v]])) {
            fail(where, ": missing order_by values are not supported by ",
              "this runner")
          }
        }
        part <- if (length(gb) > 0) row_key(data, gb) else rep("", nrow(data))
        terms <- c(
          list(match(part, unique(part))),
          unname(as.list(data[ob])),
          list(seq_len(nrow(data)))
        )
        o <- do.call(order, c(terms, list(method = "radix")))
        out <- integer(nrow(data))
        out[o] <- as.integer(ave(seq_along(o), part[o], FUN = seq_along))
        out
      },
      fail(where, ": `", names(d), "` is not supported by this runner")
    )
    data[[col]] <- as_declared(value, col, where, columns, handler)
  }

  # ---- Keys and verifications ----

  keys <- unlist(spec$keys)
  for (k in keys) {
    if (anyNA(data[[k]])) fail("key ", k, " is missing on some rows")
  }
  if (anyDuplicated(row_key(data, keys)) > 0) fail("duplicate key combination")

  for (col in names(columns)) {
    checks <- columns[[col]]$verifications
    if (is.null(checks)) next
    if (!is.null(names(checks))) checks <- list(checks) # one check, no list
    x <- data[[col]]
    for (check in checks) {
      where <- paste0("column ", col, ", ", names(check)[1])
      if (length(check) != 1) fail(where, ": one check per entry")
      if ((check[[1]]$severity %||% "error") != "error") {
        fail(where, ": severities other than error are not supported by ",
          "this runner")
      }
      switch(names(check),
        # REQ-0375: passes only when every value is present.
        not_missing = if (anyNA(x)) {
          fail(where, ": ", sum(is.na(x)), " missing value(s)")
        },
        # REQ-0376: every present value is one of the listed values.
        allowed_values = {
          allowed <- as.character(unlist(check$allowed_values$values))
          bad <- !is.na(x) & !(as.character(x) %in% allowed)
          if (any(bad)) {
            fail(where, ": value(s) not allowed: ",
              paste(head(unique(x[bad]), 5), collapse = ", "))
          }
        },
        fail(where, ": this check is not supported by this runner")
      )
    }
  }

  output_column <- function(name) {
    if (grepl(".", name, fixed = TRUE) || is.null(data[[name]])) {
      fail("verification names ", name, ", which is not a column (REQ-0405)")
    }
    data[[name]]
  }
  for (v in spec$verifications) {
    kind <- names(v)[1]
    if (length(v) != 1 || !(kind %in% c("unique", "implies"))) {
      fail("verification `", kind, "` is not supported by this runner")
    }
    body <- v[[1]]
    if (is.list(body) && (body$severity %||% "error") != "error") {
      fail("verification ", kind, ": severities other than error are not ",
        "supported by this runner")
    }
    if (kind == "unique") {
      vars <- unlist(if (is.list(body)) body$columns else body)
      for (x in vars) output_column(x)
      if (anyDuplicated(row_key(data, vars)) > 0) {
        fail("unique verification failed on ", paste(vars, collapse = ", "))
      }
    } else {
      # REQ-0383: where `when` is TRUE, `then` must be TRUE.
      where <- paste0("verification implies ", body$id %||% "")
      when <- eval_predicate(body$when, output_column, nrow(data), where)
      then <- eval_predicate(body$then, output_column, nrow(data), where)
      bad <- !is.na(when) & when & (is.na(then) | !then)
      if (any(bad)) {
        fail(where, ": ", sum(bad), " row(s) fail `", body$then, "` where `",
          body$when, "`; first: ", data$USUBJID[bad][1] %||% "")
      }
    }
  }

  # ---- Output ----

  order_by <- unlist(spec$output$order_by)
  if (length(order_by) > 0) {
    # radix order compares strings by code point, like yamaa, and is stable.
    data <- data[do.call(order, c(unname(as.list(data[order_by])),
      list(method = "radix"))), , drop = FALSE]
  }
  result <- data[unlist(spec$output$columns)]
  rownames(result) <- NULL

  write.csv(result, out_path, row.names = FALSE, na = "")
  message(sprintf("%d rows -> %s", nrow(result), out_path))
  invisible(result)
}

# ---- Cross-checks -----------------------------------------------------------

# Compares as text, except the `numeric` columns, which compare as numbers
# (R writes 100 where polars writes 100.0).
compare_reference <- function(out_path, ref_path, numeric = character()) {
  if (!file.exists(ref_path)) {
    message("no reference at ", ref_path, "; comparison skipped")
    return(invisible(NA))
  }
  r <- read.csv(out_path, colClasses = "character", na.strings = "")
  ref <- read.csv(ref_path, colClasses = "character", na.strings = "")
  for (v in intersect(numeric, intersect(names(r), names(ref)))) {
    r[[v]] <- as.numeric(r[[v]])
    ref[[v]] <- as.numeric(ref[[v]])
  }
  check <- all.equal(r, ref, check.attributes = FALSE)
  if (isTRUE(check)) {
    message("R runner matches ", ref_path)
  } else {
    message("R runner DIFFERS from ", ref_path, ":")
    print(check)
  }
  invisible(isTRUE(check))
}

# Runs the real Python engine on the same spec, when reticulate and the
# yamaa package are both available. The engine needs POSIX file APIs
# (os.open with dir_fd, O_NOFOLLOW), so it stops on native Windows; run it
# under Linux, macOS or WSL instead.
engine_cross_check <- function(spec_path, out_path) {
  if (.Platform$OS.type == "windows" ||
    !requireNamespace("reticulate", quietly = TRUE) ||
    !reticulate::py_module_available("yamaa")) {
    return(invisible(NA))
  }
  yamaa <- reticulate::import("yamaa")
  run <- yamaa$yamaa_domain(
    normalizePath(spec_path),
    schema_root = normalizePath(file.path("..", "yamaa", "yaml"))
  )
  if (is.null(run$output)) {
    print(run$issues)
    fail("the yamaa engine stopped; see the issues above")
  }
  run$save() # the output path the spec declares
  py <- read.csv(read_spec(spec_path)$output$path,
    colClasses = "character", na.strings = ""
  )
  r <- read.csv(out_path, colClasses = "character", na.strings = "")
  check <- all.equal(py, r, check.attributes = FALSE)
  if (isTRUE(check)) {
    message("R runner and yamaa engine agree")
  } else {
    message("R runner and yamaa engine DIFFER:")
    print(check)
  }
  invisible(isTRUE(check))
}
