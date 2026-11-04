#!/usr/bin/env python3
"""MoonFactory's command line: start a mod, and find and install other people's.

    moonfactory new author.my-mod                     a new mod from the tested starter
    moonfactory index mods/ --base-url URL            zip each mod and write the catalogue (index.json) of them
    moonfactory search [words] [--index URL]          the catalogue's mods, or those matching the words
    moonfactory install ID --mods <game>/mods         download a mod (and what it needs), check it, unpack it
    moonfactory list --mods <game>/mods               the mods installed there, and which have updates

The catalogue is a JSON file: {"format_version": 1, "mods": [{id, name, version, author, description, games,
dependencies, url, sha256, size}]}. The bundled mods' catalogue is published with every change to them, as the
`mod-index` release of the MoonMod repository (DEFAULT_INDEX); anyone can publish one of their own and pass --index.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import shutil
import tempfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MOD_ID = re.compile(r"^[a-z0-9][a-z0-9._-]{2,63}$")
DEFAULT_INDEX = "https://github.com/Jeffiest/MoonMod/releases/download/mod-index/index.json"
MAX_ZIP = 64 * 1024 * 1024        # a mod archive, downloaded
MAX_UNPACKED = 256 * 1024 * 1024  # and unpacked


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



# ---------------------------------------------------------------------------------------------------------------------
# The catalogue


def version_key(version: str) -> tuple:
    """1.10.0 sorts after 1.9.2; a part that isn't a number sorts as 0."""
    return tuple(int(p) if p.isdigit() else 0 for p in re.split(r"[.+-]", str(version)))


def read_manifest(folder: Path) -> dict:
    manifest = json.loads((folder / "mod.json").read_text(encoding="utf-8"))
    if not MOD_ID.fullmatch(str(manifest.get("id", ""))):
        raise ValueError(f"{folder}: mod.json has no valid id")
    return manifest


def pack_mod(folder: Path, out_dir: Path) -> tuple[Path, dict]:
    """The mod as <id>-<version>.zip, its files under <id>/ in a fixed order (the same files give the same bytes)."""
    manifest = read_manifest(folder)
    out_dir.mkdir(parents=True, exist_ok=True)
    archive = out_dir / f"{manifest['id']}-{manifest.get('version', '0')}.zip"
    files = sorted(p for p in folder.rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for path in files:
            info = zipfile.ZipInfo(f"{manifest['id']}/{path.relative_to(folder).as_posix()}", date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, path.read_bytes())
    return archive, manifest


def build_index(mods_dir: Path, out_dir: Path, base_url: str) -> Path:
    """Every mod folder under mods_dir zipped into out_dir, with out_dir/index.json naming them."""
    entries = []
    for folder in sorted(p for p in mods_dir.iterdir() if (p / "mod.json").is_file()):
        archive, m = pack_mod(folder, out_dir)
        data = archive.read_bytes()
        entries.append({
            "id": m["id"], "name": m.get("name", m["id"]), "version": m.get("version", "0"), "author": m.get("author", ""),
            "description": m.get("description", ""), "games": m.get("games", []), "dependencies": m.get("dependencies", []),
            "url": urllib.parse.urljoin(base_url.rstrip("/") + "/", archive.name),
            "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
    index = out_dir / "index.json"
    index.write_text(json.dumps({"format_version": 1, "mods": entries}, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return index


def fetch(url_or_path: str) -> bytes:
    """A URL's bytes, or a local file's."""
    if re.match(r"^[a-z]+://", url_or_path):
        with urllib.request.urlopen(url_or_path, timeout=60) as response:
            data = response.read(MAX_ZIP + 1)
        if len(data) > MAX_ZIP:
            raise ValueError(f"{url_or_path} is larger than {MAX_ZIP} bytes")
        return data
    return Path(url_or_path).expanduser().read_bytes()


def load_index(index: str) -> list[dict]:
    data = json.loads(fetch(index).decode("utf-8"))
    if data.get("format_version") != 1 or not isinstance(data.get("mods"), list):
        raise ValueError(f"{index} is not a MoonFactory catalogue")
    mods = [m for m in data["mods"] if isinstance(m, dict) and MOD_ID.fullmatch(str(m.get("id", "")))]
    # an entry's url may be relative to the catalogue
    for m in mods:
        if not re.match(r"^[a-z]+://", m.get("url", "")) and not Path(m.get("url", "")).is_absolute():
            m["url"] = urllib.parse.urljoin(index, m["url"]) if re.match(r"^[a-z]+://", index) else str(Path(index).parent / m["url"])
    return mods


def search(mods: list[dict], words: list[str]) -> list[dict]:
    found = []
    for m in mods:
        text = " ".join(str(m.get(k, "")) for k in ("id", "name", "author", "description")).lower()
        if all(w.lower() in text for w in words):
            found.append(m)
    return found


def installed(mods_folder: Path) -> dict[str, dict]:
    out = {}
    if mods_folder.is_dir():
        for folder in mods_folder.iterdir():
            try:
                m = read_manifest(folder)
            except (OSError, ValueError, json.JSONDecodeError):
                continue
            out[m["id"]] = m
    return out


def _unpack(data: bytes, mod_id: str, into: Path) -> None:
    """The archive's <mod_id>/ files into `into`, refusing anything that would land outside it."""
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        total = 0
        for info in z.infolist():
            name = info.filename
            if info.is_dir():
                continue
            parts = Path(name).parts
            if name.startswith(("/", "\\")) or ".." in parts or ":" in name or len(parts) < 2 or parts[0] != mod_id:
                raise ValueError(f"the archive holds a file outside {mod_id}/: {name}")
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f"the archive holds a symbolic link: {name}")
            total += info.file_size
            if total > MAX_UNPACKED:
                raise ValueError(f"the archive unpacks to more than {MAX_UNPACKED} bytes")
            target = into.joinpath(*parts[1:])
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(z.read(info))


def install(mod_id: str, index: str, mods_folder: Path, upgrade: bool = False, _seen: set | None = None) -> list[str]:
    """Download mod_id from the catalogue, check it, and unpack it into mods_folder/<id>, after the mods it depends
    on. Returns what was installed or upgraded, in order. An installed mod is left alone unless upgrade is set and the
    catalogue's is newer; an upgrade keeps the old folder as <id>.previous until the new one is in place."""
    seen = _seen if _seen is not None else set()
    if mod_id in seen:
        return []
    seen.add(mod_id)
    catalogue = {m["id"]: m for m in load_index(index)}
    entry = catalogue.get(mod_id)
    if entry is None:
        raise KeyError(f"{mod_id} is not in the catalogue")
    done = []
    for dep in entry.get("dependencies", []):
        done += install(dep, index, mods_folder, upgrade, seen)
    have = installed(mods_folder).get(mod_id)
    if have and not (upgrade and version_key(entry["version"]) > version_key(have.get("version", "0"))):
        return done
    data = fetch(entry["url"])
    if hashlib.sha256(data).hexdigest() != entry.get("sha256"):
        raise ValueError(f"{mod_id}: the download does not match the catalogue's checksum")
    mods_folder.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{mod_id}-", dir=mods_folder) as temporary:
        staged = Path(temporary) / mod_id
        staged.mkdir()
        _unpack(data, mod_id, staged)
        if read_manifest(staged)["id"] != mod_id:
            raise ValueError(f"{mod_id}: the archive's mod.json names another mod")
        target = mods_folder / mod_id
        previous = mods_folder / f"{mod_id}.previous"
        if target.exists():
            if previous.exists():
                shutil.rmtree(previous)
            target.rename(previous)
        staged.rename(target)
    done.append(mod_id)
    return done


def updates(mods_folder: Path, index: str) -> list[tuple[str, str, str | None]]:
    """(id, installed version, newer catalogue version or None) for each installed mod."""
    catalogue = {m["id"]: m for m in load_index(index)}
    out = []
    for mod_id, m in sorted(installed(mods_folder).items()):
        newer = catalogue.get(mod_id)
        out.append((mod_id, m.get("version", "0"),
                    newer["version"] if newer and version_key(newer["version"]) > version_key(m.get("version", "0")) else None))
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="moonfactory", description="Start a MoonFactory mod, and find and install others.")
    commands = parser.add_subparsers(dest="command", required=True)
    new = commands.add_parser("new", help="create a new mod package")
    new.add_argument("id", help="stable mod id, such as author.my-mod")
    new.add_argument("--output", type=Path, help="new package directory (defaults to ./<id>)")
    new.add_argument("--target", choices=("both", "chronicle", "chronicle-two"), default="both")
    new.add_argument("--name", help="display name stored in mod.json")
    idx = commands.add_parser("index", help="zip every mod in a folder and write the catalogue of them")
    idx.add_argument("mods", type=Path, help="a folder of mod folders, such as mods/")
    idx.add_argument("--out", type=Path, default=Path("dist/mod-index"))
    idx.add_argument("--base-url", default=DEFAULT_INDEX.rsplit("/", 1)[0] + "/",
                     help="where the zips will be downloaded from")
    find = commands.add_parser("search", help="the catalogue's mods, or those matching words")
    find.add_argument("words", nargs="*")
    find.add_argument("--index", default=DEFAULT_INDEX)
    inst = commands.add_parser("install", help="download, check and unpack mods (and what they need)")
    inst.add_argument("ids", nargs="+")
    inst.add_argument("--mods", type=Path, required=True, help="the game's mods folder")
    inst.add_argument("--index", default=DEFAULT_INDEX)
    inst.add_argument("--upgrade", action="store_true", help="replace an installed mod when the catalogue's is newer")
    lst = commands.add_parser("list", help="the mods installed in a folder, and which have updates")
    lst.add_argument("--mods", type=Path, required=True)
    lst.add_argument("--index", default=DEFAULT_INDEX)
    args = parser.parse_args(argv)

    try:
        if args.command == "new":
            output = args.output if args.output is not None else Path.cwd() / args.id
            package = create_package(args.id, output, args.target, args.name)
            print(f"Created {package}")
            print("Copy the package folder into <save>/mods, then enable it in the in-game MoonFactory manager.")
        elif args.command == "index":
            index = build_index(args.mods, args.out, args.base_url)
            print(f"Wrote {index} ({len(json.loads(index.read_text(encoding='utf-8'))['mods'])} mods)")
        elif args.command == "search":
            found = search(load_index(args.index), args.words)
            for m in found:
                print(f"{m['id']}  {m.get('version', '')}  {m.get('name', '')}")
                if m.get("description"):
                    print("    " + m["description"][:150] + ("..." if len(m["description"]) > 150 else ""))
            if not found:
                print("No mods match.")
        elif args.command == "install":
            done = []
            for mod_id in args.ids:
                done += install(mod_id, args.index, args.mods, args.upgrade)
            print("Installed: " + ", ".join(done) if done else "Nothing to do: already installed (use --upgrade for newer ones).")
            print("Enable new mods in the in-game Mod Manager.")
        elif args.command == "list":
            for mod_id, version, newer in updates(args.mods, args.index):
                print(f"{mod_id}  {version}" + (f"  (update: {newer})" if newer else ""))
    except (FileExistsError, FileNotFoundError, KeyError, ValueError, OSError, zipfile.BadZipFile) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
