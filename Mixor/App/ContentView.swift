import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showingSettings = false

    var body: some View {
        PlayerView(showingSettings: $showingSettings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MixorTheme.background)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let fileManager = FileManagerService.shared
    @State private var isSyncing = false
    @State private var syncResult: String?

    var body: some View {
        VStack(spacing: MixorTheme.largeSpacing) {
            HStack {
                Text("Settings")
                    .font(.headline)
                    .foregroundColor(MixorTheme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(MixorTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // iCloud Status
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: fileManager.iCloudAvailable ? "checkmark.icloud.fill" : "xmark.icloud")
                        .foregroundColor(fileManager.iCloudAvailable ? .green : MixorTheme.textTertiary)
                    Text(fileManager.iCloudAvailable ? "iCloud Drive Connected" : "iCloud Drive Unavailable")
                        .font(.subheadline)
                        .foregroundColor(MixorTheme.textPrimary)

                    Spacer()

                    if fileManager.iCloudAvailable {
                        Button {
                            syncLocalToiCloud()
                        } label: {
                            if isSyncing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Sync to iCloud")
                                    .font(.caption)
                                    .foregroundColor(MixorTheme.primary)
                            }
                        }
                        .disabled(isSyncing)
                    }
                }

                if let result = syncResult {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(result)
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                } else if fileManager.iCloudAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(MixorTheme.textTertiary)
                        Text("Music syncs automatically via iCloud Drive")
                            .font(.caption2)
                            .foregroundColor(MixorTheme.textTertiary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("Sign in to iCloud in System Settings to sync with iOS")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(12)
            .background(MixorTheme.elevatedBackground)
            .cornerRadius(8)

            // Music Folder
            VStack(alignment: .leading, spacing: MixorTheme.spacing) {
                Text("Music Folder")
                    .font(.subheadline)
                    .foregroundColor(MixorTheme.textSecondary)

                HStack {
                    Text(fileManager.musicDirectory.path)
                        .font(.caption)
                        .foregroundColor(MixorTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Open") {
                        fileManager.openInFinder(directory: fileManager.musicDirectory)
                    }
                    .font(.caption)
                    .foregroundColor(MixorTheme.primary)
                }
                .padding(12)
                .background(MixorTheme.elevatedBackground)
                .cornerRadius(8)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(MixorTheme.textTertiary)
                    Text("Move music files into this folder to make them available in the app")
                        .font(.caption2)
                        .foregroundColor(MixorTheme.textTertiary)
                }
            }

            Spacer()
        }
        .padding(MixorTheme.largeSpacing)
        .frame(width: 400, height: 320)
        .background(MixorTheme.cardBackground)
    }

    private func syncLocalToiCloud() {
        isSyncing = true
        syncResult = nil

        Task {
            let count = await fileManager.syncWithiCloud()
            await MainActor.run {
                isSyncing = false
                if count > 0 {
                    syncResult = "Synced \(count) file\(count == 1 ? "" : "s")"
                } else {
                    syncResult = "Already in sync"
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
