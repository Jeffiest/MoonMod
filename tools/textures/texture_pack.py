#!/usr/bin/env python3
"""Make a texture package for Chronicle: dump the game's own textures, upscale them, check the result.

    python tools/textures/texture_pack.py dump    --game darkcloud.exe --out dumps
    python tools/textures/texture_pack.py upscale --dump dumps --package <save>/mods/me.hires --model model.onnx
    python tools/textures/texture_pack.py check   --package <save>/mods/me.hires --dump dumps

dump     runs the game with DC_TEXTURE_DUMP set, so every texture it loads is written as <texture name>.png, before
         any package replaces it. With no --play it runs headless through a list of places on a scratch save; with
         --play it starts the game as usual and dumps whatever you walk past.
upscale  enlarges each dumped picture with an ESRGAN-style ONNX model (any scale, the usual is 4x) and writes it to
         <package>/textures/<texture name>.png, with a mod.json and main.lua if the package has none.
check    lists a package's pictures: whether the name can match a texture, and the size the game keeps it at.

The pictures a package holds are made from the game's disc. Share the tool and your settings, not the pictures.
Needs Python 3.10+, numpy and Pillow; upscale with a model also needs onnxruntime (onnxruntime-directml or
onnxruntime-gpu to run it on the graphics card). See tools/textures/README.md.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
from PIL import Image

# What the engine takes as a texture file's name (port/src/moonmod/mod_texture.cpp).
NAME = re.compile(r"^[a-z0-9_-]+$")
# Pictures the game loads another way, which a package cannot replace.
NOT_REPLACEABLE = ("stayframe",)
# Where the headless dump goes when no --jump is given.
PLACES = ("e01", "e03", "e04", "dungeon:0", "dungeon:1", "dungeon:2", "dungeon:3", "dungeon:4", "dungeon:5",
          "dungeon:6", "menu", "title")
PROVIDERS = {"dml": "DmlExecutionProvider", "cuda": "CUDAExecutionProvider", "cpu": "CPUExecutionProvider"}
# The engine's limits (ModsTextureMaxSide, ModsTextureMaxScale): the desktop game, and the browser one.
LIMITS = {"desktop": (4096, 8), "browser": (2048, 2)}


def kept_size(width: int, height: int, native_width: int, native_height: int, max_side: int, max_scale: int):
    """The size the engine keeps a width x height PNG at for a native texture (ModsTextureSizeFor)."""
    def over(side: int, native: int) -> bool:
        return side > max_side or side > native * max(1, max_scale)

    while (width > native_width or height > native_height) and (over(width, native_width) or over(height, native_height)):
        width, height = (width + 1) // 2, (height + 1) // 2
    return max(width, native_width), max(height, native_height)


# --- upscalers ---------------------------------------------------------------------------------------------------

def pad(picture: np.ndarray, margin: int, wrap_x: bool, wrap_y: bool) -> np.ndarray:
    """`margin` texels of context on every side: the far edge where the picture repeats, a mirror where it does not."""
    height, width = picture.shape[:2]
    mode_y = "wrap" if wrap_y else ("reflect" if height > margin else "edge")
    mode_x = "wrap" if wrap_x else ("reflect" if width > margin else "edge")
    picture = np.pad(picture, ((margin, margin), (0, 0), (0, 0)), mode=mode_y)
    return np.pad(picture, ((0, 0), (margin, margin), (0, 0)), mode=mode_x)


class Lanczos:
    """No model: a plain resize. For trying the steps out; it adds no detail."""

    def __init__(self, scale: int = 4):
        self.scale = scale
        self.name = f"lanczos {scale}x"

    def upscale(self, rgb: np.ndarray, wrap_x: bool, wrap_y: bool) -> np.ndarray:
        margin = 4
        height, width = rgb.shape[:2]
        padded = pad(rgb, margin, wrap_x, wrap_y)
        channels = []
        for channel in range(3):
            plane = Image.fromarray(np.ascontiguousarray(padded[..., channel]))
            plane = plane.resize((padded.shape[1] * self.scale, padded.shape[0] * self.scale), Image.LANCZOS)
            channels.append(np.asarray(plane))
        large = np.dstack(channels)
        edge = margin * self.scale
        return large[edge:edge + height * self.scale, edge:edge + width * self.scale]


class OnnxModel:
    """An ESRGAN-style model: one float input [1,3,h,w] of RGB in 0..1, one output [1,3,s*h,s*w]."""

    def __init__(self, path: Path, provider: str = "dml", tile: int = 256, overlap: int = 16):
        try:
            import onnxruntime
        except ImportError:
            raise SystemExit("upscale with --model needs onnxruntime: pip install onnxruntime-directml "
                             "(Windows, any graphics card), onnxruntime-gpu (CUDA) or onnxruntime (processor)")
        available = onnxruntime.get_available_providers()
        wanted = [PROVIDERS[provider]] if PROVIDERS[provider] in available else []
        self.session = onnxruntime.InferenceSession(str(path), providers=wanted + ["CPUExecutionProvider"])
        source = self.session.get_inputs()[0]
        self.input = source.name
        self.output = self.session.get_outputs()[0].name
        self.dtype = np.float16 if "float16" in source.type else np.float32
        self.tile, self.overlap = tile, overlap
        probe = self._run(np.zeros((16, 16, 3), np.float32))
        if probe.shape[0] % 16 or probe.shape[0] != probe.shape[1] or probe.shape[0] < 16:
            raise SystemExit(f"{path.name}: a 16x16 picture came back {probe.shape[1]}x{probe.shape[0]}; "
                             "not a whole-number upscaler")
        self.scale = probe.shape[0] // 16
        self.name = f"{path.name} {self.scale}x on {self.session.get_providers()[0]}"

    def _run(self, rgb: np.ndarray) -> np.ndarray:
        tensor = np.ascontiguousarray(rgb.transpose(2, 0, 1)[None], dtype=self.dtype)
        result = self.session.run([self.output], {self.input: tensor})[0][0]
        return result.transpose(1, 2, 0).astype(np.float32)

    def upscale(self, rgb: np.ndarray, wrap_x: bool, wrap_y: bool) -> np.ndarray:
        """In tiles, each with `overlap` texels of context on every side; where two tiles' context overlaps their
        results are cross-faded, so no seam shows."""
        height, width = rgb.shape[:2]
        scale, margin, tile = self.scale, self.overlap, self.tile
        padded = pad(rgb, margin, wrap_x, wrap_y)
        total = np.zeros((height * scale, width * scale, 3), np.float32)
        weight = np.zeros((height * scale, width * scale, 1), np.float32)

        def starts(length: int) -> list[int]:
            return [0] if length <= tile else list(range(0, length - tile, tile)) + [length - tile]

        for y0 in starts(height):
            for x0 in starts(width):
                y1, x1 = min(height, y0 + tile), min(width, x0 + tile)
                large = self._run(padded[y0:y1 + 2 * margin, x0:x1 + 2 * margin])
                # The tile, plus the context that lies inside the picture (the padding is dropped).
                lead_y, lead_x = min(margin, y0), min(margin, x0)
                trail_y, trail_x = min(margin, height - y1), min(margin, width - x1)
                top, left = margin - lead_y, margin - lead_x
                bottom, right = margin + (y1 - y0) + trail_y, margin + (x1 - x0) + trail_x
                part = large[top * scale:bottom * scale, left * scale:right * scale]
                fade = (self._fade(bottom - top, lead_y, trail_y)[:, None] *
                        self._fade(right - left, lead_x, trail_x)[None, :])[..., None]
                at_y, at_x = (y0 - lead_y) * scale, (x0 - lead_x) * scale
                total[at_y:at_y + part.shape[0], at_x:at_x + part.shape[1]] += part * fade
                weight[at_y:at_y + part.shape[0], at_x:at_x + part.shape[1]] += fade
        return total / np.maximum(weight, 1e-6)

    def _fade(self, texels: int, lead: int, trail: int) -> np.ndarray:
        """A weight per output pixel along one side: up from 0 over the leading context, down to 0 over the
        trailing one, 1 between."""
        length = texels * self.scale
        fade = np.ones(length, np.float32)
        if lead:
            ramp = 2 * lead * self.scale
            fade[:ramp] = np.minimum(fade[:ramp], (np.arange(ramp) + 0.5) / ramp)
        if trail:
            ramp = 2 * trail * self.scale
            fade[length - ramp:] = np.minimum(fade[length - ramp:], (np.arange(ramp)[::-1] + 0.5) / ramp)
        return fade


# --- one picture -------------------------------------------------------------------------------------------------

def repeats(rgba: np.ndarray, axis: int) -> bool:
    """Whether the picture seems to tile along an axis: its two far edges differ about as little as two
    neighbouring lines inside it do."""
    lines = np.moveaxis(rgba.astype(np.float32), axis, 0)
    if lines.shape[0] < 8:
        return False
    across = np.abs(lines[0] - lines[-1]).mean()
    inside = np.abs(lines[1:] - lines[:-1]).mean()
    return bool(across <= 1.5 * inside + 2.0)


def bleed(rgb: np.ndarray, visible: np.ndarray, rounds: int = 64) -> np.ndarray:
    """Give texels nobody sees (alpha 0) the colour of the nearest visible ones, so the model draws no dark fringe
    around a cut-out."""
    if visible.all() or not visible.any():
        return rgb
    rgb = rgb.copy()
    known = visible.copy()
    for _ in range(rounds):
        if known.all():
            break
        known_padded = np.pad(known, 1, mode="edge").astype(np.float32)
        colour_padded = np.pad(rgb * known[..., None], ((1, 1), (1, 1), (0, 0)), mode="edge")
        height, width = known.shape
        count = sum(known_padded[1 + dy:1 + dy + height, 1 + dx:1 + dx + width]
                    for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        colour = sum(colour_padded[1 + dy:1 + dy + height, 1 + dx:1 + dx + width]
                     for dy in (-1, 0, 1) for dx in (-1, 0, 1))
        grow = (~known) & (count > 0)
        rgb[grow] = colour[grow] / count[grow][:, None]
        known |= grow
    return rgb


def upscale_picture(upscaler, image: Image.Image, edge: str = "auto", alpha: str = "model") -> Image.Image:
    """The picture at the upscaler's scale. `edge`: wrap (it tiles), reflect (it does not) or auto (look at its
    edges, each way apart). `alpha`: through the model as grey (crisp cut-outs) or bicubic (soft glows)."""
    rgba = np.asarray(image.convert("RGBA"))
    height, width = rgba.shape[:2]
    wrap_x = edge == "wrap" or (edge == "auto" and repeats(rgba, 1))
    wrap_y = edge == "wrap" or (edge == "auto" and repeats(rgba, 0))
    rgb = rgba[..., :3].astype(np.float32) / 255.0
    opacity = rgba[..., 3].astype(np.float32) / 255.0
    has_alpha = bool(opacity.min() < 1.0)
    if has_alpha:
        rgb = bleed(rgb, opacity > 0.02)
    large = np.clip(upscaler.upscale(rgb, wrap_x, wrap_y), 0.0, 1.0)
    if not has_alpha:
        return Image.fromarray((large * 255.0 + 0.5).astype(np.uint8))
    scale = upscaler.scale
    if alpha == "model":
        grey = np.repeat(opacity[..., None], 3, axis=2)
        large_opacity = np.clip(upscaler.upscale(grey, wrap_x, wrap_y).mean(axis=2), 0.0, 1.0)
    else:
        plane = Image.fromarray((opacity * 255.0 + 0.5).astype(np.uint8))
        large_opacity = np.asarray(plane.resize((width * scale, height * scale), Image.BICUBIC), np.float32) / 255.0
    return Image.fromarray((np.dstack([large, large_opacity]) * 255.0 + 0.5).astype(np.uint8))


# --- the commands ------------------------------------------------------------------------------------------------

def matches(name: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(name, pattern.lower()) for pattern in patterns)


def dumped_pictures(dump: Path, only: list[str], skip: list[str]):
    """(texture name, file) for each dumped picture to work on, and (file, why) for each left out."""
    chosen: dict[str, Path] = {}
    left_out: list[tuple[Path, str]] = []
    for file in sorted(dump.glob("*.png")):
        name = file.stem.lower()
        if not NAME.match(name):
            left_out.append((file, "a package cannot name it (only a-z, 0-9, _ and - match a texture)"))
        elif name in chosen:
            left_out.append((file, f"same texture as {chosen[name].name}"))
        elif name in NOT_REPLACEABLE:
            left_out.append((file, "the game loads it another way; a package cannot replace it"))
        elif (only and not matches(name, only)) or matches(name, skip):
            continue
        else:
            chosen[name] = file
    return list(chosen.items()), left_out


def write_package_files(package: Path, package_id: str, name: str, author: str, model: str) -> None:
    """A mod.json and main.lua for a package that has none; one that has them keeps them."""
    manifest = package / "mod.json"
    if not manifest.exists():
        manifest.write_text(json.dumps({
            "schema_version": 1, "id": package_id, "name": name, "version": "1.0.0", "coop": "local",
            "author": author, "description": f"Larger textures, upscaled with {model}.",
            "framework_api": 1, "games": ["chronicle"], "entry": "main.lua",
        }, indent=2) + "\n", encoding="utf-8")
    entry = package / "main.lua"
    if not entry.exists():
        entry.write_text("-- Textures only: the game reads textures/<texture name>.png itself.\n", encoding="utf-8")


def command_upscale(arguments) -> int:
    dump, package = Path(arguments.dump), Path(arguments.package)
    if not dump.is_dir():
        raise SystemExit(f"{dump} is not a folder of dumped textures")
    package_id = arguments.id or package.name.lower()
    if not re.match(r"^[a-z0-9][a-z0-9._-]*$", package_id):
        raise SystemExit(f"'{package_id}' is not a package id (lower-case letters, digits, . _ -); give one with --id")
    pictures, left_out = dumped_pictures(dump, arguments.only, arguments.skip)
    for file, why in left_out:
        print(f"left out {file.name}: {why}")
    if not pictures:
        raise SystemExit("nothing to upscale")
    if arguments.model:
        upscaler = OnnxModel(Path(arguments.model), arguments.provider, arguments.tile, arguments.overlap)
    else:
        upscaler = Lanczos(arguments.scale or 4)
    scale = arguments.scale or upscaler.scale
    if scale > upscaler.scale:
        raise SystemExit(f"--scale {scale} is more than the model's {upscaler.scale}x")
    print(f"{len(pictures)} pictures, {upscaler.name}, kept at {scale}x")
    textures = package / "textures"
    textures.mkdir(parents=True, exist_ok=True)
    write_package_files(package, package_id, arguments.name or "Larger textures", arguments.author, upscaler.name)
    started, done, failed = time.time(), 0, 0
    for index, (name, file) in enumerate(pictures, 1):
        target = textures / f"{name}.png"
        if not arguments.redo and target.exists() and target.stat().st_mtime >= file.stat().st_mtime:
            continue
        try:
            with Image.open(file) as image:
                image.load()
                large = upscale_picture(upscaler, image, arguments.edge, arguments.alpha)
                width, height = image.width * scale, image.height * scale
                # The engine halves anything over its limit when it loads; do it once here instead, and better.
                width, height = kept_size(width, height, image.width, image.height, *LIMITS["desktop"])
            if large.size != (width, height):
                large = large.resize((width, height), Image.LANCZOS)
            large.save(target, compress_level=6)
            done += 1
        except Exception as error:  # one bad picture does not stop the rest
            failed += 1
            print(f"FAILED {file.name}: {error}")
        if index % 25 == 0 or index == len(pictures):
            print(f"{index}/{len(pictures)} in {time.time() - started:.0f}s", flush=True)
    print(f"{done} written, {failed} failed, {len(pictures) - done - failed} already there -> {textures}")
    return 1 if failed else 0


def command_dump(arguments) -> int:
    game, out = Path(arguments.game).resolve(), Path(arguments.out).resolve()
    if not game.is_file():
        raise SystemExit(f"{game} is not the game's program")
    out.mkdir(parents=True, exist_ok=True)
    before = len(list(out.glob("*.png")))
    environment = dict(os.environ, DC_TEXTURE_DUMP=str(out))
    common = ["--data", arguments.data] if arguments.data else []
    if arguments.play:
        print("the game is running: every texture it loads is dumped; close it when you have seen enough")
        subprocess.run([str(game), *common], cwd=game.parent, env=environment, check=False)
    else:
        # A save of its own, so the dump never reads or writes yours, and no package's pictures are loaded.
        with tempfile.TemporaryDirectory(prefix="moonmod-texture-dump-") as scratch:
            for place in arguments.jump or PLACES:
                command = [str(game), *common, "--save", scratch, "--headless", "--jump", place, "--fast-load",
                           "--frames", str(arguments.frames)]
                result = subprocess.run(command, cwd=game.parent, env=environment, capture_output=True, check=False)
                count = len(list(out.glob("*.png")))
                print(f"{place}: {'ok' if result.returncode == 0 else f'exit {result.returncode}'}, {count} pictures so far",
                      flush=True)
    after = len(list(out.glob("*.png")))
    print(f"{after} pictures in {out} ({after - before} new)")
    if not arguments.play:
        print("the headless run sees only what those places load; run again with --play and walk through the rest")
    return 0 if after else 1


def command_check(arguments) -> int:
    package = Path(arguments.package)
    textures = package / "textures"
    if not textures.is_dir():
        raise SystemExit(f"{package} has no textures folder")
    dump = Path(arguments.dump) if arguments.dump else None
    problems = 0
    for file in sorted(textures.iterdir()):
        if file.suffix.lower() != ".png":
            continue
        name = file.stem.lower()
        with Image.open(file) as image:
            width, height = image.size
        if not NAME.match(name):
            print(f"{file.name}: never used, the name can only hold a-z, 0-9, _ and -")
            problems += 1
            continue
        if name in NOT_REPLACEABLE:
            print(f"{file.name}: never used, the game loads this picture another way")
            problems += 1
            continue
        if file.stat().st_size > 64 * 1024 * 1024 or width > 16384 or height > 16384 or width * height > 16 * 1024 * 1024:
            print(f"{file.name}: never used, {width}x{height} is over what the game reads (16 million pixels, 64 MiB)")
            problems += 1
            continue
        native = dump / f"{name}.png" if dump else None
        if native is None:
            print(f"{file.name}: {width}x{height}")
            continue
        if not native.is_file():
            print(f"{file.name}: {width}x{height}, no dumped texture of that name")
            problems += 1
            continue
        with Image.open(native) as image:
            native_width, native_height = image.size
        sizes = {where: kept_size(width, height, native_width, native_height, *limits)
                 for where, limits in LIMITS.items()}
        notes = []
        if width * native_height != height * native_width:
            notes.append("not the texture's shape, it will be stretched")
        if width < native_width or height < native_height:
            notes.append("smaller than the texture, it is enlarged to it")
        text = ", ".join(f"{where} {size[0]}x{size[1]}" for where, size in sizes.items())
        print(f"{file.name}: {width}x{height} for {native_width}x{native_height}; kept at {text}"
              + (f" ({'; '.join(notes)})" if notes else ""))
    return 1 if problems else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)

    dump = commands.add_parser("dump", help="write the game's textures as PNG files")
    dump.add_argument("--game", required=True, help="the game's program (darkcloud.exe)")
    dump.add_argument("--out", required=True, help="folder for the PNG files")
    dump.add_argument("--data", help="the game's data folder, if it is not where the game looks by itself")
    dump.add_argument("--play", action="store_true", help="start the game as usual and dump while you play")
    dump.add_argument("--jump", action="append", help=f"a place for the headless run (repeat it); default: {' '.join(PLACES)}")
    dump.add_argument("--frames", type=int, default=600, help="frames the headless run stays in each place")
    dump.set_defaults(run=command_dump)

    upscale = commands.add_parser("upscale", help="upscale dumped textures into a package")
    upscale.add_argument("--dump", required=True, help="folder of dumped PNG files")
    upscale.add_argument("--package", required=True, help="the package folder to write (<save>/mods/<id>)")
    upscale.add_argument("--model", help="an ESRGAN-style ONNX model; without it the pictures are only resized")
    upscale.add_argument("--scale", type=int, help="times the texture's size to keep (default: the model's, usually 4)")
    upscale.add_argument("--only", action="append", default=[], help="only textures matching this (e01*); repeat it")
    upscale.add_argument("--skip", action="append", default=[], help="leave out textures matching this; repeat it")
    upscale.add_argument("--edge", choices=["auto", "wrap", "reflect"], default="auto",
                         help="what lies past a picture's edge: its far side (it tiles), a mirror, or look and decide")
    upscale.add_argument("--alpha", choices=["model", "bicubic"], default="model",
                         help="how transparency is enlarged: through the model (crisp) or resized (soft)")
    upscale.add_argument("--provider", choices=list(PROVIDERS), default="dml", help="what runs the model")
    upscale.add_argument("--tile", type=int, default=256, help="texels a side the model is given at once")
    upscale.add_argument("--overlap", type=int, default=16, help="texels of context around each tile")
    upscale.add_argument("--redo", action="store_true", help="upscale pictures the package already has")
    upscale.add_argument("--id", help="the package's id (default: the package folder's name)")
    upscale.add_argument("--name", help="the package's name in the Mod Manager")
    upscale.add_argument("--author", default="", help="the package's author")
    upscale.set_defaults(run=command_upscale)

    check = commands.add_parser("check", help="list a package's pictures and the size the game keeps them at")
    check.add_argument("--package", required=True)
    check.add_argument("--dump", help="folder of dumped PNG files, to compare sizes against")
    check.set_defaults(run=command_check)

    arguments = parser.parse_args(argv)
    return arguments.run(arguments)


if __name__ == "__main__":
    sys.exit(main())
