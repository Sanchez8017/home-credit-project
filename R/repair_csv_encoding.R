# repair_csv_encoding.R
#
# Fixes CSV files that contain stray single-byte characters left over from
# a Windows-1252 (or similar) export, which are not valid on their own as
# UTF-8 and will cause strict UTF-8 readers (e.g. DuckDB's read_csv_auto)
# to fail. Each offending byte is rewritten to the UTF-8 encoding of its
# intended character, and the repaired copy is written to a new file so
# the original raw data is never modified in place.
#
# Example:
#   source("R/repair_csv_encoding.R")
#   fixed_path <- repair_csv_encoding("data/raw/some_file.csv")

#' Repair stray non-UTF-8 bytes in a CSV file
#'
#' @param path Path to the source CSV file.
#' @param byte_map Named character vector mapping a two-digit hex byte
#'   (e.g. "85") to the Unicode replacement text it stands for. Defaults
#'   to treating 0x85 as the Windows-1252 horizontal ellipsis ("\u2026"),
#'   which is the byte found in HomeCredit_columns_description.csv.
#' @param output_dir Directory to write the repaired copy into. Defaults
#'   to a session temp directory so raw source files are left untouched.
#'
#' @return The path to the repaired file, if any stray bytes were found
#'   and replaced. If no bytes in `byte_map` are present, the original
#'   `path` is returned unchanged (no copy is made).
repair_csv_encoding <- function(
  path,
  byte_map = c("85" = "\u2026"),
  output_dir = tempdir()
) {
  if (!file.exists(path)) {
    stop("File not found: ", path)
  }

  raw_bytes <- readBin(path, "raw", n = file.info(path)$size)

  stray_bytes <- as.raw(strtoi(names(byte_map), base = 16L))
  replacement_bytes <- lapply(unname(byte_map), charToRaw)

  is_stray <- raw_bytes %in% stray_bytes
  if (!any(is_stray)) {
    return(path)
  }

  fixed_bytes <- unlist(
    lapply(as.list(raw_bytes), function(byte) {
      match_index <- match(byte, stray_bytes)
      if (is.na(match_index)) byte else replacement_bytes[[match_index]]
    })
  )

  recoded_path <- file.path(output_dir, paste0("utf8_", basename(path)))
  writeBin(as.raw(fixed_bytes), recoded_path)

  recoded_path
}
