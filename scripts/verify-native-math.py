#!/usr/bin/env python3
"""Compare native Swift matrix arithmetic with an installed SymPy (no downloads).
Run with a Python environment that already contains sympy. Builds only in a
TemporaryDirectory and uses deterministic inputs; never reads notebook data.
"""
import json, random, re, subprocess, tempfile
from pathlib import Path
import sympy as sp

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'inkpad/inkpad/Services'
MAIN = r'''
import Foundation
@main struct OracleCLI {
    static func main() {
        while let line=readLine() {
            do {
                let request=try JSONDecoder().decode(MathComputationRequest.self,from:Data(line.utf8))
                let answer=try MathComputationService().compute(request)
                let data=try JSONSerialization.data(withJSONObject:["latex":answer.outputLatex,"steps":answer.steps],options:[.sortedKeys])
                print(String(decoding:data,as:UTF8.self))
            } catch { let data=try! JSONSerialization.data(withJSONObject:["error":error.localizedDescription]);print(String(decoding:data,as:UTF8.self)) }
        }
    }
}
'''

def request(op, a, b=''):
    return dict(operation=op, inputA=a, inputB=b, variable='x', point='2', lower='0', upper='1')

def text(a):
    return ';'.join(','.join(str(x) for x in row) for row in a.tolist())

def scalar(s):
    s=re.sub(r'\\frac\{(-?\d+)\}\{(\d+)\}', r'\1/\2', s.strip())
    assert re.fullmatch(r'-?\d+(?:/\d+)?', s), s
    return sp.Rational(s)

def matrix(s):
    body=s.removeprefix(r'\begin{bmatrix}').removesuffix(r'\end{bmatrix}')
    return sp.Matrix([[scalar(x) for x in row.split('&')] for row in body.split(r'\\')])

def main():
    rng=random.Random(20261111)
    cases=[]
    def add(op,a,expected,b=None):
        cases.append((request(op,text(a),text(b) if b is not None else ''),expected))
    for _ in range(70):
        r,c=rng.randint(1,4),rng.randint(1,4)
        a=sp.Matrix(r,c,lambda i,j:sp.Rational(rng.randint(-5,5),rng.randint(1,3)))
        add('rref',a,a.rref()[0]);add('rank',a,a.rank());add('transpose',a,a.T)
        b=sp.Matrix(r,c,lambda i,j:sp.Rational(rng.randint(-4,4),rng.randint(1,3)))
        add('matrixAdd',a,a+b,b);add('matrixSubtract',a,a-b,b)
        b=sp.Matrix(c,rng.randint(1,4),lambda i,j:rng.randint(-4,4))
        add('matrixMultiply',a,a*b,b)
        if r==c:
            add('determinant',a,a.det())
            if a.det()!=0:add('inverse',a,a.inv())
    for n in [1,2,3,4,5,6]:
        a=sp.Matrix(n,n,lambda i,j:(rng.randint(-2,2) if i<j else (i+1 if i==j else 0)))
        add('determinant',a,a.det());add('inverse',a,a.inv());add('rref',a,sp.eye(n))
    # Full recognized-integral notation, including a variable that differs from
    # stale/default request fields. SymPy independently evaluates the limits.
    for index in range(100):
        v=sp.Symbol(['t','y','z'][index%3])
        polynomial=sum(sp.Rational(rng.randint(-5,5),rng.randint(1,4))*v**power for power in range(rng.randint(0,6)))
        a=sp.Rational(rng.randint(-6,6),rng.randint(1,4));b=sp.Rational(rng.randint(-6,6),rng.randint(1,4))
        latex=r'\int_{'+sp.latex(a)+'}^{'+sp.latex(b)+'} '+sp.latex(polynomial)+r'\,d'+str(v)
        cases.append((request('definiteIntegral',latex),sp.integrate(polynomial,(v,a,b))))
    with tempfile.TemporaryDirectory(prefix='folio-math-oracle-') as tmp:
        tmp=Path(tmp);(tmp/'Main.swift').write_text(MAIN)
        subprocess.run(['swiftc','-O','-module-cache-path',str(tmp/'cache'),str(SOURCES/'PolynomialIntegrationService.swift'),str(SOURCES/'MathComputationService.swift'),str(SOURCES/'PolynomialIntegralInput.swift'),str(SOURCES/'AlgebraComputationService.swift'),str(tmp/'Main.swift'),'-o',str(tmp/'oracle')],check=True)
        result=subprocess.run([str(tmp/'oracle')],input='\n'.join(json.dumps(c[0]) for c in cases)+'\n',text=True,capture_output=True,check=True)
        answers=result.stdout.splitlines();assert len(answers)==len(cases)
        for index,((req,expected),line) in enumerate(zip(cases,answers)):
            answer=json.loads(line);assert 'error' not in answer,(index,req,answer)
            actual=matrix(answer['latex']) if isinstance(expected,sp.MatrixBase) else scalar(answer['latex'])
            assert actual==expected,(index,req,actual,expected)
    print(json.dumps(dict(passed=len(cases),failed=0,seed=20261111,oracle='SymPy '+sp.__version__)))

if __name__=='__main__':main()
