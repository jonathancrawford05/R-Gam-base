#!/usr/bin/env python3
"""Compare freshly generated outputs against the committed baseline, and say
which of the two possible causes the result implies.

TEMPORARY. Delete alongside .github/workflows/diagnose-outputs.yml once the
question is answered.

  diagnose-repro.py <index.json> <baseline.json> <a-case-output.json>
"""

import json
import sys


def main():
    index_path, baseline_path, case_path = sys.argv[1], sys.argv[2], sys.argv[3]

    baseline = json.load(open(baseline_path))
    now = {o["path"]: o["sha256"] for o in json.load(open(index_path))["outputs"]}

    print("### committed baseline (written by build 7 itself)")
    for k, v in sorted(baseline.items()):
        print("  %s  %s" % (k, v))

    print("\n### what build 7's image produces today")
    for k, v in sorted(now.items()):
        print("  %s  %s" % (k, v))

    print("\n### verdict")
    if now == baseline:
        print("MATCHES -> build 7's image is stable. The baseline is a real property of")
        print("that image, so the images built since genuinely differ (case B), and the")
        print("cause is in the layers rather than in the check.")
    else:
        print("DIFFERS -> build 7's own image no longer reproduces the hashes build 7")
        print("committed. The baseline was never a property of the image (case A): the")
        print("gate has been comparing against a fiction, and the bug is mine.")
        for k in sorted(set(baseline) | set(now)):
            if baseline.get(k) != now.get(k):
                print("  %s\n    baseline %s\n    today    %s"
                      % (k, baseline.get(k), now.get(k)))

    # A difference here would mean the cause is provenance, not numerics.
    print("\n### embedded environment block")
    env = json.load(open(case_path))["environment"]
    print(json.dumps(env, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
