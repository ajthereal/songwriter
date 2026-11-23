import Foundation

/// Finds bundled files whether the app is built by Xcode, SwiftPM or Swift Playgrounds.
enum ResourceLocator {
    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = [Bundle.main]
        bundles.append(contentsOf: Bundle.allBundles)
        if let res = Bundle.main.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(at: res, includingPropertiesForKeys: nil) {
            for u in items where u.pathExtension == "bundle" {
                if let b = Bundle(url: u) { bundles.append(b) }
            }
        }
        return bundles
    }

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        let subdirs: [String?] = [nil, "Sounds", "Fonts", "Licenses", "Resources", "Resources/Sounds", "Resources/Fonts"]
        let bundles = candidateBundles()
        for b in bundles {
            for sub in subdirs {
                if let u = b.url(forResource: name, withExtension: ext, subdirectory: sub) { return u }
            }
        }
        // Last resort: walk the bundle directories.
        let target = name + "." + ext
        var roots: [URL] = [Bundle.main.bundleURL]
        if let res = Bundle.main.resourceURL,
           let items = try? FileManager.default.contentsOfDirectory(at: res, includingPropertiesForKeys: nil) {
            roots.append(contentsOf: items.filter { $0.pathExtension == "bundle" })
        }
        for root in roots {
            if let found = search(root: root, fileName: target) { return found }
        }
        return nil
    }

    static func urls(withExtension ext: String) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        for b in candidateBundles() {
            guard let e = FileManager.default.enumerator(at: b.bundleURL, includingPropertiesForKeys: nil) else { continue }
            for case let u as URL in e where u.pathExtension.lowercased() == ext.lowercased() {
                if seen.insert(u.lastPathComponent).inserted { out.append(u) }
            }
        }
        return out
    }

    private static func search(root: URL, fileName: String) -> URL? {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let u as URL in e where u.lastPathComponent == fileName { return u }
        return nil
    }

    static var soundFontURL: URL? {
        url(forResource: "GeneralUser-GS", withExtension: "sf2")
    }
}
