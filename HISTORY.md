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

## The layer cache produced different numbers under an identical manifest

The worst finding here, and the one the reproducibility gate was built without
knowing it would catch.

Build 8 failed the gate on its first real comparison: build 7 recorded output
hashes `da0bafdf`/`0e3964c7`, and every build after it produced
`3ab5ad90`/`4a89f1e3` — reproducibly. Meanwhile every version check passed.
mgcv 1.9.4, Matrix 1.7.5, nlme 3.1.169, `assert-pinned-versions.R` green, the
selftest green, the two manifests differing only in `built_at`.

Three builds in one job settled it:

| build | outputs |
| --- | --- |
| build 7's published image, pulled by digest, run twice | `da0bafdf` / `0e3964c7` |
| the same source, built fresh with **no cache** | `da0bafdf` / `0e3964c7`, identical field for field |
| the same source via `publish.yml`, with `cache-from: type=gha` | `3ab5ad90` / `4a89f1e3` |

The source was innocent, the runner was innocent, and the baseline was faithful.
**The variable was the GitHub Actions layer cache**, which served a layer that
computed different numbers while nothing observable about the environment
changed.

That is the exact drift this image exists to prevent, and it was invisible to
every check that existed before the output-hash gate — because version pinning
answers "is the same software installed", not "does it compute the same thing".

`cache-from`/`cache-to` were removed from the image build. Not a workaround: for
an image whose whole claim is that its answers do not move, a mutable cache in
the path that determines those answers cannot be traded for build time. The
build is about 50 seconds.

Two wrong turns on the way, recorded because both were confidently stated:
BLAS/CPU floating-point variation was proposed as the cause and was wrong, and
"a re-run produced the same hashes, therefore it is deterministic" was too
strong — a re-run rules out run-to-run races, not machine-to-machine variation.
Only running build 7's own image on the same host settled it.
