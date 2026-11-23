import SwiftUI

struct ChartScreen: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        let song = session.song
        let lines = ChartLayout.lines(for: song)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(Theme.serifMediumItalic(30)).foregroundColor(Theme.ink)
                        Text("Key of \(song.key.displayName)  \u{2022}  \(Int(song.tempo.rounded())) bpm  \u{2022}  \(song.timeSignature.label)")
                            .font(Theme.serifItalic(15)).foregroundColor(Theme.ink2)
                    }
                    .padding(.bottom, 14)
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        ChartLineView(session: session, line: line, song: song)
                            .id(index)
                    }
                    if lines.isEmpty {
                        Text("Add sections and chords in the Tracks view to build the lead sheet.")
                            .font(Theme.serifItalic(17)).foregroundColor(Theme.ink2)
                    }
                }
                .padding(28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: session.playingBar) { _, bar in
                guard session.isPlaying, bar >= 0 else { return }
                if let i = lines.firstIndex(where: { l in l.bars.contains { $0.bar == bar } }) {
                    withAnimation { proxy.scrollTo(i, anchor: .center) }
                }
            }
        }
    }
}

struct ChartLineView: View {
    @ObservedObject var session: ProjectSession
    var line: ChartLine
    var song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if line.showSectionHeader, song.sections.indices.contains(line.sectionIndex) {
                let s = song.sections[line.sectionIndex]
                HStack(spacing: 8) {
                    SectionBadge(letter: s.letter, size: 24)
                    Text(s.name).font(Theme.serifItalic(19)).foregroundColor(Theme.ink)
                }
                .padding(.top, 14)
            }
            if !line.bars.isEmpty {
                HStack(spacing: 0) {
                    ForEach(line.bars, id: \.bar) { bar in
                        barCell(bar)
                    }
                    ForEach(0..<max(0, 4 - line.bars.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
            }
            if !line.lyric.isEmpty {
                Text(line.lyric).font(Theme.serif(17)).foregroundColor(Theme.ink2)
                    .padding(.leading, 6)
            }
        }
    }

    private func barCell(_ bar: ChartBar) -> some View {
        let active = session.isPlaying && session.playingBar == bar.bar
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(active ? Theme.red.opacity(0.12) : Color.clear)
            HStack(spacing: 10) {
                ForEach(Array(bar.chords.enumerated()), id: \.offset) { _, c in
                    ChordText(chord: c.chord, size: 24, color: Theme.ink)
                }
            }
            .padding(.leading, 8)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}

struct LyricsScreen: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(session.song.sections) { s in
                    LyricsBlock(session: session, sectionID: s.id)
                }
                if session.song.sections.isEmpty {
                    Text("Add a section first (tap a section name in the ruler, or use Tempo, key and sections).")
                        .font(Theme.serifItalic(17)).foregroundColor(Theme.ink2)
                }
            }
            .padding(28)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct LyricsBlock: View {
    @ObservedObject var session: ProjectSession
    var sectionID: UUID
    @FocusState var focused: Bool

    var body: some View {
        if let index = session.song.sections.firstIndex(where: { $0.id == sectionID }) {
            let s = session.song.sections[index]
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SectionBadge(letter: s.letter, size: 24)
                    Text(s.name).font(Theme.serifItalic(19)).foregroundColor(Theme.ink)
                    Text("\(s.lengthBars) bars").font(Theme.ui(13)).foregroundColor(Theme.ink2)
                }
                TextEditor(text: Binding(
                    get: { session.song.sections.first(where: { $0.id == sectionID })?.lyrics ?? "" },
                    set: { newValue in
                        session.mutate { song in
                            if let i = song.sections.firstIndex(where: { $0.id == sectionID }) { song.sections[i].lyrics = newValue }
                        }
                    }
                ))
                .focused($focused)
                .font(Theme.serif(18))
                .foregroundColor(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 110)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Theme.red : Theme.line, lineWidth: 1.2))
                .onChange(of: focused) { _, isFocused in
                    if isFocused { session.beginGesture() } else { session.endGesture() }
                }
            }
        }
    }
}
