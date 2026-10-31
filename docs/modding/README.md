# Modding with MoonFactory

This is the modder's guide to MoonFactory (Moon Mod), the mod framework built into the Chronicle (Dark Cloud) and
Chronicle Two (Dark Chronicle) PC ports. It shows how the bundled mods were made, so the next mod is easier to make.
The [API map](../API.md) lists every operation. These pages explain how to put the operations together into a mod,
what to do when the API can't do something yet, and how to test the result.

Everything here comes from building real mods. Dark Genie's Gauntlet (`mods/moonmod.roguelike`) is a whole roguelike
game mode. Opar (`mods/moonmod.opar`) adds a seventh playable hero. RPG, Ascension and Dungeon+ change the story game.
When a page says "the Gauntlet does it this way", the code is there to read.

## Where to start

| You want to... | Read |
| --- | --- |
| Make your first mod and see it run | [Your first mod](FIRST_MOD.md) |
| Do something specific: a new floor, an NPC, a boss, a game mode, a weapon, a hero | [Cookbook](COOKBOOK.md) |
| Do something the API can't do yet | [Extending the engine](EXTENDING_THE_ENGINE.md) |
| Check that your mod works, outside and inside the game | [Testing mods](TESTING.md) |
| Understand how Dark Cloud's own code behaves (units, floors, triggers, saves) | [Dark Cloud engine notes](DARK_CLOUD_NOTES.md) |
| Look up an exact operation, field or event | [API map](../API.md) |
| Give a character a new animated move | [Animation guide](../ANIMATION_GUIDE.md) |
| Replace a model or texture | [Model replacements](../MODEL_REPLACEMENTS.md) |
| Write native C code instead of Lua | [Native SDK](../NATIVE_SDK.md) |

## The framework in one page

**A mod is a folder.** It holds `mod.json` (identity, permissions, settings), a Lua entry script, and any resources the
mod ships (PNGs, model packs, motion files, sounds). The folder is named after the mod's id, for example
`author.my-mod`. Players drop it into the game's `mods` folder and switch it on in the Mod Manager.

**Each mod runs in its own Lua sandbox.** There is no `io`, `os`, `debug` or `package`. Each mod has a memory ceiling
and an instruction budget per callback. A mod that throws an error is switched off on its own, and the other mods keep
running. All of a mod's contact with the game goes through the `game.*` API.

**The API is a catalog of versioned operations.** `game.dungeons.register`, `game.player.heal`,
`game.ui.choice_open` and the rest each check the mod's declared permissions (`game.read`, `game.write`,
`content.register`, `storage.read`, `storage.write`). Each one either does its job or returns `nil, {code, message}`.
An operation the running game lacks reports `unsupported`; it never pretends to work. A mod written for a newer engine
can therefore run on an older one, with the features the old engine can't do switched off.

**Everything a mod does is owned.** Floors, formulas, HUD bars, NPCs, title modes, shop goods and the rest are recorded
against the mod that made them. Unloading the mod undoes them. This is why the operations say "one mod at a time"
where two mods would fight over one thing (the rest-floor builder, the Warden room): the second mod is refused and
told who has it.

**Mods react to events.** `moonmod.on("game.tick", fn)` runs every frame. Scene changes, floor generation, kills,
hits, item pickups, doors, title-menu choices and run-menu picks are all events too. The event list is in the
[API map](../API.md#events-and-update-phases), and `game.events.list()` returns it at run time.

**Mods keep their own data.** `moonmod.storage` is per-mod key/value storage that lasts across saves (the Gauntlet's
Moon Shards and unlocks live there). `game.save` is per-mod data tied to the player's save. `moonmod.settings` are
the typed options declared in `mod.json`, which the Mod Manager draws for the player.

**When Lua isn't enough, the engine grows.** The engine is the Chronicle port with the MoonFactory patch applied, and
it is open source. Every Gauntlet feature that the API couldn't do (rest floors, Warden rooms, shortcut doors, run
menus, new moves, extra heroes) became a new, documented, tested operation that any mod can use. Dark Cloud's fixed
limits (monster slots, floor size, rooms, chests, weapon slots, characters) have been raised the same way. If your mod
hits a wall, raise the wall. [Extending the engine](EXTENDING_THE_ENGINE.md) shows how.

## The rules the bundled mods follow

These habits are why the bundled mods survive engine changes and each other:

1. **Call the game through a guard.** Wrap calls so a missing operation or a refusal never throws (the `try` and
   `call` helpers in [Your first mod](FIRST_MOD.md#guard-every-game-call)). Check the result before using it.
2. **Validate what you receive and what you send.** Engine operations reject unknown fields, so a typo fails loudly
   instead of being ignored. Send no field at all rather than an empty table, because an empty Lua table reaches the
   engine as an empty JSON object, not an array.
3. **Own what you change, and give it back.** Undo your changes when your feature turns off: clear the HUD bar, drop
   the formula, set `{enabled = false}`. Unloading does this for you, but a setting turned off mid-game doesn't.
4. **Sit out other mods' game modes.** During another mod's sandbox session (the Gauntlet), a story-game mod should
   stand down. See [Cookbook: sharing the game with other mods](COOKBOOK.md#share-the-game-with-other-mods).
5. **Put features behind settings.** Each bigger Gauntlet feature has a setting with a sensible default, so a player
   can turn off what they don't like, and you can turn off what you're debugging.
6. **Test outside the game first, then in it.** A fake game adapter runs whole Gauntlet runs in seconds. The real game
   then confirms what the fake can't. See [Testing mods](TESTING.md).
