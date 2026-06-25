"""Histogram backprojection in LAB a-b space for disc color matching."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

# --- Hardcoded inputs (edit for local testing) ---

REPO_ROOT = Path(__file__).resolve().parents[1]
REFERENCE_IMAGE_PATH = REPO_ROOT / "disc-vis-py-algorithms/popcorn-reference.png"
TARGET_IMAGE_PATH = REPO_ROOT / "disc-vis-py-algorithms/popcorn-scene1-zoom.png"

SAMPLE_RADIUS_FRACTION = 0.85
PROBABILITY_THRESHOLD = 1 # 0–255 scale from backprojection
HIST_BINS = (32, 32)


@dataclass(frozen=True)
class BackprojectionResult:
    """Pixel-level color probability map and the reference histogram used to build it."""

    probability_map: np.ndarray
    reference_histogram: np.ndarray


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


def build_ab_histogram(
    reference_bgr: np.ndarray,
    *,
    sample_radius_fraction: float = SAMPLE_RADIUS_FRACTION,
    hist_bins: tuple[int, int] = HIST_BINS,
) -> np.ndarray:
    """Build a normalized 2D histogram over LAB a-b channels from a circular center region."""
    reference_lab = cv2.cvtColor(reference_bgr, cv2.COLOR_BGR2LAB)
    mask = circular_center_mask(
        reference_lab.shape[0],
        reference_lab.shape[1],
        sample_radius_fraction,
    )

    hist = cv2.calcHist(
        [reference_lab],
        channels=[1, 2],
        mask=mask,
        histSize=list(hist_bins),
        ranges=[0, 256, 0, 256],
    )
    cv2.normalize(hist, hist, alpha=0, beta=255, norm_type=cv2.NORM_MINMAX)
    return hist


def compute_ab_histogram_backprojection(
    reference_bgr: np.ndarray,
    target_bgr: np.ndarray,
    *,
    sample_radius_fraction: float = SAMPLE_RADIUS_FRACTION,
    hist_bins: tuple[int, int] = HIST_BINS,
) -> BackprojectionResult:
    """Run histogram backprojection in a-b space to produce a per-pixel probability map."""
    hist = build_ab_histogram(
        reference_bgr,
        sample_radius_fraction=sample_radius_fraction,
        hist_bins=hist_bins,
    )

    target_lab = cv2.cvtColor(target_bgr, cv2.COLOR_BGR2LAB)
    probability_map = cv2.calcBackProject(
        [target_lab],
        channels=[1, 2],
        hist=hist,
        ranges=[0, 256, 0, 256],
        scale=1.0,
    )
    return BackprojectionResult(
        probability_map=probability_map,
        reference_histogram=hist,
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

    result = compute_ab_histogram_backprojection(
        reference_bgr,
        target_bgr,
        sample_radius_fraction=SAMPLE_RADIUS_FRACTION,
    )

    overlay = render_probability_overlay(
        target_bgr,
        result.probability_map,
        threshold=PROBABILITY_THRESHOLD,
    )

    display_images(
        overlay,
        result.probability_map,
        window_titles=["threshold overlay", "probability map"],
    )


if __name__ == "__main__":
    main()
