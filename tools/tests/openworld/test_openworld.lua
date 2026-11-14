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
-- owner = {passage = id, roads = id} (rules another mod already holds), flags = {story flag = true},
-- limits = {["dungeon:floor"] = limit zone}, zones = {owner = id, yield = bool} (another mod's zones standing)
local function boot(overrides, opts)
  opts = opts or {}
  local S = {settings = {}, handlers = {}, notices = {}, kind = opts.kind or "story", town = opts.town, visited = opts.visited or {},
             owner = {passage = opts.owner and opts.owner.passage, roads = opts.owner and opts.owner.roads},
             panel = nil, went = {}, resets = 0, closed = 0, transition_fails = false,
             flags = opts.flags or {}, limits = opts.limits or {}, zones = opts.zones, arrival = nil, walks = nil}
  if opts.town == nil and not opts.floor then S.town = 0 end
  for k, v in pairs(defaults) do S.settings[k] = v end
  for k, v in pairs(overrides or {}) do S.settings[k] = v end
  local function one_owner(key, said)
    return function(a)
      assert(type(a) == "table" and type(a.enabled) == "boolean")
      for k in pairs(a) do assert(k == "enabled" or (key == "passage" and k == "walks"), "unknown field " .. k) end
      assert(a.walks == nil or (a.enabled and type(a.walks) == "boolean"))
      if S.owner[key] and S.owner[key] ~= ME then return fail("failed", said) end
      if key == "passage" then S.walks = a.enabled and a.walks ~= false end
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
      story_flag_get = function(a) return {id = a.id, value = S.flags[a.id] == true} end,
      transition = function(a)
        if S.transition_fails then return fail("failed", "the way is shut") end
        S.went[#S.went + 1] = a.id; return {}
      end,
    },
    dungeons = {
      set_quick_passage = one_owner("passage", "another mod already set the passage"),
      -- the engine's rule: one mod's zones stand; a request made with yield = true gives way to any made without
      set_zones = function(a)
        assert(type(a) == "table")
        local others = S.zones ~= nil and S.zones.owner ~= ME
        local yields = a.yield == true
        if a.zones == nil then
          for k in pairs(a) do assert(k == "yield") end
          if others and not S.zones.yield and not yields then return fail("failed", "another mod already lays floors out in zones") end
          if others or (yields and S.zones and not S.zones.yield) then return {} end
          S.zones = nil
          return {}
        end
        if others and (yields or not S.zones.yield) then return fail("failed", "another mod already lays floors out in zones") end
        assert(#a.zones >= 2 and #a.zones <= 30)
        for _, z in ipairs(a.zones) do assert(z.rooms >= 2 and z.rooms <= 12 and math.type(z.source_floor) == "integer") end
        for _, g in ipairs(a.open or {}) do assert(g >= 1 and g < #a.zones) end
        if others then S.arrival = nil end
        S.zones = {owner = ME, yield = yields, request = a}
        return {}
      end,
      set_arrival = function(a)
        assert(S.zones and a.zone >= 0 and a.zone < #S.zones.request.zones and a.teleport == true)
        S.arrival = a; return {}
      end,
      floor_rules_get = function(a)
        assert(a.dungeon_id >= 0 and a.dungeon_id <= 5 and a.floor_id >= 0 and a.floor_id <= 24)
        return {limit_zone = S.limits[a.dungeon_id .. ":" .. a.floor_id] or -1}
      end,
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
  -- a floor is about to be built; says what stands after: "first-last>exit" with "+open gates" and "@arrival zone"
  function S.build(dungeon, floor, back)
    S.arrival = nil
    S.emit("game.dungeon.generating", {dungeon_id = dungeon, floor_id = floor, back_floor = back == true, prebuild = false})
    if not S.zones then return "none" end
    if S.zones.owner ~= ME then return S.zones.owner end
    local r = S.zones.request
    local said = r.zones[1].source_floor .. "-" .. r.zones[#r.zones].source_floor .. ">" .. tostring(r.exit_floor)
    for i, z in ipairs(r.zones) do assert(z.source_floor == r.zones[1].source_floor + i - 1 and z.rooms == 5) end
    if r.open then said = said .. "+" .. table.concat(r.open, ",") end
    if S.arrival then said = said .. "@" .. S.arrival.zone end
    return said
  end
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

print("Floors, walked")
do
  local seen = {[103] = true, [100] = true, [106] = true, [104] = true, [101] = true, [105] = true, [130] = true, [131] = true}
  local S = boot(nil, {floor = true, flags = seen})
  check(S.walks == false, "the stairs that are left have no walk out and no walk in")
  local said = S.build(0, 0)
  check(said == "0-2>3", "Divine Beast Cave: floors 1 to 3 are one map, its last gate to floor 4", said)
  check(S.zones.yield == true, "asked for as a request that gives way")
  said = S.build(0, 1)
  check(said == "0-2>3+1@1", "come in at floor 2: the gate behind stands open, the party put down on floor 2", said)
  said = S.build(0, 2)
  check(said == "0-2>3+1,2@2", "and at floor 3", said)
  said = S.build(0, 3)
  check(said == "none", "a story floor's own map stays a map of its own", said)
  said = S.build(0, 4)
  check(said == "4-5>6", "floors 5 and 6, then the floor with a rule of its own", said)
  said = S.build(0, 6)
  check(said == "none", "which is alone", said)
  said = S.build(0, 12)
  check(said == "11-13>14+1@1", "floors 12 to 14 before the boss", said)
  said = S.build(0, 14)
  check(said == "none", "the boss's floor is alone", said)

  said = S.build(1, 5)
  check(said == "4-7>8+1@1", "Wise Owl Forest: floors 5 to 8", said)
  said = S.build(1, 8)
  check(said == "none", "its story floor alone", said)
  said = S.build(1, 9)
  check(said == "9-10>11", "new walls start a new map", said)
  said = S.build(2, 13)
  check(said == "12-15>16+1@1", "Shipwreck: floors 13 to 16", said)
  said = S.build(3, 0)
  check(said == "0-3>4", "Sun and Moon Temple: floors 1 to 4, its scenes seen", said)
  said = S.build(4, 8)
  check(said == "8-9>10", "Moon Sea: floors 9 and 10", said)
  said = S.build(5, 7)
  check(said == "6-11>12+1@1", "Gallery of Time: six floors to a set of walls", said)
  said = S.build(5, 19)
  check(said == "none", "its last floors alone", said)
  said = S.build(6, 0)
  check(said == "0-19>20", "Demon Shaft: twenty floors on one map", said)
  said = S.build(6, 97)
  check(said == "80-97>98+1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17@17", "its last stretch, come in at the end", said)
  said = S.build(6, 99)
  check(said == "none", "and its last floor alone", said)
  said = S.build(7, 0)
  check(said == "none", "a dungeon the mod does not know is left as it is", said)

  -- a back floor is built as the game builds it; what stands is not touched
  S.build(1, 5)
  said = S.build(1, 5, true)
  check(said == "4-7>8+1", "a back floor asks for nothing", said)

  -- walking through a gate
  S.build(0, 0)
  S.emit("game.dungeon.zone_entered", {zone = 0, previous = -1, zones = 3, floor_id = 0, frame = 1})
  check(#S.notices == 0, "arriving says nothing")
  S.emit("game.dungeon.zone_entered", {zone = 1, previous = 0, zones = 3, floor_id = 1, frame = 2})
  check(S.notices[1] == "Floor 2", "through a gate: the floor is named", S.notices[1])
  S.build(0, 3)
  S.emit("game.dungeon.zone_entered", {zone = 1, previous = 0, zones = 3, floor_id = 1, frame = 3})
  check(#S.notices == 1, "on a floor alone nothing is said")
end

print("Floors, where the game keeps its own start")
do
  -- a new game: no scene seen yet
  local S = boot(nil, {floor = true})
  local said = S.build(0, 0)
  check(said == "none", "a floor that opens with a story scene not seen yet is alone", said)
  S.flags[103] = true
  said = S.build(0, 0)
  check(said == "none", "and so is the floor before one", said)
  S.flags[100] = true
  said = S.build(0, 0)
  check(said == "0-1>2", "each scene seen joins its floor on", said)
  S.flags[106] = true
  said = S.build(0, 0)
  check(said == "0-2>3", "until the stretch is whole", said)

  -- the Temple's scenes open floors 4 and 7
  S = boot(nil, {floor = true})
  said = S.build(3, 0)
  check(said == "0-2>3", "Sun and Moon Temple: the floor with a scene to come ends the map", said)
  said = S.build(3, 5)
  check(said == "none", "floor 6 alone between a story floor and a scene", said)

  -- a floor the save limits (one character, no healing...) starts as the game starts it
  S = boot(nil, {floor = true, limits = {["1:5"] = 2}})
  said = S.build(1, 4)
  check(said == "none", "a floor with a limit on it is alone, and so is the one cut off before it", said)
  said = S.build(1, 6)
  check(said == "6-7>8", "the floors after it are joined", said)
end

print("Floors, shared and switched off")
do
  local seen = {[103] = true, [100] = true, [106] = true}
  -- another mod lays floors out its own way (Vigil, on a Vigil World save)
  local S = boot(nil, {floor = true, flags = seen, zones = {owner = "moonmod.vigil", yield = false}})
  local said = S.build(0, 0)
  check(said == "moonmod.vigil", "another mod's zones stand", said)
  S.emit("game.dungeon.zone_entered", {zone = 1, previous = 0, zones = 3, floor_id = 1, frame = 2})
  check(#S.notices == 0 and S.arrival == nil, "and the mod says and places nothing on its map")
  said = S.build(0, 3)
  check(said == "moonmod.vigil", "nor are they let go for it", said)
  S.emit("runtime.unloaded", {})
  check(S.zones and S.zones.owner == "moonmod.vigil", "not even when the mod is switched off")

  S = boot({floors = false}, {floor = true, flags = seen})
  check(S.walks == true, "floors off: the stairs walk out and in as before")
  said = S.build(0, 0)
  check(said == "none", "and each floor is a map of its own", said)

  S = boot(nil, {floor = true, flags = seen})
  S.build(0, 0)
  S.settings.floors = false
  S.emit("settings.changed", {id = "floors", value = false})
  check(S.walks == true, "switched off in play: the walks are back at once")
  said = S.build(0, 1)
  check(said == "none", "and the next floor built is alone", said)

  S = boot(nil, {floor = true, flags = seen, kind = "sandbox"})
  said = S.build(0, 0)
  check(said == "none", "nothing is asked in another mod's game mode", said)

  S = boot(nil, {floor = true, flags = seen})
  S.build(0, 0)
  S.emit("game.session.ended", {})
  check(S.zones == nil, "the game ends: the zones are let go")
  S = boot(nil, {floor = true, flags = seen})
  S.build(0, 0)
  S.emit("runtime.unloaded", {})
  check(S.zones == nil, "the mod switched off: the zones are let go")
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
