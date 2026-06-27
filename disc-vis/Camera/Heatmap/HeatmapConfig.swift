import Foundation

enum HeatmapConfig {
    /// Long edge of the internal processing resolution.
    static let internalMaxDimension: Int = 384

    /// Scene stats downsample (matches Python ``SCENE_STATS_MAX_DIMENSION`` intent).
    static let sceneStatsMaxDimension: Int = 64

    static let objectRadiusFraction: Float = 0.85
    static let targetDominantColorCount: Int = 1
    static let backgroundDominantColorCount: Int = 5
    static let signatureMergeDeltaE: Float = 5.0

    /// Unweighted Lab ΔE below which a background signature is treated as target-colored and removed.
    static let backgroundExclusionDeltaE: Float = 15.0

    /// Subsample count for background k-means (reduced from Python 50k for mobile).
    static let scenePixelSampleCount: Int = 8_000

    /// Recompute background signatures every N processed frames.
    static let backgroundRecomputeInterval: Int = 8

    static let weightEpsilon: Float = 1e-6
    static let axisWeightEpsilon: Float = 1e-5

    /// Gaussian blur sigma approximating OpenCV 5×5 kernel.
    static let probabilityBlurSigma: Float = 1.2

    static let maxTargetSignatures: Int = 8
    static let maxBackgroundSignatures: Int = 8

    /// Maximum heatmap blend at peak match scores (0 = camera only, 1 = heat only).
    static let defaultOverlayOpacity: Float = 0.95

    /// Minimum score weight for blend (unused; both display modes use uniform overlay opacity).
    static let overlayScoreFloor: Float = 0.0

    /// Gamma applied to score before colormap (emphasizes peaks).
    static let scoreGamma: Float = 1.0

    /// Hard threshold at default sensitivity (matches Python ``PROBABILITY_THRESHOLD`` / 255).
    static let defaultProbabilityThreshold: Float = 100.0 / 255.0

    /// Threshold range mapped by the sensitivity slider (low sensitivity → high threshold).
    static let minProbabilityThreshold: Float = 0.05
    static let maxProbabilityThreshold: Float = 0.95

    /// Sensitivity 0…1; default places threshold at ``defaultProbabilityThreshold``.
    static let defaultSensitivity: Float = {
        let range = minProbabilityThreshold - maxProbabilityThreshold
        guard range != 0 else { return 0.5 }
        return (defaultProbabilityThreshold - maxProbabilityThreshold) / range
    }()

    static let defaultDisplayMode: HeatmapDisplayMode = .thermalCamera
}
