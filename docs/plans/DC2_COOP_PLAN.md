# Dark Chronicle co-op plan

The goal, in the user's words (2026-11-14): "a Co-op mode and system for it, it would require a player to be at
least at the underground waterchannel where they talk to donny for the first time to be able to play together,
would like to make it forced player one is max and forced player two is monica, if they want to swap then one
player can ask to swap characters and they would swap, i would want it to be that each player can be wherever
they want when they want but it would ask as one person enters a dungeon if the other player would like to join
and then they would be in the exact same dungeon player together. also when building georma and such it should
all be seen by both players and such as well. each player keeps there own inventory and everything. a player
would join from the start menu and load into the host world and such."

This is a plan. Nothing in it is built yet. The decisions in section 0 are settled; the next step is stage K0.

Engine paths are in the ChronicleTwo tree, branch `claude/dark-cloud-2-engine-yr3rlk` at `5122f7a4`
(`port/src/...`, `port/include/...`); line numbers are from 2026-11-14 and will drift. Script paths (`d01e01_1.c`
and the like) are the decompiled game scripts made from the user's own disc with DC2-Toolkit; they are named here
for reference and are never committed.

## 0. Decisions (settled 2026-11-14)

All seven were settled on the suggested answer ("Yeah this all sounds great"), and so was the assumption of two
players. The plan below is written to them. The other choice is kept in the table as the record of what was
turned down.

| # | Question | Decided | The other choice (not taken) |
| --- | --- | --- | --- |
| 1 | **Where exactly is the gate?** Max first talks to Donny face to face at the Channel Entrance, just before the first floor. When that talk ends Donny hands over the Classic Gun and the Help Receiver and chapter 1 starts. Donny's call on floor 1 is the next scene. | The end of the talk at the Channel Entrance (the save's story progress is 2 or more). It is in the save's header, so the Join page can show which saves qualify without loading them. | Donny's call on floor 1 (story flag 100). Needs the whole save read to check. |
| 2 | **Where are a joiner's things kept?** | In the joiner's own save. They pick one of their saves on the Join page, its bag, gear and money come along, and they are written back to that save (things only, never its story). A copy of the save is kept before the first write. | In the host's save, as Dark Cloud 1 co-op does (already built in the engine). A joiner's own save is then only used for the gate, and their co-op things exist only in that host's world. |
| 3 | **On a swap, does the gear go with the hero?** | No. Each player's things already hold a Max and a Monica. After a swap you play your own copy of the other hero, with your own gear for them. | The two heroes' worn gear trades places too. |
| 4 | **May player two move the story forward alone?** | Yes. The story flags are one shared set, whoever sets them, and the host's save keeps them. Story items go to both bags. | Only the host: player two's story triggers wait for the host. This needs every story trigger told apart from an ordinary talk, which is far more work. |
| 5 | **Chests and drops** | Each player's own: the same chest is there for both and each opens their own. Gate keys, Geostones and the floor's clear are the world's and count for both. | First come, first served. |
| 6 | **Sealed floors** (the game locks Max or Monica out of some floors) | Seals do nothing in a room, so nobody is left unable to play. | The locked-out player plays the other hero on that floor (two of the same). |
| 7 | **Photos, ideas and inventions** | Each player's own (as the engine's split has it now). Recruited townsfolk move to the world's side, since they live in the shared towns. | The world's, shared. |

Also settled: two players (the relay's rooms and the engine's avatars already take four; players three and
four would need a rule for a second Max or Monica, which this plan leaves out).

## 1. What "done" means

1. A save can host or join only once its story is past the gate (decision 1). A save that is not says why, in
   plain words, on both sides.
2. Player one (the host) plays Max and player two plays Monica, from chapter 1 on, long before the story adds her.
   Either can ask to swap, the other says yes, and they trade.
3. Each player goes where they like: another town, a house, another floor, the Georama editor. Neither waits on
   the other.
4. When one walks into a dungeon floor the other is asked to join. On yes, both stand on the same floor: same
   layout, same monsters with the same life, same doors and key, and the floor's clear counts for both.
5. A Georama part placed, moved or taken away by one is seen by the other, in the town and in its future.
6. Each player's bag, weapons, gear, money and medals are their own and are still there next time.
7. Joining is a row on the title menu: Co-op, Join, a code, and the game loads into the host's world.
8. All of it works in the browser build as well as the PC build, and a PC player and a browser player can be in
   one room.

## 2. Where things stand

More is in the tree than "nothing". The Dark Cloud 1 co-op was carried over to this engine at the operation
level (work package D of `DC2_PLAN.md`; design in `port/docs/COOP.md`, hand-off in `port/docs/coop-progress.md`).
None of it has run on the real game: "avatars, puppets, shared doors and visits are only unit-tested without
data (the headless games stay in the logo fade)" (`coop-progress.md`, "Next").

| Piece | Where | State |
| --- | --- | --- |
| Rooms through the relay (`net.*`) | `port/src/moonmod/net_session.cpp`, `net_transport_{curl,winhttp,web}.cpp` | Tested against a local relay; the web socket is linked (`port/web/web.cmake` 174) but never run |
| The save's split: world `DCW2`, player `DCP2`, town `DCT2` | `coop_save_moonmod.cpp` 67-122 | Unit tests only |
| A visit: a fresh game with the host's world, from the title | `coop_ui_moonmod.cpp` 433-462, `title.cpp` 925-931 | Unit tests only; starts only in a town's Georama map (`TownMainMap`, 186) |
| No save is written during a visit | `save_slots.cpp` 643, 655 | Built |
| Title rows for a mod (`title.mode_register`), a choice panel | `coop_ui_moonmod.cpp`, `title.cpp` 1717-1770, 1981 | Built (two rows, eight lines and eight entries a page, `port/include/moonmod/coop.hpp` 160-162); the panel does not hide its presses from the game (`COOP.md`) |
| Other players drawn (`world.avatar_set`) | `coop_world_moonmod.cpp` 66, 132-136, 380-405 | Max or Monica only, no weapon, no Ridepod or monster form (`coop_api_moonmod.cpp` 420), wearing this game's clothes |
| Monsters copied from the host (`monsters.mirror_get`, `puppet_set`, `mirror_hit`) | `coop_world_moonmod.cpp` 240-273, `monster.cpp` 2252, 2689, 2978 | Never run on a floor; a monster's blow on another player is not measured, so a guest takes no damage |
| Doors, gates, switches shared | `dungeons.shared_events_get/run` | Never run on a floor |
| The same floor from a seed (`dungeons.set_seed`) | `automap.cpp` 2465, `coop_world_moonmod.cpp` 528-545 | Covers random layouts only (see 4.4) |
| A town's Georama sent and merged (`georama.town_export/import`) | `coop_api_moonmod.cpp` 365-400, `coop_save_moonmod.cpp` 469 | Unit tests only; sent on leaving the editor, the other player's town reloads |
| Two headless games meeting | `tools/coop/two_games.py`, gauntlet gate G4 | Passes, on empty data |
| The co-op mod | `mods/moonmod.coop` | One mod for both games since K0 (co-op 0.12.0, 2026-11-14, uncommitted): the Dark Chronicle parts of MoonMod branch `claude/dark-cloud-2-engine-yr3rlk` (`f12a53b`) brought into co-op 0.11.1 (ping, rejoin, down and revive, hardening) |
| Mods in the browser build | `docs/WEB.md` 222, 238, 265 | The engine loads mods; the page has no way to add one, and co-op is listed as not done |

What the request needs that nothing covers yet: the gate, a hero per player and the swap, Monica before the story
has her, a floor that either player can own, world changes going both ways as they happen, a joiner's own save,
joining anywhere but a Georama town, and all of it on the real game.

## 3. What carries over from Dark Cloud 1, and what does not

| | Carries over | Changes for Dark Chronicle |
| --- | --- | --- |
| Transport | The relay, rooms by code, `net.*`, ping, "no signal", a guest getting back in after a drop | Nothing. The relay does not care which game it is (`game=chronicle-two`) |
| The world | The host's save is the world; a guest plays it in a fresh game that writes no world | The world goes both ways as small changes while playing, not only whole at the start |
| A guest's things | The export and import of a player's things | Kept in the joiner's own save (decision 2), not in the host's |
| Heroes | Avatars eased between reports | Dark Cloud 1 co-op is everyone as Toan. Here it is one hero each, fixed, with a swap |
| Floors | The seed per floor, monster copies, a guest's blows sent to the owner, doors, the follow offer | Dark Cloud 1's host runs every shared floor. Here whoever is on the floor first runs it, and it is handed over when they leave |
| Life and death | Down, revive, out, the party falls back to town (co-op 0.11) | The engine operations behind it (`player.down_rule_set` and the rest) do not exist on this engine yet |
| Mods in a room | The check that every game plays the same mods, the host's settings laid over | Nothing |
| Georama | Send a town on leaving the editor, merge on the host | Also live, part by part |
| Tests | The mod's script tests, the live harness's shape (two real games, a local relay, a test hook in the mod) | A new harness for this engine; scenarios also run in two headless Chrome pages |
| Missing here | | Thirst and Atla have no counterpart. About 130 operations Dark Cloud 1 has are not on this engine (`docs/C1_TO_C2_ENGINE_PARITY_PLAN.md`); co-op needs only the few named in the stages |

## 4. What the engine does (the facts the design stands on)

### 4.1 Story progress and the gate

- A save holds 2048 one-bit story flags (`bit_flag`), 128 counters (`short_flag`) and one number for how far the
  story is, `game_progress` (`port/include/savedata.hpp` 215-244; `GetBitFlag`/`SetBitFlag`,
  `port/src/platform/savedata.cpp` 84-93). A new game starts at progress 1 (`savedata.cpp` 25). The chapter
  follows from it: under 2 is the opening, 2 and 3 are chapter 1, 4 and up is progress minus 2 (`GetNowChapter`,
  `port/src/object/menu/menucommon.cpp` 564-589).
- The first talk with Donny is at the Channel Entrance (map `d01e01`, script `d01e01_1.c`,
  `talk_to_donny_or_leave_for_dungeon`). It runs while story flag 4 is set. When Max chooses to leave it clears
  flag 4, sets progress to 2, gives the Classic Gun and the Help Receiver, shows the chapter 1 title and goes to
  the dungeon. The native behind the progress write is `_SET_SAVEDATA_ETC` (`event_func.cpp` 7891-7904).
- The next Donny scene is event 100 in the channel's own script (`d01_0.c`, `play_first_floor_help_scene`): his
  call on the Help Receiver the first time floor 1 is entered. Its first line sets story flag 100, so the flag is
  set even when the scene is skipped. Nothing has to be cleared first.
- A save's header carries `game_progress` (`port/src/save_json.cpp` 1063; read back by `SaveJsonReadHeader`, 1130-1147,
  and for old image saves by `ReadImageHeader`, `port/src/save_slots.cpp` 176-212). Flags are not in the header: reading
  one from a save that is not loaded means reading the whole file (`SaveSlotRead`, `save_slots.hpp` 68).
- No operation gives a mod the story progress today (the adapter has `world.story_flag_*` and
  `world.story_value_*`, `chronicle_two_adapter.cpp` 3524-3589, and nothing for `game_progress`).

### 4.2 Heroes

- Four characters: Max 0, Monica 1, the Ridepod 2, Monica's monster form 3 (`port/include/userdata.hpp` 24-29).
- Three fields say who can be played (`userdata.hpp` 1175-1177): `party_member` (who is in the party),
  `chara_change` (who can be changed to) and `chara_change_mask` (who is masked off). `GetEnableCharaChangeFlag`
  combines them and takes out whoever the floor disables (`port/src/platform/userdata.cpp` 2921-2946). The
  Ridepod needs its own party bit; the monster form rides on Monica's.
- The story sets them with script natives (`event_func.cpp` 18218-18290: join or leave the party,
  `_SET_CHARA_CHANGE_FLAG`, `_SET_CHARA_CHANGE_MASK`). Monica joins at Sindain station (event 207, `s02b_1.c`):
  progress goes to 4 and all three fields get her bit. The same scene makes Cedric, Borneo and Erik joinable
  townsfolk. The Ridepod's joining is marked by story flag 25.
- In a dungeon L3 trades Max and Monica and R3 goes to the Ridepod or the monster form
  (`port/src/object/dun/dng_main.cpp` 2719-2752, 2908-2922). The change reloads the hero's body through the menu
  (`InitMainCharaBGCore`, `port/src/object/menu/menuchr.cpp` 7899). In a town the same button flips
  `active_chr_no` (`port/src/object/world/editloop.cpp` 1658). Monica can walk a town.
- One hero's body is in memory at a time: scene slot 0, `MainChara__2` (`port/include/dng_main.hpp` 313), built
  by `SetupMainUnit` for the active character only (`dng_main.cpp` 634, `editloop.cpp` 850).
- A new game already gives both heroes their first weapons and Monica her starting defence
  (`userdata.cpp` 2478-2512, 4455-4466), so a save at the gate has a Monica who can fight.
- Some floors are sealed against one hero (`DNGMAP_SEAL_MONICA`, `DNGMAP_SEAL_MAX`, `port/include/dngfloor.hpp`
  60-63). A seal only applies while that hero is in the party (`IsSealFloor`,
  `port/src/object/dun/dngfloor.cpp` 518-557).
- No mod operation adds Monica to the party. `party.set_active` refuses a hero who is not in it
  (`chronicle_two_adapter.cpp` 2245-2272). Debug setup can (`port/src/config_loaders.cpp` 335-368).

### 4.3 One game holds one place

- The game is one loop at a time: town and Georama (`LOOP_EDIT`), dungeon (`LOOP_DUNGEON`), title, menu
  (`port/src/platform/mainloop.cpp` 109-144, 1573-1980; `NextLoop`, 305). A house is the one case of a second
  map loaded beside the first (`port/src/object/world/mapjump.cpp` 511-547).
- A story scene is a mode inside the loop, not a loop of its own: `RunEvent`
  (`port/src/object/event/event.cpp` 137), `EDIT_CONTROL_EVENT` in a town (`editloop.cpp` 931), `DNG_STATUS_EVENT`
  on a floor (`dng_main.cpp` 2360-2370). The floor keeps stepping during a scene; only monster thinking has its
  own pause (`DNG_PAUSE_MONSTER_AI`, 1987).
- So "two players in two places" is two whole games, each running the place its own player is in. No game runs
  a place nobody is in. The world between them is data: flags, floor records, town records.

### 4.4 Floors

- A random floor's layout comes from `CAutoMapGen::RandomMapMainProc`, which takes its seed through
  `moonmod::coop::FloorSeed` and calls `srand` (`port/src/object/dun/automap.cpp` 2465-2471). That is where
  `dungeons.set_seed` lands.
- **A preset floor never reaches that line.** `CAutoMapGen::Build` picks the preset with `iRand(19) + 1` and
  returns (`automap.cpp` 2619-2656). Two games in a room can get different presets today.
- **Monsters and chests are placed after the layout, from the same single random stream.** The floor's script
  calls `place_treasure_box` and `place_monster` (`AutoSetTreasureBox`, `port/src/object/dun/dng_event.cpp` 1558;
  `AutoSetMonster`, 1803), which draw from the one global generator (`port/src/runtime.cpp` 32-39) that
  everything else draws from too. Any draw in between changes where things land.
- A floor's saved record is small: `DNG_FLOOR_SAVE` has the time of the fastest clear, the Spheda result, a kill
  count, a visit count and flags for open, clear, each medal goal, Geostone found and read, and seal cleared
  (`port/include/savedatadungeon.hpp` 31-58, 70-75; 512 records). Opened chests are not saved: they are the
  running floor's own.
- Running monsters: `CActiveMonster` with `life` and `state`, up to 128 (`port/include/monster.hpp` 64-66, 274,
  446; `capacity.hpp` 24).

### 4.5 Georama

- Five town records, `edit_data[5]`, each a `CEditData`: up to 300 parts, houses, the river grid, the place log and
  the analysis (`port/include/editdata.hpp` 279-290; `savedata.hpp` 61, 232). Parts past 300 live in the port's
  `TownLayout` (`port/src/save_json.hpp` 46). Palm Brinks has no record.
- A town's number is its map's number, 0-4: Sindain, Balance Valley, Veniccio, Heim Rada, Moon Flower Palace
  (`CSaveData::GetEditData(MapNo)`; the editor opens only on maps 0-4, `editloop.cpp` 1759-1763). It is not the
  save's `area_no` (2, 3, 4, 5, 7 for the same towns), which is what `world.get().town_map` reports.
- The record and the screen are two things. The live map is built from the record when the town is walked into
  (`EditDataLoad`, `editloop.cpp` 2578: clear every part, `LoadData`, analyse) and written back into it when the
  player leaves the editor (`EditDataSave`, 2552). The game's debug menu calls `EditDataLoad` on a town that is
  on screen, so building a town again in place is something the game itself does.
- Parts go in and out through `CEditMap::PlaceEditParts` (`port/src/object/world/editmap.cpp` 675, 689),
  `RemoveEditParts` (2484) and `DeleteEditParts` (2281). Leaving the editor saves and analyses the town
  (`EditDataSave`, `editloop.cpp` 2549-2573).
- The future follows from the analysis: `AnalyzeEditMap` per town (`port/src/object/world/editanalyze.cpp`
  82-110), the percent from `CEditData::GetAnalyzePercent` (`editdata.cpp` 423-443), which scripts read with
  `_GET_DIORAMA_PERCENT` (`event_func.cpp` 8310). Two games with the same town record see the same future.
- Parts built and waiting to be placed are a count in the save (`build_parts_num`), on the world's side of the
  split. Materials are bag items.

### 4.6 Things and saves

- Everything a player owns is one structure, `CUserDataManager` (`userdata.hpp` 1164-1196): one bag of 400
  places (unworn weapons are in it), Max's and Monica's status and worn gear (`chara_data[2]`), the Ridepod
  (`robo_data`; its core is a bag item), the monster badges, photos, ideas and inventions, money, medals,
  fishing, costumes. Only `chara_data` is per hero; the rest is one pool per save.
- The engine's split today (`coop_save_moonmod.cpp` 67-119): the world is the flags, counters, map flags,
  progress, the clock, the dungeon records, quests, the monster book, the fishing tour, the built-part count and
  the towns. The player is all of `CUserDataManager` that matters, the menu's data, and also the party fields of
  4.2 and the joinable townsfolk (`party_chara`). Not in either: play time, options, Spheda's own record
  (`SubGameSaveData`, `mainloop.cpp` 291).
- Both sides are raw structure bytes matched by size; a size that differs refuses the whole import as "another
  build" (`coop_save_moonmod.cpp` 214-216).
- Saves are JSON files, `<save root>/saves/BESCES-51190dkcl<N>.json` and `autosave.json`
  (`save_slots.cpp` 47-50, 470-476). In the browser they are in the page's private storage
  (`/opfs/chronicletwo`, `docs/WEB.md` 95-96).
- A mod is told of a changed flag, a placed part, an opened chest or a cleared floor only when a mod's own
  operation made the change (`port/src/moonmod/runtime.cpp` 975-1003). The game's own scripts and the player
  change them unseen. Co-op needs to hear those.

### 4.7 The network

- One relay, any game: `wss://<relay>/v1/host` and `/v1/join/<CODE>` with `game`, `proto` and `name`; text frames
  are the relay's own (welcome, join, leave, error, closed), binary frames are the mod's messages
  (`net_session.cpp` 102-103, 147-227). A message is at most 16 KiB (`port/include/moonmod/net_session.hpp` 21).
  When the host's connection goes the relay closes the room.
- Three sockets behind one interface: libcurl on Linux and macOS, WinHTTP on Windows, and in the browser the
  page's own WebSocket, living on the page's main thread and handing frames to the game's thread under a lock
  (`net_transport_web.cpp` 1-25). Nothing else about co-op differs in the browser.
- A browser page served over `https` can only open `wss`. The public relay is `wss`
  (`DC_COOP_RELAY_DEFAULT`, `port/CMakeLists.txt` 357).

## 5. The design

### 5.1 Two whole games, one world

Each player's game is a whole game running the place that player is in. The host's save is the world. Four kinds
of state cross the relay:

| Kind | Who decides | What | How often |
| --- | --- | --- | --- |
| **The world** | The host's game | Story flags and counters, map flags, story progress, the clock, floor records, quests, the monster book, the towns, built parts, joinable townsfolk, who the story has in the party | Whole at the join; after that each change as it happens, from either game to the host and from the host to the other |
| **A player's things** | That player's game | Bag, both heroes' status and gear, Ridepod, badges, photos, ideas, inventions, money, medals, fishing, costumes | Never sent whole in play. Written to that player's save |
| **A shared floor** | Whoever was on it first (the floor's leader) | Monsters and their life, doors and switches, the key, the clear | Fifteen times a second while both are on it |
| **Where everyone is** | Each for themselves | Place, position, heading, motion, hero and form, weapon, life | Ten times a second |

The world's side of the split grows by two things the engine has on the player's side today: the party fields
(the story's, not a player's) and the joinable townsfolk (decision 7). Story items are handled in 5.6.

### 5.2 The gate

- **Host:** the loaded save's `game_progress` is 2 or more when the room opens. Below it the Co-op row says
  "Talk to Donny at the Channel Entrance first". The engine gives the mod `progress` and `chapter` in
  `world.get`.
- **Joiner:** the save picked on the Join page has `game_progress` 2 or more in its header. Saves under it are
  shown greyed with the same line. A new operation, `save.slots_list`, gives each slot's progress, chapter and
  play time from the headers (4.1).
- The host checks the joiner's number again in the hello, so an old or changed build cannot skip it.
- With decision 1 on flag 100 instead, the joiner's check reads the whole save file. Nothing else changes.

### 5.3 Joining from the title

1. Title menu, row **Co-op** (`title.mode_register`), with two entries: **Host** and **Join**.
2. Host: pick a save. It loads as usual and the room opens; the code is on the HUD. A game already running can
   also open a room from the Mod Manager, as in Dark Cloud 1.
3. Join: pick one of your own saves (5.2), then type the code. The games check the room's mods (the check
   that exists), the build (the size check of 4.6, done first so the answer is a sentence and not a failed
   import), the protocol and the gate.
4. The host sends its world in pieces. The joiner's game starts a visit: a fresh game, the host's world, the
   joiner's own things from the picked save.
5. The joiner arrives **beside the host**: in the host's town map or house, or on the host's floor as a
   follower (5.5). If the host is in a scene, a menu or the editor, the joiner waits up to half a minute and then
   arrives at the host's last town.

The visit's start today only knows a Georama town (`TownMainMap`). In chapter 1 the host is in the channel or in
Palm Brinks, so the start has to take any map number or a dungeon floor. `world.enter_map` and
`dungeons.enter_floor` already move a running game that way (`coop_api_moonmod.cpp` 259-308).

### 5.4 Heroes and the swap

- **A room gives each game one hero.** The host is Max, the joiner Monica. A new engine piece, the room's hero
  (`party.room_hero_set {hero}` and `_clear`), answers for the three party fields of 4.2 while the room lasts:
  this game's hero is in, the other is out, L3 does nothing. As built it is a filter where the game reads those
  fields, so nothing is written: the story's own values stay in the save, the story's natives (4.2) write to them
  as always, and they are what the host's save stores and what crosses as the world.
- **Monica before chapter 2.** With the hero laid over, the joiner's game plays Monica from the gate on. Her
  body, weapons and motions are on the disc from the start and a save at the gate already has her first weapons
  (4.2). The story's scenes still show what they show: a chapter 1 scene has Max in it on both screens.
- **The Ridepod and the monster form (R3)** are the hero's own second shape, so each stays with the hero:
  whoever plays Max can ride, whoever plays Monica can transform. Each is open when the world's story has opened
  it. A player whose own things lack what it needs (the Ridepod's core and first parts, the first badge) is
  given the starting set once, because their own story may never have handed it over.
- **How the other player looks.** Avatars learn the rest: the Ridepod, a monster form, the worn weapon, and the
  other player's own clothes (sent with their position reports) in place of this game's.
- **The story's own switches.** A scene that puts a hero forward does so for its length; the room's hero comes
  back when it ends. A floor that disables a hero and a sealed floor are decision 6: nothing in a room.
- **Swap.** Either player picks "Ask to swap" (Mod Manager, and a button on the pause menu). The other gets a
  panel: "Jeffie wants to swap heroes. Swap?" On yes both games change their room hero at the next moment both
  are free (walking, no scene, no menu, not down): on a floor through the same body reload L3 uses, in a town
  through the town's. Each now plays their own copy of the other hero (decision 3). The room remembers; a new
  room starts again at host Max, joiner Monica. A swap is refused, with the reason, while either is in a boss
  fight or a scene.

### 5.5 Roaming, the dungeon question and the shared floor

- **Apart:** nothing is shared but the world and where each player is (a line on the HUD: "Monica: Sindain").
  A player alone on a floor runs it themselves, exactly as in the single game.
- **The question.** When a player walks into a floor (or picks the next one), the other gets a panel: "Max went
  into the Underground Water Channel, floor 2. Join?" It waits while the asked player is in a scene, a menu or
  the editor, and is dropped if the floor is left first. The panel has to take its presses for itself; today the
  game sees them too (`COOP.md`), so `input.block_native` is part of this.
- **On yes** the asked game goes to that floor (`dungeons.enter_floor`) with the leader's seed and arrives at
  the floor's entrance.
- **The leader.** Whoever is on a floor first runs it. The second player's monsters are copies
  (`monsters.puppet_set`), their blows go to the leader's monsters (`mirror_hit`), and the leader's monsters go
  for whichever player is nearest. Dark Cloud 1 gave every shared floor to the host; with free roaming the floor
  in progress is often the joiner's, so the floor belongs to whoever is there.
- **Arriving late.** The leader sends the floor as it stands: the seed, which monsters are dead, each living
  one's life, the doors and switches already used, whether the key is out, the floor's clock. The follower
  builds the floor from the seed and applies that.
- **Handing over.** When the leader leaves and the follower stays, the follower's copies become its own
  monsters where they stand, with the life they have. The same happens when the leader's connection drops.
- **The same floor, really.** Three fixes make the seed decide everything (4.4): the preset pick takes the seed
  too; chests are placed from a second seed made from the floor's; monsters from a third. A new
  `dungeons.layout_hash` gives a number for the built floor (cells, chests, monster kinds and spots) so both
  games, and the tests, can tell a floor that differs.
- **Blows on the follower.** The leader's monsters must hurt the other player. The leader measures a monster's
  blow against the avatar and sends it; the follower's game takes it as a monster's blow
  (`combat.strike_player`). This is the piece `COOP.md` lists as missing.
- **The world's part of a floor.** The key opens the gate for both (the door sharing lends it). A Geostone
  taken, a medal goal met and the clear are written by the leader's game and go to the world; each player gets
  the medal. Chests and drops are each player's own (decision 5).
- **Falling.** The game's rule is that a fallen hero is swapped for the other, and with nobody left the game is
  over. In a room each has one hero, so Dark Cloud 1's rule is brought across: down, the other revives by
  standing close and holding a button, out after a wait, both down means back to the town with all their
  things. The engine operations for it are built in this stage.

### 5.6 The world as it changes

- The engine tells the mod of every change the game itself makes to the world: a flag (`SetBitFlag`), a counter,
  a map flag, the story progress, a floor record, a quest, a townsperson joining, the party fields. These are
  one-line hooks in the game's units, published as the events the catalogue already names
  (`game.story_flag_changed` and the rest), which today fire only for a mod's own changes (4.6).
- Either game sends each change to the host. The host applies it (as plain data: the place it concerns need not
  be loaded) and passes it to the other game. A game applies its own change at once and does not wait.
- A change to a place the other player is standing in shows the next time that place loads, as it would after a
  scene in the single game. Georama is the exception (5.7).
- **Story items.** The game's scripts test the bag for story items, and with two bags the item may be in the
  wrong one. An item of the story's own kind given to one player is given to both, and taken from both when a
  script uses it up.
- **The clock** is the host's (`world.set_time`, as built).
- Only the host's game writes the world to a save.

### 5.7 Georama for both

- **Who pays.** A part is built from the builder's own bag. Once built it is the world's, and either player can
  place it.
- **Step one, what exists:** on leaving the editor the town is sent to the host, merged (only what changed, so
  both can build in one town), and sent on. A player walking in that town has it reloaded.
- **Step two, live (built, see K7 below):** the town is sent at each place, move and take-away. Not by hooks on
  the three functions of 4.5: the builder's game writes its live map into the record every third of a second
  while the editor is open, and the record changing is what is told. A player walking in that town sees the part
  appear or go without a reload. Still open: a player in the same town's editor seeing it too, and where the
  other's cursor is.
- **The future.** The host's game analyses the town after each change and the result is part of the town's
  record, so the percent, the conditions met and the future's maps are the same for both (4.5).
- A player standing where a part lands is moved to the nearest free spot.

### 5.8 Things and saves

- **The host** saves as always: its save is the world and the host's own things.
- **The joiner** (decision 2): things come from the picked save at the join and go back to it, things only,
  when the joiner saves, once a minute, and on leaving. The save's story, towns and dungeon records are not
  touched. Before the first write of a session the save file is copied aside. Two new operations do it without
  loading the save into the game: `save.slot_player_export {slot}` and `save.slot_player_import {slot, data}`.
- What a joiner brings home includes gear for a hero or a shape their own story has not reached. It waits there
  unused until their story gets to it.
- Gifts between players (Gilda and bag items) carry over from Dark Cloud 1 as they are, story items excepted.

### 5.9 Scenes

- A scene holds only the game it plays in. The other player keeps playing; prompts for a player in a scene wait.
- On a shared floor the leader's scene pauses the monsters for both, as the leader's pause does.
- A scene started where both players stand is offered to the other ("Watch?"). On yes their game plays the same
  event; what it sets is already set, and what it gives is given to each.
- A boss floor is entered together: the question of 5.5 says it is a boss, and the fight waits a moment for the
  answer.

### 5.10 When a connection goes

- **The joiner's drops:** the joiner keeps playing and tries to get back for two minutes (the rejoin that
  exists). Changes to the world made meanwhile are kept and sent on return. If it cannot get back, its things are
  written to its save and it goes to the title. The host plays on; a floor the joiner led becomes the host's.
- **The host's drops:** the relay closes the room (4.7). The joiner's things are written and the joiner goes to
  the title with a message. Holding the room open a little while for the host to return is a change to the relay,
  listed under later work.
- **A browser tab that is hidden** (a phone switching apps) stops the game. It is treated as a drop.

### 5.11 Transport, and the browser

- Host authority for the world, leader authority for a floor, each player for themselves. All of it as the mod's
  messages through the relay; the engine supplies operations and events, as in Dark Cloud 1.
- The same transport in the browser. What the browser build lacks is around it: a way to have the co-op mod in
  the page (no Mods card yet), saves in the page's storage proven with a real save, and a check that a browser
  build and a PC build agree on the size of the split's records (4.6), since one is 32-bit and one is not. If
  they do not, the split is given a fixed layout instead of raw bytes.
- Local tests in a browser use `http://localhost` with a `ws://` relay. The LAN page is `https`, so it needs the
  public relay or a `wss` one.

## 6. Stages

In build order. Each ends playable and is checked headless before it is called built. The harness is new:
`tools/coop/live.py` in ChronicleTwo, two real games on the disc's data through a local relay on a free port,
driven by a test hook in the mod (the shape of Dark Cloud 1's `tools/tests/coop/live`). Games start with
`--headless --jump ... --skip-events --fast-load --input <file>` (`port/src/main.cpp` 149-211;
`port/src/test_hooks.cpp` 1929-1981), and a setup file sets the story progress and flags a scenario needs
(`port/src/config_loaders.cpp` 89-92, 276-287). The same scenarios run in two headless Chrome pages against a
test server on a port of its own. With no disc present a scenario reports "not run", never "passed".

| Stage | What | Size | Check |
| --- | --- | --- | --- |
| **K0. One co-op** | Bring the Dark Chronicle parts of the branch's mod into this branch's co-op 0.11.1; one mod for both games. Regenerate the ChronicleTwo patch on the merged upstream. | S | `test_coop.lua` with both fake games; engine `ctest -R "MoonModNet\|MoonModCoop"`; `two_games.py` |
| **K1. The truth on real data** | The harness. Run what exists on the disc and fix what breaks: a visit, avatars in a town and on a floor, monster copies, doors. The three seed fixes and `layout_hash`. | L | Scenarios `meet` (both see the other's avatar move) and `floor` (same `layout_hash`, a kill on one is a death on both) |
| **K2. In the browser too** | The co-op mod in the page (built in, or the Mods card), saves in page storage, the record size check between builds. | M | `meet` in two headless Chrome pages; `meet` with a PC host and a browser joiner |
| **K3. The gate and the title** | `progress` in `world.get`, `save.slots_list`, the Co-op row with Host and Join, arriving beside the host on any map or floor, the joiner's things from and to their own save. | M | `gate` (progress 1 refused on each side with its sentence, progress 2 let in); `join_floor`; `things` (join, pick something up, leave: the save's things have it and the rest of the file is unchanged) |
| **K4. Heroes** | The room's hero, Monica from the gate, L3 off, R3 per hero with the starting set, avatars with weapon, clothes, Ridepod and monster form, the swap. | L | `heroes` (host is Max, joiner Monica at progress 2, L3 changes nothing, a swap turns it round and both avatars follow); a picture of both in the channel |
| **K5. The shared floor** | The dungeon question with its own input, leader and follower, arriving late, handing over, blows on the follower, the key and clear for both, down and revive. | L | `ask`, `late` (three dead before the join are dead after), `handover`, `hurt` (the follower loses life to a monster), `clear` (the host's save has the floor cleared when the joiner cleared it), `down` |
| **K6. The world as it changes** | The engine's change hooks, changes both ways, story items to both, townsfolk and party fields on the world's side. | M | `flags` (the joiner alone sets a story flag in another place; the host's save has it); `item` (a story item lands in both bags) |
| **K7. Georama for both** | Step one proven on the disc, then live parts, analysis on the host, the future. | L | `build` (the joiner places a house while the host stands in that town: the host's scene has it within a second, the host's save has it, both report the same percent) |
| **K8. Scenes and bosses together** | Watch offers, boss floors entered together, seals and disabled heroes per decision 6. | M | `scene` (both games play the event, the flag is set once); `boss` |
| **K9. Feel** | From `COOP_V2_PLAN.md`: the party panel, markers, pings, monster life scaled for two, a trade window; the relay holding a room for a host who drops. | M | Per item |

A hand playtest by two people follows K5 and again after K7. K3 needs K1; K2 can run beside K3 and K4.

**K0: built 2026-11-14 (co-op 0.12.0, protocol still 9, uncommitted).** The mod asks the engine which game it is
in, names Dark Chronicle's dungeons and towns, uses its town tag and arrives by the town's area. Dark Cloud 1's
path is unchanged (its live `basic` scenario passes on the merged mod). `tools/tests/coop/test_coop.lua` passes
with a Dark Chronicle section. On the merged upstream (`71ffbf72`) the engine's `MoonModNet|MoonModCoop` tests
pass 27 of 27 run one at a time (two time out when run four at once, and pass alone), and `two_games.py`
passes.

The engine work is committed in that clone (2026-11-15, Jeffie's word): `d6058ff0` on `claude/dc2-coop`, one
commit on `71ffbf72`, not pushed. The engine session's tree takes it with
`git fetch ~/dc2-coop/ChronicleTwo claude/dc2-coop`; the same commit is a file at
`~/dc2-coop/out/0001-Co-op-Dark-Cloud-2-played-by-two-on-the-real-game.patch`.

Still to do, and not co-op's alone:
- MoonMod's ChronicleTwo patch. The engine tree merged upstream `bcd19672` on 2026-11-14 (Kazarov `584cd2ef`),
  and MoonMod's two patches, `apply-moonfactory.ps1` and the README still name `7a7d7f29` and `fd72338a`: the
  pins move together, with the Kazarov patch remade against the new Kazarov (the engine's `DC2_PLAN.md` lists
  this as open for that merge). The tree half is checked: `export_moonmod_patch.py --committed --check --pin
  bcd19672` writes a 3.3 MB patch (289 files, co-op included) that applies cleanly to upstream at that pin; it
  is at `~/dc2-coop/out/moonfactory-chronicle-two.bcd19672.patch`, not in MoonMod, since half a pin move would
  leave `ports/chronicle-two` unable to apply.
- This branch's `src/`. It is far behind both engines' copies and not by co-op alone: `src/api.cpp` here has
  none of the co-op, net, session, title or mods operations either engine lists. Bringing it level is a job of
  its own.

**Where the engine work is.** A separate clone, `~/dc2-coop/ChronicleTwo` in WSL, branch `claude/dc2-coop` cut
from `71ffbf72`, nothing committed. The tree in `~/dc2-check` is not touched.

**K1, in progress (2026-11-14).** The harness is `tools/coop/live.py` in that clone: two real games on the
disc's data, through a local relay, headless at the real tick rate (`DC2_HEADLESS_BOUNDED=1`, new). The first
real runs found six things that could never have worked in play, all fixed:

| Found | Fix |
| --- | --- |
| The title's mod row could not be opened on a game without the hard disk row: the first mod row has that row's number | `title.cpp`: the hard disk branch only when that row exists |
| A world or a player's things is several hundred kilobytes as text, over the 64 KiB an operation answers | The bytes are packed before they become text (`coop_save_moonmod.cpp`); a new game's world is a few kilobytes |
| A visit could only start in a town with a Georama map, and Palm Brinks has none: nobody could join a host in chapter 1 | `session.start {visit = {map_no}}`, and the host sends its map's number |
| A visit ended in the frame it began (the game is still at the title then) | It ends on a return to the title (`coop_ui_moonmod.cpp`) |
| `dungeons.enter_floor` stopped at the dungeon's floor list | It runs the floor load event and lands on the floor |
| The host kept a guest's things only if tagged as Dark Cloud 1's | The mod checks the game's own tag |

Also built in K1: a place is the map the town runs, not its area (Palm Brinks is five maps in one area), with the
game's own name for it passed between the games (`world.get()`'s `scene_map`, `house`, `map_title`; the mod's `W`
message); `progress` and `chapter` in `world.get` (wanted by K3); the three seed fixes (`FloorBuildBegin`,
`FloorPlacing`, `FloorPlaced`) and `world.get().floor_layout`.

Scenario `meet` passes (6 checks): a guest joins a host standing in Palm Brinks from the title, and each game
shows the other's hero. Scenario `floor` passes (15 checks): the guest follows the host onto Underground Channel
floor 2, both built the same floor (same seed, same `floor_layout`), the guest's monsters are copies of the
host's, and one the host strikes down is gone from the guest's floor too. The engine's co-op tests pass 32 of 32
run one at a time, with new cases for the packing, the seeded stages and the visit's place.

Measured: a new game's world is 176,316 characters as plain text and 4,461 packed; a new game's things are
11,437 packed. The first packing (runs of zeroes only) left the world at 56,021, just under the 64 KiB an
operation may answer, because a new save is full of repeated -1 fills; the packing now writes any repeat once.

Run the live scenarios on a release build (`--build .../port/build/pc-release`): the headless renderer draws on
the processor, and a debug game manages about 4 frames a second on a floor.

Scenario `preset` runs the same on Starlight Canyon floor 1, whose floors are whole preset layouts
(`AUTOMAP_GEN_PRESET_FLOOR`): both games built the same floor there too (same seed, same `floor_layout`, 24
monsters each).

The 64 KiB an operation may take or answer is lifted to 2 MiB for the operations that carry a save's text
(`CarriesSaveText`, `lua_runtime.cpp`): a played save's photos are up to 120 KiB that no packing shrinks, and a
visit's request holds the world and the things together.

Still open in K1:

- **Doors** have not been run on the real game: a headless game has no way to walk to a door and use it. Left
  for the hand playtest, or for an operation that lists a floor's event points.
- The other player's hero is drawn without what he wears on his head (seen in `floor`'s picture); K4 covers it.
- Dark Chronicle's floors are named by the game's own numbers now ("Starlight Canyon, floor 1"); the floors' own
  names ("To the Outside World") are not shown yet.

**K3, in progress (2026-11-14).** Built:

- Engine: `save.slots_list`, `save.slot_player_export`, `save.slot_player_import` (`coop_save_moonmod.cpp`;
  `SaveSlotWriteOwnThings` in `save_slots.cpp`), with a test in `save_slots_test.cpp`: the things of a save are
  read without loading it and written back with its story, flags and towns untouched, the file copied aside
  first.
- Mod: the gate on both sides (the host's `world.get().progress`, the joiner's save, and the host checking what
  the joiner says); the Join page names the save the joiner brings and steps through those past the gate; the
  things come from that save and are written back into it every minute and on leaving; the host keeps nothing
  for such a player and does not wait on them when it closes its room. An engine without the operations keeps
  the older way (things kept by the host), so Dark Cloud 1 is unchanged.
- Live scenarios `own`, `gate` and `gate_host`.

Checked on the real game: `gate_host` (a host at the game's opening is refused a room, with the sentence),
`gate` (a joiner with no save past the gate is told why and never enters the room) and `own` (14 checks: a
joiner with a save at the gate joins with it, gains Gilda in the visit, and afterwards the save file has the
Gilda, its story still at the gate, its flags, towns and dungeon records unchanged, a copy of the file as it
was set aside, and the host's accounts empty). Every joining scenario's guest now brings a save the harness
has the game itself make.

**K4, in progress (2026-11-14).** Built:

- Engine: the room's hero (`party.room_hero_set` / `party.room_hero_clear`, `coop_party_moonmod.cpp`). It is a
  filter where the game reads its party (`GetNowPartyMember`, `GetEnableCharaChangeFlag`), not an overlay written
  into the save as section 5.4 first had it: the story's own party fields are never changed, so the host's save
  and the world it shares stay the story's with nothing to undo. The story's scripts asking who is in the party
  hear the story's answer (`StoryPartyScope` in `event_func.cpp`). Sealed floors carry no seal in a room
  (`IsSealFloor`). A visit starts as the room's hero; set while playing, the game changes hero through its own
  change (the floor's L3 path, the town's quick change) as soon as the player is free.
- The story's party fields moved from a player's things to the world, as section 5.1 says; a joiner's save keeps
  who it plays as when its things are written back.
- Mod: the host plays Max and a joiner Monica; "Ask to swap heroes" (Mod Manager, F9) asks the other player on a
  panel, and on yes both change; the host tells a joiner how the room stands, so a joiner into a swapped room
  starts as Max.
- Live scenario `heroes` (12 checks, passing): the host plays Max and the joiner Monica in Palm Brinks, from a
  save at the gate; the joiner asks to swap, the host says yes, and the host's game changes to Monica and the
  joiner's to Max while they walk.
- The other player's hero in their own gear: each game says what its hero wears and carries (`player.get`'s
  `outfit`, the mod's `O` message), and `world.avatar_set {outfit}` draws that player's hero in it, with the hat
  or hair piece and the weapons hung on the body's frames as the game hangs the hero's own
  (`coop_world_moonmod.cpp`).

- The ridepod and the monster forms, for now: the other player is shown as their hero standing in for it
  (`world.avatar_set` takes `"ridepod"` and `"monster"`), running while they move and standing when they stop.
  Before this the other player's hero froze where they had climbed in. A fall in either form is down, not out,
  like a hero's.

- Two players: the host lets one joiner in and tells a second the room is for two (`S.ROOM_FOR`; a player
  who has gone quiet for ten seconds no longer holds the place).

- Names over heads (2026-11-15): each other player's name is drawn above their hero, measured with the scene's
  own camera while the body draws (`AvatarBody::MeasureLabel`, `coop_avatar_names_moonmod.cpp`). It is hidden in
  scenes, menus, photos and the Georama editor, and when the hero is small on screen, and fades in as they come
  closer. Seen on a floor in a picture (live `look`); in town it is written but no run has put the joiner in the
  host's view. Not hidden by walls.
- The ridepod and the monster forms drawn as themselves (2026-11-15): `world.avatar_set` takes `ridepod = {leg,
  arm, body, pack}` and `form`, `player.get` says them, and the mod's outfit message carries them (nine numbers;
  a game that says four is still understood). The ridepod is built as the game builds it (below); a form is the
  monster's own model; a shape that does not load falls back to the hero standing in. A change of shape, outfit
  or hero reloads the avatar in place. Engine and mod tests; not seen live: a game started with `--jump` is in the
  debug mode, where R3 on a floor opens the debug menu instead of the change, so the test host never climbed in.
  Real play has no debug mode. Proving it needs a host started from a save through the title, or a test switch
  that leaves the debug mode once the jump is done.

Not built in K4 yet: the starting set for a player whose own things lack the ridepod's core or the first badge; a
look at every scene that puts a hero forward.

What drawing the ridepod takes (read 2026-11-15, `port/src/object/character/charasetup.cpp` 360-406, 654-729,
778-850): six models from `dungeon/robo/`, the leg as the root, then the arm, the body, Max seated ("mints", one
model per body type and outfit), the pack and Max's hat, hung on the frames `body<n>` (from the arm's part),
`spine`, `joint2`, `joint1` and `hat`, and the arm's `ude` frame given the matrix of the body's `arm<n>` frame.
The motion numbers are the leg model's, so two games with the same leg agree on them. The other game needs the
four part item numbers (`player.ridepod_get`) beside the outfit it already gets. A monster form is one model and
one config file by the form's monster id (`GetMonsterModelFile`). Neither can be checked without a save that has
the ridepod or a badge, which the live harness's saves do not.

**K5, started (2026-11-14).** Built ahead of the rest of the stage, because real play needs them:

- Blows on the follower. The game that runs a floor's monsters tests their attacks against the other player's
  hero with the game's own hit test (`AvatarHitsStep`, `CColPrim::IsHit`); what lands goes to that player's
  game, where their own hero's defence comes off it (`combat.strike_player`). Guarding and dodging are not
  weighed yet. Live scenario `hurt`.
- A panel has the pad's buttons while it is open (`PanelHoldsPad`, asked in `input/gamepad.cpp`), so answering
  "Join them?" or "Swap?" does not also swing the weapon or open the menu. The sticks stay the game's.

- The floor's leader (mod, `mon.lead`, Chronicle Two only): whoever was on a floor first runs its monsters,
  host or joiner. The one who comes second copies them as they stand, so what the first struck down stays down
  (arriving late). When the first leaves the floor the second takes it over, the monsters going on from where
  they stand (handing over). Two who take a floor in the same moment both think they lead: the host's stands
  and the joiner gives way on hearing the host's monsters. Blows go to and come from whoever leads. Live
  scenario `floor_first` (the joiner goes in alone, the host follows; 14 of 14, 2026-11-14).

- Down, not out. The mod already had the whole rule from Dark Cloud 1 (down, revived by a friend holding
  Revive beside you, out after a while, the party walking back to town when all are down); Chronicle Two had none
  of the operations it stands on, so a fall was Game Over, and for a joiner the end of the visit. Engine,
  `coop_down_moonmod.cpp`: `player.down_rule_set`, `player.revive`, `player.give_up`, `player.get().down`,
  `world.avatar_set`'s `down`, `world.get().exit_map`. The hero's death plays and they stay lying; the game's
  death event waits. Live scenario `down` (12 of 12, 2026-11-14). Revive in Dark Cloud 2 is the left stick
  click (V on the keyboard), settled with Jeffie 2026-11-15: the right stick click is the ridepod and the monster
  forms there, and the left one changes hero, which a room's one-hero rule already turns off.

- An empty floor for both needs nothing built: the follower's monsters are copies, so when the leader's last
  one falls the follower's floor is empty too. The game's own "floor cleared" script (1500) did not run at first,
  for two reasons put right on 2026-11-15: the leader's game never acted on a death asked for a monster out of its
  hero's view (`ThinkHost` skipped it; a dying monster now passes the view check), and on the follower a puppet
  the leader no longer lists kept counting (`PuppetSet` now frees it). `world.get` on a floor says
  `monsters_counted`, `mimic_chests` and `floor_cleared`. Live scenario `clear`: both games count none and both
  run 1500. The key a monster carries should drop in each game from that game's copy; not checked live.
- A monster that appears after the floor was built (an event's, a summoner's, 2026-11-15): the follower makes it
  in the leader's slot (`SetActiveMonster`'s wanted slot, `ChronicleTwoMonsterReferFor`), from the floor's loaded
  kinds, a mod enemy or the game's own refer; a kind it cannot make is refused for that slot only. Live `hurt` and
  `down` check that both games count the same monsters and the follower never says it is out of step. Proven for
  the mod's test foe; a native kind the floor never loaded goes through the game's refer, which no run has used.

Still to build in K5: doors and the floor's own scripts when the joiner leads (they are sent to everyone today,
whoever opens them; not run live yet); the ridepod and the monster forms going down.

**K6, in progress (2026-11-14).** Built:

- Engine: the shared world as it changes (`coop_register_moonmod.cpp`; `world.watch_set`,
  `world.change_apply`, `game.world.changed`). Not the hooks in game units that section 5.6 first had: once a
  frame the live save is compared with what the two games last agreed on, and each difference is one event. It
  covers story flags and counters, the story's progress, the story's party, joinable townsfolk and dungeon floor
  records (merged, so what either game did on a floor stands). No game unit is touched.
- Mod: each game sends its changes (`X kind id value`) and writes the other's; a joiner's go to the host, which
  passes them on; nothing another game sends is taken on trust.
- Live scenario `flags`.

- What the story gives (kind `gift`): an item an event script gives the player who stood in the scene is added
  to the other player's bag too, so the host's world is never short of a thing its story needs because the joiner
  saw the scene alone. It is the game's own way of giving (the ridepod's core joins the ridepod in both games; an
  item there is only one of is not doubled). Chests, floor prizes and Spheda wins stay each player's own. Engine
  and mod tests; no live scenario (no test can make the game's scripts give an item yet).

- Review fixes (2026-11-15): the story's progress only goes forward (each game keeps the higher); a townsperson
  shared between games keeps each game's own in-party bit, and a joiner's save written back keeps its own party;
  a story gift is passed on only when a story flag, counter or progress changes within five seconds of it, which
  leaves chests out (dungeon chests already were); when both change one thing in the same moment the host's value
  wins (mod, 180 frames).

Not built in K6 yet: quests and the monster book as they change; the clock is already the host's.

**K7, in progress (2026-11-14).** Built:

- The town's number put right. The mod took a town's area for its Georama number (4.5), so an edit of Sindain
  would have gone into another town's record. `world.get().georama_town` gives the number; the mod's town names
  are the five Georama towns in that order.
- Engine: `TownFingerprint` (a number for a town's record and layout); the register looks at each town every 20
  frames and tells `game.world.changed {kind = "town", id}` when it differs. A town taken from the other game
  (`georama.town_import`) is agreed as it arrives and not told back.
- Engine, live building (`coop_town_moonmod.cpp`): while the editor is open the live map is written into the
  record before each look (`TownLiveSync`), so every part is a change. A game that takes a town its player stands
  in is not walked back to the entrance any more: the record is written and the live map is built from it again
  where the player stands (`EditDataLoad`), at once if they walk free, else when the scene or menu ends or they
  come out of a house, and at the latest before the game next saves that town (`TownBeforeSave`, the one line
  added to `EditDataSave`).
- Engine: parts built and waiting (`build_parts_num`) are shared as kind `stock`, so either player places what
  the other built.
- Mod: on `town` the game sends the town as towns always went (the host its whole town, a joiner the town with
  the one it was changed from, which the host merges and sends on). Each send is measured from the town as last
  agreed, so part after part merges cleanly. A town that has to wait (the host is in that town's editor) keeps
  the oldest "changed from". The host is told once a minute who is building where, not at every part.
- Live scenarios `towns` (both in Palm Brinks, each changes another town) and `build` (both stand in Sindain,
  the joiner puts up two houses and three blocks, the host has them on its screen without moving). Both pass
  (2026-11-15): 9 of 9 and 12 of 12. `place_probe` and `georama_probe` are one game alone, for finding where a
  town can be built on.

- A player standing where a part lands is moved to the nearest walkable spot (2026-11-15, `MovePlayerAside` in
  `coop_town_moonmod.cpp`, the game's own walk check `CheckEditWalkSpot`). Live scenario `shove`.
- Review fixes (2026-11-15): the live map is written into the record before the editor opens, and never while a
  rebuild of that town waits; a town both games changed keeps its placement log, renumbered, so every part loads
  placed (proven by a real `LoadData` in a unit test); a town's save count is not part of its fingerprint; a town
  of the wrong grid size or a field given twice is refused.

Not built in K7 yet: two players in one town's editor do not see each other's parts until one leaves it, nor each
other's cursor; a player inside the editor is not moved aside; the future's maps following the town for a player
standing in the future.

Not built in K3: a Host entry on the title (a room is opened from inside the game, as in Dark Cloud 1; loading a
save from a mod's title page needs an engine piece), and arriving on the host's floor when the host is in a
dungeon (the joiner arrives in the town the dungeon is reached from and is offered the floor).

**Where it stands (2026-11-15, evening).** Every live scenario passes on the release build with the polish pass
merged (floor clear, late monsters, moved aside, names, ridepod drawing, the review's fixes): meet 7, floor 15,
preset 15, hurt 11, own 14, gate 6, gate_host 4, heroes 12, flags 7, towns 9, build 12, floor_first 14, down 15,
clear 13, shove 12, look 3, look_town 3. Mod tests 342, engine co-op tests 62 (one may abort on the Tracy
assertion, which is not co-op's). The polish pass is the engine's second local commit, `e48229e8` on top of `d6058ff0` (not pushed);
nothing in MoonMod is committed; the play copy and DC_Web are as they were. `ridepod` (a live scenario for the
ridepod drawn as itself) does not pass yet, for the debug-mode reason in the K4 note.

**After the first hand playtest (2026-11-15, night).**
- A monster one game could see was invisible in the other, though it could still be struck. The copies of the
  leader's monsters (puppets) never ran the game's own view check (`CMonsterMan::ThinkHost`'s `CheckView` and its
  fade), since their thinking is paused, so a copy that began out of view stayed faded out. `PuppetSight` in
  `coop_world_moonmod.cpp` now runs the check for each copy every frame, from this game's hero and camera, and
  `monsters.mirror_get` says `seen`. Live: the driver logs the copies near the visitor's hero and how many are
  seen; in `hurt` every one near was seen (91 of 91 looks), and `hurt` 11/11 and `floor` 15/15 pass.
- Shots and spells are seen on the other screen. The engine notes each shot this game's own hero fires (Max's
  pistol, machine gun, launcher and laser, Monica's armband magic and her magic sword's charge; `HeroFired` in the
  `Shot*` functions of `actscript.cpp`), `player.effects_take` hands them to the mod, which sends each at once
  ("F scene kind x y z dx dy dz value amount target"), and the other game draws it from that player's avatar
  (`world.avatar_effect`): the same effect, or the same bullet, grenade or beam, flying the same way. Nothing drawn
  this way strikes: no collision primitive is made for it, and an effect marked `shown_only` makes none from its
  script (`_COLPRIM_CREATE`); the hits stay the firing game's, as before. An effect the other game has not loaded
  (its own hero is the other one) is loaded on first use, as the floor's scripts load theirs. The blade's trail goes
  the same way (`HeroSwung` in `CActionChara::StepEffect`): the avatar has a trail of its own, made as the game makes
  the hero's, and starts it between the same two frames of its weapon. Live: on the visitor's floor the driver draws
  each kind from the host's avatar every five seconds; in `hurt` and `floor` every one was drawn (gun, machine gun,
  grenade, laser, trail), and both pass (11/11, 15/15). The ridepod's shots followed (2026-11-16): its rockets and
  missiles (`HeroShot::Rocket`, a missile scattered on the drawing side from numbers of its own, not the game's) and
  its laser and beam (`Laser` looks 3 and 4), besides its machine gun. Then thrown items (`HeroShot::Throw`, from
  `EntryThrowItem`, `ThrowItemObject` and `RemoveThrowItem`): the avatar holds the item up on its "item" frame, throws
  it to where it landed in the firing game, or puts it away, by the game's own thrown-item effect owned by the avatar.
  And an effect drawn only now passes that on to the effects its script starts (`_ES_CREATE`): a fireball's or a
  bomb's blast is drawn only too, where before a child effect could have struck the copies of monsters. Live (hurt
  11/11, floor 15/15): every kind drawn, 10 items held and 9 thrown in `hurt`. Not seen with eyes yet: whether the
  held item sits in the avatar's hand. Not carried: the sounds of the shots (the other hero's sound bank is not
  loaded, and the game's sounds have no place to come from). Monica's magic is
  drawn by the same path as the gun's bullet, but no live run has fired it (the harness has no way to cast).
- Two players building in one town (2026-11-16). A player in a town's Georama editor saw nothing of the other's
  parts until they left it: `georama.town_import` answered "busy" while that town's editor was open. Now the editor
  takes the town between its actions (`EditModeBetweenActions` in `editmode.cpp`: no wall being chosen, no part,
  river or removal animating, no control lock, no menu about to open; `IsEditModeTool` in `editloop.cpp`): the
  player's own parts are written into the record first, the other game's town is merged into that, and the live map
  is built again at once (`TownEditorReady`, `RebuildNow`). The editor's undo is pointed at its part's new slot, and
  how many of the held part are left is counted again (`EditModeAfterRebuild`). Mid-action it still answers "busy"
  and the mod tries again. Since a joiner's editor now takes the host's towns while the joiner builds, the host's
  answer to one part could arrive after the joiner placed the next and take that one away for a moment: the joiner
  numbers each town it sends ("#n" before it), the host's towns say the last number of that joiner's they hold, and a
  joiner holds a host town that is behind (for ten seconds at most, then the host's word stands). Live:
  `build_edit` 13/13, the host sitting in Sindain's editor while the joiner builds (the town built again in the
  editor twice); `build` 12/12 and `towns` 9/9 still pass. The story save `town:0` jumps into has Georama shut at
  that point (`MENU_DEBUG_BIT_CTRL_NO_GEORAMA`), so `build_edit` starts from the game's own Georama debug save
  (`georama:0`) and raises its progress past the gate first (coopdrive `progress`). Not tested live: the joiner in
  the editor (the "#n" hold is in the mod's tests), undo after a rebuild, and two in one editor by hand.
  On the way: a mod description over 1,024 characters makes the engine refuse the whole mod without a word in the
  log; the mod's tests now check its length.

## 7. Risks

- **Nothing here has met the real game.** K1 may find that avatars, copies or doors need rework, not fixes. It
  is first for that reason, and its size is a guess.
- **One random stream.** Every system draws from it (4.4). The seed fixes cover the layout, chests and monsters;
  anything else a floor's script rolls at its start (traps, the random circles) may still differ. `layout_hash`
  is what catches it.
- **Scripts written for one player.** About 1,400 scripts assume one bag, one active hero and Monica absent
  until chapter 2. Known traps: scenes that put a hero forward, natives that write the party fields, and native
  1263 (`_CHECK_EQUEP_CHANGE`, `event_func.cpp` 20573), which puts Monica's first weapon back in her hand
  (`CheckEquipChange`, `userdata.cpp` 4471). Each chapter needs a played pass.
- **Two games setting the same thing.** Both can start the same one-time scene in the same second, and a counter
  that is added to can be added to twice. Flags are safe to set twice; counters go through the host.
- **A joiner's save.** Writing things into a save whose story is elsewhere is new. The copy kept aside and the
  `things` check are the guard. Decision 2's other choice avoids it.
- **The browser.** A hidden tab stops the game; a phone may not hold two heavy pages' worth of memory for long;
  the record sizes may differ between builds; the LAN page cannot use a plain `ws` relay.
- **Message size.** A message is 16 KiB at most; the world (512 floor records, five towns) is sent in pieces at
  the join, and a busy floor's monster report must stay under it at 128 monsters.
- **The tree moves.** Upstream ChronicleTwo is merged in often and another session is working in the same
  tree. Hooks stay one line in game units with the body in `port/src/moonmod/`, as now.
- **Two lines of the mod.** Until K0 is done every co-op change risks landing on the wrong one.

## 8. To find out while building

These are not yours to decide; they are things the code or the game will answer.

1. Which story flag opens Monica's monster form, and what the story hands over with it and with the Ridepod (for
   the starting set of 5.4).
2. Every scene that changes the active hero or the party fields, by a search of the scripts for those natives.
3. Which scripts call native 1263, and whether a joiner's built-up sword can be lost to it.
4. How the item table marks a story item (for 5.6).
5. Whether a copy dying on the follower's game gives weapon experience and drops there as a real kill does.
6. Whether Palm Brinks, houses and the Channel Entrance take avatars (they are not Georama maps).
7. Whether the split's records are the same size in the browser build and the PC build.
8. How long the world takes to send at the join, in pieces of 16 KiB.
