import {chromium} from 'playwright';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const root=path.resolve(process.argv[2]||'artifacts/k12-dataset');
const katex=path.resolve('node_modules/katex/dist');
const records=[];
for(const split of ['train','valid','test'])records.push(...(await fs.readFile(path.join(root,split+'.jsonl'),'utf8')).trim().split('\n').filter(Boolean).map(JSON.parse));
const browser=await chromium.launch({headless:true});
const failures=[];let cursor=0, rendered=0;
await Promise.all(Array.from({length:4},async()=>{
 const page=await browser.newPage({viewport:{width:2200,height:1400},deviceScaleFactor:1});
 await page.goto(pathToFileURL(katex+'/README.md').href);
 await page.setContent('<html><head></head><body><div id="math" style="display:inline-block;padding:16px;background:white;color:black"></div></body></html>');
 await page.addStyleTag({path:katex+'/katex.min.css'});
 // CSS font URLs otherwise resolve against about:blank after setContent.
 await page.addStyleTag({content:await fs.readFile(katex+'/katex.min.css','utf8').then(x=>x.replaceAll('url(fonts/','url('+pathToFileURL(katex+'/fonts/').href))});
 await page.addScriptTag({path:katex+'/katex.min.js'});
 while(cursor<records.length){
  const row=records[cursor++];
  if(row.source!=='original-synthetic')continue;
  const file=path.join(root,row.image);
  try{await fs.access(file);continue;}catch{}
  try{
   await page.evaluate(({latex,seed})=>{document.querySelector('#math').style.fontSize=(24+seed%13)+'px';katex.render(latex,document.querySelector('#math'),{throwOnError:true,trust:false,displayMode:true,strict:'error'});},{latex:row.latex,seed:row.seed});
   await page.evaluate(()=>document.fonts.ready);
   await fs.mkdir(path.dirname(file),{recursive:true});
   await page.locator('#math').screenshot({path:file});
   rendered++;if(rendered%200===0)console.log('Rendered',rendered);
  }catch(e){failures.push({id:row.id,latex:row.latex,error:String(e)});}
 }
 await page.close();
}));
await browser.close();
await fs.writeFile(path.join(root,'render-errors.json'),JSON.stringify(failures,null,2));
console.log('Rendered',rendered,'failures',failures.length);
if(failures.length)process.exitCode=1;
