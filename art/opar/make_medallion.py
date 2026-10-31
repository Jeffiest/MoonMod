"""Opar's face as the menus' round medallion (the character change ring and the Allies card), like the six's in the
game's quickchara picture (commenu quickchr.img: 48x48 cells, each face filling its circle, edged by a thin dark
outline with a faint light rim inside it).

python art/opar/make_medallion.py [face.png] [out medallion.png]

His portrait, a little zoomed onto his face, fills a circle of the cell's size (radius 23.5 of 48, scaled to 128);
a dark outline and a soft highlight just inside it make the edge; outside it is clear. Nothing is taken from the
six's own pictures, so none of them shows round his. The mod registers the result as his portrait.
"""

import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE, CELL = 128, 48
RADIUS = 23.5   # of the 48-pixel cell, as the six's circles
OUTLINE = 1.1   # the dark edge, in cell pixels
ZOOM = 1.18     # the portrait zoomed onto the face


def main(argv):
    face_path = argv[0] if argv else os.path.join(HERE, "..", "..", "mods", "moonmod.roguelike", "resources", "opar", "face.png")
    out = argv[1] if len(argv) > 1 else os.path.join(HERE, "..", "..", "mods", "moonmod.roguelike", "resources", "opar", "medallion.png")
    k = SIZE / CELL
    face = Image.open(face_path).convert("RGBA")
    w = int(face.width / ZOOM)
    face = face.crop(((face.width - w) // 2, (face.height - w) // 2 - 4, (face.width + w) // 2, (face.height + w) // 2 - 4))
    img = np.asarray(face.resize((SIZE, SIZE), Image.LANCZOS)).astype(float)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    c = (SIZE - 1) / 2
    d = np.hypot(xx - c, yy - c)
    r, edge = RADIUS * k, OUTLINE * k
    # a faint light rim just inside the outline, brighter toward the top left (the six's light comes from there)
    light = np.clip(1 - np.abs(d - (r - edge - 1.5)) / 1.5, 0, 1) * (0.25 + 0.2 * np.clip(((c - xx) + (c - yy)) / SIZE, -1, 1))
    img[..., :3] = img[..., :3] * (1 - light[..., None]) + 235 * light[..., None]
    # the dark outline
    dark = np.clip(1 - np.abs(d - (r - edge / 2)) / (edge / 2 + 0.5), 0, 1)
    img[..., :3] = img[..., :3] * (1 - dark[..., None]) + 18 * dark[..., None]
    img[..., 3] = np.clip(r - d + 0.5, 0, 1) * 255
    Image.fromarray(img.astype(np.uint8), "RGBA").save(out)
    print("medallion:", out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
