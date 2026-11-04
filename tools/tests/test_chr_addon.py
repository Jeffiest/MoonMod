"""The Blender add-on's rules (tools/chr/blender/moonmod_chr_addon.py), on Opar's and Seda's files and broken copies.

    python tools/tests/test_chr_addon.py     # needs Blender as a module: pip install bpy (5.2)

Skips when bpy is not installed.
"""

import os
import sys
import unittest

try:
    import bpy
except ImportError:  # pragma: no cover
    bpy = None

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "chr", "blender"))


@unittest.skipIf(bpy is None, "Blender's bpy module is not installed")
class AddonRules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import moonmod_chr_addon
        cls.addon = moonmod_chr_addon
        moonmod_chr_addon.register()

    @classmethod
    def tearDownClass(cls):
        cls.addon.unregister()

    def open(self, name):
        bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "art", name, name + ".blend"))

    def errors(self, **kw):
        return [t for level, t in self.addon.check_character(**kw) if level == "error"]

    def test_opar_and_seda_pass(self):
        for name in ("opar", "seda"):
            self.open(name)
            self.assertEqual(self.errors(), [], name)
            self.assertEqual(self.addon.pack_name(bpy.context.scene), {"opar": "c07d", "seda": "c08d"}[name])

    def test_a_bone_that_is_not_a_chain_joint(self):
        self.open("seda")
        skin = bpy.data.objects["skin"]
        skin.vertex_groups.new(name="kao").add([0], 0.5, "REPLACE")
        self.assertTrue(any("aren't chain joints" in e and "kao" in e for e in self.errors()))

    def test_too_many_weights_and_none(self):
        self.open("seda")
        skin = bpy.data.objects["skin"]
        for name in ("jnt1_1", "jnt2_1", "jnt11_1", "jnt12_1", "jnt8_1"):
            skin.vertex_groups[name].add([1], 0.2, "REPLACE")
        for g in skin.vertex_groups:
            g.remove([2])
        errors = self.errors()
        self.assertTrue(any("more than 4 weights" in e for e in errors))
        self.assertTrue(any("have no weight" in e for e in errors))

    def test_material_names(self):
        self.open("seda")
        skin = bpy.data.objects["skin"]
        skin.data.materials[0]["texture"] = "c08d01"
        skin.data.materials[1]["texture"] = "body"
        errors = self.errors()
        self.assertTrue(any("eye blink" in e for e in errors))
        self.assertTrue(any("Material" in e and "not named after" in e for e in errors))

    def test_picture_size(self):
        self.open("seda")
        art = os.path.join(ROOT, "art", "seda")
        tmp = os.path.join(art, "build", "addon-test")
        os.makedirs(os.path.join(tmp, "textures"), exist_ok=True)
        img = bpy.data.images.new("big", 512, 512)
        img.filepath_raw = os.path.join(tmp, "textures", "c08d02.png")
        img.file_format = "PNG"
        img.save()
        self.assertTrue(any("512 x 512" in e for e in self.errors(art=tmp)))

    def test_no_skin(self):
        self.open("seda")
        bpy.data.objects["skin"].name = "body"
        self.assertTrue(any("No mesh named skin" in e for e in self.errors()))


if __name__ == "__main__":
    unittest.main()
