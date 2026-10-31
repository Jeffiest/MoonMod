"""Toan's Gauntlet animations, authored on his own rig (tools/anim/moonanim.py).

python tools/anim/toan_moves.py <dun/mainchara folder> <out folder> [sheet folder]

Writes one moonmod-motion v1 file per entry of ANIMATIONS (the dash thrust, whirlwind, rising slash, roll, backstep,
heavy chop, launcher, spin finisher, back slash and roll slash), and with a sheet folder a stick-figure contact sheet
of each (front row, side row) to check the poses.

Every keypose starts from one of his native poses and is then posed in world space: the body turned and lowered,
the feet planted by leg IK, the hands placed by arm IK, the sword aimed. Space: Y up, Toan facing +Z, his right -X;
ankles rest 0.7 above the floor.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moonanim as ma  # noqa: E402

ANKLE = 0.7
RIGHT_LEG = ("jnt22_1", "jnt22_2", "eff22")
LEFT_LEG = ("jnt5_1", "jnt5_2", "eff5")
RIGHT_ARM = ("jnt17_1", "jnt17_2", "eff17")
LEFT_ARM = ("jnt9_1", "jnt9_2", "eff9")
RIGHT_FOOT = ("jnt23_1", "eff24")
LEFT_FOOT = ("jnt6_1", "eff7")


def body_joints(rig, pose):
    """The model's skeleton joints in world space (not its mesh nodes or the sword's points)."""
    nodes = rig.gltf["nodes"]
    return [(name, p) for i, (name, p, _) in ma.fk(rig, pose).items()
            if name and "mesh" not in nodes[i] and "matrix" not in nodes[i] and name not in ("dcol", "weapon", "item", "skin")]


def keep_above_floor(rig, frames, lo, hi, clearance=0.3):
    """Lifts the body of every frame from lo to hi so its lowest joint clears the floor."""
    for f, pose in frames:
        if lo <= f <= hi:
            lowest = min(p[1] for _, p in body_joints(rig, pose))
            if lowest < clearance:
                t = pose[("ctr", "translation")]
                pose[("ctr", "translation")] = (t[0], t[1] + clearance - lowest, t[2])
    return frames


def keypose(rig, base, body=None, feet=None, knees=((0, 0, 1), (0, 0, 1)), hands=None, elbows=((0, -1, 0), (0, -1, 0)),
            sword=None, head=None):
    """One keypose. base: a native frame. body: ma.body() arguments. feet: (right, left) ankle targets. hands:
    (right, left) wrist targets, either may be None. sword: the blade's world direction. head: (yaw, pitch)."""
    pose = rig.sample(base)
    if body:
        ma.body(rig, pose, **body)
    if feet:
        ma.leg(rig, pose, *RIGHT_LEG, feet[0], knees[0])
        ma.leg(rig, pose, *LEFT_LEG, feet[1], knees[1])
        # a foot on the floor lies flat along it (toes ahead, a little down to the toe tip)
        for (ankle, toe), at in (((RIGHT_FOOT), feet[0]), ((LEFT_FOOT), feet[1])):
            if at[1] <= ANKLE + 0.05:
                ma.aim(rig, pose, ankle, toe, (0, -0.16, 1))
    if hands:
        if hands[0]:
            ma.leg(rig, pose, *RIGHT_ARM, hands[0], elbows[0])
        if hands[1]:
            ma.leg(rig, pose, *LEFT_ARM, hands[1], elbows[1])
    if sword:
        ma.aim(rig, pose, "jnt18_1", "dcol", sword)
    if head:
        q = ma.qmul(ma.qaxis((0, 1, 0), head[0]), ma.qaxis((1, 0, 0), head[1]))
        ma.world_turn(rig, pose, "jnt12_1", q)
    return pose


def dash_thrust(rig):
    """Out of a run: a coiled step, then a long low lunge driving the blade straight ahead, a beat held, and back."""
    idle = rig.motion_frame(0)
    run = rig.motion_frame(1, 0.3)
    coil = keypose(rig, idle, body=dict(pitch=14, drop=1.6, yaw=-20),
                   feet=((-2.0, ANKLE, 2.2), (2.3, ANKLE, -2.6)),
                   hands=((-3.6, 7.6, -2.2), (2.6, 10.2, 3.6)), elbows=((-0.4, -0.2, -1), (0.3, -1, 0)),
                   sword=(0.05, -0.25, 1), head=(15, 6))
    lunge = keypose(rig, idle, body=dict(pitch=28, drop=3.0, ahead=2.6, yaw=22),
                    feet=((-1.9, ANKLE, 8.4), (2.2, ANKLE, -5.6)), knees=((0, 0.3, 1), (0.2, -0.2, 1)),
                    hands=((-0.9, 10.2, 9.6), (3.8, 9.6, -3.6)), elbows=((-0.3, -1, 0), (0.4, -0.4, -1)),
                    sword=(0.02, -0.06, 1), head=(-18, 2))
    follow = keypose(rig, idle, body=dict(pitch=30, drop=3.2, ahead=2.8, yaw=18),
                     feet=((-1.9, ANKLE, 8.4), (2.2, ANKLE, -5.6)), knees=((0, 0.3, 1), (0.2, -0.2, 1)),
                     hands=((-1.0, 9.6, 9.2), (3.8, 9.2, -3.4)), elbows=((-0.3, -1, 0), (0.4, -0.4, -1)),
                     sword=(0.02, -0.3, 1), head=(-14, 4))
    return ma.bake([(0, rig.sample(run), None), (5, coil, "inout"), (9, lunge, "in"), (15, follow, "out"),
                    (24, rig.sample(idle), "inout")])


def whirlwind(rig):
    """Out of a charge: wound low across the body, then unwound with both arms flung wide, the blade out flat to his
    right (the move spins him), held, and finished with a two-handed slam into the floor ahead."""
    idle = rig.motion_frame(0)
    charge = rig.motion_frame(14, 0.5)
    wind = keypose(rig, idle, body=dict(yaw=48, drop=2.6, pitch=10),
                   feet=((-3.4, ANKLE, 0.6), (3.4, ANKLE, -0.8)), knees=((-0.4, 0, 1), (0.4, 0, 1)),
                   hands=((2.4, 6.8, 1.8), (3.2, 9.4, -2.4)), elbows=((0, -0.3, 1), (0.5, -1, 0)),
                   sword=(0.9, -0.35, -1), head=(30, 10))
    wide = keypose(rig, idle, body=dict(yaw=-8, drop=2.2, pitch=4),
                   feet=((-3.6, ANKLE, 0.4), (3.6, ANKLE, -0.4)), knees=((-0.4, 0, 1), (0.4, 0, 1)),
                   hands=((-7.4, 11.4, 0.6), (6.8, 11.6, 0.0)), elbows=((0, -1, 0.2), (0, -1, 0.2)),
                   sword=(-1, 0.02, 0.18), head=(-20, -4))
    held = keypose(rig, idle, body=dict(yaw=-12, drop=2.0, pitch=2, roll=-6),
                   feet=((-3.6, ANKLE, 0.4), (3.6, ANKLE, -0.4)), knees=((-0.4, 0, 1), (0.4, 0, 1)),
                   hands=((-7.4, 12.0, 0.4), (6.8, 11.0, 0.2)), elbows=((0, -1, 0.2), (0, -1, 0.2)),
                   sword=(-1, 0.12, 0.25), head=(-24, -6))
    raise_ = keypose(rig, idle, body=dict(pitch=-8, drop=0.6),
                     feet=((-3.0, ANKLE, 1.2), (3.0, ANKLE, -1.2)),
                     hands=((-1.2, 17.2, 1.4), (1.6, 16.2, 1.0)), elbows=((-0.6, 0, -1), (0.6, 0, -1)),
                     sword=(0.05, 0.6, -1), head=(0, -14))
    slam = keypose(rig, idle, body=dict(pitch=34, drop=4.2, ahead=1.2),
                   feet=((-3.2, ANKLE, 2.6), (3.0, ANKLE, -2.4)), knees=((-0.3, 0, 1), (0.3, 0, 1)),
                   hands=((-0.9, 6.4, 7.0), (1.4, 6.8, 6.4)), elbows=((-1, -0.3, 0), (1, -0.3, 0)),
                   sword=(0.02, -0.9, 0.55), head=(0, 18))
    return ma.bake([(0, rig.sample(charge), None), (6, wind, "inout"), (11, wide, "in"), (24, held, "inout"),
                    (29, raise_, "out"), (32, slam, "in"), (42, rig.sample(idle), "inout")])


def rising_slash(rig):
    """Out of a guard: dropped into a deep crouch with the blade trailing low behind him, then a rising cut that
    carries him up off his feet, the blade high over his head, and down into a ready landing."""
    idle = rig.motion_frame(0)
    guard = rig.motion_frame(9, 0.5)
    crouch = keypose(rig, idle, body=dict(drop=3.6, pitch=24, yaw=-26),
                     feet=((-2.6, ANKLE, 2.4), (2.6, ANKLE, -2.2)), knees=((-0.3, 0, 1), (0.3, 0, 1)),
                     hands=((-3.6, 4.8, -2.4), (2.6, 8.4, 3.2)), elbows=((-0.5, 0, -1), (0.4, -1, 0)),
                     sword=(-0.25, -0.75, -0.8), head=(18, 12))
    rise = keypose(rig, idle, body=dict(drop=-2.2, pitch=-4, yaw=14),
                   feet=((-1.6, 2.6, 1.4), (1.8, 2.2, -1.6)), knees=((0, 0, 1), (0, 0, 1)),
                   hands=((-1.0, 15.8, 4.2), (3.0, 9.4, -2.2)), elbows=((-1, -0.2, 0), (0.4, -1, -0.3)),
                   sword=(0.05, 1, 0.4), head=(-6, -16))
    apex = keypose(rig, idle, body=dict(drop=-3.2, pitch=-10, yaw=8),
                   feet=((-1.4, 3.6, 0.8), (1.6, 3.0, -1.2)), knees=((0, 0, 1), (0, 0, 1)),
                   hands=((-0.6, 18.4, 1.6), (3.2, 10.0, -1.8)), elbows=((-1, 0, 0), (0.4, -1, -0.3)),
                   sword=(0.05, 1, -0.3), head=(0, -20))
    land = keypose(rig, idle, body=dict(drop=1.8, pitch=12),
                   feet=((-2.2, ANKLE, 1.6), (2.2, ANKLE, -1.6)),
                   hands=((-2.0, 9.4, 5.0), (2.6, 9.6, 2.0)), elbows=((-0.4, -1, 0), (0.4, -1, 0)),
                   sword=(0.0, -0.4, 1), head=(0, 6))
    return ma.bake([(0, rig.sample(guard), None), (5, crouch, "inout"), (10, rise, "in"), (14, apex, "out"),
                    (20, land, "in"), (30, rig.sample(idle), "inout")])


def tucked(rig, base, pitch, drop, ahead=0.0):
    """A keypose of the roll: the body pitched forward by `pitch` degrees about his pelvis, curled into a ball: the
    spine and head bent in, the knees drawn to the chest, the hands at the shins, the blade laid back along him."""
    pose = rig.sample(base)
    ma.body(rig, pose, pitch=pitch, drop=drop, ahead=ahead)
    turn = ma.qaxis((1, 0, 0), pitch)
    side = ma.qrot(turn, (1, 0, 0))
    ma.world_turn(rig, pose, "jnt2_1", ma.qaxis(side, 38))
    ma.world_turn(rig, pose, "jnt12_1", ma.qaxis(side, 30))
    hips = ma.joint(rig, pose, "jnt1_1")
    chest = ma.joint(rig, pose, "jnt2_1")

    def at(origin, local):
        return ma._add(origin, ma.qrot(turn, local))

    ma.leg(rig, pose, *RIGHT_LEG, at(hips, (-1.3, -2.0, 2.8)), ma.qrot(turn, (0, 0.6, 1)))
    ma.leg(rig, pose, *LEFT_LEG, at(hips, (1.3, -2.0, 2.8)), ma.qrot(turn, (0, 0.6, 1)))
    ma.leg(rig, pose, *RIGHT_ARM, at(chest, (-1.6, -3.4, 3.2)), ma.qrot(turn, (-1, -0.4, 0)))
    ma.leg(rig, pose, *LEFT_ARM, at(chest, (1.6, -3.4, 3.2)), ma.qrot(turn, (1, -0.4, 0)))
    ma.aim(rig, pose, "jnt18_1", "dcol", ma.qrot(turn, (0.15, 0.25, -1)))
    # Rolled on the floor: the lowest joint of the body touches it, no lower.
    lowest = min(p[1] for _, p in body_joints(rig, pose))
    t = pose[("ctr", "translation")]
    pose[("ctr", "translation")] = (t[0], t[1] + (0.4 - lowest), t[2])
    return pose


def roll_plant(rig):
    """The roll's planted stance (its frame 15): feet split, the off hand on the floor, the blade trailing. The roll
    slash starts here."""
    return keypose(rig, rig.motion_frame(0), body=dict(pitch=34, drop=3.8, ahead=0.6),
                   feet=((-2.0, ANKLE, 2.2), (1.9, ANKLE, -2.8)), knees=((-0.2, 0, 1), (0.3, -0.4, 1)),
                   hands=((-3.4, 5.6, -0.4), (2.6, 1.6, 3.4)), elbows=((-1, 0, -0.4), (1, 0, 0.2)),
                   sword=(-0.3, -0.05, -1), head=(0, -6))


def roll(rig):
    """The evade with the stick pushed: out of the run, a dive with both hands reaching for the floor, a tucked
    somersault (quarter turns 6, 9, 12), feet planted in a split stance with the off hand on the floor and the blade
    trailing, pushed up through a forward-leaning step into his guard, and back to idle."""
    idle = rig.motion_frame(0)
    run = rig.motion_frame(1, 0.3)
    dive = keypose(rig, idle, body=dict(pitch=36, drop=2.4, ahead=1.2),
                   feet=((-1.6, ANKLE, -1.4), (1.6, ANKLE, 1.6)), knees=((0, 0, 1), (0, 0, 1)),
                   hands=((-1.6, 5.4, 5.6), (1.6, 5.4, 5.6)), elbows=((-1, -0.3, 0), (1, -0.3, 0)),
                   sword=(0.1, 0.3, -1), head=(0, 20))
    plant = roll_plant(rig)
    lift = keypose(rig, idle, body=dict(pitch=26, drop=3.0, ahead=0.5),
                   feet=((-2.0, ANKLE, 2.1), (1.9, ANKLE, -2.6)), knees=((-0.2, 0, 1), (0.3, -0.2, 1)),
                   hands=((-3.2, 8.4, 0.2), (2.8, 5.0, 3.0)), elbows=((-1, -0.2, -0.4), (1, -0.3, 0)),
                   sword=(-0.25, 0.85, -0.45), head=(0, -2))
    push = keypose(rig, idle, body=dict(pitch=16, drop=2.2, ahead=0.4),
                   feet=((-2.0, ANKLE, 2.0), (2.0, ANKLE, -2.4)), knees=((-0.2, 0, 1), (0.3, 0, 1)),
                   hands=((-2.8, 8.0, 2.4), (2.8, 8.6, 1.8)), elbows=((-1, -0.4, 0), (1, -0.4, 0)),
                   sword=(-0.15, 0.85, 0.5), head=(0, 0))
    frames = ma.bake([(0, rig.sample(run), None), (3, dive, "in"), (6, tucked(rig, idle, 100, 4.6, 0.6), None),
                      (9, tucked(rig, idle, 190, 4.9), None), (12, tucked(rig, idle, 280, 4.5), "out"),
                      (15, plant, "in"), (17, lift, None), (19, push, "out"), (24, rig.sample(idle), "inout")])
    return keep_above_floor(rig, frames, 4, 13)


def backstep(rig):
    """The evade with the stick at rest: a quick crouch, a low skip straight back with the guard up, the feet just off the floor,
    and a low landing."""
    idle = rig.motion_frame(0)
    crouch = keypose(rig, idle, body=dict(pitch=10, drop=1.8),
                     feet=((-2.0, ANKLE, 0.6), (2.0, ANKLE, -0.8)),
                     hands=((-2.4, 9.0, 3.6), (2.4, 9.6, 2.6)), elbows=((-1, -0.5, 0), (1, -0.5, 0)),
                     sword=(0.0, 0.1, 1), head=(0, 4))
    hop = keypose(rig, idle, body=dict(pitch=-10, drop=0.2),
                  feet=((-1.7, 1.2, 2.0), (1.7, 1.5, 1.0)), knees=((0, 0.3, 1), (0, 0.3, 1)),
                  hands=((-1.8, 10.6, 4.4), (1.9, 10.8, 3.6)), elbows=((-1, -0.5, 0), (1, -0.5, 0)),
                  sword=(0.0, 0.45, 1), head=(0, -4))
    land = keypose(rig, idle, body=dict(pitch=-4, drop=1.6),
                   feet=((-1.9, ANKLE, 1.8), (2.0, ANKLE, -2.4)), knees=((-0.2, 0, 1), (0.3, 0, 1)),
                   hands=((-2.2, 10.2, 4.0), (2.4, 10.4, 3.0)), elbows=((-1, -0.5, 0), (1, -0.5, 0)),
                   sword=(0.0, 0.4, 1), head=(0, -2))
    settle = keypose(rig, idle, body=dict(pitch=8, drop=2.0),
                     feet=((-1.9, ANKLE, 1.8), (2.0, ANKLE, -2.4)), knees=((-0.2, 0, 1), (0.3, 0, 1)),
                     hands=((-2.4, 9.2, 3.8), (2.4, 9.6, 2.8)), elbows=((-1, -0.5, 0), (1, -0.5, 0)),
                     sword=(0.0, 0.15, 1), head=(0, 4))
    return ma.bake([(0, rig.sample(idle), None), (3, crouch, "inout"), (5, hop, "out"), (8, land, "in"),
                    (11, settle, "out"), (18, rig.sample(idle), "inout")])


def heavy_chop(rig):
    """The heavy attack (R2) from rest: a slow two-handed lift of the blade over his head with the weight rocked back,
    a chop straight down into the floor ahead with a deep bend (frame 13), held, and back to idle."""
    idle = rig.motion_frame(0)
    feet = ((-1.9, ANKLE, 1.8), (2.0, ANKLE, -2.4))
    knees = ((-0.2, 0, 1), (0.3, 0, 1))
    gather = keypose(rig, idle, body=dict(pitch=6, drop=1.4), feet=feet, knees=knees,
                     hands=((-1.0, 9.0, 3.4), (1.2, 9.2, 3.0)), elbows=((-1, -0.4, 0), (1, -0.4, 0)),
                     sword=(0.0, 0.3, 1), head=(0, 4))
    raise_ = keypose(rig, idle, body=dict(pitch=-12, drop=0.6, ahead=-0.4), feet=feet, knees=knees,
                     hands=((-0.6, 17.4, -0.4), (0.8, 17.0, -0.4)), elbows=((-1, 0, -0.3), (1, 0, -0.3)),
                     sword=(0.0, 0.35, -1), head=(0, -14))
    chop = keypose(rig, idle, body=dict(pitch=34, drop=3.4, ahead=1.0), feet=feet, knees=knees,
                   hands=((-0.6, 6.6, 6.4), (0.8, 6.8, 6.0)), elbows=((-1, -0.3, 0), (1, -0.3, 0)),
                   sword=(0.0, -0.66, 0.75), head=(0, 16))
    held = keypose(rig, idle, body=dict(pitch=32, drop=3.2, ahead=1.0), feet=feet, knees=knees,
                   hands=((-0.6, 7.0, 6.2), (0.8, 7.2, 5.8)), elbows=((-1, -0.3, 0), (1, -0.3, 0)),
                   sword=(0.0, -0.6, 0.8), head=(0, 12))
    return ma.bake([(0, rig.sample(idle), None), (4, gather, "inout"), (10, raise_, "out"), (13, chop, "in"),
                    (19, held, "out"), (30, rig.sample(idle), "inout")])


def launcher(rig):
    """The finisher after two combo swings (A, A, R2): out of the second swing's end, dropped low with the blade trailing
    down behind him, then an upward cut that lifts him onto his toes (frame 8), the blade high over his head, held,
    and back to idle."""
    idle = rig.motion_frame(0)
    swing = rig.motion_frame(0x25, 1.0)
    low = keypose(rig, idle, body=dict(drop=3.4, pitch=22, yaw=-18),
                  feet=((-2.4, ANKLE, 2.2), (2.4, ANKLE, -2.2)), knees=((-0.3, 0, 1), (0.3, 0, 1)),
                  hands=((-3.0, 4.6, -1.8), (2.2, 8.4, 3.2)), elbows=((-0.5, 0, -1), (0.4, -1, 0)),
                  sword=(-0.2, -0.8, -0.6), head=(14, 10))
    cut = keypose(rig, idle, body=dict(drop=-0.6, pitch=-6, yaw=10),
                  feet=((-1.8, 1.2, 1.8), (1.9, ANKLE, -1.8)), knees=((0, 0, 1), (0.2, 0, 1)),
                  hands=((-1.0, 16.4, 4.0), (2.8, 10.0, -1.6)), elbows=((-1, -0.2, 0), (0.4, -1, -0.3)),
                  sword=(0.05, 1, 0.5), head=(-4, -18))
    top = keypose(rig, idle, body=dict(drop=-0.8, pitch=-10, yaw=6),
                  feet=((-1.8, 1.3, 1.8), (1.9, ANKLE, -1.8)), knees=((0, 0, 1), (0.2, 0, 1)),
                  hands=((-0.8, 17.6, 1.8), (3.0, 10.4, -1.6)), elbows=((-1, 0, 0), (0.4, -1, -0.3)),
                  sword=(0.05, 1, -0.2), head=(0, -20))
    ready = keypose(rig, idle, body=dict(drop=1.6, pitch=10),
                    feet=((-2.0, ANKLE, 1.6), (2.0, ANKLE, -1.8)),
                    hands=((-2.0, 9.6, 4.8), (2.6, 9.6, 2.0)), elbows=((-0.4, -1, 0), (0.4, -1, 0)),
                    sword=(0.0, -0.2, 1), head=(0, 4))
    return ma.bake([(0, rig.sample(swing), None), (4, low, "inout"), (8, cut, "in"), (13, top, "out"),
                    (19, ready, "inout"), (28, rig.sample(idle), "inout")])


def spin_finisher(rig):
    """The finisher after three combo swings (A, A, A, R2): out of the third swing, wound across his body, then flung
    wide with the blade out flat to his right while the move turns him a full circle, and ended on a lunging cut
    straight ahead (frame 20)."""
    idle = rig.motion_frame(0)
    swing = rig.motion_frame(0x26, 1.0)
    wind = keypose(rig, idle, body=dict(yaw=44, drop=2.4, pitch=8),
                   feet=((-3.2, ANKLE, 0.6), (3.2, ANKLE, -0.8)), knees=((-0.4, 0, 1), (0.4, 0, 1)),
                   hands=((2.2, 7.2, 2.0), (3.0, 9.6, -2.2)), elbows=((0, -0.3, 1), (0.5, -1, 0)),
                   sword=(0.9, -0.2, -1), head=(28, 8))
    wide = keypose(rig, idle, body=dict(yaw=-6, drop=2.0, pitch=2),
                   feet=((-3.4, ANKLE, 0.4), (3.4, ANKLE, -0.4)), knees=((-0.4, 0, 1), (0.4, 0, 1)),
                   hands=((-7.4, 11.2, 0.8), (6.6, 11.4, 0.0)), elbows=((0, -1, 0.2), (0, -1, 0.2)),
                   sword=(-1, 0.0, 0.2), head=(-18, -2))
    lunge = keypose(rig, idle, body=dict(pitch=26, drop=3.0, ahead=2.2, yaw=18),
                    feet=((-1.9, ANKLE, 7.4), (2.2, ANKLE, -5.0)), knees=((0, 0.3, 1), (0.2, -0.2, 1)),
                    hands=((-0.9, 9.8, 9.0), (3.8, 9.4, -3.4)), elbows=((-0.3, -1, 0), (0.4, -0.4, -1)),
                    sword=(0.3, -0.1, 1), head=(-14, 4))
    return ma.bake([(0, rig.sample(swing), None), (4, wind, "inout"), (8, wide, "in"), (15, wide, None),
                    (20, lunge, "in"), (25, lunge, None), (34, rig.sample(idle), "inout")])


def back_slash(rig):
    """Locked on with the stick pulled away (+ A): a quick flat cut from his right across to his left (frame 6) while he
    skips back off it (the move carries him), and a low landing on guard."""
    idle = rig.motion_frame(0)
    cock = keypose(rig, idle, body=dict(yaw=-30, drop=1.6, pitch=6),
                   feet=((-2.0, ANKLE, 0.8), (2.0, ANKLE, -0.8)),
                   hands=((-5.4, 9.2, 1.0), (2.4, 9.4, 2.6)), elbows=((-0.2, -1, -0.4), (0.4, -1, 0)),
                   sword=(-1, 0.1, 0.4), head=(-10, 4))
    cut = keypose(rig, idle, body=dict(yaw=28, drop=0.6, pitch=-6),
                  feet=((-1.7, 1.2, 1.6), (1.7, 1.4, 0.6)), knees=((0, 0.3, 1), (0, 0.3, 1)),
                  hands=((2.6, 10.2, 5.6), (3.4, 9.6, -1.6)), elbows=((-0.2, -1, 0), (0.4, -1, -0.3)),
                  sword=(1, 0.0, 0.5), head=(8, -2))
    land = keypose(rig, idle, body=dict(pitch=6, drop=2.0),
                   feet=((-1.9, ANKLE, 1.8), (2.0, ANKLE, -2.4)), knees=((-0.2, 0, 1), (0.3, 0, 1)),
                   hands=((-2.4, 9.4, 3.8), (2.4, 9.8, 2.8)), elbows=((-1, -0.5, 0), (1, -0.5, 0)),
                   sword=(0.0, 0.2, 1), head=(0, 4))
    return ma.bake([(0, rig.sample(idle), None), (3, cock, "inout"), (6, cut, "in"), (10, land, "in"),
                    (20, rig.sample(idle), "inout")])


def roll_slash(rig):
    """The evade's follow-up (A late in a roll or just after): out of the roll's low planted stance, a rising diagonal
    cut that drives him forward (frame 7), the blade up high ahead of him, held, and back to idle."""
    idle = rig.motion_frame(0)
    plant = roll_plant(rig)
    coil = keypose(rig, idle, body=dict(pitch=28, drop=3.4, ahead=0.6),
                   feet=((-2.0, ANKLE, 2.2), (1.9, ANKLE, -2.8)), knees=((-0.2, 0, 1), (0.3, -0.4, 1)),
                   hands=((-3.4, 4.8, -1.2), (2.6, 2.4, 3.4)), elbows=((-1, 0, -0.4), (1, 0, 0.2)),
                   sword=(-0.4, -0.5, -1), head=(0, -6))
    cut = keypose(rig, idle, body=dict(pitch=6, drop=1.4, ahead=1.6, yaw=16),
                  feet=((-1.9, ANKLE, 4.4), (2.1, ANKLE, -3.4)), knees=((0, 0.2, 1), (0.2, -0.2, 1)),
                  hands=((0.6, 15.0, 6.6), (3.4, 9.8, -2.4)), elbows=((-0.6, -1, 0), (0.4, -0.6, -1)),
                  sword=(0.35, 0.8, 0.6), head=(-6, -10))
    held = keypose(rig, idle, body=dict(pitch=4, drop=1.2, ahead=1.6, yaw=14),
                   feet=((-1.9, ANKLE, 4.4), (2.1, ANKLE, -3.4)), knees=((0, 0.2, 1), (0.2, -0.2, 1)),
                   hands=((0.8, 15.6, 5.8), (3.4, 9.8, -2.2)), elbows=((-0.6, -1, 0), (0.4, -0.6, -1)),
                   sword=(0.4, 0.9, 0.3), head=(-6, -12))
    return ma.bake([(0, plant, None), (3, coil, "inout"), (7, cut, "in"), (12, held, "out"), (22, rig.sample(idle), "inout")])


ANIMATIONS = {"toan_dash_thrust": (dash_thrust, 0.5), "toan_whirlwind": (whirlwind, 0.5), "toan_rising_slash": (rising_slash, 0.5),
              "toan_roll": (roll, 0.5), "toan_backstep": (backstep, 0.5), "toan_heavy_chop": (heavy_chop, 0.5),
              "toan_launcher": (launcher, 0.5), "toan_spin_finisher": (spin_finisher, 0.5), "toan_back_slash": (back_slash, 0.5),
              "toan_roll_slash": (roll_slash, 0.5)}


def main():
    data, out = sys.argv[1], sys.argv[2]
    sheets = sys.argv[3] if len(sys.argv) > 3 else None
    rig = ma.Rig(os.path.join(data, "c01d.chr"), os.path.join(data, "c01d.gltf"), "c01d.mot")
    for name, (build, speed) in ANIMATIONS.items():
        frames = build(rig)
        ma.write_json(os.path.join(out, name + ".json"), ma.motion_document(rig, "toan", frames, speed))
        if sheets:
            os.makedirs(sheets, exist_ok=True)
            step = max(1, len(frames) // 8)
            ma.stick_sheet(rig, [p for _, p in frames[::step]] + [frames[-1][1]], os.path.join(sheets, name + ".png"), cell=150)
        print(name, frames[-1][0], "frames")


if __name__ == "__main__":
    main()
