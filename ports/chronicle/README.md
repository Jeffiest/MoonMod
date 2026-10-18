# MoonFactory for Chronicle (Dark Cloud PC port)

MoonFactory runs inside the Chronicle PC port, so it ships as a patch to the Chronicle source rather than as a
separate download. You build the game yourself from your own disc; nothing from the game is included here.

| File | What it is |
| :--- | :--- |
| `moonfactory-chronicle.patch` | All MoonFactory changes to Chronicle: the Lua and native-plugin runtime, the game adapter, the in-game Mod Manager, the engine changes it needs (256 monster slots, 48 x 48 floor grid, 64 rooms) and its tests. Includes Lua 5.5.1 (MIT, `port/third_party/lua-5.5.1/LUA-LICENSE.txt`). |
| `moonfactory-kazarov.patch` | The changes MoonFactory needs in the Kazarov renderer submodule (`tools/kazarov`): named input bindings for mods and the window hooks they use. |
| `apply-moonfactory.ps1` | Checks out the matching Chronicle commit and applies both patches. |

The patch is made against Chronicle commit `50eaff633e4e02e5dbc6a7a6a84c7e34688cb738` ("Player menu framework
(#189)"). It may not apply to later Chronicle commits until it is refreshed.

## What you need

- Your own copy of _Dark Cloud_ as a disc image (PAL recommended).
- Git, and everything Chronicle's own README lists for a Windows build.

## Steps (Windows, PowerShell)

1. Get Chronicle at the matching commit and apply the patch:

   ```powershell
   git clone --recurse-submodules https://github.com/TheMoonPeople/Chronicle.git
   .\MoonMod\ports\chronicle\apply-moonfactory.ps1 -Chronicle .\Chronicle
   ```

   The script stops if the Chronicle folder has uncommitted changes. To apply by hand instead:

   ```powershell
   cd Chronicle
   git checkout 50eaff633e4e02e5dbc6a7a6a84c7e34688cb738
   git apply --whitespace=nowarn ..\MoonMod\ports\chronicle\moonfactory-chronicle.patch
   git -C tools\kazarov apply --whitespace=nowarn ..\..\..\MoonMod\ports\chronicle\moonfactory-kazarov.patch
   ```

2. Put your disc image where Chronicle expects it, for example `rom/pal/Dark Cloud (PAL).iso`.

3. Build and run with Chronicle's own scripts:

   ```powershell
   .\build.bat windows-x64-release
   .\run.bat windows-x64-release
   ```

   The first run extracts the game data from your disc image.

## Adding mods

- Put each mod in its own folder under `mods\` in the save folder (or next to the game's `.exe`). A mod folder
  holds `mod.json` and its Lua entry script; see `examples/` and `mods/` in this repository.
- New mods start disabled. Turn them on in **Options -> Game -> Mod Manager**. Lua changes need only a restart.
- Native (DLL) mods also need to be marked trusted in the Mod Manager before they load.

## Current limits

- Chronicle Two is not covered by this patch yet.
- The walk-through exit room and the older "seamless floor progression" code are in the patch but switched off:
  both were unfinished, and the seamless mode forced the player onto the next floor. The normal continue/leave
  window is used.
- `game.player.set` cannot raise max HP; it sets current HP or water only.
- A dense `dungeons.set_layout` (for example 50 rooms) may build a few rooms fewer than asked, because the
  corridors use up the space.
