# Vigil: a Souls-lite combat overhaul for Chronicle (Dark Cloud)

Working title **Vigil**, mod id `moonmod.vigil`. Rename freely.

Combat should be slow, deliberate and methodical. Every action spends stamina, and the player has to block and dodge
to survive. The world is persistent and the dungeons are random.

---

## 1. Dark Cloud already has the world we want

The world structure is mostly done, because Dark Cloud already works this way:

| What we want | What Dark Cloud already does |
| --- | --- |
| Persistent world | Six towns that keep their state across the whole save |
| A world that is placed, not generated | Georama: the player rebuilds each town piece by piece, and it stays that way. That is the nearest thing to a hand-placed world, and the player does the placing. |
| Randomly generated dungeons to crawl | Every dungeon floor is generated on entry, with a fixed theme, monster roster and boss for each dungeon |
| More dungeon variety | `moonmod.dungeon-plus` already adds bigger floors, Tiers 1-5, mutators, champions and bounties |

So this project is about **combat, the death loop and pacing**, not world generation. Hand-authored spaces are possible
later with `game.locations` and `world.transition` (copied interiors), but they are a stretch goal.

---

## 2. Design pillars and starting numbers

These are first-pass numbers. Each one should be a mod setting so they can be tuned in game.

### Stamina (one pool, shown as a HUD bar)

| Action | Cost | Notes |
| --- | --- | --- |
| Light attack (each swing) | 18 | A combo of 4 swings uses most of the bar |
| Charged attack | 35 | Paid on release |
| Dodge | 25 | Can't dodge below the cost |
| Blocking a hit | 10 + 1.5 × damage stopped | Big hits can break your guard |
| Dash (held) | 8 per second | |
| Max pool | 100 | Grows with progression (see §2.6) |
| Regen | 30 per second, after a 0.6 s delay | Half as fast while guarding |
| **Exhausted** at 0 | 1.5 s | No dodge, the guard breaks, attacks do 30% damage |

### Blocking
- Hold to guard: walk speed ×0.5, regen halved.
- It only covers a frontal arc of about 120°. A hit from the side or behind gets through at full damage.
- It stops 70-85% of the damage depending on the weapon. Goro's hammers block best, and Ruby and Osmond block worst.
- **Guard break**: a blocked hit that would take stamina below 0 knocks you down with a long recoil and takes the rest as damage.
- **Parry** (stretch goal): start guarding within about 6 frames of the hit. You take 0 damage, the enemy is stopped for 90 frames, and your next hit within 2 s does ×3 (riposte).

### Dodging
- A short burst in the stick direction (backstep with no direction), with 12-14 invincible frames and about 0.4 s of recovery.
- Built on the game's own dash, since the player tuning already scales the native dash speed.

### Enemies that make blocking and dodging necessary
- Enemy damage ×2.5 by default, so trading hits loses.
- Heavier recoil on the player (`recoil_scale` above 1), so getting hit costs time as well as HP.
- Enemies wind up before attacking (a visible pause), commit to the attack, then leave an opening. See S4.
- Stagger: heavy hits, ripostes and parries put the enemy into the native `stop` status for a short time.

### Healing scarcity
- Limit healing items to a few uses per floor, refilled at the floor entrance or in town.
- Idea: Dark Cloud's **water gauge** is already a resource that drains and refills at fountains. It could become the
  flask stand-in: drinking from it heals and costs water, and fountains act as rest points.

### Death and recovery
- When you die, your carried Gilda (and optionally unspent weapon ABS) stays where you fell: same dungeon, floor and position.
- Get back to that spot on that floor to recover it. Die before then and it's gone.
- A HUD line shows the distance to the drop while you're on that floor. `player.get().position` plus floor tracking is enough for this.

### Progression
- Max stamina and regen go up through a small skill tree (`game.skills`, shown on the Journal's Character page),
  bought with a currency earned from Warden or boss kills and floor clears.

### Per-character profiles
Each of the six characters plays differently.

| Character | Weapon | Stamina identity |
| --- | --- | --- |
| Toan | Sword | Balanced. The baseline. |
| Xiao | Slingshot | Cheap shots, a weak guard, the best dodge |
| Goro | Hammer | Expensive swings, the best guard, a slow dodge |
| Ruby | Magic rings | Shots cost more and her guard is the worst; she survives by spacing |
| Ungaga | Spear | Mid costs, long reach, a strong charged attack |
| Osmond | Gun | High cost per shot, a fast dodge |

---

## 3. What MoonMod can do today, and what needs engine work

| Need | Today (Lua only) | Gap | Engine work (Chronicle patch) |
| --- | --- | --- | --- |
| Stamina bar on the HUD | `game.render.bar_register` (Ascension's Focus bar works this way) | none | none |
| Charge stamina for swings | `game.input.bind` on the attack button gives the press edge | Can't tell a real swing from a mashed button, and can't **stop** a swing at 0 stamina | `player.state()` (current action and frame) and an owner-scoped `player.action_lock` to veto native attack and dash |
| Harder enemies | `combat.register_player_formula` (×2.5), `player.tuning_set{recoil_scale}` | none | none |
| Blocking | A held key, with the player damage formula re-registered at ×0.25 while it's held. Stamina is charged by watching HP fall. | No attacker, no direction, no pre-hit hook. A hit blocked to 0 is invisible. | A **`native.player.hit`** script hook before damage, with the attacker handle, raw damage, angle to the attacker and heavy or light. It returns `{damage, recoil_frames, cancel}`. |
| Dodging | `player.invincible{frames}` and a brief `run_speed` burst | No roll animation and no directed displacement | `player.dodge{direction, distance, frames, iframes}`: displacement through collision, using the native dash motion until there's a roll |
| Exhausted state | Attack formula ×0.3, and the native `stamina` status badge or ailment | Check what the native `stamina` ailment really does | none, unless the veto lands |
| Enemy telegraphs and stagger | `native.monster.run` override plus `monsters.call` (`SET_MOTION`, and so on), and `combat.status_add{stop}` | A per-family script for each enemy | none |
| Riposte | `combat.register_formula` with `target_hp_below_percent` and `chance` filters, or a per-target damage formula | Needs a per-target window | could use the `native.player.hit` result |
| Death drop | `player.get().position`, floor events, `game.save` | No world marker object, so the HUD shows the distance instead | optional: a pickup marker |
| Healing limits | `game.items.use` callbacks for mod items | Native potion uses may not be hookable | possibly an item-use veto |

**Bottom line:** we can build a rough Lua-only prototype now. For it to feel right, we need four engine hooks: the
pre-hit hook, the player state read, the action veto and a dodge action. They go in the Chronicle patch, with GoogleTests,
the same way the title-mode work did.

---

## 4. Phased plan (stage gates, same rules as `GAUNTLET.md`)

Each gate needs its automated checks green and a playtest checklist ticked before the next one starts.

### S0: Spike (about 1 session, no content)
- Play a dungeon and record what the native controls actually do in combat: is there a guard, lock-on, side-step or dash, and what does the action gauge do? Check whether `input.bind` on the attack button still lets the native swing through.
- In the Chronicle source (`port/src/game/dun/movechara.cpp` and its neighbours), find the player action state machine and the place where incoming damage resolves. These are the anchor points for the S2 hooks.
- Find out what the native `stamina` ailment does.
- **Output:** a short findings note added to this file.

### S1: Lua-only feel prototype
- `mods/moonmod.vigil/`: stamina pool, regen and delay, HUD bar, attack and dash costs, block on a held key (formula swap, HP-drop charging), dodge (i-frames, speed burst), exhausted state, enemy damage ×2.5, heavier recoil.
- Every number is a setting.
- Harness: `tools/tests/vigil/` built on the roguelike fake adapter (`tools/tests/roguelike/fake_game.lua`), testing the stamina maths, exhausted timing and guard break.
- **Gate:** Divine Beast Cave floors 1-3 with Toan. Is trading hits clearly worse than blocking or dodging? Does the stamina bar make you pause?

### S2: Engine hooks (Chronicle patch)
1. The `native.player.hit` script hook (pre-damage, can change or cancel the hit, sets recoil).
2. `player.state()`: action id, frame in action, facing, attacking, guarding, dashing, combo step.
3. `player.action_lock{attack, dash, frames}`: owner-scoped, removed when the mod unloads.
4. `player.dodge{direction, distance, frames, iframes}`.
- Each gets API docs in `docs/API.md`, GoogleTests and a capability record. Chronicle Two reports them unsupported.
- **Gate:** the engine tests pass and the full suite adds no failures beyond the baseline.

### S3: Real combat on the hooks
- Port S1 onto the hooks: frontal block arc, real guard break, stamina that truly gates attacks, directed dodge, then parry and riposte.
- **Gate:** playtest the same floors and the Dran fight. Blocking from the front works, a side hit gets through, and you can't swing on an empty bar.

### S4: Enemies that telegraph
- `native.monster.run` overrides for Divine Beast Cave's roster first: a wind-up pause before each attack, slower turning while attacking, a recovery window after it, and stagger on heavy hits or parries.
- **Gate:** every enemy in that dungeon can be beaten cleanly by reading it, with no unavoidable damage.

### S5: The death loop and healing
- Death drop and recovery, a limit on heals per floor, and the water flask and fountain idea if S0 says it's workable.
- **Gate:** a full Divine Beast Cave run with deaths. The loss stings without making you want to quit.

### S6: Breadth and balance
- The remaining dungeons' enemy families, the six character profiles and the progression tree.
- Coexistence: player tuning multiplies across mods. Test alongside RPG and Dungeon+, and decide whether to declare a conflict with Ascension, whose Focus powers bypass stamina.
- Difficulty presets in settings.

### S7: Release
- A README for the mod, a Hub link, and inclusion in the release zip.

---

## 5. Risks

- **The native player animations are fixed.** Without model rigging there's no new roll or guard pose. Dodge and guard will reuse native motions (dash, recoil), and they may look stiff.
- **The S2 hooks are the critical path.** If the damage-resolve code is tangled, the pre-hit hook is the hardest piece.
- **Dark Cloud's native AI** was never designed around being punished. Some enemies (fliers, ranged ones) may need full script takeovers rather than tweaks.
- **Party switching mid-fight** in Dark Cloud could become a way to dodge stamina. The pool should probably be shared, or the switch should cost stamina.

## 6. Open questions

1. Keep Dark Cloud's party swapping in fights, or lock to one character per floor?
2. Should weapon durability stay? It gives the game a second, slower "stamina", which could fit or could be one resource too many.
3. Should the death drop include weapon ABS, or only Gilda?
4. Normal saves or a single save slot? A sandbox session like the Gauntlet's is possible, but a persistent world wants a real save.
