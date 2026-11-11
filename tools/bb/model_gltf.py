"""A Bloodborne model (model.json, written by BbModel export in Program.cs) as a skinned glTF 2.0 file that Blender opens.

    python tools/bb/model_gltf.py <folder holding model.json> [-o <out.gltf>] [--mirror x|z|none]

The default output is <folder>/model.gltf with model.bin beside it. model.json comes from the player's own dump and
must stay outside the repository, so keep the folder and the output outside git.

The game's space is left-handed and glTF's is right-handed. --mirror x (the default) negates X in the positions,
normals, bone matrices and inverse binds, and swaps two indices in each triangle so the faces still point the right
way. --mirror z does the same for Z. Python 3.11, standard library only.
"""

import argparse
import json
import os
import struct
import sys

FORMAT = "moonmod-bb-model"
VERSION = 1
MIRROR_AXIS = {"x": 0, "z": 2, "none": None}  # the axis negated by each --mirror choice

# glTF enumerations
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963
FLOAT = 5126
UNSIGNED_SHORT = 5123
UNSIGNED_INT = 5125
TRIANGLES = 4

COMPONENT_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


# ---- reading ----------------------------------------------------------------------------------------------------

def load_model(path):
    """model.json as a dict, checked: a wrong format or version, an array of the wrong length, a triangle naming a
    vertex the mesh does not have, a joint that is not a node, or a parent that does not come before its child."""
    with open(path, encoding="utf-8") as f:
        model = json.load(f)
    if not isinstance(model, dict):
        raise ValueError("%s: not a JSON object" % path)
    if model.get("format") != FORMAT:
        raise ValueError("%s: format is %r, expected %r" % (path, model.get("format"), FORMAT))
    if model.get("version") != VERSION:
        raise ValueError("%s: version is %r, expected %d" % (path, model.get("version"), VERSION))

    nodes = model.get("nodes", [])
    for i, n in enumerate(nodes):
        if len(n.get("world", [])) != 16:
            raise ValueError("node %d (%s): world has %d numbers, expected 16"
                             % (i, n.get("name"), len(n.get("world", []))))
        # A parent always comes first in the file, so a child's world can be built from it in one pass.
        if n.get("parent", -1) >= i:
            raise ValueError("node %d (%s): parent %d does not come before it" % (i, n.get("name"), n["parent"]))

    for mi, m in enumerate(model.get("meshes", [])):
        _check_mesh(mi, m, len(nodes))
    return model


def _check_mesh(mi, m, bone_count):
    def bad(message):
        raise ValueError("mesh %d: %s" % (mi, message))

    vertex_count = m.get("vertex_count")
    triangle_count = m.get("triangle_count")
    if not isinstance(vertex_count, int) or vertex_count < 0:
        bad("vertex_count %r is not a count" % (vertex_count,))
    if not isinstance(triangle_count, int) or triangle_count < 0:
        bad("triangle_count %r is not a count" % (triangle_count,))

    for key, per_vertex in (("positions", 3), ("normals", 3), ("uvs", 2), ("joints", 4), ("weights", 4)):
        values = m.get(key)
        if values is None or len(values) != per_vertex * vertex_count:
            found = "missing" if values is None else "%d numbers" % len(values)
            bad("%s has %s, expected %d (%d per vertex, %d vertices)"
                % (key, found, per_vertex * vertex_count, per_vertex, vertex_count))

    triangles = m.get("triangles")
    if triangles is None or len(triangles) != 3 * triangle_count:
        found = "missing" if triangles is None else "%d numbers" % len(triangles)
        bad("triangles has %s, expected %d" % (found, 3 * triangle_count))
    for vertex in triangles:
        if vertex < 0 or vertex >= vertex_count:
            bad("a triangle names vertex %d, but the mesh has %d vertices" % (vertex, vertex_count))

    for joint in m["joints"]:
        if joint < 0 or joint >= bone_count:
            bad("a joint is node %d, but the model has %d nodes" % (joint, bone_count))


# ---- matrices ---------------------------------------------------------------------------------------------------
# A matrix is a flat list of 16 numbers, M11..M44 in row-major order, in BbModel's row-vector convention: a point is
# a row vector p and p * M moves it, so a child's world is child_local * parent_world. glTF reads the same 16 numbers
# as a column-major matrix, which is why they are written to the file unchanged.

def _mul(a, b):
    return [sum(a[i * 4 + k] * b[k * 4 + j] for k in range(4)) for i in range(4) for j in range(4)]


def _invert(m, name):
    # Gauss-Jordan elimination with partial pivoting on [m | I].
    rows = [m[i * 4:(i + 1) * 4] + [1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]
    for col in range(4):
        pivot = max(range(col, 4), key=lambda r: abs(rows[r][col]))
        if abs(rows[pivot][col]) < 1e-12:
            raise ValueError("node %s: world matrix is singular, so it has no inverse" % name)
        rows[col], rows[pivot] = rows[pivot], rows[col]
        p = rows[col][col]
        rows[col] = [x / p for x in rows[col]]
        for r in range(4):
            if r != col and rows[r][col] != 0.0:
                f = rows[r][col]
                rows[r] = [x - f * y for x, y in zip(rows[r], rows[col])]
    return [x for row in rows for x in row[4:]]


def _mirror(m, axis):
    # S * M * S with S = diag(1,1,1,1) except -1 at the mirrored axis. Element (i, j) changes sign when exactly one of
    # i and j is that axis: row 0 and column 0 except element 0 for X, row 2 and column 2 except element 10 for Z.
    def s(i):
        return -1.0 if i == axis else 1.0
    return [m[i * 4 + j] * s(i) * s(j) for i in range(4) for j in range(4)]


# ---- writing ----------------------------------------------------------------------------------------------------

def _as_f32(values):
    # Round to the float32 the file stores, so the min and max written are the values a reader gets back.
    n = len(values)
    return list(struct.unpack("<%df" % n, struct.pack("<%df" % n, *values)))


def _minmax(values, width):
    columns = [values[i::width] for i in range(width)]
    return [min(c) for c in columns], [max(c) for c in columns]


def _skin(weights, joints, vertex_count):
    # Each vertex's weights divided by their sum, so they add to 1. A vertex with no weight at all is put wholly on its
    # first bone. A joint with weight 0 is written as joint 0, which the file's readers expect for unused slots.
    out_weights, out_joints = [], []
    for v in range(vertex_count):
        w = [float(x) for x in weights[4 * v:4 * v + 4]]
        j = [int(x) for x in joints[4 * v:4 * v + 4]]
        total = sum(w)
        w = [1.0, 0.0, 0.0, 0.0] if total == 0 else [x / total for x in w]
        j = [jj if ww != 0 else 0 for jj, ww in zip(j, w)]
        out_weights.extend(w)
        out_joints.extend(j)
    return out_weights, out_joints


class _Buffer:
    """The .bin being built. Every bufferView starts on a multiple of 4 bytes, and the file's length is one too."""

    def __init__(self):
        self.data = bytearray()
        self.views = []
        self.accessors = []

    def _pad(self):
        self.data.extend(b"\0" * ((-len(self.data)) % 4))

    def add(self, payload, count, kind, component, target=None, minmax=None):
        self._pad()
        self.views.append({"buffer": 0, "byteOffset": len(self.data), "byteLength": len(payload)})
        if target is not None:
            self.views[-1]["target"] = target
        self.data.extend(payload)
        accessor = {"bufferView": len(self.views) - 1, "componentType": component, "count": count, "type": kind}
        if minmax is not None:
            accessor["min"], accessor["max"] = minmax
        self.accessors.append(accessor)
        return len(self.accessors) - 1

    def finish(self):
        self._pad()
        return bytes(self.data)


def convert(model, mirror="x"):
    """(gltf dict, bin bytes) for a model from load_model. The buffer's uri is set by main."""
    if mirror not in MIRROR_AXIS:
        raise ValueError("mirror must be x, z or none, not %r" % (mirror,))
    axis = MIRROR_AXIS[mirror]
    nodes = model["nodes"]
    bone_count = len(nodes)
    if bone_count > 65536:
        raise ValueError("%d bones, but JOINTS_0 holds 16-bit joint numbers" % bone_count)

    # Worlds first (mirrored when asked), then the locals and inverse binds, which need the parent's world.
    worlds = []
    for n in nodes:
        w = [float(x) for x in n["world"]]
        worlds.append(_mirror(w, axis) if axis is not None else w)
    inverses = [_invert(w, n.get("name", "")) for w, n in zip(worlds, nodes)]
    locals_ = []
    for i, n in enumerate(nodes):
        parent = n.get("parent", -1)
        locals_.append(worlds[i] if parent < 0 else _mul(worlds[i], inverses[parent]))

    children = [[] for _ in nodes]
    for i, n in enumerate(nodes):
        if n.get("parent", -1) >= 0:
            children[n["parent"]].append(i)
    gltf_nodes = []
    for i, n in enumerate(nodes):
        node = {"name": n.get("name", "bone%d" % i), "matrix": locals_[i]}
        if children[i]:
            node["children"] = children[i]
        gltf_nodes.append(node)
    scene_nodes = [i for i, n in enumerate(nodes) if n.get("parent", -1) < 0]

    buf = _Buffer()
    ibm = buf.add(struct.pack("<%df" % (16 * bone_count), *[x for inv in inverses for x in inv]),
                  bone_count, "MAT4", FLOAT)

    materials = []
    for m in model.get("materials", []):
        materials.append({
            "name": m.get("name", ""),
            "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 1},
            "extras": {"mtd": m.get("mtd", ""), "textures": m.get("textures", [])},
        })

    meshes = []
    mesh_nodes = []
    for mi, m in enumerate(model.get("meshes", [])):
        vertex_count = m["vertex_count"]
        triangle_count = m["triangle_count"]
        if vertex_count == 0 or triangle_count == 0:
            continue  # left out, with its node

        positions = [float(x) for x in m["positions"]]
        normals = [float(x) for x in m["normals"]]
        triangles = [int(x) for x in m["triangles"]]
        if axis is not None:
            for v in range(vertex_count):
                positions[3 * v + axis] = -positions[3 * v + axis]
                normals[3 * v + axis] = -normals[3 * v + axis]
            # A mirror turns every triangle inside out; swapping two corners keeps its front face.
            for t in range(triangle_count):
                triangles[3 * t + 1], triangles[3 * t + 2] = triangles[3 * t + 2], triangles[3 * t + 1]
        weights, joints = _skin(m["weights"], m["joints"], vertex_count)

        positions = _as_f32(positions)
        attributes = {
            "POSITION": buf.add(struct.pack("<%df" % len(positions), *positions), vertex_count, "VEC3", FLOAT,
                                ARRAY_BUFFER, _minmax(positions, 3)),
            "NORMAL": buf.add(struct.pack("<%df" % len(normals), *normals), vertex_count, "VEC3", FLOAT,
                              ARRAY_BUFFER),
            "TEXCOORD_0": buf.add(struct.pack("<%df" % len(m["uvs"]), *[float(x) for x in m["uvs"]]),
                                  vertex_count, "VEC2", FLOAT, ARRAY_BUFFER),
            "JOINTS_0": buf.add(struct.pack("<%dH" % len(joints), *joints), vertex_count, "VEC4",
                                UNSIGNED_SHORT, ARRAY_BUFFER),
            "WEIGHTS_0": buf.add(struct.pack("<%df" % len(weights), *weights), vertex_count, "VEC4", FLOAT,
                                 ARRAY_BUFFER),
        }
        indices = buf.add(struct.pack("<%dI" % len(triangles), *triangles), 3 * triangle_count, "SCALAR",
                          UNSIGNED_INT, ELEMENT_ARRAY_BUFFER)

        primitive = {"attributes": attributes, "indices": indices, "mode": TRIANGLES}
        material = m.get("material", -1)
        if isinstance(material, int) and 0 <= material < len(materials):
            primitive["material"] = material
        meshes.append({"name": "mesh%d" % mi, "primitives": [primitive]})
        # The mesh nodes come after every bone node, so the bones keep the model's node numbers.
        mesh_nodes.append({"name": "mesh%d" % mi, "mesh": len(meshes) - 1, "skin": 0})
        scene_nodes.append(bone_count + len(mesh_nodes) - 1)

    data = buf.finish()
    gltf = {
        "asset": {"version": "2.0", "generator": "moonmod tools/bb/model_gltf.py"},
        "scene": 0,
        "scenes": [{
            "nodes": scene_nodes,
            "extras": {"source": model.get("source"), "flver_version": model.get("flver_version"), "mirror": mirror},
        }],
        "nodes": gltf_nodes + mesh_nodes,
        "skins": [{"joints": list(range(bone_count)), "inverseBindMatrices": ibm}],
        "meshes": meshes,
        "materials": materials,
        "accessors": buf.accessors,
        "bufferViews": buf.views,
        "buffers": [{"uri": "model.bin", "byteLength": len(data)}],
    }
    return gltf, data


# ---- command line -----------------------------------------------------------------------------------------------

def main(argv):
    """Exit code: 0 written, 1 for a bad or missing model or a write error, 2 for bad usage."""
    parser = argparse.ArgumentParser(prog="model_gltf.py",
                                     description="model.json from BbModel export as a skinned glTF 2.0 file.")
    parser.add_argument("folder", help="folder holding model.json")
    parser.add_argument("-o", dest="out", metavar="out.gltf", help="output file (default: <folder>/model.gltf)")
    parser.add_argument("--mirror", choices=sorted(MIRROR_AXIS), default="x",
                        help="negate this axis to turn the left-handed game space right-handed (default: x)")
    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        return 0 if e.code == 0 else 2

    out = args.out or os.path.join(args.folder, "model.gltf")
    try:
        model = load_model(os.path.join(args.folder, "model.json"))
        gltf, data = convert(model, args.mirror)

        # The .bin takes the .gltf's stem and sits beside it.
        stem = os.path.splitext(os.path.basename(out))[0]
        bin_name = stem + ".bin"
        out_dir = os.path.dirname(out)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        gltf["buffers"][0]["uri"] = bin_name
        with open(os.path.join(out_dir, bin_name), "wb") as f:
            f.write(data)
        with open(out, "w", encoding="utf-8") as f:
            json.dump(gltf, f, indent=2)
    except (OSError, ValueError) as e:
        print("model_gltf: %s" % e, file=sys.stderr)
        return 1

    meshes = model.get("meshes", [])
    print("%s: %d meshes, %d vertices, %d triangles, %d bones -> %s"
          % (model.get("source"), len(meshes), sum(m["vertex_count"] for m in meshes),
             sum(m["triangle_count"] for m in meshes), len(model["nodes"]), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
