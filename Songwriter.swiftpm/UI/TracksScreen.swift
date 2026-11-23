import SwiftUI

enum TimelineMetrics {
    static let rulerHeight: CGFloat = 104
    static let trackHeight: CGFloat = 76
    static let sectionRow: CGFloat = 28
    static let chordRow: CGFloat = 34
    static let numberRow: CGFloat = 22
    static let cycleRow: CGFloat = 20
}

struct TracksScreen: View {
    @ObservedObject var session: ProjectSession
    @Environment(\.horizontalSizeClass) var hSize
    @State var request: ScrollRequest?
    @State var pinchBase: CGFloat?
    @State var tracker = ScrollTracker()

    var leftWidth: CGFloat { hSize == .compact ? 128 : 230 }

    var body: some View {
        VStack(spacing: 0) {
            timeline
            ToolsBar(session: session)
            if session.showChordPad {
                ChordPadView(session: session)
            }
            if session.showKeyboard {
                KeyboardView(session: session)
            }
            EditorView(session: session)
        }
    }

    private var contentWidth: CGFloat {
        CGFloat(session.song.totalBars + 2) * CGFloat(session.song.beatsPerBar) * session.pxPerBeat
    }

    private var contentHeight: CGFloat {
        CGFloat(session.song.tracks.count) * TimelineMetrics.trackHeight + 72
    }

    private var timeline: some View {
        Scroll2D(
            contentSize: CGSize(width: contentWidth, height: contentHeight),
            leftWidth: leftWidth,
            topHeight: TimelineMetrics.rulerHeight,
            request: request,
            tracker: tracker,
            content: { lanes },
            left: { headers },
            top: { RulerView(session: session, width: contentWidth) },
            corner: { RulerCorner(session: session) }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if pinchBase == nil { pinchBase = session.pxPerBeat }
                    let base = pinchBase ?? session.pxPerBeat
                    session.pxPerBeat = min(160, max(12, base * value))
                }
                .onEnded { _ in pinchBase = nil }
        )
        .onChange(of: session.playingBar) { _, bar in followPlayhead(bar: bar) }
        .onChange(of: session.stoppedBeat) { _, beat in
            if !session.isPlaying { revealIfNeeded(beat: beat) }
        }
    }

    private var lanes: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(session.song.tracks) { track in
                    LaneView(session: session, track: track, width: contentWidth)
                }
                Color.clear.frame(height: 72)
            }
            PlayheadLine(session: session, height: contentHeight)
        }
        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
    }

    private var headers: some View {
        VStack(spacing: 0) {
            ForEach(session.song.tracks) { track in
                TrackHeaderView(session: session, track: track)
            }
            Button(action: { session.sheet = .addTrack }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New track").font(Theme.uiMedium(15))
                }
                .foregroundColor(Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.leading, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 72, alignment: .top)
        }
    }

    private func followPlayhead(bar: Int) {
        guard session.isPlaying, bar >= 0 else { return }
        let x = CGFloat(session.song.barStartBeat(bar)) * session.pxPerBeat
        let scrollX = -tracker.offset.x
        let visible = tracker.size.width - leftWidth
        if visible <= 0 { return }
        if x < scrollX || x > scrollX + visible - session.pxPerBeat * CGFloat(session.song.beatsPerBar) {
            request = ScrollRequest(token: (request?.token ?? 0) + 1, x: max(0, x - 24), y: nil)
        }
    }

    private func revealIfNeeded(beat: Double) {
        let x = CGFloat(beat) * session.pxPerBeat
        let scrollX = -tracker.offset.x
        let visible = tracker.size.width - leftWidth
        if visible <= 0 { return }
        if x < scrollX || x > scrollX + visible {
            request = ScrollRequest(token: (request?.token ?? 0) + 1, x: max(0, x - 40), y: nil)
        }
    }
}

struct RulerCorner: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.panel
            VStack(alignment: .leading, spacing: 2) {
                Text(session.song.timeSignature.label)
                    .font(Theme.condensedBold(30))
                    .foregroundColor(Theme.ink)
                Text(session.song.key.displayName)
                    .font(Theme.serifItalic(16))
                    .foregroundColor(Theme.ink2)
            }
            .padding(.leading, 16)
            .padding(.top, 14)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}

/// The red pencil line that follows playback.
struct PlayheadLine: View {
    @ObservedObject var session: ProjectSession
    var height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !session.isPlaying)) { _ in
            let beat = max(0, session.displayBeat())
            Rectangle()
                .fill(Theme.red)
                .frame(width: 1.5, height: height)
                .offset(x: CGFloat(beat) * session.pxPerBeat - 0.75)
        }
        .allowsHitTesting(false)
    }
}

/// Playhead marker in the ruler: a pencil tip pointing down.
struct PlayheadTip: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !session.isPlaying)) { _ in
            let beat = max(0, session.displayBeat())
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.red).frame(width: 1.5, height: TimelineMetrics.rulerHeight)
                    .offset(x: CGFloat(beat) * session.pxPerBeat - 0.75)
                PencilTip()
                    .fill(Theme.red)
                    .frame(width: 14, height: 14)
                    .offset(x: CGFloat(beat) * session.pxPerBeat - 7,
                            y: TimelineMetrics.sectionRow + TimelineMetrics.chordRow + TimelineMetrics.numberRow - 12)
            }
        }
        .allowsHitTesting(false)
    }
}

struct PencilTip: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
