"""Run final baseline/candidate comparisons durably. Never deploys a model."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'artifacts/k12-eval/final-comparison'
ADAPTER='artifacts/k12-adapters/pilot-500'
OUT.mkdir(parents=True,exist_ok=True)
state={'status':'running','started_at':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'pid':os.getpid(),'completed':[],'deployment':'unchanged'}


def save():
    temporary=OUT/'status.tmp'
    temporary.write_text(json.dumps(state,indent=2))
    temporary.replace(OUT/'status.json')


def run(name,args):
    state['current']=name;save()
    command=[sys.executable,'training/k12/evaluate.py',*args,'--output',str(OUT/name)]
    with (OUT/(name+'.log')).open('w') as log:
        subprocess.run(command,cwd=ROOT,env={**os.environ,'HF_HUB_OFFLINE':'1','TRANSFORMERS_OFFLINE':'1'},stdout=log,stderr=subprocess.STDOUT,check=True)
    state['completed'].append(name);save()

try:
    run('baseline-test',['--split','test'])
    run('candidate-test',['--split','test','--adapter',ADAPTER])
    run('baseline-handwriting',['--regression-dir','artifacts/ocr-human-test'])
    run('candidate-handwriting',['--regression-dir','artifacts/ocr-human-test','--adapter',ADAPTER])
    summaries={name:json.loads((OUT/name/'summary.json').read_text()) for name in state['completed']}
    table=[]
    for name,summary in summaries.items():
        table.append({'run':name,'matched':summary['matched'],'total':summary['total'],'top3':summary['top3']})
    synthetic_ok=summaries['candidate-test']['matched']>=summaries['baseline-test']['matched']
    handwriting_ok=summaries['candidate-handwriting']['matched']>=summaries['baseline-handwriting']['matched']
    report={'results':table,'synthetic_nonregression':synthetic_ok,'handwriting_nonregression':handwriting_ok,
            'passes_count_gate':synthetic_ok and handwriting_ok,'deployment':'unchanged; inspect topic regressions and native behavior before promotion',
            'caveats':['Synthetic test expressions are label-disjoint but share template families with training.',
                       'The handwriting set is a previously used regression set, not a new unseen benchmark.',
                       'Matching uses limited LaTeX formatting normalization, not mathematical equivalence.']}
    (OUT/'comparison.json').write_text(json.dumps(report,indent=2))
    state['status']='complete';state['current']=None;state['finished_at']=time.strftime('%Y-%m-%dT%H:%M:%S%z');save()
    print(json.dumps(report,indent=2),flush=True)
except Exception as error:
    state['status']='failed';state['error']=str(error);save()
    raise
