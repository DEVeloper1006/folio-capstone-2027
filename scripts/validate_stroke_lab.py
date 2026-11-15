#!/usr/bin/env python3
"""Validate a Folio .folioink directory with the shared schema and reference rules.

Uses only the standard library. Implements exactly the schema vocabulary in v1;
unsupported keywords fail closed. Does not decode Apple's native PKDrawing data.
"""
import argparse
import json
import math
from pathlib import Path

SCHEMA = Path(__file__).resolve().parents[1] / "inkpad/inkpad/StrokeLab/stroke-lab-v1.schema.json"
KEYWORDS = {"$schema", "$id", "title", "$defs", "$ref", "type", "const", "properties",
            "required", "additionalProperties", "items", "minItems", "maxItems", "uniqueItems",
            "minLength", "minimum", "exclusiveMinimum", "maximum"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_schema(value, schema, root=None, path="page"):
    root = root or schema
    require(not (set(schema) - KEYWORDS), f"{path}: unsupported schema keyword")
    if "$ref" in schema:
        prefix = "#/$defs/"
        require(schema["$ref"].startswith(prefix), "Unsupported schema reference")
        return check_schema(value, root["$defs"][schema["$ref"][len(prefix):]], root, path)
    if "const" in schema:
        require(value == schema["const"], f"{path}: unexpected constant")
    kind = schema.get("type")
    if kind == "object":
        require(isinstance(value, dict), f"{path}: expected object")
        require(set(schema["required"]) <= value.keys(), f"{path}: missing required field")
        props = schema["properties"]
        if not schema.get("additionalProperties", True):
            require(value.keys() <= props.keys(), f"{path}: unknown field")
        for key, item in value.items():
            if key in props:
                check_schema(item, props[key], root, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(value, list), f"{path}: expected array")
        require(len(value) >= schema.get("minItems", 0), f"{path}: too few elements")
        require(len(value) <= schema.get("maxItems", math.inf), f"{path}: too many elements")
        if schema.get("uniqueItems"):
            require(len({json.dumps(v, sort_keys=True) for v in value}) == len(value), f"{path}: duplicate element")
        for i, item in enumerate(value):
            check_schema(item, schema["items"], root, f"{path}[{i}]")
    elif kind == "string":
        require(isinstance(value, str), f"{path}: expected string")
        require(len(value) >= schema.get("minLength", 0), f"{path}: string too short")
    elif kind in ("number", "integer"):
        require(type(value) in (int, float) and math.isfinite(value), f"{path}: expected finite number")
        if kind == "integer":
            require(value == int(value), f"{path}: expected integer")
        require(value >= schema.get("minimum", -math.inf), f"{path}: below minimum")
        require(value > schema.get("exclusiveMinimum", -math.inf), f"{path}: below exclusive minimum")
        require(value <= schema.get("maximum", math.inf), f"{path}: above maximum")
    else:
        require(kind is None, f"{path}: unsupported schema type")


def validate(raw, annotations, schema=None):
    schema = schema or json.loads(SCHEMA.read_text())
    check_schema({"raw": raw, "annotations": annotations}, schema)
    require(raw["pageID"] == annotations["pageID"], "Page identity mismatch")
    ids = [stroke["id"] for stroke in raw["strokes"]]
    require(len(ids) == len(set(ids)), "Duplicate stroke ID")
    for stroke in raw["strokes"]:
        times = [p["time"] for p in stroke["points"]]
        require(times == sorted(times), "Nonmonotonic point time")
    assigned, groups, all_rows = set(), set(), set()
    for group in annotations["groups"]:
        require(group["id"] not in groups, "Duplicate expression ID")
        groups.add(group["id"])
        members = set(group["strokeIDs"])
        require(members <= set(ids), "Unknown stroke in expression")
        require(not assigned & members, "Stroke in multiple expressions")
        assigned |= members
        rows = {row["id"]: row for row in group["rows"]}
        for row in group["rows"]:
            require(row["id"] not in all_rows, "Duplicate visual row ID")
            all_rows.add(row["id"])
            row_members = set(row["strokeIDs"])
            require(row_members <= members, "Row outside expression")
            visited = {row["id"]}
            parent = row.get("parentRowID")
            while parent is not None:
                require(parent not in visited and parent in rows, "Cyclic or missing row parent")
                visited.add(parent)
                require(row_members <= set(rows[parent]["strokeIDs"]), "Nested row outside ancestor")
                parent = rows[parent].get("parentRowID")
    require(annotations["revision"] == len(annotations["history"]), "Revision count mismatch")
    require([r["number"] for r in annotations["history"]] == list(range(1, annotations["revision"] + 1)), "Nonsequential revisions")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    args = parser.parse_args()
    try:
        native = args.package / "drawing.pkdrawing"
        require(native.is_file() and native.stat().st_size > 0, "Missing native drawing")
        raw = json.loads((args.package / "strokes.json").read_text())
        annotations = json.loads((args.package / "annotations.json").read_text())
        validate(raw, annotations)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Invalid Stroke Lab package: {error}\n")
    print(f"Valid v{raw['schemaVersion']} page: {len(raw['strokes'])} strokes, {len(annotations['groups'])} expressions")
    print("Native file present; native/JSON fidelity is checked by Folio's PencilKit loader.")


if __name__ == "__main__":
    main()
