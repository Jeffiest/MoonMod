"""Checks the motion pipeline against the game's own data.

python tools/anim/verify.py <dun/mainchara folder> <anims folder> [character]

character: toan (default), xiao, goro, ruby, ungaga or osmond.

1. Conventions: every native motion of the character's, sampled by moonanim and written as a moonmod-motion document, gives
   back the motion file's own keys at their frames (rotations and translations within 1e-5).
2. glTF in: the converter's glTF action for every native motion, read back by action_to_document, matches the motion
   file at the action's frames within 1e-3 (the path a Blender export takes).
3. The authored animations: each file in the folder made for that character is a valid moonmod-motion v1 document,
   keys every rotation and translation channel of the character's motion file, its frames rise from 0 to its length, its rotations are unit quaternions,
   and its first pose is within reach of a native pose (no snap when it starts), or of a pose of another of the
   character's authored animations (a follow-up, such as a slash out of a roll).
Exits non-zero on a failure.
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moonanim as ma  # noqa: E402

failures = []


def check(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok:
        failures.append(what)


def same_rotation(a, b, tol):
    # q and -q are the same rotation
    return min(max(abs(x - y) for x, y in zip(a, b)), max(abs(x + y) for x, y in zip(a, b))) <= tol


def main():
    data, anims = sys.argv[1], sys.argv[2]
    character = sys.argv[3] if len(sys.argv) > 3 else "toan"
    pack = ma.PACKS[character]
    rig = ma.open_rig(data, pack)
    print("%s (%s): %d channels, %d native motions" % (character, pack, len(rig.channels), len(rig.motions)))

    print("1. conventions (motion file -> document -> motion file)")
    worst = 0.0
    for n, (start, end, _) in enumerate(rig.motions):
        if end <= start:
            continue
        doc = ma.motion_document(rig, character, [(f - start, rig.sample(f)) for f in range(start, end + 1)])
        tracks = {(t["bone"], t["type"]): t for t in doc["tracks"]}
        for c in rig.channels:
            kind = ma.TYPES[c["type"]]
            keys = {k[0]: k for k in tracks[(c["bone"], kind)]["keys"]}
            for f, v in c["keys"]:
                if start <= f <= end:
                    got = keys[f - start][1:]
                    if kind == "rotation":
                        err = 0.0 if same_rotation(got, v, 1e-5) else max(abs(x - y) for x, y in zip(got, v))
                    else:
                        err = max(abs(x - y) for x, y in zip(got, v[:3]))
                    worst = max(worst, err)
    check(worst <= 1e-5, "every native key comes back (largest difference %.2g)" % worst)

    print("2. glTF in (converter action -> document -> motion file)")
    names = {a.get("name") for a in rig.gltf["animations"]}
    sidecar = json.load(open(os.path.join(data, pack + ".game.json"), encoding="utf-8"))
    actions = []
    for anim in sidecar.get("resources", {}).get("animations", []):
        for act in anim.get("actions", []):
            # the actions cut by the motion table's KEY lines (not the whole-timeline entries)
            if act.get("name") in names and (act.get("start"), act.get("end")) in {(m[0], m[1]) for m in rig.motions} and act["end"] > act["start"]:
                actions.append(act)
    worst, tested = 0.0, 0
    for act in actions[:len(rig.motions)]:
        try:
            doc = ma.action_to_document(rig, os.path.join(data, pack + ".gltf"), act["name"], character)
        except StopIteration:
            continue
        tested += 1
        tracks = {(t["bone"], t["type"]): t for t in doc["tracks"]}
        for c in rig.channels:
            kind = ma.TYPES[c["type"]]
            keys = {k[0]: k for k in tracks[(c["bone"], kind)]["keys"]}
            for f, v in c["keys"]:
                rel = f - act["start"]
                if 0 < rel < doc["length"] and rel in keys:
                    got = keys[rel][1:]
                    if kind == "rotation":
                        err = 0.0 if same_rotation(got, v, 1e-3) else max(abs(x - y) for x, y in zip(got, v))
                    else:
                        err = max(abs(x - y) for x, y in zip(got, v[:3]))
                    worst = max(worst, err)
    check(tested > 0 and worst <= 1e-3, "%d converter actions read back (largest difference %.2g)" % (tested, worst))

    print("3. authored animations")
    natives = [rig.sample(f) for f in sorted({f for s, e, _ in rig.motions for f in range(s, e + 1)})]
    for name in sorted(os.listdir(anims)):
        if not name.endswith(".json"):
            continue
        doc = json.load(open(os.path.join(anims, name), encoding="utf-8"))
        if doc.get("character") != character:
            continue
        ok = doc.get("format") == "moonmod-motion" and doc.get("version") == 1
        check(ok, name + ": a moonmod-motion v1 document for " + character)
        have = {(t["bone"], t["type"]) for t in doc["tracks"]}
        need = {(c["bone"], ma.TYPES[c["type"]]) for c in rig.channels}
        check(need <= have, name + ": keys all %d channels" % len(need))
        rising = all(all(a[0] < b[0] for a, b in zip(t["keys"], t["keys"][1:])) and t["keys"][0][0] == 0 and
                     t["keys"][-1][0] == doc["length"] for t in doc["tracks"])
        check(rising, name + ": frames rise from 0 to its length (%d)" % doc["length"])
        unit = all(abs(math.sqrt(sum(x * x for x in k[1:5])) - 1) < 1e-3 for t in doc["tracks"] if t["type"] == "rotation"
                   for k in t["keys"])
        check(unit, name + ": rotations are unit quaternions")
        first = {(t["bone"], t["type"]): t["keys"][0][1:] for t in doc["tracks"]}

        def gap(pose):
            g = 0.0
            for (bone, kind), v in first.items():
                if kind != "rotation" or (bone, kind) not in pose:
                    continue
                q = ma.gltf_to_game(pose[(bone, kind)])
                d = abs(sum(x * y for x, y in zip(q, v)))
                g = max(g, math.degrees(2 * math.acos(min(1.0, d))))
            return g

        nearest = min(gap(p) for p in natives)
        if nearest < 1.0:
            check(True, name + ": starts on a native pose (within %.2f degrees)" % nearest)
            continue
        # A follow-up starts where another authored animation passes.
        best, source = nearest, None
        for other in sorted(os.listdir(anims)):
            if other == name or not other.endswith(".json"):
                continue
            odoc = json.load(open(os.path.join(anims, other), encoding="utf-8"))
            if odoc.get("character") != character:
                continue
            rot = [t for t in odoc["tracks"] if t["type"] == "rotation"]
            for f in [k[0] for k in rot[0]["keys"]]:
                theirs = {}
                for t in rot:
                    for k in t["keys"]:
                        if k[0] == f:
                            theirs[(t["bone"], "rotation")] = k[1:]
                g = 0.0
                for (bone, kind), v in first.items():
                    if kind == "rotation" and (bone, kind) in theirs:
                        d = abs(sum(x * y for x, y in zip(theirs[(bone, kind)], v)))
                        g = max(g, math.degrees(2 * math.acos(min(1.0, d))))
                if g < best:
                    best, source = g, "%s frame %d" % (other, f)
        check(best < 1.0, name + ": starts on a native pose or another animation's (within %.2f degrees%s)" %
              (best, ", " + source if source else ""))
    print("%d failed" % len(failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
