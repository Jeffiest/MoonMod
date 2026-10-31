"""Xiao's Gauntlet animations, authored on her own rig (tools/anim/moonanim.py; see docs/ANIMATION_GUIDE.md).

python tools/anim/xiao_moves.py <dun/mainchara folder> <out folder> [sheet folder]

Writes xiao_triple_shot.json, xiao_tumble.json, xiao_hop_shot.json, xiao_heavy_shot.json and xiao_volley.json
(moonmod-motion v1).

Xiao holds the slingshot in her LEFT hand and draws the band with her right. The shot keyposes start from her own
aim (native frame 251: slingshot arm out, band hand drawn to the chest) and release (253), and change the body and
legs around them, so the arms aim as the game's own shot does. Space: Y up, Xiao facing +Z, her right -X; ankles rest
0.8 above the floor. Her body centre is c_ctr (Toan's is ctr).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moonanim as ma  # noqa: E402

ANKLE = 0.8
CENTER = "c_ctr"
RIGHT_LEG = ("jnt25_1", "jnt25_2", "eff25")
LEFT_LEG = ("jnt3_1", "jnt3_2", "eff3")
RIGHT_ARM = ("jnt20_1", "jnt20_2", "eff20")
LEFT_ARM = ("jnt10_1", "jnt10_2", "eff10")  # the slingshot hand
RIGHT_FOOT = ("jnt26_1", "eff27")
LEFT_FOOT = ("jnt4_1", "eff5")
FOOT_FLAT = (0, -0.23, 1)  # ankle to toe tip on a flat foot, measured at her idle
AIM, RELEASE = 251, 253.5  # native frames: the slingshot drawn, the band let go


def body_joints(rig, pose):
    """The skeleton joints in world space (not mesh nodes, the tail's or ears' points, or the slingshot's)."""
    nodes = rig.gltf["nodes"]
    return [(name, p) for i, (name, p, _) in ma.fk(rig, pose).items()
            if name and name.startswith(("jnt", "eff", "chn")) and "mesh" not in nodes[i]]


def keep_above_floor(rig, frames, lo, hi, clearance=0.3):
    """Lifts the body of every frame from lo to hi so its lowest joint clears the floor."""
    for f, pose in frames:
        if lo <= f <= hi:
            lowest = min(p[1] for _, p in body_joints(rig, pose))
            if lowest < clearance:
                t = pose[(CENTER, "translation")]
                pose[(CENTER, "translation")] = (t[0], t[1] + clearance - lowest, t[2])
    return frames


def keypose(rig, base, body=None, feet=None, knees=((0, 0, 1), (0, 0, 1)), hands=None, elbows=((0, -1, 0), (0, -1, 0)),
            head=None):
    """One keypose from native frame `base`: body (ma.body arguments), feet (right, left) ankle targets, hands
    (right, left) wrist targets (either may be None to keep the base's arm), head (yaw, pitch)."""
    pose = rig.sample(base)
    if body:
        ma.body(rig, pose, center=CENTER, **body)
    if feet:
        ma.leg(rig, pose, *RIGHT_LEG, feet[0], knees[0])
        ma.leg(rig, pose, *LEFT_LEG, feet[1], knees[1])
        for (ankle, toe), at in ((RIGHT_FOOT, feet[0]), (LEFT_FOOT, feet[1])):
            if at[1] <= ANKLE + 0.05:
                ma.aim(rig, pose, ankle, toe, FOOT_FLAT)
    if hands:
        if hands[0]:
            ma.leg(rig, pose, *RIGHT_ARM, hands[0], elbows[0])
        if hands[1]:
            ma.leg(rig, pose, *LEFT_ARM, hands[1], elbows[1])
    if head:
        q = ma.qmul(ma.qaxis((0, 1, 0), head[0]), ma.qaxis((1, 0, 0), head[1]))
        ma.world_turn(rig, pose, "jnt12_1", q)
    return pose


def triple_shot(rig):
    """Out of a run: she skids into a wide, low stance with the slingshot already coming up, draws (frame 7), lets three
    shots go at once (10, the move fans them), rides the recoil back a little, and stands (24)."""
    idle = rig.motion_frame(0)
    run = rig.motion_frame(1, 0.3)
    stance = ((-2.4, ANKLE, 1.6), (2.2, ANKLE, -1.8))
    skid = keypose(rig, AIM, body=dict(pitch=10, drop=2.2, ahead=0.6, yaw=-8),
                   feet=((-2.6, ANKLE, 2.6), (2.0, ANKLE, -2.4)), knees=((-0.3, 0, 1), (0.3, 0, 1)), head=(0, 4))
    draw = keypose(rig, AIM, body=dict(pitch=4, drop=2.0, yaw=-6), feet=stance, knees=((-0.3, 0, 1), (0.3, 0, 1)))
    loose = keypose(rig, RELEASE, body=dict(pitch=-6, drop=1.8, ahead=-0.4, yaw=-4), feet=stance,
                    knees=((-0.3, 0, 1), (0.3, 0, 1)), head=(0, -4))
    held = keypose(rig, RELEASE, body=dict(pitch=-2, drop=1.6, ahead=-0.3), feet=stance,
                   knees=((-0.3, 0, 1), (0.3, 0, 1)))
    return ma.bake([(0, rig.sample(run), None), (4, skid, "out"), (7, draw, "inout"), (10, loose, "in"), (15, held, "out"),
                    (24, rig.sample(idle), "inout")])


def tucked(rig, base, pitch, drop, ahead=0.0):
    """A keypose of the tumble: the body pitched forward by `pitch` degrees and curled into a ball, knees to the chest,
    hands at the shins (the slingshot with them), lowest joint resting on the floor."""
    pose = rig.sample(base)
    ma.body(rig, pose, pitch=pitch, drop=drop, ahead=ahead, center=CENTER)
    turn = ma.qaxis((1, 0, 0), pitch)
    side = ma.qrot(turn, (1, 0, 0))
    ma.world_turn(rig, pose, "jnt2_1", ma.qaxis(side, 36))
    ma.world_turn(rig, pose, "jnt12_1", ma.qaxis(side, 30))
    hips = ma.joint(rig, pose, "jnt1_1")
    chest = ma.joint(rig, pose, "jnt2_1")

    def at(origin, local):
        return ma._add(origin, ma.qrot(turn, local))

    ma.leg(rig, pose, *RIGHT_LEG, at(hips, (-1.1, -1.8, 2.6)), ma.qrot(turn, (0, 0.6, 1)))
    ma.leg(rig, pose, *LEFT_LEG, at(hips, (1.1, -1.8, 2.6)), ma.qrot(turn, (0, 0.6, 1)))
    ma.leg(rig, pose, *RIGHT_ARM, at(chest, (-1.4, -3.0, 2.8)), ma.qrot(turn, (-1, -0.4, 0)))
    ma.leg(rig, pose, *LEFT_ARM, at(chest, (1.4, -3.0, 2.8)), ma.qrot(turn, (1, -0.4, 0)))
    lowest = min(p[1] for _, p in body_joints(rig, pose))
    t = pose[(CENTER, "translation")]
    pose[(CENTER, "translation")] = (t[0], t[1] + (0.4 - lowest), t[2])
    return pose


def tumble(rig):
    """The evade with the stick pushed: out of the run, a low dive (3), a quick tucked somersault (quarter turns 5, 8,
    11), feet planted in a split stance with a hand down (14), up into her ready crouch (18) and idle (24)."""
    idle = rig.motion_frame(0)
    run = rig.motion_frame(1, 0.3)
    dive = keypose(rig, idle, body=dict(pitch=34, drop=2.2, ahead=1.0),
                   feet=((-1.4, ANKLE, -1.2), (1.4, ANKLE, 1.4)),
                   hands=((-1.4, 4.8, 5.0), (1.4, 4.8, 5.0)), elbows=((-1, -0.3, 0), (1, -0.3, 0)), head=(0, 18))
    plant = keypose(rig, idle, body=dict(pitch=30, drop=3.2, ahead=0.5),
                    feet=((-1.8, ANKLE, 2.0), (1.7, ANKLE, -2.4)), knees=((-0.2, 0, 1), (0.3, -0.4, 1)),
                    hands=((-2.4, 1.4, 3.0), (2.8, 4.6, 1.0)), elbows=((-1, 0, 0.2), (1, 0, -0.4)), head=(0, -6))
    rise = keypose(rig, idle, body=dict(pitch=14, drop=1.8, ahead=0.3),
                   feet=((-1.8, ANKLE, 1.8), (1.8, ANKLE, -2.0)), knees=((-0.2, 0, 1), (0.3, 0, 1)),
                   hands=((-2.4, 7.0, 2.2), (2.6, 7.4, 2.6)), elbows=((-1, -0.4, 0), (1, -0.4, 0)), head=(0, 0))
    frames = ma.bake([(0, rig.sample(run), None), (3, dive, "in"), (5, tucked(rig, idle, 100, 4.0, 0.5), None),
                      (8, tucked(rig, idle, 190, 4.3), None), (11, tucked(rig, idle, 280, 4.0), "out"),
                      (14, plant, "in"), (18, rise, "inout"), (24, rig.sample(idle), "inout")])
    return keep_above_floor(rig, frames, 3, 12)


def hop_shot(rig):
    """The evade with the stick at rest: a quick crouch with the slingshot coming up (3), a low skip straight back with
    it drawn (6), the shot let go at the top (7, the move fires it), a staggered landing still aiming (10), a settle (13)
    and idle (20). The feet leave the floor by half a unit at most."""
    idle = rig.motion_frame(0)
    stance = ((-1.8, ANKLE, 1.6), (2.0, ANKLE, -2.2))
    crouch = keypose(rig, AIM, body=dict(pitch=8, drop=1.6), feet=((-1.8, ANKLE, 0.6), (1.8, ANKLE, -0.8)),
                     knees=((-0.2, 0, 1), (0.2, 0, 1)))
    hop = keypose(rig, AIM, body=dict(pitch=-8, drop=0.2), feet=((-1.6, 1.3, 2.0), (1.7, 1.2, 0.8)),
                  knees=((0, 0.3, 1), (0, 0.3, 1)), head=(0, -2))
    loose = keypose(rig, RELEASE, body=dict(pitch=-10, drop=0.3), feet=((-1.6, 1.2, 1.9), (1.7, 1.1, 0.6)),
                    knees=((0, 0.3, 1), (0, 0.3, 1)), head=(0, -4))
    land = keypose(rig, RELEASE, body=dict(pitch=6, drop=1.8), feet=stance, knees=((-0.2, 0, 1), (0.3, 0, 1)))
    settle = keypose(rig, RELEASE, body=dict(pitch=2, drop=1.2), feet=stance, knees=((-0.2, 0, 1), (0.3, 0, 1)))
    return ma.bake([(0, rig.sample(idle), None), (3, crouch, "inout"), (6, hop, "out"), (7, loose, None), (10, land, "in"),
                    (13, settle, "out"), (20, rig.sample(idle), "inout")])


def heavy_shot(rig):
    """The heavy attack (R2): she sinks into a wide braced stance and draws (5), leans back into a long, deep draw
    held while it charges (14), lets the shot go (16, the move fires it), is rocked back on her heels by it (20), and
    stands (30)."""
    idle = rig.motion_frame(0)
    stance = ((-2.6, ANKLE, 1.8), (2.4, ANKLE, -2.2))
    knees = ((-0.3, 0, 1), (0.3, 0, 1))
    brace = keypose(rig, AIM, body=dict(pitch=10, drop=2.4, yaw=-10), feet=stance, knees=knees, head=(0, 4))
    deep = keypose(rig, AIM, body=dict(pitch=-4, drop=2.8, ahead=-0.6, yaw=-14), feet=stance, knees=knees, head=(0, -2))
    loose = keypose(rig, RELEASE, body=dict(pitch=-12, drop=2.2, ahead=-0.8, yaw=-6), feet=stance, knees=knees, head=(0, -6))
    rocked = keypose(rig, RELEASE, body=dict(pitch=-8, drop=1.6, ahead=-1.0), feet=((-2.4, ANKLE, 1.2), (2.4, ANKLE, -2.8)),
                     knees=knees, head=(0, -4))
    return ma.bake([(0, rig.sample(idle), None), (5, brace, "inout"), (14, deep, "inout"), (16, loose, "in"), (20, rocked, "out"),
                    (30, rig.sample(idle), "inout")])


def volley(rig):
    """The finisher after three shots (A, A, A, R2): three quick draws and releases swept from her left to her right
    (released at 6, 11 and 16, the move fans each), then a settle and idle (26)."""
    idle = rig.motion_frame(0)
    stance = ((-2.4, ANKLE, 1.4), (2.2, ANKLE, -1.8))
    knees = ((-0.3, 0, 1), (0.3, 0, 1))
    keys = [(0, rig.sample(idle), None)]
    for n, yaw in enumerate((18, 0, -18)):
        draw_at, loose_at = 4 + 5 * n, 6 + 5 * n
        keys.append((draw_at, keypose(rig, AIM, body=dict(pitch=6, drop=2.0, yaw=yaw), feet=stance, knees=knees), "inout"))
        keys.append((loose_at, keypose(rig, RELEASE, body=dict(pitch=-4, drop=1.8, yaw=yaw, ahead=-0.3), feet=stance, knees=knees,
                                        head=(0, -3)), "in"))
    keys.append((20, keypose(rig, RELEASE, body=dict(pitch=0, drop=1.4, ahead=-0.3), feet=stance, knees=knees), "out"))
    keys.append((26, rig.sample(idle), "inout"))
    return ma.bake(keys)


ANIMATIONS = {"xiao_triple_shot": triple_shot, "xiao_tumble": tumble, "xiao_hop_shot": hop_shot, "xiao_heavy_shot": heavy_shot,
              "xiao_volley": volley}


def main():
    data, out = sys.argv[1], sys.argv[2]
    sheets = sys.argv[3] if len(sys.argv) > 3 else None
    rig = ma.open_rig(data, ma.PACKS["xiao"])
    for name, build in ANIMATIONS.items():
        frames = build(rig)
        ma.write_json(os.path.join(out, name + ".json"), ma.motion_document(rig, "xiao", frames, 0.5))
        if sheets:
            os.makedirs(sheets, exist_ok=True)
            step = max(1, len(frames) // 8)
            ma.stick_sheet(rig, [p for _, p in frames[::step]] + [frames[-1][1]], os.path.join(sheets, name + ".png"), cell=150)
        print(name, frames[-1][0], "frames")


if __name__ == "__main__":
    main()
