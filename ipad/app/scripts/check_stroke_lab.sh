#!/bin/sh
# Run from any directory on macOS with Xcode's command-line tools installed.
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/folio-lab-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
lab_dir="$repo_dir/inkpad/inkpad/StrokeLab"
cp "$lab_dir/stroke-lab-v1.schema.json" "$check_dir/"
xcrun swiftc -module-cache-path "$check_dir/module-cache" \
    "$lab_dir/StrokeLabContract.swift" "$lab_dir/StrokeLabSchema.swift" \
    "$lab_dir/StrokeLabDocument.swift" "$repo_dir/scripts/StrokeLabSmoke.swift" \
    -o "$check_dir/check"
"$check_dir/check" "$check_dir/synthetic.folioink"
python3 "$repo_dir/scripts/validate_stroke_lab.py" "$check_dir/synthetic.folioink"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$repo_dir/scripts" -p 'test_validate_stroke_lab.py' -v
