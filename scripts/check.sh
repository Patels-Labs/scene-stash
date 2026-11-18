#!/bin/sh
# Compile and run the pure-logic checks with the Command Line Tools toolchain.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
cat scripts/check_*.swift > "$OUT/main.swift"
swiftc -swift-version 6 SceneStash/Data/Progress.swift SceneStash/Data/Holidays.swift SceneStash/Data/MarathonPlan.swift SceneStash/Data/NightStatus.swift SceneStash/Data/TimeFit.swift SceneStash/Data/Passport.swift "$OUT/main.swift" -o "$OUT/check" && "$OUT/check"
mkdir "$OUT/tmdb" && cp scripts/tmdb_check.swift "$OUT/tmdb/main.swift"
swiftc -swift-version 6 -default-isolation MainActor SceneStash/Data/TMDB.swift "$OUT/tmdb/main.swift" -o "$OUT/tmdb/check" && "$OUT/tmdb/check"
