"""Blender: Opar's model, paint and weights in opar.blend, from the concept (concept.jpg).

    blender -b art/opar/opar.blend --python art/opar/make_opar.py

Replaces the "Character" collection's body (`skin`) and writes its four pictures to art/opar/textures: c07d02 (head),
c07d03 (torso and arms), c07d05 (legs and feet), c07d04 (gear). Then build the pack with
tools/chr/build_character.py build.

- Body, one skin: volumes (round belly, soft pecs, a wide flat head with jowls, heavy brows and eyelids, thick
  deltoids, biceps and Popeye forearms, big four-fingered hands with pads, heavy thighs and calves, long four-toed
  webbed feet) fused by a voxel remesh, smoothed (Laplacian, volume kept), then carved along its normals (carve():
  three soft belly folds arching up at the sides, a crease under each pec, three nubs, the nostrils), smoothed
  lightly and decimated to TRIANGLES. Nothing is layered on the belly.
- Gear laid on the skin (rays find its surface): a thin arched upper lip and a fat lower lip (the skin under them
  painted pink), yellow eyes in the lids, quill-cluster gill frills, pauldrons of a riveted iron dome over two curved
  plates with a straw fringe (moss on the left, spikes on the right), round-edged straps (chest strap with rings,
  belt with a buckle frame), a green sash from the left shoulder, a pouch, a two-lobed gourd on a cord, a ragged
  green-over-purple loincloth, a leather bracer with straps on the right forearm, and cloth wound round the left
  forearm and left shin: two thin strips spiralling opposite ways (spiral_wrap), crossing, with a loose tail.
- Paint, baked by Cycles at 1024 and scaled to the pack's 256: each part's colour; on the hide, dense spots of
  varied size with lighter rims and speckles; the tan front (worked out per pixel from the skin's position and
  facing, FRONT_ZONES) lighter at its middle; the lips' pink on the skin; leather grain, iron with lit tops and
  scratches, cloth weave darkening to the hem, rope twist, straw streaks, moss patches; then the shade of its own
  creases (ambient occlusion), a light from above and a painter's colour variation.
- Weights: to the skeleton's 20 chain joints, by distance to each bone, kept to its side of the body and its region,
  at most 3 a vertex. Gear follows the bone it is worn on.
Coordinates are Blender's: Z up, the front is -Y, the character's left is +X.
"""

import json
import math
import os

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(bpy.data.filepath)
TEXTURES = os.path.join(HERE, "textures")
PACK = "c07d"
HEAD, TORSO, GEAR, LEGS_TEX = PACK + "02", PACK + "03", PACK + "04", PACK + "05"
PAGES = (HEAD, TORSO, GEAR, LEGS_TEX)
BAKE_SIZE, SIZE = 1024, 256
TRIANGLES = 5400  # the fused body after decimation

# Colours as they look on screen (sRGB); lin() gives the bake its linear values. The hide is a shade lighter than the
# concept's blue-black: the dungeon's light is dim.
SKIN = (0.21, 0.25, 0.35)
SPOT = (0.05, 0.06, 0.10)
RIM = (0.33, 0.40, 0.55)
BELLY = (0.74, 0.56, 0.40)
BELLY_LIGHT = (0.84, 0.66, 0.48)
LIPS = (0.66, 0.36, 0.52)
LIPS_LOWER = (0.74, 0.43, 0.59)
EYE = (0.95, 0.80, 0.36)
PUPIL = (0.03, 0.03, 0.04)
GILL = (0.36, 0.30, 0.46)
IRON = (0.36, 0.37, 0.40)
STRAW = (0.78, 0.65, 0.36)
MOSS = (0.36, 0.50, 0.20)
LEATHER = (0.48, 0.30, 0.16)
LEATHER_DARK = (0.36, 0.22, 0.12)
ROPE = (0.66, 0.50, 0.30)
WRAP_CLOTH = (0.50, 0.37, 0.25)
GOURD = (0.32, 0.46, 0.45)
GREEN = (0.22, 0.42, 0.30)
PURPLE = (0.44, 0.26, 0.48)

# Gear patterns (the `pattern` attribute)
PLAIN, LEATHERY, IRONY, CLOTH, ROPY, STRAWY, MOSSY = range(7)


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


def tube(points, radii, segs=8, caps=True):
    """A tube through points (parallel-transported rings), each its radius; closed ends."""
    pts = [Vector(p) for p in points]
    n = len(pts)
    tangents = []
    for i in range(n):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        tangents.append((b - a).normalized())
    x = tangents[0].orthogonal().normalized()
    v, f = [], []
    for i in range(n):
        t = tangents[i]
        x = (x - t * x.dot(t)).normalized()
        y = t.cross(x)
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            v.append(pts[i] + (x * math.cos(ph) + y * math.sin(ph)) * max(radii[i], 1e-3))
    for i in range(n - 1):
        for j in range(segs):
            a, b = i * segs + j, i * segs + (j + 1) % segs
            f.append((a, b, b + segs, a + segs))
    if caps:
        s, e = len(v), len(v) + 1
        v += [pts[0] - tangents[0] * radii[0] * 0.7, pts[-1] + tangents[-1] * radii[-1] * 0.7]
        last = (n - 1) * segs
        for j in range(segs):
            f.append((s, (j + 1) % segs, j))
            f.append((e, last + j, last + (j + 1) % segs))
    return v, f


def capsule(a, b, ra, rb, segs=10, steps=4):
    a, b = Vector(a), Vector(b)
    return tube([a.lerp(b, k / steps) for k in range(steps + 1)], [ra + (rb - ra) * k / steps for k in range(steps + 1)],
                segs)


def cone(a, b, r, segs=5):
    return tube([Vector(a), Vector(a).lerp(Vector(b), 0.5), Vector(b)], [r, r * 0.55, 0.01], segs)


def ring(center, axis, radius, thick, segs=16, sides=6):
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


def box(c, half, rot=None):
    rot = rot or Matrix.Identity(3)
    v = [Vector(c) + rot @ Vector((sx * half[0], sy * half[1], sz * half[2]))
         for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return v, f


def band(points, normals, width, thick, closed=False):
    """A strap along points lying on a surface (normals outward): width across, thick outward."""
    v, f = [], []
    n = len(points)
    for i in range(n):
        p, nr = points[i], normals[i]
        nxt = points[(i + 1) % n] if (closed or i + 1 < n) else p
        prv = points[i - 1] if (closed or i > 0) else p
        t = (nxt - prv).normalized()
        s = t.cross(nr).normalized() * (width / 2)
        o = nr * thick
        v += [p + s, p - s, p - s + o, p + s + o]
    segs = n if closed else n - 1
    for i in range(segs):
        a, b = 4 * i, 4 * ((i + 1) % n)
        for k in range(4):
            f.append((a + k, a + (k + 1) % 4, b + (k + 1) % 4, b + k))
    if not closed:
        f.append((0, 1, 2, 3))
        e = 4 * (n - 1)
        f.append((e + 3, e + 2, e + 1, e))
    return v, f


def band_round(points, normals, width, thick, closed=False, thin=False):
    """A strap along points on a surface (normals outward) with rounded edges: a six-point profile, width across
    (four for thin cloth)."""
    prof = ([(-0.5, 0.0), (-0.42, 1.0), (0.42, 1.0), (0.5, 0.0)] if thin else
            [(-0.5, 0.0), (-0.47, 0.62), (-0.32, 1.0), (0.32, 1.0), (0.47, 0.62), (0.5, 0.0)])
    v, f = [], []
    n = len(points)
    k = len(prof)
    for i in range(n):
        p, nr = points[i], normals[i]
        nxt = points[(i + 1) % n] if (closed or i + 1 < n) else p
        prv = points[i - 1] if (closed or i > 0) else p
        t = (nxt - prv).normalized()
        side = t.cross(nr).normalized()
        for a, b in prof:
            v.append(p + side * (a * width) + nr * (b * thick))
    segs = n if closed else n - 1
    for i in range(segs):
        a0, b0 = k * i, k * ((i + 1) % n)
        for j in range(k):
            j1 = (j + 1) % k
            f.append((a0 + j, a0 + j1, b0 + j1, b0 + j))
    if not closed:
        f.append(tuple(range(k))[::-1])
        e = k * (n - 1)
        f.append(tuple(e + j for j in range(k)))
    return v, f


def surface_ring(S, A, B, t, reach, samples=16, out=0.03):
    """Points round a limb (axis A to B, at fraction t) on the body's surface, with their normals."""
    axis = (B - A).normalized()
    x = axis.orthogonal().normalized()
    y = axis.cross(x)
    c = A.lerp(B, t)
    pts, nrm = [], []
    for i in range(samples):
        a = 2 * math.pi * i / samples
        d = x * math.cos(a) + y * math.sin(a)
        hit, n = S.around(c, d, reach)
        pts.append(hit + n * out)
        nrm.append(n)
    return pts, nrm


def spiral_wrap(S, A, B, t0, t1, turns, width, reach, thick=0.03, direction=1, lift=0.0):
    """A cloth strip wound round a limb from t0 to t1: each turn laid a little over the one before, its loose end
    hanging. (verts, faces) for the strip and the tail."""
    axis = (B - A).normalized()
    x = axis.orthogonal().normalized()
    y = axis.cross(x)
    per_turn = 13
    n = int(turns * per_turn) + 1
    pts, nrm = [], []
    for k in range(n):
        u = k / (n - 1)
        a = 2 * math.pi * turns * u * direction
        d = x * math.cos(a) + y * math.sin(a)
        c = A.lerp(B, t0 + (t1 - t0) * u)
        hit, nn = S.around(c, d, reach)
        pts.append(hit + nn * (0.025 + lift + 0.006 * u * turns))
        nrm.append(nn)
    strip = band_round(pts, nrm, width, thick, thin=True)
    end, en = pts[-1], nrm[-1]
    down = Vector((0, 0, -1))
    tail = [end + en * 0.02 + down * 0.22 * k + en * 0.05 * k for k in range(5)]
    tail_n = [(en + Vector((0, 0, 0.1))).normalized()] * 5
    tv, tf = band_round(tail, tail_n, width * 0.8, thick, thin=True)
    base = len(strip[0])
    return strip[0] + tv, strip[1] + [tuple(base + i for i in face) for face in tf]


def flap(top, bottom, thick, teeth, rows=4, outward=Vector((0, -1, 0))):
    """A cloth flap from a row of top points to a row of bottom points (as many), its bottom edge torn."""
    cols = len(top)
    v, f = [], []
    for r in range(rows + 1):
        t = r / rows
        for c in range(cols):
            p = top[c].lerp(bottom[c], t)
            if r == rows and teeth:
                p = p + Vector((0, 0, teeth * (0.0 if c % 2 else -1.0) + teeth * 0.3 * math.sin(c * 2.3)))
            v.append(p)
    base = len(v)
    v += [p + outward * thick for p in v[:base]]
    for r in range(rows):
        for c in range(cols - 1):
            a, b = r * cols + c, r * cols + c + 1
            q = (a, b, b + cols, a + cols)
            f.append(q)
            f.append(tuple(base + k for k in q[::-1]))
    for r in range(rows):
        for c in (0, cols - 1):
            a, b = r * cols + c, (r + 1) * cols + c
            f.append((a, b, base + b, base + a))
    for c in range(cols - 1):
        for r in (0, rows):
            a, b = r * cols + c, r * cols + c + 1
            f.append((a, base + a, base + b, b))
    return v, f


# ---------------------------------------------------------------------------------------------------------------------
# The skeleton


def apply_proportions(arm):
    """Moves the bones named in proportions.json (and the bones below them) to his own proportions. The offsets
    already applied are kept on the armature, so a rerun moves only the difference."""
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
    """Each deforming bone as a segment: to the next joint down its chain, or a reach past the chain's end."""
    nxt = {"jnt1_1": "jnt2_1", "jnt2_1": "jnt11_1", "jnt11_1": "jnt12_1", "jnt8_1": "jnt9_1", "jnt9_1": "jnt9_2",
           "jnt9_2": "jnt10_1", "jnt16_1": "jnt17_1", "jnt17_1": "jnt17_2", "jnt17_2": "jnt18_1",
           "jnt22_1": "jnt22_2", "jnt22_2": "jnt23_1", "jnt23_1": "jnt24_1", "jnt5_1": "jnt5_2", "jnt5_2": "jnt6_1",
           "jnt6_1": "jnt7_1"}
    reach = {"jnt12_1": Vector((0, -0.4, 2.4)), "jnt10_1": Vector((2.6, 0, 0)), "jnt18_1": Vector((-2.6, 0, 0)),
             "jnt24_1": Vector((0, -2.2, 0)), "jnt7_1": Vector((0, -2.2, 0))}
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
    """The bones a body vertex may follow: its side's limbs, by region."""
    names = set(TRUNK)
    head_z = J["jnt11_1"].z + 0.5
    if p.z > head_z and abs(p.x) < 3.2:
        return {"jnt12_1", "jnt11_1"} if p.z < head_z + 0.6 else {"jnt12_1"}
    if p.z < J["jnt11_1"].z - 0.4:
        names.discard("jnt12_1")
    if abs(p.x) > 1.3 and p.z > J["jnt2_1"].z + 1.2:
        names |= ARMS
    if p.z < J["jnt1_1"].z - 0.6:
        names |= LEGS
        if p.z < J["jnt1_1"].z - 2.0:
            names = set(LEGS) | {"jnt1_1"}
    if p.x > 0.4:
        names -= RIGHT
    elif p.x < -0.4:
        names -= LEFT
    if p.z < J["jnt1_1"].z - 0.6 and abs(p.x) <= 0.4:
        names -= ARMS
    return names


# ---------------------------------------------------------------------------------------------------------------------
# The body


HEADS = []  # the head's volumes (centre, radii), for laying the lips and eyes on its front
LIP_CURVES = []  # [(points, radii)] of the lips, for painting them
EYES = []  # the eyeballs' centres


def head_front(x, z):
    """The y of the head's front (the most forward of its volumes) at x, z."""
    best = None
    for c, r in HEADS:
        q = 1 - ((x - c[0]) / r[0]) ** 2 - ((z - c[2]) / r[2]) ** 2
        if q > 0:
            y = c[1] - r[1] * math.sqrt(q)
            best = y if best is None else min(best, y)
    return best if best is not None else -2.0


def fist(palm, grip, axis, s):
    """The staff hand's fingers closed round the staff: its line runs from `grip` (the pack's `weapon` frame) along
    `axis`, under the knuckles. Each finger leaves its knuckle, curls down and back round the line and ends against
    the palm; the thumb wraps the other way over them. Without this he holds it in an open, flat hand."""
    out = []

    def around(p, turn):
        v = p - grip
        c = grip + axis * v.dot(axis)
        return c, p - c

    def curl(base, sweep, steps, radius):
        c, r = around(base, 0)
        r = r.normalized() * max(r.length, radius)
        # the way round that takes the finger down first (under the staff), as a hand closes
        down = None
        for sign in (1, -1):
            q = Matrix.Rotation(math.radians(30 * sign), 3, axis) @ r
            if down is None or (c + q).z < down[1]:
                down = (sign, (c + q).z)
        pts = [c + Matrix.Rotation(math.radians(sweep * i / steps * down[0]), 3, axis) @ r for i in range(steps + 1)]
        return pts

    for k, dy in enumerate((-0.62, -0.2, 0.2, 0.6)):
        base = palm + Vector((s * 0.75, dy * 1.15, 0))
        if k == 0:  # the thumb: from the palm's side, over the fingers the other way
            pts = curl(base + Vector((s * -0.2, 0.0, 0.25)), -150, 4, 0.62)
            radii = [0.3, 0.28, 0.27, 0.26, 0.25]
        else:
            pts = curl(base, 250, 6, 0.58)
            radii = [0.28, 0.27, 0.26, 0.26, 0.25, 0.25, 0.24]
        out.append(tube(pts, radii, segs=10))
        tip = pts[-1] + (pts[-1] - pts[-2]).normalized() * 0.1
        out.append(ellipsoid(tip, (0.3, 0.3, 0.3), rings=6, segs=10))
    return out


def body_volumes(J):
    hips, neck, head = J["jnt1_1"], J["jnt11_1"], J["jnt12_1"]
    hz = head.z
    P = []
    P.append(ellipsoid((0, -0.55, hips.z + 1.2), (3.05, 2.85, 2.9), rings=18, segs=28))  # belly
    P.append(ellipsoid((0, -0.2, neck.z - 1.2), (2.5, 2.1, 1.7), rings=12, segs=20))      # chest
    for s in (-1, 1):
        P.append(ellipsoid((s * 1.0, -1.7, neck.z - 1.6), (1.15, 0.8, 0.85), rings=10, segs=14))  # pecs
    HEADS[:] = [((0, -0.45, hz + 0.3), (2.95, 2.45, 1.55)), ((0, -0.85, hz - 0.55), (2.9, 2.25, 1.05))]
    for c, r in HEADS:
        P.append(ellipsoid(c, r, rings=16, segs=26))
    for s in (-1, 1):
        P.append(ellipsoid((s * 1.3, -1.7, hz + 1.45), (0.95, 0.75, 0.45), rings=8, segs=12))  # brows
    # lips: a curved upper lip and a fatter, pouting lower one, part of the skin
    LIP_CURVES.clear()
    for z0, drop, r0, r1, pout in ((hz - 0.14, 0.32, 0.14, 0.26, 0.0), (hz - 0.58, 0.24, 0.18, 0.36, 0.1)):
        pts, radii = [], []
        for i in range(25):
            x = -2.35 + 4.7 * i / 24
            k = (x / 2.35) ** 2
            z = z0 - drop * k
            r = r0 + (r1 - r0) * (1 - k)
            pts.append(Vector((x, head_front(x, z) - r * 0.25 - pout * (1 - k), z)))
            radii.append(r)
        LIP_CURVES.append((pts, radii))
    # eyelids over the eyeballs, part of the skin
    EYES.clear()
    for s in (-1, 1):
        x, z = s * 1.32, hz + 1.05
        eye = Vector((x, head_front(x, z) + 0.22, z))
        EYES.append(eye)
        lid = Matrix.Rotation(math.radians(-14), 3, "X")
        P.append(ellipsoid(eye + Vector((0, 0.02, 0.4)), (0.7, 0.6, 0.34), rot=lid, rings=8, segs=12))
    for s, (sh, el, wr) in ((1, ("jnt9_1", "jnt9_2", "jnt10_1")), (-1, ("jnt17_1", "jnt17_2", "jnt18_1"))):
        A, E, W = J[sh], J[el], J[wr]
        P.append(ellipsoid(A + Vector((s * 0.8, 0, 0.15)), (1.2, 1.1, 1.05)))              # deltoid
        P.append(capsule(A, E, 0.9, 0.78, segs=12))
        P.append(ellipsoid(A.lerp(E, 0.5) + Vector((0, -0.2, 0.22)), (0.85, 0.72, 0.78)))  # biceps
        P.append(capsule(E, W, 0.8, 0.55, segs=12))
        P.append(ellipsoid(E.lerp(W, 0.35), (1.0, 0.85, 0.85)))                           # forearm
        palm = W + Vector((s * 1.05, 0, -0.05))
        P.append(ellipsoid(palm, (1.1, 0.9, 0.48)))
        if s < 0 and "weapon" in J and "dcol" in J:
            P.extend(fist(palm, J["weapon"], (J["dcol"] - J["weapon"]).normalized(), s))
            continue
        for k, dy in enumerate((-0.62, -0.2, 0.2, 0.6)):
            base = palm + Vector((s * 0.75, dy * 1.15, 0))
            if k == 0:  # the thumb, turned forward
                mid = base + Vector((s * 0.35, -0.55, -0.05))
                tip = mid + Vector((s * 0.35, -0.45, -0.1))
            else:
                mid = base + Vector((s * 0.75, dy * 0.25, -0.1))
                tip = mid + Vector((s * 0.65, dy * 0.2, -0.25))
            P.append(tube([base, mid, tip], [0.28, 0.26, 0.24], segs=10))
            P.append(ellipsoid(tip + (tip - mid).normalized() * 0.14, (0.36, 0.33, 0.26), rings=6, segs=10))
    for s, (hip, knee, ankle) in ((1, ("jnt5_1", "jnt5_2", "jnt6_1")), (-1, ("jnt22_1", "jnt22_2", "jnt23_1"))):
        H, K, A = J[hip], J[knee], J[ankle]
        # the hips are set wide (proportions.json), the thighs kept off the middle: a gap between the legs below
        # the belly
        top = H + Vector((s * 0.25, 0, -0.2))
        P.append(capsule(top, K, 1.55, 1.1, segs=14))
        P.append(ellipsoid(top.lerp(K, 0.3) + Vector((s * 0.1, 0, 0)), (1.45, 1.65, 2.1), rings=10, segs=14))  # thigh
        P.append(ellipsoid(K.lerp(A, 0.32) + Vector((0, 0.3, 0)), (0.98, 1.0, 1.35)))     # calf
        P.append(capsule(K, A + Vector((0, 0, 0.35)), 1.05, 0.58, segs=12))
        # the foot: a thick ankle over a round heel, an instep sloping down to the ball, turned out a little; toes
        # fanned wide from the ball, each arched up at the knuckle and down to a round pad on the floor, webbed
        # between their bases only
        out = Matrix.Rotation(math.radians(20 * s), 3, "Z")
        P.append(ellipsoid(A + Vector((s * 0.05, -0.1, -0.05)), (0.82, 0.88, 0.72)))     # ankle
        P.append(ellipsoid(Vector((A.x + s * 0.05, A.y + 0.3, 0.44)), (0.74, 0.7, 0.44)))  # heel
        ball = Vector((A.x + s * 0.35, -1.35, 0.34))
        instep = A.lerp(ball, 0.5) + Vector((0, 0, -0.12))
        P.append(ellipsoid(instep, (0.82, 0.95, 0.46), rot=out @ Matrix.Rotation(math.radians(18), 3, "X")))
        P.append(ellipsoid(ball, (0.8, 0.55, 0.34), rot=out))
        tips = []
        for ang, size in ((-40, 0.8), (-14, 1.05), (12, 1.1), (38, 0.85)):
            d = Matrix.Rotation(math.radians(ang + 20) * s, 3, "Z") @ Vector((0, -1, 0))
            base = ball + d * 0.3 + Vector((0, 0, 0.04))
            knuckle = base + d * 0.8 * size + Vector((0, 0, 0.16))
            tip = knuckle + d * 0.7 * size + Vector((0, 0, -0.24))
            P.append(tube([base, knuckle, tip], [0.37, 0.31, 0.23], segs=10))
            P.append(ellipsoid(knuckle, (0.34, 0.34, 0.33), rings=6, segs=10))                  # knuckle
            P.append(ellipsoid(tip + d * 0.1 + Vector((0, 0, -0.03)), (0.4, 0.4, 0.22), rings=6, segs=10))  # pad
            tips.append((base, knuckle, tip))
        for (a0, k0, t0), (a1, k1, t1) in zip(tips, tips[1:]):                             # webbing
            near, far = (a0 + a1) / 2, (k0.lerp(t0, 0.3) + k1.lerp(t1, 0.3)) / 2
            along = (far - near).normalized()
            rot = Matrix.Rotation(math.atan2(along.x, -along.y), 3, "Z")
            width = (k0 - k1).length * 0.42
            P.append(ellipsoid(near.lerp(far, 0.45) + Vector((0, 0, -0.06)), (width, (far - near).length * 0.55, 0.07),
                               rot=rot))
    return P


def carve(co, no, J):
    """Sculpted detail pressed into the fused skin, along its normals: the belly's folds (arcs rising at the sides),
    the crease under each pec, three nubs on the upper belly, the line of the mouth and the nostrils."""
    hips, neck, head = J["jnt1_1"].z, J["jnt11_1"].z, J["jnt12_1"].z
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    front = np.clip((-no[:, 1] - 0.15) / 0.4, 0, 1)
    belly = front * np.clip((2.5 - np.abs(x)) / 0.5, 0, 1) * (y < -1.0)
    d = np.zeros(len(co))
    for zc in (hips + 0.55, hips + 1.3, hips + 2.05):
        arc = zc + 0.18 * (x / 2.3) ** 2
        d -= 0.15 * np.exp(-((z - arc) / 0.2) ** 2) * belly
    for s in (-1, 1):
        u = (x - s * 1.0) / 1.15
        arc = neck - 2.4 + 0.3 * u ** 2
        d -= 0.16 * np.exp(-((z - arc) / 0.14) ** 2) * front * (np.abs(u) < 1.0) * (x * s > 0.05)
    for nx, nz_ in ((-0.55, hips + 2.5), (0.5, hips + 2.65), (0.05, hips + 2.3)):
        d += 0.12 * np.exp(-(((x - nx) ** 2 + (z - nz_) ** 2) / 0.16 ** 2)) * belly
    seam = head - 0.4 - 0.28 * (x / 2.5) ** 2
    d -= 0.0 * np.exp(-((z - seam) / 0.08) ** 2) * front * (np.abs(x) < 2.55) * (y < -1.6) * (z > head - 1.2)
    for s in (-1, 1):
        d -= 0.12 * np.exp(-(((x - s * 0.45) ** 2 + (z - head - 0.3) ** 2) / 0.11 ** 2)) * front * (y < -2.0)
    return co + no * d[:, None]


def fuse(parts, name, J):
    """The volumes made one skin (voxel remesh), the sculpted detail carved in, smoothed and decimated."""
    v, f = [], []
    for pv, pf in parts:
        base = len(v)
        v += [tuple(x) for x in pv]
        f += [tuple(base + i for i in face) for face in pf]
    mesh = bpy.data.meshes.new(name + "_volumes")
    mesh.from_pydata(v, [], f)
    obj = bpy.data.objects.new(name + "_volumes", mesh)
    bpy.context.scene.collection.objects.link(obj)
    rm = obj.modifiers.new("remesh", "REMESH")
    rm.mode, rm.voxel_size, rm.adaptivity = "VOXEL", 0.045, 0.0
    sm = obj.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.iterations, sm.lambda_factor, sm.lambda_border = 8, 0.6, 0.0
    sm.use_volume_preserve = True
    dg = bpy.context.evaluated_depsgraph_get()
    dense = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    count = len(dense.vertices)
    co = np.zeros(count * 3)
    no = np.zeros(count * 3)
    dense.vertices.foreach_get("co", co)
    dense.vertices.foreach_get("normal", no)
    co = carve(co.reshape(-1, 3), no.reshape(-1, 3), J)
    dense.vertices.foreach_set("co", co.ravel())
    dense.update()
    obj = bpy.data.objects.new(name + "_dense", dense)
    bpy.context.scene.collection.objects.link(obj)
    sm = obj.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.iterations, sm.lambda_factor, sm.lambda_border = 2, 0.3, 0.0
    sm.use_volume_preserve = True
    dg = bpy.context.evaluated_depsgraph_get()
    tris = sum(len(p.vertices) - 2 for p in obj.evaluated_get(dg).data.polygons)
    dec = obj.modifiers.new("decimate", "DECIMATE")
    dec.ratio = min(1.0, TRIANGLES / max(tris, 1))
    dg = bpy.context.evaluated_depsgraph_get()
    out = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(dense)
    return out


# ---------------------------------------------------------------------------------------------------------------------
# Gear


class Surface:
    def __init__(self, mesh):
        self.tree = BVHTree.FromPolygons([v.co.copy() for v in mesh.vertices], [tuple(p.vertices) for p in mesh.polygons])

    def onto(self, p, toward):
        """The body's surface seen from p looking at `toward`: (point, outward normal)."""
        d = (Vector(toward) - Vector(p)).normalized()
        hit = self.tree.ray_cast(Vector(p), d)
        if hit[0] is None:
            return Vector(toward), -d
        n = hit[1] if hit[1].dot(d) < 0 else -hit[1]
        return hit[0], n

    def around(self, c, d, reach):
        """The surface of the limb round axis point c in direction d, found from inside (a ray from outside can start
        in another limb and land on it): (point, outward normal)."""
        hit = self.tree.ray_cast(Vector(c), Vector(d).normalized(), reach)
        if hit[0] is None:
            return self.onto(Vector(c) + Vector(d) * reach, c)
        n = hit[1] if hit[1].dot(d) > 0 else -hit[1]
        return hit[0], n

    def front(self, x, z, depth=-8.0):
        return self.onto(Vector((x, depth, z)), Vector((x * 0.6, -0.4, z)))


class Gear:
    def __init__(self):
        self.pieces = []  # (verts, faces, colour, bones, spotted, pattern, stripe axis or None)

    def add(self, vf, colour, bones, pattern=PLAIN, spotted=0.0, stripe=None):
        self.pieces.append((vf[0], vf[1], colour, bones, spotted, pattern, stripe))


def gear(J, S):
    hips, neck, head = J["jnt1_1"], J["jnt11_1"], J["jnt12_1"]
    G = Gear()
    H = ["jnt12_1"]
    for (pts, radii), colour in zip(LIP_CURVES, (LIPS, LIPS_LOWER)):
        G.add(tube(pts, radii, segs=14), colour, H)
    for s, eye in zip((-1, 1), EYES):
        G.add(ellipsoid(eye, (0.58, 0.5, 0.5), rings=10, segs=14), EYE, H)
        G.add(ellipsoid(eye + Vector((s * 0.06, -0.47, -0.08)), (0.25, 0.1, 0.17), rings=5, segs=10), PUPIL, H)
    for s in (-1, 1):
        # gill frills: a cluster of quills on each top corner of the head, each with two barbs
        root, rn = S.onto(Vector((s * 4.0, 0.4, head.z + 2.6)), Vector((0, 0.2, head.z + 0.6)))
        for k, (out, back, up, length) in enumerate(((0.9, 0.2, 0.7, 1.7), (0.6, 0.5, 1.0, 1.9), (0.3, 0.7, 1.1, 1.6),
                                                     (1.0, 0.3, 0.25, 1.5), (0.7, 0.8, 0.5, 1.3))):
            d = Vector((s * out, back, up)).normalized()
            base = root + Vector((0, 0.15 * k - 0.3, -0.1 * k))
            tip = base + d * length
            G.add(tube([base, base.lerp(tip, 0.5) + Vector((0, 0.05, 0.08)), tip], [0.14, 0.08, 0.015], segs=5), GILL,
                  H)
            for t, side in ((0.42, -1), (0.66, 1)):
                b = base.lerp(tip, t)
                bd = (d + Vector((s * 0.2 * side, 0.35 * side, 0.4))).normalized()
                G.add(cone(b, b + bd * 0.45, 0.04, segs=3), GILL, H)
    # pauldrons: three overlapping curved iron plates over each shoulder, riveted, a straw fringe under the last;
    # moss on the left, two spikes on the right
    for s, (sh, col) in ((1, ("jnt9_1", "jnt8_1")), (-1, ("jnt17_1", "jnt16_1"))):
        bones = [sh, col]
        tilt = Matrix.Rotation(math.radians(-30 * s), 3, "Y")
        dome = J[sh] + Vector((s * 1.05, 0, 0.78))
        G.add(ellipsoid(dome, (1.5, 1.6, 0.78), rot=tilt, rings=8, segs=14), IRON, bones, IRONY)
        G.add(ring(dome - tilt @ Vector((0, 0, 0.12)), tilt @ Vector((0, 0, 1)), 1.52, 0.11, segs=16, sides=4), IRON,
              bones, IRONY)
        for k in range(5):
            a = math.radians(-70 + 35 * k)
            G.add(ellipsoid(dome + tilt @ Vector((math.sin(a) * 0.95 * s, -math.cos(a) * 1.05, 0.5)),
                            (0.1, 0.1, 0.08), rings=3, segs=5), IRON, bones, IRONY)
        last = None
        for i in range(1, 3):
            c = J[sh] + Vector((s * (0.55 + 0.62 * i), 0.0, 0.15 - 0.32 * i))
            R = 1.5 - 0.1 * i
            pts, nrm = [], []
            for k in range(10):
                ph = math.radians(-78 + 156 * k / 9)
                d = Vector((s * (0.42 + 0.22 * i), math.sin(ph), math.cos(ph))).normalized()
                pts.append(c + d * R)
                nrm.append(d)
            G.add(band_round(pts, nrm, 0.8, 0.14), IRON, bones, IRONY)
            for k in (1, 8):
                G.add(ellipsoid(pts[k] + nrm[k] * 0.16, (0.09, 0.09, 0.09), rings=4, segs=6), IRON, bones, IRONY)
            last = (pts, nrm, c)
        pts, nrm, c = last
        for k in range(1, 9):
            edge = pts[k] + Vector((s * 0.35, 0, 0)) - nrm[k] * 0.05
            tip = edge + Vector((s * 0.35, 0, -0.75 - 0.25 * (k % 3)))
            G.add(cone(edge, tip, 0.12, segs=4), STRAW, bones, STRAWY)
        top = J[sh] + Vector((s * 0.6, 0, 1.75))
        if s > 0:
            G.add(ellipsoid(top + Vector((0.25, -0.1, -0.05)), (0.75, 0.85, 0.22), rings=6, segs=12), MOSS, bones, MOSSY)
            for dy, dz in ((-0.7, -0.4), (0.6, -0.5)):
                G.add(ellipsoid(top + Vector((0.4, dy, dz)), (0.18, 0.16, 0.3), rings=4, segs=6), MOSS, bones, MOSSY)
        else:
            for dy in (-0.4, 0.35):
                b = top + Vector((-0.2, dy, -0.05))
                G.add(cone(b, b + Vector((-0.2, 0, 0.75)), 0.15, segs=6), IRON, bones, IRONY)
    # strap: right shoulder, over the chest and belly, to the left hip; two iron rings on it
    pts, nrm = [], []
    a, b = Vector((-1.95, -0.5, neck.z + 0.15)), Vector((2.6, -1.4, hips.z + 0.3))
    for i in range(26):
        q = a.lerp(b, i / 25)
        p, n = S.onto(q + (q - Vector((0, -0.4, q.z))).normalized() * 6, Vector((0, -0.4, q.z)))
        if (p - q).length > 1.5:  # the ray from outside met the staff hand's fist: find the chest from inside
            p, n = S.around(Vector((0, -0.4, q.z)), q - Vector((0, -0.4, q.z)), 6)
        pts.append(p + n * 0.04)
        nrm.append(n)
    G.add(band_round(pts, nrm, 0.55, 0.13), LEATHER, ["jnt2_1", "jnt1_1", "jnt11_1"], LEATHERY)
    for t in (0.28, 0.62):
        i = int(t * 25)
        G.add(ring(pts[i] + nrm[i] * 0.2, nrm[i], 0.32, 0.07, segs=12, sides=4), IRON, ["jnt2_1", "jnt1_1"], IRONY)
    # sash: a green rag from the left shoulder down the chest, purple under it, torn tails
    for colour, dx, w, length, dz in ((PURPLE, 0.15, 1.0, 13, 0.0), (GREEN, 0.0, 1.15, 12, 0.08)):
        pts, nrm = [], []
        a, b = Vector((1.55 + dx, 0, neck.z - 0.1)), Vector((1.05 + dx, 0, hips.z + 1.4))
        for i in range(length):
            q = a.lerp(b, i / (length - 1))
            p, n = S.front(q.x, q.z)
            pts.append(p + n * (0.07 + dz))
            nrm.append(n)
        G.add(band_round(pts, nrm, w, 0.06, thin=True), colour, ["jnt2_1", "jnt11_1", "jnt8_1"], CLOTH)
        end, en = pts[-1], nrm[-1]
        for k in (-1, 0, 1):
            base = end + Vector((k * w * 0.32, 0, 0.05))
            G.add(cone(base, base + Vector((k * 0.15, -0.1, -0.7 - 0.25 * (k == 0))), 0.17, segs=3), colour,
                  ["jnt2_1", "jnt1_1"], CLOTH)
    # belt, its buckle frame and tongue, the pouch, the gourd on its cord
    belt_z = hips.z + 0.05
    pts, nrm = [], []
    for i in range(32):
        ang = 2 * math.pi * i / 32
        p, n = S.onto(Vector((math.cos(ang) * 7, -0.4 + math.sin(ang) * 7, belt_z)), Vector((0, -0.4, belt_z)))
        pts.append(p + n * 0.03)
        nrm.append(n)
    G.add(band_round(pts, nrm, 0.72, 0.15, closed=True), LEATHER, ["jnt1_1"], LEATHERY)
    fp, fn = S.front(0, belt_z, depth=-8)
    fr = fp + fn * 0.26
    for half, off in (((0.48, 0.07, 0.08), (0, 0, 0.38)), ((0.48, 0.07, 0.08), (0, 0, -0.38)),
                      ((0.08, 0.07, 0.42), (0.42, 0, 0)), ((0.08, 0.07, 0.42), (-0.42, 0, 0))):
        G.add(box(fr + Vector(off), half), IRON, ["jnt1_1"], IRONY)
    G.add(box(fr + Vector((0.05, 0.03, 0)), (0.05, 0.05, 0.36)), IRON, ["jnt1_1"], IRONY)
    sp, sn = S.onto(Vector((-6, -5.5, belt_z - 0.55)), Vector((0, -0.4, belt_z - 0.55)))
    rot = Matrix.Rotation(math.atan2(sn.x, -sn.y) * -1, 3, "Z")
    G.add(box(sp + sn * 0.38, (0.5, 0.3, 0.55), rot=rot), LEATHER_DARK, ["jnt1_1"], LEATHERY)
    G.add(box(sp + sn * 0.5 + Vector((0, 0, 0.38)), (0.54, 0.33, 0.16), rot=rot), LEATHER, ["jnt1_1"], LEATHERY)
    G.add(ellipsoid(sp + sn * 0.86 + Vector((0, 0, 0.2)), (0.09, 0.09, 0.09), rings=4, segs=6), IRON, ["jnt1_1"],
          IRONY)
    gp, gn = S.onto(Vector((6, -5.5, belt_z - 0.1)), Vector((0, -0.4, belt_z - 0.1)))
    g = gp + gn * 0.62 + Vector((0, 0, -1.25))
    G.add(tube([gp + gn * 0.2, gp + gn * 0.5 + Vector((0, 0, -0.4)), g + Vector((0, 0, 0.95))], [0.05, 0.05, 0.05],
               segs=4), ROPE, ["jnt1_1"], ROPY)
    G.add(ellipsoid(g, (0.55, 0.55, 0.58), rings=8, segs=12), GOURD, ["jnt1_1"])
    G.add(ellipsoid(g + Vector((0, 0, 0.75)), (0.33, 0.33, 0.33), rings=6, segs=10), GOURD, ["jnt1_1"])
    G.add(capsule(g + Vector((0, 0, 1.0)), g + Vector((0, 0, 1.25)), 0.11, 0.13, segs=6, steps=1), LEATHER_DARK,
          ["jnt1_1"], LEATHERY)

    # the loincloth: purple under, green over in front, green behind; torn hems
    def row(x0, x1, z, side, n=13, out=0.06):
        pts = []
        for i in range(n):
            x = x0 + (x1 - x0) * i / (n - 1)
            p, nn = S.onto(Vector((x, side * 8, z)), Vector((x * 0.3, -0.4, z)))
            pts.append(p + nn * out)
        return pts

    knee_z = J["jnt5_2"].z

    def loin(p):
        """Hung from the belt (the pelvis), its lower part going more and more with the thigh behind it, so the
        legs swinging forward and back in a hop carry the cloth with them instead of pushing through it."""
        t = max(0.0, min(1.0, (belt_z - 0.6 - p.z) / (belt_z - 0.6 - knee_z)))
        follow = 0.8 * t ** 1.2
        if follow < 0.03:
            return [("jnt1_1", 1.0)]
        left = max(0.0, min(1.0, 0.5 + p.x / 2.4))  # the character's left is +X
        out = [("jnt1_1", 1.0 - follow)]
        if left < 0.97:
            out.append(("jnt22_1", follow * (1.0 - left)))
        if left > 0.03:
            out.append(("jnt5_1", follow * left))
        total = sum(w for _, w in out)
        return [(n, w / total) for n, w in out]

    top = row(-2.2, 2.4, belt_z - 0.3, -1, n=13, out=0.05)
    bottom = [Vector((p.x * 0.55 + 0.2, -3.2, knee_z + 0.1 + 1.6 * abs((i - 6) / 6) ** 1.5)) for i, p in enumerate(top)]
    G.add(flap(top, bottom, 0.06, 0.4, rows=6), PURPLE, loin, CLOTH)
    top = row(-2.5, 2.3, belt_z - 0.32, -1, n=13, out=0.13)
    bottom = [Vector((p.x * 0.7 - 0.1, -3.4, knee_z + 0.9 + 1.4 * abs((i - 6) / 6) ** 1.5)) for i, p in enumerate(top)]
    G.add(flap(top, bottom, 0.06, 0.45, rows=6), GREEN, loin, CLOTH)
    top = row(-1.9, 1.9, belt_z - 0.3, 1, out=0.05)
    bottom = [Vector((p.x * 0.85, 2.85, knee_z + 1.5)) for p in top]
    G.add(flap(top, bottom, 0.06, 0.4, rows=6, outward=Vector((0, 1, 0))), GREEN, loin, CLOTH)
    # the right forearm's leather bracer and its straps; cloth wound round the left forearm and the left shin
    E, W = J["jnt17_2"], J["jnt18_1"]
    G.add(capsule(E.lerp(W, 0.42), E.lerp(W, 0.9), 0.95, 0.74, segs=16, steps=4), LEATHER, ["jnt17_2", "jnt18_1"],
          LEATHERY)
    for t in (0.52, 0.8):
        pts, nrm = surface_ring(S, E, W, t, 2.5, samples=18, out=0.12)
        G.add(band_round(pts, nrm, 0.22, 0.08, closed=True), LEATHER_DARK, ["jnt17_2", "jnt18_1"], LEATHERY)
    E, W = J["jnt9_2"], J["jnt10_1"]
    for direction, lift in ((1, 0.0), (-1, 0.04)):
        G.add(spiral_wrap(S, E, W, 0.42, 0.95, 3.0, 0.3, 2.4, direction=direction, lift=lift), WRAP_CLOTH,
              ["jnt9_2", "jnt10_1"], CLOTH)
    K, A = J["jnt5_2"], J["jnt6_1"]
    for direction, lift in ((1, 0.0), (-1, 0.04)):
        G.add(spiral_wrap(S, A + Vector((0, 0, 0.55)), K, 0.0, 0.42, 3.0, 0.32, 2.6, direction=direction, lift=lift),
              WRAP_CLOTH, ["jnt5_2", "jnt6_1"], CLOTH)
    return G.pieces


# ---------------------------------------------------------------------------------------------------------------------
# Paint


def front_mask(p, n, J):
    """The tan of the front: chest, belly and throat, fading at the sides."""
    hips, neck, head = J["jnt1_1"], J["jnt11_1"], J["jnt12_1"]
    front = max(0.0, min(1.0, (-n.y - 0.05) / 0.45))
    if p.z < hips.z - 0.7 or p.z > head.z - 0.62:
        return 0.0
    if p.z > neck.z + 0.2:
        width = 2.2  # throat under the lips
    elif p.z > neck.z - 2.4:
        width = 1.9  # chest, between the arms
    else:
        width = 2.55
    return front * max(0.0, min(1.0, (width - abs(p.x)) / 0.55))


class Nodes:
    def __init__(self, tree):
        self.t = tree

    def __call__(self, kind, **settings):
        n = self.t.nodes.new(kind)
        for key, value in settings.items():
            if key.startswith("in_"):
                n.inputs[key[3:].replace("_", " ")].default_value = value
            else:
                setattr(n, key, value)
        return n

    def link(self, a, b):
        self.t.links.new(a, b)

    def math(self, op, a, b=None, clamp=False):
        m = self("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                m.inputs[i].default_value = x
            else:
                self.link(x, m.inputs[i])
        return m.outputs[0]

    def range(self, x, a, b, c, d, clamp=True):
        m = self("ShaderNodeMapRange", clamp=clamp, in_From_Min=a, in_From_Max=b, in_To_Min=c, in_To_Max=d)
        self.link(x, m.inputs["Value"])
        return m.outputs[0]

    def mix(self, factor, a, b, blend="MIX"):
        m = self("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        for slot, x in (("Factor", factor), ("A", a), ("B", b)):
            if isinstance(x, (tuple, list)):
                m.inputs[slot].default_value = (*x, 1.0) if len(x) == 3 else x
            elif isinstance(x, (int, float)):
                m.inputs[slot].default_value = x
            else:
                self.link(x, m.inputs[slot])
        return m.outputs["Result"]

    def gray(self, x):
        c = self("ShaderNodeCombineXYZ")
        for k in "XYZ":
            self.link(x, c.inputs[k])
        return c.outputs[0]


FRONT_ZONES = []  # (height, half width of the tan front), set from the skeleton in main
CREASES = []  # heights of the painted creases on the front


def paint_material(name, image):
    mat = bpy.data.materials.new(name)
    mat["texture"] = name
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N = Nodes(nt)
    out = N("ShaderNodeOutputMaterial")
    emit = N("ShaderNodeEmission")
    N.link(emit.outputs[0], out.inputs["Surface"])
    attr = lambda a: N("ShaderNodeAttribute", attribute_name=a)
    paint, spotted_attr, body = attr("paint"), attr("spotted").outputs["Fac"], attr("front").outputs["Fac"]
    lips = attr("lips").outputs["Fac"]
    pattern, stripe = attr("pattern").outputs["Fac"], attr("stripe").outputs["Fac"]
    coord = N("ShaderNodeTexCoord").outputs["Object"]
    # the tan front: facing forward, within the chest, belly and throat, by height (FRONT_ZONES)
    fsep = N("ShaderNodeSeparateXYZ"); N.link(coord, fsep.inputs[0])
    fgeo = N("ShaderNodeNewGeometry")
    fn = N("ShaderNodeSeparateXYZ"); N.link(fgeo.outputs["Normal"], fn.inputs[0])
    facing = N.range(fn.outputs["Y"], 0.05, -0.4, 0.0, 1.0)
    ax = N.math("ABSOLUTE", fsep.outputs["X"])
    z = fsep.outputs["Z"]
    width = N("ShaderNodeFloatCurve")
    curve = width.mapping.curves[0]
    zs = FRONT_ZONES
    width.mapping.clip_min_x, width.mapping.clip_max_x = zs[0][0], zs[-1][0]
    width.mapping.clip_min_y, width.mapping.clip_max_y = 0.0, 4.0
    width.mapping.use_clip = False
    while len(curve.points) < len(zs):
        curve.points.new(0.0, 0.0)
    for point, (zz, ww) in zip(curve.points, zs):
        point.location = ((zz - zs[0][0]) / (zs[-1][0] - zs[0][0]), ww / 4.0)
    zn = N.range(z, zs[0][0], zs[-1][0], 0.0, 1.0)
    N.link(zn, width.inputs["Value"])
    w = N.math("MULTIPLY", width.outputs[0], 4.0)
    side = N.range(N.math("SUBTRACT", w, ax), 0.0, 0.6, 0.0, 1.0)
    front = N.math("MULTIPLY", N.math("MULTIPLY", facing, side), body)
    spotted = N.math("MAXIMUM", N.math("MULTIPLY", N.math("SUBTRACT", 1.0, body), spotted_attr),
                     N.math("MULTIPLY", body, N.range(front, 0.0, 0.55, 1.0, 0.0)))
    vor = lambda scale, rnd=1.0: N("ShaderNodeTexVoronoi", in_Scale=scale, in_Randomness=rnd)
    noise = lambda scale, detail=2.0: N("ShaderNodeTexNoise", in_Scale=scale, in_Detail=detail)
    # spots: blobs of varied size with a lighter rim, and speckles
    v1 = vor(1.35); N.link(coord, v1.inputs["Vector"])
    size = noise(0.9); N.link(coord, size.inputs["Vector"])
    thr = N.range(size.outputs["Fac"], 0.3, 0.7, 0.24, 0.42)
    d = N.math("SUBTRACT", v1.outputs["Distance"], thr)
    spot = N.range(d, -0.02, 0.015, 1.0, 0.0)
    rim = N.math("MULTIPLY", N.range(d, 0.0, 0.03, 0.0, 1.0), N.range(d, 0.035, 0.08, 1.0, 0.0))
    v2 = vor(3.6); N.link(coord, v2.inputs["Vector"])
    speck = N.range(v2.outputs["Distance"], 0.12, 0.17, 0.9, 0.0)
    blot = N.math("MULTIPLY", N.math("MAXIMUM", spot, speck), spotted)
    blot = N.math("MULTIPLY", blot, N.math("SUBTRACT", 1.0, attr("lips").outputs["Fac"]))
    base = N.mix(front, paint.outputs["Color"], lin(BELLY))
    base = N.mix(lips, base, lin(LIPS))
    spotted = N.math("MULTIPLY", spotted, N.math("SUBTRACT", 1.0, lips))
    col = N.mix(N.math("MULTIPLY", rim, N.math("MULTIPLY", spotted, 0.45)), base, lin(RIM))
    col = N.mix(blot, col, lin(SPOT))
    # the tan front lighter at its middle
    col = N.mix(N.math("MULTIPLY", N.math("POWER", front, 3.0), 0.3), col, lin(BELLY_LIGHT))
    # the creases between the belly's rolls, and under the pecs
    crease = None
    for zc in CREASES:
        arc = N.math("ADD", zc, N.math("MULTIPLY", N.math("POWER", N.math("DIVIDE", ax, 2.3), 2.0), 0.18))
        band_ = N.range(N.math("ABSOLUTE", N.math("SUBTRACT", fsep.outputs["Z"], arc)), 0.0, 0.12, 1.0, 0.0)
        crease = band_ if crease is None else N.math("MAXIMUM", crease, band_)
    crease_w = N.range(ax, 1.4, 2.3, 1.0, 0.0)
    crease = N.math("MULTIPLY", N.math("MULTIPLY", crease, crease_w), N.math("MULTIPLY", front, 0.0))
    col = N.mix(crease, col, lin((0.50, 0.33, 0.22)))
    # gear patterns: a factor on the colour for each, chosen by `pattern`
    def mask(i):
        return N.range(N.math("ABSOLUTE", N.math("SUBTRACT", pattern, float(i))), 0.0, 0.3, 1.0, 0.0)
    sep = N("ShaderNodeSeparateXYZ"); N.link(coord, sep.inputs[0])
    geo = N("ShaderNodeNewGeometry")
    nsep = N("ShaderNodeSeparateXYZ"); N.link(geo.outputs["Normal"], nsep.inputs[0])
    grain = noise(14.0, 4.0); N.link(coord, grain.inputs["Vector"])
    leather = N.range(grain.outputs["Fac"], 0.3, 0.7, 0.78, 1.15)
    scratch = noise(22.0, 6.0); N.link(coord, scratch.inputs["Vector"])
    iron = N.math("MULTIPLY", N.range(nsep.outputs["Z"], -0.3, 1.0, 0.65, 1.55),
                  N.range(scratch.outputs["Fac"], 0.45, 0.6, 0.85, 1.15))
    weave = N.math("MULTIPLY", N.math("SINE", N.math("MULTIPLY", sep.outputs["X"], 38.0)),
                   N.math("SINE", N.math("MULTIPLY", sep.outputs["Z"], 38.0)))
    hem = N.range(sep.outputs["Z"], 4.5, 8.0, 0.72, 1.0)
    cloth = N.math("MULTIPLY", N.range(weave, -1.0, 1.0, 0.9, 1.05), hem)
    twist = N.math("SINE", N.math("ADD", N.math("MULTIPLY", stripe, 26.0),
                                 N.math("MULTIPLY", N.math("ADD", sep.outputs["X"], sep.outputs["Y"]), 9.0)))
    rope = N.range(twist, -1.0, 1.0, 0.72, 1.12)
    streak = noise(9.0, 3.0)
    stretch = N("ShaderNodeMapping", in_Scale=(1.0, 1.0, 0.15)); N.link(coord, stretch.inputs["Vector"])
    N.link(stretch.outputs[0], streak.inputs["Vector"])
    straw = N.range(streak.outputs["Fac"], 0.35, 0.65, 0.7, 1.2)
    patch = noise(3.5, 3.0); N.link(coord, patch.inputs["Vector"])
    moss = N.range(patch.outputs["Fac"], 0.4, 0.6, 0.6, 1.2)
    factor = 1.0
    acc = None
    for i, f in ((LEATHERY, leather), (IRONY, iron), (CLOTH, cloth), (ROPY, rope), (STRAWY, straw), (MOSSY, moss)):
        term = N.math("MULTIPLY", mask(i), N.math("SUBTRACT", f, 1.0))
        acc = term if acc is None else N.math("ADD", acc, term)
    factor = N.math("ADD", acc, 1.0)
    # the creases' shade, a light from above, a painter's variation
    ao = N("ShaderNodeAmbientOcclusion", only_local=True, samples=24, in_Distance=1.1)
    shade = N.range(ao.outputs["AO"], 0.0, 1.0, 0.42, 1.0)
    top = N.range(nsep.outputs["Z"], -1.0, 1.0, 0.8, 1.16)
    vary_n = noise(2.4); N.link(coord, vary_n.inputs["Vector"])
    vary = N.range(vary_n.outputs["Fac"], 0.3, 0.7, 0.9, 1.08)
    light = N.math("MULTIPLY", N.math("MULTIPLY", shade, top), N.math("MULTIPLY", vary, factor))
    final = N.mix(1.0, col, N.gray(light), blend="MULTIPLY")
    N.link(final, emit.inputs["Color"])
    target = N("ShaderNodeTexImage", image=image)
    nt.nodes.active = target
    return mat


def show_material(mat, path):
    """After the bake: the material shows its picture (and the export names its texture)."""
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path, check_existing=False)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])


# ---------------------------------------------------------------------------------------------------------------------


def main():
    scene = bpy.context.scene
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    character = bpy.data.collections["Character"]
    reference = bpy.data.collections.get("Template reference")
    if reference:
        reference.hide_render = True
    for obj in list(character.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj)
    apply_proportions(arm)
    J = joints(arm)
    segs = segments(J)
    hz, nz, kz = J["jnt12_1"].z, J["jnt11_1"].z, J["jnt1_1"].z
    CREASES[:] = [kz + 0.55, kz + 1.3, kz + 2.05]
    FRONT_ZONES[:] = [(kz - 0.9, 0.0), (kz - 0.5, 2.3), (kz + 1.5, 2.6), (nz - 2.2, 2.3), (nz - 1.0, 1.9),
                      (nz + 0.2, 2.1), (hz - 0.7, 2.2), (hz - 0.5, 0.0)]

    body = fuse(body_volumes(J), "opar", J)
    S = Surface(body)
    pieces = gear(J, S)

    verts, faces, mats = [], [], []
    colour, spotted, front, pattern, stripe, weights, lips = [], [], [], [], [], [], []

    def lip_mask(p):
        best = 1e9
        for pts, radii in LIP_CURVES:
            for a, b, ra, rb in zip(pts, pts[1:], radii, radii[1:]):
                best = min(best, to_segment(p, a, b) - (ra + rb) / 2)
        return max(0.0, min(1.0, (0.1 - best) / 0.08))
    for v in body.vertices:
        p, n = v.co.copy(), v.normal.copy()
        verts.append(p)
        colour.append(lin(SKIN))
        spotted.append(1.0)
        front.append(1.0)  # on the body: the shader works out the tan front
        lips.append(lip_mask(p) if p.y < -1.5 and p.z > J["jnt12_1"].z - 1.4 else 0.0)
        pattern.append(float(PLAIN))
        stripe.append(0.0)
        weights.append(weigh(p, body_candidates(p, J), segs))
    head_z, legs_z = J["jnt11_1"].z + 0.55, J["jnt1_1"].z - 1.0
    for poly in body.polygons:
        faces.append(tuple(poly.vertices))
        c = sum((body.vertices[i].co for i in poly.vertices), Vector()) / len(poly.vertices)
        mats.append(0 if c.z > head_z and abs(c.x) < 3.2 else (3 if c.z < legs_z else 1))
    for pv, pf, col, bones, spot, pat, axis in pieces:
        base = len(verts)
        for p in pv:
            verts.append(p)
            colour.append(lin(col))
            spotted.append(spot)
            front.append(0.0)
            lips.append(0.0)
            pattern.append(float(pat))
            stripe.append(p.dot(axis) if axis is not None else 0.0)
            weights.append(bones(p) if callable(bones) else weigh(p, bones, segs))
        faces += [tuple(base + i for i in f) for f in pf]
        mats += [2] * len(pf)
    bpy.data.meshes.remove(body)

    mesh = bpy.data.meshes.new("skin")
    mesh.from_pydata([tuple(p) for p in verts], [], faces)
    mesh.validate()
    for poly, m in zip(mesh.polygons, mats):
        poly.material_index = m
    mesh.shade_smooth()
    attr = mesh.color_attributes.new("paint", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(colour):
        attr.data[i].color = (*c, 1.0)
    for name, values in (("spotted", spotted), ("front", front), ("pattern", pattern), ("stripe", stripe),
                         ("lips", lips)):
        a = mesh.attributes.new(name, "FLOAT", "POINT")
        a.data.foreach_set("value", values)

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

    # UVs: each page's faces unwrapped in big islands into the whole picture
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
        bpy.ops.uv.smart_project(angle_limit=math.radians(72), island_margin=0.008, area_weight=0.0,
                                 scale_to_bounds=False)
        bpy.ops.uv.pack_islands(margin=0.005, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
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
    counts = [0] * len(PAGES)
    for m in mats:
        counts[m] += 1
    print("OPAR vertices", len(mesh.vertices), "triangles", sum(len(p.vertices) - 2 for p in mesh.polygons),
          "faces by page", dict(zip(PAGES, counts)))


main()
