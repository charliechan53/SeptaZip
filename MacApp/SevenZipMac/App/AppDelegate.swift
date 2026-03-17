import Cocoa
import SwiftUI
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private let serviceProvider = ServiceProvider()
    private let actionPasteboardName = NSPasteboard.Name("com.septazip.action")
    private let actionPasteboardType = NSPasteboard.PasteboardType("com.septazip.action.payload")
    private let actionNotificationName = Notification.Name("com.septazip.finder-action-posted")
    private let archiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "bz2", "xz", "zst",
        "iso", "dmg", "wim", "cab", "arj", "lzh", "lzma",
        "rpm", "deb", "cpio", "cramfs", "squashfs", "vhd",
        "vhdx", "vmdk", "qcow", "qcow2", "vdi"
    ]
    private var consumedActionIDs: [String: Date] = [:]

    private struct FinderActionFile: Codable {
        let path: String
        let bookmarkData: Data?
    }

    private struct FinderActionPayload: Codable {
        let id: String?
        let createdAt: Date?
        let action: String
        let files: [FinderActionFile]
        let format: String?
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register Services (Quick Actions) for Finder right-click menu
        NSApp.servicesProvider = serviceProvider
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Register as handler for archive file types
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenFiles(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFinderActionNotification(_:)),
            name: actionNotificationName,
            object: nil
        )

        consumePendingFinderActionsIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        consumePendingFinderActionsIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handleIncoming(urls: urls)
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

    @objc private func handleFinderActionNotification(_ notification: Notification) {
        consumePendingFinderActionsIfNeeded()

        if let action = action(from: notification) {
            Task { @MainActor in
                route(action)
            }
        }
    }

    private func openArchive(at path: String) {
        NotificationCenter.default.post(
            name: .openArchive,
            object: path
        )
    }

    private func handleIncoming(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let accessibleURLs = urls.map { SecurityScopedAccessManager.shared.retainAccess(to: $0) }

        if let archiveURL = accessibleURLs.first(where: isArchiveURL(_:)) {
            openArchive(at: archiveURL.path)
            return
        }

        Task { @MainActor in
            AppActionRouter.shared.dispatch(.compressFiles(accessibleURLs))
        }
    }

    private func consumePendingFinderActionsIfNeeded() {
        let actions = consumeQueuedFinderActions()
        guard !actions.isEmpty else { return }

        Task { @MainActor in
            for action in actions {
                route(action)
            }
        }
    }

    @MainActor
    private func route(_ action: AppOpenAction) {
        if !BackgroundArchiveJobManager.shared.handle(action) {
            AppActionRouter.shared.dispatch(action)
        }
    }

    private func consumeQueuedFinderActions() -> [AppOpenAction] {
        let payloads = readFinderActionPayloads()
        guard !payloads.isEmpty else { return [] }

        clearFinderActionPasteboard()
        pruneConsumedActionIDs()
        return payloads.compactMap { payload in
            guard shouldConsume(payload) else { return nil }
            return action(from: payload)
        }
    }

    private func readFinderActionPayloads() -> [FinderActionPayload] {
        let pasteboard = NSPasteboard(name: actionPasteboardName)

        if let data = pasteboard.data(forType: actionPasteboardType),
           let payloads = decodeFinderActionPayloads(from: data) {
            return payloads.filter { payload in
                guard let createdAt = payload.createdAt else { return true }
                return Date().timeIntervalSince(createdAt) <= 60
            }
        }

        if let data = pasteboard.data(forType: .string),
           let legacyPayload = try? JSONDecoder().decode(LegacyFinderActionPayload.self, from: data) {
            return [FinderActionPayload(
                id: UUID().uuidString,
                createdAt: Date(),
                action: legacyPayload.action,
                files: legacyPayload.files
                    .split(separator: "\n")
                    .map { FinderActionFile(path: String($0), bookmarkData: nil) },
                format: nil
            )]
        }

        return []
    }

    private func decodeFinderActionPayloads(from data: Data) -> [FinderActionPayload]? {
        if let payloads = try? JSONDecoder().decode([FinderActionPayload].self, from: data) {
            return payloads
        }

        if let payload = try? JSONDecoder().decode(FinderActionPayload.self, from: data) {
            return [payload]
        }

        return nil
    }

    private func action(from notification: Notification) -> AppOpenAction? {
        guard let userInfo = notification.userInfo else { return nil }

        let payload = FinderActionPayload(
            id: userInfo["id"] as? String,
            createdAt: (userInfo["createdAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)),
            action: userInfo["action"] as? String ?? "",
            files: (userInfo["files"] as? [String] ?? []).map {
                FinderActionFile(path: $0, bookmarkData: nil)
            },
            format: userInfo["format"] as? String
        )

        guard shouldConsume(payload) else { return nil }
        return action(from: payload)
    }

    private func shouldConsume(_ payload: FinderActionPayload) -> Bool {
        if let createdAt = payload.createdAt,
           Date().timeIntervalSince(createdAt) > 60 {
            return false
        }

        if let id = payload.id {
            pruneConsumedActionIDs()
            if consumedActionIDs[id] != nil {
                return false
            }
            consumedActionIDs[id] = Date()
        }

        return true
    }

    private func pruneConsumedActionIDs() {
        let expirationInterval: TimeInterval = 120
        consumedActionIDs = consumedActionIDs.filter { _, timestamp in
            Date().timeIntervalSince(timestamp) <= expirationInterval
        }
    }

    private func action(from payload: FinderActionPayload) -> AppOpenAction? {
        let urls = payload.files.filter { isSafePath($0.path) }.map(resolveFinderActionFile(_:))
        guard !urls.isEmpty else { return nil }

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

    private func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        return !path.components(separatedBy: "/").contains("..")
    }

    private func resolveFinderActionFile(_ file: FinderActionFile) -> URL {
        SecurityScopedAccessManager.shared.resolveURL(
            path: file.path,
            bookmarkData: file.bookmarkData
        )
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

    private func clearFinderActionPasteboard() {
        NSPasteboard(name: actionPasteboardName).clearContents()
    }

    private func isArchiveURL(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }
}

private struct LegacyFinderActionPayload: Codable {
    let action: String
    let files: String
}
