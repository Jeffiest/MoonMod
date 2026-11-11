"""Tests for tools/bb/model_gltf.py: a small made-up model.json is converted and the .gltf and .bin read back from disk."""

import io
import json
import os
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "bb"))

import model_gltf  # noqa: E402

IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
# mid: a 90 degree turn about Z, then a move of (0, 1, 0). Row-vector convention: translation in elements 12..14.
WORLD_MID = [0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1]
# tip: world translation (0.5, 2, 0.25), no rotation. Its local (relative to mid) is worked out by hand.
WORLD_TIP = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0.5, 2, 0.25, 1]
LOCAL_TIP = [0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, -0.5, 0.25, 1]

POSITIONS = [0.2, 0, 0, 1.5, 0, 0, 0.5, 1, 0.3, -0.75, 0.5, -0.2]
NORMALS = [0.6, 0, 0.8, 0, 1, 0, 0.6, 0, -0.8, 0, 0, 1]
UVS = [0, 0, 1, 0, 0.5, 1, 0.25, 0.75]
JOINTS = [0, 1, 0, 0, 1, 2, 0, 0, 2, 1, 0, 0, 2, 1, 0, 0]
# Vertex 0 sums to 0.75, vertex 3 to 0.6, vertex 2 has no weight at all.
WEIGHTS = [0.5, 0.25, 0, 0, 0.2, 0.3, 0.4, 0.1, 0, 0, 0, 0, 0.3, 0.3, 0, 0]
TRIANGLES = [0, 1, 2, 0, 2, 3]

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
CODES = {5126: "f", 5123: "H", 5125: "I"}


def make_model():
    return {
        "format": "moonmod-bb-model",
        "version": 1,
        "source": "test.flver",
        "flver_version": 0x20010,
        "nodes": [
            {"name": "root", "parent": -1, "translation": [0, 0, 0], "rotation": [0, 0, 0], "scale": [1, 1, 1],
             "world": IDENTITY},
            {"name": "mid", "parent": 0, "translation": [0, 1, 0], "rotation": [0, 0, 1.5707963], "scale": [1, 1, 1],
             "world": WORLD_MID},
            {"name": "tip", "parent": 1, "translation": [1, -0.5, 0.25], "rotation": [0, 0, 0], "scale": [1, 1, 1],
             "world": WORLD_TIP},
        ],
        "materials": [{"name": "mat", "mtd": "N.mtd",
                       "textures": [{"param": "g_Diffuse", "path": "a.tif", "file": "a"}]}],
        "meshes": [{
            "material": 0, "node": 0, "dynamic": True, "has_bone_indices": True,
            "vertex_count": 4, "triangle_count": 2,
            "positions": POSITIONS, "normals": NORMALS, "uvs": UVS, "joints": JOINTS, "weights": WEIGHTS,
            "triangles": TRIANGLES,
        }],
        "textures": [],
        "texture_errors": [],
    }


def mul(a, b):
    return [sum(a[i * 4 + k] * b[k * 4 + j] for k in range(4)) for i in range(4) for j in range(4)]


def mirrored(m, axis):
    def s(i):
        return -1.0 if i == axis else 1.0
    return [m[i * 4 + j] * s(i) * s(j) for i in range(4) for j in range(4)]


def rows(values, width):
    return [tuple(values[i:i + width]) for i in range(0, len(values), width)]


class BbModelTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = tmp.name
        self.folder = os.path.join(self.tmp, "dump")
        os.makedirs(self.folder)
        self.write_model(make_model())

    def write_model(self, model, folder=None):
        folder = folder or self.folder
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "model.json"), "w", encoding="utf-8") as f:
            json.dump(model, f)
        return folder

    def run_main(self, *args):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return model_gltf.main(list(args))

    def export(self, mirror):
        """Converts the test model with --mirror <mirror> and reads the .gltf and .bin back from disk."""
        out = os.path.join(self.tmp, "out-" + mirror, "model.gltf")
        self.assertEqual(self.run_main(self.folder, "-o", out, "--mirror", mirror), 0)
        with open(out, encoding="utf-8") as f:
            gltf = json.load(f)
        with open(os.path.join(os.path.dirname(out), gltf["buffers"][0]["uri"]), "rb") as f:
            data = f.read()
        return gltf, data

    def accessor(self, gltf, data, index):
        acc = gltf["accessors"][index]
        view = gltf["bufferViews"][acc["bufferView"]]
        fmt = "<%d%s" % (acc["count"] * COMPONENTS[acc["type"]], CODES[acc["componentType"]])
        offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        return struct.unpack_from(fmt, data, offset)

    def primitive_values(self, gltf, data, name):
        prim = gltf["meshes"][0]["primitives"][0]
        return self.accessor(gltf, data, prim["attributes"][name])

    def indices(self, gltf, data):
        return list(self.accessor(gltf, data, gltf["meshes"][0]["primitives"][0]["indices"]))

    def assertClose(self, got, want, tol=1e-6):
        self.assertEqual(len(got), len(want))
        for g, w in zip(got, want):
            self.assertAlmostEqual(g, w, delta=tol)

    def test_counts(self):
        gltf, data = self.export("x")
        prim = gltf["meshes"][0]["primitives"][0]
        for name in ("POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"):
            self.assertEqual(gltf["accessors"][prim["attributes"][name]]["count"], 4, name)
        self.assertEqual(gltf["accessors"][prim["indices"]]["count"], 6)
        self.assertEqual(len(gltf["nodes"]), 4)
        self.assertEqual(gltf["nodes"][3]["name"], "mesh0")
        self.assertEqual(gltf["nodes"][3]["mesh"], 0)
        self.assertEqual(gltf["nodes"][3]["skin"], 0)
        self.assertEqual(len(gltf["skins"][0]["joints"]), 3)
        self.assertNotIn("skeleton", gltf["skins"][0])
        self.assertEqual(gltf["scenes"][0]["nodes"], [0, 3])

    def test_mirror_none_keeps_input(self):
        gltf, data = self.export("none")
        positions = rows(self.primitive_values(gltf, data, "POSITION"), 3)
        self.assertClose([c for p in positions for c in p], POSITIONS)
        self.assertEqual(self.indices(gltf, data), TRIANGLES)

    def test_mirror_x(self):
        gltf, data = self.export("x")
        positions = rows(self.primitive_values(gltf, data, "POSITION"), 3)
        expected = [(-POSITIONS[3 * v], POSITIONS[3 * v + 1], POSITIONS[3 * v + 2]) for v in range(4)]
        self.assertClose([c for p in positions for c in p], [c for p in expected for c in p])
        normals = rows(self.primitive_values(gltf, data, "NORMAL"), 3)
        want_normals = [(-NORMALS[3 * v], NORMALS[3 * v + 1], NORMALS[3 * v + 2]) for v in range(4)]
        self.assertClose([c for n in normals for c in n], [c for n in want_normals for c in n])
        self.assertEqual(self.indices(gltf, data), [0, 2, 1, 0, 3, 2])

    def test_mirror_z(self):
        gltf, data = self.export("z")
        positions = rows(self.primitive_values(gltf, data, "POSITION"), 3)
        expected = [(POSITIONS[3 * v], POSITIONS[3 * v + 1], -POSITIONS[3 * v + 2]) for v in range(4)]
        self.assertClose([c for p in positions for c in p], [c for p in expected for c in p])
        self.assertEqual(self.indices(gltf, data), [0, 2, 1, 0, 3, 2])

    def test_local_matrices_and_inverse_binds(self):
        nodes_in = make_model()["nodes"]
        for mirror in ("none", "x", "z"):
            with self.subTest(mirror=mirror):
                gltf, data = self.export(mirror)
                axis = model_gltf.MIRROR_AXIS[mirror]
                ibm = rows(self.accessor(gltf, data, gltf["skins"][0]["inverseBindMatrices"]), 16)
                worlds = []
                for i, node in enumerate(gltf["nodes"][:3]):
                    local = node["matrix"]
                    parent = nodes_in[i]["parent"]
                    world = local if parent < 0 else mul(local, worlds[parent])
                    worlds.append(world)
                    want = nodes_in[i]["world"] if axis is None else mirrored(nodes_in[i]["world"], axis)
                    self.assertClose(world, want, 1e-5)
                    product = mul(list(ibm[i]), world)
                    self.assertClose(product, IDENTITY, 1e-5)
                if mirror == "none":
                    self.assertClose(gltf["nodes"][1]["matrix"], WORLD_MID, 1e-5)
                    self.assertClose(gltf["nodes"][2]["matrix"], LOCAL_TIP, 1e-5)

    def test_weights(self):
        gltf, data = self.export("x")
        weights = rows(self.primitive_values(gltf, data, "WEIGHTS_0"), 4)
        joints = rows(self.primitive_values(gltf, data, "JOINTS_0"), 4)
        for v, w in enumerate(weights):
            self.assertAlmostEqual(sum(w), 1.0, delta=1e-6, msg="vertex %d" % v)
        self.assertClose(weights[2], [1, 0, 0, 0])
        self.assertClose(weights[0], [0.5 / 0.75, 0.25 / 0.75, 0, 0])
        for v, (w, j) in enumerate(zip(weights, joints)):
            for k in range(4):
                if w[k] == 0:
                    self.assertEqual(j[k], 0, "vertex %d slot %d" % (v, k))

    def test_position_min_max(self):
        gltf, data = self.export("x")
        prim = gltf["meshes"][0]["primitives"][0]
        acc = gltf["accessors"][prim["attributes"]["POSITION"]]
        positions = rows(self.primitive_values(gltf, data, "POSITION"), 3)
        for axis in range(3):
            column = [p[axis] for p in positions]
            self.assertAlmostEqual(acc["min"][axis], min(column), delta=1e-6)
            self.assertAlmostEqual(acc["max"][axis], max(column), delta=1e-6)

    def test_buffer_layout(self):
        gltf, data = self.export("x")
        for view in gltf["bufferViews"]:
            self.assertEqual(view["byteOffset"] % 4, 0)
        self.assertEqual(gltf["buffers"][0]["byteLength"], len(data))
        self.assertEqual(len(data) % 4, 0)
        self.assertEqual(os.path.getsize(os.path.join(os.path.dirname(os.path.join(self.tmp, "out-x", "model.gltf")),
                                                      gltf["buffers"][0]["uri"])), len(data))

    def test_bad_models_raise_and_exit_1(self):
        def broken(name, edit):
            model = make_model()
            edit(model)
            return name, model

        cases = [
            broken("triangle", lambda m: m["meshes"][0].__setitem__("triangles", [0, 1, 2, 0, 2, 4])),
            broken("joint", lambda m: m["meshes"][0].__setitem__("joints", JOINTS[:-1] + [3])),
            broken("positions", lambda m: m["meshes"][0].__setitem__("positions", POSITIONS[:-1])),
            broken("format", lambda m: m.__setitem__("format", "something-else")),
        ]
        for name, model in cases:
            with self.subTest(case=name):
                folder = self.write_model(model, os.path.join(self.tmp, "bad-" + name))
                path = os.path.join(folder, "model.json")
                with self.assertRaises(ValueError) as ctx:
                    model_gltf.load_model(path)
                if name != "format":
                    self.assertIn("mesh 0", str(ctx.exception))
                self.assertEqual(self.run_main(folder, "-o", os.path.join(self.tmp, "bad-out", name + ".gltf")), 1)

    def test_main_writes_default_and_custom_paths(self):
        self.assertEqual(self.run_main(self.folder), 0)
        self.assertTrue(os.path.isfile(os.path.join(self.folder, "model.gltf")))
        self.assertTrue(os.path.isfile(os.path.join(self.folder, "model.bin")))

        target = os.path.join(self.tmp, "elsewhere", "run1.gltf")
        self.assertEqual(self.run_main(self.folder, "-o", target), 0)
        self.assertTrue(os.path.isfile(target))
        self.assertTrue(os.path.isfile(os.path.join(self.tmp, "elsewhere", "run1.bin")))
        with open(target, encoding="utf-8") as f:
            self.assertEqual(json.load(f)["buffers"][0]["uri"], "run1.bin")

    def test_main_usage_and_missing_folder(self):
        self.assertEqual(self.run_main(), 2)
        self.assertEqual(self.run_main(self.folder, "--mirror", "y"), 2)
        self.assertEqual(self.run_main(os.path.join(self.tmp, "nowhere")), 1)


if __name__ == "__main__":
    unittest.main()
