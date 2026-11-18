"""Derive dark, readable panel artwork from the LM-7 handbook foldout.

The source drawing is not a flight-state snapshot. Instrument values remain
illustrative, and all geometry/placement is independently marked provisional.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures"
OUT.mkdir(parents=True, exist_ok=True)
inventory = json.loads((ROOT / 'reference' / 'controls.json').read_text(encoding='utf-8-sig'))
panel_dimensions = {str(p['id']): (p['width_m'], p['height_m']) for p in inventory['panels']}
display_layout = {}
for control in inventory['controls']:
    if control['type'] != 'display':
        continue
    cid = control['id']
    u, v = control['layout']['u'], control['layout']['v']
    if 'dsky_' in cid:
        width = .084 if any(word in cid for word in ['prog_', 'verb_', 'noun_']) else .19
        height = .054
        mode = 'agc'
    elif cid == 'p1_mission_timer':
        width, height, mode = .31, .039, 'mission_clock'
    elif cid == 'p1_event_timer':
        width, height, mode = .18, .039, 'event_timer'
    elif 'deda_' in cid:
        width, height, mode = (.15 if 'address' in cid else .25), .065, 'unmodeled'
    else:
        width, height, mode = (.20 if 'helium' in cid else .14), .033, 'unmodeled'
    pw, ph = panel_dimensions[str(control['panel'])]
    display_layout[cid] = {
        'panel': str(control['panel']), 'center': [u, v],
        'uvRect': [u-width/2, v-height/2, u+width/2, v+height/2],
        'widthM': width*pw, 'heightM': height*ph, 'driver': mode,
    }

# Preserve original black instrument faces while reversing black-on-white
# placards to the light lettering used on the cabin's dark panel surfaces.
# Normalized image coordinates, measured from the top-left of each source crop.
INSTRUMENTS = {
    "1": [(0,.285,.33,.328),(.355,.285,.535,.328),(.57,.264,.72,.28),
          (.57,.307,.72,.33),(.76,.295,.947,.325),(.01,.399,.28,.542),
          (.14,.555,.53,.774),(.565,.401,.962,.53),(.56,.561,.758,.755),
          (.765,.56,.879,.754)],
    "2": [(.035,.258,.441,.384),(.458,.258,.739,.385),(.795,.258,.915,.385),
          (.458,.415,.738,.544),(.738,.403,.995,.548),(.459,.556,.872,.786)],
    "4": [(.548,.043,.747,.565)],
    "6": [(.57,.06,.83,.43)],
}

for source in sorted((ROOT / "reference" / "extracts").glob("panel-*.png")):
    panel_id = source.stem.split("-")[-1]
    image = Image.open(source).convert("L")
    gray = np.asarray(image, dtype=np.float32) / 255.0
    value = .12 + .71 * (1.0 - gray)
    width, height = image.size
    for x0, y0, x1, y1 in INSTRUMENTS.get(panel_id, []):
        region = (slice(int(y0*height), int(y1*height)), slice(int(x0*width), int(x1*width)))
        value[region] = .025 + .82 * gray[region]
    if panel_id == '16':
        # The foldout's book heading sits above this panel; it is not a placard.
        value[:int(.105*height), :] = .12
    for display in display_layout.values():
        if display['panel'] != panel_id:
            continue
        u0,v0,u1,v1 = display['uvRect']
        value[int((1-v1)*height):int((1-v0)*height), int(u0*width):int(u1*width)] = .025
    rgb = np.stack([value*.98, value, value*.94], axis=-1)
    target = OUT / f"panel-{panel_id}.png"
    Image.fromarray(np.clip(rgb*255, 0, 255).astype(np.uint8)).save(target)
    print(target.relative_to(ROOT))

(OUT / "provenance.json").write_text(json.dumps({
    "source": "LM-7 AOH Volume 1, Figure 3-2, PDF page 827, printed 3-157/3-158",
    "cropMetadata": "reference/extracts/panel-crops.json",
    "treatment": "Recolored placards; original instrument scales preserved; example digital values cleared for driven overlays.",
    "limitation": "Analog gauge artwork remains illustrative until replaced by a driven needle."
}, indent=2) + "\n", encoding="utf-8")
(ROOT/'assets'/'display-layout.json').write_text(json.dumps({
    'schemaVersion': 1, 'uvOrigin': 'bottom-left',
    'source': 'AOH LM7 Volume1 Figure3-2, PDF827',
    'displays': display_layout,
}, indent=2)+'\n', encoding='utf-8')
