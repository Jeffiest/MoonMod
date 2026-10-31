# Cookbook

Recipes for the things the bundled mods do, each with the calls involved, a short example and the traps found while
building it. Field-by-field details are in the [API map](../API.md). Each recipe names the bundled mod code that does
it for real, so you can read a working version.

Recipes are Chronicle unless they say otherwise. The snippets use the `try` and `call` guards from
[Your first mod](FIRST_MOD.md#guard-every-game-call).

- [A game mode on the title menu](#a-game-mode-on-the-title-menu)
- [Add dungeon floors](#add-dungeon-floors)
- [Shape a floor as it is built](#shape-a-floor-as-it-is-built)
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
| `dungeons.set_shortcuts({count})` | Dead-end rooms loop back through locked doors with coloured keys |
| `dungeons.set_weapon_drops({unique, rare, large_chests})` | What weapons chests hold |
| `dungeons.set_warden_room({enabled, lock_in})` | A sealed boss room behind the exit |
| `dungeons.set_rest_room({enabled})` | A two-room rest layout (spring, exit, stairs) |
| `dungeons.set_character_blocks({characters})` | Character-only doors and jumps appear only for these |
| `dungeons.set_backrooms({free, title, text, stay, lines})` | Back-floor stairs ask with a panel instead of taking the key |

**Things to know**

- `game.dungeon.generating` can fire after your own arrival logic has run, or for the back floor. Decide from the
  event's `dungeon_id` and `floor_id`, not from what you think is happening.
- Several of these are **one mod at a time** (`set_rest_room`, `set_warden_room`). A second mod is refused with
  "another mod already ...". Turn yours off (`{enabled = false}`) when your mode ends so others can use it.

**In the Gauntlet:** the `game.dungeon.generating` handler under *Floors*.

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

## Show things to the player

Everything here is drawn by the engine in the game's own art, so a mod never draws pixels.

| Want | Call | Notes |
| --- | --- | --- |
| A pop-up message | `ui.notify({message, duration_frames, icon?})` | Queued; in a dungeon it uses the game's message window |
| A line of HUD text | `render.layer_register` | Under the life and water block |
| A bar (boss HP, a timer) | `render.bar_register({id, label, current, max})` | Remove with `render.bar_remove` |
| A small icon by the floor plate | `render.hud_icon_set({id, icon or image, blink?})` | Up to six |
| The floor plate's text ("2-3") | `render.floor_label_set` | `render.floor_label_clear` restores it |
| A pick of 1-4 cards | `ui.choice_open({id, title, options})` | Pauses play; answer in `ui.choice_made` |
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
| Colour, size, a shove | `entities.tint`, `entities.scale_set`, `entities.knockback` |
| A flash or burst | `effects.burst({kind, position, scale})` |
| Player speed, i-frames, thirst, wear | `player.tuning_set` |

Formulas are owned and stack by priority. Register them once, and update them by re-registering the same id with a
new value instead of adding more. A mode that changes the rules (the Gauntlet's curses and blessings) recomputes its
formulas in one place (`apply_effects`) whenever the run changes.

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
- `items.give` can return success after adding 0 (a full bag). Check the result's count, or the bag afterwards, when
  it matters.

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
