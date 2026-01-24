//
//  NowPlayingScreen.swift
//  Music2001iOS
//
//  Now Playing screen with album art and progress

import SwiftUI

struct NowPlayingScreen: View {
    @Environment(iPodState.self) var state

    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack(spacing: 16) {
                Spacer()
                
                // Album Art
                if let artworkPath = state.currentTrack?.artworkRelativePath,
                   let artworkURL = state.artworkURL(for: artworkPath),
                   let imageData = try? Data(contentsOf: artworkURL),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.3))
                        )
                }

                // Track Info
                if let track = state.currentTrack {
                    VStack(spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 24, weight: .ultraLight))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Text(track.artist)
                            .font(.system(size: 18, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Text(track.album)
                            .font(.system(size: 14, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                // Progress
                ProgressBar(
                    currentTime: state.currentTime,
                    duration: state.duration
                )
                .padding(.bottom, 20)
            }
        }
    }
}

struct ProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    
    var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return min(1, max(0, CGFloat(currentTime / duration)))
    }
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { progressGeo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(Color.white)
                        .frame(width: progressGeo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 24)

            HStack {
                Text(formatTime(currentTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 24)
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
