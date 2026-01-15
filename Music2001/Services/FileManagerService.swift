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
        // Try standard iCloud API first (works for sandboxed apps)
        if let iCloudDocs = fm.url(forUbiquityContainerIdentifier: "iCloud.com.christianokeke.mymusiccontainer")?.appendingPathComponent("Documents") {
            containerURL = iCloudDocs
            iCloudAvailable = true
            print("[MyMusic] Using iCloud container (API): \(iCloudDocs.path)")
        } else {
            // For non-sandboxed apps, access iCloud directly via Mobile Documents
            let homeDir = fm.homeDirectoryForCurrentUser
            let mobileDocsPath = homeDir
                .appendingPathComponent("Library/Mobile Documents/iCloud~com~christianokeke~mymusiccontainer/Documents")

            // Check if user is signed into iCloud by checking if Mobile Documents exists
            let mobileDocsRoot = homeDir.appendingPathComponent("Library/Mobile Documents")
            if fm.fileExists(atPath: mobileDocsRoot.path) {
                containerURL = mobileDocsPath
                iCloudAvailable = true
                print("[MyMusic] Using iCloud container (direct): \(mobileDocsPath.path)")
            } else {
                // Fallback if iCloud not available
                containerURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("MyMusic")
                iCloudAvailable = false
                print("[MyMusic] WARNING: iCloud not available, using local: \(containerURL.path)")
            }
        }

        // Ensure folders exist
        try? fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: containerURL.appendingPathComponent("Tracks"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: containerURL.appendingPathComponent("Artwork"), withIntermediateDirectories: true)

        // Download all files for offline playback if using iCloud
        if iCloudAvailable {
            DispatchQueue.main.async { [weak self] in
                self?.downloadAllForOffline()
            }
        }

        // Copy demo music on first launch
        copyDemoMusicIfNeeded()
    }

    // MARK: - Demo Music

    /// Copy bundled demo music to user's library on first launch
    private func copyDemoMusicIfNeeded() {
        let hasInstalledDemo = UserDefaults.standard.bool(forKey: "hasInstalledDemoMusic")
        guard !hasInstalledDemo else { return }

        guard let demoMusicURL = Bundle.main.url(forResource: "DemoMusic", withExtension: nil) else {
            print("[MyMusic] No demo music bundle found")
            return
        }

        let tracksDir = fullTracksDirectory
        let artworkDir = artworkDirectory

        // Copy all demo tracks
        let demoTracksDir = demoMusicURL.appendingPathComponent("Christian Okeke/LoFi")
        if let enumerator = fm.enumerator(at: demoTracksDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                guard ["mp3", "m4a", "wav", "aac", "flac"].contains(ext) else { continue }

                // Get relative path: Christian Okeke/LoFi/Track.mp3
                let relativePath = "Christian Okeke/LoFi/" + fileURL.lastPathComponent
                let destURL = tracksDir.appendingPathComponent(relativePath)

                // Create directory structure
                try? fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

                // Copy file if it doesn't exist
                if !fm.fileExists(atPath: destURL.path) {
                    do {
                        try fm.copyItem(at: fileURL, to: destURL)
                        print("[MyMusic] Copied demo track: \(relativePath)")
                    } catch {
                        print("[MyMusic] Failed to copy demo track: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Copy artwork
        let demoArtworkDir = demoMusicURL.appendingPathComponent("Artwork")
        if let enumerator = fm.enumerator(at: demoArtworkDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                guard ["jpg", "jpeg", "png"].contains(ext) else { continue }

                let destURL = artworkDir.appendingPathComponent(fileURL.lastPathComponent)

                if !fm.fileExists(atPath: destURL.path) {
                    do {
                        try fm.copyItem(at: fileURL, to: destURL)
                        print("[MyMusic] Copied demo artwork: \(fileURL.lastPathComponent)")
                    } catch {
                        print("[MyMusic] Failed to copy demo artwork: \(error.localizedDescription)")
                    }
                }
            }
        }

        UserDefaults.standard.set(true, forKey: "hasInstalledDemoMusic")
        print("[MyMusic] Demo music installed")
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

    /// Download all iCloud files for offline playback
    /// Call this at app launch to ensure files are available offline
    func downloadAllForOffline() {
        guard iCloudAvailable else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac"]
            let imageExtensions = ["jpg", "jpeg", "png"]

            // Download all tracks
            let tracks = self.collectFiles(at: self.fullTracksDirectory, withExtensions: audioExtensions)
            for fileURL in tracks {
                try? self.fm.startDownloadingUbiquitousItem(at: fileURL)
            }

            // Download all artwork
            let artwork = self.collectFiles(at: self.artworkDirectory, withExtensions: imageExtensions)
            for fileURL in artwork {
                try? self.fm.startDownloadingUbiquitousItem(at: fileURL)
            }

            // Download playlists
            let playlistsFile = self.musicDirectory.appendingPathComponent("playlists.json")
            if self.fm.fileExists(atPath: playlistsFile.path) {
                try? self.fm.startDownloadingUbiquitousItem(at: playlistsFile)
            }

            print("[MyMusic] Downloading all files for offline use...")
        }
    }

    /// No-op on Mac since we use iCloud directly. Kept for API compatibility.
    func syncWithiCloud() async -> Int {
        // Trigger download for offline use
        downloadAllForOffline()
        return 0
    }

    /// No-op - files in iCloud container sync automatically
    func copyToiCloud(fileURL: URL) {
        // Files are already in iCloud container - macOS handles sync automatically
        // No need to do anything extra
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
