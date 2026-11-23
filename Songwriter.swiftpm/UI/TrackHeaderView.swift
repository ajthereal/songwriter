import SwiftUI

struct TrackHeaderView: View {
    @ObservedObject var session: ProjectSession
    var track: Track

    var body: some View {
        let palette = Theme.palette(track.colorKey)
        let armed = session.armedTrackID == track.id
        let selected = session.selectedTrackID == track.id
        HStack(spacing: 0) {
            Rectangle().fill(palette.caption).frame(width: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(Theme.uiSemibold(16))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.serifItalic(13))
                    .foregroundColor(Theme.ink2)
                    .lineLimit(1)
                HStack(spacing: -6) {
                    CircleToggle(label: "M", isOn: track.muted, onColor: Color(red: 0.78, green: 0.55, blue: 0.1)) {
                        session.toggleMute(track.id)
                    }
                    CircleToggle(label: "S", isOn: track.solo, onColor: Color(red: 0.2, green: 0.5, blue: 0.75)) {
                        session.toggleSolo(track.id)
                    }
                    ArmButton(isOn: armed) { session.toggleArm(track.id) }
                    if armed && track.kind == .audio {
                        LevelMeter(meter: session.meter).frame(width: 40).padding(.leading, 8)
                    }
                }
                .frame(height: 32)
            }
            .padding(.leading, 10)
            Spacer(minLength: 0)
        }
        .frame(height: TimelineMetrics.trackHeight)
        .background(armed || selected ? Theme.armed : Theme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { session.selectedTrackID = track.id }
        .onLongPressGesture { session.sheet = .track(track.id) }
        .contextMenu {
            Button("Track settings") { session.sheet = .track(track.id) }
            Button("Delete track", role: .destructive) { session.sheet = .track(track.id) }
        }
    }

    private var subtitle: String {
        if track.kind == .instrument && track.follow {
            return "\(track.instrument.displayName) \u{2022} follows chords"
        }
        return track.instrumentLabel
    }
}
