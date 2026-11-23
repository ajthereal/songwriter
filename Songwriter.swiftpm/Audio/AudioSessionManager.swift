import AVFoundation

/// Configures the shared audio session and reports interruptions and route changes in plain English.
final class AudioSessionManager: NSObject {
    static let shared = AudioSessionManager()

    /// Called on the main thread.
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: (() -> Void)?
    var onRouteChanged: (() -> Void)?

    private var observing = false

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        // Preferences are best effort; the system may choose different values.
        try? session.setPreferredSampleRate(48000)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        startObserving()
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(interruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(routeChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(mediaReset(_:)), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    @objc private func interruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        DispatchQueue.main.async {
            switch type {
            case .began:
                ErrorCenter.post("Audio was interrupted, for example by a call or another app. Playback stopped.", warning: true)
                self.onInterruptionBegan?()
            case .ended:
                do {
                    try self.activate()
                } catch {
                    ErrorCenter.report(error, while: "restart audio after the interruption")
                }
                self.onInterruptionEnded?()
            @unknown default:
                break
            }
        }
    }

    @objc private func routeChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        DispatchQueue.main.async {
            switch reason {
            case .newDeviceAvailable:
                ErrorCenter.post("Audio route changed to \(self.outputName).", warning: true)
            case .oldDeviceUnavailable:
                ErrorCenter.post("An audio device was unplugged. Now using \(self.outputName).", warning: true)
            default:
                break
            }
            self.onRouteChanged?()
        }
    }

    @objc private func mediaReset(_ note: Notification) {
        DispatchQueue.main.async {
            ErrorCenter.post("The audio system was reset. Press play to continue.", warning: true)
            do { try self.activate() } catch { ErrorCenter.report(error, while: "restart audio") }
            self.onRouteChanged?()
        }
    }

    // MARK: Route info

    var outputName: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "the built-in speaker"
    }

    var inputName: String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "no input"
    }

    var isBluetoothOutput: Bool {
        let bt: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { bt.contains($0.portType) }
    }

    /// inputLatency + outputLatency + IO buffer duration, in seconds.
    var reportedLatency: Double {
        let s = AVAudioSession.sharedInstance()
        return max(0, s.inputLatency + s.outputLatency + s.ioBufferDuration)
    }

    var ioBufferDuration: Double { AVAudioSession.sharedInstance().ioBufferDuration }

    /// The latency used to shift recordings, honouring the user's override.
    func effectiveLatency(overrideMs: Double?) -> Double {
        if let ms = overrideMs { return max(0, ms / 1000.0) }
        return reportedLatency
    }

    // MARK: Microphone permission

    enum MicState {
        case undetermined
        case denied
        case granted
    }

    var micState: MicState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    func requestMic(_ completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
