import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var session: ProjectSession
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss
    @State var measured = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Settings") { dismiss() }
            Form {
                Picker("Appearance", selection: $settings.theme) {
                    ForEach(ThemeMode.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)

                latencyRows

                Picker("Count-in", selection: $settings.countInBars) {
                    Text("Off").tag(0)
                    Text("1 bar").tag(1)
                    Text("2 bars").tag(2)
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Metronome volume").font(Theme.ui(16))
                    Slider(value: $settings.metronomeVolume, in: 0...1)
                }
                Picker("Default snap", selection: $settings.defaultSnap) {
                    ForEach(SnapMode.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                Toggle("Software monitoring (hear the input through the app)", isOn: $settings.softwareMonitoring)
                Text("Leave this off when recording with speakers. Direct monitoring on your interface has no delay. Use headphones if you turn it on.")
                    .font(Theme.serifItalic(13)).foregroundColor(Theme.ink2)

                Section("MIDI and audio devices") {
                    Text(session.midiSourceCount > 0
                         ? "\(session.midiSourceCount) MIDI source\(session.midiSourceCount == 1 ? "" : "s") connected."
                         : "No MIDI keyboard found. Plug it in with USB-C, or tap Bluetooth MIDI to pair it.")
                        .font(Theme.ui(15))
                    BluetoothMIDIButton()
                    Text("Audio output: \(AudioSessionManager.shared.outputName). Input: \(AudioSessionManager.shared.inputName).")
                        .font(Theme.ui(15))
                }
                Section("Sounds and fonts") {
                    Text("Sounds: GeneralUser GS by S. Christian Collins. Fonts: Spectral, Barlow and Barlow Condensed (SIL Open Font License). Licence files are bundled with the app.")
                        .font(Theme.ui(14)).foregroundColor(Theme.ink2)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.paper)
    }

    private var latencyRows: some View {
        let sys = AudioSessionManager.shared
        return Group {
            Toggle("Set the recording latency by hand", isOn: Binding(
                get: { settings.latencyOverrideMs != nil },
                set: { on in settings.latencyOverrideMs = on ? (sys.reportedLatency * 1000).rounded() : nil }
            ))
            if let ms = settings.latencyOverrideMs {
                HStack {
                    Text("Latency offset").font(Theme.ui(16))
                    Spacer()
                    Text("\(Int(ms)) ms").font(Theme.uiMedium(16)).monospacedDigit()
                    Stepper("", onIncrement: { settings.latencyOverrideMs = min(500, ms + 1) },
                            onDecrement: { settings.latencyOverrideMs = max(0, ms - 1) })
                        .labelsHidden()
                }
                Slider(value: Binding(get: { ms }, set: { settings.latencyOverrideMs = $0.rounded() }), in: 0...500)
            } else {
                Text("Using the latency reported by the audio system: \(Int((sys.reportedLatency * 1000).rounded())) ms.")
                    .font(Theme.ui(15))
            }
            Button("Measure latency") { measure() }
            if !measured.isEmpty {
                Text(measured).font(Theme.serifItalic(13)).foregroundColor(Theme.ink2)
            }
            Text("Recorded audio is moved earlier by this amount so it lines up with the music. If vocals sound late, increase it.")
                .font(Theme.serifItalic(13)).foregroundColor(Theme.ink2)
        }
    }

    private func measure() {
        let s = AVAudioSessionSnapshot.read()
        let total = (s.input + s.output + s.buffer) * 1000
        measured = String(format: "Input %.1f ms + output %.1f ms + buffer %.1f ms = %.1f ms. Applied as your offset.", s.input * 1000, s.output * 1000, s.buffer * 1000, total)
        settings.latencyOverrideMs = total.rounded()
    }
}

import AVFoundation

struct AVAudioSessionSnapshot {
    var input: Double
    var output: Double
    var buffer: Double

    static func read() -> AVAudioSessionSnapshot {
        let s = AVAudioSession.sharedInstance()
        return AVAudioSessionSnapshot(input: s.inputLatency, output: s.outputLatency, buffer: s.ioBufferDuration)
    }
}
