"""Opar's menu model pack (commenu/dungeon/c07model.pak): the model the item menu shows standing beside his status,
like the other characters' c0Nmodel.pak.

python art/opar/make_menu_pack.py <c07d.chr> <c07d.gltf> <out c07model.pak>

Toan's (c01model.pak) holds his model, its texture, its skin (bbp, wgt) and a short motion, c01dstat.mot: standing at
frames 5-15, knocked down at 20-30 (its c01dmenu.cfg, KEY lines). This builds Opar's the same way from his own
dungeon pack: c07d.mds, his c07d01_dun.img as c07dmenu.img, c07d.bbp and c07d.wgt as c07dstat's, and a c07dstat.mot
keyed every frame from 1 to 30 with his own idle (frames 10-20 of his pack) and the end of his defeat (Toan's 460-480,
a frog's in his pack). The menu reads members by name: c07dmenu.cfg, c07dmenu.img.
"""

import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "chr"))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "anim"))
import chrtool  # noqa: E402
import moonanim as ma  # noqa: E402
import opar_moves  # noqa: E402

CFG = """//Opar, the item menu's model (art/opar/make_menu_pack.py)

VERTEX_ANIME 1

ALLOC_DBUFF "skin"
MODEL "c07d.mds"

MOTION 0, "c07dstat.mot", "c07dstat.bbp", "c07dstat.wgt"

KEY_START 0
\tKEY\t5,\t15,\t0.1,\t//standing 0
\tKEY\t20,\t30,\t0.1,\t//down 1
MOTION_END
"""


def write_pack(members):
    """A pack of (name, bytes): each a 64-byte name, the data's offset (80), its size, the next entry's offset, 4
    spare bytes, then the data padded to 16; an empty entry closes it."""
    out = bytearray()
    for name, data in members:
        padded = (len(data) + 15) // 16 * 16
        head = bytearray(80)
        chrtool._put_name(head, 0, 64, name.encode("latin1"))
        struct.pack_into("<iii", head, 64, 80, len(data), 80 + padded)
        out += head + data + bytes(padded - len(data))
    return bytes(out + bytes(80))


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    pack, gltf, out = argv
    data = open(pack, "rb").read()
    m = {n: data[s:s + z] for n, _, s, z in chrtool.pack_entries(data)}
    rig = ma.Rig(pack, gltf)
    poses = {}
    for f in range(1, 31):
        if f <= 17:
            poses[f] = rig.sample(10 + max(0, min(10, f - 5)))  # his idle, frames 10-20
        else:
            poses[f] = rig.sample(470 + max(0, min(10, f - 20)))  # down: the end of his defeat
    mot = opar_moves.write_mot(rig, m[rig.mot_name], poses)
    members = [("c07d.mds", m["c07d.mds"]), ("c07dmenu.cfg", CFG.encode("ascii")), ("c07dmenu.img", m["c07d01_dun.img"]),
               ("c07dstat.bbp", m["c07d.bbp"]), ("c07dstat.mot", mot), ("c07dstat.wgt", m["c07d.wgt"])]
    blob = write_pack(members)
    open(out, "wb").write(blob)
    back = [n for n, *_ in chrtool.pack_entries(blob)]
    assert back == [n for n, _ in members], back
    print("%s: %d bytes (%s)" % (out, len(blob), ", ".join(back)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
