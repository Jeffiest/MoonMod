"""MoonMod animation editor: a local web page to pose and time Dark Cloud motions by hand.

python tools/anim/editor/server.py [--data <extracted game data>] [--play <play save>] [--port 8765] [--lan]

Serves the editor (index.html, editor.js) and, from the converted game data, every playable character's and
monster's model and native motions. Saving writes a moonmod-motion v1 file (what animations.player_register reads)
through moonanim's own bake and motion_document, so a file from the editor is the same kind of file as one from the
authoring scripts. Only 127.0.0.1 is served unless --lan opens it to your local network (a phone, a tablet, another
PC; anyone on that network can then open and save motions), and files are written only under the repository's mods/
and examples/.

Poses travel as glTF values in the rig's channel order: rotations (x, y, z, w), translations and scales (x, y, z).

The bridge (/api/bridge/...) carries commands from mcp_server.py to the open page and its answers back, so an
assistant poses and looks at the same page you are watching.

The reference endpoints (/api/ref/...) serve Elden Ring animations to watch beside the character, decoded by
tools/anim/reference from the player's own install and downloaded repositories into a cache outside the repository
(--reference, default %LOCALAPPDATA%/Moonmod/reference). They are only ever looked at; nothing of them is saved.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.dirname(HERE))
import moonanim as ma  # noqa: E402

PLAYERS = [("toan", "Toan"), ("xiao", "Xiao"), ("goro", "Goro"), ("ruby", "Ruby"), ("ungaga", "Ungaga"),
           ("osmond", "Osmond")]
EASES = (None, "in", "out", "inout")


class Catalog:
    """Every rig the editor can open: {id: entry}, and each opened rig cached."""

    def __init__(self, data):
        self.data = data
        self.entries = {}
        self.rigs = {}
        main = os.path.join(data, "dun", "mainchara")
        for cid, name in PLAYERS:
            pack = ma.PACKS[cid]
            self.add(cid, name, "Characters", cid, os.path.join(main, pack + ".chr"), os.path.join(main, pack + ".gltf"))
        # Opar: his pack ships in his mod; his glTF is a local build of the art (art/opar/build, not in git).
        self.add("opar", "Opar", "Characters", "opar", os.path.join(REPO, "mods", "moonmod.opar", "resources", "opar", "c07d.chr"),
                 os.path.join(REPO, "art", "opar", "build", "rig", "c07d.gltf"))
        if "opar" in self.entries:
            self.entries["opar"]["names"] = os.path.join(main, "c01d.game.json")  # his motion table is Toan's
        names = json.load(open(os.path.join(HERE, "monster_names.json"), encoding="utf-8"))
        monstor = os.path.join(data, "dun", "monstor")
        for chr_path in sorted(glob.glob(os.path.join(monstor, "*.chr"))):
            pack = os.path.basename(chr_path)[:-4]
            if pack.endswith("_") or pack.endswith("_s"):
                continue  # a backup the data keeps beside the real pack, or a beam's shadow (no motion of its own)
            name = names.get(pack)
            label = "%s (%s)" % (name, pack) if name else pack
            self.add(pack, label, "Monsters" if name else "Other models", pack, chr_path, os.path.join(monstor, pack + ".gltf"))

    def add(self, rid, name, group, character, chr_path, gltf_path):
        if os.path.exists(chr_path) and os.path.exists(gltf_path):
            self.entries[rid] = {"id": rid, "name": name, "group": group, "character": character, "chr": chr_path,
                                 "gltf": gltf_path}

    def rig(self, rid):
        if rid not in self.rigs:
            e = self.entries[rid]
            members = ma.pack_members(open(e["chr"], "rb").read())
            cfg = "base.cfg" if "base.cfg" in members else "info.cfg"
            rig = ma.Rig(e["chr"], e["gltf"], cfg_name=cfg)
            rig.motion_names = motion_names(members.get(cfg, b""), e.get("names") or e["gltf"][:-5] + ".game.json")
            self.rigs[rid] = rig
        return self.rigs[rid]


class Reference:
    """Elden Ring reference animations: the game's own (extracted into the cache) and every downloaded repository named
    in the cache's reference.json ({"exporter": ErReference.exe, "repositories": [folders]}). A group is the game's
    animation table or one repository folder; an animation is decoded the first time it is asked for and kept."""

    def __init__(self, cache):
        self.cache = cache
        self.roots = {}
        self.exporter = None
        config = os.path.join(cache or "", "reference.json")
        if not cache or not os.path.exists(config):
            return
        cfg = json.load(open(config, encoding="utf-8"))
        self.exporter = cfg.get("exporter")
        game = os.path.join(cache, "game")
        if os.path.isdir(game):
            self.roots["game"] = ("Elden Ring", game)
        for n, repo in enumerate(cfg.get("repositories", [])):
            if os.path.isdir(repo):
                self.roots["repo%d" % n] = (os.path.basename(os.path.normpath(repo)), repo)
        self.lock = threading.Lock()

    def available(self):
        return bool(self.exporter and os.path.exists(self.exporter) and self.roots)

    def groups(self):
        out = []
        for rid, (label, root) in self.roots.items():
            for name in sorted(os.listdir(root), key=str.lower):
                if os.path.isdir(os.path.join(root, name)):
                    out.append({"id": rid + "/" + name, "name": name, "source": label})
        return out

    def _dir(self, group):
        rid, _, name = group.partition("/")
        root = self.roots[rid][1]
        full = os.path.abspath(os.path.join(root, name))
        if os.path.dirname(full) != os.path.abspath(root) or not os.path.isdir(full):
            raise KeyError(group)
        return full

    def items(self, group):
        full = self._dir(group)
        found = []
        for here, _, files in os.walk(full):
            for f in files:
                if f.lower().endswith(".hkx"):
                    found.append(os.path.relpath(os.path.join(here, f), full).replace("\\", "/"))
        return sorted(found, key=lambda r: (os.path.basename(r).lower(), r.lower()))

    def decoded(self, group, rel):
        """The decoded animation's JSON (bytes), decoding it first if the cache doesn't have it yet."""
        base = self._dir(group)
        full = os.path.abspath(os.path.join(base, rel))
        if not full.startswith(base + os.sep) or not full.lower().endswith(".hkx") or not os.path.isfile(full):
            raise KeyError(rel)
        stamp = "%s|%d|%d" % (full.lower(), os.path.getsize(full), int(os.path.getmtime(full)))
        out = os.path.join(self.cache, "decoded", hashlib.sha1(stamp.encode("utf-8")).hexdigest() + ".json")
        with self.lock:
            if not os.path.exists(out):
                os.makedirs(os.path.dirname(out), exist_ok=True)
                run = subprocess.run([self.exporter, "decode", self.cache, full, out + ".part"], capture_output=True,
                                     text=True, timeout=120, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                if run.returncode != 0:
                    raise RuntimeError("couldn't decode %s: %s" % (rel, (run.stderr or run.stdout).strip()[-400:]))
                os.replace(out + ".part", out)
        with open(out, "rb") as f:
            return f.read()


def _plain(comment):
    """A cfg comment as game_names spells it: no spaces, no motion number before or after, one kind of long dash."""
    return re.sub(r"^\d+|\d+$", "", re.sub(r"\s+", "", comment)).replace("−", "ー").replace("－", "ー")


def motion_names(cfg_bytes, game_json):
    """Each native motion's name: the English id the converter gave its cfg comment (game.json's game_names), else
    the comment itself."""
    english = {}
    if game_json and os.path.exists(game_json):
        for key, value in json.load(open(game_json, encoding="utf-8")).get("game_names", {}).items():
            english[_plain(str(value.get("value", "")))] = key
    out = []
    for line in cfg_bytes.decode("shift_jis", errors="replace").splitlines():
        line = line.strip()
        if not line.startswith("KEY") or line.startswith("KEY_"):
            continue
        comment = line.split("//", 1)[1].strip() if "//" in line else ""
        out.append(english.get(_plain(comment), comment) or "(unnamed)")
    return out


def channel_value(pose, key):
    v = pose[key]
    return [round(float(x), 6) for x in v]


def native_frames(rig, motion):
    start, end, speed = rig.motions[motion]
    keys = [(c["bone"], ma.TYPES[c["type"]]) for c in rig.channels]
    frames = []
    for i in range(int(end - start) + 1):
        pose = rig.sample(start + i)
        frames.append({"frame": i, "values": [channel_value(pose, k) for k in keys]})
    return {"speed": speed or 0.5, "length": int(end - start), "frames": frames}


def document_frames(rig, doc):
    """A moonmod-motion document as frames of glTF values in the rig's channel order. Channels the document leaves
    out hold the rig's first native pose."""
    tracks = {(t["bone"], t["type"]): t["keys"] for t in doc.get("tracks", [])}
    rest = rig.sample(rig.motions[0][0]) if rig.motions else rig.sample(0)
    frames_at = sorted({k[0] for keys in tracks.values() for k in keys} or {0})

    def at(keys, f, kind):
        prev = keys[0]
        for k in keys:
            if k[0] <= f:
                prev = k
            else:
                u = (f - prev[0]) / ((k[0] - prev[0]) or 1)
                if kind == "rotation":
                    return ma.qslerp(ma.game_to_gltf(prev[1:5]), ma.game_to_gltf(k[1:5]), u)
                return tuple(a + (b - a) * u for a, b in zip(prev[1:4], k[1:4]))
        return ma.game_to_gltf(prev[1:5]) if kind == "rotation" else tuple(prev[1:4])

    frames = []
    for f in frames_at:
        values = []
        for c in rig.channels:
            key = (c["bone"], ma.TYPES[c["type"]])
            keys = tracks.get(key)
            values.append([round(float(x), 6) for x in (at(keys, f, key[1]) if keys else rest[key])])
        frames.append({"frame": f, "values": values})
    return {"speed": doc.get("speed", 0.5), "length": doc.get("length", frames_at[-1]), "frames": frames}


def motion_files(character):
    """The motion files in the repository's mods and examples made for `character`."""
    out = []
    for path in sorted(glob.glob(os.path.join(REPO, "mods", "*", "resources", "anims", "*.json")) +
                       glob.glob(os.path.join(REPO, "examples", "**", "*.json"), recursive=True)):
        try:
            with open(path, encoding="utf-8") as f:
                head = f.read(160)
            m = re.search(r'"character"\s*:\s*"([^"]+)"', head)
            if '"moonmod-motion"' in head and m and m.group(1) == character:
                out.append(os.path.relpath(path, REPO).replace("\\", "/"))
        except OSError:
            pass
    return out


def writable(rel):
    """A repository-relative .json path under mods/ or examples/, or None."""
    rel = rel.replace("\\", "/").lstrip("/")
    full = os.path.abspath(os.path.join(REPO, rel))
    inside = any(full.startswith(os.path.join(REPO, top) + os.sep) for top in ("mods", "examples"))
    return full if inside and full.endswith(".json") else None


class Bridge:
    """Commands for the open page. Each page (an id per load) long-polls next() and posts each answer to answer();
    call() queues a command and waits for its answer. A command can't outlive the page that took it: what a page was
    working on when it went away (bye()) or never received (lost()) fails, since a reloaded page holds none of its
    state and would apply the command to whatever motion it opened instead."""

    def __init__(self):
        self.cond = threading.Condition()
        self.queue = []
        self.taken = {}  # command id -> (page, command)
        self.answers = {}
        self.pages = {}  # page -> {"polls": open long-polls, "seen": time of the last}
        self.gone = set()
        self.last_id = 0

    def connected(self):
        now = time.time()
        live = [p for p, v in self.pages.items() if p not in self.gone and (v["polls"] or now - v["seen"] < 5)]
        return bool(live) or any(page not in self.gone for page, _ in self.taken.values())

    def next(self, page, wait=20):
        with self.cond:
            info = self.pages.setdefault(page, {"polls": 0, "seen": 0.0})
            info["polls"] += 1
            try:
                self.cond.wait_for(lambda: self.queue or page in self.gone, wait)
            finally:
                info["polls"] -= 1
                info["seen"] = time.time()
            if page in self.gone or not self.queue:
                return None
            cmd = self.queue.pop(0)
            self.taken[cmd["id"]] = (page, cmd)
            return cmd

    def bye(self, page):
        with self.cond:
            self.gone.add(page)
            self.pages.pop(page, None)
            for cid, (p, _) in list(self.taken.items()):
                if p == page:
                    self._fail(cid, "the page reloaded or closed during this command, and nothing it held is left; "
                                    "open the motion again (unsaved changes are gone)")

    def lost(self, cmd):
        """A command the page's long-poll was gone before it could receive."""
        with self.cond:
            self._fail(cmd["id"], "the page went away before it received this command; nothing was changed")

    def _fail(self, cid, message):
        if self.taken.pop(cid, None):
            self.answers[cid] = {"id": cid, "ok": False, "error": message}
            self.cond.notify_all()

    def answer(self, reply):
        with self.cond:
            if self.taken.pop(reply.get("id"), None):
                self.answers[reply["id"]] = reply
                self.cond.notify_all()

    def call(self, cmd, args, wait=90):
        """The page's answer {ok, result | error}, or None if no page is open."""
        with self.cond:
            if not self.connected():
                return None
            self.last_id += 1
            cid = self.last_id
            self.queue.append({"id": cid, "cmd": cmd, "args": args})
            self.cond.notify_all()
            self.cond.wait_for(lambda: cid in self.answers, wait)
            self.queue = [c for c in self.queue if c["id"] != cid]
            self.taken.pop(cid, None)
            return self.answers.pop(cid, None) or {"ok": False, "error": "the page didn't answer in %d s" % wait}


class Handler(BaseHTTPRequestHandler):
    catalog = None
    reference = Reference(None)
    play = None
    bridge = Bridge()

    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, kind="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def fail(self, code, message):
        self.send(code, {"error": message})

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        try:
            if url.path in ("/", "/index.html"):
                return self.static("index.html", "text/html; charset=utf-8")
            if url.path == "/editor.js":
                return self.static("editor.js", "text/javascript; charset=utf-8")
            if url.path == "/api/rigs":
                return self.send(200, [{k: e[k] for k in ("id", "name", "group")} for e in self.catalog.entries.values()])
            if url.path == "/api/rig":
                return self.rig_info(q["id"])
            if url.path == "/api/native":
                return self.send(200, native_frames(self.catalog.rig(q["id"]), int(q["motion"])))
            if url.path == "/api/load":
                full = writable(q["path"])
                if not full or not os.path.exists(full):
                    return self.fail(404, "no such motion file")
                return self.send(200, document_frames(self.catalog.rig(q["id"]), json.load(open(full, encoding="utf-8"))))
            if url.path == "/api/ref/groups":
                if not self.reference.available():
                    return self.send(200, {"available": False, "cache": self.reference.cache})
                return self.send(200, {"available": True, "groups": self.reference.groups()})
            if url.path == "/api/ref/items":
                return self.send(200, self.reference.items(q["group"]))
            if url.path == "/api/ref/anim":
                return self.send(200, self.reference.decoded(q["group"], q["path"]), "application/json")
            if url.path == "/api/bridge/next":
                cmd = self.bridge.next(q.get("page", ""))
                try:
                    return self.send(200, cmd) if cmd else self.send(204, b"")
                except OSError:  # the page left while it waited (a reload, a closed tab)
                    if cmd:
                        self.bridge.lost(cmd)
                    return None
            if url.path == "/api/bridge/state":
                return self.send(200, {"connected": self.bridge.connected()})
            if url.path.startswith("/model/"):
                return self.model(url.path[len("/model/"):])
            if url.path.startswith("/raw/"):
                return self.raw(url.path[len("/raw/"):])
            return self.fail(404, "not found")
        except KeyError as e:
            return self.fail(400, "missing or unknown " + str(e))
        except Exception as e:  # noqa: BLE001 (the page shows the message)
            return self.fail(500, "%s: %s" % (type(e).__name__, e))

    def do_POST(self):
        if self.headers.get("Origin") not in (None, *self.server.origins):
            return self.fail(403, "cross-origin request")
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            path = urllib.parse.urlparse(self.path).path
            if path == "/api/save":
                return self.save(body)
            if path == "/api/bridge/bye":
                self.bridge.bye(urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("page", [""])[0])
                return self.send(200, {})
            if path == "/api/bridge/result":
                self.bridge.answer(body)
                return self.send(200, {})
            if path == "/api/bridge/call":
                reply = self.bridge.call(body["cmd"], body.get("args") or {})
                if reply is None:
                    return self.fail(409, "no editor page is open")
                return self.send(200, reply)
            return self.fail(404, "not found")
        except Exception as e:  # noqa: BLE001
            return self.fail(500, "%s: %s" % (type(e).__name__, e))

    def static(self, name, kind):
        with open(os.path.join(HERE, name), "rb") as f:
            self.send(200, f.read(), kind)

    def rig_info(self, rid):
        e = self.catalog.entries[rid]
        rig = self.catalog.rig(rid)
        motions = []
        for i, (start, end, speed) in enumerate(rig.motions):
            name = rig.motion_names[i] if i < len(rig.motion_names) else ""
            motions.append({"index": i, "name": name, "start": start, "end": end, "speed": speed})
        channels = [{"node": c["frame"], "bone": c["bone"], "kind": ma.TYPES[c["type"]]} for c in rig.channels]
        self.send(200, {"id": rid, "name": e["name"], "group": e["group"], "character": e["character"],
                        "playable": e["group"] == "Characters", "model": "/model/" + rid + ".gltf",
                        "channels": channels, "motions": motions, "files": motion_files(e["character"])})

    def model(self, name):
        rid = name[:-5] if name.endswith(".gltf") else name
        e = self.catalog.entries[rid]
        g = json.load(open(e["gltf"], encoding="utf-8"))
        g.pop("animations", None)  # the native motions come from the pack, through /api/native
        # Only the model's own scene: the pack's shadow model is a second scene on its own nodes.
        g["scenes"] = [s for s in g["scenes"] if 0 in s["nodes"]] or g["scenes"][:1]
        g["scene"] = 0
        for item in g.get("buffers", []) + g.get("images", []):
            if "uri" in item and not item["uri"].startswith("data:"):
                # the whole relative path as one segment, so the browser doesn't fold its "../"
                item["uri"] = "/raw/" + rid + "/" + urllib.parse.quote(item["uri"], safe="")
        self.send(200, g, "model/gltf+json")

    def raw(self, rest):
        rid, _, rel = rest.partition("/")
        e = self.catalog.entries[rid]
        full = os.path.abspath(os.path.join(os.path.dirname(e["gltf"]), urllib.parse.unquote(rel)))
        roots = (os.path.abspath(self.catalog.data), REPO)
        if not any(full.startswith(r + os.sep) for r in roots) or not os.path.isfile(full):
            return self.fail(404, "not found")
        kind = "image/png" if full.endswith(".png") else "application/octet-stream"
        with open(full, "rb") as f:
            self.send(200, f.read(), kind)

    def save(self, body):
        rid = body["id"]
        e = self.catalog.entries[rid]
        rig = self.catalog.rig(rid)
        full = writable(body["path"])
        if not full:
            return self.fail(400, "save under mods/ or examples/, as a .json file")
        speed = float(body["speed"])
        if not 0.05 <= speed <= 4:
            return self.fail(400, "speed is 0.05 to 4")
        keys = sorted(body["keys"], key=lambda k: k["frame"])
        if not keys or keys[0]["frame"] != 0:
            return self.fail(400, "the motion needs a key at frame 0")
        channel_keys = [(c["bone"], ma.TYPES[c["type"]]) for c in rig.channels]
        poses = []
        for k in keys:
            if len(k["values"]) != len(channel_keys):
                return self.fail(400, "frame %d: %d channel values for %d channels" % (k["frame"], len(k["values"]), len(channel_keys)))
            pose = {key: tuple(v) for key, v in zip(channel_keys, k["values"])}
            ease = k.get("ease")
            poses.append((int(k["frame"]), pose, ease if ease in EASES else None))
        frames = ma.bake(poses) if len(poses) > 1 else [(0, poses[0][1])]
        doc = ma.motion_document(rig, e["character"], frames, speed)
        ma.write_json(full, doc)
        synced = []
        rel = os.path.relpath(full, REPO).replace("\\", "/")
        parts = rel.split("/")
        if self.play and body.get("sync", True) and parts[0] == "mods" and len(parts) > 2:
            target_mod = os.path.join(self.play, "mods", parts[1])
            if os.path.isdir(target_mod):
                target = os.path.join(target_mod, *parts[2:])
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.copyfile(full, target)
                synced.append(target)
        self.send(200, {"path": rel, "frames": len(frames), "length": doc["length"], "synced": synced,
                        "bytes": os.path.getsize(full)})


def lan_addresses():
    """This PC's IPv4 addresses on its local networks (the private ranges)."""
    import ipaddress
    import socket
    found = set()
    try:
        found.update(info[4][0] for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET))
    except OSError:
        pass
    try:  # the address the default route leaves from (nothing is sent)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("10.255.255.255", 1))
            found.add(probe.getsockname()[0])
    except OSError:
        pass
    return sorted(a for a in found if ipaddress.ip_address(a).is_private and not ipaddress.ip_address(a).is_loopback)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--data", default=os.environ.get("DC_DATA", "E:/Gauntlet-build/run/data"))
    p.add_argument("--play", default="E:/Gauntlet-build/play/save", help="a save folder whose mods get a copy of each save")
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--reference", default=os.environ.get("MOONANIM_REFERENCE") or
                   os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "Moonmod", "reference"),
                   help="the Elden Ring reference cache (tools/anim/reference)")
    p.add_argument("--lan", action="store_true", help="serve your local network too, not only this PC")
    args = p.parse_args()
    Handler.catalog = Catalog(args.data)
    Handler.reference = Reference(args.reference)
    Handler.play = args.play if os.path.isdir(args.play or "") else None
    server = ThreadingHTTPServer(("0.0.0.0" if args.lan else "127.0.0.1", args.port), Handler)
    hosts = ["127.0.0.1", "localhost"] + (lan_addresses() if args.lan else [])
    server.origins = ["http://%s:%d" % (h, args.port) for h in hosts]
    print("MoonMod animation editor: http://127.0.0.1:%d  (%d rigs)" % (args.port, len(Handler.catalog.entries)))
    for h in hosts[2:]:
        print("  on your network: http://%s:%d" % (h, args.port))
    server.serve_forever()


if __name__ == "__main__":
    main()
