#!/bin/sh
# Typecheck the app against Mac Catalyst UIKit from the Command Line Tools (no Xcode needed).
cd "$(dirname "$0")/.."
SDK=$(xcrun --show-sdk-path)
exec swiftc -typecheck -sdk "$SDK" -target arm64-apple-ios26.0-macabi \
  -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" \
  -swift-version 6 -default-isolation MainActor \
  $(find SceneStash -name '*.swift')
