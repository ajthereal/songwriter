# Songwriter v1 — build spec

A light DAW for **songwriting on iPad**: structure a song, record vocals, play parts from a MIDI keyboard, let a simple band follow the chord track, and bounce a demo good enough to post or hand to Suno or a producer. Not a mixing/mastering tool.

Owner: AJ (music graduate, keyboardist, producer, used to Logic Pro). Only user. iPad (landscape main), iPhone should not crash.
All UI text in **English**. Anything that can fail shows a plain message saying what happened and what to do. Never fail silently.

## Platform

- **Swift Playgrounds app package**: `Songwriter.swiftpm/` at repo root. Opens and runs in Swift Playgrounds on iPad (free, no developer account).
- SwiftUI, iOS 17.0 minimum. Swift tools 5.9, Swift 5 language mode (avoid strict-concurrency errors). No third-party packages.
- `Package.swift` uses `AppleProductTypes` `.iOSApplication` (bundle id `com.ajthereal.songwriter`, display version `0.1`, app category music, `.microphone(purposeString:)` capability, supported orientations: all on iPad). Executable target `AppModule`, `path: "."`, `resources: [.process("Resources")]`.
- Audio: AVAudioEngine + AVAudioUnitSampler (SoundFont) + AVAudioUnitEQ / AVAudioUnitReverb / Apple AUs (DynamicsProcessor, PeakLimiter) via `AVAudioUnitEffect(audioComponentDescription:)`.
- MIDI in: CoreMIDI (`MIDIClientCreateWithBlock`, `MIDIInputPortCreateWithProtocol` MIDI 1.0, connect every source; re-scan on `kMIDIMsgSetupChanged`). USB-C and Bluetooth MIDI keyboards (Bluetooth pairing is done in another app; show a hint if no source).
- Audio session: `.playAndRecord`, options `.defaultToSpeaker, .allowBluetoothA2DP`, mode `.default`, preferred sample rate 48 kHz, IO buffer ~5 ms. Handle interruptions and route changes (USB-C mic plugged/unplugged) and show a message.

## Sounds

- One bundled SoundFont: **GeneralUser GS** (S. Christian Collins, free licence, include its licence file in `Resources/Licenses/`). Use programs: Grand Piano 0, E-Piano 4 (Rhodes-like), Fingered Bass 33, Warm Pad 89, Strings 48; Drums bank MSB 0x78 program 0 (Standard kit). Instrument list in the app is exactly: Grand Piano, E-Piano, Bass, Drums, Pad, Strings.
- Fonts (OFL, bundled + registered at launch with `CTFontManagerRegisterFontsForURL`): **Spectral** (Regular, Italic, MediumItalic), **Barlow** (Regular, Medium, SemiBold), **Barlow Condensed** (SemiBold, Bold). Fallback to system fonts if registration fails (no crash).

## Design (match the approved mockup "Main view · Tracks")

Light (default follows system; manual Light/Dark/System toggle in Settings):

| token | light | dark |
|---|---|---|
| bg (paper) | #F3F5F8 | #131925 |
| panel | #EDF1F6 | #182030 |
| line | #D5DEEA | #2B3648 |
| grid | #E3E9F1 | #222C3C |
| ink | #17202E | #E8ECF2 |
| ink2 (secondary text) | #4F5B6D | #A3AEBF |
| red pencil (record, playhead, cycle) | #C2362B | #FF6A5C |
| armed-row highlight | #E9EFF7 | #172235 |

Track colours `[body, caption strip, content]` light / dark:
Vocal `#DCE6F7 #2F5DB8 #2F5DB8` / `#1E2F4D #3E6CC4 #9DBDF0` · Second audio `#E4E9F3 #6A82B0 #4F6894` / `#1C283C #566F9C #8AA3CC` · Piano `#F4E8D2 #A8741C #8A5D12` / `#33291A #A8741C #E3B866` · E-Piano `#ECE4F5 #7454A8 #5B3F8C` / `#2A2240 #6E52A0 #C2ADE6` · Bass `#DDEEE4 #2F7A55 #23603F` / `#1B3128 #2E7552 #8FCBA9` · Drums `#F6E0DC #B5473A #8E3328` / `#37201E #A9473B #F0A397` · Pad/Strings reuse E-Piano / Vocal-2 colours. Caption text white.

Type: song title Spectral Italic Medium 25; secondary labels Spectral Italic; UI Barlow; chord symbols and bar/beat counter Barlow Condensed Bold, chord extensions raised and smaller (D<sup>add9</sup>).

Layout (iPad landscape, top to bottom):
1. **Header** (≈76 pt): title + "Tempo ♩ = 84" (tap to edit tempo/key/time signature) · transport (back to start, Play, Record ring, Cycle pill, Click pill) · bar.beat counter · view switch **Tracks | Chart | Lyrics** (serif italic, selected underlined red) · Bounce button.
2. **Ruler block** (≈104 pt), left column 230 pt shows stacked time signature + key; right: section markers (boxed letter + italic name), **chord track** row, bar numbers, cycle bar (red, rounded) and red pencil-tip playhead.
3. **Tracks**: header column 230 pt (colour stripe, name, instrument in italic, M / S / record-arm circles, volume on long-press or in a track sheet). Lanes: light bar grid, Logic-style regions (rounded 5, tinted body, darker caption strip with region name, waveform for audio, mini note bars for MIDI). Red playhead line. "+ New track" at the bottom.
4. **Editor** (bottom, ≈236 pt, collapsible): **Piano Roll** for the selected MIDI region (keys, alternating rows for black keys, beat/bar grid, note blocks), or **Takes** for a selected audio region.
Touch targets ≥ 44 pt. Pinch to zoom horizontally, scroll both axes. Respect Dynamic Type sensibly, support dark mode, no emoji in UI.

## Features (v1 scope)

**Song**: title, tempo 40–240, key (12 major/minor), time signature 4/4, 3/4, 6/8. Sections (markers): name, letter, start bar, length; add, rename, resize, reorder (moving a section moves all regions and chords inside it), duplicate (e.g. Verse 2 from Verse 1).

**Chord track**: chords per bar or half bar. Edit by tapping a slot → chord picker (root, quality: maj, m, 7, maj7, m7, sus2, sus4, add9, dim, aug, m7b5, 6, m6, 9; optional slash bass). A **Chord Pad** strip offers the 7 diatonic chords of the song key plus ♭VII and V/V; tap = audition on the selected instrument, long-press = write at playhead.

**Band follows chords**: each instrument track can be in *Follow chords* mode with a style: Piano (Ballad comp, Pop eighths, Sustained), E-Piano (Pads, Comp), Bass (Roots, Root-five, Eighths), Drums (Ballad, Pop, Half-time, Off), Pad/Strings (Sustained). Generated notes are deterministic from chords + section + style. "Make editable" converts the generated part into normal MIDI regions.

**Tracks**: up to 16. Types: Audio (vocal/instrument recording) and Instrument (sampler). Mute, solo, arm, volume, pan, rename, colour, delete (with confirm).

**Recording audio**: input = current route (USB-C mic, interface or built-in mic); input level meter on armed track; count-in (off / 1 / 2 bars); metronome on/off + volume; Cycle recording creates a new **take** per pass; takes live in the region; choose the active take in the Takes editor (comping by choosing a take per region; splitting a region lets different takes play in different parts). Files: 48 kHz 24-bit (or float32) CAF/WAV inside the project folder. **Latency offset** (ms, default from `inputLatency + outputLatency + ioBufferDuration`, user-adjustable in Settings) shifts recorded audio earlier so it lines up. Warn (once) if output is Bluetooth: "Bluetooth headphones add delay. Use wired headphones or your interface for recording." Monitoring: off by default (direct monitoring on the mic/interface); optional software monitoring toggle.

**Recording MIDI**: MIDI keyboard always plays the selected instrument track (low-latency direct to sampler). When recording, note on/off + velocity + sustain pedal (CC64) are recorded into a region on the armed instrument track. On-screen keyboard (2 octaves, octave shift) as a fallback.

**Editing**: tap to select region; drag to move (snap to beat by default, snap toggle: bar / beat / 1/8 / off); drag edges to trim; split at playhead; duplicate; delete; loop region n times. Piano Roll: tap empty to add a note (length = grid), drag to move, drag right edge to resize, double-tap to delete, velocity by vertical drag in a velocity lane, Quantize (1/4, 1/8, 1/16, triplet 1/8). **Undo/Redo** for every edit (snapshot of the song model, at least 50 steps).

**Chart view**: lead sheet generated from sections + chord track + lyrics: 4 bars per line, boxed section letters, chords above lyrics. Read-only, follows playhead.

**Lyrics view**: one text block per section, edited in place. Lyrics appear in the Chart view and the Suno pack.

**Mix (light)**: per-track volume/pan; Audio tracks get a fixed **vocal chain** (high-pass 90 Hz, gentle presence EQ, compressor, send to shared reverb) with a "Vocal chain on/off" toggle and a Reverb amount; master bus: peak limiter at −1 dBTP.

**Bounce / Export** (sheet like the mockup) to the Files app via `fileExporter` / share sheet:
- Song mix: WAV 24-bit 48 kHz and M4A (AAC 256 kbps), rendered offline (manual rendering mode), loudness-normalised to about **−14 LUFS integrated** (ITU-R BS.1770 K-weighting with gating) before the limiter, true peak ≤ −1 dB.
- Stems: one WAV per non-muted track, full length from bar 1, no master normalisation.
- MIDI file: Standard MIDI File type 1, tempo + time signature + one track per instrument track + a chord-name marker track.
- Suno pack (.txt): `[Intro] [Verse 1] [Pre-Chorus] [Chorus]…` tags with lyrics, plus a style line (genre placeholder the user edits, BPM, key, mood); exported with the M4A demo.
- Lead sheet PDF: the Chart view rendered to PDF (A4).
- Project backup: the whole project folder as a single exported package/folder; Import project from Files.

**Projects**: list on launch (Songs screen): new, open, rename, duplicate, delete (confirm). Autosave on every change (debounced) to `Documents/Projects/<uuid>/song.json` + `audio/`. Schema versioned (`version: 1`).

**Settings**: theme, latency offset + "Measure latency" helper (plays clicks, user taps along or loopback through mic; keep it simple), count-in, metronome sound volume, default snap.

## Architecture

- `Model/` — Codable value types: `Song`, `Section`, `ChordEvent`, `Track`, `Region` (audio or MIDI), `Take`, `Note`. Pure Swift, no UIKit/AVFoundation imports, so it is unit-testable.
- `Theory/` — chord parsing/spelling, diatonic chords for a key, `BandGenerator` (chords + style → notes). Pure Swift.
- `Audio/` — `AudioEngine` (graph, transport, scheduling MIDI on samplers with sample-accurate timing via `AVAudioTime` or a render-thread scheduler; audio regions via `AVAudioPlayerNode.scheduleSegment`), `Recorder`, `Metronome`, `Bouncer` (offline render + loudness), `MIDIInput`.
- `Export/` — `MIDIFileWriter`, `SunoPack`, `LeadSheetPDF`.
- `Store/` — `ProjectStore` (load/save/list/import/export), `UndoStack`.
- `UI/` — SwiftUI views per the layout; `Theme` with the tokens above.
- Playback timing: transport time in beats; convert with tempo (single tempo per song in v1). Cycle loops between section boundaries or a custom bar range.

## Quality bar ("without bugs")

- Every audio/MIDI/file error caught and shown in a non-blocking banner with a plain sentence. Microphone permission denied → screen explaining how to enable it in Settings > Privacy > Microphone.
- No force unwraps on I/O. Engine restart on configuration change. Audio files written off the main thread.
- Pure-Swift parts (`Model`, `Theory`, `Export/MIDIFileWriter`, loudness maths) are covered by XCTest in a separate test package (`Tests/`) that the CI runs on macOS.
- CI (`.github/workflows/build.yml`, macOS runner, latest Xcode): (1) `xcodebuild` build of `Songwriter.swiftpm` for iOS Simulator, (2) `swift test` on the test package, (3) commit the full log + a one-line `STATUS` (PASS/FAIL) to branch `ci-results` (folder per commit SHA, plus `latest/`), because this cloud session can't read the Actions API.

## Out of scope for v1

AUv3 plugin hosting (planned v2 if Playgrounds allows), pitch correction, time-stretch, automation, tempo changes within a song, video, collaboration, cloud sync.
