"""Character packs (.chr) through glTF, with the DC1 toolkit (dc2tk model-export / model-build) doing the format work.

A new playable character is built on an existing character's pack as the template: its frames (bones) keep their
names, so the engine's motion, weapon and move code all find them. This module exports a pack to an editable folder,
builds a pack back from one, and reads and writes the glTF meshes in between (unweld, subdivide, compare).

    python tools/chr/chrtool.py export <pack.chr> <folder>
    python tools/chr/chrtool.py build <folder> <template.chr> <out.chr>

The toolkit lives at E:/dc1tk-blender (override with DC2TK=<path to dc2tk.exe>). Python 3.11, no packages needed.
"""

import json
import os
import struct
import subprocess
import sys

DC2TK = os.environ.get("DC2TK", "E:/dc1tk-blender/build/release/dc2tk.exe")


def run(*args):
    out = subprocess.run([DC2TK, *map(str, args)], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError("dc2tk %s failed:\n%s%s" % (args[0], out.stdout, out.stderr))
    return out.stdout


def export(pack, folder):
    """The pack as <folder>/<stem>.gltf + .bin + textures/; returns the glTF's path."""
    run("model-export", pack, folder)
    return next(os.path.join(folder, n) for n in os.listdir(folder) if n.endswith(".gltf"))


def build(folder, template, out):
    """A pack from an exported (and edited) folder, with `template` as the pack it is built on."""
    return run("model-build", folder, template, "-o", out)


def pack_entries(data):
    """A pack's members as (name field offset, data offset, size): a 64-byte name, then the data's offset from the
    entry, its size and the next entry's offset (moonanim.pack_members reads the same layout)."""
    off, out = 0, []
    while off + 76 <= len(data):
        name = data[off:off + 64].split(b"\0")[0]
        if not name:
            break
        o, size, nxt = struct.unpack_from("<iii", data, off + 64)
        out.append((name.decode("latin1"), off, off + o, size))
        if nxt < 76:
            break
        off += nxt
    return out


def _put_name(buf, at, width, name):
    if len(name) >= width:
        raise ValueError("%r does not fit a %d-byte name" % (name, width))
    buf[at:at + width] = name + b"\0" * (width - len(name))


def img_names(img):
    """The texture names of a DC1 .img: 'IMG\\0', a count, then 48-byte entries with the name at 16."""
    count = struct.unpack_from("<I", img, 4)[0]
    return [img[16 + 48 * i:16 + 48 * i + 32].split(b"\0")[0] for i in range(count)]


def derive(data, old="c01d", new="c07d", shadow_old="c01s", shadow_new="c07s"):
    """A copy of a character pack under new names, every file the same size: its members (c01d.mds -> c07d.mds),
    base.cfg's references, the .img's texture names and the meshes' material texture names (c01d03 -> c07d03), so
    the new character's textures never share a name with the old one's. Frame (bone) names stay: motions, weapons
    and moves find bones by them."""
    if len(old) != len(new) or len(shadow_old) != len(shadow_new):
        raise ValueError("the names must keep their length")
    swap = lambda b: b.replace(old.encode(), new.encode()).replace(shadow_old.encode(), shadow_new.encode())
    out = bytearray(data)
    textures = []
    for name, field, start, size in pack_entries(data):
        member = bytes(data[start:start + size])
        if name.lower().endswith(".img"):
            body = bytearray(member)
            for i, tex in enumerate(img_names(member)):
                textures.append(tex)
                _put_name(body, 16 + 48 * i, 32, swap(tex))
            member = bytes(body)
        out[start:start + size] = member
        _put_name(out, field, 64, swap(name.encode("latin1")))
    for name, field, start, size in pack_entries(bytes(out)):
        member = bytearray(out[start:start + size])
        if name.lower().endswith(".cfg"):
            member = bytearray(swap(bytes(member)))
        elif name.lower().endswith(".mds"):
            for tex in textures:
                at = member.find(tex + b"\0")
                while at >= 0:
                    member[at:at + len(tex)] = swap(tex)
                    at = member.find(tex + b"\0", at + 1)
        out[start:start + size] = member
    return bytes(out)


def rename_textures(data, mapping):
    """A pack with its pictures renamed (mapping old name -> new, bytes, the same length or shorter) in its .img and
    in its meshes' materials; members keep their names (a weapon's must keep the template's .cfg)."""
    out = bytearray(data)
    for name, field, start, size in pack_entries(data):
        member = bytearray(out[start:start + size])
        if name.lower().endswith(".img"):
            for i, tex in enumerate(img_names(bytes(member))):
                if tex in mapping:
                    _put_name(member, 16 + 48 * i, 32, mapping[tex])
        elif name.lower().endswith(".mds"):
            for old, new in mapping.items():
                at = member.find(old + b"\0")
                while at >= 0:
                    member[at:at + len(old) + 1] = new + b"\0" * (len(old) + 1 - len(new))
                    at = member.find(old + b"\0", at + 1)
        out[start:start + size] = member
    return bytes(out)


def strip_lines(data, tags):
    """base.cfg with every statement whose tag is in `tags` commented out in place (the file keeps its size)."""
    out = bytearray(data)
    for name, field, start, size in pack_entries(data):
        if name.lower() != "base.cfg":
            continue
        text = bytearray(out[start:start + size])
        at = 0
        while at < len(text):
            end = text.find(b"\n", at)
            end = len(text) if end < 0 else end
            line = bytes(text[at:end])
            if line.strip().split(b" ")[0].split(b"\t")[0] in tags:
                body = line.rstrip(b"\r")
                text[at:at + len(body)] = b"//" + b" " * (len(body) - 2) if len(body) >= 2 else body
            at = end + 1
        out[start:start + size] = text
    return bytes(out)


def cloth_meshes(pack_bytes):
    """The meshes a pack's cloth simulates: its base.cfg's ALLOC_MDT names. Each CLOTH .clo file drives one of them by
    vertex number, so a cloth mesh must keep its vertices (count and order) unless its .clo is rebuilt with it; a
    subdivided poncho comes out as a stretched bar."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "anim"))
    from moonanim import pack_members
    cfg = pack_members(pack_bytes).get("base.cfg", b"").decode("shift_jis", errors="replace")
    names = set()
    for line in cfg.splitlines():
        parts = line.split("//")[0].split()
        if len(parts) >= 2 and parts[0] == "ALLOC_MDT":
            names.add(parts[1].strip('";'))
    return names


# ---------------------------------------------------------------------------------------------------------------------
# glTF meshes

COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Gltf:
    """A glTF with one .bin buffer beside it, its accessors read as lists of tuples."""

    def __init__(self, path):
        self.path = path
        self.json = json.load(open(path, encoding="utf-8"))
        uri = self.json["buffers"][0]["uri"]
        self.bin = open(os.path.join(os.path.dirname(path), uri), "rb").read()
        self.data = [self._read(a) for a in self.json["accessors"]]

    def _read(self, a):
        view = self.json["bufferViews"][a["bufferView"]]
        fmt, n = COMPONENTS[a["componentType"]], WIDTH[a["type"]]
        size = struct.calcsize(fmt) * n
        stride = view.get("byteStride", size)
        off = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        return [struct.unpack_from("<%d%s" % (n, fmt), self.bin, off + i * stride) for i in range(a["count"])]

    def save(self, path=None):
        """Writes every accessor's data back, tightly packed, into a new buffer (and the glTF beside it)."""
        path = path or self.path
        stem = os.path.splitext(os.path.basename(path))[0]
        blob, views = bytearray(), []
        for i, (a, rows) in enumerate(zip(self.json["accessors"], self.data)):
            fmt, n = COMPONENTS[a["componentType"]], WIDTH[a["type"]]
            while len(blob) % 4:
                blob.append(0)
            start = len(blob)
            for row in rows:
                blob += struct.pack("<%d%s" % (n, fmt), *row)
            old = self.json["bufferViews"][a["bufferView"]]
            view = {"buffer": 0, "byteOffset": start, "byteLength": len(blob) - start}
            if "target" in old:
                view["target"] = old["target"]
            views.append(view)
            a["bufferView"], a["count"] = i, len(rows)
            a.pop("byteOffset", None)
            if a["componentType"] == 5126 and a["type"] != "MAT4" and rows:
                a["min"] = [min(r[k] for r in rows) for k in range(n)] if "min" in a else a.get("min")
                a["max"] = [max(r[k] for r in rows) for k in range(n)] if "max" in a else a.get("max")
                if a["min"] is None:
                    del a["min"], a["max"]
        self.json["bufferViews"] = views
        self.json["buffers"] = [{"uri": stem + ".bin", "byteLength": len(blob)}]
        folder = os.path.dirname(path)
        open(os.path.join(folder, stem + ".bin"), "wb").write(blob)
        json.dump(self.json, open(path, "w", encoding="utf-8"), indent=1)

    def primitives(self):
        for mesh in self.json["meshes"]:
            for p in mesh["primitives"]:
                yield mesh.get("name", ""), p

    def triangles(self, prim):
        """The primitive's triangles, each three corners of {attribute: value}."""
        attrs = {k: self.data[v] for k, v in prim["attributes"].items()}
        count = len(next(iter(attrs.values())))
        index = [i[0] for i in self.data[prim["indices"]]] if "indices" in prim else list(range(count))
        if prim.get("mode", 4) != 4:
            raise ValueError("only triangle lists are read")
        corner = lambda i: {k: v[i] for k, v in attrs.items()}
        return [tuple(corner(index[t + k]) for k in range(3)) for t in range(0, len(index) - 2, 3)]


def _mat(values):
    """A column-major glTF matrix as rows."""
    return [[values[c * 4 + r] for c in range(4)] for r in range(4)]


def _mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def _inverse(m):
    """A 4x4 inverse (Gauss-Jordan)."""
    a = [row[:] + [1.0 if r == c else 0.0 for c in range(4)] for r, row in enumerate(m)]
    for c in range(4):
        p = max(range(c, 4), key=lambda r: abs(a[r][c]))
        a[c], a[p] = a[p], a[c]
        pivot = a[c][c]
        a[c] = [x / pivot for x in a[c]]
        for r in range(4):
            if r != c and a[r][c]:
                f = a[r][c]
                a[r] = [x - f * y for x, y in zip(a[r], a[c])]
    return [row[4:] for row in a]


def _node_local(node):
    if "matrix" in node:
        return _mat(node["matrix"])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    tx, ty, tz = node.get("translation", [0, 0, 0])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[i][0] * sx, r[i][1] * sy, r[i][2] * sz, t] for i, t in enumerate((tx, ty, tz))] + [[0, 0, 0, 1]]


def _worlds(nodes, local_of):
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", ())}
    world = {}

    def of(i):
        if i not in world:
            world[i] = _mul(of(parent[i]), local_of(i)) if i in parent else local_of(i)
        return world[i]

    for i in range(len(nodes)):
        of(i)
    return world, parent


def bind_rest(g, bbp):
    """The export's skeleton placed at Dark Cloud 1's bind pose, for Blender. The .bbp holds a local matrix for each
    frame of the skin's chains (all zeros for attachment and mesh frames), multiplied down the hierarchy as
    MotionProc2 does; the toolkit writes them as world matrices (Dark Cloud 2's meaning), so its inverse bind matrices
    are near identity and Blender's bones heap up at the origin. Here a chain frame's node takes its .bbp local, every
    other frame keeps the world place the export gave it (its mesh is in model space), and the inverse bind matrices
    are the inverse of the world matrices: the bones stand where Toan's joints are and the skin is undeformed at rest.
    restore_rest gives the toolkit its own values back."""
    nodes = g.json["nodes"]
    count = len(bbp) // 64
    local_bbp = [_mat(struct.unpack_from("<16f", bbp, i * 64)) for i in range(count)]
    chain = [i < count and any(abs(x) > 1e-9 for row in local_bbp[i] for x in row) for i in range(len(nodes))]
    original, parent = _worlds(nodes, lambda i: _node_local(nodes[i]))
    world = {}

    def of(i):
        if i not in world:
            if chain[i]:
                world[i] = _mul(of(parent[i]), local_bbp[i]) if i in parent else local_bbp[i]
            else:
                world[i] = original[i]
        return world[i]

    for i, node in enumerate(nodes):
        local = _mul(_inverse(of(parent[i])), of(i)) if i in parent else of(i)
        for key in ("translation", "rotation", "scale"):
            node.pop(key, None)
        node["matrix"] = [local[r][c] for c in range(4) for r in range(4)]
    for skin in g.json.get("skins", ()):
        g.data[skin["inverseBindMatrices"]] = [
            tuple(m[r][c] for c in range(4) for r in range(4)) for m in (_inverse(of(j)) for j in skin["joints"])]


def restore_rest(g, template):
    """The toolkit's own skeleton back in a glTF made from bind_rest's (Blender's export): every node named as a
    template node takes the template's transform, and each skin's inverse bind matrices are the template's for the
    same joint names. The vertices need nothing: at rest both put them where they are, in model space. A rigid mesh
    (a mesh node without a skin, parented to a bone) keeps the world place it had."""
    nodes = g.json["nodes"]
    before, _ = _worlds(nodes, lambda i: _node_local(nodes[i]))
    by_name = {n.get("name"): n for n in template.json["nodes"]}
    tskin = template.json["skins"][0]
    tibm = {template.json["nodes"][j].get("name"): m
            for j, m in zip(tskin["joints"], template.data[tskin["inverseBindMatrices"]])}
    for node in g.json["nodes"]:
        source = by_name.get(node.get("name"))
        if source is None or "mesh" in node or "mesh" in source:
            continue
        for key in ("translation", "rotation", "scale", "matrix"):
            node.pop(key, None)
            if key in source:
                node[key] = source[key]
    for skin in g.json.get("skins", ()):
        names = [g.json["nodes"][j].get("name") for j in skin["joints"]]
        missing = [n for n in names if n not in tibm]
        if missing:
            raise ValueError("joints the template does not have: %s" % ", ".join(missing))
        g.data[skin["inverseBindMatrices"]] = [tibm[n] for n in names]
    after, parent = _worlds(nodes, lambda i: _node_local(nodes[i]))
    for i, node in enumerate(nodes):
        if "mesh" in node and "skin" not in node and i in parent:
            local = _mul(_inverse(after[parent[i]]), before[i])
            for key in ("translation", "rotation", "scale"):
                node.pop(key, None)
            node["matrix"] = [local[r][c] for c in range(4) for r in range(4)]


def move_joints(g, moves):
    """A character's own proportions on the template's skeleton: moves = {frame name: (dx, dy, dz)}, a world offset
    (glTF axes) for that frame and everything below it, given after restore_rest. The frame's translation changes in
    its parent's axes, and its inverse bind matrix with it: the toolkit's inverse bind matrix of a chain frame is the
    inverse of the frame's own local matrix (it writes the .bbp from them), checked here before anything changes.
    Returns {node index: (old translation, new translation)}; the pack's frame records take them after the build
    (set_frame_translations)."""
    nodes = g.json["nodes"]
    world, parent = _worlds(nodes, lambda i: _node_local(nodes[i]))
    ibms = []
    for skin in g.json.get("skins", ()):
        ibms.append((skin, [list(_mat(m)) for m in g.data[skin["inverseBindMatrices"]]]))
    moved = {}
    for i, node in enumerate(nodes):
        delta = moves.get(node.get("name"))
        if delta is None or "matrix" in node:
            continue
        r = [row[:3] for row in world[parent[i]][:3]] if i in parent else [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        local_delta = [sum(r[k][j] * delta[k] for k in range(3)) for j in range(3)]  # rotation's transpose
        for skin, mats in ibms:
            if i in skin["joints"]:
                at = skin["joints"].index(i)
                want = _inverse(_node_local(node))
                if any(abs(want[a][b] - mats[at][a][b]) > 1e-3 for a in range(4) for b in range(4)):
                    raise ValueError("%s: its inverse bind matrix is not its local matrix's inverse" % node["name"])
        before = list(node.get("translation", [0, 0, 0]))
        node["translation"] = [a + d for a, d in zip(before, local_delta)]
        moved[i] = (before, node["translation"])
        for skin, mats in ibms:
            if i in skin["joints"]:
                mats[skin["joints"].index(i)] = _inverse(_node_local(node))
    for skin, mats in ibms:
        g.data[skin["inverseBindMatrices"]] = [tuple(m[r][c] for c in range(4) for r in range(4)) for m in mats]
    return moved


def replace_member(data, name, member):
    """The pack with member `name` replaced by new bytes of any size: each entry is its 64-byte name, the data's offset
    (80), its size and the next entry's offset (the data padded to 16 bytes), 4 bytes kept as they were, then the
    data; an empty entry ends the pack."""
    entries = pack_entries(data)
    if name not in [e[0] for e in entries]:
        raise KeyError(name)
    out = bytearray()
    for n, at, start, size in entries:
        body = member if n == name else data[start:start + size]
        padded = (len(body) + 15) // 16 * 16
        head = bytearray(data[at:at + 80])
        struct.pack_into("<iii", head, 64, 80, len(body), 80 + padded)
        out += head + body + bytes(padded - len(body))
    last = entries[-1]
    out += data[last[2] + (last[3] + 15) // 16 * 16:]
    return bytes(out)


def set_frame_translations(data, mds, translations):
    """The pack's model frames' own translations (the toolkit rebuilds a frame's bind pose from the glTF but keeps the
    template's frame records): translations = {frame index: (old xyz, new xyz)} in member `mds` (an .mds: one
    112-byte record a frame, its translation at the record's start, the first record at 112). Each old value is
    checked before it is replaced."""
    buf = bytearray(data)
    entry = next(e for e in pack_entries(data) if e[0] == mds)
    for frame, (old, new) in translations.items():
        at = entry[2] + 112 * (frame + 1)
        have = struct.unpack_from("<3f", buf, at)
        if any(abs(a - b) > 1e-3 for a, b in zip(have, old)):
            raise ValueError("%s frame %d: translation %s, expected %s" % (mds, frame, have, old))
        struct.pack_into("<3f", buf, at, *new)
    return bytes(buf)


def unweld(g):
    """Every triangle gets three vertices of its own: the same shape, a different vertex layout."""
    for _, prim in g.primitives():
        tris = g.triangles(prim)
        for name, acc in prim["attributes"].items():
            g.data[acc] = [c[name] for t in tris for c in t]
        if "indices" in prim:
            g.data[prim["indices"]] = [(i,) for i in range(len(tris) * 3)]


def _centre(tri, name):
    values = [c[name] for c in tri]
    if name == "JOINTS_0" or name == "WEIGHTS_0":
        return values[0]  # the first corner's skin: an average could weigh more than four bones
    mean = [sum(v[k] for v in values) / 3.0 for k in range(len(values[0]))]
    if name == "NORMAL":
        length = sum(x * x for x in mean) ** 0.5 or 1.0
        mean = [x / length for x in mean]
    return tuple(mean)


def subdivide(g, skip=()):
    """Every triangle split in three around its centre (winding kept): a different surface, in place. Meshes named
    in `skip` keep theirs."""
    for name, prim in g.primitives():
        if name in skip:
            continue
        tris = g.triangles(prim)
        new = []
        for t in tris:
            mid = {name: _centre(t, name) for name in t[0]}
            new += [(t[0], t[1], mid), (t[1], t[2], mid), (t[2], t[0], mid)]
        for name, acc in prim["attributes"].items():
            g.data[acc] = [c[name] for t in new for c in t]
        g.data[prim["indices"]] = [(i,) for i in range(len(new) * 3)]


def surfaces(g):
    """{mesh name: triangles}, each corner a flat tuple of position, normal and UV with its skin as sorted
    (bone name, weight) pairs, the triangle turned to start at its smallest corner (winding kept)."""
    joints = None
    out = {}
    for name, prim in g.primitives():
        for tri in g.triangles(prim):
            corners = []
            for c in tri:
                values = tuple(c["POSITION"]) + tuple(c.get("NORMAL", ())) + tuple(c.get("TEXCOORD_0", ()))
                skin = ()
                if "JOINTS_0" in c:
                    joints = joints or g.json["skins"][0]["joints"]
                    names = [g.json["nodes"][joints[j]].get("name") for j in c["JOINTS_0"]]
                    skin = tuple(sorted((n, w) for n, w in zip(names, c["WEIGHTS_0"]) if w > 0.0005))
                corners.append((values, skin))
            k = corners.index(min(corners))
            out.setdefault(name, []).append(tuple(corners[k:] + corners[:k]))
    return out


def _close(a, b, tolerance, skin_tolerance):
    return any(_close_corners(a, b[k:] + b[:k], tolerance, skin_tolerance) for k in range(3))


def _close_corners(a, b, tolerance, skin_tolerance):
    for (va, sa), (vb, sb) in zip(a, b):
        if len(va) != len(vb) or any(abs(x - y) > tolerance for x, y in zip(va, vb)):
            return False
        wa, wb = dict(sa), dict(sb)
        if any(abs(wa.get(n, 0.0) - wb.get(n, 0.0)) > skin_tolerance for n in set(wa) | set(wb)):
            return False
    return True


def unmatched(a, b, tolerance=1e-4, skin_tolerance=0.002):
    """The triangles of `a` with no partner in `b` (each partner used once): positions, normals and UVs within
    `tolerance`, weights within `skin_tolerance`, winding kept. Float32 round trips move values by ~1e-7."""
    cell = lambda t: tuple(int(sum(c[0][k] for c in t) / 3 // 0.01) for k in range(3))
    buckets = {}
    for i, t in enumerate(b):
        buckets.setdefault(cell(t), []).append(i)
    used, missing = set(), []
    for t in a:
        cx, cy, cz = cell(t)
        found = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for i in buckets.get((cx + dx, cy + dy, cz + dz), ()):
                        if i not in used and _close(t, b[i], tolerance, skin_tolerance):
                            found = i
                            break
                    if found is not None:
                        break
                if found is not None:
                    break
            if found is not None:
                break
        if found is None:
            missing.append(t)
        else:
            used.add(found)
    return missing


def main(argv):
    if len(argv) >= 3 and argv[0] == "export":
        print(export(argv[1], argv[2]))
    elif len(argv) >= 4 and argv[0] == "build":
        print(build(argv[1], argv[2], argv[3]).strip())
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
