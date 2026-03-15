import SwiftUI

@main
struct SevenZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var archiveManager = ArchiveManager()
    @StateObject private var actionRouter = AppActionRouter.shared

    var body: some Scene {
        // Main archive browser window
        WindowGroup {
            MainWindow()
                .environmentObject(archiveManager)
                .environmentObject(actionRouter)
                .frame(minWidth: 920, minHeight: 560)
        }
        .commands {
            // File menu commands
            CommandGroup(after: .newItem) {
                Button("Open Archive...") {
                    NotificationCenter.default.post(name: .openArchive, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Compress Files...") {
                    NotificationCenter.default.post(name: .compressFiles, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Extract All...") {
                    NotificationCenter.default.post(name: .extractAll, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Test Archive") {
                    NotificationCenter.default.post(name: .testArchive, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(archiveManager)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openArchive = Notification.Name("openArchive")
    static let compressFiles = Notification.Name("compressFiles")
    static let extractAll = Notification.Name("extractAll")
    static let testArchive = Notification.Name("testArchive")
}
