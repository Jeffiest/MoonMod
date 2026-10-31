"""A weapon's own model (`commenu/weapon/<stem>.chr`, for `weapons.register{model = stem}`) from triangles made
elsewhere (art/opar/make_staffs.py), built on a template weapon's pack.

    python tools/chr/build_weapon.py <weapon folder> <template> <stem>.json [...] [--out <folder>]

<weapon folder> is the game data's commenu/weapon; <template> the template weapon's pack stem (c01w05 for template
262, Toan's sixth sword: held in the right hand). For each <stem>.json (triangles: "p" position, "n" normal, "uv"
per corner, in the pack's space: the hand at the origin) and the <stem>.png beside it (the template picture's size):

1. the template's picture is renamed <stem> in its .img and its mesh's materials (the members keep their names: the
   game reads the template's .cfg from the pack);
2. the template is exported, its first mesh replaced by the triangles and the others removed (dc2tk_remove), its
   picture replaced by <stem>.png;
3. the toolkit builds <out>/<stem>.chr, and it is checked: exported again, its triangles are the given ones.

The template's hit points (its dcol frames) stay where they are.
"""

import argparse
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import chrtool  # noqa: E402


def build(folder, template, source, out_dir):
    spec = json.load(open(source))
    stem = spec["stem"]
    if len(stem) > len(template) or not stem.isalnum():
        raise SystemExit("%s: a stem of up to %d letters and digits" % (stem, len(template)))
    retail = open(os.path.join(folder, template + ".chr"), "rb").read()
    renamed = chrtool.rename_textures(retail, {template.encode(): stem.encode()})
    work = tempfile.mkdtemp(prefix="weapon-")
    base = os.path.join(work, "template.chr")
    open(base, "wb").write(renamed)
    exported = chrtool.export(base, os.path.join(work, "model"))
    g = chrtool.Gltf(exported)
    mesh_nodes = [n for n in g.json["nodes"] if "mesh" in n]
    first = mesh_nodes[0]
    for n in mesh_nodes[1:]:
        # marked for removal, its mesh changed to one small triangle (the toolkit rebuilds only changed meshes)
        n["extras"] = {"dc2tk_remove": True}
        for pr in g.json["meshes"][n["mesh"]]["primitives"]:
            for name, acc in pr["attributes"].items():
                g.data[acc] = g.data[acc][:3]
            g.data[pr["attributes"]["POSITION"]] = [(0.0, 0.0, 0.0), (0.01, 0.0, 0.0), (0.0, 0.01, 0.0)]
            if "indices" in pr:
                g.data[pr["indices"]] = [(0,), (1,), (2,)]
    prim = g.json["meshes"][first["mesh"]]["primitives"][0]
    g.json["meshes"][first["mesh"]]["primitives"] = [prim]
    tris = spec["triangles"]
    attrs = prim["attributes"]
    g.data[attrs["POSITION"]] = [tuple(c["p"]) for t in tris for c in t]
    g.data[attrs["NORMAL"]] = [tuple(c["n"]) for t in tris for c in t]
    g.data[attrs["TEXCOORD_0"]] = [tuple(c["uv"]) for t in tris for c in t]
    if "indices" in prim:
        g.data[prim["indices"]] = [(i,) for i in range(len(tris) * 3)]
    g.save()
    png = os.path.splitext(source)[0] + ".png"
    shutil.copy(png, os.path.join(work, "model", "textures", stem + ".png"))
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, stem + ".chr")
    chrtool.build(os.path.join(work, "model"), base, out)
    # check: the pack exported again has the given triangles
    again = chrtool.export(out, os.path.join(work, "again"))
    got = [t for name, t_list in chrtool.surfaces(chrtool.Gltf(again)).items() for t in t_list]
    want = [t for name, t_list in chrtool.surfaces(g).items() if name == g.json["meshes"][first["mesh"]].get("name")
            for t in t_list]
    degenerate = lambda t: len({tuple(round(x, 4) for x in c[0][:3]) for c in t}) < 3
    want = [t for t in want if not degenerate(t)]
    missing = chrtool.unmatched(want, got, tolerance=2e-3)
    size = os.path.getsize(out)
    print("%s: %d triangles, %d in the pack, %d unmatched, %d bytes" % (stem, len(want), len(got), len(missing), size))
    shutil.rmtree(work, ignore_errors=True)
    return not missing and size <= 2 * 1024 * 1024


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("folder")
    p.add_argument("template")
    p.add_argument("sources", nargs="+")
    p.add_argument("--out", default=os.path.join(HERE, "..", "..", "art", "opar", "build", "weapons"))
    args = p.parse_args(argv)
    ok = all([build(args.folder, args.template, s, args.out) for s in args.sources])
    print("ALL PASS" if ok else "SOME FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
