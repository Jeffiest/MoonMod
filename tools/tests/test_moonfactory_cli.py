from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
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


if __name__ == "__main__":
    unittest.main()
