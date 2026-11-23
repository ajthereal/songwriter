import SwiftUI

struct EditorView: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        Group {
            if !session.editorOpen {
                HStack {
                    Text(session.selectedRegion == nil
                         ? "Editor \u{2014} tap a region to edit its notes or takes"
                         : "Editor")
                        .font(Theme.serifItalic(14)).foregroundColor(Theme.ink2)
                        .lineLimit(1)
                    Spacer()
                    IconButton(systemName: "chevron.up", label: "Open editor") { session.editorOpen = true }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Theme.panel)
                .contentShape(Rectangle())
                .onTapGesture { session.editorOpen = true }
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            } else {
                VStack(spacing: 0) {
                    if let sel = session.selectedRegion {
                        if sel.region.kind == .midi {
                            PianoRollView(session: session, trackID: sel.track.id, regionID: sel.region.id)
                        } else {
                            TakesView(session: session, trackID: sel.track.id, regionID: sel.region.id)
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(height: 236)
                .background(Theme.panel)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .onChange(of: session.selectedRegionID) { _, new in
            session.editorOpen = (new != nil)
        }
        .onAppear {
            if session.selectedRegionID == nil { session.editorOpen = false }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Editor").font(Theme.serifItalic(14)).foregroundColor(Theme.ink2)
                Spacer()
                IconButton(systemName: "chevron.down", label: "Collapse editor") { session.editorOpen = false }
            }
            .padding(.horizontal, 14)
            Spacer()
            Text("Tap a region to edit its notes or takes.")
                .font(Theme.serifItalic(17))
                .foregroundColor(Theme.ink2)
            if let t = session.selectedTrack, t.kind == .instrument {
                TextActionButton(title: "Add an empty region to \(t.name)", systemName: "plus") {
                    session.addEmptyRegion(trackID: t.id)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Piano roll

struct PianoRollView: View {
    @ObservedObject var session: ProjectSession
    var trackID: UUID
    var regionID: UUID
    @State var gridIndex = 1
    @State var selectedNote: UUID?
    @State var origin: Note?
    @State var velocityTarget: UUID?
    @State var request: ScrollRequest?
    @State var shownRegion: UUID?

    static let lowPitch = 24
    static let highPitch = 108
    static let rowHeight: CGFloat = 13
    static let keysWidth: CGFloat = 56
    static let rulerHeight: CGFloat = 20
    static let velocityHeight: CGFloat = 52
    static let grids: [(String, Double)] = [("1/4", 1.0), ("1/8", 0.5), ("1/16", 0.25), ("1/8T", 1.0 / 3.0)]

    var grid: Double { PianoRollView.grids[min(gridIndex, PianoRollView.grids.count - 1)].1 }
    var rowCount: Int { PianoRollView.highPitch - PianoRollView.lowPitch + 1 }

    var body: some View {
        if let region = session.song.region(trackID: trackID, regionID: regionID) {
            VStack(spacing: 0) {
                toolbar(region)
                roll(region)
            }
            .onAppear { scrollToNotes(region) }
            .onChange(of: regionID) { _, _ in
                selectedNote = nil
                if let r = session.song.region(trackID: trackID, regionID: regionID) { scrollToNotes(r) }
            }
        } else {
            Color.clear
        }
    }

    private func scrollToNotes(_ region: Region) {
        let pitches = region.notes.map { $0.pitch }.sorted()
        let center = pitches.isEmpty ? 64 : pitches[pitches.count / 2]
        let y = yFor(pitch: center) - 50
        request = ScrollRequest(token: (request?.token ?? 0) + 1, x: nil, y: max(0, y))
    }

    private func yFor(pitch: Int) -> CGFloat {
        CGFloat(PianoRollView.highPitch - pitch) * PianoRollView.rowHeight
    }

    // MARK: Toolbar

    private func toolbar(_ region: Region) -> some View {
        HStack(spacing: 10) {
            Text(region.name).font(Theme.serifMediumItalic(16)).foregroundColor(Theme.ink).lineLimit(1)
            Text("Piano roll").font(Theme.serifItalic(13)).foregroundColor(Theme.ink2)
            Spacer(minLength: 6)
            Picker("Grid", selection: $gridIndex) {
                ForEach(0..<PianoRollView.grids.count, id: \.self) { i in Text(PianoRollView.grids[i].0).tag(i) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            Menu {
                ForEach(0..<PianoRollView.grids.count, id: \.self) { i in
                    Button("Quantize to \(PianoRollView.grids[i].0)") { quantize(PianoRollView.grids[i].1) }
                }
            } label: {
                Text("Quantize").font(Theme.uiMedium(14)).foregroundColor(Theme.ink)
                    .padding(.horizontal, 10).frame(minHeight: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1.2))
                    .frame(minHeight: 44)
            }
            IconButton(systemName: "minus.magnifyingglass", label: "Zoom out") {
                session.rollPxPerBeat = max(24, session.rollPxPerBeat / 1.25)
            }
            IconButton(systemName: "plus.magnifyingglass", label: "Zoom in") {
                session.rollPxPerBeat = min(260, session.rollPxPerBeat * 1.25)
            }
            IconButton(systemName: "trash", label: "Delete note", enabled: selectedNote != nil) { deleteSelected() }
            IconButton(systemName: "chevron.down", label: "Collapse editor") { session.editorOpen = false }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    // MARK: Roll

    private func roll(_ region: Region) -> some View {
        let ppb = session.rollPxPerBeat
        let width = max(200, CGFloat(region.lengthBeats) * ppb + 40)
        let height = CGFloat(rowCount) * PianoRollView.rowHeight
        return Scroll2D(
            contentSize: CGSize(width: width, height: height),
            leftWidth: PianoRollView.keysWidth,
            topHeight: PianoRollView.rulerHeight,
            bottomHeight: PianoRollView.velocityHeight,
            request: request,
            content: { gridContent(region: region, ppb: ppb, width: width, height: height) },
            left: { keys(height: height) },
            top: { beatRuler(region: region, ppb: ppb, width: width) },
            corner: { Theme.panel },
            bottom: { velocityLane(region: region, ppb: ppb, width: width) }
        )
    }

    private func gridContent(region: Region, ppb: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RollGrid(region: region, ppb: ppb, grid: grid, beatsPerBar: session.song.beatsPerBar,
                     rowHeight: PianoRollView.rowHeight, lowPitch: PianoRollView.lowPitch, highPitch: PianoRollView.highPitch,
                     width: width)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        addNote(at: value.location, region: region, ppb: ppb)
                    }
                )
            ForEach(region.notes) { note in
                noteView(note: note, region: region, ppb: ppb)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func noteView(note: Note, region: Region, ppb: CGFloat) -> some View {
        let palette = Theme.palette(session.song.tracks.first(where: { $0.id == trackID })?.colorKey ?? .piano)
        let x = CGFloat(note.start) * ppb
        let y = yFor(pitch: note.pitch)
        let w = max(8, CGFloat(note.length) * ppb - 1)
        let selected = selectedNote == note.id
        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.caption.opacity(0.55 + 0.45 * Double(note.velocity) / 127.0))
            RoundedRectangle(cornerRadius: 3)
                .stroke(selected ? Theme.ink : palette.content, lineWidth: selected ? 2 : 1)
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: min(14, w))
                .contentShape(Rectangle())
                .gesture(resizeGesture(note: note, ppb: ppb))
        }
        .frame(width: w, height: PianoRollView.rowHeight - 1)
        .contentShape(Rectangle())
        .offset(x: x, y: y)
        .onTapGesture(count: 2) { deleteNote(note.id) }
        .onTapGesture {
            selectedNote = note.id
            session.engine.audition(trackID: trackID, pitches: [note.pitch], velocity: note.velocity, duration: 0.3)
        }
        .gesture(moveGesture(note: note, ppb: ppb))
    }

    // MARK: Gestures

    private func moveGesture(note: Note, ppb: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if origin == nil {
                    origin = note
                    selectedNote = note.id
                    session.beginGesture()
                }
                guard let o = origin else { return }
                let g = grid
                var start = ((o.start + Double(value.translation.width / ppb)) / g).rounded() * g
                start = max(0, start)
                let dp = Int((-value.translation.height / PianoRollView.rowHeight).rounded())
                let pitch = max(PianoRollView.lowPitch, min(PianoRollView.highPitch, o.pitch + dp))
                session.updateRegion(trackID: trackID, regionID: regionID, undo: false) { r in
                    if let i = r.notes.firstIndex(where: { $0.id == o.id }) {
                        r.notes[i].start = start
                        r.notes[i].pitch = pitch
                        if start + r.notes[i].length > r.lengthBeats { r.lengthBeats = ceil(start + r.notes[i].length) }
                    }
                }
            }
            .onEnded { _ in
                origin = nil
                session.endGesture()
            }
    }

    private func resizeGesture(note: Note, ppb: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if origin == nil {
                    origin = note
                    selectedNote = note.id
                    session.beginGesture()
                }
                guard let o = origin else { return }
                let g = grid
                let end = ((o.start + o.length + Double(value.translation.width / ppb)) / g).rounded() * g
                let length = max(g, end - o.start)
                session.updateRegion(trackID: trackID, regionID: regionID, undo: false) { r in
                    if let i = r.notes.firstIndex(where: { $0.id == o.id }) {
                        r.notes[i].length = length
                        if o.start + length > r.lengthBeats { r.lengthBeats = ceil(o.start + length) }
                    }
                }
            }
            .onEnded { _ in
                origin = nil
                session.endGesture()
            }
    }

    // MARK: Edits

    private func addNote(at location: CGPoint, region: Region, ppb: CGFloat) {
        let pitch = PianoRollView.highPitch - Int(floor(location.y / PianoRollView.rowHeight))
        guard pitch >= PianoRollView.lowPitch, pitch <= PianoRollView.highPitch else { return }
        let g = grid
        let start = max(0, (Double(location.x / ppb) / g).rounded(.down) * g)
        let note = Note(pitch: pitch, start: start, length: g, velocity: 90)
        session.updateRegion(trackID: trackID, regionID: regionID) { r in
            r.notes.append(note)
            if start + g > r.lengthBeats { r.lengthBeats = ceil(start + g) }
        }
        selectedNote = note.id
        session.engine.audition(trackID: trackID, pitches: [pitch], velocity: 90, duration: 0.3)
    }

    private func deleteNote(_ id: UUID) {
        session.updateRegion(trackID: trackID, regionID: regionID) { r in
            r.notes.removeAll { $0.id == id }
        }
        if selectedNote == id { selectedNote = nil }
    }

    private func deleteSelected() {
        if let id = selectedNote { deleteNote(id) }
    }

    private func quantize(_ g: Double) {
        session.updateRegion(trackID: trackID, regionID: regionID) { r in
            r.notes = Quantizer.quantize(r.notes, grid: g)
        }
    }

    // MARK: Keys, ruler, velocity

    private func keys(height: CGFloat) -> some View {
        RollKeys(rowHeight: PianoRollView.rowHeight, lowPitch: PianoRollView.lowPitch, highPitch: PianoRollView.highPitch)
            .frame(width: PianoRollView.keysWidth, height: height)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let pitch = PianoRollView.highPitch - Int(floor(value.location.y / PianoRollView.rowHeight))
                    if pitch >= PianoRollView.lowPitch && pitch <= PianoRollView.highPitch {
                        session.engine.audition(trackID: trackID, pitches: [pitch], velocity: 90, duration: 0.4)
                    }
                }
            )
    }

    private func beatRuler(region: Region, ppb: CGFloat, width: CGFloat) -> some View {
        let bpb = session.song.beatsPerBar
        let startBeat = region.startBeat
        return Canvas { ctx, size in
            let first = Int(floor(startBeat))
            let last = Int(ceil(startBeat + Double(size.width / ppb))) + 1
            for b in first...max(first, last) {
                let x = CGFloat(Double(b) - startBeat) * ppb
                if x < 0 { continue }
                let isBar = abs(Double(b) / bpb - (Double(b) / bpb).rounded()) < 1e-6
                var p = Path()
                p.move(to: CGPoint(x: x, y: isBar ? 2 : size.height - 6))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(Theme.line), lineWidth: 1)
                if isBar {
                    let bar = Int((Double(b) / bpb).rounded()) + 1
                    ctx.draw(Text("\(bar)").font(Theme.condensed(11)).foregroundColor(Theme.ink2), at: CGPoint(x: x + 3, y: 9), anchor: .leading)
                }
            }
        }
        .frame(width: width, height: PianoRollView.rulerHeight)
        .background(Theme.panel)
    }

    private func velocityLane(region: Region, ppb: CGFloat, width: CGFloat) -> some View {
        let h = PianoRollView.velocityHeight
        return ZStack(alignment: .topLeading) {
            Theme.panel
            Canvas { ctx, size in
                for n in region.notes {
                    let x = CGFloat(n.start) * ppb
                    let bh = CGFloat(n.velocity) / 127.0 * (size.height - 8)
                    let rect = CGRect(x: x, y: size.height - bh - 2, width: 5, height: bh)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(n.id == selectedNote ? Theme.red : Theme.ink2))
                }
                var top = Path()
                top.move(to: CGPoint(x: 0, y: 0.5))
                top.addLine(to: CGPoint(x: size.width, y: 0.5))
                ctx.stroke(top, with: .color(Theme.line), lineWidth: 1)
            }
            .frame(width: width, height: h)
        }
        .frame(width: width, height: h)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if velocityTarget == nil {
                        let x = Double(value.startLocation.x / ppb)
                        let nearest = region.notes.min { abs($0.start - x) < abs($1.start - x) }
                        if let n = nearest, abs(n.start - x) * Double(ppb) < 18 {
                            velocityTarget = n.id
                            selectedNote = n.id
                            session.beginGesture()
                        } else {
                            return
                        }
                    }
                    guard let id = velocityTarget else { return }
                    let v = Int(((1 - value.location.y / h) * 127).rounded())
                    let vel = max(1, min(127, v))
                    session.updateRegion(trackID: trackID, regionID: regionID, undo: false) { r in
                        if let i = r.notes.firstIndex(where: { $0.id == id }) { r.notes[i].velocity = vel }
                    }
                }
                .onEnded { _ in
                    velocityTarget = nil
                    session.endGesture()
                }
        )
    }
}

struct RollGrid: View {
    var region: Region
    var ppb: CGFloat
    var grid: Double
    var beatsPerBar: Double
    var rowHeight: CGFloat
    var lowPitch: Int
    var highPitch: Int
    var width: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let black: Set<Int> = [1, 3, 6, 8, 10]
            for p in lowPitch...highPitch {
                let y = CGFloat(highPitch - p) * rowHeight
                let isBlack = black.contains(p % 12)
                let rect = CGRect(x: 0, y: y, width: size.width, height: rowHeight)
                ctx.fill(Path(rect), with: .color(isBlack ? Theme.grid.opacity(0.9) : Theme.paper))
                if p % 12 == 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y + rowHeight))
                    line.addLine(to: CGPoint(x: size.width, y: y + rowHeight))
                    ctx.stroke(line, with: .color(Theme.line), lineWidth: 1)
                }
            }
            // Time lines follow the absolute beat grid.
            let startBeat = region.startBeat
            let total = Double(size.width / ppb)
            var b = (floor(startBeat / grid) * grid)
            while b - startBeat <= total + grid {
                let x = CGFloat(b - startBeat) * ppb
                if x >= 0 {
                    let onBeat = abs(b - b.rounded()) < 1e-6
                    let onBar = onBeat && abs(b / beatsPerBar - (b / beatsPerBar).rounded()) < 1e-6
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(line, with: .color(onBar ? Theme.ink2.opacity(0.5) : (onBeat ? Theme.line : Theme.grid)),
                               lineWidth: onBar ? 1.2 : 0.7)
                }
                b += grid
            }
            // End of region
            let endX = CGFloat(region.lengthBeats) * ppb
            var endLine = Path()
            endLine.move(to: CGPoint(x: endX, y: 0))
            endLine.addLine(to: CGPoint(x: endX, y: size.height))
            ctx.stroke(endLine, with: .color(Theme.red.opacity(0.6)), lineWidth: 1.5)
            ctx.fill(Path(CGRect(x: endX, y: 0, width: max(0, size.width - endX), height: size.height)), with: .color(Theme.panel.opacity(0.55)))
        }
    }
}

struct RollKeys: View {
    var rowHeight: CGFloat
    var lowPitch: Int
    var highPitch: Int

    var body: some View {
        Canvas { ctx, size in
            let black: Set<Int> = [1, 3, 6, 8, 10]
            for p in lowPitch...highPitch {
                let y = CGFloat(highPitch - p) * rowHeight
                let isBlack = black.contains(p % 12)
                let rect = CGRect(x: 0, y: y, width: isBlack ? size.width * 0.62 : size.width, height: rowHeight)
                ctx.fill(Path(rect), with: .color(isBlack ? Theme.ink : Color.white))
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y + rowHeight))
                line.addLine(to: CGPoint(x: size.width, y: y + rowHeight))
                ctx.stroke(line, with: .color(Theme.line), lineWidth: 0.6)
                if p % 12 == 0 {
                    let label = Text("C\(p / 12 - 1)").font(Theme.condensedBold(10)).foregroundColor(Color(red: 0.3, green: 0.34, blue: 0.4))
                    ctx.draw(label, at: CGPoint(x: size.width - 4, y: y + rowHeight / 2), anchor: .trailing)
                }
            }
        }
    }
}

// MARK: - Takes

struct TakesView: View {
    @ObservedObject var session: ProjectSession
    var trackID: UUID
    var regionID: UUID
    @ObservedObject var waves = WaveformStore.shared

    var body: some View {
        if let region = session.song.region(trackID: trackID, regionID: regionID) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(region.name).font(Theme.serifMediumItalic(16)).foregroundColor(Theme.ink).lineLimit(1)
                    Text("Takes").font(Theme.serifItalic(13)).foregroundColor(Theme.ink2)
                    Spacer()
                    Text("Tap a take to use it. Split the region to use different takes in different parts.")
                        .font(Theme.serifItalic(12))
                        .foregroundColor(Theme.ink2)
                        .lineLimit(1)
                    IconButton(systemName: "chevron.down", label: "Collapse editor") { session.editorOpen = false }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                if region.takes.isEmpty {
                    Spacer()
                    Text("This region has no takes.").font(Theme.serifItalic(16)).foregroundColor(Theme.ink2)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(region.takes.enumerated()), id: \.element.id) { index, take in
                                takeRow(region: region, index: index, take: take)
                                Rectangle().fill(Theme.line).frame(height: 1)
                            }
                        }
                    }
                }
            }
        } else {
            Color.clear
        }
    }

    private func takeRow(region: Region, index: Int, take: Take) -> some View {
        let active = region.activeTake == index
        let palette = Theme.palette(session.song.tracks.first(where: { $0.id == trackID })?.colorKey ?? .vocal)
        return HStack(spacing: 12) {
            Image(systemName: active ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 20))
                .foregroundColor(active ? Theme.red : Theme.ink2)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(take.name).font(Theme.uiSemibold(15)).foregroundColor(Theme.ink)
                Text(String(format: "%.1f s", take.duration)).font(Theme.serifItalic(12)).foregroundColor(Theme.ink2)
            }
            .frame(width: 90, alignment: .leading)
            TakeWave(peaks: peaks(take), offset: take.offset + region.audioOffset,
                     seconds: region.lengthBeats * session.song.secondsPerBeat, color: palette.content)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 4).fill(palette.body))
            if region.takes.count > 1 {
                IconButton(systemName: "trash", label: "Delete take") { deleteTake(index) }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(active ? Theme.armed : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            session.updateRegion(trackID: trackID, regionID: regionID) { $0.activeTake = index }
        }
    }

    private func peaks(_ take: Take) -> [Float]? {
        _ = waves.version
        return waves.peaks(dir: session.audioDir, fileName: take.fileName)
    }

    private func deleteTake(_ index: Int) {
        session.updateRegion(trackID: trackID, regionID: regionID) { r in
            guard r.takes.indices.contains(index), r.takes.count > 1 else { return }
            r.takes.remove(at: index)
            if r.activeTake >= r.takes.count { r.activeTake = r.takes.count - 1 }
            else if r.activeTake > index { r.activeTake -= 1 }
        }
    }
}

struct TakeWave: View {
    var peaks: [Float]?
    var offset: Double
    var seconds: Double
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            guard let peaks = peaks, !peaks.isEmpty, seconds > 0 else { return }
            let bucket = WaveformStore.bucketSeconds
            let midY = size.height / 2
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                let t0 = offset + Double(x / size.width) * seconds
                let t1 = offset + Double((x + 2) / size.width) * seconds
                let i0 = max(0, Int(t0 / bucket))
                let i1 = min(peaks.count - 1, max(i0, Int(t1 / bucket)))
                if i0 < peaks.count {
                    var m: Float = 0
                    var i = i0
                    while i <= i1 {
                        m = max(m, peaks[i])
                        i += 1
                    }
                    let amp = CGFloat(min(1, m)) * (size.height / 2 - 2)
                    path.move(to: CGPoint(x: x, y: midY - max(0.5, amp)))
                    path.addLine(to: CGPoint(x: x, y: midY + max(0.5, amp)))
                }
                x += 2
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.2)
        }
    }
}
