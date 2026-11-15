#!/usr/bin/env python3
"""Stage the previously validated Core ML exports; never downloads models."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--artifacts", type=Path, default=ROOT.parent / "folio-ipad-labs/results/on-device-texteller")
args = parser.parse_args()
source = args.artifacts.resolve()
reference = json.loads((source / "reference.json").read_text())
if reference["revision"] != "7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea" or reference["adapter_sha256"] != "001fdbd1e34661c007a286c04c405d21d56cab71c5006c16e4f56542af4ab6db":
    raise SystemExit("Unexpected model revision/adapter")
target = ROOT / "inkpad/inkpad/Resources/LocalTexTeller"
# Verify all source package hashes before writing resources.
packages = []
for part, name in [("encoder", "Encoder"), ("decoder", "Decoder")]:
    manifest = json.loads((source / f"export-{part}-fp16.json").read_text())
    package = source / manifest["package"]
    for relative, metadata in manifest["files"].items():
        path = package / relative
        if not path.resolve().is_relative_to(package.resolve()):
            raise SystemExit("Invalid package manifest path")
        if hashlib.sha256(path.read_bytes()).hexdigest() != metadata["sha256"]:
            raise SystemExit("Changed package file: " + str(path))
    packages.append((package, name))
target.mkdir(parents=True, exist_ok=True)
for package, name in packages:
    destination = target / f"{name}.mlpackage"
    shutil.copytree(package, destination, dirs_exist_ok=True)
shutil.copy2(source / "fixtures/tokenizer-table.json", target / "tokenizer-table.json")
(target / "model-manifest.json").write_text(json.dumps({"model": reference["model"], "revision": reference["revision"], "adapter": reference["adapter"], "adapter_sha256": reference["adapter_sha256"], "precision": "fp16", "decoder": "greedy-uncached", "max_new_tokens": 192}, indent=2) + "\n")
print("Staged validated local TexTeller resources:", target)
