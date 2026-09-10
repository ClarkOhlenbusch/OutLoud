#!/usr/bin/env bash
set -euo pipefail

# Scripts/prepare-app-store-release.sh: Pre-flight checks before archiving in Xcode

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== 1. Checking Version Train ==="
./Scripts/version.sh verify

VERSION="$(./Scripts/version.sh get | grep FULL_VERSION | cut -d= -f2)"

echo ""
echo "=== 2. Running Fast Unit & Regression Tests ==="
xcodebuild -quiet \
  -project OutLoud.xcodeproj \
  -scheme OutLoud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:OutLoudTests test

echo ""
echo "=== 3. Ready for Xcode Archive ==="
echo "Version: $VERSION"
echo "Next steps in Xcode:"
echo "  1. In Xcode, select destination: 'Any iOS Device (arm64)'"
echo "  2. Go to menu: Product > Archive"
echo "  3. In Organizer window, click 'Distribute App'"
echo "  4. Select 'App Store Connect' -> 'Upload'"
echo "  5. Xcode will validate and upload build $VERSION without error 90062 / 90186!"
