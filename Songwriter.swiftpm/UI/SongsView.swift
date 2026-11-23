import SwiftUI
import UniformTypeIdentifiers

struct SongsView: View {
    @EnvironmentObject var app: AppState
    @State private var renameTarget: ProjectInfo?
    @State private var renameText = ""
    @State private var deleteTarget: ProjectInfo?
    @State private var importing = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Songs").font(Theme.serifMediumItalic(34)).foregroundColor(Theme.ink)
                Spacer()
                TextActionButton(title: "Import", systemName: "square.and.arrow.down") { importing = true }
                TextActionButton(title: "New song", systemName: "plus", prominent: true) { app.create() }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 14)

            Rectangle().fill(Theme.line).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(app.projects) { p in
                        row(p)
                        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 28)
                    }
                    if app.projects.isEmpty {
                        Text("No songs yet. Tap New song to start.")
                            .font(Theme.serifItalic(18))
                            .foregroundColor(Theme.ink2)
                            .padding(40)
                    }
                }
            }
        }
        .alert("Rename song", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Song name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let t = renameTarget { app.rename(t.id, to: renameText) }
                renameTarget = nil
            }
        }
        .alert("Delete this song?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let t = deleteTarget { app.delete(t.id) }
                deleteTarget = nil
            }
        } message: {
            Text("\"\(deleteTarget?.title ?? "")\" and its recordings will be removed from this device. This cannot be undone.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            app.importProject(result: result.map { [$0] })
        }
    }

    private func row(_ p: ProjectInfo) -> some View {
        HStack(spacing: 12) {
            Button(action: { app.open(p.id) }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title).font(Theme.serifMediumItalic(24)).foregroundColor(Theme.ink)
                    Text("\(Int(p.tempo.rounded())) bpm  \u{2022}  \(p.keyName)  \u{2022}  \(p.bars) bars  \u{2022}  edited \(SongsView.dateFormatter.string(from: p.modified))")
                        .font(Theme.ui(14)).foregroundColor(Theme.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button("Rename") {
                    renameText = p.title
                    renameTarget = p
                }
                Button("Duplicate") { app.duplicate(p.id) }
                Button("Delete", role: .destructive) { deleteTarget = p }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.ink2)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }
}
