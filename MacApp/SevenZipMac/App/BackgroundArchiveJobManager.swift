import AppKit
import Combine
import SwiftUI
import UserNotifications

enum BackgroundArchiveJobState: Equatable {
    case running
    case completed
    case failed(String)
    case cancelled

    var summaryText: String {
        switch self {
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }
}

@MainActor
final class BackgroundArchiveJob: ObservableObject, Identifiable {
    let id = UUID()
    let archiveManager = ArchiveManager()
    let action: AppOpenAction
    let label: String

    @Published private(set) var title: String
    @Published private(set) var progress: ArchiveProgress?
    @Published private(set) var state: BackgroundArchiveJobState = .running
    @Published private(set) var kind: ArchiveOperationKind = .idle

    private(set) var createdAt = Date()
    private(set) var finishedAt: Date?
    private var cancellables = Set<AnyCancellable>()

    init(action: AppOpenAction, label: String) {
        self.action = action
        self.label = label
        self.title = label

        archiveManager.$currentOperationTitle
            .sink { [weak self] value in
                guard let self, !value.isEmpty, value != "Ready" else { return }
                self.title = value
            }
            .store(in: &cancellables)

        archiveManager.$progress
            .sink { [weak self] value in
                self?.progress = value
            }
            .store(in: &cancellables)

        archiveManager.$currentOperationKind
            .sink { [weak self] value in
                self?.kind = value
            }
            .store(in: &cancellables)
    }

    var isRunning: Bool {
        if case .running = state {
            return true
        }
        return false
    }

    var progressValue: Double {
        switch state {
        case .completed:
            return 100
        case .running:
            return progress?.percentage ?? 0
        case .failed, .cancelled:
            return progress?.percentage ?? 0
        }
    }

    var detailText: String {
        switch state {
        case .running:
            if let currentFile = progress?.currentFile, !currentFile.isEmpty {
                return currentFile
            }
            return label
        case .completed:
            return "Completed"
        case .failed(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }

    func markCompleted() {
        state = .completed
        finishedAt = Date()
        progress = ArchiveProgress(
            percentage: 100,
            currentFile: progress?.currentFile ?? label,
            bytesProcessed: progress?.bytesProcessed ?? 0,
            bytesTotal: progress?.bytesTotal ?? 0
        )
    }

    func markFailed(_ error: Error) {
        state = .failed(error.localizedDescription)
        finishedAt = Date()
    }

    func markCancelled() {
        state = .cancelled
        finishedAt = Date()
    }

}

@MainActor
final class BackgroundArchiveJobManager: ObservableObject {
    static let shared = BackgroundArchiveJobManager()

    @Published private(set) var jobs: [BackgroundArchiveJob] = []

    private let completionRetention: TimeInterval = 8

    private init() {}

    var visibleJobs: [BackgroundArchiveJob] {
        let now = Date()
        return jobs.filter { job in
            if job.isRunning {
                return true
            }
            guard let finishedAt = job.finishedAt else { return false }
            return now.timeIntervalSince(finishedAt) <= completionRetention
        }
    }

    func handle(_ action: AppOpenAction) -> Bool {
        guard action.isBackgroundJob else { return false }

        switch action {
        case .quickCompress(let urls, let format):
            startCompressionJob(for: uniqueURLs(urls), format: format)
        case .extractArchives(let urls, let mode):
            for url in uniqueURLs(urls).filter({ !$0.hasDirectoryPath }) {
                startExtractionJob(for: url, mode: mode)
            }
        case .testArchives(let urls):
            for url in uniqueURLs(urls).filter({ !$0.hasDirectoryPath }) {
                startTestJob(for: url)
            }
        case .openArchive, .compressFiles:
            return false
        }

        return true
    }

    private func startCompressionJob(for urls: [URL], format: ArchiveFormat) {
        guard !urls.isEmpty else { return }

        let outputPath = suggestedArchivePath(for: urls, format: format)
        let label = "Compress \(URL(fileURLWithPath: outputPath).lastPathComponent)"
        let job = makeJob(action: .quickCompress(urls, format), label: label)

        Task { @MainActor [weak self, weak job] in
            guard let self, let job else { return }
            do {
                try await job.archiveManager.compress(
                    files: urls.map(\.path),
                    to: outputPath,
                    format: format
                )
                self.complete(job, notificationTitle: "Archive Created", notificationBody: URL(fileURLWithPath: outputPath).lastPathComponent)
            } catch ArchiveError.cancelled {
                self.cancelJob(job)
            } catch {
                self.fail(job, error: error)
            }
        }
    }

    private func startExtractionJob(for url: URL, mode: ExternalExtractMode) {
        let label = "Extract \(url.lastPathComponent)"
        let job = makeJob(action: .extractArchives([url], mode), label: label)

        Task { @MainActor [weak self, weak job] in
            guard let self, let job else { return }
            do {
                let destination = try self.extractDestination(for: url, mode: mode)
                try await job.archiveManager.extract(
                    archive: url.path,
                    to: destination,
                    overwrite: true
                )
                self.complete(job, notificationTitle: "Archive Extracted", notificationBody: url.lastPathComponent)
            } catch ArchiveError.cancelled {
                self.cancelJob(job)
            } catch {
                self.fail(job, error: error)
            }
        }
    }

    private func startTestJob(for url: URL) {
        let label = "Test \(url.lastPathComponent)"
        let job = makeJob(action: .testArchives([url]), label: label)

        Task { @MainActor [weak self, weak job] in
            guard let self, let job else { return }
            do {
                let passed = try await job.archiveManager.testArchive(at: url.path)
                if passed {
                    self.complete(job, notificationTitle: "Archive Test Passed", notificationBody: url.lastPathComponent)
                } else {
                    self.fail(job, error: ArchiveError.operationFailed("Archive integrity check failed."))
                }
            } catch ArchiveError.cancelled {
                self.cancelJob(job)
            } catch {
                self.fail(job, error: error)
            }
        }
    }

    private func makeJob(action: AppOpenAction, label: String) -> BackgroundArchiveJob {
        let job = BackgroundArchiveJob(action: action, label: label)
        jobs.append(job)
        pruneFinishedJobs()
        BackgroundArchiveJobsPanelController.shared.present(using: self)
        return job
    }

    private func complete(_ job: BackgroundArchiveJob, notificationTitle: String, notificationBody: String) {
        job.markCompleted()
        postNotification(title: notificationTitle, body: notificationBody)
        finish(job)
    }

    private func fail(_ job: BackgroundArchiveJob, error: Error) {
        job.markFailed(error)
        postNotification(title: job.title, body: error.localizedDescription)
        finish(job)
    }

    func cancelJob(_ job: BackgroundArchiveJob) {
        guard job.isRunning else { return }
        job.archiveManager.cancel()
        job.markCancelled()
        finish(job)
    }

    private func finish(_ job: BackgroundArchiveJob) {
        pruneFinishedJobs()
        BackgroundArchiveJobsPanelController.shared.present(using: self)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(completionRetention * 1_000_000_000))
            self?.pruneFinishedJobs()
            if let self {
                BackgroundArchiveJobsPanelController.shared.present(using: self)
            }
        }
    }

    private func pruneFinishedJobs() {
        let now = Date()
        jobs = jobs.filter { job in
            if job.isRunning {
                return true
            }
            guard let finishedAt = job.finishedAt else { return false }
            return now.timeIntervalSince(finishedAt) <= completionRetention
        }
    }

    private func postNotification(title: String, body: String) {
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

    private func suggestedArchivePath(for urls: [URL], format: ArchiveFormat) -> String {
        let firstURL = urls[0]
        let directory = firstURL.deletingLastPathComponent().path
        let baseName: String

        if urls.count == 1 {
            baseName = firstURL.deletingPathExtension().lastPathComponent
        } else {
            baseName = "Archive"
        }

        return "\(directory)/\(baseName).\(format.fileExtension)"
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.path).inserted
        }
    }

}

private struct BackgroundArchiveJobsPanelView: View {
    @ObservedObject var manager: BackgroundArchiveJobManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SeptaZip Jobs")
                    .font(.headline)
                Spacer()
                Text("\(manager.visibleJobs.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            ForEach(manager.visibleJobs) { job in
                BackgroundArchiveJobRow(job: job) {
                    manager.cancelJob(job)
                }
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial)
    }
}

private struct BackgroundArchiveJobRow: View {
    @ObservedObject var job: BackgroundArchiveJob
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            ProgressView(value: job.progressValue, total: 100)
                .progressViewStyle(.linear)

            HStack(alignment: .top) {
                Text(job.detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Spacer()

                if job.isRunning {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var statusText: String {
        switch job.state {
        case .running:
            return "\(Int(job.progressValue.rounded()))%"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

@MainActor
private final class BackgroundArchiveJobsPanelController {
    static let shared = BackgroundArchiveJobsPanelController()

    private var panel: NSPanel?

    private init() {}

    func present(using manager: BackgroundArchiveJobManager) {
        let jobs = manager.visibleJobs
        guard !jobs.isEmpty else {
            panel?.orderOut(nil)
            return
        }

        let panel = panel ?? makePanel()
        let height = min(max(CGFloat(jobs.count) * 106 + 48, 148), 420)
        panel.setContentSize(NSSize(width: 340, height: height))
        panel.contentView = NSHostingView(rootView: BackgroundArchiveJobsPanelView(manager: manager))
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 148),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.maxX - panel.frame.width - 24,
            y: visibleFrame.maxY - panel.frame.height - 24
        )
        panel.setFrameOrigin(origin)
    }
}
