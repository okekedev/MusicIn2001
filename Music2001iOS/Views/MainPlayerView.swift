//
//  MainPlayerView.swift
//  Music2001iOS
//
//  Single main view - entry point for the entire app

import SwiftUI

struct MainPlayerView: View {
    @Environment(iPodState.self) var state

    var body: some View {
        GeometryReader { geometry in
            let deviceWidth = min(geometry.size.width * 0.85, 360)
            let deviceHeight = deviceWidth * 1.8
            let screenHeight = deviceHeight * 0.65
            let controlsHeight = deviceHeight * 0.35
            
            ZStack {
                // Background
                state.selectedColor.background
                    .ignoresSafeArea()
                
                // Device card
                VStack(spacing: 0) {
                    // Screen (65%) - shows different screens based on state
                    ZStack {
                        GradientBackground()
                        
                        VStack(spacing: 0) {
                            StatusBar()
                                .frame(height: 20)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            
                            // Different screens based on state
                            Group {
                                switch state.currentScreen {
                                case .nowPlaying:
                                    NowPlayingScreen()
                                default:
                                    MenuScreen()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(height: screenHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    // Controls (35%)
                    ControlsArea(size: deviceWidth)
                        .frame(height: controlsHeight)
                        .background(state.selectedColor.shell)
                }
                .frame(width: deviceWidth, height: deviceHeight)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .overlay {
            if state.showingOnboarding {
                OnboardingView()
            }
        }
    }
}

// MARK: - Controls Area
struct ControlsArea: View {
    let size: CGFloat
    @Environment(iPodState.self) var state
    @State private var lastDragY: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var accumulatedScroll: CGFloat = 0
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        HStack(spacing: size * 0.05) {
            // Left: Back button
            Button {
                impactMedium.impactOccurred()
                state.goBack()
            } label: {
                Circle()
                    .fill(state.selectedColor.wheel)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: size * 0.06, weight: .semibold))
                            .foregroundColor(state.selectedColor.wheelText)
                    )
            }
            .buttonStyle(.plain)
            
            // Center: Large circular touchpad
            Button {
                impactMedium.impactOccurred()
                state.selectCurrentItem()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(white: 0.6),
                                    Color(white: 0.4),
                                    Color(white: 0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: size * 0.015
                        )
                        .frame(width: size * 0.50, height: size * 0.50)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(white: 0.25),
                                    Color(white: 0.15)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.22
                            )
                        )
                        .frame(width: size * 0.44, height: size * 0.44)
                }
            }
            .buttonStyle(.plain)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in handleDrag(value) }
                    .onEnded { _ in
                        isDragging = false
                        accumulatedScroll = 0
                    }
            )
            
            // Right: Play/Pause button
            Button {
                impactMedium.impactOccurred()
                state.togglePlayPause()
            } label: {
                Circle()
                    .fill(state.selectedColor.wheel)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .overlay(
                        Image(systemName: "playpause.fill")
                            .font(.system(size: size * 0.06, weight: .semibold))
                            .foregroundColor(state.selectedColor.wheelText)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func handleDrag(_ value: DragGesture.Value) {
        if !isDragging {
            isDragging = true
            lastDragY = value.location.y
            return
        }
        
        let delta = value.location.y - lastDragY
        accumulatedScroll += delta
        
        let scrollThreshold: CGFloat = 15
        
        if abs(accumulatedScroll) > scrollThreshold {
            impactLight.impactOccurred()
            
            if accumulatedScroll < 0 {
                state.scrollUp()
            } else {
                state.scrollDown()
            }
            
            accumulatedScroll = 0
        }
        
        if state.currentScreen == .nowPlaying {
            state.adjustVolume(by: -delta / 200)
        }
        
        lastDragY = value.location.y
    }
}

#Preview {
    MainPlayerView()
        .environment(iPodState())
}
