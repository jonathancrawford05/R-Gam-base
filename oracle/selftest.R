#!/usr/bin/env Rscript
# Build-time gate. The image is not pushed unless this passes.
#
# The point is not "does R work" but "is this thing actually usable as an
# oracle": are the versions pinned and recorded, is the output bit-identical
# across runs, and does serialisation preserve full precision.

suppressPackageStartupMessages({
  library(mgcv)
  library(jsonlite)
  library(digest)
})

oracle_home <- Sys.getenv("ORACLE_HOME", "/opt/oracle")
source(file.path(oracle_home, "lib_reference.R"))

failures <- character(0)
check <- function(ok, what) {
  if (isTRUE(ok)) {
    message("ok   ", what)
  } else {
    failures <<- c(failures, what)
    message("FAIL ", what)
  }
}

# --- 1. the environment is pinned and self-describing ----------------------
manifest <- read_manifest()
check(!is.null(manifest), "manifest.json is present")
check(!is.null(manifest$packages$mgcv), "manifest records an mgcv version")
check(identical(as.character(utils::packageVersion("mgcv")), manifest$packages$mgcv),
      "installed mgcv matches the manifest")
check(!is.null(manifest$cran_snapshot) && !grepl("latest", manifest$cran_repo, fixed = TRUE),
      "CRAN repo is a dated snapshot, not 'latest'")
check(!is.null(manifest$base_image_digest), "manifest records the base image digest")

# Every package the harness depends on must be pinned and recorded, not just
# mgcv. jsonlite in particular is load-bearing: it is what writes the numbers.
required <- c("mgcv", "jsonlite", "digest")
check(all(required %in% names(manifest$packages)),
      "manifest records every package the harness depends on")

# mboost is not used by this harness, but the image ships it and a consumer needs
# to be able to stamp its output with the version that produced it. Its fitting
# behaviour is gated at build time by oracle/mboost_smoke.R, not here.
check("mboost" %in% names(manifest$packages),
      "manifest records the mboost version")
check(requireNamespace("mboost", quietly = TRUE), "mboost is installed and loadable")

# Printed so the resolved versions are answerable from the CI log alone,
# without pulling the image or unzipping an artifact.
message("R ", manifest$r_version, " | snapshot ", manifest$cran_snapshot)
message("packages: ", paste(sprintf("%s %s", names(manifest$packages),
                                    unlist(manifest$packages)), collapse = " | "))

# --- 2. full-precision serialisation ---------------------------------------
# jsonlite's default is 4 decimal digits, which would quietly ruin every
# comparison this image exists to support.
one_third <- serialise(list(x = 1 / 3))
check(grepl("0.33333333333", one_third, fixed = TRUE),
      "serialisation preserves full double precision")

# --- 3. mgcv fits, and the quantities we depend on exist -------------------
set.seed(1)
d <- gamSim(1, n = 300, dist = "normal", scale = 2, verbose = FALSE)
b <- gam(y ~ s(x0) + s(x1) + s(x2) + s(x3), data = d, method = "REML")

check(isTRUE(b$converged), "reference gam() converges")
check(is.numeric(b$edf) && length(b$edf) == length(coef(b)), "per-coefficient EDF available")
check(is.numeric(b$edf2), "smoothing-parameter-corrected EDF (edf2) available")
check(all(is.finite(vcov(b, unconditional = TRUE))), "vcov(unconditional = TRUE) is finite")
check(nrow(vcov(b)) == length(coef(b)), "vcov dimension matches the coefficient vector")
check(length(b$sp) == 4L, "one smoothing parameter per smooth term")

# --- 4. determinism: the property that makes this an oracle ----------------
a_dir <- file.path(tempdir(), "selftest-a")
b_dir <- file.path(tempdir(), "selftest-b")
case_files <- sort(list.files(file.path(oracle_home, "cases"),
                              pattern = "[.]json$", full.names = TRUE))
check(length(case_files) > 0, "shipped case files are present")

for (p in case_files) {
  h1 <- write_case_output(p, a_dir, manifest = manifest)$sha256
  h2 <- write_case_output(p, b_dir, manifest = manifest)$sha256
  check(identical(h1, h2), paste0("case '", basename(p), "' is byte-identical across runs"))
}

# Stronger than the above: identical across *rebuilds*, not merely across runs
# of one image. Only build time varies here, and it must not reach the output -
# otherwise the monthly rebuild would change every reference hash while every
# number stayed the same.
early <- manifest; early$built_at <- "2000-01-01T00:00:00Z"
late <- manifest; late$built_at <- "2030-12-31T23:59:59Z"
check(identical(write_case_output(case_files[[1]], file.path(tempdir(), "st-early"),
                                  manifest = early)$sha256,
                write_case_output(case_files[[1]], file.path(tempdir(), "st-late"),
                                  manifest = late)$sha256),
      "output hash is invariant to image build time")
check(is.null(run_case(jsonlite::fromJSON(case_files[[1]], simplifyVector = TRUE,
                                          simplifyDataFrame = FALSE),
                       manifest = manifest)$environment$built_at),
      "built_at is kept out of the embedded environment")

# --- 5. the lpmatrix really does reconstruct the linear predictor ----------
# Guards against emitting a design matrix that does not correspond to the fit.
case1 <- jsonlite::fromJSON(case_files[[1]], simplifyVector = TRUE, simplifyDataFrame = FALSE)
res <- run_case(case1, manifest = manifest)
beta <- unlist(res$fit$coefficients, use.names = FALSE)
check(ncol(res$prediction$lpmatrix) == length(beta),
      "lpmatrix column count matches the coefficient vector")
check(all(is.finite(res$prediction$lpmatrix)), "lpmatrix is finite")

# The documented contract: beta %*% t(lpmatrix) == predict(type = "link").
# Compared against an independent refit, so a bug that corrupted both the
# emitted matrix and the emitted coefficients in the same way still fails.
refit <- gam(as.formula(case1$formula), family = get(case1$family, mode = "function")(),
             data = simulate_data(case1), method = case1$method)
eta_direct <- as.vector(predict(refit, newdata = res$prediction$grid, type = "link"))
eta_lp <- as.vector(res$prediction$lpmatrix %*% beta)
check(identical(names(res$fit$coefficients), names(coef(refit))),
      "coefficient names are preserved in the output")
check(max(abs(eta_lp - eta_direct)) == 0,
      "lpmatrix exactly reconstructs the linear predictor")

if (length(failures) > 0) {
  stop("selftest failed:\n  - ", paste(failures, collapse = "\n  - "), call. = FALSE)
}
message("\nselftest passed (", length(case_files), " case(s))")
