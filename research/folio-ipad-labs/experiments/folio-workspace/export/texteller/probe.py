"""Reproducible TexTeller reference, Core ML export, and Mac parity experiment.

Run with the adjacent isolated .venv. All model loads are offline. The first
decoder export deliberately has no KV cache; variable-length greedy generation
is a correctness baseline, not a claim of production performance.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import sys
import time

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")

WORKSPACE = Path(__file__).resolve().parents[2]
REPO = WORKSPACE.parents[1]
sys.path.insert(0, str(WORKSPACE))

import numpy as np
from PIL import Image, ImageDraw, ImageFont
import torch
from server.local_ocr import MODEL, REVISION, Recognizer, clean_latex, preprocess

MAX_TOKENS = 192


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tokenizer_table(tokenizer) -> dict:
    from transformers.models.gpt2.tokenization_gpt2 import bytes_to_unicode
    vocab = tokenizer.get_vocab()
    pieces = [""] * (max(vocab.values()) + 1)
    for piece, token in vocab.items():
        pieces[token] = piece
    return {"pieces": pieces,
        "byte_decoder": {str(ord(character)): byte for byte, character in bytes_to_unicode().items()},
        "special_ids": tokenizer.all_special_ids, "bos": tokenizer.bos_token_id,
        "eos": tokenizer.eos_token_id, "pad": tokenizer.pad_token_id,
        "max_new_tokens": MAX_TOKENS, "clean_up_tokenization_spaces": True}


def decode_table(ids: list[int], table: dict) -> str:
    data = bytes(table["byte_decoder"][str(ord(character))] for token in ids
                 if token not in table["special_ids"] for character in table["pieces"][token])
    text = data.decode("utf8", errors="replace")
    for before, after in [(" .", "."), (" ?", "?"), (" !", "!"), (" ,", ","), (" ' ", "'"),
                          (" n't", "n't"), (" 'm", "'m"), (" 's", "'s"), (" 've", "'ve"), (" 're", "'re")]:
        text = text.replace(before, after)
    return clean_latex(text)


def fixtures(output: Path) -> list[dict]:
    directory = output / "fixtures"
    directory.mkdir(parents=True, exist_ok=True)
    font_path = Path("/System/Library/Fonts/Supplemental/Chalkboard.ttc")
    font = ImageFont.truetype(str(font_path), 48)
    math_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/STIXTwoMath.otf", 52)
    cases = [
        ("equation", "x² + 3 = 12", r"x^{2}+3=12"),
        ("arithmetic", "2 + 2 = 4", "2+2=4"),
        ("algebra", "x² + 3x = 7", r"x^{2}+3x=7"),
        ("fraction", None, r"\frac{x+1}{2}"),
        ("integral", "∫ 2x dx", r"\int 2x\,dx"),
        ("matrix", None, r"\begin{bmatrix}1&2\\3&4\end{bmatrix}"),
    ]
    rows = []
    for name, text, latex in cases:
        image = Image.new("RGB", (640, 180), "white")
        draw = ImageDraw.Draw(image)
        if text:
            draw.text((24, 40), text, font=math_font if name == "integral" else font, fill="black")
        elif name == "fraction":
            draw.text((60, 8), "x + 1", font=font, fill="black")
            draw.line([(45, 88), (210, 88)], fill="black", width=3)
            draw.text((110, 96), "2", font=font, fill="black")
        else:
            for text, point in [("1", (70, 15)), ("2", (150, 15)), ("3", (70, 90)), ("4", (150, 90))]:
                draw.text(point, text, font=font, fill="black")
            draw.line([(52, 12), (36, 12), (36, 155), (52, 155)], fill="black", width=3)
            draw.line([(202, 12), (218, 12), (218, 155), (202, 155)], fill="black", width=3)
        png = directory / f"{name}.png"
        image.save(png)
        tensor = preprocess(image.convert("L"))
        tensor.numpy().astype("<f4").tofile(directory / f"{name}.f32")
        rows.append({"id": name, "image": png.name, "tensor": f"{name}.f32", "ground_truth": latex,
                     "source": "synthetic-layout", "physical_pencil": False, "png_sha256": sha256(png)})
    write_json(directory / "manifest.json", {"fixtures": rows, "shape": [1, 1, 448, 448],
               "normalization": {"mean": 0.9545467, "std": 0.15394445},
               "font_path": str(font_path), "warning": "Synthetic fixtures, not a handwriting accuracy benchmark."})
    return rows


def load_merged(device: str = "cpu"):
    engine = Recognizer(profile="grade12")
    engine.model = engine.model.to("cpu").eval()
    engine.model = engine.model.merge_and_unload().eval().to(device)
    # Make attention export behavior explicit rather than exporting an SDPA-specific graph.
    for config in [engine.model.config.encoder, engine.model.encoder.config]:
        config._attn_implementation = "eager"
    return engine


class Encoder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.encoder = model.encoder
        self.projection = getattr(model, "enc_to_dec_proj", torch.nn.Identity())

    def forward(self, pixels):
        return self.projection(self.encoder(pixel_values=pixels, return_dict=False)[0])


class Decoder(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.decoder = model.decoder

    def forward(self, tokens, encoded):
        return self.decoder(input_ids=tokens, encoder_hidden_states=encoded,
                            use_cache=False, return_dict=False)[0][:, -1, :]


def greedy(encoder, decoder, pixels, bos: int, eos: int) -> tuple[list[int], np.ndarray, list[np.ndarray]]:
    encoded = encoder(pixels)
    ids = [bos]
    logits = []
    for _ in range(MAX_TOKENS):
        value = decoder(torch.tensor([ids], dtype=torch.long, device=pixels.device), encoded)
        logits.append(value.detach().float().cpu().numpy())
        token = int(value.argmax(dim=-1).item())
        ids.append(token)
        if token == eos:
            break
    return ids, encoded.detach().float().cpu().numpy(), logits


def reference(output: Path, device: str) -> None:
    torch.set_num_threads(4)
    torch.manual_seed(0)
    rows = fixtures(output)
    engine = load_merged(device)
    encoder, decoder = Encoder(engine.model).eval(), Decoder(engine.model).eval()
    report = []
    with torch.inference_mode():
        for row in rows:
            pixels = torch.from_numpy(np.fromfile(output / "fixtures" / row["tensor"], dtype="<f4").reshape(1, 1, 448, 448)).to(device)
            started = time.perf_counter()
            ids, encoded, logits = greedy(encoder, decoder, pixels, engine.tokenizer.bos_token_id, engine.tokenizer.eos_token_id)
            if device == "mps":
                torch.mps.synchronize()
            seconds = time.perf_counter() - started
            hf = engine.model.generate(pixel_values=pixels, max_new_tokens=MAX_TOKENS, num_beams=1,
                do_sample=False, use_cache=True, decoder_start_token_id=engine.tokenizer.bos_token_id,
                eos_token_id=engine.tokenizer.eos_token_id, pad_token_id=engine.tokenizer.pad_token_id)[0].tolist()
            if ids != hf:
                raise AssertionError(f"Uncached greedy differs from cached HF generation: {row['id']}")
            latex = clean_latex(engine.tokenizer.decode(ids, skip_special_tokens=True))
            np.savez_compressed(output / "fixtures" / f"{row['id']}-reference.npz", encoded=encoded,
                                first_logits=logits[0], tokens=np.array(ids, dtype=np.int32))
            result = {**row, "tokens": ids, "latex": latex, "eos": ids[-1] == engine.tokenizer.eos_token_id,
                      "seconds": seconds, "hf_cached_greedy_equal": True}
            report.append(result)
            print(json.dumps({"fixture": row["id"], "latex": latex, "seconds": round(seconds, 3)}), flush=True)
    # A portable byte-level BPE detokenizer table, not 15,000 independently decoded fragments.
    table = tokenizer_table(engine.tokenizer)
    for row in report:
        assert decode_table(row["tokens"], table) == row["latex"], row["id"]
    write_json(output / "fixtures" / "tokenizer-table.json", table)
    metadata = {"model": MODEL, "revision": REVISION, "adapter": "grade12-pilot-500",
        "adapter_sha256": sha256(WORKSPACE / "models/grade12/adapter_model.safetensors"),
        "adapter_merged": True, "decoder": "greedy; uncached wrapper checked against HF cached greedy",
        "reference_device": device, "physical_device": False,
        "versions": {name: importlib.metadata.version(name) for name in ["torch", "transformers", "peft", "numpy", "Pillow"]},
        "platform": platform.platform(), "fixtures": report}
    write_json(output / "reference.json", metadata)


def export(output: Path, part: str, precision: str) -> None:
    import coremltools as ct
    torch.set_num_threads(4)
    engine = load_merged("cpu")
    pixels = torch.from_numpy(np.fromfile(output / "fixtures/equation.f32", dtype="<f4").reshape(1, 1, 448, 448))
    encoder = Encoder(engine.model).eval()
    with torch.inference_mode():
        encoded = encoder(pixels)
        if part == "encoder":
            module, example = encoder, (pixels,)
            inputs = [ct.TensorType(name="pixels", shape=(1, 1, 448, 448), dtype=np.float32)]
            outputs = [ct.TensorType(name="encoded", dtype=np.float32)]
        else:
            module = Decoder(engine.model).eval()
            example = (torch.tensor([[0, 10, 20]], dtype=torch.long), encoded)
            inputs = [ct.TensorType(name="tokens", shape=(1, ct.RangeDim(lower_bound=1, upper_bound=MAX_TOKENS, default=3)), dtype=np.int32),
                      ct.TensorType(name="encoded", shape=tuple(encoded.shape), dtype=np.float32)]
            outputs = [ct.TensorType(name="logits", dtype=np.float32)]
        traced = torch.jit.trace(module, example, strict=False)
        if part == "decoder":
            for length in [1, 2, 8, 32]:
                tokens = torch.full((1, length), engine.tokenizer.bos_token_id, dtype=torch.long)
                torch.testing.assert_close(traced(tokens, encoded), module(tokens, encoded), rtol=1e-4, atol=1e-4)
        model = ct.convert(traced, source="pytorch", convert_to="mlprogram", inputs=inputs, outputs=outputs,
            minimum_deployment_target=ct.target.iOS18, compute_units=ct.ComputeUnit.CPU_AND_GPU,
            skip_model_load=True,
            compute_precision=ct.precision.FLOAT16 if precision == "fp16" else ct.precision.FLOAT32)
        name = "Encoder" if part == "encoder" else "Decoder"
        model.short_description = f"TexTeller {part}; {precision}; greedy feasibility; adapter merged"
        model.user_defined_metadata.update({"base_model": MODEL, "base_revision": REVISION,
            "adapter": "grade12-pilot-500", "precision": precision, "decoder_cache": "none"})
        destination = output / "models" / precision / f"{name}.mlpackage"
        destination.parent.mkdir(parents=True, exist_ok=True)
        model.save(str(destination))
        files = {str(p.relative_to(destination)): {"bytes": p.stat().st_size, "sha256": sha256(p)}
                 for p in destination.rglob("*") if p.is_file()}
        write_json(output / f"export-{part}-{precision}.json", {"part": part, "precision": precision,
            "coremltools": ct.__version__, "torch": torch.__version__, "package": str(destination.relative_to(output)),
            "files": files, "trace_lengths_checked": [1, 2, 8, 32] if part == "decoder" else None})
        print("Saved", destination, flush=True)


def validate(output: Path, precision: str, trials: int) -> None:
    import coremltools as ct
    reference_data = json.loads((output / "reference.json").read_text())
    tokenizer = json.loads((output / "fixtures/tokenizer-table.json").read_text())
    started = time.perf_counter()
    encoder = ct.models.MLModel(str(output / "models" / precision / "Encoder.mlpackage"), compute_units=ct.ComputeUnit.CPU_AND_GPU)
    decoder = ct.models.MLModel(str(output / "models" / precision / "Decoder.mlpackage"), compute_units=ct.ComputeUnit.CPU_AND_GPU)
    load_seconds = time.perf_counter() - started
    results = []
    for row in reference_data["fixtures"]:
        pixels = np.fromfile(output / "fixtures" / row["tensor"], dtype="<f4").reshape(1, 1, 448, 448)
        golden = np.load(output / "fixtures" / f"{row['id']}-reference.npz")
        timings = []
        trial_parity = []
        trial_eos = []
        for trial in range(trials):
            started = time.perf_counter()
            encoded = encoder.predict({"pixels": pixels})["encoded"]
            ids = [tokenizer["bos"]]
            first_logits = None
            for _ in range(MAX_TOKENS):
                logits = decoder.predict({"tokens": np.array([ids], dtype=np.int32), "encoded": encoded})["logits"]
                if first_logits is None:
                    first_logits = logits
                if not np.isfinite(logits).all():
                    raise AssertionError("Non-finite Core ML logits")
                token = int(np.argmax(logits))
                ids.append(token)
                if token == tokenizer["eos"]:
                    break
            timings.append(time.perf_counter() - started)
            trial_parity.append(ids == row["tokens"])
            trial_eos.append(ids[-1] == tokenizer["eos"])
        result = {"id": row["id"], "tokens": ids, "tokens_equal": all(trial_parity),
            "eos": all(trial_eos), "trial_token_parity": trial_parity, "seconds": timings,
            "encoder_max_absolute_error": float(np.max(np.abs(encoded - golden["encoded"]))),
            "encoder_relative_l2_error": float(np.linalg.norm(encoded - golden["encoded"]) / max(np.linalg.norm(golden["encoded"]), 1e-12)),
            "first_logits_max_absolute_error": float(np.max(np.abs(first_logits - golden["first_logits"])))}
        results.append(result)
        print(json.dumps(result), flush=True)
        write_json(output / f"parity-{precision}-mac.json", {"platform": "macOS", "physical_ipad": False,
            "compute_units": "CPU_AND_GPU", "load_seconds": load_seconds, "trials": trials,
            "precision": precision, "results": results})
    if not all(row["tokens_equal"] and row["eos"] for row in results):
        raise AssertionError("Token parity failed; see persisted per-fixture results")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["reference", "export-encoder", "export-decoder", "validate"])
    parser.add_argument("--output", type=Path, default=REPO / "results/on-device-texteller")
    parser.add_argument("--precision", choices=["fp32", "fp16"], default="fp16")
    parser.add_argument("--device", choices=["cpu", "mps"], default="cpu")
    parser.add_argument("--trials", type=int, default=2)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.trials < 1:
        parser.error("--trials must be positive")
    started = time.perf_counter()
    try:
        if args.stage == "reference":
            reference(args.output, args.device)
        elif args.stage.startswith("export-"):
            export(args.output, args.stage.removeprefix("export-"), args.precision)
        else:
            validate(args.output, args.precision, args.trials)
    except Exception as exc:
        write_json(args.output / f"failure-{args.stage}-{args.precision}.json", {
            "stage": args.stage, "error_type": type(exc).__name__, "error": str(exc),
            "seconds": time.perf_counter() - started, "physical_ipad": False})
        raise


if __name__ == "__main__":
    main()
