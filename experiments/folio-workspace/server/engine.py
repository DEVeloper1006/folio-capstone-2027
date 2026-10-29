"""A bounded MathJSON adapter. No eval, sympify strings, or generated code."""
import json
import math
import re
from math import comb
import sys
import sympy as s


class MathError(ValueError):
    pass


def decode(value, depth=0):
    if depth > 32:
        raise MathError("Expression is too deeply nested.")
    if isinstance(value, bool):
        raise MathError("Expected a mathematical expression.")
    if isinstance(value, (int, float)):
        if not math.isfinite(value) or abs(value) > 10**12:
            raise MathError("Numbers must be finite and at most 10^12.")
        return s.Rational(str(value))
    if isinstance(value, dict) and set(value) == {"num"}:
        number = str(value["num"])
        if not re.fullmatch(r"-?\d{1,13}(\.\d{1,16})?([eE][+-]?\d{1,2})?", number):
            raise MathError("Unsupported number.")
        return decode(float(number), depth + 1) if "e" in number.lower() else s.Rational(number)
    if isinstance(value, str):
        constants = {"Pi": s.pi, "ExponentialE": s.E, "ImaginaryUnit": s.I}
        if value in constants:
            return constants[value]
        if not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_]{0,23}", value):
            raise MathError("Use a simple variable name, such as x or theta.")
        if value in {"Nothing", "Undefined", "NaN", "Infinity", "Error", "ComplexInfinity"}:
            raise MathError("Complete the expression before running a command.")
        return s.Symbol(value)
    if not isinstance(value, list) or not value or not isinstance(value[0], str):
        raise MathError("Incomplete or unsupported expression.")
    op, *args = value
    if len(args) > 100:
        raise MathError("Expression has too many terms.")
    if op == "Matrix":
        if not args:
            raise MathError("Enter a matrix first.")
        matrix = decode(args[0], depth + 1)
        if not isinstance(matrix, list) or not matrix or len(matrix) > 8:
            raise MathError("Matrices must contain 1 to 8 rows.")
        if any(not isinstance(row, list) or not row or len(row) > 8 for row in matrix):
            raise MathError("Matrices must contain 1 to 8 columns.")
        if len({len(row) for row in matrix}) != 1:
            raise MathError("Every matrix row must have the same number of columns.")
        return s.Matrix(matrix)
    parsed = [decode(a, depth + 1) for a in args]
    if op in {"List", "Tuple"}:
        return parsed
    if op in {"Add", "Multiply"} and parsed:
        bits = sum(max(int(x.p).bit_length(), int(x.q).bit_length()) for x in parsed if isinstance(x, s.Rational))
        if bits > 4096:
            raise MathError("Exact numbers are too large for this calculation.")
        return (s.Add if op == "Add" else s.Mul)(*parsed)
    binary = {"Subtract": lambda a, b: a - b, "Divide": lambda a, b: a / b,
              "Rational": lambda a, b: a / b}
    if op in binary and len(parsed) == 2:
        if op in {"Divide", "Rational"} and parsed[1] == 0:
            raise MathError("Division by zero is undefined.")
        return binary[op](*parsed)
    if op == "Power" and len(parsed) == 2:
        if parsed[1].is_number and abs(parsed[1]) > 100:
            raise MathError("Exponents larger than 100 are outside the supported range.")
        if isinstance(parsed[0], s.Rational) and isinstance(parsed[1], s.Rational):
            bits = max(int(parsed[0].p).bit_length(), int(parsed[0].q).bit_length())
            if bits * abs(parsed[1]) > 4096:
                raise MathError("This power would produce an excessively large exact number.")
        return parsed[0] ** parsed[1]
    unary = {"Negate": lambda x: -x, "Square": lambda x: x**2, "Sqrt": s.sqrt,
             "Sin": s.sin, "Cos": s.cos, "Tan": s.tan, "Cot": s.cot,
             "Arcsin": s.asin, "Arccos": s.acos, "Arctan": s.atan,
             "Sinh": s.sinh, "Cosh": s.cosh, "Tanh": s.tanh,
             "Exp": s.exp, "Ln": s.log, "Log": s.log, "Abs": s.Abs}
    if op in unary and len(parsed) == 1:
        return unary[op](parsed[0])
    if op == "Log" and len(parsed) == 2:
        return s.log(*parsed)
    if op == "Root" and len(parsed) == 2 and parsed[1] != 0:
        return parsed[0] ** (1 / parsed[1])
    if op == "Equal" and len(parsed) == 2:
        return s.Eq(*parsed, evaluate=False)
    if op == "Delimiter" and len(parsed) == 1:
        return parsed[0]
    raise MathError(f"{op} is not supported by symbolic commands yet. Your expression is still editable.")


def expansion_size(expr):
    """Conservative term budget, before a symbolic expansion can allocate memory."""
    if isinstance(expr, s.MatrixBase):
        return sum(expansion_size(item) for item in expr)
    if isinstance(expr, s.Add):
        size = sum(expansion_size(item) for item in expr.args)
    elif isinstance(expr, s.Mul):
        size = 1
        for item in expr.args:
            size *= expansion_size(item)
            if size > 2000:
                break
    elif isinstance(expr, s.Pow) and expr.exp.is_Integer and expr.exp > 0:
        terms = expansion_size(expr.base)
        if terms > 1 and expr.exp > 100:
            size = 2001
        else:
            size = comb(terms + int(expr.exp) - 1, int(expr.exp)) if terms > 1 else 1
    else:
        size = 1
    if size > 2000:
        raise MathError("This expression expands to too many terms. Work with a smaller expression.")
    return size


def compute(payload):
    if len(json.dumps(payload)) > 24000:
        raise MathError("Expression is too large.")
    expr = decode(payload.get("expression"))
    if isinstance(expr, list):
        raise MathError("Select an expression or a matrix, not a list.")
    if hasattr(expr, "has") and expr.has(s.zoo, s.nan, s.oo, -s.oo):
        raise MathError("The input contains an undefined or non-finite value.")
    expansion_size(expr)
    variable = payload.get("variable", "x")
    if not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_]{0,23}", variable):
        raise MathError("Enter a valid variable name.")
    var = s.Symbol(variable)
    operation = payload.get("operation")
    note = "Computed locally with SymPy."
    if operation == "rref":
        if not isinstance(expr, s.MatrixBase):
            raise MathError("Select a matrix to find its reduced row echelon form.")
        result, pivots = expr.rref()
        note = f"Reduced row echelon form. Rank {len(pivots)}."
        if expr.free_symbols:
            note += " Symbolic pivots may require nonzero assumptions."
    elif operation == "matmul":
        other = decode(payload.get("other"))
        if not isinstance(expr, s.MatrixBase) or not isinstance(other, s.MatrixBase):
            raise MathError("Matrix multiplication needs two matrices.")
        if expr.cols != other.rows:
            raise MathError(f"Incompatible dimensions: {expr.rows}x{expr.cols} and {other.rows}x{other.cols}.")
        result = expr * other
    elif operation == "rowop":
        if not isinstance(expr, s.MatrixBase):
            raise MathError("Row operations require a matrix.")
        source, target = payload.get("row_from", 1) - 1, payload.get("row_to", 2) - 1
        if not 0 <= target < expr.rows or not 0 <= source < expr.rows:
            raise MathError("The selected row is outside this matrix.")
        action = payload.get("row_action", "add")
        result = expr.copy()
        if action == "swap":
            result.row_swap(source, target)
            note = f"Swap R{source + 1} and R{target + 1}."
        elif action in {"scale", "add"}:
            factor = decode(payload.get("other"))
            if not isinstance(factor, s.Rational) or (action == "scale" and factor == 0):
                raise MathError("Use an exact rational factor, nonzero when scaling a row.")
            if action == "scale":
                result.row_op(target, lambda value, column: factor * value)
                note = f"R{target + 1} <- ({factor}) R{target + 1}."
            else:
                if source == target:
                    raise MathError("Choose different source and target rows, or use Scale.")
                result.row_op(target, lambda value, column: value + factor * expr[source, column])
                note = f"R{target + 1} <- R{target + 1} + ({factor}) R{source + 1}."
        else:
            raise MathError("Unknown row operation.")
    elif operation == "derivative":
        if isinstance(expr, s.Equality):
            raise MathError("Select the expression to differentiate, not an equation.")
        result = s.diff(expr, var)
        note = f"Derivative with respect to {variable}."
    elif operation == "integral":
        if isinstance(expr, (s.MatrixBase, s.Equality)):
            raise MathError("Integration expects a scalar expression.")
        result = s.integrate(expr, var)
        if result.has(s.Integral):
            raise MathError("No closed-form antiderivative was found. The original expression is unchanged.")
        constant = "C"
        index = 1
        names = {str(symbol) for symbol in expr.free_symbols} | {variable}
        while constant in names:
            constant = f"C_{index}"
            index += 1
        latex = s.latex(result) + " + " + s.latex(s.Symbol(constant))
        if len(latex) > 20000:
            raise MathError("The result is too large for a document step. Try a smaller expression.")
        return {"latex": latex, "plain": str(result) + " + " + constant, "note": f"Antiderivative with respect to {variable}; {constant} is an arbitrary constant."}
    elif operation in {"simplify", "expand", "factor"}:
        result = {"simplify": s.simplify, "expand": s.expand, "factor": s.factor}[operation](expr)
        note = "Symbolic result; check the original expression's domain restrictions."
    elif operation == "substitute":
        other = decode(payload.get("other"))
        if isinstance(other, (list, s.MatrixBase, s.Equality)):
            raise MathError("Substitution expects a scalar expression.")
        result = expr.subs(var, other)
        note = f"Substituted {variable}; the original step is preserved."
    elif operation == "check":
        other = decode(payload.get("other"))
        if isinstance(expr, s.Equality) or isinstance(other, s.Equality):
            raise MathError("Equivalence checking currently compares expressions, not full equations.")
        difference = s.simplify(expr - other)
        equivalent = difference == 0 or (isinstance(difference, s.MatrixBase) and difference.is_zero_matrix is True)
        return {"equivalent": bool(equivalent), "note": "Symbolically equivalent where both expressions are defined." if equivalent else "Could not establish equivalence. Check the expressions and their domains."}
    else:
        raise MathError("Unknown command.")
    if hasattr(result, "has") and result.has(s.zoo, s.nan, s.oo, -s.oo):
        raise MathError("The result is undefined or non-finite.")
    latex = s.latex(result, mat_delim="[", mat_str="matrix")
    if len(latex) > 20000:
        raise MathError("The result is too large for a document step. Try a smaller expression.")
    return {"latex": latex, "plain": str(result), "note": note}


if __name__ == "__main__":
    try:
        import resource
        resource.setrlimit(resource.RLIMIT_CPU, (5, 6))
    except (ImportError, ValueError, OSError):
        pass
    try:
        print(json.dumps(compute(json.load(sys.stdin))))
    except Exception as exc:
        print(json.dumps({"error": str(exc) if isinstance(exc, MathError) else "This expression could not be computed. Check its structure and dimensions."}))
