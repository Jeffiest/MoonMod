"""Checks a motion for the faults an animator caught in Vigil's rolls, so an imported or retargeted motion is flagged
for them too.

python tools/anim/motion_checks.py <dun/mainchara folder> <motion.json> [more.json ...] [--evade]

verify.py runs these over a mod's animations and the reference importer over each motion it writes; a file whose name
says it is an evade (roll, dodge, tumble, step) gets the evade checks there. The bones are mapped for Toan (c01d) so
far: another character's motion gets a note saying it went unchecked, until its rig's limbs are added to RIGS.

- snap: a limb turning faster against his body (chn1) than any of his own motions turn one. A retarget or a blend
  that overshoots shows up here (a right-foot roll once spun his legs through his torso, 178 degrees in a frame).
- weapon: in an evade, the blade whipping round against his chest (a roll once spun the sword between frames). An
  attack's swing is left alone.
- anticipation: in an evade, the time from the start to the push-off (the centre's lowest point before he rises).
  Over 0.15 s reads as input lag; 0.1 s or so feels instant.
- start: a motion that doesn't start on one of his own poses snaps in, unless its move fades in (`blend_in`).
- lead foot: which foot an evade pushes off; out of a run with the other foot ahead it wants a variant (`variants`).

Each finding is (level, text): "fail" for a snap, "warn" for the rest, "note" for what is only worth knowing.
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

# Toan's rig (c01d); the other rigs reuse the same bone names for other limbs, so each is mapped on its own. Limits are per game tick, so a motion's speed counts: his own motions turn a limb at most about
# 55 degrees a tick against his body (the combo's fastest swing), and his dive roll's tuck about 47.
BODY, CHEST = "chn1", "jnt2_1"
LIMBS = {"jnt22_1": "right thigh", "jnt22_2": "right shin", "jnt23_1": "right foot", "jnt5_1": "left thigh",
         "jnt5_2": "left shin", "jnt6_1": "left foot", "jnt18_1": "right hand", "jnt10_1": "left hand", "jnt12_1": "head"}
FEET = {"right": "eff24", "left": "eff7"}
BLADE = ("jnt18_1", "dcol")
SNAP_PER_TICK = 65.0
WEAPON_PER_TICK = 30.0
ANTICIPATION_S = 0.15
TICKS_PER_S = 60.0
RIGS = {"toan"}
EVADE_WORDS = ("roll", "dodge", "tumble", "step", "evade")


def is_evade(name):
    """An evade by its file's name (toan_dive_roll, xiao_tumble, not toan_roll_attack): what the evade checks are for."""
    base = os.path.basename(name).lower()
    return any(w in base for w in EVADE_WORDS) and "attack" not in base


def _turn(a, b):
    return math.degrees(2 * math.acos(min(1.0, abs(sum(x * y for x, y in zip(a, b))))))


def _rotate(q, v):
    """v turned by the glTF quaternion q (x, y, z, w)."""
    r = ma.qmul(ma.qmul(q, (v[0], v[1], v[2], 0.0)), ma.qconj(q))
    return (r[0], r[1], r[2])


def _rel(world, parent, child):
    return ma.qmul(ma.qconj(world[parent]), world[child])


def poses(rig, doc):
    keys = [(c["bone"], ma.TYPES[c["type"]]) for c in rig.channels]
    return [(f["frame"], {k: tuple(v) for k, v in zip(keys, f["values"])}) for f in document_frames(rig, doc)["frames"]]


def check(rig, doc, evade=False, natives=None):
    """Findings for one motion document: [(level, text)]."""
    found = []
    if doc.get("character") not in RIGS:
        return [("note", "unchecked: %s's limbs aren't mapped in motion_checks.py yet" % doc.get("character"))]
    speed = doc.get("speed", 0.5)
    frames = poses(rig, doc)
    worlds = []
    for _, pose in frames:
        fk = ma.fk(rig, pose)
        worlds.append(({n: r for _, (n, p, r) in fk.items()}, {n: p for _, (n, p, r) in fk.items()}))
    names = set(worlds[0][0])

    # snap: each limb against his body, per tick
    for bone, label in LIMBS.items():
        if bone not in names or BODY not in names:
            continue
        worst, at = 0.0, 0
        for k in range(len(frames) - 1):
            step = max(1, frames[k + 1][0] - frames[k][0])
            per_tick = _turn(_rel(worlds[k][0], BODY, bone), _rel(worlds[k + 1][0], BODY, bone)) / step * speed
            if per_tick > worst:
                worst, at = per_tick, frames[k][0]
        if worst > SNAP_PER_TICK:
            found.append(("fail", "snap: his %s turns %.0f degrees a tick against his body at frame %d (his own motions "
                                  "stay under %.0f): a whip or a blend overshooting" % (label, worst, at, SNAP_PER_TICK)))

    if evade:
        # weapon: the blade against his chest
        if BLADE[1] in names and CHEST in names:
            worst, at = 0.0, 0
            for k in range(len(frames) - 1):
                step = max(1, frames[k + 1][0] - frames[k][0])
                a = [_rel(w[0], CHEST, BLADE[0]) for w in (worlds[k], worlds[k + 1])]
                per_tick = _turn(a[0], a[1]) / step * speed
                if per_tick > worst:
                    worst, at = per_tick, frames[k][0]
            if worst > WEAPON_PER_TICK:
                found.append(("warn", "weapon: the blade turns %.0f degrees a tick against his chest at frame %d: hold the "
                                      "grip still against the chest while he isn't swinging" % (worst, at)))
    if evade and "ctr" in names:
        # anticipation: start to the push-off, the first frame he rises from his crouch (the centre's first dip)
        heights = [w[1]["ctr"][1] for w in worlds]
        low = next((k for k in range(1, len(heights) - 1) if heights[k] <= heights[k - 1] and heights[k + 1] > heights[k]), 0)
        push = frames[min(low + 1, len(frames) - 1)][0]
        seconds = push / speed / TICKS_PER_S
        if seconds > ANTICIPATION_S:
            found.append(("warn", "anticipation: the push-off comes %.2f s in (frame %d at speed %s): over %.2f s reads as "
                                  "input lag" % (seconds, push, speed, ANTICIPATION_S)))
        else:
            found.append(("note", "anticipation: pushes off %.2f s in" % seconds))
        # lead foot: the foot ahead along the way he faces (his centre's +z) at the push-off is the one he pushes with
        rot, at = worlds[min(low + 1, len(worlds) - 1)]
        forward = _rotate(rot["ctr"], (0.0, 0.0, 1.0))
        ahead = {side: ma._dot(at[eff], forward) for side, eff in FEET.items() if eff in at}
        if len(ahead) == 2:
            lead = max(ahead, key=ahead.get)
            found.append(("note", "lead foot: pushes off his %s foot; out of a run with the other ahead, give the move a "
                                  "variant for it" % lead))

    if natives:
        first = frames[0][1]
        limbs = [b for b in LIMBS if (b, "rotation") in first]
        gap = min(max(_turn(first[(b, "rotation")], n[(b, "rotation")]) for b in limbs) for n in natives) if limbs else 0.0
        if gap > 1.0:
            found.append(("warn", "start: %.0f degrees from the nearest of his own poses: it snaps in unless its move "
                                  "fades in (blend_in)" % gap))
    return found


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    evade = "--evade" in sys.argv or None
    if len(args) < 2:
        raise SystemExit(__doc__)
    folder = args[0]
    rig = ma.Rig(os.path.join(folder, "c01d.chr"), os.path.join(folder, "c01d.gltf"), "c01d.mot")
    natives = [rig.sample(f) for f in sorted({f for s, e, _ in rig.motions for f in range(s, e + 1, 2)})]
    failed = 0
    for path in args[1:]:
        doc = json.load(open(path, encoding="utf-8"))
        for level, text in check(rig, doc, evade if evade else is_evade(path), natives):
            failed += level == "fail"
            print("  %-5s %s: %s" % (level, os.path.basename(path), text))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
