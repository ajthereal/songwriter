import XCTest
@testable import Core

final class SongModelTests: XCTestCase {
    private func twoSectionSong() -> Song {
        var s = Song(title: "T", tempo: 120, key: SongKey(root: 0), timeSignature: .fourFour)
        s.sections = Song.normalized([SongSection(name: "A", letter: "A", lengthBars: 2), SongSection(name: "B", letter: "B", lengthBars: 2)])
        s.chords = [ChordEvent(startBeat: 0, chord: Chord(root: 0)), ChordEvent(startBeat: 8, chord: Chord(root: 7))]
        var t = Track(name: "Keys", kind: .instrument, instrument: .grandPiano)
        t.regions = [
            Region(name: "r1", kind: .midi, startBeat: 0, lengthBeats: 8, notes: [Note(pitch: 60, start: 0, length: 1)]),
            Region(name: "r2", kind: .midi, startBeat: 8, lengthBeats: 8, notes: [Note(pitch: 62, start: 0, length: 1)]),
        ]
        s.tracks = [t]
        return s
    }

    func testBeatSecondConversion() {
        let s = twoSectionSong()
        XCTAssertEqual(s.secondsPerBeat, 0.5, accuracy: 1e-12)
        XCTAssertEqual(s.beatsToSeconds(8), 4, accuracy: 1e-12)
        XCTAssertEqual(s.secondsToBeats(s.beatsToSeconds(3.25)), 3.25, accuracy: 1e-12)
        var s2 = s
        s2.tempo = 84
        XCTAssertEqual(s2.beatsToSeconds(84), 60, accuracy: 1e-9)
        XCTAssertEqual(s.barStartBeat(3), 12, accuracy: 1e-12)
        XCTAssertEqual(s.totalBars, 4)
        let pos = s.formattedPosition(beat: 5.5)
        XCTAssertEqual(pos.bar, 2)
        XCTAssertEqual(pos.beat, 2)
    }

    func testMoveSectionMovesContent() {
        var s = twoSectionSong()
        s.moveSection(from: 1, to: 0)
        XCTAssertEqual(s.sections.map { $0.name }, ["B", "A"])
        XCTAssertEqual(s.sections.map { $0.startBar }, [0, 2])
        // G chord (was in B) now at the start, C chord (was in A) at bar 2.
        XCTAssertEqual(s.chordEvent(atBeat: 0)?.chord.symbol, "G")
        XCTAssertEqual(s.chordEvent(atBeat: 8)?.chord.symbol, "C")
        let regions = s.tracks[0].regions
        XCTAssertEqual(regions.map { $0.name }, ["r2", "r1"])
        XCTAssertEqual(regions.map { $0.startBeat }, [0, 8])
    }

    func testDuplicateSection() {
        var s = twoSectionSong()
        let originalID = s.sections[0].id
        let newID = s.duplicateSection(id: originalID)
        XCTAssertNotNil(newID)
        XCTAssertEqual(s.sections.count, 3)
        XCTAssertEqual(s.sections.map { $0.startBar }, [0, 2, 4])
        XCTAssertEqual(s.sections[1].name, "A")
        XCTAssertNotEqual(s.sections[1].id, originalID)
        // Chords: C at 0, C at 8 (the copy), G at 16.
        XCTAssertEqual(s.chords.map { $0.startBeat }, [0, 8, 16])
        XCTAssertEqual(s.chords.map { $0.chord.symbol }, ["C", "C", "G"])
        let regions = s.tracks[0].regions
        XCTAssertEqual(regions.map { $0.startBeat }, [0, 8, 16])
        XCTAssertEqual(Set(regions.map { $0.id }).count, 3)
        XCTAssertEqual(regions[1].notes[0].pitch, 60)
        XCTAssertEqual(regions[2].notes[0].pitch, 62)
    }

    func testResizeSection() {
        var s = twoSectionSong()
        s.chords.append(ChordEvent(startBeat: 4, chord: Chord(root: 5)))
        s.resizeSection(id: s.sections[0].id, bars: 1)
        XCTAssertEqual(s.sections.map { $0.startBar }, [0, 1])
        XCTAssertFalse(s.chords.contains { $0.chord.root == 5 })    // chord in removed bar dropped
        XCTAssertEqual(s.chordEvent(atBeat: 4)?.chord.symbol, "G")  // B moved one bar earlier
        XCTAssertEqual(s.tracks[0].regions[0].lengthBeats, 4, accuracy: 1e-9)  // clipped
        XCTAssertEqual(s.tracks[0].regions[1].startBeat, 4, accuracy: 1e-9)
        s.resizeSection(id: s.sections[0].id, bars: 3)
        XCTAssertEqual(s.sections.map { $0.startBar }, [0, 3])
        XCTAssertEqual(s.tracks[0].regions[1].startBeat, 12, accuracy: 1e-9)
    }

    func testAddAndDeleteSection() {
        var s = twoSectionSong()
        let id = s.addSection(name: "Bridge", letter: "D", bars: 4, at: 1)
        XCTAssertEqual(s.sections.map { $0.name }, ["A", "Bridge", "B"])
        XCTAssertEqual(s.sections.map { $0.startBar }, [0, 2, 6])
        XCTAssertEqual(s.chordEvent(atBeat: 24)?.chord.symbol, "G")
        s.deleteSection(id: id)
        XCTAssertEqual(s.sections.map { $0.startBar }, [0, 2])
        XCTAssertEqual(s.chordEvent(atBeat: 8)?.chord.symbol, "G")
        // The last remaining section cannot be deleted down to zero.
        s.deleteSection(id: s.sections[0].id)
        s.deleteSection(id: s.sections[0].id)
        XCTAssertEqual(s.sections.count, 1)
    }

    func testChordEditing() {
        var s = twoSectionSong()
        s.setChord(Chord(root: 9, quality: .m), atBeat: 4)
        XCTAssertEqual(s.chords.count, 3)
        s.setChord(Chord(root: 2), atBeat: 4)
        XCTAssertEqual(s.chords.count, 3)
        XCTAssertEqual(s.chord(atBeat: 5)?.symbol, "D")
        s.setChord(nil, atBeat: 4)
        XCTAssertEqual(s.chords.count, 2)
        XCTAssertEqual(s.chord(atBeat: 5)?.symbol, "C")
        let spans = s.chordSpans()
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].end, 8, accuracy: 1e-9)
        XCTAssertEqual(spans[1].end, s.lengthBeats, accuracy: 1e-9)
    }

    func testSplitMidiRegion() {
        var s = twoSectionSong()
        let tid = s.tracks[0].id
        let rid = s.tracks[0].regions[0].id
        s.tracks[0].regions[0].notes = [Note(pitch: 60, start: 1, length: 4), Note(pitch: 64, start: 5, length: 1)]
        let right = s.splitRegion(trackID: tid, regionID: rid, atBeat: 3)
        XCTAssertNotNil(right)
        let regs = s.tracks[0].regions
        XCTAssertEqual(regs.count, 3)
        XCTAssertEqual(regs[0].lengthBeats, 3, accuracy: 1e-9)
        XCTAssertEqual(regs[1].startBeat, 3, accuracy: 1e-9)
        XCTAssertEqual(regs[1].lengthBeats, 5, accuracy: 1e-9)
        XCTAssertEqual(regs[0].notes.count, 1)
        XCTAssertEqual(regs[0].notes[0].length, 2, accuracy: 1e-9)       // truncated
        XCTAssertEqual(regs[1].notes.count, 2)                            // continuation + second note
        XCTAssertEqual(regs[1].notes[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(regs[1].notes[0].length, 2, accuracy: 1e-9)
        XCTAssertEqual(regs[1].notes[1].start, 2, accuracy: 1e-9)
        XCTAssertNil(s.splitRegion(trackID: tid, regionID: rid, atBeat: 100))
    }

    func testSplitAudioRegionKeepsTakes() {
        var s = twoSectionSong()
        var t = Track(name: "Vox", kind: .audio)
        let take = Take(name: "Take 1", fileName: "a.caf", offset: 0.1, duration: 10)
        t.regions = [Region(name: "Take", kind: .audio, startBeat: 0, lengthBeats: 8, takes: [take], activeTake: 0, audioOffset: 0)]
        s.tracks.append(t)
        let right = s.splitRegion(trackID: t.id, regionID: t.regions[0].id, atBeat: 4)
        XCTAssertNotNil(right)
        let regs = s.tracks[1].regions
        XCTAssertEqual(regs[1].audioOffset, 2.0, accuracy: 1e-9)   // 4 beats at 120 bpm
        XCTAssertEqual(regs[1].takes, regs[0].takes)
    }

    func testDuplicateAndLoopRegion() {
        var s = twoSectionSong()
        let tid = s.tracks[0].id
        let rid = s.tracks[0].regions[0].id
        s.loopRegion(trackID: tid, regionID: rid, times: 3)
        XCTAssertEqual(s.tracks[0].regions.count, 4)
        XCTAssertEqual(s.tracks[0].regions.filter { $0.name == "r1" }.count, 3)
        let dup = s.duplicateRegion(trackID: tid, regionID: rid)
        XCTAssertNotNil(dup)
        XCTAssertEqual(s.tracks[0].regions.count, 5)
    }

    func testTimeSignatureChangeKeepsBars() {
        var s = twoSectionSong()
        s.setTimeSignature(.threeFour)
        XCTAssertEqual(s.chords[1].startBeat, 6, accuracy: 1e-9)
        XCTAssertEqual(s.barIndex(atBeat: s.chords[1].startBeat), 2)
        XCTAssertEqual(s.tracks[0].regions[1].startBeat, 6, accuracy: 1e-9)
    }

    func testQuantize() {
        let notes = [Note(pitch: 60, start: 0.13, length: 0.9), Note(pitch: 62, start: 0.62, length: 0.4)]
        let q = Quantizer.quantize(notes, grid: 0.5)
        XCTAssertEqual(q[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(q[1].start, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(q[0].length, 0)
        let t = Quantizer.quantize([Note(pitch: 60, start: 0.3, length: 0.3)], grid: 1.0 / 3.0)
        XCTAssertEqual(t[0].start, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testPlaybackNotesFromRegions() {
        let s = twoSectionSong()
        let notes = s.playbackNotes(for: s.tracks[0])
        XCTAssertEqual(notes.map { $0.pitch }, [60, 62])
        XCTAssertEqual(notes.map { $0.start }, [0, 8])
    }
}

final class UndoStackTests: XCTestCase {
    func testUndoRedo() {
        var stack = UndoStack<Int>(limit: 3)
        var value = 0
        for next in 1...5 {
            stack.record(value)
            value = next
        }
        XCTAssertEqual(stack.undoStates.count, 3)          // limited
        XCTAssertTrue(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
        if let v = stack.undo(current: value) { value = v }
        XCTAssertEqual(value, 4)
        XCTAssertTrue(stack.canRedo)
        if let v = stack.redo(current: value) { value = v }
        XCTAssertEqual(value, 5)
        if let v = stack.undo(current: value) { value = v }
        stack.record(value)                                 // new edit clears redo
        XCTAssertFalse(stack.canRedo)
    }

    func testUndoDepthOfFifty() {
        var stack = UndoStack<Int>(limit: 100)
        for i in 0..<60 { stack.record(i) }
        XCTAssertEqual(stack.undoStates.count, 60)
        var current = 60
        var steps = 0
        while let v = stack.undo(current: current) { current = v; steps += 1 }
        XCTAssertEqual(steps, 60)
        XCTAssertEqual(current, 0)
        XCTAssertNil(stack.undo(current: current))
    }
}

final class CodecTests: XCTestCase {
    func testRoundTrip() throws {
        let song = Song.demo()
        let data = try SongCodec.encode(song)
        let back = try SongCodec.decode(data)
        XCTAssertEqual(song, back)
        XCTAssertEqual(back.version, 1)
    }

    func testFutureVersionRejected() throws {
        var song = Song.demo()
        song.version = 99
        let data = try SongCodec.encode(song)
        XCTAssertThrowsError(try SongCodec.decode(data)) { error in
            XCTAssertEqual(error as? SongCodec.CodecError, .unsupportedVersion(99))
        }
    }

    func testGarbageRejected() {
        XCTAssertThrowsError(try SongCodec.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try SongCodec.decode(Data("{\"version\":1}".utf8)))
    }

    func testDemoSong() {
        let s = Song.demo()
        XCTAssertEqual(s.title, "Untitled Song 3")
        XCTAssertEqual(s.tempo, 84)
        XCTAssertEqual(s.key, SongKey(root: 2, minor: false))
        XCTAssertEqual(s.sections.map { $0.lengthBars }, [2, 8, 2, 4])
        XCTAssertEqual(s.sections.map { $0.startBar }, [0, 2, 10, 12])
        XCTAssertEqual(s.tracks.map { $0.name }, ["Lead Vocal", "Grand Piano", "Bass", "Drums", "E-Piano"])
        XCTAssertEqual(s.tracks[4].regions.count, 1)
        XCTAssertEqual(s.totalBars, 16)
    }
}

final class SunoPackTests: XCTestCase {
    func testTags() {
        let s = Song.demo()
        XCTAssertEqual(SunoPack.tags(for: s), ["[Intro]", "[Verse 1]", "[Pre-Chorus]", "[Chorus]"])
        let text = SunoPack.text(for: s)
        XCTAssertTrue(text.contains("84 BPM"))
        XCTAssertTrue(text.contains("D major"))
        XCTAssertTrue(text.contains("[Chorus]\nSing it loud"))
        XCTAssertTrue(text.contains("[Intro]\n(instrumental)"))
    }

    func testRepeatedSectionsAreNumbered() {
        var s = Song.demo()
        if let verse = s.sections.first(where: { $0.name == "Verse" }) { s.duplicateSection(id: verse.id) }
        XCTAssertEqual(SunoPack.tags(for: s), ["[Intro]", "[Verse 1]", "[Verse 2]", "[Pre-Chorus]", "[Chorus]"])
    }
}
