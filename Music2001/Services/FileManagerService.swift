import Foundation
import AppKit

class FileManagerService {
    static let shared = FileManagerService()

    private let fm = FileManager.default

    /// Whether iCloud Drive is available for syncing
    private(set) var iCloudAvailable: Bool = false

    /// The iCloud Drive folder URL (for syncing to other devices)
    private var iCloudURL: URL?

    /// Local folder - uses sandboxed Application Support for App Store compatibility
    private var localMusicURL: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyMusic")
    }

    private init() {
        setupDirectories()
    }

    private func setupDirectories() {
        // Always create local directories (used for playback)
        try? fm.createDirectory(at: localMusicURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: localMusicURL.appendingPathComponent("Tracks"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: localMusicURL.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
        print("[MyMusic] Local folder: \(localMusicURL.path)")

        // Also setup iCloud for syncing (if available)
        if let iCloudDocs = fm.url(forUbiquityContainerIdentifier: "iCloud.com.christianokeke.mymusiccontainer")?.appendingPathComponent("Documents") {
            iCloudURL = iCloudDocs
            iCloudAvailable = true
            print("[MyMusic] iCloud available for sync: \(iCloudDocs.path)")

            // Ensure iCloud folders exist
            try? fm.createDirectory(at: iCloudDocs, withIntermediateDirectories: true)
            try? fm.createDirectory(at: iCloudDocs.appendingPathComponent("Tracks"), withIntermediateDirectories: true)
            try? fm.createDirectory(at: iCloudDocs.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
        } else {
            iCloudAvailable = false
            print("[MyMusic] iCloud not available")
        }
    }

    // MARK: - Directory Paths

    /// Main music directory - always local for offline-first playback
    var musicDirectory: URL {
        localMusicURL
    }

    /// iCloud directory for syncing (may be nil)
    var iCloudDirectory: URL? {
        iCloudURL
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

    // MARK: - iCloud Sync

    /// Collect all file URLs from a directory (synchronous helper for Swift 6 compatibility)
    private func collectFiles(at directory: URL, withExtensions extensions: [String]) -> [URL] {
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

    /// Sync files bidirectionally: local ↔ iCloud
    /// - Copies local files to iCloud (for iOS access)
    /// - Copies iCloud files to local (for offline playback)
    func syncWithiCloud() async -> Int {
        guard iCloudAvailable, let iCloudBase = iCloudURL else { return 0 }

        var syncedCount = 0
        let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac"]
        let imageExtensions = ["jpg", "jpeg", "png"]

        // === SYNC TRACKS ===
        let localTracksDir = localMusicURL.appendingPathComponent("Tracks")
        let iCloudTracksDir = iCloudBase.appendingPathComponent("Tracks")

        // Local → iCloud
        let localTrackFiles = collectFiles(at: localTracksDir, withExtensions: audioExtensions)
        for fileURL in localTrackFiles {
            let relativePath = String(fileURL.path.dropFirst(localTracksDir.path.count + 1))
            let destURL = iCloudTracksDir.appendingPathComponent(relativePath)
            if !fm.fileExists(atPath: destURL.path) {
                do {
                    try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: fileURL, to: destURL)
                    print("[MyMusic] Local → iCloud: \(relativePath)")
                    syncedCount += 1
                } catch {
                    print("[MyMusic] Failed: \(error.localizedDescription)")
                }
            }
        }

        // iCloud → Local
        let iCloudTrackFiles = collectFiles(at: iCloudTracksDir, withExtensions: audioExtensions)
        for fileURL in iCloudTrackFiles {
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
            let relativePath = String(fileURL.path.dropFirst(iCloudTracksDir.path.count + 1))
            let destURL = localTracksDir.appendingPathComponent(relativePath)
            if !fm.fileExists(atPath: destURL.path) {
                do {
                    try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: fileURL, to: destURL)
                    print("[MyMusic] iCloud → Local: \(relativePath)")
                    syncedCount += 1
                } catch {
                    print("[MyMusic] Failed: \(error.localizedDescription)")
                }
            }
        }

        // === SYNC ARTWORK ===
        let localArtworkDir = localMusicURL.appendingPathComponent("Artwork")
        let iCloudArtworkDir = iCloudBase.appendingPathComponent("Artwork")
        try? fm.createDirectory(at: iCloudArtworkDir, withIntermediateDirectories: true)

        // Local → iCloud
        let localArtworkFiles = collectFiles(at: localArtworkDir, withExtensions: imageExtensions)
        for fileURL in localArtworkFiles {
            let filename = fileURL.lastPathComponent
            let destURL = iCloudArtworkDir.appendingPathComponent(filename)
            if !fm.fileExists(atPath: destURL.path) {
                do {
                    try fm.copyItem(at: fileURL, to: destURL)
                    syncedCount += 1
                } catch {}
            }
        }

        // iCloud → Local
        let iCloudArtworkFiles = collectFiles(at: iCloudArtworkDir, withExtensions: imageExtensions)
        for fileURL in iCloudArtworkFiles {
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
            let filename = fileURL.lastPathComponent
            let destURL = localArtworkDir.appendingPathComponent(filename)
            if !fm.fileExists(atPath: destURL.path) {
                do {
                    try fm.copyItem(at: fileURL, to: destURL)
                    syncedCount += 1
                } catch {}
            }
        }

        // === SYNC PLAYLISTS ===
        let localPlaylistsFile = localMusicURL.appendingPathComponent("playlists.json")
        let iCloudPlaylistsFile = iCloudBase.appendingPathComponent("playlists.json")

        // Use whichever is newer, or merge if needed
        let localExists = fm.fileExists(atPath: localPlaylistsFile.path)
        let iCloudExists = fm.fileExists(atPath: iCloudPlaylistsFile.path)

        if localExists && !iCloudExists {
            try? fm.copyItem(at: localPlaylistsFile, to: iCloudPlaylistsFile)
        } else if iCloudExists && !localExists {
            try? fm.startDownloadingUbiquitousItem(at: iCloudPlaylistsFile)
            try? fm.copyItem(at: iCloudPlaylistsFile, to: localPlaylistsFile)
        } else if localExists && iCloudExists {
            // Both exist - use the newer one
            let localDate = (try? fm.attributesOfItem(atPath: localPlaylistsFile.path)[.modificationDate] as? Date) ?? .distantPast
            let iCloudDate = (try? fm.attributesOfItem(atPath: iCloudPlaylistsFile.path)[.modificationDate] as? Date) ?? .distantPast
            if localDate > iCloudDate {
                try? fm.removeItem(at: iCloudPlaylistsFile)
                try? fm.copyItem(at: localPlaylistsFile, to: iCloudPlaylistsFile)
            } else if iCloudDate > localDate {
                try? fm.removeItem(at: localPlaylistsFile)
                try? fm.copyItem(at: iCloudPlaylistsFile, to: localPlaylistsFile)
            }
        }

        return syncedCount
    }

    /// Copy a single file to iCloud (called after download or playlist update)
    func copyToiCloud(fileURL: URL) {
        guard iCloudAvailable, let iCloudBase = iCloudURL else { return }

        let relativePath = String(fileURL.path.dropFirst(localMusicURL.path.count + 1))
        let destURL = iCloudBase.appendingPathComponent(relativePath)

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                // Remove existing file if present, then copy
                if self.fm.fileExists(atPath: destURL.path) {
                    try self.fm.removeItem(at: destURL)
                }
                try self.fm.copyItem(at: fileURL, to: destURL)
                print("[MyMusic] Synced to iCloud: \(relativePath)")
            } catch {
                print("[MyMusic] iCloud sync failed: \(error.localizedDescription)")
            }
        }
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
