"""Preprocessing for rasterized ink traces (PNG): crop, resize, normalize."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image


def load_grayscale(path: str | Path) -> Image.Image:
    """Load an image as 8-bit grayscale, flattening any alpha onto white."""
    img = Image.open(path)
    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        rgba = img.convert("RGBA")
        bg = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        img = Image.alpha_composite(bg, rgba)
    return img.convert("L")


def crop_to_ink(img: Image.Image, threshold: int = 200, padding: int = 8) -> Image.Image:
    """Crop to the bounding box of dark (ink) pixels plus padding.

    Assumes dark ink on a light background. Returns the image unchanged if no
    ink is found.
    """
    arr = np.asarray(img.convert("L"))
    ys, xs = np.nonzero(arr < threshold)
    if len(xs) == 0:
        return img
    left = max(int(xs.min()) - padding, 0)
    top = max(int(ys.min()) - padding, 0)
    right = min(int(xs.max()) + padding + 1, arr.shape[1])
    bottom = min(int(ys.max()) + padding + 1, arr.shape[0])
    return img.crop((left, top, right, bottom))


def resize_keep_aspect(img: Image.Image, max_height: int, max_width: int) -> Image.Image:
    """Downscale (never upscale) to fit within max_height x max_width."""
    scale = min(max_height / img.height, max_width / img.width, 1.0)
    if scale >= 1.0:
        return img
    size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
    return img.resize(size, Image.Resampling.LANCZOS)


def normalize(img: Image.Image) -> np.ndarray:
    """Convert to float32 array in [0, 1] with ink = 1, background = 0."""
    arr = np.asarray(img.convert("L"), dtype=np.float32) / 255.0
    return 1.0 - arr


def preprocess(
    path: str | Path,
    max_height: int = 256,
    max_width: int = 1024,
    padding: int = 8,
) -> Image.Image:
    """Load, crop to ink, and resize. Returns a grayscale PIL image."""
    img = load_grayscale(path)
    img = crop_to_ink(img, padding=padding)
    return resize_keep_aspect(img, max_height, max_width)
