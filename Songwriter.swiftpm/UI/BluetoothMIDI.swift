import SwiftUI
import UIKit
import CoreAudioKit

/// Wraps CoreAudioKit's Bluetooth MIDI pairing screen in a navigation controller with a Done button.
struct BluetoothMIDIView: UIViewControllerRepresentable {
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let central = CABTMIDICentralViewController()
        central.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.done))
        return UINavigationController(rootViewController: central)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.onDone = onDone
    }

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject {
        var onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        @objc func done() { onDone() }
    }
}

/// Button that presents the Bluetooth MIDI pairing sheet and rescans MIDI sources when it closes.
struct BluetoothMIDIButton: View {
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text("Bluetooth MIDI").font(Theme.uiMedium(15))
            }
            .foregroundColor(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1.2))
            .frame(minHeight: 44)
        }
        .sheet(isPresented: $showing, onDismiss: { MIDIInput.shared.rescan() }) {
            BluetoothMIDIView(onDone: { showing = false })
        }
    }
}
