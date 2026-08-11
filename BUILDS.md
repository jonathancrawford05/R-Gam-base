# Published builds

Every image ever published from this repository, oldest first. **Append only.**

This catalog exists because the image is used as a **numerical oracle**: a
downstream project runs `mgcv` inside it, commits the numbers as reference
values, and asserts its own implementation reproduces them. Those records are
only meaningful if the string identifying the oracle refers to exactly one build,
forever. The registry alone cannot promise that — a tag can be moved, an image
can be deleted — so the history lives here.

## How to read it

- **The digest is the primary key.** Always the full `sha256:…`, never
  abbreviated. Tags are for humans; the digest is what a measurement cites.
- **Rows are never edited.** If a published row turns out to be wrong, append a
  correction row and say so in *what changed*. The catalog records what happened,
  including mistakes.
- **Deleted builds stay listed**, marked `DELETED` in *what changed* with the
  reason. This is a history, not a mirror of current registry state.
- **A change to `mgcv` is material** and is called out in bold. Downstream
  numerical references may need re-measuring.

## Builds

| build | tag | digest | R | CRAN snapshot | mgcv | mboost | built (UTC) | repo SHA | what changed |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `r4.6.1-cran2026-08-01-b1` | `sha256:a77a61cf231933e17ec037ee0a63450067f66200a29ebc1cddbed14b8625ce8e` | 4.6.1 | 2026-08-01 | 1.9.4 | — | 2026-08-09T21:23:56Z | `0c6b56c31a88d911b1fc2732d779a9084268e597` | First published build. R 4.6.1 pinned by base digest `sha256:555a0e77…`, CRAN pinned to the 2026-08-01 P3M snapshot, mgcv/jsonlite/digest/sessioninfo installed from it. This is the digest polaris-re pinned as its conformance oracle and against which `tr(F)` was verified to 7.2e-13. Originally also carried `latest` and `r4.6.1-2026-08-01`; both were later moved to build 2. |
| 2 | `r4.6.1-cran2026-08-01-b2` | `sha256:8853bf2b600f6ce0fcae8e29d0a78e4b95ed3603dacb4f5cafa49e7c29606b7c` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-11T00:15:02Z | `95182b33cc7bcf13be99e061c034c8fb7c74971e` | Added `mboost` 2.9.13 and its tree (stabs 0.7.1, nnls 1.6, quadprog 1.5.8, partykit 1.2.29, survival 3.8.6) for `gamboost` GA2M work. **mgcv unchanged at 1.9.4**; R, the CRAN snapshot, Matrix 1.7.5, nlme 3.1.169, jsonlite 2.0.0 and digest 0.6.39 all unchanged, asserted at build time. **The `r4.6.1-2026-08-01` tag was moved from build 1 onto this build** — the name stayed truthful but stopped identifying a single artifact, which is what prompted the immutable-tag policy; that tag is deprecated and must not be used as a pin. |

## Notes on the backfilled rows

Builds 1 and 2 predate this policy, so they were catalogued by inspection rather
than produced by it. Specifically:

- Neither carries the `org.opencontainers.image.version` / `.created` /
  `.revision` labels, nor `/opt/oracle-manifest.json`. Both arrive from build 3
  onward. Build 2 does carry `/opt/oracle/manifest.json` and `/opt/versions.json`.
- **built (UTC)** is the completion of the publishing `docker push` step in the
  workflow run, not an `org.opencontainers.image.created` label, because these
  builds have no such label. Build 1: run
  [31336654228](https://github.com/jonathancrawford05/R-Gam-base/actions/runs/31336654228).
  Build 2: run
  [31445230665](https://github.com/jonathancrawford05/R-Gam-base/actions/runs/31445230665).
- The `-b1` and `-b2` tags were applied retroactively to the existing digests by
  the `retag` workflow, which copies the manifest rather than rebuilding. Neither
  digest changed.
- MASS is not recorded for these two builds: it was not in their manifest package
  list and could not be read without running the images. It is recorded from
  build 3 onward.
