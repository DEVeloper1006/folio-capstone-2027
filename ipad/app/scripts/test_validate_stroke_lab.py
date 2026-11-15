"""Synthetic contract cases; no personal handwriting fixtures."""
import copy
import json
import unittest
from validate_stroke_lab import validate, SCHEMA


def fixture():
    raw = dict(schemaVersion="1.0.0", pageID="synthetic", coordinateSystem="pencilkit-points-top-left-y-down",
               pointSpace="stroke-local", timeUnit="seconds", creationTimeEpoch="unix", identityStrategy="sha256-path-v1",
               canvasWidth=1024, canvasHeight=1366, strokes=[])
    annotations = dict(schemaVersion="1.0.0", pageID="synthetic", revision=0, groups=[], history=[])
    return raw, annotations


def stroke(identity="s1"):
    return dict(id=identity, createdAt=1700000000, points=[dict(x=10, y=20, time=0, width=2, height=2, opacity=1)],
                transform=dict(a=1, b=0, c=0, d=1, tx=0, ty=0), bounds=dict(x=9, y=19, width=2, height=2),
                ink=dict(type="pen", rgba=[0, 0, 0, 1]), randomSeed=42)


class ValidatorTests(unittest.TestCase):
    def test_empty_and_single(self):
        raw, annotations = fixture()
        validate(raw, annotations)
        raw["strokes"] = [stroke()]
        validate(raw, annotations)

    def test_required_fields_and_unknown_version(self):
        raw, annotations = fixture()
        for key in raw:
            damaged = dict(raw)
            damaged.pop(key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(damaged, annotations)
        raw["schemaVersion"] = "2.0.0"
        with self.assertRaises(ValueError): validate(raw, annotations)

    def test_references_and_exclusive_membership(self):
        raw, annotations = fixture()
        raw["strokes"] = [stroke()]
        group = dict(id="g1", label="Expression", strokeIDs=["s1"], rows=[])
        annotations["groups"] = [group]
        validate(raw, annotations)
        annotations["groups"].append(dict(group, id="g2"))
        with self.assertRaises(ValueError): validate(raw, annotations)
        annotations["groups"] = [dict(group, strokeIDs=["missing"])]
        with self.assertRaises(ValueError): validate(raw, annotations)

    def test_nested_rows_cycles_and_containment(self):
        raw, annotations = fixture()
        raw["strokes"] = [stroke()]
        parent = dict(id="r1", label="Parent", strokeIDs=["s1"])
        child = dict(id="r2", label="Child", strokeIDs=["s1"], parentRowID="r1")
        annotations["groups"] = [dict(id="g1", label="Expression", strokeIDs=["s1"], rows=[parent, child])]
        validate(raw, annotations)
        child["parentRowID"] = "r2"
        with self.assertRaises(ValueError): validate(raw, annotations)
        child["parentRowID"] = "missing"
        with self.assertRaises(ValueError): validate(raw, annotations)
        child["parentRowID"] = "r1"
        parent["strokeIDs"] = []
        with self.assertRaises(ValueError): validate(raw, annotations)

    def test_invalid_geometry_timing_and_duplicates(self):
        raw, annotations = fixture()
        raw["strokes"] = [stroke()]
        for key, value in [("time", -1), ("x", float("nan")), ("opacity", 2), ("width", True)]:
            invalid = copy.deepcopy(raw)
            invalid["strokes"][0]["points"][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): validate(invalid, annotations)
        raw["strokes"].append(stroke())
        with self.assertRaises(ValueError): validate(raw, annotations)
        raw["strokes"] = [stroke()]
        raw["strokes"][0]["points"] *= 2
        raw["strokes"][0]["points"][0] = dict(raw["strokes"][0]["points"][0], time=1)
        with self.assertRaises(ValueError): validate(raw, annotations)

    def test_revision_provenance(self):
        raw, annotations = fixture()
        annotations["revision"] = 1
        with self.assertRaises(ValueError): validate(raw, annotations)
        annotations["history"] = [dict(number=1, timestamp=1700000000, author="test", source="manual-stroke-lab", action="Create expression")]
        validate(raw, annotations)
        annotations["history"][0]["author"] = ""
        with self.assertRaises(ValueError): validate(raw, annotations)

    def test_unknown_fields_and_schema_vocabulary(self):
        raw, annotations = fixture()
        raw["unknown"] = True
        with self.assertRaises(ValueError): validate(raw, annotations)
        raw.pop("unknown")
        schema = json.loads(SCHEMA.read_text())
        schema["notImplemented"] = True
        with self.assertRaises(ValueError): validate(raw, annotations, schema)


if __name__ == "__main__":
    unittest.main()
