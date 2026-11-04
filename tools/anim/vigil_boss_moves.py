"""Vigil's story-boss motions: a move of the boss's own for its second phase, built from its native poses with
moonanim's helpers. The game appends them to the native models through animations.monster_register; Vigil holds the
boss's script while one plays (Story bosses in mods/moonmod.vigil/main.lua).

python tools/anim/vigil_boss_moves.py <dun/monstor folder> [anims folder, default mods/moonmod.vigil/resources/anims]

  c12a_rear   Dran's fire breath: he rears back on his hind legs with his wings spread (the telegraph, held from 12 to
              24), slams his head down on the line in front of him (28) and breathes along it, held low to 42, and
              settles back to idle by 56.
  c14a_stamp  Master Utan's stamp: both arms flung up as he springs (the telegraph), down onto the floor at 28.
  c13a_frost  The Ice Queen's frost: her arms raised, leaning back, then thrust down at the floor at 28.
  c16a_leap   Minotaur Joe's leap: crouched and up in the air with his axe high, then down with it on you at 28.
  c17a_sweep  The Dark Genie's beam: his arms raised and his body wound round one way, swept across the other at 28.
  c15a_curse  The King's Curse's coffin: up off the floor with its doors flung open (the curses loosed), tipped back, then
              slammed down shut at 28, tipped forward.
  c15b_curse  The King's Curse himself: his arms raised as he rears back, then flung down at the floor at 28.
  c23a_beam   The Dark Genie's final form: his mouth opened and the charge held (his own charge pose, the telegraph), then
              his own firing pose at 28. His rig is IK chains, so this one only resequences his native poses.

Each holds its telegraph from 12 to 24, lands at 28 (as the marks fall: 28 frames at speed 0.6 is 47 ticks, the marks
45), holds low to 42 and is back at idle by 56. Each is built from two of the boss's native poses: the one with its
hands highest (the wind-up) and the one with them lowest (the blow).

Dran's rig is flat (every piece is a child of the root, placed on its own), as the Skeleton's is, so the rear turns
every piece about his hind leg joints. The others are chains from the hip, so turning or lifting the hip moves the
whole body. The native poses keep their own height (the game placed them).
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import moonanim as ma  # noqa: E402

D = sys.argv[1]
A = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "..", "mods", "moonmod.vigil", "resources", "anims")


def rig_of(stem):
    return ma.Rig(os.path.join(D, stem + ".chr"), os.path.join(D, stem + ".gltf"), cfg_name="info.cfg")


def top_bones(rig):
    """The animated bones hung straight off the model's root: turning these about a point turns the whole body."""
    parents = ma._parents(rig)
    out = []
    for c in rig.channels:
        i = ma._node(rig, c["bone"])
        if parents.get(i) is not None and parents.get(parents[i]) is None and c["bone"] not in out:
            out.append(c["bone"])
    return out


def whole_turn(rig, pose, q, pivot):
    """The whole body turned by q (a world rotation) about pivot."""
    out = dict(pose)
    for bone in top_bones(rig):
        if (bone, "rotation") in out:
            out[(bone, "rotation")] = ma.qnorm(ma.qmul(q, out[(bone, "rotation")]))
        if (bone, "translation") in out:
            t = out[(bone, "translation")]
            out[(bone, "translation")] = ma._add(pivot, ma.qrot(q, ma._sub(t, pivot)))
    return out


def lowest_point(rig, pose):
    parents = ma._parents(rig)

    def top(i):
        while parents.get(i) is not None:
            i = parents[i]
        return i
    main = top(ma._node(rig, rig.channels[0]["bone"]))
    nodes = {i for i in range(len(rig.names)) if top(i) == main and i != main}
    return min(p[1] for i, (name, p, r) in ma.fk(rig, pose).items() if i in nodes)


def grounded(rig, pose, floor):
    """The pose moved up or down so its lowest point stands where the idle's does (floor)."""
    lowest = lowest_point(rig, pose)
    out = dict(pose)
    for bone in top_bones(rig):
        if (bone, "translation") in out:
            out[(bone, "translation")] = ma._add(out[(bone, "translation")], (0.0, floor - lowest, 0.0))
    return out


def write(rig, stem, name, frames, speed):
    doc = ma.motion_document(rig, stem, frames, speed)
    seen, tracks = set(), []
    for t in doc["tracks"]:
        if (t["bone"], t["type"]) in seen:  # the shadow's channel of the same bone
            continue
        seen.add((t["bone"], t["type"]))
        tracks.append(t)
    doc["tracks"] = tracks
    ma.write_json(os.path.join(A, name + ".json"), doc)
    print(name + ".json:", doc["length"], "frames,", len(tracks), "tracks")


smooth = lambda u: (lambda c: c * c * (3 - 2 * c))(min(1.0, max(0.0, u)))

# --- Dran (c12a) ------------------------------------------------------------------------------------------------------

dran = rig_of("c12a")
idle = dran.sample(10)
raised = dran.sample(50)  # wings high, head up (his take-off)
low, breath = dran.sample(285), dran.sample(290)  # the native neck blow: head down, then up the line
HIND = (0.0, 17.5, -39.3)  # his hind leg joints, so his hind feet stay put as he rears
FLOOR = lowest_point(dran, idle)


def rear(pose, degrees):
    """Pitched back on the hind feet (head up) by degrees; negative pitches him forward."""
    return whole_turn(dran, pose, ma.qaxis((1, 0, 0), -degrees), HIND)


def dran_rear():
    keys = [(0, idle, 0), (12, raised, 26), (24, raised, 32), (28, low, -6), (34, breath, -4), (42, low, -2), (56, idle, 0)]
    frames = []
    for (f0, a, da), (f1, b, db) in zip(keys, keys[1:]):
        for f in range(f0, f1):
            u = smooth((f - f0) / (f1 - f0))
            frames.append((f, rear(ma.blend(a, b, u), da + (db - da) * u)))
    frames.append((56, idle))
    return frames


write(dran, "c12a", "c12a_rear", dran_rear(), 0.6)


# --- The other story bosses -------------------------------------------------------------------------------------------

def body_bones(rig):
    """The animated bones none of whose ancestors are animated: on a chain rig the hip and whatever else hangs off the
    model's unanimated root nodes on its own (Joe's axe, the Queen's hair). Moving these moves the whole body."""
    parents = ma._parents(rig)
    animated = {c["bone"] for c in rig.channels}
    out = []
    for bone in animated:
        i, free = parents.get(ma._node(rig, bone)), True
        while i is not None:
            free = free and rig.names[i] not in animated
            i = parents.get(i)
        if free:
            out.append(bone)
    return sorted(out)


def body_turn(rig, pose, q, pivot, up):
    """The whole body turned by q about pivot and raised by up (world space; the bones' parents are taken to be
    unturned, as these rigs' root nodes are). A bone with no translation channel turns in place."""
    world = {name: wpos for name, wpos, _ in ma.fk(rig, pose).values()}
    parents = ma._parents(rig)
    out = dict(pose)
    for bone in body_bones(rig):
        if (bone, "rotation") in out:
            out[(bone, "rotation")] = ma.qnorm(ma.qmul(q, out[(bone, "rotation")]))
        if (bone, "translation") in out:
            at = world[bone]
            moved = ma._add(ma._add(pivot, ma.qrot(q, ma._sub(at, pivot))), (0.0, up, 0.0))
            out[(bone, "translation")] = ma._add(out[(bone, "translation")], ma._sub(moved, at))
    return out


def body_lowest(rig, pose):
    """The lowest point of the moving body (what hangs under body_bones), not of a still node beside it."""
    parents = ma._parents(rig)
    roots = {ma._node(rig, b) for b in body_bones(rig)}

    def under(i):
        while i is not None:
            if i in roots:
                return True
            i = parents.get(i)
        return False
    return min(p[1] for i, (name, p, r) in ma.fk(rig, pose).items() if under(i))


def heading(rig, pose):
    """Which way the body faces, in degrees about Y (the hip's +Z)."""
    for i, (name, p, r) in ma.fk(rig, pose).items():
        if name == "hip":
            ahead = ma.qrot(r, (0.0, 0.0, 1.0))
            return math.degrees(math.atan2(ahead[0], ahead[2]))
    return 0.0


def hands_up(rig, pose):
    return (ma.joint(rig, pose, "l_hand")[1] + ma.joint(rig, pose, "r_hand")[1]) / 2


def native_frames(rig):
    return sorted({f for a, b, _ in rig.motions for f in range(a, b + 1)})


def wind_and_slam(rig, head, lift=0.0, back=0.0, forward=0.0, yaw=0.0):
    """Idle, up into the boss's highest-hands pose by 12 (lifted by lift, pitched back by back degrees, wound round by
    yaw), held to 24, down into its lowest-hands pose at 28 (pitched forward, swept the other way), held to 42, idle by
    56. Turned about the floor under the hip, its lowest point where the idle's is (plus the lift). Only poses with the head
    (bone `head`) at three quarters of its idle height or more count, so a fall or a knockdown is never the blow."""
    idle = rig.sample(rig.motions[0][0])
    tall = ma.joint(rig, idle, head)[1]
    facing = heading(rig, idle)

    def usable(pose):
        # standing (not a fall), not up in a jump, upright (the head well over the hip: the King's Curse flips upside
        # down) and facing the way the idle does (no snap in or out)
        up = ma.joint(rig, pose, head)[1]
        upright = up - ma.joint(rig, pose, "hip")[1] >= 0.6 * (tall - ma.joint(rig, idle, "hip")[1])
        turn = abs((heading(rig, pose) - facing + 180.0) % 360.0 - 180.0)
        return 0.75 * tall <= up <= 1.3 * tall and upright and turn <= 20.0

    frames_by = [(hands_up(rig, pose), f) for f in native_frames(rig) for pose in (rig.sample(f),) if usable(pose)]
    raised, low = rig.sample(max(frames_by)[1]), rig.sample(min(frames_by)[1])
    floor = body_lowest(rig, idle)
    hip = ma.joint(rig, idle, "hip")
    pivot = (hip[0], 0.0, hip[2])

    keys = [(0, idle, 0, 0, 0), (12, raised, lift, back, yaw), (24, raised, lift * 1.1, back * 1.15, yaw * 1.1),
            (28, low, 0, -forward, -yaw), (34, low, 0, -forward * 0.8, -yaw), (42, low, 0, -forward * 0.6, -yaw * 0.9),
            (56, idle, 0, 0, 0)]
    return keyed(rig, keys, pivot, floor)


def keyed(rig, keys, pivot, floor):
    """Frames between keys (frame, pose, lift, pitch back, yaw), smoothed, the whole body turned about pivot and its
    lowest point at floor plus the lift."""
    def posed(pose, up, pitch, turn):
        q = ma.qmul(ma.qaxis((0, 1, 0), turn), ma.qaxis((1, 0, 0), -pitch))
        out = body_turn(rig, pose, q, pivot, 0.0)
        return body_turn(rig, out, (0.0, 0.0, 0.0, 1.0), pivot, floor + up - body_lowest(rig, out))

    frames = []
    for (f0, a, ua, pa, ta), (f1, b, ub, pb, tb) in zip(keys, keys[1:]):
        for f in range(f0, f1):
            u = smooth((f - f0) / (f1 - f0))
            frames.append((f, posed(ma.blend(a, b, u), ua + (ub - ua) * u, pa + (pb - pa) * u, ta + (tb - ta) * u)))
    frames.append((keys[-1][0], keys[-1][1]))
    return frames


SHAPES = (("c14a", "c14a_stamp", dict(head="face", lift=3.0, back=6.0, forward=10.0)),
          ("c13a", "c13a_frost", dict(head="head", back=10.0, forward=12.0)),
          ("c16a", "c16a_leap", dict(head="face", lift=24.0, back=10.0, forward=14.0)),
          ("c17a", "c17a_sweep", dict(head="face", back=4.0, yaw=50.0)),
          ("c15b", "c15b_curse", dict(head="hed", back=8.0, forward=12.0)))
for stem, name, shape in SHAPES:
    boss = rig_of(stem)
    write(boss, stem, name, wind_and_slam(boss, **shape), 0.6)


# --- The King's Curse's coffin (c15a) ---------------------------------------------------------------------------------
# A box: obj13 is the coffin (its origin 15 up, at its middle), `me` rides with it, obj17 and obj18 its doors, obj15 what
# rises inside. Its native "open" (50) has the doors flung wide, its idle (10) has them shut.

coffin = rig_of("c15a")
shut, wide = coffin.sample(10), coffin.sample(50)
write(coffin, "c15a", "c15a_curse",
      keyed(coffin, [(0, shut, 0, 0, 0), (12, wide, 12, 12, 0), (24, wide, 14, 14, 0), (28, shut, 1, -8, 0),
                     (34, shut, 0, -5, 0), (42, shut, 0, -2, 0), (56, shut, 0, 0, 0)],
            (0.0, 0.0, 0.0), body_lowest(coffin, shut)), 0.6)


# --- The Dark Genie's final form (c23a) -------------------------------------------------------------------------------
# IK chains (jnt/eff/chn) skinned to one mesh: turning a chain root off his own poses tears the skin, so this is his own
# poses in a new order. Native keys: 100-107 mouth open, 107-115 charge, 115-123 into firing, 123-130 firing.

final = rig_of("c23a")
f_idle, f_open, f_charge, f_fire = final.sample(5), final.sample(104), final.sample(112), final.sample(126)


def native_order(keys):
    frames = []
    for (f0, a), (f1, b) in zip(keys, keys[1:]):
        for f in range(f0, f1):
            frames.append((f, ma.blend(a, b, smooth((f - f0) / (f1 - f0)))))
    frames.append((keys[-1][0], keys[-1][1]))
    return frames


write(final, "c23a", "c23a_beam",
      native_order([(0, f_idle), (8, f_open), (14, f_charge), (24, f_charge), (28, f_fire), (42, f_fire), (56, f_idle)]),
      0.6)
