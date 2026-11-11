"""Tests for tools/bb/template_facts.py, on made-up packs and glTF files (no game data)."""

import contextlib
import io
import json
import os
import struct
import sys
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "bb"))
sys.path.insert(0, os.path.join(REPO, "tools", "chr"))

import chrtool  # noqa: E402
import template_facts  # noqa: E402

CFG = b'MODEL "e99a.mds";\r\n\r\nKEY_START 100;\r\n'
MDS = bytes(range(10))

FLOAT, UBYTE, USHORT = 5126, 5121, 5123


def make_pack(members):
    """Members in the layout chrtool.pack_entries reads: name (64), offset, size, next (3 x int32), 4 zero bytes,
    then the data padded to 16; an 80-byte zero block ends the pack."""
    out = bytearray()
    for name, data in members:
        size = len(data)
        padded = (size + 15) // 16 * 16
        out += name.encode("latin1").ljust(64, b"\0")
        out += struct.pack("<iii", 80, size, 80 + padded)
        out += b"\0" * 4
        out += data
        out += b"\0" * (padded - size)
    out += b"\0" * 80
    return bytes(out)


def make_png(width, height):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IEND", b"")


def make_gltf(folder, skinned=True):
    """A glTF named e99a.gltf with its e99a.bin and textures/skin01.png, written into folder. With skinned=False
    the skinned primitive has no JOINTS_0/WEIGHTS_0 and the body node has no skin, as a dc2tk export without
    skin weights would."""
    blob = bytearray()
    accessors, views = [], []

    def put(raw, comp, kind, count, bounds=None):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)})
        blob.extend(raw)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": count, "type": kind}
        if bounds:
            acc["min"], acc["max"] = bounds
        accessors.append(acc)
        return len(accessors) - 1

    pos_skin = put(struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 2, 0), FLOAT, "VEC3", 3, ([0, 0, 0], [1, 2, 0]))
    idx = put(struct.pack("<3H", 0, 1, 2), USHORT, "SCALAR", 3)
    joints = put(bytes([0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]), UBYTE, "VEC4", 3)
    weights = put(struct.pack("<12f", 1, 0, 0, 0, 0.5, 0.5, 0, 0, 1, 0, 0, 0), FLOAT, "VEC4", 3)
    pos_plain = put(struct.pack("<9f", 0, 0, 1, 1, 0, 1, 0, 1, 1), FLOAT, "VEC3", 3, ([0, 0, 1], [1, 1, 1]))
    anim_in = put(struct.pack("<2f", 0.0, 1.5), FLOAT, "SCALAR", 2, ([0.0], [1.5]))
    anim_out = put(struct.pack("<6f", 0, 0, 0, 0, 1, 0), FLOAT, "VEC3", 2)

    doc = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [
            {"name": "root", "children": [1, 3]},
            {"name": "hip", "translation": [0, 1, 0], "children": [2]},
            {"name": "arm", "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0.5, 0, 0, 1]},
            {"name": "body", "mesh": 0, "skin": 0},
        ],
        "skins": [{"joints": [1, 2]}],
        "meshes": [{"name": "body", "primitives": [
            {"attributes": {"POSITION": pos_skin, "JOINTS_0": joints, "WEIGHTS_0": weights},
             "indices": idx, "material": 0},
            {"attributes": {"POSITION": pos_plain}},
        ]}],
        "materials": [{"name": "skin01", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
        "textures": [{"source": 0}],
        "images": [{"uri": "textures/skin01.png"}],
        "animations": [{
            "name": "key100",
            "channels": [{"sampler": 0, "target": {"node": 1, "path": "translation"}}],
            "samplers": [{"input": anim_in, "output": anim_out, "interpolation": "LINEAR"}],
        }],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"uri": "e99a.bin", "byteLength": len(blob)}],
    }
    if not skinned:
        del doc["skins"]
        del doc["nodes"][3]["skin"]
        for key in ("JOINTS_0", "WEIGHTS_0"):
            del doc["meshes"][0]["primitives"][0]["attributes"][key]
    os.makedirs(os.path.join(folder, "textures"), exist_ok=True)
    with open(os.path.join(folder, "e99a.gltf"), "w", encoding="utf-8") as f:
        json.dump(doc, f)
    with open(os.path.join(folder, "e99a.bin"), "wb") as f:
        f.write(bytes(blob))
    with open(os.path.join(folder, "textures", "skin01.png"), "wb") as f:
        f.write(make_png(8, 4))


class TemplateFactsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = self.tmp.name
        self.pack = os.path.join(root, "e99a.chr")
        self.folder = os.path.join(root, "e99a")
        pack_bytes = make_pack([("info.cfg", CFG), ("e99a.mds", MDS)])
        with open(self.pack, "wb") as f:
            f.write(pack_bytes)
        make_gltf(self.folder)
        self.pack_bytes = pack_bytes

    def test_made_up_pack_reads_as_two_members(self):
        entries = chrtool.pack_entries(self.pack_bytes)
        self.assertEqual([(n, s) for n, _, _, s in entries], [("info.cfg", len(CFG)), ("e99a.mds", len(MDS))])

    def test_facts_sections(self):
        text = template_facts.facts(self.pack, self.folder)
        lines = text.split("\n")
        headings = [l for l in lines if l.startswith("== ")]
        self.assertEqual(headings, [
            "== pack e99a.chr: 2 members, %d bytes" % (len(CFG) + len(MDS)),
            "== cfg info.cfg",
            "== nodes: 4",
            "== skins: 1",
            "== meshes: 2",
            "== materials: 1",
            "== textures: 1",
            "== animations: 1",
        ])
        self.assertIn("info.cfg  %d" % len(CFG), lines)
        self.assertIn("e99a.mds  %d" % len(MDS), lines)

    def test_cfg_section(self):
        lines = template_facts.facts(self.pack, self.folder).split("\n")
        start = lines.index("== cfg info.cfg") + 1
        end = start
        while end < len(lines) and not lines[end].startswith("== "):
            end += 1
        section = lines[start:end]
        self.assertIn('  MODEL "e99a.mds";', section)
        self.assertIn("  KEY_START 100;", section)
        self.assertNotIn("", section)
        self.assertNotIn("  ", section)

    def test_node_tree(self):
        lines = template_facts.facts(self.pack, self.folder).split("\n")
        self.assertIn("root", lines)
        self.assertIn("  hip t=(0.000, 1.000, 0.000)", lines)
        self.assertIn("    arm t=(0.500, 0.000, 0.000)", lines)
        self.assertIn("  body mesh=body skin", lines)

    def test_skins(self):
        lines = template_facts.facts(self.pack, self.folder).split("\n")
        self.assertIn("skin 0: 2 joints: hip, arm", lines)

    def test_meshes(self):
        lines = template_facts.facts(self.pack, self.folder).split("\n")
        skinned = [l for l in lines if l.startswith("body [0]:")]
        plain = [l for l in lines if l.startswith("body [1]:")]
        self.assertEqual(len(skinned), 1)
        self.assertEqual(len(plain), 1)
        self.assertIn("3 vertices, 1 triangles", skinned[0])
        self.assertIn("skinned=yes", skinned[0])
        self.assertIn("max joints per vertex=2", skinned[0])
        self.assertIn("material=skin01", skinned[0])
        self.assertIn("skinned=no", plain[0])
        self.assertIn("material=-", plain[0])
        self.assertIn("total: 6 vertices, 2 triangles", lines)

    def test_materials_and_textures(self):
        lines = template_facts.facts(self.pack, self.folder).split("\n")
        self.assertIn("skin01: image=textures/skin01.png", lines)
        self.assertIn("skin01.png: 8 x 4", lines)

    def test_animations(self):
        lines = template_facts.facts(self.pack, self.folder).split("\n")
        self.assertIn("key100: 1 channels, 1.500 s", lines)

    def test_missing_texture_folder_counts_zero(self):
        empty = os.path.join(self.tmp.name, "bare")
        make_gltf(empty)
        os.rename(os.path.join(empty, "textures"), os.path.join(empty, "gone"))
        lines = template_facts.facts(self.pack, empty).split("\n")
        self.assertIn("== textures: 0", lines)

    def test_main_exit_codes(self):
        quiet = io.StringIO()
        with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(template_facts.main([]), 2)
            self.assertEqual(template_facts.main([os.path.join(self.tmp.name, "nope.chr"), self.folder]), 1)
            bare = os.path.join(self.tmp.name, "nogltf")
            os.makedirs(bare)
            self.assertEqual(template_facts.main([self.pack, bare]), 1)
            self.assertEqual(template_facts.main([self.pack, self.folder]), 0)
        self.assertIn("== nodes: 4", quiet.getvalue())

    def _facts_with_cfg(self, cfg, skinned):
        """facts() for a pack whose info.cfg is `cfg`, over a glTF that is skinned or not."""
        self._n = getattr(self, "_n", 0) + 1
        pack = os.path.join(self.tmp.name, "case%d.chr" % self._n)
        folder = os.path.join(self.tmp.name, "case%d" % self._n)
        with open(pack, "wb") as f:
            f.write(make_pack([("info.cfg", cfg), ("e99a.mds", MDS)]))
        make_gltf(folder, skinned=skinned)
        return template_facts.facts(pack, folder)

    def test_warning_when_cfg_skins_a_mesh_the_export_cannot_skin(self):
        cfg = b'VERTEX_ANIME 1\r\nALLOC_DBUFF "body"\r\nALLOC_DBUFF "cape"\r\nMODEL "e99a.mds"\r\n'
        lines = self._facts_with_cfg(cfg, skinned=False).split("\n")
        warnings = [l for l in lines if l.startswith("warning:")]
        self.assertEqual(len(warnings), 1)
        self.assertIn("body, cape", warnings[0])
        self.assertIn("(VERTEX_ANIME, ALLOC_DBUFF)", warnings[0])
        total = lines.index(next(l for l in lines if l.startswith("total:")))
        self.assertEqual(lines[total + 1], warnings[0])

    def test_warning_with_semicolons(self):
        cfg = b'VERTEX_ANIME 1;\r\nALLOC_DBUFF "body";\r\nALLOC_DBUFF "cape";\r\nMODEL "e99a.mds";\r\n'
        lines = self._facts_with_cfg(cfg, skinned=False).split("\n")
        warnings = [l for l in lines if l.startswith("warning:")]
        self.assertEqual(len(warnings), 1)
        self.assertIn("body, cape", warnings[0])

    def test_no_warning_when_export_is_skinned(self):
        cfg = b'VERTEX_ANIME 1\r\nALLOC_DBUFF "body"\r\n'
        lines = self._facts_with_cfg(cfg, skinned=True).split("\n")
        self.assertFalse([l for l in lines if l.startswith("warning:")])

    def test_no_warning_when_vertex_anime_is_zero(self):
        cfg = b'VERTEX_ANIME 0\r\nALLOC_DBUFF "body"\r\n'
        lines = self._facts_with_cfg(cfg, skinned=False).split("\n")
        self.assertFalse([l for l in lines if l.startswith("warning:")])

    def test_no_warning_when_only_a_commented_alloc(self):
        cfg = b'// ALLOC_DBUFF "ghost"\r\nVERTEX_ANIME 1\r\n'
        lines = self._facts_with_cfg(cfg, skinned=False).split("\n")
        self.assertFalse([l for l in lines if l.startswith("warning:")])


if __name__ == "__main__":
    unittest.main()
