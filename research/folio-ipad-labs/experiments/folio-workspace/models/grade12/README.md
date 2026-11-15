# Grade 12 TexTeller adapter

Local inference weights for `grade12-pilot-500`, derived from [OleehyO/TexTeller](https://huggingface.co/OleehyO/TexTeller), revision `7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea`. TexTeller is Apache-2.0 licensed; this adapter is distributed under the included Apache-2.0 license.

This is a rank-8 LoRA adapter, not a full model. Training used 500 optimizer steps and 1,000 original synthetic notation images. No public noncommercial handwriting samples were used in training this adapter. See `../../training/k12/README.md` for methodology and limitations.

The worker verifies both files against `../../config/local-ocr-grade12.json` before loading. Setup downloads the pinned base model separately. Inference uses local cached files and safetensors; no remote model code is executed.

The synthetic test improved from 187/364 to 350/364 matching first readings. Native rasterization of 100 previously used handwriting regression samples improved from 81 to 82 first readings and from 91 to 93 among three candidates. These are small regression measurements, not general accuracy guarantees. The app does not solve or verify recognized mathematics.
