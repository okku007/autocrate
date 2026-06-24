import SwiftUI

/// Minimalist stealth theme tokens. Near-black, monospace, one restrained accent.
public enum Theme {
    public static let bg            = Color(hex: 0x0B0B0C)
    public static let surface       = Color(hex: 0x141416)
    public static let border        = Color.white.opacity(0.06)
    public static let textPrimary   = Color(hex: 0xE8E8E6)
    public static let textSecondary = Color(hex: 0x8A8A85)
    public static let accent        = Color(hex: 0x6EA8FE) // single restrained accent

    public static let rowSpacing: CGFloat = 6
    public static let panelPadding: CGFloat = 12
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
}
