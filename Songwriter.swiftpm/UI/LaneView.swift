import SwiftUI

struct LaneView: View {
    @ObservedObject var session: ProjectSession
    var track: Track
    var width: CGFloat

    var body: some View {
        let palette = Theme.palette(track.colorKey)
        let selected = session.selectedTrackID == track.id
        ZStack(alignment: .topLeading) {
            LaneGrid(beatsPerBar: session.song.beatsPerBar, ppb: session.pxPerBeat, highlighted: selected)
            if track.kind == .instrument && track.follow {
                FollowRegionView(session: session, track: track, palette: palette)
            }
            ForEach(track.regions) { region in
                RegionView(session: session, track: track, region: region, palette: palette)
            }
        }
        .frame(width: width, height: TimelineMetrics.trackHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            session.selectedTrackID = track.id
            session.selectedRegionID = nil
        }
    }
}

struct LaneGrid: View {
    var beatsPerBar: Double
    var ppb: CGFloat
    var highlighted: Bool

    var body: some View {
        Canvas { ctx, size in
            if highlighted {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.armed.opacity(0.6)))
            }
            let beatPx = ppb
            let count = Int(size.width / max(beatPx, 1)) + 1
            let showBeats = beatPx >= 22
            for i in 0...count {
                let x = CGFloat(i) * beatPx
                let isBar = abs(Double(i) / beatsPerBar - (Double(i) / beatsPerBar).rounded()) < 1e-6
                if !isBar && !showBeats { continue }
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(isBar ? Theme.line : Theme.grid), lineWidth: isBar ? 1 : 0.7)
            }
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 0.5))
            base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(base, with: .color(Theme.line), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// A read-only region showing the part generated from the chord track.
struct FollowRegionView: View {
    @ObservedObject var session: ProjectSession
    var track: Track
    var palette: TrackPalette

    var body: some View {
        let song = session.song
        let ppb = session.pxPerBeat
        let notes = BandGenerator.generate(song: song, instrument: track.instrument, style: track.style)
        let w = max(6, CGFloat(song.lengthBeats) * ppb)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(palette.body.opacity(0.75))
            MiniNotes(notes: notes.map { MiniNote(start: $0.start, length: $0.length, pitch: $0.pitch) },
                      ppb: ppb, color: palette.content, isDrums: track.instrument.isDrums)
                .padding(.top, 16)
            HStack {
                Text("Follows chords \u{2022} \(track.style.displayName)")
                    .font(Theme.uiSemibold(11))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                Spacer()
            }
            .frame(height: 16)
            .background(palette.caption.opacity(0.85))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 5))
        }
        .frame(width: w, height: TimelineMetrics.trackHeight - 8)
        .offset(x: 0, y: 4)
        .allowsHitTesting(false)
    }
}

struct MiniNote {
    var start: Double
    var length: Double
    var pitch: Int
}

/// Tiny note bars inside a region (not notation).
struct MiniNotes: View {
    var notes: [MiniNote]
    var ppb: CGFloat
    var color: Color
    var isDrums: Bool = false

    var body: some View {
        Canvas { ctx, size in
            guard !notes.isEmpty else { return }
            var lo = 127
            var hi = 0
            for n in notes {
                lo = min(lo, n.pitch)
                hi = max(hi, n.pitch)
            }
            let span = max(12, hi - lo + 1)
            let rowH = max(1.5, min(4, (size.height - 4) / CGFloat(span)))
            for n in notes {
                let x = CGFloat(n.start) * ppb
                if x > size.width { continue }
                let w = max(1.5, CGFloat(n.length) * ppb - 0.5)
                let y = size.height - 2 - CGFloat(n.pitch - lo + 1) * ((size.height - 4) / CGFloat(span))
                let h = isDrums ? 2.0 : rowH
                ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: isDrums ? 2 : w, height: h), cornerRadius: 0.8), with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}
