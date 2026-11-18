"""Rebuild the provisional LM-7 visual slice in Blender from sourced controls.

Run inside Blender: exec(compile(open(path).read(), path, 'exec')).
Only objects tagged aq_generated in the named scene are replaced. Other scenes
and user objects are preserved. Blender metres: X right, Y forward, Z up.
"""
from pathlib import Path
import json, math, random, io, contextlib, hashlib
import bpy
from mathutils import Vector, Euler

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets'
OUT = ROOT / 'output'
ASSETS.mkdir(exist_ok=True)
OUT.mkdir(exist_ok=True)
scene = bpy.data.scenes.get('Aquarius_Visual_Slice') or bpy.data.scenes.new('Aquarius_Visual_Slice')
for obj in list(scene.objects):
    if obj.get('aq_generated'):
        bpy.data.objects.remove(obj, do_unlink=True)
if bpy.context.window:
    bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
primitive_cache = {}
surface_maps = ROOT / 'tools' / 'cabin-surface-maps.py'
exec(compile(surface_maps.read_text(encoding='utf-8'), str(surface_maps), 'exec'), globals())

def link(obj, parent=None):
    scene.collection.objects.link(obj)
    obj['aq_generated'] = True
    if parent: obj.parent = parent
    return obj

def empty(name, location=(0,0,0), parent=None):
    obj = link(bpy.data.objects.new(name, None), parent)
    obj.location = location
    return obj

def material(name, color, metal=0, rough=.5, emission=0):
    mat = bpy.data.materials.get('AQ_'+name) or bpy.data.materials.new('AQ_'+name)
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = rough
    if emission:
        shader.inputs['Emission Color'].default_value = (*color, 1)
        shader.inputs['Emission Strength'].default_value = emission
    return mat

metal = material('brushed_aluminum', (.44,.46,.47), .66, .49)
dark = material('panel_edges', (.027,.031,.032), .14, .57)
shell = material('pressure_shell', (.30,.32,.29), .09, .74)
insulation = material('insulation', (.108,.127,.122), 0, .92)
ivory = material('ivory_handles', (.59,.57,.49), 0, .55)
rubber = material('rubber', (.015,.019,.019), 0, .83)
blue = material('window_glass', (.009,.021,.035), .4, .18)
amber = material('amber', (.75,.30,.055), .15, .45, .5)
green = material('green', (.1,.65,.3), .1, .5, .3)
red = material('guard_red', (.40,.035,.018), .3, .35)
warm = material('lamp', (1,.65,.27), .1, .3, 4)
diffuser = material('frosted_diffuser', (.54,.50,.42), 0, .62)

detail_tiles = {metal.name: .024, shell.name: .16, insulation.name: .096, rubber.name: .024}
normal_detail(metal, 'brushed metal', 128, 128, 17, .024, brushed=True)
normal_detail(shell, 'shell paint', 256, 256, 19, .050)
normal_detail(insulation, 'equipment covers', 128, 128, 23, .065)
normal_detail(rubber, 'molded rubber', 128, 128, 29, .10)


def projected_uv(data, tile):
    layer = data.uv_layers.new(name='UVMap')
    for face in data.polygons:
        axis = max(range(3), key=lambda i: abs(face.normal[i]))
        u, v = (axis+1) % 3, (axis+2) % 3
        sign = 1 if face.normal[axis] >= 0 else -1
        for loop_index in face.loop_indices:
            point = data.vertices[data.loops[loop_index].vertex_index].co
            layer.data[loop_index].uv = (point[u] / tile, sign * point[v] / tile)

def mesh(name, verts, faces, mat, parent=None, uv=False):
    if mat and mat.name in detail_tiles:
        # Blender's tangent calculation supports triangles and quads.
        faces = [triangle for face in faces for triangle in (
            [face] if len(face) <= 4 else [(face[0], face[i], face[i+1]) for i in range(1, len(face)-1)]
        )]
    data = bpy.data.meshes.new(name+'_mesh')
    data.from_pydata(verts, [], faces)
    data.update()
    if mat: data.materials.append(mat)
    if uv:
        layer = data.uv_layers.new(name='UVMap')
        for loop in data.loops:
            co = data.vertices[loop.vertex_index].co
            layer.data[loop.index].uv = (co.x+.5, co.y+.5)
    elif mat and mat.name in detail_tiles:
        projected_uv(data, detail_tiles[mat.name])
    return link(bpy.data.objects.new(name, data), parent)

def box(name, location, size, mat, parent=None, bevel=0):
    sx,sy,sz = (v/2 for v in size)
    verts = [(x*sx,y*sy,z*sz) for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    obj = mesh(name, verts, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)], mat, parent)
    obj.location = location
    if bevel:
        mod = obj.modifiers.new('soft_machined_edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
    return obj

def cyl(name, location, radius, depth, mat, parent=None, segments=16):
    key=('cylinder',round(radius,7),round(depth,7),mat.name,segments)
    if key in primitive_cache:
        obj=link(bpy.data.objects.new(name,primitive_cache[key]),parent)
        obj.location=location
        return obj
    verts = [(radius*math.cos(i*math.tau/segments),radius*math.sin(i*math.tau/segments),z) for z in [-depth/2,depth/2] for i in range(segments)]
    faces = [tuple(reversed(range(segments))), tuple(range(segments,2*segments))]
    faces += [(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
    obj = mesh(name, verts, faces, mat, parent)
    obj.location = location
    side_faces = obj.data.polygons[-segments:]
    for poly in side_faces: poly.use_smooth = True
    if mat.name in detail_tiles:
        tile = detail_tiles[mat.name]
        repeats = max(1, round(math.tau * radius / tile))
        layer = obj.data.uv_layers.active
        for index, face in enumerate(side_faces):
            for loop_index, (offset, height) in zip(face.loop_indices, [(0, 0), (1, 0), (1, depth), (0, depth)]):
                layer.data[loop_index].uv = ((index + offset) * repeats / segments, height / tile)
    primitive_cache[key]=obj.data
    return obj

def sphere(name, location, radius, mat, segments=64, rings=32):
    verts=[]
    for j in range(rings+1):
        phi=math.pi*j/rings
        for i in range(segments+1):
            theta=math.tau*i/segments
            verts.append((radius*math.sin(phi)*math.cos(theta),radius*math.sin(phi)*math.sin(theta),radius*math.cos(phi)))
    faces=[]
    for j in range(rings):
        for i in range(segments):
            a=j*(segments+1)+i
            faces.append((a,a+segments+1,a+segments+2,a+1))
    obj=mesh(name,verts,faces,mat)
    layer=obj.data.uv_layers.new(name='UVMap')
    for loop in obj.data.loops:
        index=loop.vertex_index
        layer.data[loop.index].uv=(index%(segments+1)/segments,1-index//(segments+1)/rings)
    for poly in obj.data.polygons: poly.use_smooth=True
    obj.location=location
    return obj

def image_material(name, path, rough=.8, emit=0):
    mat=material(name,(1,1,1),0,rough)
    shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    image_node=next((n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'),None) or mat.node_tree.nodes.new('ShaderNodeTexImage')
    image_node.image=bpy.data.images.load(str(path),check_existing=True)
    image_node.image.reload()
    mat.node_tree.links.new(image_node.outputs['Color'],shader.inputs['Base Color'])
    if emit:
        mat.node_tree.links.new(image_node.outputs['Color'],shader.inputs['Emission Color'])
        shader.inputs['Emission Strength'].default_value=emit
    return mat

def rod(name, a, b, radius, mat, parent=None):
    a,b = Vector(a),Vector(b)
    obj = cyl(name, (a+b)/2, radius, (b-a).length, mat, parent)
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = (b-a).to_track_quat('Z','Y')
    return obj

def text(name, value, loc, size, mat, parent=None):
    data = bpy.data.curves.new(name+'_font', 'FONT')
    data.body = value
    data.size = size
    data.align_x = 'CENTER'
    data.extrude = .00015
    data.materials.append(mat)
    obj = link(bpy.data.objects.new(name,data), parent)
    obj.location = loc
    return obj

# This is a dimensioned greybox, not a recovered scan. Panel locations follow
# AOH Figure 1-7; dimensions below remain provisional pending drawing audit.
inventory_path = ROOT/'reference'/'controls.json'
inventory = json.loads(inventory_path.read_text(encoding='utf-8-sig')) if inventory_path.exists() else {'controls':[]}
mechanism_layout_path = ASSETS/'mechanism-layout.json'
mechanism_layout = json.loads(mechanism_layout_path.read_text(encoding='utf-8')) if mechanism_layout_path.exists() else {'controls':{}}
mechanism_presentations = mechanism_layout.get('controls', {})
aft_detail = ROOT/'tools/cabin-aft-detail.py'
exec(compile(aft_detail.read_text(encoding='utf-8'), str(aft_detail), 'exec'), globals())
mechanism_helper = ROOT/'tools/cabin-mechanism-shapes.py'
exec(compile(mechanism_helper.read_text(encoding='utf-8'), str(mechanism_helper), 'exec'), globals())
declared_ids = {c['id'] for c in inventory.get('controls', [])}
PANEL_LAYOUT = {
 '1':(-.225,.98,1.44,.43,.82,80,0), '2':(.225,.98,1.44,.43,.82,80,0),
 '3':(0,.81,.91,.88,.23,45,0), '4':(0,.59,.65,.39,.265,45,0),
 '5':(-.59,.41,.72,.40,.28,50,12), '6':(.60,.47,.71,.36,.285,55,-12),
 '8':(-1.00,.39,1.02,.73,.20,15,58), '12':(1.00,.39,.94,.73,.20,15,-58),
 '11':(-.94,.64,1.55,.67,.55,90,58), '16':(.94,.64,1.57,.67,.47,90,-58),
 '14':(1.00,.48,1.17,.67,.135,36.5,-58),
}
panel_definitions = {str(p['id']): p for p in inventory.get('panels', [])}
for panel_definition in inventory.get('panels',[]):
    pid=str(panel_definition['id'])
    if pid in PANEL_LAYOUT:
        placement=list(PANEL_LAYOUT[pid])
        placement[3]=panel_definition.get('width_m',placement[3])
        placement[4]=panel_definition.get('height_m',placement[4])
        PANEL_LAYOUT[pid]=tuple(placement)
    elif 'placement' in panel_definition:
        p = panel_definition['placement']
        PANEL_LAYOUT[pid] = (p['x'], p['y'], p['z'], panel_definition['width_m'], panel_definition['height_m'], p.get('rotateXDeg', 90), p.get('rotateZDeg', 0))
# Hatch controls sit on the interior face; published side-of-hatch controls are
# retained as explicitly labelled inspection proxies, pending exterior modelling.
for pid in ['HATCH_FWD', 'HATCH_OVHD']:
    if pid in PANEL_LAYOUT:
        p=list(PANEL_LAYOUT[pid]); p[1 if pid=='HATCH_FWD' else 2] = .985 if pid=='HATCH_FWD' else 1.985
        PANEL_LAYOUT[pid]=tuple(p)
for pid in ['ACA_CDR', 'TTCA_CDR', 'ACA_LMP', 'TTCA_LMP']:
    if pid in PANEL_LAYOUT:
        p=list(PANEL_LAYOUT[pid]); p[1] -= .27
        PANEL_LAYOUT[pid]=tuple(p)
panels = {}
for pid,(x,y,z,w,h,rx,rz) in PANEL_LAYOUT.items():
    panel = empty('Panel_'+pid, (x,y,z))
    panel.rotation_euler = (math.radians(rx), 0, math.radians(rz))
    panel['panel_id'] = pid
    panel['dimensions_provisional'] = True
    panels[pid] = panel
    if not panel_definitions.get(pid, {}).get('renderPanel', True) or (pid == 'UTIL' and 'utility_cdr_lamp' in declared_ids):
        continue
    if pid == 'ECS':
        build_ecs_fascia(panel, w, h)
        continue
    box('Panel_'+pid+'_backing', (0,0,-.017), (w+.012,h+.012,.035), dark, panel, .006)
    panel_mat = material('artwork_'+pid, (.18,.18,.17), 0, .77)
    shader = next(n for n in panel_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    image_node = panel_mat.node_tree.nodes.get('Image Texture') or panel_mat.node_tree.nodes.new('ShaderNodeTexImage')
    texture_path = ASSETS/'textures'/('panel-'+pid+'.png')
    if texture_path.exists():
        image_node.image = bpy.data.images.load(str(texture_path), check_existing=True)
        image_node.image.reload()
        panel_mat.node_tree.links.new(image_node.outputs['Color'], shader.inputs['Base Color'])
        panel_backlight(panel_mat, pid, image_node.image)
        if pid in {'1', '2', '3', '4', '11', '16'}:
            normal_detail(panel_mat, 'panel '+pid+' paint', max(160, round(w*1100)), max(120, round(h*1100)), int(pid), .064)
    else:
        text('group_label_'+pid, panel_definitions[pid].get('label',pid).upper(), (0,h*.43,.004), min(.010,w/35), ivory, panel)
    face = mesh('Panel_'+pid+'_artwork', [(-.5,-.5,0),(.5,-.5,0),(.5,.5,0),(-.5,.5,0)], [(0,1,2,3)], panel_mat,panel,uv=True)
    face.scale = (w,h,1)
    face.location.z = .001
    for ix in [-1,1]:
        for iy in [-1,1]:
            bolt = cyl('P'+pid+'_frame_screw', (ix*(w/2-.009),iy*(h/2-.010),.002), .003,.002,metal,panel,12)
            box('screw_slot', (0,0,.0013),(.004,.0006,.0003), dark,bolt)

modeled = []
for control in inventory.get('controls',[]):
    pid = str(control['panel'])
    if pid not in panels: continue
    layout = control.get('layout',{})
    if 'u' not in layout or 'v' not in layout: continue
    _,_,_,w,h,_,_ = PANEL_LAYOUT[pid]
    presentation = mechanism_presentations.get(control['id'])
    if presentation:
        root = empty(control['id'], presentation['positionBlenderM'])
        root.rotation_euler = tuple(math.radians(v) for v in presentation['rotationBlenderDeg'])
        root['geometry_qualification'] = presentation['geometryStatus']
    else:
        root = empty(control['id'], ((layout['u']-.5)*w,(layout['v']-.5)*h,.004),panels[pid])
    root['control_id'] = control['id']
    root['control_type'] = control['type']
    root['label'] = control['label']
    root['source_figure'] = control.get('source',{}).get('figure','3-2')
    actuator = empty(control['id']+'__actuator', (0,0,.006),root)
    kind = control['type'].lower()
    if pid == 'ECS':
        ecs_control_legend(control, root)
    elif not (ASSETS/'textures'/('panel-'+pid+'.png')).exists() and control.get('renderPlacards', True) and not presentation:
        text('control_label_'+control['id'], control['label'], (0,-.025,.006), min(.0065,w*.022), ivory, root)
    if presentation:
        build_mechanism_shape(control, root, actuator, presentation)
        apply_mechanism_default(control, root, actuator, presentation)
    elif kind in ['toggle','lever-lock','lever_lock','switch','guarded','guarded_toggle']:
        cyl('switch_hex_nut',(0,0,.001),.008,.003,metal,root,6)
        cyl('switch_gasket',(0,0,.003),.0047,.004,rubber,root)
        rod('toggle_stem',(0,0,0),(0,0,.020),.0023,metal,actuator)
        cyl('toggle_tip',(0,0,.022),.0038,.010,ivory,actuator,12)
        positions = control.get('positions',[])
        state_index = positions.index(control['default']) if control.get('default') in positions else 0
        actuator.rotation_euler.x = math.radians(-18 + 36*state_index/max(1,len(positions)-1))
        if 'guard' in kind:
            for xx in [-.012,.012]: rod('guard_rail',(xx,-.012,.002),(xx,.016,.025),.002,red,root)
    elif kind in ['circuit_breaker','breaker','circuit-breaker']:
        cyl('breaker_mount',(0,0,.001),.007,.003,metal,root,6)
        cyl('breaker_shaft',(0,0,.004),.004,.010,rubber,actuator,12)
        cyl('breaker_cap',(0,0,.011),.0055,.006,dark,actuator,12)
        box('breaker_white_stripe',(0,0,.0142),(.006,.001,.0003),ivory,actuator)
    elif kind == 'guard':
        # Separate pivot and cover retain independent ID and opening state.
        actuator.location.y = .015
        box('guard_cover',(0,-.010,.010),(.030,.036,.003),red,actuator,.002)
        rod('guard_hinge',(-.018,0,.003),(.018,0,.003),.0025,metal,actuator)
    elif kind == 'valve' and pid == 'ECS':
        ecs_valve_geometry(control['id'], root, actuator)
    elif kind == 'valve':
        cyl('valve_mount',(0,0,.003),.012,.006,metal,root,20)
        cyl('valve_hub',(0,0,.013),.006,.020,ivory,actuator,16)
        for angle in [0,90]:
            a=math.radians(angle)
            rod('valve_handle',(-.018*math.cos(a),-.018*math.sin(a),.025),(.018*math.cos(a),.018*math.sin(a),.025),.0035,ivory,actuator)
    elif kind == 'axis':
        cyl('controller_axis_mount',(0,0,.003),.011,.007,rubber,root,20)
        rod('controller_axis_stick',(0,0,.004),(0,0,.032),.003,metal,actuator)
        cyl('controller_axis_grip',(0,0,.035),.006,.016,ivory,actuator,16)
    elif control['id'].startswith('hatch_') and control['id'].endswith('_door'):
        # The actual structural hatch is attached to this pivot below.
        pass
    elif kind in ['rotary','rotary_switch','knob','thumbwheel']:
        cyl('rotary_base',(0,0,.003),.012,.006,metal,root,24)
        cyl('knob',(0,0,.010),.010,.015,rubber,actuator,16)
        box('knob_pointer',(0,.006,.018),(.002,.012,.002),ivory,actuator,.001)
    elif kind in ['pushbutton','button','key','dsky_key','deda_key']:
        box('button_frame',(0,0,.002),(.022,.021,.007),metal,root,.002)
        box('button_cap',(0,0,.006),(.018,.017,.008),rubber,actuator,.002)
        value=control.get('label','').replace('DSKY ','').replace('DEDA ','')
        if len(value)<=8: text('key_legend',value,(0,-.002,.0105),.0043,ivory,actuator)
    elif kind in ['talkback','indicator','light','annunciator']:
        # Keep the source face and its legible placard visible. A slim backing
        # gives the aperture relief without inventing an illuminated state.
        for xx in [-.011,.011]:
            box('indicator_bezel',(xx,0,.002),(.001,.012,.003),metal,root)
    elif kind in ['meter','gauge','display','tape','fdai','digital_display']:
        # Artwork carries the static face. The ID still exists for coverage and
        # future driven instrumentation; it is not reported as operable.
        pass
    elif kind == 'joystick':
        cyl('slew_base',(0,0,.002),.008,.004,rubber,root)
        rod('slew_stick',(0,0,0),(0,0,.022),.002,metal,actuator)
        cyl('slew_grip',(0,0,.024),.003,.006,ivory,actuator)
    else:
        cyl('control_base',(0,0,.003),.008,.006,metal,root,12)
        cyl('control_knob',(0,0,.011),.006,.014,rubber,actuator,12)
    modeled.append(control['id'])

# Physical child controls follow their parent article. Their exported default
# world poses are preserved; names/IDs and individual actuators remain intact.
bpy.context.view_layer.update()
for cid, presentation in mechanism_presentations.items():
    parent_id = presentation.get('parentAssemblyId')
    child = bpy.data.objects.get(cid) if cid in declared_ids else None
    parent = bpy.data.objects.get(parent_id+'__actuator') if parent_id in declared_ids else None
    if child and parent:
        world_pose = child.matrix_world.copy()
        child.parent = parent
        child.matrix_world = world_pose

# Faceted pressure shell with a detailed aft midsection.
crew_diameter = 92 * .0254
flight_station_spacing = 44 * .0254
box('Floor',(0,-.10,-.045),(crew_diameter,2.5,.09),shell)
# Source deck area is approximately 36 by 55 inches (AOH PDF22, printed1-6).
box('Crew_station_deck',(0,.30,.003),(55*.0254,36*.0254,.006),dark)
for xx in [-.99,-.72,-.45,-.18,.18,.45,.72,.99]:
    box('floor_nonskid',(xx,-.2,.004),(.105,2.2,.009),rubber)
for xx in [-1.18,1.18]:
    box('lower_sidewall',(xx,-.02,.57),(.07,2.28,1.14),shell)
    box('upper_sidewall',(xx,-.02,1.60),(.07,2.28,1.03),insulation)
    for yy in [-.94,-.48,-.03,.43,.90]:
        box('sidewall_rib',(xx*.977,yy,1.03),(.036,.026,1.83),metal)
    for zz in [.18,.62,1.03,1.97]:
        rod('side_rail',(xx*.976,-1.1,zz),(xx*.976,1.03,zz),.016,metal)
    # Recessed equipment covers, visible seams and captive fasteners. These are
    # geometric surface detail; dimensions remain provisional.
    for yy in [-.78,-.30,.18]:
        for zz in [1.31,1.72]:
            plate=box('equipment_cover',(xx*.976,yy,zz),(.018,.42,.34),insulation,bevel=.009)
            for dy in [-.18,.18]:
                for dz in [-.14,.14]:
                    screw=cyl('captive_fastener',(xx*.963,yy+dy,zz+dz),.0035,.004,metal,segments=12)
                    screw.rotation_euler.y=math.pi/2
box('Roof',(0,-.1,2.135),(2.36,2.45,.10),shell)
for yy in [-.95,-.40,.12,.65,1.05]:
    rod('roof_crossmember',(-1.13,yy,2.07),(1.13,yy,2.07),.021,metal)
box('Forward_lower_wall',(0,1.12,.55),(2.3,.07,1.1),shell)
box('Forward_top_rail',(0,1.07,2.02),(2.30,.10,.15),shell)
box('Instrument_support_wall',(0,1.105,1.57),(.91,.045,.91),insulation)
build_aft_midsection()

# Give each forward breaker bank a visible connection to the side structure.
for panel_id, side in [('11', -1), ('16', 1)]:
    bank = panels[panel_id]
    _, _, z, _, height, _, _ = PANEL_LAYOUT[panel_id]
    for offset in [-.35, .35]:
        anchor = bank.location + bank.rotation_euler.to_matrix() @ Vector((side * .19, height * offset, -.035))
        rod('breaker_bank_support', anchor, (side*1.13, anchor.y-.07, z+height*offset), .012, metal)
        box('breaker_bank_mount', (side*1.132, anchor.y-.07, z+height*offset), (.025,.069,.058), dark, bevel=.005)

# Triangular forward windows, structural gaskets and crash bars.
for side in [-1,1]:
    vertices = [(side*.48,1.075,1.91),(side*1.11,1.075,1.67),(side*.49,1.075,1.13)]
    # Clear aperture. Surrounding wall masks the exterior to the window shape.
    empty('Forward_window_'+str(side))
    for polygon in [
        [(.45,1.97),(1.17,1.97),(1.17,1.67),(1.11,1.67),(.48,1.91)],
        [(.45,1.97),(.48,1.91),(.49,1.13),(.45,1.08)],
        [(.45,1.08),(.49,1.13),(1.11,1.67),(1.17,1.67),(1.17,1.08)],
    ]:
        mesh('Forward_window_surround',[(side*x,1.102,z) for x,z in polygon],[tuple(range(len(polygon)))],shell)
    for i in range(3):
        a,b=vertices[i],vertices[(i+1)%3]
        rod('window_gasket',a,b,.026,rubber)
        a2=(a[0],a[1]-.019,a[2]); b2=(b[0],b[1]-.019,b[2])
        rod('window_frame',a2,b2,.012,metal)
        # Captive hardware breaks up the frame's continuous metal highlight.
        for t in [.16, .47, .78]:
            point = Vector(a2).lerp(Vector(b2), t)
            point.y -= .011
            screw = cyl('window_frame_fastener', point, .0045, .003, metal, segments=12)
            screw.rotation_euler.x = math.pi/2
    rod('window_crash_bar',(side*.47,.94,1.13),(side*1.09,.94,1.65),.020,metal)
    # Fine reticle strokes follow the documented window's LPD appearance.
    if side==-1:
        for i in range(8):
            zz=1.72-i*.047
            xx=-.68+i*.013
            rod('LPD_reticle',(xx-.012,1.069,zz),(xx+.012,1.069,zz),.0007,ivory)

# Forward hatch and latching hardware.
hatch=box('Forward_hatch',(0,1.058,.43),(32*.0254,.065,32*.0254),ivory,bevel=.06)
box('hatch_inner_plate',(0,1.018,.43),(.68,.025,.58),shell,bevel=.045)
for xx in [-.13,.13]:
    box('hatch_vertical_rib',(xx,.998,.43),(.018,.018,.56),ivory,bevel=.004)
for zz in [.24,.44,.63]:
    box('hatch_horizontal_rib',(0,.998,zz),(.65,.018,.015),ivory,bevel=.004)
for xx in [-.3,.3]:
    for zz in [.16,.70]:
        obj=cyl('hatch_fastener',(xx,.995,zz),.017,.012,metal)
        obj.rotation_euler.x=math.pi/2
rod('hatch_latch_handle',(-.19,.955,.42),(-.31,.955,.54),.014,ivory)
rod('hatch_latch_handle',(-.19,.955,.42),(-.31,.955,.31),.014,ivory)
obj=cyl('hatch_dump_valve',(.23,.98,.58),.049,.028,dark,segments=32)
obj.rotation_euler.x=math.pi/2
rod('dump_valve_handle',(.205,.953,.55),(.255,.953,.62),.007,metal)
if 'hatch_forward_antibacterial_filter' not in declared_ids:
    obj=cyl('hatch_bacterial_filter',(0,.98,.44),.057,.025,metal,segments=32)
    obj.rotation_euler.x=math.pi/2
    for i in range(-4,5):
        extent=math.sqrt(max(0,.043**2-(i*.009)**2))
        rod('filter_mesh',(-extent,.962,.44+i*.009),(extent,.962,.44+i*.009),.001,rubber)
        rod('filter_mesh',(i*.009,.962,.44-extent),(i*.009,.962,.44+extent),.001,rubber)
for zz in [.19,.68]:
    box('hatch_quick_release_hinge',(.4,.99,zz),(.07,.05,.035),metal,bevel=.005)

# Controller shelf structure; audited axes are generated from the inventory.
for side in [-1,1]:
    box('controller_mount',(side*flight_station_spacing/2,.48,.74),(.14,.18,.07),metal,bevel=.014)
    for i in range(6):
        ring=cyl('controller_bellows',(side*.40,.48,.79+i*.009),.045-i*.003,.010,rubber,segments=24)
    rod('attitude_controller',(side*.40,.48,.84),(side*.40,.47,1.02),.022,ivory)
    box('controller_grip',(side*.40,.465,1.015),(.042,.055,.075),ivory,bevel=.016)
    rod('crew_restraint',(side*.9,-.1,.2),(side*.75,.28,.76),.013,rubber)

# Alignment optical telescope, central support and overhead utility light bars.
rod('AOT_column',(0,1.01,1.73),(0,.88,2.05),.042,dark)
obj=cyl('AOT_eyepiece',(0,.80,1.84),.062,.14,metal,segments=32)
obj.rotation_euler.x=math.pi/2
obj=cyl('AOT_lens',(0,.723,1.84),.043,.008,rubber,segments=32)
obj.rotation_euler.x=math.pi/2
for side in [-1,1]:
    box('Forward_flood_housing', (side*.47,.36,2.064), (.18,.071,.035), dark, bevel=.007)
    box('Forward_flood_diffuser_' + ('CDR' if side < 0 else 'LMP'), (side*.47,.36,2.043), (.154,.050,.012), diffuser, bevel=.006)
    if 'flood_overhead_cdr_aim' not in declared_ids:
        rod('utility_light',(side*.15,.78,2.02),(side*.40,.78,2.02),.019,metal)
        rod('utility_diffuser',(side*.16,.758,2.012),(side*.39,.758,2.012),.008,warm)
    # Routed cable loom and several clamps along each station side.
    path=[(side*1.10,-.9,.87),(side*1.10,-.48,.88),(side*1.08,-.16,1.0),(side*1.08,.17,1.05)]
    for offset in [-.010,0,.010]:
        for a,b in zip(path,path[1:]):
            rod('cable_loom',(a[0],a[1],a[2]+offset),(b[0],b[1],b[2]+offset),.005,rubber)
    for yy in [-.77,-.54,-.22]:
        box('cable_clamp',(side*1.085,yy,.89),(.025,.018,.057),metal,bevel=.003)

# Overhead docking window and roof hatch; detailed control mechanisms remain
# outside the audited inventory. Shape references: AOH Figures1-8/1-10.
box('Docking_window_frame',(-.68,.45,2.065),(.40,.31,.035),metal,bevel=.045)
box('Docking_window',(-.68,.45,2.043),(.34,.25,.008),blue,bevel=.025)
rod('docking_reticle',(-.79,.45,2.037),(-.57,.45,2.037),.0008,ivory)
rod('docking_reticle',(-.68,.37,2.037),(-.68,.53,2.037),.0008,ivory)
obj=cyl('Docking_hatch',(0,-.45,2.055),.36,.035,metal,segments=64)
obj=cyl('Docking_hatch_inner',(0,-.45,2.028),.31,.014,shell,segments=64)
rod('docking_hatch_handle',(-.1,-.45,2.008),(.1,-.45,2.008),.014,ivory)
for angle in range(0,360,60):
    a=math.radians(angle)
    cyl('roof_hatch_bolt',(.335*math.cos(a),-.45+.335*math.sin(a),2.025),.006,.006,dark,segments=12)

# Operable structural hatches share the inventory's separate latch/door states.
# Preserve mesh world poses while placing the actuator pivot at the hinge.
bpy.context.view_layer.update()
for which, prefixes, hinge_offset in [
    ('forward', ['Forward_hatch','hatch_inner_plate','hatch_vertical_rib','hatch_horizontal_rib','hatch_fastener','hatch_latch_handle','hatch_dump_valve','dump_valve_handle','hatch_bacterial_filter','filter_mesh'], 32*.0254/2),
    ('overhead', ['Docking_hatch','Docking_hatch_inner','docking_hatch_handle','roof_hatch_bolt'], .36),
]:
    pivot = bpy.data.objects.get('hatch_'+which+'_door__actuator')
    if pivot:
        pivot.location.x = hinge_offset
        bpy.context.view_layer.update()
        for obj in list(scene.objects):
            if obj.type == 'MESH' and any(obj.name == prefix or obj.name.startswith(prefix+'.') for prefix in prefixes):
                world_pose = obj.matrix_world.copy()
                obj.parent = pivot
                obj.matrix_world = world_pose

# Source identifies the ACA mount on folding armrests. The existing large
# controller bodies now follow those rests; independent axis inspection
# targets remain an explicitly documented geometry simplification.
bpy.context.view_layer.update()
for obj in list(scene.objects):
    if obj.type != 'MESH' or not any(obj.name == prefix or obj.name.startswith(prefix+'.') for prefix in ['controller_bellows', 'attitude_controller', 'controller_grip']):
        continue
    arm_id = 'armrest_cdr_right' if obj.matrix_world.translation.x < 0 else 'armrest_lmp_left'
    if arm_id in declared_ids:
        parent = bpy.data.objects.get(arm_id+'__actuator')
        if parent:
            world_pose = obj.matrix_world.copy()
            obj.parent = parent
            obj.matrix_world = world_pose

earth_path=ASSETS/'textures'/'earth.jpg'
if earth_path.exists():
    earth_mat=image_material('Earth_NASA',earth_path,1,.30)
    earth=sphere('Earth_preview',(7.4,24,2.25),.52,earth_mat,96,48)
    earth.rotation_euler.z=math.radians(105)
    earth['preview_only']=True
    earth['limitation']='Illustrative direction and apparent size; no trajectory/attitude connection yet.'

def area(name, location, target, energy, color, size):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=energy; data.color=color; data.shape='DISK'; data.size=size
    obj=link(bpy.data.objects.new(name,data))
    obj.location=location
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
    return obj

area('Cabin_soft_fill',(0,-.9,1.9),(0,.85,1.1),65,(.73,.83,1),1.7)
area('Overhead_warm_left',(-.45,.40,1.99),(-.4,.8,.9),24,(1,.73,.43),.65)
area('Overhead_warm_right',(.45,.40,1.99),(.4,.8,.9),20,(1,.73,.43),.65)
area('Window_cold_rim',(.8,.92,1.8),(-.4,-.4,.65),48,(.56,.73,1),.45)
world=bpy.data.worlds.get('Aquarius_space') or bpy.data.worlds.new('Aquarius_space')
world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
bg.inputs['Color'].default_value=(.016,.023,.032,1)
bg.inputs['Strength'].default_value=.25
stars_path=ASSETS/'textures'/'stars.png'
if stars_path.exists():
    sky_node=next((n for n in world.node_tree.nodes if n.type=='TEX_ENVIRONMENT'),None) or world.node_tree.nodes.new('ShaderNodeTexEnvironment')
    sky_node.image=bpy.data.images.load(str(stars_path),check_existing=True)
    world.node_tree.links.new(sky_node.outputs['Color'],bg.inputs['Color'])
scene.world=world

def camera(name, loc, target, lens):
    data=bpy.data.cameras.new(name)
    data.lens=lens; data.clip_start=.015
    obj=link(bpy.data.objects.new(name,data))
    obj.location=loc
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
    return obj
hero=camera('Aquarius_Interior',(0,-1.60,1.60),(0,.78,1.18),20)
detail=camera('Aquarius_Panels',(-.27,-.10,1.49),(0,.98,1.34),24)
scene.camera=hero
scene.render.resolution_x=1600
scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(OUT/'aquarius-cabin.png')
scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'

for screen in bpy.data.screens:
    for space_area in screen.areas:
        if space_area.type=='VIEW_3D':
            space_area.spaces.active.region_3d.view_perspective='CAMERA'

# Selection-only export prevents the user's other scenes from entering the asset.
for obj in bpy.context.selected_objects: obj.select_set(False)
export_objects=[o for o in scene.objects if o.type not in {'CAMERA','LIGHT'}]
for obj in export_objects: obj.select_set(True)
with contextlib.redirect_stdout(io.StringIO()):
    bpy.ops.export_scene.gltf(filepath=str(ASSETS/'aquarius-cabin.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_extras=True,export_cameras=False,export_lights=False,export_tangents=True,export_apply=True)
for obj in export_objects: obj.select_set(False)
for obj in export_objects:
    if obj.get('aq_hide_in_blender_at_rest'):
        for hidden in [obj, *obj.children_recursive]:
            hidden.hide_set(True)
            hidden.hide_render = True
scene['inventory_count']=len(inventory.get('controls',[]))
scene['modeled_controls']=len(modeled)
scene['limitations']='Source-corrected panel cant and hatch/deck dimensions; other placement provisional; optical and fluid systems not coupled.'
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ASSETS/'aquarius-cabin.blend'))
(ASSETS/'cabin-build.json').write_text(json.dumps({
 'generator':'tools/build-cabin.py', 'geometryStatus':'provisional',
 'inventorySha256':hashlib.sha256(inventory_path.read_bytes()).hexdigest() if inventory_path.exists() else None,
 'mechanismLayoutSha256':hashlib.sha256(mechanism_layout_path.read_bytes()).hexdigest() if mechanism_layout_path.exists() else None,
 'sources':['AOH LM7 Vol1 Fig1-7 PDF25 printed1-9','AOH LM7 Vol1 Fig1-8 PDF26 printed1-10','AOH LM7 Vol1 Fig1-9/1-10 PDF27 printed1-11','AOH LM7 Vol1 Fig3-2 PDF827 printed3-157/3-158'],
 'controlCount':len(inventory.get('controls',[])), 'modeledControlIds':modeled,
 'unmodeledControlIds':sorted(set(c['id'] for c in inventory.get('controls',[]))-set(modeled)),
 'panels':{k:{'position':list(v[:3]),'width':v[3],'height':v[4],'rotationDegrees':[v[5],0,v[6]],'dimensionsProvisional':True} for k,v in PANEL_LAYOUT.items()},
 'geometryCalibration':{'source':'AOH LM7 Vol1 PDF22 printed1-6 and PDF24 printed1-8','crewCompartmentDiameterM':crew_diameter,'crewCompartmentDepthM':42*.0254,'flightStationCenterlineSpacingM':flight_station_spacing,'deckDimensionsM':[36*.0254,55*.0254],'forwardHatchSideM':32*.0254,'panelTiltDegreesFromHorizontal':{'1':80,'2':80,'3':45,'4':45,'8':15,'12':15,'14':36.5}},
 'aftPresentation':{'handbookFigures':['2.11-15 (PDF 663)', '3-1 (PDF 825)'],'missionSource':'AS-508 CM-109/LM-7 Final Release Stowage List, 21 April 1970','geometryStatus':'Provisional recreation of the arrangement and soft goods'},
 'limitations':['Panel sizes and most cabin placements remain approximate','Breaker row surface cant and controller grip cross-axis geometry need further modelling','Analog instrument artwork illustrative until driven','Earth preview not trajectory/attitude driven','Headset reach and frame rate require physical evidence']
},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'scene':scene.name,'objects':len(scene.objects),'controls':len(modeled),'blend':str(ASSETS/'aquarius-cabin.blend'),'glb':str(ASSETS/'aquarius-cabin.glb')}))
