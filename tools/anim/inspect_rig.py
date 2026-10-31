"""Shows what you need to author motions for one character: the native motions, the animated bones and where each
sits at idle, and (with a sheet path) a stick figure of every native motion's middle frame.

python tools/anim/inspect_rig.py <dun/mainchara folder> <character> [sheet.png]

character: toan, xiao, goro, ruby, ungaga or osmond.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moonanim as ma  # noqa: E402


def main():
    data, character = sys.argv[1], sys.argv[2]
    sheet = sys.argv[3] if len(sys.argv) > 3 else None
    pack = ma.PACKS[character]
    rig = ma.open_rig(data, pack)
    names = {}
    sidecar = os.path.join(data, pack + ".game.json")
    if os.path.exists(sidecar):
        for anim in json.load(open(sidecar, encoding="utf-8")).get("resources", {}).get("animations", []):
            for act in anim.get("actions", []):
                names.setdefault((act.get("start"), act.get("end")), act.get("name"))

    print("%s: pack %s, motion file %s, %d channels, %d native motions" %
          (character, pack, rig.mot_name, len(rig.channels), len(rig.motions)))
    print("\nNative motions (number: frames, the converter's name). rig.motion_frame(number, at) picks a frame.")
    for n, (start, end, speed) in enumerate(rig.motions):
        print("  %2d: %4d-%-4d speed %-5g %s" % (n, start, end, speed, names.get((start, end), "")))

    idle = rig.sample(rig.motion_frame(0))
    world = {name: p for _, (name, p, _) in ma.fk(rig, idle).items()}
    animated = sorted({c["bone"] for c in rig.channels})
    nodes = rig.gltf["nodes"]
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    index = {}
    for i, n in enumerate(nodes):
        index.setdefault(n.get("name"), i)
    print("\nAnimated bones at idle (world x, y, z; Y up, facing +Z, the character's right is -X), with the chain")
    print("down to the next animated bone. Arms and legs are the chains that end in an eff* point.")
    for bone in animated:
        p = world.get(bone)
        kinds = sorted(ma.TYPES[c["type"]] for c in rig.channels if c["bone"] == bone)
        kids = [nodes[c].get("name") for c in nodes[index[bone]].get("children", [])]
        up = nodes[parent[index[bone]]].get("name") if index[bone] in parent else "-"
        where = "" if p is None else "(%6.2f %6.2f %6.2f)" % p
        side = "" if p is None or abs(p[0]) < 0.3 else ("right" if p[0] < 0 else "left")
        print("  %-14s %-24s %-5s parent %-10s children %s  [%s]" % (bone, where, side, up, ", ".join(kids), "/".join(kinds)))
    low = sorted((p[1], name) for name, p in world.items() if name and name.startswith(("jnt", "eff")) and p[1] < 1.5)
    print("\nHeight at idle: %.1f. Foot joints on the floor at idle (the ankle is where the leg chain ends; its height"
          % max(p[1] for p in world.values()))
    print("is the floor height for leg IK, like toan_moves.ANKLE):")
    print("  " + ", ".join("%s %.2f" % (name, y) for y, name in low))

    if sheet:
        frames = [rig.motion_frame(n, 0.5) for n in range(len(rig.motions))]
        ma.stick_sheet(rig, [rig.sample(f) for f in frames], sheet, cell=140, labels=[str(n) for n in range(len(frames))])
        print("Wrote", sheet, "(each native motion's middle frame, numbered; front row, side row)")


if __name__ == "__main__":
    main()
