import SwiftUI
import UIKit

enum DiscTheme {
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.12)
    static let yellow = Color(red: 1.0, green: 0.78, blue: 0.18)

    static let cream = adaptive(
        light: Color(red: 1.0, green: 0.97, blue: 0.92),
        dark: Color(red: 0.14, green: 0.13, blue: 0.12)
    )

    static let backgroundBase = adaptive(
        light: .white,
        dark: Color(red: 0.08, green: 0.08, blue: 0.09)
    )

    static let surface = adaptive(
        light: Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.92),
        dark: Color(red: 0.18, green: 0.18, blue: 0.20, opacity: 0.92)
    )

    static let surfaceStroke = adaptive(
        light: yellow.opacity(0.5),
        dark: yellow.opacity(0.35)
    )

    static let cardRing = adaptive(
        light: Color.white.opacity(0.55),
        dark: Color.white.opacity(0.22)
    )

    static let shadow = adaptive(
        light: Color.black.opacity(0.12),
        dark: Color.black.opacity(0.45)
    )

    static let accentGradient = LinearGradient(
        colors: [orange, yellow],
        startPoint: .leading,
        endPoint: .trailing
    )

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [cream, backgroundBase, yellow.opacity(0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var bottomBarGradient: LinearGradient {
        LinearGradient(
            colors: [.clear, cream.opacity(0.95), backgroundBase],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
