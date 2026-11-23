import SwiftUI
import Combine

enum ViewMode: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case chart = "Chart"
    case lyrics = "Lyrics"
    var id: String { rawValue }
}

enum ActiveSheet: Identifiable, Equatable {
    case tempo
    case sections
    case bounce
    case settings
    case track(UUID)
    case chord(Double)
    case addTrack

    var id: String {
        switch self {
        case .tempo: return "tempo"
        case .sections: return "sections"
        case .bounce: return "bounce"
        case .settings: return "settings"
        case .track(let u): return "track-\(u.uuidString)"
        case .chord(let b): return "chord-\(b)"
        case .addTrack: return "addTrack"
        }
    }
}

final class MeterModel: ObservableObject {
    @Published var level: Float = 0
}

/// Everything about the open project: the song, selection, transport, undo and autosave.
final class ProjectSession: ObservableObject, Identifiable {
    let projectID: UUID
    var id: UUID { projectID }
    let store = ProjectStore.shared
    let settings = AppSettings.shared
    let engine: AudioEngine
    let meter = MeterModel()

    @Published var song: Song {
        didSet {
            if song != oldValue { songDidChange() }
        }
    }
    @Published var viewMode: ViewMode = .tracks
    @Published var selectedTrackID: UUID? {
        didSet { updateLiveTarget() }
    }
    @Published var selectedRegionID: UUID? {
        didSet { if selectedRegionID != nil && selectedFollowTrackID != nil { selectedFollowTrackID = nil } }
    }
    /// A generated (follow chords) part is selected; it has no region of its own.
    @Published var selectedFollowTrackID: UUID? {
        didSet { if selectedFollowTrackID != nil && selectedRegionID != nil { selectedRegionID = nil } }
    }
    @Published var snap: SnapMode
    @Published var pxPerBeat: CGFloat = 16
    @Published var followOn = true
    @Published var followPaused = false
    @Published var editorOpen = true
    @Published var armedTrackID: UUID?
    @Published var cycleOn = false
    @Published var isPlaying = false
    @Published var isRecording = false
    @Published var playingBar = 0
    @Published var stoppedBeat: Double = 0
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var showMicDenied = false
    @Published var midiSourceCount = 0
    @Published var sheet: ActiveSheet?
    @Published var rollPxPerBeat: CGFloat = 72
    @Published var showKeyboard = false
    @Published var showChordPad = true
    @Published var recordStartBeat: Double = 0

    private var undoStack = UndoStack<Song>(limit: 100)
    private var gestureOpen = false
    private var engineUpdateItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.ajthereal.songwriter.save", qos: .utility)
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var lastLiveInstrumentTrack: UUID?
    private var recordingTrackID: UUID?
    private var pendingRewind = false

    init(song: Song) {
        self.song = song
        projectID = song.id
        snap = AppSettings.shared.defaultSnap
        let savedZoom = UserDefaults.standard.double(forKey: "zoomPxPerBar.\(song.id.uuidString)")
        let barPx = savedZoom > 0 ? CGFloat(savedZoom) : ProjectSession.defaultBarPx
        pxPerBeat = min(ProjectSession.maxBarPx, max(ProjectSession.minBarPx, barPx)) / CGFloat(max(1, song.beatsPerBar))
        engine = AudioEngine(projectAudioDir: ProjectStore.shared.audioDir(song.id))
        selectedTrackID = song.tracks.first(where: { $0.kind == .instrument })?.id ?? song.tracks.first?.id
        lastLiveInstrumentTrack = song.tracks.first(where: { $0.kind == .instrument })?.id

        engine.onStopped = { [weak self] result in self?.handleStopped(result) }
        engine.update(song: song)
        engine.setSoftwareMonitoring(settings.softwareMonitoring)
        updateLiveTarget()

        saveSubject
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.saveNow() }
            .store(in: &cancellables)
        settings.$softwareMonitoring
            .sink { [weak self] on in self?.engine.setSoftwareMonitoring(on) }
            .store(in: &cancellables)

        let midi = MIDIInput.shared
        midi.onNoteOn = { [weak self] p, v in self?.engine.liveNoteOn(p, velocity: v) }
        midi.onNoteOff = { [weak self] p in self?.engine.liveNoteOff(p) }
        midi.onSustain = { [weak self] d in self?.engine.liveSustain(d) }
        midi.onSourcesChanged = { [weak self] n in self?.midiSourceCount = n }
        midi.start()
        midiSourceCount = midi.sourceCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tickUI() }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Lifecycle

    func close() {
        timer?.invalidate()
        timer = nil
        if isPlaying { engine.stop() }
        saveNow(synchronous: true)
        engine.shutdown()
        let midi = MIDIInput.shared
        midi.onNoteOn = nil
        midi.onNoteOff = nil
        midi.onSustain = nil
        midi.onSourcesChanged = nil
    }

    func interrupted() {
        if isPlaying { engine.stop() }
        saveNow(synchronous: true)
    }

    private func tickUI() {
        if isPlaying {
            if let beat = engine.currentBeat() {
                let bar = beat < 0 ? -1 : song.barIndex(atBeat: beat)
                if bar != playingBar { playingBar = bar }
            }
        }
        if armedTrack?.kind == .audio || isRecording {
            meter.level = engine.inputLevel
        } else if meter.level != 0 {
            meter.level = 0
        }
    }

    // MARK: - Derived

    var armedTrack: Track? {
        guard let id = armedTrackID else { return nil }
        return song.tracks.first { $0.id == id }
    }

    var selectedTrack: Track? {
        guard let id = selectedTrackID else { return nil }
        return song.tracks.first { $0.id == id }
    }

    func selectRegion(trackID: UUID, regionID: UUID) {
        selectedTrackID = trackID
        selectedRegionID = regionID
        editorOpen = true
    }

    func selectFollowPart(trackID: UUID) {
        selectedTrackID = trackID
        selectedFollowTrackID = trackID
        editorOpen = true
    }

    func clearRegionSelection(trackID: UUID? = nil) {
        if let t = trackID { selectedTrackID = t }
        selectedRegionID = nil
        selectedFollowTrackID = nil
    }

    /// The track whose generated part is selected, if it still follows the chords.
    var selectedFollowTrack: Track? {
        guard let id = selectedFollowTrackID,
              let t = song.tracks.first(where: { $0.id == id }),
              t.kind == .instrument, t.follow else { return nil }
        return t
    }

    var selectedRegion: (track: Track, region: Region)? {
        guard let rid = selectedRegionID else { return nil }
        for t in song.tracks {
            if let r = t.regions.first(where: { $0.id == rid }) { return (t, r) }
        }
        return nil
    }

    /// The beat to show: live position while playing, otherwise where the playhead was left.
    func displayBeat() -> Double {
        engine.currentBeat() ?? stoppedBeat
    }

    // MARK: - Editing

    private func songDidChange() {
        saveSubject.send()
        scheduleEngineUpdate()
    }

    private func scheduleEngineUpdate() {
        engineUpdateItem?.cancel()
        let snapshot = song
        let item = DispatchWorkItem { [weak self] in self?.engine.update(song: snapshot) }
        engineUpdateItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: item)
    }

    private func refreshUndoFlags() {
        canUndo = undoStack.canUndo
        canRedo = undoStack.canRedo
    }

    /// Applies an edit that can be undone.
    func edit(_ action: (inout Song) -> Void) {
        undoStack.record(song)
        refreshUndoFlags()
        var s = song
        action(&s)
        song = s
    }

    /// Applies an edit without recording undo (used while a gesture is in progress).
    func mutate(_ action: (inout Song) -> Void) {
        var s = song
        action(&s)
        song = s
    }

    /// Records one undo step at the start of a drag.
    func beginGesture() {
        if !gestureOpen {
            gestureOpen = true
            undoStack.record(song)
            refreshUndoFlags()
        }
    }

    func endGesture() {
        gestureOpen = false
    }

    func undo() {
        guard let previous = undoStack.undo(current: song) else { return }
        song = previous
        refreshUndoFlags()
        validateSelection()
    }

    func redo() {
        guard let next = undoStack.redo(current: song) else { return }
        song = next
        refreshUndoFlags()
        validateSelection()
    }

    private func validateSelection() {
        if let t = selectedTrackID, !song.tracks.contains(where: { $0.id == t }) { selectedTrackID = song.tracks.first?.id }
        if let a = armedTrackID, !song.tracks.contains(where: { $0.id == a }) { armedTrackID = nil }
        if selectedRegion == nil { selectedRegionID = nil }
        if selectedFollowTrack == nil { selectedFollowTrackID = nil }
    }

    func updateRegion(trackID: UUID, regionID: UUID, undo: Bool = true, _ action: (inout Region) -> Void) {
        let apply: (inout Song) -> Void = { s in
            guard let ti = s.tracks.firstIndex(where: { $0.id == trackID }),
                  let ri = s.tracks[ti].regions.firstIndex(where: { $0.id == regionID }) else { return }
            action(&s.tracks[ti].regions[ri])
        }
        if undo { edit(apply) } else { mutate(apply) }
    }

    func updateTrack(_ id: UUID, undo: Bool = true, _ action: (inout Track) -> Void) {
        let apply: (inout Song) -> Void = { s in
            guard let ti = s.tracks.firstIndex(where: { $0.id == id }) else { return }
            action(&s.tracks[ti])
        }
        if undo { edit(apply) } else { mutate(apply) }
    }

    // MARK: - Tracks

    func addTrack(kind: TrackKind, instrument: InstrumentKind) {
        if song.tracks.count >= 16 {
            ErrorCenter.post("A song can have up to 16 tracks. Delete a track before adding another.")
            return
        }
        var name = kind == .audio ? "Audio" : instrument.displayName
        let existing = song.tracks.filter { $0.name == name || $0.name.hasPrefix(name + " ") }.count
        if existing > 0 { name += " \(existing + 1)" }
        var colorKey: TrackColorKey? = nil
        if kind == .audio {
            colorKey = song.tracks.contains(where: { $0.kind == .audio }) ? .audio2 : .vocal
        }
        let t = Track(name: name, kind: kind, instrument: instrument, colorKey: colorKey,
                      follow: kind == .instrument && instrument != .grandPiano && instrument != .ePiano ? true : false)
        edit { $0.tracks.append(t) }
        selectedTrackID = t.id
    }

    func deleteTrack(_ id: UUID) {
        edit { $0.tracks.removeAll { $0.id == id } }
        validateSelection()
    }

    func toggleMute(_ id: UUID) { updateTrack(id) { $0.muted.toggle() } }
    func toggleSolo(_ id: UUID) { updateTrack(id) { $0.solo.toggle() } }

    func toggleArm(_ id: UUID) {
        guard let t = song.tracks.first(where: { $0.id == id }) else { return }
        if armedTrackID == id {
            armedTrackID = nil
            engine.armInput(false)
            return
        }
        if t.kind == .audio {
            let session = AudioSessionManager.shared
            switch session.micState {
            case .denied:
                showMicDenied = true
                return
            case .undetermined:
                session.requestMic { [weak self] granted in
                    guard let self = self else { return }
                    if granted { self.arm(t) } else { self.showMicDenied = true }
                }
                return
            case .granted:
                break
            }
        }
        arm(t)
    }

    private func arm(_ t: Track) {
        armedTrackID = t.id
        selectedTrackID = t.id
        if t.kind == .audio {
            warnBluetoothOnce()
            engine.armInput(true) { [weak self] message in
                if let m = message {
                    ErrorCenter.post(m)
                    self?.armedTrackID = nil
                }
            }
        } else {
            engine.armInput(false)
        }
    }

    private func warnBluetoothOnce() {
        if AudioSessionManager.shared.isBluetoothOutput && !settings.bluetoothWarningShown {
            settings.bluetoothWarningShown = true
            ErrorCenter.post("Bluetooth headphones add delay. Use wired headphones or your interface for recording.", warning: true)
        }
    }

    private func updateLiveTarget() {
        if let t = selectedTrack, t.kind == .instrument {
            lastLiveInstrumentTrack = t.id
        }
        engine.setLiveTarget(trackID: lastLiveInstrumentTrack)
    }

    // MARK: - Zoom

    static let defaultBarPx: CGFloat = 64
    static let minBarPx: CGFloat = 24
    static let maxBarPx: CGFloat = 400

    var pxPerBar: CGFloat { pxPerBeat * CGFloat(max(1, song.beatsPerBar)) }

    /// Sets the zoom in points per bar (clamped) and remembers it for this project.
    func setZoom(pxPerBar bar: CGFloat) {
        let clamped = min(ProjectSession.maxBarPx, max(ProjectSession.minBarPx, bar))
        pxPerBeat = clamped / CGFloat(max(1, song.beatsPerBar))
        UserDefaults.standard.set(Double(clamped), forKey: "zoomPxPerBar.\(projectID.uuidString)")
    }

    // MARK: - Transport

    func play() {
        if isPlaying { return }
        var from = max(0, stoppedBeat)
        let range: ClosedRange<Double>? = cycleOn ? song.cycleBeatRange : nil
        if let r = range, from < r.lowerBound || from >= r.upperBound { from = r.lowerBound }
        if range == nil && from >= song.lengthBeats - 0.01 { from = 0 }
        let req = PlayRequest(fromBeat: from, cycle: range, countInBeats: 0, clickEnabled: settings.clickOn,
                              clickVolume: Float(settings.metronomeVolume), recordAudioTrack: nil, recordMIDI: false,
                              latencySeconds: 0)
        recordStartBeat = from
        followPaused = false
        isPlaying = true
        engine.play(req)
    }

    func stop() {
        guard isPlaying else { return }
        engine.stop()
    }

    func togglePlay() {
        if isPlaying { stop() } else { play() }
    }

    func rewind() {
        if isPlaying {
            guard !isRecording else { return }
            pendingRewind = true
            engine.stop()
        } else {
            stoppedBeat = cycleOn ? song.cycleBeatRange.lowerBound : 0
        }
    }

    func setPlayhead(_ beat: Double) {
        let b = max(0, beat)
        if isPlaying {
            guard !isRecording else { return }
            let range: ClosedRange<Double>? = cycleOn ? song.cycleBeatRange : nil
            let req = PlayRequest(fromBeat: b, cycle: range, countInBeats: 0, clickEnabled: settings.clickOn,
                                  clickVolume: Float(settings.metronomeVolume), recordAudioTrack: nil, recordMIDI: false,
                                  latencySeconds: 0)
            engine.play(req)
        } else {
            stoppedBeat = b
        }
    }

    func toggleRecord() {
        if isRecording {
            stop()
            return
        }
        guard let t = armedTrack else {
            ErrorCenter.post("Arm a track first: tap the circle on a track header, then press Record.", warning: true)
            return
        }
        if isPlaying { engine.stop() }
        if t.kind == .audio {
            switch AudioSessionManager.shared.micState {
            case .denied:
                showMicDenied = true
                return
            case .undetermined:
                AudioSessionManager.shared.requestMic { [weak self] granted in
                    guard let self = self else { return }
                    if granted { self.startRecording(t) } else { self.showMicDenied = true }
                }
                return
            case .granted:
                break
            }
        }
        startRecording(t)
    }

    private func startRecording(_ t: Track) {
        warnBluetoothOnce()
        let bpb = song.beatsPerBar
        var from = Double(song.barIndex(atBeat: stoppedBeat + bpb * 0.5 - 0.0001)) * bpb
        if from < 0 { from = 0 }
        let range: ClosedRange<Double>? = cycleOn ? song.cycleBeatRange : nil
        if let r = range { from = r.lowerBound }
        let latency = AudioSessionManager.shared.effectiveLatency(overrideMs: settings.latencyOverrideMs)
        let req = PlayRequest(fromBeat: from, cycle: range, countInBeats: Double(settings.countInBars) * bpb,
                              clickEnabled: settings.clickOn, clickVolume: Float(settings.metronomeVolume),
                              recordAudioTrack: t.kind == .audio ? t.id : nil, recordMIDI: t.kind == .instrument,
                              latencySeconds: latency)
        recordingTrackID = t.id
        recordStartBeat = from
        followPaused = false
        isPlaying = true
        isRecording = true
        engine.play(req)
    }

    private func handleStopped(_ r: StopResult) {
        let wasRecording = isRecording
        isPlaying = false
        isRecording = false
        playingBar = 0
        if wasRecording {
            commitRecording(r)
        } else if pendingRewind {
            stoppedBeat = cycleOn ? song.cycleBeatRange.lowerBound : 0
        } else {
            stoppedBeat = max(0, r.endBeat)
        }
        pendingRewind = false
        recordingTrackID = nil
    }

    private func commitRecording(_ r: StopResult) {
        defer { stoppedBeat = max(0, r.startBeat) }
        guard let trackID = recordingTrackID, let track = song.tracks.first(where: { $0.id == trackID }) else { return }
        if r.wasRecordingAudio {
            if let failure = r.audioError {
                ErrorCenter.post("Recording problem: \(failure). The take may be incomplete.")
            }
            guard let audio = r.audio else {
                ErrorCenter.post("Nothing was recorded. Check that your microphone or interface is connected and not muted.")
                return
            }
            commitAudio(r, audio: audio, track: track)
        } else if r.recordedMIDI {
            commitMIDI(r, track: track)
        }
    }

    private func commitAudio(_ r: StopResult, audio: RecordedAudio, track: Track) {
        let spb = r.spb
        let leadIn = r.hostStart - audio.firstSampleHost
        let c = r.countInBeats
        var takes: [Take] = []
        var regionStart = r.startBeat
        var regionLength: Double
        var active = 0
        if let loop = r.loop {
            let length = loop.upperBound - loop.lowerBound
            let lastLen = max(0, r.endBeat - loop.lowerBound)
            let passes = max(1, r.passes)
            for k in 0..<passes {
                let isLast = k == passes - 1
                let passLen = isLast ? min(length, lastLen) : length
                if isLast && k > 0 && passLen < 0.5 { continue }
                let offset = max(0, leadIn + (c + Double(k) * length) * spb + r.latencySeconds)
                let dur = min(max(0, audio.durationSeconds - offset), passLen * spb + 0.5)
                if dur < 0.05 { continue }
                takes.append(Take(name: "Take \(takes.count + 1)", fileName: audio.fileName, offset: offset, duration: dur))
            }
            regionStart = loop.lowerBound
            regionLength = length
            if takes.count == 1 { regionLength = max(0.5, min(length, lastLen == 0 ? length : max(lastLen, 0.5))) }
            active = max(0, takes.count - 1)
            if passes > 1 && takes.count > 1 {
                // Prefer the last complete pass.
                let lastComplete = takes.count - 1 - (lastLen < length - 0.01 ? 1 : 0)
                active = max(0, lastComplete)
            }
        } else {
            var offset = leadIn + c * spb + r.latencySeconds
            regionLength = max(0.25, r.endBeat - r.startBeat)
            if offset < 0 {
                let shift = -offset / spb
                regionStart += shift
                regionLength = max(0.25, regionLength - shift)
                offset = 0
            }
            let dur = max(0.05, audio.durationSeconds - offset)
            takes.append(Take(name: "Take 1", fileName: audio.fileName, offset: offset, duration: dur))
        }
        guard !takes.isEmpty else {
            ErrorCenter.post("The recording was too short to keep.")
            return
        }
        let region = Region(name: track.name, kind: .audio, startBeat: regionStart, lengthBeats: regionLength,
                            takes: takes, activeTake: active, audioOffset: 0)
        edit { s in
            s.clearRange(trackID: track.id, from: region.startBeat, to: region.endBeat)
            if let ti = s.trackIndex(track.id) {
                s.tracks[ti].regions.append(region)
                s.tracks[ti].regions.sort { $0.startBeat < $1.startBeat }
            }
        }
        selectedTrackID = track.id
        selectedRegionID = region.id
        editorOpen = true
        if takes.count > 1 { ErrorCenter.post("\(takes.count) takes were recorded. Pick one in the Takes editor.", warning: true) }
    }

    private func commitMIDI(_ r: StopResult, track: Track) {
        guard !r.midiNotes.isEmpty else {
            ErrorCenter.post("No notes were recorded. Check that your keyboard is connected, or use the on-screen keyboard.", warning: true)
            return
        }
        let bpb = song.beatsPerBar
        var start = r.startBeat
        var end = r.midiNotes.map { $0.start + $0.length }.max() ?? start
        if let loop = r.loop {
            start = loop.lowerBound
            end = loop.upperBound
        } else {
            end = max(end, start + bpb)
            end = ceil(end / bpb - 1e-9) * bpb
        }
        var notes: [Note] = []
        for n in r.midiNotes where n.start >= start - 0.05 {
            let rel = max(0, n.start - start)
            if rel >= end - start { continue }
            notes.append(Note(pitch: n.pitch, start: rel, length: min(n.length, end - start - rel), velocity: n.velocity))
        }
        let pedal = r.pedal.filter { $0.beat >= start && $0.beat < end }.map { PedalEvent(beat: $0.beat - start, down: $0.down) }
        guard !notes.isEmpty else {
            ErrorCenter.post("No notes were recorded inside the recording range.", warning: true)
            return
        }
        let region = Region(name: track.name, kind: .midi, startBeat: start, lengthBeats: end - start, notes: notes, pedal: pedal)
        edit { s in
            if let ti = s.trackIndex(track.id) {
                s.tracks[ti].regions.append(region)
                s.tracks[ti].regions.sort { $0.startBeat < $1.startBeat }
            }
        }
        selectedTrackID = track.id
        selectedRegionID = region.id
        editorOpen = true
    }

    // MARK: - Chords

    /// Notes used when auditioning a chord on the selected instrument.
    func auditionChord(_ chord: Chord) {
        guard let id = lastLiveInstrumentTrack, let t = song.tracks.first(where: { $0.id == id }) else {
            ErrorCenter.post("Add an instrument track to hear chords.", warning: true)
            return
        }
        if t.instrument.isDrums {
            ErrorCenter.post("Select a pitched instrument track to hear chords.", warning: true)
            return
        }
        var pitches = BandGenerator.voicing(chord, low: 55)
        let bass = BandGenerator.pitch(forPitchClass: chord.bassPitchClass, atOrAbove: 36)
        pitches.insert(bass, at: 0)
        engine.audition(trackID: id, pitches: pitches)
    }

    /// Writes a chord at the playhead, snapped to the half bar.
    func writeChordAtPlayhead(_ chord: Chord) {
        let half = song.beatsPerBar / 2
        let beat = max(0, (displayBeat() / half).rounded(.down) * half)
        edit { $0.setChord(chord, atBeat: beat) }
    }

    /// Adds an empty MIDI region (one bar at the playhead) to an instrument track so notes can be drawn in.
    func addEmptyRegion(trackID: UUID) {
        guard let t = song.tracks.first(where: { $0.id == trackID }), t.kind == .instrument else {
            ErrorCenter.post("Select an instrument track first.", warning: true)
            return
        }
        let bpb = song.beatsPerBar
        let start = Double(song.barIndex(atBeat: max(0, displayBeat()) + 0.0001)) * bpb
        let region = Region(name: t.name, kind: .midi, startBeat: start, lengthBeats: bpb * 2)
        edit { s in
            if let ti = s.trackIndex(trackID) {
                s.tracks[ti].regions.append(region)
                s.tracks[ti].regions.sort { $0.startBeat < $1.startBeat }
            }
        }
        selectedRegionID = region.id
        editorOpen = true
    }

    // MARK: - Cycle

    func setCycle(startBar: Int, endBar: Int) {
        mutate { s in
            s.cycle = CycleRange(startBar: max(0, startBar), endBar: max(startBar + 1, endBar))
        }
    }

    // MARK: - Saving

    func saveNow(synchronous: Bool = false) {
        let copy = song
        let store = self.store
        if synchronous {
            saveQueue.sync {
                do { try store.save(copy) } catch { ErrorCenter.report(error, while: "save the project") }
            }
        } else {
            saveQueue.async {
                do { try store.save(copy) } catch { ErrorCenter.report(error, while: "save the project") }
            }
        }
    }

    var audioDir: URL { store.audioDir(projectID) }
}
