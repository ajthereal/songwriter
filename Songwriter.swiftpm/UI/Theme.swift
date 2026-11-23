import SwiftUI
import CoreText

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

struct TrackPalette {
    var body: Color
    var caption: Color
    var content: Color
}

enum Theme {
    static let paper = Color.dynamic(light: 0xF3F5F8, dark: 0x131925)
    static let panel = Color.dynamic(light: 0xEDF1F6, dark: 0x182030)
    static let line = Color.dynamic(light: 0xD5DEEA, dark: 0x2B3648)
    static let grid = Color.dynamic(light: 0xE3E9F1, dark: 0x222C3C)
    static let ink = Color.dynamic(light: 0x17202E, dark: 0xE8ECF2)
    static let ink2 = Color.dynamic(light: 0x4F5B6D, dark: 0xA3AEBF)
    static let red = Color.dynamic(light: 0xC2362B, dark: 0xFF6A5C)
    /// Text and icon colour on top of a Theme.red (or other accent) fill; passes 4.5:1 in both themes.
    static let onAccent = Color.dynamic(light: 0xFFFFFF, dark: 0x131925)
    static let muteOn = Color.dynamic(light: 0x8A5D12, dark: 0xE3B866)
    static let soloOn = Color.dynamic(light: 0x2F5DB8, dark: 0x9DBDF0)
    static let armed = Color.dynamic(light: 0xE9EFF7, dark: 0x172235)

    static func palette(_ key: TrackColorKey) -> TrackPalette {
        switch key {
        case .vocal:
            return TrackPalette(body: .dynamic(light: 0xDCE6F7, dark: 0x1E2F4D),
                                caption: .dynamic(light: 0x2F5DB8, dark: 0x3E6CC4),
                                content: .dynamic(light: 0x2F5DB8, dark: 0x9DBDF0))
        case .audio2:
            return TrackPalette(body: .dynamic(light: 0xE4E9F3, dark: 0x1C283C),
                                caption: .dynamic(light: 0x546C9A, dark: 0x566F9C),
                                content: .dynamic(light: 0x4F6894, dark: 0x8AA3CC))
        case .piano:
            return TrackPalette(body: .dynamic(light: 0xF4E8D2, dark: 0x33291A),
                                caption: .dynamic(light: 0x95650F, dark: 0x95650F),
                                content: .dynamic(light: 0x8A5D12, dark: 0xE3B866))
        case .ePiano:
            return TrackPalette(body: .dynamic(light: 0xECE4F5, dark: 0x2A2240),
                                caption: .dynamic(light: 0x7454A8, dark: 0x6E52A0),
                                content: .dynamic(light: 0x5B3F8C, dark: 0xC2ADE6))
        case .bass:
            return TrackPalette(body: .dynamic(light: 0xDDEEE4, dark: 0x1B3128),
                                caption: .dynamic(light: 0x2F7A55, dark: 0x2E7552),
                                content: .dynamic(light: 0x23603F, dark: 0x8FCBA9))
        case .drums:
            return TrackPalette(body: .dynamic(light: 0xF6E0DC, dark: 0x37201E),
                                caption: .dynamic(light: 0xB5473A, dark: 0xA9473B),
                                content: .dynamic(light: 0x8E3328, dark: 0xF0A397))
        }
    }

    // MARK: Fonts (PostScript names of the bundled OFL fonts; system font is used if registration failed)

    static func serifItalic(_ size: CGFloat) -> Font { .custom("Spectral-Italic", size: size) }
    static func serifMediumItalic(_ size: CGFloat) -> Font { .custom("Spectral-MediumItalic", size: size) }
    static func serif(_ size: CGFloat) -> Font { .custom("Spectral-Regular", size: size) }
    static func ui(_ size: CGFloat) -> Font { .custom("Barlow-Regular", size: size) }
    static func uiMedium(_ size: CGFloat) -> Font { .custom("Barlow-Medium", size: size) }
    static func uiSemibold(_ size: CGFloat) -> Font { .custom("Barlow-SemiBold", size: size) }
    static func condensed(_ size: CGFloat) -> Font { .custom("BarlowCondensed-SemiBold", size: size) }
    static func condensedBold(_ size: CGFloat) -> Font { .custom("BarlowCondensed-Bold", size: size) }
}

enum FontRegistrar {
    /// Registers the bundled TTF files for this process. Failures are non-fatal; system fonts are used instead.
    @discardableResult
    static func registerAll() -> Int {
        var count = 0
        for url in ResourceLocator.urls(withExtension: "ttf") {
            var error: Unmanaged<CFError>? = nil
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                count += 1
            } else if let e = error?.takeRetainedValue() {
                // Already registered is fine; anything else falls back to the system font.
                let code = CFErrorGetCode(e)
                if code == 105 { count += 1 }
            }
        }
        return count
    }
}

/// A chord symbol with the extension raised and smaller, set in Barlow Condensed Bold.
struct ChordText: View {
    var chord: Chord
    var size: CGFloat = 18
    var color: Color = Theme.ink

    var body: some View {
        let p = chord.displayParts
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(p.root + p.main).font(Theme.condensedBold(size))
            if !p.ext.isEmpty {
                Text(p.ext)
                    .font(Theme.condensedBold(size * 0.62))
                    .baselineOffset(size * 0.38)
            }
            if let b = p.bass {
                Text("/" + b).font(Theme.condensedBold(size * 0.8))
            }
        }
        .foregroundColor(color)
        .lineLimit(1)
        .fixedSize()
    }
}
