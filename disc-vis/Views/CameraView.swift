import SwiftUI

struct MatchOverlay: View {
    @State private var pulse = false

    private let regions: [CGRect] = [
        CGRect(x: 0.18, y: 0.32, width: 0.22, height: 0.18),
        CGRect(x: 0.58, y: 0.48, width: 0.16, height: 0.14),
        CGRect(x: 0.34, y: 0.62, width: 0.2, height: 0.16),
    ]

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(regions.enumerated()), id: \.offset) { index, region in
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DiscTheme.yellow.opacity(pulse ? 0.95 : 0.55), lineWidth: 2)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DiscTheme.orange.opacity(pulse ? 0.22 : 0.12))
                    }
                    .frame(
                        width: region.width * geometry.size.width,
                        height: region.height * geometry.size.height
                    )
                    .position(
                        x: (region.minX + region.width / 2) * geometry.size.width,
                        y: (region.minY + region.height / 2) * geometry.size.height
                    )
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(Double(index) * 0.2),
                        value: pulse
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear { pulse = true }
    }
}

struct CameraView: View {
    @Environment(DiscStore.self) private var store
    let onExit: () -> Void

    @StateObject private var cameraSession = CameraSession()

    var body: some View {
        ZStack {
            if cameraSession.permissionDenied {
                cameraUnavailable
            } else if cameraSession.isRunning {
                CameraPreview(session: cameraSession.session)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
            }

            MatchOverlay()
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onExit) {
                        Label("Back", systemImage: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Exit camera")

                    Spacer()

                    if let reference = store.selectedReference {
                        Text(reference.name)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                Text("Scanning for color & texture matches")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, 36)
            }
        }
        .onAppear { cameraSession.start() }
        .onDisappear { cameraSession.stop() }
        .transition(.opacity.combined(with: .scale(scale: 1.02)))
    }

    private var cameraUnavailable: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ContentUnavailableView {
                Label("Camera Unavailable", systemImage: "camera.fill")
            } description: {
                Text("Allow camera access in Settings to scan for discs.")
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    CameraView(onExit: {})
        .environment(DiscStore())
}
