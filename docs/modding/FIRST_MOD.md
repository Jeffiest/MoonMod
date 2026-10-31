# Your first mod

This page builds a small Chronicle mod from nothing: **Floor Blessing**, which heals the party a little each time they
reach a new dungeon floor. On the way it covers the manifest, settings, events, guarded game calls, storage, a
pop-up notice and a button in the Mod Manager. The finished mod is about 60 lines.

## 1. Make the folder

Start from the template, or make the two files by hand:

```powershell
python .\tools\moonfactory.py new yourname.floor-blessing --output .\yourname.floor-blessing --target chronicle
```

A mod's folder is named after its id. Ids are lowercase, `author.name`, with letters, digits, `.`, `_` and `-`.

Where the game looks for mods on Chronicle, in this order:

1. `mods\` in the Chronicle checkout (a source build run from the checkout).
2. `mods\` beside `darkcloud.exe`.
3. `<save folder>\mods\` (a copy of the game run with `--save <folder>`).

New mods start **disabled**. Turn yours on in **Options > Game > Mod Manager** (or the **MODS** slot of the pause
ring). After that, a change to the Lua takes a game restart.

## 2. Describe it: `mod.json`

```json
{
  "schema_version": 1,
  "id": "yourname.floor-blessing",
  "name": "Floor Blessing",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "Each new dungeon floor heals the party a little.",
  "framework_api": 1,
  "games": ["chronicle"],
  "entry": "main.lua",
  "permissions": ["game.read", "game.write", "content.register", "storage.read", "storage.write"],
  "settings": [
    {"id": "amount", "name": "HP healed per floor", "type": "integer", "default": 20, "min": 5, "max": 200, "step": 5},
    {"id": "notice", "name": "Show a notice", "type": "boolean", "default": true}
  ]
}
```

- **`permissions`** are checked on every call. A missing permission fails the call with a clear message. Ask only for
  what you use. `game.read` reads the game, `game.write` changes it, `content.register` adds things (floors, items,
  manager buttons), and `storage.*` covers your mod's own storage.
- **`settings`** are drawn by the Mod Manager for the player. The types are `boolean`, `integer`, `number`,
  `string` and `choice` (with `choices`). Read them with `moonmod.settings.get(id)`.
- **`games`** is `chronicle`, `chronicle-two` or both. Most of what the bundled mods use is Chronicle-only, and the
  [API map](../API.md) says which operations are which.
- To work with another mod, list it in `dependencies` (it must be present) or `optional_dependencies` (used when it's
  there), and in `load_after`. The whole schema is [`manifest.schema.json`](../../manifest.schema.json).

## 3. Write `main.lua`

```lua
-- Floor Blessing: each new dungeon floor heals the party a little.
local ID = "yourname.floor-blessing"

-- Guard every game call: a missing operation or a refusal returns nil instead of throwing.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= type(fallback) then return fallback end
  return value
end

-- Kept across saves and restarts: how many floors have blessed the party.
local blessings = tonumber(moonmod.storage.get("blessings")) or 0

local function bless()
  local amount = setting("amount", 20)
  local healed = 0
  -- party.list is the joined characters, each {id = "toan", max_hp = ..., ...}
  for _, member in ipairs(try(game.party.list) or {}) do
    if type(member) == "table" and try(game.player.heal, {amount = amount, character = member.id}) then healed = healed + 1 end
  end
  if healed == 0 then return end
  blessings = blessings + 1
  moonmod.storage.set("blessings", blessings)
  if setting("notice", true) then
    try(game.ui.notify, {message = "The floor blesses the party: +" .. amount .. " HP.", duration_frames = 240})
  end
end

-- A new floor: the location changed and we are now in a dungeon on a different floor.
moonmod.on("game.world.location_changed", function(e)
  if e.context ~= "dungeon" or type(e.floor_id) ~= "number" then return end
  local before = e.previous or {}
  if before.context == "dungeon" and before.dungeon_id == e.dungeon_id and before.floor_id == e.floor_id then return end
  bless()
end)

-- A button on the mod's Actions page in the Mod Manager.
try(game.ui.register, {id = "count", label = "Blessings so far", description = "How many floors have blessed you."})
moonmod.on("ui.action", function(action)
  if action.id == "count" then
    try(game.ui.notify, {message = "Floor Blessing has healed the party " .. blessings .. " times."})
  end
end)

local mod = {}
function mod.on_load() moonmod.log("info", ID .. " ready, " .. blessings .. " blessings so far") end
function mod.on_unload() moonmod.log("info", ID .. " unloaded") end
return mod
```

> Check field names against the [API map](../API.md) before relying on them. `try` makes a wrong guess fail quietly
> instead of switching your mod off, but a wrong guess still does nothing, and nothing tells you why.

### How a script runs

- The whole file runs once when the mod loads, so registrations (floors, items, buttons) usually sit at the top
  level. The returned table's `on_load` runs after loading (the `runtime.loaded` event) and `on_unload` runs before
  unloading.
- Callbacks (`moonmod.on`) each get an instruction budget. Heavy work belongs in a callback that runs rarely, not in
  `game.tick`. The Gauntlet does most per-frame work only every 15 or 30 frames (`if frame % 30 ~= 0 then return end`).
- Lua is 5.5 with the base, `table`, `string`, `math` and `utf8` libraries. `print` is not the way to log; use
  `moonmod.log(level, message)`.

### Guard every game call

Every `game.*` operation returns `result` on success or `nil, {code, message}` on failure. Engine operations can be
missing on an older engine, and a few raise on bad arguments. The Gauntlet uses two helpers everywhere:

```lua
-- try: the result, or nil. For calls whose failure is fine to ignore.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- call: the result and the error, for calls whose failure you want to report or work around.
local function call(fn, ...)
  if type(fn) ~= "function" then return nil, {code = "unsupported", message = "operation missing"} end
  local ok, value, err = pcall(fn, ...)
  if not ok then return nil, {code = "error", message = tostring(value)} end
  return value, err
end
```

Use `call` where the failure matters, and log it:

```lua
local registered, err = call(game.dungeons.register, definition)
if not registered then moonmod.log("warn", "floors unavailable: " .. (type(err) == "table" and err.message or tostring(err))) end
```

To feature-test without calling, use `moonmod.api.supports("dungeons.set_rest_room")`.

## 4. Run it and read the log

Copy the folder into the game's `mods` folder, start the game, enable **Floor Blessing** in the Mod Manager and enter
a dungeon.

Mod log lines go to the game's standard error as `moonmod[info][yourname.floor-blessing]: ...`. Errors in your
script, and the mod being switched off because of them, show up there too. To see them, start the game from a
terminal and send standard error to a file:

```powershell
.\darkcloud.exe 2> mods.log
```

The Mod Manager also shows each mod's state, and your notices appear over gameplay.

## 5. Where to go next

- **Persist correctly.** `moonmod.storage` is yours across every save, which suits unlocks, records and settings-like
  data. `game.save.get/set` follows the player's save slot, which suits story progress. `game.save.slot_id()` tells
  save slots apart. Versioned changes to saved data go through `game.save.migrate` (see the
  [API map](../API.md#shared-save-migrations)).
- **Show more.** HUD text layers, HUD bars and icons, choice panels, a run menu that replaces the pause, a page on
  Journal > Character, and boss cards are all in the [Cookbook](COOKBOOK.md#show-things-to-the-player).
- **Add content.** Floors, items, weapons, enemies, NPCs, playable characters and title-menu game modes are in the
  [Cookbook](COOKBOOK.md).
- **Test it.** Write a fake adapter test before the mod grows. See [Testing mods](TESTING.md).
- **Read real mods.** [`examples/`](../../examples/) holds small single-feature mods.
  [`mods/moonmod.opar`](../../mods/moonmod.opar/main.lua) (about 300 lines) is a medium one.
  [`mods/moonmod.roguelike`](../../mods/moonmod.roguelike/main.lua) is the largest, and its section comments are a
  map of a whole game mode.
