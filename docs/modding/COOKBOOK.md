# Cookbook

Recipes for the things the bundled mods do, each with the calls involved, a short example and the traps found while
building it. Field-by-field details are in the [API map](../API.md). Each recipe names the bundled mod code that does
it for real, so you can read a working version.

Recipes are Chronicle unless they say otherwise. The snippets use the `try` and `call` guards from
[Your first mod](FIRST_MOD.md#guard-every-game-call).

- [A game mode on the title menu](#a-game-mode-on-the-title-menu)
- [Add dungeon floors](#add-dungeon-floors)
- [Shape a floor as it is built](#shape-a-floor-as-it-is-built)
- [An open world: towns, roads and one-map dungeons](#an-open-world-towns-roads-and-one-map-dungeons)
- [A special room: the Rest floor](#a-special-room-the-rest-floor)
- [A boss in a sealed room](#a-boss-in-a-sealed-room)
- [Put a character on a floor](#put-a-character-on-a-floor)
- [Show things to the player](#show-things-to-the-player)
- [Change combat](#change-combat)
- [Weapons, shops and loot](#weapons-shops-and-loot)
- [Add a playable character](#add-a-playable-character)
- [New moves and animations](#new-moves-and-animations)
- [Change the game's text](#change-the-games-text)
- [Share the game with other mods](#share-the-game-with-other-mods)

---

## A game mode on the title menu

**What:** a row on the title menu (under NEW GAME, LOAD and OPTION) that opens your own screen, and a game that
starts fresh on a floor of your choosing, belongs to no save file and returns to your screen when it ends. This is
how Dark Genie's Gauntlet is a roguelike without touching the player's saves.

**Calls:** `title.mode_register`, `title.mode_set`, events `game.title.opened` and `game.title.selected`;
`session.start`, `session.get`, `session.finish`, events `game.session.started` and `game.session.ended`.

```lua
assert(game.title.mode_register({
  id = "trial", label = "Moon Trial", title = "MOON TRIAL", subtitle = "Three floors. No saves.",
  lines = {"Best: " .. (moonmod.storage.get("best") or 0)},
  entries = {{id = "start", label = "Start"}, {id = "records", label = "Records"}},
  root = true,
}))

moonmod.on("game.title.selected", function(e)
  if e.entry == "start" then
    -- floor: the stable id of a floor this mod registered (see "Add dungeon floors")
    local ok, err = call(game.session.start, {floor = FLOORS[1].id, party_size = 1, character = "toan"})
    if not ok then moonmod.log("warn", "could not start: " .. tostring(err and err.message)) end
  elseif e.entry == "records" then
    game.title.mode_set({id = "trial", lines = {"..."}, entries = {{id = "back", label = "Back"}}, root = false})
  end
end)

moonmod.on("game.session.ended", function(e)
  if e.owner ~= "yourname.moon-trial" then return end
  -- e.reason: defeat | left_dungeon | ended | loaded_save | developer_jump
end)
```

**Things to know**

- The session resets the save data as for a new game and drops the party onto your floor. Exit gates, Escape Powder
  and game over all lead back to your title screen, never to a town. End it yourself with `session.finish()`.
- Keep progress that outlives a run (currency, unlocks, records) in `moonmod.storage`. Keep the current run there too
  (the Gauntlet's `run` key), so a crash or a quit can be noticed at the next start-up and closed cleanly.
- A title page can be a list of up to seven entries, or a node sky (`sky = {...}`) like the Gauntlet's Norune Eternal
  unlock tree.
- Move between floors and dungeons inside a session with `world.transition({id = floor_id})`; the session follows.

**In the Gauntlet:** `main.lua` sections *Title screen pages*, *Run lifecycle* (`first_floor_setup`, `end_run`).

---

## Add dungeon floors

**What:** new floors appended to Divine Beast Cave, Wise Owl Forest, Shipwreck, Sun and Moon Temple or Moon Sea.
They use the dungeon's look and the native floor generator, and their monsters are copied from an existing floor
(`source_floor`) or listed by you.

```lua
local registered, err = call(game.dungeons.register, {
  id = "trial-cave", name = "Moon Trial: Cave", dungeon = 0, -- Divine Beast Cave
  floors = {
    {id = "rest", name = "Trial Rest", source_floor = 1, enemies = {}}, -- nothing to fight
    {id = "one", name = "Trial I", source_floor = 2},
    {id = "two", name = "Trial II", source_floor = 4},
  },
})
if not registered then
  -- The mod was reloaded in the same game run: the floors already exist, so read them back.
  registered = try(game.dungeons.get, "trial-cave")
end
-- registered.floors[n] = {id = "yourname.mod:trial-cave:one", native_floor_id = 16, ...}
```

**Things to know**

- The exit gate of a registered floor leads to the next one, as on a native floor. `dungeons.floor_redirect` sends a
  gate somewhere else, which the Gauntlet uses to skip floor IV in runs without Endless Maze.
- `enemies = {}` makes a floor with no monster on it and no key carrier. Give the gate key yourself if the floor needs
  one (see the Rest floor).
- Registration lasts for the game run, so a reload of the mod finds its floors already there. Read them back with
  `dungeons.get` instead of failing. Native floor numbers depend on registration order, so look floors up by id.
- Map events and native floor numbers go together: keep a table from `dungeon:native_floor` to your floor (the
  Gauntlet's `FLOOR_AT`), so `game.dungeon.generating` and `world.get` can tell which of your floors it is.

**In the Gauntlet:** `adopt_floors` and the registration loop under *Gauntlet floors*.

---

## Shape a floor as it is built

**What:** decide, floor by floor, how many monsters, rooms and chests there are, whether there are shortcut doors, a
Warden room, a rest layout, which character-only doors may appear, and what the back-floor stairs do.

All of these are **requests for the floors built from then on**. Set them in `game.dungeon.generating`, which fires
just before a floor is built, and set **every** one each time, including back to "off", so one floor's choice
doesn't leak into the next.

```lua
moonmod.on("game.dungeon.generating", function(e)
  local mine = MY_FLOORS[e.dungeon_id .. ":" .. e.floor_id]          -- nil on floors that aren't yours
  try(game.dungeons.set_modifiers, mine and {monsters = 25, chests = 50} or {})
  try(game.dungeons.set_shortcuts, {count = mine and 1 or 0})
  try(game.dungeons.set_weapon_drops, mine and {unique = true, rare = 40, large_chests = 22} or {})
  try(game.dungeons.set_warden_room, {enabled = mine ~= nil and mine.boss == true, lock_in = true})
  try(game.dungeons.set_rest_room, {enabled = mine ~= nil and mine.rest == true})
  if mine then try(game.dungeons.set_character_blocks, {characters = {"toan", "xiao"}}) end
end)
```

| Operation | Does |
| --- | --- |
| `dungeons.set_modifiers({rooms, monsters, chests, chest_value})` | Percent changes; `chests = -100` is none |
| `dungeons.set_layout` / `set_population` | Floor size and monster/chest density per room |
| `dungeons.set_seed({seed})` | Build the floor from a seed you kept (`game.dungeon.generated` reports each floor's `floor_seed`): the same floor every visit |
| `dungeons.set_zones({zones = {..., {rooms = 2, arena = true, quiet = true}, ...}, smoke = {n + 1}, vaults = false})` + `dungeons.room_seal` + `dungeons.zone_gate_open({zone = n + 1})` | A boss hall inside a zoned map: walking in shuts it, your boss spawns at the room's middle, and its death opens the smoke gate on (the Gauntlet's whole run on one map) |
| `dungeons.set_zones({zones = {{rooms = 5}, {rooms = 5}}, open})` | One map in 2-30 zones joined by locked gates; a monster in each zone carries the next gate's key; `dungeons.zones_get()` reports gates, carriers and the player's zone |
| `dungeons.set_zones({..., smoke = {3}})` + `game.dungeon.smoke_touched` | A smoke gate no key opens; walking up to it is your cue to offer what lies beyond (Vigil: a story floor of the game's own, by `dungeons.enter_floor`) |
| `dungeons.drop_gilda({x, y, z, amount})` | A pile of Gilda on the floor (a death drop, a reward), shown on the corner map, taken by walking up to it |
| `dungeons.set_zones({..., shrines = true})` + `game.dungeon.shrine_reached` | A healing-spring shrine in each zone, and an event when the player walks up to one (open a `ui.choice_open` panel there); `shrine_heal = false` keeps its water from healing HP |
| `dungeons.set_exits({town = "shrines"})` | No town from the Escape menu or the exit gate (the gate leads on); your mod's own way out is the only one |
| `game.dungeon.defeated` then `dungeons.enter_floor({dungeon_id, floor_id, x, y})` from town | Wake the party somewhere after a knockout (Vigil: at the last shrine) |
| `weapons.abs_add({id, character, slot, amount = -n})` | Take a weapon's unspent ABS (a death drop, a toll); it never goes below 0 |
| `dungeons.set_zones({zones = {{rooms = 5, source_floor = 0}, {rooms = 5, source_floor = 1}}, exit_floor = 2})` | A **region**: two of the game's floors on one map, each zone with its own floor's monsters, atla and chest items, the exit gate leading past both; `dungeons.set_arrival({zone = 1})` starts the player at the second floor's shrine |
| `dungeons.warp({x, y})` / `dungeons.enter_floor({floor_id, x, y})` | Move the player on this floor at once / build a floor again from the start (monsters back) and arrive at a cell; from a town add `dungeon_id` (fast travel) |
| `dungeons.map_snapshot()` / `dungeons.set_seen({seed, cells})` / `dungeons.set_waypoint({x, y})` | Keep what the player has seen of a floor, give it back on the next visit, and flag a cell on the mini map |
| `dungeons.set_opened_chests({chests, back_chests})` | With `set_seed`, open the chests the player already opened (numbers from `game.chest.opened`) as the floor is built again; `dungeons.chests_get()` lists a floor's chests |
| `dungeons.set_shortcuts({count})` | Dead-end rooms loop back through locked doors with coloured keys |
| `dungeons.set_weapon_drops({unique, rare, large_chests})` | What weapons chests hold |
| `dungeons.set_warden_room({enabled, lock_in})` | A sealed boss room behind the exit |
| `dungeons.set_rest_room({enabled})` | A two-room rest layout (spring, exit, stairs) |
| `dungeons.set_character_blocks({characters})` | Character-only doors and jumps appear only for these |
| `dungeons.set_backrooms({free, title, text, stay, lines})` | Back-floor stairs ask with a panel instead of taking the key |
| `dungeons.set_quick_passage({enabled = true})` | Town to dungeon and back with only a fade, no loading card |
| `world.set_roads({enabled = true})` + `game.town.road` | A town's gate asks the mod instead of opening the world map: answer with a `ui.choice_open({..., town = true})` panel of places, then `world.transition` or `dungeons.enter_floor` |
| `dungeons.set_floor_select({enabled = false})` | The dungeon entrance skips its floor menu and goes straight to floor 1 |
| `dungeons.set_npc_models` + `dungeons.set_npc_marks` | Stand a character (a scene's pack) at cells of a dungeon floor |
| `dungeons.play_event({program = n})` + `game.dungeon.event_ended` | Play one of the dungeon's scenes when the player asks (talk to someone) |
| `dungeons.set_story_exits({title, text})` + `game.dungeon.story_exit` | A fixed (story) floor's key gate asks "leave?" instead; you move the player on |
| `dungeons.enter_floor({floor_id, x, y, teleport = true})` | Arrive on a cell in the escape item's light, no stairs walk-in (also `set_arrival`, `warp`) |

**Things to know**

- `game.dungeon.generating` can fire after your own arrival logic has run, or for the back floor. Decide from the
  event's `dungeon_id` and `floor_id`, not from what you think is happening.
- Several of these are **one mod at a time** (`set_rest_room`, `set_warden_room`). A second mod is refused with
  "another mod already ...". Turn yours off (`{enabled = false}`) when your mode ends so others can use it.

**In the Gauntlet:** the `game.dungeon.generating` handler under *Floors*.

---

## An open world: towns, roads and one-map dungeons

**What:** walk from village to village and into every dungeon with no loading card and no world map, each dungeon
one continuous map, the story floors behind smoke you walk through. This is Vigil World (`mods/moonmod.vigil`,
setting *Vigil World preview*); `VIGIL_PLAN.md` sections 9 and 10 have the full history. The pieces stack, and each
works on its own, so take the ones you need.

### 1. Turn the rules on before the place is made

Rules that change how a town or floor is *built* must stand before the build starts. A town builds its dungeon's
first floor unseen as it loads, so `game.world.location_changed` is too late. Set them on `game.scene.will_enter`
(and again on `location_changed`, which is cheap):

```lua
local function passage_rules()
  local on = my_world_is_on()                                  -- yours: a setting, or a flag kept with the save
  try(game.dungeons.set_floor_select, {enabled = not on})       -- the entrance skips its floor menu
  try(game.dungeons.set_quick_passage, {enabled = on})          -- no loading card; town and dungeon stay loaded
  try(game.world.set_roads, {enabled = on})                     -- a town's gate asks you, not the world map
end
moonmod.on("game.scene.will_enter", passage_rules)
moonmod.on("game.world.location_changed", passage_rules)
```

All three are **one mod at a time** and given back when the mod unloads.

### 2. Town and dungeon, both live (quick passage)

With `dungeons.set_quick_passage({enabled = true})` the engine does the rest:

- **No loading card.** A jump between a town and a dungeon, between two towns, or between two floors of one dungeon
  holds the last picture on screen until the other side is ready (at most ten seconds), then cuts.
- **Connected worlds.** Each place keeps its own memory (town `100 + map`, dungeon its map), so walking back out of
  the dungeon resumes the town as it was left, villagers where they stood, and walking back in resumes floor 1.
- **The door is a window.** Norune's cave door, once opened, stays open, and the cave is drawn live through it; inside,
  the village is drawn live through the doorway behind the arrival. Walk into either facing it and you go through:
  no button, no fade. The first time, the town builds floor 1 unseen as it loads so the cave is already there
  (`prebuild = true` on `generating`/`generated`). Matataki's forest path works the same once you have been in.
- **What you see as a mod:** `game.dungeon.resumed` instead of `generating`/`generated` when a floor is gone back to,
  not built. Treat it as "the party is on this floor again".

### 3. One map per dungeon (regions)

Each dungeon is built as one map with a zone per floor, joined by locked gates whose keys a monster in each zone
carries (*Shape a floor as it is built*: `set_zones` with `source_floor` per zone and `exit_floor`). Keep each
floor's seed (`set_seed`), opened chests (`set_opened_chests`), seen cells (`set_seen`) and opened gates with the save
and give them back each build, and the map is the same every visit. Shrines (`shrines = true`) are the rest points
and the fast travel; `sanctuary = true` keeps monsters out of their circle. `descent = 40` puts each zone a step
below the one before, down a ramp outside its gate, so going deeper reads as going down. Anything a mod places by the
player's height (a ring of spawns, a burst) should wait off a ramp: `zones_get().ramps` gives their cells.

Messages between players (`messages.post`, `list`, `rate`) need no server: the player points their messages folder at
one a sync service shares. Put them at a place every save has (a dungeon, floor and shrine, never a cell: each save
builds its own maps), build them from fixed phrases and show only what parses back into one, and tell the player who
can read what they leave (`shared` in each reply).

### 4. Story floors: smoke you walk through

The boss and scene floors are fixed maps with their own scripts, so they can't be zones of a region. Put a smoke
gate in front of them instead (`set_zones({..., smoke = {zone}})`). Walking up to it fires
`game.dungeon.smoke_touched`; offer a panel, and on *Go through* call `dungeons.enter_floor({floor_id = f})`. With
quick passage on, that floor-to-floor jump is a cut too. On the story floor, `dungeons.set_story_exits` turns its key
gate into a *Leave* panel; on `game.dungeon.story_exit` enter the next floor's zone of the region.

### 5. Roads between the towns

The game has no outdoor map joining two towns (its fields join towns to dungeons), so the town's **gate is the road**.
With `world.set_roads` on, walking out of the gate sends `game.town.road` `{town_id, location_id}` once each time the
party walks onto it, and the world map never opens. Answer with a panel, which needs `town = true` to open outside a
dungeon:

```lua
local ROAD = {[0] = {{town = 1}}, [1] = {{town = 0}, {town = 2}}, [2] = {{town = 1}, {town = 3}, {dungeon = 2}},
              [3] = {{town = 2}, {town = 4}, {dungeon = 3}}, [4] = {{town = 3}, {dungeon = 4}, {dungeon = 5}}}
local from
moonmod.on("game.town.road", function(e)
  if not ROAD[e.town_id] then return end
  from = e.town_id
  local options = {}
  for _, way in ipairs(ROAD[e.town_id]) do options[#options + 1] = {title = way.town and TOWN[way.town] or DUNGEON[way.dungeon]} end
  options[#options + 1] = {title = "Stay"}
  try(game.ui.choice_open, {id = "road", title = "The road", cancel = true, town = true, options = options})
end)
moonmod.on("ui.choice_made", function(e)
  if e.id ~= "road" or e.cancelled or not from then return end
  local way = ROAD[from][e.index]
  from = nil
  if way and way.town then
    call(game.world.transition, {id = "chronicle:location:" .. TOWN_IDS[way.town]})
  elseif way then
    call(game.dungeons.enter_floor, {dungeon_id = way.dungeon, floor_id = 0})  -- the dungeons only the map reached
  end
end)
```

Put the dungeons that only the world map reached (Shipwreck, Sun and Moon Temple, Moon Sea, Gallery of Time) on the
road too, or replacing the world map cuts them off.

**Things to know**

- **Where the gates are.** Matataki's and Muska Lacka's gates are the game's own: ground of kind 1 that ran program 1
  (the world map). Norune's, Queens' and Yellow Drops' are the spot the world map sets the party down, taken facing
  out of town (Norune's spot faces a fence; Queens' kind-1 ground is elsewhere; Yellow Drops has no program 1).
- **Towns reached by road load fresh**, as the world map always loaded them. A town's live objects (party, villagers,
  ground) are shared statics the next town overwrites, so only the dungeon's way out, back to the town whose objects
  are still live, resumes one.
- **Ahead of the story.** A town reached early plays its arrival scene (Matataki's, unless story flag 9 is set); it
  plays through and hands the walk back. Sun and Moon Temple's story floors 4 and 7 leave for the desert field (s32)
  for their scene and come back by themselves, so a mod sees the dungeon left and entered again.
- **Wise Owl Forest can't be built unseen** (its walk-in waits on an action sequence only real frames move): the
  prebuild gives up after 120 frames, and the forest is built on the first walk in, connected after.
- **Panels in towns are opt-in** (`town = true`). A mod that retries its panel every tick until one opens (the
  Gauntlet's blessing and weapon picks) keeps waiting for the dungeon, as it always did.
- **Floors built without zones stay byte-identical**: none of this changes a floor a mod didn't ask to change.

### Testing it without playing

Everything above was checked headless on a copy of a real save, with a throwaway probe mod. The pattern:

1. Copy the save folder to a scratch folder and copy the current mod into its `mods/` (a stale copy misleads), plus a
   probe mod with `game.read`/`game.write` enabled in its `moonmod/profile.json`.
2. Run the game headless with a scripted pad:
   `darkcloud.exe --data <data> --save <scratch> --headless --jump title --fast-load --frames N --input pad.txt --screenshot shot.png --screenshot-at 1500,2200`.
   The input file holds lines `<frame> [buttons] [lx ly rx ry]`, held until the next line: `500 start`, `560 cross`
   and two more crosses load slot 1 from the title; `1500 128 0 128 128` holds the stick up (sticks 0-255, 128
   centre); `1504` lets go. Pad words don't reach a mod's own key bindings; `key:E` lines do.
3. In the probe, act on `game.tick` counts and log what happens (`moonmod.log` goes to stderr):

```lua
local ticks = 0
moonmod.on("game.tick", function()
  ticks = ticks + 1
  if ticks == 1100 then game.world.transition({id = "chronicle:location:matataki-village"}) end
end)
for _, ev in ipairs({"game.town.road", "game.world.location_changed", "game.dungeon.generated", "game.dungeon.resumed"}) do
  moonmod.on(ev, function(e) moonmod.log("info", "PROBE " .. ev .. " " .. tostring(e.town_id or e.floor_id or e.context) .. " at " .. ticks) end)
end
```

- **Every floor of a dungeon:** step `dungeons.enter_floor({floor_id = f})` through each in turn, counting a floor
  once `location_changed` arrives and play has run on it for a few seconds; retry when the call is refused (a story
  floor's scene may have taken the party out). This is how all six dungeons were checked, story floors included.
- **Screenshots** catch what logs can't: a loading card, a black hold, a scene that never hands the walk back.
- The held picture keeps the *old* place on screen while the new one loads, so a screenshot taken too early shows
  where you were; wait for `location_changed` before timing pad input in the new place.

**In Vigil:** `passage_rules`, *Roads*, *Smoke* and *Shrines* in `mods/moonmod.vigil/main.lua`; the engine side is
`port/src/game/doorway_view.cpp`, `editloop.cpp` and `chronicle_adapter.cpp` (`ChronicleMapJumped`,
`StepHeldPicture`, `SetRoads`) in `ports/chronicle/moonfactory-chronicle.patch`.

---

## A special room: the Rest floor

**What:** the Gauntlet's floor between biomes: one hall with a healing spring and Gaffer's shop, a side room whose
stairs take the Cursed Path, and the usual exit to the next biome. It was built as a new engine operation
(`dungeons.set_rest_room`) plus mod logic, and is a good template for "a floor with a fixed shape".

**The engine side** builds the layout: rooms, corridor, spring, entrance, exit and stairs at fixed places, with
nothing else. `dungeons.rest_room_get()` reports where things are in world units. How that was added is walked
through in [Extending the engine](EXTENDING_THE_ENGINE.md).

**The mod side:**

1. Register a floor with `enemies = {}`. In `game.dungeon.generating`, ask for `set_rest_room({enabled = true})` and
   `set_modifiers({chests = -100})` for it.
2. On arrival, wait until `rest_room_get().state == "rest"`. The floor is reported a few frames before it is built.
3. Heal at the spring by distance. The spring part has no heal event on every dungeon theme, so the mod checks
   `player.get().position` against `room.spring` (260 units), once per visit.
4. Give the gate key, because no monster carries it. Floor changes clear key items from the bag, so wait a few
   seconds after arrival, then give `back_floor_get().gate_key.id`. Check it is held, and take back a key given
   for an earlier read.
5. Make the stairs a choice: `set_backrooms({free = true, stay = true, title, text, lines})`. With `stay` the engine
   only reports Proceed (`game.dungeon.backroom`) and moves nobody, so the mod moves the run itself
   (`world.transition`).
6. Put Gaffer in front of the exit: `world.dungeon_npc_set({id = "gaffer", model = "gedit/e01/chara/p02a.chr",
   place = "exit"})`.

**In the Gauntlet:** `REST.arrive`, `REST.tick` and `REST.cursed` in `main.lua`. The test is
`tools/tests/roguelike/test_runs.lua` (search for "Rest floor").

---

## A boss in a sealed room

**What:** the Gauntlet's Warden: a room behind the exit that stays shut until the rest of the floor is clear, locks
behind you, and holds a boss with a health bar and an entrance card.

**Calls:** `dungeons.set_warden_room({enabled = true, lock_in = true})` while building; event
`game.dungeon.warden_room` (`state = "open"` when the floor is clear, `"entered"` when the player walks in);
`entities.query` and `entities.set_stats` to grow a monster into a boss; `ui.boss_card({name, kicker, epithet,
frames})`; `render.bar_register({id, label, current, max})` for its HP; `dungeons.warden_room_release()` when it falls.

**Things to know**

- A native boss can fight in the room with its own attacks (the Gauntlet's Dran, Utan, Ice Queen, King's Curse and
  Minotaur Joe), using the boss arena slot. The defeat fade replaces their story scenes.
- Scale boss HP by depth instead of fixing it, and keep the scale a setting (the Gauntlet's `warden_hp_scale`).
- Update the HP bar on a timer (every 10-15 frames), not on every hit event.

**In the Gauntlet:** `warden_cleared`, `scale_enemies`, and the Warden handlers. Design notes are in
[`GAUNTLET.md`](../../GAUNTLET.md).

---

## Put a character on a floor

**What:** a townsperson standing in the dungeon who turns to face you, and does something when you walk up.

```lua
try(game.world.dungeon_npc_set, {id = "gaffer", model = "gedit/e01/chara/p02a.chr", place = "exit"}) -- or "player"
moonmod.on("game.dungeon_npc.near", function(e)
  if e.id == "gaffer" then open_shop() end   -- e.g. a ui.choice_open panel of goods
end)
```

One figure per mod, and a new floor sends it away, so set it again on each floor that should have it. `place = "exit"`
stands it inside the exit gate's room, or in front of the exit stair when the exit is on a corridor.

**In the Gauntlet:** `gaffer_arrive` (Gaffer's Wagon shop).

---

## A hero that hunts you (an invader)

**What:** a party member, drawn dark, who comes at the player with that hero's swings and can be fought and felled.

```lua
game.party.companion_set({character = "goro", stance = "passive",
                          hostile = {hp = 200, damage = 20, defense = 0, tint = {r = 40, g = 20, b = 70}}})
moonmod.on("game.companion.struck", function(e)  -- {character, damage, hp, max_hp, killed}
  game.render.bar_register({id = "invader", label = "DARK GORO", current = e.hp, max = e.max_hp, boss = true})
  if e.killed then game.render.bar_remove({id = "invader"}) end
end)
```

It is the companion turned round: it closes in, and every third swing is a slower, heavy one. Its blows go into the
game's own hit list, so the player's guard, a dodge and poise all work on them, and the player's weapon hurts it (less
`defense`). At no life it falls and goes. It can be the hero the player is. One companion is out at a time, helper or
invader; `companion_set({})` sends it away. The player can't lock on to it.

**In Vigil:** the *Invaders* block.

---

## Show things to the player

Everything here is drawn by the engine in the game's own art, so a mod never draws pixels.

| Want | Call | Notes |
| --- | --- | --- |
| A pop-up message | `ui.notify({message, duration_frames, icon?})` | Queued; in a dungeon it uses the game's message window |
| A line of HUD text | `render.layer_register` | Under the life and water block |
| A bar (boss HP, a timer) | `render.bar_register({id, label, current, max})` | Remove with `render.bar_remove` |
| A wider HP bar on the locked target | `render.target_bar_set({on = true})` | Chronicle; a trail shows what a blow took |
| A meter under the target's bar (poise) | `render.target_meter_set({entity, fill, color?, seconds?})` | Per monster; full flashes; `{entity}` clears |
| A small icon by the floor plate | `render.hud_icon_set({id, icon or image, blink?})` | Up to six |
| The floor plate's text ("2-3") | `render.floor_label_set` | `render.floor_label_clear` restores it |
| A pick of 1-4 cards | `ui.choice_open({id, title, options})` | Pauses play; answer in `ui.choice_made` |
| A map with marks | `ui.map_open({id, title, marks, cells?})` | The floor or a kept map (`dungeons.map_snapshot`), in a dungeon or a town; answer in `ui.map_choice` / `ui.map_waypoint` |
| An upgrade sky in a dungeon | `ui.sky_open({id, title, sky})` | The title mode's node sky over the paused dungeon; answer `ui.sky_selected` by opening it again with the new states |
| A menu in place of the pause | `ui.run_menu_set({title, tabs})` | Rows send `ui.run_menu_action` |
| A boss entrance | `ui.boss_card({name, kicker, epithet, frames})` | |
| A page in the Journal | `ui.sheet_set` / `ui.sheet_open` | Journal > Character, with a skill tree |
| Buttons in the Mod Manager | `ui.register` | Answer in `ui.action` |

**Things to know**

- Send no `rows`, `lines` or `links` field rather than an empty table. An empty Lua table reaches the engine as a JSON
  object and is refused.
- Notices shown the moment a floor loads compete with the game's own messages. A second or two of delay reads better.
- Text fields have byte limits (titles about 32-64, lines 64, notices 200). Trim with `:sub(1, n)` where text is
  generated.

---

## Change combat

| Want | Call |
| --- | --- |
| Your hits do more or less | `combat.register_formula({id, operation, value, ...filters})` |
| Hits on the player do more or less | `combat.register_player_formula` |
| React to a hit | event `game.enemy_hit` (enemy, weapon, damage, `charged`) |
| Hurt a monster from script | `combat.damage` |
| Poison, freeze, ... a monster | `combat.status_add` |
| Change a monster's HP, defence, rewards | `entities.set_stats` |
| Make a script-invincible monster (a roaming King's Curse) take blows | `entities.set_stats({entity, vulnerable = true})` |
| Colour, size, a shove | `entities.tint`, `entities.scale_set`, `entities.knockback` |
| A flash or burst | `effects.burst({kind, position, scale})` |
| A roll or heavy pressed a little early still comes out | `player.tuning_set({input_buffer = 12})` |
| Make a monster fire its own projectile at a point | `monsters.call({entity, native = "SET_SHOT", args = {"dcol0", x, y, z}})` |
| One attack chains into the next (light into heavy and back) | `player.tuning_set({chain_cancel = 6})` |
| A lock-on camera that keeps the target framed | `player.tuning_set({lock_camera = true})` |
| Hit-stop, camera shake and rumble when blows land | `combat.feel_set({hit_stop = {light, heavy, critical, hurt}, shake = {light, heavy, hurt}, rumble})`, `combat.feel_clear()` |
| An attack of your own on the player (after a telegraph) | `combat.strike_player({x, y, z, radius, damage, kind})` |
| Shut the room the player is in (an ambush), open it again | `dungeons.room_seal({})`, `dungeons.room_release()` |
| Darken a place | `dungeons.lighting_set({fog = {near, far, r, g, b}, ambient})` |
| Player speed, i-frames, thirst, wear | `player.tuning_set` |
| A guard that covers the front, costs stamina, breaks and parries | `player.guard_rules_set` |
| Hits that drain the gauge, a first swing that costs, a refill delay | `player.gauge_rules_set` |
| React to the player being hit, blocked, parried or broken | event `game.player.hit` |
| Read or spend the gauge, see what the player is doing | `player.gauge_get`, `player.gauge_set`, `player.state` |
| A monster that fights differently | hook `native.monster.run` (`scripts.override`), drive it with `monsters.call` |

Formulas are owned and stack by priority. Register them once, and update them by re-registering the same id with a
new value instead of adding more. A mode that changes the rules (the Gauntlet's curses and blessings) recomputes its
formulas in one place (`apply_effects`) whenever the run changes.

A monster's own AI can be replaced program by program: override `native.monster.run`, take program 100 (its idle
loop) for the kinds you have a brain for, and hand everything else to `game.scripts.call`. Each frame the brain reads
where the player is (`GET_POSITION`), whether the player just swung (`GUARD_SEARCH`) and its own motion frame
(`CHK_MOTION_FRM`), then walks, steps, guards or attacks with `SET_MOVE` and `SET_MOTION`. Vigil's Dashers and
Skeleton Soldiers take turns with one attack token. `ctx.model` is the floor's slot, not the monster's kind: key brains
by `entities.query`'s `native_model_id` ([API](../API.md)). To find where a monster's blows land, read its own script:
`python tools/stb/stbdis.py data/dun/monstor/<model>.stb --table monster --port <Chronicle>/port` lists its
`SET_DMG_COL(bone, radius, from, to)` windows, its `SET_GUARD_FRAME(from, to)` span and the motions it plays, and
`tools/anim/moonanim.py`'s `Rig(...).motions` gives each motion's frame range (`tools/vigil/monster_survey.py` does both). (Or play each motion number on it,
read `CHK_MOTION_FRM` and watch the player's HP while it swings.)

Poise is the same hook at program 110 (hit): return `{handled = true}` without calling the retail program and the
monster skips its flinch. The game runs 110 once per blow, so count blows per entity and let the retail flinch run
once they pass the monster's poise (Vigil's *Poise*). A monster your brain drives carries on mid-swing; a retail one
still has its program cut by the hit, so it restarts its idle loop without flinching.

### Stamina, guard and parry (Souls rules)

The action gauge is Dark Cloud's stamina bar, and the guard is lock on + R1. Two rule sets turn them into a Souls
guard and a Souls stamina bar, as Vigil does:

```lua
game.player.guard_rules_set({arc = 120, cost_base = 10, cost_per_damage = 1.5, chip = 0.15,
                             break_recoil = 120, parry_frames = 6, without_lock = true})
game.player.gauge_rules_set({hit_refill = -15, first_swing_cost = 25, min_to_swing = 10, refill_delay = 36})

moonmod.on("game.player.hit", function(e)
  if e.parried and e.entity then -- the riposte window: stop the attacker and shove it off
    game.combat.status_add({entity = e.entity, status = "stop", duration_frames = 90})
  end
end)
```

Each rule set has one owner. Clear both (`guard_rules_clear`, `gauge_rules_clear`) when your mod stands aside for
another's game mode; unloading clears them too. `game.player.hit` fires for every hit, with or without rules, so a
mod can count hits taken, drop Gilda on death or show a hit direction without changing the guard at all.
`player.gauge_set({add = n})` refunds or charges gauge for things the game doesn't price (a heal, a switch).

---

## Weapons, shops and loot

```lua
-- A new weapon from a template, with its own model and icon shipped in the mod.
try(game.resources.override, {path = "resources/staff1.chr", game_path = "commenu/weapon/opsz01.chr"})
try(game.resources.override, {path = "resources/staff1_icon.png", game_path = "icons/opsz01_icon.png"})
local staff = try(game.weapons.register, {id = "staff1", name = "Lily Staff", template_weapon = 262, owner = "toan",
  model = "opsz01", icon = "opsz01_icon", stats = {attack = 12, durability = 30}, description = "..."})
-- It builds up into the next one.
try(game.weapons.build_up_register, {from = staff.id, to = staff2.id})
-- Sold in a shop, at a price.
try(game.shops.register_item, {shop_no = 1, item_id = staff.id})
try(game.shops.set_price, {item_id = staff.id, buy_price = 800, sell_price = 200})
-- Found in chests now and then.
try(game.dungeons.chest_weapons_add, {item_id = staff.id, dungeon_id = 0, floor_from = 3, percent = 10})
```

**Things to know**

- Registered weapons live in the slots past retail's (items 377-408). They start at their template's price.
- Shop goods added with `register_item` are kept apart from the shop's list and put back after any other mod rewrites
  the shop (Dungeon+ rewrites stock daily). Two mods can stock the same shop.
- Shop calls name the shop as `shop_no = N` or `id = "chronicle:shop:N"`, and the item as `item_id`. Prices go
  through `shops.set_price`, never `register_item`.
- `dungeons.chest_weapons_add` belongs to your mod and stays on until you take it back. Add the weapon only while it
  should drop, for example only in the story game, and call `dungeons.chest_weapons_clear()` when it shouldn't.
- `weapons.style_set` gives one owned weapon a coloured name, a glow and a card. The Gauntlet's rarity tiers use it.
- `weapons.stat_label_set({attack = "label_attack", endurance = "label_endurance", speed = "label_lightness",
  magic = "label_magic"})` relabels the weapon cards' stats with your own images (each put at `icons/<stem>.png` by
  `resources.override`; draw them 52x30). The Status tab then wipes its painted labels and lays yours evenly, one per
  bar. Use it when your mod changes what a stat means; `{}` brings the game's labels back.
- `items.give` can return success after adding 0 (a full bag). Check the result's count, or the bag afterwards, when
  it matters.
- `items.charm_slots_set({count = 1})` opens charm slots on the item page (up to 4 for each character, beside their shield): an
  amulet there guards that character against its ailment as from a quick slot, without taking one or any bag room. The engine keeps them with the save, and
  one holding an amulet stays shown with your mod off, so nothing is lost. `items.charm_slots()` reads them. The worn charm shows on the dungeon HUD with its uses left, before your `render.hud_icon_set` icons.
- `player.tuning_set({dodge_run = 20})` makes L2 a Souls run: hold it to run (draining 20 gauge a second), tap it to
  dodge as it is let go. Open the Feather's own charm slot with `items.charm_slots_set({count = 1, feather = true})`:
  the Feather there halves the drain. Vigil
  opens one.
- `items.gear_give({kind = "boots", name = "Swift Boots", rarity = 1, value = 180, effects = {run_cost = 16}})` makes
  a gear piece; `items.gear_equip({uid = piece.uid})` puts it on the active character, and the engine reads its
  effects (an ailment guard, stamina, lightness, defence, run cost, poise: `effects = {poise = 2}` takes two light
  hits, or one heavy, without a stagger). Give it `icon = "gear_boots"` and
  `color = {r = 232, g = 92, b = 76}` to tint one grey icon per piece.
- `items.gear_page_set({icons = {hat = "gear_hat", tunic = "gear_tunic", gloves = "gear_gloves", boots = "gear_boots"}})`
  puts the gear on the item page: an Equipment tab on the board holds the bag, and the character card becomes a hero
  page with his charm slots, his weapon at his hand and four gear slots (five with `pouch = "gear_pouch"` in `icons`;
  a worn pouch with `effects = {bag = 10}` grows the item bag by 10), each empty one showing its kind's icon
  blacked out. Pieces move with Cross or the mouse, as items do. `{}` closes it. Vigil opens it while its Gear setting
  is on.
- `items.gear_stock_set({shop = 0, goods = {{kind = "hat", name = "Viper Hood", rarity = 1, value = 180,
  effects = {guard = {poison = 30}}, price = 360}}})` puts a piece on shop 0's counter, beside its own goods, while
  the Equipment tab is open: Triangle buys it. On the shop's Equipment tab, Triangle sells a piece for its `value`.
  Bought, it is gone until you stock the shop again; `goods = {}` clears it. Vigil restocks every shop with three
  pieces each trip home.
- Add `parts = {toan = {hat = {draw = {"boushi"}, turn = 40}}}` to that call and the hat slot, the hats in the bag and
  the hat in hand show Toan's own hat from his model on a ground of each piece's `color`, in place of the icon. Add
  `tilt = 40` to a kind to see its part from the side (a boot) rather than from above, and
  `bare = {"boushi", "cloth1"}` to take his hat (and its tail) off him whenever no hat is worn. For a part of a bigger
  mesh, `boots = {draw = {"skin"}, below = {"l_f"}}` shows only what lies under his ankle wraps: his shoes.
- `player.tuning_set({lightness = true, stamina = {toan = 35, xiao = 120}})` splits the gauge in two: each character
  refills at their own rate (gauge a second), and the weapon's Speed only sets what a swing costs (a fast weapon
  cheaper, a slow one dearer, from half to double).

**In the mods:** Opar's staffs (registration, build-up, shops, chests) in `mods/moonmod.opar`; the Gauntlet's *Loot*
section (rarity). Opar's code may move between the two mods, so follow the API calls rather than particular weapon ids.

---

## Add a playable character

**What:** a hero past the six, with his own model, portrait, name and stats, in the party, the switch wheel, the
menus and the HUD. Opar is the first.

```lua
try(game.resources.override, {path = "resources/opar/c07d.chr", game_path = "dun/mainchara/c07d.chr"})
try(game.resources.override, {path = "resources/opar/medallion.png", game_path = "dun/mainchara/c07d_face.png"})
local opar = try(game.characters.register_playable, {
  id = "opar", name = "Opar", pack = "dun/mainchara/c07d.chr", portrait = "dun/mainchara/c07d_face.png",
  title = "Moon Sea Frog Mage", fights_as = "toan", hp = 90, defense = 21,
})
-- A sandbox session can start with him: party_size reaches past six to the registered characters.
```

**Things to know**

- `fights_as` names whose actions, weapons, voice and motions he borrows until he has his own.
- Give him weapons of his own with `weapons.register({owner = "opar", ...})`. He is the weapon's holder: it sits in his
  row on the weapon page and he can equip and move it. To the combat code, and in `weapons.get`, it stays a weapon of
  the character he fights as.
- Registered characters are never written to a save. The save keeps its six, so a save made with the mod on still
  loads without it. Story-mode joining keeps its state in the mod's own data.
- Up to ten registered characters. The table is open-ended by design, so don't hard-code "the seventh".
- `player.form_set({pack})` swaps the active character's model for another for a while (Opar's giant-frog form).

**In the mods:** `mods/moonmod.opar`; the design and engine work in [OPAR_PLAN.md](../OPAR_PLAN.md).

---

## New moves and animations

Mods can ship authored motions and bind them to the attack buttons (`animations.player_register`,
`player.moves_set`). The motions are written with `tools/anim`, not Blender. Start with the
[Animation guide](../ANIMATION_GUIDE.md) and the [`examples/new-move`](../../examples/new-move/) mod. The Gauntlet's
full sets for all six characters are documented in [GAUNTLET_ANIMATIONS.md](../GAUNTLET_ANIMATIONS.md).

A move out of a run can push off whichever foot is leading: give it `variants`, each another motion and the stretch of
a native motion (his run) it is for. Vigil's dive roll does this ([API](../API.md), *Chronicle mod moves*).

Locked on, a `dodge` with `direction = "left"` or `"right"` keeps him facing the target while the stick carries him
sideways: Vigil's side rolls are its dive roll with his body turned a quarter into the way he goes
(`tools/anim/vigil_side_rolls.py`). Give quick moves `blend_in` (3 or 4 frames) so the engine's fade doesn't eat the
start and `camera` (about 3) so the camera keeps up with a roll, and run `tools/anim/verify.py` or `motion_checks.py` on anything imported from another game: they flag limbs
snapping round, a whipping blade and a push-off later than 0.15 s.

**Give a monster new motions.** `animations.monster_register({id, file, model, hits})` appends a motion file to a
native monster model the next time a floor loads it; `monster_list()` then gives its motion number and first frame,
and a `native.monster.run` override plays it with `SET_MOTION`. Build the file from the monster's own poses with
`tools/anim` (`Rig(..., cfg_name="info.cfg")`). A flat rig such as the Skeleton's (every piece hung off the root)
turns as a whole by turning each piece about one point; keep every node above the floor, its weapon too. Put an
attack's `hits` where the blow lands when the monster stands at arm's length (the hand, not only the weapon's tip), and
make its damage a factor of the monster's native blow. Vigil gives the Skeleton and the Dasher a roll each way and a new
attack (`tools/anim/vigil_monster_moves.py`, `MONSTER_MOVES` in its `main.lua`).

**A critical: a backstab or a riposte with a paired motion.** Give the player a move with `trigger = "critical"`
(`critical = "backstab"` or `"riposte"`) and `pairs`, one per enemy model, naming the enemy's half (a crumple
registered with `animations.monster_register`). The attack button behind an enemy, or at the one you armed with
`player.critical_set` after a parry or a stagger, draws him in, turns the enemy and plays both; the enemy's script
waits it out. Hook `game.player.critical` for the extra damage:

```lua
game.player.moves_set({moves = {
  {id = "stab", character = "toan", trigger = "critical", critical = "backstab", animation = "toan_critical",
   reach = 22, gap = 11, arc = 100, speed = 0.5, invincible = true,
   pairs = {{model = 1, animation = "e03a_crumple", speed = 0.5}},
   hits = {{at = 0.57, radius = 8, reach = 9, damage = 1.8, knockback = 0}}}}})
moonmod.on("game.player.critical", function(e)
  game.combat.register_formula({id = "critical", operation = "multiply", value = 3, native_model_id = e.native_model_id})
  -- ...and back to 1 after e.hold ticks
end)
```

Author the two halves together: the player's thrust lands where the enemy doubles over, at the same speed.

**A weapon art.** A `trigger = "art"` move plays on R2 while guarding, for the weapons it lists once they reach
`min_level`: list one per weapon family and the equipped weapon picks its own. Say so on the weapon's card with
`weapons.style_set{character, slot, details}` (find the slots with `weapons.get("chronicle:weapon:<n>").instances`):

```lua
{id = "rush", character = "toan", trigger = "art", animation = "toan_lunge", weapons = {258, 259, 260},
 min_level = 3, gauge = 35, lunge = 4.6, hits = {{at = 0.36, radius = 10, reach = 11, damage = 1.8}}}
```

**A move your own key starts.** A `trigger = "played"` move has no button of its own: bind a key
(`game.input.bind`) and start it with `player.move_play`. `game.player.move` gives its `frames`, so a heal or an
effect can land partway through, and `game.player.hit` says whether a blow got through first. Vigil's flask is this:
D-pad Down plays each hero's native drinking motion slowly, heals 40% at 65% of it, and spills on a hit; with
`player.tuning_set{item_heal_lock = 240}` the game's healing items refuse near an enemy, so the flask is the heal in a
fight.

**A modern lock-on.** `player.tuning_set{lock_flick = true, lock_sight = true, soft_lock = 35}`: a flick of the right
stick moves the lock to the next enemy that way, the lock drops when a wall hides the target, and a swing that isn't
locked turns to the nearest enemy within 35 degrees.

**A boss fight's frame.** `ui.boss_card{kicker, name, epithet}` as the boss is first seen, and
`render.bar_register{id = "boss", label = "DRAN", current, max, boss = true}` each half second for a wide bar along the
bottom. For a second phase at half life, tint it (`entities.tint`), raise its `damage_scale` (`entities.set_stats`
returns the `current` one to multiply) and `combat.status_add{status = "haste"}` for faster moves. Vigil's story
bosses and named elites are this (`mods/moonmod.vigil/main.lua`).

**Shortcuts and illusory walls on a kept floor.** From `game.dungeon.generating`, ask
`dungeons.set_shortcuts{count = 2, illusory = 1, open = {...}, open_walls = {...}}`. Keep each
`game.dungeon.door_opened` key item and each `game.dungeon.wall_opened` `wall` number with the floor's seed, and send
them back as `open` and `open_walls` the next time it is built. Opened doors and struck walls then stay open.
Vigil's are `tools/anim/vigil_criticals.py` (Toan) and the `crumple` in `vigil_monster_moves.py`.

---

## Change the game's text

`text.set({key, text})` replaces one of the game's own messages, and `text.clear` puts it back. Opar rewrites lines
of the house scene in Norune while he is waiting to join, and puts them back afterwards (`words()` in
`mods/moonmod.opar/main.lua`). Keys and the glyph tokens (`{icon-jar}`, `{insert1}`, `{name2}`) are in the
[API map](../API.md).

---

## Share the game with other mods

- **Sit out another mod's game mode.** A story-game mod checks `session.get()` at load and on
  `game.session.started`. While `kind == "sandbox"` and it isn't the owner, it sets its formulas back to x1, clears
  its tuning, bars and sheet, and ignores events until `game.session.ended`. RPG, Ascension and Dungeon+ do this.
  `tools/tests/roguelike/test_standalone.lua` checks it.
- **Act only in the story game.** The other way round: Opar's story features check `story()` (not a sandbox) first.
- **Offer functions to other mods.** `scripts.register_function` exports a callback, and a mod that lists yours as
  an optional dependency calls it with `scripts.call_function`. Dungeon+ hands floor tiers to Ascension this way.
- **Expect claims.** One-owner operations refuse a second mod and say who holds them. Release yours when your
  feature is off, and handle the refusal when you can't have it.
- **Order matters.** `load_after` decides who registers first, which decides native floor numbers and who wins a
  replaced resource. Look things up by stable id, never by number.
- **Say where your mod belongs in online co-op.** Add `"coop"` to `mod.json`: leave it out (or `"required"`) when
  your mod changes the world or the rules, so every player in a room must have it at the host's version and plays
  with the host's settings; `"host_only"` when its state lives in the host's save and guests don't need it;
  `"local"` for a mod that is each player's own (keys, camera, HUD). Online Co-op does the rest. If your mod reads a
  setting only at load, also handle `settings.changed`, so a guest follows the host's value during a visit:

  ```lua
  local level = moonmod.settings.get("level")
  moonmod.on("settings.changed", function(e) if e.id == "level" then level = e.value end end)
  ```
- **See which mods are loaded, and their settings.** `mods.list()` gives each loaded mod's id, version and co-op role;
  `mods.settings_get({id})` its settings (another mod's need the `mods.settings` permission).
  `mods.settings_overlay({id, values})` gives a mod values for this session only, never saved, and
  `mods.settings_overlay_clear` takes them back; co-op uses these for the host's settings
  (`mods/moonmod.coop/main.lua`, "The room's mods").
- **Ship several mods as one.** A merged pack (`"parts"` in `mod.json`) holds several mods in one script behind one
  switch; each part keeps its own id, settings, saved data and co-op entry. Build one from separate mods with a
  builder like `tools/pack/build_pack.py` rather than by hand ([Packs and live on/off](PACKS.md)).
- **Survive being switched on and off live.** Players can switch your mod mid-game. Keep what you set up undoable
  through owned state (binds, HUD, tuning, formulas: all released for you), read `game.session.get()` in `on_load`
  when `live` is true instead of waiting for `game.session.started`, and save progress as you go, not only at
  `runtime.unloaded`.
