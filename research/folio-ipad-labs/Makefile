PYTHON ?= python

.PHONY: setup setup-unimumer eval-hme eval-unimumer clean

setup:
	$(PYTHON) -m pip install -e .

# Clones Uni-MuMER (gitignored), installs extras, downloads ~4.5 GB weights to the HF cache.
setup-unimumer:
	PYTHON=$(PYTHON) bash experiments/hme-recognition/setup_unimumer.sh

eval-hme:
	$(PYTHON) experiments/hme-recognition/eval_pix2tex.py

eval-unimumer:
	$(PYTHON) experiments/hme-recognition/eval_unimumer.py

# `rm results/**/*.json` doesn't recurse in make's /bin/sh, so use find.
clean:
	find results -name '*.json' -type f -delete
