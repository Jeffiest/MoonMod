from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


class MoonFactoryExampleTests(unittest.TestCase):
    def test_first_steps_is_a_complete_cross_game_package(self) -> None:
        project = Path(__file__).resolve().parents[2]
        package = project / "examples" / "first-steps"
        manifest_path = package / "mod.json"
        entry_path = package / "main.lua"
        self.assertTrue(manifest_path.is_file())
        self.assertTrue(entry_path.is_file())

        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema_version"], 1)
        self.assertRegex(manifest["id"], re.compile(r"^[a-z0-9][a-z0-9._-]{2,63}$"))
        self.assertEqual(manifest["entry"], "main.lua")
        self.assertEqual(set(manifest["games"]), {"chronicle", "chronicle-two"})
        self.assertTrue({"content.register", "game.read", "game.write"}.issubset(manifest["permissions"]))

        script = entry_path.read_text(encoding="utf-8")
        for api in ("game.quests.register", "game.skills.register", "game.ui.register", "game.scene.entered"):
            self.assertIn(api, script)

    def test_weapon_quest_reward_is_a_cross_game_package(self) -> None:
        project = Path(__file__).resolve().parents[2]
        package = project / "examples" / "weapon-quest-reward"
        manifest = json.loads((package / "mod.json").read_text(encoding="utf-8"))
        script = (package / "main.lua").read_text(encoding="utf-8")
        self.assertEqual(manifest["id"], "example.weapon-quest-reward")
        self.assertEqual(set(manifest["games"]), {"chronicle", "chronicle-two"})
        self.assertTrue({"content.register", "game.write"}.issubset(manifest["permissions"]))
        self.assertIn('chronicle = "chronicle:weapon:258"', script)
        self.assertIn('{kind = "weapon", id = weapon_id}', script)
        self.assertIn('moonmod.on("quests.completed"', script)

    def test_dungeon_plus_package_structure(self) -> None:
        project = Path(__file__).resolve().parents[2]
        package = project / "mods" / "moonmod.dungeon-plus"
        manifest = json.loads((package / "mod.json").read_text(encoding="utf-8"))
        script = (package / "main.lua").read_text(encoding="utf-8")
        self.assertEqual(manifest["id"], "moonmod.dungeon-plus")
        self.assertEqual(manifest["games"], ["chronicle"])
        self.assertTrue({"game.read", "game.write", "content.register", "storage.read", "storage.write"}.issubset(manifest["permissions"]))
        self.assertIn("game.dungeons.set_layout", script)
        self.assertIn("game.combat.register_formula", script)
        self.assertIn("moonmod.storage.get", script)

    def test_ascension_package_structure(self) -> None:
        project = Path(__file__).resolve().parents[2]
        package = project / "mods" / "moonmod.adventurer"
        manifest = json.loads((package / "mod.json").read_text(encoding="utf-8"))
        script = (package / "main.lua").read_text(encoding="utf-8")
        self.assertEqual(manifest["id"], "moonmod.adventurer")
        self.assertEqual(manifest["games"], ["chronicle"])
        self.assertTrue({"game.read", "game.write", "content.register", "storage.read", "storage.write"}.issubset(manifest["permissions"]))
        self.assertIn("game.skills.register", script)
        self.assertIn("game.combat.register_formula", script)
        self.assertIn("game.player.get", script)
        self.assertIn("game.enemy_defeated", script)


if __name__ == "__main__":
    unittest.main()

