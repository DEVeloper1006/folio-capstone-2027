"""Baseline or adapter evaluation without changing the live service."""
import argparse
import base64
import json
from pathlib import Path
import re
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from server.local_ocr import Recognizer


def normalize(text):
    text=text.replace(r'\left','').replace(r'\right','').replace(r'\,','').replace(r'\!','')
    text=re.sub(r'([_^])\{([^{}])\}',r'\1\2',text)
    return re.sub(r'\s+','',text)


def main():
    p=argparse.ArgumentParser();p.add_argument('--data',type=Path,default=Path('artifacts/k12-dataset'));p.add_argument('--split',choices=['valid','test'],default='valid');p.add_argument('--adapter',type=Path);p.add_argument('--regression-dir',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--limit',type=int);args=p.parse_args()
    engine=Recognizer()
    if args.adapter:
        from peft import PeftModel
        engine.model=PeftModel.from_pretrained(engine.model,str(args.adapter)).eval()
    if args.regression_dir:
        args.data=args.regression_dir
        args.split='handwriting-regression'
        rows=[{'id':r['id'],'family':'real_handwriting','band':'mixed','latex':r['expected'],'mode':'math','image':r['id']+'.png'} for r in json.loads((args.data/'results.json').read_text())]
    else:
        rows=[json.loads(x) for x in (args.data/f'{args.split}.jsonl').read_text().splitlines()]
    if args.limit:rows=rows[:args.limit]
    results=[];args.output.mkdir(parents=True,exist_ok=True)
    for i,row in enumerate(rows):
        start=time.monotonic()
        try:
            prediction=engine.recognize('data:image/png;base64,'+base64.b64encode((args.data/row['image']).read_bytes()).decode(),row['mode'])
        except Exception as exc:prediction={'latex':'','alternatives':[],'error':str(exc)}
        actual=prediction['latex'];candidates=[actual]+prediction.get('alternatives',[])
        results.append({'id':row['id'],'family':row['family'],'band':row['band'],'expected':row['latex'],'actual':actual,
            'match':normalize(actual)==normalize(row['latex']),'top3':any(normalize(v)==normalize(row['latex']) for v in candidates),
            'mode':row['mode'],'seconds':round(time.monotonic()-start,3),'error':prediction.get('error')})
        if (i+1)%40==0:print(i+1,'/',len(rows),flush=True)
        (args.output/'results.json').write_text(json.dumps(results,indent=2))
    groups={}
    for row in results:
        value=groups.setdefault(row['family'],{'total':0,'matched':0,'top3':0,'errors':0})
        value['total']+=1;value['matched']+=row['match'];value['top3']+=row['top3'];value['errors']+=bool(row['error'])
    summary={'split':args.split,'adapter':str(args.adapter) if args.adapter else None,'total':len(rows),'matched':sum(r['match'] for r in results),'top3':sum(r['top3'] for r in results),'families':groups}
    (args.output/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps({k:v for k,v in summary.items() if k!='families'}))

if __name__=='__main__':main()
