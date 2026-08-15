#!/usr/bin/env python3
"""Assert the reference outputs are identical to the last build's.

This is the check the README's central claim needs and did not have. selftest.R
verifies that two runs *inside one image* agree, and that varying the recorded
build time does not move a hash -- both good, both blind to the case this repo
actually cares about: does a rebuild of identical pinned inputs still produce
the same numbers?

Six builds existed before this check did, and no two of them had ever been
compared. An oracle whose reproducibility is asserted rather than measured is
just an image.

  check-output-hashes.py out/index.json catalog/expected-hashes.json

Exit 0 if they match, or if the baseline does not exist yet -- in which case it
is written and the caller should commit it. Exit 1 on any mismatch, with the
differing cases named.

A deliberate change to a case is expected to fail this. Delete the baseline
entry (or the file) in the same commit that changes the case, so the new hash
arrives as a reviewable diff rather than a silent update.
"""

import json
import os
import sys


def load_actual(path):
    with open(path) as fh:
        idx = json.load(fh)
    return {o["path"]: o["sha256"] for o in idx["outputs"]}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    index_path, baseline_path = sys.argv[1], sys.argv[2]

    actual = load_actual(index_path)

    if not os.path.exists(baseline_path):
        os.makedirs(os.path.dirname(baseline_path) or ".", exist_ok=True)
        with open(baseline_path, "w") as fh:
            json.dump(actual, fh, indent=2, sort_keys=True)
            fh.write("\n")
        print("no baseline yet; wrote %d hashes to %s" % (len(actual), baseline_path))
        print("BASELINE_WRITTEN=1")
        return 0

    with open(baseline_path) as fh:
        expected = json.load(fh)

    problems = []
    for name in sorted(set(expected) | set(actual)):
        want, got = expected.get(name), actual.get(name)
        if want is None:
            problems.append("  NEW      %s  %s" % (name, got))
        elif got is None:
            problems.append("  MISSING  %s  (expected %s)" % (name, want))
        elif want != got:
            problems.append("  CHANGED  %s\n      expected %s\n      got      %s"
                            % (name, want, got))

    if problems:
        print("::error title=Reference outputs changed::A rebuild of identical pinned "
              "inputs produced different numbers, or a case was edited without "
              "updating its baseline. This is the oracle moving underneath its "
              "consumers -- do not publish until it is understood.")
        print("\n".join(problems))
        return 1

    print("all %d reference outputs match the baseline" % len(actual))
    return 0


if __name__ == "__main__":
    sys.exit(main())
