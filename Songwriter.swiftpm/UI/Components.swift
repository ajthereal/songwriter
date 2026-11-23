import SwiftUI

struct CircleToggle: View {
    var label: String
    var isOn: Bool
    var onColor: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.uiSemibold(12))
                .foregroundColor(isOn ? .white : Theme.ink2)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isOn ? onColor : Color.clear))
                .overlay(Circle().stroke(isOn ? onColor : Theme.line, lineWidth: 1.2))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ArmButton: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Theme.red, lineWidth: 1.6).frame(width: 24, height: 24)
                Circle().fill(Theme.red).frame(width: 12, height: 12).opacity(isOn ? 1 : 0.0)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record arm")
    }
}

struct PillButton: View {
    var title: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.uiMedium(14))
                .foregroundColor(isOn ? .white : Theme.ink)
                .padding(.horizontal, 14)
                .frame(minWidth: 56, minHeight: 34)
                .background(Capsule().fill(isOn ? Theme.red : Color.clear))
                .overlay(Capsule().stroke(isOn ? Theme.red : Theme.line, lineWidth: 1.2))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    var systemName: String
    var label: String
    var enabled: Bool = true
    var color: Color = Theme.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(enabled ? color : Theme.ink2.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

struct TextActionButton: View {
    var title: String
    var systemName: String? = nil
    var prominent: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let s = systemName { Image(systemName: s).font(.system(size: 14, weight: .medium)) }
                Text(title).font(Theme.uiMedium(15))
            }
            .foregroundColor(prominent ? .white : (enabled ? Theme.ink : Theme.ink2.opacity(0.5)))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(prominent ? Theme.red : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(prominent ? Theme.red : Theme.line, lineWidth: 1.2))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Serif italic section title used on sheets.
struct SheetHeader: View {
    var title: String
    var onClose: () -> Void

    var body: some View {
        HStack {
            Text(title).font(Theme.serifMediumItalic(24)).foregroundColor(Theme.ink)
            Spacer()
            Button("Done", action: onClose)
                .font(Theme.uiMedium(16))
                .foregroundColor(Theme.red)
                .frame(minWidth: 60, minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

struct SectionBadge: View {
    var letter: String
    var size: CGFloat = 20
    var color: Color = Theme.red

    var body: some View {
        Text(letter)
            .font(Theme.uiSemibold(size * 0.6))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 1.2))
    }
}

struct LevelMeter: View {
    @ObservedObject var meter: MeterModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.line)
                RoundedRectangle(cornerRadius: 2)
                    .fill(meter.level > 0.9 ? Theme.red : Color(red: 0.25, green: 0.62, blue: 0.4))
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, meter.level))))
            }
        }
        .frame(height: 4)
    }
}
