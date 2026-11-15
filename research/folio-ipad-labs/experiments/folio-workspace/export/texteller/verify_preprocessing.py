"""Compare the compiled Swift preprocessing implementation with the real worker.

No model checkpoint is loaded. Requires an already compiled PreprocessCheck and
the existing fixture PNGs. All generated test images live in a temporary folder.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

import numpy as np
from PIL import Image

from probe import REPO, preprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, default=REPO / "results/on-device-texteller/fixtures")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    binary = str(args.binary.resolve())
    rows = []
    with tempfile.TemporaryDirectory() as folder:
        temporary = Path(folder)
        images = sorted(args.fixtures.glob("*.png"))
        if len(images) != 6:
            raise RuntimeError("Expected six existing synthetic fixture PNGs")
        rng = np.random.default_rng(19)
        for index, (width, height) in enumerate([(3, 7), (800, 503), (503, 800), (448, 448), (1, 19), (19, 1)]):
            pixels = rng.integers(0, 256, (height, width), dtype=np.uint8)
            image = temporary / f"noise-{index}.png"
            Image.fromarray(pixels).convert("RGB").save(image)
            images.append(image)
        # Crop threshold: value 240 is ignored; 239 is included. Exercise edges.
        pixels = np.full((40, 70), 255, dtype=np.uint8)
        pixels[2, 2] = 240; pixels[9:21, 10:60] = 239; pixels[10, 11] = 0
        threshold = temporary / "threshold.png"
        Image.fromarray(pixels).convert("RGB").save(threshold); images.append(threshold)
        for image in images:
            tensor = temporary / "output.f32"
            completed = subprocess.run([binary, str(image), str(tensor)], check=True, capture_output=True, text=True)
            expected = preprocess(Image.open(image).convert("L")).numpy().flatten()
            actual = np.fromfile(tensor, dtype="<f4")
            np.testing.assert_array_equal(actual, expected, err_msg=str(image))
            rows.append({"id": image.stem, "exact_tensor_match": True,
                         "info": json.loads(completed.stdout)})
        blank = temporary / "blank.png"
        Image.new("RGB", (50, 50), "white").save(blank)
        completed = subprocess.run([binary, str(blank), str(temporary / "blank.f32")], capture_output=True, text=True)
        assert completed.returncode == 2 and "No handwriting" in completed.stderr, completed
    report = {"native_platform": "macOS", "physical_ipad": False,
              "exact_tensor_cases": len(rows), "blank_rejected": True, "results": rows}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
