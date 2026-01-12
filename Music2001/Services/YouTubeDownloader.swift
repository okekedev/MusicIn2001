import Foundation

/// Simple YouTube downloader using bundled yt-dlp binary
@MainActor
class YouTubeDownloader: ObservableObject {
    static let shared = YouTubeDownloader()

    @Published var isDownloading = false
    @Published var progress: String = ""
    @Published var error: String?

    private var currentProcess: Process?

    /// Get path to bundled yt-dlp binary
    private var ytdlpPath: URL? {
        // Check bundle first
        if let bundled = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) {
            return bundled
        }
        // Development: check Resources folder
        let devPath = URL(fileURLWithPath: "/Users/christian/Desktop/MusicIn2001/Music2001/Resources/yt-dlp")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath
        }
        // Fallback: homebrew
        let brewPath = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
        if FileManager.default.fileExists(atPath: brewPath.path) {
            return brewPath
        }
        return nil
    }

    /// Download audio from YouTube URL
    /// - Parameters:
    ///   - url: YouTube video URL
    ///   - outputDir: Directory to save the file
    ///   - completion: Called with (audioFileURL, artworkURL, title) on success
    func download(
        url: String,
        to outputDir: URL,
        completion: @escaping (Result<(audio: URL, artwork: URL?, title: String), Error>) -> Void
    ) {
        guard !isDownloading else {
            completion(.failure(DownloadError.alreadyDownloading))
            return
        }

        guard let ytdlp = ytdlpPath else {
            completion(.failure(DownloadError.ytdlpNotFound))
            return
        }

        isDownloading = true
        progress = "Starting download..."
        error = nil

        Task {
            do {
                let result = try await performDownload(ytdlp: ytdlp, url: url, outputDir: outputDir)
                await MainActor.run {
                    self.isDownloading = false
                    self.progress = "Complete!"
                    completion(.success(result))
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.error = error.localizedDescription
                    self.progress = ""
                    completion(.failure(error))
                }
            }
        }
    }

    private func performDownload(ytdlp: URL, url: String, outputDir: URL) async throws -> (audio: URL, artwork: URL?, title: String) {
        // Create temp directory for download
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Output template - use title for filename
        let outputTemplate = tempDir.appendingPathComponent("%(title)s.%(ext)s").path

        let process = Process()
        process.executableURL = ytdlp
        process.arguments = [
            "-x",                           // Extract audio
            "--audio-format", "mp3",        // Convert to MP3
            "--audio-quality", "0",         // Best quality
            "--write-thumbnail",            // Download thumbnail
            "--convert-thumbnails", "jpg",  // Convert to JPG
            "-o", outputTemplate,           // Output path
            "--no-playlist",                // Single video only
            "--progress",                   // Show progress
            url
        ]

        // Add ffmpeg path
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        currentProcess = process

        // Read progress updates
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            // Parse progress from yt-dlp output
            DispatchQueue.main.async {
                if output.contains("[download]") {
                    // Extract percentage
                    if let range = output.range(of: #"\d+\.?\d*%"#, options: .regularExpression) {
                        let percent = String(output[range])
                        self?.progress = "Downloading... \(percent)"
                    }
                } else if output.contains("Extracting audio") || output.contains("ffmpeg") {
                    self?.progress = "Converting to MP3..."
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                self?.currentProcess = nil

                if process.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: stderrData, encoding: .utf8) ?? "Download failed"
                    continuation.resume(throwing: DownloadError.downloadFailed(errorMsg))
                    return
                }

                // Find downloaded files
                do {
                    let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)

                    guard let audioFile = files.first(where: { $0.pathExtension == "mp3" }) else {
                        continuation.resume(throwing: DownloadError.noAudioFile)
                        return
                    }

                    let artworkFile = files.first(where: { $0.pathExtension == "jpg" || $0.pathExtension == "webp" || $0.pathExtension == "png" })

                    // Get title from filename
                    let title = audioFile.deletingPathExtension().lastPathComponent

                    // Move files to output directory
                    let finalAudio = outputDir.appendingPathComponent(audioFile.lastPathComponent)
                    try? FileManager.default.removeItem(at: finalAudio)
                    try FileManager.default.copyItem(at: audioFile, to: finalAudio)

                    var finalArtwork: URL? = nil
                    if let artwork = artworkFile {
                        let artworkDest = outputDir.appendingPathComponent(title + ".jpg")
                        try? FileManager.default.removeItem(at: artworkDest)
                        try FileManager.default.copyItem(at: artwork, to: artworkDest)
                        finalArtwork = artworkDest
                    }

                    continuation.resume(returning: (audio: finalAudio, artwork: finalArtwork, title: title))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: DownloadError.processError(error.localizedDescription))
            }
        }
    }

    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
        isDownloading = false
        progress = ""
    }
}

enum DownloadError: LocalizedError {
    case alreadyDownloading
    case ytdlpNotFound
    case downloadFailed(String)
    case noAudioFile
    case processError(String)

    var errorDescription: String? {
        switch self {
        case .alreadyDownloading:
            return "A download is already in progress"
        case .ytdlpNotFound:
            return "yt-dlp not found. Please install via: brew install yt-dlp"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .noAudioFile:
            return "No audio file was created"
        case .processError(let msg):
            return "Process error: \(msg)"
        }
    }
}
