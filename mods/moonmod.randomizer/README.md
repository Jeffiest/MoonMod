# Randomizer

A new Dark Cloud from one seed. Each part is a setting:

| Part | What changes |
| --- | --- |
| **Shops** | Every shop is restocked from what all the shops sell, the same number of goods each, weapons for weapons and goods for goods. A Norune shop may sell a late-game sword. |
| **Weapons** | Every weapon's attack, endurance, speed, magic, durability and attack cap move within the spread (30% by default). |
| **Drops** | Each monster's rare drop and steal item become another supply item or, for steals, sometimes an attachment. A monster with no drop still has none. |
| **Chests** | That share of the supply items and attachments you find in chests become another of the same kind. Story items and keys never change. |
| **Floors** | Each floor's layout comes from the seed and how many times you have been down it, so two players on one seed walk the same floors. |

**The seed.** A save keeps the seed it first loaded with, so a playthrough never reshuffles. A new game takes its seed
from *Seed for a new save*:

- **Daily** (the default): today's date, such as 261104 for 4 November 2026. It is the UTC day, so everyone who
  starts that day plays the same game. It needs the engine's `info.get` date; an older engine falls back to the
  Fixed seed.
- **Fixed**: the *Fixed seed* setting.
- **Random**: a new seed for every new game.

**Share code.** The mod's **Seed and Share Code** action shows the save's seed and a code such as `261104-SWDF5`: the
seed, a letter for each part that is on (Shops, Weapons, Drops, Floors) and the chest share in tens. A friend sets
*Seed* to Fixed, *Fixed seed* to the number and the parts to match, and starts a new game.

**Other mods.** Dungeon+ holds the shop lists and weapon definitions while it runs, so with it on those two parts are
skipped, and the action says so. Vigil's *The same floors every visit* also picks floor seeds; with both, the last to
ask wins, so turn one off. The Randomizer sits out Dark Genie's Gauntlet and other sandbox runs.

Tests: `lua tools/tests/randomizer/test_randomizer.lua`.

## Playtest

- [ ] A new game announces its seed and code; Norune's shops sell an odd mix.
- [ ] A weapon's stats in the shop differ from the wiki's.
- [ ] A monster's drop differs; stealing works.
- [ ] Opening chests: about half the supplies are something else, and keys arrive as keys.
- [ ] Two machines on the same seed: Divine Beast Cave floor 1 has the same layout.
- [ ] Load the save the next day: the seed is unchanged.
