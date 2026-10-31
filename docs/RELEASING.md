# Releasing NotchUtils

Releases are built by GitHub Actions, so every DMG comes from a clean checkout of a tagged commit.

## Cut a release

1. Make sure everything you want to ship is on `main` and the **CI** workflow is green.
2. Add a section for the new version at the top of `CHANGELOG.md`:

   ```markdown
   ## [1.1.0] - 2026-12-01

   ### Added

   - Something great.
   ```

   Those notes become the GitHub release notes, so write them for users.
3. Run the release script:

   ```bash
   ./scripts/release.sh 1.1.0
   ```

   It checks that you're on `main` with a clean tree and a changelog entry, updates `VERSION`, commits, tags `v1.1.0` and pushes.
4. Watch the **Release** workflow on the [Actions page](https://github.com/rupajsen/NotchUtils/actions). It checks that the tag matches `VERSION`, builds the DMG and publishes a release with the DMG and its checksum.
5. Install the DMG from the release page and give it a quick try:
   - Hover opens and closes the notch.
   - Now Playing shows and controls your music.
   - A file can be dragged onto the Shelf and back out.
   - Fan control sets up, works in Manual and Max, and the helper can be removed.
   - If `FanHelper.version` changed, an existing helper is offered an update.
   - Credits shows the new version.

Pick version numbers using [Semantic Versioning](https://semver.org): bug fixes bump the last number, new features the middle one and breaking changes the first.

## Try a build locally

```bash
./scripts/make-dmg.sh
```

This writes `dist/NotchUtils-<version>.dmg` and its checksum.

## If a release goes wrong

Published releases are public, so prefer shipping a fixed version. If a build fails before anything is published, fix the problem on `main`, delete the tag and run the script again with the same version:

```bash
git push --delete origin v1.1.0
git tag -d v1.1.0
```

## Update the images

If the interface changed, regenerate the README images with `./scripts/render-demo.sh` and commit them. Don't use real screenshots that show your own music or files.

## Notarization (not set up yet)

Builds are ad hoc signed, so macOS warns people the first time they open the app. Removing the warning requires a paid [Apple Developer Program](https://developer.apple.com/programs/) membership. To set it up:

1. Create a **Developer ID Application** certificate.
2. Set `SIGN_IDENTITY` to that certificate when running `scripts/build.sh`, and add `--options runtime` to its `codesign` call. Test Now Playing afterwards, since the hardened runtime can affect controlling other apps.
3. Submit the DMG with `xcrun notarytool submit --wait`, then run `xcrun stapler staple` on it.
4. Store the certificate and credentials as GitHub Actions secrets and add these steps to `.github/workflows/release.yml`.
