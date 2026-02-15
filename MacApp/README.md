# 7-Zip for Mac (Apple Silicon)

A native macOS application for 7-Zip, built with SwiftUI and optimized for Apple Silicon (M1/M2/M3/M4). Works like the Windows version with Finder right-click integration for compress/extract operations and a built-in archive browser.

## Features

- **Archive Browser** — Browse archive contents like a file manager (similar to Windows 7-Zip)
- **Right-Click Integration** — Compress and extract directly from Finder's context menu
- **Drag & Drop** — Drop files onto the app to compress, or drop archives to open
- **40+ Formats** — 7z, ZIP, RAR, TAR, GZ, BZ2, XZ, Zstandard, ISO, DMG, WIM, and more
- **Encryption** — Create password-protected 7z and ZIP archives with AES-256
- **Native Apple Silicon** — Built for ARM64 (M1/M2/M3/M4), no Rosetta needed
- **Dark Mode** — Full macOS dark mode support
- **File Type Registration** — Double-click archives to open them in 7-Zip

## Quick Start

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (install with `brew install xcodegen`)

### Build & Run

```bash
cd MacApp

# Option 1: Full setup (recommended for first time)
make setup      # Builds 7zz binary + generates Xcode project
make run        # Build and launch

# Option 2: Step by step
./Scripts/build_7zz.sh arm64    # Compile 7zz for Apple Silicon
xcodegen generate               # Generate Xcode project
open SevenZipMac.xcodeproj      # Open in Xcode, then Cmd+R to run
```

### Install Finder Right-Click Menu

Two methods are available:

**Method 1: Finder Extension (built into the app)**
1. Build and run the app
2. Go to **System Settings → Privacy & Security → Extensions → Finder Extensions**
3. Enable **7-Zip**

**Method 2: Quick Actions (standalone scripts)**
```bash
make install-qa
# Or: ./QuickActions/install-quick-actions.sh
```

## Project Structure

```
MacApp/
├── project.yml                     # XcodeGen project specification
├── Makefile                        # Build commands
├── Scripts/
│   ├── build_7zz.sh               # Compile 7zz binary for ARM64
│   ├── setup.sh                   # Full dev environment setup
│   └── generate-icons.sh          # Generate app icons
├── SevenZipMac/                    # Main app target
│   ├── App/
│   │   ├── SevenZipApp.swift       # App entry point
│   │   └── AppDelegate.swift       # File handling + Services
│   ├── Models/
│   │   ├── ArchiveItem.swift       # Data models
│   │   └── ArchiveManager.swift    # 7zz CLI wrapper
│   ├── Views/
│   │   ├── MainWindow.swift        # Archive browser UI
│   │   ├── CompressView.swift      # Compression dialog
│   │   ├── ExtractView.swift       # Extraction dialog
│   │   └── SettingsView.swift      # App preferences
│   ├── Services/
│   │   └── ServiceProvider.swift   # macOS Services handler
│   ├── Resources/
│   │   ├── Info.plist              # App configuration + UTIs
│   │   └── Assets.xcassets/        # Icons and colors
│   └── Entitlements/
│       └── SevenZipMac.entitlements
├── FinderExtension/                # Finder Sync Extension
│   ├── FinderSync.swift            # Right-click menu handler
│   ├── Info.plist
│   └── FinderExtension.entitlements
└── QuickActions/                   # Standalone shell-based Quick Actions
    ├── compress-with-7zip.sh
    ├── extract-with-7zip.sh
    └── install-quick-actions.sh
```

## How It Works

### Architecture

The app wraps the `7zz` command-line binary (compiled natively for ARM64) with a SwiftUI interface:

```
┌─────────────────────────────────────────────┐
│  SwiftUI App (MainWindow / CompressView)    │
│                    │                        │
│          ArchiveManager.swift               │
│            (async Swift wrapper)            │
│                    │                        │
│              7zz binary                     │
│         (bundled in Resources)              │
└─────────────────────────────────────────────┘
```

### Finder Integration

The right-click menu works through two mechanisms:

1. **Finder Sync Extension** — An `appex` plugin that adds context menu items directly in Finder. Supports compress-to-format submenus, extract-here, extract-to-subfolder, open-in-app, and test-archive operations.

2. **macOS Services** — Registered via `Info.plist` `NSServices`, these appear in Finder's Quick Actions/Services menu. The `ServiceProvider` class handles the compress and extract actions.

### Supported Formats

| Operation | Formats |
|-----------|---------|
| **Compress** | 7z, ZIP, TAR, GZip, BZip2, XZ, WIM, Zstandard |
| **Extract** | 7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, WIM, CAB, ARJ, LZH, RPM, DEB, CPIO, VHD, VMDK, QCOW2, and 30+ more |

## Make Targets

| Command | Description |
|---------|-------------|
| `make setup` | First-time setup (build 7zz + generate Xcode project) |
| `make build-7zz` | Build the 7zz binary for ARM64 |
| `make generate` | Generate Xcode project from project.yml |
| `make build` | Build the app |
| `make run` | Build and launch the app |
| `make archive` | Create a release build |
| `make install-qa` | Install Finder Quick Actions |
| `make clean` | Clean build artifacts |

## Building a Universal Binary

To create a binary that runs on both Intel and Apple Silicon Macs:

```bash
./Scripts/build_7zz.sh universal
```

## License

The macOS app wrapper is provided under the same license as 7-Zip (GNU LGPL).
See the [DOC/License.txt](../DOC/License.txt) file for full details.

7-Zip is Copyright (C) Igor Pavlov.
