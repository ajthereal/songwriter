import SwiftUI

enum TimelineMetrics {
    static let rulerHeight: CGFloat = 104
    static let trackHeight: CGFloat = 62
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
    private let followTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

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
            onPinch: { scale, ended in
                if ended { pinchBase = nil; return }
                if pinchBase == nil { pinchBase = session.pxPerBar }
                session.setZoom(pxPerBar: (pinchBase ?? session.pxPerBar) * scale)
            },
            content: { lanes },
            left: { headers },
            top: { RulerView(session: session, width: contentWidth) },
            corner: { RulerCorner(session: session) }
        )
        .onAppear {
            let s = session
            tracker.onUserScroll = {
                guard s.isPlaying, s.followOn, !s.followPaused else { return }
                DispatchQueue.main.async { s.followPaused = true }
            }
        }
        .onReceive(followTimer) { _ in followTick() }
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

    /// Logic-style catch: while playing, keep the playhead inside the visible lanes by scrolling
    /// so it sits about 15% from the left whenever it passes 85% of the width or leaves on the left.
    private func followTick() {
        guard session.isPlaying, session.followOn, !session.followPaused else { return }
        let visible = tracker.size.width - leftWidth
        guard visible > 40 else { return }
        let x = CGFloat(max(0, session.displayBeat())) * session.pxPerBeat
        let scrollX = max(0, -tracker.offset.x)
        let rel = x - scrollX
        let maxScroll = max(0, contentWidth + leftWidth - tracker.size.width)
        if rel < 0 || (rel > visible * 0.85 && scrollX < maxScroll - 1) {
            scroll(toPlayheadX: x, visible: visible)
        }
    }

    private func scroll(toPlayheadX x: CGFloat, visible: CGFloat) {
        let target = max(0, x - visible * 0.15)
        request = ScrollRequest(token: (request?.token ?? 0) + 1, x: target, y: nil)
    }

    private func revealIfNeeded(beat: Double) {
        let visible = tracker.size.width - leftWidth
        if visible <= 0 { return }
        let x = CGFloat(max(0, beat)) * session.pxPerBeat
        let scrollX = max(0, -tracker.offset.x)
        if x < scrollX || x > scrollX + visible {
            scroll(toPlayheadX: x, visible: visible)
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
        .contentShape(Rectangle())
        .onTapGesture { session.sheet = .tempo }
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
