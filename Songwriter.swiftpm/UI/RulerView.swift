import SwiftUI

/// Sections, chord track, bar numbers and the cycle bar.
struct RulerView: View {
    @ObservedObject var session: ProjectSession
    var width: CGFloat
    @State var cycleDragStart: Int?

    var body: some View {
        let song = session.song
        let ppb = session.pxPerBeat
        let bpb = CGFloat(song.beatsPerBar)
        ZStack(alignment: .topLeading) {
            Theme.paper
            barNumbers(song: song, ppb: ppb, bpb: bpb)
            sectionRow(song: song, ppb: ppb, bpb: bpb)
            chordRow(song: song, ppb: ppb, bpb: bpb)
            cycleRow(song: song, ppb: ppb, bpb: bpb)
            PlayheadTip(session: session)
        }
        .frame(width: width, height: TimelineMetrics.rulerHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    // MARK: Bar numbers (tap to move the playhead)

    private func barNumbers(song: Song, ppb: CGFloat, bpb: CGFloat) -> some View {
        let y = TimelineMetrics.sectionRow + TimelineMetrics.chordRow
        let barPx = ppb * bpb
        let labelEvery = barPx < 28 ? 4 : (barPx < 56 ? 2 : 1)
        return Canvas { ctx, size in
            let bars = Int(size.width / max(barPx, 1)) + 1
            for b in 0...bars {
                let x = CGFloat(b) * barPx
                var line = Path()
                line.move(to: CGPoint(x: x, y: y + 4))
                line.addLine(to: CGPoint(x: x, y: y + TimelineMetrics.numberRow))
                ctx.stroke(line, with: .color(Theme.line), lineWidth: 1)
                if b % labelEvery == 0 {
                    let text = Text("\(b + 1)").font(Theme.condensed(12)).foregroundColor(Theme.ink2)
                    ctx.draw(text, at: CGPoint(x: x + 4, y: y + 12), anchor: .leading)
                }
            }
        }
        .frame(width: width, height: TimelineMetrics.numberRow + TimelineMetrics.chordRow + TimelineMetrics.sectionRow, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                if value.location.y >= y {
                    let beat = Double(value.location.x / ppb)
                    session.setPlayhead(session.snap.snap(beat, beatsPerBar: song.beatsPerBar))
                }
            }
        )
    }

    // MARK: Sections

    private func sectionRow(song: Song, ppb: CGFloat, bpb: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(song.sections) { s in
                let x = CGFloat(s.startBar) * bpb * ppb
                let w = CGFloat(s.lengthBars) * bpb * ppb
                HStack(spacing: 6) {
                    SectionBadge(letter: s.letter, size: 20)
                    Text(s.name)
                        .font(Theme.serifItalic(15))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                }
                .padding(.leading, 5)
                .frame(width: w, height: TimelineMetrics.sectionRow, alignment: .leading)
                .background(Theme.red.opacity(0.06))
                .overlay(alignment: .leading) { Rectangle().fill(Theme.red.opacity(0.5)).frame(width: 1.5) }
                .contentShape(Rectangle())
                .offset(x: x)
                .onTapGesture {
                    session.setCycle(startBar: s.startBar, endBar: s.endBar)
                    session.cycleOn = true
                }
                .onLongPressGesture { session.sheet = .sections }
            }
        }
        .frame(width: width, height: TimelineMetrics.sectionRow, alignment: .topLeading)
    }

    // MARK: Chords

    private func chordRow(song: Song, ppb: CGFloat, bpb: CGFloat) -> some View {
        let half = song.beatsPerBar / 2
        let slotCount = song.totalBars * 2 + 4
        let slotWidth = CGFloat(half) * ppb
        let y = TimelineMetrics.sectionRow
        return ZStack(alignment: .topLeading) {
            ForEach(0..<slotCount, id: \.self) { i in
                let beat = Double(i) * half
                Color.clear
                    .frame(width: slotWidth, height: TimelineMetrics.chordRow)
                    .contentShape(Rectangle())
                    .offset(x: CGFloat(i) * slotWidth)
                    .onTapGesture { session.sheet = .chord(beat) }
            }
            ForEach(song.chords) { e in
                ChordText(chord: e.chord, size: 20, color: Theme.ink)
                    .padding(.leading, 4)
                    .frame(height: TimelineMetrics.chordRow, alignment: .center)
                    .offset(x: CGFloat(e.startBeat) * ppb)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: TimelineMetrics.chordRow, alignment: .topLeading)
        .offset(y: y)
    }

    // MARK: Cycle bar

    private func cycleRow(song: Song, ppb: CGFloat, bpb: CGFloat) -> some View {
        let range = song.cycleBeatRange
        let x = CGFloat(range.lowerBound) * ppb
        let w = CGFloat(range.upperBound - range.lowerBound) * ppb
        let y = TimelineMetrics.sectionRow + TimelineMetrics.chordRow + TimelineMetrics.numberRow
        let barPx = ppb * bpb
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: width, height: TimelineMetrics.cycleRow)
                .contentShape(Rectangle())
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.red.opacity(session.cycleOn ? 0.85 : 0.28))
                .frame(width: max(6, w), height: 10)
                .offset(x: x, y: 5)
        }
        .frame(width: width, height: TimelineMetrics.cycleRow, alignment: .topLeading)
        .offset(y: y)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard barPx > 1 else { return }
                    if cycleDragStart == nil { cycleDragStart = Int(floor(value.startLocation.x / barPx)) }
                    let startBar = cycleDragStart ?? 0
                    let currentBar = Int(floor(value.location.x / barPx))
                    let a = max(0, min(startBar, currentBar))
                    let b = max(startBar, currentBar) + 1
                    session.setCycle(startBar: a, endBar: b)
                    session.cycleOn = true
                }
                .onEnded { _ in cycleDragStart = nil }
        )
    }
}
