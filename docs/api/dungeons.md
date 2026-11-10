# Dungeons and floors

Part of the [MoonFactory API reference](../API.md). Adding floors, shaping how floors are generated, keeping a floor
between visits, zones, shrines and warps, floor rules and loot, lighting, and each game's own dungeon systems.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Dungeon floors (`dungeons.register`, Chronicle)](#dungeon-floors-dungeonsregister-chronicle)
- [Floors with their own map pack (Chronicle)](#floors-with-their-own-map-pack-chronicle)
- [Added dungeon floors (Chronicle Two)](#added-dungeon-floors-chronicle-two)
- [Procedural floor layout (`dungeons.set_layout`)](#procedural-floor-layout-dungeonsset_layout)
- [Room-scaled encounter and chest population
  (`dungeons.set_population`)](#room-scaled-encounter-and-chest-population-dungeonsset_population)
- [Floor rules, shortcuts, modifiers and loot](#floor-rules-shortcuts-modifiers-and-loot)
- [The same floor again (`dungeons.set_seed`, Chronicle)](#the-same-floor-again-dungeonsset_seed-chronicle)
- [Chests that stay opened (`dungeons.set_opened_chests`, `dungeons.chests_get`,
  Chronicle)](#chests-that-stay-opened-dungeonsset_opened_chests-dungeonschests_get-chronicle)
- [Zones joined by locked gates (`dungeons.set_zones`, `dungeons.zones_get`,
  Chronicle)](#zones-joined-by-locked-gates-dungeonsset_zones-dungeonszones_get-chronicle)
- [Shrines, warps and the way out (`dungeons.set_exits`, `dungeons.warp`, `dungeons.enter_floor`,
  Chronicle)](#shrines-warps-and-the-way-out-dungeonsset_exits-dungeonswarp-dungeonsenter_floor-chronicle)
- [Other floor operations (Chronicle)](#other-floor-operations-chronicle)
- [Floor lighting (`dungeons.lighting_get`, `dungeons.lighting_set`,
  Chronicle)](#floor-lighting-dungeonslighting_get-dungeonslighting_set-chronicle)
- [Back floors (`dungeons.back_floor_*`, Chronicle)](#back-floors-dungeonsback_floor_-chronicle)
- [Enemy survival chance (`dungeons.set_enemy_survival`,
  Chronicle)](#enemy-survival-chance-dungeonsset_enemy_survival-chronicle)
- [Exit gate behaviour (Chronicle)](#exit-gate-behaviour-chronicle)
- [Spheda (Chronicle Two)](#spheda-chronicle-two)

## Dungeon floors (`dungeons.register`, Chronicle)

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

Chronicle's `game.dungeons.list()` returns the seven native dungeons plus mod-registered extensions.
`game.dungeons.get(id)` reads either kind by stable ID; a local suffix resolves in the calling mod's namespace first and
then against the built-in catalog. `game.dungeons.register()` and its `game.world.register_dungeon()` alias append
floors to native dungeons 0-4.

Each floor requires a local `id` and a `source_floor`: an integer selects an existing floor's enemy layout, while a
string selects an earlier floor in the same registration. Registration copies both normal and back-side native enemy
layouts into new native floor slots. An optional `enemies` array replaces that floor's roster with up to nine character
IDs registered by the same mod; an empty array (which reaches the engine as an empty object from Lua) creates an empty
encounter: no monster stands on the floor at all, nor carries its key. Mod-owned custom model resources must be
available when the floor is registered.

The game's procedural map builder supplies the existing dungeon theme, room geometry, and item rules; floor names and
stable IDs are queryable metadata while Chronicle's native floor display remains numeric. One registration can add at
most eight floors, and each target dungeon can have at most 25 floors total, matching Chronicle's fixed save and
restriction-zone tables. Gallery of Time is already at 25 floors and Demon Shaft uses a separate 100-floor path, so
neither accepts additions. Asset overrides, custom geometry, and standalone dungeon maps remain unsupported. Registered
floors remain active for the current game session.

## Floors with their own map pack (Chronicle)

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

## Added dungeon floors (Chronicle Two)

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

Registration is queued until the native dungeon scripts for the selected dungeon have loaded. Each returned floor
initially has `status = "pending"`; after the loader applies it, the floor includes its native floor number and `status
= "registered"`. An integer `source_floor` names an existing native floor; a string names an earlier local floor in this
same registration, so mods can build chained multi-floor branches. Optional `flags` accepts unique values from `exit`,
`boss`, and `sub`; `seal` accepts `none`, `monica`, or `max`.

These map to the game's native exit/boss/side-room behavior and character seal. The adapter appends each floor beside
its source, uses an available route, and reuses the source floor's room resource and texture. It accepts no resource
overrides, targets one of the seven existing Chronicle Two dungeon maps, and allows up to eight added floors per game
session. Every source needs an available adjacent route. Added floor progress is stored by the stable package floor ID
in a versioned PC-port sidecar keyed to the retail save payload fingerprint and save counter.

A native save-slot test verifies clear, visit, and kill state survives writing and loading the slot while the retail
save structure and ABI remain unchanged. The map graph still supports floor IDs 0 through 39, and mods still share the
session limit of eight additions. This slice authors connected rooms in an existing dungeon map; it does not yet author
a wholly new dungeon map, scripts, room geometry, or resource set. `game.world.register_dungeon()` remains a
compatibility alias for the same operation.

ChronicleTwo's `game.dungeons.list()` returns registered additions, and `game.dungeons.get(id)` reads one by stable id
(a local id resolves in the caller's namespace). Its floor records expose registration status, native floor numbers,
room flags, and seals, so a package can inspect whether its additions have been applied. Chronicle's calls list built-in
dungeons and appended procedural floors. A Chronicle mod can enter an appended floor by passing its stable floor ID to
`game.world.transition`; the port switches to the native dungeon and floor before the dungeon simulation starts.

These floors reuse native procedural geometry and assets selected by `source_floor`; custom room geometry and standalone
dungeon maps remain unsupported.

## Procedural floor layout (`dungeons.set_layout`)

Retail Chronicle builds every floor on a 20 x 20 grid and places at most 6 rooms (3-4 cells wide) in its top-left 16 x
16 corner. The Chronicle PC port enlarges the grid to 96 x 96 (`DNG_GRID`) and the room table to 160 (`DNG_ROOM_MAX`).
Chronicle Two builds procedural floors on a 30 x 30 grid (`DNG_GRID = 30`) and enlarges its room table from 8 to 64
(`DNG_ROOM_MAX = 64`). Without a mod setting, floors still use the retail room count, area, and sizes.

```lua
local layout = assert(game.dungeons.set_layout({rooms = 24, area = 26, room_min = 3, room_max = 5}))
-- every floor built after this call uses the layout
assert(game.dungeons.set_layout({})) -- back to the native layout
```

`rooms` (2-64) is required unless resetting with `{}`; `area` (8-46 in Chronicle, default 46; 8-30 in Chronicle Two,
default 30) is the side of the corner rooms are placed in; `room_min`/`room_max` (Chronicle 3-6, Chronicle Two 2-6;
default 3-4) bound each room's side; Chronicle needs 3 because it puts a room's door on the middle cell of a wall and a
2-cell wall would put it on a corner, which has no door piece, and `area` must exceed `room_max`. In Chronicle Two,
`room_min`/`room_max` also filter the floor builder's preset room table (`CreateRandomRoom`). The layout is global,
stays until changed (unloading the mod does not reset it) and is not saved; a floor already built keeps its layout.

## Room-scaled encounter and chest population (`dungeons.set_population`)

```lua
local population = assert(game.dungeons.set_population({
  monsters_per_room = {min = 1.5, max = 3.0},
  chests_per_room = {min = 0.75, max = 1.5}
}))
assert(game.dungeons.set_population({})) -- restore native population targets
```

Chronicle rolls a target ratio for each generated floor, multiplies it by the realized room count, applies the active
additive monster/chest bonus once, rounds up, and takes the larger of that result and the correspondingly modified
native target. The native monster targets remain 15 for regular floors and 8 for back floors; the native chest target
remains a random 4–7 before existing modifiers; a region (`dungeons.set_zones` with `source_floor`) gets that target
once per zone, as each zone is a floor. Monster placement is capped by its native slot array. The PC port now provides
160 physical box slots, with 16 reserved for mimics/special boxes and regular chest targets capped at 144; the shared
event table has 768 slots (a whole dungeon on one map holds every floor's chests).

Retail array sizes remain unchanged. Dense maps may still reach these audited capacities before the configured upper
ratio. Requests are owned by the calling mod and are removed when it unloads.

A floor built in zones (`dungeons.set_zones`) belongs to the mod that zoned it: the room density does not apply to it
(its own zones set its rooms, and a region map would otherwise fill every monster slot). Its zones' rooms and each
source floor's own monsters and chests stand as the zoning mod asked. A mod can tell such a floor by
`dungeons.zones_get().floor_zones` above 0.

## Floor rules, shortcuts, modifiers and loot

Rules a mod sets on floors and what their chests and monsters give. Both games unless an entry says Chronicle:

- `game.dungeons.floor_rules_get({dungeon = dungeon_id, floor = floor_num})`: Queries floor restriction rules (limited
  zones, character locks, red/white seals, back-floor keys).
- `game.dungeons.floor_rules_set({dungeon = dungeon_id, floor = floor_num, rules = {...}})`: Overrides active or target
  floor rules.
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
- `game.dungeons.chest_weapons_add({item_id = weapon, dungeon_id = -1..6 (-1 any, default), floor_from = 0, percent =
  10})` (Chronicle): a chest on that dungeon, from that floor on, that rolls a weapon holds this one instead `percent`
  of the time, unless one is already in a chest on the floor. For registered weapons (Opar's staffs).
  `game.dungeons.chest_weapons_clear()` takes back the calling mod's; unloading it does too.
- `game.dungeons.loot_get({dungeon = dungeon_id, floor = floor_num})`: Inspects chest loot arrays and enemy drop tables.
- `game.dungeons.loot_override({dungeon = dungeon_id, floor = floor_num, loot = {...}})`: Customizes chest contents or
  monster drop entries.

## The same floor again (`dungeons.set_seed`, Chronicle)

Every Chronicle floor is built from a seed, and a floor built from the same seed (with the same layout requests) comes
out the same, cell for cell, with the same chests and monsters. `game.dungeon.generated` reports the seed a floor was
built from, and `dungeons.set_seed` builds the next new floor from a seed you kept:

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

`seed` is an integer from 0 to 2147483647 (the floors the game picks itself use 0-21474); `{}` drops a seed not used
yet. The seed is used **once**, by the next floor built for the first time, and then cleared. A back floor follows its
floor, not the seed. A floor that can't be crossed is still built again from another seed, so keep the `floor_seed` that
`game.dungeon.generated` reports rather than the one you asked for. The result is `{seed, previous}`, each a number or
`"random"`. `world.get().floor_seed` reads the current floor's seed. `game.save` is per mod, not per save slot: key the
floors by `game.save.slot_id()` as Vigil does.

`game.dungeon.generated` fires once a floor is built, after any rebuilds, with `dungeon_id`, `floor_id`, `back_floor`,
`floor_seed` and `room_count`.

`game.dungeon.resumed` fires instead of `generating`/`generated` when the floor is not built at all: with connected
worlds (quick passage), walking back into a dungeon through its town's door onto the floor the party left there goes
back to that floor as it was, its monsters, chests and event flags with it. It carries `dungeon_id` and `floor_id`.
Treat it as "the party is on this floor again", not as a new floor.

With connected worlds, a town whose door into its dungeon is known (Norune's cave door; Matataki's forest path is known
too, but Wise Owl Forest's walk-in can't be run unseen yet, so it is built on the first visit) also builds that
dungeon's first floor unseen as the town loads, so the cave shows through the door before the first visit. That build
sends `game.dungeon.generating` and `game.dungeon.generated` with `prebuild = true` while the party is still in town (no
save is written for it); walking in then sends `game.dungeon.resumed`.

A mod that reacts to a floor being entered should wait for the party to be there (`game.world.location_changed` with
`context = "dungeon"`, or `game.dungeon.resumed`). Rules that decide how the build goes (`dungeons.set_quick_passage`,
`dungeons.set_floor_select`) must be set by `game.scene.will_enter`, which comes before the town is made. If the floor's
opening script would start another scene, the floor is not prebuilt.

## Chests that stay opened (`dungeons.set_opened_chests`, `dungeons.chests_get`, Chronicle)

A floor built again from its seed puts its chests down in the same order, so a chest's **number** names it from visit to
visit. `game.chest.opened` reports the number when the player opens one, and `dungeons.set_opened_chests` opens those
chests (lid up, empty, gone from the mini map, no Gilda) as the floor is built again:

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

`chests` is for the floor and `back_chests` for its back floor, which is built straight after it; each is a list of
chest numbers 0-63, and each is used **once**, by the next build of that floor. `{}` drops lists not used yet. It only
makes sense with `set_seed`: on a floor from another seed the numbers are other chests. The result is `{chests,
back_chests}`, the counts held. Mimics are never opened this way.

`game.chest.opened` fires once per chest the player opens, with `dungeon_id`, `floor_id`, `back_floor`, `chest`,
`item_id` and `large`. It also fires with the `dungeons.loot_override` result when a mod changes a loot table; that
payload has no `chest`.

`dungeons.chests_get()` lists the chests on the player's floor: `{back_floor, chests = {{chest, large, opened, item_id,
x, z}, ...}}`, mimics left out. It fails outside a dungeon floor.

The floor's map (item 233) and magic crystal (234) only work on the visit they're found on; Vigil leaves their chests to
fill again.

## Zones joined by locked gates (`dungeons.set_zones`, `dungeons.zones_get`, Chronicle)

A floor built while zones are on is a chain of 2-4 **zones** on one map, joined by **zone gates**: you walk from one
zone into the next with no load. Each zone is built in its own square of the grid (a snake: east, south, then west), its
rooms joined only to each other; one corridor joins it to the zone before, and that corridor's doorway into the zone is
a locked gate. The stair down stands in the first zone and the stair up in the last. A monster standing in the zone
before a gate carries its key (a small chest there holds it when no monster does), and the gate opens when the player
reaches it holding the key, which is used up.

```lua
-- floors built from now on: two zones of five rooms; the gate into zone 1 (the second) already opened
game.dungeons.set_zones({zones = {{rooms = 5}, {rooms = 5}}, open = {1}})
game.dungeons.set_zones({}) -- floors as the game builds them
```

- `zones`: 2-30 zones of 2-12 rooms each (the first needs 2), 159 rooms in all. Zones are numbered from 0; gate `n`
  leads into zone `n`. The zones' squares (each the build area, 16 cells by default) snake two wide down the grid, so
  eight zones of a 16-cell area take 32 x 64 cells; a request of more than eight snakes five wide (24 zones take 80 x
  80). Zones whose squares would not fit (a large `set_layout` area) are left off.
- `open`: gates to build open (a list of 1 to zones - 1), for a floor built again from its seed whose gates the player
  already opened. Keep them the way Vigil does: `game.dungeon.zone_gate_opened` reports each.
- `source_floor` (per zone, 0-99): the zone takes that floor's monsters, atla and chest items, so one map can hold
  several of the game's floors (a **region**; Vigil makes all of Divine Beast Cave one map this way). The monster models
  of all the zones' floors are loaded together (up to 48 kinds, in the whole model arena) and each stands only in its
  own floor's zone; each zone lays its floor's atla, and picking one up credits its own floor. The HUD's floor number
  follows the zone the player stands in. Without it a zone takes the floor being built.
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
- `exit_floor` (0-99): where the floor's exit gate leads instead of the next floor (past a region's last floor). It also
  ends the floor the way the game's own `_SET_FLOOR_LEVEL` would.
- `shrines = true`: each zone has a **shrine**, a healing spring against the top wall of its shrine room (the first
  zone's first room, a later zone's gate room), and no room gets a random spring. No monster starts within two and a
  half cells of the spot in front of a shrine, so a party that rests or arrives there isn't set upon at once (monsters
  can still walk in).
- `shrine_heal = false`: those springs refill the water gauge but leave HP alone (a mod whose rest heals, for a price),
  and Cross pressed in one no longer shows the game's "Recover health and thirst here". The default heals as the game's
  springs do.
- `sanctuary = true` (with `shrines`): no monster steps within 400 units (two and a half cells) of the spot in front of
  any shrine's spring, the circle no monster starts in. One that steps in, chasing or knocked back, is put at the
  circle's edge. Off by default.
- `descent` (0-120 units): **height steps**. Each zone lies `descent` below the zone its gate is entered from, and the
  corridor outside each gate slopes down to it: the nearest straight corridor cell to the gate (along the corridor,
  round up to three corners, within four cells) becomes a ramp, and the cells between it and the gate lie at the lower
  height. A gate with no straight corridor near it leaves its zone level with the one before. Walls, chests, atla, trap
  circles, the spring water, events, the people standing on the floor and the monsters the game sets down all follow the
  floor; collision, the camera's and the player's both, follows the slopes. The Moon Sea's floors stay level (its water
  lies at one height). Off (0) by default: the floor is built and drawn exactly as before.
- `smoke` (a list of 1 to zones - 1): those gates are **smoke gates**: a wall no key opens, drawn as a curtain of pale
  smoke rising in front of its door, and no monster carries a key for it. Walking up to one is
  `game.dungeon.smoke_touched`; what lies beyond is the mod's to offer (Vigil puts a story floor of the game's own there
  and enters it with `dungeons.enter_floor`). A smoke gate listed in `open` is built open, like any other; don't list
  one in both.
- The request stays until changed or `{}`; one mod at a time owns it, and unloading that mod clears it. It applies to
  the main floor only, never the back floor, and never to a rest floor.
- A layout that can't be split cleanly (a room that lands outside its zone, a corridor that gets round a gate) is built
  again from another seed, as an uncrossable floor is; a floor that still won't split after the rebuilds is left whole.
- The keys are the shortcut keys from the Silver Key down (passing over the one the shortcut doors skip), so a floor
  with zones has fewer shortcut doors. A locked zone gate shows its key's colour. A map of more than eight zones runs
  out of keys: from the eighth gate on, the six come round again (a key opens the nearest gate it fits, which is the one
  before the next that takes it).

`dungeons.zones_get()` returns `{zones, rooms, open, smoke, shrines, shrine_heal, source_floors, source_dungeons, quiet,
heal, arena, vaults, exit_floor, floor_zones, current, zone_floors, zone_dungeons, gates = {{zone, x, y, key, key_item,
locked, smoke, carrier}, ...}, shrines = {{zone, x, y}, ...}}` (a smoke gate has no `key`): the request, the zones of
the floor the player is on (0 on a floor without zones), the zone the player stands in, each gate with the entity id of
the monster carrying its key (while it lives and the gate is locked), and each zone's shrine spring (on the floor the
player is on; the request's `shrines` is true or false), and `zone_floors`, the floor each zone of that floor stands for
(its `source_floor`, or the floor itself), and `zone_dungeons`, the dungeon each zone is built from.

The cell to stand on in front of a spring is `y + 1`. With height steps on that floor it also has `heights` (each zone's
floor height, from zone 0) and `ramps = {{x, y, from, to}, ...}` (each ramp's cell and the heights it runs between:
`from` the zone outside the gate, `to` the one inside), and the request's `descent`.

A zone's key is never handed out twice: a floor built again while the player still holds the key (or it lies on the
floor) gives no monster or chest another.

Events:

- `game.dungeon.zone_entered`: `zone`, `previous` (-1 when the player arrives on the floor, including where
  `enter_floor` or `set_arrival` puts them: the zone the floor first stood them in isn't reported), `zones`, `floor_id`
  (the floor the zone stands for; walking into it counts as reaching that floor, for the entrance's floor list).
- `game.dungeon.zone_gate_opened`: `zone` (the zone behind it), `key`, `x`, `y`.
- `game.dungeon.zone_gate_locked`: the player reached a locked gate without its key; once while they stay there.

- `game.dungeon.shrine_reached`: `zone`, `x`, `y` (the spring's cell): the player stands in front of a shrine; once
  until they walk away (and not when a warp puts them there).
- `game.dungeon.smoke_touched`: `zone`, `x`, `y`: the player walked up to a smoke gate (within about 130 units of its
  cell); once until they walk away.
- `game.dungeon.event_ended` (to the `dungeons.play_event` caller only): `program`, `dungeon_id`, `floor_id`, `frame`:
  the scene it started is over; the floor has no monsters until it is built again.
- `game.dungeon.story_exit` (to the `dungeons.set_story_exits` owner only): `left` (Leave was chosen), `dungeon_id`,
  `floor_id`: the player answered a fixed floor's gate.

`DC_ZONE_VISIT=frames` (a test hook) puts the player just outside the first gate that many frames into a zoned floor.

## Shrines, warps and the way out (`dungeons.set_exits`, `dungeons.warp`, `dungeons.enter_floor`, Chronicle)

```lua
game.dungeons.set_exits({town = "shrines"})                 -- town only by your own way (a shrine's panel)
game.dungeons.warp({x = 12, y = 6})                          -- this floor's cell 12, 6, at once
game.dungeons.enter_floor({floor_id = 2, x = 19, y = 8})     -- floor 3 built again from the start; arrive at 19, 8
game.world.transition({id = "chronicle:location:norune-village"}) -- and leave for town (already there)
```

- `dungeons.set_exits({town = "shrines" | "any"})`: with `"shrines"` the Escape menu's way out is refused (with the
  menu's own refusal sound) and the exit gate's continue/leave window doesn't open: the gate leads on to the next floor.
  Mods hear `game.dungeon.town_refused` `{via = "menu" | "gate"}`. One mod at a time; `"any"`, `{}` or unloading the mod
  gives the native exits back. A knockout still sends the party to town.
- `game.dungeon.defeated`: `dungeon_id`, `floor_id`, `gilda` (the wallet before the knockout: the game then halves it,
  so the event reaches mods after the halving). The whole party was knocked out in a dungeon and the game is about to
  fade to town (with the game's debug mode on, which `--jump` turns on, the party gets up again instead and nothing is
  sent). A mod that wants the party somewhere else can call `dungeons.enter_floor` with `dungeon_id` once the town is
  up. The party stands where it fell until the fade ends, so `player.get().position` still reads that spot.
- `dungeons.warp({x, y, teleport?})` moves the player to a cell of the floor they are on (one with something to stand
  on), facing north (toward a room's top wall, where a spring stands), with the camera behind. With `teleport = true`
  the screen comes up from black as the escape item's light plays around the player, who (with the monsters) waits about
  a second.
- `dungeons.drop_gilda({x, y, z, amount})` puts a pile of gold (1 to 9,999,999 Gilda) on the floor the player is on, at
  a world position (160 units to a cell; `y` from `player.get().position`), the way a monster that stole Gilda drops it.
  It shows on the corner map, and the player takes it by walking within about half a cell of it (the game's own drops
  must be walked onto). The pile is gone when the floor is built again, so drop it again then; a floor holds 32 dropped
  things at once.
- `dungeons.set_arrival({zone})` or `({x, y})` (either with `teleport = true`), from `game.dungeon.generating`: the next
  main floor built starts the player in front of that zone's shrine (inside its gate on a floor without shrines), or on
  that cell. A region entered by one of its later floors (from the entrance's floor list) uses it to start at that
  floor's zone. `{}` takes it back.
- `dungeons.enter_floor({floor_id, x?, y?, dungeon_id?})` builds floor `floor_id` of the dungeon the player is in (or,
  from a town, of `dungeon_id`, its native number) again from the start and enters it, with no menu; the floor the
  player is on is allowed, which is how a rest brings the monsters back. With `x, y` the player arrives on that cell
  once play starts on the floor. With `teleport = true` as well (and on `set_arrival`), the floor's opening script still
  runs and builds the floor, but its stairs walk-in plays out unseen in a single frame; the player is put on the cell
  behind a black screen, and the screen comes up as the escape item's light plays around them.

  A story scene the floor opens with still plays. The floor is built as any other: keep it with `dungeons.set_seed`,
  `set_opened_chests` and `set_zones({open})` from `game.dungeon.generating`, as Vigil does, and it comes back as it was
  left.

## Other floor operations (Chronicle)

Smaller floor rules and things to stand on a floor, one entry each:

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
- `dungeons.set_quick_passage({enabled})`: `{enabled = true}` goes between a town and a dungeon (either way) with no
  loading card, no title the game holds for several seconds and no fade: the last picture stays on screen while the
  other side builds (at most ten seconds) and the first picture of the other side replaces it. The town and the dungeon
  both stay loaded (each keeps its own memory and textures), and each is drawn live through the other's way through,
  from where the camera stands: the cave seen through the town's door, the town seen through a doorway in the cave wall
  behind where the party arrived.

  Walking into that doorway, facing it, goes back to the town, which is gone back to as it was left (its villagers where
  they stood, its clock running on), not loaded again; it stands the party just outside the town's door, facing out, the
  camera behind them. A place shows through only once both sides have been visited. Going from one floor of a dungeon to
  another of the same dungeon (`dungeons.enter_floor`, such as a story floor through its smoke) shows no card either:
  the floor fades out as ever, the black holds while the next floor builds, and the next floor is there once the party
  can play on it. `{enabled = false}` gives the card back. One mod at a time; unloading the mod gives it back. Returns
  `{enabled}`. Vigil turns it on for a Vigil World save.
- `dungeons.set_npc_models({models = {{dungeon_id, npc, pack, cfg, motion}, ...}})`: loads up to three character packs
  into a dungeon's free NPC slots (`npc` 1-3; slot 0 is the one its floors' parts use) whenever that dungeon's map
  loads, for `set_npc_marks` to stand. `pack` is a game path `dun/.../<stem>.chr` or `gedit/.../<stem>.chr` (a scene's
  pack draws its people textured: Divine Beast Cave's Fairy King is `dun/d01/event/e28c03c.chr`); `cfg` is the pack's
  config, `<stem>.cfg` by default (`base.cfg` for `dun/mainchara`); `motion` the loop it plays (0). It takes effect from
  the dungeon's next map load, so ask before entering. `{}` stops; one mod at a time; unloading the mod stops it.
  Returns `{models}`.
- `dungeons.set_npc_marks({marks = {{npc, x, y, facing}, ...}})`: stands the map's NPCs (a floor's own, or ones
  `set_npc_models` loaded) at cells of the floor the player is on, up to 16, each facing 0-3. They are drawn while that
  floor (its map seed) stays; a floor built again needs them asked again. Fails when the player isn't on a dungeon floor
  or the slot holds no character. `{}` takes them away; one mod at a time. Returns `{marks}`.
- `dungeons.play_event({program})`: plays program `program` of the dungeon's event script (its scenes,
  `dun/script/dNN/event.stb`, which a mod can replace with `resources.override`) on the floor the player is on, the way
  a monster's script asks for one. Fails when there is no such program, a scene is already starting, or the player is
  not free on a floor. When it is over, `game.dungeon.event_ended` `{program, dungeon_id, floor_id, frame}` goes to that
  mod only; the floor's monsters are gone after a scene, so build the floor again (`enter_floor`). Returns `{program}`.
- `dungeons.set_floor_select({enabled})`: `{enabled = false}` turns the dungeon entrance's floor menu off, so the
  entrance takes the player straight to the dungeon's first floor (a resumed floor still wins; a mod then starts the
  player where it likes, such as `dungeons.set_arrival`). `{enabled = true}` gives the menu back. One mod at a time;
  unloading the mod gives it back. Returns `{enabled}`. Vigil turns it off for a Vigil World save, whose dungeons are
  one map each.
- `dungeons.set_story_exits({title?, text?})`: on a floor of the game's own design (a fixed map, not generated),
  pressing at the gate that wants the floor's key (its `gatekey` marker) opens a panel (the title, default "LEAVE THIS
  FLOOR?", and the text) with *Leave* and *Stay*, Stay first, in place of the lock. Either way the gate stays shut: the
  mod hears `game.dungeon.story_exit` `{left, dungeon_id, floor_id}` and takes the player on itself (Vigil enters the
  next floor with `dungeons.enter_floor`). One mod at a time; `{}` takes it back, as does unloading the mod.
- `dungeons.set_backrooms({free, title?, text?, stay?, lines?})`: the back floor's stairs no longer ask for the gate
  key; walking onto them puts up a choice panel (`title`, `text`, Enter / Not now) instead of the key window, and Enter
  goes down at once. The key the stairs take is given back below. Acting at the back floor's entrance itself (the tram,
  the rope) opens the same panel at once, Proceed / Not now, and Proceed goes down with no item at all. The entrance's
  own script doesn't run then, so the engine stands the party one cell into the room from the back floor's way in (the
  script would have placed it). On the back floor, the stairs up ask "Go back up?" (Go up / Not now) instead of the key
  window, hand the stairs the key they want, and give it back above only if the party held it. The mod hears
  `game.dungeon.backroom` with `entered = false, left = true`. `game.dungeon.backroom` `{entered}` reports the answer.
  `lines` (up to two strings of 1-64 bytes) replaces the Proceed option's warning lines. With `stay`, the panel's answer
  is only reported: Proceed goes nowhere and takes no key, and the owner moves the run on itself (a rest floor's stairs,
  for one).
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

## Floor lighting (`dungeons.lighting_get`, `dungeons.lighting_set`, Chronicle)

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

## Back floors (`dungeons.back_floor_*`, Chronicle)

Chronicle's back floors. Chronicle Two has none, so these are unsupported there.

- `game.dungeons.back_floor_get()` returns whether the active dungeon floor has a native back-floor enemy layout,
  whether the party is currently on it, the active floor and gate-key item identity, whether the key is held, and
  whether a request is pending. The key is the floor's native gate key, not a fabricated back-floor key table.
- `game.dungeons.back_floor_enter()` queues the game's native back-floor transition request. It never consumes the gate
  key. The request is applied at the next native script boundary (`GAME_TASK_SCRIPT_RUN`) and is reported as `queued`
  before that point.

## Enemy survival chance (`dungeons.set_enemy_survival`, Chronicle)

```lua
local setting = assert(game.dungeons.set_enemy_survival({chance_percent = 25}))
assert(game.dungeons.set_enemy_survival({})) -- remove this mod's setting
```

On a live eligible ordinary enemy's first lethal hit, Chronicle makes one chance roll. Success leaves it at 30% of
maximum HP and applies the native stop status for 70 simulation steps; the lethal hit is converted back to a nonlethal
hit result. Enemies carrying a drop/key, with 3000 or more max HP, or on a boss floor are excluded. A failed roll is
remembered for that enemy life. The request is mod-owned and cleared on unload.

## Exit gate behaviour (Chronicle)

Using the gate key on a floor's exit shows the native continue/leave window. Two replacements exist in the Chronicle
patch but are switched off: a "seamless" mode (it never built a room and pushed the player straight onto the next floor)
and a walk-through exit room built from map pieces (unfinished). `game.dungeons.set_exit_room({enabled = true})` turns
the exit room on for floors built afterwards, for testing only.

## Spheda (Chronicle Two)

Chronicle Two's Spheda challenges. Chronicle has none, so these are unsupported there.

- `game.dungeons.spheda_get()` returns the current dungeon/floor challenge and clear flags, live session flags, par,
  club, pin/ball coordinates and colours, gauge power/state/code, and the saved clear value. The native save records
  only a clear flag, so a remaining-stroke count and medal award are not exposed.
- `game.dungeons.spheda_spawn({par = optional 1..99})` requires an already allocated Spheda session on an active dungeon
  floor. It calls the game's native course setup again, optionally overrides par, and enables the play/status/minimap
  flags so the new pin and ball are active. It cannot allocate a Spheda session when the floor event has not created
  one.
- `game.spheda.completed` is queued when the native floor-info setter first records a Spheda clear (through the clear
  value or the floor clear flag). It contains `dungeon_id`, `floor_id`, `cleared`, `clear_value`, and `frame`; stroke
  count and medal are not stored by the native save format.
