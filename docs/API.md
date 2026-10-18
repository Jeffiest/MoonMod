# MoonFactory API map

The API is designed for comprehensive game modification while preserving clear compatibility boundaries. Common domains are shared under `game.*`, and every domain operation carries its own major version plus a per-game capability result. Chronicle- or Chronicle Two-specific operations can be added under their game-specific namespaces without changing common operation contracts. The Lua layer is the default for creators; native extensions are an opt-in escape hatch for engine-level work.

## Common Lua surface, API major 1

The first runtime slice implements the marked surfaces:

| Namespace | Intended surface | First slice |
| --- | --- | --- |
| `moonmod.log(level, message)` | Structured per-mod logs and in-game diagnostics | Implemented |
| `moonmod.on(event, callback)` | Event subscription with an isolated Lua callback budget | Implemented: `runtime.loaded`, `runtime.unloaded`, `game.tick` |
| `game.events.list/subscribe/unsubscribe` | Discover verified event names per game and subscribe with owner-scoped tokens | Implemented in the shared runtime; the list includes short descriptions and omits game-specific events from the other port |
| `moonmod.game` | Game id, framework API version, and capability queries | Implemented: id and API major |
| `moonmod.settings.get(id)` | Read a mod's declared, typed settings | Implemented |
| `moonmod.storage.get/set/delete(key, value)` | Per-mod key/value persistence | Implemented with `storage.read` / `storage.write` permissions |
| `game.save.get/set(key, value)` | JSON-compatible per-mod save data | Implemented with `game.read` / `game.write` permissions and atomic persistence |
| `game.save.slot_id()` | Active numbered Chronicle save identity | Implemented on Chronicle; returns the 1-based `slot_id` plus a persistent `slot_generation` that changes when a deleted slot number is reused |
| `game.save.autosave_set({enabled})` | Enable or disable Chronicle's guarded native autosave writer | Implemented on Chronicle; resets its timer on change and delays the first safe exterior-town save by six seconds |
| `game.save.migrate(definition)` | Versioned key updates/removals at the load boundary | Implemented as an atomic one-version migration during `runtime.loaded` on both ports |
| `game.resources.load/resolve/release/override/unoverride` | Read package files and optionally bind them to native asset paths | Implemented for indexed replacements on both ports and bounded new monster `.chr`/`.stb` paths; typed model bindings are available on both ports; authored model formats and rig validation remain open |
| `game.audio.register/play/stop` | Register and play package audio with owner-scoped handles | Implemented on both ports through the native mixer; path, size, permission, voice, and unload limits are enforced |
| `game.ui.register/remove` | Add or remove an owned action button in the in-game mod manager | Implemented on both ports; activation dispatches `ui.action` only to its owning mod |
| `game.ui.navigate` | Open a loaded package and its Settings, Actions, Quests, Skills, or Journal tab | Implemented on Chronicle; validates destination package and tab |
| `game.ui.notify` | Queue a bounded notice for the mod manager | Implemented on both ports |
| `game.input.bind/unbind/state/consume/axis/context_push/context_pop/context_get/wheel_mode_set` | Mod-owned digital actions, processed stick/trigger axes, priority context stack, and Chronicle's scoped mouse-wheel routing | Actions and context frames are owner-scoped on both ports; all six gamepad axes report normalized values and connection status; wheel mode is Chronicle-only |
| `moonmod.tasks` | Deferred work on a named game phase | Planned; event subscriptions are the current extension seam |
| `game.localization.register/get` | Mod-owned localized strings and language fallback | Implemented in the shared runtime; lookups use the active game language unless the caller supplies a locale |
| `game.commands.register/execute/unregister` | Owner-scoped Lua commands with JSON arguments | Implemented on both ports; registered commands appear in the mod manager's Actions tab |
| `game.scripts.register_function/list_functions/call_function/unregister_function` | Exported, owner-scoped Lua callbacks | Implemented in the shared runtime; discovery and calls are limited to self and loaded required or optional declared dependencies |
| `game.scripts.list_hooks/call/override` | Discover and call stable native game-script hooks, or provide an owned override | Both ports support the active scene event-program runner; other native script VM families remain unsupported |
| `moonmod.compat` | Capability and version negotiation | Implemented through `moonmod.api` and `game.compat` |
| `moonmod.api.list()` | Enumerate the versioned API catalog and per-game support state | Implemented |
| `moonmod.api.supports(path)` | Query an operation by canonical path, returning support and reason | Implemented |
| `moonmod.api.call(path, ...)` | Call a catalogued operation by canonical path | Implemented |

Scripts run in separate Lua states. They receive the standard base, table, string, math, and UTF-8 libraries. File, process, dynamic module, bytecode loading, debug, and unrestricted garbage-collector APIs are withheld. Each state has an allocator ceiling and callback instruction budget. A failure is reported against the owning mod and does not unwind into the game.

### Shared save migrations

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

`save.migrate` runs only from `mod.on_load` (the `runtime.loaded` event). Each call must advance exactly one version, and atomically applies a `set` object and optional `delete` key array together with the reserved `__moonmod_schema_version`. The version starts at `0`; `game.save.get` may read it, but neither `game.save.set` nor `moonmod.storage.set/delete` can change it. Repeating a migration whose target version is already stored is a successful no-op. A source-version mismatch fails without changing data. Each step preserves keys it does not name and remains subject to the per-mod 128 KiB save limit.

`game.save.slot_id()` is Chronicle-only and reads the current native save's numbered folder identifier (1-based). It returns `{slot_id = number, slot_generation = number}` or both fields as `nil` when no numbered slot is active. The generation is persisted beside the save slots, retained when loading the dedicated autosave, and replaced when a numbered slot is deleted and reused. Mods should key slot-specific records by both fields (for example, `tostring(slot_id) .. ":" .. tostring(slot_generation)`). `game.save.get/set` itself remains per-mod and is not automatically partitioned by slot. Chronicle Two does not currently expose a verified native slot identity.

`game.save.autosave_set({enabled = boolean})` is Chronicle-only and controls the separate native autosave slot writer used by the optional Autosave package. Enabling it resets the timer and waits six seconds before the first eligible exterior-town write; later writes follow the native four-minute interval. Writes are restricted to safe town walk or Georama-edit states and skip menus, event scripts, and pending transitions. Disabling it prevents further autosave writes. This does not overwrite numbered manual slots.

## Gameplay API map

Every catalogued domain is available under the global Lua `game` table. Calls use the form `game.<domain>.<operation>(...)`; the matching flat form is `moonmod.api.call("<domain>.<operation>", ...)`. Operation arguments and successful return values use JSON-compatible Lua values. A successful call returns `value, nil`; a failure returns `nil, { code = ..., message = ... }`. Calls enforce the operation's declared permission and are routed to the current port's adapter.

The namespace and catalog are stable API surfaces, but a catalog entry is not a claim that a port has already bound it to native game state. `moonmod.api.list()` returns each operation's phase, permission, support flag, and reason. `moonmod.api.supports("items.register")` returns a boolean and reason. Unsupported calls fail with `code = "unsupported"`; they never return an empty success value. Each game adapter now records an explicit status for every non-core catalog operation. Port startup rejects a missing record or an unsupported record without a reason; new operations become supported only after a native binding and adapter test exist.

`game.events.list()` returns `{game, events}`. Each listed event has a stable `name`, `domain`, and short `summary`. Chronicle and Chronicle Two return only events produced by their shared runtime and verified game adapter. Use one of those names with `game.events.subscribe(name, callback)`; event payload details and delivery timing are described alongside each producer below.

### Generic typed content registry

`game.content.list()` returns `{count, entries}` for mod-owned typed definitions registered in the current runtime. Each entry has a `content_type` field and the stable id and definition fields returned by its typed API. Chronicle lists `item`, `weapon`, `character`, and `dungeon`; Chronicle Two also lists `georama_piece`.

`game.content.register({type = ..., definition = {...}})` wraps the typed registrars. Both games accept `item`, `weapon`, `character`, and `dungeon`; Chronicle Two also accepts `georama_piece`. The nested definition follows that type's existing schema and the registering mod owns the resulting namespaced id. For example:

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

This wrapper does not add capabilities beyond the typed adapters described below. Definitions that inherit native assets remain data-only variants. Both games expose `game.content.unregister({type = ..., id = ...})`, with per-game safe-removal limits. Chronicle can remove unused registered character variants after dependency checks and unused data-only Georama variants after confirming that no saved town or live editor placement refers to them. It rejects item, weapon, and dungeon removal because those registrations use persistent native slots. Chronicle Two can remove pending items, weapons, dungeon additions, and Georama pieces before they enter native tables; it rejects materialized definitions, characters, and other types without a safe removal path. A failed removal leaves the definition registered.

### Shared localization API

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

Locale tags are case-insensitive and normalized to lowercase. Lookup tries the exact language tag, then progressively broader subtags, then the entry fallback. A lookup without `language` uses the active game's current language; an explicit `language` overrides it. Chronicle maps its native language selection to `ja`, `en-US`, `en-GB`, `fr`, `de`, `it`, or `es`; Chronicle Two uses `ja`, `en`, `fr`, `de`, `it`, `es`, `zh`, or `ko`. If no valid game language is available, lookup uses `en`. Mods can read only their own registered ids. Registration requires `content.register`, lookup requires `game.read`, and registrations are bounded to 512 entries, 32 locales per entry, 4096 bytes per string, and 64 KiB total per mod. Entries live for the lifetime of the loaded mod and are cleared when it unloads.

### Shared package resources

```lua
local resource = assert(game.resources.load({path = "resources/icon.png"}))
local payload = assert(game.resources.resolve({handle = resource.handle}))
assert(payload.encoding == "base64")
-- Decode payload.data in Lua or pass it to a native extension that understands the format.
assert(game.resources.release({handle = resource.handle}).removed)
```

Paths must stay under the package's `resources/` directory. The runtime rejects absolute paths, traversal components, symbolic links, and non-files. A mod may hold up to 64 resources and 1 MiB total; each file is limited to 256 KiB. `resolve` returns the bytes as Base64 and reports a media type. Handles are private to the Lua state that loaded them, become stale after release, and are discarded when the mod unloads. This lets scripts read data and small binary resources; it does not by itself register images, models, or sounds with the games' native asset loaders.

### Native file overrides

```lua
local override = assert(game.resources.override({
  path = "resources/dungeon/room.pac",
  game_path = "dun/pack/maindat.pac"
}))
-- Remove it early if needed; all overrides are also removed when this mod unloads.
assert(game.resources.unoverride({game_path = "dun/pack/maindat.pac"}).removed)
```

An override replaces a file that the PC port's native data reader already knows how to open. `game_path` is a relative path in the game's data tree; it is case-insensitive and accepts `/` or `\\` separators. The source must be a regular file below the package's `resources/` directory, and the same traversal and symbolic-link checks apply. A mod owns its override until it removes it or unloads; another mod cannot take or remove that path. Limits are 64 overrides per mod, 512 across all mods, and 128 MiB per source file. For an indexed file, the adapter uses the replacement only when it is non-empty and no larger than the retail file. Bounded exceptions support new native asset paths: Chronicle accepts `dun/monstor/<name>.chr` and `.stb` up to 2 MiB after sector padding; Chronicle Two accepts `dungeon/monster/<name>.chr` and `.stb` up to 3 MiB. Both use native 15-character monster names with letters, digits, `_`, `-`, or `.`. Chronicle can alias a reserved `gedit/s60`–`gedit/s69` directory to indexed built-in field assets when a mod registers a copied location; owned overrides inside that target directory can replace individual files. See [Chronicle native locations](#chronicle-native-locations). Chronicle Two also reads explicitly registered, previously unindexed files under `map/` with `.cfg`, `.efp`, `.ipk`, `.map`, `.mpk`, `.sky`, or `.stb` extensions, up to 3 MiB after sector padding. `locations.register` can append a standalone interior map to Chronicle Two's loaded native map catalog when the mod owns its required map assets; see [Chronicle Two authored locations](#chronicle-two-authored-locations) for registration and transition details. Replacements still need the exact format expected by that game's loader. This does not register a standalone dungeon or animation, and it does not validate model formats or rig compatibility. ChronicleTwo-Script `add` assets and format conversion remain unverified for the PC runtime.

### Package audio

```lua
local sound = assert(game.audio.register({id = "arrival", path = "resources/audio/arrival.ogg"}))
local voice = assert(game.audio.play({id = "arrival", volume = 0.8, pan = -0.2}))
assert(game.audio.stop({handle = voice.handle}).stopped)
```

Mods can register WAV, FLAC, or Ogg Vorbis files under `resources/audio/`, then play their own registered IDs through the game's mixer. `audio.register` requires `content.register`; `audio.play` and `audio.stop` require `game.write`. Playback returns an owner-scoped handle; another mod cannot stop it. Calls accept `loop` (default false), `volume` in `[0, 1]` (default 1), and `pan` in `[-1, 1]` (default center). Each package can register 32 sounds, retain 64 MiB of decoded audio, and play 8 voices at once. Framework-wide limits are 512 sounds, 256 MiB decoded audio, and 128 voices. Source files are limited to 16 MiB and decoded tracks to 32 MiB each. Registration and voices are released when a package unloads. This API mixes package audio into the game's existing output; replacing native music banks or sound effects is a separate asset-loader API.

### Shared mod-manager notification

```lua
local notice = assert(game.ui.notify({message = "New content is ready", duration_frames = 240}))
```

The notice is queued for the manager's status line and stays there for the requested number of game frames (1-3600, default 240). Messages are limited to 200 bytes. If the manager is open, the notice appears immediately; otherwise it appears when the player opens the manager, unless its frame duration expires first. `ui.notify` requires `game.write`.

### Shared mod-manager actions

```lua
assert(game.ui.register({
  id = "rescan",
  label = "Rescan area",
  description = "Refresh this mod's nearby markers"
}))

moonmod.on("ui.action", function(action)
  if action.id == "rescan" then
    -- Run mod-owned behavior here.
    assert(game.ui.remove({id = action.id})) -- Optional: remove a one-shot action.
  end
end)
```

Actions appear in the selected mod's **Actions** tab in the MoonFactory manager. Confirm or click an action to deliver `ui.action` to that mod only. The event contains its local `id`, qualified id, label, and description. IDs accept 1-64 ASCII letters, digits, `.`, `_`, or `-`; labels are limited to 48 bytes and descriptions to 120 bytes without control characters. A mod may register 12 actions, with a 256-action manager limit. Both operations require `content.register`; an action can only be removed by its owner, and all owned actions are removed when the mod unloads. These are manager actions rather than arbitrary custom pages, widgets, or draw callbacks; those need further UI API and renderer work.

### Cross-package Mod Manager navigation

```lua
local opened, err = game.ui.navigate({mod_id = "moonmod.ascension", tab = "skills"})
if not opened then game.ui.notify({message = err.message}) end
```

`mod_id` must identify a valid, enabled, currently loaded package. `tab` must be one of `settings`, `actions`, `quests`, `skills`, or `journal`, and that tab must be available for the destination. Navigation opens the existing Mod Manager if needed, selects the package and tab, and places focus in that view. This requires `content.register`; it does not add custom screens or bypass package enablement.

### Shared commands

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

Commands are owned by their registering mod and also appear as buttons in its **Actions** tab. Activating a button calls the command with an empty object; `commands.execute` accepts any JSON-compatible `arguments` value and returns the callback's JSON-compatible result. Callback errors, non-JSON results, and instruction-budget overruns are reported to the owning mod. IDs accept 1-60 ASCII letters, digits, `.`, `_`, or `-`; an optional qualified ID must use the registering mod's namespace. Labels and descriptions follow the manager action limits, and a mod may own at most 12 command buttons combined with its other manager actions. Registration/removal require `content.register`; executing a command requires `game.write`, including manager-button activation. Commands are removed when the mod unloads. The callback-bearing `commands.register` operation must be called as `game.commands.register(definition, callback)`; it cannot be passed through the JSON-only `moonmod.api.call` form.

### Shared callable functions

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

The callback receives one JSON-compatible argument and returns one JSON-compatible value. Registration and removal require `content.register`; listing requires `game.read`; invocation requires `game.write`. Listing returns sorted records with a qualified `id`, `owner_mod_id`, and description, and only includes this mod's exports and exports from its loaded, declared dependencies. A mod may invoke its own local IDs or a qualified `mod.id:function_id` belonging to a required or optional declared dependency. Optional dependencies do not block loading when the target is unavailable; when both are enabled, the target loads first. Each mod can expose up to 256 functions. Arguments and results are limited to 64 KiB, each Lua callback has the normal instruction budget, and nested function calls stop at depth 16. Callback failures are returned to the caller without closing either Lua state. Callback-bearing registration must be called as `game.scripts.register_function(definition, callback)`; it cannot be passed through the JSON-only `moonmod.api.call` form. Functions and callbacks are removed when their owner unloads.

### Native scene event-program hook

```lua
for _, hook in ipairs(assert(game.scripts.list_hooks()).hooks) do
  print(hook.id, hook.kind)
end

assert(game.scripts.override({id = "native.event.run"}, function(context)
  if context.program_no == 120 then
    return {handled = true} -- Skip this native event program.
  end
  return {handled = false} -- Let another override or the game handle it.
end))
```

Both ports expose one hook, `native.event.run`, at the active scene event-program dispatcher. Its callback receives `hook_id`, `game`, `program_no`, and `frame`. Returning `nil` or `{handled = false}` continues to the next mod override and then runs the native program. Returning `{handled = true}` skips the native program and completes the event with run status 0. Mods are tried in stable mod-ID order; callback errors are logged and fall through. An override belongs to its registering mod, requires the `scripts.override` manifest permission, and is removed on unload. A mod may replace its own callback or remove it with `game.scripts.override({id = "native.event.run", enabled = false})`.

Inside the override callback, `game.scripts.call({id = context.hook_id})` invokes that event's native program once and returns its `run_status`; the runtime then returns that native result without invoking later overrides. Calling it outside the active callback, calling another hook, or calling the native program twice is rejected. These hooks cover scene event programs only. Character, battle, monster, effect, and other script interpreters are not exposed through this hook catalog. Callback registration cannot be passed through JSON-only `moonmod.api.call`.

### Shared mod-owned skill trees

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

The shared runtime stores each mod's tree definitions and ranks in its protected per-mod save file. Tree registration is idempotent when the definition is unchanged; changing a registered tree requires a future migration/versioning API. Prerequisites must reference nodes in the same tree, must fit within their target node's maximum rank, and cannot form cycles. `skills.unlock` increases rank by one after prerequisite checks; `skills.set_rank` can set a validated rank or reset a node to zero. Registration requires `content.register`; reads require `game.read`; rank changes require `game.write`. A mod can register up to 32 trees and 128 nodes per tree, with ranks from 0 to 99. The optional `effects.enemy_damage_per_rank` field accepts a finite value from 0 to 1 and adds that percentage per rank to positive outgoing enemy damage. It stacks multiplicatively in stable mod/skill ID order after registered combat formulas, affects scripted `combat.damage` and native enemy-hit damage, and does not turn zero damage into a hit. Native game-specific skill UI integration remains open. The in-game manager's **Skills** tab displays each mod-owned node, tree name, rank, prerequisite availability, description, and supported enemy-damage effect summary, including saved data for disabled mods.

### Shared input actions

```lua
local action = assert(game.input.bind({id = "open_map", keys = {"M", "Gamepad:back"}}))
if assert(game.input.state({id = "open_map"})).down then
  -- Hold behavior
end
if assert(game.input.consume({id = "open_map"})).pressed then
  -- One-shot press edge; another consume call returns false until the next press
end
assert(game.input.unbind({id = "open_map"}).removed)
```

Action IDs and non-default context IDs are automatically qualified with the registering mod's ID, so mods cannot inspect or remove another mod's action or context frame. `keys` accepts 1-8 SDL keyboard names, `Mouse1` through `Mouse5`, or `Gamepad:<button>` names; Escape is reserved. Bind/unbind/consume and context push/pop require `game.write`, while state and context queries require `game.read`. `input.bind` accepts an optional local `context`; it defaults to the reserved `default` context. `input.context_push({id})` makes that mod-owned context the active top-priority context and returns a token. `input.context_pop({token})` removes only a frame owned by the caller; a covered frame may be removed by its owner without disturbing the newer frame. `input.context_get()` returns the active context and the ordered stack. Only actions bound to the active context report `down` or a consumable `pressed` edge; inactive reads return false and discard queued press edges so they cannot fire after a later context switch. The stack is capped at 64 frames total and 16 per mod, and all frames/actions are removed when their owner unloads. Context priority is global across mods: while a mod-owned context is on top, mod actions assigned to other contexts are inactive. The stack does not suppress the game's native controls.

`game.input.wheel_mode_set({mode = 0|1})` is Chronicle-only and requires `game.write`. Mode `0` routes each whole wheel notch to Left/Right during live dungeon play; mode `1` routes it to Up/Down for menus and non-dungeon contexts. Fractional high-resolution wheel movement is accumulated until a full notch is available. A native mouse-pointer menu keeps its own wheel input. When no mod owns a wheel mode, Chronicle restores the existing camera-zoom routing. Requests are owner-scoped and removed on unload; an empty object clears the caller's request.

`game.input.axis({axis = "left_x"|"left_y"|"right_x"|"right_y"|"left_trigger"|"right_trigger", pad = 0|1})` reads a processed gamepad axis. `pad` defaults to 0. It returns `{axis, pad, connected, value}`, where stick `value` spans −1 to 1, trigger `value` spans 0 to 1, and `connected` reports whether that pad has a physical gamepad attached. Pad 0 may still report keyboard-mapped stick input when `connected` is false. Values reflect the host's game-facing input mapping and configured processing, rather than raw SDL samples. X is negative left and positive right; Y follows SDL's convention, with negative up and positive down. Triggers also remain available as digital `Gamepad:L2` and `Gamepad:R2` bindings. The query requires `game.read`.

| Domain | Planned operations |
| --- | --- |
| `game.info` | Game/build/platform identity, feature flags, API compatibility |
| `game.events` | Startup, tick phases, save/load, scene/map/floor transitions, pause/resume, shutdown |
| `game.player` | Read/write character state, health, movement, equipment, animation, status effects |
| `game.party` | Party roster, active character, formation, shared state, recruitment |
| `game.economy` | Wallet reads, currency credit, and balance-checked spending |
| `game.world` | Current world/map queries, time, weather, triggers, region state, travel and spawn points |
| `game.locations` | Register and resolve authored locations, map resources and transition metadata |
| `game.dungeons` | Define dungeons, floors, entrances, exits, and route graphs |
| `game.georama` | Settlement reconstruction definitions, piece placement, and placement rules |
| `game.entities` | Query, spawn, despawn, inspect, tag, and observe entities with stable handles |
| `game.combat` | Battle lifecycle, turns, targeting, damage/healing, formulas, status effects, rewards, and fighting styles |
| `game.items` | Item definitions, registration, grants, use callbacks, inventory, equipment |
| `game.weapons` | Weapon definitions, stats, elements, upgrades, recipes, effects |
| `game.skills` | Mod-owned skill trees, prerequisites, unlocks, ranks, and progression rules |
| `game.models` | Resolve native monster model entries, register and unregister logical model bindings, and replace or restore native monster model rows |
| `game.animations` | Bind and control supported native model motions |
| `game.characters` | Character and enemy definitions, stats, AI state, dialogue and interaction hooks |
| `game.quests` | Quest/objective registration, flags, progress, rewards, journal entries |
| `game.scripts` | Expose owner-scoped Lua functions and override the active native scene event-program runner |
| `game.content` | Register and resolve mod-owned items, characters, maps, dialogue, assets and recipes |
| `game.save` | Namespaced mod save data, migrations, save-slot lifecycle events |
| `game.input` | Mod-owned actions, key/controller bindings, prioritized context stack, input consumption |
| `game.audio` | Sound/music registration and playback with ownership and cleanup |
| `game.render` | Active dungeon camera snapshots, bounded dungeon orbit changes, and Chronicle's guarded owner-scoped town overhead camera; arbitrary callbacks, material registries, dynamic texture/model registries, HUD and world draw layers. Chronicle's package OBJ/GLB mesh replacement is a separate renderer feature. |
| `game.ui` | Menus, widgets, journal pages, notifications, prompts, generated settings, localization |
| `game.physics` | Both games support live-monster velocity reads and writes; collision queries remain open |
| `game.resources` | Managed resource loading, overrides, replacement, unload and lifetime tracking |
| `game.debug` | Capability-gated inspectors, per-mod profiling, overlays, command console |

### Reading and adjusting the active dungeon camera

```lua
local camera = assert(game.render.camera_get())
print(camera.scene, camera.eye.x, camera.target.x, camera.heading)
local orbit = assert(game.render.camera_set({distance = 120, height = 15, angle = 2.25}))
```

`render.camera_get()` takes no arguments and reads the currently active dungeon camera in both ports. It returns the camera `eye` and `target` coordinates, plus heading, pitch, and roll in the game's native angle units. It fails outside an active dungeon or if the native camera pose is invalid.

`render.camera_set()` accepts any non-empty subset of `distance`, `height`, and `angle`. Distance must be 8–300 native units, height −80–150 units, and angle −1000–1000 radians; the angle is normalized before the native camera receives it. The game eases toward the requested orbit angle in follow mode. For Chronicle Two's player-controlled camera, distance and height must also fit the active native camera's own limits, and its normal collision correction remains in control. The call requires a supported dungeon orbit camera: Chronicle must be in follow mode, while Chronicle Two supports its native follow and player-controlled camera modes. Native scene or camera transitions can later replace these values. Bounded HUD text layers are supported on both games; arbitrary draw callbacks and world-space layers remain unsupported.

Chronicle also supports `render.town_camera_set({enabled = true, height = 90, back = 22})` for a legacy-style overhead town view. Height is bounded to 40–500 and the forward/back offset to −200–200 native units. Requests are owned by the calling package and removed when it unloads. The native adapter applies the pose only in the main town walking loop with a valid player and the standard main camera; menus, events, dungeons, and camera transitions stay under native control. The `moonmod.expanded-town` package exposes the legacy O and L1+L3 toggles, offsets in Settings, and a Toggle action in the Mod Manager. ChronicleTwo reports this operation unsupported.

Chronicle's `render.first_person_toggle()` queues the native dungeon camera transition while normal dungeon play or the first-person view is active. The game loop performs the transition through its existing setup and cleanup path; the request is rejected in menus and other states.

Chronicle's renderer also supports package-owned 3D mesh replacements outside the Lua API. Put `models/<texture>.obj` or `models/<texture>.glb` in an enabled package; use `<texture>__<vertex-count>v.obj` for a source-vertex-specific replacement. An optional sibling JSON file accepts `scale`, `rotate_deg`, `offset`, and `flip_v`. Enabled packages can also supply `textures/<texture>.png` to replace the matching native texture. The renderer keeps the native material strips and follows native character skinning. Later packages in MoonFactory's resolved load order override earlier package assets; a matching exact-vertex file takes precedence over a generic texture file. Set `DC_DUMP_MODELS=1` before launching to dump source meshes as OBJ files into `<save-root>/mods/_dump/models`; each file name includes its source texture and vertex count. Model and texture files larger than 64 MiB are skipped. Direct runtime GLB loading flattens mesh instances in the selected scene, applies node hierarchy transforms, expands sparse accessors, and converts triangle, strip, and fan primitives into the renderer's triangle list. Point and line primitives are skipped. The package-generating editor is documented in [MODEL_REPLACEMENTS.md](MODEL_REPLACEMENTS.md).

The native 2D item/weapon icon path uses the `itemicon` and `wepicon` atlases; package PNG overrides named `textures/itemicon.png` and `textures/wepicon.png` repaint them while keeping the native icon rectangles and layout. This does not register new per-item icon entries or alter UV rectangles.

The API-major-1 catalog is defined in [`../src/api.cpp`](../src/api.cpp), with its shared types in [`../include/moonmod/api.hpp`](../include/moonmod/api.hpp), and has concrete paths for every domain above. Capability records report both `framework_api_major` and `domain_api_major`. The common Lua runtime implements identity and capability discovery, event subscription, per-mod save data and migrations, owned localization, managed package resources and audio, manager notices, digital input actions, dependency-scoped callable functions, persisted quest progress, and mod-owned skill trees. Both game ports bind player health/status, party and character queries, normalized world time, native story flags/counters and map flags, combat/entity reads, generation-checked direct enemy damage with owner-scoped damage formulas, and item list/get/register/give/remove/use calls to native game state. Both ports also provide bounded live-enemy healing through `combat.heal`; Chronicle adds generation-checked enemy slow/stop statuses, per-mod enemy-survival chance, and room-scaled procedural population; its damage formulas support conditional per-hit chance rolls. Fighting styles remain paused while model-rigging work is out of scope. Chronicle supports native Georama reads, request completion, toggling defined optional elements, registering data-only variants of loaded native solid pieces, and placing/removing existing or registered pieces in the active town editor. ChronicleTwo exposes saved Georama placements and analysis state, including request completion and knowledge and data-only piece variants that inherit a native model and placement rules, plus native-validated placement and removal of solid pieces in its edit scene. Both games bind `party.set_active` through their native character-loading paths, with Chronicle restricted to safe active-dungeon play; ChronicleTwo also applies its native quick-change eligibility rules. ChronicleTwo additionally supports party recruitment, weapon reads/registration/equip, and added floors on existing dungeons. Other gameplay operations remain explicitly unsupported until their game-state adapters and native tests land. Contract tests use a fake adapter for broad API dispatch coverage; native tests cover the supported game-state and content paths.

Chronicle supports `georama.get` and `georama.request_set` for native saved towns, plus `georama.place/remove` for built native pieces in the active town editor. `georama.register({id, name, template_part_id, town_id?, stock?})` adds a solid, data-only variant of a loaded native template. It allocates a persistent native definition id in slots 24–55 without changing the retail save record layout. Variants inherit the template's model, collision, footprint, and native placement behavior; they cannot declare geometry or asset overrides. Registration materializes only for the requested town (or any town when `town_id` is omitted), and `stock` initializes built stock from 1 through 999. The original build-menu definition scan can enumerate the appended variants; native UI text and icons still come from the inherited template, while the supplied mod name appears in API metadata. Unregistering is rejected while any saved town or active placement refers to the variant, and the stable native id remains reserved for that stable piece id across launches. The retail headless probe registers one variant, places it using the native editor path, reads it back from saved layout, removes it, and confirms it is gone. It does not verify a reload-visible render or player-save compatibility.

ChronicleTwo supports `georama.get` for its five saved reconstruction towns, including saved river-grid dimensions, positions, and per-cell river state, `georama.request_set` for completion of an already defined native request, `georama.condition_set` for a saved town's existing analysis condition, and `georama.request_known_set` for the native request-knowledge byte. During an active town edit scene, ChronicleTwo also returns bounded `placement_anchors` from placed parts with floor collision data; each anchor includes its native part id/name, position, surface height, floor area, and local floor bounds for placement discovery. This field is empty outside a matching active town editor. River-grid cells are reported as `cells[x][z]` booleans decoded from the saved town data. `georama.river_set({grid_index, x, z, has_river})` sets or clears an existing grid cell in an active town-edit scene. Grid and cell indices are zero-based; the call uses the native neighbor-shaping routines, persists the town, recomputes its Georama analysis, and emits deferred `game.georama.river_changed` only when a cell changes. The condition setter updates the native condition byte and can affect every request that depends on it; request knowledge is separate and does not mark a request complete. `georama.register({id, name, template_part_id})` adds a data-only piece variant to the native build definitions. The new entry inherits its template's native model, collision, placement rules, and material cost, and is available through the game's Georama build menu; per-town registration status appears in `georama.get().mod_pieces`. ChronicleTwo's `georama.place({id, position, rotation_steps})` places a registered solid piece in an active town-edit scene through the game's native collision, placement, stock, and count checks. The piece must already have built stock, so a mod can provide its definition while the game's normal menu handles material requirements. `georama.remove({placement_id})` removes a saved placement from the active town-edit scene using its current `georama.get()` id. The game decides whether a fixed piece may be removed, cascades native dependent removals, returns eligible build stock, releases housed villagers, and saves the updated town. Successful placement and removal emit deferred `game.georama.piece_placed` and `game.georama.piece_removed` events. Creating new river grids, authored geometry/assets, request rewards, and authored towns remain unsupported. The catalog continues to report unsupported authored locations, wholly new dungeons, native skill bonuses, and fighting styles. Both games support model-embedded motion indices through their animation APIs; standalone animation assets remain unsupported. ChronicleTwo's current dungeon support adds a floor to an existing native dungeon; it does not yet register a wholly new dungeon.

Both native adapters expose `combat.get` for the live dungeon enemy slots and `economy.get`, `economy.add`, and `economy.spend` over the active save's Gilda balance.
Both games expose native weapon definitions and owned/equipped instances, register data-only weapons that inherit a native template, grant weapons through native inventory, and change owned loadouts through their game-specific equipment rules. Chronicle's registration reserves one of 32 appended native weapon slots and inherits native menu assets; Chronicle Two materializes definitions through its item and weapon tables.

### Native combat snapshot

```lua
local combat = assert(game.combat.get())
print(combat.in_combat, combat.enemy_count)
for _, enemy in ipairs(combat.enemies) do
  print(enemy.id, enemy.hp, enemy.max_hp)
end
```

`combat.get()` takes no arguments and reads the current dungeon monster tables on both games. It returns `in_combat`, `enemy_count`, and live `enemies`; `in_combat` is true while at least one living monster participates on the current floor. Chronicle includes the monster family/name and poison, slow, and stun timers. ChronicleTwo includes its monster definition id, status flags, and target slot. Slot IDs identify entries only for the current floor and are not persistent entity handles. Outside an active dungeon context the call fails with `failed` rather than returning an empty success snapshot.

### Mod diagnostic overlay

```lua
assert(game.debug.overlay_register({id = "status", text = "NEW DUNGEON READY"}))
```

`debug.overlay_register` registers or updates a single-line diagnostic shown in the game's top-left overlay on both ports. IDs are scoped to the calling mod, so a mod may only replace its own entry. Text must contain 1–48 characters from the overlay font's supported ASCII letters, digits, spaces, and punctuation. At most four mod entries are retained at once, and the combined display is limited to 64 characters. Unloading the owner removes its entries. The call requires `debug.inspect`; it does not draw arbitrary UI or provide per-frame callbacks.

### HUD text layers

```lua
local layer = assert(game.render.layer_register({id = "status", text = "HP 24/30"}))
assert(game.render.layer_register({id = "status", text = "HP 25/30"})) -- update
assert(game.render.layer_remove({id = "status"}))
```

`render.layer_register` registers or updates one owner-scoped text layer in the native top-left HUD pass. `render.layer_remove` removes a layer owned by the calling mod. IDs cannot collide with diagnostic-overlay IDs; both APIs share a four-entry capacity and the 64-character combined text limit. Text is restricted to the overlay font's supported ASCII set and is drawn by the native presenter on both games. The call requires `content.register`; owner unload removes all layers. This renderer contract is text-only and screen-space; it does not expose arbitrary Lua draw callbacks, shapes, textures, or world-space rendering.

### Chronicle Georama state

```lua
-- Omit town_id to query the active Georama town, or pass 0 through 5.
local town = assert(game.georama.get())
for _, part in ipairs(town.placed_parts) do
  print(part.id, part.position.x, part.position.y, part.position.z)
end
for _, grid in ipairs(town.river_grids) do
  for x, row in ipairs(grid.cells) do
    for z, has_river in ipairs(row) do
      if has_river then print("river", grid.index, x - 1, z - 1) end
    end
  end
end

-- Chronicle Two only; requires an active town-edit scene and an existing grid.
assert(game.georama.river_set({grid_index = 0, x = 0, z = 1, has_river = true}))

local request = assert(game.georama.request_set({town_id = 2, request_id = 1, completed = true}))
print(request.previous, request.completed, request.changed)

-- Chronicle only: register a data-only variant in an appended editor slot.
local chronicle_variant = assert(game.georama.register({
  id = "garden-post", name = "Garden Post", template_part_id = 4,
  town_id = 2, stock = 1
}))
print(chronicle_variant.id, chronicle_variant.native_part_id, chronicle_variant.materialized)

-- Chronicle Two only: choose a loaded native template and add a build-menu variant.
local templates = assert(game.georama.get({town_id = 2})).native_piece_templates
local piece = assert(game.georama.register({
  id = "moonstone-pillar", name = "Moonstone Pillar",
  template_part_id = assert(templates[1]).template_part_id
}))
print(piece.id, piece.status)

-- Chronicle Two only: requires built stock and an active town-edit scene.
local placed = assert(game.georama.place({
  id = piece.id, position = {x = 12, y = 0, z = 8}, rotation_steps = 0
}))
print(placed.placement_id, placed.remaining_built)

-- Chronicle Two only: remove a current placement from the active town edit scene.
local removed = assert(game.georama.remove({placement_id = placed.placement_id}))
print(removed.removed, #removed.returned_stock)

-- Chronicle Two only: this may affect multiple requests that share the condition.
local condition = assert(game.georama.condition_set({town_id = 2, condition_id = 5, met = true}))
print(condition.previous, condition.met, condition.changed)

-- Chronicle Two only: reveal an existing request without completing it.
local knowledge = assert(game.georama.request_known_set({town_id = 2, request_id = 1, known = true}))
print(knowledge.previous, knowledge.known, knowledge.changed)

-- Chronicle only: toggle a defined optional element in the active town editor.
local element = assert(game.georama.element_set({
  town_id = 2, plot_id = 4, element_id = 1, enabled = true
}))
print(element.previous, element.enabled, element.changed)

-- Chronicle only: place and remove the registered variant by stable ID.
local mod_placed = assert(game.georama.place({
  town_id = 2, part_id = chronicle_variant.id,
  position = {x = 12, y = 0, z = 8}, rotation_quarter_turns = 0
}))
assert(game.georama.remove({placement_id = mod_placed.placement_id}))

-- Chronicle only: place an existing piece after it has native built stock.
local placed = assert(game.georama.place({
  town_id = 2, part_id = 4, position = {x = 12, y = 0, z = 8}, rotation_quarter_turns = 0
}))
print(placed.placement_id, placed.remaining_built)
assert(game.georama.remove({placement_id = placed.placement_id}))
```

Chronicle reads the active save's six native town records. The result includes the selected `town_id`, request completion count, all 24 plot records (completion flags, obtained/placed/stock values, and six attachment-element states), plus placed parts with native numeric part IDs or stable namespaced mod piece IDs, quarter-turn rotation, position, and a unique `placement_id` suitable for removal. While that town's editor is active, the result also includes `placement_areas` (world-space grid origins and dimensions) and `native_pieces` (loaded native part ids, footprint sizes, and available built stock) plus active-town `mod_pieces` (registered stable IDs, assigned slots, materialization state, and available stock). Passing `{town_id = 0..5}` reads a town even when it is not active; omitting it while in a dungeon fails with `failed`. `georama.request_set` writes the completion bit for an already defined request in that town and returns its previous and resulting states. `georama.element_set({town_id, plot_id, element_id, enabled})` toggles an optional element defined for a native plot. It requires that town's active editor, rejects absent elements and unsatisfied native element dependencies, updates the live editor state and save data, and emits deferred `game.georama.element_changed` when the value changes. `georama.place({town_id, part_id, position, rotation_quarter_turns})` accepts an existing native piece by numeric part ID or a registered data-only variant by stable ID and requires built stock; native fit, collision, and placement checks still decide whether it can be placed. Rotation is 0 through 3 quarter turns. `georama.remove({placement_id})` removes a placement identified by the current `georama.get()` result, subject to the game's fixed-piece and dependency rules. Successful place/remove calls save the active editor state and emit deferred piece events. Chronicle `georama.register({id, name, template_part_id, town_id?, stock?})` creates up to 32 data-only variants in persistent native definition slots 24–55, without changing the retail save record layout. Each variant inherits a loaded native solid template's model, collision, footprint, and native placement behavior. Custom geometry and asset overrides are unsupported. Registration materializes for the selected town, or all towns when `town_id` is omitted; `stock` initializes built stock from 1 through 999. The native menu can enumerate the appended definitions, but menu text and icons still come from the template; the mod-supplied name appears in API metadata. Unregister is refused while a saved layout or active placement refers to the variant, and the stable slot remains reserved for that stable ID across launches. The retail headless probe registers a variant, places it through the native editor path, verifies saved-layout readback, removes it, and confirms it is gone. It does not verify rendering after process reload or compatibility with player saves.

ChronicleTwo's `georama.get()` reads the active saved town while the game is in the town-edit loop; `{town_id = 0..4}` selects any saved town from other scenes. It returns the native save/culture counters, placed part IDs with stable save-slot identifiers, placement state, 24-step rotation, integer position, paint colors and house links, saved house occupants, the native known-request/met-condition flags, native `native_piece_templates` discovered for towns whose map definitions have loaded, and registered mod piece variants with their per-town native IDs/status. `known_requests` means the game has exposed those requests to the player; it does not claim they are complete. `georama.request_set({town_id, request_id, completed})` requires a loaded native request definition and changes its prerequisite condition bytes through the native request setter; the result reports previous/resulting completion, whether it changed, and the current town progress percentage. Conditions can be shared by requests, and the operation does not run request reward scripts. `georama.request_known_set({town_id, request_id, known})` changes one of the town's 16 native request-knowledge bytes and returns its previous/resulting value and whether it changed. `georama.condition_set({town_id, condition_id, met})` updates one of the town's 64 native analysis-condition bytes using the game's bounded debug setter. The condition can be shared by multiple requests, so the call does not mean a single request was completed. `georama.register({id, name, template_part_id})` copies a native piece definition into each loaded town's build table under a namespaced mod id, reusing its native model, collision, rules, and materials. The original Georama menu can then build the variant. `georama.place` is available only in the live town-edit scene, accepts registered solid template variants with available built stock, and uses the game's native collision and placement checks before updating saved layout state. `georama.remove` also requires the active edit scene and a current placement id from that town's saved layout; stale ids, fixed pieces, and river-grid pieces fail without changing state. The native removal routine handles dependency cascades, stock returns where the definition allows them, and housed villagers; the adapter updates the save, culture score, and analysis state. Neither operation provides authored geometry/assets or completes request rewards.

### Native dungeon entity query

```lua
local result = assert(game.entities.query({type = "monster"}))
for _, entity in ipairs(result.entities) do
  print(entity.id, entity.health.current, entity.health.maximum)
end
```

Both adapters currently support only `type = "monster"` while a dungeon is active. The query returns living monster slots with native definition, health, status, and position data. Chronicle also includes each actor's reveal state, combat stats and drop item, plus `native_model_id` when the floor's native model mapping is known. Chronicle keeps `id` as a slot label and returns a separate generation-checked `entity_id`; ChronicleTwo's `id` is already the generation-checked actor handle. Use those stable handles with `entities.get` to detect slot reuse. Chronicle updates actor generations from the native setup and floor-clear paths. ChronicleTwo assigns each returned entity a slot generation. Chronicle's `entities.set_stats({entity, hp?, max_hp?, defense?, reward_exp?, reward_money?, drop_item?})` changes one or more stats on a live revealed enemy. `hp` and `max_hp` are 1–1,000,000, and `hp` cannot exceed the resulting `max_hp`; `defense` is 0–32,767; `reward_exp` is 0–32,767; and `reward_money` is 0–2,147,483,647; `drop_item` is `-1` to clear or a valid built-in native item number. Chronicle also supports `entities.scale_set({entity, scale})`, an owner-scoped uniform visual multiplier from 0.5 to 3.0; it captures the native scale and restores it on actor reuse or mod unload. This operation only changes the live enemy model and shadow. If only `max_hp` changes, current HP keeps the same fraction. The operation rejects stale handles, unrevealed actors, and actors outside an active Chronicle dungeon; ChronicleTwo does not support it. Both ports support `entities.spawn` for registered enemy definitions; it shares the `characters.spawn` request shape and returns a mod-owned actor handle. Chronicle only spawns when the definition's exact native template has already been loaded for the current dungeon floor. ChronicleTwo reuses an already-loaded compatible template model/script; if the template is not loaded on the current floor, spawn returns a clean failure rather than loading assets dynamically. The `entities.despawn` API in both ports removes a live enemy spawned by the calling mod and clears per-actor runtime state and native collision/projectile references. It invalidates the generation-checked handle, updates floor alive counts, and skips kill credit and drops. Chronicle rejects mimics because the dungeon map retains their chest trigger; ChronicleTwo rejects actors held by a native interaction. Both adapters also attempt to despawn safe, live owned actors when their Lua mod unloads; native safety guards leave actors in place if despawn is unsafe. NPC/world-object spawning remains unsupported. Query calls outside an active dungeon fail instead of returning an empty list; handle lookups after leaving a dungeon return `status = "expired"`.

### Dungeon entity velocity

```lua
local enemies = assert(game.entities.query({type = "monster"}))
local enemy = enemies.entities[1]
local motion = assert(game.physics.velocity_get({entity = enemy.id}))
print(motion.velocity.x, motion.velocity.y, motion.velocity.z)
local changed = assert(game.physics.velocity_set({
  entity = enemy.id, velocity = {x = 0, y = 4, z = 0}
}))
print(changed.changed, changed.velocity.y)
```

Chronicle Two exposes the native `CCharacter2` velocity vector for a live dungeon-monster handle. Chronicle reads movement intent from its live native monster record. Components are game units per frame and use the game's world axes. The handle must still identify the same live actor; dead, stale, stopped, or out-of-dungeon handles fail for writes. `game.physics.velocity_set({entity, velocity})` writes a finite vector and returns the previous value, the resulting value, and whether it changed. Chronicle converts the requested vector into the native direction and speed fields, accounts for its falling term, and clears an active knockback so the requested movement takes effect. Chronicle Two writes its actor's native velocity vector. Either game can replace the value during its next AI or movement update; this does not bypass collision resolution.

Chronicle's `game.physics.velocity_get({entity})` result includes `source` (`native_movement`, `knockback`, or `stopped`) and `semantics = "native movement intent before collision resolution"`; when the enemy is falling, the native per-frame gravity term is included. The snapshot and setter operate on movement intent before collision resolution.

### Bounded spatial query

```lua
local nearby = assert(game.physics.query({
  shape = "sphere",
  center = {x = 0, y = 0, z = 0},
  radius = 250
}))
for _, match in ipairs(nearby.matches) do
  print(match.entity, match.distance, match.position.x, match.position.y, match.position.z)
end
```

Both games support this read-only query during an active dungeon. It returns live monster actor origins inside or on the sphere, with generation-checked entity handles, positions, and distances in game units. The center coordinates are bounded to +/-1,000,000 and the radius to 0-10,000. Results follow native actor-slot order. This does not test enemy collider size, walls, floor geometry, or line of sight; those collision queries remain unsupported.

### Monster slots and the awake limit

Retail Chronicle has 16 monster actor slots per floor and keeps only the 4 nearest monsters awake; the rest wait dormant until they come closer. The Chronicle PC port raises the slot table to 256 (`MONSTOR_SLOT_MAX`), so `characters.spawn` can keep placing enemies until 256 actors exist on the floor. Chronicle Two has 32 active monster slots (`MONSTER_ACTIVE_MAX`) and defaults to keeping the 5 highest-priority monsters awake (`priority_limit = 5`). In both games, `entities.set_active_limit({active = 1..slots})` sets how many stay awake at once and returns `{active, previous, slots}`:

```lua
local limits = assert(game.entities.set_active_limit({active = 16}))
```

The limit is global, takes effect on the next simulation step (updating any live `CMonsterMan` priority limit immediately in Chronicle Two), and stays until a mod changes it again (unloading the mod does not reset it). High awake counts cost CPU and draw time. Chronicle's nine-kind model table per floor is unchanged, so a floor can still hold at most nine different monster models.

### Bounded enemy healing

```lua
local combat = assert(game.combat.get())
local target = combat.enemies[1]
local result = assert(game.combat.heal({entity = target.entity_id, amount = 25}))
print(result.hp_before, result.hp_after, result.restored, result.changed)
```

`combat.heal` takes the `entity_id` returned by `combat.get` or `entities.query`, checks its generation, clamps at the monster's native maximum HP, and returns before/after health. Both games accept `{entity = generation_checked_handle, amount = 1..1000000}`. ChronicleTwo also accepts its former `{slot = live_enemy_slot, amount = 1..1000000}` form for existing mods. Dead, stale, invalid, or out-of-dungeon targets fail without changing state. Healing changes HP directly and does not simulate an attack or trigger rewards.

### Generation-checked scripted enemy damage

```lua
local combat = assert(game.combat.get())
local target = combat.enemies[1]
local result = assert(game.combat.damage({entity = target.entity_id, amount = 25}))
print(result.hp_before, result.hp_after, result.damage, result.death_queued)
```

`combat.damage` accepts the generation-checked `entity_id` returned by `combat.get` or `entities.query` and an exact HP amount from 1 to 1,000,000. A mod's registered combat formulas are applied to the requested amount before the native hit/death path. Chronicle respects its native invulnerability timer and hidden-enemy state; a surviving enemy enters the native hit script and lethal damage queues the native death script and floor kill accounting. ChronicleTwo respects the enemy's native no-damage flag, invulnerability timer, and catch state, then routes surviving and lethal damage through the native damage/death script requests. No player or weapon is credited for a scripted kill, and the operation does not create a collision hit, status proc, knockback, or weapon experience reward. Stale handles, dead enemies, and out-of-dungeon calls fail without changing state.

### Native enemy timed statuses (Chronicle)

```lua
local combat = assert(game.combat.get())
local target = combat.enemies[1]
local result = assert(game.combat.status_add({
  entity = target.entity_id,
  status = "slow", -- or "stop"
  duration_frames = 300
}))
```

`combat.status_add` supports `slow` and `stop` for live, revealed Chronicle enemies. The generation-checked handle prevents a delayed hit event from affecting a new enemy that reuses the same slot. Duration is 1–32767 native simulation steps, and an existing timer is only extended. ChronicleTwo does not expose this operation.

### Owned combat damage formulas

```lua
local formula = assert(game.combat.register_formula({
  id = "heavy-hits",
  operation = "multiply", -- "add", "multiply", "set", "chance_multiply", "random_multiply", or Chronicle-only "ramp_multiply"
  value = 1.5,
  priority = 10
}))
```

`combat.register_formula` registers an owner-scoped damage modifier. The accepted fields are `id`, `operation`, `value`, optional integer `priority`, optional `chance` for `chance_multiply`, optional `min_value`/`max_value` for `random_multiply`, and optional native `weapon_id`, `native_model_id`, and `character_id` filters. `ramp_multiply` is Chronicle-only and additionally requires `rate_per_second` (0–10) and `reset_after_frames` (1–36,000); it ramps the multiplier from 1.0 up to `value` at the specified rate, based on matching-hit frame timestamps, then restarts after a gap longer than the reset interval. Chronicle also accepts `target_hp_below_percent` (0–100), which only matches a live weapon target whose current HP percentage is strictly below the threshold; non-hit calls lack this context and skip such a formula. `random_multiply` chooses a uniform multiplier from its inclusive bounds for each matching hit. `combat.register_player_formula` accepts optional `weapon_id` and `character_id` filters. These filters are native numeric IDs; when present, a formula only applies when every supplied filter matches. Chronicle supplies weapon, enemy-model, attacker-character, and target-HP context for real weapon hits, and weapon and character context for native incoming player damage. Unfiltered formulas retain their previous behavior. IDs are local 1–64 character ASCII identifiers; each mod may own up to 64 formulas, and the game retains at most 512. `add` accepts −1,000,000 through 1,000,000, `multiply`, `chance_multiply`, and `random_multiply` accept multipliers from 0 through 100, and `set` accepts 0 through 1,000,000. `chance_multiply` also requires a finite chance from 0 through 100 and independently rolls for each matching hit. Modifiers run in ascending priority, then owner ID and formula ID order; random effects roll independently. Re-registering an owned formula ID updates its definition; an identical definition is idempotent. Unloading a mod removes its formulas.

Formulas modify positive damage after each game's native defense, elemental, and damage-block calculations in the native enemy-hit pipeline. Chronicle also publishes `game.enemy_hit` after an accepted positive native weapon hit. That event includes the generation-checked enemy `entity`, `slot`, player `attacker`, stable `weapon_id`, `native_weapon_id`, final `damage`, `element`, `frame`, and `native_model_id` when known. The event is informational and delivered on the next runtime pump; use the formula filters for damage changes. Formulas also modify explicit `combat.damage` requests when unfiltered. A zero or blocked base hit remains zero; final damage is clamped to 0–1,000,000, then rounded upward to a whole HP for scripted `combat.damage`. These formulas do not create new attack, animation, or collision behavior.

### Chronicle built-in item definitions

```lua
for _, item in ipairs(game.items.list()) do
  print(item.id, item.item_no, item.kind, item.message_id)
end

local bread = assert(game.items.get("chronicle:item:148"))
print(bread.use_flags, bread.initial_volume, bread.stack_kind)

for _, slot in ipairs(game.items.quick_slots()) do
  print(slot.slot, slot.id, slot.count)
end
assert(game.items.quick_slot_select({slot = 2})) -- selects only
assert(game.items.quick_slot_use({slot = 2})) -- requests a normal native action-button use
```

Chronicle reads built-in definitions from its native common-item and item tables. The stable ID is `chronicle:item:<item_no>`; results include the native message and icon indices, sort key, use and kind flags, initial volume, and stacking behavior. `items.give` and `items.remove` use Chronicle's native dungeon inventory routines, accept counts from 1 to 999, and report the actual quantity changed. They require an active save and respect the native item-pack capacity. Chronicle's `items.quick_slots()` returns the three native quick-item assignments as `{slot, item_no, id, count}` records; empty slots have null `item_no`/`id` and a zero count. `items.quick_slot_select({slot = 1..3})` changes the native selected slot only during active dungeon play. `items.quick_slot_use({slot = 1..3})` selects the slot and queues the ordinary native action-button path briefly; item animations, consumption, and effects therefore remain controlled by the game. `items.use` accepts built-in HP and water consumables and the four native single-status cures, plus registered mod HP/water items and status remedies. It defaults to the active character and accepts `character = "active"` or a joined playable character id such as `"xiao"`; the target must be alive and eligible for that effect. It delegates to Chronicle's `ItemUseFunc` and consumes exactly one item after the native routine accepts it.

### Chronicle data-only items

```lua
local item = assert(game.items.register({
  id = "starlight-tonic",
  name = "Starlight Tonic",
  kind = "consumable",
  template_item = 148, -- inherits Chronicle Bread's native presentation
  assets = {},
  effect = { kind = "heal", amount = 25 }
}))

local grant = assert(game.items.give({ id = item.id, count = 2 }))
local use = assert(game.items.use({ id = item.id }))
assert(use.healing == 25)
```

Chronicle supports data-only HP-healing, water-restoring, single-status, and combined status-cure consumables copied from a built-in item template. Definitions use no asset overrides; they inherit the template's native icon and message presentation while `items.get/list` return the mod's own stable ID and name. A status remedy can use `effect = {kind = "cure_status", status = "poison"}`; supported statuses are `freeze`, `poison`, `curse`, and `goo`. A `cure_all` effect clears those four supported ailments in one native item use. Both cure forms replace the template effect flags and call Chronicle's native `ItemUseFunc`; the item is consumed only when the active living character has at least one ailment it clears. Chronicle preserves its original 11 saved slot assignments first, then searches the native consumable range and allocates only rows whose definitions are unused. The retail headless smoke registers 12 simultaneous data-only items and confirms the twelfth uses native row 142; the total capacity depends on the unused rows in the game's fixed table. Assignments are stored at `<save>/moonmod/game-content/chronicle-item-slots.json` and kept as tombstones if a mod is removed, so a saved inventory number is never reassigned to a different item. The inherited localized display name remains a Chronicle-specific constraint. `items.give`, `items.remove`, and `items.use` accept the registered stable ID. Other effect types, per-item stack caps, and asset overrides are not implemented.

`debug.inspect()` reports the current native scene context:

```lua
local runtime = assert(game.debug.inspect())
print(runtime.scene_id, runtime.native_mode, runtime.native_map_id, runtime.native_floor_id)
```

The snapshot contains only scalar scene and map identifiers: `scene_id`, native mode number, `native_map_id`, and `native_floor_id`. Map and floor IDs are `nil` when no active native map or dungeon floor exists. It exposes no pointers or arbitrary process memory.

Mods that declare `debug.inspect` can also read their own bounded runtime counters:

```lua
local profile = assert(game.debug.profile())
print(profile.lua_memory.used_bytes, profile.lua_memory.limit_bytes)
print(profile.resources.handles, profile.resources.bytes)
print(profile.events.subscriptions, profile.storage.bytes)
```

`debug.profile()` reports bounded Lua allocator usage, event subscriptions, localization entries and bytes, loaded package-resource handles and bytes, and namespaced storage size. It does not expose other mods' data or claim to measure frame time. Both calls take no arguments; omitting the `debug.inspect` manifest permission returns `permission_denied`.

### ChronicleTwo data-only items

```lua
local item = assert(game.items.register({
  id = "starlight-tonic", -- automatically namespaced to this mod
  name = "Starlight Tonic",
  kind = "consumable",
  template_item = 274, -- an existing usable item number in ChronicleTwo
  max_count = 20,
  max_stack = 5,
  effect = { kind = "heal", amount = 25 }
}))

-- After the game's item tables have loaded:
local grant = assert(game.items.give({ id = item.id, count = 2 }))
local use = assert(game.items.use({ id = item.id, target = "max" }))
local removed = assert(game.items.remove({ id = item.id, count = 1 }))
assert(removed.removed == 1)
```

Registration can happen during mod startup, before native item tables load; the returned record then has `status = "pending"`. ChronicleTwo materializes those definitions after its item data and localized item messages load. A definition may omit `assets` or provide an empty table. Non-empty asset overrides are rejected by this first adapter. Only the mod namespace can be used in an explicitly qualified mod item ID. The current native adapter has a 32-item limit per running game session and supports only consumables copied from a usable vanilla item. `items.give` and `items.remove` operate on registered item IDs and report the actual quantities accepted or removed. `items.use` invokes ChronicleTwo's native use rules for an owned item and currently supports Max or Monica as the target. Arbitrary owner-provided Lua effect callbacks remain future API work.

The optional `effect` override supports `heal` with an integer `amount`, `power` to apply Chronicle Two's native timed power status, `cure_status` with one of `poison`, `slow`, `stop`, `curse`, `stone`, or `dry`, and `cure_all` for all six supported ailments. Each override replaces the template's native effect flags while retaining its native action, target, icon, model, and item-family behavior. These effects run through Chronicle Two's own item-use routine; the result includes before/after status flags, whether they changed, and the native power-status timer in frames. Unlisted effects such as repair, weapon absorption, stat growth, damage, and Lua callbacks remain unsupported. Chronicle supports native freeze, poison, curse, and goo single-status cures and a combined `cure_all` through the same data-only registration and native item-use path; the `power` effect is currently Chronicle Two only.

`items.list` and `items.get` include loaded built-in non-weapon definitions plus registered mod items. Built-in IDs use `chronicle-two:item:<item_no>`; mod item IDs use the registering mod's namespace. `items.give` and `items.remove` accept those IDs and the stable IDs returned by `weapons.list/get/register`, so registered weapons can enter and leave the inventory through the same native inventory path. They report the actual amount accepted or removed. The inventory API does not expose unregistered content by a guessed number; the ID must resolve through loaded game data.

### Chronicle native weapon definitions

```lua
for _, weapon in ipairs(game.weapons.list()) do
  print(weapon.id, weapon.owner, weapon.stats.attack, weapon.socket_count)
end

local dagger = assert(game.weapons.get("chronicle:weapon:258"))
for _, instance in ipairs(dagger.instances) do
  print(instance.character, instance.level, instance.equipped)
end

local blade = assert(game.weapons.register({
  id = "moonblade",
  name = "Moonblade",
  template_weapon = "chronicle:weapon:258",
  owner = "toan",
  stats = {attack = 37, durability = 81},
  stat_caps = {attack = 99, magic = 40},
  assets = {}
}))
local grant = assert(game.weapons.give({id = blade.id}))
assert(grant.added and grant.native_item_no == blade.native_item_no)
```

Chronicle lists its 120 retail weapons and registered definitions. `weapons.get()` accepts a `chronicle:weapon:<item_no>` ID for retail weapons, a mod-owned stable ID, native item number, or selector object. Results include base stats, caps, elements, monster effectiveness, socket count, experience/build-up metadata, and matching owned instances with equipped state. Each owned instance reports maximum `stats.durability`, live fractional `stats.durability_current`, per-instance `elements`, `vs_monster`, and `flags`. The ownership fields are `nil` without an active save. Registration allocates one of 32 appended native slots (377-408) and persists the stable ID to `moonmod/game-content/chronicle-weapon-slots.json`, so the same mod keeps the same native item number across launches. A definition inherits its template's owner, icon, name message, elements, sockets, experience, and build-up data; it may set `owner`, `stats.attack`, `stats.durability`, `stat_caps.attack`, and `stat_caps.magic`. `assets` must be empty. The API's `name` is available to Lua, but Chronicle's inventory menus still display the inherited native localized name. `weapons.give({id})` adds one copy through the game's inventory path and assigns it to the compatible character. `weapons.equip({id, character?, slot?})` equips one owned compatible weapon on a joined character. Chronicle only changes saved loadouts from an active Georama town, so the live dungeon weapon model and collision state are never changed mid-floor. The character defaults to the active member; `slot` is required when the character owns multiple copies. Repeating the current selection succeeds with `changed = false`. `weapons.stats_set({id, character?, slot?, attack?, endurance?, speed?, magic?, durability?, elem?, vs_monster?, flags?})` is Chronicle-only and updates exactly one owned native weapon instance. Scalar stats accept integers from 0 to 32767, `elem` takes five values and `vs_monster` takes ten values from 0 to 127, and flags accept a 16-bit value. Specify both `character` and `slot` when the weapon has multiple copies. A durability-maximum update preserves the current durability fraction; element and effectiveness writes update the native saved weapon data. `weapons.durability_set({id, durability, character?, slot?})` sets current durability from zero through that instance's native maximum without changing the maximum. New model/animation identities are not part of this registration path yet.

`weapons.definition_set({id, ...fields})` is Chronicle-only and changes the live base definition of one built-in weapon so future native drops and purchases inherit the edited values. It supports attack, endurance, speed, magic, durability, owner, six socket types and socket count, five element values, ten monster-effectiveness values, ABS fields, flags, both build-up masks, attack/magic caps, and chain position. Another mod cannot override a weapon definition already owned by a different mod. Chronicle restores the complete original definition when the owner unloads. Existing weapons in saves keep their saved stats, matching the legacy Expanded Data mod. This operation does not alter localized names, model identities, shop inventories, or daily rotations; Chronicle Two does not expose this operation.

### ChronicleTwo weapon definitions

```lua
for _, weapon in ipairs(game.weapons.list()) do
  print(weapon.id, weapon.name, weapon.stats.attack)
end

local blade = assert(game.weapons.get({id = "chronicle-two:weapon:80"}))
if blade.state then
  print(blade.state.level, blade.state.durability.current)
end
```

These read-only operations expose loaded native weapon definitions, including attack and attribute values, caps, special flags, build-up requirements, and the native model key. `weapons.get` also reports the number owned and the first matching owned weapon's live level, durability, absorption, stats, and custom name when an active save contains one. A selector may use the returned stable id or a native item number. Chronicle exposes the same list/get operations over its compiled weapon table and reports every matching owned instance; its definition shape uses Chronicle's native stat and buildup fields.

```lua
local equip = assert(game.weapons.equip({id = blade.id, character = "max"}))
assert(equip.equipped)
```

`weapons.equip` routes through ChronicleTwo's native inventory/equipment rules. The weapon must already be in the inventory, must be compatible with Max or Monica, and cannot already be equipped. If `character` is omitted, the active character is used and must be Max or Monica.

```lua
local result = assert(game.weapons.upgrade({id = blade.id}))
if result.upgraded then
  print(result.previous_level, "->", result.level)
end
```

Both games require an owned weapon whose native experience has reached its current level-up threshold. A weapon that is not ready, or is already level 99, returns a successful result with `upgraded = false` and `changed = false`. Chronicle applies its native weapon-stat calculation, durability roll, level cap, and attachment conversion while retaining cumulative experience; if the same weapon is owned more than once, pass both `character` and that character's `slot` to select one instance. ChronicleTwo applies the game's native durability roll, stat and fusion-point gains, character-favored element bonus, and absorption reset. Successful changes queue `game.weapon.upgraded` for the next runtime pump.

### ChronicleTwo data-only weapons

```lua
local blade = assert(game.weapons.register({
  id = "moonblade", -- automatically namespaced to this mod
  name = "Moonblade",
  template_weapon = 80, -- an existing ChronicleTwo weapon item number
  stats = {attack = 18, durability = 125, attributes = {3, 4, 5, 6, 7, 8, 9, 10}},
  stat_caps = {attack = 120, durability = 500, attributes = {50, 51, 52, 53, 54, 55, 56, 57}},
  durability_capacity = 31,
  level_up_exp = 40,
  assets = {}
}))

-- After native weapon tables load, the same stable ID resolves through weapons.get/list.
local definition = assert(game.weapons.get(blade.id))
local grant = assert(game.weapons.give({id = blade.id}))
```

The definition inherits its model, icon, weapon type, attack behavior, special flags, and build-up path from the template. Mods may override attack/durability values and caps, the eight elemental/stat attributes and caps, durability capacity, level-up experience, and inventory limits. New texture/model/audio files are not required or accepted by this adapter. Registration queues during mod startup and becomes native after the game's weapon tables load; before then, `weapons.get` returns `phase_violation`. ChronicleTwo accepts up to 32 mod weapons per session; Chronicle allocates up to 32 persistent native slots.

### Chronicle dungeon floors

```lua
local dungeons = assert(game.dungeons.list())
local shaft = assert(game.dungeons.get("demon-shaft"))
print(shaft.floor_count, shaft.deepest_floor_reached)

local annex = assert(game.dungeons.register({
  id = "moon-vault",
  name = "Moon Vault",
  dungeon = 0, -- extend Divine Beast Cave
  floors = {
    {id = "annex", name = "Moon Vault Annex", source_floor = 2, enemies = {"moon-sentinel"}},
    {id = "mirror", source_floor = "annex"}
  }
}))
print(annex.floors[1].native_floor_id, annex.floor_count)
```

Chronicle's `game.dungeons.list()` returns the seven native dungeons plus mod-registered extensions. `game.dungeons.get(id)` reads either kind by stable ID; a local suffix resolves in the calling mod's namespace first and then against the built-in catalog. `game.dungeons.register()` and its `game.world.register_dungeon()` alias append floors to native dungeons 0-4. Each floor requires a local `id` and a `source_floor`: an integer selects an existing floor's enemy layout, while a string selects an earlier floor in the same registration. Registration copies both normal and back-side native enemy layouts into new native floor slots. An optional `enemies` array replaces that floor's roster with up to nine character IDs registered by the same mod; an empty array creates an empty encounter. Mod-owned custom model resources must be available when the floor is registered. The game's procedural map builder supplies the existing dungeon theme, room geometry, and item rules; floor names and stable IDs are queryable metadata while Chronicle's native floor display remains numeric. One registration can add at most eight floors, and each target dungeon can have at most 25 floors total, matching Chronicle's fixed save and restriction-zone tables. Gallery of Time is already at 25 floors and Demon Shaft uses a separate 100-floor path, so neither accepts additions. Asset overrides, custom geometry, and standalone dungeon maps remain unsupported. Registered floors remain active for the current game session.

### Procedural floor layout (`dungeons.set_layout`)

Retail Chronicle builds every floor on a 20 x 20 grid and places at most 6 rooms (3-4 cells wide) in its top-left 16 x 16 corner. The Chronicle PC port enlarges the grid to 48 x 48 (`DNG_GRID`) and the room table to 64 (`DNG_ROOM_MAX`). Chronicle Two builds procedural floors on a 30 x 30 grid (`DNG_GRID = 30`) and enlarges its room table from 8 to 64 (`DNG_ROOM_MAX = 64`). Without a mod setting, floors still use the retail room count, area, and sizes.

```lua
local layout = assert(game.dungeons.set_layout({rooms = 24, area = 26, room_min = 3, room_max = 5}))
-- every floor built after this call uses the layout
assert(game.dungeons.set_layout({})) -- back to the native layout
```

`rooms` (2-64) is required unless resetting with `{}`; `area` (8-46 in Chronicle, default 46; 8-30 in Chronicle Two, default 30) is the side of the corner rooms are placed in; `room_min`/`room_max` (Chronicle 3-6, Chronicle Two 2-6; default 3-4) bound each room's side; Chronicle needs 3 because it puts a room's door on the middle cell of a wall and a 2-cell wall would put it on a corner, which has no door piece, and `area` must exceed `room_max`. In Chronicle Two, `room_min`/`room_max` also filter the floor builder's preset room table (`CreateRandomRoom`). The layout is global, stays until changed (unloading the mod does not reset it) and is not saved; a floor already built keeps its layout.

### Room-scaled encounter and chest population (`dungeons.set_population`)

```lua
local population = assert(game.dungeons.set_population({
  monsters_per_room = {min = 1.5, max = 3.0},
  chests_per_room = {min = 0.75, max = 1.5}
}))
assert(game.dungeons.set_population({})) -- restore native population targets
```

Chronicle rolls a target ratio for each generated floor, multiplies it by the realized room count, applies the active additive monster/chest bonus once, rounds up, and takes the larger of that result and the correspondingly modified native target. The native monster targets remain 15 for regular floors and 8 for back floors; the native chest target remains a random 4–7 before existing modifiers. Monster placement is capped by its native slot array. The PC port now provides 64 physical box slots, with 16 reserved for mimics/special boxes and regular chest targets capped at 48; the shared event table has 384 slots. Retail array sizes remain unchanged. Dense maps may still reach these audited capacities before the configured upper ratio. Requests are owned by the calling mod and are removed when it unloads.

### Enemy Variety survival chance (Chronicle)

```lua
local setting = assert(game.dungeons.set_enemy_survival({chance_percent = 25}))
assert(game.dungeons.set_enemy_survival({})) -- remove this mod's setting
```

On a live eligible ordinary enemy's first lethal hit, Chronicle makes one chance roll. Success leaves it at 30% of maximum HP and applies the native stop status for 70 simulation steps; the lethal hit is converted back to a nonlethal hit result. Enemies carrying a drop/key, with 3000 or more max HP, or on a boss floor are excluded. A failed roll is remembered for that enemy life. The request is mod-owned and cleared on unload.

### Exit gate behaviour (Chronicle)

Using the gate key on a floor's exit shows the native continue/leave window. Two replacements exist in the Chronicle patch but are switched off: a seamless mode (it did not build a room and pushed the player straight onto the next floor) and a walk-through exit room built from map pieces (unfinished). `game.dungeons.set_exit_room({enabled = true})` turns the exit room on for floors built afterwards, for testing only.

### ChronicleTwo added dungeon floors


```lua
local dungeon = assert(game.dungeons.register({
  id = "moon-vault",
  name = "Moon Vault",
  dungeon = 0, -- an existing Chronicle Two dungeon, numbered 0-6
  floors = {
    {id = "annex", name = "Moon Vault Annex", source_floor = 1,
     flags = {"exit", "boss"}, seal = "max"},
    {id = "gallery", name = "Moon Vault Gallery", source_floor = "annex",
     flags = {"sub"}, seal = "monica"}
  }
}))
```

Registration is queued until the native dungeon scripts for the selected dungeon have loaded. Each returned floor initially has `status = "pending"`; after the loader applies it, the floor includes its native floor number and `status = "registered"`. An integer `source_floor` names an existing native floor; a string names an earlier local floor in this same registration, so mods can build chained multi-floor branches. Optional `flags` accepts unique values from `exit`, `boss`, and `sub`; `seal` accepts `none`, `monica`, or `max`. These map to the game's native exit/boss/side-room behavior and character seal. The adapter appends each floor beside its source, uses an available route, and reuses the source floor's room resource and texture. It accepts no resource overrides, targets one of the seven existing Chronicle Two dungeon maps, and allows up to eight added floors per game session. Every source needs an available adjacent route. Added floor progress is stored by the stable package floor ID in a versioned PC-port sidecar keyed to the retail save payload fingerprint and save counter. A native save-slot test verifies clear, visit, and kill state survives writing and loading the slot while the retail save structure and ABI remain unchanged. The map graph still supports floor IDs 0 through 39, and mods still share the session limit of eight additions. This slice authors connected rooms in an existing dungeon map; it does not yet author a wholly new dungeon map, scripts, room geometry, or resource set. `game.world.register_dungeon()` remains a compatibility alias for the same operation.

ChronicleTwo's `game.dungeons.list()` returns registered additions, and `game.dungeons.get(id)` reads one by stable id (a local id resolves in the caller's namespace). Its floor records expose registration status, native floor numbers, room flags, and seals, so a package can inspect whether its additions have been applied. Chronicle's calls list built-in dungeons and appended procedural floors. A Chronicle mod can enter an appended floor by passing its stable floor ID to `game.world.transition`; the port switches to the native dungeon and floor before the dungeon simulation starts. These floors reuse native procedural geometry and assets selected by `source_floor`; custom room geometry and standalone dungeon maps remain unsupported.

### Active player health

```lua
local player = assert(game.player.get())
local set_hp = assert(game.player.set({hp = 50, character = "active"}))
local healed = assert(game.player.heal({amount = 15, character = "active"}))
local bench_heal = assert(game.player.heal({amount = 10, character = "monica"})) -- Chronicle Two
local damaged = assert(game.player.damage({amount = 5, character = "active"}))
local status = assert(game.player.status_add({status = "power", character = "max", duration_frames = 300})) -- Chronicle Two
assert(game.player.status_remove({status = "power", character = "max"}))
```

`player.get()` returns the active character id plus current and maximum HP and water. During an active dungeon it also returns the active player's native world `position` (`x`, `y`, `z`) in both games. `player.set({hp = integer, character = optional_id})` sets current HP exactly through the native HP update path; `player.set({max_hp = integer, character = optional_id})` changes Chronicle's maximum HP from 1 through 999 and clamps current and pending HP down if needed; `player.set({water = integer, character = optional_id})` sets Chronicle's current water gauge within its native range and clears any pending gauge interpolation. Each call sets exactly one field. ChronicleTwo does not support `max_hp` or `water`. These calls can target a benched character without switching the active character. `player.heal` and `player.damage` accept integer amounts from 1 through 32767 and use the game's native health state, which clamps at maximum and zero HP. The optional `character` accepts `"active"` or a playable character id: Chronicle supports Toan, Xiao, Goro, Ruby, Ungaga, and Osmond; ChronicleTwo supports Max, Monica, and the ridepod. These calls can update a benched character without switching the active character. Omitting `character` targets the active character, including ChronicleTwo's transformed monster when its live gauge is available. `player.damage` changes HP only; it does not synthesize damage formulas or knockback. `player.status_add/remove` use native ailment/status rules: Chronicle accepts `freeze`, `stamina`, `poison`, `curse`, and `goo` for the active character; ChronicleTwo accepts `poison`, `slow`, `curse`, `stop`, `power`, `stone`, and `dry` for Max or Monica. ChronicleTwo requires `duration_frames` from 1 through 32767 when adding a timed status (`slow`, `stop`, `power`, or `stone`) and rejects a duration for untimed statuses. Native interactions can reject a status (for example, ChronicleTwo power wards off poison and slow). Unsupported player mutations remain unsupported.

Chronicle's `player.get()` also returns `character_id` (the native party slot) and the equipped `weapon` object when present.

### Party queries

```lua
local members = assert(game.party.list())
local active = assert(game.party.active())
local npc = assert(game.party.recruit({npc_id = 7})) -- Chronicle Two
```

These read party membership and the active character from the current save. ChronicleTwo reads the native membership mask and reports stable ids (`max`, `monica`, `ridepod`, or `monster`), the native character id, and an `active` flag; `party.list()` also reports townspeople with stable ids such as `chronicle-two:npc:7` and their joined/in-party status. Chronicle reports its joined playable roster from the native party-size field and fixed character order, plus the active member. `party.set_active({id = "toan"|"xiao"|"goro"|"ruby"|"ungaga"|"osmond"})` changes Chronicle's active member through its native character and weapon loading routine. It requires an active dungeon, a joined and living target, no current player action or movement lock, and compliance with the game's restricted-zone and Osmond ground rules. ChronicleTwo's `party.set_active({id = "max"|"monica"|"ridepod"})` checks the game's native quick-change state and changes the active character through the native setter; the game can reject a switch when the character is unavailable, locked, at zero HP, blocked by status, or barred by the current floor. A successful changed switch emits `game.party.active_changed` with `previous`, `active`, and `changed`. `party.recruit({npc_id = 1..32})` runs ChronicleTwo's native townsperson join and in-party routines. The game allows one townsperson companion at a time; recruiting another moves the previous one to the joined/waiting state. Re-recruiting the current companion is an idempotent no-op. Successful recruitment emits `game.party.recruited` with `id`, `npc_id`, `recruited`, `changed`, and `replaced`. Chronicle recruitment remains unsupported because its playable cast has no separate NPC companion roster.

Chronicle also provides `party.town_active()` and `party.town_set_active({id = "toan"|"xiao"|"goro"|"ruby"|"ungaga"|"osmond"})` for the visible town avatar. These calls require an active Chronicle town scene. Toan is always available; other characters require a positive native maximum-HP value, matching the legacy town selection check. Switching loads the character's native town-compatible model and animation resources, preserves position and rotation, and maps town motion IDs onto the selected character's motions. It does not change the saved dungeon-active character. `town_set_active` queues the model reload until the native scene is walking safely. These are Chronicle-only; ChronicleTwo does not expose town-avatar replacement.

### Playable character records

```lua
for _, character in ipairs(game.characters.list()) do
  print(character.id, character.kind, character.in_party, character.hp, character.max_hp)
end

local monica = assert(game.characters.get({id = "monica"})) -- Chronicle Two
local xiao = assert(game.characters.get({id = "xiao"})) -- Chronicle
```

`characters.list()` returns the game's known playable character records; `characters.get()` accepts one stable id as a string or `{id = ...}`. Records include native character ids, party/active flags, and health where the save has a corresponding gauge. Chronicle lists its six party characters. ChronicleTwo lists Max, Monica, the ridepod, and the monster transformation; the latter exposes health only while transformed. ChronicleTwo also appends mod-registered enemy definitions to this list and resolves their namespaced ids through `characters.get`.

### ChronicleTwo data-defined enemy variants

```lua
local sentinel = assert(game.characters.register({
  id = "sentinel",
  kind = "enemy",
  name = "Bright Sentinel",
  template_monster_id = 0, -- reuse the native Sewer Rat model and AI script
  stats = {hp = 300, attack = 75, defense = 41, reward_exp = 90, reward_money = 55},
  assets = {}
}))
assert(sentinel.status == "registered")
local definition = assert(game.characters.get(sentinel.id))
print(definition.native_monster_id, definition.model, definition.script)
```

`characters.register` creates a distinct native enemy definition from an existing ChronicleTwo monster template. The stable id is qualified with the registering mod's id. `stats` may override `hp`, `attack`, `defense`, `reward_exp`, and `reward_money`; omitted values inherit from the template. The model, AI script, drops, and other behavior continue to use the chosen native template, and non-empty asset overrides are rejected. Names are limited to 31 UTF-8 bytes for the native table. A port session can register up to 32 variants.

`characters.spawn({character = id, position = {x, y, z}, rotation = optional {x, y, z}})` uses a compatible native template model/script reference loaded during floor initialization and places the variant through the native actor setup path. Register the character before entering the target floor so Chronicle Two's native floor loader can preload its template; spawning returns a clean failure if the needed template is absent. Positions are game units; rotations are radians. The registering mod owns the definition and is the only mod allowed to spawn it. The response includes a session entity handle, native slot, and generation. `characters.get(handle)` and `characters.list()` report its live position and combat stats; handles report `dead` after the native actor dies and `expired` when its slot is reused or its dungeon closes. The actor continues its inherited native AI until death or dungeon teardown, including after its owner mod unloads. Enemy definitions and their loaded resources stay reserved until the game process exits so active actors never retain pointers to cleared definitions. The retail headless probes reuse retail models and AI, so they do not prove authored model assets, standalone animation data, or custom AI. Both verify embedded motion playback and cleanup; Chronicle's probe also verifies native velocity write/read-back. Chronicle Two's item-and-dungeon smoke enters a newly registered floor, spawns the data-only enemy, and resolves the live entity handle.

### Chronicle data-defined enemy variants

```lua
local jacket = assert(game.characters.register({
  id = "moon-jacket",
  kind = "enemy",
  name = "Moon Jacket",
  template_monster_id = 0, -- inherit Master Jacket model, AI, effects, and drops
  stats = {hp = 500, defense = 23, reward_exp = 17, reward_money = 91},
  assets = {}
}))
local resolved = assert(game.characters.get(jacket.id))
print(resolved.native_monster_id, resolved.model, resolved.script)
```

Chronicle registers up to 32 enemy variants through its native monster-model resolver. A variant can inherit the selected template's model, AI script, effects, family, and drop rules while overriding `hp`, `defense`, `reward_exp`, and `reward_money`, or it can select a package-owned model binding through `models.register`. Chronicle's monster table has no per-definition display string, so `name` is returned by the API while the in-game lock-on label still uses the template's localized name.

`characters.spawn({character = id, position = {x, y, z}, rotation = optional {x, y, z}})` and its `entities.spawn` alias use the native actor initializer and inherited AI. Data-only variants require their exact template to be loaded on the current floor. A character using a registered custom model can load that model into a free slot in Chronicle's native nine-model floor table; spawning fails with a reason when the floor loader is not ready or all slots are occupied. The registering mod owns the definition and is the only mod allowed to spawn it. Nearby mod-owned enemies enter Chronicle's active native state immediately, and the view budget (4 awake enemies by default) prioritizes mod-owned enemies before filling remaining slots with vanilla actors. The response includes a generation-checked `entity_handle`, slot, position, and supported stats. Resolve it with `entities.get`; it reports `dead` after death and `expired` after native slot reuse or dungeon cleanup. `entities.despawn({id = entity_handle})` removes a live owned non-mimic enemy without kill credit or drops.

### Native monster model resolution

```lua
local model = assert(game.models.resolve({monster_id = 0}))
print(model.model, model.source)
for _, asset in ipairs(model.assets) do
  print(asset.slot, asset.game_path, asset.overridden)
end
```

`models.resolve({monster_id = id})` reads the current port's native monster table, including registered enemy variants. It returns the model and script names, the `.chr` path used by the native loader, and whether that path has a resource override. Chronicle uses `dun/monstor/<name>.chr`; Chronicle Two uses `dungeon/monster/<name>.chr`. Both ports support `models.resolve({id = model.id})` for package model bindings. It returns the binding's model and script paths, active override state, template monster id, and availability status.

Both games can bind a new monster model path to a package asset, then use it in a new native-backed enemy definition. Chronicle Two uses `dungeon/monster/`; Chronicle uses `dun/monstor/`:

```lua
assert(game.resources.override({
  path = "resources/moon-sentinel.chr",
  game_path = "dun/monstor/moon_sentinel.chr"
}))
local model = assert(game.models.register({
  id = "moon-sentinel-model",
  template_monster_id = 0,
  model = "moon_sentinel"
  -- Optional: script = "moon_sentinel_ai" when its .stb is also overridden.
}))
local enemy = assert(game.characters.register({
  id = "moon-sentinel",
  name = "Moon Sentinel",
  kind = "enemy",
  model = model.id,
  stats = {hp = 450, attack = 80}
}))
```

`models.register` requires the registering mod to own the `.chr` override. Chronicle's pack must provide `info.cfg`; Chronicle Two's pack must provide `<model>.cfg`. A custom `script` additionally requires an owned `.stb` override; when omitted, the template's native script is inherited. `models.unregister({id = local_model_id})` removes the logical model binding when no registered character or existing embedded-motion definition refers to it; it leaves the separately registered resource overrides in place for `resources.unoverride` or owner cleanup. The character's native table row points at these asset stems. Chronicle can load a custom model after floor entry when a slot is free in its native nine-model table; Chronicle Two loads it through the native monster manager. Chronicle bounds package `.chr` and `.stb` reads to 2 MiB after sector padding; Chronicle Two uses a 3 MiB limit. `models.replace({monster_id, model})` changes the `.chr` model stem on a native monster-table row, and `models.remove({monster_id})` restores the value captured before that mod's first replacement. Replacement requires the calling mod to own the matching `resources.override` path (`dun/monstor/<model>.chr` in Chronicle or `dungeon/monster/<model>.chr` in Chronicle Two), and another mod cannot replace or remove its binding. A row whose model is loaded on the active dungeon floor cannot be changed until that floor is left. Unloading the owning mod restores its native model binding. `resources.unoverride` refuses to remove a `.chr` path that an active native model replacement still uses, and it protects `.chr` and custom `.stb` paths held by a registered model because native model definitions persist until process exit. The API checks ownership and size but does not validate the model format or rig compatibility. Existing embedded-motion playback remains at its verified baseline; it is not expanded by model binding removal.

### Animations

Both Chronicle games expose animation operations for motion entries embedded in an owned, registered `.chr` model. This binds existing model motion data; it does not author new motion data or load a standalone animation file. This implemented playback path is retained as a frozen baseline: animation API expansion, standalone animation authoring, and fighting-style authoring are deferred until model rigging is in scope.

```lua
local animation = assert(game.animations.register({
  id = "sentinel-idle",
  model = model.id,
  motion_index = 0
}))
local playback = assert(game.animations.play({
  animation = animation.id,
  entity = spawned.entity_handle
}))
local stopped = assert(game.animations.stop({entity = spawned.entity_handle}))
```

`animations.register({id, model, motion_index})` binds an integer motion index from 0 to 255 to a stable mod ID. `model` must be a `models.register` entry owned by the same mod, with its `.chr` override still active. The API defers motion-table validation until a compatible model is loaded. `animations.play({animation, entity})` accepts only a living enemy spawned by the same mod with `characters.spawn`, using the model bound to that animation. Chronicle checks the loaded motion table on each rendered part and queues a native restart request; Chronicle Two checks the loaded motion table on the root and linked parts and calls the native motion setter. `animations.stop({entity})` only acts on a playback started by the caller. If native AI has switched to another motion, the adapter leaves it alone; otherwise it restores the previous motion request when available. Despawning an animated enemy releases its tracked playback state, and owner unload stops tracked playback before despawning live enemies. The response reports stable IDs and indices rather than native motion names because game data may encode those names in a legacy non-UTF-8 character set. These APIs play motion clips already embedded in a registered model. This playback support is kept at its verified baseline; further animation work, standalone animation authoring, and fighting-style authoring are deferred until model rigging is in scope. Playable-character animation control remains unsupported.

### Wallet and currency

```lua
local wallet = assert(game.economy.get())
local credit = assert(game.economy.add({amount = 50}))
local purchase = assert(game.economy.spend({amount = 25}))
```

`economy.get()` returns Gilda and the native wallet limit. `economy.add()` accepts 1-32767 Gilda and calls the game's native credit rule, clamping at the game's cap. `economy.spend()` accepts the same range and fails without changing the wallet when funds are insufficient. Chronicle's wallet holds at most 65535; ChronicleTwo's holds at most 999999. Shop pricing, transaction callbacks, and reward hooks beyond direct wallet updates remain game-owned.

### World location

```lua
local world = assert(game.world.get())
print(world.context, world.map_id, world.dungeon_id, world.floor_id)
```

`world.get()` reports native area/map identifiers, active game context, the native adventure `day`, and the native world-time cycle. Chronicle identifies dungeon scenes from the active game mode, then reports the native dungeon and floor even when the dungeon belongs to an overworld region. During an active dungeon, Chronicle also reports `room_count`, `floor_seed`, `back_floor`, and the active additive `room_bonus_percent`, `monster_bonus_percent`, and `chest_bonus_percent`. `day` is Chronicle's saved adventure-day counter and is available to mods that need stable daily rotations. `dungeon_id` and `floor_id` are `nil` outside an active dungeon; `sub_map_id` is available in ChronicleTwo. These are the games' native identifiers, so mods should keep them as data and resolve stable mod content ids through the corresponding registration API.

```lua
local world = assert(game.world.get())
print(world.time.fraction) -- normalized to [0, 1)

local changed = assert(game.world.set_time({fraction = 0.75}))
print(changed.time.fraction)
```

The normalized `fraction` represents the same portion of the native day/night cycle in either game. `native_time` and `native_cycle_hours` report the game's stored units: Chronicle uses a 12-unit cycle and ChronicleTwo uses 24 hours. Setting the fraction requires `game.write` and an active save. Chronicle updates the saved time and the live Georama clock when the editor loop is active; other contexts use the saved value on the next world entry. ChronicleTwo applies the native `CScene::SetTime` routine to a live town or dungeon scene and updates the save, or stores the value for the next scene when no playable scene is active. Values must be finite and in `[0, 1)`; invalid input leaves the saved time unchanged. This does not change the day counter.

```lua
local story = assert(game.world.story_flag_get({id = 37}))
local updated = assert(game.world.story_flag_set({id = 37, value = true}))
local counter = assert(game.world.story_value_get({id = 3}))
assert(game.world.story_value_set({id = 3, value = counter.value + 1}))
local chest = assert(game.world.map_flag_get({map_id = 18, flag_id = 4}))
assert(game.world.map_flag_set({map_id = 18, flag_id = 4, value = true}))
```

These calls read and write the native save's raw story flags, integer story counters, and per-map flag bits. Story flag IDs are `0-8191` in Chronicle and `0-2047` in ChronicleTwo. Story value IDs are `0-31` in Chronicle (signed 32-bit values) and `0-127` in ChronicleTwo (signed 16-bit values). Map flag IDs are `0-511` across map IDs `0-79` in Chronicle, and `0-127` across map IDs `0-255` in ChronicleTwo. Reads require `game.read`; writes require `game.write` and an active save. Setters return the previous value, resulting value, and whether it changed. Invalid IDs and values outside each game's native range are rejected. Flag numbers are game data indices, not portable names: use the compatibility API to branch by game, and avoid changing a flag unless its meaning is known for that game version. Changed story flags, story counters, and map flags emit `game.story_flag_changed`, `game.story_value_changed`, and `game.map_flag_changed` respectively; unchanged writes emit no event.

### Chronicle native locations

```lua
for _, location in ipairs(game.locations.list()) do
  print(location.id, location.name, location.kind, location.visited)
end

local cave = assert(game.locations.get({id = "chronicle:location:divine-beast-cave"}))
print(cave.native_map_id, cave.frame, cave.native_progress)
```

Chronicle exposes its 16 native world-map destinations through `locations.list/get`: settlements, dungeons, fields, and Demon Shaft. Each record includes its stable `chronicle:location:<id>` identifier, native map ID, world-map frame, kind, and visit/clear progress read from the save. `locations.get` accepts either the stable ID or local suffix. Mods can also register a namespaced field location by reusing a compatible built-in field map:

```lua
local field = assert(game.locations.register({
  id = "moon-grove",
  name = "Moon Grove",
  source_map_id = 23 -- built-in field map; map 23 uses gedit/s13
}))
print(field.id, field.native_map_id, field.status)
```

`locations.register` requires an active save and exactly `id`, `name`, and `source_map_id`. The source must be a built-in field whose data directory is indexed by the native reader. Chronicle reserves map IDs 70–79 and aliases the first available, unoccupied `gedit/s60`–`gedit/s69` directory to the selected field's retail assets. This creates a new location identity and route using a compatible copied field; it does not create new map geometry or a new native map format. A mod may replace individual files under its reserved directory with `game.resources.override`, such as a package-owned `resources/mapinfo.cfg` targeted at `gedit/s60/mapinfo.cfg`. Each aliased override is limited to 8 MiB and stays pinned for the game session because the native map loader cannot safely unregister it. Registration is limited to ten locations total per session, subject to the reserved directories being unused. The result and `locations.list/get` include a stable `chronicle:location:<package-id>:<local-id>`, `source = "mod_package"`, native and source map IDs, owner, and save-backed visit state.

Chronicle can queue a transition to a built-in settlement from an active town or dungeon:

```lua
local town = assert(game.world.transition({id = "chronicle:location:norune-village"}))
if town.queued then
  print("Returning to", town.id, town.native_map_id)
end
```

`world.transition` requires `game.write`. In Chronicle it accepts a stable built-in settlement ID or local suffix, the full stable ID of a floor registered by `game.dungeons.register`, or a registered mod location ID. Mod locations can be entered from an active settlement, another registered location, or a dungeon; native settlement destinations can be reached from those same contexts. A floor transition can start from a town or dungeon and is applied after the current scene loop returns, before the destination dungeon simulation starts. Requesting the current destination is a no-op; title/menu scenes, built-in fields and dungeons as destinations, unregistered floor/location IDs, and a second request while a native map jump is pending return a failure. ChronicleTwo accepts built-in Georama towns and registered MoonFactory interior maps from active town or dungeon scenes, and a retail headless run confirms returning from a copied interior to a native town. Compatible copied maps have passed retail-data scene-load, render, and return checks; native formats for newly authored maps remain unverified. Custom dungeon geometry/assets, route graphs, and mod-authored Georama settlements remain unsupported.

On a registered Chronicle mod location, `game.world.get()` returns `context = "location"`, its native map ID and stable location ID. `area_id` is `null` when the native save has no active Georama area for that field map.

### ChronicleTwo native locations

```lua
for _, location in ipairs(game.locations.list()) do
  print(location.id, location.name, location.kind, location.native_map_id)
end

local map = assert(game.locations.get({id = "chronicle-two:location:d01f01"}))
print(map.map_name, map.title, map.area_id, map.selection_category)
```

ChronicleTwo reads the map catalog loaded from the game's localized `map/map*.cfg` table. Each record includes a stable `chronicle-two:location:<map_name>` id, native map number and type, localized title, map selection category, area, sound bank id, and optional additional path. `locations.get` accepts the stable id or the local map name. Headless smoke injects a tiny native-format map table and exercises list/get through Lua against the game executable.

### Chronicle Two authored locations

```lua
for _, extension in ipairs({"map", "cfg"}) do
  assert(game.resources.override({
    path = "resources/cave." .. extension,
    game_path = "map/m/moo/n_c/moon_cave." .. extension
  }))
end

local cave = assert(game.locations.register({
  id = "moon-cave",       -- local id; returned id is namespaced to the package
  map_name = "moon_cave",  -- native map stem, 3-15 lowercase letters/digits/_/-
  name = "Moon Cave",     -- display title, 1-127 printable UTF-8 bytes
  texture_source_map = "i01h01" -- reuse this native map's .mpk/.ipk packs when they are not packaged
}))
```

`locations.register` requires `content.register` and owned `.map` and `.cfg` overrides under the native `GetMapPath(map_name)`. A package may also own `.mpk` and `.ipk` packs. When either pack is omitted, `texture_source_map` must name an existing native map; the loader reads the missing pack from that map. The same option maps embedded texture provenance to that native map's converted texture catalog. It does not convert or add new model or texture assets. Owned `.efp`, `.sky`, and `.stb` files are also accepted. Every provided asset must be non-empty and no larger than 3 MiB after sector padding. A registration made before the native map catalog loads stays `pending` and materializes when the catalog becomes available; otherwise it appends a `MAP_TYPE_INTERIOR` row after all native rows. Native indices are unchanged. The framework caps registrations at 32 and reserves 64 appended native map rows. Map names cannot collide with native entries or another registered mod location. `locations.register` and `locations.list/get` report `texture_source_map` as a map stem or `null`. They also return a stable `chronicle-two:location:<package-id>:<local-id>`, `source = "mod_package"`, native map number/type, owner, and required/optional resource paths. The native catalog and pinned assets cannot be unregistered safely during the process, so a registered location and its overrides remain for that game session; restart the game to remove or replace it.

`world.transition({id = cave.id})` queues the native map jump from an active town or dungeon; the retail probe also verifies a return from the copied interior to a native town. Chronicle Two's native loader remains responsible for parsing the map files and initializing the destination. A retail-data headless run copied only the native shop `.map` and `.cfg` files into package resources, registered the result as a new interior at map index 189, and entered it through `CScene`. It omitted the `.mpk` and `.ipk` package files; `texture_source_map` loaded those from the donor map. The run also rendered the modified layout and returned to a native town. This verifies package-owned layout/config scripts with native pack reuse; it does not validate wholly authored map formats or assets. The synthetic headless smoke checks registration, stable lookup, asset ownership/pinning, pack alias reads, texture-source metadata, and transition guards. This API registers one interior map identity; it does not create dungeon floor graphs, custom routes, dialogue, or model rigs.

ChronicleTwo can queue transitions to built-in Georama towns or a registered interior map from an active town or dungeon:

```lua
local town
for _, location in ipairs(game.locations.list()) do
  if location.kind == "georama" then
    town = location
    break
  end
end
assert(town, "no native town is available")
local transition = assert(game.world.transition({id = town.id}))
if transition.queued then
  print("Returning to town", transition.id, transition.native_map_id)
end
```

`world.transition` requires `game.write` and accepts a stable location id or native map name from the loaded catalog. It queues a built-in Georama town or registered MoonFactory interior map destination from the active town or dungeon scene; requesting the current map is a no-op. ChronicleTwo also accepts the stable id of a registered floor after that floor has been materialized in the native dungeon graph, but only during active gameplay in the matching native dungeon, outside menus and event scripts. It queues the native floor transition and returns a no-op when already on that floor. Other inactive contexts, unmaterialized floors, and floors belonging to another dungeon fail cleanly. Chronicle implements built-in settlement and registered-floor transitions; ChronicleTwo implements built-in town, registered interior-map, and same-dungeon registered-floor transitions. A compatible copied map has passed a retail-data scene-load/render and return-trip smoke; authored map asset formats remain unverified.

### Shared quest lifecycle

Inventory mutation events support API-driven progression without polling. After `game.items.remove` removes one or more items successfully, the runtime queues `game.item_removed` for the next pump; its payload includes the stable item `id`, `source_mod`, `frame`, and the adapter's `requested`, `removed`, and `remaining` values when present. A zero-removal result emits no event. Quests can subscribe with an exact `match` filter on `id`. Removal through the game's own menus is not currently observed.

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

`quests.register` accepts one to 64 uniquely named objectives, stores a definition under the registering mod's id, and is idempotent when the same definition is registered again. Conflicting re-registration fails. Quest ids use 1-64 ASCII letters, digits, `.`, `_`, or `-`; objective ids and titles are bounded, and targets are positive integers up to 1,000,000,000. A mod can register up to 128 quests within its existing 128 KiB save-data limit. `quests.get()` returns that mod's quests; `quests.get({id = ...})` returns one owned quest and its objective progress. Status moves from `registered` to `active` to `completed`. `quests.start` is idempotent for an active quest, while completed quests cannot be restarted. `quests.advance` adds one by default or a caller-provided positive integer, clamps at the objective target, and completes the quest when every objective reaches its target.

Quest definitions and progress persist in the mod's save file under a reserved framework key. The key is hidden from `game.save` and `moonmod.storage`, so ordinary mod data and schema migrations cannot overwrite it. Registration requires `content.register`; reads require `game.read`; start and progress changes require `game.write`. Definitions may include up to eight currency rewards `{kind = "currency", amount = 1..32767}`, item rewards `{kind = "item", id = stable_item_id, count = optional 1..999}`, and/or weapon rewards `{kind = "weapon", id = stable_weapon_id}`; each weapon reward grants one weapon. Declaring a non-empty reward list also requires `game.write`. The framework applies currency, item, and weapon rewards through `economy.add`, `items.give`, and `weapons.give` respectively when the quest first completes, before publishing `quests.completed`. That event includes a `rewards` result array with each requested amount or count, item or weapon id, its `granted`, `partial`, or `failed` status, and the adapter result or failure message. Completion is saved before payout, so normal repeated events cannot pay twice; a process interruption between the save and payout can lose a reward, and incomplete payouts are reported but not retried. Item and weapon rewards must reference stable IDs available through the corresponding game API, such as definitions registered by the same mod. Other reward kinds are not supported yet. State changes emit `quests.started`, `quests.objective_advanced`, and `quests.completed`, with an owned quest id in the event payload. An objective may include `event = "game.some_event"` and an optional `match` object. Whenever the runtime publishes that `game.*` event, each matching objective on an active quest advances by one; every field in `match` must exactly match the same scalar field in the event payload. Current producers include `game.tick`, successful item-use calls (`game.item_used`), successful API item/weapon grants (`game.item_given`), native dungeon pickups in both games (`game.item_picked_up`), mod-owned character creation (`game.enemy_spawned`), native enemy defeats (`game.enemy_defeated`), native weapon upgrades in both games (`game.weapon.upgraded`), changed weapon equips in both games (`game.weapon.equipped`), changed native story flags/counters/map flags, Chronicle Georama requests, Chronicle Two Georama request completion, conditions/request knowledge, and successful piece placement/removal, Chronicle Two active-party switches and successful companion recruitment, frame-observed `game.world.location_changed`, and the top-level scene transition events below. `game.enemy_spawned` is emitted only after `characters.spawn` succeeds and is delivered on the next runtime pump. It includes the generation-checked `entity`, stable `character_id`, native `slot`, slot `generation`, world `position`, game-specific native character/model id, `source_mod`, and call `frame`. `game.enemy_defeated` is queued when the native game accepts an enemy death request and delivered on the next runtime pump, after the active callback returns. Chronicle publishes at its confirmed kill boundary; Chronicle Two publishes on an accepted lethal `combat.damage` request or when the native `MONSTER_PROG_DEAD` program begins. A generation check suppresses duplicate publication when the later dead-state opcode runs. The event includes the generation-checked `entity` handle, native `slot`, and `source` (`combat` or `scripted`); mod-spawned registered characters also include their stable `character_id`. Chronicle includes `native_model_id` when known and positive `damage` when available; Chronicle Two includes `native_monster_id`. Native mutation events are queued until the next runtime pump so event handlers run after the active API callback returns; unchanged setters and repeated recruitment do not emit an event. Their payloads include adapter result fields plus `source_mod` and the call `frame` when the event is published from an API mutation. Location-change events contain the current scalar location fields, `previous` snapshot, and `frame`. `game.item_used` always includes the stable item `id`; fields such as `item_no`, `target`, `character`, `effect`, `consumed`, and `remaining` are included when the game adapter returns them. This event currently covers item use through the MoonFactory API, not item use performed directly through the game's own menus. `game.item_given` is queued after successful `game.items.give` and `game.weapons.give` calls that report an item added. It includes the stable `id`, `kind` (`item` or `weapon`), `source_mod`, and `frame`, plus `native_item_no`, `requested`, `added`, and `slot` when returned by the adapter. A zero/false `added` result emits no event. `game.item_picked_up` fires in both games after a native dungeon pickup path (`BtGetTreasureboxBig_Loop`, `BtGetTreasureboxSmall_Loop`, or `BtGetAttach_Init` in Chronicle; `CDngTreasureManager::CheckStandItem` or `CChrItem::Exec` in Chronicle Two) adds inventory; it includes the stable item or weapon `id`, `kind`, `native_item_no`, positive `count`, `source = "native"`, and `frame`; Chronicle weapon pickups also include the exact receiving character and slot. Objectives without `event` remain manually advanced.

Chronicle's `game.enemy_defeated` event also includes `attacker`, `weapon_id` when available, positive `reward_exp` / `reward_money` fields, and `enemy_max_hp` when the defeated native actor has a valid maximum HP. Mods can use these fields for character XP and weapon kill progression without a separate player-hit event. `enemy_max_hp` is the actor's maximum at the accepted death boundary; it is not guaranteed to be the unmodified template value when another feature has scaled that actor. Chronicle's `game.enemy_hit` event provides per-hit weapon, target, model, element, and final damage context for effects that need to run on every attack.

Entity and resource references use generation-checked handles, not raw addresses. Mutating APIs report failure when an object is stale, the phase is wrong, or the mod lacks the needed capability. Registration calls return ownership tokens; disabling or reloading a mod releases the registrations owned by that mod.

## Events and update phases

The in-game mod manager has **Quests** and **Skills** tabs for mods with saved progression data, plus a consolidated **Journal** tab. Quests shows status, objective completion, per-objective progress, and a reward summary; left/right changes quests and up/down scrolls longer lists. The Journal tab gathers quests from every package into a two-pane list, shows each quest's owning mod, status, rewards, and objective progress, and keeps saved entries visible while their mod is disabled. Skills shows each registered node's tree, rank, maximum rank, prerequisite availability, and description; up/down selects a node. These are MoonFactory views, not entries in either game's original journal or native skill UI; native integration remains open.

Successful, changed native writes queue `game.georama.request_changed` on Chronicle and `game.georama.request_changed`, `game.georama.condition_changed`, and `game.georama.request_known_changed` on Chronicle Two. Piece placements and removals queue `game.georama.piece_placed` and `game.georama.piece_removed` on both ports. Removal events also include cascade counts, returned build stock, and released villagers on Chronicle Two. Payloads include the town and request/condition/part identifiers, previous and resulting state where applicable, `changed`, `source_mod`, and frame. Repeating a setter with the same value is idempotent and does not enqueue another event. Quest objectives may subscribe to these events with an exact `match` filter.

The runtime reserves stable phase names for `early`, `simulation`, `post_simulation`, `ui`, and `render`. Content registration happens before game content is finalized. API functions document the phases in which they are safe. A mod can request deterministic ordering constraints (`load_after`, `load_before`, required dependencies, and optional dependencies); an unresolved or cyclic dependency is surfaced in the manager with the responsible ids. Optional dependencies only order the packages when both are enabled and do not block the caller if the target is unavailable.

`game.world.location_changed` is sampled once per runtime pump within a scene and immediately after native scene initialization when detectable. Its payload contains the new scalar location fields (`context`, `area_id`, `map_id`, `sub_map_id`, `dungeon_id`, `floor_id`), a `previous` object with the prior snapshot, and the current framework `frame`. The initial valid snapshot establishes a baseline and emits no change. A temporarily failed world read during loading keeps the last valid snapshot so the next readable location can still emit a change; Chronicle can use native loop and map state when save-backed time or area data is briefly unavailable. This event can drive objectives such as `{event = "game.world.location_changed", match = {map_id = 2}}`. It reports the first state difference observed between samples, so transitions that begin and end within one pump interval are not separately reported. Native scene transition events remain available for top-level loading boundaries.

The common runtime emits `game.tick` from the PC port clock pump and `runtime.loaded` after each Lua package loads. Successful `game.items.use` and changed `world.story_flag_set` calls queue their `game.*` event for the next pump, so subscribers and quest objectives run after the API callback returns. Both game loops emit `game.scene.will_enter` immediately before initializing a scene and `game.scene.entered` after the initializer and arrival processing finish. Their payload contains `scene_id` (`title`, `town`, `dungeon`, `menu`, or `other`), the game's `native_mode` id, and the framework frame count. The ChronicleTwo headless smoke can verify `will_enter` before its empty-data logo-fade fixture exits. Frame-observed location changes cover map and dungeon-floor state differences; exact event timing at each native map/floor loader remains adapter work.

### Tier 2 APIs: Render, Weapons, Shops, Dungeons & Native Script Hooks

The Tier 2 expansion introduces high-utility gameplay hooks across both games:

- **HUD Overlays (`game.render.*`)**:
  - `game.render.bar_register({id = "boss_hp", label = "Boss", value = 150, max = 200, x = 100, y = 50, width = 200, height = 12, color = {r = 255, g = 50, b = 50}})`: Registers an owner-scoped HUD progress bar overlay.
  - `game.render.bar_remove({id = "boss_hp"})`: Removes an owned HUD progress bar overlay.

- **Weapon Mastery & Progression (`game.weapons.*`)**:
  - `game.weapons.abs_get({id = weapon_id, character = optional, slot = optional})`: Reads current ABS (experience points), current level, and ABS required for next level.
  - `game.weapons.abs_add({id = weapon_id, amount = 50, character = optional, slot = optional})`: Adds ABS to a weapon, auto-leveling when reaching the requirement and emitting `game.weapon.abs_gained`.
  - `game.weapons.attachments_get({id = weapon_id})`: Inspects attachment sockets, filled slots, and stat contributions (attack, endurance, speed, magic, elemental, vs-monster).
  - `game.weapons.attachment_insert({id = weapon_id, attachment_id = item_id, attachment_slot = optional})`: Inserts an attachment into an open socket.
  - `game.weapons.attachment_remove({id = weapon_id, attachment_slot = slot_idx})`: (*Chronicle only*) Safely removes an attachment from a weapon and returns it to the consumable bag.
  - `game.weapons.build_up_list({id = weapon_id})`: Lists available native and mod-registered evolution/build-up targets.
  - `game.weapons.build_up_register({from = source_id, to = target_id})`: Dynamically links a custom build-up evolution path between two weapons of the same character.
  - `game.weapons.synthesize({id = weapon_id})`: (*Chronicle only*) Status-breaks a level 5+ weapon into a SynthSphere attachment carrying 60% of its stats.
  - `game.weapons.spectrumize({id = weapon_id})`: (*Chronicle Two only*) Spectrumizes a level 5+ weapon into a SynthDrop carrying 60% of its stats and synthesis points.

- **Shop Inventory & Pricing (`game.shops.*`)**:
  - `game.shops.list()`: Enumerates native shop catalogs, their NPC owners, and scene locations.
  - `game.shops.get({shop = shop_id_or_number})`: Retrieves shop items, stock counts, and purchase prices.
  - `game.shops.register_item({shop = shop_id, item = item_id_or_number, price = optional, count = optional})`: Injects an item or weapon into a shop's stock.
  - `game.shops.remove_item({shop = shop_id, item = item_id_or_number})`: Removes an item from a shop's inventory.
  - `game.shops.set_items({shop_no = 0..17, items = [item_no, ...]})`: (*Chronicle only*) Replaces the native fixed-size list with up to 20 goods. Repeated IDs are preserved because native shops use duplicate entries for stock weighting. A shorter list retains its `-1` terminator; a full list uses every slot and is read by the game's bounded 20-entry loop. The list is owned by the calling mod and restores to its original contents when that mod unloads; another mod cannot claim the same shop while it is overridden.
  - `game.shops.set_price({item_id = item_id_or_number, buy_price = optional, sell_price = optional})`: Overrides the native global buy and/or sell price for an item or weapon. Chronicle restores the original price when the owning mod unloads.

Chronicle's `register_item`, `remove_item`, and `set_items` changes share one owner claim per native shop. `set_price` uses one owner claim per native item price. Conflicting mods receive an error instead of overwriting another owner's data; unloading the owner restores the saved native value.

- **Dungeon Floor Rules & Loot (`game.dungeons.*`)**:
  - `game.dungeons.floor_rules_get({dungeon = dungeon_id, floor = floor_num})`: Queries floor restriction rules (limited zones, character locks, red/white seals, back-floor keys).
  - `game.dungeons.floor_rules_set({dungeon = dungeon_id, floor = floor_num, rules = {...}})`: Overrides active or target floor rules.
  - `game.dungeons.loot_get({dungeon = dungeon_id, floor = floor_num})`: Inspects chest loot arrays and enemy drop tables.
  - `game.dungeons.loot_override({dungeon = dungeon_id, floor = floor_num, loot = {...}})`: Customizes chest contents or monster drop entries.

- **Native Script Hooks (`game.scripts.override`)**:
  Mods can intercept, inspect context, wrap, or replace native script execution points:
  - `native.event.run`: Native event programs / cutscene scripts.
  - `native.dialogue.show`: Message and dialogue window triggers.
  - `native.combat.before_hit`: Pre-damage calculation hook for player and enemy attacks.
  - `native.loot.roll`: Chest opening and item drop resolution.
  - `native.transition.before_enter`: Pre-scene and map entrance transitions.

- **Deferred Simulation Events**:
  - `game.weapon.abs_gained`: Emitted when an owned weapon gains ABS.
  - `game.weapon.built_up`: Emitted when a weapon undergoes build-up or synthesis/spectrumization.
  - `game.weapon.broken`: Emitted when weapon durability reaches 0 or when status-broken.
  - `game.shop.purchased`: Emitted upon shop transaction or inventory change.
  - `game.chest.opened`: Emitted when a dungeon chest is opened or loot is retrieved.
  - `game.floor.cleared`: Emitted when a dungeon floor's exit is unlocked or rules change.

### Tier 3 APIs: Signature Game Systems

These operations bind each game's signature systems to native save or live engine state. Unsupported combinations remain listed with a reason: Chronicle has no photography, invention, ridepod, monster-badge, or Spheda system; Chronicle Two has no per-character water gauge, Atla spheres, Chronicle-style satisfaction view, or back-floor state.

- **Chronicle thirst (`game.player.thirst_*`)**:
  - `game.player.thirst_get()` reads the active character, current and maximum water, the current per-frame drain, whether drain is enabled, the empty state, and the native restriction-zone/step flags.
  - `game.player.thirst_set({water = number, character = optional})` sets the absolute gauge; `game.player.thirst_set({restore = number, character = optional})` adds to it. Both clamp to the native capacity (0 through `max_water`) and clear pending gauge interpolation. Exactly one of `water` or `restore` is required. A changed write queues `game.player.thirst_changed`.
  - `game.player.thirst_changed` carries `character`, `character_id`, `previous_water`, `water`, `max_water`, `drain_per_frame`, `drained_out`, `dried_out`, `source` (`api` or `native`), `reason`, and `frame`. The adapter polls the native gauge once per runtime pump, so native drain, drinking, and drying out are observed even when no API call made the change. Native observations are emitted on whole-unit gauge boundaries and on dry-out rather than for every fractional frame, and a transition that starts and ends between two pumps is not reported.
- **Chronicle Atla and town reconstruction (`game.georama.*`)**:
  - `game.georama.atla_list()` requires an active dungeon floor and returns the open Atla spheres with their live slot, native Atla registry index and id, registry floor/refcount, world position, and whether the contents are a Georama part or chip plus its saved obtained/placed/stock state.
  - `game.georama.atla_collect({slot = 0..7})` requires an active dungeon floor and Toan as the controlled character. It uses the game's native Atla save routine (`getAtraToSaveData`), marks the live ball and matching dungeon event closed, and releases the part or chip into the same saved state as a native pickup. It does not transfer ownership of a mod-authored asset.
  - `game.georama.satisfaction_get({town_id = optional 0..4})` returns each requested Chronicle town with saved request completion, a rounded `satisfaction_percent` derived from completed native requests, and per-plot `obtained`, `placed_count`, `stock`, and element flags. The percentage is a framework view over native request state; retail has no separate satisfaction statistic.
- **Chronicle back floors (`game.dungeons.back_floor_*`)**:
  - `game.dungeons.back_floor_get()` returns whether the active dungeon floor has a native back-floor enemy layout, whether the party is currently on it, the active floor and gate-key item identity, whether the key is held, and whether a request is pending. The key is the floor's native gate key, not a fabricated back-floor key table.
  - `game.dungeons.back_floor_enter()` queues the game's native back-floor transition request. It never consumes the gate key. The request is applied at the next native script boundary (`GAME_TASK_SCRIPT_RUN`) and is reported as `queued` before that point.
- **Chronicle Two photography (`game.photos.*`)**:
  - `game.photos.ideas_list()` returns learnt idea binder slots plus carried photos with their subject, map, townsperson/monster ids, and new flag.
  - `game.photos.idea_unlock({idea_id = 1..999})` inserts an idea into the native binder. Repeating an already-learnt idea is an idempotent success. The call fails when the binder has no free slot.
  - `game.photos.scoops_list()` enumerates the native scoop table with each row's `scoop_id`, `info_index`, native `known`/`obtained` flags, whether a carried photo shows the scoop, and whether the idea binder has learnt it.
  - `game.photo.taken` is emitted by the native photo callback with `subject_id`, `neta_id`, `map_no`, `npc_no`, `monster_no`, `kind` (`idea`, `scoop`, or `none`), `ideas`, carried photo count, and, for scoops, `scoop = {scoop_id, known, obtained}`.
- **Chronicle Two inventions (`game.inventions.*`)**:
  - `game.inventions.list()` lists native recipes (recipe item, three ideas, and materials) and mod recipes. Native recipes come from the game's on-demand `inv6.lst` table; mod recipes are held by the adapter.
  - `game.inventions.register({id, item, ideas = {a, b, c}, materials = optional})` registers a namespaced three-idea recipe owned by the calling mod. `item` resolves through the normal item/weapon resolver, so a mod item, weapon, or ridepod-part item can be the result. Up to four materials are accepted as `{id, count}`. Mod recipes are API-visible and craftable, but are not inserted into the native invention-menu recipe table because that table's storage is fixed by the game's script data.
  - `game.inventions.craft({id, count = 1..99})` requires a native recipe to be discovered (`IsAlreadyCreatedItem`) or a mod recipe's three ideas to be learnt. It checks materials, inventory space, consumes materials, and adds the result through the native inventory. A successful call queues `game.invention.created` with the item id, native item number, three ideas, requested/added counts, and `source = "craft"`; native menu discovery emits the same event with `source = "native"`.
- **Chronicle Two ridepod and monster badges (`game.player.*`)**:
  - `game.player.ridepod_get()` returns fuel and maximum, core capacity and used capacity, defence, shield-kit count, ridepod name, voice-unit/voice-enabled state, and the arm/body/leg/battery parts with item ids, item numbers, durability, energy, and capacity use.
  - `game.player.ridepod_set({fuel|restore|max_fuel|shield_kits|voice_enabled|voice_unit|parts})` adjusts the native gauges and voice state. `parts = {arm, body, leg, battery}` requires an owned part of the matching native type and performs the game's equipment swap, returning the previous part to the inventory. Defence is derived from the body and shield kits; set `shield_kits` (0..999) rather than writing defence directly.
  - `game.player.transform_get()` returns the active monster form, unlocked count, and all 64 badges with monster id, enabled state, level, class, progress, degree, health, experience and threshold, attack, defence, and class-change eligibility.
  - `game.player.transform_set({badge = 1..64 | monster_id, enabled|level|experience})` updates one badge. Level is bounded to 0..98 and recomputes the native experience threshold; experience is clamped to that threshold. This changes saved badge state, not the live transformation actor.
- **Chronicle Two Spheda (`game.dungeons.spheda_*`)**:
  - `game.dungeons.spheda_get()` returns the current dungeon/floor challenge and clear flags, live session flags, par, club, pin/ball coordinates and colours, gauge power/state/code, and the saved clear value. The native save records only a clear flag, so a remaining-stroke count and medal award are not exposed.
  - `game.dungeons.spheda_spawn({par = optional 1..99})` requires an already allocated Spheda session on an active dungeon floor. It calls the game's native course setup again, optionally overrides par, and enables the play/status/minimap flags so the new pin and ball are active. It cannot allocate a Spheda session when the floor event has not created one.
  - `game.spheda.completed` is queued when the native floor-info setter first records a Spheda clear (through the clear value or the floor clear flag). It contains `dungeon_id`, `floor_id`, `cleared`, `clear_value`, and `frame`; stroke count and medal are not stored by the native save format.

## Permissions and ownership

Permissions are declared in `mod.json` and checked by the runtime for each operation: `game.read`, `game.write`, `content.register`, and `scripts.override` cover game adapters; `debug.inspect` gates diagnostics; `storage.read` and `storage.write` cover per-mod storage. Enabling a local package enables its declared Lua permissions. A package that declares `native.extension` also needs a package-relative native library and a separate local trust confirmation before that library loads. Lua does not get direct filesystem, process, network, native code, or arbitrary memory access. `storage.*` is sandboxed to a fixed JSON file under that mod's user-data directory. Trusted native code runs in-process and is outside the Lua sandbox; see [Native SDK](NATIVE_SDK.md).

## Native extension surface

The native SDK has a C-compatible, versioned ABI v1 header, descriptor validator, package-bound dynamic loader, local trust confirmation, and host logging, supported game-adapter API calls, and event services. Trust is tied to the library SHA-256 digest and package/file metadata. Native code remains an opt-in in-process escape hatch and does not receive the Lua sandbox. See [Native SDK](NATIVE_SDK.md) for its service scope and platform verification boundary.
