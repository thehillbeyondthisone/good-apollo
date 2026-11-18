"""Validate manually read octal words against assembled symbols and a second source table.
Does not load AGC memory. Source disagreements remain explicit and block promotion.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data-root',type=Path,default=Path('D:/apollo-ref'))
args=parser.parse_args()
listing=(args.data_root/'build/agc/LM131R1/assembly.log').read_text(encoding='utf-8',errors='replace')
symbols={}
for name,bank,sreg in re.findall(r'\d+,E:\s+(\S+)\s+(?:E([0-7]),)?([0-7]{4})',listing):
    location=int(sreg,8)
    symbols[name]=int(bank,8)*256+(location-0o1400) if bank else location

def lines(path):
    for number,line in enumerate(path.read_text(encoding='utf-8').splitlines(),1):
        if line and not line.startswith('#'): yield number,line.split('|')

entries={};errors=[];groups=0;parity_checked=0
for line,(page,name,offset,start,words,method) in lines(root/'reference/lm131r1-prelaunch-transcription.psv'):
    groups+=1;offset=int(offset);address=int(start,8)
    if name not in symbols or symbols[name]+offset!=address:
        errors.append(f'Line {line}: symbol/address disagreement for {name}+{offset} at {start}')
    if method not in ('none','uplink','dsky'): errors.append(f'Line {line}: invalid loading method')
    for index,value in enumerate(words.split()):
        if not re.fullmatch('[0-7]{5}',value): errors.append(f'Line {line}: invalid octal word {value}')
        current=address+index
        if current in entries: errors.append(f'Duplicate address {current:04o}')
        if not 0o10<=current<0o4000: errors.append(f'Out-of-range erasable address {current:04o}')
        numeric=int(value,8)
        # Source tables give 15 data bits, not stored parity. This encoding is an
        # independently checked representation, never evidence of source parity.
        parity=1-(numeric.bit_count()%2)
        encoded=(numeric<<1)|parity
        if encoded.bit_count()%2!=1 or encoded>>1!=numeric or not 0<=numeric<=0o77777:
            errors.append(f'Line {line}: odd-parity encoding or range failure')
        else: parity_checked+=1
        entries[current]={'addressOctal':f'{current:04o}','address':current,'valueOctal':value,'value':numeric,
            'computedOddParityBit':parity,'computedDataShiftedLeftWithParityLsbOctal':f'{encoded:06o}',
            'symbol':name,'wordOffset':offset+index,'pdfPage':int(page),'printedTablePage':int(page)-1,
            'inflightLoadingMethod':method,'reviewStatus':'single-scan-transcription'}

uplink_entries={};blocks=[]
for line,(column,count,start,words) in lines(root/'reference/lm131r1-uplink-transcription.psv'):
    values=words.split();address=int(start,8)
    if len(values)+2!=int(count,8): errors.append(f'Uplink column {column}: count mismatch')
    blocks.append({'column':column,'wordCountOctal':count,'startAddressOctal':start,'valuesOctal':values,'pdfPage':23})
    for index,value in enumerate(values):
        if not re.fullmatch('[0-7]{5}',value): errors.append(f'Uplink column {column}: invalid octal word {value}')
        if address+index in uplink_entries: errors.append('Overlapping uplink blocks')
        if not 0o10<=address+index<0o4000: errors.append('Out-of-range uplink erasable address')
        uplink_entries[address+index]=(value,column,index+3)

conflicts=[];confirmed=0;uplink_only=[]
for address,(value,column,row) in uplink_entries.items():
    if address not in entries:
        uplink_only.append({'addressOctal':f'{address:04o}','valueOctal':value,'column':column,'rowOctal':f'{row:02o}'})
        continue
    entry=entries[address]
    entry['uplinkSheet']={'pdfPage':23,'column':column,'rowOctal':f'{row:02o}','valueOctal':value}
    if value==entry['valueOctal']:
        entry['reviewStatus']='agrees-with-independent-uplink-table';confirmed+=1
    else:
        entry['reviewStatus']='source-disagreement'
        conflicts.append({'addressOctal':entry['addressOctal'],'symbol':entry['symbol'],
            'prelaunchValueOctal':entry['valueOctal'],'prelaunchPdfPage':entry['pdfPage'],
            'uplinkValueOctal':value,'uplinkPdfPage':23,'column':column,'rowOctal':f'{row:02o}'})
handbook_entries={};handbook_conflicts=[];handbook_confirmed=0
for line,(page,start,words) in lines(root/'reference/lm131r1-handbook-transcription.psv'):
    address=int(start,8)
    for index,value in enumerate(words.split()):
        current=address+index
        if not re.fullmatch('[0-7]{5}',value): errors.append(f'Handbook line {line}: invalid word')
        if not 0o10<=current<0o4000: errors.append(f'Handbook line {line}: out-of-range erasable address')
        if current in handbook_entries: errors.append(f'Handbook duplicate address {current:04o}')
        if not 0o10<=current<0o4000: errors.append('Handbook erasable address out of range')
        handbook_entries[current]=(value,int(page))
        if current not in entries:
            errors.append(f'Handbook-only address {current:04o}');continue
        entry=entries[current]
        entry['handbook']={'pdfPage':int(page),'valueOctal':value}
        if value==entry['valueOctal']:
            handbook_confirmed+=1
            if entry['reviewStatus']=='single-scan-transcription': entry['reviewStatus']='agrees-with-handbook-copy'
        else:
            entry['reviewStatus']='source-scan-disagreement'
            handbook_conflicts.append({'addressOctal':entry['addressOctal'],'symbol':entry['symbol'],
                'memoValueOctal':entry['valueOctal'],'memoPdfPage':entry['pdfPage'],
                'handbookValueOctal':value,'handbookPdfPage':int(page),
                'status':'Unresolved scan readings; neither source variant selected for loading'})
if set(handbook_entries)!=set(entries): errors.append('Handbook and memo address sets differ')
if uplink_only: errors.append('Uplink contains words absent from memo parameter list')
for label,actual,expected in [('symbol groups',groups,174),('memo words',len(entries),272),
    ('handbook words',len(handbook_entries),272),('uplink words',len(uplink_entries),182),('uplink blocks',len(blocks),12)]:
    if actual!=expected: errors.append(f'Expected {expected} {label}; found {actual}')
source=args.data_root/'flight-software/padload_13_lm.pdf'
handbook_source=args.data_root/'flight-software/LM7_Pad_loads.pdf'
result={'schemaVersion':2,'title':'LM131R1 prelaunch parameter source candidates, with unresolved scan variants',
    'source':{'path':str(source),'url':'https://www.ibiblio.org/apollo/Documents/padload_13_lm.pdf','sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'memo':'70-FS5-78','documentDate':'1970-03-26','prelaunchTablePdfPages':list(range(2,23)),'uplinkTablePdfPage':23,'plannedChangesPdfPage':24},
    'handbookSource':{'path':str(handbook_source),'url':'https://www.ibiblio.org/apollo/Documents/LM7_Pad_loads.pdf',
        'sha256':hashlib.sha256(handbook_source.read_bytes()).hexdigest(),'documentDate':'1970-03-30',
        'revision':'SNA-8-D-027(II), Rev2, Amendment61','table':'LM7/4.5.1-1','pdfPages':list(range(1,22))},
    'approvedForLoading':False,'scope':'Source candidate transcription only; not an adjudicated padload or complete flown erasable-memory checkpoint. Planned post-memo changes are not merged.',
    'parityScope':'The source lists 15-bit data without parity. Computed odd parity is only an encoding self-check; no original parity bit was recovered.',
    'validation':{'groups':groups,'prelaunchWords':len(entries),'symbolsValidated':not errors,'uplinkWords':len(uplink_entries),'crossConfirmedWords':confirmed,
        'handbookWords':len(handbook_entries),'handbookMatchingWords':handbook_confirmed,'handbookScanDisagreements':handbook_conflicts,
        'computedOddParityWordsChecked':parity_checked,'singleTableWords':sum(e['reviewStatus']=='single-scan-transcription' for e in entries.values()),
        'conflicts':conflicts,'uplinkOnlyWords':uplink_only,'errors':errors},
    'plannedChanges':[{'symbol':'WRENDPOS','engineeringValue':'609.6 m','valueOctal':'01142','sourcePdfPage':24},
        {'symbol':'WRENDVEL','engineeringValue':'0.006096 m/cs','valueOctal':'00144','sourcePdfPage':24},
        {'symbol':'WSHAFT','engineeringValue':'0.005 rad','valueOctal':'05075','sourcePdfPage':24},
        {'symbol':'R03 masses / TEPHEM / RLS','status':'Planned changes stated without complete finalized words; not applied','sourcePdfPage':24}],
    'words':[entries[a] for a in sorted(entries)],'uplinkBlocks':blocks}
out=root/'reference/lm131r1-prelaunch.json'
out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result['validation'],indent=2))
if errors: raise SystemExit(1)
