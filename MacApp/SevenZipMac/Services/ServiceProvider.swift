import Cocoa

/// Handles macOS Services (right-click Quick Actions) for Compress/Extract.
/// These appear in Finder's right-click menu under "Quick Actions" or "Services".
class ServiceProvider: NSObject {

    /// Called when user selects "Compress with 7-Zip" from Finder context menu.
    @objc func compressFiles(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            error.pointee = "No files selected" as NSString
            return
        }

        // Post notification to open compress sheet with these files
        NotificationCenter.default.post(
            name: .compressFiles,
            object: urls
        )

        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called when user selects "Extract with 7-Zip" from Finder context menu.
    @objc func extractFiles(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            error.pointee = "No files selected" as NSString
            return
        }

        // Extract each archive to a subfolder
        let archiveManager = ArchiveManager()
        for url in urls {
            Task {
                do {
                    try await archiveManager.extractHere(archive: url.path)
                } catch {
                    // Show notification on error
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Extraction Failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }
}
