import Foundation

enum UploadError: Error, LocalizedError {
    case notAuthenticated
    case uploadFailed(String)
    case invalidVideo
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please sign in first."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .invalidVideo:
            return "Invalid video file"
        case .quotaExceeded:
            return "Upload quota exceeded. Try again later."
        }
    }
}

@MainActor
class YouTubeUploadService: ObservableObject {
    @Published var isUploading = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    private var currentTask: URLSessionTask?
    private var isCancelled = false

    private let authService: GoogleAuthService

    init(authService: GoogleAuthService) {
        self.authService = authService
    }

    func upload(
        video: URL,
        metadata: UploadMetadata,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> String {
        guard authService.isAuthenticated,
              let accessToken = authService.accessToken else {
            throw UploadError.notAuthenticated
        }

        guard FileManager.default.fileExists(atPath: video.path) else {
            throw UploadError.invalidVideo
        }

        isCancelled = false
        isUploading = true
        progress = 0
        statusMessage = "Preparing upload..."

        defer {
            isUploading = false
            currentTask = nil
        }

        // Step 1: Initialize resumable upload
        let uploadURL = try await initializeUpload(
            accessToken: accessToken,
            metadata: metadata,
            fileSize: FileManager.default.attributesOfItem(atPath: video.path)[.size] as? Int64 ?? 0
        )

        // Step 2: Upload video content
        let videoId = try await uploadContent(
            uploadURL: uploadURL,
            videoFile: video,
            accessToken: accessToken,
            progressHandler: progressHandler
        )

        return videoId
    }

    private func initializeUpload(
        accessToken: String,
        metadata: UploadMetadata,
        fileSize: Int64
    ) async throws -> URL {
        let initURL = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!

        var request = URLRequest(url: initURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")

        let body: [String: Any] = [
            "snippet": [
                "title": metadata.title,
                "description": metadata.description,
                "tags": metadata.tags,
                "categoryId": "10" // Music category
            ],
            "status": [
                "privacyStatus": metadata.privacy.rawValue,
                "selfDeclaredMadeForKids": false
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.uploadFailed("Invalid response")
        }

        if httpResponse.statusCode == 403 {
            throw UploadError.quotaExceeded
        }

        guard httpResponse.statusCode == 200,
              let locationHeader = httpResponse.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: locationHeader) else {
            throw UploadError.uploadFailed("Failed to initialize upload")
        }

        return uploadURL
    }

    private func uploadContent(
        uploadURL: URL,
        videoFile: URL,
        accessToken: String,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws -> String {
        let fileData = try Data(contentsOf: videoFile)
        let fileSize = fileData.count

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("video/*", forHTTPHeaderField: "Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")

        // Create upload task with progress tracking
        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, from: fileData) { [weak self] data, response, error in
                if let error = error {
                    continuation.resume(throwing: UploadError.uploadFailed(error.localizedDescription))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: UploadError.uploadFailed("Invalid response"))
                    return
                }

                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    // Parse video ID from response
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let videoId = json["id"] as? String {
                        DispatchQueue.main.async {
                            self?.progress = 1.0
                            self?.statusMessage = "Upload complete!"
                        }
                        continuation.resume(returning: videoId)
                    } else {
                        continuation.resume(throwing: UploadError.uploadFailed("Could not parse video ID"))
                    }
                } else {
                    continuation.resume(throwing: UploadError.uploadFailed("Upload failed with status \(httpResponse.statusCode)"))
                }
            }

            // Observe progress
            let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                DispatchQueue.main.async {
                    self?.progress = progress.fractionCompleted
                    self?.statusMessage = "Uploading: \(Int(progress.fractionCompleted * 100))%"
                    progressHandler(progress.fractionCompleted, "Uploading...")
                }
            }

            currentTask = task
            task.resume()

            // Store observation to keep it alive
            _ = observation
        }
    }

    func cancel() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
        isUploading = false
        statusMessage = "Cancelled"
    }
}
