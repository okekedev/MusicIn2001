import SwiftUI

struct PlayerView: View {
    @ObservedObject private var viewModel = PlayerViewModel.shared
    @StateObject private var themeManager = ThemeManager.shared
    @EnvironmentObject var appState: AppState
    @Binding var showingSettings: Bool
    @State private var searchText = ""
    @State private var showDownloadSidebar = false
    @State private var showSearch = false
    @State private var showThemeEditor = false
    @State private var showMixerStopConfirmation = false
    @State private var pendingTrackPlay: (() -> Void)?

    private func dismissControls() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showSearch = false
            searchText = ""
            showDownloadSidebar = false
            showThemeEditor = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content
            HStack(spacing: 0) {
                // Left sidebar - Playlists
                PlaylistSidebar(viewModel: viewModel)
                    .frame(width: 180)
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in dismissControls() }
                    )

                // Center - Library/Track list
                TrackListView(
                    viewModel: viewModel,
                    searchText: $searchText,
                    onPlayTrack: playTrack
                )
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in dismissControls() }
                )

                // Right mini toolbar with expandable panels
                MiniToolbar(
                    viewModel: viewModel,
                    showSearch: $showSearch,
                    searchText: $searchText,
                    showThemeEditor: $showThemeEditor,
                    showDownloadSidebar: $showDownloadSidebar,
                    showingSettings: $showingSettings
                )
            }

            // Bottom - Now Playing Bar
            NowPlayingBar(viewModel: viewModel)
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in dismissControls() }
                )
        }
        .background(Music2001Theme.background)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .alert("Delete Track?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.trackToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let track = viewModel.trackToDelete {
                    viewModel.deleteTrack(track)
                }
            }
        } message: {
            if let track = viewModel.trackToDelete {
                Text("Are you sure you want to delete \"\(track.title)\"? This will remove the file from your library.")
            }
        }
        .alert("Stop Mixer?", isPresented: $showMixerStopConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingTrackPlay = nil
            }
            Button("Stop & Play", role: .destructive) {
                appState.isMixerActive = false
                pendingTrackPlay?()
                pendingTrackPlay = nil
            }
        } message: {
            Text("Playing this track will stop the mixer. Are you sure?")
        }
    }

    func playTrack(_ action: @escaping () -> Void) {
        if appState.isMixerActive {
            pendingTrackPlay = action
            showMixerStopConfirmation = true
        } else {
            action()
        }
    }
}

// MARK: - Playlist Sidebar

struct PlaylistSidebar: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Library")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Music2001Theme.textPrimary)
                Spacer()
            }
            .padding(12)
            .background(Music2001Theme.cardBackground)

            // View mode options
            VStack(spacing: 2) {
                SidebarButton(
                    icon: "music.note.list",
                    title: "Songs",
                    count: viewModel.library.count,
                    isSelected: viewModel.viewMode == .songs && viewModel.selectedPlaylist == nil && viewModel.selectedArtist == nil && viewModel.selectedAlbum == nil
                ) {
                    viewModel.viewMode = .songs
                    viewModel.selectedPlaylist = nil
                    viewModel.selectedArtist = nil
                    viewModel.selectedAlbum = nil
                }

                SidebarButton(
                    icon: "person.2",
                    title: "Artists",
                    count: viewModel.allArtists.count,
                    isSelected: viewModel.viewMode == .artists && viewModel.selectedPlaylist == nil
                ) {
                    viewModel.viewMode = .artists
                    viewModel.selectedPlaylist = nil
                    viewModel.selectedAlbum = nil
                }

                SidebarButton(
                    icon: "square.stack",
                    title: "Albums",
                    count: viewModel.allAlbums.count,
                    isSelected: viewModel.viewMode == .albums && viewModel.selectedPlaylist == nil
                ) {
                    viewModel.viewMode = .albums
                    viewModel.selectedPlaylist = nil
                    viewModel.selectedArtist = nil
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 8)

            // Playlists header
            HStack {
                Text("Playlists")
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textSecondary)
                Spacer()
                Button {
                    viewModel.createNewPlaylistInline()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(Music2001Theme.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)

            // Playlist list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.playlists) { playlist in
                        if viewModel.editingPlaylistId == playlist.id {
                            // Inline editing row
                            EditablePlaylistRow(
                                name: $viewModel.newPlaylistName,
                                onCommit: {
                                    viewModel.commitPlaylistRename(playlist)
                                },
                                onCancel: {
                                    viewModel.cancelPlaylistEdit()
                                }
                            )
                        } else {
                            PlaylistRow(
                                playlist: playlist,
                                isSelected: viewModel.selectedPlaylist?.id == playlist.id,
                                onSelect: {
                                    viewModel.selectedPlaylist = playlist
                                    viewModel.selectedArtist = nil
                                    viewModel.selectedAlbum = nil
                                },
                                onRename: {
                                    viewModel.startRenamingPlaylist(playlist)
                                },
                                onDelete: { viewModel.deletePlaylist(playlist) },
                                onAddTrack: { trackID in
                                    viewModel.addTrackToPlaylist(trackID: trackID, playlist: playlist)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }

            Spacer()
        }
        .background(Music2001Theme.cardBackground.opacity(0.5))
    }
}

struct PlaylistRow: View {
    let playlist: Playlist
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onAddTrack: ((UUID) -> Void)?

    @State private var isDropTargeted = false

    init(playlist: Playlist, isSelected: Bool, onSelect: @escaping () -> Void, onRename: @escaping () -> Void, onDelete: @escaping () -> Void, onAddTrack: ((UUID) -> Void)? = nil) {
        self.playlist = playlist
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRename = onRename
        self.onDelete = onDelete
        self.onAddTrack = onAddTrack
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.caption)
                    .foregroundColor(isSelected ? Music2001Theme.primary : Music2001Theme.textSecondary)
                Text(playlist.name)
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(playlist.trackIDs.count)")
                    .font(.caption2)
                    .foregroundColor(Music2001Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isDropTargeted ? Music2001Theme.primary.opacity(0.3) : (isSelected ? Music2001Theme.primary.opacity(0.15) : Color.clear))
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.text], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { string, error in
                if let trackIDString = string, let trackID = UUID(uuidString: trackIDString) {
                    DispatchQueue.main.async {
                        onAddTrack?(trackID)
                    }
                }
            }
            return true
        }
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Playlist", systemImage: "trash")
            }
        }
    }
}

struct EditablePlaylistRow: View {
    @Binding var name: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.caption)
                .foregroundColor(Music2001Theme.primary)
            TextField("Playlist name", text: $name)
                .font(.caption)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    onCommit()
                }
                .onExitCommand {
                    onCancel()
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Music2001Theme.primary.opacity(0.15))
        .cornerRadius(6)
        .onAppear {
            isFocused = true
        }
    }
}

struct SidebarButton: View {
    let icon: String
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(isSelected ? Music2001Theme.primary : Music2001Theme.textSecondary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(Music2001Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Music2001Theme.primary.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Track List

struct TrackListView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @EnvironmentObject var appState: AppState
    @Binding var searchText: String
    var onPlayTrack: ((@escaping () -> Void) -> Void)?

    @State private var editingTrack: TrackMetadata?
    @State private var showingAddSongs = false
    @State private var isDropTargeted = false

    var viewMode: PlayerViewModel.ViewMode {
        viewModel.viewMode
    }

    var tracks: [TrackMetadata] {
        let baseTracks: [TrackMetadata]
        if viewModel.selectedPlaylist != nil {
            baseTracks = viewModel.currentPlaylistTracks
        } else {
            baseTracks = viewModel.filteredLibrary
        }

        // Apply search filter
        if searchText.isEmpty {
            return baseTracks
        }
        return baseTracks.filter { track in
            track.title.localizedCaseInsensitiveContains(searchText) ||
            track.artist.localizedCaseInsensitiveContains(searchText) ||
            track.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    var headerTitle: String {
        if let artist = viewModel.selectedArtist {
            return artist
        } else if let album = viewModel.selectedAlbum {
            return album
        } else if let playlist = viewModel.selectedPlaylist {
            return playlist.name
        }
        return viewModel.viewMode.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button if filtering
            if viewModel.selectedArtist != nil || viewModel.selectedAlbum != nil || viewModel.selectedPlaylist != nil {
                HStack {
                    if viewModel.selectedArtist != nil || viewModel.selectedAlbum != nil {
                        Button {
                            viewModel.selectedArtist = nil
                            viewModel.selectedAlbum = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.caption)
                                Text("Back")
                                    .font(.caption)
                            }
                            .foregroundColor(Music2001Theme.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(headerTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Music2001Theme.textPrimary)

                    Spacer()

                    // Add Songs button (only for playlists)
                    if viewModel.selectedPlaylist != nil {
                        Button {
                            showingAddSongs = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.caption2)
                                Text("Add Songs")
                                    .font(.caption)
                            }
                            .foregroundColor(Music2001Theme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Music2001Theme.primary.opacity(0.15))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    // Play All button
                    if !tracks.isEmpty {
                        Button {
                            if let onPlayTrack = onPlayTrack {
                                onPlayTrack {
                                    viewModel.setQueue(tracks, startIndex: 0)
                                }
                            } else {
                                viewModel.setQueue(tracks, startIndex: 0)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.caption2)
                                Text("Play All")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Music2001Theme.primary)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("\(tracks.count) songs")
                        .font(.caption)
                        .foregroundColor(Music2001Theme.textTertiary)
                        .padding(.leading, 8)
                }
                .padding(12)
                .background(Music2001Theme.cardBackground)
            }

            // Content based on view mode
            if viewMode == .artists && viewModel.selectedArtist == nil && viewModel.selectedPlaylist == nil {
                // Artists list
                ArtistsListView(viewModel: viewModel)
            } else if viewMode == .albums && viewModel.selectedAlbum == nil && viewModel.selectedPlaylist == nil {
                // Albums list
                AlbumsListView(viewModel: viewModel)
            } else if tracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "music.note" : "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(Music2001Theme.textTertiary.opacity(0.3))
                    Text(searchText.isEmpty ?
                         (viewModel.selectedPlaylist != nil ? "No tracks in playlist" : "No tracks in library") :
                         "No results found")
                        .font(.subheadline)
                        .foregroundColor(Music2001Theme.textTertiary)
                    if searchText.isEmpty {
                        Text("Download tracks or add files to get started")
                            .font(.caption)
                            .foregroundColor(Music2001Theme.textTertiary.opacity(0.7))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Column headers
                HStack(spacing: 0) {
                    // Artwork placeholder
                    Spacer().frame(width: 40)
                    Text("Title")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Artist")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Album")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Year")
                        .frame(width: 50, alignment: .center)
                    Text("Duration")
                        .frame(width: 60, alignment: .trailing)
                        .padding(.trailing, 12)
                    // Space for 3-dot menu
                    Spacer().frame(width: 28)
                }
                .font(.caption2)
                .foregroundColor(Music2001Theme.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Music2001Theme.cardBackground)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                index: index + 1,
                                isPlaying: viewModel.currentTrack?.id == track.id,
                                onPlay: {
                                    let playAction = {
                                        viewModel.setQueue(tracks, startIndex: index)
                                    }
                                    if let onPlayTrack = onPlayTrack {
                                        onPlayTrack(playAction)
                                    } else {
                                        playAction()
                                    }
                                },
                                onAddToPlaylist: { playlist in
                                    viewModel.addToPlaylist(track, playlist: playlist)
                                },
                                onGetInfo: {
                                    editingTrack = track
                                },
                                onSetAlbum: { album in
                                    var updated = track
                                    updated.album = album
                                    viewModel.updateTrack(updated)
                                },
                                onSetArtist: { artist in
                                    var updated = track
                                    updated.artist = artist
                                    viewModel.updateTrack(updated)
                                },
                                onDelete: {
                                    viewModel.confirmDelete(track)
                                },
                                playlists: viewModel.playlists,
                                allAlbums: viewModel.allAlbums,
                                allArtists: viewModel.allArtists
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $editingTrack) { track in
            TrackInfoDialog(
                track: Binding(
                    get: { track },
                    set: { editingTrack = $0 }
                ),
                onSave: { updatedTrack in
                    viewModel.updateTrack(updatedTrack)
                    editingTrack = nil
                },
                onCancel: {
                    editingTrack = nil
                }
            )
        }
        .sheet(isPresented: $showingAddSongs) {
            if let playlist = viewModel.selectedPlaylist {
                AddSongsToPlaylistView(
                    viewModel: viewModel,
                    playlist: playlist,
                    onDismiss: { showingAddSongs = false }
                )
            }
        }
        .overlay(
            // Drop zone overlay
            Group {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Music2001Theme.primary, lineWidth: 3)
                        .background(Music2001Theme.primary.opacity(0.1))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 40))
                                Text("Drop audio files to import")
                                    .font(.headline)
                            }
                            .foregroundColor(Music2001Theme.primary)
                        )
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleFileDrop(providers: providers)
            return true
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) {
        let audioExtensions = ["mp3", "m4a", "wav", "aiff", "flac", "aac"]

        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      audioExtensions.contains(url.pathExtension.lowercased()) else {
                    return
                }

                DispatchQueue.main.async {
                    viewModel.importAudioFile(from: url)
                }
            }
        }
    }
}

// MARK: - Add Songs to Playlist View

struct AddSongsToPlaylistView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let playlist: Playlist
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedTrackIDs: Set<UUID> = []
    @ObservedObject private var themeManager = ThemeManager.shared

    var filteredTracks: [TrackMetadata] {
        let allTracks = viewModel.library.filter { !playlist.trackIDs.contains($0.id) }
        if searchText.isEmpty {
            return allTracks
        }
        return allTracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Songs to \(playlist.name)")
                    .font(.headline)
                    .foregroundColor(Music2001Theme.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(Music2001Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Music2001Theme.cardBackground)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textTertiary)
                TextField("Search songs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundColor(Music2001Theme.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(Music2001Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Music2001Theme.elevatedBackground)
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Track list
            if filteredTracks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "music.note" : "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(Music2001Theme.textTertiary.opacity(0.3))
                    Text(searchText.isEmpty ? "All songs already in playlist" : "No results found")
                        .font(.subheadline)
                        .foregroundColor(Music2001Theme.textTertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTracks) { track in
                            AddSongRow(
                                track: track,
                                isSelected: selectedTrackIDs.contains(track.id),
                                onToggle: {
                                    if selectedTrackIDs.contains(track.id) {
                                        selectedTrackIDs.remove(track.id)
                                    } else {
                                        selectedTrackIDs.insert(track.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Footer with add button
            HStack {
                Text("\(selectedTrackIDs.count) selected")
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textSecondary)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(Music2001Theme.textSecondary)
                .padding(.trailing, 8)

                Button {
                    for trackID in selectedTrackIDs {
                        viewModel.addTrackToPlaylist(trackID: trackID, playlist: playlist)
                    }
                    onDismiss()
                } label: {
                    Text("Add \(selectedTrackIDs.count) Songs")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedTrackIDs.isEmpty ? Music2001Theme.textTertiary : Music2001Theme.primary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(selectedTrackIDs.isEmpty)
            }
            .padding()
            .background(Music2001Theme.cardBackground)
        }
        .frame(width: 500, height: 500)
        .background(Music2001Theme.background)
    }
}

struct AddSongRow: View {
    let track: TrackMetadata
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovered = false
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Music2001Theme.primary : Music2001Theme.textTertiary)

                // Artwork
                if let artworkURL = track.artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Music2001Theme.elevatedBackground)
                    }
                    .frame(width: 36, height: 36)
                    .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Music2001Theme.elevatedBackground)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.caption)
                                .foregroundColor(Music2001Theme.textSecondary)
                        )
                }

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline)
                        .foregroundColor(Music2001Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(track.artist) • \(track.album)")
                        .font(.caption)
                        .foregroundColor(Music2001Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(track.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Music2001Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Music2001Theme.elevatedBackground.opacity(0.5) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Mini Toolbar (Right Side)

struct MiniToolbar: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @Binding var showSearch: Bool
    @Binding var searchText: String
    @Binding var showThemeEditor: Bool
    @Binding var showDownloadSidebar: Bool
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 0) {
                // Expanded panels
                if showSearch {
                    // Search panel
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search")
                                .font(.caption.weight(.medium))
                                .foregroundColor(Music2001Theme.textPrimary)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showSearch = false
                                    searchText = ""
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundColor(Music2001Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundColor(Music2001Theme.textTertiary)
                            TextField("Search tracks...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .foregroundColor(Music2001Theme.textPrimary)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(Music2001Theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(Music2001Theme.elevatedBackground)
                        .cornerRadius(6)

                        Spacer()
                    }
                    .padding(12)
                    .frame(width: 180)
                    .background(Music2001Theme.cardBackground)
                    .transition(.move(edge: .trailing))
                } else if showThemeEditor {
                    // Theme editor panel
                    ThemeEditorView(isShowing: $showThemeEditor)
                        .transition(.move(edge: .trailing))
                } else if showDownloadSidebar {
                    // Download panel
                    DownloadSidebarContent(viewModel: viewModel, isShowing: $showDownloadSidebar)
                        .frame(width: 200)
                        .transition(.move(edge: .trailing))
                }

                // Icon bar (always on far right)
                VStack(spacing: 4) {
                    // Search button
                    ToolbarIconButton(
                        icon: "magnifyingglass",
                        isActive: showSearch,
                        activeColor: Music2001Theme.accent
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showSearch.toggle()
                            if !showSearch { searchText = "" }
                            // Close others
                            showThemeEditor = false
                            showDownloadSidebar = false
                        }
                    }

                    // Theme button
                    ToolbarIconButton(
                        icon: "paintpalette",
                        isActive: showThemeEditor,
                        activeColor: Music2001Theme.primary
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showThemeEditor.toggle()
                            // Close others
                            showSearch = false
                            searchText = ""
                            showDownloadSidebar = false
                        }
                    }

                    // Download button
                    ToolbarIconButton(
                        icon: "arrow.down.circle",
                        isActive: showDownloadSidebar,
                        activeColor: Music2001Theme.primary
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDownloadSidebar.toggle()
                            // Close others
                            showSearch = false
                            searchText = ""
                            showThemeEditor = false
                        }
                    }

                    // Settings button
                    ToolbarIconButton(
                        icon: "gearshape",
                        isActive: false,
                        activeColor: Music2001Theme.textSecondary
                    ) {
                        showingSettings = true
                    }

                    Spacer()
                }
                .padding(.top, 8)
                .frame(width: 40)
                .background(Music2001Theme.cardBackground)
        }
    }
}

struct ToolbarIconButton: View {
    let icon: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isActive ? activeColor : Music2001Theme.accent)
                .frame(width: 28, height: 28)
                .background(isActive ? activeColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct TrackRow: View {
    let track: TrackMetadata
    let index: Int
    let isPlaying: Bool
    let onPlay: () -> Void
    let onAddToPlaylist: (Playlist) -> Void
    let onGetInfo: () -> Void
    let onSetAlbum: (String) -> Void
    let onSetArtist: (String) -> Void
    let onDelete: () -> Void
    let playlists: [Playlist]
    let allAlbums: [String]
    let allArtists: [String]

    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var isHovered = false
    @State private var showMenu = false

    var body: some View {
        HStack(spacing: 0) {
            // Clickable area for playing
            HStack(spacing: 0) {
                // Artwork with play overlay
                ZStack {
                    if let artworkURL = track.artworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Music2001Theme.cardBackground)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 10))
                                        .foregroundColor(Music2001Theme.textSecondary)
                                )
                        }
                        .frame(width: 32, height: 32)
                        .cornerRadius(4)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Music2001Theme.cardBackground)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 10))
                                    .foregroundColor(Music2001Theme.textSecondary)
                            )
                    }

                    // Play/Playing overlay
                    if isPlaying || isHovered {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Music2001Theme.primary)
                            )
                    }
                }
                .frame(width: 40, alignment: .leading)

                // Title
                Text(track.title)
                    .font(.subheadline)
                    .foregroundColor(isPlaying ? Music2001Theme.primary : Music2001Theme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Artist
                Text(track.artist)
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Album
                Text(track.album)
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Year
                Text(track.releaseYear.map { String($0) } ?? "-")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Music2001Theme.textSecondary)
                    .frame(width: 50, alignment: .center)

                // Duration
                Text(track.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Music2001Theme.textSecondary)
                    .frame(width: 60, alignment: .trailing)
                    .padding(.trailing, 12)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onPlay()
            }

            // 3-dot menu button
            Button {
                showMenu.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundColor(Music2001Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showMenu, arrowEdge: .trailing) {
                TrackContextMenu(
                    track: track,
                    playlists: playlists,
                    allAlbums: allAlbums,
                    allArtists: allArtists,
                    onGetInfo: {
                        onGetInfo()
                        showMenu = false
                    },
                    onSetAlbum: { album in
                        onSetAlbum(album)
                        showMenu = false
                    },
                    onSetArtist: { artist in
                        onSetArtist(artist)
                        showMenu = false
                    },
                    onAddToPlaylist: { playlist in
                        onAddToPlaylist(playlist)
                        showMenu = false
                    },
                    onDelete: {
                        onDelete()
                        showMenu = false
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Music2001Theme.cardBackground.opacity(0.5) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            NSItemProvider(object: track.id.uuidString as NSString)
        }
    }
}

// MARK: - Track Context Menu

struct TrackContextMenu: View {
    let track: TrackMetadata
    let playlists: [Playlist]
    let allAlbums: [String]
    let allArtists: [String]
    let onGetInfo: () -> Void
    let onSetAlbum: (String) -> Void
    let onSetArtist: (String) -> Void
    let onAddToPlaylist: (Playlist) -> Void
    let onDelete: () -> Void

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Get Info
            ThemedMenuButton(icon: "info.circle", title: "Get Info...") {
                onGetInfo()
            }

            // Add to Album - nested popover
            NestedSubmenuButton(
                icon: "square.stack",
                title: "Add to Album"
            ) {
                AlbumSubmenuContent(
                    track: track,
                    allAlbums: allAlbums,
                    onSetAlbum: onSetAlbum
                )
            }

            // Set Artist - nested popover
            NestedSubmenuButton(
                icon: "person",
                title: "Set Artist"
            ) {
                ArtistSubmenuContent(
                    track: track,
                    allArtists: allArtists,
                    onSetArtist: onSetArtist
                )
            }

            ThemedMenuDivider()

            // Playlist submenu
            if !playlists.isEmpty {
                NestedSubmenuButton(
                    icon: "text.badge.plus",
                    title: "Add to Playlist"
                ) {
                    PlaylistSubmenuContent(
                        playlists: playlists,
                        onAddToPlaylist: onAddToPlaylist
                    )
                }

                ThemedMenuDivider()
            }

            // Delete option
            ThemedMenuButton(icon: "trash", title: "Delete", isDestructive: true) {
                onDelete()
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 160)
        .background(Music2001Theme.cardBackground)
    }
}

// MARK: - Nested Submenu Button

struct NestedSubmenuButton<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false
    @State private var showSubmenu = false
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Button {
            showSubmenu.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textPrimary)
                    .frame(width: 16)
                Text(title)
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(Music2001Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Music2001Theme.elevatedBackground : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $showSubmenu, arrowEdge: .trailing) {
            content()
        }
    }
}

// MARK: - Album Submenu Content

struct AlbumSubmenuContent: View {
    let track: TrackMetadata
    let allAlbums: [String]
    let onSetAlbum: (String) -> Void

    @State private var showNewInput = false
    @State private var newName = ""
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showNewInput {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Album")
                        .font(.caption)
                        .foregroundColor(Music2001Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    HStack(spacing: 6) {
                        TextField("Album name", text: $newName)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .padding(6)
                            .background(Music2001Theme.elevatedBackground)
                            .cornerRadius(4)
                            .onSubmit {
                                if !newName.isEmpty {
                                    onSetAlbum(newName)
                                }
                            }
                        Button {
                            if !newName.isEmpty {
                                onSetAlbum(newName)
                            }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Music2001Theme.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                    ThemedMenuDivider()

                    ThemedMenuButton(icon: "chevron.left", title: "Back") {
                        showNewInput = false
                        newName = ""
                    }
                }
            } else {
                ForEach(allAlbums.filter { $0 != track.album }.prefix(8), id: \.self) { album in
                    ThemedMenuButton(icon: "square.stack", title: album) {
                        onSetAlbum(album)
                    }
                }

                if allAlbums.filter({ $0 != track.album }).count > 0 {
                    ThemedMenuDivider()
                }

                ThemedMenuButton(icon: "plus.circle", title: "New Album...") {
                    showNewInput = true
                    newName = ""
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 140)
        .background(Music2001Theme.cardBackground)
    }
}

// MARK: - Artist Submenu Content

struct ArtistSubmenuContent: View {
    let track: TrackMetadata
    let allArtists: [String]
    let onSetArtist: (String) -> Void

    @State private var showNewInput = false
    @State private var newName = ""
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showNewInput {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Artist")
                        .font(.caption)
                        .foregroundColor(Music2001Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    HStack(spacing: 6) {
                        TextField("Artist name", text: $newName)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .padding(6)
                            .background(Music2001Theme.elevatedBackground)
                            .cornerRadius(4)
                            .onSubmit {
                                if !newName.isEmpty {
                                    onSetArtist(newName)
                                }
                            }
                        Button {
                            if !newName.isEmpty {
                                onSetArtist(newName)
                            }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Music2001Theme.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                    ThemedMenuDivider()

                    ThemedMenuButton(icon: "chevron.left", title: "Back") {
                        showNewInput = false
                        newName = ""
                    }
                }
            } else {
                ForEach(allArtists.filter { $0 != track.artist }.prefix(8), id: \.self) { artist in
                    ThemedMenuButton(icon: "person", title: artist) {
                        onSetArtist(artist)
                    }
                }

                if allArtists.filter({ $0 != track.artist }).count > 0 {
                    ThemedMenuDivider()
                }

                ThemedMenuButton(icon: "plus.circle", title: "Other...") {
                    showNewInput = true
                    newName = ""
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 140)
        .background(Music2001Theme.cardBackground)
    }
}

// MARK: - Playlist Submenu Content

struct PlaylistSubmenuContent: View {
    let playlists: [Playlist]
    let onAddToPlaylist: (Playlist) -> Void

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(playlists) { playlist in
                ThemedMenuButton(icon: "music.note.list", title: playlist.name) {
                    onAddToPlaylist(playlist)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 140)
        .background(Music2001Theme.cardBackground)
    }
}

// MARK: - Themed Menu Components

struct ThemedMenuButton: View {
    let icon: String
    let title: String
    var color: Color? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @ObservedObject private var themeManager = ThemeManager.shared

    private var foregroundColor: Color {
        if isDestructive { return .red }
        if let color = color { return color }
        return Music2001Theme.textPrimary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(foregroundColor)
                    .frame(width: 16)
                Text(title)
                    .font(.caption)
                    .foregroundColor(foregroundColor)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Music2001Theme.elevatedBackground : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ThemedMenuDivider: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Rectangle()
            .fill(Music2001Theme.elevatedBackground)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

// MARK: - Track Info Dialog

struct TrackInfoDialog: View {
    @Binding var track: TrackMetadata
    let onSave: (TrackMetadata) -> Void
    let onCancel: () -> Void

    @State private var editedTitle: String = ""
    @State private var editedArtist: String = ""
    @State private var editedAlbum: String = ""
    @State private var editedGenre: String = ""
    @State private var editedYear: String = ""
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var lookupResults: [iTunesResult] = []
    @State private var showResultsPicker = false
    @FocusState private var focusedField: TrackInfoFocusField?

    @ObservedObject private var themeManager = ThemeManager.shared

    enum TrackInfoFocusField {
        case title, artist, album, genre, year
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Track Info")
                    .font(.headline)
                    .foregroundColor(Music2001Theme.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundColor(Music2001Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 16) {
                // Artwork
                VStack {
                    if let artworkURL = track.artworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Music2001Theme.elevatedBackground)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.title)
                                        .foregroundColor(Music2001Theme.textTertiary)
                                )
                        }
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Music2001Theme.elevatedBackground)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.title)
                                    .foregroundColor(Music2001Theme.textTertiary)
                            )
                    }
                }

                // Fields
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption2)
                            .foregroundColor(Music2001Theme.textTertiary)
                        TextField("", text: $editedTitle)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .padding(8)
                            .background(Music2001Theme.elevatedBackground)
                            .cornerRadius(6)
                            .focused($focusedField, equals: .title)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Artist")
                            .font(.caption2)
                            .foregroundColor(Music2001Theme.textTertiary)
                        TextField("", text: $editedArtist)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .padding(8)
                            .background(Music2001Theme.elevatedBackground)
                            .cornerRadius(6)
                            .focused($focusedField, equals: .artist)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Album")
                            .font(.caption2)
                            .foregroundColor(Music2001Theme.textTertiary)
                        TextField("", text: $editedAlbum)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .padding(8)
                            .background(Music2001Theme.elevatedBackground)
                            .cornerRadius(6)
                            .focused($focusedField, equals: .album)
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Genre")
                                .font(.caption2)
                                .foregroundColor(Music2001Theme.textTertiary)
                            TextField("", text: $editedGenre)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .foregroundColor(Music2001Theme.textPrimary)
                                .padding(8)
                                .background(Music2001Theme.elevatedBackground)
                                .cornerRadius(6)
                                .focused($focusedField, equals: .genre)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Year")
                                .font(.caption2)
                                .foregroundColor(Music2001Theme.textTertiary)
                            TextField("", text: $editedYear)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .foregroundColor(Music2001Theme.textPrimary)
                                .padding(8)
                                .background(Music2001Theme.elevatedBackground)
                                .cornerRadius(6)
                                .focused($focusedField, equals: .year)
                        }
                        .frame(width: 80)
                    }
                }
            }

            // Lookup button and results
            VStack(spacing: 8) {
                HStack {
                    Button {
                        lookupFromiTunes()
                    } label: {
                        HStack(spacing: 6) {
                            if isLookingUp {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text("Lookup from iTunes")
                        }
                        .font(.caption)
                        .foregroundColor(Music2001Theme.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLookingUp)

                    Spacer()

                    if let error = lookupError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    if showResultsPicker && !lookupResults.isEmpty {
                        Button {
                            showResultsPicker = false
                            lookupResults = []
                        } label: {
                            Text("Clear")
                                .font(.caption2)
                                .foregroundColor(Music2001Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Results picker
                if showResultsPicker && !lookupResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(lookupResults) { result in
                                iTunesResultRow(result: result) {
                                    editedTitle = result.trackName
                                    editedArtist = result.artistName
                                    editedAlbum = result.collectionName
                                    editedGenre = result.genre ?? ""
                                    editedYear = result.releaseYear
                                    showResultsPicker = false
                                    lookupResults = []
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .background(Music2001Theme.elevatedBackground)
                    .cornerRadius(8)
                }
            }

            Divider()
                .background(Music2001Theme.elevatedBackground)

            // Actions
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundColor(Music2001Theme.textSecondary)
                .padding(.trailing, 8)

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .tint(Music2001Theme.primary)
            }
        }
        .padding(28)
        .frame(width: 480, height: showResultsPicker ? 520 : 400)
        .animation(.easeInOut(duration: 0.2), value: showResultsPicker)
        .background(Music2001Theme.cardBackground)
        .onAppear {
            editedTitle = track.title
            editedArtist = track.artist
            editedAlbum = track.album
            editedGenre = track.genre ?? ""
            editedYear = track.releaseYear.map { String($0) } ?? ""
        }
    }

    private func saveChanges() {
        var updatedTrack = track
        updatedTrack.title = editedTitle
        updatedTrack.artist = editedArtist
        updatedTrack.album = editedAlbum
        updatedTrack.genre = editedGenre.isEmpty ? nil : editedGenre
        updatedTrack.releaseYear = Int(editedYear)
        onSave(updatedTrack)
    }

    private func lookupFromiTunes() {
        isLookingUp = true
        lookupError = nil
        showResultsPicker = false
        lookupResults = []

        // Build search query from title and artist
        var searchTerms = editedTitle
        if editedArtist != "Unknown Artist" && !editedArtist.isEmpty {
            searchTerms += " " + editedArtist
        }

        // Clean up search terms
        searchTerms = searchTerms
            .replacingOccurrences(of: "(Official Video)", with: "")
            .replacingOccurrences(of: "(Official Audio)", with: "")
            .replacingOccurrences(of: "[Official Video]", with: "")
            .replacingOccurrences(of: "[Official Audio]", with: "")
            .replacingOccurrences(of: "(Lyrics)", with: "")
            .replacingOccurrences(of: "[Lyrics]", with: "")
            .replacingOccurrences(of: "(HD)", with: "")
            .replacingOccurrences(of: "[HD]", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let encoded = searchTerms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&limit=8") else {
            isLookingUp = false
            lookupError = "Invalid search query"
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   !results.isEmpty {

                    let parsedResults = results.compactMap { item -> iTunesResult? in
                        guard let trackName = item["trackName"] as? String,
                              let artistName = item["artistName"] as? String else {
                            return nil
                        }
                        let collectionName = item["collectionName"] as? String ?? "Unknown Album"
                        let releaseDate = item["releaseDate"] as? String ?? ""
                        let year = String(releaseDate.prefix(4))
                        let genre = item["primaryGenreName"] as? String
                        let artworkURL = (item["artworkUrl100"] as? String)?
                            .replacingOccurrences(of: "100x100", with: "300x300")

                        return iTunesResult(
                            trackName: trackName,
                            artistName: artistName,
                            collectionName: collectionName,
                            releaseYear: year,
                            genre: genre,
                            artworkURLString: artworkURL
                        )
                    }

                    await MainActor.run {
                        isLookingUp = false
                        if parsedResults.count == 1 {
                            // Auto-fill if only one result
                            let result = parsedResults[0]
                            editedTitle = result.trackName
                            editedArtist = result.artistName
                            editedAlbum = result.collectionName
                            editedGenre = result.genre ?? ""
                            editedYear = result.releaseYear
                        } else if parsedResults.count > 1 {
                            // Show picker for multiple results
                            lookupResults = parsedResults
                            showResultsPicker = true
                        } else {
                            lookupError = "No results found"
                        }
                    }
                } else {
                    await MainActor.run {
                        isLookingUp = false
                        lookupError = "No results found"
                    }
                }
            } catch {
                await MainActor.run {
                    isLookingUp = false
                    lookupError = "Lookup failed"
                }
            }
        }
    }
}

// MARK: - iTunes Result Model

struct iTunesResult: Identifiable {
    let id = UUID()
    let trackName: String
    let artistName: String
    let collectionName: String
    let releaseYear: String
    let genre: String?
    let artworkURLString: String?

    var artworkURL: URL? {
        guard let urlString = artworkURLString else { return nil }
        return URL(string: urlString)
    }
}

struct iTunesResultRow: View {
    let result: iTunesResult
    let onSelect: () -> Void

    @State private var isHovered = false
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Artwork
                if let artworkURL = result.artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Music2001Theme.primary.opacity(0.2))
                    }
                    .frame(width: 36, height: 36)
                    .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Music2001Theme.primary.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.caption2)
                                .foregroundColor(Music2001Theme.primary)
                        )
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.trackName)
                        .font(.caption)
                        .foregroundColor(Music2001Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(result.artistName) • \(result.collectionName) • \(result.releaseYear)")
                        .font(.caption2)
                        .foregroundColor(Music2001Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if isHovered {
                    Image(systemName: "arrow.up.left")
                        .font(.caption2)
                        .foregroundColor(Music2001Theme.primary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Music2001Theme.primary.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct TrackInfoField: View {
    let label: String
    @Binding var text: String
    var isNumeric: Bool = false

    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(Music2001Theme.textTertiary)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundColor(Music2001Theme.textPrimary)
                .padding(8)
                .background(Music2001Theme.elevatedBackground)
                .cornerRadius(6)
        }
    }
}

// MARK: - Artists List View

struct ArtistsListView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.allArtists, id: \.self) { artist in
                    ArtistRow(
                        artist: artist,
                        trackCount: viewModel.tracksForArtist(artist).count,
                        onSelect: {
                            viewModel.selectedArtist = artist
                        }
                    )
                }
            }
        }
    }
}

struct ArtistRow: View {
    let artist: String
    let trackCount: Int
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Music2001Theme.elevatedBackground)
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundColor(Music2001Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(Music2001Theme.textPrimary)
                    Text("\(trackCount) \(trackCount == 1 ? "song" : "songs")")
                        .font(.caption)
                        .foregroundColor(Music2001Theme.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isHovered ? Music2001Theme.elevatedBackground.opacity(0.5) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Albums List View

struct AlbumsListView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.allAlbums, id: \.self) { album in
                    AlbumRow(
                        album: album,
                        trackCount: viewModel.tracksForAlbum(album).count,
                        artwork: viewModel.tracksForAlbum(album).first?.artworkURL,
                        onSelect: {
                            viewModel.selectedAlbum = album
                        }
                    )
                }
            }
        }
    }
}

struct AlbumRow: View {
    let album: String
    let trackCount: Int
    let artwork: URL?
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if let artworkURL = artwork {
                    AsyncImage(url: artworkURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Music2001Theme.elevatedBackground)
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Music2001Theme.elevatedBackground)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "square.stack")
                                .font(.title3)
                                .foregroundColor(Music2001Theme.textSecondary)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(album)
                        .font(.subheadline)
                        .foregroundColor(Music2001Theme.textPrimary)
                    Text("\(trackCount) \(trackCount == 1 ? "song" : "songs")")
                        .font(.caption)
                        .foregroundColor(Music2001Theme.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Music2001Theme.elevatedBackground.opacity(0.5) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Download Sidebar Content

struct DownloadSidebarContent: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Download")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Music2001Theme.textPrimary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isShowing = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(Music2001Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if viewModel.canDownload {
                // URL input (only when downloads are enabled)
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .leading) {
                        if viewModel.urlInput.isEmpty {
                            Text("e.g. youtube.com/watch?v=...")
                                .font(.caption2)
                                .foregroundColor(Music2001Theme.textTertiary)
                                .padding(.leading, 8)
                        }
                        TextField("", text: $viewModel.urlInput)
                            .textFieldStyle(.plain)
                            .font(.caption2)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .padding(8)
                            .onSubmit {
                                viewModel.downloadTrack()
                            }
                    }
                    .background(Music2001Theme.elevatedBackground)
                    .cornerRadius(6)

                    Button {
                        viewModel.downloadTrack()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                        }
                        .font(.caption2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(viewModel.urlInput.isEmpty ? Music2001Theme.textTertiary : Music2001Theme.primary)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.urlInput.isEmpty || viewModel.isDownloading)

                    Text("Tip: Use - Topic channels")
                        .font(.system(size: 9))
                        .foregroundColor(Music2001Theme.textTertiary)
                }

                // Progress
                if viewModel.isDownloading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(viewModel.downloadProgress)
                            .font(.caption2)
                            .foregroundColor(Music2001Theme.textSecondary)
                    }
                }
            } else {
                // Downloads disabled (App Store sandbox mode)
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundColor(Music2001Theme.textTertiary)

                    Text("Downloads Unavailable")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Music2001Theme.textPrimary)

                    Text("This feature is only available in the direct download version.")
                        .font(.caption2)
                        .foregroundColor(Music2001Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 8)
            }

            Spacer()
        }
        .padding(12)
        .background(Music2001Theme.cardBackground)
    }
}

// MARK: - Now Playing Bar

struct NowPlayingBar: View {
    @ObservedObject var viewModel: PlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Music2001Theme.elevatedBackground)
                    Rectangle()
                        .fill(Music2001Theme.primary)
                        .frame(width: viewModel.duration > 0 ? geo.size.width * (viewModel.currentTime / viewModel.duration) : 0)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = value.location.x / geo.size.width
                            let time = Double(progress) * viewModel.duration
                            viewModel.seek(to: max(0, min(time, viewModel.duration)))
                        }
                )
            }
            .frame(height: 4)

            HStack(spacing: 16) {
                // Track info
                HStack(spacing: 10) {
                    if let track = viewModel.currentTrack, let artworkURL = track.artworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Music2001Theme.elevatedBackground)
                        }
                        .frame(width: 44, height: 44)
                        .cornerRadius(4)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Music2001Theme.elevatedBackground)
                            .frame(width: 44, height: 44)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentTrack?.title ?? "No track selected")
                            .font(.subheadline)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .lineLimit(1)
                        Text(viewModel.currentTrack?.artist ?? "")
                            .font(.caption)
                            .foregroundColor(Music2001Theme.textSecondary)
                            .lineLimit(1)
                    }

                    // Add to playlist button (only when track is playing)
                    if let track = viewModel.currentTrack, !viewModel.playlists.isEmpty {
                        Menu {
                            ForEach(viewModel.playlists) { playlist in
                                Button(playlist.name) {
                                    viewModel.addToPlaylist(track, playlist: playlist)
                                }
                            }
                        } label: {
                            Image(systemName: "text.badge.plus")
                                .font(.caption)
                                .foregroundColor(Music2001Theme.textSecondary)
                                .padding(6)
                                .background(Music2001Theme.elevatedBackground)
                                .cornerRadius(4)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Add to playlist")
                    }
                }
                .frame(width: 260, alignment: .leading)

                Spacer()

                // Playback controls
                HStack(spacing: 12) {
                    // Shuffle
                    Button {
                        viewModel.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.caption)
                            .foregroundColor(viewModel.isShuffled ? Music2001Theme.primary : Music2001Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Previous
                    Button {
                        viewModel.playPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Play/Pause
                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(Music2001Theme.primary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Next
                    Button {
                        viewModel.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundColor(Music2001Theme.textPrimary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Repeat
                    Button {
                        viewModel.toggleRepeat()
                    } label: {
                        Image(systemName: viewModel.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(.caption)
                            .foregroundColor(viewModel.repeatMode != .off ? Music2001Theme.primary : Music2001Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Time + Volume
                HStack(spacing: 16) {
                    Text("\(viewModel.formatTime(viewModel.currentTime)) / \(viewModel.formatTime(viewModel.duration))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(Music2001Theme.textTertiary)

                    HStack(spacing: 6) {
                        Image(systemName: viewModel.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(Music2001Theme.textSecondary)

                        Slider(value: $viewModel.volume, in: 0...1)
                            .frame(width: 80)
                            .tint(Music2001Theme.primary)
                            .onChange(of: viewModel.volume) { newValue in
                                viewModel.setVolume(newValue)
                            }
                    }
                }
                .frame(width: 260, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Music2001Theme.cardBackground)
    }
}

#Preview {
    PlayerView(showingSettings: .constant(false))
}
