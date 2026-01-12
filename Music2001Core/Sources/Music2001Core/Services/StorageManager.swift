import Foundation

/// Protocol for storage management - allows platform-specific implementations
public protocol StorageManagerProtocol {
    /// The base container URL for all Mixor content
    var containerURL: URL { get }

    /// URL for music files
    var musicDirectory: URL { get }

    /// URL for artwork files
    var artworkDirectory: URL { get }

    /// Check if a file exists at the relative path
    func fileExists(at relativePath: String) -> Bool

    /// Get the absolute URL for a relative path
    func absoluteURL(for relativePath: String) -> URL

    /// Save library to persistent storage
    func saveLibrary(_ library: Library) throws

    /// Load library from persistent storage
    func loadLibrary() throws -> Library

    /// Check if iCloud is available
    var isCloudAvailable: Bool { get }
}

/// Default storage manager using iCloud or local fallback
public class StorageManager: StorageManagerProtocol {
    public static let shared = StorageManager()

    /// iCloud container identifier
    public static let iCloudContainerID = "iCloud.com.christianokeke.mymusiccontainer"

    private let fileManager = FileManager.default
    private var _containerURL: URL?

    public init() {
        setupContainer()
    }

    private func setupContainer() {
        // Try iCloud first
        if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: Self.iCloudContainerID) {
            _containerURL = iCloudURL.appendingPathComponent("Documents")
        } else {
            // Fallback to local storage
            #if os(macOS)
            let musicURL = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first!
            _containerURL = musicURL.appendingPathComponent("MyMusic")
            #else
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            _containerURL = documentsURL.appendingPathComponent("MyMusic")
            #endif
        }

        // Create directories if needed
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        guard let container = _containerURL else { return }

        let directories = [
            container,
            container.appendingPathComponent("Music"),
            container.appendingPathComponent("Artwork")
        ]

        for dir in directories {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - StorageManagerProtocol

    public var containerURL: URL {
        guard let url = _containerURL else {
            fatalError("Storage container not initialized")
        }
        return url
    }

    public var musicDirectory: URL {
        containerURL.appendingPathComponent("Music")
    }

    public var artworkDirectory: URL {
        containerURL.appendingPathComponent("Artwork")
    }

    public func fileExists(at relativePath: String) -> Bool {
        let url = absoluteURL(for: relativePath)
        return fileManager.fileExists(atPath: url.path)
    }

    public func absoluteURL(for relativePath: String) -> URL {
        containerURL.appendingPathComponent(relativePath)
    }

    public var isCloudAvailable: Bool {
        fileManager.url(forUbiquityContainerIdentifier: Self.iCloudContainerID) != nil
    }

    // MARK: - Library Persistence

    private var libraryURL: URL {
        containerURL.appendingPathComponent("library.json")
    }

    public func saveLibrary(_ library: Library) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try data.write(to: libraryURL, options: .atomic)

        // Also save to UserDefaults for quick local access
        UserDefaults.standard.set(data, forKey: Library.userDefaultsKey)
    }

    public func loadLibrary() throws -> Library {
        // Try loading from file first
        if fileManager.fileExists(atPath: libraryURL.path) {
            let data = try Data(contentsOf: libraryURL)
            let decoder = JSONDecoder()
            return try decoder.decode(Library.self, from: data)
        }

        // Fall back to UserDefaults
        if let data = UserDefaults.standard.data(forKey: Library.userDefaultsKey) {
            let decoder = JSONDecoder()
            return try decoder.decode(Library.self, from: data)
        }

        // Return empty library
        return Library()
    }

    // MARK: - File Operations

    /// Copy a file into the container and return the relative path
    public func importFile(from sourceURL: URL, toRelativePath relativePath: String) throws -> String {
        let destinationURL = absoluteURL(for: relativePath)

        // Create parent directory if needed
        let parentDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        // Copy file
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return relativePath
    }

    /// Delete a file at the relative path
    public func deleteFile(at relativePath: String) throws {
        let url = absoluteURL(for: relativePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Generate a relative path for a new music file
    public func relativePath(forTrack title: String, artist: String, album: String, ext: String) -> String {
        let sanitizedArtist = sanitizeFilename(artist)
        let sanitizedAlbum = sanitizeFilename(album)
        let sanitizedTitle = sanitizeFilename(title)
        return "Music/\(sanitizedArtist)/\(sanitizedAlbum)/\(sanitizedTitle).\(ext)"
    }

    /// Generate a relative path for artwork
    public func artworkRelativePath(forTrackID id: UUID, ext: String = "jpg") -> String {
        "Artwork/\(id.uuidString).\(ext)"
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name
            .components(separatedBy: invalidChars)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - iCloud Sync Helpers

extension StorageManager {
    /// Start downloading a file from iCloud if needed
    public func startDownloading(relativePath: String) {
        let url = absoluteURL(for: relativePath)
        do {
            try fileManager.startDownloadingUbiquitousItem(at: url)
        } catch {
            print("Failed to start downloading: \(error)")
        }
    }

    /// Check if a file is downloaded locally
    public func isDownloaded(relativePath: String) -> Bool {
        let url = absoluteURL(for: relativePath)

        var isDownloaded: AnyObject?
        do {
            try (url as NSURL).getResourceValue(&isDownloaded, forKey: .ubiquitousItemDownloadingStatusKey)
            if let status = isDownloaded as? URLUbiquitousItemDownloadingStatus {
                return status == .current
            }
        } catch {
            // Not a ubiquitous item, assume it's local
        }

        return fileManager.fileExists(atPath: url.path)
    }
}
