"""Intent-router eval for the voice agent.

Sends each labeled utterance (plus an optional fixture element table) to TypeSafe Jev via
OpenRouter's Decisions API, using the same question schema as
VoiceAgent/Brain/IntentRouter.swift::classify, then reports per-question accuracy and latency.
Prints metrics and writes a JSON results file.

Usage:
    OPENROUTER_API_KEY=... python experiments/voice-agent/eval_router.py \
        --config experiments/voice-agent/configs/router_eval.yaml
"""

from __future__ import annotations

import argparse
import json
import os
import re
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
SCORED_QUESTIONS = ("intent", "key", "app", "target_index", "text_payload")

# Mirror of Brain/TextPayload.swift.
TEXT_TRIGGERS = (
    "with the text", "that says", "which says", "reply with", "search for", "search up", "look up",
    "look for", "called", "named", "titled", "saying", "says", "type", "write", "enter", "put",
    "dictate", "search", "for",
)
LOCATION_CUTS = (" into the ", " in the ", " on the ", " into ", " in ", " and press ", " then ", " and ")
QUOTED = re.compile(r"[\"“'‘]([^\"“”'‘’]{1,200})[\"”'’]")
MAX_CANDIDATES = 10


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


def _clean(phrase: str) -> str:
    text = phrase.strip()
    for prefix in (":", "that ", "the text "):
        if text.lower().startswith(prefix):
            text = text[len(prefix):].strip()
    return text.strip(" .,!?\"“”'‘’")


def text_candidates(transcript: str) -> list[str]:
    """Mirror of TextPayload.candidates(from:)."""
    ordered: list[str] = []
    seen: set[str] = set()

    def add(raw: str) -> None:
        phrase = _clean(raw)
        if phrase and len(ordered) < MAX_CANDIDATES and phrase.lower() not in seen:
            seen.add(phrase.lower())
            ordered.append(phrase)

    for match in QUOTED.finditer(transcript):
        add(match.group(1))
    lower = transcript.lower()
    for trigger in TEXT_TRIGGERS:
        m = re.search(rf"\b{re.escape(trigger)}\b", lower)
        if not m:
            continue
        tail = transcript[m.end():]
        for cut in LOCATION_CUTS:
            idx = tail.lower().find(cut)
            if idx >= 0:
                add(tail[:idx])
        add(tail)
    add(transcript)
    return ordered


TEXT_INPUT_ROLES = {"AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"}


def summarize(role: str, label: str | None, value: str | None = None) -> str:
    """Mirror of ElementEntry.summary: text inputs also report whether they're empty."""
    kind = role.replace("AX", "").lower()
    text = f"{kind} '{label[:60]}'" if label else f"{kind} (unlabeled)"
    if role in TEXT_INPUT_ROLES:
        current = (value or "").strip()
        text += " (empty)" if not current else f" (value: '{current[:40]}')"
    return text


def serialize_screen(screen: dict[str, Any] | None) -> str:
    """Mirror of ElementTable.serialize()."""
    if not screen:
        return "Screen: (nothing observable)"
    header = f"App: {screen['app']}" + (f" — window: {screen['window']}" if screen.get("window") else "")
    lines = [header, 'Elements (index role "label" id actions):']
    for i, (role, label, ident, actions) in enumerate(screen["elements"]):
        parts = [f"[{i}]", role]
        if label:
            parts.append(f'"{label}"')
        if ident:
            parts.append(f"id={ident}")
        if actions:
            parts.append("actions=" + ",".join(actions))
        lines.append(" ".join(parts))
    return "\n".join(lines)


def build_state(text: str, screen: dict[str, Any] | None) -> str:
    """Mirror of JevQuestions.state(transcript:table:)."""
    return f'User said: "{text}"\n\nCurrent screen:\n{serialize_screen(screen)}'


def app_criteria(cfg: dict[str, Any]) -> dict[str, str]:
    """Mirror of AppCatalog.criteria(): installed apps, then websites that don't share a name."""
    criteria = {name: f"The {name} app" for name in cfg["apps"]}
    installed = {name.lower() for name in cfg["apps"]}
    for name, extra_aliases in cfg.get("websites", {}).items():
        if name.lower() in installed:
            continue
        alias = f" (also called {', '.join(extra_aliases)})" if extra_aliases else ""
        criteria[name] = f"The {name} website{alias}, opened in the browser"
    return criteria


def build_questions(cfg: dict[str, Any], text: str, screen: dict[str, Any] | None) -> dict[str, Any]:
    """Mirror of IntentRouter.classify's question set."""
    questions: dict[str, Any] = {
        "intent": {
            "type": "choice",
            "instructions": "What should the Mac do for this request?",
            "criteria": cfg["intents"],
        },
        "key": {
            "type": "choice",
            "instructions": "If pressing a key or shortcut, which one?",
            "criteria": cfg["keys"],
        },
        "app": {
            "type": "choice",
            "instructions": "If opening an app or website, which one?",
            "criteria": app_criteria(cfg),
        },
    }
    if screen and screen["elements"]:
        questions["target_index"] = {
            "type": "choice",
            "instructions": "If clicking, typing or scrolling, which element from the table (by index)?",
            "criteria": {str(i): summarize(role, label) for i, (role, label, _, _) in enumerate(screen["elements"])},
        }
    candidates = text_candidates(text)
    if candidates:
        questions["text_payload"] = {
            "type": "choice",
            "instructions": "If typing, which phrase from the user's words should be typed exactly?",
            "criteria": {c: f"Type exactly: {c}" for c in candidates},
        }
    return questions


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

    screens = cfg.get("screens", {})
    correct = {q: 0 for q in SCORED_QUESTIONS}
    total = {q: 0 for q in SCORED_QUESTIONS}
    latencies: list[float] = []
    rows: list[dict[str, Any]] = []
    errors = 0
    served_model = None

    print(f"Evaluating {len(cases)} utterances against {model} ...")
    for case in cases:
        text, expect = case["text"], case.get("expect", {})
        screen = screens.get(case["screen"]) if case.get("screen") else None
        try:
            payload, ms = call_jev(
                cfg["endpoint"],
                api_key,
                model,
                build_state(text, screen),
                build_questions(cfg, text, screen),
                cfg.get("timeout_s", 15),
            )
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
            detail = exc.read().decode(errors="replace")[:200] if isinstance(exc, urllib.error.HTTPError) else str(exc)
            print(f"  ERROR  {text!r}: {detail}")
            rows.append({"text": text, "expect": expect, "error": detail})
            errors += 1
            continue

        served_model = served_model or payload.get("model")
        latencies.append(ms)
        raw_answers = payload.get("answers", {})
        answers = {name: ans.get("choice") for name, ans in raw_answers.items()}
        intent_confidence = raw_answers.get("intent", {}).get("confidence")
        hits = {}
        for q in SCORED_QUESTIONS:
            if q in expect:
                total[q] += 1
                hits[q] = answers.get(q) == expect[q]
                correct[q] += int(hits[q])
        ok = all(hits.values())
        shown = {q: answers.get(q) for q in expect} if ok else answers
        print(f"  {'ok  ' if ok else 'MISS'}  {ms:6.0f}ms  {text!r} -> {shown}" + ("" if ok else f"  expected {expect}"))
        rows.append(
            {
                "text": text,
                "screen": case.get("screen"),
                "expect": expect,
                "answers": answers,
                "intent_confidence": intent_confidence,
                "latency_ms": round(ms, 1),
                "correct": hits,
            }
        )

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
            print(f"  {q:<12} accuracy  {accuracy[q]:.1%}  ({correct[q]}/{total[q]})")
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
