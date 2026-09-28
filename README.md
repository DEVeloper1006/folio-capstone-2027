# folio-ipad-labs

ML experimentation layer for the Folio iPad math workspace. Each folder under `experiments/` is a self-contained research spike (handwritten math recognition, voice agents, graph generation, proof explanation), sharing data loaders, metrics, and export tooling from `shared/`. Experiments that pan out get exported to CoreML/ONNX and wired into the iPad app through `ios-bridge/`. This repo is not the Folio app itself.

## Quickstart

```bash
make setup      # pip install -e .
make eval-hme   # pix2tex baseline on data/test_images
```

## Experiment index

| Experiment | Status | Description |
|------------|--------|-------------|
| [`hme-recognition`](experiments/hme-recognition/) | Active | Handwritten math expression → LaTeX |
| [`voice-agent`](experiments/voice-agent/) | Planned | Laya voice model fine-tuning for Folio |
| [`graph-generation`](experiments/graph-generation/) | Planned | Math expression → visual graph/plot |
| [`proof-explainer`](experiments/proof-explainer/) | Planned | Step-by-step proof breakdown |

## Layout

```
shared/        data loaders, eval metrics, export utils
experiments/   one folder per experiment (start from experiments/_template/)
ios-bridge/    Swift inference wrappers for on-device deployment
results/       eval outputs (JSON gitignored, folders tracked)
data/          downloaded datasets (gitignored)
```
