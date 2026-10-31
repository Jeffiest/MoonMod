"""Toan's house (gedit/e01/in/i01h01/event.stb) with baby Opar in it, for the story Opar mod (docs/OPAR_PLAN.md §8).

    python art/opar/story/patch_house.py [retail event.stb] [out event.stb]

Xiao's own scene is kept; tools/stb/stbpatch.py adds to it:

- the house loads its people (program 128 calls code+0x8394): with baby Opar's sphere found (game flag 7001) and him
  not yet joined (7002), and the cat's element in the house (its completion event 0), he stands beside the cat in
  villager slot 6 (c07baby.chr), at the cat's size;
- the cat's scene (code+0x86b8), when he is in the house: after its own characters load, baby Opar (slot 6,
  e04c07baby.chr) beside the cat and Opar grown (slot 7, e04c07opar.chr) hidden; when the cat is hidden and Xiao
  shown, baby Opar is hidden and Opar shown beside her; when the scene makes the party two, game flag 7002 is set
  (the mod has him join) and both are put away;
- program 11 (the floor region by the cat, which the house turns on while she is there): once the cat's scene has
  played (game flag 18), and baby Opar is there, pressing by him fades out, sets 7002 and fades in: his own short join.

The mod sets 7001 when Toan picks up baby Opar's sphere, and keeps the region on while baby Opar is in the house.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "stb"))
from stbpatch import Script  # noqa: E402

RETAIL = "E:/Gauntlet-build/run/data/gedit/e01/in/i01h01/event.stb"
OUT = os.path.join(ROOT, "mods", "moonmod.opar", "resources", "story", "i01h01_event.stb")

FOUND, JOINED, CAT_DONE = 7001, 7002, 18
BABY, GROWN = 6, 7
BABY_SCALE = 0.15  # the monster at the cat's size
# where they stand (x, height, z): the cat stands at (27, 44, -24) in the house and sits on the bed at (31.2, 44, -25.4)
# in the scene; Xiao appears over the bed at (28.9, 49.7, -23.1) and ends on the floor at (22.4, 37.08, -12.4); Toan
# stands on the floor at (17.4, 37.6, -16.4)
BABY_HOUSE = (21.0, 44.0, -24.0, 0.33)
BABY_SCENE = (25.2, 44.0, -25.4)
GROWN_SCENE = (36.5, 37.6, -16.0)  # on open floor by the bed's foot, clear of it and of Xiao's moves (she ends at 22.4, -12.4)
FACE_TOAN = -2.2
GROWN_FACE_TOAN = -1.8  # toward Toan and Xiao

# the house's own code
CALL_LOAD_PEOPLE = 0x115DC  # program 128: CALL code+0x8394
AFTER_SCENE_LOADS = 0x08868  # the scene: EXT LOAD_CHARA(4, 'kira5.cfg')
CALL_LOAD_WAIT = 0x0873C  # the scene: CALL code+0x2c0, waiting for its files
CAT_HIDDEN = 0x09DEC  # the scene: EXT NPC_DRAW(0, 1)
PARTY_TWO = 0x0BE8C  # the scene: EXT SSET_PARTY_NUM(2)
CAT_ELEMENT_CHECK = 0x084F0  # code+0x8394: CALL code+0x2058 (the cat's element in?)
CALL_FADE_WAIT = 0x0BDFC  # the scene: CALL code+0x9fc, waiting for a fade


def baby_here(skip):
    """Leaves 1 in local 0 when baby Opar is in the house (found, not joined); jumps to `skip` when he is not."""
    return ["SGET_GAME_FLAG(%d, &0)" % FOUND, "SGET_GAME_FLAG(%d, &1)" % JOINED,
            "LOAD 0", "LOAD 1", "NOT", "AND", "JMP_FALSE " + skip]


def patch(src):
    s = Script(src)
    element_check = s.old_record(CAT_ELEMENT_CHECK)
    load_wait = s.old_record(CALL_LOAD_WAIT)
    fade_wait = s.old_record(CALL_FADE_WAIT)

    # the house's people: baby Opar beside the cat
    load_people = s.old_record(CALL_LOAD_PEOPLE)
    x, z, y, rot = BABY_HOUSE
    people = s.function([
        "CALL %d" % load_people, "POP",
        *baby_here("done"),
        "PUSH 0", "CALL %d" % element_check, "JMP_FALSE done",
        'LOAD_IN_VILLAGER(%d, -1, "c07baby", %r, %r, %r, %r)' % (BABY, x, z, y, rot),
        "SET_NPC_SCALE(%d, %rf)" % (BABY, BABY_SCALE),
        "SSET_MAP_FLAG(2, 1)",  # the region by the cat: on while he is there too
        "done:", "PUSH 0", "RET"], args=0, locals=2)
    s.retarget_call(CALL_LOAD_PEOPLE, people)

    # the scene: his two loaded after its own
    bx, bz, by = BABY_SCENE
    gx, gz, gy = GROWN_SCENE
    s.hook_ext(AFTER_SCENE_LOADS, [
        *baby_here("done"),
        'LOAD_CHR_FILE("e04c07baby.chr", "e04c07opar.chr")',
        "CALL %d" % load_wait, "POP",
        "ACTIVE_FILE_BUFFER(0, 1)", 'LOAD_CHARA(%d, "e04c07baby.cfg")' % BABY,
        "ACTIVE_FILE_BUFFER(1, 1)", 'LOAD_CHARA(%d, "e04c07opar.cfg")' % GROWN,
        "SET_NPC_SCALE(%d, %rf)" % (BABY, BABY_SCALE),
        "SET_NPC_POS(%d, %rf, %rf, %rf)" % (BABY, bx, bz, by), "SET_NPC_ROT(%d, 0.0f, %rf, 0.0f)" % (BABY, FACE_TOAN),
        "SET_NPC_MOTION(%d, 0)" % BABY,
        "SET_NPC_POS(%d, %rf, %rf, %rf)" % (GROWN, gx, gz, gy), "SET_NPC_ROT(%d, 0.0f, %rf, 0.0f)" % (GROWN, GROWN_FACE_TOAN),
        "SET_NPC_MOTION(%d, 0)" % GROWN,
        "NPC_DRAW(0, %d)" % GROWN,
        "done:"], locals=2)

    # the cat turns into Xiao: baby Opar into Opar
    s.hook_ext(CAT_HIDDEN, [
        *baby_here("done"),
        "NPC_DRAW(0, %d)" % BABY, "NPC_DRAW(1, %d)" % GROWN,
        "done:"], locals=2)

    # the party made two: he joins (the mod), and both are put away
    s.hook_ext(PARTY_TWO, [
        *baby_here("done"),
        "SSET_GAME_FLAG(%d, 1)" % JOINED,
        "NPC_DRAW(0, %d, %d)" % (BABY, GROWN),
        "done:"], locals=2)

    # program 11 once the cat's scene has played: baby Opar's own short join
    old11 = s.program_record(11)
    region = s.function([
        "SGET_GAME_FLAG(%d, &0)" % CAT_DONE, "LOAD 0", "JMP_FALSE native",
        *baby_here("native"),
        "GET_PADDOWN(&0)", "LOAD 0", "PUSH 160", "AND", "JMP_TRUE pressed",  # cross or circle, as the cat's region
        "DRAW_EXCLAMATION_MARK()", "PUSH 0", "RET",
        "pressed:",
        "FADE_OUT(60)", "CALL %d" % fade_wait, "POP",
        "SSET_GAME_FLAG(%d, 1)" % JOINED,
        "NPC_DRAW(0, %d)" % BABY,
        "SSET_MAP_FLAG(2, 0)",
        "FADE_IN(60)",
        "PUSH 0", "RET",
        "native:", "CALL %d" % old11, "RET"], args=0, locals=2)
    s.add_program(11, region)
    return s.build()


def main(argv):
    src = argv[0] if argv else RETAIL
    out = argv[1] if len(argv) > 1 else OUT
    os.makedirs(os.path.dirname(out), exist_ok=True)
    data = patch(open(src, "rb").read())
    open(out, "wb").write(data)
    print(out, len(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
