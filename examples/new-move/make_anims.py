"""Writes this example's motion: Toan's Overhead Chop.

python examples/new-move/make_anims.py <game data folder>/dun/mainchara [sheet.png]

The motion starts on Toan's run (the move comes out of a run), raises the blade two-handed over his head, chops it
down into the floor ahead with a deep bend, holds a beat and returns to idle.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "anim"))
import moonanim as ma  # noqa: E402
from toan_moves import ANKLE, keypose  # noqa: E402


def overhead_chop(rig):
    idle = rig.motion_frame(0)  # native motion 0: idle
    run = rig.motion_frame(1, 0.3)  # native motion 1: run, 30% into its cycle
    feet = ((-1.9, ANKLE, 1.8), (2.0, ANKLE, -2.4))  # right foot ahead, left back: a split stance
    raise_ = keypose(rig, idle, body=dict(pitch=-8, drop=0.8),
                     feet=feet, knees=((-0.2, 0, 1), (0.3, 0, 1)),
                     hands=((-0.6, 17.0, 0.4), (0.8, 16.6, 0.4)), elbows=((-1, 0, -0.3), (1, 0, -0.3)),
                     sword=(0.0, 0.5, -1), head=(0, -12))
    chop = keypose(rig, idle, body=dict(pitch=32, drop=3.2, ahead=0.8),
                   feet=feet, knees=((-0.2, 0, 1), (0.3, 0, 1)),
                   hands=((-0.6, 6.8, 6.2), (0.8, 7.0, 5.8)), elbows=((-1, -0.3, 0), (1, -0.3, 0)),
                   sword=(0.0, -0.62, 0.78), head=(0, 16))
    held = keypose(rig, idle, body=dict(pitch=30, drop=3.0, ahead=0.8),
                   feet=feet, knees=((-0.2, 0, 1), (0.3, 0, 1)),
                   hands=((-0.6, 7.2, 6.0), (0.8, 7.4, 5.6)), elbows=((-1, -0.3, 0), (1, -0.3, 0)),
                   sword=(0.0, -0.58, 0.81), head=(0, 12))
    # (frame, pose, ease into this key): start on the run, end on idle so the game takes him back without a snap
    return ma.bake([(0, rig.sample(run), None), (6, raise_, "inout"), (9, chop, "in"), (14, held, "out"),
                    (24, rig.sample(idle), "inout")])


def main():
    folder = sys.argv[1]
    rig = ma.open_rig(folder, ma.PACKS["toan"])
    frames = overhead_chop(rig)
    ma.write_json(os.path.join(HERE, "resources", "anims", "toan_overhead_chop.json"),
                  ma.motion_document(rig, "toan", frames, 0.5))
    if len(sys.argv) > 2:
        ma.stick_sheet(rig, [p for _, p in frames[::3]] + [frames[-1][1]], sys.argv[2], cell=150)
    print("toan_overhead_chop:", frames[-1][0], "frames")


if __name__ == "__main__":
    main()
