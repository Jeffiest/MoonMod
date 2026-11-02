# Elden Ring reference animations

`ErReference` reads Elden Ring animations so the animation editor's *Reference* panel
([../editor/README.md](../editor/README.md)) can show them beside a character: a stick figure to watch how a roll,
a swing or a stagger moves while you pose your own keys on your own rig.

Everything it reads comes from your own copy of the game, and from animation repositories you downloaded yourself
(for example the Elden Ring Player Animation Repositories on Nexus Mods). Everything it writes goes to a cache
outside the repository, or, if you import one, into your own save. None of it is committed or shipped: these are
FromSoftware's animations.

## What you need

- Elden Ring installed (the `Game` folder with `Data0.bhd` … `Data3.bdt` and `oo2core_6_win64.dll`).
- DSAnimStudio unpacked somewhere (it has the libraries this builds against, and the archives' public keys in
  `Res/PEM/ER`). Nothing of it is copied here.
- The .NET 9 SDK.
- Optionally, downloaded animation repositories: folders of `.hkx` files already retargeted onto the player's
  skeleton (`c0000`), one folder per character.

## Build and extract

```bash
dotnet build tools/anim/reference -c Release -p:DsasDir="C:/path/to/DSAnimStudio"
```

```bash
tools/anim/reference/bin/Release/net9.0/ErReference.exe extract "C:/path/to/ELDEN RING/Game" "C:/path/to/DSAnimStudio/Res/PEM/ER" "$LOCALAPPDATA/Moonmod/reference" "C:/path/to/a repository"
```

`extract` decrypts the archive headers, finds `chr/c0000.anibnd.dcx` and `chr/c0000_a00_hi.anibnd.dcx`, and writes
the player's `skeleton.hkx`, the game's own player animations (`game/a000/*.hkx`, about 1,200, with the
`types.compendium` they share) and `reference.json` (this program's path and the repository folders) into the cache.
Run it again to add or change repositories.

The editor's server finds the cache at `%LOCALAPPDATA%/Moonmod/reference` (or `--reference`, or the
`MOONANIM_REFERENCE` environment variable) and, the first time you show an animation, runs
`ErReference decode <cache> <animation.hkx> <out.json>`, keeping the result in the cache's `decoded` folder.

## What a decoded animation holds

`frame_time` and `frames`, the skeleton's `bones` and `parents`, its `rest` pose, and per frame every bone's
model-space position (`p`) and local rotation and translation (`l`), with the root motion (`root`: x, y, z, yaw per
frame). The game's space has Y up and the character facing −Z; the editor turns the figure to face +Z.

## Finding an animation

The game's player table names animations `a000_XXXXXX`. A few worth knowing: `a000_027000`–`027030` are short
steps, `a000_027100`–`027107` the medium-weight rolls (`027100` forward, `027101` back, `027102` to
the left, `027103` to the right), `027110`–`027127` the heavier rolls, `027140`–`027143` the light quick ones, and `027500`–`027507` a jump
roll. A repository's own files follow its folders.

Weapon movesets are groups of their own, numbered as in Dark Souls III: `a023` straight sword, `a028` curved sword,
`a029` katana, and so on. Within one, `030000`–`030040` are the one-handed light (R1) chain, `030200` and `030210` the
first and second heavy (R2), `030300` the attack out of a roll, `030400` the running attack, `030500` a step and strike,
`030505` a lunging thrust and `030700` the guard counter. `032xxx` are the two-handed versions.

## Importing one into your save

`import_motion.py` retargets a reference animation onto a character and puts it in place of one motion a mod already
plays, in your save only:

```bash
python tools/anim/reference/import_motion.py --save "C:/path/to/save" --mod moonmod.vigil --motion toan_dive_roll --anim game/a000/a000_027100.hkx --to 40
```

```bash
python tools/anim/reference/import_motion.py --save "C:/path/to/save" --mod moonmod.vigil --motion toan_dive_roll --restore
```

- `--anim` is a path as the Reference panel lists it (group, then file), or a `.hkx` file in the cache's game folder
  or one of its repositories. `--from`/`--to` pick the frames to use.
- The result is fitted to the replaced motion's length and keeps its speed, so the mod's lunge still matches.
  `--length N` sets another length, and `--own-timing` keeps the animation's own 30 frames a second.
- It starts on the replaced motion's own first pose and ends on its last, two frames each way, so it blends in and
  out as the mod's own did.
- `--blow` lines the reference's blow (the frame its blade's tip moves fastest) up with the replaced motion's, so a
  move's hits, timed as fractions of its motion, still land on the swing. With `--blow`, `--from`/`--to` default to a
  window around the blow (18 frames before, 24 after).
- The sword follows: his blade is aimed along the reference's weapon bone every frame.
- The mod's own file is kept as `<motion>.json.original` the first time, and `--restore` puts it back. Updating the mod
  (a new release, or syncing a play copy from the repository) replaces the import with the mod's own motion again;
  run the import again after.
- It refuses to write inside the repository. Characters: Toan so far (`CHARACTERS` in the script maps a rig's bones
  to the reference skeleton's; another character is one more entry).

## A whole moveset

A moveset file names the mod and, for each of its motions, the animation to put there (with `from`, `to` and `blow`
as above; `blow` is on by default here). `movesets/toan_straight_sword.json` fills Vigil's eight attack slots for Toan
from the straight sword (`a023`):

```bash
python tools/anim/reference/import_motion.py --save "C:/path/to/save" --moveset tools/anim/reference/movesets/toan_straight_sword.json
```

```bash
python tools/anim/reference/import_motion.py --save "C:/path/to/save" --moveset tools/anim/reference/movesets/toan_straight_sword.json --restore
```

A moveset file holds only names and paths into your cache, nothing of the game, so another set (curved sword, katana)
is a copy with other paths.

## How the retarget works

The retarget turns his pelvis, chest, neck and head from his idle pose the way the reference's turn from its rest pose,
puts his pelvis at the reference's height (scaled to his), and places his hands and feet by IK relative to his
shoulders and hips, scaled by limb length, with the elbows and knees bending toward the reference's.
