import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private let serviceProvider = ServiceProvider()
    private let actionPasteboardName = NSPasteboard.Name("com.septazip.action")
    private let archiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "bz2", "xz", "zst",
        "iso", "dmg", "wim", "cab", "arj", "lzh", "lzma",
        "rpm", "deb", "cpio", "cramfs", "squashfs", "vhd",
        "vhdx", "vmdk", "qcow", "qcow2", "vdi"
    ]

    private struct FinderActionPayload: Codable {
        let action: String
        let files: String
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register Services (Quick Actions) for Finder right-click menu
        NSApp.servicesProvider = serviceProvider

        // Register as handler for archive file types
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenFiles(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
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

    private func openArchive(at path: String) {
        NotificationCenter.default.post(
            name: .openArchive,
            object: path
        )
    }

    private func handleIncoming(urls: [URL]) {
        guard !urls.isEmpty else { return }

        if let action = actionFromPasteboard(for: urls) {
            Task { @MainActor in
                AppActionRouter.shared.dispatch(action)
            }
            return
        }

        if let archiveURL = urls.first(where: isArchiveURL(_:)) {
            openArchive(at: archiveURL.path)
            return
        }

        Task { @MainActor in
            AppActionRouter.shared.dispatch(.compressFiles(urls))
        }
    }

    private func actionFromPasteboard(for urls: [URL]) -> AppOpenAction? {
        let pasteboard = NSPasteboard(name: actionPasteboardName)
        guard let data = pasteboard.data(forType: .string),
              let payload = try? JSONDecoder().decode(FinderActionPayload.self, from: data) else {
            return nil
        }

        let incomingPaths = urls.map(\.path)
        let payloadPaths = payload.files
            .split(separator: "\n")
            .map(String.init)

        guard !payloadPaths.isEmpty, Set(incomingPaths) == Set(payloadPaths) else {
            return nil
        }

        pasteboard.clearContents()

        switch payload.action {
        case "compress":
            return .compressFiles(urls)
        case "extract":
            if let archiveURL = urls.first(where: isArchiveURL(_:)) {
                return .extractArchive(archiveURL.path)
            }
        case "test":
            if let archiveURL = urls.first(where: isArchiveURL(_:)) {
                return .testArchive(archiveURL.path)
            }
        case "open":
            if let archiveURL = urls.first(where: isArchiveURL(_:)) {
                return .openArchive(archiveURL.path)
            }
        default:
            break
        }

        return nil
    }

    private func isArchiveURL(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }
}
