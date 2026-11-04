"""Draws Vigil's gear icons: a hat, a tunic, gloves, boots and a pouch, in light greys with a dark outline.

The engine tints each piece its own colour when it draws one (items.gear_give `color`), so one grey icon makes every
coloured version: keep them light, the tint only darkens. Drawn at 4x and shrunk to 32x32 for smooth edges.

    python tools/vigil/make_gear_icons.py   # writes mods/moonmod.vigil/resources/gear_*.png
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SCALE = 4
SIZE = 32 * SCALE
OUT = Path(__file__).resolve().parents[2] / "mods" / "moonmod.vigil" / "resources"

OUTLINE = (34, 30, 36, 255)
LIGHT = (246, 246, 246, 255)
MID = (206, 206, 210, 255)
SHADE = (156, 156, 164, 255)
DARK = (112, 112, 122, 255)


def p(points):
    return [(x * SCALE, y * SCALE) for x, y in points]


def shape(draw, points, fill, width=1.6):
    draw.polygon(p(points), fill=fill, outline=OUTLINE, width=int(width * SCALE))


def line(draw, points, fill=OUTLINE, width=1.2):
    draw.line(p(points), fill=fill, width=int(width * SCALE), joint="curve")


def hat(draw):
    # A soft pointed cap with a band and a brim, leaning back.
    shape(draw, [(5, 24), (9, 15), (14, 8), (21, 4), (27, 3), (24, 8), (24, 14), (26, 21), (26, 24)], MID)
    shape(draw, [(14, 8), (21, 4), (27, 3), (24, 8), (19, 9)], LIGHT, 1.0)
    shape(draw, [(6, 21), (26, 20), (26, 24), (6, 25)], SHADE, 1.2)
    shape(draw, [(2, 25), (29, 23), (30, 26), (16, 28.5), (3, 28)], DARK, 1.4)
    line(draw, [(9, 16), (12, 11)], LIGHT, 1.4)


def tunic(draw):
    # A short-sleeved tunic with a V neck and a belt.
    body = [(9, 3), (13, 3), (16, 8), (19, 3), (23, 3), (30, 8), (27, 15), (24, 13), (24, 29), (8, 29), (8, 13), (5, 15),
            (2, 8)]
    shape(draw, body, MID)
    shape(draw, [(19, 3), (23, 3), (30, 8), (27, 15), (24, 13), (24, 29), (19, 29)], SHADE, 1.0)
    shape(draw, [(13, 3), (16, 8), (19, 3), (17.5, 3), (16, 6), (14.5, 3)], DARK, 1.0)
    shape(draw, [(8, 20), (24, 20), (24, 23), (8, 23)], DARK, 1.2)
    shape(draw, [(14.5, 19.5), (17.5, 19.5), (17.5, 23.5), (14.5, 23.5)], LIGHT, 1.0)
    line(draw, [(10, 8), (11, 17)], LIGHT, 1.4)


def gloves(draw):
    # One gauntlet, fingers up, with a flared cuff.
    shape(draw, [(8, 17), (8, 9), (10, 7.5), (12, 9), (12, 5), (14, 3.5), (16, 5), (16, 4), (18, 2.5), (20, 4), (20, 6),
                 (22, 5), (24, 6.5), (24, 17), (27, 12), (29.5, 13), (29, 16), (24, 23), (10, 23)], MID)
    shape(draw, [(20, 6), (22, 5), (24, 6.5), (24, 17), (27, 12), (29.5, 13), (29, 16), (24, 23), (20, 23)], SHADE, 1.0)
    line(draw, [(12, 9), (12, 15)], OUTLINE, 1.0)
    line(draw, [(16, 5), (16, 15)], OUTLINE, 1.0)
    line(draw, [(20, 6), (20, 15)], OUTLINE, 1.0)
    shape(draw, [(8, 22), (25, 22), (28, 30), (5, 30)], DARK, 1.4)
    line(draw, [(9.5, 10), (9.5, 16)], LIGHT, 1.2)


def boots(draw):
    # One boot in profile, toe to the right, with a folded top.
    shape(draw, [(8, 3), (19, 3), (19, 18), (27, 21), (30, 24), (30, 28), (6, 28), (7, 18)], MID)
    shape(draw, [(19, 18), (27, 21), (30, 24), (30, 28), (17, 28), (17, 18)], SHADE, 1.0)
    shape(draw, [(6.5, 3), (20.5, 3), (20, 8), (7, 8)], LIGHT, 1.4)
    shape(draw, [(5, 26), (31, 26), (31, 29.5), (5, 29.5)], DARK, 1.4)
    line(draw, [(10, 10), (9.5, 20)], LIGHT, 1.4)


def pouch(draw):
    # A satchel with its strap over the top, a flap and a buckle.
    line(draw, [(7, 14), (9, 6), (16, 3), (23, 6), (25, 14)], OUTLINE, 3.2)
    line(draw, [(7, 14), (9, 6), (16, 3), (23, 6), (25, 14)], SHADE, 1.6)
    shape(draw, [(4, 13), (28, 13), (29, 27), (27, 29.5), (5, 29.5), (3, 27)], MID)
    shape(draw, [(20, 13), (28, 13), (29, 27), (27, 29.5), (20, 29.5)], SHADE, 1.0)
    shape(draw, [(4, 13), (28, 13), (27, 21), (16, 23), (5, 21)], LIGHT, 1.4)
    shape(draw, [(14, 19.5), (18, 19.5), (18, 24.5), (14, 24.5)], DARK, 1.2)


def render(paint):
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    paint(ImageDraw.Draw(image))
    # A soft drop shadow under the shape, as the game's own icons have.
    alpha = image.getchannel("A")
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda a: a * 0.45).filter(ImageFilter.GaussianBlur(SCALE * 0.8)))
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    out.alpha_composite(shadow, (SCALE, SCALE))
    out.alpha_composite(image)
    return out.resize((32, 32), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, paint in (("hat", hat), ("tunic", tunic), ("gloves", gloves), ("boots", boots), ("pouch", pouch)):
        render(paint).save(OUT / f"gear_{name}.png")
        print("wrote", OUT / f"gear_{name}.png")


if __name__ == "__main__":
    main()
