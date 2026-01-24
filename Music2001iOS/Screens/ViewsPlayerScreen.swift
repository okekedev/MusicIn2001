//
//  PlayerScreen.swift
//  Music2001iOS
//
//  Main screen display component

import SwiftUI

struct PlayerScreen: View {
    @Environment(iPodState.self) var state

    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack(spacing: 0) {
                StatusBar()
                    .frame(height: 20)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                
                ScreenContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct ScreenContent: View {
    @Environment(iPodState.self) var state

    var body: some View {
        Group {
            switch state.currentScreen {
            case .nowPlaying:
                NowPlayingScreen()
            default:
                MenuScreen()
            }
        }
    }
}
