#!/usr/bin/env bash
# Read metabase_versions.json and the Dockerfile's pinned Metabase version, and
# emit them as GitHub Actions step outputs:
#
#   versions -> compact JSON array, consumed by a job matrix via fromJSON()
#   primary  -> the single version that also receives the :latest tag
#   driver   -> the driver version shared by deps.edn and the Dockerfile
#
set -euo pipefail

file=metabase_versions.json
dockerfile=Dockerfile
deps_file=deps.edn
release_tag="${RELEASE_TAG:-}"

die() { echo "::error::$1"; exit 1; }

[ -f "$file" ] || die "$file not found"
jq -e . "$file" >/dev/null 2>&1 || die "$file is not valid JSON"
jq -e 'type == "array"' "$file" >/dev/null \
  || die "$file must be a JSON array of Metabase versions, e.g. [\"0.63.10\"]"

versions="$(jq -c . "$file")"

[ -f "$dockerfile" ] || die "$dockerfile not found"

primary="$(sed -n 's/^ARG METABASE_VERSION=//p' "$dockerfile" | tr -d '\r')"

jq -e --arg v "$primary" 'index($v)' "$file" >/dev/null \
  || die "$dockerfile pins ARG METABASE_VERSION=$primary, which is not listed in $file; :latest would point at a version we do not claim compatibility with"

[ -f "$deps_file" ] || die "$deps_file not found"

deps_driver_version="$(sed -n 's/.*org\.duckdb\/duckdb_jdbc[[:space:]]*{:mvn\/version[[:space:]]*"\([^"]*\)".*/\1/p' "$deps_file")"
[ -n "$deps_driver_version" ] \
  || die "Could not read org.duckdb/duckdb_jdbc's :mvn/version from $deps_file -- is it missing, renamed, or unparseable?"

dockerfile_driver_version="$(sed -n 's/^ARG METABASE_DUCKDB_DRIVER_VERSION=//p' "$dockerfile" | tr -d '\r')"

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
