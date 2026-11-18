"""Build the presentation-only placement/motion plan for cabin mechanisms.

Source states live in reference/controls.json. These coordinates, rotations,
and intermediate poses are explicitly provisional visual proxies, never
engineering measurements or as-flown configurations.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
controls = {}

def add(cid, position, rotation=(0, 0, 0), motion=None, parent=None, shape=None):
    controls[cid] = dict(positionBlenderM=list(position), rotationBlenderDeg=list(rotation),
                         geometryStatus='provisional presentation proxy', renderPlacards=False)
    if motion: controls[cid]['motion'] = dict(motion, proxy=True)
    if parent: controls[cid]['parentAssemblyId'] = parent
    if shape: controls[cid]['shape'] = shape

def rotate(axis, values): return dict(kind='rotate', axis=axis, values=values)
def translate(axis, values): return dict(kind='translate', axis=axis, values=values)
def scale(axis, values): return dict(kind='scale', axis=axis, values=values)
def poses(positions, rotations=None):
    result = dict(kind='poses', worldPositionsBlenderM=positions)
    if rotations: result['worldRotationsBlenderDeg'] = rotations
    return result

for who, side in [('cdr', -1), ('lmp', 1)]:
    add('shade_'+who, (side*.49, .985, 1.13), (90, 0, 0), scale('y', [.025, 1]), shape='forward_shade')
add('shade_docking', (-.68, .575, 2.015), (180, 0, 0), scale('y', [.025, 1]), shape='docking_shade')

for who, center in [('cdr', -.5588), ('lmp', .5588)]:
    for hand, offset in [('left', -.16), ('right', .16)]:
        add('armrest_'+who+'_'+hand, (center+offset, .05, .84), motion=rotate('x', [90, 30, 0, -30, -60, -90]), shape='armrest')
    add('restraint_'+who+'_reel_lock', (center, .45, .58), (90, 0, 0), rotate('z', [0, 50]), shape='reel')
add('restraint_cdr_docking_pin', (-.60, .05, .62), (90, 0, 0), translate('z', [0, .035]), shape='pin')

coas_left = [-.58, .975, 1.53]
coas_free = [-.46, .15, 1.34]
coas_overhead = [-.68, .45, 1.965]
add('coas_mount', coas_left, (90, 0, 0),
    poses([coas_left, coas_free, coas_overhead], [[90, 0, 0], [90, 0, 0], [180, 0, 0]]), shape='coas')
add('coas_illumination', (-.534, .85, 1.53), (90, 0, 0), rotate('z', [0, 80, 160]), 'coas_mount', 'knob')
add('coas_barrel_lock', (-.532, .94, 1.58), (90, 0, 0), rotate('z', [0, 70]), 'coas_mount', 'lock')
# Park the removed cap beside the eyepiece so its aperture is clear.
add('coas_cap', (-.58, .779, 1.53), (90, 0, 0), translate('x', [0, .079]), 'coas_mount', 'cap')
add('coas_filter', (-.58, .775, 1.572), (90, 0, 0), translate('x', [0, -.09]), 'coas_mount', 'filter')

for who, side in [('cdr', -1), ('lmp', 1)]:
    stowed = [side*.23, .40, .52]
    free = [side*.70, -.02, 1.12]
    clamped = [side*.99, .38, 1.45]
    add('utility_'+who+'_lamp', stowed, (90, 0, 0), poses([stowed, free, clamped]), shape='portable_lamp')
    add('utility_'+who+'_clamp', (stowed[0]+side*.045, stowed[1], stowed[2]-.035),
        (90, 0, 0), rotate('z', [0, 65]), 'utility_'+who+'_lamp', 'clamp')
    add('utility_'+who+'_plug', (side*.47, .53, 1.96), (180, 0, 0), translate('z', [.025, 0]), shape='connector')
    add('flood_overhead_'+who+'_aim', (side*.27, .77, 2.005), (180, 0, 0), rotate('x', [-30, 0, 30]), shape='reflector')
    add('umbilical_'+who+'_ptt', (side*.83, -.18, .94), (90, 0, side*-20), shape='ptt')

dispenser_bracket = [.19, -.94, .97]
dispenser_free = [.08, -.35, 1.10]
add('water_dispenser_pose', dispenser_bracket, (-90, 0, 0), poses([dispenser_bracket, dispenser_free]), shape='dispenser')
# Nozzle ends at local Z=.120 plus the common .006 actuator stand-off.
# Child controls have their own .006 stand-off, so place the cap root at .120.
# Park a removed cap sideways, leaving a clear water path along the nozzle axis.
controls['water_dispenser_pose']['targetLocalBlenderM'] = [0, 0, .055]
controls['water_dispenser_pose']['targetNormalLocalBlenderM'] = [1, 0, 0]
add('water_dispenser_trigger', (.225, -.875, .97), (-90, 0, 0), parent='water_dispenser_pose', shape='trigger')
add('water_dispenser_cap', (.19, -.820, .97), (-90, 0, 0), translate('x', [0, -.065]), 'water_dispenser_pose', 'cap')
add('tool_b_head_lock', (.98, -.61, .62), (90, 0, -55), translate('z', [0, .015]), shape='tool_b')
add('drogue_retention', (.27, -.44, 1.96), (180, 0, 0), rotate('z', [0, 65]), shape='assembly_retention')
add('drogue_pose', (0, -.45, 1.97), (180, 0, 0),
    poses([[0, -.45, 1.97], [0, -.10, 1.34], [-.93, -.66, .60]]), shape='drogue')
add('hatch_forward_hinge_pin_set', (.437, .98, .55), (90, 0, 0), translate('z', [0, .045]), shape='pin_set')
add('hatch_forward_antibacterial_filter', (.30, .37, .35), (90, 0, 0),
    poses([[.30, .37, .35], [.23, .935, .58]]), shape='antibacterial_filter')
# Both rolls start beneath the LHSSC. Rigged spacing is a presentation pose.
for who, stowed, rigged, facing in [
    ('cdr', [-.68,-.81,.25], [-.24,-.10,1.38], 0),
    ('lmp', [-.68,-.80,.385], [0,-.36,.86], 90),
]:
    add('hammock_'+who, stowed, motion=poses([stowed, rigged], [[0,0,0], [0,0,facing]]), shape='hammock')
    # Approach the stacked rolls from the cabin, rather than through the roll above.
    controls['hammock_'+who]['targetNormalLocalBlenderM'] = [0, 1, 0]

assert len(controls) == 35
# The two already-inventoried selectors belong on the portable lamps. Their
# IDs and source states stay unchanged when the physical assemblies move.
for who, side in [('cdr', -1), ('lmp', 1)]:
    add('util_'+who, (side*.274, .34, .52), (90, 0, 0),
        rotate('z', [0, 80, 160]), 'utility_'+who+'_lamp', 'knob')
output = ROOT/'assets/mechanism-layout.json'
output.write_text(json.dumps(dict(schemaVersion=1, frame='Blender X right, Y forward, Z up; metres',
    qualification='All placements and motion angles are provisional display proxies. Sourced mechanism states and exact numeric anchors are separate inventory evidence.',
    opticalTransmissionNote='Deployed shades use a nearly opaque material; no calibrated optical/lighting transport is claimed.',
    controls=controls), indent=2)+'\n', encoding='utf-8')
print(f'Wrote 35 mechanism layouts and2 existing selector placements to {output}')
