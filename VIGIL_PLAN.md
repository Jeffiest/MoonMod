# Vigil: a Souls-lite combat overhaul for Chronicle (Dark Cloud)

Working title **Vigil**, mod id `moonmod.vigil`. Rename freely.

Combat should be slow, deliberate and methodical. Every action spends stamina, and the player has to block and dodge
to survive. The world is persistent and the dungeons are random.

> **Built on [Jeffiest/MoonMod#15](https://github.com/Jeffiest/MoonMod/pull/15)** (Rest floor, Opar, animations and the
> modder's guide). This plan uses its operations and follows its guide: the
> [Cookbook](docs/modding/COOKBOOK.md), [Extending the engine](docs/modding/EXTENDING_THE_ENGINE.md),
> [Testing mods](docs/modding/TESTING.md), [Dark Cloud engine notes](docs/modding/DARK_CLOUD_NOTES.md) and the
> [Animation guide](docs/ANIMATION_GUIDE.md). Those paths exist once that PR is merged. Vigil work starts after it lands.

---

## 1. Dark Cloud already has the world we want

| What we want | What Dark Cloud already does |
| --- | --- |
| Persistent world | Six towns that keep their state across the whole save |
| A world that is placed, not generated | Georama: the player rebuilds each town piece by piece, and it stays that way |
| Randomly generated dungeons to crawl | Every floor is generated on entry, with a fixed theme, roster and boss for each dungeon |
| Control over how floors are built | Cookbook, *Shape a floor as it is built*: `set_modifiers`, `set_layout`, `set_population`, `set_shortcuts` in `game.dungeon.generating` |
| Checkpoints and bosses | Cookbook, *A special room: the Rest floor* and *A boss in a sealed room*: `set_rest_room`, `set_warden_room`, `ui.boss_card` |

So Vigil is about **combat, the death loop and pacing**, not world generation.

---

## 2. What PR 15 already gives us

PR 15 covers most of what the first version of this plan listed as missing engine work.

| Vigil needs | PR 15 provides | Where |
| --- | --- | --- |
| A real dodge with i-frames | Evade moves: `player.moves_set` with `trigger = "dodge"` (L2 + stick) or `"dodge_back"` (L2 at rest), `invincible`, `lunge`, `cooldown`, and `cancel` to cut a swing short once its blow lands | API *Chronicle mod moves*; the Gauntlet's `ROLL` and `BACKSTEP` |
| Dodge animations | Toan's **Roll** (24 frames) and **Backstep** (18), Xiao's Tumble and Hop Shot, and generic melee sets for Goro and Ungaga, all authored with `tools/anim` | `docs/GAUNTLET_ANIMATIONS.md`, `mods/moonmod.roguelike/resources/anims/` |
| A guard | The native guard: **lock on (circle), then hold R1**. `guard_attack` fires a move from it (the Gauntlet's Counter Slash). | API `guard_attack`; the Animation guide's button names |
| Knowing when an action starts | Event `game.player.move` `{id, owner, character, cancel}` as each mod move starts | API *Chronicle mod moves* |
| A built-in cost gate | Each move's `gauge` (0-100): the move spends that much **action gauge** and won't fire without it. `tuning_set{gauge_refill}` scales the refill. | API *Chronicle mod moves*, *Player tuning* |
| Heavier hits on the player | `recoil_scale`, plus `combat.register_player_formula` | *Player tuning*; Cookbook *Change combat* |
| Making party swapping costly | `tuning_set{swap_delay = 0..4}` scales the switch's two 20-frame waits | *Player tuning* |
| Feedback for block, parry and stagger | `effects.burst{kind = "guard" or "sparks"}`, `entities.knockback`, `entities.tint`, `combat.status_add{stop}` | *Weapon styles, effect bursts, tints and shoves* |
| Enemy telegraphs | `entities.tint` to flash an enemy as it winds up, plus the `native.monster.run` takeover | as above, and *Chronicle monster AI from Lua* |
| A last-stand mechanic | `player.fatal_guard{charges}` with event `game.player.guarded` | *Active player health* |
| New combat motions (guard break, parry, heavy swings) | `animations.player_register` and the `tools/anim` pipeline | Animation guide; `examples/new-move` |
| A souls-ish map option | `tuning_set{map_hidden = true}` (no minimap) | *Player tuning* |

### What is still missing (the engine work Vigil adds)

There is **no event or hook for the player being hit**. The only player-side hit signal is `game.player.guarded`, and
it fires only for fatal hits. S0 (§7) found that the guard and the stamina bar both already exist natively. They only
need their rules changed, so the engine work is smaller than first thought, and it can be **rule data instead of
per-hit Lua callbacks**.

| # | Operation | Why | Where (S0) |
| --- | --- | --- | --- |
| E1 | **`player.guard_rules_set{arc, cost_base, cost_per_damage, chip, break_recoil, parry_frames, without_lock}`** (owner-scoped, cleared on unload), plus a **`game.player.hit`** event `{entity, damage, kind, blocked, parried, broke, angle}` after each hit. | The native guard blocks everything from every side for free. These rules give it a front-only arc, a gauge cost per blocked hit, chip damage, guard break and a parry window. The event lets Lua react (riposte window, death drop, stats). | `BtCheckDamageProc` in `port/src/game/dun/gameloop.cpp`: the block test is `action_on == 6` / `action_no == 9`. The guard is entered in `movechara.cpp` (R1 with `lockOnTargetFlag`). |
| E2 | **`player.gauge_rules_set{hit_refill, first_swing_cost, min_to_swing, swing_cost, refill_delay}`** | The gauge already gates combo follow-ups (needs 20, costs 25), but **a hit refills it to 100** and the first swing is free. Souls needs the opposite on both. | The refill on hit is in `BtCheckDamageProc`. Swing costs are in `charakey.cpp` (`*Key_On` / `*Key_Play`), and regen is in `gameloop.cpp` near the `gauge_refill` scale. |
| E3 | **`player.gauge_get/set`** and **`player.state()`** (`action_on`, `action_no`, guarding, locked on, recoil and invincible frames) | Refunds on a parry, spending from Lua (switching, items), and HUD and logic that know what the player is doing | `BtActStatus` (`include/game/btactstatus.hpp`) |

A per-hit Lua hook (`native.player.hit`, like `native.monster.run`) stays an option if the data rules prove too
rigid. Data rules are cheaper to run, easier to test, and can't stall a hit on a slow script.

Each is added the way *Extending the engine* walks through `dungeons.set_rest_room`: catalog it in `api.cpp`, dispatch
and handle it in `chronicle_adapter.cpp`, release it on unload, add engine tests, document it in `docs/API.md`, teach
the fake game, then regenerate the patch. Chronicle Two reports them unsupported.

---

## 3. Design pillars and starting numbers

These are first-pass numbers. Each one is a mod setting (*the rules the bundled mods follow*, rule 5).

### Stamina is the action gauge
S0 settled this: **Dark Cloud already has a stamina bar.** It's the weapon gauge drawn bottom-left (`TEX_WepGage`).
- Combo follow-ups need 20 and cost 25.
- Goro needs a full bar to swing at all.
- A held swing that becomes a charge empties it.
- It refills at the weapon's **Speed** / 30 per frame. Toan and Ungaga refill at a quarter of that and not at all
  mid-swing; Xiao and Ruby refill ×1.5.

So heavy weapons already recover stamina slowly, like Souls equip weight, and the player already sees the bar. Vigil
changes its rules (E2) instead of adding a second bar. Until E2 lands, the S1 prototype uses `gauge` on moves and
`gauge_refill`.

| Action | Cost (of 100) | How it's charged |
| --- | --- | --- |
| Light swing | 25 (first swing too, via E2) | native for follow-ups; E2 adds the first swing |
| Heavy (R2) / charge release | 35 | the move's `gauge` |
| Roll / backstep | 25 | the move's `gauge`, so an empty bar means no evade |
| Counter (guard + attack) | 20 | the move's `gauge` |
| A blocked hit | 10 + 1.5 × damage stopped | E1 |
| Regen | 30/s after a 0.6 s pause, half while guarding | `gauge_refill`, re-set while guarding |
| **Exhausted** at 0 | 1.5 s | no evade (the gauge gate), the guard breaks, swings do 30% damage (a formula) |

### Blocking (the native lock-on + R1 guard)
- Natively it needs a lock-on target and blocks **everything**, from any side, for free (S0). E1 changes that.
- Allow guarding without a lock-on (`without_lock`), as in Souls.
- Covers about 120° in front. A hit from the side or behind gets through at full damage (E1's `angle`).
- Stops 70-85% by weapon: Goro's hammers block best, Ruby and Osmond worst.
- **Guard break**: a blocked hit that would empty the gauge knocks you down with a long recoil (`recoil_frames`).
  Show it with `effects.burst{kind = "sparks"}`.
- **Parry**: guard within about 6 frames of the hit (E1 plus the guard's start frame from E3). You take no damage, a
  `guard` burst plays, the enemy is stopped for 90 frames and shoved back (`entities.knockback`), and the
  `guard_attack` **Counter** becomes the riposte at ×3 for 2 s.

### Dodging (the evade moves)
- Roll with the stick pushed, backstep at rest, both `invincible`. The i-frames come from the move.
- Tighten the Gauntlet's numbers to make it deliberate: a longer `cooldown` (about 30), less `lunge` (2.2), and
  `cancel_after` around 6, so you commit to a swing before you can roll out of it.

### Enemies that make blocking and dodging necessary
- Enemy damage ×2.5 by default (`register_player_formula`), and `recoil_scale` 1.5.
- **Telegraphs**: each enemy family's takeover (`native.monster.run`) holds a wind-up pose with an `entities.tint` flash
  before it attacks, commits to the attack, then leaves an opening.
- **Stagger**: heavy hits, ripostes and parries put the enemy into `stop`.
- Fewer, tougher enemies: `set_modifiers{monsters = -40}` and higher HP with `entities.set_stats`.

### Rest points, healing and death
- **Rest floors as bonfires.** Insert a Rest floor every few floors in each dungeon (`dungeons.register` plus
  `set_rest_room`, as in the Cookbook recipe). The spring heals and refills your heals, and Gaffer can stand by the
  exit as a merchant. The native springs (map parts 32-35) can serve as small rest points where the dungeon gives them
  an event.
- **Healing scarcity**: a few heal uses per stretch between rest floors.
- **Death drop**: carried Gilda (optionally unspent ABS) stays where you fell, saved with `game.save`. Get back to that
  dungeon, floor and position to recover it. A HUD line (`render.layer_register`) shows the distance.
- **Ember**: one `fatal_guard` charge, restored at a rest floor. You survive one killing blow at 1 HP.

### Gatekeepers
- A Warden room (`set_warden_room`, `ui.boss_card`, an HP bar) every few floors. It's the Souls mid-boss, and it gates
  the next stretch.

### Progression and characters
- Max stamina, regen and parry window grow through a skill tree on the Journal's Character page (`ui.sheet_set`).
- Per-character profiles:

| Character | Stamina identity | Evade |
| --- | --- | --- |
| Toan | Balanced baseline | Roll / Backstep (exist) |
| Xiao | Cheap shots, weak guard, best dodge | Tumble / Hop Shot (exist) |
| Goro | Expensive swings, best guard, slow evade | melee set (exists) |
| Ruby | Costly casts, worst guard, survives by spacing | to author |
| Ungaga | Mid costs, long reach, strong charge | melee set (exists) |
| Osmond | Costly shots, fast evade | Retreat Shot (exists) |

### Party swapping
Keep it, but make it a choice: `swap_delay` above 1, plus a stamina cost to switch.

---

## 4. Phased plan (stage gates, same rules as `GAUNTLET.md`)

Each gate needs its automated checks green and a playtest checklist ticked before the next one starts.

### S0: Spike (no content)
- In game: what does the native lock-on + R1 guard actually do to incoming damage? What is the action gauge natively
  (and is it drawn anywhere)? What does the native `stamina` ailment do?
- In `port/src/game/dun/`: find where enemy hits resolve on the player (the anchor for E1), and where combo swings
  start (the anchor for E2). The move runner's combo-cancel hook is a good lead.
- **Output:** §7. The source half is done; the in-game half still needs the game.

### S1: Lua prototype on PR 15's API (built; awaiting the playtest)
Built in `mods/moonmod.vigil/` ([README](mods/moonmod.vigil/README.md)), tested by `tools/tests/vigil/test_vigil.lua`
(45 checks).
- **Evades for all six**: roll or tumble with the stick, backstep or hop back at rest. Untouchable, `gauge` 25 (the
  native gauge is the stamina bar, so an empty one stops them), cooldown 30, `cancel_after` 6. The motions are copied
  from the Gauntlet. If they can't load, it falls back to the engine's shove dodge (`dodge_power`).
- **Enemy damage ×2.5** (`register_player_formula`). **Recoil ×0.4** (shorter stun, and shorter post-hit protection).
- **Guarding slows the gauge**: R1 read through `input.bind` (plus an optional keyboard key), and `gauge_refill` set
  again on each press and release.
- Switches ×2 (`swap_delay`), no "Stamina" power-ups from enemies (`status_immune`), and an optional no-minimap.
- Sits out the Gauntlet (`moves_clear`, `tuning_clear`, the formula back to ×1), including when loaded mid-run.
- **Dropped from this stage:** a separate Lua stamina bar (S0 showed the native gauge is the bar), and charging
  blocked hits from HP drops (a blocked hit takes no HP, so there's nothing to see). Both wait for E1-E3.
- Found while building it: `input.block_native({buttons, frames})` hides pad buttons from the game. Guard break can use
  it (no R1 for N frames) before E1. It's one mask for the whole game, last writer wins (RPG and Ascension use it while
  L2 is held), so it needs care.
- **Gate:** the playtest checklist in the mod's README. Divine Beast Cave floors 1-3 as Toan: trading hits is clearly
  worse than guarding or evading, and the gauge makes you pause.

### S2: Engine (E1-E3)
- Following *Extending the engine*: E1 first, since it's the critical path, then E2 and E3.
- Engine GoogleTests for each, a test hook where a hit is hard to reach in game, and a driver mod with an input
  script for a headless run (*Testing mods* §4).
- **Gate:** the engine tests pass, the full suite adds no failures beyond the baseline, and the patch regenerates and
  applies to Chronicle `9418a550`.

### S3: Real combat on the hooks
- Switch stamina to the action gauge. Add the frontal block arc, guard break, swings gated by the gauge, the parry
  window and the Counter riposte.
- New motions where the native ones read badly, such as a guard-break stagger and a parry flinch (Animation guide,
  `tools/anim`).
- **Gate:** playtest the same floors and Dran. A frontal block holds, a side hit gets through, an empty bar stops
  swings and rolls, and a parry lands reliably.

### S4: Enemies that telegraph
- Takeovers for Divine Beast Cave's roster first: a tinted wind-up, a committed attack, a recovery window, and stagger.
- **Gate:** every enemy there can be beaten cleanly by reading it, with no unavoidable damage.

### S5: Rest floors, the death loop and healing
- Rest floors every few floors, Gaffer, heal charges, the ember (`fatal_guard`), the death drop and recovery, and a
  Warden every few floors.
- **Gate:** a full Divine Beast Cave run with deaths. The loss stings without making you want to quit.

### S6: Breadth and balance
- The remaining dungeons' enemy families, all six profiles (Ruby needs an evade authored) and the skill tree.
- Coexistence with RPG, Dungeon+ and Opar (who `fights_as` Toan, so he gets Toan's set). Decide on Ascension, whose
  Focus powers bypass stamina.
- Difficulty presets.

### S7: Release
- A README, a Hub link, the release zip and a Cookbook recipe: *Stamina, guard and evade*.

---

## 5. Risks

- **E1 is the critical path.** If the player's hit resolution is tangled, frontal blocking and parry slip. The S1
  prototype is still playable without it.
- **One owner per trigger per character.** Vigil and the Gauntlet both want L2 and guard + attack. Releasing them
  during sandbox sessions handles this, but it needs a test.
- **Native AI was never designed to be punished.** Fliers and ranged enemies may need full takeovers.
- **Changing the action gauge changes every character.** Its per-character rules (Goro's full-bar swing, Osmond's gun
  modes, Jinn's special) all read it, so E2's rules need a pass for each character in S6.

## 6. Decisions and open questions

**Decided:** weapon durability stays. It's the slow resource to stamina's fast one, and Dark Cloud's weapon that breaks
for good is already Souls-grade punishment. Repair Powder is the scarce counterweight: limit how much is sold, and add
it to Rest-floor shops.

**Decided:** the death drop is carried Gilda **and** the equipped weapon's unspent ABS.

**Decided:** rest points should feel like part of the dungeon, not a separate two-room floor. In the single-level
dungeon (§9) they're **shrines**: the native healing-spring rooms (map parts 32-35) placed along the path. **Town is
reachable only from a shrine.**

**Decided (Vigil World):** chosen when a save is started, never toggled mid-game. Monsters respawn on rest and on
death, as in Souls; the slow trickle stays a setting, off by default. Demon Shaft stays floor-by-floor as the endless
challenge.

1. Should Vigil also offer a sandbox title mode, a "Vigil Trial" like the Gauntlet, for testing balance away from the
   story save?

---

## 7. S0 findings (source half)

Read from Chronicle `9418a550` with PR 15's `moonfactory-chronicle.patch` applied. The in-game half still needs the
disc image and a GPU (see the end of this section).

### The guard (`movechara.cpp`, `BtCheckDamageProc`)
- **Entering it:** R1 while **locked on** (`lockOnTargetFlag`), with movement and water free and no action running. It
  runs `action_on = 6`: raise (action 8, motion 8), hold (action 9, `guard_mode = 5`), lower on release (action 0xA).
  Losing the lock drops it. While holding, the walk is ×0.4 (motion 0x21).
- **What it stops:** everything. A light hit (`kind` 2, 80 recoil) or a trap (`kind` 4) is blocked during **any** guard
  phase, raising and lowering included. A heavy hit (`kind` 3, 160 recoil) is blocked only while the guard is
  held (action 9). A blocked hit costs nothing, deals no damage, pushes the player back, and plays `SE_HIT_BLOCKED`.
  **There's no angle test**, so attacks from behind are blocked too.
- **What gets through anyway:** the ailment rolls (Freeze, Poison, Curse, Goo, and the hit that steals a fifth of your
  Gilda) run **before** the block test, so a guard doesn't stop them. That's a ready-made Souls-style "guard doesn't
  stop the poison".

### The action gauge (`charakey.cpp`, `gameloop.cpp`)
- It's the stamina bar described in §3: a follow-up needs 20 and costs 25 (Toan's line), and some lines need 40 and
  cost 20. Goro needs 100. Jinn (the special) needs 100. A held swing becomes a charge and empties it.
- Refill per frame = weapon Speed / 30 (at least 1), ×0.5 under Goo, ×2 under "Stamina", then the per-character
  multipliers, then MoonMod's `gauge_refill`. `refill_frames` already counts frames since the last swing, which is the
  hook for a regen delay.
- **Any hit, blocked or not, refills it to 100** and clears `gauge_exhausted`. That's the opposite of Souls (E2).

### Hits and recoil (`BtCheckDamageProc`)
- Damage = the hit's damage (after MoonMod's monster `damage_scale`) − defense, at least 0. The player damage formulas
  and `fatal_guard` apply inside `CUserStatus::AddNowLife` (`dngstatusdata.cpp`).
- **Recoil frames are also invulnerability:** the whole check is skipped while `recoil_frames` or `invincible_frames`
  is above 0. A heavy hit gives 160 frames (2.7 s) of both, a light one 80. That mercy is very un-Souls, but cutting
  `recoil_scale` also shortens the stun, which is what we want: get hit, recover fast, and the next hit can land.
  Tune `recoil_scale` to about 0.4 and measure in S1.
- A light hit with the stick pushed hard doesn't stagger at all (`action_on = 0`, motion 0x1D): Dark Cloud's own
  poise, of a sort.

### The "Stamina" ailment is a buff
In this code `AILMENT_STAMINA` **doubles** the player's swing damage, defense (`guard *= 2`) and gauge refill. Monsters
inflict it at 65% on hits flagged `0x1000`. Either the name is a misreading, or Dark Cloud's "Stamina" status is
Power Up. Vigil can't use it as an "Exhausted" state. Use the HUD's `stamina` badge for Exhausted, and consider
`status_immune{stamina}` so enemies stop handing out buffs.

### Durability (`hitvalue.cpp`, `shot_freefuncs.cpp`)
Wear is per hit and warns at 10% and 5%. The rest is as documented in the API.

### Still needs the game (the in-game half of S0)
1. Does the Gauntlet's evade `gauge` cost read right against the native bar? The bar is drawn only below 100, so
   watch it drain and refill.
2. How a heavy hit against a raising guard (action 8) looks and feels.
3. Recoil at `recoil_scale` 0.4: does a stun-lock become possible against packs?
4. Which Divine Beast Cave enemies use heavy (`kind` 3) hits. Those are the ones a raised guard must be fully up for.

---

## 8. More Dark Souls (idea backlog, ranked)

| # | Idea | Why it's Souls | How | Cost |
| --- | --- | --- | --- | --- |
| 1 | **Getting hit drains stamina instead of refilling it**, and the first swing costs | Trades and panic-mashing become wrong | E2 | engine, small |
| 2 | **No pausing to heal.** The item menu pauses the game; Souls never does. In combat, heal only from quick slots, with a drink delay that leaves you open. | Healing becomes a read of the enemy, not a menu | Lock the pause menu's item use while `combat.get().in_combat`. The Controls mod's quick-item keys plus a move with a drink motion (`player.move_play`). | engine, small (menu lock) |
| 3 | **Enemy poise.** Dark Cloud enemies flinch on every hit, so you can stun-lock them. Give each a poise value. Below it, a hit doesn't interrupt (skip program 110 in `native.monster.run`). Breaking it staggers (`stop`). | Enemies that trade back; you pick openings | Lua: monster takeover plus a per-entity poise table | Lua |
| 4 | **Backstabs and ripostes.** Behind an enemy (its `GET_ROTATION` against your position) the attack becomes a critical, ×3. After a parry, Counter is the riposte. | The signature reward for reading and positioning | Lua: a `lock_attack` move plus a one-shot target formula | Lua, plus a motion |
| 5 | **Shortcuts that open from one side** | Souls level design in a random dungeon | `set_shortcuts` already loops dead-ends back with keyed doors. Make the key drop on the far side. | Lua |
| 6 | **Rest floors as bonfires**: resting refills heals and the ember, and you **level up only there** (spend Gilda on the skill tree) | Gilda becomes Souls: currency and XP at risk at once | Rest floor recipe plus `ui.sheet_set`, with spending gated to the rest floor | Lua |
| 7 | **Fog-gate bosses with a name banner and a bottom HP bar** | The boss walk-in | Warden room plus `ui.boss_card` ("DRAN, THE SCORCHED BEAST"). An HP bar along the bottom of the screen is a small engine addition (`render.bar_register` is top-left only). | Lua, plus a small engine addition |
| 8 | **Summon signs**: before a Warden, pay to call a party member as an AI companion | Co-op help, offline | `party.companion_set` (PR 15) | Lua |
| 9 | **"YOU DIED"** | The ritual | `ui.boss_card` on defeat, before the game-over fade | Lua |
| 10 | **No minimap** | Learning the space | `tuning_set{map_hidden = true}`, as a setting | Lua |
| 11 | **Ailment build-up** instead of a 65% coin flip | Readable status threats | Replace the roll in `BtCheckDamageProc` with a per-ailment meter | engine, medium |
| 12 | **Terse lore**: cryptic weapon cards and Rest-floor NPC lines | Souls tone | `weapons.style_set{details}`, `text.set`, `dungeon_npc_set` | writing |
| 13 | **NG+**: after Dark Genie, a new cycle with harder floors | Replay | Dungeon+ tiers, or Vigil's own scaling | Lua |
| 14 | **Heavy weapons as equip load**: low Speed already means slow gauge regen. Show it on the weapon card and lean on it in balance. | Build identity | Already native. Surface it with `weapons.style_set`. | writing |

Recommended for the first pass: 1-6. They change how every fight plays. 7-10 are cheap feel wins for S5. 11-14 can wait.

---

## 9. The single-level dungeon ("Vigil World")

**The idea:** each dungeon is one continuous map, not a stack of floors. You enter and you're in the whole dungeon.
Each old "floor" is a **zone**, and the old exit gate is a locked door to the next zone, like the shortcut doors that
seal rooms off today. There are no stair cutscenes and no "continue or exit" prompt. The map is generated **once per
save** and kept. **Shrines** (bonfires) along the way are the only exits to town and the only fast-travel points.
Monsters respawn when you rest, and they scale so nothing is ever trivial.

### What the engine already has toward it (S0, Chronicle `9418a550` + PR 15)
| Need | Status |
| --- | --- |
| The same map every visit | **Yes.** Floors are built from `map_seed`, and a rebuild from the same seed comes out the same (rest floors, shortcut doors and Warden rooms already rely on this). There's even a test hook (`DC_MAZE_SEED`). What's missing is an API to **set** the seed, so it can be kept in `game.save`. |
| Big maps that still draw fast | **Mostly.** The map draws only cells within `draw_dist_scale` of the player and in front of the camera, so size costs memory more than draw time. |
| Lots of monsters | **Yes.** 256 slots, and only the nearest few are awake (`set_active_limit`). |
| Locked doors between parts of a map | **Yes**, in pieces: shortcut doors with coloured keys (items 216-222), room gates (parts 36-39), the Warden room's seal. |
| Map size | **The wall** (raised in W2). A grid of 48 × 48 cells (`DNG_GRID`), and 64 rooms (`DNG_ROOM_MAX`); now 96 × 96 and 160. Retail floors have about 6 rooms, so 20 floors' worth is about 120 rooms. |
| Monster kinds | **A wall.** At most 9 monster models per map; a dungeon's whole roster is more than that. |
| Atla (Georama pieces) | Placed per floor, up to 8 per floor (`buildEventData`). Each zone must place its old floor's atla. |
| Story bosses | Dran and the other story bosses fight on fixed, scripted maps (`dranmapfield.cpp`), not random ones. They stay separate: a boss door warps you into the arena, Souls fog-gate style. |

### Recommended path: regions first, then one map
Building straight to "one 20-floor map" means raising every limit at once. Instead:

**W1, Regions (fits today's limits).** Each **shrine-to-shrine stretch** (4-5 old floors' worth, about 25-30 rooms) is
one continuous map. You walk from zone to zone through locked gates with no loading. A load happens only at a shrine
or a boss door. That gives most of the feel. It fits in 48 × 48 and 64 rooms, and a region's roster usually fits in 9
monster kinds.

**W2, One map per dungeon.** Raise `DNG_GRID` (to 96 or 128) and `DNG_ROOM_MAX` (to 160). Load monster models by zone
(swap the 9-kind table when you cross a zone gate). Merge the regions. Do this only if W1 plays well and the memory
budget allows. *Extending the engine*'s rule is to raise the wall, not obey it, but measure first.

### The pieces (engine operations, in the *Extending the engine* style)
| # | Operation | Does |
| --- | --- | --- |
| W-a | `dungeons.set_seed({seed})` / `floor_seed` in `world.get()` (already reported) | Build the next floor from this seed. Vigil keeps one seed per dungeon in `game.save`, so the layout is locked for the save. |
| W-b | `dungeons.set_zones({zones = {{rooms, source_floor, level}, ...}, shrine_every})` | The generator lays out rooms in a chain of zones. Each zone is joined to the next by one **zone gate** (a sealed door, like a shortcut door). The gate opens with the key the zone's carrier drops, and stays open (saved). Each zone takes its monsters and atla from its `source_floor`, and a shrine room (a healing-spring part) goes at chosen zone boundaries. `dungeons.zones_get()` reports zones, gates, shrines and the player's current zone. |
| W-c | `dungeons.set_exits({town = "shrines"})` | The entrance stair and Escape Powder no longer take you to town. Only a shrine does. |
| W-d | `dungeons.repopulate({zones?})` | Respawn the dead monsters of the given zones, from their native rosters, at their rooms. Used when you rest at a shrine. |
| W-e | Room state that persists: zone gates opened, chests opened, shrines lit | Kept with the seed in `game.save`, and re-applied when the map is built |

### How it plays
- **Entering a dungeon** by walking in from town starts at the entrance, floor 1. **Shrines are reached from the map**: the
  town's map and a shrine's Travel both open the dungeon's map with the lit shrines to pick (the user, 2026-11-01). A
  knockout still wakes you at the last shrine you rested at.
  Vigil holds the seed and the shrine, sets them before the build, and `world.transition` takes you there.
- **Shrines**: light one the first time (`ui.notify`, the `heal` burst). Resting heals you, refills your heal charges
  and the ember (`fatal_guard`), **respawns the monsters** (W-d), and opens a panel (`ui.choice_open`) with: Rest,
  Level up (spend Gilda on the tree, the only place you can), Travel (to any lit shrine in this dungeon, or to town),
  and Leave.
- **Zone gates** replace stairs. The key carrier in each zone drops the gate key. Crossing a gate marks the old floor
  as reached for the game's own bookkeeping (floor records, the dungeon entrance's floor list), so story progress
  still advances.
- **Back floors** (the native *ura* floors) become optional side branches off a zone, behind their own stairs.
- **Bosses**: a Warden room guards some zone gates. The story boss is a fog door into its native arena, and back
  through the door brings you to the zone you left.
- **Death**: you wake at the last shrine. Gilda and ABS stay where you fell (`game.save` keeps zone and position).
  The monsters have respawned, since a death counts as a rest.

### Respawns
- **On rest and on death**, everything respawns, as in Souls (W-d).
- Optionally a **slow trickle**: a zone you've left refills one monster every few minutes, up to its roster. This is a
  setting, off by default (decided).
- Key carriers and Wardens stay dead once beaten; their gates stay open.

### Difficulty that never goes soft ("floor scaling")
Every zone has a **base level** that rises with depth. Vigil keeps a **player level** from its tree, the equipped
weapon's attack and max HP.
- **Monster level = max(zone base, player level − 2).** Deeper zones above you stay harder than you, and pushing
  through without levelling hits a wall. Zones you've outgrown rise to just under you, so nothing becomes a one-hit
  kill.
- Applied when a monster spawns: `entities.set_stats` (HP, defense, rewards) and its `damage_scale`. Rewards scale
  with the monster's level, so farming a lower zone still pays, a little less.
- Bosses use the same rule, with a higher base.
- The gap (−2), the base curve and an "old zones scale" on/off are settings.

### Compatibility
- Vigil World replaces Dark Cloud's floor structure. Make it a choice **when a save is started** (a story-mode
  option kept in the save), not a toggle mid-game. A save started without it stays a normal Dark Cloud save.
  *Built (2026-11-01):* the first time a save goes into a dungeon Vigil settles it and keeps it with the save
  ("world"): a save already holding Vigil World places (shrines, gates, zone shapes) is one; a save with dungeon
  progress (`dungeons.list` `deepest_floor_reached` past the first floor) and none was started without it; a new game
  takes the *Vigil World preview* setting, which is now for new games only (changing it on a settled save says so).
  A title-menu row isn't the way: title modes start sandbox runs, not story saves.
  *Dungeon+ stands down (2026-11-01):* mods can't ask each other (a command runs only in its own mod), so the floor
  says it: the engine leaves another mod's room density (`set_population`) off a zoned floor, and Dungeon+ gives a
  floor whose `zones_get().floor_zones` is above 0 no tier and no mutator. Its room count was already the zones'.
  Checked in the game: Divine Beast Cave's first map held 105 monsters and 35 chests with Dungeon+ on, 103 and 35
  with Vigil alone.
- It owns `set_layout`, `set_zones` and the exit rules while active. Dungeon+ must stand down its layout and tier
  features in a Vigil World save; that needs a test.
- Demon Shaft (100 floors, no atla) stays floor-by-floor, as the endless challenge (decided). W2's stress test is a
  regular dungeon instead.

### Order
W1 comes after the combat core (S1-S3), since the world only matters if the fighting is right. Suggested gates:
- **W1.0**: `set_seed` and keeping the seed per save. Re-entering Divine Beast Cave gives the same floor.
  *Built (2026-10-31):* `dungeons.set_seed`, the `game.dungeon.generated` event, and Vigil's *The same floors
  every visit* (seeds kept per save slot in `game.save`). *Built (2026-11-01):* the chest part of W-e:
  `game.chest.opened` on every real open, `dungeons.set_opened_chests` and `dungeons.chests_get`; opened chests stay
  opened. Gates opened staying so comes with W1.1.
- **W1.1**: `set_zones` with 2 zones and one gate on one map. Walk from zone 1 to zone 2 without a load.
  *Built (2026-11-01):* `dungeons.set_zones` (2-4 zones, each in its own square of the grid, one gate between each
  pair; a layout that leaks round a gate is rebuilt), `dungeons.zones_get` (gates, key carriers, the player's zone),
  `game.dungeon.zone_entered` / `zone_gate_opened` / `zone_gate_locked`. A monster in the zone before carries the key.
  Vigil's *Vigil World preview* setting (off by default) makes each kept floor two zones of five rooms and keeps opened
  gates open. Checked in the game: locked gate, key, gate opens, zone 2 entered with no load. Each zone still takes
  the floor's own monsters (per-zone `source_floor` comes with W1.3).
- **W1.2**: shrines (light, rest, respawn, travel, town only from shrines).
  *Built (2026-11-01):* `set_zones({shrines = true})` puts a spring in each zone's shrine room (and no random ones),
  reported by `zones_get`; `game.dungeon.shrine_reached`; `dungeons.set_exits({town = "shrines"})` (the Escape menu
  refuses, the exit gate leads on); `dungeons.warp` and `dungeons.enter_floor` (W-d's respawn is the floor built
  again from its kept seed: monsters back, chests and gates kept, no second key). Vigil lights shrines per floor
  ("0:3:shrines") and opens Rest / Travel / Leave / Stay. Checked in the game: walking up opens the panel; Rest
  heals, rebuilds the same floor and wakes you at the shrine.
  *Levelling (2026-11-01):* the panel's fourth card (Stay before; Circle still stays) is **Level up**: the shrine tree
  on the Journal's Character page (`skills.register`, `ui.sheet_set`, `ui.sheet_open`), bought with Gilda and refused
  away from a shrine. Vigour (+5 max HP for the whole party, 20 ranks), Endurance (gauge refill +10%, 10 ranks), Guard
  (holding the guard slows the refill 5 points less, 10 ranks). A level costs 150 Gilda, then about 12% more each
  time. Ranks are kept with the save ("tree") and shown on the engine's tree. Checked in the game through the real
  page: Cross on Vigour took 150 of 1000 Gilda and raised max HP from 70 to 75. Floor scaling still reads the
  player's level from the weapon: a level bought at a shrine is the player's own edge, not a reason for monsters to
  rise.
  *Waking (2026-11-01):* the shrine reached last in each dungeon is kept ("rest:0"). Coming in from town to its map
  starts you in front of it (another map of the dungeon, or another dungeon, starts as ever). A knockout
  (`game.dungeon.defeated`, new) still fades to town; once the town is up Vigil takes the party on to that shrine,
  healed, the map built again with its monsters back. Checked in the game: knocked out on Divine Beast Cave's first
  map, the party woke at floor 2's shrine on the same map, and coming in from town (`enter_floor` with no cell, as a
  town's entrance does) arrived there too. The half of the Gilda a knockout takes (the game's own rule; ABS isn't
  touched) and the equipped weapon's unspent ABS (as section 6 decided; `weapons.abs_add` now takes a negative
  amount) lie where the party fell ("fallen", shown on the map): walk there to take them back; fall again first and
  they're gone. Checked in the game: the dagger's 33 ABS went to 0 on the knockout and back to 33 at the spot. Checked in the game: 500 Gilda, knocked out at the shrine, 250 in town, 500 again on waking there.
  Found on the way: every main floor's back floor is built with it, and Vigil had taken that for the player being
  on a back floor, which kept the map screen showing "Back floor" and stopped the map being kept; it now asks
  `world.get().back_floor`. A monster could stand in a shrine room and set upon a party that had just woken; now
  no monster starts within two and a half cells of a shrine (checked: woken, then standing still at the shrine for 50
  seconds, untouched). Arriving by `enter_floor` or `set_arrival` no longer reports a walk from the zone the floor
  first stood the player in (it had toasted "floor 1" on waking at floor 2's shrine).
- **W1.3**: a whole Divine Beast Cave as 3 regions (floors 1-4, 5-7 and Dran, then 9-15), with atla and the story
  bookkeeping checked.
  *Built (2026-11-01):* per-zone `source_floor` in `set_zones` (each zone loads and stands its own floor's monsters,
  lays its floor's atla, fills its chests from its floor's items; up to 40 atla on a floor), `exit_floor` (the exit gate
  leads past the region), `dungeons.set_arrival` (start at a zone's shrine), `zone_floors` in `zones_get` and
  `floor_id` on `zone_entered` (which raises `floor_reached`, so the entrance's list offers every floor of a region
  walked into). Vigil's *Regions* setting (on with the preview) makes Divine Beast Cave four regions: floors 1-4, 5-7,
  9-12 and 13-15, with Dran's floor 8 left as the game builds it. Floors 9-15 were split in two because seven floors'
  monsters didn't fit one map's model budget and zones stopped at four (W2 raised both and joined them). A region is kept under its first
  floor; its shrines are named by their floor. Checked in the game: floors 1-4 as one map, each zone with its own
  floor's monsters and atla; entering by floor 3 starts at floor 3's shrine with floor 3's monsters. Not yet: the HUD
  shows the floor you came in by, not the zone's.
- **W1.4**: floor scaling.
  *Built (2026-11-01), in Lua:* Vigil's *Floor scaling* (on with the preview). Zone base = 1 + 2 x floor + zone; player
  level = 1 + (weapon attack - the dungeon's starting attack) until the tree exists; monster level = max(base, player
  - gap), gap 2 by default. Each monster is scaled once as it wakes (`entities.set_stats`): life x(1 + 0.12 per level
  over its zone, + 0.1 in a floor's second zone), hits x(1 + 0.06 per level, at most x2), rewards x(1 + 0.05 per
  level). Checked in the game: a 23-life monster on floor 1 meets an attack-30 weapon at 73 life.
- **W2**: raise the limits, and make Divine Beast Cave one map.
  *Built (2026-11-01):* `DNG_GRID` 96 (from 48), `DNG_ROOM_MAX` 160 (from 64), up to 8 zones (a snake two squares wide),
  48 monster kinds and the whole model arena for them (about 2.5M quadwords, from 507K), 80 atla. Floors built without
  zones are unchanged (rooms stay in the build area; the whole-grid spot search keeps retail's 196 cap unless zones are
  asked for). The HUD's floor number follows the zone. Vigil's Divine Beast Cave is now two maps: floors 1-7 (seven
  zones, 35 rooms) and 9-15, with Dran's floor 8 between as the game builds it (a scripted boss floor, a load either
  side, as planned). Checked in the game: both maps, every zone with its own floor's monsters and atla, each shrine
  reachable (a room divider could wall one off; fixed), the HUD reading the zone's floor; floors 9-15 load 483K of
  monster models. The map ending on the dungeon's last floor leads its gate to floor 15, which, as in retail, has no
  exit. Not yet: other dungeons as one map (needs each one's boss floors listed); merging the two maps across Dran.
- **W2.1**: a map you can read, and travel by (from the first play of W2).
  *Built (2026-11-01):* a map screen (`ui.map_open`): Select or L3 (M on the keyboard) in a dungeon pauses play on the
  whole place as far as you have seen it, rooms as blocks and roads as lines, with its shrines (lit or not) and locked
  gates once found, you, and a cursor; Triangle puts the waypoint, which the mini map flags too. What you have seen of a
  kept place is kept with it ("0:0:map", `dungeons.map_snapshot` / `set_seen`), so it is still there on the next
  visit and in town: in the dungeon's town L3 or M opens every place of its dungeons you have been to (L2/R2 between
  them), and Cross on a lit shrine travels there (`enter_floor` from a town, with `dungeon_id`). Select stays the
  game's Georama button in town. The mini map on a region-sized map shows the part around you, scrolling, at a size
  you can read; the waypoint is held at its edge when it lies outside. Also fixed from that play: leaving the dungeon
  could crash (a Norune event asked for a texture the baked set lacks: it now falls back to the source decoder), and a
  region got one floor's chests (now each zone's; 35 on the floors 1-7 map); a place kept by an older layout starts
  again as new (its seed no longer gives the same map, so its opened chests would have been the wrong ones). Checked
  in the game: the map in a dungeon and over Norune, waypoint, marks, pages, travel; the scrolling mini map. Not yet
  checked with a pad: Vigil's own Select / L3 binding (headless runs press the game's pad, not a mod's binding).
- **W2.2**: every dungeon as one map before its midway boss and one after.
  *Built (2026-11-01):* the boss floors were found in the game (entering each candidate and seeing which are fixed
  maps rather than built from a seed): the midway floor (`CenterFloorTbl` less one) and the last floor of each dungeon;
  Gallery of Time has no midway boss. Vigil's `REGIONS` now covers all six: Divine Beast Cave 1-7 / 9-14, Wise Owl
  Forest 1-8 / 10-16, Shipwreck 1-8 / 10-17, Sun and Moon Temple 1-8 / 10-17, Moon Sea 1-7 / 9-14 and Gallery of Time
  1-8 / 9-16 / 17-24 (eight zones at most), each map's gate leading to the boss floor after it. Divine Beast Cave's
  second map had wrongly taken in its last floor (a fixed map); it now stops before it, and a save that kept the old
  shape starts that map again as new. Checked in the game: all 13 maps build with a zone, a shrine and a gate per
  floor and the right exit, the largest (Gallery 17-24) loading 651K of the 2.5M monster model budget. Not yet:
  played through with a story save past each midway boss; Demon Shaft stays floor by floor.

### Playtest 1 (2026-11-01)

From the user's first run through Divine Beast Cave as Vigil World:

- **One map per dungeon.** Every floor up to the last boss's is a zone of one map (Gallery of Time: two maps of
  twelve). The engine takes up to 24 zones (a five-wide snake past eight), 160 chests, 768 events.
- **Smoke floors.** The story floors (the game's no-atla floors: Divine Beast Cave's 4, the skeleton; 8, Seda; 11) sit
  on the map as small zones behind smoke gates, walls no key opens. Walking up to one offers the floor itself, played
  as the game has it; its own way down leads to the next floor's zone of the map, and from then on the smoke is gone
  and the small zone is walked through. The floor before 8 had been folded into the region, so its scene never ran:
  that is why floor 8 came up empty.
- **Shrines.** The panel opens with Square while standing in the spring's water, not on arrival. The water quenches
  thirst but no longer heals (`shrine_heal = false`); Rest heals and cures poison, curse, goo, freeze and stamina.
  Travel lists every lit shrine, three to a page with More; on one map, travel is a warp, with no stairs.
- **Death drop.** The lost Gilda lies at the fall spot as a pile of gold (`dungeons.drop_gilda`), on the corner map
  too, with the map screen's mark; walking up to it gives back the Gilda and the weapon's ABS.
- **Teleport, not stairs.** A rest, a wake, travel, coming back in from town and coming out of the smoke arrive in the
  escape item's light: the floor's stairs walk-in plays out unseen (`teleport = true` on `enter_floor`,
  `set_arrival`, `warp`). A story scene the floor opens with (the Mayor on floor 5) still plays.
- **Smoke door out.** On the story floor itself, the gate that wants the floor's key asks "Leave through the smoke?"
  (`dungeons.set_story_exits`); *Leave* goes back to the map at the next floor's shrine, by teleport, and the smoke
  over that floor clears. Checked in the game through the skeleton's floor 4 to floor 5's shrine.
- **A wall of smoke.** A shut smoke gate is drawn as a curtain of pale smoke rising in front of its door (the engine's
  `SmokeGatesDraw`, within nine cells of the player), and stays a hard wall. The floor title card names the zone's
  floor, as the corner number does ("B 2" on floor 2's zone).
- **Floor 11.** Unlike 4 and 8 it is a generated floor of the game's own ("Toan was summoned", no other characters),
  so there is no fixed far gate to ask at: its own key door and stairs lead down, which builds the map again at floor
  12's shrine with floor 11's smoke cleared. Checked headless through the smoke gate, the floor and the way down. Its
  script hands control to Xiao; on a save without her (a test save, or a map reached out of the story's order) the
  engine now leaves Toan in control instead of crashing on a weapon file with no name. A smoke gate's touch reaches
  150 units (a keyed gate's stays 130): its wall stops the player about 131 out along some approaches.
- **Floor 8.** Checked headless through its smoke gate: the floor loads, the Seda scene, his QTE and the knockdown play,
  and Toan is free on the floor with Floor 8 in the corner. At its far door (`gatekey_2`, stood on by a test-only hook,
  since a ledge defeats blind steering) "Leave through the smoke?" comes up; *Leave* lands at floor 9's shrine with
  floor 8's smoke gate and the next one open. A no-heal shrine's water no longer says "Recover health and thirst here"
  when Cross is pressed in it.

## 10. Open world (goal: walk from town into the dungeon and between towns, no loading)

**Goal.** Each dungeon is one open place you walk into from its town, with no floor menu and no loading; the
story floors are fenced off with smoke; then the towns are joined so you can walk between them. Built in the order
below; each step is playable on its own and checked in the game before the next.

### Playtest 2 (2026-11-01): fixes first (step O0)

- **Leaving floors 4 and 8 went to floor 15.** The native way out of a story floor asks for "the next floor", and the
  engine's region redirect (`set_zones exit_floor`) still matched on the story floor's own fixed map, so it sent the
  player past the whole region. The redirect now applies only on the generated, zoned floor itself.
- **Dran's floor was generated.** Each dungeon's boss floor was the region's exit floor and got built as a zoned
  floor, with Dran outside the map. The boss floor becomes the region's last zone, a **smoke floor** (DBC 15, Wise Owl
  17, Shipwreck 18, Sun and Moon 18, Moon Sea 15, Gallery 25).
- **Floor 11 isn't a story floor**, only a Xiao-only floor (no atla because only Toan gathers it). It is an ordinary
  zone of the map now, and so is each dungeon's other character floor, found by entering every no-atla floor and
  logging its `_SET_MAIN_CHR`: Wise Owl 12 (Goro), Shipwreck 12 (Ruby), Sun and Moon 13 (Ungaga), Moon Sea 11 (Osmond).
  The other no-atla floors switch character only for their scene or boss and stay smoke.
- **A boss floor's smoke stays** after the boss: it is the door to the game's own boss floor, which plays as the
  game has it once the boss is beaten.
- **No floor selector.** Entering from town goes straight in (`dungeons.set_floor_select`); Vigil starts you at the
  shrine you last rested at. Walking the map marks floors as reached, which is what let the selector offer floor 15
  early (the soft lock).
- **The map's key (Dran's Crest, the yellow gate).** Any monster on the map may carry it. It is kept through a
  knockout, and it comes once: a second one is paid out in Gilda instead.
- **Spring text.** A shrine's water no longer says it heals.

### O1. Into the dungeon on foot

Built so far: **no loading card** between town and dungeon (`dungeons.set_quick_passage`, on for Vigil World saves):
town to the cave measured 39 frames headless against 436 with the card, and the town is ready about 400 frames
sooner on the way back. Next, in order:

1. **Play check** of the entrance from Norune: does the town ask before going in (a yes/no), and is the fade short
   enough to read as a walk? If there's a prompt, a mod switch skips it once the dungeon is open.
2. **Safe ground** (built, not yet seen in play): `set_zones sanctuary = true` makes each shrine's circle (400 units,
   the circle no monster starts in) a wall to monsters: one that steps in is put back at its edge. Vigil turns it on.
   Headless runs couldn't show it (the test floor's monsters never moved toward the player, with or without it).
3. **The Fairy King** in the dungeon (built 2026-11-01, uncommitted). On a region map the dungeon's floor-start
   program (100 in `dun/script/d01/event.stb`) runs once, for the map's first floor, so his later scenes never came.
   His scenes: floor 1, e29 (program 199, flag 103, still plays on arrival as the opening); floor 3, e32 (flag 106);
   floor 5, e30 (flag 104); floor 7, e31 (flag 105). `art/vigil/patch_dbc_king.py` builds
   `resources/dun/d01_event.stb` with programs 191-193 that play the three (set the flag, fade, scene), shipped like
   Opar's house script. His model is `c03c`, the cave's scene pack `dun/d01/event/e28c03c.chr` (dungeon NPC 0,
   `d01o03_m`, is a waterfall; `c07a` is Seda). Vigil loads him into NPC slot 1 (`dungeons.set_npc_models`), stands
   him beside each such zone's shrine while his scene is unheard (`set_npc_marks`, kept as `king:<d>:<floor>`),
   Square beside him plays it (`dungeons.play_event`), and `game.dungeon.event_ended` builds the floor again at that
   shrine. Seen headless: his model drawn on floor 1, his spot at floor 3's shrine and its prompt, scene 192 and the
   rebuild after it, and the talk itself (the input script holds `key:E`, which mod bindings read): E beside him
   played floor 3's scene and the floor was built again at its shrine. He faces south (facing 0), into the room.
   Later: the other dungeons' King scenes.
4. **True co-loading** (the town and the first zone in one place, no fade at all) is the large engine step: the town
   (edit mode) and the dungeon are separate game modes with their own loops and memory. It is planned after 1-3 work.

- The dungeon entrance in town becomes a path: once the dungeon is open, walking into it continues straight onto
  its first zone (the town and the dungeon's first zone loaded together, or a seamless swap hidden by the walk), with
  no menu and no loading screen.
- **Safe ground.** Town and the first stretch of the dungeon are no-spawn, no-aggro zones: monsters don't start
  there and won't follow you in.
- **The Fairy King** stands at the start of the floors that have his scene; walk up and talk to him and that floor's
  scene plays (instead of it playing on arrival).

### O2. Towns joined: one continuous world (the user's choice, 2026-11-01)

- Walk between Norune, Matataki, Queens, Muska Lacka, Yellow Drops and Brownboo along roads, the dungeons opening off
  them, with no world map and no loading between them.

Chosen over "roads as dungeon maps" and "town edge to next town": towns, roads and dungeons as one space with no
fades. What stands in the way (read 2026-11-01): a town is edit mode (`editloop.cpp`: georama ground, villagers,
scripts) and a dungeon is dungeon mode (`dun/gameloop.cpp`); each mode's init calls `InitializeDataBuffer`, which
empties the one global heap (`dataset.cpp`) and carves that mode's arenas from it, so only one side exists at a time.
Today a town-to-cave switch with quick passage shows ~33 black frames while the cave builds, then a ~60 frame fade in
(`q_seam` capture). The steps, each playable on its own:

- **C0. The cut.** No fade and no black between town and dungeon: the last frame drawn stays on screen while the
  other side builds, and the first frame of the other side replaces it. The player walks into the cave mouth and is
  in the cave. Engine: quick passage skips the fade out/in and holds the presented frame across the mode init.
  *Built 2026-11-01:* `MapJump` starts a hold (quick passage, town to dungeon or back); `MGEndFrame` draws the last
  good frame over every frame until the other side is ready (a dungeon 4 frames after its floor is built, a town
  after 4 walk frames, an arrival event pausing the count), at most 600 frames; every Ed fade in while held, and the
  arriving place's first one, takes one frame. `q_seam` capture: cave to 292, town at 293; town to 520, cave at 521.
- **C1. Both kept, live (connected worlds).** The user (2026-11-01): the picture windows "seem fake"; wanted are
  "true connected states", the town and the dungeon loaded at once, since these mods run on PCs. So the town and
  the dungeon each keep their own world in memory, both stay alive, and each is drawn live through the other's
  door. The picture windows of C2's first step are off (`DC_DOORWAY_PICTURES` turns them back on for comparison);
  their door finding (where the party left, where it stands once walked in) stays for the live view.
  What one mode switch throws away today, and what replaces it:
  - **L1. Arenas by world.** Every arena is a host block per owner (`platform/arena.cpp`); a mode's init re-carves
    the same owners (`VisualData`, `MotionData`, the edit arenas...) and `ArenaClearAll` zeroes them all, so the
    dungeon writes over the town. Blocks are kept per owner *and* world (town, dungeon; everything else world 0),
    and a clear zeroes only the current world's. Off unless connected worlds are on, so nothing else changes.
  - **L2. A texture manager per world.** Both inits call `TexManager.Initialize`, which drops every texture. The
    registry's keys are already virtual (one 14-bit space, round robin), so each world gets its own
    `CTextureManager` and releases only its own entries; `TexManager` names the current world's. The key space is
    widened if two worlds fill it.
  - **L3. Going back is a switch.** Entering a kept world restores its arena descriptors (base, limit, used) and
    globals the other mode touched (camera, packet and read buffers) instead of loading again: the town is as you
    left it, villagers and time, the dungeon floor with its monsters.
  - **L4. Seen live.** Each mode's draw also draws the other world's ground through the door, with the other
    world's texture manager current and the camera taken through the doorway transform (the door planes laid on
    each other): the cave's first room seen from Norune's door, Norune seen from the cave's stairs, moving as you
    move. Then the other side's characters (villagers, monsters) drawn, then stepped.
  - **L5. Walking across.** With both alive the hand-off at the threshold is the switch of L3, in one frame; the
    door's own open animation (the stone door slides open in the game's event) plays first, its fade to black
    taken out.
  *Built 2026-11-01 (L1-L5):* arenas and the texture manager are kept per world; each tick the
  other place is drawn live into the doorway (`DoorwayLive`: the camera taken through the door, its near plane at
  the door, the other place's own lights and textures) and shown in the door. The dungeon's door is set into the
  wall behind where the party arrives (found along the party's heading with the collision); walking into it,
  facing it, goes to the town and stands the party just outside the town's door, facing out. The town's door
  event no longer fades to black, so the stone door slides open onto the cave and the walk-in follows. Checked
  headless on a copy of the user's save (Norune's cave door, floor 14) with quick passage forced on. L3 too: a world left is kept (its carved arenas, the town's hand-laid NPC, villager, work and menu arenas, and the
  read/work/active pointers), and walking back through the doorway switches to it (`ResumeDataWorld`, `EditResume`):
  no file is read again, the villagers stand where they were, the event script is read again and the start event runs,
  and the door's event plays again for the next trip in. The party arrives 110 units out of the town's door so the
  camera fits behind them (closer, the town camera's wall rule swings it round to the front). Checked headless on a
  copy of the user's save (town, cave, back, cave again). The dungeon side too (2026-11-01): walking back in through
  the town's door onto the floor left there (the first floor, whose doorway is placed) switches to the kept dungeon
  world (`GameResume` in `dun/gameloop.cpp`) instead of building the floor: the same layout, its monsters where they
  were, chests and event flags as left, the party standing 80 units inside the doorway facing in, with
  `game.dungeon.resumed` for mods (no `generating`/`generated`). Left from a deeper floor (or a save loaded, or the
  title) the floor is built as before. Checked headless: town, cave, town, cave again, the Dasher that followed the
  party to the door still there. The first visit too: a town with a known door into its dungeon (Norune's, in
  `kTownDoors` in `doorway_view.cpp`) builds the dungeon's first floor unseen as it loads (`DunPrebuild`: the opening
  script run to its end with the walk-in skipped; no save, no sound, `prebuild = true` on generating/generated), so the
  stone door slides open onto the cave the first time, and walking in goes back to that floor. A floor whose opening
  would play an unheard scene is not prebuilt (Vigil holds the Fairy King's before the town loads, so his isn't one).
  The cave's way out no longer shows a black arch: that was the dark hollow Norune builds behind its door, now clipped
  away, so the village shows in daylight. The cave's own door at its way in (the entrance piece's `in_door`, which
  rises and falls) is no longer drawn, so the only door is the town's sliding one, and the cave's window stands just
  behind the rock: only the arch shows the village. Once Norune's door has opened (its program 130 run through to the
  jump), it stands open for the rest of the play: the town slides its halves apart as it loads
  (`DoorwayStandTownDoorOpen`, from `kTownDoors`: fixed part 3's `door1`/`door2`, 18 each way), and facing into it
  walks the party in with no button and no door scene (`DoorwayOpenTownDoor`). Loading a save closes it again.
  The other towns: only Matataki has a way into its dungeon on foot, the forest path its program 3 walks the party up
  (to -1287, 31, -375, then `MAP_JUMP` to 201); it is in `kTownDoors` with no door halves. Queens, Muska Racka and e05
  have no jump into a dungeon in their scripts or map points: their dungeons are reached from the world map, so
  there is no door to see through. Wise Owl Forest cannot be built unseen yet (its walk-in waits on an action
  sequence that only real frames move), so the prebuild gives up after 120 frames, the town does not try again until
  a save is loaded (`DoorwayPrebuildFailed`), and the forest is built on the first walk in; from then on it is
  connected as Norune's cave is (walking out resumes Matataki, walking back in resumes the forest, both checked
  headless).
- **C2. Seen across.** Became L4 above. The user's words (2026-11-01): no fade in or out; "the door opens and I
  walk", "I can look in and see the dungeon in front", and turning round inside the dungeon "I would be able to see
  the village". *Picture windows built 2026-11-01 and turned off the same day* (`doorway_view.cpp`): leaving, the
  place was drawn from its door looking back in and copied; the other side drew it in its door as a window. It
  worked headless (the cave's room through Norune's stone door, the village behind Toan on the cave's stairs) but
  is a still picture, which the user rejected for live worlds.
  Real door, checked on a copy of the user's save: Norune's cave door (event point 1, destination `dungeon`, at
  910,-7,-498, facing 1.57, range 20) takes cross, slides open, Toan walks in, then the event fades to black before
  the jump, so the cut holds a black picture there until L5.
- **C3. Roads.** Outdoor maps between towns, entered from a town's edge with the same hand-off, their far end the
  next town; the dungeon entrances open off them. The world map is then only a map.
  *L6, the road, built 2026-11-01 (uncommitted):* no outdoor maps yet. There are none to use: the game's fields
  (s01-s36) link towns to dungeons, never town to town, and `locations.register` copies only the four on the world
  map. So a town's gate is the road itself. Each town's gate is its program 1 (fade, `WORLD_MAP`, `MAP_JUMP`), run
  from ground polygons of kind 1 beside where the world map sets the party down; with `world.set_roads` on, that ground
  sends `game.town.road` instead (once each time the party walks onto it) and the world map never opens. Norune's
  spot faces a fence, Queens' kind-1 ground is not near its spot, and Yellow Drops has no program 1, so those three
  take the road at the spot itself, facing out (`DoorwayTownRoad`: Norune -780,-342; Queens 1407,44; Yellow Drops
  0,-560). Vigil asks which way on a `ui.choice_open` panel (now also open in a town's walk, the town going on around
  it): the towns lie along one road, Norune - Matataki - Queens - Muska Lacka - Yellow Drops, and the dungeons only the
  world map reached are on it too (Queens: Shipwreck; Muska Lacka: Sun and Moon Temple; Yellow Drops: Moon Sea and
  Gallery of Time; in at floor 1 by `dungeons.enter_floor`). A jump between two towns holds the picture as quick
  passage does between a town and a dungeon. Checked headless on the user's save: Matataki to Norune and back, each
  town's gate opening the panel, and each of the four dungeons entered from it. The towns reached by road are loaded
  again, as the world map loads them, not resumed: a town's live objects (the party, villagers, ground) are shared
  statics the next town overwrites, so only the dungeon's way out, back to the town whose objects are still live, can
  resume one. Story floors stay behind smoke (they are fixed maps with their own scripts, so they can't be zones of a
  region), but going through is now quick passage too: a jump between two floors of one dungeon holds the picture
  (black, after the floor's own fade out) until the party can play on the next, with no loading card (checked
  headless: Divine Beast Cave floor 1 to the skeleton's floor 4, straight into its stairs walk-in). Every floor of
  every dungeon was then entered in turn on the user's save (a probe stepping `enter_floor` through each, 240 frames
  played on each): all build and play, story floors included. Sun and Moon Temple's story floors 4 and 7 go out to the
  desert field (s32, map 42) for their scene and come back by themselves; the held picture is only for the five towns,
  or it froze on that field for its full ten seconds. The panel opens in a town only because Vigil asks (`ui.choice_open` `town = true`; the Gauntlet retries
  its panels until one opens, and must keep waiting for the dungeon). Not yet: a town reached ahead of the story plays its
  arrival scene (Matataki's, unless story flag 9 is set; checked headless, it plays through and hands the walk back) and its dungeon's story gating is the game's own.

### Order

O0 (fixes) → O1 (one dungeon, DBC from Norune, then the rest) → O2 (towns, Norune to Matataki first).
