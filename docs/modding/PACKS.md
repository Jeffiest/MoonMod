# Packs and turning mods on and off live

Two things change how mods are installed and switched:

- A **merged pack** puts several mods into one folder and one script, behind one Mod Manager switch. The MoonMod Pack
  (`mods/moonmod.pack`) is one: Autosave, Controls, Expanded Town Camera, Modern Cloud, SirFancyBacon, Living Towns,
  Dungeon+, RPG: Character Paths, Dark Genie's Gauntlet, Opar, Vigil and the Hub.
- **Live on/off**: switching a mod on or off in the Mod Manager takes effect at once when the engine can undo what the
  mod did, and a mod whose files change on disk comes back with the new files. Otherwise the change waits for a
  restart, and the Mod Manager says why.

## Merged packs

### What a part keeps

Each mod in a pack is a **part**. The engine runs every part inside the pack's one Lua state, but as its own owner:

| | A part keeps | So |
| --- | --- | --- |
| Id and version | its own (`moonmod.rpg` 2.0.1) | other mods' `dependencies` and `scripts.call_function` reach it as before |
| Settings | its own, stored under its id in the profile | a player's choices carry over from the separate mod |
| Saved data | `moonmod/data/<part id>/` (`moonmod.storage`, `game.save`, quests, skills) | progress carries over; nothing has to move |
| What it registers | owned by the part: input binds, title modes, HUD, tuning, formulas, menus, script hooks... | parts never overwrite each other's one-per-owner state, and turning a part off releases only its own |
| Events | `moonmod.on` handlers run as the part; events sent to the part (`settings.changed`, `ui.action`, its title mode's) reach only it | |
| Co-op | `mods.list()` lists each running part with its own version and `coop` role | a room compares parts, so the pack and the separate mods match each other |
| Globals | its own `_ENV` | two parts can both have a global called `apply` |

The pack itself is `"coop": "local"`, so co-op never asks for the pack, only for its parts.

### The Mod Manager

The pack is one row; its parts are listed indented under it, each with its own switch and settings page. The pack's
switch turns the whole pack on or off; each part's own switch is remembered apart from it (in the profile's `parts`,
under the pack), so a part you turned off stays off when the pack goes off and on again. Parts start switched on. A
part's switch works while its pack is off too (it shows dimmed): the pack starts it or not as it was left. A part
turned off while the pack runs stops at once when it can (see below).

A pack's part stands in for a separate mod of the same id while the pack is on: install both and the separate one
steps aside (stopping at once when it can). Turn the pack off and the separate one is itself again, with its own
switch, and starts at once if it is switched on and can.

### `mod.json`

A pack's manifest is a normal one plus `parts`, one entry per part:

```json
{
  "schema_version": 1, "id": "moonmod.pack", "name": "MoonMod Pack", "version": "1.0.0",
  "framework_api": 1, "games": ["chronicle"], "entry": "main.lua", "coop": "local",
  "permissions": ["game.read", "game.write", "content.register", "storage.read", "storage.write", "scripts.override"],
  "parts": [
    {"id": "moonmod.rpg", "name": "RPG: Character Paths", "version": "2.0.1", "optional_dependencies": ["moonmod.dungeon-plus"],
     "settings": [{"id": "xp_rate", "name": "XP rate (%)", "type": "integer", "default": 100, "min": 25, "max": 300, "step": 25}]}
  ]
}
```

A part entry takes `id`, `name`, `version`, and optionally `description`, `coop`, `settings`, `dependencies` and
`optional_dependencies`, with the same rules as a mod's own. Parts share the pack's permissions, games and folder
(resources). Up to 64 parts; each part's id must be unique and not the pack's.

### The script

The pack's script hands each part over with `moonmod.part.run`, giving either the part's script as source or a
function:

```lua
-- moonmod:part moonmod.autosave
moonmod.part.run("moonmod.autosave", [[
-- mods/moonmod.autosave/main.lua, unchanged
]], part_env("moonmod.autosave"), "moonmod.autosave/main.lua")
-- moonmod:end
```

- `moonmod.part.run(id, source, globals, name)`: the engine compiles `source` as a chunk of its own, the way it
  compiles a mod's script, with `globals` (a table, optional) as its globals and `name` in its error messages. So the
  part has the same room for local variables as when it was a mod of its own, and an error reads
  `moonmod.rpg/main.lua:812: ...`, the line in the part's own file. This is how the MoonMod Pack hands its parts over.
- `moonmod.part.run(id, fn)`: the part is a function of the pack's script. Note that a function body has one local
  variable less room than a main chunk.
- Either way the engine runs the part as itself, only when it is on, and keeps the code so it can start the part
  again later without a restart. The part may return a module table (`on_load`, `on_unload`, `on_tick`), as a mod's
  script may.
- A part given as source starts each time with its globals table as it was handed over: globals an earlier run set
  are gone, as for a mod started again. (A part given as a function keeps whatever its upvalues hold.)
- It returns `true`, or `false` and `"off"` / an error message. A part that fails to compile or load is stopped and
  released, and its row shows the error; the others go on. A part can't start another part.
- `moonmod.part.enabled(id)` says whether a part is switched on; `moonmod.part.list()` gives `{id, enabled, running}`
  for each part.
- The `-- moonmod:part <id>` / `-- moonmod:end` lines mark each part's code. The engine reads them to decide whether
  a part can start mid-game (below); without them it judges the whole script.

Budgets are shared and grow with the pack: the Lua memory ceiling and the per-event handler limit are the usual ones
times (1 + parts), and each part's load gets its own instruction budget. A script may be up to 4 MiB and `mod.json`
up to 1 MiB.

### The MoonMod Pack is generated

Don't edit `mods/moonmod.pack` by hand. Its parts' sources stay in their own folders (`mods/moonmod.rpg`, ...), where
their tests run. After changing one, build the pack again:

```
python tools/pack/build_pack.py           # writes mods/moonmod.pack
python tools/pack/build_pack.py --check   # fails when the pack is out of date
lua tools/tests/pack/test_pack.lua        # the merged script: order, markers, isolation
```

The builder orders the parts by their `dependencies`, `optional_dependencies` and `load_after`, copies every part's
other files (resources, licences) into the pack at the same paths (it stops if two parts ship different files at one
path), and puts each part's README under `docs/<part id>/`. To change which mods are in the pack, edit `PARTS` in
`tools/pack/build_pack.py`.

The builder hands each part over as source, inside a long string deep enough (`[==[ ... ]==]`) to hold it unchanged,
so a part's script needs no changes to go into the pack.

Engines without merged packs refuse the `parts` key and list the pack as invalid.

## Live on/off

### What happens at the switch

| The mod... | Switched on | Switched off |
| --- | --- | --- |
| hooks only what the engine can undo (events, binds, HUD, menus, title modes, tuning, formulas, overrides, shop and weapon edits, ...) | starts at once | stops at once |
| asks for content the game keeps (see below) | starts at once at the title screen; mid-game, after a restart | after a restart, once it has registered any |
| has native code | after a restart | after a restart |
| is needed by a running mod (`dependencies`) | | after a restart |
| needs a mod that isn't running | after a restart | |

**Content the game keeps** is what is written into the game's own tables and can't be taken back while it runs:
`items.register`, `weapons.register`, `weapons.build_up_register`, `characters.register`,
`characters.register_playable`, `dungeons.register` / `world.register_dungeon`, `georama.register`,
`locations.register`, `content.register`, `models.register`, `animations.register`, `animations.player_register`,
`animations.monster_register`, `inventions.register`, `combat.styles_register`. A mod (or part) that called one of
these this run turns off only with a restart; one whose script names any of them turns on only from the title screen,
not in a game in play (a story save, a sandbox or a visit). In the MoonMod Pack that is the Gauntlet, Opar and Vigil; the other parts switch live.

When a change waits, the Mod Manager shows `ON*` / `OFF*` and **RESTART REQUIRED**, and says why, naming what the mod
added: "Off after a restart: it added dungeons, playable characters and weapons, which the game keeps until it
closes". The reason stays on the mod's page until the restart. Switching back cancels the wait.

### What a mod sees

- Started live: `runtime.loaded` with `live = true`. A mod started mid-game missed `game.session.started`; check
  `game.session.get()` in `on_load` if it cares.
- Stopped live: `runtime.unloaded`, then everything it owned is released, as at shutdown. Its saved data is written.

### Changed files

Every two seconds the engine compares each running mod's `mod.json` and entry script with what it loaded. When they
changed and the mod can stop and start live, it reloads with the new files (the log says "reloaded after its files
changed"); otherwise its status says "Its files changed; restart to use them". If the new files don't load (a syntax
error, a file saved half-way), the mod shows the error and is tried again the next time its files change, unless it has
been switched off since. A mod or pack switched on that fails to start is retried the same way. For a pack,
the pack's whole script reloads. Handy while writing a mod: save the Lua, look at the game.

### From code

`Runtime::SetEnabled(id, on, error)` saves the choice (a part's under its pack) and applies it live when it can; the
record's `restart_required` and `restart_reason` say whether and why it waits. `ModRecord::pack` names a part's pack.
Tests: `src/tests/moonmod_pack_live_test.cpp`, and `moonmod_real_pack_test.cpp` (the real pack through the Chronicle
adapter; set `MOONMOD_PACK_PATH` to `mods/moonmod.pack`).
