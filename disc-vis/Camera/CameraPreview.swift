import AVFoundation
import SwiftUI
import Combine

struct CameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

@MainActor
final class CameraSession: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false

    func start() {
        Task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                await configureAndStart()
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    await configureAndStart()
                } else {
                    permissionDenied = true
                }
            default:
                permissionDenied = true
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    private func configureAndStart() async {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.inputs.forEach { session.removeInput($0) }
        session.addInput(input)
        session.commitConfiguration()

        await Task.detached { [session] in
            session.startRunning()
        }.value
        isRunning = true
    }
}
