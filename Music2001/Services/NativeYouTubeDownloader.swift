import Foundation
import AVFoundation

// MARK: - Native YouTube Downloader
// Uses YouTubeKit for extraction (add via SPM: https://github.com/alexeichhorn/YouTubeKit)

/// Native YouTube downloader that works within App Sandbox
/// No external executables required - uses YouTubeKit + AVFoundation
@MainActor
class NativeYouTubeDownloader: ObservableObject {
    static let shared = NativeYouTubeDownloader()

    @Published var isDownloading = false
    @Published var progress: String = ""
    @Published var downloadProgress: Double = 0
    @Published var error: String?

    private var downloadTask: URLSessionDownloadTask?

    struct DownloadResult {
        let audioURL: URL
        let artworkURL: URL?
        let title: String
        let artist: String
        let album: String
    }

    /// Extract video ID from various YouTube URL formats
    func extractVideoID(from urlString: String) -> String? {
        // Handle various YouTube URL formats
        let patterns = [
            "(?:v=|/v/|youtu\\.be/|/embed/)([a-zA-Z0-9_-]{11})",
            "^([a-zA-Z0-9_-]{11})$"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
               let range = Range(match.range(at: 1), in: urlString) {
                return String(urlString[range])
            }
        }
        return nil
    }

    /// Download audio from YouTube
    func download(
        url urlString: String,
        to outputDir: URL,
        artworkDir: URL,
        progressHandler: @escaping (String) -> Void
    ) async throws -> DownloadResult {
        guard !isDownloading else {
            throw DownloadError.alreadyDownloading
        }

        guard let videoID = extractVideoID(from: urlString) else {
            throw DownloadError.invalidURL
        }

        isDownloading = true
        progress = "Extracting video info..."
        progressHandler("Extracting video info...")

        defer { isDownloading = false }

        // Step 1: Get video info using YouTubeKit
        // Note: You need to add YouTubeKit package first
        // For now, we'll use a direct API approach

        let (title, artist, album, audioStreamURL, thumbnailURL) = try await fetchVideoInfo(videoID: videoID)

        progress = "Downloading audio..."
        progressHandler("Downloading \"\(title)\"...")

        // Step 2: Download the audio stream
        let tempAudioURL = try await downloadFile(from: audioStreamURL, progressHandler: { [weak self] prog in
            self?.downloadProgress = prog
            progressHandler("Downloading... \(Int(prog * 100))%")
        })

        // Step 3: Convert to MP3 using AVFoundation (if needed)
        let safeTitle = sanitizeFilename(title)
        let finalAudioURL = outputDir.appendingPathComponent("\(safeTitle).mp3")

        progress = "Converting to MP3..."
        progressHandler("Converting to MP3...")

        try await convertToMP3(input: tempAudioURL, output: finalAudioURL)

        // Step 4: Download thumbnail
        var finalArtworkURL: URL? = nil
        if let thumbURL = thumbnailURL {
            progress = "Downloading artwork..."
            progressHandler("Downloading artwork...")

            let artworkURL = artworkDir.appendingPathComponent("\(safeTitle).jpg")
            if let artworkData = try? await downloadData(from: thumbURL) {
                try? artworkData.write(to: artworkURL)
                finalArtworkURL = artworkURL
            }
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempAudioURL)

        progress = "Complete!"
        progressHandler("Complete!")

        return DownloadResult(
            audioURL: finalAudioURL,
            artworkURL: finalArtworkURL,
            title: title,
            artist: artist,
            album: album
        )
    }

    // MARK: - Private Methods

    private func fetchVideoInfo(videoID: String) async throws -> (title: String, artist: String, album: String, audioURL: URL, thumbnailURL: URL?) {
        // Fetch video info from YouTube's oEmbed API (basic info)
        let oembedURL = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json")!

        let (data, _) = try await URLSession.shared.data(from: oembedURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let title = json?["title"] as? String ?? "Unknown"
        var artist = json?["author_name"] as? String ?? "Unknown Artist"

        // Clean up artist name (remove " - Topic", "VEVO", etc.)
        artist = artist.replacingOccurrences(of: " - Topic", with: "")
        artist = artist.replacingOccurrences(of: "VEVO", with: "")
        artist = artist.trimmingCharacters(in: .whitespaces)

        // Try to parse "Artist - Title" format
        if title.contains(" - ") {
            let parts = title.components(separatedBy: " - ")
            if parts.count >= 2 && artist == "Unknown Artist" {
                artist = parts[0].trimmingCharacters(in: .whitespaces)
            }
        }

        let thumbnailURL = URL(string: "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg")

        // For audio URL, we need YouTubeKit or similar
        // This is a placeholder - YouTubeKit will provide the actual stream URL
        // For now, throw an error indicating YouTubeKit is needed
        throw DownloadError.youtubeKitRequired
    }

    private func downloadFile(from url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DownloadError.downloadFailed("Server returned error")
        }

        // Move to a known location
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".webm")
        try FileManager.default.moveItem(at: tempURL, to: destURL)

        return destURL
    }

    private func downloadData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private func convertToMP3(input: URL, output: URL) async throws {
        // Use AVFoundation for conversion
        let asset = AVAsset(url: input)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw DownloadError.conversionFailed("Could not create export session")
        }

        // Export as M4A first (AVFoundation doesn't directly support MP3)
        let m4aOutput = output.deletingPathExtension().appendingPathExtension("m4a")
        exportSession.outputURL = m4aOutput
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status == .completed {
            // Rename to mp3 (or use FFmpegKit for proper conversion)
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: m4aOutput, to: output.deletingPathExtension().appendingPathExtension("m4a"))
        } else if let error = exportSession.error {
            throw DownloadError.conversionFailed(error.localizedDescription)
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name
            .components(separatedBy: invalidChars)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        progress = ""
    }
}

// MARK: - Errors

enum DownloadError: LocalizedError {
    case alreadyDownloading
    case invalidURL
    case youtubeKitRequired
    case downloadFailed(String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyDownloading:
            return "A download is already in progress"
        case .invalidURL:
            return "Invalid YouTube URL"
        case .youtubeKitRequired:
            return "YouTubeKit package required for audio extraction"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .conversionFailed(let msg):
            return "Conversion failed: \(msg)"
        }
    }
}
