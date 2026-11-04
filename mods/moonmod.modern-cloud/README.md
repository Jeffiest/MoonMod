# Modern Cloud

Quality of life for Chronicle's story game. Each part is its own setting in the Mod Manager, and **Check** on the
mod's Actions page shows what is set right now.

| Setting | Default | What it does |
| --- | --- | --- |
| Thirst | 50% | How fast the water gauge drains. 0 keeps it full in dungeons. |
| Weapon wear | 75% | How fast weapons lose durability per hit. |
| Weapon guard | Repair Powder | **Warn** tells you when the weapon drops below the warning level, again at half of it, and when it is about to break. **Repair Powder** also uses one of your Repair Powders to mend the weapon fully when it is three points from breaking. **Never break** keeps it at four points instead, with a notice to repair it. **Off** does nothing. |
| Warn when durability is below | 25% | The first warning's level. |
| Show the whole floor map | off | The floor map as if you held the Map. |
| Show monsters on the map | off | Monsters on the map as if you held the Magical Crystal. |
| Character switch wait | 50% | The two waits of a switch from the battle menu. 0 switches as soon as the model loads. |
| Walk speed in dungeons | 100% | Up to 150%. |
| Keys 1, 2, 3 use the quick item slots | on | On the keyboard, in dungeons, each key uses its quick slot the way the action button does. |

Modern Cloud sits out Dark Genie's Gauntlet and other sandbox runs, and comes back when they end. Its tuning combines
with other mods' (multipliers multiply), so with Vigil or RPG on, the effects stack.

Tests: `lua tools/tests/modern-cloud/test_modern_cloud.lua`.

## Playtest

- [ ] Thirst 0: the water gauge stays full through a whole floor.
- [ ] Wear down a weapon: the two warnings come at 25% and 12%.
- [ ] With a Repair Powder in the bag, the weapon is mended at three points and the powder is gone.
- [ ] Never break: hit things at three points; the weapon stays whole.
- [ ] Keys 1, 2 and 3 use the quick slots in a dungeon and do nothing in town.
- [ ] Map and monster reveal show on the minimap.
