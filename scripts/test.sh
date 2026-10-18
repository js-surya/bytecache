#!/usr/bin/env bash
# Runs package tests, then builds the app for iOS Simulator and macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --package-path Packages/ByteCatchKit
xcodegen generate --quiet
xcodebuild -scheme ByteCatch -destination 'generic/platform=iOS Simulator' build -quiet
xcodebuild -scheme ByteCatch -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO -quiet
echo "All green."
