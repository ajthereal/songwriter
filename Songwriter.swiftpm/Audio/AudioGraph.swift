import AVFoundation
import AudioToolbox

/// The nodes belonging to one song track.
final class TrackNodes {
    let id: UUID
    let kind: TrackKind
    var instrument: InstrumentKind
    let sampler: AVAudioUnitSampler?
    let player: AVAudioPlayerNode?
    let eq: AVAudioUnitEQ?
    let comp: AVAudioUnitEffect?
    let mixer = AVAudioMixerNode()
    var loadedInstrument: InstrumentKind?
    var busIndex: Int = 0

    init(track: Track) {
        id = track.id
        kind = track.kind
        instrument = track.instrument
        if track.kind == .instrument {
            sampler = AVAudioUnitSampler()
            player = nil
            eq = nil
            comp = nil
        } else {
            sampler = nil
            player = AVAudioPlayerNode()
            let e = AVAudioUnitEQ(numberOfBands: 2)
            e.bands[0].filterType = .highPass
            e.bands[0].frequency = 90
            e.bands[0].bandwidth = 0.5
            e.bands[0].bypass = false
            e.bands[1].filterType = .parametric
            e.bands[1].frequency = 3500
            e.bands[1].bandwidth = 1.0
            e.bands[1].gain = 2.0
            e.bands[1].bypass = false
            eq = e
            let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                 componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                                 componentManufacturer: kAudioUnitManufacturer_Apple,
                                                 componentFlags: 0, componentFlagsMask: 0)
            let c = AVAudioUnitEffect(audioComponentDescription: desc)
            AudioUnitSetParameter(c.audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -18, 0)
            AudioUnitSetParameter(c.audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 6, 0)
            AudioUnitSetParameter(c.audioUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.012, 0)
            AudioUnitSetParameter(c.audioUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.15, 0)
            comp = c
        }
    }

    var allNodes: [AVAudioNode] {
        var out: [AVAudioNode] = []
        if let s = sampler { out.append(s) }
        if let p = player { out.append(p) }
        if let e = eq { out.append(e) }
        if let c = comp { out.append(c) }
        out.append(mixer)
        return out
    }
}

/// Builds the node graph for a song. Used by the live engine and by the offline bouncer.
final class AudioGraph {
    let engine: AVAudioEngine
    let stereo: AVAudioFormat
    let mono: AVAudioFormat
    let sumMixer = AVAudioMixerNode()
    let reverbMixer = AVAudioMixerNode()
    let reverb = AVAudioUnitReverb()
    let limiter: AVAudioUnitEffect
    let monitorMixer = AVAudioMixerNode()
    private(set) var nodes: [UUID: TrackNodes] = [:]
    private var fixedAttached = false
    var soundFontURL: URL?
    /// Plain English problems found while building the graph.
    private(set) var issues: [String] = []

    init(engine: AVAudioEngine, sampleRate: Double = 48000) {
        self.engine = engine
        stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_PeakLimiter,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.005, 0)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.05, 0)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 0, 0)
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 100
    }

    func takeIssues() -> [String] {
        let i = issues
        issues = []
        return i
    }

    func sampler(for id: UUID) -> AVAudioUnitSampler? { nodes[id]?.sampler }
    func player(for id: UUID) -> AVAudioPlayerNode? { nodes[id]?.player }

    private func attachFixedNodes() {
        guard !fixedAttached else { return }
        engine.attach(sumMixer)
        engine.attach(reverbMixer)
        engine.attach(reverb)
        engine.attach(limiter)
        engine.attach(monitorMixer)
        fixedAttached = true
    }

    /// Creates, removes and reconnects nodes so the graph matches the song.
    /// - Parameter only: build just this track (used for stems).
    func configure(song: Song, only: UUID? = nil) {
        attachFixedNodes()
        let wanted = song.tracks.filter { only == nil || $0.id == only }

        // Remove nodes of deleted tracks.
        let wantedIDs = Set(wanted.map { $0.id })
        for (id, n) in nodes where !wantedIDs.contains(id) {
            for node in n.allNodes {
                engine.disconnectNodeOutput(node)
                engine.disconnectNodeInput(node)
                engine.detach(node)
            }
            nodes.removeValue(forKey: id)
        }

        // Create new nodes.
        for t in wanted {
            if let existing = nodes[t.id], existing.kind != t.kind {
                for node in existing.allNodes {
                    engine.disconnectNodeOutput(node)
                    engine.detach(node)
                }
                nodes.removeValue(forKey: t.id)
            }
            if nodes[t.id] == nil {
                let n = TrackNodes(track: t)
                for node in n.allNodes { engine.attach(node) }
                nodes[t.id] = n
            }
            if let n = nodes[t.id] {
                n.instrument = t.instrument
                if t.kind == .instrument { loadInstrument(n) }
            }
        }

        // Disconnect everything we own, then reconnect from scratch.
        engine.disconnectNodeOutput(sumMixer)
        engine.disconnectNodeOutput(reverbMixer)
        engine.disconnectNodeOutput(reverb)
        engine.disconnectNodeOutput(limiter)
        for n in nodes.values {
            for node in n.allNodes { engine.disconnectNodeOutput(node) }
        }

        engine.connect(reverbMixer, to: reverb, format: stereo)
        engine.connect(reverb, to: sumMixer, fromBus: 0, toBus: 0, format: stereo)
        engine.connect(sumMixer, to: limiter, format: stereo)
        engine.connect(limiter, to: engine.mainMixerNode, fromBus: 0, toBus: 0, format: stereo)
        engine.connect(monitorMixer, to: engine.mainMixerNode, fromBus: 0, toBus: 1, format: stereo)
        monitorMixer.outputVolume = 0

        for (i, t) in wanted.enumerated() {
            guard let n = nodes[t.id] else { continue }
            n.busIndex = i
            if t.kind == .instrument, let s = n.sampler {
                engine.connect(s, to: n.mixer, format: stereo)
                engine.connect(n.mixer, to: sumMixer, fromBus: 0, toBus: 1 + i, format: stereo)
            } else if let p = n.player, let e = n.eq, let c = n.comp {
                engine.connect(p, to: e, format: mono)
                engine.connect(e, to: c, format: mono)
                engine.connect(c, to: n.mixer, format: mono)
                let points = [AVAudioConnectionPoint(node: sumMixer, bus: 1 + i),
                              AVAudioConnectionPoint(node: reverbMixer, bus: i)]
                engine.connect(n.mixer, to: points, fromBus: 0, format: stereo)
            }
        }
        applyMix(song: song)
    }

    private func loadInstrument(_ n: TrackNodes) {
        guard let sampler = n.sampler else { return }
        if n.loadedInstrument == n.instrument { return }
        guard let url = soundFontURL else {
            issues.append("The built-in sounds were not found, so instrument tracks will be silent.")
            return
        }
        do {
            let melodic = UInt8(kAUSampler_DefaultMelodicBankMSB)
            let percussion = UInt8(kAUSampler_DefaultPercussionBankMSB)
            let lsb = UInt8(kAUSampler_DefaultBankLSB)
            try sampler.loadSoundBankInstrument(at: url,
                                                program: UInt8(n.instrument.program),
                                                bankMSB: n.instrument.isDrums ? percussion : melodic,
                                                bankLSB: lsb)
            n.loadedInstrument = n.instrument
        } catch {
            n.loadedInstrument = nil
            issues.append("Could not load the \(n.instrument.displayName) sound. \(ErrorCenter.describe(error))")
        }
    }

    /// Whether a track is audible given mute and solo states.
    static func isAudible(_ t: Track, in song: Song) -> Bool {
        if t.muted { return false }
        let anySolo = song.tracks.contains { $0.solo }
        return !anySolo || t.solo
    }

    func applyMix(song: Song) {
        for t in song.tracks {
            guard let n = nodes[t.id] else { continue }
            let audible = AudioGraph.isAudible(t, in: song)
            n.mixer.outputVolume = audible ? Float(max(0, min(1.25, t.volume))) : 0
            n.mixer.pan = Float(max(-1, min(1, t.pan)))
            if t.kind == .audio {
                n.eq?.bypass = !t.vocalChain
                n.comp?.bypass = !t.vocalChain
                if let dest = n.mixer.destination(forMixer: reverbMixer, bus: n.busIndex) {
                    dest.volume = t.vocalChain ? Float(max(0, min(1, t.reverbAmount))) : 0
                }
            }
        }
    }
}
