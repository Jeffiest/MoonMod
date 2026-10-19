# MoonFactory for Chronicle Two

This integration embeds MoonMod / MoonFactory in the Chronicle Two PC port. It includes the
shared Lua and native plugin runtime, Chronicle Two adapter, Mod Manager, game hooks, vendored
Lua 5.5.1, native tests, and a two-launch executable smoke test. No retail data is distributed.

The supported source revision is **9b7794d51dce6ed59fd56c0a343bb2ed8c3a1e55** of
[TheMoonPeople/ChronicleTwo](https://github.com/TheMoonPeople/ChronicleTwo), with Kazarov at
**25a4c5a89ae736517a467b5e05dea4894c255afc**. The installer pins these revisions;
applying this patch to newer upstream source is not verified.

| File | Purpose |
| --- | --- |
| `moonfactory-chronicle-two.patch` | Game adapter, runtime, UI, engine hooks, and tests. |
| `moonfactory-kazarov.patch` | Required digital/analog input polling in the Kazarov submodule. |
| `apply-moonfactory.ps1` | Pins source revisions, checks both patches, and applies them. |
| `verify-headless.ps1` | Builds and runs the Chronicle Two MoonMod native tests; optionally checks executable startup. |

## How the patch is laid out

MoonFactory's code lives in `port/`: the runtime and adapter in `port/src/moonmod/`, replacement functions as `PORT_OVERRIDE` copies in `port/src/`, and the declarations the port needs in `port/include/stubs/<unit>.hpp` and `port/include/moonmod/`. The edits under `ps2/` are capacity constants (`AUTOMAP_ROOM_MAX`, the save-data floor range, the item and weapon table sizes) and one-line hooks, all inside `#ifdef PORT`, so without `PORT` every `ps2/src` unit preprocesses to exactly the upstream text and the PS2 build is unchanged (checked unit by unit when the patch is refreshed).

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

## Verification on October 18, 2026

The distributed patches were applied to a fresh checkout and compared against the compiled sources.
Both the game and native test executable built successfully. All 18 Python tests and all 80 MoonMod
native cases passed, along with the two-launch executable startup test. Of 59 selected engine cases,
57 passed and two retail-file cases skipped under the intentionally empty native fixture.

Separate runs with an existing PAL extraction and isolated saves verified the manager Journal screen,
data-only item use, weapon registration/equip, a quest weapon reward, native pickup events, entry into
an appended dungeon floor, camera adjustment, and registered enemy spawn/defeat events. See
`artifacts/chronicle-two-port-verification.json` for the checked markers and patch hashes. These checks
do not establish a full playthrough, existing-save compatibility, or support for newer upstream commits.
