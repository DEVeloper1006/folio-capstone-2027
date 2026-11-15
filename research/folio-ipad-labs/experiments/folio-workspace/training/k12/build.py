"""Create deterministic expression-disjoint manifests. Images are rendered separately."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import sys
import xml.etree.ElementTree as ET
sys.path.insert(0, str(Path(__file__).resolve().parent))
from catalog import FAMILIES, generate


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=Path('artifacts/k12-dataset'))
    parser.add_argument('--train',type=int,default=32)
    parser.add_argument('--valid',type=int,default=4)
    parser.add_argument('--test',type=int,default=4)
    parser.add_argument('--mathwriting',type=Path)
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    rng=random.Random(271028)
    used=set(); splits={s:[] for s in ['train','valid','test']}
    for family in FAMILIES:
        for split,count in [('train',args.train),('valid',args.valid),('test',args.test)]:
            for _ in range(count):
                for attempt in range(10000):
                    latex=generate(family,rng)
                    if latex not in used: break
                else: raise RuntimeError('Not enough unique labels: '+family.name)
                used.add(latex)
                id=hashlib.sha256(latex.encode()).hexdigest()[:20]
                splits[split].append(dict(id=id,latex=latex,split=split,family=family.name,band=family.band,topic=family.topic,
                    mode='numbers' if family.numeric else 'math',image=f'images/{split}/{id}.png',source='original-synthetic',
                    representation='typeset',license='original-project-content',seed=rng.randrange(2**31)))
    # Import public train samples only. Previously inspected public valid/test
    # samples remain regression data, not part of a new clean training split.
    if args.mathwriting:
        from PIL import Image,ImageDraw
        for path in sorted((args.mathwriting/'train').glob('*.inkml')):
            root=ET.parse(path).getroot()
            a={x.attrib.get('type'):x.text for x in root if x.tag.endswith('annotation')}
            latex=a.get('normalizedLabel',a.get('label',''))
            if not latex or latex in used: continue
            used.add(latex)
            traces=[[tuple(map(float,p.split()[:2])) for p in t.text.split(',')] for t in root if t.tag.endswith('trace')]
            points=[p for trace in traces for p in trace]
            x0,y0=min(p[0] for p in points),min(p[1] for p in points)
            w,h=max(p[0] for p in points)-x0,max(p[1] for p in points)-y0
            scale=min(1,900/max(w,h,1))
            image=Image.new('RGB',(int(w*scale)+32,int(h*scale)+32),'white')
            draw=ImageDraw.Draw(image)
            for trace in traces:
                xy=[((x-x0)*scale+16,(y-y0)*scale+16) for x,y in trace]
                if len(xy)>1: draw.line(xy,fill='black',width=3,joint='curve')
                else: draw.ellipse((xy[0][0]-1,xy[0][1]-1,xy[0][0]+1,xy[0][1]+1),fill='black')
            id='mw-'+path.stem; relative=f'images/train/{id}.png'
            (args.output/'images/train').mkdir(parents=True,exist_ok=True)
            image.save(args.output/relative)
            stroke_path=f'strokes/{id}.inkml';(args.output/'strokes').mkdir(exist_ok=True)
            (args.output/stroke_path).write_bytes(path.read_bytes())
            splits['train'].append(dict(id=id,latex=latex,split='train',family='public_handwriting',band='unmapped',topic='Mixed notation',
                mode='math',image=relative,strokes=stroke_path,source='MathWriting-2024-excerpt/train',representation='human-handwriting',license='CC-BY-NC-SA-4.0; source expressions CC-BY-SA',seed=0))
    for split,records in splits.items():
        (args.output/f'{split}.jsonl').write_text(''.join(json.dumps(row)+'\n' for row in records))
    summary=dict(seed=271028,families=len(FAMILIES),counts={k:len(v) for k,v in splits.items()},split_method='Exact-expression-disjoint; shared template families. Not writer-disjoint or template-disjoint.',
        scope='Ontario-inspired notation coverage, not exhaustive curriculum compliance.',
        sources=['https://www.ontario.ca/page/math-curriculum-grades-1-8','https://www.dcp.edu.gov.on.ca/en/math','https://www.edu.gov.on.ca/eng/curriculum/secondary/math1112currb.pdf'])
    (args.output/'dataset.json').write_text(json.dumps(summary,indent=2))
    (args.output/'coverage.json').write_text(json.dumps([f.__dict__ for f in FAMILIES],indent=2))
    print(json.dumps(summary,indent=2))

if __name__=='__main__':main()
