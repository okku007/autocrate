import SwiftUI

/// Locked fonts: JetBrains Mono for all readable UI/data; Geist Pixel Square for big numerals only.
public enum Fonts {
    public static let mono    = "JetBrains Mono"
    public static let display = "Geist Pixel Square"

    public static func body(_ size: CGFloat) -> Font { .custom(mono, size: size) }
    public static func numerals(_ size: CGFloat) -> Font { .custom(display, size: size) }
}
