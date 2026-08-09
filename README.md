# R-Gam-base

A digest-pinned R + mgcv container that produces independent reference outputs
("oracle" outputs) for validating [Polaris RE](https://github.com/jonathancrawford05/polaris-re)'s
penalized GAM implementation.

The value of an oracle is that its answers do not move. If a comparison fails,
that has to mean *your* implementation changed — never that the reference did.
Everything below exists to make that true.

## What is pinned, and why

| Layer | Pinned by | Why it would otherwise drift |
| --- | --- | --- |
| Base image | `rocker/r-ver:4.6.1@sha256:555a0e77…` | The `4.6.1` tag is periodically rebuilt, so the tag alone moves. |
| R | Base image digest | — |
| CRAN packages | Dated P3M snapshot (`CRAN_SNAPSHOT`) | `rocker/r-ver` ships `CRAN=…/noble/latest`, which resolves to whatever is current at build time. |
| Consumed image | `@sha256:` digest in the consumer | A `:latest` tag would let a rebuild silently change your reference. |

Two notes on the base image, both of which are easy to get wrong:

- **`rocker/r-ver`, not `rocker/r-base`.** `r-base` tracks current R and installs
  whatever package versions exist at build time — a reference whose answers can
  change between runs.
- **`r-ver` does *not* pin CRAN for you.** It is built with
  `--with-recommended-packages`, so mgcv is already present, but its default
  repo is `…/noble/latest`. This image overrides that with a dated snapshot in
  `Rprofile.site`. mgcv is then installed explicitly so its version is a
  deliberate choice rather than a side effect of which R release the base
  happens to track.

The resolved versions are frozen into `/opt/oracle/manifest.json` at build time
and embedded in **every** reference output, so "which mgcv produced this number"
is answerable from the artifact alone.

## Use it

```bash
docker pull ghcr.io/jonathancrawford05/r-gam-base:latest
docker run --rm -v "$PWD/out:/work/out" \
  ghcr.io/jonathancrawford05/r-gam-base:latest \
  Rscript /opt/oracle/run.R --out /work/out
```

In the consuming repository's CI, as a job container — the workspace is mounted
automatically, so committed case files are simply present and outputs land back
in the workspace:

```yaml
mgcv-conformance:
  runs-on: ubuntu-latest
  container: ghcr.io/jonathancrawford05/r-gam-base@sha256:<digest>
  steps:
    - uses: actions/checkout@v4
    - run: Rscript /opt/oracle/run.R --out reference/
    - run: <compare reference/ against the Polaris RE implementation>
```

The digest for each build is printed in that run's GitHub Actions job summary.

Keep the image **public** on GHCR. A public package needs no credentials from
the consumer; a private one would require a PAT with `read:packages`, because a
repository's `GITHUB_TOKEN` cannot read another repository's packages. Nothing
here is sensitive — it is a build recipe for open-source packages.

## What an output contains

One JSON file per case, plus `index.json` recording each file's sha256.

| Field | Purpose |
| --- | --- |
| `environment` | The build manifest: R version, mgcv version, CRAN snapshot, base digest, BLAS/LAPACK. |
| `data` | The simulated inputs, plus a sha256 of their canonical CSV form so you can prove both implementations were fed identical data. |
| `fit.coefficients` | Fitted coefficients, named. |
| `fit.edf` / `fit.edf2` | Per-coefficient EDF (`tr(F)`) and the smoothing-parameter-uncertainty-corrected version that pairs with `vcov(unconditional = TRUE)`. |
| `fit.smoothing_parameters` | The selected smoothing parameters. |
| `vcov.conditional` / `vcov.unconditional` | Both covariance flavours. |
| `smooths[].penalties` | The penalty matrices `S` for each smooth (a list — a tensor product carries several). |
| `prediction.lpmatrix` | The design matrix at a fixed grid; `beta %*% t(lpmatrix)` reproduces the linear predictor. |

Emitting the design and penalty matrices — not just the fitted values — is what
makes a failure diagnosable. A mismatch in `lpmatrix` is a basis-construction
bug, a mismatch in `S` is a penalty bug, and a mismatch in only the
coefficients is a fitting/optimisation bug.

Numbers are serialised with `digits = NA` (full double precision). jsonlite's
4-digit default would quietly destroy the comparison, so the selftest asserts
against it.

## Adding a case

Drop a JSON file in `oracle/cases/`:

```json
{
  "id": "gaussian_tp_cr",
  "seed": 20260809,
  "n": 400,
  "family": "gaussian",
  "method": "REML",
  "formula": "y ~ s(x1, bs = 'tp', k = 10) + s(x2, bs = 'cr', k = 8) + x3",
  "predictors": {
    "x1": { "dist": "uniform", "min": 0, "max": 1 },
    "x3": { "dist": "normal", "mean": 0, "sd": 1 }
  },
  "response": { "eta": "2 + sin(2 * pi * x1) + 0.3 * x3", "sd": 0.4 },
  "predict_n": 50
}
```

`family` is one of `gaussian`, `binomial`, `poisson`. `formula` and
`response.eta` are evaluated as R expressions — case files are a trusted,
in-repo DSL, so do not point this at untrusted input.

Data generation sets the RNG algorithm explicitly
(`RNGkind("Mersenne-Twister", "Inversion", "Rejection")`) before seeding;
`set.seed()` alone is not sufficient for reproducibility across environments.

## CI

`.github/workflows/publish.yml` builds, **tests, and only then pushes** — the
bytes that pass the selftest are the exact bytes published. The selftest checks
that the environment is pinned and self-describing, that serialisation preserves
full precision, that the mgcv quantities we depend on exist, and that repeated
runs are byte-identical.

Publishing is deliberately narrow: `main`, the monthly rebuild, or an explicit
`workflow_dispatch`. Pull requests and feature branches build and selftest
without pushing, so a branch can prove the image is sound without moving
`:latest`.

The monthly rebuild moves nothing. Because the base is digest-pinned and CRAN is
snapshot-pinned, it cannot pull in base-OS patches either — what it proves is
that the pinned snapshot is still resolvable and the image still builds, which
is early warning that a pin has rotted. Picking up OS patches means bumping
`BASE_DIGEST`, which is a deliberate commit.

Because of that, a rebuild must produce byte-identical reference outputs. The
image build time is deliberately kept out of each output and recorded in
`index.json` instead; the selftest asserts an output's hash does not change when
only the build time does.

## Bumping versions

Deliberately a reviewable commit, never automatic:

1. Edit `ARG R_VERSION`, `ARG BASE_DIGEST`, and/or `ARG CRAN_SNAPSHOT` in the
   `Dockerfile`.
2. Merge; CI publishes and prints the new digest.
3. Update the digest in the consuming repository, with the re-run attached.

That way an mgcv update can never silently change the reference — it always
arrives as a diff someone approved.
