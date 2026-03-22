import Foundation
import Combine
import Security

/// Error types for archive operations.
enum ArchiveError: LocalizedError {
    case binaryNotFound
    case sandboxedBuildUnsupported
    case operationFailed(String)
    case parseError(String)
    case cancelled
    case passwordRequired
    case invalidArchive(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "7zz binary not found. Please rebuild the app or run the build script."
        case .sandboxedBuildUnsupported:
            return "This SeptaZip build is sandboxed. The app launches the bundled 7zz tool as a child process, and a sandboxed parent app cannot grant that child access to user-selected files. Rebuild or install an unsandboxed Release/direct-download build."
        case .operationFailed(let msg):
            return "Operation failed: \(msg)"
        case .parseError(let msg):
            return "Failed to parse output: \(msg)"
        case .cancelled:
            return "Operation was cancelled."
        case .passwordRequired:
            return "This archive requires a password."
        case .invalidArchive(let path):
            return "Not a valid archive: \(path)"
        }
    }
}

/// Progress information for archive operations.
struct ArchiveProgress {
    let percentage: Double
    let currentFile: String
    let bytesProcessed: UInt64
    let bytesTotal: UInt64
}

enum ArchiveOperationKind: Equatable {
    case idle
    case listing
    case extracting
    case compressing
    case testing

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .listing:
            return "Loading Archive"
        case .extracting:
            return "Extracting"
        case .compressing:
            return "Compressing"
        case .testing:
            return "Testing"
        }
    }

    var supportsProgress: Bool {
        switch self {
        case .extracting, .compressing, .testing:
            return true
        case .idle, .listing:
            return false
        }
    }
}

/// Runtime details for the bundled 7-Zip engine.
struct EngineDetails: Equatable {
    let versionNumber: String
    let architecture: String?
    let buildDate: String?
    let copyright: String?
    let runtimeLine: String
    let platformLine: String?
    let binaryPath: String

    var displayVersion: String {
        if let architecture {
            return "7-Zip \(versionNumber) (\(architecture))"
        }
        return "7-Zip \(versionNumber)"
    }

    var buildSummary: String {
        if let buildDate {
            return "\(displayVersion) · \(buildDate)"
        }
        return displayVersion
    }

    var diagnosticsText: String {
        [
            "Engine: \(displayVersion)",
            buildDate.map { "Build date: \($0)" },
            copyright.map { "Copyright: \($0)" },
            platformLine.map { "Platform: \($0)" },
            "Binary: \(binaryPath)",
            "Upstream: https://github.com/ip7z/7zip"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    static func parse(from output: String, binaryPath: String) -> EngineDetails {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let runtimeLine = lines.first ?? "7-Zip"
        let platformLine = lines.dropFirst().first
        let parts = runtimeLine.components(separatedBy: " : ")
        let runtimeDescriptor = parts.first ?? runtimeLine
        let versionDescriptor = runtimeDescriptor.replacingOccurrences(of: "7-Zip (z) ", with: "")

        let versionNumber: String
        let architecture: String?

        if let openParen = versionDescriptor.firstIndex(of: "("),
           let closeParen = versionDescriptor.lastIndex(of: ")"),
           openParen < closeParen {
            versionNumber = versionDescriptor[..<openParen]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            architecture = versionDescriptor[versionDescriptor.index(after: openParen)..<closeParen]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            versionNumber = versionDescriptor.trimmingCharacters(in: .whitespacesAndNewlines)
            architecture = nil
        }

        return EngineDetails(
            versionNumber: versionNumber.isEmpty ? "Unknown" : versionNumber,
            architecture: architecture,
            buildDate: parts.count > 2 ? parts[2] : nil,
            copyright: parts.count > 1 ? parts[1] : nil,
            runtimeLine: runtimeLine,
            platformLine: platformLine,
            binaryPath: binaryPath
        )
    }
}

/// Wraps the 7zz command-line binary for archive operations.
@MainActor
class ArchiveManager: ObservableObject {
    @Published var items: [ArchiveItem] = []
    @Published var archiveInfo: ArchiveInfo?
    @Published var isLoading = false
    @Published var error: ArchiveError?
    @Published var progress: ArchiveProgress?
    @Published var engineDetails: EngineDetails?
    @Published var engineDetailsError: String?
    @Published var isLoadingEngineDetails = false
    @Published private(set) var currentOperationKind: ArchiveOperationKind = .idle
    @Published private(set) var currentOperationTitle = "Ready"

    private var currentProcess: Process?

    private var isRunningSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }

        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.app-sandbox" as CFString,
            nil
        )

        return (value as? Bool) == true
    }

    private var bundledBinaryPath: String? {
        guard let bundlePath = Bundle.main.path(forResource: "7zz", ofType: nil),
              FileManager.default.isExecutableFile(atPath: bundlePath) else {
            return nil
        }
        return bundlePath
    }

    private var allowsExternalBinaryFallbacks: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["SEPTAZIP_ALLOW_EXTERNAL_7ZZ"] == "1"
        #endif
    }

    private var externalBinaryFallbacks: [String] {
        [
            "/usr/local/bin/7zz",
            "/opt/homebrew/bin/7zz",
            "\(NSHomeDirectory())/.local/bin/7zz"
        ]
    }

    /// Path to the 7zz binary bundled with the app.
    var binaryPath: String {
        if let bundledBinaryPath {
            return bundledBinaryPath
        }

        if allowsExternalBinaryFallbacks {
            for path in externalBinaryFallbacks {
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        return ""
    }

    /// Check if the 7zz binary is available.
    var isBinaryAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    var isUsingBundledBinary: Bool {
        guard !binaryPath.isEmpty else { return false }
        return binaryPath == bundledBinaryPath
    }

    func refreshEngineDetails(force: Bool = false) async {
        guard force || engineDetails == nil else { return }
        guard !isLoadingEngineDetails else { return }
        guard isBinaryAvailable else {
            engineDetails = nil
            engineDetailsError = ArchiveError.binaryNotFound.localizedDescription
            return
        }

        isLoadingEngineDetails = true
        defer { isLoadingEngineDetails = false }

        do {
            let output = try await execute7zz(args: ["i"], trackForCancellation: false)
            engineDetails = EngineDetails.parse(from: output, binaryPath: binaryPath)
            engineDetailsError = nil
        } catch {
            engineDetails = nil
            engineDetailsError = error.localizedDescription
        }
    }

    // MARK: - List Archive Contents

    /// List all items in an archive.
    func listArchive(at path: String, password: String? = nil) async throws {
        beginOperation(.listing, title: "Loading \(URL(fileURLWithPath: path).lastPathComponent)")
        error = nil
        defer { finishOperation() }

        var args = ["l", "-slt"]
        if let password = password {
            args.append("-p\(password)")
        }
        args.append(path)

        let output = try await run7zz(args: args)
        let (info, parsedItems) = try parseListOutput(output, archivePath: path)

        self.archiveInfo = info
        self.items = parsedItems
    }

    // MARK: - Extract

    /// Extract all files from an archive to a destination directory.
    func extract(archive: String, to destination: String, password: String? = nil,
                 overwrite: Bool = true) async throws {
        beginOperation(.extracting, title: "Extracting \(URL(fileURLWithPath: archive).lastPathComponent)")
        error = nil
        defer { finishOperation() }

        var args = ["x", "-bsp1", "-bb1"]
        if overwrite {
            args.append("-aoa") // overwrite all
        } else {
            args.append("-aos") // skip existing
        }
        args.append("-o\(destination)")
        if let password = password {
            args.append("-p\(password)")
        }
        args.append(archive)

        _ = try await run7zz(args: args)
    }

    /// Extract specific files from an archive.
    func extractFiles(archive: String, files: [String], to destination: String,
                      password: String? = nil) async throws {
        beginOperation(.extracting, title: "Extracting \(URL(fileURLWithPath: archive).lastPathComponent)")
        error = nil
        defer { finishOperation() }

        var args = ["x", "-bsp1", "-bb1", "-o\(destination)"]
        if let password = password {
            args.append("-p\(password)")
        }
        args.append(archive)
        args.append(contentsOf: files)

        _ = try await run7zz(args: args)
    }

    /// Extract archive to the same directory it's in.
    func extractHere(archive: String, password: String? = nil) async throws {
        let dir = (archive as NSString).deletingLastPathComponent
        let baseName = ((archive as NSString).lastPathComponent as NSString).deletingPathExtension
        let extractDir = "\(dir)/\(baseName)"

        try FileManager.default.createDirectory(atPath: extractDir,
                                                  withIntermediateDirectories: true)
        try await extract(archive: archive, to: extractDir, password: password)
    }

    // MARK: - Compress

    /// Create a new archive from files/directories.
    func compress(files: [String], to archivePath: String,
                  format: ArchiveFormat = .sevenZ,
                  level: CompressionLevel = .normal,
                  password: String? = nil,
                  encrypt: Bool = false) async throws {
        beginOperation(.compressing, title: "Compressing \(URL(fileURLWithPath: archivePath).lastPathComponent)")
        error = nil
        defer { finishOperation() }

        var args = ["a", "-bsp1", "-bb1"]
        args.append("-t\(format.typeFlag)")
        args.append("-mx=\(level.rawValue)")

        if let password = password, !password.isEmpty {
            args.append("-p\(password)")
            if encrypt {
                args.append("-mhe=on") // encrypt headers too
            }
        }

        args.append(archivePath)
        args.append(contentsOf: files)

        _ = try await run7zz(args: args)
    }

    // MARK: - Test

    /// Test archive integrity.
    func testArchive(at path: String, password: String? = nil) async throws -> Bool {
        beginOperation(.testing, title: "Testing \(URL(fileURLWithPath: path).lastPathComponent)")
        error = nil
        defer { finishOperation() }

        var args = ["t", "-bsp1", "-bb1"]
        if let password = password {
            args.append("-p\(password)")
        }
        args.append(path)

        let output = try await run7zz(args: args)
        return output.contains("Everything is Ok")
    }

    // MARK: - Cancel

    /// Cancel the current operation.
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        finishOperation()
        error = .cancelled
    }

    // MARK: - Private

    /// Execute the 7zz binary with arguments.
    private func run7zz(args: [String]) async throws -> String {
        try await execute7zz(args: args, trackForCancellation: true)
    }

    private func execute7zz(args: [String], trackForCancellation: Bool) async throws -> String {
        guard isBinaryAvailable else {
            throw ArchiveError.binaryNotFound
        }

        guard !isRunningSandboxed else {
            throw ArchiveError.sandboxedBuildUnsupported
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()
            let outputHandle = pipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            let lock = NSLock()
            var outputData = Data()
            var errorData = Data()

            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = errorPipe
            process.environment = ProcessInfo.processInfo.environment

            if trackForCancellation {
                self.currentProcess = process
            }

            outputHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock()
                outputData.append(chunk)
                lock.unlock()
                Task { @MainActor [weak self] in
                    self?.handleProgressChunk(chunk)
                }
            }

            errorHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock()
                errorData.append(chunk)
                lock.unlock()
                Task { @MainActor [weak self] in
                    self?.handleProgressChunk(chunk)
                }
            }

            process.terminationHandler = { [weak self] proc in
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil

                let trailingOutput = outputHandle.readDataToEndOfFile()
                let trailingError = errorHandle.readDataToEndOfFile()

                lock.lock()
                outputData.append(trailingOutput)
                errorData.append(trailingError)
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                lock.unlock()

                Task { @MainActor [weak self] in
                    if trackForCancellation {
                        self?.currentProcess = nil
                    }
                }

                let status = proc.terminationStatus
                if status == 0 || status == 1 {
                    // 0 = success, 1 = warning (non-fatal)
                    continuation.resume(returning: output)
                } else if errorOutput.contains("Wrong password") || errorOutput.contains("password") {
                    continuation.resume(throwing: ArchiveError.passwordRequired)
                } else {
                    let message = errorOutput.isEmpty ? output : errorOutput
                    continuation.resume(throwing: ArchiveError.operationFailed(
                        message.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                if trackForCancellation {
                    currentProcess = nil
                }
                continuation.resume(throwing: ArchiveError.operationFailed(error.localizedDescription))
            }
        }
    }

    private func beginOperation(_ kind: ArchiveOperationKind, title: String) {
        currentOperationKind = kind
        currentOperationTitle = title
        isLoading = true

        if kind.supportsProgress {
            progress = ArchiveProgress(
                percentage: 0,
                currentFile: "Preparing...",
                bytesProcessed: 0,
                bytesTotal: 0
            )
        } else {
            progress = nil
        }
    }

    private func finishOperation() {
        isLoading = false
        currentOperationKind = .idle
        currentOperationTitle = "Ready"
        progress = nil
    }

    private func handleProgressChunk(_ chunk: Data) {
        guard currentOperationKind.supportsProgress,
              let rawChunk = String(data: chunk, encoding: .utf8),
              !rawChunk.isEmpty else {
            return
        }

        let percentage = Self.parseProgressPercentage(from: rawChunk)
        let currentFile = Self.parseCurrentFile(from: rawChunk)

        guard percentage != nil || currentFile != nil else { return }

        Task { @MainActor in
            let existingProgress = self.progress ?? ArchiveProgress(
                percentage: 0,
                currentFile: "Preparing...",
                bytesProcessed: 0,
                bytesTotal: 0
            )

            self.progress = ArchiveProgress(
                percentage: percentage ?? existingProgress.percentage,
                currentFile: currentFile ?? existingProgress.currentFile,
                bytesProcessed: existingProgress.bytesProcessed,
                bytesTotal: existingProgress.bytesTotal
            )
        }
    }

    private static func parseProgressPercentage(from rawChunk: String) -> Double? {
        let pattern = #"(?<!\d)(100|[1-9]?\d)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(rawChunk.startIndex..<rawChunk.endIndex, in: rawChunk)
        let matches = regex.matches(in: rawChunk, range: range)
        guard let match = matches.last,
              let percentageRange = Range(match.range(at: 1), in: rawChunk),
              let percentage = Double(rawChunk[percentageRange]) else {
            return nil
        }

        return percentage
    }

    private static func parseCurrentFile(from rawChunk: String) -> String? {
        let cleanedChunk = rawChunk
            .replacingOccurrences(of: "\u{8}", with: "")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = cleanedChunk
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let pattern = #"[+\-]\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        for line in lines.reversed() {
            let searchRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: searchRange),
                  let valueRange = Range(match.range(at: 1), in: line) else {
                continue
            }

            return String(line[valueRange])
        }

        return nil
    }

    /// Parse the technical listing output of `7zz l -slt`.
    private func parseListOutput(_ output: String, archivePath: String) throws -> (ArchiveInfo, [ArchiveItem]) {
        var items: [ArchiveItem] = []
        let lines = output.components(separatedBy: "\n")

        // Parse archive-level info from header
        var archiveType = ""
        var physicalSize: UInt64 = 0
        var method = ""
        var solid = false
        var blocks = 0
        var headerSize: UInt64 = 0
        var archiveEncrypted = false

        // Parse file entries
        var currentEntry: [String: String] = [:]
        var inListing = false

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Archive header properties
            if trimmed.hasPrefix("Type = ") {
                archiveType = String(trimmed.dropFirst(7))
            } else if trimmed.hasPrefix("Physical Size = ") {
                physicalSize = UInt64(String(trimmed.dropFirst(16))) ?? 0
            } else if trimmed.hasPrefix("Method = ") {
                method = String(trimmed.dropFirst(9))
            } else if trimmed.hasPrefix("Solid = ") {
                solid = String(trimmed.dropFirst(8)) == "+"
            } else if trimmed.hasPrefix("Blocks = ") {
                blocks = Int(String(trimmed.dropFirst(9))) ?? 0
            } else if trimmed.hasPrefix("Headers Size = ") {
                headerSize = UInt64(String(trimmed.dropFirst(15))) ?? 0
            }

            // Detect start of file listing
            if trimmed == "----------" {
                inListing = true
                if !currentEntry.isEmpty {
                    if let item = makeArchiveItem(from: currentEntry, dateFormatter: dateFormatter) {
                        items.append(item)
                    }
                    currentEntry = [:]
                }
                continue
            }

            guard inListing else { continue }

            // Empty line separates entries
            if trimmed.isEmpty {
                if !currentEntry.isEmpty {
                    if let item = makeArchiveItem(from: currentEntry, dateFormatter: dateFormatter) {
                        items.append(item)
                    }
                    currentEntry = [:]
                }
                continue
            }

            // Parse "Key = Value" pairs
            if let eqRange = trimmed.range(of: " = ") {
                let key = String(trimmed[trimmed.startIndex..<eqRange.lowerBound])
                let value = String(trimmed[eqRange.upperBound...])
                currentEntry[key] = value
            } else if trimmed.contains(" = ") == false, let key = trimmed.components(separatedBy: " = ").first {
                // Handle "Key = " with empty value
                currentEntry[key] = ""
            }
        }

        // Don't forget the last entry
        if !currentEntry.isEmpty {
            if let item = makeArchiveItem(from: currentEntry, dateFormatter: dateFormatter) {
                items.append(item)
            }
        }

        var totalFiles = 0
        var totalFolders = 0
        var totalSize: UInt64 = 0
        for item in items {
            if item.isDirectory {
                totalFolders += 1
            } else {
                totalFiles += 1
            }
            totalSize += item.size
        }

        let info = ArchiveInfo(
            path: archivePath,
            type: archiveType,
            physicalSize: physicalSize,
            totalFiles: totalFiles,
            totalFolders: totalFolders,
            totalSize: totalSize,
            method: method,
            encrypted: archiveEncrypted,
            solid: solid,
            blocks: blocks,
            headerSize: headerSize
        )

        return (info, items)
    }

    /// Create an ArchiveItem from parsed key-value pairs.
    private func makeArchiveItem(from entry: [String: String],
                                  dateFormatter: DateFormatter) -> ArchiveItem? {
        guard let path = entry["Path"], !path.isEmpty else { return nil }

        let name = (path as NSString).lastPathComponent
        let isDir = entry["Folder"] == "+" ||
                    (entry["Attributes"]?.contains("D") == true)

        let size = UInt64(entry["Size"] ?? "0") ?? 0
        let packed = UInt64(entry["Packed Size"] ?? "0") ?? 0

        var modified: Date?
        if let modStr = entry["Modified"] {
            modified = dateFormatter.date(from: String(modStr.prefix(19)))
        }

        let attributes = entry["Attributes"] ?? ""
        let crc = entry["CRC"] ?? ""
        let encrypted = entry["Encrypted"] == "+"
        let method = entry["Method"] ?? ""

        return ArchiveItem(
            path: path,
            name: name,
            isDirectory: isDir,
            size: size,
            compressedSize: packed,
            modified: modified,
            attributes: attributes,
            crc: crc,
            encrypted: encrypted,
            method: method
        )
    }
}
