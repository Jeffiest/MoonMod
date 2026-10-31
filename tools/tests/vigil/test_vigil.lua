-- Plays mods/moonmod.vigil/main.lua against a small fake Chronicle adapter.
-- Usage, from the repository root:  lua tools/tests/vigil/test_vigil.lua   (Lua 5.4 or newer)
--
-- The fake refuses what the real adapter refuses (ports/chronicle/moonfactory-chronicle.patch,
-- chronicle_adapter.cpp: the tuning_set field checks, the moves_set move checks), so a wrong field or a value out of
-- range fails here the way it would in the game. See docs/modding/TESTING.md, "Keep the fake honest".
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."
local MOD_DIR = root .. "/mods/moonmod.vigil"

-- Setting defaults straight from the manifest (one setting object per line there).
local defaults = {}
for line in io.lines(MOD_DIR .. "/mod.json") do
  local id = line:match('"id":%s*"([%w_]+)"')
  local default = line:match('"default":%s*([^,}]+)')
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

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

local function file_exists(path) local f = io.open(path, "rb"); if f then f:close() return true end return false end
local function read_file(path) local f = assert(io.open(path, "rb")); local s = f:read("a"); f:close(); return s end

-- The fake game -------------------------------------------------------------------------------------------------
local CHARACTERS = {toan = true, xiao = true, goro = true, ruby = true, ungaga = true, osmond = true}
local MULTIPLIERS = {run_speed = true, attack_anim_speed = true, recoil_scale = true, gauge_refill = true, thirst_drain = true,
                     durability_wear = true, status_duration = true, reach_scale = true}
local AILMENTS = {freeze = true, stamina = true, poison = true, curse = true, goo = true}
local MOVE_FIELDS = {}
for _, k in ipairs({"id", "character", "trigger", "run_frames", "chain", "direction", "min_charge", "max_charge", "motion", "from", "to",
                    "speed", "lunge", "lunge_decay", "lunge_angle", "spin", "spin_from", "spin_to", "invincible", "gauge", "wear",
                    "cooldown", "hits", "cues", "animation", "cancel", "cancel_after"}) do MOVE_FIELDS[k] = true end
local SOUNDS = {swing = true, swing_heavy = true, voice = true, voice_2 = true, voice_3 = true, shout = true, shout_2 = true, action = true}

local function fail(code, msg) return nil, {code = code, message = msg} end
local function is_list(t) if type(t) ~= "table" then return false end local n = 0 for _ in pairs(t) do n = n + 1 end return n == #t and n > 0 end

local function new_game(opts)
  opts = opts or {}
  local S = {
    frame = 0, callbacks = {}, storage = copy(opts.storage or {}), settings = copy(defaults),
    session = opts.session or {kind = "story"},
    animations = {}, moves = nil, tuning = nil, player_formulas = {}, bindings = {}, held = {},
    toasts = {}, actions = {}, calls = {}, fail_ops = opts.fail_ops or {}, logs = {},
  }
  for k, v in pairs(opts.settings or {}) do S.settings[k] = v end
  local function count(op) S.calls[op] = (S.calls[op] or 0) + 1 end
  local function refused(op) if S.fail_ops[op] then return true end end

  S.game = {
    animations = {
      player_register = function(a)
        count("animations.player_register")
        if refused("animations.player_register") then return fail("unsupported", "no mod motions") end
        for k in pairs(a) do assert(k == "id" or k == "file", "player_register field " .. k) end
        assert(type(a.id) == "string" and #a.id >= 1 and #a.id <= 64, "player_register id")
        assert(type(a.file) == "string" and a.file:match("^resources/.+%.json$"), "player_register file under resources/")
        local path = MOD_DIR .. "/" .. a.file
        if not file_exists(path) then return fail("not_found", "no such file " .. a.file) end
        local text = read_file(path)
        if not text:find('"format":"moonmod-motion"', 1, true) then return fail("invalid_argument", a.file .. " is not a moonmod-motion") end
        local character = text:match('"character":"(%a+)"')
        S.animations[a.id] = {character = character, file = a.file}
        return {id = a.id, character = character}
      end,
    },
    player = {
      moves_set = function(a)
        count("player.moves_set")
        for k in pairs(a) do assert(k == "moves", "moves_set field " .. k) end
        assert(type(a.moves) == "table" and #a.moves >= 1 and #a.moves <= 160, "moves_set takes 1-160 moves")
        local seen = {}
        for _, m in ipairs(a.moves) do
          for k in pairs(m) do if not MOVE_FIELDS[k] then return fail("invalid_argument", "unknown move field " .. k) end end
          if type(m.id) ~= "string" or #m.id < 1 or #m.id > 40 then return fail("invalid_argument", "move id is 1-40 bytes") end
          if not CHARACTERS[m.character] then return fail("invalid_argument", m.id .. ": character") end
          local key = m.character .. "/" .. tostring(m.trigger)
          if seen[key] then return fail("invalid_argument", "two moves on " .. key) end
          seen[key] = true
          local evade = m.trigger == "dodge" or m.trigger == "dodge_back"
          if (m.cancel ~= nil or m.cancel_after ~= nil) and not evade then
            return fail("invalid_argument", m.id .. ": cancel and cancel_after are for evades")
          end
          if m.animation then
            local anim = S.animations[m.animation]
            if not anim then return fail("invalid_argument", m.id .. ": animation not registered " .. m.animation) end
            if anim.character ~= m.character then return fail("invalid_argument", m.id .. ": animation is another character's") end
          elseif math.type(m.motion) ~= "integer" then
            return fail("invalid_argument", m.id .. ": motion or animation")
          end
          local function within(field, lo, hi)
            local v = m[field]
            return v == nil or (type(v) == "number" and v >= lo and v <= hi)
          end
          if not (within("gauge", 0, 100) and within("wear", 0, 5) and within("cooldown", 0, 600)) then
            return fail("invalid_argument", m.id .. ": gauge is 0..100, wear 0..5 and cooldown 0..600 frames")
          end
          if not within("cancel_after", 0, 60) then return fail("invalid_argument", m.id .. ": cancel_after 0..60") end
          if not (within("speed", 0.2, 4) and within("lunge", 0, 6) and within("lunge_decay", 0.01, 2) and within("lunge_angle", -180, 180)) then
            return fail("invalid_argument", m.id .. ": speed or lunge out of range")
          end
          if m.invincible ~= nil and type(m.invincible) ~= "boolean" then return fail("invalid_argument", m.id .. ": invincible") end
          for _, c in ipairs(m.cues or {}) do
            if c.sound and not SOUNDS[c.sound] then return fail("invalid_argument", m.id .. ": cue sound " .. c.sound) end
          end
        end
        S.moves = copy(a.moves)
        return {count = #a.moves}
      end,
      moves_clear = function() count("player.moves_clear"); S.moves = nil; return {cleared = true} end,
      tuning_set = function(a)
        count("player.tuning_set")
        if refused("player.tuning_set") then return fail("unsupported", "no tuning") end
        for k, v in pairs(a) do
          if MULTIPLIERS[k] then
            if type(v) ~= "number" or v < 0.25 or v > 4 then return fail("invalid_argument", k .. " must be a number from 0.25 to 4") end
          elseif k == "map_reveal" or k == "monster_reveal" or k == "map_hidden" or k == "first_person" or k == "shots_pierce" or k == "dodge_hop" then
            if type(v) ~= "boolean" then return fail("invalid_argument", k .. " must be a boolean") end
          elseif k == "swap_delay" then
            if type(v) ~= "number" or v < 0 or v > 4 then return fail("invalid_argument", "swap_delay must be a number from 0 to 4") end
          elseif k == "dodge_power" then
            if type(v) ~= "number" or (v ~= 0 and (v < 0.25 or v > 4)) then return fail("invalid_argument", "dodge_power") end
          elseif k == "dodge_invincible_frames" then
            if math.type(v) ~= "integer" or v < 0 or v > 60 then return fail("invalid_argument", "dodge_invincible_frames") end
          elseif k == "status_immune" then
            -- an empty Lua table would reach the engine as {} (an object), which it refuses
            if not is_list(v) then return fail("invalid_argument", "status_immune must be a list of ailment names") end
            for _, name in ipairs(v) do if not AILMENTS[name] then return fail("invalid_argument", "status_immune names") end end
          else
            return fail("invalid_argument", "player.tuning_set received an unsupported field: " .. k)
          end
        end
        S.tuning = copy(a)
        return {owner = "moonmod.vigil", status = "set", tuning = copy(a), effective = copy(a)}
      end,
      tuning_clear = function() count("player.tuning_clear"); S.tuning = nil; return {status = "cleared"} end,
    },
    combat = {
      register_player_formula = function(a)
        count("combat.register_player_formula")
        for k in pairs(a) do
          assert(k == "id" or k == "operation" or k == "value" or k == "priority" or k == "weapon_id" or k == "character_id",
                 "register_player_formula field " .. k)
        end
        assert(type(a.id) == "string" and #a.id >= 1 and #a.id <= 64, "formula id")
        assert(a.operation == "multiply", "Vigil only multiplies")
        if type(a.value) ~= "number" or a.value < 0 or a.value > 100 then return fail("invalid_argument", "multiply 0..100") end
        S.player_formulas[a.id] = copy(a)
        return {id = a.id}
      end,
    },
    input = {
      bind = function(a)
        count("input.bind")
        for k in pairs(a) do assert(k == "id" or k == "keys" or k == "context", "bind field " .. k) end
        assert(type(a.keys) == "table" and #a.keys >= 1 and #a.keys <= 8, "bind takes 1-8 keys")
        for _, key in ipairs(a.keys) do
          assert(type(key) == "string" and key ~= "Escape", "bind key")
          if key:match("^Gamepad:") then assert(key:match("^Gamepad:%l+"), "gamepad button name " .. key) end
        end
        if S.bindings[a.id] then return fail("already_exists", "action " .. a.id .. " is bound") end
        S.bindings[a.id] = copy(a.keys)
        return {id = "moonmod.vigil." .. a.id}
      end,
      unbind = function(a)
        count("input.unbind")
        local had = S.bindings[a.id] ~= nil
        S.bindings[a.id] = nil
        return {removed = had}
      end,
      state = function(a)
        if not S.bindings[a.id] then return fail("not_found", "no action " .. tostring(a.id)) end
        return {down = S.held[a.id] == true}
      end,
    },
    session = {get = function() return copy(S.session) end},
    ui = {
      notify = function(a)
        assert(type(a.message) == "string" and #a.message <= 200, "notify message is up to 200 bytes")
        S.toasts[#S.toasts + 1] = a.message
        return {queued = true}
      end,
      register = function(a)
        assert(type(a.id) == "string" and type(a.label) == "string" and #a.label <= 48, "ui.register label")
        assert(a.description == nil or #a.description <= 120, "ui.register description")
        S.actions[a.id] = copy(a)
        return {id = a.id}
      end,
    },
  }
  S.moonmod = {
    on = function(name, fn) S.callbacks[name] = S.callbacks[name] or {}; table.insert(S.callbacks[name], fn) end,
    log = function(level, msg) S.logs[#S.logs + 1] = level .. ": " .. msg end,
    settings = {get = function(id) return S.settings[id] end},
    storage = {get = function(k) return S.storage[k] end, set = function(k, v) S.storage[k] = v end},
  }
  function S.emit(name, payload) for _, fn in ipairs(S.callbacks[name] or {}) do fn(payload) end end
  function S.tick(n) for _ = 1, n or 1 do S.frame = S.frame + 1; S.emit("game.tick", {frame = S.frame}) end end
  function S.set(id, value) S.settings[id] = value; S.emit("settings.changed", {id = id}) end
  function S.guard(on) S.held.guard = on end
  function S.load()
    local env = setmetatable({game = S.game, moonmod = S.moonmod}, {__index = _G})
    local chunk = assert(loadfile(MOD_DIR .. "/main.lua", "t", env))
    S.mod = chunk()
    if S.mod and S.mod.on_load then S.mod.on_load() end
    return S
  end
  return S
end

local function moves_by(S)
  local t = {}
  for _, m in ipairs(S.moves or {}) do t[m.character .. "/" .. m.trigger] = m end
  return t
end

-- 1. Story game: the rules go on ---------------------------------------------------------------------------------
print("1. Loading in the story game")
do
  local S = new_game().load()
  check(S.moves and #S.moves == 12, "twelve evades: a dodge and a dodge_back for each of the six", S.moves and #S.moves)
  local by = moves_by(S)
  local all_ok = true
  for c in pairs(CHARACTERS) do
    for _, trigger in ipairs({"dodge", "dodge_back"}) do
      local m = by[c .. "/" .. trigger]
      if not (m and m.invincible == true and m.gauge == 35 and m.cooldown == 30 and m.cancel == true and m.cancel_after == 6 and m.wear == 0
              and m.hits == nil and S.animations[m.animation] and S.animations[m.animation].character == c) then
        all_ok = false
      end
    end
  end
  check(all_ok, "each is untouchable, costs 35 gauge, cools down 30 frames, commits 6 frames, never attacks, uses its own motion")
  check(by["toan/dodge_back"].lunge_angle == 180 and by["toan/dodge"].lunge_angle == nil, "the backstep carries him back, the roll the way the stick points")
  check(by["xiao/dodge"].animation == "xiao_tumble" and by["xiao/dodge_back"].animation == "xiao_hop_shot", "Xiao tumbles and hops back")
  check(S.player_formulas["enemy-damage"] and S.player_formulas["enemy-damage"].value == 2.5, "enemies hit x2.5")
  local t = S.tuning or {}
  check(t.recoil_scale == 0.4 and t.gauge_refill == 1 and t.swap_delay == 2, "recoil x0.4, gauge refill x1, switching x2", t.recoil_scale)
  check(t.status_immune and t.status_immune[1] == "stamina" and #t.status_immune == 1, "no Stamina power-ups from enemies")
  check(t.map_hidden == nil and t.dodge_power == nil, "minimap kept, no shove dodge")
  check(S.bindings.guard and S.bindings.guard[1] == "Gamepad:rightshoulder" and #S.bindings.guard == 1, "the guard is read from R1")
  check(S.actions.check ~= nil, "a Check button in the Mod Manager")
  check(#S.toasts == 0, "no tips before a dungeon")
end

-- 2. Guarding slows the gauge's recovery ------------------------------------------------------------------------
print("2. Guarding")
do
  local S = new_game().load()
  local sets = S.calls["player.tuning_set"]
  S.tick(10)
  check(S.calls["player.tuning_set"] == sets, "nothing is re-sent while nothing changes")
  S.guard(true); S.tick(1)
  check(S.tuning.gauge_refill == 0.25, "holding the guard: the gauge recovers at a quarter", S.tuning.gauge_refill)
  check(S.tuning.recoil_scale == 0.4 and S.tuning.status_immune, "the rest of the set stays (each call replaces the owner's whole set)")
  S.tick(30)
  check(S.calls["player.tuning_set"] == sets + 1, "once on the press, not every frame")
  S.guard(false); S.tick(1)
  check(S.tuning.gauge_refill == 1 and S.calls["player.tuning_set"] == sets + 2, "letting go puts it back")
  S.set("gauge_refill", 50); S.guard(true); S.tick(1)
  check(S.tuning.gauge_refill == 0.25, "never below the engine's floor of 0.25", S.tuning.gauge_refill)
end

-- 3. Settings ----------------------------------------------------------------------------------------------------
print("3. Settings")
do
  local S = new_game().load()
  S.set("evade_cost", 40); S.set("evade_cooldown", 12); S.set("evade_commit", 0)
  local m = moves_by(S)["goro/dodge"]
  check(m.gauge == 40 and m.cooldown == 12 and m.cancel_after == 0, "evade cost, cooldown and commit follow the settings")
  S.set("enemy_damage", 100)
  check(S.player_formulas["enemy-damage"].value == 1, "enemy damage back to normal")
  S.set("no_minimap", true)
  check(S.tuning.map_hidden == true, "no minimap")
  S.set("no_power_up", false)
  check(S.tuning.status_immune == nil, "Stamina immunity off sends no field (an empty list would reach the engine as an object)")
  S.set("guard_key", "E")
  check(S.bindings.guard and S.bindings.guard[2] == "E", "a keyboard guard key is bound too")
  S.guard(true); S.tick(1)
  check(S.tuning.gauge_refill == 0.25, "and read after rebinding")
  S.set("evades", false)
  check(S.moves == nil and S.tuning.dodge_power == nil, "evades off: no moves and no shove dodge")
  local first = new_game({settings = {recoil = 25, swap_delay = 0}}).load()
  check(first.tuning.recoil_scale == 0.25 and first.tuning.swap_delay == 0, "the setting extremes are values the engine accepts")
end

-- 4. Missing motions fall back to the engine's dodge ------------------------------------------------------------
print("4. No motions")
do
  local S = new_game({fail_ops = {["animations.player_register"] = true}}).load()
  check(S.moves == nil, "no moves without their motions")
  check(S.tuning.dodge_power == 1 and S.tuning.dodge_invincible_frames == 14, "L2 still dodges, untouchable for 14 frames")
  local warned = false
  for _, l in ipairs(S.logs) do if l:find("not registered", 1, true) then warned = true end end
  check(warned, "the log says why")
end

-- 5. Sitting out another mod's game mode ------------------------------------------------------------------------
print("5. Dark Genie's Gauntlet")
do
  local S = new_game().load()
  S.session = {kind = "sandbox", owner = "moonmod.roguelike", mode = "gauntlet"}
  S.emit("game.session.started", {owner = "moonmod.roguelike"})
  check(S.moves == nil and S.tuning == nil, "moves and tuning handed back for the run")
  check(S.player_formulas["enemy-damage"].value == 1, "enemy damage back to x1 (a formula can't be removed)")
  local sets = S.calls["player.tuning_set"]
  S.guard(true); S.tick(20)
  check(S.calls["player.tuning_set"] == sets and S.tuning == nil, "the guard is ignored during the run")
  S.set("evade_cost", 50)
  check(S.moves == nil, "a settings change during the run changes nothing")
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  check(#S.toasts == 0, "no tips during the run")
  S.session = {kind = "story"}
  S.emit("game.session.ended", {owner = "moonmod.roguelike", reason = "ended"})
  check(S.moves and #S.moves == 12 and moves_by(S)["toan/dodge"].gauge == 50, "back afterwards, with the new setting")
  check(S.tuning and S.tuning.gauge_refill == 0.25, "and the guard held across the switch counts")
  check(S.player_formulas["enemy-damage"].value == 2.5, "enemies hit hard again")

  local mid = new_game({session = {kind = "sandbox", owner = "moonmod.roguelike"}}).load()
  check(mid.moves == nil and mid.tuning == nil and mid.player_formulas["enemy-damage"].value == 1, "loaded mid-run: stands down from the start")
  check(mid.calls["player.moves_set"] == nil, "and never claimed the L2 triggers the Gauntlet holds")
end

-- 6. Tips ----------------------------------------------------------------------------------------------------------
print("6. Tips")
do
  local S = new_game().load()
  S.emit("game.world.location_changed", {context = "town"})
  check(#S.toasts == 0, "not in town")
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  check(#S.toasts == 3 and S.storage.told == true, "three tips on the first dungeon", #S.toasts)
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 1})
  check(#S.toasts == 3, "once")
  local again = new_game({storage = {told = true}}).load()
  again.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  check(#again.toasts == 0, "not after a restart either")
  local quiet = new_game({settings = {tips = false}}).load()
  quiet.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  check(#quiet.toasts == 0, "or with tips off")
  S.emit("ui.action", {id = "check"})
  check(S.toasts[#S.toasts]:find("evades on", 1, true) and S.toasts[#S.toasts]:find("x2.50", 1, true), "Check reports what is set", S.toasts[#S.toasts])
end

-- 7. The shipped motions -----------------------------------------------------------------------------------------
print("7. Motion files")
do
  local ok, bad = true, nil
  local names = {"toan_roll", "toan_backstep", "xiao_tumble", "xiao_hop_shot", "goro_roll", "goro_backstep", "ungaga_roll",
                 "ungaga_backstep", "ruby_tumble", "ruby_hop_shot", "osmond_tumble", "osmond_hop_shot"}
  for _, n in ipairs(names) do
    local path = MOD_DIR .. "/resources/anims/" .. n .. ".json"
    if not file_exists(path) then ok, bad = false, n .. " missing"
    else
      local text = read_file(path)
      local length = tonumber(text:match('"length":(%d+)'))
      if not (text:find('"format":"moonmod-motion","version":1', 1, true) and text:match('"character":"(%a+)"') == n:match("^(%a+)_")
              and length and length >= 1 and length <= 600 and #text <= 4 * 1024 * 1024) then
        ok, bad = false, n
      end
    end
  end
  check(ok, "twelve moonmod-motion v1 files, each its character's and within the 4 MiB limit", bad)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
