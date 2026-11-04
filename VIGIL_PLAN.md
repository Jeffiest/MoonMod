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

**Built 2026-11-03 (not yet played by hand).** E1 is `player.guard_rules_set` / `guard_rules_clear` and the
`game.player.hit` event; E2 is `player.gauge_rules_set` / `gauge_rules_clear` (the first swing's gate and cost hook
every character's native attack button, not each `*Key_On`); E3 is `player.gauge_get`, `player.gauge_set` and
`player.state`. The rules live in `guard_rules.cpp` and `gauge_rules.cpp`, unit-tested. Vigil turns them on with the
§3 numbers (settings *Souls guard* and *Souls stamina*) and answers a parry with a stop and a shove. Found on the way:
`player.tuning_set`'s `recoil_scale` and `invincible_bonus_frames` had not been applied since `BtCheckDamageProc`
moved into `src/game/dun`; they are again, so Vigil's shorter hit stun (and the Gauntlet's and RPG's recoil perks)
work for the first time since then. Then, in Lua on top of them: **Exhausted** (an empty gauge
makes swings deal 30% for 1.5 s, with the HUD's blinking stamina badge) and the **riposte** (after a parry, the next
blow on the parried enemy within 2 s deals ×3; a formula can only name an enemy kind, so it is scoped by
`native_model_id` and spent on the first blow on that entity). Not done from §3: Exhausted doesn't yet stop evades or
break the guard beyond what the empty gauge already does.

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
|   | *Built 2026-11-03 (not yet played), patrols:* a crowned elite whose family has an enemy brain walks a beat while you are more than 420 units off: a cross of four legs from where it was crowned, back through the middle each time, turning back early at a wall (the brain's own blocked count). Nearer, it fights as the brain does. *Elite patrols* is a setting. Not yet: beats along chosen corridors (no op reads the floor's cells from Lua).
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

---

## 11. Gear and running (from a talk with SirFancyBacon, 2026-11-01)

**The ideas.** Amulets take one of the three quick slots, so carrying protection costs you a heal. Give them a slot
of their own. Then replace Dran's Feather with a real run, turn the weapon's Speed into how light the weapon is to
swing, give each character a Stamina stat, and grow the charm slot into gear (hat, tunic, gloves, boots) with
rarities and effects such as a chance to shrug off an ailment.

**What the game does now** (read from Chronicle `9418a550` + the patch):
- The four amulets (Anti-Freeze, Antidote, Anti-Curse, Anti-Goo) already work passively, but only from a quick slot:
  when a hit rolls an ailment (`gameloop.cpp`, the `hit->flags` checks), `CheckActItemSlot` looks through the three
  quick slots, and a match blocks the ailment and spends one use (`SpendQuickItem`). The amulet breaks when its uses
  run out.
- Dran's Feather is a quick-slot item too: held Square with it selected sets `BtBySpeedFlag`, which doubles the walk
  (1.45 to 3.0 a frame) and pulses the model blue, spending a use every frame.
- The action gauge refills by the weapon's Speed / 30 a frame (then per-character factors and `gauge_refill`).
- The item page draws the quick slots top left (`ActiveItemDraw` at 58,74), the bag board from y 120 on the right
  (`DrawPersonalBoard` at 340,120) and the trash bottom right, so the upper right above the board is empty.

### G1. The charm slot (built 2026-11-02, not yet played)
*Built:* `charm_slots.hpp/.cpp` in the engine, `items.charm_slots_set({count})` and `items.charm_slots()`, Vigil's
*Charm slot* setting (on, one slot). Each character has their own (the user's call: the active character's guards
when hit), and an amulet in one is out of the bag, taking none of its room. On the item page it sits beside the weapon and the shield (the user's choice, over the
empty top right), an amulet blacked out while it is empty; Right from the shield reaches it,
Cross puts an amulet in or picks it up, Square sends it to the bag; anything but an amulet is refused. In a hit, a
charm slot's amulet guards first, then the quick slots as before. Kept beside the save as `charms.json` (written and
read with it, like `characters.json`). Checked: unit tests, and headless on Divine Beast Cave (an Antidote Amulet
moved from the bag into the slot, its card shown). Also (the user's asks): the worn charm shows on the dungeon HUD
left of the gate-key plate with its uses left in the corner (the item page's slot shows them too; its icon is copied
into a free 48x48 corner of the HUD sheet with the quick slots'), and an amulet sells for its price times uses left
over full uses, nothing below half. Checked headless: the HUD icon and its count, the page's count; the price by unit
test only. Not yet seen: an amulet actually blocking poison in play, or a worn one at a shop. Later:
a "Charm" label on the page, and more slots from the shrine tree.

- One slot on the item page, in the empty upper right, that takes only charms (the four amulets, and later mod
  items marked as charms). A charm there works exactly as from a quick slot: it blocks its ailment when a hit rolls
  one and spends a use. The quick slots keep working as before, so nothing is lost for a player who never uses it.
- The engine holds the slot count (0 = off, the retail game; Vigil sets 1) and the slots' contents; more slots unlock
  later (Jeffie: "a way to unlock more slots" for curse plus poison), up to 4, for example from the shrine tree.
- Saved through the mod: the engine reports and accepts the slots' contents, and Vigil keeps them with the save as it
  keeps opened chests. If the slots are switched off, whatever is in them goes back into the bag, never lost.

### G2. Running instead of Dran's Feather (built 2026-11-02, not yet played)
*Built:* `dodge_run.hpp/.cpp` (a tick-by-tick state machine, unit-tested) and `player.tuning_set` `dodge_run` (gauge a
second, 0 = off); Vigil's *Run cost* setting (20). L2 held 12 ticks with the stick pushed runs at 3.0 a tick (the
Feather's dash) and drains the gauge, which doesn't refill while running; empty, he walks until L2 is let go. A tap
dodges on release instead of the press (a fifth of a second later at most). L2 no longer swings the camera behind
(held, it would chase the run round in circles). Dran's Feather became a charm with a slot of its own (the user's
call: one slot for amulets, one for the Feather), right of the amulet slots, opened with the run
(`charm_slots_set` `feather`): halves the drain, a use per tick of running, its seconds on the HUD; the quick-slot
boost is off while the run is. Checked headless: walk 1.45 vs run 3.0 a
tick, 20 a second drained, 10 with the Feather, a tap still evading. Not yet felt by hand: the tap's release timing.
- Hold the dodge button to run (tap L2 rolls, hold runs, as in Souls). Running uses the dash speed (3.0, the
  Feather's) and drains the action gauge each frame; an empty gauge drops back to a walk.
- Dran's Feather leaves the run. Turn it into a charm (a lighter step: running drains less) so it stays worth finding.

### G3. Lightness and Stamina
**Built 2026-11-02.** Engine: `player.tuning_set` `lightness` (the refill reads every weapon as Speed 60; a swing costs
60 / Speed of the game's, clamped to 0.5..2, the combo's hard-coded costs and a mod's attack moves alike, evades
unchanged) and `stamina` ({id = gauge a second}, replacing Speed / 30 and the character factor). The rules live in
gauge_rules.cpp with a test that the untouched refill matches retail for every character, speed and state. Vigil: the
*Lightness and Stamina* setting (on), Stamina Toan 35, Ungaga 30, Goro 60, Osmond 80, Xiao 120, Ruby 180 a second
(each one's retail refill with their first weapon, rounded). Checked headless: Toan refills 0.583 a tick and his
dagger combo costs 21.4 a swing (25 x 60/70). The shrine tree's Endurance speeds every hero's refill 10% a rank.
**Labels, 2026-11-03:** `weapons.stat_label_set` puts a mod's image where the weapon cards' two-letter labels were.
The card under each weapon draws it in the label's cell; the Status tab, whose labels are painted into it overlapping
each other, is wiped to plain stone down the label column (strips of the clear band between Abs. and At) and all four
are laid again one size, each centred on its bar. Vigil sets all four, in the game's lettering
(tools/vigil/make_stat_labels.py), Speed reading **Lt** while Lightness is on and Sp otherwise. Checked headless on
both cards.
- The weapon's Speed becomes **Lightness**: it no longer sets the refill; it lowers what a swing costs from the gauge.
  Heavy weapons cost more per swing (backlog idea 14, equip load, comes with it).
- Each character gets a **Stamina** stat: the refill rate (and, later, the gauge's size). It starts from the
  character's retail feel (Toan and Ungaga slow, Xiao and Ruby quick) and grows with the shrine tree's Endurance.
- Engine: a per-character refill base the mod sets, and a swing cost scaled by the weapon's Speed. The weapon card
  shows Speed as "Lightness" in Vigil (`weapons.style_set`).

### G4. Gear
**Built 2026-11-02.** Engine: gear.hpp/.cpp, pieces a mod makes (`items.gear_give`) with a kind, name, rarity, value
and effects, in a bag of 99 beside those worn, one of each kind per character, kept as gear.json beside the save.
The worn effects are read in the hit (ailment guard rolled before an amulet is spent; defence), the refill
(`GaugeRefill.gear_stamina`), the swing cost (`ChroniclePlayerSwingCostScale`) and the run drain. Ops `items.gear`,
`gear_give`, `gear_equip`, `gear_unequip`, `gear_remove` (sell). Vigil: the *Gear* setting (on); a chest holds a piece
one time in five, a beaten monster one in thirty; rarity common/fine/rare/unique (deeper dungeons lean rarer) gives
1/2/3/3 effects at 1x to 4x strength (guard 15%, stamina 6, lightness 5%, defence 2, run cost 8% a tier), the first
always the kind's own (hat guard, tunic defence, gloves lightness, boots run cost); prices 60/180/450/1200. Start in a
dungeon opens a Gear screen (`ui.run_menu_set`): Worn, Bag, Sell. Checked headless: a piece given, worn and summed
(defence 10, stamina 30, poison 90%), and the Gear screen drawn. Not done: no gear slots on the game's item page and no
icons (the run menu shows them); shops don't stock gear; not yet played by hand.
- Four more slots per character: hat, tunic, gloves, boots. Pieces drop or are sold with a rarity (common, fine,
  rare, unique) and one to three effects: a chance to negate an ailment, Stamina, Lightness, defence, run cost.
- The charm slot's engine work is the base: slots with a kind, items that declare a kind, and effects the engine
  reads where the game does (the ailment roll, the refill, the swing cost). Items and art come after G1-G3 play well.

### G5. The gear on the item page
**Built 2026-11-03.** Asked for: the character card replaced by the hero alone, HP and water over his feet, a weapon
dragged to his hand, the charm and Feather slots in a column, and gear as real inventory in a new tab with coloured
pieces. Engine: `items.gear_page_set({icons})` opens it; pieces carry `icon` and `color`. The board gets a fourth tab,
Equipment (the bag, its plate pieced from the Items one), with pick-up, put-back and the trash can, and the help box
names the piece. The hero page: the model 1.1x and centred, a soft shade behind, the charm column, the weapon (attack,
durability bar) and shield (defence), four gear slots with each empty kind blacked out; Cross swaps a piece in, takes
one into the hand; Square takes it off. A weapon from the Weapons tab dropped on the hand is equipped with Equip's
checks (an Osmond or Ruby in play is refused: the weapon effects can only load in the weapon menu). The mouse: the
hero slots and the fourth tab have hit boxes; drags carry gear as items. Vigil: four greyscale icons
(tools/vigil/make_gear_icons.py) tinted by each piece's first effect; the Start-screen Gear menu is gone. Checked
headless: the tab, a hat worn from the bag, a weapon put back on the hand. Selling (2026-11-03, below) is in the
shops; the mouse drag is untested by script; not yet played by hand.

**Polish, 2026-11-03.** The pieces are the hero's own clothes: `gear_page_set` takes `parts`, frames of each hero's
menu model per kind, and the engine draws only those, grown to fill the slot, turned and tilted to show them, on a
ground of the piece's colour (dark when the slot is empty), in the slots, the bag's cells and the hand. Vigil names
Toan's (`boushi`; his vest `cloth2` and `cloth3`, drawn as it hangs at rest, with the belt `beruto`; `l_g` with
`l_hand`; his shoes, part of his body `skin`, shown alone below a cut a third of the way down his ankle wrap `l_f`
(`below`) and seen from the side; his satchel `kaban`). The other five are named too where they have the piece (Xiao's
paw and shoes, Goro's mantle, Ruby's tiara, hand and slippers, Ungaga's cap, sash and bracer, Osmond's goggles, glove,
boots and bag; `below` on a bone cuts at the joint), and a kind one has nothing for keeps its icon; the hero on the
item page and in the dungeon is known by which model is drawn, not by name. With no hat worn he goes bareheaded, with no tunic his vest comes off to the shirt and with no pouch his satchel
goes (`bare`), in the menu and the world; his gloves and shoes are part of him and stay. Each save dresses him once in
his own cap, vest and satchel, plain pieces, so he starts out looking himself, and Goro, Ungaga and Osmond in theirs once
they join; an empty slot whose clothes come off shows the kind's icon.

**Gear in the shops, 2026-11-03.** While the Equipment tab is open, a native item shop has it on the player's side:
Triangle on a piece sells it for its value through the shop's own "sell it?" question. `items.gear_stock_set({shop,
goods})` puts up to ten pieces with prices in a shop's empty cells after its own goods, drawn as in the bag, the help
box naming the one under the cursor and its price; Triangle buys one into the bag (refused past a full bag or a thin
wallet), and a bought piece is gone until the shop is stocked again. Cross never takes gear onto the counter or into a
deal. Vigil stocks all eighteen shops with three pieces each trip home from a dungeon, rolled as gear drops are for
the last dungeon, at twice their value. A shop whose own list is full (Norune's has 20) lays its gear in the board's
last ten cells. Checked headless in Norune's shop (`DC_SHOP_TEST=<shop>` opens one once the town is up): the pieces
on the counter with their prices, a buy (1000 to 640 G), a refusal on an empty wallet, and a sale from the
Equipment tab (640 to 820 G). Not yet played by hand.

**Pouch, 2026-11-03.** A fifth gear kind, `pouch`, in a slot at the hero's hip (the outer column; the page has it only
when the mod names its icon). Its effect `bag` grows the game's item bag, outside the game's Pocket upgrades: the
largest pouch anyone in the party wears counts (Vigil: 5 slots a tier, 20 for a unique), up to the game's 100. Taken
off, the bag shrinks as far as its items let, moving items down from the slots that go; the engine keeps what it added
in `gear.json` so the Pockets' size stays the save's. The
hero page sits on a panel in the help windows' frame, his side's column holding the amulet, the Feather, the weapon
(attack in the corner, wear up its edge) and the shield, the gear opposite, the HP line across his feet with the water
centred under it, and the help box says what Cross and Square do on each slot.

### Order
G1 (charm slot) → G2 (run) → G3 (Lightness, Stamina) → G4 (gear) → G5 (gear on the item page). Each gets a playtest
before the next.

---

## 12. Stretch goals (2026-11-03)

Ideas past the core plan, for once the fighting is right. Most of them read `game.player.hit` or the gauge, so
**E1-E3 (§2) are still the first thing to build**, before any of these. Engine limits in the way get raised, not
worked round (*Extending the engine*).

Ranked by how much they would change the game for what they cost. Recommended first: 1-5.

### Fighting

| # | Goal | What the player gets | How | Cost |
| --- | --- | --- | --- | --- |
| 1 | **Every family has a brain** | Today only Dashers and Skeleton Soldiers fight like Souls enemies; the rest are retail AI under ×2.5 damage. Every enemy should have a readable wind-up, a commitment and an opening. | Turn the two brains in `main.lua` into a kit: circle, take turns, feint, punish a whiff, guard, rush, as parts a family picks from a table keyed by native model id (as `BRAINS` is now). Then one family a dungeon at a time, fliers and ranged enemies by full takeover (§5's risk). Each gets one new attack motion from `tools/anim`. |<br>*Started 2026-11-03 (not yet played):* the brain was already table-driven, so a family is a `BRAINS` row. Added Master Jacket (0) and the Werewolf (4), both with their native guard; the Werewolf gets rolls and a new rake (`e07a_*`). Blow frames now come straight from each monster's script (`SET_DMG_COL` in `tools/stb/stbdis.py --table monster`), no in-game measuring. Master Jacket's rig is a deep chain with odd bone names, so it has no new motions yet. Same day, every other hand-to-hand family whose motions fit the layout (idle, walk, back, right, left at 0-4, guard at 5-7, attacks at 13/16): the Rash Dasher (the Dasher's rig, so its rolls and pounce too: `e63a_*`), White Fang, Mummy, Captain, Corcea, Curse Dancer, Sunday, Monday, Wednesday, Saturday, Hell Pockle and the four melee card soldiers. A family like another is a copy of its row with its own numbers (`like`/`landing` in main.lua). Left on retail AI: fliers, shooters and casters (Heart, Tuesday, Thursday, Gunny, Alexander, Mask of Prajna...), Friday and Rockanoff (a swing split over three motions), Arthur (attacks at 11/12), the walk-only Statue and Living Armor, the diggers and plants, and the bosses. `tools/vigil/monster_survey.py` prints a family's blows, guard and motions. | Lua, motions; large but even |
| 2 | **Poise both ways** | Enemies that trade through a light swing instead of flinching every hit; a heavy blow or a riposte breaks them into a stagger you can punish. The player gets poise from tunics, so armour finally means something. | §8 idea 3 for enemies (a poise table, skip the flinch program in the takeover). For the player, a `poise` gear effect read in `BtCheckDamageProc` next to `recoil_scale`: a hit under it doesn't interrupt the swing. A short engine op beside E1. | Lua, engine small |
|   | *Enemy half built 2026-11-03 (not yet played):* Vigil's `native.monster.run` hook skips program 110 (the flinch) while a monster's poise holds (2 blows, back after 2 s without a hit); the blow past it plays the flinch and a 40-frame `stop`; R2 and the finishers break it at once (`game.player.move`). The engine runs 110 once per blow (`CheckDmg`), so skipping it is safe. A braced family (a brain) carries on mid-swing; any other monster's hit still cuts its program, so it loses the flinch but restarts its idle loop. *Player half built 2026-11-03 (not yet played):* a `poise` gear effect (0-8 points, `gear.hpp`), decided in `ChroniclePlayerHitResolve` by `PoiseTakes` (`guard_rules.hpp`): a landed light hit costs 1, a heavy one 2, poise whole again 120 frames after the last hit; a poised hit keeps its damage but skips the turn, motion change and recoil in `BtCheckDamageProc`, and `game.player.hit` says `poised`. Traps, broken guards and lethal hits always stagger. Tunics carry it as their first effect (1-4 by rarity, *Stalwart*), and only tunics. | | |
| 3 | **Criticals with their own motions** | Backstab, riposte and the stagger critical play a paired animation, Toan's stab and the enemy's crumple: the one big hit Souls players chase. | §8 idea 4, then a paired-motion op: play a mod motion on the player and one on the target in the same tick, the target held (`combat.status_add{stop}`) and turned to face. Author the pairs for the two braced families first. | engine medium, motions |
|   | *Built 2026-11-03 (not yet played):* a `critical` trigger for `player.moves_set` (`backstab` behind an enemy within an arc, `riposte` on the enemy `player.critical_set` armed), with `pairs` of monster motions; the engine draws Toan in, turns the target, ends its `stop` (which freezes and greys it, so it can't hold a crumple) and holds its script instead (`ChronicleMonsterHeld` in `monstorunit.cpp`), then sends `game.player.critical`. Vigil arms a riposte on a parry (2 s) and a poise break (the stagger and half a second), and raises the critical's blows on that kind of enemy x3 for the hold (*Critical damage*). Toan's stab is `toan_critical` (`tools/anim/vigil_criticals.py`); the Skeleton and the Dasher crumple (`e03a_crumple`, `e06a_crumple`); other families are held standing. *Criticals* in the settings. | | |
| 4 | **Weapon arts from attachments** | Dark Cloud's synthesis becomes the build: an attachment or a weapon's build-up unlocks a held-R2 art (a thrust, a spin, a counter stance) that costs gauge. Two players' Daggers stop playing the same. | A table from weapon id or attachment to a `player.moves_set` move, refreshed when the weapon changes. The art shows on the weapon card (`weapons.style_set{details}`). | Lua, motions |
|   | *Built 2026-11-03 (not yet played), Toan's half:* an `art` trigger for `player.moves_set` (R2 while guarding) with `weapons` (native item numbers) and `min_level`: the equipped weapon (`NowWeaponHave`) picks its art and its build-up unlocks it, so it is the weapon and not an attachment (the game keeps attachments as stats, not a list). Toan's blades fall in three families: the short blades' Piercing Rush (a long lunge, two stabs, 35 gauge), the long swords' Whirlwind (two turns, five hits, 45) and the great swords' Earthsplitter (a slam with an explosion, 50), from level 3 (*Art level*). They reuse his attack motions played their own way; a motion of their own each is the next step. Each blade's card in the weapon menu names its art and when it unlocks (`weapons.style_set` `details`). The other heroes have none yet. | | |
| 5 | **The flask** | Healing as a decision: a refillable flask (charges grown by shards found in the dungeon) drunk with a slow motion you can be punished in, refilled at a shrine. No item-menu heals in combat (§8 idea 2). | A mod item in a quick slot with uses the shrine resets; drinking is a move with a drink motion; the pause menu's item use locked while `in_combat`. Shards are rare chest drops, one a zone at most, kept with the save. | Lua, engine small |
|   | *Built 2026-11-03 (not yet played):* not a quick-slot item after all. The game's quick-slot drink freezes every monster while you drink (`CMonUnitHold` in `movechara.cpp`), and a mod item can't be quick-used, so the flask is Vigil's own: charges kept with the save, a HUD line (`Flask 2/3`), D-pad Down (free in the dungeon) or a key. A drink is a `played` move (a new trigger, only `player.move_play` starts it) on each hero's native drinking motion (28) at half speed; it heals 40% of max HP at 65% of the drink (`frames` on `game.player.move`), and a hit that lands first spills it, the charge spent. Refilled at a shrine's rest and in town. A Flask Shard (15% of chests, one a floor, up to 7) adds a charge for good. `item_heal_lock` (a `tuning_set` key) makes HP-healing items refuse within 240 of a live enemy, in the item menu (`ItemUseFunc`) and from a quick slot (`checkItemUsed`), instead of an `in_combat` test (which is true on any floor with a monster left). Water and cures still work. | | |
| 6 | **Lock-on that feels modern** | Flick the right stick to switch target; the lock drops past a distance or behind a wall; a soft lock turns a swing toward the nearest enemy without locking. | Engine: the target choice in `movechara.cpp` takes a direction; a `tuning_set` key for the drop distance. | engine small |
|   | *Built 2026-11-03 (not yet played):* three `tuning_set` keys. `lock_flick`: in the dungeon loop (`MoonModLockOnExtras`, `gameloop.cpp`), a flick of the right stick moves the lock to the nearest enemy on that side of the target, read against the camera. `lock_sight`: the lock drops after half a second with a wall between (a straight line over an empty map cell, sampled every 40 units). The game already drops it past its own lock range. `soft_lock` (35 degrees in Vigil): not locked, a native swing or a mod move turns to the nearest enemy within 64 units and that arc. All three are settings. | | |

### Enemies and bosses

| # | Goal | What the player gets | How | Cost |
| --- | --- | --- | --- | --- |
| 7 | **Story bosses with a second phase** | Dran, Master Utan, the Ice Queen and the rest keep their arenas but turn at half life: a roar, a new tint, faster moves, one new attack each. A name banner, and an HP bar along the bottom of the screen. | The Wardens already fight with their native casts (`arena_slot`, `script_int_set`); a takeover on top of each boss's cast for phase two, `ui.boss_card` on entry, a bottom-of-screen boss bar (the small addition §8 idea 7 named). One boss at a time, Dran first. | Lua, engine small, motions |
|   | *Built 2026-11-03 (not yet played):* in Lua, keyed by native model (Dran 78 to the dark Dark Genie 106). On first sight there is a `ui.boss_card` with the boss's epithet, and a new `render.bar_register{boss = true}` bar along the bottom of the screen. At half life the boss roars (a burst and a word), turns red, rises to x1.3 damage, and gains `combat.status_add` haste, a new engine status that plays its scripted motions and moves 1.4 times as fast. The phase stays until the fight ends. Not yet: a new attack for each boss (that needs boss motions and a takeover of each cast). | | |
|   | *Built 2026-11-03 (not yet played), the new move:* in its second phase each boss casts a move of its own every six seconds: marks glint where it will land (a `guard` burst, again halfway), and 45 frames later the blow falls on each (`combat.strike_player`, a new engine op: one native hit only the player can be struck by, so guard, parry, dodge and poise take it, and stepping off the mark beats it). Dran breathes fire in a line to you, Utan stamps a ring around himself, the Ice Queen calls frost under you and beside you, the King's Curse rains curses in a square, Joe leaps onto you, and the Genie sweeps a beam. Each is a share of your life. *Boss moves* is a setting. Built 2026-11-04 for Dran: his fire breath has a motion of his own (`c12a_rear`, from `tools/anim/vigil_boss_moves.py`): he rears up with his wings spread as the marks glint, and slams his head down on the line as they fall, his script held meanwhile. Utan, the Ice Queen, Joe and the Genie got theirs the same day, and then the King's Curse (his coffin rises with its doors flung open and slams down shut, `c15a_curse`; out of it, he flings his arms down, `c15b_curse`) and the Genie's final form (his own charge held, then his own firing pose, `c23a_beam`: his rig is IK chains skinned to one mesh, so it only reorders his native poses).
| 8 | **Named elites** | A few fixed foes on the kept map, in the same place every visit, tinted and scaled, with a title card and a unique drop: the Souls "knight in the corridor". Some patrol between zones. | `characters.spawn` at chosen cells of the kept seed, `entities.set_stats` and `entities.scale_set`, gone for good once beaten (kept like opened chests). A patrol is a brain with waypoints. | Lua |
|   | *Built 2026-11-03 (not yet played):* one elite on each floor or zone of a kept map. It is the first ordinary monster seen there, crowned on its second sighting so floor scaling goes first. It gets a name from the floor's key (the same name every visit), a gold tint, x3 life (a setting), x1.5 damage and x5 reward, a bar of its own, and a "walks this floor" line. When it falls, it drops the best of four gear rolls (one more per NG+ cycle) and stays down for good, kept with the floor's seed (`d:f:zone:elite`). Not yet: chosen cells and patrols, since `characters.spawn` at kept cells needs the spawn table. | | |
| 9 | **Ambushes and traps by theme** | Rooms that shut behind you until the pack is dead, enemies dropping from above, poison pools in the Moon Sea, a dark Gallery of Time where only a lantern charm shows the way. | Room seals exist (the Warden room's): a `set_zones` room flag for ambush rooms. Darkness as a per-zone `draw_dist_scale`; the lantern a charm whose effect is read where the draw distance is set. | Lua, engine small |
|   | *Built 2026-11-03 (not yet played), the ambush:* about one zone in three of a kept map (picked by its key) springs a moment after you walk in. Three of the floor's own monsters (`characters.spawn` of a variant registered on the native template already loaded) drop in around you in a cloud of dust. A sprung ambush is kept with the floor, and NG+ forgets it. Not yet: rooms that shut (a `set_zones` room flag), poison pools and the dark Gallery (no draw-distance API yet). | | |
|   | *Built 2026-11-03 (not yet played), rooms that shut, darkness and miasma:* `dungeons.room_seal` (new: every room's doorways and the gate for each are recorded as a floor is built) shuts the room you stand in when an ambush springs, until the pack is dead (90 s at most). In the Gallery of Time a zone whose shrine isn't lit is dark (`lighting_set` fog at 40-360, a dim ambient); lighting its shrine lifts it. In the Moon Sea one cell in eleven of a kept map holds a foul mist (picked by the floor's key and the cell): it puffs nearby and poisons you while you stand in it. *Ambush rooms*, *Darkness* and *Miasma* are settings. Not yet: enemies dropping from above, a lantern charm. *Both built 2026-11-04: ambushers fall from above (`physics.velocity_set` each tick, checked headless), and the Gallery's first lit shrine gives the Shrine Lantern (a pouch that widens the dark to a ring of warm light round you).*
| 10 | **Invaders** | Now and then a dark copy of a party member, Goro or Xiao in black, hunts you through a zone with a hero's moves. | A hero model spawned as an enemy, driven by the mod-move runner behind a brain. The biggest engine piece here (`characters.spawn` takes only monster templates today). Worth it once 1 and 3 exist. | engine large |
|   | *Built 2026-11-03 (not yet played):* `party.companion_set{hostile = {hp, damage, defense, tint}}` turns the companion round. In `companion_moonmod.cpp` it closes in on the player and swings (every third a slower heavy one at x1.5). Each blow is a native hit in the game's collision list aimed at the player (`NowColData->Set`, mask 1), so guard rules, parries, dodge invincibility and poise all take it. The player's weapon hits (`FindMonsterHit` on its body, from no monster) hurt it, sending `game.companion.struck`. At 0 it falls (down motion) and goes. It draws in its tint and flashes white when hit. In Vigil, about one zone in five of a kept map (never an ambush zone) sends a dark copy of another joined hero a moment after you walk in, with a boss bar. Its life is 1.4x yours and a blow a sixth of it, both more on each NG+ cycle. Felled, it pays 300 Gilda a cycle and the best of several gear rolls, and its zone stays clear (`:invader`). *Invaders* is a setting. Not yet: lock-on to it, dodges and guards of its own, a hero's full move set (it has the first swing). | | |

### The world

| # | Goal | What the player gets | How | Cost |
| --- | --- | --- | --- | --- |
| 11 | **Shortcuts that open from one side, and drops** | The Souls loop: push deep, open a door from the far side, and you're back by the shrine you left. Ledges you can drop down but not climb. | §8 idea 5 on the one-map dungeons: `set_shortcuts` with the key on the far side, chosen so the loop lands near a shrine. A one-way drop is a height step the generator places between two zones. | Lua, engine medium |
|   | *Built 2026-11-03 (not yet played), the shortcuts:* each floor of a kept map asks for two shortcut doors. Each is a dead end's second doorway, locked from the far side, with its key in a chest there. A door once opened is built open on later visits: `set_shortcuts` gained `open`, a list of key items, and Vigil keeps `d:f:doors` from `game.dungeon.door_opened`. On a region, zone gates take most of the keys, so its floors get fewer shortcut doors. Not yet: placing a loop so it lands by a shrine, and one-way drops (a height step between zones). | | |
|   | *Built 2026-11-03 (not yet played), the drops, in Lua:* beside about one locked zone gate in three of a kept map (picked by the floor's key and the zone) is a ledge. Reaching the gate without its key offers *Drop down* (`ui.choice_open`): a `dungeons.warp` with the escape light to the zone beyond, by its shrine, for a tenth of your life (never the last of it). The gate stays locked behind you, so it is one way until you find the key or travel by a shrine. *Ledges* is a setting.
|   | *Built 2026-11-04 (checked headless, not yet played), real height steps:* `set_zones` takes `descent` (0-120). Each zone of a zoned floor lies that far below the zone before, and the nearest straight corridor cell outside each gate (within four cells, round up to three corners) becomes a ramp down to it. The engine raises every cell's part to its zone's height and shears a ramp's part along its slope, for drawing and for collision (the player's, the camera's, the monsters'). Chests, atla, trap circles, the spring water, heal zones, events, the floor's people and the monsters the game sets down all follow the floor. Divine Beast Cave's fall-into-the-river check is measured from the floor, so a lower zone isn't a fall. Vigil asks for 40 (setting *Each zone a step lower*), and an ambush waits until you're off a ramp, so its ring stays level. Checked headless on a Divine Beast Cave floor: zones at 0, -40 and -80; Toan stands on a ramp, walks down it and back up, the floor's height following his x along the slope, with no damage. Two fixes this took: a part frame is shared by many cells, so a sheared one is put back after each use, and `CFrame::GetInverseMatrix` now inverts a sheared matrix properly (the game's own only inverts rotations). Not yet: the ledges still drop by a warp (a real drop needs a zone that is lower than the gate's ledge with no ramp, a later step). | | |
| 12 | **Illusory walls** | Hit a wall that looks like every other wall and it fades, opening a hidden room with something worth the paranoia. | A wall part the generator places on a dead end, with a hit box; a blow opens it and it stays open (kept like gates). | engine medium |
|   | *Built 2026-11-03 (not yet played; how the wall part looks over a doorway is unchecked):* `set_shortcuts{illusory = 1}` plans one more shortcut a floor. Its doorway in the dead end is drawn as the room's plain wall on that side (the door part less 4, its direction kept), with no key or chest. The attack button pressed within reach of it, facing it, puts the doorway back (`ChronicleWallStruck` at the swing in `movechara.cpp`) and sends `game.dungeon.wall_opened`. Vigil keeps it open (`d:f:walls`, sent back as `open_walls`), and what lies behind is a piece of gear, the best of several rolls. | | |
| 13 | **Georama as a Souls hub** | Townsfolk met in the dungeon (lost, cursed, trapped behind an elite) come home to the town you rebuilt: a smith who reinforces and repairs, a trader with rarer gear, someone whose quests send you back down. Rebuilding the town grows the hub. | Rescues are dungeon NPCs (`dungeon_npc_set`) kept with the save; at home they're residents with new lines (`text.set`) and shop lists. Ties Dark Cloud's best idea to Souls' hub. | Lua, writing |
|   | *Built 2026-11-03 (not yet played):* three townsfolk, each held by a named elite. The first elite to fall in Divine Beast Cave frees Gorm the smith, in Wise Owl Forest Ysolde the trader, in the Shipwreck Old Harl the seeker (`world.dungeon_npc_set` beside you; walking up sends them home, kept with the save as `hub`). In town, D-pad Up or H calls the folk you saved (`ui.choice_open{town = true}`): the smith gives +3 attack and a full mend for 500 Gilda, the trader the best of several gear rolls for 400, the seeker a hunt of three named elites for 800. Not yet: their own models and town lines (they wear a villager's), stock that grows with the town. *Your town as a hub* is a setting. | | |
|   | *Built 2026-11-03 (not yet played), their own looks and lines:* each wears a villager of the town nearest the dungeon that held them (Gorm Norune's `p05a`, Ysolde Matataki's `p24a`, Harl Queens' `p36a`; `p02a` if one won't load), and one of them speaks a line of their own over the town panel, a different one each visit. Ysolde's stock grows with the deepest dungeon you have rested in.
| 14 | **Where you died** | The map screen marks your last deaths, and a bloodstain at the fall spot plays the last seconds before you fell as a ghost. | Marks: a list kept with the save, drawn by `ui.map_open`. The ghost: a ring buffer of positions and motion ids replayed on a translucent copy of the hero. | Lua; the ghost engine medium |
|   | *Built 2026-11-03 (not yet played), the marks:* a knockout shows a "YOU DIED" card (`ui.boss_card`, a setting), and the save keeps the last eight deaths (`deaths`, newest first). The map marks each one, one mark a cell, beside the pile of what you lost. Not yet: the ghost replaying your last seconds (a ring buffer of positions and motions replayed on a translucent hero needs an engine copy of the hero). | | |
|   | *Built 2026-11-03 (not yet played), the ghost, in Lua:* the last five seconds before you fell (a point every 10 frames) are kept with the save. Come back within reach of the spot and a wisp (`heal` sparkles) walks the path, ending in a puff where you went down, once each time you return. *Your ghost* is a setting. Not yet: a translucent copy of the hero playing its motions (the companion slot could carry it, but the invader uses it).
|   | *Built 2026-11-03 (not yet played), the hero's ghost:* `ghost_moonmod.cpp` keeps the player's place, heading and motion every other frame on a dungeon floor (five seconds), read by `world.ghost_get`. `world.ghost_play{character, frames}` loads the hero's pack into arenas of its own (texture block 0x63) and walks the frames again, pale blue and see-through (ambient alpha 56), fading over a second at the end. Motions a mod appended play as standing. Vigil keeps the record at death with the save and plays it when you come back to the spot, falling back to the wisp.

### Long runs

| # | Goal | What the player gets | How | Cost |
| --- | --- | --- | --- | --- |
| 15 | **NG+** | After Dark Genie, a new cycle: new seeds for every map, monsters a band higher, elites in new places, gear and the tree kept, a few rewards found only on a second cycle. | A cycle number kept with the save; floor scaling's base rises with it; seeds rerolled. §8 idea 13. | Lua |
|   | *Built 2026-11-03 (not yet played):* the dark Dark Genie's death (model 106) readies a cycle. At a shrine, Leave then offers Next cycle. Beginning it forgets every kept map, chest list, shrine, elite and rest point, and keeps the tree, levels and gear. Each cycle past the first multiplies floor scaling's life by 1 + 0.5c, damage by 1 + 0.25c (the cap rises with it) and reward by 1 + 0.5c. Not yet: rewards found only on a second cycle. | | |
| 16 | **Vigil Trial** | A title mode to fight any boss or elite with a chosen build, for practice and for tuning balance (§6, question 1). | The Gauntlet's title mode and Warden room with Vigil's rules on. | Lua |
|   | *Built 2026-11-03 (not yet played):* Vigil's own title mode, the second mod mode beside the Gauntlet. Pick one of the five story bosses and a hero, then Begin. The session (`session.start`) starts on an empty floor Vigil registers in Divine Beast Cave (`source_floor` 12, no monsters). The party gets each hero's strongest weapon under a cap for that boss's place in the story, and the max HP for it. Three seconds in, the boss comes out in front of you with its cast (`characters.spawn` with `arena_slot`, `hit_share` so any hero can hurt it). The story-boss card, bar and second phase follow. A win is timed, the best time per boss is kept (`moonmod.storage`), and the session ends back at the title. Not yet: the Dark Genie (his two forms need the Gauntlet's cast choreography), elites, and a build picker beyond the hero. | | |
|   | *Built 2026-11-03 (not yet played):* the Dark Genie's elemental form (106, with its eight helpers) is the sixth Trial, at a sixth tier (attack cap 170, 760 HP). The title page cycles the boss on one entry (a page holds seven). Not yet: elites in the Trial. *Built 2026-11-04: six named elites, one for each place in the story, each of a family with an enemy brain: gold, half again the bite, a bar of their own and a best time each.*
| 17 | **Messages, online** | Short notes left on the floor for others on the same seed ("illusory wall ahead"), rated by readers. | Through DC_Web and a small server; offline, a set of written notes as lore. Last, and only if the web build takes off. | large, outside the engine |
|   | *Built 2026-11-03 (not yet played), the offline half:* the first time you reach a shrine, a note is scratched beside it: a warning, a tip or a line of lore, written for each dungeon and picked by the shrine's key, so it is the same note every time. It is kept as read with the floor, and NG+ forgets it. Not yet: notes players leave for each other, which needs DC_Web and a server. | | |
|   | *Built 2026-11-04 (checked in tests, not yet played), the online half, with no server:* the engine's `messages.*` keep each message as a small file in a messages folder. A player who points it at a folder a sync service shares (OneDrive, Dropbox, a LAN share) trades messages with everyone else who does, so no hosting is needed. The folder is the player's choice, never a mod's, and each player writes only their own files; others' are read as untrusted data with caps. At a shrine, a fifth card, Messages: leave one built from six phrases and fifteen words ("Beware a mimic"), read others' best rated first and rate them, or take one back. Reaching a shrine, the best rated one comes up. Messages are kept by dungeon, floor and shrine, not cell, so they match across saves whose maps differ. Vigil shows only text that parses back into its phrases. Engine tests (two players sharing a folder, hostile files), Vigil tests. A DC_Web server could later carry the same files. | | |

### Order
E1-E3 → 1 (brains) with 2 (poise) → 3 (criticals) → 5 (flask) → 4 (weapon arts) → 7 (bosses, Dran first) → the
world (11, 13) → the rest as appetite allows. Each gets a playtest before the next, as before.

## 13. Where Vigil stands, and what a modern feel still needs (2026-11-03)

After §12, Vigil has most of the systems a Souls-like is judged by:
- **The player's side:** a stamina gauge that gates everything; rolls and backsteps with invincibility; guard, parry and riposte; poise on both sides; backstabs and ripostes; weapon arts; a slow flask that spills on a hit; a lock-on that switches by flick, drops behind walls, and a soft lock.
- **The enemies' side:** enemy brains for 19 melee families, story bosses with a second phase, named elites, ambushes, and invaders (a dark copy of a party member that hunts you with native hits).
- **The world:** a kept, connected world with shrines, shortcuts that stay open, illusory walls, deaths marked on the map, notes, NG+, and a town that grows into a hub (a smith, a trader and a seeker you rescue from named elites).
- **Practice:** the Vigil Trial, a title mode to fight any story boss with a chosen hero, armed for that point in the story, with best times kept.

**None of §12 has been played by hand yet.** Every piece passes its headless tests (Vigil 494 checks, the engine suite), but feel can only be judged with a pad. **The next step should be a playtest of §12, before more features.**

Measured against the modern bar, from the action games people now hold up (Elden Ring, Sekiro, Lies of P, Nioh), these gaps matter most, most important first:

1. **Hit feel.** *Built: `combat.feel_set` (hit-stop, camera shake, rumble); Vigil sets light 3, heavy 6, critical 10 and hurt 5 frames, shake on heavy blows and on being hurt, and rumble (setting *Hit feel*, test section 40).*
   - Before it, a blow landed with a spark and a number, and that was most of why DC1 combat read as light.
   - The freeze is in `GameLoop` (the floor is drawn, not stepped), started from the monsters' hit check on the player's blows, the player's hurt in the dungeon loop, and the critical's start.
2. **Input buffering and cancel windows.** *Built: `player.tuning_set` `input_buffer`; Vigil keeps a refused roll or R2 for 12 steps (setting *Input buffer*, test section 41). Evades already cancel a swing's recovery (`cancel_after`); and `chain_cancel` (built 2026-11-04, setting *Chain attacks*) lets R2 in a swing's recovery, 6 steps past its blow, cut into the heavy, and attack in a heavy's recovery cut back into the combo.*
   - Player moves start only on the frame the button is read; nothing is buffered.
   - Modern games keep the last press for about 10-15 frames, so a roll pressed late in a swing's recovery comes out at the first cancel frame instead of being lost.
   - Add a buffer in the move runner (`ChroniclePlayerMoveOn*`) and explicit `cancel` windows on moves (roll-cancel, chain-cancel).
3. **Bosses that change how they fight, not just their numbers.** *Built (2026-11-04): each story boss's second-phase move has a motion of its own (`tools/anim/vigil_boss_moves.py`), played as its marks glint with the boss's script held meanwhile: Dran rears up and slams his head down along the line, Utan springs with his arms up and stamps, the Ice Queen leans back and thrusts her arms down, Joe goes up with his axe and brings it down on you, the Genie winds round and sweeps across, the King's Curse's coffin rises with its doors open and slams shut, and the Genie's final form holds his charge and fires. The fog gate already stands: with Vigil World each boss floor (Dran's 15 and the rest) is a small zone behind a smoke gate you walk up to and go through, and the zone before it has a shrine; reaching a shrine makes it the one you wake at, so a death behind the smoke wakes you a short walk from it. Not yet played: none of the eight motions has been seen in a running game.*
   - Phase two is a tint, a speed-up and more damage. A Souls boss's second phase brings new attacks and a new rhythm.
   - It needs per-boss motions and a takeover of each cast's script for phase two (the §12 goal 7 remainder), Dran first.
   - Also missing: a fog gate in front of each boss, with a shrine near it, so a retry is a short walk.
4. **Telegraphs.** *Built: a string's opening blow glints with a soft ping a beat before it lands; a family's own new attack flashes red with a crack (setting *Telegraphs*, test section 42).*
   - Brains wind up, feint and punish, but a wind-up has no cue of its own: no glint, no sound, no colour.
   - Each brain's attack could fire a small cue at wind-up (`effects.burst` "guard" at the weapon plus a sound). Unblockable or grab attacks could get a red one, as Sekiro does.
5. **The other five heroes.** *Correction: every hero already rolls or tumbles and backsteps on L2 (Vigil's EVADES, from `party_moves.py` and `xiao_moves.py`). Built now: the engine's shove dodge, Vigil's fallback when the motions are missing, is never given to a hero with a roll (`ChroniclePlayerHasDodgeMove`) and costs the gauge a roll does (`dodge_gauge`), so an empty gauge refuses L2 for everyone. Built too: the Gauntlet's sets for them (19 moves, setting *Party attacks*, test section 1). Goro and Ungaga get a heavy, a finisher after two blows and after three, a guard counter and a roll attack; Xiao, Ruby and Osmond a heavy shot and two volleys. Their criticals too (a backstab and a riposte each, `ATTACKS.party_criticals`): until each has a stab of its own, the hero's strongest close blow at point blank (Goro's and Ungaga's guard counter, the casters' heavy shot) against the enemy's crumple. Built 2026-11-04: each has a critical of its own on Toan's timing (`party_moves.py` `critical` and `critical_cast`, `xiao_moves.py` `critical`): Goro slams down from his crouch, Ungaga drives the spear in, and the three casters press in and shoot twice at point blank. Their weapon arts too (2026-11-04): Goro's Earthquake, Ungaga's Spear Storm, Xiao's Stone Rain, Ruby's Inferno and Osmond's Barrage, each on all of that hero's weapons, from their own moves played their own way, and named on the weapon cards.*
   - Evades, the heavy, finishers, criticals and arts are Toan's own.
   - Xiao, Goro, Ruby, Ungaga and Osmond fight as DC1 had them, so switching heroes switches genres.
   - Each needs at least an evade, a heavy and a critical (motions through `tools/anim`).
6. **The camera.** *Built in part: `lock_camera` keeps the target framed (setting *Lock-on camera*); the game's own camera already pulls in at walls (`DungeonZoomApply`). Pulling out for a large target is built too (2026-11-04): locked on to a big monster or boss, the camera may sit up to 60 units further back.* DC1's camera trails behind. A modern lock-on camera keeps both the player and the target framed, and pulls in when a wall is near. This is an engine piece in the dungeon camera.
7. **Ranged and casting enemies.** *Built for 40 shooting families (nine of the early dungeons', 25 later ones and six fliers, which keep their height); the three casters with a second spell alternate the two (`SET_SHOT2`): they keep their distance (back off inside 70, close in past 190), step aside, and fire their own projectile (`SET_SHOT` through `monsters.call`, which now takes a frame name) a beat after a glint; two never fire together (setting *Shooters*, test section 43). Fixed 2026-11-04: 18 rows were keyed by the wrong model (the later families' file numbers had been taken for model ids), which handed Dran, Master Utan and the King's Curse to the shooter brain; each is now keyed by the model that uses its file. Still to do: the shooting families whose walk motion couldn't be read from their scripts.*
8. **Readable HUD.** The locked target needs an HP bar and a poise or stagger meter (Sekiro's posture bar is the modern reference). Elites have bars, but ordinary foes show nothing.
   *Built 2026-11-03 (not yet seen on screen):* `render.target_bar_set` puts a bar half again as wide as the game's gauge under the locked target's name, with a damage trail, and `render.target_meter_set` a meter under it; Vigil fills it from enemy poise (a third a light blow, full and flashing at the break, gone two seconds after the last hit). *Target bar* setting. Engine test and Vigil tests pass; a headless lock-on kept the bat off screen, so the look waits on the hand playtest.
9. **Invaders that fight like players.** *Built in part: an invader with a blade weighs each swing you start close by and raises the hero's own guard about two times in five, blocking it with a clang (`companion_moonmod.cpp`). It also dashes aside out of a swing's line (about three in ten, five for a ranged one), untouchable while it goes, and comes straight back in. Its dash picks an open side and stops at walls; between swings it circles you on the hero's own lock-on strafe; below a third of its life it backs off and drinks one of two flasks (two fifths back; hit it mid-drink to spill it); and your lock-on takes it when it's the nearest. Built 2026-11-04.* The invader closes in and swings, with a heavy every third. A real one would roll away from your swing, guard, punish your flask and back off to heal. Lock-on doesn't reach it yet, which a duel needs most. Both are engine work in `companion_moonmod.cpp` and the lock-on loop.
10. **Left over from §12.** Built since the first pass: a telegraphed new move for each boss (on `combat.strike_player`), rooms that shut on an ambush (`dungeons.room_seal`), darkness and miasma, the hero's ghost (`world.ghost_play`), one-way drops by ledges, the Dark Genie in the Trial, elite patrols, and the townsfolk's own looks and lines. Every §12 goal now has a built version. What's left is depth, not missing goals:
    - Motions of the bosses' own for their new moves. *Built 2026-11-04 for five of them (see the last re-evaluation).*
    - ~~Drops as real height steps in the generator~~: built 2026-11-04 (see below). ~~Enemies dropping from above, a lantern charm, elites in the Trial~~: built 2026-11-04. Ambushers start 70 above the floor and fall, faster each tick and never past the floor (`physics.velocity_set` each tick: left alone, a monster off the floor only eases down over seconds, and a speed of its own carries it through; checked headless, 70 units in 23 ticks, landing at the floor), setting *Ambushers drop from above*. The Gallery's first lit shrine gives the Shrine Lantern, a pouch that, worn by anyone in the party, turns the dark into a wide ring of warm light (setting *The Shrine Lantern*). Six named elites (Garrow, a Skeleton Soldier, to Sable, a Club) join the Trial's list, one for each place in the story (the later dungeons' Sunday and Club checked headless: they spawn on a Divine Beast Cave floor and take their set life).
    - ~~Online messages (goal 17) beyond the offline notes~~: built 2026-11-04 through a shared messages folder, no server (see item 17).
    - **A hand playtest of all of §12.** Every piece is checked headless (Vigil 494 checks, the engine suite), none with a pad.
### Order

1. Playtest §12.
2. Hit feel (1) and buffering (2), since both are engine small.
3. Telegraphs (4).
4. Dran's real second phase and a fog gate (3).
5. The other heroes' evade, heavy and critical (5).
6. The camera (6).
7. Invaders that dodge and can be locked onto (9).
8. Then the §12 leftovers (10). Use the Trial for every balance pass above: it starts any boss fight in a few seconds.

### Re-evaluation after the feel pass (2026-11-03, later)

Built since the list above: hit feel (1), input buffering (2), telegraphs (4), a lock-on camera that keeps the target framed (6, in part), shooters that keep their distance (7, nine families), and the locked target's bar and poise meter (8, by S1). Of the eight gaps, the ones about how a blow *feels* (weight, responsiveness, readability, framing) now all have a built version. What is left is content, not plumbing:

- **The other five heroes (5).** They roll, and now have heavies and finishers too (the Gauntlet's sets). Their criticals reuse a close blow; stabs of their own are motion work in `tools/anim`, as `vigil_criticals.py` made Toan's.
- **Bosses with a real second phase (3).** The new moves fall while the boss's own body keeps fighting as before. They need motions of the boss's own and a fog gate with a shrine before it.
- **Invaders that duel (9).** They guard and dash aside now; they still need lock-on, engine work in `companion_moonmod.cpp` and the lock-on loop.
- **Depth on what's built:** a chain-cancel from one attack into the next, and the camera pulling out to fit a large target.

The order stands, with one change: **a hand playtest is now more urgent than any of these.** Hit-stop, buffering windows and telegraph lead times are numbers that only a pad can tune, and every one of them is a setting so it can be tuned without a build. Play Divine Beast Cave floors 1-4 and the Dran Trial with the README's hand tests, and note which settings felt wrong and by how much. Then build the other heroes.

### Re-evaluation after the stretch goals (2026-11-04)

Every gap the 2026-11-03 re-evaluation listed now has a built version, checked headless (the engine suite; Vigil 507 checks):

- **The other five heroes (5).** Each has its own critical motion, on Toan's timing, played paired with the enemy's crumple.
- **Bosses with a real second phase (3).** Five bosses (Dran, Utan, the Ice Queen, Joe, the Genie) wind up and strike in motions of their own, their scripts held meanwhile. The smoke gate before each boss floor, with a shrine in the zone before it, is the fog gate.
- **Invaders that duel (9).** An invader circles you between swings on the hero's lock-on strafe. It guards, and dashes aside to whichever side has no wall. Low on life it backs off and drinks: two flasks, and a hit spills one. Your lock-on takes it.
- **Depth.** `chain_cancel` takes a landed blow into the heavy and the heavy back into the combo, and the camera pulls out for a large target.
- **A bug found on the way.** 18 shooter rows were keyed by file number instead of model id. That gave Dran, Utan and the King's Curse the shooter brain in place of their boss scripts, and pointed other rows at the wrong families. Fixed.

What a modern feel still lacks, in order of how much it would change play:

1. **Tuning by hand.** Hit-stop, buffer and chain windows, telegraph lead times, invader timings and the new boss motions are all numbers only a pad can judge. S1 viewed the boss motions in the editor (two were fixed after); nothing else has been played. This is now the only blocker to calling the feel done.
2. ~~Weapon arts for the other heroes~~ (built the same day), and ~~the King's Curse's and the Genie's final form's own motions~~ (built the same day: `c15a_curse`, `c15b_curse`, `c23a_beam`).
3. **Height in the dungeon.** *Built 2026-11-04:* each zone lies a step below the one before, down a ramp the engine shears from a straight corridor part (`set_zones` `descent`; checked headless). The ledges are still one-way warps; a real fall would need a zone below a ledge with no ramp, a later step.
4. **Online messages.** *Built 2026-11-04 with no server:* `messages.*` through a messages folder players share by any sync service; Vigil's Messages card at each shrine. A DC_Web server is optional, not needed.

Built after this list was written (still 2026-11-04; Vigil 521 checks): weapon arts for Goro, Ungaga, Xiao, Ruby and Osmond; the King's Curse's coffin, the King's Curse himself and the Genie's final form each with a motion of their own (all eight boss motions now); ambushers that fall from above (checked headless); the Shrine Lantern; six named elites in the Trial (the later dungeons' ones checked headless).

**Where the project stands (2026-11-04).** Every §12 and §13 goal has a built version, and the combat loop has the pieces a modern action game is judged by:
- **Readable enemies.** Brains with feints, guards and side steps; wind-ups held a beat; criticals, poise and a posture bar on the locked target.
- **Bosses that change how they fight.** Each of the eight story-boss bodies has a telegraphed move of its own in its second phase.
- **A player kit with depth.** Buffering, chain cancels, ripostes, guard and exhaustion, weapon arts for all six heroes, flasks.
- **A world that rewards learning.** Kept maps, shrines, shortcuts, ambushes, elites, darkness, the lantern, ghosts and NG+.

Height in the floor itself is now built: each zone lies a step below the one before, down a ramp outside its gate (item 3; checked headless, not yet played). Players' messages to each other are built too, with no server: they travel through a messages folder the players share by any sync service (item 4; checked in tests, not yet played).

The order now: the hand playtest (the README's hand tests, then the Trial against each boss and elite). Its notes feed one tuning pass on the numbers in item 1. Nothing built is waiting on a decision; a hosted server for messages (DC_Web) is optional now.
