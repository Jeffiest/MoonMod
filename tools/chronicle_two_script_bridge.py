#!/usr/bin/env python3
"""Inspect a ChronicleTwo-Script mod and write a Moon Factory compatibility report.

This tool never turns disc scripts or game assets into a Moon Factory runtime mod.
It inventories authored build-time components, checks their local paths, and can
optionally delegate script validation to the user's installed dc2tk executable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any


REPOSITORY_URL = "https://github.com/fakegenie/DC2-Toolkit"
REPOSITORY_ALIASES = ["https://github.com/fakegenie/ChronicleTwo-Script"]
MOON_FACTORY_PACKAGE_SCHEMA = 1
MOON_FACTORY_LUA_API_MAJOR = 1
IDENTIFIER = re.compile(r"^[A-Za-z0-9_.-]{1,80}$")
FLAG_CALL = re.compile(r"\bNEW_(FLAG|COUNTER|PROGRAM|MONSTER_VAR)\s*\(\s*([A-Za-z_]\w*)\s*\)")
TARGET_LINE = re.compile(r"^\s*#\s*pragma\s+target\s+(.+?)\s*$", re.MULTILINE)
OVERRIDE_LINE = re.compile(r"^\s*#\s*pragma\s+override(?:\s+(NATIVE))?\s*$", re.MULTILINE)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tool_fingerprint(path: Path) -> dict[str, Any]:
    resolved = path.expanduser().resolve()
    file_type = "batch_wrapper" if resolved.suffix.lower() == ".bat" else "executable"
    try:
        if not resolved.is_file():
            raise OSError("not a regular file")
        return {
            "path": str(resolved),
            "file_type": file_type,
            "size_bytes": resolved.stat().st_size,
            "sha256": sha256_file(resolved),
        }
    except OSError as exc:
        return {"path": str(resolved), "file_type": file_type, "size_bytes": None, "sha256": None,
                "error": str(exc)}


def tree_fingerprint(root: Path) -> str | None:
    if not root.is_dir():
        return None
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file() and not item.is_symlink()):
        rel = path.relative_to(root).as_posix()
        digest.update(rel.encode("utf-8"))
        digest.update(b"\0")
        digest.update(bytes.fromhex(sha256_file(path)))
    return digest.hexdigest()


def read_json(path: Path, errors: list[str], label: str) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"{label}: could not read valid JSON ({exc})")
        return None
    if not isinstance(value, dict):
        errors.append(f"{label}: expected a JSON object")
        return None
    return value


def contained_source_file(mod_root: Path, raw: str, errors: list[str], label: str) -> Path | None:
    relative = Path(raw)
    if relative.is_absolute() or any(part in ("..", "") for part in relative.parts):
        errors.append(f"{label}: source path must stay inside the mod folder: {raw}")
        return None
    candidate = mod_root / relative
    current = mod_root
    for part in relative.parts:
        current /= part
        if current.is_symlink():
            errors.append(f"{label}: source path contains a symbolic link: {raw}")
            return None
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(mod_root.resolve(strict=True))
    except (OSError, ValueError):
        errors.append(f"{label}: source file is missing or escapes the mod folder: {raw}")
        return None
    if not resolved.is_file():
        errors.append(f"{label}: source path is not a file: {raw}")
        return None
    return resolved


def contained_source_path(mod_root: Path, raw: str, errors: list[str], label: str) -> Path | None:
    relative = Path(raw)
    if relative.is_absolute() or any(part in ("..", "") for part in relative.parts):
        errors.append(f"{label}: source path must stay inside the mod folder: {raw}")
        return None
    candidate = mod_root / relative
    current = mod_root
    for part in relative.parts:
        current /= part
        if current.is_symlink():
            errors.append(f"{label}: source path contains a symbolic link: {raw}")
            return None
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(mod_root.resolve(strict=True))
    except (OSError, ValueError):
        errors.append(f"{label}: source path is missing or escapes the mod folder: {raw}")
        return None
    if not resolved.is_file() and not resolved.is_dir():
        errors.append(f"{label}: source path is not a file or directory: {raw}")
        return None
    return resolved


def source_path_fingerprint(path: Path, errors: list[str], label: str) -> dict[str, Any] | None:
    if path.is_file():
        return {"source_kind": "file", "size_bytes": path.stat().st_size, "sha256": sha256_file(path)}
    digest = hashlib.sha256()
    total_bytes = 0
    file_count = 0
    for item in sorted(path.rglob("*")):
        if item.is_symlink():
            errors.append(f"{label}: asset directory contains a symbolic link: {item.relative_to(path).as_posix()}")
            return None
        if not item.is_file():
            continue
        relative = item.relative_to(path).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(bytes.fromhex(sha256_file(item)))
        total_bytes += item.stat().st_size
        file_count += 1
    return {"source_kind": "directory", "size_bytes": total_bytes, "file_count": file_count,
            "tree_sha256": digest.hexdigest()}


def git_revision(root: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def scan_source(mod_root: Path, path: Path, component_kind: str, errors: list[str]) -> dict[str, Any]:
    relative = path.relative_to(mod_root).as_posix()
    record: dict[str, Any] = {
        "kind": component_kind,
        "path": relative,
        "size_bytes": path.stat().st_size,
        "sha256": sha256_file(path),
        "runtime_status": "build_only",
    }
    if path.suffix.lower() not in (".c", ".h"):
        return record
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        errors.append(f"{relative}: C source is not readable UTF-8 ({exc})")
        return record
    record["targets"] = TARGET_LINE.findall(source)
    record["overrides"] = [
        {"native_wrapper": match.group(1) is not None, "line": source.count("\n", 0, match.start()) + 1}
        for match in OVERRIDE_LINE.finditer(source)
    ]
    record["every_frame_hooks"] = len(re.findall(r"^\s*#\s*pragma\s+every_frame\b", source, re.MULTILINE))
    record["original_calls"] = len(re.findall(r"\boriginal\s*\(", source))
    record["symbols"] = {
        kind.lower(): sorted(set(name for found_kind, name in FLAG_CALL.findall(source) if found_kind == kind))
        for kind in ("FLAG", "COUNTER", "PROGRAM", "MONSTER_VAR")
    }
    return record


def parse_asset_entries(
    mod_root: Path,
    manifest: dict[str, Any],
    field: str,
    errors: list[str],
) -> list[dict[str, Any]]:
    mapping = manifest.get(field, {})
    if mapping is None:
        return []
    if not isinstance(mapping, dict):
        errors.append(f"mod.json: {field} must be an object mapping asset IDs to files")
        return []
    entries: list[dict[str, Any]] = []
    for asset_id, spec in sorted(mapping.items()):
        if not isinstance(asset_id, str):
            errors.append(f"mod.json: {field} contains a non-string asset ID")
            continue
        source_name = spec if isinstance(spec, str) else spec.get("file") if isinstance(spec, dict) else None
        entry: dict[str, Any] = {
            "operation": field,
            "asset_id": asset_id,
            "settings": {key: value for key, value in spec.items() if key != "file"} if isinstance(spec, dict) else {},
            "runtime_status": "build_only",
        }
        if not isinstance(source_name, str):
            errors.append(f"mod.json: {field}[{asset_id!r}] must name a source file")
            entry["source"] = None
            entry["source_exists"] = False
        else:
            source_path = contained_source_path(mod_root, source_name, errors, f"{field}[{asset_id!r}]")
            entry["source"] = source_name.replace("\\", "/")
            entry["source_exists"] = source_path is not None
            if source_path is not None:
                fingerprint = source_path_fingerprint(source_path, errors, f"{field}[{asset_id!r}]")
                if fingerprint is not None:
                    entry.update(fingerprint)
        entries.append(entry)
    return entries


def inspect_project(
    project_root: Path,
    mod_name: str,
    disc_path: Path | None = None,
    mod_dir: Path | None = None,
) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    root = project_root.resolve()
    mods_root = root / "mods"
    if not IDENTIFIER.fullmatch(mod_name):
        return {"errors": ["mod name must use letters, digits, '.', '_' or '-' and be at most 80 characters"]}
    mod_root = mod_dir if mod_dir is not None else mods_root / mod_name
    if mod_root.is_symlink():
        return {"errors": [f"mod folder must not be a symlink: {mod_root}"]}
    try:
        resolved_mod_root = mod_root.resolve(strict=True)
        if mod_dir is None:
            resolved_mod_root.relative_to(mods_root.resolve(strict=True))
    except (OSError, ValueError):
        return {"errors": [f"mod folder is missing or escapes the project's mods folder: {mod_root}"]}
    if not resolved_mod_root.is_dir():
        return {"errors": [f"mod folder is not a directory: {mod_root}"]}

    manifest_path = resolved_mod_root / "mod.json"
    manifest = read_json(manifest_path, errors, "mod.json")
    if manifest is None:
        manifest = {}

    components: list[dict[str, Any]] = []
    requested_symbols: dict[str, set[str]] = {"flag": set(), "counter": set(), "program": set(), "monster_var": set()}
    for path in sorted(resolved_mod_root.rglob("*")):
        if path.is_symlink():
            errors.append(f"mod content symlink is not accepted: {path.relative_to(resolved_mod_root).as_posix()}")
            continue
        if not path.is_file():
            continue
        relative = path.relative_to(resolved_mod_root)
        if any(part.startswith(".") for part in relative.parts):
            continue
        if relative.parts[0] == "files":
            record = scan_source(resolved_mod_root, path, "whole_file_override", errors)
            components.append(record)
        elif relative.parts[0] == "disc":
            components.append(scan_source(resolved_mod_root, path, "raw_disc_file_override", errors))
        elif path.name == "tests.c":
            components.append(scan_source(resolved_mod_root, path, "dc2tk_mod_test", errors))
        elif path.suffix.lower() in (".c", ".h"):
            record = scan_source(resolved_mod_root, path, "script_patch_or_shared_source", errors)
            components.append(record)

    for record in components:
        for kind, names in record.get("symbols", {}).items():
            requested_symbols[kind].update(names)

    replace_entries = parse_asset_entries(resolved_mod_root, manifest, "replace", errors)
    add_entries = parse_asset_entries(resolved_mod_root, manifest, "add", errors)
    seen: dict[str, str] = {}
    for entry in replace_entries + add_entries:
        asset_id = entry["asset_id"]
        if asset_id in seen:
            errors.append(f"asset ID {asset_id!r} appears in both {seen[asset_id]} and {entry['operation']}")
        seen[asset_id] = entry["operation"]

    additions = manifest.get("additions", [])
    addition_records: list[dict[str, Any]] = []
    if not isinstance(additions, list) or any(not isinstance(item, dict) for item in additions):
        errors.append("mod.json: additions must be an array of script selection objects")
    else:
        for index, addition in enumerate(additions):
            includes = addition.get("includes", [])
            if not isinstance(includes, list) or any(not isinstance(path, str) for path in includes):
                errors.append(f"mod.json: additions[{index}].includes must be an array of source paths")
                includes = []
            include_records = []
            for source_name in includes:
                source_path = contained_source_file(resolved_mod_root, source_name, errors,
                                                    f"additions[{index}].includes")
                include_records.append({"source": source_name, "exists": source_path is not None,
                                        "sha256": sha256_file(source_path) if source_path is not None else None})
            addition_records.append({"selection": {key: addition[key] for key in ("map", "scripts") if key in addition},
                                     "programs": addition.get("programs", {}),
                                     "wrap": addition.get("wrap", {}),
                                     "includes": include_records,
                                     "runtime_status": "build_only"})

    dependencies: dict[str, list[str]] = {}
    for key in ("requires", "after"):
        value = manifest.get(key, [])
        if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
            errors.append(f"mod.json: {key} must be an array of mod names")
            dependencies[key] = []
        else:
            dependencies[key] = value

    persisted_allocations: Any = None
    allocations_path = mods_root / "numbers.json"
    if mod_dir is not None and not allocations_path.exists():
        sibling_allocations = resolved_mod_root.parent / "numbers.json"
        if sibling_allocations.is_file():
            allocations_path = sibling_allocations
    if allocations_path.exists():
        persisted_allocations = read_json(allocations_path, errors, "mods/numbers.json")
    fingerprints_path = resolved_mod_root / "fingerprints.json"
    fingerprints: Any = read_json(fingerprints_path, errors, "fingerprints.json") if fingerprints_path.exists() else None

    disc_record: dict[str, Any] | None = None
    if disc_path is not None:
        try:
            resolved_disc = disc_path.resolve(strict=True)
            if not resolved_disc.is_file():
                raise OSError("not a regular file")
            disc_record = {"path": str(resolved_disc), "size_bytes": resolved_disc.stat().st_size, "sha256": sha256_file(resolved_disc)}
        except OSError as exc:
            errors.append(f"disc fingerprint: could not read {disc_path} ({exc})")

    if not components and not replace_entries and not add_entries:
        warnings.append("the source mod has no script, asset, or raw-disc components")
    warnings.append("C2-Script build components are preserved as build-only; this report does not make them load in the PC runtime")
    return {
        "format_version": 1,
        "report_kind": "moon-factory.chronicle-two-script-compatibility",
        "source": {
            "repository": REPOSITORY_URL,
            "repository_aliases": REPOSITORY_ALIASES,
            "project_root": str(root),
            "tool_revision": git_revision(root),
            "definition_set": "definitions/pal",
            "definition_set_sha256": tree_fingerprint(root / "definitions" / "pal"),
            "mod_name": mod_name,
            "mod_root": str(resolved_mod_root),
            "manifest_sha256": sha256_file(manifest_path) if manifest_path.is_file() else None,
            "manifest": manifest,
            "dependencies": dependencies,
            "start_at": manifest.get("start_at"),
            "disc_fingerprint": disc_record,
        },
        "target": {
            "game_id": "chronicle-two",
            "package_schema_version": MOON_FACTORY_PACKAGE_SCHEMA,
            "lua_api_major": MOON_FACTORY_LUA_API_MAJOR,
        },
        "components": components,
        "assets": {"replace": replace_entries, "add": add_entries},
        "script_additions": addition_records,
        "script_symbols": {
            "requested": {key: sorted(names) for key, names in requested_symbols.items()},
            "persisted_allocations": persisted_allocations,
            "allocation_file": str(allocations_path.resolve()) if allocations_path.is_file() else None,
            "target_fingerprints": fingerprints,
            "allocation_destination": "ChronicleTwo-Script mods/numbers.json (build-time only)",
        },
        "capabilities": {
            "chronicle_two_pc_runtime": "not_loaded",
            "script_image_build": "not_run",
            "notes": [
                "Script overrides, native wrappers, whole-file replacements, added assets, and allocated symbols affect a rebuilt script image only.",
                "Moon Factory's current PC adapter must independently prove a matching native runtime loader before any component is reported runtime-supported.",
            ],
        },
        "validation": {
            "static_inventory": "failed" if errors else "passed",
            "dc2tk_mod_check": {"status": "not_requested"},
        },
        "warnings": warnings,
        "errors": errors,
    }


def run_mod_check(project_root: Path, mod_name: str, tool: Path | None, disc_path: Path | None) -> dict[str, Any]:
    root = project_root.resolve()
    if tool is None:
        candidates = [root / "build" / "release" / "dc2tk.exe", root / "build" / "release" / "dc2tk", root / "dc2tk.bat"]
        tool = next((candidate for candidate in candidates if candidate.is_file()), None)
    if tool is None:
        return {"status": "failed", "exit_code": None, "error": "dc2tk was not found; pass --dc2tk with its executable or wrapper path"}
    tool_record = tool_fingerprint(tool)
    source = root / "extracted" / "scripts"
    if not source.is_dir():
        return {"status": "failed", "exit_code": None, "error": "missing extracted/scripts; run dc2tk setup with the user's own disc first"}
    command = [str(tool), "mod", "check", str(source), mod_name]
    if disc_path is not None:
        command.extend(["--disc", str(disc_path.resolve())])
    try:
        if tool.suffix.lower() == ".bat":
            command_text = subprocess.list2cmdline(command)
            result = subprocess.run(["cmd.exe", "/d", "/s", "/c", command_text], cwd=root, capture_output=True, text=True, timeout=300)
        else:
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"status": "failed", "exit_code": None, "error": str(exc), "command": command,
                "tool": tool_record}
    return {
        "status": "passed" if result.returncode == 0 else "failed",
        "exit_code": result.returncode,
        "command": command,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "tool": tool_record,
    }


def run_mod_test(project_root: Path, mod_name: str, tool: Path | None) -> dict[str, Any]:
    root = project_root.resolve()
    if tool is None:
        candidates = [root / "build" / "release" / "dc2tk.exe", root / "build" / "release" / "dc2tk", root / "dc2tk.bat"]
        tool = next((candidate for candidate in candidates if candidate.is_file()), None)
    if tool is None:
        return {"status": "failed", "exit_code": None, "error": "dc2tk was not found; pass --dc2tk with its executable or wrapper path"}
    tool_record = tool_fingerprint(tool)
    source = root / "extracted" / "scripts"
    if not source.is_dir():
        return {"status": "failed", "exit_code": None, "error": "missing extracted/scripts; run dc2tk setup with the user's own disc first"}
    command = [str(tool), "mod", "test", str(source), mod_name]
    try:
        if tool.suffix.lower() == ".bat":
            command_text = subprocess.list2cmdline(command)
            result = subprocess.run(["cmd.exe", "/d", "/s", "/c", command_text], cwd=root,
                                   capture_output=True, text=True, timeout=300)
        else:
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"status": "failed", "exit_code": None, "error": str(exc), "command": command,
                "tool": tool_record}
    return {
        "status": "passed" if result.returncode == 0 else "failed",
        "exit_code": result.returncode,
        "command": command,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "tool": tool_record,
        "runtime_status": "build_only",
    }


def run_mod_build(
    project_root: Path,
    mod_name: str,
    tool: Path | None,
    disc_path: Path | None,
    output_image: Path | None,
) -> dict[str, Any]:
    root = project_root.resolve()
    if tool is None:
        candidates = [root / "build" / "release" / "dc2tk.exe", root / "build" / "release" / "dc2tk", root / "dc2tk.bat"]
        tool = next((candidate for candidate in candidates if candidate.is_file()), None)
    if tool is None:
        return {"status": "failed", "exit_code": None, "error": "dc2tk was not found; pass --dc2tk with its executable or wrapper path"}
    tool_record = tool_fingerprint(tool)
    source = root / "extracted" / "scripts"
    if not source.is_dir():
        return {"status": "failed", "exit_code": None, "error": "missing extracted/scripts; run dc2tk setup with the user's own disc first"}
    if disc_path is None:
        return {"status": "failed", "exit_code": None, "error": "building a script image requires --disc with the user's own base image"}
    try:
        disc = disc_path.expanduser().resolve(strict=True)
        if not disc.is_file():
            raise OSError("not a regular file")
    except OSError as exc:
        return {"status": "failed", "exit_code": None, "error": f"could not read base image {disc_path}: {exc}"}
    if output_image is None:
        return {"status": "failed", "exit_code": None, "error": "an explicit --output-image path is required"}
    output = output_image.expanduser()
    if not output.is_absolute():
        output = root / output
    output = output.resolve()
    if output == disc:
        return {"status": "failed", "exit_code": None, "error": "output image must not overwrite the input disc"}
    if output.exists():
        return {"status": "failed", "exit_code": None, "error": f"output image already exists: {output}"}
    if output.suffix.lower() not in (".iso", ".bin"):
        return {"status": "failed", "exit_code": None, "error": "output image must use an .iso or .bin extension"}
    if not output.parent.is_dir():
        return {"status": "failed", "exit_code": None, "error": f"output directory does not exist: {output.parent}"}

    command = [str(tool), "build", str(source), str(disc), "-o", str(output), "--mod", mod_name]
    try:
        if tool.suffix.lower() == ".bat":
            command_text = subprocess.list2cmdline(command)
            result = subprocess.run(["cmd.exe", "/d", "/s", "/c", command_text], cwd=root,
                                   capture_output=True, text=True, timeout=1800)
        else:
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=1800)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"status": "failed", "exit_code": None, "error": str(exc), "command": command,
                "tool": tool_record}
    report: dict[str, Any] = {
        "status": "passed" if result.returncode == 0 else "failed",
        "exit_code": result.returncode,
        "command": command,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "tool": tool_record,
        "input_disc": {"path": str(disc), "size_bytes": disc.stat().st_size, "sha256": sha256_file(disc)},
        "output_image": str(output),
        "runtime_status": "build_only",
    }
    if result.returncode == 0:
        if not output.is_file():
            report["status"] = "failed"
            report["error"] = "dc2tk reported success but did not create the requested output image"
        else:
            report["built_image"] = {
                "path": str(output),
                "size_bytes": output.stat().st_size,
                "sha256": sha256_file(output),
                "runtime_status": "build_only",
            }
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", nargs="?", type=Path, help="local ChronicleTwo-Script checkout")
    parser.add_argument("--mod", help="mod folder name under <project>/mods")
    parser.add_argument("--mod-dir", type=Path,
                        help="optional authored mod directory for static inventory; dc2tk checks still use extracted/scripts")
    parser.add_argument("--disc", type=Path, help="optional user-owned PAL ISO to fingerprint and pass to mod check")
    parser.add_argument("--dc2tk", type=Path, help="optional dc2tk executable or dc2tk.bat path")
    parser.add_argument("--run-mod-check", action="store_true", help="run dc2tk mod check against extracted/scripts")
    parser.add_argument("--run-mod-test", action="store_true", help="run the mod's dc2tk tests without the game")
    parser.add_argument("--run-mod-build", action="store_true",
                        help="build the selected C2-Script mod into a separate offline image")
    parser.add_argument("--output-image", type=Path,
                        help="new ISO/BIN path required by --run-mod-build; existing files are never overwritten")
    parser.add_argument("--output", type=Path, help="write the full JSON report to this path")
    parser.add_argument("--self-test", action="store_true", help="run bridge and package-example fixture tests")
    args = parser.parse_args(argv)

    if args.self_test:
        test_root = Path(__file__).with_name("tests")
        suite = unittest.defaultTestLoader.discover(str(test_root), pattern="test_*.py")
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if args.project is None or not args.mod:
        parser.error("project and --mod are required unless --self-test is used")
    if args.run_mod_build and (args.disc is None or args.output_image is None):
        parser.error("--run-mod-build requires both --disc and --output-image")

    report = inspect_project(args.project, args.mod, args.disc, args.mod_dir)
    inventory_valid = report.get("validation", {}).get("static_inventory") == "passed"
    external_validation_allowed = inventory_valid and args.mod_dir is None
    if args.mod_dir is not None:
        external_validation_error = "--mod-dir is static-inventory-only; dc2tk commands require the selected package under <project>/mods"
    else:
        external_validation_error = "static inventory failed; dc2tk was not run"
    if args.run_mod_check:
        report.setdefault("validation", {})["dc2tk_mod_check"] = (
            run_mod_check(args.project, args.mod, args.dc2tk, args.disc)
            if external_validation_allowed else
            {"status": "failed", "exit_code": None, "error": external_validation_error}
        )
        if report["validation"]["dc2tk_mod_check"]["status"] != "passed":
            report["validation"]["script_image_build"] = "failed"
        else:
            report["validation"]["script_image_build"] = "mod_check_passed"
    if args.run_mod_test:
        report.setdefault("validation", {})["dc2tk_mod_test"] = (
            run_mod_test(args.project, args.mod, args.dc2tk)
            if external_validation_allowed else
            {"status": "failed", "exit_code": None, "error": external_validation_error}
        )
    if args.run_mod_build:
        build_report = (
            run_mod_build(args.project, args.mod, args.dc2tk, args.disc, args.output_image)
            if external_validation_allowed else
            {"status": "failed", "exit_code": None, "error": external_validation_error}
        )
        report.setdefault("validation", {})["dc2tk_mod_build"] = build_report
        report["capabilities"]["script_image_build"] = (
            "built_build_only" if build_report["status"] == "passed" else "failed"
        )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Moon Factory bridge report: {args.output}")
    else:
        print(json.dumps(report, indent=2, sort_keys=True))
    validation = report.get("validation", {})
    return 1 if report.get("errors") or validation.get("script_image_build") == "failed" or \
        validation.get("dc2tk_mod_test", {}).get("status") == "failed" or \
        validation.get("dc2tk_mod_build", {}).get("status") == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
