import XCTest
@testable import Core

final class ChordTests: XCTestCase {
    func testParseBasic() {
        let d = Chord.parse("D")
        XCTAssertEqual(d?.root, 2)
        XCTAssertEqual(d?.quality, .maj)
        let bm7 = Chord.parse("Bm7")
        XCTAssertEqual(bm7?.root, 11)
        XCTAssertEqual(bm7?.quality, .m7)
        let half = Chord.parse("F#m7b5")
        XCTAssertEqual(half?.root, 6)
        XCTAssertEqual(half?.quality, .m7b5)
    }

    func testParseSlashAndRoundTrip() {
        let c = Chord.parse("Dadd9/F#")
        XCTAssertEqual(c?.root, 2)
        XCTAssertEqual(c?.quality, .add9)
        XCTAssertEqual(c?.bass, 6)
        XCTAssertEqual(c?.symbol, "Dadd9/F#")
        let flat = Chord.parse("Bb/D")
        XCTAssertEqual(flat?.root, 10)
        XCTAssertEqual(flat?.bass, 2)
        XCTAssertEqual(flat?.symbol, "Bb/D")
        for s in ["C", "Am", "G7", "Cmaj7", "Dm7", "Esus2", "Asus4", "Fadd9", "Bdim", "Caug", "Em7b5", "G6", "Am6", "D9"] {
            XCTAssertEqual(Chord.parse(s)?.symbol, s, "round trip of \(s)")
        }
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(Chord.parse(""))
        XCTAssertNil(Chord.parse("H"))
        XCTAssertNil(Chord.parse("Cxyz"))
        XCTAssertNil(Chord.parse("C/"))
        XCTAssertNil(Chord.parse("C/Zb"))
    }

    func testSpelling() {
        XCTAssertEqual(Chord(root: 1, quality: .maj, flats: true).symbol, "Db")
        XCTAssertEqual(Chord(root: 1, quality: .maj, flats: false).symbol, "C#")
        XCTAssertEqual(Chord(root: 10, quality: .m7, flats: true).symbol, "Bbm7")
        XCTAssertEqual(Chord(root: -2, quality: .maj).root, 10)
    }

    func testPitchClassesAndDisplay() {
        XCTAssertEqual(Chord.parse("D")?.pitchClasses, [2, 6, 9])
        XCTAssertEqual(Chord.parse("Dadd9")?.pitchClasses, [2, 6, 9, 4])
        let parts = Chord.parse("Dadd9")?.displayParts
        XCTAssertEqual(parts?.root, "D")
        XCTAssertEqual(parts?.ext, "add9")
        XCTAssertEqual(parts?.main, "")
        let m7 = Chord.parse("Bm7")?.displayParts
        XCTAssertEqual(m7?.main, "m")
        XCTAssertEqual(m7?.ext, "7")
    }
}

final class KeyTests: XCTestCase {
    func testDMajorDiatonic() {
        let key = SongKey(root: 2, minor: false)
        XCTAssertEqual(key.diatonicChords().map { $0.chord.symbol }, ["D", "Em", "F#m", "G", "A", "Bm", "C#dim"])
        XCTAssertEqual(key.diatonicChords().map { $0.label }, ["I", "ii", "iii", "IV", "V", "vi", "vii\u{00B0}"])
    }

    func testBMinorDiatonic() {
        let key = SongKey(root: 11, minor: true)
        XCTAssertEqual(key.diatonicChords().map { $0.chord.symbol }, ["Bm", "C#dim", "D", "Em", "F#m", "G", "A"])
    }

    func testFlatKeySpelling() {
        let key = SongKey(root: 5, minor: false)
        XCTAssertTrue(key.usesFlats)
        XCTAssertEqual(key.diatonicChords().map { $0.chord.symbol }, ["F", "Gm", "Am", "Bb", "C", "Dm", "Edim"])
        XCTAssertEqual(SongKey(root: 2, minor: true).usesFlats, true)  // D minor, relative F major
        XCTAssertEqual(SongKey(root: 9, minor: true).usesFlats, false)
    }

    func testChordPad() {
        let pad = SongKey(root: 2, minor: false).chordPad()
        XCTAssertEqual(pad.count, 9)
        XCTAssertEqual(pad[7].chord.symbol, "C")
        XCTAssertEqual(pad[8].chord.symbol, "E")
        XCTAssertEqual(pad[8].label, "V/V")
        let minorPad = SongKey(root: 9, minor: true).chordPad()
        XCTAssertEqual(minorPad.count, 9)
        XCTAssertEqual(minorPad[7].chord.symbol, "E")
    }

    func testAllKeys() {
        XCTAssertEqual(SongKey.all.count, 24)
        XCTAssertEqual(SongKey(root: 2).name, "D major")
        XCTAssertEqual(SongKey(root: 11, minor: true).name, "B minor")
    }

    func testTimeSignature() {
        XCTAssertEqual(TimeSignature.fourFour.beatsPerBar, 4)
        XCTAssertEqual(TimeSignature.threeFour.beatsPerBar, 3)
        XCTAssertEqual(TimeSignature.sixEight.beatsPerBar, 3)
        XCTAssertEqual(TimeSignature.sixEight.clickInterval, 1.5)
    }
}

final class BandGeneratorTests: XCTestCase {
    func testDeterministic() {
        let song = Song.demo()
        for inst in InstrumentKind.allCases {
            for style in inst.styles {
                let a = BandGenerator.generate(song: song, instrument: inst, style: style)
                let b = BandGenerator.generate(song: song, instrument: inst, style: style)
                XCTAssertEqual(a, b, "\(inst) \(style)")
            }
        }
    }

    func testBassRootsFollowChords() {
        let song = Song.demo()
        let notes = BandGenerator.generate(song: song, instrument: .bass, style: .bassRoots)
        // 16 bars, plus one extra attack for the half-bar chord change in bar 12 (index 11).
        XCTAssertEqual(notes.count, 17)
        XCTAssertEqual(notes[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(notes[0].pitch % 12, 2)             // D
        XCTAssertEqual(notes[1].pitch % 12, 1)             // A/C# -> bass note C#
        XCTAssertTrue(notes.allSatisfy { $0.pitch >= 28 && $0.pitch < 40 })
        XCTAssertTrue(notes.allSatisfy { $0.start >= 0 && $0.start < song.lengthBeats })
    }

    func testTimingWithinBars() {
        let song = Song.demo()
        for style in InstrumentKind.grandPiano.styles {
            let notes = BandGenerator.generate(song: song, instrument: .grandPiano, style: style)
            XCTAssertFalse(notes.isEmpty)
            for n in notes {
                XCTAssertGreaterThanOrEqual(n.start, 0)
                XCTAssertLessThan(n.start + 1e-9, song.lengthBeats)
                XCTAssertGreaterThan(n.length, 0)
                XCTAssertLessThanOrEqual(n.start + n.length, song.lengthBeats + 1e-6)
                XCTAssertTrue((1...127).contains(n.velocity))
            }
        }
    }

    func testDrums() {
        let song = Song.demo()
        let notes = BandGenerator.generate(song: song, instrument: .drums, style: .drumsPop)
        XCTAssertTrue(notes.contains { $0.pitch == 36 && abs($0.start) < 1e-9 })
        XCTAssertTrue(notes.contains { $0.pitch == 49 })  // crash at section starts
        XCTAssertTrue(BandGenerator.generate(song: song, instrument: .drums, style: .drumsOff).isEmpty)
        // Kick on the first beat of every bar.
        for bar in 0..<song.totalBars {
            let start = Double(bar) * 4
            XCTAssertTrue(notes.contains { $0.pitch == 36 && abs($0.start - start) < 1e-9 }, "bar \(bar)")
        }
    }

    func testRangeRestriction() {
        let song = Song.demo()
        let all = BandGenerator.generate(song: song, instrument: .ePiano, style: .epPads)
        let chorus = BandGenerator.generate(song: song, instrument: .ePiano, style: .epPads, from: 48, to: 64)
        XCTAssertFalse(chorus.isEmpty)
        XCTAssertTrue(chorus.allSatisfy { $0.start >= 48 && $0.start < 64 })
        XCTAssertLessThan(chorus.count, all.count)
    }

    func testWaltz() {
        var song = Song.demo()
        song.setTimeSignature(.threeFour)
        let notes = BandGenerator.generate(song: song, instrument: .bass, style: .bassRootFive)
        XCTAssertFalse(notes.isEmpty)
        XCTAssertTrue(notes.allSatisfy { $0.start < song.lengthBeats })
    }

    func testMakeEditable() {
        var song = Song.demo()
        let piano = song.tracks[1]
        let generated = song.playbackNotes(for: piano)
        song.makeEditable(trackID: piano.id)
        let after = song.tracks[1]
        XCTAssertFalse(after.follow)
        XCTAssertEqual(after.regions.count, song.sections.count)
        let converted = song.playbackNotes(for: after)
        XCTAssertEqual(converted.count, generated.count)
        for (a, b) in zip(generated, converted) {
            XCTAssertEqual(a.pitch, b.pitch)
            XCTAssertEqual(a.start, b.start, accuracy: 1e-9)
        }
    }

    func testChartLayout() {
        let song = Song.demo()
        let lines = ChartLayout.lines(for: song)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertTrue(lines[0].showSectionHeader)
        XCTAssertEqual(lines[0].bars.count, 2)  // intro is two bars
        XCTAssertEqual(lines[1].bars.count, 4)
    }
}
