//
//  iPodView.swift
//  Music2001iOS
//

import SwiftUI

struct iPodView: View {
    @Environment(iPodState.self) var state

    var body: some View {
        // iPod Classic 7th gen proportions (~1.67 aspect ratio)
        GeometryReader { geometry in
            let iPodWidth = min(geometry.size.width * 0.92, 380)
            let iPodHeight = iPodWidth * 1.67
            let screenHeight = iPodHeight * 0.40
            let topPadding: CGFloat = 20
            let screenAreaHeight = screenHeight + topPadding
            let wheelAreaHeight = iPodHeight - screenAreaHeight
            let wheelSize = iPodWidth * 0.72

            // iPod Body - clean, flat Apple design
            ZStack(alignment: .top) {
                // Background
                RoundedRectangle(cornerRadius: 24)
                    .fill(state.selectedColor.shell)

                VStack(spacing: 0) {
                    // Screen
                    ScreenView()
                        .frame(height: screenHeight)
                        .padding(.horizontal, 16)
                        .padding(.top, topPadding)

                    // Click Wheel - centered in remaining space
                    ClickWheelView(size: wheelSize)
                        .frame(height: wheelAreaHeight)
                }
            }
            .frame(width: iPodWidth, height: iPodHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .background(state.selectedColor.background)
        .ignoresSafeArea()
        .overlay {
            if state.showingOnboarding {
                OnboardingOverlay()
            }
        }
    }
}

// MARK: - Onboarding

struct OnboardingOverlay: View {
    @Environment(iPodState.self) var state

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Welcome to Music in 2001")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Get Music in 2001 on a Mac")
                    Text("2. Add songs via MP3 or link")
                    Text("3. Open this app")
                    Text("4. Click Sync")
                }
                .font(.body)
                .foregroundColor(.white.opacity(0.9))

                Button("Got it") {
                    state.dismissOnboarding()
                }
                .font(.headline)
                .foregroundColor(.black)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(20)
                .padding(.top, 10)
            }
            .padding(30)
        }
    }
}

// MARK: - Screen

struct ScreenView: View {
    @Environment(iPodState.self) var state

    var body: some View {
        ZStack {
            // Screen border/bezel - thin dark line
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(white: 0.2))

            // LCD Background - classic iPod blue-green/cyan tint
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.78, green: 0.88, blue: 0.86))
                .padding(2)

            // Content
            VStack(spacing: 0) {
                StatusBarView()
                    .frame(height: 24)

                ScreenContentView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(4)
        }
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @Environment(iPodState.self) var state

    var body: some View {
        HStack {
            Text(screenTitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))

            Spacer()

            if state.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
            }

            // Volume indicator on Now Playing
            if state.currentScreen == .nowPlaying {
                HStack(spacing: 2) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 8))
                    Rectangle()
                        .frame(width: 30, height: 4)
                        .foregroundColor(Color(white: 0.5))
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .frame(width: 30 * state.volume, height: 4)
                                .foregroundColor(Color(white: 0.2))
                        }
                }
            }

            BatteryView()
        }
        .foregroundColor(Color(white: 0.15))
        .padding(.horizontal, 8)
        .background(Color(white: 0.55).opacity(0.4))
    }

    var screenTitle: String {
        switch state.currentScreen {
        case .mainMenu: return "Music in 2001"
        case .music: return "Music"
        case .playlists: return "Playlists"
        case .onTheGo: return "On-The-Go"
        case .playlist(let name): return name
        case .artists: return "Artists"
        case .artistAlbums(let artist): return artist
        case .albums: return "Albums"
        case .albumTracks(let album): return album
        case .songs: return "Songs"
        case .genres: return "Genres"
        case .genreTracks(let genre): return genre
        case .nowPlaying: return "Now Playing"
        case .settings: return "Settings"
        case .colorPicker: return "Color"
        case .repeatSetting: return "Repeat"
        case .support: return "Support"
        case .howToUse: return "How to Use"
        }
    }
}

struct BatteryView: View {
    @State private var batteryLevel: Float = 1.0

    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 1)
                .stroke(Color(white: 0.2), lineWidth: 1)
                .frame(width: 20, height: 9)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color(white: 0.2))
                        .frame(width: max(2, 16 * CGFloat(batteryLevel)), height: 5)
                        .padding(.leading, 2)
                }
            RoundedRectangle(cornerRadius: 0.5)
                .fill(Color(white: 0.2))
                .frame(width: 2, height: 5)
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteryLevel = UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : 1.0
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            batteryLevel = UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : 1.0
        }
    }
}

// MARK: - Screen Content

struct ScreenContentView: View {
    @Environment(iPodState.self) var state

    var body: some View {
        Group {
            switch state.currentScreen {
            case .nowPlaying:
                NowPlayingView()
            default:
                MenuListView()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

// MARK: - Menu List

struct MenuListView: View {
    @Environment(iPodState.self) var state

    var body: some View {
        let items = state.menuItems(for: state.currentScreen)

        ZStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            MenuRowView(
                                title: item.title,
                                icon: item.icon,
                                hasSubmenu: item.destination != nil,
                                isSelected: index == state.selectedIndex
                            )
                            .id(index)
                        }
                    }
                }
                .onChange(of: state.selectedIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            // Thank you overlay
            if state.showingThankYou {
                VStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 32))
                    Text("Thank You!")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(Color(white: 0.15))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.78, green: 0.88, blue: 0.86).opacity(0.95))
            }

            // Sync result overlay
            if state.showingSyncResult {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 32))
                    Text(state.lastSyncResult)
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(Color(white: 0.15))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.78, green: 0.88, blue: 0.86).opacity(0.95))
            }
        }
    }
}

struct MenuRowView: View {
    let title: String
    let icon: String?
    let hasSubmenu: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
            }

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)

            Spacer()

            if hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundColor(isSelected ? .white : Color(white: 0.15))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ?
            LinearGradient(colors: [Color.blue.opacity(0.9), Color.blue], startPoint: .top, endPoint: .bottom) :
            LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
        )
        .cornerRadius(4)
    }
}

// MARK: - Now Playing

struct NowPlayingView: View {
    @Environment(iPodState.self) var state

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 8) {
                // Album Art
                let artSize = min(geo.size.width * 0.6, geo.size.height * 0.5)
                if let artworkPath = state.currentTrack?.artworkRelativePath,
                   let artworkURL = state.artworkURL(for: artworkPath),
                   let imageData = try? Data(contentsOf: artworkURL),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: artSize, height: artSize)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.35).opacity(0.5))
                        .frame(width: artSize, height: artSize)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 40))
                                .foregroundColor(Color(white: 0.25))
                        )
                }

                // Track Info
                if let track = state.currentTrack {
                    VStack(spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Text(track.album)
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.35))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color(white: 0.15))
                }

                Spacer()

                // Progress
                VStack(spacing: 4) {
                    GeometryReader { progressGeo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(white: 0.45))
                                .frame(height: 5)
                            Capsule()
                                .fill(Color(white: 0.15))
                                .frame(width: progressGeo.size.width * progress, height: 5)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text(formatTime(state.currentTime))
                        Spacer()
                        Text("-\(formatTime(state.duration - state.currentTime))")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.3))
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var progress: CGFloat {
        guard state.duration > 0 else { return 0 }
        return min(1, max(0, CGFloat(state.currentTime / state.duration)))
    }

    func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    iPodView()
        .environment(iPodState())
}
