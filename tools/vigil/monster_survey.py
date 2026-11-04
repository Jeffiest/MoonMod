"""Where a monster family's blows land, for Vigil's enemy brain (BRAINS in mods/moonmod.vigil/main.lua).

    python tools/vigil/monster_survey.py <dun/monstor folder> <Chronicle port folder> ID:FILE [ID:FILE ...]

ID is the native model id (MonstorTable's index in port/src/game/monstorunit.cpp), FILE its model file (e07a). For
each it prints the motions the monster's own script plays, every SET_DMG_COL window (bone, frames) with the motions
whose range holds it, the SET_GUARD_FRAME span with the motions inside it, and every motion's frame range.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "anim"))
import moonanim as ma  # noqa: E402

D, PORT = sys.argv[1], sys.argv[2]
for arg in sys.argv[3:]:
    model, stem = arg.split(":")
    motions = ma.Rig(os.path.join(D, stem + ".chr"), os.path.join(D, stem + ".gltf"), cfg_name="info.cfg").motions
    dis = subprocess.run([sys.executable, os.path.join(HERE, "..", "stb", "stbdis.py"), os.path.join(D, stem + ".stb"),
                          "--table", "monster", "--port", PORT], capture_output=True, text=True).stdout
    played = sorted(set(int(x) for x in re.findall(r"SET_MOTION\((\d+)", dis)))
    print(f"{model} {stem}: plays {played}")
    for bone, radius, a, b in re.findall(r"SET_DMG_COL\('(\w+)', ([\d.]+), ([\d.]+), ([\d.]+)\)", dis):
        a, b = float(a), float(b)
        within = [k for k, (x, y, _) in enumerate(motions) if x != y and x <= a and b <= y + 0.5]
        print(f"  blow {bone} r{float(radius):.0f} {a:.0f}-{b:.0f} in motions {within}")
    for a, b in re.findall(r"SET_GUARD_FRAME\(([\d.]+), ([\d.]+)\)", dis):
        a, b = float(a), float(b)
        within = [k for k, (x, y, _) in enumerate(motions) if x != y and x >= a - 5 and y <= b + 8]
        print(f"  guard {a:.0f}-{b:.0f} over motions {within}")
    print("  motions " + " ".join(f"{k}:{x}-{y}" for k, (x, y, _) in enumerate(motions)))
