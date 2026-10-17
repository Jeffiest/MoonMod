#!/usr/bin/env python3
"""Create starter MoonFactory Lua mod packages."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MOD_ID = re.compile(r"^[a-z0-9][a-z0-9._-]{2,63}$")


def create_package(mod_id: str, output: Path, target: str = "both", name: str | None = None) -> Path:
    if not MOD_ID.fullmatch(mod_id):
        raise ValueError("mod id must be 3-64 lowercase letters, digits, '.', '_' or '-' and start with a letter or digit")
    if target not in {"both", "chronicle", "chronicle-two"}:
        raise ValueError("target must be 'both', 'chronicle', or 'chronicle-two'")

    source = PROJECT_ROOT / "examples" / "first-steps"
    if not (source / "mod.json").is_file() or not (source / "main.lua").is_file():
        raise FileNotFoundError(f"starter template is incomplete: {source}")

    destination = output.expanduser().resolve()
    if destination.exists():
        raise FileExistsError(f"output already exists: {destination}")

    manifest = json.loads((source / "mod.json").read_text(encoding="utf-8"))
    mod_name = name or mod_id.rsplit(".", 1)[-1].replace("-", " ").replace("_", " ").title()
    if not mod_name.strip() or len(mod_name) > 96:
        raise ValueError("mod name must contain 1-96 characters")
    manifest["id"] = mod_id
    manifest["name"] = mod_name
    manifest["author"] = mod_id.split(".", 1)[0]
    manifest["games"] = ["chronicle", "chronicle-two"] if target == "both" else [target]

    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination)
    try:
        (destination / "mod.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    except Exception:
        shutil.rmtree(destination)
        raise
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(prog="moonfactory", description="Create a Lua mod package from a tested starter template.")
    commands = parser.add_subparsers(dest="command", required=True)
    new = commands.add_parser("new", help="create a new mod package")
    new.add_argument("id", help="stable mod id, such as author.my-mod")
    new.add_argument("--output", type=Path, help="new package directory (defaults to ./<id>)")
    new.add_argument("--target", choices=("both", "chronicle", "chronicle-two"), default="both")
    new.add_argument("--name", help="display name stored in mod.json")
    args = parser.parse_args()

    output = args.output if args.output is not None else Path.cwd() / args.id
    try:
        package = create_package(args.id, output, args.target, args.name)
    except (FileExistsError, FileNotFoundError, ValueError, OSError) as error:
        parser.error(str(error))
    print(f"Created {package}")
    print("Copy the package folder into <save>/mods, then enable it in the in-game MoonFactory manager.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
