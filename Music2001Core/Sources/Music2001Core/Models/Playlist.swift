import Foundation

/// A user-created playlist containing track references
public struct Playlist: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var trackIDs: [UUID]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        trackIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
    }

    /// Get tracks from the library that belong to this playlist
    public func tracks(from library: Library) -> [Track] {
        trackIDs.compactMap { id in
            library.tracks.first { $0.id == id }
        }
    }

    /// Add a track to the playlist
    public mutating func addTrack(_ track: Track) {
        if !trackIDs.contains(track.id) {
            trackIDs.append(track.id)
        }
    }

    /// Remove a track from the playlist
    public mutating func removeTrack(_ track: Track) {
        trackIDs.removeAll { $0 == track.id }
    }

    /// Check if playlist contains a track
    public func contains(_ track: Track) -> Bool {
        trackIDs.contains(track.id)
    }
}
