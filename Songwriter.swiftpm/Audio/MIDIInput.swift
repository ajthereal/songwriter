import Foundation
import CoreMIDI

/// Receives MIDI 1.0 channel voice messages from every connected source (USB-C and Bluetooth keyboards).
final class MIDIInput {
    static let shared = MIDIInput()
    var onNoteOn: ((Int, Int) -> Void)?
    var onNoteOff: ((Int) -> Void)?
    var onSustain: ((Bool) -> Void)?
    /// Called on the main thread when the number of connected sources changes.
    var onSourcesChanged: ((Int) -> Void)?

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var started = false
    private(set) var sourceCount = 0

    func start() {
        guard !started else { return }
        let status = MIDIClientCreateWithBlock("Songwriter" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                self?.rescan()
            }
        }
        guard status == noErr else {
            ErrorCenter.post("MIDI is not available (error \(status)). You can still use the on-screen keyboard.")
            return
        }
        let portStatus = MIDIInputPortCreateWithProtocol(client, "Songwriter In" as CFString, ._1_0, &port) { [weak self] eventList, _ in
            self?.handle(eventList)
        }
        guard portStatus == noErr else {
            ErrorCenter.post("Could not open the MIDI input (error \(portStatus)). You can still use the on-screen keyboard.")
            return
        }
        started = true
        rescan()
    }

    func rescan() {
        guard port != 0 else { return }
        let count = MIDIGetNumberOfSources()
        var connected = 0
        for i in 0..<count {
            let src = MIDIGetSource(i)
            if src != 0 && MIDIPortConnectSource(port, src, nil) == noErr { connected += 1 }
        }
        sourceCount = connected
        DispatchQueue.main.async { self.onSourcesChanged?(connected) }
    }

    private func handle(_ listPtr: UnsafePointer<MIDIEventList>) {
        for packetPtr in listPtr.unsafeSequence() {
            let packet = packetPtr.pointee
            let count = Int(packet.wordCount)
            withUnsafeBytes(of: packet.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                var i = 0
                while i < count && i < words.count {
                    process(words[i])
                    i += 1
                }
            }
        }
    }

    private func process(_ word: UInt32) {
        let messageType = (word >> 28) & 0xF
        guard messageType == 0x2 else { return }       // MIDI 1.0 channel voice
        let status = Int((word >> 16) & 0xF0)
        let data1 = Int((word >> 8) & 0x7F)
        let data2 = Int(word & 0x7F)
        switch status {
        case 0x90:
            if data2 > 0 { onNoteOn?(data1, data2) } else { onNoteOff?(data1) }
        case 0x80:
            onNoteOff?(data1)
        case 0xB0:
            if data1 == 64 { onSustain?(data2 >= 64) }
        default:
            break
        }
    }
}
