import Foundation

struct Note: Codable, Equatable, Identifiable {
    var id: UUID
    var pitch: Int
    /// Beats relative to the region start.
    var start: Double
    var length: Double
    var velocity: Int

    init(id: UUID = UUID(), pitch: Int, start: Double, length: Double, velocity: Int = 90) {
        self.id = id
        self.pitch = pitch
        self.start = start
        self.length = length
        self.velocity = velocity
    }
}

struct PedalEvent: Codable, Equatable {
    /// Beats relative to the region start.
    var beat: Double
    var down: Bool
}

struct Take: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    /// File name inside the project's audio folder.
    var fileName: String
    /// Seconds into the file at which the owning region's start lines up (latency already applied).
    var offset: Double
    /// Usable length in seconds.
    var duration: Double

    init(id: UUID = UUID(), name: String, fileName: String, offset: Double, duration: Double) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.offset = offset
        self.duration = duration
    }
}

enum RegionKind: String, Codable {
    case midi
    case audio
}

struct Region: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var kind: RegionKind
    var startBeat: Double
    var lengthBeats: Double
    var notes: [Note]
    var pedal: [PedalEvent]
    var takes: [Take]
    var activeTake: Int
    /// Extra seconds skipped in the active take (set by trimming and splitting).
    var audioOffset: Double

    init(id: UUID = UUID(), name: String, kind: RegionKind, startBeat: Double, lengthBeats: Double,
         notes: [Note] = [], pedal: [PedalEvent] = [], takes: [Take] = [], activeTake: Int = 0, audioOffset: Double = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.startBeat = startBeat
        self.lengthBeats = lengthBeats
        self.notes = notes
        self.pedal = pedal
        self.takes = takes
        self.activeTake = activeTake
        self.audioOffset = audioOffset
    }

    var endBeat: Double { startBeat + lengthBeats }

    var activeTakeValue: Take? {
        guard kind == .audio, takes.indices.contains(activeTake) else { return nil }
        return takes[activeTake]
    }

    /// A copy with fresh identifiers (used by duplicate / loop / split).
    func copyWithNewIDs() -> Region {
        var r = self
        r.id = UUID()
        r.notes = notes.map { n in
            var m = n
            m.id = UUID()
            return m
        }
        return r
    }
}

enum TrackKind: String, Codable {
    case audio
    case instrument
}

enum InstrumentKind: String, Codable, CaseIterable, Equatable {
    case grandPiano
    case ePiano
    case bass
    case drums
    case pad
    case strings

    var displayName: String {
        switch self {
        case .grandPiano: return "Grand Piano"
        case .ePiano: return "E-Piano"
        case .bass: return "Bass"
        case .drums: return "Drums"
        case .pad: return "Pad"
        case .strings: return "Strings"
        }
    }

    /// General MIDI program number in the bundled SoundFont.
    var program: Int {
        switch self {
        case .grandPiano: return 0
        case .ePiano: return 4
        case .bass: return 33
        case .drums: return 0
        case .pad: return 89
        case .strings: return 48
        }
    }

    var isDrums: Bool { self == .drums }

    var styles: [BandStyle] {
        switch self {
        case .grandPiano: return [.pianoBallad, .pianoPop, .pianoSustained]
        case .ePiano: return [.epPads, .epComp]
        case .bass: return [.bassRoots, .bassRootFive, .bassEighths]
        case .drums: return [.drumsBallad, .drumsPop, .drumsHalfTime, .drumsOff]
        case .pad, .strings: return [.padSustained]
        }
    }

    var defaultStyle: BandStyle { styles[0] }

    var defaultColor: TrackColorKey {
        switch self {
        case .grandPiano: return .piano
        case .ePiano: return .ePiano
        case .bass: return .bass
        case .drums: return .drums
        case .pad: return .ePiano
        case .strings: return .audio2
        }
    }
}

enum BandStyle: String, Codable, CaseIterable, Equatable {
    case pianoBallad
    case pianoPop
    case pianoSustained
    case epPads
    case epComp
    case bassRoots
    case bassRootFive
    case bassEighths
    case drumsBallad
    case drumsPop
    case drumsHalfTime
    case drumsOff
    case padSustained

    var displayName: String {
        switch self {
        case .pianoBallad: return "Ballad comp"
        case .pianoPop: return "Pop eighths"
        case .pianoSustained: return "Sustained"
        case .epPads: return "Pads"
        case .epComp: return "Comp"
        case .bassRoots: return "Roots"
        case .bassRootFive: return "Root-five"
        case .bassEighths: return "Eighths"
        case .drumsBallad: return "Ballad"
        case .drumsPop: return "Pop"
        case .drumsHalfTime: return "Half-time"
        case .drumsOff: return "Off"
        case .padSustained: return "Sustained"
        }
    }
}

enum TrackColorKey: String, Codable, CaseIterable, Equatable {
    case vocal
    case audio2
    case piano
    case ePiano
    case bass
    case drums

    var displayName: String {
        switch self {
        case .vocal: return "Blue"
        case .audio2: return "Slate"
        case .piano: return "Amber"
        case .ePiano: return "Violet"
        case .bass: return "Green"
        case .drums: return "Red"
        }
    }
}

struct Track: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var kind: TrackKind
    var instrument: InstrumentKind
    var colorKey: TrackColorKey
    /// 0...1, 0.8 is the default.
    var volume: Double
    /// -1...1
    var pan: Double
    var muted: Bool
    var solo: Bool
    var follow: Bool
    var style: BandStyle
    var regions: [Region]
    var vocalChain: Bool
    var reverbAmount: Double

    init(id: UUID = UUID(), name: String, kind: TrackKind, instrument: InstrumentKind = .grandPiano,
         colorKey: TrackColorKey? = nil, volume: Double = 0.8, pan: Double = 0, muted: Bool = false, solo: Bool = false,
         follow: Bool = false, style: BandStyle? = nil, regions: [Region] = [], vocalChain: Bool = true, reverbAmount: Double = 0.2) {
        self.id = id
        self.name = name
        self.kind = kind
        self.instrument = instrument
        self.colorKey = colorKey ?? (kind == .audio ? .vocal : instrument.defaultColor)
        self.volume = volume
        self.pan = pan
        self.muted = muted
        self.solo = solo
        self.follow = follow
        self.style = style ?? instrument.defaultStyle
        self.regions = regions
        self.vocalChain = vocalChain
        self.reverbAmount = reverbAmount
    }

    var instrumentLabel: String {
        switch kind {
        case .audio: return "Audio"
        case .instrument: return instrument.displayName
        }
    }
}

struct SongSection: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var letter: String
    var startBar: Int
    var lengthBars: Int
    var lyrics: String

    init(id: UUID = UUID(), name: String, letter: String, startBar: Int = 0, lengthBars: Int, lyrics: String = "") {
        self.id = id
        self.name = name
        self.letter = letter
        self.startBar = startBar
        self.lengthBars = lengthBars
        self.lyrics = lyrics
    }

    var endBar: Int { startBar + lengthBars }
}

struct ChordEvent: Codable, Equatable, Identifiable {
    var id: UUID
    /// Absolute beat position (bar start or half bar).
    var startBeat: Double
    var chord: Chord

    init(id: UUID = UUID(), startBeat: Double, chord: Chord) {
        self.id = id
        self.startBeat = startBeat
        self.chord = chord
    }
}

struct CycleRange: Codable, Equatable {
    var startBar: Int
    var endBar: Int
}

struct Song: Codable, Equatable, Identifiable {
    static let currentVersion = 1

    var version: Int
    var id: UUID
    var title: String
    var tempo: Double
    var key: SongKey
    var timeSignature: TimeSignature
    var sections: [SongSection]
    var chords: [ChordEvent]
    var tracks: [Track]
    var cycle: CycleRange

    init(id: UUID = UUID(), title: String = "Untitled Song", tempo: Double = 90, key: SongKey = SongKey(root: 0),
         timeSignature: TimeSignature = .fourFour, sections: [SongSection] = [], chords: [ChordEvent] = [],
         tracks: [Track] = [], cycle: CycleRange = CycleRange(startBar: 0, endBar: 4)) {
        self.version = Song.currentVersion
        self.id = id
        self.title = title
        self.tempo = tempo
        self.key = key
        self.timeSignature = timeSignature
        self.sections = sections
        self.chords = chords
        self.tracks = tracks
        self.cycle = cycle
    }
}

/// Reads and writes a song as JSON with a schema version check.
enum SongCodec {
    enum CodecError: Error, Equatable {
        case unsupportedVersion(Int)
        case unreadable
    }

    static func encode(_ song: Song) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(song)
    }

    static func decode(_ data: Data) throws -> Song {
        struct VersionProbe: Decodable { var version: Int }
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { throw CodecError.unreadable }
        if probe.version > Song.currentVersion || probe.version < 1 { throw CodecError.unsupportedVersion(probe.version) }
        do {
            return try decoder.decode(Song.self, from: data)
        } catch {
            throw CodecError.unreadable
        }
    }
}
