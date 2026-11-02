"""Builds Vigil's toan_dive_roll_right.json (the roll pushing off his right foot) from toan_dive_roll.json (off his left).

python tools/anim/vigil_lead_foot.py <dun/mainchara folder> [anims folder, default mods/moonmod.vigil/resources/anims]

His legs are mirrored across his hips (positions by IK, the feet aimed along the mirrored toes) through the crouch and
the push-off, then blended back to the roll's own by the time he is in the air; the first frames ease out of his run
with the right foot ahead (native motion 1 at 0.8). Run it again after reworking toan_dive_roll.json.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "editor"))
import moonanim as ma  # noqa: E402
from server import document_frames  # noqa: E402
from toan_moves import LEFT_LEG, RIGHT_LEG  # noqa: E402

D = sys.argv[1]
A = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "mods", "moonmod.vigil", "resources", "anims")
rig = ma.Rig(os.path.join(D, "c01d.chr"), os.path.join(D, "c01d.gltf"), "c01d.mot")
keys = [(c["bone"], ma.TYPES[c["type"]]) for c in rig.channels]
doc = json.load(open(os.path.join(A, "toan_dive_roll.json")))
ps = [dict(zip(keys, map(tuple, f["values"]))) for f in document_frames(rig, doc)["frames"]]
FEET = {"R": ("jnt23_1", "eff24"), "L": ("jnt6_1", "eff7")}
LEGS = {"R": RIGHT_LEG, "L": LEFT_LEG}
MIRROR_TO, BACK_BY = 4, 8  # legs fully mirrored through the push-off, back to his own by the dive
EASE_TO = 2  # the crouch out of his run: the push-off is frame 3
smooth = lambda u: (lambda c: c * c * (3 - 2 * c))(min(1.0, max(0.0, u)))

def mirrored_legs(pose, w):
    world = {n: p for _, (n, p, r) in ma.fk(rig, pose).items()}
    lat = ma._unit(ma._sub(world["jnt22_1"], world["jnt5_1"]))
    mid = ma._scale(ma._add(world["jnt22_1"], world["jnt5_1"]), 0.5)
    mv = lambda v: ma._sub(v, ma._scale(lat, 2 * ma._dot(v, lat)))
    mp = lambda p: ma._add(mid, mv(ma._sub(p, mid)))
    other = {"R": "L", "L": "R"}
    want = {}
    for s in "RL":
        o = other[s]
        hip, knee, ankle = LEGS[o]
        own_hip, own_knee, own_ankle = LEGS[s]
        target = mp(world[ankle])
        hint = mv(ma._sub(world[knee], world[hip]))
        toe = mv(ma._sub(world[FEET[o][1]], world[FEET[o][0]]))
        lerp = lambda a, b: ma._add(ma._scale(a, 1 - w), ma._scale(b, w))
        want[s] = (lerp(world[own_ankle], target), lerp(ma._sub(world[own_knee], world[own_hip]), hint),
                   lerp(ma._sub(world[FEET[s][1]], world[FEET[s][0]]), toe))
    out = dict(pose)
    for s in "RL":
        ma.leg(rig, out, *LEGS[s], want[s][0], want[s][1])
        ma.aim(rig, out, *FEET[s], want[s][2])
    return out

run = rig.sample(rig.motion_frame(1, 0.8))
frames = []
for f, p in enumerate(ps):
    w = 1.0 if f <= MIRROR_TO else max(0.0, 1 - smooth((f - MIRROR_TO) / (BACK_BY - MIRROR_TO)))
    q = mirrored_legs(p, w) if w > 0 else p
    if f <= EASE_TO:
        q = ma.blend(run, q, smooth(f / EASE_TO))
    frames.append((f, q))
ma.write_json(os.path.join(A, "toan_dive_roll_right.json"), ma.motion_document(rig, "toan", frames, doc["speed"]))
print("toan_dive_roll_right.json:", len(frames) - 1, "frames")
