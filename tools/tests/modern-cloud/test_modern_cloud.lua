-- Plays mods/moonmod.modern-cloud/main.lua against a small fake Chronicle adapter.
-- Usage, from the repository root:  lua tools/tests/modern-cloud/test_modern_cloud.lua   (Lua 5.4 or newer)
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."
local MOD_DIR = root .. "/mods/moonmod.modern-cloud"

local defaults = {}
for line in io.lines(MOD_DIR .. "/mod.json") do
  local id = line:match('"id":%s*"([%w_]+)"')
  local default = line:match('"default":%s*([^,}]+)')
  local name = line:match('"name":%s*"([^"]*)"')
  assert(not (id and name) or #name <= 96, "setting " .. tostring(id) .. ": its name is over 96 bytes")
  if id and default then
    default = default:gsub("%s+$", "")
    if default == "true" then defaults[id] = true
    elseif default == "false" then defaults[id] = false
    elseif default:match('^"') then defaults[id] = default:match('^"(.*)"$')
    else defaults[id] = math.tointeger(tonumber(default)) or tonumber(default) end
  end
end

local passed, failed = 0, 0
local function check(cond, label, extra)
  if cond then passed = passed + 1; print("  ok   " .. label)
  else failed = failed + 1; print("  FAIL " .. label .. (extra ~= nil and ("  [" .. tostring(extra) .. "]") or "")) end
end

local TUNING_RANGE = {thirst_drain = {0.25, 4}, durability_wear = {0.25, 4}, swap_delay = {0, 4}, run_speed = {0.25, 4}}
local TUNING_BOOL = {map_reveal = true, monster_reveal = true}

local function boot(overrides, session_kind)
  local S = {settings = {}, handlers = {}, notices = {}, tuning = nil, bound = {}, pressed = {},
             context = "dungeon", water = 50, max_water = 100, powders = 1, quick_used = {}, session = session_kind or "story",
             weapon = {id = "chronicle:weapon:258", item_no = 258, slot = 0, durability = 40, durability_max = 40}}
  for k, v in pairs(defaults) do S.settings[k] = v end
  for k, v in pairs(overrides or {}) do S.settings[k] = v end
  local function fail(code, msg) return nil, {code = code, message = msg} end
  _G.moonmod = {
    settings = {get = function(id) return S.settings[id] end},
    on = function(name, fn) S.handlers[name] = S.handlers[name] or {}; table.insert(S.handlers[name], fn) end,
    log = function() end,
  }
  _G.game = {
    world = {get = function() return {context = S.context} end},
    session = {get = function() return {kind = S.session} end},
    ui = {notify = function(a) assert(type(a.message) == "string" and #a.message <= 200, "notify message"); table.insert(S.notices, a.message); return true end,
          register = function(a) assert(a.id and a.label) return true end},
    input = {
      bind = function(a) assert(type(a.id) == "string" and type(a.keys) == "table" and #a.keys >= 1); S.bound[a.id] = a.keys; return {id = a.id} end,
      unbind = function(a) S.bound[a.id] = nil; return {removed = true} end,
      consume = function(a) local p = S.pressed[a.id] and S.bound[a.id] ~= nil; S.pressed[a.id] = nil; return {pressed = p or false} end,
    },
    player = {
      tuning_set = function(t)
        for k, v in pairs(t) do
          if TUNING_RANGE[k] then
            if type(v) ~= "number" or v < TUNING_RANGE[k][1] or v > TUNING_RANGE[k][2] then return fail("invalid_argument", k) end
          elseif TUNING_BOOL[k] then
            if type(v) ~= "boolean" then return fail("invalid_argument", k) end
          else return fail("invalid_argument", "unknown field " .. k) end
        end
        S.tuning = t; return {tuning = t}
      end,
      tuning_clear = function() S.tuning = nil; return {} end,
      get = function() return {character = "toan", water = S.water, max_water = S.max_water, weapon = S.weapon} end,
      set = function(a)
        local n = 0 for k in pairs(a) do if k ~= "character" then n = n + 1 end end
        assert(n == 1, "player.set takes one field")
        if a.water then S.water = a.water end
        return {}
      end,
    },
    weapons = {durability_set = function(a)
      assert(a.id == S.weapon.id and a.character == "toan" and a.slot == S.weapon.slot, "durability_set target")
      if a.durability < 0 or a.durability > S.weapon.durability_max then return fail("invalid_argument", "durability") end
      S.weapon.durability = a.durability; return {}
    end},
    items = {
      remove = function(a)
        assert(a.id == "chronicle:item:177" and a.count == 1, "remove what")
        if S.powders <= 0 then return {removed = 0, remaining = 0} end
        S.powders = S.powders - 1; return {removed = 1, remaining = S.powders}
      end,
      quick_slot_use = function(a)
        if S.context ~= "dungeon" then return fail("failed", "not in a dungeon") end
        table.insert(S.quick_used, a.slot); return {slot = a.slot}
      end,
      quick_slots = function() return {{slot = 1, id = "x"}, {slot = 2, id = "y"}, {slot = 3}} end,
    },
  }
  local chunk = assert(loadfile(MOD_DIR .. "/main.lua"))
  chunk()
  function S.emit(name, ...) for _, fn in ipairs(S.handlers[name] or {}) do fn(...) end end
  function S.tick(n) for _ = 1, n or 1 do S.emit("game.tick") end end
  return S
end

print("Tuning")
local S = boot()
check(S.tuning and math.abs(S.tuning.thirst_drain - 0.5) < 1e-9 and math.abs(S.tuning.durability_wear - 0.75) < 1e-9, "defaults: half thirst, three quarters wear")
check(S.tuning.swap_delay == 0.5 and S.tuning.run_speed == 1 and S.tuning.map_reveal == false, "defaults: half switch wait, normal walk, no reveal")
S.settings.map_reveal = true; S.settings.run_speed = 120; S.emit("settings.changed")
check(S.tuning.map_reveal == true and math.abs(S.tuning.run_speed - 1.2) < 1e-9, "a settings change re-applies the tuning")

print("Thirst off")
S = boot({thirst = 0})
check(S.tuning.thirst_drain == 0.25, "thirst 0 asks for the slowest drain the engine allows")
S.water = 10; S.tick(10)
check(S.water == 100, "and keeps the water gauge full in a dungeon")
S = boot({thirst = 50}); S.water = 10; S.tick(20)
check(S.water == 10, "thirst above 0 leaves the gauge alone")

print("Weapon guard")
S = boot()
S.weapon.durability = 9; S.tick(10)
check(#S.notices == 1 and S.notices[1]:find("wearing down"), "below 25% warns once", S.notices[1])
S.tick(30)
check(#S.notices == 1, "and only once")
S.weapon.durability = 4; S.tick(10)
check(#S.notices == 2 and S.notices[2]:find("badly worn"), "below half the warning warns again")
S.weapon.durability = 3; S.tick(10)
check(S.weapon.durability == 40 and S.powders == 0 and S.notices[3]:find("Repair Powder"), "at the edge a Repair Powder mends it")
S.weapon.durability = 2; S.tick(10)
check(S.weapon.durability == 2 and S.notices[4]:find("no Repair Powder"), "with none left, a loud warning instead")
S.tick(30)
check(#S.notices == 4, "the loud warning is not repeated")

S = boot({weapon_guard = "Never break"})
S.weapon.durability = 2; S.tick(10)
check(S.weapon.durability == 4 and S.powders == 1, "Never break holds durability above the edge without using powder")
S.weapon.durability = 3; S.tick(10)
check(S.weapon.durability == 4 and #S.notices == 1, "every time, with one notice")

S = boot({weapon_guard = "Off"})
S.weapon.durability = 1; S.tick(30)
check(S.weapon.durability == 1 and #S.notices == 0, "Off does nothing")

S = boot({weapon_guard = "Warn"})
S.weapon.durability = 2; S.tick(10)
check(S.weapon.durability == 2 and S.powders == 1 and S.notices[1]:find("about to break"), "Warn only warns")

S = boot(); S.context = "georama"; S.weapon.durability = 1; S.tick(30)
check(S.weapon.durability == 1 and #S.notices == 0, "nothing happens in town")

print("Quick keys")
S = boot()
check(S.bound.quick_1 and S.bound.quick_1[1] == "1" and S.bound.quick_3[1] == "3", "keys 1-3 bound")
S.pressed.quick_2 = true; S.tick()
check(S.quick_used[1] == 2, "2 uses quick slot 2")
S.context = "georama"; S.pressed.quick_1 = true; S.tick()
check(#S.quick_used == 1, "not in town")
S.settings.quick_keys = false; S.emit("settings.changed")
check(S.bound.quick_1 == nil, "turning the setting off unbinds them")

print("Sandbox sessions")
S = boot(nil, "sandbox")
check(S.tuning == nil, "a Gauntlet run starts with no Modern Cloud tuning")
S.weapon.durability = 1; S.tick(30)
check(S.weapon.durability == 1 and #S.notices == 0, "and no weapon guard")
S.session = "story"; S.emit("game.session.ended")
check(S.tuning ~= nil, "the tuning comes back when the run ends")
S = boot(); S.emit("game.session.started")
check(S.tuning == nil, "a run starting takes it away")

print("Check action")
S = boot(); S.emit("ui.action", {id = "check"})
check(S.notices[1] and S.notices[1]:find("guard: Repair Powder"), "Check reports the settings", S.notices[1])

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
