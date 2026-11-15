#!/usr/bin/env python3
"""Independent exact checks of native complex quadratic roots. No downloads/data access.
Requires an existing Python with SymPy and Swift. Output parser is a small
whitelist for the emitted scalar LaTeX, never eval/sympify on result text.
"""
import json, random, re, subprocess, tempfile
from pathlib import Path
import sympy as sp
ROOT=Path(__file__).resolve().parents[1]
SERVICES=ROOT/'inkpad/inkpad/Services'
CLI=r'''
import Foundation
@main struct CLI {
 static func main() {
  while let line=readLine() {
   do {
    let q=try JSONDecoder().decode(MathComputationRequest.self,from:Data(line.utf8))
    let a=try MathComputationService().compute(q)
    let d=try JSONSerialization.data(withJSONObject:["latex":a.outputLatex]);print(String(decoding:d,as:UTF8.self))
   } catch {let d=try! JSONSerialization.data(withJSONObject:["error":error.localizedDescription]);print(String(decoding:d,as:UTF8.self))}
  }
 }
}
'''
class Scalar:
 def __init__(self,text):
  text=text.replace(r'\,','').replace(' ','')
  self.tokens=re.findall(r'\\frac|\\sqrt|\d+|[{}+\-i]',text)
  assert ''.join(self.tokens)==text,('Unexpected output token',text)
  self.i=0
 def take(self,t):
  assert self.i<len(self.tokens) and self.tokens[self.i]==t,(self.tokens,self.i,t)
  self.i+=1
 def atom(self):
  t=self.tokens[self.i];self.i+=1
  if t=='-':return -self.atom()
  if t=='+':return self.atom()
  if t=='i':return sp.I
  if t.isdigit():return sp.Integer(t)
  if t=='{':
   v=self.product();self.take('}');return v
  if t==r'\frac':return self.atom()/self.atom()
  if t==r'\sqrt':return sp.sqrt(self.atom())
  raise AssertionError(t)
 def product(self):
  v=self.atom()
  while self.i<len(self.tokens) and self.tokens[self.i]!='}':v*=self.atom()
  return v
 def parse(self):
  v=self.product();assert self.i==len(self.tokens);return v

def main():
 rng=random.Random(20261114);x=sp.Symbol('x');cases=[]
 for a,b,c in [(1,0,1),(1,2,5),(-1,0,-1),(4,0,1),(1,0,12),(1,0,2)]:cases.append((sp.Integer(a),sp.Integer(b),sp.Integer(c)))
 while len(cases)<166:
  a=rng.choice([i for i in range(-15,16) if i]);b=rng.randint(-20,20);c=rng.randint(-30,30)
  if b*b-4*a*c<0:
   scale=sp.Rational(rng.choice([-3,-2,1,2,3]),rng.randint(1,5));cases.append(tuple(scale*k for k in (a,b,c)))
 requests=[]
 for a,b,c in cases:
  expression=f'({a})x^2+({b})x+({c})=0'
  requests.append(dict(operation='solveEquation',inputA=expression,inputB='',variable='x',point='2',lower='0',upper='1'))
 with tempfile.TemporaryDirectory(prefix='folio-complex-oracle-') as tmp:
  tmp=Path(tmp);(tmp/'Main.swift').write_text(CLI)
  files=['PolynomialIntegrationService','MathComputationService','PolynomialIntegralInput','AlgebraComputationService']
  subprocess.run(['swiftc','-O','-module-cache-path',str(tmp/'cache')]+[str(SERVICES/(f+'.swift')) for f in files]+[str(tmp/'Main.swift'),'-o',str(tmp/'oracle')],check=True)
  run=subprocess.run([str(tmp/'oracle')],input='\n'.join(map(json.dumps,requests))+'\n',text=True,capture_output=True,check=True,timeout=30)
 answers=run.stdout.splitlines();assert len(answers)==len(cases)
 for (a,b,c),line in zip(cases,answers):
  answer=json.loads(line);assert 'error' not in answer,((a,b,c),answer)
  real,imaginary=answer['latex'].removeprefix('x = ').split(r'\pm')
  center=Scalar(real.strip()).parse() if real.strip() else sp.Integer(0)
  offset=Scalar(imaginary.strip()).parse()
  roots=[sp.simplify(center+offset),sp.simplify(center-offset)]
  expected=sp.solve(a*x*x+b*x+c,x)
  assert len(expected)==2 and roots[0]!=roots[1]
  for root in roots:
   assert sp.simplify(a*root*root+b*root+c)==0,((a,b,c),answer)
   assert any(sp.simplify(root-e)==0 for e in expected),((a,b,c),root,expected)
 print(json.dumps(dict(passed=len(cases),failed=0,seed=20261114,oracle='SymPy '+sp.__version__,scope='Real rational coefficients with negative discriminant; exact root sets and substitution')))
if __name__=='__main__':main()
