import AppKit
import SwiftUI

enum LogbookStyle {
    static let accentHex = NSColor(hex: 0x0169CC)
    static let darkBackgroundHex = NSColor(hex: 0x111111)
    static let darkCardHex = NSColor(hex: 0x171717)
    static let darkRaisedHex = NSColor(hex: 0x1B1B1B)
    static let darkBorderHex = NSColor(hex: 0x2A2A2A)
    static let darkForegroundHex = NSColor(hex: 0xFCFCFC)
    static let darkMutedHex = NSColor(hex: 0xA7A7A7)

    static let lightBackgroundHex = NSColor(hex: 0xF5F5F7)
    static let lightCardHex = NSColor(hex: 0xFFFFFF)
    static let lightRaisedHex = NSColor(hex: 0xFAFAFB)
    static let lightBorderHex = NSColor(hex: 0xDFDFE3)
    static let lightForegroundHex = NSColor(hex: 0x121212)
    static let lightMutedHex = NSColor(hex: 0x6F6F76)

    static var canvasTop: Color { isDarkMode ? Color(nsColor: darkBackgroundHex) : Color(nsColor: lightBackgroundHex) }
    static var canvasBottom: Color { isDarkMode ? Color(nsColor: darkBackgroundHex) : Color(nsColor: lightBackgroundHex) }

    static var cardFill: Color { isDarkMode ? Color(nsColor: darkCardHex) : Color(nsColor: lightCardHex) }
    static var secondaryCardFill: Color { isDarkMode ? Color(nsColor: darkRaisedHex) : Color(nsColor: lightRaisedHex) }
    static var cardStroke: Color { isDarkMode ? Color(nsColor: darkBorderHex) : Color(nsColor: lightBorderHex) }

    static let accent = Color(nsColor: accentHex)
    static var text: Color { isDarkMode ? Color(nsColor: darkForegroundHex) : Color(nsColor: lightForegroundHex) }
    static var subtleText: Color { isDarkMode ? Color(nsColor: darkMutedHex) : Color(nsColor: lightMutedHex) }
    static var inlineCodeFill: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x202020)) : Color(nsColor: NSColor(hex: 0xF1F2F4)) }
    static var inlineCodeStroke: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x323232)) : Color(nsColor: NSColor(hex: 0xD8DADF)) }
    static var inlineCodeText: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0xF5F5F5)) : Color(nsColor: NSColor(hex: 0x1A1A1A)) }
    static var inputFill: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x171717)) : Color(nsColor: NSColor(hex: 0xFFFFFF)) }
    static var inputFocusedFill: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x1B1B1B)) : Color(nsColor: NSColor(hex: 0xFFFFFF)) }
    static var inputText: Color { text }
    static var inputPlaceholder: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x7D7D82)) : Color(nsColor: NSColor(hex: 0x8B8E96)) }
    static var badgeFill: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x1F1F1F)) : Color(nsColor: NSColor(hex: 0xF2F3F5)) }
    static var badgeStroke: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x303030)) : Color(nsColor: NSColor(hex: 0xD9DCE2)) }
    static var badgeText: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0xD2D2D2)) : Color(nsColor: NSColor(hex: 0x5B5E66)) }
    static let badgeBlueFill = Color(nsColor: accentHex).opacity(0.14)
    static let badgeBlueStroke = Color(nsColor: accentHex).opacity(0.22)
    static var badgeBlueText: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x52A8FF)) : Color(nsColor: NSColor(hex: 0x0F5EAE)) }
    static var badgeWarmFill: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x2A2217)) : Color(nsColor: NSColor(hex: 0xFFF1D6)) }
    static var badgeWarmStroke: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x5C4320)) : Color(nsColor: NSColor(hex: 0xE7C98B)) }
    static var badgeWarmText: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0xF4C15D)) : Color(nsColor: NSColor(hex: 0x8A5A12)) }
    static var badgeGreenFill: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x16261C)) : Color(nsColor: NSColor(hex: 0xDDF4E6)) }
    static var badgeGreenStroke: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x295739)) : Color(nsColor: NSColor(hex: 0x8FD3A8)) }
    static var badgeGreenText: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x4AD66D)) : Color(nsColor: NSColor(hex: 0x1E7A3F)) }

    static var warning: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0xFF8A5B)) : Color(nsColor: NSColor(hex: 0xB24A2D)) }
    static var success: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x4AD66D)) : Color(nsColor: NSColor(hex: 0x1E7A3F)) }
    static var caution: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0xF4C15D)) : Color(nsColor: NSColor(hex: 0x8A5A12)) }

    static var phaseFocus: Color { badgeBlueText }
    static var phaseSupport: Color { badgeWarmText.opacity(0.96) }
    static var phasePause: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x5A5A5A)) : Color(nsColor: NSColor(hex: 0xB3B6BE)) }
    static var phaseNeutral: Color { isDarkMode ? Color(nsColor: NSColor(hex: 0x414141)) : Color(nsColor: NSColor(hex: 0xC8CAD0)) }

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func codeFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static var isDarkMode: Bool { true }
}

private extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
