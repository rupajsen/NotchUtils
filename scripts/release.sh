#!/bin/zsh
# SPDX-License-Identifier: MIT
# Cuts a release: ./scripts/release.sh 1.1.0
# Bumps VERSION, commits, tags and pushes. The tag makes GitHub Actions build and publish the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version>, e.g. 1.1.0}

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "Version must look like 1.2.3"; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main"; exit 1; }
grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "Add a '## [$VERSION]' section to CHANGELOG.md first"; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "v$VERSION already exists"; exit 1; }

echo "$VERSION" > VERSION
git add VERSION CHANGELOG.md
git diff --cached --quiet || git commit -m "Release $VERSION"
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree has other changes; commit them first"; exit 1; }

git tag -a "v$VERSION" -m "NotchUtils $VERSION"
git push origin main "v$VERSION"
echo "Pushed v$VERSION. Follow the build at https://github.com/rupajsen/NotchUtils/actions"
