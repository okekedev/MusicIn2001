import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: String?
    @Published var accessToken: String?

    // Shared file manager
    let fileManager = FileManagerService.shared

    // Recent extractions for quick access
    @Published var recentExtractions: [AudioTrack] = []

    // Mixer deck queues (shared between Player and Mix views)
    @Published var deckAQueue: [TrackMetadata] = []
    @Published var deckBQueue: [TrackMetadata] = []
    @Published var isMixerActive: Bool = false

    // Navigation
    @Published var shouldNavigateToPlayer: Bool = false
    @Published var showQueueTooltip: Bool = false
    @Published var queueTooltipDeck: String = ""

    // User preferences
    @AppStorage("hideQueueTooltip") var hideQueueTooltip: Bool = false

    // Add track to deck queue
    func addToDeckA(_ track: TrackMetadata) {
        if !deckAQueue.contains(where: { $0.id == track.id }) {
            deckAQueue.append(track)
        }
    }

    func addToDeckB(_ track: TrackMetadata) {
        if !deckBQueue.contains(where: { $0.id == track.id }) {
            deckBQueue.append(track)
        }
    }

    func removeFromDeckA(at index: Int) {
        guard index >= 0 && index < deckAQueue.count else { return }
        deckAQueue.remove(at: index)
    }

    func removeFromDeckB(at index: Int) {
        guard index >= 0 && index < deckBQueue.count else { return }
        deckBQueue.remove(at: index)
    }

    func navigateToPlayerForQueue(deck: String) {
        queueTooltipDeck = deck
        // Only show tooltip if user hasn't dismissed it permanently
        if !hideQueueTooltip {
            showQueueTooltip = true
        }
        shouldNavigateToPlayer = true
    }

    func dismissQueueTooltipPermanently() {
        hideQueueTooltip = true
        showQueueTooltip = false
    }

    init() {
        // Load stored auth state
        loadAuthState()

        // Ensure directories exist
        do {
            try fileManager.ensureDirectoriesExist()
        } catch {
            print("Failed to create directories: \(error)")
        }
    }

    private func loadAuthState() {
        if let token = KeychainService.load(key: "access_token") {
            accessToken = token
            isAuthenticated = true
            currentUser = KeychainService.load(key: "user_email")
        }
    }

    func logout() {
        KeychainService.delete(key: "access_token")
        KeychainService.delete(key: "refresh_token")
        KeychainService.delete(key: "user_email")
        accessToken = nil
        currentUser = nil
        isAuthenticated = false
    }

    func addRecentExtraction(_ track: AudioTrack) {
        recentExtractions.insert(track, at: 0)
        if recentExtractions.count > 10 {
            recentExtractions.removeLast()
        }
    }
}
