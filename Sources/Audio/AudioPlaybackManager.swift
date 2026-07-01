import AVFoundation

/// Plays Int16 PCM audio received from /WSaudioRX using AVAudioPlayerNode.
/// The engine handles sample rate conversion (16kHz → hardware rate) automatically.
final class AudioPlaybackManager: NSObject, ObservableObject, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let ioQueue = DispatchQueue(label: "audio.playback", qos: .userInitiated)

    private let sourceSampleRate: Double = 48000  // matches server RX_OUT_RATE
    private var playbackFormat: AVAudioFormat!

    private(set) var isStarted = false

    // ── Observable state ──────────────────────────────────────
    @Published var isMuted: Bool = false {
        didSet { playerNode.volume = isMuted ? 0 : 1 }
    }
    @Published var rmsLevel: Float = 0.0
    @Published var audioError: String?

    // ── Recording ─────────────────────────────────────────────
    @Published var isRecording: Bool = false
    private var recordBuffer: [Float] = []
    private let recordLock = NSLock()

    func startRecording() {
        recordLock.lock(); recordBuffer.removeAll(keepingCapacity: true); recordLock.unlock()
        isRecording = true
    }

    func stopRecording() -> Data? {
        isRecording = false
        recordLock.lock(); let samples = recordBuffer; recordLock.unlock()
        guard !samples.isEmpty else { return nil }
        return makeWAV(samples: samples)
    }

    var recordingDuration: TimeInterval {
        recordLock.lock(); let c = recordBuffer.count; recordLock.unlock()
        return TimeInterval(c) / sourceSampleRate
    }

    // ── Start / Stop ─────────────────────────────────────────

    func start() {
        guard !isStarted else { return }
        isStarted = true

        playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                        sampleRate: sourceSampleRate,
                                        channels: 1,
                                        interleaved: false)!

        configureSession()

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
        playerNode.volume = isMuted ? 0 : 1

        do {
            try engine.start()
            playerNode.play()
            print("🔊 Audio playback started @ \(sourceSampleRate) Hz (player node)")
        } catch {
            audioError = "Engine start: \(error.localizedDescription)"
            print("⚠️ \(audioError!)")
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        playerNode.stop()
        engine.stop()
        engine.reset()
        print("🔇 Audio playback stopped")
    }

    // MARK: - Enqueue PCM data

    /// Frame format: 1-byte codec tag (0x00=PCM, 0x01=Opus) + payload.
    func enqueue(int16Data: Data) {
        guard isStarted, int16Data.count >= 3 else { return }
        let codec = int16Data[0]
        if codec == 0x01 { return }  // Opus, skip

        let pcmBytes = int16Data.dropFirst()
        let byteCount = pcmBytes.count
        let sampleCount = byteCount / 2
        guard sampleCount > 0 else { return }

        // Convert Int16 LE → Float32
        var samples = [Float](repeating: 0, count: sampleCount)
        pcmBytes.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<sampleCount {
                let lo = UInt16(bytes[i * 2])
                let hi = UInt16(bytes[i * 2 + 1])
                let val = Int16(bitPattern: lo | (hi << 8))
                samples[i] = Float(val) / 32768.0
            }
        }

        // Recording
        if isRecording {
            recordLock.lock()
            recordBuffer.append(contentsOf: samples)
            recordLock.unlock()
        }

        // RMS
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = sqrt(sum / Float(sampleCount))
        DispatchQueue.main.async { [weak self] in self?.rmsLevel = rms }

        // Schedule buffer on player node
        guard let fmt = playbackFormat,
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(sampleCount))
        else { return }

        buf.frameLength = AVAudioFrameCount(sampleCount)
        if let dst = buf.floatChannelData?.pointee {
            dst.initialize(from: samples, count: sampleCount)
        }

        ioQueue.async { [weak self] in
            self?.playerNode.scheduleBuffer(buf)
        }
    }

    // MARK: - Private

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default,
                                    options: [.mixWithOthers, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("⚠️ AudioSession: \(error)")
        }
    }

    // MARK: - WAV export

    private func makeWAV(samples: [Float]) -> Data {
        let sr = UInt32(sourceSampleRate)
        let ch: UInt16 = 1, bps: UInt16 = 16
        let dataSize = UInt32(samples.count * 2)
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: ch.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sr.littleEndian) { Data($0) })
        let byteRate = sr * UInt32(ch) * UInt32(bps / 8)
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign = ch * (bps / 8)
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bps.littleEndian) { Data($0) })
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * 32767)
            data.append(withUnsafeBytes(of: v.littleEndian) { Data($0) })
        }
        return data
    }
}
