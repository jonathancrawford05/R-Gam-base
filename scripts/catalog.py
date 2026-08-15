#!/usr/bin/env python3
"""Read the build catalog. The catalog is JSON; BUILDS.md is rendered from it.

Replaces the previous scripts/catalog.sh, which parsed BUILDS.md with awk. That
was the wrong direction: the document was the source of truth and the prose in
it kept being read as data -- a build number in a sentence moved the counter, a
digest named in a paragraph made a guard refuse. Here the records are JSON
written by CI from the published image, and the Markdown is output.

Usage:
  catalog.py digests            one digest per build, oldest first
  catalog.py tags               one immutable tag per build
  catalog.py max-build          highest build number, 0 if there are none
  catalog.py latest             the newest record, as JSON
  catalog.py render             render BUILDS.md to stdout
  catalog.py add FILE           add a record (from CI), refusing duplicates
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILDS_DIR = os.path.join(ROOT, "catalog", "builds")
LATEST = os.path.join(ROOT, "catalog", "latest.json")


def records():
    """Every build record, oldest first. Ordered by build number, not filename."""
    if not os.path.isdir(BUILDS_DIR):
        return []
    out = []
    for name in os.listdir(BUILDS_DIR):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(BUILDS_DIR, name)) as fh:
            out.append(json.load(fh))
    return sorted(out, key=lambda r: r["build"])


def render(recs):
    """BUILDS.md. Every column comes from a record field -- there is no prose
    column, because a column nothing can check is how this file went wrong."""
    lines = [
        "# Published builds",
        "",
        "**Generated from `catalog/builds/*.json` by `scripts/catalog.py render`.**",
        "Do not edit; edits are overwritten on the next publish. The JSON records are",
        "written by CI out of the image it just published, so every value here was read",
        "from the installed library rather than asserted by hand.",
        "",
        "Pin by digest. To see what is in an image without trusting this file:",
        "",
        "```bash",
        "docker run --rm ghcr.io/jonathancrawford05/r-gam-base@<digest> \\",
        "  cat /opt/oracle-manifest.json",
        "```",
        "",
        "Narrative about how builds came to be is in [HISTORY.md](HISTORY.md), which is",
        "commentary and is not machine-checked.",
        "",
        "| build | tag | digest | R | CRAN snapshot | mgcv | mboost | built (UTC) | source |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for r in recs:
        p = r.get("packages", {})
        lines.append(
            "| {build} | `{tag}` | `{digest}` | {r} | {snap} | {mgcv} | {mboost} "
            "| {built} | {source} |".format(
                build=r["build"],
                tag=r["tag"],
                digest=r["digest"],
                r=r.get("r_version", "?"),
                snap=r.get("cran_snapshot", "?"),
                mgcv=p.get("mgcv", "—"),
                mboost=p.get("mboost", "—"),
                built=r.get("built_at", "?"),
                source=r.get("source", "?"),
            )
        )
    lines += [
        "",
        "`source` is `published` when CI wrote the record from the image at publish",
        "time, and `backfilled` when it was reconstructed afterwards from that build's",
        "workflow run. Backfilled records may omit packages that were never recorded.",
        "",
    ]
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    recs = records()

    if cmd == "digests":
        print("\n".join(r["digest"] for r in recs))
    elif cmd == "tags":
        print("\n".join(r["tag"] for r in recs))
    elif cmd == "max-build":
        print(max((r["build"] for r in recs), default=0))
    elif cmd == "latest":
        if not recs:
            sys.exit("catalog.py: no builds recorded")
        print(json.dumps(recs[-1], indent=2))
    elif cmd == "render":
        print(render(recs))
    elif cmd == "add":
        with open(sys.argv[2]) as fh:
            new = json.load(fh)
        for key in ("build", "tag", "digest"):
            if key not in new:
                sys.exit("catalog.py: record is missing '%s'" % key)
        # Immutability, enforced on the catalog as well as the registry: a build
        # number, a tag and a digest are each claimed exactly once, forever.
        for r in recs:
            for key in ("build", "tag", "digest"):
                if r[key] == new[key]:
                    sys.exit(
                        "catalog.py: %s %r is already recorded by build %d"
                        % (key, new[key], r["build"])
                    )
        os.makedirs(BUILDS_DIR, exist_ok=True)
        with open(os.path.join(BUILDS_DIR, "%s.json" % new["tag"]), "w") as fh:
            json.dump(new, fh, indent=2, sort_keys=True)
            fh.write("\n")
        with open(LATEST, "w") as fh:
            json.dump(new, fh, indent=2, sort_keys=True)
            fh.write("\n")
        print("recorded build %d (%s)" % (new["build"], new["tag"]))
    else:
        sys.exit("catalog.py: unknown command %r" % cmd)


if __name__ == "__main__":
    main()
