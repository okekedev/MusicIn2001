import Foundation

struct VideoProject: Identifiable {
    let id: UUID
    var imageURL: URL?
    var audioURL: URL?
    var outputURL: URL?
    var title: String
    var status: Status
    var progress: Double

    enum Status {
        case draft
        case processing
        case complete
        case failed
    }

    init(
        id: UUID = UUID(),
        title: String = "Untitled Video"
    ) {
        self.id = id
        self.title = title
        self.status = .draft
        self.progress = 0
    }

    var canCreate: Bool {
        imageURL != nil && audioURL != nil
    }
}

struct UploadMetadata {
    var title: String
    var description: String
    var privacy: Privacy
    var tags: [String]

    enum Privacy: String, CaseIterable {
        case `public` = "public"
        case unlisted = "unlisted"
        case `private` = "private"

        var displayName: String {
            switch self {
            case .public: return "Public"
            case .unlisted: return "Unlisted"
            case .private: return "Private"
            }
        }
    }

    init(
        title: String = "",
        description: String = "",
        privacy: Privacy = .private,
        tags: [String] = []
    ) {
        self.title = title
        self.description = description
        self.privacy = privacy
        self.tags = tags
    }
}
