"""Original expression generators, organized by an Ontario-inspired scope.
These are notation examples, not copied curriculum questions or worked answers.
"""
from dataclasses import dataclass
from fractions import Fraction
import random

@dataclass(frozen=True)
class Family:
    name: str
    band: str
    topic: str
    pattern: str
    numeric: bool = False

FAMILIES = [
    Family('whole_numbers','K-3','Number sense',r'{a}{b}{c}',True),
    Family('addition','K-3','Arithmetic',r'{a}+{b}={sum}',True),
    Family('subtraction','K-3','Arithmetic',r'{sum}-{a}={b}',True),
    Family('multiplication','3-6','Arithmetic',r'{a}\times{b}={product}',True),
    Family('division','3-6','Arithmetic',r'{product}\div{a}={b}',True),
    Family('comparison','K-3','Ordering',r'{a}<{sum}',True),
    Family('missing_value','K-3','Patterns and equality',r'\square+{a}={sum}'),
    Family('decimal_addition','3-6','Decimals',r'{a}.{b}+0.{c}',True),
    Family('rounding','3-6','Estimation',r'{a}.{b}\approx{rounded}',True),
    Family('fractions','3-6','Fractions',r'\frac{{{a}}}{{{sum}}}',True),
    Family('mixed_numbers','3-6','Fractions',r'{c}\frac{{{a}}}{{{sum}}}',True),
    Family('equivalent_fractions','3-6','Fractions',r'\frac{{{a}}}{{{b}}}=\frac{{{twicea}}}{{{twiceb}}}',True),
    Family('fraction_arithmetic','6-8','Rational numbers',r'\frac{{{a}}}{{{b}}}+\frac{{{c}}}{{{d}}}',True),
    Family('percentages','6-8','Percent and proportionality',r'{a}{b}\%',True),
    Family('ratios','6-8','Ratios',r'{a}:{b}={twicea}:{twiceb}',True),
    Family('proportions','6-8','Proportionality',r'\frac{{x}}{{{a}}}=\frac{{{b}}}{{{c}}}'),
    Family('integers','6-8','Signed arithmetic',r'(-{a})+{b}',True),
    Family('order_operations','6-8','Arithmetic',r'{a}+{b}({c}-{d})',True),
    Family('numeric_powers','6-8','Powers',r'{a}^{{{p}}}',True),
    Family('numeric_roots','6-8','Roots',r'\sqrt{{{square}}}={a}',True),
    Family('absolute_value','6-8','Number sense',r'|-{a}|={a}',True),
    Family('scientific_notation','9-10','Scientific notation',r'{a}.{b}\times10^{{-{p}}}',True),
    Family('unit_conversion','3-6','Measurement',r'{a}\,\mathrm{{m}}={hundreda}\,\mathrm{{cm}}'),
    Family('money','3-6','Financial literacy',r'\${a}.{b}0+\${c}.{d}0'),
    Family('rectangle_area','3-6','Geometry and measurement',r'A={a}\times{b}={product}'),
    Family('perimeter','3-6','Geometry and measurement',r'P=2({a}+{b})'),
    Family('triangle_area','6-8','Geometry and measurement',r'A=\frac{{1}}{{2}}({a})({b})'),
    Family('circle','6-8','Geometry and measurement',r'A=\pi({a})^2'),
    Family('volume','6-8','Geometry and measurement',r'V=\pi({a})^2({b})'),
    Family('angles','3-6','Angles',r'{angle}^\circ+{otherangle}^\circ=180^\circ',True),
    Family('pythagorean','6-8','Geometry',r'c^2={a}^2+{b}^2'),
    Family('linear_equations','6-8','Algebra',r'{a}x+{b}={sum}'),
    Family('inequalities','9-10','Algebra',r'{a}x-{b}\leq{c}'),
    Family('numeric_inequalities','6-8','Ordering',r'-{a}\leq{b}',True),
    Family('substitution','6-8','Algebra',r'y={a}({b})+{c}'),
    Family('slope','9-10','Analytic geometry',r'm=\frac{{{a}-{b}}}{{{c}-{d}}}'),
    Family('line_equation','9-10','Analytic geometry',r'y={a}x-{b}'),
    Family('coordinates','6-8','Coordinate geometry',r'P=({a},-{b})'),
    Family('distance','9-10','Analytic geometry',r'd=\sqrt{{({a}-{b})^2+({c}-{d})^2}}'),
    Family('linear_system','9-10','Systems',r'\begin{{cases}}{a}x+y={b}\\x-{c}y={d}\end{{cases}}'),
    Family('polynomials','9-10','Polynomials',r'{a}x^2+{b}x-{c}'),
    Family('binomial_product','9-10','Factoring',r'(x+{a})(x-{b})'),
    Family('difference_squares','9-10','Factoring',r'x^2-{square}=(x-{a})(x+{a})'),
    Family('quadratic_vertex','9-10','Quadratics',r'y={a}(x-{b})^2+{c}'),
    Family('quadratic_formula','9-10','Quadratics',r'x=\frac{{-{b}\pm\sqrt{{{b}^2-4({a})({c})}}}}{{2({a})}}'),
    Family('radical_operations','11-12','Radicals',r'{a}\sqrt{{{b}}}+{c}\sqrt{{{b}}}'),
    Family('rational_expressions','11-12','Rational functions',r'\frac{{x+{a}}}{{x^2-{square}}}'),
    Family('negative_exponents','9-10','Exponents',r'({a}x)^{{-{p}}}=\frac{{1}}{{({a}x)^{{{p}}}}}'),
    Family('rational_exponents','11-12','Exponents',r'x^{{\frac{{{a}}}{{{b}}}}}'),
    Family('function_notation','11-12','Functions',r'f({a})={a}^2+{b}'),
    Family('domain_range','11-12','Functions',r'D=\{{x\in\mathbb{{R}}\mid x\ne{a}\}}'),
    Family('intervals','11-12','Functions',r'(-\infty,{a}]\cup[{sum},\infty)'),
    Family('piecewise','11-12','Functions',r'f(x)=\begin{{cases}}x+{a}&x\geq0\\{b}x&x<0\end{{cases}}'),
    Family('inverse_functions','11-12','Functions',r'f^{{-1}}(x)=\frac{{x-{b}}}{{{a}}}'),
    Family('composition','11-12','Functions',r'(f\circ g)(x)=({a}x+{b})^2'),
    Family('exponential_functions','11-12','Exponentials',r'y={a}({b})^x'),
    Family('logarithms','11-12','Logarithms',r'\log_{{{a}}}({product})'),
    Family('natural_logs','11-12','Logarithms',r'\ln(x+{a})={b}'),
    Family('right_triangle_trig','9-10','Trigonometry',r'\sin\theta=\frac{{{a}}}{{{sum}}}'),
    Family('radians','11-12','Trigonometry',r'\theta=\frac{{{a}\pi}}{{{b}}}'),
    Family('trig_functions','11-12','Trigonometry',r'y={a}\sin({b}x-{c})+{d}'),
    Family('sine_law','11-12','Trigonometry',r'\frac{{{a}}}{{\sin A}}=\frac{{{b}}}{{\sin B}}'),
    Family('cosine_law','11-12','Trigonometry',r'c^2={a}^2+{b}^2-2({a})({b})\cos C'),
    Family('arithmetic_sequences','11-12','Sequences',r'a_n={a}+(n-1){b}'),
    Family('geometric_sequences','11-12','Sequences',r'a_n={a}({b})^{{n-1}}'),
    Family('summation','11-12','Sequences and data',r'\sum_{{k=1}}^{{{n}}}k^2'),
    Family('simple_interest','9-10','Financial mathematics',r'I={principal}({rate})({p})'),
    Family('compound_interest','11-12','Financial mathematics',r'A={principal}(1+{rate})^{{{n}}}'),
    Family('annuity','11-12','Financial mathematics',r'FV={principal}\frac{{(1+{rate})^{{{n}}}-1}}{{{rate}}}'),
    Family('mean','6-8','Data and statistics',r'\bar{{x}}=\frac{{{a}+{b}+{c}}}{{3}}'),
    Family('probability','6-8','Probability',r'P(A)=\frac{{{a}}}{{{sum}}}'),
    Family('set_probability','11-12','Probability',r'P(A_{{{n}}}\cup B)=P(A_{{{n}}})+P(B)-P(A_{{{n}}}\cap B)'),
    Family('conditional_probability','11-12','Probability',r'P(A_{{{n}}}\mid B)=\frac{{P(A_{{{n}}}\cap B)}}{{P(B)}}\quad P(B)>{rate}'),
    Family('factorials','11-12','Counting',r'{n}!',True),
    Family('combinations','11-12','Counting',r'\binom{{{n}}}{{{p}}}'),
    Family('permutations','11-12','Counting',r'P({n},{p})=\frac{{{n}!}}{{({n}-{p})!}}'),
    Family('binomial_distribution','11-12','Probability distributions',r'P(X={p})=\binom{{{n}}}{{{p}}}({rate})^{{{p}}}(1-{rate})^{{{n}-{p}}}'),
    Family('standardization','11-12','Statistics',r'z=\frac{{x-{a}}}{{{b}}}'),
    Family('variance','11-12','Statistics',r's^2=\frac{{\sum_{{i=1}}^{{{n}}}(x_i-\bar{{x}})^2}}{{{n}-1}}'),
    Family('limits','11-12','Calculus',r'\lim_{{x\to{a}}}\frac{{x^2-{square}}}{{x-{a}}}'),
    Family('derivatives','11-12','Calculus',r'\frac{{d}}{{dx}}({a}x^{{{p}}})={derivative}x^{{{pm1}}}'),
    Family('derivative_notation','11-12','Calculus',r'f^\prime(x)={a}x^2+{b}'),
    Family('tangent_line','11-12','Calculus',r'y-{b}={a}(x-{c})'),
    Family('vector_components','11-12','Vectors',r'\vec{{v}}=\langle{a},-{b},{c}\rangle'),
    Family('vector_magnitude','11-12','Vectors',r'\|\vec{{v}}\|=\sqrt{{{a}^2+{b}^2+{c}^2}}'),
    Family('dot_product','11-12','Vectors',r'\vec{{u}}\cdot\vec{{v}}={a}({b})+{c}({d})'),
    Family('vector_line','11-12','Vectors',r'\vec{{r}}=({a},{b},{c})+t(1,{d},2)'),
    Family('plane_equation','11-12','Vectors',r'{a}x+{b}y-{c}z={d}'),
    # Explicit extensions for other Grade 12 programs, not Ontario core claims.
    Family('matrices','extension','Matrices',r'\begin{{pmatrix}}{a}&{b}\\{c}&{d}\end{{pmatrix}}'),
    Family('definite_integrals','extension','Integration',r'\int_0^{{{a}}}x^{{{p}}}\,dx'),
    Family('complex_numbers','extension','Complex numbers',r'z={a}+{b}i'),
]


def generate(family: Family, rng: random.Random) -> str:
    a,b,c,d = rng.sample(range(1, 50), 4)
    p = rng.randint(2, 8)
    values=dict(a=a,b=b,c=c,d=d,p=p,pm1=p-1,n=rng.randint(10,90),sum=a+b,product=a*b,
                square=a*a,derivative=a*p,rounded=a+(1 if int(str(b)[0])>=5 else 0),twicea=2*a,twiceb=2*b,hundreda=100*a,angle=a*3,otherangle=180-a*3,
                principal=rng.randint(10,999)*100,rate=f'0.{rng.randint(1,9):02d}')
    return family.pattern.format(**values)
