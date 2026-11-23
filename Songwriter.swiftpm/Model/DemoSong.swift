import Foundation

extension Song {
    /// The song seeded on first launch.
    static func demo() -> Song {
        var song = Song(title: "Untitled Song 3", tempo: 84, key: SongKey(root: 2, minor: false), timeSignature: .fourFour)
        let intro = SongSection(name: "Intro", letter: "I", lengthBars: 2)
        let verse = SongSection(name: "Verse", letter: "A", lengthBars: 8,
                                lyrics: "Morning light on the window sill\nI hum a line I haven't finished\nCoffee cooling, the street is still\nAnd all my plans are small and quiet")
        let pre = SongSection(name: "Pre", letter: "B", lengthBars: 2, lyrics: "Then it builds, I can feel it")
        let chorus = SongSection(name: "Chorus", letter: "C", lengthBars: 4, lyrics: "Sing it loud, sing it now\nWe were always on our way")
        song.sections = Song.normalized([intro, verse, pre, chorus])
        let bpb = song.beatsPerBar

        func put(_ bar: Int, _ offset: Double, _ symbol: String) {
            if let c = Chord.parse(symbol, flats: false) {
                song.chords.append(ChordEvent(startBeat: Double(bar) * bpb + offset, chord: c))
            }
        }
        // Intro (bars 0-1)
        put(0, 0, "Dadd9"); put(1, 0, "A/C#")
        // Verse A (bars 2-9)
        put(2, 0, "D"); put(3, 0, "A/C#"); put(4, 0, "Bm7"); put(5, 0, "G")
        put(6, 0, "D"); put(7, 0, "A"); put(8, 0, "Bm7"); put(9, 0, "G")
        // Pre B (bars 10-11)
        put(10, 0, "Em7"); put(11, 0, "Asus4"); put(11, 2, "A")
        // Chorus C (bars 12-15)
        put(12, 0, "D"); put(13, 0, "A"); put(14, 0, "Bm7"); put(15, 0, "G")
        song.chords.sort { $0.startBeat < $1.startBeat }

        let vocal = Track(name: "Lead Vocal", kind: .audio, colorKey: .vocal)
        let piano = Track(name: "Grand Piano", kind: .instrument, instrument: .grandPiano, follow: true, style: .pianoBallad)
        let bass = Track(name: "Bass", kind: .instrument, instrument: .bass, follow: true, style: .bassRoots)
        let drums = Track(name: "Drums", kind: .instrument, instrument: .drums, follow: true, style: .drumsBallad)
        var ep = Track(name: "E-Piano", kind: .instrument, instrument: .ePiano, follow: false, style: .epPads)
        song.tracks = [vocal, piano, bass, drums, ep]

        // E-Piano pads only in the chorus, as a normal editable region.
        if let chorusSection = song.sections.first(where: { $0.name == "Chorus" }) {
            let a = song.barStartBeat(chorusSection.startBar)
            let b = song.barStartBeat(chorusSection.endBar)
            let gen = BandGenerator.generate(song: song, instrument: .ePiano, style: .epPads, from: a, to: b)
            let notes = gen.map { Note(pitch: $0.pitch, start: $0.start - a, length: $0.length, velocity: $0.velocity) }
            ep.regions = [Region(name: "Chorus pads", kind: .midi, startBeat: a, lengthBeats: b - a, notes: notes)]
            song.tracks[4] = ep
        }
        song.cycle = CycleRange(startBar: 12, endBar: 16)
        return song
    }
}
