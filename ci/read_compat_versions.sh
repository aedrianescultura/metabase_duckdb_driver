#!/usr/bin/env bash
# Read metabase_versions.json and the Dockerfile's pinned Metabase version, and
# emit them as GitHub Actions step outputs:
#
#   versions -> compact JSON array, consumed by a job matrix via fromJSON()
#   primary  -> the single version that also receives the :latest tag
#   driver   -> the driver version shared by deps.edn and the Dockerfile
#
set -euo pipefail

file="${VERSIONS_FILE:-metabase_versions.json}"
dockerfile="${DOCKERFILE:-Dockerfile}"
deps_file="${DEPS_FILE:-deps.edn}"
release_tag="${RELEASE_TAG:-}"

die() { echo "::error::$1"; exit 1; }

[ -f "$file" ] || die "$file not found"
jq -e . "$file" >/dev/null 2>&1 || die "$file is not valid JSON"
jq -e 'type == "array"' "$file" >/dev/null \
  || die "$file must be a JSON array of Metabase versions, e.g. [\"0.63.10\"]"

count="$(jq -r 'length' "$file")"
[ "$count" -gt 0 ] || die "$file is empty; this release would publish no images"

jq -e 'all(type == "string")' "$file" >/dev/null \
  || die "$file must contain only strings"

jq -e 'all(test("^[0-9]+(\\.[0-9]+)+$"))' "$file" >/dev/null \
  || die "$file contains an invalid version; expected numeric dot-separated versions such as 0.63.10"

jq -e '(length) == (unique | length)' "$file" >/dev/null \
  || die "$file contains duplicate versions; two matrix jobs would race the same image tag and both would push :latest"

versions="$(jq -c . "$file")"

[ -f "$dockerfile" ] || die "$dockerfile not found"

# Exactly one, or the sed below would emit a multi-line value and corrupt the
# step output.
arg_lines="$(grep -c '^ARG METABASE_VERSION=' "$dockerfile" || true)"
[ "$arg_lines" -eq 1 ] \
  || die "expected exactly one 'ARG METABASE_VERSION=' line in $dockerfile, found $arg_lines"

# CRLF line endings would otherwise leave a trailing \r on primary, which
# makes the membership check below fail while naming a version that visibly
# IS in the file.
primary="$(sed -n 's/^ARG METABASE_VERSION=//p' "$dockerfile" | tr -d '\r')"
[ -n "$primary" ] \
  || die "Could not read 'ARG METABASE_VERSION=' from $dockerfile -- did the line move or get renamed?"
[[ "$primary" =~ ^[0-9]+(\.[0-9]+)+$ ]] \
  || die "$dockerfile pins an invalid Metabase version: $primary"

# index() returns null when absent, and 0 when the match is first. jq -e fails
# only on false/null, so a primary at index 0 correctly passes.
jq -e --arg v "$primary" 'index($v)' "$file" >/dev/null \
  || die "$dockerfile pins ARG METABASE_VERSION=$primary, which is not listed in $file; :latest would point at a version we do not claim compatibility with"

# The driver's own version (deps.edn) and the version of the driver jar the
# image bundles (Dockerfile) are two independent sources of truth for the same
# number. A rebase, a half-finished bump, or an out-of-order merge can let them
# drift apart silently -- catch that here instead of shipping an image whose
# plugin jar doesn't match what the rest of the build claims it is.
[ -f "$deps_file" ] || die "$deps_file not found"

deps_driver_version="$(sed -n 's/.*org\.duckdb\/duckdb_jdbc[[:space:]]*{:mvn\/version[[:space:]]*"\([^"]*\)".*/\1/p' "$deps_file")"
[ -n "$deps_driver_version" ] \
  || die "Could not read org.duckdb/duckdb_jdbc's :mvn/version from $deps_file -- is it missing, renamed, or unparseable?"

dockerfile_driver_version="$(sed -n 's/^ARG METABASE_DUCKDB_DRIVER_VERSION=//p' "$dockerfile" | tr -d '\r')"
[ -n "$dockerfile_driver_version" ] \
  || die "Could not read 'ARG METABASE_DUCKDB_DRIVER_VERSION=' from $dockerfile -- did the line move or get renamed?"
[[ "$dockerfile_driver_version" =~ ^[0-9]+(\.[0-9]+)+$ ]] \
  || die "$dockerfile pins an invalid driver version: $dockerfile_driver_version"

[ "$deps_driver_version" = "$dockerfile_driver_version" ] \
  || die "$deps_file pins org.duckdb/duckdb_jdbc :mvn/version $deps_driver_version but $dockerfile pins ARG METABASE_DUCKDB_DRIVER_VERSION=$dockerfile_driver_version -- the driver's declared version and the version its own image bundles must match"

if [ -n "$release_tag" ] && [ "$release_tag" != "$dockerfile_driver_version" ]; then
  die "release tag $release_tag does not match driver version $dockerfile_driver_version"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "versions=$versions"
    echo "primary=$primary"
    echo "driver=$dockerfile_driver_version"
  } >> "$GITHUB_OUTPUT"
fi

echo "Compatible Metabase versions: $versions (primary: $primary)"
