#!/bin/sh
# Compile and run the pure-logic checks with the Command Line Tools toolchain.
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
cat scripts/check_*.swift > "$OUT/main.swift"
swiftc -swift-version 6 SceneStash/Data/Progress.swift SceneStash/Data/Holidays.swift SceneStash/Data/MarathonPlan.swift "$OUT/main.swift" -o "$OUT/check" && "$OUT/check"
