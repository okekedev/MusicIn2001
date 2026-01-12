import Foundation
import AVFoundation

/// EQ settings for 5-band parametric EQ
public struct EQSettings: Equatable {
    public var sub: Double      // 80Hz - Sub/Bass
    public var low: Double      // 350Hz - Low-Mid
    public var mid: Double      // 1kHz - Mid
    public var highMid: Double  // 3.5kHz - High-Mid
    public var high: Double     // 10kHz - High/Treble

    public init(
        sub: Double = 0,
        low: Double = 0,
        mid: Double = 0,
        highMid: Double = 0,
        high: Double = 0
    ) {
        self.sub = sub
        self.low = low
        self.mid = mid
        self.highMid = highMid
        self.high = high
    }

    /// Flat EQ (no boost/cut)
    public static let flat = EQSettings()
}

/// Audio playback engine with EQ, delay, and reverb
public class AudioEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()

    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?
    private(set) public var duration: TimeInterval = 0
    private var startFrame: AVAudioFramePosition = 0
    private var pausedTime: TimeInterval = 0
    private var _isPlaying = false

    /// Whether the engine is currently playing
    public var isPlaying: Bool { _isPlaying }

    /// Current playback position in seconds
    public var currentTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let file = audioFile else {
            return pausedTime
        }

        let sampleRate = file.processingFormat.sampleRate
        let currentFrame = startFrame + playerTime.sampleTime
        return Double(currentFrame) / sampleRate
    }

    /// Detected BPM (estimated)
    public var detectedBPM: Double {
        detectBPM()
    }

    /// Initialize with a file URL
    public init?(url: URL) {
        do {
            audioFile = try AVAudioFile(forReading: url)
            guard let file = audioFile else { return nil }

            duration = Double(file.length) / file.processingFormat.sampleRate

            // Load audio into buffer
            audioBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
            guard let buffer = audioBuffer else { return nil }
            try file.read(into: buffer)

            setupAudioChain()
            configureEQ()

        } catch {
            print("Failed to initialize audio engine: \(error)")
            return nil
        }
    }

    private func setupAudioChain() {
        // Attach nodes
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(eq)
        engine.attach(delay)
        engine.attach(reverb)

        guard let file = audioFile else { return }
        let format = file.processingFormat

        // Connect: player -> timePitch -> EQ -> delay -> reverb -> output
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        // Configure effects defaults
        delay.delayTime = 0.08
        delay.feedback = 10
        delay.lowPassCutoff = 10000
        delay.wetDryMix = 0

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0

        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func configureEQ() {
        // 5-band DJ EQ - industry standard frequencies
        let bands = eq.bands

        // Sub/Bass - low shelf at 80Hz (kick drums, sub bass)
        bands[0].filterType = .lowShelf
        bands[0].frequency = 80
        bands[0].gain = 0
        bands[0].bypass = false

        // Low-Mid - 350Hz (bass guitar, warmth, muddiness control)
        bands[1].filterType = .parametric
        bands[1].frequency = 350
        bands[1].bandwidth = 2.0  // ~1.5 octaves, musical width
        bands[1].gain = 0
        bands[1].bypass = false

        // Mid - 1kHz (vocals, snare, primary instrument body)
        bands[2].filterType = .parametric
        bands[2].frequency = 1000
        bands[2].bandwidth = 2.0
        bands[2].gain = 0
        bands[2].bypass = false

        // High-Mid - 3.5kHz (presence, vocal clarity, hi-hats)
        bands[3].filterType = .parametric
        bands[3].frequency = 3500
        bands[3].bandwidth = 2.0
        bands[3].gain = 0
        bands[3].bypass = false

        // High/Treble - high shelf at 10kHz (air, sparkle, cymbals)
        bands[4].filterType = .highShelf
        bands[4].frequency = 10000
        bands[4].gain = 0
        bands[4].bypass = false
    }

    private func detectBPM() -> Double {
        guard let buffer = audioBuffer else { return 120 }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData?[0] else { return 120 }

        let sampleRate = buffer.format.sampleRate
        let windowSize = Int(sampleRate * 0.02) // 20ms windows
        let hopSize = windowSize / 2

        var energies: [Float] = []

        // Calculate energy for each window
        var i = 0
        while i + windowSize < frameCount {
            var energy: Float = 0
            for j in 0..<windowSize {
                let sample = channelData[i + j]
                energy += sample * sample
            }
            energies.append(energy / Float(windowSize))
            i += hopSize
        }

        guard energies.count > 10 else { return 120 }

        // Find peaks (beats) by comparing to local average
        var peakIndices: [Int] = []
        let threshold: Float = 1.5

        for i in 2..<(energies.count - 2) {
            let localAvg = (energies[i-2] + energies[i-1] + energies[i+1] + energies[i+2]) / 4
            if energies[i] > localAvg * threshold && energies[i] > energies[i-1] && energies[i] > energies[i+1] {
                peakIndices.append(i)
            }
        }

        guard peakIndices.count > 2 else { return 120 }

        // Calculate average interval between peaks
        var intervals: [Double] = []
        for i in 1..<peakIndices.count {
            let interval = Double(peakIndices[i] - peakIndices[i-1]) * Double(hopSize) / sampleRate
            if interval > 0.2 && interval < 2.0 {
                intervals.append(interval)
            }
        }

        guard !intervals.isEmpty else { return 120 }

        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        var bpm = 60.0 / avgInterval

        // Normalize BPM to common range (80-160)
        while bpm < 80 { bpm *= 2 }
        while bpm > 160 { bpm /= 2 }

        return round(bpm)
    }

    // MARK: - Playback Control

    /// Start or resume playback
    public func play() {
        guard let buffer = audioBuffer, let file = audioFile else { return }

        if !_isPlaying {
            let sampleRate = buffer.format.sampleRate

            // Clamp pausedTime to valid range
            let clampedPausedTime = max(0, min(pausedTime, duration - 0.1))
            startFrame = AVAudioFramePosition(clampedPausedTime * sampleRate)

            // Ensure startFrame is within bounds
            let maxFrame = AVAudioFramePosition(buffer.frameLength)
            if startFrame >= maxFrame {
                startFrame = 0
                pausedTime = 0
            }

            // Create a segment of the buffer from the current position
            let remainingFrames = AVAudioFrameCount(maxFrame - startFrame)
            guard remainingFrames > 0 else { return }

            playerNode.stop()

            // Seek to the correct position
            if startFrame > 0 {
                playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: remainingFrames, at: nil)
            } else {
                playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            }

            playerNode.play()
            _isPlaying = true
        }
    }

    /// Pause playback
    public func pause() {
        if _isPlaying {
            pausedTime = currentTime
            playerNode.pause()
            _isPlaying = false
        }
    }

    /// Stop playback and reset to beginning
    public func stop() {
        playerNode.stop()
        pausedTime = 0
        startFrame = 0
        _isPlaying = false
    }

    /// Seek to a specific time
    public func seek(to time: TimeInterval) {
        let wasPlaying = _isPlaying
        playerNode.stop()
        pausedTime = max(0, min(time, max(0, duration - 0.5)))
        startFrame = 0
        _isPlaying = false

        if wasPlaying {
            play()
        }
    }

    // MARK: - Volume & Effects

    /// Set output volume (0.0 - 1.0)
    public func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1.1, volume))
    }

    /// Set playback rate (0.5 - 2.0)
    public func setRate(_ rate: Float) {
        timePitch.rate = max(0.5, min(2.0, rate))
    }

    /// Set EQ settings
    public func setEQ(_ settings: EQSettings) {
        eq.bands[0].gain = Float(settings.sub)
        eq.bands[1].gain = Float(settings.low)
        eq.bands[2].gain = Float(settings.mid)
        eq.bands[3].gain = Float(settings.highMid)
        eq.bands[4].gain = Float(settings.high)
    }

    /// Set EQ band values directly
    public func setEQ(sub: Double, low: Double, mid: Double, highMid: Double, high: Double) {
        eq.bands[0].gain = Float(sub)
        eq.bands[1].gain = Float(low)
        eq.bands[2].gain = Float(mid)
        eq.bands[3].gain = Float(highMid)
        eq.bands[4].gain = Float(high)
    }

    /// Set delay wet/dry mix (0.0 - 1.0)
    public func setDelayMix(_ mix: Double) {
        delay.wetDryMix = Float(mix * 100)
    }

    /// Set reverb wet/dry mix (0.0 - 1.0)
    public func setReverbMix(_ mix: Double) {
        reverb.wetDryMix = Float(mix * 100)
    }
}
