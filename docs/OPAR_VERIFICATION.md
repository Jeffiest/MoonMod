# Opar in the Gauntlet: verification and grading

This is how Opar ([OPAR_PLAN.md](OPAR_PLAN.md)) is checked before he counts as a finished Gauntlet character. It
works like [GAUNTLET.md](../GAUNTLET.md): gates in order, each with automated checks, a playtest checklist and a
grade. The difference is the grading: **13 metrics scored 1 to 10**, and the bar is high.

## The pass rule

Opar is **done** when, in one graded pass, all of these are true:

1. Every gate's automated checks and playtest lines are green.
2. **The average of the 13 metrics is 8.5 or higher.**
3. **No metric is below 7.** A high average cannot hide a weak spot.
4. **Metrics 5 (combat feel), 7 (balance) and 11 (stability) are 8 or higher.**

A gate also has its own bar: the metrics it touches (listed with each gate) must reach **7** before the next phase
starts, so the work never builds on something weak.

## How to grade

- Grade in Chronicle, not from screenshots alone. Each metric says what to look at and what to measure.
- Use the anchors below: a score is the highest anchor whose every sentence is true. Between anchors, pick the
  number in between.
- Write each pass into `tools/tests/roguelike/gauntlet-log.md` under *Opar*: date, build, the 13 scores, the
  average, and one sentence for every score under 9 saying what would raise it.
- A metric that cannot be graded yet (its feature is not built) scores **1**, not "n/a": the average shows how far
  there is to go.
- Grade honestly against the other six characters, not against "good for a mod".

---

## Gates

### O1: Pack pipeline (phase 1) — PASSED 2026-10-29
*Automated:* `python tools/chr/roundtrip_test.py <mainchara> c01d`: all pass (unchanged build byte-identical; every
mesh split and rebuilt with identical triangles, UVs, weights and weight-list order).
*Playtest:* the rebuilt Toan pack loaded by a test mod looks and moves like the game's. ✔
*Metrics:* 11.

### O2: Model and paint (phase 2) — HEADLESS PART DONE 2026-10-29
*Automated:*
- [x] `build_character.py build`: every triangle, UV and weight of the Blender body is in `c07d.chr`; the pack's
  textures match the paint (mean difference under 3 levels).
- [x] Model buffer under 80% with Opar loaded (150,463 of 210,000 = 72%).
*Playtest:*
- [x] Front and back in a lit dungeon: he reads as the concept (head, lips, eyes, spines, belly, gear).
- [ ] *(hands)* Rotate the camera all the way round, near and far: no holes, no gear floating off the body, nothing
  poking through.
- [ ] *(hands)* Run, attack, dodge, get hit, die: no limb, belly or loincloth tearing or folding through itself.
*Metrics:* 1, 2, 3.

### O3: The seventh slot (phase 3) — PASSED 2026-10-29
*Automated:*
- [x] The engine tests for the seventh character (party list, switch, save) pass; the full suite adds no failure the
  baseline lacks. (`SeventhCharacter.*`, 7 tests, and `MoonModPlayerPartyApi.*`: 13 of 13. Full suite: 819 passed,
  the same 7 failures as the baseline: three PlatformMc seek tests, two LocalizeLanguages exports,
  LocalizeOptions' export, DataRead.MetadataSnapshotsStayFreshWhenDisabled.)
- [x] `test_runs.lua` runs a seven-character party through a whole run. (Scenario 25: Opar off by default; on, the
  title cycles to him, Start Run asks for seven, he leads with Toan's dagger, finds and is given Toan's weapons, and
  the party of seven wins all five biomes. 348 passed.)
*Playtest* (headless, `darkcloud_slot7.exe`, captured with `--screenshot-at` and looked at):
- [x] Switch to and from Opar on every floor type, with the switch wheel and the run menu; his portrait, name and HUD
  show; switching never leaves Toan's model or textures on him. (I, II, III and the Warden floor of all five biomes,
  and Vaults; the wheel shows seven with his portrait, the Allies ring names him "Opar" with his HP and portrait, the
  weapon page shows his portrait, the run menu's Party tab lists him; Toan, Ungaga and back are clean.)
- [x] A story save loaded after a Gauntlet run with Opar is byte-identical to before. (All five files under
  `saves/` hashed before, after the run and after loading file 1 into Norune: identical.)
- [x] 30 minutes of play with Opar: no crash. (A soak of 142,440 frames, about 40 minutes of game time: 62 floors,
  512 switches, 128 of them to him, one refused by the game's own mid-action guard; no crash.)
*Found and fixed on the way:* the weapon and effect model buffers were sized from the PS2's 210,000 quadwords, not
the arena as carved (four times that), so his bigger pack starved Toan's weapon (an arena overflow on load); the HUD's
gauges (`topStatusInfo`), the name length for messages, a hit's weapon owner and the weapon menu's turntable wrap
still stopped at six.
*Open:* the battle menu's character message (system line `30 + chara`, so 36 for him) is unknown text and was not
seen on the Allies or weapon pages; his portrait is a square picture where the six have round framed faces.
*Re-checked after opening the slot up (2026-10-29, the user's request for room for more characters):* the fixed
seventh slot became a registry of up to ten playable characters past the six (`characters.register_playable`), and
the Gauntlet registers Opar as the first.
- [x] Engine tests with two registered characters (Opar fighting as Toan, a test "Kit" fighting as Ruby) and a third
  registered through the API: indexes, refusals, the save layout and image, gauges, start stats, names, slots in
  play, the party API and weapons. (`PlayableRoster.*`, 9 tests. Full suite: 823 passed, the same 7 baseline
  failures.)
- [x] `test_runs.lua`: Opar comes through the registry; without his registration the Opar setting adds no one.
  (350 passed; `test_standalone.lua` 38.)
- [x] Headless, `darkcloud_roster.exe`, a test mod registering Opar and Kit: a party of eight; switches Toan → Opar
  → Toan → Kit → Ruby with each one's own HP; the wheel shows eight places (Opar's portrait, Kit with Ruby's face, as
  he has none); the dungeon menu opens as Kit; Kit on Opar's Toan-skeleton pack attacks as Ruby with no crash.
- [x] Found and fixed: a pack built on another skeleton than its `fights_as` character's lacked that character's
  extra files (Ruby's raised hand `hand_up.cfg` crashed `LoadChara2`); a registered character now borrows them
  from his `fights_as` character's own pack. This is what lets Opar fight as Ruby in phase 4.
*Metrics:* 10, 11.

### O4: Staffs (phase 4) — MODELS DONE 2026-10-29
*Automated:* each staff registers, has a model and an icon; `test_runs.lua` drops each in its biome.
- [x] `tools/chr/build_weapon.py`: all six packs hold exactly the staffs' triangles, each under 2 MiB.
- [x] Tidecaller registered (`model = "opst06"`), given and equipped: drawn in hand in game, swings with it.
*Playtest:*
- [ ] Each staff is visibly different in his hand; its glow shows its colour.
- [ ] Spit globs home on the locked-on target, splash on impact, and each staff's own effect works.
- [ ] Tidecaller's Riptide splits on a hit and the splits find new targets.
*Metrics:* 8, 12.

### O5: Motions (phase 5)
*Automated:* `tools/anim/verify.py` passes for every Opar motion.
*Playtest:*
- [ ] Every motion of §5 of the plan seen in game, captured with `--screenshot-at` and looked at frame by frame.
- [ ] He squats and hops like a frog; nothing of Toan's gait is left.
- [ ] His own shadow model is a frog's.
*Metrics:* 3, 4.

### O6: Kit and Opar Form (phase 6)
*Automated:* the moves register without refusal; the form's timers, gauge and cooldown hold in a headless run.
*Playtest:*
- [ ] Every input of §3 of the plan does its move, cancels where it should, and feels responsive.
- [ ] Jump Slam → Opar Form → back, 20 times: never stuck in the form, never loses his weapon, never takes the form
  through a floor exit.
- [ ] The form against a Warden is worth the gauge, and not a win button.
*Metrics:* 5, 6, 9.

### O7: The Gauntlet around him (phase 7)
*Playtest:*
- [ ] His star appears after the first Moon Sea Warden kill and buys him into later runs.
- [ ] His Signature sky nodes each change his play.
- [ ] As companion (setting on), he helps and never transforms.
- [ ] His flame and poison parts only appear as detours.
*Metrics:* 7, 13.

### O8: The full grade
*Playtest:*
- [ ] Three full runs with Opar as the main character (one shuffled, one with the Cursed Gate every chance), each
  graded.
- [ ] The pass rule above holds on the third run's grade.

---

## The 13 metrics

Each anchor describes what is true at that score. **10** is "as good as the best of the original six", never "perfect".

### 1. Silhouette and likeness
*Look:* his outline at a distance and up close, beside the concept.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Not him, or Toan shows through | A frog, but not this one | Reads as the concept from the front and back; some proportions are still Toan's | Recognised at a glance from any angle, his own stance | Stands beside the original cast as if he had always been there |

### 2. Paint
*Look:* the textures in the dungeon's light, near and far.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Untextured or wrong | Flat colours, visible seams or smears | Colours and spots read, light shading painted in; blurry up close or seams on close inspection | Crisp at the game's resolution, no seams in play, hand-painted feel | Matches the original cast's painting |

### 3. Deformation
*Look:* elbows, shoulders, hips, knees, belly and loincloth through every motion.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Parts tear or stay in the bind pose | Bends, but pinches or folds badly at several joints | Clean in idle, walk and attack; small faults in extremes | Clean in every motion, gear stays on | Holds up as well as Toan's skin |

### 4. Animation
*Look:* every motion of the plan's §5.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Toan's motions | Some of his own, the rest Toan's | All his own; some stiff or floaty | Weight and timing read as a heavy frog | Each motion tells you what he is doing before it lands |

### 5. Combat feel (pass rule: 8 or higher)
*Measure:* time from button to the spit leaving (target 8 frames or fewer at 30 fps); hits have a sound, a mark and a
reaction.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Attacks don't land or lag badly | Works, but slow or mushy | Responsive, hits feel like hits | Snappy, every move has clear feedback, cancels where you expect | As satisfying as Toan's sword |

### 6. A kit of his own
*Look:* how he is played beside the other six.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Plays as someone else | Ruby with a different skin | His range-and-swat rhythm is clear | Players choose him for how he plays, not just how he looks | His kit makes situations no one else handles |

### 7. Balance (pass rule: 8 or higher)
*Measure:* median floor clear time with Opar against the party median, over at least 15 floors; deaths per run.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Unplayable, or trivialises runs | Clears over 30% slower or faster | Within ±20%, deaths comparable | Within ±10% in every biome | Within ±10%, and as many good runs use him as the others |

### 8. Staffs
*Look:* the staff line from starter to Legendary.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| No staffs of his own | Staffs differ by numbers only | Each staff has its own model and effect | Finding the next staff is something to look forward to | Tidecaller is as much a run-maker as the other Legendaries |

### 9. Opar Form
*Look:* the special from start to end, against crowds and Wardens.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Missing or breaks the game | Works but rarely worth it, or always | A strong moment, used by judgement | The moment players save their gauge for | The moment people remember from the run |

### 10. Integration
*Look:* switch wheel, run menu, HUD, Journal, saving, other mods.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Only in Toan's slot | His own slot, gaps in menus | Every screen knows him; saves untouched | No seam a player would notice | Indistinguishable from a built-in character |

### 11. Stability and cost (pass rule: 8 or higher)
*Measure:* crashes per hour, model buffer use, frame time beside Toan.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Crashes or corrupts saves | A crash in a long session | No crash in three runs; buffer under 80% | No crash, no frame time cost beside Toan | Same, with a companion of him on screen too |

### 12. Sound and effects
*Look and listen:* spit, splash, bubble, slam, form change, voice.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Silent or Toan's sounds | Some of his own | Every move has a sound and a visible effect | They fit a frog: wet, heavy, funny | They're why players pick him |

### 13. Gauntlet fit
*Look:* his star, Signature sky, Legendary, character blocks, companion.
| 1 | 4 | 7 | 9 | 10 |
|---|---|---|---|---|
| Not in the Gauntlet's systems | Joins, but the systems ignore him | Every Gauntlet system has his piece | Unlocking him is a goal players chase | He changes how players plan a run |

---

## Grade, 2026-10-29 (after phase 2)

Graded honestly: what is not built scores 1. This is the starting point, not a pass.

| # | Metric | Score | Why, and what raises it |
|---|---|---|---|
| 1 | Silhouette and likeness | 7 | Reads as the concept front and back in game. Long legs and Toan's stance remain (phase 5); no staff in hand (phase 4). |
| 2 | Paint | 7 | Baked spots, folds, shading; reads in the dungeon light. Low resolution on the body (fragmented UVs on a 256 picture), soft up close. Hand-placed UV seams and a larger head picture would raise it. |
| 3 | Deformation | 6 | Clean in idle, walk and attack as captured; weights are by distance, not tuned; the loincloth is rigid to the hips and will cut the thighs in big steps; extremes not checked. |
| 4 | Animation | 1 | Toan's motions. |
| 5 | Combat feel | 1 | Toan's sword and swings. |
| 6 | A kit of his own | 1 | Not built. |
| 7 | Balance | 1 | Not measurable yet. |
| 8 | Staffs | 1 | Not built. |
| 9 | Opar Form | 1 | Not built. |
| 10 | Integration | 1 | Rides in Toan's slot through a test mod. |
| 11 | Stability and cost | 7 | No crash in the headless runs (two with the finished model); model buffer 72%. Not his own slot; not timed against Toan; the game's own `darkcloud.exe` still needs the override fix linked in. |
| 12 | Sound and effects | 1 | Toan's. |
| 13 | Gauntlet fit | 1 | Not built. |
| | **Average** | **2.8** | Target 8.5, nothing under 7. |

Gate O2's two *(hands)* lines are the next check; phase 3 (the seventh slot) is the next build.

## Grade, 2026-10-29 (model reworked: one sculpted skin, 15,000 triangles)

The user found the 7,300-triangle model too plain and layered. The rework (see art/opar/README.md) is graded from
lit renders and the offline pack check only: it overflows the engine's character model buffer until phase 3 raises
it, so it has not been seen in game.

| # | Metric | Score | Why, and what raises it |
|---|---|---|---|
| 1 | Silhouette and likeness | 8 | Reads as the concept at a glance: wide flat head, heavy lids, lips, frills, belly, pauldrons, wraps. Toan's long legs (phase 5) and no staff (phase 4). |
| 2 | Paint | 7 | Dense varied spots, warm front, materials on the gear, baked shading. 256 pictures are soft up close; the belly paint still shows faint wrinkles. |
| 3 | Deformation | 7 | One skin; shoulders and elbows bend cleanly in a lowered-arm pose; gear follows its bones. Not yet seen moving in game; the loincloth is rigid. |
| 4-10, 12, 13 | | 1 | Not built (unchanged). |
| 11 | Stability and cost | 3 | The pack overflows the 210,000-quadword model buffer and the game stops loading him. Raising the buffer (phase 3) brings this back to 7 or more. |
| | **Average** | **2.6** | Lower than before only because stability dropped; the asset metrics rose. |

### 2026-10-29, later: the six staff models

| # | Metric | Score | Why, and what raises it |
|---|---|---|---|
| 8 | Staffs | 4 | Six staffs with models of their own (`opst01`-`opst06`), Tidecaller drawn in hand in game. No icons, effects, line or drops yet; the angle in the hand follows Toan's grip until his motions. |

The other metrics stand as graded above; the average is now 2.8.

## Grade, 2026-10-29 (after phase 3: the seventh slot)

Metrics 10 and 11, the ones gate O3 touches. The others stand as graded above.

| # | Metric | Score | Why, and what raises it |
|---|---|---|---|
| 10 | Integration | 7 | Every screen seen knows him: the switch wheel (seven places, his portrait), the Allies ring (his name, HP, portrait), the weapon page, the HUD, the run menu's Party tab; saves untouched (hashes identical). Seams a player would notice: his portrait is a square picture among round framed faces, he speaks with Toan's voice, the battle menu's line 36 is unknown text, and the companion refuses him. A framed round portrait, his own lines and the companion (phase 7) raise it. |
| 11 | Stability and cost | 8 | No crash in about 40 minutes of soak over every floor type and 512 switches, nor in the playtests after the buffer fix; the pack takes 25% of the carved character arena. Frame time beside Toan not yet measured; a companion of him not yet on screen. |
| | **Average** | **3.7** | 8, 7, 7, 1, 1, 1, 1, 4, 1, 7, 8, 1, 1: seven metrics are still 1 (animation, combat feel, kit, balance, Opar Form, sound, Gauntlet fit). Gate O3's bar (metrics 10 and 11 at 7 or more) is met. |

