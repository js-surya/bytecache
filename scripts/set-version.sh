#!/usr/bin/env bash
# Sets the app version (e.g. 1.2.0) for the app and all extensions, then regenerates the Xcode project.
# A pull request that changes the version publishes a GitHub release when it's merged into main.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: scripts/set-version.sh X.Y.Z   (current: $(scripts/version.sh))" >&2
    exit 1
fi
sed -i '' -E "s/^( *MARKETING_VERSION: )\"[^\"]*\"/\1\"$version\"/" project.yml
xcodegen generate --quiet
echo "Version set to $version"
