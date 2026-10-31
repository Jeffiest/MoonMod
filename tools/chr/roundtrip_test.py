"""Round trip of a character pack through glTF: proof that a pack can be rebuilt from an edited model.

    python tools/chr/roundtrip_test.py <mainchara folder> [pack, default c01d] [work folder]

1. Unchanged: export and build back; the pack must come out byte for byte the game's.
2. Rebuilt: every triangle of every mesh split in three around its centre, so the toolkit must write the mesh, skin
   weights and bind pose anew (it keeps a mesh whose surface is unchanged). Cloth meshes (ALLOC_MDT, simulated by the
   pack's .clo files, which name their vertices by number) are left as they are: see chrtool.cloth_meshes. The rebuilt pack is exported again and must
   have exactly the split triangles, normals, UVs and skin weights, and every member besides the model, weights and
   pose must be unchanged.

Writes <work>/<pack>_rebuilt.chr for the in-game check (tools/chr/README.md).
"""

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "anim"))
import chrtool  # noqa: E402
from moonanim import pack_members, parse_mot  # noqa: E402


def check(ok, message):
    print(("PASS " if ok else "FAIL ") + message)
    return ok


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    folder, pack = argv[0], argv[1] if len(argv) > 1 else "c01d"
    work = argv[2] if len(argv) > 2 else tempfile.mkdtemp(prefix="chr-rt-")
    original = os.path.join(folder, pack + ".chr")
    retail = open(original, "rb").read()
    ok = True

    plain = os.path.join(work, "export")
    shutil.rmtree(plain, ignore_errors=True)
    chrtool.export(original, plain)
    same = os.path.join(work, pack + "_same.chr")
    chrtool.build(plain, original, same)
    ok &= check(open(same, "rb").read() == retail, "unchanged export builds back byte for byte")

    edited = os.path.join(work, "subdivided")
    shutil.rmtree(edited, ignore_errors=True)
    shutil.copytree(plain, edited)
    gltf_name = next(n for n in os.listdir(edited) if n.endswith(".gltf"))
    g = chrtool.Gltf(os.path.join(edited, gltf_name))
    before = sum(len(g.data[p["attributes"]["POSITION"]]) for _, p in g.primitives())
    cloth = chrtool.cloth_meshes(retail)
    print("cloth meshes kept as they are:", ", ".join(sorted(cloth)) or "none")
    chrtool.subdivide(g, skip=cloth)
    g.save()
    expected = chrtool.surfaces(chrtool.Gltf(os.path.join(edited, gltf_name)))
    after = sum(len(g.data[p["attributes"]["POSITION"]]) for _, p in g.primitives())
    print("subdivided: %d corners -> %d" % (before, after))

    rebuilt = os.path.join(work, pack + "_rebuilt.chr")
    print(chrtool.build(edited, original, rebuilt).strip())
    data = open(rebuilt, "rb").read()
    ok &= check(data != retail, "the subdivided model is rebuilt (the pack changed)")

    a, b = pack_members(retail), pack_members(data)
    stem = os.path.splitext(gltf_name)[0]
    rewritten = {stem + ".mds", stem + ".wgt", stem + ".bbp"}
    ok &= check(set(a) == set(b), "the same members (%d)" % len(a))
    for name in sorted(a):
        if name in rewritten:
            print("     %-16s %7d -> %7d bytes%s" % (name, len(a[name]), len(b.get(name, b"")),
                                                     "" if a[name] != b.get(name) else " (unchanged)"))
        else:
            ok &= check(a[name] == b.get(name), "%s unchanged" % name)

    # Dark Cloud 1 skins a mesh by walking its weight lists in order, a list for every bone on the way (keys or none)
    order = lambda wgt: [(c["frame"], c["target"]) for c in parse_mot(wgt)]
    ok &= check(order(a[stem + ".wgt"]) == order(b[stem + ".wgt"]),
                "weight lists name the same bones in the same order (%d lists)" % len(order(a[stem + ".wgt"])))

    again = os.path.join(work, "again")
    shutil.rmtree(again, ignore_errors=True)
    chrtool.export(rebuilt, again)
    sig_a = expected
    sig_b = chrtool.surfaces(chrtool.Gltf(os.path.join(again, gltf_name)))
    ok &= check(sorted(sig_a) == sorted(sig_b), "the same %d meshes" % len(sig_a))
    for name in sorted(sig_a):
        got = sig_b.get(name, [])
        missing = chrtool.unmatched(sig_a[name], got)
        same_mesh = not missing and len(got) == len(sig_a[name])
        ok &= check(same_mesh, "mesh %-10s %4d triangles: positions, normals, UVs%s match" %
                    (name, len(sig_a[name]), " and skin weights" if name == "skin" else ""))
        if missing:
            print("     %d unmatched, first: %s" % (len(missing), missing[0]))
    print("rebuilt pack:", rebuilt)
    print("ALL PASS" if ok else "SOME FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
