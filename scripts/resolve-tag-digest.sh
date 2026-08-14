#!/usr/bin/env bash
# Print the digest a tag currently resolves to.
#
# Exit codes mirror check-tag-free.sh so the two read the same way at a call
# site, and so an unreachable registry can never be mistaken for an answer:
#
#   0  tag is absent            prints "ABSENT"
#   10 tag exists               prints the digest on stdout
#   1  no definite answer       prints nothing on stdout; reason on stderr
#
# Usage: resolve-tag-digest.sh ghcr.io/owner/name <tag>

set -uo pipefail

image="${1:?usage: resolve-tag-digest.sh <ghcr.io/owner/name> <tag>}"
tag="${2:?usage: resolve-tag-digest.sh <ghcr.io/owner/name> <tag>}"
repo="${image#ghcr.io/}"

# Anonymous works for a public package; credentials are used when present so a
# private package and a rate-limited runner both still get a real answer.
auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-u "x:${GITHUB_TOKEN}")

token=$(curl -sS --max-time 30 "${auth[@]}" \
  "https://ghcr.io/token?scope=repository:${repo}:pull&service=ghcr.io" 2>/dev/null \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))' 2>/dev/null)

if [ -z "$token" ]; then
  echo "resolve-tag-digest: could not obtain a registry token for ${repo}" >&2
  exit 1
fi

# All four media types: a plain image manifest and a manifest list are both
# legitimate answers here, and asking for only one of them turns the other into
# a 404 -- which would read as "absent" for a tag that plainly exists.
accept='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'

headers=$(curl -sS --max-time 30 -I -D - -o /dev/null \
  -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
  -w 'HTTP_STATUS:%{http_code}\n' \
  "https://ghcr.io/v2/${repo}/manifests/${tag}" 2>/dev/null)

code=$(printf '%s' "$headers" | sed -n 's/^HTTP_STATUS://p' | tail -1)

case "$code" in
  200)
    digest=$(printf '%s' "$headers" \
      | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p' | tail -1)
    if [ -z "$digest" ]; then
      echo "resolve-tag-digest: 200 with no Docker-Content-Digest header" >&2
      exit 1
    fi
    echo "$digest"
    exit 10
    ;;
  404)
    echo "ABSENT"
    exit 0
    ;;
  *)
    echo "resolve-tag-digest: registry returned HTTP ${code:-<none>} for ${image}:${tag}" >&2
    exit 1
    ;;
esac
