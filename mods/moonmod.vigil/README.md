# Vigil (prototype S1)

Souls-lite combat for Chronicle's story game: slow, deliberate fights where you read an enemy, then guard or evade,
then punish. This is the first prototype. It uses only what the engine already offers. The plan, the findings behind
it and the engine work still to come are in [`VIGIL_PLAN.md`](../../VIGIL_PLAN.md).

## What it does

| | |
| --- | --- |
| **L2: evade** | A roll the way the stick points, or a backstep with the stick at rest. Xiao, Ruby and Osmond tumble and hop back instead. You can't be hit while evading. Each evade costs **35 weapon gauge** and has a 30-frame cooldown. With the starting Dagger, four quick evades in a row empty the gauge, and L2 then waits for it to refill to 35. An evade can cut a swing short, but only 6 frames after its blow lands, so you commit to a swing. |
| **The weapon gauge is your stamina** | It's the gauge under your weapon at the bottom left. Dark Cloud already spends it on combo swings (a follow-up needs 20 and costs 25), and refills it at your weapon's Speed. |
| **Guard (lock on, then hold R1)** | The game's own guard. While you hold it, the gauge recovers at a quarter of its speed. |
| **Enemies hit hard** | ×2.5 damage. |
| **Shorter hit stun** | A hit stuns you for 40% of the usual time. In Dark Cloud the stun is also your protection after a hit, so the next hit can land sooner. Don't get hit twice. |
| **Slower character switches** | ×2 the wait, so a switch isn't a free escape. |
| **No Stamina power-up from enemies** | In this game the "Stamina" ailment is actually a power-up (double attack, defense and gauge refill), and some enemies hand it out. Vigil turns that off. |

Every number is a setting in the Mod Manager. **Check** on the mod's Actions page shows what's set right now.

Vigil sits out Dark Genie's Gauntlet. During a run it hands back L2, its tuning and its damage formula, and takes them
again afterwards.

## Not yet (needs engine work, see the plan)

- The guard still blocks **everything, from every side, for free**. A front-only guard, a gauge cost per blocked hit,
  guard break and parry come with E1.
- **A hit still refills the gauge to full**, and the first swing of a combo is free. E2 fixes both.
- Vigil can't read the gauge yet (E3), so there's no Exhausted state of its own.
- With a keyboard, pick your guard key in the settings (*Keyboard key you guard with*) so the slower recovery works.

## Playtest (gate S1)

Divine Beast Cave floors 1-3 as Toan, Vigil's defaults, nothing else gameplay-changing on.

- [ ] L2 with the stick pushed rolls that way; at rest, he backsteps. Neither can be hit.
- [ ] Four quick evades in a row empty the gauge, and L2 does nothing until it refills.
- [ ] L2 right after a swing's blow cuts the swing. L2 before the blow doesn't.
- [ ] Holding the guard visibly slows the gauge's refill.
- [ ] Trading hits with a Skeleton Soldier loses. Evading or guarding and then hitting wins.
- [ ] Getting hit, then hit again soon after, is possible (the shorter stun), and it feels fair rather than cheap.
- [ ] Note what feels wrong, with numbers: which setting, which value felt right.

Record results in `tools/tests/vigil/playtest-log.md`.

## Tests

```bash
lua tools/tests/vigil/test_vigil.lua
```

45 checks against a fake adapter that refuses what the real one refuses: the evades for all six characters, the guard,
settings, the fallback to the engine's own dodge when the motions can't load, sitting out the Gauntlet, and the
shipped motion files.

The motions in `resources/anims/` are copies of the Gauntlet's (authored with `tools/anim`; see
[`docs/GAUNTLET_ANIMATIONS.md`](../../docs/GAUNTLET_ANIMATIONS.md)).
