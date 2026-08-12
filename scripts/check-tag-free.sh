#!/usr/bin/env bash
# Is this tag free to publish?  Usage: check-tag-free.sh <image> <tag>
#
#   exit 0   free      - the registry answered 404
#   exit 10  taken     - the registry answered 200
#   exit 1   unknown   - anything else, INCLUDING auth, rate-limit and network
#                        failures. The caller must treat this as "do not push".
#
# WHY NOT `docker manifest inspect`
# --------------------------------
# It exits non-zero for "not found", for an auth failure, for a rate limit and
# for a dropped connection, with no way to tell them apart. A guard built on it
# is fail-OPEN: the one time the registry is unreachable, it reports the tag as
# free and the publish moves a tag that something has already recorded. That
# failure is invisible until someone tries to reproduce a measurement and gets
# different bytes, which is the exact outcome the immutable-tag policy exists to
# prevent. So this asks the registry directly and branches on the status code.
set -uo pipefail

image="${1:?usage: check-tag-free.sh <image> <tag>}"
tag="${2:?usage: check-tag-free.sh <image> <tag>}"

# ghcr.io/owner/name -> owner/name
repo="${image#ghcr.io/}"

# A token is required even for anonymous pulls of a public package. When
# GITHUB_TOKEN is present it is used, so this also works for a private package.
auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-u "x:${GITHUB_TOKEN}")

token=$(curl -sS --max-time 30 "${auth[@]}" \
  "https://ghcr.io/token?scope=repository:${repo}:pull&service=ghcr.io" 2>/dev/null \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("token",""))' 2>/dev/null)

if [ -z "$token" ]; then
  echo "check-tag-free: could not obtain a registry token for ${repo}" >&2
  exit 1
fi

code=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' -I \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
  "https://ghcr.io/v2/${repo}/manifests/${tag}" 2>/dev/null)

case "$code" in
  200) echo "taken   ${image}:${tag}"; exit 10 ;;
  404) echo "free    ${image}:${tag}"; exit 0 ;;
  *)   echo "check-tag-free: registry returned HTTP ${code:-<none>} for ${image}:${tag};" \
            "cannot determine whether the tag exists, so refusing to treat it as free" >&2
       exit 1 ;;
esac
