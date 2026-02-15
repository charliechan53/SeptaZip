import Foundation

/// Represents a single file or directory entry inside an archive.
struct ArchiveItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let compressedSize: UInt64
    let modified: Date?
    let attributes: String
    let crc: String
    let encrypted: Bool
    let method: String

    /// Display-friendly file size string
    var formattedSize: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Display-friendly compressed size string
    var formattedCompressedSize: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(compressedSize), countStyle: .file)
    }

    /// Compression ratio as a percentage
    var ratio: String {
        if isDirectory || size == 0 { return "--" }
        let r = Double(compressedSize) / Double(size) * 100.0
        return String(format: "%.0f%%", r)
    }

    /// File extension (lowercased)
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    /// Parent directory path
    var parentPath: String {
        (path as NSString).deletingLastPathComponent
    }

    /// SF Symbol name for the file type icon
    var iconName: String {
        if isDirectory {
            return "folder.fill"
        }
        switch fileExtension {
        case "7z", "zip", "rar", "tar", "gz", "bz2", "xz", "zst":
            return "doc.zipper"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic", "svg":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm":
            return "film"
        case "mp3", "aac", "flac", "wav", "ogg", "wma", "m4a":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "doc", "docx", "rtf", "odt":
            return "doc.text"
        case "xls", "xlsx", "csv", "ods":
            return "tablecells"
        case "ppt", "pptx", "odp":
            return "rectangle.split.3x1"
        case "swift", "py", "js", "ts", "c", "cpp", "h", "java", "rs", "go":
            return "chevron.left.forwardslash.chevron.right"
        case "txt", "md", "log", "json", "xml", "yaml", "yml", "toml", "ini", "cfg":
            return "doc.plaintext"
        case "html", "htm", "css":
            return "globe"
        case "exe", "dll", "app", "dmg", "pkg", "deb", "rpm":
            return "gearshape"
        case "iso", "img":
            return "opticaldiscdrive"
        default:
            return "doc"
        }
    }
}

/// Represents metadata about an archive file itself.
struct ArchiveInfo {
    let path: String
    let type: String
    let physicalSize: UInt64
    let totalFiles: Int
    let totalFolders: Int
    let totalSize: UInt64
    let method: String
    let encrypted: Bool
    let solid: Bool
    let blocks: Int
    let headerSize: UInt64

    var formattedPhysicalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(physicalSize), countStyle: .file)
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }

    var overallRatio: String {
        if totalSize == 0 { return "--" }
        let r = Double(physicalSize) / Double(totalSize) * 100.0
        return String(format: "%.1f%%", r)
    }
}

/// Archive format options for creating archives.
enum ArchiveFormat: String, CaseIterable, Identifiable {
    case sevenZ = "7z"
    case zip = "zip"
    case tar = "tar"
    case gzip = "gzip"
    case bzip2 = "bzip2"
    case xz = "xz"
    case wim = "wim"
    case zstd = "zstd"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "ZIP"
        case .tar: return "TAR"
        case .gzip: return "GZip"
        case .bzip2: return "BZip2"
        case .xz: return "XZ"
        case .wim: return "WIM"
        case .zstd: return "Zstandard"
        }
    }

    var fileExtension: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .gzip: return "tar.gz"
        case .bzip2: return "tar.bz2"
        case .xz: return "tar.xz"
        case .wim: return "wim"
        case .zstd: return "tar.zst"
        }
    }

    /// The -t flag value for 7zz
    var typeFlag: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .gzip: return "gzip"
        case .bzip2: return "bzip2"
        case .xz: return "xz"
        case .wim: return "wim"
        case .zstd: return "zstd"
        }
    }
}

/// Compression level options
enum CompressionLevel: Int, CaseIterable, Identifiable {
    case store = 0
    case fastest = 1
    case fast = 3
    case normal = 5
    case maximum = 7
    case ultra = 9

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .store: return "Store (no compression)"
        case .fastest: return "Fastest"
        case .fast: return "Fast"
        case .normal: return "Normal"
        case .maximum: return "Maximum"
        case .ultra: return "Ultra"
        }
    }
}
