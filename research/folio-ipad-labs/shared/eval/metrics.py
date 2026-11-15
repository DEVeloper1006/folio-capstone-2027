"""Standard HME metrics: ExpRate, BLEU, and normalized edit distance.

All metrics operate on LaTeX token sequences. Strings are normalized with
``shared.utils.latex_normalize.normalize_latex`` before tokenization unless
``normalize=False`` is passed.
"""

from __future__ import annotations

import re
from collections.abc import Sequence

import editdistance
from nltk.translate.bleu_score import SmoothingFunction, corpus_bleu

from shared.utils.latex_normalize import normalize_latex

# A control word (\frac), a control symbol (\{), or any single non-space char.
_TOKEN_RE = re.compile(r"\\[a-zA-Z]+|\\.|\S")


def tokenize_latex(s: str, normalize: bool = True) -> list[str]:
    """Split a LaTeX string into tokens."""
    if normalize:
        s = normalize_latex(s)
    return _TOKEN_RE.findall(s)


def _check_lengths(preds: Sequence[str], refs: Sequence[str]) -> None:
    if len(preds) != len(refs):
        raise ValueError(f"preds ({len(preds)}) and refs ({len(refs)}) differ in length")


def token_edit_distance(pred: str, ref: str, normalize: bool = True) -> int:
    """Levenshtein distance between the token sequences of pred and ref."""
    return int(editdistance.eval(tokenize_latex(pred, normalize), tokenize_latex(ref, normalize)))


def exp_rate(
    preds: Sequence[str],
    refs: Sequence[str],
    tolerance: int = 0,
    normalize: bool = True,
) -> float:
    """Expression recognition rate.

    Fraction of predictions whose token edit distance to the reference is
    <= ``tolerance``. ``tolerance=0`` is the standard exact-match ExpRate;
    1 and 2 give the CROHME-style "<=1" / "<=2" error variants.
    """
    _check_lengths(preds, refs)
    if not preds:
        return 0.0
    hits = sum(token_edit_distance(p, r, normalize) <= tolerance for p, r in zip(preds, refs))
    return hits / len(preds)


def bleu(
    preds: Sequence[str],
    refs: Sequence[str],
    max_n: int = 4,
    normalize: bool = True,
) -> float:
    """Corpus-level BLEU over LaTeX tokens (nltk, method1 smoothing)."""
    _check_lengths(preds, refs)
    if not preds:
        return 0.0
    hyps = [tokenize_latex(p, normalize) for p in preds]
    references = [[tokenize_latex(r, normalize)] for r in refs]
    weights = tuple(1.0 / max_n for _ in range(max_n))
    return float(
        corpus_bleu(references, hyps, weights=weights, smoothing_function=SmoothingFunction().method1)
    )


def normalized_edit_distance(pred: str, ref: str, normalize: bool = True) -> float:
    """Token edit distance divided by the longer sequence length, in [0, 1]."""
    p, r = tokenize_latex(pred, normalize), tokenize_latex(ref, normalize)
    denom = max(len(p), len(r))
    if denom == 0:
        return 0.0
    return editdistance.eval(p, r) / denom


def mean_normalized_edit_distance(
    preds: Sequence[str],
    refs: Sequence[str],
    normalize: bool = True,
) -> float:
    """Mean of per-sample normalized edit distances (lower is better)."""
    _check_lengths(preds, refs)
    if not preds:
        return 0.0
    return sum(normalized_edit_distance(p, r, normalize) for p, r in zip(preds, refs)) / len(preds)


def compute_all(preds: Sequence[str], refs: Sequence[str], normalize: bool = True) -> dict[str, float]:
    """Compute every standard metric and return them keyed by name."""
    return {
        "exp_rate": exp_rate(preds, refs, 0, normalize),
        "exp_rate_le1": exp_rate(preds, refs, 1, normalize),
        "exp_rate_le2": exp_rate(preds, refs, 2, normalize),
        "bleu": bleu(preds, refs, normalize=normalize),
        "edit_distance": mean_normalized_edit_distance(preds, refs, normalize),
        "num_samples": float(len(preds)),
    }
