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

## The oracle's numbers depend on the machine (open)

The reproducibility gate failed on its first real comparison and is still
failing intermittently. Recorded here while it is open, because the wrong
answers along the way are instructive.

Build 7 recorded output hashes `da0bafdf`/`0e3964c7`. Later builds produce
either those or `3ab5ad90`/`4a89f1e3` — **exactly two values, never a third,
roughly half the runs each** — while every version check passes: mgcv 1.9.4,
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

Two wrong causes were proposed and both were stated with more confidence than
the evidence carried:

1. **BLAS/CPU floating point** — proposed first, then discarded because one
   diagnostic run reproduced build 7's hashes from a fresh build. One
   observation of an intermittent phenomenon proves nothing; that run landed on
   one side of a coin flip.
2. **The GHA layer cache** — concluded from that same run and stated publicly
   on PR #10. The table above refutes it outright: a cached build passed and a
   cache-free build failed.

The lesson, which cost most of a day: **when the phenomenon is intermittent, a
single observation cannot establish a cause.** Both errors were the same error.

What the data does support is that the cause is *discrete*. Two stable values
rather than a spread is the signature of two thread counts, since OpenBLAS
sizes its pool from the visible core count and a threaded reduction sums in a
different order than a serial one. `OPENBLAS_NUM_THREADS=1` is now set in the
image, and the mechanism is tested by varying `--cpuset-cpus` within a single
job rather than by re-running CI and hoping the runners differ.

`cache-from`/`cache-to` remain removed from the build. That is defensible on its
own for an image claiming reproducibility, but it is **not** the fix and was
never shown to be.
