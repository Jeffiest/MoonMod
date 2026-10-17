from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from chronicle_two_script_bridge import inspect_project, main as bridge_main, run_mod_build, run_mod_check, run_mod_test  # noqa: E402


class ChronicleTwoScriptBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="moon-factory-c2script-")
        self.root = Path(self.temporary.name)
        self.mod = self.root / "mods" / "sample-mod"
        self.mod.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write(self, relative: str, contents: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def test_reports_build_only_components_symbols_and_asset_provenance(self) -> None:
        self.write(
            "mods/sample-mod/mod.json",
            json.dumps(
                {
                    "requires": ["base-mod"],
                    "after": ["other-mod"],
                    "start_at": "s51:SHOW_SCENE",
                    "replace": {"texture:e254a1": "art/recolor.png"},
                    "add": {"sound:SE_MOD_BEEP": {"file": "audio/beep.wav", "bank": "SP_004"}},
                    "additions": [{"map": "s51", "programs": {"9000": "start_scene"},
                                   "includes": ["lib/mods/sample-mod/scene.c"]}],
                }
            ),
        )
        self.write(
            "mods/sample-mod/s51.c",
            "#pragma target map s51\n"
            "NEW_FLAG(SCENE_SEEN);\n"
            "#pragma override NATIVE\n"
            "void wrap_native(void) { original(); }\n",
        )
        self.write("mods/sample-mod/art/recolor.png", "png fixture")
        self.write("mods/sample-mod/audio/beep.wav", "wav fixture")
        self.write("mods/sample-mod/lib/mods/sample-mod/scene.c", "void start_scene(void) {}")
        self.write("mods/sample-mod/files/map/s51_1.c", "NEW_PROGRAM(MOD_SCENE);\n")
        self.write("mods/numbers.json", '{"sample-mod": {"SCENE_SEEN": 1024}}')
        self.write("definitions/pal/README.txt", "PAL fixture definitions")

        report = inspect_project(self.root, "sample-mod")

        self.assertEqual(report["validation"]["static_inventory"], "passed")
        self.assertEqual(report["source"]["dependencies"], {"requires": ["base-mod"], "after": ["other-mod"]})
        self.assertEqual(report["script_symbols"]["requested"]["flag"], ["SCENE_SEEN"])
        self.assertEqual(report["script_symbols"]["requested"]["program"], ["MOD_SCENE"])
        patch = next(component for component in report["components"] if component["path"] == "s51.c")
        self.assertEqual(patch["targets"], ["map s51"])
        self.assertEqual(patch["overrides"], [{"native_wrapper": True, "line": 3}])
        self.assertEqual(report["assets"]["replace"][0]["source"], "art/recolor.png")
        self.assertEqual(report["assets"]["add"][0]["settings"], {"bank": "SP_004"})
        self.assertEqual(report["script_additions"][0]["selection"], {"map": "s51"})
        self.assertTrue(report["script_additions"][0]["includes"][0]["exists"])
        self.assertEqual(report["capabilities"]["chronicle_two_pc_runtime"], "not_loaded")
        self.assertEqual(report["capabilities"]["script_image_build"], "not_run")
        self.assertEqual(report["source"]["repository"], "https://github.com/fakegenie/DC2-Toolkit")
        self.assertIn("https://github.com/fakegenie/ChronicleTwo-Script", report["source"]["repository_aliases"])
        self.assertEqual(report["target"]["package_schema_version"], 1)
        self.assertEqual(report["target"]["lua_api_major"], 1)

    def test_rejects_asset_paths_that_escape_the_mod_folder(self) -> None:
        self.write(
            "mods/sample-mod/mod.json",
            json.dumps({"replace": {"texture:e254a1": "../../outside.png"}}),
        )
        report = inspect_project(self.root, "sample-mod")
        self.assertEqual(report["validation"]["static_inventory"], "failed")
        self.assertTrue(any("must stay inside the mod folder" in error for error in report["errors"]))

    def test_reports_duplicate_asset_ids_across_add_and_replace(self) -> None:
        self.write("mods/sample-mod/mod.json", json.dumps({"replace": {"sound:X": "x.wav"}, "add": {"sound:X": {"file": "x.wav"}}}))
        self.write("mods/sample-mod/x.wav", "wav fixture")
        report = inspect_project(self.root, "sample-mod")
        self.assertTrue(any("appears in both replace and add" in error for error in report["errors"]))

    def test_scans_external_example_folder_and_fingerprints_directory_assets(self) -> None:
        example = self.root / "docs" / "examples" / "calculator"
        self.write(
            "docs/examples/calculator/mod.json",
            json.dumps({"add": {"file:mods/calculator/ui.img": {"file": "ui"}}}),
        )
        self.write("docs/examples/calculator/calculator.c", "NEW_PROGRAM(CALCULATOR_START);\n")
        self.write("docs/examples/calculator/ui/body.png", "body")
        self.write("docs/examples/calculator/ui/nested/icons.png", "icons")
        self.write("docs/examples/numbers.json", '{"calculator": {"CALCULATOR_START": 9000}}')

        report = inspect_project(self.root, "calculator", mod_dir=example)

        self.assertEqual(report["validation"]["static_inventory"], "passed")
        self.assertEqual(report["source"]["mod_root"], str(example.resolve()))
        self.assertEqual(report["script_symbols"]["requested"]["program"], ["CALCULATOR_START"])
        self.assertEqual(report["script_symbols"]["persisted_allocations"], {"calculator": {"CALCULATOR_START": 9000}})
        asset = report["assets"]["add"][0]
        self.assertEqual(asset["source_kind"], "directory")
        self.assertEqual(asset["file_count"], 2)
        self.assertEqual(asset["size_bytes"], len("body") + len("icons"))
        self.assertEqual(len(asset["tree_sha256"]), 64)

    def test_runs_the_users_dc2tk_mod_check_command(self) -> None:
        self.write("extracted/scripts/.fixture", "")
        tool = self.root / "dc2tk.exe"
        tool.write_bytes(b"fixture")
        with patch(
            "chronicle_two_script_bridge.subprocess.run",
            return_value=SimpleNamespace(returncode=0, stdout="mod check passed", stderr=""),
        ) as run:
            result = run_mod_check(self.root, "sample-mod", tool, None)

        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["tool"]["sha256"], hashlib.sha256(b"fixture").hexdigest())
        self.assertEqual(result["tool"]["file_type"], "executable")
        self.assertEqual(
            result["command"],
            [str(tool), "mod", "check", str(self.root.resolve() / "extracted" / "scripts"), "sample-mod"],
        )
        self.assertEqual(run.call_args.kwargs["cwd"], self.root.resolve())

    def test_runs_the_mods_offline_dc2tk_tests(self) -> None:
        scripts = self.root / "extracted" / "scripts"
        scripts.mkdir(parents=True)
        tool = self.root / "dc2tk.exe"
        tool.write_bytes(b"fixture")
        with patch(
            "chronicle_two_script_bridge.subprocess.run",
            return_value=SimpleNamespace(returncode=0, stdout="mod tests passed", stderr=""),
        ) as run:
            result = run_mod_test(self.root, "sample-mod", tool)

        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["runtime_status"], "build_only")
        self.assertEqual(result["tool"]["sha256"], hashlib.sha256(b"fixture").hexdigest())
        self.assertEqual(
            result["command"],
            [str(tool), "mod", "test", str(scripts), "sample-mod"],
        )
        self.assertEqual(run.call_args.kwargs["cwd"], self.root.resolve())

    def test_builds_a_separate_offline_image_and_fingerprints_it(self) -> None:
        scripts = self.root / "extracted" / "scripts"
        scripts.mkdir(parents=True)
        disc = self.root / "owned-pal.iso"
        disc.write_bytes(b"owned source image")
        tool = self.root / "dc2tk.exe"
        tool.write_bytes(b"fixture")
        output = self.root / "build" / "sample-mod.iso"
        output.parent.mkdir()

        def build(command: list[str], **kwargs: object) -> SimpleNamespace:
            Path(command[command.index("-o") + 1]).write_bytes(b"built script image")
            return SimpleNamespace(returncode=0, stdout="image verified", stderr="")

        with patch("chronicle_two_script_bridge.subprocess.run", side_effect=build) as run:
            result = run_mod_build(self.root, "sample-mod", tool, disc, output)

        expected_command = [
            str(tool), "build", str(scripts), str(disc), "-o", str(output), "--mod", "sample-mod"
        ]
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["runtime_status"], "build_only")
        self.assertEqual(result["tool"]["sha256"], hashlib.sha256(b"fixture").hexdigest())
        self.assertEqual(result["command"], expected_command)
        self.assertEqual(result["built_image"]["size_bytes"], len(b"built script image"))
        self.assertEqual(len(result["built_image"]["sha256"]), 64)
        self.assertEqual(run.call_args.args[0], expected_command)
        self.assertEqual(run.call_args.kwargs["cwd"], self.root.resolve())

    def test_offline_image_build_refuses_to_overwrite_or_replace_the_disc(self) -> None:
        scripts = self.root / "extracted" / "scripts"
        scripts.mkdir(parents=True)
        disc = self.root / "owned-pal.iso"
        disc.write_bytes(b"owned source image")
        tool = self.root / "dc2tk.exe"
        tool.write_bytes(b"fixture")
        existing = self.root / "already-built.iso"
        existing.write_bytes(b"keep")

        with patch("chronicle_two_script_bridge.subprocess.run") as run:
            overwrite = run_mod_build(self.root, "sample-mod", tool, disc, existing)
            same_path = run_mod_build(self.root, "sample-mod", tool, disc, disc)

        self.assertEqual(overwrite["status"], "failed")
        self.assertIn("already exists", overwrite["error"])
        self.assertEqual(same_path["status"], "failed")
        self.assertIn("must not overwrite", same_path["error"])
        self.assertEqual(existing.read_bytes(), b"keep")
        run.assert_not_called()

    def test_cli_will_not_run_dc2tk_after_static_inventory_failure(self) -> None:
        self.write("mods/sample-mod/mod.json", json.dumps({"replace": {"texture:bad": "../../outside.png"}}))
        (self.root / "extracted" / "scripts").mkdir(parents=True)
        disc = self.root / "owned-pal.iso"
        disc.write_bytes(b"owned source image")
        tool = self.root / "dc2tk.exe"
        tool.write_bytes(b"fixture")
        output_image = self.root / "built.iso"
        report_path = self.root / "report.json"

        with patch("chronicle_two_script_bridge.git_revision", return_value=None), \
             patch("chronicle_two_script_bridge.subprocess.run") as run:
            exit_code = bridge_main([
                str(self.root), "--mod", "sample-mod", "--run-mod-build", "--dc2tk", str(tool),
                "--disc", str(disc), "--output-image", str(output_image), "--output", str(report_path),
            ])

        self.assertEqual(exit_code, 1)
        run.assert_not_called()
        report = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertEqual(report["validation"]["static_inventory"], "failed")
        self.assertIn("dc2tk was not run", report["validation"]["dc2tk_mod_build"]["error"])
        self.assertFalse(output_image.exists())

    def test_external_build_is_disabled_for_static_only_mod_dir(self) -> None:
        example = self.root / "docs" / "examples" / "calculator"
        example.mkdir(parents=True)
        (example / "mod.json").write_text("{}", encoding="utf-8")
        (example / "calculator.c").write_text("NEW_PROGRAM(CALCULATOR_START);\n", encoding="utf-8")
        (self.root / "extracted" / "scripts").mkdir(parents=True)
        disc = self.root / "owned-pal.iso"
        disc.write_bytes(b"owned source image")
        tool = self.root / "dc2tk.exe"
        tool.write_bytes(b"fixture")
        report_path = self.root / "report.json"
        output_image = self.root / "built.iso"

        with patch("chronicle_two_script_bridge.git_revision", return_value=None), \
             patch("chronicle_two_script_bridge.subprocess.run") as run:
            exit_code = bridge_main([
                str(self.root), "--mod", "calculator", "--mod-dir", str(example), "--run-mod-build",
                "--dc2tk", str(tool), "--disc", str(disc), "--output-image", str(output_image),
                "--output", str(report_path),
            ])

        self.assertEqual(exit_code, 1)
        run.assert_not_called()
        report = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertEqual(report["validation"]["static_inventory"], "passed")
        self.assertIn("static-inventory-only", report["validation"]["dc2tk_mod_build"]["error"])
        self.assertFalse(output_image.exists())


if __name__ == "__main__":
    unittest.main()
