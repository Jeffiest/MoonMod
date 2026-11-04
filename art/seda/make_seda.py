"""Blender: Seda's model, paint and weights in seda.blend.

    blender -b art/seda/seda.blend --python art/seda/make_seda.py -- --retail <seda.gltf>   # his own model
    blender -b art/seda/seda.blend --python art/seda/make_seda.py                           # the stand-in

**His own model (`--retail`).** The game has Seda (pack `c07a`, from his floor 8 fight). `tools/chr/build_character.py
retail` exports that pack from your disc's data and runs this with it. His mesh is fitted onto Toan's skeleton
(retail_model): scaled so his hips stand at Toan's, then each of his chain bones' part of the mesh turned and moved so
the bone lies along Toan's bone of the same name, blended by his own skin weights. The weights carry over by name.
His own pictures are baked into the pack's four pages (head, torso and arms, waist, legs) through his own UVs. If his
joints are not named as Toan's, he is scaled to Toan's height and weighted by distance instead (retail_fallback).

**The stand-in** (no `--retail`), made before his pack was found:

Seda, the swordsman of four hundred years ago: lean and pale, long white hair falling down his back, red eyes, a
violet long coat over a dark shirt, its skirt split at the front and hemmed in silver, a high collar, a steel pauldron
on the left shoulder, a belt with a silver buckle, dark gloves and boots. Built on Toan's skeleton (the Opar file's,
with Opar's wider hips taken back out: proportions.json is empty), so he plays Toan's motions and holds his swords.

Replaces the "Character" collection's body (`skin`) and writes its four pictures to art/seda/textures: c08d02 (head
and hair), c08d03 (torso and arms), c08d05 (legs and boots), c08d04 (coat skirt, collar, belt, pauldron). Then build
the pack with tools/chr/build_character.py build --art art/seda. Previews of the result go to art/seda/previews.

- Body, one skin: volumes (pelvis, waist, chest, shoulders, neck, a narrow head with jaw, brow and nose, arms, hands,
  legs, booted feet) fused by a voxel remesh, smoothed and decimated to TRIANGLES.
- Gear on top, each its own shell joined into the skin: the coat's skirt (an open cone from the waist to below the
  knees, its front open), the collar, the belt and buckle, the pauldron, and the hair (a cap, a long fall down the
  back, two side locks and the fringe).
- Paint: each part's colour by region, then baked by Cycles (cloth grain, hair streaks, ambient occlusion) at 1024
  and scaled to the pack's 256.
- Weights: to the skeleton's 20 chain joints by distance, kept to the body's side and region, at most 3 a vertex.
  The skirt follows the hips and thighs, more the thighs the lower it hangs; the hair's fall follows the head at the
  top and the chest at its end, so it doesn't stretch when he turns.
Coordinates are Blender's: Z up, the front is -Y, the character's left is +X.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(bpy.data.filepath) or os.path.dirname(os.path.abspath(__file__))
TEXTURES = os.path.join(HERE, "textures")
PREVIEWS = os.path.join(HERE, "previews")
PACK = "c08d"
HEAD, TORSO, GEAR, LEGS_TEX = PACK + "02", PACK + "03", PACK + "04", PACK + "05"
PAGES = (HEAD, TORSO, GEAR, LEGS_TEX)
BAKE_SIZE, SIZE = 1024, 256
TRIANGLES = 5200

# Colours as they look on screen (sRGB)
SKIN = (0.86, 0.76, 0.70)
SKIN_SHADE = (0.74, 0.62, 0.58)
EYE = (0.78, 0.08, 0.10)
PUPIL = (0.10, 0.02, 0.03)
BROW = (0.62, 0.62, 0.66)
LIPS = (0.70, 0.52, 0.52)
HAIR = (0.90, 0.90, 0.94)
COAT = (0.29, 0.18, 0.42)
COAT_INNER = (0.16, 0.10, 0.24)
SHIRT = (0.30, 0.28, 0.34)
TRIM = (0.74, 0.74, 0.80)
TROUSERS = (0.17, 0.16, 0.21)
LEATHER = (0.25, 0.17, 0.11)
GLOVE = (0.16, 0.12, 0.10)
STEEL = (0.56, 0.58, 0.64)
BUCKLE = (0.80, 0.78, 0.70)

# Paint patterns (the `pattern` attribute): how the bake works each part's surface
PLAIN, CLOTH, HAIR_PAT, METAL = 0, 1, 2, 3


def lin(c):
    return tuple(x ** 2.2 for x in c)


DEFORM = [
    "jnt1_1", "jnt2_1", "jnt11_1", "jnt12_1",
    "jnt8_1", "jnt9_1", "jnt9_2", "jnt10_1",
    "jnt16_1", "jnt17_1", "jnt17_2", "jnt18_1",
    "jnt22_1", "jnt22_2", "jnt23_1", "jnt24_1",
    "jnt5_1", "jnt5_2", "jnt6_1", "jnt7_1",
]
LEFT = {"jnt8_1", "jnt9_1", "jnt9_2", "jnt10_1", "jnt5_1", "jnt5_2", "jnt6_1", "jnt7_1"}
RIGHT = {"jnt16_1", "jnt17_1", "jnt17_2", "jnt18_1", "jnt22_1", "jnt22_2", "jnt23_1", "jnt24_1"}
ARMS = {"jnt9_1", "jnt9_2", "jnt10_1", "jnt17_1", "jnt17_2", "jnt18_1"}
LEGS = {"jnt22_1", "jnt22_2", "jnt23_1", "jnt24_1", "jnt5_1", "jnt5_2", "jnt6_1", "jnt7_1"}
TRUNK = {"jnt1_1", "jnt2_1", "jnt11_1", "jnt12_1", "jnt8_1", "jnt16_1"}


# ---------------------------------------------------------------------------------------------------------------------
# Shapes: (verts, faces) in world space


def ellipsoid(c, r, rot=None, rings=8, segs=12):
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
    last = (rings - 2) * segs
    for j in range(segs):
        f.append((top, j, (j + 1) % segs))
        f.append((bottom, last + (j + 1) % segs, last + j))
    return v, f


def tube(points, radii, segs=10, caps=True):
    """A tube through points (parallel-transported rings), each its radius; closed ends."""
    pts = [Vector(p) for p in points]
    v, f = [], []
    d0 = (pts[1] - pts[0]).normalized()
    side = d0.cross(Vector((0, 0, 1)))
    if side.length < 1e-4:
        side = d0.cross(Vector((1, 0, 0)))
    side.normalize()
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = (side - d * side.dot(d)).normalized()
        up = d.cross(side)
        for j in range(segs):
            a = 2 * math.pi * j / segs
            v.append(p + (side * math.cos(a) + up * math.sin(a)) * radii[i])
    for i in range(len(pts) - 1):
        for j in range(segs):
            a, b = i * segs + j, i * segs + (j + 1) % segs
            f.append((a, b, b + segs, a + segs))
    if caps:
        c0, c1 = len(v), len(v) + 1
        v += [pts[0], pts[-1]]
        last = (len(pts) - 1) * segs
        for j in range(segs):
            f.append((c0, (j + 1) % segs, j))
            f.append((c1, last + j, last + (j + 1) % segs))
    return v, f


def capsule(a, b, ra, rb, segs=12, steps=5):
    a, b = Vector(a), Vector(b)
    pts = [a.lerp(b, t / steps) for t in range(steps + 1)]
    rad = [ra + (rb - ra) * t / steps for t in range(steps + 1)]
    tv, tf = tube(pts, rad, segs, caps=False)
    ea = ellipsoid(a, (ra, ra, ra), rings=6, segs=segs)
    eb = ellipsoid(b, (rb, rb, rb), rings=6, segs=segs)
    return merge([(tv, tf), ea, eb])


def box(c, half, rot=None):
    rot = rot or Matrix.Identity(3)
    v = [Vector(c) + rot @ Vector((sx * half[0], sy * half[1], sz * half[2]))
         for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return v, f


def merge(parts):
    v, f = [], []
    for pv, pf in parts:
        base = len(v)
        v += [Vector(x) for x in pv]
        f += [tuple(base + i for i in face) for face in pf]
    return v, f


def shell(rings, closed=True, thick=0.06):
    """A surface through rings of points (each ring the same count), made two-sided with an inner copy `thick` in."""
    n, m = len(rings), len(rings[0])
    v, f = [], []
    for ring in rings:
        v += [Vector(p) for p in ring]
    span = m if closed else m - 1
    for i in range(n - 1):
        for j in range(span):
            a, b = i * m + j, i * m + (j + 1) % m
            f.append((a, b, b + m, a + m))
    # the inner side: each point pulled toward its ring's middle
    base = len(v)
    for ring in rings:
        mid = sum((Vector(p) for p in ring), Vector()) / m
        for p in ring:
            d = Vector(p) - mid
            d.z = 0
            v.append(Vector(p) - (d.normalized() * thick if d.length > 1e-6 else Vector()))
    for i in range(n - 1):
        for j in range(span):
            a, b = base + i * m + j, base + i * m + (j + 1) % m
            f.append((a, a + m, b + m, b))
    if not closed:  # close the two open edges
        for i in range(n - 1):
            for j in (0, m - 1):
                o, ii = i * m + j, base + i * m + j
                f.append((o, o + m, ii + m, ii) if j == 0 else (o, ii, ii + m, o + m))
    # the hem and the top: join outer to inner
    for i in (0, n - 1):
        for j in range(span):
            a, b = i * m + j, i * m + (j + 1) % m
            f.append((a, base + a, base + b, b) if i == 0 else (a, b, base + b, base + a))
    return v, f


# ---------------------------------------------------------------------------------------------------------------------
# The skeleton


def apply_proportions(arm):
    """Moves the bones named in proportions.json (and those below them) from Toan's places. The offsets applied are
    kept on the armature, so a rerun moves only the difference; the file starts from Opar's (wider hips), and Seda's
    empty proportions take those back out."""
    path = os.path.join(HERE, "proportions.json")
    moves = json.load(open(path))["move"] if os.path.exists(path) else {}
    done = json.loads(arm.get("proportions", "{}"))
    if done == moves:
        return
    for o in bpy.context.selected_objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    to_local = arm.matrix_world.inverted().to_3x3()
    for name in set(moves) | set(done):
        delta = Vector(moves.get(name, (0, 0, 0))) - Vector(done.get(name, (0, 0, 0)))
        bone = arm.data.edit_bones[name]
        for b in [bone] + list(bone.children_recursive):
            b.head += to_local @ delta
            b.tail += to_local @ delta
    bpy.ops.object.mode_set(mode="OBJECT")
    arm["proportions"] = json.dumps(moves)


def joints(arm):
    return {b.name: (arm.matrix_world @ b.matrix_local).to_translation() for b in arm.data.bones}


def segments(J):
    nxt = {"jnt1_1": "jnt2_1", "jnt2_1": "jnt11_1", "jnt11_1": "jnt12_1", "jnt8_1": "jnt9_1", "jnt9_1": "jnt9_2",
           "jnt9_2": "jnt10_1", "jnt16_1": "jnt17_1", "jnt17_1": "jnt17_2", "jnt17_2": "jnt18_1",
           "jnt22_1": "jnt22_2", "jnt22_2": "jnt23_1", "jnt23_1": "jnt24_1", "jnt5_1": "jnt5_2", "jnt5_2": "jnt6_1",
           "jnt6_1": "jnt7_1"}
    reach = {"jnt12_1": Vector((0, -0.4, 2.4)), "jnt10_1": Vector((2.4, 0, 0)), "jnt18_1": Vector((-2.4, 0, 0)),
             "jnt24_1": Vector((0, -2.0, 0)), "jnt7_1": Vector((0, -2.0, 0))}
    out = {}
    for name in DEFORM:
        a = J[name]
        out[name] = (a, J[nxt[name]] if name in nxt else a + reach[name])
    return out


def to_segment(p, a, b):
    ab = b - a
    t = 0.0 if ab.length_squared == 0 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (a + ab * t - p).length


def weigh(p, candidates, segs, keep=3, power=5):
    scored = sorted(((1.0 / max(to_segment(p, *segs[n]), 0.05) ** power, n) for n in candidates), reverse=True)[:keep]
    total = sum(s for s, _ in scored)
    out = [(n, s / total) for s, n in scored if s / total > 0.03]
    total = sum(w for _, w in out)
    return [(n, w / total) for n, w in out]


def body_candidates(p, J):
    names = set(TRUNK)
    head_z = J["jnt11_1"].z + 0.5
    if p.z > head_z and abs(p.x) < 2.0:
        return {"jnt12_1", "jnt11_1"} if p.z < head_z + 0.5 else {"jnt12_1"}
    if p.z < J["jnt11_1"].z - 0.4:
        names.discard("jnt12_1")
    if abs(p.x) > 1.2 and p.z > J["jnt2_1"].z + 1.2:
        names |= ARMS
    if p.z < J["jnt1_1"].z - 0.5:
        names |= LEGS
        if p.z < J["jnt1_1"].z - 2.0:
            names = set(LEGS) | {"jnt1_1"}
    if p.x > 0.3:
        names -= RIGHT
    elif p.x < -0.3:
        names -= LEFT
    if p.z < J["jnt1_1"].z - 0.5 and abs(p.x) <= 0.3:
        names -= ARMS
    return names


# ---------------------------------------------------------------------------------------------------------------------
# The body


def body_volumes(J):
    hip_z, chest_z, neck_z, head_z = J["jnt1_1"].z, J["jnt2_1"].z, J["jnt11_1"].z, J["jnt12_1"].z
    parts = [
        ellipsoid((0, 0.05, hip_z + 0.1), (1.55, 1.00, 1.10)),        # pelvis
        ellipsoid((0, 0.08, hip_z + 1.25), (1.48, 0.95, 1.35)),       # waist, no narrower than the hips
        ellipsoid((0, 0.12, chest_z + 1.45), (1.68, 0.98, 1.70)),     # chest: broad, flat at the front
        ellipsoid((0, 0.30, chest_z + 1.9), (1.45, 0.78, 1.20)),      # back
        capsule((0, 0.05, neck_z - 0.4), (0, -0.05, head_z - 0.2), 0.48, 0.44),  # neck
        ellipsoid((0, -0.05, head_z + 0.75), (1.00, 1.15, 1.35)),     # skull, narrow and long
        ellipsoid((0, -0.55, head_z + 0.05), (0.72, 0.70, 0.62)),     # jaw
        ellipsoid((0, -1.18, head_z + 0.95), (0.80, 0.22, 0.18)),     # brow
        ellipsoid((0, -1.25, head_z + 0.45), (0.15, 0.25, 0.36)),     # nose
    ]
    for s, sh, el, wr, hip, knee, ankle, toe in (
            (1, "jnt9_1", "jnt9_2", "jnt10_1", "jnt5_1", "jnt5_2", "jnt6_1", "jnt7_1"),
            (-1, "jnt17_1", "jnt17_2", "jnt18_1", "jnt22_1", "jnt22_2", "jnt23_1", "jnt24_1")):
        parts.append(ellipsoid((s * 1.55, 0.0, neck_z - 0.5), (0.85, 0.80, 0.70)))          # shoulder
        parts.append(capsule(J[sh] + Vector((s * 0.3, 0, 0)), J[el], 0.55, 0.46))          # upper arm
        parts.append(capsule(J[el], J[wr], 0.46, 0.36))                                    # forearm
        parts.append(ellipsoid(J[wr] + Vector((s * 0.95, -0.05, -0.05)), (0.85, 0.32, 0.45)))  # hand
        parts.append(capsule(J[wr] + Vector((s * 0.45, -0.35, 0.1)), J[wr] + Vector((s * 0.95, -0.65, 0.15)), 0.14, 0.11))  # thumb
        parts.append(capsule(J[hip] + Vector((0, 0, -0.2)), J[knee], 0.82, 0.58))          # thigh
        parts.append(capsule(J[knee], J[ankle] + Vector((0, 0, 0.2)), 0.58, 0.44))          # shin
        parts.append(capsule(J[ankle] + Vector((0, 0.35, 0.05)), J[toe] + Vector((0, -0.2, 0.0)), 0.50, 0.38))  # boot
    return parts


def fuse(parts, name):
    """The volumes made one skin: a voxel remesh, smoothed and decimated."""
    v, f = merge(parts)
    mesh = bpy.data.meshes.new(name + "_volumes")
    mesh.from_pydata([tuple(p) for p in v], [], f)
    obj = bpy.data.objects.new(name + "_volumes", mesh)
    bpy.context.scene.collection.objects.link(obj)
    rm = obj.modifiers.new("remesh", "REMESH")
    rm.mode, rm.voxel_size, rm.adaptivity = "VOXEL", 0.06, 0.0
    sm = obj.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.iterations, sm.lambda_factor, sm.lambda_border = 8, 0.6, 0.0
    sm.use_volume_preserve = True
    dg = bpy.context.evaluated_depsgraph_get()
    tris = sum(len(p.vertices) - 2 for p in obj.evaluated_get(dg).data.polygons)
    dec = obj.modifiers.new("decimate", "DECIMATE")
    dec.ratio = min(1.0, TRIANGLES / max(tris, 1))
    dg = bpy.context.evaluated_depsgraph_get()
    out = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    return out


def body_paint(p, n, J):
    """(colour, pattern, page) of a body vertex, by where it is."""
    hip_z, neck_z, head_z = J["jnt1_1"].z, J["jnt11_1"].z, J["jnt12_1"].z
    if p.z > neck_z + 0.3 and abs(p.x) < 2.0:
        for ex in (0.40, -0.40):  # the eyes, on the face's front
            d = (p - Vector((ex, -1.05, head_z + 0.62))).length
            if d < 0.14 and n.y < -0.4:
                return (PUPIL if d < 0.06 else EYE), PLAIN, 0
        if p.y < -0.95 and abs(p.z - (head_z + 0.86)) < 0.07 and 0.18 < abs(p.x) < 0.62:
            return BROW, PLAIN, 0
        if p.y < -0.9 and abs(p.z - (head_z - 0.12)) < 0.05 and abs(p.x) < 0.24:
            return LIPS, PLAIN, 0
        return (SKIN if p.y < 0.2 else SKIN_SHADE), PLAIN, 0
    wrist = max(abs(J["jnt10_1"].x), abs(J["jnt18_1"].x))
    if abs(p.x) > wrist - 0.15:
        return GLOVE, PLAIN, 1
    if abs(p.x) > wrist - 0.5 and p.z > neck_z - 1.6:
        return TRIM, METAL, 1  # the sleeve's cuff
    if p.z > hip_z - 0.4:
        # the coat; its front opens in a V from the belt to the collar, the shirt between silver edges
        t = max(0.0, min(1.0, (p.z - hip_z) / (neck_z - hip_z)))
        half = 0.16 + 0.38 * t
        if p.y < -0.3 and p.z < neck_z - 0.1 and abs(p.x) < half + 0.12:
            return (TRIM if abs(p.x) > half else SHIRT), (METAL if abs(p.x) > half else CLOTH), 1
        return COAT, CLOTH, 1
    knee_z = J["jnt5_2"].z
    if p.z < knee_z - 1.5:
        return (TRIM if abs(p.z - (knee_z - 1.6)) < 0.12 else LEATHER), PLAIN, 3  # boots and their cuffs
    return TROUSERS, CLOTH, 3


# ---------------------------------------------------------------------------------------------------------------------
# Gear: (verts, faces, colour, pattern, weights) with weights a set of bones or a function of the point


def gear(J, segs):
    hip_z, chest_z, neck_z, head_z = J["jnt1_1"].z, J["jnt2_1"].z, J["jnt11_1"].z, J["jnt12_1"].z
    knee_z = J["jnt5_2"].z
    out = []

    # The coat's skirt: from the waist to below the knees, flaring, its front open (angle 0 is the front, -Y).
    rows, cols = 7, 22
    top_z, hem_z = hip_z + 0.7, knee_z - 1.2
    rings = []
    for i in range(rows):
        t = i / (rows - 1)
        z = top_z + (hem_z - top_z) * t
        rx, ry = 1.62 + 0.95 * t, 1.18 + 0.85 * t
        gap = math.radians(14 + 26 * t)  # the opening widens toward the hem
        ring = []
        for j in range(cols):
            a = gap + (2 * math.pi - 2 * gap) * j / (cols - 1)
            ring.append(Vector((math.sin(a) * rx, -math.cos(a) * ry + 0.05, z)))
        rings.append(ring)
    sv, sf = shell(rings, closed=False, thick=0.07)

    def skirt_weights(p):
        t = max(0.0, min(1.0, (top_z - p.z) / (top_z - hem_z)))
        thigh = "jnt5_1" if p.x > 0 else "jnt22_1"
        side = min(1.0, abs(p.x) / 1.2)  # the back panel follows the hips more than the side panels
        w_thigh = t * 0.75 * side
        return [("jnt1_1", 1.0 - w_thigh), (thigh, w_thigh)] if w_thigh > 0.03 else [("jnt1_1", 1.0)]
    out.append((sv, sf, COAT, CLOTH, skirt_weights, "skirt"))

    # The hem's silver band, a little proud of the skirt
    band = [rings[-1], [Vector((p.x * 1.02, (p.y - 0.05) * 1.02 + 0.05, p.z + 0.22)) for p in rings[-1]]]
    bv, bf = shell([band[1], band[0]], closed=False, thick=0.08)
    out.append((bv, bf, TRIM, METAL, skirt_weights, "hem"))

    # The collar: high, open at the front
    crings = []
    for i, (z, r) in enumerate(((neck_z - 0.35, 0.95), (neck_z + 0.25, 0.92), (neck_z + 0.85, 1.08))):
        ring = []
        for j in range(16):
            a = math.radians(30) + math.radians(300) * j / 15
            ring.append(Vector((math.sin(a) * r, -math.cos(a) * r * 0.95 + 0.08, z)))
        crings.append(ring)
    cv, cf = shell(crings, closed=False, thick=0.08)
    out.append((cv, cf, COAT, CLOTH, {"jnt2_1", "jnt11_1"}, "collar"))

    # The belt and its buckle
    belt = []
    for z in (hip_z + 0.55, hip_z + 0.95):
        belt.append([Vector((math.sin(2 * math.pi * j / 24) * 1.66, -math.cos(2 * math.pi * j / 24) * 1.22 + 0.05, z))
                     for j in range(24)])
    lv, lf = shell(belt, closed=True, thick=0.08)
    out.append((lv, lf, LEATHER, PLAIN, {"jnt1_1"}, "belt"))
    out.append((*box((0, -1.24, hip_z + 0.75), (0.32, 0.06, 0.26)), BUCKLE, METAL, {"jnt1_1"}, "buckle"))

    # The pauldron on the left shoulder: two plates, the upper domed
    sh = Vector((1.75, 0.0, neck_z - 0.25))
    out.append((*ellipsoid(sh + Vector((0.15, 0, 0.15)), (1.05, 1.05, 0.55), rings=6, segs=12), STEEL, METAL,
                {"jnt8_1", "jnt9_1"}, "pauldron"))
    out.append((*ellipsoid(sh + Vector((0.55, 0, -0.35)), (0.85, 0.95, 0.35), rings=5, segs=12), STEEL, METAL,
                {"jnt9_1"}, "pauldron2"))

    # The hair: a cap over the skull, the fringe, two side locks and a long fall down the back
    head = lambda p: [("jnt12_1", 1.0)]
    out.append((*ellipsoid((0, 0.08, head_z + 0.95), (1.08, 1.18, 1.32), rings=8, segs=14), HAIR, HAIR_PAT, head, "cap"))
    for x in (-0.55, -0.2, 0.15, 0.5):  # the fringe: locks falling over the brow
        out.append((*tube([(x, -0.95, head_z + 1.9), (x * 1.1, -1.25, head_z + 1.35), (x * 1.15, -1.32, head_z + 0.95)],
                          [0.24, 0.16, 0.05], segs=6), HAIR, HAIR_PAT, head, "fringe"))
    for s in (1, -1):  # side locks framing the face
        out.append((*tube([(s * 0.95, -0.45, head_z + 1.2), (s * 1.08, -0.62, head_z + 0.2), (s * 1.0, -0.6, head_z - 0.9)],
                          [0.30, 0.22, 0.06], segs=6), HAIR, HAIR_PAT, head, "lock"))

    fall_top, fall_end = head_z + 0.9, chest_z + 0.2
    def fall_weights(p):
        t = max(0.0, min(1.0, (fall_top - p.z) / (fall_top - fall_end)))
        return [("jnt12_1", 1.0 - 0.8 * t), ("jnt2_1", 0.8 * t)] if t > 0.04 else [("jnt12_1", 1.0)]
    out.append((*tube([(0, 0.85, fall_top), (0, 1.25, head_z - 0.6), (0, 1.45, neck_z - 1.6), (0, 1.55, fall_end)],
                      [0.95, 0.85, 0.6, 0.15], segs=12), HAIR, HAIR_PAT, fall_weights, "fall"))
    return out


# ---------------------------------------------------------------------------------------------------------------------
# Paint


def paint_material(name, image):
    mat = bpy.data.materials.new(name)
    mat["texture"] = name
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    nodes, links = nt.nodes, nt.links
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    links.new(emit.outputs[0], out.inputs["Surface"])
    paint = nodes.new("ShaderNodeAttribute"); paint.attribute_name = "paint"
    pattern = nodes.new("ShaderNodeAttribute"); pattern.attribute_name = "pattern"
    coord = nodes.new("ShaderNodeTexCoord")
    # cloth: a fine weave; hair: streaks along the strands; metal: a soft sheen from above
    noise = nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 28.0
    links.new(coord.outputs["Object"], noise.inputs["Vector"])
    wave = nodes.new("ShaderNodeTexWave"); wave.wave_type = "BANDS"; wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 0.0
    wave.inputs["Distortion"].default_value = 4.0
    links.new(coord.outputs["Object"], wave.inputs["Vector"])
    streak = nodes.new("ShaderNodeTexNoise"); streak.inputs["Scale"].default_value = 9.0
    mapping = nodes.new("ShaderNodeMapping"); mapping.inputs["Scale"].default_value = (6.0, 6.0, 0.35)
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], streak.inputs["Vector"])
    geo = nodes.new("ShaderNodeNewGeometry")
    sep = nodes.new("ShaderNodeSeparateXYZ"); links.new(geo.outputs["Normal"], sep.inputs[0])

    def math_node(op, a, b):
        m = nodes.new("ShaderNodeMath"); m.operation = op
        for i, x in enumerate((a, b)):
            if isinstance(x, (int, float)):
                m.inputs[i].default_value = x
            else:
                links.new(x, m.inputs[i])
        return m.outputs[0]

    def is_pattern(k):  # 1 where pattern == k
        return math_node("COMPARE", pattern.outputs["Fac"], float(k))

    cloth = math_node("ADD", 0.9, math_node("MULTIPLY", noise.outputs["Fac"], 0.2))
    hair = math_node("ADD", 0.78, math_node("MULTIPLY", streak.outputs["Fac"], 0.42))
    metal = math_node("ADD", 0.85, math_node("MULTIPLY", sep.outputs["Z"], 0.25))
    factor = math_node("ADD", math_node("ADD", math_node("MULTIPLY", is_pattern(CLOTH), math_node("SUBTRACT", cloth, 1.0)),
                                        math_node("MULTIPLY", is_pattern(HAIR_PAT), math_node("SUBTRACT", hair, 1.0))),
                       math_node("ADD", 1.0, math_node("MULTIPLY", is_pattern(METAL), math_node("SUBTRACT", metal, 1.0))))
    ao = nodes.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = 0.6
    shade = math_node("ADD", 0.55, math_node("MULTIPLY", ao.outputs["AO"], 0.45))
    mix = nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    links.new(paint.outputs["Color"], mix.inputs[6])
    comb = nodes.new("ShaderNodeCombineXYZ")
    total = math_node("MULTIPLY", factor, shade)
    for k in ("X", "Y", "Z"):
        links.new(total, comb.inputs[k])
    links.new(comb.outputs[0], mix.inputs[7])
    links.new(mix.outputs[2], emit.inputs["Color"])
    tex = nodes.new("ShaderNodeTexImage"); tex.image = image
    nt.nodes.active = tex
    return mat


def show_material(mat, path):
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path, check_existing=False)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])


def previews(obj):
    """Front, side and back pictures of the baked model, for looking at without the game."""
    scene = bpy.context.scene
    os.makedirs(PREVIEWS, exist_ok=True)
    cam_data = bpy.data.cameras.new("preview")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 22
    cam = bpy.data.objects.new("preview", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    # Cycles on the CPU, so it renders on a machine with no GPU too
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 12
    world = scene.world or bpy.data.worlds.new("preview")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.55, 0.6, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.6
    sun_data = bpy.data.lights.new("preview_sun", "SUN")
    sun_data.energy = 2.5
    sun = bpy.data.objects.new("preview_sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    scene.collection.objects.link(sun)
    scene.render.resolution_x, scene.render.resolution_y = 480, 560
    reference = bpy.data.collections.get("Template reference")
    for name, angle in (("front", 0), ("side", 90), ("back", 180)):
        a = math.radians(angle)
        cam.location = (math.sin(a) * 40, -math.cos(a) * 40, 9.0)
        cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(PREVIEWS, "seda_" + name + ".png")
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(sun)


# ---------------------------------------------------------------------------------------------------------------------


def main():
    scene = bpy.context.scene
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    character = bpy.data.collections["Character"]
    reference = bpy.data.collections.get("Template reference")
    if reference:
        reference.hide_render = True
        for o in reference.objects:
            o.hide_render = True
    for obj in list(character.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj)
    apply_proportions(arm)
    J = joints(arm)
    segs = segments(J)

    body = fuse(body_volumes(J), "seda")
    verts, faces, mats, colour, pattern, weights = [], [], [], [], [], []
    for v in body.vertices:
        p, n = v.co.copy(), v.normal.copy()
        col, pat, page = body_paint(p, n, J)
        verts.append(p)
        colour.append(lin(col))
        pattern.append(float(pat))
        weights.append(weigh(p, body_candidates(p, J), segs))
    for poly in body.polygons:
        faces.append(tuple(poly.vertices))
        c = sum((body.vertices[i].co for i in poly.vertices), Vector()) / len(poly.vertices)
        mats.append(body_paint(c, poly.normal, J)[2])
    bpy.data.meshes.remove(body)

    page_of = {"cap": 0, "fringe": 0, "lock": 0, "fall": 0}
    for pv, pf, col, pat, bones, part in gear(J, segs):
        base = len(verts)
        for p in pv:
            verts.append(Vector(p))
            colour.append(lin(col))
            pattern.append(float(pat))
            weights.append(bones(p) if callable(bones) else weigh(p, bones, segs))
        faces += [tuple(base + i for i in f) for f in pf]
        mats += [page_of.get(part, 2)] * len(pf)

    mesh = bpy.data.meshes.new("skin")
    mesh.from_pydata([tuple(p) for p in verts], [], faces)
    mesh.validate()
    for poly, m in zip(mesh.polygons, mats):
        poly.material_index = m
    mesh.shade_smooth()
    attr = mesh.color_attributes.new("paint", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(colour):
        attr.data[i].color = (*c, 1.0)
    a = mesh.attributes.new("pattern", "FLOAT", "POINT")
    a.data.foreach_set("value", pattern)

    images, materials = [], []
    for name in PAGES:
        old = bpy.data.images.get("bake_" + name)
        if old:
            bpy.data.images.remove(old)
        img = bpy.data.images.new("bake_" + name, BAKE_SIZE, BAKE_SIZE, alpha=False)
        images.append(img)
        mat = paint_material(name, img)
        materials.append(mat)
        mesh.materials.append(mat)

    obj = bpy.data.objects.new("skin", mesh)
    character.objects.link(obj)
    obj.parent = arm
    for name in DEFORM:
        obj.vertex_groups.new(name=name)
    for i, w in enumerate(weights):
        for name, value in w:
            obj.vertex_groups[name].add([i], value, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

    view = bpy.context.view_layer
    for o in view.objects:
        o.select_set(False)
    view.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for i in range(len(PAGES)):
        bpy.ops.mesh.select_all(action="DESELECT")
        obj.active_material_index = i
        bpy.ops.object.material_slot_select()
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.008, area_weight=0.0,
                                 scale_to_bounds=False)
        bpy.ops.uv.pack_islands(margin=0.005, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
    os.makedirs(TEXTURES, exist_ok=True)
    for name, img, mat in zip(PAGES, images, materials):
        img.scale(SIZE, SIZE)
        path = os.path.join(TEXTURES, name + ".png")
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        show_material(mat, path)
    bpy.ops.wm.save_mainfile()
    previews(obj)
    counts = [0] * len(PAGES)
    for m in mats:
        counts[m] += 1
    print("SEDA vertices", len(mesh.vertices), "triangles", sum(len(p.vertices) - 2 for p in mesh.polygons),
          "faces by page", dict(zip(PAGES, counts)))


# ---------------------------------------------------------------------------------------------------------------------
# His own model: the retail pack's glTF, fitted onto Toan's skeleton

NEXT = {"jnt1_1": "jnt2_1", "jnt2_1": "jnt11_1", "jnt11_1": "jnt12_1", "jnt8_1": "jnt9_1", "jnt9_1": "jnt9_2",
        "jnt9_2": "jnt10_1", "jnt16_1": "jnt17_1", "jnt17_1": "jnt17_2", "jnt17_2": "jnt18_1",
        "jnt22_1": "jnt22_2", "jnt22_2": "jnt23_1", "jnt23_1": "jnt24_1", "jnt5_1": "jnt5_2", "jnt5_2": "jnt6_1",
        "jnt6_1": "jnt7_1"}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv[argv.index("--retail") + 1] if "--retail" in argv else None


def arc(a, b):
    """The shortest turn taking direction a onto direction b."""
    a, b = a.normalized(), b.normalized()
    return a.rotation_difference(b).to_matrix()


def import_retail(path):
    """His glTF imported beside the file's own skeleton: (his armature, his meshes)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next((o for o in new if o.type == "ARMATURE"), None)
    # his meshes hang on his armature; the importer's own helpers (a bone-shape Icosphere) don't
    meshes = [o for o in new if o.type == "MESH" and o.parent is arm]
    return arm, meshes, new


def chain_parent(obj, names):
    """The chain bone a rigid mesh hangs on: its parent bone, or the nearest ancestor of it named in `names`."""
    arm = obj.parent
    bone = arm.data.bones.get(obj.parent_bone) if arm and obj.parent_bone else None
    while bone is not None and bone.name not in names:
        bone = bone.parent
    return bone.name if bone else None


def retail_model(path, J, segs):
    """His mesh on Toan's skeleton: verts, faces, per face (page, picture, UVs of its corners), weights."""
    arm, meshes, new = import_retail(path)
    if arm is None or not meshes:
        raise RuntimeError("no armature or mesh in " + path)
    S = {b.name: (arm.matrix_world @ b.matrix_local).to_translation() for b in arm.data.bones}
    matched = [n for n in DEFORM if n in S]
    named = len(matched) >= 15
    # his height to Toan's: by the hips when they are named, else by the whole figure
    zs = [(o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices]
    floor, top = min(zs), max(zs)
    if named:
        scale = (J["jnt1_1"].z) / max(S["jnt1_1"].z - floor, 1e-3)
    else:
        scale = (J["jnt12_1"].z + 2.2) / max(top - floor, 1e-3)
    lift = Vector((0, 0, -floor))

    def his(p):  # his point, scaled to Toan's size, his feet on the floor
        return (p + lift) * scale

    # each chain bone's fit: his joint onto Toan's, his bone's direction onto Toan's
    fit = {}
    if named:
        for n in matched:
            a = his(S[n])
            if n in NEXT and NEXT[n] in S:
                d_his, d_toan = his(S[NEXT[n]]) - a, J[NEXT[n]] - J[n]
            else:
                d_his = d_toan = None
            R = arc(d_his, d_toan) if d_his is not None and d_his.length > 1e-4 and d_toan.length > 1e-4 else None
            fit[n] = (a, R)
        for n in matched:  # a chain's end bone turns as its parent does
            if fit[n][1] is None:
                parent = next((p for p, c in NEXT.items() if c == n and p in fit), None)
                fit[n] = (fit[n][0], fit[parent][1] if parent and fit[parent][1] is not None else Matrix.Identity(3))

    def place(p, w):
        q = his(p)
        if not named or not w:
            return q
        out = Vector()
        for n, wt in w:
            a, R = fit[n]
            out += (J[n] + R @ (q - a)) * wt
        return out

    verts, faces, face_info, weights = [], [], [], []
    for obj in meshes:
        mesh = obj.data
        groups = {g.index: g.name for g in obj.vertex_groups}
        rigid = None if groups else chain_parent(obj, set(matched))
        uv = mesh.uv_layers.active
        base = len(verts)
        for v in mesh.vertices:
            p = obj.matrix_world @ v.co
            if named:
                w = [(groups[g.group], g.weight) for g in v.groups if g.group in groups and groups[g.group] in fit and g.weight > 0]
                if not w and rigid:
                    w = [(rigid, 1.0)]
                if not w:  # a vertex on a bone Toan has no match for: the nearest matched joint
                    q = his(p)
                    w = [(min(fit, key=lambda n: (his(S[n]) - q).length), 1.0)]
                total = sum(x for _, x in w)
                w = sorted(((n, x / total) for n, x in w), key=lambda t: -t[1])[:3]
                total = sum(x for _, x in w)
                w = [(n, x / total) for n, x in w]
                verts.append(place(p, w))
                weights.append(w)
            else:
                q = his(p)
                verts.append(q)
                weights.append(None)  # weighed by distance below
        for poly in mesh.polygons:
            faces.append(tuple(base + i for i in poly.vertices))
            mat = mesh.materials[poly.material_index] if mesh.materials else None
            image = None
            if mat and mat.node_tree:
                image = next((n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image), None)
            uvs = [tuple(uv.data[li].uv) for li in poly.loop_indices] if uv else [(0.0, 0.0)] * len(poly.vertices)
            face_info.append((image, uvs))
    for i, w in enumerate(weights):
        if w is None:
            weights[i] = weigh(verts[i], body_candidates(verts[i], J), segs)
    for o in new:
        bpy.data.objects.remove(o)
    print("SEDA retail:", "fitted by joint names" if named else "scaled and weighted by distance",
          "matched joints", len(matched), "scale %.3f" % scale)
    return verts, faces, face_info, weights


def retail_page(c, J):
    """Which of the four pictures a face is baked into, by height: head, torso and arms, waist, legs."""
    if c.z > J["jnt11_1"].z + 0.3 and abs(c.x) < 2.2:
        return 0
    if c.z < J["jnt1_1"].z - 1.0:
        return 3
    if c.z < J["jnt1_1"].z + 1.0 and abs(c.x) < 2.6:
        return 2
    return 1


def main_retail(path):
    scene = bpy.context.scene
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name == "skeleton")
    character = bpy.data.collections["Character"]
    reference = bpy.data.collections.get("Template reference")
    if reference:
        for o in reference.objects:
            o.hide_render = True
    for obj in list(character.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj)
    apply_proportions(arm)
    J = joints(arm)
    segs = segments(J)
    verts, faces, face_info, weights = retail_model(path, J, segs)

    mesh = bpy.data.meshes.new("skin")
    mesh.from_pydata([tuple(p) for p in verts], [], faces)
    pages = [retail_page(sum((verts[i] for i in f), Vector()) / len(f), J) for f in faces]
    # one material per (page, source picture): it shows the picture through his UVs and bakes into the page
    targets = []
    for name in PAGES:
        old = bpy.data.images.get("bake_" + name)
        if old:
            bpy.data.images.remove(old)
        targets.append(bpy.data.images.new("bake_" + name, BAKE_SIZE, BAKE_SIZE, alpha=False))
    combos, index = {}, []
    for page, (image, _) in zip(pages, face_info):
        key = (page, image.name if image else "")
        if key not in combos:
            mat = bpy.data.materials.new("bake_%d_%s" % key)
            mat.use_nodes = True
            nt = mat.node_tree
            nt.nodes.clear()
            out = nt.nodes.new("ShaderNodeOutputMaterial")
            emit = nt.nodes.new("ShaderNodeEmission")
            nt.links.new(emit.outputs[0], out.inputs["Surface"])
            if image:
                src = nt.nodes.new("ShaderNodeTexImage"); src.image = image; src.interpolation = "Closest"
                uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "source"
                nt.links.new(uvn.outputs[0], src.inputs["Vector"])
                nt.links.new(src.outputs["Color"], emit.inputs["Color"])
            else:
                emit.inputs["Color"].default_value = (0.5, 0.5, 0.5, 1)
            tgt = nt.nodes.new("ShaderNodeTexImage"); tgt.image = targets[page]
            nt.nodes.active = tgt
            combos[key] = len(mesh.materials)
            mesh.materials.append(mat)
        index.append(combos[key])
    source = mesh.uv_layers.new(name="source")
    for poly, (_, uvs) in zip(mesh.polygons, face_info):
        for li, uvv in zip(poly.loop_indices, uvs):
            source.data[li].uv = uvv
    paged = mesh.uv_layers.new(name="UVMap")
    for poly, m in zip(mesh.polygons, index):
        poly.material_index = m
    mesh.validate()
    mesh.shade_smooth()

    obj = bpy.data.objects.new("skin", mesh)
    character.objects.link(obj)
    obj.parent = arm
    for name in DEFORM:
        obj.vertex_groups.new(name=name)
    for i, w in enumerate(weights):
        for name, value in w:
            obj.vertex_groups[name].add([i], value, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

    # the pages' UVs: each page's faces unwrapped into its own picture
    mesh.uv_layers.active = paged
    view = bpy.context.view_layer
    for o in list(bpy.context.selected_objects):
        o.select_set(False)
    view.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for page in range(len(PAGES)):
        bpy.ops.mesh.select_all(action="DESELECT")
        for key, slot in combos.items():
            if key[0] == page:
                obj.active_material_index = slot
                bpy.ops.object.material_slot_select()
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.008, area_weight=0.0, scale_to_bounds=False)
        bpy.ops.uv.pack_islands(margin=0.005, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
    os.makedirs(TEXTURES, exist_ok=True)
    final = []
    for name, img in zip(PAGES, targets):
        img.scale(SIZE, SIZE)
        path_png = os.path.join(TEXTURES, name + ".png")
        img.filepath_raw = path_png
        img.file_format = "PNG"
        img.save()
        mat = bpy.data.materials.new(name)
        mat["texture"] = name
        mat.use_nodes = True
        show_material(mat, path_png)
        final.append(mat)
    # the four page materials in place of the bake's, his own UVs dropped
    page_of_slot = {slot: key[0] for key, slot in combos.items()}
    slots = [page_of_slot[p.material_index] for p in mesh.polygons]
    mesh.materials.clear()
    for mat in final:
        mesh.materials.append(mat)
    for poly, page in zip(mesh.polygons, slots):
        poly.material_index = page
    mesh.uv_layers.remove(mesh.uv_layers["source"])
    bpy.ops.wm.save_mainfile()
    previews(obj)
    counts = [slots.count(i) for i in range(len(PAGES))]
    print("SEDA vertices", len(mesh.vertices), "triangles", sum(len(p.vertices) - 2 for p in mesh.polygons),
          "faces by page", dict(zip(PAGES, counts)))


if args():
    main_retail(args())
else:
    main()
