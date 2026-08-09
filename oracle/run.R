#!/usr/bin/env Rscript
# Usage:
#   Rscript /opt/oracle/run.R [--out DIR] [CASE.json ...]
#
# With no case files, runs every case shipped in the image.
# Writes one JSON per case plus an index.json recording each output's sha256.

suppressPackageStartupMessages({
  library(mgcv)
  library(jsonlite)
  library(digest)
})

oracle_home <- Sys.getenv("ORACLE_HOME", "/opt/oracle")
source(file.path(oracle_home, "lib_reference.R"))

args <- commandArgs(trailingOnly = TRUE)
out_dir <- "out"
if (length(args) >= 2 && args[[1]] == "--out") {
  out_dir <- args[[2]]
  args <- args[-(1:2)]
}

cases <- if (length(args) > 0) {
  args
} else {
  sort(list.files(file.path(oracle_home, "cases"), pattern = "[.]json$", full.names = TRUE))
}

if (length(cases) == 0) stop("no case files found", call. = FALSE)

manifest <- read_manifest()
index <- lapply(cases, function(p) {
  message("running case: ", basename(p))
  write_case_output(p, out_dir, manifest = manifest)
})

# The index carries the full manifest, build timestamp included. Provenance
# lives here precisely so it can stay out of the per-case outputs, whose hashes
# have to survive a rebuild of identical pinned inputs.
writeLines(
  jsonlite::toJSON(
    list(
      schema_version = ORACLE_SCHEMA_VERSION,
      environment = manifest,
      outputs = index
    ),
    auto_unbox = TRUE, pretty = TRUE, null = "null"
  ),
  file.path(out_dir, "index.json")
)

for (e in index) message(e$sha256, "  ", e$path)
message("wrote ", length(index), " reference output(s) to ", normalizePath(out_dir))
