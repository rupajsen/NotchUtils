#!/bin/zsh
# SPDX-License-Identifier: MIT
# Regenerates docs/images from the app's real views, filled with made-up demo data.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONS=$(mktemp -d)
swift scripts/make-icon.swift "$ICONS"
mkdir -p docs/images
cp "$ICONS/icon_256x256@2x.png" docs/images/logo.png

swift build -c release -Xswiftc -DDEMO --build-path .build-demo
.build-demo/release/NotchUtils --demo-capture docs/images

ls -la docs/images
