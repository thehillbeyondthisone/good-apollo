"""Aft midsection and soft stowage for the procedural LM-7 scene.

Arrangement follows AOH figs. 2.11-15 and 3-1. Shapes, finishes and
mounting coordinates are reconstructions within the existing cabin envelope.
"""

canvas = material('woven_equipment_canvas', (.51, .48, .36), 0, .91)
duck = material('woven_light_fabric', (.68, .65, .51), 0, .88)
webbing = material('restraint_webbing', (.165, .153, .107), 0, .94)
thread = material('stowage_thread', (.46, .42, .31), 0, .91)
hose_jacket = material('umbilical_jacket', (.25, .28, .30), 0, .67)
hose_braid = material('umbilical_light_jacket', (.38, .39, .34), 0, .8)
hose_cuff = material('umbilical_cuff', (.12, .19, .22), .13, .54)
anodized = material('aft_anodized_fittings', (.20, .23, .22), .47, .53)
avionics = material('aft_electronics', (.17, .205, .205), .19, .68)
paper = material('onboard_data_paper', (.78, .73, .56), 0, .91)
book_cover = material('onboard_data_cover', (.19, .225, .18), 0, .82)
liner = material('aft_thermal_liner', (.43, .44, .39), 0, .84)
ecs_fascia = material('ecs_gray_green_enamel', (.19, .236, .226), 0, .73)
ecs_oxygen = material('ecs_oxygen_enamel', (.243, .254, .213), 0, .77)
ecs_ink = material('ecs_engraving_fill', (.83, .83, .72), 0, .86)
stitch = material('stowage_topstitch', (.66, .57, .39), 0, .93)
foil = material('food_laminate', (.47, .49, .47), .31, .48)

for fabric in [canvas, duck, webbing]:
    detail_tiles[fabric.name] = .026
    weave_normal(fabric)
detail_tiles[liner.name] = .17
normal_detail(liner, 'aft liner paint', 192, 192, 37, .051)
for seed, enamel in [(38, ecs_fascia), (42, ecs_oxygen)]:
    detail_tiles[enamel.name] = .097
    normal_detail(enamel, enamel.name[3:], 192, 192, seed, .052)


def tube_path(name, points, radius, mat, parent, sides=10, rib_pitch=0):
    points = [Vector(point) for point in points]
    vertices, faces = [], []
    distance = 0.0
    normal = None
    for index, point in enumerate(points):
        if index:
            distance += (point - points[index-1]).length
        tangent = (points[min(index+1, len(points)-1)] - points[max(index-1, 0)]).normalized()
        # Carry the cross-section around the bend without rotating it abruptly.
        if normal is None:
            axis = Vector((0, 1, 0)) if abs(tangent.y) < .93 else Vector((1, 0, 0))
            normal = tangent.cross(axis)
        u = (normal - tangent * normal.dot(tangent)).normalized()
        normal = u
        v = tangent.cross(u)
        ring_radius = radius if not rib_pitch else radius * (1 + .11 * math.cos(math.tau * distance / rib_pitch))
        for segment in range(sides):
            angle = math.tau * segment / sides
            vertices.append(point + ring_radius * (u * math.cos(angle) + v * math.sin(angle)))
            if index:
                first = (index-1) * sides
                nxt = (segment+1) % sides
                faces.append((first+segment, first+nxt, first+nxt+sides, first+segment+sides))
    obj = mesh(name, vertices, faces, mat, parent)
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


def hose_curve(name, points, radius, mat, parent, rib_pitch=0):
    points = [Vector(point) for point in points]
    curve = []
    for index, (a, b) in enumerate(zip(points, points[1:])):
        tangent_a = (b - points[max(0, index-1)]) / 2
        tangent_b = (points[min(len(points)-1, index+2)] - a) / 2
        for step in range(30):
            t = step / 30
            curve.append((2*t**3 - 3*t*t + 1)*a + (t**3 - 2*t*t + t)*tangent_a
                         + (-2*t**3 + 3*t*t)*b + (t**3 - t*t)*tangent_b)
    return tube_path(name, curve + [points[-1]], radius, mat, parent, rib_pitch=rib_pitch)


def fabric_strip(name, points, width, across, mat, parent):
    across = Vector(across).normalized() * width/2
    vertices = [Vector(point) + across * side for point in points for side in [-1, 1]]
    faces = [(i, i+1, i+3, i+2) for i in range(0, len(vertices)-2, 2)]
    return mesh(name, vertices, faces, mat, parent)


def sewn_perimeter(name, outline, parent):
    points = [Vector(point) for point in outline]
    verts = []
    for a, b in zip(points, points[1:] + points[:1]):
        for start in [.15, .57]:
            first = a.lerp(b, start)
            end = a.lerp(b, start+.20)
            radial = Vector((first.x, 0, first.z)).normalized()
            offset = radial*.0021 + Vector((0,.0014,0))
            for point in (first, end):
                verts.extend([point + offset - radial*.00055, point + offset + radial*.00055])
    faces = [(i, i+1, i+3, i+2) for i in range(0, len(verts), 4)]
    mesh(name, verts, faces, stitch, parent)


def cloth_pack(name, location, size, mat, parent, straps=(), facing=0, handle=False):
    """A filled soft bag with a sewn perimeter and captive release hardware."""
    pack = empty(name, location, parent)
    pack.rotation_euler.z = facing
    width, depth, height = size
    count = 32
    rings = [(-.50, .77), (-.47, .93), (-.35, .99), (0, 1.0), (.33, 1.01), (.46, .91), (.50, .72)]
    points = []
    for y, fullness in rings:
        for index in range(count):
            angle = math.tau * index / count
            c, s = math.cos(angle), math.sin(angle)
            tension = fullness * (1 + .023 * math.sin(3*angle + y*7) + .014 * math.cos(7*angle - y*4))
            points.append((math.copysign(abs(c)**.42, c) * width/2 * tension, y*depth,
                           math.copysign(abs(s)**.42, s) * height/2 * tension))
    faces = []
    for ring in range(len(rings)-1):
        for index in range(count):
            i, j = ring*count + index, ring*count + (index+1) % count
            faces.append((i, i+count, j+count, j))
    for ring, depth_sign in [(0, -1), (len(rings)-1, 1)]:
        center = len(points)
        points.append((0, depth_sign * depth * .507, 0))
        for index in range(count):
            a, b = ring*count + index, ring*count + (index+1) % count
            faces.append((center, a, b) if depth_sign < 0 else (center, b, a))
    bag = mesh(name+'_fabric', points, faces, mat, pack)
    for face in bag.data.polygons:
        face.use_smooth = True
    # Follow the curved panels with the weave. The front and back use flat UVs.
    outline = [Vector(point) for point in points[3*count:4*count]]
    length = [0.0]
    for index, point in enumerate(outline):
        length.append(length[-1] + (point - outline[(index+1) % count]).length)
    tile = detail_tiles[mat.name]
    wraps = max(1, round(length[-1] / tile))
    uv = bag.data.uv_layers.active.data
    for face in bag.data.polygons[:(len(rings)-1)*count]:
        ring, column = divmod(face.index, count)
        for loop, (u, v) in zip(face.loop_indices, [(column,ring), (column,ring+1), (column+1,ring+1), (column+1,ring)]):
            uv[loop].uv = (wraps * length[u] / length[-1], rings[v][0] * depth / tile)
    seam = points[4*count:5*count]
    tube_path(name+'_corded_seam', seam + [seam[0]], .0022, thread, pack, sides=6)
    sewn_perimeter(name+'_stitching', seam, pack)
    for x_fraction in straps:
        x = width * x_fraction
        wrap = [(x + z*.007, depth*y, height*z) for y,z in [(.2,-.49),(.39,-.461),(.51,-.36),
                  (.54,-.12),(.549,.18),(.52,.36),(.39,.461),(.2,.49)]]
        fabric_strip('pack_wrapped_webbing', wrap, .025, (1,0,0), webbing, pack)
        buckle_y, buckle_z = depth*.554, height*.19
        box('pack_buckle', (x,buckle_y,buckle_z), (.037,.013,.024), anodized,pack,.004)
        box('pack_buckle_slot', (x,buckle_y+.0069,buckle_z), (.023,.003,.012),dark,pack,.002)
        box('pack_buckle_keeper', (x,buckle_y+.009,buckle_z+.001), (.027,.004,.0037),metal,pack,.001)
        fabric_strip('pack_webbing_tail', [(x+.005,depth*.566,buckle_z-.015), (x+.008,depth*.575,buckle_z-.029),
                     (x+.012,depth*.551,buckle_z-.061)],.019,(1,0,0),webbing,pack)
    if handle:
        span = min(.13, width*.48)
        grip = [(span*x, depth*.515+y, height*.245+z) for x,y,z in [(-.5,0,0),(-.40,.019,.016),
                (-.24,.033,.024),(.24,.033,.024),(.40,.019,.016),(.5,0,0)]]
        fabric_strip('pack_grab_loop',grip,.021,(0,0,1),webbing,pack)
        for x in [-span/2, span/2]:
            box('pack_handle_reinforcement',(x,depth*.516,height*.245),(.031,.007,.034),canvas,pack,.003)
    return pack


def wall_text(name, value, position, size, ink, parent):
    label = text(name, value, position, size, ink, parent)
    label.rotation_euler = (math.pi/2, 0, math.pi)
    return label


def ecs_legend(name, value, position, size, panel):
    legend = text(name, value, position, size, ecs_ink, panel)
    # Both in-plane axes of the aft-facing assembly are reversed from the reader's view.
    legend.rotation_euler.z = math.pi
    legend.data.extrude = .000035
    legend.data.space_line = .87
    return legend


def build_ecs_fascia(panel, width, height):
    box('Panel_ECS_backing', (0,0,-.017), (width+.012,height+.012,.035), dark, panel, .006)
    sections = [
        ('CANISTERS', (-.478,-.124,-.486,-.170), ecs_fascia),
        ('SUIT CONDITIONING', (-.108,.478,-.486,-.265), ecs_fascia),
        ('WATER / SUIT CIRCUIT', (-.478,.478,-.156,.151), ecs_fascia),
        ('OXYGEN CONTROL', (-.478,.478,.167,.488), ecs_oxygen),
    ]
    for title, bounds, enamel in sections:
        left, right, top, bottom = bounds
        cx, cy = (left+right)*width/2, (top+bottom)*height/2
        w, h = (right-left)*width, (bottom-top)*height
        box('ECS_face_module', (cx,cy,-.004), (w,h,.014), enamel, panel, .007)
        title_y = top*height + .005
        box('ECS_module_title_strip', (cx,title_y,.0035),(w-.020,.017,.0025),dark,panel,.001)
        ecs_legend('ECS_module_identification', title, (cx,title_y+.0040,.0055), .014, panel)
        for x in [left*width+.010, right*width-.010]:
            for y in [top*height+.011,bottom*height-.010]:
                screw = cyl('ECS_fascia_captive_screw',(x,y,.004),.0043,.0032,metal,panel,12)
                box('ECS_fascia_fastener_slot',(0,0,.0018),(.0057,.00075,.0005),dark,screw)
    for index, x in enumerate([.106,.177,.248]):
        y = -.234*height + index*.012
        tube_path('ECS_conditioning_hard_line', [(x,-.278*height,.004),(x,-.262*height,.022),
                  (x-.009,y,.029),(.004,y,.029),(-.064,y,.029),(-.088,y,.009)], .0046,metal,panel, sides=12)
        box('ECS_hard_line_clamp',(.067,y,.015),(.019,.015,.019),anodized,panel,.002)
        box('ECS_hard_line_bulkhead_fitting',(-.087,y,.0035),(.020,.016,.013),anodized,panel,.002)


ECS_MARKINGS = {
    'ecs_primary_co2_vent': 'PRIMARY VENT',
    'ecs_secondary_co2_vent': 'SECONDARY VENT',
    'ecs_primary_co2_cover': 'PRIMARY CO₂',
    'ecs_secondary_co2_cover': 'SECONDARY CO₂',
    'ecs_liquid_garment_cooling': 'LCG COOLING',
    'ecs_water_tank_safety_trigger': 'SAFETY',
}


def ecs_control_legend(control, root):
    cid = control['id']
    value = ECS_MARKINGS.get(cid, control['label'])
    # The module header occupies the upper edge. Put that first row's markings below the buttons.
    row = round(control['layout']['v'], 2)
    below = row in [.06, .39, .56, .73]
    if len(value) > 19:
        words = value.split()
        split = min(range(1,len(words)), key=lambda i: abs(len(' '.join(words[:i])) - len(' '.join(words[i:]))))
        value = ' '.join(words[:split]) + '\n' + ' '.join(words[split:])
    offset = (.030 if row == .06 else .045) if below else (-.056 if cid.endswith('_co2_cover') else -.037)
    point = (.047,.004,.0007) if cid == 'ecs_water_tank_safety_trigger' else (0,offset,.0007)
    ecs_legend('ECS_control_legend_'+cid, value, point, .0122, root)


def ecs_valve_geometry(cid, root, actuator):
    is_cover = cid.endswith('_co2_cover')
    radius = .039 if is_cover else .024
    cyl('ecs_valve_bezel', (0,0,.002), radius, .005, metal, root, 24)
    cyl('ecs_valve_seal', (0,0,.005), radius*.86, .003, rubber, root, 20)
    if is_cover:
        cyl('ecs_canister_cover', (0,0,.006), radius*.82, .013, liner, actuator, 24)
        box('ecs_canister_lock_bar', (0,0,.015), (radius*1.37,.013,.011), anodized,actuator,.004)
        return
    # Three-finger phenolic handwheel silhouette from the ECS control drawings.
    segments = 30
    profile = [(math.cos(a)*r, math.sin(a)*r)
               for a in (math.tau*i/segments for i in range(segments))
               for r in [.016 + .0038*math.cos(3*a)]]
    verts = [(x,y,z) for z in [.003,.016] for x,y in profile]
    faces = [tuple(reversed(range(segments))), tuple(range(segments,segments*2))]
    faces += [(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
    knob = mesh('ecs_three_lobe_handwheel', verts, faces, dark, actuator)
    for face in knob.data.polygons[2:]:
        face.use_smooth = True
    box('ecs_wheel_index', (0,.009,.0165), (.003,.009,.001), ivory,actuator)


def hammock_geometry(cid, actuator):
    rolled = empty(cid+'_rolled', parent=actuator)
    cloth_pack(cid+'_roll', (0,0,0), (.36,.108,.105), duck, rolled, (-.28,.25))
    box(cid+'_identity_tab', (0,.057,.008), (.067,.006,.029), paper, rolled, .004)
    wall_text(cid+'_identity', cid.split('_')[-1].upper(), (0,.061,.003), .011, dark, rolled)

    rigged = empty(cid+'_rigged', parent=actuator)
    rigged['aq_hide_in_blender_at_rest'] = True
    verts = []
    rows, across = 21, 11
    for row in range(rows):
        y = 1.54 * (row / (rows-1) - .5)
        tension = math.cos(math.pi * y / 1.54)
        for column in range(across):
            x = 2 * column / (across-1) - 1
            z = -.15*tension*(1-.55*x*x) + .013*tension*math.cos(5*x + 8*y)
            verts.append((x * (.10 + .14*tension), y, z))
    faces = [(i, i+1, i+across+1, i+across) for i in range((rows-1)*across) if i % across < across-1]
    fabric = mesh(cid+'_sling', verts, faces, duck, rigged)
    for face in fabric.data.polygons:
        face.use_smooth = True
    for column in [0, across-1]:
        edge = verts[column::across]
        tube_path(cid+'_hem', edge, .007, thread, rigged, sides=8)
    for sign in [-1, 1]:
        for x in [-.1,.1]:
            tube_path(cid+'_tie', [(x,sign*.77,0), (x*.62,sign*.89,.04), (0,sign*1.02,.115)], .006,
                      webbing, rigged, sides=8)
        cyl(cid+'_anchor_eye', (0,sign*1.02,.115), .013, .012, anodized, rigged, 12)
    return rolled, rigged


def ecs_union(name, point, axis, parent, scale=1.0):
    origin = Vector(point)
    direction = Vector(axis).normalized()
    quat = direction.to_track_quat('Z','Y')
    for distance, radius, depth, segments, finish in [(-.015,.028,.014,6,metal),(-.002,.024,.014,16,hose_cuff),
            (.012,.026,.010,12,anodized),(.024,.0205,.020,16,hose_cuff)]:
        fitting = cyl(name, origin + direction*distance*scale, radius*scale, depth*scale, finish, parent, segments)
        fitting.rotation_mode = 'QUATERNION'
        fitting.rotation_quaternion = quat


def build_aft_plumbing(aft):
    box('Aft_ecs_upper_manifold', (.67,-1.045,1.67), (.55,.14,.16), liner, aft, .022)
    lines = [
        ([(.61,-.948,1.656),(.61,-.894,1.655),(.79,-.836,1.61),(.962,-.764,1.45),
          (1.017,-.642,1.164),(1.012,-.558,.926),(.980,-.509,.851),(.924,-.400,.939),(.851,-.203,.947)], hose_jacket),
        ([(.805,-.948,1.657),(.805,-.890,1.655),(.972,-.813,1.602),(1.070,-.691,1.455),
          (1.085,-.643,1.202),(1.081,-.627,.986),(1.061,-.627,.911),(1.046,-.765,.931),(1.035,-.857,1.003)], hose_braid),
    ]
    for points, jacket in lines:
        inlet, outlet = Vector(points[0]), Vector(points[-1])
        ecs_union('Aft_manifold_quick_disconnect', inlet, Vector(points[1])-inlet, aft)
        hose_curve('Aft_oxygen_umbilical', points,.0185,jacket,aft,rib_pitch=.0135)
        ecs_union('Aft_umbilical_ferrule', outlet, Vector(points[-2])-outlet, aft)
    for z, y, x in [(1.20,-.635,1.092),(.98,-.763,1.076)]:
        box('Aft_umbilical_saddle',(x,y,z),(.030,.073,.050),anodized,aft,.007)
        rod('Aft_umbilical_saddle_bail',(x-.027,y-.027,z),(x-.027,y+.027,z),.006,metal,aft)
    cyl('Aft_manifold_blind_plug',(.923,-.969,1.663),.018,.015,metal,aft,6).rotation_euler.x = -math.pi/2
    for x in [.44,.67]:
        cyl('Aft_ecs_canister', (x,-1.026,.53), .086,.31, liner, aft, 30)
        for z in [.405,.62]:
            cyl('Aft_ecs_canister_band',(x,-1.026,z),.090,.029,anodized,aft,30)
            box('Aft_canister_band_clasp',(x-.046,-.949,z),(.027,.025,.032),metal,aft,.003)
        cyl('Aft_canister_lid_flange',(x,-1.025,.683),.092,.023,metal,aft,30)
        cyl('Aft_canister_lid_inset',(x,-1.025,.697),.068,.008,ecs_fascia,aft,28)
        rod('Aft_canister_pull',(x-.035,-.927,.56),(x+.035,-.927,.56),.009,dark,aft)
        for xx in [x-.030,x+.030]:
            rod('Aft_canister_pull_mount',(xx,-.933,.56),(xx,-.954,.56),.007,dark,aft)
    hose_curve('Aft_dispenser_supply',[(.54,-.938,.74),(.34,-.94,.64),(.15,-.91,.70),(.19,-.94,.92)], .012,hose_cuff,aft)
    ecs_union('Aft_dispenser_supply_union',(.54,-.938,.74),(-.23,0,-.12),aft,.69)


def build_aft_midsection():
    aft = empty('Aft_midsection')
    aft['source'] = 'LM-7 AOH fig. 2.11-15 and fig. 3-1; AS-508 final stowage list'
    aft['qualification'] = 'Reconstructed structure, shapes, soft goods and spacing within the provisional cabin envelope'
    box('Aft_pressure_bulkhead', (0,-1.204,1.036), (2.33,.108,2.082), shell, aft)
    box('Aft_crown_headliner', (0,-1.125,1.92), (1.89,.061,.27), liner, aft, .024)
    for side in [-1,1]:
        box('Aft_corner_closeout', (side*1.07,-1.105,1.13), (.19,.10,1.82), liner, aft, .033)
        for z in [.26,.72,1.75]:
            cyl('Aft_captive_fastener', (side*1.08,-1.046,z), .007,.004,metal,aft, 12).rotation_euler.x = -math.pi/2
    box('Aft_foot_rail', (0,-1.103,.11), (2.07,.09,.16), insulation, aft, .012)

    # The aft LMP-side controls keep their original plane and pick targets.
    box('Aft_ecs_rack', (.55,-1.113,1.13), (.89,.123,.83), avionics, aft, .026)
    for x in [.10,1.00]:
        rod('Aft_ecs_support', (x,-1.035,.73), (x,-1.035,1.54), .014, anodized, aft)
        for z in [.78,1.49]:
            box('Aft_ecs_mount', (x,-1.059,z), (.051,.051,.056), metal, aft, .006)
    build_aft_plumbing(aft)

    # Twin PLSS remote units are retained against the Z27 aft bulkhead.
    box('Aft_PLSS_remote_cradle', (-.088,-1.129,1.46), (.26,.045,.41), anodized,aft,.015)
    for z in [1.36,1.55]:
        box('Aft_PLSS_remote_unit', (-.088,-1.085,z), (.221,.085,.141), avionics,aft,.026)
        box('Aft_PLSS_remote_cover', (-.087,-1.037,z+.014), (.16,.012,.081),liner,aft,.006)
        rod('Aft_remote_retention_bar',(-.185,-1.014,z-.038),(.016,-1.014,z-.038),.010,metal,aft)
        hose_curve('Aft_PLSS_remote_lead',[(.066,-1.12,z-.073),(.037,-1.02,z-.074),(.026,-1.02,z-.034),(.012,-1.05,z+.015)], .006,rubber,aft)

    # Engine hump and covered service space occupy the center of the midsection.
    engine = empty('Aft_ascent_engine_cover', (0,-.897,0), aft)
    box('Aft_occluder_engine_cover', (0,0,.285), (.83,.55,.57), liner, engine, .133)
    box('Aft_engine_access_plate', (0,.012,.547), (.65,.44,.06), insulation, engine, .059)
    for x in [-.266,.266]:
        rod('Aft_engine_cover_edge', (x,-.12,.575), (x,.17,.575), .007, anodized, engine)
    cloth_pack('Aft_helmet_stowage_bag', (-.135,-.064,.70), (.36,.27,.25), duck, engine, (-.26,.28), -.14, handle=True)
    box('Aft_engine_heel_plate', (0,.251,.19), (.47,.029,.121), anodized, engine, .014)
    for x in [-.192, .192]:
        for z in [.152,.226]:
            cyl('Aft_engine_heel_fastener',(x,.267,z), .005,.006,metal,engine,12).rotation_euler.x = -math.pi/2
    for x, y, z in [(-.24,-1.122,1.495),(-.24,.924,1.495),(-1.02,-.36,.975),(1.02,-.36,.975)]:
        box('Cabin_rest_tether_anchor',(x,y,z),(.046,.028,.051),anodized,aft,.009)

    # The commander-side rack combines electronics, reference books and soft stowage.
    cdr = empty('Aft_commander_stowage', (-.67,-1.05,0), aft)
    box('Aft_stowage_frame', (0,-.038,1.13), (.75,.135,1.42), insulation, cdr, .030)
    for x in [-.358,.358]:
        rod('Aft_stowage_upright', (x,.074,.45),(x,.074,1.87), .011, anodized, cdr)
    for z in [.52,.91,1.30,1.56,1.85]:
        box('Aft_stowage_shelf', (0,.115,z), (.72,.346,.029), anodized, cdr, .012)
        rod('Aft_shelf_retention_rail', (-.34,.286,z+.027),(.34,.286,z+.027),.010,metal,cdr)

    # Data file. Different booklet sizes and tucked-in tabs make the form readable close up.
    cloth_pack('Aft_onboard_data_file', (-.07,.154,1.631), (.51,.255,.198), canvas, cdr, (-.33,.33))
    for x, h, tilt, title in [(-.21,.150,-.09,'CREW LOG'),(-.06,.159,.036,'LM PROCEDURES'),(.09,.148,-.03,'FLIGHT PLAN')]:
        book = empty('Aft_flight_book', (x,.210,1.695),cdr)
        book.rotation_euler.y = tilt
        box('Aft_book_pages', (0,0,.014), (.120,.031,h),paper,book,.002)
        box('Aft_book_front', (0,.019,.015), (.124,.006,h+.006),book_cover,book,.002)
        box('Aft_book_nameplate', (0,.024,.064), (.100,.003,.019),paper,book,.002)
        wall_text('Aft_book_title', title, (0,.026,.060), .0081,dark,book)
        box('Aft_book_edge_tab', (.054,.015,.086), (.024,.009,.016),duck,book,.002)
    box('Aft_data_file_sewn_tag',(-.092,.288,1.641),(.218,.009,.034),paper,cdr,.003)
    wall_text('Aft_file_identification', 'ONBOARD DATA FILE', (-.092,.295,1.635), .015, dark,cdr)

    box('Aft_data_storage_electronics', (.088,.165,1.43), (.476,.244,.231), avionics,cdr,.018)
    box('Aft_data_storage_face', (.088,.295,1.43), (.440,.013,.190), liner,cdr,.007)
    for x in [-.096,-.043,.019,.10,.175,.231]:
        box('Aft_avionics_cooling_slot', (x,.304,1.44), (.013,.004,.092),dark,cdr,.003)
    for x in [-.104,.276]:
        rod('Aft_avionics_pull', (x,.329,1.365),(x,.329,1.491),.009,metal,cdr)

    # Launch-stowage evidence establishes provision types. The visible packing is illustrative.
    cloth_pack('Aft_LHSSC_soft_case', (-.078,.161,1.10), (.486,.26,.30), canvas,cdr,(-.29,.28),.045,handle=True)
    cloth_pack('Aft_interim_stowage_side_pouch', (.247,.147,1.090), (.176,.219,.254), duck,cdr,(-.14,),-.11)
    for x, z, roll, height in [(-.21,.686,.05,.133),(-.028,.667,-.08,.106),(.17,.690,.14,.147)]:
        packet = empty('Aft_food_packet', (x,.214,z),cdr)
        packet.rotation_euler.y = roll
        box('Aft_food_inner_pack', (0,0,0), (.150,.038,height*.91),foil,packet,.014)
        box('Aft_food_packet_fold', (0,.010,height*.47), (.149,.017,.017),foil,packet,.004)
        for side in [-1,1]:
            box('Aft_food_packet_seal',(side*.073,0,0),(.009,.021,height),foil,packet,.003)
        box('Aft_food_packet_marking', (0,.021,.015), (.084,.004,.028),paper,packet,.002)
        for z_line, width in [(.020,.070),(.013,.054),(.006,.068)]:
            box('Aft_packet_print_line',(0,.024,z_line),(width,.0006,.0015),book_cover,packet)
    box('Aft_food_retention_band',(0,.265,.614),(.65,.010,.051),webbing,cdr,.005)
    for i in range(7):
        x = -.306 + .082*i
        rod('Aft_food_net_chevron',(x,.260,.63),(x+.074,.250,.730),.0035,thread,cdr)
        rod('Aft_food_net_chevron',(x+.074,.260,.63),(x,.250,.730),.0035,thread,cdr)
    rod('Aft_food_net_top',(-.317,.250,.730),(.315,.250,.730),.0045,webbing,cdr)

    # Secondary sidewall bags stay tied into their existing mounting regions.
    for side in [-1,1]:
        cloth_pack('Cabin_side_provision_bag',(side*1.065,-.274,.419),(.29,.186,.43),
                   duck if side<0 else canvas,aft,(-.23,.22),side*math.pi/2)
        box('Cabin_side_bag_retainer', (side*.966,-.274,.563),(.016,.34,.035),anodized,aft,.008)
