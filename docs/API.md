# MoonFactory API reference

MoonFactory mods are Lua scripts that change Chronicle (Dark Cloud) and Chronicle Two (Dark Chronicle) through one
versioned API. This page explains how the API is laid out and how every call behaves. The chapters hold the detail,
and the [operation index](api/OPERATIONS.md) lists every operation with its permission and which game supports it.

New to modding? Start with the [modder's guide](modding/README.md): it builds a first mod and has recipes for the
common jobs. Come back here to look things up.

## Chapters

| Chapter | What it covers | Domains |
| --- | --- | --- |
| [Runtime and core services](api/runtime.md) | Save data and migrations, the content registry, localization, commands, functions other mods can call, quests, skill trees, events and phases, diagnostics, merged packs, permissions | `save`, `content`, `localization`, `commands`, `scripts`, `quests`, `skills`, `events`, `debug`, `mods` |
| [Package files and assets](api/assets.md) | A package's own files, replacing the game's files, audio, game text, models, animations and new motions | `resources`, `audio`, `text`, `models`, `animations` |
| [Mod Manager, HUD, screens, input, camera](api/ui.md) | Notices, Mod Manager actions and pages, HUD layers and bars, choice panels, run menu, map and sky screens, input actions, the camera | `ui`, `input`, `render` |
| [Player and party](api/player.md) | Health and state, tuning, guard and gauge, mod-made moves and forms, the companion, the party, playable characters, the wallet | `player`, `party`, `characters`, `economy` |
| [Items, gear, weapons, shops](api/items-weapons.md) | Item and weapon definitions, registering new ones, inventory, charm slots, gear, weapon growth, shops, inventions | `items`, `weapons`, `shops`, `inventions` |
| [Monsters, entities, combat](api/combat.md) | Monsters on a floor, stats, spawning, damage, statuses, damage formulas, enemy definitions, monster AI from Lua | `combat`, `entities`, `physics`, `monsters`, `effects` |
| [Dungeons and floors](api/dungeons.md) | Added floors, floor generation, kept floors, zones, shrines and warps, floor rules and loot, lighting, back floors, Spheda | `dungeons` |
| [Georama](api/georama.md) | Town state, requests, piece variants, placing and removing pieces, Atla | `georama` |
| [World, locations, scripts, game modes](api/world.md) | Where the party is, locations and travel, town villagers, hooks into the game's scripts, title-menu game modes, sandbox sessions, photography | `world`, `locations`, `title`, `session`, `photos` |
| [Online play and co-op](api/online.md) | Rooms through the co-op relay, the split co-op save, the mods a room needs, player messages | `net`, `save` (co-op), `mods`, `messages` |
| [Operation and event index](api/OPERATIONS.md) | Every operation and event in one table, generated from the catalog | all |

Related references: the [manifest schema](../manifest.schema.json) for `mod.json`, the
[Native SDK](NATIVE_SDK.md) for C plugins, and the [animation guide](ANIMATION_GUIDE.md) for new motions.

## A mod's script

The entry script named in `mod.json` returns a table. The runtime calls `on_load` when the mod starts.

```lua
local mod = {}

function mod.on_load()
  moonmod.log("info", "hello from " .. game.info.get().mod_id)
  moonmod.on("game.scene.entered", function(event)
    if event.scene_id == "dungeon" then
      game.ui.notify({message = "Good luck down there"})
    end
  end)
end

return mod
```

Two global tables are available:

- **`moonmod`** is the runtime itself: logging, events, the mod's settings and storage, and the catalog.
- **`game`** is the catalog of game operations, grouped by domain: `game.player`, `game.items`, `game.dungeons` and
  so on.

### The `moonmod` table

| Function | What it does |
| --- | --- |
| `moonmod.log(level, message)` | Writes to the game's log under the mod's name. |
| `moonmod.on(event, callback)` | Subscribes to an event. `runtime.loaded` (with `live = true` when the mod was switched on mid-run), `runtime.unloaded` and `game.tick` come from the runtime; the rest are listed by `game.events.list()`. |
| `moonmod.settings.get(id)` | Reads one of the typed settings the mod declares in `mod.json`. |
| `moonmod.storage.get/set/delete(key, value)` | Small per-mod key/value storage. Needs `storage.read` / `storage.write`. |
| `moonmod.game` | The game id and the framework API major. |
| `moonmod.api.list()` | Every catalogued operation with its phase, permission, support flag and reason. |
| `moonmod.api.supports(path)` | Whether one operation is supported in the running game, and why not. |
| `moonmod.api.call(path, ...)` | Calls an operation by its path, such as `"player.heal"`. |
| `moonmod.part.run/enabled/list` | Only in a merged pack: hands each part of the pack its own script. See [Merged packs and live on/off](api/runtime.md#merged-packs-and-live-onoff). |

`game.save` is the larger, JSON-shaped store ([Save data and migrations](api/runtime.md#save-data-and-migrations-save)).
Deferred work on a named game phase (`moonmod.tasks`) is planned; today a mod does that work from event
subscriptions.

### The sandbox

Each mod runs in its own Lua 5.5 state (the parts of a merged pack share the pack's state, each as its own owner).
A script gets the standard base, table, string, math and UTF-8 libraries. File, process, dynamic module, bytecode
loading, debug and unrestricted garbage-collector functions are withheld. Each state has a memory ceiling, and each
callback an instruction budget. An error is reported against the mod that made it and never unwinds into the game;
a mod that errors is switched off and the others keep running.

## How calls work

Every operation is called as `game.<domain>.<operation>(arguments)`. The same call by path is
`moonmod.api.call("<domain>.<operation>", arguments)`. Arguments and results are JSON-shaped Lua values: tables,
strings, numbers and booleans.

```lua
local result, err = game.player.heal({amount = 25})
if not result then
  moonmod.log("warn", err.code .. ": " .. err.message)
end

-- or, when failure should stop the callback:
local healed = assert(game.player.heal({amount = 25}))
```

A call that works returns `value, nil`. A call that fails returns `nil, {code = ..., message = ...}` and changes
nothing. The codes are:

| Code | Meaning |
| --- | --- |
| `unsupported` | The running game does not bind this operation. The message says why. |
| `invalid_argument` | An argument is missing, of the wrong type or out of range. |
| `permission_denied` | The mod's `mod.json` does not list the permission the operation needs. |
| `phase_violation` | The call was made at a time the operation is not safe, such as before the game's tables load. |
| `failed` | The game refused: nothing is loaded to act on, the handle is stale, the game's own rules said no. |

Operations that take a Lua callback (`commands.register`, `scripts.register_function`, `scripts.override`) must be
called in the `game.*` form; a function cannot pass through `moonmod.api.call`.

### Checking what a game supports

The catalog is the same in both games, but each game binds only the operations it has a tested native
implementation for. An operation a game does not bind is still listed and still callable: it fails with
`unsupported` and a reason, and never returns an empty success.

```lua
local ok, reason = moonmod.api.supports("georama.river_set")
if not ok then moonmod.log("info", "no river editing here: " .. reason) end
```

`moonmod.api.list()` returns every operation's phase, permission, support flag and reason, and
`game.events.list()` returns `{game, events}` with each event's `name`, `domain` and `summary` for the running game
only. The [operation index](api/OPERATIONS.md) is the same information for both games, generated from the source.

A mod can target both games or one (`games` in `mod.json`). Do not assume that a Chronicle operation and a
Chronicle Two operation of the same name behave the same: the chapters say where they differ. Some systems exist in
one game only. Chronicle has no photography, inventions, ridepod, monster badges or Spheda. Chronicle Two has no
per-character water gauge, Atla, satisfaction view or back floors.

### Ids, handles and ownership

- **Ids.** What a mod registers gets an id in the mod's own namespace: registering `id = "moonblade"` in the mod
  `author.my-mod` returns `author.my-mod:moonblade`. The games' own content has ids such as `chronicle:item:148`
  and `chronicle-two:weapon:80`. A local id resolves in the calling mod's namespace first.
- **Handles.** Entities and resources are named by generation-checked handles, never raw addresses. A handle that
  outlives its object (a monster whose slot was reused, a released resource) fails cleanly.
- **Ownership.** Everything a mod registers or changes is owned by that mod: another mod cannot remove or replace
  it, and disabling or reloading the mod releases it. Where only one mod may hold something at a time (a floor rule,
  a shop's list), the second mod's call fails with a message that says so.

### Phases

Each operation names the phase it is safe in: `any`, `simulation` (while the game is playing), `content`
(registration) or `ui`. Registration is best done in `on_load`. A call made at a moment its operation is not safe
fails with `phase_violation` and changes nothing. See
[Events and update phases](api/runtime.md#events-and-update-phases).

## Permissions

A mod lists the permissions it needs under `permissions` in `mod.json`, and every call checks the one its operation
declares. Turning a mod on in the Mod Manager grants the Lua permissions it lists.

| Permission | Allows |
| --- | --- |
| `game.read` | Reading game state: the player, party, items, floors, towns. |
| `game.write` | Changing game state, and showing notices and screens. |
| `content.register` | Registering content: items, weapons, characters, floors, quests, Mod Manager actions, file overrides, audio. |
| `scripts.override` | Hooking the game's own scripts (`game.scripts.override`). |
| `storage.read`, `storage.write` | `moonmod.storage` and the shared messages folder (`messages.*`). |
| `debug.inspect` | Diagnostics: `debug.inspect`, `debug.profile`, the diagnostic overlay. |
| `net.session` | Online play through `net.*`. The mod talks only to the co-op relay, in text, to the players in its room. |
| `mods.settings` | Reading other mods' settings and giving them values for the session (`mods.*`). |
| `native.extension` | Shipping a native library. The player must also trust it by hand; see the [Native SDK](NATIVE_SDK.md). |

Lua never gets the filesystem, processes, sockets of its own choosing, native code or raw memory. The limits and
the reasoning are in [Permissions and ownership](api/runtime.md#permissions-and-ownership).

## Where the catalog lives

The operation and event catalogs are compiled into each port (`port/src/moonmod/api.cpp`), which this repository
carries in [`ports/`](../ports/). Operation names are stable within API major 1; each capability record reports
`framework_api_major` and its domain's `domain_api_major`. A port's start-up refuses a catalog entry that has neither
a binding nor a reason for being unsupported, so the index cannot drift from the game.

After a change to the catalog, regenerate the index and check the links:

```
python tools/gen_api_reference.py
python tools/check_docs.py
```
