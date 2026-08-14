#!/usr/bin/env bash
# Point a tag at an existing digest WITHOUT changing that digest.
#
# `docker buildx imagetools create` cannot do this, which is not obvious and
# cost this repository a bad tag before it was noticed. Given a plain image
# manifest it does not copy the manifest -- it builds a manifest LIST that
# references it, and that list is a new object with its own digest. The tag then
# names something the catalog has never heard of:
#
#   copying sha256:a77a61cf... from ...@sha256:a77a61cf...
#   pushing sha256:1971e750... to ...:r4.6.1-cran2026-08-01-b1
#
# That is run 31800500412. The image content was identical and the old digest
# was untouched, but "the tag resolves to the catalogued digest" -- the one
# property this workflow exists to provide -- was false.
#
# A manifest's digest is by definition the sha256 of its bytes. So fetch the
# bytes, verify they hash to the digest asked for, and PUT those exact bytes
# under the new name. Digest-preserving by construction rather than by hope.
# This is what `crane tag` does; done here with curl to keep the mechanism
# auditable and the workflow free of another third-party action.
#
# Exit codes:
#   0  the tag now resolves to <digest>
#   1  it does not, and nothing was changed that would make it look as if it did
#
# Usage: point-tag-at-digest.sh ghcr.io/owner/name sha256:<64 hex> <tag>

set -uo pipefail

image="${1:?usage: point-tag-at-digest.sh <ghcr.io/owner/name> <digest> <tag>}"
digest="${2:?usage: point-tag-at-digest.sh <ghcr.io/owner/name> <digest> <tag>}"
tag="${3:?usage: point-tag-at-digest.sh <ghcr.io/owner/name> <digest> <tag>}"
repo="${image#ghcr.io/}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "point-tag-at-digest: GITHUB_TOKEN is required (this pushes)" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- token -------------------------------------------------------------------
# push scope as well as pull: writing a tag is a manifest PUT.
token=$(curl -sS --max-time 30 -u "x:${GITHUB_TOKEN}" \
  "https://ghcr.io/token?scope=repository:${repo}:pull,push&service=ghcr.io" 2>/dev/null \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))' 2>/dev/null)

if [ -z "$token" ]; then
  echo "point-tag-at-digest: could not obtain a pull,push token for ${repo}" >&2
  exit 1
fi

accept='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'

# --- fetch the manifest by digest --------------------------------------------
code=$(curl -sS --max-time 60 -o "$work/manifest.json" -D "$work/head.txt" \
  -w '%{http_code}' \
  -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
  "https://ghcr.io/v2/${repo}/manifests/${digest}" 2>/dev/null)

if [ "$code" != "200" ]; then
  echo "point-tag-at-digest: GET ${digest} returned HTTP ${code:-<none>}" >&2
  exit 1
fi

# --- verify the bytes actually hash to the digest we were given ---------------
# Cheap, and it is the whole premise: if these bytes hash to the requested
# digest, PUTting them under a name cannot produce anything else.
got="sha256:$(sha256sum "$work/manifest.json" | cut -d' ' -f1)"
if [ "$got" != "$digest" ]; then
  echo "point-tag-at-digest: fetched bytes hash to ${got}, not ${digest} -- refusing" >&2
  exit 1
fi

# Re-PUT under the SAME media type. A different Content-Type is a different
# manifest as far as the digest is concerned, so this is not cosmetic.
ctype=$(tr -d '\r' < "$work/head.txt" \
  | sed -n 's/^[Cc]ontent-[Tt]ype: //p' | tail -1)
if [ -z "$ctype" ]; then
  echo "point-tag-at-digest: manifest came back with no Content-Type" >&2
  exit 1
fi

# --- write the tag -----------------------------------------------------------
put_code=$(curl -sS --max-time 60 -o "$work/put-body.txt" -D "$work/put-head.txt" \
  -w '%{http_code}' -X PUT \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: ${ctype}" \
  --data-binary "@$work/manifest.json" \
  "https://ghcr.io/v2/${repo}/manifests/${tag}" 2>/dev/null)

if [ "$put_code" != "201" ] && [ "$put_code" != "200" ]; then
  echo "point-tag-at-digest: PUT ${tag} returned HTTP ${put_code:-<none>}" >&2
  sed -n '1,20p' "$work/put-body.txt" >&2
  exit 1
fi

# The registry echoes the digest it stored. Trust that over our own arithmetic.
stored=$(tr -d '\r' < "$work/put-head.txt" \
  | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: //p' | tail -1)
if [ -n "$stored" ] && [ "$stored" != "$digest" ]; then
  echo "point-tag-at-digest: registry stored ${stored}, not ${digest}" >&2
  exit 1
fi

echo "tagged  ${image}:${tag} -> ${digest} (${ctype})"
exit 0
