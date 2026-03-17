import Cocoa
import FinderSync
import UserNotifications

class FinderSync: FIFinderSync {
    private var lastSelectedItems: [URL] = []
    private let actionPasteboardName = NSPasteboard.Name("com.septazip.action")
    private let actionPasteboardType = NSPasteboard.PasteboardType("com.septazip.action.payload")
    private let actionNotificationName = Notification.Name("com.septazip.finder-action-posted")

    private struct FinderActionFile: Codable {
        let path: String
        let bookmarkData: Data?
    }

    private struct FinderActionPayload: Codable {
        let id: String
        let createdAt: Date
        let action: String
        let files: [FinderActionFile]
        let format: String?
    }

    override init() {
        super.init()
        // Monitor all directories - the extension will show context menus everywhere
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        // Request notification permission for operation feedback
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Context Menu for selected items

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }

        let menu = NSMenu(title: "7-Zip")
        let selectedItems = FIFinderSyncController.default().selectedItemURLs() ?? []
        let selectedFiles = selectedItems.filter { !$0.hasDirectoryPath }
        lastSelectedItems = selectedItems

        if selectedItems.isEmpty { return nil }

        if !selectedFiles.isEmpty {
            let extractMenu = NSMenu()

            let extractHere = NSMenuItem(
                title: "Extract Here",
                action: #selector(extractHere(_:)),
                keyEquivalent: ""
            )
            extractHere.target = self
            extractHere.image = menuSymbol(
                "square.and.arrow.down",
                description: "Extract Here"
            )
            extractMenu.addItem(extractHere)

            let extractTo = NSMenuItem(
                title: "Extract to Subfolder",
                action: #selector(extractToSubfolder(_:)),
                keyEquivalent: ""
            )
            extractTo.target = self
            extractTo.image = menuSymbol(
                "folder.badge.plus",
                description: "Extract to Subfolder"
            )
            extractMenu.addItem(extractTo)

            let extractChoose = NSMenuItem(
                title: "Extract to...",
                action: #selector(extractToChosen(_:)),
                keyEquivalent: ""
            )
            extractChoose.target = self
            extractChoose.image = menuSymbol(
                "ellipsis.circle",
                description: "Extract to Folder"
            )
            extractMenu.addItem(extractChoose)

            let openWith = NSMenuItem(
                title: "Open with 7-Zip",
                action: #selector(openInApp(_:)),
                keyEquivalent: ""
            )
            openWith.target = self
            openWith.image = menuSymbol(
                "archivebox",
                description: "Open with 7-Zip"
            )
            extractMenu.addItem(openWith)

            let testItem = NSMenuItem(
                title: "Test Archive",
                action: #selector(testArchive(_:)),
                keyEquivalent: ""
            )
            testItem.target = self
            testItem.image = menuSymbol(
                "checkmark.shield",
                description: "Test Archive"
            )
            extractMenu.addItem(testItem)

            let extractRoot = NSMenuItem(
                title: "Decompress with 7-Zip",
                action: nil,
                keyEquivalent: ""
            )
            extractRoot.submenu = extractMenu
            extractRoot.image = menuSymbol(
                "tray.and.arrow.down",
                description: "Decompress with 7-Zip"
            )
            menu.addItem(extractRoot)
        }

        // Always offer compression for the current selection.
        let compressMenu = NSMenu()

        let formats: [(String, String)] = [
            ("7z", "Compress to .7z"),
            ("zip", "Compress to .zip"),
            ("tar.gz", "Compress to .tar.gz"),
            ("tar.xz", "Compress to .tar.xz"),
        ]

        for (tag, title) in formats.enumerated() {
            let item = NSMenuItem(
                title: title.1,
                action: #selector(compressAs(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = tag
            compressMenu.addItem(item)
        }

        let compressCustom = NSMenuItem(
            title: "Compress with Options...",
            action: #selector(compressWithOptions(_:)),
            keyEquivalent: ""
        )
        compressCustom.target = self
        compressMenu.addItem(compressCustom)

        let compressItem = NSMenuItem(
            title: "Compress with 7-Zip",
            action: nil,
            keyEquivalent: ""
        )
        compressItem.submenu = compressMenu
        compressItem.image = menuSymbol(
            "tray.and.arrow.up",
            description: "Compress with 7-Zip"
        )
        menu.addItem(compressItem)

        return menu
    }

    // MARK: - Actions

    @objc func extractHere(_ sender: NSMenuItem) {
        openMainApp(action: "extractHere", urls: selectedFileURLs())
    }

    @objc func extractToSubfolder(_ sender: NSMenuItem) {
        openMainApp(action: "extractToSubfolder", urls: selectedFileURLs())
    }

    @objc func extractToChosen(_ sender: NSMenuItem) {
        let archives = selectedFileURLs()
        guard !archives.isEmpty else { return }
        openMainApp(action: "extract", urls: archives)
    }

    @objc func openInApp(_ sender: NSMenuItem) {
        guard let firstFile = selectedFileURLs().first else { return }
        openMainApp(action: "open", urls: [firstFile])
    }

    @objc func testArchive(_ sender: NSMenuItem) {
        openMainApp(action: "test", urls: selectedFileURLs())
    }

    @objc func compressAs(_ sender: NSMenuItem) {
        let urls = selectedItemURLs()
        guard !urls.isEmpty else { return }
        let ext: String
        switch sender.tag {
        case 0:
            ext = "7z"
        case 1:
            ext = "zip"
        case 2:
            ext = "tar.gz"
        case 3:
            ext = "tar.xz"
        default:
            ext = "7z"
        }
        openMainApp(action: "compressDirect", urls: urls, format: ext)
    }

    @objc func compressWithOptions(_ sender: NSMenuItem) {
        let urls = selectedItemURLs()
        openMainApp(action: "compress", urls: urls)
    }

    // MARK: - Helpers

    private func selectedFileURLs() -> [URL] {
        selectedItemURLs().filter { !$0.hasDirectoryPath }
    }

    private func selectedItemURLs() -> [URL] {
        let currentSelection = FIFinderSyncController.default().selectedItemURLs() ?? []
        if currentSelection.isEmpty {
            return lastSelectedItems
        }
        return currentSelection
    }

    private func menuSymbol(_ systemName: String, description: String) -> NSImage? {
        let baseImage = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: description
        )
        let sizeConfiguration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .regular,
            scale: .medium
        )
        let monochromeConfiguration = NSImage.SymbolConfiguration.preferringMonochrome()
        let configuration = sizeConfiguration.applying(monochromeConfiguration)
        guard let symbolImage = (baseImage?.withSymbolConfiguration(configuration) ?? baseImage) else {
            return nil
        }

        let imageSize = NSSize(width: 16, height: 16)
        return NSImage(size: imageSize, flipped: false) { rect in
            let targetRect = rect.insetBy(dx: 0.5, dy: 0.5)
            symbolImage.draw(
                in: targetRect,
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            NSColor.labelColor.setFill()
            targetRect.fill(using: .sourceIn)
            return true
        }
    }

    private func hostApplicationURL() -> URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func openMainApp(action: String, urls: [URL], format: String? = nil) {
        guard !urls.isEmpty else { return }

        let appBundleId = "com.septazip.SeptaZip"
        let workspace = NSWorkspace.shared
        let payload = FinderActionPayload(
            id: UUID().uuidString,
            createdAt: Date(),
            action: action,
            files: urls.map(makeFinderActionFile(from:)),
            format: format
        )

        let pb = NSPasteboard(name: actionPasteboardName)
        var queuedPayloads = readQueuedPayloads(from: pb)
        queuedPayloads.append(payload)
        writeQueuedPayloads(queuedPayloads, to: pb)

        DistributedNotificationCenter.default().postNotificationName(
            actionNotificationName,
            object: nil,
            userInfo: notificationUserInfo(for: payload),
            deliverImmediately: true
        )

        let config = NSWorkspace.OpenConfiguration()
        config.activates = shouldActivateApp(for: action)
        let appURL = workspace.urlForApplication(withBundleIdentifier: appBundleId) ?? hostApplicationURL()

        workspace.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                self.showNotification(
                    title: "7-Zip Error",
                    message: "Failed to open app: \(error.localizedDescription)"
                )
            }
        }
    }

    private func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func readQueuedPayloads(from pasteboard: NSPasteboard) -> [FinderActionPayload] {
        guard let data = pasteboard.data(forType: actionPasteboardType) else {
            return []
        }

        if let payloads = try? JSONDecoder().decode([FinderActionPayload].self, from: data) {
            return payloads
        }

        if let payload = try? JSONDecoder().decode(FinderActionPayload.self, from: data) {
            return [payload]
        }

        return []
    }

    private func writeQueuedPayloads(_ payloads: [FinderActionPayload], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !payloads.isEmpty,
              let data = try? JSONEncoder().encode(payloads) else {
            return
        }
        pasteboard.setData(data, forType: actionPasteboardType)
    }

    private func notificationUserInfo(for payload: FinderActionPayload) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            "id": payload.id,
            "createdAt": payload.createdAt.timeIntervalSince1970,
            "action": payload.action,
            "files": payload.files.map(\.path)
        ]
        if let format = payload.format {
            info["format"] = format
        }
        return info
    }

    private func shouldActivateApp(for action: String) -> Bool {
        switch action {
        case "open", "extract", "compress":
            return true
        default:
            return false
        }
    }

    private func makeFinderActionFile(from url: URL) -> FinderActionFile {
        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return FinderActionFile(
            path: url.path,
            bookmarkData: bookmarkData
        )
    }
}
