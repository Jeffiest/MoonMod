-- Vigil: Souls-lite combat for the story game. This is the S1 prototype (VIGIL_PLAN.md section 4), built only from
-- what the engine already offers:
--
--   * L2 evades. A roll with the stick pushed, a backstep with it at rest, untouchable while they last, and able to
--     cut a swing short a few frames after its blow (player.moves_set). Each costs weapon gauge (the move's
--     `gauge`): that gauge is Dark Cloud's own stamina bar (VIGIL_PLAN.md section 7), so an empty bar means no evade.
--     The motions are copies of the Gauntlet's (tools/anim), in resources/anims.
--   * Enemies hit harder (a player damage formula).
--   * A hit stuns you for less, and so protects you for less: the game's recoil frames are also its invincibility
--     frames, so a smaller recoil lets the next hit land sooner (player.tuning_set recoil_scale).
--   * Holding the guard slows the gauge's recovery (gauge_refill, set again whenever the guard is pressed or let go).
--   * Character switches take longer (swap_delay), and enemies can't hand you the "Stamina" ailment, which in this
--     game is a power-up (status_immune).
--
-- What S1 can't do yet, and the engine work that brings it (VIGIL_PLAN.md section 2): guard only in front, charge the
-- gauge for blocked hits, break the guard, parry (E1); stop a hit refilling the gauge to full, make the first swing
-- cost (E2); read the gauge (E3).
--
-- Vigil sits out other mods' game modes (Dark Genie's Gauntlet), as the Cookbook's "Share the game with other mods"
-- describes: no moves, no tuning, formulas back to x1, until the session ends.

local ID = "moonmod.vigil"

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil, {code = "unsupported", message = "operation missing"} end
  local ok, value, err = pcall(fn, ...)
  if not ok then return nil, {code = "error", message = tostring(value)} end
  return value, err
end

local function message(err) return type(err) == "table" and tostring(err.message) or tostring(err) end

local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= type(fallback) then return fallback end
  return value
end

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

local function toast(text, frames) try(game.ui.notify, {message = text, duration_frames = frames or 300}) end

-- Evades ----------------------------------------------------------------------------------------------------------
-- One pair per character: `dodge` (L2 with the stick pushed, turning the way it points) and `dodge_back` (L2 with
-- the stick at rest, keeping his facing). Melee fighters roll and backstep; Xiao, Ruby and Osmond tumble and hop back
-- (the hop without its shot: an evade here never attacks).
local EVADES = {
  toan   = {dodge = "toan_dive_roll", back = "toan_backstep"},
  xiao   = {dodge = "xiao_tumble",   back = "xiao_hop_shot"},
  goro   = {dodge = "goro_roll",     back = "goro_backstep"},
  ruby   = {dodge = "ruby_tumble",   back = "ruby_hop_shot"},
  ungaga = {dodge = "ungaga_roll",   back = "ungaga_backstep"},
  osmond = {dodge = "osmond_tumble", back = "osmond_hop_shot"},
}
local ORDER = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
-- How each motion plays (from the Gauntlet's tuned values): the rolls are slow and long, the tumbles quicker. Toan's
-- dive roll (Vigil's own, tools/anim/vigil_moves.py) leaves the floor and takes about a second: about 43 units carried
-- over its first 27 ticks (the dive and the somersault), against the roll's 29 over 24, then getting up.
local SHAPE = {
  dive_roll = {speed = 0.45, lunge = 3.2, lunge_decay = 0.12},
  roll      = {speed = 0.5, lunge = 2.4, lunge_decay = 0.1},
  tumble    = {speed = 1.2, lunge = 2.2, lunge_decay = 0.11},
  backstep  = {speed = 1.1, lunge = 2.2, lunge_decay = 0.2, lunge_angle = 180},
  hop_shot  = {speed = 1.1, lunge = 2.0, lunge_decay = 0.2, lunge_angle = 180},
}

local animated -- nil: not tried yet; true: every motion registered; false: fall back to the tuning dodge
local function register_motions()
  if animated ~= nil then return animated end
  animated = true
  for _, who in ipairs(ORDER) do
    for _, anim in pairs(EVADES[who]) do
      local ok, err = call(game.animations.player_register, {id = anim, file = "resources/anims/" .. anim .. ".json"})
      if not ok then
        animated = false
        moonmod.log("warn", "motion " .. anim .. " not registered: " .. message(err))
      end
    end
  end
  return animated
end

local function evade_move(who, trigger, anim)
  local kind = anim:match("_([%a_]+)$")
  local shape = SHAPE[kind] or SHAPE.roll
  local move = {
    id = "vigil_" .. anim, character = who, trigger = trigger, animation = anim,
    speed = shape.speed, lunge = shape.lunge, lunge_decay = shape.lunge_decay,
    invincible = true, wear = 0,
    gauge = setting("evade_cost", 35),
    cooldown = setting("evade_cooldown", 30),
    cancel = true, cancel_after = setting("evade_commit", 6),
    cues = {{at = 0, sound = "action"}},
  }
  if shape.lunge_angle then move.lunge_angle = shape.lunge_angle end
  return move
end

local function moves()
  local list = {}
  for _, who in ipairs(ORDER) do
    list[#list + 1] = evade_move(who, "dodge", EVADES[who].dodge)
    list[#list + 1] = evade_move(who, "dodge_back", EVADES[who].back)
  end
  return list
end

-- Guard -----------------------------------------------------------------------------------------------------------
-- The game's guard is lock on, then hold R1. Mods read the pad through their own bindings, so Vigil binds R1 on the
-- controller and, if the player picks one, the keyboard key they guard with. The game still sees the button.
local guard_bound = nil
local function bind_guard()
  local keys = {"Gamepad:rightshoulder"}
  local key = setting("guard_key", "None")
  if key ~= "None" then keys[#keys + 1] = key end
  local signature = table.concat(keys, "+")
  if guard_bound == signature then return end
  try(game.input.unbind, {id = "guard"})
  local ok, err = call(game.input.bind, {id = "guard", keys = keys})
  if ok then guard_bound = signature else guard_bound = nil; moonmod.log("warn", "guard binding: " .. message(err)) end
end

local function guard_held()
  local state = try(game.input.state, {id = "guard"})
  return type(state) == "table" and state.down == true
end

-- Applying the rules ----------------------------------------------------------------------------------------------
local in_sandbox = false
local guarding = false
local applied = {} -- what the last apply() asked for, for the Mod Manager's "Check" action

local function tuning()
  local refill = setting("gauge_refill", 100) / 100
  if guarding then refill = refill * setting("guard_refill", 25) / 100 end
  local t = {
    recoil_scale = clamp(setting("recoil", 40) / 100, 0.25, 4),
    gauge_refill = clamp(refill, 0.25, 4),
    swap_delay = clamp(setting("swap_delay", 200) / 100, 0, 4),
  }
  -- Send a field only when it says something: an empty Lua table reaches the engine as a JSON object.
  if setting("no_power_up", true) then t.status_immune = {"stamina"} end
  if setting("no_minimap", false) then t.map_hidden = true end
  if setting("evades", true) and animated == false then
    -- Without the evade motions L2 still dodges: the engine's own shove dodge, untouchable for a moment, free of gauge.
    t.dodge_power = 1
    t.dodge_invincible_frames = 14
  end
  return t
end

local function apply_tuning()
  local t = tuning()
  local ok, err = call(game.player.tuning_set, t)
  if not ok then moonmod.log("warn", "tuning: " .. message(err)) end
  applied.tuning = t
end

local function apply()
  if in_sandbox then return end
  local ok, err = call(game.combat.register_player_formula,
    {id = "enemy-damage", operation = "multiply", value = setting("enemy_damage", 250) / 100})
  if not ok then moonmod.log("warn", "enemy damage formula: " .. message(err)) end
  applied.enemy_damage = setting("enemy_damage", 250) / 100

  if setting("evades", true) and register_motions() then
    local set, set_err = call(game.player.moves_set, {moves = moves()})
    if not set then
      moonmod.log("warn", "evade moves: " .. message(set_err))
      applied.evades = "refused: " .. message(set_err)
    else
      applied.evades = "on"
    end
  else
    try(game.player.moves_clear)
    applied.evades = setting("evades", true) and "tuning dodge (motions missing)" or "off"
  end

  bind_guard()
  guarding = guard_held()
  apply_tuning()
end

local function stand_down()
  try(game.player.moves_clear)
  try(game.player.tuning_clear)
  try(game.combat.register_player_formula, {id = "enemy-damage", operation = "multiply", value = 1})
  guarding = false
  applied = {stood_down = true}
end

local function set_sandbox(now)
  if now == in_sandbox then return end
  in_sandbox = now
  if now then stand_down() else apply() end
end

-- The controls, once per install.
local function tips()
  if not setting("tips", true) or moonmod.storage.get("told") then return end
  moonmod.storage.set("told", true)
  toast("Vigil: L2 rolls, or backsteps with the stick at rest. Each costs weapon gauge.")
  toast("Vigil: lock on and hold R1 to guard. The gauge recovers slowly while you do.")
  toast("Vigil: enemies hit hard. Read them, guard or roll, then punish.")
end

-- Events ----------------------------------------------------------------------------------------------------------
moonmod.on("game.tick", function()
  if in_sandbox then return end
  local now = guard_held()
  if now ~= guarding then
    guarding = now
    apply_tuning()
  end
end)

moonmod.on("settings.changed", function()
  if in_sandbox then return end
  apply()
end)

moonmod.on("game.world.location_changed", function(e)
  if in_sandbox or type(e) ~= "table" or e.context ~= "dungeon" then return end
  tips()
end)

moonmod.on("game.session.started", function(e)
  local session = try(game.session.get)
  set_sandbox(type(session) == "table" and session.kind == "sandbox" and session.owner ~= ID)
end)
moonmod.on("game.session.ended", function() set_sandbox(false) end)

-- Mod Manager: what Vigil has asked the engine for right now.
try(game.ui.register, {id = "check", label = "Check", description = "Show what Vigil has set right now."})
moonmod.on("ui.action", function(action)
  if type(action) ~= "table" or action.id ~= "check" then return end
  if in_sandbox then toast("Vigil sits out this game mode.") return end
  local t = applied.tuning or {}
  toast(string.format("Vigil: evades %s, enemy damage x%.2f, recoil x%.2f, gauge refill x%.2f%s",
    tostring(applied.evades), applied.enemy_damage or 1, t.recoil_scale or 1, t.gauge_refill or 1,
    guarding and " (guarding)" or ""))
end)

-- Start -----------------------------------------------------------------------------------------------------------
local session = try(game.session.get)
in_sandbox = type(session) == "table" and session.kind == "sandbox" and session.owner ~= ID
if in_sandbox then stand_down() else apply() end

local mod = {}
function mod.on_load() moonmod.log("info", ID .. " ready" .. (in_sandbox and " (sitting out a game mode)" or "")) end
function mod.on_unload() moonmod.log("info", ID .. " unloaded") end
return mod
