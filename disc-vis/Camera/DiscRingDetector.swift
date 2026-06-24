import CoreGraphics
import CoreVideo

/// Tunable parameters for the inner/outer intensity ring detector.
enum DiscDetectionConfig {
    /// Normalized radius R of the guide circle (relative to min image dimension).
    static let ringRadius: CGFloat = 0.38
    /// Ring offset δ — inner ring at R−δ, outer ring at R+δ (normalized).
    static let delta: CGFloat = 0.02
    /// Minimum |avg_inner − avg_outer| on a 0–255 scale to detect an edge.
    static let contrastThreshold: CGFloat = 12
    /// Number of angular samples per ring.
    static let sampleCount = 120
}

struct DiscRingDetector: Sendable {
    private let innerPoints: [CGPoint]
    private let outerPoints: [CGPoint]
    private let contrastThreshold: CGFloat

    init(
        radius: CGFloat = DiscDetectionConfig.ringRadius,
        delta: CGFloat = DiscDetectionConfig.delta,
        sampleCount: Int = DiscDetectionConfig.sampleCount,
        contrastThreshold: CGFloat = DiscDetectionConfig.contrastThreshold
    ) {
        self.contrastThreshold = contrastThreshold
        let center = CGPoint(x: 0.5, y: 0.5)
        innerPoints = Self.ringPoints(
            center: center,
            radius: radius - delta,
            count: sampleCount
        )
        outerPoints = Self.ringPoints(
            center: center,
            radius: radius + delta,
            count: sampleCount
        )
    }

    func analyze(pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let minDimension = min(width, height)

        let innerAverage = averageIntensity(
            for: innerPoints,
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow,
            width: width,
            height: height,
            minDimension: minDimension
        )
        let outerAverage = averageIntensity(
            for: outerPoints,
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow,
            width: width,
            height: height,
            minDimension: minDimension
        )

        return abs(innerAverage - outerAverage) >= contrastThreshold
    }

    private static func ringPoints(center: CGPoint, radius: CGFloat, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let angle = (CGFloat(index) / CGFloat(count)) * 2 * .pi
            return CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }

    private func averageIntensity(
        for normalizedPoints: [CGPoint],
        baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        width: Int,
        height: Int,
        minDimension: Int
    ) -> CGFloat {
        guard !normalizedPoints.isEmpty else { return 0 }

        var total: CGFloat = 0
        var count: CGFloat = 0
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)

        for point in normalizedPoints {
            let x = Int((point.x * CGFloat(minDimension) + CGFloat(width - minDimension) / 2).rounded())
            let y = Int((point.y * CGFloat(minDimension) + CGFloat(height - minDimension) / 2).rounded())
            guard x >= 0, x < width, y >= 0, y < height else { continue }

            let offset = y * bytesPerRow + x * 4
            let blue = CGFloat(pointer[offset])
            let green = CGFloat(pointer[offset + 1])
            let red = CGFloat(pointer[offset + 2])
            total += 0.299 * red + 0.587 * green + 0.114 * blue
            count += 1
        }

        return count > 0 ? total / count : 0
    }
}
