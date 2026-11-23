import SwiftUI

struct RegionView: View {
    @ObservedObject var session: ProjectSession
    var track: Track
    var region: Region
    var palette: TrackPalette
    @ObservedObject var waves = WaveformStore.shared
    @State var original: Region?

    var selected: Bool { session.selectedRegionID == region.id }

    var body: some View {
        let ppb = session.pxPerBeat
        let w = max(8, CGFloat(region.lengthBeats) * ppb)
        let h = TimelineMetrics.trackHeight - 8
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(palette.body)
            regionContent(width: w, height: h)
            caption
            RoundedRectangle(cornerRadius: 5)
                .stroke(selected ? Theme.ink : palette.caption.opacity(0.55), lineWidth: selected ? 2 : 1)
            if selected {
                handles(width: w)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .offset(x: CGFloat(region.startBeat) * ppb, y: 4)
        .onTapGesture {
            session.selectedTrackID = track.id
            session.selectedRegionID = region.id
            session.editorOpen = true
        }
        .gesture(moveGesture)
    }

    private var caption: some View {
        HStack {
            Text(captionText)
                .font(Theme.uiSemibold(11))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .background(palette.caption)
    }

    private var captionText: String {
        if region.kind == .audio, region.takes.count > 1, region.takes.indices.contains(region.activeTake) {
            return "\(region.name) \u{2022} \(region.takes[region.activeTake].name)"
        }
        return region.name
    }

    @ViewBuilder
    private func regionContent(width: CGFloat, height: CGFloat) -> some View {
        if region.kind == .midi {
            MiniNotes(notes: region.notes.map { MiniNote(start: $0.start, length: $0.length, pitch: $0.pitch) },
                      ppb: session.pxPerBeat, color: palette.content, isDrums: track.instrument.isDrums)
                .padding(.top, 16)
        } else {
            WaveformShape(region: region, ppb: session.pxPerBeat, spb: session.song.secondsPerBeat,
                          peaks: peaksForRegion, color: palette.content)
                .padding(.top, 16)
        }
    }

    private var peaksForRegion: [Float]? {
        guard let take = region.activeTakeValue else { return nil }
        _ = waves.version
        return waves.peaks(dir: session.audioDir, fileName: take.fileName)
    }

    // MARK: Gestures

    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    if original == nil {
                        original = region
                        session.beginGesture()
                        session.selectedTrackID = track.id
                        session.selectedRegionID = region.id
                    }
                    guard let o = original else { return }
                    let delta = Double(drag.translation.width / session.pxPerBeat)
                    var start = session.snap.snap(o.startBeat + delta, beatsPerBar: session.song.beatsPerBar)
                    start = max(0, start)
                    session.updateRegion(trackID: track.id, regionID: region.id, undo: false) { $0.startBeat = start }
                }
            }
            .onEnded { _ in
                original = nil
                session.endGesture()
            }
    }

    private func handles(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            handle(isLeft: true)
            Spacer(minLength: 0)
            handle(isLeft: false)
        }
    }

    private func handle(isLeft: Bool) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.ink.opacity(0.65))
                    .frame(width: 4, height: 22)
                    .padding(isLeft ? .leading : .trailing, 3),
                alignment: isLeft ? .leading : .trailing
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if original == nil {
                            original = region
                            session.beginGesture()
                        }
                        guard let o = original else { return }
                        let ppb = session.pxPerBeat
                        let bpb = session.song.beatsPerBar
                        let spb = session.song.secondsPerBeat
                        let delta = Double(value.translation.width / ppb)
                        if isLeft {
                            let target = max(0, session.snap.snap(o.startBeat + delta, beatsPerBar: bpb))
                            session.updateRegion(trackID: track.id, regionID: region.id, undo: false) { r in
                                r = o
                                r.trimStart(by: target - o.startBeat, secondsPerBeat: spb)
                            }
                        } else {
                            var end = session.snap.snap(o.endBeat + delta, beatsPerBar: bpb)
                            if o.kind == .audio, let take = o.activeTakeValue {
                                let available = (take.offset + take.duration - take.offset - o.audioOffset) / spb
                                end = min(end, o.startBeat + max(0.25, available))
                            }
                            session.updateRegion(trackID: track.id, regionID: region.id, undo: false) { r in
                                r = o
                                r.trimEnd(toLength: end - o.startBeat)
                            }
                        }
                    }
                    .onEnded { _ in
                        original = nil
                        session.endGesture()
                    }
            )
    }
}

/// Waveform drawn from cached peaks.
struct WaveformShape: View {
    var region: Region
    var ppb: CGFloat
    var spb: Double
    var peaks: [Float]?
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            guard let peaks = peaks, !peaks.isEmpty, let take = region.activeTakeValue else {
                var mid = Path()
                mid.move(to: CGPoint(x: 0, y: size.height / 2))
                mid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(mid, with: .color(color.opacity(0.4)), lineWidth: 1)
                return
            }
            let base = take.offset + region.audioOffset
            let bucket = WaveformStore.bucketSeconds
            let midY = size.height / 2
            let step: CGFloat = 2
            var x: CGFloat = 0
            var path = Path()
            while x < size.width {
                let t0 = base + Double(x / ppb) * spb
                let t1 = base + Double((x + step) / ppb) * spb
                let i0 = max(0, Int(t0 / bucket))
                let i1 = min(peaks.count - 1, max(i0, Int(t1 / bucket)))
                if i0 < peaks.count && t0 >= 0 {
                    var m: Float = 0
                    var i = i0
                    while i <= i1 {
                        m = max(m, peaks[i])
                        i += 1
                    }
                    let amp = CGFloat(min(1, m)) * (size.height / 2 - 2)
                    path.move(to: CGPoint(x: x + 0.5, y: midY - max(0.5, amp)))
                    path.addLine(to: CGPoint(x: x + 0.5, y: midY + max(0.5, amp)))
                }
                x += step
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.2)
        }
        .allowsHitTesting(false)
    }
}
