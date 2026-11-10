#!/usr/bin/env python3
"""Check the repository's Markdown: every relative link must lead to a file, and every #anchor to a heading.

    python tools/check_docs.py

Links to other sites are not fetched. Exits 1 and lists what is broken, as `file:line: target`.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)|!\[[^\]]*\]\(([^)\s]+)\)")
SKIP = ("vendor/", "mods/moonmod.pack/docs/")  # third-party text, and copies the pack builder makes


def slug(heading: str) -> str:
    """GitHub's anchor for a heading."""
    heading = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading.strip().lower())
    return re.sub(r"[^\w\- ]", "", heading).replace(" ", "-")


def prose(path: Path):
    """The file's lines outside code fences, with inline code blanked, as (number, text)."""
    fence = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if not fence:
            yield number, line


def anchors(path: Path, cache: dict[Path, set[str]]) -> set[str]:
    if path not in cache:
        found: set[str] = set()
        for _, line in prose(path):
            match = re.match(r"#{1,6}\s+(.*)", line)
            if match:
                base, name, count = slug(match.group(1)), slug(match.group(1)), 0
                while name in found:  # GitHub numbers a repeated heading: name, name-1, name-2
                    count += 1
                    name = f"{base}-{count}"
                found.add(name)
            found.update(re.findall(r'<a (?:name|id)="([^"]+)"', line))
        cache[path] = found
    return cache[path]


def main() -> int:
    files = subprocess.run(["git", "ls-files", "*.md"], cwd=ROOT, capture_output=True, text=True, check=True)
    cache: dict[Path, set[str]] = {}
    broken = []
    for name in files.stdout.splitlines():
        if name.startswith(SKIP):
            continue
        path = ROOT / name
        if not path.exists():
            continue
        for number, line in prose(path):
            for match in LINK.finditer(re.sub(r"`[^`]*`", "", line)):
                target = match.group(1) or match.group(2)
                if re.match(r"[a-z][a-z0-9+.-]*:", target):
                    continue
                file_part, _, anchor = target.partition("#")
                linked = (path.parent / file_part).resolve() if file_part else path
                if not linked.exists():
                    broken.append(f"{name}:{number}: {target} (no such file)")
                elif anchor and linked.suffix == ".md" and anchor.lower() not in anchors(linked, cache):
                    broken.append(f"{name}:{number}: {target} (no such heading)")
    for entry in broken:
        print(entry)
    print(f"{len(broken)} broken link(s)" if broken else "all Markdown links resolve")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
