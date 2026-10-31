"""Opar's staff icons: each staff's mesh (art/opar/staffs/<stem>.json, from make_staffs.py) drawn into a 32x32 menu
icon, lying from bottom left to top right as the game's own weapon icons do, with a dark outline.

python art/opar/make_staff_icons.py [out folder, default mods/moonmod.roguelike/resources/opar]

Writes <stem>_icon.png for opst01-opst06: the mesh rendered 8x over (each pixel's texture colour by its UVs, lit from
the upper left), shrunk to 32x32, outlined one pixel. The mod registers each as icons/<stem>_icon.png.
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
STEMS = ["opst0%d" % i for i in range(1, 7)]
SIZE, OVER = 32, 8
LIGHT = np.array([-0.5, 0.6, 0.62])


def render(stem):
    data = json.load(open(os.path.join(HERE, "staffs", stem + ".json")))
    tex = np.asarray(Image.open(os.path.join(HERE, "staffs", stem + ".png")).convert("RGB"), dtype=np.float32)
    th, tw = tex.shape[:2]
    big = SIZE * OVER
    # the staff's length (z) along the diagonal, its width (x) across it, seen from the side (y toward the viewer)
    a = math.radians(45)
    def screen(p):
        u, v = p[2], p[0]
        return (u * math.cos(a) - v * math.sin(a), u * math.sin(a) + v * math.cos(a), p[1])
    tris = [[(screen(v["p"]), v["n"], v["uv"]) for v in t] for t in data["triangles"]]
    xs = [s[0] for t in tris for s, _, _ in t]
    ys = [s[1] for t in tris for s, _, _ in t]
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    scale = (big - 2 * OVER) / span
    ox = (big - (max(xs) - min(xs)) * scale) / 2 - min(xs) * scale
    oy = (big - (max(ys) - min(ys)) * scale) / 2 - min(ys) * scale
    color = np.zeros((big, big, 4), np.float32)
    depth = np.full((big, big), -1e9, np.float32)
    light = LIGHT / np.linalg.norm(LIGHT)
    for t in tris:
        pts = np.array([[s[0] * scale + ox, big - (s[1] * scale + oy), s[2]] for s, _, _ in t])
        x0, x1 = int(max(0, pts[:, 0].min())), int(min(big - 1, pts[:, 0].max() + 1))
        y0, y1 = int(max(0, pts[:, 1].min())), int(min(big - 1, pts[:, 1].max() + 1))
        if x1 < x0 or y1 < y0:
            continue
        (ax, ay, _), (bx, by, _), (cx, cy, _) = pts
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / den
        w1 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        z = w0 * pts[0, 2] + w1 * pts[1, 2] + w2 * pts[2, 2]
        region = depth[y0:y1 + 1, x0:x1 + 1]
        nearer = inside & (z > region)
        if not nearer.any():
            continue
        uv = np.array([v[2] for v in t])
        u = (w0 * uv[0, 0] + w1 * uv[1, 0] + w2 * uv[2, 0]) % 1.0
        v = (w0 * uv[0, 1] + w1 * uv[1, 1] + w2 * uv[2, 1]) % 1.0
        texel = tex[np.clip((v * th).astype(int), 0, th - 1), np.clip((u * tw).astype(int), 0, tw - 1)]
        n = np.array([screen(v[1]) for v in t])
        nrm = w0[..., None] * n[0] + w1[..., None] * n[1] + w2[..., None] * n[2]
        nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True) + 1e-9
        shade = 0.45 + 0.75 * np.clip(nrm @ light, 0, 1)
        region[nearer] = z[nearer]
        patch = color[y0:y1 + 1, x0:x1 + 1]
        patch[nearer, :3] = np.clip(texel[nearer] * shade[nearer][..., None], 0, 255)
        patch[nearer, 3] = 255
    img = Image.fromarray(color.astype(np.uint8), "RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    # a one-pixel dark outline round the shape, under it
    alpha = img.split()[3].point(lambda x: 255 if x > 40 else 0)
    ring = alpha.filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (SIZE, SIZE), (18, 14, 10, 255)), (0, 0), ring)
    out.alpha_composite(img)
    return out


def main(argv):
    folder = argv[0] if argv else os.path.join(HERE, "..", "..", "mods", "moonmod.roguelike", "resources", "opar")
    os.makedirs(folder, exist_ok=True)
    for stem in STEMS:
        render(stem).save(os.path.join(folder, stem + "_icon.png"))
    print("icons:", ", ".join(s + "_icon.png" for s in STEMS), "->", folder)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
