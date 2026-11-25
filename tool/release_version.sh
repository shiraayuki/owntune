#!/usr/bin/env bash
# Prints "<build-name> <build-number>" for a release tag, used by the iOS,
# Android and Release workflows so both platforms get the same numbers:
#   tool/release_version.sh v0.8.2   →   0.8.2 802
# The build number is major*10000 + minor*100 + patch, so it grows with
# every release (minor and patch must stay below 100).
set -euo pipefail

tag=${1:?usage: tool/release_version.sh vX.Y.Z}
if [[ ! "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "not a vX.Y.Z tag: $tag" >&2
  exit 1
fi
major=$((10#${BASH_REMATCH[1]}))
minor=$((10#${BASH_REMATCH[2]}))
patch=$((10#${BASH_REMATCH[3]}))
if ((minor > 99 || patch > 99)); then
  echo "minor and patch must be below 100: $tag" >&2
  exit 1
fi
echo "$major.$minor.$patch $((major * 10000 + minor * 100 + patch))"
