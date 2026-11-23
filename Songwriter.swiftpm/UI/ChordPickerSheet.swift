import SwiftUI

struct ChordPickerSheet: View {
    @ObservedObject var session: ProjectSession
    var beat: Double
    @State var root = 0
    @State var quality: ChordQuality = .maj
    @State var bass: Int? = nil
    @State var loaded = false
    @Environment(\.dismiss) var dismiss

    var flats: Bool { session.song.key.usesFlats }

    var chord: Chord { Chord(root: root, quality: quality, bass: bass, flats: flats) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Chord at bar \(barLabel)") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 18) {
                        ChordText(chord: chord, size: 44)
                            .frame(minWidth: 140, alignment: .leading)
                        TextActionButton(title: "Hear", systemName: "speaker.wave.2") { session.auditionChord(chord) }
                        Spacer()
                        TextActionButton(title: "Set chord", prominent: true) { set() }
                    }
                    label("Key chords")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(session.song.key.chordPad()) { d in
                                Button(action: {
                                    root = d.chord.root
                                    quality = d.chord.quality
                                    bass = nil
                                    session.auditionChord(d.chord)
                                }) {
                                    VStack(spacing: 0) {
                                        Text(d.label).font(Theme.ui(11)).foregroundColor(Theme.ink2)
                                        ChordText(chord: d.chord, size: 20)
                                    }
                                    .frame(minWidth: 60, minHeight: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1.2))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    label("Root")
                    noteGrid(selection: Binding(get: { root }, set: { root = $0 }), allowNone: false)
                    label("Quality")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(ChordQuality.allCases, id: \.self) { q in
                            choice(title: q.pickerLabel, selected: quality == q) { quality = q }
                        }
                    }
                    label("Slash bass (optional)")
                    noteGrid(selection: Binding(get: { bass ?? -1 }, set: { bass = $0 < 0 ? nil : $0 }), allowNone: true)
                    if session.song.chordEvent(atBeat: beat) != nil {
                        TextActionButton(title: "Clear this chord", systemName: "trash") {
                            session.edit { $0.setChord(nil, atBeat: beat) }
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Theme.paper)
        .onAppear { load() }
    }

    private var barLabel: String {
        let p = session.song.formattedPosition(beat: beat)
        let half = (beat - Double(p.bar - 1) * session.song.beatsPerBar) > 0.01
        return half ? "\(p.bar) (second half)" : "\(p.bar)"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let e = session.song.chordEvent(atBeat: beat) ?? session.song.chords.last(where: { $0.startBeat <= beat }) {
            root = e.chord.root
            quality = e.chord.quality
            bass = e.chord.bass
        } else {
            root = session.song.key.root
        }
    }

    private func set() {
        session.edit { $0.setChord(chord, atBeat: beat) }
        dismiss()
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.serifItalic(15)).foregroundColor(Theme.ink2)
    }

    private func choice(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.uiMedium(15))
                .foregroundColor(selected ? Theme.onAccent : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.red : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.red : Theme.line, lineWidth: 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func noteGrid(selection: Binding<Int>, allowNone: Bool) -> some View {
        let names = (0..<12).map { NoteName.display(NoteName.name($0, flats: flats)) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            if allowNone {
                choice(title: "None", selected: selection.wrappedValue < 0) { selection.wrappedValue = -1 }
            }
            ForEach(0..<12, id: \.self) { pc in
                choice(title: names[pc], selected: selection.wrappedValue == pc) { selection.wrappedValue = pc }
            }
        }
    }
}
