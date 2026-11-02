"""Vigil's new monster motions: a dodge roll to each side and a new attack for the Skeleton Soldier (e03a) and the
Dasher (e06a), built from each monster's own native poses with moonanim's helpers. The game appends them to the
native models through animations.monster_register.

python tools/anim/vigil_monster_moves.py <dun/monstor folder> [anims folder, default mods/moonmod.vigil/resources/anims]

  e03a_roll_left / e03a_roll_right, e06a_roll_left / e06a_roll_right
      A tuck out of the idle, a full sideways turn over the shoulder (the brain carries the monster across the floor
      while it plays), and up again. Left is the monster's own left (+x).
  e03a_whirl   The Skeleton's whirling slash: the knife drawn back with the body twisted away, one full turn with the
               blade held out (it hits from frame 12 to 24), and the slash's own follow-through.
  e06a_pounce  The Dasher's pounce: a crouch with the mace raised, a leap (the brain carries it forward), and the mace
               slammed down in front on landing (it hits from frame 14 to 22).

The Skeleton's rig is flat (every piece is a child of the root, placed on its own), so its tuck draws the pieces in
toward the hips; the Dasher's is a chain, so its legs and arms are bent with IK. Each pose is lifted so its lowest
joint stays on the floor.
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


def shifted(rig, pose, delta):
    out = dict(pose)
    for bone in top_bones(rig):
        if (bone, "translation") in out:
            out[(bone, "translation")] = ma._add(out[(bone, "translation")], delta)
    return out


def model_nodes(rig):
    """Every node of the model itself (its weapon and collision points too), not of the shadow hung beside it."""
    parents = ma._parents(rig)

    def top(i):
        while parents.get(i) is not None:
            i = parents[i]
        return i
    main = top(ma._node(rig, rig.channels[0]["bone"]))
    return {i for i in range(len(rig.names)) if top(i) == main and i != main}


def grounded(rig, pose, lift=0.0, floor=0.0):
    """The pose moved up or down so its lowest point (a weapon's too) stands on the floor (plus lift: off the floor
    in a leap)."""
    nodes = model_nodes(rig)
    lowest = min(p[1] for i, (name, p, r) in ma.fk(rig, pose).items() if i in nodes)
    return shifted(rig, pose, (0.0, floor + lift - lowest, 0.0))


def center(rig, pose, bone):
    return ma.joint(rig, pose, bone)


def write(rig, stem, name, frames, speed):
    doc = ma.motion_document(rig, stem, frames, speed)
    # a duplicate (the shadow's channel of the same bone) is left out
    seen, tracks = set(), []
    for t in doc["tracks"]:
        if (t["bone"], t["type"]) in seen:
            continue
        seen.add((t["bone"], t["type"]))
        tracks.append(t)
    doc["tracks"] = tracks
    ma.write_json(os.path.join(A, name + ".json"), doc)
    print(name + ".json:", doc["length"], "frames,", len(tracks), "tracks")


smooth = lambda u: (lambda c: c * c * (3 - 2 * c))(min(1.0, max(0.0, u)))


def roll(rig, idle, tuck, hips, side, length=18, tuck_by=3, roll_from=3, roll_to=13, clear=0.0):
    """A sideways roll: into the tuck by tuck_by, one full turn over the shoulder between roll_from and roll_to (side
    +1: toward the monster's left, +x), and out of the tuck back to idle by length. clear: lift through the turn, for
    a weapon whose head reaches past its node."""
    frames = []
    for f in range(length + 1):
        if f <= tuck_by:
            pose = ma.blend(idle, tuck, smooth(f / tuck_by))
        elif f < roll_to:
            pose = tuck
        else:
            pose = ma.blend(tuck, idle, smooth((f - roll_to) / (length - roll_to)))
        u = smooth((f - roll_from) / (roll_to - roll_from))
        if 0 < u < 1:
            pivot = center(rig, pose, hips)
            pose = whole_turn(rig, pose, ma.qaxis((0, 0, 1), -360.0 * side * u), pivot)
        frames.append((f, grounded(rig, pose, clear * math.sin(math.pi * u))))
    return frames


# --- The Skeleton Soldier (e03a) --------------------------------------------------------------------------------------

skel = rig_of("e03a")
s_idle = skel.sample(10)


def skel_tuck(pose, draw=0.55, pitch=40.0):
    """The flat rig drawn in toward the hips and pitched forward: a ball, as near as rigid pieces make one."""
    hips = center(skel, pose, "kotsuban")
    out = dict(pose)
    for bone in top_bones(skel):
        if bone == "kotsuban" or (bone, "translation") not in out:
            continue
        t = out[(bone, "translation")]
        out[(bone, "translation")] = ma._add(hips, ma._scale(ma._sub(t, hips), draw))
    out = shifted(skel, out, (0.0, -2.5, 0.0))
    return whole_turn(skel, out, ma.qaxis((1, 0, 0), pitch), center(skel, out, "kotsuban"))


s_ball = skel_tuck(skel.sample(105))  # from the guard's crouch, the shield in front
for name, side in (("e03a_roll_left", 1), ("e03a_roll_right", -1)):
    write(skel, "e03a", name, roll(skel, s_idle, s_ball, "kotsuban", side), 0.5)


def skel_whirl():
    """Wind-up (the knife drawn back, the body twisted away) by 7, one full turn with the blade out from 10 to 24,
    the native slash's follow-through to 30, idle by 38."""
    raised, strike, follow = skel.sample(58), skel.sample(64), skel.sample(68)
    yaw = lambda pose, deg: whole_turn(skel, pose, ma.qaxis((0, 1, 0), deg), center(skel, pose, "kotsuban"))
    frames = []
    for f in range(39):
        if f <= 7:
            pose = yaw(ma.blend(s_idle, raised, smooth(f / 7)), 50 * smooth(f / 7))
        elif f < 10:
            pose = yaw(ma.blend(raised, strike, smooth((f - 7) / 3)), 50 * (1 - smooth((f - 7) / 3)))
        elif f <= 24:
            pose = yaw(strike, -360 * smooth((f - 10) / 14))
        elif f <= 30:
            pose = ma.blend(strike, follow, smooth((f - 24) / 6))
        else:
            pose = ma.blend(follow, s_idle, smooth((f - 30) / 8))
        frames.append((f, grounded(skel, pose)))
    return frames


write(skel, "e03a", "e03a_whirl", skel_whirl(), 0.4)

# --- The Dasher (e06a) ------------------------------------------------------------------------------------------------

dash = rig_of("e06a")
d_idle = dash.sample(10)
LEGS = (("l_upleg", "l_leg", "l_toe", 1), ("r_upleg", "r_leg", "r_toe", -1))
ARMS = (("l_arm", "l_farm", "l_hand", 1), ("r_arm", "r_farm", "r_hand", -1))


def dash_tuck():
    pose = dict(d_idle)
    pose = shifted(dash, pose, (0.0, -1.6, 0.0))
    ma.world_turn(dash, pose, "spine", ma.qaxis((1, 0, 0), 40))
    ma.world_turn(dash, pose, "neck", ma.qaxis((1, 0, 0), 30))
    hips = center(dash, pose, "hip")
    chest = center(dash, pose, "spine")
    for hip, knee, ankle, s in LEGS:
        ma.leg(dash, pose, hip, knee, ankle, ma._add(hips, (1.2 * s, -1.4, 2.2)), (0.3 * s, 0.6, 1))
    for arm, elbow, hand, s in ARMS:
        ma.leg(dash, pose, arm, elbow, hand, ma._add(chest, (1.6 * s, 1.2, 3.2)), (s, -0.4, 0))
    return pose


d_ball = dash_tuck()
for name, side in (("e06a_roll_left", 1), ("e06a_roll_right", -1)):
    write(dash, "e06a", name, roll(dash, d_idle, d_ball, "hip", side, clear=2.5), 0.5)  # the mace's head


def dash_pounce():
    """Crouched with the mace raised by 6, a leap (peak at 12), the mace slammed down in front as it lands at 16 (the
    native blow's landing pose), held low to 24, idle by 32."""
    raised = dash.sample(156)
    crouch = shifted(dash, dict(raised), (0.0, -1.4, 0.0))
    hips = center(dash, crouch, "hip")
    for hip, knee, ankle, s in LEGS:
        ma.leg(dash, crouch, hip, knee, ankle, (hips[0] + 1.6 * s, 0.5, hips[2] + 1.2), (0, 0.3, 1))
    chest = center(dash, crouch, "spine")
    for arm, elbow, hand, s in ARMS:
        ma.leg(dash, crouch, arm, elbow, hand, ma._add(chest, (2.6 * s, 7.5, -1.0)), (s, 0, -0.5))
    air = dict(d_ball)
    ma.world_turn(dash, air, "spine", ma.qaxis((1, 0, 0), -30))  # opened out of the tuck, leaning into the leap
    chest = center(dash, air, "spine")
    for arm, elbow, hand, s in ARMS:
        ma.leg(dash, air, arm, elbow, hand, ma._add(chest, (2.4 * s, 6.5, 1.5)), (s, 0, -0.5))
    # the native blow's own landing (frame 170): the mace brought down 21 units out in front, where it reaches
    slam = shifted(dash, dash.sample(170), (0.0, -0.8, 0.0))
    low = dash.sample(170)
    frames = []
    for f in range(33):
        lift = 0.0
        if f <= 6:
            pose = ma.blend(d_idle, crouch, smooth(f / 6))
        elif f <= 12:
            pose = ma.blend(crouch, air, smooth((f - 6) / 6))
            lift = 7.0 * math.sin(math.pi / 2 * (f - 6) / 6)
        elif f <= 16:
            pose = ma.blend(air, slam, smooth((f - 12) / 4))
            lift = 7.0 * math.cos(math.pi / 2 * (f - 12) / 4)
        elif f <= 24:
            pose = ma.blend(slam, low, smooth((f - 16) / 8))
        else:
            pose = ma.blend(low, d_idle, smooth((f - 24) / 8))
        frames.append((f, grounded(dash, pose, lift)))
    return frames


write(dash, "e06a", "e06a_pounce", dash_pounce(), 0.45)
