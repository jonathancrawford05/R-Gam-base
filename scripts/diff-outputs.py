#!/usr/bin/env python3
"""Say WHICH part of two reference outputs differs.

TEMPORARY, alongside .github/workflows/diagnose-outputs.yml.

Build 7's image is reproducible and the newer image is not equal to it, so the
question is no longer "do they differ" but "where". A difference in
`environment` is provenance and harmless to the numbers; a difference in `data`
means the simulated inputs moved; a difference in `fit`/`vcov`/`prediction`
means mgcv computed something else.

  diff-outputs.py <a.json> <b.json>
"""

import json
import sys


def walk(a, b, path=""):
    """Yield (path, a, b) for each differing leaf, deepest-first."""
    if type(a) is not type(b):
        yield path, "type %s" % type(a).__name__, "type %s" % type(b).__name__
        return
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a:
                yield "%s.%s" % (path, k), "<absent>", "present"
            elif k not in b:
                yield "%s.%s" % (path, k), "present", "<absent>"
            else:
                yield from walk(a[k], b[k], "%s.%s" % (path, k))
    elif isinstance(a, list):
        if len(a) != len(b):
            yield path, "length %d" % len(a), "length %d" % len(b)
            return
        for i, (x, y) in enumerate(zip(a, b)):
            yield from walk(x, y, "%s[%d]" % (path, i))
    elif a != b:
        yield path, a, b


def main():
    a = json.load(open(sys.argv[1]))
    b = json.load(open(sys.argv[2]))

    diffs = list(walk(a, b))
    if not diffs:
        print("identical")
        return 0

    # Which top-level sections are implicated is the actual finding; the leaves
    # are only useful as evidence for it.
    sections = {}
    for path, _, _ in diffs:
        sections.setdefault(path.lstrip(".").split(".")[0].split("[")[0], 0)
        sections[path.lstrip(".").split(".")[0].split("[")[0]] += 1

    print("%d differing leaves, by section:" % len(diffs))
    for name, n in sorted(sections.items(), key=lambda kv: -kv[1]):
        print("  %-14s %d" % (name, n))

    print("\nfirst 15 differing leaves:")
    for path, x, y in diffs[:15]:
        sx, sy = repr(x), repr(y)
        if len(sx) > 60:
            sx = sx[:60] + "…"
        if len(sy) > 60:
            sy = sy[:60] + "…"
        print("  %s\n      A %s\n      B %s" % (path.lstrip("."), sx, sy))

    # A last-bit float difference and a structurally different value are very
    # different diagnoses, so quantify rather than eyeball.
    floats = [(p, x, y) for p, x, y in diffs
              if isinstance(x, float) and isinstance(y, float)]
    if floats:
        worst = max(floats, key=lambda t: abs(t[1] - t[2]))
        rel = [abs(x - y) / max(abs(x), abs(y)) for _, x, y in floats
               if max(abs(x), abs(y)) > 0]
        print("\n%d differing floats" % len(floats))
        print("  largest absolute difference: %s at %s" %
              (abs(worst[1] - worst[2]), worst[0].lstrip(".")))
        if rel:
            print("  largest relative difference: %.3e" % max(rel))
            print("  (~1e-16 is last-bit; anything larger is a real numeric change)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
