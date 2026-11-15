"""Evaluate Uni-MuMER (Qwen3-VL-2B fine-tuned for handwritten math) on MathWriting.

Mirrors Uni-MuMER's own ``scripts/vllm_infer.py`` (system prompt, user turn of
[image, prompt], ChatML template, whitespace-stripped output) but runs through
Hugging Face ``transformers`` instead of vLLM, which needs CUDA and does not
run on Apple Silicon. Samples, rendering, metrics and the results table are
shared with ``eval_pix2tex.py`` via ``hme_common.py``.

Setup: ``bash experiments/hme-recognition/setup_unimumer.sh``

Usage (from repo root):
    python experiments/hme-recognition/eval_unimumer.py [--config PATH] [--limit N] [--split valid]
"""

from __future__ import annotations

import argparse
import glob
import json
from pathlib import Path
from typing import Any

from PIL import Image

from hme_common import CONFIG_DIR, EXPERIMENT_NAME, Predictor, evaluate, load_config, load_items, resolve_path

DEFAULT_CONFIG = CONFIG_DIR / "unimumer.yaml"

# Verbatim from Uni-MuMER's data (data.zip -> data/CROHME/prompts/*.json,
# messages[0].value, repo commit 85732e0), including the literal "<image>" tag,
# which their vllm_infer.py passes through unchanged.
SYSTEM_PROMPT = "You are a helpful assistant."
USER_PROMPT = (
    "<image>I have an image of a handwritten mathematical expression. "
    "Please write out the expression of the formula in the image using LaTeX format."
)


def pick_device(requested: str) -> str:
    import torch

    if requested != "auto":
        return requested
    if torch.cuda.is_available():
        return "cuda"
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def pick_dtype(requested: str, device: str) -> Any:
    import torch

    if requested != "auto":
        return getattr(torch, requested)
    return torch.float32 if device == "cpu" else torch.bfloat16


def load_predictor(cfg: dict[str, Any]) -> Predictor:
    try:
        import torch
        from transformers import AutoProcessor, Qwen3VLForConditionalGeneration
    except ImportError as e:
        raise SystemExit("transformers>=4.57 is required. Run `make setup-unimumer` first.") from e

    device = pick_device(cfg.get("device", "auto"))
    dtype = pick_dtype(cfg.get("dtype", "auto"), device)
    model_id = cfg["model"]
    print(f"Loading {model_id} on {device} ({dtype})...")
    processor = AutoProcessor.from_pretrained(model_id)
    model = Qwen3VLForConditionalGeneration.from_pretrained(model_id, dtype=dtype).to(device).eval()

    temperature = float(cfg.get("temperature", 0.0))
    gen_kwargs: dict[str, Any] = {"max_new_tokens": int(cfg.get("max_new_tokens", 1024))}
    if temperature > 0:
        gen_kwargs.update(do_sample=True, temperature=temperature, top_p=0.8, top_k=50)
    else:
        gen_kwargs.update(do_sample=False, temperature=None, top_p=None, top_k=None)

    def predict(img: Image.Image) -> str:
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": [{"type": "image", "image": img}, {"type": "text", "text": USER_PROMPT}]},
        ]
        inputs = processor.apply_chat_template(
            messages, tokenize=True, add_generation_prompt=True, return_dict=True, return_tensors="pt"
        ).to(device)
        with torch.inference_mode():
            out = model.generate(**inputs, **gen_kwargs)
        new_tokens = out[:, inputs["input_ids"].shape[1] :]
        return processor.batch_decode(new_tokens, skip_special_tokens=True)[0].strip()

    return predict


def check_same_samples_as_pix2tex(cfg: dict[str, Any], sample_ids: list[str]) -> None:
    """Warn if the latest matching pix2tex run used different samples."""
    pattern = str(resolve_path(f"results/{EXPERIMENT_NAME}/pix2tex_mathwriting-{cfg.get('split')}_*.json"))
    runs = sorted(glob.glob(pattern))
    if not runs:
        return
    with open(runs[-1]) as f:
        ref_ids = [s["sample_id"] for s in json.load(f)["samples"]]
    if ref_ids == sample_ids:
        print(f"Same {len(ref_ids)} samples as {Path(runs[-1]).name}")
    elif ref_ids[: len(sample_ids)] == sample_ids:
        print(f"Samples are the first {len(sample_ids)} of {Path(runs[-1]).name}")
    else:
        print(f"WARNING: samples differ from {Path(runs[-1]).name}; results are not directly comparable")


def run(cfg: dict[str, Any]) -> dict[str, Any]:
    items, label_fields = load_items(cfg)
    if cfg.get("dataset", "mathwriting") == "mathwriting":
        check_same_samples_as_pix2tex(cfg, [it.sample_id for it in items])
    out_path = resolve_path(cfg.get("output_file", f"results/{EXPERIMENT_NAME}/unimumer_baseline.json"))
    predict = load_predictor(cfg)
    return evaluate(predict, cfg, items, label_fields, out_path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--model", help="HF model id or local path")
    parser.add_argument("--split")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--output-file", dest="output_file")
    parser.add_argument("--device", help="auto | mps | cuda | cpu")
    parser.add_argument("--dtype", help="auto | bfloat16 | float16 | float32")
    parser.add_argument("--temperature", type=float)
    parser.add_argument("--max-new-tokens", dest="max_new_tokens", type=int)
    parser.add_argument("--preprocess", action="store_true", default=None)
    args = parser.parse_args()

    overrides = {k: v for k, v in vars(args).items() if k != "config"}
    run(load_config(args.config, overrides))


if __name__ == "__main__":
    main()
