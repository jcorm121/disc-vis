import SwiftUI

struct DiscSelectScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DiscTheme.orange)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                content()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 120)
        }
        .background(DiscTheme.backgroundGradient.ignoresSafeArea())
    }
}
