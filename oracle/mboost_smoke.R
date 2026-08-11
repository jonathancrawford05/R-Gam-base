#!/usr/bin/env Rscript
# Build gate for mboost. Runs inside `docker build`, so a broken install fails the
# build rather than the first user.
#
# This is deliberately shaped like the real GA2M call rather than a generic
# gamboost() on toy data, because the constructs most likely to be missing or
# broken in a fresh install are the specific ones that fit uses:
#
#   bbs(x, df, knots)                          spline main effect
#   bols(f)                                    factor main effect
#   bbs(x, by = f, center = TRUE)              varying coefficient by a factor
#   bbs(x) %X% bbs(z)                          Kronecker (tensor) base-learner
#   bols(f, by = g)                            factor x factor
#   Binomial(type = "glm", link = "cloglog")   two-column cbind() response
#
# Each base-learner is fitted ALONE first, then all of them together. A generic
# smoke test would report "the formula failed"; this reports which construct
# failed, which is the difference between a five-minute fix and an afternoon.
#
# The data is synthetic but matches the real grain: cell-grouped mortality, one
# row per Smoke x FaceSize x StudyYear x Duration x AttainedAge cell, with the
# measures summed within a cell — not one row per policy-year.

suppressPackageStartupMessages(library(mboost))

# As set by the real fitting script. Governs when mboost switches to its indexed
# representation for tied covariate values, which cell-grouped data is full of.
options(mboost_indexmin = 1000)

failures <- character(0)
ok <- function(label) message("ok   ", label)
bad <- function(label, e) {
  failures <<- c(failures, sprintf("%s: %s", label, conditionMessage(e)))
  message("FAIL ", label, " -- ", conditionMessage(e))
}

cat("mboost", as.character(packageVersion("mboost")), "\n")

# --- synthetic cell-grouped mortality ---------------------------------------
RNGkind(kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
set.seed(20260810)

grid <- expand.grid(
  AttdAge  = seq(25, 90, by = 5),
  PolYear  = c(1, 2, 4, 6, 11, 16, 21, 26),
  StudyYr  = 2015:2022,
  Smoke    = factor(c("NT", "TB"), levels = c("NT", "TB")),
  FaceSize = factor(c("0", "1"), levels = c("0", "1")),
  KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
)
n <- nrow(grid)
d <- data.frame(
  AttdAge     = as.numeric(grid$AttdAge),
  PolYear     = as.numeric(grid$PolYear),
  StudyYear_C = as.numeric(grid$StudyYr) - 2018,
  Smoke       = grid$Smoke,
  FaceSize    = grid$FaceSize
)
# Exposure varies by cell; mortality rises with age, falls with duration, and is
# higher for smokers -- enough signal for boosting to have something to select.
d$ExposCnt <- pmax(50, round(rlnorm(n, meanlog = 6, sdlog = 0.7)))
eta <- -10.5 + 0.085 * d$AttdAge - 0.02 * d$PolYear + 0.03 * d$StudyYear_C +
  0.55 * (d$Smoke == "TB") + 0.15 * (d$FaceSize == "1")
d$DthCnt <- rbinom(n, size = d$ExposCnt, prob = 1 - exp(-exp(eta)))  # cloglog

cat(sprintf("cells: %d | deaths: %d | exposure: %d\n",
            n, sum(d$DthCnt), sum(d$ExposCnt)))
stopifnot(nrow(d) > 0, sum(d$DthCnt) > 0, all(d$DthCnt <= d$ExposCnt))

my_df <- 4
my_nu <- 0.2
resp <- quote(cbind(DthCnt, pmax(0, ExposCnt - DthCnt)))

# The crude rate on the link scale, passed as the starting offset. mboost derives
# a sensible offset from the family when this is NULL, so it is belt-and-braces
# rather than load-bearing: supplying it moved the starting risk by 0.5% (28590
# -> 28436), which is how we know the default was already sane.
crude_q <- sum(d$DthCnt) / sum(d$ExposCnt)
eta0 <- log(-log1p(-crude_q))
cat(sprintf("crude q: %.5f | offset (cloglog): %.4f\n", crude_q, eta0))

# --- the family, before any fitting ------------------------------------------
fam <- tryCatch(
  {
    f <- Binomial(type = "glm", link = "cloglog")
    ok('Binomial(type = "glm", link = "cloglog") constructs')
    f
  },
  error = function(e) {
    bad('Binomial(type = "glm", link = "cloglog") constructs', e)
    NULL
  }
)

# --- each base-learner on its own, so a failure names itself ------------------
fit_one <- function(label, rhs, mstop = 5L) {
  tryCatch(
    {
      fm <- as.formula(paste(deparse(resp), "~", rhs))
      m <- gamboost(fm, data = d, family = fam, offset = eta0,
                    control = boost_control(mstop = mstop, nu = my_nu, trace = FALSE))
      stopifnot(all(is.finite(predict(m, type = "link"))))
      ok(label)
      TRUE
    },
    error = function(e) {
      bad(label, e)
      FALSE
    }
  )
}

if (!is.null(fam)) {
  fit_one("bbs() spline main effect",
          "bbs(AttdAge, df = my_df, knots = 10)")
  fit_one("bols() factor main effect",
          "bols(Smoke)")
  fit_one("bbs(by = factor, center = TRUE) varying coefficient",
          "bbs(AttdAge, by = Smoke, df = my_df, knots = 10, center = TRUE)")
  fit_one("bbs(by = numeric, center = TRUE) varying coefficient",
          "bbs(AttdAge, by = StudyYear_C, df = my_df, knots = 8, center = TRUE)")
  fit_one("%X% Kronecker base-learner",
          "bbs(AttdAge, df = my_df, knots = 8) %X% bbs(PolYear, df = my_df, knots = 5)")
  invisible(fit_one("bols(f, by = g) factor x factor",
                    "bols(Smoke, by = FaceSize)"))
}

# --- the whole GA2M formula together -----------------------------------------
# Same base-learners, knots and df as the production fit; only mstop and the cell
# count are reduced, because this gate is about "does this construct work here",
# not about convergence quality.
if (length(failures) == 0L) {
  tryCatch(
    {
      ga2m <- cbind(DthCnt, pmax(0, ExposCnt - DthCnt)) ~
        bbs(AttdAge, df = my_df, knots = 10) +
        bbs(PolYear, df = my_df, knots = 6) +
        bbs(StudyYear_C, df = my_df, knots = 6) +
        bols(Smoke) +
        bols(FaceSize) +
        bbs(AttdAge, by = Smoke, df = my_df, knots = 10, center = TRUE) +
        bbs(AttdAge, by = FaceSize, df = my_df, knots = 10, center = TRUE) +
        bbs(PolYear, by = Smoke, df = my_df, knots = 6, center = TRUE) +
        bbs(PolYear, by = FaceSize, df = my_df, knots = 6, center = TRUE) +
        bbs(AttdAge, df = my_df, knots = 8) %X% bbs(PolYear, df = my_df, knots = 5) +
        bbs(AttdAge, df = my_df, knots = 8) %X% bbs(StudyYear_C, df = my_df, knots = 5) +
        bbs(AttdAge, by = StudyYear_C, df = my_df, knots = 8, center = TRUE) +
        bols(Smoke, by = FaceSize)

      fit <- gamboost(ga2m, data = d, family = fam, offset = eta0,
                      control = boost_control(mstop = 50L, nu = my_nu, trace = FALSE))

      cf <- coef(fit)
      pr <- predict(fit, type = "link")
      sel <- selected(fit)

      stopifnot(
        length(cf) > 0L,
        all(vapply(cf, function(x) all(is.finite(unlist(x))), logical(1))),
        all(is.finite(pr)),
        length(sel) == 50L,
        mstop(fit) == 50L
      )
      ok(sprintf("full GA2M formula: %d base-learners, %d selected distinct, risk %.4f -> %.4f",
                 length(fit$baselearner), length(unique(sel)),
                 risk(fit)[1], risk(fit)[length(risk(fit))]))

      # --- reported, not gated -------------------------------------------------
      # Whether the risk falls is a property of the MODEL on THIS synthetic data,
      # not of whether the image can run mboost. It is printed rather than
      # asserted, because a build gate that fails on the conditioning of a toy
      # problem blocks the image for a reason that has nothing to do with the
      # image. Two runs measured the combined fit diverging here (risk 28590 ->
      # 497350, then 28436 -> 524075, one base-learner selected at every
      # iteration) while every construct above fitted cleanly and returned finite
      # predictions -- so this is a question about the model specification, and it
      # belongs in front of a human rather than in an exit code.
      r <- risk(fit)
      cat(sprintf("risk path: %.4f -> %.4f over %d iterations (%d distinct learners)\n",
                  r[1], r[length(r)], length(r) - 1L, length(unique(sel))))
      cat("  first 5:", paste(sprintf("%.1f", head(r, 5)), collapse = " "), "\n")
      cat("  last 5: ", paste(sprintf("%.1f", tail(r, 5)), collapse = " "), "\n")
      # Measured shape: the first two or three steps overshoot hard (28e3 -> 341e3
      # -> 8.7e6 -> 1.5e7) and the path then falls steadily (8.3e5 ... 5.2e5) but
      # has not returned below its start by iteration 50. Small probabilities and
      # large exposures make the early negative gradient enormous, and nu = 0.2 is
      # not small enough to contain the first step. On real data mstop = 500 has
      # far more room to recover, but it is worth a maintainer checking
      # risk(fit)[1:10] rather than assuming the early path is productive.
      if (r[length(r)] >= r[1]) {
        message("NOTE risk has not returned below its starting value by iteration ",
                length(r) - 1L, " -- early overshoot, see the path above")
      }

      # NOT retried as a proportion + weights: mboost refuses it outright --
      # "response should be either a two-column matrix (no. successes and no.
      # failures) or a two level factor or a vector of 0 and 1's for this family".
      # So the production script's cbind() form is not merely supported, it is the
      # only accepted parameterisation for Binomial(type = "glm"), and the
      # overshoot above is not an artefact of how the response was passed.
    },
    error = function(e) bad("full GA2M formula", e)
  )
} else {
  message("\nskipping the combined fit -- a base-learner above already failed")
}

if (length(failures) > 0L) {
  stop("mboost smoke test failed:\n  - ", paste(failures, collapse = "\n  - "), call. = FALSE)
}
message("\nmboost smoke test passed")
