import SwiftUI

struct ToolsBar: View {
    @ObservedObject var session: ProjectSession
    @State var loopTimes = 4
    @State var showMIDIPopover = false
    @State var showBluetooth = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(compact: false)
            content(compact: true)
            ScrollView(.horizontal, showsIndicators: false) { content(compact: true) }
        }
        .frame(height: 48)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .sheet(isPresented: $showBluetooth, onDismiss: { MIDIInput.shared.rescan() }) {
            BluetoothMIDIView(onDone: { showBluetooth = false })
        }
    }

    private func content(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Snap").font(Theme.serifItalic(14)).foregroundColor(Theme.ink2)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Picker("Snap", selection: $session.snap) {
                ForEach(SnapMode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            divider
            IconButton(systemName: "minus.magnifyingglass", label: "Zoom out") {
                session.setZoom(pxPerBar: session.pxPerBar / 1.25)
            }
            IconButton(systemName: "plus.magnifyingglass", label: "Zoom in") {
                session.setZoom(pxPerBar: session.pxPerBar * 1.25)
            }
            TextActionButton(title: "Follow", systemName: "arrow.right.to.line",
                             prominent: session.followOn && !session.followPaused, showTitle: !compact) {
                toggleFollow()
            }
            divider
            TextActionButton(title: "Split", systemName: "scissors", enabled: regionSelected, showTitle: !compact) { split() }
            TextActionButton(title: "Duplicate", systemName: "plus.square.on.square", enabled: regionSelected, showTitle: !compact) { duplicate() }
            Menu {
                ForEach([2, 4, 8, 16], id: \.self) { n in
                    Button("Loop \(n) times") { loop(n) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                    if !compact {
                        Text("Loop").font(Theme.uiMedium(15)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .foregroundColor(regionSelected ? Theme.ink : Theme.ink2.opacity(0.5))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1.2))
                .frame(minHeight: 44)
            }
            .disabled(!regionSelected)
            .accessibilityLabel("Loop")
            TextActionButton(title: "Delete", systemName: "trash", enabled: regionSelected, showTitle: !compact) { delete() }
            divider
            PillButton(title: "Chords", isOn: session.showChordPad) { session.showChordPad.toggle() }
            PillButton(title: "Keys", isOn: session.showKeyboard) { session.showKeyboard.toggle() }
            midiChip
        }
        .padding(.horizontal, 12)
    }

    private var midiChip: some View {
        Button(action: { showMIDIPopover = true }) {
            HStack(spacing: 5) {
                Image(systemName: "pianokeys").font(.system(size: 14, weight: .medium))
                Text(session.midiSourceCount > 0 ? "\(session.midiSourceCount) MIDI" : "No MIDI")
                    .font(Theme.uiMedium(14))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(session.midiSourceCount > 0 ? Theme.ink : Theme.ink2)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .overlay(Capsule().stroke(session.midiSourceCount > 0 ? Theme.ink2 : Theme.line, lineWidth: 1.2))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("MIDI devices")
        .popover(isPresented: $showMIDIPopover) {
            VStack(alignment: .leading, spacing: 12) {
                Text(midiStatus)
                    .font(Theme.serifItalic(15))
                    .foregroundColor(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: {
                    showMIDIPopover = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showBluetooth = true }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("Bluetooth MIDI").font(Theme.uiMedium(15))
                    }
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1.2))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func toggleFollow() {
        if session.followOn && session.followPaused {
            session.followPaused = false
        } else {
            session.followOn.toggle()
            session.followPaused = false
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 24)
    }

    private var regionSelected: Bool { session.selectedRegion != nil }

    private var midiStatus: String {
        session.midiSourceCount > 0
            ? "\(session.midiSourceCount) MIDI source\(session.midiSourceCount == 1 ? "" : "s") connected"
            : "No MIDI keyboard found. Plug it in with USB-C, or tap Bluetooth MIDI to pair it."
    }

    private func split() {
        guard let sel = session.selectedRegion else { return }
        let beat = session.snap.snap(session.displayBeat(), beatsPerBar: session.song.beatsPerBar)
        if beat <= sel.region.startBeat + 0.01 || beat >= sel.region.endBeat - 0.01 {
            ErrorCenter.post("Move the playhead inside the selected region, then tap Split.", warning: true)
            return
        }
        var newID: UUID?
        session.edit { s in newID = s.splitRegion(trackID: sel.track.id, regionID: sel.region.id, atBeat: beat) }
        if let id = newID { session.selectedRegionID = id }
    }

    private func duplicate() {
        guard let sel = session.selectedRegion else { return }
        var newID: UUID?
        session.edit { s in newID = s.duplicateRegion(trackID: sel.track.id, regionID: sel.region.id) }
        if let id = newID { session.selectedRegionID = id }
    }

    private func loop(_ n: Int) {
        guard let sel = session.selectedRegion else { return }
        session.edit { $0.loopRegion(trackID: sel.track.id, regionID: sel.region.id, times: n) }
    }

    private func delete() {
        guard let sel = session.selectedRegion else { return }
        session.edit { $0.deleteRegion(trackID: sel.track.id, regionID: sel.region.id) }
        session.selectedRegionID = nil
    }
}

struct ChordPadView: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        let pad = session.song.key.chordPad()
        HStack(spacing: 8) {
            Text("Chord pad")
                .font(Theme.serifItalic(14))
                .foregroundColor(Theme.ink2)
                .padding(.leading, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pad) { d in
                        VStack(spacing: 0) {
                            Text(d.label).font(Theme.ui(11)).foregroundColor(Theme.ink2)
                            ChordText(chord: d.chord, size: 20, color: Theme.ink)
                        }
                        .frame(minWidth: 62, minHeight: 44)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.paper))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1.2))
                        .contentShape(Rectangle())
                        .onTapGesture { session.auditionChord(d.chord) }
                        .onLongPressGesture(minimumDuration: 0.4) {
                            session.writeChordAtPlayhead(d.chord)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Text("Tap to hear, hold to write at the playhead")
                .font(Theme.serifItalic(12))
                .foregroundColor(Theme.ink2)
                .padding(.trailing, 12)
                .lineLimit(2)
                .frame(maxWidth: 150)
        }
        .frame(height: 56)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// On-screen two octave keyboard with octave shift.
struct KeyboardView: View {
    @ObservedObject var session: ProjectSession
    @State var baseOctave = 3
    @State var pressed = Set<Int>()

    private let whiteSteps = [0, 2, 4, 5, 7, 9, 11]
    private let blackAfter: [Int: Int] = [0: 1, 1: 3, 3: 6, 4: 8, 5: 10]

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                IconButton(systemName: "chevron.up", label: "Octave up", enabled: baseOctave < 6) { baseOctave += 1 }
                Text("C\(baseOctave)").font(Theme.condensedBold(14)).foregroundColor(Theme.ink2)
                IconButton(systemName: "chevron.down", label: "Octave down", enabled: baseOctave > 0) { baseOctave -= 1 }
            }
            .frame(width: 48)
            GeometryReader { geo in
                let whiteCount = 14
                let w = geo.size.width / CGFloat(whiteCount)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(0..<whiteCount, id: \.self) { i in
                            let pitch = pitchForWhite(i)
                            keyShape(pitch: pitch, black: false)
                                .frame(width: w, height: geo.size.height)
                        }
                    }
                    ForEach(0..<whiteCount, id: \.self) { i in
                        if let semis = blackAfter[i % 7] {
                            let pitch = (baseOctave + 1 + i / 7) * 12 + semis
                            keyShape(pitch: pitch, black: true)
                                .frame(width: w * 0.62, height: geo.size.height * 0.62)
                                .offset(x: CGFloat(i + 1) * w - w * 0.31)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.trailing, 10)
        }
        .frame(height: 130)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func pitchForWhite(_ i: Int) -> Int {
        (baseOctave + 1 + i / 7) * 12 + whiteSteps[i % 7]
    }

    private func keyShape(pitch: Int, black: Bool) -> some View {
        let on = pressed.contains(pitch)
        return RoundedRectangle(cornerRadius: 3)
            .fill(black ? (on ? Theme.red : Theme.ink) : (on ? Theme.red.opacity(0.35) : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed.contains(pitch) {
                            pressed.insert(pitch)
                            session.engine.liveNoteOn(pitch, velocity: 90)
                        }
                    }
                    .onEnded { _ in
                        pressed.remove(pitch)
                        session.engine.liveNoteOff(pitch)
                    }
            )
    }
}
