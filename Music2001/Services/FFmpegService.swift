import Foundation
import AVFoundation

enum FFmpegError: Error, LocalizedError {
    case ffmpegNotFound
    case encodingFailed(String)
    case invalidInput
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg not found. Please install FFmpeg."
        case .encodingFailed(let message):
            return "Video encoding failed: \(message)"
        case .invalidInput:
            return "Invalid input files"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}

class FFmpegService: ObservableObject, @unchecked Sendable {
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    private var currentProcess: Process?
    private var isCancelled = false

    // FFmpeg paths
    private var bundledFFmpegPath: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin/ffmpeg")
    }

    private var systemFFmpegPath: URL? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private var ffmpegExecutable: URL? {
        if let bundled = bundledFFmpegPath,
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return systemFFmpegPath
    }

    /// Get audio duration using AVFoundation
    func getAudioDuration(url: URL) async -> TimeInterval? {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            return nil
        }
    }

    /// Create video from static image + audio
    func createVideo(
        image: URL,
        audio: URL,
        output: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        guard let ffmpeg = ffmpegExecutable else {
            throw FFmpegError.ffmpegNotFound
        }

        guard FileManager.default.fileExists(atPath: image.path),
              FileManager.default.fileExists(atPath: audio.path) else {
            throw FFmpegError.invalidInput
        }

        isCancelled = false
        isProcessing = true
        progress = 0
        statusMessage = "Starting video creation..."

        defer {
            isProcessing = false
            currentProcess = nil
        }

        // Get audio duration for progress calculation
        let audioDuration = await getAudioDuration(url: audio) ?? 180.0

        let process = Process()
        process.executableURL = ffmpeg

        // FFmpeg command: static image + audio -> video
        process.arguments = [
            "-y",                           // Overwrite output
            "-loop", "1",                   // Loop image
            "-i", image.path,               // Input image
            "-i", audio.path,               // Input audio
            "-c:v", "libx264",              // Video codec
            "-tune", "stillimage",          // Optimize for still image
            "-c:a", "aac",                  // Audio codec
            "-b:a", "192k",                 // Audio bitrate
            "-pix_fmt", "yuv420p",          // Pixel format for compatibility
            "-shortest",                    // Match audio duration
            "-movflags", "+faststart",      // Web optimization
            "-progress", "pipe:1",          // Output progress to stdout
            output.path
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        currentProcess = process

        return try await withCheckedThrowingContinuation { continuation in
            // Parse progress from stdout
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let output = String(data: data, encoding: .utf8) else { return }

                // Parse FFmpeg progress output
                // Format: out_time_ms=123456789
                for line in output.components(separatedBy: .newlines) {
                    if line.hasPrefix("out_time_ms="),
                       let msString = line.split(separator: "=").last,
                       let ms = Double(msString) {
                        let seconds = ms / 1_000_000
                        let progressValue = min(seconds / audioDuration, 1.0)

                        DispatchQueue.main.async {
                            self?.progress = progressValue
                            self?.statusMessage = "Creating video: \(Int(progressValue * 100))%"
                            progressHandler(progressValue, "Creating video...")
                        }
                    }
                }
            }

            process.terminationHandler = { [weak self] process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil

                if self?.isCancelled == true {
                    continuation.resume(throwing: FFmpegError.cancelled)
                    return
                }

                if process.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: FFmpegError.encodingFailed(errorMessage))
                    return
                }

                DispatchQueue.main.async {
                    self?.progress = 1.0
                    self?.statusMessage = "Complete"
                }
                continuation.resume()
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FFmpegError.encodingFailed(error.localizedDescription))
            }
        }
    }

    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        isProcessing = false
        statusMessage = "Cancelled"
    }
}
