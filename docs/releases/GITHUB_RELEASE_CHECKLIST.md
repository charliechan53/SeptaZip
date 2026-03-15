# GitHub Release Checklist

Use this flow when publishing SeptaZip outside the Mac App Store.

## Before releasing

1. Confirm `main` contains the intended app changes.
2. Build the current release DMG from `MacApp/`.
3. Generate a SHA-256 checksum for the DMG.
4. Smoke-test the DMG on a clean install path.
5. Tag the release commit.
6. Push `main` and the tag.
7. Create a GitHub Release and upload the DMG plus checksum.

## Build artifacts

```bash
cd MacApp
make dmg
shasum -a 256 build/SeptaZip-1.0.dmg > build/SeptaZip-1.0.dmg.sha256
```

Adjust the filename if the app version changes.

## Smoke test

Check:
- the DMG opens
- the app icon appears correctly
- the app launches
- opening a ZIP shows the archive browser instead of hanging
- Finder Extension can be enabled
- Finder right-click menu appears after enabling the extension

## Tag and push

```bash
git checkout main
git pull --ff-only
git tag -a v1.0.0 -m "SeptaZip v1.0.0"
git push origin main
git push origin v1.0.0
```

## Create the GitHub release

```bash
gh release create v1.0.0 \
  MacApp/build/SeptaZip-1.0.dmg \
  MacApp/build/SeptaZip-1.0.dmg.sha256 \
  --title "SeptaZip v1.0.0" \
  --notes-file docs/releases/RELEASE_NOTES_TEMPLATE.md
```

If you want to edit the notes before publishing, create the release as a draft:

```bash
gh release create v1.0.0 \
  MacApp/build/SeptaZip-1.0.dmg \
  MacApp/build/SeptaZip-1.0.dmg.sha256 \
  --title "SeptaZip v1.0.0" \
  --notes-file docs/releases/RELEASE_NOTES_TEMPLATE.md \
  --draft
```

## What to mention in the release notes

- direct-download DMG for macOS
- minimum supported macOS version
- main archive features
- Finder integration
- powered by the official 7-Zip engine
- not Mac App Store distributed
- if not notarized, mention the first-launch Gatekeeper warning and `Open Anyway`

## Suggested attached assets

- `SeptaZip-<version>.dmg`
- `SeptaZip-<version>.dmg.sha256`
- screenshots for the release page if helpful

## Post-release checks

1. Open the GitHub release page in a browser.
2. Download the DMG from the release page.
3. Verify the checksum file matches the downloaded DMG.
4. Confirm install instructions are clear.
5. Confirm the README still links users to Releases.
