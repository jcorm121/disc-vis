import Foundation
import simd
import UIKit

/// Cached target-side statistics and color signatures from a reference disc image.
///
/// Target k-means runs once in unweighted Lab (see plan note: scene-dependent axis weights
/// are applied at distance time on the GPU).
struct ReferenceSignatureModel: Sendable {
    let targetMean: SIMD3<Float>
    let targetStd: SIMD3<Float>
    let targetSignatures: [SIMD3<Float>]

    static func build(from image: UIImage) -> ReferenceSignatureModel? {
        guard let pixels = ReferenceImageSampler.maskedLabPixels(
            from: image,
            radiusFraction: HeatmapConfig.objectRadiusFraction
        ), !pixels.isEmpty else {
            return nil
        }

        let mean = meanVector(pixels)
        let std = stdVector(pixels, mean: mean)

        // Initial axis weights from reference-only stats (scene updated per frame).
        let fallbackWeights = SIMD3<Float>(repeating: 1.0)
        let weightedPixels = pixels.map { LabColorSpace.applyAxisWeights(
            LabColorSpace.Lab(L: $0.x, a: $0.y, b: $0.z),
            weights: fallbackWeights
        ) }

        let meanSignature = mean
        let dominant = KMeansLab.cluster(
            pixels: weightedPixels,
            count: HeatmapConfig.targetDominantColorCount
        )
        let mergedWeighted = KMeansLab.mergeSignatures([meanSignature] + dominant)
        let signatures = mergedWeighted.map { weighted -> SIMD3<Float> in
            LabColorSpace.removeAxisWeights(weighted, weights: fallbackWeights).vector
        }

        return ReferenceSignatureModel(
            targetMean: mean,
            targetStd: std,
            targetSignatures: signatures
        )
    }

    private static func meanVector(_ pixels: [SIMD3<Float>]) -> SIMD3<Float> {
        var total = SIMD3<Float>(repeating: 0)
        for pixel in pixels {
            total += pixel
        }
        return total / Float(pixels.count)
    }

    private static func stdVector(_ pixels: [SIMD3<Float>], mean: SIMD3<Float>) -> SIMD3<Float> {
        var variance = SIMD3<Float>(repeating: 0)
        for pixel in pixels {
            let delta = pixel - mean
            variance += delta * delta
        }
        variance /= Float(pixels.count)
        return SIMD3(sqrt(variance.x), sqrt(variance.y), sqrt(variance.z))
    }
}

enum ReferenceImageSampler {
    static func maskedLabPixels(from image: UIImage, radiusFraction: Float) -> [SIMD3<Float>]? {
        guard let cgImage = image.normalizedCGImage() else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let centerX = Float(width) / 2
        let centerY = Float(height) / 2
        let radius = radiusFraction * Float(min(width, height)) / 2
        let radiusSquared = radius * radius

        var pixels: [SIMD3<Float>] = []
        pixels.reserveCapacity(Int(radiusSquared * .pi))

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                if dx * dx + dy * dy > radiusSquared { continue }

                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(data[offset]) / 255.0
                let g = Float(data[offset + 1]) / 255.0
                let b = Float(data[offset + 2]) / 255.0
                pixels.append(LabColorSpace.fromSRGB(SIMD3(r, g, b)).vector)
            }
        }

        return pixels
    }
}

private extension UIImage {
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}
