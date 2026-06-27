import Foundation
import simd

/// CIELAB utilities matching ``DiscHeatmap.metal`` (L* ∈ [0, 100], a*/b* centered at 0).
enum LabColorSpace {
    struct Lab: Sendable {
        var L: Float
        var a: Float
        var b: Float

        var vector: SIMD3<Float> { SIMD3(L, a, b) }
    }

    static func fromSRGB(_ rgb: SIMD3<Float>) -> Lab {
        let linear = srgbToLinear(rgb)
        let x = linear.x * 0.4124564 + linear.y * 0.3575761 + linear.z * 0.1804375
        let y = linear.x * 0.2126729 + linear.y * 0.7151522 + linear.z * 0.0721750
        let z = linear.x * 0.0193339 + linear.y * 0.1191920 + linear.z * 0.9503041

        let xn: Float = 0.95047
        let yn: Float = 1.0
        let zn: Float = 1.08883

        func f(_ t: Float) -> Float {
            let delta: Float = 6.0 / 29.0
            return t > 0.008856 ? pow(t, 1.0 / 3.0) : (t / (3 * delta * delta) + 4.0 / 29.0)
        }

        let fx = f(x / xn)
        let fy = f(y / yn)
        let fz = f(z / zn)

        return Lab(
            L: 116.0 * fy - 16.0,
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    static func applyAxisWeights(_ lab: Lab, weights: SIMD3<Float>) -> SIMD3<Float> {
        lab.vector / weights
    }

    static func removeAxisWeights(_ weighted: SIMD3<Float>, weights: SIMD3<Float>) -> Lab {
        let raw = weighted * weights
        return Lab(L: raw.x, a: raw.y, b: raw.z)
    }

    static func deltaE(_ lhs: Lab, _ rhs: Lab, weights: SIMD3<Float>) -> Float {
        let a = applyAxisWeights(lhs, weights: weights)
        let b = applyAxisWeights(rhs, weights: weights)
        return simd_length(a - b)
    }

    static func deltaE(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
        simd_length(lhs - rhs)
    }

    /// Removes background signatures that are too close to any target in unweighted Lab space.
    static func decontaminateBackgroundSignatures(
        _ background: [SIMD3<Float>],
        targetSignatures: [SIMD3<Float>],
        exclusionDeltaE: Float = HeatmapConfig.backgroundExclusionDeltaE
    ) -> [SIMD3<Float>] {
        guard !targetSignatures.isEmpty else { return background }
        return background.filter { backgroundSignature in
            let nearestTargetDistance = targetSignatures
                .map { deltaE(backgroundSignature, $0) }
                .min() ?? .infinity
            return nearestTargetDistance >= exclusionDeltaE
        }
    }

    private static func srgbToLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            channelSrgbToLinear(c.x),
            channelSrgbToLinear(c.y),
            channelSrgbToLinear(c.z)
        )
    }

    private static func channelSrgbToLinear(_ c: Float) -> Float {
        c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
    }
}
