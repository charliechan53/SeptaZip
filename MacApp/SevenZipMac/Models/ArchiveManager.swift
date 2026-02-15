import Foundation
import Combine

/// Error types for archive operations.
enum ArchiveError: LocalizedError {
    case binaryNotFound
    case operationFailed(String)
    case parseError(String)
    case cancelled
    case passwordRequired
    case invalidArchive(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "7zz binary not found. Please rebuild the app or run the build script."
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

/// Wraps the 7zz command-line binary for archive operations.
@MainActor
class ArchiveManager: ObservableObject {
    @Published var items: [ArchiveItem] = []
    @Published var archiveInfo: ArchiveInfo?
    @Published var isLoading = false
    @Published var error: ArchiveError?
    @Published var progress: ArchiveProgress?

    private var currentProcess: Process?

    /// Path to the 7zz binary bundled with the app.
    var binaryPath: String {
        if let bundlePath = Bundle.main.path(forResource: "7zz", ofType: nil) {
            return bundlePath
        }
        // Fallback: check common install locations
        let fallbacks = [
            "/usr/local/bin/7zz",
            "/opt/homebrew/bin/7zz",
            "\(NSHomeDirectory())/.local/bin/7zz"
        ]
        for path in fallbacks {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return ""
    }

    /// Check if the 7zz binary is available.
    var isBinaryAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    // MARK: - List Archive Contents

    /// List all items in an archive.
    func listArchive(at path: String, password: String? = nil) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

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
        isLoading = true
        error = nil
        defer { isLoading = false }

        var args = ["x"]
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
        isLoading = true
        error = nil
        defer { isLoading = false }

        var args = ["x", "-o\(destination)"]
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
        isLoading = true
        error = nil
        defer { isLoading = false }

        var args = ["a"]
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
        isLoading = true
        error = nil
        defer { isLoading = false }

        var args = ["t"]
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
        isLoading = false
        error = .cancelled
    }

    // MARK: - Private

    /// Execute the 7zz binary with arguments.
    private func run7zz(args: [String]) async throws -> String {
        guard isBinaryAvailable else {
            throw ArchiveError.binaryNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = errorPipe
            process.environment = ProcessInfo.processInfo.environment

            self.currentProcess = process

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ArchiveError.operationFailed(error.localizedDescription))
                return
            }

            process.waitUntilExit()
            self.currentProcess = nil

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            let status = process.terminationStatus

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
