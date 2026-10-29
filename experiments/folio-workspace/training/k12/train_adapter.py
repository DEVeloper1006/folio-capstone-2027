"""Bounded LoRA pilot. Saves a candidate only; never modifies the live model."""
import argparse
import json
import math
import random
from pathlib import Path
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
import numpy as np
from PIL import Image
import torch
from peft import LoraConfig,get_peft_model
from server.local_ocr import Recognizer,preprocess,MODEL,REVISION


def main():
    p=argparse.ArgumentParser();p.add_argument('--data',type=Path,default=Path('artifacts/k12-dataset'));p.add_argument('--output',type=Path,required=True);p.add_argument('--steps',type=int,default=80);p.add_argument('--accumulate',type=int,default=2);p.add_argument('--allow-noncommercial-handwriting',action='store_true');args=p.parse_args()
    if args.output.exists():raise SystemExit('Use a new output directory; refusing to overwrite a candidate.')
    torch.manual_seed(271028);random.seed(271028);np.random.seed(271028)
    rows=[json.loads(x) for x in (args.data/'train.jsonl').read_text().splitlines()]
    if not args.allow_noncommercial_handwriting:rows=[r for r in rows if r['source']=='original-synthetic']
    if not rows:raise SystemExit('No eligible training rows')
    engine=Recognizer();model=get_peft_model(engine.model,LoraConfig(r=8,lora_alpha=16,lora_dropout=0.05,target_modules=['q_proj','v_proj'],bias='none'))
    model.config.decoder_start_token_id=engine.tokenizer.bos_token_id
    model.config.pad_token_id=engine.tokenizer.pad_token_id
    model.train();model.encoder.eval()
    parameters=[p for p in model.parameters() if p.requires_grad]
    optimizer=torch.optim.AdamW(parameters,lr=5e-5,weight_decay=0.01)
    args.output.mkdir(parents=True)
    rng=random.Random(271028);rng.shuffle(rows)
    losses=[];seen=[];start=time.monotonic();optimizer.zero_grad(set_to_none=True)
    for step in range(args.steps):
        total=0.0
        for micro in range(args.accumulate):
            row=rows[(step*args.accumulate+micro)%len(rows)]
            image=Image.open(args.data/row['image']).convert('L')
            # Mild training-only rotation; no augmentation of evaluation images.
            angle=rng.uniform(-0.8,0.8)
            image=image.rotate(angle,resample=Image.Resampling.BICUBIC,expand=True,fillcolor=255)
            pixels=preprocess(image).to(engine.device)
            target=engine.tokenizer.encode(r'\['+row['latex']+r'\]',add_special_tokens=False)+[engine.tokenizer.eos_token_id]
            if len(target)>192:raise ValueError('Training target exceeds inference limit')
            labels=torch.tensor([target],device=engine.device)
            output=model(pixel_values=pixels,labels=labels,use_cache=False)
            loss=output.loss/args.accumulate
            if not torch.isfinite(loss):raise RuntimeError('Non-finite training loss')
            loss.backward();total+=float(loss.detach().cpu());seen.append(row['id'])
        torch.nn.utils.clip_grad_norm_(parameters,1.0)
        optimizer.step();optimizer.zero_grad(set_to_none=True);losses.append(total)
        if (step+1)%10==0:print(json.dumps({'step':step+1,'loss':round(total,4),'seconds':round(time.monotonic()-start,1)}),flush=True)
    model.save_pretrained(args.output)
    report={'base_model':MODEL,'revision':REVISION,'steps':args.steps,'accumulate':args.accumulate,'examples_seen':len(seen),'unique_examples':len(set(seen)),
            'trainable_parameters':sum(p.numel() for p in parameters),'seconds':time.monotonic()-start,'losses':losses,'training_ids':seen,
            'noncommercial_handwriting_enabled':args.allow_noncommercial_handwriting,'deployment':'candidate only; not loaded by service'}
    (args.output/'training-report.json').write_text(json.dumps(report,indent=2));print('Candidate saved:',args.output)

if __name__=='__main__':main()
