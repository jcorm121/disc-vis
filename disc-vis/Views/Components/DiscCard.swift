import SwiftUI

struct DiscCard: View {
    let name: String
    let primaryColor: Color
    let secondaryColor: Color
    var isSelected = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [primaryColor, secondaryColor.opacity(0.85)],
                            center: .center,
                            startRadius: 4,
                            endRadius: 44
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                    }
                    .shadow(color: primaryColor.opacity(0.35), radius: isSelected ? 10 : 4, y: 3)

                Circle()
                    .strokeBorder(DiscTheme.yellow.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 52, height: 52)
            }
            .scaleEffect(isSelected ? 1.05 : 1)

            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary.opacity(0.85))
        }
        .padding(.vertical, 8)
        .animation(.smooth(duration: 0.25), value: isSelected)
    }
}
