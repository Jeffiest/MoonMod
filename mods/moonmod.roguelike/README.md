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
   - **Norune Eternal**: the unlock sky. See *Norune Eternal* below.
   - **Records**: Moon Shards, runs, wins, defeats, retreats, best depth and the Heirloom.
   - **Circle** goes back to the normal title menu. (The screen takes the keyboard and controller; the mouse cannot
     click its entries yet.)
3. Find the gate key and take the exit as usual. The exit carries you to the next floor of the run.
4. On the fourth floor, the **Warden** is the monster holding the gate key. It grows larger and stronger and gets a
   HUD bar. When it dies, the run moves you on after 5 seconds, to a **Rest floor** before the next biome (a setting).
   It is one quiet room, in the next biome's own dungeon: nothing to fight, no chests. It holds a healing spring
   (walk up to it: the whole party's HP, water and ailments, once per biome), Gaffer's shop by the exit, and two ways
   on. The exit gate (its key is already in your bag) leads to the biome's first floor as usual. The stairs in the side
   room ask **TAKE THE CURSED PATH?**: Proceed and every floor of that biome before its Warden is cursed, with two
   curses each and the cursed floors' rewards (richer chests, a Miracle cache each). Its Warden then pays twice: another
   Miracle cache, a blessing and three more Moon Shards. The Rest floor doesn't count toward depth.
5. After the fifth Warden the run goes down one more floor, the **Genie's Lair** (the finale; a setting). Beat the
   Dark Genie there to win. After the win, or after a defeat, or if you leave the dungeon (exit, Escape Powder, or **Actions > Abandon
   Run**), you are back on the Gauntlet's title screen. It shows how the last run went.

The HUD shows the run in the game's own art. The floor plate reads the biome and floor (`2-3`; a Warden floor keeps
the native *Boss*), and the card shown on arriving reads the run's depth (*B6*). A cursed floor shows a small Curse
badge and the chest its Miracle cache pays beside the key; a curse waiting for the next floor blinks its badge. A Vault
turns the plate purple, as any back floor does. (An engine without HUD icons gets a text line instead.) The run's
messages pop up one at a time in the game's message window for five seconds, short, with the Curse badge or the
chest where they are about a curse or a cache. During a run, **Start opens the run menu** in place of the pause:
RUN (the floor, depth and curses; curse the next floor; companion stance; abandon, with a confirmation), DIORAMA
(place tiles straight from the list, or clear it), BLESSINGS and PARTY, and GAFFER while he is on the floor. The pad
and the mouse both work it. (The old Journal page is still there as a setting.)

- **Gaffer's Buggy**: once a floor is swept, Gaffer pulls up just inside the exit. Walk up to him and his wares open
  in the run menu: Antidote, Bread, Water and Repair Powder always, and a spread of run-only wares (a weapon tune-up,
  a Diorama tile, an ally contract, a new weapon, attachments, Auto Repair, Holy Water). Gaffer's Wagon, Haggler,
  Gaffer's Stock and Gaffer's Partner improve him.
- **A found weapon pauses for a choice**: two cards, the one in hand and the one found, with what each would be after
  melting the other in. Chests never hold a weapon the party already has, and often a stronger one.
- **Vaults are free**: the back floor's stairs ask "Enter the Vault?" (enter at your own risk). Below, monsters have
  2.5x HP and hit 60% harder, and a Vault Warden guards a hoard: Moon Shards, two Diorama tiles and a blessing.
- **Wardens are true bosses**: every Warden floor has a large Warden room (6x6 where it fits), a dead end sealed until
  every monster outside it is dead. Walk in and the doors slam shut behind you as the Warden appears: half the time (a
  setting) the dungeon's own boss (Dran, cut down to fit the room, Master Utan, the Ice Queen with her spells, King's
  Curse rising from its coffin, Minotaur Joe with his wine kegs), otherwise the floor's toughest monster grown to x10
  base HP in the first biome rising to x100 in the fifth. A boss hits as hard as, and has the life of, the story boss
  whose place in the run it took (an early Minotaur Joe is fought like Dran), and every hero can hurt it: where its
  story let only one hero harm it (the Ice Queen only feared Ruby), any hero now can. It fades out with its cast when it
  falls. A boss's entrance card, a HUD bar, and the doors open when it falls.
- **The Genie's Lair**: the finale, below the last Warden, steeped in violet fog. Clear it and the sealed room holds the
  Dark Genie in his two forms, the pink Genie (hands, light, wind, beam and shockwave) and his dark elemental form
  (shades, pillars, shockwaves and beam). Each run rolls the fight: the pink Genie and then his dark form rising where he
  fell, the dark form first and then the Genie reforming, or both at once side by side with fewer spells each. Each form
  brings a random share of its spells. The pink Genie always brings both hands and his beam: break both hands to open
his eye to your blows. Beating him wins the run (+12 Moon Shards).
- **Weapon rarity**: found weapons roll Common, Uncommon, Rare, Epic or Legendary (rarer deeper, in Vaults, and
  from Wardens, who now leave a weapon behind). Each tier grows the stats (x1.0 to x1.8), shows the name in the tier's
  colour in the weapon menu and makes the swing glow in it. Rare and better carry touches: Vampire, Poison, Goo, Frost,
  Thunder Chain, Echo, Ember Burst, Gravity Well, Quake, Reaper, Gilded, Thorns, Frenzy. Epic and Legendary weapons
  are named from their touches ("Dracula's Baselard", "Frostreap Dagger"); names stay within 22 characters.
- **Legendaries**: one per character, each with a signature (Moonfang's Lunar Arc, Ninefold's Ricochet, Titanfall's
  Earthsplitter, Emberheart's Phoenix, Gaia's Sting's Venom Totem, Starfall's Starfall). Finding one unlocks it as that
  character's starting weapon on the title screen.
- **New moves**: Toan has three new animations of his own (docs/GAUNTLET_ANIMATIONS.md): the Dash Slash (attack
  out of a run: a low lunging thrust, untouchable), the Spinning Sweep (hold a charge past the jump slash, then let
  go: arms flung wide, two turns, then a slam; its hits count as charged) and the Counter Slash (attack while
  guarding: a rising cut out of a crouch). L2 is his evade: a tucked roll the way the stick points (further with
  Moonwalker), or with the stick at rest a hop back; he can't be hit during either. Either one also cuts an attack
  short once its blow has landed, a combo swing or one of the moves above. Xiao gets her own: attack out of a run
  skids into a Triple Shot (three shots fanned at once, a full gauge), and L2 tumbles the way the stick points
  (further with Moonwalker or her Tumbler signature) or, with the stick at rest, hops back loosing a shot.
- **Combos** (with New moves): A stays the light attack (the native combo). R2 is the heavy attack (Toan's Heavy
  Chop, Xiao's Heavy Shot). R2 partway through the combo is a finisher: after two swings Toan's Launcher or Xiao's
  Fan Shot (five shots), after three Toan's Spin Finisher or Xiao's Volley. Locked on, A with the stick toward the
  target lunges in (Lunge Thrust, Dash Shot) and away from it strikes while backing off (Back Slash, Retreat Shot).
  A late in a roll or tumble, or just after, follows it up (Roll Slash, Tumble Shot). R2's first-person view is off.
- **The rest of the party** (with New moves): Goro and Ungaga fight like Toan (a dash attack, a guard counter, a roll
  and backstep, an R2 slam, a Launcher after two swings and a Spin Finisher after three, a lunge and a back slash when
  locked on, a Roll Slash out of an evade); Goro's hit harder, Ungaga's spear reaches further. Ruby and Osmond fight
  like Xiao with their own orbs and bullets (a running triple, a tumble, a hop shot, a heavy cast, a Fan and a
  Volley, a dash shot and a retreat shot, a Tumble Shot). A toast lists each character's inputs the first time they
  lead a run.
- **Bosses on the loose**: on about one floor in four (a setting) one of the dungeons' bosses, with
  its cast, roams as a regular monster: 60-100% of its size with a modest HP pool and three quarters of a Warden's
  blows, never on a Warden floor.
- **Character doors and jumps**: only drafted characters' own doors and jump spots appear on a floor.
- **Shuffled floors**: the run starts in Divine Beast Cave, but every later floor before a Warden is in a dungeon drawn
  at random (a setting).

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
| Gilda | Every run starts with none. Floors pay 40 x depth, and enemies pay as usual. Gaffer's Buggy, which pulls up on each swept floor, is where you spend it. |
| Moon Shards | 1 per floor, +2 for a cursed floor or Vault, +3 per Warden, +12 for the Dark Genie, +10 for a win. They are banked when the run ends, however it ends. |

## Norune Eternal

The permanent unlocks are a night sky on the Gauntlet's title screen: seven constellations around Norune Eternal, each
a trunk that forks into build paths, each path ending in a **Keystone** that changes the rules. The full design is in
[ETERNAL_TREE.md](ETERNAL_TREE.md).

- **Moving.** The D-pad moves to the nearest node in that direction; the view follows the cursor's constellation and
  names the neighbouring ones at the screen's edges. **R2** or **Triangle** shows the whole sky. The plate at
  the bottom names the node under the cursor: rank, what it costs, what it does, what it needs and what it opens.
- **Buying.** **Cross** buys the next rank. A node opens once any node it links back to is bought, so paths branch
  rather than run in a line, and some bridge into a neighbouring constellation (Craft into the Heirloom Vault).
- **Switching.** **Square** switches a bought node off or on before a run, without touching what was bought after it.
  **L1/R1** set a ranked node to any rank owned. Two Keystones can be on at once (Third Star adds a slot); Pact
  Keystones don't use the slots.
- **Three currencies.** Moon Shards from every run; **Genie Sigils** for Keystones (1 per Warden at Heat 5+, 3 per win,
  +1 per win at Heat 10, 15 and 20); **Character Marks** for the run's starting character (1 per biome cleared), kept
  for the Signature skies.
- **Heat.** The Dark Genie's Pacts (more monsters, bigger floors, tougher enemies, thirst, wear, a lean start, angry
  Wardens, every third floor cursed) add Heat while on. Each point pays +10% Moon Shards at the end of the run.

Every node is built: 125 to buy (155 ranks) for 1,007 Moon Shards, 65 Genie Sigils and 90 Character Marks,
and Heat up to 40. Some highlights:

- **The Companion** (Allies): the first drafted ally who isn't you comes out and fights beside you. It can't be hurt,
  deals its weapon's base attack and goes after your lock-on target; with **Stances**, Actions > Companion Stance makes
  it aggressive (anything near) or passive, and it remembers the choice for later runs. Switch to it and you trade places. Keen Partner, Twin Strike and Soul Bond
  build on it. The companion only comes out with the **Companion** setting on (off by default).
- **Moonwalker** (Spirit): L2 dodges forward with a moment of invincibility; Xiao's Tumbler and Osmond's Rocket Boost
  give them their own.
- **Signature skies**, one per character, bought with that character's Marks: Toan's faster swings and stunning
  charged attacks, Xiao's twin pebbles, Goro's Ground Pound, Ruby's paired and piercing orbs, Ungaga's longer spear and
  Totem Guard, Osmond's Steady Aim and jetpack dash.
- **The Pacts**: Blind Halls (no map), Twin Keys (two key holders), Endless Maze (a fourth floor in every biome), Barren
  (no chests), Twin Wardens and the Warden's Court (five Wardens on the last floor).
- **Loadouts** (from the heart of the sky): four saved sets of switches and ranks.

**Shortcut doors.** Floors I to III (and IV) loop back on themselves: a dead-end room gets a second, locked way out
toward a far part of the floor, and its key waits in a small chest in the dead end. Reach the dead end the long way,
take the key, and the shortcut opens from inside. Each door is lit in the colour of its key (Bone, Moustache,
Shipcabin, Stone, Handle, Pitchdark, Silver), and each key's icon is drawn in that colour too
(`resources/keys/`, made by `tools/roguelike/make_keys.ps1`). One a floor, one more per Sprawling Floors rank, up to three.

The run's own Moon Shards: 1 per floor, +2 for a cursed floor or Vault, +3 per Warden (6 with Moon Tithe), +12 for the
Dark Genie (20 with Moon Tithe), +10 for a win, times the Heat, Shard Lens and Full Party multipliers. A win earns about 58 at Heat 0, and a run that falls in the
third biome about 15.

## How it is built

**Engine (MoonFactory's Chronicle patch).** The patch adds title modes and sandbox sessions; see *Chronicle title modes
and sandbox sessions* in [docs/API.md](../../docs/API.md).

- `port/src/moonmod/title_modes.cpp` holds the registry, the mode screen's state and the session state.
- `port/src/game/title/titleloop.cpp` and `port/src/title/title_menu.cpp` draw the extra title rows and the mode screen with the game's UI framework: a stone
  plate, the game font and the title's pointing hand.
- `port/src/app/gameloop.cpp` starts a session as a new game without the story. It also sends a session's exits back to
  the title (`GameFollowMapJump`), resetting the save on the way.
- `port/src/game/dun/movechara.cpp` marks a game over as a defeat.
- `dungeons.set_rest_room` builds the Rest floor (`port/src/game/dungeonmap.cpp`: a hall with the spring and an
  antechamber with the back floor's stairs, joined by the corridor with the way in and the exit), and
  `dungeons.set_backrooms` `stay` turns those stairs into a choice the mod answers itself.

**Mod.** At load the mod uses `dungeons.register` to append seven floors to each of dungeons 0-4: the Rest floor (an
empty `enemies` list), floors I to IV, the Warden floor and the Genie's Lair, native floors 15-21 in Divine Beast Cave,
17-23 in Wise Owl Forest, and so on. The Rest floor comes first, so its exit leads to floor I in the same dungeon. Each floor copies the enemy layout of a mid-dungeon floor
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
  five-biome win, the Norune Eternal sky (buying along a path, locked nodes, switching off, ranks, Keystone slots,
  Heat), unlocks on the next run, sky effects (every node, from Full Party and the Pacts to the Signature skies, the
  companion, the dodges, the fatal guards, Twin Keys, Endless Maze and the Warden's Court), Loadouts, the found-weapon choice, absorbing, a broken weapon ending the run, drafting, a retreat, a
  defeat, Abandon, an off-route floor, quitting mid-run, a reload, an engine without title modes, and a start as
  someone other than Toan, kept through the dungeon entrance and into the next biome. 183 checks.
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
