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
    @FocusState var focusedSection: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(session.song.sections) { s in
                        LyricsBlock(session: session, sectionID: s.id, focus: $focusedSection)
                            .id(s.id)
                    }
                    if session.song.sections.isEmpty {
                        Text("Add a section first (tap a section name in the ruler, or use Tempo, key and sections).")
                            .font(Theme.serifItalic(17)).foregroundColor(Theme.ink2)
                    }
                    // Room so the last box can scroll above the keyboard.
                    Color.clear.frame(height: 320)
                }
                .padding(28)
                .frame(maxWidth: 800, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { focusedSection = nil })
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedSection) { _, id in
                guard let id = id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedSection = nil }
                }
            }
        }
    }
}

/// One editable lyrics box. Text is kept in local state so typing is never interrupted by model updates;
/// it is written to the song (one undo step per burst of typing) shortly after typing pauses, and when focus leaves.
struct LyricsBlock: View {
    @ObservedObject var session: ProjectSession
    var sectionID: UUID
    var focus: FocusState<UUID?>.Binding
    @State var text = ""
    @State var loaded = false
    @State var commitWork: DispatchWorkItem?

    private var modelText: String? {
        session.song.sections.first(where: { $0.id == sectionID })?.lyrics
    }

    var body: some View {
        if let s = session.song.sections.first(where: { $0.id == sectionID }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SectionBadge(letter: s.letter, size: 24)
                    Text(s.name).font(Theme.serifItalic(19)).foregroundColor(Theme.ink)
                    Text("\(s.lengthBars) bars").font(Theme.ui(13)).foregroundColor(Theme.ink2)
                }
                TextEditor(text: $text)
                    .focused(focus, equals: sectionID)
                    .font(Theme.serif(18))
                    .foregroundColor(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled(false)
                    .padding(10)
                    .frame(minHeight: 120)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(focus.wrappedValue == sectionID ? Theme.red : Theme.line, lineWidth: 1.2))
                    .onAppear {
                        if !loaded { text = s.lyrics; loaded = true }
                    }
                    .onChange(of: text) { _, newValue in scheduleCommit(newValue) }
                    .onChange(of: modelText) { _, newValue in
                        // External change (undo, redo): adopt it unless the user is typing here.
                        if focus.wrappedValue != sectionID, let v = newValue, v != text { text = v }
                    }
                    .onChange(of: focus.wrappedValue) { _, newFocus in
                        if newFocus != sectionID { commitNow() }
                    }
                    .onDisappear { commitNow() }
            }
        }
    }

    private func scheduleCommit(_ value: String) {
        guard loaded, value != modelText else { return }
        commitWork?.cancel()
        let work = DispatchWorkItem { commitNow() }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func commitNow() {
        commitWork?.cancel()
        commitWork = nil
        guard loaded, let current = modelText, current != text else { return }
        let value = text
        session.edit { song in
            if let i = song.sections.firstIndex(where: { $0.id == sectionID }) { song.sections[i].lyrics = value }
        }
    }
}
