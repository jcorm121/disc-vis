import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class DiscCaptureSession: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var discDetected = false
    @Published private(set) var capturedImage: UIImage?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let detector = DiscRingDetector()
    private let analysisQueue = DispatchQueue(label: "discvis.capture.analysis", qos: .userInitiated)
    private let analysisThrottler = FrameAnalysisThrottler()

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
        discDetected = false
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func clearCapture() {
        capturedImage = nil
    }

    private func configureAndStart() async {
        session.beginConfiguration()
        session.sessionPreset = .photo

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
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
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

/// Drops frames while analysis is in flight so the delegate stays ahead of real time.
private final class FrameAnalysisThrottler: @unchecked Sendable {
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

extension DiscCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard analysisThrottler.tryBegin() else { return }

        let detected = detector.analyze(pixelBuffer: pixelBuffer)
        analysisThrottler.end()

        Task { @MainActor in
            discDetected = detected
        }
    }
}

extension DiscCaptureSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            return
        }
        Task { @MainActor in
            capturedImage = image
        }
    }
}
