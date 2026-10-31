"""Opar Form: the game's own Opar monster (dun/monstor/e104a.chr) as a player model, for his Jump Slam's transform.

python art/opar/make_form.py <e104a.chr> <out c07f.chr>

The monster's pack already holds a model, a shadow model and their motions; a player model differs only in its
configuration's name (base.cfg, not info.cfg) and in its motion table, which must list the player's motions by
Toan's numbers (he fights as Toan). This writes the pack with the monster's members as they are and a base.cfg whose
motion table maps each of Toan's 41 motions to the monster's nearest: standing, the walk (also the run), his hurt,
his death, the gill spit (Toan's first swing and the combo's) and the body press (the second swing, the charge, the
skill).

The player code looks some frames up by name (the weapon's grip, the item hand, the spit's mouth); the mod names
stand-ins for them when it sets the form (player.form_set frames): FRAMES below.
"""

import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "chr"))
import chrtool  # noqa: E402

IDLE, WALK, HURT, DEATH, SPIT, PRESS, RISE = (10, 20), (30, 50), (60, 70), (80, 100), (110, 120), (130, 150), (160, 180)

# Toan's motion numbers (dun/mainchara/c01d.chr base.cfg) -> (first frame, last frame, speed) of the monster's.
MOTIONS = [
    (*IDLE, 0.13),   # 0 standing
    (*WALK, 0.3),    # 1 running
    (*WALK, 0.2),    # 2 walking
    (*IDLE, 0.13),   # 3 charge, held
    (*HURT, 0.25),   # 4 hurt
    (IDLE[0], IDLE[0], 0.0),  # 5 charge, held
    (*HURT, 0.2),    # 6 hurt badly
    (*RISE, 0.2),    # 7 getting up
    (*IDLE, 0.13),   # 8 to guard
    (*IDLE, 0.13),   # 9 guarding
    (*IDLE, 0.13),   # 10 guard to standing
    (*SPIT, 0.4),    # 11 swing 1
    (*PRESS, 0.3),   # 12 swing 2
    (160, 165, 0.2),  # 13 to charge
    (165, 170, 0.1),  # 14 charging
    (130, 140, 0.3),  # 15 charged swing, start
    (140, 141, 0.0),  # 16 charged swing, held
    (140, 150, 0.3),  # 17 charged swing, end
    (*IDLE, 0.13),   # 18 ready
    (*IDLE, 0.13),   # 19 ready, right
    (*IDLE, 0.13),   # 20 ready, left
    (*IDLE, 0.13),   # 21 ready, ahead
    (*IDLE, 0.13),   # 22 ready, behind
    (*DEATH, 0.2),   # 23 defeated
    (PRESS[0], RISE[1], 0.25),  # 24 skill: Opar's big slam, the press and getting up
    (IDLE[0], IDLE[0], 0.0),  # 25 charged swing, held
    (SPIT[0], SPIT[0], 0.0),  # 26 throw, held
    (*SPIT, 0.4),    # 27 throw
    (*IDLE, 0.13),   # 28 drinking
    (*WALK, 0.3),    # 29 running hurt
    (*WALK, 0.2),    # 30 moving charged
    (*IDLE, 0.13),   # 31 out of breath
    (*IDLE, 0.13),   # 32 falling
    (*WALK, 0.2),    # 33 moving guarded
    (*IDLE, 0.13),   # 34 picking up
    (*IDLE, 0.13),   # 35 holding up
    (*SPIT, 0.4),    # 36 combo 1
    (*PRESS, 0.3),   # 37 combo 2
    (*SPIT, 0.4),    # 38 combo 3
    (*PRESS, 0.3),   # 39 combo 4
    (*PRESS, 0.25),  # 40 combo 5
]

# Frames the player code looks up by name -> the monster's frame standing in (player.form_set frames).
FRAMES = {"weapon": "r_hand", "item": "l_hand", "tukene1": "karada", "jnt2_1": "karada", "jnt12_1": "shita"}


def base_cfg(info):
    """The monster's info.cfg with its motion table replaced by MOTIONS (Shift-JIS comments dropped)."""
    text = info.decode("shift_jis", "replace")
    head = text[:text.index("KEY_START")]
    keys = "".join("\tKEY\t%d,\t%d,\t%.2f,\t//%d\r\n" % (a, b, s, n) for n, (a, b, s) in enumerate(MOTIONS))
    head = "\r\n".join(line for line in head.splitlines() if not line.startswith("//")) + "\r\n"
    return (head + "KEY_START 0\r\n" + keys + "MOTION_END\r\n").encode("ascii")


def rename_member(data, old, new):
    for name, at, _, _ in chrtool.pack_entries(data):
        if name == old:
            out = bytearray(data)
            chrtool._put_name(out, at, 64, new.encode("latin1"))
            return bytes(out)
    raise KeyError(old)


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    data = open(argv[0], "rb").read()
    members = {n: data[s:s + z] for n, _, s, z in chrtool.pack_entries(data)}
    pack = chrtool.replace_member(data, "info.cfg", base_cfg(members["info.cfg"]))
    pack = rename_member(pack, "info.cfg", "base.cfg")
    os.makedirs(os.path.dirname(os.path.abspath(argv[1])), exist_ok=True)
    open(argv[1], "wb").write(pack)
    print("%s: %d bytes, %d motions (%s)" % (argv[1], len(pack), len(MOTIONS), ", ".join(n for n, *_ in chrtool.pack_entries(pack))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
