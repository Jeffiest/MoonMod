"""Goro's, Ungaga's, Ruby's and Osmond's Gauntlet animations, from one set of move recipes and a spec of each rig.

python tools/anim/party_moves.py <dun/mainchara folder> <out folder> [sheet folder] [character ...]

Toan's and Xiao's sets were posed by hand (toan_moves.py, xiao_moves.py). These four are built systematically: each
character's SPEC names its bones (the body's centre, legs, arms, spine and head) and the native frames its own attack
passes through (wind-up, strike, follow-through; aim and release for a caster). Every attack keypose starts from one
of those native frames, so the arms and the weapon move as the game's own swing does, and changes only the body (turn,
lean, drop) and the stance (each foot moved from where it stands at idle). Distances are given for Toan's build and
scaled by the character's leg length, so one recipe fits a short Goro and a tall Ungaga alike. The evades (a tucked
roll, a skip back) are posed from the hips and chest with arm and leg IK.

Melee characters (Goro, Ungaga) get nine motions, casters (Ruby, Osmond) five; see RECIPES. Space: Y up, facing +Z,
the character's right -X.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moonanim as ma  # noqa: E402

TOAN_LEG = 7.8  # Toan's hip to ankle, the build the recipes' distances are given for

SPEC = {
    # Goro's swing is a jump slam: crouch (93), the hammer high (96), the slam (102), up again (105). One swing, no combo.
    "goro": dict(kind="melee", center="null69", root="null69",
                 legs=(("jnt22_1", "jnt22_2", "eff22"), ("jnt11_1", "jnt11_2", "eff11")),
                 arms=(("jnt18_1", "jnt18_2", "eff18"), ("jnt9_1", "jnt9_2", "eff9")), spine="jnt4_1", head="jnt6_1",
                 windup=93, high=96, strike=102, follow=105, chain2=105, chain3=105),
    # Ungaga's spear combo: three thrusts (blows at 674, 686-692 and 700-704); a finisher cuts the second or third.
    "ungaga": dict(kind="melee", center="null84", root="null84",
                   legs=(("jnt22_1", "jnt22_2", "eff22"), ("jnt12_1", "jnt12_2", "eff12")),
                   arms=(("jnt39_1", "jnt39_2", "eff39"), ("jnt32_1", "jnt32_2", "eff32")), spine="jnt27_1", head="jnt4_1",
                   windup=682, high=686, strike=690, follow=694, chain2=694, chain3=710),
    # Ruby casts with her right hand: the arm drawn back (126), thrown forward as the orb goes (130).
    "ruby": dict(kind="caster", center="hip", root="hip",
                 legs=(("r_upleg", "r_leg", "r_foot"), ("l_upleg", "l_leg", "l_foot")),
                 arms=(("r_arm", "r_farm", "r_hand"), ("l_arm", "l_farm", "l_hand")), spine="spine", head="neck",
                 aim=126, release=130),
    # Osmond hovers and fires his gun from the right hand, held out (84, 86 as it kicks).
    "osmond": dict(kind="caster", center="null11", root="null11",
                   legs=(("r_upleg", "r_leg", "eff21"), ("l_upleg", "l_leg", "eff8")),
                   arms=(("r_arm", "r_farm", "eff16"), ("l_arm", "l_farm", "eff5")), spine="spine", head="neck2",
                   aim=84, release=86),
}


class Cast:
    """A character's rig with its spec: idle positions, the scale, and posing helpers."""

    def __init__(self, rig, spec):
        self.rig, self.spec = rig, spec
        self.idle = rig.motion_frame(0)
        self.run = rig.motion_frame(1, 0.3)
        self.guard = rig.motion_frame(9, 0.5)
        world = self.world(rig.sample(self.idle))
        legs = spec["legs"]
        self.feet = [world[leg[2]] for leg in legs]
        self.scale = sum(ma._len(ma._sub(world[leg[0]], world[leg[2]])) for leg in legs) / 2 / TOAN_LEG
        self.floor = min(p[1] for p in self.feet)

    def world(self, pose):
        return {name: p for _, (name, p, _) in ma.fk(self.rig, pose).items()}

    def chain_joints(self, pose):
        s = self.spec
        names = [b for chain in s["legs"] + s["arms"] for b in chain] + [s["spine"], s["head"]]
        w = self.world(pose)
        return [w[n] for n in names]

    def key(self, base, body=None, feet=None, knees=((0, 0, 1), (0, 0, 1)), head=None):
        """A keypose from native frame `base`: body (ma.body arguments; drop/ahead/side in Toan units), feet (right,
        left) offsets from where each stands at idle (Toan units; None leaves the leg as the base has it), head (yaw,
        pitch)."""
        s, k = self.spec, self.scale
        pose = self.rig.sample(base)
        if base != self.idle and feet:
            # Only the native frame's upper body: the hips and legs start from idle (a jump or crouch in the native
            # swing would stack with the body changes here), then are posed below.
            idle = self.rig.sample(self.idle)
            for channel in self.lower_channels():
                pose[channel] = idle[channel]
        if body:
            b = dict(body)
            for f in ("drop", "ahead", "side"):
                if f in b:
                    b[f] *= k
            ma.body(self.rig, pose, root=s["root"], center=s["center"], **b)
        if feet:
            targets = [None if off is None else (idle[0] + off[0] * k, idle[1] + off[1] * k, idle[2] + off[2] * k)
                       for idle, off in zip(self.feet, feet)]
            # A foot out of the leg's reach: the hips sink until it reaches (a stance longer than this build's legs
            # allow is shortened instead), so planted feet stay planted on every build.
            w = self.world(pose)
            sink = 0.0
            for n, (leg, at) in enumerate(zip(s["legs"], targets)):
                if at is None:
                    continue
                hip = w[leg[0]]
                reach = 0.97 * (ma._len(ma._sub(w[leg[1]], hip)) + ma._len(ma._sub(w[leg[2]], w[leg[1]])))
                flat = ma._len((at[0] - hip[0], 0.0, at[2] - hip[2]))
                if flat > reach * 0.9:
                    shrink = reach * 0.9 / flat
                    at = (hip[0] + (at[0] - hip[0]) * shrink, at[1], hip[2] + (at[2] - hip[2]) * shrink)
                    targets[n] = at
                    flat = reach * 0.9
                need = (hip[1] - at[1]) - (reach * reach - flat * flat) ** 0.5
                sink = max(sink, need)
            if sink > 0:
                t = pose[(s["center"], "translation")]
                pose[(s["center"], "translation")] = (t[0], t[1] - sink, t[2])
            for leg, at, knee in zip(s["legs"], targets, knees):
                if at is not None:
                    ma.leg(self.rig, pose, *leg, at, knee)
        if head:
            ma.world_turn(self.rig, pose, s["head"], ma.qmul(ma.qaxis((0, 1, 0), head[0]), ma.qaxis((1, 0, 0), head[1])))
        return pose

    def lower_channels(self):
        """The hips' channels (centre and root) and every leg bone's, with the bones between the hips and each leg."""
        if not hasattr(self, "_lower"):
            nodes = self.rig.gltf["nodes"]
            parents = ma._parents(self.rig)
            names = {self.spec["center"], self.spec["root"]}
            for leg in self.spec["legs"]:
                i = ma._node(self.rig, leg[0])
                p = parents.get(i)
                if p is not None and nodes[p].get("name", "").startswith("chn"):
                    names.add(nodes[p]["name"])
                stack = [i]
                while stack:
                    n = stack.pop()
                    names.add(nodes[n].get("name"))
                    stack.extend(nodes[n].get("children", []))
            self._lower = [ch for ch in self.rig.sample(self.idle) if ch[0] in names]
        return self._lower

    def tucked(self, base, pitch, drop, ahead=0.0):
        """The roll's ball: pitched forward by `pitch` about the hips, spine and head curled in, knees to the chest,
        hands at the shins, the lowest joint resting on the floor."""
        s, k, rig = self.spec, self.scale, self.rig
        pose = rig.sample(base)
        ma.body(rig, pose, pitch=pitch, drop=drop * k, ahead=ahead * k, root=s["root"], center=s["center"])
        turn = ma.qaxis((1, 0, 0), pitch)
        side = ma.qrot(turn, (1, 0, 0))
        ma.world_turn(rig, pose, s["spine"], ma.qaxis(side, 34))
        ma.world_turn(rig, pose, s["head"], ma.qaxis(side, 26))
        w = self.world(pose)
        hips = ma._scale(ma._add(w[s["legs"][0][0]], w[s["legs"][1][0]]), 0.5)
        chest = ma._scale(ma._add(w[s["arms"][0][0]], w[s["arms"][1][0]]), 0.5)

        def at(origin, local):
            return ma._add(origin, ma.qrot(turn, ma._scale(local, k)))

        ma.leg(rig, pose, *s["legs"][0], at(hips, (-0.5, -2.0, 2.8)), ma.qrot(turn, (0, 0.6, 1)))
        ma.leg(rig, pose, *s["legs"][1], at(hips, (0.5, -2.0, 2.8)), ma.qrot(turn, (0, 0.6, 1)))
        ma.leg(rig, pose, *s["arms"][0], at(chest, (-0.6, -5.0, 3.2)), ma.qrot(turn, (-1, -0.4, 0)))
        ma.leg(rig, pose, *s["arms"][1], at(chest, (0.6, -5.0, 3.2)), ma.qrot(turn, (1, -0.4, 0)))
        lowest = min(p[1] for p in self.chain_joints(pose))
        t = pose[(s["center"], "translation")]
        pose[(s["center"], "translation")] = (t[0], t[1] + (self.floor + 0.3 - lowest), t[2])
        return pose

    def keep_above_floor(self, frames, lo, hi):
        """Lifts the body of every frame from lo to hi so no joint goes below the ankles' height at idle."""
        c = self.spec["center"]
        for f, pose in frames:
            if lo <= f <= hi:
                lowest = min(p[1] for p in self.chain_joints(pose))
                if lowest < self.floor:
                    t = pose[(c, "translation")]
                    pose[(c, "translation")] = (t[0], t[1] + self.floor - lowest, t[2])
        return frames

    def sample(self, frame):
        return self.rig.sample(frame)


SPLIT = ((0, 0, 1.8), (0, 0, -2.2))  # right foot ahead, left back
WIDE = ((-1.4, 0, 0.6), (1.4, 0, -0.6))
LUNGE = ((0, 0, 7.0), (0, 0, -5.2))
KNEES = ((-0.2, 0, 1), (0.3, 0, 1))


# -- the evades (every character) ---------------------------------------------------------------------------------
def roll(c):
    """L2 with the stick pushed: out of the run, a dive (3), a tucked somersault (quarter turns 6, 9, 12), feet
    planted in a split stance (15), pushed up through a forward lean (19) and idle (24)."""
    dive = c.key(c.idle, body=dict(pitch=34, drop=2.2, ahead=1.0), feet=((0, 0, -1.6), (0, 0, 1.6)), head=(0, 18))
    frames = ma.bake([(0, c.sample(c.run), None), (3, dive, "in"), (6, c.tucked(c.idle, 100, 4.4, 0.6), None),
                      (9, c.tucked(c.idle, 190, 4.7), None), (12, c.tucked(c.idle, 280, 4.3), "out"),
                      (15, roll_plant(c), "in"), (19, c.key(c.idle, body=dict(pitch=16, drop=2.0, ahead=0.4), feet=SPLIT, knees=KNEES), "out"),
                      (24, c.sample(c.idle), "inout")])
    return c.keep_above_floor(frames, 4, 13)


def roll_plant(c):
    """The roll's planted stance (its frame 15), where the roll's follow-up starts."""
    return c.key(c.idle, body=dict(pitch=30, drop=3.4, ahead=0.6), feet=((0, 0, 2.2), (0, 0, -2.8)), knees=((-0.2, 0, 1), (0.3, -0.4, 1)),
                 head=(0, -6))


def backstep(c, arms=None):
    """L2 with the stick at rest: a crouch (3), a low skip back (5), a staggered landing (8), a settle (11), idle (18).
    `arms`: a native frame for the arms (a caster aims through it)."""
    base = arms if arms is not None else c.idle
    crouch = c.key(base, body=dict(pitch=10, drop=1.6), feet=((0, 0, 0.6), (0, 0, -0.8)))
    hop = c.key(base, body=dict(pitch=-10, drop=0.2), feet=((0, 0.6, 2.0), (0, 0.8, 1.0)), knees=((0, 0.3, 1), (0, 0.3, 1)))
    land = c.key(base, body=dict(pitch=-4, drop=1.6), feet=SPLIT, knees=KNEES)
    settle = c.key(base, body=dict(pitch=6, drop=1.8), feet=SPLIT, knees=KNEES)
    return ma.bake([(0, c.sample(c.idle), None), (3, crouch, "inout"), (5, hop, "out"), (8, land, "in"), (11, settle, "out"),
                    (18, c.sample(c.idle), "inout")])


# -- melee ----------------------------------------------------------------------------------------------------------
def dash(c):
    """Out of a run (or locked on, stick toward): a coiled step on the wind-up (5), a long low lunge on the strike (9),
    held (15), idle (24)."""
    s = c.spec
    coil = c.key(s["windup"], body=dict(pitch=12, drop=1.4, yaw=-16), feet=((0, 0, 2.2), (0, 0, -2.6)), knees=KNEES)
    lunge = c.key(s["strike"], body=dict(pitch=22, drop=2.6, ahead=2.0, yaw=14), feet=LUNGE, knees=((0, 0.3, 1), (0.2, -0.2, 1)))
    follow = c.key(s["follow"], body=dict(pitch=24, drop=2.8, ahead=2.2, yaw=12), feet=LUNGE, knees=((0, 0.3, 1), (0.2, -0.2, 1)))
    return ma.bake([(0, c.sample(c.run), None), (5, coil, "inout"), (9, lunge, "in"), (15, follow, "out"), (24, c.sample(c.idle), "inout")])


def counter(c):
    """Out of the guard: a deep crouch on the wind-up (5), a rising strike up onto the toes (10), the follow-through
    (14), a ready landing (20), idle (30)."""
    s = c.spec
    crouch = c.key(s["windup"], body=dict(drop=3.4, pitch=22, yaw=-20), feet=((0, 0, 2.4), (0, 0, -2.2)), knees=KNEES, head=(16, 10))
    rise = c.key(s["strike"], body=dict(drop=-0.8, pitch=-6, yaw=12), feet=((0, 1.0, 1.4), (0, 0, -1.6)))
    top = c.key(s["follow"], body=dict(drop=-0.6, pitch=-8, yaw=6), feet=((0, 1.0, 1.4), (0, 0, -1.6)))
    land = c.key(c.idle, body=dict(drop=1.6, pitch=10), feet=SPLIT, knees=KNEES)
    return ma.bake([(0, c.sample(c.guard), None), (5, crouch, "inout"), (10, rise, "in"), (14, top, "out"), (20, land, "in"),
                    (30, c.sample(c.idle), "inout")])


def heavy(c):
    """R2 from rest: a gather (4), a slow lift with the weight rocked back (10), the strike with a deep bend (13), held
    (19), idle (30)."""
    s = c.spec
    gather = c.key(s["windup"], body=dict(pitch=6, drop=1.4), feet=SPLIT, knees=KNEES)
    lift = c.key(s["high"], body=dict(pitch=-12, drop=0.6, ahead=-0.4), feet=SPLIT, knees=KNEES, head=(0, -12))
    strike = c.key(s["strike"], body=dict(pitch=32, drop=3.2, ahead=1.0), feet=SPLIT, knees=KNEES, head=(0, 14))
    held = c.key(s["strike"], body=dict(pitch=30, drop=3.0, ahead=1.0), feet=SPLIT, knees=KNEES, head=(0, 10))
    return ma.bake([(0, c.sample(c.idle), None), (4, gather, "inout"), (10, lift, "out"), (13, strike, "in"), (19, held, "out"),
                    (30, c.sample(c.idle), "inout")])


def launcher(c):
    """A, A, R2: out of the second swing, dropped low on the wind-up (4), an upward strike onto the toes (8), the top
    (13), a ready stance (19), idle (28)."""
    s = c.spec
    low = c.key(s["windup"], body=dict(drop=3.2, pitch=22, yaw=-16), feet=((0, 0, 2.2), (0, 0, -2.2)), knees=KNEES, head=(12, 10))
    cut = c.key(s["strike"], body=dict(drop=-0.6, pitch=-6, yaw=10), feet=((0, 1.0, 1.8), (0, 0, -1.8)))
    top = c.key(s["high"], body=dict(drop=-0.8, pitch=-10, yaw=6), feet=((0, 1.0, 1.8), (0, 0, -1.8)), head=(0, -16))
    ready = c.key(c.idle, body=dict(drop=1.6, pitch=10), feet=SPLIT, knees=KNEES)
    return ma.bake([(0, c.sample(s["chain2"]), None), (4, low, "inout"), (8, cut, "in"), (13, top, "out"), (19, ready, "inout"),
                    (28, c.sample(c.idle), "inout")])


def spin_finisher(c):
    """A, A, A, R2: out of the third swing, wound across the body (4), flung out on the strike while the move turns
    the character a full circle (8-15), ended on a lunging strike (20), idle (34)."""
    s = c.spec
    wind = c.key(s["windup"], body=dict(yaw=44, drop=2.2, pitch=8), feet=WIDE, knees=((-0.4, 0, 1), (0.4, 0, 1)))
    wide = c.key(s["strike"], body=dict(yaw=-6, drop=2.0, pitch=2), feet=WIDE, knees=((-0.4, 0, 1), (0.4, 0, 1)))
    lunge = c.key(s["strike"], body=dict(pitch=24, drop=2.8, ahead=2.0, yaw=16), feet=((0, 0, 6.4), (0, 0, -4.6)),
                  knees=((0, 0.3, 1), (0.2, -0.2, 1)))
    return ma.bake([(0, c.sample(s["chain3"]), None), (4, wind, "inout"), (8, wide, "in"), (15, wide, None), (20, lunge, "in"),
                    (25, lunge, None), (34, c.sample(c.idle), "inout")])


def back_slash(c):
    """Locked on, stick away + A: the wind-up turned away (3), the strike swung across while skipping back (6), a low
    landing (10), idle (20)."""
    s = c.spec
    cock = c.key(s["windup"], body=dict(yaw=-28, drop=1.4, pitch=6), feet=((0, 0, 0.8), (0, 0, -0.8)))
    cut = c.key(s["strike"], body=dict(yaw=24, drop=0.6, pitch=-6), feet=((0, 0.6, 1.6), (0, 0.8, 0.6)), knees=((0, 0.3, 1), (0, 0.3, 1)))
    land = c.key(c.idle, body=dict(pitch=6, drop=1.8), feet=SPLIT, knees=KNEES)
    return ma.bake([(0, c.sample(c.idle), None), (3, cock, "inout"), (6, cut, "in"), (10, land, "in"), (20, c.sample(c.idle), "inout")])


def roll_slash(c):
    """A late in the roll or just after: out of its planted stance (0), a coil (3), a rising strike driving forward
    (7), held (12), idle (22)."""
    s = c.spec
    coil = c.key(s["windup"], body=dict(pitch=26, drop=3.2, ahead=0.6), feet=((0, 0, 2.2), (0, 0, -2.8)), knees=((-0.2, 0, 1), (0.3, -0.4, 1)))
    cut = c.key(s["strike"], body=dict(pitch=6, drop=1.4, ahead=1.6, yaw=14), feet=((0, 0, 4.4), (0, 0, -3.4)), knees=((0, 0.2, 1), (0.2, -0.2, 1)))
    held = c.key(s["follow"], body=dict(pitch=4, drop=1.2, ahead=1.6, yaw=12), feet=((0, 0, 4.4), (0, 0, -3.4)), knees=((0, 0.2, 1), (0.2, -0.2, 1)))
    return ma.bake([(0, roll_plant(c), None), (3, coil, "inout"), (7, cut, "in"), (12, held, "out"), (22, c.sample(c.idle), "inout")])


# -- casters --------------------------------------------------------------------------------------------------------
def rush(c):
    """Out of a run: a skid into a wide low stance on the aim (4), the aim drawn (7), the cast let go (10; the move
    fires it), riding the recoil back (15), idle (24). The finisher, the lock-on dash and the evade follow-up reuse it
    from part way in."""
    s = c.spec
    stance = ((-1.0, 0, 1.6), (1.0, 0, -1.8))
    skid = c.key(s["aim"], body=dict(pitch=10, drop=2.2, ahead=0.6, yaw=-8), feet=((-1.0, 0, 2.6), (1.0, 0, -2.4)), knees=KNEES)
    draw = c.key(s["aim"], body=dict(pitch=4, drop=2.0, yaw=-6), feet=stance, knees=KNEES)
    loose = c.key(s["release"], body=dict(pitch=-6, drop=1.8, ahead=-0.4, yaw=-4), feet=stance, knees=KNEES)
    held = c.key(s["release"], body=dict(pitch=-2, drop=1.6, ahead=-0.3), feet=stance, knees=KNEES)
    return ma.bake([(0, c.sample(c.run), None), (4, skid, "out"), (7, draw, "inout"), (10, loose, "in"), (15, held, "out"),
                    (24, c.sample(c.idle), "inout")])


def heavy_cast(c):
    """R2: a braced stance on the aim (5), a long deep draw held while it charges (14), the cast let go (16), rocked
    back (20), idle (30)."""
    s = c.spec
    stance = ((-1.2, 0, 1.8), (1.2, 0, -2.2))
    brace = c.key(s["aim"], body=dict(pitch=10, drop=2.4, yaw=-10), feet=stance, knees=KNEES)
    deep = c.key(s["aim"], body=dict(pitch=-4, drop=2.8, ahead=-0.6, yaw=-14), feet=stance, knees=KNEES)
    loose = c.key(s["release"], body=dict(pitch=-12, drop=2.2, ahead=-0.8, yaw=-6), feet=stance, knees=KNEES)
    rocked = c.key(s["release"], body=dict(pitch=-8, drop=1.6, ahead=-1.0), feet=((-1.2, 0, 1.2), (1.2, 0, -2.8)), knees=KNEES)
    return ma.bake([(0, c.sample(c.idle), None), (5, brace, "inout"), (14, deep, "inout"), (16, loose, "in"), (20, rocked, "out"),
                    (30, c.sample(c.idle), "inout")])


def volley(c):
    """A, A, A, R2: three quick aims and casts swept from left to right (cast at 6, 11, 16), a settle (20), idle (26)."""
    s = c.spec
    stance = ((-1.0, 0, 1.4), (1.0, 0, -1.8))
    keys = [(0, c.sample(c.idle), None)]
    for n, yaw in enumerate((18, 0, -18)):
        keys.append((4 + 5 * n, c.key(s["aim"], body=dict(pitch=6, drop=2.0, yaw=yaw), feet=stance, knees=KNEES), "inout"))
        keys.append((6 + 5 * n, c.key(s["release"], body=dict(pitch=-4, drop=1.8, yaw=yaw, ahead=-0.3), feet=stance, knees=KNEES), "in"))
    keys.append((20, c.key(s["release"], body=dict(drop=1.4, ahead=-0.3), feet=stance, knees=KNEES), "out"))
    keys.append((26, c.sample(c.idle), "inout"))
    return ma.bake(keys)


RECIPES = {
    "melee": {"dash": dash, "counter": counter, "roll": roll, "backstep": backstep, "heavy": heavy, "launcher": launcher,
              "spin_finisher": spin_finisher, "back_slash": back_slash, "roll_slash": roll_slash},
    "caster": {"rush": rush, "tumble": roll, "hop_shot": lambda c: backstep(c, arms=c.spec["release"]), "heavy_cast": heavy_cast,
               "volley": volley},
}


def build(data, character):
    """Every motion of one character: {name: frames}."""
    spec = SPEC[character]
    c = Cast(ma.open_rig(data, ma.PACKS[character]), spec)
    return c, {"%s_%s" % (character, name): recipe(c) for name, recipe in RECIPES[spec["kind"]].items()}


def main():
    data, out = sys.argv[1], sys.argv[2]
    sheets = sys.argv[3] if len(sys.argv) > 3 else None
    who = sys.argv[4:] or list(SPEC)
    for character in who:
        c, motions = build(data, character)
        for name, frames in motions.items():
            ma.write_json(os.path.join(out, name + ".json"), ma.motion_document(c.rig, character, frames, 0.5))
            if sheets:
                os.makedirs(sheets, exist_ok=True)
                step = max(1, len(frames) // 8)
                ma.stick_sheet(c.rig, [p for _, p in frames[::step]] + [frames[-1][1]], os.path.join(sheets, name + ".png"), cell=150)
            print(name, frames[-1][0], "frames")


if __name__ == "__main__":
    main()
