import Cocoa
import SwiftUI
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private let serviceProvider = ServiceProvider()
    private let actionURLScheme = "septazip"
    private let actionNotificationName = Notification.Name("com.septazip.finder-action-posted")
    private let sharedAppGroupIdentifier = "com.septazip.shared"
    private let finderExtensionBundleIdentifier = "com.septazip.SeptaZip.FinderExtension"
    private let finderActionQueueDirectoryName = "SeptaZipFinderActions"
    private let archiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "bz2", "xz", "zst",
        "iso", "dmg", "wim", "cab", "arj", "lzh", "lzma",
        "rpm", "deb", "cpio", "cramfs", "squashfs", "vhd",
        "vhdx", "vmdk", "qcow", "qcow2", "vdi"
    ]
    private var isConsumingFinderActions = false
    private var finderActionPollTimer: DispatchSourceTimer?
    private var processedFinderActionIDs = Set<String>()
    private var processedFinderActionOrder: [String] = []
    private let maxProcessedFinderActionIDs = 512
    private var recentFinderActionSignatures: [String: Date] = [:]
    private var recentFinderActionSignatureOrder: [String] = []
    private let maxRecentFinderActionSignatures = 256
    private let duplicateFinderActionWindow: TimeInterval = 2.0

    private struct QueuedFinderActionPayload: Decodable {
        let id: String
        let createdAt: Date
        let action: String
        let files: [String]
        let format: String?
    }

    private struct FinderActionFile: Decodable {
        let path: String
    }

    private struct FinderActionPayload: Decodable {
        let action: String
        let files: [FinderActionFile]
        let format: String?

        private enum CodingKeys: String, CodingKey {
            case action
            case files
            case format
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            action = try container.decode(String.self, forKey: .action)
            format = try container.decodeIfPresent(String.self, forKey: .format)

            if let structuredFiles = try? container.decode([FinderActionFile].self, forKey: .files) {
                files = structuredFiles
            } else {
                let filePaths = try container.decode([String].self, forKey: .files)
                files = filePaths.map(FinderActionFile.init(path:))
            }
        }
    }

    override init() {
        super.init()
        registerAppleEventHandlers()
        registerFinderActionObserver()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        finderActionPollTimer?.cancel()
    }

    private func registerAppleEventHandlers() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenFiles(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    private func registerFinderActionObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFinderActionNotification(_:)),
            name: actionNotificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startFinderActionPolling()
        consumeQueuedFinderActions()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        consumeQueuedFinderActions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        finderActionPollTimer?.cancel()
        finderActionPollTimer = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("SeptaZip received URLs: %@", urls.map(\.absoluteString).joined(separator: ", "))
        let actionURLs = urls.filter { $0.scheme == actionURLScheme }
        let fileURLs = urls.filter(\.isFileURL)

        if !actionURLs.isEmpty {
            let actions = actionURLs.compactMap(action(fromActionURL:))
            NSLog("SeptaZip decoded %ld action(s) from URL handoff", actions.count)
            if !actions.isEmpty, actions.allSatisfy(\.isBackgroundJob) {
                scheduleBackgroundWindowSuppression()
            }
            for action in actions {
                route(action)
            }
        }

        if !fileURLs.isEmpty {
            handleIncoming(urls: fileURLs)
        }
    }

    @objc func handleOpenFiles(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let listDesc = event.paramDescriptor(forKeyword: keyDirectObject),
              listDesc.numberOfItems > 0 else { return }
        var urls: [URL] = []
        for i in 1...listDesc.numberOfItems {
            if let urlDesc = listDesc.atIndex(i),
               let urlString = urlDesc.stringValue,
               let url = URL(string: urlString) {
                urls.append(url)
            }
        }
        handleIncoming(urls: urls)
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            NSLog("SeptaZip received invalid get-url Apple event")
            return
        }
        NSLog("SeptaZip handling get-url event: %@", urlString)
        application(NSApp, open: [url])
    }

    @objc private func handleFinderActionNotification(_ notification: Notification) {
        consumeQueuedFinderActions()
    }

    private func openArchive(at path: String) {
        NotificationCenter.default.post(
            name: .openArchive,
            object: path
        )
    }

    private func handleIncoming(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let accessibleURLs = urls.map { SecurityScopedAccessManager.shared.retainRelatedAccess(for: $0) }

        if let archiveURL = accessibleURLs.first(where: isArchiveURL(_:)) {
            openArchive(at: archiveURL.path)
            return
        }

        AppActionRouter.shared.dispatch(.compressFiles(accessibleURLs))
    }

    private func route(_ action: AppOpenAction) {
        NSLog("SeptaZip routing action: %@", String(describing: action))
        if !action.isBackgroundJob {
            presentMainWindowIfNeeded()
        }
        if !BackgroundArchiveJobManager.shared.handle(action) {
            AppActionRouter.shared.dispatch(action)
        }
    }

    private func presentMainWindowIfNeeded() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where !(window is NSPanel) {
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    private func startFinderActionPolling() {
        guard finderActionPollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(500),
            repeating: .seconds(1),
            leeway: .milliseconds(200)
        )
        timer.setEventHandler { [weak self] in
            self?.consumeQueuedFinderActions()
        }
        timer.resume()
        finderActionPollTimer = timer
    }

    private func scheduleBackgroundWindowSuppression() {
        let suppressRegularWindows = {
            for window in NSApp.windows where !(window is NSPanel) {
                window.orderOut(nil)
            }
        }

        DispatchQueue.main.async(execute: suppressRegularWindows)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: suppressRegularWindows)
    }

    private func action(fromActionURL url: URL) -> AppOpenAction? {
        guard url.scheme == actionURLScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payloadValue = components.queryItems?.first(where: { $0.name == "payload" })?.value,
              let payloadData = Data(base64Encoded: payloadValue),
              let payload = try? JSONDecoder().decode(FinderActionPayload.self, from: payloadData) else {
            NSLog("SeptaZip failed to decode action URL: %@", url.absoluteString)
            return nil
        }

        let urls = payload.files
            .filter { isSafePath($0.path) }
            .map { URL(fileURLWithPath: $0.path).standardizedFileURL }
        guard !urls.isEmpty else { return nil }

        NSLog(
            "SeptaZip action payload decoded: action=%@ files=%@ format=%@",
            payload.action,
            urls.map(\.path).joined(separator: ", "),
            payload.format ?? "(nil)"
        )

        switch payload.action {
        case "compress":
            return .compressFiles(urls)
        case "compressDirect":
            guard let format = archiveFormat(from: payload.format) else { return nil }
            return .quickCompress(urls, format)
        case "extract":
            return .extractArchives(urls.filter { !$0.hasDirectoryPath }, .prompt)
        case "extractHere":
            return .extractArchives(urls.filter { !$0.hasDirectoryPath }, .sameFolder)
        case "extractToSubfolder":
            return .extractArchives(urls.filter { !$0.hasDirectoryPath }, .subfolder)
        case "test":
            return .testArchives(urls.filter { !$0.hasDirectoryPath })
        case "open":
            if let firstFileURL = urls.first(where: { !$0.hasDirectoryPath }) {
                return .openArchive(firstFileURL)
            }
        default:
            break
        }

        return nil
    }

    private func action(fromQueuedFinderPayload payload: QueuedFinderActionPayload) -> AppOpenAction? {
        let urls = payload.files
            .filter(isSafePath(_:))
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard !urls.isEmpty else { return nil }

        switch payload.action {
        case "compress":
            return .compressFiles(urls)
        case "compressDirect":
            guard let archiveFormat = archiveFormat(from: payload.format) else { return nil }
            return .quickCompress(urls, archiveFormat)
        case "extract":
            return .extractArchives(urls.filter { !$0.hasDirectoryPath }, .prompt)
        case "extractHere":
            return .extractArchives(urls.filter { !$0.hasDirectoryPath }, .sameFolder)
        case "extractToSubfolder":
            return .extractArchives(urls.filter { !$0.hasDirectoryPath }, .subfolder)
        case "test":
            return .testArchives(urls.filter { !$0.hasDirectoryPath })
        case "open":
            if let firstFileURL = urls.first(where: { !$0.hasDirectoryPath }) {
                return .openArchive(firstFileURL)
            }
        default:
            break
        }

        return nil
    }

    private func consumeQueuedFinderActions() {
        guard !isConsumingFinderActions else { return }
        isConsumingFinderActions = true
        defer { isConsumingFinderActions = false }

        let fileManager = FileManager.default
        for queueDirectoryURL in finderActionQueueDirectoryURLs() {
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: queueDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let actionFiles = fileURLs
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            for fileURL in actionFiles {
                defer { try? fileManager.removeItem(at: fileURL) }

                guard let payloadData = try? Data(contentsOf: fileURL),
                      let payload = try? JSONDecoder().decode(QueuedFinderActionPayload.self, from: payloadData) else {
                    continue
                }

                if hasProcessedFinderAction(id: payload.id) {
                    continue
                }

                if shouldSuppressDuplicateFinderAction(payload) {
                    markFinderActionProcessed(id: payload.id)
                    continue
                }

                guard let action = action(fromQueuedFinderPayload: payload) else {
                    markFinderActionProcessed(id: payload.id)
                    continue
                }

                markFinderActionProcessed(id: payload.id)
                if action.isBackgroundJob {
                    scheduleBackgroundWindowSuppression()
                }
                route(action)
            }
        }
    }

    private func hasProcessedFinderAction(id: String) -> Bool {
        processedFinderActionIDs.contains(id)
    }

    private func markFinderActionProcessed(id: String) {
        guard processedFinderActionIDs.insert(id).inserted else { return }
        processedFinderActionOrder.append(id)
        if processedFinderActionOrder.count > maxProcessedFinderActionIDs {
            let overflow = processedFinderActionOrder.count - maxProcessedFinderActionIDs
            let removed = processedFinderActionOrder.prefix(overflow)
            processedFinderActionOrder.removeFirst(overflow)
            for staleID in removed {
                processedFinderActionIDs.remove(staleID)
            }
        }
    }

    private func finderActionSignature(for payload: QueuedFinderActionPayload) -> String {
        let normalizedPaths = payload.files
            .filter(isSafePath(_:))
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .sorted()
        return ([payload.action, payload.format ?? ""] + normalizedPaths)
            .joined(separator: "|")
    }

    private func shouldSuppressDuplicateFinderAction(_ payload: QueuedFinderActionPayload) -> Bool {
        let signature = finderActionSignature(for: payload)
        let eventTime = payload.createdAt

        if let lastSeenAt = recentFinderActionSignatures[signature],
           abs(eventTime.timeIntervalSince(lastSeenAt)) < duplicateFinderActionWindow {
            return true
        }

        let wasNew = recentFinderActionSignatures.updateValue(eventTime, forKey: signature) == nil
        if wasNew {
            recentFinderActionSignatureOrder.append(signature)
            if recentFinderActionSignatureOrder.count > maxRecentFinderActionSignatures {
                let overflow = recentFinderActionSignatureOrder.count - maxRecentFinderActionSignatures
                let removed = recentFinderActionSignatureOrder.prefix(overflow)
                recentFinderActionSignatureOrder.removeFirst(overflow)
                for staleSignature in removed {
                    recentFinderActionSignatures.removeValue(forKey: staleSignature)
                }
            }
        }

        return false
    }

    private func finderActionQueueDirectoryURLs() -> [URL] {
        var urls: [URL] = []

        if let groupContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier
        ) {
            urls.append(
                groupContainerURL.appendingPathComponent(
                    finderActionQueueDirectoryName,
                    isDirectory: true
                )
            )
        } else {
            // Legacy fallback for previously shipped builds that used the extension container.
            let containerPath = "Library/Containers/\(finderExtensionBundleIdentifier)/Data/Library/Application Support/\(finderActionQueueDirectoryName)"
            let legacyURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(containerPath, isDirectory: true)
            urls.append(legacyURL)
        }

        return urls
    }

    private func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        return !path.components(separatedBy: "/").contains("..")
    }

    private func archiveFormat(from rawFormat: String?) -> ArchiveFormat? {
        switch rawFormat {
        case "7z":
            return .sevenZ
        case "zip":
            return .zip
        case "tar.gz":
            return .gzip
        case "tar.xz":
            return .xz
        default:
            return nil
        }
    }

    private func isArchiveURL(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }
}
