"""Reproduce Fig.3-2 panel crops from the downloaded LM-7 handbook.

Requires pypdfium2 and Pillow. Does not alter the source PDF or the control inventory.
The crop metadata is measured in the 2376x1134 (1.5x) page rendering.
"""
import argparse
import json
from pathlib import Path
import pypdfium2 as pdfium

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pdf',default='D:/apollo-ref/lm-systems/a13-lm-aoh-v1-lm7-subs-300ppi.pdf')
parser.add_argument('--output',type=Path,default=root/'reference/extracts')
parser.add_argument('--include-overviews',action='store_true')
args=parser.parse_args()
metadata=json.loads((root/'reference/extracts/panel-crops.json').read_text(encoding='utf-8'))
pdf=pdfium.PdfDocument(args.pdf)
image=pdf[metadata['pdfPage']-1].render(scale=4).to_pil()
args.output.mkdir(parents=True,exist_ok=True)
ratio=image.width/metadata['baseRenderSize'][0]
for panel,crop in metadata['panels'].items():
    bounds=tuple(round(v*ratio) for v in crop['cropBasePixels'])
    image.crop(bounds).save(args.output/f'panel-{panel}.png')
if args.include_overviews:
    for n in [23,25]:
        pdf[n-1].render(scale=2).to_pil().save(args.output/f'lm7-aoh-p{n:03}.png')
print(f'Extracted {len(metadata["panels"])} panel crops from PDF page {metadata["pdfPage"]}.')
