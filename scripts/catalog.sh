#!/usr/bin/env bash
# Read BUILDS.md's table as DATA. Never as text.
#
# The catalog is a Markdown document whose *what changed* column is deliberately
# discursive -- correction rows, deletion notes, "superseded by", and at least
# one section describing a digest that must never be used. Any check written as
# `grep -qF "$something" BUILDS.md` therefore matches prose as readily as data,
# and both directions of that are wrong:
#
#   * "this digest must be catalogued" passes for a digest merely *mentioned*
#   * "this digest must NOT be catalogued" fails for the same reason
#
# The second one is not hypothetical. Run 31802521297 refused to correct the
# -b1 tag because the bad digest it was correcting appears in the paragraph
# explaining that it is bad.
#
# A row is data iff its first cell is an integer -- the build number. Headers,
# separators, marker comments and prose all fail that test.
#
# Usage:
#   catalog.sh digests    [file]   one digest per build, in table order
#   catalog.sh tags       [file]   one immutable tag per build
#   catalog.sh max-build  [file]   highest build number, or 0 for an empty table
#
# Compare with `grep -qxF` (note -x), so a prefix can never masquerade as a hit.

set -uo pipefail

field="${1:?usage: catalog.sh <digests|tags|max-build> [file]}"
file="${2:-BUILDS.md}"

case "$field" in
  digests|tags|max-build) ;;
  *) echo "catalog.sh: unknown field '$field'" >&2; exit 2 ;;
esac

if [ ! -f "$file" ]; then
  echo "catalog.sh: no such file: $file" >&2
  exit 2
fi

awk -F'|' -v want="$field" '
  /^[[:space:]]*\|/ {
    n = $2; gsub(/[[:space:]]/, "", n)
    if (n !~ /^[0-9]+$/) next        # header row, separator, or a prose line
    tag = $3; digest = $4
    gsub(/[[:space:]`]/, "", tag)
    gsub(/[[:space:]`]/, "", digest)
    if      (want == "digests")   print digest
    else if (want == "tags")      print tag
    else if (want == "max-build") { if (n + 0 > max) max = n + 0 }
  }
  END { if (want == "max-build") print max + 0 }
' "$file"
