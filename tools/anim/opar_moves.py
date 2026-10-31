"""Opar's motions: a frog on Toan's skeleton (tools/anim/moonanim.py), written into his own pack's motion file.

python tools/anim/opar_moves.py <toan motions .chr> <c07d.gltf> <c07d.chr> [--sheets <folder>]

The first pack gives Toan's motions (art/opar/build/c07d_template.chr, his pack renamed), the glTF his skeleton (an
export of his built pack: art/opar/build/rig/c07d.gltf), and the last is his built pack, whose motion file is
replaced.

He fights as Toan, so the game plays Toan's motion numbers on him, read from his own pack (`c07d.mot`, the timeline
`base.cfg` cuts into numbered motions). Rather than add motions, this rewrites that timeline, so every native action
he takes is a frog's and Toan's pack is untouched:

- every frame of every motion gets his posture (frog()): the pelvis dropped into a squat, the body leaning forward,
  the feet set wider with the knees bowed out, each foot keeping the way it pointed;
- outside his attacks, the staff stands upright in his right hand (staff_up()): he plants it beside him;
- the motions seen most are made for him over that: the idle (squatting, the throat and belly heaving, a slow look
  round), the walk (a side-to-side waddle) and the run (a string of low frog hops, both feet together).

The pack's motion file is replaced with one key a frame for every channel (write_mot), and also saved beside the pack
as <pack>.mot, which tools/chr/build_character.py puts back after rebuilding the model. With --sheets, stick-figure
sheets of the made motions and of the frog posture over Toan's (sheet folder).

Space is glTF's: Y up, he faces +Z, his right is -X. His hips are wider than Toan's (art/opar/proportions.json), so
the rig is read from his own built pack and its export, not from Toan's.
"""

import argparse
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "chr"))
import chrtool  # noqa: E402
import moonanim as ma  # noqa: E402

RIGHT_LEG = ("jnt22_1", "jnt22_2", "eff22")
LEFT_LEG = ("jnt5_1", "jnt5_2", "eff5")
RIGHT_ARM = ("jnt17_1", "jnt17_2", "eff17")
LEFT_ARM = ("jnt9_1", "jnt9_2", "eff9")
FEET = (("jnt23_1", "eff24"), ("jnt6_1", "eff7"))  # right, left: the ankle and the toe tip
ANKLE = 0.7  # the ankle above the floor, standing

CROUCH = 2.0  # how far his pelvis sits below Toan's
LEAN = 9.0  # degrees forward
SPREAD = 0.35  # each foot this much further out than Toan's
STAFF_UP = (-0.05, 1.0, 0.05)  # the staff's line from his grip, held upright: a touch out and forward

# Toan's motion table (native number: frames), the stretches where the staff is a weapon in motion and is left as
# Toan swings it: the attacks, the charge, the guard, the skill, throwing, drinking, falling and the item pick-ups.
SWINGING = [(100, 110), (116, 150), (155, 206), (210, 230), (546, 566), (570, 590), (620, 655), (715, 766),
            (778, 815), (820, 884)]
IDLE, WALK, RUN = (10, 20), (35, 55), (70, 90)


def swinging(frame):
    return any(a <= frame <= b for a, b in SWINGING)


# ---------------------------------------------------------------------------------------------------------------------
# Posing


def set_world(rig, pose, bone, q_world):
    """Gives a bone a world rotation (its children follow)."""
    current = ma.fk(rig, pose)[ma._node(rig, bone)][2]
    ma.world_turn(rig, pose, bone, ma.qmul(q_world, ma.qconj(current)))


def world_of(rig, pose, names):
    world = ma.fk(rig, pose)
    index = {v[0]: v for v in world.values() if v[0]}
    return {n: index[n] for n in names}


def staff_up(rig, pose, direction=STAFF_UP):
    """Turns his right hand so the staff (the line from its grip, `weapon`, to `dcol`) points along `direction`."""
    w = world_of(rig, pose, ("weapon", "dcol"))
    line = ma._sub(w["dcol"][1], w["weapon"][1])
    ma.world_turn(rig, pose, "jnt18_1", ma.qbetween(line, direction))


def frog(rig, pose, crouch=CROUCH, lean=LEAN, spread=SPREAD, feet=None, knees_out=0.7, staff=True):
    """His posture over any pose: the body lowered and leaned forward, the feet planted where they were (or at
    `feet`, (right, left) ankle targets) and pushed out by `spread`, the knees bowed out; each foot keeps its world
    turn. The staff upright unless `staff` is False."""
    w = world_of(rig, pose, ("eff22", "eff5", "jnt23_1", "jnt6_1"))
    if feet is None:
        feet = (ma._add(w["eff22"][1], (-spread, 0, 0)), ma._add(w["eff5"][1], (spread, 0, 0)))
    ma.body(rig, pose, pitch=lean, drop=crouch)
    ma.leg(rig, pose, *RIGHT_LEG, feet[0], (-knees_out, 0.0, 1.0))
    ma.leg(rig, pose, *LEFT_LEG, feet[1], (knees_out, 0.0, 1.0))
    set_world(rig, pose, "jnt23_1", w["jnt23_1"][2])
    set_world(rig, pose, "jnt6_1", w["jnt6_1"][2])
    if staff:
        staff_up(rig, pose)
    return pose


TOES_OUT = 10.0  # degrees each foot turns out from straight ahead, the same both sides


def flat_feet(rig, pose, toe_drop=0.16, out=TOES_OUT):
    """Both feet flat along the floor, each turned out by `out` degrees. Not the way Toan's feet point: his stances
    turn one foot far out (68 degrees in the run's), which on a frog reads as a bowed, twisted foot."""
    for (ankle, toe), side in zip(FEET, (-1, 1)):
        a = math.radians(out) * side
        ma.aim(rig, pose, ankle, toe, (math.sin(a), -toe_drop, math.cos(a)))
    return pose


def hold(rig, pose, hand=(-4.4, 8.0, 2.6), elbow=(-1.0, -0.4, -0.5), off=None, off_elbow=(1.0, -0.3, -0.3)):
    """The staff hand at `hand` (out beside his belly, high enough that the staff's butt rests on the floor), the staff
    upright; the free hand at `off` if given."""
    ma.leg(rig, pose, *RIGHT_ARM, hand, elbow)
    if off is not None:
        ma.leg(rig, pose, *LEFT_ARM, off, off_elbow)
    staff_up(rig, pose)
    return pose


def head_turn(rig, pose, yaw=0.0, pitch=0.0):
    q = ma.qmul(ma.qaxis((0, 1, 0), yaw), ma.qaxis((1, 0, 0), pitch))
    ma.world_turn(rig, pose, "jnt12_1", q)
    return pose


def chest_swell(rig, pose, amount):
    """The chest lifted back and the throat out by `amount` (0-1), the breath of his idle."""
    ma.world_turn(rig, pose, "chn2", ma.qaxis((1, 0, 0), -4.0 * amount))
    ma.world_turn(rig, pose, "jnt12_1", ma.qaxis((1, 0, 0), 3.0 * amount))
    return pose


# ---------------------------------------------------------------------------------------------------------------------
# His own motions, each a list of (timeline frame, pose) inside a native motion's frames


def stand(rig, base, crouch=CROUCH, lean=LEAN, side=0.0, roll=0.0, bob=0.0, feet=None):
    """His squat over the native pose at `base`: feet planted wide at `feet` ((right, left) or the defaults), the knees
    bowed out less than in his other motions, so the staff he plants beside him clears his right knee."""
    pose = rig.sample(base)
    if feet is None:
        feet = ((-2.9, ANKLE, 0.5), (2.9, ANKLE, -0.1))
    pose = ma.body(rig, pose, roll=roll, side=side)
    return frog(rig, pose, crouch=crouch - bob, lean=lean, feet=feet, knees_out=0.45, staff=False)


def idle(rig):
    """Squatting wide, the staff planted beside him: the belly and throat heave twice through the loop, the head
    turns a little one way and back. The loop's first and last frames are the same pose."""
    a, b = IDLE
    out = []
    for f in range(a, b + 1):
        t = (f - a) / (b - a)
        breath = 0.5 - 0.5 * math.cos(2 * math.pi * 2 * t)
        pose = stand(rig, a, bob=-0.12 * breath)
        hold(rig, pose, hand=(-4.4, 8.0 + 0.12 * breath, 2.6), off=(3.9, 7.8 + 0.1 * breath, 2.0))
        flat_feet(rig, pose)
        chest_swell(rig, pose, breath)
        head_turn(rig, pose, yaw=10 * math.sin(2 * math.pi * t), pitch=-3)
        out.append((f, pose))
    return out


def walk(rig):
    """A waddle: short steps with the feet kept wide, the body rocking onto the foot that's down, a bob at each
    step, the staff planted and lifted in time."""
    a, b = WALK
    n = b - a
    out = []
    for f in range(a, b + 1):
        t = (f - a) / n
        ph = 2 * math.pi * t
        stride, lift = 1.6, 0.9
        right_z = stride * math.sin(ph)
        left_z = -right_z
        # each foot is lifted while it swings forward (the right while cos > 0) and planted while it pushes back
        right_y = ANKLE + lift * max(0.0, math.cos(ph))
        left_y = ANKLE + lift * max(0.0, -math.cos(ph))
        rock = -math.cos(ph)  # + over his right foot: the weight goes onto the planted one
        pose = stand(rig, a, roll=7 * rock, side=-0.45 * rock, bob=0.25 * abs(math.cos(ph)) - 0.1,
                     feet=((-2.9, right_y, 0.4 + right_z), (2.9, left_y, 0.4 + left_z)))
        hold(rig, pose, hand=(-4.4, 8.1, 2.4 + 0.4 * math.sin(ph)), off=(3.9, 7.6, 1.9 - 0.6 * math.sin(ph)))
        flat_feet(rig, pose)
        head_turn(rig, pose, yaw=-4 * rock, pitch=-4)
        out.append((f, pose))
    return out


def hop_pose(rig, base, phase):
    """One low frog hop at `phase` (0-1): crouched on both feet (0), pushing off with the legs driving back (0.2),
    stretched in the air with the feet trailing (0.4), the feet swung under ahead of him (0.65), landed in a deep
    crouch (0.8), and up into the crouch again (1)."""
    keys = [  # phase, pelvis height above the squat, lean, feet z, feet y, staff hand ahead
        (0.0, -0.6, 16, 0.4, ANKLE, 1.8),
        (0.2, 0.4, 28, -2.6, ANKLE, 2.4),
        (0.4, 2.2, 24, -3.6, ANKLE + 2.0, 3.2),
        (0.65, 2.0, 8, 2.6, ANKLE + 1.6, 2.6),
        (0.8, -0.9, 20, 1.2, ANKLE, 1.6),
        (1.0, -0.6, 16, 0.4, ANKLE, 1.8),
    ]
    for (p0, *v0), (p1, *v1) in zip(keys, keys[1:]):
        if p0 <= phase <= p1:
            k = ma.ease((phase - p0) / (p1 - p0), "inout")
            up, lean, fz, fy, hz = (x + (y - x) * k for x, y in zip(v0, v1))
            break
    pose = rig.sample(base)
    frog(rig, pose, crouch=CROUCH - up, lean=lean, feet=((-2.3, fy, fz), (2.3, fy, fz - 0.3)), knees_out=0.45,
         staff=False)
    hold(rig, pose, hand=(-4.4, 8.2 + up * 0.8, hz), off=(3.9, 7.6 + up * 0.8, 1.2 - 0.8 * (lean - 8) / 20))
    flat_feet(rig, pose, toe_drop=0.16 if fy <= ANKLE + 0.05 else 0.5)
    head_turn(rig, pose, pitch=-lean * 0.6)
    return pose


def run(rig):
    """Two hops through the run's loop, both feet together."""
    a, b = RUN
    n = b - a
    return [(f, hop_pose(rig, a, ((f - a) / n * 2) % 1.0 if f < b else 0.0)) for f in range(a, b + 1)]


def rest(rig):
    """His idle's first pose (frame 10): the start and end of the motions below."""
    return dict(idle(rig)[0][1])


# Toan's motion numbers 4 (hurt, 285-291), 6 and 7 (knocked down and getting up, 295-335) and 23 (defeated, 460-480)


HURT, KNOCKED, DEFEATED = (285, 291), (295, 335), (460, 480)
ON_BACK = dict(lean=-86, drop=4.4, hand=(1.6, -1.6, -2.4), off=(-1.6, -1.6, -2.2), staff=(-0.9, 0.1, -0.4), head=-6,
               knees=1.1)


def hurt(rig):
    """Hurt: rocked back with his throat puffed and the free arm flung up (287), half back (291)."""
    base = rest(rig)
    return ma.bake([(285, base, None),
                    (287, kit_pose(rig, base, lean=-16, swell=0.8, head=-22, hand=(-0.3, 0.6, -0.6), off=(0.8, 1.2, -0.6)), "out"),
                    (291, kit_pose(rig, base, lean=-8, swell=0.3, head=-8), "inout")])


def knocked(rig):
    """Knocked down: thrown up and back (298, 302), down on his back like a flipped frog (306) with his legs kicking
    in the air (310, 314); then (Toan's getting up, from 315) he rocks up to sit (319), rolls forward onto all fours
    (324), hops up (329) and squats again (335)."""
    base = rest(rig)
    kick_a = dict(ON_BACK, feet=((-1.6, 3.0, 3.6), (1.6, 4.6, 2.6)))
    kick_b = dict(ON_BACK, feet=((-1.6, 4.6, 2.6), (1.6, 3.0, 3.6)))
    return ma.bake([(295, base, None),
                    (298, kit_pose(rig, base, lean=-24, drop=-0.6, head=-24, swell=0.8, feet=((0, 0.6, 0.8), (0, 0.6, 0.6))), "out"),
                    (302, kit_pose(rig, base, lean=-55, drop=-2.0, head=-20, feet=((-0.5, 2.5, 2.5), (0.5, 2.5, 2.2)),
                                   hand=(0.4, 1.6, -1.2), off=(-0.4, 1.8, -1.2)), "out"),
                    (306, kit_pose(rig, base, **dict(ON_BACK, feet=((-1.2, 4.2, 3.2), (1.2, 4.0, 3.0)))), "in"),
                    (310, kit_pose(rig, base, **kick_a), "inout"),
                    (314, kit_pose(rig, base, **kick_b), "inout"),
                    (315, kit_pose(rig, base, **kick_b), None),
                    (319, kit_pose(rig, base, lean=-30, drop=3.0, head=-6, feet=((0, 0, 1.5), (0, 0, 1.3)),
                                   hand=(0.6, -3.0, -1.6), off=(-0.6, -3.0, -1.6)), "inout"),
                    (324, kit_pose(rig, base, lean=40, drop=2.2, head=-20, hand=(0.4, -4.0, 3.0), off=(-0.4, -4.0, 2.8),
                                   staff=(0.1, 0.2, 1)), "inout"),
                    (329, kit_pose(rig, base, lean=10, drop=-0.6, head=-8), "out"),
                    (335, base, "inout")])


def defeated(rig):
    """Defeated: struck, his throat puffed (463), he sways (467), topples back (471), lands belly-up (475) and lies
    still with his legs splayed (480; the game holds it)."""
    base = rest(rig)
    return ma.bake([(460, base, None),
                    (463, kit_pose(rig, base, lean=-14, head=-24, swell=1.0), "out"),
                    (467, kit_pose(rig, base, lean=-6, roll=12, drop=1.0, head=-10), "inout"),
                    (471, kit_pose(rig, base, lean=-50, drop=2.6, head=-18, feet=((0, 1.5, 1.5), (0, 1.5, 1.3)),
                                   hand=(0.8, 0.6, -1.4), off=(-0.8, 0.8, -1.4)), "in"),
                    (475, kit_pose(rig, base, **dict(ON_BACK, feet=((-1.4, 4.4, 3.0), (1.4, 4.4, 3.0)))), "out"),
                    (480, kit_pose(rig, base, **dict(ON_BACK, head=4, knees=1.6, feet=((-2.4, 2.8, 3.4), (2.4, 2.8, 3.4)))), "inout")])


MADE = {"idle": idle, "walk": walk, "run": run, "hurt": hurt, "knocked": knocked, "defeated": defeated}


# ---------------------------------------------------------------------------------------------------------------------
# The motion file


def write_mot(rig, original, poses):
    """A motion file: the original's channels (their headers kept), each keyed at every frame of `poses`
    ({frame: pose})."""
    frames = sorted(poses)
    out = bytearray()
    off = 0
    headers = []
    while True:
        head = original[off:off + 32]
        frame, target, typ, size, count, more = struct.unpack_from("<IIiIII", head, 0)
        headers.append(head)
        off += 32 + count * 32
        if more == 0:
            break
    by_frame = {(c["frame"], c["type"]): c for c in rig.channels}
    for i, head in enumerate(headers):
        frame, target, typ, size, count, more = struct.unpack_from("<IIiIII", head, 0)
        channel = by_frame[(frame, typ)]
        key = (channel["bone"], ma.TYPES[typ])
        body = bytearray()
        for f in frames:
            v = poses[f][key]
            if typ == 0:
                values = ma.gltf_to_game(v)
            else:
                values = tuple(v) + (0.0,)
            body += struct.pack("<4I4f", f, 0, 0, 0, *values)
        h = bytearray(head)
        last = i == len(headers) - 1
        struct.pack_into("<II", h, 16, len(frames), 0 if last else 32 + len(frames) * 32)
        out += h + body
    return bytes(out)


def write_shadow_mot(rig, original, poses):
    """The shadow's motion file (c07s.mot): its channels, on the same skeleton as the model's, keyed from the model's
    poses wherever the model has that channel, so the shadow (still Toan's shape) crouches and leans with him rather
    than standing tall through his head. A channel the model lacks keeps its original keys."""
    frames = sorted(poses)
    sample = poses[frames[0]]
    out = bytearray()
    off = 0
    while True:
        head = bytearray(original[off:off + 32])
        frame, target, typ, size, count, more = struct.unpack_from("<IIiIII", head, 0)
        body = original[off + 32:off + 32 + count * 32]
        off += 32 + count * 32
        last = more == 0
        key = (rig.names[frame], ma.TYPES.get(typ)) if frame < len(rig.names) else None
        if key in sample:
            body = bytearray()
            for f in frames:
                v = poses[f][key]
                values = ma.gltf_to_game(v) if typ == 0 else tuple(v) + (0.0,)
                body += struct.pack("<4I4f", f, 0, 0, 0, *values)
            count = len(frames)
        struct.pack_into("<II", head, 16, count, 0 if last else 32 + count * 32)
        out += head + body
        if last:
            return bytes(out)


# ---------------------------------------------------------------------------------------------------------------------
# His attacks: mod motions (animations.player_register, character "opar") on his own frog motions, each starting and
# ending on his idle (native frame 10 of his rewritten pack), played by his moves in the Gauntlet


def spit_pose(rig, base, lean=0.0, drop=0.0, swell=0.0, head=0.0, ahead=0.0, lift=0.0, feet_back=0.0):
    """His idle with the body leaned (forward +), lowered, the throat and belly swelled (0-1.6) and the head pitched
    (down/forward +); the feet stay planted (lifted by `lift` and moved back by `feet_back` for a hop) and the
    staff stays upright in his hand."""
    pose = dict(base)
    w = world_of(rig, pose, ("eff22", "eff5", "jnt23_1", "jnt6_1"))
    feet = [ma._add(w[e][1], (0.0, lift, -feet_back)) for e in ("eff22", "eff5")]
    ma.body(rig, pose, pitch=lean, drop=drop, ahead=ahead)
    ma.leg(rig, pose, *RIGHT_LEG, feet[0], (-0.7, 0.0, 1.0))
    ma.leg(rig, pose, *LEFT_LEG, feet[1], (0.7, 0.0, 1.0))
    set_world(rig, pose, "jnt23_1", w["jnt23_1"][2])
    set_world(rig, pose, "jnt6_1", w["jnt6_1"][2])
    if swell:
        ma.world_turn(rig, pose, "chn2", ma.qaxis((1, 0, 0), -6.0 * swell))
    if head:
        head_turn(rig, pose, pitch=head)
    staff_up(rig, pose)
    return pose


def spit(rig):
    """Spit (20 frames): rocks back with the throat puffed (5), snaps the head forward and spits (8: the glob leaves
    at 40%), a beat leaning in (12), and back to idle."""
    idle = rig.sample(IDLE[0])
    return ma.bake([(0, idle, None),
                    (5, spit_pose(rig, idle, lean=-12, swell=1.0, head=-18), "out"),
                    (8, spit_pose(rig, idle, lean=16, drop=0.3, head=16, ahead=0.5), "in"),
                    (12, spit_pose(rig, idle, lean=12, drop=0.3, head=10, ahead=0.4), "out"),
                    (20, idle, "inout")])


def gob(rig):
    """Gob (26 frames): a deep wind-up, the body thrown back and the throat swollen (8), a lunging spit with the head
    whipped forward (12: three globs fan out at 46%), held (17), back to idle."""
    idle = rig.sample(IDLE[0])
    return ma.bake([(0, idle, None),
                    (8, spit_pose(rig, idle, lean=-18, drop=0.4, swell=1.4, head=-24), "out"),
                    (12, spit_pose(rig, idle, lean=24, drop=0.8, head=20, ahead=1.0), "in"),
                    (17, spit_pose(rig, idle, lean=20, drop=0.8, head=14, ahead=0.9), "out"),
                    (26, idle, "inout")])


def bubble(rig):
    """Bubble (34 frames): sinks into a deep squat as the belly and throat swell up (10), swelling further, trembling
    (14, 18), then heaves forward and lets the bubble go (20: at 59%), held (25), back to idle."""
    idle = rig.sample(IDLE[0])
    return ma.bake([(0, idle, None),
                    (10, spit_pose(rig, idle, lean=-6, drop=1.0, swell=1.5, head=-12), "out"),
                    (14, spit_pose(rig, idle, lean=-9, drop=1.1, swell=1.7, head=-16), "inout"),
                    (18, spit_pose(rig, idle, lean=-7, drop=1.0, swell=1.8, head=-14), "inout"),
                    (20, spit_pose(rig, idle, lean=22, drop=0.6, head=18, ahead=0.8), "in"),
                    (25, spit_pose(rig, idle, lean=18, drop=0.6, head=12, ahead=0.7), "out"),
                    (34, idle, "inout")])


def back_hop(rig):
    """Back Hop (22 frames): a quick crouch (3), a hop backward with the feet swung forward under him and a spit at
    the top (7: at 32%), a crouched landing (12), settled (16), idle (22). The move carries him back."""
    idle = rig.sample(IDLE[0])
    return ma.bake([(0, idle, None),
                    (3, spit_pose(rig, idle, lean=14, drop=0.9, head=6), "out"),
                    (7, spit_pose(rig, idle, lean=6, drop=-1.6, lift=1.4, feet_back=-1.2, head=18, ahead=0.4), "out"),
                    (12, spit_pose(rig, idle, lean=16, drop=1.0, head=8), "in"),
                    (16, spit_pose(rig, idle, lean=8, drop=0.5, head=2), "out"),
                    (22, idle, "inout")])


# His kit (docs/OPAR_PLAN.md §3): the same idle-based keyposes, with his legs, arms and staff placed freely.

HAND = (-4.4, 8.0, 2.6)  # the staff hand at idle, and the free one
OFF = (3.2, 6.6, 1.1)


def kit_pose(rig, base, lean=0.0, drop=0.0, ahead=0.0, roll=0.0, yaw=0.0, feet=None, toes=None, swell=0.0, head=0.0,
             hand=None, off=None, staff=STAFF_UP, knees=0.7):
    """His idle moved about: the body leaned (forward +), rolled, turned, lowered by `drop` (negative lifts him) and
    moved `ahead`; `feet` as ((dx, dy, dz) right, left) moves from where each stands at idle (None: planted), with the
    toes pointing along `toes` (None: as at idle); the throat swelled and the head pitched as spit_pose's. `hand` and
    `off` put the staff hand and the free hand that far from where they are at idle (shifted with the body), and the
    staff points along `staff`."""
    pose = dict(base)
    w = world_of(rig, pose, ("eff22", "eff5", "jnt23_1", "jnt6_1"))
    moves = feet or ((0, 0, 0), (0, 0, 0))
    targets = [ma._add(w[e][1], m) for e, m in zip(("eff22", "eff5"), moves)]
    ma.body(rig, pose, yaw=yaw, pitch=lean, roll=roll, drop=drop, ahead=ahead)
    ma.leg(rig, pose, *RIGHT_LEG, targets[0], (-knees, 0.0, 1.0))
    ma.leg(rig, pose, *LEFT_LEG, targets[1], (knees, 0.0, 1.0))
    set_world(rig, pose, "jnt23_1", w["jnt23_1"][2])
    set_world(rig, pose, "jnt6_1", w["jnt6_1"][2])
    if toes is not None:
        for ankle, toe in FEET:
            ma.aim(rig, pose, ankle, toe, toes)
    if swell:
        ma.world_turn(rig, pose, "chn2", ma.qaxis((1, 0, 0), -6.0 * swell))
    if head:
        head_turn(rig, pose, pitch=head)
    shift = (0.0, -drop, ahead)
    if hand is not None:
        ma.leg(rig, pose, *RIGHT_ARM, ma._add(ma._add(HAND, shift), hand), (-1.0, -0.4, -0.5))
    if off is not None:
        ma.leg(rig, pose, *LEFT_ARM, ma._add(ma._add(OFF, shift), off), (1.0, -0.6, -0.2))
    staff_up(rig, pose, staff)
    return pose


def belly_slide(rig):
    """Belly Slide (36 frames): a crouch (4), a dive forward with the staff out ahead (8), flat on his belly sliding,
    the feet trailing (12 to 24: the hits at 30% and 55%), pushed back up onto his feet (30), idle (36). The move's
    lunge carries him."""
    idle = rig.sample(IDLE[0])
    flat = dict(lean=80, drop=3.8, ahead=1.2, feet=((0.6, 1.0, -4.6), (-0.6, 1.0, -4.8)), toes=(0, -0.6, -1),
                head=-38, hand=(1.2, 0.6, 6.0), off=(-1.0, 0.4, 5.6), staff=(0.05, 0.1, 1), knees=0.2)
    return ma.bake([(0, idle, None),
                    (4, kit_pose(rig, idle, lean=26, drop=1.2, head=-8, hand=(0, 0, 1.5), off=(0, 0, 1.2)), "out"),
                    (8, kit_pose(rig, idle, lean=58, drop=2.4, ahead=0.8, feet=((0.4, 1.6, -3.0), (-0.4, 1.4, -3.2)),
                                 toes=(0, -0.8, -1), head=-26, hand=(1.0, 1.0, 5.0), off=(-0.8, 0.8, 4.6),
                                 staff=(0.05, 0.25, 1), knees=0.3), "in"),
                    (12, kit_pose(rig, idle, **flat), "out"),
                    (24, kit_pose(rig, idle, **dict(flat, lean=78, head=-34)), "inout"),
                    (30, kit_pose(rig, idle, lean=30, drop=1.4, head=-10, hand=(0, 0, 1.6), off=(0, 0, 1.4)), "inout"),
                    (36, idle, "inout")])


def staff_swat(rig):
    """Staff Swat (30 frames): the staff drawn back across his body (5), swung out flat to his right (9: the move's
    spin turns him round with it held out, the hits at 35% and 60%), held out through the turn (22), back to idle
    (30)."""
    idle = rig.sample(IDLE[0])
    out = dict(lean=4, drop=0.9, roll=-8, hand=(-2.4, 0.4, -0.8), off=(1.6, 0.6, -0.4), staff=(-1, 0.08, -0.25),
               head=-4)
    return ma.bake([(0, idle, None),
                    (5, kit_pose(rig, idle, lean=10, drop=0.8, roll=10, yaw=20, hand=(3.2, 0.6, 1.2), off=(1.0, 0.0, 0.6),
                                 staff=(1, 0.15, 0.6), head=-2), "out"),
                    (9, kit_pose(rig, idle, **out), "in"),
                    (22, kit_pose(rig, idle, **dict(out, roll=-4)), "inout"),
                    (30, idle, "inout")])


def frog_hop(rig):
    """Frog Hop (24 frames): a deep crouch (3), the push off with the legs driving back (7), stretched out in the air
    (11), the feet swung through ahead (15), landed in a crouch (18), idle (24). The move carries him; its landing is
    where a late attack becomes the Leap Strike."""
    idle = rig.sample(IDLE[0])
    return ma.bake([(0, idle, None),
                    (3, kit_pose(rig, idle, lean=18, drop=1.2, head=-8, hand=(0, 0, 0.8)), "out"),
                    (7, kit_pose(rig, idle, lean=30, drop=-1.2, feet=((0, 0.6, -2.6), (0, 0.6, -2.8)), toes=(0, -1, -0.6),
                                 head=-18, hand=(0, 0.6, 1.6), off=(0, 1.0, -1.0)), "in"),
                    (11, kit_pose(rig, idle, lean=22, drop=-3.0, feet=((0, 2.4, -3.0), (0, 2.4, -3.2)), toes=(0, -1, -0.6),
                                  head=-16, hand=(0, 1.0, 2.0), off=(0, 1.6, -1.2)), "out"),
                    (15, kit_pose(rig, idle, lean=6, drop=-2.2, feet=((0, 2.0, 2.2), (0, 2.0, 2.0)), head=-6,
                                  hand=(0, 0.6, 1.4), off=(0, 0.6, 0.6)), "inout"),
                    (18, kit_pose(rig, idle, lean=20, drop=1.2, head=-8, hand=(0, -0.2, 1.0)), "in"),
                    (24, idle, "inout")])


def tongue_lash(rig):
    """Tongue Lash (32 frames): rears back with the throat puffed (6), thrusts the head out at the target (10: the
    lash's hit at 33%, which yanks the enemy in), holds it (15), snaps back (19), and bonks what he pulled in with the
    staff brought down ahead of him (23: at 72%), idle (32)."""
    idle = rig.sample(IDLE[0])
    return ma.bake([(0, idle, None),
                    (6, kit_pose(rig, idle, lean=-14, swell=1.2, head=-22, off=(0, 0.4, -0.6)), "out"),
                    (10, kit_pose(rig, idle, lean=28, drop=0.6, ahead=1.0, head=26, off=(0.6, -0.4, 0.6)), "in"),
                    (15, kit_pose(rig, idle, lean=26, drop=0.6, ahead=1.0, head=24, off=(0.6, -0.4, 0.6)), "inout"),
                    (19, kit_pose(rig, idle, lean=-6, drop=0.4, head=-10, hand=(0.6, 3.4, 0.2), staff=(0, 0.7, -0.7)),
                     "out"),
                    (23, kit_pose(rig, idle, lean=22, drop=0.9, ahead=0.6, head=8, hand=(1.0, 0.6, 3.8),
                                  staff=(0.05, -0.35, 1)), "in"),
                    (32, idle, "inout")])


def croak(rig):
    """Croak (40 frames): sinks with a breath in (8), the throat and belly swelling up hugely, the head thrown back
    (16), the croak itself (20: the ring at 50%), held trembling (24, 28), idle (40)."""
    idle = rig.sample(IDLE[0])
    big = dict(lean=-14, drop=0.2, swell=2.6, head=-34, off=(1.8, 1.6, -0.4))
    return ma.bake([(0, idle, None),
                    (8, kit_pose(rig, idle, lean=4, drop=0.8, swell=1.0, head=-6, off=(0.4, -0.4, 0)), "out"),
                    (16, kit_pose(rig, idle, lean=-10, drop=0.4, swell=2.2, head=-26, off=(1.2, 1.0, -0.2)), "inout"),
                    (20, kit_pose(rig, idle, **big), "out"),
                    (24, kit_pose(rig, idle, **dict(big, swell=2.4, head=-30)), "inout"),
                    (28, kit_pose(rig, idle, **dict(big, swell=2.6, head=-33)), "inout"),
                    (40, idle, "inout")])


def leap_strike(rig):
    """Leap Strike (36 frames): a crouch (3), a high leap with the staff raised over his head (8, 12), down onto the
    enemy with the staff brought down (17: the hit at 47%), a spit off the top of it (22: the glob at 61%), settled
    (28), idle (36)."""
    idle = rig.sample(IDLE[0])
    return ma.bake([(0, idle, None),
                    (3, kit_pose(rig, idle, lean=16, drop=1.2, head=-8, hand=(0, 0, 0.6)), "out"),
                    (8, kit_pose(rig, idle, lean=4, drop=-4.0, feet=((0, 3.2, -1.2), (0, 3.2, -1.4)), toes=(0, -1, -0.3),
                                 head=-10, hand=(1.4, 6.0, -0.6), staff=(0.1, 0.6, -0.8), off=(0, 2.0, 0)), "out"),
                    (12, kit_pose(rig, idle, lean=-6, drop=-4.6, feet=((0, 3.6, 0.6), (0, 3.6, 0.4)), head=-14,
                                  hand=(1.4, 6.4, -1.0), staff=(0.1, 0.4, -1), off=(0, 2.4, 0)), "inout"),
                    (17, kit_pose(rig, idle, lean=26, drop=1.2, ahead=0.6, head=6, hand=(1.0, 0.0, 4.0),
                                  staff=(0.05, -0.45, 1)), "in"),
                    (22, kit_pose(rig, idle, lean=18, drop=0.8, ahead=0.6, head=18, hand=(1.0, 0.2, 3.6),
                                  staff=(0.05, -0.4, 1)), "out"),
                    (28, kit_pose(rig, idle, lean=8, drop=0.4, head=4), "inout"),
                    (36, idle, "inout")])


def jump_slam(rig):
    """Jump Slam's leap (14 frames): a deep crouch with the throat swelling (5), the leap, tucked with the staff
    raised in both hands (10), at the top of it (14). There the smoke covers him and the giant Opar slams down in his
    place (the mod: player.form_set, then the monster's own press). No hang at the top: the user saw a pause there."""
    idle = rig.sample(IDLE[0])
    high = dict(feet=((0, 5.2, -0.6), (0, 5.2, -0.8)), toes=(0, -1, -0.2), hand=(1.6, 7.0, -0.4), off=(-1.8, 7.2, -0.2),
                staff=(0.1, 0.5, -1))
    return ma.bake([(0, idle, None),
                    (5, kit_pose(rig, idle, lean=20, drop=1.6, swell=1.2, head=-10, hand=(0, -0.4, 1.0), off=(0, -0.4, 0.8)), "out"),
                    (10, kit_pose(rig, idle, lean=-4, drop=-5.0, head=-16, **high), "out"),
                    (14, kit_pose(rig, idle, lean=-8, drop=-7.0, head=-20, **high), "inout")])


ATTACKS = {"opar_spit": spit, "opar_gob": gob, "opar_bubble": bubble, "opar_back_hop": back_hop,
           "opar_belly_slide": belly_slide, "opar_staff_swat": staff_swat, "opar_frog_hop": frog_hop,
           "opar_tongue_lash": tongue_lash, "opar_croak": croak, "opar_leap_strike": leap_strike,
           "opar_jump_slam": jump_slam}


def timeline(rig):
    """Every frame of his motion file: the frog posture over Toan's, his own motions where they are made."""
    last = max(k[0] for c in rig.channels for k in c["keys"])
    poses = {}
    made = {}
    for fn in MADE.values():
        made.update(dict(fn(rig)))
    for f in range(1, last + 1):
        if f in made:
            poses[f] = made[f]
        else:
            pose = rig.sample(f)
            poses[f] = frog(rig, pose, staff=not swinging(f))
    return poses


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("source")
    p.add_argument("gltf")
    p.add_argument("pack")
    p.add_argument("--sheets")
    p.add_argument("--anims", help="folder for his attack motions (moonmod-motion files), e.g. the mod's resources/anims")
    args = p.parse_args(argv)
    rig = ma.Rig(args.source, args.gltf)  # Toan's motions on his skeleton
    original = ma.pack_members(open(args.source, "rb").read())[rig.mot_name]
    toan = rig
    poses = timeline(rig)
    mot = write_mot(rig, original, poses)
    out = args.pack
    data = open(out, "rb").read()
    open(os.path.splitext(out)[0] + ".mot", "wb").write(mot)
    data = chrtool.replace_member(data, rig.mot_name, mot)
    # the shadow's motions too (c07s.mot): Toan's, played as they were, stood his shadow upright through the frog,
    # and its head showed round his in close-ups (opening a chest, an Atlamillia)
    shadow_name = next(n for n in ma.pack_members(data) if n.endswith("s.mot"))
    shadow = write_shadow_mot(rig, ma.pack_members(open(args.source, "rb").read())[shadow_name], poses)
    open(os.path.join(os.path.dirname(out), shadow_name), "wb").write(shadow)
    data = chrtool.replace_member(data, shadow_name, shadow)
    open(out, "wb").write(data)
    # check: read back, every channel at every frame is what was written
    back = ma.Rig(out, args.gltf)
    worst = 0.0
    for f in range(1, max(poses) + 1, 7):
        got = back.sample(f)
        for key, v in poses[f].items():
            if key in got:
                if key[1] == "rotation":
                    d = 1 - abs(sum(a * b for a, b in zip(v, got[key])))
                else:
                    d = max(abs(a - b) for a, b in zip(v, got[key]))
                worst = max(worst, d)
    print("%s: %d frames, %d channels, motion file %d bytes, read back within %.2g" %
          (out, len(poses), len(rig.channels), len(mot), worst))
    if args.anims:
        for name, fn in ATTACKS.items():
            frames = fn(back)
            ma.write_json(os.path.join(args.anims, name + ".json"), ma.motion_document(back, "opar", frames))
            if args.sheets:
                os.makedirs(args.sheets, exist_ok=True)
                picks = [pose for f, pose in frames if f % 2 == 0]
                ma.stick_sheet(back, picks, os.path.join(args.sheets, name + ".png"))
        print("attack motions:", ", ".join(ATTACKS), "->", args.anims)
    if args.sheets:
        os.makedirs(args.sheets, exist_ok=True)
        for name, (a, b) in (("idle", IDLE), ("walk", WALK), ("run", RUN), ("hurt", HURT), ("knocked", KNOCKED),
                             ("defeated", DEFEATED)):
            frames = list(range(a, b + 1, max(1, (b - a) // 8)))
            ma.stick_sheet(back, [back.sample(f) for f in frames], os.path.join(args.sheets, "opar_%s.png" % name))
        picks = [("idle", 15), ("damage", 288), ("big damage", 305), ("defeated", 470), ("combo", 825),
                 ("guard", 220), ("hurt run", 700), ("strafe", 350)]
        ma.stick_sheet(toan, [toan.sample(f) for _, f in picks], os.path.join(args.sheets, "toan_native.png"))
        ma.stick_sheet(back, [back.sample(f) for _, f in picks], os.path.join(args.sheets, "opar_native.png"))
    return 0 if worst < 1e-3 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
