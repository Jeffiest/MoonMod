# Dark Cloud engine notes

Facts about how Dark Cloud's own code behaves, learned while building the bundled mods. They matter when you place
things on a floor, time a call, or extend the engine. The game's code is the Chronicle port's fork in
`port/src/game` and `port/include/game`.

## Time and space

- **Frames.** The game runs at 60 frames a second. `duration_frames = 300` is five seconds. `game.tick` reports
  `frame`.
- **World units.** A dungeon cell is **160 units** square. The cell at column `c`, row `r` is centred near
  `x = 160 * c`, `z = 160 * r`; `y` is height. The API reports positions in these units (`player.get().position`,
  `rest_room_get().spring`).
- **The floor grid** is `DNG_GRID` x `DNG_GRID` cells (48 on the PC port, 20 in retail), indexed
  `col + row * DNG_GRID`. Rows grow toward +z.

## Dungeons and floors

| Native id | Dungeon | Retail floors |
| --- | --- | --- |
| 0 | Divine Beast Cave | 15 |
| 1 | Wise Owl Forest | 17 |
| 2 | Shipwreck | 18 |
| 3 | Sun and Moon Temple | 18 |
| 4 | Moon Sea | 15 |
| 5 | Gallery of Time | 25 |
| 6 | Demon Shaft | 100 |

- Floor numbers are 0-based natively; the game shows them 1-based. Some floors hold story bosses (Divine Beast Cave's
  native floor 8 is Dran's, and each dungeon's last floor is its boss). Copy enemy layouts from other floors.
- `dungeons.register` appends floors to dungeons 0-4, up to 25 floors per dungeon (the save's fixed tables). Gallery
  of Time is already full, and Demon Shaft has its own 100-floor path. Native numbers of added floors depend on
  registration order, so always look them up by stable id.
- **Back floors** (the game's *ura* floors) are a second version of a floor reached by stairs. Their entrance parts
  are `MAP_PARTS_URA_ENTRANCE_*` (40-43).
- A floor is **reported before it is built.** The location changes a few frames before the map exists. Wait for
  the state you need (a getter answering, a room reported) before acting on the layout.
- `game.dungeon.generating` fires just before the builder runs, and floor requests (`set_modifiers`,
  `set_rest_room`, ...) apply to that floor and the ones after it.

## Map parts

Each cell holds one part (`MAP_PARTS_*` in `dungeonparts.hpp`). Parts with four directions come in
north/east/south/west order.

| Id | Part |
| --- | --- |
| 0-4 | Corridors: straight, corner, cross, tee, dead end |
| 5-8 | Room walls |
| 9-12 | Room wall with a doorway |
| 13-16 | Room corners |
| 17 | Room floor |
| 18-29 | Dividing walls inside rooms (ends, doors, walls) |
| 30 | `STAIR_DOWN`: where the player comes in |
| 31 | `STAIR_UP`: the exit gate, opened by the floor's key |
| 32-35 | Healing spring |
| 36-39 | Room gate: a door closing the room the floor links to |
| 40-43 | Back-floor entrance |
| 44 | Back-floor corridor |
| 45-46 | Pillars |
| 47-54 | Room doors, variants B and C |
| 55-59 | Xiao-only door and part |
| 60-63 | Goro-only door |
| 64-67 | Ruby-only door |
| 68, 69 | Ungaga-only and Osmond-only parts |

## Map events and triggers

What happens when the player reaches a stair, a gate or a back-floor entrance is a **map event**:

- `CDungeonEventMan::SetupEvent` binds the dungeon's event slot definitions to cells **by part id**. A part with no
  slot in that dungeon's definitions does nothing. The healing spring has no event on Wise Owl Forest, which is why
  the Gauntlet's rest floor heals by distance in the mod.
- An event fires when the player is inside its trigger: `SearchDataSlotPos2` matches within the slot's radius plus
  10 units. **Triggers are small and sit off the cell's centre:** the back-floor entrance has radius 10, the exit
  stair radius 20. A test that teleports the player to the middle of the cell misses them. Use the event's own
  position (`CDungeonEventData::pos`).
- The exit gate asks for the floor's key in each dungeon's own way. In Wise Owl Forest it is an owl ("Seems like it
  wants something"), and the key is used from the item menu.

## Items and keys

- Item numbers are the game's item table (`ps2/include/itemdata.hpp`). Weapons registered by mods take items
  377-408. The Gauntlet's shortcut-door keys are items 216-222.
- **A floor change takes every key item from the bag.** A key given the moment a floor is entered is lost. Give it a
  few seconds in, and check it is there.
- `items.give` can succeed while adding nothing (a full bag). Check the result's count.
- Weapons wear with every hit, more for heavy and charged swings. Ruby's spells wear her ring too.

## Characters and saves

- Playable ids in engine order: `toan`, `xiao`, `goro`, `ruby`, `ungaga`, `osmond` (native 0-5), then registered
  characters from 6.
- The save holds six of everything per character, and `party_size` counts joined characters in that order. The
  port keeps this layout exactly, so saves stay compatible both ways. Registered characters live outside the save.
- Character packs are `dun/mainchara/*.chr`, weapon models `commenu/weapon/*.chr`, town villagers
  `gedit/<town>/chara/*.chr` (Gaffer is `gedit/e01/chara/p02a.chr`). A mod supplies its own files at such paths with
  `resources.override`.
- A character's model shares a fixed model arena with weapons and effects. A very detailed model can crowd them out.
  The port carves four times the PS2 arena, and weapons and effects use what's left of it.

## Monsters

- 256 monster slots on the PC port (16 in retail). How many act at once is a separate limit
  (`entities.set_active_limit`).
- Monsters are identified by generation-checked handles. A slot is reused when its monster dies, so a handle from
  earlier fails cleanly rather than pointing at a new monster.
- Enemy movement is rewritten by the game's AI each step. A speed change has to be reapplied while it should hold.
