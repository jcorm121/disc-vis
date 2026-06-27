import SwiftUI

struct CameraView: View {
    @Environment(DiscStore.self) private var store
    let onExit: () -> Void

    @StateObject private var cameraSession = CameraSession()
    @State private var heatmapEngine: LabHeatmapEngine? = LabHeatmapEngine()
    @State private var palette: HeatmapPalette = .whiteHot
    @State private var overlayOpacity = Double(HeatmapConfig.defaultOverlayOpacity)
    @State private var useProbabilityThreshold = HeatmapConfig.defaultUseProbabilityThreshold
    @State private var probabilityThreshold = Double(HeatmapConfig.defaultProbabilityThreshold)

    private var hasReference: Bool {
        store.selectedReference != nil
    }

    var body: some View {
        ZStack {
            if cameraSession.permissionDenied {
                cameraUnavailable
            } else if heatmapEngine == nil {
                ContentUnavailableView {
                    Label("Metal Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("This device cannot run the heatmap pipeline.")
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
            } else if cameraSession.isRunning, let heatmapEngine {
                HeatmapMetalView(engine: heatmapEngine)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
            }

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

                VStack(spacing: 12) {
                    if !hasReference {
                        Text("Select a disc reference to enable heatmap")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.35), in: Capsule())
                    }

                    if hasReference {
                        heatmapControls
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            loadReference()
            wireFrameHandler()
            cameraSession.start()
        }
        .onDisappear {
            cameraSession.frameHandler = nil
            cameraSession.stop()
        }
        .onChange(of: store.selectedReference?.id) { _, _ in
            loadReference()
        }
        .onChange(of: palette) { _, newValue in
            heatmapEngine?.palette = newValue
        }
        .onChange(of: overlayOpacity) { _, newValue in
            heatmapEngine?.overlayOpacity = Float(newValue)
        }
        .onChange(of: useProbabilityThreshold) { _, newValue in
            heatmapEngine?.useProbabilityThreshold = newValue
        }
        .onChange(of: probabilityThreshold) { _, newValue in
            heatmapEngine?.probabilityThreshold = Float(newValue)
        }
        .transition(.opacity.combined(with: .scale(scale: 1.02)))
    }

    private var heatmapControls: some View {
        VStack(spacing: 10) {
            Picker("Palette", selection: $palette) {
                ForEach(HeatmapPalette.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Overlay")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Slider(value: $overlayOpacity, in: 0.5...1.0)
                    .tint(DiscTheme.yellow)
            }

            Toggle(isOn: $useProbabilityThreshold) {
                Text("Threshold overlay")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .tint(DiscTheme.yellow)

            if useProbabilityThreshold {
                HStack {
                    Text("Threshold")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Slider(value: $probabilityThreshold, in: 0...1)
                        .tint(DiscTheme.yellow)
                    Text("\(Int((probabilityThreshold * 255).rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
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

    private func loadReference() {
        guard let engine = heatmapEngine else { return }
        guard
            let reference = store.selectedReference,
            let image = store.image(for: reference),
            let model = ReferenceSignatureModel.build(from: image)
        else {
            engine.setReference(nil)
            return
        }
        engine.setReference(model)
        engine.palette = palette
        engine.overlayOpacity = Float(overlayOpacity)
        engine.useProbabilityThreshold = useProbabilityThreshold
        engine.probabilityThreshold = Float(probabilityThreshold)
    }

    private func wireFrameHandler() {
        guard let engine = heatmapEngine else { return }
        cameraSession.frameHandler = { pixelBuffer in
            engine.processFrame(pixelBuffer)
        }
    }
}

#Preview {
    CameraView(onExit: {})
        .environment(DiscStore())
}
