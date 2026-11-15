"""Offline TexTeller inference. Separate environment and loopback-only process."""
import asyncio
import base64
import binascii
from contextlib import asynccontextmanager
from functools import lru_cache
import io
import hashlib
import json
import os
from pathlib import Path
import time
import re
import secrets
from urllib.parse import urlsplit
from typing import Literal

import numpy as np
from PIL import Image, ImageChops, UnidentifiedImageError
import torch
from transformers import RobertaTokenizerFast, VisionEncoderDecoderModel
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

MODEL = "OleehyO/TexTeller"
REVISION = "7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea"
Image.MAX_IMAGE_PIXELS = 2_000_000


def decode_image(value: str) -> Image.Image:
    if not value.startswith("data:image/png;base64,"):
        raise ValueError("Expected a PNG image")
    raw = base64.b64decode(value.split(",", 1)[1], validate=True)
    if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Expected a PNG image")
    with Image.open(io.BytesIO(raw)) as source:
        if source.width * source.height > 2_000_000:
            raise ValueError("Image is too large")
        source.load()
        rgba = source.convert("RGBA")
        image = Image.new("RGBA", source.size, "white")
        image.alpha_composite(rgba)
        return image.convert("L")


def preprocess(image: Image.Image) -> torch.Tensor:
    # TexTeller uses tight crops, long edge 448, normalized grayscale, and
    # zero padding in normalized space. Keep this aligned with model training.
    difference = ImageChops.difference(image, Image.new("L", image.size, 255))
    bounds = difference.point(lambda p: 255 if p > 15 else 0).getbbox()
    if bounds is None:
        raise ValueError("No handwriting found")
    image = image.crop(bounds)
    ratio = 448 / max(image.size)
    size = tuple(max(1, int(d * ratio)) for d in image.size)
    image = image.resize(size, Image.Resampling.BICUBIC)
    pixels = (np.asarray(image, dtype=np.float32) / 255 - 0.9545467) / 0.15394445
    output = np.zeros((1, 1, 448, 448), dtype=np.float32)
    output[0, 0, :size[1], :size[0]] = pixels
    return torch.from_numpy(output)


def clean_latex(latex: str) -> str:
    latex = latex.strip()
    # Percent is a visible symbol in handwriting, not a LaTeX comment.
    latex = re.sub(r"(?<!\\)%", r"\\%", latex)
    for opening, closing in [(r"\[", r"\]"), (r"\(", r"\)"), ("$$", "$$"), ("$", "$")]:
        if latex.startswith(opening) and latex.endswith(closing):
            return latex[len(opening):-len(closing)].strip()
    return latex


def is_numeric(latex: str) -> bool:
    # Choose among model hypotheses, never rewrite letters into digits.
    remainder = re.sub(r"\\(?:frac|sqrt|times|div|cdot|left|right|approx|leq|geq|neq|le|ge|ne|circ|mathbf|boldsymbol|mathrm|mathit|textbf|bm|bf|%|,|!)", "", latex)
    return bool(re.search(r"[0-9]", remainder)) and bool(re.fullmatch(r"[0-9+*/=().,{}\[\]^_\s<>|:!%\-]+", remainder))


def adapter_spec(profile: str) -> dict | None:
    if profile == "base":
        return None
    if profile != "grade12":
        raise ValueError("FOLIO_OCR_PROFILE must be grade12 or base")
    root = Path(__file__).resolve().parents[1]
    spec = json.loads((root / "config/local-ocr-grade12.json").read_text())
    if spec["base_model"] != MODEL or spec["revision"] != REVISION:
        raise ValueError("Adapter does not match the pinned base model")
    directory = root / spec["directory"]
    for name in ("adapter_config.json", "adapter_model.safetensors"):
        file = directory / name
        if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != spec["sha256"][name]:
            raise ValueError(f"Missing or changed Grade 12 adapter: {name}. Restore the tested files or use FOLIO_OCR_PROFILE=base.")
    return {**spec, "directory": directory}


class Recognizer:
    # Direct construction remains the baseline for reproducible training/evaluation.
    def __init__(self, profile: str = "base"):
        spec = adapter_spec(profile)
        self.profile = profile
        self.adapter_id = spec["id"] if spec else None
        self.device = "mps" if torch.backends.mps.is_available() else "cpu"
        torch.set_num_threads(4)
        # Never downloads or executes model repository code at runtime.
        self.tokenizer = RobertaTokenizerFast.from_pretrained(MODEL, revision=REVISION, local_files_only=True)
        self.model = VisionEncoderDecoderModel.from_pretrained(
            MODEL, revision=REVISION, local_files_only=True, use_safetensors=True
        ).eval().to(self.device)
        if spec:
            from peft import PeftModel
            self.model = PeftModel.from_pretrained(
                self.model, str(spec["directory"]), local_files_only=True, is_trainable=False
            ).eval().to(self.device)
        self.model.decoder.config.use_cache = True

    @lru_cache(maxsize=16)
    def recognize(self, value: str, mode: str = "math") -> dict:
        pixels = preprocess(decode_image(value)).to(self.device)
        start = time.monotonic()
        with torch.inference_mode():
            tokens = self.model.generate(
                pixels, max_new_tokens=192, num_beams=3, num_return_sequences=3, do_sample=False,
                use_cache=True, decoder_start_token_id=self.tokenizer.bos_token_id,
                eos_token_id=self.tokenizer.eos_token_id, pad_token_id=self.tokenizer.pad_token_id,
            )
        decoded = self.tokenizer.batch_decode(tokens, skip_special_tokens=True)
        candidates = list(dict.fromkeys(clean_latex(text) for text, ids in zip(decoded, tokens)
                                       if self.tokenizer.eos_token_id in ids.tolist()[1:] and clean_latex(text)))
        if mode == "numbers":
            candidates = [text for text in candidates if is_numeric(text)]
        if not candidates:
            raise ValueError("No complete numeric reading found. Try Algebra mode or correct the row." if mode == "numbers" else "No complete expression found. Try a smaller row.")
        return {"latex": candidates[0], "alternatives": candidates[1:], "note": "Local model draft. Review before accepting.",
                "seconds": round(time.monotonic() - start, 3), "provider": "TexTeller", "device": self.device, "profile": self.profile, "adapter": self.adapter_id}


@asynccontextmanager
async def lifespan(app: FastAPI):
    lan = os.environ.get("FOLIO_OCR_LAN") == "1"
    token = os.environ.get("FOLIO_OCR_TOKEN", "")
    hosts = {host.strip().lower() for host in os.environ.get("FOLIO_OCR_ALLOWED_HOSTS", "").split(",") if host.strip()}
    if lan and (len(token) < 24 or not hosts or "*" in hosts):
        raise RuntimeError("LAN mode requires FOLIO_OCR_TOKEN (24+ characters) and explicit FOLIO_OCR_ALLOWED_HOSTS")
    app.state.lan = lan
    app.state.token = token
    app.state.allowed_hosts = (hosts if lan else set()) | {"127.0.0.1", "localhost"}
    app.state.recognizer = await asyncio.to_thread(Recognizer, profile=os.environ.get("FOLIO_OCR_PROFILE", "grade12"))
    app.state.busy = False
    yield


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None)


@app.middleware("http")
async def local_only(request: Request, call_next):
    # Native clients send no Origin. Reject websites and DNS rebinding hosts.
    try:
        host = urlsplit("//" + request.headers.get("host", "")).hostname
    except ValueError:
        return JSONResponse({"detail": "Invalid host"}, status_code=403)
    if request.headers.get("origin") or host not in request.app.state.allowed_hosts:
        return JSONResponse({"detail": "Local native clients only"}, status_code=403)
    if request.app.state.lan:
        supplied = request.headers.get("authorization", "")
        if not secrets.compare_digest(supplied.encode(), ("Bearer " + request.app.state.token).encode()):
            return JSONResponse({"detail": "Connection token required"}, status_code=401)
    if request.method == "POST":
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > 3_500_000:
                return JSONResponse({"detail": "Image is too large"}, status_code=413)
            # Body replay is required by FastAPI after middleware consumption.
        request._body = bytes(body)
    return await call_next(request)


class RecognitionRequest(BaseModel):
    image: str = Field(max_length=3_400_000)
    mode: Literal["math", "numbers"] = "math"


@app.get("/health")
def health():
    return {"ready": True, "model": MODEL, "revision": REVISION, "device": app.state.recognizer.device,
            "offline": True, "profile": app.state.recognizer.profile, "adapter": app.state.recognizer.adapter_id}


@app.post("/recognize")
async def recognize(payload: RecognitionRequest):
    if app.state.busy:
        raise HTTPException(503, "Local recognizer is busy. Retry after the current row.")
    app.state.busy = True
    task = asyncio.create_task(asyncio.to_thread(app.state.recognizer.recognize, payload.image, payload.mode))
    # A disconnected client must not release the slot while inference still runs.
    task.add_done_callback(lambda _: setattr(app.state, "busy", False))
    try:
        return await asyncio.shield(task)
    except (ValueError, binascii.Error, UnidentifiedImageError, Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise HTTPException(422, str(exc)) from exc
    except Exception as exc:
        raise HTTPException(503, "Local inference failed. Ink is unchanged.") from exc
