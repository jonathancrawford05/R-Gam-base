# Backlog — deferred findings and known limitations

Open work on this repository that was deliberately **not** done at the time it
was found, plus limitations that are accepted rather than fixed. One entry per
item, each with the condition that would make it matter, so a future maintainer
can decide whether it is worth doing rather than re-deriving the analysis.

Nothing here affects the correctness of the publish path today. Everything that
did — one P0 and five P1s from the review of PR #3 — was fixed before merge and
is listed under [Closed](#closed) for reference.

## How to read it

- **Trigger** is the concrete circumstance under which the item stops being
  theoretical. If the trigger cannot occur in your situation, the item is not
  costing you anything.
- **Effort** is implementation plus verification, assuming familiarity with the
  file in question.
- Items are listed in **suggested order**, which is by trigger likelihood ×
  cost-when-triggered, not by where they appear in the code.
- Line references are against `fdca7bc` and will drift. The file and the
  symptom are the durable parts.

## Deferred items

| # | area | one line | trigger likelihood | cost if triggered | effort |
|---|---|---|---|---|---|
| [P2-1](#p2-1) | `publish.yml` | build number is grepped out of free-form Markdown | **medium** | high — wedges publishing | S |
| [P2-2](#p2-2) | `oracle-manifest.R` | the build-identity guard can never fire | low | high — publishes an image stamped `unknown` | S |
| [P2-3](#p2-3) | `retag.yml` | source-digest check fails with no annotation | medium | low — operator confusion only | XS |
| [P2-4](#p2-4) | `retag.yml` / `publish.yml` | the two tag patterns disagree | very low | medium — retag refuses a real tag | XS |
| [P2-5](#p2-5) | `Dockerfile` | label keys were renamed without a note | low | low — a filter silently matches nothing | XS |
| [P2-6](#p2-6) | `README.md` | the retired `sha-<12>` tag is undocumented | low | low — a stale pin with no explanation | XS |
| [P2-7](#p2-7) | `publish.yml` | a documentation-only push publishes a build | **high** | low — a redundant build, correctly catalogued | XS |

---

### P2-1

**Build numbers are derived by grepping free-form Markdown.**
`.github/workflows/publish.yml:73-74`

```bash
last=$(grep -oE 'r[0-9.]+-cran[0-9-]+-b[0-9]+' BUILDS.md 2>/dev/null \
       | sed 's/.*-b//' | sort -n | tail -1)
```

The pattern matches anywhere in the file, including the *what changed* prose.
`BUILDS.md` explicitly encourages that prose — correction rows, deletion notes,
"superseded by" references — so the format most likely to break this is the one
the catalog asks for.

**Trigger.** Any narrative sentence containing a tag-shaped string with a build
number higher than the real maximum. A row reading "superseded by
`r4.6.1-cran2026-08-01-b9`" jumps the counter from 3 to 10.

**Cost.** Not a silent wrong answer — the counter only ever moves *forward*, so
no tag is reused and the fail-closed guard is never fooled. The damage is that
build numbers stop being a dense sequence and the catalog's own text can move
them, which is a surprising coupling for whoever hits it.

**Fix.** Restrict the match to the tag column, or at minimum to table rows:

```bash
last=$(grep -E '^\|' BUILDS.md | awk -F'|' '{print $3}' \
       | grep -oE 'b[0-9]+$' | tr -d b | sort -n | tail -1)
```

**Acceptance.** Add a prose row naming a `-b99` tag to a copy of `BUILDS.md`;
derivation must still return the real next number.

---

### P2-2

**The build-identity guard can never fire.**
`scripts/oracle-manifest.R:77-81`, with `Dockerfile:24-28`

```r
if (is.null(manifest$image$tag) || is.null(manifest$image$revision)) {
  warning("oracle-manifest.json is missing build identity (...)", call. = FALSE)
}
```

The Dockerfile defaults `IMAGE_TAG=unknown` and `SOURCE_REVISION=unknown`, so
`env_or_null()` sees `nzchar("unknown")` → `TRUE` and returns the string. The
`is.null()` test is therefore always `FALSE`. Two claims in the file's own header
are consequently untrue: the value is recorded as `"unknown"` rather than `null`,
so a manifest built outside CI is **not** visibly incomplete; and `warning()`
would not fail the build even if the branch were reachable, despite the comment
"a build that cannot say what it is has no business being published."

**Trigger.** A typo in a `build-args` key in `publish.yml` — `IMAGE_TG`,
`SOURCE_REVSION`. The build succeeds, the image publishes, and its manifest says
`"tag": "unknown"`.

**Cost.** High relative to its likelihood: a published oracle image that cannot
name itself, discovered later by whoever tries to trace a number back to a build.

**Fix.** Either default the ARGs to empty and `stop()` when CI is detected
(`Sys.getenv("CI") == "true"`), or test for the literal `"unknown"` explicitly.
Keep local `docker build` working and visibly unidentified — that part of the
current design is deliberate and worth preserving.

**Acceptance.** A build with a deliberately misspelled build-arg key fails, and a
plain local `docker build` still succeeds.

---

### P2-3

**`retag.yml` verifies the source digest with the tool this repo argues is
unreliable.** `.github/workflows/retag.yml:128-129`

```yaml
- name: Verify the source digest exists
  run: docker manifest inspect '${{ steps.meta.outputs.ref }}' >/dev/null
```

`check-tag-free.sh`'s header explains why `docker manifest inspect` was rejected
for the tag guard: it exits non-zero for absent, unauthorised, rate-limited and
network-dead alike. Here it fails **closed**, so it is safe — a transient
registry failure aborts the retag, which is the right outcome. The defect is only
in the reporting: a bare non-zero exit with no `::error` annotation, which is
exactly the "which failure was this?" confusion the script was written to remove.

**Trigger.** Any transient GHCR failure during a retag run.

**Fix.** Wrap it the way the tag guard is wrapped, and distinguish "digest absent"
(operator error — check the catalog) from "registry unreachable" (retry).

---

### P2-4

**The retag tag pattern is stricter than what publish generates.**
`retag.yml:67` vs `publish.yml:76`

Retag requires `^r[0-9]+\.[0-9]+\.[0-9]+-cran[0-9]{4}-[0-9]{2}-[0-9]{2}-b[0-9]+$`
— three-component R version. `publish.yml` interpolates `r_version` straight out
of `ARG R_VERSION` with no constraint at all.

**Trigger.** A two-component R version in the Dockerfile (`ARG R_VERSION=4.7`).
Publish would mint `r4.7-cran…-b4`; retag would refuse to ever apply that tag.
R releases as `x.y.z`, so this is theoretical.

**Fix.** One pattern, defined once. The cleanest version validates `R_VERSION` at
the point it is read in `publish.yml`, so a malformed version fails at resolve
time rather than producing a tag that half the toolchain rejects.

---

### P2-5

**Label keys were renamed without a note.** `Dockerfile:99-108`

| before (builds 1–2) | after (build 3 onward) |
| --- | --- |
| `io.polaris.oracle.r-version` | `io.polaris.r-version` |
| `io.polaris.oracle.cran-snapshot` | `io.polaris.cran-snapshot` |
| `io.polaris.oracle.base-digest` | `io.polaris.base-digest` |

Anything filtering on the old keys matches nothing rather than failing. Not
mentioned in PR #3's body or in the README.

**Trigger.** A consumer or script that filters images by the old label keys.
No such consumer is known — this is the same class of problem as a moved tag, so
it is recorded rather than assumed harmless.

**Fix.** A line in the README's identity section stating the rename and the build
it took effect from. Re-adding the old keys as duplicates is possible but not
recommended: two keys for one fact is how they drift apart.

---

### P2-6

**The retired `sha-<12>` tag is undocumented.** `README.md`, tag table

Builds 1 and 2 also published a `sha-<first 12 of the repo SHA>` tag.
`sha-0c6b56c31a88` and `sha-95182b33cc7b` are both present in GHCR — verified
against the live registry, not inferred from the workflow — and resolve to builds
1 and 2. PR #3 dropped the tag from the push loop, and the new tag table does not
mention it ever existed.

Dropping it was right, and the reason belongs in the record: a repo SHA does not
identify a build. The monthly scheduled rebuild runs on an unchanged `main`, so
it would have pushed the *same* `sha-<12>` tag onto a *different* digest — the
identical failure as `r4.6.1-2026-08-01`, just less obviously.

**Trigger.** Someone finds one of those two tags in the registry, or in an old
note, and cannot tell whether it is safe to use.

**Fix.** A deprecation line in the README's tag table next to
`r4.6.1-2026-08-01`, saying the tag was retired after build 2, why, and that the
two existing ones happen to be unambiguous only because no rebuild reused their
SHA.

---

### P2-7

**A documentation-only push to `main` publishes an image.**
`.github/workflows/publish.yml:3-11`

```yaml
on:
  push:
    branches: [main, "claude/**"]
    paths-ignore: ["BUILDS.md"]
```

Only `BUILDS.md` is excluded, and only because its own catalog commit would
otherwise retrigger the workflow forever. Every other path publishes — so editing
`README.md`, or this file, mints a build number, pushes a new immutable tag,
moves the floating tags and appends a catalog row, for an image whose bytes are
very likely identical to the previous one.

**Trigger.** Any docs commit to `main`. This is the most likely trigger in the
list, which is why it is worth a line even though the consequence is mild.

**Cost.** Low and self-correcting rather than dangerous: the build is real, its
digest is real, and the catalog row is accurate. The waste is CI minutes and a
gap in the build sequence that means nothing.

**Fix.** Extend `paths-ignore` to the documentation that cannot affect the image
— `README.md`, `BACKLOG.md`, `LICENSE`, `**/*.md` — leaving `workflow_dispatch`
as the way to force a rebuild anyway.

Deliberately **not** bundled with this file: it changes when the publish path
runs, which is the part of the workflow that got the most review scrutiny, and it
should arrive as its own reviewable diff rather than riding along with a
documentation commit. Note also that `paths-ignore` must never grow to cover
`oracle/`, `scripts/` or the `Dockerfile` — those do change the numbers.

---

## Accepted limitations

Not defects, and not scheduled. Recorded so they are not rediscovered as
surprises.

### L-1 — `r4.6.1-2026-08-01` cannot be deleted

GHCR has no per-tag delete. The API deletes package *versions*, and a version is
a digest. That tag sits on `sha256:8853bf2b…`, the current oracle, which
polaris-re has pinned — so deleting the version would destroy a validated
reference to remove a naming problem.

It is therefore **demoted, not deleted**: marked deprecated in the README with an
explanation, and superseded by `-b1`/`-b2`. Revisit only if GHCR gains per-tag
deletion, and even then only for tags no measurement cites.

### L-2 — the tag → catalog critical section is not atomic

`publish.yml` pushes the immutable tag, then reads versions, then appends and
pushes the `BUILDS.md` row. There is no transaction around those steps. A failure
between them leaves a published tag with no catalog row, which consumes a build
number and blocks the next publish until someone hand-edits the file.

Mitigated, not solved: `cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}`
makes publishing runs uninterruptible, which removes the only *routine* cause. A
runner crash or a GitHub outage can still land in the window. The recovery is
documented and the guard's error message names it, which is why this is accepted
rather than engineered around — a genuinely atomic version would need the catalog
to live in the registry, which is the thing the catalog exists to be independent of.

### L-3 — `retag.yml`'s definition and its data come from different refs

The workflow *definition* comes from the dispatched ref; the scripts and
`BUILDS.md` it reads come from `main` (`actions/checkout` with `ref: main`).
This is the intended trade — the gate must read the authoritative catalog and the
reviewed copy of `check-tag-free.sh`, not a branch's — but it means testing a
change to `retag.yml` on a branch validates against `main`'s catalog. Expect it
when iterating on that workflow.

## Closed

Fixed before PR #3 merged; listed so this file's scope is unambiguous.

| severity | issue | fixed in |
|---|---|---|
| P0 | `workflow_dispatch` from any branch could push that branch's history onto `main` | `c016cd9` |
| P1 | `rc=$?` unreachable under inherited `-e`; the whole guard `case` was dead code | `c016cd9` |
| P1 | catalog asserted a retag that had not happened | `c016cd9` |
| P1 | `/opt/versions.json` re-pointed at an incompatible schema | `c016cd9` |
| P1 | retag could mint an uncatalogued tag and wedge the next publish | `c016cd9` |
| P1 | `cancel-in-progress: true` opened a tag/catalog desync window | `fdca7bc` |
| — | `retag.yml` header contradicted its own catalog gate | `fdca7bc` |
| — | `retag.yml` validated against the dispatched ref's catalog | `fdca7bc` |

Full reasoning is in the review threads on
[PR #3](https://github.com/jonathancrawford05/R-Gam-base/pull/3).
