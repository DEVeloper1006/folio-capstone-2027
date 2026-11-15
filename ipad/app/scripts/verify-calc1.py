#!/usr/bin/env python3
"""Independent SymPy checks of bundled Calc 1 results; no downloads or notebooks.
Requires an existing Python+SymPy and Node installation. JSON ASTs are translated
through a whitelist, never eval(). Checks supported examples, not all of Calc 1.
"""
import json,subprocess,random,tempfile
from pathlib import Path
import sympy as s
ROOT=Path(__file__).resolve().parents[1]
RES=ROOT/'inkpad/inkpad/Resources'
x=s.Symbol('x',real=True)
functions={'sin':s.sin,'cos':s.cos,'tan':s.tan,'sec':s.sec,'csc':s.csc,'cot':s.cot,'asin':s.asin,'acos':s.acos,'atan':s.atan,'asec':s.asec,'acsc':s.acsc,'acot':s.acot,'sinh':s.sinh,'cosh':s.cosh,'tanh':s.tanh,'sech':s.sech,'csch':s.csch,'coth':s.coth,'asinh':s.asinh,'acosh':s.acosh,'atanh':s.atanh,'exp':s.exp,'log':s.log,'abs':s.Abs}
def ast(a):
    k=a['k']
    if k=='n':return s.Rational(a['v'])
    if k=='v':return s.Symbol(a['v'],real=True)
    if k=='c':return {'pi':s.pi,'e':s.E,'Inf':s.oo}[a['v']]
    if k=='f':return functions[a['v']](ast(a['a']))
    p,q=ast(a['a']),ast(a['b']);return {'+':lambda:p+q,'-':lambda:p-q,'*':lambda:p*q,'/':lambda:p/q,'^':lambda:p**q}[a['v']]()
def main():
    rng=random.Random(20261112);cases=[]
    def add(op,latex,expected,kind='exact',**kw):
        cases.append((dict(operation=op,inputA=latex,variable='x',point='2',lower='0',upper='1',**kw),expected,kind))
    for a in range(1,6):
        for power in [1,2,3]:
            f=s.sin(a*x)*s.exp(x)+s.Rational(a,3)*x**power
            add('derivative',rf'\sin({a}x)e^x+\frac{{{a}}}{{3}}x^{power}',s.diff(f,x))
            add('secondDerivative',rf'\cos({a}x)+\ln(x)+x^{power}',s.diff(s.cos(a*x)+s.log(x)+x**power,x,2))
    pairs=[(r'\sin x',s.sin(x)),(r'\cos x',s.cos(x)),(r'\tan x',s.tan(x)),(r'\sec x',s.sec(x)),(r'\csc x',s.csc(x)),(r'\cot x',s.cot(x)),(r'\ln x',s.log(x)),(r'\log(x)',s.log(x,10)),(r'\sqrt{x}',s.sqrt(x)),(r'2^x',2**x),(r'x^x',x**x),(r'\arcsin x',s.asin(x)),(r'\sin^{-1}x',s.asin(x)),(r'\arctan x',s.atan(x)),(r'\sinh x',s.sinh(x)),(r'\cosh x',s.cosh(x)),(r'\tanh x',s.tanh(x)),(r'\frac{x^2+1}{x+2}',(x*x+1)/(x+2))]
    for latex,f in pairs:add('derivative',latex,s.diff(f,x))
    integrals=[(r'\sin x',s.sin(x)),(r'\cos x',s.cos(x)),(r'e^x',s.exp(x)),(r'1/x',1/x),(r'1/(1+x^2)',1/(1+x*x)),(r'\sec^2 x',s.sec(x)**2),(r'x e^x',x*s.exp(x)),(r'2x\cos(x^2)',2*x*s.cos(x*x)),(r'\sqrt{x}',s.sqrt(x)),(r'\ln x',s.log(x))]
    for latex,f in integrals:add('integral',r'\int '+latex+' dx',f,'antiderivative')
    for a in range(1,6):
        add('definiteIntegral',rf'\int_0^{{\pi}} \sin({a}x) dx',s.integrate(s.sin(a*x),(x,0,s.pi)))
        add('definiteIntegral',rf'\int_0^1 e^{{{a}x}} dx',(s.exp(a)-1)/a)
    for latex,expected,point,op in [(r'\sin x/x',1,'0','limit'),('(x^2-1)/(x-1)',2,'1','limit'),('(1+1/x)^x',s.E,'Inf','limit'),('1/x',s.oo,'0','limitRight'),('1/x',-s.oo,'0','limitLeft'),(r'\ln x',-s.oo,'0','limitRight'),('(2x^2+1)/(x^2+3)',2,'-Inf','limit')]:
        q=dict(operation=op,inputA=latex,variable='x',point=point,lower='0',upper='1');cases.append((q,expected,'exact'))
    add('numericalIntegral',r'\int_0^1 e^{-x^2} dx',s.integrate(s.exp(-x*x),(x,0,1)),'numeric')
    add('numericalIntegral','1/1000000000000',s.Rational(1,10**12),'numeric')
    add('areaBetween','x',s.Rational(1,6),'numeric',inputB='x^2')
    add('arcLength','x',s.sqrt(2),'numeric')
    add('volumeDisk','x',s.pi/3)
    add('averageValue','x^2',s.Rational(1,3))
    add('derivative','f(x)=sin(x)',s.cos(x))
    add('derivative','e',s.Integer(0))
    add('arithmetic','1e-3',s.Rational(1,1000))
    add('volumeWasher','2',11*s.pi/3,inputB='x')
    add('volumeShell','x^2+3x+2',9*s.pi/2)
    rejected=[('definiteIntegral',r'\int_{-1}^1 1/x dx'),('numericalIntegral',r'\int_0^{\pi} \tan x dx'),('limit','1/x'),('integral','e^{-x^2}'),('derivative',r'\Gamma(x)'),('derivative','x+y'),('derivative',r'\lim_{x\to0} x'),('expand','(x+1)^1000'),('arithmetic','0^0'),('arithmetic','log(-1)')]
    for op,latex in rejected:cases.append((dict(operation=op,inputA=latex,variable='x',point='0',lower='0',upper='1'),None,'reject'))
    runner=r'''
const fs=require('node:fs'),rl=require('node:readline'),n=require(process.argv[2]);require(process.argv[3]);
rl.createInterface({input:process.stdin}).on('line',line=>{try{const q=JSON.parse(line),r=FolioCalc1.compute(q,n);let text=r.latex.split('\\quad\\text{for }')[0].replace(/\s*\+\s*C(?:_\{1\})?$/,'').replace(/^\\approx\s*/,'');
const tree=FolioCalc1.parse(text);console.log(JSON.stringify({tree,latex:r.latex}));}catch(e){console.log(JSON.stringify({error:e.message}));}});
'''
    with tempfile.TemporaryDirectory(prefix='folio-calc1-oracle-') as tmp:
        p=Path(tmp)/'run.cjs';p.write_text(runner)
        run=subprocess.run(['node',str(p),str(RES/'nerdamer-2.0.1.js'),str(RES/'calc1-worker.js')],input='\n'.join(json.dumps(q) for q,_,_ in cases)+'\n',text=True,capture_output=True,timeout=90,check=True)
    answers=run.stdout.splitlines();assert len(answers)==len(cases),(len(answers),len(cases),run.stderr)
    for i,((q,expected,kind),line) in enumerate(zip(cases,answers)):
        answer=json.loads(line)
        if kind=='reject':assert 'error' in answer,(i,q,answer);continue
        assert 'error' not in answer,(i,q,answer)
        actual=ast(answer['tree'])
        if kind=='antiderivative':actual=s.diff(actual,x)
        if kind=='numeric':assert abs(float(s.N(actual-expected)))<1e-8,(i,q,actual,expected)
        elif actual in [s.oo,-s.oo] or expected in [s.oo,-s.oo]:assert actual==expected,(i,q,actual,expected)
        else:
            delta=s.simplify(actual-expected)
            if delta!=0:
                # Real log(abs) derivatives may retain sign/piecewise terms.
                for point in [s.Rational(1,5),s.Rational(2,5),s.Rational(3,5)]:
                    val=s.N(delta.subs(x,point));assert abs(complex(val))<1e-9,(i,q,actual,expected,point,val)
    print(json.dumps(dict(passed=len(cases),failed=0,oracle='SymPy '+s.__version__,seed=20261112,notes='symbolic comparisons, sampled branch checks and explicitly numeric tolerances; not a universal CAS proof')))
if __name__=='__main__':main()
