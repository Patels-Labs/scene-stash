#!/bin/sh
# Full compile + link as a Mac Catalyst app with only the Command Line Tools.
# Catches concurrency errors that -typecheck misses, and gives a runnable local preview.
# Usage: scripts/build-catalyst.sh <output dir>   (TMDB_TOKEN env var is baked into the local Info.plist)
set -e
cd "$(dirname "$0")/.."
OUT=${1:-build}
SDK=$(xcrun --show-sdk-path)
APP="$OUT/SceneStash.app"
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -sdk "$SDK" -target arm64-apple-ios26.0-macabi \
  -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" -L "$SDK/System/iOSSupport/usr/lib" \
  -swift-version 6 -default-isolation MainActor -Onone -D DEBUG \
  $(find SceneStash -name '*.swift') -o "$APP/Contents/MacOS/SceneStash"
sed -e 's/$(PRODUCT_MODULE_NAME)/SceneStash/; s/$(MARKETING_VERSION)/1.0/; s/$(CURRENT_PROJECT_VERSION)/1/' \
  -e "s|\$(TMDB_TOKEN)|${TMDB_TOKEN}|" SceneStash/Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string SceneStash "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.heetpatel.scenestash.local "$APP/Contents/Info.plist"
plutil -replace CFBundlePackageType -string APPL "$APP/Contents/Info.plist"
codesign -s - --force "$APP"
echo "$APP"
