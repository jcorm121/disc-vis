import Foundation
import simd

enum KMeansLab {
    static func cluster(
        pixels: [SIMD3<Float>],
        count: Int,
        maxIterations: Int = 20
    ) -> [SIMD3<Float>] {
        guard !pixels.isEmpty else { return [] }
        let k = max(1, min(count, pixels.count))
        if k == 1 {
            return [mean(pixels)]
        }

        var centers = kMeansPlusPlusInit(pixels: pixels, k: k)
        var assignments = [Int](repeating: 0, count: pixels.count)

        for _ in 0..<maxIterations {
            var changed = false
            for index in pixels.indices {
                let nearest = nearestCenter(pixels[index], centers: centers)
                if assignments[index] != nearest {
                    assignments[index] = nearest
                    changed = true
                }
            }
            if !changed { break }

            var grouped = Array(repeating: [SIMD3<Float>](), count: k)
            for (pixel, cluster) in zip(pixels, assignments) {
                grouped[cluster].append(pixel)
            }

            for clusterIndex in 0..<k {
                if grouped[clusterIndex].isEmpty {
                    centers[clusterIndex] = pixels.randomElement() ?? centers[clusterIndex]
                } else {
                    centers[clusterIndex] = mean(grouped[clusterIndex])
                }
            }
        }

        return centers
    }

    static func mergeSignatures(
        _ signatures: [SIMD3<Float>],
        mergeDeltaE: Float = HeatmapConfig.signatureMergeDeltaE
    ) -> [SIMD3<Float>] {
        var merged: [SIMD3<Float>] = []
        for signature in signatures {
            if merged.isEmpty {
                merged.append(signature)
                continue
            }
            let minDistance = merged.map { LabColorSpace.deltaE(signature, $0) }.min() ?? .infinity
            if minDistance > mergeDeltaE {
                merged.append(signature)
            }
        }
        return merged
    }

    static func subsample(_ pixels: [SIMD3<Float>], count: Int, seed: UInt64 = 0) -> [SIMD3<Float>] {
        guard pixels.count > count else { return pixels }
        var generator = SeededRNG(seed: seed)
        var indices = Array(0..<pixels.count)
        for index in 0..<count {
            let swapIndex = index + Int(generator.next() % UInt64(pixels.count - index))
            indices.swapAt(index, swapIndex)
        }
        return indices.prefix(count).map { pixels[$0] }
    }

    private static func mean(_ pixels: [SIMD3<Float>]) -> SIMD3<Float> {
        var total = SIMD3<Float>(repeating: 0)
        for pixel in pixels {
            total += pixel
        }
        return total / Float(pixels.count)
    }

    private static func nearestCenter(_ pixel: SIMD3<Float>, centers: [SIMD3<Float>]) -> Int {
        var bestIndex = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (index, center) in centers.enumerated() {
            let distance = LabColorSpace.deltaE(pixel, center)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func kMeansPlusPlusInit(pixels: [SIMD3<Float>], k: Int) -> [SIMD3<Float>] {
        var generator = SeededRNG(seed: 0)
        var centers: [SIMD3<Float>] = [pixels[Int(generator.next() % UInt64(pixels.count))]]

        while centers.count < k {
            var distances = [Float](repeating: 0, count: pixels.count)
            var total: Float = 0
            for (index, pixel) in pixels.enumerated() {
                let nearest = centers.map { LabColorSpace.deltaE(pixel, $0) }.min() ?? 0
                distances[index] = nearest * nearest
                total += distances[index]
            }

            var threshold = Float(generator.next()) / Float(UInt64.max) * total
            var chosen = pixels[0]
            for (index, distance) in distances.enumerated() {
                threshold -= distance
                if threshold <= 0 {
                    chosen = pixels[index]
                    break
                }
            }
            centers.append(chosen)
        }

        return centers
    }
}

/// Deterministic RNG for reproducible subsampling (seed 0 in Python).
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
