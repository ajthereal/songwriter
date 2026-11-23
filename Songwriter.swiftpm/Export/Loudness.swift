import Foundation

/// ITU-R BS.1770-4 loudness measurement and a simple true-peak-safe limiter.
enum Loudness {
    struct Biquad {
        var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var z1: Double = 0
        var z2: Double = 0

        init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
            self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    /// The two K-weighting stages for a sample rate.
    static func kWeighting(sampleRate fs: Double) -> (shelf: Biquad, highpass: Biquad) {
        // Stage 1: high shelf
        var f0 = 1681.974450955533
        let g = 3.999843853973347
        var q = 0.7071752369554196
        var k = tan(Double.pi * f0 / fs)
        let vh = pow(10.0, g / 20.0)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1.0 + k / q + k * k
        let shelf = Biquad(b0: (vh + vb * k / q + k * k) / a0,
                           b1: 2.0 * (k * k - vh) / a0,
                           b2: (vh - vb * k / q + k * k) / a0,
                           a1: 2.0 * (k * k - 1.0) / a0,
                           a2: (1.0 - k / q + k * k) / a0)
        // Stage 2: RLB high pass
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(Double.pi * f0 / fs)
        a0 = 1.0 + k / q + k * k
        let hp = Biquad(b0: 1.0, b1: -2.0, b2: 1.0,
                        a1: 2.0 * (k * k - 1.0) / a0,
                        a2: (1.0 - k / q + k * k) / a0)
        return (shelf, hp)
    }

    /// Integrated loudness in LUFS (nil when the signal is too short or entirely below the absolute gate).
    static func integratedLUFS(channels: [[Float]], sampleRate: Double) -> Double? {
        guard !channels.isEmpty, let frames = channels.first?.count, frames > 0 else { return nil }
        let hop = Int((sampleRate * 0.1).rounded())
        let blockChunks = 4
        guard hop > 0, frames >= hop * blockChunks else { return nil }
        let chunkCount = frames / hop

        // Sum of squares per 100 ms chunk, summed over channels (all channel weights are 1.0).
        var chunkEnergy = [Double](repeating: 0, count: chunkCount)
        for ch in channels {
            guard ch.count >= chunkCount * hop else { return nil }
            var filters = kWeighting(sampleRate: sampleRate)
            for c in 0..<chunkCount {
                var sum = 0.0
                let base = c * hop
                for i in 0..<hop {
                    let x = Double(ch[base + i])
                    let y = filters.highpass.process(filters.shelf.process(x))
                    sum += y * y
                }
                chunkEnergy[c] += sum
            }
        }

        let blockLen = Double(hop * blockChunks)
        var blocks: [Double] = []   // mean square (summed over channels) per 400 ms block, 75% overlap
        if chunkCount >= blockChunks {
            for start in 0...(chunkCount - blockChunks) {
                var e = 0.0
                for k in 0..<blockChunks { e += chunkEnergy[start + k] }
                blocks.append(e / blockLen)
            }
        }
        func lufs(_ z: Double) -> Double { -0.691 + 10.0 * log10(max(z, 1e-20)) }

        let absGated = blocks.filter { lufs($0) > -70.0 }
        guard !absGated.isEmpty else { return nil }
        let meanAbs = absGated.reduce(0, +) / Double(absGated.count)
        let relThreshold = lufs(meanAbs) - 10.0
        let relGated = absGated.filter { lufs($0) >= relThreshold }
        guard !relGated.isEmpty else { return nil }
        let mean = relGated.reduce(0, +) / Double(relGated.count)
        return lufs(mean)
    }

    static func dB(fromLinear x: Double) -> Double { 20.0 * log10(max(x, 1e-12)) }
    static func linear(fromDB db: Double) -> Double { pow(10.0, db / 20.0) }

    /// Catmull-Rom interpolation value between p1 and p2 at t in 0...1.
    @inline(__always)
    private static func cubic(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float, _ t: Float) -> Float {
        let a = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3
        let b = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3
        let c = -0.5 * p0 + 0.5 * p2
        return ((a * t + b) * t + c) * t + p1
    }

    /// Estimated true peak (linear) using 4x oversampling.
    static func truePeak(_ x: [Float]) -> Float {
        let n = x.count
        if n == 0 { return 0 }
        var peak: Float = 0
        for i in 0..<n {
            peak = max(peak, abs(x[i]))
            if i + 1 < n {
                let p0 = i > 0 ? x[i - 1] : x[i]
                let p3 = i + 2 < n ? x[i + 2] : x[i + 1]
                for t in [Float(0.25), 0.5, 0.75] {
                    peak = max(peak, abs(cubic(p0, x[i], x[i + 1], p3, t)))
                }
            }
        }
        return peak
    }

    static func truePeak(channels: [[Float]]) -> Float {
        var p: Float = 0
        for c in channels { p = max(p, truePeak(c)) }
        return p
    }

    static func samplePeak(channels: [[Float]]) -> Float {
        var p: Float = 0
        for c in channels { for s in c { p = max(p, abs(s)) } }
        return p
    }

    /// Offline look-ahead limiter. Brings the estimated true peak down to `ceilingDB` (dBFS).
    static func limit(channels: inout [[Float]], ceilingDB: Double, sampleRate: Double) {
        guard let n = channels.first?.count, n > 0 else { return }
        let ceil = Float(linear(fromDB: ceilingDB))
        let w = max(2, Int(sampleRate * 0.005))

        // Required gain per sample, from sample and inter-sample peaks.
        var required = [Float](repeating: 1, count: n)
        var needsLimiting = false
        for ch in channels {
            for i in 0..<n {
                var p = abs(ch[i])
                if i + 1 < n {
                    let p0 = i > 0 ? ch[i - 1] : ch[i]
                    let p3 = i + 2 < n ? ch[i + 2] : ch[i + 1]
                    for t in [Float(0.25), 0.5, 0.75] {
                        p = max(p, abs(cubic(p0, ch[i], ch[i + 1], p3, t)))
                    }
                }
                if p > ceil {
                    needsLimiting = true
                    required[i] = min(required[i], ceil / p)
                }
            }
        }
        if needsLimiting {
            // Sliding window minimum over w samples with padding of ones, then a box filter of w samples.
            let padded = [Float](repeating: 1, count: w - 1) + required + [Float](repeating: 1, count: w - 1)
            let m = n + w - 1
            var mins = [Float](repeating: 1, count: m)
            let cap = w + 1
            var dq = [Int](repeating: 0, count: cap)
            var head = 0
            var size = 0
            for i in 0..<padded.count {
                let v = padded[i]
                while size > 0 {
                    let backIdx = dq[(head + size - 1) % cap]
                    if padded[backIdx] >= v { size -= 1 } else { break }
                }
                dq[(head + size) % cap] = i
                size += 1
                if dq[head] <= i - w {
                    head = (head + 1) % cap
                    size -= 1
                }
                if i >= w - 1 { mins[i - (w - 1)] = padded[dq[head]] }
            }
            var gain = [Float](repeating: 1, count: n)
            var running: Double = 0
            for j in 0..<min(w, m) { running += Double(mins[j]) }
            for i in 0..<n {
                gain[i] = Float(running / Double(w))
                let drop = i
                let add = i + w
                running -= Double(mins[drop])
                if add < m { running += Double(mins[add]) }
            }
            for c in 0..<channels.count {
                for i in 0..<n { channels[c][i] *= gain[i] }
            }
        }
        // Final guard against any residual overshoot.
        let tp = truePeak(channels: channels)
        if tp > ceil {
            let scale = ceil / tp
            for c in 0..<channels.count {
                for i in 0..<n { channels[c][i] *= scale }
            }
        }
    }
}
