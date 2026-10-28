# Dark Genie's Gauntlet (`moonmod.roguelike`)

A roguelike game mode for Chronicle, started from the title menu. It has its own title screen and its own progress,
and it never touches a save file. A run goes forward through five biomes of three floors and a Warden each. There is no
way back: leaving the dungeon or falling ends the run, and Moon Shards from every run buy permanent unlocks.

It needs the MoonFactory engine with **title modes and sandbox sessions** (the Chronicle patch in `ports/chronicle/`
from this version on). On an older engine the mod loads, logs that the engine has no title modes, and stays out of the way.

## Playing

1. Enable **Dark Genie's Gauntlet** in the Mod Manager (Options > Game > Mod Manager) and restart the game.
2. On the title menu, between OPTION and EXIT, choose **Dark Genie's Gauntlet**. The title screen turns into the
   Gauntlet's own:
   - **Start Run**: a fresh game begins on the first floor of Divine Beast Cave.
   - **Starting Character**: who starts the run. Cross cycles through all six.
   - **Norune Eternal**: spend Moon Shards. Cross on an unlock shows what it does; Cross again buys it.
   - **Records**: Moon Shards, runs, wins, defeats, retreats, best depth and the Heirloom.
   - **Circle** goes back to the normal title menu. (The screen takes the keyboard and controller; the mouse cannot
     click its entries yet.)
3. Find the gate key and take the exit as usual. The exit carries you to the next floor of the run.
4. On the fourth floor, the **Warden** is the monster holding the gate key. It grows larger and stronger and gets a
   HUD bar. When it dies, the run moves you to the next biome after 5 seconds.
5. After the fifth Warden, or after a defeat, or if you leave the dungeon (exit, Escape Powder, or **Actions > Abandon
   Run**), you are back on the Gauntlet's title screen. It shows how the last run went.

The HUD shows the run in the game's own art. The floor plate reads the biome and floor (`2-3`; a Warden floor keeps
the native *Boss*), and the card shown on arriving reads the run's depth (*B6*). A cursed floor shows a small Curse
badge and the chest its Miracle cache pays beside the key; a curse waiting for the next floor blinks its badge. A Vault
turns the plate purple, as any back floor does. (An engine without HUD icons gets a text line instead.) The run's
messages pop up one at a time in the game's message window for five seconds, short, with the Curse badge or the
chest where they are about a curse or a cache. During a run, the
Journal's Character page (or the Hub's **K**) shows the run page with the Diorama and Norune Eternal trees, and the
Mod Manager's Actions tab has Run Status, the Cursed Gate, Heirloom, Gaffer and Abandon Run.

### No save file

Start Run resets the game's save data in memory, as a new game does, and starts a *sandbox session*. That session
belongs to no save slot and never saves: it never reaches a town or the save screen. When the run ends, the in-memory
save is thrown away again. Your story saves are never read or written.

### Its own game

A run is a standalone game mode: the other gameplay mods sit it out. When a run starts, RPG: Character Paths,
Ascension and Dungeon+ set every damage bonus they added back to x1, take back their HUD bars, player tuning and
Character page, and ignore the run's kills, pickups, chests and floors. They level nothing, count no stats and store
nothing. Dungeon+ also puts back the native floor layout, monster and chest counts, enemy get-up chance and enemy AI,
and rolls no tiers, mutators, bounties or champions. They pick your story game back up when the run ends.

Two things still carry over: Dungeon+'s Expanded Data weapon balance (the engine restores a weapon definition only
when the mod that changed it unloads) and its kill-count trophies (the engine advances those from every enemy defeat).
Turn Dungeon+ off in the manager for a fully native weapon table.

The Gauntlet's own progress is this mod's storage (`<save>/moonmod/...`): Moon Shards, Norune Eternal, the Heirloom,
the starting character and records. It is kept across runs, restarts and story saves. A run itself is not resumable.
Closing the game in the middle of one counts it as a retreat (its Moon Shards are kept) the next time the game starts.

## What a run has

| System | How it plays |
| --- | --- |
| Party | All six characters are in the party, but only the starting one can fight; the others start knocked out. A Golden Atla drafts and revives a random ally on floor II of the first and third biome. Switching to someone who is not drafted bounces you back (setting *Only drafted allies may fight*). Everyone starts with their first weapon, Toan's Dagger and so on. |
| Route | Divine Beast Cave → Wise Owl Forest → Shipwreck → Sun and Moon Temple → Moon Sea, or a shuffled order (*Shuffle biome order*). A late biome rolled early has weaker enemies and weaker hits. Enemy HP grows 6% per floor of depth. |
| Cursed Gate | Press **G** (or **L1+Select**, or **Actions**) on a floor to curse the *next* one. It gets +60% enemy HP and two of: Parched (water drains 3x), Brittle (wear 2x), Glass (+50% damage taken). It also gets more and richer chests. Leaving it pays a **Miracle cache** (a gem and an attachment), two extra tiles, two Moon Shards and a 35% chance of a blessing. The floor before a Warden cannot be cursed. |
| Vault | A back floor on a run floor (native back-floor key) is a Vault: 1.5x enemy HP and ABS, and a blessing when you leave. |
| Fast ABS | Revealed enemies carry 6x their ABS (*Weapon ABS multiplier*, 1-12), so weapons build up within one run. Cursed floors and Vaults give 1.5x more. |
| Shared ABS | Drafted allies on the bench get 50% of each kill's ABS on their equipped weapon, and level up from it. |
| Found weapons | A weapon picked up on a run floor arrives 1-4 levels up with 1-2 random attachments. |
| One weapon | Each character carries one weapon for the whole run. Picking up another (a chest) opens a choice over the HUD: **L1/R1** (or Left/Right) between *KEEP HELD* and *TAKE FOUND*, each line showing the stats it would end with, and **Cross** (or Enter) to confirm. The weapon not kept is absorbed into the keeper: a quarter of its attack, endurance, speed, magic and elements. A weapon for someone outside the draft is absorbed into the active character's weapon at once. |
| A broken weapon ends the run | When the equipped weapon breaks (durability 0, or a starter turned into its broken version), the run is over: it counts as a death and goes back to the Gauntlet's title. Repair Powder, Smithies, Tempered Steel and the durability unlocks are the protection. |
| Diorama | Atla picked up on run floors, cleared floors, swept floors, Wardens and caches give Georama tiles. Place them on the Diorama tree with Cross (6 plots, more with Deep Well). **Clear Diorama** puts every tile back in stock. Rivers: water drains 12% slower each. Windmill + Storehouse pairs: +25% ABS each. Lamps: +4% damage each; 1 maps every floor, 2 show monsters. Trees: 1 HP every 3 s each. Houses: -6% damage taken each. Carts: +20% Gilda each. Smithies: wear 12% slower each. |
| Blessings | Wardens, Vaults and some cursed floors grant one for the rest of the run: Moonlit Edge, Dran's Stride, Fairy Ward, Tempered Steel, Bottomless Flask, Second Breath, Lucky Star, Scholar's Eye, Mender's Charm. |
| Gilda | Every run starts with none. Floors pay 40 x depth, and enemies pay as usual. Gaffer's Wagon is where you spend it. |
| Moon Shards | 1 per floor, +2 for a cursed floor or Vault, +3 per Warden, +10 for a win. They are banked when the run ends, however it ends. |

## Norune Eternal

| Unlock | Cost | Effect |
| --- | --- | --- |
| Gaffer's Wagon | 6, 10 | On floor II of every biome: **Actions > Gaffer** sells 2 Repair Powder (300 G) or 2 Bread and 2 Tasty Water (240 G). Rank 2 is a third cheaper. |
| Macho's Forge | 4, 8, 12 | The starting weapon gets one random attachment per rank. |
| Heirloom Vault | 10 | Each Warden gives a charge. **Actions > Bank Heirloom** keeps half of the equipped weapon's attack, endurance, speed, magic and elements. They are added to every new run's starting weapon. |
| Dran's Shrine | 5, 10, 15 | +10% ABS per rank. |
| Deep Well | 5, 9, 13 | +1 Diorama plot per rank. |
| Matataki Embassy | 12 | A second ally is drafted when the run starts. |
| Moon Blessing | 15 | Every run starts with a random blessing. |
| Whetstone | 2, 4, 6 | +10 maximum durability on the starting weapon per rank. |
| Gaffer's Oil | 3, 6 | Weapons wear 10% slower per rank. |
| Repair Kit | 2, 4 | +1 Repair Powder in the starter kit per rank. |

A win earns about 45 Moon Shards, and a run that falls in the third biome about 15. Everything costs 161. The Eternal page shows six unlocks at a time; *More unlocks* turns the page.

## How it is built

**Engine (MoonFactory's Chronicle patch).** The patch adds title modes and sandbox sessions; see *Chronicle title modes
and sandbox sessions* in [docs/API.md](../../docs/API.md).

- `port/src/moonmod/title_modes.cpp` holds the registry, the mode screen's state and the session state.
- `port/src/game/title/titleloop.cpp` and `port/src/title/title_menu.cpp` draw the extra title rows and the mode screen with the game's UI framework: a stone
  plate, the game font and the title's pointing hand.
- `port/src/app/gameloop.cpp` starts a session as a new game without the story. It also sends a session's exits back to
  the title (`GameFollowMapJump`), resetting the save on the way.
- `port/src/game/dun/movechara.cpp` marks a game over as a defeat.

**Mod.** At load the mod uses `dungeons.register` to append four floors to each of dungeons 0-4: native floors 15-18
in Divine Beast Cave, 17-20 in Wise Owl Forest, and so on. Each floor copies the enemy layout of a mid-dungeon floor
that does not hold a story boss, so the native exit gate chains I → II → III → Warden. `title.mode_register` adds the
title mode, and `game.title.selected` drives its pages. `session.start` begins a run with `party_size = 6`, and the
undrafted are set to 0 HP. Between biomes the run moves with `world.transition`; `session.finish` ends it after the last
Warden, and `game.session.ended` reports how a run ended. Every other system works as in the earlier version: enemy
stats through `entities.set_stats`, player effects through combat formulas and `player.tuning_set`, weapons through
the `weapons.*` operations, and Atla through `georama.atla_list`.

## Differences from the design doc

| Design | Here | Why |
| --- | --- | --- |
| 6 biomes, Gallery of Time last | 5 biomes | `dungeons.register` only extends dungeons 0-4, and Gallery of Time is already at the 25-floor limit. |
| Boss floor per biome | Warden floor: the key holder becomes a boss | The story boss arenas are scripted by floor number, so copying them would not bring the boss. |
| Two exits per floor (normal and cursed) | One exit, plus a Cursed Gate toggle for the next floor | The exit gate cannot be duplicated from Lua. |
| Tiered enemy pools across biomes | Depth scaling, biome shuffle with scale-down | A registered floor's roster can only be replaced by mod-registered enemies whose templates are loaded on the floor. |
| Shatter drops a 50% SynthSphere; status break at +3 | One weapon each, a broken weapon ends the run, found weapons absorbed | A design change after G3: the run's weapon is the run, so durability is the pressure. |
| Build-up thresholds -35% | Not changed; fast ABS does the pacing | `weapons.definition_set` on build-up targets would collide with Dungeon+'s Expanded Data edits. |
| 8x8 Georama grid with adjacency | Diorama plots with count and pair synergies | There is no grid UI; the skill-tree page is the closest page a mod can drive. |
| Character gates guard vaults | Drafting only | Obstacles and doors are native map data. |
| Meta hub village | Norune Eternal on the Gauntlet's title screen | The title screen is the hub. A rebuilt hub town would need authored Georama towns, which the API does not offer. |

## Verified, and still to check in the game

Checked here, without the game's data:

- The engine changes build on Linux (clang 18) with the rest of the port. Six new native tests cover the registry,
  validation, ownership, screen navigation (including a mod that never answers Circle), session start and party
  setup, a queued start that can never outlive its screen, floor-to-floor and dungeon-to-dungeon moves, the defeat,
  finish and save-load endings, and the save-slot blackout. The port's whole test suite runs as
  before. The ten suites that fail here (graphics, platform) fail the same way on the untouched baseline, because
  this machine has no GPU.
- `MoonModRoguelikePackage` loads this package through the real Lua runtime and the Chronicle adapter. It registers
  all five biomes and the title mode with no warnings. It drives the pages, starts a session with all six joined and
  the chosen character active, ends it with a defeat, and checks that the title shows the result.
- `tools/tests/roguelike/test_runs.lua` (Lua 5.4+, or the vendored 5.5) plays whole runs against a fake adapter: a
  five-biome win, Norune Eternal purchases (two pages), unlocks on the next run, the found-weapon choice, absorbing, a broken weapon ending the run, drafting, a retreat, a
  defeat, Abandon, an off-route floor, quitting mid-run, a reload, an engine without title modes, and a start as
  someone other than Toan, kept through the dungeon entrance and into the next biome. 92 checks.
- `tools/tests/roguelike/test_standalone.lua` loads RPG, Ascension and Dungeon+ against a recording stub, starts a
  session in the middle of a story game and also loads each mod mid-run. It checks that every bonus goes to x1, that
  the run's events reach no game call and store nothing, and that everything comes back after. 38 checks.

Not run: the game itself, which needs your disc image and a GPU. These need a pass in the game:

- **How the screens look.** The title rows between OPTION and EXIT, the copyright banner moved down under them, the mode screen's
  layout, and how well the text reads on both PAL (480) and NTSC (448).
- **Starting straight into a dungeon from a fresh save.** `cur_georama` and party setup are covered by tests. What the
  native dungeon entrance does with no story progress is not.
- Walking the native exit from floor to floor. The registered floors are numbered straight after the retail ones and
  the exit asks for the next number, so they chain; all 20 load (G2 in `GAUNTLET.md`). The Warden floor's exit can
  only be opened after the Warden dies, and the engine keeps it on that floor.
- The Warden (its size, bar and the move to the next biome), and the weapon choice opened by a real chest, which need
  someone playing.

RPG, Ascension and Dungeon+ sit runs out (see *Its own game* above), so their pages, bonuses and floor rules do not
mix with the Gauntlet's.
