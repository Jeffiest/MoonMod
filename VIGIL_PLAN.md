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

### S1: Lua prototype on PR 15's API
- `mods/moonmod.vigil/`, scaffolded with `tools/moonfactory.py new` and following *Your first mod* (`try` and `call` guards).
- Evades: Roll and Backstep with a `gauge` cost, longer cooldowns and a later `cancel_after`. Copy the motion JSON
  rather than depending on the Gauntlet.
- A Lua stamina pool shown with `render.bar_register`. Swings are charged from the attack button's press edge, moves
  from `game.player.move`, and blocked hits from HP drops while R1 is held (`input.bind` on `Gamepad:rightshoulder`).
- Heavier enemy damage and recoil, and the exhausted state.
- Sitting out other mods' game modes: `moves_clear`, `tuning_clear` and formulas back to ×1 during a sandbox session
  (Cookbook, *Share the game with other mods*). The Gauntlet owns the same L2 triggers.
- Tests: the fake adapter (*Testing mods* §1) in `tools/tests/vigil/`, covering the stamina maths, the gauge gate,
  exhausted timing, and sitting out a session.
- **Gate:** Divine Beast Cave floors 1-3 as Toan. Trading hits is clearly worse than blocking or rolling, and the bar
  makes you pause.

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
| Map size | **The wall.** A grid of 48 × 48 cells (`DNG_GRID`), and 64 rooms (`DNG_ROOM_MAX`). Retail floors have about 6 rooms, so 20 floors' worth is about 120 rooms. |
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
- **Entering a dungeon** from town puts you at the **last shrine you rested at**, or the entrance the first time.
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
- It owns `set_layout`, `set_zones` and the exit rules while active. Dungeon+ must stand down its layout and tier
  features in a Vigil World save; that needs a test.
- Demon Shaft (100 floors, no atla) stays floor-by-floor, as the endless challenge (decided). W2's stress test is a
  regular dungeon instead.

### Order
W1 comes after the combat core (S1-S3), since the world only matters if the fighting is right. Suggested gates:
- **W1.0**: `set_seed` and keeping the seed per save. Re-entering Divine Beast Cave gives the same floor.
- **W1.1**: `set_zones` with 2 zones and one gate on one map. Walk from zone 1 to zone 2 without a load.
- **W1.2**: shrines (light, rest, respawn, travel, town only from shrines).
- **W1.3**: a whole Divine Beast Cave as 3 regions (floors 1-4, 5-7 and Dran, then 9-15), with atla and the story
  bookkeeping checked.
- **W1.4**: floor scaling.
- **W2**: raise the limits, and make Divine Beast Cave one map.
