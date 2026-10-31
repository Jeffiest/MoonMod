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
import json
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
    how_to = HOW_TO.format(version=version, commit=commit, mods="\n".join(mod_line(mod) for mod in bundled))
    listing = "\n".join(f"- `{path.as_posix()}`" for path in files)
    (destination / "MoonMod-README.txt").write_text(how_to + FILES.format(files=listing), encoding="utf-8",
                                                    newline="\r\n")
    # The GitHub release page: the same how-to, with the file list folded away.
    notes = how_to + f"\n<details><summary>Files this release replaces or adds ({len(files)})</summary>\n\n{listing}\n\n</details>\n"
    (output / f"{name}-notes.md").write_text(notes, encoding="utf-8")

    print(f"{destination}: {len(files)} Chronicle files, {len(bundled)} mods")
    if make_zip:
        archive = output / f"{name}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zipped:
            for path in sorted(destination.rglob("*")):
                if path.is_file():
                    zipped.write(path, Path(name) / path.relative_to(destination))
        print(archive)
    return destination


HOW_TO = r"""# MoonMod {version}

MoonMod (MoonFactory) adds mods to **Chronicle**, the PC port of _Dark Cloud_: an in-game Mod Manager, Lua mods
and the bundled mods below. This release is made for Chronicle commit `{commit}`; every MoonMod version is named
after the Chronicle commit it is made for. Nothing from the game is included: you build Chronicle yourself from
your own disc.

## What you need

- Windows 10 or 11, 64-bit.
- [Git for Windows](https://git-scm.com/download/win).
- Your own _Dark Cloud_ disc image, PAL version.
- `MoonMod-{version}.zip` from this release.

## Install

1. **Get Chronicle at the matching commit.** Open PowerShell in the folder that should hold Chronicle and run:

   ```powershell
   git clone --recurse-submodules https://github.com/TheMoonPeople/Chronicle.git
   cd Chronicle
   git checkout {commit}
   git submodule update --init --recursive
   ```

2. **Copy MoonMod into it.** Unzip `MoonMod-{version}.zip`. Open the `MoonMod-{version}` folder inside it, select
   everything (Ctrl+A), copy it, and paste it into the `Chronicle` folder. When Windows asks, choose **Replace the
   files in the destination**, for all of them. The replaced files are Chronicle's own files with MoonMod's changes
   already made; the rest are new, including the `mods` folder.

3. **Add your disc image** as `Chronicle\rom\pal\Dark Cloud (PAL).iso`.

4. **Build** from the `Chronicle` folder:

   ```powershell
   .\build.bat windows-x64-release
   ```

   The first build downloads Chronicle's toolchain into `.kazarov\windows` and takes a while; later builds are
   quicker. If the output warns that _MoonMod is made for Chronicle ..._, the checkout is at the wrong commit: see
   Troubleshooting.

5. **Play:**

   ```powershell
   .\run.bat windows-x64-release
   ```

   The first start extracts the game data from your disc image into `port\run\data`.

## Turn mods on

Mods start **off**. In the game open **Options > Game > Mod Manager** (also **MODS** on the pause ring). Pick a mod,
turn it on, and look through its **Settings** and **Actions**. Restart the game for the change to take effect.

## Add more mods

Each mod is a folder in `Chronicle\mods`, named after the mod's id, holding its `mod.json` and Lua script. Drop a
new mod folder in there and start the game; it shows up in the Mod Manager, turned off. Adding, changing or removing
mods needs only a game restart, never a rebuild.

Bundled mods:

{mods}

## Update to a new MoonMod

A new MoonMod version normally means Chronicle moved and MoonMod was reworked for it. In the `Chronicle` folder:

```powershell
git checkout -- .
git -C tools\kazarov checkout -- .
git fetch
git checkout <the new release's Chronicle commit>
git submodule update --init --recursive
```

Then paste the new release over it as in step 2, and build again. Your saves (`port\run\save`) and any mods you
added to `mods` stay. Do not update Chronicle on its own while MoonMod is installed: wait for the MoonMod release
made for the newer commit.

## Go back to plain Chronicle

In the `Chronicle` folder run `git checkout -- .` and `git -C tools\kazarov checkout -- .`, then `git clean -n` to
list the files MoonMod added and `git clean -f` to delete them (it leaves ignored files, such as your saves and the
build, alone). Delete the `mods` folder if you no longer want it, and build again.

## Troubleshooting

- **The build warns that MoonMod is made for another Chronicle commit.** Run `git checkout -- .` and
  `git -C tools\kazarov checkout -- .`, then `git checkout {commit}` and
  `git submodule update --init --recursive`, paste the release again and rebuild.
- **The build fails after pasting.** Make sure every file was replaced (step 2), then build from scratch:
  `$env:CLEAN=1; .\build.bat windows-x64-release`.
- **The Mod Manager says no mods were found.** Each mod needs its own folder directly in `Chronicle\mods` with
  `mod.json` inside (`Chronicle\mods\moonmod.rpg\mod.json`, not `Chronicle\mods\moonmod.rpg\moonmod.rpg\mod.json`).
  The game's console output names the folder it reads, in the line `moonmod: mods folder ...`.
- **A mod turned itself off.** It hit an error; the console output says which and why. The other mods keep running.
- **The game asks for its data.** The disc image is not at `rom\pal\Dark Cloud (PAL).iso`.

More: [MoonMod on GitHub](https://github.com/Jeffiest/MoonMod), and Chronicle's own README for the build itself.
"""

FILES = """
## Files this release replaces or adds

{files}
"""

MODS_README = """Each mod goes in its own folder here, named after the mod's id, holding its mod.json and Lua script.
New mods start off: turn them on in the game under Options > Game > Mod Manager, then restart the game.
"""


def mod_line(mod: Path) -> str:
    """One line per bundled mod: its row in the README's table of bundled mods, else its manifest's first sentence."""
    manifest = json.loads((mod / "mod.json").read_text(encoding="utf-8"))
    readme = (PROJECT_ROOT / "README.md").read_text(encoding="utf-8")
    row = re.search(rf"^\s*\| `{re.escape(mod.name)}` [^|]*\| (.+?) \|\s*$", readme, re.MULTILINE)
    if row:
        summary = re.sub(r"\s*\(\[[^]]*\]\([^)]*\)\)", "", row.group(1))  # drop "([guide](relative/link))"
    else:
        summary = re.split(r"(?<=[.!?])\s", manifest.get("description", "").strip(), maxsplit=1)[0]
    return f"- **{manifest.get('name', mod.name)}** (`{mod.name}`): {summary}"


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
