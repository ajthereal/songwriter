import SwiftUI

@main
struct SongwriterApp: App {
    @StateObject private var app = AppState()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var errors = ErrorCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(settings)
                .environmentObject(errors)
                .preferredColorScheme(settings.theme.colorScheme)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { app.session?.saveNow(synchronous: true) }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var errors: ErrorCenter

    var body: some View {
        ZStack(alignment: .top) {
            Theme.paper.ignoresSafeArea()
            if let session = app.session {
                MainView(session: session)
            } else {
                SongsView()
            }
            if let banner = errors.banner {
                BannerView(banner: banner)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: errors.banner)
    }
}

struct BannerView: View {
    var banner: ErrorCenter.Banner
    @EnvironmentObject var errors: ErrorCenter

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.isWarning ? "exclamationmark.circle" : "xmark.octagon")
                .font(.system(size: 16, weight: .semibold))
            Text(banner.message)
                .font(Theme.ui(15))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: { errors.dismiss() }) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
            }
            .frame(width: 44, height: 28)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(banner.isWarning ? Color(red: 0.55, green: 0.38, blue: 0.08) : Color(red: 0.70, green: 0.17, blue: 0.14)))
        .padding(.horizontal, 16)
        .frame(maxWidth: 720)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .onTapGesture { errors.dismiss() }
    }
}
