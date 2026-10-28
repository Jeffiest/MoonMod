# Gauntlet log

Passes of the gate loop in [GAUNTLET.md](../../../GAUNTLET.md), newest first.

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
