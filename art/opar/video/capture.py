"""Opar showcase: capture every shot (vshot.ps1), every frame (60 a second), into shots/video/<name>_<frame>.png."""
import subprocess
import sys

PRE = "0\n200 start\n204\n500 start\n504\n700 down\n704\n720 down\n724\n800 cross\n804\n950 cross\n954\n"
FACE_CAMERA = "1800 128 255 128 128\n1812 128 128 128 128\n"
FACE_LEFT = "1800 0 128 128 128\n1806 128 128 128 128\n"
FREE = "\nfree"  # the director leaves the follow camera alone (shots where he travels)

# name: (turn, inputs, first frame, last frame, camera "distance height" and flags)
SHOTS = {
    "idle": (FACE_CAMERA, "", 1830, 1990, "150 25"),
    "run": ("", "1830 128 0 128 128\n1960 128 128 128 128\n", 1830, 1960, "150 30" + FREE),
    "spit": (FACE_LEFT, "1830 cross\n1834\n1846 cross\n1850\n1862 r2\n1866\n", 1826, 1930, "140 25"),
    "gob": (FACE_LEFT, "1830 cross\n1834\n1846 cross\n1850\n1862 cross\n1866\n1878 r2\n1882\n", 1826, 1960, "140 25"),
    "bubble": (FACE_LEFT, "1830 cross\n1920\n", 1826, 2010, "150 25"),
    "slide": ("", "1830 128 0 128 128\n1880 cross 128 0 128 128\n1884 128 0 128 128\n1890 128 128 128 128\n", 1856, 1970,
              "160 30" + FREE),
    "croak": (FACE_CAMERA, "1830 r2\n1834\n", 1826, 1930, "150 25"),
    "hop": (FACE_CAMERA, "1830 l2 128 255 128 128\n1834 128 255 128 128\n1838 128 128 128 128\n1880 cross\n1884\n", 1826,
            1990, "320 70"),
    "backhop": (FACE_CAMERA, "1830 l2\n1834\n", 1826, 1886, "150 25"),
    "slam": (FACE_CAMERA, "1830 cross\n2075\n", 2066, 2300, "200 45"),
}


def capture(name):
    turn, inputs, first, last, cam = SHOTS[name]
    at = ",".join(str(f) for f in range(first, last + 1))
    script = PRE + turn + inputs
    ps = ("& 'C:\\Users\\armor\\AppData\\Local\\Temp\\claude\\E--Moonmod\\4802d590-5ba4-453b-97df-ff78ca19c2de\\scratchpad\\vshot.ps1'"
          " -Name '%s' -Frames %d -Script $env:VSCRIPT -At '%s' -Shot '%s'" % (name, last + 10, at, cam))
    env = dict(__import__("os").environ, VSCRIPT=script)
    out = subprocess.run(["pwsh", "-NoProfile", "-Command", ps], capture_output=True, text=True, env=env)
    print(name, out.stdout.strip(), out.stderr.strip()[:200], flush=True)


if __name__ == "__main__":
    for name in (sys.argv[1:] or SHOTS):
        capture(name)
