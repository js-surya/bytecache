#!/usr/bin/env bash
# Builds unsigned release files into dist/:
#   ByteCache-<version>-iOS.ipa    universal: iPhone and iPad, ad-hoc signed with its App Group (sideload,
#                                  e.g. with AltStore, SideStore or Sideloadly)
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

# TIP_LINKS: GitHub builds include the Ko-fi link; App Store archives never set it (guideline 3.1.1).
common=(CURRENT_PROJECT_VERSION="$build" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) TIP_LINKS')

echo "▸ iOS (iPhone + iPad) $version ($build)"
xcodebuild -scheme ByteCache -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived/ios" "${common[@]}" build -quiet
payload="$derived/ipa/Payload"
mkdir -p "$payload"
cp -R "$derived/ios/Build/Products/Release-iphoneos/ByteCache.app" "$payload/"
# Ad-hoc sign with the App Group entitlement (frameworks, then extensions, then the app). Sideloading
# tools re-sign the app and only set up the App Groups its binaries declare; without one the widget
# can't see the app's snippets. iCloud and keychain groups need a real team, so the installer adds those.
ios_app="$payload/ByteCache.app"
entitlements="$derived/ios-app-group.entitlements"
cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array><string>group.me.suryajs.bytecache</string></array>
</dict>
</plist>
PLIST
plutil -lint -s "$entitlements"
find "$ios_app/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -exec codesign --force --sign - {} \; 2>/dev/null || true
for appex in "$ios_app"/PlugIns/*.appex; do
    codesign --force --sign - --entitlements "$entitlements" "$appex"
done
codesign --force --sign - --entitlements "$entitlements" "$ios_app"
for bundle in "$ios_app" "$ios_app"/PlugIns/*.appex; do
    signed="$(codesign -d --entitlements - "$bundle" 2>/dev/null || true)"
    [[ "$signed" == *group.me.suryajs.bytecache* ]] || { echo "error: $bundle has no App Group entitlement" >&2; exit 1; }
done
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
