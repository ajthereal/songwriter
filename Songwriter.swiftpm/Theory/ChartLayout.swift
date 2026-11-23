import Foundation

struct ChartChord: Equatable {
    var beatInBar: Double
    var chord: Chord
}

struct ChartBar: Equatable {
    var bar: Int
    var chords: [ChartChord]
}

struct ChartLine: Equatable {
    var sectionIndex: Int
    var showSectionHeader: Bool
    var bars: [ChartBar]
    var lyric: String
}

/// Lead sheet layout: four bars per line, chords per bar, lyrics under each line.
enum ChartLayout {
    static func lines(for song: Song, barsPerLine: Int = 4) -> [ChartLine] {
        var out: [ChartLine] = []
        let bpb = song.beatsPerBar
        let perLine = max(1, barsPerLine)
        var lastChord: Chord? = nil
        for (si, s) in song.sections.enumerated() {
            let lyricLines = s.lyrics.components(separatedBy: "\n")
            var lyricIndex = 0
            var bar = s.startBar
            var first = true
            while bar < s.endBar {
                var bars: [ChartBar] = []
                let lineEnd = min(bar + perLine, s.endBar)
                for b in bar..<lineEnd {
                    let a = Double(b) * bpb
                    var chords: [ChartChord] = []
                    for e in song.chords where e.startBeat >= a - 1e-9 && e.startBeat < a + bpb - 1e-9 {
                        chords.append(ChartChord(beatInBar: e.startBeat - a, chord: e.chord))
                    }
                    chords.sort { $0.beatInBar < $1.beatInBar }
                    if let c = chords.last { lastChord = c.chord }
                    bars.append(ChartBar(bar: b, chords: chords))
                }
                let lyric = lyricIndex < lyricLines.count ? lyricLines[lyricIndex] : ""
                lyricIndex += 1
                out.append(ChartLine(sectionIndex: si, showSectionHeader: first, bars: bars, lyric: lyric))
                first = false
                bar = lineEnd
            }
            // Remaining lyric lines that did not fit under a bar line.
            while lyricIndex < lyricLines.count {
                let rest = lyricLines[lyricIndex]
                lyricIndex += 1
                if rest.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                out.append(ChartLine(sectionIndex: si, showSectionHeader: false, bars: [], lyric: rest))
            }
        }
        _ = lastChord
        return out
    }
}
