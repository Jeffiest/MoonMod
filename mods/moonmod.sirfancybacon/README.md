# SirFancyBacon Mod Pack

Quality-of-life ideas from **SirFancyBacon**'s branches of Chronicle
([github.com/SirFancyBacon/Chronicle](https://github.com/SirFancyBacon/Chronicle)), redone as a MoonMod mod. The ideas
and their rules are his; this pack carries over the ones the MoonMod API can do today. His gear and running plan
(VIGIL_PLAN §11) is already in Vigil and is not repeated here.

## In the pack

| Setting | What it does | From |
| :-- | :-- | :-- |
| Auto Repair Powder works from the bag | A weapon about to break (3 durability or less) is mended to full by an Auto Repair Powder (item 183) in the bag, with the repair sound. One in a quick slot is left to the game, as retail does. | qol-pack, "Inventory auto repair" |
| T mends the weapon | T uses one Repair Powder (177) from the bag on the active weapon. His pack lets Repair Powder sit in a quick slot; a key does the same without a slot. (R is R2 by default and G is the Gauntlet's curse key.) | qol-pack, "Repair Powder in a quick slot" |
| The floor list warns of limited floors | On a dungeon's floor list, a floor that lets only one character in, locks the weapon, or dries you out faster shows its warning before you go in. Floors fixed by the game (Divine Beast Cave B7 and B11, Wise Owl Forest 4 and 12, Sun and Moon Temple 5 and 13) and the limits the save rolled (`dungeons.floor_rules_get`). | floor-select, "Limited-floor warning" |

With Modern Cloud's weapon guard on "Repair Powder", both may step in at 3 durability; whichever mod runs first that
frame mends the weapon, so only one powder is spent.

## Waiting on engine support

These are his and worth having, but the MoonMod API has no way to do them yet. Each needs the engine op named.

| Feature (branch) | Engine op it needs |
| :-- | :-- |
| Healing springs restore the whole party (qol-pack) | An event from the native spring, e.g. `game.dungeon.spring_used {character}`; then Lua heals and waters the living party |
| Favourite food gives a fixed defense: +5 for Xiao, Ruby, Osmond, +7 for Toan, Goro, Ungaga (qol-pack) | A native item-use hook with a writable amount (`native.item.use`), or `items.use_rules_set {item, fixed_amount}` |
| Item windows list only the key they take; locked doors open with their key (qol-pack) | `dungeons.rules_set {key_item_filter, auto_open_locked_doors}` |
| A red "!" in the floor list's row, and Circle asks "Leave dungeon?" (floor-select) | `dungeons.set_badges` taking a glyph, and a floor-list cancel hook with a leave-to-town op |
| Enhanced Fishing: Dark Cloud 2's bite and tension fight, rod stats, three rods, Ruty's quest in Queens (fishing-framework) | A `fishing.*` domain: fish, bait, spots, bite and fight rules, prizes, rods, and `game.fishing.caught`/`lost` |
| Georama request list per building (journal) | A list screen usable in town, villager home data, and the talk lines heard |
| Knockdowns and staggers held for 2 s, hits that know their move (combat-framework) | A monster reaction/hold op and the move on `game.enemy_hit`; overlaps Vigil's poise |

His engine fixes (the windmill-slash crash, chest-tracker counts, the limited-zone window, the options hand) belong
in the Chronicle patch, not in a mod.

## Tests

`lua tools/tests/sirfancybacon/test_pack.lua`
