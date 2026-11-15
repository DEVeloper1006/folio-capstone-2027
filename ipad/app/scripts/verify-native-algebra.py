#!/usr/bin/env python3
"""Deterministic algebra/matrix-space oracle. Requires an existing SymPy install.
No network, notebook access, or repository writes; Swift builds are temporary.
"""
import importlib.util,json,random,re,subprocess,tempfile
from pathlib import Path
import sympy as sp
from sympy.parsing.sympy_parser import parse_expr,standard_transformations,implicit_multiplication_application
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('native_oracle',ROOT/'scripts/verify-native-math.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
x=sp.Symbol('x')

def group(text,index):
    assert text[index]=='{',(text,index)
    depth=1;end=index+1
    while depth:
        if text[end]=='{':depth+=1
        if text[end]=='}':depth-=1
        end+=1
    return text[index+1:end-1],end

def expression(tex):
    tex=tex.replace(r'\left','').replace(r'\right','').replace(r'\cdot','*')
    while r'\frac' in tex:
        start=tex.index(r'\frac');a,end=group(tex,start+5);b,last=group(tex,end)
        tex=tex[:start]+'('+expression_text(a)+')/('+expression_text(b)+')'+tex[last:]
    tex=tex.replace('^','**').replace('{','(').replace('}',')')
    assert re.fullmatch(r'[x0-9+*/().\-\s]+',tex),tex
    return parse_expr(tex,local_dict={'x':x},transformations=standard_transformations+(implicit_multiplication_application,))

def expression_text(tex):return str(expression(tex))
def roots(tex):
    if tex==r'\varnothing':return sp.EmptySet
    if tex==r'x \in \mathbb{R}':return sp.S.Reals
    if tex.startswith(r'x \in \left\{'):
        text=tex.removeprefix(r'x \in \left\{').removesuffix(r'\right\}')
        return sp.FiniteSet(*(expression(a) for a in text.split(',')))
    text=tex.removeprefix('x = ')
    if r'\pm' not in text:return sp.FiniteSet(expression(text))
    numerator,end=group(text,5);denominator,_=group(text,end)
    negative_b,radical=numerator.split(r'\pm')
    d,_=group(radical.strip(),5)
    return sp.FiniteSet((expression(negative_b)+sp.sqrt(expression(d)))/expression(denominator),(expression(negative_b)-sp.sqrt(expression(d)))/expression(denominator))

def main():
    rng=random.Random(20261112);cases=[]
    def add(op,a,expected,b='',kind='expression',point='2'):
        req=base.request(op,a,b);req['point']=point;cases.append((req,expected,kind))
    def text(p):return str(sp.expand(p)).replace('**','^')
    for _ in range(50):
        a=sum(sp.Rational(rng.randint(-4,4),rng.randint(1,4))*x**i for i in range(rng.randint(1,5)+1))
        b=sum(rng.randint(-3,3)*x**i for i in range(rng.randint(1,3)+1)) or sp.Integer(1)
        for op,expected in [('polynomialAdd',a+b),('polynomialSubtract',a-b),('polynomialMultiply',a*b),('polynomialDivide',a/b),('simplify',a)]:add(op,text(a),expected,text(b))
        add('equivalent',text(a),r'\text{Equivalent}',text(a),kind='literal')
        factored=sp.Integer(rng.choice([1,2,-1,-2]))
        for _ in range(rng.randint(1,5)):factored*=rng.randint(1,3)*x-rng.randint(-3,3)
        add('factor',text(factored),factored)
    for _ in range(100):
        a,b,c=[sp.Rational(rng.randint(-6,6),rng.randint(1,3)) for _ in range(3)]
        p=a*x*x+b*x+c;offset=rng.randint(-4,4)
        add('solveEquation',text(p+offset)+'='+str(offset),sp.solveset(p,x,domain=sp.S.Reals),kind='roots')
    for _ in range(20):
        a,b,c=rng.randint(-9,9),rng.randint(1,9),rng.randint(1,9)
        add('arithmetic',f'({a}/{b}+{c})/2',(sp.Rational(a,b)+c)/2)
    for _ in range(35):
        r,c=rng.randint(1,4),rng.randint(1,4)
        a=sp.Matrix(r,c,lambda i,j:rng.randint(-3,3));reduced,pivots=a.rref()
        add('matrixScale',base.text(a),a*sp.Rational(-2,3),kind='matrix',point='-2/3')
        for op,vectors in [('nullspace',a.nullspace()),('columnSpace',a.columnspace())]:
            expected=sp.Matrix.hstack(*vectors) if vectors else r'\varnothing'
            add(op,base.text(a),expected,kind='matrix' if vectors else 'literal')
        expected=reduced[:len(pivots),:] if pivots else r'\varnothing'
        add('rowSpace',base.text(a),expected,kind='matrix' if pivots else 'literal')
        if r==c:
            add('trace',base.text(a),sp.trace(a))
            add('matrixPower',base.text(a),a**3,kind='matrix',point='3')
            if a.det()!=0:add('matrixPower',base.text(a),a**-2,kind='matrix',point='-2')
    with tempfile.TemporaryDirectory(prefix='folio-algebra-oracle-') as tmp:
        tmp=Path(tmp);(tmp/'Main.swift').write_text(base.MAIN)
        source=ROOT/'inkpad/inkpad/Services'
        subprocess.run(['swiftc','-O','-module-cache-path',str(tmp/'cache'),*[str(source/name) for name in ['PolynomialIntegrationService.swift','MathComputationService.swift','PolynomialIntegralInput.swift','AlgebraComputationService.swift']],str(tmp/'Main.swift'),'-o',str(tmp/'oracle')],check=True)
        run=subprocess.run([str(tmp/'oracle')],input='\n'.join(json.dumps(req) for req,_,_ in cases)+'\n',capture_output=True,text=True,check=True)
        lines=run.stdout.splitlines();assert len(lines)==len(cases)
        for index,((req,expected,kind),line) in enumerate(zip(cases,lines)):
            result=json.loads(line);assert 'error' not in result,(index,req,result)
            output=result['latex']
            if kind=='matrix':actual=base.matrix(output);ok=actual==expected
            elif kind=='roots':actual=roots(output);ok=actual==expected or actual.symmetric_difference(expected)==sp.EmptySet
            elif kind=='literal':actual=output;ok=actual==expected
            else:actual=expression(output);ok=sp.cancel(actual-expected)==0
            assert ok,(index,req,actual,expected)
    print(json.dumps(dict(passed=len(cases),failed=0,seed=20261112,oracle='SymPy '+sp.__version__)))
if __name__=='__main__':main()
