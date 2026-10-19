# Shipped packages

Each folder is one mod: `mod.json` and `main.lua`. Copy a folder into `<save>\mods\` (or `mods\` beside
`darkcloud.exe`) and turn it on in **Options > Game > Mod Manager**. All of these are for Chronicle (Dark Cloud 1).
Test and tutorial packages live in [`../examples/`](../examples/), not here.

| Package | What it does | In game |
|---|---|---|
| `moonmod.rpg` | **RPG: Character Paths.** Kills give XP; levels give max HP, damage, toughness and skill points. Toan spends them on three paths (Swordsman, Survivor, Explorer, 21 nodes): crits, Riposte, Blade Study, Sword Dance, Second Wind, Battle Cry on a Focus bar, thirst and durability savings, Lucky Find, Atla Sense, Fleet Foot, Keen Eyes. Weapon mastery, loot rolls and the DarkCloud-Expanded weapon abilities. Other characters level up; their own paths come later. | **Journal > Character** (or K / L1+R1+R3 with the Hub). Hold L2 + Square / Triangle / Circle (F4-F6) for the powers. Needs the Chronicle patch's `player.tuning_set` for five nodes. |
| `moonmod.dungeon-plus` | **Dungeon+.** Replay floors at Tiers 1-5, presets and mutators, a bounty and streaks per floor, a bestiary and trophies, champions with themed loot, enemy variety, harder AI, the DarkCloud-Expanded weapon data and shops. | Floor list: Square / Triangle (or `[` `]`) pick the tier. Mod Manager > Dungeon+ for actions and the trophy journal (J with the Hub). |
| `moonmod.hub` | **MoonMod Hub.** Hotkeys and quick links to the other packages' pages. | K or L1+R1+R3: Character page. J: Dungeon+ journal. Mod Manager > Hub > Actions for the links. |
| `moonmod.controls` | **Controls.** Dungeon quick-item hotkeys, party shortcuts, first-person toggle. | Keys are settings in the Mod Manager. |
| `moonmod.autosave` | **Autosave.** Turns Chronicle's guarded town autosave slot on or off. | One setting. |
| `moonmod.expanded-town` | **Expanded Town Camera.** The legacy overhead camera while walking in towns. | Toggle in the Mod Manager; a setting keeps it on. |

`moonmod.rpg` and `moonmod.dungeon-plus` talk to each other when both are on (champion and tier XP bonuses); each
works alone. The Hub only links to packages that are enabled.

Replaced packages: Ascension 1.6, Weapon Mastery and Ascension 3.0 (`moonmod.adventurer`) were folded into
`moonmod.rpg` on 2026-10-19; they are in the git history if you need them. The Lua API every package uses is in
[`../docs/API.md`](../docs/API.md).
