import Foundation

struct ChordSpan: Equatable {
    var start: Double
    var end: Double
    var chord: Chord
}

// MARK: - Timing

extension Song {
    var beatsPerBar: Double { timeSignature.beatsPerBar }
    var secondsPerBeat: Double { 60.0 / max(tempo, 1) }

    func beatsToSeconds(_ beats: Double) -> Double { beats * secondsPerBeat }
    func secondsToBeats(_ seconds: Double) -> Double { seconds / secondsPerBeat }
    func barStartBeat(_ bar: Int) -> Double { Double(bar) * beatsPerBar }

    /// 0-based bar index containing a beat.
    func barIndex(atBeat beat: Double) -> Int {
        Int(floor(beat / beatsPerBar + 1e-9))
    }

    var sectionsEndBar: Int { sections.map { $0.startBar + $0.lengthBars }.max() ?? 0 }

    var contentEndBeat: Double {
        var end = 0.0
        for t in tracks {
            for r in t.regions { end = max(end, r.endBeat) }
        }
        if let lastChord = chords.map({ $0.startBeat }).max() { end = max(end, lastChord + 0.001) }
        return end
    }

    var totalBars: Int {
        let contentBars = Int(ceil(contentEndBeat / beatsPerBar - 1e-9))
        return max(sectionsEndBar, contentBars, 1)
    }

    var lengthBeats: Double { Double(totalBars) * beatsPerBar }

    func sectionIndex(atBeat beat: Double) -> Int? {
        let bar = barIndex(atBeat: beat)
        return sections.firstIndex { bar >= $0.startBar && bar < $0.startBar + $0.lengthBars }
    }

    func section(withID id: UUID) -> SongSection? { sections.first { $0.id == id } }

    func sectionBeatRange(_ s: SongSection) -> ClosedRange<Double> {
        barStartBeat(s.startBar)...barStartBeat(s.startBar + s.lengthBars)
    }

    /// The beat range used when cycle is on.
    var cycleBeatRange: ClosedRange<Double> {
        let a = max(0, min(cycle.startBar, cycle.endBar - 1))
        let b = max(a + 1, cycle.endBar)
        return barStartBeat(a)...barStartBeat(b)
    }

    func formattedPosition(beat: Double) -> (bar: Int, beat: Int) {
        let bpb = beatsPerBar
        let bar = Int(floor(beat / bpb + 1e-9))
        let inBar = beat - Double(bar) * bpb
        let interval = timeSignature.isCompound ? 1.5 : 1.0
        let b = Int(floor(inBar / interval + 1e-9)) + 1
        return (bar + 1, b)
    }
}

// MARK: - Chords

extension Song {
    func chordSpans() -> [ChordSpan] {
        let sorted = chords.sorted { $0.startBeat < $1.startBeat }
        var out: [ChordSpan] = []
        let total = lengthBeats
        for (i, e) in sorted.enumerated() {
            let end = i + 1 < sorted.count ? sorted[i + 1].startBeat : total
            if end > e.startBeat + 1e-9 && e.startBeat < total - 1e-9 {
                out.append(ChordSpan(start: e.startBeat, end: end, chord: e.chord))
            }
        }
        return out
    }

    func chord(atBeat beat: Double) -> Chord? {
        var found: Chord? = nil
        for e in chords.sorted(by: { $0.startBeat < $1.startBeat }) {
            if e.startBeat <= beat + 1e-9 { found = e.chord } else { break }
        }
        return found
    }

    /// Sets (or clears when nil) the chord that starts exactly at `beat`.
    mutating func setChord(_ chord: Chord?, atBeat beat: Double) {
        chords.removeAll { abs($0.startBeat - beat) < 1e-6 }
        if let c = chord { chords.append(ChordEvent(startBeat: beat, chord: c)) }
        chords.sort { $0.startBeat < $1.startBeat }
    }

    func chordEvent(atBeat beat: Double) -> ChordEvent? {
        chords.first { abs($0.startBeat - beat) < 1e-6 }
    }
}

// MARK: - Sections

extension Song {
    private func offsetRange(_ s: SongSection, _ bpb: Double) -> (Double, Double) {
        (Double(s.startBar) * bpb, Double(s.startBar + s.lengthBars) * bpb)
    }

    /// Recomputes `startBar` so sections are contiguous from bar 0.
    static func normalized(_ sections: [SongSection]) -> [SongSection] {
        var out = sections
        var bar = 0
        for i in out.indices {
            out[i].startBar = bar
            bar += out[i].lengthBars
        }
        return out
    }

    /// Replaces the section list and moves chords and regions along with their sections.
    /// - Parameter clip: trim regions that spill past the end of their (resized) section.
    mutating func replaceSections(_ newSectionsRaw: [SongSection], clip: Bool = false) {
        let bpb = beatsPerBar
        let old = sections
        let new = Song.normalized(newSectionsRaw)
        let oldEnd = Double(old.map { $0.startBar + $0.lengthBars }.max() ?? 0) * bpb
        let newEnd = Double(new.map { $0.startBar + $0.lengthBars }.max() ?? 0) * bpb

        /// Returns the new start and the end of the destination section, or nil when the item is dropped.
        func map(_ s: Double) -> (start: Double, limit: Double)? {
            for o in old {
                let (a, b) = offsetRange(o, bpb)
                if s >= a - 1e-9 && s < b - 1e-9 {
                    guard let n = new.first(where: { $0.id == o.id }) else { return nil }
                    let (na, nb) = offsetRange(n, bpb)
                    let t = s - a + na
                    if t < nb - 1e-9 { return (t, nb) }
                    return nil
                }
            }
            if s >= oldEnd - 1e-9 { return (s + (newEnd - oldEnd), Double.greatestFiniteMagnitude) }
            return (s, Double.greatestFiniteMagnitude)
        }

        var newChords: [ChordEvent] = []
        for c in chords {
            if let m = map(c.startBeat) {
                var e = c
                e.startBeat = m.start
                newChords.append(e)
            }
        }
        chords = newChords.sorted { $0.startBeat < $1.startBeat }

        for ti in tracks.indices {
            var regions: [Region] = []
            for r in tracks[ti].regions {
                guard let m = map(r.startBeat) else { continue }
                var nr = r
                nr.startBeat = m.start
                if clip && nr.endBeat > m.limit + 1e-9 {
                    nr = Song.clipped(nr, toLength: m.limit - nr.startBeat)
                }
                if nr.lengthBeats > 1e-6 { regions.append(nr) }
            }
            tracks[ti].regions = regions.sorted { $0.startBeat < $1.startBeat }
        }
        sections = new
        let total = totalBars
        cycle.endBar = min(max(cycle.endBar, 1), max(total, 1))
        cycle.startBar = min(cycle.startBar, cycle.endBar - 1)
        if cycle.startBar < 0 { cycle.startBar = 0 }
    }

    static func clipped(_ region: Region, toLength length: Double) -> Region {
        var r = region
        let len = max(0, length)
        r.lengthBeats = len
        r.notes = r.notes.compactMap { n in
            if n.start >= len - 1e-9 { return nil }
            var m = n
            m.length = min(n.length, len - n.start)
            return m
        }
        r.pedal = r.pedal.filter { $0.beat < len }
        return r
    }

    @discardableResult
    mutating func addSection(name: String, letter: String, bars: Int, at index: Int? = nil) -> UUID {
        let s = SongSection(name: name, letter: letter, lengthBars: max(1, min(bars, 64)))
        var list = sections
        let i = min(max(index ?? list.count, 0), list.count)
        list.insert(s, at: i)
        replaceSections(list)
        return s.id
    }

    mutating func deleteSection(id: UUID) {
        guard sections.count > 1 else { return }
        replaceSections(sections.filter { $0.id != id })
    }

    mutating func renameSection(id: UUID, name: String, letter: String? = nil) {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
        sections[i].name = name
        if let l = letter { sections[i].letter = l }
    }

    mutating func resizeSection(id: UUID, bars: Int) {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return }
        var list = sections
        list[i].lengthBars = max(1, min(bars, 64))
        replaceSections(list, clip: true)
    }

    /// Moves the section at `from` so it ends up at index `to` (index in the resulting array).
    mutating func moveSection(from: Int, to: Int) {
        guard sections.indices.contains(from) else { return }
        var list = sections
        let s = list.remove(at: from)
        let dest = min(max(to, 0), list.count)
        list.insert(s, at: dest)
        replaceSections(list)
    }

    /// Inserts a copy of the section (with its chords and regions) right after the original.
    @discardableResult
    mutating func duplicateSection(id: UUID) -> UUID? {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { return nil }
        let bpb = beatsPerBar
        let original = sections[i]
        var copy = original
        copy.id = UUID()
        var list = sections
        list.insert(copy, at: i + 1)
        replaceSections(list)

        // After the relayout the original keeps its range and the copy's range is empty; fill it.
        guard let o = section(withID: original.id), let c = section(withID: copy.id) else { return nil }
        let oStart = Double(o.startBar) * bpb
        let oEnd = Double(o.endBar) * bpb
        let shift = Double(c.startBar - o.startBar) * bpb
        var addedChords: [ChordEvent] = []
        for e in chords where e.startBeat >= oStart - 1e-9 && e.startBeat < oEnd - 1e-9 {
            addedChords.append(ChordEvent(startBeat: e.startBeat + shift, chord: e.chord))
        }
        chords.append(contentsOf: addedChords)
        chords.sort { $0.startBeat < $1.startBeat }
        for ti in tracks.indices {
            var extra: [Region] = []
            for r in tracks[ti].regions where r.startBeat >= oStart - 1e-9 && r.startBeat < oEnd - 1e-9 {
                var nr = r.copyWithNewIDs()
                nr.startBeat += shift
                extra.append(nr)
            }
            tracks[ti].regions.append(contentsOf: extra)
            tracks[ti].regions.sort { $0.startBeat < $1.startBeat }
        }
        return copy.id
    }
}

// MARK: - Time signature

extension Song {
    /// Changes the time signature and rescales positions so every bar stays at the same bar number.
    mutating func setTimeSignature(_ new: TimeSignature) {
        let oldBPB = beatsPerBar
        let newBPB = new.beatsPerBar
        guard abs(oldBPB - newBPB) > 1e-9 else {
            timeSignature = new
            return
        }
        let f = newBPB / oldBPB
        for i in chords.indices { chords[i].startBeat *= f }
        for ti in tracks.indices {
            for ri in tracks[ti].regions.indices {
                tracks[ti].regions[ri].startBeat *= f
                tracks[ti].regions[ri].lengthBeats *= f
                for ni in tracks[ti].regions[ri].notes.indices {
                    tracks[ti].regions[ri].notes[ni].start *= f
                    tracks[ti].regions[ri].notes[ni].length *= f
                }
                for pi in tracks[ti].regions[ri].pedal.indices {
                    tracks[ti].regions[ri].pedal[pi].beat *= f
                }
            }
        }
        timeSignature = new
    }
}

// MARK: - Regions

extension Song {
    func trackIndex(_ id: UUID) -> Int? { tracks.firstIndex { $0.id == id } }

    func region(trackID: UUID, regionID: UUID) -> Region? {
        guard let ti = trackIndex(trackID) else { return nil }
        return tracks[ti].regions.first { $0.id == regionID }
    }

    /// Splits a region at an absolute beat. Returns the id of the right-hand region.
    @discardableResult
    mutating func splitRegion(trackID: UUID, regionID: UUID, atBeat beat: Double) -> UUID? {
        guard let ti = trackIndex(trackID), let ri = tracks[ti].regions.firstIndex(where: { $0.id == regionID }) else { return nil }
        let r = tracks[ti].regions[ri]
        let local = beat - r.startBeat
        guard local > 0.01, local < r.lengthBeats - 0.01 else { return nil }

        var left = r
        var right = r.copyWithNewIDs()
        left.lengthBeats = local
        right.startBeat = beat
        right.lengthBeats = r.lengthBeats - local
        right.name = r.name

        if r.kind == .midi {
            var leftNotes: [Note] = []
            var rightNotes: [Note] = []
            for n in r.notes {
                if n.start >= local - 1e-9 {
                    var m = n
                    m.id = UUID()
                    m.start = n.start - local
                    rightNotes.append(m)
                } else {
                    var l = n
                    if n.start + n.length > local + 1e-9 {
                        l.length = local - n.start
                        let rest = n.start + n.length - local
                        if rest >= 0.1 {
                            rightNotes.append(Note(pitch: n.pitch, start: 0, length: rest, velocity: n.velocity))
                        }
                    }
                    leftNotes.append(l)
                }
            }
            left.notes = leftNotes
            right.notes = rightNotes.sorted { $0.start < $1.start }
            left.pedal = r.pedal.filter { $0.beat < local }
            right.pedal = r.pedal.filter { $0.beat >= local }.map { PedalEvent(beat: $0.beat - local, down: $0.down) }
        } else {
            right.audioOffset = r.audioOffset + local * secondsPerBeat
        }
        tracks[ti].regions[ri] = left
        tracks[ti].regions.insert(right, at: ri + 1)
        return right.id
    }

    /// Places a copy right after the original. Returns the new id.
    @discardableResult
    mutating func duplicateRegion(trackID: UUID, regionID: UUID) -> UUID? {
        guard let ti = trackIndex(trackID), let r = tracks[ti].regions.first(where: { $0.id == regionID }) else { return nil }
        var copy = r.copyWithNewIDs()
        copy.startBeat = r.endBeat
        if r.kind == .audio { copy.audioOffset = r.audioOffset }
        tracks[ti].regions.append(copy)
        tracks[ti].regions.sort { $0.startBeat < $1.startBeat }
        return copy.id
    }

    /// Repeats the region so it plays `times` times in total (times >= 1).
    mutating func loopRegion(trackID: UUID, regionID: UUID, times: Int) {
        guard let ti = trackIndex(trackID), let r = tracks[ti].regions.first(where: { $0.id == regionID }), times > 1 else { return }
        for k in 1..<min(times, 64) {
            var copy = r.copyWithNewIDs()
            copy.startBeat = r.startBeat + Double(k) * r.lengthBeats
            tracks[ti].regions.append(copy)
        }
        tracks[ti].regions.sort { $0.startBeat < $1.startBeat }
    }

    mutating func deleteRegion(trackID: UUID, regionID: UUID) {
        guard let ti = trackIndex(trackID) else { return }
        tracks[ti].regions.removeAll { $0.id == regionID }
    }
}

// MARK: - Quantize

enum Quantizer {
    /// Grid in beats for the given label.
    static func grid(quarter: Bool = false, eighth: Bool = false, sixteenth: Bool = false, tripletEighth: Bool = false) -> Double {
        if quarter { return 1.0 }
        if eighth { return 0.5 }
        if sixteenth { return 0.25 }
        if tripletEighth { return 1.0 / 3.0 }
        return 0.25
    }

    /// Snaps note starts to the nearest grid line. Note ends are kept unless that would make a note too short.
    static func quantize(_ notes: [Note], grid: Double) -> [Note] {
        guard grid > 0.0001 else { return notes }
        return notes.map { n in
            var m = n
            let end = n.start + n.length
            m.start = max(0, (n.start / grid).rounded() * grid)
            m.length = max(grid / 2, end - m.start)
            return m
        }
    }
}
