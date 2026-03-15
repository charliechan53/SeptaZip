# SeptaZip Security Review

Date: 2026-03-15

Scope:
- `MacApp/SevenZipMac`
- `MacApp/FinderExtension`
- `MacApp/QuickActions`

## Findings

### High: archive passwords are exposed on the `7zz` command line

Affected code:
- `MacApp/SevenZipMac/Models/ArchiveManager.swift`

Current behavior:
- Passwords are passed as `-p<password>` arguments to `7zz` for list, extract, compress, and test operations.

Risk:
- Other local processes can inspect process arguments while the command is running.
- This is a confidentiality issue for encrypted archives.

Status:
- Not fully remediated in this branch because upstream `7zz` primarily exposes password input as a command-line switch.

Recommended follow-up:
- Investigate whether the current 7-Zip console supports a secure non-argument password path for macOS builds.
- If not, document this limitation clearly in the UI and avoid presenting archive-password handling as high-security storage.

### High: app and Finder extension are not App Sandbox-enabled

Affected files:
- `MacApp/SevenZipMac/Entitlements/SevenZipMac.entitlements`
- `MacApp/FinderExtension/FinderExtension.entitlements`

Current behavior:
- Both entitlements files are empty.

Risk:
- The app is broader in privilege than a Mac App Store build should be.
- The current project is not ready for Mac App Store submission.

Recommended follow-up:
- Enable App Sandbox for the main app and Finder extension.
- Audit every file-access path and migrate to user-selected access and any required security-scoped bookmark flow.
- Re-test Finder integration under sandboxed conditions.

### Medium: external `7zz` fallbacks could execute an untrusted local binary

Affected code:
- `MacApp/SevenZipMac/Models/ArchiveManager.swift`
- `MacApp/FinderExtension/FinderSync.swift`
- `MacApp/QuickActions/compress-with-7zip.sh`
- `MacApp/QuickActions/extract-with-7zip.sh`

Previous behavior:
- If the bundled `7zz` was missing, the app and helpers would fall back to binaries in `/usr/local/bin`, `/opt/homebrew/bin`, or `~/.local/bin`.

Risk:
- A tampered local binary could be executed instead of the shipped engine.

Mitigation in this branch:
- Production behavior now prefers the bundled app resource by default.
- External fallbacks now require explicit opt-in via `SEPTAZIP_ALLOW_EXTERNAL_7ZZ=1` or debug builds.

### Medium: Finder Sync monitors the filesystem root

Affected code:
- `MacApp/FinderExtension/FinderSync.swift`

Current behavior:
- `FIFinderSyncController.default().directoryURLs` is set to `/` so the extension can show context menus everywhere.

Risk:
- This is a broad scope choice and should be reviewed against least-privilege expectations, especially for App Store distribution.

Recommended follow-up:
- Validate whether this scope remains necessary once sandboxing is enabled.
- If Apple review or runtime behavior pushes back, narrow monitored locations or adjust the product strategy.

## Additional notes

- The app does not download code or update the 7-Zip engine at runtime.
- The engine is built from vendored source in `source_code/7zip` and bundled into the app.
- The app now prefers its bundled `7zz` binary in production, which is materially safer than the previous fallback behavior.

## Suggested next security pass

1. Confirm whether `7zz` has a secure password input mechanism on macOS that avoids process arguments.
2. Add App Sandbox entitlements and retest open/compress/extract/Finder flows.
3. Review any future preview feature carefully before extracting files to temporary locations.
