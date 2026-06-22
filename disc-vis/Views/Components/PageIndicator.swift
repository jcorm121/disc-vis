import SwiftUI

struct PageIndicator: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selection ? DiscTheme.orange : DiscTheme.yellow.opacity(0.45))
                    .frame(width: index == selection ? 22 : 7, height: 7)
                    .animation(.smooth(duration: 0.3), value: selection)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(selection + 1) of \(count)")
    }
}
