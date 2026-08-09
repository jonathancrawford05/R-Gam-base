# Reference-output generator for penalized GAMs fitted with mgcv.
#
# Produces the quantities an independent implementation has to match: the fitted
# coefficients, the per-term EDF, the smoothing parameters, both flavours of the
# covariance matrix, the linear-predictor (design) matrix at a fixed grid, and
# the penalty matrices themselves. Emitting the design and penalty matrices
# matters because it lets a consumer localise a disagreement: a mismatch in the
# lpmatrix is a basis-construction bug, a mismatch in S is a penalty bug, and a
# mismatch only in the coefficients is a fitting/optimisation bug.
#
# Case files are a trusted, in-repo DSL: `formula` and `response.eta` are
# evaluated as R expressions. Do not point this at untrusted input.

ORACLE_SCHEMA_VERSION <- "1.0.0"

read_manifest <- function(path = file.path(Sys.getenv("ORACLE_HOME", "/opt/oracle"),
                                           "manifest.json")) {
  if (!file.exists(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

# Deterministic across machines and R versions: the RNG algorithm is stated
# explicitly rather than inherited from whatever the session default happens to
# be. set.seed() alone is not enough for a reproducible oracle.
seed_rng <- function(seed) {
  RNGkind(kind = "Mersenne-Twister", normal.kind = "Inversion",
          sample.kind = "Rejection")
  set.seed(as.integer(seed))
  invisible(NULL)
}

draw_predictor <- function(spec, n) {
  switch(
    spec$dist,
    uniform = stats::runif(n, spec$min, spec$max),
    normal  = stats::rnorm(n, spec$mean, spec$sd),
    stop("unsupported predictor distribution: ", spec$dist, call. = FALSE)
  )
}

simulate_data <- function(case) {
  seed_rng(case$seed)
  n <- as.integer(case$n)

  cols <- lapply(case$predictors, draw_predictor, n = n)
  dat <- as.data.frame(cols, stringsAsFactors = FALSE)

  eta <- eval(parse(text = case$response$eta), envir = dat)

  dat$y <- switch(
    case$family,
    gaussian = eta + stats::rnorm(n, 0, case$response$sd),
    binomial = stats::rbinom(n, size = 1, prob = stats::plogis(eta)),
    poisson  = stats::rpois(n, lambda = exp(eta)),
    stop("unsupported family: ", case$family, call. = FALSE)
  )
  dat
}

# A crossed grid would blow up combinatorially with the number of predictors, so
# each predictor is swept over its own observed range in lockstep: row i holds
# every predictor at its i-th step. That still exercises each basis across its
# full support, which is what the lpmatrix comparison needs.
prediction_grid <- function(dat, m) {
  vars <- setdiff(names(dat), "y")
  as.data.frame(
    lapply(dat[vars], function(x) seq(min(x), max(x), length.out = m)),
    stringsAsFactors = FALSE
  )
}

describe_smooth <- function(sm, fit) {
  idx <- sm$first.para:sm$last.para
  out <- list(
    label = sm$label,
    terms = sm$term,
    bs_dim = sm$bs.dim,
    null_space_dim = sm$null.space.dim,
    first_para = sm$first.para,
    last_para = sm$last.para,
    edf = unname(sum(fit$edf[idx])),
    # One smooth can carry several penalties (e.g. tensor products), so S is
    # always a list even when it has length 1.
    penalties = unname(lapply(sm$S, as.matrix))
  )
  if (!is.null(sm$xp)) out$knots <- as.numeric(sm$xp)          # cr / cc bases
  if (!is.null(sm$knots)) out$knots <- as.numeric(sm$knots)    # bs / ps bases
  out
}

run_case <- function(case, manifest = read_manifest()) {
  dat <- simulate_data(case)
  fam <- get(case$family, mode = "function")

  fit <- mgcv::gam(
    formula = stats::as.formula(case$formula),
    family = fam(),
    data = dat,
    method = case$method
  )

  grid <- prediction_grid(dat, if (is.null(case$predict_n)) 50L else as.integer(case$predict_n))
  lp <- stats::predict(fit, newdata = grid, type = "lpmatrix")

  # Canonical serialisation of the inputs, so a consumer can prove it fed the
  # oracle and its own implementation byte-identical data.
  data_csv <- paste(utils::capture.output(
    utils::write.csv(dat, row.names = FALSE)
  ), collapse = "\n")

  list(
    schema_version = ORACLE_SCHEMA_VERSION,
    case = case,
    environment = manifest,
    data = list(
      n = nrow(dat),
      columns = names(dat),
      sha256 = digest::digest(data_csv, algo = "sha256", serialize = FALSE),
      values = dat
    ),
    fit = list(
      converged = fit$converged,
      method = fit$method,
      rank = fit$rank,
      df_residual = stats::df.residual(fit),
      coefficients = as.list(fit$coefficients),
      # edf  = tr(F), the standard EDF.
      # edf2 = the smoothing-parameter-uncertainty-corrected version that pairs
      #        with vcov(unconditional = TRUE).
      edf = unname(fit$edf),
      edf2 = unname(fit$edf2),
      edf_total = sum(fit$edf),
      smoothing_parameters = as.list(fit$sp),
      scale = fit$scale,
      sig2 = fit$sig2,
      deviance = fit$deviance,
      null_deviance = fit$null.deviance,
      aic = fit$aic,
      gcv_ubre = unname(fit$gcv.ubre)
    ),
    vcov = list(
      conditional = unname(as.matrix(stats::vcov(fit, unconditional = FALSE))),
      unconditional = unname(as.matrix(stats::vcov(fit, unconditional = TRUE)))
    ),
    smooths = unname(lapply(fit$smooth, describe_smooth, fit = fit)),
    prediction = list(
      grid = grid,
      # Row-major nested arrays. beta %*% t(lpmatrix) reproduces the linear
      # predictor, so this pins the basis independently of the fit.
      lpmatrix = unname(as.matrix(lp))
    )
  )
}

# digits = NA emits full double precision rather than jsonlite's 4-digit
# default, which would silently destroy the numbers this whole repo exists to
# compare.
serialise <- function(x) {
  jsonlite::toJSON(
    x,
    auto_unbox = TRUE,
    digits = NA,
    matrix = "rowmajor",
    dataframe = "columns",
    na = "null",
    null = "null",
    pretty = 2
  )
}

write_case_output <- function(case_path, out_dir, manifest = read_manifest()) {
  case <- jsonlite::fromJSON(case_path, simplifyVector = TRUE, simplifyDataFrame = FALSE)
  result <- run_case(case, manifest = manifest)

  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  out_path <- file.path(out_dir, paste0(case$id, ".json"))
  writeLines(serialise(result), out_path)

  list(
    id = case$id,
    path = out_path,
    sha256 = digest::digest(file = out_path, algo = "sha256")
  )
}
