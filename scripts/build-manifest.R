#!/usr/bin/env Rscript
# Records the environment actually resolved at image build time.
# Written to /opt/oracle/manifest.json and embedded in every reference output.

args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args) >= 1) args[[1]] else "/opt/oracle/manifest.json"

pkgs <- c(
  # the GAM oracle and what it links against
  "mgcv", "nlme", "Matrix", "survival",
  # serialisation and hashing of the outputs
  "jsonlite", "digest", "sessioninfo",
  # boosting, plus the tree the snapshot resolved for it
  "mboost", "stabs", "nnls", "quadprog", "partykit"
)
present <- pkgs[vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

env_or_null <- function(name) {
  v <- Sys.getenv(name, unset = "")
  if (nzchar(v)) v else NULL
}

manifest <- list(
  schema_version = "1.0.0",
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  r_svn_rev = R.version[["svn rev"]],
  platform = R.version$platform,
  base_image_digest = env_or_null("BASE_IMAGE_DIGEST"),
  cran_snapshot = env_or_null("CRAN_SNAPSHOT"),
  cran_repo = unname(getOption("repos")[["CRAN"]]),
  blas = tryCatch(sessioninfo::platform_info()$blas, error = function(e) NULL),
  lapack = tryCatch(sessioninfo::platform_info()$lapack, error = function(e) NULL),
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  packages = as.list(vapply(
    present,
    function(p) as.character(utils::packageVersion(p)),
    character(1)
  ))
)

dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"),
  out
)
