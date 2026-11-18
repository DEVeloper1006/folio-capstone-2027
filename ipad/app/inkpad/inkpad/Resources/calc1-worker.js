/* Folio Calc 1 adapter. Input is parsed as mathematics, never JavaScript.
   Runs in a fresh, time-limited worker with a pinned local Nerdamer bundle. */
(function(root){
'use strict';
const funcs=new Set('sin cos tan sec csc cot asin acos atan asec acsc acot sinh cosh tanh sech csch coth asinh acosh atanh exp ln log sqrt abs'.split(' '));
const fail=m=>{throw new Error(m);};
const N=v=>({k:'n',v:String(v)}),V=v=>({k:'v',v}),F=(v,a)=>({k:'f',v,a}),B=(v,a,b)=>({k:'b',v,a,b});
function lex(s){
 if(typeof s!=='string'||!s.trim()||s.length>2000)fail('Enter an expression of 1–2,000 characters.');
 let out=[],i=0;const emit=t=>{out.push(t);if(out.length>400)fail('This expression is too long. Split it into smaller steps.');};
 s=s.trim();for(const [a,b]of[['\\[','\\]'],['\\(','\\)'],['$$','$$'],['$','$']])if(s.startsWith(a)&&s.endsWith(b)){s=s.slice(a.length,-b.length);break;}
 while(i<s.length){let c=s[i];if(/\s/.test(c)){i++;continue;}
 if(/[0-9.]/.test(c)){let m=s.slice(i).match(/^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/);if(!m)fail('Invalid decimal.');let value=m[0];if(/[eE]/.test(value)){const [mantissa,power]=value.split(/[eE]/),e=Number(power),parts=mantissa.split('.'),digits=parts.join(''),point=parts[0].length+e;if(Math.abs(e)>100)fail('Scientific exponent is too large.');value=point<=0?'0.'+'0'.repeat(-point)+digits:point>=digits.length?digits+'0'.repeat(point-digits.length):digits.slice(0,point)+'.'+digits.slice(point);}emit({t:'n',v:value});i+=m[0].length;continue;}
 if(c==='\\'){
  i++;let m=s.slice(i).match(/^[A-Za-z]+/);if(!m){if(/[,;:! ]/.test(s[i]||'')){i++;continue;}fail('Unsupported LaTeX punctuation.');}
  let name=m[0];i+=name.length;
  if(['left','right','displaystyle','textstyle','limits','nolimits','quad','qquad'].includes(name))continue;
  if(name==='mathrm'||name==='operatorname'){let g=s.slice(i).match(/^\s*\{([A-Za-z]+)\}/);if(!g)fail('Review the function or differential.');i+=g[0].length;name=g[1];}
  if(name==='dfrac'||name==='tfrac')name='frac';if(name==='cdot'||name==='times')name='*';if(name==='div')name='/';if(name==='infty')name='Inf';if(name==='to'||name==='rightarrow')name='to';
  if(name.startsWith('arc')&&funcs.has('a'+name.slice(3)))name='a'+name.slice(3);
  if(funcs.has(name))emit({t:'f',v:name});else if(['frac','int','lim','to','pi','Inf','d','e'].includes(name))emit({t:name==='d'?'v':name,v:name});else if(['*','/'].includes(name))emit({t:name});else fail('Unsupported notation \\'+name+'. Use a single-variable elementary expression.');continue;
 }
 if(/[A-Za-z]/.test(c)){let m=s.slice(i).match(/^[A-Za-z]+/)[0];i+=m.length;
  if(funcs.has(m))emit({t:'f',v:m});else if(m==='pi'||m==='Inf'||m==='infinity')emit({t:m==='pi'?'pi':'Inf',v:m});
  else {if(m.length>1&&s.slice(i).trimStart().startsWith('('))fail('Unsupported function '+m+'. Use an elementary function with explicit parentheses.');for(const letter of m)emit({t:letter==='e'?'e':'v',v:letter});}continue;
 }
 const map={'−':'-','×':'*','·':'*','÷':'/','π':'pi','∞':'Inf','∫':'int'};
 if(c==='²'||c==='³'){emit({t:'^'});emit({t:'n',v:c==='²'?'2':'3'});i++;continue;}
 c=map[c]||c;if('+-*/^(){}[]_|=,'.includes(c)||['pi','Inf','int'].includes(c)){emit({t:c,v:c});i++;continue;}
 fail('Unsupported symbol '+c+'.');
 }return out;
}
class Parser{
 constructor(tokens,internal=false){this.t=tokens;this.i=0;this.nodes=0;this.depth=0;this.pipe=0;this.internal=internal;}
 cur(){return this.t[this.i]?.t;} take(t){if(this.cur()===t){this.i++;return true;}return false;}expect(t){if(!this.take(t))fail('Review parentheses, braces and function arguments.');}
 node(n){if(++this.nodes>160)fail('Expression is too complex; split it into smaller steps.');return n;}
 parse(){let a=this.expr();if(this.i!==this.t.length)fail('Unfinished or unsupported notation. Add parentheses to clarify the expression.');return a;}
 expr(){let a=this.product();while(this.cur()==='+'||this.cur()==='-'){let op=this.t[this.i++].t;a=this.node(B(op,a,this.product()));}return a;}
 starts(){return ['n','v','e','pi','Inf','f','frac','(','{','['].includes(this.cur())||(this.cur()==='|'&&this.pipe===0);}
 product(){let a=this.unary();while(true){if(this.take('*'))a=this.node(B('*',a,this.unary()));else if(this.take('/'))a=this.node(B('/',a,this.unary()));else if(this.starts())a=this.node(B('*',a,this.unary()));else break;}return a;}
 unary(){if(this.take('+'))return this.unary();if(this.take('-'))return this.node(B('*',N(-1),this.unary()));return this.power();}
 power(){let a=this.atom();if(this.take('^')){const exponent=this.unary();if(!variables(exponent).size&&Math.abs(numeric(exponent,0,'x'))>1000)fail('Use a power of magnitude at most 1,000.');if(!variables(a).size&&!variables(exponent).size&&numeric(a,0,'x')===0&&numeric(exponent,0,'x')===0)fail('Zero to the zeroth power is undefined here.');a=this.node(B('^',a,exponent));}return a;}
 group(){const open=this.cur(),close={'(':')','{':'}','[':']'}[open];if(!close)fail('Put fractions and roots in braces.');this.i++;const a=this.expr();this.expect(close);return a;}
 atom(){if(++this.depth>32)fail('Too many nested groups.');let a,t=this.t[this.i++];if(!t)fail('The expression is incomplete.');
 switch(t.t){case'n':a=N(t.v);break;case'v':a=V(t.v);break;case'e':case'pi':case'Inf':a={k:'c',v:t.t};break;
 case'(':case'{':case'[':this.i--;a=this.group();break;
 case'|':this.pipe++;a=F('abs',this.expr());this.expect('|');this.pipe--;break;
 case'frac':{const num=this.group(),den=this.group();a=B('/',num,den);break;}
 case'f':{let name=t.v,exponent=null,base=null;
  if(name==='sqrt'&&this.cur()==='['){base=this.group();}
  if(name==='log'&&this.take('_'))base=this.cur()==='{'?this.group():this.atom();
  if(this.take('^'))exponent=this.cur()==='{'?this.group():this.unary();
  if(exponent&&!variables(exponent).size&&Math.abs(numeric(exponent,0,'x'))>1000)fail('Use a function power of magnitude at most 1,000.');
  let arg;if(['(','{','['].includes(this.cur()))arg=this.group();else{
   arg=this.unary();if(arg.k==='n'&&this.cur()==='v')arg=B('*',arg,this.unary());
  }
  if(exponent&&variables(exponent).size===0&&numeric(exponent,0,'x')===-1&&['sin','cos','tan','sec','csc','cot'].includes(name)){name='a'+name;exponent=null;}
  if(name==='sqrt')a=B('^',arg,B('/',N(1),base||N(2)));
  else if(name==='log'&&!this.internal)a=B('/',F('log',arg),F('log',base||N(10)));
  else a=F(name==='ln'?'log':name,arg);
  if(exponent)a=B('^',a,exponent);break;
 }
 default:fail('Review the expression near '+(t.v||t.t)+'.');
 }this.depth--;return this.node(a);}
}
function cas(a){switch(a.k){case'n':return '('+a.v+')';case'v':case'c':return a.v;case'f':return a.v+'('+cas(a.a)+')';case'b':return '('+cas(a.a)+a.v+cas(a.b)+')';}}
function variables(a,out=new Set()){if(a.k==='v')out.add(a.v);if(a.a)variables(a.a,out);if(a.b)variables(a.b,out);return out;}
function parse(s,internal=false){return new Parser(lex(s),internal).parse();}
function fullInput(s){
 let tokens=lex(s),p=new Parser(tokens),meta={},body;
 if(p.take('int')){
  let low=null,high=null;
  while(p.cur()==='_'||p.cur()==='^'){const marker=p.t[p.i++].t;let negative=p.take('-');const value0=p.cur()==='{'?p.group():p.atom();const value=negative?B('*',N(-1),value0):value0;if(marker==='_'){if(low)fail('Duplicate lower limit.');low=value;}else{if(high)fail('Duplicate upper limit.');high=value;}}
  if(!!low!==!!high)fail('Review both integral limits; one is missing.');
  let rest=tokens.slice(p.i);if(rest.length<2||rest.at(-1).t!=='v'||rest.at(-2).t!=='v'||rest.at(-2).v!=='d')fail('End the integral with a differential, such as dx or dt.');
  meta.variable=rest.at(-1).v;meta.lowerAST=low;meta.upperAST=high;meta.kind=low?'definiteIntegral':'integral';
  body=rest.length===2?N(1):new Parser(rest.slice(0,-2)).parse();
 }else if(p.take('lim')){
  p.expect('_');p.expect('{');const v=p.t[p.i++];if(v?.t!=='v')fail('The limit needs one variable.');p.expect('to');
  let end=p.i,nesting=0;while(end<tokens.length){if(tokens[end].t==='{')nesting++;if(tokens[end].t==='}'){if(nesting===0)break;nesting--;}end++;}
  if(end===tokens.length)fail('Close the limit subscript.');let pt=tokens.slice(p.i,end);
  if(pt.length>=4&&pt.at(-4).t==='^'&&pt.at(-3).t==='{'&&pt.at(-1).t==='}'&&['+','-'].includes(pt.at(-2).t)){meta.direction=pt.at(-2).t==='+'?'right':'left';pt=pt.slice(0,-4);}
  if(pt.length>=2&&pt.at(-2).t==='^'&&['+','-'].includes(pt.at(-1).t)){meta.direction=pt.at(-1).t==='+'?'right':'left';pt=pt.slice(0,-2);}
  meta.pointAST=new Parser(pt).parse();meta.variable=v.v;meta.kind='limit';body=new Parser(tokens.slice(end+1)).parse();
 }else{body=p.parse();meta.kind='expression';}
 return{body,meta};
}
function numeric(a,x,v){let n;if(a.k==='n')return Number(a.v);if(a.k==='c')return a.v==='pi'?Math.PI:a.v==='e'?Math.E:Infinity;if(a.k==='v'){if(a.v!==v)fail('Unexpected variable '+a.v+'.');return x;}
 if(a.k==='b'){const l=numeric(a.a,x,v),r=numeric(a.b,x,v);switch(a.v){case'+':n=l+r;break;case'-':n=l-r;break;case'*':n=l*r;break;case'/':if(r===0)fail('Division by zero.');n=l/r;break;case'^':n=Math.pow(l,r);if(l<0&&!Number.isFinite(n)){for(let q=1;q<=15;q+=2){const p=Math.round(r*q);if(Math.abs(r*q-p)<1e-12){n=(p%2?-1:1)*Math.pow(-l,r);break;}}}break;}}
 else{const z=numeric(a.a,x,v);switch(a.v){case'sec':n=1/Math.cos(z);break;case'csc':n=1/Math.sin(z);break;case'cot':n=1/Math.tan(z);break;case'sech':n=1/Math.cosh(z);break;case'csch':n=1/Math.sinh(z);break;case'coth':n=1/Math.tanh(z);break;case'asec':n=Math.acos(1/z);break;case'acsc':n=Math.asin(1/z);break;case'acot':n=Math.atan(1/z);break;case'abs':n=Math.abs(z);break;case'log':n=Math.log(z);break;default:n=Math[a.v]?.(z);}}
 if(!Number.isFinite(n))fail('The expression is not finite and real at this input.');return n;
}
function scalar(a,label,allowInf=false){if(variables(a).size)fail(label+' must be a constant, such as 0, 1/2 or pi.');if(allowInf&&a.k==='c'&&a.v==='Inf')return Infinity;if(allowInf&&a.k==='b'&&a.v==='*'&&a.a.k==='n'&&a.a.v==='-1'&&a.b.k==='c'&&a.b.v==='Inf')return -Infinity;const n=numeric(a,0,'x');if(!allowInf&&!Number.isFinite(n))fail(label+' must be finite.');return n;}
function interval(a,l,h,v){
 if(a.k==='v'){if(a.v!==v)fail('Use one variable.');return[l,h];}if(!variables(a).size){let z=scalar(a,'Constant');return[z,z];}
 if(a.k==='b'){const p=interval(a.a,l,h,v),q=interval(a.b,l,h,v);let r;
 switch(a.v){case'+':return[p[0]+q[0],p[1]+q[1]];case'-':return[p[0]-q[1],p[1]-q[0]];case'*':r=[p[0]*q[0],p[0]*q[1],p[1]*q[0],p[1]*q[1]];break;
 case'/':if(q[0]<=0&&q[1]>=0)fail('Could not certify continuity: the denominator may be zero in this interval. Split the interval or simplify first.');r=[p[0]/q[0],p[0]/q[1],p[1]/q[0],p[1]/q[1]];break;
 case'^':{if(q[0]!==q[1]){if(p[0]<=0)fail('A variable power needs a positive base throughout the interval.');r=[Math.pow(p[0],q[0]),Math.pow(p[0],q[1]),Math.pow(p[1],q[0]),Math.pow(p[1],q[1])];break;}
 const e=q[0];if(e<0&&p[0]<=0&&p[1]>=0)fail('The integral crosses a pole. Improper integrals need a separate analysis.');
 if(!Number.isInteger(e)&&p[0]<0)fail('Could not certify the real domain of this fractional power on the interval.');
 r=[Math.pow(p[0],e),Math.pow(p[1],e)];if(p[0]<=0&&p[1]>=0&&e>0)r.push(0);break;}}
 if(r.some(x=>!Number.isFinite(x)))fail('Interval values are not finite.');return[Math.min(...r),Math.max(...r)];
 }
 const p=interval(a.a,l,h,v),lo=p[0],hi=p[1],trig=(offset=0)=>{const z=[Math.sin(lo+offset),Math.sin(hi+offset)];if(hi-lo>=2*Math.PI)return[-1,1];for(let k=Math.ceil((lo+offset-Math.PI/2)/Math.PI);k<=(hi+offset-Math.PI/2)/Math.PI;k++)z.push(k%2?-1:1);return[Math.min(...z),Math.max(...z)];};
 if(a.v==='sin')return trig();if(a.v==='cos')return trig(Math.PI/2);
 if(a.v==='tan'||a.v==='sec'){if(Math.ceil((lo-Math.PI/2)/Math.PI)<=Math.floor((hi-Math.PI/2)/Math.PI))fail('This interval crosses a trigonometric pole.');}
 if(a.v==='cot'||a.v==='csc'){if(Math.ceil(lo/Math.PI)<=Math.floor(hi/Math.PI))fail('This interval crosses a trigonometric pole.');}
 if(['csch','coth'].includes(a.v)&&lo<=0&&hi>=0)fail('This interval crosses a hyperbolic pole.');
 if(a.v==='log'&&lo<=0)fail('Logarithm requires a positive argument throughout the interval. Improper endpoint integrals are not handled here.');
 if(['asin','acos'].includes(a.v)&&(lo < -1||hi>1))fail('Inverse trig argument leaves the real domain.');
 if(['asec','acsc'].includes(a.v)&&lo<1&&hi> -1)fail('Inverse reciprocal trig argument leaves the real domain.');
 if(a.v==='acosh'&&lo<1||a.v==='atanh'&&(lo<=-1||hi>=1))fail('Hyperbolic argument leaves the real domain.');
 if(a.v==='abs')return[lo<=0&&hi>=0?0:Math.min(Math.abs(lo),Math.abs(hi)),Math.max(Math.abs(lo),Math.abs(hi))];
 const values=[numeric(F(a.v,N(lo)),0,v),numeric(F(a.v,N(hi)),0,v)];if(a.v==='cosh'&&lo<=0&&hi>=0)values.push(1);return[Math.min(...values),Math.max(...values)];
}
function numericalIntegral(a,low,high,v){
 if(low===high){numeric(a,low,v);return{value:0,error:0,evaluations:1};}
 const sign=high<low?-1:1,l=Math.min(low,high),h=Math.max(low,high);interval(a,l,h,v);
 let count=0,error=0;const f=x=>{if(++count>30000)fail('Numerical integral exceeded its evaluation budget. Try a shorter interval.');return numeric(a,x,v);};
 const simp=(a,b,fa,fm,fb)=>(b-a)*(fa+4*fm+fb)/6;
 function recur(a,b,fa,fm,fb,whole,tol,depth){const m=(a+b)/2,fl=f((a+m)/2),fr=f((m+b)/2),left=simp(a,m,fa,fl,fm),right=simp(m,b,fm,fr,fb),delta=left+right-whole;
 if(Math.abs(delta)<=15*tol){error+=Math.abs(delta)/15;return left+right+delta/15;}
 if(depth===0)fail('Numerical integration did not converge to the requested tolerance. No result was saved.');return recur(a,m,fa,fl,fm,left,tol/2,depth-1)+recur(m,b,fm,fr,fb,right,tol/2,depth-1);}
 const fa=f(l),fm=f((l+h)/2),fb=f(h),whole=simp(l,h,fa,fm,fb),value=sign*recur(l,h,fa,fm,fb,whole,1e-9*Math.max(1,Math.abs(whole)),18);
 return{value,error,evaluations:count};
}
function realLogs(a){if(a.k==='f')return F(a.v,a.v==='log'?F('abs',realLogs(a.a)):realLogs(a.a));if(a.k==='b')return B(a.v,realLogs(a.a),realLogs(a.b));return a;}
function approximateTeX(value){const s=Number(value.toPrecision(11)).toString(),parts=s.split('e');return parts.length===2?parts[0]+'\\times 10^{'+Number(parts[1])+'}':s;}
function compute(q,n){
 if(!q||typeof q.operation!=='string')fail('Choose an operation.');
 const operations=new Set('inspect partialDerivative derivative secondDerivative integral definiteIntegral numericalIntegral evaluate limit limitLeft limitRight tangentLine normalLine implicitDerivative averageRate averageValue areaBetween volumeDisk volumeShell volumeWasher arcLength rootInterval simplify expand arithmetic'.split(' '));
 if(!operations.has(q.operation))fail('This operation is not available in the elementary engine.');
 if(q.operation==='implicitDerivative'){
  const sides=q.inputA.split('=');if(sides.length!==2)fail('Enter an equation in x and y, e.g. x^2+y^2=1.');
  const a=parse(sides[0]),b=parse(sides[1]);if([...variables(B('-',a,b))].some(x=>x!=='x'&&x!=='y'))fail('Implicit dy/dx currently uses x and y only.');
  const f='('+cas(a)+'-'+cas(b)+')',fx=n.diff(f,'x'),fy=n.diff(f,'y');if(fy.text()==='0')fail('This relation does not determine y as a function of x.');
  const r=n.simplify('(-('+fx.text()+'))/('+fy.text()+')');return{latex:'\\frac{dy}{dx} = '+r.toTeX().replace(/\\mathrm\{log\}/g,'\\ln'),steps:['Differentiate F(x,y)=0: F_x + F_y dy/dx = 0.','Return −F_x/F_y where F_y ≠ 0. This is a local derivative, not a general differential-equation solution.'],resolved:{...q,variable:'x'}};
 }
 const inputOperation=q.operation==='inspect' ? q.inspectionOperation:q.operation;
 let parsed;
 const equation=q.inputA.split('=');
 if(equation.length===2&&inputOperation==='rootInterval')parsed={body:B('-',parse(equation[0]),parse(equation[1])),meta:{kind:'expression'}};
 else if(equation.length===2&&['partialDerivative','derivative','secondDerivative','evaluate','tangentLine','normalLine','limit','limitLeft','limitRight','averageRate','averageValue','areaBetween','volumeDisk','volumeShell','volumeWasher','arcLength','integral','definiteIntegral','numericalIntegral'].includes(inputOperation)){
  const header=equation[0].trim(),declaration=header.match(/^[fgh]\s*\(\s*([A-Za-z])\s*\)$/);
  if(header==='y'||declaration)parsed={body:parse(equation[1]),meta:{kind:'function',variable:declaration?.[1]}};
 }
 if(!parsed)parsed=fullInput(q.inputA);
 const {body:a,meta}=parsed,vars=variables(a);let v=(inputOperation==='partialDerivative'?q.variable:null)||meta.variable||([...vars][0])||(!['e','i'].includes(q.variable)?q.variable:null)||'x';
 if(v==='i'||v==='e')fail('e and i are reserved constants; use x, t or another real variable.');
 if(!/^[A-Za-z]$/.test(v)||(inputOperation!=='partialDerivative'&&(vars.size>1||[...vars].some(z=>z!==v))))fail('Use one independent Latin-letter variable. Multivariable expressions are not supported in this menu.');
 function validateConstants(tree){if(!variables(tree).size){scalar(tree,'Constant');return;}if(tree.a)validateConstants(tree.a);if(tree.b)validateConstants(tree.b);}
 validateConstants(a);
 const usesPoint=['evaluate','limit','limitLeft','limitRight','tangentLine','normalLine'].includes(inputOperation),usesInterval=['definiteIntegral','numericalIntegral','averageRate','averageValue','areaBetween','volumeDisk','volumeShell','volumeWasher','arcLength','rootInterval'].includes(inputOperation);
 const parameter=(value,label,fallback)=>{if(value!=null&&!String(value).trim())fail('Enter the '+label+'.');return parse(value??fallback);};
 const expr=cas(a),rawPoint=meta.pointAST||(usesPoint?parameter(q.point,'point','2'):N(2)),lower=meta.lowerAST||(usesInterval?parameter(q.lower,'lower limit','0'):N(0)),upper=meta.upperAST||(usesInterval?parameter(q.upper,'upper limit','1'):N(1));
 const resolved={...q,variable:v,point:cas(rawPoint),lower:cas(lower),upper:cas(upper)};
 const latex=n(expr).toTeX().replace(/\\mathrm\{log\}/g,'\\ln');let steps=[],out;
 if(q.operation==='inspect'){if(usesPoint)scalar(rawPoint,'Point',['limit','limitLeft','limitRight'].includes(inputOperation));if(usesInterval){scalar(lower,'Lower limit');scalar(upper,'Upper limit');}return{latex,steps:[],review:{variable:v,integrand:latex,kind:meta.kind,lower:meta.lowerAST?n(cas(lower)).toTeX().replace(/\\mathrm\{log\}/g,'\\ln'):null,upper:meta.upperAST?n(cas(upper)).toTeX().replace(/\\mathrm\{log\}/g,'\\ln'):null,point:meta.pointAST?n(cas(rawPoint)).toTeX().replace(/\\mathrm\{log\}/g,'\\ln'):null,direction:meta.direction||null}};}
 if(meta.kind==='limit'&&!['limit','limitLeft','limitRight'].includes(q.operation))fail('Choose a limit operation for this row, or remove the limit notation to work with the function itself.');
 if(meta.kind==='integral'||meta.kind==='definiteIntegral'){
  if(!['integral','definiteIntegral','numericalIntegral','averageValue','volumeDisk','volumeShell'].includes(q.operation))fail('Choose an integration operation for this full integral, or enter the function without its integral sign.');
  if(meta.kind==='definiteIntegral'&&q.operation==='integral')fail('This row has limits. Choose Definite integral.');
 }
 const derive=order=>n.diff(expr,v,order);
 const ensureSolved=e=>{if(/(?:integrate|limit|sum)\(/.test(e.text()))fail('The symbolic engine could not resolve this expression. For a finite definite integral, try Numerical integral.');return e;};
 function anti(expression){let result=ensureSolved(n.integrate(expression,v));const check=n.simplify('('+n.diff(result,v).text()+')-('+expression+')');if(check.text()!=='0')fail('The proposed antiderivative could not be verified by differentiation. Try Numerical integral for finite limits.');return result;}
 const valueAt=(expression,x)=>ensureSolved(n(expression,{[v]:n(cas(x))}));
 const approximate=(ast,lo,hi,extra='')=>{const result=numericalIntegral(ast,lo,hi,v);steps=['Numerical approximation (adaptive Simpson, radians).'+extra,'Estimated quadrature error '+result.error.toExponential(2)+'; '+result.evaluations+' evaluations. This estimate is not a proof of exactness.','Continuity was conservatively checked on the finite interval; unresolved domains are rejected.'];return '\\approx '+approximateTeX(result.value);};
 switch(q.operation){
 case'partialDerivative':case'derivative':case'secondDerivative':{
  const order=q.operation==='secondDerivative'?2:1,conditions=[];
  function boundaries(t){
   if(t.k==='f'&&t.v==='abs'&&variables(t.a).size)conditions.push(t.a);
   if(t.k==='b'&&t.v==='^'&&!variables(t.b).size){const power=numeric(t.b,0,v);if(!Number.isInteger(power)&&power>0&&power<order&&variables(t.a).size)conditions.push(t.a);}
   if(t.a)boundaries(t.a);if(t.b)boundaries(t.b);
  }boundaries(a);
  out=derive(order).toTeX().replace(/\\mathrm\{log\}/g,'\\ln');
  steps=[q.operation==='partialDerivative'?'Differentiate with respect to '+v+' holding the other independent variables constant.':'Differentiate symbolically using product, quotient and chain rules; trig functions use radians.','The derivative applies only where the original expression and derivative are real and defined.'];
  if(conditions.length){const unique=[...new Set(conditions.map(cas))];out+='\\quad\\text{for }'+unique.map(t=>n(t).toTeX()+'\\ne0').join(',\\;');steps.push('This formula is stated away from zeros of absolute-value or fractional-power arguments. Additional zero points need separate one-sided derivative analysis; differentiability there is not assumed.');}
  break;
 }
 case'integral':{const result=anti(expr);let tree;try{tree=parse(result.text(),true);if([...variables(tree)].some(x=>x!==v))throw new Error();}catch{fail('No supported elementary antiderivative. For a finite interval, choose Numerical definite integral.');}out=n(cas(realLogs(tree))).toTeX().replace(/\\mathrm\{log\}/g,'\\ln')+' + '+(v==='C'?'C_{1}':'C');steps=['Symbolic antiderivative verified by simplifying F′ − f to zero.','Natural logarithms are written with absolute values for real antiderivatives. Valid on intervals where the original function is defined.'];break;}
 case'definiteIntegral':case'averageValue':case'volumeDisk':case'volumeShell':case'volumeWasher':{
  const lo=scalar(lower,'Lower limit'),hi=scalar(upper,'Upper limit');interval(a,Math.min(lo,hi),Math.max(lo,hi),v);
  if(['volumeDisk','volumeShell','volumeWasher'].includes(q.operation)&&hi<lo)fail('Volume needs lower ≤ upper.');
  if(q.operation==='averageValue'&&lo===hi)fail('Average value needs different lower and upper limits.');
  if(q.operation==='volumeShell'&&(Math.min(lo,hi)<0))fail('Shells currently use a nonnegative x-radius about the y-axis. Choose an interval with x ≥ 0.');
  let f=expr;if(q.operation==='volumeDisk')f='pi*('+expr+')^2';if(q.operation==='volumeShell'){
   const range=interval(a,lo,hi,v);
   if(range[0]>=0)f='2*pi*'+v+'*('+expr+')';
   else if(range[1]<=0)f='-2*pi*'+v+'*('+expr+')';
   else {out=approximate(B('*',B('*',N(2),{k:'c',v:'pi'}),B('*',V(v),F('abs',a))),lo,hi,' Shells about the y-axis, including height sign changes.');break;}
  }
  if(q.operation==='volumeWasher'){
   const inner=parse(q.inputB||'');if([...variables(inner)].some(z=>z!==v))fail('Use the same variable for both radii.');
   const outerRange=interval(a,lo,hi,v),innerRange=interval(inner,lo,hi,v),difference=interval(B('-',a,inner),lo,hi,v);
   if(outerRange[0]<0||innerRange[0]<0||difference[0]<0)fail('Enter nonnegative outer and inner radii with outer ≥ inner throughout the interval. Split intervals where they cross.');
   f='pi*(('+expr+')^2-('+cas(inner)+')^2)';
  }
  const F=anti(f),atLow=valueAt(F.text(),lower),atHigh=valueAt(F.text(),upper);let r=n.simplify('('+atHigh.text()+')-('+atLow.text()+')');
  if(q.operation==='averageValue')r=n('('+r.text()+')/(('+cas(upper)+')-('+cas(lower)+'))');
  ensureSolved(r);const resultAST=parse(r.text(),true);scalar(resultAST,'Result');out=r.toTeX().replace(/\\mathrm\{log\}/g,'\\ln');steps=['Symbolic antiderivative checked by differentiation.','Use the fundamental theorem on a continuity-checked finite interval: F(upper) − F(lower).'];
  if(q.operation==='averageValue')steps.push('Divide by upper − lower for the average value.');if(q.operation==='volumeDisk')steps.push('Disk method about the x-axis: π ∫ f(x)² dx.');if(q.operation==='volumeWasher')steps.push('Washers about the x-axis: π ∫ (R² − r²) dx, with nonnegative radii and R ≥ r.');if(q.operation==='volumeShell')steps.push('Shell method about the y-axis: 2π ∫ x |f(x)| dx with x ≥ 0.');break;}
 case'numericalIntegral':out=approximate(a,scalar(lower,'Lower limit'),scalar(upper,'Upper limit'));break;
 case'evaluate':{const x=scalar(rawPoint,'Evaluation point');numeric(a,x,v);out=valueAt(expr,rawPoint).toTeX().replace(/\\mathrm\{log\}/g,'\\ln');steps=['Substitute '+v+' at the reviewed point, in radians.','Only finite real values are accepted.'];break;}
 case'limit':case'limitLeft':case'limitRight':{scalar(rawPoint,'Approach point',true);let dir=meta.direction||({limitLeft:'left',limitRight:'right'}[q.operation])||'both';resolved.operation=dir==='left'?'limitLeft':dir==='right'?'limitRight':'limit';
  const point=scalar(rawPoint,'Approach point',true);
  if(Number.isFinite(point)){
   const eps=1e-5*Math.max(1,Math.abs(point));
   if(dir!=='right')interval(a,point-2*eps,point-eps,v);
   if(dir!=='left')interval(a,point+eps,point+2*eps,v);
  }
  let result;
  try{result=ensureSolved(n.limit(expr,v,cas(rawPoint),dir));}
  catch(error){
   // A known real logarithm limit: log(g) -> -infinity when g -> 0+
   // and the requested side(s) have passed the real-domain check above.
   if(a.k==='f'&&a.v==='log'&&n.limit(cas(a.a),v,cas(rawPoint),dir).text()==='0')result=n('-Inf');
   else fail('Could not resolve this limit symbolically. It may be nonexistent or outside the supported rules.');
  }
  scalar(parse(result.text(),true),'Limit',true);out=result.toTeX().replace(/\\mathrm\{log\}/g,'\\ln');steps=['Symbolic '+(dir==='both'?'two-sided':dir+'-hand')+' limit as '+v+' approaches the reviewed point.','An unresolved limit is reported as unsupported or nonexistent, never silently returned as a computed value.'];break;}
 case'tangentLine':case'normalLine':{const x=scalar(rawPoint,'Point'),y=numeric(a,x,v),d=derive(1),slope=numeric(parse(d.text(),true),x,v);let m=valueAt(d.text(),rawPoint),y0=valueAt(expr,rawPoint);
  if(q.operation==='normalLine'&&slope===0)out=v+' = '+n(cas(rawPoint)).toTeX().replace(/\\mathrm\{log\}/g,'\\ln');else{if(q.operation==='normalLine')m=n('(-1)/('+m.text()+')');out='y = '+n('('+m.text()+')*('+v+'-('+cas(rawPoint)+'))+('+y0.text()+')').toTeX().replace(/\\mathrm\{log\}/g,'\\ln');}
  if(!Number.isFinite(y))fail('The function is not defined at this point.');steps=['Evaluate the function and its derivative at the reviewed point.','Tangent slope is f′(a); normal slope is −1/f′(a). A zero tangent slope gives a vertical normal.'];break;}
 case'averageRate':{const lo=scalar(lower,'First point'),hi=scalar(upper,'Second point');if(lo===hi)fail('Average rate needs two different points.');numeric(a,lo,v);numeric(a,hi,v);out=n('(('+valueAt(expr,upper).text()+')-('+valueAt(expr,lower).text()+'))/(('+cas(upper)+')-('+cas(lower)+'))').toTeX().replace(/\\mathrm\{log\}/g,'\\ln');steps=['Average rate / secant slope: (f(b) − f(a)) / (b − a).'];break;}
 case'areaBetween':{const other=parse(q.inputB||'');if([...variables(other)].some(x=>x!==v))fail('Both curves must use the same variable.');const lo=scalar(lower,'Lower limit'),hi=scalar(upper,'Upper limit');if(hi<lo)fail('Area needs lower ≤ upper.');interval(other,lo,hi,v);out=approximate(F('abs',B('-',a,other)),lo,hi,' Area is ∫ |f − g|, including curve crossings.');break;}
 case'arcLength':{const lo=scalar(lower,'Lower limit'),hi=scalar(upper,'Upper limit');if(hi<lo)fail('Arc length needs lower ≤ upper.');interval(a,lo,hi,v);const d=parse(derive(1).text(),true);out=approximate(B('^',B('+',N(1),B('^',d,N(2))),B('/',N(1),N(2))),lo,hi,' Arc length is ∫ sqrt(1 + f′²).');break;}
 case'rootInterval':{let lo=scalar(lower,'Lower bracket'),hi=scalar(upper,'Upper bracket');if(lo>=hi)fail('Root bracket needs lower < upper.');interval(a,lo,hi,v);let fl=numeric(a,lo,v),fh=numeric(a,hi,v),x;if(fl===0)x=lo;else if(fh===0)x=hi;else{if(fl*fh>0)fail('No sign change across this bracket. Choose a bracket around one root; this does not prove there are no roots.');for(let i=0;i<100;i++){x=(lo+hi)/2;const fx=numeric(a,x,v);if(fx===0||hi-lo<1e-11*Math.max(1,Math.abs(x)))break;if(fl*fx<0){hi=x;fh=fx;}else{lo=x;fl=fx;}}}out=v+' \\approx '+approximateTeX(x);steps=['Numerical root in the reviewed continuous bracket by bisection.','Reports one bracketed root; not all roots or a symbolic solution set.'];break;}
 case'simplify':out=n.simplify(expr).toTeX().replace(/\\mathrm\{log\}/g,'\\ln');steps=['Symbolic simplification. Original domain exclusions remain in force.'];break;
 case'expand':{const terms=t=>{if(t.k!=='b')return 1;const l=terms(t.a),r=terms(t.b);if(t.v==='+'||t.v==='-')return Math.min(501,l+r);if(t.v==='*')return Math.min(501,l*r);if(t.v==='^'&&!variables(t.b).size){const e=scalar(t.b,'Power');if(Number.isInteger(e)&&e>=0)return Math.min(501,Math.pow(l,e));}return 1;};if(terms(a)>500)fail('This expansion would be too large. Use smaller powers or split the expression.');out=n.expand(expr).toTeX().replace(/\\mathrm\{log\}/g,'\\ln');steps=['Expand the expression symbolically.'];break;}
 case'arithmetic':if(vars.size)fail('Calculate accepts constants only; choose Evaluate for a function.');scalar(a,'Expression');out=n(expr).toTeX().replace(/\\mathrm\{log\}/g,'\\ln');steps=['Evaluate a constant expression symbolically; angles are in radians.'];break;
 }
 if(typeof out!=='string'||!out||out.length>12000||/NaN|undefined/.test(out))fail('No supported finite result was produced.');
 return{latex:out,steps,resolved};
}
root.FolioCalc1={compute,parse,fullInput,cas,numeric,interval};
if(typeof root.postMessage==='function')root.onmessage=function(event){try{const result=compute(event.data,root.nerdamer);root.postMessage({ok:true,...result});}catch(e){root.postMessage({ok:false,error:e.message||'Computation failed.'});}};
})(typeof self!=='undefined'?self:globalThis);
