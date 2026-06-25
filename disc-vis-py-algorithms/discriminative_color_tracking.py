"""Adaptive discriminative pixel filter for disc color matching.

Selects H-S or S-V feature space from target chromaticity, builds normalized
target/scene histograms, smooths them with a mode-dependent Gaussian kernel,
applies a discriminative weight LUT, and smooths the resulting probability map.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path

import cv2
import numpy as np

# --- Hardcoded inputs (edit for local testing) ---

REPO_ROOT = Path(__file__).resolve().parents[1]
REFERENCE_IMAGE_PATH = REPO_ROOT / "disc-vis-py-algorithms/popcorn-reference.png"
TARGET_IMAGE_PATH = REPO_ROOT / "disc-vis-py-algorithms/popcorn-scene1-zoom.png"

OBJECT_RADIUS_FRACTION = 0.85
PROBABILITY_THRESHOLD = 100

CHROMATIC_SATURATION_MIN = 0.15
CHROMATIC_VALUE_MIN = 0.15
CHROMATIC_VALUE_MAX = 0.98

CHROMATIC_BINS = (180, 256)
ACHROMATIC_BINS = (32, 32)

ILLUMINATION_VALUE_MIN = 20
ILLUMINATION_VALUE_MAX = 235

WEIGHT_EPSILON = 1e-7
CHROMATIC_HISTOGRAM_GAUSSIAN_KERNEL = (9, 9)
ACHROMATIC_HISTOGRAM_GAUSSIAN_KERNEL = (3, 3)
PROBABILITY_MAP_GAUSSIAN_KERNEL = (5, 5)
WEIGHTED_BIN_REPORT_COUNT = 100


class TrackingMode(Enum):
    CHROMATIC = "chromatic"
    ACHROMATIC = "achromatic"


@dataclass(frozen=True)
class TrackingProfile:
    """Active feature space selected from reference target statistics."""

    mode: TrackingMode
    mean_saturation: float
    mean_value: float
    channels: tuple[int, int]
    hist_bins: tuple[int, int]
    channel_ranges: tuple[tuple[int, int], tuple[int, int]]


@dataclass(frozen=True)
class DiscriminativeColorResult:
    """Smoothed pixel-level discriminative map and intermediate model state."""

    probability_map: np.ndarray
    profile: TrackingProfile
    target_histogram: np.ndarray
    scene_histogram: np.ndarray
    likelihood_weights: np.ndarray


@dataclass(frozen=True)
class WeightedBin:
    """A single LUT bin with its discriminative weight and feature coordinates."""

    bin_a: int
    bin_b: int
    weight: float
    channel_a: str
    channel_b: str
    channel_a_range: tuple[float, float]
    channel_b_range: tuple[float, float]
    target_prob: float
    scene_prob: float


def circular_center_mask(
    height: int,
    width: int,
    radius_fraction: float,
) -> np.ndarray:
    """Binary mask for a circle centered on the image."""
    center = (width // 2, height // 2)
    radius = int(radius_fraction * min(width, height) / 2)
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.circle(mask, center, radius, 255, thickness=-1)
    return mask


def analyze_target_profile(
    reference_bgr: np.ndarray,
    target_mask: np.ndarray,
) -> TrackingProfile:
    """Phase 1: classify chromaticity and choose the active HSV feature pair."""
    reference_hsv = cv2.cvtColor(reference_bgr, cv2.COLOR_BGR2HSV)
    target_pixels = reference_hsv[target_mask > 0]

    mean_saturation = float(target_pixels[:, 1].mean() / 255.0)
    mean_value = float(target_pixels[:, 2].mean() / 255.0)

    is_chromatic = (
        mean_saturation >= CHROMATIC_SATURATION_MIN
        and CHROMATIC_VALUE_MIN <= mean_value <= CHROMATIC_VALUE_MAX
    )

    if is_chromatic:
        return TrackingProfile(
            mode=TrackingMode.CHROMATIC,
            mean_saturation=mean_saturation,
            mean_value=mean_value,
            channels=(0, 1),
            hist_bins=CHROMATIC_BINS,
            channel_ranges=((0, 180), (0, 256)),
        )

    return TrackingProfile(
        mode=TrackingMode.ACHROMATIC,
        mean_saturation=mean_saturation,
        mean_value=mean_value,
        channels=(1, 2),
        hist_bins=ACHROMATIC_BINS,
        channel_ranges=((0, 256), (0, 256)),
    )


def build_joint_histogram(
    image_bgr: np.ndarray,
    profile: TrackingProfile,
    mask: np.ndarray | None = None,
) -> np.ndarray:
    """Phase 2: build a normalized 2D joint histogram for the active feature pair."""
    image_hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    hist = cv2.calcHist(
        [image_hsv],
        channels=list(profile.channels),
        mask=mask,
        histSize=list(profile.hist_bins),
        ranges=[bound for channel_range in profile.channel_ranges for bound in channel_range],
    )
    hist = hist.astype(np.float64)
    total = hist.sum()
    if total > 0:
        hist /= total
    return hist


def histogram_gaussian_kernel(profile: TrackingProfile) -> tuple[int, int]:
    if profile.mode is TrackingMode.CHROMATIC:
        return CHROMATIC_HISTOGRAM_GAUSSIAN_KERNEL
    return ACHROMATIC_HISTOGRAM_GAUSSIAN_KERNEL


def smooth_histogram(
    histogram: np.ndarray,
    kernel_size: tuple[int, int],
) -> np.ndarray:
    """Low-pass filter a 2D histogram, then re-normalize to sum to 1."""
    smoothed = cv2.GaussianBlur(histogram.astype(np.float64), kernel_size, 0)
    total = smoothed.sum()
    if total > 0:
        smoothed /= total
    return smoothed


def build_likelihood_weights(
    target_histogram: np.ndarray,
    scene_histogram: np.ndarray,
    *,
    epsilon: float = WEIGHT_EPSILON,
) -> np.ndarray:
    """Phase 3: w(i) = P(i) / (P(i) + Q(i) + epsilon)."""
    return (target_histogram / (target_histogram + scene_histogram + epsilon)).astype(np.float32)


def feature_bin_indices(
    channel_values: np.ndarray,
    hist_bins: int,
    value_range: tuple[int, int],
) -> np.ndarray:
    """Map channel values to histogram bin indices matching ``cv2.calcHist``."""
    low, high = value_range
    scaled = (channel_values.astype(np.float32) - low) / (high - low)
    indices = (scaled * hist_bins).astype(np.int32)
    return np.clip(indices, 0, hist_bins - 1)


def backproject_likelihood_weights(
    scene_bgr: np.ndarray,
    profile: TrackingProfile,
    likelihood_weights: np.ndarray,
) -> np.ndarray:
    """Phase 4: assign w(i) to every scene pixel via LUT lookup."""
    scene_hsv = cv2.cvtColor(scene_bgr, cv2.COLOR_BGR2HSV)
    channel_a = scene_hsv[:, :, profile.channels[0]]
    channel_b = scene_hsv[:, :, profile.channels[1]]

    bins_a, bins_b = profile.hist_bins
    range_a, range_b = profile.channel_ranges
    index_a = feature_bin_indices(channel_a, bins_a, range_a)
    index_b = feature_bin_indices(channel_b, bins_b, range_b)

    probability_map = likelihood_weights[index_a, index_b].astype(np.float32)

    if profile.mode is TrackingMode.CHROMATIC:
        value_channel = scene_hsv[:, :, 2]
        broken_illumination = (value_channel < ILLUMINATION_VALUE_MIN) | (
            value_channel > ILLUMINATION_VALUE_MAX
        )
        probability_map[broken_illumination] = 0.0

    probability_uint8 = np.clip(probability_map * 255.0, 0, 255).astype(np.uint8)
    return probability_uint8.astype(np.float32)


def suppress_noise(probability_map: np.ndarray) -> np.ndarray:
    """Phase 5: low-pass Gaussian smoothing on the 8-bit probability map."""
    probability_uint8 = np.clip(probability_map, 0, 255).astype(np.uint8)
    smoothed = cv2.GaussianBlur(probability_uint8, PROBABILITY_MAP_GAUSSIAN_KERNEL, 0)
    return smoothed.astype(np.float32)


def compute_discriminative_color_map(
    reference_bgr: np.ndarray,
    scene_bgr: np.ndarray,
    *,
    object_radius_fraction: float = OBJECT_RADIUS_FRACTION,
) -> DiscriminativeColorResult:
    """Run the full adaptive discriminative pixel filter pipeline."""
    target_mask = circular_center_mask(
        reference_bgr.shape[0],
        reference_bgr.shape[1],
        object_radius_fraction,
    )

    profile = analyze_target_profile(reference_bgr, target_mask)
    histogram_kernel = histogram_gaussian_kernel(profile)

    target_histogram = smooth_histogram(
        build_joint_histogram(reference_bgr, profile, mask=target_mask),
        histogram_kernel,
    )
    scene_histogram = smooth_histogram(
        build_joint_histogram(scene_bgr, profile, mask=None),
        histogram_kernel,
    )
    likelihood_weights = build_likelihood_weights(target_histogram, scene_histogram)

    raw_map = backproject_likelihood_weights(scene_bgr, profile, likelihood_weights)
    probability_map = suppress_noise(raw_map)

    return DiscriminativeColorResult(
        probability_map=probability_map,
        profile=profile,
        target_histogram=target_histogram,
        scene_histogram=scene_histogram,
        likelihood_weights=likelihood_weights,
    )


def channel_labels(profile: TrackingProfile) -> tuple[str, str]:
    if profile.mode is TrackingMode.CHROMATIC:
        return ("H", "S")
    return ("S", "V")


def bin_value_range(
    bin_index: int,
    hist_bins: int,
    value_range: tuple[int, int],
) -> tuple[float, float]:
    low, high = value_range
    width = (high - low) / hist_bins
    return (low + bin_index * width, low + (bin_index + 1) * width)


def weighted_bin_at(
    result: DiscriminativeColorResult,
    bin_a: int,
    bin_b: int,
) -> WeightedBin:
    profile = result.profile
    label_a, label_b = channel_labels(profile)
    range_a, range_b = profile.channel_ranges
    bins_a, bins_b = profile.hist_bins
    return WeightedBin(
        bin_a=bin_a,
        bin_b=bin_b,
        weight=float(result.likelihood_weights[bin_a, bin_b]),
        channel_a=label_a,
        channel_b=label_b,
        channel_a_range=bin_value_range(bin_a, bins_a, range_a),
        channel_b_range=bin_value_range(bin_b, bins_b, range_b),
        target_prob=float(result.target_histogram[bin_a, bin_b]),
        scene_prob=float(result.scene_histogram[bin_a, bin_b]),
    )


def get_extreme_weighted_bins(
    result: DiscriminativeColorResult,
    n: int = WEIGHTED_BIN_REPORT_COUNT,
) -> tuple[list[WeightedBin], list[WeightedBin]]:
    """Return the ``n`` highest- and lowest-weight LUT bins."""
    weights = result.likelihood_weights.ravel()
    report_count = min(n, weights.size)
    sorted_indices = np.argsort(weights, kind="stable")
    #filtered_indices = sorted_indices[sorted_indices]

    lowest_bins: list[WeightedBin] = []
    for flat_index in sorted_indices[:report_count]:
        bin_a, bin_b = np.unravel_index(flat_index, result.profile.hist_bins)
        lowest_bins.append(weighted_bin_at(result, int(bin_a), int(bin_b)))

    highest_bins: list[WeightedBin] = []
    for flat_index in sorted_indices[-report_count:][::-1]:
        bin_a, bin_b = np.unravel_index(flat_index, result.profile.hist_bins)
        highest_bins.append(weighted_bin_at(result, int(bin_a), int(bin_b)))

    return highest_bins, lowest_bins


def format_weighted_bin(weighted_bin: WeightedBin) -> str:
    a_low, a_high = weighted_bin.channel_a_range
    b_low, b_high = weighted_bin.channel_b_range
    return (
        f"bins=({weighted_bin.bin_a}, {weighted_bin.bin_b}) "
        f"w={weighted_bin.weight:.4f} "
        f"P={weighted_bin.target_prob:.6f} Q={weighted_bin.scene_prob:.6f} "
        f"{weighted_bin.channel_a}=[{a_low:.1f}, {a_high:.1f}) "
        f"{weighted_bin.channel_b}=[{b_low:.1f}, {b_high:.1f})"
    )


def print_extreme_weighted_bins(
    result: DiscriminativeColorResult,
    n: int = WEIGHTED_BIN_REPORT_COUNT,
) -> None:
    highest_bins, lowest_bins = get_extreme_weighted_bins(result, n=n)

    print(f"\nTop {len(highest_bins)} weighted bins:")
    for rank, weighted_bin in enumerate(highest_bins, start=1):
        print(f"  {rank:2d}. {format_weighted_bin(weighted_bin)}")

    print(f"\nBottom {len(lowest_bins)} weighted bins:")
    for rank, weighted_bin in enumerate(lowest_bins, start=1):
        print(f"  {rank:2d}. {format_weighted_bin(weighted_bin)}")


def render_probability_overlay(
    scene_bgr: np.ndarray,
    probability_map: np.ndarray,
    *,
    threshold: float = PROBABILITY_THRESHOLD,
) -> np.ndarray:
    """Highlight pixels above ``threshold`` in pure red on a copy of the scene image."""
    output = scene_bgr.copy()
    mask = probability_map.squeeze() >= threshold
    output[mask] = (0, 0, 255)  # BGR pure red
    return output


def display_images(*images: np.ndarray, window_titles: list[str] | None = None) -> None:
    """Show one or more BGR images in OpenCV windows."""
    titles = window_titles or [f"image_{index}" for index in range(len(images))]
    for title, image in zip(titles, images, strict=True):
        cv2.imshow(title, image)
    cv2.waitKey(0)
    cv2.destroyAllWindows()


def main() -> None:
    reference_bgr = cv2.imread(str(REFERENCE_IMAGE_PATH))
    scene_bgr = cv2.imread(str(TARGET_IMAGE_PATH))

    if reference_bgr is None:
        raise FileNotFoundError(f"Could not load reference image: {REFERENCE_IMAGE_PATH}")
    if scene_bgr is None:
        raise FileNotFoundError(f"Could not load scene image: {TARGET_IMAGE_PATH}")

    result = compute_discriminative_color_map(
        reference_bgr,
        scene_bgr,
        object_radius_fraction=OBJECT_RADIUS_FRACTION,
    )

    print(
        f"tracking mode: {result.profile.mode.value} "
        f"(S={result.profile.mean_saturation:.2f}, V={result.profile.mean_value:.2f})"
    )
    print_extreme_weighted_bins(result, n=WEIGHTED_BIN_REPORT_COUNT)

    overlay = render_probability_overlay(
        scene_bgr,
        result.probability_map,
        threshold=PROBABILITY_THRESHOLD,
    )

    display_images(
        overlay,
        result.probability_map,
        window_titles=["threshold overlay", "discriminative probability map"],
    )


if __name__ == "__main__":
    main()
