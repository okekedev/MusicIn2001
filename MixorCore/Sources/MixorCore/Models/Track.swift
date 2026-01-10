import Foundation

/// A music track with relative paths for iCloud sync compatibility
public struct Track: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval

    /// Relative path from container root (e.g., "Music/Artist/Album/song.mp3")
    public var relativePath: String

    /// Relative path for artwork (e.g., "Artwork/song.jpg")
    public var artworkRelativePath: String?

    public var releaseYear: Int?

    public init(
        id: UUID = UUID(),
        title: String,
        artist: String = "Unknown Artist",
        album: String = "Unknown Album",
        duration: TimeInterval = 0,
        relativePath: String,
        artworkRelativePath: String? = nil,
        releaseYear: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.relativePath = relativePath
        self.artworkRelativePath = artworkRelativePath
        self.releaseYear = releaseYear
    }

    /// Formatted duration string (e.g., "3:45")
    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Resolve file URL using a container base URL
    public func fileURL(in containerURL: URL) -> URL {
        containerURL.appendingPathComponent(relativePath)
    }

    /// Resolve artwork URL using a container base URL
    public func artworkURL(in containerURL: URL) -> URL? {
        guard let path = artworkRelativePath else { return nil }
        return containerURL.appendingPathComponent(path)
    }

    // MARK: - Migration from absolute URLs

    /// Create a Track from an absolute file URL by extracting the relative path
    /// - Parameters:
    ///   - fileURL: Absolute URL to the audio file
    ///   - containerURL: Base container URL to calculate relative path from
    ///   - metadata: Existing metadata to preserve
    public static func fromAbsoluteURL(
        fileURL: URL,
        artworkURL: URL?,
        containerURL: URL,
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        releaseYear: Int?
    ) -> Track? {
        let filePath = fileURL.path
        let containerPath = containerURL.path

        // Check if file is within container
        guard filePath.hasPrefix(containerPath) else {
            return nil
        }

        // Extract relative path
        var relativePath = String(filePath.dropFirst(containerPath.count))
        if relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }

        // Extract artwork relative path if present
        var artworkRelative: String? = nil
        if let artURL = artworkURL {
            let artPath = artURL.path
            if artPath.hasPrefix(containerPath) {
                var rel = String(artPath.dropFirst(containerPath.count))
                if rel.hasPrefix("/") {
                    rel = String(rel.dropFirst())
                }
                artworkRelative = rel
            }
        }

        return Track(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            relativePath: relativePath,
            artworkRelativePath: artworkRelative,
            releaseYear: releaseYear
        )
    }
}
