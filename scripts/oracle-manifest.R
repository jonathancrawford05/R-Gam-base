#!/usr/bin/env Rscript
# Writes /opt/oracle-manifest.json -- the image's build identity, readable with
#   docker run --rm <image> cat /opt/oracle-manifest.json
#
# Every package version here is read from the INSTALLED LIBRARY, not from a spec
# file. That distinction is the whole point: a spec records what was requested,
# an installed library records what is actually in the image, and the two drift
# the moment a dependency resolves to something other than what was asked for.
# This image is used as a numerical oracle, so the question a consumer asks is
# always "what produced this number", never "what did someone intend to install".
#
# Build metadata arrives through the environment, set from build args by the
# Dockerfile. A missing value is recorded as null rather than silently omitted,
# so a manifest built outside CI is visibly incomplete instead of quietly wrong.

out <- local({
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) >= 1) a[[1]] else "/opt/oracle-manifest.json"
})

env_or_null <- function(name) {
  v <- Sys.getenv(name, unset = "")
  if (nzchar(v)) v else NULL
}

# Recorded for every build. Anything mgcv links against belongs here, because a
# change in those moves the oracle's numbers without moving mgcv's version.
pkgs <- c(
  "mgcv", "jsonlite", "mboost",          # the ones a consumer asks about by name
  # nlme and Matrix are mgcv's only non-base dependencies and are version-locked
  # by assert-pinned-versions.R. MASS and survival are recorded but NOT
  # load-bearing for mgcv -- MASS is a Suggests, not a dependency, and neither is
  # gated. They are here so the manifest describes the image, not because a
  # change in them could move a number.
  "nlme", "Matrix", "MASS", "survival",
  "digest", "sessioninfo",               # output hashing and environment capture
  "stabs", "nnls", "quadprog", "partykit"
)
installed <- pkgs[vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
missing <- setdiff(pkgs, installed)

manifest <- list(
  schema_version = "2.0.0",

  # --- identity: what to write down when citing this image --------------------
  image = list(
    tag = env_or_null("IMAGE_TAG"),
    build_number = local({
      v <- env_or_null("BUILD_NUMBER")
      if (is.null(v)) NULL else as.integer(v)
    }),
    digest = NULL,  # not knowable from inside; the registry assigns it on push
    built_at = env_or_null("BUILD_CREATED"),
    repo = env_or_null("SOURCE_REPO"),
    revision = env_or_null("SOURCE_REVISION")
  ),

  # --- environment: what actually produced the numbers ------------------------
  r = R.version.string,
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  platform = R.version$platform,
  base_image_digest = env_or_null("BASE_IMAGE_DIGEST"),
  cran_snapshot = env_or_null("CRAN_SNAPSHOT"),
  cran_repo = unname(getOption("repos")[["CRAN"]]),
  blas = tryCatch(sessioninfo::platform_info()$blas, error = function(e) NULL),
  lapack = tryCatch(sessioninfo::platform_info()$lapack, error = function(e) NULL),

  packages = as.list(vapply(
    installed,
    function(p) as.character(utils::packageVersion(p)),
    character(1)
  )),
  packages_absent = if (length(missing)) as.list(missing) else NULL
)

dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
writeLines(
  jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"),
  out
)

# A build that cannot say what it is has no business being published.
if (is.null(manifest$image$tag) || is.null(manifest$image$revision)) {
  warning("oracle-manifest.json is missing build identity (IMAGE_TAG / SOURCE_REVISION)",
          call. = FALSE)
}
