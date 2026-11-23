import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SnapMode: String, CaseIterable, Identifiable {
    case bar
    case beat
    case eighth
    case off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bar: return "Bar"
        case .beat: return "Beat"
        case .eighth: return "1/8"
        case .off: return "Off"
        }
    }
    /// Grid size in beats (nil when snapping is off).
    func grid(beatsPerBar: Double) -> Double? {
        switch self {
        case .bar: return beatsPerBar
        case .beat: return 1.0
        case .eighth: return 0.5
        case .off: return nil
        }
    }
    func snap(_ value: Double, beatsPerBar: Double) -> Double {
        guard let g = grid(beatsPerBar: beatsPerBar) else { return value }
        return (value / g).rounded() * g
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var theme: ThemeMode { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    /// nil means "use the value reported by the audio system".
    @Published var latencyOverrideMs: Double? {
        didSet {
            if let v = latencyOverrideMs { defaults.set(v, forKey: "latencyOverrideMs") } else { defaults.removeObject(forKey: "latencyOverrideMs") }
        }
    }
    @Published var countInBars: Int { didSet { defaults.set(countInBars, forKey: "countInBars") } }
    @Published var metronomeVolume: Double { didSet { defaults.set(metronomeVolume, forKey: "metronomeVolume") } }
    @Published var defaultSnap: SnapMode { didSet { defaults.set(defaultSnap.rawValue, forKey: "defaultSnap") } }
    @Published var softwareMonitoring: Bool { didSet { defaults.set(softwareMonitoring, forKey: "softwareMonitoring") } }
    @Published var clickOn: Bool { didSet { defaults.set(clickOn, forKey: "clickOn") } }

    var bluetoothWarningShown: Bool {
        get { defaults.bool(forKey: "bluetoothWarningShown") }
        set { defaults.set(newValue, forKey: "bluetoothWarningShown") }
    }

    init() {
        theme = ThemeMode(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        if defaults.object(forKey: "latencyOverrideMs") != nil {
            latencyOverrideMs = defaults.double(forKey: "latencyOverrideMs")
        } else {
            latencyOverrideMs = nil
        }
        countInBars = defaults.object(forKey: "countInBars") != nil ? defaults.integer(forKey: "countInBars") : 1
        metronomeVolume = defaults.object(forKey: "metronomeVolume") != nil ? defaults.double(forKey: "metronomeVolume") : 0.6
        defaultSnap = SnapMode(rawValue: defaults.string(forKey: "defaultSnap") ?? "") ?? .beat
        softwareMonitoring = defaults.bool(forKey: "softwareMonitoring")
        clickOn = defaults.object(forKey: "clickOn") != nil ? defaults.bool(forKey: "clickOn") : true
    }
}
