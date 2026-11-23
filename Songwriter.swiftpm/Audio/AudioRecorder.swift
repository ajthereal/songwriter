import AVFoundation

extension NSLocking {
    func sync<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

func hostNowSeconds() -> Double {
    AVAudioTime.seconds(forHostTime: mach_absolute_time())
}

struct RecordedAudio {
    var fileName: String
    var url: URL
    /// Host time (seconds) of the first sample in the file.
    var firstSampleHost: Double
    var frames: Int64
    var sampleRate: Double
    var durationSeconds: Double { sampleRate > 0 ? Double(frames) / sampleRate : 0 }
}

/// Taps the input node, tracks the input level and writes 48 kHz mono float32 CAF files off the audio thread.
final class AudioRecorder {
    static let fileSampleRate: Double = 48000

    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "com.ajthereal.songwriter.writer", qos: .userInitiated)
    private var writing = false
    private var levelValue: Float = 0
    private var levelTime: Double = 0
    private(set) var tapInstalled = false

    // Write-queue confined.
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var firstHost: Double?
    private var framesWritten: Int64 = 0
    private var writeFailure: String?
    private var converters: [Double: AVAudioConverter] = [:]
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.fileSampleRate,
                                          channels: 1, interleaved: false)

    /// Current input peak (0...1) with a gentle decay, safe to read from any thread.
    var level: Float {
        lock.sync {
            let age = Float(max(0, hostNowSeconds() - levelTime))
            return max(0, levelValue - age * 1.5)
        }
    }

    func installTap(on input: AVAudioInputNode) {
        if tapInstalled { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, when in
            self?.handle(buffer, when)
        }
        tapInstalled = true
    }

    func markTapRemoved() {
        tapInstalled = false
    }

    func removeTap(from input: AVAudioInputNode) {
        if tapInstalled { input.removeTap(onBus: 0) }
        tapInstalled = false
        lock.sync { levelValue = 0 }
    }

    private func handle(_ buffer: AVAudioPCMBuffer, _ when: AVAudioTime) {
        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if n == 0 || channels == 0 { return }
        var mono = [Float](repeating: 0, count: n)
        var peak: Float = 0
        if channels == 1 {
            for i in 0..<n {
                let v = data[0][i]
                mono[i] = v
                peak = max(peak, abs(v))
            }
        } else {
            let scale = 1.0 / Float(channels)
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channels { sum += data[c][i] }
                let v = sum * scale
                mono[i] = v
                peak = max(peak, abs(v))
            }
        }
        let now = hostNowSeconds()
        let isWriting: Bool = lock.sync {
            if peak >= levelValue - Float(max(0, now - levelTime)) * 1.5 {
                levelValue = peak
                levelTime = now
            }
            return writing
        }
        guard isWriting else { return }
        let host = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : now
        let rate = buffer.format.sampleRate
        writeQueue.async { [weak self] in
            self?.write(mono, rate: rate, host: host)
        }
    }

    // MARK: Writing (write queue)

    private func write(_ samples: [Float], rate: Double, host: Double) {
        guard let file = file, let outFormat = outFormat else { return }
        if firstHost == nil { firstHost = host }
        do {
            if abs(rate - AudioRecorder.fileSampleRate) < 0.5 {
                guard let buf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                      let ch = buf.floatChannelData else { return }
                for i in 0..<samples.count { ch[0][i] = samples[i] }
                buf.frameLength = AVAudioFrameCount(samples.count)
                try file.write(from: buf)
                framesWritten += Int64(samples.count)
            } else {
                guard let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else { return }
                if converters[rate] == nil { converters[rate] = AVAudioConverter(from: inFormat, to: outFormat) }
                guard let converter = converters[rate],
                      let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                      let inCh = inBuf.floatChannelData else { return }
                for i in 0..<samples.count { inCh[0][i] = samples[i] }
                inBuf.frameLength = AVAudioFrameCount(samples.count)
                let capacity = AVAudioFrameCount(Double(samples.count) * AudioRecorder.fileSampleRate / rate) + 64
                guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
                var supplied = false
                var convError: NSError?
                let status = converter.convert(to: outBuf, error: &convError) { _, outStatus in
                    if supplied {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    supplied = true
                    outStatus.pointee = .haveData
                    return inBuf
                }
                if status == .error {
                    writeFailure = convError?.localizedDescription ?? "sample rate conversion failed"
                    return
                }
                if outBuf.frameLength > 0 {
                    try file.write(from: outBuf)
                    framesWritten += Int64(outBuf.frameLength)
                }
            }
        } catch {
            writeFailure = ErrorCenter.describe(error)
        }
    }

    func beginWriting(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioRecorder.fileSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        writeQueue.sync {
            self.file = f
            self.fileURL = url
            self.firstHost = nil
            self.framesWritten = 0
            self.writeFailure = nil
        }
        lock.sync { writing = true }
    }

    /// Stops writing, closes the file and returns what was recorded (on the main thread).
    func endWriting(completion: @escaping (RecordedAudio?, String?) -> Void) {
        lock.sync { writing = false }
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            let url = self.fileURL
            let first = self.firstHost
            let frames = self.framesWritten
            let failure = self.writeFailure
            self.file = nil          // closes the file
            self.fileURL = nil
            var result: RecordedAudio? = nil
            if let url = url, let first = first, frames > 0 {
                result = RecordedAudio(fileName: url.lastPathComponent, url: url, firstSampleHost: first,
                                       frames: frames, sampleRate: AudioRecorder.fileSampleRate)
            }
            DispatchQueue.main.async { completion(result, failure) }
        }
    }
}
