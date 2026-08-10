#!/usr/bin/env Rscript
# One variable per rebuild, enforced.
#
# A downstream project pins this image by digest and compares its numbers
# run-to-run. Adding a package must not move anything that can change those
# numbers -- and the dangerous case is NOT mgcv's own version. mgcv links against
# Matrix and nlme, so a new dependency that drags either of those forward changes
# the linear algebra underneath mgcv while `packageVersion("mgcv")` stays put. The
# rebuild would look clean and the oracle would have moved.
#
# LOCKED packages fail the build if they move. Everything else is recorded in the
# manifest but allowed to float, because it cannot reach the fitted numbers.
#
# WHEN THIS FAILS: that is the guard working. Do not "fix" it by updating the
# numbers below to whatever resolved -- that defeats the entire point. Either drop
# the change that dragged the dependency, or make moving it the deliberate,
# single subject of its own rebuild, and update these values in that commit.

expected_r <- "4.6.1"

# Resolved by the 2026-08-01 CRAN snapshot on the digest-pinned base image, and
# published as ghcr.io/jonathancrawford05/r-gam-base@sha256:a77a61cf2319...
locked <- c(
  mgcv     = "1.9.4",  # the oracle itself
  Matrix   = "1.7.5",  # mgcv links against it
  nlme     = "3.1.169",  # mgcv links against it
  jsonlite = "2.0.0",  # writes the numbers out
  digest   = "0.6.39"  # hashes the outputs
)

# Recorded, not gated: nothing here can change a fitted value. survival in
# particular arrives as an mboost dependency and is free to move.
watched <- c("survival", "sessioninfo", "mboost", "stabs", "nnls", "quadprog", "partykit")

actual_r <- paste(R.version$major, R.version$minor, sep = ".")
problems <- character(0)

if (!identical(actual_r, expected_r)) {
  problems <- c(problems, sprintf("R: expected %s, got %s", expected_r, actual_r))
}

for (p in names(locked)) {
  got <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
  if (is.na(got)) {
    problems <- c(problems, sprintf("%s: LOCKED but not installed", p))
  } else if (!identical(got, unname(locked[[p]]))) {
    problems <- c(problems, sprintf("%s: expected %s, got %s", p, locked[[p]], got))
  }
}

cat("locked:\n")
for (p in names(locked)) {
  got <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) "ABSENT")
  cat(sprintf("  %-10s %-10s (expected %s)\n", p, got, locked[[p]]))
}
cat("watched (recorded, not gated):\n")
for (p in watched) {
  got <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) "absent")
  cat(sprintf("  %-10s %s\n", p, got))
}

if (length(problems) > 0L) {
  stop(
    "pinned versions moved -- this rebuild changed more than one variable:\n  - ",
    paste(problems, collapse = "\n  - "),
    "\n\nA downstream project compares this image's output run-to-run. If mgcv or the ",
    "libraries it links against move in the same commit that adds a package, any change ",
    "in those numbers becomes unattributable. Read the comment at the top of ",
    "scripts/assert-pinned-versions.R before touching the expected values.",
    call. = FALSE
  )
}
cat("\nall locked versions match\n")
