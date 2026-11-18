"""Shape helpers executed in build-cabin.py's Blender generation context.

These are editable, source-qualified presentation proxies. Published lengths
are used where established; unmeasured shapes and poses remain provisional.
"""

def mechanism_ring(name, radius, inner, z, mat, parent, segments=32):
    verts = []
    for r in [radius, inner]:
        verts.extend((r*math.cos(i*math.tau/segments), r*math.sin(i*math.tau/segments), z) for i in range(segments))
    faces = [(i, (i+1)%segments, (i+1)%segments+segments, i+segments) for i in range(segments)]
    return mesh(name, verts, faces, mat, parent)


def sight_tube(name, outer, inner, front, rear, parent, segments=64):
    verts = [(radius * math.cos(i * math.tau / segments), radius * math.sin(i * math.tau / segments), z)
             for radius, z in [(outer, front), (outer, rear), (inner, front), (inner, rear)]
             for i in range(segments)]
    faces = []
    for i in range(segments):
        j = (i + 1) % segments
        faces.extend([(i, j, j+segments, i+segments),
                      (i+2*segments, i+3*segments, j+3*segments, j+2*segments)])
    tube = mesh(name, verts, faces, dark, parent)
    for face in tube.data.polygons:
        face.use_smooth = True
    return tube

def build_mechanism_shape(control, root, actuator, specification):
    cid = control['id']
    shape = specification['shape']
    if shape in ['forward_shade', 'docking_shade']:
        film = material('shade_film', (.002, .003, .004), 0, .97)
        if shape == 'forward_shade':
            side = -1 if cid == 'shade_cdr' else 1
            vertices = [(-side*.01, .78, .008), (side*.62, .54, .008), (0, 0, .008)]
            rod(cid+'_roller', (0, 0, .004), (side*.62, 0, .004), .012, rubber, root)
        else:
            vertices = [(-.17, 0, .008), (.17, 0, .008), (.17, .25, .008), (-.17, .25, .008)]
            rod(cid+'_roller', (-.18, 0, .004), (.18, 0, .004), .012, rubber, root)
        mesh(cid+'_sheet', vertices, [tuple(range(len(vertices)))], film, actuator)
    elif shape == 'armrest':
        joint = cyl(cid+'_hinge', (0, 0, 0), .027, .10, metal, root, 24)
        joint.rotation_euler.y = math.pi/2
        box(cid+'_arm', (0, .15, .012), (.048, .31, .032), metal, actuator, .008)
        box(cid+'_pad', (0, .16, .038), (.085, .28, .025), rubber, actuator, .009)
        box(cid+'_detent_release', (.044, .24, .020), (.012, .024, .012), ivory, actuator)
    elif shape == 'reel':
        cyl(cid+'_reel_body', (0, 0, .010), .036, .026, dark, root, 24)
        cyl(cid+'_spindle', (0, 0, .027), .012, .013, metal, actuator, 16)
        box(cid+'_lock_lever', (0, .019, .035), (.012, .045, .009), ivory, actuator, .003)
    elif shape in ['pin', 'pin_set', 'connector']:
        cyl(cid+'_socket', (0, 0, .003), .012, .012, dark, root, 20)
        cyl(cid+'_shaft', (0, 0, .015), .007, .033, metal, actuator, 16)
        rod(cid+'_handle', (-.018, 0, .033), (.018, 0, .033), .004, ivory, actuator)
    elif shape == 'coas':
        # AOH gives an overall8-inch length; shape/envelope are not a scan.
        sight_tube(cid+'_barrel', .026, .021, .010, .200, actuator)
        for zz in [.020, .170, .200]:
            mechanism_ring(cid+'_barrel_ring', .031, .021, zz, metal, actuator, 64)
        mechanism_ring(cid+'_eyepiece', .024, .019, .2032, rubber, actuator, 64)
        rod(cid+'_reticle_x', (-.019, 0, .208), (.019, 0, .208), .00020, ivory, actuator)
        rod(cid+'_reticle_y', (0, -.019, .208), (0, .019, .208), .00020, ivory, actuator)
        box(cid+'_mount_foot', (0, -.036, .045), (.052, .025, .070), metal, actuator, .004)
    elif shape == 'knob':
        cyl(cid+'_base', (0, 0, .002), .011, .006, metal, root, 24)
        cyl(cid+'_knob', (0, 0, .011), .009, .015, rubber, actuator, 20)
        box(cid+'_pointer', (0, .005, .019), (.002, .010, .002), ivory, actuator)
    elif shape in ['lock', 'clamp', 'assembly_retention']:
        box(cid+'_bracket', (0, 0, .004), (.038, .035, .008), metal, root, .003)
        cyl(cid+'_pivot', (0, 0, .015), .006, .018, dark, actuator, 16)
        box(cid+'_retention_lever', (0, .014, .025), (.012, .038, .010), ivory, actuator, .003)
        if shape == 'clamp':
            for xx in [-.021, .021]: box(cid+'_jaw', (xx, 0, .012), (.009, .038, .025), metal, root)
    elif shape == 'cap':
        radius = .018 if cid.startswith('water_') else .032
        cyl(cid+'_cap', (0, 0, .007), radius, .014, ivory, actuator, 32)
        cyl(cid+'_rim', (0, 0, .014), radius*.9, .003, rubber, actuator, 32)
    elif shape == 'filter':
        frame = mechanism_ring(cid+'_frame', .030, .024, .006, metal, actuator)
        frame.location.y = -.042
        box(cid+'_tab', (0, -.005, .006), (.012, .024, .004), ivory, actuator)
    elif shape == 'portable_lamp':
        cyl(cid+'_body', (0, 0, .047), .017, .095, metal, actuator, 24)
        cyl(cid+'_grip', (0, 0, .035), .018, .045, rubber, actuator, 20)
        cyl(cid+'_lens', (0, 0, .099), .015, .005, diffuser, actuator, 24)
        mechanism_ring(cid+'_lens_rim', .019, .015, .102, dark, actuator, 24)
    elif shape == 'reflector':
        box(cid+'_housing', (0, 0, .004), (.25, .050, .025), dark, root, .006)
        box(cid+'_reflector', (0, 0, .020), (.230, .044, .010), metal, actuator, .004)
        rod(cid+'_diffuser', (-.10, 0, .028), (.10, 0, .028), .008, diffuser, actuator)
    elif shape in ['ptt', 'trigger']:
        box(cid+'_body', (0, 0, .003), (.028, .042, .016), dark, root, .004)
        box(cid+'_button', (0, 0, .013), (.017, .027, .008), ivory, actuator, .003)
    elif shape == 'dispenser':
        cyl(cid+'_hose_collar', (0, 0, -.006), .014, .018, metal, actuator, 20)
        cyl(cid+'_body', (0, 0, .048), .027, .096, ivory, actuator, 24)
        cyl(cid+'_neck', (0, 0, .105), .011, .030, metal, actuator, 20)
        cyl(cid+'_nozzle_bore', (0, 0, .1205), .006, .001, rubber, actuator, 20)
        rod(cid+'_grip', (.028, 0, .020), (.040, 0, .075), .009, rubber, actuator)
    elif shape == 'tool_b':
        # Source gives6.25-inch total length and4.25-inch shaft, not a full shape.
        rod(cid+'_shaft', (0, 0, .004), (0, .10795, .004), .0056, metal, root)
        rod(cid+'_handle', (-.035, 0, .004), (.035, 0, .004), .009, rubber, root)
        box(cid+'_head', (0, .136, .006), (.030, .0455, .020), metal, actuator, .004)
        cyl(cid+'_ball_lock', (0, .127, .022), .005, .006, ivory, actuator, 16)
    elif shape == 'drogue':
        segments = 32
        verts = [(r*math.cos(i*math.tau/segments), r*math.sin(i*math.tau/segments), z)
                 for r, z in [(.29, 0), (.055, .235)] for i in range(segments)]
        faces = [(i, (i+1)%segments, (i+1)%segments+segments, i+segments) for i in range(segments)]
        mesh(cid+'_cone', verts, faces, ivory, actuator)
        mechanism_ring(cid+'_rim', .305, .282, .002, metal, actuator)
    elif shape == 'antibacterial_filter':
        cyl(cid+'_body', (0, 0, .005), .052, .018, metal, actuator, 32)
        for index in range(-4, 5):
            extent = math.sqrt(max(0, .043**2-(index*.009)**2))
            rod(cid+'_grille', (-extent, index*.009, .016), (extent, index*.009, .016), .0015, dark, actuator)
    elif shape == 'hammock':
        hammock_geometry(cid, actuator)
    else:
        raise ValueError('Unknown mechanism presentation shape: '+shape)

def apply_mechanism_default(control, root, actuator, specification):
    motion = specification.get('motion', {})
    index = control['positions'].index(control['default'])
    kind = motion.get('kind')
    if kind in ['rotate', 'translate', 'scale']:
        axis = 'xyz'.index(motion['axis'])
        value = motion['values'][index]
        if kind == 'rotate': actuator.rotation_euler[axis] += math.radians(value)
        elif kind == 'translate': actuator.location[axis] += value
        else: actuator.scale[axis] *= value
    elif kind == 'poses':
        delta = Vector(motion['worldPositionsBlenderM'][index])-Vector(specification['positionBlenderM'])
        actuator.location += root.rotation_euler.to_matrix().inverted() @ delta
        if motion.get('worldRotationsBlenderDeg'):
            target = Euler(tuple(math.radians(v) for v in motion['worldRotationsBlenderDeg'][index]), 'XYZ').to_matrix()
            actuator.rotation_euler = (root.rotation_euler.to_matrix().inverted() @ target).to_euler()
