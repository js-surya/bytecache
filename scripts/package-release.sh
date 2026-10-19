#!/usr/bin/env bash
# Builds unsigned release files into dist/:
#   ByteCache-<version>-iOS.ipa    universal: iPhone and iPad (sideload, e.g. with Sideloadly or AltStore)
#   ByteCache-<version>-macOS.zip  the Mac app, ad-hoc signed (right-click → Open the first time)
# Usage: scripts/package-release.sh [build number]
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(scripts/version.sh)"
build="${1:-1}"
dist="dist"
derived="build/release"
rm -rf "$dist" "$derived"
mkdir -p "$dist"

common=(CURRENT_PROJECT_VERSION="$build" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")

echo "▸ iOS (iPhone + iPad) $version ($build)"
xcodebuild -scheme ByteCache -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived/ios" "${common[@]}" build -quiet
payload="$derived/ipa/Payload"
mkdir -p "$payload"
cp -R "$derived/ios/Build/Products/Release-iphoneos/ByteCache.app" "$payload/"
(cd "$derived/ipa" && zip -qry "../../../$dist/ByteCache-$version-iOS.ipa" Payload)

echo "▸ macOS $version ($build)"
xcodebuild -scheme ByteCache -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived/mac" "${common[@]}" build -quiet
app="$derived/mac/Build/Products/Release/ByteCache.app"
# Apple silicon refuses unsigned code: ad-hoc sign the extensions, then the app.
find "$app/Contents/PlugIns" -name "*.appex" -maxdepth 1 -exec codesign --force --sign - {} \; 2>/dev/null || true
codesign --force --sign - "$app"
ditto -c -k --keepParent "$app" "$dist/ByteCache-$version-macOS.zip"

(cd "$dist" && shasum -a 256 ./* > SHA256SUMS.txt)
ls -lh "$dist"
