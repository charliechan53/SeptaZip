import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    private let serviceProvider = ServiceProvider()

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
        for url in urls {
            openArchive(at: url.path)
        }
    }

    @objc func handleOpenFiles(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let listDesc = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        for i in 1...listDesc.numberOfItems {
            if let urlDesc = listDesc.atIndex(i),
               let urlString = urlDesc.stringValue,
               let url = URL(string: urlString) {
                openArchive(at: url.path)
            }
        }
    }

    private func openArchive(at path: String) {
        NotificationCenter.default.post(
            name: .openArchive,
            object: path
        )
    }
}
