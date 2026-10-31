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
it fires only for fatal hits. That is the one big addition. There are two smaller ones.

| # | Operation | Why | Size |
| --- | --- | --- | --- |
| E1 | **`native.player.hit` script hook** (or a `player.hit_filter`): runs before an enemy hit lands on the player. The context has the attacker's `entity`, raw `damage`, `heavy`, `element`, `angle` (attacker relative to the player's facing) and `guarding`. It returns `{damage?, recoil_frames?, cancel?}`. | A guard that only covers the front, stamina charged per blocked hit, guard break and the parry window. Without it, a blocked hit for 0 can't be seen at all. | The critical path. Damage resolves in the player code under `port/src/game/dun/` (S0 finds the exact spot). |
| E2 | **A stamina gate on native combo swings**: a `combo` move trigger, or `tuning_set{attack_gauge}` so each native swing spends action gauge and won't start without it. | `gauge` already gates mod moves, but basic combo swings bypass it. Stamina can't truly be required until they don't. | Small. The move runner already intercepts combo swings for `cancel` and `combo_finisher`. |
| E3 | **`player.gauge_get/set`** and a small **`player.state()`** (action, guarding, locked-on, frame in the action) | To show the action gauge as the stamina bar, refund it after a parry, and know when the player is guarding. | Small reads. |

Each is added the way *Extending the engine* walks through `dungeons.set_rest_room`: catalog it in `api.cpp`, dispatch
and handle it in `chronicle_adapter.cpp`, release it on unload, add engine tests, document it in `docs/API.md`, teach
the fake game, then regenerate the patch. Chronicle Two reports them unsupported.

---

## 3. Design pillars and starting numbers

These are first-pass numbers. Each one is a mod setting (*the rules the bundled mods follow*, rule 5).

### Stamina is the action gauge
Use Dark Cloud's own action gauge as the stamina pool. Moves already spend it with `gauge`, `gauge_refill` already
tunes its regen, and E2 makes native swings spend it too. Until E2 and E3 land, the S1 prototype keeps a Lua pool and
draws it with `render.bar_register`.

| Action | Cost (of 100) | How it's charged |
| --- | --- | --- |
| Light swing | 18 | E2 (prototype: a Lua charge on the attack button's press edge) |
| Heavy (R2) / charge release | 35 | the move's `gauge` |
| Roll / backstep | 25 | the move's `gauge`, so an empty bar means no evade |
| Counter (guard + attack) | 20 | the move's `gauge` |
| A blocked hit | 10 + 1.5 × damage stopped | E1 |
| Regen | 30/s after a 0.6 s pause, half while guarding | `gauge_refill`, re-set while guarding |
| **Exhausted** at 0 | 1.5 s | no evade (the gauge gate), the guard breaks, swings do 30% damage (a formula) |

### Blocking (the native lock-on + R1 guard)
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
- **Output:** a findings note appended to this file.

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
- **The action gauge may already mean something** (Xiao's and the Gauntlet's moves spend 100 of it). S0 decides
  whether to adopt it or keep a separate Lua pool.

## 6. Open questions

1. Should weapon durability stay? It's a second, slower resource on top of stamina.
2. Should the death drop include weapon ABS, or only Gilda?
3. How many floors between Rest floors: 3, or one per dungeon section?
4. Should Vigil also offer a sandbox title mode, a "Vigil Trial" like the Gauntlet, for testing balance away from the
   story save?
