import AVFoundation
import AudioToolbox

/// Maps between unrolled transport "x" beats (count-in, then song position, then repeating loop passes) and host time.
struct Timeline {
    var h0: Double = 0          // host seconds at x0
    var x0: Double = 0          // first x (negative offset during count-in)
    var spb: Double = 0.5
    var b0: Double = 0          // beat where the music starts
    var looping: Bool = false
    var loopStart: Double = 0
    var loopEnd: Double = 0

    var loopLength: Double { loopEnd - loopStart }

    func x(atHost t: Double) -> Double { x0 + (t - h0) / spb }
    func host(atX x: Double) -> Double { h0 + (x - x0) * spb }

    /// The song beat and loop pass for an unrolled position.
    func fold(_ x: Double) -> (beat: Double, pass: Int) {
        if looping && loopLength > 1e-9 && x >= loopEnd {
            let k = floor((x - loopEnd) / loopLength) + 1
            return (loopStart + (x - loopEnd - (k - 1) * loopLength), Int(k))
        }
        return (x, 0)
    }

    /// Calls `body(foldedStart, foldedEnd, offsetX, endsAtWrap)` for each contiguous piece of [from, to).
    func walk(from: Double, to: Double, _ body: (Double, Double, Double, Bool) -> Void) {
        var cx = from
        var guardCount = 0
        while cx < to - 1e-12 && guardCount < 64 {
            guardCount += 1
            var segEnd = to
            var boundary: Double? = nil
            if looping && loopLength > 1e-9 {
                if cx < loopEnd {
                    boundary = loopEnd
                } else {
                    let k = floor((cx - loopEnd) / loopLength) + 1
                    boundary = loopEnd + k * loopLength
                }
                if let b = boundary, b < to { segEnd = b } else { boundary = nil }
            }
            let f = fold(cx)
            body(f.beat, f.beat + (segEnd - cx), cx - f.beat, boundary != nil)
            cx = segEnd
        }
    }
}

struct PlayRequest {
    var fromBeat: Double
    var cycle: ClosedRange<Double>?
    var countInBeats: Double
    var clickEnabled: Bool
    var clickVolume: Float
    var recordAudioTrack: UUID?
    var recordMIDI: Bool
    var latencySeconds: Double
}

struct StopResult {
    var endBeat: Double
    var startBeat: Double
    var loop: ClosedRange<Double>?
    var countInBeats: Double
    var spb: Double
    var hostStart: Double
    var passes: Int
    var audio: RecordedAudio?
    var audioTrackID: UUID?
    var audioError: String?
    var midiNotes: [AbsNote]
    var pedal: [PedalEvent]
    var recordedMIDI: Bool
    var latencySeconds: Double
    var wasRecordingAudio: Bool
}

private struct SchedEvent {
    var beat: Double
    var order: UInt8      // 0 note off, 1 pedal up, 2 pedal down, 3 note on
    var pitch: UInt8
    var vel: UInt8
    var track: Int
}

private struct SchedTrack {
    var id: UUID
    var sampler: AVAudioUnitSampler?
    var audible: Bool
}

private struct StructureItem: Equatable {
    var id: UUID
    var kind: TrackKind
    var instrument: InstrumentKind
}

/// Live audio engine: graph, transport, MIDI and audio scheduling, metronome and recording.
final class AudioEngine {
    /// Called on the main thread whenever the transport stops (user, end of song, or error).
    var onStopped: ((StopResult) -> Void)?

    private let q = DispatchQueue(label: "com.ajthereal.songwriter.audio", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let graph: AudioGraph
    private let metroPlayer = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private let recorder = AudioRecorder()
    private let audioDir: URL

    // Shared state guarded by `lock`.
    private let lock = NSLock()
    private var shared = Shared()
    private struct Shared {
        var playing = false
        var timeline = Timeline()
        var liveSampler: AVAudioUnitSampler?
        var liveTrackID: UUID?
        var midiRecording = false
        var midiEvents: [(beat: Double, pitch: Int, vel: Int, on: Bool)] = []
        var pedalEvents: [(beat: Double, down: Bool)] = []
    }

    // Queue confined state.
    private var song = Song()
    private var graphBuilt = false
    private var lastStructure: [StructureItem] = []
    private var lastAudioSignature: String = ""
    private var schedTracks: [SchedTrack] = []
    private var events: [SchedEvent] = []
    private var sounding = Set<Int>()
    private var timer: DispatchSourceTimer?
    private var timeline = Timeline()
    private var request: PlayRequest?
    private var midiX: Double = 0
    private var clickX: Double = 0
    private var audioPass: Int = 0
    private var fileCache: [String: AVAudioFile] = [:]
    private var reportedFiles = Set<String>()
    private var inputConnected = false
    private var softwareMonitoring = false
    private var recordingAudioTrack: UUID?
    private var finishing = false
    private var configObserver: NSObjectProtocol?

    init(projectAudioDir: URL) {
        audioDir = projectAudioDir
        graph = AudioGraph(engine: engine)
        graph.soundFontURL = ResourceLocator.soundFontURL
        engine.attach(metroPlayer)
        engine.connect(metroPlayer, to: engine.mainMixerNode, fromBus: 0, toBus: 2, format: graph.mono)
        clickBuffer = makeClick(freq: 1000, amp: 0.5, ms: 30)
        accentBuffer = makeClick(freq: 1600, amp: 0.8, ms: 30)
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.configChanged()
        }
    }

    deinit {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        timer?.cancel()
        if engine.isRunning { engine.stop() }
    }

    /// Stops everything synchronously (used when a project is closed).
    func shutdown() {
        q.sync {
            if self.isPlaying { self.stopTransport(notify: false) }
            if self.recorder.tapInstalled { self.recorder.removeTap(from: self.engine.inputNode) }
            self.allNotesOff()
            if self.engine.isRunning { self.engine.stop() }
        }
    }

    private func makeClick(freq: Double, amp: Float, ms: Double) -> AVAudioPCMBuffer? {
        let sr = graph.mono.sampleRate
        let n = AVAudioFrameCount(sr * ms / 1000.0)
        guard let b = AVAudioPCMBuffer(pcmFormat: graph.mono, frameCapacity: n), let ch = b.floatChannelData else { return nil }
        b.frameLength = n
        for i in 0..<Int(n) {
            let t = Double(i) / sr
            ch[0][i] = Float(sin(2.0 * Double.pi * freq * t) * exp(-t * 140.0)) * amp
        }
        return b
    }

    // MARK: - Public API (any thread)

    func update(song newSong: Song) {
        let copy = newSong
        q.async { self.applySong(copy) }
    }

    func setLiveTarget(trackID: UUID?) {
        q.async {
            let s = trackID.flatMap { self.graph.sampler(for: $0) }
            self.lock.sync {
                self.shared.liveSampler = s
                self.shared.liveTrackID = trackID
            }
        }
    }

    func setSoftwareMonitoring(_ on: Bool) {
        q.async {
            self.softwareMonitoring = on
            self.graph.monitorMixer.outputVolume = on ? 1 : 0
        }
    }

    func setMetronomeVolume(_ v: Float) {
        q.async { self.metroPlayer.volume = max(0, min(1, v)) }
    }

    var isPlaying: Bool { lock.sync { shared.playing } }

    /// Current song position in beats, or nil when stopped. Negative values mean count-in.
    func currentBeat() -> Double? {
        let t: Timeline? = lock.sync { shared.playing ? shared.timeline : nil }
        guard let tl = t else { return nil }
        let x = max(tl.x0, tl.x(atHost: hostNowSeconds()))
        return tl.fold(x).beat
    }

    var inputLevel: Float { recorder.level }

    func play(_ req: PlayRequest) {
        q.async { self.startTransport(req) }
    }

    func stop() {
        q.async { self.stopTransport() }
    }

    func panic() {
        q.async { self.allNotesOff() }
    }

    // MARK: Live notes

    func liveNoteOn(_ pitch: Int, velocity: Int) {
        let s = lock.sync { shared.liveSampler }
        s?.startNote(UInt8(max(0, min(127, pitch))), withVelocity: UInt8(max(1, min(127, velocity))), onChannel: 0)
        recordLive(pitch: pitch, vel: velocity, on: true)
    }

    func liveNoteOff(_ pitch: Int) {
        let s = lock.sync { shared.liveSampler }
        s?.stopNote(UInt8(max(0, min(127, pitch))), onChannel: 0)
        recordLive(pitch: pitch, vel: 0, on: false)
    }

    func liveSustain(_ down: Bool) {
        let s = lock.sync { shared.liveSampler }
        s?.sendController(64, withValue: down ? 127 : 0, onChannel: 0)
        if let beat = currentBeat() {
            lock.sync {
                if shared.midiRecording { shared.pedalEvents.append((beat, down)) }
            }
        }
    }

    private func recordLive(pitch: Int, vel: Int, on: Bool) {
        guard let beat = currentBeat() else { return }
        lock.sync {
            if shared.midiRecording { shared.midiEvents.append((beat, pitch, vel, on)) }
        }
    }

    /// Plays a few notes on a track's instrument for a moment (chord pad, key audition).
    func audition(trackID: UUID, pitches: [Int], velocity: Int = 84, duration: Double = 0.9) {
        q.async {
            guard let sampler = self.graph.sampler(for: trackID) else { return }
            do { try self.startEngineIfNeeded() } catch {
                ErrorCenter.report(error, while: "start the audio engine")
                return
            }
            for p in pitches {
                sampler.startNote(UInt8(max(0, min(127, p))), withVelocity: UInt8(max(1, min(127, velocity))), onChannel: 0)
            }
            self.q.asyncAfter(deadline: .now() + duration) {
                for p in pitches { sampler.stopNote(UInt8(max(0, min(127, p))), onChannel: 0) }
            }
        }
    }

    // MARK: - Song updates (queue)

    private func structure(of s: Song) -> [StructureItem] {
        s.tracks.map { StructureItem(id: $0.id, kind: $0.kind, instrument: $0.instrument) }
    }

    private func audioSignature(of s: Song) -> String {
        var parts: [String] = ["\(s.tempo)"]
        for t in s.tracks where t.kind == .audio {
            parts.append("\(t.id)|\(AudioGraph.isAudible(t, in: s))")
            for r in t.regions {
                parts.append("\(r.id)|\(r.startBeat)|\(r.lengthBeats)|\(r.audioOffset)|\(r.activeTake)|\(r.takes.map { $0.id.uuidString + String($0.offset) }.joined())")
            }
        }
        return parts.joined(separator: ";")
    }

    private func applySong(_ new: Song) {
        song = new
        let structureNow = structure(of: new)
        let wasPlaying = isPlaying
        if !graphBuilt || structureNow != lastStructure {
            if wasPlaying { stopTransport() }
            rebuildGraph()
            lastStructure = structureNow
        } else {
            graph.applyMix(song: new)
            refreshSchedTracks()
        }
        rebuildEvents()
        let sig = audioSignature(of: new)
        if sig != lastAudioSignature {
            lastAudioSignature = sig
            if isPlaying && recordingAudioTrack == nil, let req = request, let beat = currentBeat() {
                // Audio content changed during playback: restart from the current position.
                var again = req
                again.fromBeat = beat
                again.countInBeats = 0
                startTransport(again)
            }
        }
    }

    private func rebuildGraph() {
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        graph.soundFontURL = ResourceLocator.soundFontURL
        graph.configure(song: song)
        graph.monitorMixer.outputVolume = softwareMonitoring ? 1 : 0
        graphBuilt = true
        refreshSchedTracks()
        for issue in graph.takeIssues() { ErrorCenter.post(issue, warning: true) }
        let liveID = lock.sync { shared.liveTrackID }
        let s = liveID.flatMap { graph.sampler(for: $0) }
        lock.sync { shared.liveSampler = s }
        _ = wasRunning
        do {
            engine.prepare()
            try engine.start()
        } catch {
            ErrorCenter.report(error, while: "start the audio engine")
        }
    }

    private func refreshSchedTracks() {
        schedTracks = song.tracks.map { t in
            SchedTrack(id: t.id, sampler: graph.sampler(for: t.id), audible: AudioGraph.isAudible(t, in: song))
        }
    }

    private func rebuildEvents() {
        var out: [SchedEvent] = []
        for (i, t) in song.tracks.enumerated() where t.kind == .instrument {
            for n in song.playbackNotes(for: t) {
                let p = UInt8(max(0, min(127, n.pitch)))
                let v = UInt8(max(1, min(127, n.velocity)))
                out.append(SchedEvent(beat: n.start, order: 3, pitch: p, vel: v, track: i))
                out.append(SchedEvent(beat: n.start + n.length, order: 0, pitch: p, vel: 0, track: i))
            }
            for pe in song.playbackPedal(for: t) {
                out.append(SchedEvent(beat: pe.beat, order: pe.down ? 2 : 1, pitch: 0, vel: 0, track: i))
            }
        }
        out.sort { a, b in
            if a.beat != b.beat { return a.beat < b.beat }
            return a.order < b.order
        }
        events = out
    }

    private func configChanged() {
        q.async {
            let wasPlaying = self.isPlaying
            if wasPlaying {
                self.stopTransport()
                ErrorCenter.post("The audio device changed, so playback was stopped. Press play to continue.", warning: true)
            }
            self.inputConnected = false
            self.recorder.removeTapIfNeeded()
            if self.engine.isRunning { self.engine.stop() }
            self.rebuildGraph()
        }
    }

    // MARK: - Engine / input

    private func startEngineIfNeeded() throws {
        if engine.isRunning { return }
        if !graphBuilt { rebuildGraph() }
        engine.prepare()
        try engine.start()
    }

    /// Connects the input node (needs microphone permission) and installs the metering tap.
    func armInput(_ on: Bool, completion: ((String?) -> Void)? = nil) {
        q.async {
            if on {
                do {
                    try self.ensureInputPath()
                    self.recorder.installTap(on: self.engine.inputNode)
                    completion.map { c in DispatchQueue.main.async { c(nil) } }
                } catch {
                    let msg = ErrorCenter.describe(error)
                    completion.map { c in DispatchQueue.main.async { c(msg) } }
                }
            } else if self.recordingAudioTrack == nil {
                if self.recorder.tapInstalled { self.recorder.removeTap(from: self.engine.inputNode) }
                completion.map { c in DispatchQueue.main.async { c(nil) } }
            }
        }
    }

    private func ensureInputPath() throws {
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw AppMessage("No audio input is available. Connect a microphone or audio interface, and make sure microphone access is allowed in Settings.")
        }
        if !inputConnected {
            let wasRunning = engine.isRunning
            if wasRunning { engine.pause() }
            engine.connect(input, to: graph.monitorMixer, format: fmt)
            inputConnected = true
            engine.prepare()
            try engine.start()
        } else if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    // MARK: - Transport (queue)

    private func startTransport(_ req: PlayRequest) {
        if isPlaying { stopTransport(notify: false) }
        finishing = false
        do {
            try startEngineIfNeeded()
        } catch {
            ErrorCenter.report(error, while: "start the audio engine")
            DispatchQueue.main.async { self.onStopped?(self.emptyResult(req)) }
            return
        }

        var b0 = req.fromBeat
        var tl = Timeline()
        tl.spb = song.secondsPerBeat
        if let c = req.cycle, c.upperBound - c.lowerBound > 0.01 {
            tl.looping = true
            tl.loopStart = c.lowerBound
            tl.loopEnd = c.upperBound
            if b0 < c.lowerBound - 1e-9 || b0 >= c.upperBound - 1e-9 { b0 = c.lowerBound }
        }
        tl.b0 = b0
        tl.x0 = b0 - max(0, req.countInBeats)
        tl.h0 = hostNowSeconds() + 0.10

        // Recording set-up happens before the transport clock starts.
        recordingAudioTrack = nil
        if let trackID = req.recordAudioTrack {
            do {
                try ensureInputPath()
                if !recorder.tapInstalled { recorder.installTap(on: engine.inputNode) }
                let name = "take-\(UUID().uuidString.prefix(8)).caf"
                try recorder.beginWriting(to: audioDir.appendingPathComponent(name))
                recordingAudioTrack = trackID
            } catch {
                ErrorCenter.report(error, while: "start recording")
                DispatchQueue.main.async { self.onStopped?(self.emptyResult(req)) }
                return
            }
        }

        timeline = tl
        request = req
        midiX = tl.x0
        clickX = tl.x0
        audioPass = 0
        sounding.removeAll()
        rebuildEvents()
        refreshSchedTracks()

        metroPlayer.volume = max(0, min(1, req.clickVolume))
        metroPlayer.stop()
        metroPlayer.play()
        for t in song.tracks where t.kind == .audio {
            if let p = graph.player(for: t.id) {
                p.stop()
                p.play()
            }
        }
        scheduleAudio(from: b0, to: tl.looping ? tl.loopEnd : max(song.lengthBeats, b0) + 1, offsetX: 0, tl: tl)

        lock.sync {
            shared.timeline = tl
            shared.playing = true
            shared.midiRecording = req.recordMIDI
            shared.midiEvents.removeAll()
            shared.pedalEvents.removeAll()
        }

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: q)
        t.schedule(deadline: .now(), repeating: .milliseconds(4), leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        timer?.cancel()
        timer = t
        t.resume()
    }

    private func emptyResult(_ req: PlayRequest) -> StopResult {
        StopResult(endBeat: req.fromBeat, startBeat: req.fromBeat, loop: req.cycle, countInBeats: req.countInBeats,
                   spb: song.secondsPerBeat, hostStart: 0, passes: 0, audio: nil, audioTrackID: nil, audioError: nil,
                   midiNotes: [], pedal: [], recordedMIDI: false, latencySeconds: req.latencySeconds, wasRecordingAudio: false)
    }

    private func tick() {
        guard isPlaying else { return }
        let tl = timeline
        let now = hostNowSeconds()

        // MIDI: send events that are due (tiny look-ahead covers the IO buffer).
        let xMIDI = tl.x(atHost: now + max(0.002, AudioSessionManager.shared.ioBufferDuration * 0.5))
        if xMIDI > midiX {
            processMIDI(to: xMIDI, tl: tl)
            midiX = xMIDI
        }

        // Clicks and audio passes are scheduled further ahead with host time stamps.
        let xAhead = tl.x(atHost: now + 0.25)
        if xAhead > clickX {
            scheduleClicks(to: xAhead, tl: tl, now: now)
            clickX = xAhead
        }
        if tl.looping {
            let current = tl.fold(max(tl.x0, tl.x(atHost: now))).pass
            while audioPass < current + 2 {
                audioPass += 1
                scheduleAudio(from: tl.loopStart, to: tl.loopEnd, offsetX: Double(audioPass) * tl.loopLength, tl: tl)
            }
        }

        // Stop at the end of the song unless looping or recording.
        if !tl.looping && recordingAudioTrack == nil && !(request?.recordMIDI ?? false) {
            let xNow = tl.x(atHost: now)
            if xNow >= max(song.lengthBeats, tl.b0) + 1.0 {
                stopTransport()
            }
        }
    }

    private func processMIDI(to xEnd: Double, tl: Timeline) {
        tl.walk(from: midiX, to: xEnd) { fb0, fb1, _, endsAtWrap in
            if fb1 > fb0 && !events.isEmpty {
                var lo = 0
                var hi = events.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if events[mid].beat < fb0 - 1e-9 { lo = mid + 1 } else { hi = mid }
                }
                var i = lo
                while i < events.count && events[i].beat < fb1 - 1e-9 {
                    send(events[i])
                    i += 1
                }
            }
            if endsAtWrap { releaseSounding() }
        }
    }

    private func send(_ e: SchedEvent) {
        guard e.track >= 0, e.track < schedTracks.count else { return }
        let t = schedTracks[e.track]
        guard let sampler = t.sampler else { return }
        let key = e.track * 256 + Int(e.pitch)
        switch e.order {
        case 3:
            guard t.audible else { return }
            if sounding.contains(key) { sampler.stopNote(e.pitch, onChannel: 0) }
            sampler.startNote(e.pitch, withVelocity: e.vel, onChannel: 0)
            sounding.insert(key)
        case 0:
            if sounding.remove(key) != nil { sampler.stopNote(e.pitch, onChannel: 0) }
        case 2:
            if t.audible { sampler.sendController(64, withValue: 127, onChannel: 0) }
        case 1:
            sampler.sendController(64, withValue: 0, onChannel: 0)
        default:
            break
        }
    }

    private func releaseSounding() {
        for key in sounding {
            let track = key / 256
            let pitch = UInt8(key % 256)
            if track < schedTracks.count { schedTracks[track].sampler?.stopNote(pitch, onChannel: 0) }
        }
        sounding.removeAll()
        for t in schedTracks { t.sampler?.sendController(64, withValue: 0, onChannel: 0) }
    }

    private func allNotesOff() {
        releaseSounding()
        for t in schedTracks {
            t.sampler?.sendController(123, withValue: 0, onChannel: 0)
            t.sampler?.sendController(120, withValue: 0, onChannel: 0)
        }
    }

    private func scheduleClicks(to xEnd: Double, tl: Timeline, now: Double) {
        guard let req = request, let click = clickBuffer, let accent = accentBuffer else { return }
        let interval = song.timeSignature.clickInterval
        let bpb = song.beatsPerBar
        tl.walk(from: clickX, to: xEnd) { fb0, fb1, offset, _ in
            var n = Int(ceil(fb0 / interval - 1e-9))
            while Double(n) * interval < fb1 - 1e-9 {
                let beat = Double(n) * interval
                let x = beat + offset
                let isCountIn = x < tl.b0 - 1e-9
                if isCountIn || req.clickEnabled {
                    let host = tl.host(atX: x)
                    if host > now {
                        let barPos = beat / bpb
                        let isAccent = abs(barPos - barPos.rounded()) < 1e-6
                        let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: host))
                        metroPlayer.scheduleBuffer(isAccent ? accent : click, at: when, options: [], completionHandler: nil)
                    }
                }
                n += 1
            }
        }
    }

    // MARK: Audio region scheduling

    private func openFile(_ name: String) -> AVAudioFile? {
        if let f = fileCache[name] { return f }
        let url = audioDir.appendingPathComponent(name)
        do {
            let f = try AVAudioFile(forReading: url)
            fileCache[name] = f
            return f
        } catch {
            if reportedFiles.insert(name).inserted {
                ErrorCenter.post("An audio take could not be opened (\(name)). It may have been deleted. \(ErrorCenter.describe(error))")
            }
            return nil
        }
    }

    /// Schedules the audio regions overlapping [a, b) (song beats), shifted by offsetX in unrolled beats.
    private func scheduleAudio(from a: Double, to b: Double, offsetX: Double, tl: Timeline) {
        let now = hostNowSeconds()
        let spb = tl.spb
        for t in song.tracks where t.kind == .audio {
            guard AudioGraph.isAudible(t, in: song), let player = graph.player(for: t.id) else { continue }
            for r in t.regions where r.kind == .audio {
                guard r.startBeat < b - 1e-9, r.endBeat > a + 1e-9, let take = r.activeTakeValue else { continue }
                guard let file = openFile(take.fileName) else { continue }
                let fmt = file.processingFormat
                if fmt.channelCount != 1 || abs(fmt.sampleRate - graph.mono.sampleRate) > 0.5 {
                    if reportedFiles.insert(take.fileName).inserted {
                        ErrorCenter.post("The take \(take.fileName) has an unsupported audio format and was skipped.")
                    }
                    continue
                }
                let s = max(a, r.startBeat)
                let e = min(b, r.endBeat)
                if e - s < 1e-6 { continue }
                let fileSeconds = take.offset + r.audioOffset + (s - r.startBeat) * spb
                var startFrame = AVAudioFramePosition((fileSeconds * fmt.sampleRate).rounded())
                var frames = AVAudioFramePosition(((e - s) * spb * fmt.sampleRate).rounded())
                var host = tl.host(atX: s + offsetX)
                if startFrame < 0 {
                    // The take starts later than the region: delay the start.
                    host += Double(-startFrame) / fmt.sampleRate
                    frames += startFrame
                    startFrame = 0
                }
                if host < now + 0.005 {
                    let skip = AVAudioFramePosition((now + 0.005 - host) * fmt.sampleRate)
                    startFrame += skip
                    frames -= skip
                    host = now + 0.005
                }
                if startFrame >= file.length { continue }
                frames = min(frames, file.length - startFrame)
                if frames <= 0 { continue }
                let when = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: host))
                player.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(frames), at: when, completionHandler: nil)
            }
        }
    }

    // MARK: Stop

    private func stopTransport(notify: Bool = true) {
        guard isPlaying else { return }
        let tl = timeline
        let now = hostNowSeconds()
        let xNow = max(tl.x0, tl.x(atHost: now))
        let folded = tl.fold(xNow)
        timer?.cancel()
        timer = nil
        metroPlayer.stop()
        for t in song.tracks where t.kind == .audio { graph.player(for: t.id)?.stop() }
        allNotesOff()

        var midiNotes: [AbsNote] = []
        var pedal: [PedalEvent] = []
        var recordedMIDI = false
        let endBeat = max(tl.b0, folded.beat)
        let (events, pedals, wasMIDI): ([(beat: Double, pitch: Int, vel: Int, on: Bool)], [(beat: Double, down: Bool)], Bool) = lock.sync {
            let r = (shared.midiEvents, shared.pedalEvents, shared.midiRecording)
            shared.playing = false
            shared.midiRecording = false
            return r
        }
        if wasMIDI {
            recordedMIDI = true
            var open: [Int: (beat: Double, vel: Int)] = [:]
            for e in events {
                if e.on {
                    if let prev = open[e.pitch] {
                        midiNotes.append(AbsNote(start: prev.beat, length: max(0.05, e.beat - prev.beat), pitch: e.pitch, velocity: prev.vel))
                    }
                    open[e.pitch] = (e.beat, e.vel)
                } else if let o = open[e.pitch] {
                    midiNotes.append(AbsNote(start: o.beat, length: max(0.05, e.beat - o.beat), pitch: e.pitch, velocity: o.vel))
                    open[e.pitch] = nil
                }
            }
            for (pitch, o) in open {
                midiNotes.append(AbsNote(start: o.beat, length: max(0.05, endBeat - o.beat), pitch: pitch, velocity: o.vel))
            }
            midiNotes.sort { $0.start < $1.start }
            pedal = pedals.map { PedalEvent(beat: $0.beat, down: $0.down) }
        }

        let req = request
        let recTrack = recordingAudioTrack
        recordingAudioTrack = nil
        let loop: ClosedRange<Double>? = tl.looping ? tl.loopStart...tl.loopEnd : nil
        var result = StopResult(endBeat: endBeat, startBeat: tl.b0, loop: loop, countInBeats: tl.b0 - tl.x0, spb: tl.spb,
                                hostStart: tl.h0, passes: folded.pass + 1, audio: nil, audioTrackID: recTrack, audioError: nil,
                                midiNotes: midiNotes, pedal: pedal, recordedMIDI: recordedMIDI,
                                latencySeconds: req?.latencySeconds ?? 0, wasRecordingAudio: recTrack != nil)
        guard notify else {
            if recTrack != nil { recorder.endWriting { _, _ in } }
            return
        }
        if recTrack != nil {
            // Keep capturing for the latency amount so the very end of the take is not cut off.
            let tail = min(0.4, max(0.02, req?.latencySeconds ?? 0.05))
            q.asyncAfter(deadline: .now() + tail) {
                self.recorder.endWriting { audio, failure in
                    result.audio = audio
                    result.audioError = failure
                    self.onStopped?(result)
                }
            }
        } else {
            DispatchQueue.main.async { self.onStopped?(result) }
        }
    }
}

extension AudioRecorder {
    func removeTapIfNeeded() {
        // The tap is removed by the engine on a configuration change; just forget it.
        markTapRemoved()
    }
}
