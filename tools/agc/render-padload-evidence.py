"""Render immutable source-page evidence for unresolved LM131R1 padload readings."""
import argparse
import hashlib
import json
from pathlib import Path
import pypdfium2 as pdf

root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--data-root',type=Path,default=Path('D:/apollo-ref'))
args=p.parse_args()
out=root/'reference/extracts/agc-padload'
out.mkdir(parents=True,exist_ok=True)
sources=[('memo','padload_13_lm.pdf',[1,2,3,6,8,12,13,15,16,20,23,24]),
         ('handbook','LM7_Pad_loads.pdf',[1,2,5,7,11,12,14,15,19])]
evidence=[]
for label,filename,pages in sources:
    source=args.data_root/'flight-software'/filename
    doc=pdf.PdfDocument(str(source))
    for page in pages:
        # Full frames preserve headings/footers; numeric-column crops remain
        # unfiltered source raster samples, with no OCR or reconstructed text.
        full=doc[page-1].render(scale=2).to_pil()
        path=out/f'{label}-p{page:02d}-full.png';full.save(path)
        evidence.append({'file':str(path.relative_to(root)),'sourcePdf':filename,
            'pdfPage':page,'scale':2,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        if (label=='memo' and 2<=page<=22) or label=='handbook':
            scale=3 if label=='memo' else 4
            box=(150,200,1125,1535) if label=='memo' else (200,240,1560,1627)
            im=doc[page-1].render(scale=scale).to_pil().crop(box)
            path=out/f'{label}-p{page:02d}-numbers.png';im.save(path)
            evidence.append({'file':str(path.relative_to(root)),'sourcePdf':filename,
                'pdfPage':page,'scale':scale,'cropPixels':box,
                'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(out/'evidence.json').write_text(json.dumps({'schemaVersion':1,'images':evidence},indent=2)+'\n')
print(f'Rendered {len(evidence)} source evidence images to {out}')
