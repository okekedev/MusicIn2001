import Foundation

struct AudioTrack: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let instrumentalURL: URL
    let vocalsURL: URL
    let originalURL: String?
    let createdAt: Date
    let duration: TimeInterval?

    init(
        id: UUID = UUID(),
        title: String,
        instrumentalURL: URL,
        vocalsURL: URL,
        originalURL: String? = nil,
        createdAt: Date = Date(),
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.instrumentalURL = instrumentalURL
        self.vocalsURL = vocalsURL
        self.originalURL = originalURL
        self.createdAt = createdAt
        self.duration = duration
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
