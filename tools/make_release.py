#!/usr/bin/env python3
"""Build the MoonMod release for Chronicle: a folder to paste over a Chronicle checkout.

The folder holds every Chronicle file the MoonFactory patches add or change, already patched, at the same paths as
in Chronicle (Kazarov's under tools/kazarov), plus a mods/ folder with the bundled mods. Its version is the Chronicle
commit it is made for (ports/chronicle/CHRONICLE_COMMIT), shortened to 8 characters.

    python tools/make_release.py                       # clones Chronicle from GitHub
    python tools/make_release.py --chronicle ..\\Chronicle   # or reuses a local clone (any commit, left untouched)
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PORT = PROJECT_ROOT / "ports" / "chronicle"
CHRONICLE_URL = "https://github.com/TheMoonPeople/Chronicle.git"
KAZAROV = Path("tools") / "kazarov"


def git(*args: str, cwd: Path) -> str:
    result = subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True)
    return result.stdout


def chronicle_commit() -> str:
    commit = (PORT / "CHRONICLE_COMMIT").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError(f"ports/chronicle/CHRONICLE_COMMIT must hold a full commit hash, not {commit!r}")
    patch = (PORT / "moonfactory-chronicle.patch").read_text(encoding="utf-8", errors="replace")
    pinned = re.search(r"set\(MOONMOD_CHRONICLE_COMMIT ([0-9a-f]{40})\)", patch)
    if not pinned or pinned.group(1) != commit:
        raise ValueError("MOONMOD_CHRONICLE_COMMIT in moonfactory-chronicle.patch does not match CHRONICLE_COMMIT")
    return commit


def changed_files(repo: Path) -> list[Path]:
    """Files that differ from HEAD or are new, without the submodule's own entry."""
    files = []
    for line in git("status", "--porcelain", "--untracked-files=all", "--ignore-submodules=all", cwd=repo).splitlines():
        status, path = line[:2], line[3:]
        if "D" in status or "R" in status:
            raise RuntimeError(f"the patch deletes or renames {path}; a pasted folder cannot do that")
        files.append(Path(path))
    return sorted(files)


def checkout(source: Path | str, commit: str, work: Path) -> Path:
    """Chronicle at commit with Kazarov at the commit it pins, taken from a local clone when there is one."""
    tree = work / "chronicle"
    git("clone", "--quiet", "--no-checkout", str(source), str(tree), cwd=work)
    git("checkout", "--quiet", commit, cwd=tree)
    kazarov = KAZAROV.as_posix()
    pinned = git("ls-tree", "HEAD", kazarov, cwd=tree).split()[2]
    local = Path(source) / KAZAROV if isinstance(source, Path) else None
    kazarov_source = str(local) if local and (local / ".git").exists() else \
        git("config", "-f", ".gitmodules", f"submodule.{kazarov}.url", cwd=tree).strip()
    git("clone", "--quiet", "--no-checkout", kazarov_source, str(tree / KAZAROV), cwd=work)
    git("checkout", "--quiet", pinned, cwd=tree / KAZAROV)
    return tree


def build(chronicle: str | None, output: Path, make_zip: bool) -> Path:
    commit = chronicle_commit()
    version = commit[:8]
    name = f"MoonMod-{version}"
    destination = output / name
    if destination.exists():
        shutil.rmtree(destination)

    with tempfile.TemporaryDirectory(prefix="moonmod-release-") as temp:
        work = Path(temp)
        tree = checkout(Path(chronicle).resolve() if chronicle else CHRONICLE_URL, commit, work)
        git("apply", "--whitespace=nowarn", str(PORT / "moonfactory-chronicle.patch"), cwd=tree)
        git("apply", "--whitespace=nowarn", str(PORT / "moonfactory-kazarov.patch"), cwd=tree / KAZAROV)

        files = changed_files(tree) + [KAZAROV / path for path in changed_files(tree / KAZAROV)]
        for relative in files:
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(tree / relative, target)

    mods = destination / "mods"
    mods.mkdir()
    bundled = sorted(path for path in (PROJECT_ROOT / "mods").iterdir() if (path / "mod.json").is_file())
    for mod in bundled:
        shutil.copytree(mod, mods / mod.name)
    (mods / "README.txt").write_text(MODS_README, encoding="utf-8", newline="\r\n")
    (destination / "MoonMod-README.txt").write_text(
        README.format(version=version, commit=commit, mods="\n".join(f"  {mod.name}" for mod in bundled),
                      files="\n".join(f"  {path.as_posix()}" for path in files)),
        encoding="utf-8", newline="\r\n")

    print(f"{destination}: {len(files)} Chronicle files, {len(bundled)} mods")
    if make_zip:
        archive = output / f"{name}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zipped:
            for path in sorted(destination.rglob("*")):
                if path.is_file():
                    zipped.write(path, Path(name) / path.relative_to(destination))
        print(archive)
    return destination


README = """MoonMod {version}
==================

MoonMod (MoonFactory) for Chronicle, the Dark Cloud PC port. This version is made for Chronicle commit
{commit}. MoonMod versions are named after the Chronicle commit they are made for.

Install
-------

1. Get Chronicle at that commit (Git for Windows, in PowerShell):

     git clone --recurse-submodules https://github.com/TheMoonPeople/Chronicle.git
     cd Chronicle
     git checkout {commit}
     git submodule update --init --recursive

2. Copy everything inside this MoonMod-{version} folder into the Chronicle folder. When Windows asks, choose
   "Replace the files in the destination". The replaced files are Chronicle's own files with MoonMod's changes
   already in them; the rest are new.

3. Put your Dark Cloud disc image where Chronicle expects it (rom\\pal\\Dark Cloud (PAL).iso), then build and run
   with Chronicle's own scripts:

     .\\build.bat windows-x64-release
     .\\run.bat windows-x64-release

   If the build warns that MoonMod is made for another Chronicle commit, the checkout is not at {commit}.

Mods
----

Each mod is a folder in Chronicle\\mods. Drop new ones in there; they start disabled. Turn them on in the game
under Options > Game > Mod Manager. Changing or adding mods needs only a restart of the game, not a rebuild.

Bundled mods:
{mods}

Updating Chronicle
------------------

Do not pull a newer Chronicle over a MoonMod install: wait for the MoonMod release named after that commit. To go
back to plain Chronicle, run "git checkout -- ." in Chronicle and in Chronicle\\tools\\kazarov.

Files this release replaces or adds
-----------------------------------

{files}
"""

MODS_README = """Each mod goes in its own folder here, named after the mod's id, holding its mod.json and Lua script.
New mods start disabled: turn them on in the game under Options > Game > Mod Manager, then restart the game.
"""


def main() -> int:
    parser = argparse.ArgumentParser(prog="make_release", description=__doc__.splitlines()[0])
    parser.add_argument("--chronicle", help="a local Chronicle clone to copy from instead of GitHub (left untouched)")
    parser.add_argument("--output", type=Path, default=PROJECT_ROOT / "dist", help="where to write the folder (dist/)")
    parser.add_argument("--no-zip", action="store_true", help="write only the folder, not the .zip beside it")
    args = parser.parse_args()
    try:
        build(args.chronicle, args.output.resolve(), not args.no_zip)
    except (subprocess.CalledProcessError, OSError, ValueError, RuntimeError) as error:
        detail = getattr(error, "stderr", "") or ""
        print(f"make_release: {error}\n{detail}".rstrip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
