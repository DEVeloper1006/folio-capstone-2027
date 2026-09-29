"""Intent-router eval for the voice agent.

Sends each labeled utterance to TypeSafe Jev via OpenRouter's System One API using
the same question schema as VoiceAgent/Brain/IntentRouter.swift, then reports
per-question accuracy and latency. Prints metrics and writes a JSON results file.

Usage:
    OPENROUTER_API_KEY=... python experiments/voice-agent/eval_router.py \
        --config experiments/voice-agent/configs/router_eval.yaml
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml

EXPERIMENT_NAME = "voice-agent"
REPO_ROOT = Path(__file__).resolve().parents[2]
SCORED_QUESTIONS = ("mode", "action", "key", "app")


def resolve_path(path: str) -> Path:
    p = Path(path)
    return p if p.is_absolute() else REPO_ROOT / p


def load_api_key() -> str | None:
    key = os.environ.get("OPENROUTER_API_KEY")
    if key:
        return key
    for candidate in (REPO_ROOT / "experiments" / EXPERIMENT_NAME / ".env", REPO_ROOT / ".env"):
        if candidate.exists():
            for line in candidate.read_text().splitlines():
                if line.strip().startswith("OPENROUTER_API_KEY="):
                    value = line.split("=", 1)[1].strip().strip("'\"")
                    if value:
                        return value
    return None


def build_questions(cfg: dict[str, Any]) -> dict[str, Any]:
    """Mirror of IntentRouter.classify's question set."""
    return {
        "mode": {"type": "choice", "instructions": "What kind of request is this?", "criteria": cfg["modes"]},
        "action": {
            "type": "choice",
            "instructions": "If this is a single Mac command, which one?",
            "criteria": cfg["actions"],
        },
        "key": {
            "type": "choice",
            "instructions": "If a key or shortcut should be pressed, which one?",
            "criteria": cfg["keys"],
        },
        "app": {
            "type": "choice",
            "instructions": "Which application does the user mean, if any?",
            "criteria": {name: f"The {name} app" for name in cfg["apps"]},
        },
    }


def call_jev(
    endpoint: str, api_key: str, model: str, state: str, questions: dict[str, Any], timeout: float
) -> tuple[dict[str, Any], float]:
    body = json.dumps({"model": model, "state": state, "questions": questions}).encode()
    req = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "X-Title": "folio-voice-agent-eval",
        },
    )
    start = time.perf_counter()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        payload = json.loads(resp.read())
    return payload, (time.perf_counter() - start) * 1000


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    k = (len(ordered) - 1) * pct
    lo, hi = int(k), min(int(k) + 1, len(ordered) - 1)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (k - lo)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", default="experiments/voice-agent/configs/router_eval.yaml")
    parser.add_argument("--model", help="Override the Jev model id from the config")
    parser.add_argument("--limit", type=int, help="Only run the first N cases")
    args = parser.parse_args()

    cfg = yaml.safe_load(resolve_path(args.config).read_text())
    model = args.model or cfg["model"]
    cases = cfg["cases"][: args.limit] if args.limit else cfg["cases"]

    api_key = load_api_key()
    if not api_key:
        print("OPENROUTER_API_KEY not set (env, experiments/voice-agent/.env, or repo .env); skipping eval.")
        return 2

    questions = build_questions(cfg)
    correct = {q: 0 for q in SCORED_QUESTIONS}
    total = {q: 0 for q in SCORED_QUESTIONS}
    latencies: list[float] = []
    rows: list[dict[str, Any]] = []
    errors = 0
    served_model = None

    print(f"Evaluating {len(cases)} utterances against {model} ...")
    for case in cases:
        text, expect = case["text"], case.get("expect", {})
        try:
            payload, ms = call_jev(
                cfg["endpoint"], api_key, model, f"User said: {text}", questions, cfg.get("timeout_s", 15)
            )
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
            detail = exc.read().decode(errors="replace")[:200] if isinstance(exc, urllib.error.HTTPError) else str(exc)
            print(f"  ERROR  {text!r}: {detail}")
            rows.append({"text": text, "expect": expect, "error": detail})
            errors += 1
            continue

        served_model = served_model or payload.get("model")
        latencies.append(ms)
        answers = {name: ans.get("choice") for name, ans in payload.get("answers", {}).items()}
        hits = {}
        for q in SCORED_QUESTIONS:
            if q in expect:
                total[q] += 1
                hits[q] = answers.get(q) == expect[q]
                correct[q] += int(hits[q])
        ok = all(hits.values())
        print(f"  {'ok  ' if ok else 'MISS'}  {ms:6.0f}ms  {text!r} -> {answers}" + ("" if ok else f"  expected {expect}"))
        rows.append({"text": text, "expect": expect, "answers": answers, "latency_ms": round(ms, 1), "correct": hits})

    accuracy = {q: (correct[q] / total[q] if total[q] else None) for q in SCORED_QUESTIONS}
    exact = [r for r in rows if "answers" in r]
    exact_match = sum(all(r["correct"].values()) for r in exact) / len(exact) if exact else None
    metrics = {
        **{f"{q}_accuracy": accuracy[q] for q in SCORED_QUESTIONS},
        "exact_match": exact_match,
        "latency_p50_ms": percentile(latencies, 0.50),
        "latency_p95_ms": percentile(latencies, 0.95),
        "latency_mean_ms": statistics.fmean(latencies) if latencies else None,
        "n_cases": len(cases),
        "n_errors": errors,
    }

    print("\nMetrics")
    for q in SCORED_QUESTIONS:
        if accuracy[q] is not None:
            print(f"  {q:<7} accuracy  {accuracy[q]:.1%}  ({correct[q]}/{total[q]})")
    if exact_match is not None:
        print(f"  exact match       {exact_match:.1%}")
    if latencies:
        print(f"  latency p50/p95   {metrics['latency_p50_ms']:.0f} / {metrics['latency_p95_ms']:.0f} ms")
    print(f"  errors            {errors}/{len(cases)}")

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_path = resolve_path(cfg["output_file"].format(timestamp=timestamp))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(
            {
                "experiment": EXPERIMENT_NAME,
                "model_requested": model,
                "model_served": served_model,
                "config": args.config,
                "timestamp": timestamp,
                "metrics": metrics,
                "cases": rows,
            },
            indent=2,
        )
    )
    print(f"\nWrote {out_path.relative_to(REPO_ROOT)}")
    return 0 if errors < len(cases) else 1


if __name__ == "__main__":
    sys.exit(main())
