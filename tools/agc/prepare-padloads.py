"""Deskew photocopied padload page renderings and remove long ruled lines for OCR.
Only derivative images are changed; source PDFs remain untouched.
"""
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('input',type=Path)
p.add_argument('output',type=Path)
p.add_argument('--first-only',action='store_true')
args=p.parse_args()
args.output.mkdir(parents=True,exist_ok=True)
paths=sorted(args.input.glob('*.png')) if args.input.is_dir() else [args.input]
if args.first_only: paths=paths[:1]
meta=[]
for source in paths:
    image=Image.open(source).convert('L')
    sample=image.copy();sample.thumbnail((900,900))
    best_score=-1;best_angle=0
    for angle in np.arange(-2.0,2.01,0.05):
        data=np.asarray(sample.rotate(float(angle),resample=Image.Resampling.BILINEAR,fillcolor=255))
        ink=(data<150).sum(axis=1)
        score=np.sort(ink)[-16:].astype(np.int64).dot(np.sort(ink)[-16:].astype(np.int64))
        if score>best_score: best_score=score;best_angle=float(angle)
    rotated=image.rotate(best_angle,resample=Image.Resampling.BICUBIC,fillcolor=255)
    pixels=np.array(rotated)
    black=pixels<175
    removed=0
    minimum=max(90,image.width//20)
    for y,row in enumerate(black):
        changes=np.diff(np.r_[False,row,False].astype(np.int8))
        starts=np.flatnonzero(changes==1);ends=np.flatnonzero(changes==-1)
        for start,end in zip(starts,ends):
            if end-start>=minimum:
                pixels[max(0,y-1):min(image.height,y+2),start:end]=255
                removed+=1
    # The primary table occupies the central page; retain headers and footers
    # as source anchors but remove unrelated scan borders.
    result=Image.fromarray(pixels).point(lambda x:255 if x>180 else 0)
    dest=args.output/source.name
    result.save(dest)
    meta.append({'source':str(source),'output':str(dest),'angleDegrees':best_angle,'ruleSegmentsRemoved':removed})
    print(f'{source.name} deskew={best_angle:.2f} removed={removed}')
(args.output/'preprocessing.json').write_text(json.dumps(meta,indent=2),encoding='utf-8')
