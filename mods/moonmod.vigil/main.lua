-- Vigil: Souls-lite combat for the story game. This is the S1 prototype (VIGIL_PLAN.md section 4), built only from
-- what the engine already offers:
--
--   * L2 evades. A roll with the stick pushed, a backstep with it at rest, untouchable while they last, and able to
--     cut a swing short a few frames after its blow (player.moves_set). Each costs weapon gauge (the move's
--     `gauge`): that gauge is Dark Cloud's own stamina bar (VIGIL_PLAN.md section 7), so an empty bar means no evade.
--     The motions are copies of the Gauntlet's (tools/anim), in resources/anims.
--   * Toan's attacks: a heavy, two combo finishers, a lunge and a backing-off strike when locked on, a running attack,
--     a follow-up out of an evade and a guard counter (player.moves_set). Each motion is a slot a player can fill with
--     their own (tools/anim/reference); see "Toan's attacks" below.
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
-- Out of a run, Toan pushes off whichever foot is leading: his dive roll goes off his left foot, and this one, for the
-- part of his stride (native motion 1, his run) when his right foot is ahead, off his right (move `variants`).
local LEAD_FOOT = {
  toan = {anim = "toan_dive_roll_right", motion = 1, spans = {{0, 0.3}, {0.8, 1}}},
}
-- Locked on with the stick to the side, Toan rolls sideways and keeps facing the target (the dodge's `direction`):
-- the dive roll with his body turned into the way he goes and back (tools/anim/vigil_side_rolls.py).
local SIDE_ROLLS = {
  toan = {left = "toan_side_roll_left", right = "toan_side_roll_right"},
}
-- Frames to fade into a move from the pose he is in. The game's own fade (10) smears a roll's quick crouch into his
-- run, which reads as a stop before it; a short one shows it at once.
local BLEND_IN = {evade = 3, attack = 4}
-- Steps the camera takes to close on Toan while he evades. The game's own (8 steps, 14 locked on) leaves it trailing
-- a roll that carries him 40-odd units in a second.
local EVADE_CAMERA = {toan = 3}
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

local function register(anim)
  local ok, err = call(game.animations.player_register, {id = anim, file = "resources/anims/" .. anim .. ".json"})
  if not ok then moonmod.log("warn", "motion " .. anim .. " not registered: " .. message(err)) end
  return ok and true or false
end

local animated -- nil: not tried yet; true: every motion registered; false: fall back to the tuning dodge
local function register_motions()
  if animated ~= nil then return animated end
  animated = true
  for _, who in ipairs(ORDER) do
    for _, anim in pairs(EVADES[who]) do
      if not register(anim) then animated = false end
    end
    if LEAD_FOOT[who] and not register(LEAD_FOOT[who].anim) then animated = false end
    for _, anim in pairs(SIDE_ROLLS[who] or {}) do
      if not register(anim) then animated = false end
    end
  end
  return animated
end

local EVADE_IDS = {} -- the evades' move ids, so the enemy brain knows a roll from a swing
local function evade_move(who, trigger, anim, direction)
  EVADE_IDS["vigil_" .. anim] = true
  local kind = direction and "dive_roll" or anim:match("_([%a_]+)$")
  local shape = SHAPE[kind] or SHAPE.roll
  local move = {
    id = "vigil_" .. anim, character = who, trigger = trigger, animation = anim, direction = direction,
    speed = shape.speed, lunge = shape.lunge, lunge_decay = shape.lunge_decay, blend_in = BLEND_IN.evade,
    invincible = true, wear = 0, camera = EVADE_CAMERA[who],
    gauge = setting("evade_cost", 35),
    cooldown = setting("evade_cooldown", 30),
    cancel = true, cancel_after = setting("evade_commit", 6),
    cues = {{at = 0, sound = "action"}},
  }
  if shape.lunge_angle then move.lunge_angle = shape.lunge_angle end
  local lead = trigger == "dodge" and not direction and LEAD_FOOT[who]
  if lead then
    move.variants = {}
    for _, span in ipairs(lead.spans) do
      move.variants[#move.variants + 1] = {animation = lead.anim, motion = lead.motion, from = span[1], to = span[2]}
    end
  end
  return move
end

-- Toan's attacks ----------------------------------------------------------------------------------------------------
-- A moveset on top of his native combo: R2 a heavy blow, R2 partway through the combo a finisher (after two blows, or
-- three), locked on A toward the target a lunge and away from it a strike while backing off, A out of a run a running
-- attack, A late in an evade a follow-up, A while guarding a counter. The motions in resources/anims start as copies
-- of the Gauntlet's (tools/anim/toan_moves.py), and so do the numbers. Each motion is a slot: a player who owns a
-- moveset can swap their own in, in their save only (tools/anim/reference/import_motion.py --moveset); the hits keep
-- their timing because the importer lines each blow up with the one it replaces.
local ATTACKS = {
  {anim = "toan_heavy", trigger = "heavy", speed = 0.9, lunge = 1.2, lunge_decay = 0.15, cooldown = 30, wear = 1.5,
    hits = {{at = 0.43, radius = 11, reach = 8, damage = 2.4, knockback = 5, heavy = true, burst = "impact", burst_scale = 1.5}},
    cues = {{at = 0.05, sound = "voice"}, {at = 0.36, sound = "swing_heavy", trail = "slam"}}},
  {anim = "toan_finisher_2", trigger = "combo_finisher", chain = 2, speed = 1.1, lunge = 1.0, lunge_decay = 0.15, cooldown = 20,
    hits = {{at = 0.29, radius = 10, reach = 6, height = 8, damage = 1.6, knockback = 6, heavy = true},
            {at = 0.4, radius = 10, reach = 5, height = 14, damage = 0.8, knockback = 2}},
    cues = {{at = 0.1, sound = "voice_2"}, {at = 0.25, sound = "swing", trail = "wide"}}},
  {anim = "toan_finisher_3", trigger = "combo_finisher", chain = 3, speed = 1.0, spin = 1, spin_from = 0.24, spin_to = 0.44,
    cooldown = 30,
    hits = {{at = 0.28, radius = 15, reach = 0, damage = 0.9}, {at = 0.36, radius = 15, reach = 0, damage = 0.9},
            {at = 0.44, radius = 15, reach = 0, damage = 0.9},
            {at = 0.59, radius = 11, reach = 9, damage = 2.0, knockback = 5, heavy = true, burst = "sparks", burst_scale = 1.5}},
    cues = {{at = 0.05, sound = "shout"}, {at = 0.25, sound = "swing", trail = "heavy"}, {at = 0.55, sound = "shout_2", trail = "wide"}}},
  {anim = "toan_run_attack", trigger = "run_attack", run_frames = 20, speed = 1.0, lunge = 3.4, lunge_decay = 0.2, cooldown = 30,
    hits = {{at = 0.36, radius = 10, reach = 9, damage = 1.4, knockback = 3}, {at = 0.5, radius = 10, reach = 11, damage = 1.0, knockback = 2}},
    cues = {{at = 0.15, sound = "voice_2"}, {at = 0.3, sound = "swing", trail = "wide"}}},
  {anim = "toan_lunge", trigger = "lock_attack", direction = "toward", speed = 1.0, lunge = 3.0, lunge_decay = 0.22, cooldown = 24,
    hits = {{at = 0.36, radius = 10, reach = 9, damage = 1.3, knockback = 3}, {at = 0.5, radius = 10, reach = 11, damage = 0.8, knockback = 2}},
    cues = {{at = 0.15, sound = "voice_2"}, {at = 0.3, sound = "swing", trail = "wide"}}},
  {anim = "toan_back_attack", trigger = "lock_attack", direction = "away", speed = 1.0, lunge = 2.2, lunge_decay = 0.2,
    lunge_angle = 180, cooldown = 16,
    hits = {{at = 0.3, radius = 11, reach = 7, damage = 1.2, knockback = 3}},
    cues = {{at = 0.1, sound = "voice"}, {at = 0.22, sound = "swing", trail = "light"}}},
  {anim = "toan_roll_attack", trigger = "evade_attack", speed = 1.0, lunge = 2.0, lunge_decay = 0.15, cooldown = 20,
    hits = {{at = 0.32, radius = 11, reach = 8, height = 6, damage = 1.6, knockback = 4}},
    cues = {{at = 0.05, sound = "voice_2"}, {at = 0.25, sound = "swing", trail = "wide"}}},
  {anim = "toan_guard_counter", trigger = "guard_attack", speed = 1.0, invincible = true, cooldown = 20,
    hits = {{at = 0.34, radius = 10, reach = 7, height = 8, damage = 1.8, knockback = 4, heavy = true},
            {at = 0.46, radius = 10, reach = 5, height = 12, damage = 1.0, knockback = 2}},
    cues = {{at = 0.1, sound = "voice"}, {at = 0.3, sound = "swing_heavy", trail = "wide"}}},
}

local armed -- nil: not tried yet; otherwise whether every attack motion registered
local function register_attacks()
  if armed ~= nil then return armed end
  armed = true
  for _, attack in ipairs(ATTACKS) do
    if not register(attack.anim) then armed = false end
  end
  return armed
end

local function attack_move(attack)
  local move = {id = "vigil_" .. attack.anim, character = "toan", animation = attack.anim, blend_in = BLEND_IN.attack}
  for k, v in pairs(attack) do
    if k ~= "anim" then move[k] = v end
  end
  return move
end

local function moves(evades, attacks)
  local list = {}
  if evades then
    for _, who in ipairs(ORDER) do
      list[#list + 1] = evade_move(who, "dodge", EVADES[who].dodge)
      list[#list + 1] = evade_move(who, "dodge_back", EVADES[who].back)
      for side, anim in pairs(SIDE_ROLLS[who] or {}) do list[#list + 1] = evade_move(who, "dodge", anim, side) end
    end
  end
  if attacks then
    for _, attack in ipairs(ATTACKS) do list[#list + 1] = attack_move(attack) end
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

-- Enemies that fight like it -------------------------------------------------------------------------------------------
-- The game's own scripts walk a monster in and swing the moment you are in reach. Vigil's brain takes over the idle
-- program of the monsters listed in BRAINS (hook native.monster.run, program 100) and drives them with the natives
-- their own scripts use. A monster keeps its distance and circles you, then commits: it turns to track you through the
-- wind-up and stops tracking just before the blow, sometimes holding the wind-up to catch an early roll, sometimes
-- feinting (a wind-up broken off into a sidestep, then the real swing), sometimes chaining up to three blows, and it
-- stands open for a moment after. From the edge of the circle it may rush in and swing as it arrives. Against your
-- swing it sidesteps, rolls aside (MONSTER_MOVES), steps back or (with a shield) blocks, and answers at once. Against your roll it holds its
-- wind-up, turning with you, until the roll is spent. Only one monster attacks at a time. Being hit and dying still run the
-- retail script; other monsters keep their own. Keyed by the native model number (entities.query's native_model_id).
local BRAINS = {
  -- Frames are the motion's own, measured in the game: the Dasher's attack_1 runs 151-180 and pauses at the top of its
  -- wind-up (166) before the blow (169); attack_2 runs 191-215, its blow at about 200.
  [3] = { -- the Dasher (e06a), the first floor of the Divine Beast Cave
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.6, sidestep = 0.6,
    walk_speed = 0.55, press_speed = 0.8, step_speed = 0.55, ring = 26, reach = 18, rush = 0.4, feint = 0.15,
    attacks = {
      {motion = 13, from = 151, speed = 0.42, hold = 166, track_to = 167, lunge = 0.6, done = 180, next = 2},
      {motion = 16, from = 191, speed = 0.42, hold = 196, track_to = 198, lunge = 0.5, done = 215, next = 1},
    },
  },
  -- The Skeleton Soldier's blows land at frame 64 of attack_1 (50-70) and 84 of attack_2 (75-95). Its spawn script
  -- opens a guard window over its guard motions (frames 100-120), so playing them blocks a blow.
  [1] = { -- the Skeleton Soldier (e03a)
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.3, sidestep = 0.5,
    guard = {up = 5, hold = 6, down = 7, chance = 0.5},
    walk_speed = 0.5, press_speed = 0.75, step_speed = 0.5, ring = 24, reach = 16, rush = 0.25, feint = 0.2,
    attacks = {
      {motion = 13, from = 50, speed = 0.42, hold = 61, track_to = 62, lunge = 0.5, done = 70, next = 2},
      {motion = 16, from = 75, speed = 0.42, hold = 81, track_to = 82, lunge = 0.5, done = 95, next = 1},
    },
  },
}

local hook_frame = 0 -- the monster hook's latest frame

-- Each monster's own new motions (tools/anim/vigil_monster_moves.py), appended to its native model by
-- animations.monster_register: a sideways roll each way, and a new attack. The attack's frames are its own, counted
-- from its first; its hits take the kind of the monster's first native blow, times damage.
local MONSTER_MOVES = {
  [3] = { -- the Dasher's pounce: the mace up by 6, a leap, the mace slammed down in front on landing (16)
    roll_left = "e06a_roll_left", roll_right = "e06a_roll_right", roll_chance = 0.6,
    attack = {id = "e06a_pounce", speed = 0.45, hold = 5, track_to = 7, lunge = 1.3, chance = 0.3,
              -- the mace's head lands 21 out and the hand 13: one sphere each, so it catches you close or far
              hits = {{bone = "dcol0", radius = 5, from = 14, to = 22, damage = 1.2},
                      {bone = "r_hand", radius = 5, from = 15, to = 22, damage = 1.2}}},
  },
  [1] = { -- the Skeleton's whirl: the knife drawn back by 7, one full turn with the blade out (10-24)
    roll_left = "e03a_roll_left", roll_right = "e03a_roll_right", roll_chance = 0.4,
    attack = {id = "e03a_whirl", speed = 0.4, hold = 6, track_to = 9, lunge = 0.45, chance = 0.3,
              hits = {{bone = "dcol0", radius = 5, from = 12, to = 24, damage = 1.0},
                      {bone = "hand_r", radius = 4, from = 12, to = 24, damage = 1.0}}},
  },
}

local monster_moves_registered = false
local function register_monster_moves()
  if monster_moves_registered then return end
  monster_moves_registered = true
  for model, m in pairs(MONSTER_MOVES) do
    for _, id in ipairs({m.roll_left, m.roll_right}) do
      local ok, err = call(game.animations.monster_register, {id = id, model = model, file = "resources/anims/" .. id .. ".json"})
      if not ok then moonmod.log("warn", "monster motion " .. id .. ": " .. message(err)) end
    end
    local a = m.attack
    local ok, err = call(game.animations.monster_register,
      {id = a.id, model = model, file = "resources/anims/" .. a.id .. ".json", hits = a.hits})
    if not ok then moonmod.log("warn", "monster motion " .. a.id .. ": " .. message(err)) end
  end
end

-- The new motions' numbers once a floor has loaded the model (nil before, or if they are missing): kind.roll =
-- {left, right} and the attack added to kind.attacks as kind.special.
local function resolve_moves(kind, model)
  if kind.resolved or not MONSTER_MOVES[model] or hook_frame < (kind.resolve_at or 0) then return end
  kind.resolve_at = hook_frame + 300 -- not on this floor's model yet (registered after it loaded): ask now and then
  local listed = try(game.animations.monster_list)
  local by_id = {}
  for _, m in ipairs(type(listed) == "table" and listed.motions or {}) do
    if m.model == model and m.motion then by_id[m.id] = m end
  end
  local moves = MONSTER_MOVES[model]
  local l, r, at = by_id[moves.roll_left], by_id[moves.roll_right], by_id[moves.attack.id]
  if not (l or r or at) then return end
  kind.resolved = true
  if l and r then kind.roll = {left = l.motion, right = r.motion, chance = moves.roll_chance} end
  if at then
    local a = moves.attack
    kind.attacks[#kind.attacks + 1] = {motion = at.motion, from = at.start, speed = a.speed, hold = at.start + a.hold,
      track_to = at.start + a.track_to, lunge = a.lunge, done = at.start + at.length}
    kind.special = {n = #kind.attacks, chance = a.chance}
  end
end

local F, I = {out = "float"}, {out = "int"}
local minds = {}   -- entity -> what that monster is doing
local kinds = {}   -- entity -> its BRAINS entry, or false
local turn = nil   -- {entity, at}: the monster whose turn it is to attack
local rolled = nil -- the hook's frame when the player last started an evade
local brain_on = false

local function native(entity, name, args)
  local ok, r = pcall(game.monsters.call, {entity = entity, native = name, args = args})
  if ok and type(r) == "table" then return r.out or {} end
end

local function spot(entity, who)
  local o = native(entity, "GET_POSITION", {who, F, F, F})
  if o and o[3] then return {o[1], o[2], o[3]} end
end

local function face(entity, at, rate) native(entity, "SET_ROTATION", {at[1], at[2], at[3], rate}) end
local function go(entity, at, speed) native(entity, "SET_MOVE", {at[1], at[2], at[3], speed}) end
-- No args at all: an empty table goes over as {} rather than a list, and the call is turned away.
local function halt(entity) native(entity, "SET_MOVE_CANSEL") end

-- Toward the player round whatever is in the way, as its own script does: the first of these headings the floor
-- carries it along for 30 units.
local HEADINGS = {0, 45, -45, 90, -90}
local function way(entity, me, ux, uz)
  for _, deg in ipairs(HEADINGS) do
    local c, s = math.cos(math.rad(deg)), math.sin(math.rad(deg))
    local at = {me[1] + (ux * c - uz * s) * 30, me[2], me[3] + (ux * s + uz * c) * 30}
    local clear = native(entity, "CHK_MOVE_INFO", {at[1], at[2], at[3], I})
    if clear == nil or clear[1] ~= 0 then return at end
  end
end

-- A looping motion only restarts when it changes; a one-shot (flags 2|4: from its first frame, hold the last) always.
-- The blend into it is set every time: a retail script (a flinch) can leave it at 0, and then a looping motion never
-- blends in, so the monster glides about frozen in its last pose. 0.25 blends in four frames, short enough that it
-- doesn't slide into a walk either.
local function play(entity, mind, motion, speed, once)
  native(entity, "SET_MOTION_CHANGE_STEP", {0.25})
  if once then
    native(entity, "SET_MOTION", {motion, speed, 6})
    mind.motion = nil
  elseif mind.motion ~= motion then
    native(entity, "SET_MOTION", {motion})
    mind.motion = motion
  end
end

local function free_turn(entity, frame)
  if turn and (turn.entity == entity or frame - turn.at > 600) then turn = nil end
  if turn == nil then turn = {entity = entity, at = frame} return true end
  return false
end
local function end_turn(entity) if turn and turn.entity == entity then turn = nil end end

local function to(mind, state) mind.state, mind.t, mind.from = state, 0, nil end

-- quick: an answer (after a dodge or a block), with no held wind-up or feint. chained: the next blow of a string,
-- counted so a string stops at three.
local function strike(entity, mind, kind, n, quick, chained)
  -- An opening blow is now and then the monster's own new attack.
  if n == 1 and not chained and kind.special and math.random() < kind.special.chance then n = kind.special.n end
  local a = kind.attacks[n]
  halt(entity)
  mind.attack, mind.lunged, mind.flashed, mind.caught = n, false, false, false
  mind.chain = chained and (mind.chain or 1) + 1 or 1
  -- A delayed swing now and then: the wind-up freezes for a beat to catch a roll thrown on reflex.
  mind.hold = not quick and math.random() < 0.3 and math.random(14, 30) or 0
  mind.feint = not quick and mind.hold == 0 and math.random() < (kind.feint or 0)
  mind.speed = a.speed * (0.9 + math.random() * 0.25) -- no two swings quite the same tempo
  play(entity, mind, a.motion, mind.speed, true)
  to(mind, "attack")
end

-- A quick step to one side, out of the line of a swing (the other side if a wall is there).
local function sidestep(e, mind, kind, me, ux, uz, you)
  local side = math.random() < 0.5 and 1 or -1
  local at
  for _ = 1, 2 do
    at = {me[1] - uz * side * 30, me[2], me[3] + ux * side * 30}
    local clear = native(e, "CHK_MOVE_INFO", {at[1], at[2], at[3], I})
    if clear == nil or clear[1] ~= 0 then break end
    side = -side
  end
  face(e, you, 1)
  if kind.roll and math.random() < kind.roll.chance then
    -- The roll: further and quicker over the floor than the step, and longer to get up from.
    play(e, mind, side > 0 and kind.roll.right or kind.roll.left, -1, true)
    go(e, {me[1] + (at[1] - me[1]) * 1.4, me[2], me[3] + (at[3] - me[3]) * 1.4}, 1.5)
    to(mind, "evade")
    mind.evade_for = 34
    return
  end
  play(e, mind, side > 0 and kind.right or kind.left, -1, true)
  go(e, at, 1.0)
  to(mind, "evade")
end

local function backstep(e, mind, kind, me, ux, uz, you)
  play(e, mind, kind.back, -1, true)
  face(e, you, 1)
  go(e, {me[1] - ux * 20, me[2], me[3] - uz * 20}, 0.75)
  to(mind, "evade")
end

local function think(ctx, kind)
  local e = ctx.entity
  local mind = minds[e]
  if mind == nil then
    mind = {state = "close", t = 0, rest = math.random(30, 90), side = math.random() < 0.5 and 1 or -1, dodge = 0,
            last = ctx.frame}
    minds[e] = mind
  end
  -- The hook runs on alternate frames (the engine finishes the program, then asks again), so count real frames.
  local dt = clamp(ctx.frame - mind.last, 1, 10)
  mind.last = ctx.frame
  mind.t = mind.t + dt
  mind.dodge = mind.dodge - dt

  local me, you = spot(e, -1), spot(e, -2)
  if me == nil or you == nil then return end
  local dx, dz = you[1] - me[1], you[3] - me[3]
  local dist = math.sqrt(dx * dx + dz * dz)
  local ux, uz = dx / math.max(dist, 0.01), dz / math.max(dist, 0.01) -- toward the player
  -- Walking into something the floor check missed (a wall's edge, another monster): the engine stops it dead, so it
  -- counts as blocked rather than walking on the spot.
  local was = mind.at
  mind.at = me
  if mind.walking and was and (me[1] - was[1]) ^ 2 + (me[3] - was[3]) ^ 2 < 0.01 then
    mind.blocked = (mind.blocked or 0) + dt
  else
    mind.blocked = 0
  end
  mind.walking = false

  if mind.state == "attack" then
    local a = kind.attacks[mind.attack]
    local o = native(e, "CHK_MOTION_FRM", {I, F}) or {}
    -- The new motion shows up a frame or two late; until it does, the reading is the old one's.
    local started = mind.t > 4 and o[2] ~= nil and o[2] >= a.from and o[2] <= a.done
    local done, frame = started and o[1] == 1, started and o[2] or a.from
    if frame < a.track_to then face(e, you, 0.2) end
    -- The player rolled before the blow: hold the wind-up and turn with the roll until it is spent, then swing.
    if rolled and not mind.caught and not mind.lunged and ctx.frame - rolled < 16 then
      mind.caught = true
      mind.hold = math.max(mind.hold, 34)
    end
    if mind.feint and frame >= a.hold then
      -- The feint: the wind-up broken off into a sidestep, and the real swing straight after.
      mind.feint, mind.after = false, true
      sidestep(e, mind, kind, me, ux, uz, you)
      return
    end
    if mind.hold > 0 and frame >= a.hold then
      if not mind.flashed then
        native(e, "SET_MOTION", {a.motion, mind.speed, 3}) -- paused where it stands, until let go
        native(e, "STATUS_SET_PALLET", {255, 150, 60, 1, 0.1})
        mind.flashed = true
      end
      face(e, you, 0.35)
      mind.hold = mind.hold - dt
      if mind.hold <= 0 then native(e, "SET_MOTION", {a.motion, mind.speed, 2}) end
      return
    end
    if not mind.lunged and frame >= a.track_to then
      -- The commit: no more turning, a short lunge along the line it chose.
      mind.lunged = true
      if dist > 8 then go(e, {me[1] + ux * 30, me[2], me[3] + uz * 30}, a.lunge * (mind.rushing and 2 or 1)) end
      mind.rushing = false
    elseif mind.lunged and frame >= a.track_to + 5 then
      halt(e)
    end
    if done or (started and frame >= a.done - 0.5) or mind.t > 240 then
      if a.next and mind.chain < 3 and dist < kind.reach + 6 and math.random() < (mind.chain == 1 and 0.55 or 0.3) then
        strike(e, mind, kind, a.next, true, true)
      else
        halt(e)
        play(e, mind, kind.idle)
        mind.recover = math.random(36, 54) -- open to a punish
        to(mind, "recover")
      end
    end
    return
  end

  if mind.state == "recover" then
    if mind.t >= mind.recover then
      play(e, mind, kind.idle)
      end_turn(e)
      mind.rest = math.random(50, 120)
      to(mind, "space")
    end
    return
  end

  if mind.state == "guard" then
    face(e, you, 0.2)
    if mind.t >= 12 then play(e, mind, kind.guard.hold) end -- the shield up, held
    if mind.t >= mind.guard_for then
      if dist < kind.reach + 8 and math.random() < 0.5 and free_turn(e, ctx.frame) then
        strike(e, mind, kind, 1, true) -- the riposte off the block
      else
        play(e, mind, kind.guard.down, -1, true)
        mind.recover = 14
        to(mind, "recover")
      end
    end
    return
  end

  if mind.state == "evade" then
    if mind.t >= (mind.evade_for or 20) then
      mind.evade_for = nil
      halt(e)
      if mind.after then
        mind.after = false
        strike(e, mind, kind, math.random(#kind.attacks), true) -- the real swing after a feint
      elseif dist < kind.reach + 10 and math.random() < 0.7 and free_turn(e, ctx.frame) then
        strike(e, mind, kind, 1, true) -- the punish for a swing that missed
      else
        play(e, mind, kind.idle)
        to(mind, "space")
      end
    end
    return
  end

  -- Reading the player: a swing just started close by sends it behind its shield, to one side or back out of reach.
  local seen = native(e, "GUARD_SEARCH", {I, F, I})
  if seen and seen[1] and seen[1] >= 2 and seen[1] <= 10 and seen[2] < 24 and mind.dodge <= 0 then
    mind.dodge = 70
    local roll, guard = math.random(), kind.guard and kind.guard.chance or 0
    if roll < guard then
      halt(e)
      face(e, you, 1)
      play(e, mind, kind.guard.up, -1, true)
      mind.guard_for = math.random(30, 50)
      to(mind, "guard")
      return
    elseif roll < guard + kind.dodge_chance then
      if math.random() < (kind.sidestep or 0) then
        sidestep(e, mind, kind, me, ux, uz, you)
      else
        backstep(e, mind, kind, me, ux, uz, you)
      end
      return
    end
  end

  if mind.state == "press" then
    -- A rush swings as it arrives, a little short of reach, and its lunge carries it the rest of the way.
    if dist <= kind.reach + (mind.rushing and 10 or 0) then
      local rushing = mind.rushing
      strike(e, mind, kind, 1)
      mind.rushing = rushing
    elseif mind.t > 90 or mind.blocked >= 6 then
      halt(e)
      play(e, mind, kind.idle)
      end_turn(e)
      mind.rushing = false
      mind.rest = math.random(40, 80)
      to(mind, "space")
    else
      local at = way(e, me, ux, uz)
      if at then
        play(e, mind, kind.walk)
        face(e, at, 0.2)
        go(e, at, kind.press_speed * (mind.rushing and 1.8 or 1))
        mind.walking = true
      else
        halt(e)
        play(e, mind, kind.idle)
      end
    end
    return
  end

  if mind.state == "close" then
    -- No ground gained in a while (a wall, a ledge): wait where it stands and try again later.
    mind.from = mind.from or dist
    if mind.blocked >= 6 then mind.t, mind.from = math.max(mind.t, 91), math.min(mind.from, dist) end
    if mind.t > 90 and dist > mind.from - 10 then
      halt(e)
      play(e, mind, kind.idle)
      face(e, you, 0.12)
      if mind.t > 150 then mind.from = dist; mind.t = 0 end
      return
    end
    if dist <= kind.ring then
      halt(e)
      play(e, mind, kind.idle)
      to(mind, "space")
    else
      local at = way(e, me, ux, uz)
      if at then
        play(e, mind, kind.walk)
        face(e, at, 0.12)
        go(e, at, kind.walk_speed)
        mind.walking = true
      else
        halt(e)
        play(e, mind, kind.idle)
        face(e, you, 0.12)
      end
    end
    return
  end

  -- "space": circle at the edge of reach until it is this monster's turn.
  if dist > kind.ring + 14 then to(mind, "close") return end
  mind.rest = mind.rest - dt
  if mind.rest <= 0 and free_turn(e, ctx.frame) then
    if dist <= kind.reach then
      strike(e, mind, kind, 1)
    else
      to(mind, "press")
      mind.rushing = math.random() < (kind.rush or 0)
    end
    return
  end
  face(e, you, 0.3)
  if mind.t < (mind.step_until or 0) then return end
  if mind.stepping then
    halt(e)
    play(e, mind, kind.idle)
    mind.stepping = false
    mind.step_until = mind.t + math.random(10, 40) -- a beat of stillness between steps
    if math.random() < 0.3 then mind.side = -mind.side end
    return
  end
  local px, pz = -uz * mind.side, ux * mind.side           -- along the circle
  local pull = clamp((dist - kind.ring) / 10, -1, 1)          -- and back onto it
  local at = {me[1] + (px + ux * pull) * 20, me[2], me[3] + (pz + uz * pull) * 20}
  local clear = native(e, "CHK_MOVE_INFO", {at[1], at[2], at[3], I})
  if clear and clear[1] == 0 then
    mind.side = -mind.side
    mind.step_until = mind.t + 6
    return
  end
  play(e, mind, mind.side > 0 and kind.right or kind.left)
  go(e, at, kind.step_speed)
  mind.stepping = true
  mind.step_until = mind.t + math.random(24, 40)
end

-- The hook's ctx.model is the floor's model slot; the game's monster id comes from the entity query.
local function kind_of(entity)
  if kinds[entity] == nil then
    local q = try(game.entities.query, {type = "monster"})
    for _, m in ipairs(type(q) == "table" and q.entities or {}) do
      -- Unknown until the floor's model table is mapped: ask again next time rather than settle on no brain.
      if kinds[m.entity_id] == nil and m.native_model_id ~= nil then kinds[m.entity_id] = BRAINS[m.native_model_id] or false end
      if BRAINS[m.native_model_id] then BRAINS[m.native_model_id].model = m.native_model_id end
    end
  end
  return kinds[entity]
end

local function brain_hook(ctx)
  if type(ctx) == "table" and ctx.frame then hook_frame = ctx.frame end
  local kind = brain_on and type(ctx) == "table" and kind_of(ctx.entity)
  if kind then
    resolve_moves(kind, kind.model)
    if ctx.program_no == 100 then
      local ok, err = pcall(think, ctx, kind)
      if ok then return {handled = true} end
      moonmod.log("warn", "enemy brain: " .. message(err))
    elseif ctx.program_no == 110 then
      -- Hit: the retail flinch and its answer run, then the brain picks up again from the circle.
      end_turn(ctx.entity)
      local mind = minds[ctx.entity]
      if mind then mind.motion = nil; mind.rest = math.random(20, 60); to(mind, "space") end
    elseif ctx.program_no == 120 then
      end_turn(ctx.entity)
      minds[ctx.entity], kinds[ctx.entity] = nil, nil
    end
  end
  return game.scripts.call({id = "native.monster.run"})
end

local function set_brain(on)
  if on == brain_on then return true end
  minds, kinds, turn = {}, {}, nil
  local scripts = type(game.scripts) == "table" and game.scripts or {}
  if on then
    register_monster_moves()
    local ok, err = call(scripts.override, {id = "native.monster.run"}, brain_hook)
    if not ok then moonmod.log("warn", "enemy brain: " .. message(err)) return false end
  else
    try(scripts.override, {id = "native.monster.run", enabled = false})
  end
  brain_on = on
  return true
end

-- Applying the rules ----------------------------------------------------------------------------------------------
local in_sandbox = false
local guarding = false
local applied = {} -- what the last apply() asked for, for the Mod Manager's "Check" action
local TREE = {vigour = 0, endurance = 0, guard = 0} -- the shrine tree's ranks in this save (Levelling, below)

local function tuning()
  local refill = setting("gauge_refill", 100) / 100 * (1 + 0.1 * TREE.endurance)
  if guarding then refill = refill * math.min(75, setting("guard_refill", 25) + 5 * TREE.guard) / 100 end
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

  local evades = setting("evades", true) and register_motions()
  local attacks = setting("toan_attacks", true) and register_attacks()
  if evades or attacks then
    local set, set_err = call(game.player.moves_set, {moves = moves(evades, attacks)})
    if not set then
      moonmod.log("warn", "moves: " .. message(set_err))
      evades, attacks = false, false
      applied.moves = "refused: " .. message(set_err)
    end
  else
    try(game.player.moves_clear)
  end
  applied.evades = evades and "on" or (setting("evades", true) and "tuning dodge (motions missing)" or "off")
  applied.toan_attacks = attacks and "on" or (setting("toan_attacks", true) and "motions missing" or "off")
  local brain = setting("enemy_brain", true)
  applied.enemy_brain = (set_brain(brain) and brain) and "on" or (brain and "refused" or "off")

  bind_guard()
  guarding = guard_held()
  apply_tuning()
end

local function stand_down()
  try(game.player.moves_clear)
  try(game.player.tuning_clear)
  set_brain(false)
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
  if setting("toan_attacks", true) then
    toast("Vigil: Toan's R2 is a heavy blow, or a finisher partway through his combo. Locked on, attack toward or away.")
  end
  toast("Vigil: lock on and hold R1 to guard. The gauge recovers slowly while you do.")
  toast("Vigil: enemies hit hard. Read them, guard or roll, then punish.")
end

-- Floors ----------------------------------------------------------------------------------------------------------
-- The same floors every visit (VIGIL_PLAN.md section 9, W1.0): a floor is built again from the seed it was first
-- built from, kept with the save, so it is a place you learn rather than a new maze each time. Back floors follow
-- their floor; Demon Shaft stays new every time, the endless challenge. A chest you opened stays opened: the floor's
-- kept table holds the chests opened on it ("0:3:chests") and on its back floor ("0:3:back") by their number.
local DEMON_SHAFT = 6
-- The floor's map and magic crystal only work on the visit they're found on, so their chests fill up again.
local FLOOR_ONLY_ITEMS = {[233] = true, [234] = true}
local floors = {key = nil, seeds = {}}

local function floor_seeds()
  local slot = try(game.save.slot_id)
  local key = type(slot) == "table" and slot.slot_id and ("floors:" .. slot.slot_id .. ":" .. tostring(slot.slot_generation)) or nil
  if key ~= floors.key then
    local kept = key and try(game.save.get, key)
    local seeds = type(kept) == "table" and kept or {}
    -- A game not saved yet keeps its floors for the session, and takes them to the slot it is first saved in.
    if floors.key == nil then
      for k, v in pairs(floors.seeds) do if seeds[k] == nil then seeds[k] = v end end
    end
    floors.key, floors.seeds = key, seeds
  end
  return floors.seeds
end

local function kept_floor(e)
  return not in_sandbox and type(e) == "table" and not e.back_floor and type(e.dungeon_id) == "number" and
         e.dungeon_id ~= DEMON_SHAFT and type(e.floor_id) == "number" and setting("same_floors", true)
end

-- Zones (W1.1, the Vigil World preview): a floor is two zones joined by a locked gate, and a monster in the first
-- carries its key. A gate once opened is built open on the floor's later visits ("0:3:gates"). Each zone has a shrine
-- (W1.2): its spring, lit the first time you reach it ("0:3:shrines"), where you rest, travel to another lit shrine
-- or leave for town, the one way back to town while the preview is on.
local ZONE_ROOMS = 5
local zones_asked = false

-- Vigil World belongs to a save (VIGIL_PLAN 9 "Compatibility"): the first time a save goes into a dungeon, Vigil
-- settles it and keeps it with the save ("world"). A save already holding Vigil World places is one; a save with
-- dungeon progress and none was started without it and stays a normal Dark Cloud save; a new game takes the
-- setting. Changing the setting later changes only saves not settled yet.
local function world_save(settle)
  local seeds = floor_seeds()
  if type(seeds.world) == "boolean" then return seeds.world end
  local on
  for k, v in pairs(seeds) do
    local key = tostring(k)
    if key:find(":shrines$") or key:find(":gates$") or (key:find(":shape$") and (tostring(v):find("region") or tostring(v):find("zones"))) then on = true end
  end
  if on == nil then
    local list = try(game.dungeons.list)
    for _, d in ipairs(type(list) == "table" and (list.dungeons or list) or {}) do
      if type(d) == "table" and type(d.deepest_floor_reached) == "number" and d.deepest_floor_reached > 0 then on = false end
    end
  end
  if on == nil then on = setting("world_zones", false) end
  if not settle then return on end
  seeds.world = on
  if floors.key then try(game.save.set, floors.key, seeds) end
  return on
end

local smoke_floor -- the regions', below
local function zoned_floor(e)
  return kept_floor(e) and world_save(false) and not smoke_floor(e.dungeon_id, e.floor_id)
end

-- Regions (W1.3, W2, W2.2, playtests 1 and 2): each dungeon is one map, every floor a zone of it with its own monsters,
-- atla and chest items, up to and with the last floor: the boss's own fixed map, a smoke floor at the map's far end
-- (playtest 2: built as zones, Dran stood outside the map). Gallery of Time's 25 floors are two maps. A region is kept
-- under its first floor ("0:0").
local REGIONS = {
  [0] = {{0, 14}},           -- Divine Beast Cave: Dran 14
  [1] = {{0, 16}},           -- Wise Owl Forest: 16
  [2] = {{0, 17}},           -- Shipwreck: 17
  [3] = {{0, 17}},           -- Sun and Moon Temple: 17
  [4] = {{0, 14}},           -- Moon Sea: 14
  [5] = {{0, 11}, {12, 24}}, -- Gallery of Time: 24
}
-- Smoke floors: the floors where the story happens on a map of the game's own: Divine Beast Cave's 4 (the skeleton)
-- and 8 (Seda), each dungeon's midway boss, and each dungeon's last boss (Dran's 15). The third floor of each dungeon
-- the game keeps atla off (noEntryTbl) is only there to give the party to one character (Divine Beast Cave's 11 Xiao,
-- Wise Owl's 12 Goro, Shipwreck's 12 Ruby, the Temple's 13 Ungaga, Moon Sea's 11 Osmond): an ordinary zone
-- (playtest 2). On the region's
-- map such a floor is a small zone behind a smoke gate, a wall no key opens; walking up to it offers the floor itself,
-- played as the game has it. Its way down leads to the next floor's zone of the map, and the smoke is gone from then on
-- ("smoke:<d>" lists the floors cleared): the small zone is walked through.
local SMOKE_FLOORS = {
  [0] = {3, 7, 14}, [1] = {3, 8, 16}, [2] = {4, 8, 17}, [3] = {4, 8, 17}, [4] = {3, 7, 14},
  [5] = {18, 19, 20, 21, 22, 24},
}
local REGION_ROOMS = 5
local SMOKE_ROOMS = 2

smoke_floor = function(dungeon_id, floor_id)
  for _, f in ipairs(SMOKE_FLOORS[dungeon_id] or {}) do if f == floor_id then return true end end
  return false
end

-- A smoke floor isn't part of its region when the player is on it: it is the game's own floor.
local function region_of(dungeon_id, floor_id)
  if not world_save(false) or not setting("world_regions", true) or smoke_floor(dungeon_id, floor_id) then return nil end
  for _, r in ipairs(REGIONS[dungeon_id] or {}) do
    if floor_id >= r[1] and floor_id <= r[2] then return r end
  end
  return nil
end

local function smoke_cleared(dungeon_id, floor_id)
  local list = floor_seeds()["smoke:" .. tostring(dungeon_id)]
  for _, f in ipairs(type(list) == "table" and list or {}) do if f == floor_id then return true end end
  return false
end

-- The key a floor is kept under: its region's first floor, or its own.
local function place_key(dungeon_id, floor_id)
  local r = region_of(dungeon_id, floor_id)
  return tostring(dungeon_id) .. ":" .. tostring(r and r[1] or floor_id)
end

-- What a kept place is built as. Its seed gives the same map, and its chest numbers the same chests, only while this
-- holds: a place whose shape changed (a region's floors, or how many chests it gets: v2) starts again as new.
local function place_shape(e)
  local r = region_of(e.dungeon_id, e.floor_id)
  if r then return string.format("v3:region:%d-%d:%d", r[1], r[2], REGION_ROOMS) end
  if zoned_floor(e) then return "v2:zones:" .. ZONE_ROOMS end
  return "floor"
end

-- A region whose floors only grew at the far end (playtest 2: the boss's floor joined it) is a new map, but its zones
-- keep their floors: the gates opened and the shrines lit there still hold, only where they stand is read again.
local function region_grew(old, new)
  local a, b, n = string.match(old or "", "^v3:region:(%d+)-(%d+):(%d+)$")
  local c, d, m = string.match(new or "", "^v3:region:(%d+)-(%d+):(%d+)$")
  return a ~= nil and c ~= nil and a == c and n == m and tonumber(b) < tonumber(d)
end

local PLACE_LISTS = {"", ":chests", ":back", ":gates", ":shrines", ":map", ":waypoint", ":shape"}
local function forget_place(seeds, k)
  for _, list in ipairs(PLACE_LISTS) do seeds[k .. list] = nil end
end

local entering = false -- Vigil itself is taking the player to a floor (a rest, a shrine): it says where they arrive
local from_town = true -- the next floor built is entered from a town (or the title), not from another floor
local walk_entry = false -- the floor being built was entered from town by its entrance, not by Vigil (rest, shrine, wake)
local hold_entry_scenes   -- the Fairy King's, below: a map's opening scene held for the King to give
local fallen_lies = true -- false from a knockout until a floor is built again: the party is still on the spot

-- The shrine the player last rested at in a dungeon ("rest:0"): {floor_id, zone, x, y}. Waking after a knockout starts
-- the player there; walking in from town starts at the entrance (floor 1), and the shrines are reached from the map.
local function rest_shrine(dungeon_id)
  local sh = floor_seeds()["rest:" .. tostring(dungeon_id)]
  if type(sh) ~= "table" or type(sh.floor_id) ~= "number" or type(sh.zone) ~= "number" then return nil end
  if not zoned_floor({dungeon_id = dungeon_id, floor_id = sh.floor_id}) then return nil end
  return sh
end

local function ask_zones(e, seeds, k)
  if zoned_floor(e) then
    local open = type(seeds[k .. ":gates"]) == "table" and #seeds[k .. ":gates"] > 0 and seeds[k .. ":gates"] or nil
    local r = region_of(e.dungeon_id, e.floor_id)
    -- (O1 safe ground: a shrine's circle is a sanctuary no monster steps into)
    local request = {zones = {{rooms = ZONE_ROOMS}, {rooms = ZONE_ROOMS}}, open = open, shrines = true, shrine_heal = false,
                     sanctuary = true}
    if r then
      request.zones = {}
      local opened, smoke = {}, {}
      for _, z in ipairs(open or {}) do opened[z] = true end
      for f = r[1], r[2] do
        local z = f - r[1]
        if smoke_floor(e.dungeon_id, f) then
          -- a small zone with the monsters of the floor before it
          local src = f - 1
          while src > r[1] and smoke_floor(e.dungeon_id, src) do src = src - 1 end
          request.zones[#request.zones + 1] = {rooms = SMOKE_ROOMS, source_floor = math.max(r[1], src)}
          if smoke_cleared(e.dungeon_id, f) then
            -- walked through now, the gate out of it too (the player came back in past it)
            opened[z] = true
            if f < r[2] then opened[z + 1] = true end
          elseif z > 0 then
            smoke[#smoke + 1] = z
          end
        else
          request.zones[#request.zones + 1] = {rooms = REGION_ROOMS, source_floor = f}
        end
      end
      for _, z in ipairs(smoke) do opened[z] = nil end
      request.open = {}
      for z in pairs(opened) do request.open[#request.open + 1] = z end
      table.sort(request.open)
      if #request.open == 0 then request.open = nil end
      request.smoke = #smoke > 0 and smoke or nil
      request.exit_floor = r[2] + 1
      -- Come in by one of its later floors (the entrance's floor list): start at that floor's zone.
      if e.floor_id ~= r[1] and not entering then try(game.dungeons.set_arrival, {zone = e.floor_id - r[1], teleport = true}) end
    end
    zones_asked = try(game.dungeons.set_zones, request) ~= nil
    if zones_asked then try(game.dungeons.set_exits, {town = "shrines"}) end
  elseif zones_asked then
    try(game.dungeons.set_zones, {})
    try(game.dungeons.set_exits, {town = "any"})
    zones_asked = false
  end
end

moonmod.on("game.dungeon.generating", function(e)
  if type(e) ~= "table" or e.back_floor then return end
  -- built unseen as the town loads (the cave seen through its door) is a walk-in from town too
  walk_entry = e.prebuild == true or (from_town and not entering)
  if kept_floor(e) then world_save(true) end
  -- walked in onto a map's first floor: its opening is held before the floor's opening script reaches it
  local first = region_of(e.dungeon_id, e.floor_id)
  if walk_entry and first and e.floor_id == first[1] then hold_entry_scenes() end
  -- Out of a smoke floor by its way down: the smoke is gone.
  local seeds0 = floor_seeds()
  local into = seeds0.smoke_in
  if type(into) == "table" and into.dungeon_id == e.dungeon_id and type(into.floor_id) == "number" and e.floor_id > into.floor_id then
    local key = "smoke:" .. tostring(e.dungeon_id)
    local list = type(seeds0[key]) == "table" and seeds0[key] or {}
    local have = false
    for _, f in ipairs(list) do have = have or f == into.floor_id end
    if not have then table.insert(list, into.floor_id) end
    seeds0[key], seeds0.smoke_in = list, nil
    -- several smoke floors in a row: the next one is entered as the game has it too
    if smoke_floor(e.dungeon_id, e.floor_id) then
      seeds0.smoke_in = {dungeon_id = e.dungeon_id, floor_id = e.floor_id}
    else
      try(game.dungeons.set_story_exits, {})
    end
    if floors.key then try(game.save.set, floors.key, seeds0) end
    toast(string.format("Vigil: the smoke over floor %d clears.", into.floor_id + 1), 240)
  end
  local seeds, k = floor_seeds(), place_key(e.dungeon_id, e.floor_id)
  ask_zones(e, seeds, k)
  if not e.prebuild then entering = false end
  if not kept_floor(e) then return end
  if type(seeds[k]) ~= "number" then return end
  if (seeds[k .. ":shape"] or "floor") ~= place_shape(e) then
    local gates, shrines = seeds[k .. ":gates"], seeds[k .. ":shrines"]
    local grew = region_grew(seeds[k .. ":shape"], place_shape(e))
    forget_place(seeds, k)
    if grew then
      seeds[k .. ":gates"], seeds[k .. ":regrown"] = gates, shrines or {}
    end
    if floors.key then try(game.save.set, floors.key, seeds) end
    return
  end
  try(game.dungeons.set_seed, {seed = seeds[k]})
  local opened = {}
  if type(seeds[k .. ":chests"]) == "table" and #seeds[k .. ":chests"] > 0 then opened.chests = seeds[k .. ":chests"] end
  if type(seeds[k .. ":back"]) == "table" and #seeds[k .. ":back"] > 0 then opened.back_chests = seeds[k .. ":back"] end
  if next(opened) then try(game.dungeons.set_opened_chests, opened) end
end)

moonmod.on("game.dungeon.generated", function(e)
  if not kept_floor(e) or type(e.floor_seed) ~= "number" then return end
  local seeds, k = floor_seeds(), place_key(e.dungeon_id, e.floor_id)
  if seeds[k] == e.floor_seed then return end
  -- The first visit, or a kept seed whose floor couldn't be crossed and was built from another: a new floor, its
  -- chests all closed.
  local gates, regrown = seeds[k .. ":gates"], seeds[k .. ":regrown"]
  forget_place(seeds, k)
  seeds[k], seeds[k .. ":shape"] = e.floor_seed, place_shape(e)
  if type(regrown) == "table" then
    seeds[k .. ":regrown"], seeds[k .. ":gates"] = nil, gates
    local z = try(game.dungeons.zones_get)
    local at = {}
    for _, sh in ipairs(type(z) == "table" and type(z.shrines) == "table" and z.shrines or {}) do
      if type(sh) == "table" and type(sh.zone) == "number" then at[sh.zone] = sh end
    end
    local lit = {}
    for _, sh in ipairs(regrown) do
      local now = type(sh) == "table" and at[sh.zone]
      if now then lit[#lit + 1] = {zone = sh.zone, x = now.x, y = now.y, label = sh.label} end
    end
    seeds[k .. ":shrines"] = #lit > 0 and lit or nil
    local rest = seeds["rest:" .. tostring(e.dungeon_id)]
    local now = type(rest) == "table" and place_key(e.dungeon_id, rest.floor_id or -1) == k and at[rest.zone]
    if now then rest.x, rest.y = now.x, now.y end
  end
  if floors.key then try(game.save.set, floors.key, seeds) end
end)

moonmod.on("game.chest.opened", function(e)
  if type(e) ~= "table" or type(e.chest) ~= "number" then return end -- a mod's loot change, not a chest
  if FLOOR_ONLY_ITEMS[e.item_id] then return end
  if not kept_floor({dungeon_id = e.dungeon_id, floor_id = e.floor_id}) then return end
  local seeds, k = floor_seeds(), place_key(e.dungeon_id, e.floor_id)
  if type(seeds[k]) ~= "number" then return end
  local list = k .. (e.back_floor and ":back" or ":chests")
  seeds[list] = type(seeds[list]) == "table" and seeds[list] or {}
  for _, chest in ipairs(seeds[list]) do if chest == e.chest then return end end
  table.insert(seeds[list], e.chest)
  if floors.key then try(game.save.set, floors.key, seeds) end
end)

local floor_now = nil -- {dungeon_id, floor_id} of the floor the player is on
local keep_map         -- the map section's: keeps what the player has seen of the place they're on
moonmod.on("game.dungeon.generated", function(e)
  if type(e) == "table" and not e.back_floor then floor_now = {dungeon_id = e.dungeon_id, floor_id = e.floor_id} end
  if type(e) == "table" and e.prebuild then return end -- built unseen: the party is still in town
  from_town, fallen_lies = false, true
end)
-- Walked back in through the town's door onto the floor left there: it is the same floor, not a new one
moonmod.on("game.dungeon.resumed", function(e)
  if type(e) == "table" then floor_now = {dungeon_id = e.dungeon_id, floor_id = e.floor_id} end
  from_town = false
end)

moonmod.on("game.dungeon.zone_gate_opened", function(e)
  if in_sandbox or type(e) ~= "table" or type(e.zone) ~= "number" or not floor_now or not kept_floor(floor_now) then return end
  local seeds, k = floor_seeds(), place_key(floor_now.dungeon_id, floor_now.floor_id)
  if type(seeds[k]) ~= "number" then return end
  local list = type(seeds[k .. ":gates"]) == "table" and seeds[k .. ":gates"] or {}
  for _, zone in ipairs(list) do if zone == e.zone then return end end
  table.insert(list, e.zone)
  seeds[k .. ":gates"] = list
  if floors.key then try(game.save.set, floors.key, seeds) end
  toast("Vigil: the gate is open, and stays open.", 180)
end)

moonmod.on("game.dungeon.zone_gate_locked", function()
  if in_sandbox then return end
  toast("Vigil: locked. A monster on this side of the gate carries its key.", 240)
end)

moonmod.on("game.dungeon.zone_entered", function(e)
  if in_sandbox or type(e) ~= "table" or type(e.zone) ~= "number" or type(e.zones) ~= "number" then return end
  if e.previous ~= nil and e.previous >= 0 then
    if floor_now and region_of(floor_now.dungeon_id, floor_now.floor_id) and type(e.floor_id) == "number" then
      toast(string.format("Vigil: floor %d", e.floor_id + 1), 150)
    else
      toast(string.format("Vigil: zone %d of %d", e.zone + 1, e.zones), 150)
    end
  end
end)

-- Shrines (W1.2) --------------------------------------------------------------------------------------------------
-- The town each dungeon's shrines lead back to.
local SHRINE_TOWNS = {[0] = "norune-village", [1] = "matataki-village", [2] = "queens", [3] = "muska-lacka",
                      [4] = "yellow-drops", [5] = "yellow-drops"}
local shrine_at = nil -- the shrine the panel is open at: {dungeon_id, floor_id, zone, x, y}
local level_now, level_cost, open_tree -- Levelling's, below
local open_travel_map -- the Map's, below: Travel picks a lit shrine on the dungeon's map

-- The lit shrines of a dungeon, by floor then zone: {floor_id, zone, x, y}.
local function lit_shrines(dungeon_id)
  local seeds, out = floor_seeds(), {}
  for k, list in pairs(seeds) do
    local d, f = tostring(k):match("^(%d+):(%d+):shrines$")
    if d and tonumber(d) == dungeon_id and type(list) == "table" then
      for _, sh in ipairs(list) do
        if type(sh) == "table" and type(sh.zone) == "number" then
          out[#out + 1] = {floor_id = tonumber(f), zone = sh.zone, x = sh.x, y = sh.y, label = sh.label}
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.floor_id < b.floor_id or (a.floor_id == b.floor_id and a.zone < b.zone) end)
  return out
end

local shrine_name
shrine_name = function(sh)
  if type(sh.label) == "number" then return string.format("Floor %d", sh.label + 1) end
  return string.format("Floor %d, zone %d", sh.floor_id + 1, sh.zone + 1)
end

-- Puts the player in front of a shrine: on this floor at once, on another floor built again first.
local function go_to_shrine(sh, here_floor)
  if place_key(shrine_at.dungeon_id, sh.floor_id) == place_key(shrine_at.dungeon_id, here_floor) then
    try(game.dungeons.warp, {x = sh.x, y = sh.y + 1, teleport = true})
  else
    entering = true
    try(game.dungeons.enter_floor, {floor_id = sh.floor_id, x = sh.x, y = sh.y + 1, teleport = true})
  end
end

local function heal_party()
  local members = try(game.party and game.party.list)
  local healed = false
  for _, m in ipairs(type(members) == "table" and (members.members or members) or {}) do
    if type(m) == "table" and type(m.id) == "string" then healed = try(game.player.heal, {amount = 32767, character = m.id}) ~= nil or healed end
  end
  if not healed then try(game.player.heal, {amount = 32767, character = "active"}) end
end

local AILMENTS = {"poison", "curse", "goo", "freeze", "stamina"}
local function rest()
  heal_party()
  for _, status in ipairs(AILMENTS) do try(game.player.status_remove, {status = status}) end
  -- The floor built again from its seed, chests and gates as you left them, the monsters back.
  entering = true
  try(game.dungeons.enter_floor, {floor_id = shrine_at.floor_id, x = shrine_at.x, y = shrine_at.y + 1, teleport = true})
  toast("Vigil: you rest, healed and cured. The monsters return.", 240)
end

-- Levelling (W1.2, VIGIL_PLAN 3 "Progression"): the shrine tree, bought with Gilda and only at a shrine (the panel's
-- Level up opens it on the Journal's Character page). Vigour gives the whole party max HP, Endurance refills the
-- action gauge faster, Guard eases how much holding the guard slows that refill. Each level costs about 12% more than
-- the last. The ranks are kept with the save ("tree"), and given to the engine's tree to show.
local TREE_SKILLS = {
  {id = "vigour", title = "VIGOUR", max_rank = 20, description = "+5 max HP for everyone in the party."},
  {id = "endurance", title = "ENDURANCE", max_rank = 10, description = "The action gauge refills 10% faster."},
  {id = "guard", title = "GUARD", max_rank = 10, description = "Holding the guard slows the gauge's refill less (5 points)."},
}
local tree_registered = false

level_now = function() return TREE.vigour + TREE.endurance + TREE.guard end
level_cost = function() return 10 * math.floor(15 * 1.12 ^ level_now() + 0.5) end

-- The kept ranks into TREE (and the engine's tree), and the party's Vigour HP topped up to them.
local function load_tree()
  local kept = floor_seeds().tree
  kept = type(kept) == "table" and kept or {}
  local changed = false
  for _, s in ipairs(TREE_SKILLS) do
    local r = math.type(kept[s.id]) == "integer" and math.max(0, math.min(s.max_rank, kept[s.id])) or 0
    changed = changed or TREE[s.id] ~= r
    TREE[s.id] = r
  end
  if not tree_registered then
    local ok, err = call(game.skills and game.skills.register, {id = "shrine", title = "Shrine", description = "Bought with Gilda at a shrine.", skills = TREE_SKILLS})
    tree_registered = true
    if not ok then moonmod.log("warn", "shrine tree: " .. message(err)) end
    changed = true
  end
  if changed then
    for _, s in ipairs(TREE_SKILLS) do try(game.skills and game.skills.set_rank, {id = ID .. ":shrine." .. s.id, rank = TREE[s.id]}) end
    apply_tuning()
  end
  -- Vigour: each member's max HP raised once per rank ("tree".hp says how many ranks each has had)
  if TREE.vigour > 0 then
    local seeds = floor_seeds()
    local t = type(seeds.tree) == "table" and seeds.tree or {}
    t.hp = type(t.hp) == "table" and t.hp or {}
    local members, grew = try(game.party and game.party.list), false
    for _, m in ipairs(type(members) == "table" and (members.members or members) or {}) do
      local id = type(m) == "table" and m.id
      local had = id and (math.type(t.hp[id]) == "integer" and t.hp[id] or 0)
      local info = id and had < TREE.vigour and try(game.characters and game.characters.get, {id = id})
      if type(info) == "table" and math.type(info.max_hp) == "integer" then
        if try(game.player.set, {max_hp = math.min(999, info.max_hp + 5 * (TREE.vigour - had)), character = id}) then
          t.hp[id], grew = TREE.vigour, true
        end
      end
    end
    if grew then
      seeds.tree = t
      if floors.key then try(game.save.set, floors.key, seeds) end
    end
  end
end

-- Standing at the shrine the panel was opened at.
local function at_shrine()
  if not shrine_at or not floor_now or place_key(shrine_at.dungeon_id, shrine_at.floor_id) ~= place_key(floor_now.dungeon_id, floor_now.floor_id) then return false end
  local p = try(game.player.get)
  local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
  return at ~= nil and math.abs(at.x - 160 * shrine_at.x) < 240 and math.abs(at.z - 160 * (shrine_at.y + 1)) < 240
end

local function tree_sheet()
  local gilda = try(game.economy.get)
  try(game.ui.sheet_set, {title = "SHRINE", trees = {"shrine"},
    lines = {string.format("Level %d", level_now()),
             string.format("Next level: %d Gilda", level_cost()),
             string.format("Gilda: %d", type(gilda) == "table" and gilda.amount or 0)},
    hint = "Cross levels up the skill. Only at a shrine."})
end

open_tree = function()
  load_tree()
  tree_sheet()
  local ok, err = call(game.ui.sheet_open)
  if not ok then toast("Vigil: can't open the tree: " .. message(err), 240) end
end

moonmod.on("skills.train_requested", function(e)
  if in_sandbox or type(e) ~= "table" or type(e.id) ~= "string" then return end
  local skill = e.id:match("^" .. ID:gsub("%.", "%%.") .. ":shrine%.(%w+)$")
  local def
  for _, s in ipairs(TREE_SKILLS) do if s.id == skill then def = s end end
  if not def then return end
  if not at_shrine() then toast("Vigil: you can level up only at a shrine.", 240) return end
  load_tree()
  if TREE[def.id] >= def.max_rank then toast("Vigil: " .. def.title .. " is at its most.", 200) return end
  local cost = level_cost()
  if not call(game.economy.spend, {amount = cost}) then toast(string.format("Vigil: the next level costs %d Gilda.", cost), 240) return end
  local seeds = floor_seeds()
  local t = type(seeds.tree) == "table" and seeds.tree or {}
  t[def.id] = TREE[def.id] + 1
  seeds.tree = t
  if floors.key then try(game.save.set, floors.key, seeds) end
  load_tree()
  if def.id == "vigour" then heal_party() end
  tree_sheet()
  toast(string.format("Vigil: %s %d. Level %d.", def.title, TREE[def.id], level_now()), 200)
end)

moonmod.on("game.dungeon.generated", function(e)
  if not in_sandbox and type(e) == "table" and not e.back_floor then load_tree() end
end)

moonmod.on("game.dungeon.shrine_reached", function(e)
  if in_sandbox or type(e) ~= "table" or type(e.zone) ~= "number" or not floor_now or not zoned_floor(floor_now) then return end
  local seeds, k = floor_seeds(), place_key(floor_now.dungeon_id, floor_now.floor_id)
  if type(seeds[k]) ~= "number" then return end
  local list = type(seeds[k .. ":shrines"]) == "table" and seeds[k .. ":shrines"] or {}
  local r = region_of(floor_now.dungeon_id, floor_now.floor_id)
  local lit = false
  for _, sh in ipairs(list) do lit = lit or (type(sh) == "table" and sh.zone == e.zone) end
  if not lit then
    table.insert(list, {zone = e.zone, x = e.x, y = e.y, label = r and r[1] + e.zone or nil})
    seeds[k .. ":shrines"] = list
    if floors.key then try(game.save.set, floors.key, seeds) end
    toast("Vigil: a shrine is lit. Step into its water and press Square to pray: rest, travel, leave or level up.", 300)
  end
  shrine_at = {dungeon_id = floor_now.dungeon_id, floor_id = floor_now.floor_id, zone = e.zone, x = e.x, y = e.y,
               label = r and r[1] + e.zone or nil}
  seeds["rest:" .. floor_now.dungeon_id] = {floor_id = floor_now.floor_id, zone = e.zone, x = e.x, y = e.y}
  if floors.key then try(game.save.set, floors.key, seeds) end
end)

-- The shrine panel: Rest, Travel, Leave, Level up.
local function open_shrine_panel()
  local others = #lit_shrines(floor_now.dungeon_id) - 1
  local options = {
    {title = "Rest", lines = {"Heal fully, cure ailments.", {text = "The floor's monsters return.", tone = "bad"}}},
    {title = "Travel", lines = {others > 0 and string.format("%d other lit shrine%s, on the map.", others, others == 1 and "" or "s")
                                or {text = "No other shrine is lit yet.", tone = "dim"}}},
    {title = "Leave", lines = {"Back to town.", {text = "Return by its shrines.", tone = "dim"}}},
    {title = "Level up", lines = {string.format("Level %d.", level_now()), {text = string.format("Next: %d Gilda.", level_cost()), tone = "gold"}}},
  }
  try(game.ui.choice_open, {id = "vigil.shrine", title = "Shrine", subtitle = shrine_name(shrine_at), cancel = true, cursor = 4, options = options})
end

-- Standing in a shrine's water (the spring's cell) on the floor the player is on: its zone and cell, or nil.
local SPRING_REACH = 120
local function spring_here()
  local z = try(game.dungeons.zones_get)
  local p = try(game.player.get)
  local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
  if type(z) ~= "table" or type(z.shrines) ~= "table" or not at then return nil end
  for _, sh in ipairs(z.shrines) do
    if type(sh) == "table" and math.abs(at.x - 160 * sh.x) < SPRING_REACH and math.abs(at.z - 160 * sh.y) < SPRING_REACH then return sh end
  end
  return nil
end

-- The Fairy King (O1): on a region map the dungeon's floor-start scenes come once, for its first floor, so the King's
-- scenes for later floors never would. He stands beside the shrine of each zone whose floor has one, until it has
-- played; Square beside him plays it (resources/dun/d01_event.stb, built by art/vigil/patch_dbc_king.py, adds the
-- programs), and the floor is built again at that shrine afterwards (a scene leaves the floor without its monsters).
local KING_SCENES = {[0] = {[2] = 191, [4] = 192, [6] = 193}} -- dungeon: {floor id = program}
local KING_PACKS = {[0] = "dun/d01/event/e28c03c.chr"}        -- his model from the dungeon's own scenes
local KING_NPC, KING_FACING, KING_REACH = 1, 0, 200 -- facing 0: toward the room (south), where the player comes from
local kings = {}       -- the King's spots on the floor the player is on: {floor_id, program, x, y}
local king_marks = {}  -- where they stand, as set_npc_marks takes them
local king_talk = nil  -- the shrine the floor is built again at when his scene ends
-- Floor 1's scene, the dungeon's opening (retail program 199, behind story flag 103), isn't played on arrival: walked in
-- through the town's door, the party finds the King a little ahead, and Square beside him plays it (program 190).
local KING_ENTRY = {[0] = {program = 190, flag = 103}} -- dungeon: its first floor's scene
local KING_AHEAD = 2   -- cells ahead of where the party stands once walked in
local entry_king = nil -- {dungeon_id, floor_id, ticks}: the party walked in, the King to stand once it stands still
local in_dungeon = false -- the last place the party was seen in is a dungeon (a floor may be built from town, unseen)
moonmod.on("game.world.location_changed", function(e)
  if type(e) == "table" then in_dungeon = e.context == "dungeon" end
end)
moonmod.on("game.dungeon.resumed", function() in_dungeon = true end)

local function king_key(dungeon_id, floor_id) return "king:" .. tostring(dungeon_id) .. ":" .. tostring(floor_id) end
local function held_key(dungeon_id) return "king_held:" .. tostring(dungeon_id) end

-- In town, and again as the first floor is built: the opening's flag is set, so the floor's opening script passes it
-- by, and kept as held until the King has been talked to.
hold_entry_scenes = function()
  if in_sandbox or not world_save(false) then return end
  local seeds, changed = floor_seeds(), false
  for d, k in pairs(KING_ENTRY) do
    if not seeds[king_key(d, 0)] and not seeds[held_key(d)] then
      local flag = try(game.world.story_flag_get, {id = k.flag})
      if type(flag) == "table" and flag.value == false and try(game.world.story_flag_set, {id = k.flag, value = true}) then
        seeds[held_key(d)], changed = true, true
      end
    end
  end
  if changed and floors.key then try(game.save.set, floors.key, seeds) end
end

-- his model rides with the dungeon's map, except while Vigil sits out another mod's game mode
local function king_models()
  local session = try(game.session.get)
  local away = type(session) == "table" and session.kind == "sandbox" and session.owner ~= ID
  local models = {}
  for d, pack in pairs(KING_PACKS) do
    if not away then models[#models + 1] = {dungeon_id = d, npc = KING_NPC, pack = pack} end
  end
  try(game.dungeons.set_npc_models, #models > 0 and {models = models} or {})
end
king_models()
moonmod.on("game.session.started", king_models)
moonmod.on("game.session.ended", king_models)
for d in pairs(KING_SCENES) do
  try(game.resources.override, {path = string.format("resources/dun/d%02d_event.stb", d + 1), game_path = string.format("dun/script/d%02d/event.stb", d + 1)})
end

local function place_kings(e)
  kings = {}
  local scenes = KING_SCENES[e.dungeon_id]
  local r = scenes and not in_sandbox and region_of(e.dungeon_id, e.floor_id)
  local marks = {}
  king_marks = marks
  if r and zoned_floor(e) then
    local seeds, z = floor_seeds(), try(game.dungeons.zones_get)
    for _, sh in ipairs(type(z) == "table" and type(z.shrines) == "table" and z.shrines or {}) do
      local f = type(sh) == "table" and type(sh.zone) == "number" and r[1] + sh.zone
      if f and scenes[f] and not seeds[king_key(e.dungeon_id, f)] then
        -- beside the spring's step: the shrine room's next cell along
        kings[#kings + 1] = {floor_id = f, program = scenes[f], x = sh.x + 1, y = sh.y + 1, shrine = sh}
        marks[#marks + 1] = {npc = KING_NPC, x = sh.x + 1, y = sh.y + 1, facing = KING_FACING}
      end
    end
  end
  try(game.dungeons.set_npc_marks, #marks > 0 and {marks = marks} or {})
end

moonmod.on("game.dungeon.generated", function(e)
  if type(e) ~= "table" or e.back_floor then return end
  place_kings(e)
  -- walked in from town onto the map's first floor, with its opening held: the King stands ahead once play begins
  local r = not in_sandbox and region_of(e.dungeon_id, e.floor_id)
  entry_king = nil
  if r and walk_entry and e.floor_id == r[1] and KING_ENTRY[e.dungeon_id] and floor_seeds()[held_key(e.dungeon_id)] then
    entry_king = {dungeon_id = e.dungeon_id, floor_id = r[1], ticks = 0}
  end
end)

-- The King a few cells ahead of the party, turned toward it (facing k looks along (sin, cos) of k quarter turns).
moonmod.on("game.tick", function()
  local w = entry_king
  if not w or not in_dungeon or not floor_now or floor_now.dungeon_id ~= w.dungeon_id then return end
  w.ticks = w.ticks + 1
  if w.ticks < 40 then return end
  entry_king = nil
  local p = try(game.player.get)
  local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
  if not at or type(p.heading) ~= "number" then return end
  local cx, cy = math.floor(at.x / 160 + 0.5), math.floor(at.z / 160 + 0.5)
  local kx = cx + math.floor(KING_AHEAD * math.sin(p.heading) + 0.5)
  local ky = cy + math.floor(KING_AHEAD * math.cos(p.heading) + 0.5)
  local facing = math.floor((p.heading + math.pi) / (math.pi / 2) + 0.5) % 4
  local k = KING_ENTRY[w.dungeon_id]
  -- after his scene the floor is built again where the party stood (a scene leaves it without its monsters)
  kings[#kings + 1] = {floor_id = w.floor_id, program = k.program, x = kx, y = ky, shrine = {x = cx, y = cy - 1}, entry = true}
  king_marks[#king_marks + 1] = {npc = KING_NPC, x = kx, y = ky, facing = facing}
  try(game.dungeons.set_npc_marks, {marks = king_marks})
end)

local function king_here()
  local p = #kings > 0 and try(game.player.get)
  local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
  if not at then return nil end
  for _, k in ipairs(kings) do
    if math.abs(at.x - 160 * k.x) < KING_REACH and math.abs(at.z - 160 * k.y) < KING_REACH then return k end
  end
  return nil
end

local function talk_to_king(k)
  local ok, err = call(game.dungeons.play_event, {program = k.program})
  if not ok then toast("Vigil: the Fairy King can't speak now: " .. message(err), 200) return end
  local seeds = floor_seeds()
  seeds[king_key(floor_now.dungeon_id, k.floor_id)] = true
  if k.entry then seeds[held_key(floor_now.dungeon_id)] = nil end
  if floors.key then try(game.save.set, floors.key, seeds) end
  king_talk = {floor_id = floor_now.floor_id, x = k.shrine.x, y = k.shrine.y}
  kings = {}
  try(game.dungeons.set_npc_marks, {})
end

moonmod.on("game.dungeon.event_ended", function()
  local t = king_talk
  king_talk = nil
  if not t then return end
  entering = true
  local ok, err = call(game.dungeons.enter_floor, {floor_id = t.floor_id, x = t.x, y = t.y + 1, teleport = true})
  if not ok then entering = false toast("Vigil: couldn't return to the shrine: " .. message(err), 240) end
end)

local pray_bound, in_water, pray_clock, near_king = false, false, 0, false
moonmod.on("game.tick", function()
  pray_clock = pray_clock + 1
  if in_sandbox or not floor_now or not zoned_floor(floor_now) or pray_clock % 5 ~= 0 then return end
  if not pray_bound then
    pray_bound = true
    local ok, err = call(game.input.bind, {id = "pray", keys = {"Gamepad:x", "E"}})
    if not ok then moonmod.log("warn", "shrine binding: " .. message(err)) end
  end
  local sh = spring_here()
  if sh and not in_water then toast("Vigil: Square to pray at the shrine.", 150) end
  in_water = sh ~= nil
  local king = king_here()
  if king and not near_king then toast("Vigil: Square to talk to the Fairy King.", 150) end
  near_king = king ~= nil
  local press = try(game.input.consume, {id = "pray"})
  if type(press) ~= "table" or not press.pressed then return end
  if king then talk_to_king(king) return end
  if not sh then return end
  local r = region_of(floor_now.dungeon_id, floor_now.floor_id)
  shrine_at = {dungeon_id = floor_now.dungeon_id, floor_id = floor_now.floor_id, zone = sh.zone, x = sh.x, y = sh.y,
               label = r and r[1] + sh.zone or nil}
  open_shrine_panel()
end)

moonmod.on("ui.choice_made", function(e)
  if type(e) ~= "table" or e.cancelled or type(e.index) ~= "number" or not shrine_at then return end
  if e.id == "vigil.shrine" then
    if e.index == 1 then
      rest()
    elseif e.index == 2 then
      if #lit_shrines(shrine_at.dungeon_id) < 2 then toast("Vigil: no other shrine is lit yet.", 180) return end
      open_travel_map(shrine_at)
    elseif e.index == 3 then
      local town = SHRINE_TOWNS[shrine_at.dungeon_id]
      keep_map()
      if town then try(game.world and game.world.transition, {id = "chronicle:location:" .. town}) end
    elseif e.index == 4 then
      open_tree()
    end
  end
end)

-- Smoke (playtest 1): walking up to a smoke gate offers the floor behind it, the game's own. Its gate, the one that
-- wants the floor's key, is a smoke door out: it asks, and leaving goes back to the map past the smoke, by teleport.
local smoke_offer = nil -- {dungeon_id, floor_id} the smoke panel is open for
local function smoke_door_out()
  try(game.dungeons.set_story_exits, {title = "LEAVE THROUGH THE SMOKE?", text = "Back to the map, past the smoke."})
end
moonmod.on("game.dungeon.smoke_touched", function(e)
  if in_sandbox or type(e) ~= "table" or type(e.zone) ~= "number" or not floor_now then return end
  local r = region_of(floor_now.dungeon_id, floor_now.floor_id)
  if not r then return end
  local f = r[1] + e.zone
  smoke_offer = {dungeon_id = floor_now.dungeon_id, floor_id = f}
  try(game.ui.choice_open, {id = "vigil.smoke", title = "Smoke", subtitle = string.format("Floor %d lies beyond", f + 1), cancel = true, cursor = 2,
    options = {{title = "Go through", lines = {string.format("Floor %d, as the game has it.", f + 1), {text = "Leave by its far gate, back to the map.", tone = "dim"}}},
               {title = "Stay", lines = {"Not yet."}}}})
end)

moonmod.on("ui.choice_made", function(e)
  if type(e) ~= "table" or e.id ~= "vigil.smoke" or e.cancelled or e.index ~= 1 or not smoke_offer then return end
  local seeds = floor_seeds()
  seeds.smoke_in = smoke_offer
  if floors.key then try(game.save.set, floors.key, seeds) end
  keep_map()
  smoke_door_out()
  -- not `entering`: the game's own map fires no generating event to take it back, and the floor after it arrives at its
  -- zone of the map as any floor entered by its stairs
  local ok, err = call(game.dungeons.enter_floor, {floor_id = smoke_offer.floor_id})
  if not ok then
    toast("Vigil: the smoke won't let you through: " .. message(err), 240)
  end
  smoke_offer = nil
end)

moonmod.on("game.dungeon.story_exit", function(e)
  if type(e) ~= "table" or not e.left or type(e.floor_id) ~= "number" then return end
  local into = floor_seeds().smoke_in
  if type(into) ~= "table" or into.dungeon_id ~= e.dungeon_id then return end
  -- the next floor is a zone of the map: generating clears the smoke and starts the party at that zone's shrine
  local ok, err = call(game.dungeons.enter_floor, {floor_id = e.floor_id + 1})
  if not ok then toast("Vigil: the smoke won't let you through: " .. message(err), 240) end
end)

-- The map's key (playtest 2): the key to a dungeon's back floor (Dran's Crest in Divine Beast Cave) is carried by any
-- monster on its one map. It comes once ("key:<d>": "have", then "used" once the back floor is entered): the game
-- takes it on a knockout or a trip to town, so it is given back on the next visit while "have"; and a second one
-- found is paid out in Gilda instead.
local KEY_GILDA = 300
local function map_key()
  local b = try(game.dungeons.back_floor_get)
  local k = type(b) == "table" and b.gate_key or nil
  if type(k) ~= "table" or type(k.id) ~= "string" or k.id == "" then return nil end
  return k
end
moonmod.on("game.dungeon.generated", function(e)
  if in_sandbox or type(e) ~= "table" or type(e.dungeon_id) ~= "number" or not region_of(e.dungeon_id, e.floor_id or -1) then return end
  local seeds = floor_seeds()
  local tag = "key:" .. tostring(e.dungeon_id)
  if e.back_floor then
    if seeds[tag] == "have" then
      seeds[tag] = "used"
      if floors.key then try(game.save.set, floors.key, seeds) end
    end
    return
  end
  if seeds[tag] ~= "have" then return end
  local k = map_key()
  if k and (k.count or 0) == 0 and try(game.items.give, {id = k.id, count = 1}) then
    toast("Vigil: you still hold the map's key.", 180)
  end
end)
moonmod.on("game.item_picked_up", function(e)
  if in_sandbox or type(e) ~= "table" or not floor_now or not region_of(floor_now.dungeon_id, floor_now.floor_id) then return end
  local k = map_key()
  if not k or e.id ~= k.id then return end
  local seeds = floor_seeds()
  local tag = "key:" .. tostring(floor_now.dungeon_id)
  if seeds[tag] == nil then
    seeds[tag] = "have"
    if floors.key then try(game.save.set, floors.key, seeds) end
    return
  end
  -- found again: keep one at most, and none once it has been used
  local keep = seeds[tag] == "have" and 1 or 0
  local extra = (k.count or 0) - keep
  if extra > 0 and try(game.items.remove, {id = k.id, count = extra}) then
    try(game.economy.add, {amount = KEY_GILDA * extra})
    toast(string.format("Vigil: you have had this key already. %d Gilda instead.", KEY_GILDA * extra), 240)
  end
end)

-- Waking (W1.2): a knockout in a dungeon with a shrine rested at sends the party to town as ever, then on to that
-- shrine, healed, the place built again with its monsters back (a death counts as a rest). Leaving for town and
-- coming back in by the place of that shrine starts there too (ask_zones). The half of the Gilda the game takes for a
-- knockout, and the unspent ABS Vigil takes from the equipped weapon, lie where the party fell ("fallen"): walk there to
-- take them back. Fall again first and they're gone.
local waking = nil -- {dungeon_id, ticks}: knocked out, to wake at the dungeon's shrine once in town

moonmod.on("game.dungeon.defeated", function(e)
  if in_sandbox or type(e) ~= "table" or type(e.dungeon_id) ~= "number" then return end
  waking = rest_shrine(e.dungeon_id) and {dungeon_id = e.dungeon_id, ticks = 0} or nil
  local seeds = floor_seeds()
  seeds.fallen, fallen_lies = nil, false
  local lost = type(e.gilda) == "number" and e.gilda - e.gilda // 2 or 0
  local p = try(game.player.get)
  local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
  if at and floor_now and floor_now.dungeon_id == e.dungeon_id and zoned_floor(floor_now) then
    local w = type(p.weapon) == "table" and p.weapon or nil
    local abs = 0
    if w and w.id then
      local got = try(game.weapons.abs_get, {id = w.id, character = p.character, slot = w.slot})
      local have = type(got) == "table" and math.type(got.abs) == "integer" and math.min(got.abs, 32767) or 0
      if have > 0 then
        local took = try(game.weapons.abs_add, {id = w.id, character = p.character, slot = w.slot, amount = -have})
        abs = type(took) == "table" and math.type(took.added) == "integer" and -took.added or 0
      end
    end
    if lost > 0 or abs > 0 then
      seeds.fallen = {key = place_key(floor_now.dungeon_id, floor_now.floor_id), x = math.floor(at.x / 160 + 0.5),
                      y = math.floor(at.z / 160 + 0.5), px = at.x, py = at.y, pz = at.z, gilda = lost,
                      abs = abs > 0 and {amount = abs, id = w.id, character = p.character, slot = w.slot} or nil}
    end
  end
  if floors.key then try(game.save.set, floors.key, seeds) end
end)

local function passage_rules()
  -- One map per dungeon has no floors to pick from: the entrance goes straight in, to the shrine last rested at
  -- (playtest 2: walking the map marks every floor reached, so the menu offered the boss floor early)
  try(game.dungeons.set_floor_select, {enabled = not (world_save(false) and setting("world_regions", true))})
  -- Open world (O1): town and dungeon are gone between with only a fade, no loading card
  try(game.dungeons.set_quick_passage, {enabled = world_save(false)})
  -- and the towns' gates are the road to the next town, not the world map (Roads, below)
  try(game.world.set_roads, {enabled = world_save(false)})
end

-- Before a place is made, too: a town builds its dungeon's first floor unseen as it loads (the cave in its door), and
-- the rules must stand by then, the first time after a save is loaded as well
moonmod.on("game.scene.will_enter", function(e)
  passage_rules()
  -- the town's dungeon may be built before the town (above): its opening is held before then
  if type(e) == "table" and e.scene_id == "town" then hold_entry_scenes() end
end)

moonmod.on("game.world.location_changed", function(e)
  if type(e) == "table" and e.context ~= "dungeon" then from_town = true end
  if type(e) == "table" and e.context == "georama" then hold_entry_scenes() end
  passage_rules()
  -- a smoke floor's door out only while the party is on the floor entered through the smoke
  local into, w = floor_seeds().smoke_in, try(game.world.get)
  if type(into) == "table" and type(w) == "table" and w.context == "dungeon" and w.dungeon_id == into.dungeon_id then
    smoke_door_out()
  else
    try(game.dungeons.set_story_exits, {})
  end
end)

-- Roads (§10 L6): the towns lie along one road, Norune to Yellow Drops. Walking up to a town's gate facing out (where the
-- world map sets the party down) takes the road to the next town; a town between two asks which way. Only with Vigil
-- World, whose quick passage makes the trip a cut, not a loading card. The gate was the world map, so the dungeons only
-- the map reached (Shipwreck, Sun and Moon Temple, Moon Sea, Gallery of Time) are along the road too; Divine Beast Cave
-- and Wise Owl Forest are walked into from their towns.
local ROAD = {[0] = {{town = 1}},
              [1] = {{town = 0}, {town = 2}},
              [2] = {{town = 1}, {town = 3}, {dungeon = 2}},
              [3] = {{town = 2}, {town = 4}, {dungeon = 3}},
              [4] = {{town = 3}, {dungeon = 4}, {dungeon = 5}}}
local TOWN_NAMES = {[0] = "Norune Village", [1] = "Matataki Village", [2] = "Queens", [3] = "Muska Lacka", [4] = "Yellow Drops"}
local DUNGEON_NAMES = {[2] = "Shipwreck", [3] = "Sun and Moon Temple", [4] = "Moon Sea", [5] = "Gallery of Time"}
local road_from = nil -- the town the road panel is open in

local function take_road(way)
  local ok, err
  if way.town then
    ok, err = call(game.world.transition, {id = "chronicle:location:" .. SHRINE_TOWNS[way.town]})
  else
    -- in at its entrance, floor 1, as through a town's door
    ok, err = call(game.dungeons.enter_floor, {dungeon_id = way.dungeon, floor_id = 0})
  end
  if not ok then toast("Vigil: the road is closed: " .. message(err), 240) end
end

moonmod.on("game.town.road", function(e)
  if in_sandbox or type(e) ~= "table" or not ROAD[e.town_id] or not world_save(false) then return end
  road_from = e.town_id
  local options = {}
  for _, way in ipairs(ROAD[e.town_id]) do
    if way.town then
      options[#options + 1] = {title = TOWN_NAMES[way.town], lines = {way.town < e.town_id and "Back along the road." or "On along the road."}}
    else
      options[#options + 1] = {title = DUNGEON_NAMES[way.dungeon], lines = {"Into the dungeon, at floor 1."}}
    end
  end
  options[#options + 1] = {title = "Stay", lines = {{text = "Not yet.", tone = "dim"}}}
  try(game.ui.choice_open, {id = "vigil.road", title = "The road", subtitle = "Out of " .. TOWN_NAMES[e.town_id],
                            cancel = true, cursor = 1, town = true, options = options})
end)

moonmod.on("ui.choice_made", function(e)
  if type(e) ~= "table" or e.id ~= "vigil.road" or e.cancelled or not road_from then return end
  local way = ROAD[road_from][e.index]
  road_from = nil
  if way then take_road(way) end
end)

moonmod.on("game.tick", function()
  if not waking then return end
  local w = try(game.world.get)
  if type(w) ~= "table" or w.context == "dungeon" then return end
  waking.ticks = waking.ticks + 1
  if waking.ticks % 30 ~= 0 then return end -- the town settles first; a scene there holds it
  local sh = rest_shrine(waking.dungeon_id)
  if not sh then waking = nil return end
  entering = true
  local ok, err = call(game.dungeons.enter_floor, {dungeon_id = waking.dungeon_id, floor_id = sh.floor_id, x = sh.x, y = sh.y + 1, teleport = true})
  if ok then
    waking = nil
    heal_party()
    toast(floor_seeds().fallen and "Vigil: you wake at the shrine. The monsters have returned. What you lost lies where you fell."
          or "Vigil: you wake at the shrine. The monsters have returned.", 300)
  else
    entering = false
    if waking.ticks >= 1800 then
      waking = nil
      toast("Vigil: couldn't take you back to the shrine: " .. message(err), 240)
    end
  end
end)

-- The map (W2.1) ----------------------------------------------------------------------------------------------------
-- Select, L3 or M opens the map (in a town Select is the game's Georama button, so there it is L3 or M). In a dungeon it is the floor you're on, as far as you've seen it, with its shrines and
-- locked gates once found and your waypoint; Triangle puts the waypoint, which the minimap shows too. What you've seen
-- of a kept place is kept with it ("0:0:map"), so it is still seen on your next visit, and in the dungeon's town the
-- map shows every place of its dungeons you've been to (L2/R2 between them): Cross on a lit shrine travels there.
local DUNGEON_NAMES = {[0] = "Divine Beast Cave", [1] = "Wise Owl Forest", [2] = "Shipwreck", [3] = "Sun and Moon Temple",
                       [4] = "Moon Sea", [5] = "Gallery of Time", [6] = "Demon Shaft"}
-- The player is on a back floor (floor_now is the main floor's). Asked of the game: each main floor's back floor is
-- built with it, so a built back floor doesn't mean the player is there.
local function on_back()
  local w = try(game.world.get)
  return type(w) == "table" and w.back_floor == true
end
local map_up = nil        -- the open map: {pages = travel map pages or nil, page, key, marks, here = the shrine travelled from}
local map_bound = false
local map_clock, map_closed_at, map_seen = 0, -100, -1

moonmod.on("game.dungeon.generated", function(e)
  if type(e) ~= "table" then return end
  if e.back_floor then return end
  map_seen = -1
  local seeds, k = floor_seeds(), place_key(e.dungeon_id, e.floor_id)
  local m, w = seeds[k .. ":map"], seeds[k .. ":waypoint"]
  if kept_floor(e) and type(m) == "table" and type(m.cells) == "string" and type(m.seed) == "number" then
    try(game.dungeons.set_seen, {seed = m.seed, cells = m.cells})
  end
  if kept_floor(e) and type(w) == "table" and type(w.x) == "number" then
    try(game.dungeons.set_waypoint, {x = w.x, y = w.y})
  else
    try(game.dungeons.set_waypoint, {})
  end
end)

-- The floors a kept place covers, for its map's name.
local function place_title(dungeon_id, first)
  local r = region_of(dungeon_id, first)
  local floors_text = r and string.format("Floors %d-%d", r[1] + 1, r[2] + 1) or string.format("Floor %d", first + 1)
  return DUNGEON_NAMES[dungeon_id] or "Dungeon", floors_text
end

-- Keeps what the player has seen of the place they're on (and where its shrines stand), when it has grown.
keep_map = function()
  if in_sandbox or not floor_now or not kept_floor(floor_now) or on_back() then return end
  local seeds, k = floor_seeds(), place_key(floor_now.dungeon_id, floor_now.floor_id)
  if type(seeds[k]) ~= "number" then return end
  local snap = try(game.dungeons.map_snapshot)
  if type(snap) ~= "table" or snap.seed ~= seeds[k] or snap.seen == map_seen then return end
  map_seen = snap.seen
  local kept = {seed = snap.seed, cells = snap.cells}
  local z = try(game.dungeons.zones_get)
  if type(z) == "table" and type(z.shrines) == "table" then
    kept.shrines = {}
    for _, sh in ipairs(z.shrines) do kept.shrines[#kept.shrines + 1] = {zone = sh.zone, x = sh.x, y = sh.y} end
  end
  seeds[k .. ":map"] = kept
  if floors.key then try(game.save.set, floors.key, seeds) end
end

-- A place's shrines as marks: lit ones by name (Cross travels to them when `travel`), the others once found.
local function shrine_marks(marks, seeds, k, first, positions, travel)
  local lit, list = {}, {}
  -- by zone, so the cursor and L1/R1 go floor by floor
  for _, sh in ipairs(type(seeds[k .. ":shrines"]) == "table" and seeds[k .. ":shrines"] or {}) do list[#list + 1] = sh end
  table.sort(list, function(a, b) return (tonumber(type(a) == "table" and a.zone) or 0) < (tonumber(type(b) == "table" and b.zone) or 0) end)
  for _, sh in ipairs(list) do
    if type(sh) == "table" and type(sh.zone) == "number" then
      lit[sh.zone] = true
      local label = shrine_name({floor_id = first, zone = sh.zone, label = sh.label})
      marks[#marks + 1] = {x = sh.x, y = sh.y, kind = "shrine_lit", label = label .. (travel and "" or " (lit)"), pick = travel,
                           shrine = {floor_id = first, zone = sh.zone, x = sh.x, y = sh.y}}
    end
  end
  for _, sh in ipairs(type(positions) == "table" and positions or {}) do
    if type(sh) == "table" and not lit[sh.zone] then
      marks[#marks + 1] = {x = sh.x, y = sh.y, kind = "shrine", label = "Shrine (not lit)"}
    end
  end
end

local function waypoint_mark(marks, seeds, k)
  local w = seeds[k .. ":waypoint"]
  if type(w) == "table" and type(w.x) == "number" then marks[#marks + 1] = {x = w.x, y = w.y, kind = "waypoint", label = "Waypoint"} end
  local f = seeds.fallen
  if type(f) == "table" and f.key == k and type(f.x) == "number" then
    local abs = type(f.abs) == "table" and f.abs.amount or 0
    marks[#marks + 1] = {x = f.x, y = f.y, kind = "mark", label = abs > 0 and string.format("Where you fell (%d Gilda, %d ABS)", f.gilda or 0, abs)
                                                                   or string.format("Where you fell (%d Gilda)", f.gilda or 0)}
  end
end

-- The engine takes marks without Vigil's own fields.
local function plain(marks)
  local out = {}
  for i, m in ipairs(marks) do out[i] = {x = m.x, y = m.y, kind = m.kind, label = m.label, pick = m.pick or false} end
  return out
end

local function open_floor_map()
  local title, subtitle = DUNGEON_NAMES[floor_now and floor_now.dungeon_id] or "Dungeon", nil
  local marks, k = {}, nil
  local seeds = floor_seeds()
  local back = on_back()
  if floor_now and not back and kept_floor(floor_now) then
    keep_map()
    k = place_key(floor_now.dungeon_id, floor_now.floor_id)
    local first = tonumber(k:match(":(%d+)$"))
    title, subtitle = place_title(floor_now.dungeon_id, first)
    local z = try(game.dungeons.zones_get)
    shrine_marks(marks, seeds, k, first, type(z) == "table" and z.shrines, false)
    for _, g in ipairs(type(z) == "table" and type(z.gates) == "table" and z.gates or {}) do
      if g.locked then marks[#marks + 1] = {x = g.x, y = g.y, kind = "gate", label = "Locked gate"} end
    end
    waypoint_mark(marks, seeds, k)
  elseif back then
    subtitle = "Back floor"
  end
  if try(game.ui.map_open, {id = "vigil.map", title = title, subtitle = subtitle, marks = plain(marks), waypoints = k ~= nil}) then
    map_up = {key = k, marks = marks}
  end
end

-- Kept places of the dungeons `wanted` takes, as map pages: those with a kept map, and (`lit`) those with a lit
-- shrine though their map isn't kept yet (the place you stand in shows itself).
local function kept_pages(wanted, lit)
  local pages, seen = {}, {}
  for k, v in pairs(floor_seeds()) do
    local d, f, list = tostring(k):match("^(%d+):(%d+):(%a+)$")
    d, f = tonumber(d), tonumber(f)
    local key = d and (d .. ":" .. f)
    if d and not seen[key] and wanted(d) and type(v) == "table" and
       ((list == "map" and type(v.cells) == "string") or (lit and list == "shrines" and #v > 0)) then
      seen[key] = true
      pages[#pages + 1] = {dungeon_id = d, first = f, key = key}
    end
  end
  local seeds = floor_seeds()
  for _, page in ipairs(pages) do page.map = type(seeds[page.key .. ":map"]) == "table" and seeds[page.key .. ":map"] or {} end
  table.sort(pages, function(a, b) return a.dungeon_id < b.dungeon_id or (a.dungeon_id == b.dungeon_id and a.first < b.first) end)
  return pages
end

-- The kept places of the town's dungeons.
local function town_pages(area_id)
  local town = SHRINE_TOWNS[area_id]
  if not town then return {} end
  return kept_pages(function(d) return SHRINE_TOWNS[d] == town end, false)
end

-- A page of the travel map. From a shrine (`here`), the one you stand at is shown but not offered.
local function open_town_map(pages, index, here)
  local page = pages[index]
  local seeds, marks = floor_seeds(), {}
  local title, floors_text = place_title(page.dungeon_id, page.first)
  shrine_marks(marks, seeds, page.key, page.first, page.map.shrines, here ~= nil or world_save(false))
  for _, m in ipairs(marks) do
    if here and m.shrine and m.shrine.zone == here.zone and page.key == place_key(here.dungeon_id, here.floor_id) then
      m.pick, m.label = false, m.label .. " (you are here)"
    end
  end
  waypoint_mark(marks, seeds, page.key)
  local subtitle = #pages > 1 and string.format("%s  (%d of %d)", floors_text, index, #pages) or floors_text
  local cursor = nil
  for _, m in ipairs(marks) do if m.pick and not cursor then cursor = {x = m.x, y = m.y} end end
  if try(game.ui.map_open, {id = "vigil.map", title = title, subtitle = subtitle, cells = page.map.cells, marks = plain(marks),
                            cursor = cursor, waypoints = true, hint = "Travel", pages = #pages > 1}) then
    map_up = {pages = pages, page = index, key = page.key, dungeon_id = page.dungeon_id, marks = marks, here = here}
  end
end

-- Travel from a shrine: the dungeon's map, on the first page with another lit shrine to pick.
open_travel_map = function(here)
  keep_map()
  local pages = kept_pages(function(d) return d == here.dungeon_id end, true)
  if #pages == 0 then return end
  local seeds, start = floor_seeds(), nil
  for i, page in ipairs(pages) do
    for _, sh in ipairs(type(seeds[page.key .. ":shrines"]) == "table" and seeds[page.key .. ":shrines"] or {}) do
      local mine = page.key == place_key(here.dungeon_id, here.floor_id) and sh.zone == here.zone
      if not start and not mine then start = i end
    end
  end
  open_town_map(pages, start or 1, here)
end

local function open_map()
  local w = try(game.world.get)
  if type(w) ~= "table" then return end
  if w.context == "dungeon" then
    open_floor_map()
  elseif w.context == "georama" then
    local pages = town_pages(w.area_id)
    if #pages == 0 then toast("Vigil: no maps yet. A dungeon's map is kept here once you've explored it.", 240) return end
    open_town_map(pages, 1)
  end
end

moonmod.on("game.tick", function()
  map_clock = map_clock + 1
  if in_sandbox or not setting("world_map", true) then return end
  if not map_bound then
    map_bound = true
    for id, keys in pairs({open_map = {"M", "Gamepad:leftstick"}, open_map_select = {"Gamepad:back"}}) do
      local ok, err = call(game.input.bind, {id = id, keys = keys})
      if not ok then moonmod.log("warn", "map binding: " .. message(err)) end
    end
  end
  if map_clock % 300 == 0 and not map_up then keep_map() end
  local press = try(game.input.consume, {id = "open_map"})
  local select = try(game.input.consume, {id = "open_map_select"})
  local pressed = type(press) == "table" and press.pressed
  if type(select) == "table" and select.pressed then
    local w = try(game.world.get)
    pressed = pressed or (type(w) == "table" and w.context == "dungeon")
  end
  -- the press that closed the map is not one that opens it again
  if pressed and not map_up and map_clock - map_closed_at > 15 then open_map() end
end)

moonmod.on("ui.map_closed", function(e)
  if type(e) ~= "table" or e.id ~= "vigil.map" then return end
  map_up, map_closed_at = nil, map_clock
end)

moonmod.on("ui.map_page", function(e)
  if type(e) ~= "table" or e.id ~= "vigil.map" or not map_up or not map_up.pages then return end
  local n = #map_up.pages
  open_town_map(map_up.pages, (map_up.page - 1 + (e.way or 1)) % n + 1, map_up.here)
end)

moonmod.on("ui.map_waypoint", function(e)
  if type(e) ~= "table" or e.id ~= "vigil.map" or not map_up or not map_up.key then return end
  local seeds = floor_seeds()
  seeds[map_up.key .. ":waypoint"] = e.set and {x = e.x, y = e.y} or nil
  if floors.key then try(game.save.set, floors.key, seeds) end
end)

-- Cross on a lit shrine of the travel map: there, the place built again from its seed (on the place you stand in
-- from a shrine, a warp).
moonmod.on("ui.map_choice", function(e)
  if type(e) ~= "table" or e.id ~= "vigil.map" or not map_up or not map_up.pages then return end
  local mark = map_up.marks[e.mark]
  if not mark or not mark.shrine or not mark.pick then return end
  local sh = mark.shrine
  if map_up.here and shrine_at then
    try(game.ui.map_close)
    go_to_shrine(sh, shrine_at.floor_id)
    return
  end
  entering = true
  local ok, err = call(game.dungeons.enter_floor, {dungeon_id = map_up.dungeon_id, floor_id = sh.floor_id, x = sh.x, y = sh.y + 1, teleport = true})
  if not ok then
    entering = false
    toast("Vigil: can't travel from here: " .. message(err), 240)
  end
end)

-- The Gilda lost to a knockout, taken back by walking to where the party fell: a pile of it lies there (the game's own,
-- as a thief drops what it stole), on the corner map too.
local bag_down = false -- the pile is on the floor built last
moonmod.on("game.dungeon.generated", function(e)
  if type(e) == "table" and not e.back_floor then bag_down = false end
end)
local BAG_REACH = 60
moonmod.on("game.tick", function()
  if in_sandbox or map_clock % 10 ~= 0 or not floor_now or map_up or not fallen_lies or on_back() then return end
  local seeds = floor_seeds()
  local f = seeds.fallen
  if type(f) ~= "table" or f.key ~= place_key(floor_now.dungeon_id, floor_now.floor_id) then return end
  local p = try(game.player.get)
  local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
  local fx, fz = type(f.px) == "number" and f.px or 160 * f.x, type(f.pz) == "number" and f.pz or 160 * f.y
  if not at then return end
  if not bag_down and (f.gilda or 0) > 0 then
    bag_down = try(game.dungeons.drop_gilda, {x = fx, y = type(f.py) == "number" and f.py or at.y, z = fz, amount = f.gilda}) ~= nil
  end
  if math.abs(at.x - fx) > BAG_REACH or math.abs(at.z - fz) > BAG_REACH then return end
  local left = bag_down and 0 or (f.gilda or 0) -- the pile gives its Gilda as the player walks onto it
  while left > 0 do
    local part = math.min(left, 32767)
    if not try(game.economy.add, {amount = part}) then break end
    left = left - part
  end
  local abs = type(f.abs) == "table" and math.type(f.abs.amount) == "integer" and f.abs.amount or 0
  if abs > 0 then
    -- back to the weapon it came from, or the one in hand if that one is gone
    local back = try(game.weapons.abs_add, {id = f.abs.id, character = f.abs.character, slot = f.abs.slot, amount = abs})
    if not back then
      local w = type(p.weapon) == "table" and p.weapon or nil
      if w and w.id then try(game.weapons.abs_add, {id = w.id, character = p.character, slot = w.slot, amount = abs}) end
    end
  end
  seeds.fallen = nil
  if floors.key then try(game.save.set, floors.key, seeds) end
  toast(abs > 0 and string.format("Vigil: you take back %d Gilda and %d ABS.", f.gilda or 0, abs)
        or string.format("Vigil: you take back %d Gilda.", f.gilda or 0), 240)
end)

-- Floor scaling (W1.4) -------------------------------------------------------------------------------------------
-- Each zone has a base level that rises with depth (two per floor). The player's level, until Vigil has its own tree,
-- comes from the equipped weapon's attack against what a weapon has at the dungeon's start. A monster is fought at
-- max(zone base, player level - gap): one in a zone the player has outgrown is raised to just under them, so nothing
-- dies in a hit or two. Each monster is scaled once, as it wakes, through entities.set_stats.
local WEAPON_START = {[0] = 10, [1] = 28, [2] = 45, [3] = 65, [4] = 85, [5] = 105}
local scaled = {}  -- entity ids already scaled on this floor
local scale_clock = 0

-- How much stronger than the game made it a monster of this zone is, for a weapon of this attack.
local function zone_scaling(dungeon_id, floor_id, zone, attack)
  local base = 1 + 2 * floor_id + zone
  local player = 1 + math.max(0, (attack or 0) - (WEAPON_START[dungeon_id] or 10))
  local level = math.max(base, player - setting("scaling_gap", 2))
  local over = level - base
  return {level = level, base = base, hp = 1 + 0.12 * over + 0.1 * zone, damage = math.min(2, 1 + 0.06 * over), reward = 1 + 0.05 * over}
end

local function scale_monsters()
  local q = try(game.entities.query, {type = "monster"})
  if type(q) ~= "table" or type(q.entities) ~= "table" then return end
  local p = try(game.player.get)
  local attack = type(p) == "table" and type(p.weapon) == "table" and p.weapon.attack or 0
  local z = try(game.dungeons.zones_get)
  local zone = type(z) == "table" and type(z.current) == "number" and z.current or 0
  -- In a region each zone is a floor of its own.
  local r = region_of(floor_now.dungeon_id, floor_now.floor_id)
  local k = r and zone_scaling(floor_now.dungeon_id, r[1] + zone, 0, attack) or zone_scaling(floor_now.dungeon_id, floor_now.floor_id, zone, attack)
  for _, m in ipairs(q.entities) do
    local id = m.entity_id
    local normal = type(m.definition) ~= "table" or m.definition.kind == 0
    if id and m.revealed and not scaled[id] and normal and m.character == nil then
      scaled[id] = true
      local health = type(m.health) == "table" and m.health or {}
      local combat = type(m.combat) == "table" and m.combat or {}
      local stats = {entity = id}
      if type(health.maximum) == "number" and k.hp > 1 then stats.max_hp = math.max(1, math.min(1000000, math.floor(health.maximum * k.hp + 0.5))) end
      if k.damage > 1 then stats.damage_scale = k.damage end
      if k.reward > 1 and type(combat.reward_exp) == "number" then stats.reward_exp = math.min(32767, math.floor(combat.reward_exp * k.reward + 0.5)) end
      if k.reward > 1 and type(combat.reward_money) == "number" then stats.reward_money = math.floor(combat.reward_money * k.reward + 0.5) end
      if stats.max_hp or stats.damage_scale or stats.reward_exp or stats.reward_money then try(game.entities.set_stats, stats) end
    end
  end
end

moonmod.on("game.dungeon.generated", function(e)
  if type(e) == "table" and not e.back_floor then scaled = {} end
end)

moonmod.on("game.tick", function()
  scale_clock = scale_clock + 1
  if scale_clock % 30 ~= 0 or in_sandbox or not floor_now or not zoned_floor(floor_now) or not setting("world_scaling", true) then return end
  scale_monsters()
end)

moonmod.on("game.dungeon.town_refused", function(e)
  if in_sandbox then return end
  toast("Vigil: the way back to town is through a shrine.", 240)
end)

-- Events ----------------------------------------------------------------------------------------------------------
moonmod.on("game.tick", function()
  if in_sandbox then return end
  local now = guard_held()
  if now ~= guarding then
    guarding = now
    apply_tuning()
  end
end)

-- The enemy brain watches for the player's rolls, to hold a swing until the roll is spent.
moonmod.on("game.player.move", function(e)
  if type(e) == "table" and EVADE_IDS[e.id] then rolled = hook_frame end
end)

moonmod.on("settings.changed", function()
  if in_sandbox then return end
  apply()
  local kept = floor_seeds().world
  if type(kept) == "boolean" and kept ~= setting("world_zones", false) then
    toast(kept and "Vigil: this save was started with Vigil World and keeps it. The setting is for new games."
               or "Vigil: this save was started without Vigil World and stays a normal save. The setting is for new games.", 360)
  end
end)

moonmod.on("game.world.location_changed", function(e)
  minds, kinds, turn = {}, {}, nil -- a new floor: no monster carries its plan over
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
  toast(string.format("Vigil: evades %s, Toan's attacks %s, enemy brain %s, enemy damage x%.2f, recoil x%.2f, gauge refill x%.2f%s",
    tostring(applied.evades), tostring(applied.toan_attacks), tostring(applied.enemy_brain), applied.enemy_damage or 1, t.recoil_scale or 1, t.gauge_refill or 1,
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
