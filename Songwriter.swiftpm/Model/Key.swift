import Foundation

struct TimeSignature: Codable, Equatable, Hashable {
    var numerator: Int
    var denominator: Int

    static let fourFour = TimeSignature(numerator: 4, denominator: 4)
    static let threeFour = TimeSignature(numerator: 3, denominator: 4)
    static let sixEight = TimeSignature(numerator: 6, denominator: 8)
    static let supported: [TimeSignature] = [.fourFour, .threeFour, .sixEight]

    /// Bar length in quarter notes.
    var beatsPerBar: Double { Double(numerator) * 4.0 / Double(denominator) }
    /// Metronome click spacing in quarter notes (dotted quarter in compound time).
    var clickInterval: Double { denominator == 8 ? 1.5 : 1.0 }
    var isCompound: Bool { denominator == 8 }
    var label: String { "\(numerator)/\(denominator)" }
}

struct DiatonicChord: Equatable, Identifiable {
    var label: String
    var chord: Chord
    var id: String { label }
}

struct SongKey: Codable, Equatable, Hashable {
    var root: Int
    var minor: Bool

    init(root: Int, minor: Bool = false) {
        self.root = ((root % 12) + 12) % 12
        self.minor = minor
    }

    static let majorNames = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    static let minorNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]

    static var all: [SongKey] {
        var out: [SongKey] = []
        for r in 0..<12 { out.append(SongKey(root: r, minor: false)) }
        for r in 0..<12 { out.append(SongKey(root: r, minor: true)) }
        return out
    }

    /// Whether chords in this key are spelled with flats.
    var usesFlats: Bool {
        let relativeMajor = minor ? (root + 3) % 12 : root
        return [5, 10, 3, 8, 1].contains(relativeMajor)
    }

    var tonicName: String {
        let names = minor ? SongKey.minorNames : SongKey.majorNames
        return names[root]
    }

    var name: String { tonicName + (minor ? " minor" : " major") }
    var shortName: String { tonicName + (minor ? "m" : "") }
    var displayName: String { NoteName.display(tonicName) + (minor ? " minor" : " major") }

    var scale: [Int] { minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11] }

    func diatonicChords() -> [DiatonicChord] {
        let numerals = minor ? ["i", "ii\u{00B0}", "III", "iv", "v", "VI", "VII"] : ["I", "ii", "iii", "IV", "V", "vi", "vii\u{00B0}"]
        let qualities: [ChordQuality] = minor
            ? [.m, .dim, .maj, .m, .m, .maj, .maj]
            : [.maj, .m, .m, .maj, .maj, .m, .dim]
        var out: [DiatonicChord] = []
        for i in 0..<7 {
            let c = Chord(root: root + scale[i], quality: qualities[i], bass: nil, flats: usesFlats)
            out.append(DiatonicChord(label: numerals[i], chord: c))
        }
        return out
    }

    /// The seven diatonic chords plus a borrowed bVII (or the major V in minor) and V/V.
    func chordPad() -> [DiatonicChord] {
        var out = diatonicChords()
        if minor {
            out.append(DiatonicChord(label: "V", chord: Chord(root: root + 7, quality: .maj, flats: usesFlats)))
        } else {
            out.append(DiatonicChord(label: "\u{266D}VII", chord: Chord(root: root + 10, quality: .maj, flats: usesFlats)))
        }
        out.append(DiatonicChord(label: "V/V", chord: Chord(root: root + 2, quality: .maj, flats: usesFlats)))
        return out
    }
}
