//
//  iPodTypes.swift
//  Music2001iOS
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
    case colorSettings
    case shellColorPicker
    case backgroundPicker
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
        )
    ]
}
// MARK: - Background Gradient Themes

struct BackgroundTheme: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let colors: [Color]
    
    static let themes: [BackgroundTheme] = [
        BackgroundTheme(
            name: "Default Purple",
            colors: [
                Color(red: 0.4, green: 0.2, blue: 0.6),
                Color(red: 0.2, green: 0.1, blue: 0.4),
                Color(red: 0.1, green: 0.05, blue: 0.2)
            ]
        ),
        BackgroundTheme(
            name: "Red",
            colors: [
                Color(red: 0.6, green: 0.15, blue: 0.15),
                Color(red: 0.4, green: 0.08, blue: 0.08),
                Color(red: 0.2, green: 0.03, blue: 0.03)
            ]
        ),
        BackgroundTheme(
            name: "Blue",
            colors: [
                Color(red: 0.15, green: 0.3, blue: 0.6),
                Color(red: 0.08, green: 0.15, blue: 0.4),
                Color(red: 0.03, green: 0.08, blue: 0.2)
            ]
        ),
        BackgroundTheme(
            name: "Green",
            colors: [
                Color(red: 0.15, green: 0.5, blue: 0.25),
                Color(red: 0.08, green: 0.3, blue: 0.15),
                Color(red: 0.03, green: 0.15, blue: 0.08)
            ]
        ),
        BackgroundTheme(
            name: "Yellow",
            colors: [
                Color(red: 0.6, green: 0.5, blue: 0.1),
                Color(red: 0.4, green: 0.3, blue: 0.05),
                Color(red: 0.2, green: 0.15, blue: 0.02)
            ]
        ),
        BackgroundTheme(
            name: "Orange",
            colors: [
                Color(red: 0.7, green: 0.35, blue: 0.1),
                Color(red: 0.5, green: 0.2, blue: 0.05),
                Color(red: 0.25, green: 0.1, blue: 0.02)
            ]
        ),
        BackgroundTheme(
            name: "Pink",
            colors: [
                Color(red: 0.6, green: 0.2, blue: 0.4),
                Color(red: 0.4, green: 0.1, blue: 0.25),
                Color(red: 0.2, green: 0.05, blue: 0.12)
            ]
        ),
        BackgroundTheme(
            name: "Teal",
            colors: [
                Color(red: 0.1, green: 0.5, blue: 0.5),
                Color(red: 0.05, green: 0.3, blue: 0.3),
                Color(red: 0.02, green: 0.15, blue: 0.15)
            ]
        )
    ]
}

