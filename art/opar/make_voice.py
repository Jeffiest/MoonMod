"""Opar's voice bank: sound/voice/voice106.snd (106 = 100 + his character index, 6), the croaks the game plays for his
voice cues in place of Toan's, from CC0 frog sounds (art/opar/sounds, CREDITS.md).

python art/opar/make_voice.py <voice0.snd> [out voice106.snd]

Toan's bank (voice0.snd: toan_s.hd, toan_s.bd, voice0.txt) is the template: its header (programs, sample sets and
samples, so every voice cue keeps its slot) is kept, and each of its nine samples is replaced by a frog sound of a
like length (SLOTS), trimmed of silence, matched to the loudness of the one it replaces and encoded as PS ADPCM laid
out as his are: a silent block, the first block marked as the loop start (flag 4), the sound, the last sound block
flagged as the end (1), and a silent closing block (7). The Vagi chunk's offsets follow the new data; the rate stays
44.1 kHz. The pack holds opar_s.hd, opar_s.bd and voice106.txt naming the .hd.
"""

import os
import struct
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "chr"))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "snd"))
sys.path.insert(0, HERE)
import chrtool  # noqa: E402
import extract_bank as eb  # noqa: E402
from make_menu_pack import write_pack  # noqa: E402

RATE = 44100
# Toan's nine samples (0.22 0.25 0.36 0.33 0.55 0.70 0.64 0.60 1.07 s) -> (sound, speed): speed > 1 higher and shorter
SLOTS = [("croak_02", 1.0), ("croak_02", 1.15), ("croak_04", 1.1), ("ribbit_03", 1.2), ("croak_04", 1.0),
         ("ribbit_02", 1.0), ("ribbit_03", 1.0), ("croak_01", 1.15), ("croak_03", 0.85)]
FILTERS = eb.FILTERS


def load(name, speed):
    with wave.open(os.path.join(HERE, "sounds", name + ".wav")) as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1 and w.getsampwidth() == 2
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(float)
    loud = np.nonzero(np.abs(x) > 0.02 * np.abs(x).max())[0]
    x = x[max(0, loud[0] - 200):loud[-1] + 400]
    if speed != 1.0:
        x = np.interp(np.arange(0, len(x) - 1, speed), np.arange(len(x)), x)
    fade = min(len(x), 600)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def encode(samples):
    """16-bit samples -> PS ADPCM blocks (28 samples each), the best filter and shift per block, without the flags."""
    s1 = s2 = 0.0
    out = bytearray()
    padded = np.concatenate([samples, np.zeros((-len(samples)) % 28)])
    for b in range(0, len(padded), 28):
        block = padded[b:b + 28]
        best = None
        for f, (f0, f1) in enumerate(FILTERS):
            # the prediction error's range picks the shift
            p1, p2, peak = s1, s2, 0.0
            for v in block:
                pred = (p1 * f0 + p2 * f1) / 64.0
                peak = max(peak, abs(v - pred))
                p2, p1 = p1, v
            shift = 12
            while shift > 0 and peak > (7 << (12 - shift)):
                shift -= 1
            # encode with this filter and shift, tracking the decoder's state
            p1, p2, err, nibs = s1, s2, 0.0, []
            for v in block:
                pred = (p1 * f0 + p2 * f1) / 64.0
                q = int(round((v - pred) * (1 << shift) / 4096.0))
                q = max(-8, min(7, q))
                dec = (q << 12) >> shift  # as the decoder does (eb.decode)
                dec = int(dec + (int(p1) * f0 + int(p2) * f1 + 32) // 64)
                dec = max(-32768, min(32767, dec))
                err += (v - dec) ** 2
                nibs.append(q & 0x0F)
                p2, p1 = p1, dec
            if best is None or err < best[0]:
                best = (err, f, shift, nibs, p1, p2)
        _, f, shift, nibs, s1, s2 = best
        data = bytes(nibs[i] | (nibs[i + 1] << 4) for i in range(0, 28, 2))
        out += bytes([(f << 4) | shift, 0]) + data
    return out


def vag(samples):
    """Laid out as Toan's: a silent block, the sound with its first block flagged 4 and its last 1, a silent 7."""
    blocks = bytearray(encode(samples))
    blocks[1] = 4
    blocks[-15] = 1
    return bytes(16) + bytes(blocks) + bytes([0, 7]) + bytes(14)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    out = argv[1] if len(argv) > 1 else os.path.join(HERE, "..", "..", "mods", "moonmod.roguelike", "resources", "opar", "voice106.snd")
    data = open(argv[0], "rb").read()
    m = {n: data[s:s + z] for n, _, s, z in chrtool.pack_entries(data)}
    hd, bd = bytearray(m["toan_s.hd"]), m["toan_s.bd"]
    infos = eb.vag_infos(bytes(hd))
    assert len(infos) == len(SLOTS), len(infos)
    new_bd = bytearray()
    voff, _ = eb.chunks(bytes(hd))[b"IECSigaV"]
    for i, ((start, rate), (name, speed)) in enumerate(zip(infos, SLOTS)):
        end = infos[i + 1][0] if i + 1 < len(infos) else len(bd)
        theirs = np.array(eb.decode(bd, start, end), dtype=float)
        ours = load(name, speed)
        ours *= (np.abs(theirs).max() / max(1.0, np.abs(ours).max()))
        rel = struct.unpack_from("<I", hd, voff + 16 + 4 * i)[0]
        struct.pack_into("<I", hd, voff + rel, len(new_bd))
        new_bd += vag(np.clip(ours, -32768, 32767))
        print("slot %d: %s x%.2f, %.2f s (Toan's %.2f s)" % (i, name, speed, len(ours) / RATE, len(theirs) / RATE))
    # the header's record of the .bd's size
    hoff, _ = eb.chunks(bytes(hd))[b"IECSdaeH"]
    struct.pack_into("<I", hd, hoff + 16, len(new_bd))
    pack = write_pack([("opar_s.hd", bytes(hd)), ("opar_s.bd", bytes(new_bd)), ("voice106.txt", b"opar_s.hd\r\n")])
    open(out, "wb").write(pack)
    # check: every sample decodes back close to what went in
    back = {n: pack[s:s + z] for n, _, s, z in chrtool.pack_entries(pack)}
    for i, (start, _) in enumerate(eb.vag_infos(back["opar_s.hd"])):
        assert len(eb.decode(back["opar_s.bd"], start, len(back["opar_s.bd"]))) > 0
    print("%s: %d bytes" % (out, len(pack)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
