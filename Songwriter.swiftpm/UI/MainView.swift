import SwiftUI

struct MainView: View {
    @ObservedObject var session: ProjectSession
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(session: session)
            Rectangle().fill(Theme.line).frame(height: 1)
            content
        }
        .sheet(item: $session.sheet) { sheet in
            sheetView(sheet)
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
        .overlay {
            if session.showMicDenied {
                MicDeniedView(onClose: { session.showMicDenied = false })
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.viewMode {
        case .tracks:
            TracksScreen(session: session)
        case .chart:
            ChartScreen(session: session)
        case .lyrics:
            LyricsScreen(session: session)
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .tempo:
            TempoSheet(session: session)
        case .sections:
            SectionsSheet(session: session)
        case .bounce:
            BounceSheet(session: session)
        case .settings:
            SettingsSheet(session: session)
        case .track(let id):
            TrackSheet(session: session, trackID: id)
        case .chord(let beat):
            ChordPickerSheet(session: session, beat: beat)
        case .addTrack:
            AddTrackSheet(session: session)
        }
    }
}

struct MicDeniedView: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("Microphone access is off")
                    .font(Theme.serifMediumItalic(26))
                    .foregroundColor(Theme.ink)
                Text("Songwriter needs the microphone to record vocals and instruments. To turn it on, open Settings, then Privacy & Security, then Microphone, and switch on Songwriter. You can still play and record MIDI without it.")
                    .font(Theme.ui(16))
                    .foregroundColor(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextActionButton(title: "Not now", action: onClose)
                    Spacer()
                    TextActionButton(title: "Open Settings", systemName: "gearshape", prominent: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        onClose()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
            .padding(24)
        }
    }
}
