# Gauntlet log

Passes of the gate loop in [GAUNTLET.md](../../../GAUNTLET.md), newest first.

## 2026-10-28 — Key icons in their doors' colours (uncommitted)

The seven shortcut keys (items 216-222) now wear icons in their doors' colours: 32x32 keys drawn by
`tools/roguelike/make_keys.ps1` (bow, ring, shaft, teeth; outline and light-to-dark shading in the door's colour) into
`resources/keys/`, and a new engine call `items.icon_set` that puts a mod's icon on a built-in item (one mod per item,
undone on unload). In the game: all seven keys in the item bag, each in its door's colour. Engine test added; full
suite 808 passed (the 7 baseline failures); harness 189; patch applies.

Found on the way: keys given at the moment a floor is entered are cleared by the game's floor change (it drops every
key item); give them a few seconds in.


Engine (`dungeons.set_shortcuts`, `dungeons.shortcuts_get`, `game.dungeon.door_opened/door_locked`): the floor
generator records which rooms it joins, finds dead ends (one doorway), and joins each to a room three or more joins
away through another side (undoing a corridor that only came back to its own side). The new doorway becomes a native
room-gate part; its key (items 216-222, one per door) goes in a small chest in the dead end. Collision, the map and
the minimap follow the cell's part, so opening a door puts the doorway part back. Each door's frames are lit in its
key's colour (`use_color`; the ambient light made no visible difference). The native random locked room is skipped on
floors with shortcuts. The mod asks for one a floor plus one per Sprawling Floors rank (up to three) and says which
key a locked door wants.

| Check | Result |
|---|---|
| Generated | Asking for three on Divine Beast Cave 1-1 gave two (Bone Key at 2,13 and Moustache Key on one floor; one on another): a 3x3 dead end with its doorway on the east wall and a new corridor running east. |
| Locked / opened | Pass. Without the key, walking into the door sent `door_locked` (Bone Key); with it, `door_opened`, the key used, and Ruby walked through into the shortcut corridor. |
| Colour | Pass. The Bone door's cell is lit ivory; the rest of the cave is not. |
| Gauntlet alone | Pass. With only the mod asking (one a floor), floor 1-1 had a lit locked door. |
| Tests | Full suite 808 passed (the 7 baseline failures); harness 188 (scenario 21 new); patch applies. |

Found on the way: moving the player by more than a cell needs the camera moved and the cells' camera distances
refreshed, or the floor collision (taken around the last drawn view) is missing for a frame and the player falls; the
`DC_SHORTCUT_VISIT` test hook does both. Not checked in the game: the other six key colours side by side.


- **Ranged shots.** Xiao, Ruby and Osmond now fire a visible shot: a sprite from the dungeon's `basefx01` sheet (the
  one Xiao's own pebbles use), drawn in the same effects pass so it blends the same way. It flies at 5 units a frame
  from hand height to the target, and the blow lands when it arrives. Xiao: her pebble; Ruby: a larger pink one; Osmond:
  a small white one (the game's own orb and bullet are separate effect models). In the game: a test bolt drew blended in
  front of Toan (it first showed a black box when drawn in the character pass), and a real fight landed three pebbles
  from Xiao (4, 4, a kill).
- **Toan's poncho.** It is cloth, simulated each frame; the companion now steps its cloth after its body. In the game:
  after switching to Ruby, Toan stood beside her in his poncho.
- Full suite 807 passed (the 7 baseline failures); harness 183; patch applies.


A test-only driver kept the player invincible and logged the companion's blows; a temporary trace printed its
position each half second. On Divine Beast Cave 1-1:

| Check | Result |
|---|---|
| Aggressive | Pass. A monster wandered within 150 units; Osmond ran out, shot it from 45 units (12, his weapon's base attack, a kill) and came back. Ruby and Goro did the same on other runs (Ruby: 10 then a kill). |
| Lock-on target | Pass. Without a lock-on the companion stayed at Toan's side; after Circle locked on, Ruby ran out, struck twice and killed it. |
| Passive | Pass. Locked on, no strikes; the monster kept its 12 HP. |
| Trading places | Pass. Switching to the companion (Osmond) made Toan the companion; the screenshot shows Osmond locked on to a Cave Bat with Toan beside him, holding back. |

Fixed on the way: the companion only looked at monster slots 0-15, but the port has 256 (`MONSTOR_SLOT_MAX`); the
aggressive range went from 90 to 150 units (90 is about a second's walk); the stance is now kept between runs (meta).
Seen (fixed in the next entry): ranged companions showed no shot; Toan as a companion had no poncho. Not checked: the
camera never faced a blow as it landed.

## 2026-10-28 — Every Norune Eternal node built (uncommitted)

All 50 *Coming soon* nodes are in: 125 nodes to buy (155 ranks). Engine work in the Chronicle patch:

| Engine | For |
|---|---|
| `player.tuning_set`: `map_hidden`, `status_duration`, `status_immune`, `swap_delay` | Blind Halls, Hardy, Clear Mind, Swift Swap |
| `player.tuning_set`: `dodge_power`, `dodge_invincible_frames`, `dodge_hop` (L2) | Moonwalker, Tumbler, Rocket Boost |
| `player.tuning_set`: `extra_shots`, `shots_pierce`, `reach_scale` | Pebble Storm, Orb Split, Genie's Daughter, Spear Reach |
| `player.fatal_guard` and `game.player.guarded` | Second Wind, Cat's Nine Lives |
| Charged hits: `game.enemy_hit.charged`, formula filter `charged` | Charged Fury, Lightning Fang, Ground Pound, Mountain's Might |
| `dungeons.set_modifiers` chests down to -100 | Barren |
| `dungeons.floor_redirect` | Endless Maze (runs without it skip floor IV) |
| Gate keys reported as `game.item_picked_up` | Twin Keys |
| `party.companion_set/get`, `game.companion.hit`: a second character on screen, its own model and weapon arenas | The Companion path |
| Texture manager raised to 128 blocks and 512 textures | the companion's textures (72 blocks left it untextured) |

| Check | Result |
|---|---|
| `test_runs.lua` | 183 passed (scenarios 13-20 new: mod-built nodes, tuning, guards, charged hits, per-character tuning, Twin Keys, Endless Maze, the Court, the companion) |
| `test_standalone.lua` | 38 passed |
| Full engine suite | 807 passed; the 7 known baseline failures only (new tests: tuning, fatal guard, charged filter, floor redirect) |
| Patch | Applies to upstream `9418a550` (generated from the working tree; the two new companion files are intent-to-add) |
| In the game | The companion loads textured with its weapon and runs beside Toan (seen as Ungaga, Xiao and Goro on separate runs). Its combat, the dodge, the shots and the reach need hands. |

Seen but not from this work: an icon drawn over the player's head in the dungeon (present with the companion off).
Nothing is committed: the user asked to keep it uncommitted until every modifier is in and checked.

## 2026-10-28 — The Norune Eternal sky

Engine: `title.mode_set` takes a `sky` page (groups, nodes, links, captions, top lines), and the title draws it as a
panning night sky: item-box nodes in moon rings, dotted links, the cursor's constellation in view with its neighbours
named at the screen's edges, a star map, R2/Triangle for the whole sky, and the bottom plate for the cursor's node.
Cross/Square/L1/R1 send `buy`/`toggle`/`rank_down`/`rank_up`. New engine test
`MoonModTitleModes.SkyPageValidatesAndMovesByDirection`; the package test now expects the sky.

Mod: the Eternal list became the sky from ETERNAL_TREE.md: 126 nodes in 14 constellations, 75 working now (816
shards, 45 Sigils, Heat up to 23), the rest *Coming soon*. Genie Sigils, Character Marks, Heat, Keystone slots,
switching off and rank setting are in. Effects added for the new nodes (damage, crits, Moonblade, wear, thirst, speed,
HP, starting kit and purse, floor rewards, Wardens, Gaffer, the Diorama paths, the Pacts, the Heat payout).

| Check | Result |
|---|---|
| `test_runs.lua` | 114 passed (new: the sky's buying, locks, switching, ranks, Keystone slots and Heat; sky effects; Moonblade) |
| `test_standalone.lua` | 38 passed |
| Engine mod suites | 29 passed (with the new sky test) |
| Full engine suite | 803 passed; the 7 known baseline failures only |
| Patch | Applies to upstream `9418a550` |
| In the game | The sky draws and moves: heart, Arms (bottom and top), the Pacts, the map. Node labels were dropped at the user's request (the bottom plate names the node). Fixed on the way: overlapping edge names (now eight compass slots, nearest constellation each), plates under the panel (the camera follows the cursor within tall constellations), links missing from the payload, and off-screen links costing draws (5619 → 1725). |

Needs hands: buying and switching with a pad, and how the grind feels.

## 2026-10-28 — G5 endings and the meta loop, PAL: headless part done

Automated: `test_runs.lua` 92/92 (a new scenario: a fall on the third biome's second floor banks 12-18 shards; the win
check is now 40-50, the harness's win banks 46), `test_standalone.lua` 38/38. A test-only mod ended runs in the game.

| Line | Result |
|---|---|
| Endings land on the title with the last run | Defeat passes: `player.damage` to 0 ends the session as a defeat and the title reads *Fell in Divine Beast Cave ...*. A broken weapon passed in the G3 rework. Needs hands: the win, the exit gate, Escape Powder (`items.use` only uses healing, water and cures) and Abandon (the Mod Manager's Actions). |
| Quitting mid-run is a retreat, shards kept | Pass. A run left open in storage with 7 shards closed as a retreat at start-up: retreats +1, shards 0 → 7, *Left at ..., +7*. |
| Shards match the table | Pass in the harness: a clean win 46, a third-biome fall 12-18. |
| Unlocks show on the next run | Pass in the game. Macho's Forge and Whetstone bought on the title page with scripted input (200 → 194), and the next run's Gold Ring started with 1 attachment and 55/55 durability. |
| Runs to buy everything (161) | Needs hands. Estimate: about 8-10 runs for an improving player. |

Fixed on the way: the last-run line named floors the old way (*Divine Beast Cave I*); it now reads *1-1* or *Warden*
like the HUD. The Diorama tile notice ran to 79 characters (more than the message window's three lines; the harness
caught it on the runs that placed a Windmill) and is now short.

Metric audit: **4 Meta pull: 2** (each unlock changes the next run, seen in the game).

## 2026-10-28 — Run messages in the game's message window

Engine: mod notices (`ui.notify`) queue and pop up one at a time in the dungeon's own message window (bottom right,
the system message frame and font), each for its duration, counting down only while shown, and waiting while the
game's own message has the window. `ui.notify` takes an optional `icon` (a status badge or a registered png). The
Gauntlet's messages are rewritten short (three lines at most, checked by the harness), each five seconds, with the
Curse badge or the cache chest where they fit. Checked in the game: the opening ("Divine Beast Cave 1-1. Ruby sets
out."), the Cursed Gate with its badge, the chest icon, and the window gone after five seconds. New engine test
`MoonModManagerUi.GameNoticesQueueAndCountDownOnlyWhileShown`; the full suite has the baseline's 7 failures (803
pass). `test_runs.lua` 90/90, `test_standalone.lua` 38/38.

## 2026-10-28 — The Gauntlet's HUD in the game's own art

The run's HUD text line is gone. Engine: `render.hud_icon_set` (a native status badge at half size, or a mod png)
draws icons left of the key and floor plate, and `render.floor_label_set` puts a label on the plate and a number on the
arrival card. The Gauntlet's plate reads `1-2` (digits: the game font's capital I reads as l), the card *B2* (depth),
a Warden floor keeps *Boss*, a cursed floor shows the Curse badge and a new chest icon (`resources/hud/cache.png`,
drawn by `tools/roguelike/make_chest.ps1`), and a waiting curse blinks its badge. Checked in the game on DBC I and a
cursed DBC II. Engine filter plus the new render test pass; the full suite has the baseline's 7 failures (802 pass).
`test_runs.lua` 88/88, `test_standalone.lua` 38/38.

## 2026-10-28 — G4 risk and reward, PAL: headless part done (2 fixes)

Automated: `test_runs.lua` 84/84 (one new check; the fake now reports a new floor 16 frames before it builds it, as
the engine does, and two checks fail on the old mod), `test_standalone.lua` 38/38. A test-only mod moved Ruby's run
through DBC I-III; the test copy of the mod also logged its toasts and floor generation (the repo copy does not).

| Line | Result |
|---|---|
| G, L1+Select, Actions curse; `NEXT CURSED`; Warden floor refuses | G passes: *CURSED GATE* toast and the HUD reads `GAUNTLET 1-I NEXT CURSED`; G on floor III gives *The next floor is the Warden's: it cannot be cursed.* L1+Select and Actions need hands: mod bindings read scripted keys but not scripted pad buttons (`ModActionHeldInternal` reads the SDL gamepad), and Actions lives in the Mod Manager. |
| Cursed floor harder, Miracle cache on leaving | **Fixed:** the engine reports the new floor about 3 frames before it builds it. The mod saw the arrival first and spent the curse, so the floor was built uncursed: no +50% chests. The build now checks the floor the run is cursing. In the game: DBC II and III built with `chest_bonus_percent` 50 and their two curses named. The extra HP and the cache need a fight and a real exit. |
| Vault pays a blessing | Needs hands: `dungeons.back_floor_enter` queues the back floor for the next native script boundary (the back-floor key at the gate), which an idle player never reaches. |
| Diorama pieces noticeable | Needs hands: tiles are placed with Cross on Journal > Character. |
| Gaffer about once per biome | Needs hands. Estimate: floor II of biome 1 has about 40 Gilda plus drops, short of 300 for Repair Powder; biome 2 about 600 plus drops. |

Also **fixed:** every floor intro showed twice. The floor's seed changes when it is built, so the mod counted a
second arrival; the second sighting of the same floor within 2 s is now the same arrival.

Noticed: the HUD line covered the native HP readout (with `NEXT CURSED` it hid all of 90/90); fixed in the engine
(mod lines now start under the life, weapon and water block). Later the same day: in a dungeon, mod lines and notices are
drawn in the game's own HUD pass, in its lettering, with notices in its translucent help window. Moves made with
`world.transition` inside a biome (the test mod's, not a player's) pass the dungeon entrance and pay no floor rewards.

## 2026-10-28 — G3 reworked: one weapon each, a broken weapon ends the run

A design change after the G3 headless pass. Each character carries one weapon for the run, and a break ends it.
Shatter and Sacrifice are gone. A chest weapon opens a choice: keep the held one or take the found one, and the
other is absorbed into the keeper (25% of its attack, endurance, speed, magic and elements). A weapon for a character
outside the draft is absorbed into the active weapon. Three cheap Norune Eternal unlocks soften the start: Whetstone
(+10 durability per rank, 2/4/6), Gaffer's Oil (10% slower wear per rank, 3/6) and Repair Kit (+1 Repair Powder per
rank, 2/4). Everything now costs 161 shards, and the Eternal page shows six unlocks at a time with *More unlocks*.

Engine: `weapons.equip` now works in a dungeon; for the active character it reloads the model through the native
character-switch routine. A new `weapons.remove` deletes an unequipped instance. New test
`MoonModWeaponsApi.EquipsInADungeonWithAModelReloadAndRemovesTheSpare`; the weapon, API and player suites pass (20).

Automated: `test_runs.lua` 83/83 (the Shatter and Sacrifice checks replaced by the choice, absorb, break and unlock
checks), `test_standalone.lua` 38/38.

In the game (Ruby, DBC I, a test-only mod): a given Crystal Ring equipped mid-floor (the HUD weapon changed, 48/48),
the old Gold Ring removed; durability set to 0 ended the run, and the title read *Weapon broke in Divine Beast Cave I*.
The result line had cut off at *+0 shard*, so it no longer says "shards" (the total is on the line above). Both Eternal
pages draw cleanly on the plate.

Not checked: the choice screen itself, which only a real chest pickup opens.

## 2026-10-28 — G3 weapons, PAL: headless part done (1 fix); fights need hands

Automated: `test_runs.lua` 69/69 (3 new checks, 2 of them fail without the fix), `test_standalone.lua` 38/38, the
engine filter 10/10 plus a new `player.get` weapon test. A test-only mod in the test save drove Ruby's run on DBC I
and II.

| Line | Result |
|---|---|
| Wear per hit; nothing breaks at the default 3 | **Fixed.** From `hitvalue.cpp`: a hit wears `(1.5 - endurance/100) x weight`, the weight 0.8-1.8, a charged attack 3, times the run's wear. A charged hit on low endurance wears up to 4.5, and on a Brittle floor (2x) a plain combo hit up to 5.4, so a weapon at 4-5 could break outright before the threshold of 3 caught it. Shatter now also fires once the next charged hit could break the weapon, and comes back clear of that point. `player.get` now reports the weapon's endurance (Ruby's Gold Ring: 40, so 3.3: at 4 no Shatter, at 3 Shatter, checked in the game). Measured wear per hit needs a fight. |
| First Shatter between biome 1 III and biome 2 II | Needs hands. Estimate: 45 durability at 1-2 a hit is 30-40 hits, so floor I-II without Repair Powder (the kit has 2). Leveling up raises the maximum by 1-3 and does not refill. If play agrees, it lands early: consider more durability on the starter kit or a gentler threshold. |
| Burst; 75% attack; at most two | Stats pass in the game: attack 10 → 7 → 5, max durability 45 → 33 → 24, back to 11 then 8, and a third drop to 3 does not shatter. The burst needs enemies in range (hands). |
| Found weapon 1-4 levels, 1-2 attachments | The mod reacts to a chest pickup, which needs hands. The calls it makes work in the game: a given Gold Ring went from level 0 to 3 and both its sockets took an attachment. |
| Benched allies level by the end of biome 2 | Needs hands. In the game: Goro, drafted by the Golden Atla on floor II, has his weapon recorded for the shared ABS, and every benched weapon takes ABS (30 of 32-45 to the next level). |
| Different builds | Needs two players. |

Sacrifice: the engine side works (a +8 unequipped ring synthesized). Metric audit: G3's metric (2, Build within a
run) needs the hands-on lines; not scored.
Next: the *(hands)* lines of G2 and G3, then G4.

## 2026-10-28 — G2 floor chain, PAL: headless part done (3 fixes); Warden lines need hands

Same build and data, plus the engine guard below. Automated: `test_runs.lua` 66/66 (3 new checks), `test_standalone.lua`
38/38, engine filter 10/10 (1 new test). Scripted input can't walk a floor to its exit, so a test-only mod in the test
save (not shipped) moved the run floor to floor with `world.transition` and logged each arrival.

| Line | Result |
|---|---|
| Native exit chains I → II → III → Warden | Headless half. The registered floors sit straight after each dungeon's retail floors (DBC 15-18, Wise Owl Forest 17-20, Shipwreck 18-21, Temple 18-21, Moon Sea 15-18) and the native exit sets the current floor + 1 (`_SET_FLOOR_LEVEL`), in place, keeping the character. All 20 floors load, with 15 enemies each and no crash. Walking an exit is left for a hands-on pass. |
| Warden: key, size, bar, next biome in 5 s | Not checked. `entities.query` lists only the monsters loaded around the player, so the key holder (and its Warden scaling and bar) appears once the player reaches its room. The floor shows the native *Floor Boss* plate, because it is the dungeon's last floor. |
| Warden floor's exit before the Warden dies | Safe: the Warden holds the key. **Fixed:** in the 5 s between its death and the move to the next biome, opening the exit would have asked for a floor past the floor tables. The engine now keeps a mod's last floor's exit on that floor. |
| Source floors play no scripted event | Pass, all five biomes. A registered floor copies only its source floor's enemy layout; story events key on retail floor numbers. |
| Shuffle: weaker late biome, right HUD line | HUD half passes (a Temple start reads `GAUNTLET 1-II` on Temple II). The weaker enemies need combat. |

Fixed besides the guard:
- **The dungeon entrance read as off route.** The launch and every move to the next biome re-enter the dungeon
  through its entrance, which reports floor 0 for about 7 s. The mod paused the run and toasted *This floor is off
  the Gauntlet route* (in G1 too, hidden under the floor intro). It now waits the entrance out while it is moving the run.
- **The next biome opened as Toan.** Re-entering the dungeon loads Toan, so a run started as anyone else bounced
  back with a *not drafted* toast at each biome. The mod now switches back to the last drafted character quietly.
  The fake engine models both (a 30-frame entrance with Toan loaded), and three new checks fail without the fixes.
- **"Sun & Moon Temple" drew as "SUN ? MOON TEMPLE":** the overlay font has no "&". It is now "Sun and Moon Temple".

Noticed, not failures: the mod's HUD line sits over the native HP readout's first digits, and the native HUD numbers
registered floors after retail's (*Floor 16* on DBC I).

Metric audit: **1 No way back: 2** so far (every exit ends the run or moves it on; the Warden's exit can't skip a biome).
Next: the *(hands)* lines of G2, then G3.

## 2026-10-28 — G1 run start, PAL: PASSED (after one fix)

Same build and PAL data as G0. Automated: `test_runs.lua` 63/63 (one new check, below), `test_standalone.lua` 38/38,
engine filter 9/9. Headless runs now pass `--show-fps --screenshot-fps`: without them the screenshot leaves out the
overlay, which is where mod HUD lines and toasts draw.

| Line | Result |
|---|---|
| Start Run from a fresh install lands on DBC floor I | Pass. No story save in the folder. The toasts read *THE GAUNTLET OPENS: 5 biomes* and *DIVINE BEAST CAVE I (depth 1/20)*, the HUD line `GAUNTLET 1-I`, and the starter kit (2 bread, 2 water, 2 Repair Powder) arrives. Cross to control: about 7 s of game time (Cross on tick 900, the HUD is in by about tick 1320, after the native walk down the entrance stairs). |
| Six in the party, draft enforced | Pass. The character ring shows all six; the undrafted are at 0 HP and dimmed, and the game refuses to switch to them. The mod's own bounce stays as the backstop. **Fixed:** the native dungeon start always loads Toan, so every run with another starting character opened with *Toan is not drafted for this run. Back to Xiao.* The mod now switches to the starting character quietly in its first-floor setup. The fake now starts every dungeon as Toan too, and a new scenario checks a Xiao start has no bounce. Re-checked in the game with Ruby. |
| First weapons | Pass, all six: Toan Dagger (258), Xiao Wooden Slingshot (300), Goro Mallet (315), Ruby Gold Ring (332), Ungaga Fighting Stick (348), Osmond Machine Gun (364). |
| Story save byte-identical; RPG and Ascension sit out | Pass. With a copy of a real story save (`saves/1`, `saves/autosave`, `state.json`) and RPG and Ascension (`moonmod.adventurer`) enabled, the save files hash the same after a run, and nothing of RPG's or Ascension's shows mid-run. Over every run, only the Gauntlet's own `storage.json` changed. |

Noticed, not failures:
- The native HUD shows *Floor 16* on Gauntlet floor I, because registered floors take native numbers after a
  dungeon's own. Worth a look in G2 (the mod's own line says `1-I`).
- With a story save present, the title cursor starts on CONTINUE, so the Gauntlet row is two presses down, not three.
- Each run closed by quitting is counted as a retreat on the next start, as designed (25 runs started over G0 and G1: 24 retreats, the 25th still open in storage).

Metric audit: **5 Clean sandbox: 2** (saves untouched, other mods sit out). No other metric touched.
Next: G2 (the floor chain).

## 2026-10-28 — G0 playtest, PAL: PASSED (after one fix)

Patched Chronicle `9418a550`, `Dark Cloud (Europe) (En,Fr,De,Es,It).iso` extracted with `dcdata`, a fresh save
folder with only `moonmod.roguelike` installed and enabled, English set in `config.json` to skip the language
screen. Each line was checked on screenshots of headless runs driven by `--input` scripts (pad buttons, then the
same with `key:Down`, `key:Return`, `key:Escape`), 640 x 480 logical, shown at 1280 x 960.

| Line | Result |
|---|---|
| Row between OPTION and EXIT, banner clear | Pass. START, CONTINUE, OPTION, *Dark Genie's Gauntlet*, EXIT at 28 apart; the trademark lines sit below EXIT with room to spare. |
| Mode screen reads cleanly, no pop | **Failed, then fixed.** Upstream's UI font is larger and its translucent plate draws taller than asked, so the old fixed layout left Norune Eternal and Records outside the plate and the hint above the entries. The screen is now laid out from its content on the stone plate (heading, lines, entries, hint at the bottom). Opening it is a clean cut: the plate is whole from its first frame. |
| Keyboard and controller, Circle back | Pass. Down moves the hand, Cross or Return cycles Starting Character (Toan to Xiao, kept across a restart in the mod's storage), Circle or Escape returns to the title menu with the hand on the Gauntlet row. |
| Mod disabled: native title | Pass. START, CONTINUE, OPTION, EXIT and the banner in its native place. |

Not checked: the mouse (a known gap), and how the screens look on real NTSC (out of scope).
Metric audit: G0 touches none of the five metrics directly; no score recorded.
Next: G1 (Start Run from a fresh save into Divine Beast Cave floor I).

## 2026-10-28 — G0 automated on the new master, Windows

The patch was ported to Chronicle `9418a550` (master after `d3666bcb` forked the game into `port/src/game`) and
Kazarov `b619d1a`. Both patches apply cleanly to an untouched checkout. Built with `build.bat windows-x64-release`
(its pinned llvm-mingw, Rust and FFmpeg), then `DC_BUILD_TESTS=ON`.

| Check | Result |
|---|---|
| `darkcloud`, `darkcloud_tests`, `dcdata` build | Clean |
| Engine filter (`MoonModTitleModes*:MoonModRoguelike*:MoonModWorldTransition*`) | **9 passed, 0 failed** |
| Full suite, patched | 818 tests: 794 passed, 17 skipped, 7 failed |
| Full suite, baseline (unpatched `9418a550`) | 683 passed, 18 failed |
| Failures on the patched build that the baseline passes | **None** |
| Lua harness | 62/62 and 38/38 |

The 7 patched failures all fail on the baseline too: three `PlatformMc` seek tests, two `LocalizeLanguages` export
tests, `LocalizeOptions.TheExportListsTheOptionStringsWithTheShippedText` and `DataRead.MetadataSnapshotsStayFresh
WhenDisabled`. The baseline's other 11 (`PlatformPad.InputBindings`, 10 `PlatformMouseLook.*`) pass with the patch.

Found and fixed during the port, beyond moving code:

- `LocalizeOptions.ShippedTranslationsHaveExactlyTheCodesKeys` (failing on the old base too): the patch shipped
  translations for the aerial and fit-to-screen dungeon map but no option rows. Both are now Options > Game rows.
- The enlarged item tables (32 mod weapon slots) leaked into upstream's new item documents and read `PriceList` past
  its end. The documents now cover the retail rows only, and `PriceList` has room for the mod slots.
- `scanRoomInfoWork` was 16 x 16 while the room scan indexes up to 48 x 48 on mod floors; it is now sized and reset
  for the full room area.
- `MoonModLocationsApi` left the data reader indexed on a deleted folder, which broke a later localization test.
- Upstream's native autosave writes nothing during a sandbox session, so a run never saves.

Not carried over: the floor-build diagnostics (`DC_MAZE_DUMP`, the pit report and the maze ground probe). They
only logged.

## 2026-10-28 — G0 automated, Windows (on `6ec3b808`, before the port)

Chronicle `6ec3b808` + `moonfactory-chronicle.patch` + `moonfactory-kazarov.patch` (both applied cleanly with
`apply-moonfactory.ps1`), MoonFactory at `bc7d524`. Built in `E:\Gauntlet-build` with llvm-mingw (clang, 2026-09-22
ucrt), Ninja, RelWithDebInfo, SDL 3.4.18, Vulkan SDK 1.4.363, on a machine with a GPU.

| Check | Result |
|---|---|
| Patched `darkcloud_tests` build | Clean |
| Engine filter (`MoonModTitleModes*:MoonModRoguelike*:MoonModWorldTransition*`) | **9 passed, 0 failed** |
| Full suite, patched | 622 tests, 104 suites: 607 passed, 8 skipped, 7 failed |
| Full suite, baseline (unpatched `6ec3b808` + Kazarov `a78762c` only, since plain `6ec3b808` does not build) | 522 tests, 69 suites: 494 passed, 8 skipped, 20 failed |
| Failures on the patched build that the baseline passes | **None** |

The 7 patched failures, all failing identically on the baseline: `PlatformMc.SeekMovesPositionForReadAndWrite`,
`PlatformMc.SeekRejectsBadFileAndOrigin`, `PlatformMc.EndReturnsZeroAndKeepsOpenFiles`,
`PathsXdgDarkcloud.DarkcloudNamesTheDirectoryToExtractTo`, `LocalizeOptions.ShippedTranslationsHaveExactlyTheCodesKeys`
(fr_fr carries `dungeon_aerial_map` and `fit_dungeon_map` keys the code lacks), and
`AreaCard.TranslatedLettersUseTheWholeRetailBox` / `TranslatedWordsKeepTheRetailBoxAlignment`. The baseline's other 13
(`PlatformPad.InputBindings`, 10 `PlatformMouseLook.*`, 2 `DataRead.Paths*`) pass with the patch.

Verdict: G0 automated is **green**. G0 playtest is next (title rows on PAL, the mode screen, Circle back, mod off), with
`Dark Cloud (Europe) (En,Fr,De,Es,It).iso`. NTSC checks are dropped.

Before the playtest: Chronicle master moved 74 commits past `6ec3b808` (to `9418a550`), including `d3666bcb`, which
forks the game into `port/src/game` and removes `PORT_OVERRIDE`. The patch is being ported to it, and G0 automated
re-runs on the new base.

## 2026-10-28 — Lua harness, Windows (provisional)

Branch `claude/roguelike-gauntlet-continue-w0c9ci` at `bc7d524`. Vendored Lua 5.5.1 built with LLVM clang.

| Check | Result |
|---|---|
| `test_runs.lua` | 62 passed, 0 failed |
| `test_standalone.lua` | 38 passed, 0 failed |
| Engine filter (`MoonModTitleModes*:MoonModRoguelike*:MoonModWorldTransition*`) | Not run on Windows yet (last run: Linux, clang 18, 9 passed) |
| Playtest | Not started |

Verdict: no gate signed. G0 is next: apply the Chronicle patch, run the engine filter, then the title-screen playtest.

## Opar

Graded against [docs/OPAR_VERIFICATION.md](../../../docs/OPAR_VERIFICATION.md) (13 metrics, 1-10; pass: average 8.5,
none under 7, metrics 5, 7 and 11 at 8 or more).

### 2026-10-29: after phase 2 (model and paint), headless only

Build: Chronicle checkout with the override fix, run as `darkcloud_test.exe`; `art/opar/build/c07d.chr` loaded in
Toan's slot by a test mod. Gates O1 passed; O2 headless lines passed, its two *(hands)* lines open.

| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | Average |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 7 | 7 | 6 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 7 | 1 | 1 | 2.8 |

Under 9, what raises it: the reasons are in the grade table of OPAR_VERIFICATION.md.

### 2026-10-29: model reworked (one sculpted skin, 15,072 triangles), offline and renders only

Not loadable yet: "arena ... allocation overflow" in the character model buffer (0x33450 quadwords); raising it is
requested of the phase 3 session. Offline: every triangle, UV and weight in the pack; textures within 2 levels.

| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | Average |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 8 | 7 | 7 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 3 | 1 | 1 | 2.6 |

### 2026-10-29: Opar's six staff models

`art/opar/make_staffs.py` + `tools/chr/build_weapon.py` on template `c01w05`: all six packs exact (1,048-3,424
triangles, 90-255 KB). Tidecaller registered with `model = "opst06"`, given and equipped on Toan in a headless run:
drawn in hand and swung. Metric 8: 4. Average 2.8 (8, 7, 7, 1, 1, 1, 1, 4, 1, 1, 3, 1, 1).

### 2026-10-29: after phase 3 (the seventh slot), headless

Build: the Chronicle checkout with the seventh slot, linked as `darkcloud_slot7.exe`; the Gauntlet with its **Opar**
setting on (Full Party unlocked so all seven are drafted); the 21:08 rework of `c07d.chr` and a 128 px portrait.
Gate O3 passed:
- Engine: `SeventhCharacter.*` (7) and `MoonModPlayerPartyApi.*`: 13 of 13. Full suite 819 passed, failures only the
  baseline's 7.
- Harness: `test_runs.lua` 348 passed (scenario 25: a party of seven through all five biomes); `test_standalone.lua`
  38 passed.
- The rework's "allocation overflow" is gone: the weapon and effect model buffers now take what the carved arena
  leaves (840,000 quadwords), not what the PS2 figure (210,000) leaves. His pack: 207,891 quadwords.
- Playtest: switched to and from him on I, II, III, Warden and Vault floors of all five biomes, with the wheel and
  the API; wheel, Allies ring, weapon page, HUD and the run menu's Party tab show him (name, portrait, HP 90).
  Found and fixed: no HUD for him (a six-character bound in `topStatusInfo`), and three more such bounds.
- Story save: every file under `saves/` byte-identical after a Gauntlet run with him and after loading file 1.
- Soak: 142,440 frames (about 40 minutes of game time), 62 floors, 512 switches (128 to him): no crash.

| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | Average |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 8 | 7 | 7 | 1 | 1 | 1 | 1 | 4 | 1 | 7 | 8 | 1 | 1 | 3.7 |

Under 9, what raises it: 10 (Integration, 7): a round framed portrait like the six's, his own voice and battle-menu
line (36), and the companion taking him. 11 (Stability, 8): frame time measured beside Toan, and a companion of him
on screen. The others as in OPAR_VERIFICATION.md.

### 2026-10-29: the reworked model seen in his own slot

`darkcloud_slot7.exe`, a private copy of the run save with the Gauntlet's Opar setting on, switched to him in a
dungeon: front by a torch (folds, lips, strap, sash, wraps, frills read as the concept) and from behind in a fight
(idle, walk and swings deform cleanly; in shadow the hide reads nearly black). Metrics 1-3 are now graded in game,
unchanged (8, 7, 7). Average stays 3.7.

### 2026-10-29: the slot opened up for more characters

At the user's request (room for more heroes than Opar), the fixed seventh slot became a registry: a mod registers up
to ten playable characters past the six with `characters.register_playable` (id, name, pack, portrait, the character
he fights as, start HP and defence), and the Gauntlet registers Opar as the first (index 6). Built as
`darkcloud_roster.exe`.
- Engine: `PlayableRoster.*` (9 tests, two registered characters and a third through the API) and
  `MoonModPlayerPartyApi.*` pass. Full suite 823 passed, failures only the baseline's 7.
- Harness: `test_runs.lua` 350 passed (Opar through the registry; no registration, no Opar); `test_standalone.lua` 38.
- Headless, with a test mod registering Opar and "Kit" (fights as Ruby): a party of eight, switches through both
  with their own HP, an eight-place wheel, the dungeon menu as Kit, Kit attacking as Ruby on Opar's pack.
- Found and fixed: a pack on another skeleton than its `fights_as` character's crashed on Ruby's raised-hand model;
  a registered character now borrows such files from that character's own pack.

Metric 10 (Integration) and 11 (Stability) stand at 7 and 8; the average stays 3.7.

### 2026-10-30: Opar's feet reworked

The feet were long flat paddles with the toes fused by the webbing and no heel. Now a thick ankle, a round heel, an
instep sloping to the ball, the foot turned out 20 degrees, four arched toes fanned wide with round pads, webbed at
their bases (`art/opar/make_opar.py`, `art/opar/previews/opar_feet.png`). The body stays at 15,072 triangles; the
pack rebuilt (3,077,712 bytes) and shipped to the mod and the play copy. In game (`darkcloud_roster.exe`, his own
slot): the heel and the rounded toes show at idle. Seen from behind only; the camera follows him.

### 2026-10-30: Opar's legs apart

The thighs were thick enough to cross the middle with the hips only 0.8 apart, so the legs fused into one block.
His hip frames (`chn5`, `chn22`) now sit 1.5 out (`art/opar/proportions.json`): the bones in `opar.blend`, the
pack's frame records and its bind pose all moved (`chrtool.move_joints`, `set_frame_translations`), and the thighs
are slimmer on the inside. Read back from the built pack: frame and `.bbp` both at 1.5. In game
(`darkcloud_roster.exe`, his slot): a gap between the legs at idle with the back flap hanging in it; running, the
legs swing apart without tearing. Pack 3,071,984 bytes, shipped to the mod and the play copy.

### 2026-10-30: the shin wrap stuck out

With the legs apart, the left shin's wrap reached across to the right leg as a flat plate: its points were found by
rays cast inward from 2.6 out, and on the inner side those started inside the other leg. Wraps and straps
(`spiral_wrap`, `surface_ring`) now find the limb's surface from its own axis outward (`Surface.around`). Seen from
eight sides in Blender and in game: the wrap sits on the shin. Pack 3,070,640 bytes, shipped to the mod and play copy.

### 2026-10-30: Opar's base motions (phase 5, first part)

`tools/anim/opar_moves.py` rewrites his pack's motion timeline from Toan's (884 frames, 41 channels, one key a frame;
read back within 5e-7): his posture on every native motion (squat 2.0, lean 9 degrees, wide bowed legs, feet keeping
their turn), the staff upright outside the attack stretches, and his own idle, walk and run. The pack build puts the
saved motion file back (checked: identical after a rebuild). In game (`darkcloud_roster.exe`, his slot, the test
camera pulled back with `render.camera_set`): the idle squats wide with the staff planted beside him; running, he
hops (a crouch, a push-off with the legs stretched behind, a landing crouch); the combo still swings the staff. Not
yet seen in game: the walk, hits, the knock-down and death (they have his posture over Toan's). Still to make: his
attack motions (spits, Bubble, the kit, the Jump Slam). New abilities added to the plan: Tongue Lash, Croak, Leap
Strike. Pack 3,709,008 bytes, shipped to the mod and the play copy.

### 2026-10-30: Opar's spits

On Toan's controls, as separate moves (the user's choice): A,A,R2 Spit (two globs), A,A,A,R2 Gob (three fanned 14
degrees), a charge let go Bubble (one big slow glob, 2.4x), L2 at rest Back Hop (a hop back with a glob at the top).
Each has its own motion (`tools/anim/opar_moves.py --anims`, `resources/anims/opar_*.json`, starting and ending on
his idle). Engine: a move's shot can name where it leaves from (`from`, `from_ahead`, `from_rise`: his head, 2.6
ahead), its `basefx01` cell and size (8, the blue blob, 2.2; the Bubble 4.0), and a `burst` played where it lands.
In game (`darkcloud_spit.exe`, his slot): the back hop carries him back with a glob flying off; the Bubble leaves his
mouth as a big blue blob, hits the wall and bursts in blue sparkles; A,A,R2 throws two globs that flash on the wall.
Not yet seen in game: the Gob's fan (A,A,A,R2), a glob hitting an enemy. `test_runs.lua` 359 passed (new: his four
moves, their motions and the globs' look); `test_standalone.lua` 38; `darkcloud_tests` all but the 7 known
failures. The Chronicle patch is not regenerated yet (the Gauntlet session has its own changes in the same tree).

### 2026-10-30: Opar's frog kit

Six more moves for him, each with its own motion (`opar_moves.py`'s `kit_pose`): run+attack Belly Slide (a dive onto
his belly, lunge 4.5, two low hits with knockback 6), guard+attack Staff Swat (the staff held out flat through one
spin, two ring hits), L2 with the stick Frog Hop (a long invincible hop), attack late in an evade Leap Strike (a high
leap, a staff bonk on landing, then a glob), locked on with the stick away + attack Tongue Lash (a thin hit 34 ahead
whose first enemy is yanked in with `entities.knockback`, then a staff bonk), R2 at rest Croak (half the gauge, a
ring that stuns what it reaches for 90 steps). The lash and the croak's effects ride on `game.player.move` and
`game.enemy_hit` (FORM.kit). The moves went past the engine's 64 per mod (70), so the cap is now 160 (adapter,
patch, API doc, fake game). In game (his slot, the test save with `enforce_draft` off): the slide drops him low with
the staff out ahead, the hop leaves the ground and lands crouched, the croak throws his head back. The swat, the lash
and the leap strike are checked only headless. `test_runs.lua` 376 passed; `test_standalone.lua` 38.

### 2026-10-30: Opar's Jump Slam and Opar Form

A charge held to the top (1.5) with a full gauge is his Jump Slam (`opar_jump_slam` motion: a crouch, a high leap
with the staff raised, a landing that drives it down; a ring hit of 2.5x, knockback 8, an explosion), listed ahead
of the Bubble so shorter charges stay the Bubble. Once it lets go of him he becomes the Opar monster for 12 seconds:
new engine call `player.form_set` (the active character's model reloads from a mod pack, with stand-in frames for the
names the player code looks up, the weapon hidden; `form_clear`, a new floor and unloading give his own model back).
The pack is the monster's own (`art/opar/make_form.py`: `info.cfg` renamed `base.cfg`, its motion table remapped to
Toan's 41 numbers: the spit for swing 1 and the press for swing 2). In the form: 40% less damage (a player formula),
R2 a body press, run+attack a belly flop; a puff of sparkles in and out; the slam comes back a minute after.
`test_runs.lua` 383 passed (new: the slam's place and cost, the form's pack and stand-ins, its damage and moves, its
end and the slam's return).
In game (his slot): the charge leaps him up and the landing explodes; "Opar Form!" and he is the monster, drawn at half
its size (`player.form_set` `scale`; at full size it filled the screen); R2's body press leaps and slams with an
explosion; 12 seconds later a puff of sparkles and he is himself. Fixed on the way: the slam's 600-step cooldown held
every move through the form (mod moves share one cooldown), so it is 20 now and the minute is the mod's. The idle is
the monster's own and barely moves; the A spit (its gill spit) is subtle. `test_runs.lua` 387; engine tests: the
moves test now checks the 160 cap, only the 7 known failures left.

### 2026-10-30: the Jump Slam as one slam

The user's call: he shouldn't walk about as the big Opar, only slam down as him. Now the top charge leaps him up (his
own `opar_jump_slam`, ending high), and at the top a cloud of smoke (new burst `smoke`: the bomb's smoke puffs, added
over the scene, quick to thin); he is the monster (`player.form_set`, half size), which at once (`player.move_play`,
new: a mod's own move started from Lua) plays its press from mid-air and its getting up (the form pack's motion 24,
frames 138-180): a 3x ring hit with knockback 9 and an explosion on landing. Once it has let go of him, a puff of
smoke and `form_clear`. The 12-second form, its damage cut and its spit, press and flop moves are gone. In game
(slam3 frames): leap, smoke, the monster drops and slams, gets up, a puff, small Opar again, about 3 seconds in all.
`test_runs.lua` 384.

### 2026-10-30: Opar's staffs

His six staffs are his weapons now: registered at load when he is (`weapons.register`, template 262 whose `c01w05.cfg`
their models hold, owner Toan, attack 8 to 56), each with its model (`resources/opar/opstNN.chr`) and a 32x32 icon
rendered from its mesh (`art/opar/make_staff_icons.py`). He starts with the Driftwood Staff (his first weapon traded
for it, named by a plain record); any weapon that comes to him becomes the staff of the dungeon it came in (Reed in
Wise Owl Forest, Coral in the Shipwreck, Bog Oak in the Temple, Moonpearl in the Moon Sea and below) before its rarity
rolls; Tidecaller is his Legendary (Frost, Echo, Riptide). The Gaffer sells Toan none of them. Each staff's own line
leads its card. Effects: every Bubble splashes those round what it hits for half (Bog Oak 40% wider); Reed globs 20%
faster (MOVES follow the staff he holds); Coral globs go on to one more foe; Moonpearl brings the Jump Slam back 20 s
sooner; Riptide splits a glob that hits into three. In game: the Coral Staff given and equipped is in his hand and
swings. `test_runs.lua` 390 (new: the six registered with models and icons, the Driftwood start, a found weapon
becoming a staff, the Bubble's splash).

### 2026-10-30: Opar in the menus

The item menu crashed opening on him: it reads each character's menu model from commenu/dungeon/c0Nmodel.pak and he
had none. Now he has one (`art/opar/make_menu_pack.py`: his model, texture and skin with a short standing/down
motion), registered characters' menu packs are mod files (`IsPlayableCharaPack`), a missing one leaves the model out
instead of crashing, his finer model gets more room, and the read buffer doubled. The weapon menu built Toan's
weapons in his place (EnterWeaponModel turned him into Toan before reading his slots), so it never loaded a staff's
model and crashed leaving it; it now reads his own slots, and a registered weapon's menu model goes by its template's
cfg (WeaponNames). The item menu's status panel draws a mod weapon's own icon. His portrait is now his face in the
round medallion the six have (`art/opar/make_medallion.py`), in the Allies ring and card. In game: the item menu
shows his model, his staff's icon with its attack; the weapon menu draws the Coral Staff on its card; the Allies ring
and card show his medallion. An engine test that counted all registered content now counts its own georama pieces
(the bundled Gauntlet's staffs were in the count). `test_runs.lua` 392; engine tests 7 known failures.

### 2026-10-30: the staffs' own words in the weapon menu

`weapons.register` takes a `description` (a string or up to 4 lines); a registered weapon without a style now goes by
its own name in the menus and shows its description on the weapon menu's card, not its template's ("Crysknife",
"Crystal Knife, stylet with magical power"). Each staff registers two lines: what it looks like and what it does.
In game: the Coral Staff given directly shows "Coral Staff" on its plate and its card. Engine tests 7 known
failures; `test_runs.lua` 406.

### 2026-10-30: Opar's hurt, knock-down and death; his Signature sky

His own motions over Toan's numbers 4, 6, 7 and 23 (`opar_moves.py` hurt, knocked, defeated): a recoil with the throat
puffed; thrown back onto his back like a flipped frog, legs kicking, then rocking up, rolling forward onto all fours
and hopping up; struck, swaying, toppling back to lie belly-up with his legs splayed (the menu pack's "down" too). In
game: knocked to 0 HP he plays the death and lies belly-up. His Signature sky, shown with the Opar setting (seven
skies round the ring): Big Mouth (Gob of five), Bog Hop (a slowing puddle where the Frog Hop lands), Spitter (+20%),
Old Toad (the Jump Slam heals a quarter of his HP), King of the Moon Sea (the slam back in 30 s, 50% wider). New
scenario 25b checks each; `test_runs.lua` 413. Sounds: `tools/snd/extract_bank.py` decodes a bank's samples to WAV;
the Opar monster's set (304) is the same file as the Statue Dog's (303), so his croaks have to be picked by ear.

### 2026-10-30: Opar's voice

None of the game's own sounds fit (the user listened to the Opar monster's set), so his voice is CC0 frog sounds from
OpenGameArt (EZduzziteh's "Frog Croaks" and "Ribbit Frog Sounds", `art/opar/sounds/CREDITS.md`). `art/opar/make_voice.py`
builds `voice106.snd` on Toan's bank: the same header (so every voice cue keeps its slot), each of the nine samples
replaced by a croak or ribbit of like length, matched in loudness, encoded to PS ADPCM (37-45 dB back from the
source). Engine: `CharaVoiceSet` gives a registered character his own set (100 + index) when his mod supplies it, and
the voice cue table for a set past 100 is his fight-as character's (set 106 read past the 11-entry table and
crashed on the first cue: fixed). In game: voice106 loads and his attacks' cues play without a fault (not heard,
headless). Engine tests 7 known failures; `test_runs.lua` 415.

### 2026-10-30: Opar joins; Opar as the companion

His star: the first Moon Sea Warden (native dungeon 4) a run beats sets meta.opar_met ("A new star rises in the
Allies: Opar of the Moon Sea."), and *Opar of the Moon Sea* (`oparstar`, 30 Moon Shards, after Matataki Embassy)
shows in the Allies; bought, every run has him (ROSTER.wanted: the setting or the star). His Signature sky is always
defined now and, like the star, hidden until he is met or the setting is on (`reveal`); a hidden node can't be
bought. The companion: engine `party.companion_set` takes a registered character (his own pack, moving and
fighting as his fight-as character) and an optional `shot` (a basefx01 cell and size: from range); the Gauntlet gives
Opar his glob (cell 8, 2.0). In game: requested as the companion with Ruby leading, he comes out and follows her.
Scenario 25c: the star hidden, met, bought, in the next run; Opar the companion with his glob. `test_runs.lua` 426.

### 2026-10-30: Opar's first balance pass

`tools/roguelike/move_table.lua` prints every character's mod moves from the mod itself (the fake adapter): damage
in weapon attacks, steps, cooldown, gauge, and damage per second if used back to back. Opar was behind everyone on
his finishers (Spit 1.20/s, Gob 1.33 against Toan's 1.58 and 2.20 and the shooters' 2.36 and 3.37). Raised: Spit's
globs 1.3 each (1.95/s), Gob's 1.5 (2.50/s), Bubble 3.0, Belly Slide 1.6 + 1.2, Staff Swat 1.3 + 1.1, Big Mouth's
five globs 1.1 (3.06/s, under the shooters' Volley). He thirsts 30% slower (the plan's frog). His health and
defence stay as planned (90, 21); his staffs keep their attack curve. The field ability is dropped. `test_runs.lua`
426. Floor clear times still need play.

### 2026-10-30: Opar's medallion without Toan

The user saw Toan round Opar's portrait: the medallion's rim was Toan's own cell scaled up, and the band at its edge
holds the edge of Toan's picture (his bandana, his skin). `art/opar/make_medallion.py` now takes nothing from the six's
picture: his face fills the circle as theirs do, with a dark outline and a faint highlight inside it. In game (the
video save's Allies screen): his card and his place on the ring show only his face. The video save's mod copy and the
play copy are synced (also bringing the Move tips setting to the play copy).

The user found his staffs tiny in the video. They were made at Toan's sword's size (13-15 units; he stands about 16),
so in his hand they stopped at his eyes and read as twigs. `art/opar/make_staffs.py` now writes them 1.45 times bigger
(`SCALE`; the paint is unchanged): 19-21 units, the hook or crown past his head and the butt toward the ground, as in
the concept. The menu draws weapons at the holder's size (Toan's, for him), so the longer staff overflowed its frame:
`weapons.register` takes `menu_scale` (engine: `MoonModWeaponMenuScale`, applied in `PortDrawAallWeapon`; adapter,
fake game, `docs/API.md`), and the staffs register with 0.7. In game: idle and swat show the new size; the weapon menu
fits it in the frame. Engine tests 7 known failures; `test_runs.lua` 426, `test_standalone.lua` 38. Patch regenerated
and checked; play copy (mods and exe) synced.

The user said he doesn't hold the staff right. At rest his grip sat at hip height close to his body (7.1 up), so the
longer staff's butt went a unit into the floor across his right foot and the staff leaned out over it. In
`tools/anim/opar_moves.py` the rest hand (`hold`, idle, walk, hop, and the kit's `HAND`) is now out beside his belly
(-4.4, 8.0, 1.6) and `STAFF_UP` straighter: the butt rests on the floor (0.3) beside the foot, the top at 20. Motions,
attack animations and the menu pack (`c07model.pak`, his idle) rebuilt. In game: idle from the front (fist round the
rope grip, staff planted upright), the run (carried upright at his side), a combo. Play copy synced.

**Opar, the user's play notes (2026-10-30).**
- Chest and Atlamillia scenes garbled: his shadow model (Toan's) played Toan's own motions, standing tall through the frog, and in close-ups it showed round his head. `opar_moves.py` now writes the shadow's motions (c07s.mot) from his poses; `build_character.py` puts them back. Not yet seen at a chest in game.
- No lock-on: the engine's lock range and height tables are six long, and he is index 6 (read past the end). They now look up through CombatChara (gameloop.cpp, monstorunit.cpp).
- Item menu:
  - his name on the panel (CharaNameLine for registered characters);
  - his own title under his picture ("Moon Sea Frog Mage", `register_playable{title}`);
  - the staff named as itself, not "Crysknife": registered weapons have their own message number, and their name and description lines are served from `weapons.register`;
  - the weapon page has room for him (70);
  - his face in the weapon menu's row (SysChara had six entries).
  All seen in game. Registered character name lines moved to 31000 (2006 is the system file's "Dark Power").
- Motions:
  - the staff a unit further forward, clear of his right knee (1.7 from it, was 1.0);
  - the knees bowed out less at rest;
  - his left hand out from his belly;
  - the run with the feet closer and the knees less bowed;
  - the leap 14 frames with no hang at the top, and the slam joined later (0.24) and faster (0.7): about 12 frames sooner from leap to explosion.
  Seen in game.
- Engine tests: 827 plus the 7 baseline failures. test_runs 448, standalone 38. Patch regenerated; play copy (mods and exe) synced.

**Opar story, S3 (2026-10-30).**
- **Built:**
  - mod Atla spheres in the engine (the floor's sphere table 8 -> 16);
  - the script patcher `tools/stb/stbpatch.py`;
  - baby Opar's packs;
  - Toan's house patched;
  - the story mod `moonmod.opar`.
- **Checked in game (the story test exe):**
  - a mod sphere put at Toan's feet and opened with the game's pickup ("'Baby Opar' acquired.");
  - the mod told;
  - the story mod putting his sphere on the floor.
- **Not checked:** the house scene (no story save with the cat's element placed yet).
- Engine tests: 829 plus the 7 baseline failures (ModAtla new). Patch regenerated with the new files (`git add -N`). Play exe synced. The story mod is not in the play copy.
- Opar story house scene seen in game via `--jump house:i01h01@150` (new developer jump), and "Opar House Test.bat" in the play folder. The party after the scene is Toan, Xiao, Opar. Town model size limit raised to 16 MiB for his grown pack. Engine tests 829 + 7 baseline; test_runs 448. Patch and play exe synced; `moonmod.opar` copied to the play mods.
- The user saw grown Opar clipping into the bed after the change.
  - Tried behind Toan (x 16, z -30, then x 9, z -27): both touched the bed's head end.
  - Left of Toan: out of every shot.
  - Now on open floor by the bed's foot (36.5, 37.6, -16), turned toward Toan (-1.8). In every shot he is in: clear of the bed, and Xiao moves in front of him.
  - Play mods synced.

### 2026-10-30: Opar's staffs in the story
- `moonmod.opar` registers all six staffs (its own `opsz01`-`06` models), each building up into the next (`weapons.build_up_register`), Driftwood given when he joins.
- Sold in the shops that sell Toan's swords: Reed in shop 1 (900), Coral and Bog Oak in shop 8 (2400, 4200), Moonpearl in shop 10 (7000). Tidecaller only by building up the Moonpearl. Headless run: the shops list them at those prices, no errors.
- Engine: a registered weapon's shop price started at 0; it now copies its template's price, and `shops.set_price` (and restores, chest values) reach the registered slots 377-408. `shops.register_item` takes `shop_no`/`id` and `item_id` (API.md said `shop`/`item`; fixed).
- Chests: new `dungeons.chest_weapons_add` / `chest_weapons_clear` (engine `MoonModChestWeapon` in itemdata, called after `DngChestWeapon` in `buildEventData`). Once he has joined, a chest weapon is 15% a staff: Reed from the cave's 8th floor, Coral in Wise Owl, Bog Oak in the Shipwreck, Moonpearl in Sun and Moon. Engine test `ModChestWeapon` passes; in game the calls are accepted.
- Fixed: his join and sphere notices used `text`/`frames`; `ui.notify` takes `message`/`duration_frames`, so they never showed.
- Not seen in a menu yet: the build-up page showing the next staff (the engine test covers the link); a staff in a chest.
- Patch regenerated and checked; play exe and mods synced.
- Shop clash (the Gauntlet session spotted it): Expanded Data rewrites shops 0-17 with `set_items` each day, and `register_item` claimed the shop, so whichever mod came first locked the other out. Now `register_item` claims nothing; additions are kept apart and put back after any `set_items`. Checked in game: a second mod's `set_items` on shops 1 and 8 succeeds and the staffs are still there after.

### 2026-10-31: Opar fixes from play (weapon screen, his staff's row, grip, cloth, feet)
- Weapon screen (L1/R1 between faces): it wrapped at a hard-coded 6, so Opar's face showed but could not be reached. Now it wraps at the party's places (`CharaSlotsInPlay`); the mouse's face click wraps the same way.
- His staff could not be put down in another slot of his row: the staffs were registered as Toan's (`owner = "toan"`, he fights as Toan), and the weapon page only takes a weapon in its owner's row. New: `weapons.register` takes `owner = "opar"`, a registered character. The weapon stays Toan's to the combat code (`weapons.get` still says `owner = "toan"`, so the Gauntlet's `fights_as` filters are unchanged) and gets a holder (engine `MoonModWeaponHolder`), which `WhoIsWeaponEquip` and `CheckWeaponUser` return. So it sits in his row, chests and pickups put it there, and the "can't carry more" line uses Toan's. Both mods' staffs now say `owner = "opar"` (one word in the Gauntlet's `main.lua`, line 3615). Engine test `ModWeaponHolder` passes.
- Grip: his right hand is now a fist closed round the staff's line (`make_opar.py` `fist()`). It was an open, flat hand beside the staff. The chest strap's first point was being found on the raised fist (a stretched sliver showed as a brown rod at his shoulder); it now falls back to a ray from inside the chest.
- Loincloth: the flaps' lower part follows the thigh behind it (`loin()` weights), so his legs no longer push through it in the hop.
- Feet: `flat_feet` turned each foot the way Toan's pointed. In the run his left foot was 68 degrees out (the "bowed" foot); at idle they were -15 and +23. Both now turn out 10 degrees. Attack motions regenerated into both mods.
- Rebuilt and copied into both mods: `c07d.chr`, `c07model.pak`, `e04c07opar.chr`, and the attack motions. Checked in game from behind at a run: the feet are even, the cloth hangs clear, no rod. The fist is checked in Blender renders, not yet close up in game.
- Patch regenerated; play exe and both mods synced.

