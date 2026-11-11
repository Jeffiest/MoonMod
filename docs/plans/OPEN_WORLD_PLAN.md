# Open World plan

The goal, in the user's words (2026-11-11): Dark Cloud as "a full open world", "able to walk from village to village,
from village into dungeon", with loading screens "and things like that" gone.

This plan takes over from VIGIL_PLAN §10 (O0 to O2, C0 to C3, L1 to L6), which built the first stretch inside Vigil:
Norune and Matataki are joined to their dungeons through a real door, with both places loaded and no loading card.
That section stays as the record of how it was built. Work from here on is planned and tracked in this file.

Engine paths below are in the engine tree (`port/src/...`); line numbers are from 2026-11-11 and will drift.

## 1. What "done" means

One measure decides every phase: **between any two places the player can walk, how many frames are not the game
world?** A loading card, a fade to black, a held picture and a blank frame all count. Done is zero, everywhere the
story lets the party walk.

1. Village to village on foot, along a road that is a place of its own (not a menu).
2. Village, or road, into a dungeon through a door or a cave mouth, and back out the same way.
3. Into a house and out again with no fade.
4. Down a dungeon with no break between floors.
5. Where the story itself moves the party (a scene, a ship, the moon), the trip is shown, not hidden behind a card.

## 2. Where things stand

Built, and in the play build (VIGIL_PLAN §10; memory `vigil-world`):

| Piece | What it does | Limit today |
| --- | --- | --- |
| Quick passage (`dungeons.set_quick_passage`) | No loading card between a town and a dungeon | One mod holds it; until now only Vigil World saves had it |
| Connected worlds (L1 to L5) | Town and dungeon each keep their own memory and textures; the other place is drawn live through the door; walking back resumes it | One town and one dungeon at a time; only floor 1; only Norune and Matataki have a door |
| First visit (`DunPrebuild`) | Floor 1 is built unseen while the town loads | Wise Owl's can't run unseen, so its first walk in still builds |
| The cut (C0) | A held picture covers a load instead of a card | Still a break: the picture stands still |
| Roads (L6, `world.set_roads`) | A town's gate opens a panel of neighbour towns instead of the world map | A menu, not a road; the arrival reloads the town; arrival scenes still play |
| Vigil World regions | Each dungeon is one map, so no floor loads | Vigil saves only; boss and story floors are still entered through smoke |

Still breaking the world (survey of 2026-11-11):

| Break | Where | Size |
| --- | --- | --- |
| The loading card | Every `MapJump` runs the one mode loop (`app/gameloop.cpp` 977 to 1177). The card (`game/nowload.cpp` 272 to 342) has a fixed length of about 6.6 s, however fast the load is, and the town's ground load waits for it (`editloop.cpp` 5097) | Every trip that isn't a quick passage |
| World-map travel | The map is a ring-menu page (`battlemenu.cpp` 9251, table at 9216); picking a place is a `MapJump` (`editloop.cpp` 1889) | Every town-to-town trip in the story game |
| Script jumps | `_MAP_JUMP` in town and dungeon scripts (`editloop3.cpp` 3738, `dun/movechara.cpp` 1767) | Story trips, field maps |
| Leaving a dungeon | Escape and defeat go to the town or a field map (`movechara.cpp` 2160 to 2192, 2701, 2902) | Every dungeon exit that isn't the doorway |
| Houses | `GotoInterior` (`editloop.cpp` 4024): 100-frame fade, black frame, villager textures deleted, interior loaded; leaving reloads the town script, villagers and music | Every house, both ways |
| Dungeon floors | `_LOAD_DUNGEON_MAP2` to `BtMapJumpLoad`; back floors by `GAME_TASK_URA_SWAP`; one floor per arena | Every floor in a save without Vigil World |
| Small waits | Every file read is on the game's thread: menu opens, character switch (`btitem.cpp` 98), weapon models (1242), the town autosave (`gameloop.cpp` 1087) | Hitches |

Why only two places can be alive (same survey):

- A kept place is an arena set plus a texture manager, tagged with a world number (`dataset.cpp` 68 to 192,
  `texture.cpp` 1151 to 1177). That part already takes any number of places.
- The town's *state* does not. About 300 globals in the town code (`editloop*.cpp`, `editmapscript.cpp`, `edit.cpp`,
  `editmenu.cpp`) are one-of: pointers into the arenas, the villagers, the event scripts, cameras, time of day, music.
  The dungeon has the same in `dun/gameloop.cpp`, with a single current floor.
- The door code tracks one other place (`doorway_view.cpp`: `g_last_town`, `g_last_dungeon`, one live picture).
- A kept place is drawn, never stepped: its villagers and monsters stand still.
- Nothing is ever let go: each town commits about 108 MB, and all textures share 16384 keys.

Engine limits like these are raised, not planned around.

## 3. Phases

Each phase ends playable and is checked headless before it is called built. Order is by what the player feels first.

### OW0. A mod of its own (built 2026-11-11)

`mods/moonmod.openworld` (Open World). It takes the two rules Vigil held for its own saves and gives them to any story
save: no loading card between a town and its dungeon, and a town's gate is the road. The road panel only offers what
the save's world map would (a place the story hasn't opened stays closed). Vigil stands down for whichever of the two
rules another mod holds, so both can be on.

Open World is where every later phase's rules and settings live. Engine work stays generic (ops any mod can call).

### OW1. No cards, no fades (one place alive at a time, as now)

Every trip that still loads keeps loading, but nothing stands between the player and the game for longer than the load.

1. **The card goes.** With open world on, no `MapJump` shows the card: world map, script jumps, dungeon exits, save
   load. The cut (C0) covers the load. Where a card is still shown (open world off), it lasts as long as the load, not
   6.6 s.
2. **Loads get short.** Measure each `ModeInit`; move file reads off the game's thread for what can be read ahead
   (the next town's ground and textures while the panel is open, the town while walking to the dungeon's way out).
3. **Dungeon exits walk out.** Escape powder, the floor's exit and defeat arrive at the door the party would have
   walked out of, with the cut, not at the town's default spot behind a card.
4. **Houses.** The interior gets its own NPC buffer (it shares `EdNPCBuffer` with the villagers today, which is why
   the villagers are thrown away) and its own kept world, built with the town. The door opens and the party walks in:
   the house is a doorway like the dungeon's, drawn live through its door.
5. **Floors without Vigil.** For saves that go floor by floor: the next floor is built in its own world while the
   party plays the current one, and the stairs are a doorway. Back floors the same way.
6. **Hitches.** Menu art, the other characters' models and the weapon models are kept loaded; the autosave writes on
   another thread.

Check: a probe that counts frames with the card, a fade or a held picture on screen, per kind of trip. Target: zero for
houses and floors, load-bound only for the rest.

### OW2. Many places alive

The step that makes roads possible: the town the party left is still there when they walk back.

1. **`TownState`.** The town's globals move into one structure that `SwitchWorld` swaps (the survey's list is the
   starting point). Same for the dungeon's `dun/gameloop.cpp` state, so a second dungeon, or floor, can be kept.
2. **Any number of kept places.** The door code keys places by world number, not "the town" and "the dungeon"; each
   doorway has its own live picture.
3. **Letting go.** Least recently visited places are released when memory or texture keys run short. The count is a
   setting (large on a desktop, two or three in the browser build). Arena blocks and texture managers learn to be
   freed.
4. **One party, many places.** The save's single current floor, the music, and the event scripts that re-read from
   disk on resume (`LoadScript`, `editloop.cpp` 496) are handled per place.
5. **Do kept places keep living?** See decision D3. Frozen is free; stepping the neighbours costs time each frame and
   needs the town step to be safe to run without the player.

Check: walk Norune, cave, Norune, Matataki, forest, Matataki, Norune with no reload, headless, with memory logged.

### OW3. Roads you walk

There are no town-to-town maps in the game, so these are made. Material found on the disc (run/data/gedit):

| Stretch | What exists |
| --- | --- |
| Norune to Matataki | `s41` (Norune from afar, 5500 x 4240); Wise Owl Forest's parts for a wooded road |
| Matataki to Brownboo to Queens | `s04`/`s43` Brownboo (3000 x 3000); `s09` East Harbor (6600 x 8000), `s33` harbor with houses |
| Queens to Muska Lacka | `s12`/`s32` the desert (7000 x 5260), which is also the ground outside the Sun and Moon Temple |
| Muska Lacka to Yellow Drops | `s13`/`s38` the field at Yellow Drops; `s11`. Yellow Drops is on the moon: this leg is a ride, not a road |
| Dungeon mouths | `s25`/`s29` Shipwreck, `s26` Sun and Moon Temple, `s27` Moon Sea, `s28`/`s30` Dark Heaven Castle, `s50`/`s51` Demon Shaft |

1. **A road is a place.** New map numbers for mod maps (today `locations.register` gives ten, 70 to 79, and only as
   copies of four fields; both limits go). A road has its own `mapinfo.cfg`: ground parts, collision, sky, and gates.
2. **Two ways to make the ground**, see decision D2: re-lay the game's field maps (ready art, fixed shapes), or build
   outdoor zones from dungeon part banks the way Vigil World builds a dungeon map (any length and shape, forest and
   cave art only).
3. **Gates are doorways.** A town's gate shows the road live and the party walks through; the road's far gate shows
   the next town. `world.set_roads` grows from "send an event" to "this gate leads to that place".
4. **First road: Norune to Matataki.** One road, both gates, walked both ways, before any other is drawn.
5. **Along the road.** Monsters by day and night, a shrine or a camp, chests, the map screen showing the road. These
   come after the first road works.
6. **Rides.** Where there is no land (the moon; see D4 for the sea), the trip is played: the party stands on the deck
   while the far side loads, and the view is the live picture of where they are going.

### OW4. Every dungeon has a door

1. Wise Owl's first visit: its walk-in needs real frames, so it is built over the first seconds in Matataki instead of
   in one unseen step.
2. The dungeons the world map reached (Shipwreck, Sun and Moon Temple, Moon Sea, Gallery of Time, Demon Shaft) get
   their mouth on a road or field (the `s25` to `s51` maps above), with a doorway into floor 1 and a town-side entry
   in `kTownDoors` terms.
3. Deeper floors from the door for saves without Vigil World: the floor menu at the door, then the cut; with OW1 step
   5 the walk down is unbroken anyway.

### OW5. The story in an open world

1. **Closed roads.** A place the story hasn't opened is shut in the world, not missing from a menu: a gate, a fallen
   bridge, a guard. It opens when the world map would have shown it.
2. **Arrival scenes** play where the party stands when they walk in, with no black before them.
3. **Story trips** (`_MAP_JUMP` to the field maps, the opening, Dark Heaven Castle) keep working; each is either
   walked (the field is now on a road) or shown as a ride.
4. **The world map** becomes a map: where you are, the roads, and travel to places already walked to (D5).

### OW6. One world (stretch)

Places drawn at their true positions, so the next village is seen from the road and not only through a gate: far
models for kept places, one coordinate space, loading by distance instead of by gate. Not started until OW3 has shown
what the roads feel like.

## 4. Decisions for the user

- **D1. A mod of its own, or part of Vigil?** Taken as: its own mod (Open World), so the story game gets it without
  Vigil's combat. Say so if it should stay inside Vigil.
- **D2. How roads are made**: re-laid field maps, generated outdoor zones, or both (fields for the desert and the
  coast, generated for the forest road).
- **D3. Kept places**: frozen while the party is away, or still living (villagers walk, time passes, monsters move)?
- **D4. Queens to Muska Lacka**: a coast road, or a ship from the East Harbor.
- **D5. Fast travel**: keep travel from the map to places already walked to, or walk everywhere.
- **D6. Which first**: OW1 (the cards and fades that are left, felt everywhere at once) or OW2 then OW3 (the first
  walked road, Norune to Matataki). OW3 can't start before OW2.

## 5. Rules that hold throughout

- Off in the Gauntlet and every sandbox session; floors built without zones stay byte-identical.
- Co-op: a guest follows the host between places as now. Open World is a "required" mod, so a room agrees on it.
- Nothing game-derived is shipped: a road is a recipe (which of the player's own files to lay where), not art.
- Every engine op is generic and documented in `docs/api`; recipes go in `docs/modding`.
- Each step lands with a headless check and a line in this file saying what was checked and what wasn't.

## 6. Log

- 2026-11-11: plan written from three surveys (loads and fades; kept-world state; map material). OW0 built: the Open
  World mod with its test (`tools/tests/openworld`); Vigil yields the passage and the roads to whoever holds them. The road is asked for only in a town, on ticks, so Vigil's own claim on a Vigil World save comes first. Fake-game tests: openworld 36, vigil 574, pack 55.
- 2026-11-11, OW0 in the real game (headless, `--jump e01`, the rebuilt play exe): the mod loads clean and holds
  nothing at the title. In Norune it holds the passage from before the town loads; the roads stay with the world map
  because Matataki isn't on the save's map yet. With the story's gates off the roads are held within a second,
  walking out at the gate opens "The road / Out of Norune Village / Matataki Village / Stay", and taking it arrives
  in Matataki (its arrival scene plays). With Vigil also on, on a plain story game, one panel opens (Open World's).
  Found and fixed in the engine: a held stick walked the party on under a town panel, since the pad's lock stops
  buttons only; the town walk's `keylock()` (`ebattle.cpp`) now also holds while a mod's panel or map is up.
  Not checked: the cave door walked under Open World's passage (same engine path Vigil's check walked; only who
  holds the rule was confirmed), a mid-story save with the story's gates on, a Vigil World save with both mods on
  (fake-game tests only), and a hand playtest.
- 2026-11-11, OW1 item 1, first piece (engine; patch round 51). Measured first, with the real card timing and
  `DC_PERF_TRANSITIONS=1` (which now also prints `perf held begin/end`): the card is up 397 ticks (6.6 s) for a load
  of 0.5 to 0.75 s. Found: on the road from Norune to Matataki the held picture stayed its full ten seconds (601
  ticks, ended by the timeout), because Matataki opens with its arrival scene and only walk frames let the picture
  go; the first ten seconds of the scene were hidden. Changed: `ChronicleMapJumped` holds the picture for every jump
  made from a town, a field or a floor to any town-side map (0-199) or dungeon, not only town/dungeon doors, town to
  town and floor to floor; the town loop lets the picture go four frames into its first walk or scene
  (`g_arrived_held`). Checked headless, card timing real: Norune to Matataki by the road 10 ticks held (was 601; the
  same on the rebuilt play exe), Norune to map 19 by `world.enter_map` 10 ticks, Norune into the Shipwreck 49 and the
  Divine Beast Cave 45 (as before), a Shipwreck floor out to map 19 10 ticks; no card on any of them. Engine tests
  799 pass.
  Still to do in item 1: a save loaded from the title (the card is decided before a mod can claim the passage, and
  the title is not a place to hold a picture of); the card lasting only as long as the load when open world is off.
  Not checked: the world map's own jump (same `MapJump`, by hand only), a scene's `_MAP_JUMP` with an event, the
  dungeon's leave-through-the-menu path (item 3), and the eye: these are tick counts, nobody has watched the cut.
