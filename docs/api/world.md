# World, locations, story scripts and game modes

Part of the [MoonFactory API reference](../API.md). Where the party is, registering and travelling to locations, town
villagers, hooks into the game's own scripts, title-menu game modes and sandbox sessions.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [World location (`world.get`)](#world-location-worldget)
- [Native locations (Chronicle)](#native-locations-chronicle)
- [Native locations (Chronicle Two)](#native-locations-chronicle-two)
- [Authored locations (Chronicle Two)](#authored-locations-chronicle-two)
- [Town villagers (`characters.register` kind = "npc", Chronicle)](#town-villagers-charactersregister-kind--npc-chronicle)
- [Scene event-program hook (`scripts.override`)](#scene-event-program-hook-scriptsoverride)
- [Other script hooks](#other-script-hooks)
- [Event natives (`events.natives`, `events.call`, Chronicle)](#event-natives-eventsnatives-eventscall-chronicle)
- [Title modes and sandbox sessions (`title.*`, `session.*`,
  Chronicle)](#title-modes-and-sandbox-sessions-title-session-chronicle)
- [Photography (Chronicle Two)](#photography-chronicle-two)

## World location (`world.get`)

```lua
local world = assert(game.world.get())
print(world.context, world.map_id, world.dungeon_id, world.floor_id)
```

`world.get()` reports native area/map identifiers, active game context, the native adventure `day`, and the native
world-time cycle. Chronicle identifies dungeon scenes from the active game mode, then reports the native dungeon and
floor even when the dungeon belongs to an overworld region. During an active dungeon, Chronicle also reports
`room_count`, `floor_seed`, `walking` (playing on the floor, not loading it or in a menu), `back_floor`, and the active
additive `room_bonus_percent`, `monster_bonus_percent`, and `chest_bonus_percent`.

`day` is Chronicle's saved adventure-day counter and is available to mods that need stable daily rotations. `dungeon_id`
and `floor_id` are `nil` outside an active dungeon; `sub_map_id` is available in ChronicleTwo. These are the games'
native identifiers, so mods should keep them as data and resolve stable mod content ids through the corresponding
registration API.

```lua
local world = assert(game.world.get())
print(world.time.fraction) -- normalized to [0, 1)

local changed = assert(game.world.set_time({fraction = 0.75}))
print(changed.time.fraction)
```

The normalized `fraction` represents the same portion of the native day/night cycle in either game. `native_time` and
`native_cycle_hours` report the game's stored units: Chronicle uses a 12-unit cycle and ChronicleTwo uses 24 hours.
Setting the fraction requires `game.write` and an active save. Chronicle updates the saved time and the live Georama
clock when the editor loop is active; other contexts use the saved value on the next world entry.

ChronicleTwo applies the native `CScene::SetTime` routine to a live town or dungeon scene and updates the save, or
stores the value for the next scene when no playable scene is active. Values must be finite and in `[0, 1)`; invalid
input leaves the saved time unchanged. This does not change the day counter.

```lua
local story = assert(game.world.story_flag_get({id = 37}))
local updated = assert(game.world.story_flag_set({id = 37, value = true}))
local counter = assert(game.world.story_value_get({id = 3}))
assert(game.world.story_value_set({id = 3, value = counter.value + 1}))
local chest = assert(game.world.map_flag_get({map_id = 18, flag_id = 4}))
assert(game.world.map_flag_set({map_id = 18, flag_id = 4, value = true}))
```

These calls read and write the native save's raw story flags, integer story counters, and per-map flag bits. Story flag
IDs are `0-8191` in Chronicle and `0-2047` in ChronicleTwo. Story value IDs are `0-31` in Chronicle (signed 32-bit
values) and `0-127` in ChronicleTwo (signed 16-bit values). Map flag IDs are `0-511` across map IDs `0-79` in Chronicle,
and `0-127` across map IDs `0-255` in ChronicleTwo. Reads require `game.read`; writes require `game.write` and an active
save. Setters return the previous value, resulting value, and whether it changed. Invalid IDs and values outside each
game's native range are rejected.

Flag numbers are game data indices, not portable names: use the compatibility API to branch by game, and avoid changing
a flag unless its meaning is known for that game version. Changed story flags, story counters, and map flags emit
`game.story_flag_changed`, `game.story_value_changed`, and `game.map_flag_changed` respectively; unchanged writes emit
no event.

## Native locations (Chronicle)

```lua
for _, location in ipairs(game.locations.list()) do
  print(location.id, location.name, location.kind, location.visited)
end

local cave = assert(game.locations.get({id = "chronicle:location:divine-beast-cave"}))
print(cave.native_map_id, cave.frame, cave.native_progress)
```

Chronicle exposes its 16 native world-map destinations through `locations.list/get`: settlements, dungeons, fields, and
Demon Shaft. Each record includes its stable `chronicle:location:<id>` identifier, native map ID, world-map frame, kind,
and visit/clear progress read from the save. `locations.get` accepts either the stable ID or local suffix. Mods can also
register a namespaced field location by reusing a compatible built-in field map:

```lua
local field = assert(game.locations.register({
  id = "moon-grove",
  name = "Moon Grove",
  source_map_id = 23 -- built-in field map; map 23 uses gedit/s13
}))
print(field.id, field.native_map_id, field.status)
```

`locations.register` requires an active save and exactly `id`, `name`, and `source_map_id`. The source must be a
built-in field whose data directory is indexed by the native reader. Chronicle reserves map IDs 70–79 and aliases the
first available, unoccupied `gedit/s60`–`gedit/s69` directory to the selected field's retail assets. This creates a new
location identity and route using a compatible copied field; it does not create new map geometry or a new native map
format.

A mod may replace individual files under its reserved directory with `game.resources.override`, such as a package-owned
`resources/mapinfo.cfg` targeted at `gedit/s60/mapinfo.cfg`. Each aliased override is limited to 8 MiB and stays pinned
for the game session because the native map loader cannot safely unregister it. Registration is limited to ten locations
total per session, subject to the reserved directories being unused. The result and `locations.list/get` include a
stable `chronicle:location:<package-id>:<local-id>`, `source = "mod_package"`, native and source map IDs, owner, and
save-backed visit state.

Chronicle can queue a transition to a built-in settlement from an active town or dungeon:

```lua
local town = assert(game.world.transition({id = "chronicle:location:norune-village"}))
if town.queued then
  print("Returning to", town.id, town.native_map_id)
end
```

`world.transition` requires `game.write`. In Chronicle it accepts a stable built-in settlement ID or local suffix, the
full stable ID of a floor registered by `game.dungeons.register`, or a registered mod location ID. Mod locations can be
entered from an active settlement, another registered location, or a dungeon; native settlement destinations can be
reached from those same contexts.

A floor transition can start from a town or dungeon and is applied after the current scene loop returns, before the
destination dungeon simulation starts. Requesting the current destination is a no-op; title/menu scenes, built-in fields
and dungeons as destinations, unregistered floor/location IDs, and a second request while a native map jump is pending
return a failure.

ChronicleTwo accepts built-in Georama towns and registered MoonFactory interior maps from active town or dungeon scenes,
and a retail headless run confirms returning from a copied interior to a native town. Compatible copied maps have passed
retail-data scene-load, render, and return checks; native formats for newly authored maps remain unverified. Custom
dungeon geometry/assets, route graphs, and mod-authored Georama settlements remain unsupported.

On a registered Chronicle mod location, `game.world.get()` returns `context = "location"`, its native map ID and stable
location ID. `area_id` is `null` when the native save has no active Georama area for that field map.

## Native locations (Chronicle Two)

```lua
for _, location in ipairs(game.locations.list()) do
  print(location.id, location.name, location.kind, location.native_map_id)
end

local map = assert(game.locations.get({id = "chronicle-two:location:d01f01"}))
print(map.map_name, map.title, map.area_id, map.selection_category)
```

ChronicleTwo reads the map catalog loaded from the game's localized `map/map*.cfg` table. Each record includes a stable
`chronicle-two:location:<map_name>` id, native map number and type, localized title, map selection category, area, sound
bank id, and optional additional path. `locations.get` accepts the stable id or the local map name. Headless smoke
injects a tiny native-format map table and exercises list/get through Lua against the game executable.

## Authored locations (Chronicle Two)

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

`locations.register` requires `content.register` and owned `.map` and `.cfg` overrides under the native map directory
(`map/<a>/<abc>/<def>/<name>`, Chronicle Two's `dc2::world::MapPath(map_name)`). A package may also own `.mpk` and
`.ipk` packs. When either pack is omitted, `texture_source_map` must name an existing native map; the loader reads the
missing pack from that map. The same option maps embedded texture provenance to that native map's converted texture
catalog. It does not convert or add new model or texture assets. Owned `.efp`, `.sky`, and `.stb` files are also
accepted. Every provided asset must be non-empty and no larger than 3 MiB after sector padding.

A registration made before the native map catalog loads stays `pending` and materializes when the catalog becomes
available; otherwise it appends a `MAP_TYPE_INTERIOR` row after all native rows. Native indices are unchanged. The
framework caps registrations at 32 and reserves 64 appended native map rows. Map names cannot collide with native
entries or another registered mod location. `locations.register` and `locations.list/get` report `texture_source_map` as
a map stem or `null`. They also return a stable `chronicle-two:location:<package-id>:<local-id>`, `source =
"mod_package"`, native map number/type, owner, and required/optional resource paths.

The native catalog and pinned assets cannot be unregistered safely during the process, so a registered location and its
overrides remain for that game session; restart the game to remove or replace it.

`world.transition({id = cave.id})` queues the native map jump from an active town or dungeon; the retail probe also
verifies a return from the copied interior to a native town. Chronicle Two's native loader remains responsible for
parsing the map files and initializing the destination. A retail-data headless run copied only the native shop `.map`
and `.cfg` files into package resources, registered the result as a new interior at map index 189, and entered it
through `CScene`. It omitted the `.mpk` and `.ipk` package files; `texture_source_map` loaded those from the donor map.
The run also rendered the modified layout and returned to a native town.

This verifies package-owned layout/config scripts with native pack reuse; it does not validate wholly authored map
formats or assets. The synthetic headless smoke checks registration, stable lookup, asset ownership/pinning, pack alias
reads, texture-source metadata, and transition guards. This API registers one interior map identity; it does not create
dungeon floor graphs, custom routes, dialogue, or model rigs.

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

`world.transition` requires `game.write` and accepts a stable location id or native map name from the loaded catalog. It
queues a built-in Georama town or registered MoonFactory interior map destination from the active town or dungeon scene;
requesting the current map is a no-op. ChronicleTwo also accepts the stable id of a registered floor after that floor
has been materialized in the native dungeon graph, but only during active gameplay in the matching native dungeon,
outside menus and event scripts. It queues the native floor transition and returns a no-op when already on that floor.
Other inactive contexts, unmaterialized floors, and floors belonging to another dungeon fail cleanly.

Chronicle implements built-in settlement and registered-floor transitions; ChronicleTwo implements built-in town,
registered interior-map, and same-dungeon registered-floor transitions. A compatible copied map has passed a retail-data
scene-load/render and return-trip smoke; authored map asset formats remain unverified.

## Town villagers (`characters.register` kind = "npc", Chronicle)

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

## Scene event-program hook (`scripts.override`)

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

Both ports call the `native.event.run` hook at the active scene event-program dispatcher. Its callback receives
`hook_id`, `game`, `program_no`, and `frame`. Returning `nil` or `{handled = false}` continues to the next mod override
and then runs the native program. Returning `{handled = true}` skips the native program and completes the event with run
status 0. Mods are tried in stable mod-ID order; callback errors are logged and fall through. An override belongs to its
registering mod, requires the `scripts.override` manifest permission, and is removed on unload. A mod may replace its
own callback or remove it with `game.scripts.override({id = "native.event.run", enabled = false})`.

Inside the override callback, `game.scripts.call({id = context.hook_id})` invokes that event's native program once and
returns its `run_status`; the runtime then returns that native result without invoking later overrides. Calling it
outside the active callback, calling another hook, or calling the native program twice is rejected. This hook covers
scene event programs only.

Chronicle also calls `native.monster.run` before a monster's script program (see [Monster AI from
Lua](combat.md#monster-ai-from-lua-monstersnatives-monsterscall-chronicle)); character, battle, effect, and other script
interpreters are not hooked. Callback registration cannot be passed through JSON-only `moonmod.api.call`.

## Other script hooks

`game.scripts.list_hooks()` returns six hook ids, each with its `kind`, `summary` and `context` fields. Two of them
run today:

| Hook | Runs | Where |
| --- | --- | --- |
| `native.event.run` | Before a scene event program starts | Both games (above) |
| `native.monster.run` | Before a monster's script program | Chronicle ([Monster AI from Lua](combat.md#monster-ai-from-lua-monstersnatives-monsterscall-chronicle)) |

The other four are reserved names: `native.dialogue.show` (a message or dialogue window opening),
`native.combat.before_hit` (before a hit applies damage), `native.loot.roll` (a chest or monster drop being rolled)
and `native.transition.before_enter` (before a map, town or floor transition). `scripts.override` accepts a callback
for them, but neither port calls them yet, so the callback never runs. To react to those moments use the events
instead: `game.enemy_hit` and damage formulas, `game.chest.opened`, and `game.scene.will_enter`.

## Event natives (`events.natives`, `events.call`, Chronicle)

`game.events.natives()` lists the town (`editloop3.cpp`) and dungeon (`btsysscript.cpp`) event-script natives that are
safe outside a running event: the getters and checks, and the game, map, work and event flag setters (78). Each entry
has a `mode` of `"town"` or `"dungeon"`. `game.events.call{native, args?}` runs one in its own mode, with arguments as for
`monsters.call`. Examples: `GET_FLOOR_LEVEL`, `CHECK_EVENT_FLG`, `SSET_GAME_FLAG`, `GET_CHARA_POS`, `GET_BGM_NO`.
Requires `game.write`.

```lua
local floor = game.events.call({native = "GET_FLOOR_LEVEL", args = {{out = "int"}}}).out[1]
```

## Title modes and sandbox sessions (`title.*`, `session.*`, Chronicle)

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

  The D-pad moves to the nearest node in that direction (a node linked to the cursor's comes first), L2 and R2 jump to
  the previous and next constellation, and Triangle toggles the whole-sky map, all without an event. The mouse works
  too: the node under the hand takes the cursor, a left click buys it, a click on a button in the hint row, the star map
  or a constellation's name at the edge does what it shows, the wheel turns through the constellations and a right click
  goes back. The page spreads across a wide window. Cross, Square, L1 and R1 on a node send `game.title.selected` with
  `entry` = the node id and `action` = `"buy"`, `"toggle"`, `"rank_down"` or `"rank_up"`; Circle sends `entry = "back"`
  as on any sub-page. The view follows the cursor's constellation; the bottom plate shows the cursor node's `title`,
  `rank`, `tag`, `cost`, `text` and `needs`. A new sky keeps the cursor on the same node id and keeps the map view.
- `session.start({floor, party_size?, character?})` (`game.write`) works only while the caller's mode screen is open on
  the title. A queued start goes ahead on the next frame. Leaving the screen, or a start that cannot happen, drops it.
  `floor` is the stable id of a floor registered with `dungeons.register`. The screen fades out, the save data is reset
  as for a new game (the configuration is kept), and the player starts on that floor. The first `party_size` characters
  (1 to 6 plus the registered playable characters, default 1) have joined; past six they are the registered ones in
  order (below). Each of them is equipped with their first weapon (a new game gives only Toan one; a registered
  character gets the first weapon of the character he fights as). `character` (default `"toan"`) is the active one and
  must be within the party. The session belongs to no save slot: `save.slot_id` returns nil, and native saving never
  happens, because the session never reaches a town or the save screen.
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

## Photography (Chronicle Two)

Max's camera, ideas and scoops. Chronicle has no photography, so these are unsupported there.

- `game.photos.ideas_list()` returns learnt idea binder slots plus carried photos with their subject, map,
  townsperson/monster ids, and new flag.
- `game.photos.idea_unlock({idea_id = 1..999})` inserts an idea into the native binder. Repeating an already-learnt idea
  is an idempotent success. The call fails when the binder has no free slot.
- `game.photos.scoops_list()` enumerates the native scoop table with each row's `scoop_id`, `info_index`, native
  `known`/`obtained` flags, whether a carried photo shows the scoop, and whether the idea binder has learnt it.
- `game.photo.taken` is emitted by the native photo callback with `subject_id`, `neta_id`, `map_no`, `npc_no`,
  `monster_no`, `kind` (`idea`, `scoop`, or `none`), `ideas`, carried photo count, and, for scoops, `scoop = {scoop_id,
  known, obtained}`.
