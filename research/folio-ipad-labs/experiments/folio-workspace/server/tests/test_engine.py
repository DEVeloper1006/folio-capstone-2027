import pytest
import sympy as s
from server.engine import MathError, compute, decode


def matrix(rows):
    return ["Matrix", ["List", *[["List", *row] for row in rows]], "'[]'"]


def run(operation, expression, **kwargs):
    return compute({"operation": operation, "expression": expression, **kwargs})


def test_rref_exact_solution():
    result = run("rref", matrix([[1, 2, -1, 3], [2, 1, 1, 6], [-1, 1, 2, 1]]))
    assert result["plain"] == "Matrix([[1, 0, 0, 2], [0, 1, 0, 1], [0, 0, 1, 1]])"
    assert "Rank 3" in result["note"]


def test_rref_rank_deficient():
    assert "Rank 1" in run("rref", matrix([[1, 2], [2, 4]]))["note"]


def test_rref_fractions_are_exact():
    assert "1/3" in run("rref", matrix([[3, 1]]))["plain"]


def test_matmul():
    assert run("matmul", matrix([[1, 2], [3, 4]]), other=matrix([[2], [1]]))["plain"] == "Matrix([[4], [10]])"


def test_matmul_incompatible():
    with pytest.raises(MathError, match="Incompatible"):
        run("matmul", matrix([[1, 2]]), other=matrix([[1, 2]]))


def test_product_rule():
    result = run("derivative", ["Multiply", ["Power", "x", 2], ["Sin", "x"]])
    assert result["plain"] == "x**2*cos(x) + 2*x*sin(x)"


def test_derivative_other_variable():
    assert run("derivative", ["Multiply", "x", ["Power", "y", 2]], variable="y")["plain"] == "2*x*y"


def test_integral_constant():
    result = run("integral", ["Add", ["Multiply", 3, ["Power", "x", 2]], ["Multiply", 2, "x"], 1])
    assert result["plain"] == "x**3 + x**2 + x + C"
    assert result["latex"].endswith(" + C")


def test_integration_constant_does_not_collide_with_a_parameter():
    result = run("integral", ["Multiply", "C", "x"])
    assert result["plain"] == "C*x**2/2 + C_1"


def test_nonfinite_input_cannot_become_a_finite_derivative():
    with pytest.raises(MathError, match="non-finite"):
        run("derivative", ["Tan", ["Divide", "Pi", 2]])


def test_symbolic_matrix_warns_about_pivot_assumptions():
    assert "nonzero assumptions" in run("rref", matrix([["x", 1]]))["note"]


def test_simplify_trig():
    assert run("simplify", ["Add", ["Power", ["Sin", "x"], 2], ["Power", ["Cos", "x"], 2]])["plain"] == "1"


def test_expand():
    assert run("expand", ["Power", ["Add", "x", 1], 2])["plain"] == "x**2 + 2*x + 1"


def test_factor():
    assert run("factor", ["Subtract", ["Power", "x", 2], 1])["plain"] == "(x - 1)*(x + 1)"


def test_substitute():
    assert run("substitute", ["Add", ["Power", "x", 2], 1], variable="x", other=3)["plain"] == "10"


def test_equivalence_and_domain_warning():
    result = run("check", ["Power", ["Add", "x", 1], 2], other=["Add", ["Power", "x", 2], ["Multiply", 2, "x"], 1])
    assert result["equivalent"]
    assert "where both expressions are defined" in result["note"]


def test_unestablished_is_not_claimed_false():
    result = run("check", "x", other=["Power", "x", 2])
    assert not result["equivalent"]
    assert "Could not establish" in result["note"]


def test_matrix_equivalence():
    assert run("check", matrix([[1, 2]]), other=matrix([[1, 2]]))["equivalent"]


@pytest.mark.parametrize("bad", [None, True, {}, {"foo": "bar"}, ["Error", "x"], "__import__('os')", ["Run", "x"], "Infinity", float('inf'), ["Rational", 1, 0], ["Power", 2, 1000]])
def test_invalid_or_unsafe_input(bad):
    with pytest.raises((MathError, ValueError)):
        run("simplify", bad)


def test_depth_limit():
    value = "x"
    for _ in range(35):
        value = ["Sin", value]
    with pytest.raises(MathError, match="deeply"):
        run("simplify", value)


def test_ragged_matrix():
    with pytest.raises(MathError, match="same number"):
        decode(matrix([[1, 2], [3]]))


def test_large_matrix():
    with pytest.raises(MathError, match="1 to 8"):
        decode(matrix([[1] * 9]))


def test_equations_not_differentiated_silently():
    with pytest.raises(MathError, match="not an equation"):
        run("derivative", ["Equal", "y", ["Power", "x", 2]])


@pytest.mark.parametrize("action,source,target,factor,expected", [
    ("swap", 1, 2, None, "Matrix([[3, 4], [1, 2]])"),
    ("scale", 1, 2, ["Rational", 1, 2], "Matrix([[1, 2], [3/2, 2]])"),
    ("add", 1, 2, -3, "Matrix([[1, 2], [0, -2]])"),
])
def test_row_operations(action, source, target, factor, expected):
    result = run("rowop", matrix([[1, 2], [3, 4]]), row_action=action, row_from=source, row_to=target, other=factor)
    assert result["plain"] == expected
    assert "R" in result["note"]


def test_zero_row_scaling_rejected():
    with pytest.raises(MathError, match="nonzero"):
        run("rowop", matrix([[1, 2], [3, 4]]), row_action="scale", row_to=1, other=0)


def test_same_row_addition_rejected():
    with pytest.raises(MathError, match="different"):
        run("rowop", matrix([[1, 2], [3, 4]]), row_action="add", row_from=1, row_to=1, other=2)


def test_out_of_bounds_row_rejected():
    with pytest.raises(MathError, match="outside"):
        run("rowop", matrix([[1, 2], [3, 4]]), row_action="swap", row_from=1, row_to=4)


def test_nested_numeric_power_budget():
    value = ["Power", ["Power", 2, 100], 100]
    with pytest.raises(MathError, match="large exact number"):
        run("simplify", value)


def test_combinatorial_expansion_budget():
    value = ["Power", ["Add", "x", "y", "z", "a", "b"], 50]
    with pytest.raises(MathError, match="too many terms"):
        run("expand", value)


def test_unknown_operation():
    with pytest.raises(MathError, match="Unknown command"):
        run("exec", "x")
