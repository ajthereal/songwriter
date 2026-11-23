import SwiftUI

struct HeaderView: View {
    @ObservedObject var session: ProjectSession
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings
    @State var renaming = false
    @State var titleText = ""

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(subtitle: true, compactSwitch: false)
            row(subtitle: false, compactSwitch: false)
            row(subtitle: false, compactSwitch: true)
            ScrollView(.horizontal, showsIndicators: false) {
                row(subtitle: false, compactSwitch: true)
            }
        }
        .frame(height: 76)
        .background(Theme.paper)
        .alert("Rename song", isPresented: $renaming) {
            TextField("Song name", text: $titleText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let t = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty {
                    ErrorCenter.post("A song needs a name.", warning: true)
                } else {
                    session.edit { $0.title = t }
                }
            }
        }
    }

    private func row(subtitle: Bool, compactSwitch: Bool) -> some View {
        HStack(spacing: 12) {
            IconButton(systemName: "chevron.left", label: "Back to songs") {
                app.closeProject()
            }
            titleBlock(subtitle: subtitle)
            Spacer(minLength: 6)
            transport
            PositionCounter(session: session)
            Spacer(minLength: 6)
            viewSwitch(compact: compactSwitch)
            Spacer(minLength: 6)
            rightButtons
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 76)
    }

    private func titleBlock(subtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: {
                titleText = session.song.title
                renaming = true
            }) {
                Text(session.song.title)
                    .font(Theme.serifMediumItalic(25))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            if subtitle {
                Button(action: { session.sheet = .tempo }) {
                    Text("Tempo \u{2669} = \(Int(session.song.tempo.rounded()))  \u{2022}  \(session.song.key.displayName)  \u{2022}  \(session.song.timeSignature.label)")
                        .font(Theme.serifItalic(14))
                        .foregroundColor(Theme.ink2)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 120, maxWidth: 260, alignment: .leading)
    }

    private var transport: some View {
        HStack(spacing: 2) {
            IconButton(systemName: "backward.end.fill", label: "Back to start") { session.rewind() }
            IconButton(systemName: session.isPlaying && !session.isRecording ? "stop.fill" : "play.fill",
                       label: session.isPlaying ? "Stop" : "Play") {
                if session.isRecording { session.stop() } else { session.togglePlay() }
            }
            Button(action: { session.toggleRecord() }) {
                ZStack {
                    Circle().stroke(Theme.red, lineWidth: 2).frame(width: 28, height: 28)
                    Circle().fill(Theme.red).frame(width: session.isRecording ? 16 : 10, height: session.isRecording ? 16 : 10)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record")
            PillButton(title: "Cycle", isOn: session.cycleOn) { session.cycleOn.toggle() }
            PillButton(title: "Click", isOn: settings.clickOn) { settings.clickOn.toggle() }
        }
    }

    private func viewSwitch(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 16) {
            ForEach(ViewMode.allCases) { mode in
                Button(action: { session.viewMode = mode }) {
                    VStack(spacing: 3) {
                        Text(mode.rawValue)
                            .font(Theme.serifItalic(compact ? 16 : 18))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundColor(session.viewMode == mode ? Theme.ink : Theme.ink2)
                        Rectangle()
                            .fill(session.viewMode == mode ? Theme.red : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.horizontal, compact ? 4 : 8)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rightButtons: some View {
        HStack(spacing: 2) {
            IconButton(systemName: "arrow.uturn.backward", label: "Undo", enabled: session.canUndo) { session.undo() }
            IconButton(systemName: "arrow.uturn.forward", label: "Redo", enabled: session.canRedo) { session.redo() }
            IconButton(systemName: "gearshape", label: "Settings") { session.sheet = .settings }
            Button(action: { session.sheet = .bounce }) {
                Text("Bounce")
                    .font(Theme.uiMedium(15))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Color.clear))
                    .overlay(Capsule().stroke(Theme.ink, lineWidth: 1.5))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Bar.beat counter in Barlow Condensed.
struct PositionCounter: View {
    @ObservedObject var session: ProjectSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !session.isPlaying)) { _ in
            let beat = session.displayBeat()
            let text = label(beat)
            VStack(alignment: .center, spacing: 0) {
                Text(text)
                    .font(Theme.condensedBold(32))
                    .foregroundColor(Theme.ink)
                    .monospacedDigit()
                Text("BAR  BEAT")
                    .font(Theme.condensed(10))
                    .foregroundColor(Theme.ink2)
            }
            .frame(minWidth: 96)
        }
    }

    private func label(_ beat: Double) -> String {
        let song = session.song
        if session.isPlaying && beat < session.recordStartBeat - 1e-6 {
            let interval = song.timeSignature.clickInterval
            let remaining = Int(ceil((session.recordStartBeat - beat) / interval - 1e-6))
            return "Count \(max(1, remaining))"
        }
        let p = song.formattedPosition(beat: max(0, beat))
        return "\(p.bar).\(p.beat)"
    }
}
