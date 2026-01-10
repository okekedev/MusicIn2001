//
//  iPodTypes.swift
//  MixoriOS
//

import SwiftUI

// MARK: - Track

struct iPodTrack: Identifiable, Equatable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let genre: String
    let duration: TimeInterval
    let relativePath: String
    let artworkRelativePath: String?

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Playlist

struct iPodPlaylist: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]

    // Custom decoder to ignore extra fields from Mac (like createdAt)
    private enum CodingKeys: String, CodingKey {
        case id, name, trackIDs
    }
}

// MARK: - Navigation

enum Screen: Equatable {
    case mainMenu
    case music
    case playlists
    case onTheGo
    case playlist(name: String)
    case artists
    case artistAlbums(artist: String)
    case albums
    case albumTracks(album: String)
    case songs
    case genres
    case genreTracks(genre: String)
    case nowPlaying
    case settings
    case colorPicker
    case repeatSetting
    case support
    case howToUse
}

// MARK: - Playback Settings

enum ShuffleMode: String, CaseIterable {
    case off = "Off"
    case songs = "Songs"
    case albums = "Albums"
}

enum RepeatMode: String, CaseIterable {
    case off = "Off"
    case one = "One"
    case all = "All"
}

// MARK: - Menu Item

struct MenuItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String?
    let destination: Screen?
    let action: (() -> Void)?

    init(title: String, icon: String? = nil, destination: Screen? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.destination = destination
        self.action = action
    }
}

// MARK: - iPod Colors

struct iPodColor: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let shell: Color         // Body/face color
    let wheel: Color         // Click wheel color
    let centerButton: Color  // Center button (matches shell)
    let wheelText: Color     // Text on the wheel (Menu, Play, etc.)
    let background: Color    // Background behind the iPod

    static let presets: [iPodColor] = [
        // Silver - white wheel, dark text (like real silver iPod Classic)
        iPodColor(
            name: "Silver",
            shell: Color(white: 0.88),
            wheel: Color(white: 0.96),
            centerButton: Color(white: 0.88),
            wheelText: Color(white: 0.3),
            background: Color(white: 0.35)
        ),
        // Black - dark grey wheel, light text (like real black iPod Classic)
        iPodColor(
            name: "Black",
            shell: Color(white: 0.12),
            wheel: Color(white: 0.22),
            centerButton: Color(white: 0.12),
            wheelText: Color(white: 0.6),
            background: Color(white: 0.25)
        ),
        // Red - darker red wheel, white text (like Product Red iPod)
        iPodColor(
            name: "Red",
            shell: Color(red: 0.85, green: 0.12, blue: 0.12),
            wheel: Color(red: 0.65, green: 0.08, blue: 0.08),
            centerButton: Color(red: 0.85, green: 0.12, blue: 0.12),
            wheelText: Color.white,
            background: Color(red: 0.35, green: 0.05, blue: 0.05)
        ),
        // Blue - darker blue wheel, white text (like blue iPod nano)
        iPodColor(
            name: "Blue",
            shell: Color(red: 0.12, green: 0.45, blue: 0.85),
            wheel: Color(red: 0.08, green: 0.35, blue: 0.65),
            centerButton: Color(red: 0.12, green: 0.45, blue: 0.85),
            wheelText: Color.white,
            background: Color(red: 0.05, green: 0.15, blue: 0.35)
        ),
        // Green - darker green wheel, white text (like green iPod nano)
        iPodColor(
            name: "Green",
            shell: Color(red: 0.12, green: 0.70, blue: 0.25),
            wheel: Color(red: 0.08, green: 0.52, blue: 0.18),
            centerButton: Color(red: 0.12, green: 0.70, blue: 0.25),
            wheelText: Color.white,
            background: Color(red: 0.05, green: 0.25, blue: 0.08)
        ),
        // Pink - darker pink wheel, white text (like pink iPod nano)
        iPodColor(
            name: "Pink",
            shell: Color(red: 0.95, green: 0.45, blue: 0.65),
            wheel: Color(red: 0.75, green: 0.35, blue: 0.50),
            centerButton: Color(red: 0.95, green: 0.45, blue: 0.65),
            wheelText: Color.white,
            background: Color(red: 0.35, green: 0.15, blue: 0.22)
        ),
        // Yellow - darker yellow wheel, dark text (like yellow iPod nano)
        iPodColor(
            name: "Yellow",
            shell: Color(red: 0.98, green: 0.85, blue: 0.25),
            wheel: Color(red: 0.80, green: 0.68, blue: 0.18),
            centerButton: Color(red: 0.98, green: 0.85, blue: 0.25),
            wheelText: Color(white: 0.25),
            background: Color(red: 0.38, green: 0.32, blue: 0.08)
        ),
    ]
}
