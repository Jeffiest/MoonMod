-- Plays mods/moonmod.vigil/main.lua against a small fake Chronicle adapter.
-- Usage, from the repository root:  lua tools/tests/vigil/test_vigil.lua   (Lua 5.4 or newer)
--
-- The fake refuses what the real adapter refuses (ports/chronicle/moonfactory-chronicle.patch,
-- chronicle_adapter.cpp: the tuning_set field checks, the moves_set move checks), so a wrong field or a value out of
-- range fails here the way it would in the game. See docs/modding/TESTING.md, "Keep the fake honest".
math.randomseed(7) -- the brain rolls dice (feints, holds, which way to step): the same throws every run
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."
local MOD_DIR = root .. "/mods/moonmod.vigil"

-- Setting defaults straight from the manifest (one setting object per line there).
local defaults = {}
for line in io.lines(MOD_DIR .. "/mod.json") do
  local id = line:match('"id":%s*"([%w_]+)"')
  local default = line:match('"default":%s*([^,}]+)')
  -- The manifest loader turns the whole mod away for a setting name over 96 bytes.
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
                    "cooldown", "hits", "cues", "animation", "cancel", "cancel_after", "variants", "blend_in", "camera", "critical", "reach", "gap", "arc", "hold", "pairs", "weapons", "min_level"}) do MOVE_FIELDS[k] = true end
local SOUNDS = {swing = true, swing_heavy = true, voice = true, voice_2 = true, voice_3 = true, shout = true, shout_2 = true, action = true}

local function fail(code, msg) return nil, {code = code, message = msg} end
local function is_list(t) if type(t) ~= "table" then return false end local n = 0 for _ in pairs(t) do n = n + 1 end return n == #t and n > 0 end

-- The marks of the open map Cross can take, by index.
local function picks(S)
  local out = {}
  for i, m in ipairs(S.map and S.map.marks or {}) do if m.pick then out[#out + 1] = i end end
  return out
end

local function new_game(opts)
  opts = opts or {}
  local S = {
    frame = 0, callbacks = {}, storage = copy(opts.storage or {}), settings = copy(defaults),
    session = opts.session or {kind = "story"},
    animations = {}, moves = nil, tuning = nil, player_formulas = {}, bindings = {}, held = {},
    toasts = {}, actions = {}, calls = {}, fail_ops = opts.fail_ops or {}, logs = {},
    save_data = {}, slot = opts.slot, gear = {}, active = "toan",
    natives = {}, monster_at = {}, player_at = {0, 0, 0}, monster_motions = {}, models_loaded = false,
    floor = {{entity_id = "m1", native_model_id = 3}, {entity_id = "m2", native_model_id = 52}, {entity_id = "m3", native_model_id = 3},
             {entity_id = "m4", native_model_id = 1}, {entity_id = "m5", native_model_id = 3},
             {entity_id = "m6", native_model_id = 3}, {entity_id = "m7", native_model_id = 3},
             {entity_id = "m8", native_model_id = 4}, {entity_id = "m9", native_model_id = 0},
             {entity_id = "m10", native_model_id = 44}, {entity_id = "m11", native_model_id = 41},
             {entity_id = "m12", native_model_id = 24}},
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
      -- As the adapter: the file's character must be the model's file, and the motions get numbers only once a floor
      -- loads the model (S.models_loaded here), counted from 100 with their first frames 1000 apart.
      monster_register = function(a)
        count("animations.monster_register")
        for k in pairs(a) do assert(k == "id" or k == "file" or k == "model" or k == "hits", "monster_register field " .. k) end
        local stem = ({[0] = "e01a", [1] = "e03a", [3] = "e06a", [4] = "e07a", [55] = "e63a", [78] = "c12a", [79] = "c14a", [80] = "c13a", [81] = "c15a", [82] = "c15b", [83] = "c16a", [84] = "c17a", [106] = "c23a"})[a.model]
        assert(stem, "monster_register model")
        local path = MOD_DIR .. "/" .. a.file
        if not file_exists(path) then return fail("not_found", "no such file " .. a.file) end
        local character = read_file(path):match('"character":"(%w+)"')
        if character ~= stem then return fail("invalid_argument", "character names the model's file, " .. stem) end
        assert(a.hits == nil or #a.hits <= 4, "up to 4 hits")
        for _, h in ipairs(a.hits or {}) do
          for k in pairs(h) do assert(k == "bone" or k == "radius" or k == "from" or k == "to" or k == "damage", "hit field " .. k) end
          assert(type(h.bone) == "string" and h.from >= 0 and h.to > h.from and h.damage > 0 and h.damage <= 10, "hit values")
        end
        S.monster_motions[#S.monster_motions + 1] = {id = a.id, model = a.model, length = tonumber(read_file(path):match('"length":(%d+)'))}
        return {id = a.id}
      end,
      monster_list = function()
        local out = {}
        for i, m in ipairs(S.monster_motions) do
          out[i] = {id = m.id, model = m.model, length = m.length,
                    motion = S.models_loaded and 100 + i or nil, start = S.models_loaded and 1000 * i or nil}
        end
        return {motions = out}
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
          -- One move per character, trigger, chain and direction (the adapter's own slot: SetPlayerMoves).
          local key = m.character .. "/" .. tostring(m.trigger) .. "/" .. tostring(m.chain) .. "/" .. tostring(m.direction) .. "/" .. tostring(m.critical)
          if seen[key] and m.trigger ~= "played" and m.trigger ~= "art" then return fail("invalid_argument", "two moves on " .. key) end
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
          if m.blend_in ~= nil and (math.type(m.blend_in) ~= "integer" or m.blend_in < 1 or m.blend_in > 30) then
            return fail("invalid_argument", m.id .. ": blend_in is 1..30 frames")
          end
          if m.camera ~= nil and (math.type(m.camera) ~= "integer" or m.camera < 1 or m.camera > 14) then
            return fail("invalid_argument", m.id .. ": camera is 1..14 steps")
          end
          if m.direction ~= nil then
            local ok = (m.trigger == "lock_attack" and (m.direction == "toward" or m.direction == "away"))
              or (m.trigger == "dodge" and (m.direction == "any" or m.direction == "toward" or m.direction == "away"
                                            or m.direction == "left" or m.direction == "right"))
            if not ok then return fail("invalid_argument", m.id .. ": direction is for a lock_attack or a dodge") end
          end
          if not (within("speed", 0.2, 4) and within("lunge", 0, 6) and within("lunge_decay", 0.01, 2) and within("lunge_angle", -180, 180)) then
            return fail("invalid_argument", m.id .. ": speed or lunge out of range")
          end
          if m.variants ~= nil then
            if not m.animation or not is_list(m.variants) or #m.variants > 4 then
              return fail("invalid_argument", m.id .. ": variants is up to 4 variants, on a move that plays an animation")
            end
            for _, v in ipairs(m.variants) do
              for k in pairs(v) do
                if k ~= "animation" and k ~= "motion" and k ~= "from" and k ~= "to" then
                  return fail("invalid_argument", m.id .. ": a variant received an unsupported field: " .. k)
                end
              end
              local anim = S.animations[v.animation]
              if math.type(v.motion) ~= "integer" or v.motion < 0 or v.motion > 63 or not anim or anim.character ~= m.character
                 or not ((v.from or 0) < (v.to or 1)) then
                return fail("invalid_argument", m.id .. ": each variant is {animation, motion = 0..63, from, to}")
              end
            end
          end
          if m.invincible ~= nil and type(m.invincible) ~= "boolean" then return fail("invalid_argument", m.id .. ": invincible") end
          -- A critical: a backstab or a riposte, within reach 4..60, drawn in to gap 2..40, its pairs the enemies'
          -- monster motions.
          if m.trigger == "critical" then
            if m.critical ~= "backstab" and m.critical ~= "riposte" then return fail("invalid_argument", m.id .. ": critical") end
            if not (within("reach", 4, 60) and within("gap", 2, 40) and within("arc", 20, 180) and within("hold", 0, 600)) then
              return fail("invalid_argument", m.id .. ": reach, gap, arc or hold out of range")
            end
            if m.pairs ~= nil and #m.pairs > 32 then return fail("invalid_argument", m.id .. ": up to 32 pairs") end
            for _, pair in ipairs(m.pairs or {}) do
              for k in pairs(pair) do
                if k ~= "model" and k ~= "animation" and k ~= "speed" then return fail("invalid_argument", m.id .. ": pair field " .. k) end
              end
              if math.type(pair.model) ~= "integer" or type(pair.animation) ~= "string" or not (pair.speed == nil or (pair.speed >= 0.05 and pair.speed <= 4)) then
                return fail("invalid_argument", m.id .. ": a pair is {model, animation, speed?}")
              end
            end
          elseif m.trigger == "art" then
            if not (m.weapons == nil or (#m.weapons <= 64)) or not within("min_level", 1, 99) then return fail("invalid_argument", m.id .. ": weapons or min_level") end
            for _, w in ipairs(m.weapons or {}) do
              if math.type(w) ~= "integer" or w < 257 or w > 511 then return fail("invalid_argument", m.id .. ": a weapon is a native item number") end
            end
          else
            if m.weapons ~= nil or m.min_level ~= nil then return fail("invalid_argument", m.id .. ": weapons and min_level are for an art") end
            for _, k in ipairs({"critical", "reach", "gap", "arc", "hold", "pairs"}) do
              if m[k] ~= nil then return fail("invalid_argument", m.id .. ": " .. k .. " is for a critical") end
            end
          end
          for _, c in ipairs(m.cues or {}) do
            if c.sound and not SOUNDS[c.sound] then return fail("invalid_argument", m.id .. ": cue sound " .. c.sound) end
          end
        end
        S.moves = copy(a.moves)
        return {count = #a.moves}
      end,
      moves_clear = function() count("player.moves_clear"); S.moves = nil; return {cleared = true} end,
      critical_set = function(a)
        count("player.critical_set")
        for k in pairs(a) do assert(k == "entity" or k == "frames", "critical_set field " .. k) end
        assert(type(a.entity) == "string" and (a.frames == nil or (math.type(a.frames) == "integer" and a.frames >= 1 and a.frames <= 600)),
          "critical_set takes an entity and 1..600 frames")
        S.critical_arm = copy(a)
        return {entity = a.entity, frames = a.frames or 120}
      end,
      critical_clear = function() count("player.critical_clear"); S.critical_arm = nil; return {cleared = true} end,
      tuning_set = function(a)
        count("player.tuning_set")
        if refused("player.tuning_set") then return fail("unsupported", "no tuning") end
        for k, v in pairs(a) do
          if MULTIPLIERS[k] then
            if type(v) ~= "number" or v < 0.25 or v > 4 then return fail("invalid_argument", k .. " must be a number from 0.25 to 4") end
          elseif k == "map_reveal" or k == "monster_reveal" or k == "map_hidden" or k == "first_person" or k == "shots_pierce" or k == "dodge_hop" or
                 k == "lock_flick" or k == "lock_sight" or k == "lock_camera" then
            if type(v) ~= "boolean" then return fail("invalid_argument", k .. " must be a boolean") end
          elseif k == "swap_delay" then
            if type(v) ~= "number" or v < 0 or v > 4 then return fail("invalid_argument", "swap_delay must be a number from 0 to 4") end
          elseif k == "dodge_power" then
            if type(v) ~= "number" or (v ~= 0 and (v < 0.25 or v > 4)) then return fail("invalid_argument", "dodge_power") end
          elseif k == "lightness" then
            if type(v) ~= "boolean" then return fail("invalid_argument", "lightness must be a boolean") end
          elseif k == "stamina" then
            if type(v) ~= "table" or is_list(v) then return fail("invalid_argument", "stamina must be {character id = gauge a second}") end
            for id, rate in pairs(v) do
              if not ({toan = 1, xiao = 1, goro = 1, ruby = 1, ungaga = 1, osmond = 1})[id] then
                return fail("invalid_argument", "stamina names an unknown character: " .. tostring(id))
              end
              if type(rate) ~= "number" or rate < 0 or rate > 600 then return fail("invalid_argument", "stamina." .. id) end
            end
          elseif k == "chain_cancel" then
            if math.type(v) ~= "integer" or v < 0 or v > 30 then return fail("invalid_argument", "chain_cancel must be an integer from 0 to 30") end
          elseif k == "input_buffer" then
            if math.type(v) ~= "integer" or v < 0 or v > 20 then return fail("invalid_argument", "input_buffer must be an integer from 0 to 20") end
          elseif k == "soft_lock" then
            if math.type(v) ~= "integer" or v < 0 or v > 90 then return fail("invalid_argument", "soft_lock must be an integer from 0 to 90") end
          elseif k == "item_heal_lock" then
            if math.type(v) ~= "integer" or v < 0 or v > 400 then return fail("invalid_argument", "item_heal_lock must be an integer from 0 to 400") end
          elseif k == "dodge_run" then
            if type(v) ~= "number" or v < 0 or v > 200 then return fail("invalid_argument", "dodge_run must be a number from 0 to 200") end
          elseif k == "dodge_gauge" then
            if math.type(v) ~= "integer" or v < 0 or v > 100 then return fail("invalid_argument", "dodge_gauge") end
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
      -- player.guard_rules_set / gauge_rules_set: the engine's field checks (chronicle_adapter.cpp SetGuardRules,
      -- SetGaugeRules); integers where it reads one with ReadBoundedInt.
      guard_rules_set = function(a)
        count("player.guard_rules_set")
        if refused("player.guard_rules_set") then return fail("unsupported", "no guard rules") end
        local ranges = {arc = {0, 360}, cost_base = {0, 100}, cost_per_damage = {0, 10}, chip = {0, 1},
                        break_recoil = {0, 600, true}, parry_frames = {0, 60, true}}
        for k, v in pairs(a) do
          local r = ranges[k]
          if k == "without_lock" then
            if type(v) ~= "boolean" then return fail("invalid_argument", "without_lock must be a boolean") end
          elseif not r then return fail("invalid_argument", "player.guard_rules_set received an unsupported field: " .. k)
          elseif type(v) ~= "number" or v < r[1] or v > r[2] or (r[3] and math.type(v) ~= "integer") then
            return fail("invalid_argument", k .. " out of range")
          end
        end
        S.guard_rules = copy(a)
        return {on = true}
      end,
      guard_rules_clear = function() count("player.guard_rules_clear"); S.guard_rules = nil; return {cleared = true} end,
      gauge_rules_set = function(a)
        count("player.gauge_rules_set")
        if refused("player.gauge_rules_set") then return fail("unsupported", "no gauge rules") end
        local ranges = {hit_refill = {-100, 100}, first_swing_cost = {0, 100}, min_to_swing = {0, 100},
                        swing_cost_scale = {0, 4}, refill_delay = {0, 600, true}}
        for k, v in pairs(a) do
          local r = ranges[k]
          if not r then return fail("invalid_argument", "player.gauge_rules_set received an unsupported field: " .. k) end
          if type(v) ~= "number" or v < r[1] or v > r[2] or (r[3] and math.type(v) ~= "integer") then
            return fail("invalid_argument", k .. " out of range")
          end
        end
        S.gauge_rules = copy(a)
        return {on = true}
      end,
      gauge_rules_clear = function() count("player.gauge_rules_clear"); S.gauge_rules = nil; return {cleared = true} end,
      get = function() return {position = {x = 0, y = 0, z = 0}} end,
      gauge_get = function()
        if not S.in_dungeon_now then return fail("failed", "player.gauge_get needs an active dungeon") end
        return {gauge = S.gauge or 100, max = 100, exhausted = false}
      end,
    },
    render = {
      hud_icon_set = function(a) S.icons = S.icons or {}; S.icons[a.id] = copy(a); return {} end,
      hud_icon_remove = function(a) if S.icons then S.icons[a.id] = nil end; return {} end,
      -- render.target_bar_set {on}; render.target_meter_set {entity, fill 0..1, color?, seconds?}, {entity} clears.
      target_bar_set = function(a)
        assert(type(a.on) == "boolean" and next(a, next(a)) == nil, "target_bar_set takes {on}")
        S.target_bar = a.on
        return {on = a.on}
      end,
      target_meter_set = function(a)
        for k in pairs(a) do assert(k == "entity" or k == "fill" or k == "color" or k == "seconds", "target_meter_set field " .. k) end
        assert(type(a.entity) == "string", "a meter names its monster")
        assert(a.fill == nil or (type(a.fill) == "number" and a.fill >= 0 and a.fill <= 1), "fill 0..1")
        assert(a.seconds == nil or (type(a.seconds) == "number" and a.seconds >= 0 and a.seconds <= 600), "seconds 0..600")
        S.meters = S.meters or {}
        S.meters[a.entity] = a.fill and copy(a) or nil
        return {meter = a.fill ~= nil}
      end,
    },
    effects = {burst = function(a) S.bursts = S.bursts or {}; S.bursts[#S.bursts + 1] = copy(a); return {} end},
    audio = {se_play = function(a) S.sounds = S.sounds or {}; S.sounds[#S.sounds + 1] = copy(a); return {} end},
    combat = {
      status_add = function(a) S.statuses = S.statuses or {}; S.statuses[#S.statuses + 1] = copy(a); return {} end,
      -- As chronicle_adapter.cpp SetHitFeel.
      feel_set = function(a)
        for k in pairs(a) do assert(k == "hit_stop" or k == "shake" or k == "rumble", "feel_set field " .. k) end
        for k, v in pairs(a.hit_stop or {}) do
          assert((k == "light" or k == "heavy" or k == "critical" or k == "hurt") and math.type(v) == "integer" and v >= 0 and v <= 12, "hit_stop")
        end
        for k, v in pairs(a.shake or {}) do
          assert((k == "light" or k == "heavy" or k == "hurt") and math.type(v) == "integer" and v >= 0 and v <= 10, "shake")
        end
        assert(a.rumble == nil or type(a.rumble) == "boolean", "rumble")
        S.feel = copy(a)
        return copy(a)
      end,
      feel_clear = function() S.feel = nil return {cleared = true} end,
      register_formula = function(a)
        for k in pairs(a) do
          assert(k == "id" or k == "operation" or k == "value" or k == "native_model_id", "register_formula field " .. k)
        end
        assert(a.operation == "multiply" and type(a.value) == "number" and a.value >= 0 and a.value <= 100, "multiply 0..100")
        assert(a.native_model_id == nil or math.type(a.native_model_id) == "integer", "native_model_id is an integer")
        S.formulas = S.formulas or {}
        S.formulas[a.id] = copy(a)
        return {id = a.id}
      end,
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
    items = {
      -- As chronicle_adapter.cpp SetCharmSlots: {count = integer 0..4, feather = optional boolean} and nothing else.
      charm_slots_set = function(a)
        count("items.charm_slots_set")
        assert(type(a) == "table" and math.type(a.count) == "integer" and a.count >= 0 and a.count <= 4,
          "items.charm_slots_set takes {count = 0..4}")
        assert(a.feather == nil or type(a.feather) == "boolean", "feather is a boolean")
        for k in pairs(a) do assert(k == "count" or k == "feather", "items.charm_slots_set field " .. k) end
        S.charm_slots = a.count
        S.feather_slot = a.feather == true
        return {open = a.count, feather = a.feather == true, characters = {}}
      end,
      -- As chronicle_adapter.cpp's items.gear* ops (gear.hpp): a bag of up to 99 pieces besides those worn.
      gear = function()
        local pieces, bag = {}, 0
        for _, p in ipairs(S.gear) do pieces[#pieces + 1] = copy(p); if p.worn_by == nil then bag = bag + 1 end end
        local worn = {}
        for c in pairs(CHARACTERS) do
          local slots, effects = {}, {}
          for _, p in ipairs(S.gear) do
            if p.worn_by == c then
              slots[p.kind] = p.uid
              for k, v in pairs(p.effects) do
                if k == "guard" then
                  effects.guard = effects.guard or {}
                  for a, n in pairs(v) do effects.guard[a] = (effects.guard[a] or 0) + n end
                else effects[k] = (effects[k] or 0) + v end
              end
            end
          end
          worn[c] = {slots = slots, effects = effects}
        end
        return {pieces = pieces, bag = bag, bag_max = 99, worn = worn}
      end,
      gear_give = function(a)
        count("items.gear_give")
        for k in pairs(a) do
          assert(k == "kind" or k == "name" or k == "rarity" or k == "value" or k == "effects" or k == "icon" or k == "color",
            "gear_give field " .. k)
        end
        assert(a.icon == nil or (type(a.icon) == "string" and a.icon:match("^[%w_]+$") and #a.icon <= 48), "icon is a bare stem")
        if a.color ~= nil then
          for _, c in ipairs({"r", "g", "b"}) do
            assert(math.type(a.color[c]) == "integer" and a.color[c] >= 0 and a.color[c] <= 255, "color." .. c .. " 0..255")
          end
        end
        assert(({hat = 1, tunic = 1, gloves = 1, boots = 1, pouch = 1})[a.kind], "gear kind " .. tostring(a.kind))
        assert(type(a.name) == "string" and #a.name >= 1 and #a.name <= 24, "gear name is 1-24 bytes (a row value)")
        assert(math.type(a.rarity) == "integer" and a.rarity >= 0 and a.rarity <= 3, "rarity 0..3")
        assert(math.type(a.value) == "integer" and a.value >= 0 and a.value <= 65535, "value")
        local caps = {stamina = 120, lightness = 50, defence = 99, run_cost = 75, poise = 8, bag = 50}
        for k, v in pairs(a.effects or {}) do
          if k == "guard" then
            for ailment, n in pairs(v) do
              assert(({freeze = 1, poison = 1, curse = 1, goo = 1})[ailment], "guard ailment " .. tostring(ailment))
              assert(math.type(n) == "integer" and n >= 0 and n <= 90, "guard 0..90")
            end
          else
            assert(caps[k] and math.type(v) == "integer" and v >= 0 and v <= caps[k], "effect " .. k .. " " .. tostring(v))
          end
        end
        local bag = 0
        for _, p in ipairs(S.gear) do if p.worn_by == nil then bag = bag + 1 end end
        if bag >= 99 then return fail("failed", "the gear bag is full (99 pieces)") end
        S.gear_uid = (S.gear_uid or 0) + 1
        local piece = copy(a)
        piece.effects = piece.effects or {}
        piece.uid = S.gear_uid
        S.gear[#S.gear + 1] = piece
        return copy(piece)
      end,
      -- items.gear_stock_set: the gear a shop sells beside its own goods, each a piece as gear_give takes it with a price.
      gear_stock_set = function(a)
        count("items.gear_stock_set")
        for k in pairs(a) do assert(k == "shop" or k == "goods", "gear_stock_set field " .. k) end
        assert(math.type(a.shop) == "integer" and a.shop >= 0 and a.shop <= 255, "shop 0..255")
        assert(type(a.goods) == "table" and #a.goods <= 10, "at most ten goods")
        for _, g in ipairs(a.goods) do
          assert(g.price == nil or (math.type(g.price) == "integer" and g.price >= 0 and g.price <= 65535), "price 0..65535")
          local piece = copy(g)
          piece.price = nil
          local saved, uid = S.gear, S.gear_uid
          S.gear = {}
          S.game.items.gear_give(piece) -- the same checks as a piece given
          S.gear, S.gear_uid = saved, uid
        end
        S.gear_stock = S.gear_stock or {}
        S.gear_stock[a.shop] = #a.goods > 0 and copy(a.goods) or nil
        return {shop = a.shop, goods = #a.goods}
      end,
      -- items.gear_page_set: the item page's Equipment tab and the gear slots, each kind's icon a bare stem; {} closes.
      gear_page_set = function(a)
        count("items.gear_page_set")
        if next(a) == nil then S.gear_page = nil return {page = false} end
        for k in pairs(a) do assert(k == "icons" or k == "parts", "gear_page_set field " .. k) end
        for _, kind in ipairs({"hat", "tunic", "gloves", "boots"}) do
          assert(type(a.icons[kind]) == "string" and a.icons[kind]:match("^[%w_]+$"), "icons." .. kind .. " is a bare stem")
        end
        assert(a.icons.pouch == nil or (type(a.icons.pouch) == "string" and a.icons.pouch:match("^[%w_]+$")), "icons.pouch is a bare stem")
        for kind in pairs(a.icons) do
          assert(({hat = 1, tunic = 1, gloves = 1, boots = 1, pouch = 1})[kind], "icons." .. tostring(kind) .. " is a kind")
        end
        -- parts: {<hero id> = {<kind> = {frame names} or {draw = names, fit = names?, bare = names?, turn = degrees?, tilt = degrees?}}}
        local function frame_names(list, where)
          assert(type(list) == "table" and #list >= 1 and #list <= 8, where .. " is 1 to 8 frame names")
          for _, name in ipairs(list) do assert(type(name) == "string" and #name >= 1 and #name <= 31, where .. " frame name") end
        end
        for hero, kinds in pairs(a.parts or {}) do
          assert(type(hero) == "string" and type(kinds) == "table", "parts." .. tostring(hero))
          for kind, entry in pairs(kinds) do
            local where = "parts." .. hero .. "." .. kind
            assert(kind == "hat" or kind == "tunic" or kind == "gloves" or kind == "boots" or kind == "pouch", where .. " is a kind")
            if entry.draw then
              for k in pairs(entry) do assert(k == "draw" or k == "fit" or k == "bare" or k == "below" or k == "turn" or k == "tilt", where .. " field " .. k) end
              frame_names(entry.draw, where .. ".draw")
              if entry.fit then frame_names(entry.fit, where .. ".fit") end
              if entry.bare then frame_names(entry.bare, where .. ".bare") end
              if entry.below then frame_names(entry.below, where .. ".below") end
              assert(entry.turn == nil or (type(entry.turn) == "number" and entry.turn >= -180 and entry.turn <= 180), where .. ".turn")
              assert(entry.tilt == nil or (type(entry.tilt) == "number" and entry.tilt >= -90 and entry.tilt <= 90), where .. ".tilt")
            else
              frame_names(entry, where)
            end
          end
        end
        S.gear_page = copy(a.icons)
        S.gear_parts = a.parts and copy(a.parts)
        return {page = true}
      end,
      gear_equip = function(a)
        count("items.gear_equip")
        assert(math.type(a.uid) == "integer", "gear_equip uid")
        local piece
        for _, p in ipairs(S.gear) do if p.uid == a.uid then piece = p end end
        if not piece then return fail("invalid_argument", "no such piece") end
        local who = a.character or S.active
        for _, p in ipairs(S.gear) do if p.worn_by == who and p.kind == piece.kind then p.worn_by = nil end end
        piece.worn_by = who
        return {}
      end,
      gear_unequip = function(a)
        count("items.gear_unequip")
        local who = a.character or S.active
        for _, p in ipairs(S.gear) do
          if p.worn_by == who and p.kind == a.kind then p.worn_by = nil; return {} end
        end
        return fail("failed", "nothing is worn there")
      end,
      gear_remove = function(a)
        count("items.gear_remove")
        for k in pairs(a) do assert(k == "uid" or k == "sell", "gear_remove field " .. k) end
        for i, p in ipairs(S.gear) do
          if p.uid == a.uid then
            table.remove(S.gear, i)
            local money = a.sell and p.value or 0
            S.money = (S.money or 0) + money
            return {uid = a.uid, money = money}
          end
        end
        return fail("invalid_argument", "no such piece")
      end,
    },
    save = {
      slot_id = function() return S.slot and copy(S.slot) or {} end,
      get = function(key) return copy(S.save_data[key]) end,
      set = function(key, value) S.save_data[key] = copy(value); return true end,
    },
    dungeons = {
      room_seal = function(a)
        assert(type(a) == "table" and next(a) == nil, "room_seal takes {}")
        if S.room_shut then return nil, {code = "failed"} end
        S.room_shut = true; S.room_seals = (S.room_seals or 0) + 1
        return {sealed = true, doors = 2, room = {x = 10, y = 10, w = 3, h = 3}}
      end,
      room_release = function()
        local was = S.room_shut; S.room_shut = nil
        return {released = was == true}
      end,
      set_seed = function(a)
        assert(type(a) == "table" and next(a) and math.type(a.seed) == "integer" and a.seed >= 0, "dungeons.set_seed takes {seed = integer}")
        S.next_seed = a.seed
        return {seed = a.seed}
      end,
      set_opened_chests = function(a)
        assert(type(a) == "table" and next(a), "dungeons.set_opened_chests takes a non-empty table")
        for k, list in pairs(a) do
          assert((k == "chests" or k == "back_chests") and #list > 0, "chests and back_chests are non-empty lists")
        end
        S.next_chests = copy(a)
        return {}
      end,
      set_zones = function(a)
        assert(type(a) == "table", "dungeons.set_zones takes a table")
        if next(a) == nil then S.zones = nil return {zones = 0} end
        assert(#a.zones >= 2, "two zones at least")
        for _, z in ipairs(a.zones) do assert(math.type(z.rooms) == "integer" and z.rooms >= 2, "each zone has rooms") end
        if a.open ~= nil then assert(#a.open > 0, "open is a non-empty list or left out") end
        if a.smoke ~= nil then assert(#a.smoke > 0, "smoke is a non-empty list or left out") end
        if a.descent ~= nil then assert(math.type(a.descent) == "integer" and a.descent >= 0 and a.descent <= 120, "descent is 0 to 120") end
        assert(#a.zones <= 24, "24 zones at most")
        for _, z in ipairs(a.smoke or {}) do
          assert(z >= 1 and z < #a.zones, "smoke lists gates 1 to zones - 1")
          for _, o in ipairs(a.open or {}) do assert(o ~= z, "a smoke gate isn't built open") end
        end
        for k in pairs(a) do
          assert(k == "zones" or k == "open" or k == "shrines" or k == "exit_floor" or k == "smoke" or k == "shrine_heal" or k == "sanctuary" or k == "descent", "set_zones field " .. k)
        end
        for _, z in ipairs(a.zones) do
          for k in pairs(z) do assert(k == "rooms" or k == "source_floor", "zone field " .. k) end
        end
        S.zones = copy(a)
        S.zone_calls = (S.zone_calls or 0) + 1
        return {zones = #a.zones}
      end,
      set_exits = function(a)
        assert(a.town == "shrines" or a.town == "any", "set_exits town")
        S.exits = a.town
        return {town = a.town}
      end,
      set_quick_passage = function(a)
        assert(type(a) == "table" and type(a.enabled) == "boolean", "set_quick_passage takes {enabled}")
        S.quick_passage = a.enabled
        return {enabled = a.enabled}
      end,
      set_floor_select = function(a)
        assert(type(a) == "table" and type(a.enabled) == "boolean", "set_floor_select takes {enabled}")
        S.floor_select = a.enabled
        return {enabled = a.enabled}
      end,
      set_story_exits = function(a)
        assert(type(a) == "table" and (next(a) == nil or type(a.title) == "string"), "set_story_exits takes {title, text} or {}")
        S.story_exits = next(a) ~= nil and copy(a) or nil
        return {set = S.story_exits ~= nil}
      end,
      drop_gilda = function(a)
        assert(type(a.x) == "number" and type(a.y) == "number" and type(a.z) == "number" and math.type(a.amount) == "integer" and a.amount >= 1,
               "drop_gilda takes a position and an amount")
        S.dropped = copy(a)
        return {amount = a.amount}
      end,
      warp = function(a)
        assert(math.type(a.x) == "integer" and math.type(a.y) == "integer", "warp to a cell")
        assert(a.teleport == nil or type(a.teleport) == "boolean", "warp's teleport is a boolean")
        S.warped = copy(a)
        return copy(a)
      end,
      set_arrival = function(a)
        assert((a.zone ~= nil) ~= (a.x ~= nil), "set_arrival takes a zone or a cell")
        S.arrival = copy(a)
        return {arrival = true}
      end,
      enter_floor = function(a)
        assert(math.type(a.floor_id) == "integer" and (a.x == nil) == (a.y == nil), "enter_floor shape")
        S.entered = copy(a)
        return {floor_id = a.floor_id, queued = true}
      end,
      set_npc_models = function(a)
        assert(type(a) == "table" and (next(a) == nil or type(a.models) == "table"), "set_npc_models takes {models} or {}")
        S.npc_models = a.models and copy(a.models) or {}
        return {models = #S.npc_models}
      end,
      set_npc_marks = function(a)
        assert(type(a) == "table" and (next(a) == nil or type(a.marks) == "table"), "set_npc_marks takes {marks} or {}")
        S.npc_marks = a.marks and copy(a.marks) or {}
        return {marks = #S.npc_marks}
      end,
      play_event = function(a)
        assert(type(a) == "table" and math.type(a.program) == "integer", "play_event takes {program}")
        S.played = a.program
        return {program = a.program}
      end,
    },
    resources = {
      override = function(a)
        assert(type(a.path) == "string" and type(a.game_path) == "string", "resources.override takes {path, game_path}")
        S.resource_overrides = S.resource_overrides or {}
        S.resource_overrides[a.game_path] = a.path
        return {path = a.path}
      end,
    },
    -- weapons.stat_label_set: each named stat's label an icon stem; a stat left out gets the game's back.
    weapons = {
      stat_label_set = function(a)
        count("weapons.stat_label_set")
        for k, v in pairs(a) do
          assert(({attack = 1, endurance = 1, speed = 1, magic = 1})[k], "stat_label_set stat " .. tostring(k))
          assert(type(v) == "string" and v:match("^[%w_]+$") and #v <= 48, "a label is a bare icon stem")
        end
        S.stat_labels = copy(a)
        return {labels = copy(a)}
      end,
    },
    -- Monster AI: the native.monster.run hook, the natives a callback runs, and the floor's monsters.
    scripts = {
      override = function(spec, fn)
        count("scripts.override")
        assert(spec.id == "native.monster.run", "hook id")
        if spec.enabled == false then S.override = nil return {removed = true} end
        assert(type(fn) == "function", "override takes a callback")
        S.override = fn
        return {id = spec.id}
      end,
      call = function(spec)
        assert(spec.id == "native.monster.run", "call id")
        S.retail = (S.retail or 0) + 1
        return {ran = true}
      end,
    },
    monsters = {
      call = function(a)
        assert(type(a.entity) == "string" and type(a.native) == "string" and (a.args == nil or type(a.args) == "table"), "monsters.call shape")
        -- The engine turns an empty table away: it arrives as {}, not a list.
        if a.args ~= nil and next(a.args) == nil then
          S.rejected = (S.rejected or 0) + 1
          error("args must be a list of at most 16 values")
        end
        for _, v in ipairs(a.args or {}) do
          assert(type(v) == "number" or type(v) == "boolean" or (type(v) == "string" and v:match("^[%w_]+$") and #v <= 31) or
                 (type(v) == "table" and (v.out == "int" or v.out == "float")),
                 "monsters.call args are numbers, booleans, frame names or outs")
        end
        S.natives[#S.natives + 1] = {entity = a.entity, native = a.native, args = copy(a.args or {})}
        local mon = S.monster_at[a.entity] or {0, 0, 0}
        if a.native == "GET_POSITION" then
          local at = a.args[1] == -2 and S.player_at or mon
          return {out = {at[1], at[2], at[3]}}
        elseif a.native == "CHK_MOTION_FRM" then return {out = {0, S.motion_frame or 0}}
        elseif a.native == "GUARD_SEARCH" then return {out = {S.player_swing or 3600, 20, 0}}
        elseif a.native == "CHK_MOVE_INFO" then return {out = {1}}
        end
        return {out = {}}
      end,
    },
    entities = {query = function() return {entities = copy(S.floor)} end,
                get = function(id) return {id = id, native_model_id = 3, position = {x = 0, y = 0, z = 50}} end,
                knockback = function(a) S.knockbacks = S.knockbacks or {}; S.knockbacks[#S.knockbacks + 1] = copy(a); return {} end},
    ui = {
      map_open = function(a)
        S.map = copy(a)
        return {id = a.id}
      end,
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
  -- As chronicle_adapter.cpp SetRunMenu.
  S.game.ui.run_menu_set = function(a)
    for k in pairs(a) do assert(k == "title" or k == "tabs", "run_menu_set field " .. k) end
    assert(type(a.title) == "string" and #a.title >= 1 and #a.title <= 48, "run menu title")
    assert(type(a.tabs) == "table" and #a.tabs >= 1 and #a.tabs <= 6, "1-6 tabs")
    for _, t in ipairs(a.tabs) do
      assert(type(t.id) == "string" and #t.id <= 32 and type(t.title) == "string" and #t.title <= 24, "tab id and title")
      assert(t.lines == nil or (#t.lines >= 1 and #t.lines <= 8), "tab lines: leave out an empty list")
      for _, l in ipairs(t.lines or {}) do assert(type(l) == "string" and #l <= 96, "tab line up to 96 bytes: " .. tostring(l)) end
      assert(t.rows == nil or (#t.rows >= 1 and #t.rows <= 64), "tab rows: leave out an empty list, up to 64")
      for _, r in ipairs(t.rows or {}) do
        assert(type(r.id) == "string" and #r.id >= 1 and #r.id <= 32, "row id")
        assert(type(r.label) == "string" and #r.label >= 1 and #r.label <= 48, "row label")
        assert(r.value == nil or #r.value <= 24, "row value up to 24 bytes: " .. tostring(r.value))
        assert(r.detail == nil or #r.detail <= 240, "row detail up to 240 bytes: " .. tostring(r.detail))
        assert(r.tone == nil or ({good = 1, bad = 1, dim = 1, gold = 1})[r.tone], "row tone")
        assert(r.enabled == nil or type(r.enabled) == "boolean", "row enabled")
      end
    end
    S.run_menu = copy(a)
    return {set = true}
  end
  S.game.ui.run_menu_clear = function() S.run_menu = nil return {cleared = true} end
  -- messages.*: one shared folder, the player's own messages marked mine (as the engine checks them)
  S.message_store = {}
  local function message_place(place) return type(place) == "string" and #place >= 1 and #place <= 64 and not place:find("[^a-z0-9:_%.%-]") end
  S.game.messages = {
    post = function(a)
      assert(message_place(a.place) and type(a.text) == "string" and #a.text >= 1 and #a.text <= 120 and not a.text:find("[^ -~]"), "messages.post {place, text}")
      local id = string.format("000000000000-%08x", #S.message_store + 1)
      S.message_store[#S.message_store + 1] = {id = id, place = a.place, text = a.text, at = #S.message_store + 1, good = 0, poor = 0, mine = true, rated = 0}
      return {id = id, shared = S.messages_shared == true}
    end,
    list = function(a)
      assert(message_place(a.place), "messages.list {place}")
      local out = {}
      for _, m in ipairs(S.message_store) do if m.place == a.place then out[#out + 1] = copy(m) end end
      table.sort(out, function(x, y) return x.good - x.poor > y.good - y.poor end)
      return {messages = out, shared = S.messages_shared == true}
    end,
    rate = function(a)
      assert(a.rating == 1 or a.rating == -1 or a.rating == 0, "messages.rate rating")
      for _, m in ipairs(S.message_store) do
        if m.id == a.id then
          assert(not m.mine, "no one rates their own")
          if m.rated == 1 then m.good = m.good - 1 elseif m.rated == -1 then m.poor = m.poor - 1 end
          if a.rating == 1 then m.good = m.good + 1 elseif a.rating == -1 then m.poor = m.poor + 1 end
          m.rated = a.rating
          return {id = a.id, rating = a.rating}
        end
      end
      error("no such message")
    end,
    remove = function(a)
      for i, m in ipairs(S.message_store) do
        if m.id == a.id then assert(m.mine, "only one's own") table.remove(S.message_store, i) return {removed = a.id} end
      end
      error("no such message")
    end,
  }
  S.game.ui.choice_open = function(a)
    assert(type(a.id) == "string" and #a.options >= 1 and #a.options <= 6, "choice_open takes 1-6 options")
    assert(a.cursor == nil or (a.cursor >= 1 and a.cursor <= #a.options), "cursor is an option's number")
    S.panel = copy(a)
    return {open = true}
  end
  S.game.player.heal = function(a)
    assert(math.type(a.amount) == "integer" and a.amount >= 1 and a.amount <= 32767, "heal amount")
    S.healed = (S.healed or 0) + 1
    return {hp = 100}
  end
  S.game.party = {list = function() return {{id = "toan", active = true}, {id = "xiao"}} end}
  S.game.world = {transition = function(a) S.transition = a.id return {queued = true} end,
                  set_roads = function(a)
                    assert(type(a) == "table" and type(a.enabled) == "boolean", "set_roads takes {enabled}")
                    S.roads = a.enabled
                    return {enabled = a.enabled}
                  end}
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

-- The moves but the flask's drinks (Flask: a played move for each hero) and the weapon arts.
local function fighting(S)
  if not S.moves then return nil end
  local n = 0
  for _, m in ipairs(S.moves) do if m.trigger ~= "played" and m.trigger ~= "art" then n = n + 1 end end
  return n
end

local function moves_by(S)
  local t = {}
  for _, m in ipairs(S.moves or {}) do
    local key = m.character .. "/" .. m.trigger
    if m.chain then key = key .. "/" .. m.chain end
    if m.direction then key = key .. "/" .. m.direction end
    t[key] = m
  end
  return t
end

-- 1. Story game: the rules go on ---------------------------------------------------------------------------------
print("1. Loading in the story game")
do
  local S = new_game().load()
  check(fighting(S) == 53, "fourteen evades (a dodge and a dodge_back for each of the six, Toan's side rolls), Toan's eight attacks, his two criticals and the other heroes' 19 and their ten criticals",
    S.moves and #S.moves)
  local by = moves_by(S)
  local all_ok = true
  for c in pairs(CHARACTERS) do
    for _, trigger in ipairs({"dodge", "dodge_back"}) do
      local m = by[c .. "/" .. trigger]
      if not (m and m.invincible == true and m.gauge == 35 and m.cooldown == 30 and m.cancel == true and m.cancel_after == 6 and m.wear == 0
              and m.blend_in == 3
              and m.hits == nil and S.animations[m.animation] and S.animations[m.animation].character == c) then
        all_ok = false
      end
    end
  end
  check(all_ok, "each is untouchable, costs 35 gauge, cools down 30 frames, commits 6 frames, never attacks, uses its own motion")
  local party_ok = true
  for _, key in ipairs({"goro/heavy", "goro/combo_finisher/2", "goro/combo_finisher/3", "goro/guard_attack", "goro/evade_attack",
                        "ungaga/heavy", "ungaga/combo_finisher/3", "xiao/heavy", "xiao/combo_finisher/2", "ruby/combo_finisher/3",
                        "osmond/heavy"}) do
    local m = by[key]
    if not (m and m.hits and S.animations[m.animation] and S.animations[m.animation].character == key:match("^%a+")) then party_ok = false end
  end
  check(party_ok, "the other five heroes: a heavy, finishers, a counter and a roll attack, each on its own motion (§13, item 5)")
  check(S.charm_slots == 1, "one charm slot opened on the item page")
  check(S.feather_slot, "and a slot of its own for Dran's Feather, while L2 runs")
  S.set("charm_slot", false)
  check(S.charm_slots == 0, "and closed again with its setting off")
  check(S.feather_slot, "the Feather's slot stays with the run")
  S.set("run_cost", 0)
  check(not S.feather_slot, "and closes with it")
  S.set("run_cost", 20)
  S.set("charm_slot", true)
  check(by["toan/dodge_back"].lunge_angle == 180 and by["toan/dodge"].lunge_angle == nil, "the backstep carries him back, the roll the way the stick points")
  local v = by["toan/dodge"].variants
  check(v and #v == 2 and v[1].animation == "toan_dive_roll_right" and v[1].motion == 1 and v[1].from == 0 and v[1].to == 0.3
        and v[2].from == 0.8 and v[2].to == 1 and by["xiao/dodge"].variants == nil,
    "out of a run with his right foot ahead, Toan's roll pushes off his right foot")
  local left, right = by["toan/dodge/left"], by["toan/dodge/right"]
  check(left and right and left.animation == "toan_side_roll_left" and right.animation == "toan_side_roll_right"
        and left.variants == nil and left.gauge == 35 and left.invincible == true and left.blend_in == 3 and by["xiao/dodge/left"] == nil
        and left.camera == 3 and by["toan/dodge"].camera == 3 and by["xiao/dodge"].camera == nil,
    "locked on with the stick to the side, Toan rolls sideways (a dodge with a direction), at the same cost; his camera keeps up")
  check(by["xiao/dodge"].animation == "xiao_tumble" and by["xiao/dodge_back"].animation == "xiao_hop_shot", "Xiao tumbles and hops back")
  local slots = {["toan/heavy"] = "toan_heavy", ["toan/combo_finisher/2"] = "toan_finisher_2",
                 ["toan/combo_finisher/3"] = "toan_finisher_3", ["toan/run_attack"] = "toan_run_attack",
                 ["toan/lock_attack/toward"] = "toan_lunge", ["toan/lock_attack/away"] = "toan_back_attack",
                 ["toan/evade_attack"] = "toan_roll_attack", ["toan/guard_attack"] = "toan_guard_counter"}
  local attacks_ok = true
  for key, anim in pairs(slots) do
    local m = by[key]
    if not (m and m.animation == anim and S.animations[anim] and S.animations[anim].character == "toan" and m.hits and #m.hits >= 1
            and m.gauge == nil and m.cancel == nil and m.blend_in == 4) then
      attacks_ok = false
    end
  end
  check(attacks_ok, "Toan's eight attacks, each on its own slot motion, each hitting, each fading in over 4 frames")
  check(S.override ~= nil, "the enemy brain hooks the monsters' scripts")
  check(S.player_formulas["enemy-damage"] and S.player_formulas["enemy-damage"].value == 2.5, "enemies hit x2.5")
  local t = S.tuning or {}
  check(t.recoil_scale == 0.4 and t.gauge_refill == 1 and t.swap_delay == 2, "recoil x0.4, gauge refill x1, switching x2", t.recoil_scale)
  check(t.status_immune and t.status_immune[1] == "stamina" and #t.status_immune == 1, "no Stamina power-ups from enemies")
  check(t.map_hidden == nil, "minimap kept")
  check(t.dodge_power == 1 and t.dodge_hop == true and t.dodge_invincible_frames == 14,
        "a hero whose evade motions are missing still hops aside on L2, untouchable for 14 frames (a roll takes L2 first)")
  check(t.dodge_gauge == 35, "for the gauge a roll costs")
  check(t.dodge_run == 20, "holding L2 runs, draining 20 gauge a second", t.dodge_run)
  check(t.lightness == true, "a weapon's Speed sets what a swing costs (Lightness)")
  check(S.stat_labels and S.stat_labels.speed == "label_lightness" and S.resource_overrides["icons/label_lightness.png"] == "resources/label_lightness.png",
    "and the weapon cards label it Lt, from Vigil's resources")
  check(S.stat_labels.attack == "label_attack" and S.stat_labels.endurance == "label_endurance" and S.stat_labels.magic == "label_magic",
    "all four labels are Vigil's, one size, so the Status tab lays them evenly")
  local found = 0
  for _, stat in ipairs({"attack", "endurance", "speed", "lightness", "magic"}) do
    local png = io.open(MOD_DIR .. "/resources/label_" .. stat .. ".png", "rb")
    if png then found = found + 1 png:close() end
  end
  check(found == 5, "the five labels are in Vigil's resources", found)
  local st = t.stamina or {}
  check(st.toan == 35 and st.ungaga == 30 and st.xiao == 120 and st.ruby == 180 and st.goro == 60 and st.osmond == 80,
    "each character refills at their own rate: Toan and Ungaga slow, Xiao and Ruby quick")
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
  S.set("run_cost", 0)
  check(S.tuning.dodge_run == nil, "a run cost of 0 leaves L2 a press-to-evade")
  S.set("run_cost", 35)
  check(S.tuning.dodge_run == 35, "and the cost is the setting's", S.tuning.dodge_run)
  S.set("lightness", false)
  check(S.tuning.lightness == nil and S.tuning.stamina == nil, "Lightness off: the weapon's Speed sets the refill again")
  check(S.stat_labels and S.stat_labels.speed == "label_speed" and S.stat_labels.attack == "label_attack", "and the cards say Sp again, in Vigil's lettering")
  S.set("lightness", true)
  check(S.stat_labels.speed == "label_lightness", "on again, Lt")
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
  check(fighting(S) == 39 and moves_by(S)["toan/dodge"] == nil and S.tuning.dodge_power == nil,
    "evades off: Toan's attacks stay, no evades and no shove dodge")
  S.set("toan_attacks", false)
  check(fighting(S) == 0 and #S.moves == 6, "and with his attacks off too, only the flask's drinks")
  S.set("evades", true)
  check(fighting(S) == 14 and moves_by(S)["toan/heavy"] == nil, "evades alone without his attacks")
  S.set("enemy_brain", false)
  check(S.override ~= nil, "the enemy brain off: the hook stays for Poise")
  S.set("poise", 0)
  check(S.override == nil, "and with Poise off too, the monsters' own scripts again")
  S.set("enemy_brain", true)
  check(S.override ~= nil, "and back on")
  S.set("poise", 2)
  local first = new_game({settings = {recoil = 25, swap_delay = 0}}).load()
  check(first.tuning.recoil_scale == 0.25 and first.tuning.swap_delay == 0, "the setting extremes are values the engine accepts")
end

-- 4. Missing motions fall back to the engine's dodge ------------------------------------------------------------
print("4. No motions")
do
  local S = new_game({fail_ops = {["animations.player_register"] = true}}).load()
  check(fighting(S) == 0, "no moves without their motions, the flask's (native motions) aside")
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
  check(S.override == nil, "the Gauntlet's monsters keep their own scripts")
  check(S.npc_models and #S.npc_models == 0, "no Fairy King in the Gauntlet's cave")
  check(S.player_formulas["enemy-damage"].value == 1, "enemy damage back to x1 (a formula can't be removed)")
  check(S.charm_slots == 0, "the charm slot closed for the run")
  local sets = S.calls["player.tuning_set"]
  S.guard(true); S.tick(20)
  check(S.calls["player.tuning_set"] == sets and S.tuning == nil, "the guard is ignored during the run")
  S.set("evade_cost", 50)
  check(S.moves == nil, "a settings change during the run changes nothing")
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  check(#S.toasts == 0, "no tips during the run")
  S.session = {kind = "story"}
  S.emit("game.session.ended", {owner = "moonmod.roguelike", reason = "ended"})
  check(fighting(S) == 53 and moves_by(S)["toan/dodge"].gauge == 50, "back afterwards, with the new setting")
  check(S.override ~= nil, "the enemy brain back too")
  check(S.npc_models and #S.npc_models == 1, "and the King's model back with the cave")
  check(S.tuning and S.tuning.gauge_refill == 0.25, "and the guard held across the switch counts")
  check(S.player_formulas["enemy-damage"].value == 2.5, "enemies hit hard again")
  check(S.charm_slots == 1, "and the charm slot open again")

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
  check(#S.toasts == 4 and S.storage.told == true, "four tips on the first dungeon", #S.toasts)
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 1})
  check(#S.toasts == 4, "once")
  local again = new_game({storage = {told = true}}).load()
  again.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  check(#again.toasts == 0, "not after a restart either")
  local quiet = new_game({settings = {tips = false}}).load()
  quiet.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  check(#quiet.toasts == 0, "or with tips off")
  S.emit("ui.action", {id = "check"})
  check(S.toasts[#S.toasts]:find("evades on", 1, true) and S.toasts[#S.toasts]:find("attacks on", 1, true) and S.toasts[#S.toasts]:find("x2.50", 1, true), "Check reports what is set", S.toasts[#S.toasts])
end

-- 7. The shipped motions -----------------------------------------------------------------------------------------
print("7. Motion files")
do
  local ok, bad = true, nil
  local names = {"toan_dive_roll", "toan_backstep", "xiao_tumble", "xiao_hop_shot", "goro_roll", "goro_backstep", "ungaga_roll",
                 "ungaga_backstep", "ruby_tumble", "ruby_hop_shot", "osmond_tumble", "osmond_hop_shot", "toan_dive_roll_right", "toan_side_roll_left",
                 "toan_side_roll_right", "toan_heavy",
                 "toan_finisher_2", "toan_finisher_3", "toan_run_attack", "toan_lunge", "toan_back_attack", "toan_roll_attack",
                 "toan_guard_counter"}
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
  check(ok, "every shipped moonmod-motion v1 file, each its character's and within the 4 MiB limit", bad)
end

-- 8. The enemy brain --------------------------------------------------------------------------------------------
print("8. Enemy brain")
do
  local S = new_game({settings = {poise = 0}}).load() -- every hit flinches, as the game has it (Poise: section 27)
  local frame = 0
  local function run(entity, program, n)
    local last
    for _ = 1, n or 1 do
      frame = frame + 2 -- the hook comes round on alternate frames
      last = S.override({entity = entity, slot = 0, program_no = program, model = 0, frame = frame})
    end
    return last
  end
  local function started(entity, motion, from)
    for i = from or 1, #S.natives do
      local n = S.natives[i]
      if n.entity == entity and n.native == "SET_MOTION" and n.args[1] == motion then return true end
    end
    return false
  end
  S.monster_at.m1 = {60, 0, 0}
  local r = run("m1", 100)
  check(type(r) == "table" and r.handled == true and (S.retail or 0) == 0, "the brain takes over a Dasher's idle program")
  check(started("m1", 1), "far off, it walks in")
  local retail = S.retail or 0
  run("m2", 100)
  check(S.retail == retail + 1, "a monster it has no brain for keeps its own script")
  run("m1", 110)
  check(S.retail == retail + 2, "being hit runs the game's own reaction")
  S.monster_at.m1, S.monster_at.m3 = {15, 0, 0}, {0, 0, 15}
  local mark = #S.natives + 1
  for _ = 1, 120 do
    run("m1", 100)
    if started("m1", 13, mark) then break end
  end
  check(started("m1", 13, mark), "within reach, after a beat of circling, it commits to its attack")
  local turned = false
  for i = mark, #S.natives do if S.natives[i].entity == "m1" and S.natives[i].native == "SET_ROTATION" then turned = true end end
  check(turned, "turning to track the player")
  local other = #S.natives + 1
  run("m3", 100, 150)
  check(not started("m3", 13, other), "a second Dasher waits its turn while the first attacks")
  S.monster_at.m4, S.player_swing = {0, 0, 14}, 4
  local shield = #S.natives + 1
  for _ = 1, 400 do
    run("m4", 100)
    if started("m4", 5, shield) then break end
  end
  check(started("m4", 5, shield), "a Skeleton Soldier raises its shield against a swing close by")
  S.monster_at.m5 = {14, 0, 0}
  local dodged, side = #S.natives + 1, false
  for _ = 1, 400 do
    run("m5", 100)
    if started("m5", 3, dodged) or started("m5", 4, dodged) then side = true break end
  end
  check(side, "a Dasher sidesteps a swing close by")
  S.player_swing = nil
  -- A roll thrown against a wind-up: the swing is held (paused) and turns with the roll.
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  S.monster_at = {m6 = {15, 0, 0}}
  local mark6 = #S.natives + 1
  for _ = 1, 200 do
    run("m6", 100)
    if started("m6", 13, mark6) then break end
  end
  S.motion_frame = 160
  run("m6", 100, 4)
  S.emit("game.player.move", {id = "vigil_toan_dive_roll"})
  S.motion_frame = 166
  local held = #S.natives + 1
  run("m6", 100, 3)
  local paused = false
  for i = held, #S.natives do
    local n = S.natives[i]
    if n.entity == "m6" and n.native == "SET_MOTION" and n.args[1] == 13 and n.args[3] == 3 then paused = true end
  end
  check(started("m6", 13, mark6) and paused, "a Dasher holds its wind-up against a roll until the roll is spent")
  S.motion_frame = nil
  -- Its own new motions: registered with the brain, given numbers once a floor loads the model, then played.
  local ids = {}
  for _, m in ipairs(S.monster_motions) do ids[m.id] = m.model end
  check(ids.e06a_roll_left == 3 and ids.e06a_roll_right == 3 and ids.e06a_pounce == 3 and ids.e03a_roll_left == 1 and
        ids.e03a_roll_right == 1 and ids.e03a_whirl == 1 and ids.e07a_roll_left == 4 and ids.e07a_roll_right == 4 and
        ids.e07a_rake == 4 and ids.e63a_roll_left == 55 and ids.e63a_pounce == 55,
        "each monster's rolls and new attack are registered on its model")
  S.models_loaded = true
  S.monster_at = {m7 = {14, 0, 0}}
  S.player_swing = 4
  local mark7, rolled7, pounced = #S.natives + 1, false, false
  for _ = 1, 3000 do
    run("m7", 100)
    S.motion_frame = nil
    for i = mark7, #S.natives do
      local n = S.natives[i]
      if n.entity == "m7" and n.native == "SET_MOTION" then
        local number = 100 + (function() for k, m in ipairs(S.monster_motions) do if m.id == "e06a_pounce" then return k end end end)()
        if n.args[1] == number then pounced = true end
        if n.args[1] ~= number and n.args[1] > 100 then rolled7 = true end
      end
    end
    mark7 = #S.natives + 1
    if rolled7 and pounced then break end
  end
  check(rolled7, "a Dasher rolls aside from a swing")
  check(pounced, "a Dasher opens with its pounce now and then")
  local halted = false
  for _, n in ipairs(S.natives) do if n.native == "SET_MOVE_CANSEL" then halted = true end end
  check(halted and (S.rejected or 0) == 0, "a monster really stops (no native call turned away)", S.rejected)
  S.player_swing = nil
  -- More families: the Werewolf and Master Jacket walk in, then swing (attack_1 is motion 13; the Werewolf may open
  -- with its rake, a motion of its own, numbered past 100).
  for _, w in ipairs({{"m8", "a Werewolf"}, {"m9", "a Master Jacket"}, {"m10", "a Mummy"}, {"m11", "a Spade"},
                      {"m12", "a Corcea (a copy of the Captain's row)"}}) do
    local id = w[1]
    S.monster_at = {[id] = {60, 0, 0}}
    local mark8 = #S.natives + 1
    local r8 = run(id, 100)
    check(type(r8) == "table" and r8.handled == true and started(id, 1, mark8), w[2] .. " gets the brain and walks in")
    S.monster_at[id] = {15, 0, 0}
    mark8 = #S.natives + 1
    local function swung()
      for i = mark8, #S.natives do
        local n = S.natives[i]
        if n.entity == id and n.native == "SET_MOTION" and (n.args[1] == 13 or n.args[1] > 100) then return true end
      end
    end
    for _ = 1, 500 do -- once the last one's turn to attack is over (600 frames at most)
      run(id, 100)
      if swung() then break end
    end
    check(swung(), w[2] .. " commits to an attack in reach")
  end
  S.set("enemy_brain", false)
  check(S.override == nil, "off: the hook is gone")
end

-- 9. The same floors every visit --------------------------------------------------------------------------------
print("9. The same floors every visit")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 7}}).load()
  -- The engine's side: a floor built with no seed asked for picks its own; a seed asked for is used once.
  local function build(dungeon, floor, back)
    S.next_seed = nil
    S.emit("game.dungeon.generating", {dungeon_id = dungeon, floor_id = floor, back_floor = back or false})
    local asked = S.next_seed
    local seed = asked or math.random(0, 21474)
    S.emit("game.dungeon.generated", {dungeon_id = dungeon, floor_id = floor, back_floor = back or false, floor_seed = seed, room_count = 6})
    return seed, asked ~= nil
  end
  local first, asked = build(0, 3)
  check(not asked, "a floor's first visit picks its own layout")
  check(S.save_data["floors:1:7"] and S.save_data["floors:1:7"]["0:3"] == first, "its seed is kept with this save slot")
  build(0, 4)
  local again, asked_again = build(0, 3)
  check(asked_again and again == first, "back on the floor later: built from the kept seed, the same floor")
  local _, back_asked = build(0, 3, true)
  check(not back_asked, "the back floor is left to follow its floor")
  build(6, 3)
  local _, shaft_asked = build(6, 3)
  check(not shaft_asked and S.save_data["floors:1:7"]["6:3"] == nil, "Demon Shaft stays new every time")
  -- A kept seed whose floor couldn't be crossed is built from another: the new one is kept.
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 3, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 3, back_floor = false, floor_seed = first + 1, room_count = 6})
  check(S.save_data["floors:1:7"]["0:3"] == first + 1, "a rebuilt floor keeps the seed it was really built from")

  S.slot = {slot_id = 2, slot_generation = 1}
  local _, other_asked = build(0, 3)
  check(not other_asked, "another save slot has floors of its own")

  S.slot = {slot_id = 1, slot_generation = 7}
  S.set("same_floors", false)
  local _, off_asked = build(0, 3)
  check(not off_asked, "off: every visit is a new floor")
  S.set("same_floors", true)

  local N = new_game().load()
  N.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 1, back_floor = false, floor_seed = 555, room_count = 6})
  N.slot = {slot_id = 3, slot_generation = 2}
  N.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 1, back_floor = false})
  check(N.next_seed == 555 and N.save_data["floors:3:2"]["0:1"] == 555, "a new game's floors go with it to the slot it is first saved in")
  N.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 1, back_floor = false, floor_seed = 555, room_count = 6})
  N.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 2, back_floor = false, floor_seed = 77, room_count = 6})
  check(N.save_data["floors:3:2"] and N.save_data["floors:3:2"]["0:1"] == 555, "and are written there with its next floor")

  S.session = {kind = "sandbox", owner = "moonmod.roguelike"}
  S.emit("game.session.started", {owner = "moonmod.roguelike"})
  local _, run_asked = build(0, 3)
  check(not run_asked, "the Gauntlet's floors are its own")
end

-- 10. Opened chests stay opened ------------------------------------------------------------------------------------
print("10. Opened chests stay opened")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}}).load()
  local function enter(floor, seed)
    S.next_seed, S.next_chests = nil, nil
    S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = floor, back_floor = false, floor_seed = S.next_seed or seed, room_count = 6})
  end
  enter(2, 500)
  check(S.next_chests == nil, "a new floor opens no chests")
  S.emit("game.chest.opened", {dungeon_id = 0, floor_id = 2, back_floor = false, chest = 3, item_id = 81, large = false})
  S.emit("game.chest.opened", {dungeon_id = 0, floor_id = 2, back_floor = false, chest = 3, item_id = 81, large = false})
  S.emit("game.chest.opened", {dungeon_id = 0, floor_id = 2, back_floor = true, chest = 0, item_id = 90, large = true})
  S.emit("game.chest.opened", {}) -- a mod changed a loot table
  S.emit("game.chest.opened", {dungeon_id = 0, floor_id = 2, back_floor = false, chest = 0, item_id = 233, large = false})
  local kept = S.save_data["floors:1:1"]
  check(kept and #kept["0:2:chests"] == 1 and kept["0:2:chests"][1] == 3 and kept["0:2:back"][1] == 0,
        "opened chests are kept with the floor, once each, the back floor's apart (the map's chest fills again)")
  enter(3, 600)
  enter(2, 999)
  check(S.next_chests and S.next_chests.chests[1] == 3 and S.next_chests.back_chests[1] == 0,
        "back on the floor: its opened chests are opened again as it is built")
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 2, back_floor = false, floor_seed = 777, room_count = 6})
  check(S.save_data["floors:1:1"]["0:2:chests"] == nil, "a floor built from a new seed has its chests closed again")
  S.emit("game.chest.opened", {dungeon_id = 6, floor_id = 4, back_floor = false, chest = 1})
  check(S.save_data["floors:1:1"]["6:4:chests"] == nil, "Demon Shaft's chests are new every time")
end

-- Standing in the water of shrine sh ({zone, x, y}) and pressing Square.
local function pray(S, sh)
  local zg, pg, ic = S.game.dungeons.zones_get, S.game.player.get, S.game.input.consume
  S.game.dungeons.zones_get = function() return {current = sh.zone, shrines = {copy(sh)}, gates = {}, floor_zones = 2} end
  S.game.player.get = function() return {hp = 50, character = "toan", position = {x = 160 * sh.x, y = 0, z = 160 * sh.y + 30}} end
  S.game.input.consume = function(a) return {pressed = a.id == "pray"} end
  S.tick(5)
  S.game.dungeons.zones_get, S.game.player.get, S.game.input.consume = zg, pg, ic
end
local function any_toast(S, text)
  for _, t in ipairs(S.toasts) do if t:find(text, 1, true) then return true end end
  return false
end
local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

-- 11. Zones (the Vigil World preview) ------------------------------------------------------------------------------
print("11. Zones (the Vigil World preview)")
do
  local function last_toast(S, text) return S.toasts[#S.toasts] ~= nil and S.toasts[#S.toasts]:find(text, 1, true) ~= nil end
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}}).load()
  local function enter(floor, seed)
    S.next_seed = nil
    S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = floor, back_floor = true})
    S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = floor, back_floor = false, floor_seed = S.next_seed or seed, room_count = 10})
  end
  enter(2, 500)
  check(S.zones == nil and S.zone_calls == nil, "off by default: floors are built as they always were")
  check(S.save_data["floors:1:1"].world == false, "the save is settled as a normal Dark Cloud save")
  S.set("world_zones", true)
  enter(5, 600)
  check(S.zones == nil, "turning the setting on later leaves it one")
  check(last_toast(S, "started without Vigil World"), "and says why")
  S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true, world_regions = false}}).load()
  enter(5, 600)
  check(S.zones and #S.zones.zones == 2 and S.zones.open == nil, "on: a floor is two zones, its gate locked the first time")
  check(S.zones.descent == 40, "each zone a step lower (height steps)")
  S.set("height_steps", false)
  enter(5, 600)
  check(S.zones and S.zones.descent == nil, "height steps off: the floor stays level")
  S.set("height_steps", true)
  enter(3, 650)
  check(S.zones == nil, "a story floor (Divine Beast Cave's 4) is the game's own")
  enter(5, 600)
  S.emit("game.dungeon.zone_gate_locked", {zone = 1, key = "chronicle:item:222"})
  check(last_toast(S, "carries its key"), "a locked gate says who holds the key")
  S.emit("game.dungeon.zone_gate_opened", {zone = 1, key = "chronicle:item:222", x = 18, y = 9})
  check(S.save_data["floors:1:1"]["0:5:gates"][1] == 1, "an opened gate is kept with the floor")
  S.emit("game.dungeon.zone_entered", {zone = 1, previous = 0, zones = 2})
  check(last_toast(S, "zone 2 of 2"), "walking into the next zone says so")
  enter(6, 700)
  enter(5, 999)
  check(S.zones and S.zones.open and S.zones.open[1] == 1, "back on the floor: its gate is built open")
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 5, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 5, back_floor = false, floor_seed = 4321, room_count = 10})
  check(S.save_data["floors:1:1"]["0:5:gates"] == nil, "a floor built from a new seed has its gate locked again")
  enter(6, 100)
  S.emit("game.dungeon.generating", {dungeon_id = 6, floor_id = 9, back_floor = false})
  check(S.zones == nil, "Demon Shaft stays floor by floor")
  S.set("world_zones", false)
  enter(8, 800)
  check(S.zones and #S.zones.zones == 2, "a save started with Vigil World keeps it when the setting is turned off")
  S.set("world_zones", true)
  S.session = {kind = "sandbox", owner = "moonmod.roguelike"}
  S.emit("game.session.started", {owner = "moonmod.roguelike"})
  local before = S.zone_calls
  enter(8, 800)
  check(S.zone_calls == before and S.zones == nil, "the Gauntlet's floors are its own")
end

-- 12. Shrines (W1.2) ----------------------------------------------------------------------------------------------
print("12. Shrines (W1.2)")
do
  local function last_toast(S, text) return S.toasts[#S.toasts] ~= nil and S.toasts[#S.toasts]:find(text, 1, true) ~= nil end
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true, world_regions = false}}).load()
  local function enter(floor, seed)
    S.next_seed = nil
    S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = floor, back_floor = false, floor_seed = S.next_seed or seed, room_count = 10})
  end
  enter(2, 500)
  check(S.zones and S.zones.shrines == true and S.zones.shrine_heal == false and S.exits == "shrines",
        "a zoned floor asks for shrines (whose water doesn't heal) and keeps town behind them")
  S.emit("game.dungeon.town_refused", {via = "menu"})
  check(last_toast(S, "through a shrine"), "the Escape menu says where the way out is")
  S.emit("game.dungeon.shrine_reached", {zone = 0, x = 12, y = 5})
  check(S.save_data["floors:1:1"]["0:2:shrines"][1].x == 12, "the first visit lights the shrine")
  check(S.panel == nil and any_toast(S, "press Square"), "and says how to pray there; no panel yet")
  S.game.player.status_remove = function(a) S.cured = (S.cured or 0) + 1 return {} end
  pray(S, {zone = 0, x = 12, y = 5})
  check(S.panel and S.panel.id == "vigil.shrine" and #S.panel.options == 5 and S.panel.cursor == 4, "Square in its water opens the panel, on Level up")

  -- Messages, online (stretch goal 17): a fifth card; others' messages read and rated, one's own left and taken back.
  check(S.panel.options[5].title == "Messages" and S.panel.options[5].lines[1].text == "None left here by others.",
        "a Messages card, none here yet")
  local spot = "vigil:d0:f2z0:shrine"
  for i, m in ipairs({{text = "Beware a mimic", good = 2, poor = 0}, {text = "Send me your Gilda", good = 9, poor = 0},
                      {text = "Try rolling", good = 0, poor = 5}, {text = "Try rolling", good = 0, poor = 0, place = "vigil:d0:f3z0:shrine"}}) do
    S.message_store[#S.message_store + 1] = {id = string.format("aaaaaaaaaaaa-%08x", i), place = m.place or spot, text = m.text,
                                             at = i, good = m.good, poor = m.poor, mine = false, rated = 0}
  end
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 5})
  check(S.panel.id == "vigil.msg_menu" and #S.panel.options == 2 and S.panel.options[2].title == "Read" and
        S.panel.options[2].lines[1] == "1 here, best rated first.",
        "only Vigil's own phrases show, not free text, nor one rated well under water, nor another shrine's")
  check(S.panel.subtitle:find("until you choose a shared folder", 1, true), "it says the messages stay in the save without a shared folder")
  S.emit("ui.choice_made", {id = "vigil.msg_menu", index = 2})
  check(S.panel.id == "vigil.msg_read" and S.panel.title == "\"Beware a mimic\"", "Read shows the message")
  S.emit("ui.choice_made", {id = "vigil.msg_read", index = 1})
  check(S.message_store[1].good == 3 and S.message_store[1].rated == 1, "Good rates it")
  S.messages_shared = true
  pray(S, {zone = 0, x = 12, y = 5})
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 5})
  check(S.panel.subtitle:find("anyone who shares your messages folder", 1, true), "with a shared folder, it says who can read them")
  S.emit("ui.choice_made", {id = "vigil.msg_menu", index = 1})
  check(S.panel.id == "vigil.msg_phrase" and #S.panel.options == 6 and S.panel.options[3].title == "Try ...", "Leave one: a phrase")
  S.emit("ui.choice_made", {id = "vigil.msg_phrase", index = 3})
  check(S.panel.id == "vigil.msg_word" and #S.panel.options == 6 and S.panel.options[6].title == "More", "then a word, five to a page")
  S.emit("ui.choice_made", {id = "vigil.msg_word", index = 6})
  check(S.panel.options[3].title == "Try rolling", "More: the next words")
  S.emit("ui.choice_made", {id = "vigil.msg_word", index = 3})
  local left = S.message_store[#S.message_store]
  check(left.mine and left.text == "Try rolling" and left.place == spot and last_toast(S, "Anyone who shares your messages folder"),
        "the message is left at this shrine, and the player told who reads it")
  pray(S, {zone = 0, x = 12, y = 5})
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 5})
  check(S.panel.options[#S.panel.options].title == "Take back", "one's own can be taken back")
  S.emit("ui.choice_made", {id = "vigil.msg_menu", index = #S.panel.options})
  check(S.message_store[#S.message_store].text ~= "Try rolling" or not S.message_store[#S.message_store].mine, "Take back removes it")
  S.emit("game.dungeon.shrine_reached", {zone = 0, x = 12, y = 5})
  S.tick(401)
  check(last_toast(S, "A message by the spring: \"Beware a mimic\" (3 found it good)"), "reaching the shrine, the best rated message comes up")
  S.panel = nil
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 2})
  check(last_toast(S, "no other shrine"), "nowhere to travel with one shrine lit")
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 1})
  check(S.healed == 2 and S.entered and S.entered.floor_id == 2 and S.entered.x == 12 and S.entered.y == 6,
        "Rest heals the party and builds the floor again, the player in front of the spring")
  check(S.cured == 5, "and cures every ailment (poison, curse, goo, freeze, stamina)")
  S.emit("game.dungeon.shrine_reached", {zone = 1, x = 19, y = 7})
  check(#S.save_data["floors:1:1"]["0:2:shrines"] == 2, "a second shrine is lit")
  S.emit("game.dungeon.shrine_reached", {zone = 1, x = 19, y = 7})
  check(#S.save_data["floors:1:1"]["0:2:shrines"] == 2, "once")
  pray(S, {zone = 1, x = 19, y = 7})
  S.map = nil
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 2})
  check(S.map and S.map.hint == "Travel" and #picks(S) == 1 and S.map.marks[picks(S)[1]].label == "Floor 3, zone 1",
        "Travel opens the map, the other lit shrine to pick")
  check(S.map.cursor and S.map.cursor.x == 12, "the cursor on it")
  local here_mark
  for _, m in ipairs(S.map.marks) do if m.label:find("you are here", 1, true) then here_mark = m end end
  check(here_mark and here_mark.pick == false and here_mark.x == 19, "the shrine you stand at is shown, not offered")
  S.emit("ui.map_choice", {id = "vigil.map", x = 12, y = 5, mark = picks(S)[1]})
  check(S.warped and S.warped.x == 12 and S.warped.y == 6, "one on this floor is a warp")
  check(S.warped.teleport == true, "in the escape light")
  enter(5, 600)
  S.entered = nil
  S.emit("game.dungeon.shrine_reached", {zone = 0, x = 4, y = 4})
  pray(S, {zone = 0, x = 4, y = 4})
  S.emit("ui.map_closed", {id = "vigil.map"})
  S.map = nil
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 2})
  check(S.map and S.map.pages == true and #picks(S) == 2 and S.map.subtitle:find("1 of 2", 1, true),
        "shrines on every floor of the dungeon are on its map's pages, opened on one with a shrine to pick")
  S.emit("ui.map_choice", {id = "vigil.map", x = 12, y = 5, mark = picks(S)[1]})
  check(S.entered and S.entered.floor_id == 2 and S.entered.y == 6, "one on another floor enters that floor")
  S.emit("ui.map_closed", {id = "vigil.map"})
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 3})
  check(S.transition == "chronicle:location:norune-village", "Leave goes to the dungeon's town")
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 5, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 5, back_floor = false, floor_seed = 4321, room_count = 10})
  check(S.save_data["floors:1:1"]["0:5:shrines"] == nil, "a floor built from a new seed has its shrines dark again")
  S.session = {kind = "sandbox", owner = "moonmod.roguelike"}
  S.emit("game.session.started", {owner = "moonmod.roguelike"})
  enter(4, 700)
  check(S.exits == "any", "in the Gauntlet: town by any way again")
end

-- 13. Floor scaling (W1.4) ----------------------------------------------------------------------------------------
print("13. Floor scaling (W1.4)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true, world_regions = false}}).load()
  local stats = {}
  S.attack, S.zone_now = 10, 0
  S.monsters = {}
  S.game.entities.query = function()
    return {entities = copy(S.monsters)}
  end
  S.game.entities.set_stats = function(a)
    assert(type(a.entity) == "string", "set_stats entity")
    assert(a.max_hp == nil or (math.type(a.max_hp) == "integer" and a.max_hp >= 1 and a.max_hp <= 1000000), "max_hp 1-1000000")
    assert(a.damage_scale == nil or (a.damage_scale >= 0 and a.damage_scale <= 100), "damage_scale 0-100")
    assert(a.reward_exp == nil or (math.type(a.reward_exp) == "integer" and a.reward_exp <= 32767), "reward_exp")
    stats[a.entity] = copy(a)
    return {}
  end
  S.game.player.get = function() return {hp = 70, max_hp = 70, weapon = {attack = S.attack}} end
  S.game.dungeons.zones_get = function() return {current = S.zone_now, floor_zones = 2} end
  local function monster(id, hp, revealed)
    return {entity_id = id, revealed = revealed ~= false, definition = {kind = 0}, health = {current = hp, maximum = hp},
            combat = {defense = 5, reward_exp = 10, reward_money = 20}}
  end
  local function enter(floor, seed)
    S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = floor, back_floor = false, floor_seed = seed, room_count = 10})
  end
  enter(0, 100)
  S.monsters = {monster("a", 40)}
  S.tick(30)
  check(stats.a == nil, "the first zone, with the starting weapon: monsters as the game made them")
  S.zone_now = 1
  S.monsters = {monster("a", 40), monster("b", 40), monster("c", 40, false)}
  S.tick(30)
  check(stats.a == nil, "a monster is scaled once, as it wakes")
  check(stats.b and stats.b.max_hp == 44 and stats.b.damage_scale == nil, "the second zone runs deeper: more life")
  check(stats.c == nil, "not before it is seen")
  enter(1, 200)
  S.zone_now, S.attack = 0, 30
  S.monsters = {monster("d", 40)}
  S.tick(30)
  -- base 3, player 21, level 19: 16 over
  check(stats.d and stats.d.max_hp == math.floor(40 * (1 + 0.12 * 16) + 0.5) and stats.d.damage_scale == 1.96 and stats.d.reward_exp == 18,
        "a weapon far past the zone raises its monsters to just under you")
  S.set("scaling_gap", 10)
  S.monsters = {monster("e", 40)}
  S.tick(30)
  check(stats.e and stats.e.max_hp == math.floor(40 * (1 + 0.12 * 8) + 0.5), "the gap is a setting")
  S.set("world_scaling", false)
  S.monsters = {monster("f", 40)}
  S.tick(30)
  check(stats.f == nil, "scaling can be turned off")
  S.set("world_scaling", true)
  enter(6, 300)
  S.monsters = {monster("g", 40)}
  S.tick(30)
  check(stats.g == nil, "only on Vigil World floors (not Demon Shaft's)")
end

-- 14. Regions (W1.3) ----------------------------------------------------------------------------------------------
print("14. Regions (W1.3)")
do
  local function last_toast(S, text) return S.toasts[#S.toasts] ~= nil and S.toasts[#S.toasts]:find(text, 1, true) ~= nil end
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}}).load()
  local function enter(dungeon, floor, seed)
    S.next_seed, S.arrival = nil, nil
    S.emit("game.dungeon.generating", {dungeon_id = dungeon, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = dungeon, floor_id = floor, back_floor = false, floor_seed = S.next_seed or seed, room_count = 18})
  end
  enter(0, 0, 900)
  local z = S.zones
  check(z and #z.zones == 15 and z.zones[1].source_floor == 0 and z.zones[14].source_floor == 13 and z.exit_floor == 15,
        "Divine Beast Cave is one map, each floor a zone, Dran's floor 15 its last")
  check(z.zones[4].rooms == 2 and z.zones[4].source_floor == 2 and z.zones[8].source_floor == 6 and z.smoke and #z.smoke == 3 and
        z.smoke[1] == 3 and z.smoke[2] == 7 and z.smoke[3] == 14 and z.open == nil and z.zones[15].rooms == 2,
        "its story floors (4 and 8) and Dran's 15 are small zones behind smoke, with the monsters of the floor before")
  check(z.zones[11].rooms ~= 2 and z.zones[11].source_floor == 10, "floor 11 (Xiao's only) is an ordinary zone")
  check(z.sanctuary == true and z.shrines == true, "its shrines are sanctuaries: no monster steps near one")
  check(S.arrival == nil, "come in by its first floor: start at the stairs")
  check(S.save_data["floors:1:1"]["0:0"] == 900, "the region is kept under its first floor")
  S.emit("game.dungeon.zone_entered", {zone = 2, previous = 1, zones = 14, floor_id = 2})
  check(last_toast(S, "floor 3"), "walking into a zone names its floor")
  S.emit("game.dungeon.shrine_reached", {zone = 2, x = 30, y = 20})
  pray(S, {zone = 2, x = 30, y = 20})
  check(S.panel and S.panel.subtitle == "Floor 3", "its shrine is named by its floor")
  enter(0, 2, 1234)
  check(S.next_seed == 900 and S.arrival and S.arrival.zone == 2, "come in by floor 3: the same map, starting at floor 3's zone")
  check(S.arrival.teleport == true, "by teleport, not the stairs")
  check(S.save_data["floors:1:1"]["0:2"] == nil, "floor 3 keeps nothing of its own")
  pray(S, {zone = 2, x = 30, y = 20})
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 1})
  check(S.entered and S.entered.floor_id == 2 and S.entered.x == 30 and S.entered.y == 21, "Rest builds the region again, waking at the shrine")
  check(S.entered.teleport == true, "a rest arrives by teleport")
  enter(0, 2, 1234)
  check(S.arrival == nil, "a rest says where it arrives itself")

  -- the smoke over floor 4
  S.entered = nil
  S.emit("game.dungeon.smoke_touched", {zone = 3, x = 9, y = 40})
  check(S.panel and S.panel.id == "vigil.smoke" and S.panel.subtitle == "Floor 4 lies beyond" and S.panel.cursor == 2,
        "a smoke gate offers the floor beyond, Stay first")
  S.emit("ui.choice_made", {id = "vigil.smoke", index = 2})
  check(S.entered == nil, "staying stays")
  S.emit("game.dungeon.smoke_touched", {zone = 3, x = 9, y = 40})
  S.emit("ui.choice_made", {id = "vigil.smoke", index = 1})
  check(S.entered and S.entered.floor_id == 3 and S.entered.x == nil, "going through enters floor 4 as the game has it")
  check(S.story_exits and S.story_exits.title == "LEAVE THROUGH THE SMOKE?", "its key gate is a smoke door out")
  S.entered = nil
  S.emit("game.dungeon.story_exit", {left = false, dungeon_id = 0, floor_id = 3})
  check(S.entered == nil, "staying at the smoke door stays")
  S.emit("game.dungeon.story_exit", {left = true, dungeon_id = 0, floor_id = 3})
  check(S.entered and S.entered.floor_id == 4 and S.entered.x == nil, "leaving goes on to floor 5")
  -- floor 4 is a map of the game's own (no generated event); leaving it builds floor 5
  enter(0, 4, 4321)
  check(S.story_exits == nil, "back on the map, no smoke door")
  check(S.next_seed == 900 and S.arrival and S.arrival.zone == 4, "its way down comes back to the map, at floor 5's zone")
  check(has(S.zones.open, 3) and has(S.zones.open, 4) and #S.zones.smoke == 2 and S.zones.smoke[1] == 7,
        "the smoke over floor 4 is gone for good, its small zone walked through")
  check(any_toast(S, "smoke over floor 4 clears"), "and says so")
  check(S.save_data["floors:1:1"].smoke_in == nil and S.save_data["floors:1:1"]["smoke:0"][1] == 3, "kept with the save")
  enter(0, 3, 977)
  check(S.zones == nil, "floor 4 itself, from the town's floor list, is the game's own floor")
  enter(0, 7, 970)
  check(S.zones == nil, "so is Seda's floor 8")

  -- travel: more lit shrines than a panel holds
  enter(0, 0, 900)
  for zone = 0, 5 do S.emit("game.dungeon.shrine_reached", {zone = zone, x = 10 + zone, y = 5}) end
  pray(S, {zone = 0, x = 10, y = 5})
  S.map = nil
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 2})
  check(S.map and #picks(S) == 5 and S.map.marks[picks(S)[1]].label == "Floor 2", "every lit shrine of the map is a pick on it, by floor")
  local far
  for _, i in ipairs(picks(S)) do if S.map.marks[i].x == 15 then far = i end end
  S.emit("ui.map_choice", {id = "vigil.map", x = 15, y = 5, mark = far})
  check(S.warped and S.warped.x == 15 and S.warped.y == 6, "and a shrine on it is a warp on this map")
  S.emit("ui.map_closed", {id = "vigil.map"})

  enter(0, 14, 960)
  check(S.zones == nil or S.zones.zones[1].source_floor == nil, "on Dran's floor itself: the game's own, not the map")
  enter(1, 0, 400)
  check(#S.zones.zones == 17 and S.zones.zones[16].source_floor == 15 and S.zones.exit_floor == 17 and S.zones.smoke[1] == 3 and S.zones.smoke[2] == 8 and
        S.zones.smoke[3] == 16 and #S.zones.smoke == 3 and S.zones.zones[12].rooms ~= 2,
        "Wise Owl Forest: floors 1-17 are one map, Goro's floor 12 an ordinary zone, the boss's 17 behind smoke at its end")
  enter(5, 17, 410)
  check(#S.zones.zones == 13 and S.zones.zones[1].source_floor == 12 and S.zones.exit_floor == 25 and S.arrival and S.arrival.zone == 5 and
        #S.zones.smoke == 6 and S.zones.zones[11].source_floor == 17,
        "Gallery of Time is two maps (floors 1-12 and 13-25); coming in by floor 18 starts at its zone")
  enter(6, 3, 420)
  check(S.zones == nil or S.zones.zones[1].source_floor == nil, "Demon Shaft has no regions")
  S.set("world_regions", false)
  enter(0, 5, 990)
  check(#S.zones.zones == 2 and S.zones.exit_floor == nil, "regions can be turned off")
end

-- 15. The map (W2.1) ----------------------------------------------------------------------------------------------
print("15. The map (W2.1)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}}).load()
  local pressed, seen_ask, waypoint, snapshot = {}, nil, nil, {seed = 900, width = 96, cells = "a9216", seen = 12}
  S.game.input.consume = function(a)
    local p = pressed[a.id] == true
    pressed[a.id] = nil
    return {pressed = p}
  end
  S.game.dungeons.map_snapshot = function() return copy(snapshot) end
  S.game.dungeons.set_seen = function(a)
    assert(math.type(a.seed) == "integer" and type(a.cells) == "string", "set_seen takes {seed, cells}")
    seen_ask = copy(a)
    return {applied = true}
  end
  S.game.dungeons.set_waypoint = function(a)
    assert(next(a) == nil or (math.type(a.x) == "integer" and math.type(a.y) == "integer"), "set_waypoint takes {x, y} or {}")
    waypoint = next(a) and copy(a) or false
    return {}
  end
  S.game.dungeons.zones_get = function()
    return {current = 0, shrines = {{zone = 0, x = 10, y = 4}, {zone = 1, x = 20, y = 4}}, gates = {{zone = 0, x = 15, y = 6, locked = true}}}
  end
  S.game.ui.map_open = function(a)
    for k in pairs(a) do
      assert(({id = 1, title = 1, subtitle = 1, cells = 1, marks = 1, cursor = 1, waypoints = 1, hint = 1, pages = 1})[k], "map_open field " .. k)
    end
    for _, m in ipairs(a.marks or {}) do
      for k in pairs(m) do assert(({x = 1, y = 1, kind = 1, label = 1, pick = 1})[k], "mark field " .. k) end
    end
    S.map = copy(a)
    return {id = a.id}
  end
  S.where = "dungeon"
  S.game.world.get = function() return {context = S.where, area_id = 0} end
  local function enter(floor, seed)
    S.next_seed = nil
    S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = floor, back_floor = false, floor_seed = S.next_seed or seed, room_count = 35})
    -- the game builds the floor's back floor with it, the player still on the main floor
    S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = floor, back_floor = true, floor_seed = seed + 1, room_count = 12})
  end
  local function press(id) pressed[id or "open_map_select"] = true; S.tick(1) end
  local function kind_of(kind) local n = 0 for _, m in ipairs(S.map.marks or {}) do if m.kind == kind then n = n + 1 end end return n end

  enter(0, 900)
  S.tick(1)
  check(S.bindings.open_map and S.bindings.open_map[1] == "M" and S.bindings.open_map[2] == "Gamepad:leftstick" and
        S.bindings.open_map_select[1] == "Gamepad:back", "Select, L3 or M opens the map")
  press()
  check(S.map and S.map.cells == nil and S.map.title == "Divine Beast Cave" and S.map.subtitle == "Floors 1-15", "in a dungeon: the place you're on (the whole dungeon)")
  check(kind_of("shrine") == 2 and kind_of("gate") == 1 and S.map.waypoints == true, "its shrines and locked gates (shown once found) and a waypoint")
  check(S.save_data["floors:1:1"]["0:0:map"].cells == "a9216", "what you've seen is kept with the place")
  S.emit("ui.map_waypoint", {id = "vigil.map", x = 7, y = 8, set = true})
  check(S.save_data["floors:1:1"]["0:0:waypoint"].x == 7, "the waypoint is kept")
  S.emit("ui.map_closed", {id = "vigil.map"})
  S.map = nil
  press()
  check(S.map == nil, "the press that closed it doesn't open it again")
  S.tick(20)
  S.emit("game.dungeon.shrine_reached", {zone = 0, x = 10, y = 4})
  press()
  check(kind_of("shrine_lit") == 1 and kind_of("shrine") == 1, "a lit shrine shows lit")
  S.emit("ui.map_closed", {id = "vigil.map"})

  enter(0, 900)
  check(seen_ask and seen_ask.seed == 900 and seen_ask.cells == "a9216", "the next visit: what you saw is seen again")
  check(waypoint and waypoint.x == 7 and waypoint.y == 8, "and the waypoint is back on the minimap")
  enter(7, 970)
  check(waypoint == false, "a floor without one has none")

  S.where = "georama"
  S.map = nil
  S.tick(20)
  press()
  check(S.map == nil, "in town Select stays the game's (Georama)")
  press("open_map")
  check(S.map and S.map.cells == "a9216" and S.map.hint == "Travel" and not S.map.pages, "in town: the kept map")
  check(S.map.cursor and S.map.cursor.x == 10, "the cursor starts on a lit shrine")
  local lit
  for i, m in ipairs(S.map.marks) do if m.kind == "shrine_lit" then lit = i end end
  check(lit and S.map.marks[lit].pick == true, "which Cross can take")
  S.emit("ui.map_choice", {id = "vigil.map", x = 10, y = 4, mark = lit})
  check(S.entered and S.entered.dungeon_id == 0 and S.entered.floor_id == 0 and S.entered.x == 10 and S.entered.y == 5,
        "and travels there from town")
  S.emit("ui.map_closed", {id = "vigil.map"})

  S.where = "dungeon"
  enter(8, 950)
  snapshot = {seed = 900, width = 96, cells = "b9216", seen = 30}
  S.tick(300)
  check(S.save_data["floors:1:1"]["0:0:map"] and S.save_data["floors:1:1"]["0:0:map"].cells == "b9216", "the map is kept as you walk, floor 9 on the same map")
  S.where = "georama"
  S.tick(20)
  press("open_map")
  check(S.map.pages ~= true and S.map.cells == "b9216" and S.map.subtitle:find("Floors 1-15", 1, true),
        "the town shows the dungeon's one map, all you've seen on it")
  S.emit("ui.map_closed", {id = "vigil.map"})

  -- a save kept by the old four-zone layout: the region starts again as new
  local G = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  G.save_data["floors:1:1"] = {["0:0"] = 900, ["0:0:chests"] = {1, 2}, ["0:0:shrines"] = {{zone = 0, x = 3, y = 3}}}
  G.load()
  G.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = false})
  check(G.next_seed == nil and G.next_chests == nil, "a place built by an older layout isn't built from its old seed")
  G.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 1111, room_count = 35})
  local kept = G.save_data["floors:1:1"]
  check(kept["0:0"] == 1111 and kept["0:0:chests"] == nil and kept["0:0:shrines"] == nil and tostring(kept["0:0:shape"]):find("^v3:region"),
        "it is new again, its chests closed")
  S.where = "dungeon"
  S.game.world.get = function() return {context = "dungeon", area_id = 0, back_floor = true} end
  S.map = nil
  S.tick(20)
  press()
  check(S.map and S.map.subtitle == "Back floor" and S.map.waypoints == false, "on a back floor the map says so")
  S.emit("ui.map_closed", {id = "vigil.map"})
  S.game.world.get = function() return {context = S.where, area_id = 0} end
  S.set("world_map", false)
  S.map = nil
  S.tick(20)
  press()
  check(S.map == nil, "the map can be turned off")
end

-- 16. Waking at the last shrine (W1.2) ---------------------------------------------------------------------------
print("16. Waking at the last shrine")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}}).load()
  S.where = "dungeon"
  S.game.world.get = function() return {context = S.where, area_id = 0} end
  local function enter(dungeon, floor, seed)
    S.next_seed, S.arrival, S.where = nil, nil, "dungeon"
    S.emit("game.dungeon.generating", {dungeon_id = dungeon, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = dungeon, floor_id = floor, back_floor = false, floor_seed = S.next_seed or seed, room_count = 35})
    S.emit("game.dungeon.generated", {dungeon_id = dungeon, floor_id = floor, back_floor = true, floor_seed = seed + 1, room_count = 12})
  end
  local function to_town() S.where = "georama" S.emit("game.world.location_changed", {context = "georama", area_id = 0}) end

  enter(0, 0, 900)
  check(S.arrival == nil, "the first time: the entrance")
  S.emit("game.dungeon.shrine_reached", {zone = 3, x = 40, y = 12})
  check(S.save_data["floors:1:1"]["rest:0"] and S.save_data["floors:1:1"]["rest:0"].zone == 3, "the shrine reached is kept as the one to wake at")
  to_town()
  enter(0, 0, 900)
  check(S.arrival == nil, "walking back in from town: the entrance, floor 1 (the shrines are reached from the map)")
  enter(0, 7, 970)
  check(S.arrival == nil, "going on to Seda's floor: its own start")
  to_town()
  enter(0, 8, 950)
  check(S.arrival and S.arrival.zone == 8, "from town by a later floor of the same map: that floor's zone")
  to_town()
  enter(1, 0, 400)
  check(S.arrival == nil, "another dungeon: its own start")

  enter(0, 0, 900)
  S.entered = nil
  S.emit("game.dungeon.defeated", {dungeon_id = 0, floor_id = 2})
  S.tick(60)
  check(S.entered == nil, "knocked out: nothing while still in the dungeon")
  to_town()
  S.tick(30)
  check(S.entered and S.entered.dungeon_id == 0 and S.entered.floor_id == 0 and S.entered.x == 40 and S.entered.y == 13,
        "then from town on to the shrine, the place built again")
  check(S.toasts[#S.toasts]:find("wake", 1, true), "and says so")
  enter(0, 0, 900)
  check(S.arrival == nil, "the wake says where it arrives itself")
  S.entered = nil
  S.tick(90)
  check(S.entered == nil, "and happens once")

  enter(1, 0, 400)
  S.emit("game.dungeon.defeated", {dungeon_id = 1, floor_id = 3})
  to_town()
  S.tick(60)
  check(S.entered == nil, "no shrine reached in that dungeon: the town, as ever")

  -- The Gilda a knockout takes lies where the party fell.
  local at, added = {x = 160 * 12, y = 0, z = 160 * 9 - 70}, 0
  local abs = {dagger = 40}
  S.game.player.get = function()
    return S.where == "dungeon" and {hp = 1, character = "toan", position = copy(at), weapon = {id = "dagger", slot = 0}} or {hp = 0}
  end
  S.game.weapons = {
    abs_get = function(a) return abs[a.id] and {abs = abs[a.id], abs_max = 100} or nil, {code = "not_found"} end,
    abs_add = function(a)
      assert(math.type(a.amount) == "integer" and a.amount ~= 0 and a.character == "toan", "abs_add shape")
      if not abs[a.id] then return nil, {code = "not_found"} end
      local before = abs[a.id]
      abs[a.id] = math.max(0, before + a.amount)
      return {abs = abs[a.id], added = abs[a.id] - before}
    end,
  }
  S.game.economy = {add = function(a)
    assert(math.type(a.amount) == "integer" and a.amount >= 1 and a.amount <= 32767, "economy.add takes 1-32767")
    added = added + a.amount
    return {amount = added}
  end}
  enter(0, 0, 900)
  S.emit("game.dungeon.defeated", {dungeon_id = 0, floor_id = 0, gilda = 301})
  S.tick(30)
  check(added == 0, "not taken back while the party still lies there")
  local fallen = S.save_data["floors:1:1"].fallen
  check(fallen and fallen.gilda == 151 and fallen.x == 12 and fallen.y == 9 and fallen.key == "0:0", "the half the game takes (151 of 301) lies where you fell")
  check(abs.dagger == 0 and fallen.abs and fallen.abs.amount == 40, "and the weapon's unspent ABS with it")
  to_town()
  S.tick(30)
  check(S.toasts[#S.toasts]:find("where you fell", 1, true), "waking says where it is")
  enter(0, 0, 900)
  at = {x = 160 * 3, y = 0, z = 160 * 3}
  S.tick(30)
  check(added == 0, "away from it: still there")
  S.map = nil
  S.game.ui.map_open = function(a) S.map = copy(a) return {id = a.id} end
  S.game.dungeons.zones_get = function() return {current = 0, shrines = {}, gates = {}} end
  S.game.input.consume = function(a) return {pressed = a.id == "open_map"} end
  S.tick(1)
  local marked
  for _, m in ipairs(S.map and S.map.marks or {}) do if m.kind == "mark" and m.x == 12 then marked = m end end
  check(marked and marked.label:find("151", 1, true) and marked.label:find("40 ABS", 1, true), "the map shows it")
  S.emit("ui.map_closed", {id = "vigil.map"})
  S.game.input.consume = function() return {pressed = false} end
  S.tick(30)
  at = {x = 160 * 12 + 40, y = 0, z = 160 * 9 + 60}
  S.tick(30)
  check(added == 0, "a cell's middle is not enough: the spot you fell on")
  at = {x = 160 * 12 + 40, y = 0, z = 160 * 9 - 30}
  S.tick(30)
  check(S.dropped and S.dropped.amount == 151 and S.dropped.x == 160 * 12 and S.dropped.z == 160 * 9 - 70, "the Gilda lies there as a pile, on the corner map too")
  check(added == 0 and abs.dagger == 40 and S.save_data["floors:1:1"].fallen == nil, "walk onto it: the pile gives the Gilda, Vigil the ABS")
  S.emit("game.dungeon.defeated", {dungeon_id = 0, floor_id = 0, gilda = 100})
  S.emit("game.dungeon.defeated", {dungeon_id = 0, floor_id = 0, gilda = 40})
  check(S.save_data["floors:1:1"].fallen.gilda == 20, "fall again first and the old one is gone")
  -- Where you died (stretch goal 14): the last eight deaths stay marked on the map.
  local deaths = S.save_data["floors:1:1"].deaths
  check(deaths and #deaths >= 3 and deaths[1].key == "0:0", "every death is kept, newest first")
  for _ = 1, 6 do S.emit("game.dungeon.defeated", {dungeon_id = 0, floor_id = 0, gilda = 0}) end
  check(#S.save_data["floors:1:1"].deaths == 8, "up to eight")
  local was = at
  at = {x = 160 * 4, y = 0, z = 160 * 6}
  S.emit("game.dungeon.defeated", {dungeon_id = 0, floor_id = 0, gilda = 0})
  at = was
  S.emit("game.dungeon.defeated", {dungeon_id = 0, floor_id = 0, gilda = 0})
  S.map = nil
  S.game.input.consume = function(a) return {pressed = a.id == "open_map"} end
  S.tick(1)
  local old
  for _, m in ipairs(S.map and S.map.marks or {}) do if m.kind == "mark" and m.x == 4 and m.y == 6 then old = m end end
    local at_spot = 0
  for _, m in ipairs(S.map and S.map.marks or {}) do if m.kind == "mark" and m.x == 12 and m.y == 9 then at_spot = at_spot + 1 end end
  check(at_spot == 1, "one mark a spot, however often you fell there")
  check(old and old.label == "You fell here before", "an older death is marked on the map")
  S.emit("ui.map_closed", {id = "vigil.map"})
  S.game.input.consume = function() return {pressed = false} end
end

-- 17. Levelling at a shrine (W1.2) ------------------------------------------------------------------------------
print("17. Levelling at a shrine")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  local ranks, sheet, opened, gilda, max_hp = {}, nil, 0, 1000, {toan = 100, xiao = 80}
  local at = {x = 160 * 10, y = 0, z = 160 * 5}
  S.game.skills = {
    register = function(a)
      assert(a.id == "shrine" and #a.skills == 3, "the shrine tree")
      for _, k in ipairs(a.skills) do for f in pairs(k) do assert(({id = 1, title = 1, description = 1, max_rank = 1})[f], "skill field " .. f) end end
      return {id = "moonmod.vigil:shrine"}
    end,
    set_rank = function(a) ranks[a.id] = a.rank return {rank = a.rank} end,
  }
  S.game.ui.sheet_set = function(a) sheet = copy(a) return {} end
  S.game.ui.sheet_open = function() opened = opened + 1 return {} end
  S.game.economy = {
    get = function() return {amount = gilda} end,
    spend = function(a)
      assert(math.type(a.amount) == "integer" and a.amount >= 1 and a.amount <= 32767, "economy.spend takes 1-32767")
      if a.amount > gilda then return nil, {code = "failed", message = "not enough"} end
      gilda = gilda - a.amount
      return {amount = gilda}
    end,
  }
  S.game.characters = {get = function(a) return max_hp[a.id] and {id = a.id, max_hp = max_hp[a.id]} or nil end}
  S.game.player.set = function(a)
    assert(math.type(a.max_hp) == "integer" and a.max_hp >= 1 and a.max_hp <= 999 and type(a.character) == "string", "player.set max_hp")
    max_hp[a.character] = a.max_hp
    return {max_hp = a.max_hp}
  end
  S.game.player.get = function() return {hp = 50, character = "toan", position = copy(at)} end
  S.load()
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 900, room_count = 35})
  local function train(skill) S.emit("skills.train_requested", {id = "moonmod.vigil:shrine." .. skill}) end

  train("vigour")
  check(gilda == 1000 and S.toasts[#S.toasts]:find("only at a shrine", 1, true), "away from a shrine: no levelling")
  S.emit("game.dungeon.shrine_reached", {zone = 0, x = 10, y = 4})
  pray(S, {zone = 0, x = 10, y = 4})
  check(S.panel.options[4].title == "Level up" and S.panel.options[4].lines[2].text:find("150 Gilda", 1, true), "the panel's fourth card levels up: 150 Gilda")
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 4})
  check(opened == 1 and sheet and sheet.trees[1] == "shrine" and sheet.lines[1] == "Level 0", "it opens the tree on the Journal's Character page")
  train("vigour")
  check(gilda == 850 and ranks["moonmod.vigil:shrine.vigour"] == 1, "Vigour 1 for 150 Gilda")
  check(max_hp.toan == 105 and max_hp.xiao == 85, "the whole party gains 5 max HP")
  check(sheet.lines[1] == "Level 1" and sheet.lines[2]:find("170", 1, true), "the page shows the next level's cost")
  local refill = S.tuning.gauge_refill
  train("endurance")
  check(gilda == 680 and math.abs(S.tuning.gauge_refill - refill * 1.1) < 1e-6, "Endurance: the gauge refills 10% faster")
  train("guard")
  check(ranks["moonmod.vigil:shrine.guard"] == 1 and gilda == 680 - 190, "Guard 1")
  check(S.save_data["floors:1:1"].tree.vigour == 1 and S.save_data["floors:1:1"].tree.hp.toan == 1, "kept with the save")
  gilda = 10
  train("vigour")
  check(ranks["moonmod.vigil:shrine.vigour"] == 1 and S.toasts[#S.toasts]:find("costs", 1, true), "not enough Gilda: nothing bought")

  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 900, room_count = 35})
  check(max_hp.toan == 105, "the next floor doesn't give the HP again")

  -- a fresh load of the same save: the ranks come back
  local G = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  G.save_data["floors:1:1"] = copy(S.save_data["floors:1:1"])
  local granks = {}
  G.game.skills = {register = function() return {} end, set_rank = function(a) granks[a.id] = a.rank return {} end}
  G.load()
  G.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 900, room_count = 35})
  check(granks["moonmod.vigil:shrine.vigour"] == 1 and granks["moonmod.vigil:shrine.guard"] == 1, "a loaded save shows its ranks")
end

-- 18. Vigil World belongs to a save ----------------------------------------------------------------------------
print("18. Vigil World belongs to a save")
do
  local function enter(S, floor)
    S.zones = nil
    S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = floor, back_floor = false, floor_seed = 900 + floor, room_count = 35})
  end
  local A = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  A.game.dungeons.list = function() return {{id = "divine-beast-cave", deepest_floor_reached = 4}} end
  A.load()
  enter(A, 0)
  check(A.zones == nil and A.save_data["floors:1:1"].world == false, "a story save with progress and no Vigil World stays a normal save")

  local B = new_game({slot = {slot_id = 1, slot_generation = 1}})
  B.save_data["floors:1:1"] = {["0:0"] = 7265, ["0:0:gates"] = {1}, ["0:0:shrines"] = {{zone = 0, x = 3, y = 5}}}
  B.load()
  enter(B, 0)
  check(B.save_data["floors:1:1"].world == true and B.zones ~= nil, "a save already holding Vigil World places is one, whatever the setting")

  local C = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  C.game.dungeons.list = function() return {{id = "divine-beast-cave", deepest_floor_reached = 0}} end
  C.load()
  enter(C, 0)
  check(C.save_data["floors:1:1"].world == true and C.zones ~= nil, "a new game takes the setting")
  C.emit("game.world.location_changed", {context = "georama"})
  check(C.floor_select == false, "a Vigil World save's dungeon entrance has no floor menu")
  check(C.quick_passage == true, "and goes between town and dungeon with no loading card")
  A.emit("game.world.location_changed", {context = "georama"})
  check(A.floor_select == true, "a normal save keeps the floor menu")
  check(A.quick_passage == false, "and its loading card")
end

print("19. The map's key (playtest 2)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}}).load()
  local held, gilda, KEY = 0, 0, "chronicle:item:195"
  S.game.dungeons.back_floor_get = function() return {gate_key = {id = KEY, native_item_no = 195, count = held}} end
  S.game.items = S.game.items or {}
  S.game.items.give = function(a) held = held + a.count return {added = true} end
  S.game.items.remove = function(a) held = held - a.count return {removed = true} end
  S.game.economy = S.game.economy or {}
  S.game.economy.add = function(a) gilda = gilda + a.amount return {amount = gilda} end
  local function enter(back)
    S.zones = nil
    S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = back})
    S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = back, floor_seed = 900, room_count = 35})
  end
  local function pick() S.emit("game.item_picked_up", {id = KEY, kind = "item", native_item_no = 195, count = 1}) end
  local function tag() return (S.save_data["floors:1:1"] or {})["key:0"] end
  enter(false)
  held = 1
  pick()
  check(tag() == "have" and held == 1 and gilda == 0, "the map's key, found once, is kept with the save", tostring(tag()))
  held = 0
  enter(false)
  check(held == 1, "taken by a knockout or a trip to town: given back on the next visit", held)
  held = 2
  pick()
  check(held == 1 and gilda == 300, "a second one is paid out in Gilda", held .. " " .. gilda)
  enter(true)
  check(tag() == "used", "used once the back floor is entered", tostring(tag()))
  held = 0
  enter(false)
  check(held == 0, "a used key isn't given back", held)
  held = 1
  pick()
  check(held == 0 and gilda == 600, "and any found after is Gilda", held .. " " .. gilda)
end

print("20. A region that grew keeps its gates and shrines (playtest 2)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  S.save_data["floors:1:1"] = {world = true, ["0:0"] = 777, ["0:0:shape"] = "v3:region:0-13:5", ["0:0:gates"] = {1, 2, 5},
    ["0:0:shrines"] = {{zone = 2, x = 1, y = 1, label = 2}, {zone = 9, x = 2, y = 2, label = 9}}, ["0:0:chests"] = {4},
    ["0:0:map"] = {seed = 777, cells = {}}, ["rest:0"] = {floor_id = 0, zone = 2, x = 1, y = 1}}
  S.load()
  S.game.dungeons.zones_get = function()
    return {current = 0, shrines = {{zone = 2, x = 40, y = 41}, {zone = 9, x = 50, y = 51}}, gates = {}, floor_zones = 15}
  end
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = false})
  check(S.zones and S.zones.open and S.zones.open[1] == 1 and S.zones.open[3] == 5, "the gates opened before are asked open again")
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 901, room_count = 40})
  local kept = S.save_data["floors:1:1"]
  check(kept["0:0"] == 901 and kept["0:0:shape"] == "v3:region:0-14:5", "the bigger map is a new place")
  check(kept["0:0:chests"] == nil and kept["0:0:map"] == nil and kept["0:0:regrown"] == nil, "its chests and map start again")
  check(kept["0:0:gates"] and #kept["0:0:gates"] == 3, "its gates stay open")
  local sh = kept["0:0:shrines"]
  check(sh and #sh == 2 and sh[1].x == 40 and sh[2].y == 51 and sh[2].label == 9, "its lit shrines stay lit, where they stand now")
  check(kept["rest:0"].x == 40 and kept["rest:0"].y == 41, "and the shrine rested at too")
end

print("21. The Fairy King stands at the shrines of his floors and talks there (O1)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  S.save_data["floors:1:1"] = {world = true}
  S.load()
  check(S.npc_models and S.npc_models[1].pack == "dun/d01/event/e28c03c.chr" and S.npc_models[1].dungeon_id == 0,
        "his model loads with Divine Beast Cave's map")
  check(S.resource_overrides and S.resource_overrides["dun/script/d01/event.stb"] == "resources/dun/d01_event.stb",
        "the cave's event script with his talks")
  check(file_exists(MOD_DIR .. "/resources/dun/d01_event.stb"), "which ships with the mod")
  S.game.dungeons.zones_get = function()
    return {current = 0, shrines = {{zone = 0, x = 5, y = 5}, {zone = 2, x = 20, y = 8}, {zone = 4, x = 30, y = 9}, {zone = 5, x = 40, y = 9}},
            gates = {}, floor_zones = 15}
  end
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 555, room_count = 40})
  local m = S.npc_marks or {}
  check(#m == 2 and m[1].x == 21 and m[1].y == 9 and m[2].x == 31 and m[2].npc == 1,
        "beside the shrines of floors 3 and 5 only", #m)
  local pg, ic = S.game.player.get, S.game.input.consume
  S.game.player.get = function() return {hp = 50, character = "toan", position = {x = 160 * 21 - 60, y = 0, z = 160 * 9}} end
  S.game.input.consume = function(a) return {pressed = a.id == "pray"} end
  S.tick(5)
  S.game.player.get, S.game.input.consume = pg, ic
  check(S.played == 191, "Square beside him plays floor 3's scene", S.played)
  check(S.save_data["floors:1:1"]["king:0:2"] == true, "once: it is kept with the save")
  check(S.npc_marks and #S.npc_marks == 0, "he is gone while it plays")
  S.entered = nil
  S.emit("game.dungeon.event_ended", {program = 191, dungeon_id = 0, floor_id = 0})
  check(S.entered and S.entered.floor_id == 0 and S.entered.x == 20 and S.entered.y == 9 and S.entered.teleport,
        "afterwards the floor is built again in front of that shrine")
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 555, room_count = 40})
  check(#S.npc_marks == 1 and S.npc_marks[1].x == 31, "then only floor 5's King is left")
  S.entered = nil
  S.emit("game.dungeon.event_ended", {program = 192, dungeon_id = 0, floor_id = 0})
  check(S.entered == nil, "a scene Vigil didn't start doesn't move the player")
end

print("22. Walked in through the town's door: the King's opening stands ahead instead of playing (O2)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  S.save_data["floors:1:1"] = {world = true}
  S.load()
  local flags = {[103] = false}
  S.game.world.story_flag_get = function(a) return {id = a.id, value = flags[a.id] or false} end
  S.game.world.story_flag_set = function(a) flags[a.id] = a.value return {id = a.id, value = a.value, changed = true} end
  S.game.dungeons.zones_get = function() return {current = 0, shrines = {{zone = 0, x = 5, y = 5}}, gates = {}, floor_zones = 15} end
  S.emit("game.world.location_changed", {context = "georama", area_id = 0})
  check(flags[103] == true and S.save_data["floors:1:1"]["king_held:0"] == true,
        "in town the opening's flag is set, so the floor's opening script passes it by, and kept as held")
  -- built unseen as the town loads (the cave seen through the door), then walked into: he waits for the dungeon
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = false, prebuild = true})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 777, room_count = 40, prebuild = true})
  S.tick(45)
  check(#(S.npc_marks or {}) == 0, "built from town, he doesn't stand while the party is still in town")
  S.emit("game.dungeon.resumed", {dungeon_id = 0, floor_id = 0})
  local pg = S.game.player.get
  -- standing at cell (10, 20), facing +z (heading 0)
  S.game.player.get = function() return {hp = 50, character = "toan", position = {x = 1600, y = 0, z = 3200}, heading = 0} end
  S.tick(45)
  local m = S.npc_marks or {}
  check(#m == 1 and m[1].x == 10 and m[1].y == 22 and m[1].facing == 2, "once walked in, he stands two cells ahead, facing the party", #m)
  local ic = S.game.input.consume
  S.game.player.get = function() return {hp = 50, character = "toan", position = {x = 1600, y = 0, z = 160 * 22 - 60}, heading = 0} end
  S.game.input.consume = function(a) return {pressed = a.id == "pray"} end
  S.tick(5)
  S.game.player.get, S.game.input.consume = pg, ic
  check(S.played == 190, "Square beside him plays the opening", S.played)
  check(S.save_data["floors:1:1"]["king:0:0"] == true and S.save_data["floors:1:1"]["king_held:0"] == nil, "once, kept with the save")
  S.entered = nil
  S.emit("game.dungeon.event_ended", {program = 190, dungeon_id = 0, floor_id = 0})
  check(S.entered and S.entered.x == 10 and S.entered.y == 20, "afterwards the floor is built again where the party stood")
  S.emit("game.world.location_changed", {context = "georama", area_id = 0})
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 0, back_floor = false, floor_seed = 777, room_count = 40})
  S.emit("game.world.location_changed", {context = "dungeon", area_id = 0})
  S.tick(45)
  check(#(S.npc_marks or {}) == 0, "heard once, he isn't there again")
  -- out to town and back in through the door: the floor is gone back to as it was left, not built
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 0, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 1, floor_id = 0, back_floor = false, floor_seed = 555, room_count = 10})
  S.emit("game.world.location_changed", {context = "georama", area_id = 0})
  S.emit("game.dungeon.resumed", {dungeon_id = 0, floor_id = 0})
  S.emit("game.dungeon.zone_gate_opened", {zone = 1, key = "chronicle:item:222", x = 18, y = 9})
  local gates = S.save_data["floors:1:1"]["0:0:gates"]
  check(gates and gates[1] == 1, "the resumed floor is the one the party is on", gates)
end

print("23. The road between the towns (L6)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true}})
  S.save_data["floors:1:1"] = {world = true}
  S.load()
  S.emit("game.world.location_changed", {context = "georama", area_id = 1})
  check(S.roads == true, "with Vigil World, the towns' gates are roads, not the world map")
  S.emit("game.town.road", {town_id = 1, location_id = "chronicle:location:matataki-village"})
  local p = S.panel
  check(p and p.id == "vigil.road" and #p.options == 3 and p.options[1].title == "Norune Village" and p.options[2].title == "Queens"
        and p.options[3].title == "Stay" and p.cancel == true,
    "Matataki's gate asks which way: back to Norune, on to Queens, or stay", p and #p.options)
  check(p and p.town == true, "the panel asks to open in the town's walk")
  S.emit("ui.choice_made", {id = "vigil.road", index = 2})
  check(S.transition == "chronicle:location:queens", "taking the road goes to the next town", S.transition)
  S.transition = nil
  S.emit("game.town.road", {town_id = 4})
  p = S.panel
  check(p and #p.options == 4 and p.options[1].title == "Muska Lacka" and p.options[2].title == "Moon Sea"
        and p.options[3].title == "Gallery of Time",
    "Yellow Drops' road leads to the dungeons only the world map reached, too")
  S.entered = nil
  S.emit("ui.choice_made", {id = "vigil.road", index = 3})
  check(S.entered and S.entered.dungeon_id == 5 and S.entered.floor_id == 0 and S.transition == nil,
    "into Gallery of Time at floor 1", S.entered and S.entered.dungeon_id)
  S.emit("game.town.road", {town_id = 0})
  S.emit("ui.choice_made", {id = "vigil.road", index = 2, cancelled = true})
  check(S.transition == nil, "backing out stays")
  local T = new_game({settings = {world_zones = false}}).load()
  T.emit("game.world.location_changed", {context = "georama", area_id = 0})
  T.emit("game.town.road", {town_id = 0})
  check(T.roads == false and T.panel == nil, "without Vigil World the gates are the world map, as ever")
end

print("24. Gear: pieces from chests and monsters, the item page's Equipment tab (G4, G5)")
do
  local S = new_game().load()
  check(S.gear_page and S.gear_page.hat == "gear_hat" and S.gear_page.boots == "gear_boots",
    "the item page opens its Equipment tab, each kind with its icon")
  check(S.resource_overrides and S.resource_overrides["icons/gear_tunic.png"] == "resources/gear_tunic.png",
    "the four icons come from Vigil's resources")
  check(S.gear_parts and S.gear_parts.toan and S.gear_parts.toan.hat.draw[1] == "boushi"
    and S.gear_parts.toan.tunic.draw[1] == "cloth2" and S.gear_parts.toan.boots.draw[1] == "skin"
    and S.gear_parts.toan.boots.below[1] == "l_f",
    "Toan's own hat, tunic, gloves and boots show in the slots, the boots his shoes")
  check(S.gear_parts.toan.hat.bare[1] == "boushi" and S.gear_parts.toan.tunic.bare[1] == "cloth2"
    and S.gear_parts.toan.gloves.bare == nil and S.gear_parts.toan.boots.bare == nil,
    "with no hat or tunic on Toan goes without; his hands and feet stay")
  check(S.run_menu == nil, "Start is the game's own pause")

  do
    -- A save dresses Toan once in his own cap and vest, so an empty slot doesn't leave him bareheaded from the start.
    local G = new_game()
    G.slot = {slot_id = 3, slot_generation = 1}
    G.load()
    G.emit("game.world.location_changed", {context = "town"})
    local names, worn = {}, 0
    for _, p in ipairs(G.gear) do
      names[p.name] = p
      if p.worn_by == "toan" then worn = worn + 1 end
    end
    check(names["Toan's Cap"] and names["Toan's Cap"].kind == "hat" and names["Toan's Vest"] and names["Toan's Vest"].kind == "tunic"
      and names["Toan's Satchel"] and names["Toan's Satchel"].kind == "pouch" and not next(names["Toan's Satchel"].effects)
      and worn == 3, "Toan starts out wearing his own cap, vest and satchel, nothing to them")
    G.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
    local before = #G.gear
    G.emit("game.world.location_changed", {context = "town"})
    check(#G.gear == before, "and only once for the save")

    -- A save dressed before the satchel came gets the satchel alone.
    local O = new_game()
    O.slot = {slot_id = 4, slot_generation = 1}
    O.load()
    O.save_data["dressed:4:1"] = true
    O.emit("game.world.location_changed", {context = "town"})
    check(#O.gear == 1 and O.gear[1].name == "Toan's Satchel" and O.gear[1].worn_by == "toan",
      "a save dressed in his cap and vest before gets his satchel alone")

    -- The others' clothes that come off are given once each is in the party, and not before.
    local P = new_game()
    P.slot = {slot_id = 5, slot_generation = 1}
    P.load()
    P.save_data["dressed:5:1"] = {hat = true, tunic = true, pouch = true}
    P.game.party = {list = function() return {{id = "toan", active = true}, {id = "goro"}, {id = "osmond"}} end}
    P.emit("game.world.location_changed", {context = "town"})
    local by = {}
    for _, p in ipairs(P.gear) do by[p.name] = p.worn_by end
    check(by["Goro's Mantle"] == "goro" and by["Osmond's Bag"] == "osmond" and by["Ungaga's Cap"] == nil and #P.gear == 2,
      "Goro's mantle and Osmond's bag go on them once they've joined; Ungaga, not yet with them, gets nothing")
    P.game.party = {list = function() return {{id = "toan"}, {id = "goro"}, {id = "ungaga"}, {id = "osmond"}} end}
    P.emit("game.world.location_changed", {context = "town"})
    for _, p in ipairs(P.gear) do by[p.name] = p.worn_by end
    check(by["Ungaga's Cap"] == "ungaga" and by["Ungaga's Sash"] == "ungaga" and #P.gear == 4,
      "and Ungaga's cap and sash when he joins, the others not given again")
  end

  -- Every hero shows their own pieces where they have them; the rest keep the icons.
  local parts = S.gear_parts
  check(parts.xiao.boots.below[1] == "l_asi" and parts.goro.tunic.bare[1] == "mant" and parts.ruby.hat.draw[1] == "cube37"
    and parts.ungaga.hat.bare[1] == "cap" and parts.osmond.boots.below[1] == "l_foot" and parts.osmond.pouch.bare[1] == "bag"
    and parts.xiao.hat == nil and parts.goro.boots == nil,
    "the other heroes' own clothes show in their slots; a kind one has nothing for keeps its icon")

  -- Every kind and rarity a roll can make is one the engine takes.
  for i = 1, 400 do
    S.emit("game.chest.opened", {chest = i, dungeon_id = i % 7, floor_id = 0, item_id = 1})
  end
  local made = #S.gear
  check(made > 40 and made < 140, "about one chest in five holds a piece", made)
  local kinds, rarities, three, tinted = {}, {}, false, true
  for _, p in ipairs(S.gear) do
    kinds[p.kind] = true
    rarities[p.rarity] = true
    local n = 0
    for _ in pairs(p.effects) do n = n + 1 end
    three = three or n == 3
    tinted = tinted and p.icon == "gear_" .. p.kind and type(p.color) == "table"
  end
  check(kinds.hat and kinds.tunic and kinds.gloves and kinds.boots and kinds.pouch and rarities[0] and rarities[1] and rarities[2],
    "hats, tunics, gloves, boots and pouches, common to rare")
  check(three, "rarer pieces carry three effects")
  check(tinted, "each piece is its kind's icon, tinted")
  check(any_toast(S, "It's in the Equipment tab."), "and the toast says where it went")

  -- A kind's first effect is its own: boots make running cheaper, and its colour says which effect leads.
  local boots_ok, swift_red = true, true
  for _, p in ipairs(S.gear) do
    if p.kind == "boots" and not p.effects.run_cost then boots_ok = false end
    if p.kind == "boots" and (p.color.r ~= 232 or p.color.g ~= 92) then swift_red = false end
  end
  check(boots_ok, "every pair of boots cuts what the run drains")
  check(swift_red, "and is the run's red")
  local tunics_poise, poise_only_tunics = true, true
  for _, p in ipairs(S.gear) do
    if p.kind == "tunic" and not (p.effects.poise and p.effects.poise >= 1 and p.effects.poise <= 4) then tunics_poise = false end
    if p.kind ~= "tunic" and p.effects.poise then poise_only_tunics = false end
  end
  check(tunics_poise, "every tunic carries poise, 1 to 4 by rarity")
  check(poise_only_tunics, "and only a tunic does")
  local pouches_bag, bag_only_pouches = true, true
  for _, p in ipairs(S.gear) do
    if p.kind == "pouch" and not (p.effects.bag and p.effects.bag % 5 == 0 and p.effects.bag >= 5 and p.effects.bag <= 20) then pouches_bag = false end
    if p.kind ~= "pouch" and p.effects.bag then bag_only_pouches = false end
  end
  check(pouches_bag, "every pouch grows the item bag, 5 slots a tier")
  check(bag_only_pouches, "and only a pouch does")

  -- Monsters drop one now and then; a scripted death never does.
  local before = #S.gear
  for _ = 1, 600 do S.emit("game.enemy_defeated", {attacker = 0}) end
  local dropped = #S.gear - before
  check(dropped > 3 and dropped < 50, "about one monster in thirty drops a piece", dropped)
  before = #S.gear
  for _ = 1, 300 do S.emit("game.enemy_defeated", {}) end
  check(#S.gear == before, "a death with no attacker drops nothing")

  -- Home from a dungeon, every shop puts out three pieces at twice their value; walking about town doesn't restock.
  S.emit("game.world.location_changed", {context = "town", previous = {context = "dungeon"}})
  local stock = S.gear_stock or {}
  local stocked, priced = 0, true
  for shop = 0, 17 do
    if stock[shop] and #stock[shop] == 3 then stocked = stocked + 1 end
    for _, g in ipairs(stock[shop] or {}) do priced = priced and g.price == g.value * 2 end
  end
  check(stocked == 18 and priced, "each town shop sells three pieces of gear at twice their value", stocked)
  local first = stock[0] and stock[0][1]
  S.emit("game.world.location_changed", {context = "town", previous = {context = "town"}})
  check(S.gear_stock[0][1] == first, "and moving about town keeps the same goods")
  S.emit("game.world.location_changed", {context = "town", previous = {context = "dungeon"}})
  check(S.gear_stock[0][1] ~= first, "the next trip home they are new")

  -- Off, the tab goes and nothing drops.
  S.set("gear", false)
  check(S.gear_page == nil, "Gear off: the item page is the game's own again")
  before = #S.gear
  for i = 1, 100 do S.emit("game.chest.opened", {chest = i, dungeon_id = 0, floor_id = 0, item_id = 1}) end
  check(#S.gear == before, "and nothing drops")
  S.set("gear", true)
  check(S.gear_page and S.gear_page.gloves == "gear_gloves", "on again, the tab is back")

  local T = new_game({session = {kind = "sandbox", owner = "moonmod.roguelike"}}).load()
  check(T.gear_page == nil, "Vigil leaves the item page alone in another mod's game mode")
end

print("25. The guard and the gauge follow Souls rules (E1, E2)")
do
  local S = new_game().load()
  local g, r = S.guard_rules, S.gauge_rules
  check(g and g.arc == 120 and g.parry_frames == 6 and g.without_lock == true and g.chip == 0.15,
    "the guard covers the front, parries in its first 6 frames and needs no lock-on")
  check(g and g.cost_base == 10 and g.cost_per_damage == 1.5 and math.type(g.break_recoil) == "integer",
    "a blocked hit costs 10 gauge and 1.5 a point of damage; a break knocks down")
  check(r and r.hit_refill == -15 and r.first_swing_cost == 25 and r.min_to_swing == 10 and r.refill_delay == 36,
    "a hit drains 15, the first swing costs 25 and needs 10, the refill waits 36 frames")

  S.emit("game.player.hit", {kind = "heavy", damage = 0, blocked = true, parried = true, entity = "monster:3:1", angle = 5, gauge = 50})
  check(S.statuses and S.statuses[1].entity == "monster:3:1" and S.statuses[1].status == "stop",
    "a parry stops the attacker")
  check(S.knockbacks and S.knockbacks[1].direction.z > 0, "and shoves it away")
  check(S.bursts and S.bursts[1].kind == "guard", "with a guard burst")
  S.emit("game.player.hit", {kind = "light", damage = 20, broke = true, entity = "monster:3:1", angle = 5, gauge = 0})
  check(S.bursts[2] and S.bursts[2].kind == "sparks" and #S.statuses == 1, "a guard break throws sparks and stops nothing")
  S.emit("game.player.hit", {kind = "light", damage = 20, angle = 170, gauge = 10})
  check(#S.bursts == 2, "a plain hit does nothing more")

  S.set("guard_rules", false)
  check(S.guard_rules == nil and S.gauge_rules ~= nil, "Souls guard off: the game's guard again, the gauge rules kept")
  S.set("gauge_rules", false)
  check(S.gauge_rules == nil, "Souls stamina off: the game's gauge again")

  local T = new_game({session = {kind = "sandbox", owner = "moonmod.roguelike"}}).load()
  check(T.guard_rules == nil and T.gauge_rules == nil, "Vigil leaves the guard and gauge alone in another mod's game mode")
end

print("26. Exhausted on an empty gauge, a riposte after a parry (§3)")
do
  local S = new_game().load()
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  S.in_dungeon_now = true
  S.gauge = 40
  S.tick(5)
  check(not (S.formulas and S.formulas.exhausted and S.formulas.exhausted.value ~= 1), "a gauge with something in it: not exhausted")
  S.gauge = 0
  S.tick()
  check(S.formulas.exhausted.value == 0.3 and S.icons and S.icons.exhausted and S.icons.exhausted.blink,
    "an empty gauge: swings at 30% and the stamina badge blinks")
  S.gauge = 50
  S.tick(89)
  check(S.formulas.exhausted.value == 0.3, "for a second and a half")
  S.tick()
  check(S.formulas.exhausted.value == 1 and S.icons.exhausted == nil, "then it passes")

  S.emit("game.player.hit", {kind = "heavy", damage = 0, blocked = true, parried = true, entity = "m1", angle = 5, gauge = 50})
  local r = S.formulas.riposte
  check(r and r.value == 3 and r.native_model_id == 3, "a parry: the next blow on that kind of enemy does x3")
  S.emit("game.enemy_hit", {entity = "m3", damage = 30})
  check(S.formulas.riposte.value == 3, "a blow on another enemy doesn't spend it")
  S.emit("game.enemy_hit", {entity = "m1", damage = 90})
  check(S.formulas.riposte.value == 1 and S.formulas.riposte.native_model_id == nil, "the blow on the parried one does")
  S.emit("game.player.hit", {kind = "heavy", damage = 0, blocked = true, parried = true, entity = "m1", angle = 5, gauge = 50})
  S.tick(120)
  check(S.formulas.riposte.value == 1, "unused, it lapses after 2 seconds")
end

print("27. Poise: enemies shrug off the first blows, then stagger (stretch goal 2)")
do
  local S = new_game().load()
  check(S.override ~= nil, "Poise hooks the monsters' scripts")
  local frame = 0
  local function hit(entity)
    frame = frame + 2
    S.statuses = nil
    local retail = S.retail or 0
    local r = S.override({entity = entity, slot = 0, program_no = 110, model = 0, frame = frame})
    return type(r) == "table" and r.handled == true and (S.retail or 0) == retail, S.statuses and S.statuses[1]
  end
  check(S.target_bar == true, "the locked enemy gets the wider target bar")
  local held1 = hit("m2")
  local fill1 = S.meters and S.meters.m2 and S.meters.m2.fill
  local held2 = hit("m2")
  local fill2 = S.meters and S.meters.m2 and S.meters.m2.fill
  local held3, stagger = hit("m2")
  check(held1 and held2, "the first two blows don't make it flinch")
  check(fill1 and fill2 and math.abs(fill1 - 1 / 3) < 1e-6 and math.abs(fill2 - 2 / 3) < 1e-6 and S.meters.m2.fill == 1,
    "its poise meter fills a third a blow, and is full as it breaks", fill1)
  check(S.meters.m2.seconds > 40 / 60, "and stays full through the stagger")
  check(not held3 and stagger and stagger.status == "stop" and stagger.duration_frames == 40,
    "the third breaks its poise: the game's flinch and a stagger")
  check(hit("m2"), "then its poise is whole again")
  frame = frame + 200
  check(hit("m2") and hit("m2"), "and two seconds without a hit restore it")
  S.emit("game.player.move", {id = "vigil_toan_heavy", character = "toan"})
  local held, broke = hit("m3")
  check(not held and broke, "a heavy blow breaks it at once")

  S.set("poise", 0)
  check(hit("m2") == false, "Poise 0: every blow flinches, as in the game")
  S.set("target_bar", false)
  check(S.target_bar == false, "Target bar off: the game's own gauge")

  local T = new_game({session = {kind = "sandbox", owner = "moonmod.roguelike"}}).load()
  check(T.override == nil, "Vigil's hook stays off in another mod's game mode")
end

print("28. Criticals: a backstab, and a riposte on a parried or staggered enemy (stretch goal 3)")
do
  local S = new_game().load()
  local backstab, riposte
  local others = {}
  for _, m in ipairs(S.moves or {}) do
    if m.trigger == "critical" and m.character == "toan" then
      if m.critical == "backstab" then backstab = m else riposte = m end
    elseif m.trigger == "critical" then
      others[m.character .. "/" .. m.critical] = m
    end
  end
  local all = true
  for _, who in ipairs({"xiao", "goro", "ruby", "ungaga", "osmond"}) do
    for _, kind in ipairs({"backstab", "riposte"}) do
      local m = others[who .. "/" .. kind]
      if not (m and m.invincible and m.pairs and #m.pairs > 0 and S.animations[m.animation].character == who) then all = false end
    end
  end
  check(all, "the other five heroes have a backstab and a riposte too, on their own motions, with the enemy's crumple")
  check(backstab and riposte and backstab.animation == "toan_critical" and riposte.animation == "toan_critical"
        and backstab.character == "toan" and backstab.invincible == true,
    "Toan has a backstab and a riposte, both his critical stab")
  local paired = {}
  for _, p in ipairs(backstab and backstab.pairs or {}) do paired[p.model] = p.animation end
  check(paired[1] == "e03a_crumple" and paired[3] == "e06a_crumple", "the Skeleton and the Dasher crumple to it")
  local registered = {}
  for _, m in ipairs(S.monster_motions) do registered[m.id] = m.model end
  check(registered.e03a_crumple == 1 and registered.e06a_crumple == 3, "and their crumples are registered on their models")

  S.emit("game.player.hit", {kind = "heavy", damage = 0, blocked = true, parried = true, entity = "m1", angle = 5, gauge = 50})
  check(S.critical_arm and S.critical_arm.entity == "m1" and S.critical_arm.frames == 120, "a parry opens the enemy to a riposte for 2 s")
  S.critical_arm = nil
  for f = 2, 6, 2 do S.override({entity = "m2", slot = 0, program_no = 110, model = 0, frame = f}) end
  check(S.critical_arm and S.critical_arm.entity == "m2" and S.critical_arm.frames == 70, "a poise break too, for its stagger and half a second")

  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 0})
  S.emit("game.player.critical", {id = "vigil_toan_riposte", owner = "moonmod.vigil", kind = "riposte", entity = "m1",
                                  native_model_id = 3, hold = 88})
  local c = S.formulas.critical
  check(c and c.value == 3 and c.native_model_id == 3 and S.formulas.riposte.value == 1,
    "a critical: x3 on that kind of enemy, in place of the riposte")
  S.tick(87)
  check(S.formulas.critical.value == 3, "while it is held")
  S.tick()
  check(S.formulas.critical.value == 1, "then back to x1")
  S.emit("game.player.critical", {id = "other_stab", owner = "other.mod", kind = "backstab", entity = "m1", hold = 40})
  check(S.formulas.critical.value == 1, "another mod's critical is its own business")

  S.set("criticals", false)
  local any = false
  for _, m in ipairs(S.moves or {}) do any = any or m.trigger == "critical" end
  check(S.moves and not any, "Criticals off: no critical moves")
  S.critical_arm = nil
  S.emit("game.player.hit", {kind = "heavy", damage = 0, blocked = true, parried = true, entity = "m1", angle = 5, gauge = 50})
  check(S.critical_arm == nil, "and a parry arms nothing")
end

print("29. The flask: a slow drink that heals late and spills on a hit (stretch goal 5)")
do
  local S = new_game().load()
  local drinks = {}
  for _, m in ipairs(S.moves or {}) do if m.trigger == "played" then drinks[m.character] = m end end
  local all = true
  for _, who in ipairs({"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}) do
    local m = drinks[who]
    all = all and m and m.id == "vigil_" .. who .. "_flask" and m.motion == 28 and m.speed == 0.5
  end
  check(all, "each hero drinks with their own drinking motion, slowed, a played move")
  check(S.tuning and S.tuning.item_heal_lock == 240, "healing items refuse within 240 of an enemy")

  S.slot = {slot_id = 1, slot_generation = 1}
  S.layers, S.played, S.heals = {}, {}, {}
  S.game.render.layer_register = function(a) S.layers[a.id] = a.text; return {} end
  S.game.render.layer_remove = function(a) S.layers[a.id] = nil; return {} end
  S.game.player.move_play = function(a) S.played[#S.played + 1] = a.id; return {id = a.id} end
  S.game.player.heal = function(a) S.heals[#S.heals + 1] = copy(a); return {} end
  S.game.player.get = function() return {character = "toan", hp = 30, max_hp = 100, position = {x = 0, y = 0, z = 0}} end
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 2})
  check(S.layers.flask == "Flask 3/3", "in a dungeon the HUD shows the flask, full", S.layers.flask)

  local function press() S.held.flask = true; S.tick(); S.held.flask = false; S.tick() end
  S.held.flask = true
  S.tick(3)
  check(#S.played == 1 and S.played[1] == "vigil_toan_flask" and S.layers.flask == "Flask 2/3",
    "a press drinks once, however long it is held, and spends a charge")
  check(S.bindings.flask and S.bindings.flask[1] == "Gamepad:dpdown", "D-pad Down drinks")
  S.held.flask = false
  S.emit("game.player.move", {id = "vigil_toan_flask", character = "toan", frames = 100})
  S.tick(63)
  check(#S.heals == 0, "no heal early in the drink")
  S.tick(2)
  check(#S.heals == 1 and S.heals[1].amount == 40 and S.heals[1].character == "toan", "late in it, 40% of max HP")

  press()
  S.emit("game.player.move", {id = "vigil_toan_flask", character = "toan", frames = 100})
  S.emit("game.player.hit", {kind = "light", damage = 5, blocked = true})
  S.emit("game.player.hit", {kind = "light", damage = 5, poised = true})
  S.emit("game.player.hit", {kind = "light", damage = 12})
  S.tick(100)
  check(#S.heals == 1 and any_toast(S, "spilled") and S.layers.flask == "Flask 1/3",
    "a hit that lands spills it, the charge spent (a blocked or poised one doesn't)")
  press()
  S.emit("game.player.move", {id = "vigil_toan_flask", character = "toan", frames = 100})
  S.tick(70)
  press()
  check(#S.played == 3 and S.layers.flask == "Flask 0/3" and any_toast(S, "the flask is empty"), "an empty flask doesn't drink")

  S.set("gear", false) -- the gear's own chest roll would take the stubbed dice too
  local random = math.random
  math.random = function() return 0 end
  S.emit("game.chest.opened", {dungeon_id = 0, floor_id = 2, back_floor = false, chest = 1})
  S.emit("game.chest.opened", {dungeon_id = 0, floor_id = 2, back_floor = false, chest = 2})
  math.random = random
  check(S.layers.flask == "Flask 1/4" and any_toast(S, "Flask Shard"), "a Flask Shard from a chest adds a charge for good, one a floor")
  S.emit("game.world.location_changed", {context = "town"})
  check(S.layers.flask == nil, "the HUD hides it in town")
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 3})
  check(S.layers.flask == "Flask 4/4", "and town fills it")

  S.set("flask", false)
  local any = false
  for _, m in ipairs(S.moves or {}) do any = any or m.trigger == "played" end
  check(not any and S.tuning.item_heal_lock == nil, "Flask off: no drinks, and healing items work as in the game")
end

print("30. Weapon arts: guard + R2 plays the weapon's art, shown on its card (stretch goal 4)")
do
  local S = new_game().load()
  local arts = {}
  for _, m in ipairs(S.moves or {}) do if m.trigger == "art" then arts[m.id] = m end end
  local rush, whirl, split = arts.vigil_toan_art_rush, arts.vigil_toan_art_whirl, arts.vigil_toan_art_split
  check(rush and whirl and split and rush.character == "toan" and rush.min_level == 3 and rush.name == nil,
    "Toan has three arts, from weapon level 3")
  local seen, twice = {}, false
  for _, m in pairs(arts) do
    for _, w in ipairs(m.weapons) do twice = twice or seen[w]; seen[w] = true end
  end
  check(not twice and seen[258] and seen[261] and seen[264], "each blade has one art: the Dagger rushes, the Wise Owl Sword whirls, the Buster Sword splits")
  check(rush.gauge == 35 and whirl.gauge == 45 and split.gauge == 50 and whirl.spin == 2, "each costs gauge; the whirl turns twice")

  S.styles = {}
  S.game.weapons = {
    get = function(id)
      if id == "chronicle:weapon:258" then return {instances = {{character = "toan", slot = 0, level = 1, equipped = true}}} end
      if id == "chronicle:weapon:261" then return {instances = {{character = "toan", slot = 2, level = 4}}} end
      if id == "chronicle:weapon:300" then return {instances = {{character = "xiao", slot = 0, level = 9}}} end
      return {instances = {}}
    end,
    style_set = function(a)
      for k in pairs(a) do assert(k == "character" or k == "slot" or k == "details", "style_set field " .. k) end
      assert(#a.details <= 5, "up to 5 details")
      for _, line in ipairs(a.details) do
        local text = type(line) == "table" and line.text or line
        assert(type(text) == "string" and #text <= 64, "a detail line is up to 64 bytes")
      end
      if a.character == "toan" then S.styles[a.slot] = copy(a) else S.party_styles[a.character .. a.slot] = copy(a) end
      return {}
    end,
    style_clear = function() S.styles, S.party_styles = {}, {}; return {} end,
  }
  S.party_styles = {}
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 1})
  local dagger, owl = S.styles[0], S.styles[2]
  local sling = S.party_styles.xiao0
  check(sling and sling.details[1].text == "Art: Stone Rain" and sling.details[4].text == "Ready.",
    "Xiao's slingshot names her own art (Party attacks)")
  local party_arts = {}
  for _, m in ipairs(S.moves) do if m.trigger == "art" and m.character ~= "toan" then party_arts[m.character] = m.id end end
  check(party_arts.goro and party_arts.ungaga and party_arts.xiao and party_arts.ruby and party_arts.osmond,
    "each of the other five heroes has an art of their own")
  check(dagger and dagger.details[1].text == "Art: Piercing Rush" and dagger.details[4].text:find("level 3 %(now 1%)"),
    "the Dagger's card names its art and the level it unlocks at")
  check(owl and owl.details[1].text == "Art: Whirlwind" and owl.details[4].text == "Ready.", "a built-up sword's art is ready")
  S.set("art_level", 5)
  check(S.styles[2].details[4].text:find("level 5"), "the Art level setting moves the unlock, on the cards too")
  local five = true
  for _, m in ipairs(S.moves) do if m.trigger == "art" then five = five and m.min_level == 5 end end
  check(five, "and on the moves")
  S.set("arts", false)
  local any = false
  for _, m in ipairs(S.moves or {}) do any = any or m.trigger == "art" end
  check(not any and next(S.styles) == nil and next(S.party_styles) == nil, "Arts off: no arts and no cards")
end

print("31. Lock-on, story bosses, named elites and NG+ (stretch goals 6, 7, 8, 15)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true, world_regions = false, gear = false}}).load()
  check(S.tuning.lock_flick == true and S.tuning.lock_sight == true and S.tuning.soft_lock == 35,
    "lock-on: flick to switch, lost behind walls, and a 35-degree soft lock")
  S.set("soft_lock", 0)
  check(S.tuning.soft_lock == nil, "soft lock 0 sends nothing")

  local stats, tints, bars, cards = {}, {}, {}, {}
  S.statuses = nil
  S.monsters = {}
  S.game.entities.query = function() return {entities = copy(S.monsters)} end
  S.game.entities.set_stats = function(a)
    assert(a.damage_scale == nil or (a.damage_scale >= 0 and a.damage_scale <= 10), "damage_scale 0-10")
    local was = stats[a.entity] or {damage_scale = 1}
    local now = copy(was)
    for k, v in pairs(a) do now[k] = v end
    stats[a.entity] = now
    return {entity = a.entity, previous = copy(was), current = copy(now)}
  end
  S.game.entities.tint = function(a) tints[a.entity] = copy(a); return {} end
  S.game.render.bar_register = function(a)
    for k in pairs(a) do assert(k == "id" or k == "label" or k == "current" or k == "max" or k == "boss", "bar_register field " .. k) end
    assert(#a.label <= 24 and a.current >= 0 and a.current <= a.max, "a bar's label and range")
    bars[a.id] = copy(a)
    return {}
  end
  S.game.render.bar_remove = function(a) bars[a.id] = nil; return {} end
  S.game.ui.boss_card = function(a) cards[#cards + 1] = copy(a); return {} end
  S.game.dungeons.zones_get = function() return {current = 0, floor_zones = 2} end
  local function monster(id, hp, max, model)
    return {entity_id = id, revealed = true, native_model_id = model or 3, definition = {kind = 0}, position = {x = 0, y = 0, z = 0},
            health = {current = hp, maximum = max}, combat = {reward_exp = 10, reward_money = 20}}
  end
  local function enter(dungeon, floor, seed)
    S.emit("game.dungeon.generating", {dungeon_id = dungeon, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = dungeon, floor_id = floor, back_floor = false, floor_seed = seed, room_count = 10})
    S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = dungeon, floor_id = floor})
  end

  -- A story boss: a card on entry, a bar along the bottom, and a second phase at half life.
  enter(0, 2, 500)
  S.monsters = {monster("dran", 400, 400, 78)}
  S.tick(60)
  check(#cards == 1 and cards[1].name == "Dran" and cards[1].epithet ~= nil, "Dran walks in with his card")
  check(bars.boss and bars.boss.boss == true and bars.boss.label == "DRAN" and bars.boss.current == 400, "his bar runs along the bottom")
  check(stats.dran == nil or stats.dran.damage_scale == 1, "not enraged above half life")
  S.monsters = {monster("dran", 190, 400, 78)}
  S.tick(60)
  local haste
  for _, st in ipairs(S.statuses or {}) do if st.entity == "dran" and st.status == "haste" then haste = st end end
  check(stats.dran and math.abs(stats.dran.damage_scale - 1.3) < 1e-9 and tints.dran and haste, "at half life he rages: red, faster, harder")
  check(any_toast(S, "rages"), "and the screen says so")
  check(#cards == 1, "one card a fight")
  -- Phase two brings a new move: marks glint between him and you, and three quarters of a second later fall.
  local strikes, glints = {}, 0
  S.game.combat = S.game.combat or {}
  S.game.combat.strike_player = function(a)
    assert(a.radius >= 2 and a.radius <= 120 and a.damage >= 0 and (a.kind == "light" or a.kind == "heavy"), "strike_player")
    strikes[#strikes + 1] = copy(a) return {struck = true}
  end
  local burst_was = S.game.effects.burst
  S.game.effects.burst = function(a) if a.kind == "guard" then glints = glints + 1 end return {} end
  S.game.player.get = function() return {hp = 100, max_hp = 100, character = "toan", position = {x = 200, y = 0, z = 0}} end
  S.models_loaded = true
  for _ = 1, 400 do if glints > 0 then break end S.tick(1) end
  check(glints >= 4 and #strikes == 0, "the marks glint first")
  local reared
  for _, n in ipairs(S.natives) do
    if n.entity == "dran" and n.native == "SET_MOTION" and n.args[1] > 100 and n.args[2] == 0.6 then reared = n.args[1] end
  end
  local listed = S.game.animations.monster_list().motions
  local rear_n
  for _, m in ipairs(listed) do if m.id == "c12a_rear" and m.model == 78 then rear_n = m.motion end end
  check(rear_n and reared == rear_n, "as they glint, Dran rears up in a motion of his own")
  local bodies = {}
  for _, m in ipairs(listed) do bodies[m.id] = m.model end
  check(bodies.c14a_stamp == 79 and bodies.c13a_frost == 80 and bodies.c16a_leap == 83 and bodies.c17a_sweep == 84 and
        bodies.c12a_rear == 78, "and Utan, the Ice Queen, Joe and the Genie each have one of their own")
  check(bodies.c15a_curse == 81 and bodies.c15b_curse == 82 and bodies.c23a_beam == 106,
        "as do the King's Curse, his coffin and the Genie's final form")
  if S.override then
    local retail = S.retail or 0
    S.override({entity = "dran", slot = 0, program_no = 100, model = 78, frame = 1})
    check((S.retail or 0) == retail, "his script waits while he rears")
    S.override({entity = "dran", slot = 0, program_no = 100, model = 78, frame = 1e9})
    check((S.retail or 0) == retail + 1, "and takes up again once the move is done")
  end
  S.tick(90)
  check(#strikes == 4 and strikes[1].damage == 18 and strikes[1].kind == "heavy" and math.abs(strikes[1].x - 40) < 1e-6,
        "then Dran's fire falls along the line to you")
  check(any_toast(S, "breathes fire"), "named once")
  S.game.effects.burst = burst_was
  S.monsters = {}
  S.tick(60)
  check(bars.boss == nil, "the bar goes with him")

  -- A named elite: the second time an ordinary monster is seen, it is crowned.
  enter(0, 3, 600)
  S.monsters = {monster("grunt", 40, 40)}
  S.tick(80)
  check(stats.grunt and stats.grunt.max_hp == 120 and math.abs(stats.grunt.damage_scale - 1.5) < 1e-9 and stats.grunt.reward_exp == 50,
    "a named elite: three times the life, half again the bite, five times the reward")
  check(tints.grunt and bars.elite and bars.elite.boss == nil, "gold, with a bar of its own")
  S.emit("game.enemy_defeated", {entity = "grunt", attacker = 0})
  check(any_toast(S, "has fallen") and bars.elite == nil, "its fall is told, and the bar goes")
  stats = {}
  enter(0, 3, 600)
  S.monsters = {monster("grunt2", 40, 40)}
  S.tick(120)
  check(stats.grunt2 == nil, "a fallen elite stays down when its floor is built again")
  enter(0, 4, 700)
  S.monsters = {monster("other", 40, 40)}
  S.tick(80)
  check(bars.elite and bars.elite.label ~= nil, "the next floor has its own")
  S.set("elites", false)
  stats = {}
  enter(0, 5, 800)
  S.monsters = {monster("plain", 40, 40)}
  S.tick(120)
  check(stats.plain == nil, "Named elites can be turned off")
  S.set("elites", true)

  -- NG+: the Dark Genie's fall readies a cycle, begun at a shrine.
  S.emit("game.enemy_defeated", {entity = "genie", native_model_id = 106, attacker = 0})
  check(any_toast(S, "next cycle"), "the Dark Genie's fall readies the next cycle")
  enter(1, 1, 900)
  S.emit("game.dungeon.shrine_reached", {zone = 0, x = 12, y = 5})
  pray(S, {zone = 0, x = 12, y = 5})
  check(S.panel and S.panel.options[3].lines[2].text:find("next cycle", 1, true), "the shrine's Leave card offers it")
  S.emit("ui.choice_made", {id = "vigil.shrine", index = 3})
  check(S.panel.id == "vigil.cycle" and S.panel.options[2].title == "Next cycle", "Leave asks: leave, or begin the next cycle")
  S.emit("ui.choice_made", {id = "vigil.cycle", index = 2})
  check(any_toast(S, "cycle 2 begins"), "praying begins cycle 2")
  stats = {}
  enter(0, 3, 900)
  S.monsters = {monster("again", 40, 40)}
  S.tick(80)
  check(stats.again and stats.again.max_hp ~= nil, "a new cycle brings the fallen elites back")
end

print("32. Ambushes (stretch goal 9)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true, world_regions = false, gear = false, elites = false}}).load()
  local spawned, registered = {}, {}
  S.game.characters = {
    register = function(a)
      assert(a.kind == "enemy" and math.type(a.template_monster_id) == "integer" and #a.name <= 30, "register an enemy variant")
      registered[a.id] = a.template_monster_id
      return {id = "moonmod.vigil:" .. a.id}
    end,
    spawn = function(a) spawned[#spawned + 1] = copy(a); return {entity_handle = "s" .. #spawned} end,
  }
  -- Each spawned monster where the velocities written move it (one tick a write), as velocity_set on Chronicle.
  local fell, lowest = {}, {}
  S.game.physics = {velocity_set = function(a)
    local n = tonumber(a.entity:match("^s(%d+)$"))
    local y = spawned[n].position.y + a.velocity.y
    spawned[n].position.y = y
    fell[a.entity] = (fell[a.entity] or 0) + 1
    lowest[a.entity] = math.min(lowest[a.entity] or y, y)
    return {}
  end}
  S.game.entities.query = function()
    local list = {{entity_id = "m1", revealed = true, native_model_id = 7, definition = {kind = 0}, health = {current = 10, maximum = 10}}}
    for n, s in ipairs(spawned) do
      list[#list + 1] = {entity_id = "s" .. n, native_model_id = 7, character = s.character, position = copy(s.position)}
    end
    return {entities = list}
  end
  S.game.player.get = function() return {hp = 50, character = "toan", position = {x = 1600, y = 0, z = 800}} end
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 1, floor_id = 1, back_floor = false, floor_seed = 42, room_count = 10})
  S.emit("game.dungeon.zone_entered", {zone = 0, previous = -1, zones = 2})
  S.tick(120)
  check(#spawned == 0, "no ambush as you arrive on a floor")
  local sprung, first
  for zone = 1, 9 do
    S.emit("game.dungeon.zone_entered", {zone = zone, previous = zone - 1, zones = 10})
    S.tick(30)
    local early = #spawned
    S.tick(90)
    if #spawned > 0 and not sprung then
      sprung, first = zone, #spawned
      check(early == 0, "a moment after you walk in, not at once")
    end
  end
  check(sprung and first == 3 and #spawned < 27 and registered["ambush-7"] == 7, "an ambush: three of the floor's own monsters drop in")
  local d = math.sqrt((spawned[1].position.x - 1600) ^ 2 + (spawned[1].position.z - 800) ^ 2)
  check(math.abs(d - 70) < 1e-6, "around you, close")
  check(fell.s1 and fell.s3 and fell.s1 > 10, "from above: high over the floor, falling faster each tick")
  check(math.abs(spawned[1].position.y) < 0.6 and math.abs(spawned[3].position.y) < 0.6 and lowest.s1 >= 0 and lowest.s3 >= 0,
        "landing on the floor, never through it")
  check(any_toast(S, "ambush"), "and the screen says so")
  local room_test = S.game.dungeons.room_seal and true
  if S.game.dungeons.room_seal then
    check(S.room_shut == true and any_toast(S, "The way is shut"), "the room shuts behind you")
    for i = 1, 2 do S.emit("game.enemy_defeated", {entity = "s" .. i, attacker = 0}) end
    check(S.room_shut == true, "while one of the pack still stands")
    S.emit("game.enemy_defeated", {entity = "s3", attacker = 0})
    check(not S.room_shut and any_toast(S, "the way opens"), "and opens once the pack is dead")
  end
  check(room_test, "the fake knows room seals")
  local before = #spawned
  S.emit("game.dungeon.zone_entered", {zone = sprung, previous = sprung + 1, zones = 10})
  S.tick(120)
  check(#spawned == before, "a sprung ambush doesn't happen twice")
  -- Height steps: on or beside a ramp the ring around you isn't level, so the ambush waits until you're off it.
  local zg_before = S.game.dungeons.zones_get
  S.game.dungeons.zones_get = function() return {current = 0, floor_zones = 40, ramps = {{x = 10, y = 5, from = 0, to = -40}}} end
  for zone = 11, 39 do
    S.emit("game.dungeon.zone_entered", {zone = zone, previous = zone - 1, zones = 40})
    S.tick(120)
  end
  check(#spawned == before, "no ambush springs while you stand on a ramp")
  S.game.dungeons.zones_get = zg_before
  S.tick(40)
  check(#spawned > before, "it springs once you're off it")

  -- Messages, offline (stretch goal 17): a note by each shrine, read once.
  local function notes()
    local n = 0
    for _, t in ipairs(S.toasts) do if t:find("A note, scratched", 1, true) then n = n + 1 end end
    return n
  end
  S.emit("game.dungeon.shrine_reached", {zone = 0, x = 10, y = 4})
  S.emit("game.dungeon.shrine_reached", {zone = 0, x = 10, y = 4})
  check(notes() == 1, "a note by the shrine, the first time you reach it")
  for _, t in ipairs(S.toasts) do assert(#t <= 200, "a note fits a notice") end

  -- Shortcuts (stretch goal 11): two doors a kept floor, built open once opened.
  local asked
  S.game.dungeons.set_shortcuts = function(a)
    for k in pairs(a) do assert(k == "count" or k == "open" or k == "illusory" or k == "open_walls", "set_shortcuts field " .. k) end
    asked = copy(a)
    return {count = a.count}
  end
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 1, floor_id = 1, back_floor = false, floor_seed = 42, room_count = 10})
  check(asked and asked.count == 2 and asked.open == nil, "a kept floor asks for two shortcut doors")
  S.emit("game.dungeon.door_opened", {key = "chronicle:item:217", x = 5, y = 9})
  check(any_toast(S, "shortcut opens"), "opening one says so")
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  check(asked.count == 2 and asked.open and asked.open[1] == 217 and #asked.open == 1, "and the floor built again has it open")
  check(asked.illusory == 1 and asked.open_walls == nil, "and one illusory wall")
  S.emit("game.dungeon.wall_opened", {wall = 0, x = 7, y = 3})
  check(any_toast(S, "never there"), "a struck wall fades")
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  check(asked.open_walls and asked.open_walls[1] == 0, "and stays open on the next visit")
  S.emit("game.dungeon.generating", {dungeon_id = 6, floor_id = 2, back_floor = false})
  check(asked.count == 0, "not on Demon Shaft's floors")
end

print("33. Vigil Trial: a title mode to fight any story boss (stretch goal 16)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {gear = false}, storage = {trial_best = {dran = 4000}}})
  local mode, started, finished, spawned, given, equipped, set = nil, nil, false, {}, {}, {}, {}
  S.game.dungeons.register = function(a)
    assert(a.dungeon == 0 and #a.floors == 1 and next(a.floors[1].enemies) == nil, "one empty floor in Divine Beast Cave")
    return {id = "moonmod.vigil:vigil-trial", floors = {{id = "moonmod.vigil:arena", native_floor_id = 23}}}
  end
  S.game.title = {
    mode_register = function(a)
      assert(#a.entries <= 7 and #a.lines <= 6 and #a.label <= 32 and #a.title <= 40, "mode page limits")
      for _, en in ipairs(a.entries) do assert(#en.label <= 64, "entry label") end
      mode = copy(a)
      return {id = a.id}
    end,
    mode_set = function(a) for k, v in pairs(a) do mode[k] = copy(v) end return {} end,
  }
  S.game.session.start = function(a) started = copy(a) return {queued = true} end
  S.game.session.finish = function() finished = true return {} end
  S.game.weapons = {
    list = function()
      return {{id = "chronicle:weapon:258", owner = "toan", stats = {attack = 10}}, {id = "chronicle:weapon:261", owner = "toan", stats = {attack = 45}},
              {id = "chronicle:weapon:270", owner = "toan", stats = {attack = 99}}, {id = "chronicle:weapon:300", owner = "xiao", stats = {attack = 30}}}
    end,
    give = function(a) given[#given + 1] = copy(a) return {slot = 1} end,
    equip = function(a) equipped[#equipped + 1] = copy(a) return {} end,
  }
  S.game.characters = {
    register = function(a) return {id = "moonmod.vigil:" .. a.id} end,
    spawn = function(a) spawned[#spawned + 1] = copy(a) return {entity_handle = "e" .. #spawned} end,
  }
  S.game.player.set = function(a) set[#set + 1] = copy(a) return {} end
  S.game.player.get = function() return {hp = 50, character = "toan", heading = 0, position = {x = 100, y = 0, z = 100}} end
  S.load()
  check(mode and mode.id == "vigil_trial" and #mode.entries == 3, "a title mode: the boss, the hero and Begin")
  check(mode.entries[1].label:find("Dran", 1, true) and mode.entries[1].label:find("best 1:06", 1, true), "Dran first, with a best time")
  S.emit("game.title.selected", {mode = "vigil_trial", entry = "boss", index = 0})
  check(mode.entries[1].label:find("Master Utan", 1, true), "Cross on the boss turns to the next")
  for _ = 1, 4 do S.emit("game.title.selected", {mode = "vigil_trial", entry = "boss", index = 0}) end
  check(mode.entries[1].label:find("Dark Genie", 1, true), "on to the Dark Genie")
  S.emit("game.title.selected", {mode = "vigil_trial", entry = "boss", index = 0})
  check(mode.entries[1].label:find("Elite: Garrow", 1, true), "then the named elites")
  for _ = 1, 7 do S.emit("game.title.selected", {mode = "vigil_trial", entry = "boss", index = 0}) end
  S.emit("game.title.selected", {mode = "vigil_trial", entry = "start", index = 2})
  check(started and started.floor == "moonmod.vigil:arena" and started.party_size == 6 and started.character == "toan",
    "Begin starts a session on the arena floor")
  S.session = {kind = "sandbox", owner = "moonmod.vigil", mode = "vigil_trial"}
  S.emit("game.session.started", {owner = "moonmod.vigil", mode = "vigil_trial"})
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 23})
  S.tick(1)
  local toan
  for _, g in ipairs(given) do if g.character == "toan" then toan = g.id end end
  check(toan == "chronicle:weapon:261", "Toan gets his strongest blade under Master Utan's cap")
  local hp
  for _, p in ipairs(set) do if p.character == "toan" and p.max_hp then hp = p.max_hp end end
  check(hp == 220, "and the life for that place in the story")
  S.tick(240)
  check(#spawned == 1 and spawned[1].character == "moonmod.vigil:trial-79" and spawned[1].arena_slot == 0, "then Master Utan comes out")
  check(math.abs(spawned[1].position.z - 240) < 1e-6, "in front of you")
  S.tick(60)
  check(#spawned == 1, "once")
  S.emit("game.enemy_defeated", {entity = "e1", native_model_id = 79})
  check(any_toast(S, "falls in") and S.storage.trial_best.utan ~= nil, "a win is timed and kept")
  S.tick(300)
  check(finished, "and the Trial ends back at the title")

  -- An elite: Garrow the Unbowed, a Skeleton Soldier, at the first place in the story.
  local stats, tinted, bar = {}, nil, nil
  S.game.entities.set_stats = function(a) stats[a.entity] = copy(a) return {} end
  S.game.entities.tint = function(a) tinted = copy(a) return {} end
  S.game.render.bar_register = function(a) bar = copy(a) return {} end
  S.game.entities.query = function() return {entities = {{entity_id = "e2", native_model_id = 1, health = {current = 300, maximum = 360}}}} end
  S.emit("game.session.ended", {owner = "moonmod.vigil", reason = "finished"})
  for _ = 1, 5 do S.emit("game.title.selected", {mode = "vigil_trial", entry = "boss", index = 0}) end
  check(mode.entries[1].label:find("Elite: Garrow the Unbowed", 1, true), "Garrow is the first elite")
  S.emit("game.title.selected", {mode = "vigil_trial", entry = "start", index = 2})
  S.emit("game.session.started", {owner = "moonmod.vigil", mode = "vigil_trial"})
  S.tick(240)
  check(#spawned == 2 and spawned[2].character == "moonmod.vigil:trial-1" and spawned[2].arena_slot == nil,
        "an elite comes out alone, no boss's arena")
  check(stats.e2 and stats.e2.max_hp == 360 and stats.e2.damage_scale == 1.5 and tinted and tinted.color.g == 200,
        "gold, with a crowned one's life and bite")
  S.tick(30)
  check(bar and bar.id == "elite" and bar.label == "GARROW THE UNBOWED" and bar.current == 300, "and a bar of its own")
  S.emit("game.enemy_defeated", {entity = "e2", native_model_id = 1})
  check(S.storage.trial_best.garrow ~= nil, "its best time is kept too")
end

print("34. Georama as a hub: folk saved from the dungeons serve at home (stretch goal 13)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1}, settings = {world_zones = true, world_regions = false, gear = false}})
  local npc, cleared, panel, gilda, stats_set, bound = nil, false, nil, 2000, nil, {}
  S.game.world = S.game.world or {}
  S.game.world.dungeon_npc_set = function(a) npc = copy(a) return {id = a.id} end
  S.game.world.dungeon_npc_clear = function() cleared = true return {} end
  S.game.ui.choice_open = function(a)
    assert(#a.options >= 1 and #a.options <= 4, "1-4 cards")
    panel = copy(a)
    return {open = true}
  end
  S.game.economy = {
    get = function() return {amount = gilda} end,
    spend = function(a) if a.amount > gilda then return nil, {code = "failed"} end gilda = gilda - a.amount return {amount = gilda} end,
    add = function(a) gilda = gilda + a.amount return {amount = gilda} end,
  }
  S.game.weapons = S.game.weapons or {}
  S.game.weapons.stats_set = function(a) stats_set = copy(a) return {} end
  S.game.weapons.durability_set = function() return {} end
  S.load()
  local stats = {}
  S.game.entities.query = function() return {entities = copy(S.monsters or {})} end
  S.game.entities.set_stats = function(a) stats[a.entity] = copy(a) return {current = {damage_scale = 1}} end
  S.game.dungeons.zones_get = function() return {current = 0, floor_zones = 2} end
  local function enter(dungeon, floor, seed)
    S.emit("game.dungeon.generating", {dungeon_id = dungeon, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = dungeon, floor_id = floor, back_floor = false, floor_seed = seed, room_count = 10})
    S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = dungeon, floor_id = floor})
  end
  local function fell_elite(dungeon, floor, id)
    enter(dungeon, floor, 100 + floor)
    S.monsters = {{entity_id = id, revealed = true, native_model_id = 3, definition = {kind = 0}, position = {x = 0, y = 0, z = 0},
                   health = {current = 40, maximum = 40}, combat = {reward_exp = 10, reward_money = 20}}}
    S.tick(80)
    S.emit("game.enemy_defeated", {entity = id, attacker = 0})
  end
  fell_elite(0, 2, "e1")
  check(npc and npc.id == "smith" and npc.place == "player" and any_toast(S, "Gorm the smith"), "the first elite to fall in the cave frees the smith")
  check(npc.model == "gedit/e01/chara/p05a.chr", "in a Norune villager's clothes")
  S.emit("game.dungeon_npc.near", {id = "smith"})
  check(cleared and any_toast(S, "Find me in town"), "walking up sends him home")
  fell_elite(1, 2, "e2")
  S.emit("game.dungeon_npc.near", {id = "trader"})
  fell_elite(2, 2, "e3")
  S.emit("game.dungeon_npc.near", {id = "seeker"})

  S.game.player.get = function() return {hp = 50, character = "toan", weapon = {id = "chronicle:weapon:261", slot = 0, attack = 30, durability_max = 40}} end
  S.emit("game.world.location_changed", {context = "town"})
  S.game.input.consume = function(a) return {pressed = a.id == "hub"} end
  S.tick(1)
  S.game.input.consume = function() return {pressed = false} end
  check(panel and panel.town == true and #panel.options == 3, "in town, D-pad Up calls the three you saved")
  check(panel.subtitle:find('"', 1, true) ~= nil, "and one of them speaks up")
  S.emit("ui.choice_made", {id = "vigil.hub", index = 1})
  check(stats_set and stats_set.attack == 33 and gilda == 1500, "the smith reinforces the weapon for 500 Gilda")
  S.emit("ui.choice_made", {id = "vigil.hub", index = 3})
  check(any_toast(S, "named ones below"), "the seeker sets a hunt")
  for i = 1, 3 do fell_elite(0, 4 + i, "h" .. i) end
  check(any_toast(S, "hunt is done"), "three named foes later, it is done")
  S.emit("game.world.location_changed", {context = "town"})
  S.emit("ui.choice_made", {id = "vigil.hub", index = 3})
  check(gilda == 1500 + 800, "and he pays")
end

print("35. Invaders: a dark copy of a party member hunts you (stretch goal 10)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1},
                      settings = {world_zones = true, world_regions = false, gear = false, elites = false, ambushes = false}}).load()
  local set, bars, removed, gilda = {}, {}, 0, 0
  S.game.party.companion_set = function(a) set[#set + 1] = copy(a) return {character = a.character} end
  S.game.party.list = function() return {{id = "toan", active = true}, {id = "xiao"}, {id = "goro"}} end
  S.game.render.bar_register = function(a) if a.id == "invader" then bars[#bars + 1] = copy(a) end return {} end
  S.game.render.bar_remove = function(a) if a.id == "invader" then removed = removed + 1 end return {} end
  S.game.economy = {add = function(a) gilda = gilda + a.amount return {amount = gilda} end}
  S.game.player.get = function() return {hp = 120, max_hp = 120, character = "toan", position = {x = 0, y = 0, z = 0}} end
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 1, floor_id = 1, back_floor = false, floor_seed = 42, room_count = 10})
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 1, floor_id = 1})
  S.emit("game.dungeon.zone_entered", {zone = 0, previous = -1, zones = 10})
  S.tick(200)
  check(#set == 0, "no invader as you arrive on a floor")
  local zone
  for z = 1, 9 do
    S.emit("game.dungeon.zone_entered", {zone = z, previous = z - 1, zones = 10})
    S.tick(200)
    local hostile = set[#set] and set[#set].hostile
    if hostile then zone = z break end
  end
  local a = zone and set[#set]
  check(a and (a.character == "xiao" or a.character == "goro") and a.hostile.hp == 168 and a.hostile.damage == 20 and a.hostile.tint,
        "an invader: another party member, in black, with a life and a blow for yours")
  check(bars[#bars] and bars[#bars].boss and bars[#bars].label:find("^DARK ") and any_toast(S, "has invaded"), "with a bar of its own")
  S.emit("game.companion.struck", {character = a and a.character, damage = 60, hp = 108, max_hp = 168, killed = false})
  check(bars[#bars].current == 108, "your hits show on its bar")
  S.emit("game.companion.struck", {character = a and a.character, damage = -40, hp = 148, max_hp = 168, killed = false})
  check(bars[#bars].current == 148, "and its flask shows there too")
  S.emit("game.companion.struck", {character = a and a.character, damage = 40, hp = 108, max_hp = 168, killed = false})
  S.emit("game.companion.struck", {character = a and a.character, damage = 108, hp = 0, max_hp = 168, killed = true})
  check(gilda == 300 and removed >= 1 and any_toast(S, "driven out"), "felled, it pays and goes")
  local n = #set
  S.emit("game.dungeon.zone_entered", {zone = zone or 1, previous = (zone or 1) + 1, zones = 10})
  S.tick(200)
  check(#set == n, "and that zone stays clear")
  -- One still out when you leave the floor is sent away.
  for z = 1, 9 do
    if z ~= zone then
      S.emit("game.dungeon.zone_entered", {zone = z, previous = z - 1, zones = 10})
      S.tick(200)
    end
  end
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 2, back_floor = false})
  check(next(set[#set]) == nil or #set == n, "leaving the floor sends any invader away")
end

print("36. Darkness and miasma (stretch goal 9)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1},
                      settings = {world_zones = true, world_regions = false, gear = true, elites = false, ambushes = false, invaders = false}}).load()
  local lighting, poisoned, bursts = {}, 0, 0
  local zone = 1
  S.game.dungeons.lighting_get = function()
    return {side = "front", view_scale = 1, front = {fog = {near = 300, far = 2000, min = 0, max = 255, r = 50, g = 50, b = 60},
                                                     background = {r = 10, g = 10, b = 20}, ambient = {r = 128, g = 128, b = 128}}}
  end
  S.game.dungeons.lighting_set = function(a) lighting[#lighting + 1] = copy(a) return {} end
  S.game.dungeons.zones_get = function() return {current = zone, floor_zones = 4, shrines = {}} end
  S.game.player.status_add = function(a) if a.status == "poison" then poisoned = poisoned + 1 end return {} end
  S.game.effects.burst = function() bursts = bursts + 1 return {} end
  local function enter(dungeon, floor)
    S.emit("game.dungeon.generating", {dungeon_id = dungeon, floor_id = floor, back_floor = false})
    S.emit("game.dungeon.generated", {dungeon_id = dungeon, floor_id = floor, back_floor = false, floor_seed = 77, room_count = 10})
    S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = dungeon, floor_id = floor})
  end
  enter(5, 2)
  S.emit("game.dungeon.zone_entered", {zone = 1, previous = 0, zones = 4})
  local last = lighting[#lighting]
  check(last and last.fog and last.fog.far <= 400 and any_toast(S, "darkness"), "an unlit zone of the Gallery lies in darkness")
  -- The shrine lit, the dark lifts.
  local seeds = S.storage_seeds and S.storage_seeds() or nil
  S.game.dungeons.zones_get = function() return {current = 2, floor_zones = 4, shrines = {}} end
  local n = #lighting
  S.emit("game.dungeon.zone_entered", {zone = 2, previous = 1, zones = 4})
  check(#lighting == n, "dark stays dark while the next zone is unlit too")
  S.emit("game.dungeon.shrine_reached", {zone = 2, x = 4, y = 4})
  S.tick(60)
  check(#lighting == n + 1 and lighting[#lighting].fog.far == 2000 and any_toast(S, "light holds back the dark"),
        "light the zone's shrine and the dark lifts")
  -- The first light gives the Shrine Lantern; worn as a pouch, the dark is a wide ring of light.
  local lantern
  for _, p in ipairs(S.gear or {}) do if p.name == "Shrine Lantern" then lantern = p end end
  check(lantern and lantern.kind == "pouch" and any_toast(S, "old lantern"), "the first shrine lit in the Gallery gives a lantern")
  if lantern then
    lantern.worn_by = "toan"
    S.game.dungeons.zones_get = function() return {current = 3, floor_zones = 4, shrines = {}} end
    S.emit("game.dungeon.zone_entered", {zone = 3, previous = 2, zones = 4})
    check(lighting[#lighting].fog.far > 600, "wearing it, the next dark zone is lit some way round you")
    local gifts = 0
    for _, p in ipairs(S.gear) do if p.name == "Shrine Lantern" then gifts = gifts + 1 end end
    S.game.dungeons.zones_get = function() return {current = 2, floor_zones = 4, shrines = {}} end
    S.emit("game.dungeon.zone_entered", {zone = 2, previous = 3, zones = 4})
    local again = 0
    for _, p in ipairs(S.gear) do if p.name == "Shrine Lantern" then again = again + 1 end end
    check(gifts == 1 and again == 1, "only one lantern a save")
  end

  enter(4, 2)
  local walked = 0
  for cx = 0, 40 do
    S.game.player.get = function() return {hp = 50, max_hp = 50, character = "toan", position = {x = 160 * cx, y = 0, z = 160 * 7}} end
    S.tick(30)
    walked = walked + 1
  end
  check(poisoned > 0 and any_toast(S, "mist here is foul"), "in the Moon Sea some cells are foul and poison you")
  check(bursts > 0, "and the mist shows")
  enter(1, 2)
  local p0 = poisoned
  for cx = 0, 40 do
    S.game.player.get = function() return {hp = 50, max_hp = 50, character = "toan", position = {x = 160 * cx, y = 0, z = 160 * 7}} end
    S.tick(30)
  end
  check(poisoned == p0, "elsewhere the air is clean")
end

print("37. The death ghost (stretch goal 14)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1},
                      settings = {world_zones = true, world_regions = false, gear = false, elites = false, ambushes = false, invaders = false}}).load()
  local bursts = {}
  S.game.effects.burst = function(a) bursts[#bursts + 1] = copy(a) return {} end
  local pos = {x = 0, y = 0, z = 0}
  S.game.player.get = function() return {hp = 50, max_hp = 50, character = "toan", position = {x = pos.x, y = pos.y, z = pos.z}} end
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 1, floor_id = 1, back_floor = false, floor_seed = 42, room_count = 10})
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 1, floor_id = 1})
  for i = 1, 40 do pos.x = 1000 + i * 10 S.tick(10) end
  S.emit("game.dungeon.defeated", {dungeon_id = 1, gilda = 0})
  local g = S.save_data["floors:1:1"] and S.save_data["floors:1:1"].ghost
  check(g and #g.path == 30 and g.path[#g.path].x == 1400, "the last five seconds are kept where you fell")
  -- Back on the floor, far away: nothing. Walk up: the wisp retraces them and ends in a puff.
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 1, floor_id = 1, back_floor = false, floor_seed = 42, room_count = 10})
  pos.x = 4000
  S.tick(60)
  check(#bursts == 0, "nothing from afar")
  pos.x = 1450
  S.tick(10 * 32)
  check(#bursts >= 30 and bursts[1].kind == "heal" and any_toast(S, "ghost walks"), "near the spot, the wisp walks the path")
  local puff
  for _, b in ipairs(bursts) do if b.kind == "smoke" then puff = b end end
  check(puff and puff.position.x == 1400, "and ends in a puff where you went down")
  local n = #bursts
  S.tick(200)
  check(#bursts == n, "once each time you come back")

  -- With the engine's record, the ghost is the hero itself.
  local played
  S.game.world = S.game.world or {}
  S.game.world.ghost_get = function() return {character = "goro", frames = {{1000, 0, 0, 0.5, 2}, {1010, 0, 0, 0.5, 4}}} end
  S.game.world.ghost_play = function(a) played = copy(a) return {playing = true} end
  pos.x = 1000
  for i = 1, 10 do pos.x = 1000 + i * 10 S.tick(10) end
  S.emit("game.dungeon.defeated", {dungeon_id = 1, gilda = 0})
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 1, floor_id = 1, back_floor = false, floor_seed = 42, room_count = 10})
  pos.x = 4000
  S.tick(60)
  n = #bursts
  pos.x = 1100
  S.tick(100)
  check(played and played.character == "goro" and #played.frames == 2, "with the engine's record, the hero's own ghost plays")
  check(#bursts == n, "and no wisp besides")
end

print("38. Elite patrols (stretch goal 8)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1},
                      settings = {world_zones = true, world_regions = false, gear = false, ambushes = false, invaders = false, poise = 0}}).load()
  S.game.dungeons.zones_get = function() return {current = 0, floor_zones = 2} end
  S.game.entities.set_stats = function() return {current = {damage_scale = 1}} end
  S.game.entities.tint = function() return {} end
  S.floor = {{entity_id = "m1", revealed = true, native_model_id = 3, definition = {kind = 0}, position = {x = 0, y = 0, z = 0},
              health = {current = 30, maximum = 30}, combat = {reward_exp = 5, reward_money = 5}}}
  S.monster_at.m1 = {0, 0, 0}
  S.player_at = {3000, 0, 3000}
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 0, floor_id = 2, back_floor = false, floor_seed = 900, room_count = 10})
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 0, floor_id = 2})
  local frame = 0
  local function run(n) for _ = 1, n do frame = frame + 2 S.override({entity = "m1", slot = 0, program_no = 100, model = 0, frame = frame}) end end
  S.tick(80)
  check(any_toast(S, "walks this floor"), "a Dasher is crowned")
  run(1)
  S.tick(40)
  local mark = #S.natives + 1
  run(6)
  local walked
  for i = mark, #S.natives do
    local n = S.natives[i]
    if n.entity == "m1" and n.native == "SET_MOVE" then walked = n.args end
  end
  check(walked and math.abs(walked[1] - 220) < 1e-6 and math.abs(walked[3]) < 1e-6, "with you far off, it walks its beat")
  S.monster_at.m1 = {220, 0, 0}
  mark = #S.natives + 1
  run(2)
  walked = nil
  for i = mark, #S.natives do
    local n = S.natives[i]
    if n.entity == "m1" and n.native == "SET_MOVE" then walked = n.args end
  end
  check(walked and math.abs(walked[1]) < 1e-6 and math.abs(walked[3]) < 1e-6, "and turns back through the middle")
  S.player_at = {240, 0, 0}
  mark = #S.natives + 1
  run(4)
  walked = nil
  for i = mark, #S.natives do
    local n = S.natives[i]
    if n.entity == "m1" and n.native == "SET_MOVE" and math.abs(n.args[1]) < 1e-6 and math.abs(n.args[3]) < 1e-6 then walked = true end
  end
  check(not walked, "near you, it leaves its beat to fight")
end

print("39. One-way drops (stretch goal 11)")
do
  local S = new_game({slot = {slot_id = 1, slot_generation = 1},
                      settings = {world_zones = true, world_regions = false, gear = false, elites = false, ambushes = false, invaders = false}}).load()
  local panel, warped, hurt
  S.game.ui.choice_open = function(a) assert(#a.options >= 1 and #a.options <= 4, "1-4 cards") panel = copy(a) return {open = true} end
  S.game.dungeons.warp = function(a) warped = copy(a) return {} end
  S.game.player.damage = function(a) hurt = a.amount return {} end
  S.game.player.get = function() return {hp = 80, max_hp = 120, character = "toan", position = {x = 0, y = 0, z = 0}} end
  local shrines = {}
  for z = 0, 9 do shrines[#shrines + 1] = {zone = z, x = 10 + z, y = 20} end
  S.game.dungeons.zones_get = function() return {current = 0, floor_zones = 10, shrines = shrines} end
  S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 1, back_floor = false})
  S.emit("game.dungeon.generated", {dungeon_id = 1, floor_id = 1, back_floor = false, floor_seed = 42, room_count = 10})
  S.emit("game.world.location_changed", {context = "dungeon", dungeon_id = 1, floor_id = 1})
  local ledges, at = 0, nil
  for z = 1, 9 do
    panel = nil
    S.emit("game.dungeon.zone_gate_locked", {zone = z, key = "chronicle:item:216", x = 5, y = 5})
    if panel and panel.id == "vigil.drop" then ledges = ledges + 1 at = at or z end
  end
  check(ledges >= 1 and ledges <= 6, "some locked gates have a ledge beside them, not all")
  S.emit("game.dungeon.zone_gate_locked", {zone = at, key = "chronicle:item:216", x = 5, y = 5})
  S.emit("ui.choice_made", {id = "vigil.drop", index = 2})
  check(warped == nil, "Stay keeps you where you are")
  S.emit("game.dungeon.zone_gate_locked", {zone = at, key = "chronicle:item:216", x = 5, y = 5})
  S.emit("ui.choice_made", {id = "vigil.drop", index = 1})
  check(warped and warped.x == 10 + at and warped.y == 21 and warped.teleport, "Drop down lands you by the next zone's shrine")
  check(hurt == 12 and any_toast(S, "way back is shut"), "for a tenth of your life")
end

print("40. Hit feel (§13, item 1)")
do
  local S = new_game({}).load()
  check(S.feel and S.feel.hit_stop.light == 3 and S.feel.hit_stop.heavy == 6 and S.feel.hit_stop.critical == 10 and S.feel.rumble == true,
        "blows freeze a moment as they land, more for heavy ones and criticals, and the pad rumbles")
  local off = new_game({settings = {hit_feel = false}}).load()
  check(off.feel == nil, "off in the settings, off in the game")
end

print("41. Input buffering (§13, item 2)")
do
  local S = new_game({}).load()
  check(S.tuning and S.tuning.input_buffer == 12, "a roll or R2 pressed a little early is kept 12 frames")
  local off = new_game({settings = {input_buffer = 0}}).load()
  check(off.tuning and off.tuning.input_buffer == nil, "0 in the settings: pressed on the frame, as the game has it")
  check(S.tuning.lock_camera == true, "locked on, the camera keeps the target framed (§13, item 6)")
  check(S.tuning.chain_cancel == 6, "a landed blow chains into the heavy, and the heavy back into the combo")
  local loose = new_game({settings = {chain_cancel = false}}).load()
  check(loose.tuning and loose.tuning.chain_cancel == nil, "Chain attacks off: each attack plays out")
end

print("42. Telegraphs (§13, item 4)")
do
  local function wind_up(settings)
    local S = new_game({settings = settings}).load()
    S.monster_at.m1 = {15, 0, 0}
    local frame = 0
    local function run(n)
      for _ = 1, n do
        frame = frame + 2
        S.override({entity = "m1", slot = 0, program_no = 100, model = 0, frame = frame})
      end
    end
    local swung
    for _ = 1, 200 do
      run(1)
      for _, n in ipairs(S.natives) do if n.entity == "m1" and n.native == "SET_MOTION" and n.args[1] == 13 then swung = true end end
      if swung then break end
    end
    S.bursts, S.sounds = {}, {}
    S.motion_frame = 155 -- early in the Dasher's wind-up (151-166): nothing yet
    run(4)
    local early = #S.bursts + #S.sounds
    S.motion_frame = 162 -- the top of the wind-up, a beat before the blow at 169
    run(3)
    return S, swung, early
  end
  local S, swung, early = wind_up({poise = 0})
  check(swung and early == 0, "a Dasher winds up without a cue at first")
  local glint = S.bursts[1]
  check(glint and glint.kind == "guard" and glint.scale < 1 and #S.bursts == 1, "a glint at the top of the wind-up, once")
  check(S.sounds[1] and S.sounds[1].se == 370, "with a soft ping")
  local off = wind_up({poise = 0, telegraphs = false})
  check(#off.bursts == 0 and #off.sounds == 0, "off in the settings: no cue")
end

print("43. Ranged and casting enemies (§13, item 7)")
do
  local function shooter(settings, at)
    local S = new_game({settings = settings}).load()
    S.floor = {{entity_id = "r1", native_model_id = 5}}
    S.monster_at = {r1 = at}
    local frame = 0
    for _ = 1, 300 do
      frame = frame + 2
      S.override({entity = "r1", slot = 0, program_no = 100, model = 0, frame = frame})
    end
    return S
  end
  local S = shooter({}, {120, 0, 0})
  local motion, shot
  for _, n in ipairs(S.natives) do
    if n.entity == "r1" and n.native == "SET_MOTION" and n.args[1] == 16 then motion = true end
    if n.entity == "r1" and n.native == "SET_SHOT" then shot = n.args end
  end
  check(motion and shot and shot[1] == "dcol0", "a shooter in range plays its shot and fires from its own frame")
  check(S.bursts and S.bursts[1] and S.bursts[1].kind == "guard", "after a glint")
  local near = shooter({}, {30, 0, 0})
  local back
  for _, n in ipairs(near.natives) do
    if n.entity == "r1" and n.native == "SET_MOVE" and n.args[1] > 30 then back = true end
  end
  check(back, "too close, it backs off")
  local off = shooter({shooters = false}, {120, 0, 0})
  local fired
  for _, n in ipairs(off.natives) do if n.native == "SET_SHOT" then fired = true end end
  check(not fired and (off.retail or 0) > 0, "off in the settings: the game's own script")
  local late = new_game({}).load()
  late.floor = {{entity_id = "r2", native_model_id = 161}}
  late.monster_at = {r2 = {120, 0, 0}}
  local f2 = 0
  for _ = 1, 300 do f2 = f2 + 2 late.override({entity = "r2", slot = 0, program_no = 100, model = 0, frame = f2}) end
  local shot2
  for _, n in ipairs(late.natives) do if n.entity == "r2" and n.native == "SET_SHOT" then shot2 = n.args end end
  check(shot2 and shot2[1] == "dcol2", "the later dungeons' shooters too (34 families)")
  local caster = new_game({}).load()
  caster.floor = {{entity_id = "r3", native_model_id = 26}}
  caster.monster_at = {r3 = {120, 0, 0}}
  local f3 = 0
  for _ = 1, 900 do f3 = f3 + 2 caster.override({entity = "r3", slot = 0, program_no = 100, model = 0, frame = f3}) end
  local one, two
  for _, n in ipairs(caster.natives) do
    if n.entity == "r3" and n.native == "SET_SHOT" then one = true end
    if n.entity == "r3" and n.native == "SET_SHOT2" and n.args[1] == "dcol2" then two = true end
  end
  check(one and two, "a caster alternates its two spells")
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
