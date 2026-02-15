import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    override init() {
        super.init()
        // Monitor all directories - the extension will show context menus everywhere
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - Context Menu for selected items

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }

        let menu = NSMenu(title: "7-Zip")
        let selectedItems = FIFinderSyncController.default().selectedItemURLs() ?? []

        if selectedItems.isEmpty { return nil }

        let hasArchives = selectedItems.contains { isArchiveFile($0) }
        let hasNonArchives = selectedItems.contains { !isArchiveFile($0) }

        // If archives are selected, show extraction options
        if hasArchives {
            let extractHere = NSMenuItem(
                title: "Extract Here",
                action: #selector(extractHere(_:)),
                keyEquivalent: ""
            )
            extractHere.image = NSImage(systemSymbolName: "arrow.down.doc",
                                         accessibilityDescription: "Extract")
            menu.addItem(extractHere)

            let extractTo = NSMenuItem(
                title: "Extract to Subfolder",
                action: #selector(extractToSubfolder(_:)),
                keyEquivalent: ""
            )
            extractTo.image = NSImage(systemSymbolName: "folder.badge.plus",
                                       accessibilityDescription: "Extract to folder")
            menu.addItem(extractTo)

            let extractChoose = NSMenuItem(
                title: "Extract to...",
                action: #selector(extractToChosen(_:)),
                keyEquivalent: ""
            )
            menu.addItem(extractChoose)

            let openWith = NSMenuItem(
                title: "Open with 7-Zip",
                action: #selector(openInApp(_:)),
                keyEquivalent: ""
            )
            openWith.image = NSImage(systemSymbolName: "doc.zipper",
                                      accessibilityDescription: "Open")
            menu.addItem(openWith)

            let testItem = NSMenuItem(
                title: "Test Archive",
                action: #selector(testArchive(_:)),
                keyEquivalent: ""
            )
            testItem.image = NSImage(systemSymbolName: "checkmark.shield",
                                      accessibilityDescription: "Test")
            menu.addItem(testItem)
        }

        // If non-archive files are selected, show compression options
        if hasNonArchives || !hasArchives {
            if hasArchives { menu.addItem(.separator()) }

            // Compress submenu
            let compressMenu = NSMenu()

            let formats: [(String, String)] = [
                ("7z", "Compress to .7z"),
                ("zip", "Compress to .zip"),
                ("tar.gz", "Compress to .tar.gz"),
                ("tar.xz", "Compress to .tar.xz"),
                ("tar.zst", "Compress to .tar.zst"),
            ]

            for (tag, title) in formats.enumerated() {
                let item = NSMenuItem(
                    title: title.1,
                    action: #selector(compressAs(_:)),
                    keyEquivalent: ""
                )
                item.tag = tag
                item.representedObject = title.0
                compressMenu.addItem(item)
            }

            compressMenu.addItem(.separator())

            let compressCustom = NSMenuItem(
                title: "Compress with Options...",
                action: #selector(compressWithOptions(_:)),
                keyEquivalent: ""
            )
            compressMenu.addItem(compressCustom)

            let compressItem = NSMenuItem(
                title: "Compress with 7-Zip",
                action: nil,
                keyEquivalent: ""
            )
            compressItem.submenu = compressMenu
            compressItem.image = NSImage(systemSymbolName: "arrow.up.doc",
                                          accessibilityDescription: "Compress")
            menu.addItem(compressItem)
        }

        return menu
    }

    // MARK: - Actions

    @objc func extractHere(_ sender: NSMenuItem) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in urls where isArchiveFile(url) {
            let dir = url.deletingLastPathComponent().path
            run7zz(args: ["x", "-o\(dir)", "-aoa", url.path])
        }
    }

    @objc func extractToSubfolder(_ sender: NSMenuItem) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in urls where isArchiveFile(url) {
            let dir = url.deletingLastPathComponent().path
            let name = url.deletingPathExtension().lastPathComponent
            let dest = "\(dir)/\(name)"
            try? FileManager.default.createDirectory(atPath: dest,
                                                      withIntermediateDirectories: true)
            run7zz(args: ["x", "-o\(dest)", "-aoa", url.path])
        }
    }

    @objc func extractToChosen(_ sender: NSMenuItem) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard let firstArchive = urls.first(where: { isArchiveFile($0) }) else { return }

        // Open the main app with extract intent
        openMainApp(action: "extract", files: [firstArchive.path])
    }

    @objc func openInApp(_ sender: NSMenuItem) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        let paths = urls.filter { isArchiveFile($0) }.map { $0.path }
        openMainApp(action: "open", files: paths)
    }

    @objc func testArchive(_ sender: NSMenuItem) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in urls where isArchiveFile(url) {
            run7zz(args: ["t", url.path])
        }
    }

    @objc func compressAs(_ sender: NSMenuItem) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !urls.isEmpty else { return }
        let ext = sender.representedObject as? String ?? "7z"

        let baseName: String
        if urls.count == 1 {
            baseName = urls[0].deletingPathExtension().lastPathComponent
        } else {
            baseName = "Archive"
        }

        let dir = urls[0].deletingLastPathComponent().path
        let outputPath = "\(dir)/\(baseName).\(ext)"

        let formatFlag: String
        switch ext {
        case "7z": formatFlag = "7z"
        case "zip": formatFlag = "zip"
        case "tar.gz": formatFlag = "gzip"
        case "tar.xz": formatFlag = "xz"
        case "tar.zst": formatFlag = "zstd"
        default: formatFlag = "7z"
        }

        var args = ["a", "-t\(formatFlag)", outputPath]
        args.append(contentsOf: urls.map { $0.path })
        run7zz(args: args)
    }

    @objc func compressWithOptions(_ sender: NSMenuItem) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        let paths = urls.map { $0.path }
        openMainApp(action: "compress", files: paths)
    }

    // MARK: - Helpers

    private func isArchiveFile(_ url: URL) -> Bool {
        let archiveExtensions: Set<String> = [
            "7z", "zip", "rar", "tar", "gz", "bz2", "xz", "zst",
            "iso", "dmg", "wim", "cab", "arj", "lzh", "lzma",
            "rpm", "deb", "cpio", "cramfs", "squashfs", "vhd",
            "vhdx", "vmdk", "qcow", "qcow2", "vdi"
        ]
        return archiveExtensions.contains(url.pathExtension.lowercased())
    }

    private func find7zz() -> String? {
        // Look in the main app bundle
        let appBundlePaths = [
            Bundle.main.bundlePath
                .replacingOccurrences(of: "/Contents/PlugIns/FinderExtension.appex",
                                      with: "/Contents/Resources/7zz"),
        ]

        for path in appBundlePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback paths
        let fallbacks = [
            "/usr/local/bin/7zz",
            "/opt/homebrew/bin/7zz",
            "\(NSHomeDirectory())/.local/bin/7zz"
        ]
        for path in fallbacks {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func run7zz(args: [String]) {
        guard let binary = find7zz() else {
            showNotification(title: "7-Zip Error",
                           message: "7zz binary not found. Please open the 7-Zip app first.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    self.showNotification(title: "7-Zip",
                                        message: "Operation completed successfully.")
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    self.showNotification(title: "7-Zip Error",
                                        message: errorMsg.prefix(200).description)
                }
            } catch {
                self.showNotification(title: "7-Zip Error",
                                    message: error.localizedDescription)
            }
        }
    }

    private func openMainApp(action: String, files: [String]) {
        let appBundleId = "com.7zip.SevenZipMac"
        let workspace = NSWorkspace.shared

        // Pass files via pasteboard with a custom type
        let pb = NSPasteboard(name: NSPasteboard.Name("com.7zip.action"))
        pb.clearContents()
        let data = try? JSONEncoder().encode(["action": action, "files": files.joined(separator: "\n")])
        if let data = data {
            pb.setData(data, forType: .string)
        }

        // Open the main app
        if let appURL = workspace.urlForApplication(withBundleIdentifier: appBundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            let fileURLs = files.map { URL(fileURLWithPath: $0) }
            workspace.open(fileURLs, withApplicationAt: appURL,
                          configuration: config) { _, error in
                if let error = error {
                    self.showNotification(title: "7-Zip Error",
                                        message: "Failed to open app: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = nil
        NSUserNotificationCenter.default.deliver(notification)
    }
}
