import SwiftUI
import AVFoundation
import Combine
import CryptoKit

/// Generate a stable UUID from a string (used for consistent track IDs across devices)
func stableUUID(from string: String) -> UUID {
    let hash = SHA256.hash(data: Data(string.utf8))
    let hashBytes = Array(hash)
    // Use first 16 bytes of SHA256 hash to create UUID
    let uuid = UUID(uuid: (
        hashBytes[0], hashBytes[1], hashBytes[2], hashBytes[3],
        hashBytes[4], hashBytes[5], hashBytes[6], hashBytes[7],
        hashBytes[8], hashBytes[9], hashBytes[10], hashBytes[11],
        hashBytes[12], hashBytes[13], hashBytes[14], hashBytes[15]
    ))
    return uuid
}

// MARK: - Data Models

struct TrackMetadata: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String?
    var duration: TimeInterval
    var fileURL: URL
    var artworkURL: URL?
    var releaseYear: Int?

    init(id: UUID = UUID(), title: String, artist: String = "Unknown Artist", album: String = "Unknown Album", genre: String? = nil, duration: TimeInterval = 0, fileURL: URL, artworkURL: URL? = nil, releaseYear: Int? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.duration = duration
        self.fileURL = fileURL
        self.artworkURL = artworkURL
        self.releaseYear = releaseYear
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct Playlist: Codable, Identifiable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
    }
}

// MARK: - View Model

@MainActor
class PlayerViewModel: ObservableObject {
    static let shared = PlayerViewModel()

    // Library
    @Published var library: [TrackMetadata] = []
    @Published var playlists: [Playlist] = []
    @Published var selectedPlaylist: Playlist?

    // Playback
    @Published var currentTrack: TrackMetadata?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Double = 1.0
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off

    // Queue
    @Published var playQueue: [TrackMetadata] = []
    @Published var queueIndex: Int = 0

    // Mixer Deck Queues
    @Published var deckAQueue: [TrackMetadata] = []
    @Published var deckBQueue: [TrackMetadata] = []
    @Published var isMixerActive: Bool = false

    // Download
    @Published var urlInput: String = ""
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: String = ""

    // UI State
    @Published var searchText: String = ""
    @Published var showError: Bool = false
    @Published var errorMessage: String?
    @Published var newPlaylistName: String = ""
    @Published var editingPlaylistId: UUID?
    @Published var showDeleteConfirmation: Bool = false
    @Published var trackToDelete: TrackMetadata?

    // Filtering
    @Published var selectedArtist: String?
    @Published var selectedAlbum: String?

    enum ViewMode: String, CaseIterable {
        case songs = "Songs"
        case artists = "Artists"
        case albums = "Albums"
    }
    @Published var viewMode: ViewMode = .songs

    enum RepeatMode {
        case off, one, all
    }

    private var audioPlayer: AVAudioPlayer?
    private var timerCancellable: AnyCancellable?
    private let fileManager = FileManagerService.shared

    private let playlistsKey = "savedPlaylists"  // Legacy UserDefaults key
    private let libraryKey = "savedLibrary"

    /// URL for playlists JSON file in iCloud (synced with iOS)
    private var playlistsURL: URL {
        fileManager.musicDirectory.appendingPathComponent("playlists.json")
    }

    /// URL for library JSON file in iCloud (synced with iOS)
    private var libraryURL: URL {
        fileManager.musicDirectory.appendingPathComponent("library.json")
    }

    var allArtists: [String] {
        let artists = Set(library.map { $0.artist })
        return artists.sorted()
    }

    var allAlbums: [String] {
        let albums = Set(library.map { $0.album })
        return albums.sorted()
    }

    var filteredLibrary: [TrackMetadata] {
        var tracks = library

        // Filter by selected artist
        if let artist = selectedArtist {
            tracks = tracks.filter { $0.artist == artist }
        }

        // Filter by selected album
        if let album = selectedAlbum {
            tracks = tracks.filter { $0.album == album }
        }

        // Filter by search text
        if !searchText.isEmpty {
            tracks = tracks.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText) ||
                $0.album.localizedCaseInsensitiveContains(searchText)
            }
        }

        return tracks
    }

    func tracksForArtist(_ artist: String) -> [TrackMetadata] {
        library.filter { $0.artist == artist }
    }

    func tracksForAlbum(_ album: String) -> [TrackMetadata] {
        library.filter { $0.album == album }
    }

    var currentPlaylistTracks: [TrackMetadata] {
        guard let playlist = selectedPlaylist else { return [] }
        return playlist.trackIDs.compactMap { id in
            library.first { $0.id == id }
        }
    }

    init() {
        loadSavedData()
        Task {
            await scanLibrary()
        }
        setupTimer()
    }

    // MARK: - Persistence

    private func loadSavedData() {
        // Load playlists from iCloud
        if FileManager.default.fileExists(atPath: playlistsURL.path),
           let data = try? Data(contentsOf: playlistsURL),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }

        // Load library from iCloud
        if FileManager.default.fileExists(atPath: libraryURL.path),
           let data = try? Data(contentsOf: libraryURL),
           let decoded = try? JSONDecoder().decode([TrackMetadata].self, from: data) {
            library = decoded
        }
        // If no library exists, scanLibrary() will build it fresh
    }

    private func savePlaylists() {
        // Save locally
        if let encoded = try? JSONEncoder().encode(playlists) {
            try? encoded.write(to: playlistsURL)
        }
        // Auto-sync to iCloud
        fileManager.copyToiCloud(fileURL: playlistsURL)
    }

    private func saveLibrary() {
        // Save to iCloud (syncs with iOS, downloaded locally for offline use)
        if let encoded = try? JSONEncoder().encode(library) {
            try? encoded.write(to: libraryURL)
        }
    }

    func updateTrack(_ updatedTrack: TrackMetadata) {
        if let index = library.firstIndex(where: { $0.id == updatedTrack.id }) {
            let oldTrack = library[index]

            // Check if artist or album changed - need to reorganize file
            if oldTrack.artist != updatedTrack.artist || oldTrack.album != updatedTrack.album {
                if let newURL = organizeTrackFile(updatedTrack) {
                    var trackWithNewURL = updatedTrack
                    trackWithNewURL.fileURL = newURL
                    library[index] = trackWithNewURL
                } else {
                    library[index] = updatedTrack
                }
            } else {
                library[index] = updatedTrack
            }
            saveLibrary()
        }
    }

    /// Organizes a track file into Artist/Album folder structure
    /// Returns the new file URL if moved, nil if organization failed or wasn't needed
    func organizeTrackFile(_ track: TrackMetadata) -> URL? {
        let tracksDir = fileManager.fullTracksDirectory
        let currentURL = track.fileURL

        // Sanitize folder names (remove invalid characters)
        let artistFolder = sanitizeFolderName(track.artist.isEmpty ? "Unknown Artist" : track.artist)
        let albumFolder = sanitizeFolderName(track.album.isEmpty || track.album == "Unknown Album" ? "Singles" : track.album)

        // Build target directory: Tracks/Artist/Album/
        let targetDir = tracksDir
            .appendingPathComponent(artistFolder)
            .appendingPathComponent(albumFolder)

        // Check if file is already in the correct location
        let currentDir = currentURL.deletingLastPathComponent()
        if currentDir.path == targetDir.path {
            return nil // Already organized correctly
        }

        // Create target directory if needed
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        } catch {
            print("[MyMusic] Failed to create directory \(targetDir): \(error)")
            return nil
        }

        // Build target file URL
        let filename = currentURL.lastPathComponent
        var targetURL = targetDir.appendingPathComponent(filename)

        // Handle filename conflicts
        if FileManager.default.fileExists(atPath: targetURL.path) && targetURL != currentURL {
            let baseName = currentURL.deletingPathExtension().lastPathComponent
            let ext = currentURL.pathExtension
            var counter = 1
            while FileManager.default.fileExists(atPath: targetURL.path) {
                targetURL = targetDir.appendingPathComponent("\(baseName) (\(counter)).\(ext)")
                counter += 1
            }
        }

        // Move the file
        do {
            try FileManager.default.moveItem(at: currentURL, to: targetURL)
            print("[MyMusic] Organized: \(currentURL.lastPathComponent) -> \(artistFolder)/\(albumFolder)/")

            // Clean up empty directories
            cleanupEmptyDirectories(from: currentDir, stopAt: tracksDir)

            return targetURL
        } catch {
            print("[MyMusic] Failed to move file: \(error)")
            return nil
        }
    }

    private func sanitizeFolderName(_ name: String) -> String {
        // Remove characters that are invalid in folder names
        let invalidChars = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = name.components(separatedBy: invalidChars).joined(separator: "_")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        // Limit length
        if sanitized.count > 100 {
            sanitized = String(sanitized.prefix(100))
        }
        return sanitized.isEmpty ? "Unknown" : sanitized
    }

    private func cleanupEmptyDirectories(from directory: URL, stopAt rootDir: URL) {
        var currentDir = directory

        while currentDir.path != rootDir.path && currentDir.path.hasPrefix(rootDir.path) {
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: currentDir, includingPropertiesForKeys: nil)
                if contents.isEmpty {
                    try FileManager.default.removeItem(at: currentDir)
                    print("[MyMusic] Cleaned up empty directory: \(currentDir.lastPathComponent)")
                    currentDir = currentDir.deletingLastPathComponent()
                } else {
                    break // Directory not empty, stop
                }
            } catch {
                break
            }
        }
    }

    // MARK: - Library Management

    // Known metadata mappings for existing tracks
    private static let knownMetadata: [String: (artist: String, album: String)] = [
        "Lecrae - Always Knew": ("Lecrae", "All Things Work Together"),
        "King Chav-Born Ready": ("King Chav", "The Golden Lining"),
        "Steven Malcolm": ("Steven Malcolm", "Tree"),
        "SUMMERTIME": ("Steven Malcolm", "Tree"),
        "Braille - IV": ("Braille", "The IV Edition"),
        "Fugees - The Mask": ("Fugees", "The Score"),
        "Mission ft. V. Rose - Thank the Lord": ("Mission", "Thank the Lord"),
        "Japhia Life": ("Japhia Life", "Westside Pharmacy"),
        "Small World": ("Japhia Life", "Westside Pharmacy"),
        "Ready or Not": ("Lecrae & 1K Phew", "No Church in a While"),
        "Sleight of Hand": ("King Chav", "The Leftovers"),
        "Live at the Rio": ("King Chav & Rab G", "Pen 'N Teller"),
        "Gucci Mane - 4 Lifers": ("Gucci Mane", "Instrumentals"),
        "Metro Boomin - Metro Spider": ("Metro Boomin", "Instrumentals"),
        "Travis Scott - 4X4": ("Travis Scott", "Instrumentals"),
        "Youngs Teflon - Stay Dangerous": ("Youngs Teflon", "Instrumentals"),
        "Too Young (Instrumental)": ("Unknown", "Instrumentals"),
        "Russ Type Beat": ("Type Beat", "Instrumentals"),
        "ISAIAH RASHAD": ("Type Beat", "Instrumentals"),
        "Fresh (feat. Ebonique)": ("Unknown", "Singles"),
        "Enough 2 Bury Me": ("Unknown", "Singles"),
        "HELP!": ("Unknown", "Singles"),
        "Iron Sharpens Iron": ("Unknown", "Singles"),
        "KNOCKED OUT": ("Unknown", "Singles"),
        "Letter to Lindsay": ("Unknown", "Singles"),
        "Multiple Choice": ("King Chav", "Singles"),
        "Not the Same": ("Unknown", "Singles"),
        "Parable Rhymes": ("Unknown", "Singles"),
        "Poker Face": ("Lecrae & 1K Phew", "No Church in a While"),
        "Posted Notes": ("Unknown", "Singles"),
        "Shadowboxing": ("King Chav", "The Leftovers"),
        "Sit Here": ("Unknown", "Singles"),
        "Summer Back": ("Unknown", "Singles"),
        "We Will Remember": ("Braille", "The IV Edition"),
    ]

    private func lookupKnownMetadata(for filename: String) -> (artist: String, album: String)? {
        let lowercased = filename.lowercased()
        for (pattern, meta) in Self.knownMetadata {
            if lowercased.contains(pattern.lowercased()) {
                return meta
            }
        }
        return nil
    }

    private func parseArtistFromFilename(_ filename: String) -> (artist: String, title: String)? {
        // Try common separators: " - ", " – ", " — "
        let separators = [" - ", " – ", " — "]
        for sep in separators {
            if filename.contains(sep) {
                let parts = filename.components(separatedBy: sep)
                if parts.count >= 2 {
                    let artist = parts[0].trimmingCharacters(in: .whitespaces)
                    let title = parts.dropFirst().joined(separator: sep).trimmingCharacters(in: .whitespaces)
                    return (artist, title)
                }
            }
        }
        return nil
    }

    func rescanLibrary() {
        // Clear existing library and rescan
        library.removeAll()
        UserDefaults.standard.removeObject(forKey: libraryKey)
        Task {
            await scanLibrary()
        }
    }

    /// Collect audio files from directory (synchronous helper for Swift 6 compatibility)
    private func collectAudioFiles(at directory: URL) -> [URL] {
        let audioExtensions = Set(["mp3", "m4a", "wav", "aiff", "flac", "aac"])
        var audioFiles: [URL] = []

        if let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                    audioFiles.append(fileURL)
                }
            }
        }
        return audioFiles
    }

    func scanLibrary() async {
        try? fileManager.ensureDirectoriesExist()

        let tracksDir = fileManager.fullTracksDirectory
        let artworkDir = fileManager.artworkDirectory

        // Collect audio files synchronously (Swift 6 compatible)
        let audioFiles = collectAudioFiles(at: tracksDir)

        for fileURL in audioFiles {
            // Skip if already in library
            if library.contains(where: { $0.fileURL == fileURL }) { continue }

            let filename = fileURL.deletingPathExtension().lastPathComponent
            let artworkURL = artworkDir.appendingPathComponent("\(filename).jpg")
            let hasArtwork = FileManager.default.fileExists(atPath: artworkURL.path)

            // Get duration
            var duration: TimeInterval = 0
            if let player = try? AVAudioPlayer(contentsOf: fileURL) {
                duration = player.duration
            }

            // Try to extract metadata from file first
            let asset = AVAsset(url: fileURL)
            var artist = "Unknown Artist"
            var album = "Unknown Album"
            var title = filename
            var releaseYear: Int? = nil

            // Use modern async metadata loading API
            if let metadata = try? await asset.load(.commonMetadata) {
                for item in metadata {
                    if item.commonKey == .commonKeyArtist,
                       let value = try? await item.load(.stringValue), !value.isEmpty {
                        artist = value
                    } else if item.commonKey == .commonKeyAlbumName,
                              let value = try? await item.load(.stringValue), !value.isEmpty {
                        album = value
                    } else if item.commonKey == .commonKeyTitle,
                              let value = try? await item.load(.stringValue), !value.isEmpty {
                        title = value
                    } else if item.commonKey == .commonKeyCreationDate,
                              let value = try? await item.load(.stringValue), !value.isEmpty {
                        // Try to extract year from date string (could be "2024" or "2024-01-15" etc.)
                        let yearString = String(value.prefix(4))
                        releaseYear = Int(yearString)
                    }
                }
            }

            // If metadata is missing, try known mappings
            if artist == "Unknown Artist" || album == "Unknown Album" {
                if let known = lookupKnownMetadata(for: filename) {
                    if artist == "Unknown Artist" { artist = known.artist }
                    if album == "Unknown Album" { album = known.album }
                }
            }

            // If still unknown, try parsing from filename
            if artist == "Unknown Artist" {
                if let parsed = parseArtistFromFilename(filename) {
                    artist = parsed.artist
                    // Clean up artist name
                    artist = artist
                        .replacingOccurrences(of: " (Official Audio)", with: "")
                        .replacingOccurrences(of: " (Official Video)", with: "")
                        .replacingOccurrences(of: " [Official Audio]", with: "")
                        .replacingOccurrences(of: " [Official Video]", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }

            // Detect instrumentals/type beats
            let lowerFilename = filename.lowercased()
            if lowerFilename.contains("instrumental") || lowerFilename.contains("type beat") {
                if album == "Unknown Album" { album = "Instrumentals" }
            }

            // Compute relative path for stable UUID (matches iOS)
            let musicDir = fileManager.musicDirectory
            let relativePath = String(fileURL.path.dropFirst(musicDir.path.count + 1))
            let stableID = stableUUID(from: relativePath)

            let track = TrackMetadata(
                id: stableID,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                fileURL: fileURL,
                artworkURL: hasArtwork ? artworkURL : nil,
                releaseYear: releaseYear
            )

            library.append(track)

            // Auto-sync new track to iCloud
            fileManager.copyToiCloud(fileURL: fileURL)
            if hasArtwork {
                fileManager.copyToiCloud(fileURL: artworkURL)
            }
        }

        // Remove tracks that no longer exist
        library.removeAll { !FileManager.default.fileExists(atPath: $0.fileURL.path) }

        saveLibrary()
    }

    /// Import an audio file from Finder (drag and drop)
    func importAudioFile(from sourceURL: URL) {
        Task {
            do {
                // Get metadata from file
                let asset = AVAsset(url: sourceURL)
                var artist = "Unknown Artist"
                var album = "Unknown Album"
                var title = sourceURL.deletingPathExtension().lastPathComponent

                if let metadata = try? await asset.load(.commonMetadata) {
                    for item in metadata {
                        if item.commonKey == .commonKeyArtist,
                           let value = try? await item.load(.stringValue), !value.isEmpty {
                            artist = value
                        } else if item.commonKey == .commonKeyAlbumName,
                                  let value = try? await item.load(.stringValue), !value.isEmpty {
                            album = value
                        } else if item.commonKey == .commonKeyTitle,
                                  let value = try? await item.load(.stringValue), !value.isEmpty {
                            title = value
                        }
                    }
                }

                // Create destination path: Tracks/Artist/Album/filename.ext
                let ext = sourceURL.pathExtension
                let relativePath = fileManager.organizedRelativePath(artist: artist, album: album, title: title, ext: ext)
                let destURL = fileManager.musicDirectory.appendingPathComponent(relativePath)

                // Create directory and copy file
                try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)

                // Get duration
                var duration: TimeInterval = 0
                if let player = try? AVAudioPlayer(contentsOf: destURL) {
                    duration = player.duration
                }

                // Create track metadata
                let stableID = stableUUID(from: relativePath)
                let track = TrackMetadata(
                    id: stableID,
                    title: title,
                    artist: artist,
                    album: album,
                    duration: duration,
                    fileURL: destURL,
                    artworkURL: nil,
                    releaseYear: nil
                )

                await MainActor.run {
                    library.append(track)
                    saveLibrary()
                }

                // Sync to iCloud
                fileManager.copyToiCloud(fileURL: destURL)

                print("[MyMusic] Imported: \(title) by \(artist)")
            } catch {
                print("[MyMusic] Import failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Playback

    private func setupTimer() {
        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePlaybackTime()
            }
    }

    private func updatePlaybackTime() {
        guard let player = audioPlayer, isPlaying else { return }
        currentTime = player.currentTime

        // Check if track ended
        if currentTime >= duration - 0.1 {
            handleTrackEnd()
        }
    }

    private func handleTrackEnd() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            play()
        case .all:
            playNext()
        case .off:
            if queueIndex < playQueue.count - 1 {
                playNext()
            } else {
                isPlaying = false
                currentTime = 0
            }
        }
    }

    func playTrack(_ track: TrackMetadata) {
        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: track.fileURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = Float(volume)

            currentTrack = track
            duration = audioPlayer?.duration ?? 0
            currentTime = 0

            // Update queue if playing from library
            if let index = playQueue.firstIndex(where: { $0.id == track.id }) {
                queueIndex = index
            }

            play()
        } catch {
            errorMessage = "Failed to play: \(error.localizedDescription)"
            showError = true
        }
    }

    func play() {
        audioPlayer?.play()
        isPlaying = true
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            if currentTrack == nil, let first = playQueue.first {
                playTrack(first)
            } else {
                play()
            }
        }
    }

    func playNext() {
        guard !playQueue.isEmpty else { return }

        if isShuffled {
            let randomIndex = Int.random(in: 0..<playQueue.count)
            queueIndex = randomIndex
        } else {
            queueIndex = (queueIndex + 1) % playQueue.count
        }

        playTrack(playQueue[queueIndex])
    }

    func playPrevious() {
        guard !playQueue.isEmpty else { return }

        // If more than 3 seconds in, restart current track
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        queueIndex = queueIndex > 0 ? queueIndex - 1 : playQueue.count - 1
        playTrack(playQueue[queueIndex])
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    func setVolume(_ vol: Double) {
        volume = vol
        audioPlayer?.volume = Float(vol)
    }

    func toggleShuffle() {
        isShuffled.toggle()
    }

    func toggleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Queue Management

    func setQueue(_ tracks: [TrackMetadata], startIndex: Int = 0) {
        playQueue = tracks
        queueIndex = startIndex
        if let track = tracks[safe: startIndex] {
            playTrack(track)
        }
    }

    func playAll() {
        setQueue(filteredLibrary, startIndex: 0)
    }

    func shuffleAll() {
        var shuffled = filteredLibrary
        shuffled.shuffle()
        setQueue(shuffled, startIndex: 0)
        isShuffled = true
    }

    func playPlaylist(_ playlist: Playlist) {
        selectedPlaylist = playlist
        let tracks = currentPlaylistTracks
        if !tracks.isEmpty {
            setQueue(tracks, startIndex: 0)
        }
    }

    func shufflePlaylist(_ playlist: Playlist) {
        selectedPlaylist = playlist
        var tracks = currentPlaylistTracks
        tracks.shuffle()
        if !tracks.isEmpty {
            setQueue(tracks, startIndex: 0)
            isShuffled = true
        }
    }

    // MARK: - Playlist Management

    func createPlaylist(name: String) {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        savePlaylists()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        if selectedPlaylist?.id == playlist.id {
            selectedPlaylist = nil
        }
        savePlaylists()
    }

    func addToPlaylist(_ track: TrackMetadata, playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if !playlists[index].trackIDs.contains(track.id) {
            playlists[index].trackIDs.append(track.id)
            savePlaylists()
        }
    }

    func addTrackToPlaylist(trackID: UUID, playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if !playlists[index].trackIDs.contains(trackID) {
            playlists[index].trackIDs.append(trackID)
            savePlaylists()
        }
    }

    // MARK: - Mixer Deck Queues

    func addToDeckA(_ track: TrackMetadata) {
        if !deckAQueue.contains(where: { $0.id == track.id }) {
            deckAQueue.append(track)
        }
    }

    func addToDeckB(_ track: TrackMetadata) {
        if !deckBQueue.contains(where: { $0.id == track.id }) {
            deckBQueue.append(track)
        }
    }

    func removeFromDeckA(_ track: TrackMetadata) {
        deckAQueue.removeAll { $0.id == track.id }
    }

    func removeFromDeckB(_ track: TrackMetadata) {
        deckBQueue.removeAll { $0.id == track.id }
    }

    func clearDeckAQueue() {
        deckAQueue.removeAll()
    }

    func clearDeckBQueue() {
        deckBQueue.removeAll()
    }

    func removeFromPlaylist(_ track: TrackMetadata, playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].trackIDs.removeAll { $0 == track.id }
        savePlaylists()
    }

    func createNewPlaylistInline() {
        let playlist = Playlist(name: "New Playlist")
        playlists.append(playlist)
        newPlaylistName = "New Playlist"
        editingPlaylistId = playlist.id
        savePlaylists()
    }

    func startRenamingPlaylist(_ playlist: Playlist) {
        newPlaylistName = playlist.name
        editingPlaylistId = playlist.id
    }

    func commitPlaylistRename(_ playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else {
            editingPlaylistId = nil
            return
        }

        let trimmedName = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            playlists[index].name = trimmedName
            savePlaylists()
        }
        editingPlaylistId = nil
        newPlaylistName = ""
    }

    func cancelPlaylistEdit() {
        // If it was a new playlist with default name, delete it
        if let id = editingPlaylistId,
           let playlist = playlists.first(where: { $0.id == id }),
           playlist.name == "New Playlist" && playlist.trackIDs.isEmpty {
            playlists.removeAll { $0.id == id }
            savePlaylists()
        }
        editingPlaylistId = nil
        newPlaylistName = ""
    }

    // MARK: - Download

    func downloadTrack() {
        guard !urlInput.isEmpty else { return }

        isDownloading = true
        downloadProgress = "Starting download..."

        Task {
            do {
                var track = try await downloadWithMetadata(from: urlInput)
                await MainActor.run {
                    // Organize into Artist/Album folder
                    if let newURL = organizeTrackFile(track) {
                        track.fileURL = newURL
                    }
                    library.append(track)
                    saveLibrary()

                    // Auto-sync to iCloud in background
                    fileManager.copyToiCloud(fileURL: track.fileURL)
                    if let artworkURL = track.artworkURL {
                        fileManager.copyToiCloud(fileURL: artworkURL)
                    }

                    urlInput = ""
                    isDownloading = false
                    downloadProgress = ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Download failed: \(error.localizedDescription)"
                    showError = true
                    isDownloading = false
                    downloadProgress = ""
                }
            }
        }
    }

    /// Clean YouTube URL to remove playlist and extra parameters
    private func cleanYouTubeURL(_ urlString: String) -> String {
        // Extract video ID from various YouTube URL formats
        var videoId: String?

        if urlString.contains("youtube.com/watch") {
            // Standard: https://www.youtube.com/watch?v=VIDEO_ID&list=...
            if let url = URLComponents(string: urlString),
               let vParam = url.queryItems?.first(where: { $0.name == "v" })?.value {
                videoId = vParam
            }
        } else if urlString.contains("youtu.be/") {
            // Short: https://youtu.be/VIDEO_ID?list=...
            if let url = URL(string: urlString) {
                videoId = url.lastPathComponent.components(separatedBy: "?").first
            }
        } else if urlString.contains("youtube.com/embed/") {
            // Embed: https://www.youtube.com/embed/VIDEO_ID
            if let url = URL(string: urlString) {
                videoId = url.lastPathComponent.components(separatedBy: "?").first
            }
        }

        if let id = videoId, !id.isEmpty {
            // Return clean URL with just the video ID
            return "https://www.youtube.com/watch?v=\(id)"
        }

        // Return original if we can't parse it (might be other service)
        return urlString
    }

    private func downloadWithMetadata(from urlString: String) async throws -> TrackMetadata {
        let outputDir = fileManager.fullTracksDirectory
        let artworkDir = fileManager.artworkDirectory
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)

        // Clean the URL to remove playlist parameters
        let cleanedURL = cleanYouTubeURL(urlString)
        print("[MyMusic] Original URL: \(urlString)")
        print("[MyMusic] Cleaned URL: \(cleanedURL)")

        let downloadStartTime = Date()
        let pythonPath = "/opt/homebrew/bin/python3.11"
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")

        // Step 1: Get metadata from YouTube first
        await MainActor.run { downloadProgress = "Fetching metadata..." }

        var videoTitle = ""
        var videoArtist = "Unknown Artist"
        var videoAlbum = "Unknown"
        var videoReleaseYear: Int? = nil

        let infoProcess = Process()
        infoProcess.executableURL = URL(fileURLWithPath: pythonPath)
        infoProcess.arguments = [
            "-m", "yt_dlp",
            "--dump-json",
            "--no-playlist",
            cleanedURL
        ]
        infoProcess.environment = env

        let infoPipe = Pipe()
        infoProcess.standardOutput = infoPipe
        infoProcess.standardError = Pipe()

        try infoProcess.run()

        // Read pipe data and wait for process concurrently to avoid deadlock
        let infoData: Data = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = infoPipe.fileHandleForReading.readDataToEndOfFile()
                infoProcess.waitUntilExit()
                continuation.resume(returning: data)
            }
        }

        if infoProcess.terminationStatus == 0 {
            print("[MyMusic] Got metadata response, size: \(infoData.count) bytes")
            if let json = try? JSONSerialization.jsonObject(with: infoData) as? [String: Any] {
                videoTitle = json["title"] as? String ?? ""
                print("[MyMusic] Title: \(videoTitle)")
                print("[MyMusic] Artist field: \(json["artist"] ?? "nil")")
                print("[MyMusic] Creator field: \(json["creator"] ?? "nil")")
                print("[MyMusic] Uploader field: \(json["uploader"] ?? "nil")")
                print("[MyMusic] Album field: \(json["album"] ?? "nil")")

                // Try to get artist from various fields
                if let artist = json["artist"] as? String, !artist.isEmpty {
                    videoArtist = artist
                    print("[MyMusic] Using artist: \(artist)")
                } else if let creator = json["creator"] as? String, !creator.isEmpty {
                    videoArtist = creator
                    print("[MyMusic] Using creator: \(creator)")
                } else if let uploader = json["uploader"] as? String, !uploader.isEmpty {
                    // Clean up channel names (remove " - Topic", "VEVO", etc.)
                    var cleanUploader = uploader
                    cleanUploader = cleanUploader.replacingOccurrences(of: " - Topic", with: "")
                    cleanUploader = cleanUploader.replacingOccurrences(of: "VEVO", with: "")
                    cleanUploader = cleanUploader.trimmingCharacters(in: .whitespaces)
                    videoArtist = cleanUploader
                    print("[MyMusic] Using uploader: \(cleanUploader)")
                }

                // Try to get album
                if let album = json["album"] as? String, !album.isEmpty {
                    videoAlbum = album
                    print("[MyMusic] Using album: \(album)")
                } else if let playlist = json["playlist_title"] as? String, !playlist.isEmpty {
                    videoAlbum = playlist
                }

                // Try to get release year
                if let releaseYear = json["release_year"] as? Int {
                    videoReleaseYear = releaseYear
                    print("[MyMusic] Using release year: \(releaseYear)")
                }

                // Try to parse artist - title from video title
                if videoArtist == "Unknown Artist" || videoArtist.isEmpty {
                    let separators = [" - ", " – ", " — ", " | "]
                    for sep in separators {
                        if videoTitle.contains(sep) {
                            let parts = videoTitle.components(separatedBy: sep)
                            if parts.count >= 2 {
                                videoArtist = parts[0].trimmingCharacters(in: .whitespaces)
                                print("[MyMusic] Parsed artist from title: \(videoArtist)")
                                break
                            }
                        }
                    }
                }
            }
        }

        // Step 2: Download the audio
        await MainActor.run { downloadProgress = "Downloading audio..." }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            "-m", "yt_dlp",
            "-x",
            "--audio-format", "mp3",
            "--audio-quality", "0",
            "-o", "\(outputDir.path)/%(title)s.%(ext)s",
            "--write-thumbnail",
            "--convert-thumbnails", "jpg",
            "--no-playlist",
            "--ffmpeg-location", "/opt/homebrew/bin",
            cleanedURL
        ]
        process.environment = env

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Wait on background thread to avoid blocking UI
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Download failed"
            throw NSError(domain: "PlayerViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: errorString])
        }

        // Find the new file
        let contents = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: [.contentModificationDateKey])
        let mp3Files = contents.filter { $0.pathExtension == "mp3" }
        let newFiles = mp3Files.filter { url in
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return modDate >= downloadStartTime.addingTimeInterval(-1)
        }

        guard let fileURL = newFiles.sorted(by: { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return date1 > date2
        }).first else {
            throw NSError(domain: "PlayerViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Downloaded file not found"])
        }

        // Step 3: Embed metadata with ffmpeg
        await MainActor.run { downloadProgress = "Embedding metadata..." }

        let tempURL = fileURL.deletingLastPathComponent().appendingPathComponent("temp_\(UUID().uuidString).mp3")

        let ffmpegProcess = Process()
        ffmpegProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        ffmpegProcess.arguments = [
            "-i", fileURL.path,
            "-c", "copy",
            "-metadata", "title=\(videoTitle.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : videoTitle)",
            "-metadata", "artist=\(videoArtist)",
            "-metadata", "album=\(videoAlbum)",
            "-y",
            tempURL.path
        ]
        ffmpegProcess.environment = env
        ffmpegProcess.standardOutput = Pipe()
        ffmpegProcess.standardError = Pipe()

        try ffmpegProcess.run()

        // Wait on background thread to avoid blocking UI
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                ffmpegProcess.waitUntilExit()
                continuation.resume()
            }
        }

        if ffmpegProcess.terminationStatus == 0 {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.moveItem(at: tempURL, to: fileURL)
        } else {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Move artwork
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let originalArtwork = outputDir.appendingPathComponent("\(baseName).jpg")
        let artworkURL = artworkDir.appendingPathComponent("\(baseName).jpg")

        if FileManager.default.fileExists(atPath: originalArtwork.path) {
            try? FileManager.default.removeItem(at: artworkURL)
            try? FileManager.default.moveItem(at: originalArtwork, to: artworkURL)
        }

        // Get duration
        var duration: TimeInterval = 0
        if let player = try? AVAudioPlayer(contentsOf: fileURL) {
            duration = player.duration
        }

        let title = videoTitle.isEmpty ? baseName : videoTitle

        // Compute relative path for stable UUID (matches iOS)
        let musicDir = fileManager.musicDirectory
        let relativePath = String(fileURL.path.dropFirst(musicDir.path.count + 1))
        let stableID = stableUUID(from: relativePath)

        return TrackMetadata(
            id: stableID,
            title: title,
            artist: videoArtist,
            album: videoAlbum,
            duration: duration,
            fileURL: fileURL,
            artworkURL: FileManager.default.fileExists(atPath: artworkURL.path) ? artworkURL : nil,
            releaseYear: videoReleaseYear
        )
    }

    // MARK: - Helpers

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func confirmDelete(_ track: TrackMetadata) {
        trackToDelete = track
        showDeleteConfirmation = true
    }

    func deleteTrack(_ track: TrackMetadata) {
        // Stop playback if this track is playing
        if currentTrack?.id == track.id {
            audioPlayer?.stop()
            currentTrack = nil
            isPlaying = false
        }

        // Remove from queue
        playQueue.removeAll { $0.id == track.id }

        // Remove from library
        library.removeAll { $0.id == track.id }

        // Remove from all playlists
        for i in playlists.indices {
            playlists[i].trackIDs.removeAll { $0 == track.id }
        }

        // Remove file locally
        try? FileManager.default.removeItem(at: track.fileURL)
        if let artworkURL = track.artworkURL {
            try? FileManager.default.removeItem(at: artworkURL)
        }

        saveLibrary()
        savePlaylists()
        trackToDelete = nil
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
