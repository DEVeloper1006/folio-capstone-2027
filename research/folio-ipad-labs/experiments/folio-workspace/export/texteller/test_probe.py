"""Small offline contract tests; no model checkpoint is loaded."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image
import torch
from transformers import RobertaTokenizerFast, TrOCRConfig, TrOCRForCausalLM, ViTConfig, ViTModel, VisionEncoderDecoderModel

import probe


class ProbeTests(unittest.TestCase):
    def test_synthetic_fixture_tensor_contract_and_repeatability(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)
            first = probe.fixtures(output)
            second = probe.fixtures(output)
            self.assertEqual(first, second)
            self.assertEqual(len(first), 6)
            for row in first:
                values = np.fromfile(output / "fixtures" / row["tensor"], dtype="<f4")
                self.assertEqual(values.size, 448 * 448)
                self.assertTrue(np.isfinite(values).all())
                self.assertFalse(row["physical_pencil"])

    def test_blank_image_rejected_by_reference_preprocessor(self):
        with self.assertRaises(ValueError):
            probe.preprocess(Image.new("L", (40, 40), 255))

    def test_greedy_eos_and_token_bound(self):
        class FakeDecoder:
            def __call__(self, tokens, encoded):
                scores = torch.zeros((1, 8))
                scores[0, 4 if tokens.shape[1] == 1 else 2] = 1
                return scores
        ids, _, logits = probe.greedy(lambda pixels: pixels, FakeDecoder(), torch.zeros((1, 1)), 0, 2)
        self.assertEqual(ids, [0, 4, 2])
        self.assertEqual(len(logits), 2)
        with patch.object(probe, "MAX_TOKENS", 3):
            ids, _, _ = probe.greedy(lambda pixels: pixels, FakeDecoder(), torch.zeros((1, 1)), 0, 7)
        self.assertEqual(len(ids), 4)

    def test_split_wrappers_match_full_tiny_transformer(self):
        torch.manual_seed(5)
        vision = ViTModel(ViTConfig(image_size=32, patch_size=16, num_channels=1,
            hidden_size=24, num_hidden_layers=1, num_attention_heads=4, intermediate_size=48))
        decoder = TrOCRForCausalLM(TrOCRConfig(vocab_size=50, d_model=32, decoder_layers=1,
            decoder_attention_heads=4, decoder_ffn_dim=64, max_position_embeddings=32,
            cross_attention_hidden_size=24))
        model = VisionEncoderDecoderModel(encoder=vision, decoder=decoder).eval()
        pixels = torch.randn((1, 1, 32, 32))
        with torch.inference_mode():
            encoded = probe.Encoder(model)(pixels)
            for length in [1, 3, 8]:
                tokens = torch.randint(3, 50, (1, length))
                actual = probe.Decoder(model)(tokens, encoded)
                expected = model(pixel_values=pixels, decoder_input_ids=tokens, use_cache=False).logits[:, -1, :]
                torch.testing.assert_close(actual, expected)

    def test_portable_byte_bpe_handles_unicode_and_latex(self):
        tokenizer = RobertaTokenizerFast.from_pretrained(probe.MODEL, revision=probe.REVISION, local_files_only=True)
        table = probe.tokenizer_table(tokenizer)
        for text in [r"\frac{x+1}{2}", "α + π = θ", r"\[25%\]", "x^{2}+3x=7"]:
            ids = tokenizer.encode(text)
            self.assertEqual(probe.decode_table(ids, table),
                             probe.clean_latex(tokenizer.decode(ids, skip_special_tokens=True)))


if __name__ == "__main__":
    unittest.main()
