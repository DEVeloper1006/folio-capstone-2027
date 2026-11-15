#!/usr/bin/env python3
"""Compare compiled Swift with the existing SymPy engine; development only."""
import argparse
import importlib.util
import json
from pathlib import Path
import random
import subprocess
import sympy as s

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--binary", type=Path, required=True)
parser.add_argument("--engine", type=Path, required=True)
parser.add_argument("--report", type=Path)
args = parser.parse_args()
spec = importlib.util.spec_from_file_location("folio_reference_engine", args.engine)
engine = importlib.util.module_from_spec(spec); spec.loader.exec_module(engine)
x, t, y, C = s.symbols("x t y C")
cases = [("x^2+3x+2", x*x+3*x+2, x),
    (r"\int (t^{2}+3t+2)\,dt", t*t+3*t+2, t),
    (r"\int \frac{y+1}{2}\,\mathrm{d}y", (y+1)/2, y),
    ("-x^2", -x*x, x), ("(-x)^2", x*x, x),
    ("0.1x+0.25", x/10+s.Rational(1,4), x), ("C^2", C*C, C),
    ("0", s.Integer(0), t), ("7", s.Integer(7), y),
    (r"\left(x+1\right)(x-1)", x*x-1, x), ("x^{20}", x**20, x)]
rng = random.Random(71)
for _ in range(120):
    variable = rng.choice([x,t,y]); degree = rng.randrange(1,9)
    coefficients = [rng.randrange(-8,9) for _ in range(degree+1)]
    expression = sum(s.Rational(c)*variable**i for i,c in enumerate(coefficients))
    latex = "+".join(f"({c}){variable}^{{{i}}}" for i,c in enumerate(coefficients))
    cases.append((latex, expression, variable))
for _ in range(30):
    a,b,c = [rng.randrange(-5,6) for _ in range(3)]
    cases.append((f"({a}x+{b})(x+{c})", (a*x+b)*(x+c), x))
invalid = ["", "x+y", "1/x", r"\sin{x}", r"\int_0^1 x dx", "x^{-1}", "x^{21}",
    "(x^2+1)^{20}", "1/0", "x+", r"\int x", r"\int x dy", r"\left x", "(x}",
    "0^0", "9"*40, "("*100+"x"+")"*100, "x"*5001,
    "999999999999999999*999999999999999999x"]
requests = [{"latex": latex, "variable": str(var)} for latex,_,var in cases]+[{"latex": text} for text in invalid]
process = subprocess.run([str(args.binary.resolve())], input="".join(json.dumps(row)+"\n" for row in requests),
                         capture_output=True, text=True, check=True)
answers = [json.loads(line) for line in process.stdout.splitlines()]
assert len(answers) == len(requests)
def native(value, variable):
    return sum(s.Rational(c["numerator"], c["denominator"])*variable**int(d) for d,c in value["coefficients"].items())
def mathjson(expression, variable):
    terms = []
    for (degree,), coefficient in s.Poly(s.expand(expression), variable).terms():
        coefficient = s.Rational(coefficient)
        number = ["Rational", int(coefficient.p), int(coefficient.q)]
        terms.append(number if degree == 0 else ["Multiply", number, ["Power", str(variable), degree]])
    return ["Add", *terms]
for (latex, expected, var), actual in zip(cases, answers):
    assert "error" not in actual, (latex, actual)
    assert s.expand(native(actual["integrand"], var)-expected) == 0, latex
    integrated = native(actual["antiderivative"], var)
    assert s.expand(s.diff(integrated,var)-expected) == 0, latex
    reference = engine.compute({"operation":"integral", "expression":mathjson(expected,var), "variable":str(var)})
    constant = s.Symbol("C_1" if str(var)=="C" else "C")
    parsed_reference = s.sympify(reference["plain"], locals={str(var):var,str(constant):constant})
    assert s.simplify(parsed_reference-constant-integrated) == 0, (latex, reference, actual)
for text, actual in zip(invalid, answers[len(cases):]):
    assert "error" in actual, (text,actual)
report = {"native_supported_cases":len(cases),"sympy_oracle_matches":len(cases),"invalid_cases_rejected":len(invalid),
          "physical_device":False,"model_inference":False,"seed":71}
if args.report:
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps(report,indent=2))
