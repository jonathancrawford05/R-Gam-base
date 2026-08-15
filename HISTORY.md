# History

Informal commentary. **Nothing here is machine-checked**, and nothing here should
be relied on as a record — [`catalog/builds/*.json`](catalog/builds) is the record,
and the image itself is the authority on what is inside it:

```bash
docker run --rm ghcr.io/jonathancrawford05/r-gam-base@<digest> \
  cat /opt/oracle-manifest.json
```

This file exists for one reason: two of the traps below cost a working day, both
are invisible until you hit them, and both are the kind of thing you would
otherwise rediscover from scratch.

## `docker buildx imagetools create` does not copy a manifest

Given a plain image manifest it builds a manifest **list** referencing it, and
that list is a new object with its own digest. Applying a tag with it therefore
points the tag at something that is *not* the digest you asked for:

```
copying sha256:a77a61cf... from ...@sha256:a77a61cf...
pushing sha256:1971e750... to ...:r4.6.1-cran2026-08-01-b1
```

Pulling the tag gave you the right image; the digest it resolved to was not the
right digest. Nothing was lost — build 1's digest was untouched throughout, and
the confirmation step caught the mismatch and failed the job — but a tag was
left pointing at a wrapper for about 40 minutes.

`scripts/point-tag-at-digest.sh` replaces it. A manifest's digest is the sha256
of its bytes, so it fetches the manifest by digest, checks the bytes hash to what
was asked for, and re-PUTs those exact bytes under the new name. Digest-preserving
by construction. (`crane tag` does the same thing; curl avoids another dependency.)

`sha256:1971e750f8c48be8eb941307d7d6873ac115803ce1f2b25a6aff6acb9b8f8ecb` still
exists in the registry, untagged. It is a one-entry manifest list whose child is
build 1. GHCR has no per-tag delete, and deleting the *version* would mean
deleting something that references a digest polaris-re pins, so it is left alone.

## Prose in a Markdown table is not data

The catalog used to be hand-written Markdown, and three separate checks read it
with `grep`:

- the next build number, from anything tag-shaped anywhere in the file;
- "is this digest catalogued", for the retag gate;
- "is this digest **not** catalogued", for the correction guard.

All three answered *"is this mentioned"* when the question was *"is this a
build"*. The correction guard refused to repair the `-b1` tag because the bad
digest appeared in the paragraph explaining that it was bad.

This is why the catalog is now JSON written by CI and `BUILDS.md` is generated
output. There is no prose column to misread, because there is no prose column.

## Two rows used to overclaim byte identity

Builds 3 and 4 were described as differing from their predecessors "only by
labels". That was false: 9 of 18 layers change on every publish, diverging from
layer 7, the first layer this Dockerfile adds. Labels live in the config blob,
not in layers.

It was never evidence that the *content* differed — layer digests are hashes of
tars, and tars carry mtimes and entry ordering, so a rebuild installing identical
packages produces exactly this. But it could not be checked either way, which was
the real problem. `scripts/check-output-hashes.py` now settles the question that
actually matters by comparing each build's reference-output hashes against the
previous build's.

The general rule the repository now follows, learned here: **don't write down a
claim about an artifact unless something checks it.** A byte-level statement
needs the bytes compared; a version statement needs the version read from the
installed library. Anything else belongs in this file.

## The `r4.6.1-2026-08-01` and `sha-<12>` tags

Both are retired and must not be used; see the tag table in
[README.md](README.md). `r4.6.1-2026-08-01` was moved from build 1 to build 2, so
it named two artifacts at two different times. The `sha-<12>` scheme — the first
12 characters of the repo commit SHA, published by builds 1 and 2 — was dropped
because a commit SHA does not identify a build: the monthly rebuild runs on an
unchanged `main` and would have pushed the same name onto a different digest.

Neither can be deleted, for the same reason as `1971e750` above.

## The oracle's numbers depended on the machine

Build 7 recorded output hashes `da0bafdf`/`0e3964c7`. Later builds produced
either those or `3ab5ad90`/`4a89f1e3` — **exactly two values, never a third,
roughly half the runs each** — while every version check passed: mgcv 1.9.4,
Matrix 1.7.5, nlme 3.1.169, `assert-pinned-versions.R` green, the selftest
green, the two image manifests differing only in `built_at`.

| run | commit | layer cache | result |
| --- | --- | --- | --- |
| push | `fb25715` | yes | fail |
| push, re-run | `fb25715` | yes | fail |
| push | `ce9005b4` | yes | **pass** |
| pull_request | `ce9005b4` | yes | pass |
| push | `e091a73` | no | pass |
| pull_request | `e091a73` | no | pass |
| push | `756a491` | no | **fail** |
| pull_request | `756a491` | no | pass |

### Two wrong causes, both stated too confidently

1. **BLAS/CPU floating point** — proposed first, then discarded because one
   diagnostic run reproduced build 7's hashes from a fresh build.
2. **The GHA layer cache** — concluded from that same run and written into the
   README, a workflow comment and a PR comment. The table refutes it outright:
   a cached build passed and a cache-free build failed.

Both were the same mistake: **treating a single observation of an intermittent
phenomenon as proof of a mechanism.** It cost most of a day and two retractions.

### The fix

Two stable values rather than a spread is the signature of two thread counts.
OpenBLAS sizes its pool from the visible core count, and a threaded reduction
sums in a different order than a serial one — correct either way, differing in
the last bits, which for an oracle is the entire artifact.

`OPENBLAS_NUM_THREADS=1`, `OMP_NUM_THREADS=1`, `MKL_NUM_THREADS=1` are set as
`ENV` in the image. Measured with `--cpuset-cpus` varied inside a single job
(run 31889520068), the pinned image produced identical outputs at 1, 2 and 4
cores, and produced a **third** value distinct from both earlier ones —
`6fc8c248`/`e3ffe80d` — which is what a serial reduction should give if thread
count was the variable.

**Evidence, stated precisely:** the pin makes the output independent of core
affinity *on one host*, and the new value is consistent with the thread
hypothesis. That is support, not proof. The proof is cross-host, and it arrives
for free: ordinary CI runs land on varied runners, so a run of green gate
results across successive builds is the confirmation. If the gate fails again,
the hypothesis is wrong and the two-valued pattern needs re-examining — do not
update the baseline to make it pass.

### Consequence for consumers

The reference values changed once, deliberately, at this commit. Digests already
pinned are unaffected — build 7 and earlier are exactly as published — but a
consumer adopting a build from here on is comparing against different numbers
and must re-measure at that point.
