"""Builds Vigil's side rolls (toan_side_roll_left.json, toan_side_roll_right.json) from toan_dive_roll.json.

python tools/anim/vigil_side_rolls.py <dun/mainchara folder> [anims folder, default mods/moonmod.vigil/resources/anims]

Locked on, a dodge with the stick to the side keeps him facing the target while the stick carries him sideways (the
move's direction "left" or "right"). The roll is the dive roll with his whole body (ctr) turned into the way he goes:
a quarter turn through the crouch, held across the roll, and turned back to face the target as he gets up. Run it
again after reworking toan_dive_roll.json.
"""

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "editor"))
import moonanim as ma  # noqa: E402
from server import document_frames  # noqa: E402

D = sys.argv[1]
A = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "mods", "moonmod.vigil", "resources", "anims")
rig = ma.Rig(os.path.join(D, "c01d.chr"), os.path.join(D, "c01d.gltf"), "c01d.mot")
keys = [(c["bone"], ma.TYPES[c["type"]]) for c in rig.channels]
doc = json.load(open(os.path.join(A, "toan_dive_roll.json")))
ps = [dict(zip(keys, map(tuple, f["values"]))) for f in document_frames(rig, doc)["frames"]]
TURNED_BY, BACK_FROM = 3, 17  # facing the way he rolls by the push-off; facing the target again by the last frame
smooth = lambda u: (lambda c: c * c * (3 - 2 * c))(min(1.0, max(0.0, u)))


def turned(pose, degrees):
    """The whole body turned about the vertical (left +), the centre's offset with it."""
    out = dict(pose)
    q = ma.qaxis((0, 1, 0), degrees)
    ma.world_turn(rig, out, "ctr", q)
    t = out[("ctr", "translation")]
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    out[("ctr", "translation")] = (t[0] * c + t[2] * s, t[1], -t[0] * s + t[2] * c)
    return out


last = len(ps) - 1
for name, side in (("toan_side_roll_left", 1), ("toan_side_roll_right", -1)):
    frames = []
    for f, p in enumerate(ps):
        w = smooth(f / TURNED_BY) if f <= TURNED_BY else 1 - smooth((f - BACK_FROM) / (last - BACK_FROM))
        frames.append((f, turned(p, 90 * side * w) if w > 0 else p))
    ma.write_json(os.path.join(A, name + ".json"), ma.motion_document(rig, "toan", frames, doc["speed"]))
    print(name + ".json:", last, "frames")
