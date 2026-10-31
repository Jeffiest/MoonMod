# MoonFactory for Chronicle (Dark Cloud PC port)

MoonFactory runs inside the Chronicle PC port, so it ships as changes to the Chronicle source. You build the game
yourself from your own disc; nothing from the game is included here.

A **MoonMod release** is a folder named after the Chronicle commit it is made for, such as `MoonMod-9418a550`.
It holds the Chronicle files MoonMod changes, already patched, at the same paths as in Chronicle, plus a `mods`
folder. Copy it over a Chronicle checkout at that commit, replace the files, and build. A new MoonMod version
normally means Chronicle moved and MoonMod was reworked for it.

| File | What it is |
| :--- | :--- |
| `moonfactory-chronicle.patch` | All MoonFactory changes to Chronicle: the Lua and native-plugin runtime, the game adapter, the in-game Mod Manager, mod title modes and sandbox sessions, the engine changes it needs (256 monster slots, 48 x 48 floor grid, 64 rooms) and its tests. Includes Lua 5.5.1 (MIT, `port/third_party/lua-5.5.1/LUA-LICENSE.txt`). |
| `moonfactory-kazarov.patch` | The changes MoonFactory needs in the Kazarov renderer submodule (`tools/kazarov`): named input bindings for mods and the window hooks they use. |
| `apply-moonfactory.ps1` | Checks out the matching Chronicle commit and applies both patches. |
| `CHRONICLE_COMMIT` | The Chronicle commit the patches are made against, and so the MoonMod version. |

The patch is made against Chronicle commit `9418a5506e2a08e7739aa68d70841df6bc516201` ("Lift map parts by
retail's depth-scaled height at each point"), the master after `d3666bcb` forked the game into `port/src/game`.
It may not apply to later Chronicle commits until it is refreshed. The Kazarov patch is made against the Kazarov
commit that master pins, `b619d1a`.

The Mod Manager is drawn with the game's UI framework (`ui::` windows, labels, tab plate, cursor and brackets,
scroll and progress bars, confirm modal), so it matches the game's other menus and takes the same mouse input.

## How the patch is laid out

Since `d3666bcb` the port compiles its own fork of the game (`port/src/game`, `port/include/game`, namespace
`dc::game`) and `ps2/` is only the byte-matching decomp, so the patch edits the game's code in place:

- `port/src/moonmod/` and `port/include/moonmod/`: the runtime, the Lua and native-plugin hosts, the Chronicle
  adapter, title modes and sandbox sessions, and the game-side helpers (`*_moonmod.cpp`, `dungeonmap_layout.cpp`,
  `exit_room.cpp`, `mod_model.cpp`, `mod_texture.cpp`, `item_icon_override.cpp`). `moonmod/game_hooks.hpp`
  declares the hooks the game's units call.
- `port/src/game/` and `port/include/game/`: the capacity changes (`MONSTOR_SLOT_MAX` 256, `DNG_GRID` 48,
  `DNG_ROOM_MAX` 64, 64 chests, 384 events, 56 Georama plots, 32 weapon slots after retail's, items 377-408) and
  the hook calls, marked with a comment where they sit.
- `port/src/title/title_menu.*`: a row on the title menu for each mod title mode, between OPTION and EXIT.
- `port/src/options/`, `port/src/ui/journal_character.*`, `port/src/battlemenu/main_ring.cpp`: the Mod Manager,
  its Options row and ring slot, and the Journal's Character page.
- `port/src/tests/moonmod_*_test.cpp`: the tests. `darkcloud_tests --gtest_filter='MoonMod*'` runs them.

Upstream's native autosave (on each town and dungeon floor) is kept; it writes nothing during a sandbox session.

## What you need

- Your own copy of _Dark Cloud_ as a disc image (PAL recommended).
- Git, and everything Chronicle's own README lists for a Windows build.

## Install a release (Windows, PowerShell)

The [release page](https://github.com/Jeffiest/MoonMod/releases/latest) has the full how-to, with updating,
going back to plain Chronicle and troubleshooting; `MoonMod-README.txt` in the zip holds the same text. In short:

1. Download `MoonMod-<commit>.zip` from the [releases](https://github.com/Jeffiest/MoonMod/releases) and unzip it.
2. Get Chronicle at that commit (the full hash is on the release page and in `MoonMod-README.txt`):

   ```powershell
   git clone --recurse-submodules https://github.com/TheMoonPeople/Chronicle.git
   cd Chronicle
   git checkout 9418a5506e2a08e7739aa68d70841df6bc516201
   git submodule update --init --recursive
   ```

3. Copy everything inside the `MoonMod-<commit>` folder into the `Chronicle` folder and choose **Replace the files
   in the destination**. This also adds `Chronicle\mods` with the bundled mods.
4. Put your disc image in `rom\pal`, then `.\build.bat windows-x64-release` and `.\run.bat windows-x64-release`
   (steps 2 and 3 below). If the build warns that MoonMod is made for another Chronicle commit, the checkout is
   not at the release's commit.

To go back to plain Chronicle, run `git checkout -- .` in `Chronicle` and in `Chronicle\tools\kazarov`, and delete
the new files `git status` lists.

## Build from the patch (Windows, PowerShell)

1. Get Chronicle at the matching commit and apply the patch:

   ```powershell
   git clone --recurse-submodules https://github.com/TheMoonPeople/Chronicle.git
   .\MoonMod\ports\chronicle\apply-moonfactory.ps1 -Chronicle .\Chronicle
   ```

   The script stops if the Chronicle folder has uncommitted changes. To apply by hand instead:

   ```powershell
   cd Chronicle
   git checkout 9418a5506e2a08e7739aa68d70841df6bc516201
   git apply --whitespace=nowarn ..\MoonMod\ports\chronicle\moonfactory-chronicle.patch
   git -C tools\kazarov apply --whitespace=nowarn ..\..\..\MoonMod\ports\chronicle\moonfactory-kazarov.patch
   ```

2. Put your disc image where Chronicle expects it, for example `rom/pal/Dark Cloud (PAL).iso`.

3. Build and run with Chronicle's own scripts (the first build downloads Chronicle's pinned Windows toolchain,
   Rust and FFmpeg included, into `.kazarov/windows`):

   ```powershell
   .\build.bat windows-x64-release
   .\run.bat windows-x64-release
   ```

   The first run extracts the game data from your disc image.

## Adding mods

- Put each mod in its own folder in `Chronicle\mods` (the release creates it). A mod folder holds `mod.json` and
  its Lua entry script; see `examples/` and `mods/` in this repository.
- The game reads mods from one folder only, so a package never shows up twice: `mods` in the Chronicle checkout it
  was built in (found by walking up from the executable to the folder holding `kazarov.conf`); if there is none,
  `mods` beside the executable; otherwise `mods` in the save folder (`port\run\save\mods` with `run.bat`). The
  game's log names the folder it uses (`moonmod: mods folder ...`).
- New mods start disabled. Turn them on in **Options -> Game -> Mod Manager**. Lua changes need only a restart.
- Native (DLL) mods also need to be marked trusted in the Mod Manager before they load.

## Making a release

A release is made for one Chronicle commit, and its version is that commit's first 8 characters.

1. Refresh the patches against the new Chronicle `master` commit and test them, as for any port change. In a
   Chronicle checkout with the patches applied, regenerate the game patch with
   `git add -A && git diff --cached --abbrev=8 HEAD > moonfactory-chronicle.patch`.
2. Put the new full commit hash in `CHRONICLE_COMMIT` and in `set(MOONMOD_CHRONICLE_COMMIT ...)` in the patch
   (`port/CMakeLists.txt`); `make_release.py` refuses to run when the two differ.
3. Build the folder and zip with `python tools/make_release.py` (add `--chronicle <path>` to copy from a local
   clone instead of GitHub). They land in `dist/`. Or run **Actions > release > Run workflow** on GitHub, which
   builds them and publishes the GitHub release `MoonMod-<commit>`. Pushes to `main` that touch the port, the mods
   or the script also build them, as a workflow artifact only.

The script applies both patches to a fresh checkout of that commit, copies every file they add or change, and
adds `mods/` with each bundled mod plus `MoonMod-README.txt` (the how-to and the file list). The same how-to,
written by the script, becomes the release page (`dist/MoonMod-<commit>-notes.md`). It stops if a patch
deletes or renames a file, because a pasted folder cannot do that.

## Current limits

- Chronicle Two is not covered by this patch yet.
- The walk-through exit room and the older "seamless floor progression" code are in the patch but switched off:
  both were unfinished, and the seamless mode forced the player onto the next floor. The normal continue/leave
  window is used.
- `game.player.set` cannot raise max HP; it sets current HP or water only.
- A dense `dungeons.set_layout` (for example 50 rooms) may build a few rooms fewer than asked, because the
  corridors use up the space.
