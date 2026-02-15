import SwiftUI

struct ExtractView: View {
    @EnvironmentObject var archiveManager: ArchiveManager
    @Environment(\.dismiss) private var dismiss

    let archivePath: String

    @State private var destinationPath = ""
    @State private var extractMode: ExtractMode = .toSubfolder
    @State private var overwriteMode: OverwriteMode = .overwrite
    @State private var password = ""
    @State private var isExtracting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    enum ExtractMode: String, CaseIterable {
        case toSubfolder = "To subfolder"
        case here = "Here (same folder)"
        case chooseFolder = "Choose folder..."
    }

    enum OverwriteMode {
        case overwrite
        case skip
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Extract Archive")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                // Archive info
                GroupBox("Archive") {
                    HStack {
                        Image(systemName: "doc.zipper")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: archivePath).lastPathComponent)
                                .fontWeight(.medium)
                            Text(archivePath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        Spacer()
                        if let info = archiveManager.archiveInfo {
                            VStack(alignment: .trailing) {
                                Text("\(info.totalFiles) files")
                                    .font(.caption)
                                Text(info.formattedTotalSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                // Destination
                GroupBox("Extract to") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $extractMode) {
                            ForEach(ExtractMode.allCases, id: \.rawValue) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        .onChange(of: extractMode) { newValue in
                            updateDestination(mode: newValue)
                        }

                        if extractMode == .chooseFolder || !destinationPath.isEmpty {
                            HStack {
                                TextField("Destination", text: $destinationPath)
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse...") {
                                    chooseFolderPanel()
                                }
                            }
                        }

                        HStack {
                            Text("If file exists:")
                            Picker("", selection: $overwriteMode) {
                                Text("Overwrite").tag(OverwriteMode.overwrite)
                                Text("Skip").tag(OverwriteMode.skip)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }
                    .padding(8)
                }

                // Password
                GroupBox("Password (if encrypted)") {
                    HStack {
                        SecureField("Enter password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .padding()

            Spacer()

            Divider()

            // Action buttons
            HStack {
                if isExtracting {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Extracting...")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    if isExtracting {
                        archiveManager.cancel()
                    }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Extract") {
                    startExtraction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExtracting)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .onAppear {
            updateDestination(mode: extractMode)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Extraction Complete", isPresented: $showSuccess) {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destinationPath)
                dismiss()
            }
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Files have been extracted successfully.")
        }
    }

    // MARK: - Actions

    private func updateDestination(mode: ExtractMode) {
        let archiveDir = (archivePath as NSString).deletingLastPathComponent
        let baseName = ((archivePath as NSString).lastPathComponent as NSString).deletingPathExtension

        switch mode {
        case .toSubfolder:
            destinationPath = "\(archiveDir)/\(baseName)"
        case .here:
            destinationPath = archiveDir
        case .chooseFolder:
            if destinationPath.isEmpty {
                destinationPath = archiveDir
            }
        }
    }

    private func chooseFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Extract To"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
        }
    }

    private func startExtraction() {
        isExtracting = true

        Task {
            do {
                try await archiveManager.extract(
                    archive: archivePath,
                    to: destinationPath,
                    password: password.isEmpty ? nil : password,
                    overwrite: overwriteMode == .overwrite
                )
                isExtracting = false
                showSuccess = true
            } catch {
                isExtracting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
