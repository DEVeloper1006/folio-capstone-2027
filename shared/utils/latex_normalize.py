"""LaTeX string normalization so that cosmetically different outputs compare equal."""

from __future__ import annotations

import re

# Aliases mapped to a single canonical form. Order matters: longer keys first.
LATEX_ALIASES: dict[str, str] = {
    r"\dfrac": r"\frac",
    r"\tfrac": r"\frac",
    r"\le": r"\leq",
    r"\ge": r"\geq",
    r"\ne": r"\neq",
    r"\to": r"\rightarrow",
    r"\gets": r"\leftarrow",
    r"\lbrace": r"\{",
    r"\rbrace": r"\}",
    r"\lvert": "|",
    r"\rvert": "|",
    r"\vert": "|",
    r"\ast": "*",
    r"\colon": ":",
}

# Sizing / spacing commands that carry no semantic content.
_DROP_COMMANDS: tuple[str, ...] = (
    r"\left",
    r"\right",
    r"\displaystyle",
    r"\textstyle",
    r"\limits",
    r"\bigl",
    r"\bigr",
    r"\Bigl",
    r"\Bigr",
    r"\big",
    r"\Big",
)
_NULL_DELIM_RE = re.compile(r"\\(?:left|right)\.")
_SPACING_RE = re.compile(r"(?<!\\)\\[,;:! ]|\\quad|\\qquad|~")
_MATH_DELIMS_RE = re.compile(r"^\s*(\$\$|\$|\\\[|\\\()|(\$\$|\$|\\\]|\\\))\s*$")
_WHITESPACE_RE = re.compile(r"\s+")


def _replace_command(s: str, old: str, new: str) -> str:
    """Replace a control word only when it is not a prefix of a longer command."""
    return re.sub(re.escape(old) + r"(?![a-zA-Z])", lambda _: new, s)


def strip_math_delimiters(s: str) -> str:
    """Remove surrounding $...$, $$...$$, \\[...\\], \\(...\\)."""
    prev = None
    while prev != s:
        prev = s
        s = _MATH_DELIMS_RE.sub("", s)
    return s


def normalize_latex(s: str) -> str:
    """Canonicalize a LaTeX string for comparison.

    Strips math delimiters, drops sizing/spacing commands, maps common aliases
    to one form, and collapses whitespace.
    """
    s = strip_math_delimiters(s.strip())
    s = _NULL_DELIM_RE.sub(" ", s)
    s = _SPACING_RE.sub(" ", s)
    for cmd in _DROP_COMMANDS:
        s = _replace_command(s, cmd, " ")
    for old, new in sorted(LATEX_ALIASES.items(), key=lambda kv: -len(kv[0])):
        s = _replace_command(s, old, new)
    s = _WHITESPACE_RE.sub(" ", s).strip()
    return s
