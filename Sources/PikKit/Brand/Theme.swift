import AppKit
import SwiftUI

public enum Theme {
    public static let accent = Color(red: 1.0, green: 0.478, blue: 0.102)
    public static let accentDeep = Color(red: 0.86, green: 0.33, blue: 0.05)
    public static let rec = Color(red: 1.0, green: 0.23, blue: 0.19)
    public static let ink = Color(red: 0.13, green: 0.09, blue: 0.20)
    public static let barBackground = Color(red: 0.11, green: 0.10, blue: 0.15)
    public static let barStroke = Color.white.opacity(0.10)
    public static let panelBackground = Color(red: 0.14, green: 0.13, blue: 0.19)
    public static let cream = Color(red: 1, green: 0.96, blue: 0.90)

    public static let nsAccent = NSColor(srgbRed: 1.0, green: 0.478, blue: 0.102, alpha: 1)
    public static let nsRec = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1)

    public static func color(hex: String) -> Color {
        Color(nsColor: nsColor(hex: hex))
    }

    public static func nsColor(hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nsAccent }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    public static func hex(of color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Botón primario naranja.
public struct PikPrimaryButtonStyle: ButtonStyle {
    public var recording = false
    public init(recording: Bool = false) { self.recording = recording }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(
                Capsule().fill(recording ? Theme.rec : Theme.accent)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .contentShape(Capsule())
    }
}

public struct PikSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09)))
            .contentShape(Rectangle())
    }
}

/// Botón de ícono redondo para las barras flotantes oscuras.
public struct PillIconButtonStyle: ButtonStyle {
    public var selected = false
    public var size: CGFloat = 36
    public var tint: Color = .white
    public init(selected: Bool = false, size: CGFloat = 36, tint: Color = .white) {
        self.selected = selected; self.size = size; self.tint = tint
    }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint.opacity(selected ? 1 : 0.78))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(selected ? 0.20 : (configuration.isPressed ? 0.14 : 0.0))))
            .contentShape(Circle())
    }
}
