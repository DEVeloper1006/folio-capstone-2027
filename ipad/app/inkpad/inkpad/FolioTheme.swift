import SwiftUI

enum FolioTheme {
    // MARK: - Paper & backgrounds (from tokens.css --bg, --panel, --canvas-bg)
    static let paper = Color(hex: 0xF4F2EC)
    static let panel = Color(hex: 0xECE8DE)
    static let panelSecondary = Color(hex: 0xE3DFD4)
    static let canvasGrid = Color(hex: 0xDED9CE)

    // MARK: - Ink (--ink)
    static let ink = Color(hex: 0x1C1C1A)

    // MARK: - Accent — AI-authored content only
    static let accent = Color(hex: 0x4E9A95)
    static let accentFill = Color(hex: 0x4E9A95).opacity(0.12)

    // MARK: - Text hierarchy (--muted, --dim)
    static let muted = Color(hex: 0x65625D)
    static let dim = Color(hex: 0x8D8981)

    // MARK: - Rules & dividers
    static let rule = Color(hex: 0xCBC6BA)
    static let ruleStrong = Color(hex: 0x98938A)
    static let ruleSubtle = Color(hex: 0xD8D3C8)

    // MARK: - Status colors (muted per spec)
    static let statusOK = Color(hex: 0x5A9E5A)
    static let statusWarn = Color(hex: 0xC7943A)
    static let statusError = Color(hex: 0xC45C4A)

    // MARK: - Shadow
    static let shadow = Color(hex: 0x1C1C1A).opacity(0.12)

    // MARK: - Chrome (floating UI)
    static let chromeBackground = Color.white
    static let chromeShadow = Color.black.opacity(0.08)

    // MARK: - Cover palette for Library notebook cards
    static let coverColors: [Color] = [
        Color(hex: 0xE8E4DA),
        Color(hex: 0xDAE0D8),
        Color(hex: 0xD8DDE4),
        Color(hex: 0xE4DAD8),
        Color(hex: 0xE0DCD4),
        Color(hex: 0xD4DCD8),
    ]

    // MARK: - Fonts
    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func ghostTypesetFont(size: CGFloat) -> Font {
        .system(size: size, design: .serif).italic()
    }

    static func handwritingFont(size: CGFloat) -> Font {
        .custom("Caveat", size: size)
    }

    // MARK: - Spacing
    static let gutterWidth: CGFloat = 52
    static let toolbarHeight: CGFloat = 44
    static let cornerRadius: CGFloat = 12
    static let pillRadius: CGFloat = 22
    static let dotSpacing: CGFloat = 28
    static let dotRadius: CGFloat = 1.2
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
