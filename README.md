# SeptaZip

A native macOS app for [7-Zip](https://7-zip.org), built with SwiftUI for Apple Silicon and Intel Macs. **SeptaZip** (Sept = seven in Latin) provides Finder right-click integration, an archive browser, and support for 40+ archive formats.

SeptaZip is powered by the official upstream 7-Zip source maintained by Igor Pavlov and the [ip7z/7zip](https://github.com/ip7z/7zip) repository.

## Download

Grab the latest DMG from the [Releases](../../releases) page, open it, and drag **SeptaZip** into your Applications folder.

## Features

- Browse archive contents like a file manager
- Compress and extract from Finder's right-click menu
- Drag & drop files to compress or archives to open
- 40+ formats: 7z, ZIP, RAR, TAR, GZ, XZ, Zstandard, ISO, DMG, and more
- AES-256 encrypted 7z and ZIP archives
- Native ARM64 and Intel (universal binary) support
- macOS dark mode

## Build from Source

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Quick Start

```bash
cd MacApp
make setup      # Compile 7zz + generate Xcode project
make run        # Build and launch the app
```

### Step by Step

```bash
cd MacApp

# 1. Build the 7zz binary
make build-7zz

# 2. Generate Xcode project
make generate

# 3. Build and run
make build
make run

# Or open in Xcode directly
open SeptaZip.xcodeproj
```

### Create a DMG for Distribution

```bash
cd MacApp
make dmg        # Builds release archive, then packages into a DMG
```

The DMG will be at `MacApp/build/SeptaZip-<version>.dmg`.

**Fixing "Damaged DMG" errors:** macOS adds quarantine attributes that trigger Gatekeeper warnings. Remove them with:
```bash
xattr -d com.apple.quarantine build/SeptaZip-*.dmg
```

### Publishing a Release

1. Build the DMG:
   ```bash
   cd MacApp && make dmg
   ```

2. Remove Gatekeeper quarantine from the DMG:
   ```bash
   xattr -d com.apple.quarantine build/SeptaZip-*.dmg
   ```

3. Create a GitHub release:
   ```bash
   gh release create v26.00 build/SeptaZip-26.0.dmg \
     --title "SeptaZip v26.00" \
     --notes "Native macOS app for 7-Zip compression."
   ```

## Make Targets

Run these from the `MacApp/` directory:

| Command | Description |
|---------|-------------|
| `make setup` | First-time setup (build 7zz + generate Xcode project) |
| `make build-7zz` | Compile the 7zz binary for ARM64 |
| `make generate` | Generate Xcode project from project.yml |
| `make build` | Build the app (Debug) |
| `make build-release` | Build the app (Release) |
| `make run` | Build and launch |
| `make archive` | Create .xcarchive for signing/notarization |
| `make dmg` | Create DMG installer |
| `make install-qa` | Install Finder Quick Actions |
| `make clean` | Clean all build artifacts |

## Universal Binary (Intel + Apple Silicon)

```bash
cd MacApp
./Scripts/build_7zz.sh universal
```

## Project Layout

```
MacApp/
  project.yml                   # XcodeGen spec (generates .xcodeproj)
  Makefile                      # Build commands
  Scripts/
    build_7zz.sh                # Compile 7zz from source
    create_dmg.sh               # Package .app into DMG
    setup.sh                    # Dev environment setup
    generate-septazip-icon.sh   # Generate SeptaZip app icon
  SevenZipMac/                  # Main app (SwiftUI)
  FinderExtension/              # Finder right-click menu plugin
  QuickActions/                 # Standalone Finder Quick Actions

source_code/7zip/
  Asm/ C/ CPP/ DOC/             # Upstream 7-Zip source tree
```

## Updating 7-Zip Source (Fork Sync)

To keep this fork easy to combine with future 7-Zip source updates:

```bash
# one-time
git remote add upstream https://github.com/ip7z/7zip.git

# each update
git fetch upstream --tags
./source_code/sync_7zip_source.sh upstream/main
```

Then rebuild from `MacApp/`:

```bash
cd MacApp
make build-7zz
```

## Upstream Credit

- Core engine: [7-Zip](https://7-zip.org) by Igor Pavlov
- Official upstream source: [ip7z/7zip](https://github.com/ip7z/7zip)
- SeptaZip only provides the native macOS app, Finder integration, packaging, and UI around that official engine

## Generating the App Icon

To regenerate the SeptaZip icon:

```bash
cd MacApp
./Scripts/generate-septazip-icon.sh
```

This creates a modern macOS squircle icon with a warm sunset gradient, a dark inset plate, and a stylized '7' zipper mark.

## License

7-Zip is Copyright (C) Igor Pavlov, licensed under the GNU LGPL.
See [source_code/7zip/DOC/License.txt](source_code/7zip/DOC/License.txt) for details.

**SeptaZip** is a macOS wrapper/frontend around the official 7-Zip source and follows the same license.
