import Foundation

struct ProcessingJob: Identifiable {
    let id: UUID
    var status: Status
    var progress: Double
    var statusMessage: String
    var currentStep: String
    var result: JobResult?
    var error: String?

    enum Status: String {
        case queued
        case downloading
        case processing
        case complete
        case failed
        case cancelled
    }

    struct JobResult: Codable {
        let success: Bool
        let instrumentalPath: String?
        let vocalsPath: String?
        let title: String?
        let duration: Double?
        let error: String?
    }

    init(id: UUID = UUID()) {
        self.id = id
        self.status = .queued
        self.progress = 0
        self.statusMessage = "Queued"
        self.currentStep = "waiting"
        self.result = nil
        self.error = nil
    }

    var isActive: Bool {
        switch status {
        case .queued, .downloading, .processing:
            return true
        case .complete, .failed, .cancelled:
            return false
        }
    }
}

struct ProgressUpdate: Codable {
    let progress: Double
    let status: String
    let step: String
}
