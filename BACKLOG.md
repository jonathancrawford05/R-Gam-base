# Backlog — deferred findings and known limitations

Open work on this repository that was deliberately **not** done at the time it
was found, plus limitations that are accepted rather than fixed. One entry per
item, each with the condition that would make it matter, so a future maintainer
can decide whether it is worth doing rather than re-deriving the analysis.

Nothing here affects the correctness of the publish path today. P2-1 did, once it
blocked a retag, so it was promoted out of this list and fixed. Everything that
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
| [P2-2](#p2-2) | `oracle-manifest.R` | the build-identity guard can never fire | low | high — publishes an image stamped `unknown` | S |
| [P2-4](#p2-4) | `retag.yml` / `publish.yml` | the two tag patterns disagree | very low | medium — retag refuses a real tag | XS |
| [P2-5](#p2-5) | `Dockerfile` | label keys were renamed without a note | low | low — a filter silently matches nothing | XS |
| [P2-7](#p2-7) | `publish.yml` | any push that cannot change the image still publishes a build | **high** | low — a redundant build, correctly catalogued | S |

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

### P2-7

**Any push that cannot change the image still publishes a build.**
`.github/workflows/publish.yml:3-11`

```yaml
on:
  push:
    branches: [main, "claude/**"]
    paths-ignore: ["BUILDS.md"]
```

Only `BUILDS.md` is excluded, and only because its own catalog commit would
otherwise retrigger the workflow forever. Every other path publishes: a new
build number, a new immutable tag, both floating tags moved, a catalog row —
for an image whose bytes are identical apart from the labels recording that it
is a different build.

**This was originally written as "a documentation-only push", which was too
narrow and made the item look cheaper than it is.** Builds 4, 5 and 6 are all
redundant, but only build 6 came from a docs-only merge:

| build | published by | non-`.md` files changed |
| --- | --- | --- |
| 4 | merge of #4 | `publish.yml`, `retag.yml`, `point-tag-at-digest.sh`, `resolve-tag-digest.sh` |
| 5 | merge of #5 | `publish.yml`, `retag.yml`, `catalog.sh` |
| 6 | merge of #7 | *(none — docs only)* |

Nothing in `.github/` is a Docker build input, and neither are the CI-only shell
scripts. So a `paths-ignore` of `**/*.md` — the obvious fix, and the one this
entry used to propose — would have prevented **one** of those three, and whoever
shipped it would see the next workflow tweak publish a build and reopen the item.

**Trigger.** Any push to `main` that touches no Docker build input. That is most
maintenance work on this repository.

**Cost.** Low and self-correcting rather than dangerous: the build is real, its
digest is real, the catalog row is accurate, and the tag guard is unaffected. The
waste is CI minutes, plus a build sequence with gaps that mean nothing — which
quietly weakens the catalog's usefulness as a narrative.

**Fix.** Extend `paths-ignore` to everything that cannot reach the image:

```yaml
paths-ignore:
  - "**/*.md"
  - "LICENSE"
  - ".github/**"
  - "scripts/catalog.sh"
  - "scripts/check-tag-free.sh"
  - "scripts/resolve-tag-digest.sh"
  - "scripts/point-tag-at-digest.sh"
```

**The build inputs, which must never appear in that list**, are exactly the
Dockerfile and what it `COPY`s:

| path | why it reaches the image |
| --- | --- |
| `Dockerfile` | the recipe |
| `oracle/**` | copied to `/opt/oracle/` |
| `scripts/build-manifest.R` | copied, and runs at build time |
| `scripts/assert-pinned-versions.R` | copied, and gates the build |
| `scripts/oracle-manifest.R` | copied, writes the identity manifest |

Note the direction the mechanism fails in, because it is the reason to keep
`paths-ignore` rather than switch to an allowlist: forgetting to ignore a new
documentation file costs a redundant build, while forgetting to *list* a new
build input under `paths:` would mean a real change silently never publishes.
A deny-list is wrong in the cheap direction.

**Acceptance.** A commit touching only `README.md` and a commit touching only
`.github/workflows/retag.yml` each run no publish job; a commit touching
`oracle/lib_reference.R` still does.

**Still deliberately not bundled with a documentation change.** It alters when
the publish path runs, which is the most heavily reviewed part of the workflow,
and belongs in its own reviewable diff.

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
| P2-3 | `retag.yml` checked the source digest with a bare `docker manifest inspect`, no annotation | superseded — that step is gone; `point-tag-at-digest.sh` reports the HTTP status |
| P2-6 | the retired `sha-<12>` tags were undocumented | fixed — two rows in README's tag table plus a callout, closing review P2-2 on PR #6 |
| P2-1 | catalog checks grepped free-form Markdown instead of reading the table | promoted and fixed — it stopped being theoretical when it blocked the `-b1` correction; all catalog reads now go through `scripts/catalog.sh` |

Full reasoning is in the review threads on
[PR #3](https://github.com/jonathancrawford05/R-Gam-base/pull/3).
