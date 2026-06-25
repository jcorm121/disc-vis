"""Continuous L*a*b* discriminative pixel filter (bin-free).

Purpose
-------
Prototype for DiscVis iOS: given a *reference* photo of a disc (centered, cropped)
and a *scene* photo (disc possibly hidden in brush), produce a per-pixel probability
map highlighting pixels that look like the disc.

This script is intentionally separate from the histogram-based prototypes in this
folder (``histogram_backprojection.py``, ``histogram_backprojection_hsv.py``,
``discriminative_color_tracking.py``). Those discretize color into bins; this one
treats color as a point in continuous 3D Lab space.

Architecture (keep this split when extending)
---------------------------------------------
1. **Processing** — ``compute_continuous_lab_map()`` and helpers below it in the
   "Processing pipeline" section. Returns ``ContinuousLabResult`` with raw maps.
2. **Display** — ``render_probability_*`` and ``display_images()``. Never pass
   ``probability_map`` directly to ``cv2.imshow`` (see display section).

Pipeline overview
-----------------
1. Dynamic axis weights  — scale each Lab axis before measuring distance
2. Target signatures     — mean + k-means dominant colors from reference disc region
3. Background signatures — k-means dominant colors from the *scene* (not reference)
4. Per-pixel distances   — min Euclidean distance to any signature (weighted space)
5. Discriminative score  — compares target vs background proximity per pixel
6. Spatial smoothing     — Gaussian blur on the 8-bit map

Run: ``python continuous_lab_discriminative.py``
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

# =============================================================================
# Hardcoded inputs — edit these for local iteration
# =============================================================================

REPO_ROOT = Path(__file__).resolve().parents[1]
REFERENCE_IMAGE_PATH = REPO_ROOT / "disc-vis-py-algorithms/popcorn-reference.png"
SCENE_IMAGE_PATH = REPO_ROOT / "disc-vis-py-algorithms/popcorn-scene5.png"

# Fraction of the inscribed circle radius used as the target sampling region on
# the *reference* image. This replaces a bounding-box ROI used in tracking papers.
OBJECT_RADIUS_FRACTION = 0.85

# Threshold on probability_map (0–255 scale) for the red overlay in main().
PROBABILITY_THRESHOLD = 100

# k-means signature counts. Target always includes the mean color *plus* up to
# ``TARGET_DOMINANT_COLOR_COUNT`` k-means centroids (deduped).
TARGET_DOMINANT_COLOR_COUNT = 3
BACKGROUND_DOMINANT_COLOR_COUNT = 3

# Merge threshold in *weighted* Lab space during signature extraction.
SIGNATURE_MERGE_DELTA_E = 5.0

# Background k-means subsamples pixels (not spatially) for speed.
SCENE_PIXEL_SAMPLE_COUNT = 50_000

# Scene μ/σ for dynamic axis weights are computed on a spatially downsampled copy
# of the scene Lab image. Reference stats use the full masked target region.
# 640px long edge ≈ preview resolution; mean/std are stable well below full 4K.
SCENE_STATS_MAX_DIMENSION = 640

WEIGHT_EPSILON = 1e-6          # stabilizer in discriminative ratio (step 5)
AXIS_WEIGHT_EPSILON = 1e-5     # stabilizer in dynamic axis weights (step 1)
PROBABILITY_MAP_GAUSSIAN_KERNEL = (5, 5)

AXIS_NAMES = ("L*", "a*", "b*")


# =============================================================================
# Result types
# =============================================================================


@dataclass(frozen=True)
class AxisWeightProfile:
    """Per-axis distance divisors (k_L, k_a, k_b) and the stats used to derive them.

    ``axis_weights`` are divisors applied via ``apply_axis_weights()`` — larger k
    means that axis contributes *less* to Euclidean distance. This is the inverse
    of a typical "importance weight" and confuses people on first read.
    """

    axis_weights: tuple[float, float, float]
    target_mean: tuple[float, float, float]
    target_std: tuple[float, float, float]
    scene_mean: tuple[float, float, float]
    scene_std: tuple[float, float, float]


@dataclass(frozen=True)
class ColorSignatures:
    """Core color vectors stored in *unweighted* L*a*b* for human-readable output."""

    target_signatures: np.ndarray   # shape (N, 3)
    background_signatures: np.ndarray


@dataclass(frozen=True)
class ContinuousLabResult:
    """Output of the processing pipeline.

    ``probability_map`` is float32 on a 0–255 scale after spatial smoothing.
    It is NOT normalized to 0–1. See ``render_probability_heatmap()`` before display.
    """

    probability_map: np.ndarray
    signatures: ColorSignatures
    target_distance_map: np.ndarray   # weighted ΔE, pre-discriminative-ratio
    background_distance_map: np.ndarray
    axis_weight_profile: AxisWeightProfile


# =============================================================================
# Geometry / color space
# =============================================================================


def circular_center_mask(
    height: int,
    width: int,
    radius_fraction: float,
) -> np.ndarray:
    """Binary mask for a filled circle at the image center.

    Unlike typical tracker specs that use a rectangular bounding box, DiscVis
    reference photos are center-cropped discs, so the target region is circular.
    radius_fraction is relative to half the shorter image side (inscribed radius).
    """
    center = (width // 2, height // 2)
    radius = int(radius_fraction * min(width, height) / 2)
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.circle(mask, center, radius, 255, thickness=-1)
    return mask


def bgr_to_lab_float(image_bgr: np.ndarray) -> np.ndarray:
    """Convert BGR to L*a*b* floats suitable for Euclidean distance.

    OpenCV's LAB is uint8 internally (L in 0–255, a/b centered at 128). We rescale
    to conventional ranges: L* ∈ [0, 100], a*/b* centered at 0. Do not skip this step
    and use raw OpenCV LAB uint8 values — distances would be wrong.
    """
    lab = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    lab[..., 0] *= 100.0 / 255.0
    lab[..., 1] -= 128.0
    lab[..., 2] -= 128.0
    return lab


def lab_axis_scale(axis_weights: tuple[float, float, float]) -> np.ndarray:
    scale = np.array(axis_weights, dtype=np.float32)
    if np.any(scale <= 0):
        raise ValueError("LAB axis weights must be positive.")
    return scale


def apply_axis_weights(
    lab: np.ndarray,
    axis_weights: tuple[float, float, float],
) -> np.ndarray:
    """Divide each axis by k_i to realize weighted Euclidean distance.

    Weighted ΔE = ||(C_pixel - C_ref) / k||₂  ≡  dividing coordinates before norm.

    All clustering, merging, and distance math should happen in this weighted space.
    Convert back with ``remove_axis_weights()`` only for printing or storage.
    """
    return lab / lab_axis_scale(axis_weights)


def remove_axis_weights(
    lab: np.ndarray,
    axis_weights: tuple[float, float, float],
) -> np.ndarray:
    """Undo ``apply_axis_weights()`` so signatures print as real L*a*b* values."""
    return lab * lab_axis_scale(axis_weights)


def downsample_scene_lab_for_stats(
    scene_lab: np.ndarray,
    max_dimension: int = SCENE_STATS_MAX_DIMENSION,
) -> np.ndarray:
    """Spatially downsample scene Lab before per-channel μ/σ (scene side only).

    Uses area interpolation so each surviving pixel approximates a local average,
    which is appropriate for global mean/std estimates. The full-resolution
    ``scene_lab`` is still used everywhere else in the pipeline.
    """
    height, width = scene_lab.shape[:2]
    long_edge = max(height, width)
    if long_edge <= max_dimension:
        return scene_lab

    scale = max_dimension / long_edge
    new_width = max(1, int(round(width * scale)))
    new_height = max(1, int(round(height * scale)))
    return cv2.resize(scene_lab, (new_width, new_height), interpolation=cv2.INTER_AREA)


# =============================================================================
# Processing pipeline
# =============================================================================


def compute_dynamic_axis_weights(
    reference_lab: np.ndarray,
    scene_lab: np.ndarray,
    target_mask: np.ndarray,
    *,
    epsilon: float = AXIS_WEIGHT_EPSILON,
) -> AxisWeightProfile:
    """Step 1 — per-axis distance divisors from target vs scene statistics.

    For each axis i ∈ {L*, a*, b*}:
        k_i = (σ_T,i + σ_S,i) / (|μ_T,i − μ_S,i| + ε)

    μ_T, σ_T come from the masked *reference* target region (full resolution).
    μ_S, σ_S come from a downsampled copy of the *scene* image — see
    ``downsample_scene_lab_for_stats()``. Reference stats are not downsampled
    because the iOS app will cache them.

    Axes with little mean separation but high noise get a large k_i and are
    automatically down-weighted. This differs from fixed hand-tuned axis scales.
    """
    target_pixels = reference_lab[target_mask > 0].reshape(-1, 3)
    if target_pixels.size == 0:
        raise ValueError("Target mask contains no pixels.")

    scene_pixels = downsample_scene_lab_for_stats(scene_lab).reshape(-1, 3)

    target_mean = target_pixels.mean(axis=0)
    target_std = target_pixels.std(axis=0)
    scene_mean = scene_pixels.mean(axis=0)
    scene_std = scene_pixels.std(axis=0)

    axis_weights = (target_std + scene_std) / (np.abs(target_mean - scene_mean) + epsilon)

    return AxisWeightProfile(
        axis_weights=(float(axis_weights[0]), float(axis_weights[1]), float(axis_weights[2])),
        target_mean=(float(target_mean[0]), float(target_mean[1]), float(target_mean[2])),
        target_std=(float(target_std[0]), float(target_std[1]), float(target_std[2])),
        scene_mean=(float(scene_mean[0]), float(scene_mean[1]), float(scene_mean[2])),
        scene_std=(float(scene_std[0]), float(scene_std[1]), float(scene_std[2])),
    )


def extract_dominant_colors(pixels_lab: np.ndarray, count: int) -> np.ndarray:
    """k-means centroids in the *caller's* Lab space (usually already axis-weighted)."""
    if pixels_lab.size == 0:
        return np.empty((0, 3), dtype=np.float32)

    pixel_count = pixels_lab.shape[0]
    cluster_count = max(1, min(count, pixel_count))
    if cluster_count == 1:
        return pixels_lab.mean(axis=0, keepdims=True).astype(np.float32)

    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 20, 0.5)
    _, _, centers = cv2.kmeans(
        pixels_lab.astype(np.float32),
        cluster_count,
        None,
        criteria,
        3,
        cv2.KMEANS_PP_CENTERS,
    )
    return centers.astype(np.float32)


def merge_signatures(
    signatures: np.ndarray,
    *,
    merge_delta_e: float = SIGNATURE_MERGE_DELTA_E,
) -> np.ndarray:
    """Greedy dedup of near-identical signatures (in whatever Lab space is passed in)."""
    if signatures.size == 0:
        return signatures

    merged: list[np.ndarray] = []
    for signature in signatures:
        if not merged:
            merged.append(signature)
            continue

        distances = [float(np.linalg.norm(signature - existing)) for existing in merged]
        if min(distances) > merge_delta_e:
            merged.append(signature)

    return np.stack(merged, axis=0).astype(np.float32)


def sample_pixels(pixels_lab: np.ndarray, sample_count: int) -> np.ndarray:
    """Deterministic subsample (seed 0) for reproducible background k-means."""
    if pixels_lab.shape[0] <= sample_count:
        return pixels_lab
    indices = np.random.default_rng(0).choice(pixels_lab.shape[0], sample_count, replace=False)
    return pixels_lab[indices]


def extract_target_signatures(
    reference_bgr: np.ndarray,
    target_mask: np.ndarray,
    *,
    dominant_color_count: int = TARGET_DOMINANT_COLOR_COUNT,
    merge_delta_e: float = SIGNATURE_MERGE_DELTA_E,
    axis_weights: tuple[float, float, float],
) -> np.ndarray:
    """Step 2a — target color signatures from the reference disc region.

    Returns unweighted L*a*b* vectors. Internally clusters in weighted space so
    k-means respects the dynamic axis scaling, then converts back for storage.
    """
    reference_lab = bgr_to_lab_float(reference_bgr)
    target_pixels = apply_axis_weights(reference_lab[target_mask > 0].reshape(-1, 3), axis_weights)
    if target_pixels.size == 0:
        raise ValueError("Target mask contains no pixels.")

    mean_signature = target_pixels.mean(axis=0, keepdims=True)
    dominant_signatures = extract_dominant_colors(target_pixels, dominant_color_count)
    merged_signatures = merge_signatures(
        np.vstack([mean_signature, dominant_signatures]),
        merge_delta_e=merge_delta_e,
    )
    return remove_axis_weights(merged_signatures, axis_weights)


def extract_background_signatures(
    scene_bgr: np.ndarray,
    *,
    dominant_color_count: int = BACKGROUND_DOMINANT_COLOR_COUNT,
    sample_count: int = SCENE_PIXEL_SAMPLE_COUNT,
    axis_weights: tuple[float, float, float],
) -> np.ndarray:
    """Step 2b — dominant scene colors from the *scene* image.

    Unlike ``discriminative_color_tracking.py`` (which builds a scene histogram Q
    over all pixels) or DAT-style surrounding-region models on the reference frame,
    background signatures here are explicit k-means centroids of the scene. The
    discriminative ratio still uses continuous distance, not bin counts.
    """
    scene_lab = bgr_to_lab_float(scene_bgr)
    scene_pixels = apply_axis_weights(scene_lab.reshape(-1, 3), axis_weights)
    sampled_pixels = sample_pixels(scene_pixels, sample_count)
    dominant_signatures = extract_dominant_colors(sampled_pixels, dominant_color_count)
    return remove_axis_weights(dominant_signatures, axis_weights)


def min_distance_to_signatures(
    pixel_lab: np.ndarray,
    signatures: np.ndarray,
) -> np.ndarray:
    """Step 4a — min weighted Euclidean distance from each pixel to any signature.

    Uses the minimum over signatures (not mean), so multicolored targets match if
    a pixel is close to *any* target color.
    """
    if signatures.size == 0:
        return np.full(pixel_lab.shape[:2], np.inf, dtype=np.float32)

    difference = pixel_lab[..., np.newaxis, :] - signatures[np.newaxis, np.newaxis, :, :]
    distances = np.linalg.norm(difference, axis=-1)
    return distances.min(axis=-1).astype(np.float32)


def compute_discriminative_weights(
    target_distance_map: np.ndarray,
    background_distance_map: np.ndarray,
    *,
    epsilon: float = WEIGHT_EPSILON,
) -> np.ndarray:
    """Step 4b — per-pixel discriminative score in [0, 1].

        w = d_bg / (d_target + d_bg + ε)

    High when the pixel is close to a target signature AND far from scene signatures.
    Analogous to P/(P+Q) in binned discriminative tracking, but uses inverse-distance
    geometry instead of histogram bin occupancy. Output is 0–1 float, not 0–255.
    """
    return (background_distance_map / (target_distance_map + background_distance_map + epsilon)).astype(
        np.float32
    )


def suppress_noise(probability_map: np.ndarray) -> np.ndarray:
    """Step 5 — Gaussian smooth after quantizing the 0–1 score to uint8.

    Input ``probability_map`` is expected in [0, 1] from ``compute_discriminative_weights``.
    Output is float32 on a 0–255 scale (matching ``PROBABILITY_THRESHOLD`` units).
    """
    probability_uint8 = np.clip(probability_map * 255.0, 0, 255).astype(np.uint8)
    smoothed = cv2.GaussianBlur(probability_uint8, PROBABILITY_MAP_GAUSSIAN_KERNEL, 0)
    return smoothed.astype(np.float32)


def compute_continuous_lab_map(
    reference_bgr: np.ndarray,
    scene_bgr: np.ndarray,
    *,
    object_radius_fraction: float = OBJECT_RADIUS_FRACTION,
    target_dominant_color_count: int = TARGET_DOMINANT_COLOR_COUNT,
    background_dominant_color_count: int = BACKGROUND_DOMINANT_COLOR_COUNT,
    axis_weights: tuple[float, float, float] | None = None,
) -> ContinuousLabResult:
    """Run the full pipeline. Primary entry point for processing.

    Pass ``axis_weights`` to override the dynamically computed k_i values; stats in
    ``axis_weight_profile`` are still computed and returned for logging.
    """
    target_mask = circular_center_mask(
        reference_bgr.shape[0],
        reference_bgr.shape[1],
        object_radius_fraction,
    )

    reference_lab = bgr_to_lab_float(reference_bgr)
    scene_lab = bgr_to_lab_float(scene_bgr)

    axis_weight_profile = compute_dynamic_axis_weights(reference_lab, scene_lab, target_mask)
    if axis_weights is None:
        axis_weights = axis_weight_profile.axis_weights
    else:
        axis_weight_profile = AxisWeightProfile(
            axis_weights=axis_weights,
            target_mean=axis_weight_profile.target_mean,
            target_std=axis_weight_profile.target_std,
            scene_mean=axis_weight_profile.scene_mean,
            scene_std=axis_weight_profile.scene_std,
        )

    target_signatures = extract_target_signatures(
        reference_bgr,
        target_mask,
        dominant_color_count=target_dominant_color_count,
        axis_weights=axis_weights,
    )
    background_signatures = extract_background_signatures(
        scene_bgr,
        dominant_color_count=background_dominant_color_count,
        axis_weights=axis_weights,
    )
    signatures = ColorSignatures(
        target_signatures=target_signatures,
        background_signatures=background_signatures,
    )

    # Signatures are stored unweighted but distances are computed in weighted space.
    # Re-apply weights here rather than storing two copies of each signature.
    scene_lab = apply_axis_weights(scene_lab, axis_weights)
    target_signatures_weighted = apply_axis_weights(target_signatures, axis_weights)
    background_signatures_weighted = apply_axis_weights(background_signatures, axis_weights)

    target_distance_map = min_distance_to_signatures(scene_lab, target_signatures_weighted)
    background_distance_map = min_distance_to_signatures(scene_lab, background_signatures_weighted)

    raw_weights = compute_discriminative_weights(target_distance_map, background_distance_map)
    probability_map = suppress_noise(raw_weights)

    return ContinuousLabResult(
        probability_map=probability_map,
        signatures=signatures,
        target_distance_map=target_distance_map,
        background_distance_map=background_distance_map,
        axis_weight_profile=axis_weight_profile,
    )


# =============================================================================
# Diagnostics (stdout)
# =============================================================================


def print_axis_weight_profile(profile: AxisWeightProfile) -> None:
    print("\nDynamic axis weights (distance divisors k_i):")
    for index, axis_name in enumerate(AXIS_NAMES):
        print(
            f"  {axis_name}: k={profile.axis_weights[index]:.6f} "
            f"(μ_T={profile.target_mean[index]:7.2f} σ_T={profile.target_std[index]:6.2f} "
            f"μ_S={profile.scene_mean[index]:7.2f} σ_S={profile.scene_std[index]:6.2f})"
        )


def format_lab_vector(color: np.ndarray) -> str:
    return f"L*={color[0]:5.1f} a*={color[1]:6.1f} b*={color[2]:6.1f}"


def print_color_signatures(result: ContinuousLabResult) -> None:
    print("\nTarget signatures:")
    for index, color in enumerate(result.signatures.target_signatures, start=1):
        print(f"  {index}. {format_lab_vector(color)}")

    print("\nBackground signatures:")
    for index, color in enumerate(result.signatures.background_signatures, start=1):
        print(f"  {index}. {format_lab_vector(color)}")


# =============================================================================
# Display (decoupled from processing — safe to swap for Swift / other viewers)
# =============================================================================


def render_probability_heatmap(probability_map: np.ndarray) -> np.ndarray:
    """White-hot BGR visualization: high score = white, low = black.

    IMPORTANT: ``cv2.imshow`` treats float images as 0–1. ``probability_map`` is
    float32 on a 0–255 scale, so passing it directly to imshow saturates to white.
    Always route through this function (or cast to uint8 yourself) for display.
    """
    gray = np.clip(probability_map.squeeze(), 0, 255).astype(np.uint8)
    return cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)


def render_probability_overlay(
    scene_bgr: np.ndarray,
    probability_map: np.ndarray,
    *,
    threshold: float = PROBABILITY_THRESHOLD,
) -> np.ndarray:
    """Paint pixels at or above ``threshold`` (0–255 scale) pure red on the scene."""
    output = scene_bgr.copy()
    mask = probability_map.squeeze() >= threshold
    output[mask] = (0, 0, 255)  # BGR pure red
    return output


def display_images(*images: np.ndarray, window_titles: list[str] | None = None) -> None:
    """Show BGR uint8 images in OpenCV windows. Blocks until a keypress."""
    titles = window_titles or [f"image_{index}" for index in range(len(images))]
    for title, image in zip(titles, images, strict=True):
        cv2.imshow(title, image)
    cv2.waitKey(0)
    cv2.destroyAllWindows()


def main() -> None:
    reference_bgr = cv2.imread(str(REFERENCE_IMAGE_PATH))
    scene_bgr = cv2.imread(str(SCENE_IMAGE_PATH))

    if reference_bgr is None:
        raise FileNotFoundError(f"Could not load reference image: {REFERENCE_IMAGE_PATH}")
    if scene_bgr is None:
        raise FileNotFoundError(f"Could not load scene image: {SCENE_IMAGE_PATH}")

    result = compute_continuous_lab_map(reference_bgr, scene_bgr)
    print_axis_weight_profile(result.axis_weight_profile)
    print_color_signatures(result)

    overlay = render_probability_overlay(
        scene_bgr,
        result.probability_map,
        threshold=PROBABILITY_THRESHOLD,
    )
    heatmap = render_probability_heatmap(result.probability_map)

    display_images(
        overlay,
        heatmap,
        window_titles=["threshold overlay", "continuous lab probability map"],
    )


if __name__ == "__main__":
    main()
