import Foundation
import AppKit

class FileManagerService {
    static let shared = FileManagerService()

    private let fm = FileManager.default

    /// Whether iCloud Drive is available
    private(set) var iCloudAvailable: Bool = false

    /// The iCloud container URL - this is the ONLY storage location on Mac
    private var containerURL: URL!

    private init() {
        setupDirectories()
    }

    private func setupDirectories() {
        // Mac uses iCloud container exclusively
        if let iCloudDocs = fm.url(forUbiquityContainerIdentifier: "iCloud.com.christianokeke.mymusiccontainer")?.appendingPathComponent("Documents") {
            containerURL = iCloudDocs
            iCloudAvailable = true
            print("[MyMusic] Using iCloud container: \(iCloudDocs.path)")

            // Ensure folders exist
            try? fm.createDirectory(at: iCloudDocs, withIntermediateDirectories: true)
            try? fm.createDirectory(at: iCloudDocs.appendingPathComponent("Tracks"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: iCloudDocs.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
        } else {
            // Fallback if iCloud not available (shouldn't happen normally)
            containerURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MyMusic")
            iCloudAvailable = false
            print("[MyMusic] WARNING: iCloud not available, using local: \(containerURL.path)")

            try? fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
            try? fm.createDirectory(at: containerURL.appendingPathComponent("Tracks"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: containerURL.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
        }
    }

    // MARK: - Directory Paths

    /// Main music directory - iCloud container on Mac
    var musicDirectory: URL {
        containerURL
    }

    /// iCloud directory (same as musicDirectory on Mac)
    var iCloudDirectory: URL? {
        iCloudAvailable ? containerURL : nil
    }

    var fullTracksDirectory: URL {
        musicDirectory.appendingPathComponent("Tracks")
    }

    var artworkDirectory: URL {
        musicDirectory.appendingPathComponent("Artwork")
    }

    var mixesDirectory: URL {
        musicDirectory.appendingPathComponent("Mixes")
    }

    var tempDirectory: URL {
        fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyMusic")
            .appendingPathComponent(".temp")
    }

    var downloadsDirectory: URL {
        fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    // For backwards compatibility
    var containerDirectory: URL { musicDirectory }
    var localMusicDirectory: URL { musicDirectory }

    // MARK: - Directory Management

    func ensureDirectoriesExist() throws {
        let directories = [
            musicDirectory,
            fullTracksDirectory,
            artworkDirectory,
            tempDirectory
        ]

        for directory in directories {
            if !fm.fileExists(atPath: directory.path) {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - iCloud Helpers

    /// Collect all file URLs from a directory (synchronous helper for Swift 6 compatibility)
    func collectFiles(at directory: URL, withExtensions extensions: [String]) -> [URL] {
        var files: [URL] = []
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return files
        }
        for case let fileURL as URL in enumerator {
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }
        return files
    }

    /// No-op on Mac since we use iCloud directly. Kept for API compatibility.
    func syncWithiCloud() async -> Int {
        // Mac uses iCloud container directly - no sync needed
        return 0
    }

    /// No-op on Mac since we use iCloud directly. Kept for API compatibility.
    func copyToiCloud(fileURL: URL) {
        // Mac uses iCloud container directly - files are already in iCloud
    }

    // MARK: - File Operations

    func exportToDownloads(file: URL, filename: String? = nil) throws -> URL {
        let name = filename ?? file.lastPathComponent
        let destination = downloadsDirectory.appendingPathComponent(name)

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        try fm.copyItem(at: file, to: destination)
        return destination
    }

    func deleteFile(at url: URL) throws {
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    func clearTempDirectory() throws {
        if fm.fileExists(atPath: tempDirectory.path) {
            try fm.removeItem(at: tempDirectory)
            try fm.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        }
    }

    func fileExists(at url: URL) -> Bool {
        fm.fileExists(atPath: url.path)
    }

    func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }

    func formattedFileSize(at url: URL) -> String {
        guard let size = fileSize(at: url) else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Reveal in Finder

    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInFinder(directory: URL) {
        NSWorkspace.shared.open(directory)
    }

    // MARK: - Relative Path Helpers

    func relativePath(for absoluteURL: URL) -> String? {
        let containerPath = musicDirectory.path
        let filePath = absoluteURL.path

        guard filePath.hasPrefix(containerPath) else { return nil }

        var relative = String(filePath.dropFirst(containerPath.count))
        if relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        return relative
    }

    func absoluteURL(for relativePath: String) -> URL {
        musicDirectory.appendingPathComponent(relativePath)
    }

    func organizedRelativePath(artist: String, album: String, title: String, ext: String) -> String {
        let sanitizedArtist = sanitizeFilename(artist)
        let sanitizedAlbum = sanitizeFilename(album)
        let sanitizedTitle = sanitizeFilename(title)
        return "Tracks/\(sanitizedArtist)/\(sanitizedAlbum)/\(sanitizedTitle).\(ext)"
    }

    func artworkRelativePath(trackID: UUID, ext: String = "jpg") -> String {
        "Artwork/\(trackID.uuidString).\(ext)"
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        var sanitized = name
            .components(separatedBy: invalidChars)
            .joined()
            .trimmingCharacters(in: .whitespaces)

        if sanitized.isEmpty {
            sanitized = "Unknown"
        }

        return sanitized
    }
}
