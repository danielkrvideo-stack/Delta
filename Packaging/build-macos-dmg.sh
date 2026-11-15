#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "${DELTA_APP_ALREADY_BUILT:-false}" != "true" ]]; then
  bash ./build-app.sh
fi
VERSION="${DELTA_VERSION:-0.1.0}"
DMG="Delta-macos-intel-${VERSION}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R Delta.app "$STAGING/Delta.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Delta" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
printf 'Created %s\n' "$DMG"
