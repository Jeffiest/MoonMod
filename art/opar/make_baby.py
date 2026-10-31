"""Baby Opar for the story (docs/OPAR_PLAN.md §8): the packs the house and its scene load.

    python art/opar/make_baby.py [out folder]

From the mod's Opar Form pack (resources/opar/c07f.chr: the Opar monster, e104a, art/opar/make_form.py) and his own
pack (c07d.chr), into <out> (default: the story mod's resources/opar):

- c07baby.chr: baby Opar standing in Toan's house (LOAD_IN_VILLAGER), a villager pack like the cat's c04pcat.chr:
  its config is info.cfg, its motions the monster's idle (key 0) and walk (key 1).
- e04c07baby.chr: baby Opar in the house's scene (LOAD_CHARA from e04c07baby.cfg), as the cat's e04c04cat.chr.
- e04c07opar.chr: Opar grown, in the scene (LOAD_CHARA from e04c07opar.cfg): his own pack, its config his base.cfg.

The house's patched script (art/opar/story/patch_house.py) draws them at the cat's size (SET_NPC_SCALE).
"""

import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "chr"))
import chrtool  # noqa: E402

GAUNTLET = os.path.join(ROOT, "mods", "moonmod.roguelike", "resources", "opar")
OUT = os.path.join(ROOT, "mods", "moonmod.opar", "resources", "opar")

# The monster's motions (e104a.mot): 10-20 its idle, 30-50 its walk.
BABY_KEYS = [(10, 20, 0.13), (30, 50, 0.30), (30, 50, 0.30), (10, 20, 0.13)]


def renamed(data, old, new):
    """The pack with member `old` named `new` (names are 64-byte fields)."""
    out = bytearray(data)
    for name, name_at, _, _ in chrtool.pack_entries(data):
        if name == old:
            out[name_at:name_at + 64] = new.encode("latin1").ljust(64, b"\0")
            return bytes(out)
    raise SystemExit("%s has no %s" % ("pack", old))


def member(data, name):
    for n, _, at, size in chrtool.pack_entries(data):
        if n == name:
            return data[at:at + size]
    raise SystemExit("no member " + name)


def baby_cfg(form_cfg):
    """The form's config with its motion keys replaced by the monster's idle and walk."""
    lines, keys, out = form_cfg.decode("shift_jis").splitlines(), False, []
    for line in lines:
        bare = line.strip()
        if bare.startswith("KEY_START"):
            out.append(line)
            out += ["\tKEY\t%d,\t%d,\t%.2f," % k for k in BABY_KEYS]
            keys = True
            continue
        if keys and bare.startswith("KEY"):
            continue
        if bare.startswith("MOTION_END"):
            keys = False
        out.append(line)
    return ("\r\n".join(out) + "\r\n").encode("shift_jis")


def main(argv):
    out = argv[0] if argv else OUT
    os.makedirs(out, exist_ok=True)
    form = open(os.path.join(GAUNTLET, "c07f.chr"), "rb").read()
    cfg = baby_cfg(member(form, "base.cfg"))
    baby = chrtool.replace_member(form, "base.cfg", cfg)
    for stem, cfg_name in (("c07baby", "info.cfg"), ("e04c07baby", "e04c07baby.cfg")):
        path = os.path.join(out, stem + ".chr")
        open(path, "wb").write(renamed(baby, "base.cfg", cfg_name))
        print(path, os.path.getsize(path))
    grown = open(os.path.join(GAUNTLET, "c07d.chr"), "rb").read()
    path = os.path.join(out, "e04c07opar.chr")
    open(path, "wb").write(renamed(grown, "base.cfg", "e04c07opar.cfg"))
    print(path, os.path.getsize(path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
