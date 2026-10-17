# MoonFactory

MoonFactory (display name: Moon Factory) is a shared, versioned mod framework for the PC ports of Chronicle and Chronicle Two. The Moon People changed the world in these games; MoonFactory gives creators APIs to do the same through mods. It provides one package format, a Lua scripting layer, persistent settings and storage, and an in-game manager. An opt-in C-compatible native plugin ABI is also available after a separate local trust confirmation; native code runs in-process outside the Lua sandbox.

The source snapshot in this workspace is the canonical first implementation. Each PC port carries the same runtime sources and its own thin game adapter so either game repository can build on its own. The public API and package format are described in `docs/`.

## What runs today

- Local `mods/` package discovery and manifest validation.
- Per-game profiles, enable/disable state, generated setting definitions, and dependency ordering.
- One memory-limited Lua 5.5.1 state per mod with an instruction budget and no `io`, `os`, `debug`, or `package` library.
- Common APIs for logging, events, typed settings, isolated save data and migrations, callable Lua functions, mod-owned quests and skill trees, localized text, bounded package resources, package audio, digital input actions, and permission-gated diagnostics.
- A versioned `game.*` catalog with 139 operations and per-game support reporting. Both ports bind native player health/status, party and character queries, world time, story flags/counters and map flags, quests, items, and selected other systems. Generic `game.content.list/register` wraps each port's typed item, weapon, character, and dungeon registries; Chronicle Two also wraps Georama pieces. Chronicle reads and changes saved Georama requests, toggles defined plot elements in the active editor, registers native-backed consumables and data-only weapons, and reports enemy movement intent. ChronicleTwo reads saved Georama data and conditions, registers/equips weapons and usable items, and appends reachable floors to existing dungeons.
- Quest and skill progression is persistent and shown in the in-game manager. Quest objectives can react to verified scene, world-location, item-use, story-state, Georama, and ChronicleTwo party events. Quests can grant Gilda or registered items on completion. Skills provide owned trees, prerequisites, saved ranks, and manager display; game-specific skill UI integration remains open.
- A PC settings entry that opens a two-pane manager with Settings, Actions, Quests, and Skills views. It fits Chronicle's 640×480 canvas and is horizontally scaled to Chronicle Two's 512×480 canvas. It is navigable with keyboard, controller, and mouse.
- A [DC2-Toolkit bridge](https://github.com/fakegenie/DC2-Toolkit) that reports mod manifests, scripts, symbols, asset provenance, and game fingerprints; it can invoke offline `dc2tk mod check`, `dc2tk mod test`, and build a patched image at a new output path. Those outputs remain build-only; automatic conversion and an asset-backed PC runtime proof remain open.
- Both ports expose an owned Lua override at the active scene event-program runner. Mods can inspect the hook, skip a selected program, or call that program's native implementation once from the override callback. Other native script interpreters remain unsupported.
- Ready-to-copy [First Steps](examples/first-steps/) and [Weapon Quest Reward](examples/weapon-quest-reward/) examples for both ports. Native package tests load First Steps to verify its event-driven quest and skill tree; the weapon example shows game-specific native IDs and reports the payout result.

The catalog is broader than the current adapters. Authored locations and independent dungeon graphs, authored Georama geometry/assets, mod-created playable characters, authored model and standalone animation assets, fighting styles, other native script interpreters, renderer hooks, Chronicle velocity writes, and collision queries remain unsupported and return explicit reasons. Chronicle supports data-only Georama variants that inherit a loaded native solid piece; authored geometry and custom model assets remain open. Fighting-style definitions, animation API expansion, authored animation assets, and rig work are deferred until model rigging is in scope. Existing embedded model-motion playback on mod-spawned enemies remains available as a frozen, verified baseline. Both games also support bounded orbit changes on an active dungeon follow camera; camera render callbacks and draw layers remain unsupported. Read the [delivery roadmap](docs/ROADMAP.md) for the active gaps.

The runtime searches the local save directory (`<save>/mods`) and the game's install directory (`mods/` beside the executable). It reads the profile from `<save>/moonmod/profile.json`; that existing storage path and the `moonmod` Lua namespace stay stable for compatibility. MoonFactory does not use an online catalog.

Lua is vendored at `vendor/lua-5.5.1/src` and in each port's `port/third_party/lua-5.5.1`. Upstream Lua is MIT licensed; see `vendor/LUA-LICENSE.txt`.

## Package sketch

Create a runnable starter package with:

```powershell
python .\MoonFactory\tools\moonfactory.py new author.my-mod --output .\my-mod --target both
```

The command fills in the package identity and game targets without overwriting an existing folder. The included template demonstrates a setting, an event-driven quest, saved skill ranks, and actions in the in-game manager. Choose `--target chronicle` or `--target chronicle-two` for a game-specific package.

```text
mods/
  my-first-mod/
    mod.json
    main.lua
```

```json
{
  "schema_version": 1,
  "id": "author.my-first-mod",
  "name": "My First Mod",
  "version": "1.0.0",
  "framework_api": 1,
  "games": ["chronicle", "chronicle-two"],
  "entry": "main.lua",
  "permissions": ["storage.read", "storage.write"],
  "settings": [
    {"id": "enabled_feature", "name": "Enable feature", "type": "boolean", "default": true}
  ]
}
```

```lua
local mod = {}

function mod.on_load()
  moonmod.log("info", "Hello from " .. moonmod.game.id)
end

moonmod.on("game.tick", function(frame)
  -- Game-facing APIs are added through the versioned adapters.
end)

return mod
```

## Compatibility policy

The package format and common Lua APIs use explicit major versions. Game-specific namespaces report their own capability versions. A mod can target both games or one game; it must not assume that a similarly named Chronicle and Chronicle Two subsystem has identical behavior. Each call checks its declared permission, and each adapter reports unsupported operations instead of pretending they succeeded. Native plugins require the `native.extension` permission, a package-contained library declaration, and a separate local approval; their host API calls still check requested and declared permissions.

## Verification

On Windows, run `pwsh -File .\MoonFactory\verify-headless.ps1` from the workspace root to run the Python tests for the ChronicleTwo-Script bridge, package CLI, and examples; build both native test targets; verify both synthetic headless probes; and launch the empty-data executable checks. The verifier runs each synthetic probe twice from clean roots and compares its stable API/feature markers. It also validates every API operation and domain count, including explicit unsupported reasons, and writes [`artifacts/verification-report.json`](artifacts/verification-report.json) with per-game catalogs and test results.

When complete extracted retail data is available, the verifier launches each game for 120 headless frames and captures a startup screenshot using an isolated save directory. That checks process startup and screenshot creation; it does not inspect screenshot pixels or prove gameplay. Pass data roots with `-ChronicleDataRoot` and `-ChronicleTwoDataRoot`; otherwise it uses `DC_DATA`/`DC2_DATA` or detects complete per-user extractions. Add `-NoBuild` to reuse existing port build directories. `-ManagerUiSmoke` separately loads two Lua quest packages, navigates to the Journal tab, and captures the manager at 1280×720 in both ports; the report records screenshot paths and checks package startup markers. Review the screenshots for visual fit. Retail gameplay flags run separate fixtures, so use one of `-RetailGameplaySmoke`, `-RetailItemSmoke`, `-RetailDungeonSmoke`, `-RetailCharacterSmoke`, or `-RetailGeoramaSmoke` per invocation. `-RetailGameplaySmoke` captures a checkpoint after scripted movement; `-RetailItemSmoke` verifies usable data-only items and weapons, quest events and a native quest weapon reward, a registered enemy, and Chronicle Two's appended floor and camera; `-RetailDungeonSmoke` verifies a registered Chronicle floor; `-RetailCharacterSmoke` checks the registered enemy, model binding, embedded-motion playback baseline, and combat; and `-RetailGeoramaSmoke` verifies data-only piece registration, native placement, saved-layout readback, and removal in both games. `-RetailLocationSmoke` separately checks entry and return for compatible copied maps; Chronicle Two also runs the copied `.map`/`.cfg` without packaged `.mpk`/`.ipk` files and verifies native pack reuse. Other screenshots are saved for review, but are not pixel-inspected. Synthetic native adapter tests cover API contracts and state changes without requiring extracted game data.

Add `-RetailGeoramaSmoke` to test Georama integration in both games with retail data. Chronicle uses an isolated Norune save to register a data-only solid variant in appended native slot 24–55, place and remove it through native editor routines, and verify saved-layout readback. Chronicle Two uses an isolated Sindain save to materialize, place, and remove a Lua-registered variant through native edit routines and verify the town layout. Neither run verifies visual persistence after process reload or compatibility with a player's save.

See:

- [API map](docs/API.md)
- [First Steps starter mod](examples/first-steps/)
- [Weapon quest reward example](examples/weapon-quest-reward/)
- [Native SDK](docs/NATIVE_SDK.md)
- [ChronicleTwo-Script compatibility](docs/ChronicleTwo-Script.md)
- [ChronicleTwo-Script bridge design](docs/CHRONICLETWO_SCRIPT_BRIDGE.md)
- [Delivery roadmap](docs/ROADMAP.md)
- [Manifest schema](manifest.schema.json)
