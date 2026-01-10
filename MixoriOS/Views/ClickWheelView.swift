//
//  ClickWheelView.swift
//  MixoriOS
//

import SwiftUI

struct ClickWheelView: View {
    let size: CGFloat
    @Environment(iPodState.self) var state
    @State private var lastAngle: Double = 0
    @State private var isDragging: Bool = false
    @State private var accumulatedRotation: Double = 0
    @State private var showingAddedFeedback: Bool = false

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ZStack {
            // Outer Wheel - flat, flush with body
            Circle()
                .fill(state.selectedColor.wheel)
                .frame(width: size, height: size)

            // Button Labels - positioned INSIDE the wheel ring
            // Menu (top)
            Button(action: {
                impactMedium.impactOccurred()
                state.goBack()
            }) {
                Text("MENU")
                    .font(.system(size: size * 0.055, weight: .bold, design: .rounded))
                    .foregroundColor(buttonTextColor)
            }
            .buttonStyle(.plain)
            .position(x: size / 2, y: size * 0.18)

            // Previous (left)
            Button(action: {
                impactMedium.impactOccurred()
                state.previousTrack()
            }) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: size * 0.055))
                    .foregroundColor(buttonTextColor)
            }
            .buttonStyle(.plain)
            .position(x: size * 0.18, y: size / 2)

            // Next (right)
            Button(action: {
                impactMedium.impactOccurred()
                state.nextTrack()
            }) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: size * 0.055))
                    .foregroundColor(buttonTextColor)
            }
            .buttonStyle(.plain)
            .position(x: size * 0.82, y: size / 2)

            // Play/Pause (bottom)
            Button(action: {
                impactMedium.impactOccurred()
                state.togglePlayPause()
            }) {
                Image(systemName: "playpause.fill")
                    .font(.system(size: size * 0.055))
                    .foregroundColor(buttonTextColor)
            }
            .buttonStyle(.plain)
            .position(x: size / 2, y: size * 0.82)

            // Center Button - metallic/chrome look
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            state.selectedColor.centerButton.opacity(1.0),
                            state.selectedColor.centerButton.opacity(0.95)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.19
                    )
                )
                .frame(width: size * 0.38, height: size * 0.38)
                .onTapGesture {
                    impactMedium.impactOccurred()
                    state.selectCurrentItem()
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    // Long press to add song to On-The-Go (like real iPod)
                    if let track = state.currentSelectedTrack() {
                        impactHeavy.impactOccurred()
                        state.addToOnTheGo(track)
                        showingAddedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            showingAddedFeedback = false
                        }
                    }
                }

            // "Added" feedback overlay
            if showingAddedFeedback {
                Text("Added to On-The-Go")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in handleDrag(value) }
                .onEnded { _ in
                    isDragging = false
                    accumulatedRotation = 0
                }
        )
    }

    var buttonTextColor: Color {
        state.selectedColor.wheelText
    }

    private func handleDrag(_ value: DragGesture.Value) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = value.location.x - center.x
        let dy = value.location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        // Only respond to touches in the wheel ring (not center button)
        let innerRadius = size * 0.19
        let outerRadius = size * 0.5

        guard distance > innerRadius && distance < outerRadius else { return }

        let angle = atan2(dy, dx) * 180 / .pi

        if isDragging {
            var delta = angle - lastAngle

            // Handle wrap-around
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }

            accumulatedRotation += delta

            // Scroll threshold - roughly every 15 degrees
            let scrollThreshold: Double = 15

            if abs(accumulatedRotation) > scrollThreshold {
                impactLight.impactOccurred()

                // Clockwise (positive) scrolls down through menu
                if accumulatedRotation > 0 {
                    state.scrollUp()
                } else {
                    state.scrollDown()
                }

                accumulatedRotation = 0
            }

            // Volume adjustment on Now Playing screen
            if state.currentScreen == .nowPlaying {
                state.adjustVolume(by: delta / 180)
            }

            lastAngle = angle
        } else {
            isDragging = true
            lastAngle = angle
        }
    }
}

#Preview {
    ZStack {
        Color(white: 0.9)
        ClickWheelView(size: 280)
            .environment(iPodState())
    }
}
