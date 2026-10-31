"""MoonMod motion authoring: Dark Cloud character motions as moonmod-motion JSON.

Reads a character pack (.chr) and its converted glTF (for the bone names), samples poses from the character's own
motions, lets a script pose bones on top of them, and writes:

- a moonmod-motion v1 file (what animations.player_register reads), every rotation/translation channel of the
  character's motion file keyed at the authored frames, rotations as the game stores them (w, -x, -y, -z of the glTF
  quaternion);
- stick-figure contact sheets (front and side) of any poses, computed from the rig, to check a motion in seconds;
- a glTF of the character with only the new action (preview_gltf), for tools that read glTF actions.

Also converts a glTF action (a Blender export of the character's rig) into a moonmod-motion file.

Conventions, checked against the converter (tools/anim/README.md): glTF node i is model frame i; glTF rotations are
(x, y, z, w) of the node's local rotation; the game key is (w, -x, -y, -z); translations are the same in both; an
action's time t is frame (t * 30) from its start.
"""

import base64
import copy
import json
import math
import os
import struct

# ---------------------------------------------------------------------------------------------------------------------
# Quaternions, glTF order (x, y, z, w)


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qnorm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def qaxis(axis, degrees):
    x, y, z = axis
    n = math.sqrt(x * x + y * y + z * z) or 1.0
    h = math.radians(degrees) / 2
    s = math.sin(h) / n
    return (x * s, y * s, z * s, math.cos(h))


def qslerp(a, b, t):
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b = tuple(-c for c in b)
        dot = -dot
    if dot > 0.9995:
        return qnorm(tuple(x + (y - x) * t for x, y in zip(a, b)))
    th = math.acos(min(1.0, dot))
    s = math.sin(th)
    wa = math.sin((1 - t) * th) / s
    wb = math.sin(t * th) / s
    return tuple(wa * x + wb * y for x, y in zip(a, b))


def game_to_gltf(v):
    w, x, y, z = v[:4]
    return qnorm((-x, -y, -z, w))


def gltf_to_game(q):
    x, y, z, w = q
    return (w, -x, -y, -z)


# ---------------------------------------------------------------------------------------------------------------------
# Packs and motion files


def pack_members(data):
    off, out = 0, {}
    while off + 76 <= len(data):
        name = data[off:off + 64].split(b"\0")[0].decode("latin1")
        if not name:
            break
        o, size, nxt = struct.unpack_from("<iii", data, off + 64)
        out[name] = data[off + o:off + o + size]
        if nxt < 76:
            break
        off += nxt
    return out


def parse_mot(data):
    channels, off = [], 0
    while True:
        frame, target, typ, _, count, more = struct.unpack_from("<IIiIII", data, off)
        off += 32
        keys = []
        for _ in range(count):
            f = struct.unpack_from("<I", data, off)[0]
            keys.append((f, struct.unpack_from("<4f", data, off + 16)))
            off += 32
        channels.append({"frame": frame, "target": target, "type": typ, "keys": keys})
        if more == 0:
            return channels


TYPES = {0: "rotation", 1: "scale", 2: "translation"}


def open_rig(folder, pack):
    """The rig of one character pack in a converted data folder (dun/mainchara): open_rig(folder, "c04b")."""
    return Rig(os.path.join(folder, pack + ".chr"), os.path.join(folder, pack + ".gltf"))


# The playable characters' dungeon packs and the names the engine and the motion files use.
PACKS = {"toan": "c01d", "xiao": "c04b", "goro": "c06b", "ruby": "c05a", "ungaga": "c10b", "osmond": "c18a"}


class Rig:
    """A character's motion channels with their bone names, and the native motion table."""

    def __init__(self, chr_path, gltf_path, mot_name=None, cfg_name="base.cfg"):
        members = pack_members(open(chr_path, "rb").read())
        if mot_name is None:
            # the model's motion file; the other one (c01s.mot, c06s.mot...) is the shadow's. Goro's pack c06b holds
            # c06a.mot, so the name doesn't always follow the pack's.
            mot_name = next(n for n in members if n.endswith(".mot") and not n.endswith("s.mot"))
        self.mot_name = mot_name
        self.channels = [c for c in parse_mot(members[mot_name]) if c["type"] in TYPES]
        self.gltf_path = gltf_path
        self.gltf = json.load(open(gltf_path, encoding="utf-8"))
        names = [n.get("name") for n in self.gltf["nodes"]]
        for c in self.channels:
            c["bone"] = names[c["frame"]]
        self.names = names
        self.motions = []
        cfg = members.get(cfg_name, b"").decode("shift_jis", errors="replace")
        for line in cfg.splitlines():
            parts = line.strip().replace(",", " ").split()
            if len(parts) >= 4 and parts[0] == "KEY":
                try:
                    self.motions.append((int(parts[1]), int(parts[2]), float(parts[3])))
                except ValueError:
                    pass

    def channel(self, bone, kind="rotation"):
        for c in self.channels:
            if c["bone"] == bone and TYPES[c["type"]] == kind:
                return c
        return None

    def sample(self, frame):
        """The pose at a (fractional) native frame: {(bone, kind): value}, rotations as glTF quaternions."""
        pose = {}
        for c in self.channels:
            keys = c["keys"]
            prev = keys[0]
            nxt = None
            for k in keys:
                if k[0] <= frame:
                    prev = k
                else:
                    nxt = k
                    break
            kind = TYPES[c["type"]]
            if nxt is None or prev[0] == frame or prev[0] > frame:
                v = prev[1]
                pose[(c["bone"], kind)] = game_to_gltf(v) if kind == "rotation" else tuple(v[:3])
                continue
            t = (frame - prev[0]) / (nxt[0] - prev[0])
            if kind == "rotation":
                pose[(c["bone"], kind)] = qslerp(game_to_gltf(prev[1]), game_to_gltf(nxt[1]), t)
            else:
                pose[(c["bone"], kind)] = tuple(a + (b - a) * t for a, b in zip(prev[1][:3], nxt[1][:3]))
        return pose

    def motion_frame(self, motion, at=0.0):
        """A native frame inside motion number `motion`: `at` 0 is its first frame, 1 its last."""
        start, end, _ = self.motions[motion]
        return start + (end - start) * at


# ---------------------------------------------------------------------------------------------------------------------
# Authoring


def pose_from(rig, base, turns=None, moves=None, scale=1.0):
    """A pose: the rig's pose at native frame `base`, with `turns` = {bone: [(axis, degrees), ...]} applied in each
    bone's own frame (after its pose), and `moves` = {bone: (dx, dy, dz)} added to its translation."""
    pose = dict(rig.sample(base))
    for bone, list_ in (turns or {}).items():
        key = (bone, "rotation")
        if key not in pose:
            raise KeyError("no rotation channel for " + bone)
        q = pose[key]
        for axis, degrees in list_:
            q = qnorm(qmul(q, qaxis(axis, degrees * scale)))
        pose[key] = q
    for bone, delta in (moves or {}).items():
        key = (bone, "translation")
        if key not in pose:
            raise KeyError("no translation channel for " + bone)
        pose[key] = tuple(a + d for a, d in zip(pose[key], delta))
    return pose


def blend(a, b, t):
    out = {}
    for key, va in a.items():
        vb = b.get(key, va)
        out[key] = qslerp(va, vb, t) if key[1] == "rotation" else tuple(x + (y - x) * t for x, y in zip(va, vb))
    return out


def ease(t, kind):
    if kind == "in":
        return t * t
    if kind == "out":
        return 1 - (1 - t) * (1 - t)
    if kind == "inout":
        return t * t * (3 - 2 * t)
    return t


def bake(keyposes, step=1):
    """Keyposes [(frame, pose, ease)] -> a pose for every `step` frames, eased between keyposes."""
    frames = []
    for (f0, p0, _), (f1, p1, e) in zip(keyposes, keyposes[1:]):
        for f in range(f0, f1, step):
            frames.append((f, blend(p0, p1, ease((f - f0) / (f1 - f0), e))))
    frames.append((keyposes[-1][0], keyposes[-1][1]))
    return frames


def motion_document(rig, character, frames, speed=0.5):
    """Baked frames [(frame, pose)] -> a moonmod-motion v1 document."""
    length = frames[-1][0]
    tracks = []
    for c in rig.channels:
        kind = TYPES[c["type"]]
        key = (c["bone"], kind)
        keys = []
        for f, pose in frames:
            v = pose[key]
            if kind == "rotation":
                keys.append([f] + [round(x, 6) for x in gltf_to_game(v)])
            else:
                keys.append([f] + [round(x, 5) for x in v])
        tracks.append({"bone": c["bone"], "type": kind, "keys": keys})
    return {"format": "moonmod-motion", "version": 1, "character": character, "length": length, "speed": speed,
            "tracks": tracks}


def write_json(path, doc):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, separators=(",", ":"))


# ---------------------------------------------------------------------------------------------------------------------
# glTF: previews out, Blender actions in


def preview_gltf(rig, doc, path, name):
    """The rig's glTF with only `doc` as its animation, its bytes in a second (embedded) buffer."""
    g = copy.deepcopy(rig.gltf)
    base_dir = os.path.dirname(os.path.abspath(rig.gltf_path))
    for b in g["buffers"] + g.get("images", []):
        if "uri" in b and not b["uri"].startswith("data:"):
            b["uri"] = os.path.normpath(os.path.join(base_dir, b["uri"])).replace("\\", "/")
    # Only the model's own scene (the pack's shadow model is a second scene on its own nodes).
    g["scenes"] = [s for s in g["scenes"] if 0 in s["nodes"]] or g["scenes"][:1]
    g["scene"] = 0
    blob = bytearray()
    # The model's own frames come first; a shadow model in the same glTF reuses the bone names.
    index = {}
    for i, n in enumerate(rig.names):
        index.setdefault(n, i)

    def add_accessor(values, kind):
        off = len(blob)
        for v in values:
            blob.extend(struct.pack("<%df" % len(v), *v))
        while len(blob) % 4:
            blob.append(0)
        g["bufferViews"].append({"buffer": len(g["buffers"]), "byteOffset": off, "byteLength": len(blob) - off})
        acc = {"bufferView": len(g["bufferViews"]) - 1, "componentType": 5126, "count": len(values), "type": kind}
        if kind == "SCALAR":
            acc["min"] = [min(v[0] for v in values)]
            acc["max"] = [max(v[0] for v in values)]
        g["accessors"].append(acc)
        return len(g["accessors"]) - 1

    anim = {"name": name, "channels": [], "samplers": []}
    for t in doc["tracks"]:
        times = add_accessor([(k[0] / 30.0,) for k in t["keys"]], "SCALAR")
        if t["type"] == "rotation":
            values = add_accessor([game_to_gltf(k[1:5]) for k in t["keys"]], "VEC4")
        else:
            values = add_accessor([tuple(k[1:4]) for k in t["keys"]], "VEC3")
        anim["samplers"].append({"input": times, "output": values, "interpolation": "LINEAR"})
        anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": index[t["bone"]], "path": t["type"]}})
    g["animations"] = [anim]
    g["buffers"].append({"byteLength": len(blob), "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(blob)).decode()})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(g, f)


class GltfFile:
    def __init__(self, path):
        self.j = json.load(open(path, encoding="utf-8"))
        self.dir = os.path.dirname(os.path.abspath(path))
        self.buffers = []
        for b in self.j["buffers"]:
            uri = b.get("uri", "")
            if uri.startswith("data:"):
                self.buffers.append(base64.b64decode(uri.split(",", 1)[1]))
            else:
                self.buffers.append(open(os.path.join(self.dir, uri), "rb").read())

    def accessor(self, i):
        a = self.j["accessors"][i]
        bv = self.j["bufferViews"][a["bufferView"]]
        n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 4 * n)
        data = self.buffers[bv["buffer"]]
        return [struct.unpack_from("<%df" % n, data, off + k * stride) for k in range(a["count"])]


def action_to_document(rig, gltf_path, action, character, speed=0.5, step=1):
    """A glTF action (by name) on the rig's bones -> a moonmod-motion document sampled every `step` frames. Bones the
    action leaves alone hold the pose of the rig's first native frame."""
    g = GltfFile(gltf_path)
    anim = next(a for a in g.j["animations"] if a.get("name") == action)
    names = [n.get("name") for n in g.j["nodes"]]
    curves = {}
    length = 0
    for ch in anim["channels"]:
        bone, kind = names[ch["target"]["node"]], ch["target"]["path"]
        if kind not in ("rotation", "translation"):
            continue
        s = anim["samplers"][ch["sampler"]]
        times = [t[0] for t in g.accessor(s["input"])]
        values = g.accessor(s["output"])
        curves[(bone, kind)] = (times, values)
        length = max(length, round(times[-1] * 30))
    rest = rig.sample(rig.motions[0][0])

    def at(curve, t, kind):
        times, values = curve
        if t <= times[0]:
            return values[0]
        for k in range(1, len(times)):
            if times[k] >= t:
                u = (t - times[k - 1]) / ((times[k] - times[k - 1]) or 1)
                if kind == "rotation":
                    return qslerp(values[k - 1], values[k], u)
                return tuple(a + (b - a) * u for a, b in zip(values[k - 1], values[k]))
        return values[-1]

    frames = []
    for f in list(range(0, length, step)) + [length]:
        pose = dict(rest)
        for key, curve in curves.items():
            if key in pose:
                pose[key] = at(curve, f / 30.0, key[1])
        frames.append((f, pose))
    return motion_document(rig, character, frames, speed)


# ---------------------------------------------------------------------------------------------------------------------
# Previews without a renderer: forward kinematics and stick figures (front and side), written as PNG


def qrot(q, v):
    x, y, z, w = q
    vx, vy, vz = v
    # v + 2w(q x v) + 2 q x (q x v)
    cx, cy, cz = y * vz - z * vy, z * vx - x * vz, x * vy - y * vx
    cx2, cy2, cz2 = y * cz - z * cy, z * cx - x * cz, x * cy - y * cx
    return (vx + 2 * (w * cx + cx2), vy + 2 * (w * cy + cy2), vz + 2 * (w * cz + cz2))


def matrix_rotation(m):
    """The rotation of a glTF node matrix (column-major) as a quaternion (x, y, z, w), its scale divided out. Toan's
    left shoulder (chn9) keeps its turn here. A mirrored matrix (a hand point) has no rotation to give: identity."""
    cols = [m[0:3], m[4:7], m[8:11]]
    lens = [math.sqrt(sum(v * v for v in c)) or 1.0 for c in cols]
    c = [[v / n for v in col] for col, n in zip(cols, lens)]
    det = (c[0][0] * (c[1][1] * c[2][2] - c[2][1] * c[1][2]) - c[1][0] * (c[0][1] * c[2][2] - c[2][1] * c[0][2]) +
           c[2][0] * (c[0][1] * c[1][2] - c[1][1] * c[0][2]))
    if det <= 0:
        return (0.0, 0.0, 0.0, 1.0)
    r = lambda row, col: c[col][row]  # noqa: E731
    tr = r(0, 0) + r(1, 1) + r(2, 2)
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        q = ((r(2, 1) - r(1, 2)) / s, (r(0, 2) - r(2, 0)) / s, (r(1, 0) - r(0, 1)) / s, 0.25 * s)
    elif r(0, 0) > r(1, 1) and r(0, 0) > r(2, 2):
        s = math.sqrt(1.0 + r(0, 0) - r(1, 1) - r(2, 2)) * 2
        q = (0.25 * s, (r(0, 1) + r(1, 0)) / s, (r(0, 2) + r(2, 0)) / s, (r(2, 1) - r(1, 2)) / s)
    elif r(1, 1) > r(2, 2):
        s = math.sqrt(1.0 + r(1, 1) - r(0, 0) - r(2, 2)) * 2
        q = ((r(0, 1) + r(1, 0)) / s, 0.25 * s, (r(1, 2) + r(2, 1)) / s, (r(0, 2) - r(2, 0)) / s)
    else:
        s = math.sqrt(1.0 + r(2, 2) - r(0, 0) - r(1, 1)) * 2
        q = ((r(0, 2) + r(2, 0)) / s, (r(1, 2) + r(2, 1)) / s, 0.25 * s, (r(1, 0) - r(0, 1)) / s)
    return qnorm(q)


def fk(rig, pose):
    """World positions of the model's nodes (glTF space, Y up, the character facing +Z) for a pose."""
    nodes = rig.gltf["nodes"]
    out = {}

    def visit(i, rot, pos):
        n = nodes[i]
        name = n.get("name")
        if "matrix" in n:
            t = tuple(n["matrix"][12:15])
            r = matrix_rotation(n["matrix"])
        else:
            t = tuple(n.get("translation", (0, 0, 0)))
            r = tuple(n.get("rotation", (0, 0, 0, 1)))
        t = pose.get((name, "translation"), t)
        r = pose.get((name, "rotation"), r)
        wpos = tuple(a + b for a, b in zip(pos, qrot(rot, t)))
        wrot = qnorm(qmul(rot, r))
        out[i] = (name, wpos, wrot)
        for c in n.get("children", []):
            visit(c, wrot, wpos)

    visit(0, (0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0))
    return out


def _png(path, width, height, rgb):
    import zlib
    raw = b"".join(b"\0" + bytes(rgb[y * width * 3:(y + 1) * width * 3]) for y in range(height))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) +
                chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


# Toan's bone names, then Xiao's (her right arm jnt20/21, legs jnt25-27 and jnt3-5; she shares jnt9/10, jnt5, jnt12).
LIMB_COLORS = [(("jnt16", "jnt17", "jnt18", "chn16", "chn17", "chn18", "eff16", "eff17", "eff18", "r_",
                 "jnt20", "jnt21", "chn20", "chn21", "eff20", "eff21"), (230, 80, 60)),
               (("jnt8", "jnt9", "jnt10", "chn8", "chn9", "chn10", "eff8", "eff9", "eff10", "l_hand", "item"), (70, 140, 240)),
               (("jnt22", "jnt23", "jnt24", "chn22", "chn23", "chn24", "eff22", "eff23", "eff24", "footr",
                 "jnt25", "jnt26", "jnt27", "chn25", "chn26", "chn27", "eff25", "eff26", "eff27"), (240, 160, 60)),
               (("jnt5", "jnt6", "jnt7", "chn5", "chn6", "chn7", "eff5", "eff6", "eff7", "footl",
                 "jnt3", "jnt4", "chn3", "chn4", "eff3", "eff4"), (90, 200, 220)),
               (("jnt11", "jnt12", "chn11", "chn12", "eff11", "eff12", "face", "boushi"), (120, 220, 120))]


def _color(name):
    for prefixes, c in LIMB_COLORS:
        if name and name.startswith(prefixes):
            return c
    return (225, 225, 225)


def stick_sheet(rig, poses, path, cell=180, scale=7.0, labels=None):
    """A contact sheet of stick figures: one column per pose, rows front (looking at his face) and side (his right).
    The sword is drawn from the weapon bone to the hit point (dcol), in gold."""
    cols, rows = len(poses), 2
    width, height = cols * cell, rows * int(cell * 1.3)
    img = bytearray([34, 32, 30] * width * height)
    ch = int(cell * 1.3)

    def put(x, y, c):
        if 0 <= x < width and 0 <= y < height:
            o = (y * width + x) * 3
            img[o:o + 3] = bytes(c)

    def line(a, b, c, thick=2):
        (x0, y0), (x1, y1) = a, b
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for s in range(steps + 1):
            t = s / steps
            x, y = int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t))
            for dx in range(-thick // 2, thick - thick // 2):
                for dy in range(-thick // 2, thick - thick // 2):
                    put(x + dx, y + dy, c)

    nodes = rig.gltf["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    for col, pose in enumerate(poses):
        world = fk(rig, pose)
        for row in range(rows):
            ox, oy = col * cell + cell // 2, row * ch + int(ch * 0.85)

            def proj(p):
                x, y, z = p
                # front: facing him (he faces +Z, his right, -X, on our left); side: from his right, ahead to our right
                return (ox + x * scale, oy - y * scale) if row == 0 else (ox + z * scale, oy - y * scale)

            line((col * cell, oy), ((col + 1) * cell - 1, oy), (70, 66, 60), 1)
            for i, (name, pos, _) in world.items():
                p = parent.get(i)
                if p is None or p not in world or name in ("skin",) or "mesh" in nodes[i]:
                    continue
                line(proj(world[p][1]), proj(pos), _color(name))
            names = {v[0]: v[1] for v in world.values()}
            if "weapon" in names and "dcol" in names:
                w, d = names["weapon"], names["dcol"]
                tip = tuple(w[k] + (d[k] - w[k]) * 2.2 for k in range(3))
                line(proj(w), proj(tip), (250, 215, 80), 3)
    _png(path, width, height, img)


# ---------------------------------------------------------------------------------------------------------------------
# World-space posing: aim a bone, bend a leg to a foot target, turn the body. Space is glTF's: Y up, the character
# facing +Z, his right -X. Each helper edits a pose in place and returns it.


def _sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def _add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def _scale(a, k):
    return tuple(x * k for x in a)


def _len(a):
    return math.sqrt(sum(x * x for x in a))


def _unit(a):
    n = _len(a) or 1.0
    return tuple(x / n for x in a)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def qconj(q):
    return (-q[0], -q[1], -q[2], q[3])


def qbetween(a, b):
    """The shortest rotation taking direction a to direction b."""
    a, b = _unit(a), _unit(b)
    d = _dot(a, b)
    if d < -0.9999:
        axis = _cross(a, (1, 0, 0)) if abs(a[0]) < 0.9 else _cross(a, (0, 1, 0))
        return qaxis(axis, 180)
    c = _cross(a, b)
    return qnorm((c[0], c[1], c[2], 1 + d))


def _node(rig, name):
    for i, n in enumerate(rig.names):
        if n == name:
            return i
    raise KeyError(name)


def _parents(rig):
    parent = {}
    for i, n in enumerate(rig.gltf["nodes"]):
        for c in n.get("children", []):
            parent.setdefault(c, i)
    return parent


def world_turn(rig, pose, bone, q_world):
    """Turns a bone by a world-space rotation (its children follow)."""
    world = fk(rig, pose)
    i = _node(rig, bone)
    p = _parents(rig).get(i)
    parent_rot = world[p][2] if p is not None else (0.0, 0.0, 0.0, 1.0)
    new_world = qnorm(qmul(q_world, world[i][2]))
    pose[(bone, "rotation")] = qnorm(qmul(qconj(parent_rot), new_world))
    return pose


def aim(rig, pose, bone, tip, direction):
    """Turns `bone` so the segment from it to `tip` (a descendant) points along a world direction."""
    world = fk(rig, pose)
    cur = _sub(world[_node(rig, tip)][1], world[_node(rig, bone)][1])
    return world_turn(rig, pose, bone, qbetween(cur, direction))


def body(rig, pose, yaw=0.0, pitch=0.0, roll=0.0, drop=0.0, ahead=0.0, side=0.0, root="chn1", center="ctr"):
    """The whole body above the hips: yaw (left +), pitch (lean forward +), roll (lean to his right +), and the
    pelvis moved down by `drop`, ahead by `ahead`, to his left by `side` (feet are re-placed by legs())."""
    q = qmul(qaxis((0, 1, 0), yaw), qmul(qaxis((1, 0, 0), pitch), qaxis((0, 0, 1), -roll)))
    world_turn(rig, pose, root, q)
    t = pose[(center, "translation")]
    pose[(center, "translation")] = (t[0] + side, t[1] - drop, t[2] + ahead)
    return pose


def leg(rig, pose, hip, knee, ankle, foot_target, knee_hint):
    """Two-bone IK: the thigh (hip) and shin (knee) bend so the ankle reaches foot_target, the knee toward knee_hint
    (a world direction)."""
    world = fk(rig, pose)
    h = world[_node(rig, hip)][1]
    k = world[_node(rig, knee)][1]
    a = world[_node(rig, ankle)][1]
    l1, l2 = _len(_sub(k, h)), _len(_sub(a, k))
    to = _sub(foot_target, h)
    d = min(_len(to), (l1 + l2) * 0.999)
    to = _scale(_unit(to), d)
    # the knee: along `to` by x, and out toward the hint by y
    x = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    y = math.sqrt(max(0.0, l1 * l1 - x * x))
    hint = _unit(knee_hint)
    perp = _unit(_sub(hint, _scale(_unit(to), _dot(hint, _unit(to)))))
    knee_pos = _add(h, _add(_scale(_unit(to), x), _scale(perp, y)))
    aim(rig, pose, hip, knee, _sub(knee_pos, h))
    aim(rig, pose, knee, ankle, _sub(_add(h, to), knee_pos))
    return pose


def joint(rig, pose, name):
    return fk(rig, pose)[_node(rig, name)][1]
