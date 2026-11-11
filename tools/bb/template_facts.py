"""What a Dark Cloud monster's pack (.chr) and its exported glTF hold, as plain text to paste into a chat.

    python tools/bb/template_facts.py <pack.chr> <exported folder>

The folder is what `python tools/chr/chrtool.py export <pack.chr> <folder>` wrote: one <stem>.gltf, its .bin and a
textures/ folder of PNG files. Read only: nothing is changed. Python 3.11+, standard library only.
"""

import json
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "chr"))
import chrtool  # noqa: E402  (pack_entries reads a pack's members)

COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _label(obj, i):
    return obj.get("name") or str(i)


def _node_name(nodes, i):
    return nodes[i].get("name") or "node%d" % i


class Gltf:
    """A glTF with its .bin buffers beside it; accessors are read as lists of tuples."""

    def __init__(self, path):
        with open(path, encoding="utf-8") as f:
            self.doc = json.load(f)
        folder = os.path.dirname(path)
        self.buffers = []
        for b in self.doc.get("buffers", []):
            with open(os.path.join(folder, b["uri"]), "rb") as f:
                self.buffers.append(f.read())
        self._cache = {}

    def accessor(self, index):
        if index not in self._cache:
            a = self.doc["accessors"][index]
            view = self.doc["bufferViews"][a["bufferView"]]
            fmt, n = COMPONENTS[a["componentType"]], WIDTH[a["type"]]
            size = struct.calcsize("<" + fmt) * n
            stride = view.get("byteStride", size)
            off = view.get("byteOffset", 0) + a.get("byteOffset", 0)
            buf = self.buffers[view.get("buffer", 0)]
            self._cache[index] = [
                struct.unpack_from("<%d%s" % (n, fmt), buf, off + i * stride) for i in range(a["count"])
            ]
        return self._cache[index]

    def roots(self):
        nodes = self.doc.get("nodes", [])
        scenes = self.doc.get("scenes")
        if scenes:
            return list(scenes[self.doc.get("scene", 0)].get("nodes", []))
        children = {c for n in nodes for c in n.get("children", [])}
        return [i for i in range(len(nodes)) if i not in children]


def find_gltf(folder):
    """The first .gltf in the folder (by name), or None."""
    if not os.path.isdir(folder):
        return None
    names = sorted(n for n in os.listdir(folder) if n.endswith(".gltf"))
    return os.path.join(folder, names[0]) if names else None


def _translation(node):
    if "translation" in node:
        return node["translation"]
    if "matrix" in node:
        m = node["matrix"]
        return [m[12], m[13], m[14]]
    return None


def node_lines(g):
    nodes = g.doc.get("nodes", [])
    meshes = g.doc.get("meshes", [])
    out, seen = [], set()

    def walk(i, depth):
        if i in seen:
            return
        seen.add(i)
        node = nodes[i]
        parts = [_node_name(nodes, i)]
        if "mesh" in node:
            parts.append("mesh=" + _label(meshes[node["mesh"]], node["mesh"]))
        if "skin" in node:
            parts.append("skin")
        t = _translation(node)
        if t and any(v != 0 for v in t):
            parts.append("t=(%s)" % ", ".join("%.3f" % v for v in t))
        out.append("  " * depth + " ".join(parts))
        for c in node.get("children", []):
            walk(c, depth + 1)

    for r in g.roots():
        walk(r, 0)
    return out


def skin_lines(g):
    nodes = g.doc.get("nodes", [])
    out = []
    for i, s in enumerate(g.doc.get("skins", [])):
        joints = [_node_name(nodes, j) for j in s.get("joints", [])]
        out.append(("skin %d: %d joints: %s" % (i, len(joints), ", ".join(joints))).rstrip())
    return out


def primitive_lines(g):
    doc = g.doc
    out, total_v, total_t = [], 0, 0
    for mi, mesh in enumerate(doc.get("meshes", [])):
        for pi, p in enumerate(mesh.get("primitives", [])):
            attrs = p.get("attributes", {})
            pos = g.accessor(attrs["POSITION"])
            vertices = len(pos)
            if "indices" in p:
                triangles = len(g.accessor(p["indices"])) // 3
            else:
                triangles = vertices // 3
            skinned = "JOINTS_0" in attrs
            max_joints = 0
            if skinned and "WEIGHTS_0" in attrs:
                for w in g.accessor(attrs["WEIGHTS_0"]):
                    max_joints = max(max_joints, sum(1 for x in w if x > 0))
            acc = doc["accessors"][attrs["POSITION"]]
            lo, hi = acc.get("min"), acc.get("max")
            if lo is None or hi is None:
                lo = [min(c) for c in zip(*pos)] if pos else [0.0] * 3
                hi = [max(c) for c in zip(*pos)] if pos else [0.0] * 3
            bounds = " ".join("%s %.3f..%.3f" % (axis, lo[k], hi[k]) for k, axis in enumerate("xyz"))
            material = "-"
            if "material" in p:
                material = _label(doc["materials"][p["material"]], p["material"])
            out.append(
                "%s [%d]: %d vertices, %d triangles, material=%s, skinned=%s, max joints per vertex=%d, bounds %s"
                % (_label(mesh, mi), pi, vertices, triangles, material, "yes" if skinned else "no",
                   max_joints, bounds)
            )
            total_v += vertices
            total_t += triangles
    out.append("total: %d vertices, %d triangles" % (total_v, total_t))
    return out


def material_lines(g):
    doc = g.doc
    textures, images = doc.get("textures", []), doc.get("images", [])
    out = []
    for i, m in enumerate(doc.get("materials", [])):
        uri = "-"
        base = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if base is not None:
            tex = textures[base["index"]]
            if "source" in tex:
                uri = images[tex["source"]].get("uri", "-")
        out.append("%s: image=%s" % (_label(m, i), uri))
    return out


def texture_lines(folder):
    tex_dir = os.path.join(folder, "textures")
    if not os.path.isdir(tex_dir):
        return []
    out = []
    for name in sorted(n for n in os.listdir(tex_dir) if n.lower().endswith(".png")):
        with open(os.path.join(tex_dir, name), "rb") as f:
            head = f.read(24)
        if len(head) == 24 and head[:8] == PNG_SIGNATURE:
            width, height = struct.unpack(">II", head[16:24])
            out.append("%s: %d x %d" % (name, width, height))
        else:
            out.append("%s: not a PNG" % name)
    return out


def animation_lines(g):
    doc = g.doc
    out = []
    for i, an in enumerate(doc.get("animations", [])):
        maxes = []
        for s in an.get("samplers", []):
            acc = doc["accessors"][s["input"]]
            if acc.get("max"):
                maxes.append(acc["max"][0])
        duration = max(maxes) if maxes else 0.0
        out.append("%s: %d channels, %.3f s" % (_label(an, i), len(an.get("channels", [])), duration))
    return out


def cfg_sections(members, data):
    out = []
    for name, _, doff, size in members:
        if not name.endswith(".cfg"):
            continue
        text = data[doff:doff + size].decode("shift_jis", errors="replace")
        out.append("== cfg %s" % name)
        for line in text.splitlines():
            line = line.rstrip()
            if line:
                out.append("  " + line)
    return out


def _statements(text):
    """(COMMAND, first argument) for each cfg statement; `//` comments, `;` and quotes are dropped. The
    semicolon is optional: real DC1 cfg lines are written both ways."""
    for line in text.splitlines():
        tokens = line.split("//", 1)[0].split()
        if not tokens:
            continue
        arg = tokens[1].rstrip(";").strip('"') if len(tokens) > 1 else ""
        yield tokens[0].upper(), arg


def skinned_mesh_names(cfg_texts):
    """Mesh names the pack's cfgs mark as skinned: in a cfg with a VERTEX_ANIME whose argument is not 0, every
    ALLOC_DBUFF's argument, in the order found, without repeats."""
    names = []
    for text in cfg_texts:
        stmts = list(_statements(text))
        on = False
        for cmd, arg in stmts:
            if cmd == "VERTEX_ANIME":
                try:
                    on = on or int(arg) != 0
                except ValueError:
                    pass
        if not on:
            continue
        for cmd, arg in stmts:
            if cmd == "ALLOC_DBUFF" and arg and arg not in names:
                names.append(arg)
    return names


def _has_skin_weights(g):
    return any("JOINTS_0" in p.get("attributes", {})
               for m in g.doc.get("meshes", []) for p in m.get("primitives", []))


def facts(pack_path, folder):
    """The whole text report for a pack and its exported folder, as one string."""
    with open(pack_path, "rb") as f:
        data = f.read()
    members = chrtool.pack_entries(data)
    gltf_path = find_gltf(folder)
    if gltf_path is None:
        raise FileNotFoundError("no .gltf in %s" % folder)
    g = Gltf(gltf_path)

    lines = ["== pack %s: %d members, %d bytes" % (
        os.path.basename(pack_path), len(members), sum(size for _, _, _, size in members))]
    lines += ["%s  %d" % (name, size) for name, _, _, size in members]
    lines += cfg_sections(members, data)

    nodes = node_lines(g)
    lines.append("== nodes: %d" % len(nodes))
    lines += nodes

    skins = skin_lines(g)
    lines.append("== skins: %d" % len(skins))
    lines += skins

    prims = primitive_lines(g)
    lines.append("== meshes: %d" % (len(prims) - 1))
    lines += prims
    cfg_texts = [data[doff:doff + size].decode("shift_jis", errors="replace")
                 for name, _, doff, size in members if name.endswith(".cfg")]
    skinned = skinned_mesh_names(cfg_texts)
    if skinned and not _has_skin_weights(g):
        lines.append("warning: the pack's cfg skins %s (VERTEX_ANIME, ALLOC_DBUFF) but this export has no skin "
                     "weights: the dc2tk that wrote it does not export them" % ", ".join(skinned))

    materials = material_lines(g)
    lines.append("== materials: %d" % len(materials))
    lines += materials

    textures = texture_lines(folder)
    lines.append("== textures: %d" % len(textures))
    lines += textures

    animations = animation_lines(g)
    lines.append("== animations: %d" % len(animations))
    lines += animations
    return "\n".join(lines) + "\n"


def main(argv):
    if len(argv) != 2:
        print("usage: template_facts.py <pack.chr> <exported folder>", file=sys.stderr)
        return 2
    pack, folder = argv
    if not os.path.isfile(pack):
        print("no such pack: %s" % pack, file=sys.stderr)
        return 1
    if not os.path.isdir(folder):
        print("no such folder: %s" % folder, file=sys.stderr)
        return 1
    if find_gltf(folder) is None:
        print("no .gltf in %s" % folder, file=sys.stderr)
        return 1
    print(facts(pack, folder), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
