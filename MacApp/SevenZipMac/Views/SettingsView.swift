import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultFormat") private var defaultFormat = "7z"
    @AppStorage("defaultLevel") private var defaultLevel = 5
    @AppStorage("extractToSubfolder") private var extractToSubfolder = true
    @AppStorage("openAfterExtract") private var openAfterExtract = true
    @AppStorage("deleteAfterExtract") private var deleteAfterExtract = false
    @AppStorage("showFinderExtension") private var showFinderExtension = true

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
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
                    Label("Integration", systemImage: "puzzlepiece")
                }
        }
        .frame(width: 450, height: 300)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent("7zz Binary") {
                    let manager = ArchiveManager()
                    if manager.isBinaryAvailable {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Found")
                        }
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Not found")
                        }
                    }
                }

                LabeledContent("Version") {
                    Text("7-Zip 26.00 for macOS")
                }
            }
        }
        .padding()
    }

    // MARK: - Compression Tab

    private var compressionTab: some View {
        Form {
            Picker("Default format:", selection: $defaultFormat) {
                ForEach(ArchiveFormat.allCases) { fmt in
                    Text(fmt.displayName).tag(fmt.rawValue)
                }
            }

            Picker("Default level:", selection: $defaultLevel) {
                ForEach(CompressionLevel.allCases) { lvl in
                    Text(lvl.displayName).tag(lvl.rawValue)
                }
            }
        }
        .padding()
    }

    // MARK: - Extraction Tab

    private var extractionTab: some View {
        Form {
            Toggle("Extract to subfolder by default", isOn: $extractToSubfolder)
            Toggle("Open folder after extraction", isOn: $openAfterExtract)
            Toggle("Move archive to Trash after extraction", isOn: $deleteAfterExtract)
        }
        .padding()
    }

    // MARK: - Integration Tab

    private var integrationTab: some View {
        Form {
            Section {
                Toggle("Show in Finder context menu", isOn: $showFinderExtension)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Finder Extension")
                        .fontWeight(.medium)
                    Text("To enable the right-click menu in Finder:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("1. Open System Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("2. Go to Privacy & Security → Extensions → Finder Extensions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("3. Enable \"7-Zip\"")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!
                        )
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
    }
}
