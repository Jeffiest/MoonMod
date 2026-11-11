-- Plays mods/moonmod.openworld/main.lua against a small fake Chronicle adapter.
-- Usage, from the repository root:  lua tools/tests/openworld/test_openworld.lua   (Lua 5.4 or newer)
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."
local MOD_DIR = root .. "/mods/moonmod.openworld"

local defaults = {}
for line in io.lines(MOD_DIR .. "/mod.json") do
  local id = line:match('"id":%s*"([%w_]+)"')
  local default = line:match('"default":%s*([^,}]+)')
  local name = line:match('"name":%s*"([^"]*)"')
  assert(not (id and name) or #name <= 96, "setting " .. tostring(id) .. ": its name is over 96 bytes")
  if id and default then
    default = default:gsub("%s+$", "")
    if default == "true" then defaults[id] = true elseif default == "false" then defaults[id] = false end
  end
end

local passed, failed = 0, 0
local function check(cond, label, extra)
  if cond then passed = passed + 1; print("  ok   " .. label)
  else failed = failed + 1; print("  FAIL " .. label .. (extra ~= nil and ("  [" .. tostring(extra) .. "]") or "")) end
end
local function fail(code, msg) return nil, {code = code, message = msg} end

local ME = "moonmod.openworld"

-- opts: kind (session kind), town (area the party stands in, or nil for a dungeon floor), visited = {place id = true},
-- owner = {passage = id, roads = id} (rules another mod already holds)
local function boot(overrides, opts)
  opts = opts or {}
  local S = {settings = {}, handlers = {}, notices = {}, kind = opts.kind or "story", town = opts.town, visited = opts.visited or {},
             owner = {passage = opts.owner and opts.owner.passage, roads = opts.owner and opts.owner.roads},
             panel = nil, went = {}, resets = 0, closed = 0, transition_fails = false}
  if opts.town == nil and not opts.floor then S.town = 0 end
  for k, v in pairs(defaults) do S.settings[k] = v end
  for k, v in pairs(overrides or {}) do S.settings[k] = v end
  local function one_owner(key, said)
    return function(a)
      assert(type(a) == "table" and type(a.enabled) == "boolean")
      if S.owner[key] and S.owner[key] ~= ME then return fail("failed", said) end
      if a.enabled then S.owner[key] = ME else
        S.owner[key] = nil
        if key == "passage" then S.resets = S.resets + 1 end
      end
      return {enabled = S.owner[key] ~= nil}
    end
  end
  _G.moonmod = {
    settings = {get = function(id) return S.settings[id] end},
    on = function(name, fn) S.handlers[name] = S.handlers[name] or {}; table.insert(S.handlers[name], fn) end,
    log = function() end,
  }
  _G.game = {
    session = {get = function() return {kind = S.kind} end},
    world = {
      get = function()
        if S.kind == "title" then return fail("failed", "no game") end
        if S.town then return {context = "georama", area_id = S.town, map_id = S.town} end
        return {context = "dungeon", dungeon_id = 0, floor_id = 1}
      end,
      set_roads = one_owner("roads", "another mod already has the roads"),
      transition = function(a)
        if S.transition_fails then return fail("failed", "the way is shut") end
        S.went[#S.went + 1] = a.id; return {}
      end,
    },
    dungeons = {
      set_quick_passage = one_owner("passage", "another mod already set the passage"),
      enter_floor = function(a) S.went[#S.went + 1] = "dungeon " .. a.dungeon_id .. " floor " .. a.floor_id; return {} end,
    },
    locations = {get = function(a)
      local id = a.id:match("^chronicle:location:(.+)$")
      if not id then return fail("not_found", "no such place") end
      return {id = a.id, visited = S.visited[id] == true}
    end},
    ui = {
      notify = function(a) assert(#a.message <= 200); S.notices[#S.notices + 1] = a.message; return true end,
      choice_open = function(a)
        assert(a.id and a.title and #a.options >= 1 and #a.options <= 6 and a.town == true)
        if S.panel then return fail("failed", "a panel is already up") end
        S.panel = a; return {}
      end,
      choice_close = function() S.panel = nil; S.closed = S.closed + 1; return {} end,
    },
  }
  assert(loadfile(MOD_DIR .. "/main.lua"))()
  function S.emit(name, ...) for _, fn in ipairs(S.handlers[name] or {}) do fn(...) end end
  function S.tick(n) for _ = 1, n or 1 do S.emit("game.tick", {}) end end
  function S.gate(town) S.emit("game.town.road", {town_id = town or S.town, location_id = "x", frame = 1}) end
  function S.pick(index) local id = S.panel.id; S.panel = nil; S.emit("ui.choice_made", {id = id, index = index}) end
  function S.titles() local t = {} for i, o in ipairs(S.panel.options) do t[i] = o.title end return table.concat(t, ", ") end
  return S
end

print("The passage")
do
  local S = boot()
  check(S.owner.passage == ME, "held from the moment the mod loads, before the first place is made")
  check(S.owner.roads == nil, "the road is not asked for before the party stands in a town a tick long")
  S.settings.passage = false
  S.emit("settings.changed", {id = "passage", value = false})
  check(S.owner.passage == nil and S.resets == 1, "switched off in its settings, it is let go")
  S.settings.passage = true
  S.emit("game.scene.will_enter", {scene_id = "town"})
  check(S.owner.passage == ME, "and taken up again as the next place loads")

  S = boot(nil, {owner = {passage = "moonmod.vigil"}})
  S.tick(60)
  check(S.owner.passage == "moonmod.vigil", "another mod's passage is left to it")
  S.emit("runtime.unloaded", {})
  check(S.owner.passage == "moonmod.vigil" and S.resets == 0, "and never let go for it")
  S.owner.passage = nil
  S.emit("game.world.location_changed", {context = "georama"})
  check(S.owner.passage == ME, "once the other lets go, it is taken up")

  S = boot(nil, {kind = "sandbox"})
  S.tick(60)
  check(S.owner.passage == nil and S.owner.roads == nil, "nothing is held in another mod's game mode")
  S = boot(nil, {kind = "title"})
  S.tick(60)
  check(S.owner.passage == nil and S.owner.roads == nil, "nor at the title")
  S = boot(nil, {kind = "visit"})
  S.tick(60)
  check(S.owner.passage == nil and S.owner.roads == nil, "nor as a guest in a friend's world")
end

print("The road, where the story has opened the way")
do
  -- an early save: Norune, nothing else on the map yet
  local S = boot(nil, {town = 0, visited = {["norune-village"] = true}})
  S.tick(30)
  check(S.owner.roads == nil, "with no way open the gate stays the world map")
  S.gate()
  check(S.panel == nil, "and the mod answers nothing at the gate")
  -- the story opens Matataki while the party stands in Norune
  S.visited["matataki-village"] = true
  S.tick(30)
  check(S.owner.roads == ME, "a way opens: within a second the gate is the road")
  S.gate()
  check(S.panel and S.panel.id == "openworld.road" and S.titles() == "Matataki Village, Stay", "the road out of Norune is to Matataki", S.panel and S.titles())
  check(S.panel.subtitle == "Out of Norune Village" and S.panel.cancel == true and S.panel.town == true, "asked in the town, the party free to say no")
  S.pick(1)
  check(S.went[1] == "chronicle:location:matataki-village", "taking it walks to Matataki", S.went[1])

  S = boot(nil, {town = 2, visited = {["matataki-village"] = true, queens = true, shipwreck = true}})
  S.tick(30)
  S.gate()
  check(S.titles() == "Matataki Village, Shipwreck, Stay", "Queens before Muska Lacka is found: back, or into the Shipwreck", S.titles())
  check(S.panel.options[1].lines[1] == "Back along the road." and S.panel.options[2].lines[1] == "Into the dungeon, at floor 1.", "each way says what it is")
  S.pick(2)
  check(S.went[1] == "dungeon 2 floor 0", "the Shipwreck is entered at its first floor", S.went[1])
  S.gate()
  S.pick(3)
  check(#S.went == 1, "Stay goes nowhere")
  S.gate()
  local id = S.panel.id; S.panel = nil
  S.emit("ui.choice_made", {id = id, cancelled = true})
  check(#S.went == 1, "nor does backing out")
  S.emit("ui.choice_made", {id = id, index = 1})
  check(#S.went == 1, "an answer with no question open is nothing")

  S = boot(nil, {town = 4, visited = {["muska-lacka"] = true, ["moon-sea"] = true, ["gallery-of-time"] = true}})
  S.tick(30)
  S.gate()
  check(S.titles() == "Muska Lacka, Moon Sea, Gallery of Time, Stay", "Yellow Drops with everything open", S.titles())

  S = boot({story_gates = false}, {town = 1})
  S.tick(30)
  S.gate()
  check(S.titles() == "Norune Village, Queens, Stay", "with the story's gates off every road is open", S.panel and S.titles())
  check(S.panel.options[1].lines[1] == "Back along the road." and S.panel.options[2].lines[1] == "On along the road.", "back and on")

  S = boot(nil, {town = 1, visited = {["norune-village"] = true}})
  S.tick(30)
  S.transition_fails = true
  S.gate()
  S.pick(1)
  check(#S.went == 0 and S.notices[1] and S.notices[1]:find("the way is shut", 1, true), "a road that fails says so", S.notices[1])
end

print("The road, shared")
do
  -- another mod (Vigil, on a Vigil World save) set the roads as the town loaded
  local S = boot(nil, {town = 1, visited = {["norune-village"] = true}, owner = {roads = "moonmod.vigil"}})
  S.tick(90)
  check(S.owner.roads == "moonmod.vigil", "roads another mod holds are left to it")
  S.gate()
  check(S.panel == nil, "and its gate is not answered twice")
  S.owner.roads = nil
  S.tick(30)
  S.gate()
  check(S.owner.roads == ME and S.panel ~= nil, "once it lets go the road is taken up")

  -- on a floor nothing is decided; back in a town with no way, the roads are let go
  S = boot(nil, {town = 1, visited = {["norune-village"] = true}})
  S.tick(30)
  S.town = nil
  S.tick(60)
  check(S.owner.roads == ME, "the road is kept through a dungeon")
  S.town, S.visited = 0, {}
  S.tick(30)
  check(S.owner.roads == nil, "and let go in a town with nowhere to go yet")

  S = boot(nil, {town = 1, visited = {["norune-village"] = true}})
  S.tick(30)
  S.settings.roads = false
  S.emit("settings.changed", {id = "roads", value = false})
  check(S.owner.roads == nil, "switched off in its settings, the gate is the world map again")
  S.gate()
  check(S.panel == nil, "and the mod is silent at it")

  S = boot(nil, {town = 1, visited = {["norune-village"] = true}})
  S.tick(30)
  S.gate()
  S.emit("game.session.ended", {})
  check(S.owner.roads == nil and S.owner.passage == nil and S.panel == nil and S.closed == 1, "the game ends: both rules let go, the question taken down")
  S.emit("ui.choice_made", {id = "openworld.road", index = 1})
  check(#S.went == 0, "and a late answer goes nowhere")

  S = boot(nil, {town = 1, visited = {["norune-village"] = true}})
  S.tick(30)
  S.emit("runtime.unloaded", {})
  check(S.owner.roads == nil and S.owner.passage == nil, "the mod switched off: both rules let go")
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
