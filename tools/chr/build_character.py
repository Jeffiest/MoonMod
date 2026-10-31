"""A new playable character's pack from its Blender file, built on a template character (Opar: c07d on Toan's c01d).

    python tools/chr/build_character.py start <mainchara folder> [--art art/opar]
    python tools/chr/build_character.py build <mainchara folder> [--art art/opar] [--out <pack.chr>]

start: the template pack renamed (chrtool.derive), exported with its rest at the bind pose (chrtool.bind_rest), and
       the starting Blender file <art>/<name>.blend made from it (blender/start_character.py), with a blockout body,
       its texture in <art>/textures and the concept picture (<art>/concept.*) as a reference. It will not overwrite
       an existing .blend.
build: the .blend's "Character" collection exported (blender/export_character.py) and built on the template:
       its meshes replace the template's by frame name, and every template mesh it does not give is removed
       (dc2tk_remove); with the cloth meshes gone, base.cfg's CLOTH and ALLOC_MDT lines are commented out. The
       textures are the template's, with <art>/textures/<name>.png in place of each it gives. Writes
       <art>/build/<pack>.chr (or --out).

Blender: BLENDER=<path to blender.exe> (default Blender 5.2's). The toolkit: DC2TK (see chrtool).
"""

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import chrtool  # noqa: E402

BLENDER = os.environ.get("BLENDER", "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe")
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

# The characters made this way: name -> (template pack, its shadow, the new pack, its shadow).
CHARACTERS = {"opar": ("c01d", "c01s", "c07d", "c07s")}


def blender(*args):
    out = subprocess.run([BLENDER, *map(str, args)], capture_output=True, text=True)
    lines = [l for l in out.stdout.splitlines() + out.stderr.splitlines()
             if l.startswith(("START", "EXPORTED", "Error", "Traceback")) or "Error:" in l]
    if out.returncode != 0 or any(l.startswith(("Error", "Traceback")) or "Error:" in l for l in lines):
        raise RuntimeError("blender failed:\n" + "\n".join(out.stdout.splitlines()[-30:] + out.stderr.splitlines()[-30:]))
    return lines


def template(mainchara, art, name):
    old, old_shadow, new, new_shadow = CHARACTERS[name]
    retail = open(os.path.join(mainchara, old + ".chr"), "rb").read()
    path = os.path.join(art, "build", new + "_template.chr")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(chrtool.derive(retail, old, new, old_shadow, new_shadow))
    return path, new


def bbp_of(pack_path):
    sys.path.insert(0, os.path.join(HERE, "..", "anim"))
    from moonanim import pack_members
    members = pack_members(open(pack_path, "rb").read())
    return next(data for name, data in members.items() if name.endswith(".bbp") and not name.endswith("s.bbp"))


def start(args):
    art, name = os.path.abspath(args.art), os.path.basename(os.path.abspath(args.art))
    blend = os.path.join(art, name + ".blend")
    if os.path.exists(blend):
        raise SystemExit("%s exists; move it away to start again" % blend)
    path, pack = template(args.mainchara, art, name)
    rest = os.path.join(art, "build", "rest")
    shutil.rmtree(rest, ignore_errors=True)
    gltf = chrtool.export(path, rest)
    g = chrtool.Gltf(gltf)
    chrtool.bind_rest(g, bbp_of(path))
    g.save()
    concept = (glob.glob(os.path.join(art, "concept.*")) or [""])[0]
    os.environ["CHR_PACK"] = pack
    for line in blender("-b", "--factory-startup", "--python", os.path.join(HERE, "blender", "start_character.py"),
                        "--", gltf, os.path.join(art, "textures"), concept, blend):
        print(line)


def frame_of(node):
    name = node.get("name", "")
    if "." in name and name.rsplit(".", 1)[1].isdigit():
        name = name.rsplit(".", 1)[0]
    if "skin" in node and name.endswith("_skin"):
        name = name[:-5]
    return name


def mark_removed(g, template_frames):
    """A removal node (extras.dc2tk_remove) under the bone of every template mesh frame the export has no mesh for."""
    nodes = g.json["nodes"]
    given = {frame_of(n) for n in nodes if "mesh" in n}
    gone = sorted(f for f in template_frames if f not in given)
    if not gone:
        return gone
    accessors = g.json["accessors"]
    # one small triangle for the removal nodes to carry (never built)
    g.data.append([(0.0, 0.0, 0.0), (0.01, 0.0, 0.0), (0.0, 0.01, 0.0)])
    accessors.append({"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
                      "min": [0, 0, 0], "max": [0.01, 0.01, 0]})
    mesh = len(g.json["meshes"])
    g.json["meshes"].append({"name": "dc2tk_removed", "primitives": [{"attributes": {"POSITION": len(accessors) - 1}}]})
    bones = {n.get("name"): i for i, n in enumerate(nodes) if "mesh" not in n}
    for frame in gone:
        if frame not in bones:
            raise SystemExit("the export has no bone %r to remove a mesh from" % frame)
        nodes.append({"name": frame, "mesh": mesh, "extras": {"dc2tk_remove": True}})
        nodes[bones[frame]].setdefault("children", []).append(len(nodes) - 1)
    return gone


def build(args):
    art, name = os.path.abspath(args.art), os.path.basename(os.path.abspath(args.art))
    blend = os.path.join(art, name + ".blend")
    path, pack = template(args.mainchara, art, name)
    work = os.path.join(art, "build", "export")
    shutil.rmtree(work, ignore_errors=True)
    exported = chrtool.export(path, os.path.join(art, "build", "template"))
    template_frames = {frame_of(n) for n in json.load(open(exported, encoding="utf-8"))["nodes"] if "mesh" in n}
    os.makedirs(work)
    gltf = os.path.join(work, pack + ".gltf")
    for line in blender("-b", blend, "--python", os.path.join(HERE, "blender", "export_character.py"), "--", gltf):
        print(line)
    g = chrtool.Gltf(gltf)
    chrtool.restore_rest(g, chrtool.Gltf(exported))
    proportions = os.path.join(art, "proportions.json")
    if os.path.exists(proportions):
        moves = json.load(open(proportions))["move"]
        # Blender's axes (Z up, the left +X) to glTF's (Y up)
        moved = chrtool.move_joints(g, {n: (d[0], d[2], -d[1]) for n, d in moves.items()})
        print("proportions: %d frames moved (%s)" % (len(moved), ", ".join(sorted(moves))))
    else:
        moved = {}
    gone = mark_removed(g, template_frames)
    g.save()
    print("removed template meshes:", ", ".join(gone) or "none")
    shutil.copytree(os.path.join(os.path.dirname(exported), "textures"), os.path.join(work, "textures"))
    for png in glob.glob(os.path.join(art, "textures", "*.png")):
        target = os.path.join(work, "textures", os.path.basename(png))
        if not os.path.exists(target):
            raise SystemExit("%s names no texture of the pack" % png)
        shutil.copy(png, target)
    out = args.out or os.path.join(art, "build", pack + ".chr")
    print(chrtool.build(work, path, out).strip())
    data = open(out, "rb").read()
    if moved:
        # the model's frames (the first skeleton in the export; the shadow keeps the template's)
        names = [n.get("name") for n in json.load(open(exported, encoding="utf-8"))["nodes"]]
        frames = {names.index(g.json["nodes"][i]["name"]): v for i, v in moved.items()}
        data = chrtool.set_frame_translations(data, pack + ".mds", frames)
        open(out, "wb").write(data)
    motions = os.path.join(art, "build", pack + ".mot")
    if os.path.exists(motions):
        # his own motions (tools/anim/opar_moves.py), kept from the last time they were made
        data = chrtool.replace_member(data, pack + ".mot", open(motions, "rb").read())
        open(out, "wb").write(data)
        print("motions:", motions)
    shadow = CHARACTERS[name][3]
    shadow_motions = os.path.join(art, "build", shadow + ".mot")
    if os.path.exists(shadow_motions):
        # and his shadow's, made from them
        data = chrtool.replace_member(data, shadow + ".mot", open(shadow_motions, "rb").read())
        open(out, "wb").write(data)
    cloth = chrtool.cloth_meshes(data)
    if cloth and cloth <= set(gone):
        data = chrtool.strip_lines(data, {b"CLOTH", b"ALLOC_MDT"})
        open(out, "wb").write(data)
        print("cloth removed: CLOTH and ALLOC_MDT commented out")
    print("built", out, len(data), "bytes")


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("command", choices=("start", "build"))
    p.add_argument("mainchara", help="the game data's dun/mainchara folder")
    p.add_argument("--art", default=os.path.join(ROOT, "art", "opar"))
    p.add_argument("--out")
    args = p.parse_args(argv)
    start(args) if args.command == "start" else build(args)


if __name__ == "__main__":
    main(sys.argv[1:])
