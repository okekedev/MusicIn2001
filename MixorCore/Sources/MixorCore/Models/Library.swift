import Foundation

/// The complete music library containing tracks and playlists
public struct Library: Codable, Equatable {
    public var tracks: [Track]
    public var playlists: [Playlist]

    /// Version for migration support
    public var version: Int

    /// Current library format version
    public static let currentVersion = 1

    public init(
        tracks: [Track] = [],
        playlists: [Playlist] = [],
        version: Int = Library.currentVersion
    ) {
        self.tracks = tracks
        self.playlists = playlists
        self.version = version
    }

    // MARK: - Track Management

    /// Add a track to the library
    public mutating func addTrack(_ track: Track) {
        if !tracks.contains(where: { $0.id == track.id }) {
            tracks.append(track)
        }
    }

    /// Remove a track from the library and all playlists
    public mutating func removeTrack(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        for i in playlists.indices {
            playlists[i].removeTrack(track)
        }
    }

    /// Find a track by ID
    public func track(withID id: UUID) -> Track? {
        tracks.first { $0.id == id }
    }

    /// Update a track in the library
    public mutating func updateTrack(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index] = track
        }
    }

    // MARK: - Playlist Management

    /// Add a playlist to the library
    public mutating func addPlaylist(_ playlist: Playlist) {
        if !playlists.contains(where: { $0.id == playlist.id }) {
            playlists.append(playlist)
        }
    }

    /// Remove a playlist from the library
    public mutating func removePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
    }

    /// Find a playlist by ID
    public func playlist(withID id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    /// Update a playlist in the library
    public mutating func updatePlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        }
    }

    // MARK: - Organization

    /// Get all unique artists
    public var artists: [String] {
        Array(Set(tracks.map { $0.artist })).sorted()
    }

    /// Get all unique albums
    public var albums: [String] {
        Array(Set(tracks.map { $0.album })).sorted()
    }

    /// Get tracks by artist
    public func tracks(byArtist artist: String) -> [Track] {
        tracks.filter { $0.artist == artist }
    }

    /// Get tracks by album
    public func tracks(byAlbum album: String) -> [Track] {
        tracks.filter { $0.album == album }
    }

    /// Get albums by artist
    public func albums(byArtist artist: String) -> [String] {
        Array(Set(tracks.filter { $0.artist == artist }.map { $0.album })).sorted()
    }

    // MARK: - Search

    /// Search tracks by query (matches title, artist, album)
    public func search(_ query: String) -> [Track] {
        guard !query.isEmpty else { return tracks }
        let lowercased = query.lowercased()
        return tracks.filter { track in
            track.title.lowercased().contains(lowercased) ||
            track.artist.lowercased().contains(lowercased) ||
            track.album.lowercased().contains(lowercased)
        }
    }
}

// MARK: - Persistence Keys

extension Library {
    public static let userDefaultsKey = "MixorLibrary"
}
