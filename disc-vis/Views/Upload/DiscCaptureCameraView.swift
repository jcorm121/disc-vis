import AVFoundation
import SwiftUI

struct DiscGuideOverlay: View {
    let radiusFraction: CGFloat
    var isDetected = false

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height) * radiusFraction * 2
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                Circle()
                    .strokeBorder(
                        isDetected ? DiscTheme.yellow : Color.white.opacity(0.85),
                        lineWidth: isDetected ? 4 : 3
                    )
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .shadow(color: .black.opacity(0.25), radius: 8)
                    .animation(.smooth(duration: 0.25), value: isDetected)

                Circle()
                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [8, 8]))
                    .frame(width: diameter * 0.92, height: diameter * 0.92)
                    .position(center)
            }
        }
        .allowsHitTesting(false)
    }
}

struct DiscCaptureCameraView: View {
    @Environment(DiscStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onSavedToBag: () -> Void

    @StateObject private var captureSession = DiscCaptureSession()
    @State private var isSaving = false
    @State private var discName = ""
    @State private var reviewPreview: UIImage?

    var body: some View {
        ZStack {
            if captureSession.permissionDenied {
                permissionView
            } else if let captured = captureSession.capturedImage, let preview = reviewPreview {
                reviewView(image: captured, preview: preview)
            } else {
                liveCaptureView
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { captureSession.start() }
        .onDisappear { captureSession.stop() }
        .onChange(of: captureSession.capturedImage) { _, image in
            reviewPreview = image.map { DiscImageProcessor.cropToDiscSquare($0) }
        }
    }

    private var liveCaptureView: some View {
        ZStack {
            if captureSession.isRunning {
                CameraPreview(session: captureSession.session, videoGravity: .resizeAspect)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            DiscGuideOverlay(
                radiusFraction: DiscDetectionConfig.ringRadius,
                isDetected: captureSession.discDetected
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 20) {
                    Text("Align the edge of your disc with the circle")
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.45), in: Capsule())

                    captureButton
                }
                .padding(.bottom, 40)
            }
        }
    }

    private var captureButton: some View {
        Button {
            captureSession.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 4)
                    .frame(width: 78, height: 78)

                Circle()
                    .fill(captureSession.discDetected ? DiscTheme.yellow : Color.gray.opacity(0.55))
                    .frame(width: 64, height: 64)
            }
        }
        .buttonStyle(.plain)
        .disabled(!captureSession.discDetected)
        .animation(.smooth(duration: 0.25), value: captureSession.discDetected)
        .accessibilityLabel("Capture disc photo")
    }

    private func reviewView(image: UIImage, preview: UIImage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: preview)
                .resizable()
                .scaledToFit()
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(DiscTheme.yellow, lineWidth: 3)
                }
                .padding(.horizontal, 32)
                .shadow(color: .black.opacity(0.35), radius: 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("Name this disc:")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                TextField("Disc name", text: $discName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 24)

            HStack(spacing: 16) {
                Button("Retake") {
                    withAnimation(.smooth(duration: 0.25)) {
                        discName = ""
                        reviewPreview = nil
                        captureSession.clearCapture()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)

                Button {
                    usePhoto(image)
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Use Photo")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DiscTheme.accentGradient, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(isSaving || discName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(discName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("Camera Unavailable", systemImage: "camera.fill")
        } description: {
            Text("Allow camera access in Settings to photograph your disc.")
        }
        .foregroundStyle(.white)
    }

    private func usePhoto(_ image: UIImage) {
        let name = discName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isSaving = true
        do {
            _ = try store.addCapturedDisc(from: image, name: name)
            dismiss()
            onSavedToBag()
        } catch {
            isSaving = false
        }
    }
}

#Preview {
    DiscCaptureCameraView(onSavedToBag: {})
        .environment(DiscStore())
}
