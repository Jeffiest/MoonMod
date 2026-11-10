# Runtime and core services

Part of the [MoonFactory API reference](../API.md). Save data, the content registry, localization, commands, functions
other mods can call, quests, skill trees, events, diagnostics, merged packs and permissions: the parts of the API that
are the same in both games.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Save data and migrations (`save.*`)](#save-data-and-migrations-save)
- [Typed content registry (`content.*`)](#typed-content-registry-content)
- [Localization (`localization.*`)](#localization-localization)
- [Commands (`commands.*`)](#commands-commands)
- [Callable functions (`scripts.register_function`)](#callable-functions-scriptsregister_function)
- [Quests (`quests.*`)](#quests-quests)
- [Skill trees (`skills.*`)](#skill-trees-skills)
- [Quests, Skills and Journal in the Mod Manager](#quests-skills-and-journal-in-the-mod-manager)
- [Events and update phases](#events-and-update-phases)
- [Events sent by weapon, shop and chest changes](#events-sent-by-weapon-shop-and-chest-changes)
- [Debug inspection and profiling (`debug.*`)](#debug-inspection-and-profiling-debug)
- [Merged packs and live on/off](#merged-packs-and-live-onoff)
- [Permissions and ownership](#permissions-and-ownership)
- [Native extensions](#native-extensions)

## Save data and migrations (`save.*`)

```lua
local mod = {}

function mod.on_load()
  local version = assert(game.save.get("__moonmod_schema_version"))
  if version == 0 then
    assert(game.save.migrate({
      from_version = 0,
      to_version = 1,
      set = {progress = {chapter = 1}, options = {show_hints = true}},
      delete = {"old_progress"}
    }))
  end
end

return mod
```

`save.migrate` runs only from `mod.on_load` (the `runtime.loaded` event). Each call must advance exactly one version,
and atomically applies a `set` object and optional `delete` key array together with the reserved
`__moonmod_schema_version`. The version starts at `0`; `game.save.get` may read it, but neither `game.save.set` nor
`moonmod.storage.set/delete` can change it. Repeating a migration whose target version is already stored is a successful
no-op. A source-version mismatch fails without changing data. Each step preserves keys it does not name and remains
subject to the per-mod 128 KiB save limit.

`game.save.slot_id()` is Chronicle-only and reads the current native save's numbered folder identifier (1-based). It
returns `{slot_id = number, slot_generation = number}` or both fields as `nil` when no numbered slot is active. The
generation is persisted beside the save slots, retained when loading the dedicated autosave, and replaced when a
numbered slot is deleted and reused. Mods should key slot-specific records by both fields (for example,
`tostring(slot_id) .. ":" .. tostring(slot_generation)`). `game.save.get/set` itself remains per-mod and is not
automatically partitioned by slot. Chronicle Two does not currently expose a verified native slot identity.

`game.save.autosave_set({enabled = boolean})` is Chronicle-only and controls the separate native autosave slot writer
used by the optional Autosave package. Enabling it resets the timer and waits six seconds before the first eligible
exterior-town write; later writes follow the native four-minute interval. Writes are restricted to safe town walk or
Georama-edit states and skip menus, event scripts, and pending transitions. Disabling it prevents further autosave
writes. This does not overwrite numbered manual slots.

## Typed content registry (`content.*`)

`game.content.list()` returns `{count, entries}` for mod-owned typed definitions registered in the current runtime. Each
entry has a `content_type` field and the stable id and definition fields returned by its typed API. Chronicle lists
`item`, `weapon`, `character`, and `dungeon`; Chronicle Two also lists `georama_piece`.

`game.content.register({type = ..., definition = {...}})` wraps the typed registrars. Both games accept `item`,
`weapon`, `character`, and `dungeon`; Chronicle Two also accepts `georama_piece`. The nested definition follows that
type's existing schema and the registering mod owns the resulting namespaced id. For example:

```lua
local enemy = assert(game.content.register({
  type = "character",
  definition = {
    id = "bright-sentinel",
    kind = "enemy",
    name = "Bright Sentinel",
    template_monster_id = 0,
    stats = {hp = 240},
  },
}))
```

This wrapper does not add capabilities beyond the typed registrars described in the other chapters. Definitions that
inherit native assets remain data-only variants. Both games expose `game.content.unregister({type = ..., id = ...})`,
with per-game safe-removal limits. Chronicle can remove unused registered character variants after dependency checks and
unused data-only Georama variants after confirming that no saved town or live editor placement refers to them. It
rejects item, weapon, and dungeon removal because those registrations use persistent native slots.

Chronicle Two can remove pending items, weapons, dungeon additions, and Georama pieces before they enter native tables;
it rejects materialized definitions, characters, and other types without a safe removal path. A failed removal leaves
the definition registered.

## Localization (`localization.*`)

```lua
local greeting = assert(game.localization.register({
  id = "greeting", -- local ids are qualified with this mod's id
  translations = {en = "Hello", fr = "Bonjour", ["fr-CA"] = "Salut"},
  fallback_language = "en" -- optional; defaults to English, or the first normalized locale
}))
assert(greeting.id == "example.mod:greeting")
assert(game.localization.get({id = "greeting", language = "fr-CA"}) == "Salut")
assert(game.localization.get({id = "greeting", language = "fr-BE"}) == "Bonjour")
```

Locale tags are case-insensitive and normalized to lowercase. Lookup tries the exact language tag, then progressively
broader subtags, then the entry fallback. A lookup without `language` uses the active game's current language; an
explicit `language` overrides it. Chronicle maps its native language selection to `ja`, `en-US`, `en-GB`, `fr`, `de`,
`it`, or `es`; Chronicle Two uses `ja`, `en`, `fr`, `de`, `it`, `es`, `zh`, or `ko`. If no valid game language is
available, lookup uses `en`.

Mods can read only their own registered ids. Registration requires `content.register`, lookup requires `game.read`, and
registrations are bounded to 512 entries, 32 locales per entry, 4096 bytes per string, and 64 KiB total per mod. Entries
live for the lifetime of the loaded mod and are cleared when it unloads.

## Commands (`commands.*`)

```lua
local command = assert(game.commands.register({
  id = "heal_party",
  label = "Heal party",
  description = "Restore the active character"
}, function(arguments)
  local amount = arguments.amount or 25
  local result = assert(game.player.heal({amount = amount}))
  return {healed = result.healed, hp = result.hp}
end))

local result = assert(game.commands.execute({
  id = command.id,
  arguments = {amount = 40}
}))
assert(result.healed == 40)
assert(game.commands.unregister({id = command.id}).removed)
```

Commands are owned by their registering mod and also appear as buttons in its **Actions** tab. Activating a button calls
the command with an empty object; `commands.execute` accepts any JSON-compatible `arguments` value and returns the
callback's JSON-compatible result. Callback errors, non-JSON results, and instruction-budget overruns are reported to
the owning mod. IDs accept 1-60 ASCII letters, digits, `.`, `_`, or `-`; an optional qualified ID must use the
registering mod's namespace. Labels and descriptions follow the manager action limits, and a mod may own at most 12
command buttons combined with its other manager actions.

Registration/removal require `content.register`; executing a command requires `game.write`, including manager-button
activation. Commands are removed when the mod unloads. The callback-bearing `commands.register` operation must be called
as `game.commands.register(definition, callback)`; it cannot be passed through the JSON-only `moonmod.api.call` form.

## Callable functions (`scripts.register_function`)

```lua
local exported = assert(game.scripts.register_function({
  id = "double",
  description = "Double a number"
}, function(arguments)
  return {value = arguments.value * 2}
end))

-- A function can call another function it owns using a local id.
local result = assert(game.scripts.call_function({
  id = "double", arguments = {value = 21}
}))
assert(result.value == 42)
assert(game.scripts.unregister_function({id = exported.id}).removed)

-- Discover this mod's exports and exports from loaded declared dependencies.
for _, entry in ipairs(assert(game.scripts.list_functions()).functions) do
  print(entry.id, entry.owner_mod_id, entry.description)
end
```

The callback receives one JSON-compatible argument and returns one JSON-compatible value. Registration and removal
require `content.register`; listing requires `game.read`; invocation requires `game.write`. Listing returns sorted
records with a qualified `id`, `owner_mod_id`, and description, and only includes this mod's exports and exports from
its loaded, declared dependencies. A mod may invoke its own local IDs or a qualified `mod.id:function_id` belonging to a
required or optional declared dependency. Optional dependencies do not block loading when the target is unavailable;
when both are enabled, the target loads first.

Each mod can expose up to 256 functions. Arguments and results are limited to 64 KiB, each Lua callback has the normal
instruction budget, and nested function calls stop at depth 16. Callback failures are returned to the caller without
closing either Lua state. Callback-bearing registration must be called as `game.scripts.register_function(definition,
callback)`; it cannot be passed through the JSON-only `moonmod.api.call` form. Functions and callbacks are removed when
their owner unloads.

## Quests (`quests.*`)

Inventory mutation events support API-driven progression without polling. After `game.items.remove` removes one or more
items successfully, the runtime queues `game.item_removed` for the next pump; its payload includes the stable item `id`,
`source_mod`, `frame`, and the adapter's `requested`, `removed`, and `remaining` values when present. A zero-removal
result emits no event. Quests can subscribe with an exact `match` filter on `id`. Removal through the game's own menus
is not currently observed.

```lua
local definition = {
  id = "lost-relic", -- local id; returned as "example.mod:lost-relic"
  title = "The Lost Relic",
  description = "Find the relic and bring it home.", -- optional
  objectives = {
    {id = "find", title = "Find the relic", target = 1},
    {id = "return", title = "Return to town", target = 1,
     event = "game.scene.entered", match = {scene_id = "town"}}
  }
}

local registered = assert(game.quests.register(definition))
assert(game.quests.start({id = "lost-relic"}))
assert(game.quests.advance({id = "lost-relic", objective = "find"}))
local quest = assert(game.quests.get({id = registered.id}))
print(quest.status, quest.objectives[1].progress, quest.objectives[1].target)
```

`quests.register` accepts one to 64 uniquely named objectives, stores a definition under the registering mod's id, and
is idempotent when the same definition is registered again. Conflicting re-registration fails. Quest ids use 1-64 ASCII
letters, digits, `.`, `_`, or `-`; objective ids and titles are bounded, and targets are positive integers up to
1,000,000,000. A mod can register up to 128 quests within its existing 128 KiB save-data limit.

`quests.get()` returns that mod's quests; `quests.get({id = ...})` returns one owned quest and its objective progress.
Status moves from `registered` to `active` to `completed`. `quests.start` is idempotent for an active quest, while
completed quests cannot be restarted. `quests.advance` adds one by default or a caller-provided positive integer, clamps
at the objective target, and completes the quest when every objective reaches its target.

## Skill trees (`skills.*`)

```lua
local tree = assert(game.skills.register({
  id = "combat",
  title = "Combat",
  skills = {
    {id = "focus", title = "Focus", max_rank = 2,
      effects = {enemy_damage_per_rank = 0.1}},
    {id = "power", title = "Power", max_rank = 3,
      prerequisites = {{id = "focus", rank = 2}}}
  }
}))

assert(assert(game.skills.unlock({id = "combat.focus"})).rank == 1)
assert(assert(game.skills.unlock({id = "combat.focus"})).rank == 2)
assert(assert(game.skills.unlock({id = "combat.power"})).rank == 1)
```

The shared runtime stores each mod's tree definitions and ranks in its protected per-mod save file. Tree registration is
idempotent when the definition is unchanged; changing a registered tree requires a future migration/versioning API.
Prerequisites must reference nodes in the same tree, must fit within their target node's maximum rank, and cannot form
cycles. `skills.unlock` increases rank by one after prerequisite checks; `skills.set_rank` can set a validated rank or
reset a node to zero.

Registration requires `content.register`; reads require `game.read`; rank changes require `game.write`. A mod can
register up to 32 trees and 128 nodes per tree, with ranks from 0 to 99. The optional `effects.enemy_damage_per_rank`
field accepts a finite value from 0 to 1 and adds that percentage per rank to positive outgoing enemy damage. It stacks
multiplicatively in stable mod/skill ID order after registered combat formulas, affects scripted `combat.damage` and
native enemy-hit damage, and does not turn zero damage into a hit.

On Chronicle a mod can also show its tree on the native Journal > Character page (see [Character
sheet](ui.md#character-sheet-the-journals-character-page-chronicle)). The in-game manager's **Skills** tab displays each
mod-owned node, tree name, rank, prerequisite availability, description, and supported enemy-damage effect summary,
including saved data for disabled mods.

## Quests, Skills and Journal in the Mod Manager

The in-game Mod Manager has **Quests** and **Skills** tabs for mods with saved progression data, plus a consolidated
**Journal** tab. Quests shows status, objective completion, per-objective progress, and a reward summary; left/right
changes quests and up/down scrolls longer lists. The Journal tab gathers quests from every package into a two-pane list,
shows each quest's owning mod, status, rewards, and objective progress, and keeps saved entries visible while their mod
is disabled. Skills shows each registered node's tree, rank, maximum rank, prerequisite availability, and description;
up/down selects a node.

These are MoonFactory views, not entries in either game's original journal or native skill UI; native integration
remains open.

## Events and update phases

The runtime reserves stable phase names for `early`, `simulation`, `post_simulation`, `ui`, and `render`. Content
registration happens before game content is finalized. API functions document the phases in which they are safe. A mod
can request deterministic ordering constraints (`load_after`, `load_before`, required dependencies, and optional
dependencies); an unresolved or cyclic dependency is surfaced in the manager with the responsible ids. Optional
dependencies only order the packages when both are enabled and do not block the caller if the target is unavailable.

`game.world.location_changed` is sampled once per runtime pump within a scene and immediately after native scene
initialization when detectable. Its payload contains the new scalar location fields (`context`, `area_id`, `map_id`,
`sub_map_id`, `dungeon_id`, `floor_id`), a `previous` object with the prior snapshot, and the current framework `frame`.
The initial valid snapshot establishes a baseline and emits no change.

A temporarily failed world read during loading keeps the last valid snapshot so the next readable location can still
emit a change; Chronicle can use native loop and map state when save-backed time or area data is briefly unavailable.
This event can drive objectives such as `{event = "game.world.location_changed", match = {map_id = 2}}`. It reports the
first state difference observed between samples, so transitions that begin and end within one pump interval are not
separately reported. Native scene transition events remain available for top-level loading boundaries.

The common runtime emits `game.tick` from the PC port clock pump and `runtime.loaded` after each Lua package loads.
Successful `game.items.use` and changed `world.story_flag_set` calls queue their `game.*` event for the next pump, so
subscribers and quest objectives run after the API callback returns. Both game loops emit `game.scene.will_enter`
immediately before initializing a scene and `game.scene.entered` after the initializer and arrival processing finish.
Their payload contains `scene_id` (`title`, `town`, `dungeon`, `menu`, or `other`), the game's `native_mode` id, and the
framework frame count. The ChronicleTwo headless smoke can verify `will_enter` before its empty-data logo-fade fixture
exits.

Frame-observed location changes cover map and dungeon-floor state differences; exact event timing at each native
map/floor loader remains adapter work.

## Events sent by weapon, shop and chest changes

These are queued when the change happens and delivered on the next runtime pump:

- `game.weapon.abs_gained`: Emitted when an owned weapon gains ABS.
- `game.weapon.built_up`: Emitted when a weapon undergoes build-up or synthesis/spectrumization.
- `game.weapon.broken`: Emitted when weapon durability reaches 0 or when status-broken.
- `game.shop.purchased`: Emitted upon shop transaction or inventory change.
- `game.chest.opened`: Emitted when the player opens a dungeon chest (`dungeon_id`, `floor_id`, `back_floor`, `chest`,
  `item_id`, `large`), or a mod changes a loot table (no `chest`).
- `game.floor.cleared`: Emitted when a dungeon floor's exit is unlocked or rules change.

## Debug inspection and profiling (`debug.*`)

`debug.inspect()` reports the current native scene context:

```lua
local runtime = assert(game.debug.inspect())
print(runtime.scene_id, runtime.native_mode, runtime.native_map_id, runtime.native_floor_id)
```

The snapshot contains only scalar scene and map identifiers: `scene_id`, native mode number, `native_map_id`, and
`native_floor_id`. Map and floor IDs are `nil` when no active native map or dungeon floor exists. It exposes no pointers
or arbitrary process memory.

Mods that declare `debug.inspect` can also read their own bounded runtime counters:

```lua
local profile = assert(game.debug.profile())
print(profile.lua_memory.used_bytes, profile.lua_memory.limit_bytes)
print(profile.resources.handles, profile.resources.bytes)
print(profile.events.subscriptions, profile.storage.bytes)
```

`debug.profile()` reports bounded Lua allocator usage, event subscriptions, localization entries and bytes, loaded
package-resource handles and bytes, and namespaced storage size. It does not expose other mods' data or claim to measure
frame time. Both calls take no arguments; omitting the `debug.inspect` manifest permission returns `permission_denied`.

## Merged packs and live on/off

A **merged pack** is one mod whose script holds several mods, its *parts* (`"parts"` in `mod.json`, up to 64). The
script hands each part over with `moonmod.part.run(id, source, globals, name)` (the part's script as source, compiled as
a chunk of its own, so errors name the part's file and line) or `moonmod.part.run(id, fn)`; the engine runs the part
only when it is on, as the part's own owner: the part's id, settings (`moonmod.settings.get`), saved data
(`moonmod/data/<part id>/`), events, and everything it registers are its own, as when it was a separate mod.
`moonmod.part.enabled(id)` and `moonmod.part.list()` (`{id, enabled, running}`) read the state. Parts are records of
their own in the Mod Manager (listed under the pack), in `mods.list`, `mods.settings_get` and to other mods'
`dependencies` and `scripts.call_function`. A pack's switch turns its parts on and off with it; each part's own switch
is kept apart (the profile's `parts`, under the pack), so the pack's switch never overwrites it. While a pack is on, a
part stands in for a separate mod of the same id; when it goes off, that mod is itself again and starts at once if it is
on. The memory ceiling and per-event handler limit grow with the number of parts, each part's load has its own
instruction budget, a script may be 4 MiB and `mod.json` 1 MiB.

**Live on/off.** Switching a mod or part in the Mod Manager applies at once when the engine can undo it: the mod
starts (`runtime.loaded` with `live = true`) or stops (`runtime.unloaded`, then its owned state is released). It
waits for a restart, with the reason in the Mod Manager, when the mod has native code, a running mod depends on it, a
dependency isn't running, or it touches content the game keeps: `items.register`, `weapons.register`,
`weapons.build_up_register`, `characters.register`, `characters.register_playable`, `dungeons.register`,
`world.register_dungeon`, `georama.register`, `locations.register`, `content.register`, `models.register`,
`animations.register`, `animations.player_register`, `animations.monster_register`, `inventions.register`,
`combat.styles_register`. A mod that called one of those this run turns off only with a restart; one whose script
names one turns on mid-game only from the title screen (no game session running). A running package whose `mod.json`
or entry script changes on disk is reloaded within about two seconds when it could be switched off and on live.
Details and the MoonMod Pack's builder: [Packs and live on/off](../modding/PACKS.md).

## Permissions and ownership

Permissions are declared in `mod.json` and checked by the runtime for each operation: `game.read`, `game.write`,
`content.register`, and `scripts.override` cover game adapters; `debug.inspect` gates diagnostics; `storage.read` and
`storage.write` cover per-mod storage. Enabling a local package enables its declared Lua permissions. A package that
declares `native.extension` also needs a package-relative native library and a separate local trust confirmation before
that library loads. Lua does not get direct filesystem, process, network, native code, or arbitrary memory access.
`storage.*` is sandboxed to a fixed JSON file under that mod's user-data directory.

`net.session` lets a mod play online through `net.*`: it talks only to the co-op relay, in text messages to the other
players in its room, never to an address of its own choosing beyond a `wss://` relay. `mods.settings` lets a mod read
other mods' settings and give them session-only values (`mods.*`); it never writes another mod's saved settings. Trusted
native code runs in-process and is outside the Lua sandbox; see [Native SDK](../NATIVE_SDK.md).

## Native extensions

The native SDK has a C-compatible, versioned ABI v1 header, descriptor validator, package-bound dynamic loader, local
trust confirmation, and host logging, supported game-adapter API calls, and event services. Trust is tied to the library
SHA-256 digest and package/file metadata. Native code remains an opt-in in-process escape hatch and does not receive the
Lua sandbox. See [Native SDK](../NATIVE_SDK.md) for its service scope and platform verification boundary.
