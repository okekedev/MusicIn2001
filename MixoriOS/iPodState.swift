//
//  iPodState.swift
//  MixoriOS
//

import SwiftUI
import AVFoundation
import Observation
import CryptoKit
import MediaPlayer

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

@Observable
@MainActor
final class iPodState {
    // Navigation
    var navigationStack: [Screen] = [.mainMenu]
    var selectedIndex: Int = 0

    // Library
    var tracks: [iPodTrack] = []
    var artists: [String] = []
    var albums: [String] = []
    var genres: [String] = []
    var playlists: [iPodPlaylist] = []

    // Playback
    var currentTrack: iPodTrack?
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Double = 0.7

    // Queue
    var playQueue: [iPodTrack] = []
    var queueIndex: Int = 0

    // Playback Settings
    var shuffleMode: ShuffleMode = .off
    var repeatMode: RepeatMode = .off

    // Appearance (default to Black theme - index 1)
    var selectedColor: iPodColor = iPodColor.presets[1]

    // Tips
    let tipManager = TipManager.shared
    var showingThankYou = false

    // Onboarding
    var showingOnboarding: Bool = false

    // Audio
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    // Sync status
    var isSyncing: Bool = false
    var syncProgress: String = ""
    var lastSyncResult: String = ""
    var showingSyncResult: Bool = false

    // Debug info
    var debugStatus: String = "Initializing..."

    /// iCloud Drive available for syncing
    private(set) var iCloudAvailable: Bool = false

    /// Local folder - always used for playback (offline-first)
    private var localMusicURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("MyMusic")
    }

    /// iCloud Drive folder (for syncing from Mac)
    private var iCloudURL: URL?

    /// Main music directory - always local for offline playback
    private var containerURL: URL {
        localMusicURL
    }

    /// Get full URL for artwork
    func artworkURL(for relativePath: String) -> URL? {
        let url = containerURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var currentScreen: Screen {
        navigationStack.last ?? .mainMenu
    }

    init() {
        // Listen for audio interruptions (phone calls, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }

        // Setup remote controls (lock screen, Control Center)
        setupRemoteCommandCenter()

        // Setup directories (iCloud Drive or local fallback)
        setupDirectories()

        loadLibrary()
        loadPlaylists()
        loadAppearanceSettings()
        checkFirstLaunch()
    }

    private func checkFirstLaunch() {
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        if !hasSeenOnboarding {
            showingOnboarding = true
        }
    }

    func dismissOnboarding() {
        showingOnboarding = false
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
    }

    // MARK: - Directory Setup

    private func setupDirectories() {
        let fm = FileManager.default

        // Always create local directories (used for playback - offline first)
        try? fm.createDirectory(at: localMusicURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: localMusicURL.appendingPathComponent("Tracks"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: localMusicURL.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
        print("[MyMusic] Local folder: \(localMusicURL.path)")

        // Check if iCloud is available for syncing
        if fm.ubiquityIdentityToken == nil {
            iCloudAvailable = false
            debugStatus = "Local only (not signed into iCloud)"
            print("[MyMusic] Not signed into iCloud - using local only")
            return
        }

        // Setup iCloud for syncing
        if let iCloudDocs = fm.url(forUbiquityContainerIdentifier: "iCloud.com.christianokeke.mymusiccontainer")?.appendingPathComponent("Documents") {
            iCloudURL = iCloudDocs
            iCloudAvailable = true
            debugStatus = "iCloud available for sync"
            print("[MyMusic] iCloud available: \(iCloudDocs.path)")

            // Ensure folders exist
            try? fm.createDirectory(at: iCloudDocs, withIntermediateDirectories: true)
            try? fm.createDirectory(at: iCloudDocs.appendingPathComponent("Tracks"), withIntermediateDirectories: true)
        } else {
            iCloudAvailable = false
            debugStatus = "iCloud container not available"
            print("[MyMusic] iCloud container not available - using local only")
        }
    }

    // MARK: - iCloud File Download

    /// Ensure a file is downloaded from iCloud before playing
    private func ensureFileDownloaded(_ url: URL) async -> Bool {
        let fm = FileManager.default

        // Check if file exists and is downloaded
        do {
            let resourceValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if resourceValues.ubiquitousItemDownloadingStatus == .current {
                return true // Already downloaded
            }

            // Start downloading
            try fm.startDownloadingUbiquitousItem(at: url)

            // Wait for download (with timeout)
            for _ in 0..<60 { // 30 second timeout
                let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if values.ubiquitousItemDownloadingStatus == .current {
                    return true
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            return false
        } catch {
            // File might be local (not iCloud), which is fine
            return fm.fileExists(atPath: url.path)
        }
    }

    // MARK: - Sync Library

    /// Sync from iCloud to local, then reload library
    func syncFromiCloudWithFeedback() {
        isSyncing = true
        syncProgress = "Syncing..."

        Task {
            let syncedCount = await syncFromiCloud { [weak self] current, total in
                await MainActor.run {
                    self?.syncProgress = "Syncing... (\(current) of \(total))"
                }
            }

            await MainActor.run {
                loadLibrary()
                loadPlaylists()
                let newCount = tracks.count

                isSyncing = false
                syncProgress = ""

                if syncedCount > 0 {
                    lastSyncResult = "Added \(syncedCount) song\(syncedCount == 1 ? "" : "s") (\(newCount) total)"
                } else {
                    lastSyncResult = "Up to date (\(newCount) songs)"
                }
                showingSyncResult = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.showingSyncResult = false
                }
            }
        }
    }

    /// Collect all file URLs from a directory (synchronous helper for Swift 6 compatibility)
    private func collectFiles(at directory: URL, withExtensions extensions: [String]) -> [URL] {
        var files: [URL] = []
        let fm = FileManager.default
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

    /// Check if an iCloud file is downloaded and ready to copy
    private func waitForDownload(_ url: URL, timeout: Int = 30) async -> Bool {
        let fm = FileManager.default

        // Start the download
        try? fm.startDownloadingUbiquitousItem(at: url)

        // Wait for download to complete
        for _ in 0..<(timeout * 2) {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey])

                // Check if fully downloaded
                if resourceValues.ubiquitousItemDownloadingStatus == .current {
                    return true
                }

                // Wait 0.5 seconds before checking again
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                // Not an iCloud file or already local - check if it exists
                return fm.fileExists(atPath: url.path)
            }
        }
        return false
    }

    /// Download files from iCloud to local folder
    private func syncFromiCloud(progress: ((Int, Int) async -> Void)? = nil) async -> Int {
        guard iCloudAvailable, let iCloudBase = iCloudURL else { return 0 }

        let fm = FileManager.default
        var syncedTrackCount = 0
        var skippedCount = 0
        let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac"]
        let imageExtensions = ["jpg", "jpeg", "png"]

        // Sync Tracks: iCloud → Local
        let iCloudTracksDir = iCloudBase.appendingPathComponent("Tracks")
        let localTracksDir = localMusicURL.appendingPathComponent("Tracks")

        let iCloudTrackFiles = collectFiles(at: iCloudTracksDir, withExtensions: audioExtensions)
        let totalTracks = iCloudTrackFiles.count
        print("[MyMusic] Found \(totalTracks) tracks in iCloud")

        var currentTrack = 0
        for fileURL in iCloudTrackFiles {
            currentTrack += 1
            let relativePath = String(fileURL.path.dropFirst(iCloudTracksDir.path.count + 1))
            let destURL = localTracksDir.appendingPathComponent(relativePath)

            // Skip if already exists locally
            if fm.fileExists(atPath: destURL.path) {
                skippedCount += 1
                continue
            }

            // Update progress
            await progress?(currentTrack, totalTracks)

            // Wait for iCloud file to download (up to 10 seconds per file)
            let isDownloaded = await waitForDownload(fileURL, timeout: 10)
            guard isDownloaded else {
                print("[MyMusic] Skipped (not downloaded): \(relativePath)")
                continue
            }

            do {
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: fileURL, to: destURL)
                print("[MyMusic] iCloud → Local: \(relativePath)")
                syncedTrackCount += 1
            } catch {
                print("[MyMusic] Failed to sync: \(error.localizedDescription)")
            }
        }

        print("[MyMusic] Sync complete: \(syncedTrackCount) new tracks, \(skippedCount) already local")

        // Sync Artwork: iCloud → Local (don't count towards song total)
        let iCloudArtworkDir = iCloudBase.appendingPathComponent("Artwork")
        let localArtworkDir = localMusicURL.appendingPathComponent("Artwork")

        let iCloudArtworkFiles = collectFiles(at: iCloudArtworkDir, withExtensions: imageExtensions)
        var artworkSynced = 0
        for fileURL in iCloudArtworkFiles {
            let isDownloaded = await waitForDownload(fileURL, timeout: 5)
            guard isDownloaded else { continue }

            let filename = fileURL.lastPathComponent
            let destURL = localArtworkDir.appendingPathComponent(filename)

            if !fm.fileExists(atPath: destURL.path) {
                do {
                    try fm.copyItem(at: fileURL, to: destURL)
                    artworkSynced += 1
                } catch {}
            }
        }
        if artworkSynced > 0 {
            print("[MyMusic] Synced \(artworkSynced) artwork files")
        }

        // Sync Playlists: iCloud → Local
        let iCloudPlaylistsFile = iCloudBase.appendingPathComponent("playlists.json")
        let localPlaylistsFile = localMusicURL.appendingPathComponent("playlists.json")

        print("[MyMusic] Checking for playlists at: \(iCloudPlaylistsFile.path)")

        // Wait for playlist file to download from iCloud (up to 5 seconds)
        let playlistDownloaded = await waitForDownload(iCloudPlaylistsFile, timeout: 5)
        print("[MyMusic] Playlist download result: \(playlistDownloaded), exists: \(fm.fileExists(atPath: iCloudPlaylistsFile.path))")

        if playlistDownloaded && fm.fileExists(atPath: iCloudPlaylistsFile.path) {
            let iCloudDate = (try? fm.attributesOfItem(atPath: iCloudPlaylistsFile.path)[.modificationDate] as? Date) ?? .distantPast
            let localDate = (try? fm.attributesOfItem(atPath: localPlaylistsFile.path)[.modificationDate] as? Date) ?? .distantPast

            print("[MyMusic] Playlist dates - iCloud: \(iCloudDate), Local: \(localDate)")

            if iCloudDate > localDate || !fm.fileExists(atPath: localPlaylistsFile.path) {
                try? fm.removeItem(at: localPlaylistsFile)
                do {
                    try fm.copyItem(at: iCloudPlaylistsFile, to: localPlaylistsFile)
                    print("[MyMusic] Synced playlists from iCloud")
                } catch {
                    print("[MyMusic] Failed to sync playlists: \(error.localizedDescription)")
                }
            } else {
                print("[MyMusic] Local playlists are up to date")
            }
        } else {
            print("[MyMusic] No playlists file in iCloud")
        }

        return syncedTrackCount
    }

    // MARK: - Appearance

    func loadAppearanceSettings() {
        if let colorIndex = UserDefaults.standard.object(forKey: "MixorColorIndex") as? Int,
           colorIndex < iPodColor.presets.count {
            selectedColor = iPodColor.presets[colorIndex]
        }
    }

    func saveAppearanceSettings() {
        if let index = iPodColor.presets.firstIndex(where: { $0.name == selectedColor.name }) {
            UserDefaults.standard.set(index, forKey: "MixorColorIndex")
        }
    }

    func selectColor(_ color: iPodColor) {
        selectedColor = color
        saveAppearanceSettings()
    }

    // MARK: - Library

    func loadLibrary() {
        let tracksDir = containerURL.appendingPathComponent("Tracks")

        guard FileManager.default.fileExists(atPath: tracksDir.path) else {
            print("[MyMusic] Tracks directory does not exist")
            debugStatus += " | No Tracks folder"
            return
        }
        guard let enumerator = FileManager.default.enumerator(at: tracksDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            print("[MyMusic] Could not enumerate Tracks directory")
            return
        }

        var loadedTracks: [iPodTrack] = []
        let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac"]

        for case let fileURL as URL in enumerator {
            guard audioExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

            let components = fileURL.pathComponents
            guard components.count >= 4 else { continue }

            // Default metadata from path
            let title = fileURL.deletingPathExtension().lastPathComponent
            let artist = components[components.count - 3]
            let album = components[components.count - 2]
            let genre = "Unknown"
            var trackDuration: TimeInterval = 0

            // Get duration
            if let player = try? AVAudioPlayer(contentsOf: fileURL) {
                trackDuration = player.duration
            }

            // Calculate relative path - standardize paths to handle /private/var vs /var
            let standardizedFile = fileURL.standardizedFileURL.path
            let standardizedTracksDir = tracksDir.standardizedFileURL.path
            let afterTracksDir = String(standardizedFile.dropFirst(standardizedTracksDir.count))
            let cleanPath = afterTracksDir.hasPrefix("/") ? String(afterTracksDir.dropFirst()) : afterTracksDir
            let relativePath = "Tracks/" + cleanPath

            // Check for artwork in Artwork folder (same name as audio file with .jpg)
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let artworkPath = "Artwork/\(baseName).jpg"
            let artworkFullPath = containerURL.appendingPathComponent(artworkPath)
            let hasArtwork = FileManager.default.fileExists(atPath: artworkFullPath.path)

            let track = iPodTrack(
                id: stableUUID(from: relativePath),
                title: title,
                artist: artist,
                album: album,
                genre: genre,
                duration: trackDuration,
                relativePath: relativePath,
                artworkRelativePath: hasArtwork ? artworkPath : nil
            )
            loadedTracks.append(track)
        }

        tracks = loadedTracks.sorted { $0.title < $1.title }
        artists = Array(Set(tracks.map { $0.artist })).sorted()
        albums = Array(Set(tracks.map { $0.album })).sorted()
        genres = Array(Set(tracks.map { $0.genre })).filter { $0 != "Unknown" }.sorted()

        print("[MyMusic] Loaded \(tracks.count) tracks, \(artists.count) artists, \(albums.count) albums")
        debugStatus += " | \(tracks.count) songs"
    }

    // MARK: - On-The-Go Playlist (iPod Classic style)

    private var onTheGoKey: String { "MixorOnTheGoTrackIDs" }

    var onTheGoTrackIDs: [UUID] {
        get {
            guard let data = UserDefaults.standard.data(forKey: onTheGoKey),
                  let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
                return []
            }
            return ids
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: onTheGoKey)
            }
        }
    }

    var onTheGoTracks: [iPodTrack] {
        onTheGoTrackIDs.compactMap { id in
            tracks.first { $0.id == id }
        }
    }

    func addToOnTheGo(_ track: iPodTrack) {
        if !onTheGoTrackIDs.contains(track.id) {
            onTheGoTrackIDs.append(track.id)
        }
    }

    func removeFromOnTheGo(_ track: iPodTrack) {
        onTheGoTrackIDs.removeAll { $0 == track.id }
    }

    func clearOnTheGo() {
        onTheGoTrackIDs = []
    }

    // Check if current selection is a song that can be added to On-The-Go
    func canAddCurrentToOnTheGo() -> Bool {
        switch currentScreen {
        case .songs, .albumTracks, .genreTracks, .playlist:
            let items = menuItems(for: currentScreen)
            guard selectedIndex < items.count else { return false }
            return items[selectedIndex].action != nil // Has an action = is a playable song
        default:
            return false
        }
    }

    // Get the track at current selection (if it's a song)
    func currentSelectedTrack() -> iPodTrack? {
        switch currentScreen {
        case .songs:
            guard selectedIndex < tracks.count else { return nil }
            return tracks[selectedIndex]
        case .albumTracks(let album):
            let albumTracks = tracks.filter { $0.album == album }
            guard selectedIndex < albumTracks.count else { return nil }
            return albumTracks[selectedIndex]
        case .genreTracks(let genre):
            let genreTracks = tracks.filter { $0.genre == genre }
            guard selectedIndex < genreTracks.count else { return nil }
            return genreTracks[selectedIndex]
        case .playlist(let name):
            guard let playlist = playlists.first(where: { $0.name == name }) else { return nil }
            let playlistTracks = tracksForPlaylist(playlist)
            guard selectedIndex < playlistTracks.count else { return nil }
            return playlistTracks[selectedIndex]
        default:
            return nil
        }
    }

    // MARK: - Playlists

    private var playlistsURL: URL {
        containerURL.appendingPathComponent("playlists.json")
    }

    func loadPlaylists() {
        guard FileManager.default.fileExists(atPath: playlistsURL.path),
              let data = try? Data(contentsOf: playlistsURL),
              let loaded = try? JSONDecoder().decode([iPodPlaylist].self, from: data) else {
            return
        }
        playlists = loaded
    }

    func savePlaylists() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: playlistsURL)
    }

    func createPlaylist(name: String) {
        let playlist = iPodPlaylist(id: UUID(), name: name, trackIDs: [])
        playlists.append(playlist)
        savePlaylists()
    }

    func addTrackToPlaylist(_ track: iPodTrack, playlist: iPodPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if !playlists[index].trackIDs.contains(track.id) {
            playlists[index].trackIDs.append(track.id)
            savePlaylists()
        }
    }

    func removeTrackFromPlaylist(_ track: iPodTrack, playlist: iPodPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].trackIDs.removeAll { $0 == track.id }
        savePlaylists()
    }

    func deletePlaylist(_ playlist: iPodPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
    }

    func tracksForPlaylist(_ playlist: iPodPlaylist) -> [iPodTrack] {
        playlist.trackIDs.compactMap { id in
            tracks.first { $0.id == id }
        }
    }

    // MARK: - Menu Items

    func menuItems(for screen: Screen) -> [MenuItem] {
        switch screen {
        // MARK: Main Menu (iPod Classic order)
        case .mainMenu:
            let statusIcon = iCloudAvailable ? "☁️" : "⚠️"
            return [
                MenuItem(title: "Now Playing", destination: .nowPlaying),
                MenuItem(title: "Music", destination: .music),
                MenuItem(title: "Settings", destination: .settings),
                MenuItem(title: isSyncing ? "Syncing..." : "Sync Library") { [weak self] in
                    self?.syncFromiCloudWithFeedback()
                },
                MenuItem(title: "\(statusIcon) \(tracks.count) songs")
            ]

        // MARK: Music Menu (iPod Classic order)
        case .music:
            var items: [MenuItem] = [
                MenuItem(title: "Playlists", destination: .playlists),
                MenuItem(title: "Artists", destination: .artists),
                MenuItem(title: "Albums", destination: .albums),
                MenuItem(title: "Songs", destination: .songs)
            ]
            if !genres.isEmpty {
                items.append(MenuItem(title: "Genres", destination: .genres))
            }
            return items

        // MARK: Playlists
        case .playlists:
            var items: [MenuItem] = [
                MenuItem(title: "On-The-Go", destination: .onTheGo)
            ]
            items += playlists.map { playlist in
                MenuItem(title: playlist.name, destination: .playlist(name: playlist.name))
            }
            return items

        case .onTheGo:
            if onTheGoTracks.isEmpty {
                return [MenuItem(title: "No Songs")]
            }
            var items: [MenuItem] = [
                MenuItem(title: "Shuffle", icon: "shuffle") { [weak self] in
                    self?.shuffleTracks(self?.onTheGoTracks ?? [])
                },
                MenuItem(title: "Play All", icon: "play.fill") { [weak self] in
                    self?.playAllTracks(self?.onTheGoTracks ?? [])
                }
            ]
            items += onTheGoTracks.map { track in
                MenuItem(title: track.title) { [weak self] in
                    guard let self = self else { return }
                    self.playTrack(track, queue: self.onTheGoTracks)
                }
            }
            // Add Clear Playlist option at the end
            items.append(MenuItem(title: "Clear Playlist") { [weak self] in
                self?.clearOnTheGo()
            })
            return items

        case .playlist(let name):
            guard let playlist = playlists.first(where: { $0.name == name }) else { return [] }
            let playlistTracks = tracksForPlaylist(playlist)
            if playlistTracks.isEmpty {
                return [MenuItem(title: "No Songs")]
            }
            var items: [MenuItem] = [
                MenuItem(title: "Shuffle", icon: "shuffle") { [weak self] in
                    self?.shuffleTracks(playlistTracks)
                },
                MenuItem(title: "Play All", icon: "play.fill") { [weak self] in
                    self?.playAllTracks(playlistTracks)
                }
            ]
            items += playlistTracks.map { track in
                MenuItem(title: track.title) { [weak self] in
                    self?.playTrack(track, queue: playlistTracks)
                }
            }
            return items

        // MARK: Artists
        case .artists:
            if artists.isEmpty {
                return [MenuItem(title: "No Artists")]
            }
            return artists.map { artist in
                MenuItem(title: artist, destination: .artistAlbums(artist: artist))
            }

        case .artistAlbums(let artist):
            let artistTracks = tracks.filter { $0.artist == artist }
            let artistAlbums = Array(Set(artistTracks.map { $0.album })).sorted()

            // Add Shuffle and Play All options at top
            var items: [MenuItem] = [
                MenuItem(title: "Shuffle", icon: "shuffle") { [weak self] in
                    self?.shuffleTracks(artistTracks)
                },
                MenuItem(title: "Play All", icon: "play.fill") { [weak self] in
                    self?.playAllTracks(artistTracks)
                }
            ]
            items += artistAlbums.map { album in
                MenuItem(title: album, destination: .albumTracks(album: album))
            }
            return items

        // MARK: Albums
        case .albums:
            if albums.isEmpty {
                return [MenuItem(title: "No Albums")]
            }
            return albums.map { album in
                MenuItem(title: album, destination: .albumTracks(album: album))
            }

        case .albumTracks(let album):
            let albumTracks = tracks.filter { $0.album == album }.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            if albumTracks.isEmpty {
                return [MenuItem(title: "No Songs")]
            }
            var items: [MenuItem] = [
                MenuItem(title: "Shuffle", icon: "shuffle") { [weak self] in
                    self?.shuffleTracks(albumTracks)
                },
                MenuItem(title: "Play All", icon: "play.fill") { [weak self] in
                    self?.playAllTracks(albumTracks)
                }
            ]
            items += albumTracks.map { track in
                MenuItem(title: track.title) { [weak self] in
                    self?.playTrack(track, queue: albumTracks)
                }
            }
            return items

        // MARK: Songs
        case .songs:
            if tracks.isEmpty {
                return [MenuItem(title: "No Songs")]
            }
            var items: [MenuItem] = [
                MenuItem(title: "Shuffle", icon: "shuffle") { [weak self] in
                    self?.shuffleTracks(self?.tracks ?? [])
                },
                MenuItem(title: "Play All", icon: "play.fill") { [weak self] in
                    self?.playAllTracks(self?.tracks ?? [])
                }
            ]
            items += tracks.map { track in
                MenuItem(title: track.title) { [weak self] in
                    self?.playTrack(track, queue: self?.tracks ?? [])
                }
            }
            return items

        // MARK: Genres
        case .genres:
            return genres.map { genre in
                MenuItem(title: genre, destination: .genreTracks(genre: genre))
            }

        case .genreTracks(let genre):
            let genreTracks = tracks.filter { $0.genre == genre }
            if genreTracks.isEmpty {
                return [MenuItem(title: "No Songs")]
            }
            var items: [MenuItem] = [
                MenuItem(title: "Shuffle", icon: "shuffle") { [weak self] in
                    self?.shuffleTracks(genreTracks)
                },
                MenuItem(title: "Play All", icon: "play.fill") { [weak self] in
                    self?.playAllTracks(genreTracks)
                }
            ]
            items += genreTracks.map { track in
                MenuItem(title: track.title) { [weak self] in
                    self?.playTrack(track, queue: genreTracks)
                }
            }
            return items

        // MARK: Settings (iPod Classic order)
        case .settings:
            return [
                MenuItem(title: "How to Use", destination: .howToUse),
                MenuItem(title: "Repeat", destination: .repeatSetting),
                MenuItem(title: "Color", destination: .colorPicker),
                MenuItem(title: "Support", destination: .support)
            ]

        case .howToUse:
            return [
                MenuItem(title: "1. Get MyMusic on a Mac"),
                MenuItem(title: "2. Add songs via MP3 or link"),
                MenuItem(title: "3. Open this app"),
                MenuItem(title: "4. Click Sync")
            ]

        case .support:
            return [
                MenuItem(title: tipManager.displayPrice(for: "com.christianokeke.MyMusiciOS.tip1")) { [weak self] in
                    self?.purchaseTip(productID: "com.christianokeke.MyMusiciOS.tip1")
                },
                MenuItem(title: tipManager.displayPrice(for: "com.christianokeke.MyMusiciOS.tip5")) { [weak self] in
                    self?.purchaseTip(productID: "com.christianokeke.MyMusiciOS.tip5")
                },
                MenuItem(title: tipManager.displayPrice(for: "com.christianokeke.MyMusiciOS.tip20")) { [weak self] in
                    self?.purchaseTip(productID: "com.christianokeke.MyMusiciOS.tip20")
                },
                MenuItem(title: tipManager.displayPrice(for: "com.christianokeke.MyMusiciOS.tip100")) { [weak self] in
                    self?.purchaseTip(productID: "com.christianokeke.MyMusiciOS.tip100")
                }
            ]

        case .repeatSetting:
            return RepeatMode.allCases.map { mode in
                let isSelected = repeatMode == mode
                return MenuItem(title: isSelected ? "\(mode.rawValue) ✓" : mode.rawValue) { [weak self] in
                    self?.repeatMode = mode
                    self?.goBack()
                }
            }

        case .colorPicker:
            return iPodColor.presets.map { color in
                let isSelected = selectedColor.name == color.name
                return MenuItem(title: isSelected ? "\(color.name) ✓" : color.name) { [weak self] in
                    self?.selectColor(color)
                    self?.goBack()
                }
            }

        case .nowPlaying:
            return []
        }
    }

    // MARK: - Tips

    func purchaseTip(productID: String) {
        guard let product = tipManager.product(for: productID) else { return }
        Task {
            let success = await tipManager.purchase(product)
            if success {
                showingThankYou = true
                // Auto-dismiss after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.showingThankYou = false
                    self?.goBack()
                }
            }
        }
    }

    // MARK: - Shuffle & Play All

    func shuffleTracks(_ tracksToShuffle: [iPodTrack]) {
        guard !tracksToShuffle.isEmpty else { return }
        var shuffled = tracksToShuffle
        shuffled.shuffle()
        guard let firstTrack = shuffled.first else { return }

        // Temporarily enable shuffle for this playback
        let previousShuffle = shuffleMode
        shuffleMode = .songs
        playTrack(firstTrack, queue: shuffled)
        shuffleMode = previousShuffle
    }

    func playAllTracks(_ tracksToPlay: [iPodTrack]) {
        guard let firstTrack = tracksToPlay.first else { return }
        playTrack(firstTrack, queue: tracksToPlay)
    }

    // MARK: - Navigation

    func navigate(to screen: Screen) {
        navigationStack.append(screen)
        selectedIndex = 0
    }

    func goBack() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        selectedIndex = 0
    }

    func selectCurrentItem() {
        let items = menuItems(for: currentScreen)
        guard selectedIndex < items.count else { return }

        let item = items[selectedIndex]
        if let action = item.action {
            action()
        } else if let destination = item.destination {
            navigate(to: destination)
        }
    }

    func scrollUp() {
        let items = menuItems(for: currentScreen)
        guard !items.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func scrollDown() {
        let items = menuItems(for: currentScreen)
        guard !items.isEmpty else { return }
        selectedIndex = min(items.count - 1, selectedIndex + 1)
    }

    // MARK: - Playback

    func playTrack(_ track: iPodTrack, queue: [iPodTrack]) {
        currentTrack = track

        // Apply shuffle if enabled
        if shuffleMode == .songs {
            // Put selected track first, shuffle the rest
            var shuffledQueue = queue.filter { $0 != track }
            shuffledQueue.shuffle()
            playQueue = [track] + shuffledQueue
            queueIndex = 0
        } else if shuffleMode == .albums {
            // Shuffle album order but keep songs in album order
            let albumGroups = Dictionary(grouping: queue) { $0.album }
            var shuffledAlbums = Array(albumGroups.keys).shuffled()
            // Move current track's album to front
            if let currentAlbum = shuffledAlbums.first(where: { $0 == track.album }) {
                shuffledAlbums.removeAll { $0 == currentAlbum }
                shuffledAlbums.insert(currentAlbum, at: 0)
            }
            playQueue = shuffledAlbums.flatMap { albumGroups[$0] ?? [] }
            queueIndex = playQueue.firstIndex(of: track) ?? 0
        } else {
            playQueue = queue
            queueIndex = queue.firstIndex(of: track) ?? 0
        }

        let fileURL = containerURL.appendingPathComponent(track.relativePath).standardizedFileURL

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = Float(volume)
            audioPlayer?.play()
            isPlaying = true
            duration = audioPlayer?.duration ?? 0
            startTimer()
            updateNowPlayingInfo()
            navigate(to: .nowPlaying)
        } catch {
            print("[MyMusic] Playback error: \(error.localizedDescription)")
        }
    }

    func togglePlayPause() {
        guard let player = audioPlayer else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func nextTrack() {
        // Repeat One: stay on current track
        if repeatMode == .one {
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
            currentTime = 0
            return
        }

        // Check if at end of queue
        if queueIndex >= playQueue.count - 1 {
            // Repeat All: loop back to start (re-shuffle if needed)
            if repeatMode == .all {
                if shuffleMode == .songs {
                    playQueue.shuffle()
                }
                queueIndex = 0
                playCurrentQueueTrack()
            }
            // Repeat Off: stop at end
            return
        }

        // Normal next
        queueIndex += 1
        playCurrentQueueTrack()
    }

    func previousTrack() {
        if currentTime > 3 {
            audioPlayer?.currentTime = 0
            currentTime = 0
        } else if queueIndex > 0 {
            queueIndex -= 1
            playCurrentQueueTrack()
        } else if repeatMode == .all {
            // Wrap to end of queue
            queueIndex = playQueue.count - 1
            playCurrentQueueTrack()
        }
    }

    private func playCurrentQueueTrack() {
        guard queueIndex < playQueue.count else { return }
        let track = playQueue[queueIndex]
        currentTrack = track
        let fileURL = containerURL.appendingPathComponent(track.relativePath)

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.volume = Float(volume)
            audioPlayer?.play()
            isPlaying = true
            duration = audioPlayer?.duration ?? 0
            startTimer()
        } catch {
            print("Failed to play: \(error)")
        }
    }

    func setVolume(_ newVolume: Double) {
        volume = max(0, min(1, newVolume))
        audioPlayer?.volume = Float(volume)
    }

    func adjustVolume(by delta: Double) {
        setVolume(volume + delta)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updatePlaybackState()
            }
        }
    }

    private func updatePlaybackState() {
        currentTime = audioPlayer?.currentTime ?? 0
        updateNowPlayingInfo()

        // Auto-advance when track ends
        if let player = audioPlayer,
           !player.isPlaying && isPlaying && currentTime >= duration - 0.5 {
            nextTrack()
        }
    }

    // MARK: - Audio Interruption Handling

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began (e.g., phone call)
            if isPlaying {
                audioPlayer?.pause()
            }
        case .ended:
            // Interruption ended
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && isPlaying {
                    audioPlayer?.play()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Now Playing Info (Lock Screen & Control Center)

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrack()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousTrack()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.audioPlayer?.currentTime = event.positionTime
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        // Add artwork if available
        if let artworkPath = track.artworkRelativePath,
           let artworkURL = artworkURL(for: artworkPath),
           let imageData = try? Data(contentsOf: artworkURL),
           let uiImage = UIImage(data: imageData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: uiImage.size) { _ in uiImage }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
