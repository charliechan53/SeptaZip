import SwiftUI
import UniformTypeIdentifiers

struct CompressView: View {
    @EnvironmentObject var archiveManager: ArchiveManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFiles: [URL] = []
    @State private var outputPath = ""
    @State private var format: ArchiveFormat = .sevenZ
    @State private var level: CompressionLevel = .normal
    @State private var password = ""
    @State private var encryptHeaders = false
    @State private var splitSize = ""
    @State private var isCompressing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var isDraggingOver = false

    init(initialFiles: [URL] = []) {
        let defaults = UserDefaults.standard
        let format = ArchiveFormat(
            rawValue: defaults.string(forKey: "defaultFormat") ?? ArchiveFormat.sevenZ.rawValue
        ) ?? .sevenZ
        let level = CompressionLevel(
            rawValue: defaults.object(forKey: "defaultLevel") as? Int ?? CompressionLevel.normal.rawValue
        ) ?? .normal

        _selectedFiles = State(initialValue: Self.uniqueURLs(initialFiles))
        _outputPath = State(initialValue: "")
        _format = State(initialValue: format)
        _level = State(initialValue: level)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Create Archive")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // File selection
                    GroupBox("Files to compress") {
                        VStack {
                            if selectedFiles.isEmpty {
                                dropZone
                            } else {
                                fileList
                            }

                            HStack {
                                Button("Add Files...") {
                                    addFiles()
                                }
                                Button("Add Folder...") {
                                    addFolder()
                                }
                                Spacer()
                                if !selectedFiles.isEmpty {
                                    Button("Clear All") {
                                        selectedFiles.removeAll()
                                        outputPath = ""
                                    }
                                    .foregroundColor(.red)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .padding(8)
                    }

                    // Output settings
                    GroupBox("Output") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Save as:")
                                TextField("Archive path", text: $outputPath)
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse...") {
                                    chooseOutputPath()
                                }
                            }

                            HStack {
                                Text("Format:")
                                Picker("", selection: $format) {
                                    ForEach(ArchiveFormat.allCases) { fmt in
                                        Text(fmt.displayName).tag(fmt)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 150)
                                .onChange(of: format) { _ in
                                    updateOutputExtension()
                                }

                                Spacer()

                                Text("Level:")
                                Picker("", selection: $level) {
                                    ForEach(CompressionLevel.allCases) { lvl in
                                        Text(lvl.displayName).tag(lvl)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 200)
                            }
                        }
                        .padding(8)
                    }

                    // Encryption
                    GroupBox("Encryption (optional)") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Password:")
                                SecureField("Enter password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 250)
                            }

                            if !password.isEmpty && (format == .sevenZ) {
                                Toggle("Encrypt file names", isOn: $encryptHeaders)
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            HStack {
                if isCompressing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Compressing...")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    if isCompressing {
                        archiveManager.cancel()
                    }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Compress") {
                    startCompression()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFiles.isEmpty || outputPath.isEmpty || isCompressing)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 600, height: 550)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Archive Created", isPresented: $showSuccess) {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
                dismiss()
            }
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Archive has been created successfully.")
        }
        .onAppear {
            updateOutputPath()
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 36))
                .foregroundColor(isDraggingOver ? .accentColor : .secondary)
            Text("Drag files here or use buttons below")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDraggingOver ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            ForEach(selectedFiles, id: \.self) { url in
                HStack {
                    Image(systemName: url.hasDirectoryPath ? "folder.fill" : "doc.fill")
                        .foregroundColor(url.hasDirectoryPath ? .accentColor : .secondary)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .onDelete { indices in
                selectedFiles.remove(atOffsets: indices)
            }
        }
        .frame(height: min(CGFloat(selectedFiles.count) * 28 + 16, 150))
        .listStyle(.bordered)
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Actions

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            appendSelectedFiles(panel.urls)
            updateOutputPath()
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            appendSelectedFiles(panel.urls)
            updateOutputPath()
        }
    }

    private func chooseOutputPath() {
        let panel = NSSavePanel()
        panel.title = "Save Archive As"
        panel.nameFieldStringValue = URL(fileURLWithPath: outputPath).lastPathComponent
        panel.allowedContentTypes = [
            UTType(filenameExtension: format.fileExtension) ?? .data
        ]
        panel.allowsOtherFileTypes = true

        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
        }
    }

    private func updateOutputPath() {
        guard outputPath.isEmpty, let firstFile = selectedFiles.first else { return }
        let dir = firstFile.deletingLastPathComponent().path
        let baseName: String
        if selectedFiles.count == 1 {
            baseName = firstFile.deletingPathExtension().lastPathComponent
        } else {
            baseName = "Archive"
        }
        outputPath = "\(dir)/\(baseName).\(format.fileExtension)"
    }

    private func updateOutputExtension() {
        guard !outputPath.isEmpty else { return }
        let url = URL(fileURLWithPath: outputPath)
        let dir = url.deletingLastPathComponent().path
        var baseName = url.deletingPathExtension().lastPathComponent
        // Remove double extensions like .tar from .tar.gz
        for ext in ["tar"] {
            if baseName.hasSuffix(".\(ext)") {
                baseName = String(baseName.dropLast(ext.count + 1))
            }
        }
        outputPath = "\(dir)/\(baseName).\(format.fileExtension)"
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        appendSelectedFiles([url])
                        updateOutputPath()
                    }
                }
            }
        }
        return true
    }

    private func startCompression() {
        isCompressing = true
        let files = selectedFiles.map { $0.path }

        Task {
            do {
                try await archiveManager.compress(
                    files: files,
                    to: outputPath,
                    format: format,
                    level: level,
                    password: password.isEmpty ? nil : password,
                    encrypt: encryptHeaders
                )
                isCompressing = false
                showSuccess = true
            } catch {
                isCompressing = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func appendSelectedFiles(_ urls: [URL]) {
        let merged = selectedFiles + urls
        selectedFiles = Self.uniqueURLs(merged)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.path).inserted
        }
    }
}
