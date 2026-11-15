#!/usr/bin/env python3
"""Deterministic independent SymPy checks of exact algebra. No installs/notebooks.
A whitelist parser translates emitted LaTeX; result strings are never eval'd.
"""
import json,random,re,subprocess,tempfile
from pathlib import Path
import sympy as s
ROOT=Path(__file__).resolve().parents[1];SRC=ROOT/'inkpad/inkpad/Services';x=s.Symbol('x',real=True)
CLI=r'''
import Foundation
@main struct CLI {static func main(){while let line=readLine(){do{
 let q=try JSONDecoder().decode(MathComputationRequest.self,from:Data(line.utf8));let a=try MathComputationService().compute(q)
 let d=try JSONSerialization.data(withJSONObject:["latex":a.outputLatex]);print(String(decoding:d,as:UTF8.self))
}catch{let d=try! JSONSerialization.data(withJSONObject:["error":error.localizedDescription]);print(String(decoding:d,as:UTF8.self))}}}}
'''
class Scalar:
 def __init__(self,text):
  text=text.replace(r'\,','').replace(' ','').replace(r'\cdot','*')
  self.ts=re.findall(r'\\frac|\\sqrt|\\infty|\d+|[{}()+\-*/^ix]',text);self.i=0
  assert ''.join(self.ts)==text,('token',text)
 def take(self,t):assert self.ts[self.i]==t;(setattr(self,'i',self.i+1))
 def atom(self):
  t=self.ts[self.i];self.i+=1
  if t in ['+','-']:v=self.atom();return v if t=='+' else -v
  if t.isdigit():v=s.Integer(t)
  elif t=='i':v=s.I
  elif t=='x':v=x
  elif t==r'\infty':v=s.oo
  elif t in ['{','(']:v=self.expr();self.take('}' if t=='{' else ')')
  elif t==r'\frac':v=self.atom()/self.atom()
  elif t==r'\sqrt':v=s.sqrt(self.atom())
  else:raise AssertionError(t)
  if self.i<len(self.ts) and self.ts[self.i]=='^':self.i+=1;v=v**self.atom()
  return v
 def product(self):
  v=self.atom()
  while self.i<len(self.ts):
   t=self.ts[self.i]
   if t in ['*','/']:self.i+=1;a=self.atom();v=v*a if t=='*' else v/a
   elif t in ['i','x','{','(',r'\frac',r'\sqrt'] or t.isdigit():v*=self.atom()
   else:break
  return v
 def expr(self):
  v=self.product()
  while self.i<len(self.ts) and self.ts[self.i] in ['+','-']:
   t=self.ts[self.i];self.i+=1;a=self.product();v=v+a if t=='+' else v-a
  return v
 def parse(self):v=self.expr();assert self.i==len(self.ts),(self.ts,self.i);return v

def solution(text):
 text=text.replace(r'\,','')
 if text==r'\varnothing':return s.S.EmptySet
 if r'\mathbb{R}' in text:return s.S.Reals
 if text.startswith('x = '):return s.FiniteSet(Scalar(text[4:]).parse())
 body=text.split(r'\in',1)[1].strip().replace(r'\left','').replace(r'\right','')
 if body.startswith(r'\{'):return s.FiniteSet(*(Scalar(v).parse() for v in body[2:-2].split(',')))
 intervals=[]
 for part in body.split(r'\cup'):
  part=part.strip();lo,hi=part[1:-1].split(',');intervals.append(s.Interval(Scalar(lo).parse(),Scalar(hi).parse(),left_open=part[0]=='(',right_open=part[-1]==')'))
 return s.Union(*intervals)

def main():
 rng=random.Random(20261114);cases=[]
 def add(op,a,expected,b='',kind='scalar'):
  q=dict(operation=op,inputA=a,inputB=b,variable='x',point='2',lower='0',upper='1');cases.append((q,expected,kind))
 for _ in range(80):
  a,b,c=[s.Rational(rng.randint(-5,5),rng.randint(1,3)) for _ in range(3)]
  p=a*x*x+b*x+c;src=f'({a})x^2+({b})x+({c})'
  for op,relation in [('<',s.Lt),('<=',s.Le),('>',s.Gt),('>=',s.Ge)]:
   add('solveInequality',src+op+'0',s.solve_univariate_inequality(relation(p,0),x,relational=False),kind='set')
 for _ in range(70):
  a,b,c=[s.Integer(rng.randint(-6,6)) for _ in range(3)]
  add('solveAbsolute',f'|({a})x+({b})|={c}',s.solveset(s.Abs(a*x+b)-c,x,domain=s.S.Reals),kind='set')
 for _ in range(70):
  a,b,c,d=[s.Rational(rng.randint(-5,5),rng.randint(1,4)) for _ in range(4)]
  if c==d==0:c=s.Integer(1)
  text=f'(({a})+({b})i)/(({c})+({d})i)';z=(a+b*s.I)/(c+d*s.I)
  add('complexCalculate',text,s.simplify(z));add('complexConjugate',text,s.conjugate(z));add('complexModulus',text,s.Abs(z))
 for _ in range(40):
  a=sum(s.Integer(rng.randint(-3,3))*x**i for i in range(rng.randint(1,4)));b=sum(s.Integer(rng.randint(-2,2))*x**i for i in range(rng.randint(1,4)))
  add('compose',str(a).replace('**','^'),s.expand(a.subs(x,b)),str(b).replace('**','^'))
 with tempfile.TemporaryDirectory(prefix='folio-algebra-oracle-') as tmp:
  tmp=Path(tmp);(tmp/'Main.swift').write_text(CLI)
  subprocess.run(['swiftc','-O','-module-cache-path',str(tmp/'cache')]+[str(SRC/(n+'.swift')) for n in ['PolynomialIntegrationService','PolynomialIntegralInput','MathComputationService','AlgebraComputationService']]+[str(tmp/'Main.swift'),'-o',str(tmp/'oracle')],check=True)
  run=subprocess.run([str(tmp/'oracle')],input='\n'.join(json.dumps(q) for q,_,_ in cases)+'\n',capture_output=True,text=True,timeout=60,check=True)
 answers=run.stdout.splitlines();assert len(answers)==len(cases)
 for i,((q,expected,kind),line) in enumerate(zip(cases,answers)):
  reply=json.loads(line);assert 'error' not in reply,(i,q,reply)
  actual=solution(reply['latex']) if kind=='set' else Scalar(reply['latex']).parse()
  if kind=='set':assert actual==expected,(i,q,actual,expected)
  else:assert s.simplify(actual-expected)==0,(i,q,actual,expected)
 print(json.dumps(dict(passed=len(cases),failed=0,seed=20261114,oracle='SymPy '+s.__version__,scope='Exact inequality solution sets, absolute-value roots, Gaussian rationals, composition')))
if __name__=='__main__':main()
