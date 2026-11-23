import Foundation

/// Note spelling helpers.
enum NoteName {
    static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    static func name(_ pitchClass: Int, flats useFlats: Bool) -> String {
        let i = ((pitchClass % 12) + 12) % 12
        return useFlats ? flats[i] : sharps[i]
    }

    /// Replaces ASCII accidentals with typographic ones for display.
    static func display(_ name: String) -> String {
        if name.count == 2 {
            if name.hasSuffix("#") { return String(name.prefix(1)) + "\u{266F}" }
            if name.hasSuffix("b") { return String(name.prefix(1)) + "\u{266D}" }
        }
        return name
    }
}

enum ChordQuality: String, Codable, CaseIterable, Equatable {
    case maj
    case m
    case dom7 = "7"
    case maj7
    case m7
    case sus2
    case sus4
    case add9
    case dim
    case aug
    case m7b5
    case six = "6"
    case m6
    case nine = "9"

    /// Semitone offsets from the root (may exceed 11 for added ninths).
    var intervals: [Int] {
        switch self {
        case .maj: return [0, 4, 7]
        case .m: return [0, 3, 7]
        case .dom7: return [0, 4, 7, 10]
        case .maj7: return [0, 4, 7, 11]
        case .m7: return [0, 3, 7, 10]
        case .sus2: return [0, 2, 7]
        case .sus4: return [0, 5, 7]
        case .add9: return [0, 4, 7, 14]
        case .dim: return [0, 3, 6]
        case .aug: return [0, 4, 8]
        case .m7b5: return [0, 3, 6, 10]
        case .six: return [0, 4, 7, 9]
        case .m6: return [0, 3, 7, 9]
        case .nine: return [0, 4, 7, 10, 14]
        }
    }

    /// Text part drawn on the baseline ("" or "m").
    var displayMain: String {
        switch self {
        case .m, .m7, .m7b5, .m6: return "m"
        default: return ""
        }
    }

    /// Text part drawn raised and smaller.
    var displayExtension: String {
        switch self {
        case .maj, .m: return ""
        case .dom7: return "7"
        case .maj7: return "maj7"
        case .m7: return "7"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        case .add9: return "add9"
        case .dim: return "dim"
        case .aug: return "aug"
        case .m7b5: return "7\u{266D}5"
        case .six: return "6"
        case .m6: return "6"
        case .nine: return "9"
        }
    }

    /// ASCII suffix used in plain-text chord symbols.
    var suffix: String {
        switch self {
        case .maj: return ""
        case .m: return "m"
        case .dom7: return "7"
        case .maj7: return "maj7"
        case .m7: return "m7"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        case .add9: return "add9"
        case .dim: return "dim"
        case .aug: return "aug"
        case .m7b5: return "m7b5"
        case .six: return "6"
        case .m6: return "m6"
        case .nine: return "9"
        }
    }

    var pickerLabel: String { self == .maj ? "maj" : suffix }

    static let aliases: [String: ChordQuality] = [
        "": .maj, "maj": .maj, "M": .maj,
        "m": .m, "min": .m, "-": .m,
        "7": .dom7, "dom7": .dom7,
        "maj7": .maj7, "M7": .maj7, "\u{0394}": .maj7, "\u{0394}7": .maj7,
        "m7": .m7, "min7": .m7, "-7": .m7,
        "sus2": .sus2, "sus4": .sus4, "sus": .sus4,
        "add9": .add9, "add2": .add9,
        "dim": .dim, "\u{00B0}": .dim,
        "aug": .aug, "+": .aug,
        "m7b5": .m7b5, "m7\u{266D}5": .m7b5, "\u{00F8}": .m7b5, "\u{00F8}7": .m7b5,
        "6": .six, "m6": .m6, "9": .nine,
    ]
}

struct Chord: Codable, Equatable, Hashable {
    var root: Int
    var quality: ChordQuality
    var bass: Int?
    var flats: Bool

    init(root: Int, quality: ChordQuality = .maj, bass: Int? = nil, flats: Bool = false) {
        self.root = ((root % 12) + 12) % 12
        self.quality = quality
        if let b = bass { self.bass = ((b % 12) + 12) % 12 } else { self.bass = nil }
        self.flats = flats
    }

    var rootName: String { NoteName.name(root, flats: flats) }
    var bassName: String? {
        guard let b = bass else { return nil }
        return NoteName.name(b, flats: flats)
    }

    /// Plain ASCII symbol, e.g. "Dadd9/F#".
    var symbol: String {
        var s = rootName + quality.suffix
        if let b = bassName { s += "/" + b }
        return s
    }

    /// Pitch classes of the chord tones (without the slash bass unless it is a non-chord tone).
    var pitchClasses: [Int] {
        var out: [Int] = []
        for i in quality.intervals {
            let pc = (root + i) % 12
            if !out.contains(pc) { out.append(pc) }
        }
        return out
    }

    var bassPitchClass: Int { bass ?? root }

    struct DisplayParts: Equatable {
        var root: String
        var main: String
        var ext: String
        var bass: String?
    }

    var displayParts: DisplayParts {
        DisplayParts(root: NoteName.display(rootName), main: quality.displayMain, ext: quality.displayExtension,
                     bass: bassName.map { NoteName.display($0) })
    }

    // MARK: Parsing

    private struct ParsedNote {
        var pitchClass: Int
        var flat: Bool
        var sharp: Bool
        var rest: String
    }

    private static func parseNote(_ s: String) -> ParsedNote? {
        guard let first = s.first else { return nil }
        let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let base = letters[first] else { return nil }
        var rest = String(s.dropFirst())
        var pc = base
        var flat = false
        var sharp = false
        if let c = rest.first {
            if c == "#" || c == "\u{266F}" {
                pc += 1; sharp = true; rest = String(rest.dropFirst())
            } else if c == "b" || c == "\u{266D}" {
                pc -= 1; flat = true; rest = String(rest.dropFirst())
            }
        }
        return ParsedNote(pitchClass: ((pc % 12) + 12) % 12, flat: flat, sharp: sharp, rest: rest)
    }

    /// Parses symbols such as "D", "Bm7", "F#m7b5", "Dadd9/F#", "Bb/D". Returns nil when unrecognised.
    static func parse(_ text: String, flats defaultFlats: Bool = false) -> Chord? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let head = parts.first else { return nil }
        guard let rootNote = parseNote(String(head)) else { return nil }
        guard let quality = ChordQuality.aliases[rootNote.rest] else { return nil }
        var bassPC: Int? = nil
        var bassFlat = false
        var bassSharp = false
        if parts.count == 2 {
            guard let b = parseNote(String(parts[1])), b.rest.isEmpty else { return nil }
            bassPC = b.pitchClass
            bassFlat = b.flat
            bassSharp = b.sharp
        }
        var flats = defaultFlats
        if rootNote.sharp || bassSharp { flats = false }
        if rootNote.flat || bassFlat { if !(rootNote.sharp || bassSharp) { flats = true } }
        return Chord(root: rootNote.pitchClass, quality: quality, bass: bassPC, flats: flats)
    }
}
