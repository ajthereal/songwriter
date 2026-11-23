import Foundation

/// A note at an absolute beat position.
struct AbsNote: Equatable {
    var start: Double
    var length: Double
    var pitch: Int
    var velocity: Int
}

/// Generates accompaniment parts from the chord track. Fully deterministic.
enum BandGenerator {
    private enum Role {
        case root
        case fifth
        case octave
        case chord
        case arp(Int)
    }

    private struct Hit {
        var pos: Double
        var len: Double
        var role: Role
        var vel: Int
    }

    // MARK: Public

    static func generate(song: Song, instrument: InstrumentKind, style: BandStyle,
                         from: Double = 0, to: Double? = nil) -> [AbsNote] {
        if style == .drumsOff { return [] }
        let end = to ?? song.lengthBeats
        var notes: [AbsNote]
        if instrument.isDrums {
            notes = drums(song: song, style: style)
        } else {
            notes = harmonic(song: song, instrument: instrument, style: style)
        }
        var out: [AbsNote] = []
        for n in notes where n.start >= from - 1e-9 && n.start < end - 1e-9 {
            var m = n
            m.length = max(0.05, min(n.length, end - n.start))
            out.append(m)
        }
        out.sort { a, b in
            if abs(a.start - b.start) > 1e-9 { return a.start < b.start }
            return a.pitch < b.pitch
        }
        return out
    }

    /// Voicing of a chord: each chord tone placed in [low, low + 12), ascending.
    static func voicing(_ chord: Chord, low: Int) -> [Int] {
        var out: [Int] = []
        for pc in chord.pitchClasses {
            var p = low + (((pc - low) % 12) + 12) % 12
            if p < low { p += 12 }
            out.append(p)
        }
        return out.sorted()
    }

    /// Lowest pitch with the given pitch class at or above `low`.
    static func pitch(forPitchClass pc: Int, atOrAbove low: Int) -> Int {
        low + (((pc - low) % 12) + 12) % 12
    }

    /// Deterministic pseudo random value used for small velocity variation.
    static func hash(_ a: Int, _ b: Int, _ c: Int) -> Int {
        var h: UInt64 = 1469598103934665603
        for v in [a, b, c] {
            h ^= UInt64(bitPattern: Int64(v))
            h = h &* 1099511628211
            h ^= (h >> 29)
        }
        return Int(h >> 33)
    }

    private static func humanize(_ base: Int, _ a: Int, _ b: Int, _ c: Int) -> Int {
        let v = base + (hash(a, b, c) % 9) - 4
        return max(1, min(127, v))
    }

    // MARK: Harmonic instruments

    private static func patterns(style: BandStyle, bpb: Double) -> [Hit] {
        var hits: [Hit] = []
        let eighths = Int(bpb * 2 + 0.001)
        switch style {
        case .pianoBallad:
            hits.append(Hit(pos: 0, len: bpb * 0.98, role: .root, vel: 62))
            let seq = [0, 1, 2, 3, 2, 1, 2, 1]
            for j in 0..<eighths {
                hits.append(Hit(pos: Double(j) * 0.5, len: 0.5, role: .arp(seq[j % seq.count]), vel: 54))
            }
        case .pianoPop:
            hits.append(Hit(pos: 0, len: 1.5, role: .root, vel: 68))
            hits.append(Hit(pos: 2, len: 1.5, role: .root, vel: 62))
            let pos: [Double] = [0, 1.5, 2, 3.5]
            let len: [Double] = [1.0, 0.5, 1.5, 0.5]
            for i in 0..<pos.count {
                hits.append(Hit(pos: pos[i], len: len[i], role: .chord, vel: i == 0 ? 66 : 58))
            }
        case .pianoSustained:
            hits.append(Hit(pos: 0, len: bpb * 0.98, role: .root, vel: 60))
            hits.append(Hit(pos: 0, len: bpb * 0.98, role: .chord, vel: 56))
        case .epPads:
            hits.append(Hit(pos: 0, len: bpb * 0.99, role: .chord, vel: 50))
        case .epComp:
            let pos: [Double] = [0, 1.5, 2.5, 3.5]
            let len: [Double] = [0.75, 0.75, 0.75, 0.5]
            for i in 0..<pos.count {
                hits.append(Hit(pos: pos[i], len: len[i], role: .chord, vel: 58))
            }
        case .padSustained:
            hits.append(Hit(pos: 0, len: bpb * 0.99, role: .chord, vel: 52))
        case .bassRoots:
            hits.append(Hit(pos: 0, len: bpb * 0.95, role: .root, vel: 86))
        case .bassRootFive:
            hits.append(Hit(pos: 0, len: 1.9, role: .root, vel: 88))
            hits.append(Hit(pos: 2, len: 1.9, role: .fifth, vel: 78))
        case .bassEighths:
            for j in 0..<eighths {
                let pos = Double(j) * 0.5
                let isOctave = (j % 4 == 3)
                hits.append(Hit(pos: pos, len: 0.45, role: isOctave ? .octave : .root, vel: j % 2 == 0 ? 88 : 74))
            }
        case .drumsBallad, .drumsPop, .drumsHalfTime, .drumsOff:
            break
        }
        return hits
    }

    private static func harmonic(song: Song, instrument: InstrumentKind, style: BandStyle) -> [AbsNote] {
        let bpb = song.beatsPerBar
        let allHits = patterns(style: style, bpb: bpb)
        if allHits.isEmpty { return [] }
        let voicingLow: Int
        switch instrument {
        case .grandPiano: voicingLow = 57
        case .ePiano: voicingLow = 55
        case .pad: voicingLow = 57
        case .strings: voicingLow = 55
        default: voicingLow = 57
        }
        let bassLow = 28
        var out: [AbsNote] = []

        for span in song.chordSpans() {
            let chord = span.chord
            let voice = voicing(chord, low: voicingLow)
            let leftRoot = pitch(forPitchClass: chord.bassPitchClass, atOrAbove: 36)
            let bassRoot = pitch(forPitchClass: chord.bassPitchClass, atOrAbove: bassLow)
            let bassFifth = pitch(forPitchClass: chord.bassPitchClass + 7, atOrAbove: bassRoot)
            var cellStart = span.start
            while cellStart < span.end - 1e-9 {
                let barIndex = Int(floor(cellStart / bpb + 1e-9))
                let barStart = Double(barIndex) * bpb
                let cellEnd = min(span.end, barStart + bpb)
                let rs = cellStart - barStart
                let re = cellEnd - barStart

                var hits = allHits.filter { $0.pos >= rs - 1e-9 && $0.pos < re - 1e-9 }
                // Make sure there is an attack at the chord change.
                let hasAttack = hits.contains { abs($0.pos - rs) < 1e-9 }
                if !hasAttack {
                    let template = allHits.first { $0.pos >= 0 } ?? allHits[0]
                    let next = hits.first?.pos ?? re
                    hits.insert(Hit(pos: rs, len: max(0.25, next - rs), role: template.role, vel: template.vel), at: 0)
                }

                for h in hits {
                    let start = barStart + h.pos
                    let length = min(h.len, cellEnd - start)
                    if length < 0.05 { continue }
                    let vel = humanize(h.vel, barIndex, Int(h.pos * 4), instrument.program)
                    switch h.role {
                    case .root:
                        let p = instrument == .bass ? bassRoot : leftRoot
                        out.append(AbsNote(start: start, length: length, pitch: p, velocity: vel))
                    case .fifth:
                        out.append(AbsNote(start: start, length: length, pitch: bassFifth, velocity: vel))
                    case .octave:
                        out.append(AbsNote(start: start, length: length, pitch: bassRoot + 12, velocity: vel))
                    case .chord:
                        for p in voice {
                            out.append(AbsNote(start: start, length: length, pitch: p, velocity: vel))
                        }
                    case .arp(let idx):
                        if !voice.isEmpty {
                            let p = voice[idx % voice.count]
                            out.append(AbsNote(start: start, length: length, pitch: p, velocity: vel))
                        }
                    }
                }
                cellStart = cellEnd
            }
        }
        return out
    }

    // MARK: Drums

    private struct DrumHit {
        var pos: Double
        var note: Int
        var vel: Int
    }

    private static func drumBar(style: BandStyle, bpb: Double, compound: Bool) -> [DrumHit] {
        var hits: [DrumHit] = []
        let eighths = Int(bpb * 2 + 0.001)
        let kickVel = 100
        func hats(_ strong: Int, _ weak: Int) {
            for j in 0..<eighths {
                hits.append(DrumHit(pos: Double(j) * 0.5, note: 42, vel: j % 2 == 0 ? strong : weak))
            }
        }
        if compound {
            hits.append(DrumHit(pos: 0, note: 36, vel: kickVel))
            hits.append(DrumHit(pos: 1.5, note: style == .drumsBallad ? 37 : 38, vel: 92))
            hats(style == .drumsBallad ? 56 : 70, style == .drumsBallad ? 40 : 52)
            return hits
        }
        if abs(bpb - 3) < 1e-9 {
            hits.append(DrumHit(pos: 0, note: 36, vel: kickVel))
            hits.append(DrumHit(pos: 1, note: style == .drumsBallad ? 37 : 38, vel: 88))
            hits.append(DrumHit(pos: 2, note: style == .drumsBallad ? 37 : 38, vel: 84))
            hats(style == .drumsBallad ? 56 : 70, style == .drumsBallad ? 40 : 52)
            return hits
        }
        switch style {
        case .drumsBallad:
            hits.append(DrumHit(pos: 0, note: 36, vel: kickVel - 6))
            hits.append(DrumHit(pos: 2.5, note: 36, vel: kickVel - 14))
            hits.append(DrumHit(pos: 1, note: 37, vel: 86))
            hits.append(DrumHit(pos: 3, note: 37, vel: 90))
            hats(54, 38)
        case .drumsPop:
            hits.append(DrumHit(pos: 0, note: 36, vel: kickVel))
            hits.append(DrumHit(pos: 2, note: 36, vel: kickVel - 8))
            hits.append(DrumHit(pos: 2.5, note: 36, vel: kickVel - 16))
            hits.append(DrumHit(pos: 1, note: 38, vel: 98))
            hits.append(DrumHit(pos: 3, note: 38, vel: 100))
            hats(74, 54)
        case .drumsHalfTime:
            hits.append(DrumHit(pos: 0, note: 36, vel: kickVel))
            hits.append(DrumHit(pos: 2.5, note: 36, vel: kickVel - 14))
            hits.append(DrumHit(pos: 2, note: 38, vel: 102))
            hats(68, 48)
        default:
            break
        }
        return hits
    }

    private static func drums(song: Song, style: BandStyle) -> [AbsNote] {
        let bpb = song.beatsPerBar
        let compound = song.timeSignature.isCompound
        let template = drumBar(style: style, bpb: bpb, compound: compound)
        if template.isEmpty { return [] }
        var out: [AbsNote] = []
        let bars = song.totalBars
        for bar in 0..<bars {
            let barStart = Double(bar) * bpb
            var hits = template
            let sectionIdx = song.sections.firstIndex { bar >= $0.startBar && bar < $0.endBar }
            var isFirstBar = false
            var isLastBar = false
            var hasNextSection = false
            if let si = sectionIdx {
                let s = song.sections[si]
                isFirstBar = bar == s.startBar
                isLastBar = bar == s.endBar - 1
                hasNextSection = si + 1 < song.sections.count
            }
            if isLastBar && hasNextSection && bpb >= 3 {
                hits.removeAll { $0.pos >= bpb - 1 - 1e-9 }
                hits.append(DrumHit(pos: bpb - 1, note: 38, vel: 78))
                hits.append(DrumHit(pos: bpb - 0.75, note: 38, vel: 70))
                hits.append(DrumHit(pos: bpb - 0.5, note: 47, vel: 84))
                hits.append(DrumHit(pos: bpb - 0.25, note: 45, vel: 90))
            }
            if isFirstBar, let si = sectionIdx, si > 0 {
                hits.append(DrumHit(pos: 0, note: 49, vel: 92))
            }
            for h in hits {
                let vel = humanize(h.vel, bar, Int(h.pos * 4), h.note)
                out.append(AbsNote(start: barStart + h.pos, length: 0.2, pitch: h.note, velocity: vel))
            }
        }
        return out
    }
}

// MARK: - Playback notes

extension Song {
    /// All notes a track plays, as absolute beats: generated (follow chords) plus region notes.
    func playbackNotes(for track: Track) -> [AbsNote] {
        guard track.kind == .instrument else { return [] }
        var out: [AbsNote] = []
        if track.follow {
            out.append(contentsOf: BandGenerator.generate(song: self, instrument: track.instrument, style: track.style))
        }
        for r in track.regions where r.kind == .midi {
            for n in r.notes {
                let start = r.startBeat + n.start
                if n.start >= r.lengthBeats - 1e-9 { continue }
                let len = min(n.length, r.lengthBeats - n.start)
                if len <= 0 { continue }
                out.append(AbsNote(start: start, length: len, pitch: n.pitch, velocity: n.velocity))
            }
        }
        out.sort { a, b in
            if abs(a.start - b.start) > 1e-9 { return a.start < b.start }
            return a.pitch < b.pitch
        }
        return out
    }

    func playbackPedal(for track: Track) -> [PedalEvent] {
        guard track.kind == .instrument else { return [] }
        var out: [PedalEvent] = []
        for r in track.regions where r.kind == .midi {
            for p in r.pedal where p.beat < r.lengthBeats {
                out.append(PedalEvent(beat: r.startBeat + p.beat, down: p.down))
            }
        }
        out.sort { $0.beat < $1.beat }
        return out
    }

    /// Converts the generated part of a track into one MIDI region per section and turns follow mode off.
    mutating func makeEditable(trackID: UUID) {
        guard let ti = trackIndex(trackID) else { return }
        let track = tracks[ti]
        guard track.kind == .instrument, track.follow else { return }
        var regions: [Region] = []
        let ranges: [(String, Double, Double)]
        if sections.isEmpty {
            ranges = [(track.name, 0, lengthBeats)]
        } else {
            ranges = sections.map { s in
                (s.name, barStartBeat(s.startBar), barStartBeat(s.endBar))
            }
        }
        for (name, a, b) in ranges {
            let gen = BandGenerator.generate(song: self, instrument: track.instrument, style: track.style, from: a, to: b)
            if gen.isEmpty { continue }
            let notes = gen.map { Note(pitch: $0.pitch, start: $0.start - a, length: $0.length, velocity: $0.velocity) }
            regions.append(Region(name: name, kind: .midi, startBeat: a, lengthBeats: b - a, notes: notes))
        }
        tracks[ti].regions.append(contentsOf: regions)
        tracks[ti].regions.sort { $0.startBeat < $1.startBeat }
        tracks[ti].follow = false
    }
}
