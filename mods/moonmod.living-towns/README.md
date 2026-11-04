# Living Towns

The towns ask things of you once you start reaching their dungeons, and their stores keep up with the story.

## The bounty board

Each adventure day the villagers post up to three bounties (*Bounties a day*), each in a dungeon your story has
reached and asked by someone from its town:

| Bounty | Done when |
| --- | --- |
| **Hunt** | you fell that many monsters in the dungeon |
| **Chests** | you open that many chests there |
| **Deeper** | you reach a floor one or two past your deepest there |
| **Fetch** | you hand in the items they want (Mod Manager: **Hand In and Collect**) |

The board grows with the story: more dungeons reached means bigger hunts, more Gilda and better reward items.
A save's board for a day is always the same. **Bounty Board** in the Mod Manager shows it.

**The villager.** On the floors of a dungeon with an open bounty a villager waits just inside the exit gate. Walk up
to him and he pays every bounty of that dungeon that is done (Gilda and an item), or reminds you what is left.
**Hand In and Collect** pays from town too.

## Stores that keep up

A general store (a shop that sells mostly goods) gains stock for each dungeon reached: Premium Water, Cheese and
Antidote after the Wise Owl Forest; Premium Chicken, Holy Water, Stamina Drink and the Fire and Ice attachments after
the Shipwreck; Mighty Healing, Auto Repair Powder, Thunder and Wind after the Temple; Revival and Powerup Powder and
Holy after the Moon Sea. The goods are added with `shops.register_item`, which claims no shop, so Dungeon+'s daily
rotation and the Randomizer's shuffle still work beside it.

Living Towns sits out Dark Genie's Gauntlet and the Challenges.

Tests: `lua tools/tests/living-towns/test_living_towns.lua`.

## Playtest

- [ ] After reaching Divine Beast Cave, a notice says bounties are posted; the board names Norune's villagers.
- [ ] A hunt counts kills in its dungeon only, and the villager by the exit gate pays it.
- [ ] A fetch takes the items at Hand In and Collect.
- [ ] After reaching Wise Owl Forest, Norune's general store sells Premium Water.
