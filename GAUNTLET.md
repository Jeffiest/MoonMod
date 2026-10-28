# The Gauntlet Gate Loop

Dark Genie's Gauntlet (`mods/moonmod.roguelike/`) is finished and tested, but only away from the game. This file is the
stage-gate loop that takes it from "passes its harness" to "plays right in Chronicle". Gates are worked in order, and a
gate does not advance until it passes. Every gate has three kinds of checks:

| Check type | Who runs it | Pass condition |
|---|---|---|
| **Automated** | The Lua harness and the engine's GoogleTest filters below | 100% green |
| **Playtest** | A human in Chronicle, with the gate's checklist | Every line ticked, with timings recorded |
| **Metric audit** | Designer, scoring the 5 metrics at the bottom 0–3 | No metric this gate touches scores below 2 |

The rule: **you may not build gate N+1 content while gate N is red.** Ideas can be prototyped on a branch, but they do
not merge into the Gauntlet branch until the gate before them is green.

---

## How to run a gauntlet pass

1. **Freeze** the slice. Stop adding content and only fix what the gate needs.
2. **Automated run.**

   The Lua harness needs Lua 5.4 or newer. With none installed, build the vendored 5.5.1 once (any C compiler; this
   uses LLVM's clang on Windows):
   ```
   cd vendor/lua-5.5.1/src && clang -O2 -D_CRT_SECURE_NO_WARNINGS -o <somewhere>/lua.exe $(ls *.c | grep -v '^luac.c$')
   ```
   Then, from the repo root:
   ```
   lua tools/tests/roguelike/test_runs.lua         # 84 checks: whole runs against a fake adapter
   lua tools/tests/roguelike/test_standalone.lua   # 38 checks: RPG, Ascension and Dungeon+ sit runs out
   ```
   The engine side lives in the Chronicle patch. Apply `ports/chronicle/moonfactory-chronicle.patch` with
   `ports/chronicle/apply-moonfactory.ps1` to Chronicle `9418a550`, with this checkout beside it named `MoonFactory`,
   build, and run:
   ```
   darkcloud_tests --gtest_filter='MoonModTitleModes*:MoonModRoguelike*:MoonModWorldTransition*'
   ```
   That is 10 tests. The full suite must add no failure the baseline does not have, on the same machine and toolchain.
   The baseline is the same Chronicle commit, unpatched, built the same way (`build.bat windows-x64-release`, then
   `DC_BUILD_TESTS=ON` and the `darkcloud_tests` target). Which tests fail on the baseline depends on the machine (Linux without a GPU and Windows with one
   differ), so compare the two runs; don't rely on a fixed list.

   A pass logged with only the Lua harness says so and stays **provisional** until the engine filter runs too.
3. **Playtest.** Enable *Dark Genie's Gauntlet* in the Mod Manager, restart, and work through the gate's checklist.
   Write times and failures into `tools/tests/roguelike/gauntlet-log.md`. Keep the *Weapon ABS multiplier* and the
   other settings at their defaults unless the line says otherwise, and log any you changed.
4. **Score** the 5 metrics (table at the bottom) and record them in the log.
5. **Verdict:**
   - **PASS:** the gate is signed and the next one starts.
   - **FAIL (fixable):** fix it and re-run the whole gate, not just the failed line.
   - **FAIL x3 on the same line** is a **design strike**. The mechanic goes back to the design table in the mod's
     README (*Differences from the design doc*), and the log notes what changed before it is rebuilt.

---

## Gates

### G0 — Engine: title modes and sandbox sessions — PASSED 2026-10-28 (see the log)
*Entry:* the Chronicle patch applies cleanly to `9418a550`.
*Automated:* the 9 engine tests above, and the full suite at baseline.
*Playtest:*
- [x] The *Dark Genie's Gauntlet* row shows between OPTION and EXIT, and the copyright banner sits below the menu
  without clipping, on **PAL (480)**. The Gauntlet is checked on the PAL disc only; NTSC is out of scope.
- [x] The mode screen's plate, font and pointing hand read cleanly. Fades in and out have no pop.
- [x] Keyboard and controller both move through Start Run, Starting Character, Norune Eternal and Records. Circle
  returns to the normal title menu. (The mouse is a known gap, not a fail.)
- [x] With the mod disabled, the title menu is exactly the native one.

### G1 — Run start, no save file — PASSED 2026-10-28 (see the log)
*Automated:* `test_runs.lua` scenarios for start, party setup and reload; `MoonModRoguelikePackage`.
*Playtest:*
- [x] Start Run from a **fresh install with no story progress** lands on Divine Beast Cave floor I. Time from Cross to
  control: about 7 s.
- [x] All six are in the party; only the starting character can fight, and switching to an undrafted one bounces back.
- [x] Every character from *Starting Character* starts with their first weapon.
- [x] Hash the story save folder before and after a run: it is byte-identical. RPG and Ascension show no slot mid-run.
*Kill criterion:* if the native dungeon entrance cannot run without story progress, the run needs its own entry path
in the engine before anything else is built.

### G2 — The floor chain — HEADLESS PART DONE 2026-10-28; the lines marked *(hands)* need someone playing
*Automated:* `MoonModWorldTransitionApi.*`, and the route scenarios in `test_runs.lua` (win, off-route floor).
*Playtest:*
- [ ] In every biome the native exit chains I → II → III → Warden on the registered floors, never onto a story floor.
  Headless: each biome's four floors are numbered straight after its retail floors (DBC and Moon Sea 15-18, Wise Owl
  Forest 17-20, Shipwreck and Temple 18-21), the native exit asks for the current floor + 1, and all 20 floors load
  and spawn 15 enemies. *(hands)* Walk one exit per biome.
- [ ] *(hands)* The Warden holds the gate key, is larger, has its HUD bar, and on death moves the run to the next biome in 5 s.
  The mod only sees the key holder once the player is in its room (`entities.query` lists loaded monsters only).
- [x] Reaching the Warden floor's exit before the Warden dies does something safe. Record what: **it can't be reached**:
  the Warden holds the key. In the 5 s after its death the exit could be opened; the engine now keeps a mod's last
  floor's exit on that floor (`ChronicleScriptFloorLevel`) instead of reading past the floor tables, and the run
  moves on when the 5 s are up.
- [x] The source floors in `BIOMES` (`main.lua`) play no scripted event: Divine Beast Cave 2/5/10/12, Wise Owl Forest
  2/5/10/13, Shipwreck and Sun and Moon Temple 2/5/11/14, Moon Sea 2/5/10/12 (0-based). A source floor gives only its
  enemy layout; story events key on retail floor numbers, which the registered floors are past. All 20 visited.
- [ ] *Shuffle biome order* on: a late biome rolled first is visibly weaker *(hands)*, and the HUD line names the right
  floor (headless: yes, a Temple start reads `GAUNTLET 1-II` on Temple II).

### G3 — Weapons: one each, fast ABS, found weapons — REWORKED 2026-10-28 (one weapon each); *(hands)* lines need someone playing
*Automated:* the found-weapon, absorb, broken-weapon and drafting scenarios in `test_runs.lua`, and
`MoonModWeaponsApi.EquipsInADungeonWithAModelReloadAndRemovesTheSpare`.
*Playtest:*
- [ ] Wear per hit, measured on the starting weapon: ______ durability per hit *(hands)*. From the code: a hit wears
  `(1.5 - endurance/100) x weight` (weight 0.8-1.8, a charged attack 3), times the run's wear (Brittle 2x).
- [ ] A weapon at 0 ends the run: the title shows *Weapon broke in ...* and it counts as a death (headless: yes).
  How many floors a careful player gets from the starting weapon with the kit's 2 Repair Powder: ______ *(hands)*.
  Fewer than 3 is too harsh; tune the kit or the durability unlocks.
- [ ] A chest weapon for a drafted character opens the choice over the HUD; L1/R1 switch, Cross confirms, and each
  line's stats are what that weapon ends with *(hands: a chest)*. Headless: the in-dungeon swap reloads the model,
  the spare goes, and the harness covers keep, take and the 25% absorb.
- [ ] A chest weapon for someone outside the draft is absorbed into the active weapon with a message *(hands)*.
- [ ] A found weapon arrives 1–4 levels up with 1–2 attachments before the choice *(hands: a chest)*.
- [ ] Benched drafted allies level from shared ABS by the end of biome 2 *(hands)*.
- [ ] Two players end biome 2 with different weapon builds *(hands)*.

### G4 — Risk and reward: Cursed Gate, Vaults, Diorama, Gilda — HEADLESS PART DONE 2026-10-28 (2 fixes); *(hands)* lines need someone playing
*Automated:* the curse, Vault, blessing and Diorama scenarios in `test_runs.lua`.
*Playtest:*
- [ ] **G**, **L1+Select** and **Actions** all curse the next floor; the HUD shows `NEXT CURSED`; the floor before a
  Warden refuses. Headless: G curses (HUD `GAUNTLET 1-I NEXT CURSED`), and G on floor III is refused. *(hands)*
  L1+Select and Actions: scripted pad buttons do not reach mod bindings, and the Actions tab needs the Mod Manager.
- [ ] A cursed floor feels harder (+60% HP, two of Parched/Brittle/Glass) *(hands)* and leaving it pays the Miracle
  cache *(hands: a real exit)*. Headless: the floor opens with its two curses named and **now** gets its +50% chests
  (fixed: the floor was built after the run had spent its curse, so cursed floors had no extra chests).
- [ ] A back floor on a run floor is a Vault and pays a blessing on the way out *(hands)*: the back floor opens only
  at a native script boundary (the back-floor key at the gate).
- [ ] Each Diorama piece's effect is noticeable within a floor (a Lamp maps the floor, Trees heal, and so on). No piece
  is one a player never places *(hands: placing is on Journal > Character)*.
- [ ] Gaffer's Wagon (if unlocked) appears on floor II and Gilda is enough to buy from it about once per biome
  *(hands)*. Estimate: floors pay 40 x depth, so floor II of biome 1 has about 40 plus drops (short of 300 for Repair
  Powder) and biome 2 about 600 plus drops: likely no purchase in biome 1.
*Kill criterion:* if testers curse fewer than 1 floor in 5, the reward is not worth the risk; retune before G5.

### G5 — Run endings and the meta loop
*Automated:* the win, defeat, retreat, Abandon, quit-mid-run, reload and purchase scenarios in `test_runs.lua`.
*Playtest:*
- [ ] Each ending lands back on the Gauntlet's title screen with the last run shown: win, defeat, exit gate out,
  Escape Powder, **Actions > Abandon Run**.
- [ ] Closing the game mid-run counts as a retreat on the next start and keeps the run's Moon Shards.
- [ ] Moon Shards match the table: a win pays about 45, a third-biome fall about 15. Records update.
- [ ] Each Norune Eternal unlock bought shows up on the next run (Macho's Forge attachment, Matataki ally, and so on).
- [ ] Runs to buy everything (161 shards): ______. Target: 6–10 runs.

### G6 — Standalone runs
*Automated:* `test_standalone.lua` (38 checks).
*Playtest, with RPG: Character Paths, Ascension and Dungeon+ enabled:*
- [ ] Mid-run: no RPG or Ascension bars, tuning or Character page; no Dungeon+ tiers, champions or mutators.
- [ ] After the run, load the story save: RPG levels, Ascension stats and Dungeon+ state are exactly as before.
- [ ] Known carry-overs only: Dungeon+'s Expanded Data weapon balance and its kill-count trophies.

### G7 — Full run, end to end
*Playtest:*
- [ ] A cold player goes title → five Wardens → win screen. Time: ______. Target: 75–120 minutes.
- [ ] Median floor clear time is 3–6 minutes.
- [ ] No crash, soft-lock or story floor across 3 full runs (one shuffled, one with the Cursed Gate every chance).
- [ ] Metric audit: all 5 metrics score 2 or higher.

Each later content change (a sixth biome, real boss floors, two exits per floor) re-runs **G2–G7**.

---

## Metric audit scoring (0–3)

| # | Metric | 0 | 1 | 2 (gate minimum) | 3 |
|---|---|---|---|---|---|
| 1 | No way back (G2, G5) | Runs can be resumed or saved | Ending a run is unclear | Every exit ends the run, cleanly | Players feel the weight of each exit |
| 2 | Build within a run (G3) | Weapons barely grow | Growth but one dominant build | Weapons grow each biome, builds differ | Players chase a build on purpose |
| 3 | Risk is a choice (G4) | Cursed Gate ignored | Used, but always or never | Used on some floors, by judgement | Players argue about when to curse |
| 4 | Meta pull (G5) | Shards feel pointless | Unlocks exist but don't change runs | Each unlock changes the next run | Players start "one more run" for an unlock |
| 5 | Clean sandbox (G1, G6) | A story save changes | Other mods leak into runs | Saves untouched, other mods sit out | Players never notice the seam |
