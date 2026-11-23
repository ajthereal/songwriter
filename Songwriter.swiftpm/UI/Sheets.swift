import SwiftUI

// MARK: - Tempo, key, time signature

struct TempoSheet: View {
    @ObservedObject var session: ProjectSession
    @Environment(\.dismiss) var dismiss
    @State var tempoText = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Tempo, key and time") { dismiss() }
            Form {
                tempoRows
                Picker("Key", selection: Binding(
                    get: { session.song.key.root },
                    set: { r in session.edit { $0.key = SongKey(root: r, minor: $0.key.minor) } }
                )) {
                    ForEach(0..<12, id: \.self) { r in
                        Text(NoteName.display(session.song.key.minor ? SongKey.minorNames[r] : SongKey.majorNames[r])).tag(r)
                    }
                }
                Picker("Mode", selection: Binding(
                    get: { session.song.key.minor },
                    set: { m in session.edit { $0.key = SongKey(root: $0.key.root, minor: m) } }
                )) {
                    Text("Major").tag(false)
                    Text("Minor").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Time signature", selection: Binding(
                    get: { session.song.timeSignature },
                    set: { t in
                        if session.isPlaying { session.stop() }
                        session.edit { $0.setTimeSignature(t) }
                    }
                )) {
                    ForEach(TimeSignature.supported, id: \.self) { t in Text(t.label).tag(t) }
                }
                .pickerStyle(.segmented)
                Button("Edit sections") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { session.sheet = .sections }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.paper)
        .onAppear { tempoText = "\(Int(session.song.tempo.rounded()))" }
    }

    private var tempoRows: some View {
        Group {
            HStack {
                Text("Tempo").font(Theme.ui(16))
                Spacer()
                TextField("BPM", text: $tempoText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onSubmit { applyText() }
                Text("bpm").font(Theme.ui(14)).foregroundColor(Theme.ink2)
                Stepper("", onIncrement: { setTempo(session.song.tempo + 1) }, onDecrement: { setTempo(session.song.tempo - 1) })
                    .labelsHidden()
            }
            Slider(value: Binding(
                get: { session.song.tempo },
                set: { setTempo($0.rounded()) }
            ), in: 40...240)
        }
    }

    private func applyText() {
        guard let v = Double(tempoText.trimmingCharacters(in: .whitespaces)) else {
            ErrorCenter.post("Tempo must be a number between 40 and 240.", warning: true)
            tempoText = "\(Int(session.song.tempo.rounded()))"
            return
        }
        setTempo(v)
    }

    private func setTempo(_ value: Double) {
        let t = min(240, max(40, value))
        if t != value { ErrorCenter.post("Tempo is limited to 40 to 240 bpm.", warning: true) }
        if session.isPlaying { session.stop() }
        session.edit { $0.tempo = t }
        tempoText = "\(Int(t.rounded()))"
    }
}

// MARK: - Sections

struct SectionsSheet: View {
    @ObservedObject var session: ProjectSession
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Sections") { dismiss() }
            Text("Moving or resizing a section moves the chords and regions inside it.")
                .font(Theme.serifItalic(14)).foregroundColor(Theme.ink2)
                .padding(.horizontal, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            List {
                ForEach(Array(session.song.sections.enumerated()), id: \.element.id) { index, s in
                    sectionRow(index: index, section: s)
                }
                Button(action: addSection) {
                    Label("Add section", systemImage: "plus").font(Theme.uiMedium(16))
                }
                .frame(minHeight: 44)
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.paper)
    }

    private func sectionRow(index: Int, section s: SongSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Letter", text: Binding(
                    get: { s.letter },
                    set: { v in session.mutate { $0.renameSection(id: s.id, name: s.name, letter: String(v.prefix(2))) } }
                ))
                .frame(width: 44)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                TextField("Name", text: Binding(
                    get: { s.name },
                    set: { v in session.mutate { $0.renameSection(id: s.id, name: v) } }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Stepper("\(s.lengthBars) bars", onIncrement: { session.edit { $0.resizeSection(id: s.id, bars: s.lengthBars + 1) } },
                        onDecrement: { session.edit { $0.resizeSection(id: s.id, bars: s.lengthBars - 1) } })
                    .font(Theme.ui(15))
                Spacer()
                IconButton(systemName: "arrow.up", label: "Move up", enabled: index > 0) {
                    session.edit { $0.moveSection(from: index, to: index - 1) }
                }
                IconButton(systemName: "arrow.down", label: "Move down", enabled: index < session.song.sections.count - 1) {
                    session.edit { $0.moveSection(from: index, to: index + 1) }
                }
                IconButton(systemName: "plus.square.on.square", label: "Duplicate section") {
                    session.edit { $0.duplicateSection(id: s.id) }
                }
                IconButton(systemName: "trash", label: "Delete section", enabled: session.song.sections.count > 1, color: Theme.red) {
                    session.edit { $0.deleteSection(id: s.id) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func addSection() {
        let letters = ["A", "B", "C", "D", "E", "F", "G"]
        let used = Set(session.song.sections.map { $0.letter })
        let letter = letters.first { !used.contains($0) } ?? "X"
        session.edit { $0.addSection(name: "Section", letter: letter, bars: 4) }
    }
}

// MARK: - Add track

struct AddTrackSheet: View {
    @ObservedObject var session: ProjectSession
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New track") { dismiss() }
            List {
                Button(action: { add(.audio, .grandPiano) }) {
                    row(title: "Audio", subtitle: "Record a vocal or an instrument with a microphone", color: .vocal)
                }
                ForEach(InstrumentKind.allCases, id: \.self) { inst in
                    Button(action: { add(.instrument, inst) }) {
                        row(title: inst.displayName, subtitle: inst.isDrums ? "Plays a drum kit" : "Plays a built-in sound", color: inst.defaultColor)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.paper)
    }

    private func row(title: String, subtitle: String, color: TrackColorKey) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.palette(color).caption).frame(width: 5, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.uiSemibold(17)).foregroundColor(Theme.ink)
                Text(subtitle).font(Theme.serifItalic(14)).foregroundColor(Theme.ink2)
            }
            Spacer()
        }
        .frame(minHeight: 48)
    }

    private func add(_ kind: TrackKind, _ inst: InstrumentKind) {
        session.addTrack(kind: kind, instrument: inst)
        dismiss()
    }
}

// MARK: - Track settings

struct TrackSheet: View {
    @ObservedObject var session: ProjectSession
    var trackID: UUID
    @Environment(\.dismiss) var dismiss
    @State var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Track") { dismiss() }
            if let t = session.song.tracks.first(where: { $0.id == trackID }) {
                Form {
                    TextField("Name", text: Binding(
                        get: { t.name },
                        set: { v in session.updateTrack(trackID, undo: false) { $0.name = v } }
                    ))
                    colorRow(t)
                    if t.kind == .instrument { instrumentRows(t) }
                    mixRows(t)
                    if t.kind == .audio { vocalRows(t) }
                    Button("Delete track", role: .destructive) { confirmDelete = true }
                }
                .scrollContentBackground(.hidden)
            } else {
                Text("This track no longer exists.").font(Theme.serifItalic(16)).padding(30)
                Spacer()
            }
        }
        .background(Theme.paper)
        .alert("Delete this track?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                session.deleteTrack(trackID)
                dismiss()
            }
        } message: {
            Text("The track and its regions will be removed. Recorded files stay in the project folder. You can undo this.")
        }
    }

    private func colorRow(_ t: Track) -> some View {
        HStack {
            Text("Colour").font(Theme.ui(16))
            Spacer()
            ForEach(TrackColorKey.allCases, id: \.self) { key in
                Button(action: { session.updateTrack(trackID) { $0.colorKey = key } }) {
                    Circle()
                        .fill(Theme.palette(key).caption)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Theme.ink, lineWidth: t.colorKey == key ? 2.5 : 0).padding(-3))
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key.displayName)
            }
        }
    }

    @ViewBuilder
    private func instrumentRows(_ t: Track) -> some View {
        Picker("Instrument", selection: Binding(
            get: { t.instrument },
            set: { inst in
                if session.isPlaying { session.stop() }
                session.updateTrack(trackID) { tr in
                    tr.instrument = inst
                    if !inst.styles.contains(tr.style) { tr.style = inst.defaultStyle }
                }
            }
        )) {
            ForEach(InstrumentKind.allCases, id: \.self) { i in Text(i.displayName).tag(i) }
        }
        Toggle("Follow chords", isOn: Binding(
            get: { t.follow },
            set: { v in session.updateTrack(trackID) { $0.follow = v } }
        ))
        if t.follow {
            Picker("Style", selection: Binding(
                get: { t.style },
                set: { st in session.updateTrack(trackID) { $0.style = st } }
            )) {
                ForEach(t.instrument.styles, id: \.self) { st in Text(st.displayName).tag(st) }
            }
            Button("Make editable (convert to regions)") {
                session.edit { $0.makeEditable(trackID: trackID) }
            }
        }
    }

    @ViewBuilder
    private func mixRows(_ t: Track) -> some View {
        HStack {
            Text("Volume").font(Theme.ui(16))
            Slider(value: Binding(
                get: { t.volume },
                set: { v in session.updateTrack(trackID, undo: false) { $0.volume = v } }
            ), in: 0...1.2)
        }
        HStack {
            Text("Pan").font(Theme.ui(16))
            Slider(value: Binding(
                get: { t.pan },
                set: { v in session.updateTrack(trackID, undo: false) { $0.pan = v } }
            ), in: -1...1)
        }
    }

    @ViewBuilder
    private func vocalRows(_ t: Track) -> some View {
        Toggle("Vocal chain (high-pass, presence, compressor)", isOn: Binding(
            get: { t.vocalChain },
            set: { v in session.updateTrack(trackID) { $0.vocalChain = v } }
        ))
        HStack {
            Text("Reverb").font(Theme.ui(16))
            Slider(value: Binding(
                get: { t.reverbAmount },
                set: { v in session.updateTrack(trackID, undo: false) { $0.reverbAmount = v } }
            ), in: 0...1)
        }
    }
}
