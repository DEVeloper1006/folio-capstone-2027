"""Verify a copied iPad handwriting example against the Python preprocessing.

This checks tensor/crop parity and persisted token/text metadata, not recognition
accuracy. No model is loaded. Pass the copied Handwriting/<UUID> directory.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

from probe import REPO, decode_table, preprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("example", type=Path)
    args = parser.parse_args()
    folder = args.example
    record = json.loads((folder / "result.json").read_text())
    expected = preprocess(Image.open(folder / "input.png").convert("L")).numpy().flatten()
    actual = np.fromfile(folder / "input.f32", dtype="<f4")
    np.testing.assert_array_equal(actual, expected)
    assert (folder / "strokes.drawing").stat().st_size > 0
    table = json.loads((REPO / "results/on-device-texteller/fixtures/tokenizer-table.json").read_text())
    prediction = record["recognition"]
    assert prediction["tokens"][-1] == table["eos"]
    assert decode_table(prediction["tokens"], table) == prediction["latex"]
    assert all(np.isfinite(prediction[key]) and prediction[key] >= 0
               for key in ["inferenceSeconds", "encoderSeconds", "decoderSeconds"])
    print(json.dumps({"id": record["id"], "source": record["source"],
        "native_tensor_matches_python": True, "persisted_token_text_consistent": True,
        "latex": prediction["latex"], "expected_latex": record["expectedLatex"],
        "inference_seconds": prediction["inferenceSeconds"]}, indent=2))


if __name__ == "__main__":
    main()
