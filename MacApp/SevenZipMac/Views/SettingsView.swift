import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var archiveManager: ArchiveManager
    @AppStorage("defaultFormat") private var defaultFormat = "7z"
    @AppStorage("defaultLevel") private var defaultLevel = 5
    @AppStorage("extractToSubfolder") private var extractToSubfolder = true
    @AppStorage("openAfterExtract") private var openAfterExtract = true
    @AppStorage("deleteAfterExtract") private var deleteAfterExtract = false
    @AppStorage("showFinderExtension") private var showFinderExtension = true

    private let upstreamURL = URL(string: "https://github.com/ip7z/7zip")!
    private let githubReleasesURL = URL(string: "https://github.com/ip7z/7zip/releases")!
    private let finderExtensionsURL = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!

    var body: some View {
        TabView {
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }

            compressionTab
                .tabItem {
                    Label("Compression", systemImage: "arrow.up.doc")
                }

            extractionTab
                .tabItem {
                    Label("Extraction", systemImage: "arrow.down.doc")
                }

            integrationTab
                .tabItem {
                    Label("Integration", systemImage: "square.grid.2x2")
                }
        }
        .frame(width: 620, height: 480)
        .task {
            await archiveManager.refreshEngineDetails()
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                aboutHero
                engineSection
                updateSection
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var aboutHero: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                Text("SeptaZip")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text("Native archive management for macOS, powered by the official 7-Zip engine.")
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    settingsBadge(appVersionText, systemImage: "app.badge")
                    settingsBadge(archiveManager.isUsingBundledBinary ? "Bundled engine" : "External engine fallback",
                                  systemImage: archiveManager.isUsingBundledBinary ? "shippingbox.fill" : "exclamationmark.triangle.fill")
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Button("Official 7-Zip") {
                    NSWorkspace.shared.open(upstreamURL)
                }
                .buttonStyle(.borderedProminent)

                Button("Copy Diagnostics") {
                    copyDiagnostics()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var engineSection: some View {
        settingsCard(
            title: "Bundled Engine",
            subtitle: "The app now reads the actual runtime metadata from the bundled `7zz` binary."
        ) {
            if archiveManager.isLoadingEngineDetails && archiveManager.engineDetails == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading engine details...")
                        .foregroundColor(.secondary)
                }
            } else if let details = archiveManager.engineDetails {
                VStack(spacing: 10) {
                    infoRow("Version", value: details.displayVersion)
                    infoRow("Build date", value: details.buildDate ?? "Unknown")
                    infoRow("Binary path", value: details.binaryPath, monospaced: true)
                    infoRow("Upstream", value: "Igor Pavlov · github.com/ip7z/7zip")

                    if let platformLine = details.platformLine {
                        infoRow("Runtime", value: platformLine, monospaced: true)
                    }

                    if !archiveManager.isUsingBundledBinary {
                        Label("Running with an external `7zz` binary. Production builds should use the bundled engine.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label(archiveManager.engineDetailsError ?? "Unable to inspect the 7-Zip engine.", systemImage: "xmark.octagon.fill")
                        .foregroundColor(.red)
                    Button("Retry") {
                        Task {
                            await archiveManager.refreshEngineDetails(force: true)
                        }
                    }
                }
            }
        }
    }

    private var updateSection: some View {
        settingsCard(
            title: "Update Guidance",
            subtitle: "SeptaZip does not auto-update the 7-Zip core yet. Compare the version here with the latest official upstream source or release when you want to refresh it."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current workflow:")
                    .font(.subheadline.weight(.medium))

                VStack(alignment: .leading, spacing: 8) {
                    settingsStep("1. Check the official upstream repository or releases for a newer 7-Zip version.")
                    settingsStep("2. Sync `source_code/7zip/` from upstream and rebuild the bundled `7zz` binary.")
                    settingsStep("3. Rebuild the app and recreate the DMG.")
                }

                HStack(spacing: 10) {
                    Button("Open Upstream Repository") {
                        NSWorkspace.shared.open(upstreamURL)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Releases") {
                        NSWorkspace.shared.open(githubReleasesURL)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Compression

    private var compressionTab: some View {
        Form {
            Section("Defaults") {
                Picker("Default format", selection: $defaultFormat) {
                    ForEach(ArchiveFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }

                Picker("Compression level", selection: $defaultLevel) {
                    ForEach(CompressionLevel.allCases) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
            }

            Section("Guidance") {
                Text("Use `7z` when size matters most. Use `ZIP` when compatibility with other tools is more important.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - Extraction

    private var extractionTab: some View {
        Form {
            Section("Defaults") {
                Toggle("Extract to a subfolder by default", isOn: $extractToSubfolder)
                Toggle("Reveal extracted files in Finder", isOn: $openAfterExtract)
                Toggle("Move archive to Trash after extraction", isOn: $deleteAfterExtract)
            }

            Section("Guidance") {
                Text("For safer testing, keep automatic trashing off until you have verified the extracted files.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - Integration

    private var integrationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsCard(
                    title: "Finder Menu",
                    subtitle: "SeptaZip already supports Finder right-click actions similar to Windows 7-Zip."
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show in Finder context menu", isOn: $showFinderExtension)

                        Text("Current menu set: Extract Here, Extract to Subfolder, Extract to..., Open with 7-Zip, Test Archive, and Compress with 7-Zip.")
                            .foregroundColor(.secondary)

                        Button("Open Finder Extensions Settings") {
                            NSWorkspace.shared.open(finderExtensionsURL)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                settingsCard(
                    title: "Manual Setup",
                    subtitle: "Finder Sync must be enabled once in macOS before the menu appears."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        settingsStep("1. Open System Settings.")
                        settingsStep("2. Go to Privacy & Security → Extensions → Finder Extensions.")
                        settingsStep("3. Enable “SeptaZip Finder Extension”.")
                        settingsStep("4. Relaunch Finder if the menu does not appear immediately.")
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "App \(shortVersion) (\(build))"
    }

    private func copyDiagnostics() {
        let diagnostics = [
            "SeptaZip \(appVersionText)",
            archiveManager.engineDetails?.diagnosticsText ?? "Engine: unavailable"
        ].joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func settingsBadge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            )
    }

    private func infoRow(_ title: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsStep(_ text: String) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
