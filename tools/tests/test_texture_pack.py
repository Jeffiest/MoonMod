"""The texture package tool (tools/textures/texture_pack.py): sizes, names, the tiled upscale, the package it writes.

    python tools/tests/test_texture_pack.py

Skips when numpy or Pillow is not installed. No game and no model are needed.
"""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:  # pragma: no cover
    np = None

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "textures"))


def run(tool, *arguments):
    """The tool's exit code and what it printed."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = tool.main(list(arguments))
    return code, out.getvalue()


@unittest.skipIf(np is None, "numpy and Pillow are not installed")
class TexturePack(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import texture_pack
        cls.tool = texture_pack

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)
        self.dump = self.root / "dump"
        self.dump.mkdir()

    def tearDown(self):
        self.folder.cleanup()

    def picture(self, name, width, height, alpha=False, seed=1):
        values = np.random.default_rng(seed).integers(0, 256, (height, width, 4 if alpha else 3), dtype=np.uint8)
        Image.fromarray(values).save(self.dump / name)

    def test_the_size_the_engine_keeps(self):
        kept = self.tool.kept_size
        # The same cases as ModTexture.SizeRule in the engine's tests.
        self.assertEqual(kept(256, 256, 64, 64, 4096, 8), (256, 256))
        self.assertEqual(kept(1024, 1024, 64, 64, 4096, 8), (512, 512))      # over 8 times: halved
        self.assertEqual(kept(8192, 8192, 2048, 2048, 4096, 8), (4096, 4096))  # over the longest side
        self.assertEqual(kept(32, 32, 64, 64, 4096, 8), (64, 64))            # never under the texture
        self.assertEqual(kept(256, 64, 64, 64, 4096, 2), (128, 64))          # both sides halve together
        self.assertEqual(kept(512, 512, 128, 128, 2048, 2), (256, 256))      # the browser's limits
        self.assertEqual(kept(512, 512, 128, 128, 4096, 1), (128, 128))      # scale 1: the old behaviour

    def test_which_dumped_pictures_are_taken(self):
        for name in ("e01t03.png", "E01T04.png", "bad name.png", "stayframe.png", "c01d01.png"):
            self.picture(name, 8, 8)
        chosen, left_out = self.tool.dumped_pictures(self.dump, [], [])
        self.assertEqual([name for name, _ in chosen], ["c01d01", "e01t03", "e01t04"])
        self.assertEqual(sorted(file.name for file, _ in left_out), ["bad name.png", "stayframe.png"])
        chosen, _ = self.tool.dumped_pictures(self.dump, ["e01*"], ["*04"])
        self.assertEqual([name for name, _ in chosen], ["e01t03"])

    def test_upscale_writes_a_package(self):
        self.picture("e01t03.png", 32, 16)
        self.picture("c01d01.png", 16, 16, alpha=True)
        package = self.root / "mods" / "me.hires"
        code, text = run(self.tool, "upscale", "--dump", str(self.dump), "--package", str(package))
        self.assertEqual(code, 0, text)
        with Image.open(package / "textures" / "e01t03.png") as image:
            self.assertEqual((image.size, image.mode), ((128, 64), "RGB"))
        with Image.open(package / "textures" / "c01d01.png") as image:
            self.assertEqual((image.size, image.mode), ((64, 64), "RGBA"))
        manifest = json.loads((package / "mod.json").read_text(encoding="utf-8"))
        self.assertEqual((manifest["id"], manifest["entry"], manifest["coop"]), ("me.hires", "main.lua", "local"))
        self.assertTrue((package / "main.lua").is_file())

        # A second run leaves finished pictures and the package's own files alone.
        (package / "mod.json").write_text(json.dumps(dict(manifest, name="Mine")), encoding="utf-8")
        code, text = run(self.tool, "upscale", "--dump", str(self.dump), "--package", str(package))
        self.assertIn("0 written, 0 failed, 2 already there", text)
        self.assertEqual(json.loads((package / "mod.json").read_text(encoding="utf-8"))["name"], "Mine")
        code, text = run(self.tool, "upscale", "--dump", str(self.dump), "--package", str(package), "--redo",
                         "--scale", "2")
        self.assertIn("2 written", text)
        with Image.open(package / "textures" / "e01t03.png") as image:
            self.assertEqual(image.size, (64, 32))

    def test_a_package_id_must_be_one(self):
        self.picture("e01t03.png", 8, 8)
        with self.assertRaises(SystemExit):
            run(self.tool, "upscale", "--dump", str(self.dump), "--package", str(self.root / "My Pack"))

    def test_tiles_join_without_a_seam(self):
        """A model that only repeats each texel: cut in tiles and cross-faded, the picture must come back whole."""
        tool = self.tool

        class Repeat(tool.OnnxModel):
            def __init__(self):
                self.scale, self.tile, self.overlap, self.name = 2, 8, 2, "repeat"

            def _run(self, rgb):
                return np.repeat(np.repeat(rgb, 2, axis=0), 2, axis=1).astype(np.float32)

        rgb = np.random.default_rng(3).random((21, 30, 3), dtype=np.float32)
        whole = np.repeat(np.repeat(rgb, 2, axis=0), 2, axis=1)
        for wrap in (False, True):
            large = Repeat().upscale(rgb, wrap, wrap)
            self.assertEqual(large.shape, whole.shape)
            self.assertLess(float(np.abs(large - whole).max()), 1e-5)

    def test_a_tiling_picture_is_told_from_one_that_is_not(self):
        y, x = np.mgrid[0:32, 0:32]
        tiling = np.dstack([127 + 100 * np.sin(2 * np.pi * x / 32)] * 3 + [np.full((32, 32), 255)]).astype(np.uint8)
        slope = np.dstack([x * 8] * 3 + [np.full((32, 32), 255)]).astype(np.uint8)
        self.assertTrue(self.tool.repeats(tiling, 1))
        self.assertFalse(self.tool.repeats(slope, 1))
        self.assertTrue(self.tool.repeats(slope, 0))  # the same from top to bottom

    def test_hidden_texels_take_their_neighbours_colour(self):
        rgb = np.zeros((8, 8, 3), np.float32)
        visible = np.zeros((8, 8), bool)
        rgb[3:5, 3:5] = (1.0, 0.5, 0.25)
        visible[3:5, 3:5] = True
        filled = self.tool.bleed(rgb, visible)
        self.assertTrue(np.allclose(filled, (1.0, 0.5, 0.25), atol=1e-5))

    def test_pure_black_stays_where_it_was(self):
        """The game draws some pictures without transparency with pure black as see-through."""
        tool = self.tool

        class Darken(tool.OnnxModel):
            """Repeats each texel and takes a little off, so dark texels land on black and black stays black."""
            def __init__(self):
                self.scale, self.tile, self.overlap, self.name = 2, 8, 2, "darken"

            def _run(self, rgb):
                return np.repeat(np.repeat(rgb, 2, axis=0), 2, axis=1).astype(np.float32) - 2.0 / 255.0

        # A font like the debug one: a backdrop of (1, 1, 1), white letters, and no black anywhere.
        font = np.full((16, 16, 3), 1, np.uint8)
        font[4:12, 6:10] = 255
        large = np.asarray(tool.upscale_picture(Darken(), Image.fromarray(font)))
        self.assertEqual(large.shape, (32, 32, 3))
        self.assertFalse((large == 0).all(axis=2).any())

        # A picture whose black is its cut-out: the cut-out stays pure black, and nothing else turns into it.
        cut = np.full((16, 16, 3), 2, np.uint8)
        cut[:, :8] = 0
        large = np.asarray(tool.upscale_picture(Darken(), Image.fromarray(cut), edge="reflect"))
        black = (large == 0).all(axis=2)
        self.assertTrue(black[:, :16].all())
        self.assertFalse(black[:, 16:].any())

    def test_check_reads_a_package(self):
        self.picture("e01t03.png", 16, 16)
        package = self.root / "mods" / "me.hires"
        run(self.tool, "upscale", "--dump", str(self.dump), "--package", str(package))
        code, text = run(self.tool, "check", "--package", str(package), "--dump", str(self.dump))
        self.assertEqual(code, 0, text)
        self.assertIn("e01t03.png: 64x64 for 16x16; kept at desktop 64x64, browser 32x32", text)

        textures = package / "textures"
        Image.new("RGB", (8, 8)).save(textures / "Bad Name.png")
        Image.new("RGB", (8, 8)).save(textures / "stayframe.png")
        Image.new("RGB", (8, 8)).save(textures / "nothing.png")
        Image.new("RGB", (64, 32)).save(textures / "e01t03.png")
        code, text = run(self.tool, "check", "--package", str(package), "--dump", str(self.dump))
        self.assertEqual(code, 1)
        self.assertIn("Bad Name.png: never used", text)
        self.assertIn("stayframe.png: never used", text)
        self.assertIn("nothing.png: 8x8, no dumped texture of that name", text)
        self.assertIn("it will be stretched", text)

    def test_a_name_with_more_than_one_picture_is_kept_apart(self):
        """Every dungeon has its own "frame": one package picture would land on all of them."""
        places = {}
        for index, place in enumerate(("dungeon:0", "dungeon:1", "title")):
            places[place] = self.root / f"place{index}"
            places[place].mkdir()
        for place, seed in (("dungeon:0", 1), ("dungeon:1", 2)):
            values = np.random.default_rng(seed).integers(0, 256, (8, 8, 3), dtype=np.uint8)
            Image.fromarray(values).save(places[place] / "frame.png")
            Image.new("RGB", (8, 8), (9, 9, 9)).save(places[place] / "gaiji.png")   # the same in both
        Image.new("RGB", (8, 8), (9, 9, 9)).save(places["title"] / "gaiji.png")
        Image.new("RGB", (8, 8)).save(places["title"] / "logo.png")
        self.picture("frame.png", 8, 8, seed=3)                                    # from an earlier dump

        shared = self.tool.merge_places(places, self.dump)
        self.assertEqual(shared, {"frame": ["dungeon:0", "dungeon:1"]})
        self.assertEqual(sorted(file.name for file in self.dump.glob("*.png")), ["gaiji.png", "logo.png"])
        self.assertEqual(sorted(file.name for file in (self.dump / "shared-names").iterdir()),
                         ["frame.dungeon_0.png", "frame.dungeon_1.png", "frame.earlier.png"])

        # A dump made by playing puts the name back; it is still left out, and check names a package that has it.
        self.picture("frame.png", 8, 8, seed=4)
        chosen, left_out = self.tool.dumped_pictures(self.dump, [], [])
        self.assertEqual([name for name, _ in chosen], ["gaiji", "logo"])
        self.assertEqual([file.name for file, _ in left_out], ["frame.png"])
        package = self.root / "mods" / "me.hires"
        run(self.tool, "upscale", "--dump", str(self.dump), "--package", str(package))
        self.assertFalse((package / "textures" / "frame.png").exists())
        Image.new("RGB", (32, 32)).save(package / "textures" / "frame.png")
        code, text = run(self.tool, "check", "--package", str(package), "--dump", str(self.dump))
        self.assertEqual(code, 1)
        self.assertIn("frame.png: 32x32, goes on 3 different pictures of that name", text)


if __name__ == "__main__":
    unittest.main()
