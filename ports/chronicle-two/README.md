# MoonFactory for Chronicle Two

This integration embeds MoonMod / MoonFactory in the Chronicle Two PC port. It includes the
shared Lua and native plugin runtime, Chronicle Two adapter, Mod Manager, game hooks, vendored
Lua 5.5.1, native tests, and a two-launch executable smoke test. No retail data is distributed.

The supported source revision is **7a7d7f29ae544a04e65634278d244b785d801066** of
[TheMoonPeople/ChronicleTwo](https://github.com/TheMoonPeople/ChronicleTwo) (its `master` of November 2, 2026),
with Kazarov at **fd72338a6aebf5c119947bb3150bba580217fec9**, the submodule commit that revision pins. The
installer pins these revisions; applying this patch to newer upstream source is not verified.

| File | Purpose |
| --- | --- |
| `moonfactory-chronicle-two.patch` | Game adapter, runtime, UI, engine hooks, and tests. |
| `moonfactory-kazarov.patch` | Required digital/analog input polling in the Kazarov submodule, the camera matching the aerial dungeon map needs (a tick that draws through several cameras keeps each one's interpolation), the movie muxer building with FFmpeg 6 as well as 7, and the web build's changes under `__EMSCRIPTEN__`. |
| `apply-moonfactory.ps1` | Pins source revisions, checks both patches, and applies them. |
| `verify-headless.ps1` | Builds and runs the Chronicle Two MoonMod native tests; optionally checks executable startup. |

## How the patch is laid out

Chronicle Two now keeps its native game sources in `port/` itself (`port/src/<domain>/<unit>.cpp`, declarations in
`port/include/`), so MoonFactory edits them in place; there is no build-time copy of `ps2/src` to patch any more, and
the patch does not touch `ps2/` at all. MoonFactory's own code lives in `port/src/moonmod/` and
`port/include/moonmod/`, with its Lua 5.5.1 in `port/third_party/lua-5.5.1/`. The game's code carries only what has to
live there: capacity constants (`AUTOMAP_ROOM_MAX`, the item and weapon table sizes, the dungeon grid's room for mod
floors), one-line hooks that call into `port/src/moonmod/`, and the declarations those hooks need in
`port/include/stubs/<unit>.hpp`.

Chronicle Two runs its own scripts in Luau, and its `lua.h` is on the game's include path. MoonFactory's Lua is a
separate C library (`moonmod_lua`) whose headers `port/src/moonmod/lua_runtime.cpp` includes by path; Luau's API is
C++-linked and Lua's is C-linked, so both link into one executable.

The patch also carries the aerial dungeon map (`port/src/object/dun/automap.cpp`, `port/src/aerial_keys.cpp`): the map shows a live render of the floor from above instead of the flat tiles. F1/F2 change the map size, F5/F6 the model size, F7/Shift+F7 the zoom and Shift+F5/F6 the ceiling cut; each is saved to `config.json` (`aerial_map`, `aerial_map_size`, `aerial_map_model_scale`, `aerial_map_zoom`, `aerial_map_ceiling`). Set `aerial_map` to false for the retail map.

## Install and play on Windows

You need your own PAL Dark Chronicle disc image, PowerShell 7, Git, and the build prerequisites
in Chronicle Two's README. Keep MoonMod and ChronicleTwo beside each other:

If using the local source ZIP, extract its `MoonMod` folder and skip the MoonMod clone below.

```powershell
git clone https://github.com/Jeffiest/MoonMod.git
git clone --recurse-submodules https://github.com/TheMoonPeople/ChronicleTwo.git
pwsh -File .\MoonMod\ports\chronicle-two\apply-moonfactory.ps1 -ChronicleTwo .\ChronicleTwo
```

The installer requires clean game and submodule checkouts, including untracked files. It switches
Chronicle Two to the supported commit with a detached HEAD, initializes its submodules, and checks
both patches before applying either. To check an already pinned, clean checkout without changing
files, add `-CheckOnly`. Do not run a submodule update after applying the Kazarov patch.

Place `Dark Chronicle (PAL).iso` in `ChronicleTwo\rom\pal\`, then:

```powershell
cd .\ChronicleTwo
.\build.bat windows-x64-release
.\run.bat windows-x64-release
```

Copy `MoonMod\examples\first-steps` into `mods\first-steps` in the game's save directory
or beside `darkchronicle.exe`. Open **Options -> Game -> Mod Manager**, enable it, and restart the game.
Packages start disabled. ON/OFF changes apply after restarting; a `*` marks a pending change.
Restart to reload Lua changes. Native DLL packages additionally require
explicit local trust in the manager. The existing `moonmod` Lua API and save-directory names stay stable.

## Verify

After configuring a PC build with `CT_BUILD_TESTS=ON` (the default):

```powershell
pwsh -File .\MoonMod\ports\chronicle-two\verify-headless.ps1 -BuildDirectory .\ChronicleTwo\port\build\YOUR_BUILD
pwsh -File .\MoonMod\ports\chronicle-two\verify-headless.ps1 -BuildDirectory .\ChronicleTwo\port\build\YOUR_BUILD -NoBuild -StartupSmoke
```

Use the actual build directory containing `CMakeCache.txt`. Each native case runs in a separate
process. The optional Vulkan startup smoke uses empty synthetic data and an isolated save directory
under the build directory; it loads a Lua package twice and checks API reporting, persistence,
and PNG creation. It does not establish retail gameplay or screenshot correctness.

The First Steps integration test finds a sibling `MoonMod` or `MoonFactory` checkout. For another
layout, configure with `-DMOONFACTORY_FIRST_STEPS_PATH=C:/path/to/examples/first-steps`.

## Limits

This is an experimental integration pinned to the source above. Read `docs/API.md` and query
capabilities before using game operations. The broader roadmap and historical verification artifacts
describe work from the original development workspace; they are not a new retail validation of this
distributed patch. Authored model rigs, fighting styles, independent dungeon graphs, and other open
items remain unsupported. Test with an isolated save before using an existing playthrough.

## Regenerated on November 8, 2026

Both patches are now generated from Jeffiest/ChronicleTwo's `claude/dark-cloud-2-engine-yr3rlk` branch with its
`tools/gauntlet/export_moonmod_patch.py --committed --check`, so they carry that branch's Dark Cloud 2 engine work:
raised capacities (`port/include/capacity.hpp`, listed in `port/docs/capacity.md`), co-op for Chronicle Two
(`port/docs/COOP.md`) and content registration (`port/docs/CONTENT.md`). The pins are unchanged: ChronicleTwo
`7a7d7f29` and Kazarov `fd72338a`. Both patches apply cleanly to them. The branch's gauntlet passed on Linux with
software Vulkan, as `tools/gauntlet/report/merged-20261108` there records. That covers the build, the CPU suite with
no new failure, every MoonMod case, the co-op relay with two games and the web build. Nothing ran with retail data.

## Verification on November 2, 2026

The patches were rebuilt for ChronicleTwo `7a7d7f29` and Kazarov `fd72338a` and apply cleanly to a fresh recursive
checkout of both (`git apply --check`, as the `patches` workflow does). A Linux Debug build (clang 20 with libc++,
Rust 1.99, SDL 3.4, Ubuntu's FFmpeg 6.1 instead of Kazarov's pinned 9.0) built `darkchronicle` and
`darkchronicle_tests`. With software Vulkan (llvmpipe):

- 78 of the 80 `MoonMod*` native cases pass. First Steps skips when the example package is not beside the
  checkout, and `MoonModManagerUi.ChangesTypedSettingsNotifiesModsAndSurvivesReload` fails: its skill-tree mouse expectation fails against the manager code the previous patch already shipped (neither the
  test nor `manager_ui.cpp` changed in this port);
- the changed upstream suites (`DataRead`, `SaveSlotTest`, `EventRuntimeMemory`, `TestHooks`, `NativeDungeon`,
  monster and Luau runtime cases) and upstream's `NativeArchitecture.Check` pass;
- `Smoke.HeadlessFramesScreenshot` and the two-launch `MoonMod.HeadlessProbe` pass;
- of the full CPU suite (2419 cases, 68 of them skipping without retail data), 13 fail. The other failures are upstream's log-file, crash-handler and
  Vulkan-validation-layer cases, which this patch does not touch and which fail in that container.

What changed upstream, and how the port follows it:

- **Monster slots.** `MONSTER_ACTIVE_MAX` is now 60 and the dungeon's monster characters start at
  `DNG_CHARA_SLOT_MONSTER` (24); the manager reaches its monsters through `GetActiveMonster(slot)` and
  `GetScene()`. Entity handles, despawn and the spawn path use those, and `entities.set_active_limit` overrides
  the port's own sight limit (5, or more with the `more_monsters` setting) only when a mod sets it.
- **Data tables are JSON.** Dungeon maps and floor tables (`dmap<n>.cfg.json`, `dflr<n>.cfg.json`), treasure
  tables and the map catalog (`map<n>.cfg.json`) are native documents. Mod floors are reserved in both the JSON and
  the text-script grid allocation, and mod floors inherit their source floor's treasure in `LoadTreasureBoxInfo`.
- **Scripts are Luau modules.** A `.stb` file is loaded as a handle naming its Luau module, so resource overrides
  no longer replace `.stb` scripts; model (`.chr`) and map overrides still load through the data reader.
- **File loading** goes through Kazarov's virtual file system; overrides are read as host files with the same size
  limits as before.
- **Saves** are JSON documents, and `SaveSlotWriteAutosave` writes them too. The mod floor sidecar is written for
  autosaves as well as manual saves, and is keyed by the save counter and the save's `CSaveDataDungeon`, which round
  trips exactly (the whole `CSaveData` no longer does).
- **Georama layouts** (placed pieces, houses, river grids) are kept in a `TownLayout` beside each town's save record
  (`port/src/save_json.hpp`), not in `CEditData`'s arrays; `georama.get`, `georama.place` and `georama.remove` read it.
- **Map names load earlier.** The catalog is read before the first scene event, as the previous patch arranged, so
  mods can list and register locations from it on the title screen.

No retail data was used: these checks do not establish a full playthrough, existing-save compatibility, a Windows
build, or support for newer upstream commits. Run `verify-headless.ps1 -StartupSmoke` on a Windows build to check it
there.
