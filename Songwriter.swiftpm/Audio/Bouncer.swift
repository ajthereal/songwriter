import AVFoundation
import AudioToolbox

struct BounceReport {
    var lufsBefore: Double
    var lufsAfter: Double
    var truePeakDB: Double
    var gainDB: Double
    var seconds: Double
}

struct RenderedAudio {
    var channels: [[Float]]
    var sampleRate: Double
    var frames: Int { channels.first?.count ?? 0 }
}

/// Offline rendering (manual rendering mode on a separate engine), loudness normalisation and file writing.
enum Bouncer {
    static let sampleRate: Double = 48000
    static let targetLUFS: Double = -14.0
    static let ceilingDB: Double = -1.0

    private struct OfflineEvent {
        var frame: Int
        var order: UInt8
        var pitch: UInt8
        var vel: UInt8
        var sampler: AVAudioUnitSampler?
    }

    /// Renders the song (or a single track for stems) to stereo float arrays without touching the live engine.
    static func render(song songIn: Song, audioDir: URL, only trackID: UUID?,
                       progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> RenderedAudio {
        var song = songIn
        if trackID != nil {
            song.tracks = song.tracks.map { t in
                var c = t
                c.muted = false
                c.solo = false
                return c
            }
        }
        let sr = sampleRate
        let spb = song.secondsPerBeat
        let songSeconds = song.lengthBeats * spb
        let hasReverb = song.tracks.contains { $0.kind == .audio && $0.vocalChain && $0.reverbAmount > 0 }
        let tail = hasReverb ? 3.5 : 1.5
        let totalFrames = Int((songSeconds + tail) * sr)
        guard totalFrames > 0 else { throw AppMessage("The song is empty, so there is nothing to render.") }

        let engine = AVAudioEngine()
        let graph = AudioGraph(engine: engine, sampleRate: sr)
        graph.soundFontURL = ResourceLocator.soundFontURL
        let renderFormat = graph.stereo
        try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)
        graph.configure(song: song, only: trackID)
        for issue in graph.takeIssues() { ErrorCenter.post(issue, warning: true) }

        // Audio tracks: compose each track's regions into one buffer scheduled at sample zero.
        var audioBuffers: [(AVAudioPlayerNode, AVAudioPCMBuffer)] = []
        for t in song.tracks where t.kind == .audio && (trackID == nil || t.id == trackID) {
            guard AudioGraph.isAudible(t, in: song), let player = graph.player(for: t.id) else { continue }
            var samples = [Float](repeating: 0, count: totalFrames)
            var any = false
            for r in t.regions where r.kind == .audio {
                guard let take = r.activeTakeValue else { continue }
                let url = audioDir.appendingPathComponent(take.fileName)
                let file: AVAudioFile
                do {
                    file = try AVAudioFile(forReading: url)
                } catch {
                    ErrorCenter.post("The take \(take.fileName) could not be read, so it is missing from the bounce. \(ErrorCenter.describe(error))")
                    continue
                }
                let fsr = file.processingFormat.sampleRate
                if abs(fsr - sr) > 0.5 {
                    ErrorCenter.post("The take \(take.fileName) has an unsupported sample rate and is missing from the bounce.")
                    continue
                }
                let startInFile = AVAudioFramePosition(((take.offset + r.audioOffset) * fsr).rounded())
                let regionFrames = Int((r.lengthBeats * spb * sr).rounded())
                let placeAt = Int((r.startBeat * spb * sr).rounded())
                var readStart = startInFile
                var dest = placeAt
                var count = regionFrames
                if readStart < 0 {
                    dest += Int(-readStart)
                    count += Int(readStart)
                    readStart = 0
                }
                count = min(count, Int(max(0, file.length - readStart)), totalFrames - dest)
                if count <= 0 || dest < 0 { continue }
                guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) else { continue }
                file.framePosition = readStart
                try file.read(into: buf, frameCount: AVAudioFrameCount(count))
                guard let ch = buf.floatChannelData else { continue }
                let n = Int(buf.frameLength)
                for i in 0..<n { samples[dest + i] += ch[0][i] }
                any = true
            }
            if any, let pcm = AVAudioPCMBuffer(pcmFormat: graph.mono, frameCapacity: AVAudioFrameCount(totalFrames)),
               let ch = pcm.floatChannelData {
                for i in 0..<totalFrames { ch[0][i] = samples[i] }
                pcm.frameLength = AVAudioFrameCount(totalFrames)
                audioBuffers.append((player, pcm))
            }
        }

        // MIDI events.
        var events: [OfflineEvent] = []
        for t in song.tracks where t.kind == .instrument && (trackID == nil || t.id == trackID) {
            guard AudioGraph.isAudible(t, in: song), let sampler = graph.sampler(for: t.id) else { continue }
            for n in song.playbackNotes(for: t) {
                let on = Int((n.start * spb * sr).rounded())
                let off = max(on + 1, Int(((n.start + n.length) * spb * sr).rounded()))
                let p = UInt8(max(0, min(127, n.pitch)))
                let v = UInt8(max(1, min(127, n.velocity)))
                events.append(OfflineEvent(frame: on, order: 3, pitch: p, vel: v, sampler: sampler))
                events.append(OfflineEvent(frame: off, order: 0, pitch: p, vel: 0, sampler: sampler))
            }
            for pe in song.playbackPedal(for: t) {
                let f = Int((pe.beat * spb * sr).rounded())
                events.append(OfflineEvent(frame: f, order: pe.down ? 2 : 1, pitch: 0, vel: 0, sampler: sampler))
            }
        }
        events.sort { a, b in
            if a.frame != b.frame { return a.frame < b.frame }
            return a.order < b.order
        }

        engine.prepare()
        try engine.start()
        for (player, buf) in audioBuffers {
            player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
            player.play()
        }

        let block = 128
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: AVAudioFrameCount(block)) else {
            throw AppMessage("Could not allocate the render buffer.")
        }
        var left = [Float](repeating: 0, count: totalFrames)
        var right = [Float](repeating: 0, count: totalFrames)
        var frame = 0
        var idx = 0
        var stalls = 0
        var lastReport = 0
        while frame < totalFrames {
            if isCancelled() {
                engine.stop()
                throw AppMessage("The bounce was cancelled.")
            }
            while idx < events.count && events[idx].frame < frame + block {
                let e = events[idx]
                switch e.order {
                case 3: e.sampler?.startNote(e.pitch, withVelocity: e.vel, onChannel: 0)
                case 0: e.sampler?.stopNote(e.pitch, onChannel: 0)
                case 2: e.sampler?.sendController(64, withValue: 127, onChannel: 0)
                default: e.sampler?.sendController(64, withValue: 0, onChannel: 0)
                }
                idx += 1
            }
            let n = AVAudioFrameCount(min(block, totalFrames - frame))
            let status = try engine.renderOffline(n, to: outBuf)
            switch status {
            case .success:
                stalls = 0
                guard let ch = outBuf.floatChannelData else { throw AppMessage("The renderer returned no audio.") }
                let got = Int(outBuf.frameLength)
                let chans = Int(outBuf.format.channelCount)
                for i in 0..<got {
                    left[frame + i] = ch[0][i]
                    right[frame + i] = chans > 1 ? ch[1][i] : ch[0][i]
                }
                frame += got
            case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                stalls += 1
                if stalls > 2000 { throw AppMessage("The renderer stalled. Try bouncing again.") }
                Thread.sleep(forTimeInterval: 0.001)
            case .error:
                throw AppMessage("The audio renderer reported an error.")
            @unknown default:
                throw AppMessage("The audio renderer returned an unexpected result.")
            }
            if frame - lastReport > Int(sr) {
                lastReport = frame
                progress(Double(frame) / Double(totalFrames))
            }
        }
        engine.stop()

        // Trim trailing silence, but never cut the song itself.
        let songFrames = Int(songSeconds * sr)
        var last = totalFrames - 1
        while last > songFrames && abs(left[last]) < 1e-4 && abs(right[last]) < 1e-4 { last -= 1 }
        let keep = min(totalFrames, max(songFrames, last + Int(0.25 * sr)))
        if keep < totalFrames {
            left.removeLast(totalFrames - keep)
            right.removeLast(totalFrames - keep)
        }
        progress(1.0)
        return RenderedAudio(channels: [left, right], sampleRate: sr)
    }

    /// Normalises to about -14 LUFS integrated, then limits to -1 dBTP.
    static func normalise(_ audio: RenderedAudio) throws -> (RenderedAudio, BounceReport) {
        guard let before = Loudness.integratedLUFS(channels: audio.channels, sampleRate: audio.sampleRate) else {
            throw AppMessage("The mix is silent or too short to measure loudness. Add some notes or a recording and try again.")
        }
        var gainDB = targetLUFS - before
        gainDB = max(-40, min(40, gainDB))
        let gain = Float(Loudness.linear(fromDB: gainDB))
        var chans = audio.channels
        for c in 0..<chans.count {
            for i in 0..<chans[c].count { chans[c][i] *= gain }
        }
        Loudness.limit(channels: &chans, ceilingDB: ceilingDB, sampleRate: audio.sampleRate)
        let after = Loudness.integratedLUFS(channels: chans, sampleRate: audio.sampleRate) ?? before
        let tp = Loudness.dB(fromLinear: Double(Loudness.truePeak(channels: chans)))
        let report = BounceReport(lufsBefore: before, lufsAfter: after, truePeakDB: tp, gainDB: gainDB,
                                  seconds: Double(audio.frames) / audio.sampleRate)
        return (RenderedAudio(channels: chans, sampleRate: audio.sampleRate), report)
    }

    // MARK: File writing

    private static func writeFile(_ audio: RenderedAudio, to url: URL, settings: [String: Any]) throws {
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let chunk = 8192
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)),
              let ch = buf.floatChannelData else {
            throw AppMessage("Could not allocate the file writer.")
        }
        let channelCount = Int(format.channelCount)
        var pos = 0
        let total = audio.frames
        while pos < total {
            let n = min(chunk, total - pos)
            for c in 0..<channelCount {
                let src = audio.channels[min(c, audio.channels.count - 1)]
                for i in 0..<n { ch[c][i] = src[pos + i] }
            }
            buf.frameLength = AVAudioFrameCount(n)
            try file.write(from: buf)
            pos += n
        }
    }

    static func writeWAV24(_ audio: RenderedAudio, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        try writeFile(audio, to: url, settings: settings)
    }

    static func writeM4A(_ audio: RenderedAudio, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256000,
        ]
        try writeFile(audio, to: url, settings: settings)
    }
}
