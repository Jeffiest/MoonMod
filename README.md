# MoonMod

MoonMod is the home of **MoonFactory** (Moon Factory), a mod framework for the PC ports of Dark Cloud
([Chronicle](ports/chronicle/README.md)) and Dark Chronicle ([Chronicle Two](ports/chronicle-two/README.md)), and of
the mods built on it. The Moon People changed the world in these games; MoonFactory lets mods do the same.

MoonFactory gives both games one mod package format, a sandboxed Lua scripting layer with a versioned `game.*` API,
saved settings and storage for each mod, and an in-game Mod Manager. Native C plugins are also possible, behind a
separate trust confirmation by the player.

| I want to... | Go to |
| --- | --- |
| Play with mods | [Install](#install) and [Use](#use) below |
| See what mods exist | [Bundled mods](#bundled-mods) |
| Make a mod | The [modder's guide](docs/modding/README.md), then the [API reference](docs/API.md) |
| Look up an operation | The [operation index](docs/api/OPERATIONS.md) |
| Work on the framework itself | [Repository layout](#repository-layout) and [Verification](#verification) |

## Install

MoonFactory is built into the Chronicle and Chronicle Two PC ports, which you build yourself from your own disc
image. Nothing from either game is included here.

1. **Build the port with MoonFactory in it.** Each port folder has the exact steps and names the upstream commit it
   supports:
   - [Chronicle (Dark Cloud)](ports/chronicle/README.md): download the
     [latest release](https://github.com/Jeffiest/MoonMod/releases/latest), `MoonMod-<commit>`, named after the
     Chronicle commit it is made for. Its page has the full how-to. Clone Chronicle at that commit, copy the release
     folder's contents into it (replace the files), then run Chronicle's own `build.bat windows-x64-release` and
     `run.bat`. Or apply the patch yourself with `ports\chronicle\apply-moonfactory.ps1`.
   - [Chronicle Two (Dark Chronicle)](ports/chronicle-two/README.md): clone ChronicleTwo, run
     `ports\chronicle-two\apply-moonfactory.ps1` (it applies the game patch and the required Kazarov input patch
     together), then build and run the same way.
2. **Add mods.** Each mod is a folder named after the mod's id, holding `mod.json` and the Lua script it names. On
   Chronicle the folder goes in `Chronicle\mods\<mod id>\`, which a release creates with the bundled mods in it. On
   Chronicle Two it goes in `mods\<mod id>\` in the game's save folder or beside its executable. The bundled mods in
   [`mods/`](mods/) and the examples in [`examples/`](examples/) are ready to copy as they are.
3. **Start the game and switch mods on.** New mods are found at start-up and begin **off**; turn them on in the Mod
   Manager. Most switches apply at once. A mod that adds content the game keeps (items, characters, floors) waits
   for a restart, and a native (DLL) plugin must also be marked trusted before it loads.

### Find and install mods from the catalogue

`tools/moonfactory.py` (Python 3.10 or newer, nothing else needed) reads the mod catalogue, which is published as
this repository's `mod-index` release every time the bundled mods change:

```
python tools/moonfactory.py search                       # every mod in the catalogue
python tools/moonfactory.py search boss                  # those matching words
python tools/moonfactory.py install moonmod.randomizer --mods <Chronicle>\mods
python tools/moonfactory.py list --mods <Chronicle>\mods # what is installed, and which have updates
python tools/moonfactory.py install moonmod.randomizer --mods <Chronicle>\mods --upgrade
```

`install` brings the mods a mod depends on first, checks each download against the catalogue's checksum, refuses an
archive with files outside its own folder, and keeps the folder an upgrade replaces as `<id>.previous`. Anyone can
publish a catalogue of their own mods with `moonfactory index` and share its address for `--index`.

### Where the game looks for mods

Chronicle reads mods from one folder: `mods/` in the Chronicle checkout, else `mods/` beside the executable, else
`<save>/mods`. Chronicle Two reads `<save>/mods` and `mods/` beside the executable. Which mods are on, and their
settings, are saved per game in `<save>/moonmod/profile.json`. With `MOONMOD_NO_MODS=1` in the environment every
mod starts off for that run, and the profile keeps the player's choices for the next one.

## Use

- **Open the Mod Manager** from **Options > Game > Mod Manager**. On Chronicle it is also the **MODS** entry of the
  pause ring (the former Manuals slot; Triangle there still opens the manuals). It works with keyboard, controller
  and mouse.
- **Switch mods on and set them up.** The list shows every mod found, with its version and author. Select one to
  turn it on or off and to open its pages: **Settings** (the options the mod declares), **Actions** (buttons and
  commands the mod registers), and **Quests**, **Skills** and **Journal** (the mod's own progression).
- **Play.** Mods react to the game through events (ticks, scene changes, item pickups, kills, floor generation,
  Georama changes and more) and show their state through notices and their pages. A mod that errors is switched
  off on its own and says so in the game's log; the other mods keep running.
- **Run several at once.** The manager lists dependency order and conflicts.

## Bundled mods

All are for Chronicle (Dark Cloud). Each is a complete, shipping package in [`mods/`](mods/), and good reading for
anyone making a mod.

  | Mod | What it does |
  | --- | --- |
  | `moonmod.pack` MoonMod Pack | Twelve of the bundled mods merged into one folder with one switch, each part still switchable on its own ([about packs](docs/modding/PACKS.md)) |
  | `moonmod.rpg` RPG: Character Paths | Kills give XP, levels give HP, damage, toughness and skill points; a skill tree per character on the Journal's Character page |
  | `moonmod.adventurer` Ascension | Per-character levels and a 17-skill tree with face-button powers and a Focus bar |
  | `moonmod.dungeon-plus` Dungeon+ | Champions with themed loot, floors replayable at Tiers 1-5, mutators, bounties, bigger floors |
  | `moonmod.roguelike` Dark Genie's Gauntlet | A roguelike game mode on the title menu, with its own title screen and progress and no save file: five biomes of three floors and a Warden, Cursed Gates, fast ABS, Shatter, an in-run Diorama, drafted allies and the Norune Eternal unlocks ([guide](mods/moonmod.roguelike/README.md)) |
  | `moonmod.vigil` Vigil | Souls-lite combat for the story game: stamina-gated rolls and backsteps, harder-hitting enemies, and floors that stay the same between visits ([guide](mods/moonmod.vigil/README.md)) |
  | `moonmod.challenges` Challenges | Boss fights worth the name, and challenge modes on the title menu's Challenges row ([guide](mods/moonmod.challenges/README.md)) |
  | `moonmod.randomizer` Randomizer | A new Dark Cloud from one seed: shop stock, weapon stats, monster drops and steals, chest contents and floor layouts, all shuffled ([guide](mods/moonmod.randomizer/README.md)) |
  | `moonmod.living-towns` Living Towns | The towns ask things of you after their houses are rebuilt ([guide](mods/moonmod.living-towns/README.md)) |
  | `moonmod.opar` Opar in the Story | Opar, the frog mage, joins the story with Xiao as a seventh playable hero |
  | `moonmod.modern-cloud` Modern Cloud | Quality of life for the story game, each part its own setting: thirst, weapon wear and a break guard, map and monster reveal, and more ([guide](mods/moonmod.modern-cloud/README.md)) |
  | `moonmod.sirfancybacon` SirFancyBacon Mod Pack | Quality-of-life ideas from SirFancyBacon's Chronicle branches ([guide](mods/moonmod.sirfancybacon/README.md)) |
  | `moonmod.controls` Controls | Dungeon quick-item hotkeys, party shortcuts and a first-person toggle |
  | `moonmod.autosave` Autosave | Controls Chronicle's guarded town autosave slot |
  | `moonmod.expanded-town` Expanded Town Camera | Toggles the legacy overhead camera while walking in towns |
  | `moonmod.hub` MoonMod Hub | Quick links to the other mods' pages in the manager |
  | `moonmod.coop` Online Co-op | Up to four play together online: the host's world, story and Georama, with each guest's own weapons, items and Gilda kept in the host's save (in progress: [plan](docs/plans/COOP_PLAN.md)) |

## Create a mod

A mod is a folder with a manifest and a Lua script, run in its own sandbox: no `io`, `os`, `debug` or `package`, a
memory limit, and an instruction budget per callback.

**The [modder's guide](docs/modding/README.md) is the place to start.** It walks through a first mod, has recipes
for what the bundled mods do (game modes, floors, rooms, bosses, NPCs, weapons, shops, new heroes), shows how to add
an operation to the engine when Lua isn't enough, and how to test a mod outside and inside the game. The short
version:

1. **Start from the template.**

   ```powershell
   python .\tools\moonfactory.py new author.my-mod --output .\my-mod --target both
   ```

   This fills in the package identity and game targets without overwriting an existing folder. The template shows a
   setting, an event-driven quest, saved skill ranks and manager actions. Use `--target chronicle` or
   `--target chronicle-two` for a mod for one game. The smallest possible mod is
   [`examples/hello-world`](examples/hello-world/): a `mod.json` and a dozen lines of Lua.

2. **Describe it in `mod.json`.** The id (`author.my-mod`, also the folder name), name, version, author,
   description, `framework_api` (1), the `games` it targets, the `entry` script, the `permissions` it needs
   (`storage.read`, `game.write`, ...) and its typed `settings`, which the manager draws for the player. The full
   schema is [`manifest.schema.json`](manifest.schema.json).

3. **Write the script.** The entry script returns a table; `on_load` runs when the mod starts. Subscribe to game
   events with `moonmod.on(event, callback)`, read settings with `moonmod.settings.get`, save with `moonmod.storage`
   (small key/value) or `game.save` (JSON-shaped data), and change the game through the `game.*` operations. Every
   operation reports whether the running game supports it, so one mod can target both games. The
   [API reference](docs/API.md) explains how calls behave and where each area is written up.

4. **Test it.** Copy the folder into the game's `mods\` folder, start the game, switch the mod on and watch the
   game's log for `moonmod.log` output and errors. [Testing mods](docs/modding/TESTING.md) covers checking a mod
   without the game and with a headless one.

5. **Go further** with the examples:

   | Example | Shows |
   | --- | --- |
   | [`hello-world`](examples/hello-world/) | The smallest mod |
   | [`first-steps`](examples/first-steps/) | An event-driven quest and a skill tree, for both games |
   | [`weapon-quest-reward`](examples/weapon-quest-reward/) | A quest that hands out a native weapon, for both games |
   | [`horde-250`](examples/horde-250/), [`maze-50`](examples/maze-50/) | The raised monster and floor limits |
   | [`new-move`](examples/new-move/) | A new animated attack for Toan, walked through in the [animation guide](docs/ANIMATION_GUIDE.md) |

## Documentation

Everything is indexed in [`docs/`](docs/README.md). The main entries:

- **[Modder's guide](docs/modding/README.md)**: [first mod](docs/modding/FIRST_MOD.md),
  [cookbook](docs/modding/COOKBOOK.md), [extending the engine](docs/modding/EXTENDING_THE_ENGINE.md),
  [testing](docs/modding/TESTING.md), [packs and live on/off](docs/modding/PACKS.md),
  [Dark Cloud engine notes](docs/modding/DARK_CLOUD_NOTES.md)
- **[API reference](docs/API.md)**: how calls work, permissions, and ten chapters by area; the
  [operation index](docs/api/OPERATIONS.md) lists every operation and event
- **Assets**: [animation guide](docs/ANIMATION_GUIDE.md), [model and texture replacements](docs/MODEL_REPLACEMENTS.md)
- **Native code**: [Native SDK](docs/NATIVE_SDK.md)
- **Chronicle Two scripts**: [ChronicleTwo-Script compatibility](docs/ChronicleTwo-Script.md) and the
  [bridge design](docs/CHRONICLETWO_SCRIPT_BRIDGE.md)
- **Plans and history**: [`docs/plans/`](docs/plans/), including the [delivery roadmap](docs/plans/ROADMAP.md)

## What works today

- **Packages.** Mods are found in the local `mods/` folder, their manifests checked, and loaded in dependency
  order with per-game profiles and generated settings pages. Several mods can ship as one merged pack.
- **Lua.** One memory-limited Lua 5.5.1 state per mod with an instruction budget per callback and no `io`, `os`,
  `debug` or `package` library.
- **The API.** 381 operations in 43 domains. Chronicle binds 362 of them and Chronicle Two 176; the rest report
  `unsupported` with a reason rather than pretending to work. The [operation index](docs/api/OPERATIONS.md) has the
  list for each game.
- **The Mod Manager.** A two-pane manager with Settings, Actions, Quests, Skills and Journal views, drawn in each
  game's own UI and usable with keyboard, controller and mouse.
- **Chronicle goes furthest.** Title-menu game modes and sandbox sessions, generated floors of any size with
  zones, shrines and kept layouts, new moves and motions for the heroes, new playable characters, monster AI from
  Lua, gear and charm slots, and online co-op for up to four.
- **Chronicle Two** has the shared core (saves, quests, skills, input, audio, the manager), items and weapons,
  Georama, added floors and locations, and its own systems: photography, inventions, the ridepod, monster badges
  and Spheda.
- **Native plugins.** An opt-in C ABI ([Native SDK](docs/NATIVE_SDK.md)); a plugin runs in-process, outside the
  Lua sandbox, only after the player trusts it.
- **DC2-Toolkit bridge.** `tools/chronicle_two_script_bridge.py` reports what a
  [DC2-Toolkit](https://github.com/fakegenie/DC2-Toolkit) mod contains and can run its offline checks and builds.
  Those builds stay disc-image patches; running them in the PC port is still open.

Still open: wholly new dungeons and towns with their own geometry, renderer hooks and draw callbacks, collision
queries, and most of Chronicle's newer systems on Chronicle Two. The [roadmap](docs/plans/ROADMAP.md) has the gaps.

### Compatibility

The package format and the common Lua API carry explicit major versions, and each game domain reports its own. A
mod may target both games or one; it must not assume that a Chronicle operation and a Chronicle Two operation of the
same name behave the same. Every call checks its permission, and an operation a game does not support says so. The
`moonmod` Lua namespace and the `<save>/moonmod/` storage path are stable. MoonFactory itself never goes online; the
catalogue tool and the co-op mod are the only parts that do.

## Repository layout

| Path | What it holds |
| --- | --- |
| [`ports/`](ports/) | The framework as each game builds it: one patch per port against a named upstream commit, with the scripts that apply it. **This is the current source of the runtime.** |
| [`mods/`](mods/) | The bundled mods. `mods/moonmod.pack` is generated from the others by `tools/pack/build_pack.py`. |
| [`examples/`](examples/) | Small mods to copy from. |
| [`docs/`](docs/README.md) | The modder's guide, the API reference, asset guides, and plans. |
| [`tools/`](tools/) | `moonfactory.py` (new mods, the catalogue), the release and pack builders, animation, character and sound tools, the docs generators, and the tests in `tools/tests/`. |
| [`art/`](art/) | Sources for the characters the mods add (Opar, Seda). |
| [`src/`](src/), [`include/`](include/), `CMakeLists.txt` | A standalone copy of the shared runtime, meant to match the one in the Chronicle Two patch. Chronicle's copy, inside its patch, is newer. |
| [`vendor/`](vendor/) | Lua 5.5.1 (MIT; see `vendor/LUA-LICENSE.txt`). Each port also carries it under `port/third_party/`. |
| [`artifacts/`](artifacts/) | Reports, logs and screenshots from past verification runs. |
| [`manifest.schema.json`](manifest.schema.json) | The JSON schema for `mod.json`. |

## Verification

```
python -m unittest discover -s tools/tests -p "test_*.py"   # the tools and the examples
python tools/pack/build_pack.py --check                     # mods/moonmod.pack matches the mods it is built from
python tools/gen_api_reference.py --check                   # docs/api/OPERATIONS.md matches the port patches
python tools/check_docs.py                                  # every Markdown link resolves
```

CI also checks that both port patches still apply to the upstream commits they name. The full gate,
`verify-headless.ps1`, builds both ports on Windows, runs their native tests and headless probes, and with extracted
game data runs gameplay checks in the real games. [docs/VERIFICATION.md](docs/VERIFICATION.md) explains how to run it
and what each check proves.
