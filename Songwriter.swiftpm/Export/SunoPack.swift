import Foundation

enum SunoPack {
    /// Maps a section name to the bracket tag used by Suno, numbering repeats (Verse 1, Verse 2).
    static func tags(for song: Song) -> [String] {
        var counts: [String: Int] = [:]
        var totals: [String: Int] = [:]
        for s in song.sections { totals[baseName(s.name), default: 0] += 1 }
        var out: [String] = []
        for s in song.sections {
            let base = baseName(s.name)
            counts[base, default: 0] += 1
            var label = tagLabel(base)
            if (totals[base] ?? 0) > 1 || base.lowercased() == "verse" {
                label += " \(counts[base] ?? 1)"
            }
            out.append("[" + label + "]")
        }
        return out
    }

    private static func baseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Drop a trailing number: "Verse 2" -> "Verse"
        var parts = trimmed.split(separator: " ").map(String.init)
        if let last = parts.last, Int(last) != nil, parts.count > 1 { parts.removeLast() }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? "Section" : joined
    }

    private static func tagLabel(_ base: String) -> String {
        switch base.lowercased() {
        case "pre", "pre-chorus", "prechorus", "pre chorus": return "Pre-Chorus"
        default: return base
        }
    }

    static func text(for song: Song, genre: String = "genre (edit me)", mood: String = "mood (edit me)") -> String {
        var lines: [String] = []
        let style = "\(genre), \(Int(song.tempo.rounded())) BPM, \(song.key.name), \(mood)"
        lines.append("Style: " + style)
        lines.append("")
        let tagList = tags(for: song)
        for (i, s) in song.sections.enumerated() {
            lines.append(tagList[i])
            let lyric = s.lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            if lyric.isEmpty {
                lines.append("(instrumental)")
            } else {
                lines.append(lyric)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
