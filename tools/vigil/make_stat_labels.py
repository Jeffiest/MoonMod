"""Draws Vigil's weapon stat labels, At, Ed, Sp, Lt and Mp, for the weapon menu's cards.

The game paints its labels into the Status tab tall enough that each overlaps its neighbours, so Vigil wipes the
column and lays its own there (weapons.stat_label_set), one centred on each bar, all one size. They keep the game's
look: bold, rounded letters shading from cream at the top to each stat's colour (sampled from the tab), with a thick
dark outline. Lt is Speed under Vigil's Lightness rule. Drawn at 8x and shrunk to 52x30, twice the 26x15 box each is
drawn in.

    python tools/vigil/make_stat_labels.py   # writes mods/moonmod.vigil/resources/label_*.png
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SCALE = 8  # drawing pixels per card pixel
W, H = 26, 15  # a label's box on the Status tab, in card pixels
OUT = Path(__file__).resolve().parents[2] / "mods" / "moonmod.vigil" / "resources"
FONT = Path("C:/Windows/Fonts/ARLRDBD.TTF")  # Arial Rounded MT Bold

OUTLINE = (2, 54, 55)
CREAM = (251, 241, 216)
LABELS = {
    "attack": ("At", [(0.0, CREAM), (0.35, (210, 243, 203)), (0.7, (118, 214, 172)), (1.0, (96, 196, 150))]),
    "endurance": ("Ed", [(0.0, CREAM), (0.3, (251, 222, 168)), (0.6, (242, 214, 112)), (1.0, (240, 190, 44))]),
    "speed": ("Sp", [(0.0, CREAM), (0.35, (214, 244, 206)), (0.65, (150, 224, 200)), (1.0, (84, 168, 146))]),
    "lightness": ("Lt", [(0.0, CREAM), (0.35, (214, 244, 206)), (0.65, (150, 224, 200)), (1.0, (84, 168, 146))]),
    "magic": ("Mp", [(0.0, CREAM), (0.4, (236, 214, 196)), (0.7, (234, 188, 212)), (1.0, (224, 158, 206))]),
}


def shade(stops, t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return stops[-1][1]


def letters(text):
    """A capital and a small letter standing on one line at the box's foot, the small one a little shorter, left aligned."""
    mask = Image.new("L", (W * SCALE, H * SCALE), 0)
    draw = ImageDraw.Draw(mask)
    big = ImageFont.truetype(str(FONT), int(14.5 * SCALE))
    small = ImageFont.truetype(str(FONT), int(13 * SCALE))
    pad = int(1.5 * SCALE)
    foot = H * SCALE - pad
    x0, _, x1, bottom = draw.textbbox((0, 0), text[0], font=big)
    draw.text((pad - x0, foot - bottom), text[0], font=big, fill=255)
    sx0, _, _, s_bottom = draw.textbbox((0, 0), text[1], font=small)
    draw.text((pad + (x1 - x0) - sx0 + int(0.4 * SCALE), foot - s_bottom), text[1], font=small, fill=255)
    # The game's strokes are heavier than the font's.
    return mask.filter(ImageFilter.MaxFilter(2 * int(0.4 * SCALE) + 1))


def label(text, stops):
    mask = letters(text)
    w, h = mask.size
    box = mask.getbbox()
    fill = Image.new("RGBA", (w, h))
    px = fill.load()
    for y in range(h):
        c = shade(stops, min(max((y - box[1]) / max(box[3] - box[1], 1), 0.0), 1.0))
        for x in range(w):
            px[x, y] = c + (255,)
    outline = mask.filter(ImageFilter.MaxFilter(2 * int(1.3 * SCALE) + 1))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (w, h), OUTLINE + (255,)), (0, 0), outline)
    out.paste(fill, (0, 0), mask)
    # A thin light rim inside the top edges, as the game's letters have.
    rim = ImageChops.subtract(mask, mask.transform(mask.size, Image.AFFINE, (1, 0, 0, 0, 1, -int(0.5 * SCALE))))
    out.paste(Image.new("RGBA", (w, h), (255, 255, 250, 255)), (0, 0), rim.point(lambda v: v // 2))
    return out.resize((W * 2, H * 2), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (text, stops) in LABELS.items():
        path = OUT / f"label_{name}.png"
        label(text, stops).save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
