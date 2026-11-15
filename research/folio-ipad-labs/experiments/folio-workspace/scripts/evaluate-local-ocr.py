"""Evaluate local OCR on fonts (smoke tests) or real MathWriting InkML.
No recognition labels are sent to the model. Run with the local OCR environment.
"""
import argparse
import base64
import io
import json
from pathlib import Path
import re
import time
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont
import httpx


def normalize(latex):
    # Formatting equivalence only. Preserve case, operators, and all digits.
    latex = latex.replace(r"\left", "").replace(r"\right", "")
    latex = latex.replace(r"\,", "").replace(r"\!", "")
    latex = re.sub(r"\\(?:mathrm|mathit)\{([^{}]*)\}", r"\1", latex)
    latex = re.sub(r"([_^])\{([^{}])\}", r"\1\2", latex)
    return re.sub(r"\s+", "", latex)


def inkml(path):
    root = ET.parse(path).getroot()
    annotations = {x.attrib.get('type'): x.text for x in root if x.tag.endswith('annotation')}
    strokes = [[tuple(map(float, p.split()[:2])) for p in trace.text.split(',')] for trace in root if trace.tag.endswith('trace')]
    points = [p for stroke in strokes for p in stroke]
    left, top = min(p[0] for p in points), min(p[1] for p in points)
    width, height = max(p[0] for p in points)-left, max(p[1] for p in points)-top
    scale = min(2, 1000/max(width, height, 1))
    image = Image.new('RGB', (int(width*scale)+32, int(height*scale)+32), 'white')
    draw = ImageDraw.Draw(image)
    normalized = []
    for stroke in strokes:
        xy = [((x-left)*scale+16, (y-top)*scale+16) for x,y in stroke]
        normalized.append(xy)
        draw.line(xy, fill='black', width=max(2, round(3*scale)), joint='curve')
    return annotations.get('normalizedLabel', annotations['label']), image, normalized


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inkml', type=Path)
    parser.add_argument('--limit', type=int, default=25)
    parser.add_argument('--mode', choices=['math', 'numbers'], default='math')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    cases = []
    if args.inkml:
        for path in args.inkml.glob('*.inkml'):
            label, image, strokes = inkml(path)
            cases.append((path.stem, label, image, strokes))
        cases = sorted(cases, key=lambda x: (len(x[1]), x[0]))[:args.limit]
    else:
        for name in ['Chalkboard', 'Comic Sans MS', 'Bradley Hand Bold']:
            path = Path('/System/Library/Fonts/Supplemental') / (name + ('.ttc' if name == 'Chalkboard' else '.ttf'))
            font = ImageFont.truetype(str(path), 48)
            for index, label in enumerate([*'0123456789', '12', '123', '2+2=4', '7-3=4', '3.14', '-12', '2x+3=7', 'x+y=5', '(x+1)(x-1)', 'y=2x+1']):
                if args.mode == 'numbers' and re.search('[a-zA-Z]', label):
                    continue
                image = Image.new('RGB', (700,110), 'white')
                ImageDraw.Draw(image).text((16,16), label, font=font, fill='black')
                cases.append((name.replace(' ', '-')+str(index), label, image, None))
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    with httpx.Client(timeout=90) as client:
        for id, label, image, strokes in cases:
            image.save(args.output / (id+'.png'))
            if strokes is not None:
                (args.output / (id+'.json')).write_text(json.dumps({'label':label,'strokes':strokes}))
            data = io.BytesIO(); image.save(data,format='PNG')
            start=time.monotonic()
            response=client.post('http://127.0.0.1:8002/recognize',json={'image':'data:image/png;base64,'+base64.b64encode(data.getvalue()).decode(), 'mode':args.mode})
            result=response.json(); prediction=result.get('latex','')
            row={'id':id,'expected':label,'actual':prediction,'match':normalize(label)==normalize(prediction),'seconds':round(time.monotonic()-start,3),'status':response.status_code,'alternatives':result.get('alternatives',[]),'mode':args.mode}
            results.append(row); print(json.dumps(row),flush=True)
            (args.output/'results.json').write_text(json.dumps(results,indent=2))
    print(f"Matches: {sum(x['match'] for x in results)}/{len(results)}")


if __name__ == '__main__': main()
