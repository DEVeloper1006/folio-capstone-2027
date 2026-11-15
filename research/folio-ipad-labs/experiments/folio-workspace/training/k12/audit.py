import hashlib
import json
from pathlib import Path
import sys
from PIL import Image
from transformers import RobertaTokenizerFast

root=Path(sys.argv[1] if len(sys.argv)>1 else 'artifacts/k12-dataset')
tokenizer=RobertaTokenizerFast.from_pretrained('OleehyO/TexTeller',revision='7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea',local_files_only=True)
labels={}; hashes={}; failures=[]; counts={}; max_tokens=0
for split in ['train','valid','test']:
    records=[json.loads(line) for line in (root/f'{split}.jsonl').read_text().splitlines()]
    counts[split]=len(records)
    for row in records:
        if row['latex'] in labels: failures.append('Duplicate label '+row['id'])
        labels[row['latex']]=split
        file=root/row['image']
        if not file.exists(): failures.append('Missing '+str(file));continue
        image=Image.open(file); image.verify()
        digest=hashlib.sha256(file.read_bytes()).hexdigest()
        if digest in hashes and hashes[digest]!=split: failures.append('Cross-split image duplicate '+row['id'])
        hashes[digest]=split
        target=tokenizer.encode(r'\['+row['latex']+r'\]',add_special_tokens=False)
        max_tokens=max(max_tokens,len(target)+1)
        if len(target)+1>192: failures.append('Over token limit '+row['id'])
        if split!='train' and row['source'].startswith('MathWriting'): failures.append('Previously seen public regression data in clean synthetic holdout')
report={'counts':counts,'max_target_tokens':max_tokens,'failures':failures,'exact_label_overlap':len(labels)!=sum(counts.values())}
(root/'audit.json').write_text(json.dumps(report,indent=2)); print(json.dumps(report,indent=2))
if failures:sys.exit(1)
