import SwiftUI

enum DiscTheme {
    static let orange = Color(red: 1.0, green: 0.42, blue: 0.12)
    static let yellow = Color(red: 1.0, green: 0.78, blue: 0.18)
    static let cream = Color(red: 1.0, green: 0.97, blue: 0.92)

    static let backgroundGradient = LinearGradient(
        colors: [cream, .white, yellow.opacity(0.14)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [orange, yellow],
        startPoint: .leading,
        endPoint: .trailing
    )
}
