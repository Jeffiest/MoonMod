"""Vigil's evade motions, authored on Toan's rig with toan_moves.py's helpers (tools/anim/moonanim.py).

python tools/anim/vigil_moves.py <dun/mainchara folder> <out folder> [sheet folder]

The Gauntlet's roll is a somersault from a stoop. Vigil's dive roll leaves the floor first: a crouch with the arms
swung back, a push off into a flat dive with the arms reaching ahead and the legs trailing, the hands down, the same
tucked somersault, and up through the roll's planted stance. The Gauntlet's own files are left as they are.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moonanim as ma  # noqa: E402
from toan_moves import ANKLE, LEFT_ARM, LEFT_LEG, RIGHT_ARM, RIGHT_LEG, body_joints, keypose, roll_plant, tucked  # noqa: E402


def stretched(rig, base, pitch, clearance, reach=1.0):
    """A keypose of the dive: the whole body pitched forward by `pitch` degrees and held long, the arms reaching
    ahead of the head (by `reach`, 0 to 1), the legs trailing straight behind, the blade laid back along him, his
    lowest joint `clearance` above the floor."""
    pose = rig.sample(base)
    ma.body(rig, pose, pitch=pitch)
    turn = ma.qaxis((1, 0, 0), pitch)
    hips = ma.joint(rig, pose, "jnt1_1")
    chest = ma.joint(rig, pose, "jnt2_1")

    def at(origin, local):
        return ma._add(origin, ma.qrot(turn, local))

    ma.leg(rig, pose, *RIGHT_LEG, at(hips, (-1.0, -6.6, -0.6)), ma.qrot(turn, (0, 0, 1)))
    ma.leg(rig, pose, *LEFT_LEG, at(hips, (1.0, -6.2, -1.2)), ma.qrot(turn, (0, 0, 1)))
    ma.leg(rig, pose, *RIGHT_ARM, at(chest, (-1.3, 2.0 + 3.4 * reach, 1.6 - 0.8 * reach)), ma.qrot(turn, (-1, 0, -0.3)))
    ma.leg(rig, pose, *LEFT_ARM, at(chest, (1.3, 2.0 + 3.4 * reach, 1.6 - 0.8 * reach)), ma.qrot(turn, (1, 0, -0.3)))
    ma.aim(rig, pose, "jnt18_1", "dcol", ma.qrot(turn, (0.1, -1, -0.25)))
    ma.world_turn(rig, pose, "jnt12_1", ma.qaxis(ma.qrot(turn, (1, 0, 0)), -24))  # the head up, looking ahead
    lowest = min(p[1] for _, p in body_joints(rig, pose))
    t = pose[("ctr", "translation")]
    pose[("ctr", "translation")] = (t[0], t[1] + (clearance - lowest), t[2])
    return pose


def dive_roll(rig):
    """The evade with the stick pushed: out of the run, a crouch with the arms swung back (frame 2), a push off the
    front foot into a flat dive (peak at 6), the hands reaching for the floor (9), a tucked somersault (quarter turns
    11, 13, 15), feet planted in the split stance (18), and up through a forward-leaning step into idle (27)."""
    idle = rig.motion_frame(0)
    run = rig.motion_frame(1, 0.3)
    coil = keypose(rig, idle, body=dict(pitch=34, drop=3.6, ahead=0.4),
                   feet=((-1.6, ANKLE, -1.2), (1.6, ANKLE, 1.4)), knees=((0, 0, 1), (0, 0, 1)),
                   hands=((-2.6, 6.4, -3.0), (2.6, 6.4, -2.6)), elbows=((-1, 0, 0), (1, 0, 0)),
                   sword=(0.2, 0.6, -1), head=(0, 16))
    push = keypose(rig, idle, body=dict(pitch=52, drop=2.2, ahead=1.6),
                   feet=((-1.4, 1.8, -3.6), (1.6, ANKLE, 0.6)), knees=((0, 0.4, 1), (0, 0, 1)),
                   hands=((-1.6, 9.4, 5.8), (1.6, 9.4, 5.8)), elbows=((-1, -0.3, 0), (1, -0.3, 0)),
                   sword=(0.1, 0.2, -1), head=(0, 24))
    plant = roll_plant(rig)
    lift = keypose(rig, idle, body=dict(pitch=26, drop=3.0, ahead=0.5),
                   feet=((-2.0, ANKLE, 2.1), (1.9, ANKLE, -2.6)), knees=((-0.2, 0, 1), (0.3, -0.2, 1)),
                   hands=((-3.2, 8.4, 0.2), (2.8, 5.0, 3.0)), elbows=((-1, -0.2, -0.4), (1, -0.3, 0)),
                   sword=(-0.25, 0.85, -0.45), head=(0, -2))
    rise = keypose(rig, idle, body=dict(pitch=16, drop=2.2, ahead=0.4),
                   feet=((-2.0, ANKLE, 2.0), (2.0, ANKLE, -2.4)), knees=((-0.2, 0, 1), (0.3, 0, 1)),
                   hands=((-2.8, 8.0, 2.4), (2.8, 8.6, 1.8)), elbows=((-1, -0.4, 0), (1, -0.4, 0)),
                   sword=(-0.15, 0.85, 0.5), head=(0, 0))
    frames = ma.bake([(0, rig.sample(run), None), (2, coil, "inout"), (4, push, "in"),
                      (6, stretched(rig, idle, 78, 2.6), None), (8, stretched(rig, idle, 92, 1.2, 0.8), None),
                      (9, tucked(rig, idle, 105, 4.6, 0.6), None), (11, tucked(rig, idle, 150, 4.8, 0.3), None),
                      (13, tucked(rig, idle, 220, 4.9), None), (15, tucked(rig, idle, 290, 4.5), "out"),
                      (18, plant, "in"), (20, lift, None), (22, rise, "out"), (27, rig.sample(idle), "inout")])
    return frames


ANIMATIONS = {"toan_dive_roll": (dive_roll, 0.45)}


def main():
    data, out = sys.argv[1], sys.argv[2]
    sheets = sys.argv[3] if len(sys.argv) > 3 else None
    rig = ma.Rig(os.path.join(data, "c01d.chr"), os.path.join(data, "c01d.gltf"), "c01d.mot")
    for name, (build, speed) in ANIMATIONS.items():
        frames = build(rig)
        ma.write_json(os.path.join(out, name + ".json"), ma.motion_document(rig, "toan", frames, speed))
        if sheets:
            os.makedirs(sheets, exist_ok=True)
            step = max(1, len(frames) // 10)
            ma.stick_sheet(rig, [p for _, p in frames[::step]] + [frames[-1][1]], os.path.join(sheets, name + ".png"), cell=150)
        print(name, frames[-1][0], "frames")


if __name__ == "__main__":
    main()
