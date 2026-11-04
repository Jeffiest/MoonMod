"""Vigil's critical: Toan's half of the paired motion a backstab or a riposte plays (player.moves_set trigger
critical), authored on his rig with toan_moves.py's helpers. The enemies' halves (their crumples) are written by
vigil_monster_moves.py.

python tools/anim/vigil_criticals.py <dun/mainchara folder> <out folder> [sheet folder]

  toan_critical  Both hands on the hilt, the blade drawn back level at his chest (frame 6), driven straight in ahead
                 with a long step (10), pushed deeper (16), wrenched up and out (24), the blade swept off to his side
                 (30), and back to idle (42). The engine draws him in to the critical's gap from the target first, so
                 the thrust lands in it.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moonanim as ma  # noqa: E402
from toan_moves import ANKLE, keypose  # noqa: E402


def critical_stab(rig):
    idle = rig.motion_frame(0)
    set_feet = ((-1.9, ANKLE, 1.6), (2.0, ANKLE, -2.2))
    step_feet = ((-1.9, ANKLE, 6.4), (2.2, ANKLE, -4.6))
    step_knees = ((0, 0.3, 1), (0.2, -0.2, 1))
    draw = keypose(rig, idle, body=dict(pitch=-4, drop=1.2, ahead=-0.6), feet=set_feet,
                   hands=((-0.9, 10.4, -1.6), (0.6, 10.0, -2.6)), elbows=((-1, -0.3, -0.4), (1, -0.3, -0.4)),
                   sword=(0.0, 0.04, 1), head=(0, 4))
    thrust = keypose(rig, idle, body=dict(pitch=20, drop=2.6, ahead=2.2), feet=step_feet, knees=step_knees,
                     hands=((-0.6, 10.0, 8.6), (0.5, 9.8, 7.4)), elbows=((-0.6, -1, 0), (0.6, -1, 0)),
                     sword=(0.0, -0.05, 1), head=(0, 6))
    deeper = keypose(rig, idle, body=dict(pitch=26, drop=3.0, ahead=2.6), feet=step_feet, knees=step_knees,
                     hands=((-0.6, 9.6, 9.4), (0.5, 9.4, 8.2)), elbows=((-0.6, -1, 0), (0.6, -1, 0)),
                     sword=(0.0, -0.08, 1), head=(0, 8))
    wrench = keypose(rig, idle, body=dict(pitch=6, drop=2.0, ahead=1.4, yaw=-12), feet=step_feet, knees=step_knees,
                     hands=((-0.8, 13.2, 6.0), (0.6, 12.6, 5.0)), elbows=((-1, -0.4, 0), (1, -0.4, 0)),
                     sword=(0.0, 0.5, 0.86), head=(0, -6))
    sweep = keypose(rig, idle, body=dict(pitch=8, drop=1.6, ahead=0.6, yaw=24), feet=step_feet, knees=step_knees,
                    hands=((-5.2, 9.4, 3.0), None), elbows=((-1, -0.6, 0), (1, -0.4, 0)),
                    sword=(-0.8, -0.2, 0.56), head=(-10, 2))
    return ma.bake([(0, rig.sample(idle), None), (6, draw, "inout"), (10, thrust, "in"), (16, deeper, "out"),
                    (24, wrench, "inout"), (30, sweep, "out"), (42, rig.sample(idle), "inout")])


ANIMATIONS = {"toan_critical": (critical_stab, 0.5)}


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
