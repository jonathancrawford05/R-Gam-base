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

| build | tag (see note 3) | digest | R | CRAN snapshot | mgcv | mboost | built (UTC) | repo SHA | what changed |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `r4.6.1-cran2026-08-01-b1` | `sha256:a77a61cf231933e17ec037ee0a63450067f66200a29ebc1cddbed14b8625ce8e` | 4.6.1 | 2026-08-01 | 1.9.4 | — | 2026-08-09T21:23:56Z | `0c6b56c31a88d911b1fc2732d779a9084268e597` | First published build. R 4.6.1 pinned by base digest `sha256:555a0e77…`, CRAN pinned to the 2026-08-01 P3M snapshot, mgcv/jsonlite/digest/sessioninfo installed from it. This is the digest polaris-re pinned as its conformance oracle and against which `tr(F)` was verified to 7.2e-13. Originally also carried `latest` and `r4.6.1-2026-08-01`; both were later moved to build 2. |
| 2 | `r4.6.1-cran2026-08-01-b2` | `sha256:8853bf2b600f6ce0fcae8e29d0a78e4b95ed3603dacb4f5cafa49e7c29606b7c` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-11T00:15:02Z | `95182b33cc7bcf13be99e061c034c8fb7c74971e` | Added `mboost` 2.9.13 and its tree (stabs 0.7.1, nnls 1.6, quadprog 1.5.8, partykit 1.2.29, survival 3.8.6) for `gamboost` GA2M work. **mgcv unchanged at 1.9.4**; R, the CRAN snapshot, Matrix 1.7.5, nlme 3.1.169, jsonlite 2.0.0 and digest 0.6.39 all unchanged, asserted at build time. **The `r4.6.1-2026-08-01` tag was moved from build 1 onto this build** — the name stayed truthful but stopped identifying a single artifact, which is what prompted the immutable-tag policy; that tag is deprecated and must not be used as a pin. |
| 3 | `r4.6.1-cran2026-08-01-b3` | `sha256:9ea27ff8103aff292ec775e85a1d7ca810f7ea43dcde49d40ab210c13c591aaa` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-14T12:28:08Z | `c9cb8939255d3f13ec61fa7278c6ce471805104d` | First build produced under the immutable-tag policy (PR #3). **No version changed** -- R, the CRAN snapshot, mgcv 1.9.4 and mboost 2.9.13 are all identical to build 2, asserted at build time. What is new is identity: OCI labels (`org.opencontainers.image.version`/`.created`/`.revision`, `io.polaris.*`) and `/opt/oracle-manifest.json`, so this is the first image that can name itself. The bytes differ from build 2 only by those labels and that file. |
| 4 | `r4.6.1-cran2026-08-01-b4` | `sha256:e295b0e23bc4eb8dab806b1e46830dde477e44259b54dcea3a9135538a9ed61c` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-14T12:56:48Z | `e198f20c1771458cd22160b46d699b9ee2fb7c1e` | **No version changed** -- identical R, CRAN snapshot, mgcv 1.9.4 and mboost 2.9.13 to build 3, asserted at build time. Published by the merge of PR #4, which changed only workflows, scripts and documentation; the image differs from build 3 only in the labels that record its own tag, timestamp and repo SHA. First row inserted into the table rather than appended past the end of the file. |
| 5 | `r4.6.1-cran2026-08-01-b5` | `sha256:f77fd7ae6bfc86154e846632b0dad4e552ecf488d2db86b90074c9f8305c6037` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-14T13:06:31Z | `c1a7864acdefb7c25d20683477744220e28b04a8` | **No version changed** -- identical R, CRAN snapshot, mgcv 1.9.4 and mboost 2.9.13 to build 4, asserted at build time. Published by the merge of PR #5, which changed only catalog-reading logic (`scripts/catalog.sh`) and documentation. |
| 6 | `r4.6.1-cran2026-08-01-b6` | `sha256:779c286a13531d3d89e9742b282348dea1f6ce940c66a75d0f78ae41461550be` | 4.6.1 | 2026-08-01 | 1.9.4 | 2.9.13 | 2026-08-14T18:45:38Z | `99035a32dfe5efe467f80837f39fbdcbc3c1f1c1` | **No version changed** -- identical R, CRAN snapshot, mgcv 1.9.4 and mboost 2.9.13 to build 5, asserted at build time. Published by the merge of PR #7, which changed only README and BACKLOG. **Supersedes the build-5 reconciliation snapshot below**, exactly as that section warns: `latest` and `r4.6.1-latest` have moved off `f77fd7ae` onto this digest, and the snapshot has no `-b6` row. This was a known and accepted consequence of merging #7, not drift. |
<!-- new build rows are inserted directly above this line -->

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
- **The `-b1` and `-b2` tags were applied on 2026-08-14** and both resolve to
  the digests in this table, confirmed against the registry. It took three
  attempts; the section below records why. The digest column has been correct
  from the moment it was written, and remains the thing to resolve by.
- MASS is not recorded for these two builds: it was not in their manifest package
  list and could not be read without running the images. It is recorded from
  build 3 onward.

## The first `-b1` retag attempt was wrong

Recorded because this catalog is a history, and because the mistake is worth
knowing if you ever reach for the same tool.

`retag.yml` originally applied a tag with `docker buildx imagetools create`,
described in its own comments as "copies the manifest rather than rebuilding".
That is not what it does. Given a plain image manifest it builds a manifest
**list** referencing it, and the list is a new object with its own digest. Run
[31800500412](https://github.com/jonathancrawford05/R-Gam-base/actions/runs/31800500412):

```
copying sha256:a77a61cf... from ...@sha256:a77a61cf...
pushing sha256:1971e750... to ...:r4.6.1-cran2026-08-01-b1
```

So `r4.6.1-cran2026-08-01-b1` resolved, for about 40 minutes, to
`sha256:1971e750f8c48be8eb941307d7d6873ac115803ce1f2b25a6aff6acb9b8f8ecb` -- a
one-entry manifest list whose single child is build 1. Pulling that tag gave you
build 1's image; the digest it resolved to was nevertheless not build 1's.

What did **not** happen matters as much as what did:

- **Build 1's digest is untouched.** `sha256:a77a61cf…` is still present, still
  pullable, still exactly the bytes polaris-re validated. No recorded
  measurement is affected.
- **The run failed.** The confirmation step compared the resolved digest against
  the requested one and stopped the job, so nothing downstream acted on it and
  no catalog row claimed success. The tag was written before that check, which
  is why there is residue at all.
- **`-b2` was never attempted.** The two retags were run one at a time rather
  than together, so the fault produced one bad tag instead of two.

`1971e750` is deliberately **not** given a build number. It is not a build — it
is a wrapper created by a failed operation, it appears in no measurement, and
numbering it would imply the image was published on purpose.

The fix replaces `imagetools create` with a re-PUT of the manifest's exact bytes
(`scripts/point-tag-at-digest.sh`), which is digest-preserving by construction:
a manifest's digest *is* the hash of its bytes. Correcting the `-b1` tag then
requires re-pointing a tag, which this repository otherwise forbids — permitted
here by a rule narrow enough to keep the guarantee intact: a tag may be
re-pointed only when the digest it currently names **is not a build row in the
table above**, which is what proves no measurement can cite it.

### The second attempt failed too, on this document

Run [31802521297](https://github.com/jonathancrawford05/R-Gam-base/actions/runs/31802521297)
refused to correct the tag, reporting that `1971e750` "appears in BUILDS.md, so
it may be cited by a downstream measurement". It does appear — in the paragraph
above, which exists to say the opposite.

The guard asked `grep -qF "$digest" BUILDS.md`, so it answered "is this digest
*mentioned*" when the question was "is this digest a *build*". Both directions
of that mistake are wrong, and the lenient one is worse: the same file's
"the digest must be catalogued" gate would have accepted a digest that only ever
appeared in prose.

`scripts/catalog.sh` now reads the table as data — a row counts only when its
first cell is a build number — and every catalog check in both workflows goes
through it, including `publish.yml`'s build-number derivation, which had the
same flaw and was already recorded as P2-1 in the backlog. The guard behaved
correctly given what it was asked; it was asked the wrong question.

### Resolved

Both tags are applied and independently confirmed.

| tag | run | resolves to |
| --- | --- | --- |
| `r4.6.1-cran2026-08-01-b1` | [31803406179](https://github.com/jonathancrawford05/R-Gam-base/actions/runs/31803406179) | `sha256:a77a61cf231933e17ec037ee0a63450067f66200a29ebc1cddbed14b8625ce8e` |
| `r4.6.1-cran2026-08-01-b2` | [31803459455](https://github.com/jonathancrawford05/R-Gam-base/actions/runs/31803459455) | `sha256:8853bf2b600f6ce0fcae8e29d0a78e4b95ed3603dacb4f5cafa49e7c29606b7c` |

Verified three ways, because the whole point of the exercise was that the tool
did not do what its documentation said:

1. The workflow's own confirmation step, which reads the registry back rather
   than trusting the writer.
2. An independent anonymous pull of each tag's manifest, checking the
   `Docker-Content-Digest` header.
3. Hashing the returned manifest bytes -- both hash to the digest the tag
   resolves to, and both are plain image manifests (`manifest.v2+json`), not
   manifest lists. That last check is what would have caught the original fault
   immediately.

**Both digests are unchanged.** `a77a61cf` is the same digest polaris-re
validated `tr(F)` against; nothing about it moved at any point in this exercise.

`sha256:1971e750…` still exists in the registry. Nothing points at it -- it
carries no tag and appears in no measurement -- but it is itself a manifest list
whose single child is `sha256:a77a61cf…`, build 1. That child relationship is
the concrete reason it is left alone rather than a general caution: GHCR has no
per-tag delete, so removing it means deleting a package *version* that
references the digest polaris-re pins, and the blast radius of getting that
wrong is the oracle itself. It is not a build, has no build number, and is
recorded here instead of deleted.

### Registry reconciliation, as of build 5

**A point-in-time snapshot, not maintained.** Nothing updates it, and the next
publish makes three rows wrong at once: a `-b6` row goes missing and both
floating tags move off `f77fd7ae`. It is tied to a build number rather than a
date so that drift is self-evident from the catalog itself. `scripts/catalog.sh`
and the registry are authoritative; this is here to record that the two agreed
once, at a moment when that was in doubt.

Every tag present at build 5, and what it resolved to. The five immutable tags
match the build table exactly.

| tag | digest | kind |
| --- | --- | --- |
| `r4.6.1-cran2026-08-01-b1` | `sha256:a77a61cf…` | immutable |
| `r4.6.1-cran2026-08-01-b2` | `sha256:8853bf2b…` | immutable |
| `r4.6.1-cran2026-08-01-b3` | `sha256:9ea27ff8…` | immutable |
| `r4.6.1-cran2026-08-01-b4` | `sha256:e295b0e2…` | immutable |
| `r4.6.1-cran2026-08-01-b5` | `sha256:f77fd7ae…` | immutable |
| `latest` | `sha256:f77fd7ae…` | floating — **moves every publish** |
| `r4.6.1-latest` | `sha256:f77fd7ae…` | floating — **moves every publish** |
| `r4.6.1-2026-08-01` | `sha256:8853bf2b…` | **deprecated**, do not use |
| `sha-0c6b56c31a88` | `sha256:a77a61cf…` | retired scheme, do not use |
| `sha-95182b33cc7b` | `sha256:8853bf2b…` | retired scheme, do not use |

The two `sha-<12>` tags are from a scheme dropped in PR #3: a repo SHA does not
identify a build, and the monthly rebuild would eventually have pushed the same
name onto a different digest. They happen to be unambiguous only because no
rebuild has reused their SHA. The full explanation is in README.md's tag table;
BACKLOG.md records the history under P2-6, now closed.
