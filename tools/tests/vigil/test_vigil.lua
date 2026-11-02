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
                    "cooldown", "hits", "cues", "animation", "cancel", "cancel_after", "variants", "blend_in", "camera"}) do MOVE_FIELDS[k] = true end
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
    save_data = {}, slot = opts.slot,
    natives = {}, monster_at = {}, player_at = {0, 0, 0}, monster_motions = {}, models_loaded = false,
    floor = {{entity_id = "m1", native_model_id = 3}, {entity_id = "m2", native_model_id = 52}, {entity_id = "m3", native_model_id = 3},
             {entity_id = "m4", native_model_id = 1}, {entity_id = "m5", native_model_id = 3},
             {entity_id = "m6", native_model_id = 3}, {entity_id = "m7", native_model_id = 3}},
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
        local stem = ({[1] = "e03a", [3] = "e06a"})[a.model]
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
          local key = m.character .. "/" .. tostring(m.trigger) .. "/" .. tostring(m.chain) .. "/" .. tostring(m.direction)
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
    save = {
      slot_id = function() return S.slot and copy(S.slot) or {} end,
      get = function(key) return copy(S.save_data[key]) end,
      set = function(key, value) S.save_data[key] = copy(value); return true end,
    },
    dungeons = {
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
        assert(#a.zones <= 24, "24 zones at most")
        for _, z in ipairs(a.smoke or {}) do
          assert(z >= 1 and z < #a.zones, "smoke lists gates 1 to zones - 1")
          for _, o in ipairs(a.open or {}) do assert(o ~= z, "a smoke gate isn't built open") end
        end
        for k in pairs(a) do
          assert(k == "zones" or k == "open" or k == "shrines" or k == "exit_floor" or k == "smoke" or k == "shrine_heal" or k == "sanctuary", "set_zones field " .. k)
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
          assert(type(v) == "number" or type(v) == "boolean" or (type(v) == "table" and (v.out == "int" or v.out == "float")),
                 "monsters.call args are numbers, booleans or outs")
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
    entities = {query = function() return {entities = copy(S.floor)} end},
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
  S.game.ui.choice_open = function(a)
    assert(type(a.id) == "string" and #a.options >= 1 and #a.options <= 4, "choice_open takes 1-4 options")
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
  check(S.moves and #S.moves == 22, "fourteen evades (a dodge and a dodge_back for each of the six, Toan's side rolls) and Toan's eight attacks",
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
  check(S.moves and #S.moves == 8 and moves_by(S)["toan/dodge"] == nil and S.tuning.dodge_power == nil,
    "evades off: Toan's attacks stay, no evades and no shove dodge")
  S.set("toan_attacks", false)
  check(S.moves == nil, "and with his attacks off too, no moves at all")
  S.set("evades", true)
  check(S.moves and #S.moves == 14 and moves_by(S)["toan/heavy"] == nil, "evades alone without his attacks")
  S.set("enemy_brain", false)
  check(S.override == nil, "the enemy brain off: the monsters' own scripts again")
  S.set("enemy_brain", true)
  check(S.override ~= nil, "and back on")
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
  check(S.override == nil, "the Gauntlet's monsters keep their own scripts")
  check(S.npc_models and #S.npc_models == 0, "no Fairy King in the Gauntlet's cave")
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
  check(S.moves and #S.moves == 22 and moves_by(S)["toan/dodge"].gauge == 50, "back afterwards, with the new setting")
  check(S.override ~= nil, "the enemy brain back too")
  check(S.npc_models and #S.npc_models == 1, "and the King's model back with the cave")
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
  local S = new_game().load()
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
        ids.e03a_roll_right == 1 and ids.e03a_whirl == 1, "each monster's rolls and new attack are registered on its model")
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
  check(S.panel and S.panel.id == "vigil.shrine" and #S.panel.options == 4 and S.panel.cursor == 4, "Square in its water opens the panel, on Level up")
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

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
