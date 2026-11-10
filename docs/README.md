# MoonMod documentation

## Make a mod

| Document | What it is |
| --- | --- |
| [Modder's guide](modding/README.md) | Where to start: how the framework fits together and what to read next |
| [Your first mod](modding/FIRST_MOD.md) | A mod from an empty folder to running in the game |
| [Cookbook](modding/COOKBOOK.md) | Recipes: game modes, floors, rooms, bosses, NPCs, weapons, shops, new heroes |
| [Testing mods](modding/TESTING.md) | Checking a mod without the game, with a headless game, and in play |
| [Packs and live on/off](modding/PACKS.md) | Shipping several mods as one, and when a switch applies at once |
| [Extending the engine](modding/EXTENDING_THE_ENGINE.md) | Adding an operation when Lua can't do the job yet |
| [Event battles and fishing](modding/EVENT_BATTLES_AND_FISHING.md) | What the API offers for the button-prompt scenes and fishing |
| [Dark Cloud engine notes](modding/DARK_CLOUD_NOTES.md) | How the game's own code behaves: units, floors, triggers, saves |

## Look things up

| Document | What it is |
| --- | --- |
| [API reference](API.md) | How calls work, errors, permissions, and the map of chapters |
| [Operation and event index](api/OPERATIONS.md) | Every operation and event, with permission and per-game support (generated) |
| [Runtime and core services](api/runtime.md) | Saves, content registry, localization, commands, quests, skills, events, packs |
| [Package files and assets](api/assets.md) | Resources, file overrides, audio, game text, models, animations |
| [Mod Manager, HUD, screens, input, camera](api/ui.md) | Notices, manager pages, HUD, panels and menus, input, camera |
| [Player and party](api/player.md) | Health, tuning, guard and gauge, moves, forms, companion, party, wallet |
| [Items, gear, weapons, shops](api/items-weapons.md) | Definitions, registration, inventory, gear, weapon growth, shops |
| [Monsters, entities, combat](api/combat.md) | Monsters, spawning, damage, statuses, formulas, monster AI |
| [Dungeons and floors](api/dungeons.md) | Added floors, generation, kept floors, zones, shrines, rules, lighting |
| [Georama](api/georama.md) | Town state, requests, piece variants, placement, Atla |
| [World, locations, scripts, game modes](api/world.md) | Locations, villagers, script hooks, title modes, sessions |
| [Online play and co-op](api/online.md) | Rooms, the co-op save, the room's mods, player messages |
| [Manifest schema](../manifest.schema.json) | The JSON schema for `mod.json` |

## Assets and native code

| Document | What it is |
| --- | --- |
| [Animation guide](ANIMATION_GUIDE.md) | Giving a character a new animated move, start to finish |
| [Gauntlet animations](GAUNTLET_ANIMATIONS.md) | How the Gauntlet's motions were built and checked; the reference for a new character's set |
| [Model and texture replacements](MODEL_REPLACEMENTS.md) | Replacing Chronicle's meshes and textures from a package |
| [Native SDK](NATIVE_SDK.md) | The C plugin ABI, its trust model and limits |
| [ChronicleTwo-Script compatibility](ChronicleTwo-Script.md) | How MoonFactory mods and DC2-Toolkit disc mods relate |
| [ChronicleTwo-Script bridge](CHRONICLETWO_SCRIPT_BRIDGE.md) | The design of the bridge tool |

## Build and verify

| Document | What it is |
| --- | --- |
| [Chronicle port](../ports/chronicle/README.md) | Building Dark Cloud's PC port with MoonFactory, and how the patch is laid out |
| [Chronicle Two port](../ports/chronicle-two/README.md) | The same for Dark Chronicle |
| [Verification](VERIFICATION.md) | The headless verifier, its options, and what each check proves |

## Plans and history

Working documents, kept in [`plans/`](plans/). They record what was decided and why; where one disagrees with the
guides above or with the game, the guides and the game are right.

| Document | What it is |
| --- | --- |
| [Delivery roadmap](plans/ROADMAP.md) | The framework's stages and the gaps still open |
| [Next work checklist](plans/CHECKLIST.md) | The mods and tools worked through in order, with what still needs a playtest |
| [Online co-op plan](plans/COOP_PLAN.md), [Co-op 2](plans/COOP_V2_PLAN.md) | The co-op rules, what is built, and what would make it play well |
| [Vigil plan](plans/VIGIL_PLAN.md) | The Souls-lite combat overhaul and the Vigil World |
| [Gauntlet gate loop](plans/GAUNTLET.md), [Gauntlet handoff](plans/HANDOFF-roguelike.md) | Taking Dark Genie's Gauntlet from its test harness to the game |
| [Opar plan](plans/OPAR_PLAN.md), [Opar verification](plans/OPAR_VERIFICATION.md) | The seventh playable character and how he is graded |
| [Seda plan](plans/SEDA_PLAN.md) | The eighth hero |
| [VR plan](plans/VR_PLAN.md) | A VR mode for Dark Cloud |
| [Legacy mod parity](plans/LEGACY_MOD_PARITY_PLAN.md), [mod audit](plans/MOD_AUDIT_AND_GUIDE.md) | Bringing the older Windows-branch mods across |
| [Code review ledger](plans/CODE_REVIEW_CHANGELOG.md) | Review findings and fixes across the runtime copies |
