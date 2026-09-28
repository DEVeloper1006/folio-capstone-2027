# <experiment-name>

> Template. Copy this folder to start a new experiment:
>
> ```bash
> cp -r experiments/_template experiments/<experiment-name>
> mkdir -p results/<experiment-name> && touch results/<experiment-name>/.gitkeep
> ```
>
> Then:
> 1. Fill in the sections below.
> 2. Add configs as YAML under `configs/`.
> 3. Write an eval script that prints metrics to stdout and writes JSON to `results/<experiment-name>/` (use `shared/eval/metrics.py`).
> 4. Keep notebooks in `notebooks/` only — no notebooks in production paths.
> 5. Don't import from other experiments; put shared code in `shared/`.
> 6. Register the experiment in the root `README.md` index (and `AGENTS.md`).
> 7. Delete this block.

## What it does

## How to run

```bash
python experiments/<experiment-name>/eval.py --config experiments/<experiment-name>/configs/default.yaml
```

## Metrics to expect

| Metric | Expected |
|--------|----------|
|        |          |
