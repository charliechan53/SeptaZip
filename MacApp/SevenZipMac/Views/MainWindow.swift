import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @EnvironmentObject var archiveManager: ArchiveManager
    @State private var currentArchivePath: String?
    @State private var selectedItems: Set<ArchiveItem.ID> = []
    @State private var searchText = ""
    @State private var showCompressSheet = false
    @State private var showExtractSheet = false
    @State private var showPasswordPrompt = false
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTestResult = false
    @State private var testPassed = false
    @State private var currentPath = "" // For navigating inside archive
    @State private var isDraggingOver = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar area
            toolbarView

            Divider()

            // Breadcrumb navigation
            if currentArchivePath != nil {
                breadcrumbView
                Divider()
            }

            // Main content
            if currentArchivePath == nil {
                welcomeView
            } else if archiveManager.isLoading {
                loadingView
            } else {
                archiveBrowserView
            }

            Divider()

            // Status bar
            statusBarView
        }
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDraggingOver {
                dropOverlayView
            }
        }
        .sheet(isPresented: $showCompressSheet) {
            CompressView()
                .environmentObject(archiveManager)
        }
        .sheet(isPresented: $showExtractSheet) {
            ExtractView(archivePath: currentArchivePath ?? "")
                .environmentObject(archiveManager)
        }
        .alert("Password Required", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $password)
            Button("OK") {
                if let path = currentArchivePath {
                    openArchive(path: path, password: password)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This archive is encrypted. Enter the password to open it.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert(testPassed ? "Test Passed" : "Test Failed", isPresented: $showTestResult) {
            Button("OK") {}
        } message: {
            Text(testPassed
                 ? "Archive integrity check passed. All files are OK."
                 : "Archive integrity check failed. The archive may be corrupted.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openArchive)) { notification in
            if let path = notification.object as? String {
                openArchive(path: path)
            } else {
                showOpenPanel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .compressFiles)) { _ in
            showCompressSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .extractAll)) { _ in
            if currentArchivePath != nil {
                showExtractSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .testArchive)) { _ in
            if let path = currentArchivePath {
                testArchive(path: path)
            }
        }
        .navigationTitle(currentArchivePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "7-Zip")
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Open button
            Button {
                showOpenPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open an archive file")

            // Extract button
            Button {
                showExtractSheet = true
            } label: {
                Label("Extract", systemImage: "arrow.down.doc")
            }
            .disabled(currentArchivePath == nil)
            .help("Extract files from archive")

            // Compress button
            Button {
                showCompressSheet = true
            } label: {
                Label("Compress", systemImage: "arrow.up.doc")
            }
            .help("Create a new archive")

            // Test button
            Button {
                if let path = currentArchivePath {
                    testArchive(path: path)
                }
            } label: {
                Label("Test", systemImage: "checkmark.shield")
            }
            .disabled(currentArchivePath == nil)
            .help("Test archive integrity")

            Spacer()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 200)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.textBackgroundColor)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Breadcrumb

    private var breadcrumbView: some View {
        HStack(spacing: 4) {
            Button {
                currentPath = ""
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            if !currentPath.isEmpty {
                let components = currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        currentPath = components[0...index].joined(separator: "/")
                    } label: {
                        Text(component)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(index == components.count - 1 ? .primary : .accentColor)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.zipper")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("7-Zip for Mac")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Open an archive or drag files here to compress")
                .font(.title3)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Button("Open Archive") {
                    showOpenPanel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Compress Files") {
                    showCompressSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            // Supported formats
            VStack(spacing: 8) {
                Text("Supported formats")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, WIM, and 40+ more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.textBackgroundColor))
    }

    // MARK: - Archive Browser

    private var archiveBrowserView: some View {
        Table(filteredItems, selection: $selectedItems, sortOrder: .constant([])) {
            TableColumn("Name") { item in
                HStack(spacing: 6) {
                    Image(systemName: item.iconName)
                        .foregroundColor(item.isDirectory ? .accentColor : .secondary)
                        .frame(width: 16)

                    Text(item.name)
                        .lineLimit(1)

                    if item.encrypted {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .width(min: 200, ideal: 350)

            TableColumn("Size") { item in
                Text(item.formattedSize)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Packed") { item in
                Text(item.formattedCompressedSize)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Ratio") { item in
                Text(item.ratio)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Modified") { item in
                if let date = item.modified {
                    Text(date, style: .date)
                        .foregroundColor(.secondary)
                } else {
                    Text("--")
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 80, ideal: 120)

            TableColumn("Method") { item in
                Text(item.method)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .width(min: 50, ideal: 80)
        }
        .contextMenu(forSelectionType: ArchiveItem.ID.self) { items in
            if !items.isEmpty {
                Button("Extract Selected...") {
                    extractSelected(items)
                }
                Divider()
                Button("Copy Path") {
                    copyPaths(items)
                }
            }
        } primaryAction: { items in
            // Double-click to navigate into directories
            if let itemId = items.first,
               let item = archiveManager.items.first(where: { $0.id == itemId }),
               item.isDirectory {
                if currentPath.isEmpty {
                    currentPath = item.path
                } else {
                    currentPath = item.path
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading archive...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.textBackgroundColor))
    }

    // MARK: - Status Bar

    private var statusBarView: some View {
        HStack {
            if let info = archiveManager.archiveInfo {
                Text("\(info.totalFiles) files, \(info.totalFolders) folders")
                Text("·")
                Text("Size: \(info.formattedTotalSize)")
                Text("·")
                Text("Packed: \(info.formattedPhysicalSize)")
                Text("·")
                Text("Ratio: \(info.overallRatio)")
                Text("·")
                Text("Type: \(info.type)")
            } else {
                Text("Ready")
            }
            Spacer()
            if archiveManager.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Drop Overlay

    private var dropOverlayView: some View {
        ZStack {
            Color.accentColor.opacity(0.1)

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                Text("Drop files to compress")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
        .cornerRadius(12)
        .padding(20)
    }

    // MARK: - Computed Properties

    private var filteredItems: [ArchiveItem] {
        var items = archiveManager.items

        // Filter by current path (show only items in current directory)
        if !currentPath.isEmpty {
            items = items.filter { item in
                let parent = item.parentPath
                return parent == currentPath || parent == currentPath + "/"
            }
        } else {
            // At root level, show only top-level items
            items = items.filter { item in
                !item.path.contains("/") ||
                (item.isDirectory && !item.path.dropLast().contains("/"))
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            // When searching, search ALL items regardless of current path
            items = archiveManager.items.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort: directories first, then alphabetically
        items.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return items
    }

    // MARK: - Actions

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Archive"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "7z")!,
            UTType(filenameExtension: "zip")!,
            UTType(filenameExtension: "rar")!,
            UTType(filenameExtension: "tar")!,
            UTType(filenameExtension: "gz")!,
            UTType(filenameExtension: "bz2")!,
            UTType(filenameExtension: "xz")!,
            UTType(filenameExtension: "iso")!,
            UTType(filenameExtension: "dmg")!,
            UTType(filenameExtension: "wim")!,
            UTType(filenameExtension: "cab")!,
            UTType(filenameExtension: "rpm")!,
            UTType(filenameExtension: "deb")!,
            UTType(filenameExtension: "zst")!,
        ]
        panel.allowsOtherFileTypes = true

        if panel.runModal() == .OK, let url = panel.url {
            openArchive(path: url.path)
        }
    }

    private func openArchive(path: String, password: String? = nil) {
        currentArchivePath = path
        currentPath = ""
        selectedItems = []
        searchText = ""

        Task {
            do {
                try await archiveManager.listArchive(at: path, password: password)
            } catch ArchiveError.passwordRequired {
                showPasswordPrompt = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func testArchive(path: String) {
        Task {
            do {
                testPassed = try await archiveManager.testArchive(at: path)
            } catch {
                testPassed = false
            }
            showTestResult = true
        }
    }

    private func extractSelected(_ itemIds: Set<ArchiveItem.ID>) {
        let files = archiveManager.items
            .filter { itemIds.contains($0.id) }
            .map { $0.path }

        guard !files.isEmpty, let archivePath = currentArchivePath else { return }

        let panel = NSOpenPanel()
        panel.title = "Extract To"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await archiveManager.extractFiles(
                        archive: archivePath,
                        files: files,
                        to: url.path
                    )
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func copyPaths(_ itemIds: Set<ArchiveItem.ID>) {
        let paths = archiveManager.items
            .filter { itemIds.contains($0.id) }
            .map { $0.path }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            if urls.count == 1, isArchiveFile(urls[0].pathExtension) {
                // Single archive file dropped - open it
                openArchive(path: urls[0].path)
            } else {
                // Multiple files or non-archive - offer to compress
                showCompressSheet = true
            }
        }
        return true
    }

    private func isArchiveFile(_ ext: String) -> Bool {
        let archiveExtensions = ["7z", "zip", "rar", "tar", "gz", "bz2", "xz",
                                  "iso", "dmg", "wim", "cab", "zst", "lzma", "lz"]
        return archiveExtensions.contains(ext.lowercased())
    }
}
