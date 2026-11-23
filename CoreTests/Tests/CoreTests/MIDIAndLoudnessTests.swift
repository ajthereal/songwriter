import XCTest
@testable import Core

final class MIDIFileWriterTests: XCTestCase {
    func testVLQ() {
        XCTAssertEqual(MIDIFileWriter.vlq(0), [0x00])
        XCTAssertEqual(MIDIFileWriter.vlq(0x40), [0x40])
        XCTAssertEqual(MIDIFileWriter.vlq(0x7F), [0x7F])
        XCTAssertEqual(MIDIFileWriter.vlq(0x80), [0x81, 0x00])
        XCTAssertEqual(MIDIFileWriter.vlq(0x2000), [0xC0, 0x00])
        XCTAssertEqual(MIDIFileWriter.vlq(0x3FFF), [0xFF, 0x7F])
        XCTAssertEqual(MIDIFileWriter.vlq(0x4000), [0x81, 0x80, 0x00])
        XCTAssertEqual(MIDIFileWriter.vlq(0x0FFFFFFF), [0xFF, 0xFF, 0xFF, 0x7F])
        XCTAssertEqual(MIDIFileWriter.vlq(480), [0x83, 0x60])
    }

    private func find(_ pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        for i in 0...(bytes.count - pattern.count) where Array(bytes[i..<(i + pattern.count)]) == pattern { return i }
        return nil
    }

    func testHeaderAndMeta() {
        var song = Song.demo()
        song.tempo = 120
        let bytes = [UInt8](MIDIFileWriter.data(for: song))
        XCTAssertEqual(Array(bytes[0..<4]), Array("MThd".utf8))
        XCTAssertEqual(Array(bytes[4..<8]), [0, 0, 0, 6])
        XCTAssertEqual(Array(bytes[8..<10]), [0, 1])                       // format 1
        // conductor + chords + 4 instrument tracks
        XCTAssertEqual(Array(bytes[10..<12]), [0, 6])
        XCTAssertEqual(Array(bytes[12..<14]), [0x01, 0xE0])                // 480 ticks per quarter
        XCTAssertEqual(Array(bytes[14..<18]), Array("MTrk".utf8))
        XCTAssertNotNil(find([0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20], in: bytes), "tempo 500000 us")
        XCTAssertNotNil(find([0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08], in: bytes), "4/4")
        XCTAssertNotNil(find([0xFF, 0x59, 0x02, 0x02, 0x00], in: bytes), "D major, two sharps")
        XCTAssertNotNil(find(Array("Dadd9".utf8), in: bytes))
        XCTAssertNotNil(find(Array("Chorus".utf8), in: bytes))
        XCTAssertNotNil(find([0xFF, 0x2F, 0x00], in: bytes))
    }

    func testTempoAt84() {
        let song = Song.demo()
        let bytes = [UInt8](MIDIFileWriter.data(for: song))
        let micros = Int((60_000_000.0 / 84.0).rounded())
        let pattern: [UInt8] = [0xFF, 0x51, 0x03, UInt8((micros >> 16) & 0xFF), UInt8((micros >> 8) & 0xFF), UInt8(micros & 0xFF)]
        XCTAssertNotNil(find(pattern, in: bytes))
    }

    func testTrackChunkLengthsAreConsistent() {
        let bytes = [UInt8](MIDIFileWriter.data(for: Song.demo()))
        var i = 14
        var chunks = 0
        while i < bytes.count {
            XCTAssertEqual(Array(bytes[i..<(i + 4)]), Array("MTrk".utf8))
            let len = (Int(bytes[i + 4]) << 24) | (Int(bytes[i + 5]) << 16) | (Int(bytes[i + 6]) << 8) | Int(bytes[i + 7])
            i += 8 + len
            XCTAssertEqual(bytes[i - 3], 0xFF)  // end of track meta
            XCTAssertEqual(bytes[i - 2], 0x2F)
            chunks += 1
        }
        XCTAssertEqual(i, bytes.count)
        XCTAssertEqual(chunks, 6)
    }

    func testDeltaTimesAndNoteOrder() {
        var song = Song(title: "T", tempo: 120, key: SongKey(root: 0), timeSignature: .fourFour)
        song.sections = Song.normalized([SongSection(name: "A", letter: "A", lengthBars: 1)])
        var t = Track(name: "K", kind: .instrument, instrument: .grandPiano)
        t.regions = [Region(name: "r", kind: .midi, startBeat: 0, lengthBeats: 4, notes: [
            Note(pitch: 60, start: 0, length: 1, velocity: 100),
            Note(pitch: 64, start: 1, length: 1, velocity: 90),
        ])]
        song.tracks = [t]
        let bytes = [UInt8](MIDIFileWriter.data(for: song))
        // note on 60 at delta 0, then note off 60 + note on 64 at delta 480 (0x83 0x60), off before on
        let expected: [UInt8] = [0x00, 0x90, 60, 100, 0x83, 0x60, 0x80, 60, 0, 0x00, 0x90, 64, 90]
        XCTAssertNotNil(find(expected, in: bytes))
        // program change for grand piano on channel 0
        XCTAssertNotNil(find([0xC0, 0x00], in: bytes))
    }

    func testDrumsUseChannelTen() {
        let bytes = [UInt8](MIDIFileWriter.data(for: Song.demo()))
        XCTAssertNotNil(find([0x99, 36], in: bytes))
    }
}

final class LoudnessTests: XCTestCase {
    private func sine(freq: Double, amplitude: Double, seconds: Double, sampleRate: Double = 48000) -> [Float] {
        let n = Int(seconds * sampleRate)
        return (0..<n).map { Float(amplitude * sin(2.0 * Double.pi * freq * Double($0) / sampleRate)) }
    }

    func testSineLoudness() throws {
        let amp = Loudness.linear(fromDB: -3.0)
        let s = sine(freq: 1000, amplitude: amp, seconds: 6)
        let lufs = try XCTUnwrap(Loudness.integratedLUFS(channels: [s, s], sampleRate: 48000))
        XCTAssertEqual(lufs, -3.0, accuracy: 0.3)
    }

    func testFullScaleMonoSine() throws {
        let s = sine(freq: 1000, amplitude: 1.0, seconds: 5)
        let lufs = try XCTUnwrap(Loudness.integratedLUFS(channels: [s], sampleRate: 48000))
        XCTAssertEqual(lufs, -3.01, accuracy: 0.3)
    }

    func testLevelScalesInDB() throws {
        let a = sine(freq: 1000, amplitude: 0.5, seconds: 5)
        let b = sine(freq: 1000, amplitude: 0.25, seconds: 5)
        let la = try XCTUnwrap(Loudness.integratedLUFS(channels: [a, a], sampleRate: 48000))
        let lb = try XCTUnwrap(Loudness.integratedLUFS(channels: [b, b], sampleRate: 48000))
        XCTAssertEqual(la - lb, 6.02, accuracy: 0.05)
    }

    func testAbsoluteGateIgnoresSilence() throws {
        let tone = sine(freq: 1000, amplitude: Loudness.linear(fromDB: -20), seconds: 5)
        let quiet = sine(freq: 1000, amplitude: Loudness.linear(fromDB: -100), seconds: 5)
        let alone = try XCTUnwrap(Loudness.integratedLUFS(channels: [tone, tone], sampleRate: 48000))
        let mixed = try XCTUnwrap(Loudness.integratedLUFS(channels: [tone + quiet, tone + quiet], sampleRate: 48000))
        XCTAssertEqual(alone, mixed, accuracy: 0.05)
    }

    func testRelativeGateIgnoresQuietPassage() throws {
        let loud = sine(freq: 1000, amplitude: Loudness.linear(fromDB: -14), seconds: 8)
        let quiet = sine(freq: 1000, amplitude: Loudness.linear(fromDB: -50), seconds: 8)   // well below -10 LU
        let alone = try XCTUnwrap(Loudness.integratedLUFS(channels: [loud, loud], sampleRate: 48000))
        let both = try XCTUnwrap(Loudness.integratedLUFS(channels: [loud + quiet, loud + quiet], sampleRate: 48000))
        XCTAssertEqual(alone, both, accuracy: 0.1)
        // Without gating the mean would be about 3 dB lower; make sure gating is active.
        XCTAssertGreaterThan(both, alone - 0.5)
    }

    func testSilenceAndShortSignals() {
        let silence = [Float](repeating: 0, count: 48000 * 3)
        XCTAssertNil(Loudness.integratedLUFS(channels: [silence, silence], sampleRate: 48000))
        XCTAssertNil(Loudness.integratedLUFS(channels: [[0.1, 0.2]], sampleRate: 48000))
        XCTAssertNil(Loudness.integratedLUFS(channels: [], sampleRate: 48000))
    }

    func testOtherSampleRate() throws {
        let amp = Loudness.linear(fromDB: -3.0)
        let s = sine(freq: 1000, amplitude: amp, seconds: 5, sampleRate: 44100)
        let lufs = try XCTUnwrap(Loudness.integratedLUFS(channels: [s, s], sampleRate: 44100))
        XCTAssertEqual(lufs, -3.0, accuracy: 0.3)
    }

    func testLimiterHonoursCeiling() {
        var ch = [sine(freq: 220, amplitude: 2.0, seconds: 1), sine(freq: 330, amplitude: 1.5, seconds: 1)]
        Loudness.limit(channels: &ch, ceilingDB: -1.0, sampleRate: 48000)
        let ceil = Float(Loudness.linear(fromDB: -1.0))
        XCTAssertLessThanOrEqual(Loudness.samplePeak(channels: ch), ceil + 1e-4)
        XCTAssertLessThanOrEqual(Loudness.truePeak(channels: ch), ceil * 1.001)
        XCTAssertGreaterThan(Loudness.samplePeak(channels: ch), ceil * 0.8)   // not crushed to nothing
    }

    func testLimiterLeavesQuietSignalAlone() {
        let original = sine(freq: 440, amplitude: 0.3, seconds: 1)
        var ch = [original]
        Loudness.limit(channels: &ch, ceilingDB: -1.0, sampleRate: 48000)
        XCTAssertEqual(ch[0], original)
    }

    func testTruePeakEstimateExceedsSamplePeakForIntersamplePeaks() {
        // Two equal samples straddling a peak: the true peak is above the sample peak.
        var x = [Float](repeating: 0, count: 64)
        for i in 0..<64 { x[i] = Float(sin(2.0 * Double.pi * 12000.0 * (Double(i) + 0.5) / 48000.0)) }
        let sp = x.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(Loudness.truePeak(x), sp)
    }

    func testNormalisationTowardTarget() throws {
        let s = sine(freq: 1000, amplitude: 0.05, seconds: 5)
        let measured = try XCTUnwrap(Loudness.integratedLUFS(channels: [s, s], sampleRate: 48000))
        let gain = Float(Loudness.linear(fromDB: -14.0 - measured))
        let scaled = s.map { $0 * gain }
        let after = try XCTUnwrap(Loudness.integratedLUFS(channels: [scaled, scaled], sampleRate: 48000))
        XCTAssertEqual(after, -14.0, accuracy: 0.05)
    }
}
