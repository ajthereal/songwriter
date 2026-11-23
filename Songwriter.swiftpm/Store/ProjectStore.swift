import Foundation

struct ProjectInfo: Identifiable, Equatable {
    var id: UUID
    var title: String
    var modified: Date
    var tempo: Double
    var keyName: String
    var bars: Int
}

enum StoreError: LocalizedError {
    case noDocumentsFolder
    case notAProject
    case futureVersion
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .noDocumentsFolder: return "The app's Documents folder is not available."
        case .notAProject: return "That folder does not look like a Songwriter project. It needs a song.json file."
        case .futureVersion: return "That project was saved by a newer version of Songwriter."
        case .missing(let what): return "\(what) could not be found."
        }
    }
}

/// Projects live in Documents/Projects/<uuid>/ with song.json and an audio/ folder.
final class ProjectStore {
    static let shared = ProjectStore()
    private let fm = FileManager.default

    var root: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("Projects", isDirectory: true)
    }

    func projectDir(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func audioDir(_ id: UUID) -> URL { projectDir(id).appendingPathComponent("audio", isDirectory: true) }
    func songURL(_ id: UUID) -> URL { projectDir(id).appendingPathComponent("song.json") }

    private func ensureDirs(_ id: UUID) throws {
        try fm.createDirectory(at: audioDir(id), withIntermediateDirectories: true)
    }

    func list() -> (projects: [ProjectInfo], unreadable: Int) {
        var out: [ProjectInfo] = []
        var bad = 0
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return ([], 0)
        }
        for dir in items {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let file = dir.appendingPathComponent("song.json")
            guard fm.fileExists(atPath: file.path) else { continue }
            do {
                let data = try Data(contentsOf: file)
                let song = try SongCodec.decode(data)
                let attrs = try? fm.attributesOfItem(atPath: file.path)
                let date = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                out.append(ProjectInfo(id: song.id, title: song.title, modified: date, tempo: song.tempo,
                                       keyName: song.key.displayName, bars: song.totalBars))
            } catch {
                bad += 1
            }
        }
        out.sort { $0.modified > $1.modified }
        return (out, bad)
    }

    func load(_ id: UUID) throws -> Song {
        let data = try Data(contentsOf: songURL(id))
        do {
            return try SongCodec.decode(data)
        } catch SongCodec.CodecError.unsupportedVersion {
            throw StoreError.futureVersion
        } catch {
            throw StoreError.notAProject
        }
    }

    /// Writes song.json atomically.
    func save(_ song: Song) throws {
        try ensureDirs(song.id)
        let data = try SongCodec.encode(song)
        try data.write(to: songURL(song.id), options: .atomic)
    }

    func delete(_ id: UUID) throws {
        let dir = projectDir(id)
        if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
    }

    func duplicate(_ id: UUID) throws -> UUID {
        var song = try load(id)
        let newID = UUID()
        let src = projectDir(id)
        let dst = projectDir(newID)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: dst)
        song.id = newID
        song.title += " copy"
        try save(song)
        return newID
    }

    func rename(_ id: UUID, to title: String) throws {
        var song = try load(id)
        song.title = title
        try save(song)
    }

    /// Copies a project folder (chosen in the Files app) into the store under a new identifier.
    func importProject(from folder: URL) throws -> UUID {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        let songFile = folder.appendingPathComponent("song.json")
        guard fm.fileExists(atPath: songFile.path) else { throw StoreError.notAProject }
        let data = try Data(contentsOf: songFile)
        var song: Song
        do {
            song = try SongCodec.decode(data)
        } catch SongCodec.CodecError.unsupportedVersion {
            throw StoreError.futureVersion
        } catch {
            throw StoreError.notAProject
        }
        let newID = UUID()
        let dst = projectDir(newID)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.copyItem(at: folder, to: dst)
        song.id = newID
        try save(song)
        return newID
    }

    /// Creates the demo project when the store is empty.
    func seedIfEmpty() throws -> Bool {
        let (projects, bad) = list()
        if projects.isEmpty && bad == 0 {
            try save(Song.demo())
            return true
        }
        return false
    }

    func audioFileURL(project: UUID, fileName: String) -> URL {
        audioDir(project).appendingPathComponent(fileName)
    }
}
