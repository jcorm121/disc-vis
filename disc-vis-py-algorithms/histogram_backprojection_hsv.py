"""Histogram backprojection on HSV channels for disc color matching."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

# --- Hardcoded inputs (edit for local testing) ---

REPO_ROOT = Path(__file__).resolve().parents[1]
REFERENCE_IMAGE_PATH = REPO_ROOT / "disc-vis-py-algorithms/popcorn-reference.png"
TARGET_IMAGE_PATH = REPO_ROOT / "disc-vis-py-algorithms/popcorn-scene1-zoom.png"

SAMPLE_RADIUS_FRACTION = 0.8
PROBABILITY_THRESHOLD = 70  # 0–255 scale from backprojection
HIST_BINS = 32


@dataclass(frozen=True)
class HSVChannelWeights:
    """Relative weights for combining per-channel probability maps."""

    hue: float = 1.0
    saturation: float = 1.0
    value: float = 1.0

    def normalized(self) -> tuple[float, float, float]:
        total = self.hue + self.saturation + self.value
        if total == 0:
            raise ValueError("Channel weights must sum to a positive value.")
        return (self.hue / total, self.saturation / total, self.value / total)


CHANNEL_WEIGHTS = HSVChannelWeights(hue=1, saturation=1, value=1)

_HSV_CHANNELS = (
    ("hue", 0, (0, 180)),
    ("saturation", 1, (0, 256)),
    ("value", 2, (0, 256)),
)


@dataclass(frozen=True)
class BackprojectionResult:
    """Combined and per-channel probability maps plus reference histograms."""

    probability_map: np.ndarray
    channel_maps: dict[str, np.ndarray]
    reference_histograms: dict[str, np.ndarray]


def circular_center_mask(
    height: int,
    width: int,
    radius_fraction: float,
) -> np.ndarray:
    """Binary mask for a circle centered on the image.

    ``radius_fraction`` is relative to the inscribed circle radius (half the shorter side).
    """
    center = (width // 2, height // 2)
    radius = int(radius_fraction * min(width, height) / 2)
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.circle(mask, center, radius, 255, thickness=-1)
    return mask


def build_channel_histogram(
    reference_hsv: np.ndarray,
    channel_index: int,
    mask: np.ndarray,
    *,
    hist_bins: int = HIST_BINS,
    value_range: tuple[int, int],
) -> np.ndarray:
    """Build a normalized 1D histogram for a single HSV channel."""
    hist = cv2.calcHist(
        [reference_hsv],
        channels=[channel_index],
        mask=mask,
        histSize=[hist_bins],
        ranges=list(value_range),
    )
    cv2.normalize(hist, hist, alpha=0, beta=255, norm_type=cv2.NORM_MINMAX)
    return hist


def backproject_channel(
    target_hsv: np.ndarray,
    channel_index: int,
    hist: np.ndarray,
    *,
    value_range: tuple[int, int],
) -> np.ndarray:
    """Backproject a single HSV channel histogram onto the target image."""
    return cv2.calcBackProject(
        [target_hsv],
        channels=[channel_index],
        hist=hist,
        ranges=list(value_range),
        scale=1.0,
    )


def combine_channel_maps(
    channel_maps: dict[str, np.ndarray],
    *,
    channel_weights: HSVChannelWeights = CHANNEL_WEIGHTS,
) -> np.ndarray:
    """Weighted average of per-channel probability maps."""
    weights = channel_weights.normalized()
    names = ("hue", "saturation", "value")
    combined = np.zeros_like(channel_maps["hue"], dtype=np.float32)
    for name, weight in zip(names, weights, strict=True):
        combined += weight * channel_maps[name].astype(np.float32)
    return combined


def compute_hsv_histogram_backprojection(
    reference_bgr: np.ndarray,
    target_bgr: np.ndarray,
    *,
    sample_radius_fraction: float = SAMPLE_RADIUS_FRACTION,
    hist_bins: int = HIST_BINS,
    channel_weights: HSVChannelWeights = CHANNEL_WEIGHTS,
) -> BackprojectionResult:
    """Backproject H, S, and V separately, then combine via weighted average."""
    reference_hsv = cv2.cvtColor(reference_bgr, cv2.COLOR_BGR2HSV)
    target_hsv = cv2.cvtColor(target_bgr, cv2.COLOR_BGR2HSV)
    mask = circular_center_mask(
        reference_hsv.shape[0],
        reference_hsv.shape[1],
        sample_radius_fraction,
    )

    channel_maps: dict[str, np.ndarray] = {}
    reference_histograms: dict[str, np.ndarray] = {}

    for name, channel_index, value_range in _HSV_CHANNELS:
        hist = build_channel_histogram(
            reference_hsv,
            channel_index,
            mask,
            hist_bins=hist_bins,
            value_range=value_range,
        )
        reference_histograms[name] = hist
        channel_maps[name] = backproject_channel(
            target_hsv,
            channel_index,
            hist,
            value_range=value_range,
        )

    probability_map = combine_channel_maps(channel_maps, channel_weights=channel_weights)
    return BackprojectionResult(
        probability_map=probability_map,
        channel_maps=channel_maps,
        reference_histograms=reference_histograms,
    )


def render_probability_overlay(
    target_bgr: np.ndarray,
    probability_map: np.ndarray,
    *,
    threshold: float = PROBABILITY_THRESHOLD,
) -> np.ndarray:
    """Highlight pixels above ``threshold`` in pure red on a copy of the target image."""
    output = target_bgr.copy()
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
    target_bgr = cv2.imread(str(TARGET_IMAGE_PATH))

    if reference_bgr is None:
        raise FileNotFoundError(f"Could not load reference image: {REFERENCE_IMAGE_PATH}")
    if target_bgr is None:
        raise FileNotFoundError(f"Could not load target image: {TARGET_IMAGE_PATH}")

    result = compute_hsv_histogram_backprojection(
        reference_bgr,
        target_bgr,
        sample_radius_fraction=SAMPLE_RADIUS_FRACTION,
        channel_weights=CHANNEL_WEIGHTS,
    )

    overlay = render_probability_overlay(
        target_bgr,
        result.probability_map,
        threshold=PROBABILITY_THRESHOLD,
    )

    display_images(
        overlay,
        result.probability_map,
        window_titles=["threshold overlay", "combined probability map"],
    )


if __name__ == "__main__":
    main()
