#!/bin/zsh
# SPDX-License-Identifier: MIT
# Builds dist/NotchUtils-<version>.dmg and its SHA-256 checksum.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
DMG="dist/NotchUtils-$VERSION.dmg"

scripts/build.sh

STAGE=$(mktemp -d)
cp -R dist/NotchUtils.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp LICENSE "$STAGE/LICENSE.txt"

rm -f "$DMG" "$DMG.sha256"
# hdiutil occasionally reports "resource busy" on CI machines, so give it a few tries.
for attempt in 1 2 3; do
    if hdiutil create -volname "NotchUtils $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG"; then
        break
    fi
    [[ $attempt == 3 ]] && exit 1
    sleep 5
done
hdiutil verify "$DMG"

(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
cat "$DMG.sha256"
