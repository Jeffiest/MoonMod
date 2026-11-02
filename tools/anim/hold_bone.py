"""Eases a bone's turn against another bone across a span of frames, in place: the fix for a hand or a weapon that
flips between two frames (motion_checks.py's "snap" or "weapon").

python tools/anim/hold_bone.py <dun/mainchara folder> <motion.json> <bone> <against> <from> <to>

Between frames `from` and `to` the bone keeps the turn it has against `against` (its forearm, his chest) at `from`
and eases into the one it has at `to`, by the shorter way; the frames outside are left alone. Vigil's dive roll holds
his sword hand against his chest this way, and eases his left hand into its flat plant.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "editor"))
import moonanim as ma  # noqa: E402
from server import document_frames  # noqa: E402

smooth = lambda u: (lambda c: c * c * (3 - 2 * c))(min(1.0, max(0.0, u)))


def world_rotations(rig, pose):
    return {n: r for _, (n, p, r) in ma.fk(rig, pose).items()}


def hold(rig, frames, bone, against, start, end):
    """frames: [(frame, pose)], changed in place between start and end."""
    def rel(pose):
        w = world_rotations(rig, pose)
        return ma.qmul(ma.qconj(w[against]), w[bone])

    first = rel(dict(frames[start][1]))
    last = rel(dict(frames[end][1]))
    if sum(x * y for x, y in zip(first, last)) < 0:
        last = tuple(-x for x in last)
    for k in range(start + 1, end):
        f, pose = frames[k]
        want = ma.qslerp(first, last, smooth((f - frames[start][0]) / (frames[end][0] - frames[start][0])))
        w = world_rotations(rig, pose)
        desired = ma.qnorm(ma.qmul(w[against], want))
        ma.world_turn(rig, pose, bone, ma.qnorm(ma.qmul(desired, ma.qconj(w[bone]))))


def main():
    if len(sys.argv) != 7:
        raise SystemExit(__doc__)
    folder, path, bone, against = sys.argv[1:5]
    start, end = int(sys.argv[5]), int(sys.argv[6])
    rig = ma.Rig(os.path.join(folder, "c01d.chr"), os.path.join(folder, "c01d.gltf"), "c01d.mot")
    doc = json.load(open(path, encoding="utf-8"))
    keys = [(c["bone"], ma.TYPES[c["type"]]) for c in rig.channels]
    frames = [(f["frame"], {k: tuple(v) for k, v in zip(keys, f["values"])}) for f in document_frames(rig, doc)["frames"]]
    index = {f: i for i, (f, _) in enumerate(frames)}
    if start not in index or end not in index or start >= end:
        raise SystemExit("from and to are keyed frames, from below to")
    hold(rig, frames, bone, against, index[start], index[end])
    ma.write_json(path, ma.motion_document(rig, doc["character"], frames, doc["speed"]))
    print("%s: %s held against %s over frames %d-%d" % (os.path.basename(path), bone, against, start, end))


if __name__ == "__main__":
    main()
