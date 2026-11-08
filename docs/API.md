# MoonFactory API map

The API is designed for comprehensive game modification while preserving clear compatibility boundaries. Common domains are shared under `game.*`, and every domain operation carries its own major version plus a per-game capability result. Chronicle- or Chronicle Two-specific operations can be added under their game-specific namespaces without changing common operation contracts. The Lua layer is the default for creators; native extensions are an opt-in escape hatch for engine-level work.

## Common Lua surface, API major 1

The first runtime slice implements the marked surfaces:

| Namespace | Intended surface | First slice |
| --- | --- | --- |
| `moonmod.log(level, message)` | Structured per-mod logs and in-game diagnostics | Implemented |
| `moonmod.on(event, callback)` | Event subscription with an isolated Lua callback budget | Implemented: `runtime.loaded` (`live = true` when the mod was switched on mid-run), `runtime.unloaded`, `game.tick` |
| `moonmod.part.run/enabled/list` | A merged pack's script hands over each part (a mod of its own inside the pack) | Implemented; only in a pack (`parts` in `mod.json`). See [Packs and live on/off](modding/PACKS.md) |
| `game.events.list/subscribe/unsubscribe` | Discover verified event names per game and subscribe with owner-scoped tokens | Implemented in the shared runtime; the list includes short descriptions and omits game-specific events from the other port |
| `moonmod.game` | Game id, framework API version, and capability queries | Implemented: id and API major |
| `game.info.get()` | Game id and name, API major, the calling mod's id, and today's `date` `{year, month, day}` | Implemented; the date is the UTC calendar day, the same for every player, for daily seeds (Chronicle; the Lua sandbox has no `os`) |
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
| `game.ui.sheet_set/sheet_clear/sheet_open` | Character page: a mod's sheet and skill tree as the native **Journal > Character** page | Implemented on Chronicle; unsupported on Chronicle Two |
| `game.ui.notify` | Queue a bounded notice for the mod manager and over gameplay | Implemented on both ports |
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

Scripts run in separate Lua states (a merged pack's parts share the pack's, each as its own owner). They receive the standard base, table, string, math, and UTF-8 libraries. File, process, dynamic module, bytecode loading, debug, and unrestricted garbage-collector APIs are withheld. Each state has an allocator ceiling and callback instruction budget. A failure is reported against the owning mod and does not unwind into the game.

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

An override replaces a file that the PC port's native data reader already knows how to open. `game_path` is a relative path in the game's data tree; it is case-insensitive and accepts `/` or `\\` separators. The source must be a regular file below the package's `resources/` directory, and the same traversal and symbolic-link checks apply. A mod owns its override until it removes it or unloads; another mod cannot take or remove that path. Limits are 64 overrides per mod, 512 across all mods, and 128 MiB per source file. For an indexed file, the adapter uses the replacement only when it is non-empty and no larger than the retail file, except on Chronicle as described in [Chronicle: overrides larger than retail](#chronicle-overrides-larger-than-retail). Bounded exceptions support new native asset paths: Chronicle accepts `dun/monstor/<name>.chr` and `.stb` up to 2 MiB after sector padding; Chronicle Two accepts `dungeon/monster/<name>.chr` up to 3 MiB. Chronicle Two runs its scripts as Luau modules (from ChronicleTwo `7a7d7f29`), so its data reader no longer loads `.stb` files: a `.stb` override registers but the game does not read it. Both use native 15-character monster names with letters, digits, `_`, `-`, or `.`. Chronicle can alias a reserved `gedit/s60`–`gedit/s69` directory to indexed built-in field assets when a mod registers a copied location; owned overrides inside that target directory can replace individual files. See [Chronicle native locations](#chronicle-native-locations). Chronicle Two also reads explicitly registered, previously unindexed files under `map/` with `.cfg`, `.efp`, `.ipk`, `.map`, `.mpk`, or `.sky` extensions (also with a trailing `.json`, the form its converted tables take), up to 3 MiB after sector padding. `locations.register` can append a standalone interior map to Chronicle Two's loaded native map catalog when the mod owns its required map assets; see [Chronicle Two authored locations](#chronicle-two-authored-locations) for registration and transition details. Replacements still need the exact format expected by that game's loader. This does not register a standalone dungeon or animation, and it does not validate model formats or rig compatibility. ChronicleTwo-Script `add` assets and format conversion remain unverified for the PC runtime.

### Chronicle: overrides larger than retail

On Chronicle (the PC port only; PS2 builds keep the retail-size rule), an override of an existing file may be larger
than the retail file when its kind allows it and the game has room for it where it reads it:

| Kind | Limit (bytes) | Read into |
|---|---|---|
| `.mpd` floor pack | 6,399,999 | the map read buffer (the game stops at 6,400,000) |
| `.cfg` floor script | 1,048,576 | a temporary block at the end of the map model buffer |
| `.chr` character, monster, weapon | 16,777,216 | the read buffer, or an arena block advanced by the file's size |
| `.stb` script | 4,194,304 | the read buffer, then copied into the monster or event script arena |
| `.mes` text | 1,048,576 | the battle, edit or system message buffer (about 670 KB of room in a dungeon); `opdat/*.mes` 68,992 |
| `.snd` sound pack | 16,777,216 | the sound read buffer |
| `.scn` Georama scene | 8,388,608 | the edit NPC buffer |
| `.edt` Georama layout | 65,536 | a 64 KiB block (retail: a 4,000-byte stack buffer) |
| everything else (`.mds`, `.img`, `.pak`, `.pac`, `.bin`, ...) | retail size | fixed layouts |

Besides the kind's limit, the file rounded up to 2,048-byte sectors must fit the room left in the arena block it is read
into; the port checks this when the file is read. A larger file that is used logs
`moonmod: override for <path> grows <retail> -> <size> bytes (limit <limit>, buffer room <room>)`. One that is not logs
`moonmod: refused override for <path>: ...` with the reason, and the retail file is read instead. With no override active
the game reads exactly as before. [dc1tk](https://github.com/Jeffiest/dc1tk) `mod-pack --port` packages edits against
these limits.

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

The notice is queued for the manager's status line and stays there for the requested number of game frames (1-3600, default 240). Messages are limited to 200 bytes. Over gameplay, notices queue and pop up one at a time, each for its duration (180 frames at least), counting down only while it is on screen. In a Chronicle dungeon each pops up in the game's own message window at the bottom right, wrapped to three lines (a longer one ends in "..."), and waits while the game's own message has the window. Elsewhere it is an overlay line. An optional `icon` (Chronicle) draws in the window beside the text: `"freeze"`, `"stamina"`, `"poison"`, `"curse"` or `"goo"` for the game's status badges, or a png game path the mod registered with `resources.override`. The manager's status line shows the notice too if the manager is open, or when the player opens it before the duration expires. `ui.notify` requires `game.write`.

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

### Character sheet: the Journal's Character page (Chronicle)

```lua
assert(game.ui.sheet_set({
  title = "TOAN",                                   -- the banner: "JOURNAL: TOAN"
  lines = {"Level 12   XP 340 / 812", "Skill points: 3"},
  progress = 340 / 812, progress_label = "XP 340 / 812",
  hint = "Cross trains the selected skill.",
  trees = {"swordsman", "survivor", "explorer"}  -- the page shows the trees in this order
}))
assert(game.ui.sheet_open())   -- during play: opens the menu on the page
assert(game.ui.sheet_clear())
```

A mod with a skill tree (`skills.register`) can give the player a native page for it: **Journal > Character** in
the battle menu, drawn with the port's UI framework like the Chest Tracker. The player reaches it from the ring:
**Journal > Mod Manager > Triangle > Character** (Triangle in the Mod Manager opens the native Journal list, where
Character is the sixth category), or with a mod hotkey that calls `ui.sheet_open`. `title` is required (1-32 bytes)
and `trees` names at most 32 trees. The left pane shows the sheet's
`lines` (up to six, 48 bytes each), its `hint` (80 bytes, gold) and a progress bar when `progress` (0 to 1) is
given, labelled `progress_label` (32 bytes); the right pane lists the mod's skill nodes one tree at a time, the
trees in the order `trees` names them (local tree ids; unnamed trees follow)
(Left/Right or L1/R1 change tree, Up/Down select, Circle goes back, the counter shows rank/max, a node whose prerequisites are
unmet is dimmed and its description names the first missing one). Cross on a node delivers
`skills.train_requested` with the node's qualified id to the owning mod, exactly as the Mod Manager's Skills tab
does, and the mod's next `ui.notify` message is shown on the page. The page lists only while a loaded mod has set
a sheet; the last sheet set wins when several mods have one. `ui.sheet_open` asks for the page from any mod
during play and fails when no sheet is set. In a dungeon the menu opens on the page as soon as no action is
running (the same point where Triangle would open it). In town the request is not acted on yet (the town menu has no hook for it), so
use the ring path above. `ui.sheet_clear` takes the mod's sheet back; unloading the mod does too. All three require `game.write`.
Chronicle Two has no Journal page yet, so these calls are unsupported there.

The bundled **MoonMod Hub** binds this: **K** on the keyboard, or **L1+R1+R3** held together on a gamepad, calls
`ui.sheet_open` (the page of `moonmod.rpg` or whichever mod set the last sheet). On an engine without the page, or
when no sheet is set, it falls back to `ui.navigate` to the `moonmod.rpg` Skills tab, then its Actions tab, and
shows a notice if neither opens. **J** opens the Dungeon+ journal tab.

### Cross-package Mod Manager navigation

```lua
local opened, err = game.ui.navigate({mod_id = "moonmod.adventurer", tab = "skills"})
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

The shared runtime stores each mod's tree definitions and ranks in its protected per-mod save file. Tree registration is idempotent when the definition is unchanged; changing a registered tree requires a future migration/versioning API. Prerequisites must reference nodes in the same tree, must fit within their target node's maximum rank, and cannot form cycles. `skills.unlock` increases rank by one after prerequisite checks; `skills.set_rank` can set a validated rank or reset a node to zero. Registration requires `content.register`; reads require `game.read`; rank changes require `game.write`. A mod can register up to 32 trees and 128 nodes per tree, with ranks from 0 to 99. The optional `effects.enemy_damage_per_rank` field accepts a finite value from 0 to 1 and adds that percentage per rank to positive outgoing enemy damage. It stacks multiplicatively in stable mod/skill ID order after registered combat formulas, affects scripted `combat.damage` and native enemy-hit damage, and does not turn zero damage into a hit. On Chronicle a mod can also show its tree on the native Journal > Character page (see *Character sheet* above). The in-game manager's **Skills** tab displays each mod-owned node, tree name, rank, prerequisite availability, description, and supported enemy-damage effect summary, including saved data for disabled mods.

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
| `game.player` | Read/write character state, health, movement, equipment, animation, status effects; on Chronicle, owner-scoped player tuning and one-shot invincibility (`tuning_set/tuning_clear/invincible`, see *Player tuning*) |
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

`render.camera_set()` accepts any non-empty subset of `distance`, `height`, and `angle`, and returns the resulting `distance`, `height` and `angle` with the values they replaced under `previous`, so a caller can put the camera back. On Chronicle the native follow camera keeps its own reach: it eases a distance past 80 back to 80, and a height down toward 5. Distance must be 8–300 native units, height −80–150 units, and angle −1000–1000 radians; the angle is normalized before the native camera receives it. The game eases toward the requested orbit angle in follow mode. For Chronicle Two's player-controlled camera, distance and height must also fit the active native camera's own limits, and its normal collision correction remains in control. The call requires a supported dungeon orbit camera: Chronicle must be in follow mode, while Chronicle Two supports its native follow and player-controlled camera modes. Native scene or camera transitions can later replace these values. Bounded HUD text layers are supported on both games; arbitrary draw callbacks and world-space layers remain unsupported.

Chronicle also supports `render.town_camera_set({enabled = true, height = 90, back = 22})` for a legacy-style overhead town view. Height is bounded to 40–500 and the forward/back offset to −200–200 native units. Requests are owned by the calling package and removed when it unloads. The native adapter applies the pose only in the main town walking loop with a valid player and the standard main camera; menus, events, dungeons, and camera transitions stay under native control. The `moonmod.expanded-town` package exposes the legacy O and L1+L3 toggles, offsets in Settings, and a Toggle action in the Mod Manager. ChronicleTwo reports this operation unsupported.

Chronicle's `render.first_person_toggle()` queues the native dungeon camera transition while normal dungeon play or the first-person view is active. The game loop performs the transition through its existing setup and cleanup path; the request is rejected in menus and other states.

Chronicle's renderer also supports package-owned 3D mesh replacements outside the Lua API. Put `models/<texture>.obj` or `models/<texture>.glb` in an enabled package; use `<texture>__<vertex-count>v.obj` for a source-vertex-specific replacement. An optional sibling JSON file accepts `scale`, `rotate_deg`, `offset`, and `flip_v`. Enabled packages can also supply `textures/<texture>.png` to replace the matching native texture. The renderer keeps the native material strips and follows native character skinning. Later packages in MoonFactory's resolved load order override earlier package assets; a matching exact-vertex file takes precedence over a generic texture file. Set `DC_DUMP_MODELS=1` before launching to dump source meshes as OBJ files into `<save-root>/mods/_dump/models`; each file name includes its source texture and vertex count. Model and texture files larger than 64 MiB are skipped. Direct runtime GLB loading flattens mesh instances in the selected scene, applies node hierarchy transforms, expands sparse accessors, and converts triangle, strip, and fan primitives into the renderer's triangle list. Point and line primitives are skipped. The package-generating editor is documented in [MODEL_REPLACEMENTS.md](MODEL_REPLACEMENTS.md).

The native 2D item/weapon icon path uses the `itemicon` and `wepicon` atlases; package PNG overrides named `textures/itemicon.png` and `textures/wepicon.png` repaint them while keeping the native icon rectangles and layout. This does not register new per-item icon entries or alter UV rectangles.

The API-major-1 catalog is defined in [`../src/api.cpp`](../src/api.cpp), with its shared types in [`../include/moonmod/api.hpp`](../include/moonmod/api.hpp), and has concrete paths for every domain above. Capability records report both `framework_api_major` and `domain_api_major`. The common Lua runtime implements identity and capability discovery, event subscription, per-mod save data and migrations, owned localization, managed package resources and audio, manager notices, digital input actions, dependency-scoped callable functions, persisted quest progress, and mod-owned skill trees. Both game ports bind player health/status, party and character queries, normalized world time, native story flags/counters and map flags, combat/entity reads, generation-checked direct enemy damage with owner-scoped damage formulas, and item list/get/register/give/remove/use calls to native game state. Both ports also provide bounded live-enemy healing through `combat.heal`; Chronicle adds generation-checked enemy slow/stop statuses, per-mod enemy-survival chance, and room-scaled procedural population; its damage formulas support conditional per-hit chance rolls. Fighting styles remain paused while model-rigging work is out of scope. Chronicle supports native Georama reads, request completion, toggling defined optional elements, registering data-only variants of loaded native solid pieces, and placing/removing existing or registered pieces in the active town editor. ChronicleTwo exposes saved Georama placements and analysis state, including request completion and knowledge and data-only piece variants that inherit a native model and placement rules, plus native-validated placement and removal of solid pieces in its edit scene. Both games bind `party.set_active` through their native character-loading paths, with Chronicle restricted to safe active-dungeon play; ChronicleTwo also applies its native quick-change eligibility rules. ChronicleTwo additionally supports party recruitment, weapon reads/registration/equip, and added floors on existing dungeons. Other gameplay operations remain explicitly unsupported until their game-state adapters and native tests land. Contract tests use a fake adapter for broad API dispatch coverage; native tests cover the supported game-state and content paths.

Chronicle supports `georama.get` and `georama.request_set` for native saved towns, plus `georama.place/remove` for built native pieces in the active town editor. `georama.register({id, name, template_part_id, town_id?, stock?})` adds a solid, data-only variant of a loaded native template. It allocates a persistent native definition id in slots 24–55 without changing the retail save record layout. Variants inherit the template's model, collision, footprint, and native placement behavior unless they declare their own model (see [Chronicle Georama variants with their own model](#chronicle-georama-variants-with-their-own-model)); they cannot declare their own footprint, cell data or menu assets. Registration materializes only for the requested town (or any town when `town_id` is omitted), and `stock` initializes built stock from 1 through 999. The original build-menu definition scan can enumerate the appended variants; native UI text and icons still come from the inherited template, while the supplied mod name appears in API metadata. Unregistering is rejected while any saved town or active placement refers to the variant, and the stable native id remains reserved for that stable piece id across launches. The retail headless probe registers one variant, places it using the native editor path, reads it back from saved layout, removes it, and confirms it is gone. It does not verify a reload-visible render or player-save compatibility.

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

`render.hud_icon_set({id, icon = "freeze"|"stamina"|"poison"|"curse"|"goo"} or {id, image = game_path}, blink?)` shows an icon in a row left of the dungeon's key and floor plate: one of the game's status badges at half size, or a 32x32 png the mod registered with `resources.override` (drawn 22x22). `blink = true` pulses it. At most six icons; `render.hud_icon_remove({id})` takes one away. `render.floor_label_set({text, number?})` puts up to six characters on the floor plate in place of its number, lettered like it, and `number` (1-99) replaces the floor number on the card shown on arriving, in the card's own digits; one mod at a time, and `render.floor_label_clear()` gives both back. Unloading a mod takes its icons and label away.

`render.layer_register` registers or updates one owner-scoped text layer in the native top-left HUD pass. In a dungeon, Chronicle draws the layers in its own HUD, in the game's lettering, under the life, weapon and water block and any `render.bar_register` bars, and `ui.notify` notices below them in the game's translucent help window. Elsewhere they are overlay lines starting 16% down the screen (the FPS badge stays above them), with notices below. `render.layer_remove` removes a layer owned by the calling mod. IDs cannot collide with diagnostic-overlay IDs; both APIs share a four-entry capacity and the 64-character combined text limit. Text is restricted to the overlay font's supported ASCII set and is drawn by the native presenter on both games. The call requires `content.register`; owner unload removes all layers. This renderer contract is text-only and screen-space; it does not expose arbitrary Lua draw callbacks, shapes, textures, or world-space rendering.

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

### Chronicle Georama variants with their own model

`game.georama.register` accepts an optional `model = {scene = <scene file>, part = <part archive name>}`. `scene` is
either a retail `gedit/<town>/scene.scn` or a mod's own `gedit/mod/<name>.scn`. A `gedit/mod/` scene is a new path, up
to 8 MiB, with a name of 1-15 `[a-z0-9_]` characters, and the mod must own its override before registering. `part` is the
name of a part archive inside that scene (up to 31 characters), for example `e01h05`. When the variant is set up in the
town editor, its LOD0-3, shadow, collision, shade, ripple and camera models come from that archive, and its bounds and
placement preview are recomputed. Footprint, function points, stock behaviour, menu name and icon still come from
`template_part_id`. If the scene or part cannot be loaded, the variant keeps the template's model and the game logs it.
Up to 8 distinct scene files stay loaded per session. The model's textures must be in the town's loaded texture pack.

```lua
assert(game.resources.override({path = "resources/gedit/mod/moonhouse.scn", game_path = "gedit/mod/moonhouse.scn"}))
local house = assert(game.georama.register({
  id = "moon-house", name = "Moon House", template_part_id = 0, town_id = 0, stock = 3,
  model = {scene = "gedit/mod/moonhouse.scn", part = "e01h05"},
}))
```

This replaces the earlier rule that variants "cannot declare geometry or asset overrides": they can now declare a model.
They can also declare their own footprint and cells (below); menu text and icons still come from the template.

Chronicle: registered content can bring its own files. Every file is a `game.resources.override` the mod owns (1 byte to 2 MiB),
registered before the content that names it.

### Chronicle weapons with their own model and icon

```lua
game.resources.override({path = "resources/annexmdl.chr", game_path = "commenu/weapon/annexmdl.chr"})
game.resources.override({path = "resources/annexicon.png", game_path = "icons/annexicon.png"})
local blade = assert(game.weapons.register({
  id = "annex", name = "Annex Blade", template_weapon = 262, owner = "toan",
  model = "annexmdl",   -- commenu/weapon/annexmdl.chr
  icon = "annexicon",   -- icons/annexicon.png
}))
```

- `model` names `commenu/weapon/<stem>.chr`. The game reads the template weapon's `.cfg` from inside it, so the file
  must hold a `.cfg` with the template's name (for template 262, Toan's sixth weapon, `c01w05.cfg`). Without `model`
  the weapon draws its template's model. Native names (`cNNwNN`) are refused.
- `icon` names `icons/<stem>.png`, any size, drawn into the 32x32 menu cell. `items.register` takes `icon` too.
- `description` (a string, or up to 4 lines of 1-64 bytes) is what the weapon menu's card says of it. A registered
  weapon a mod hasn't styled (`weapons.style_set`) goes by its own `name` in the menus and shows its `description` on
  the card, in place of its template's name and text; a styled one shows its style.
- `menu_scale` (0.1 to 4, default 1) is how big the weapon menu draws the model, against its holder's own weapons:
  a model made bigger than the template's (Opar's staffs, 1.45 times a sword) is shrunk to fit the menu's frame.
  In the hand it keeps its own size. `weapons.get()` reports it when it isn't 1.
- `items.icon_set({id, icon})` (`content.register`) gives a built-in item (`chronicle:item:<n>`, a dungeon item) a
  mod's own menu icon, `icons/<stem>.png`; leaving out `icon` puts the native one back. One mod per item; unloading
  the mod puts the native icons back.
- `weapons.get().assets` reports `model` and `icon` game paths.
- The model shows once the weapon is equipped (`weapons.equip` in town or a dungeon, or the game's menus).

### Chronicle Georama variants with their own footprint

```lua
game.georama.register({id = "long_fence", name = "Long Fence", template_part_id = 0, town_id = 0, stock = 5,
  footprint = {width = 4, height = 1}})                          -- every cell filled
game.georama.register({id = "corner", name = "Corner", template_part_id = 0, town_id = 0,
  footprint = {width = 2, height = 3, cells = {5, 0, 5, 0, 5, 5}}}) -- row by row, 0 = empty
```

`width`/`height` are 1-32 cells. `cells` holds width x height values 0-255 as the part definition file has them
(0 empty, other values as the template uses them); left out, every cell takes the template's most used non-empty
value. The model and collision still come from the template (or `model = {scene, part}`). `georama.get().mod_pieces`
reports `width_cells`/`height_cells`.

### Chronicle run screens (choice panel, run menu, boss card)

During dungeon play a mod can put up three screens of its own, each drawn by the engine in the game's own stone
plates and lettering, driven by the pad or the mouse, and spread across a wide window:

- `ui.choice_open({id, title, subtitle?, cancel?, cursor?, options = {{title, subtitle?, lines?}, ...}})` pauses the
  dungeon (as the game's pause does) on 1-6 option cards side by side. A line is a string or `{text, tone}` with tone
  `good`, `bad`, `dim` or `gold`. Left/right (or L1/R1) move, Cross takes, Circle backs out when `cancel` is set; the
  mouse picks the card under it. The owner gets `ui.choice_made` `{id, index}` (index from 1) or `{id, cancelled =
  true}`. One panel at a time; it waits for play to be free (not mid-chest) before it shows. Notices hold back while it
  is up. `ui.choice_close()` takes it away. With `town = true` it opens in a town too while the party walks free: there
  the town goes on around it and only the party's controls wait. Without it a panel opens only in dungeon play.
- `ui.run_menu_set({title, tabs = {{id, title, lines?, rows?}, ...}})` gives the mod a run menu: while it has one,
  Start in a dungeon opens it in place of the bare pause. Up to 6 tabs (L1/R1) of up to 64 rows (`{id, label, value?,
  detail?, tone?, enabled?}`); a side pane shows the tab's lines and the chosen row's detail. Cross on an enabled row
  sends `ui.run_menu_action` `{tab, row}`; set the menu again to show the result (the cursor stays on the same tab and
  row ids). `ui.run_menu_open({tab?})` opens it from the mod (when play is next free), `ui.run_menu_close()` and
  `ui.run_menu_clear()` close and remove it; `ui.run_menu_shown` `{open, tab}` reports it opening and closing. Leave
  out an empty `rows` or `lines` (or send none) rather than an empty table.
- `ui.boss_card({name, kicker?, epithet?, frames = 30-600})` is a boss's entrance: letterbox bars, the kicker in red,
  the name large in gold and the epithet under it, the scene held still while it shows.

### Chronicle dungeon floor extras

- `world.dungeon_npc_set({id, model = "gedit/e01/chara/p02a.chr", place = "exit" | "player"})` stands a town
  villager's model on the floor, just inside the floor's exit gate (or beside the player), turning to face the player
  as they come near. Walking up to it sends `game.dungeon_npc.near` `{id}` (again only after walking away). One figure
  per mod; a new floor sends it away. `world.dungeon_npc_clear()` takes it off. It has its own model and texture
  arenas.
- `dungeons.set_weapon_drops({unique?, rare = 0-100, large_chests = 0-100})`: with `unique`, a chest never holds a
  weapon the party already holds (or one already in a chest on the floor) and gets another of the same character's;
  `rare` is the percent chance a chest weapon steps up to a stronger one for the same character (up to about half
  again its attack); `large_chests` is the share of large chests, where weapons are (retail 12). `{}` restores retail.
- `world.set_roads({enabled})`: `{enabled = true}` makes walking out of a town's gate (the ground that opened the world
  map) send `game.town.road` `{town_id, location_id}` instead, once each time the party walks onto it; the world map
  no longer opens there. Where the gate's ground isn't beside the spot the world map sets the party down (Norune,
  Queens) or the town has none (Yellow Drops), standing on that spot facing out of the town sends it. The mod takes
  the road itself, with `world.transition` to another town or `dungeons.enter_floor({dungeon_id, floor_id = 0})`; with
  quick passage on, a jump between two towns holds the picture as one between a town and a dungeon does. One mod at a
  time; unloading the mod gives the world map back. Returns `{enabled}`. Vigil turns it on for a Vigil World save.
- `dungeons.set_quick_passage({enabled})`: `{enabled = true}` goes between a town and a dungeon (either way) with no loading card, no title the game holds for several seconds and no fade: the last picture stays on screen while the other side builds (at most ten seconds) and the first picture of the other side replaces it. The town and the dungeon both stay loaded (each keeps its own memory and textures), and each is drawn live through the other's way through, from where the camera stands: the cave seen through the town's door, the town seen through a doorway in the cave wall behind where the party arrived. Walking into that doorway, facing it, goes back to the town, which is gone back to as it was left (its villagers where they stood, its clock running on), not loaded again; it stands the party just outside the town's door, facing out, the camera behind them. A place shows through only once both sides have been visited. Going from one floor of a dungeon to another of the same dungeon (`dungeons.enter_floor`, such as a story floor through its smoke) shows no card either: the floor fades out as ever, the black holds while the next floor builds, and the next floor is there once the party can play on it. `{enabled = false}` gives the card back. One mod at a time; unloading the mod gives it back. Returns `{enabled}`. Vigil turns it on for a Vigil World save.
- `dungeons.set_npc_models({models = {{dungeon_id, npc, pack, cfg, motion}, ...}})`: loads up to three character packs into a dungeon's free NPC slots (`npc` 1-3; slot 0 is the one its floors' parts use) whenever that dungeon's map loads, for `set_npc_marks` to stand. `pack` is a game path `dun/.../<stem>.chr` or `gedit/.../<stem>.chr` (a scene's pack draws its people textured: Divine Beast Cave's Fairy King is `dun/d01/event/e28c03c.chr`); `cfg` is the pack's config, `<stem>.cfg` by default (`base.cfg` for `dun/mainchara`); `motion` the loop it plays (0). It takes effect from the dungeon's next map load, so ask before entering. `{}` stops; one mod at a time; unloading the mod stops it. Returns `{models}`.
- `dungeons.set_npc_marks({marks = {{npc, x, y, facing}, ...}})`: stands the map's NPCs (a floor's own, or ones `set_npc_models` loaded) at cells of the floor the player is on, up to 16, each facing 0-3. They are drawn while that floor (its map seed) stays; a floor built again needs them asked again. Fails when the player isn't on a dungeon floor or the slot holds no character. `{}` takes them away; one mod at a time. Returns `{marks}`.
- `dungeons.play_event({program})`: plays program `program` of the dungeon's event script (its scenes, `dun/script/dNN/event.stb`, which a mod can replace with `resources.override`) on the floor the player is on, the way a monster's script asks for one. Fails when there is no such program, a scene is already starting, or the player is not free on a floor. When it is over, `game.dungeon.event_ended` `{program, dungeon_id, floor_id, frame}` goes to that mod only; the floor's monsters are gone after a scene, so build the floor again (`enter_floor`). Returns `{program}`.
- `dungeons.set_floor_select({enabled})`: `{enabled = false}` turns the dungeon entrance's floor menu off, so the entrance takes the player straight to the dungeon's first floor (a resumed floor still wins; a mod then starts the player where it likes, such as `dungeons.set_arrival`). `{enabled = true}` gives the menu back. One mod at a time; unloading the mod gives it back. Returns `{enabled}`. Vigil turns it off for a Vigil World save, whose dungeons are one map each.
- `dungeons.set_story_exits({title?, text?})`: on a floor of the game's own design (a fixed map, not generated), pressing at the gate that wants the floor's key (its `gatekey` marker) opens a panel (the title, default "LEAVE THIS FLOOR?", and the text) with *Leave* and *Stay*, Stay first, in place of the lock. Either way the gate stays shut: the mod hears `game.dungeon.story_exit` `{left, dungeon_id, floor_id}` and takes the player on itself (Vigil enters the next floor with `dungeons.enter_floor`). One mod at a time; `{}` takes it back, as does unloading the mod.
- `dungeons.set_backrooms({free, title?, text?, stay?, lines?})`: the back floor's stairs no longer ask for the gate key; walking onto
  them puts up a choice panel (`title`, `text`, Enter / Not now) instead of the key window, and Enter goes down at
  once. The key the stairs take is given back below. Acting at the back floor's entrance itself (the tram, the
  rope) opens the same panel at once, Proceed / Not now, and Proceed goes down with no item at all. The entrance's
  own script doesn't run then, so the engine stands the party one cell into the room from the back floor's way in
  (the script would have placed it). On the back floor, the stairs up ask "Go back up?" (Go up / Not now) instead of
  the key window, hand the stairs the key they want, and give it back above only if the party held it. The mod
  hears `game.dungeon.backroom` with `entered = false, left = true`.
  `game.dungeon.backroom` `{entered}` reports the answer. `lines` (up to two strings of 1-64 bytes) replaces the
  Proceed option's warning lines. With `stay`, the panel's answer is only reported: Proceed goes nowhere and takes
  no key, and the owner moves the run on itself (a rest floor's stairs, for one).
- `dungeons.set_character_blocks({characters = {"toan", "xiao", ...}})`: the parts only one character opens (Xiao's
  doors and jump spots, Goro's and Ruby's doors, Ungaga's and Osmond's parts) go on new floors only for the characters
  listed, so a run never meets a lock its party can't open. They also go only where the whole floor, its exit and every
  room, stays reachable without passing them: a detour for that character, never the only way on (a floor with no such
  place gets none). `{}` restores the retail rule, which counts the party and may put a part on the only way.

Floor building (Chronicle port) also never leaves a floor that can't be crossed: a corridor that reaches its room at a
corner has its doorway moved one cell along the wall, and a floor whose rooms or exit still can't all be reached (rare)
is built again from another seed. `darkcloud_tests --gtest_filter=DungeonReach.*` walks thousands of generated floors
(`DC_REACH_SEEDS` sets how many per setup; `DC_REACH_DUMP=<seed>` prints one floor's grid).
- `dungeons.set_warden_room({enabled, lock_in?})`: floors built from then on get a Warden room: one more room, 6x6
  cells where it fits (never under 4x4), built after the others and joined to its nearest room only, so it is a dead
  end and sealing it cuts nothing else off. It may stand a few cells past the area the other rooms keep to (the
  full-screen map shrinks its tiles to fit). Its doorway is closed by a gate; no monster, character door or back
  floor entrance is put in it, and the floor gets no native gated room. The gate opens once no monster is left
  outside (a hidden mimic doesn't count), and the owner hears `game.dungeon.warden_room` `{state = "open", center}`.
  Walking into the room sends `{state = "entered", center, size, shut}`; with `lock_in` the gate closes again behind
  the player until `dungeons.warden_room_release()`. `dungeons.warden_room_get()` reads `{state = none | sealed |
  open | shut | released, center, size}`. On the rare floor with no space for the room, the room behind the floor's
  native room gate is used, and a floor with neither reports `none`. One mod at a time; unloading it opens the doors.
- `world.ghost_get()` returns the player's last five seconds on the dungeon floor they are on: `{character, frames}`,
  `frames` oldest first, every other frame, each `{x, y, z, heading, motion}`. A new floor or another hero starts it
  again. `world.ghost_play({character, frames})` (1-600 frames, as `ghost_get` gives them) plays them back on that hero's
  model, pale and see-through, at the speed they were lived, and fades over a second at the end; `{}` stops it. Motions
  a mod appended to the hero play as standing. Dungeon only; one ghost at a time.
- **Messages players leave for each other** (`messages.*`, `storage.read`/`storage.write`). There is no server: each
  message is a small file in the **messages folder**, and a player who points that folder at one a sync service
  shares (OneDrive, Dropbox, a LAN share) reads the messages of everyone else who does. The folder is the player's
  choice, never a mod's, and no call takes a path: `DC_MESSAGES_DIR` when set, else the path on the first line of
  `<save>/moonmod/messages-folder.txt`, else `<save>/moonmod/messages` (the player's own messages only). Each player
  writes only their own fixed file names there (`<player>-<id>.json`, `<player>.ratings.json`); another player's files
  are read as untrusted data (at most 2 KB a message, 4000 files a list, links not followed, anything malformed left
  out). Anyone with the folder can read what is left in it.
  - `messages.post({place, text})` leaves a message: `place` is 1-64 characters of `a-z 0-9 : _ . -` that the mod
    names (a spot every player's game has, such as a shrine), `text` 1-120 characters of printable ASCII. Returns `{id,
    shared}` (`shared`: the folder is one the player chose). A player keeps 300 messages at most.
  - `messages.list({place})` or `({places = {...}})` (up to 32): the mod's messages there, best rated first, then
    newest, at most 50: `{messages = {{id, place, text, at, good, poor, mine, rated}, ...}, shared}`. Only messages
    the same mod left are listed. Show text as text: a mod that builds its messages from fixed phrases (as Vigil does)
    should show only those that parse back into them.
  - `messages.rate({id, rating})`: 1 good, -1 poor, 0 takes it back; not one's own.
  - `messages.remove({id})` takes back one of the player's own.
- `dungeons.zone_gate_open({zone})`: opens the gate into `zone` (1 to zones - 1) of the floor the player is on, a keyed
  gate or a smoke gate, as `game.dungeon.zone_gate_opened` (with `key = nil`); `{opened = false}` when it already stood
  open. For the mod whose zones the floor has (or any mod when no mod asks for zones now). The Gauntlet opens a
  Warden's way on with it once the Warden falls.
- `dungeons.room_seal({})`: shuts the room the player stands in (well inside it, past its edge cells), each doorway
  closed by a gate facing its corridor, as the Warden room's are; returns `{sealed = true, doors, room = {x, y, w, h}}`
  in cells, or `{sealed = false}` in a corridor or a room with no doorways. `dungeons.room_release()` opens it again
  (`{released}`). One shut room at a time; a new floor forgets it. Every room's doorways are recorded as the floor is
  built, so shortcut doors, illusory walls and the Warden room's own gates are left as they are.
- `dungeons.set_rest_room({enabled})`: floors built from then on are rest floors: a 6x6 hall with the native healing
  spring against its top wall and a 4x4 antechamber with the back floor's stairs in its top wall, joined by one
  corridor that holds the way in and the exit gate. Nothing else goes on them: no other rooms, pillars, character
  parts, Warden room or exit room. Pair it with a registered floor whose `enemies` is empty and
  `dungeons.set_modifiers({chests = -100})` for a floor with nothing to fight or open. `dungeons.rest_room_get()` reads
  `{enabled, state = none | rest, spring, stairs, center, size}` (world units, 160 to a cell); `state` is `rest` only
  on the rest floor the party stands on (not its back floor). The spring's own event doesn't heal on every dungeon's
  theme, so a mod that wants the spring to heal watches the player's distance to `spring`. One mod at a time;
  unloading it turns rest floors off. `DC_REST_TEST=spring|stairs|gate` stands the player, once per rest floor, in
  front of the spring or on the stairs' or the exit gate's trigger (test builds).

### Chronicle weapon styles, effect bursts, tints and shoves

- `weapons.style_set({character, slot, name?, color = {r, g, b}?, glow = {r, g, b}?})` gives one owned weapon its own
  name (up to 40 bytes) in the weapon menu, drawn in `color` on the name scroll, and makes its swing trail glow in
  `glow` instead of its element's colour. The style follows the weapon in that slot: another weapon put there doesn't
  inherit it. `weapons.style_clear({character, slot})` takes one back, `weapons.style_clear({})` all of the mod's.
  `badge` (up to 3 lines) and `details` (up to 5) give the weapon a card: while the menu's cursor is on it, one panel
  takes the place of the powder box and the description, with the badge on the left (a rarity, say) and the name
  over the details on the right. Each line is a string or `{text, color = {r, g, b}?, scale = 0.5..1.6?}`, 64 bytes.
  `weapons.get` and `weapons.list` report a retail weapon's own `name` in the game's language.
- `effects.burst({kind, position = {x, y, z}, scale?})` plays one of the game's own effects at a point: `explosion`
  (the bomb's), `heal` (the healing sparkles), `sparks` or `guard` (hit marks), `impact` (Osmond's bullet), `smoke` (a cloud of dust: the bomb's smoke puffs without the fire). Scale 0.1-4.
- `entities.tint({entity, color = {r, g, b}, frames})` draws a live enemy in a colour for up to 3600 frames (0 ends it).
- `entities.knockback({entity, direction = {x, z}, speed})` shoves a live enemy along a direction, slowing to a stop
  (speed 0.5-40); pointing it at another enemy pulls it in.

### Chronicle playable-character motions (`animations.player_register`)

`animations.player_register({id, file})` adds a mod's own motion to a playable character. `file` is a `.json` file
under the package's `resources/` (up to 4 MiB) in the `moonmod-motion` v1 format:
`{format = "moonmod-motion", version = 1, character, length (1-600 frames), speed?, tracks = {{bone, type =
"rotation"|"translation"|"scale", keys = {{frame, w, x, y, z}...} or {{frame, x, y, z}...}}}}`, rotations as the game
stores them, frames rising from 0 to `length`. Whenever that character's model loads in a dungeon, each of its
registered motions is appended after its last native frame (on the model and its shadow) and its first motion set
grows by one motion number per file; bones a file leaves out hold their idle pose. A registration made while the
character is loaded applies at once. `animations.player_unregister({id})` takes one back (unloading takes all);
`animations.player_list()` lists the mod's motions with the motion number each has on the loaded character. Moves
play them by name (`player.moves_set`, `animation`). A mod registers up to 64. The tools in `tools/anim` write
these files from a character's own rig; see the [animation guide](ANIMATION_GUIDE.md) and
[Gauntlet animations](GAUNTLET_ANIMATIONS.md).

### Chronicle monster motions (`animations.monster_register`)

`animations.monster_register({id, file, model, hits?})` adds a mod's own motion to a native monster model (`model`,
the native model id, as `entities.query`'s `native_model_id`: 1 the Skeleton Soldier, 3 the Dasher). The file is the
same `moonmod-motion` v1 format, its `character` the model's file name (`e03a`, `e06a`); bone names may keep a frame's
attribute (`knife__m`). Whenever a floor loads the model, its registered motions are appended after its last native
frame, on the model, its shadow and each part it carries, in the order they were registered, and its first motion
set grows by one motion number for each. A registration counts from the next load of the model (the next floor), so
register at load. `hits` (up to 4: `{bone, radius (default 2, up to 40), from, to, damage (default 1, up to 10)}`)
become damage spheres on the named frame of every monster of the model as it spawns, live while the motion's frame
lies between `from` and `to` (the motion's own frames): each deals the kind of hit of the monster's first native blow,
and that blow's damage times `damage`. `animations.monster_unregister({id})` takes one back from the next load
(unloading takes all); `animations.monster_list()` lists the mod's monster motions with `motion` (the number to give
`SET_MOTION`) and `start` (its first frame, what `CHK_MOTION_FRM` reads while it plays) once a loaded floor model
carries them, nil before. A mod registers up to 64. Vigil's rolls and attacks are an example
(`tools/anim/vigil_monster_moves.py`, `MONSTER_MOVES` in `mods/moonmod.vigil/main.lua`).

### Chronicle mod moves (`player.moves_set`)

`player.moves_set({moves = {...}})` gives characters this mod's own attacks, up to 160, replacing the mod's earlier set;
`player.moves_clear()` takes them back (and unloading does). A move replays a stretch of one of the character's own
native motions at its own speed and brings its own lunge, spin, hits, bursts, sounds and trail, in place of the native
action. Mods hear `game.player.move` ({id, owner, character, cancel, variant, frames}) as one starts (`variant` is the
number of the variant that played, or nil; `frames` how many steps it runs).

- `id` (1-40 bytes), `character` (one of the six), `trigger`:
  - `run_attack`: the attack button after running for `run_frames` (1-300 game steps, two drawn frames each),
    still running as attack is pressed (stick pushed hard, nothing locked on; locking on doesn't count as running).
  - `guard_attack`: the attack button while guarding (locked on, R1 held).
  - `dodge` / `dodge_back`: L2 with the stick pushed (the move turns the way it points) / at rest (he keeps his
    facing). A `dodge` can take a `direction`: `any` (the default), or, while locked on, `toward` or `away` (the stick
    within 45 degrees of the way to the target, or of the way from it) or `left` or `right` (the stick between them).
    A `left` or `right` dodge keeps him facing the target and carries him the way the stick points: a side roll.
    The dodge for the stick's way wins, and an `any` dodge takes the rest. An evade takes L2 ahead of the tuning dodge (`dodge_power`). It also cuts an attack short: a swing of
    the character's own combo, or one of the mod's attack moves, once its last blow is `cancel_after` steps past
    (0-60, default 2). `cancel = false` turns that off. Specials (the jump slash, the wave), a charge being held and
    another evade can't be cut. Evades keep their own cooldown, apart from the attack moves'. `game.player.move`
    carries `cancel = true` for an evade that cut an attack short.
  - `heavy`: R2 pressed at rest (the heavy attack). A character with an R2 move (`heavy` or `combo_finisher`) gives
    up R2's first-person view in dungeons.
  - `combo_finisher` with `chain` (1-6): R2 pressed partway through the attack combo, once `chain` swings in a row
    have laid their blow (each within 150 steps of the last; a blow counts for a new swing when the action changes
    or more than 6 steps have passed, so a long swing's several blows count once; for Xiao, Ruby and Osmond each
    shot or cast counts). R2 cuts any native attack short while the chain is live, even the next swing before its
    blow, or comes at rest within 60 steps of the last blow. Combo swings that run with the act flag down
    (Ungaga's) can still be cut. The finisher with the
    longest chain reached wins, so `chain = 2` and `chain = 3` sit side by side. A move (any of the mod's) ends the
    chain.
  - `lock_attack` with `direction` (`toward` or `away`): the attack button at rest while locked on, the stick pushed
    (half way or more) within 60 degrees of the way to the target, or of the way from it. The move faces the target;
    `lunge_angle = 180` carries an `away` move back off it.
  - `evade_attack`: the attack button late in an evade (60% through or more; it cuts the rest short, with `cancel =
    true` on `game.player.move`) or within 20 steps after one ends.
  - `charge_release` (Toan): his charge let go at `min_charge` or more on the game's charge count (0-10; the native
    jump slash comes at 0.5 and the wave at 1.5, a count of 1 being about two seconds held), ahead of the jump slash.
    While Toan has the wave's skill, a charge at `max_charge` or more is left to the wave. His charge flashes orange
    as it reaches `min_charge`.
  - `art`: R2 while guarding (the guard's own state, locked on or not with `guard_rules` `without_lock`). `weapons`
    (up to 64 native weapon item numbers, 257 and up; none means any) and `min_level` (1-99, default 1) say which
    equipped weapon it is for: the first of the character's arts whose list holds the weapon he holds, at that level
    or higher, plays. Any number sit side by side, another mod's too. Vigil gives each of Toan's blades one.
  - `played`: no button; only `player.move_play` starts it. Any number of a character's `played` moves sit side by
    side, another mod's too. Vigil's flask drink is one (each hero's native drinking motion, 28, at half speed).
  - `critical` with `critical = "backstab"` or `"riposte"`: the attack button at rest, tried ahead of every other
    trigger. A backstab takes the nearest live enemy within `reach` (4-60, default 24; the lock target first) whose
    back he stands at, within `arc` degrees of straight behind it (20-180, default 90). A riposte takes the enemy the
    mod armed with `player.critical_set`, while it is armed and within `reach`. He is drawn in to `gap` (2-40, default
    12) of it if farther, and faces it; it stops where it is, is turned to him (a riposte) or away (a backstab), any
    `stop` on it ends, and it plays its half from `pairs` (up to 32 `{model (a native model id), animation (a motion
    registered on that model with `animations.monster_register`: the mod's id or `"mod:id"`), speed? (0.05-4, default
    0.5)}`). Its script waits `hold` steps (0-600; 0 is its pair's length at that speed, else the move's), hits and
    all; its flinch is skipped and its death still plays. An enemy without a pair is held standing.
- `motion` (native motion number 0-63) or `animation` (a motion registered with `animations.player_register`: the
  mod's own id, or `"mod:id"`), `from`/`to` (the stretch, fractions 0-1), `speed` (0.2-4, motion units a step).
- `variants` (up to 4, for a move with an `animation`): `{animation, motion, from?, to?}`, another registered motion
  that plays instead when the move starts while the character is in native motion `motion` (0-63), between the
  fractions `from` and `to` of it (default 0 and 1). The first that matches wins. Vigil's roll pushes off whichever
  foot leads: Toan's run is his native motion 1, his right foot ahead for its first 30% and its last 20%:

  ```lua
  {id = "roll", character = "toan", trigger = "dodge", animation = "toan_dive_roll", -- off his left foot
   variants = {{animation = "toan_dive_roll_right", motion = 1, from = 0, to = 0.3},
               {animation = "toan_dive_roll_right", motion = 1, from = 0.8, to = 1}}}
  ```
- `lunge` (0-6) and `lunge_decay` (0.01-2): a push the way the stick points (else the way the character faces). Every
  move but `run_attack` and the evades faces the lock target if there is one (and pushes that way).
  `lunge_angle` (-180 to 180): the push's angle from the way he faces (180 pushes him backward).
  `blend_in` (1-30 frames): how quickly the move takes over from the pose he is in. The engine fades from it over 10
  ticks otherwise, which smears the first frames of a quick move; Vigil fades its evades in over 3 and its attacks
  over 4.
  `camera` (1-14 steps): how quickly the follow camera closes on the character while the move plays. The game's own
  is 8 (14 locked on), which leaves the camera trailing a roll by 20 units; Vigil gives Toan's evades 3.
  `spin` (-4 to 4): whole turns, made between `spin_from` and `spin_to` (fractions of the move, default the whole). `invincible`: no hits land during it. `gauge` (0-100): action gauge
  spent, and the move needs that much. `wear` (0-5): weapon wear, as a swing's. `cooldown` (0-600 steps).
- `hits` (up to 12): `{at (0-1 through the move), radius (1-40), reach (-20 to 40, ahead of the character), height,
  damage (times the weapon's attack, 0-10), knockback (0-10), heavy?, charged? (enemy_hit reports it charged),
  burst? (an effects.burst kind), burst_scale?}`. A hit strikes every enemy in its reach once.
  A hit with `shot = true` fires projectiles instead: `count` (1-5) shots fanned `spread` degrees apart (0-45,
  default 10) at `speed` (1-10, default 5), from the slingshot's tip (Xiao) or the weapon hand, toward the locked-on
  target or the way the move faces, each for `damage` times the weapon's attack. Xiao fires her slingshot shots,
  Ruby her magic orbs (damage on her attack and magic averaged) and Osmond his gun's bullets; a melee character's
  shots are Xiao-style. They use the game's player shots
  (12 at a time). A shot, the move's or a native one, counts as a blow for an evade's cancel. A Xiao-style shot can
  have its own start and look: `from` (a frame of the character's model, e.g. `"jnt12_1"` the head; default the
  weapon's tip), `from_ahead` and `from_rise` (-10 to 10: moved that far the way the move faces, and up), `cell` (0-15:
  the `dun/effect/basefx01` picture's 32 x 32 cell it is drawn with, row by row; 8 is a glowing blue blob) and `size`
  (0.3-4). A `burst` on a shot plays where each one lands (a wall, the floor or an enemy). Opar's spit is
  `{shot = true, from = "jnt12_1", from_ahead = 2.6, from_rise = -0.4, cell = 8, size = 2.2, burst = "heal"}`.
- `cues` (up to 12): `{at, sound? (swing, swing_heavy, voice, voice_2, voice_3, shout, shout_2, action),
  trail? (light, wide, heavy, wave, slam)}`.

Another mod's move on the same character and trigger is refused. Of a mod's own `charge_release` moves, the first in
its list that the charge reaches plays, so a high `min_charge` listed ahead of a lower one takes the longer charges.

### Chronicle player forms (`player.form_set`)

`player.form_set({pack, frames?, hide_weapon?})` turns the active character into another model where he stands: his
model reloads from `pack` (`dun/mainchara/<stem>.chr`, a mod's `resources.override`), a pack laid out like a player's
(a `base.cfg` whose motion table lists the character's motions by the numbers his action plays; a monster's pack works
once its `info.cfg` is renamed and its table remapped, see `art/opar/make_form.py`). His action, weapon stats, moves
and health stay his. `frames` (up to 16) names stand-ins for the frames the player code looks up by name that the
form's model lacks (`weapon` the grip, `item` the hand items are held in, `tukene1`, `jnt2_1`, and a shot's `from`),
e.g. `{weapon = "r_hand"}`. `hide_weapon` (default true) leaves the weapon undrawn; its hits still swing from the
grip. `scale` (0.1-4, default 1) draws the model that much its size (a monster's model is far bigger than a hero's). Mod motions (`animations.player_register`) are not added to a form's model; its moves use native `motion`
numbers. `player.form_clear()` gives him his own model back. Either fails (try again) while an action or a scene holds
the model, as a character switch does. A new floor, switching the character in and out, and unloading the mod also end
it. Opar's Jump Slam turns him into the Opar monster this way, for one slam.

`player.critical_set({entity, frames?})` opens one enemy (a live monster handle) to the mod's `riposte` criticals
for `frames` steps (1-600, default 120), as after a parry or a stagger; one at a time, a new one replaces it, and a
critical on it spends it. `player.critical_clear()` closes it. Each critical that starts sends
**`game.player.critical`** `{id, owner, kind (backstab or riposte), entity, native_model_id?, hold}`: a mod's
critical damage hangs off it (Vigil raises its blows on that kind of enemy for `hold` ticks with a formula).

`player.move_play({id})` starts one of the mod's own moves (`player.moves_set`) now, whatever its trigger: a
chained move, such as the move a form makes as soon as it is taken. The move must be the active character's; like
a trigger it needs him free to act and the move's gauge, but it doesn't wait on the moves' cooldown. It fails while
he is in an action (try again).

### Chronicle town villagers (`characters.register` kind = "npc")

```lua
game.characters.register({id = "moon_trader", kind = "npc", name = "Moon Trader", town_id = 0,
  model = "e04", position = {x = 120, y = 0, z = -340}, facing = 90, talk_event = nil})
game.events.subscribe("game.npc.talk", function(event) ... end)  -- event.id, name, town_id
```

- Up to 4 villagers; they take the free villager slots (retail fills at most 6 of 10) each time the town picks its
  villagers, stand still at `position`, facing `facing` degrees.
- `model` is a villager in the town's `gedit/e0N/chara/` folder, or a mod's own override of
  `gedit/e0N/chara/<model>.chr`.
- The talk button runs native event `talk_event` when given, else publishes `game.npc.talk` to the mods.
- `content.list()` shows them (`content_type = "npc"`, `in_town`, `villager_slot`).

Not yet: Whole new dungeons (an 8th dungeon and beyond): see the plan in HITLIST 0bb. `dungeons.register` adds floors to
dungeons 0-4 only.

### Native dungeon entity query

```lua
local result = assert(game.entities.query({type = "monster"}))
for _, entity in ipairs(result.entities) do
  print(entity.id, entity.health.current, entity.health.maximum)
end
```

Both adapters currently support only `type = "monster"` while a dungeon is active. The query returns living monster slots with native definition, health, status, and position data. Chronicle also includes each actor's reveal state, combat stats and drop item, plus `native_model_id` when the floor's native model mapping is known. Chronicle keeps `id` as a slot label and returns a separate generation-checked `entity_id`; ChronicleTwo's `id` is already the generation-checked actor handle. Use those stable handles with `entities.get` to detect slot reuse. Chronicle updates actor generations from the native setup and floor-clear paths. ChronicleTwo assigns each returned entity a slot generation. Chronicle's `entities.set_stats({entity, hp?, max_hp?, defense?, reward_exp?, reward_money?, drop_item?, damage_scale?, hit_reach?, hit_share?, vulnerable?})` changes one or more stats on a live revealed enemy. `hp` and `max_hp` are 1–1,000,000, and `hp` cannot exceed the resulting `max_hp`; `defense` is 0–32,767; `reward_exp` is 0–32,767; and `reward_money` is 0–2,147,483,647; `drop_item` is `-1` to clear or a valid built-in native item number; on Chronicle, `damage_scale` (0–100) multiplies what that enemy's own attacks and the shots it fires take off the player, before the player's defense and `combat.register_player_formula` (a new actor in the slot, or a new floor, sets it back to 1); and `hit_reach` (0–200 game units) is added to each of that enemy's body hit-spheres when the player's blows are checked against it, for a weak point a blade cannot otherwise reach (it resets to 0 the same way); and `hit_share = true` makes each of the enemy's body hit-spheres take from every character the share of a blow it takes from the character it suits best. A story boss's scripts set a per-character damage percentage on each sphere, and many shut out whole heroes (the Ice Queen takes nothing from anyone but Ruby), so a boss met by a different party needs this to be beatable. It resets to false the same way. `vulnerable = true`
lets blows land through the enemy's own script invincibility (the native `STATUS_SET_MUTEKI`), and a body sphere that
no hero's blow hurts takes the blow whole; `combat.damage` and a companion's blow land too. The King's Curse is
invincible by its script (only its coffin dies in its fight), so the Gauntlet sets this on it when it roams a floor
alone. It resets to false the same way. Chronicle also supports `entities.script_int_set({entity, index, value})` on a live member of a boss's cast (the boss or a helper it spawned through `characters.spawn` with `arena_slot`): it writes integer `index` (0–255) of the global block that cast's native scripts share, and returns `{entity, index, previous, value}`. A cast's scripts pass signals through that block (the pink Genie reads each hand's integer to learn it is broken), so a mod can hold one when its own spawning bypasses the native path. Chronicle also supports `entities.scale_set({entity, scale})`, an owner-scoped uniform visual multiplier from 0.5 to 3.0; it captures the native scale and restores it on actor reuse or mod unload. This operation only changes the live enemy model and shadow. If only `max_hp` changes, current HP keeps the same fraction. The operation rejects stale handles, unrevealed actors, and actors outside an active Chronicle dungeon; ChronicleTwo does not support it. Both ports support `entities.spawn` for registered enemy definitions; it shares the `characters.spawn` request shape and returns a mod-owned actor handle. Chronicle only spawns when the definition's exact native template has already been loaded for the current dungeon floor. ChronicleTwo reuses an already-loaded compatible template model/script; if the template is not loaded on the current floor, spawn returns a clean failure rather than loading assets dynamically. The `entities.despawn` API in both ports removes a live enemy spawned by the calling mod and clears per-actor runtime state and native collision/projectile references. It invalidates the generation-checked handle, updates floor alive counts, and skips kill credit and drops. Chronicle rejects mimics because the dungeon map retains their chest trigger; ChronicleTwo rejects actors held by a native interaction. Both adapters also attempt to despawn safe, live owned actors when their Lua mod unloads; native safety guards leave actors in place if despawn is unsafe. NPC/world-object spawning remains unsupported. Query calls outside an active dungeon fail instead of returning an empty list; handle lookups after leaving a dungeon return `status = "expired"`.

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

`combat.strike_player({x, y, z, radius = 2..120, damage = 0..9999, kind = "light" | "heavy"})` lays one native hit at
that point that only the player can be struck by, as a monster's blow would be: the game's own hit test takes it on the
next frame (the player's defence comes off), so a guard, a parry, a dodge's invincibility and poise all work on it, and
`game.player.hit` reports it with no `entity`. Light flinches; heavy knocks back. It is for a mod's own attacks (a
boss's new move after a telegraph, a trap). Dungeon only.

`combat.feel_set({hit_stop = {light, heavy, critical, hurt}, shake = {light, heavy, hurt}, rumble = true})` gives
blows weight. `hit_stop` values are frames (0-12) the whole floor holds still when one of the player's blows lands
(`heavy` for a heavy hit or a charged one, `critical` as a critical begins) or when the player is hurt (`hurt` for a
knockback, half of it for a flinch). It is drawn, not stepped, and a swing that strikes several monsters in one frame
freezes once. `shake` values (0-10) are the camera shake's strength for the same moments, and `rumble` turns the pad's
vibration on for landed blows and criticals. Every field is optional and missing ones are 0. One mod's feel is set at
a time (another mod's call fails until it clears). `combat.feel_clear()` takes it off; unloading the mod does too.

`player.tuning_set` also takes `input_buffer` (0-20 steps): a roll or R2 move (`player.moves_set` dodge, dodge_back,
heavy, combo_finisher, art) pressed when it can't start, such as late in a swing before its cancel point, mid-roll or in
a hit-stop, is kept that long and starts at the first step it can. 0 is the game's own (tried on its frame only). `dodge_gauge` (0-100) is what the `dodge_power` shove costs
of the weapon gauge (refused with less); the shove is only for a character with no dodge move of a mod's. And
`lock_camera` (boolean): locked on, the camera turns to keep the target straight beyond the player, with 8 degrees of
slack far off and 30 close up, where the game lets it drift up to 90 degrees off first; locked on to a large monster
(body radius or half its height past 15 units) the camera may also sit up to 60 units further out, walls still
pulling it in. And `chain_cancel` (0-30
steps, 0 off): R2 pressed in an attack's recovery, its last blow that many steps past, cuts into the heavy (a native
swing, or one of the mod's own attack moves, a heavy among them); attack pressed in a mod attack move's recovery ends it
so the native combo starts on that press. Several mods asking: the earliest wins.

`combat.status_add` supports `slow`, `stop` and `haste` for live, revealed Chronicle enemies. `haste` is not a native status: while it lasts the enemy's scripted motions and moves play 1.4 times as fast (the inverse of `slow`, and the two multiply), and it ends with the enemy's slot. The generation-checked handle prevents a delayed hit event from affecting a new enemy that reuses the same slot. Duration is 1–32767 native simulation steps, and an existing timer is only extended. ChronicleTwo does not expose this operation.

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

Formulas modify positive damage after each game's native defense, elemental, and damage-block calculations in the native enemy-hit pipeline. Chronicle also publishes `game.enemy_hit` after an accepted positive native weapon hit. That event includes the generation-checked enemy `entity`, `slot`, player `attacker`, stable `weapon_id`, `native_weapon_id`, final `damage`, `element`, `frame`, and `native_model_id` when known. The event is informational and delivered on the next runtime pump; use the formula filters for damage changes. Chronicle's `game.enemy_hit` also carries `charged`: true when the hit lands within a second of a charged move
(Toan's held charge, Xiao's full-gauge shot, Goro's swing held into a second spin, Ruby's full charge, Osmond's charged
shot; Ungaga's combo has no charge). A formula with `charged = true` (or `false`) applies only to such (or other) real
weapon hits; calls without hit context skip it. Formulas also modify explicit `combat.damage` requests when unfiltered. A zero or blocked base hit remains zero; final damage is clamped to 0–1,000,000, then rounded upward to a whole HP for scripted `combat.damage`. These formulas do not create new attack, animation, or collision behavior.

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

Chronicle's **charm slots** are each character's own slots on the item page, beside their weapon and shield on the
character panel, that hold only the four amulets (Anti-Freeze, Anti-Curse, Anti-Goo, Antidote). An amulet in a charm
slot is out of the bag and takes none of its room. When a hit rolls an ailment, an amulet in the active character's
charm slots guards against it before the quick slots are looked at, spending a use as the game's own amulets do and
breaking with the last. On the
page, Right from the shield reaches them (an empty one shows an amulet blacked out), Cross puts the held amulet in (or picks it up), and Square sends it back
to the bag. `items.charm_slots_set({count = 0..4, feather = optional boolean})` (`game.write`) opens that many amulet
slots for every character, and with `feather = true` one more after them that takes only Dran's Feather (an amulet slot
refuses the Feather and the Feather's slot refuses amulets); none, the default, is the game's own page.
`items.charm_slots()` returns `{open, feather, characters = {toan = {{slot, kind, item_no, id, uses}}, ...}}` (`kind`
is `"amulet"` or `"feather"`, `slot` the position on the page) with every character's shown slots: those open, plus any further one still holding an amulet, so an amulet is never out of reach after its mod closes the slots.
They are not in the save image: the engine keeps them beside it as `charms.json` in the save slot's folder, by character id (a character no mod
registers now keeps theirs), written
and read with the save, so they come back with it whether or not the mod is loaded. In a dungeon the active
character's charms show on the HUD left of the gate-key plate (before any `render.hud_icon_set` icons), each with its
uses left in the corner, as the item page's slots show them. A worn amulet sells for less: its price times the uses
left over its full uses, and nothing once it is worn below half of them. Dran's Feather, in its own slot, lightens a
`dodge_run` run (half the drain), spending a use each tick of running, and shows its time left in seconds; it sells
for its price whatever is left. A Feather a file keeps in an amulet slot moves to its own on load.

### Chronicle gear

```lua
local piece = assert(game.items.gear_give({kind = "boots", name = "Swift Boots", rarity = 1, value = 180,
  effects = {run_cost = 16, guard = {goo = 30}}}))
game.items.gear_equip({uid = piece.uid})              -- on the active character; or character = "xiao"
local gear = game.items.gear()                        -- {pieces, bag, bag_max, bag_slots, worn = {toan = {slots, effects}}}
game.items.gear_unequip({kind = "boots"})             -- back into the bag
game.items.gear_remove({uid = piece.uid, sell = true}) -- {uid, money}
game.items.gear_page_set({icons = {hat = "gear_hat", tunic = "gear_tunic", gloves = "gear_gloves", boots = "gear_boots"},
  parts = {toan = {hat = {draw = {"boushi"}, turn = 40, bare = {"boushi", "cloth1"}},
                   boots = {draw = {"skin", "l_f", "r_f"}, fit = {"l_f", "footl", "eff7"}, turn = 70, tilt = 15}}}})
```

Each character wears up to five **gear** pieces, one of each kind: `hat`, `tunic`, `gloves`, `boots` and `pouch`. A mod makes
each piece with `items.gear_give({kind, name, rarity?, value?, icon?, color?, effects?})` (`game.write`): `name` 1-32 bytes, `rarity`
0 to 4 (common, uncommon, rare, epic, legendary: the Gauntlet's five, named and coloured so in the item page's help box; a gear.json from before version 2 had four, and its 3, unique, loads as legendary), `value` the Gilda it sells for (0 to 65535), and
`effects` any of `guard` (`{freeze, poison, curse, goo = percent}`, 0 to 90 each), `stamina` (gauge a second, 0 to
120), `lightness` (percent off a swing's cost, 0 to 50), `defence` (0 to 99), `run_cost` (percent off what a
`dodge_run` drains, 0 to 75), `poise` (points of hits taken without a stagger, 0 to 8) and `bag` (item bag slots, 0 to
50). `icon` is the stem of an `icons/<stem>.png` a mod provides (as `items.register` takes
one; without it the piece shows its kind's icon) and `color` `{r, g, b}` (0 to 255 each) tints it, so one grey icon can
make a red pair of boots and a blue one. It goes into the gear bag, which holds 99 pieces besides those worn, and the
result is the piece: `{uid, kind, rarity, name, value, effects, worn_by, icon, color}`; a full bag fails. `uid` numbers the piece for good
(never reused in that save). Pieces are not the game's items and take no room in the item bag.

`items.gear_equip({uid, character?})` puts a piece on (`character` an id or `"active"`, the default), taking it off
whoever wore it; what was in that slot goes to the bag. `items.gear_unequip({kind, character?})` takes one off into
the bag (failing when the bag is full or nothing is worn there), and `items.gear_remove({uid, sell?})` takes a piece
away, worn or not, with `sell = true` adding its value to the wallet (up to the wallet's 65535). `items.gear()`
(`game.read`) returns every piece, the bag's count and size, and for each character the uid in each slot (or nil) and
`effects`, what their worn pieces do together.

The engine reads the active character's worn effects where the game decides each thing, added up across the pieces
and capped: a hit that rolls an ailment first rolls the `guard` chance against it (90% at most) and, if that holds,
nothing happens and no amulet is spent; `defence` is taken off each hit with the character's own; `stamina` is added
to the refill (`player.tuning_set` `stamina`, or the game's) on any frame it isn't stopped, halved by Goo (120 at
most); `lightness` scales every swing's cost (half at most) on top of the tuning's `lightness`; `run_cost` scales the
run's drain (75% off at most) on top of Dran's Feather; `poise` (8 at most) takes a landed light hit for 1 point and a
heavy one for 2 with no stagger: the damage and the hurt sound, but no flinch, knockdown or recoil, and the swing or
dodge under way goes on. A hit past what is left staggers as usual and leaves poise whole for the next; poise is whole
again 2 seconds (120 frames) after the last hit. A trap, a broken guard or a hit that would empty the life bar always
staggers. `bag` grows the game's item bag (the one its Pockets grow) by the largest any character wears (50 at most;
one bag for the party), never past the game's own 100. Taken off, the bag shrinks as far as its items let: items in
the slots that go move into empty ones, and while it is too full it stays larger, shrinking as it empties. The engine
remembers what it added (`items.gear()` `bag_slots`), so the size the save's Pockets gave it is left alone; the item
page and the gear calls bring the bag in line. Gear is kept beside the save as `gear.json`, read and written
with it; a piece worn by a character no mod registers now stays theirs.

`items.gear_page_set({icons = {hat, tunic, gloves, boots, pouch?}})` (`game.write`) opens the gear page on the game's item
page, each `icons` entry a stem as `icon` takes (the first four are needed; each kind's empty slot shows its icon blacked
out). Name `pouch` too and the page has a pouch slot, at the character's hip in the outer column; leave it out and the
page has four slots, as before. The personal board gets a fourth tab, **Equipment**, holding the bag: Cross picks a piece up and puts it back, the
trash can throws it away, and the help box names the piece under the cursor with its rarity, price and effects. The
character card gives way to the **hero page**, a panel in the help windows' frame: the character alone and larger, down
his left side his charm slots and then his weapon (its attack in the corner, its wear up its edge) and shield, any
charm slots past the second (and the pouch) in a column further out, the other gear slots down his right side and his HP and water
across his feet. The help box at the bottom left says what Cross and Square do on the slot under the cursor. Cross with a piece in hand on its kind's slot puts it on, the piece it replaces coming up into the hand; Cross
on a worn piece takes it into the hand (past a full bag, until it is put down) and Square takes it off to the bag.
One of the character's weapons picked up from the Weapons tab and dropped on the hand is equipped, with the weapon
menu's checks (a curse, a no-weapon-change zone, a character out of the party); an Osmond or Ruby in play keeps theirs
until the weapon menu, which reloads their weapon's effects. The mouse carries pieces as it does items: press on a cell
or slot, let go on another. `items.gear_page_set({})` closes it all, and `items.gear()` reports `page`.

While the page is open, a native item shop shows the Equipment tab on the player's side too: Triangle on a piece sells
it for its `value` (the shop's usual "sell it?" question; a wallet at 65535 refuses). Cross can't take a piece onto
the counter. `items.gear_stock_set({shop, goods})` (`game.write`) stocks a shop (its number, as `shops.*` uses: 0 to
17 for the game's own) with up to 10 pieces, each as `gear_give` takes it plus `price` (0 to 65535 gilda; its `value`
when left out). They lie in the shop's empty cells after its own goods, drawn as in the bag, and the help box names the
one under the cursor with its price. Triangle buys one into the bag (refused past a full bag or a thin wallet); Cross
can't drag one into a deal. A bought piece is gone from that shop until the mod stocks it again, and `{shop, goods =
{}}` takes the shop's gear away. Stock is kept for the session only, not in the save; with the page closed no shop
shows its gear.

`parts` (optional) shows each hero's own clothes in place of the icons: for a character id, each kind names frames of
that character's menu model, either as a list (1 to 8 names, up to 31 bytes each; a name matches a frame's whole name
or the part before its `__` flags) or as `{draw = names, fit = names?, bare = names?, below = names?, turn = degrees?, tilt = degrees?}`. The slot
draws only the `draw` frames, grown and centred until the `fit` frames (all of `draw` when left out) fill it, the model
turned `turn` degrees (-180 to 180, left positive) and held there, and leant back `tilt` degrees (-90
to 90, forwards when negative) so a part the menu camera sees from above, such as a boot, shows from the side. A
piece's `color` fills the ground behind its part and warms the light a little, so the part keeps its own look; an empty
slot draws its parts dark, except a kind with `bare` frames: the hero isn't wearing them, so its empty slot has the
kind's icon. This covers the hero page's slots, the Equipment tab's cells and the piece
in hand, for pieces whose icon is their kind's own; a piece with an icon of its own, a kind with no parts and a hero
with none keep the icon, as does the page while the model is still loading. The parts are the character's whose page is
shown. Cloth the model simulates is drawn in a slot as it hangs at rest. `bare` names frames the character's models
leave out while nothing is worn in that slot, on the hero page and in the world alike (cloth hanging from one of them is
left out with it): his hat, with no hat on. The hero in the dungeon and on the item page are known by which model they
are; elsewhere (Toan in town) a model is the character's when its root's name starts as the character's pack does
(`c01`). A frame that is any model's root, or a character with none named, is drawn as ever, and nothing is left out
while the page is closed. `below` cuts the slot off a third of the way down the named frames' box (at the joint itself
for a bone with no mesh of its own, such as an ankle), and fits the slot to the `draw` frames' vertices under that cut instead of `fit`: a part of a bigger mesh
alone, as his shoes are part of his body (`draw = {"skin"}, below = {"l_f"}`, the shoes under his ankle wraps). Toan's
are `boushi` (hat) with `cloth1` (its tail, cloth), `cloth2` and `cloth3` (his vest's front and back, cloth) with
`beruto` (the belt), `l_g` with `l_hand` (the glove's cuff and the hand), `l_f` (his ankle wrap) and `kaban` (the
satchel at his hip); `r_g`, `r_hand` and `r_f` are the other side's, and `skin` is his body, his shoes and shirt with
it. With no hat his hair is open at the crown where the hat sat, which a camera from above can catch. The others'
menu models (`commenu/dungeon/c0Nmodel.pak`): Xiao `l_hand` (her paw), `l_ude` (arm wrap), `l_asi` (leg wrap), `suzu`
(bell), `skin` (her dress and shoes); Goro `mant` (his bear mantle, cloth), `faces2`, `skin` (the hood is part of it);
Ruby `cube37` (tiara), `body5` (left hand and cuff), `cube40`/`cube60` (slipper toes), `l_foot`, `skin`; Ungaga `cap`
(feathered cap), `cloth1`/`cloth2` (sash tails, cloth), `l_udewa_2` with `r_hand4` (a bracer and its hand),
`kubikaazri` (necklace), `skin`; Osmond `face` (goggles), `l_hand4` (glove), `bag`, `backpack` (his jet pack), `l_foot`,
`skin`.

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

Chronicle lists its 120 retail weapons and registered definitions. `weapons.get()` accepts a `chronicle:weapon:<item_no>` ID for retail weapons, a mod-owned stable ID, native item number, or selector object. Results include base stats, caps, elements, monster effectiveness, socket count, experience/build-up metadata, and matching owned instances with equipped state. Each owned instance reports maximum `stats.durability`, live fractional `stats.durability_current`, per-instance `elements`, `vs_monster`, and `flags`. The ownership fields are `nil` without an active save. Registration allocates one of 32 appended native slots (377-408) and persists the stable ID to `moonmod/game-content/chronicle-weapon-slots.json`, so the same mod keeps the same native item number across launches. A definition inherits its template's owner, icon, name message, elements, sockets, experience, and build-up data; it may set `owner`, `stats.attack`, `stats.durability`, `stat_caps.attack`, and `stat_caps.magic`. `owner` may be a registered playable character (`"opar"`): the weapon then belongs to the character he fights as (`owner` reads that one, so the combat code treats it as theirs) and sits in his own row of the weapon page, chests and pickups put it there, and only he can be given it; `weapons.get` reports him as `holder`. `assets` must be empty. The API's `name` is available to Lua, but Chronicle's inventory menus still display the inherited native localized name. `weapons.give({id, character?})` adds one copy through the game's inventory path and assigns it to the compatible character, or to `character` (a joined playable id) when given; a weapon fits its owner, and a registered playable character the weapons of the character he fights as (`fights_as`). `weapons.equip({id, character?, slot?})` equips one owned compatible weapon on a joined character. Chronicle changes the loadout in an active Georama town or dungeon; in a dungeon, equipping the active character's weapon reloads the character and weapon models through the native character-switch routine, and is refused during an attack or other locked action. `weapons.remove({id, character?, slot?})` deletes one owned instance that is not equipped (Chronicle only). The character defaults to the active member; `slot` is required when the character owns multiple copies. Repeating the current selection succeeds with `changed = false`. `weapons.stats_set({id, character?, slot?, attack?, endurance?, speed?, magic?, durability?, elem?, vs_monster?, flags?})` is Chronicle-only and updates exactly one owned native weapon instance. Scalar stats accept integers from 0 to 32767, `elem` takes five values and `vs_monster` takes ten values from 0 to 127, and flags accept a 16-bit value. Specify both `character` and `slot` when the weapon has multiple copies. A durability-maximum update preserves the current durability fraction; element and effectiveness writes update the native saved weapon data. `weapons.durability_set({id, durability, character?, slot?})` sets current durability from zero through that instance's native maximum without changing the maximum. New model/animation identities are not part of this registration path yet.

`weapons.stat_label_set({attack?, endurance?, speed?, magic?})` (`game.write`, Chronicle only) shows a mod's own image
as a stat's label on the weapon menu's cards, in place of the game's two letters (At, Ed, Sp, Mp): each value is a stem
as `items.gear_give`'s `icon` takes (icons/<stem>.png, put there with `resources.override`). The card under each
weapon draws it in the label's 16x12 cell. On the Status tab, whose four labels are painted into it overlapping one
another, any label set wipes the whole column to plain stone and lays all four again one size, each in a 26x15 box
centred on its bar: the mod's image, or the game's own label from the card for a stat left out (so set all four for
one look). Draw a label at 52x30 for a crisp one (it is loaded as 32x32 and stretched back). `{}` gives the game's
labels back. It changes only the label, not the stat. Vigil sets all four, Speed reading "Lt" under its Lightness rule.

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

Chronicle's `game.dungeons.list()` returns the seven native dungeons plus mod-registered extensions. `game.dungeons.get(id)` reads either kind by stable ID; a local suffix resolves in the calling mod's namespace first and then against the built-in catalog. `game.dungeons.register()` and its `game.world.register_dungeon()` alias append floors to native dungeons 0-4. Each floor requires a local `id` and a `source_floor`: an integer selects an existing floor's enemy layout, while a string selects an earlier floor in the same registration. Registration copies both normal and back-side native enemy layouts into new native floor slots. An optional `enemies` array replaces that floor's roster with up to nine character IDs registered by the same mod; an empty array (which reaches the engine as an empty object from Lua) creates an empty encounter: no monster stands on the floor at all, nor carries its key. Mod-owned custom model resources must be available when the floor is registered. The game's procedural map builder supplies the existing dungeon theme, room geometry, and item rules; floor names and stable IDs are queryable metadata while Chronicle's native floor display remains numeric. One registration can add at most eight floors, and each target dungeon can have at most 25 floors total, matching Chronicle's fixed save and restriction-zone tables. Gallery of Time is already at 25 floors and Demon Shaft uses a separate 100-floor path, so neither accepts additions. Asset overrides, custom geometry, and standalone dungeon maps remain unsupported. Registered floors remain active for the current game session.

### Chronicle floors with their own map pack

A floor definition passed to `game.dungeons.register` may name its own floor pack with `map`. The registering mod must first
own native overrides for `dun/<map>.cfg` and `dun/mpd_pack/<map>.mpd`. These paths are new: they have no retail file, so the
retail-size rule does not apply. Each file may be up to 6,400,000 bytes, which is the limit of `BtMapJumpLoad`'s map buffer.
`map` is 1-15 characters of lowercase letters, digits or `_`. When the player enters the floor, the game loads that pack in
place of the one the dungeon's event script chose. A floor without `map` keeps the native pack. `dungeons.get/list` report
`map` on such floors.

```lua
for _, path in ipairs({"dun/moon_annex.cfg", "dun/mpd_pack/moon_annex.mpd"}) do
  assert(game.resources.override({path = "resources/" .. path, game_path = path}))
end
local annex = assert(game.dungeons.register({
  id = "moon-annex", name = "Moon Annex", dungeon = 0,
  floors = {{id = "annex", source_floor = 3, map = "moon_annex"}},
}))
print(annex.floors[1].native_floor_id, annex.floors[1].map)  -- 15  moon_annex
```

The pack must be in the format the floor builder expects: a `.cfg` and `.mpd` pair, for example from dc1tk
`maps-export` -> edit -> `floor-build`. Its part names must match the ones the dungeon's map builder asks for. The floor
still uses the dungeon's theme rules and map type, and the HUD keeps the native numeric floor display (past retail
floor 15, Divine Beast Cave shows "Boss").

### Chronicle floor lighting (`dungeons.lighting_get` / `dungeons.lighting_set`)

`game.dungeons.lighting_get()` reads the active floor's fog, background colour and ambient light, for the front side
and the back side of the floor, and which side is drawn now (`side = "front"` or `"back"`). They are the values the
floor script's `FOG`, `BG_COL` and `AMBIENT` lines set (`URA_FOG`, `URA_BG_COL`, `URA_AMBIENT` for the back side), and
the dungeon draw applies them every frame. `game.dungeons.lighting_set{side?, fog?, background?, ambient?}` changes them
live: `side` is `"front"`, `"back"` or `"both"` (default), `fog` takes `near`, `far` (0-100000), `min`, `max` (0-255),
`r`, `g`, `b` (0-255), and `background` and `ambient` take `r`, `g`, `b` (0-255). Every field is checked before anything
is written; it returns the lighting as `lighting_get` does. Changes last until the next floor loads its own script, so
a mod that wants them on every floor sets them again when a floor starts. Requires `game.read` / `game.write`;
Chronicle only.

```lua
moonmod.on("game.tick", function()
  local now = game.dungeons.lighting_get()
  if now and now.front.fog.r ~= 170 then
    game.dungeons.lighting_set({fog = {near = 150, far = 700, r = 170, g = 20, b = 20}, background = {r = 70, g = 0, b = 0}})
  end
end)
```

**Lights and view distance.** `lighting_set` also takes `lights`, a list of up to three
`{light = 1..3, x?, y?, z?, r?, g?, b?}`: the floor script's `LIGHT_C` directional lights (`URA_LIGHT_C` for the back
side). `x, y, z` is a direction (normalised for you), and `r, g, b` is its colour from 0 to 255. `view_scale` (0.1-10)
is the floor script's `VIEWLEVEL`, which scales how far the floor is drawn. `lighting_get` reports `front_lights`,
`back_lights` and `view_scale`. Water surfaces are floor geometry (`PT_WATER` in the floor script). Edit them with dc1tk
`maps-export` / `floor-build`.

```lua
game.dungeons.lighting_set({lights = {{light = 1, x = 0, y = -1, z = 0, r = 255, g = 40, b = 40}}, view_scale = 2.0})
```

### Chronicle monster AI from Lua (`monsters.natives` / `monsters.call`, hook `native.monster.run`)

Every monster runs a compiled script (`dun/monstor/<name>.stb`), and that script calls natives such as `SET_MOTION`,
`GET_POSITION` and `SET_MOVE`. `game.monsters.natives()` lists the 86 natives a mod can run, each with its `name` and
`op`, under the names dc1tk's decompiler uses without the leading `_`. `game.monsters.call{entity, native, args?}` runs
one of them on a living monster, as that monster's own script would. `entity` is the generation-checked `entity_id`
from `game.entities.query`. `native` is a name or an op number. `args` is a list:
- a number (whole numbers go in as integers, the rest as floats) or a boolean;
- a string, for a model frame's name (1-31 letters, digits or `_`), such as `SET_SHOT`'s `"dcol0"`: `{"dcol0", x, y, z}` fires the monster's own projectile from that frame at a point;
- `{out = "int"}` or `{out = "float"}` for a value the native writes back. These come back in order in `out`.

`_RUN_SCRIPT`, `_PUSH_IGLOBAL`/`_POP_IGLOBAL` and `_SET_REFERENCE`/`_DEL_REFERENCE` need a running script, so they are
not offered. Requires `game.write`.

```lua
local m = game.entities.query({type = "monster"}).entities[1]
local pos = game.monsters.call({entity = m.entity_id, native = "GET_POSITION",
                                args = {-1, {out = "float"}, {out = "float"}, {out = "float"}}})
print(pos.out[1], pos.out[2], pos.out[3])
game.monsters.call({entity = m.entity_id, native = "SET_MOTION", args = {3}})
```

The `native.monster.run` script hook (`game.scripts.override`) runs before a monster's script program. The context is
`entity`, `slot`, `program_no` and `model`; the programs are 1 (spawn), 50 (revealed), 100 (its idle loop), 110 (hit)
and 120 (killed). Calling `game.scripts.call({id = "native.monster.run"})` runs the retail program. A callback that
does not call it takes the monster over for that program. The program then counts as finished, so the hook runs again
on the next frame, and a mod can drive the monster each frame with `monsters.call`.

`ctx.model` is the floor's model slot (0-2, the order the floor loads its monsters in), not the monster's kind: find
the kind from `entities.query`'s `native_model_id` for `ctx.entity`. The hook runs when a program starts. A monster's
retail idle loop (100) never ends on its own, so when a mod installs or removes a `native.monster.run` override, every
monster then in its retail idle loop starts it again once: the new override takes it over on the next frame. A
monster's spawn script may set up things its other programs rely on: a Skeleton Soldier's opens a guard window over
its guard motions (`SET_GUARD_FRAME` 100-120), so a brain that plays those motions blocks. Vigil's enemy brain is a
full example: Dashers and Skeleton Soldiers that circle, feint, block, punish a whiff and wait their turn
(`mods/moonmod.vigil/main.lua`, *Enemies that fight like it*).

```lua
game.scripts.override({id = "native.monster.run"}, function(ctx)
  if ctx.program_no == 100 and ctx.model == 3 then
    game.monsters.call({entity = ctx.entity, native = "SET_ROTATION", args = {(ctx.frame * 4) % 360}})
    return {handled = true}                       -- this model now only spins
  end
  return game.scripts.call({id = "native.monster.run"})
end)
```

### Chronicle event natives (`events.natives` / `events.call`)

`game.events.natives()` lists the town (`editloop3.cpp`) and dungeon (`btsysscript.cpp`) event-script natives that are
safe outside a running event: the getters and checks, and the game, map, work and event flag setters (78). Each entry
has a `mode` of `"town"` or `"dungeon"`. `game.events.call{native, args?}` runs one in its own mode, with arguments as for
`monsters.call`. Examples: `GET_FLOOR_LEVEL`, `CHECK_EVENT_FLG`, `SSET_GAME_FLAG`, `GET_CHARA_POS`, `GET_BGM_NO`.
Requires `game.write`.

```lua
local floor = game.events.call({native = "GET_FLOOR_LEVEL", args = {{out = "int"}}}).out[1]
```

### Chronicle game text (`text.get` / `text.set` / `text.clear`)

Messages are keyed as in the language files (dc1tk `lang-export`, upstream `docs/LOCALIZATION.md`): the message file
key, a dot and the message id, for example `dun.message.old_data.dungeon.0`. `game.text.set{key, text}` replaces a
message (up to 4096 bytes, in the language files' notation, `{insert1}`, `{cyan}` ...), over the language file's text,
for as long as the mod is loaded. It applies when the message file next loads, which for most messages is the next
scene. `game.text.clear{key}` takes it back. `game.text.get{key}` gives the text and its `source`: `mod:<id>`,
`language file`, or `disc` (then `text` is null). Two mods cannot set the same message. Requires `content.register`.

```lua
game.text.set({key = "dun.message.old_data.dungeon.0", text = "{icon-jar}\"{insert1}\" found!"})
```

### Chronicle retail sound and music (`audio.se_play`, `audio.bgm_play`, `audio.bgm_stop`, `audio.music_set`)

- `game.audio.se_play{se, volume?}` plays one of the game's own sound effects by its table number (0-4095; `volume` 0-127,
  default the table's).
- `game.audio.bgm_play{set, track?}` loads music set `set` (0-255) and plays track `track` (default 0).
- `game.audio.bgm_stop()` stops the music.
- `game.audio.music_set{sequence, path, gain?, loop?, loop_start?, loop_end?}` plays a package recording (WAV, FLAC or OGG
  under `resources/audio/`) in place of a game music sequence. `sequence` is the sequence name the soundtrack option uses
  (`DC_AUDIO_TRACE=1` prints them). It works whichever soundtrack is chosen and takes effect the next time that sequence
  starts. `audio.music_clear{sequence}` takes it back, and unloading the mod takes back all of its music. Two mods
  cannot replace the same sequence.

```lua
game.audio.music_set({sequence = "e01a_a", path = "resources/audio/norune.ogg", loop_start = 4.0})
```

### Chronicle override reload and notices

About once a second, the game checks every override file it was given. When one has been rewritten on disk (a new
dc1tk build, an edit), the game picks it up: it logs `moonmod: reloaded override <path>`, shows "Mod file reloaded"
on screen, and reads the new bytes the next time it loads that path (for a floor, the next floor). A replacement the game
refuses when it loads (too big for its kind or its buffer) is shown on screen once, as "Mod file not used: <path>", as
well as logged. dc1tk `mod-pack --install <save>` writes the package into `<save>/mods` and turns it on in
`<save>/moonmod/profile.json` (backup `profile.json.before-<id>`). A new override file, or a changed `main.lua`, needs
the game restarted.

### Procedural floor layout (`dungeons.set_layout`)

Retail Chronicle builds every floor on a 20 x 20 grid and places at most 6 rooms (3-4 cells wide) in its top-left 16 x 16 corner. The Chronicle PC port enlarges the grid to 96 x 96 (`DNG_GRID`) and the room table to 160 (`DNG_ROOM_MAX`). Chronicle Two builds procedural floors on a 30 x 30 grid (`DNG_GRID = 30`) and enlarges its room table from 8 to 64 (`DNG_ROOM_MAX = 64`). Without a mod setting, floors still use the retail room count, area, and sizes.

```lua
local layout = assert(game.dungeons.set_layout({rooms = 24, area = 26, room_min = 3, room_max = 5}))
-- every floor built after this call uses the layout
assert(game.dungeons.set_layout({})) -- back to the native layout
```

`rooms` (2-64) is required unless resetting with `{}`; `area` (8-46 in Chronicle, default 46; 8-30 in Chronicle Two, default 30) is the side of the corner rooms are placed in; `room_min`/`room_max` (Chronicle 3-6, Chronicle Two 2-6; default 3-4) bound each room's side; Chronicle needs 3 because it puts a room's door on the middle cell of a wall and a 2-cell wall would put it on a corner, which has no door piece, and `area` must exceed `room_max`. In Chronicle Two, `room_min`/`room_max` also filter the floor builder's preset room table (`CreateRandomRoom`). The layout is global, stays until changed (unloading the mod does not reset it) and is not saved; a floor already built keeps its layout.

### The same floor again (`dungeons.set_seed`, Chronicle)

Every Chronicle floor is built from a seed, and a floor built from the same seed (with the same layout requests) comes out the same, cell for cell, with the same chests and monsters. `game.dungeon.generated` reports the seed a floor was built from, and `dungeons.set_seed` builds the next new floor from a seed you kept:

```lua
moonmod.on("game.dungeon.generating", function(e)
  local kept = game.save.get("floors") or {}
  local seed = not e.back_floor and kept[e.dungeon_id .. ":" .. e.floor_id]
  if seed then game.dungeons.set_seed({seed = seed}) end
end)
moonmod.on("game.dungeon.generated", function(e)
  if e.back_floor then return end
  local kept = game.save.get("floors") or {}
  kept[e.dungeon_id .. ":" .. e.floor_id] = e.floor_seed
  game.save.set("floors", kept)
end)
```

`seed` is an integer from 0 to 2147483647 (the floors the game picks itself use 0-21474); `{}` drops a seed not used yet. The seed is used **once**, by the next floor built for the first time, and then cleared. A back floor follows its floor, not the seed. A floor that can't be crossed is still built again from another seed, so keep the `floor_seed` that `game.dungeon.generated` reports rather than the one you asked for. The result is `{seed, previous}`, each a number or `"random"`. `world.get().floor_seed` reads the current floor's seed. `game.save` is per mod, not per save slot: key the floors by `game.save.slot_id()` as Vigil does.

`game.dungeon.generated` fires once a floor is built, after any rebuilds, with `dungeon_id`, `floor_id`, `back_floor`, `floor_seed` and `room_count`.

`game.dungeon.resumed` fires instead of `generating`/`generated` when the floor is not built at all: with connected worlds (quick passage), walking back into a dungeon through its town's door onto the floor the party left there goes back to that floor as it was, its monsters, chests and event flags with it. It carries `dungeon_id` and `floor_id`. Treat it as "the party is on this floor again", not as a new floor.

With connected worlds, a town whose door into its dungeon is known (Norune's cave door; Matataki's forest path is known too, but Wise Owl Forest's walk-in can't be run unseen yet, so it is built on the first visit) also builds that dungeon's first floor unseen as the town loads, so the cave shows through the door before the first visit. That build sends `game.dungeon.generating` and `game.dungeon.generated` with `prebuild = true` while the party is still in town (no save is written for it); walking in then sends `game.dungeon.resumed`. A mod that reacts to a floor being entered should wait for the party to be there (`game.world.location_changed` with `context = "dungeon"`, or `game.dungeon.resumed`). Rules that decide how the build goes (`dungeons.set_quick_passage`, `dungeons.set_floor_select`) must be set by `game.scene.will_enter`, which comes before the town is made. If the floor's opening script would start another scene, the floor is not prebuilt.

### Chests that stay opened (`dungeons.set_opened_chests`, `dungeons.chests_get`, Chronicle)

A floor built again from its seed puts its chests down in the same order, so a chest's **number** names it from visit to visit. `game.chest.opened` reports the number when the player opens one, and `dungeons.set_opened_chests` opens those chests (lid up, empty, gone from the mini map, no Gilda) as the floor is built again:

```lua
moonmod.on("game.chest.opened", function(e)
  if not e.chest then return end -- a mod changed a loot table
  local kept = game.save.get("chests") or {}
  local k = e.dungeon_id .. ":" .. e.floor_id .. (e.back_floor and ":back" or "")
  kept[k] = kept[k] or {}
  table.insert(kept[k], e.chest)
  game.save.set("chests", kept)
end)
moonmod.on("game.dungeon.generating", function(e)
  if e.back_floor then return end
  local kept, k = game.save.get("chests") or {}, e.dungeon_id .. ":" .. e.floor_id
  -- ... game.dungeons.set_seed({seed = ...}) as above, then:
  game.dungeons.set_opened_chests({chests = kept[k], back_chests = kept[k .. ":back"]})
end)
```

`chests` is for the floor and `back_chests` for its back floor, which is built straight after it; each is a list of chest numbers 0-63, and each is used **once**, by the next build of that floor. `{}` drops lists not used yet. It only makes sense with `set_seed`: on a floor from another seed the numbers are other chests. The result is `{chests, back_chests}`, the counts held. Mimics are never opened this way.

`game.chest.opened` fires once per chest the player opens, with `dungeon_id`, `floor_id`, `back_floor`, `chest`, `item_id` and `large`. It also fires with the `dungeons.loot_override` result when a mod changes a loot table; that payload has no `chest`.

`dungeons.chests_get()` lists the chests on the player's floor: `{back_floor, chests = {{chest, large, opened, item_id, x, z}, ...}}`, mimics left out. It fails outside a dungeon floor.

The floor's map (item 233) and magic crystal (234) only work on the visit they're found on; Vigil leaves their chests to fill again.

### Zones joined by locked gates (`dungeons.set_zones`, `dungeons.zones_get`, Chronicle)

A floor built while zones are on is a chain of 2-4 **zones** on one map, joined by **zone gates**: you walk from one zone into the next with no load. Each zone is built in its own square of the grid (a snake: east, south, then west), its rooms joined only to each other; one corridor joins it to the zone before, and that corridor's doorway into the zone is a locked gate. The stair down stands in the first zone and the stair up in the last. A monster standing in the zone before a gate carries its key (a small chest there holds it when no monster does), and the gate opens when the player reaches it holding the key, which is used up.

```lua
-- floors built from now on: two zones of five rooms; the gate into zone 1 (the second) already opened
game.dungeons.set_zones({zones = {{rooms = 5}, {rooms = 5}}, open = {1}})
game.dungeons.set_zones({}) -- floors as the game builds them
```

- `zones`: 2-30 zones of 2-12 rooms each (the first needs 2), 159 rooms in all. Zones are numbered from 0; gate `n` leads into zone `n`. The zones' squares (each the build area, 16 cells by default) snake two wide down the grid, so eight zones of a 16-cell area take 32 x 64 cells; a request of more than eight snakes five wide (24 zones take 80 x 80). Zones whose squares would not fit (a large `set_layout` area) are left off.
- `open`: gates to build open (a list of 1 to zones - 1), for a floor built again from its seed whose gates the player already opened. Keep them the way Vigil does: `game.dungeon.zone_gate_opened` reports each.
- `source_floor` (per zone, 0-99): the zone takes that floor's monsters, atla and chest items, so one map can hold several of the game's floors (a **region**; Vigil makes all of Divine Beast Cave one map this way). The monster models of all the zones' floors are loaded together (up to 48 kinds, in the whole model arena) and each stands only in its own floor's zone; each zone lays its floor's atla, and picking one up credits its own floor. The HUD's floor number follows the zone the player stands in. Without it a zone takes the floor being built.
- `source_dungeon` (per zone, 0-6): the zone is built from that dungeon's parts and has its monsters (the
  Gauntlet's **Confluence**: a Divine Beast Cave floor whose second zone is Wise Owl Forest and third the Shipwreck).
  That dungeon's main floor pack (`dun/mpd_pack/dNNmain_a.mpd`) loads beside the floor's own when the map loads, or
  when the floor is built if the zones were asked for in `game.dungeon.generating`; its ground textures get a texture
  block of their own. The zone's corridors, room walls, doors, corners, floors, dividing walls, pillars and its shrine's
  spring are that dungeon's (drawn, collided with, and their torches and water too); stairs, gates and the character
  doors stay the floor's own, so its keys and events line up. Each zone is lit as its dungeon is: the lights, ambient,
  fog and background ease (over about a second) to the bank dungeon's while the player stands in its zone, and back to
  the floor's own elsewhere (`dungeons.lighting_set` on such a floor becomes the floor's own lighting). With
  `source_dungeon`, a zone's `source_floor` is a floor of that dungeon, whose monsters the zone takes (else the floor
  of the same number, or that dungeon's last); such a zone lays none of the floor's atla, and its chests and HUD floor
  number are the floor's own. Up to six other dungeons on one map.
- `quiet` (per zone, true or false): none of the floor's monsters start in the zone, and it adds none to the floor's
  count (a boss's hall, a rest stop); a mod's own spawns still can. Its gate out takes no key carrier from it: make that
  gate smoke (opened by `dungeons.zone_gate_open`) or open.
- `heal` (per zone): the zone's spring heals as a spring does even with `shrine_heal = false` (a rest stop).
- `arena` (per zone): the zone's rooms are built 6x6, room for a boss and its cast; `dungeons.room_seal` in one shuts
  it for the fight.
- `vaults = false`: no way down to the floor's back side (a map whose zones are a whole run, which a Vault and back
  would populate again).
- `exit_floor` (0-99): where the floor's exit gate leads instead of the next floor (past a region's last floor). It also ends the floor the way the game's own `_SET_FLOOR_LEVEL` would.
- `shrines = true`: each zone has a **shrine**, a healing spring against the top wall of its shrine room (the first zone's first room, a later zone's gate room), and no room gets a random spring. No monster starts within two and a half cells of the spot in front of a shrine, so a party that rests or arrives there isn't set upon at once (monsters can still walk in).
- `shrine_heal = false`: those springs refill the water gauge but leave HP alone (a mod whose rest heals, for a price), and Cross pressed in one no longer shows the game's "Recover health and thirst here". The default heals as the game's springs do.
- `sanctuary = true` (with `shrines`): no monster steps within 400 units (two and a half cells) of the spot in front of any shrine's spring, the circle no monster starts in. One that steps in, chasing or knocked back, is put at the circle's edge. Off by default.
- `descent` (0-120 units): **height steps**. Each zone lies `descent` below the zone its gate is entered from, and the corridor outside each gate slopes down to it: the nearest straight corridor cell to the gate (along the corridor, round up to three corners, within four cells) becomes a ramp, and the cells between it and the gate lie at the lower height. A gate with no straight corridor near it leaves its zone level with the one before. Walls, chests, atla, trap circles, the spring water, events, the people standing on the floor and the monsters the game sets down all follow the floor; collision, the camera's and the player's both, follows the slopes. The Moon Sea's floors stay level (its water lies at one height). Off (0) by default: the floor is built and drawn exactly as before.
- `smoke` (a list of 1 to zones - 1): those gates are **smoke gates**: a wall no key opens, drawn as a curtain of pale smoke rising in front of its door, and no monster carries a key for it. Walking up to one is `game.dungeon.smoke_touched`; what lies beyond is the mod's to offer (Vigil puts a story floor of the game's own there and enters it with `dungeons.enter_floor`). A smoke gate listed in `open` is built open, like any other; don't list one in both.
- The request stays until changed or `{}`; one mod at a time owns it, and unloading that mod clears it. It applies to the main floor only, never the back floor, and never to a rest floor.
- A layout that can't be split cleanly (a room that lands outside its zone, a corridor that gets round a gate) is built again from another seed, as an uncrossable floor is; a floor that still won't split after the rebuilds is left whole.
- The keys are the shortcut keys from the Silver Key down (passing over the one the shortcut doors skip), so a floor with zones has fewer shortcut doors. A locked zone gate shows its key's colour. A map of more than eight zones runs out of keys: from the eighth gate on, the six come round again (a key opens the nearest gate it fits, which is the one before the next that takes it).

`dungeons.zones_get()` returns `{zones, rooms, open, smoke, shrines, shrine_heal, source_floors, source_dungeons, quiet, heal, arena, vaults, exit_floor, floor_zones, current, zone_floors, zone_dungeons, gates = {{zone, x, y, key, key_item, locked, smoke, carrier}, ...}, shrines = {{zone, x, y}, ...}}` (a smoke gate has no `key`): the request, the zones of the floor the player is on (0 on a floor without zones), the zone the player stands in, each gate with the entity id of the monster carrying its key (while it lives and the gate is locked), and each zone's shrine spring (on the floor the player is on; the request's `shrines` is true or false), and `zone_floors`, the floor each zone of that floor stands for (its `source_floor`, or the floor itself), and
`zone_dungeons`, the dungeon each zone is built from. The cell to stand on in front of a spring is `y + 1`. With height steps on that floor it also has `heights` (each zone's floor height, from zone 0) and `ramps = {{x, y, from, to}, ...}` (each ramp's cell and the heights it runs between: `from` the zone outside the gate, `to` the one inside), and the request's `descent`.

A zone's key is never handed out twice: a floor built again while the player still holds the key (or it lies on the floor) gives no monster or chest another.

Events:

- `game.dungeon.zone_entered`: `zone`, `previous` (-1 when the player arrives on the floor, including where `enter_floor` or `set_arrival` puts them: the zone the floor first stood them in isn't reported), `zones`, `floor_id` (the floor the zone stands for; walking into it counts as reaching that floor, for the entrance's floor list).
- `game.dungeon.zone_gate_opened`: `zone` (the zone behind it), `key`, `x`, `y`.
- `game.dungeon.zone_gate_locked`: the player reached a locked gate without its key; once while they stay there.

- `game.dungeon.shrine_reached`: `zone`, `x`, `y` (the spring's cell): the player stands in front of a shrine; once until they walk away (and not when a warp puts them there).
- `game.dungeon.smoke_touched`: `zone`, `x`, `y`: the player walked up to a smoke gate (within about 130 units of its cell); once until they walk away.
- `game.dungeon.event_ended` (to the `dungeons.play_event` caller only): `program`, `dungeon_id`, `floor_id`, `frame`: the scene it started is over; the floor has no monsters until it is built again.
- `game.dungeon.story_exit` (to the `dungeons.set_story_exits` owner only): `left` (Leave was chosen), `dungeon_id`, `floor_id`: the player answered a fixed floor's gate.

`DC_ZONE_VISIT=frames` (a test hook) puts the player just outside the first gate that many frames into a zoned floor.

### Shrines, warps and the way out (`dungeons.set_exits`, `dungeons.warp`, `dungeons.enter_floor`, Chronicle)

```lua
game.dungeons.set_exits({town = "shrines"})                 -- town only by your own way (a shrine's panel)
game.dungeons.warp({x = 12, y = 6})                          -- this floor's cell 12, 6, at once
game.dungeons.enter_floor({floor_id = 2, x = 19, y = 8})     -- floor 3 built again from the start; arrive at 19, 8
game.world.transition({id = "chronicle:location:norune-village"}) -- and leave for town (already there)
```

- `dungeons.set_exits({town = "shrines" | "any"})`: with `"shrines"` the Escape menu's way out is refused (with the menu's own refusal sound) and the exit gate's continue/leave window doesn't open: the gate leads on to the next floor. Mods hear `game.dungeon.town_refused` `{via = "menu" | "gate"}`. One mod at a time; `"any"`, `{}` or unloading the mod gives the native exits back. A knockout still sends the party to town.
- `game.dungeon.defeated`: `dungeon_id`, `floor_id`, `gilda` (the wallet before the knockout: the game then halves it, so the event reaches mods after the halving). The whole party was knocked out in a dungeon and the game is about to fade to town (with the game's debug mode on, which `--jump` turns on, the party gets up again instead and nothing is sent). A mod that wants the party somewhere else can call `dungeons.enter_floor` with `dungeon_id` once the town is up. The party stands where it fell until the fade ends, so `player.get().position` still reads that spot.
- `dungeons.warp({x, y, teleport?})` moves the player to a cell of the floor they are on (one with something to stand on), facing north (toward a room's top wall, where a spring stands), with the camera behind. With `teleport = true` the screen comes up from black as the escape item's light plays around the player, who (with the monsters) waits about a second.
- `dungeons.drop_gilda({x, y, z, amount})` puts a pile of gold (1 to 9,999,999 Gilda) on the floor the player is on, at a world position (160 units to a cell; `y` from `player.get().position`), the way a monster that stole Gilda drops it. It shows on the corner map, and the player takes it by walking within about half a cell of it (the game's own drops must be walked onto). The pile is gone when the floor is built again, so drop it again then; a floor holds 32 dropped things at once.
- `dungeons.set_arrival({zone})` or `({x, y})` (either with `teleport = true`), from `game.dungeon.generating`: the next main floor built starts the player in front of that zone's shrine (inside its gate on a floor without shrines), or on that cell. A region entered by one of its later floors (from the entrance's floor list) uses it to start at that floor's zone. `{}` takes it back.
- `dungeons.enter_floor({floor_id, x?, y?, dungeon_id?})` builds floor `floor_id` of the dungeon the player is in (or, from a town, of `dungeon_id`, its native number) again from the start and enters it, with no menu; the floor the player is on is allowed, which is how a rest brings the monsters back. With `x, y` the player arrives on that cell once play starts on the floor. With `teleport = true` as well (and on `set_arrival`), the floor's opening script still runs and builds the floor, but its stairs walk-in plays out unseen in a single frame; the player is put on the cell behind a black screen, and the screen comes up as the escape item's light plays around them. A story scene the floor opens with still plays. The floor is built as any other: keep it with `dungeons.set_seed`, `set_opened_chests` and `set_zones({open})` from `game.dungeon.generating`, as Vigil does, and it comes back as it was left.

### The map screen, kept maps and waypoints (`ui.map_open`, `dungeons.map_snapshot`, Chronicle)

```lua
local snap = game.dungeons.map_snapshot()            -- {seed, width = 96, cells, seen}: what the player has seen
game.dungeons.set_seen({seed = snap.seed, cells = snap.cells})   -- next visit (same seed): seen again
game.dungeons.set_waypoint({x = 30, y = 21})         -- the red flag on the mini map; {} takes it away
game.ui.map_open({id = "map", title = "Divine Beast Cave", subtitle = "Floors 1-7",
  marks = {{x = 30, y = 20, kind = "shrine_lit", label = "Floor 3", pick = true}},
  waypoints = true})                                 -- the floor the player is on
game.ui.map_open({id = "map", title = "Divine Beast Cave", cells = snap.cells, hint = "Travel",
  marks = marks, pages = true})                      -- a kept map, in a town too
```

- `ui.map_open({id, title, subtitle?, cells?, marks?, cursor?, waypoints?, hint?, pages?})` opens the map screen. In a
  dungeon it pauses play as the choice panel does; in a town (while walking) it holds the town's controls. Without
  `cells` it is the floor the player is on (dungeon only), showing the cells they have seen (all of them with the
  floor's map item), the player, and the marks; with `cells` from `dungeons.map_snapshot` it is that kept map,
  anywhere. Rooms are blocks, roads lines between the cells they join. A mark is `{x, y, kind?, label?, pick?}` with
  kind `shrine` (not lit), `shrine_lit`, `waypoint`, `gate`, `stair` or `mark`; up to 64. A `shrine` or `gate` mark
  stays hidden until its cell has been seen. The cursor starts at `cursor`, else on the player, else the middle of the
  map; the pad or left stick moves it, L1/R1 step between `pick` marks, Cross on one sends `ui.map_choice` `{id, x, y,
  mark}` (mark numbered from 1, as listed) and closes, Triangle (with `waypoints`) puts or takes away the one waypoint
  under the cursor (`ui.map_waypoint` `{id, x, y, set}`; on the live map the mini map's flag moves at once), L2/R2
  (with `pages`) send `ui.map_page` `{id, way = -1 | 1}`, and Circle, Select or Start close it (`ui.map_closed`).
  Opening again while the mod's own map is up replaces it in place, which is how a page turns. One mod's map at a
  time; `ui.map_close()` takes it away, and unloading the mod does too.
- `dungeons.map_snapshot()` returns the floor the player is on as far as they have seen it: `{seed, width, cells,
  seen}`, `cells` a short text (each cell a letter, runs counted) to keep in a mod's save. Unseen cells are left out.
- `dungeons.set_seen({seed, cells})` counts a kept map's cells as seen again on the floor the player is on, when that
  floor was built from `seed` (`{applied = false}` otherwise). Call it from `game.dungeon.generated`.
- `dungeons.set_waypoint({x, y})` puts the waypoint flag on the mini map for the floor the player is on (held at the
  mini map's edge while it lies outside the part shown); `{}` takes it away. A floor built from another seed doesn't
  show it.
- On a map too big for the corner (a region of several floors) the mini map shows the part around the player, at a
  readable size, scrolling as they walk, in a framed box.

### A node sky in play (`ui.sky_open`, Chronicle)

```lua
game.ui.sky_open({id = "sky", title = "VIGIL SKY", hint = "{dpad} Move  {cross} Level up  {circle} Back",
  sky = {groups = groups, nodes = nodes, top = {"Level 3", "Gilda 1200", "Embers 2"}}})
moonmod.on("ui.sky_selected", function(e)        -- {id, entry, action = "buy" | "toggle" | "rank_down" | "rank_up"}
  if e.action == "buy" then buy(e.entry) game.ui.sky_open({id = "sky", title = "VIGIL SKY", sky = page()}) end
end)
```

- `ui.sky_open({id, title, hint?, sky})` (`game.write`) opens a node sky over the dungeon and pauses it, as the map
  screen does. `sky` is what `title.mode_set` takes as its `sky` (groups, nodes, links, states, Keystones, the top
  lines), read and drawn the same way; `id` is 1-64 bytes, `title` 1-32 and `hint` up to 160. The pad or left stick
  moves between nodes, L2/R2 jump between constellations and Triangle shows the whole sky. Cross sends
  `ui.sky_selected` with action `buy`, Square `toggle`, L1 `rank_down` and R1 `rank_up`. Circle, Select or Start close
  it (`ui.sky_closed` `{id}`). The engine changes nothing itself: the mod answers by opening the page again with the
  new states, which keeps the cursor on the node it was on. It opens only during dungeon play, and one mod's page at a
  time; `ui.sky_close()` takes it away, and unloading the mod does too.

### Room-scaled encounter and chest population (`dungeons.set_population`)

```lua
local population = assert(game.dungeons.set_population({
  monsters_per_room = {min = 1.5, max = 3.0},
  chests_per_room = {min = 0.75, max = 1.5}
}))
assert(game.dungeons.set_population({})) -- restore native population targets
```

Chronicle rolls a target ratio for each generated floor, multiplies it by the realized room count, applies the active additive monster/chest bonus once, rounds up, and takes the larger of that result and the correspondingly modified native target. The native monster targets remain 15 for regular floors and 8 for back floors; the native chest target remains a random 4–7 before existing modifiers; a region (`dungeons.set_zones` with `source_floor`) gets that target once per zone, as each zone is a floor. Monster placement is capped by its native slot array. The PC port now provides 160 physical box slots, with 16 reserved for mimics/special boxes and regular chest targets capped at 144; the shared event table has 768 slots (a whole dungeon on one map holds every floor's chests). Retail array sizes remain unchanged. Dense maps may still reach these audited capacities before the configured upper ratio. Requests are owned by the calling mod and are removed when it unloads.

A floor built in zones (`dungeons.set_zones`) belongs to the mod that zoned it: the room density does not apply to it (its own zones set its rooms, and a region map would otherwise fill every monster slot). Its zones' rooms and each source floor's own monsters and chests stand as the zoning mod asked. A mod can tell such a floor by `dungeons.zones_get().floor_zones` above 0.

### Enemy Variety survival chance (Chronicle)

```lua
local setting = assert(game.dungeons.set_enemy_survival({chance_percent = 25}))
assert(game.dungeons.set_enemy_survival({})) -- remove this mod's setting
```

On a live eligible ordinary enemy's first lethal hit, Chronicle makes one chance roll. Success leaves it at 30% of maximum HP and applies the native stop status for 70 simulation steps; the lethal hit is converted back to a nonlethal hit result. Enemies carrying a drop/key, with 3000 or more max HP, or on a boss floor are excluded. A failed roll is remembered for that enemy life. The request is mod-owned and cleared on unload.

### Exit gate behaviour (Chronicle)

Using the gate key on a floor's exit shows the native continue/leave window. Two replacements exist in the Chronicle patch but are switched off: a "seamless" mode (it never built a room and pushed the player straight onto the next floor) and a walk-through exit room built from map pieces (unfinished). `game.dungeons.set_exit_room({enabled = true})` turns the exit room on for floors built afterwards, for testing only.

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

`player.get()` returns the active character id plus current and maximum HP and water. Chronicle also returns `character_id` (the native party slot) and the equipped `weapon` object when present (`id`, `item_no`, `slot`, `attack`, `endurance`, `speed`, `durability` and `durability_max`; a hit wears `(1.5 - endurance / 100)` times the swing's weight, up to 3 for a charged attack). During an active dungeon it also returns the active player's native world `position` (`x`, `y`, `z`) in both games. In a Chronicle dungeon it also returns `heading`, the way the player faces in radians (0 looks along +z, as `sin(heading)`, `cos(heading)` on x and z). `player.set({hp = integer, character = optional_id})` sets current HP exactly through the native HP update path; `player.set({max_hp = integer, character = optional_id}) changes Chronicle's maximum HP from 1 through 999 and clamps current and pending HP down if needed; player.set({water = integer, character = optional_id}) sets Chronicle's current water gauge within its native range and clears any pending gauge interpolation. Each call sets exactly one field. Attempts to set max_water, multiple fields together, or unknown fields are rejected. Chronicle Two does not support max_hp or water. This call can target a benched character without switching the active character. `player.heal` and `player.damage` accept integer amounts from 1 through 32767 and use the game's native health state, which clamps at maximum and zero HP. The optional `character` accepts `"active"` or a playable character id: Chronicle supports Toan, Xiao, Goro, Ruby, Ungaga, Osmond and the registered playable characters in the party (`characters.register_playable`); ChronicleTwo supports Max, Monica, and the ridepod. These calls can update a benched character without switching the active character. Omitting `character` targets the active character, including ChronicleTwo's transformed monster when its live gauge is available. `player.damage` changes HP only; it does not synthesize damage formulas or knockback. `player.status_add/remove` use native ailment/status rules: Chronicle accepts `freeze`, `stamina`, `poison`, `curse`, and `goo` for the active character; ChronicleTwo accepts `poison`, `slow`, `curse`, `stop`, `power`, `stone`, and `dry` for Max or Monica. ChronicleTwo requires `duration_frames` from 1 through 32767 when adding a timed status (`slow`, `stop`, `power`, or `stone`) and rejects a duration for untimed statuses. Native interactions can reject a status (for example, ChronicleTwo power wards off poison and slow). Unsupported player mutations remain unsupported.

### Player tuning (Chronicle)

```lua
assert(game.player.tuning_set({run_speed = 1.24, attack_anim_speed = 1.18, invincible_bonus_frames = 24,
                               recoil_scale = 0.5, gauge_refill = 1.0, thirst_drain = 0.64, durability_wear = 0.64,
                               map_reveal = true, monster_reveal = true}))
assert(game.player.invincible({frames = 90}))   -- one-shot, in a dungeon
assert(game.player.tuning_clear())
local supported = select(2, game.player.tuning_set({})) == nil   -- an empty table is valid: "no change"
```

`player.tuning_set` gives a mod one owner-scoped set of knobs on the dungeon player that the Lua formulas cannot
reach. Every field is optional and a field left out means the retail value for that owner; each call replaces the
owner's whole set, `player.tuning_clear` takes it back, and unloading the mod restores it. Several mods can hold
tuning at once: multipliers multiply, `invincible_bonus_frames` add (capped at 120) and the reveal flags OR, and the
combined multipliers are kept inside 0.25 to 4. The result carries the owner's `tuning` and the combined `effective`
set. Fields, all validated (a bad field rejects the whole call with `invalid_argument` and changes nothing):

| field | range | what it does in Chronicle |
|---|---|---|
| `run_speed` | 0.25 to 4 | multiplies the dungeon walk speed (1.45 per frame) and the dash speed (3.0) |
| `attack_anim_speed` | 0.25 to 4 | plays the recovery of Toan's sword swings (combo actions 0x24 to 0x28, after each swing's last hit and sound frame) at this speed; the hit frames keep their one-frame steps because the game tests them in half-frame windows, so a bigger number shortens the time to the next swing rather than the swing itself. Other characters are unchanged |
| `invincible_bonus_frames` | 0 to 120, integer | after a hit lands, the player stays invincible this many frames past the recoil |
| `recoil_scale` | 0.25 to 4 | scales the recoil (stun) frames a hit sets (160 for a heavy hit, 80 light, 8 from traps), never below 1 |
| `gauge_refill` | 0.25 to 4 | scales the action gauge's refill per frame |
| `thirst_drain` | 0.25 to 4 | scales the water gauge drain per frame; `player.thirst_get`'s `drain_per_frame` includes it |
| `durability_wear` | 0.25 to 4 | scales the weapon wear per hit, after the weapon's own halving or doubling flags |
| `map_reveal` | boolean | the floor map draws every cell as if the Map item were held (the HUD shows the Map icon too) |
| `monster_reveal` | boolean | monsters show on the map as if the Magical Crystal were held |
| `map_hidden` | boolean | no floor map or minimap at all (wins over `map_reveal`) |
| `map_window` | boolean | the minimap is always the framed square that scrolls around the player, as on a region's map, however small the floor (the Gauntlet's map) |
| `status_duration` | 0.25 to 4 | scales how long Freeze (300 frames) and Stamina (1800) last |
| `status_immune` | list of `freeze`, `stamina`, `poison`, `curse`, `goo` | the active player never takes these ailments (owners' lists combine) |
| `swap_delay` | 0 to 4 | scales the two 20-frame waits of a battle-menu character switch; 0 switches as soon as the model loads |
| `dodge_power` | 0, or 0.25 to 4 | with a value, L2 throws the player forward (the push an attack lunge uses, so walls stop it); 45-frame cooldown; owners take the strongest |
| `dodge_invincible_frames` | 0 to 60, integer | invincibility a dodge gives |
| `dodge_hop` | boolean | the dodge leaves the ground |
| `dodge_run` | 0 to 200 | with a value, L2 runs as in Souls: held past 12 ticks (0.2 s) with the stick pushed it runs at the dash speed Dran's Feather gave (3.0 a tick against the walk's 1.45, times `run_speed`), draining this much action gauge a second, with no refill while running; an empty gauge walks until L2 is let go. A tap dodges as it is let go (the `dodge` moves and `dodge_power` alike), not on the press. L2 no longer swings the camera behind, and Dran's Feather in a quick slot no longer boosts: it is a charm, and in the Feather's charm slot (`items.charm_slots_set` `feather`) halves the drain, spending a use a tick of running. Owners take the largest |
| `lightness` | boolean | a weapon's Speed no longer sets the refill (every weapon refills as Speed 60 does); it scales what a swing costs instead, 60 / Speed held between half and double: a Speed 99 weapon swings for 0.61 of the game's cost, a Speed 30 club for double. It covers the game's own combo costs and a mod's attack moves (`moves`); evades (`dodge`, `dodge_back`) cost what they say. Any owner turns it on |
| `stamina` | {character id = 0 to 600} | that character's own refill, in gauge a second, whatever the weapon: it replaces Speed / 30 and the character's factor (Toan's and Ungaga's quarter, Xiao's and Ruby's half again). A swing frame still refills nothing for Toan and Ungaga, Goo still halves it, Osmond's gun rules still apply, and `gauge_refill` still scales it. 0 leaves the game's. Owners take the largest per character |
| `extra_shots` | 0 to 2, integer | Xiao's slingshot and Ruby's orbs fire this many more, fanned 8 degrees either side (owners add, capped at 2) |
| `shots_pierce` | boolean | Ruby's orbs fly on through monsters (walls still stop them) |
| `first_person` | boolean | `false` turns off R2's first-person view in dungeons |
| `reach_scale` | 0.25 to 4 | Ungaga's spear hit points sit this much further out from him |
| `item_heal_lock` | 0 to 400, integer | an HP-healing item (from the item menu or eaten from a quick slot) is refused while a live, revealed enemy is within this distance of the active character (a floor cell is 160); a mod's own `items.use` is not. Owners take the largest |
| `lock_flick` | boolean | while locked on, a flick of the right stick (from near the middle to three quarters out) moves the lock to the nearest enemy on that side of the target, within lock range. Any owner turns it on |
| `lock_sight` | boolean | the lock drops (with the refuse sound) after half a second with a wall between the player and the target: a straight line crossing an empty cell of the random floor's map. Any owner turns it on |
| `soft_lock` | 0 to 90 degrees, integer | not locked on, a swing (a native swing, or a mod move started by the attack button) turns to the nearest live, revealed enemy within 64 units and this many degrees of the way the player faces or the stick points. Owners take the largest; 0 is off |

`player.invincible({frames = 1..600})` sets the active player's native invincibility counter to at least `frames`
during an active dungeon (it fails in town) and reports the counter and its previous value; it never shortens a
longer run and counts down with the game. All three need `game.write`. Chronicle Two has no binding for them yet.

`player.fatal_guard({charges = 0..99, character = optional id})` (Chronicle, `game.write`) sets how many fatal hits a
character survives: an animated hit that would take its HP to 0 leaves 1 HP instead, spends a charge, gives 90
invincible frames and sends `game.player.guarded` `{character, charges}` (the charges left). Without `character` it
sets all six. Charges are not saved; the result lists every character's.

### The guard, the action gauge and the player's state (Chronicle)

The game's guard (lock on, then hold R1) blocks every hit from every side for nothing, and any hit, blocked or not,
fills the action gauge to 100. Two owner-scoped rule sets change that. Each has one owner at a time: a second mod's
set fails until the first clears it or unloads. A set replaces the owner's whole rule set, and fields left out take
the defaults below. With neither set, hits play exactly as in retail.

```lua
assert(game.player.guard_rules_set({arc = 120, cost_base = 10, cost_per_damage = 1.5, chip = 0.15,
                                    break_recoil = 120, parry_frames = 6, without_lock = true}))
assert(game.player.gauge_rules_set({hit_refill = -15, first_swing_cost = 25, min_to_swing = 10, refill_delay = 36}))
```

`player.guard_rules_set` (`game.write`):

| Field | Range (default) | Does |
| --- | --- | --- |
| `arc` | 0 to 360 degrees (360) | only a hit from within this arc, centred on where the player faces, is blocked; a hit from the side or behind lands in full |
| `cost_base` | 0 to 100 (0) | gauge a blocked hit costs |
| `cost_per_damage` | 0 to 10 (0) | gauge a blocked hit costs for each point of its damage (after defence) |
| `chip` | 0 to 1 (0) | share of a blocked hit's damage that still gets through |
| `break_recoil` | integer 0 to 600 (0) | recoil frames a guard break leaves; 0 keeps the game's recoil for the hit |
| `parry_frames` | integer 0 to 60 (0) | a hit within this many frames of R1 is parried: no damage, no cost, heavy hits too, even while the guard is still rising. 0 is no parry |
| `without_lock` | boolean (false) | R1 guards with no lock-on target; R1 no longer turns the camera while unlocked |

A blocked hit that would cost more than the gauge holds **breaks the guard**: the hit lands in full, the gauge empties,
and the player is knocked down (a light hit included) for `break_recoil` frames. Outside a parry, a heavy hit is
still blocked only once the guard is fully up, as in the game. The ailment rolls (poison, curse and the rest) happen
before the guard, so a guard never stops them. `player.guard_rules_clear()` turns the caller's rules off.

`player.gauge_rules_set` (`game.write`):

| Field | Range (default) | Does |
| --- | --- | --- |
| `hit_refill` | -100 to 100 (0) | a hit that lands adds this to the gauge (negative drains) instead of filling it; a block under the game's guard leaves it alone |
| `first_swing_cost` | 0 to 100 (0) | gauge the first swing of a native combo costs (follow-ups keep their own costs) |
| `min_to_swing` | 0 to 100 (0) | gauge the first swing needs; below it the attack button does nothing |
| `swing_cost_scale` | 0 to 4 (1) | scales what the combo's later swings and a mod's attack moves cost, on top of `lightness` and gear |
| `refill_delay` | integer 0 to 600 (0) | frames the refill waits after the gauge last went down, from any spend: a swing, an evade, a block, a run, a hit |

`player.gauge_rules_clear()` turns the caller's rules off. Both clears return `{cleared, rules}`; unloading the owner
clears both.

`player.gauge_get()` (`game.read`, dungeon only) returns `{gauge, max = 100, exhausted, guard_rules, gauge_rules}`
(`exhausted` is Osmond's emptied gun; each rules table is `{on = false}` or the fields in force and their `owner`).
`player.gauge_set({gauge = 0..100})` or `player.gauge_set({add = -100..100})` (`game.write`, dungeon only, exactly
one of the two) sets the gauge or adds to it and returns `{gauge, previous}`; use it for refunds, or to charge for
something the game doesn't.

`player.state()` (`game.read`) is what the active player is doing this frame. Away from a dungeon it is
`{active = false}`; in one: `{active = true, character, hp, max_hp, action_on, action_no, motion, attacking,
guarding, guard_held, guard_frames, locked_on, target?, recoil_frames, invincible_frames, running, in_water, gauge,
exhausted}`. `guard_frames` counts from R1; `target` is the lock-on enemy's entity handle. `action_on`, `action_no`
and `motion` are the game's own numbers (`action_on` 1 is a swing, 6 the guard; see
[Dark Cloud engine notes](modding/DARK_CLOUD_NOTES.md)).

Every hit that reaches the player, with or without rules, sends **`game.player.hit`** `{character, entity?, kind,
damage, incoming, blocked, parried, broke, poised, angle, gauge}`: `kind` is `light`, `heavy`, `trap` or `other`; `damage` is
what got through (before the player damage formulas and `fatal_guard`), `incoming` the hit's damage after defence;
`angle` the degrees from the player's facing to the attacker (0 ahead, 180 behind); `gauge` the gauge after the hit;
`entity` the attacker's handle when a monster landed it; `poised` that it landed but the worn gear's `poise` took the
stagger. A parry's riposte, a guard break's effect or a death drop
hang off it.

`player.tuning_set`'s `recoil_scale` and `invincible_bonus_frames` apply to every landed hit; a guard break's
`break_recoil` replaces the scaled recoil.

Chronicle Two doesn't have these operations or the event yet.

### The companion (Chronicle)

```lua
assert(game.party.companion_set({character = "ruby", stance = "target", damage_scale = 1.0}))
assert(game.party.companion_set({}))   -- send it back
local out = game.party.companion_get() -- {character = "ruby" or nil, out = boolean}
```

`party.companion_set` (`game.write`) brings a party member out beside the player in a dungeon. The engine loads its
model and equipped weapon into arenas of their own and drives it: it follows the player, runs to and attacks the
player's lock-on target (`stance = "target"`, the default), any monster within 150 units of the player (`"aggressive"`), or
nothing (`"passive"`). It cannot be hurt and monsters never target it; each blow deals its equipped weapon's base attack
times `damage_scale` (0 to 10), with no damage formulas (Xiao, Ruby and Osmond fire a visible shot that lands on arrival), and is reported as `game.companion.hit` `{entity, character,
damage, killed, reward_exp, frame}`. It catches up at once if it falls far behind. A companion can't be the active
character: switching to it sends it back until the mod names another. Only one mod's companion is out at a time, and
unloading the mod sends it back.

`hostile = {hp = 1..9999, damage = 1..999, defense = optional 0..999, tint = optional {r, g, b}}` makes it an invader:
it hunts the player instead (stance is ignored), and may be the active character. Each swing lays a native hit on the
player in front of it (kind light, every third heavy at x1.5 and slower to come; a ranged hero's shot lands where it
arrives), so guard rules, dodge invincibility and poise take it, and `game.player.hit` reports it with no `entity`.
A player weapon hit that reaches its body (a hit that strikes monsters, dealt by no monster) takes `damage - defense`,
at least 1, and sends **`game.companion.struck`** `{character, damage, hp, max_hp, killed}`. At 0 it plays its down
motion and goes 1.5 seconds later. `tint` is the colour it is drawn in; it flashes white when hit. `companion_get`
adds `hostile` and, for an invader, `hp` and `max_hp`. The player's lock-on takes it when it's nearer than the nearest
monster (the cursor shows over it; its bar is the mod's). Between swings it circles the player on its lock-on strafe;
it guards or dashes aside from swings started close by (the dash doesn't go through walls); below a third of its life
it backs off and drinks one of two flasks, healing two fifths, which sends `game.companion.struck` with `damage`
negative (the heal) and the new `hp`. A hit while it drinks spills the flask.

### Party queries

```lua
local members = assert(game.party.list())
local active = assert(game.party.active())
local npc = assert(game.party.recruit({npc_id = 7})) -- Chronicle Two
```

These read party membership and the active character from the current save. ChronicleTwo reads the native membership mask and reports stable ids (`max`, `monica`, `ridepod`, or `monster`), the native character id, and an `active` flag; `party.list()` also reports townspeople with stable ids such as `chronicle-two:npc:7` and their joined/in-party status. Chronicle reports its joined playable roster from the native party-size field and fixed character order, plus the active member. `party.set_active({id = "toan"|"xiao"|"goro"|"ruby"|"ungaga"|"osmond"|<registered id>})` changes Chronicle's active member through its native character and weapon loading routine. It requires an active dungeon, a joined and living target, no current player action or movement lock, no scene playing (a floor's entry scene, a gate: it picks its motions by the character it began with), and compliance with the game's restricted-zone and Osmond ground rules. ChronicleTwo's `party.set_active({id = "max"|"monica"|"ridepod"})` checks the game's native quick-change state and changes the active character through the native setter; the game can reject a switch when the character is unavailable, locked, at zero HP, blocked by status, or barred by the current floor. A successful changed switch emits `game.party.active_changed` with `previous`, `active`, and `changed`. `party.recruit({npc_id = 1..32})` runs ChronicleTwo's native townsperson join and in-party routines. The game allows one townsperson companion at a time; recruiting another moves the previous one to the joined/waiting state. Re-recruiting the current companion is an idempotent no-op. Successful recruitment emits `game.party.recruited` with `id`, `npc_id`, `recruited`, `changed`, and `replaced`. Chronicle recruitment remains unsupported because its playable cast has no separate NPC companion roster.

**Playable characters past the six (Chronicle, sandbox sessions only).** A mod can add playable characters with
`characters.register_playable` (`content.register`), usually while it loads:

```lua
game.characters.register_playable({
  id = "opar", name = "Opar",                    -- API id (1-15 of a-z, 0-9, _); name 1-10 letters
  pack = "dun/mainchara/c07d.chr",               -- his character pack, a file the mod supplies (resources.override)
  portrait = "dun/mainchara/c07d_face.png",      -- optional 128 x 128 PNG for the menus' faces
  title = "Moon Sea Frog Mage",                  -- optional: what the item menu says under his picture (default: name)
  fights_as = "toan",                            -- optional (default toan): whose action, motions, weapons, voice
  hp = 90, defense = 21,                         -- optional: start values (default: those of fights_as)
})                                               -- returns {id, character_id, count}
```

Each takes the next native index from 6 (`character_id`) and keeps it while the game runs; there is room for ten
(sixteen characters in all). Registering the same id again updates him in place; another mod's id is refused. A party
holds the first `party_size` characters and every registered one who has joined. A sandbox party that reaches his
index holds him by its size: `session.start({party_size = 7})` takes the first registered, 8 the first two. A story
party takes him with `party.join({character = id})` (`game.write`), whatever its size (Opar joining with Xiao, at
two), and `party.leave({character = id})` lets him go (not while he leads, nor from a party that holds him by its size);
both return `{character, joined, changed, party_count}`. A new game has nobody joined. The save itself never holds
one: it keeps its six (its layout is unchanged, so it loads without the mod), and writing a save image counts a party
of six with Toan active. What is his goes beside it, in the save's folder as `characters.json` (written with the save
and the autosave, read when it loads, deleted with it): for each registered character by id, whether he joined, led
the party, his life, water, defence, ailments, skill, weapons and equipped slot. One the file names that no mod
registers now is kept as it was; one it does not name starts afresh, out of the party. A weapon given to a character
with nothing in hand (one just joined) goes in his hand (`weapons.give` returns `equipped = true`), as the story's own
joins equip a first weapon. They appear in `party.list`, `characters.list` and `characters.get` (with `name`, `fights_as`, and
`in_party` false outside a party that reaches them), `player.*`, `party.set_active`, `player.fatal_guard`,
`dungeons.set_character_blocks`, the combat events' `attacker` and `game.item_picked_up`'s `character` (their index).
A registered character fights as `fights_as`: that character's weapons (`weapons.give` with `character`), action,
voice, motions, weapon models and menu poses. His pack is built on that character's skeleton (up to 16 MiB); his
portrait is drawn on the switch wheel, the Allies ring and the weapon page, or the face of `fights_as` without one.
The companion (`party.companion_set`) takes them too: his own model, moving and fighting as `fights_as`, and with
`shot = {cell = 0..15, size = 0.3..4}` from range, throwing that `basefx01` cell (any companion can take one). The
Gauntlet registers Opar this way (its **Opar** setting, or his star in Norune Eternal's Allies).

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

Chronicle registers up to 128 enemy variants through its native monster-model resolver. A variant can inherit the selected template's model, AI script, effects, family, and drop rules while overriding `hp`, `defense`, `reward_exp`, and `reward_money`, or it can select a package-owned model binding through `models.register`. Chronicle's monster table has no per-definition display string, so `name` is returned by the API while the in-game lock-on label still uses the template's localized name.

`characters.spawn({character = id, position = {x, y, z}, rotation = optional {x, y, z}})` and its `entities.spawn` alias use the native actor initializer and inherited AI. Data-only variants require their exact template to be loaded on the current floor. A character using a registered custom model can load that model into a free slot of the floor's model table (48 models; the native game had 9); spawning fails with a reason when the floor loader is not ready or all slots are occupied. The registering mod owns the definition and is the only mod allowed to spawn it. Nearby mod-owned enemies enter Chronicle's active native state immediately, and the view budget (4 awake enemies by default) prioritizes mod-owned enemies before filling remaining slots with vanilla actors. The response includes a generation-checked `entity_handle`, slot, position, and supported stats. Resolve it with `entities.get`; it reports `dead` after death and `expired` after native slot reuse or dungeon cleanup. `entities.despawn({id = entity_handle})` removes a live owned non-mimic enemy without kill credit or drops.

A data-only variant whose template the floor didn't load (a boss on an ordinary floor) has the template loaded into a
free slot of the floor's model table when it spawns. The retail bosses (Dran 78, Master Utan 79, Ice Queen 80, King's
Curse 81/82, Minotaur Joe 83, Dark Genie 84) run scripts written for their own arenas, centred on the world origin;
`arena_origin = {x, y, z}` tells the engine where that arena's centre lies on this floor, and every position the
boss's script reads or sets is moved by it. `grounded = true` (with `arena_origin`) also keeps every height the script
asks for at the floor (Dran stays on the ground).

`arena_slot = 0..15` (with `arena_origin`) makes the spawn a member of a boss's cast: the monsters its arena places
beside it, whose scripts name each other by the slots they hold there (the boss in 0). Spawn the boss with
`arena_slot = 0` and each helper with its native slot and the same `arena_origin`; the engine maps those slot numbers
(monster positions, links, references, script IDs) onto the slots the cast holds on this floor, and the shared script
values (`SET_GLOBAL_INT`) are the cast's own bank, apart from the floor's other monsters, which use the same numbers for their own ends, and start cleared for the cast's first member, as the arena's floor load leaves them. A boss (`arena_slot = 0`) always opens a new cast, even at an origin where another cast still stands (a second boss rising where the first fell, while it fades out): the helpers spawned after it at that origin join it, and the two casts never fade or name each other. A missing member leaves its
part of the fight out. The native casts: Ice Queen 80 with Ice Barrier 101, Ice Arrow 76, Ice Prison 102, Ice Meteor
103, Ice Aura 92 and three Ice Tornadoes 104 (slots 1-8); King's Curse coffin 81 (the part that dies) with the Curse
82 in slot 1; Minotaur Joe 83 with three Wine Kegs 91; the pink Dark Genie 84 with his hands 85 and 86, light 87, wind
88, beam 89 and 90 and shockwave 93 (slots 1-7; his eye opens to blows only once both hands are broken, and he waits on
his beam, slot 5, so leave those in); the dark Genie 106 with
shades 105 (slots 1-2), pillars 107 (3-4, each raising the shade below it), shockwaves 108 (5-6) and beam 109 and 110
(7-8). The Genie's casts load more textures than a floor's share of the PS2's 4 MB; Chronicle's texture count, which
is bookkeeping only, goes to four times that.

The story scenes a boss's fight asks for don't run away from its arena. When a boss in an arena (any `arena_origin`
spawn) asks for its defeat scene with its life gone, it fades out over a second and a half in its place and dies;
other scene requests are skipped. When a cast's slot-0 member is defeated, by its scene request or its own script,
the rest of its cast fades out with it.

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

`models.register` requires the registering mod to own the `.chr` override. Chronicle's pack must provide `info.cfg`; Chronicle Two's pack must provide `<model>.cfg`. A custom `script` additionally requires an owned `.stb` override; when omitted, the template's native script is inherited. On Chronicle Two a custom `script` cannot load, because the game runs monster scripts as Luau modules; inherit the template's script there. `models.unregister({id = local_model_id})` removes the logical model binding when no registered character or existing embedded-motion definition refers to it; it leaves the separately registered resource overrides in place for `resources.unoverride` or owner cleanup. The character's native table row points at these asset stems. Chronicle can load a custom model after floor entry when a slot is free in its 24-model floor table; Chronicle Two loads it through the native monster manager. Chronicle bounds package `.chr` and `.stb` reads to 2 MiB after sector padding; Chronicle Two uses a 3 MiB limit. `models.replace({monster_id, model})` changes the `.chr` model stem on a native monster-table row, and `models.remove({monster_id})` restores the value captured before that mod's first replacement. Replacement requires the calling mod to own the matching `resources.override` path (`dun/monstor/<model>.chr` in Chronicle or `dungeon/monster/<model>.chr` in Chronicle Two), and another mod cannot replace or remove its binding. A row whose model is loaded on the active dungeon floor cannot be changed until that floor is left. Unloading the owning mod restores its native model binding. `resources.unoverride` refuses to remove a `.chr` path that an active native model replacement still uses, and it protects `.chr` and custom `.stb` paths held by a registered model because native model definitions persist until process exit. The API checks ownership and size but does not validate the model format or rig compatibility. Existing embedded-motion playback remains at its verified baseline; it is not expanded by model binding removal.

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

`world.get()` reports native area/map identifiers, active game context, the native adventure `day`, and the native world-time cycle. Chronicle identifies dungeon scenes from the active game mode, then reports the native dungeon and floor even when the dungeon belongs to an overworld region. During an active dungeon, Chronicle also reports `room_count`, `floor_seed`, `walking` (playing on the floor, not loading it or in a menu), `back_floor`, and the active additive `room_bonus_percent`, `monster_bonus_percent`, and `chest_bonus_percent`. `day` is Chronicle's saved adventure-day counter and is available to mods that need stable daily rotations. `dungeon_id` and `floor_id` are `nil` outside an active dungeon; `sub_map_id` is available in ChronicleTwo. These are the games' native identifiers, so mods should keep them as data and resolve stable mod content ids through the corresponding registration API.

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

`locations.register` requires `content.register` and owned `.map` and `.cfg` overrides under the native map directory (`map/<a>/<abc>/<def>/<name>`, Chronicle Two's `dc2::world::MapPath(map_name)`). A package may also own `.mpk` and `.ipk` packs. When either pack is omitted, `texture_source_map` must name an existing native map; the loader reads the missing pack from that map. The same option maps embedded texture provenance to that native map's converted texture catalog. It does not convert or add new model or texture assets. Owned `.efp`, `.sky`, and `.stb` files are also accepted. Every provided asset must be non-empty and no larger than 3 MiB after sector padding. A registration made before the native map catalog loads stays `pending` and materializes when the catalog becomes available; otherwise it appends a `MAP_TYPE_INTERIOR` row after all native rows. Native indices are unchanged. The framework caps registrations at 32 and reserves 64 appended native map rows. Map names cannot collide with native entries or another registered mod location. `locations.register` and `locations.list/get` report `texture_source_map` as a map stem or `null`. They also return a stable `chronicle-two:location:<package-id>:<local-id>`, `source = "mod_package"`, native map number/type, owner, and required/optional resource paths. The native catalog and pinned assets cannot be unregistered safely during the process, so a registered location and its overrides remain for that game session; restart the game to remove or replace it.

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

### Chronicle title modes and sandbox sessions (`title.*`, `session.*`)

A mod can add its own game mode to the title menu. `game.title.mode_register` adds a row under NEW GAME, LOAD and
OPTION (two mod modes at most). Choosing the row replaces the logo and menu with the mode's screen, which the mod
drives: a heading, a subtitle, up to six info lines, a hint and up to seven entries.

```lua
assert(game.title.mode_register({
  id = "gauntlet", label = "Dark Genie's Gauntlet",          -- the title-menu row (1-32 bytes)
  title = "DARK GENIE'S GAUNTLET",                          -- the screen's heading (1-40 bytes)
  subtitle = "Five biomes. No saves.", hint = "",           -- 0-64 bytes; an empty hint shows Cross/Circle
  lines = {"Moon Shards 12"},                               -- up to 6 lines of 0-64 bytes
  entries = {{id = "start", label = "Start Run"},           -- up to 7; label 1-64 bytes
             {id = "records", label = "Records", enabled = false}},
  root = true,                                              -- Circle on a root page goes back to the title menu
}))
moonmod.on("game.title.selected", function(e)               -- e.mode, e.entry ("back" for Circle), e.index
  if e.entry == "records" then game.title.mode_set({id = "gauntlet", lines = {"..."}, entries = {...}, root = false}) end
end)
```

- `title.mode_register` (`content.register`) registers or updates a mode. `title.mode_set` (`game.write`) changes
  any page field: `label`, `title`, `subtitle`, `hint`, `lines`, `entries`, `cursor` (0-based) or `root`.
  A new `entries` list resets the cursor unless `cursor` is given. `title.mode_remove` (`content.register`) removes
  the mode. Only the owner can change or remove it, and unloading the mod removes it. Entry ids follow the action-id
  rules; `back` is reserved. Text may use the game font's glyph tokens such as `{cross}`.
- `game.title.opened` is sent to the owner when the player opens the mode's screen. `game.title.selected` is sent
  when the player confirms an enabled entry, or presses Circle (`entry = "back"`, `closed = true` on a root page).
  Up and Down move the cursor without an event. On a sub-page the mod answers Circle, usually with `title.mode_set`.
  If it leaves three presses in a row unanswered, Circle returns to the title menu anyway. The screen takes the
  keyboard and controller; the mouse does not click its entries yet.
- **A sky page.** `title.mode_set({id, sky = {...}})` swaps the entry list for a panning node sky (the Gauntlet's
  Norune Eternal). A page with `entries` and no `sky` goes back to a list. The sky is checked whole and refused with
  `invalid_argument` if any part is wrong:
  - `groups`: 1-16 constellations, each `{id, name (1-32 bytes), x, y, colour = {r, g, b}?}`.
  - `nodes`: 1-200, each `{id, group, x, y, label (1-32 bytes)}` plus optional `rank` (12 bytes), `icon` (a HUD icon:
    `heart`, `sword`, `flask`, `drop`, `crystal`, `map`, `shield`, or a status badge `freeze`, `stamina`, `poison`,
    `curse`, `goo`; or a registered png path, 240 bytes), `title` (64), `tag` (32), `text` (160), `needs` (96),
    `cost` (48), `state` (`"locked"`, `"open"` or `"owned"`), `on` (false dims an owned node), `keystone` (a larger,
    crowned ring) and `links` (up to 4 node ids, drawn as dotted lines; send no field rather than an empty table, which
    reaches the engine as an object). Coordinates are sky units within ±8000; 640 units span the screen.
  - `texts`: up to 24 captions `{text, x, y, colour?}`; `top`: up to 3 lines of 64 bytes at the top right.

  The D-pad moves to the nearest node in that direction (a node linked to the cursor's comes first), L2 and R2 jump
  to the previous and next constellation, and Triangle toggles the whole-sky map, all without an event. The mouse
  works too: the node under the hand takes the cursor, a left click buys it, a click on a button in the hint row, the
  star map or a constellation's name at the edge does what it shows, the wheel turns through the constellations and
  a right click goes back. The page spreads across a wide window. Cross, Square, L1 and R1 on a node send `game.title.selected` with `entry` = the node id and `action` =
  `"buy"`, `"toggle"`, `"rank_down"` or `"rank_up"`; Circle sends `entry = "back"` as on any sub-page. The view
  follows the cursor's constellation; the bottom plate shows the cursor node's `title`, `rank`, `tag`, `cost`, `text`
  and `needs`. A new sky keeps the cursor on the same node id and keeps the map view.
- `session.start({floor, party_size?, character?})` (`game.write`) works only while the caller's mode screen is
  open on the title. A queued start goes ahead on the next frame. Leaving the screen, or a start that cannot happen,
  drops it. `floor` is the stable id of a floor registered with `dungeons.register`. The screen fades out,
  the save data is reset as for a new game (the configuration is kept), and the player starts on that floor. The
  first `party_size` characters (1 to 6 plus the registered playable characters, default 1) have joined; past six they
  are the registered ones in order (below). Each of them is equipped with their first weapon (a new game gives only
  Toan one; a registered character gets the first weapon of the character he fights as). `character` (default `"toan"`) is the active one and must be within the party. The
  session belongs to no save slot: `save.slot_id` returns nil, and native saving never happens, because the session
  never reaches a town or the save screen.
- A session ends when it leaves its dungeons. The dungeon exit, Escape Powder and a game over all redirect to the
  title, never to a town. `session.finish()` (`game.write`, the owner, from its dungeon) also ends it. Loading a
  real save, or a developer-menu jump, ends it in place. `game.session.started` and `game.session.ended` are published
  to every mod as they happen, with `owner`, `mode` and, on the end, `reason`: `defeat`, `left_dungeon`, `ended`,
  `loaded_save` or `developer_jump`. The save data is reset again on the way to the title. The title then opens on the
  mode's screen, and `game.title.opened` follows.
- `session.get()` returns `{kind = "title" | "story" | "sandbox", owner, mode}`.
- Other mods keep running during a session. A gameplay mod that should not touch another mod's game mode sits it out
  itself: it checks `session.get` at load, and on `game.session.started` it sets its formulas to x1, clears its
  tuning, bars and sheet, and ignores events until `game.session.ended`. RPG, Ascension and Dungeon+ do this.
- `world.transition` to another registered floor, in the same dungeon or another one, keeps the session going, and
  the session's area follows the dungeon it enters.

The bundled Dark Genie's Gauntlet (`mods/moonmod.roguelike`) is built on these. Chronicle Two has no title modes yet.

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

Quest definitions and frame. Chronicle weapon pickups also include the exact receiving character and slot. Objectives without event remain manually advanced.

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
  - `game.render.bar_register({id = "boss_hp", label = "Boss", current = 150, max = 200})`: Registers or updates an owner-scoped HUD progress bar overlay. It accepts only these fields: `label` is 1-24 overlay characters, `max` is positive, `current` is in `[0, max]`, and an optional boolean `boss`. A boss bar is drawn wide along the bottom of the screen in a dark red, its label over it, instead of in the top-left HUD. Bars share the limit of four with diagnostic overlays and HUD text layers.
  - `game.render.bar_remove({id = "boss_hp"})`: Removes an owned HUD progress bar overlay.
  - `game.render.target_bar_set({on = true})` (Chronicle only): Draws the locked target's HP as a bar half again as wide as the game's thin gauge under its name, framed, with a pale trail behind the red that holds what the last blows took for half a second and then drains away. `{on = false}` gives the game's gauge back. The game's setting that hides the target gauge hides this bar too.
  - `game.render.target_meter_set({entity, fill = 0..1, color = {r, g, b}?, seconds?})` (Chronicle only): A thin meter under that monster's target bar, shown while it is the locked target and the bar is on (a poise or stagger meter). `color` defaults to gold; a full meter flashes white. It goes after `seconds` (0 to 600) without another set, or stays with 0, the default. `{entity}` alone takes it away. A monster that has gone fails with "that monster is gone", and the meter goes with the monster when another takes its slot.

- **Weapon Mastery & Progression (`game.weapons.*`)**:
  - `game.weapons.abs_get({id = weapon_id, character = optional, slot = optional})`: Reads current ABS (experience points), current level, and ABS required for next level.
  - `game.weapons.abs_add({id = weapon_id, amount = 50, character = optional, slot = optional})`: Adds ABS to a weapon, auto-leveling when reaching the requirement and emitting `game.weapon.abs_gained`. A negative `amount` (down to -32767) takes unspent ABS away, never below 0 and never a level; the result's `added` is then negative and no `abs_gained` is sent. `slot` needs `character`.
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
  - `game.shops.register_item({shop_no = 0..17 or id = "chronicle:shop:N", item_id = item_id_or_number})`: Adds an item or weapon to a shop's stock (a shop holds at most 20 goods). Its price is the item's own (a registered weapon starts at its template's); set it with `set_price`, which reaches registered weapons too.
  - `game.shops.remove_item({shop_no = 0..17 or id = "chronicle:shop:N", item_id = item_id_or_number})`: Removes an item from a shop's inventory.
  - `game.shops.set_items({shop_no = 0..17, items = [item_no, ...]})`: (*Chronicle only*) Replaces the native fixed-size list with up to 20 goods. Repeated IDs are preserved because native shops use duplicate entries for stock weighting. A shorter list retains its `-1` terminator; a full list uses every slot and is read by the game's bounded 20-entry loop. The list is owned by the calling mod and restores to its original contents when that mod unloads; another mod cannot claim the same shop while it is overridden.
  - `game.shops.set_price({item_id = item_id_or_number, buy_price = optional, sell_price = optional})`: Overrides the native global buy and/or sell price for an item or weapon. Chronicle restores the original price when the owning mod unloads.

Chronicle's `register_item` claims no shop: the goods it adds are kept apart and put back at the end of the list after any mod's `set_items` (while there is room), so a mod rotating a shop's stock and a mod adding to it both work. `remove_item` of the caller's own addition takes it back; otherwise `remove_item` and `set_items` share one owner claim per native shop. `set_price` uses one owner claim per native item price. Conflicting mods receive an error instead of overwriting another owner's data; unloading the owner restores the saved native value.

- **Dungeon Floor Rules & Loot (`game.dungeons.*`)**:
  - `game.dungeons.floor_rules_get({dungeon = dungeon_id, floor = floor_num})`: Queries floor restriction rules (limited zones, character locks, red/white seals, back-floor keys).
  - `game.dungeons.floor_rules_set({dungeon = dungeon_id, floor = floor_num, rules = {...}})`: Overrides active or target floor rules.
  - `game.dungeons.set_shortcuts({count = 0..7})` (Chronicle): new floors get up to `count` shortcut doors (the most
    any mod asks for). The generator finds dead-end rooms (one doorway) and joins each to a room at least three joins
    away, leaving by another side; the new doorway is locked with a gate and its key waits in a small chest in the dead
    end, so the shortcut opens from inside, once the player has come the long way. Keys are items 216-222 (Bone Key to
    Silver Key), one per door, skipping the floor's own gate key so no key fits two locks. Only a floor with more
    than one shortcut colours its doors, and its first door stays native; the others are lit (softly) in their key's
    colour. Walking up to a door with its key uses the key
    and opens the doorway (`game.dungeon.door_opened` `{key, x, y}`); without it, `game.dungeon.door_locked` `{key, x,
    y}` is sent once while the player stays there. Floors with shortcuts skip the native random locked room, which
    uses the same keys. `game.dungeons.shortcuts_get()` lists the floor's doors `{x, y, key, key_item, locked}`.
    `open = {216, ...}` (key items, up to 7) builds those doors already open on a floor built again from its seed (a
    kept floor, with `dungeons.set_seed`). The door's key chest is still placed, so the floor's chest numbers hold. Keep
    each `game.dungeon.door_opened` key, as Vigil does. Owners' lists are joined, and an owner's list goes when it unloads.
    `illusory = 0..3` adds that many more doorways of the same kind, each drawn as the room's own plain wall on that
    side, with no key and no chest (the 7 doors are shared, keyed doors first). The attack button pressed within reach
    of one, facing it, opens it: `game.dungeon.wall_opened` `{wall, x, y}`, where `wall` is its number on the floor
    (0 up). `open_walls = {0, ...}` builds those numbers open on a floor built again from its seed. `shortcuts_get`
    lists an illusory wall as `{x, y, illusory = true, locked}`.
    Test hook: the environment variable `DC_SHORTCUT_VISIT` puts the player in the first door's dead end ten seconds
    into a floor.
  - `game.dungeons.floor_redirect({dungeon_id, floor_id, to_floor_id})` (Chronicle): an exit gate that would lead to
    `floor_id` leads to `to_floor_id` instead; both must be floors added by `dungeons.register` in that dungeon. Leaving
    out `to_floor_id` takes the redirect back; another mod's redirect on the same floor is refused; unloading the mod
    takes its redirects back. (The Gauntlet skips its fourth floor this way in runs without Endless Maze.)
  - `game.dungeons.set_modifiers({rooms, monsters, chests, chest_value})` (Chronicle): owner-scoped bonus percentages
    (0 to 300); `chests` alone may go down to -100, which leaves a floor without regular chests. Gate keys picked up
    are now reported as `game.item_picked_up` too. So is a weapon a dungeon script hands over (the clown's trapped chest).
  - `game.dungeons.chest_weapons_add({item_id = weapon, dungeon_id = -1..6 (-1 any, default), floor_from = 0, percent = 10})` (Chronicle): a chest on that dungeon, from that floor on, that rolls a weapon holds this one instead `percent` of the time, unless one is already in a chest on the floor. For registered weapons (Opar's staffs). `game.dungeons.chest_weapons_clear()` takes back the calling mod's; unloading it does too.
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
  - `game.chest.opened`: Emitted when the player opens a dungeon chest (`dungeon_id`, `floor_id`, `back_floor`, `chest`, `item_id`, `large`), or a mod changes a loot table (no `chest`).
  - `game.floor.cleared`: Emitted when a dungeon floor's exit is unlocked or rules change.

### Tier 3 APIs: Signature Game Systems

These operations bind each game's signature systems to native save or live engine state. Unsupported combinations remain listed with a reason: Chronicle has no photography, invention, ridepod, monster-badge, or Spheda system; Chronicle Two has no per-character water gauge, Atla spheres, Chronicle-style satisfaction view, or back-floor state.

- **Chronicle thirst (`game.player.thirst_*`)**:
  - `game.player.thirst_get()` reads the active character, current and maximum water, the current per-frame drain, whether drain is enabled, the empty state, and the native restriction-zone/step flags.
  - `game.player.thirst_set({water = number, character = optional})` sets the absolute gauge; `game.player.thirst_set({restore = number, character = optional})` adds to it. Both clamp to the native capacity (0 through `max_water`) and clear pending gauge interpolation. Exactly one of `water` or `restore` is required. A changed write queues `game.player.thirst_changed`.
  - `game.player.thirst_changed` carries `character`, `character_id`, `previous_water`, `water`, `max_water`, `drain_per_frame`, `drained_out`, `dried_out`, `source` (`api` or `native`), `reason`, and `frame`. The adapter polls the native gauge once per runtime pump, so native drain, drinking, and drying out are observed even when no API call made the change. Native observations are emitted on whole-unit gauge boundaries and on dry-out rather than for every fractional frame, and a transition that starts and ends between two pumps is not reported.
- **Chronicle Atla and town reconstruction (`game.georama.*`)**:
  - `game.georama.atla_list()` requires an active dungeon floor and returns the open Atla spheres with their live slot, native Atla registry index and id, registry floor/refcount, world position, and whether the contents are a Georama part or chip plus its saved obtained/placed/stock state.
  - `game.georama.atla_spawn({id, name, position?})` (`game.write`) puts a mod's own Atla sphere on the active dungeon floor: at `position` (`{x, y?, z}`), or a free spot as the floor's own spheres are put. Toan opens it as he does theirs, and the pickup says `"<name>" acquired`. It holds nothing of the game's (no Georama part or chip, no save record); `game.georama.atla_collected` tells the mods `{id, owner, name}`, and the mod keeps what it means (a story flag, say). It lasts for that floor; put it again on a later visit while the mod still wants it found. A floor holds 80 spheres (the game puts 8 at most; a map of eight floors' zones, 64), and one picked up leaves its place free; up to 16 mod spheres can be registered. Each `atla_list` entry has `floor_id`, the floor the sphere belongs to (a region's zone's floor). `atla_list` shows mod spheres with `contents = {kind = "mod", id, owner, name}`.
  - `game.georama.atla_collect({slot = 0..15})` requires an active dungeon floor and Toan as the controlled character. It uses the game's native Atla save routine (`getAtraToSaveData`), marks the live ball and matching dungeon event closed, and releases the part or chip into the same saved state as a native pickup. It does not transfer ownership of a mod-authored asset.
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

## Online play (`net.*`, `net.session` permission, Chronicle)

```lua
local ok = game.net.host({version = 1, name = "Toan"})        -- a room through the co-op relay
-- or: game.net.join({code = "AB3CD", version = 1, name = "Xiao"})
for _, e in ipairs(game.net.receive().events) do            -- each tick
  if e.kind == "connected" then moonmod.log("info", "room " .. e.code .. ", I am " .. e.peer)
  elseif e.kind == "message" then handle(e.peer, e.data) end
end
game.net.send({to = "all", data = "P 120 0 340"})           -- or to = a player's id (the host is 0)
```

One online session for the game at a time, owned by the mod that opens it; another mod's calls fail while it is open,
and it closes when its mod unloads. The relay (DC_Web's `coop/relay`, a Cloudflare Worker) passes messages between up
to four players and keeps no game state: the host's game is the world, and the mod decides what its messages mean.

- `net.host({version, name?, relay?})` opens a room; `net.join({code, version, name?, relay?})` joins one by its five
  letters and digits (any case). `version` (1-9999) is the mod's message protocol: a room takes only players on the
  same number, so change it when the messages change. `name` is at most 24 bytes. `relay` is a `wss://` or `ws://` address (a
  private server, DC_Web's `coop/relay/server.mjs`, may be plain `ws://` on a home network or a VPN; browsers need
  `wss://`); without it the game uses `DC_COOP_RELAY` from its
  environment, else the one the build names (`DC_COOP_RELAY_DEFAULT`). Both return the status at once; the result
  arrives through `net.receive`.
- `net.receive({max?})` takes waiting events, oldest first (256 by default, up to 1024): `connected` `{peer = this
  player's id, code}`, `joined` `{peer, name}`, `left` `{peer}`, `message` `{peer = the sender, data}`, and `closed`
  `{reason}`, which ends the session (the relay refused, the host left, the connection dropped). At most 4096 wait;
  past that the oldest messages go first.
- `net.send({to, data})`: `to` a player's id or `"all"` (everyone else); `data` text (UTF-8) of at most 16 KiB.
  A guest can send to another guest. The relay drops a player's frames past 240 a second.
- `net.status()` gives `{state = "idle" | "connecting" | "hosting" | "joined", available, id?, code?, peers = {{id,
  name}}, owner?}`; any mod with the permission can read it.
- `net.leave()` leaves; a host leaving ends the room for everyone.

The web build uses the browser's WebSocket, Windows WinHTTP, Linux and macOS libcurl; a build without libcurl reports
`net.*` unsupported.

## Co-op: the host's world, a guest's things, visits (`save.*`, `session.start {visit}`, Chronicle)

Co-op splits a save in two (`moonmod/coop_save.hpp`): the **world**, which is the host's (Georama in every town, the
story and map flags, the day and time, dungeon progress, and the party the story has brought), and a **player's own
things** (each character's life, defense, water, weapons and equipped weapon; the item pack, quick slots, stored
items and stock; Gilda; fishing points). Both travel as text a mod passes along.

- `save.world_export()` and `save.player_export()` give `{data}`: `"DCW1..."` and `"DCP1..."`, about 64 KB and 37 KB.
  A player's things carry MoonMod's own beside the save after them (`|DCX1` and a JSON object): the gear and the charm
  slots, as `gear.json` and `charms.json` hold them; an import without them leaves none. A visit for a new account
  (no `player`) starts with no gear or charms.
- `save.player_extra_set({data})` keeps a value of this mod's (any table or value, 32 KB as JSON at most; `{}` drops
  it) with the player's things, so it travels with them: a co-op guest's levels go to the host's save with the rest,
  and come back on the next visit, where `save.player_extra_get()` gives `{data}` (or `{}`). A visit for a new account
  starts with none. The bundled RPG and Adventurer keep a guest's levels this way during a visit, and never in the
  guest's own slots.
- `save.world_import({data})` and `save.player_import({data})` work only during this mod's own visit, so no mod can
  write another game's world or things into a player's save. Data from another build (a field sized differently) is
  refused whole, and a refused import changes nothing.
- `save.account_get({id})`, `save.account_set({id, name?, data})`, `save.account_list()`, `save.account_remove({id})`:
  the guests the host's save keeps, each a player's things under the id the guest's game made (8-64 of `a-z 0-9 -`),
  at most 64. They are written as `coop_accounts.json` in the slot's folder with every save of the slot, read with its
  load, and gone with the slot; a new game has none. Not during a visit.
- `session.start({visit = {world, player?, map}})`, from the mod's open title mode screen, starts a **visit**: a new
  game takes the host's world and the guest's things (without `player`, a new account keeps the new game's), every
  character in the host's party has a weapon, and it walks into town `map` (0-4). A visit goes wherever the world goes;
  the way to the title (or `session.finish`, from a town or a dungeon) ends it. It never writes a save slot: saving
  refuses, and autosave skips it. `session.get()`, `game.session.started` and `game.session.ended` say
  `kind = "visit"`; `game.session.failed` `{kind = "visit", reason}` comes to the mod when the data didn't fit.

- `world.avatar_set({slot, character, weapon?, x, y, z, heading, motion, tint?, name?})` shows another player (slot 1-3) on
  the dungeon floor, or walking in the town the player walks in (without a weapon there, and with the town's motions): `character` a character id, `weapon` an `item_no` (as `player.get().weapon.item_no`), the position
  and `heading` as `player.get()` reports them, `motion` its `motion`, and `tint` `{r, g, b}` (each 0-128) the ambient
  it draws in. Set it as reports come (several a second): between them the hero eases there and turns the shortest
  way, and it jumps when far away (a warp, the stairs). Each has its own model and texture arenas, loaded on the next
  dungeon frame and let go out of the dungeon (the slot is kept for the next floor). `world.avatar_clear({slot})`
  takes one away, `world.avatar_clear()` every one. `player.get()` reports the `motion` the hero plays, and in a town,
  walking, its `position`, `heading`, `motion` and `town_character` (the hero it walks as, `party.town_set_active`).
  `world.get()` in a town reports `walking` too, and on a dungeon floor `walking` is true only while the player plays there (false while the floor loads, when its `floor_id` and `floor_seed` aren't settled yet, and in a menu or a scene). `name` (24
  bytes at most) is drawn over the hero's head, in blue for a tinted one, fading out toward where monsters stop being
  drawn.

- `monsters.mirror_get()` (co-op's host) gives the floor's monsters, `{monsters = {{slot, kind, state, hp, max_hp, x,
  y, z, heading, motion}, ...}, hits}`, and what struck other players' heroes since the last call (anything that would
  strike the player: a monster's blow, its shot or spell, a trap, measured on each hero as the game measures it on the
  player), `hits = {{avatar, slot, damage, kind, flags}, ...}` (`avatar` as `world.avatar_set` numbers it, `slot` the
  monster or -1, `kind` 2 a small hit, 3 a blow, 4 a heavy blow). While heroes are on
  the floor, the host's monsters see them as players: each wakes for the nearest player and chases it.
  `monsters.puppet_set({monsters})` (a guest) makes this floor's monsters copies of those, by slot: a copy has no
  thoughts or blows of its own and stands, turns and moves as the host's does; a slot left out, or one with `hp` 0, is
  gone on the host, and a copy still up dies, its own death and drops playing out. A slot holding another kind here is
  `refused`. It returns, as `hits = {{slot, damage}, ...}`, the blows this player landed on the copies since the last
  call (any blow: a weapon's, a bomb's, a thrown item's), for the host's monsters; a copy keeps a sliver of life until
  the host's dies. `monsters.puppet_clear()` gives them their own thoughts back (leaving the floor does too).
  `monsters.mirror_hit({slot, damage})` (the host) lands another player's blow on a monster: the life goes, and a kill
  dies on the host as the host's own would.

- `dungeons.shared_events_get()` gives the system scripts this player ran since the last call that changed the floor
  without leaving it (a door or gate opened, a switch turned: an object moved or an event switched), as `{events =
  {{script, mode, ext, pos = {x, y, z}, dir = {x, y, z}}, ...}}`; one that leaves the floor or changes the character is
  never listed, nor one this game ran for another player, nor one every game runs by itself (a room cleared of its
  monsters, a monster's death). `dungeons.shared_event_run(event)` runs one here, at its
  place, once the player is free (not in a menu, a script or held still; it waits up to half a minute), the key it asks
  for taken as given. One waits at a time: another fails `busy` until it is taken.

- `world.enter_map({map_no})` walks the player into a town or one of its houses by its map number, as `world.get()`
  reports it (`map_no`, in a town or house), from walking in a town or playing on a dungeon floor. `items.owned()` lists
  what the player carries (the bag and the quick slots) as `{items = {{id, item_no, name, count}, ...}}`, names as the
  menus show them. A town imported while the player stands in it is no longer written back over by the town on screen
  when they leave it.

- `georama.town_export({town_id})` gives one town's Georama (its record and chips) as `{data}` text, and
  `georama.town_import({town_id, data, base?})` takes it. With `base` (the town as the editing game had it when its
  player opened the editor), only what they changed comes across, merged into this game's town: a plot, villager,
  chip or request they changed takes their value, the buildings they put up are added and those they took down taken
  away, and the rest stays as it is here (`merged = true`). A town open in Georama's editor or a menu is not imported over: the
  call fails with a reason starting `busy`, to be tried again. A player walking in that town is walked into it again,
  at its entrance (`reloaded = true`), so no one stands where a building just went. `world.get()` in a town reports
  `town_map` and `editing` (Georama's edit mode or its menu).

The bundled Online Co-op mod (`mods/moonmod.coop`) is built on these and `net.*`; `docs/COOP_PLAN.md` has what is
built and what comes next.

## Mods in a session and their co-op roles (`mods.*`, both games)

```lua
for _, m in ipairs(game.mods.list().mods) do print(m.id, m.version, m.coop) end   -- what this session loaded
local s = game.mods.settings_get({id = "moonmod.roguelike"})                      -- {id, values, overlaid}
game.mods.settings_overlay({id = "moonmod.roguelike", values = {companion = true}}) -- for this session only
game.mods.settings_overlay_clear({})                                              -- every mod's, or {id = ...}
```

- `mods.list()` (`game.read`) gives `{mods = {{id, name, version, author, coop}}}`: the Lua mods running now, in
  load order, a merged pack's running parts right after the pack (each with its own version and role). A mod switched
  on or off live is listed, or not, at once; one whose change waits for a restart keeps its current state.
- `coop` comes from the mod's manifest key of that name: `"required"` (the default when the key is absent) every
  player in an online room has the mod at the host's version and plays with the host's settings; `"host_only"` only
  the host needs it (a mod whose state lives in the host's save, such as Randomizer and Living Towns); `"local"` each
  player's own, never asked for and never sent (controls, the camera, autosave, the hub). Any other value refuses the
  manifest.
- `mods.settings_get({id?})` (`game.read`) gives `{id, values, overlaid}`: each declared setting's effective value
  (an overlay's, else the profile's, else the default). Without `id` it reads the caller's own; another mod's need the
  `mods.settings` permission.
- `mods.settings_overlay({id, values})` (`mods.settings`) gives a mod setting values for this session only. Each value
  is checked against its setting (type, range, choices); those refused are named in `refused`, the rest returned as
  `applied`. The values are never written to the profile, and the Mod Manager's own changes stay underneath them.
  The mod gets `settings.changed {id, value}` at the next tick for each setting whose value changed, and
  `moonmod.settings.get` returns the overlay's value at once. A mod that reads a setting only when it loads should
  also listen to `settings.changed` to follow an overlay.
- `mods.settings_overlay_clear({id?})` (`mods.settings`) drops one mod's overlay, or every mod's; each mod is told
  its own values again through `settings.changed`. Every overlay also ends by itself when `game.session.ended` or
  `game.session.failed` is published (a visit ends) and when the runtime stops or reloads its mods.

Online Co-op uses these to make every game in a room play the same mods with the host's settings: see
`docs/COOP_PLAN.md`, "The room's mods".


## Merged packs and live on/off (both games)

A **merged pack** is one mod whose script holds several mods, its *parts* (`"parts"` in `mod.json`, up to 64). The
script hands each part over with `moonmod.part.run(id, source, globals, name)` (the part's script as source, compiled
as a chunk of its own, so errors name the part's file and line) or `moonmod.part.run(id, fn)`; the engine runs the
part only when it is on, as the part's own owner: the part's id, settings (`moonmod.settings.get`), saved data (`moonmod/data/<part id>/`), events,
and everything it registers are its own, as when it was a separate mod. `moonmod.part.enabled(id)` and
`moonmod.part.list()` (`{id, enabled, running}`) read the state. Parts are records of their own in the Mod Manager
(listed under the pack), in `mods.list`, `mods.settings_get` and to other mods' `dependencies` and
`scripts.call_function`. A pack's switch turns its parts on and off with it; each part's own switch is kept apart
(the profile's `parts`, under the pack), so the pack's switch never overwrites it. While a pack is on, a part stands
in for a separate mod of the same id; when it goes off, that mod is itself again and starts at once if it is on. The memory ceiling and per-event handler limit grow with the number of parts, each
part's load has its own instruction budget, a script may be 4 MiB and `mod.json` 1 MiB.

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
Details and the MoonMod Pack's builder: [Packs and live on/off](modding/PACKS.md).
## Permissions and ownership

Permissions are declared in `mod.json` and checked by the runtime for each operation: `game.read`, `game.write`, `content.register`, and `scripts.override` cover game adapters; `debug.inspect` gates diagnostics; `storage.read` and `storage.write` cover per-mod storage. Enabling a local package enables its declared Lua permissions. A package that declares `native.extension` also needs a package-relative native library and a separate local trust confirmation before that library loads. Lua does not get direct filesystem, process, network, native code, or arbitrary memory access. `storage.*` is sandboxed to a fixed JSON file under that mod's user-data directory. `net.session` lets a mod play online through `net.*`: it talks only to the co-op relay, in text messages to the other players in its room, never to an address of its own choosing beyond a `wss://` relay. `mods.settings` lets a mod read other mods' settings and give them session-only values (`mods.*`); it never writes another mod's saved settings. Trusted native code runs in-process and is outside the Lua sandbox; see [Native SDK](NATIVE_SDK.md).

## Native extension surface

The native SDK has a C-compatible, versioned ABI v1 header, descriptor validator, package-bound dynamic loader, local trust confirmation, and host logging, supported game-adapter API calls, and event services. Trust is tied to the library SHA-256 digest and package/file metadata. Native code remains an opt-in in-process escape hatch and does not receive the Lua sandbox. See [Native SDK](NATIVE_SDK.md) for its service scope and platform verification boundary.
