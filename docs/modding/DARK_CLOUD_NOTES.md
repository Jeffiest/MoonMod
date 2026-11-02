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

- Floor numbers are 0-based natively; the game shows them 1-based. The **boss floors** are fixed maps, not built
  from a seed (no `game.dungeon.generated`): each dungeon's midway floor, which is `CenterFloorTbl` less one, and its
  last floor. Native numbers: Divine Beast Cave 7 (Dran) and 14, Wise Owl Forest 8 and 16, Shipwreck 8 and 17, Sun and
  Moon Temple 8 and 17, Moon Sea 7 and 14, Gallery of Time 24 only (no midway boss). Checked in the game by entering
  each one. Copy enemy layouts from other floors.
- Each main floor is built together with its **back floor** (`buildRandomMap` with `first_build` 0), so a
  `game.dungeon.generated` with `back_floor = true` comes straight after every main floor's, while the player is
  still on the main floor. Ask `world.get().back_floor` whether the player is on a back floor.
- With connected worlds (quick passage), a dungeon walked back into through its town's door, onto the floor the party
  left there, is not built at all: `game.dungeon.resumed` comes instead of `generating`/`generated`, and the floor's
  opening script (program 100) does not run, so nothing it sets up runs again either.
- Walked in through the town's door, program 100 still builds the floor, but its stairs walk-in (and any scene it runs
  on the way, such as Divine Beast Cave's Fairy King, `RUN_SCRIPT_NO(199)` behind story flag 103) plays out unseen.
  A mod that wants such a first-entry scene seen holds its flag before the floor is built and plays it later, as
  Vigil does with the King. With connected worlds the first floor is built as the town loads (`prebuild = true`), so
  hold the flag from `game.scene.will_enter` for the town, not from `game.world.location_changed`.
- Norune's door into the Divine Beast Cave is program 130 of `gedit/e01/event.stb`, run by a door point whose
  destination is `"dungeon"`. It waits for Cross (game flag 1 is the story's key used), then slides fixed part 3's
  `door1` and `door2` frames 18 apart along z over 60 frames and `MAP_JUMP`s to 201 (map 200). With connected worlds,
  a door that has opened once is set open as the town loads and walked through without the program. The cave's
  entrance piece (DBC part 30) has its own door, `in_door`, that rises and falls on the stairs walk-in; with connected
  worlds it is hidden, the town's door being the way out. The other towns have no program 130.
- Sun and Moon Temple's story floors 4 and 7 (floor ids 3 and 6) leave the dungeon for the desert field s32 (map 42)
  to play their scene there, then jump back to the temple; a mod sees the dungeon left and entered again.
- A town's gate to the world map is its program 1 (`WORLD_MAP`, then `MAP_JUMP` to the pick, or the party set back
  facing in): it runs from ground polygons of kind 1 (`ground_kind`, `RunEvent` on landing), beside where the world
  map's start program 128 sets the party down (Norune -780,-342 facing 1.57, a fence ahead; Matataki 80,-880 facing 0;
  Queens 1407,170,44 facing -1.57; Muska Lacka 807,405 facing -1.57; Yellow Drops 0,110,-560 facing 0). Yellow Drops
  has no program 1. No field (s01-s36) joins two towns; they join towns to dungeons.
- Matataki's way into Wise Owl Forest is its program 3 (`gedit/e02/event.stb`): the party walks to (-1287, 31, -375)
  watched from a camera at (-1132, 30, -339), the screen fades, and `MAP_JUMP(202)` goes to map 201. Queens, Muska
  Racka and e05 have no jump into a dungeon in their event scripts and no `"dungeon"` door point in `mapinfo.cfg`;
  their dungeons are reached from the world map (`MenuMapJumpMode`). Wise Owl Forest's opening script 100 walks the
  party in with an action sequence (`ASQ_CHECK` waits on it), which only advances with real frames.
- A **knockout** (the whole party down) halves the Gilda (`CDngStatusData::SetDead`) and sends the party to town.
  ABS is not touched. `game.dungeon.defeated` carries the Gilda from before.
- Headless runs with `--jump` turn the game's debug mode on, and in debug mode a knockout gets the party up again
  at full life instead. To test a knockout, press `l1 r1 l2 r2 r3` together in the `--input` script first (it
  prints "debug mode off").
- The other floors in the game's no-atla list (`noEntryTbl`, such as Divine Beast Cave's native 10) are built floors
  whose script switches to a story character. Entered directly with a save that lacks that character, the game stops
  on a missing weapon model ("commenu/weapon/"). Use a story save, or keep away from them in tests.
- `dungeons.register` appends floors to dungeons 0-4, up to 25 floors per dungeon (the save's fixed tables). Gallery
  of Time is already full, and Demon Shaft has its own 100-floor path. Native numbers of added floors depend on
  registration order, so always look them up by stable id.
- **Back floors** (the game's *ura* floors) are a second version of a floor reached by stairs. Their entrance parts
  are `MAP_PARTS_URA_ENTRANCE_*` (40-43).
- A floor is **reported before it is built.** The location changes a few frames before the map exists. Wait for
  the state you need (a getter answering, a room reported) before acting on the layout.
- `game.dungeon.generating` fires just before the builder runs, and floor requests (`set_modifiers`,
  `set_rest_room`, ...) apply to that floor and the ones after it.
- A floor is its **seed**. The same seed and the same requests build the same floor, chests and monsters included.
  `game.dungeon.generated` reports it once the floor exists; `dungeons.set_seed` builds it again. Back floors take
  their floor's seed.
- Rooms join as a tree: each new room digs a corridor toward the nearest earlier room and stops at the first cell
  already dug (`joinRoom`). Zones use that: a zone's rooms join only each other, and the corridor into it is dug last and
  kept only if it stopped on the zone before's side.
- A floor's monster models come from its enemy layout (`BtEnemyLayoutList[dungeon][floor]`), all loaded when the floor
  starts, into what the map leaves of its model arena (retail's 0xA7F80 quadwords; the port's arena is four times that).
  A Divine Beast Cave floor uses about 108K quadwords, its floors 1-7 together 364K, and 9-15 together 483K, near
  retail's 507K: the port gives the monsters the whole arena, about 2.5M. Its atla come from `BtAtraFloorCyoice(dungeon, floor)`, and a pickup is credited to a floor
  (`getAtraToSaveData`), so a region's atla can each keep their own floor. Divine Beast Cave's floor 4 (native 3)
  has no atla in a new save.
- The entrance's floor list offers each floor up to the deepest reached (`floor_reached`, raised by `SetNowFloor`).
  The exit gate's next floor goes through the floor scripts' `_SET_FLOOR_LEVEL`.
- A room may be split by a wall along a row or column (`setRoomDivid`), which can run right in front of a spring on
  the room's top wall. Shrines keep it clear.
- Divine Beast Cave's floor 3 (native 2) starts with a scene with the Mayor the first time; it holds the floor in a
  system script (`GAME_TASK_SCRIPT_RUN`) until the player reads it through.
- Chests are placed after the layout (`buildEventData`, from the same `rand()` stream), so the same seed puts the same
  chests down in the same order with the same items. A chest is opened by clearing its event and setting `closed = 0`.

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

## Story floors, and where their maps come from (2026-11-01)

The floors each dungeon keeps atla off (`noEntryTbl` in `dungeonparts.cpp`, 1-based: Divine Beast Cave 4, 8, 11) are its
story floors. Divine Beast Cave's 4 and 8 are fixed maps (`d01inter2.cfg`, "battle with the skeleton", and
`d01inter.cfg`, "Seda appears"; Dran's is `d01boss.cfg`), with no `game.dungeon.generated` event. Each fixed map has its
own `gatekey` and `out` ("to the next floor") markers, so its way out is the game's own. Entering one of the story
floors straight from a fresh `--jump` save can crash on `File open error "commenu/weapon/"` (Wise Owl Forest 4,
Divine Beast Cave 11): they expect the story before them. A floor built from a seed in a mod's region never runs
another floor's event data (`buildEventData` takes the floor being built), so a story floor folded into a region
loses its scene. The game's own Gilda drops (`CRandomItem`) are taken within 5 units, standing on them.
