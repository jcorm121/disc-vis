import CoreGraphics
import UIKit

enum DiscImageProcessor {
    static let outputSize = DiscImageStore.cropSize

    /// Crops the center disc region and resizes to 675×675.
    /// Uses the same normalized radius as the on-screen guide overlay.
    static func cropToDiscSquare(_ image: UIImage, radiusFraction: CGFloat = DiscDetectionConfig.ringRadius) -> UIImage {
        let oriented = image.normalizedOrientation()
        guard let cgImage = oriented.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let minSide = min(width, height)
        let cropSide = minSide * radiusFraction * 2
        let originX = (width - cropSide) / 2
        let originY = (height - cropSide) / 2
        let cropRect = CGRect(x: originX, y: originY, width: cropSide, height: cropSide).integral

        guard let cropped = cgImage.cropping(to: cropRect) else { return oriented }

        let size = CGSize(width: outputSize, height: outputSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
