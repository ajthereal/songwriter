import SwiftUI

/// A single place for user-facing problems. Every catch block ends up here with a plain English sentence.
final class ErrorCenter: ObservableObject {
    static let shared = ErrorCenter()

    struct Banner: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var isWarning: Bool
    }

    @Published var banner: Banner?
    private var dismissItem: DispatchWorkItem?

    /// Safe to call from any thread.
    static func post(_ message: String, warning: Bool = false) {
        DispatchQueue.main.async {
            ErrorCenter.shared.show(message, warning: warning)
        }
    }

    /// Reports a thrown error as "Could not <action>. <reason>".
    static func report(_ error: Error, while action: String) {
        post("Could not \(action). \(describe(error))")
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription, !d.isEmpty { return d }
        let text = (error as NSError).localizedDescription
        return text.isEmpty ? "An unknown problem occurred." : text
    }

    func show(_ message: String, warning: Bool) {
        banner = Banner(message: message, isWarning: warning)
        dismissItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.banner = nil }
        dismissItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (warning ? 8 : 10), execute: item)
    }

    func dismiss() {
        dismissItem?.cancel()
        banner = nil
    }
}

struct AppMessage: LocalizedError {
    var text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
