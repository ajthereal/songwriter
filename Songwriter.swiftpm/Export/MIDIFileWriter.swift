import Foundation

/// Writes a Standard MIDI File (type 1).
enum MIDIFileWriter {
    static let ticksPerQuarter = 480

    /// Variable length quantity encoding.
    static func vlq(_ value: Int) -> [UInt8] {
        var v = UInt32(max(0, min(value, 0x0FFFFFFF)))
        var bytes: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return bytes
    }

    private struct Event {
        var tick: Int
        var order: Int
        var bytes: [UInt8]
    }

    private static func be32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func be16(_ v: Int) -> [UInt8] {
        [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func meta(_ type: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [0xFF, type] + vlq(payload.count) + payload
    }

    private static func text(_ type: UInt8, _ s: String) -> [UInt8] {
        meta(type, Array(s.utf8))
    }

    private static func tick(_ beat: Double) -> Int {
        Int((beat * Double(ticksPerQuarter)).rounded())
    }

    private static func trackChunk(_ events: [Event]) -> [UInt8] {
        let sorted = events.enumerated().sorted { a, b in
            if a.element.tick != b.element.tick { return a.element.tick < b.element.tick }
            if a.element.order != b.element.order { return a.element.order < b.element.order }
            return a.offset < b.offset
        }.map { $0.element }
        var body: [UInt8] = []
        var last = 0
        for e in sorted {
            body += vlq(e.tick - last)
            body += e.bytes
            last = e.tick
        }
        body += vlq(0)
        body += [0xFF, 0x2F, 0x00]
        return Array("MTrk".utf8) + be32(body.count) + body
    }

    /// Key signature: number of sharps (positive) or flats (negative) for a major key root.
    static func accidentals(forMajorRoot pc: Int) -> Int {
        let table = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5]
        return table[((pc % 12) + 12) % 12]
    }

    static func data(for song: Song) -> Data {
        var tracks: [[UInt8]] = []

        // Track 0: tempo map, time signature, key, section markers.
        var conductor: [Event] = []
        conductor.append(Event(tick: 0, order: 0, bytes: text(0x03, song.title)))
        let microsPerQuarter = Int((60_000_000.0 / max(song.tempo, 1)).rounded())
        conductor.append(Event(tick: 0, order: 1, bytes: meta(0x51, [UInt8((microsPerQuarter >> 16) & 0xFF),
                                                                    UInt8((microsPerQuarter >> 8) & 0xFF),
                                                                    UInt8(microsPerQuarter & 0xFF)])))
        let den = song.timeSignature.denominator
        let denPower = den == 8 ? 3 : (den == 2 ? 1 : 2)
        let clocks = song.timeSignature.isCompound ? 36 : 24
        conductor.append(Event(tick: 0, order: 1, bytes: meta(0x58, [UInt8(song.timeSignature.numerator), UInt8(denPower), UInt8(clocks), 8])))
        let majorRoot = song.key.minor ? (song.key.root + 3) % 12 : song.key.root
        let sf = accidentals(forMajorRoot: majorRoot)
        conductor.append(Event(tick: 0, order: 1, bytes: meta(0x59, [UInt8(bitPattern: Int8(sf)), song.key.minor ? 1 : 0])))
        for s in song.sections {
            conductor.append(Event(tick: tick(song.barStartBeat(s.startBar)), order: 2, bytes: text(0x06, s.name)))
        }
        tracks.append(trackChunk(conductor))

        // Chord marker track.
        var chordEvents: [Event] = [Event(tick: 0, order: 0, bytes: text(0x03, "Chords"))]
        for c in song.chords {
            chordEvents.append(Event(tick: tick(c.startBeat), order: 1, bytes: text(0x06, c.chord.symbol)))
        }
        tracks.append(trackChunk(chordEvents))

        // One track per instrument track.
        let melodicChannels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15]
        var nextMelodic = 0
        for t in song.tracks where t.kind == .instrument {
            let channel: Int
            if t.instrument.isDrums {
                channel = 9
            } else {
                channel = melodicChannels[min(nextMelodic, melodicChannels.count - 1)]
                nextMelodic += 1
            }
            var ev: [Event] = []
            ev.append(Event(tick: 0, order: 0, bytes: text(0x03, t.name)))
            if !t.instrument.isDrums {
                ev.append(Event(tick: 0, order: 1, bytes: [UInt8(0xC0 | channel), UInt8(t.instrument.program)]))
            }
            for n in song.playbackNotes(for: t) {
                let on = tick(n.start)
                let off = max(on + 1, tick(n.start + n.length))
                let pitch = UInt8(max(0, min(127, n.pitch)))
                let vel = UInt8(max(1, min(127, n.velocity)))
                ev.append(Event(tick: on, order: 3, bytes: [UInt8(0x90 | channel), pitch, vel]))
                ev.append(Event(tick: off, order: 2, bytes: [UInt8(0x80 | channel), pitch, 0]))
            }
            for p in song.playbackPedal(for: t) {
                ev.append(Event(tick: tick(p.beat), order: 2, bytes: [UInt8(0xB0 | channel), 64, p.down ? 127 : 0]))
            }
            tracks.append(trackChunk(ev))
        }

        var out: [UInt8] = Array("MThd".utf8) + be32(6) + be16(1) + be16(tracks.count) + be16(ticksPerQuarter)
        for t in tracks { out += t }
        return Data(out)
    }
}
