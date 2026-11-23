import SwiftUI
import AVFoundation

/// Computes and caches waveform peaks (one value per 10 ms) for recorded takes, off the main thread.
final class WaveformStore: ObservableObject {
    static let shared = WaveformStore()
    static let bucketSeconds: Double = 0.01

    @Published var version = 0
    private var cache: [String: [Float]] = [:]
    private var loading = Set<String>()
    private let queue = DispatchQueue(label: "com.ajthereal.songwriter.waveforms", qos: .utility)

    func peaks(dir: URL, fileName: String) -> [Float]? {
        let key = dir.path + "/" + fileName
        if let p = cache[key] { return p }
        if loading.contains(key) { return nil }
        loading.insert(key)
        let url = dir.appendingPathComponent(fileName)
        queue.async {
            var result: [Float] = []
            do {
                let file = try AVAudioFile(forReading: url)
                let sr = file.processingFormat.sampleRate
                let bucket = max(1, Int(sr * WaveformStore.bucketSeconds))
                let chunk = 16384
                guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)) else { throw AppMessage("buffer") }
                var current: Float = 0
                var inBucket = 0
                while file.framePosition < file.length {
                    try file.read(into: buf, frameCount: AVAudioFrameCount(chunk))
                    let n = Int(buf.frameLength)
                    if n == 0 { break }
                    guard let ch = buf.floatChannelData else { break }
                    for i in 0..<n {
                        current = max(current, abs(ch[0][i]))
                        inBucket += 1
                        if inBucket >= bucket {
                            result.append(current)
                            current = 0
                            inBucket = 0
                        }
                    }
                }
                if inBucket > 0 { result.append(current) }
            } catch {
                // A missing file is reported when playing; the region simply shows no waveform.
            }
            DispatchQueue.main.async {
                self.cache[key] = result
                self.loading.remove(key)
                self.version += 1
            }
        }
        return nil
    }
}
