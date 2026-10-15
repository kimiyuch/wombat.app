import SwiftUI
import AppKit
import CoreText

// The look of wombat.kimiyu.ch: the burrow indigo of the icon, Figtree headings, white cards with a thin ring.
// Dark mode follows the website's dark Cleanup section (burrow-950 with white/5 cards).

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }

    /// A colour that switches with the window's appearance.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

enum Burrow {
    static let c50 = Color(hex: 0xf4f4fa)
    static let c100 = Color(hex: 0xe8e7f4)
    static let c200 = Color(hex: 0xd0cee8)
    static let c300 = Color(hex: 0xaeaad6)
    static let c400 = Color(hex: 0x8a84be)
    static let c500 = Color(hex: 0x6d66a8)
    static let c600 = Color(hex: 0x58518f)
    static let c700 = Color(hex: 0x484276)
    static let c800 = Color(hex: 0x3b3661)
    static let c900 = Color(hex: 0x2e2b4c)
    static let c950 = Color(hex: 0x1d1b31)
}

enum Theme {
    static let pageTop = Color.adaptive(light: Burrow.c50, dark: Color(hex: 0x15142a))
    static let page = Color.adaptive(light: .white, dark: Color(hex: 0x121124))
    static let card = Color.adaptive(light: .white, dark: .white.opacity(0.05))
    static let ring = Color.adaptive(light: Burrow.c950.opacity(0.1), dark: .white.opacity(0.1))
    static let divider = Color.adaptive(light: Color(hex: 0x0a0a0a, opacity: 0.05), dark: .white.opacity(0.08))

    /// Headings and figures.
    static let ink = Color.adaptive(light: Burrow.c950, dark: .white)
    static let text = Color.adaptive(light: Color(hex: 0x262626), dark: Burrow.c50)
    static let muted = Color.adaptive(light: Color(hex: 0x737373), dark: Burrow.c100.opacity(0.7))

    static let accent = Color.adaptive(light: Burrow.c600, dark: Burrow.c400)
    static let link = Color.adaptive(light: Burrow.c700, dark: Burrow.c300)
    static let green = Color.adaptive(light: Color(hex: 0x16a34a), dark: Color(hex: 0x4ade80))
    static let orange = Color.adaptive(light: Color(hex: 0xf97316), dark: Color(hex: 0xfdba74))
    static let red = Color.adaptive(light: Color(hex: 0xdc2626), dark: Color(hex: 0xf87171))

    static let free = Color.adaptive(light: Color(hex: 0xe5e5e5), dark: .white.opacity(0.1))

    static let background = LinearGradient(colors: [pageTop, page], startPoint: .top, endPoint: .bottom)

    static let cornerRadius: CGFloat = 10
}

// MARK: - Figtree

extension Font {
    /// Figtree, the website's display face, for headings and figures. Falls back to the system font.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name = weight == .medium ? "FigtreeLight-Medium" : "FigtreeLight-SemiBold"
        return Fonts.registered ? .custom(name, size: size) : .system(size: size, weight: weight)
    }
}

enum Fonts {
    /// Registers the Figtree files in Contents/Resources/Fonts for this process.
    static let registered: Bool = {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "woff2", subdirectory: "Fonts"), !urls.isEmpty else {
            return false
        }
        return urls.allSatisfy { CTFontManagerRegisterFontsForURL($0 as CFURL, .process, nil) }
    }()
}

// MARK: - Surfaces and buttons

extension View {
    /// A white card with a thin ring, like the panels on the website.
    func cardSurface(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.ring))
    }
}

/// The website's rounded-full buttons: filled burrow for the main action, white with a ring otherwise.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = Burrow.c600
    var foreground: Color = .white
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, large ? 18 : 11)
            .padding(.vertical, large ? 9 : 4)
            .foregroundStyle(prominent ? foreground : Theme.link)
            .background(Capsule().fill(prominent ? tint : Theme.card))
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Theme.ring))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillProminent: PillButtonStyle { PillButtonStyle(prominent: true) }
    static var pillDestructive: PillButtonStyle { PillButtonStyle(prominent: true, tint: Color(hex: 0xdc2626)) }
}
