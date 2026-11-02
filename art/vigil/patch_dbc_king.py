"""Builds Vigil's Divine Beast Cave event script: the Fairy King's floor scenes as programs a talk can start.

    python art/vigil/patch_dbc_king.py [RETAIL_EVENT_STB]

On a Vigil World region map the dungeon's floor-start program (100) runs once, for the map's first floor, so the
King's scenes for floors 3, 5 and 7 (scene files e32, e30 and e31, each played once, behind story flags 106, 104 and
105) never come. This adds programs 191, 192 and 193 that play them, as program 100 does: set the flag, fade out,
wait for the fade, play the scene. Vigil starts one (dungeons.play_event) when the player talks to the King at that
floor's zone shrine. Floor 1's scene (program 199, flag 103) is the dungeon's opening: walked in through the town's
door it doesn't play on arrival (Vigil sets flag 103 first), and program 190 plays it when the player walks up to the
King standing a little ahead.

Run it again whenever this file changes; the output is shipped with the mod as Opar's patched house script is.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "stb"))
from stbpatch import Script  # noqa: E402

RETAIL = "E:/Gauntlet-build/run/data/dun/script/d01/event.stb"
OUT = os.path.join(ROOT, "mods", "moonmod.vigil", "resources", "dun", "d01_event.stb")

# program 100's CALLs: the fade wait, then each scene (code offsets in the retail script)
FADE_WAIT_AT = 0x566e8
SCENES = {  # program: (story flag, the CALL of the scene in program 100)
    191: (106, 0x56700),  # floor 3, e32
    192: (104, 0x56820),  # floor 5, e30
    193: (105, 0x56940),  # floor 7, e31
}


# floor 1's scene, as program 100 runs it: its own program, started rather than called
ENTRY_PROGRAM, ENTRY_SCENE = 190, 199


def build(retail):
    s = Script(open(retail, "rb").read())
    fade_wait = s.old_record(FADE_WAIT_AT)
    s.add_program(ENTRY_PROGRAM, s.function([
        "FADE_OUT(10)", "CALL %d" % fade_wait, "POP",
        "RUN_SCRIPT_NO(%d, 1)" % ENTRY_SCENE, "WAIT", "WAIT",
        "PUSH 0", "RET"], args=0, locals=0))
    for program, (flag, call_at) in SCENES.items():
        scene = s.old_record(call_at)
        f = s.function([
            "SSET_GAME_FLAG(%d, 1)" % flag,
            "FADE_OUT(10)", "CALL %d" % fade_wait, "POP",
            "CALL %d" % scene, "POP",
            "PUSH 0", "RET"], args=0, locals=0)
        s.add_program(program, f)
    return s.build()


if __name__ == "__main__":
    retail = sys.argv[1] if len(sys.argv) > 1 else RETAIL
    data = build(retail)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "wb").write(data)
    print("wrote %s (%d bytes)" % (OUT, len(data)))
