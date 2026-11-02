"""Imports an Elden Ring animation onto a MoonMod character, into the player's own save only.

python tools/anim/reference/import_motion.py --save <save folder> --mod <mod id> --motion <name> --anim <animation>
                                             [--from N] [--to N] [--length N | --own-timing] [--blow] [--data <game data>]
python tools/anim/reference/import_motion.py --save <save folder> --moveset <moveset file>
python tools/anim/reference/import_motion.py --save <save folder> (--mod <mod id> --motion <name> | --moveset <file>) --restore

Replaces one motion a mod in the save already plays (<save>/mods/<mod>/resources/anims/<name>.json) with the
animation retargeted onto that motion's character, keeping the mod's own file beside it as <name>.json.original the
first time; --restore puts it back. Nothing is written into the repository or a release: the animation comes from the
player's own install (or a repository they downloaded), through the reference cache tools/anim/reference fills.

<animation> is a path inside the cache's groups as the editor's Reference panel lists them ("game/a000/a000_027100.hkx",
"repo0/Abyss Watchers/a000_003000.hkx"), or a .hkx file. By default it is fitted to the replaced motion's length, so
the mod's speed and lunge still match it; --own-timing keeps the animation's 30 frames a second (speed 0.5). --blow
lines the reference's blow (its blade tip's fastest frame) up with the replaced motion's, so the move's hits still land.

A moveset file is {"mod": <mod id>, "motions": {<name>: {"anim": <animation>, "from"?, "to"?, "blow"?}}}: every motion it
names, imported at once, blow-aligned unless it says "blow": false.

The retarget turns each part of the character from its idle pose as the reference's part turns from its rest pose
(pelvis, chest, neck, head), puts the pelvis at the reference's height, and places the hands and feet by IK relative
to the shoulders and hips, scaled by limb length, the elbows and knees toward the reference's, and aims his blade
along the reference's weapon bone. The motion starts on the replaced motion's own first pose and ends on its last, two
frames each way. Characters: Toan.
"""

import argparse
import json
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "editor"))
import moonanim as ma  # noqa: E402
import motion_checks  # noqa: E402
from server import Reference, document_frames  # noqa: E402
from toan_moves import LEFT_ARM, LEFT_LEG, RIGHT_ARM, RIGHT_LEG, keep_above_floor  # noqa: E402

# Per character: its pack, and its bones for each reference part. pairs are (from, to) joints; the reference's are
# the player skeleton's (c0000).
CHARACTERS = {
    "toan": {
        "pack": "c01d",
        "hips": "jnt1_1",
        "parts": [  # bone, its main pair, its side pair, the reference's main and side pairs
            ("chn1", ("jnt1_1", "eff1"), ("jnt22_1", "jnt5_1"), ("Pelvis", "Spine1"), ("R_Thigh", "L_Thigh")),
            ("jnt2_1", ("jnt2_1", "eff2"), ("jnt17_1", "jnt9_1"), ("Spine1", "Neck"), ("R_UpperArm", "L_UpperArm")),
            ("jnt11_1", ("jnt11_1", "jnt12_1"), ("jnt17_1", "jnt9_1"), ("Neck", "Head"), ("R_UpperArm", "L_UpperArm")),
            ("jnt12_1", ("jnt12_1", "eff12"), ("jnt11_1", "eff11"), ("Head", "L_eyeA"), ("Neck", "Head")),
        ],
        "limbs": [(RIGHT_ARM, "R", "arm"), (LEFT_ARM, "L", "arm"), (RIGHT_LEG, "R", "leg"), (LEFT_LEG, "L", "leg")],
        "feet": [("R", "jnt23_1", "eff24"), ("L", "jnt6_1", "eff7")],
        "foot_ahead": (0, -0.16, 1),  # his ankle-to-toe direction standing
        "weapon": ("jnt18_1", "dcol"),  # his wrist and his blade's tip: the blade is aimed along the reference's
    },
}
REF_LIMB = {"arm": ("UpperArm", "Forearm", "Hand"), "leg": ("Thigh", "Calf", "Foot")}


def sub(a, b): return ma._sub(a, b)
def add(a, b): return ma._add(a, b)
def scale(a, k): return ma._scale(a, k)
def unit(a): return ma._unit(a)
def length(a): return ma._len(a)


def basis(a, b):
    """An orthonormal frame (as three vectors) from a main direction a and a side direction b."""
    y = unit(a)
    x = unit(sub(b, scale(y, ma._dot(b, y))))
    return (x, y, ma._cross(x, y))


def frame_turn(cur, want):
    """The rotation (x, y, z, w) taking one frame onto another."""
    m = [[sum(want[k][r] * cur[k][c] for k in range(3)) for c in range(3)] for r in range(3)]
    (a, b, c), (d, e, f), (g, h, i) = m
    tr = a + e + i
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        q = ((h - f) / s, (c - g) / s, (d - b) / s, 0.25 * s)
    elif a > e and a > i:
        s = math.sqrt(1.0 + a - e - i) * 2
        q = (0.25 * s, (b + d) / s, (c + g) / s, (h - f) / s)
    elif e > i:
        s = math.sqrt(1.0 + e - a - i) * 2
        q = ((b + d) / s, 0.25 * s, (f + h) / s, (c - g) / s)
    else:
        s = math.sqrt(1.0 + i - a - e) * 2
        q = ((c + g) / s, (f + h) / s, 0.25 * s, (d - b) / s)
    return ma.qnorm(q)


class Retarget:
    def __init__(self, rig, spec, anim):
        self.rig, self.spec, self.anim = rig, spec, anim
        self.index = {n: i for i, n in enumerate(anim["bones"])}
        self.idle = rig.motion_frame(0)
        self.idle_pose = rig.sample(self.idle)
        rest = anim["rest"]["p"]
        self.rest = lambda name: self.at(rest, rest, 0.0, name)  # noqa: E731
        self.k_hips = self.joint(self.idle_pose, spec["hips"])[1] / self.rest("Pelvis")[1]
        self.k = {}
        for chain, side, kind in spec["limbs"]:
            top, mid, end = (self.rest(side + "_" + n) for n in REF_LIMB[kind])
            mine = sum(length(sub(self.joint(self.idle_pose, b), self.joint(self.idle_pose, a)))
                       for a, b in zip(chain, chain[1:]))
            self.k[kind] = mine / (length(sub(mid, top)) + length(sub(end, mid)))
        self.toe_rest = {s: unit(sub(self.rest(s + "_Toe0"), self.rest(s + "_Foot"))) for s, _, _ in spec["feet"]}
        # The reference's blade per frame: its weapon bone's +Y, through the bone's chain of local rotations.
        self.blades = []
        chain = []
        i = self.index["R_Weapon"]
        while i >= 0:
            chain.append(i)
            i = anim["parents"][i]
        for pose in anim["poses"]:
            q = (0.0, 0.0, 0.0, 1.0)
            for i in reversed(chain):
                q = ma.qmul(q, tuple(pose["l"][i * 7:i * 7 + 4]))
            b = ma.qrot(q, (0, 1, 0))
            self.blades.append((b[0], b[1], -b[2]))

    def joint(self, pose, name):
        return ma.joint(self.rig, pose, name)

    def at(self, p0, p1, t, name):
        """A reference bone between two frames' positions, turned to face +Z like the character (the game faces -Z)."""
        i = self.index[name] * 3
        return (p0[i] + (p1[i] - p0[i]) * t, p0[i + 1] + (p1[i + 1] - p0[i + 1]) * t,
                -(p0[i + 2] + (p1[i + 2] - p0[i + 2]) * t))

    def pose_at(self, frame):
        """The character's pose at a (fractional) frame of the reference."""
        a = self.anim
        f0 = max(0, min(a["frames"] - 1, int(math.floor(frame))))
        f1, t = min(a["frames"] - 1, f0 + 1), frame - f0
        P = lambda name: self.at(a["poses"][f0]["p"], a["poses"][f1]["p"], t, name)  # noqa: E731
        rig, J = self.rig, self.joint
        pose = rig.sample(self.idle)
        vec = lambda p, pair: sub(J(p, pair[1]), J(p, pair[0]))  # noqa: E731
        for bone, main, side, ref_main, ref_side in self.spec["parts"]:
            ev = lambda get, pair: sub(get(pair[1]), get(pair[0]))  # noqa: E731
            turn = frame_turn(basis(ev(self.rest, ref_main), ev(self.rest, ref_side)), basis(ev(P, ref_main), ev(P, ref_side)))
            want = basis(ma.qrot(turn, vec(self.idle_pose, main)), ma.qrot(turn, vec(self.idle_pose, side)))
            ma.world_turn(rig, pose, bone, frame_turn(basis(vec(pose, main), vec(pose, side)), want))
        want, have = scale(P("Pelvis"), self.k_hips), J(pose, self.spec["hips"])
        c = pose[("ctr", "translation")]
        pose[("ctr", "translation")] = (c[0] + want[0] - have[0], c[1] + want[1] - have[1], c[2] + want[2] - have[2])
        for chain, s, kind in self.spec["limbs"]:
            top, mid, end = (P(s + "_" + n) for n in REF_LIMB[kind])
            hint = sub(mid, scale(add(top, end), 0.5))
            ma.leg(rig, pose, *chain, add(J(pose, chain[0]), scale(sub(end, top), self.k[kind])),
                   hint if length(hint) > 1e-4 else (0, 0, 1))
        for s, ankle, toe in self.spec["feet"]:
            now = unit(sub(P(s + "_Toe0"), P(s + "_Foot")))
            ma.aim(rig, pose, ankle, toe, ma.qrot(ma.qbetween(self.toe_rest[s], now), self.spec["foot_ahead"]))
        blade = add(scale(self.blades[f0], 1 - t), scale(self.blades[f1], t))
        ma.aim(rig, pose, *self.spec["weapon"], blade)
        return pose

    def blow(self, start=0, end=None):
        """The reference's blow: the frame its blade's tip moves fastest (the tip about a sword's length out)."""
        a = self.anim
        end = a["frames"] - 1 if end is None else end
        grip = self.index["R_Weapon"] * 3
        tips = [add((pose["p"][grip], pose["p"][grip + 1], -pose["p"][grip + 2]), scale(self.blades[n], 0.9))
                for n, pose in enumerate(a["poses"])]
        return max(range(start, end), key=lambda n: length(sub(tips[n + 1], tips[n])))


def decode(reference, anim):
    if os.path.isfile(anim):  # a file: find its group, the folder under one of the cache's roots
        full = os.path.abspath(anim)
        for rid, (_, root) in reference.roots.items():
            try:
                inside = os.path.relpath(full, os.path.abspath(root)).replace("\\", "/")
            except ValueError:  # another drive
                continue
            if not inside.startswith("../") and "/" in inside:
                group, rel = rid + "/" + inside.split("/")[0], inside.split("/", 1)[1]
                break
        else:
            raise SystemExit("%s isn't in the reference cache's game folder or repositories (tools/anim/reference)" % anim)
    else:
        parts = anim.replace("\\", "/").split("/")
        group, rel = "/".join(parts[:2]), "/".join(parts[2:])
    return json.loads(reference.decoded(group, rel))


def motion_poses(rig, doc):
    """A motion file's keyed frames: [(frame, pose)]."""
    keys = [(c["bone"], ma.TYPES[c["type"]]) for c in rig.channels]
    return [(f["frame"], {k: tuple(v) for k, v in zip(keys, f["values"])}) for f in document_frames(rig, doc)["frames"]]


def motion_blow(rig, spec, poses, length_):
    """Where a motion's blow falls, as a fraction of it: the frame its blade's tip moves fastest."""
    tips = [(f, ma.joint(rig, pose, spec["weapon"][1])) for f, pose in poses]
    n = max(range(len(tips) - 1), key=lambda k: length(sub(tips[k + 1][1], tips[k][1])) / max(1, tips[k + 1][0] - tips[k][0]))
    return tips[n][0] / length_


def import_one(args, rig_for, reference, mod, motion, anim_name, start=None, end=None, align=False, length_=None):
    """Replaces one motion of `mod` in the save with `anim_name` retargeted; returns a line saying what it did."""
    target = os.path.join(args.save, "mods", mod, "resources", "anims", motion + ".json")
    original = target + ".original"
    if not os.path.exists(target) and not os.path.exists(original):
        raise SystemExit("%s has no motion %s (%s)" % (mod, motion, target))
    mine = json.load(open(original if os.path.exists(original) else target, encoding="utf-8"))
    spec = CHARACTERS.get(mine.get("character"))
    if not spec:
        raise SystemExit("%s is %s's motion; the importer knows %s so far" % (motion, mine.get("character"), ", ".join(CHARACTERS)))
    rig = rig_for(spec["pack"])
    anim = decode(reference, anim_name)
    retarget = Retarget(rig, spec, anim)
    last = anim["frames"] - 1
    own = motion_poses(rig, mine)
    if args.own_timing:
        start = max(0, start or 0)
        end = min(last, last if end is None else end)
        frames, speed = end - start, 0.5
    else:
        frames, speed = length_ or mine["length"], mine["speed"]
    lead = 2
    if frames < 2 * lead + 4:
        raise SystemExit("%d frames is too short for %s" % (frames, motion))
    if align:
        # The reference's blow lands where the mod's own motion has its blow, so the mod's hits still land on it; a
        # little of its wind-up and recovery around the blow fills the rest.
        blow = retarget.blow()
        start = max(0, blow - 18) if start is None else start
        end = min(last, blow + 24) if end is None else end
        blow = retarget.blow(start, end)
        at = min(frames - lead - 2, max(lead + 2, round(motion_blow(rig, spec, own, mine["length"]) * frames)))

        def ref_frame(f):
            if f <= at:
                return start + (blow - start) * (f - lead) / (at - lead)
            return blow + (end - blow) * (f - at) / (frames - lead - at)
    else:
        start = max(0, min(last - 1, start or 0))
        end = max(start + 1, min(last, last if end is None else end))

        def ref_frame(f):
            return start + (end - start) * (f - lead) / (frames - 2 * lead)
    # Out of the mod's motion's own first pose (a native one, so it blends in as his own do) and back to its last;
    # the reference plays between.
    keys = [(0, own[0][1], None)]
    keys += [(f, retarget.pose_at(ref_frame(f)), None) for f in range(lead, frames - lead, 2)]
    keys += [(frames - lead, retarget.pose_at(ref_frame(frames - lead)), None), (frames, own[-1][1], "inout")]
    baked = keep_above_floor(rig, ma.bake(keys), 0, frames, clearance=0.2)
    if not os.path.exists(original):
        shutil.copyfile(target, original)
    doc = ma.motion_document(rig, mine["character"], baked, speed)
    ma.write_json(target, doc)
    # What an animator would catch: a limb snapping round, a slow push-off or a whipping blade in an evade.
    findings = "".join("\n  %-5s %s" % (level, text) for level, text in
                       motion_checks.check(rig, doc, motion_checks.is_evade(motion)))
    return "%s: %s frames %d-%d as %d frames at speed %s%s" % (motion, anim_name, start, end, frames, speed, findings)


def restore(args, mod, motion):
    target = os.path.join(args.save, "mods", mod, "resources", "anims", motion + ".json")
    if not os.path.exists(target + ".original"):
        return "%s: never replaced" % motion
    shutil.move(target + ".original", target)
    return "%s: restored" % motion


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--save", required=True, help="the save folder (its mods/ holds the mod)")
    p.add_argument("--mod", help="the mod's folder name, e.g. moonmod.vigil")
    p.add_argument("--motion", help="the motion to replace, e.g. toan_dive_roll")
    p.add_argument("--anim", help="the reference animation (see above)")
    p.add_argument("--moveset", help="a moveset file: every motion it names, at once (see above)")
    p.add_argument("--from", dest="start", type=int, help="its first frame")
    p.add_argument("--to", dest="end", type=int, help="its last frame (default: its end)")
    p.add_argument("--length", type=int, help="frames of the result (default: the replaced motion's)")
    p.add_argument("--own-timing", action="store_true", help="one frame per reference frame, at speed 0.5")
    p.add_argument("--blow", action="store_true", help="line the reference's blow up with the replaced motion's")
    p.add_argument("--restore", action="store_true", help="put the mod's own motion (or the moveset's) back")
    p.add_argument("--data", default=os.environ.get("DC_DATA", "E:/Gauntlet-build/run/data"), help="the converted game data")
    p.add_argument("--reference", default=os.environ.get("MOONANIM_REFERENCE") or
                   os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "Moonmod", "reference"))
    args = p.parse_args()

    repo = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
    if os.path.abspath(args.save) == repo or os.path.abspath(args.save).startswith(repo + os.sep):
        raise SystemExit("that's inside the repository; import into a save folder")
    if args.moveset:
        moveset = json.load(open(args.moveset, encoding="utf-8"))
        mod = args.mod or moveset["mod"]
        jobs = [(mod, name, entry) for name, entry in moveset["motions"].items()]
    elif args.mod and args.motion:
        jobs = [(args.mod, args.motion, {"anim": args.anim, "from": args.start, "to": args.end, "blow": args.blow})]
    else:
        raise SystemExit("name --mod and --motion, or a --moveset")
    if args.restore:
        for mod, name, _ in jobs:
            print(restore(args, mod, name))
        return

    reference = Reference(args.reference)
    if not reference.available():
        raise SystemExit("no reference cache at %s: run tools/anim/reference's extract first" % args.reference)
    rigs = {}

    def rig_for(pack):
        if pack not in rigs:
            folder = os.path.join(args.data, "dun", "mainchara")
            rigs[pack] = ma.Rig(os.path.join(folder, pack + ".chr"), os.path.join(folder, pack + ".gltf"), pack + ".mot")
        return rigs[pack]

    for mod, name, entry in jobs:
        if not entry.get("anim"):
            raise SystemExit("--anim names the animation to import")
        print(import_one(args, rig_for, reference, mod, name, entry["anim"], entry.get("from"), entry.get("to"),
                         entry.get("blow", bool(args.moveset)), args.length))
    print("the mod's own motions are kept beside them as <motion>.json.original; --restore puts them back")


if __name__ == "__main__":
    main()
