import SwiftUI
import UniformTypeIdentifiers
import Combine
import UserNotifications

struct MainWindow: View {
    @EnvironmentObject var archiveManager: ArchiveManager
    @EnvironmentObject var actionRouter: AppActionRouter
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
    @State private var pendingCompressionFiles: [URL] = []
    @State private var pendingExtractArchivePath: String?
    @State private var activeExternalAction: AppOpenAction?
    @State private var resumeExternalQueueAfterPasswordPrompt = false

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
            } else if archiveManager.currentOperationKind == .listing && archiveManager.isLoading {
                loadingView
            } else {
                archiveBrowserView
            }

            Divider()

            // Status bar
            statusBarView
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task {
            await archiveManager.refreshEngineDetails()
            processQueuedActionsIfPossible()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDraggingOver {
                dropOverlayView
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if archiveManager.currentOperationKind.supportsProgress,
               let progress = archiveManager.progress {
                operationProgressView(progress)
                    .padding(.trailing, 18)
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showCompressSheet, onDismiss: {
            pendingCompressionFiles = []
            if case .compressFiles? = activeExternalAction {
                finishQueuedExternalAction()
            } else {
                processQueuedActionsIfPossible()
            }
        }) {
            CompressView(initialFiles: pendingCompressionFiles)
                .environmentObject(archiveManager)
        }
        .sheet(isPresented: $showExtractSheet, onDismiss: {
            pendingExtractArchivePath = nil
            if case .extractArchives(_, .prompt)? = activeExternalAction {
                finishQueuedExternalAction()
            } else {
                processQueuedActionsIfPossible()
            }
        }) {
            ExtractView(archivePath: pendingExtractArchivePath ?? currentArchivePath ?? "")
                .environmentObject(archiveManager)
        }
        .alert("Password Required", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $password)
            Button("OK") {
                if let path = currentArchivePath {
                    openArchive(
                        path: path,
                        password: password,
                        lockExternalQueueOnPasswordPrompt: resumeExternalQueueAfterPasswordPrompt
                    ) {
                        if resumeExternalQueueAfterPasswordPrompt {
                            resumeExternalQueueAfterPasswordPrompt = false
                            finishQueuedExternalAction()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                if resumeExternalQueueAfterPasswordPrompt {
                    resumeExternalQueueAfterPasswordPrompt = false
                    finishQueuedExternalAction()
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .compressFiles)) { notification in
            if let urls = notification.object as? [URL] {
                pendingCompressionFiles = uniqueURLs(urls)
            } else {
                pendingCompressionFiles = []
            }
            showCompressSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .extractAll)) { _ in
            if currentArchivePath != nil {
                pendingExtractArchivePath = currentArchivePath
                showExtractSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .testArchive)) { _ in
            if let path = currentArchivePath {
                testArchive(path: path)
            }
        }
        .onReceive(actionRouter.$pendingActions) { _ in
            processQueuedActionsIfPossible()
        }
        .onChange(of: archiveManager.isLoading) { isLoading in
            if !isLoading {
                processQueuedActionsIfPossible()
            }
        }
        .onChange(of: showPasswordPrompt) { isPresented in
            if !isPresented && !resumeExternalQueueAfterPasswordPrompt {
                processQueuedActionsIfPossible()
            }
        }
        .onChange(of: showError) { isPresented in
            if !isPresented {
                processQueuedActionsIfPossible()
            }
        }
        .onChange(of: showTestResult) { isPresented in
            if !isPresented {
                processQueuedActionsIfPossible()
            }
        }
        .navigationTitle(currentArchivePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "SeptaZip")
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    showOpenPanel()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .help("Open an archive file")

                Button {
                    pendingExtractArchivePath = currentArchivePath
                    showExtractSheet = true
                } label: {
                    Label("Extract", systemImage: "arrow.down.doc")
                }
                .disabled(currentArchivePath == nil)
                .help("Extract files from archive")

                Button {
                    pendingCompressionFiles = []
                    showCompressSheet = true
                } label: {
                    Label("Compress", systemImage: "archivebox")
                }
                .help("Create a new archive")

                Button {
                    if let path = currentArchivePath {
                        testArchive(path: path)
                    }
                } label: {
                    Label("Test", systemImage: "checkmark.shield")
                }
                .disabled(currentArchivePath == nil)
                .help("Test archive integrity")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
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
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .padding(.top, 6)
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        GeometryReader { proxy in
            ViewThatFits(in: .vertical) {
                welcomeContent(compact: false)
                welcomeContent(compact: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, proxy.size.width > 1050 ? 36 : 24)
            .padding(.vertical, proxy.size.height > 660 ? 32 : 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color(nsColor: .textBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private func welcomeContent(compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 22) {
            VStack(spacing: compact ? 12 : 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: compact ? 60 : 92, height: compact ? 60 : 92)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: compact ? 10 : 16, y: compact ? 4 : 8)

                VStack(spacing: compact ? 6 : 8) {
                    Text("SeptaZip")
                        .font(.system(size: compact ? 28 : 34, weight: .semibold, design: .rounded))

                    Text("Browse, extract, test, and compress archives with the official 7-Zip engine on macOS.")
                        .font(compact ? .body : .title3)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: compact ? 560 : 620)
                }
            }

            HStack(spacing: 14) {
                Button("Open Archive") {
                    showOpenPanel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(compact ? .regular : .large)

                Button("Compress Files") {
                    pendingCompressionFiles = []
                    showCompressSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(compact ? .regular : .large)
            }

            if compact {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    welcomeFeatureCard(
                        title: "Archive Browser",
                        detail: "Open ZIP, 7z, RAR, TAR, DMG, ISO, and more.",
                        systemImage: "square.stack.3d.up.fill",
                        compact: true
                    )
                    welcomeFeatureCard(
                        title: "Finder Actions",
                        detail: "Right-click integration for extract, compress, and test.",
                        systemImage: "cursorarrow.click.2",
                        compact: true
                    )
                    welcomeFeatureCard(
                        title: "Official Engine",
                        detail: archiveManager.engineDetails?.buildSummary ?? "Built on bundled 7-Zip.",
                        systemImage: "shippingbox.fill",
                        compact: true
                    )
                }
            } else {
                HStack(spacing: 14) {
                    welcomeFeatureCard(
                        title: "Archive Browser",
                        detail: "Open ZIP, 7z, RAR, TAR, DMG, ISO, and more.",
                        systemImage: "square.stack.3d.up.fill",
                        compact: false
                    )
                    welcomeFeatureCard(
                        title: "Finder Actions",
                        detail: "Right-click integration for extract, compress, and test.",
                        systemImage: "cursorarrow.click.2",
                        compact: false
                    )
                    welcomeFeatureCard(
                        title: "Official Engine",
                        detail: archiveManager.engineDetails?.buildSummary ?? "Built on bundled 7-Zip.",
                        systemImage: "shippingbox.fill",
                        compact: false
                    )
                }
            }

            VStack(spacing: compact ? 6 : 10) {
                Text("Supported formats")
                    .font((compact ? Font.caption : Font.caption.weight(.semibold)))
                    .foregroundColor(.secondary)

                Text("7z, ZIP, RAR, TAR, GZ, BZ2, XZ, ZSTD, ISO, DMG, WIM, and 40+ more")
                    .font(compact ? .caption2 : .caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Archive Browser

    private var archiveBrowserView: some View {
        Table(filteredItems, selection: $selectedItems) {
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
                currentPath = item.path
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 14) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 34))
                .foregroundColor(.accentColor)
            ProgressView()
                .controlSize(.large)
            Text("Loading archive...")
                .font(.headline)
            Text("SeptaZip is reading the archive catalog.")
                .foregroundColor(.secondary)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var statusBarView: some View {
        HStack {
            if let info = archiveManager.archiveInfo {
                statusPill("\(info.totalFiles) files · \(info.totalFolders) folders")
                statusPill("Size \(info.formattedTotalSize)")
                statusPill("Packed \(info.formattedPhysicalSize)")
                statusPill("Ratio \(info.overallRatio)")
                statusPill(info.type)
            } else {
                statusPill("Ready")
            }
            Spacer()
            if archiveManager.currentOperationKind.supportsProgress,
               let progress = archiveManager.progress {
                statusPill("\(Int(progress.percentage.rounded()))%")
                ProgressView(value: progress.percentage, total: 100)
                    .frame(width: 90)
            } else if archiveManager.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    // MARK: - Drop Overlay

    private var dropOverlayView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))

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

    private func welcomeFeatureCard(title: String, detail: String, systemImage: String, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(compact ? .headline : .title3)
                .foregroundColor(.accentColor)

            Text(title)
                .font(compact ? .subheadline.weight(.semibold) : .headline)

            Text(detail)
                .font(compact ? .caption : .subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, minHeight: compact ? 88 : 138, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func operationProgressView(_ progress: ArchiveProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(archiveManager.currentOperationTitle)
                        .font(.headline)
                    Text(progress.currentFile)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("\(Int(progress.percentage.rounded()))%")
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
            }

            ProgressView(value: progress.percentage, total: 100)
                .progressViewStyle(.linear)

            HStack {
                Spacer()
                Button("Cancel") {
                    archiveManager.cancel()
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 8)
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            )
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

    private var isPresentingModalUI: Bool {
        showCompressSheet || showExtractSheet || showPasswordPrompt || showError || showTestResult
    }

    private func processQueuedActionsIfPossible() {
        guard activeExternalAction == nil else { return }
        guard !archiveManager.isLoading else { return }
        guard !isPresentingModalUI else { return }
        guard let nextAction = actionRouter.dequeue() else { return }

        activeExternalAction = nextAction
        handleExternalAction(nextAction)
    }

    private func finishQueuedExternalAction() {
        activeExternalAction = nil
        processQueuedActionsIfPossible()
    }

    private func showBackgroundNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func handleExternalOperationError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }

    private func openArchive(
        path: String,
        password: String? = nil,
        lockExternalQueueOnPasswordPrompt: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        currentArchivePath = path
        currentPath = ""
        selectedItems = []
        searchText = ""
        pendingExtractArchivePath = nil

        Task {
            do {
                try await archiveManager.listArchive(at: path, password: password)
                completion?()
            } catch ArchiveError.passwordRequired {
                if lockExternalQueueOnPasswordPrompt {
                    resumeExternalQueueAfterPasswordPrompt = true
                }
                showPasswordPrompt = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                completion?()
            }
        }
    }

    private func testArchive(path: String, completion: (() -> Void)? = nil) {
        Task {
            do {
                testPassed = try await archiveManager.testArchive(at: path)
            } catch {
                testPassed = false
            }
            showTestResult = true
            completion?()
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
                pendingCompressionFiles = uniqueURLs(urls)
                showCompressSheet = true
            }
        }
        return true
    }

    private func handleExternalAction(_ action: AppOpenAction) {
        switch action {
        case .openArchive(let url):
            openArchive(
                path: url.path,
                lockExternalQueueOnPasswordPrompt: true
            ) {
                finishQueuedExternalAction()
            }
        case .compressFiles(let urls):
            pendingCompressionFiles = uniqueURLs(urls)
            showCompressSheet = true
        case .quickCompress:
            finishQueuedExternalAction()
        case .extractArchives(let urls, let mode):
            handleExternalExtract(urls: uniqueURLs(urls), mode: mode)
        case .testArchives:
            finishQueuedExternalAction()
        }
    }

    private func handleExternalExtract(urls: [URL], mode: ExternalExtractMode) {
        let archiveURLs = urls.filter { !$0.hasDirectoryPath }
        guard !archiveURLs.isEmpty else {
            finishQueuedExternalAction()
            return
        }

        switch mode {
        case .prompt:
            pendingExtractArchivePath = archiveURLs[0].path
            showExtractSheet = true
        case .sameFolder, .subfolder:
            finishQueuedExternalAction()
        }
    }

    private func extractDestination(for url: URL, mode: ExternalExtractMode) throws -> String {
        let parentDirectory = url.deletingLastPathComponent()

        switch mode {
        case .sameFolder:
            return parentDirectory.path
        case .subfolder:
            let destination = parentDirectory.appendingPathComponent(
                url.deletingPathExtension().lastPathComponent,
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            return destination.path
        case .prompt:
            return parentDirectory.path
        }
    }

    private func completeExternalArchiveOperation(revealPath: String, isFile: Bool = false) {
        if isFile {
            NSWorkspace.shared.selectFile(revealPath, inFileViewerRootedAtPath: "")
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: revealPath)
        }
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.path).inserted
        }
    }

    private func isArchiveFile(_ ext: String) -> Bool {
        let archiveExtensions = ["7z", "zip", "rar", "tar", "gz", "bz2", "xz",
                                  "iso", "dmg", "wim", "cab", "zst", "lzma", "lz"]
        return archiveExtensions.contains(ext.lowercased())
    }
}

private final class ExternalProgressPanelModel: ObservableObject {
    @Published var title = "Working"
    @Published var currentFile = ""
    @Published var percentage = 0.0
    var cancelAction: (() -> Void)?
}

private struct ExternalProgressPanelView: View {
    @ObservedObject var model: ExternalProgressPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.headline)
                    Text(model.currentFile)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("\(Int(model.percentage.rounded()))%")
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: model.percentage, total: 100)
                .progressViewStyle(.linear)

            HStack {
                Spacer()
                Button("Cancel") {
                    model.cancelAction?()
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial)
    }
}
