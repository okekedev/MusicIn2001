//
//  ZunePlayerView.swift
//  Music2001iOS
//
//  Complete Zune-style music player - single file

import SwiftUI

// MARK: - Main Player View
struct ZunePlayerView: View {
    @Environment(iPodState.self) var state
    @State private var lastDragY: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var accumulatedScroll: CGFloat = 0
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geometry in
            let safeBottom = geometry.safeAreaInsets.bottom
            let screenHeight = geometry.size.height * 0.70
            let controlsHeight = geometry.size.height * 0.30
            
            ZStack {
                // Background extends into safe areas
                AnimatedGradient()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Screen Area (70%)
                    VStack(spacing: 0) {
                        MinimalStatusBar()
                            .frame(height: 20)
                            .padding(.horizontal, 12)
                        
                        Group {
                            switch state.currentScreen {
                            case .nowPlaying:
                                NowPlaying()
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                            default:
                                MenuList()
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)
                                    ))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: screenHeight)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleContinuousDrag(value)
                            }
                            .onEnded { value in
                                handleDragEnd(value)
                            }
                    )
                    
                    // Controls (30%) - background extends into safe area
                    ZuneControlPad(size: geometry.size.width)
                        .frame(height: controlsHeight)
                        .padding(.bottom, safeBottom)
                }
            }
        }
        .overlay {
            if state.showingOnboarding {
                WelcomeOverlay()
            }
        }
    }
    
    private func handleContinuousDrag(_ value: DragGesture.Value) {
        if !isDragging {
            isDragging = true
            lastDragY = value.location.y
            accumulatedScroll = 0
            return
        }
        
        let delta = value.location.y - lastDragY
        accumulatedScroll += delta
        
        // Scroll threshold - about 25 points per item
        let scrollThreshold: CGFloat = 25
        
        if abs(accumulatedScroll) > scrollThreshold {
            if state.hapticFeedbackEnabled {
                impactLight.impactOccurred()
            }
            
            if accumulatedScroll < 0 {
                // Dragging up = scroll up
                state.scrollUp()
            } else {
                // Dragging down = scroll down
                state.scrollDown()
            }
            
            accumulatedScroll = 0
        }
        
        lastDragY = value.location.y
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        // Reset dragging state
        let wasDragging = isDragging
        isDragging = false
        
        let horizontalAmount = value.translation.width
        let verticalAmount = value.translation.height
        let totalMovement = sqrt(horizontalAmount * horizontalAmount + verticalAmount * verticalAmount)
        
        // If barely moved (< 10 points), treat as a tap to select
        if totalMovement < 10 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.selectCurrentItem()
            }
            accumulatedScroll = 0
            return
        }
        
        // If user was actively dragging (scrolling), don't trigger swipe actions
        // This prevents accidental navigation when user is just scrolling through list
        if wasDragging && abs(verticalAmount) > abs(horizontalAmount) {
            accumulatedScroll = 0
            return
        }
        
        accumulatedScroll = 0
        
        // Check if it was a quick swipe for navigation
        // Only treat as swipe if it was quick and primarily horizontal
        if abs(horizontalAmount) > 80 && abs(horizontalAmount) > abs(verticalAmount) * 1.5 {
            if horizontalAmount > 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    state.goBack()
                }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    state.selectCurrentItem()
                }
            }
        }
    }
}

// MARK: - Animated Gradient
struct AnimatedGradient: View {
    @Environment(iPodState.self) var state
    @State private var animate = false
    
    var body: some View {
        LinearGradient(
            colors: state.selectedBackgroundTheme.colors,
            startPoint: animate ? .topLeading : .bottomLeading,
            endPoint: animate ? .bottomTrailing : .topTrailing
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
        .onChange(of: state.selectedBackgroundTheme.name) { _, _ in
            // Restart animation when theme changes
            animate = false
            withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Status Bar
struct MinimalStatusBar: View {
    @Environment(iPodState.self) var state
    
    var body: some View {
        HStack(spacing: 8) {
            if state.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
    }
}

// MARK: - Menu List
struct MenuList: View {
    @Environment(iPodState.self) var state

    var body: some View {
        let items = state.menuItems(for: state.currentScreen)

        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Text(item.title.lowercased())
                                .font(.system(size: index == state.selectedIndex ? 42 : 34, weight: .ultraLight))
                                .foregroundColor(index == state.selectedIndex ? .white : .white.opacity(0.4))
                                .offset(x: index == state.selectedIndex ? 0 : -10)
                                .id(index)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: state.selectedIndex)
                    .padding(.leading, 28)
                    .padding(.top, 40)
                    .padding(.bottom, 100)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(true) // User scrolls with wheel, not by dragging
                .onChange(of: state.selectedIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .top)
                    }
                }
            }

            if state.showingThankYou {
                StatusOverlay(icon: "heart.fill", text: "Thank You!")
                    .transition(.scale.combined(with: .opacity))
            }

            if state.isSyncing {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text(state.syncProgress)
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.7))
                .transition(.opacity)
            }

            if state.showingSyncResult {
                StatusOverlay(icon: "checkmark.icloud.fill", text: state.lastSyncResult)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct StatusOverlay: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.white)
            Text(text)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7))
    }
}

// MARK: - Now Playing
struct NowPlaying: View {
    @Environment(iPodState.self) var state

    var body: some View {
        VStack(spacing: 20) {
                Spacer()
                
                if let artworkPath = state.currentTrack?.artworkRelativePath,
                   let artworkURL = state.artworkURL(for: artworkPath),
                   let imageData = try? Data(contentsOf: artworkURL),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 240, height: 240)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 70))
                                .foregroundColor(.white.opacity(0.3))
                        )
                }

                if let track = state.currentTrack {
                    VStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Text(track.artist)
                            .font(.system(size: 22, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Text(track.album)
                            .font(.system(size: 18, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 5)
                            
                            Capsule()
                                .fill(Color.white)
                                .frame(width: geo.size.width * progress, height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.horizontal, 28)

                    HStack {
                        Text(formatTime(state.currentTime))
                        Spacer()
                        Text(formatTime(state.duration))
                    }
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 24)
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

// MARK: - Control Pad
struct ZuneControlPad: View {
    let size: CGFloat
    @Environment(iPodState.self) var state
    @State private var lastAngle: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var accumulatedRotation: CGFloat = 0
    @State private var particles: [WheelParticle] = []
    @State private var lastParticleAngle: CGFloat = 0
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        // Determine wheel ring colors based on shell brightness
        let wheelRingColors: [Color] = {
            // Silver (light shell) gets lighter gray ring
            if state.selectedColor.name == "Silver" {
                return [
                    Color(white: 0.65),
                    Color(white: 0.55)
                ]
            } else {
                // Black (dark shell) keeps dark ring
                return [
                    Color(white: 0.25),
                    Color(white: 0.15)
                ]
            }
        }()
        
        ZStack {
            // Background color extends into safe area
            state.selectedColor.shell
                .ignoresSafeArea()
            
            // Controls centered vertically
            HStack(spacing: size * 0.04) {
                Button {
                    if state.hapticFeedbackEnabled {
                        impactMedium.impactOccurred()
                    }
                    state.goBack()
                } label: {
                    Circle()
                        .fill(state.selectedColor.wheel)
                        .frame(width: size * 0.14, height: size * 0.14)
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.system(size: size * 0.055, weight: .semibold))
                                .foregroundColor(state.selectedColor.wheelText)
                        )
                }
                .buttonStyle(.plain)
                
                // Touchpad - tap to select, drag circularly to scroll
                ZStack {
                    // Outer ring border (subtle gray - thinner)
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(white: 0.5),
                                    Color(white: 0.35),
                                    Color(white: 0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: size * 0.008
                        )
                        .frame(width: size * 0.55, height: size * 0.55)
                    
                    // Wheel ring (with hole in center) - lighter for silver, darker for black
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: wheelRingColors,
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.27
                            )
                        )
                        .frame(width: size * 0.53, height: size * 0.53)
                        .mask(
                            // Create donut shape by cutting out center - smaller center = more scrollable area
                            Circle()
                                .fill(Color.white)
                                .overlay(
                                    Circle()
                                        .fill(Color.black)
                                        .frame(width: size * 0.24, height: size * 0.24)
                                        .blendMode(.destinationOut)
                                )
                        )
                    
                    // Inner ring border (subtle gray - thinner)
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(white: 0.4),
                                    Color(white: 0.3),
                                    Color(white: 0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: size * 0.006
                        )
                        .frame(width: size * 0.24, height: size * 0.24)
                    
                    // Particles following the scroll
                    ForEach(particles) { particle in
                        Circle()
                            .fill(Color.white.opacity(particle.opacity))
                            .frame(width: particle.size, height: particle.size)
                            .position(particle.position)
                            .blur(radius: 0.5)
                    }
                    
                    // Center button (matches shell color) - smaller for more scroll area
                    Circle()
                        .fill(state.selectedColor.shell)
                        .frame(width: size * 0.23, height: size * 0.23)
                        .overlay(
                            Circle()
                                .stroke(Color(white: 0.3).opacity(0.2), lineWidth: 0.5)
                                .frame(width: size * 0.23, height: size * 0.23)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
                }
                .frame(width: size * 0.55, height: size * 0.55)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleWheelDrag(value)
                        }
                        .onEnded { value in
                            handleWheelDragEnd(value)
                        }
                )
                
                Button {
                    if state.hapticFeedbackEnabled {
                        impactMedium.impactOccurred()
                    }
                    state.togglePlayPause()
                } label: {
                    Circle()
                        .fill(state.selectedColor.wheel)
                        .frame(width: size * 0.14, height: size * 0.14)
                        .overlay(
                            Image(systemName: "playpause.fill")
                                .font(.system(size: size * 0.055, weight: .semibold))
                                .foregroundColor(state.selectedColor.wheelText)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Wheel Gesture Handlers (Circular Scroll)
    
    /// Calculate angle from center of wheel to touch point
    private func angle(for location: CGPoint, in wheelSize: CGFloat) -> CGFloat {
        let center = wheelSize / 2
        let dx = location.x - center
        let dy = location.y - center
        return atan2(dy, dx)
    }
    
    /// Convert angle to position on the wheel ring
    private func position(for angle: CGFloat, wheelSize: CGFloat, radius: CGFloat) -> CGPoint {
        let center = wheelSize / 2
        let x = center + cos(angle) * radius
        let y = center + sin(angle) * radius
        return CGPoint(x: x, y: y)
    }
    
    private func handleWheelDrag(_ value: DragGesture.Value) {
        let wheelSize = size * 0.55
        let currentAngle = angle(for: value.location, in: wheelSize)
        
        if !isDragging {
            isDragging = true
            lastAngle = currentAngle
            lastParticleAngle = currentAngle
            accumulatedRotation = 0
            return
        }
        
        // Calculate angular delta (handling wrap-around at ±π)
        var delta = currentAngle - lastAngle
        
        // Handle crossing the -π/π boundary
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta < -.pi {
            delta += 2 * .pi
        }
        
        accumulatedRotation += delta
        
        // Spawn particles as you drag (every ~15 degrees)
        let particleThreshold: CGFloat = .pi / 12 // ~15 degrees
        var particleDelta = currentAngle - lastParticleAngle
        if particleDelta > .pi {
            particleDelta -= 2 * .pi
        } else if particleDelta < -.pi {
            particleDelta += 2 * .pi
        }
        
        if abs(particleDelta) > particleThreshold {
            spawnParticle(at: currentAngle, wheelSize: wheelSize)
            lastParticleAngle = currentAngle
        }
        
        // Rotation threshold - about π/8 radians (22.5°) per item
        // This means ~16 items per full rotation (360°)
        let rotationThreshold: CGFloat = .pi / 8
        
        if abs(accumulatedRotation) > rotationThreshold {
            if state.hapticFeedbackEnabled {
                impactLight.impactOccurred()
            }
            
            if accumulatedRotation > 0 {
                // Clockwise = scroll up
                state.scrollUp()
            } else {
                // Counter-clockwise = scroll down
                state.scrollDown()
            }
            
            accumulatedRotation = 0
        }
        
        lastAngle = currentAngle
    }
    
    private func handleWheelDragEnd(_ value: DragGesture.Value) {
        isDragging = false
        
        let totalMovement = sqrt(
            value.translation.width * value.translation.width +
            value.translation.height * value.translation.height
        )
        
        // If barely moved (< 10 points), treat as a tap to select
        if totalMovement < 10 {
            if state.hapticFeedbackEnabled {
                impactMedium.impactOccurred()
            }
            
            // Trigger particle revolution around the wheel
            spawnParticleRevolution()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.selectCurrentItem()
            }
        }
        
        accumulatedRotation = 0
        
        // Fade out remaining particles
        withAnimation(.easeOut(duration: 0.5)) {
            particles.removeAll()
        }
    }
    
    // MARK: - Particle Effects
    
    private func spawnParticle(at angle: CGFloat, wheelSize: CGFloat) {
        let radius = wheelSize * 0.21 // Position on the wheel ring
        let particlePosition = position(for: angle, wheelSize: wheelSize, radius: radius)
        
        let particle = WheelParticle(
            position: particlePosition,
            opacity: 0.8,
            size: CGFloat.random(in: 2...4)
        )
        
        particles.append(particle)
        
        // Fade out and remove particle after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                    particles[index].opacity = 0
                    particles[index].size = 1
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                particles.removeAll { $0.id == particle.id }
            }
        }
    }
    
    /// Create a revolution of particles around the wheel when center button is tapped
    private func spawnParticleRevolution() {
        let wheelSize = size * 0.55
        let radius = wheelSize * 0.21
        
        // Create 24 particles around the wheel (every 15 degrees)
        let particleCount = 24
        
        for i in 0..<particleCount {
            let angle = (CGFloat(i) / CGFloat(particleCount)) * 2 * .pi
            let particlePosition = position(for: angle, wheelSize: wheelSize, radius: radius)
            
            let particle = WheelParticle(
                position: particlePosition,
                opacity: 0.9,
                size: 3
            )
            
            // Stagger the appearance slightly for wave effect
            let delay = Double(i) * 0.015 // 15ms per particle
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                particles.append(particle)
                
                // Fade out after appearing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                            particles[index].opacity = 0
                            particles[index].size = 1
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        particles.removeAll { $0.id == particle.id }
                    }
                }
            }
        }
    }
}

// MARK: - Wheel Particle
struct WheelParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var opacity: Double
    var size: CGFloat
}

// MARK: - Onboarding
struct WelcomeOverlay: View {
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

#Preview {
    ZunePlayerView()
        .environment(iPodState())
}
