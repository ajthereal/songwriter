import SwiftUI
import UniformTypeIdentifiers

final class CancelToken {
    var cancelled = false
}

struct BounceSheet: View {
    @ObservedObject var session: ProjectSession
    @Environment(\.dismiss) var dismiss

    @State var wantWAV = true
    @State var wantM4A = true
    @State var wantStems = false
    @State var wantMIDI = true
    @State var wantSuno = true
    @State var wantPDF = true
    @State var wantBackup = false
    @State var genre = "genre (edit me)"
    @State var mood = "mood (edit me)"
    @State var busy = false
    @State var progress: Double = 0
    @State var status = ""
    @State var folder: URL?
    @State var files: [URL] = []
    @State var report: BounceReport?
    @State var showExporter = false
    @State var token = CancelToken()

    var anyChoice: Bool { wantWAV || wantM4A || wantStems || wantMIDI || wantSuno || wantPDF || wantBackup }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Bounce and export") {
                if busy { token.cancelled = true }
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Everything is rendered on this device. The mix is normalised to about \u{2212}14 LUFS with a true peak ceiling of \u{2212}1 dB.")
                        .font(Theme.serifItalic(15)).foregroundColor(Theme.ink2)
                    group("Audio") {
                        toggleRow("Song mix, WAV (24 bit, 48 kHz)", $wantWAV)
                        toggleRow("Song mix, M4A (AAC 256 kbps)", $wantM4A)
                        toggleRow("Stems, one WAV per track (no normalising)", $wantStems)
                    }
                    group("Other formats") {
                        toggleRow("MIDI file (tempo, chords and one track per instrument)", $wantMIDI)
                        toggleRow("Suno pack (lyrics with section tags and a style line)", $wantSuno)
                        toggleRow("Lead sheet PDF (A4)", $wantPDF)
                        toggleRow("Project backup (the whole project folder)", $wantBackup)
                    }
                    if wantSuno {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Style line for Suno").font(Theme.serifItalic(14)).foregroundColor(Theme.ink2)
                            TextField("Genre", text: $genre).textFieldStyle(.roundedBorder)
                            TextField("Mood", text: $mood).textFieldStyle(.roundedBorder)
                        }
                    }
                    if busy {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress)
                            Text(status).font(Theme.ui(14)).foregroundColor(Theme.ink2)
                            TextActionButton(title: "Cancel") { token.cancelled = true }
                        }
                    } else {
                        TextActionButton(title: "Export", systemName: "square.and.arrow.up", prominent: true, enabled: anyChoice) { start() }
                        if !status.isEmpty {
                            Text(status).font(Theme.ui(14)).foregroundColor(Theme.ink2)
                        }
                    }
                    if let r = report {
                        Text(String(format: "Loudness %.1f LUFS (was %.1f before normalising), true peak %.1f dB, length %.0f s", r.lufsAfter, r.lufsBefore, r.truePeakDB, r.seconds))
                            .font(Theme.serifItalic(14)).foregroundColor(Theme.ink)
                    }
                    if !files.isEmpty && !busy {
                        resultList
                    }
                }
                .padding(20)
            }
        }
        .background(Theme.paper)
        .fileExporter(isPresented: $showExporter,
                      document: FolderDocument(url: folder ?? URL(fileURLWithPath: NSTemporaryDirectory())),
                      contentType: .folder,
                      defaultFilename: folder?.lastPathComponent ?? "Songwriter Export") { result in
            switch result {
            case .success:
                ErrorCenter.post("Saved to the Files app.", warning: true)
            case .failure(let error):
                ErrorCenter.report(error, while: "save the export")
            }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Theme.serifMediumItalic(18)).foregroundColor(Theme.ink).padding(.bottom, 4)
            content()
        }
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(title).font(Theme.ui(16)).foregroundColor(Theme.ink)
        }
        .tint(Theme.red)
        .frame(minHeight: 44)
        .disabled(busy)
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ready to save").font(Theme.serifMediumItalic(18)).foregroundColor(Theme.ink)
            TextActionButton(title: "Save all to Files", systemName: "folder", prominent: true) { showExporter = true }
            ForEach(files, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent).font(Theme.ui(15)).foregroundColor(Theme.ink).lineLimit(1)
                    Spacer()
                    if !isDirectory(url) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }
                    }
                }
                .frame(minHeight: 44)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Song" : cleaned
    }

    // MARK: Export

    private func start() {
        if session.isPlaying { session.stop() }
        session.saveNow(synchronous: true)
        busy = true
        progress = 0
        status = "Starting"
        report = nil
        files = []
        let newToken = CancelToken()
        token = newToken

        let song = session.song
        let audioDir = session.audioDir
        let projectDir = session.store.projectDir(session.projectID)
        let name = safeName(song.title)
        let opts = (wav: wantWAV, m4a: wantM4A, stems: wantStems, midi: wantMIDI, suno: wantSuno, pdf: wantPDF, backup: wantBackup)
        let genreText = genre
        let moodText = mood

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fm = FileManager.default
                let out = fm.temporaryDirectory.appendingPathComponent("\(name) Export", isDirectory: true)
                try? fm.removeItem(at: out)
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                var produced: [URL] = []
                var rep: BounceReport?

                func setStatus(_ text: String, _ p: Double) {
                    DispatchQueue.main.async {
                        status = text
                        progress = p
                    }
                }

                if opts.wav || opts.m4a {
                    setStatus("Rendering the mix", 0.02)
                    let rendered = try Bouncer.render(song: song, audioDir: audioDir, only: nil,
                                                      progress: { p in setStatus("Rendering the mix", 0.02 + p * 0.5) },
                                                      isCancelled: { newToken.cancelled })
                    setStatus("Measuring loudness", 0.55)
                    let (norm, r) = try Bouncer.normalise(rendered)
                    rep = r
                    if opts.wav {
                        setStatus("Writing WAV", 0.6)
                        let url = out.appendingPathComponent("\(name).wav")
                        try Bouncer.writeWAV24(norm, to: url)
                        produced.append(url)
                    }
                    if opts.m4a {
                        setStatus("Writing M4A", 0.68)
                        let url = out.appendingPathComponent("\(name).m4a")
                        try Bouncer.writeM4A(norm, to: url)
                        produced.append(url)
                    }
                }
                if opts.stems {
                    let stemTracks = song.tracks.filter { t in
                        if t.muted { return false }
                        if t.kind == .audio { return !t.regions.isEmpty }
                        return t.follow || !t.regions.isEmpty
                    }
                    for (i, t) in stemTracks.enumerated() {
                        let base = 0.7 + 0.2 * Double(i) / Double(max(1, stemTracks.count))
                        setStatus("Rendering stem \(i + 1) of \(stemTracks.count): \(t.name)", base)
                        let stem = try Bouncer.render(song: song, audioDir: audioDir, only: t.id, progress: { _ in },
                                                      isCancelled: { newToken.cancelled })
                        let url = out.appendingPathComponent("\(name) - \(i + 1) \(safeName(t.name)).wav")
                        try Bouncer.writeWAV24(stem, to: url)
                        produced.append(url)
                    }
                    if stemTracks.isEmpty {
                        ErrorCenter.post("There were no unmuted tracks with content, so no stems were written.", warning: true)
                    }
                }
                if opts.midi {
                    setStatus("Writing MIDI file", 0.92)
                    let url = out.appendingPathComponent("\(name).mid")
                    try MIDIFileWriter.data(for: song).write(to: url, options: .atomic)
                    produced.append(url)
                }
                if opts.suno {
                    setStatus("Writing Suno pack", 0.94)
                    let url = out.appendingPathComponent("\(name) Suno pack.txt")
                    let text = SunoPack.text(for: song, genre: genreText, mood: moodText)
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    produced.append(url)
                }
                if opts.pdf {
                    setStatus("Rendering the lead sheet", 0.96)
                    let url = out.appendingPathComponent("\(name) lead sheet.pdf")
                    var data = Data()
                    DispatchQueue.main.sync { data = LeadSheetPDF.render(song: song) }
                    try data.write(to: url, options: .atomic)
                    produced.append(url)
                }
                if opts.backup {
                    setStatus("Copying the project folder", 0.98)
                    let dst = out.appendingPathComponent("\(name) project", isDirectory: true)
                    try fm.copyItem(at: projectDir, to: dst)
                    produced.append(dst)
                }
                let finalFiles = produced
                let finalReport = rep
                DispatchQueue.main.async {
                    busy = false
                    progress = 1
                    folder = out
                    files = finalFiles
                    report = finalReport
                    status = finalFiles.isEmpty ? "Nothing was exported." : "Done. \(finalFiles.count) item\(finalFiles.count == 1 ? "" : "s") ready."
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false
                    status = "The export did not finish."
                    if !newToken.cancelled { ErrorCenter.report(error, while: "export the song") }
                }
            }
        }
    }
}
