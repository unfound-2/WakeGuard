import Combine
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }
}

struct WakeGuardPalette {
    let background: Color
    let surface: Color
    let elevatedSurface: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let text: Color
    let secondaryText: Color
    let mutedText: Color
    let divider: Color
    let success: Color
    let warning: Color
    let danger: Color

    static let dark = WakeGuardPalette(
        background: Color(hex: 0x0D1115),
        surface: Color(hex: 0x182026),
        elevatedSurface: Color(hex: 0x222C33),
        primary: Color(hex: 0xBF5700),
        secondary: Color(hex: 0x333F48),
        tertiary: Color(hex: 0xFFFFFF),
        text: Color(hex: 0xFFFFFF),
        secondaryText: Color(hex: 0xD8DEE3),
        mutedText: Color(hex: 0xA7B0B8),
        divider: Color.white.opacity(0.10),
        success: Color(hex: 0x34C759),
        warning: Color(hex: 0xFFCC00),
        danger: Color(hex: 0xFF453A)
    )

    static let light = WakeGuardPalette(
        background: Color(hex: 0xF4F6F8),
        surface: Color(hex: 0xFFFFFF),
        elevatedSurface: Color(hex: 0xFFFFFF),
        primary: Color(hex: 0xFFFFFF),
        secondary: Color(hex: 0xBF5700),
        tertiary: Color(hex: 0x333F48),
        text: Color(hex: 0x333F48),
        secondaryText: Color(hex: 0x4B5963),
        mutedText: Color(hex: 0x6F7B84),
        divider: Color.black.opacity(0.08),
        success: Color(hex: 0x248A3D),
        warning: Color(hex: 0xB98200),
        danger: Color(hex: 0xD70015)
    )
}

final class ThemeManager: ObservableObject {
    private let storageKey = "wakeguard.appearanceMode"
    private let defaults: UserDefaults

    @Published var mode: AppearanceMode {
        didSet {
            defaults.set(mode.rawValue, forKey: storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: storageKey),
           let savedMode = AppearanceMode(rawValue: rawValue) {
            mode = savedMode
        } else {
            mode = .dark
        }
    }

    var palette: WakeGuardPalette {
        switch mode {
        case .dark: .dark
        case .light: .light
        }
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
