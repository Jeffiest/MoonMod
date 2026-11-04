from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import hashlib  # noqa: E402
import zipfile  # noqa: E402

import moonfactory  # noqa: E402
from moonfactory import create_package  # noqa: E402


class MoonFactoryCliTests(unittest.TestCase):
    def test_creates_cross_game_starter_with_requested_identity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="moonfactory-new-") as temporary:
            destination = create_package(
                "test.author-first-mod", Path(temporary) / "FirstMod", target="both", name="First Mod"
            )
            manifest = json.loads((destination / "mod.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["id"], "test.author-first-mod")
            self.assertEqual(manifest["name"], "First Mod")
            self.assertEqual(manifest["games"], ["chronicle", "chronicle-two"])
            self.assertTrue((destination / "main.lua").is_file())

    def test_can_target_one_game_and_refuses_to_overwrite(self) -> None:
        with tempfile.TemporaryDirectory(prefix="moonfactory-new-") as temporary:
            destination = Path(temporary) / "existing"
            destination.mkdir()
            sentinel = destination / "keep.txt"
            sentinel.write_text("preserve", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                create_package("test.author-first-mod", destination, target="chronicle-two")
            self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve")

            package = create_package(
                "test.author-second-mod", Path(temporary) / "SecondMod", target="chronicle-two"
            )
            manifest = json.loads((package / "mod.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["games"], ["chronicle-two"])


def _mod(root: Path, mod_id: str, version: str, deps=None, extra: str = "") -> Path:
    folder = root / mod_id
    folder.mkdir(parents=True)
    manifest = {"schema_version": 1, "id": mod_id, "name": mod_id.title(), "version": version, "author": "test",
                "description": "A test mod about moons " + extra, "framework_api": 1, "games": ["chronicle"],
                "entry": "main.lua", "permissions": []}
    if deps:
        manifest["dependencies"] = deps
    (folder / "mod.json").write_text(json.dumps(manifest), encoding="utf-8")
    (folder / "main.lua").write_text("moonmod.log('info', '%s %s')\n" % (mod_id, version), encoding="utf-8")
    (folder / "resources").mkdir()
    (folder / "resources" / "a.txt").write_text("x" * 100, encoding="utf-8")
    return folder


class ModBrowserTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="moonfactory-index-")
        self.root = Path(self.tmp.name)
        self.source = self.root / "source"
        _mod(self.source, "test.base", "1.0.0")
        _mod(self.source, "test.addon", "2.1.0", deps=["test.base"], extra="frogs")
        self.dist = self.root / "dist"
        self.index = moonfactory.build_index(self.source, self.dist, "https://example.invalid/mods/")
        # serve the zips from the folder: the catalogue's urls point at local files
        data = json.loads(self.index.read_text(encoding="utf-8"))
        for m in data["mods"]:
            m["url"] = Path(m["url"]).name
        self.index.write_text(json.dumps(data), encoding="utf-8")
        self.game = self.root / "game" / "mods"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_index_lists_every_mod_with_checksums_and_stable_archives(self) -> None:
        mods = {m["id"]: m for m in json.loads(self.index.read_text(encoding="utf-8"))["mods"]}
        self.assertEqual(set(mods), {"test.base", "test.addon"})
        archive = self.dist / "test.addon-2.1.0.zip"
        self.assertEqual(mods["test.addon"]["sha256"], hashlib.sha256(archive.read_bytes()).hexdigest())
        self.assertEqual(mods["test.addon"]["dependencies"], ["test.base"])
        before = archive.read_bytes()
        moonfactory.pack_mod(self.source / "test.addon", self.root / "again")
        self.assertEqual((self.root / "again" / "test.addon-2.1.0.zip").read_bytes(), before)
        with zipfile.ZipFile(archive) as z:
            self.assertIn("test.addon/resources/a.txt", z.namelist())

    def test_search_matches_words_in_names_and_descriptions(self) -> None:
        mods = moonfactory.load_index(str(self.index))
        self.assertEqual([m["id"] for m in moonfactory.search(mods, ["frogs"])], ["test.addon"])
        self.assertEqual(len(moonfactory.search(mods, ["moons"])), 2)
        self.assertEqual(moonfactory.search(mods, ["dragons"]), [])

    def test_install_brings_its_dependencies_first_and_leaves_installed_mods(self) -> None:
        done = moonfactory.install("test.addon", str(self.index), self.game)
        self.assertEqual(done, ["test.base", "test.addon"])
        self.assertTrue((self.game / "test.addon" / "main.lua").is_file())
        self.assertTrue((self.game / "test.base" / "resources" / "a.txt").is_file())
        self.assertEqual(moonfactory.install("test.addon", str(self.index), self.game), [])
        self.assertEqual(moonfactory.updates(self.game, str(self.index)), [("test.addon", "2.1.0", None), ("test.base", "1.0.0", None)])

    def test_upgrade_replaces_an_older_mod_and_keeps_the_previous(self) -> None:
        moonfactory.install("test.base", str(self.index), self.game)
        (self.game / "test.base" / "mine.txt").write_text("kept in previous", encoding="utf-8")
        shutil_source = self.root / "source2"
        _mod(shutil_source, "test.base", "1.2.0")
        moonfactory.build_index(shutil_source, self.dist, "https://example.invalid/mods/")
        data = json.loads((self.dist / "index.json").read_text(encoding="utf-8"))
        for m in data["mods"]:
            m["url"] = Path(m["url"]).name
        (self.dist / "index.json").write_text(json.dumps(data), encoding="utf-8")
        self.assertEqual(moonfactory.updates(self.game, str(self.index)), [("test.base", "1.0.0", "1.2.0")])
        self.assertEqual(moonfactory.install("test.base", str(self.index), self.game), [])
        self.assertEqual(moonfactory.install("test.base", str(self.index), self.game, upgrade=True), ["test.base"])
        self.assertEqual(json.loads((self.game / "test.base" / "mod.json").read_text())["version"], "1.2.0")
        self.assertTrue((self.game / "test.base.previous" / "mine.txt").is_file())

    def test_a_tampered_download_is_refused(self) -> None:
        archive = self.dist / "test.base-1.0.0.zip"
        archive.write_bytes(archive.read_bytes() + b"tampered")
        with self.assertRaises(ValueError):
            moonfactory.install("test.base", str(self.index), self.game)
        self.assertFalse((self.game / "test.base").exists())

    def test_an_archive_reaching_outside_its_folder_is_refused(self) -> None:
        bad = self.dist / "bad.zip"
        with zipfile.ZipFile(bad, "w") as z:
            z.writestr("test.bad/mod.json", json.dumps({"id": "test.bad", "version": "1"}))
            z.writestr("test.bad/../escape.txt", "outside")
        data = json.loads(self.index.read_text(encoding="utf-8"))
        data["mods"].append({"id": "test.bad", "version": "1", "url": "bad.zip",
                             "sha256": hashlib.sha256(bad.read_bytes()).hexdigest(), "dependencies": []})
        self.index.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaises(ValueError):
            moonfactory.install("test.bad", str(self.index), self.game)
        self.assertFalse((self.game.parent / "escape.txt").exists())
        self.assertFalse((self.game / "test.bad").exists())

    def test_unknown_mods_and_bad_catalogues_are_errors(self) -> None:
        with self.assertRaises(KeyError):
            moonfactory.install("test.nothing", str(self.index), self.game)
        junk = self.root / "junk.json"
        junk.write_text(json.dumps({"mods": "no"}), encoding="utf-8")
        with self.assertRaises(ValueError):
            moonfactory.load_index(str(junk))

    def test_versions_compare_as_numbers(self) -> None:
        self.assertGreater(moonfactory.version_key("1.10.0"), moonfactory.version_key("1.9.2"))


if __name__ == "__main__":
    unittest.main()
