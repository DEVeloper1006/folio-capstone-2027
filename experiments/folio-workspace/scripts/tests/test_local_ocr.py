"""Run with .venv-local-ocr/bin/python -m unittest scripts.tests.test_local_ocr."""
import base64
import io
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image, ImageDraw
from fastapi.testclient import TestClient
from server import local_ocr


def png(blank=False):
    image = Image.new("RGB", (200, 80), "white")
    if not blank:
        ImageDraw.Draw(image).line([(10, 10), (70, 50)], fill="black", width=3)
    output = io.BytesIO()
    image.save(output, format="PNG")
    return "data:image/png;base64," + base64.b64encode(output.getvalue()).decode()


class FakeRecognizer:
    device = "cpu"
    adapter_id = "grade12-pilot-500"

    def __init__(self, profile="base"):
        self.profile = profile

    def recognize(self, value, mode="math"):
        local_ocr.preprocess(local_ocr.decode_image(value))
        return {"latex": "x", "seconds": 0.01}


class LocalOCRTests(unittest.TestCase):
    def setUp(self):
        self.patch = patch.object(local_ocr, "Recognizer", FakeRecognizer)
        self.patch.start()
        self.client = TestClient(local_ocr.app, base_url="http://127.0.0.1:8002")
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.patch.stop()

    def test_numeric_mode_filter(self):
        for value in ["0", "7", "2+2=4", "-3.14", r"\frac{1}{2}", r"\sqrt{4}", r"3\times2=6", r"\mathbf{123}", r"\boldsymbol{2+3}", r"25\%", r"90^\circ", "7!", r"2\leq3", r"4\approx4"]:
            self.assertTrue(local_ocr.is_numeric(value), value)
        for value in ["o", "z", "x+1", r"\frac{x}{2}", "", r"\text{7}", r"\mathbf{x+1}", r"\sqrt{x}", r"\input{7}", r"\frac{O}{2}"]:
            self.assertFalse(local_ocr.is_numeric(value), value)

    def test_latex_wrappers(self):
        self.assertEqual(local_ocr.clean_latex(r"\[x^2\]"), "x^2")
        self.assertEqual(local_ocr.clean_latex("$$7$$"), "7")
        self.assertEqual(local_ocr.clean_latex("x+1"), "x+1")
        self.assertEqual(local_ocr.clean_latex(r"\[25%\]"), r"25\%")
        self.assertEqual(local_ocr.clean_latex(r"25\%"), r"25\%")

    def test_invalid_mode(self):
        self.assertEqual(self.client.post("/recognize", json={"image": png(), "mode": "guess"}).status_code, 422)

    def test_health(self):
        self.assertTrue(self.client.get("/health").json()["offline"])

    def test_preprocessing(self):
        tensor = local_ocr.preprocess(local_ocr.decode_image(png()))
        self.assertEqual(tuple(tensor.shape), (1, 1, 448, 448))
        self.assertTrue(tensor.isfinite().all())

    def test_recognize(self):
        result = self.client.post("/recognize", json={"image": png()})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()["latex"], "x")

    def test_invalid_and_blank(self):
        for image in ["no", "data:image/png;base64,not-base64", png(blank=True)]:
            self.assertEqual(self.client.post("/recognize", json={"image": image}).status_code, 422)

    def test_browser_and_rebinding_rejected(self):
        self.assertEqual(self.client.post("/recognize", json={"image": png()}, headers={"origin": "https://example.com"}).status_code, 403)
        self.assertEqual(self.client.get("/health", headers={"host": "evil.example"}).status_code, 403)

    def test_busy_does_not_queue(self):
        local_ocr.app.state.busy = True
        self.assertEqual(self.client.post("/recognize", json={"image": png()}).status_code, 503)

    def test_large_body_rejected(self):
        self.assertEqual(self.client.post("/recognize", content=b"x" * 3_500_001).status_code, 413)


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "config").mkdir()
        (self.root / "adapter").mkdir()
        hashes = {}
        for name in ("adapter_config.json", "adapter_model.safetensors"):
            data = b"test fixture, model loading is mocked"
            (self.root / "adapter" / name).write_bytes(data)
            hashes[name] = hashlib.sha256(data).hexdigest()
        self.spec = {"id": "test", "base_model": local_ocr.MODEL, "revision": local_ocr.REVISION,
                     "directory": "adapter", "sha256": hashes}
        self.write_spec()
        patcher = patch.object(local_ocr, "__file__", str(self.root / "server/local_ocr.py"))
        patcher.start(); self.addCleanup(patcher.stop)

    def write_spec(self):
        (self.root / "config/local-ocr-grade12.json").write_text(json.dumps(self.spec))

    def test_base_does_not_require_adapter(self):
        self.assertIsNone(local_ocr.adapter_spec("base"))
        with self.assertRaises(ValueError): local_ocr.adapter_spec("typo")

    def test_missing_and_corrupt_weights_fail_closed(self):
        weights = self.root / "adapter/adapter_model.safetensors"
        weights.write_bytes(b"changed")
        with self.assertRaises(ValueError): local_ocr.adapter_spec("grade12")
        weights.unlink()
        with self.assertRaises(ValueError): local_ocr.adapter_spec("grade12")

    def test_wrong_revision_rejected(self):
        self.spec["revision"] = "other"
        self.write_spec()
        with self.assertRaises(ValueError): local_ocr.adapter_spec("grade12")

    def test_loads_tested_adapter_offline_for_inference(self):
        with patch.object(local_ocr.RobertaTokenizerFast, "from_pretrained"), \
             patch.object(local_ocr.VisionEncoderDecoderModel, "from_pretrained"), \
             patch("peft.PeftModel.from_pretrained") as load:
            engine = local_ocr.Recognizer(profile="grade12")
            self.assertEqual(engine.profile, "grade12")
            self.assertEqual(engine.adapter_id, "test")
            self.assertEqual(load.call_args.kwargs, {"local_files_only": True, "is_trainable": False})
            self.assertEqual(load.call_args.args[1], str((self.root / "adapter").resolve()))


if __name__ == "__main__":
    unittest.main()
