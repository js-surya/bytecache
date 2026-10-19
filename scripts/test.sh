#!/usr/bin/env bash
# Runs package tests, then builds the app for iOS Simulator and macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --package-path Packages/ByteCacheKit
xcodegen generate --quiet
xcodebuild -scheme ByteCache -destination 'generic/platform=iOS Simulator' build -quiet
xcodebuild -scheme ByteCache -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO -quiet
echo "All green."
