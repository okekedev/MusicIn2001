import Foundation

enum PythonError: Error, LocalizedError {
    case pythonNotFound
    case scriptNotFound
    case executionFailed(String)
    case invalidOutput
    case cancelled

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python environment not found in app bundle"
        case .scriptNotFound:
            return "Python script not found"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .invalidOutput:
            return "Invalid output from Python script"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}

enum PythonCommand {
    case extractURL(url: String, outputDir: String)
    case extractFile(path: String, outputDir: String)

    var arguments: [String] {
        switch self {
        case .extractURL(let url, let outputDir):
            return ["extract_url", "--url", url, "--output", outputDir]
        case .extractFile(let path, let outputDir):
            return ["extract_file", "--file", path, "--output", outputDir]
        }
    }
}

@MainActor
class PythonBridge: ObservableObject {
    @Published var isRunning = false
    @Published var currentProgress: Double = 0
    @Published var statusMessage: String = ""

    private var currentProcess: Process?
    nonisolated(unsafe) private var isCancelled = false

    // Paths to bundled Python
    private var pythonResourcesPath: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Python")
    }

    private var pythonExecutable: URL? {
        pythonResourcesPath?.appendingPathComponent("venv/bin/python3")
    }

    private var mixorScript: URL? {
        pythonResourcesPath?.appendingPathComponent("mixor_cli.py")
    }

    // For development: use system Python if bundled not available
    private var developmentPythonPath: URL? {
        // Check common locations - prefer Python 3.11+ for latest yt-dlp
        let paths = [
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func execute(
        command: PythonCommand,
        progressHandler: @escaping (ProgressUpdate) -> Void
    ) async throws -> ProcessingJob.JobResult {
        guard !isRunning else {
            throw PythonError.executionFailed("Already processing")
        }

        isCancelled = false
        isRunning = true
        currentProgress = 0
        statusMessage = "Starting..."

        defer {
            isRunning = false
            currentProcess = nil
        }

        // Determine Python executable
        let pythonPath: URL
        let scriptPath: URL

        // Always use system Python 3.11 for development (has yt-dlp installed)
        guard let devPython = developmentPythonPath else {
            throw PythonError.pythonNotFound
        }
        pythonPath = devPython

        // Use the script from project directory
        let projectScript = URL(fileURLWithPath: "/Users/christian/Desktop/mixor/Python/mixor_cli.py")
        if FileManager.default.fileExists(atPath: projectScript.path) {
            scriptPath = projectScript
        } else if let bundledScript = mixorScript,
                  FileManager.default.fileExists(atPath: bundledScript.path) {
            scriptPath = bundledScript
        } else {
            throw PythonError.scriptNotFound
        }

        let process = Process()
        process.executableURL = pythonPath
        process.arguments = [scriptPath.path] + command.arguments

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        if let resourcesPath = pythonResourcesPath {
            let venvPath = resourcesPath.appendingPathComponent("venv")
            env["VIRTUAL_ENV"] = venvPath.path
            env["PATH"] = venvPath.appendingPathComponent("bin").path + ":" + (env["PATH"] ?? "")
        }
        // Add homebrew paths for node, ffmpeg, etc.
        let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = homebrewPaths + ":" + (env["PATH"] ?? "")
        env["PYTHONIOENCODING"] = "utf-8"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        currentProcess = process

        // Use a class to safely capture mutable state (Swift 6 compatibility)
        final class OutputState: @unchecked Sendable {
            var outputData = Data()
            var lastResult: ProcessingJob.JobResult?
            private let lock = NSLock()

            func appendData(_ data: Data) {
                lock.lock()
                outputData.append(data)
                lock.unlock()
            }

            func setResult(_ result: ProcessingJob.JobResult) {
                lock.lock()
                lastResult = result
                lock.unlock()
            }

            func getResult() -> ProcessingJob.JobResult? {
                lock.lock()
                defer { lock.unlock() }
                return lastResult
            }

            func getData() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return outputData
            }
        }

        let state = OutputState()

        return try await withCheckedThrowingContinuation { continuation in
            // Read stdout for progress updates
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                state.appendData(data)

                // Try to parse each line as JSON
                if let output = String(data: data, encoding: .utf8) {
                    for line in output.components(separatedBy: .newlines) where !line.isEmpty {
                        if let lineData = line.data(using: .utf8) {
                            // Try as progress update
                            if let progress = try? JSONDecoder().decode(ProgressUpdate.self, from: lineData) {
                                DispatchQueue.main.async {
                                    self?.currentProgress = progress.progress
                                    self?.statusMessage = progress.status
                                    progressHandler(progress)
                                }
                            }
                            // Try as final result
                            else if let result = try? JSONDecoder().decode(ProcessingJob.JobResult.self, from: lineData) {
                                state.setResult(result)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { [weak self] process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil

                // Check if cancelled
                if self?.isCancelled == true {
                    continuation.resume(throwing: PythonError.cancelled)
                    return
                }

                // Check exit status
                if process.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: PythonError.executionFailed(errorMessage))
                    return
                }

                // Return result
                if let result = state.getResult() {
                    continuation.resume(returning: result)
                } else {
                    // Try to parse any remaining output
                    if let result = try? JSONDecoder().decode(ProcessingJob.JobResult.self, from: state.getData()) {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: PythonError.invalidOutput)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: PythonError.executionFailed(error.localizedDescription))
            }
        }
    }

    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        isRunning = false
        statusMessage = "Cancelled"
    }
}
