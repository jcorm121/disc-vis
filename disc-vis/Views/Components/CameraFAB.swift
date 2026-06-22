import SwiftUI

struct CameraFAB: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(DiscTheme.accentGradient)
                    .frame(width: 64, height: 64)
                    .shadow(color: DiscTheme.orange.opacity(0.4), radius: isPressed ? 6 : 14, y: isPressed ? 2 : 6)

                Image(systemName: "camera.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isPressed)
            }
            .scaleEffect(isPressed ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open camera")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.smooth(duration: 0.15)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.smooth(duration: 0.2)) { isPressed = false }
                }
        )
    }
}
