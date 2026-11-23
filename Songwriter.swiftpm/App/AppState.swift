import SwiftUI

/// App-wide state: the project list and the open project.
final class AppState: ObservableObject {
    @Published var projects: [ProjectInfo] = []
    @Published var session: ProjectSession?
    @Published var loading = false

    private let store = ProjectStore.shared

    init() {
        FontRegistrar.registerAll()
        do {
            try AudioSessionManager.shared.activate()
        } catch {
            ErrorCenter.report(error, while: "set up audio")
        }
        AudioSessionManager.shared.onInterruptionBegan = { [weak self] in self?.session?.interrupted() }
        do {
            _ = try store.seedIfEmpty()
        } catch {
            ErrorCenter.report(error, while: "create the demo song")
        }
        refresh()
    }

    func refresh() {
        let result = store.list()
        projects = result.projects
        if result.unreadable > 0 {
            ErrorCenter.post("\(result.unreadable) project\(result.unreadable == 1 ? "" : "s") could not be read and \(result.unreadable == 1 ? "is" : "are") hidden. They are still in the Projects folder.", warning: true)
        }
    }

    func open(_ id: UUID) {
        do {
            let song = try store.load(id)
            session?.close()
            session = ProjectSession(song: song)
        } catch {
            ErrorCenter.report(error, while: "open the project")
        }
    }

    func closeProject() {
        session?.close()
        session = nil
        refresh()
    }

    func create() {
        var song = Song(title: "Untitled Song", tempo: 90, key: SongKey(root: 0), timeSignature: .fourFour)
        song.sections = Song.normalized([SongSection(name: "Verse", letter: "A", lengthBars: 8)])
        song.tracks = [Track(name: "Lead Vocal", kind: .audio, colorKey: .vocal),
                       Track(name: "Grand Piano", kind: .instrument, instrument: .grandPiano)]
        song.cycle = CycleRange(startBar: 0, endBar: 4)
        do {
            try store.save(song)
            refresh()
            open(song.id)
        } catch {
            ErrorCenter.report(error, while: "create the project")
        }
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            ErrorCenter.post("A song needs a name.", warning: true)
            return
        }
        do {
            try store.rename(id, to: t)
            refresh()
        } catch {
            ErrorCenter.report(error, while: "rename the project")
        }
    }

    func duplicate(_ id: UUID) {
        do {
            _ = try store.duplicate(id)
            refresh()
        } catch {
            ErrorCenter.report(error, while: "duplicate the project")
        }
    }

    func delete(_ id: UUID) {
        do {
            try store.delete(id)
            refresh()
        } catch {
            ErrorCenter.report(error, while: "delete the project")
        }
    }

    func importProject(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            ErrorCenter.report(error, while: "open that folder")
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let id = try store.importProject(from: url)
                refresh()
                open(id)
            } catch {
                ErrorCenter.report(error, while: "import the project")
            }
        }
    }
}
