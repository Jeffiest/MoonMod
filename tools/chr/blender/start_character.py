"""Blender: the starting file for a new character on a template character's skeleton.

    blender -b --factory-startup --python start_character.py -- <bind.gltf> <textures dir> <concept image> <out.blend>

<bind.gltf> is the template pack's export with its rest at the bind pose (build_character.py start writes it). The file
gets:
- collection "Character" (the one that is exported): the template's armature, and a blockout `skin` mesh weighted to
  the deforming bones, to model over or replace;
- collection "Template reference": the template's own meshes, as wireframe, not exported;
- the concept image as a reference picture behind the model (front view);
- material `c07d03` on the blockout, its picture painted into <textures dir>/c07d03.png.

Model in "Character". The body is one skinned mesh named `skin` (the frame the pack's ALLOC_DBUFF names), weighted
to the deforming bones (DEFORM below; at most 32, 4 weights a vertex); materials are named after the pack's textures
(c07d02-c07d05, 256 x 256; c07d01 is the face picture the eye blink writes into).
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
SRC, TEXTURES, CONCEPT, OUT = ARGS[:4]
PACK = os.environ.get("CHR_PACK", "c07d")
BODY_TEXTURE = PACK + "03"

# Bones a body may be weighted to: the joints of the skeleton's chains (hips, chest, neck, head, collarbones, arms,
# hands, legs, feet, toes), each with a place in the bind pose. The others are chain links, ends, effects, attachment
# points (weapon, dcol, item, face) and the frames Toan's rigid meshes hang on (kao, l_hand, r_f...), which sit at
# the origin: their meshes are in model space.
DEFORM = {
    "jnt1_1", "jnt2_1", "jnt11_1", "jnt12_1",
    "jnt8_1", "jnt9_1", "jnt9_2", "jnt10_1",
    "jnt16_1", "jnt17_1", "jnt17_2", "jnt18_1",
    "jnt22_1", "jnt22_2", "jnt23_1", "jnt24_1",
    "jnt5_1", "jnt5_2", "jnt6_1", "jnt7_1",
}

# Picture regions of the body texture (u0, v0, u1, v1) and their colours.
REGIONS = {
    "skin": ((0.0, 0.5, 0.5, 1.0), (0.13, 0.17, 0.26)),
    "belly": ((0.5, 0.5, 1.0, 1.0), (0.80, 0.66, 0.47)),
    "lips": ((0.0, 0.25, 0.25, 0.5), (0.86, 0.52, 0.66)),
    "eye": ((0.25, 0.25, 0.5, 0.5), (0.93, 0.83, 0.42)),
    "leather": ((0.5, 0.25, 0.75, 0.5), (0.42, 0.27, 0.15)),
    "green": ((0.75, 0.25, 1.0, 0.5), (0.24, 0.40, 0.27)),
    "purple": ((0.0, 0.0, 0.25, 0.25), (0.40, 0.25, 0.42)),
    "metal": ((0.25, 0.0, 0.5, 0.25), (0.47, 0.47, 0.50)),
    "dark": ((0.5, 0.0, 0.75, 0.25), (0.05, 0.05, 0.07)),
}


def paint_texture(path, size=256):
    img = bpy.data.images.new(BODY_TEXTURE, size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    for name, ((u0, v0, u1, v1), (r, g, b)) in REGIONS.items():
        for y in range(int(v0 * size), int(v1 * size)):
            for x in range(int(u0 * size), int(u1 * size)):
                cr, cg, cb = r, g, b
                if name == "skin":
                    # black spots on the blue-black hide
                    fx, fy = (x % 24) - 12, (y % 20) - 10
                    jitter = ((x // 24) * 7 + (y // 20) * 13) % 5
                    if fx * fx + fy * fy < 18 + jitter * 4:
                        cr, cg, cb = 0.03, 0.04, 0.07
                elif name == "belly" and (y % 16) < 2:
                    cr, cg, cb = r * 0.85, g * 0.85, b * 0.85  # the belly's folds
                i = (y * size + x) * 4
                px[i:i + 4] = [cr, cg, cb, 1.0]
    img.pixels = px
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.reload()
    return img


def body_material(img):
    mat = bpy.data.materials.new(BODY_TEXTURE)
    mat["texture"] = BODY_TEXTURE
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    bsdf = nodes.get("Principled BSDF")
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def bone_world(arm, name):
    return arm.matrix_world @ arm.data.bones[name].matrix_local


def pos(arm, name):
    return bone_world(arm, name).to_translation()


def segment(arm, name):
    """A deforming bone as the segment from its head to the next deforming bone down its chain (a point at the
    chain's end)."""
    a = pos(arm, name)
    bone = arm.data.bones[name]
    best = None
    stack = list(bone.children)
    while stack:
        child = stack.pop()
        if child.name in DEFORM:
            p = pos(arm, child.name)
            if (p - a).length > 0.2 and (best is None or (p - a).length < (best - a).length):
                best = p
            continue
        stack.extend(child.children)
    return a, best if best is not None else a


def distance_to_segment(p, a, b):
    ab = b - a
    t = 0.0 if ab.length_squared == 0 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (a + ab * t - p).length


def add_piece(pieces, verts_faces, region, bones):
    pieces.append((verts_faces, region, bones))


def ellipsoid(center, radii, rot=Matrix.Identity(3), rings=8, segments=12, cut=None):
    verts, faces = [], []
    for i in range(rings + 1):
        th = math.pi * i / rings
        for j in range(segments):
            ph = 2 * math.pi * j / segments
            v = Vector((math.sin(th) * math.cos(ph) * radii[0], math.sin(th) * math.sin(ph) * radii[1],
                        math.cos(th) * radii[2]))
            verts.append(center + rot @ v)
    for i in range(rings):
        for j in range(segments):
            a, b = i * segments + j, i * segments + (j + 1) % segments
            c, d = a + segments, b + segments
            faces.append((a, c, d, b))
    return verts, faces


def capsule(a, b, ra, rb, segments=10, rings=4):
    """A tube from a to b, its radius ra to rb, closed with caps."""
    axis = b - a
    if axis.length < 1e-4:
        axis = Vector((0, 0, 0.01))
    z = axis.normalized()
    x = z.orthogonal().normalized()
    y = z.cross(x)
    verts, faces = [], []
    for i in range(rings + 1):
        t = i / rings
        r = ra + (rb - ra) * t
        c = a + axis * t
        for j in range(segments):
            ph = 2 * math.pi * j / segments
            verts.append(c + (x * math.cos(ph) + y * math.sin(ph)) * r)
    for i in range(rings):
        for j in range(segments):
            p, q = i * segments + j, i * segments + (j + 1) % segments
            faces.append((p, q, q + segments, p + segments))
    for end, center in ((0, a - z * ra * 0.6), (rings, b + z * rb * 0.6)):
        verts.append(center)
        k = len(verts) - 1
        for j in range(segments):
            p, q = end * segments + j, end * segments + (j + 1) % segments
            faces.append((p, q, k) if end else (q, p, k))
    return verts, faces


def blockout(arm):
    """A frog's blockout on the template's skeleton: a fat spotted body and belly, a wide head with pink lips and
    yellow eyes, thick limbs, big hands and feet, a belt, a loincloth and shoulder pads."""
    P = lambda n: pos(arm, n)
    front = Vector((0, -1, 0))
    pieces = []
    hips, chest, neck, head = P("jnt1_1"), P("jnt2_1"), P("jnt11_1"), P("jnt12_1")
    up = (neck - hips).normalized()
    belly_center = hips.lerp(chest, 0.5)
    add_piece(pieces, ellipsoid(belly_center + up * 0.3, (3.4, 2.6, 3.6)), "skin",
              ["jnt1_1", "jnt2_1", "jnt11_1"])
    add_piece(pieces, ellipsoid(belly_center + front * 1.4 - up * 0.2, (2.6, 1.5, 2.9)), "belly",
              ["jnt1_1", "jnt2_1"])
    hc = head + up * 1.3 + front * 0.5
    add_piece(pieces, ellipsoid(hc, (2.7, 2.3, 1.9)), "skin", ["jnt12_1", "jnt11_1"])
    add_piece(pieces, ellipsoid(hc + front * 1.9 - up * 0.35, (2.1, 0.5, 0.45)), "lips", ["jnt12_1", "jnt11_1"])
    for side in (-1, 1):
        e = hc + up * 1.4 + front * 0.9 + Vector((side * 1.3, 0, 0))
        add_piece(pieces, ellipsoid(e, (0.55, 0.5, 0.5), rings=6, segments=8), "eye", ["jnt12_1", "jnt11_1"])
        add_piece(pieces, ellipsoid(e + front * 0.42 + up * 0.05, (0.42, 0.15, 0.12), rings=4, segments=8),
                  "dark", ["jnt12_1", "jnt11_1"])
        # the gill spines
        for k in range(3):
            base = hc + Vector((side * 2.3, 0.3, 0.6 + k * 0.4))
            tip = base + Vector((side * 1.4, 0.4, 0.9 - k * 0.2))
            add_piece(pieces, capsule(base, tip, 0.18, 0.04, segments=5, rings=1), "skin", ["jnt12_1", "jnt11_1"])
    limbs = [
        ("jnt9_1", 1.0, 0.85), ("jnt9_2", 0.85, 0.75), ("jnt17_1", 1.0, 0.85), ("jnt17_2", 0.85, 0.75),
        ("jnt22_1", 1.45, 1.1), ("jnt22_2", 1.1, 0.8), ("jnt5_1", 1.45, 1.1), ("jnt5_2", 1.1, 0.8),
        ("jnt8_1", 1.1, 1.0), ("jnt16_1", 1.1, 1.0),
    ]
    for name, ra, rb in limbs:
        a, b = segment(arm, name)
        parent = arm.data.bones[name].parent
        while parent is not None and parent.name not in DEFORM:
            parent = parent.parent
        add_piece(pieces, capsule(a, b, ra, rb), "skin", [name] + ([parent.name] if parent else []))
    for hand, wrist in (("jnt10_1", "jnt9_2"), ("jnt18_1", "jnt17_2")):
        h = P(hand)
        out = (h - P(wrist)).normalized()
        add_piece(pieces, ellipsoid(h + out * 1.0, (1.1, 0.75, 0.9)), "skin", [hand, wrist])
        for f in range(4):
            spread = (f - 1.5) * 0.45
            base = h + out * 1.6 + Vector((0, spread, -0.2))
            add_piece(pieces, capsule(base, base + out * 1.3 + Vector((0, spread * 0.6, -0.3)), 0.25, 0.3,
                                      segments=6, rings=1), "skin", [hand])
    for foot in ("jnt23_1", "jnt6_1"):
        a = P(foot)
        add_piece(pieces, ellipsoid(a + front * 1.6 - up * 0.5, (1.5, 2.6, 0.6)), "skin",
                  [foot, "jnt24_1" if foot == "jnt23_1" else "jnt7_1"])
    add_piece(pieces, ellipsoid(hips + up * 0.2, (3.3, 2.6, 0.45), segments=16), "leather", ["jnt1_1"])
    add_piece(pieces, ellipsoid(hips - up * 1.6 + front * 2.3, (1.6, 0.25, 1.9)), "green", ["jnt1_1"])
    add_piece(pieces, ellipsoid(hips - up * 1.4 + front * 2.15 + Vector((0.6, 0, 0)), (0.9, 0.2, 1.6)), "purple",
              ["jnt1_1"])
    add_piece(pieces, ellipsoid(hips - up * 1.6 - front * 2.3, (1.8, 0.25, 1.9)), "green", ["jnt1_1"])
    for shoulder in ("jnt9_1", "jnt17_1"):
        add_piece(pieces, ellipsoid(P(shoulder) + up * 0.6, (1.4, 1.5, 0.8)), "metal",
                  [shoulder, "jnt8_1" if shoulder == "jnt9_1" else "jnt16_1"])
    return pieces


def build_skin(arm, pieces, mat):
    segments = {name: segment(arm, name) for name in DEFORM}
    verts, faces, uvs, weights = [], [], [], []
    for (vs, fs), region, bones in pieces:
        (u0, v0, u1, v1), _ = REGIONS[region]
        inset = 0.02
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        size = hi - lo
        base = len(verts)
        for v in vs:
            verts.append(v)
            # a cylinder wrap around the piece's longest axis, squeezed into its region
            n = (v - (lo + hi) / 2)
            a = math.atan2(n.y, n.x) / (2 * math.pi) + 0.5
            h = (v.z - lo.z) / size.z if size.z > 1e-6 else 0.5
            weights.append(piece_weights(v, bones, segments))
            uvs.append((u0 + inset + a * (u1 - u0 - 2 * inset), v0 + inset + h * (v1 - v0 - 2 * inset)))
        faces.extend(tuple(base + i for i in f) for f in fs)
    mesh = bpy.data.meshes.new("skin")
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[mesh.loops[li].vertex_index]
    mesh.materials.append(mat)
    mesh.validate()
    obj = bpy.data.objects.new("skin", mesh)
    for name in sorted(DEFORM):
        obj.vertex_groups.new(name=name)
    for i, w in enumerate(weights):
        for name, value in w:
            obj.vertex_groups[name].add([i], value, "REPLACE")
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return obj


def piece_weights(p, bones, segments, keep=3):
    """Weights of a point among a piece's bones: by inverse distance to each bone's segment (power 4), the strongest
    `keep`, summing to 1."""
    scored = []
    for name in bones:
        a, b = segments[name]
        d = max(distance_to_segment(p, a, b), 0.05)
        scored.append((1.0 / d ** 4, name))
    scored.sort(reverse=True)
    scored = scored[:keep]
    total = sum(s for s, _ in scored)
    return [(n, s / total) for s, n in scored if s / total > 0.02]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    scene = bpy.context.scene
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    character = bpy.data.collections.new("Character")
    reference = bpy.data.collections.new("Template reference")
    scene.collection.children.link(character)
    scene.collection.children.link(reference)
    for obj in list(bpy.data.objects):
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        if obj == arm:
            character.objects.link(obj)
        elif obj.type == "MESH" and obj.parent is None and not obj.vertex_groups:
            bpy.data.objects.remove(obj)  # the importer's bone display shape
        else:
            reference.objects.link(obj)
            obj.display_type = "WIRE"
            obj.hide_select = True
    for bone in arm.data.bones:
        bone.use_deform = bone.name in DEFORM
    arm.show_in_front = True
    arm.data.display_type = "STICK"

    os.makedirs(TEXTURES, exist_ok=True)
    img = paint_texture(os.path.join(TEXTURES, BODY_TEXTURE + ".png"))
    skin = build_skin(arm, blockout(arm), body_material(img))
    character.objects.link(skin)

    if os.path.isfile(CONCEPT):
        picture = bpy.data.images.load(CONCEPT)
        ref = bpy.data.objects.new("Concept", None)
        ref.empty_display_type = "IMAGE"
        ref.data = picture
        ref.empty_display_size = 22.0
        ref.empty_image_side = "FRONT"
        ref.show_empty_image_perspective = False
        ref.location = (0, 12, 9)
        ref.rotation_euler = (math.radians(90), 0, 0)
        reference.objects.link(ref)

    bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children["Character"]
    bpy.ops.wm.save_as_mainfile(filepath=OUT, relative_remap=True)
    print("START", OUT, "vertices", len(skin.data.vertices), "triangles",
          sum(len(p.vertices) - 2 for p in skin.data.polygons))


main()
