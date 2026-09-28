PYTHON ?= python

.PHONY: setup eval-hme clean

setup:
	$(PYTHON) -m pip install -e .

eval-hme:
	$(PYTHON) experiments/hme-recognition/eval_pix2tex.py

# `rm results/**/*.json` doesn't recurse in make's /bin/sh, so use find.
clean:
	find results -name '*.json' -type f -delete
