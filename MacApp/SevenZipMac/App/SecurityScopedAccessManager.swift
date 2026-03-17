import Foundation

@MainActor
final class SecurityScopedAccessManager {
    static let shared = SecurityScopedAccessManager()

    private var activeURLs: [String: URL] = [:]

    private init() {}

    deinit {
        for url in activeURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func retainAccess(to url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        let key = standardizedURL.path

        if let activeURL = activeURLs[key] {
            return activeURL
        }

        guard standardizedURL.startAccessingSecurityScopedResource() else {
            return standardizedURL
        }

        activeURLs[key] = standardizedURL
        return standardizedURL
    }

    public func releaseAccess(to url: URL) {
        let standardizedURL = url.standardizedFileURL
        let key = standardizedURL.path

        if let activeURL = activeURLs[key] {
            activeURL.stopAccessingSecurityScopedResource()
            activeURLs.removeValue(forKey: key)
        }
    }

    func resolveURL(path: String, bookmarkData: Data?) -> URL {
        let fallbackURL = URL(fileURLWithPath: path).standardizedFileURL
        let key = fallbackURL.path

        if let activeURL = activeURLs[key] {
            return activeURL
        }

        guard let bookmarkData else {
            return fallbackURL
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL else {
            return fallbackURL
        }

        if resolvedURL.startAccessingSecurityScopedResource() {
            activeURLs[key] = resolvedURL
        }

        return resolvedURL
    }
}
