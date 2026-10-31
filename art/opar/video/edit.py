"""Opar showcase: the captured shots cut together with cards and captions, 1280x720 at 30 fps, into opar_showcase.mp4.

Each shot is its frames (shots/video/<name>_<frame>.png, every second game frame), brightened a little, with a
caption: the move's name large, its controls under it. Cards are drawn on black or over a blurred still. A few of
his croaks (his CC0 voice set) mark the title, the Croak and the slam.
"""
import glob
import os
import subprocess
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SHOTS = "E:/Gauntlet-build/run/shots/video"
OUT = "C:/Users/armor/AppData/Local/Temp/claude/E--Moonmod/4802d590-5ba4-453b-97df-ff78ca19c2de/scratchpad/video/out"
FINAL = "E:/Moonmod/art/opar/video/opar_showcase.mp4"
W, H, FPS = 1280, 720, 60
K = FPS // 30  # every length below is in 30ths of a second
FONT_BIG = "C:/Windows/Fonts/georgiab.ttf"
FONT = "C:/Windows/Fonts/segoeuib.ttf"
TEAL = (120, 225, 215)
GOLD = (245, 215, 140)

frames = []  # (image, croak or None)
cues = []    # (frame index, wav)


def font(path, size):
    return ImageFont.truetype(path, size)


def shot_frames(name):
    files = sorted(glob.glob(f"{SHOTS}/{name}_*.png"), key=lambda p: int(p.rsplit("_", 1)[1][:-4]))
    return [p for p in files if not p.endswith(f"{name}.png")]


def grade(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    a = np.clip(a ** 0.78 * 1.06, 0, 1)  # the corridors are dark: lift the shadows
    return Image.fromarray((a * 255).astype(np.uint8))


def shadowed_text(draw, xy, text, f, fill, anchor="la", alpha=255):
    x, y = xy
    for dx, dy in ((2, 2), (3, 3)):
        draw.text((x + dx, y + dy), text, font=f, fill=(0, 0, 0, int(alpha * 0.8)), anchor=anchor)
    draw.text((x, y), text, font=f, fill=fill + (alpha,), anchor=anchor)


def caption(img, title, sub, t, n):
    """A lower-left caption that slides and fades in over the first 8 frames and out over the last 8."""
    alpha = min(1.0, t / (8.0 * K), (n - t) / (8.0 * K))
    if alpha <= 0:
        return img
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    a = int(255 * alpha)
    # a soft dark band under the lower third, so the words read over the game and its HUD
    for y in range(440, H):
        d.line((0, y, W, y), fill=(0, 0, 0, int(185 * alpha * min(1.0, (y - 440) / 120.0))))
    x = 70 - int(30 * (1 - alpha))
    d.rectangle((x - 20, 512, x - 14, 600), fill=TEAL + (a,))
    shadowed_text(d, (x, 506), title, font(FONT_BIG, 54), (255, 255, 255), alpha=a)
    shadowed_text(d, (x, 570), sub, font(FONT, 26), TEAL, alpha=a)
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def add_shot(name, title, sub, cut=(0, None), croak_at=None):
    files = shot_frames(name)[cut[0]:cut[1]]
    n = len(files)
    start = len(frames)
    for t, p in enumerate(files):
        img = grade(Image.open(p))
        if title:
            img = caption(img, title, sub, t, n)
        frames.append(img)
    if croak_at is not None:
        cues.append((start + croak_at[0], croak_at[1]))
    return start, n


def card(lines, n, background=None, fade=10):
    n, fade = n * K, fade * K
    """Centred lines [(text, font, size, colour)] over black or a blurred, darkened still, fading in and out."""
    if background is not None:
        bg = grade(background).resize((W, H)).filter(ImageFilter.GaussianBlur(9))
        bg = Image.blend(Image.new("RGB", (W, H)), bg, 0.45)
    else:
        bg = Image.new("RGB", (W, H))
    total = sum(s + 18 for _, _, s, _ in lines)
    for t in range(n):
        alpha = min(1.0, t / fade, (n - t) / fade)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        y = H // 2 - total // 2
        for text, path, size, colour in lines:
            shadowed_text(d, (W // 2, y + size // 2), text, font(path, size), colour, anchor="mm", alpha=int(255 * alpha))
            y += size + 18
        frames.append(Image.alpha_composite(bg.convert("RGBA"), layer).convert("RGB"))


def still(path, title, sub, n, zoom=(1.0, 1.08)):
    n = n * K
    """A menu screenshot, slowly zoomed, letterboxed over its own blur, with a caption."""
    src = grade(Image.open(path))
    scale = H / src.height
    fg = src.resize((int(src.width * scale), H))
    bg = src.resize((W, int(src.height * W / src.width))).crop((0, 0, W, H)).filter(ImageFilter.GaussianBlur(14))
    bg = Image.blend(Image.new("RGB", (W, H)), bg, 0.5)
    for t in range(n):
        z = zoom[0] + (zoom[1] - zoom[0]) * t / max(1, n - 1)
        img = bg.copy()
        f = fg.resize((int(fg.width * z), int(fg.height * z)))
        img.paste(f, ((W - f.width) // 2, (H - f.height) // 2))
        frames.append(caption(img, title, sub, t, n))


def mix_audio(path):
    rate = 44100
    track = np.zeros(int(len(frames) / FPS * rate) + rate, np.float32)
    for at, wav in cues:
        with wave.open(wav) as w:
            x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
        start = int(at / FPS * rate)
        track[start:start + len(x)] += x[:len(track) - start] * 0.8
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((np.clip(track, -1, 1) * 32767).astype(np.int16).tobytes())


def main():
    snd = "E:/Moonmod/art/opar/sounds"
    card([("MoonMod", FONT, 30, TEAL), ("presents a new hero for Dark Genie's Gauntlet", FONT, 26, (220, 220, 220))], 75)
    s, n = add_shot("idle", None, None)
    # the title over the idle shot
    for t in range(n):
        alpha = min(1.0, max(0, t - 6 * K) / (12 * K), (n - t) / (10 * K))
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        a = int(255 * alpha)
        shadowed_text(d, (900, 300), "OPAR", font(FONT_BIG, 120), GOLD, anchor="mm", alpha=a)
        shadowed_text(d, (900, 390), "the frog mage of the Moon Sea", font(FONT, 32), (255, 255, 255), anchor="mm", alpha=a)
        frames[s + t] = Image.alpha_composite(frames[s + t].convert("RGBA"), layer).convert("RGB")
    cues.append((s + 8 * K, f"{snd}/croak_03.wav"))
    add_shot("run", "Hops where others run", "a frog's gait, staff in hand", cut=(0, 40 * K))
    card([("Strong at range.", FONT_BIG, 56, (255, 255, 255)), ("Fragile up close.", FONT_BIG, 56, TEAL)], 60)
    add_shot("spit", "Spit", "A, A, R2  ·  two globs from the throat")
    add_shot("gob", "Gob", "A, A, A, R2  ·  a fan of three")
    add_shot("bubble", "Bubble", "hold the charge, let go  ·  bursts and splashes")
    add_shot("croak", "Croak", "R2  ·  everything close is stunned", croak_at=(14 * K, f"{snd}/croak_01.wav"))
    card([("And when the gauge is full...", FONT_BIG, 50, (255, 255, 255))], 55)
    s, n = add_shot("slam", "Jump Slam", "hold the charge to the top  ·  the giant Opar comes down")
    cues.append((s + 30 * K, f"{snd}/croak_03.wav"))
    still(f"{SHOTS}/../menu4_2660.png", "Six staffs of his own", "Driftwood to the Legendary Tidecaller", 90)
    still(f"{SHOTS}/../menu3_2900.png", "One of the party", "his own face, his own place on the ring", 75)
    card([("OPAR", FONT_BIG, 96, GOLD), ("Beat the Moon Sea's Warden.", FONT, 30, (255, 255, 255)),
          ("His star rises in Norune Eternal.", FONT, 30, TEAL), ("", FONT, 20, (0, 0, 0)),
          ("Dark Genie's Gauntlet  ·  MoonMod for Dark Cloud", FONT, 24, (200, 200, 200))], 120, fade=14)

    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(f"{OUT}/*.png"):
        os.remove(f)
    for i, img in enumerate(frames):
        img.save(f"{OUT}/f{i:05d}.png", compress_level=1)
    mix_audio(f"{OUT}/audio.wav")
    os.makedirs(os.path.dirname(FINAL), exist_ok=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", f"{OUT}/f%05d.png",
                    "-i", f"{OUT}/audio.wav", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "slow",
                    "-c:a", "aac", "-b:a", "128k", "-shortest", FINAL], check=True)
    print(FINAL, len(frames), "frames", round(len(frames) / FPS, 1), "s")


if __name__ == "__main__":
    main()
