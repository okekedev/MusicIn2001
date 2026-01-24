//
//  MenuScreen.swift
//  Music2001iOS
//
//  Main menu with Zune-style typography

import SwiftUI

struct MenuScreen: View {
    @Environment(iPodState.self) var state

    var body: some View {
        let items = state.menuItems(for: state.currentScreen)

        ZStack {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MenuItemView(
                            title: item.title,
                            isSelected: index == state.selectedIndex
                        )
                        .id(index)
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: state.selectedIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            // Overlays
            if state.showingThankYou {
                OverlayView(
                    icon: "heart.fill",
                    title: "Thank You!"
                )
            }

            if state.isSyncing {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text(state.syncProgress)
                        .font(.system(size: 16, weight: .light))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.7))
            }

            if state.showingSyncResult {
                OverlayView(
                    icon: "checkmark.icloud.fill",
                    title: state.lastSyncResult
                )
            }
        }
    }
}

struct MenuItemView: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        Text(title.lowercased())
            .font(.system(size: isSelected ? 42 : 28, weight: .ultraLight))
            .foregroundColor(isSelected ? .white : .white.opacity(0.4))
            .animation(.easeOut(duration: 0.2), value: isSelected)
    }
}

struct OverlayView: View {
    let icon: String
    let title: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7))
    }
}
