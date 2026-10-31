"""Dark Cloud sound banks (.snd packs of PS2 .hd/.bd pairs) to WAV files, one per sample, to hear what a bank holds.

python tools/snd/extract_bank.py <bank.snd> <out folder>

Each .hd is SCEI's ("IECSsreV" header, then chunks "IECSdaeH", "IECSigaV", ...); its Vagi chunk lists every sample's
offset in the paired .bd and its rate. The .bd is PS ADPCM (16-byte frames: shift and filter, a flag byte, 14 bytes
of 4-bit samples). Writes <hd stem>_<index>.wav (mono, 16-bit) and prints each sample's length.
"""

import os
import struct
import sys
import wave

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "chr"))
import chrtool  # noqa: E402

FILTERS = [(0, 0), (60, 0), (115, -52), (98, -55), (122, -60)]


def chunks(hd):
    """The .hd's chunks by tag: {tag: (offset, size)}."""
    out, off = {}, 0
    while off + 16 <= len(hd):
        tag = hd[off:off + 8]
        size = struct.unpack_from("<I", hd, off + 8)[0]
        out[tag] = (off, size)
        if size <= 0:
            break
        off += size
    return out


def vag_infos(hd):
    """(bd offset, rate) for each sample, from the Vagi chunk: a max index, then that many+1 offsets to entries of
    (bd offset u32, rate u16, loop u8, pad)."""
    c = chunks(hd)
    if b"IECSigaV" not in c:
        return []
    off, size = c[b"IECSigaV"]
    max_index = struct.unpack_from("<I", hd, off + 12)[0]
    out = []
    for i in range(max_index + 1):
        rel = struct.unpack_from("<I", hd, off + 16 + 4 * i)[0]
        if rel == 0xFFFFFFFF:
            continue
        bd_off, rate = struct.unpack_from("<IH", hd, off + rel)
        out.append((bd_off, rate))
    return out


def decode(bd, start, end):
    """PS ADPCM from start to end (or the frame flagged last) -> 16-bit samples."""
    s1 = s2 = 0
    out = []
    pos = start
    while pos + 16 <= end:
        head, flags = bd[pos], bd[pos + 1]
        shift, filt = head & 0x0F, min(head >> 4, 4)
        f0, f1 = FILTERS[filt]
        for b in bd[pos + 2:pos + 16]:
            for nib in (b & 0x0F, b >> 4):
                v = nib - 16 if nib >= 8 else nib
                v = (v << 12) >> shift
                v += (s1 * f0 + s2 * f1 + 32) >> 6
                v = max(-32768, min(32767, v))
                s2, s1 = s1, v
                out.append(v)
        pos += 16
        if flags & 1 and pos > start + 16:
            break
    return out


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    data = open(argv[0], "rb").read()
    members = {n: data[s:s + z] for n, _, s, z in chrtool.pack_entries(data)}
    os.makedirs(argv[1], exist_ok=True)
    for name, hd in members.items():
        if not name.endswith(".hd") or len(hd) == 0:
            continue
        bd = members.get(name[:-3] + ".bd", b"")
        infos = vag_infos(hd)
        for i, (start, rate) in enumerate(infos):
            end = infos[i + 1][0] if i + 1 < len(infos) and infos[i + 1][0] > start else len(bd)
            samples = decode(bd, start, end)
            path = os.path.join(argv[1], "%s_%02d.wav" % (name[:-3], i))
            with wave.open(path, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(rate or 22050)
                w.writeframes(struct.pack("<%dh" % len(samples), *samples))
            print("%s: %.2f s at %d Hz" % (os.path.basename(path), len(samples) / float(rate or 22050), rate))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
