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
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = videoGravity
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.previewLayer.videoGravity = videoGravity
    }
}

@MainActor
final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false

    private let frameDelivery = FrameDelivery()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "discvis.scan.video", qos: .userInitiated)
    private let frameThrottler = ScanFrameThrottler()

    var frameHandler: (@Sendable (CVPixelBuffer) -> Void)? {
        get { frameDelivery.handler }
        set { frameDelivery.handler = newValue }
    }

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
        session.outputs.forEach { session.removeOutput($0) }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }

        session.commitConfiguration()

        await Task.detached { [session] in
            session.startRunning()
        }.value
        isRunning = true
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard frameThrottler.tryBegin() else { return }
        defer { frameThrottler.end() }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameDelivery.handler?(pixelBuffer)
    }
}

private final class FrameDelivery: @unchecked Sendable {
    var handler: (@Sendable (CVPixelBuffer) -> Void)?
}

private final class ScanFrameThrottler: @unchecked Sendable {
    private let lock = NSLock()
    private var isProcessing = false

    func tryBegin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isProcessing else { return false }
        isProcessing = true
        return true
    }

    func end() {
        lock.lock()
        isProcessing = false
        lock.unlock()
    }
}
