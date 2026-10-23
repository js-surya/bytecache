#!/usr/bin/env bash
# Sets the app version (e.g. 1.2.0) and optionally the build number for the app and all extensions,
# then regenerates the Xcode project. Usage: scripts/set-version.sh X.Y.Z [BUILD]
# A pull request that changes the version publishes a GitHub release when it's merged into main.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: scripts/set-version.sh X.Y.Z [BUILD]   (current: $(scripts/version.sh) ($(scripts/version.sh --build)))" >&2
    exit 1
fi
sed -i '' -E "s/^( *MARKETING_VERSION: )\"[^\"]*\"/\1\"$version\"/" project.yml
build="${2:-}"
if [ -n "$build" ]; then
    [[ "$build" =~ ^[0-9]+$ ]] || { echo "BUILD must be a number" >&2; exit 1; }
    sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$build\"/" project.yml
fi
xcodegen generate --quiet
echo "Version set to $version ($(scripts/version.sh --build))"
