"""Prevent the distributed port snapshot from silently lagging the shared runtime."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "ports/chronicle-two/moonfactory-chronicle-two.patch"


def added_files():
    files = {}
    path = None
    added = False
    body = []
    for line in PATCH.read_text(encoding="utf-8").splitlines(keepends=True):
        if line.startswith("diff --git "):
            if added and path:
                files[path] = "".join(body)
            path = line.rstrip("\n").split(" b/", 1)[1]
            added = False
            body = []
        elif line.startswith("new file mode "):
            added = True
        elif added and line.startswith("+") and not line.startswith("+++ "):
            body.append(line[1:])
    if added and path:
        files[path] = "".join(body)
    return files


class ChronicleTwoPortTests(unittest.TestCase):
    def test_embedded_runtime_matches_shared_source(self):
        files = added_files()
        for source, destination in [("src", "port/src/moonmod"), ("include/moonmod", "port/include/moonmod")]:
            for path in (ROOT / source).iterdir():
                if not path.is_file():
                    continue
                with self.subTest(file=path.name):
                    self.assertEqual(files.get(f"{destination}/{path.name}"), path.read_text(encoding="utf-8"))

    def test_embedded_lua_matches_vendored_source(self):
        files = added_files()
        for path in (ROOT / "vendor/lua-5.5.1/src").iterdir():
            if path.suffix not in (".c", ".h"):
                continue
            with self.subTest(file=path.name):
                self.assertEqual(files.get(f"port/third_party/lua-5.5.1/{path.name}"), path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
