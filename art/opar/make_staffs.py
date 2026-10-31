"""Blender: Opar's six staffs, modelled, painted and written out for tools/chr/build_weapon.py.

    blender -b --factory-startup --python art/opar/make_staffs.py

Each staff is made in the weapon pack's own space (the hand at the origin, the shaft along +Z: the butt about 5.5
below the hand, the head 7-10 above it) and written out SCALE (1.45) times that, so it reaches from the ground to past
his head as in the concept (the butt about 8 below the hand, the head 10-13 above it); its paint baked by Cycles at 512 and scaled to the pack's 128 x 128 picture.
Writes art/opar/staffs/<stem>.json (triangles: positions, normals, UVs) and art/opar/staffs/<stem>.png, and
art/opar/staffs/staffs.blend to look at them.

| Stem | Staff | Look |
|---|---|---|
| opst01 | Driftwood Staff | bleached, gnarled driftwood curling into a hook, rope at the grip |
| opst02 | Reed Staff | a bundle of reeds tied with cord, a fan of fronds at the top |
| opst03 | Coral Staff | sea-worn wood crowned with branching coral |
| opst04 | Bog Oak Staff | two black oak stems twisted together, a root knot and moss at the head |
| opst05 | Moonpearl Staff | dark wood, a silver claw holding a moon pearl |
| opst06 | Tidecaller | the concept's staff: gnarled wood wound into a spiral hook round a glowing rune disc, rope and moss |
"""

import json
import math
import os
import random

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "staffs")
BAKE, SIZE = 512, 128
SCALE = 1.45  # written out this much bigger: modelled at Toan's sword's size, they read as twigs in Opar's big hands

# Patterns (the `pattern` attribute)
PLAIN, WOOD, METAL, GLOW, ROPE, MOSS, CORAL, PEARL = range(8)


def lin(c):
    return tuple(x ** 2.2 for x in c)


# ---------------------------------------------------------------------------------------------------------------------
# Shapes


def tube(points, radii, segs=8, caps=True):
    pts = [Vector(p) for p in points]
    n = len(pts)
    tangents = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
    x = tangents[0].orthogonal().normalized()
    v, f = [], []
    for i in range(n):
        t = tangents[i]
        x = (x - t * x.dot(t)).normalized()
        y = t.cross(x)
        for j in range(segs):
            a = 2 * math.pi * j / segs
            v.append(pts[i] + (x * math.cos(a) + y * math.sin(a)) * max(radii[i], 1e-3))
    for i in range(n - 1):
        for j in range(segs):
            a, b = i * segs + j, i * segs + (j + 1) % segs
            f.append((a, b, b + segs, a + segs))
    if caps:
        s, e = len(v), len(v) + 1
        v += [pts[0] - tangents[0] * radii[0] * 0.6, pts[-1] + tangents[-1] * radii[-1] * 0.6]
        last = (n - 1) * segs
        for j in range(segs):
            f.append((s, (j + 1) % segs, j))
            f.append((e, last + j, last + (j + 1) % segs))
    return v, f


def ellipsoid(c, r, rot=None, rings=6, segs=10):
    rot = rot or Matrix.Identity(3)
    v, f = [], []
    for i in range(1, rings):
        th = math.pi * i / rings
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            v.append(Vector(c) + rot @ Vector((math.sin(th) * math.cos(ph) * r[0], math.sin(th) * math.sin(ph) * r[1],
                                               math.cos(th) * r[2])))
    top, bottom = len(v), len(v) + 1
    v += [Vector(c) + rot @ Vector((0, 0, r[2])), Vector(c) + rot @ Vector((0, 0, -r[2]))]
    for i in range(rings - 2):
        for j in range(segs):
            a, b = i * segs + j, i * segs + (j + 1) % segs
            f.append((a, a + segs, b + segs, b))
    for j in range(segs):
        f.append((top, j, (j + 1) % segs))
        last = (rings - 2) * segs
        f.append((bottom, last + (j + 1) % segs, last + j))
    return v, f


def ring(center, axis, radius, thick, segs=12, sides=4):
    axis = Vector(axis).normalized()
    x = axis.orthogonal().normalized()
    y = axis.cross(x)
    v, f = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c = Vector(center) + (x * math.cos(a) + y * math.sin(a)) * radius
        out = (c - Vector(center)).normalized()
        for j in range(sides):
            b = 2 * math.pi * j / sides
            v.append(c + (out * math.cos(b) + axis * math.sin(b)) * thick)
    for i in range(segs):
        for j in range(sides):
            a0, a1 = i * sides + j, i * sides + (j + 1) % sides
            b0, b1 = ((i + 1) % segs) * sides + j, ((i + 1) % segs) * sides + (j + 1) % sides
            f.append((a0, b0, b1, a1))
    return v, f


def disc(center, normal, radius, thick, segs=24):
    """A flat round plate, its faces flat and its rim round."""
    n = Vector(normal).normalized()
    x = n.orthogonal().normalized()
    y = n.cross(x)
    c = Vector(center)
    v, f = [], []
    rings = [(0.0, -0.5), (0.92, -0.5), (1.0, -0.25), (1.0, 0.25), (0.92, 0.5), (0.0, 0.5)]
    for rr, hh in rings[1:-1]:
        for j in range(segs):
            a = 2 * math.pi * j / segs
            v.append(c + (x * math.cos(a) + y * math.sin(a)) * radius * rr + n * thick * hh)
    back, front = len(v), len(v) + 1
    v += [c - n * thick / 2, c + n * thick / 2]
    k = len(rings) - 2
    for i in range(k - 1):
        for j in range(segs):
            a, b = i * segs + j, i * segs + (j + 1) % segs
            f.append((a, b, b + segs, a + segs))
    last = (k - 1) * segs
    for j in range(segs):
        f.append((back, (j + 1) % segs, j))
        f.append((front, last + j, last + (j + 1) % segs))
    return v, f


def gnarled(z0, z1, r0, r1, rng, wiggle=0.12, knots=4, steps=26):
    """A crooked shaft along +Z with knots."""
    pts, radii = [], []
    kz = [rng.uniform(z0 + 1, z1 - 1) for _ in range(knots)]
    ph = [rng.uniform(0, 6.28) for _ in range(4)]
    for i in range(steps + 1):
        t = i / steps
        z = z0 + (z1 - z0) * t
        x = wiggle * (math.sin(z * 0.9 + ph[0]) + 0.5 * math.sin(z * 2.3 + ph[1]))
        y = wiggle * (math.sin(z * 0.7 + ph[2]) + 0.5 * math.sin(z * 1.9 + ph[3]))
        r = r0 + (r1 - r0) * t
        r *= 1 + sum(0.35 * math.exp(-((z - k) / 0.25) ** 2) for k in kz)
        pts.append(Vector((x, y, z)))
        radii.append(r)
    return pts, radii


def spiral_cord(center_line, radius, turns, thick=0.07, per_turn=12):
    """A cord wound round a straight part of the shaft (points along it), as a tube."""
    a, b = Vector(center_line[0]), Vector(center_line[1])
    axis = (b - a).normalized()
    x = axis.orthogonal().normalized()
    y = axis.cross(x)
    n = int(turns * per_turn) + 1
    pts = [a.lerp(b, k / (n - 1)) + (x * math.cos(2 * math.pi * turns * k / (n - 1)) +
                                       y * math.sin(2 * math.pi * turns * k / (n - 1))) * radius for k in range(n)]
    return tube(pts, [thick] * n, segs=5)


class Staff:
    def __init__(self):
        self.parts = []

    def add(self, vf, colour, pattern=PLAIN):
        self.parts.append((vf[0], vf[1], lin(colour), pattern))


# ---------------------------------------------------------------------------------------------------------------------
# The six staffs

BLEACHED = (0.72, 0.64, 0.52)
WOOD_MID = (0.42, 0.29, 0.18)
WOOD_DARK = (0.18, 0.12, 0.09)
CORD = (0.62, 0.48, 0.30)
MOSS_GREEN = (0.36, 0.50, 0.20)
REED_GREEN = (0.55, 0.60, 0.32)
REED_TAN = (0.74, 0.66, 0.42)
CORAL_PINK = (0.92, 0.48, 0.42)
SILVER = (0.72, 0.74, 0.78)
PEARL_WHITE = (0.92, 0.92, 0.96)
TEAL = (0.35, 0.95, 0.85)
DISC_FACE = (0.62, 0.86, 0.80)
RUNE = (0.86, 0.42, 0.40)


def driftwood(rng):
    S = Staff()
    pts, radii = gnarled(-5.6, 6.2, 0.26, 0.22, rng, wiggle=0.16)
    top = pts[-1]
    for k in range(1, 12):  # curling over into a hook
        a = math.radians(16 * k)
        pts.append(top + Vector((0.9 * (1 - math.cos(a)), 0, 0.9 * math.sin(a))))
        radii.append(0.22 * (1 - k / 14))
    S.add(tube(pts, radii, segs=8), BLEACHED, WOOD)
    S.add(spiral_cord(((0, 0, -0.9), (0, 0, 0.9)), 0.3, 7), CORD, ROPE)
    return S


def reed(rng):
    S = Staff()
    for k in range(5):
        a = 2 * math.pi * k / 5
        off = Vector((math.cos(a) * 0.13, math.sin(a) * 0.13, 0))
        pts = [off + Vector((0.02 * math.sin(z * 1.3 + k), 0, z)) for z in [-5.5 + 12.5 * i / 16 for i in range(17)]]
        S.add(tube(pts, [0.1] * len(pts), segs=6), REED_TAN if k % 2 else REED_GREEN, WOOD)
    for z in (-3.5, 0.0, 3.5, 6.6):
        S.add(ring((0, 0, z), (0, 0, 1), 0.25, 0.06, segs=10), CORD, ROPE)
    for k in range(9):  # the fronds
        a = 2 * math.pi * k / 9
        d = Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 1.0)).normalized()
        base = Vector((0, 0, 7.0))
        tip = base + d * rng.uniform(1.6, 2.2)
        mid = base.lerp(tip, 0.5) + Vector((0, 0, 0.15))
        S.add(tube([base, mid, tip], [0.08, 0.06, 0.01], segs=4), REED_GREEN, MOSS)
    return S


def coral(rng):
    S = Staff()
    pts, radii = gnarled(-5.6, 6.6, 0.25, 0.2, rng, wiggle=0.1)
    S.add(tube(pts, radii, segs=8), WOOD_MID, WOOD)
    top = pts[-1]

    def branch(p, d, r, depth, length):
        pts, radii = [p], [r]
        q, dd = Vector(p), Vector(d)
        steps = 6
        for k in range(1, steps + 1):
            dd = (dd + Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 0.18))).normalized()
            q = q + dd * (length / steps)
            pts.append(q.copy())
            radii.append(r * (1 - 0.55 * k / steps))
        S.add(tube(pts, radii, segs=7), CORAL_PINK, CORAL)
        S.add(ellipsoid(pts[-1], (radii[-1] * 1.25,) * 3, rings=5, segs=7), CORAL_PINK, CORAL)
        if depth > 0:
            for k in (2, 4):
                nd = (dd + Vector((rng.uniform(-0.9, 0.9), rng.uniform(-0.9, 0.9), 0.2))).normalized()
                branch(pts[k], nd, radii[k] * 0.8, depth - 1, length * 0.55)

    for k in range(4):
        a = 2 * math.pi * k / 4 + 0.4
        branch(top, Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, 1)).normalized(), 0.17, 1, 2.0)
    S.add(spiral_cord(((0, 0, -0.9), (0, 0, 0.9)), 0.29, 7), CORD, ROPE)
    return S


def bog_oak(rng):
    S = Staff()
    for k in range(2):
        pts = []
        for i in range(31):
            z = -5.6 + 12.4 * i / 30
            a = z * 0.9 + k * math.pi
            pts.append(Vector((math.cos(a) * 0.13, math.sin(a) * 0.13, z)))
        S.add(tube(pts, [0.17 - 0.03 * (i / 30) for i in range(31)], segs=7), WOOD_DARK, WOOD)
    knot = Vector((0, 0, 7.3))
    S.add(ellipsoid(knot, (0.62, 0.56, 0.78), rings=8, segs=12), WOOD_DARK, WOOD)
    S.add(ellipsoid(knot + Vector((0.18, -0.1, 0.35)), (0.42, 0.4, 0.45), rings=6, segs=10), WOOD_DARK, WOOD)
    S.add(ellipsoid(knot + Vector((-0.2, 0.15, -0.3)), (0.45, 0.42, 0.42), rings=6, segs=10), WOOD_DARK, WOOD)
    for k in range(6):  # roots hugging the knot down onto the shaft
        a = 2 * math.pi * k / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [knot + d * 0.5 + Vector((0, 0, 0.1)), knot + d * 0.66 + Vector((0, 0, -0.4)),
               knot + d * 0.45 + Vector((0, 0, -0.9)), knot + d * 0.22 + Vector((0, 0, -1.4))]
        S.add(tube(pts, [0.11, 0.1, 0.07, 0.03], segs=6), WOOD_DARK, WOOD)
    for k in range(5):
        a = 2 * math.pi * k / 5 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        rot = Matrix.Rotation(a, 3, "Z")
        S.add(ellipsoid(knot + d * 0.55 + Vector((0, 0, rng.uniform(0.0, 0.5))), (0.12, 0.34, 0.3), rot=rot, rings=4,
                        segs=8), MOSS_GREEN, MOSS)
    S.add(spiral_cord(((0, 0, -0.9), (0, 0, 0.9)), 0.35, 7), CORD, ROPE)
    return S


def moonpearl(rng):
    S = Staff()
    pts, radii = gnarled(-5.6, 6.4, 0.24, 0.21, rng, wiggle=0.08, knots=3)
    S.add(tube(pts, radii, segs=8), WOOD_DARK, WOOD)
    top = pts[-1]
    pearl = top + Vector((0, 0, 1.15))
    S.add(ellipsoid(pearl, (0.62, 0.62, 0.62), rings=8, segs=12), PEARL_WHITE, PEARL)
    for k in range(4):  # the silver claw
        a = 2 * math.pi * k / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        claw = [top, top + d * 0.45 + Vector((0, 0, 0.35)), pearl + d * 0.7 + Vector((0, 0, -0.1)),
                pearl + d * 0.45 + Vector((0, 0, 0.55))]
        S.add(tube(claw, [0.1, 0.09, 0.07, 0.02], segs=5), SILVER, METAL)
    for z in (top.z - 0.3, -0.9, 0.9):
        S.add(ring((0, 0, z), (0, 0, 1), 0.27, 0.06, segs=12), SILVER, METAL)
    return S


def tidecaller(rng):
    S = Staff()
    pts, radii = gnarled(-5.6, 5.8, 0.27, 0.22, rng, wiggle=0.18, knots=5)
    top = pts[-1]
    # the head: the wood winds up and round in a spiral hook, about a disc
    centre = top + Vector((0.35, 0, 1.6))
    for k in range(1, 38):
        a = math.radians(-90 + 11 * k)
        r = 1.4 * (1 - k / 58)
        pts.append(centre + Vector((math.cos(a) * r, 0.04 * math.sin(k), math.sin(a) * r)))
        radii.append(0.22 * (1 - k / 44))
    S.add(tube(pts, radii, segs=8), WOOD_MID, WOOD)
    S.add(disc(centre, (0, 1, 0), 0.66, 0.14), DISC_FACE, GLOW)
    S.add(ring(centre, (0, 1, 0), 0.68, 0.07, segs=24, sides=5), TEAL, GLOW)
    # the rune on the disc (a branching glyph), both faces
    for face in (-1, 1):
        y = face * 0.085
        glyph = [((0, -0.42), (0, 0.42)), ((0, 0.1), (0.3, 0.32)), ((0, 0.1), (-0.3, 0.32)), ((0, -0.15), (0.26, -0.35)),
                 ((0, -0.15), (-0.26, -0.35)), ((0.3, 0.32), (0.36, 0.1)), ((-0.3, 0.32), (-0.36, 0.1))]
        for (ax, az), (bx, bz) in glyph:
            a = centre + Vector((ax, y, az))
            b = centre + Vector((bx, y, bz))
            S.add(tube([a, b], [0.05, 0.05], segs=5), RUNE, PLAIN)
    # rope at the grip and under the head, its ends hanging
    S.add(spiral_cord(((0, 0, -0.9), (0, 0, 0.9)), 0.32, 7), CORD, ROPE)
    S.add(spiral_cord(((top.x, top.y, top.z - 1.0), (top.x, top.y, top.z - 0.1)), 0.27, 3), CORD, ROPE)
    for dx in (-0.1, 0.12):
        a = Vector((top.x + 0.28, top.y + dx, top.z - 0.6))
        S.add(tube([a, a + Vector((0.12, 0, -0.7)), a + Vector((0.08, 0.05, -1.4))], [0.05, 0.045, 0.04], segs=4),
              CORD, ROPE)
    for k in range(5):  # moss, flat on the wood
        z = rng.uniform(top.z - 1.4, top.z + 0.3)
        a = rng.uniform(0, 6.28)
        d = Vector((math.cos(a), math.sin(a), 0))
        S.add(ellipsoid(d * 0.2 + Vector((0, 0, z)), (0.1, 0.3, 0.36), rot=Matrix.Rotation(a, 3, "Z"), rings=4,
                        segs=8), MOSS_GREEN, MOSS)
    for k in range(5):  # water beads round the disc
        a = rng.uniform(0, 6.28)
        p = centre + Vector((math.cos(a) * 1.0, rng.uniform(-0.3, 0.3), math.sin(a) * 1.0))
        S.add(ellipsoid(p, (0.09, 0.09, 0.09), rings=4, segs=6), TEAL, GLOW)
    return S


STAFFS = [("opst01", driftwood), ("opst02", reed), ("opst03", coral), ("opst04", bog_oak), ("opst05", moonpearl),
          ("opst06", tidecaller)]


# ---------------------------------------------------------------------------------------------------------------------
# Paint and output


def material(name, image):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    new = nt.nodes.new
    link = nt.links.new

    def math_(op, a, b):
        m = new("ShaderNodeMath")
        m.operation = op
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                m.inputs[i].default_value = x
            else:
                link(x, m.inputs[i])
        return m.outputs[0]

    def rng_(x, a, b, c, d):
        m = new("ShaderNodeMapRange")
        m.inputs["From Min"].default_value, m.inputs["From Max"].default_value = a, b
        m.inputs["To Min"].default_value, m.inputs["To Max"].default_value = c, d
        link(x, m.inputs["Value"])
        return m.outputs[0]

    out = new("ShaderNodeOutputMaterial")
    emit = new("ShaderNodeEmission")
    link(emit.outputs[0], out.inputs["Surface"])
    paint = new("ShaderNodeAttribute"); paint.attribute_name = "paint"
    pat = new("ShaderNodeAttribute"); pat.attribute_name = "pattern"
    coord = new("ShaderNodeTexCoord").outputs["Object"]

    def mask(i):
        return rng_(math_("ABSOLUTE", math_("SUBTRACT", pat.outputs["Fac"], float(i)), None), 0.0, 0.3, 1.0, 0.0)

    wave = new("ShaderNodeTexWave"); wave.wave_type = "BANDS"; wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 3.0; wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 3.0
    link(coord, wave.inputs["Vector"])
    wood = rng_(wave.outputs["Fac"], 0.2, 0.9, 0.7, 1.2)
    nz = new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 18.0; link(coord, nz.inputs["Vector"])
    metal = rng_(nz.outputs["Fac"], 0.4, 0.6, 0.85, 1.25)
    rope = rng_(nz.outputs["Fac"], 0.35, 0.65, 0.75, 1.15)
    vor = new("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 14.0; link(coord, vor.inputs["Vector"])
    coral = rng_(vor.outputs["Distance"], 0.05, 0.25, 0.65, 1.1)
    moss = rng_(nz.outputs["Fac"], 0.4, 0.6, 0.65, 1.2)
    geo = new("ShaderNodeNewGeometry")
    sep = new("ShaderNodeSeparateXYZ"); link(geo.outputs["Normal"], sep.inputs[0])
    pearl = rng_(sep.outputs["X"], -1.0, 1.0, 0.85, 1.12)
    acc = None
    for i, f in ((WOOD, wood), (METAL, metal), (ROPE, rope), (MOSS, moss), (CORAL, coral), (PEARL, pearl)):
        term = math_("MULTIPLY", mask(i), math_("SUBTRACT", f, 1.0))
        acc = term if acc is None else math_("ADD", acc, term)
    factor = math_("ADD", acc, 1.0)
    ao = new("ShaderNodeAmbientOcclusion"); ao.only_local = True; ao.samples = 16
    ao.inputs["Distance"].default_value = 0.4
    shade = rng_(ao.outputs["AO"], 0.0, 1.0, 0.5, 1.0)
    light = math_("MULTIPLY", shade, factor)
    glow = mask(GLOW)
    light = math_("ADD", math_("MULTIPLY", light, math_("SUBTRACT", 1.0, glow)), math_("MULTIPLY", glow, 1.15))
    gray = new("ShaderNodeCombineXYZ")
    for k in "XYZ":
        link(light, gray.inputs[k])
    mix = new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    link(paint.outputs["Color"], mix.inputs["A"]); link(gray.outputs[0], mix.inputs["B"])
    link(mix.outputs["Result"], emit.inputs["Color"])
    target = new("ShaderNodeTexImage"); target.image = image
    nt.nodes.active = target
    return mat


def build(stem, staff, scene, row):
    verts, faces, colours, patterns = [], [], [], []
    for pv, pf, col, pat in staff.parts:
        base = len(verts)
        verts += [tuple(p) for p in pv]
        faces += [tuple(base + i for i in f) for f in pf]
        colours += [col] * len(pv)
        patterns += [float(pat)] * len(pv)
    mesh = bpy.data.meshes.new(stem)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.shade_smooth()
    attr = mesh.color_attributes.new("paint", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(colours):
        attr.data[i].color = (*c, 1.0)
    a = mesh.attributes.new("pattern", "FLOAT", "POINT")
    a.data.foreach_set("value", patterns)
    img = bpy.data.images.new("bake_" + stem, BAKE, BAKE, alpha=False)
    mesh.materials.append(material(stem, img))
    obj = bpy.data.objects.new(stem, mesh)
    scene.collection.objects.link(obj)
    view = bpy.context.view_layer
    for o in view.objects:
        o.select_set(False)
    view.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=0.006, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.bake(type="EMIT", margin=6, use_clear=True)
    img.scale(SIZE, SIZE)
    img.filepath_raw = os.path.join(OUT, stem + ".png")
    img.file_format = "PNG"
    img.save()
    # triangles for the pack: position, normal, UV per corner (the pack's space is the mesh's)
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers.active.data
    tris = []
    for t in mesh.loop_triangles:
        corners = []
        for li in t.loops:
            loop = mesh.loops[li]
            corners.append({"p": [x * SCALE for x in mesh.vertices[loop.vertex_index].co], "n": list(loop.normal),
                            "uv": [uv[li].uv[0], 1.0 - uv[li].uv[1]]})
        tris.append(corners)
    json.dump({"stem": stem, "triangles": tris}, open(os.path.join(OUT, stem + ".json"), "w"))
    obj.location.x = row * 3.2
    show = mat_show(stem, img.filepath_raw)
    mesh.materials[0] = show
    return len(tris)


def mat_show(stem, path):
    mat = bpy.data.materials.new(stem + "_show")
    mat.use_nodes = True
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path, check_existing=False)
    nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return mat


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    os.makedirs(OUT, exist_ok=True)
    for row, (stem, make) in enumerate(STAFFS):
        n = build(stem, make(random.Random(row * 31 + 7)), scene, row)
        print("STAFF", stem, "triangles", n)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "staffs.blend"))


main()
