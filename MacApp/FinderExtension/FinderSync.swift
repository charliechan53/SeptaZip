import Cocoa
import FinderSync
import UserNotifications

class FinderSync: FIFinderSync {
    private var lastSelectedItems: [URL] = []
    private let actionNotificationName = Notification.Name("com.septazip.finder-action-posted")
    private let actionQueueDirectoryName = "SeptaZipFinderActions"
    private let sharedAppGroupIdentifier = "com.septazip.shared"
    private let duplicateActionWindow: TimeInterval = 2.0
    private let lastDispatchedSignatureDefaultsKey = "finder.lastDispatchedSignature"
    private let lastDispatchedTimestampDefaultsKey = "finder.lastDispatchedTimestamp"
    private var lastDispatchedActionSignature: String?
    private var lastDispatchedActionTime = Date.distantPast

    private struct FinderActionPayload: Codable {
        let id: String
        let createdAt: Date
        let action: String
        let files: [String]
        let format: String?
    }

    override init() {
        super.init()
        refreshMonitoredDirectories()
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(refreshMonitoredDirectories),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(refreshMonitoredDirectories),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
        // Request notification permission for operation feedback
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Context Menu for selected items

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }

        let menu = NSMenu(title: "7-Zip")
        let selectedItems = currentContextURLs(for: menuKind)
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
        let controller = FIFinderSyncController.default()
        let currentSelection = controller.selectedItemURLs() ?? []
        if currentSelection.isEmpty {
            if let targetedURL = controller.targetedURL() {
                return [targetedURL]
            }
            return lastSelectedItems
        }
        return currentSelection
    }

    private func currentContextURLs(for menuKind: FIMenuKind) -> [URL] {
        let controller = FIFinderSyncController.default()
        let selectedItems = controller.selectedItemURLs() ?? []
        if !selectedItems.isEmpty {
            return selectedItems
        }

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            if let targetedURL = controller.targetedURL() {
                return [targetedURL]
            }
        default:
            break
        }

        return lastSelectedItems
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

        let normalizedPaths = urls
            .map { $0.standardizedFileURL.path }
            .sorted()
        let signature = ([action, format ?? ""] + normalizedPaths)
            .joined(separator: "|")
        let now = Date()
        if shouldSuppressDuplicateDispatch(signature: signature, now: now) {
            return
        }

        let appBundleId = "com.septazip.SeptaZip"
        let workspace = NSWorkspace.shared
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: appBundleId)
        let payload = FinderActionPayload(
            id: UUID().uuidString,
            createdAt: Date(),
            action: action,
            files: urls.map(\.path),
            format: format
        )
        guard enqueueFinderAction(payload) else {
            showNotification(
                title: "7-Zip Error",
                message: "Failed to queue Finder action."
            )
            return
        }

        if !runningApps.isEmpty {
            if shouldActivateApp(for: action) {
                runningApps.first?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            notifyMainApp(repeats: 2)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = shouldActivateApp(for: action)
        let appURL = workspace.urlForApplication(withBundleIdentifier: appBundleId) ?? hostApplicationURL()

        workspace.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                self.showNotification(
                    title: "7-Zip Error",
                    message: "Failed to open app: \(error.localizedDescription)"
                )
            } else {
                self.notifyMainApp(repeats: 8)
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

    private func shouldActivateApp(for action: String) -> Bool {
        switch action {
        case "open", "extract", "compress":
            return true
        default:
            return false
        }
    }

    private func notifyMainApp(repeats: Int) {
        let notificationCenter = DistributedNotificationCenter.default()

        for attempt in 0..<max(repeats, 1) {
            let delay = 0.2 * Double(attempt)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                notificationCenter.postNotificationName(
                    self.actionNotificationName,
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
        }
    }

    private func enqueueFinderAction(_ payload: FinderActionPayload) -> Bool {
        guard let queueDirectoryURL = actionQueueDirectoryURL() else { return false }
        do {
            try FileManager.default.createDirectory(
                at: queueDirectoryURL,
                withIntermediateDirectories: true
            )
            let fileName = "finder-action-\(Int(payload.createdAt.timeIntervalSince1970 * 1000))-\(payload.id).json"
            let fileURL = queueDirectoryURL.appendingPathComponent(fileName)
            let payloadData = try JSONEncoder().encode(payload)
            try payloadData.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func actionQueueDirectoryURL() -> URL? {
        if let groupContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier
        ) {
            return groupContainerURL.appendingPathComponent(
                actionQueueDirectoryName,
                isDirectory: true
            )
        }

        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return appSupportURL.appendingPathComponent(actionQueueDirectoryName, isDirectory: true)
    }

    private func shouldSuppressDuplicateDispatch(signature: String, now: Date) -> Bool {
        if signature == lastDispatchedActionSignature,
           now.timeIntervalSince(lastDispatchedActionTime) < duplicateActionWindow {
            return true
        }

        let defaults = UserDefaults.standard
        let sharedSignature = defaults.string(forKey: lastDispatchedSignatureDefaultsKey)
        let sharedTimestamp = defaults.double(forKey: lastDispatchedTimestampDefaultsKey)
        if let sharedSignature,
           signature == sharedSignature,
           sharedTimestamp > 0 {
            let sharedTime = Date(timeIntervalSince1970: sharedTimestamp)
            if now.timeIntervalSince(sharedTime) < duplicateActionWindow {
                lastDispatchedActionSignature = signature
                lastDispatchedActionTime = now
                return true
            }
        }

        lastDispatchedActionSignature = signature
        lastDispatchedActionTime = now
        defaults.set(signature, forKey: lastDispatchedSignatureDefaultsKey)
        defaults.set(now.timeIntervalSince1970, forKey: lastDispatchedTimestampDefaultsKey)
        return false
    }

    @objc private func refreshMonitoredDirectories() {
        var monitoredURLs = Set<URL>()
        monitoredURLs.insert(URL(fileURLWithPath: "/"))
        // Monitoring /Volumes keeps external-drive menus available without
        // treating each mounted volume root as a decorated sync folder.
        monitoredURLs.insert(URL(fileURLWithPath: "/Volumes"))

        FIFinderSyncController.default().directoryURLs = monitoredURLs
    }
}
