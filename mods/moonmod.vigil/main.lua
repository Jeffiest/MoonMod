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
--   * The guard covers the front only, costs gauge for each blocked hit, lets a little through, breaks when the gauge
--     can't pay, parries in its first frames, and works without a lock-on (player.guard_rules_set, E1). A hit that
--     lands drains the gauge instead of filling it, the first swing needs and costs gauge, and the refill waits a
--     moment after a spend (player.gauge_rules_set, E2). game.player.hit tells Vigil of parries and breaks.
--
-- Vigil sits out other mods' game modes (Dark Genie's Gauntlet), as the Cookbook's "Share the game with other mods"
-- describes: no moves, no tuning, formulas back to x1, until the session ends.

-- This chunk is near Lua's limit of 200 locals. Put a new feature's helpers and state in a do ... end block, and
-- forward-declare (one local line) only what code outside it calls, as the gear and the riposte blocks do.

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

-- Criticals (§12, stretch goal 3): the attack button at an enemy's back stabs it (a backstab), and so does the attack
-- button at an enemy you parried or whose poise you broke (a riposte, armed with player.critical_set). Toan is drawn
-- in and plays toan_critical; the enemy plays its own crumple (MONSTER_MOVES crumple, the pairs below) and its script
-- waits it out. The blows land at x critical (the setting) on that kind of enemy while it lasts.
ATTACKS.critical = {anim = "toan_critical", moves = {}, pairs = {}} -- pairs: filled from MONSTER_MOVES, below
for _, kind in ipairs({"backstab", "riposte"}) do
  ATTACKS.critical.moves[#ATTACKS.critical.moves + 1] = {anim = "toan_critical", id = "vigil_toan_" .. kind, trigger = "critical",
    critical = kind, reach = kind == "riposte" and 26 or 22, gap = 11, arc = 100, speed = 0.5, invincible = true,
    cooldown = 30,
    hits = {{at = 0.24, radius = 8, reach = 9, damage = 1.2, knockback = 0},
            {at = 0.57, radius = 8, reach = 9, damage = 1.8, knockback = 0, burst = "sparks", burst_scale = 1.5}},
    cues = {{at = 0.05, sound = "voice"}, {at = 0.2, sound = "swing_heavy", trail = "slam"}, {at = 0.55, sound = "shout"}}}
end

-- Weapon arts (§12, stretch goal 4): R2 while guarding (R1) plays the equipped weapon's art, once the weapon has been
-- built up to the Art level (a setting). Toan's blades fall in three families: the short blades lunge and stab twice,
-- the long swords spin, the great swords split the ground. Each is one of his attack motions played its own way, at a
-- gauge cost. The weapon's card in the menu says which art it has and when it unlocks (Weapon arts, below).
ATTACKS.arts = {
  {anim = "toan_lunge", id = "vigil_toan_art_rush", name = "Piercing Rush", line = "A long lunge that stabs twice.",
    weapons = {258, 259, 260, 262, 265, 266, 278, 283, 290, 291, 293},
    trigger = "art", speed = 0.85, lunge = 4.6, lunge_decay = 0.18, gauge = 35, cooldown = 30,
    hits = {{at = 0.36, radius = 10, reach = 11, damage = 1.8, knockback = 4},
            {at = 0.5, radius = 10, reach = 13, damage = 1.4, knockback = 3, burst = "sparks"}},
    cues = {{at = 0.1, sound = "shout"}, {at = 0.3, sound = "swing", trail = "heavy"}}},
  {anim = "toan_finisher_3", id = "vigil_toan_art_whirl", name = "Whirlwind", line = "Two turns with the blade out, then a cut.",
    weapons = {261, 263, 267, 268, 270, 271, 272, 273, 274, 276, 279, 280, 281, 282, 285, 287, 292, 294, 295, 296, 297, 298},
    trigger = "art", speed = 0.9, spin = 2, spin_from = 0.2, spin_to = 0.5, gauge = 45, cooldown = 36,
    hits = {{at = 0.24, radius = 17, reach = 0, damage = 1.0}, {at = 0.32, radius = 17, reach = 0, damage = 1.0},
            {at = 0.4, radius = 17, reach = 0, damage = 1.0}, {at = 0.48, radius = 17, reach = 0, damage = 1.0},
            {at = 0.59, radius = 12, reach = 9, damage = 2.2, knockback = 6, heavy = true, burst = "sparks", burst_scale = 1.5}},
    cues = {{at = 0.05, sound = "shout_2"}, {at = 0.22, sound = "swing", trail = "wide"}, {at = 0.55, sound = "shout", trail = "heavy"}}},
  {anim = "toan_heavy", id = "vigil_toan_art_split", name = "Earthsplitter", line = "A slam that bursts the ground around it.",
    weapons = {264, 269, 275, 284, 286, 288, 289},
    trigger = "art", speed = 0.75, lunge = 0.8, lunge_decay = 0.15, gauge = 50, cooldown = 40, wear = 2,
    hits = {{at = 0.43, radius = 18, reach = 8, damage = 3.4, knockback = 8, heavy = true, burst = "explosion", burst_scale = 1.2}},
    cues = {{at = 0.05, sound = "voice_3"}, {at = 0.36, sound = "swing_heavy", trail = "slam"}}},
}

-- The other heroes' attacks (§13, item 5): the Gauntlet's sets (mods/moonmod.roguelike, melee_set and caster_set),
-- their motions copied into resources/anims. Goro and Ungaga get a heavy, a finisher after two blows and after three,
-- a counter from the guard and an attack out of a roll; Xiao, Ruby and Osmond a charged heavy shot and two volleys.
-- Each move whose motion doesn't register is left out on its own.
do
  local function melee(who, reach, power)
    local function d(x) return x * power end
    return {
      {anim = who .. "_heavy", character = who, trigger = "heavy", speed = 0.9, lunge = 1.2, lunge_decay = 0.15, cooldown = 30, wear = 1.5,
        hits = {{at = 0.43, radius = 11, reach = 8 * reach, damage = d(2.4), knockback = 5, heavy = true, burst = "impact", burst_scale = 1.5}},
        cues = {{at = 0.05, sound = "voice"}, {at = 0.36, sound = "swing_heavy", trail = "slam"}}},
      {anim = who .. "_launcher", character = who, trigger = "combo_finisher", chain = 2, speed = 1.1, lunge = 1.0, lunge_decay = 0.15,
        cooldown = 20, hits = {{at = 0.29, radius = 10, reach = 6 * reach, height = 8, damage = d(1.6), knockback = 6, heavy = true},
                               {at = 0.4, radius = 10, reach = 5 * reach, height = 14, damage = d(0.8), knockback = 2}},
        cues = {{at = 0.1, sound = "voice_2"}, {at = 0.25, sound = "swing", trail = "wide"}}},
      {anim = who .. "_spin_finisher", character = who, trigger = "combo_finisher", chain = 3, speed = 1.0, spin = 1, spin_from = 0.24,
        spin_to = 0.44, cooldown = 30,
        hits = {{at = 0.28, radius = 15, reach = 0, damage = d(0.9)}, {at = 0.36, radius = 15, reach = 0, damage = d(0.9)},
                {at = 0.44, radius = 15, reach = 0, damage = d(0.9)},
                {at = 0.59, radius = 11, reach = 9 * reach, damage = d(2.0), knockback = 5, heavy = true, burst = "sparks", burst_scale = 1.5}},
        cues = {{at = 0.05, sound = "shout"}, {at = 0.25, sound = "swing", trail = "heavy"}, {at = 0.55, sound = "shout_2", trail = "wide"}}},
      {anim = who .. "_counter", character = who, trigger = "guard_attack", speed = 1.0, invincible = true, cooldown = 20,
        hits = {{at = 0.33, radius = 10, reach = 6 * reach, height = 8, damage = d(1.8), knockback = 4, heavy = true}},
        cues = {{at = 0.1, sound = "voice"}, {at = 0.3, sound = "swing_heavy", trail = "wide"}}},
      {anim = who .. "_roll_slash", character = who, trigger = "evade_attack", speed = 1.0, lunge = 2.0, lunge_decay = 0.15, cooldown = 20,
        hits = {{at = 0.32, radius = 11, reach = 8 * reach, height = 6, damage = d(1.6), knockback = 4}},
        cues = {{at = 0.05, sound = "voice_2"}, {at = 0.25, sound = "swing", trail = "wide"}}},
    }
  end
  -- Xiao's finishers take no gauge (her shots have just spent it); her heavy and the others' casts take their gauge.
  local function caster(who, gauge, heavy, fan)
    return {
      {anim = heavy, id = "vigil_" .. who .. "_heavy", character = who, trigger = "heavy", speed = 0.9, gauge = gauge, cooldown = 30,
        hits = {{at = 0.53, shot = true, damage = 2.6, speed = 7}}, cues = {{at = 0.05, sound = "voice"}, {at = 0.5, sound = "shout"}}},
      {anim = fan, id = "vigil_" .. who .. "_fan", character = who, trigger = "combo_finisher", chain = 2, from = 0.15, speed = 1.0,
        cooldown = 24, hits = {{at = 0.31, shot = true, count = 5, spread = 14, damage = 0.7}}, cues = {{at = 0.05, sound = "voice_2"}}},
      {anim = who .. "_volley", character = who, trigger = "combo_finisher", chain = 3, speed = 1.0, cooldown = 30,
        hits = {{at = 0.23, shot = true, count = 3, spread = 12, damage = 0.7}, {at = 0.42, shot = true, count = 3, spread = 12, damage = 0.7},
                {at = 0.62, shot = true, count = 3, spread = 12, damage = 0.7}}, cues = {{at = 0.05, sound = "shout"}}},
    }
  end
  ATTACKS.party = {}
  for _, set in ipairs({melee("goro", 0.9, 1.1), melee("ungaga", 1.3, 1.0), caster("xiao", 100, "xiao_heavy_shot", "xiao_triple_shot"),
                        caster("ruby", 100, "ruby_heavy_cast", "ruby_rush"), caster("osmond", 50, "osmond_heavy_cast", "osmond_rush")}) do
    for _, attack in ipairs(set) do ATTACKS.party[#ATTACKS.party + 1] = attack end
  end
  ATTACKS.party_criticals = {}
  -- Each hero's own critical (tools/anim/party_moves.py and xiao_moves.py), on Toan's timing: driven in at 0.24, the
  -- second blow at 0.57 (a caster's a cast into the fallen enemy, then another at point blank).
  for _, c in ipairs({{"goro"}, {"ungaga"}, {"xiao", true}, {"ruby", true}, {"osmond", true}}) do
    for _, kind in ipairs({"backstab", "riposte"}) do
      local function blow(at, damage)
        return c[2] and {at = at, shot = true, damage = damage, speed = 7, burst = at > 0.5 and "sparks" or nil}
                     or {at = at, radius = 8, reach = 9, damage = damage, knockback = 0, burst = at > 0.5 and "sparks" or nil,
                         burst_scale = at > 0.5 and 1.5 or nil}
      end
      ATTACKS.party_criticals[#ATTACKS.party_criticals + 1] = {anim = c[1] .. "_critical", id = "vigil_" .. c[1] .. "_" .. kind,
        character = c[1], trigger = "critical", critical = kind, reach = kind == "riposte" and 26 or 22, gap = 11, arc = 100,
        speed = 0.5, invincible = true, cooldown = 30, hits = {blow(0.24, 1.2), blow(0.57, 1.8)},
        cues = {{at = 0.05, sound = "voice"}, {at = 0.2, sound = "swing_heavy"}, {at = 0.55, sound = "shout"}}}
    end
  end
  -- Their weapon arts (§12 goal 4 for the party): one each, on every weapon of theirs, from their own moves played
  -- their own way. Weapons by item number, the broken and unused ones left out.
  local function span(a, b, gap) local out = {} for i = a, b do if i ~= gap then out[#out + 1] = i end end return out end
  for _, art in ipairs({
    {anim = "goro_heavy", character = "goro", id = "vigil_goro_art_quake", name = "Earthquake",
      line = "A slow slam that shakes the ground all around.", weapons = span(315, 329, 326),
      speed = 0.7, lunge = 0.6, lunge_decay = 0.15, gauge = 50, cooldown = 40, wear = 2,
      hits = {{at = 0.43, radius = 22, reach = 8, damage = 3.6, knockback = 9, heavy = true, burst = "explosion", burst_scale = 1.4}},
      cues = {{at = 0.05, sound = "voice_3"}, {at = 0.36, sound = "swing_heavy", trail = "slam"}}},
    {anim = "ungaga_spin_finisher", character = "ungaga", id = "vigil_ungaga_art_storm", name = "Spear Storm",
      line = "Two turns with the spear out, then a thrust.", weapons = span(348, 360, 358),
      speed = 0.9, spin = 2, spin_from = 0.2, spin_to = 0.5, gauge = 45, cooldown = 36,
      hits = {{at = 0.24, radius = 19, reach = 0, damage = 1.0}, {at = 0.32, radius = 19, reach = 0, damage = 1.0},
              {at = 0.4, radius = 19, reach = 0, damage = 1.0}, {at = 0.48, radius = 19, reach = 0, damage = 1.0},
              {at = 0.59, radius = 12, reach = 12, damage = 2.2, knockback = 6, heavy = true, burst = "sparks", burst_scale = 1.5}},
      cues = {{at = 0.05, sound = "shout_2"}, {at = 0.22, sound = "swing", trail = "wide"}, {at = 0.55, sound = "shout", trail = "heavy"}}},
    {anim = "xiao_volley", character = "xiao", id = "vigil_xiao_art_rain", name = "Stone Rain",
      line = "Three wide fans of stones.", weapons = span(300, 313),
      speed = 1.1, gauge = 40, cooldown = 30,
      hits = {{at = 0.23, shot = true, count = 5, spread = 20, damage = 0.8}, {at = 0.42, shot = true, count = 5, spread = 20, damage = 0.8},
              {at = 0.62, shot = true, count = 5, spread = 20, damage = 0.8}},
      cues = {{at = 0.05, sound = "shout"}}},
    {anim = "ruby_heavy_cast", character = "ruby", id = "vigil_ruby_art_inferno", name = "Inferno",
      line = "One great orb, slow to draw, that bursts where it lands.", weapons = span(332, 345, 342),
      speed = 0.75, gauge = 50, cooldown = 40,
      hits = {{at = 0.53, shot = true, damage = 4.2, speed = 6, burst = "explosion"}},
      cues = {{at = 0.05, sound = "voice_3"}, {at = 0.5, sound = "shout"}}},
    {anim = "osmond_volley", character = "osmond", id = "vigil_osmond_art_barrage", name = "Barrage",
      line = "Three quick bursts of fire.", weapons = span(364, 375),
      speed = 1.3, gauge = 40, cooldown = 30,
      hits = {{at = 0.23, shot = true, count = 4, spread = 10, damage = 0.9}, {at = 0.42, shot = true, count = 4, spread = 10, damage = 0.9},
              {at = 0.62, shot = true, count = 4, spread = 10, damage = 0.9}},
      cues = {{at = 0.05, sound = "shout"}}},
  }) do
    art.trigger = "art"
    ATTACKS.arts[#ATTACKS.arts + 1] = art
  end
end

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
    if k ~= "anim" and k ~= "ok" then move[k] = v end
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
    if setting("party_attacks", true) then
      for _, attack in ipairs(ATTACKS.party) do
        if attack.ok == nil then attack.ok = register(attack.anim) end
        if attack.ok then list[#list + 1] = attack_move(attack) end
      end
    end
    local c = ATTACKS.critical
    if setting("criticals", true) then
      if c.ok == nil then c.ok = register(c.anim) end
      if c.ok then
        for _, move in ipairs(c.moves) do
          move = attack_move(move)
          move.pairs = c.pairs
          list[#list + 1] = move
        end
      end
      if setting("party_attacks", true) then
        for _, crit in ipairs(ATTACKS.party_criticals) do
          if crit.ok == nil then crit.ok = register(crit.anim) end
          if crit.ok then
            local move = attack_move(crit)
            move.pairs = c.pairs
            list[#list + 1] = move
          end
        end
      end
    end
    if setting("arts", true) then
      for _, art in ipairs(ATTACKS.arts) do
        -- the party's arts play their Party attacks motions, so they come with them
        local party = art.character ~= nil and art.character ~= "toan"
        if party and art.ok == nil then art.ok = register(art.anim) end
        if not party or (art.ok and setting("party_attacks", true)) then
          local move = attack_move(art)
          move.name, move.line = nil, nil
          move.min_level = clamp(setting("art_level", 3), 1, 99)
          list[#list + 1] = move
        end
      end
    end
  end
  -- The flask's drink (Flask, below): each hero's own drinking motion, slowed, started only by player.move_play.
  if setting("flask", true) then
    for _, who in ipairs(ORDER) do
      list[#list + 1] = {id = "vigil_" .. who .. "_flask", character = who, trigger = "played", motion = 28, speed = 0.5,
                         blend_in = 4, cooldown = 0}
    end
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
  -- From here on the blow frames are the damage windows the monster's own script sets (SET_DMG_COL, read with
  -- tools/stb/stbdis.py), and the guard is its SET_GUARD_FRAME span.
  -- Master Jacket shares the Skeleton's motion layout: blows at 62-64 of attack_1 and 77-79 of attack_2 (75-95), so
  -- attack_2 lands at once and only follows a first blow. Guard frames 100-117.
  [0] = { -- Master Jacket (e01a)
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.35, sidestep = 0.5,
    guard = {up = 5, hold = 6, down = 7, chance = 0.4},
    walk_speed = 0.5, press_speed = 0.75, step_speed = 0.5, ring = 24, reach = 16, rush = 0.3, feint = 0.25,
    attacks = {
      {motion = 13, from = 50, speed = 0.42, hold = 60, track_to = 61, lunge = 0.5, done = 70, next = 2},
      {motion = 16, from = 75, speed = 0.42, hold = 75, track_to = 76, lunge = 0.4, done = 95, next = 1},
    },
  },
  -- The Werewolf: a hopping right swipe at 60-65 of attack_1 (50-70), the left claw at 80-81 of attack_2 (70-90).
  -- Guard frames 244-263 (motions 5-7).
  [4] = { -- the Werewolf (e07a)
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.5, sidestep = 0.5,
    guard = {up = 5, hold = 6, down = 7, chance = 0.35},
    walk_speed = 0.6, press_speed = 0.9, step_speed = 0.6, ring = 28, reach = 19, rush = 0.45, feint = 0.2,
    attacks = {
      {motion = 13, from = 50, speed = 0.36, hold = 57, track_to = 59, lunge = 0.6, done = 70, next = 2},
      {motion = 16, from = 70, speed = 0.36, hold = 76, track_to = 78, lunge = 0.4, done = 90, next = 1},
    },
  },
  -- The Mummy has the Skeleton's layout and guard (100-117); attack_1 (360-385) lands at 372, attack_2 (320-350) at 330.
  [44] = { -- the Mummy (e50a)
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.2, sidestep = 0.4,
    guard = {up = 5, hold = 6, down = 7, chance = 0.3},
    walk_speed = 0.4, press_speed = 0.6, step_speed = 0.4, ring = 24, reach = 16, rush = 0.15, feint = 0.1,
    attacks = {
      {motion = 13, from = 360, speed = 0.36, hold = 369, track_to = 371, lunge = 0.4, done = 385, next = 2},
      {motion = 16, from = 320, speed = 0.36, hold = 327, track_to = 329, lunge = 0.4, done = 350, next = 1},
    },
  },
  -- The Captain and Corcea: attack_1 (60-81) lands at 69, attack_2 (90-106) at 93. The Captain guards (180-190).
  [23] = { -- the Captain (e27a)
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.35, sidestep = 0.5,
    guard = {up = 5, hold = 6, down = 7, chance = 0.4},
    walk_speed = 0.5, press_speed = 0.75, step_speed = 0.5, ring = 24, reach = 16, rush = 0.3, feint = 0.2,
    attacks = {
      {motion = 13, from = 60, speed = 0.36, hold = 66, track_to = 68, lunge = 0.5, done = 81, next = 2},
      {motion = 16, from = 90, speed = 0.36, hold = 91, track_to = 92, lunge = 0.4, done = 106, next = 1},
    },
  },
  -- The Curse Dancer: quick on its feet. attack_1 (240-262) lands at 249, attack_2 (270-293) at 280; guard 160-174.
  [46] = { -- the Curse Dancer (e52a)
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.6, sidestep = 0.7,
    guard = {up = 5, hold = 6, down = 7, chance = 0.3},
    walk_speed = 0.55, press_speed = 0.85, step_speed = 0.6, ring = 26, reach = 17, rush = 0.35, feint = 0.3,
    attacks = {
      {motion = 13, from = 240, speed = 0.3, hold = 246, track_to = 248, lunge = 0.5, done = 262, next = 2},
      {motion = 16, from = 270, speed = 0.3, hold = 277, track_to = 279, lunge = 0.5, done = 293, next = 1},
    },
  },
  -- The days of the week (Sunday to Saturday) share one layout: attack_1 from 255, attack_2 from 280-290, which lands
  -- at once and so only follows a first blow. Sunday and Monday guard (120-137). Tuesday and Thursday shoot, Friday's
  -- swing is split over three motions: they keep their own scripts.
  [10] = { -- Sunday (e14a): lands at 262 and 285
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.35, sidestep = 0.5,
    guard = {up = 5, hold = 6, down = 7, chance = 0.4},
    walk_speed = 0.5, press_speed = 0.75, step_speed = 0.5, ring = 26, reach = 18, rush = 0.3, feint = 0.2,
    attacks = {
      {motion = 13, from = 255, speed = 0.36, hold = 259, track_to = 261, lunge = 0.5, done = 280, next = 2},
      {motion = 16, from = 285, speed = 0.36, hold = 285, track_to = 286, lunge = 0.4, done = 297, next = 1},
    },
  },
  [11] = { -- Monday (e15a): lands at 259 and 280
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.35, sidestep = 0.5,
    guard = {up = 5, hold = 6, down = 7, chance = 0.4},
    walk_speed = 0.5, press_speed = 0.75, step_speed = 0.5, ring = 26, reach = 18, rush = 0.3, feint = 0.2,
    attacks = {
      {motion = 13, from = 255, speed = 0.36, hold = 257, track_to = 258, lunge = 0.5, done = 270, next = 2},
      {motion = 16, from = 280, speed = 0.36, hold = 280, track_to = 281, lunge = 0.4, done = 292, next = 1},
    },
  },
  [13] = { -- Wednesday (e17a): one blow, at 267
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.4, sidestep = 0.5,
    walk_speed = 0.5, press_speed = 0.75, step_speed = 0.5, ring = 26, reach = 18, rush = 0.3, feint = 0.25,
    attacks = {
      {motion = 13, from = 255, speed = 0.36, hold = 264, track_to = 266, lunge = 0.5, done = 280},
    },
  },
  [16] = { -- Saturday (e20a): lands at 265 (both hands) and 290
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.4, sidestep = 0.5,
    walk_speed = 0.5, press_speed = 0.75, step_speed = 0.5, ring = 26, reach = 18, rush = 0.35, feint = 0.2,
    attacks = {
      {motion = 13, from = 255, speed = 0.36, hold = 262, track_to = 264, lunge = 0.5, done = 280, next = 2},
      {motion = 16, from = 290, speed = 0.36, hold = 290, track_to = 291, lunge = 0.4, done = 302, next = 1},
    },
  },
  -- The card soldiers (Club, Diamond, Spade, Joker; the Heart shoots, so keeps its script): one swing over 270-305
  -- and a guard over 120-142, on the days' layout.
  [39] = { -- Club (e45a): lands at 284
    idle = 0, walk = 1, back = 2, right = 3, left = 4, dodge_chance = 0.35, sidestep = 0.5,
    guard = {up = 5, hold = 6, down = 7, chance = 0.45},
    walk_speed = 0.5, press_speed = 0.75, step_speed = 0.5, ring = 26, reach = 18, rush = 0.3, feint = 0.2,
    attacks = {{motion = 13, from = 270, speed = 0.36, hold = 281, track_to = 283, lunge = 0.5, done = 305}},
  },
}

do -- Families that fight like another: a copy of its row (attacks too: the brain adds a family's own motions to them)
  -- with its own numbers over it.
  local function like(model, over)
    local t = {}
    for k, v in pairs(BRAINS[model]) do t[k] = v end
    t.attacks = {}
    for n, a in ipairs(BRAINS[model].attacks) do
      t.attacks[n] = {}
      for k, v in pairs(a) do t.attacks[n][k] = v end
    end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
  end
  local function landing(row, n, at) -- attack n's blow moved to frame at
    local a = row.attacks[n]
    a.hold, a.track_to = at - 3, at - 1
    return row
  end
  BRAINS[55] = like(3, {walk_speed = 0.65, press_speed = 0.95, rush = 0.5}) -- the Rash Dasher (e63a): the Dasher's rig
  -- White Fang (e56a): the Werewolf's layout; blows at 62-64 and 80-84, guard 240-265
  BRAINS[48] = landing(landing(like(4, {dodge_chance = 0.55, rush = 0.5}), 1, 62), 2, 80)
  BRAINS[24] = like(23, {guard = false}) -- Corcea (e28a): the Captain's layout, no guard
  BRAINS[54] = landing(like(16), 1, 264) -- Hell Pockle (e62a): Saturday's layout, lands at 264 and 290
  BRAINS[40] = landing(like(39), 1, 283)                          -- Diamond (e46a)
  BRAINS[41] = landing(like(39, {reach = 20}), 1, 281)            -- Spade (e47a): the longest reach
  BRAINS[42] = landing(like(39, {feint = 0.35}), 1, 280)          -- Joker (e48a)
end

local hook_frame = 0 -- the monster hook's latest frame

-- Each monster's own new motions (tools/anim/vigil_monster_moves.py), appended to its native model by
-- animations.monster_register: a sideways roll each way, and a new attack. The attack's frames are its own, counted
-- from its first; its hits take the kind of the monster's first native blow, times damage.
local MONSTER_MOVES = {
  [3] = { -- the Dasher's pounce: the mace up by 6, a leap, the mace slammed down in front on landing (16)
    roll_left = "e06a_roll_left", roll_right = "e06a_roll_right", roll_chance = 0.6, crumple = "e06a_crumple",
    attack = {id = "e06a_pounce", speed = 0.45, hold = 5, track_to = 7, lunge = 1.3, chance = 0.3,
              -- the mace's head lands 21 out and the hand 13: one sphere each, so it catches you close or far
              hits = {{bone = "dcol0", radius = 5, from = 14, to = 22, damage = 1.2},
                      {bone = "r_hand", radius = 5, from = 15, to = 22, damage = 1.2}}},
  },
  [1] = { -- the Skeleton's whirl: the knife drawn back by 7, one full turn with the blade out (10-24)
    roll_left = "e03a_roll_left", roll_right = "e03a_roll_right", roll_chance = 0.4, crumple = "e03a_crumple",
    attack = {id = "e03a_whirl", speed = 0.4, hold = 6, track_to = 9, lunge = 0.45, chance = 0.3,
              hits = {{bone = "dcol0", radius = 5, from = 12, to = 24, damage = 1.0},
                      {bone = "hand_r", radius = 4, from = 12, to = 24, damage = 1.0}}},
  },
  [55] = { -- the Rash Dasher: the Dasher's moves on its own file (the same rig)
    roll_left = "e63a_roll_left", roll_right = "e63a_roll_right", roll_chance = 0.6,
    attack = {id = "e63a_pounce", speed = 0.5, hold = 5, track_to = 7, lunge = 1.4, chance = 0.35,
              hits = {{bone = "dcol0", radius = 5, from = 14, to = 22, damage = 1.2},
                      {bone = "r_hand", radius = 5, from = 15, to = 22, damage = 1.2}}},
  },
  [4] = { -- the Werewolf's rake: a long leap, the right claw raked down on landing (16), then the left across (25)
    roll_left = "e07a_roll_left", roll_right = "e07a_roll_right", roll_chance = 0.5,
    attack = {id = "e07a_rake", speed = 0.42, hold = 5, track_to = 9, lunge = 1.4, chance = 0.3,
              hits = {{bone = "r_hand", radius = 6, from = 14, to = 18, damage = 1.1},
                      {bone = "l_hand", radius = 6, from = 23, to = 27, damage = 0.9}}},
  },
}

-- A crumple is the enemy's half of a critical: doubled over from the blade and back up, 44 frames at half speed.
for model, m in pairs(MONSTER_MOVES) do
  if m.crumple then ATTACKS.critical.pairs[#ATTACKS.critical.pairs + 1] = {model = model, animation = m.crumple, speed = 0.5} end
end
table.sort(ATTACKS.critical.pairs, function(a, b) return a.model < b.model end)

local monster_moves_registered = false
local function register_monster_moves()
  if monster_moves_registered then return end
  monster_moves_registered = true
  for model, m in pairs(MONSTER_MOVES) do
    for _, id in ipairs({m.roll_left, m.roll_right, m.crumple}) do
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
local brain_on, brain_hooked = false, false

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
  mind.attack, mind.lunged, mind.flashed, mind.caught, mind.cued = n, false, false, false, false
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

  -- A named elite on patrol (Named elites, below, sets mind.beat): until you come near, it walks its beat, turning
  -- back at a wall.
  if mind.beat and dist > 420 and mind.state ~= "attack" then
    mind.leg = mind.leg or 1
    local goal = mind.beat[mind.leg]
    if (me[1] - goal[1]) ^ 2 + (me[3] - goal[3]) ^ 2 < 144 or mind.blocked > 30 then
      mind.leg, mind.blocked = mind.leg % #mind.beat + 1, 0
      goal = mind.beat[mind.leg]
    end
    face(e, goal, 0.2)
    play(e, mind, kind.walk)
    go(e, goal, kind.walk_speed)
    mind.walking = true
    return
  end

  -- A family that shoots (Ranged and casting enemies, below) keeps its distance and fires.
  if kind.ranged then return kind.ranged.think(ctx, kind, mind, me, you, dist, ux, uz, dt) end

  if mind.state == "attack" then
    local a = kind.attacks[mind.attack]
    local o = native(e, "CHK_MOTION_FRM", {I, F}) or {}
    -- The new motion shows up a frame or two late; until it does, the reading is the old one's.
    local started = mind.t > 4 and o[2] ~= nil and o[2] >= a.from and o[2] <= a.done
    local done, frame = started and o[1] == 1, started and o[2] or a.from
    if frame < a.track_to then face(e, you, 0.2) end
    -- The telegraph (§13, item 4): a string's opening blow glints at the top of its wind-up, a beat before it lands,
    -- with a soft ping. The family's own new attack (the whirl, the pounce, the rake) flashes red with a crack instead:
    -- a blow to roll from, not to trade with. Blows later in a string come without one.
    if not mind.cued and started and mind.chain == 1 and frame >= math.max(a.from + 1, a.hold - 5) then
      mind.cued = true
      if setting("telegraphs", true) then
        local red = kind.special ~= nil and mind.attack == kind.special.n
        try(game.effects.burst, {kind = "guard", position = {x = me[1] + ux * 10, y = me[2] + 22, z = me[3] + uz * 10},
                                 scale = red and 1.3 or 0.7})
        try(game.audio and game.audio.se_play, {se = red and 616 or 370, volume = red and 100 or 64})
        if red then native(e, "STATUS_SET_PALLET", {255, 40, 40, 1, 0.12}) end
      end
    end
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

local poise_hit -- Poise, below: true while the hit monster's poise holds and it shrugs the blow off

local function brain_hook(ctx)
  if type(ctx) == "table" and ctx.frame then hook_frame = ctx.frame end
  -- A hit inside the monster's poise skips the retail flinch: it carries on with what it was doing.
  if type(ctx) == "table" and ctx.program_no == 110 and poise_hit and poise_hit(ctx.entity) then return {handled = true} end
  -- A story boss playing a move of its own (Story bosses, below) is held off its script, a hit's flinch too, until
  -- the move is done.
  local held = type(ctx) == "table" and minds[ctx.entity]
  if held and held.boss_until and ctx.program_no ~= 120 then
    if hook_frame < held.boss_until then return {handled = true} end
    minds[ctx.entity] = nil
  end
  local kind = brain_on and type(ctx) == "table" and kind_of(ctx.entity)
  if kind and kind.ranged and not setting("shooters", true) then kind = false end
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

-- The hook serves the brain and Poise; it stays while either wants it (hook: Poise wants it).
local function set_brain(on, hook)
  hook = on or hook == true
  if on == brain_on and hook == (brain_on or brain_hooked) then return true end
  minds, kinds, turn = {}, {}, nil
  local scripts = type(game.scripts) == "table" and game.scripts or {}
  if on then register_monster_moves() end
  if hook then
    local ok, err = call(scripts.override, {id = "native.monster.run"}, brain_hook)
    if not ok then moonmod.log("warn", "enemy brain: " .. message(err)) brain_hooked = false return false end
  else
    try(scripts.override, {id = "native.monster.run", enabled = false})
  end
  brain_on, brain_hooked = on, hook
  return true
end

-- Applying the rules ----------------------------------------------------------------------------------------------
local in_sandbox = false

-- Poise (§12, stretch goal 2): a monster shrugs off the first blows of a flurry instead of flinching at each, so it
-- can trade with you; the blow past its poise breaks it into the retail flinch and a short stagger. Poise comes back
-- after two seconds without a hit. A heavy blow or a combo finisher breaks it at once.
do
  local poise, heavy_until = {}, -1
  local HEAVY = {vigil_toan_heavy = true, vigil_toan_finisher_2 = true, vigil_toan_finisher_3 = true}

  poise_hit = function(entity)
    local need = setting("poise", 2)
    if in_sandbox or need <= 0 or entity == nil then return false end
    local p = poise[entity]
    if not p or hook_frame - p.last > 120 then p = {hits = 0}; poise[entity] = p end
    p.last = hook_frame
    p.hits = (hook_frame <= heavy_until) and need + 1 or p.hits + 1
    -- The target bar's meter fills with each blow it shrugs off, and flashes full through the stagger.
    local meter = setting("target_bar", true) and game.render and game.render.target_meter_set
    local stagger = setting("stagger", 40)
    if p.hits <= need then
      try(meter, {entity = entity, fill = p.hits / (need + 1), seconds = 2})
      return true
    end
    try(meter, {entity = entity, fill = 1, seconds = stagger / 60 + 0.5})
    poise[entity] = nil
    if stagger > 0 then try(game.combat.status_add, {entity = entity, status = "stop", duration_frames = stagger}) end
    -- Open to a critical while it reels, and a moment after.
    if setting("criticals", true) then try(game.player.critical_set, {entity = entity, frames = stagger + 30}) end
    return false
  end

  moonmod.on("game.player.move", function(e)
    if type(e) == "table" and HEAVY[e.id] then heavy_until = hook_frame + 60 end
  end)
  moonmod.on("game.world.location_changed", function() poise = {} end)
end
local guarding = false
local applied = {} -- what the last apply() asked for, for the Mod Manager's "Check" action
local TREE = {vigour = 0, endurance = 0, guard = 0} -- the shrine tree's ranks in this save (Levelling, below)

-- Stamina (§11 G3): each character's own gauge refill, a second, in place of the weapon's Speed. They start where the
-- game has them with their first weapon (Speed / 30 a tick, times a quarter for Toan and Ungaga and half again for
-- Xiao and Ruby): Toan and Ungaga slow, Xiao and Ruby quick. The shrine tree's Endurance and the refill setting
-- scale them, as gauge_refill.
local STAMINA = {toan = 35, xiao = 120, goro = 60, ruby = 180, ungaga = 30, osmond = 80}

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
  -- Hold L2 to run (§11 G2): the dash speed, draining the gauge; a tap evades as it is let go. Dran's Feather in the
  -- charm slot halves the drain. 0 leaves L2 as a press-to-evade.
  local run = setting("run_cost", 20)
  if run > 0 then t.dodge_run = run end
  -- Lightness (§11 G3): the weapon's Speed no longer sets the refill; it scales what a swing costs, a light weapon
  -- down to half, a heavy one up to double. Evades cost what they say.
  if setting("lightness", true) then
    t.lightness = true
    t.stamina = STAMINA
  end
  if setting("evades", true) then
    -- A hero without a roll of his own (his evade motions missing) still dodges on L2: the engine's shove dodge with a hop, untouchable for a moment, for the gauge a roll
    -- costs (refused with less). A hero with a roll never gets it, so his refused roll stays refused.
    t.dodge_power = 1
    t.dodge_invincible_frames = 14
    local cost = clamp(setting("evade_cost", 35), 0, 100)
    if cost > 0 then t.dodge_gauge = math.floor(cost) end
    if animated ~= false then t.dodge_hop = true end
  end
  -- No healing items with an enemy near: the flask (below) is the heal in a fight.
  local lock = setting("flask", true) and clamp(setting("heal_lock", 240), 0, 400) or 0
  if lock > 0 then t.item_heal_lock = lock end
  -- Lock-on (§12, stretch goal 6): flick the right stick to move the lock, lose it behind a wall, and a soft turn of
  -- a swing toward the nearest enemy ahead when not locked.
  if setting("lock_flick", true) then t.lock_flick = true end
  if setting("lock_sight", true) then t.lock_sight = true end
  local soft = clamp(setting("soft_lock", 35), 0, 90)
  if soft > 0 then t.soft_lock = soft end
  -- Input buffering (§13, item 2): a roll or R2 pressed a little early (late in a swing, mid-roll, in a hit-stop)
  -- comes out at the first step it can instead of being lost.
  local buffer = clamp(setting("input_buffer", 12), 0, 20)
  if buffer > 0 then t.input_buffer = math.floor(buffer) end
  -- Chaining (§13, item 2): R2 in a swing's recovery, its blow landed, cuts into the heavy; attack in a heavy's
  -- recovery cuts back into the combo.
  if setting("chain_cancel", true) then t.chain_cancel = 6 end
  -- The lock-on camera (§13, item 6) keeps the target framed beyond you instead of letting it drift to the edge.
  if setting("lock_camera", true) then t.lock_camera = true end
  return t
end

local function apply_tuning()
  local t = tuning()
  local ok, err = call(game.player.tuning_set, t)
  if not ok then moonmod.log("warn", "tuning: " .. message(err)) end
  applied.tuning = t
end

-- The guard and the gauge (E1, E2): a guard that covers only the front, costs gauge for each blocked hit, lets some
-- damage through and breaks when the gauge can't pay; a parry in the first frames of the guard; guarding without a
-- lock-on. A hit that lands drains the gauge instead of filling it, the first swing costs and needs gauge, and the
-- refill waits a moment after any spend.
local function apply_rules()
  if setting("guard_rules", true) then
    local rules = {
      arc = clamp(setting("guard_arc", 120), 0, 360),
      cost_base = clamp(setting("guard_cost", 10), 0, 100),
      cost_per_damage = clamp(setting("guard_cost_per_damage", 150) / 100, 0, 10),
      chip = clamp(setting("guard_chip", 15) / 100, 0, 1),
      break_recoil = 120,
      parry_frames = clamp(setting("parry_frames", 6), 0, 60),
      without_lock = setting("guard_without_lock", true),
    }
    local ok, err = call(game.player.guard_rules_set, rules)
    applied.guard_rules = ok and "on" or ("refused: " .. message(err))
  else
    try(game.player.guard_rules_clear)
    applied.guard_rules = "off"
  end
  if setting("gauge_rules", true) then
    local rules = {
      hit_refill = -clamp(setting("hit_drain", 15), 0, 100),
      first_swing_cost = clamp(setting("first_swing_cost", 25), 0, 100),
      min_to_swing = clamp(setting("min_to_swing", 10), 0, 100),
      refill_delay = clamp(setting("refill_delay", 36), 0, 600),
    }
    local ok, err = call(game.player.gauge_rules_set, rules)
    applied.gauge_rules = ok and "on" or ("refused: " .. message(err))
  else
    try(game.player.gauge_rules_clear)
    applied.gauge_rules = "off"
  end
end

local arm_riposte, end_moments -- the riposte and Exhausted, below (they need in_dungeon)

-- A parry stops the attacker for a moment and shoves it back, a guard break throws sparks. The Counter (guard +
-- attack) is the riposte that follows.
moonmod.on("game.player.hit", function(e)
  if in_sandbox or type(e) ~= "table" or not (e.parried or e.broke) then return end
  local p = try(game.player.get)
  local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
  if at then
    try(game.effects.burst, {kind = e.parried and "guard" or "sparks", position = {x = at.x, y = (at.y or 0) + 10, z = at.z},
                             scale = e.parried and 1.5 or 1})
  end
  if not (e.parried and e.entity) then return end
  try(game.combat.status_add, {entity = e.entity, status = "stop", duration_frames = 90})
  local m = try(game.entities.get, e.entity)
  local from = type(m) == "table" and type(m.position) == "table" and m.position or nil
  if at and from then
    try(game.entities.knockback, {entity = e.entity, direction = {x = from.x - at.x, z = from.z - at.z}, speed = 6})
  end
  arm_riposte(e.entity, type(m) == "table" and m.native_model_id or nil)
  if setting("criticals", true) then try(game.player.critical_set, {entity = e.entity, frames = 120}) end
end)


local function apply()
  if in_sandbox then return end
  local ok, err = call(game.combat.register_player_formula,
    {id = "enemy-damage", operation = "multiply", value = setting("enemy_damage", 250) / 100})
  if not ok then moonmod.log("warn", "enemy damage formula: " .. message(err)) end
  applied.enemy_damage = setting("enemy_damage", 250) / 100

  local evades = setting("evades", true) and register_motions()
  local attacks = setting("toan_attacks", true) and register_attacks()
  if evades or attacks or setting("flask", true) then
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
  applied.enemy_brain = (set_brain(brain, setting("poise", 2) > 0) and brain) and "on" or (brain and "refused" or "off")

  -- The charm slot, beside the shield on the item page: an amulet there guards against its ailment without taking a
  -- quick slot. While L2 runs, Dran's Feather has a slot of its own after it, to lighten the run.
  local charms = setting("charm_slot", true) and 1 or 0
  local feather = setting("run_cost", 20) > 0
  local charmed, charm_err = call(game.items.charm_slots_set, {count = charms, feather = feather})
  applied.charm_slot = charmed and (charms > 0 and "on" or "off") or ("refused: " .. message(charm_err))
  applied.feather_slot = charmed and feather

  -- Hit feel (§13, item 1): a landed blow holds the whole floor still for a few frames (more for a heavy or charged one,
  -- most for a critical), the camera shakes on heavy blows and hurts, and the pad rumbles.
  if setting("hit_feel", true) then
    local feel = call(game.combat.feel_set, {hit_stop = {light = 3, heavy = 6, critical = 10, hurt = 5},
                                              shake = {light = 0, heavy = 3, hurt = 4}, rumble = true})
    applied.hit_feel = feel and "on" or "refused"
  else
    try(game.combat.feel_clear)
    applied.hit_feel = "off"
  end

  bind_guard()
  guarding = guard_held()
  apply_tuning()
  apply_rules()
end

local function stand_down()
  try(game.player.moves_clear)
  try(game.player.tuning_clear)
  try(game.player.guard_rules_clear)
  try(game.player.gauge_rules_clear)
  try(game.combat.feel_clear)
  end_moments()
  set_brain(false)
  try(game.combat.register_player_formula, {id = "enemy-damage", operation = "multiply", value = 1})
  try(game.items.charm_slots_set, {count = 0}) -- a charm already in it stays shown, so it can be taken out
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
  if setting("run_cost", 20) > 0 then
    toast("Vigil: tap L2 to roll, or backstep with the stick at rest; hold it to run. Both cost weapon gauge.")
  else
    toast("Vigil: L2 rolls, or backsteps with the stick at rest. Each costs weapon gauge.")
  end
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
  return not in_sandbox and not floors.trial and type(e) == "table" and not e.back_floor and type(e.dungeon_id) == "number" and
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

local PLACE_LISTS = {"", ":chests", ":back", ":gates", ":shrines", ":map", ":waypoint", ":shape", ":doors", ":walls"}
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
    -- Height steps: each zone lies a step below the one before, down a ramp outside its gate.
    if setting("height_steps", true) then request.descent = 40 end
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

-- Set further down (the main chunk is at Lua's 200-local cap, so they share one): flask_refill, the flask full again
-- (Flask); cycle_now and next_cycle, the save's cycle and beginning the next (NG+); elite_gear, a named elite's drop.
local later = {}
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
  if later.flask_refill then later.flask_refill() end
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

level_now = function()
  local n = 0
  for _, r in pairs(TREE) do if math.type(r) == "integer" then n = n + r end end
  return n
end
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
  if later.load_sky then later.load_sky() end -- the Vigil sky's other nodes (below)
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
  if later.apply_sky then later.apply_sky() end
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
  if setting("vigil_sky", true) and later.sky_open and later.sky_open() then return end
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

-- The Vigil sky (VIGIL_PLAN §14, X2), the Gauntlet's Norune Eternal in Vigil's shape: the shrine tree's three skills
-- are three constellations' trunks (a save keeps their ranks), and around them Arms, Fortune and Flask. A node needs
-- the one it hangs from; each rank costs a level's Gilda (the curve above), and a Keystone also takes Embers, which
-- named elites (1), story bosses (2) and each new cycle (3) leave. It opens at a shrine's Level up card
-- (ui.sky_open over the paused dungeon); an engine without it shows the shrine tree on the Journal instead.
do
  local function rgb(r, g, b) return {r, g, b} end
  local GROUPS = {
    {id = "flame", name = "The Shrine Flame", colour = rgb(255, 240, 190), x = 0, y = 0},
    {id = "vigour", name = "Vigour", colour = rgb(236, 110, 110), x = 0, y = -430},
    {id = "endurance", name = "Endurance", colour = rgb(244, 200, 90), x = 380, y = -210},
    {id = "guard", name = "Guard", colour = rgb(150, 190, 236), x = 380, y = 230},
    {id = "arms", name = "Arms", colour = rgb(248, 206, 92), x = 0, y = 440},
    {id = "fortune", name = "Fortune", colour = rgb(196, 160, 255), x = -380, y = 230},
    {id = "flask", name = "Flask", colour = rgb(120, 220, 200), x = -380, y = -210},
  }
  local GROUP = {}
  for _, g in ipairs(GROUPS) do GROUP[g.id] = g end
  -- {id, group, title, ranks, text, needs, icon, dx, dy (from the constellation's centre), embers (a Keystone's)}
  local NODES = {
    {id = "vigour", group = "vigour", title = "Vigour", ranks = 20, text = "+5 max HP for everyone in the party per rank.",
     icon = "heart", dx = 0, dy = 60},
    {id = "endurance", group = "endurance", title = "Endurance", ranks = 10, text = "The action gauge refills 10% faster per rank.",
     icon = "stamina", dx = -40, dy = 30},
    {id = "guard", group = "guard", title = "Guard", ranks = 10, text = "Holding the guard slows the gauge's refill less (5 points a rank).",
     icon = "shield", dx = -40, dy = -30},
    {id = "keen", group = "arms", title = "Keen Edge", ranks = 5, text = "+4% damage per rank.", icon = "sword", dx = 0, dy = -70},
    {id = "heavy_hand", group = "arms", title = "Heavy Hand", ranks = 3, needs = "keen", text = "Charged blows land 10% harder per rank.",
     icon = "sword", dx = -90, dy = 10},
    {id = "bloodletter", group = "arms", title = "Bloodletter", ranks = 1, needs = "keen", embers = 2, icon = "heart", dx = 90, dy = 10,
     text = "Keystone. Every blow heals you 3% of the damage it deals."},
    {id = "last_light", group = "arms", title = "Last Light", ranks = 1, needs = "heavy_hand", embers = 3, icon = "curse", dx = -40, dy = 100,
     text = "Keystone. Under a quarter of your HP, your blows land 30% harder."},
    {id = "keen_eye", group = "fortune", title = "Keen Eye", ranks = 3, text = "Found weapons roll as if a dungeon deeper per rank.",
     icon = "crystal", dx = 50, dy = -50},
    {id = "gilded_path", group = "fortune", title = "Gilded Path", ranks = 3, needs = "keen_eye", text = "Each kill drops Gilda, more per rank and deeper in.",
     icon = "crystal", dx = -60, dy = -10},
    {id = "fortunes_favour", group = "fortune", title = "Fortune's Favour", ranks = 1, needs = "keen_eye", embers = 2, icon = "map", dx = 40, dy = 70,
     text = "Keystone. Every named elite leaves a weapon, Rare or better."},
    {id = "deep_flask", group = "flask", title = "Deep Flask", ranks = 3, text = "+1 flask charge per rank.", icon = "flask", dx = 50, dy = 50},
    {id = "healing_draught", group = "flask", title = "Healing Draught", ranks = 3, needs = "deep_flask", text = "A drink heals 10% more of your HP per rank.",
     icon = "drop", dx = -50, dy = 0},
  }
  local NODE = {}
  for _, n in ipairs(NODES) do NODE[n.id] = n end
  later.SKY_NODES = NODES

  local function seeds_tree()
    local seeds = floor_seeds()
    if type(seeds.tree) ~= "table" then seeds.tree = {} end
    return seeds.tree, seeds
  end
  later.sky_rank = function(id)
    local r = TREE[id]
    return math.type(r) == "integer" and r or 0
  end
  later.embers = function()
    local e = floor_seeds().embers
    return math.type(e) == "integer" and e or 0
  end
  later.give_embers = function(n, why)
    if in_sandbox or not setting("vigil_sky", true) then return end
    local seeds = floor_seeds()
    seeds.embers = later.embers() + n
    if floors.key then try(game.save.set, floors.key, seeds) end
    toast(string.format("Vigil: %s left %d Ember%s (%d).", why, n, n == 1 and "" or "s", seeds.embers), 240)
  end
  -- The ranks of the sky's own nodes, from the save (the three trunks are read with the shrine tree).
  later.load_sky = function()
    local t = seeds_tree()
    for _, n in ipairs(NODES) do
      if not (n.id == "vigour" or n.id == "endurance" or n.id == "guard") then
        local r = t[n.id]
        TREE[n.id] = math.type(r) == "integer" and math.max(0, math.min(n.ranks, r)) or 0
      end
    end
  end

  local function open_to(n)
    return not n.needs or later.sky_rank(n.needs) > 0
  end
  local function page()
    local gilda = try(game.economy.get)
    local purse = type(gilda) == "table" and gilda.amount or 0
    local groups, nodes = {}, {}
    for _, g in ipairs(GROUPS) do groups[#groups + 1] = {id = g.id, name = g.name, colour = g.colour, x = g.x, y = g.y} end
    nodes[1] = {id = "flame", group = "flame", x = 0, y = 0, label = "The Shrine Flame", title = "The Shrine Flame", state = "owned",
                icon = "crystal", text = "Gilda buys levels here, each dearer than the last. Keystones also take Embers, from elites, bosses and cycles."}
    for _, n in ipairs(NODES) do
      local g = GROUP[n.group]
      local r = later.sky_rank(n.id)
      local state = r > 0 and "owned" or (open_to(n) and "open" or "locked")
      local cost = r >= n.ranks and "Most" or string.format("%d G%s", level_cost(), n.embers and string.format(" + %d Embers", n.embers) or "")
      nodes[#nodes + 1] = {id = n.id, group = n.group, x = g.x + n.dx, y = g.y + n.dy, label = n.title, title = n.title,
                           rank = n.ranks > 1 and string.format("%d/%d", r, n.ranks) or nil, icon = n.icon, text = n.text,
                           tag = g.name, cost = cost, state = state, keystone = n.embers ~= nil,
                           needs = n.needs and ("Needs " .. NODE[n.needs].title .. ".") or nil,
                           links = {n.needs or "flame"}}
    end
    return {groups = groups, nodes = nodes,
            top = {string.format("Level %d", level_now()), string.format("Gilda %d", purse), string.format("Embers %d", later.embers())}}
  end
  later.sky_open = function()
    if not (game.ui and game.ui.sky_open) then return false end
    local ok = call(game.ui.sky_open, {id = "vigil_sky", title = "VIGIL SKY", sky = page(),
      hint = "{dpad} Move  {L2}{R2} Sky  {cross} Level up  {triangle} Map  {circle} Back"})
    return ok ~= nil
  end

  -- Cross on a node: one rank more, at a shrine, for a level's Gilda (and a Keystone's Embers).
  moonmod.on("ui.sky_selected", function(e)
    if in_sandbox or type(e) ~= "table" or e.id ~= "vigil_sky" or e.action ~= "buy" then return end
    local n = NODE[e.entry]
    if not n then return end
    load_tree()
    local r = later.sky_rank(n.id)
    if r >= n.ranks then toast("Vigil: " .. n.title .. " is at its most.", 200)
    elseif not open_to(n) then toast("Vigil: " .. n.title .. " needs " .. NODE[n.needs].title .. " first.", 200)
    elseif not at_shrine() then toast("Vigil: you can level up only at a shrine.", 240)
    elseif n.embers and later.embers() < n.embers then toast(string.format("Vigil: %s takes %d Embers.", n.title, n.embers), 240)
    else
      local cost = level_cost()
      if not call(game.economy.spend, {amount = cost}) then
        toast(string.format("Vigil: the next level costs %d Gilda.", cost), 240)
      else
        local t, seeds = seeds_tree()
        t[n.id] = r + 1
        if n.embers then seeds.embers = later.embers() - n.embers end
        if floors.key then try(game.save.set, floors.key, seeds) end
        load_tree()
        if n.id == "vigour" then heal_party() end
        toast(string.format("Vigil: %s %d. Level %d.", n.title, r + 1, level_now()), 200)
      end
    end
    later.sky_open()
  end)

  -- What the nodes do -----------------------------------------------------------------------------------------------
  local last_light = false
  later.apply_sky = function()
    if in_sandbox then return end
    try(game.combat.register_formula, {id = "sky_keen", operation = "multiply", value = 1 + 0.04 * later.sky_rank("keen")})
    try(game.combat.register_formula, {id = "sky_heavy", operation = "multiply", value = 1 + 0.1 * later.sky_rank("heavy_hand"), charged = true})
  end
  moonmod.on("game.enemy_hit", function(e)
    if in_sandbox or type(e) ~= "table" or later.sky_rank("bloodletter") == 0 then return end
    local damage = tonumber(e.damage) or 0
    if damage > 0 then try(game.player.heal, {amount = math.max(1, math.floor(damage * 0.03 + 0.5))}) end
  end)
  moonmod.on("game.enemy_defeated", function(e)
    if in_sandbox or type(e) ~= "table" or e.attacker == nil then return end
    local r = later.sky_rank("gilded_path")
    local d = floor_now and tonumber(floor_now.dungeon_id) or 0
    if r > 0 then try(game.economy.add, {amount = math.random(2, 4) * r * (1 + d)}) end
  end)
  local BOSSES = {[78] = "Dran", [79] = "Master Utan", [80] = "The Ice Queen", [81] = "The King's Curse", [83] = "Minotaur Joe",
                  [84] = "The Dark Genie", [106] = "The Dark Genie"}
  moonmod.on("game.enemy_defeated", function(e)
    if in_sandbox or type(e) ~= "table" or not BOSSES[e.native_model_id] then return end
    local seeds = floor_seeds()
    local key = string.format("ember_boss:%d:%d", e.native_model_id, later.cycle_now and later.cycle_now() or 0)
    if seeds[key] then return end
    seeds[key] = true
    later.give_embers(2, BOSSES[e.native_model_id])
  end)

  local ticks, stood = 0, false
  moonmod.on("game.tick", function()
    ticks = ticks + 1
    if ticks % 15 ~= 0 then return end
    -- Another mod's run (a Gauntlet run): the sky's formulas stand down, and come back after.
    if in_sandbox ~= stood then
      stood = in_sandbox
      for _, id in ipairs({"sky_keen", "sky_heavy", "sky_last_light"}) do
        try(game.combat.register_formula, {id = id, operation = "multiply", value = 1, charged = id == "sky_heavy" or nil})
      end
      last_light = false
      if not stood then later.apply_sky() end
    end
    if in_sandbox then return end
    local on = false
    if in_dungeon and later.sky_rank("last_light") > 0 then
      local p = try(game.player.get)
      on = type(p) == "table" and tonumber(p.hp) and tonumber(p.max_hp) and p.hp > 0 and p.hp < p.max_hp * 0.25 or false
    end
    if on ~= last_light then
      last_light = on
      try(game.combat.register_formula, {id = "sky_last_light", operation = "multiply", value = on and 1.3 or 1})
      if on then toast("Vigil: Last Light.", 90) end
    end
  end)
end

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
  -- NG+ (below): with a cycle ready, Leave asks whether to leave or begin it (a panel holds four cards).
  if floor_seeds().cycle_ready then options[3].lines[2] = {text = "Or begin the next cycle.", tone = "gold"} end
  -- Messages (below): a fifth card, while they're on.
  local card = later.messages_card and later.messages_card()
  if card then options[#options + 1] = card end
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

-- The riposte and Exhausted (§3) are damage formulas Vigil keeps at x1 and raises for a moment. A formula can't name
-- one enemy, so the riposte names the parried enemy's kind and is spent on the first blow that lands on it.
do
  local riposte = nil   -- {entity, until_tick} while the riposte is armed
  local exhausted = nil -- the tick Exhausted ends, while it lasts
  local ticks = 0

  local function formula(id, value, model)
    local def = {id = id, operation = "multiply", value = value}
    if value ~= 1 and math.type(model) == "integer" then def.native_model_id = model end
    try(game.combat.register_formula, def)
  end

  arm_riposte = function(entity, model)
    local value = setting("riposte", 300) / 100
    if value == 1 then return end
    riposte = {entity = entity, until_tick = ticks + 120}
    formula("riposte", value, model)
  end

  local function end_riposte()
    if riposte then riposte = nil; formula("riposte", 1) end
  end

  local function end_exhausted()
    if exhausted then
      exhausted = nil
      formula("exhausted", 1)
      try(game.render.hud_icon_remove, {id = "exhausted"})
    end
  end

  moonmod.on("game.enemy_hit", function(e)
    if riposte and type(e) == "table" and e.entity == riposte.entity then end_riposte() end
  end)

  -- A critical (Criticals, above): its blows land at x critical on the enemy's kind for as long as it is held, in
  -- place of the riposte's.
  local critical = nil -- the tick the critical's formula ends, while it lasts
  local function end_critical()
    if critical then critical = nil; formula("critical", 1) end
  end
  moonmod.on("game.player.critical", function(e)
    if in_sandbox or type(e) ~= "table" or type(e.id) ~= "string" or e.id:sub(1, 11) ~= "vigil_toan_" then return end
    end_riposte()
    local value = setting("critical", 300) / 100
    if value == 1 then return end
    critical = ticks + (math.type(e.hold) == "integer" and e.hold or 90)
    formula("critical", value, e.native_model_id)
  end)

  moonmod.on("game.tick", function()
    ticks = ticks + 1
    if riposte and ticks >= riposte.until_tick then end_riposte() end
    if exhausted and ticks >= exhausted then end_exhausted() end
    if critical and ticks >= critical then end_critical() end
    if in_sandbox or not in_dungeon or exhausted or setting("exhausted", 30) >= 100 then return end
    local g = try(game.player.gauge_get)
    if type(g) ~= "table" or type(g.gauge) ~= "number" or g.gauge >= 0.5 then return end
    exhausted = ticks + 90
    formula("exhausted", setting("exhausted", 30) / 100)
    try(game.render.hud_icon_set, {id = "exhausted", icon = "stamina", blink = true})
  end)

  end_moments = function() end_riposte(); end_exhausted(); end_critical(); try(game.player.critical_clear) end
end

-- The flask (§12, stretch goal 5): healing as a decision. D-pad Down (or the Flask key) drinks, each hero with their
-- own drinking motion played slowly; it heals a share of max HP late in the drink, and a hit that gets through first
-- spills it, the charge spent. Charges come back at a shrine's rest and in town; a Flask Shard, one at most a floor
-- from a chest, adds one for good. Healing items (the item menu's, a quick slot's) refuse with an enemy near, so the
-- flask is the heal in a fight (player.tuning_set item_heal_lock). The flask is kept with the save ("flask").
do
  local SHARDS_MAX, SHARD_CHANCE, HEAL_AT = 7, 0.15, 0.65
  local bound, held, ticks = nil, false, 0
  local drinking = nil -- {who, at} from the drink's start, the tick it heals at once its frames are known

  local function save_key()
    local slot = try(game.save.slot_id)
    return type(slot) == "table" and slot.slot_id and ("flask:" .. slot.slot_id .. ":" .. tostring(slot.slot_generation)) or nil
  end
  local function state()
    local key = save_key()
    local s = key and try(game.save.get, key)
    if type(s) ~= "table" then s = {} end
    s.shards = math.type(s.shards) == "integer" and s.shards or 0
    s.taken = type(s.taken) == "table" and s.taken or {}
    return s, key
  end
  local function most(s) return clamp(setting("flask_charges", 3), 1, 10) + s.shards + later.sky_rank("deep_flask") end
  local function charges(s) return math.type(s.charges) == "integer" and math.min(s.charges, most(s)) or most(s) end
  local function store(s, key) if key then try(game.save.set, key, s) end end

  local function show(s)
    if in_sandbox or not (setting("flask", true) and in_dungeon) then try(game.render.layer_remove, {id = "flask"}) return end
    try(game.render.layer_register, {id = "flask", text = string.format("Flask %d/%d", charges(s), most(s))})
  end

  later.flask_refill = function()
    local s, key = state()
    s.charges = most(s)
    store(s, key)
    show(s)
  end

  local function drink()
    local p = try(game.player.get)
    if type(p) ~= "table" or type(p.character) ~= "string" then return end
    local s, key = state()
    local left = charges(s)
    if left <= 0 then toast("Vigil: the flask is empty. Rest at a shrine to fill it.", 150) return end
    if not try(game.player.move_play, {id = "vigil_" .. p.character .. "_flask"}) then return end
    s.charges = left - 1
    store(s, key)
    show(s)
    drinking = {who = p.character}
  end

  moonmod.on("game.player.move", function(e)
    if drinking and type(e) == "table" and e.id == "vigil_" .. drinking.who .. "_flask" then
      drinking.at = ticks + math.floor((math.type(e.frames) == "integer" and e.frames or 60) * HEAL_AT)
    end
  end)

  -- A hit that lands (not blocked, parried or taken on poise) spills the drink.
  moonmod.on("game.player.hit", function(e)
    if drinking and type(e) == "table" and not (e.blocked or e.parried or e.poised) then
      drinking = nil
      toast("Vigil: the flask spilled.", 90)
    end
  end)

  moonmod.on("game.tick", function()
    ticks = ticks + 1
    if in_sandbox or not setting("flask", true) then return end
    if drinking and drinking.at and ticks >= drinking.at then
      local p = try(game.player.get)
      local most_hp = type(p) == "table" and math.type(p.max_hp) == "integer" and p.max_hp or 0
      local heal = clamp(setting("flask_heal", 40), 10, 100) + 10 * later.sky_rank("healing_draught")
      local amount = math.max(1, math.floor(most_hp * math.min(heal, 100) / 100 + 0.5))
      try(game.player.heal, {amount = math.min(amount, 32767), character = drinking.who})
      local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
      if at then try(game.effects.burst, {kind = "heal", position = {x = at.x, y = (at.y or 0) + 10, z = at.z}}) end
      drinking = nil
    end
    local signature = "Gamepad:dpdown+" .. setting("flask_key", "None")
    if bound ~= signature then
      try(game.input.unbind, {id = "flask"})
      local keys = {"Gamepad:dpdown"}
      if setting("flask_key", "None") ~= "None" then keys[2] = setting("flask_key", "None") end
      local ok, err = call(game.input.bind, {id = "flask", keys = keys})
      bound = ok and signature or nil
      if not ok then moonmod.log("warn", "flask binding: " .. message(err)) end
    end
    local press = in_dungeon and try(game.input.state, {id = "flask"})
    local down = type(press) == "table" and press.down == true
    if down and not held and not drinking then drink() end
    held = down
  end)

  -- A Flask Shard: now and then in a chest, one at most a floor, kept with the save.
  moonmod.on("game.chest.opened", function(e)
    if in_sandbox or not setting("flask", true) or type(e) ~= "table" or type(e.dungeon_id) ~= "number" then return end
    local s, key = state()
    local place = tostring(e.dungeon_id) .. ":" .. tostring(e.floor_id)
    if s.shards >= SHARDS_MAX or s.taken[place] or math.random() >= SHARD_CHANCE then return end
    s.taken[place] = true
    s.shards = s.shards + 1
    s.charges = charges(s) + 1
    store(s, key)
    show(s)
    toast(string.format("Vigil: a Flask Shard. The flask holds %d now.", most(s)), 240)
  end)

  moonmod.on("game.world.location_changed", function(e)
    if type(e) ~= "table" then return end
    drinking = nil
    if e.context == "town" then later.flask_refill() else show((state())) end
  end)
end

-- Weapon rarity (from the Gauntlet's loot) ----------------------------------------------------------------------------
-- A weapon found in a dungeon (a chest, a pickup, a named elite's drop) rolls a rarity: Common, Uncommon, Rare, Epic or
-- Legendary, the Gauntlet's five, in its colours. Its stats grow once by the tier's multiplier, its name shows in the
-- tier's colour in the weapon menu and its swing trail glows in it. Rare and better carry touches, mechanics that fire
-- on hits and kills (Vampire, Poison, Frost, Thunder Chain, Echo, ...); Epic and Legendary get a generated name from
-- them ("Dracula's Baselard"). Each character has one fixed legendary with a signature of its own (Toan's Moonfang),
-- which a Legendary roll may turn out to be. Deeper dungeons, later cycles and elites lean rarer. The rarities are kept
-- with the save ("loot", by character and weapon slot) and shown again on load. Weapons bought in town stay plain.
-- The setting `loot_rarity` turns it off; weapons already rolled keep their stats.
do
  local function rgb(r, g, b) return {r = r, g = g, b = b} end
  local TIERS = {
    {key = "common", name = "Common", mult = 1.0, color = rgb(235, 235, 235), touches = 0},
    {key = "uncommon", name = "Uncommon", mult = 1.15, color = rgb(120, 230, 120), glow = rgb(70, 210, 70), touches = 0},
    {key = "rare", name = "Rare", mult = 1.3, color = rgb(110, 170, 255), glow = rgb(70, 130, 255), touches = 1},
    {key = "epic", name = "Epic", mult = 1.5, color = rgb(205, 125, 255), glow = rgb(175, 70, 255), touches = 2},
    {key = "legendary", name = "Legendary", mult = 1.8, color = rgb(255, 170, 60), glow = rgb(255, 150, 30), touches = 2},
  }
  -- adj: a Rare's word; own: an Epic's owner; of: an Epic's ending; roots/ends: a Legendary's own name is made of two.
  local TOUCHES = {
    vampire = {name = "Vampire Touch", short = "heals 8% of damage dealt", adj = "Vampiric", own = "Dracula's",
               of = "of the Hungry Night", roots = {"Blood", "Night", "Crimson"}, ends = {"fang", "thirst", "kiss"}},
    poison = {name = "Poison Touch", short = "1 in 3 hits poisons", adj = "Venomous", own = "Viper's",
              of = "of Slow Rot", roots = {"Venom", "Blight", "Rot"}, ends = {"sting", "bite", "kiss"}},
    goo = {name = "Goo Touch", short = "hits slow enemies", adj = "Gooey", own = "the Slime King's",
           of = "of Clinging Muck", roots = {"Muck", "Ooze", "Mire"}, ends = {"grip", "drip", "maw"}},
    frost = {name = "Frost Touch", short = "hits may freeze", adj = "Frozen", own = "the Ice Queen's",
             of = "of the Long Winter", roots = {"Frost", "Rime", "Winter"}, ends = {"bite", "song", "heart"}},
    thunder = {name = "Thunder Chain", short = "1 in 4 hits arc to another", adj = "Stormcalled", own = "Raijin's",
               of = "of the Seventh Storm", roots = {"Storm", "Thunder", "Volt"}, ends = {"call", "crack", "fury"}},
    echo = {name = "Echo", short = "1 in 3 hits strike again", adj = "Echoing", own = "the Phantom's",
            of = "of Twice-Told Blows", roots = {"Echo", "Ghost", "Shade"}, ends = {"song", "step", "call"}},
    ember = {name = "Ember Burst", short = "kills explode in flame", adj = "Blazing", own = "the Salamander's",
             of = "of Ash", roots = {"Ember", "Ash", "Cinder"}, ends = {"heart", "brand", "fall"}},
    gravity = {name = "Gravity Well", short = "charged hits pull foes in", adj = "Abyssal", own = "the Black Star's",
               of = "of the Undertow", roots = {"Void", "Abyss", "Star"}, ends = {"pull", "well", "maw"}},
    quake = {name = "Quake", short = "charged hits throw foes back", adj = "Quaking", own = "the Titan's",
             of = "of Broken Earth", roots = {"Quake", "Stone", "Titan"}, ends = {"fall", "break", "heart"}},
    reaper = {name = "Reaper", short = "finishes foes under 15% HP", adj = "Grim", own = "the Reaper's",
              of = "of the Final Hour", roots = {"Grave", "Dusk", "Death"}, ends = {"knell", "reap", "end"}},
    gilded = {name = "Gilded", short = "kills drop gilda", adj = "Gilded", own = "Midas'", of = "of Fortune",
              roots = {"Gold", "Coin", "Sun"}, ends = {"gleam", "purse", "crown"}},
    thorns = {name = "Thorns", short = "returns the hits you take", adj = "Thorned", own = "the Briar Witch's",
              of = "of Bramble", roots = {"Thorn", "Briar", "Bramble"}, ends = {"guard", "spite", "kiss"}},
    frenzy = {name = "Frenzy", short = "kills stack +8% damage", adj = "Frenzied", own = "the Berserker's",
              of = "of Red Mist", roots = {"Rage", "Red", "Wild"}, ends = {"fury", "howl", "fang"}},
    -- the legendaries' signatures
    lunar = {name = "Lunar Arc", short = "charged hits chain to 3 foes", signature = true},
    ricochet = {name = "Ricochet", short = "shots bounce to 2 more foes", signature = true},
    earthsplit = {name = "Earthsplitter", short = "charged hits explode", signature = true},
    phoenix = {name = "Phoenix", short = "kills explode and heal you", signature = true},
    venomtotem = {name = "Venom Totem", short = "poisons; kills under 25%", signature = true},
    starfall = {name = "Starfall", short = "every 5th hit calls a star", signature = true},
  }
  local POOL = {"vampire", "poison", "goo", "frost", "thunder", "echo", "ember", "gravity", "quake", "reaper", "gilded", "thorns", "frenzy"}
  local LEGENDS = {
    toan = {key = "moonfang", name = "Moonfang", item = 266, touches = {"thunder", "echo", "lunar"}},
    xiao = {key = "ninefold", name = "Ninefold", item = 304, touches = {"vampire", "frost", "ricochet"}},
    goro = {key = "titanfall", name = "Titanfall", item = 322, touches = {"quake", "gravity", "earthsplit"}},
    ruby = {key = "emberheart", name = "Emberheart", item = 337, touches = {"ember", "thunder", "phoenix"}},
    ungaga = {key = "gaiasting", name = "Gaia's Sting", item = 352, touches = {"poison", "reaper", "venomtotem"}},
    osmond = {key = "starfall", name = "Starfall", item = 365, touches = {"echo", "gilded", "starfall"}},
  }
  -- Each character's weapons, by native item number, for an elite's drop.
  local RANGES = {toan = {258, 272}, xiao = {300, 311}, goro = {315, 325}, ruby = {332, 340}, ungaga = {348, 357}, osmond = {364, 368}}
  local ROSTER = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
  local QUALITY = {"Fine", "Keen", "Honed", "Sturdy", "Polished", "Tempered"}
  local NAME_CAP = 22 -- names stay short enough for the weapon menu's name plates
  local TOUCH_RGB, SIGNATURE_RGB = rgb(240, 215, 150), rgb(255, 225, 120)

  local function pick(t) return t[math.random(#t)] end
  local function on() return setting("loot_rarity", true) and not in_sandbox end
  local function wid(item) return "chronicle:weapon:" .. item end
  local function who_of(c) return type(c) == "number" and ROSTER[c + 1] or c end

  -- The save's rolled weapons: {["toan:3"] = {id, tier, touches, name, legend}}.
  local function kept()
    local seeds = floor_seeds()
    if type(seeds.loot) ~= "table" then seeds.loot = {} end
    return seeds.loot, seeds
  end
  local function store(seeds) if floors.key then try(game.save.set, floors.key, seeds) end end

  local function base_name(id)
    local w = try(game.weapons.get, id)
    return type(w) == "table" and type(w.name) == "string" and w.name ~= "" and w.name or "Weapon"
  end
  local function first_fit(...)
    local shortest
    for _, s in ipairs({...}) do
      if #s <= NAME_CAP then return s end
      if not shortest or #s < #shortest then shortest = s end
    end
    return shortest
  end
  local function make_name(tier, base, touches)
    local t1, t2, t3 = TOUCHES[touches[1] or ""], TOUCHES[touches[2] or ""], TOUCHES[touches[3] or ""]
    if tier == 2 then return first_fit(pick(QUALITY) .. " " .. base, "Fine " .. base, base) end
    if tier == 3 and t1 then return first_fit(t1.adj .. " " .. base, base) end
    if tier == 4 and t1 then
      local long = t2 and (t1.adj .. " " .. base .. " " .. t2.of)
      if long and #long <= NAME_CAP and math.random(2) == 1 then return long end
      return first_fit(t1.own .. " " .. base, t1.adj .. " " .. base, base)
    end
    if tier == 5 and t1 then
      local a, b = t1, t2 or t1
      local proper = pick(a.roots) .. pick(b.ends)
      return first_fit(proper .. ", " .. (t3 or a).own .. " " .. base, proper .. " " .. base, proper)
    end
    return base
  end

  -- How deep the party is: the dungeon (0-6) counts most, then the floor, then each cycle past the first.
  local function depth()
    local d = floor_now and tonumber(floor_now.dungeon_id) or 0
    local f = floor_now and tonumber(floor_now.floor_id) or 0
    return 3 * d + math.floor(f / 4) + 6 * (later.cycle_now and later.cycle_now() or 0) + 3 * later.sky_rank("keen_eye")
  end
  -- The tier a weapon rolls; `least` is the lowest allowed.
  local function roll_tier(least)
    local forced = setting("loot_tier", 0) -- tests only: always this tier
    if forced >= 1 and forced <= 5 then return forced end
    local d = depth()
    local weights = {math.max(8, 52 - 2 * d), 28, 14 + d, 5 + 0.6 * d, 1 + 0.25 * d}
    local total = 0
    for t = least or 1, 5 do total = total + weights[t] end
    local r = math.random() * total
    for t = least or 1, 5 do
      r = r - weights[t]
      if r <= 0 then return t end
    end
    return 5
  end
  local function draw_touches(n)
    local bag, out = {}, {}
    for _, id in ipairs(POOL) do bag[#bag + 1] = id end
    for _ = 1, n do
      if #bag == 0 then break end
      out[#out + 1] = table.remove(bag, math.random(#bag))
    end
    return out
  end

  -- The record of the weapon in a character's slot, if it is still the one that rolled.
  local function record(c, slot, id)
    local r = kept()[c .. ":" .. tostring(slot)]
    if type(r) == "table" and (id == nil or r.id == id) then return r end
  end

  -- What the menu shows of a rolled weapon: {name, color, glow, badge, details}, or nil for a plain one.
  later.loot_style = function(c, slot, id)
    local r = on() and record(c, slot, id)
    local tier = r and TIERS[r.tier]
    if not tier then return nil end
    local badge = {{text = tier.name:upper(), color = tier.color, scale = 1.15},
                   {text = (string.format("Stats x%.2f", tier.mult):gsub("0$", "")), color = rgb(200, 195, 185), scale = 0.75}}
    local details = {}
    for _, t in ipairs(r.touches or {}) do
      local d = TOUCHES[t]
      if d then details[#details + 1] = {text = (d.signature and "* " or "") .. d.name .. ": " .. d.short, color = d.signature and SIGNATURE_RGB or TOUCH_RGB} end
    end
    return {name = r.name, color = tier.color, glow = tier.glow, badge = badge, details = details}
  end

  -- The weapons that moved: a record whose slot now holds another weapon follows its weapon to the slot it went to
  -- (the menu sorts, a sale shifts the rest), or is let go once the weapon is gone. Returns the records to show.
  later.loot_settle = function()
    local loot, seeds = kept()
    if not (try(game.save.slot_id) or floors.key) then return loot end -- no save loaded: leave the records be
    local changed = false
    local owned, asked = {}, {} -- "c:slot" -> id, for each weapon a record names
    for _, r in pairs(loot) do
      if type(r) == "table" and type(r.id) == "string" and not asked[r.id] then
        asked[r.id] = true
        local w = try(game.weapons.get, r.id)
        for _, inst in ipairs(type(w) == "table" and type(w.instances) == "table" and w.instances or {}) do
          local c = who_of(inst.character)
          if type(c) == "string" and math.type(inst.slot) == "integer" then owned[c .. ":" .. inst.slot] = r.id end
        end
      end
    end
    local moved = {}
    for k, r in pairs(loot) do
      if type(r) ~= "table" or owned[k] ~= r.id then moved[#moved + 1] = k end
    end
    for _, k in ipairs(moved) do
      local r = loot[k]
      loot[k] = nil
      changed = true
      local c = k:match("^([^:]+):")
      if type(r) == "table" and c then
        for ok, id in pairs(owned) do
          if id == r.id and ok:match("^([^:]+):") == c and not loot[ok] then loot[ok] = r; break end
        end
      end
    end
    if changed then store(seeds) end
    return loot
  end

  -- Grows the weapon's stats by the tier and keeps its record.
  local function apply(c, slot, id, tier, touches, name, legend)
    local w = try(game.weapons.get, {id = id, character = c, slot = slot})
    local stats
    for _, inst in ipairs(type(w) == "table" and type(w.instances) == "table" and w.instances or {}) do
      if who_of(inst.character) == c and inst.slot == slot then stats = inst.stats end
    end
    stats = stats or (type(w) == "table" and w.stats)
    if type(stats) == "table" then
      local request = {id = id, character = c, slot = slot}
      for _, k in ipairs({"attack", "endurance", "speed", "magic"}) do
        request[k] = math.floor(clamp((tonumber(stats[k]) or 0) * TIERS[tier].mult + 0.5, 0, 32767))
      end
      try(game.weapons.stats_set, request)
    end
    local loot, seeds = kept()
    loot[c .. ":" .. tostring(slot)] = {id = id, tier = tier, touches = touches, name = name, legend = legend}
    store(seeds)
    if later.weapon_cards then later.weapon_cards() end
  end

  -- A found weapon rolls its rarity. Returns the tier rolled, or nil.
  later.loot_roll = function(c, id, slot, least)
    c = who_of(c)
    if not on() or type(c) ~= "string" or type(id) ~= "string" or math.type(slot) ~= "integer" then return nil end
    if record(c, slot, id) then return nil end -- already rolled
    local tier = roll_tier(least)
    local legend = LEGENDS[c]
    if tier == 5 and legend and math.random(100) <= 35 then
      local given = call(game.weapons.give, {id = wid(legend.item), character = c})
      if given and given.slot then
        try(game.weapons.remove, {id = id, character = c, slot = slot})
        later.loot_settle()
        apply(c, given.slot, wid(legend.item), 5, legend.touches, legend.name, legend.key)
        toast(string.format("Vigil: %s! %s's own legendary.", legend.name, (c:gsub("^%l", string.upper))), 300)
        return 5
      end
    end
    local touches = draw_touches(TIERS[tier].touches + (tier == 5 and 1 or 0))
    local name = (make_name(tier, base_name(id), touches):gsub("^%l", string.upper))
    apply(c, slot, id, tier, touches, name)
    if tier >= 3 then toast(string.format("Vigil: %s (%s).", name, TIERS[tier].name), 240) end
    return tier
  end

  -- A named elite leaves a weapon, Rare or better, for someone in the party.
  later.loot_elite_drop = function(who)
    if not on() then return end
    local party = {}
    local members = try(game.party and game.party.list)
    for _, m in ipairs(type(members) == "table" and (members.members or members) or {}) do
      if type(m) == "table" and RANGES[m.id] and m.joined ~= false then party[#party + 1] = m.id end
    end
    local c = pick(#party > 0 and party or {"toan"})
    local range = RANGES[c]
    local given = call(game.weapons.give, {id = wid(math.random(range[1], range[2])), character = c})
    if not (given and given.slot) then return end
    toast(string.format("Vigil: %s left a weapon behind for %s.", who or "The elite", (c:gsub("^%l", string.upper))), 240)
    later.loot_roll(c, given.id or wid(given.native_item_no), given.slot, 3)
  end

  moonmod.on("game.item_picked_up", function(e)
    if type(e) ~= "table" or e.kind ~= "weapon" or not in_dungeon then return end
    later.loot_roll(e.character, e.id, e.slot)
  end)

  -- Touches in play ------------------------------------------------------------------------------------------------
  local dots, echoes, last_pos, frenzy = {}, {}, {}, {stacks = 0, until_ = 0}
  local hits, tick, hp_seen, hp_who = 0, 0, nil, nil
  local function touches_of(p)
    local w = type(p) == "table" and p.weapon
    local r = type(w) == "table" and w.id and on() and record(p.character, w.slot, w.id)
    local set = {}
    for _, t in ipairs(r and r.touches or {}) do set[t] = true end
    return set
  end
  local function position_of(entity)
    local m = try(game.entities.get, entity)
    if type(m) == "table" and m.position then last_pos[tostring(entity)] = m.position end
    return m
  end
  local function others(center, radius, except)
    local near = try(game.physics.query, {shape = "sphere", center = {x = center.x, y = center.y, z = center.z}, radius = radius})
    local out = {}
    for _, m in ipairs(type(near) == "table" and near.matches or {}) do
      if tostring(m.entity) ~= tostring(except) then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return (a.distance or 0) < (b.distance or 0) end)
    return out
  end
  local function burst(kind, at, scale) if at then try(game.effects.burst, {kind = kind, position = {x = at.x, y = (at.y or 0) + 8, z = at.z}, scale = scale}) end end
  local function poison(entity, m, frames)
    local max = type(m) == "table" and m.health and tonumber(m.health.maximum) or 40
    dots[tostring(entity)] = {entity = entity, until_ = tick + frames, next = tick + 60, amount = math.max(1, math.floor(max * 0.03))}
    try(game.entities.tint, {entity = entity, color = rgb(90, 255, 90), frames = frames})
  end
  local function chain(at, except, count, amount)
    local struck = 0
    for _, o in ipairs(others(at, 150, except)) do
      if struck >= count then break end
      if try(game.combat.damage, {entity = o.entity, amount = amount}) then
        struck = struck + 1
        burst("sparks", (position_of(o.entity) or {}).position, 0.8)
      end
    end
  end
  local function explode(at, except, amount)
    burst("explosion", at, 0.8)
    for _, o in ipairs(others(at, 100, except)) do try(game.combat.damage, {entity = o.entity, amount = amount}) end
  end

  moonmod.on("game.enemy_hit", function(e)
    if type(e) ~= "table" or not e.entity then return end
    local damage = tonumber(e.damage) or 0
    if damage <= 0 then return end
    local p = try(game.player.get)
    local set = touches_of(p)
    if next(set) == nil then return end
    hits = hits + 1
    local m = position_of(e.entity)
    local at = type(m) == "table" and m.position
    local hp = type(m) == "table" and m.health and tonumber(m.health.current) or 0
    local max = type(m) == "table" and m.health and tonumber(m.health.maximum) or 1
    if set.vampire then
      try(game.player.heal, {amount = math.max(1, math.floor(damage * 0.08))})
      if hits % 4 == 0 then burst("heal", p.position, 1) end
    end
    if set.frenzy and frenzy.stacks > 0 and tick < frenzy.until_ then
      try(game.combat.damage, {entity = e.entity, amount = math.max(1, math.floor(damage * 0.08 * frenzy.stacks))})
    end
    if (set.poison and math.random(3) == 1) or set.venomtotem then poison(e.entity, m, 300) end
    if set.goo then
      try(game.combat.status_add, {entity = e.entity, status = "slow", duration_frames = 150})
      try(game.entities.tint, {entity = e.entity, color = rgb(190, 100, 255), frames = 150})
    end
    if set.frost and math.random(100) <= 15 then
      try(game.combat.status_add, {entity = e.entity, status = "stop", duration_frames = 75})
      try(game.entities.tint, {entity = e.entity, color = rgb(160, 225, 255), frames = 75})
      burst("guard", at, 1)
    end
    if at and set.thunder and math.random(4) == 1 then chain(at, e.entity, 1, math.max(1, math.floor(damage * 0.5))) end
    if at and set.ricochet then chain(at, e.entity, 2, math.max(1, math.floor(damage * 0.35))) end
    if at and set.lunar and e.charged then chain(at, e.entity, 3, math.max(1, math.floor(damage * 0.6))) end
    if set.echo and math.random(3) == 1 then echoes[#echoes + 1] = {at = tick + 30, entity = e.entity, amount = math.max(1, math.floor(damage * 0.6))} end
    if at and set.gravity and e.charged then
      for _, o in ipairs(others(at, 170, e.entity)) do
        local om = try(game.entities.get, o.entity)
        local op = type(om) == "table" and om.position
        if op then try(game.entities.knockback, {entity = o.entity, direction = {x = at.x - op.x, z = at.z - op.z}, speed = 9}) end
      end
      burst("guard", at, 1.4)
    end
    if set.quake and e.charged and p.position then
      for _, o in ipairs(others(p.position, 130, nil)) do
        local om = try(game.entities.get, o.entity)
        local op = type(om) == "table" and om.position
        if op then try(game.entities.knockback, {entity = o.entity, direction = {x = op.x - p.position.x, z = op.z - p.position.z}, speed = 12}) end
      end
      burst("sparks", p.position, 1.5)
    end
    if at and set.earthsplit and e.charged then explode(at, nil, math.max(1, math.floor(damage * 1.2))) end
    if at and set.starfall and hits % 5 == 0 then explode(at, nil, math.max(1, math.floor(damage * 2))) end
    -- finishers last, on what is left after the hit
    if hp > 0 and ((set.reaper and hp < max * 0.15) or (set.venomtotem and dots[tostring(e.entity)] and hp < max * 0.25)) then
      try(game.combat.damage, {entity = e.entity, amount = hp})
      burst("guard", at, 1)
    end
  end)

  moonmod.on("game.enemy_defeated", function(e)
    if type(e) ~= "table" or not e.entity then return end
    local id = tostring(e.entity)
    dots[id] = nil
    local at = last_pos[id]
    last_pos[id] = nil
    local p = try(game.player.get)
    local set = touches_of(p)
    if next(set) == nil then return end
    if set.frenzy then frenzy.stacks, frenzy.until_ = math.min(5, (tick < frenzy.until_ and frenzy.stacks or 0) + 1), tick + 360 end
    if set.gilded then try(game.economy.add, {amount = math.random(5, 15) * (1 + depth())}) end
    if at and (set.ember or set.phoenix) then
      local w = p.weapon
      explode(at, e.entity, math.max(4, math.floor((tonumber(type(w) == "table" and w.attack) or 20) * 1.5)))
    end
    if set.phoenix and p.max_hp then try(game.player.heal, {amount = math.max(1, math.floor(p.max_hp * 0.04))}) end
  end)

  -- Each tick: poison and echoes land, and Thorns answers the hits taken.
  moonmod.on("game.tick", function()
    tick = tick + 1
    if next(dots) == nil and #echoes == 0 and tick % 6 ~= 0 then return end
    for id, d in pairs(dots) do
      if tick >= d.until_ then dots[id] = nil
      elseif tick >= d.next then
        d.next = tick + 60
        if not try(game.combat.damage, {entity = d.entity, amount = d.amount}) then dots[id] = nil end
      end
    end
    for i = #echoes, 1, -1 do
      local q = echoes[i]
      if tick >= q.at then
        table.remove(echoes, i)
        local m = position_of(q.entity)
        if try(game.combat.damage, {entity = q.entity, amount = q.amount}) then burst("sparks", type(m) == "table" and m.position, 1.2) end
      end
    end
    if not in_dungeon then return end
    local p = try(game.player.get)
    if type(p) == "table" and p.hp then
      local was = hp_seen
      hp_seen = p.hp
      if was and p.hp < was and p.character == hp_who and touches_of(p).thorns and p.position then
        local o = others(p.position, 130, nil)[1]
        if o then try(game.combat.damage, {entity = o.entity, amount = math.floor((was - p.hp) * 1.5) + 2}) end
      end
      hp_who = p.character
    end
  end)

  moonmod.on("game.world.location_changed", function()
    dots, echoes, last_pos, hp_seen = {}, {}, {}, nil
  end)
end

-- Weapon arts (above): each weapon that has an art (Toan's, and with Party attacks the others') says so on its card in
-- the weapon menu, with the level
-- it unlocks at. Done again on each new place and when a weapon levels up; Arts off takes the cards away. A weapon
-- that rolled a rarity (Weapon rarity, above) shows it on the same card: its name and colour, the tier, its touches,
-- then its art in two lines.
do
  local function cards()
    if in_sandbox or type(game.weapons) ~= "table" then return end
    try(game.weapons.style_clear, {})
    local styles = {} -- "who:slot" -> the style_set request
    for k, r in pairs(later.loot_settle()) do
      local who, slot = k:match("^([^:]+):(%d+)$")
      local style = who and later.loot_style(who, tonumber(slot), r.id)
      if style then
        style.character, style.slot = who, tonumber(slot)
        styles[k] = style
      end
    end
    local need = clamp(setting("art_level", 3), 1, 99)
    for _, art in ipairs(setting("arts", true) and ATTACKS.arts or {}) do
      local gauge, who = art.gauge, art.character or "toan"
      local shown = who == "toan" and setting("toan_attacks", true) or who ~= "toan" and setting("party_attacks", true)
      for _, item_no in ipairs(shown and art.weapons or {}) do
        local w = try(game.weapons.get, "chronicle:weapon:" .. item_no)
        for _, owned in ipairs(type(w) == "table" and type(w.instances) == "table" and w.instances or {}) do
          if owned.character == who and math.type(owned.slot) == "integer" then
            local level = math.type(owned.level) == "integer" and owned.level or 1
            local ready = level >= need and {text = "Ready.", color = {140, 220, 140}}
              or {text = string.format("Unlocks at level %d (now %d).", need, level), color = {200, 160, 160}}
            local k = who .. ":" .. owned.slot
            local style = styles[k]
            if style and #style.details > 0 then
              -- the touches first; the art in two lines below them (a card holds five)
              while #style.details > 3 do table.remove(style.details) end
              style.details[#style.details + 1] = {text = string.format("Art: %s (R1 + R2, %d gauge)", art.name, gauge), color = {236, 200, 120}}
              style.details[#style.details + 1] = ready
            else
              style = style or {character = who, slot = owned.slot}
              style.details = {{text = "Art: " .. art.name, color = {236, 200, 120}}, art.line,
                               string.format("Guard (R1) + R2. Costs %d gauge.", gauge), ready}
              styles[k] = style
            end
          end
        end
      end
    end
    for _, style in pairs(styles) do
      if #style.details == 0 then style.details = {{text = "No touches. Stronger than its plain kind.", color = {200, 195, 185}}} end
      try(game.weapons.style_set, style)
    end
  end
  later.weapon_cards = cards
  moonmod.on("game.world.location_changed", cards)
  moonmod.on("game.weapon.upgraded", cards)
  moonmod.on("settings.changed", function(e)
    if type(e) == "table" and (e.id == "arts" or e.id == "art_level" or e.id == "toan_attacks" or e.id == "party_attacks" or
                               e.id == "loot_rarity") then cards() end
  end)
end

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
    elseif e.index == 3 and floor_seeds().cycle_ready then
      try(game.ui.choice_open, {id = "vigil.cycle", title = "Leave", subtitle = shrine_name(shrine_at), cancel = true, cursor = 1, options = {
        {title = "Leave", lines = {"Back to town.", {text = "The cycle waits.", tone = "dim"}}},
        {title = "Next cycle", lines = {"Every map made new, all in them stronger.", {text = "Your levels, tree and gear stay.", tone = "gold"}}}}})
    elseif e.index == 3 then
      local town = SHRINE_TOWNS[shrine_at.dungeon_id]
      keep_map()
      if town then try(game.world and game.world.transition, {id = "chronicle:location:" .. town}) end
    elseif e.index == 4 then
      open_tree()
    elseif e.index == 5 and later.messages_open then
      later.messages_open()
    end
  elseif e.id == "vigil.cycle" and (e.index == 1 or (later.next_cycle and later.next_cycle())) then
    local town = SHRINE_TOWNS[shrine_at.dungeon_id]
    if e.index == 1 then keep_map() end
    if town then try(game.world and game.world.transition, {id = "chronicle:location:" .. town}) end
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
  -- Where you died (§12, stretch goal 14): the card, and the last eight deaths kept with the save for the map.
  if setting("you_died", true) then try(game.ui.boss_card, {name = "YOU DIED", frames = 150}) end
  if at and floor_now and floor_now.dungeon_id == e.dungeon_id and zoned_floor(floor_now) then
    local deaths = type(seeds.deaths) == "table" and seeds.deaths or {}
    table.insert(deaths, 1, {key = place_key(floor_now.dungeon_id, floor_now.floor_id), x = math.floor(at.x / 160 + 0.5),
                             y = math.floor(at.z / 160 + 0.5)})
    for i = #deaths, 9, -1 do deaths[i] = nil end
    seeds.deaths = deaths
  end
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
  local seen = {} -- one mark a cell, the newest death's
  if type(f) == "table" and f.key == k then seen[tostring(f.x) .. ":" .. tostring(f.y)] = true end
  for i, d in ipairs(type(seeds.deaths) == "table" and seeds.deaths or {}) do
    local cell = type(d) == "table" and tostring(d.x) .. ":" .. tostring(d.y)
    if cell and d.key == k and type(d.x) == "number" and not seen[cell] then
      seen[cell] = true
      marks[#marks + 1] = {x = d.x, y = d.y, kind = "mark", label = i == 1 and "You fell here last" or "You fell here before"}
    end
  end
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
  local c = later.cycle_now and later.cycle_now() or 0 -- NG+ (below): each cycle past the first, half again as hardy, and so on
  return {level = level, base = base, hp = (1 + 0.12 * over + 0.1 * zone) * (1 + 0.5 * c),
          damage = math.min(2 + 0.5 * c, (1 + 0.06 * over) * (1 + 0.25 * c)), reward = (1 + 0.05 * over) * (1 + 0.5 * c)}
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

-- Story bosses (§12, stretch goal 7): Dran and the bosses after him keep their own arenas and casts, but each has an
-- entrance card, a bar of its own along the bottom of the screen, and a second phase at half life: a roar (a burst and
-- a word), a red tint, its moves 40% faster (combat.status_add haste) and its blows 30% harder. Keyed by native model.
do
  local BOSSES = {
    [78] = {name = "Dran", epithet = "Lord of the Divine Beast Cave"},
    [79] = {name = "Master Utan", epithet = "Elder of the Wise Owl Forest"},
    [80] = {name = "Ice Queen", epithet = "Mistress of the Shipwreck"},
    [81] = {name = "King's Curse", epithet = "The Sun and Moon Temple's Shadow"},
    [83] = {name = "Minotaur Joe", epithet = "Brute of the Moon Sea"},
    [84] = {name = "Dark Genie", epithet = "The Wish-Granter's Shadow"},
    [106] = {name = "Dark Genie", epithet = "Darkness Unbound"},
  }
  local fights = {} -- entity -> {model, max, phase, refresh, move_at, told}
  local clock, shown = 0, false

  -- Each boss's new move in its second phase, every six seconds or so: marks glint where it will land (the telegraph),
  -- and three quarters of a second later the blow falls there (combat.strike_player: a guard, a parry or a dodge's
  -- invincibility take it, and stepping off the mark beats it). `marks` lays the marks out from the boss (b) toward the
  -- player (p); `share` is the blow's share of the player's life, `stagger` frames between marks. `motion` is a move's
  -- body: a motion of the boss's own (tools/anim/vigil_boss_moves.py) it plays as the marks glint, its script held
  -- meanwhile; its blow lands with the marks.
  local function along(b, p, steps, spacing)
    local dx, dz = p.x - b.x, p.z - b.z
    local d = math.max(1, math.sqrt(dx * dx + dz * dz))
    local out = {}
    for i = 1, steps do out[i] = {x = b.x + dx / d * spacing * i, y = p.y, z = b.z + dz / d * spacing * i} end
    return out
  end
  local MOVES = {
    [78] = {word = "breathes fire", share = 0.18, kind = "heavy", radius = 26, stagger = 8, land = "explosion",
            marks = function(b, p) return along(b, p, 4, 40) end,
            -- rears up with his wings spread (the telegraph), and slams his head down on the line at 28
            motion = {id = "c12a_rear", speed = 0.6}},
    [79] = {word = "stamps the earth", share = 0.14, kind = "light", radius = 34, stagger = 0, land = "smoke",
            marks = function(b, p)
              local out = {}
              for i = 0, 5 do out[#out + 1] = {x = b.x + 60 * math.cos(i * math.pi / 3), y = p.y, z = b.z + 60 * math.sin(i * math.pi / 3)} end
              return out
            end,
            motion = {id = "c14a_stamp", speed = 0.6}}, -- both arms flung up as he springs, then down on the floor
    [80] = {word = "calls the frost", share = 0.15, kind = "light", radius = 30, stagger = 12, land = "impact",
            marks = function(_, p) return {{x = p.x, y = p.y, z = p.z}, {x = p.x + 40, y = p.y, z = p.z}, {x = p.x - 40, y = p.y, z = p.z}} end,
            motion = {id = "c13a_frost", speed = 0.6}}, -- her arms raised as she leans back, then thrust down
    [81] = {word = "rains curses", share = 0.12, kind = "light", radius = 24, stagger = 6, land = "impact",
            marks = function(_, p)
              return {{x = p.x, y = p.y, z = p.z}, {x = p.x + 50, y = p.y, z = p.z + 50}, {x = p.x - 50, y = p.y, z = p.z + 50},
                      {x = p.x + 50, y = p.y, z = p.z - 50}, {x = p.x - 50, y = p.y, z = p.z - 50}}
            end,
            motion = {id = "c15a_curse", speed = 0.6}}, -- the coffin up with its doors flung open, then slammed shut
    [83] = {word = "leaps", share = 0.22, kind = "heavy", radius = 42, stagger = 0, land = "explosion",
            marks = function(_, p) return {{x = p.x, y = p.y, z = p.z}} end,
            motion = {id = "c16a_leap", speed = 0.6}}, -- up with his axe high, then down with it on you
    [84] = {word = "sweeps a beam", share = 0.2, kind = "heavy", radius = 26, stagger = 5, land = "explosion",
            marks = function(b, p) return along(b, p, 6, 40) end,
            motion = {id = "c17a_sweep", speed = 0.6}}, -- his arms raised and wound round, then swept across
  }
  -- the King's Curse out of his coffin (c15b) and the Genie's final form (c23a) are other models: the same moves, with
  -- bodies of their own (his arms flung down; the Genie's own charge and firing poses)
  MOVES[82] = setmetatable({motion = {id = "c15b_curse", speed = 0.6}}, {__index = MOVES[81]})
  MOVES[106] = setmetatable({motion = {id = "c23a_beam", speed = 0.6}}, {__index = MOVES[84]})
  local falling = {} -- {at, pos, radius, damage, kind, land}

  local function cast_move(fight, boss_at, entity)
    local move = MOVES[fight.model]
    local p = try(game.player.get)
    local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
    if not move or not at or not boss_at then return end
    local body = move.motion
    if body and entity then
      if not body.n then
        local listed = try(game.animations.monster_list)
        for _, r in ipairs(type(listed) == "table" and listed.motions or {}) do
          if r.id == body.id and r.model == fight.model and r.motion then body.n, body.length = r.motion, r.length end
        end
      end
      if body.n then
        native(entity, "SET_MOVE_CANSEL")
        native(entity, "SET_MOTION_CHANGE_STEP", {0.25})
        native(entity, "SET_MOTION", {body.n, body.speed, 6})
        minds[entity] = {boss_until = hook_frame + math.ceil((body.length or 56) / body.speed)}
      end
    end
    local most = type(p.max_hp) == "number" and p.max_hp or 100
    local damage = math.max(4, math.floor(most * move.share + 0.5))
    for i, mark in ipairs(move.marks(boss_at, at)) do
      try(game.effects.burst, {kind = "guard", position = {x = mark.x, y = mark.y + 4, z = mark.z}, scale = 1.6})
      falling[#falling + 1] = {at = clock + 45 + (i - 1) * move.stagger, glint = clock + 22, pos = mark, radius = move.radius,
                               damage = damage, kind = move.kind, land = move.land}
    end
    if not fight.told then
      fight.told = true
      toast(string.format("Vigil: %s %s! Watch for the glint.", BOSSES[fight.model].name, move.word), 200)
    end
  end

  local function enrage(entity, fight, at)
    fight.phase = 2
    local b = BOSSES[fight.model]
    if at then try(game.effects.burst, {kind = "explosion", position = {x = at.x, y = (at.y or 0) + 20, z = at.z}, scale = 1.6}) end
    toast(string.format("Vigil: %s rages!", b.name), 180)
    local now = try(game.entities.set_stats, {entity = entity})
    local before = type(now) == "table" and type(now.current) == "table" and tonumber(now.current.damage_scale) or 1
    try(game.entities.set_stats, {entity = entity, damage_scale = clamp(before * 1.3, 0, 10)})
  end

  local function sustain(entity)
    try(game.entities.tint, {entity = entity, color = {r = 220, g = 60, b = 40}, frames = 3600})
    try(game.combat.status_add, {entity = entity, status = "haste", duration_frames = 3600})
  end

  local function clear()
    fights, shown, falling = {}, false, {}
    try(game.render.bar_remove, {id = "boss"})
  end

  -- The marks: a second glint halfway, then the blow.
  moonmod.on("game.tick", function()
    if #falling == 0 then return end
    local keep = {}
    for _, f in ipairs(falling) do
      if f.glint and clock >= f.glint then
        f.glint = nil
        try(game.effects.burst, {kind = "guard", position = {x = f.pos.x, y = f.pos.y + 4, z = f.pos.z}, scale = 1.2})
      end
      if clock >= f.at then
        try(game.effects.burst, {kind = f.land, position = {x = f.pos.x, y = f.pos.y + 6, z = f.pos.z}, scale = 1.3})
        try(game.combat.strike_player, {x = f.pos.x, y = f.pos.y + 6, z = f.pos.z, radius = f.radius, damage = f.damage, kind = f.kind})
      else
        keep[#keep + 1] = f
      end
    end
    falling = keep
  end)

  moonmod.on("game.tick", function()
    clock = clock + 1
    -- The bosses' own motions are appended to their models from the next floor that loads one.
    if not MOVES[78].motion.registered then
      for model, move in pairs(MOVES) do
        if move.motion and not move.motion.registered then
          move.motion.registered = true
          local ok, err = call(game.animations.monster_register,
                               {id = move.motion.id, model = model, file = "resources/anims/" .. move.motion.id .. ".json"})
          if not ok then moonmod.log("warn", "boss motion " .. move.motion.id .. ": " .. message(err)) end
        end
      end
    end
    if in_sandbox or not in_dungeon or clock % 15 ~= 0 or not setting("boss_phase", true) then return end
    local q = try(game.entities.query, {type = "monster"})
    if type(q) ~= "table" or type(q.entities) ~= "table" then return end
    local current, most, name = 0, 0, nil
    for _, m in ipairs(q.entities) do
      local b = m.native_model_id and BOSSES[m.native_model_id]
      local id = m.entity_id
      local health = type(m.health) == "table" and m.health or {}
      if b and id and m.revealed and type(health.current) == "number" and type(health.maximum) == "number" then
        local fight = fights[id]
        if not fight then
          fight = {model = m.native_model_id, phase = 1, refresh = 0}
          fights[id] = fight
          if not shown then
            shown = true
            try(game.ui.boss_card, {kicker = "A STORY BOSS", name = b.name, epithet = b.epithet, frames = 170})
          end
        end
        if fight.phase == 1 and health.current <= health.maximum / 2 then
          enrage(id, fight, type(m.position) == "table" and m.position or nil)
        end
        if fight.phase == 2 and clock >= fight.refresh then
          fight.refresh = clock + 1800
          sustain(id)
        end
        if fight.phase == 2 and setting("boss_moves", true) then
          if not fight.move_at then
            fight.move_at = clock + 120
          elseif clock >= fight.move_at then
            fight.move_at = clock + 360
            cast_move(fight, type(m.position) == "table" and m.position or nil, id)
          end
        end
        current, most, name = current + health.current, most + health.maximum, name or b.name
      end
    end
    if name and most > 0 then
      try(game.render.bar_register, {id = "boss", label = name:upper():sub(1, 24), current = math.max(0, math.min(current, most)),
                                     max = most, boss = true})
    elseif shown then
      clear()
    end
  end)
  moonmod.on("game.world.location_changed", clear)
end

-- Named elites (§12, stretch goal 8): each floor of a dungeon (and each zone of a region) has one named foe, picked from
-- its ordinary monsters the first time they are seen: gold, three times the life, half again the bite, five times the
-- reward, its name over a bar of its own, and a piece of gear (Fine or better) when it falls. A floor's elite falls once:
-- the save keeps it, so a cleared floor's elite stays down when the floor is built again.
do
  local TITLES = {"the Unbowed", "the Gravewalker", "the Hollow", "Who Waits", "the Last Watch", "of the Long Night",
                  "the Oathless", "the Ashen", "Bone-Crowned", "the Wanderer", "the Patient", "Moon-Eater"}
  local NAMES = {"Garrow", "Velka", "Oskar", "Kestrel", "Morwen", "Aldric", "Mirel", "Tobben", "Sable", "Corwen", "Ilse", "Dunmor"}
  local STORY_BOSS = {[78] = true, [79] = true, [80] = true, [81] = true, [82] = true, [83] = true, [84] = true, [106] = true}
  local elite, slain_key, sighted, clock = nil, nil, nil, 0 -- elite: {entity, name, max}

  local function elite_on() return setting("elites", true) and not in_sandbox end

  local function floor_key()
    if not floor_now then return nil end
    local z = try(game.dungeons.zones_get)
    local zone = type(z) == "table" and type(z.current) == "number" and z.current or 0
    return string.format("%s:%d:elite", place_key(floor_now.dungeon_id, floor_now.floor_id), zone)
  end

  -- The same name for the same floor every time it is built.
  local function name_for(key)
    local h = 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 1000003 end
    return NAMES[h % #NAMES + 1] .. " " .. TITLES[(h // #NAMES) % #TITLES + 1]
  end

  local function drop_bar()
    try(game.render.bar_remove, {id = "elite"})
  end

  local function crown(m, key)
    local id = m.entity_id
    local health = type(m.health) == "table" and m.health or {}
    local combat = type(m.combat) == "table" and m.combat or {}
    local mult = setting("elite_strength", 300) / 100
    local now = try(game.entities.set_stats, {entity = id})
    local before = type(now) == "table" and type(now.current) == "table" and tonumber(now.current.damage_scale) or 1
    local stats = {entity = id, damage_scale = clamp(before * 1.5, 0, 10)}
    if type(health.maximum) == "number" then stats.max_hp = math.max(1, math.min(1000000, math.floor(health.maximum * mult + 0.5))) end
    if type(combat.reward_exp) == "number" then stats.reward_exp = math.min(32767, combat.reward_exp * 5) end
    if type(combat.reward_money) == "number" then stats.reward_money = combat.reward_money * 5 end
    try(game.entities.set_stats, stats)
    try(game.entities.tint, {entity = id, color = {r = 255, g = 200, b = 60}, frames = 36000})
    elite = {entity = id, name = name_for(key), key = key}
    local c = type(m.position) == "table" and m.position or nil
    if c then
      local function at(dx, dz) return {c.x + dx, c.y or 0, c.z + dz} end
      local mid = at(0, 0)
      elite.beat = {at(220, 0), mid, at(0, 220), mid, at(-220, 0), mid, at(0, -220), mid}
    end
    toast(string.format("Vigil: %s walks this floor.", elite.name), 240)
  end

  moonmod.on("game.dungeon.generated", function(e)
    if type(e) == "table" and e.back_floor then return end
    elite, slain_key, sighted = nil, nil, nil
    drop_bar()
  end)
  moonmod.on("game.dungeon.zone_entered", function()
    elite, slain_key, sighted = nil, nil, nil
    drop_bar()
  end)

  moonmod.on("game.tick", function()
    clock = clock + 1
    if clock % 40 ~= 0 or not in_dungeon or not elite_on() then return end
    local q = try(game.entities.query, {type = "monster"})
    if type(q) ~= "table" or type(q.entities) ~= "table" then return end
    -- Its beat: a cross of four legs from where it was crowned, back through the middle each time (Enemies that fight
    -- like it, above, walks it while the player is far off). Only families with a brain walk one.
    if elite and elite.beat and setting("elite_patrols", true) then
      local mind = minds[elite.entity]
      if mind and not mind.beat then mind.beat = elite.beat end
    end
    if not elite then
      local key = floor_key()
      if not key or key == slain_key then return end
      if floor_seeds()[key] == true then slain_key = key return end
      for _, m in ipairs(q.entities) do
        local normal = type(m.definition) ~= "table" or m.definition.kind == 0
        if m.entity_id and m.revealed and normal and m.character == nil and not STORY_BOSS[m.native_model_id] then
          -- The second time it is seen, after floor scaling (every 30 frames) has scaled it.
          if sighted == m.entity_id then
            crown(m, key)
          else
            sighted = m.entity_id
          end
          break
        end
      end
      if not elite then return end
    end
    for _, m in ipairs(q.entities) do
      if m.entity_id == elite.entity then
        local health = type(m.health) == "table" and m.health or {}
        if m.revealed and type(health.current) == "number" and type(health.maximum) == "number" and health.maximum > 0 then
          try(game.render.bar_register, {id = "elite", label = elite.name:upper():sub(1, 24),
                                         current = clamp(health.current, 0, health.maximum), max = health.maximum})
        end
        return
      end
    end
  end)

  moonmod.on("game.enemy_defeated", function(e)
    if not elite or type(e) ~= "table" or e.entity ~= elite.entity then return end
    local seeds = floor_seeds()
    seeds[elite.key] = true
    if floors.key then try(game.save.set, floors.key, seeds) end
    slain_key = elite.key
    toast(string.format("Vigil: %s has fallen.", elite.name), 240)
    if later.elite_gear then later.elite_gear(floor_now and floor_now.dungeon_id, elite.name) end
    if later.loot_elite_drop and (later.sky_rank("fortunes_favour") > 0 or math.random(100) <= 35 + 10 * later.cycle_now()) then
      later.loot_elite_drop(elite.name)
    end
    if later.give_embers then later.give_embers(1, elite.name) end
    if later.elite_fell then later.elite_fell(elite) end -- Georama as a hub, below
    elite = nil
    drop_bar()
  end)
end

-- NG+ (§12, stretch goal 15): the Dark Genie's fall readies a new cycle, begun by praying at any shrine. Every kept map
-- is forgotten (new seeds, new chests, new elites, shrines to light again), while the tree, the gear and the levels
-- stay. Each cycle past the first makes monsters half again as hardy, a quarter again as hard-hitting, and pays half
-- again as much (zone_scaling reads later.cycle_now), and an elite's drop is rolled once more for each cycle.
later.cycle_now = function()
  local c = floor_seeds().cycle
  return type(c) == "number" and c or 0
end
do
  moonmod.on("game.enemy_defeated", function(e)
    if in_sandbox or type(e) ~= "table" or e.native_model_id ~= 106 or not setting("ng_plus", true) then return end
    local seeds = floor_seeds()
    if seeds.cycle_ready then return end
    seeds.cycle_ready = true
    if floors.key then try(game.save.set, floors.key, seeds) end
    toast("Vigil: the Dark Genie is gone. Pray at any shrine to begin the next cycle.", 420)
  end)

  later.next_cycle = function()
    local seeds = floor_seeds()
    if not seeds.cycle_ready then return false end
    local places = {}
    for k in pairs(seeds) do
      if type(k) == "string" and (k:match("^%d+:%d+$") or k:match(":elite$") or k:match(":ambush$") or k:match(":note$") or k:match("^rest:")) then places[#places + 1] = k end
    end
    for _, k in ipairs(places) do
      if k:match("^%d+:%d+$") then forget_place(seeds, k) else seeds[k] = nil end
    end
    seeds.cycle, seeds.cycle_ready = later.cycle_now() + 1, nil
    seeds.embers = later.embers() + 3
    if floors.key then try(game.save.set, floors.key, seeds) end
    toast(string.format("Vigil: cycle %d begins. Every map is new, and all in them stronger.", seeds.cycle + 1), 420)
    return true
  end
end

-- Ambushes (§12, stretch goal 9): about one zone in three of a kept map is an ambush, chosen by its key. A moment
-- after you walk into it, monsters of the floor drop in around you in a cloud of dust: from above, landing in a puff. A
-- sprung ambush is kept with the floor, so it doesn't happen twice.
do
  local STORY_BOSS = {[78] = true, [79] = true, [80] = true, [81] = true, [82] = true, [83] = true, [84] = true, [106] = true}
  local DROP = 70 -- how far above the floor they start
  local armed, clock, variants = nil, 0, {}
  local dropping = {} -- {handle, at, t}: a monster falling, `t` ticks in
  local shut -- {pack = {handle = true}, left, until}: the room shut on a sprung ambush, until the pack is dead

  local function release(word)
    if not shut then return end
    shut = nil
    try(game.dungeons.room_release)
    if word then toast(word, 150) end
  end

  local function variant(model)
    if variants[model] then return variants[model] end
    local r = try(game.characters.register, {id = "ambush-" .. model, kind = "enemy", name = "Ambusher", template_monster_id = model})
    variants[model] = r and r.id or (ID .. ":ambush-" .. model)
    return variants[model]
  end

  local function spring()
    local p = try(game.player.get)
    local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
    -- On or beside a ramp (height steps) the ring around the player isn't level: it waits until they are off it.
    local zg = at and try(game.dungeons.zones_get)
    for _, r in ipairs(type(zg) == "table" and type(zg.ramps) == "table" and zg.ramps or {}) do
      if math.abs(160 * r.x - at.x) <= 240 and math.abs(160 * r.y - at.z) <= 240 then armed.at = clock + 30 return end
    end
    local key = armed.key
    armed = nil
    local q = try(game.entities.query, {type = "monster"})
    if type(q) ~= "table" or type(q.entities) ~= "table" or not at then return end
    local models = {}
    for _, m in ipairs(q.entities) do
      if m.native_model_id and not STORY_BOSS[m.native_model_id] and m.character == nil then models[#models + 1] = m.native_model_id end
    end
    if #models == 0 then return end
    local n, spawned, pack = clamp(setting("ambush_size", 3), 1, 6), 0, {}
    for i = 1, n do
      local a = (i / n) * 2 * math.pi + 0.4
      local there = {x = at.x + 70 * math.cos(a), y = at.y, z = at.z + 70 * math.sin(a)}
      local drop = setting("ambush_drops", true)
      local s = try(game.characters.spawn, {character = variant(models[(i - 1) % #models + 1]),
                                            position = drop and {x = there.x, y = there.y + DROP, z = there.z} or there})
      if s then
        spawned = spawned + 1
        local handle = type(s) == "table" and (s.entity_handle or s.id)
        if handle then pack[handle] = true end
        if drop and handle then
          dropping[#dropping + 1] = {handle = handle, at = there, t = -3 * i}
        else
          try(game.effects.burst, {kind = "smoke", position = {x = there.x, y = there.y + 10, z = there.z}, scale = 1.4})
        end
      end
    end
    if spawned == 0 then return end
    -- The room shuts behind you until the pack is dead (a minute and a half at most, should one get stuck in a wall).
    local sealed = setting("ambush_rooms", true) and try(game.dungeons.room_seal, {})
    if type(sealed) == "table" and sealed.sealed then
      local left = 0
      for _ in pairs(pack) do left = left + 1 end
      shut = {pack = pack, left = left, ["until"] = clock + 5400}
      toast("Vigil: an ambush! The way is shut.", 150)
    else
      toast("Vigil: an ambush!", 150)
    end
    local seeds = floor_seeds()
    seeds[key] = true
    if floors.key then try(game.save.set, floors.key, seeds) end
  end

  moonmod.on("game.dungeon.zone_entered", function(e)
    armed = nil
    if in_sandbox or type(e) ~= "table" or type(e.zone) ~= "number" or e.previous == -1 or not floor_now or not zoned_floor(floor_now) or
       not setting("ambushes", true) then
      return
    end
    local key = string.format("%s:%d:ambush", place_key(floor_now.dungeon_id, floor_now.floor_id), e.zone)
    if floor_seeds()[key] then return end
    local h = 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 1000003 end
    if h % 3 == 0 then armed = {key = key, at = clock + 90} end
  end)
  moonmod.on("game.dungeon.generated", function() armed, shut, dropping = nil, nil, {} end)
  moonmod.on("game.enemy_defeated", function(e)
    if not shut or type(e) ~= "table" or not shut.pack[e.entity] then return end
    shut.pack[e.entity] = nil
    shut.left = shut.left - 1
    if shut.left <= 0 then release("Vigil: the way opens.") end
  end)
  moonmod.on("game.tick", function()
    clock = clock + 1
    if armed and clock >= armed.at then spring() end
    if shut and clock >= shut["until"] then release("Vigil: the way opens.") end
    -- Falling: left alone, a monster off the floor only eases down over seconds, and a speed of its own carries it
    -- through the floor. So each tick it falls faster (0.3 a tick more: 70 units in about 23 ticks), never past the
    -- floor, and once down it stops in a puff of dust and its own script walks it from there.
    if #dropping > 0 then
      local q = try(game.entities.query, {type = "monster"})
      local y = {}
      for _, m in ipairs(type(q) == "table" and type(q.entities) == "table" and q.entities or {}) do
        if m.entity_id and type(m.position) == "table" then y[m.entity_id] = m.position.y end
      end
      for i = #dropping, 1, -1 do
        local d = dropping[i]
        d.t = d.t + 1
        local above = y[d.handle] and (y[d.handle] - d.at.y)
        if d.t > 0 and (not above or above <= 0.5 or d.t > 90) then
          table.remove(dropping, i)
          if above then try(game.physics.velocity_set, {entity = d.handle, velocity = {x = 0, y = 0, z = 0}}) end
          try(game.effects.burst, {kind = "smoke", position = {x = d.at.x, y = d.at.y + 4, z = d.at.z}, scale = 1.6})
        elseif d.t > 0 then
          try(game.physics.velocity_set, {entity = d.handle, velocity = {x = 0, y = -math.min(0.5 + 0.3 * d.t, above), z = 0}})
        else
          try(game.physics.velocity_set, {entity = d.handle, velocity = {x = 0, y = 0, z = 0}}) -- held a beat, in turn
        end
      end
    end
  end)
end

-- Messages, offline (§12, stretch goal 17): the first time you reach a shrine, a note left by someone who came before
-- is scratched beside it: a warning, a tip or a line of lore, the same at that shrine every time. The online half
-- (notes players leave for each other) waits for DC_Web.
do
  local NOTES = {
    [0] = {"Dran's breath can be outrun. His tail can't.", "Guard first. Swing second. Live third.",
           "The Fairy King lies about nothing. He just leaves things out.", "Try rolling through, not away.",
           "A named one walks these halls. Don't fight it tired."},
    [1] = {"The trees here listen. Walk softly.", "Master Utan hits hardest when he's standing still.",
           "Poise breaks on the third blow. Count.", "Turn back? No. Rest first."},
    [2] = {"Salt water rusts more than blades.", "She freezes what she cannot break. Keep moving.",
           "Behind you. Always behind you.", "The flask spills if you drink in reach."},
    [3] = {"The curse is patient. Be more patient.", "Light the shrine. Then decide.", "Ambush ahead. Or not. Who knows."},
    [4] = {"The Minotaur charges straight. Step aside.", "Stone remembers the sea.", "Heavy blows break guards."},
    [5] = {"Time loops here. So will you.", "The Genie keeps his promises. That's the problem.", "Don't rest. Don't stop."},
  }
  moonmod.on("game.dungeon.shrine_reached", function(e)
    if in_sandbox or type(e) ~= "table" or type(e.zone) ~= "number" or not floor_now or not zoned_floor(floor_now) or
       not setting("notes", true) then
      return
    end
    local key = string.format("%s:%d:note", place_key(floor_now.dungeon_id, floor_now.floor_id), e.zone)
    local seeds = floor_seeds()
    if seeds[key] then return end
    local list = NOTES[floor_now.dungeon_id] or NOTES[0]
    local h = 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 1000003 end
    seeds[key] = true
    if floors.key then try(game.save.set, floors.key, seeds) end
    toast("A note, scratched beside the spring: \"" .. list[h % #list + 1] .. "\"", 360)
  end)
end

-- Messages, online (§12, stretch goal 17): players leave each other short messages at a shrine, built from a phrase
-- and a word, and rate the ones they read. They travel through the messages folder (messages.*): a player who points
-- it at a folder a sync service shares reads their friends' messages at the same shrines, whatever their maps look
-- like. Only a message that is one of these phrases with one of these words is ever shown.
do
  local PHRASES = {"%s ahead", "Beware %s", "Try %s", "Could this be %s?", "%s, at last", "No %s here"}
  local WORDS = {"an ambush", "a named one", "a locked gate", "a ledge", "the dark", "treasure", "a shortcut", "rolling",
                 "guarding", "the flask", "patience", "a strong foe", "an easy way", "a mimic", "rest"}
  local function say(phrase, word)
    local text = phrase:format(word)
    return text:sub(1, 1):upper() .. text:sub(2)
  end
  local shown = {}
  for _, phrase in ipairs(PHRASES) do
    for _, word in ipairs(WORDS) do shown[say(phrase, word)] = true end
  end
  local PAGE = 5
  local menu, phrase_at, word_page, reading = {}, nil, 1, nil
  local pending, clock = nil, 0

  -- The shrine the panel is open at, as a place every player's map has: its dungeon and floor (a region's zone is
  -- its floor), never the cell, since each save builds its own maps.
  local function place()
    if not shrine_at then return nil end
    if shrine_at.label then return string.format("vigil:d%d:f%d:shrine", shrine_at.dungeon_id, shrine_at.label) end
    return string.format("vigil:d%d:f%dz%d:shrine", shrine_at.dungeon_id, shrine_at.floor_id, shrine_at.zone)
  end

  -- The messages at the shrine Vigil would show: its own phrases only, and none rated well under water.
  local function here()
    local p = place()
    local r = p and try((game.messages or {}).list, {place = p})
    local list, others, mine = {}, 0, 0
    for _, m in ipairs(type(r) == "table" and type(r.messages) == "table" and r.messages or {}) do
      if type(m) == "table" and shown[m.text] and (m.mine or (m.good or 0) - (m.poor or 0) > -3) then
        list[#list + 1] = m
        if m.mine then mine = mine + 1 else others = others + 1 end
      end
    end
    return list, others, mine, type(r) == "table" and r.shared
  end

  later.messages_card = function()
    if not setting("messages", true) or not place() then return nil end
    local _, others, mine = here()
    return {title = "Messages", lines = {
      others > 0 and string.format("%d left here by others.", others) or {text = "None left here by others.", tone = "dim"},
      mine > 0 and {text = string.format("%d of yours.", mine), tone = "gold"} or "Leave one for whoever comes."}}
  end

  local function open_words()
    local options, first = {}, (word_page - 1) * PAGE
    for i = first + 1, math.min(first + PAGE, #WORDS) do
      options[#options + 1] = {title = say(PHRASES[phrase_at], WORDS[i])}
    end
    if #WORDS > PAGE then options[#options + 1] = {title = "More", lines = {{text = "Other words.", tone = "dim"}}} end
    try(game.ui.choice_open, {id = "vigil.msg_word", title = "Leave a message", subtitle = "Pick a word.", cancel = true, options = options})
  end

  local function open_reading()
    local m = reading and reading.list[reading.i]
    if not m then reading = nil return end
    local good = {string.format("%d found it good.", m.good or 0)}
    if m.rated == 1 then good[2] = {text = "You rated it good.", tone = "gold"} end
    local poor = {string.format("%d found it poor.", m.poor or 0)}
    if m.rated == -1 then poor[2] = {text = "You rated it poor.", tone = "gold"} end
    try(game.ui.choice_open, {id = "vigil.msg_read", title = "\"" .. m.text .. "\"", cancel = true,
      subtitle = string.format("Message %d of %d", reading.i, #reading.list), options = {
        {title = "Good", lines = good}, {title = "Poor", lines = poor},
        {title = reading.i < #reading.list and "Next" or "Done"}}})
  end

  later.messages_open = function()
    local _, others, mine, shared = here()
    menu = {}
    local options = {{title = "Leave one", lines = {"A phrase and a word, left by this spring."}}}
    menu[1] = "leave"
    if others > 0 then
      options[#options + 1] = {title = "Read", lines = {string.format("%d here, best rated first.", others), "Rate each good or poor."}}
      menu[#options] = "read"
    end
    if mine > 0 then
      options[#options + 1] = {title = "Take back", lines = {string.format("Yours here: %d.", mine), {text = "The newest goes.", tone = "dim"}}}
      menu[#options] = "take"
    end
    try(game.ui.choice_open, {id = "vigil.msg_menu", title = "Messages", cancel = true, options = options,
      subtitle = shared and "Seen by anyone who shares your messages folder." or "Kept in your save until you choose a shared folder."})
  end

  moonmod.on("ui.choice_made", function(e)
    if type(e) ~= "table" or e.cancelled or type(e.index) ~= "number" or type(e.id) ~= "string" or not e.id:find("^vigil%.msg_") then return end
    if e.id == "vigil.msg_menu" then
      local what = menu[e.index]
      if what == "leave" then
        local options = {}
        for i, phrase in ipairs(PHRASES) do options[i] = {title = say(phrase, "...")} end
        try(game.ui.choice_open, {id = "vigil.msg_phrase", title = "Leave a message", subtitle = "Pick a phrase.", cancel = true, options = options})
      elseif what == "read" then
        reading = {list = {}, i = 1}
        for _, m in ipairs((here())) do if not m.mine then reading.list[#reading.list + 1] = m end end
        open_reading()
      elseif what == "take" then
        local newest = nil
        for _, m in ipairs((here())) do if m.mine and (not newest or (m.at or 0) > (newest.at or 0)) then newest = m end end
        if newest and try((game.messages or {}).remove, {id = newest.id}) then toast("Vigil: your message \"" .. newest.text .. "\" is taken back.", 240) end
      end
    elseif e.id == "vigil.msg_phrase" and PHRASES[e.index] then
      phrase_at, word_page = e.index, 1
      open_words()
    elseif e.id == "vigil.msg_word" and phrase_at then
      local i = (word_page - 1) * PAGE + e.index
      if e.index > PAGE or i > #WORDS then
        word_page = word_page % math.ceil(#WORDS / PAGE) + 1
        open_words()
        return
      end
      local text, p = say(PHRASES[phrase_at], WORDS[i]), place()
      local r = p and try((game.messages or {}).post, {place = p, text = text})
      if type(r) == "table" then
        toast("Vigil: \"" .. text .. "\" is left by the spring. " .. (r.shared and "Anyone who shares your messages folder can read it."
              or "It stays in your save until you choose a shared messages folder."), 360)
      end
    elseif e.id == "vigil.msg_read" and reading then
      local m = reading.list[reading.i]
      if e.index <= 2 and m then
        local rating = e.index == 1 and 1 or -1
        if m.rated == rating then rating = 0 end -- the same again takes it back
        if try((game.messages or {}).rate, {id = m.id, rating = rating}) then
          if m.rated == 1 then m.good = (m.good or 1) - 1 elseif m.rated == -1 then m.poor = (m.poor or 1) - 1 end
          if rating == 1 then m.good = (m.good or 0) + 1 elseif rating == -1 then m.poor = (m.poor or 0) + 1 end
          m.rated = rating
        end
      end
      reading.i = reading.i + 1
      open_reading()
    end
  end)

  -- Reaching a shrine, the best rated message there from someone else comes up after any note scratched beside it.
  moonmod.on("game.dungeon.shrine_reached", function(e)
    if in_sandbox or type(e) ~= "table" or not setting("messages", true) or not shrine_at or shrine_at.zone ~= e.zone then return end
    pending = clock + 400
  end)
  moonmod.on("game.tick", function()
    clock = clock + 1
    if not pending or clock < pending then return end
    pending = nil
    for _, m in ipairs((here())) do
      if not m.mine then
        toast(string.format("A message by the spring: \"%s\"%s", m.text,
              (m.good or 0) > 0 and string.format(" (%d found it good)", m.good) or ""), 300)
        return
      end
    end
  end)
end

-- Shortcuts (§12, stretch goal 11): each floor of a kept map has two shortcut doors (dungeons.set_shortcuts), locked
-- from the far side of a dead end, the key in a chest there. A door once opened is built open on later visits
-- ("d:f:doors", the key items), the way zone gates are, so the long way round is walked once.
do
  local here = nil -- the place the floor being built is kept under, while shortcuts are on
  moonmod.on("game.dungeon.generating", function(e)
    here = nil
    if in_sandbox or type(e) ~= "table" or e.back_floor or not setting("shortcuts", true) or not zoned_floor(e) then
      try(game.dungeons.set_shortcuts, {count = 0})
      return
    end
    here = place_key(e.dungeon_id, e.floor_id)
    local seeds = floor_seeds()
    local open, walls = seeds[here .. ":doors"], seeds[here .. ":walls"]
    -- Illusory walls (§12, stretch goal 12): one more shortcut a floor, drawn as a plain wall a blow opens.
    local illusory = setting("illusory_walls", true) and 1 or nil
    try(game.dungeons.set_shortcuts, {count = 2, open = type(open) == "table" and #open > 0 and open or nil, illusory = illusory,
                                      open_walls = illusory and type(walls) == "table" and #walls > 0 and walls or nil})
  end)
  moonmod.on("game.dungeon.wall_opened", function(e)
    if not here or type(e) ~= "table" or math.type(e.wall) ~= "integer" then return end
    local seeds = floor_seeds()
    local list = type(seeds[here .. ":walls"]) == "table" and seeds[here .. ":walls"] or {}
    for _, n in ipairs(list) do if n == e.wall then return end end
    list[#list + 1] = e.wall
    seeds[here .. ":walls"] = list
    if floors.key then try(game.save.set, floors.key, seeds) end
    toast("Vigil: the wall was never there.", 200)
    if later.elite_gear then later.elite_gear(floor_now and floor_now.dungeon_id, "Behind it, someone") end
  end)
  moonmod.on("game.dungeon.door_opened", function(e)
    local item = here and type(e) == "table" and tonumber(tostring(e.key):match("(%d+)$"))
    if not item then return end
    local seeds = floor_seeds()
    local list = type(seeds[here .. ":doors"]) == "table" and seeds[here .. ":doors"] or {}
    for _, k in ipairs(list) do if k == item then return end end
    list[#list + 1] = item
    seeds[here .. ":doors"] = list
    if floors.key then try(game.save.set, floors.key, seeds) end
    toast("Vigil: a shortcut opens. The way back is shorter now.", 200)
  end)
end

-- Vigil Trial (§12, stretch goal 16): a title mode to fight any story boss with Vigil's rules, for practice and for
-- tuning. Pick a boss (Dran to the Dark Genie) and a hero; the session starts on an empty floor of Divine Beast Cave (registered below, no
-- monsters of its own), the party armed and toughened for that boss's place in the story, and the boss comes out
-- in front of you with its cast, its card, its bar and its second phase (Story bosses, above). Best times are kept.
do
  local MODE = "vigil_trial"
  local TRIALS = {
    {key = "dran", model = 78, name = "Dran", grounded = true, life = 737, scale = 0.65, tier = 1},
    {key = "utan", model = 79, name = "Master Utan", life = 2065, tier = 2},
    {key = "queen", model = 80, name = "Ice Queen", life = 2065, tier = 3, cast = {101, 76, 102, 103, 92, 104, 104, 104}},
    {key = "curse", model = 81, name = "King's Curse", life = 5899, tier = 4, cast = {82}},
    {key = "joe", model = 83, name = "Minotaur Joe", life = 5899, tier = 5, cast = {91, 91, 91}},
    -- The Dark Genie's elemental form with all its helpers (shades, pillars, shockwaves and beam), as the Gauntlet's
    -- finale brings it.
    {key = "genie", model = 106, name = "Dark Genie", life = 7500, tier = 6, cast = {105, 105, 107, 107, 108, 108, 109, 110}},
    -- Named elites, one for each place in the story, each of a family with an enemy brain (Enemies that fight, above):
    -- gold, half again the bite, the life of a crowned one of its dungeon, and a bar of its own.
    {key = "garrow", model = 1, name = "Garrow the Unbowed", elite = "Skeleton Soldier", life = 360, tier = 1},
    {key = "velka", model = 4, name = "Velka Moon-Eater", elite = "Werewolf", life = 900, tier = 2},
    {key = "oskar", model = 23, name = "Oskar the Oathless", elite = "Captain", life = 1500, tier = 3},
    {key = "morwen", model = 44, name = "Morwen the Hollow", elite = "Mummy", life = 2600, tier = 4},
    {key = "aldric", model = 10, name = "Aldric Who Waits", elite = "Sunday", life = 3600, tier = 5},
    {key = "sable", model = 39, name = "Sable the Last Watch", elite = "Club", life = 4800, tier = 6},
  }
  local HEROES = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
  local HERO_NAMES = {toan = "Toan", xiao = "Xiao", goro = "Goro", ruby = "Ruby", ungaga = "Ungaga", osmond = "Osmond"}
  -- A weapon's base attack at most, and max HP, for each place in the story.
  local ATTACK_CAP = {28, 48, 70, 95, 130, 170}
  local HP = {120, 220, 330, 450, 600, 760}
  local arena -- the trial floor's stable id, once registered
  local pick = {boss = 1, hero = 1}
  local fight -- {trial, entered, boss, started} while a trial runs
  local best = {}

  local reg = game.dungeons and try(game.dungeons.register, {id = "vigil-trial", name = "Vigil Trial", dungeon = 0,
                                          floors = {{id = "arena", name = "Trial Arena", source_floor = 12, enemies = {}}}})
  if type(reg) ~= "table" and game.dungeons then reg = try(game.dungeons.get, "vigil-trial") end
  if type(reg) == "table" and type(reg.floors) == "table" and type(reg.floors[1]) == "table" then arena = reg.floors[1].id end
  local kept = moonmod.storage and try(moonmod.storage.get, "trial_best")
  if type(kept) == "table" then best = kept end

  local function seconds(frames) return string.format("%d:%02d", frames // 3600, (frames // 60) % 60) end

  local function page()
    -- The boss and the hero each cycle on Cross (a page holds seven entries, and there are more bosses than that leaves).
    local t = TRIALS[pick.boss]
    local b = best[t.key]
    local entries = {{id = "boss", label = (t.elite and "Elite: " or "Boss: ") .. t.name .. (b and ("  (best " .. seconds(b) .. ")") or "")}}
    entries[#entries + 1] = {id = "hero", label = "Hero: " .. HERO_NAMES[HEROES[pick.hero]]}
    entries[#entries + 1] = {id = "start", label = "Begin the Trial", enabled = arena ~= nil}
    return {id = MODE, label = "Vigil Trial", title = "VIGIL TRIAL", subtitle = "Any story boss, with Vigil's rules.",
            hint = "", root = true, entries = entries,
            lines = {"Pick a boss or a named elite and a hero, then begin.", "The party is armed for the foe's place in the story.",
                     arena and "" or "The arena floor could not be registered."}}
  end
  if setting("trial", true) and game.title then try(game.title.mode_register, page()) end

  moonmod.on("game.title.selected", function(e)
    if type(e) ~= "table" or e.mode ~= MODE or e.entry == "back" then return end
    if e.entry == "boss" then pick.boss = pick.boss % #TRIALS + 1
    elseif e.entry == "hero" then pick.hero = pick.hero % #HEROES + 1
    elseif e.entry == "start" and arena then
      fight = {trial = TRIALS[pick.boss], hero = HEROES[pick.hero]}
      floors.trial = true
      if not call(game.session and game.session.start, {floor = arena, party_size = 6, character = fight.hero}) then
        fight, floors.trial = nil, nil
        toast("Vigil: the Trial could not start.", 200)
      end
      return
    end
    local p = page()
    p.cursor = (tonumber(e.index) or 0)
    if game.title then try(game.title.mode_set, {id = MODE, entries = p.entries, cursor = p.cursor}) end
  end)

  -- Arm the party for the boss's place: each hero's strongest weapon under the cap, and the life for it.
  local function arm(tier)
    local list = try(game.weapons.list)
    for _, who in ipairs(HEROES) do
      local top, top_attack
      for _, w in ipairs(type(list) == "table" and list or {}) do
        local a = type(w) == "table" and type(w.stats) == "table" and tonumber(w.stats.attack)
        if a and w.owner == who and not w.mod_owned and a <= ATTACK_CAP[tier] and (not top_attack or a > top_attack) then
          top, top_attack = w.id, a
        end
      end
      if top then
        local given = call(game.weapons.give, {id = top, character = who})
        if given then try(game.weapons.equip, {id = top, character = who, slot = given.slot}) end
      end
      try(game.player.set, {max_hp = HP[tier], character = who})
      try(game.player.set, {hp = HP[tier], character = who})
    end
  end

  local variants = {}
  local function variant(model)
    if variants[model] then return variants[model] end
    local r = try(game.characters.register, {id = "trial-" .. model, kind = "enemy", name = "Trial", template_monster_id = model})
    variants[model] = r and r.id or (ID .. ":trial-" .. model)
    return variants[model]
  end

  local function bring(t)
    local p = try(game.player.get)
    local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
    if not at then return false end
    local h = type(p.heading) == "number" and p.heading or 0
    local there = {x = at.x + 140 * math.sin(h), y = at.y, z = at.z + 140 * math.cos(h)}
    if t.elite then
      local s = call(game.characters.spawn, {character = variant(t.model), position = there})
      local handle = type(s) == "table" and (s.entity_handle or s.id)
      if not handle then return false end
      try(game.entities.set_stats, {entity = handle, max_hp = t.life, hp = t.life, damage_scale = 1.5, hit_share = true})
      try(game.entities.tint, {entity = handle, color = {r = 255, g = 200, b = 60}, frames = 36000})
      toast(string.format("Vigil Trial: %s, a %s, comes for you.", t.name, t.elite), 200)
      fight.boss = handle
      return true
    end
    local s = call(game.characters.spawn, {character = variant(t.model), position = there, arena_origin = there, arena_slot = 0,
                                           grounded = t.grounded})
    local handle = type(s) == "table" and (s.entity_handle or s.id)
    if not handle then return false end
    try(game.entities.set_stats, {entity = handle, max_hp = t.life, hp = t.life, hit_share = true})
    if t.scale then try(game.entities.scale_set, {entity = handle, scale = t.scale}) end
    for n, model in ipairs(t.cast or {}) do
      local c = call(game.characters.spawn, {character = variant(model), position = there, arena_origin = there, arena_slot = n,
                                             grounded = t.grounded})
      local ch = type(c) == "table" and (c.entity_handle or c.id)
      if ch then try(game.entities.set_stats, {entity = ch, hit_share = true}) end
    end
    fight.boss = handle
    return true
  end

  local clock = 0
  moonmod.on("game.session.started", function(e)
    if not fight or type(e) ~= "table" or e.owner ~= ID then fight, floors.trial = nil, nil return end
    fight.entered = nil
  end)
  moonmod.on("game.session.ended", function(e)
    if fight and type(e) == "table" and e.reason == "defeat" then toast("Vigil: the Trial is lost.", 200) end
    if fight and fight.trial.elite then try(game.render.bar_remove, {id = "elite"}) end
    fight, floors.trial = nil, nil
    if setting("trial", true) and game.title then try(game.title.mode_register, page()) end
  end)
  moonmod.on("game.tick", function()
    clock = clock + 1
    if not fight or not in_dungeon then return end
    if not fight.entered then
      fight.entered = clock
      arm(fight.trial.tier)
      toast(string.format("Vigil Trial: %s. Ready yourself.", fight.trial.name), 180)
    elseif not fight.boss and clock - fight.entered >= 180 and clock % 30 == 0 then
      if bring(fight.trial) then fight.started = clock end
    elseif fight.boss and fight.trial.elite and not fight.won and clock % 15 == 0 then
      -- An elite has no story boss's bar: its own, by name, as a crowned one's.
      local q = try(game.entities.query, {type = "monster"})
      for _, m in ipairs(type(q) == "table" and type(q.entities) == "table" and q.entities or {}) do
        local health = type(m.health) == "table" and m.health or {}
        if m.entity_id == fight.boss and type(health.current) == "number" and type(health.maximum) == "number" and health.maximum > 0 then
          try(game.render.bar_register, {id = "elite", label = fight.trial.name:upper():sub(1, 24),
                                         current = clamp(health.current, 0, health.maximum), max = health.maximum})
        end
      end
    end
  end)
  moonmod.on("game.enemy_defeated", function(e)
    if not fight or not fight.boss or type(e) ~= "table" or e.entity ~= fight.boss then return end
    local t, took = fight.trial, clock - (fight.started or clock)
    local record = not best[t.key] or took < best[t.key]
    if record then
      best[t.key] = took
      if moonmod.storage then try(moonmod.storage.set, "trial_best", best) end
    end
    toast(string.format("Vigil Trial: %s falls in %s%s.", t.name, seconds(took), record and ", a best time" or ""), 300)
    if t.elite then try(game.render.bar_remove, {id = "elite"}) end
    fight.won = clock
  end)
  moonmod.on("game.tick", function()
    if fight and fight.won and clock - fight.won >= 300 then
      fight.won = nil
      try(game.session and game.session.finish)
    end
  end)
end

-- Georama as a hub (§12, stretch goal 13): three townsfolk are held in the dungeons, each by a named elite. The first
-- elite to fall in Divine Beast Cave frees Gorm the smith, in Wise Owl Forest Ysolde the trader, in the Shipwreck
-- Old Harl the seeker; each stands beside you, and walking up to them sends them home. In town, D-pad Up (or H)
-- calls the folk you saved: the smith reinforces your weapon, the trader sells gear, the seeker sets a hunt for named
-- elites and pays for it. Kept with the save ("hub").
do
  local FOLK = {
    -- Each wears a villager of the town nearest the dungeon that held them (Norune, Matataki, Queens).
    [0] = {id = "smith", name = "Gorm the smith", model = "gedit/e01/chara/p05a.chr",
           lines = {"\"Steel remembers every blow. So should you.\"", "\"Bring me Gilda and I'll bring you an edge.\"",
                    "\"That cave nearly had me. Didn't have you.\""}},
    [1] = {id = "trader", name = "Ysolde the trader", model = "gedit/e02/chara/p24a.chr",
           lines = {"\"I find things. Dead men don't need boots.\"", "\"The deeper you go, the better I trade.\"",
                    "\"Owls watched me for nine days in that forest.\""}},
    [2] = {id = "seeker", name = "Old Harl the seeker", model = "gedit/e03/chara/p36a.chr",
           lines = {"\"Names are carved on the deep ones. I collect names.\"", "\"The sea gave me back. It wants something for it.\"",
                    "\"Three more, and I'll sleep tonight.\""}},
  }
  local FALLBACK_MODEL = "gedit/e01/chara/p02a.chr"
  local visits = 0
  local REINFORCE, WARES, HUNT, BOUNTY = 500, 400, 3, 800
  local waiting -- the folk standing on this floor, waiting to be walked up to
  local in_town, bound = false, false

  local function hub()
    local seeds = floor_seeds()
    if type(seeds.hub) ~= "table" then seeds.hub = {rescued = {}} end
    if type(seeds.hub.rescued) ~= "table" then seeds.hub.rescued = {} end
    return seeds.hub, seeds
  end
  local function keep(seeds) if floors.key then try(game.save.set, floors.key, seeds) end end
  local function hub_on() return setting("hub", true) and not in_sandbox and not floors.trial end

  -- A named elite fell (Named elites, above): its dungeon's folk come out, and the seeker's hunt counts it.
  later.elite_fell = function()
    if not hub_on() or not floor_now then return end
    local h, seeds = hub()
    if type(h.quest) == "table" and not h.quest.done then
      h.quest.have = math.min(h.quest.need, (h.quest.have or 0) + 1)
      if h.quest.have >= h.quest.need then toast("Vigil: the hunt is done. Old Harl will pay you in town.", 240) end
    end
    local folk = FOLK[floor_now.dungeon_id]
    if folk and not h.rescued[folk.id] and not waiting then
      if try(game.world.dungeon_npc_set, {id = folk.id, model = folk.model, place = "player"}) or
         try(game.world.dungeon_npc_set, {id = folk.id, model = FALLBACK_MODEL, place = "player"}) then
        waiting = folk
        toast(string.format("Vigil: %s was held here. Walk up to them.", folk.name), 300)
      end
    end
    keep(seeds)
  end

  moonmod.on("game.dungeon_npc.near", function(e)
    if not waiting or type(e) ~= "table" or e.id ~= waiting.id then return end
    local h, seeds = hub()
    h.rescued[waiting.id] = true
    keep(seeds)
    toast(string.format("%s: \"I'll go home. Find me in town, D-pad Up.\"", waiting.name), 300)
    try(game.world.dungeon_npc_clear)
    waiting = nil
  end)
  moonmod.on("game.dungeon.generated", function() waiting = nil end)

  local function cards()
    local h = hub()
    local options, ids = {}, {}
    if h.rescued.smith then
      options[#options + 1] = {title = "Gorm", lines = {"Reinforce your weapon:", "+3 attack, mended.", {text = REINFORCE .. " Gilda", tone = "gold"}}}
      ids[#ids + 1] = "smith"
    end
    if h.rescued.trader then
      options[#options + 1] = {title = "Ysolde", lines = {"A piece of gear,", "the best of several.", {text = WARES .. " Gilda", tone = "gold"}}}
      ids[#ids + 1] = "trader"
    end
    if h.rescued.seeker then
      local q = h.quest
      local line = not q and {"A hunt: fell " .. HUNT .. " named", "foes, for " .. BOUNTY .. " Gilda."}
                   or (q.have or 0) >= q.need and {"The hunt is done.", {text = "Take " .. BOUNTY .. " Gilda.", tone = "good"}}
                   or {"The hunt: " .. (q.have or 0) .. " of " .. q.need, {text = "named foes felled.", tone = "dim"}}
      options[#options + 1] = {title = "Old Harl", lines = line}
      ids[#ids + 1] = "seeker"
    end
    return options, ids
  end

  local shown_ids
  local function open_hub()
    local options, ids = cards()
    if #options == 0 then toast("Vigil: nobody you've saved lives here yet.", 180) return end
    shown_ids = ids
    -- One of the folk speaks up, a different line each visit.
    visits = visits + 1
    local speaker
    for _, f in pairs(FOLK) do if f.id == ids[(visits - 1) % #ids + 1] then speaker = f end end
    local line = speaker and speaker.lines[(visits - 1) // #ids % #speaker.lines + 1] or "The folk you saved"
    try(game.ui.choice_open, {id = "vigil.hub", title = "Your town", subtitle = line, cancel = true, town = true,
                              options = options})
  end

  local function serve(what)
    local h, seeds = hub()
    if what == "smith" then
      local p = try(game.player.get)
      local w = type(p) == "table" and type(p.weapon) == "table" and p.weapon or nil
      if not w then return end
      if not call(game.economy.spend, {amount = REINFORCE}) then toast("Vigil: Gorm wants " .. REINFORCE .. " Gilda.", 200) return end
      try(game.weapons.stats_set, {id = w.id, character = p.character, slot = w.slot, attack = math.min(32767, (w.attack or 0) + 3)})
      if type(w.durability_max) == "number" then
        try(game.weapons.durability_set, {id = w.id, character = p.character, slot = w.slot, durability = w.durability_max})
      end
      toast("Gorm: \"There. It'll bite deeper now.\"", 220)
    elseif what == "trader" then
      if not call(game.economy.spend, {amount = WARES}) then toast("Vigil: Ysolde wants " .. WARES .. " Gilda.", 200) return end
      -- Her stock grows with how far down you have been: she trades in the deepest dungeon's gear you have reached.
      local deepest = 0
      for d = 0, 6 do if (floor_seeds()["rest:" .. d]) then deepest = d end end
      if later.elite_gear then later.elite_gear(math.max(deepest, floor_now and floor_now.dungeon_id or 0), "Ysolde sold you") end
    elseif what == "seeker" then
      local q = h.quest
      if not q or q.done then
        h.quest = {need = HUNT, have = 0}
        toast("Old Harl: \"Fell " .. HUNT .. " of the named ones below. I'll pay.\"", 240)
      elseif (q.have or 0) >= q.need then
        try(game.economy.add, {amount = BOUNTY})
        h.quest = nil
        toast("Old Harl: \"As promised.\" (" .. BOUNTY .. " Gilda)", 220)
      else
        toast(string.format("Old Harl: \"%d more.\"", q.need - (q.have or 0)), 180)
      end
      keep(seeds)
    end
  end

  moonmod.on("ui.choice_made", function(e)
    if type(e) ~= "table" or e.id ~= "vigil.hub" or e.cancelled or not shown_ids then return end
    local what = shown_ids[tonumber(e.index) or 0]
    if what then serve(what) end
  end)

  moonmod.on("game.world.location_changed", function(e)
    in_town = type(e) == "table" and e.context == "town"
    if not in_town or not hub_on() then return end
    if not bound then
      bound = true
      try(game.input.bind, {id = "hub", keys = {"Gamepad:dpup", "H"}})
    end
    local h = hub()
    if next(h.rescued) then toast("Vigil: D-pad Up calls the folk you saved.", 200) end
  end)
  moonmod.on("game.tick", function()
    if not in_town or not hub_on() then return end
    local press = try(game.input.consume, {id = "hub"})
    if type(press) == "table" and press.pressed then open_hub() end
  end)
end

-- Invaders (§12, stretch goal 10): now and then a dark copy of a party member hunts you through a zone. About one
-- zone in five of a kept map (none an ambush's) holds one, picked by its key: a moment after you walk in, it steps out
-- ahead of you in black, with a bar of its own. It is the engine's companion made hostile (party.companion_set
-- hostile): its blows are the game's own hits on you, so guard, dodge and poise all work on it, and your weapon hurts
-- it. Felled, it drops the best of several gear rolls and Gilda, and that zone stays clear (kept with the floor).
-- Leave the floor and it goes.
do
  local HEROES = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
  local NAMES = {toan = "Toan", xiao = "Xiao", goro = "Goro", ruby = "Ruby", ungaga = "Ungaga", osmond = "Osmond"}
  local armed, out, clock = nil, nil, 0

  local function joined_heroes(active)
    local members = try(game.party and game.party.list)
    local list = {}
    for _, m in ipairs(type(members) == "table" and (members.members or members) or {}) do
      if type(m) == "table" and NAMES[m.id] and m.id ~= active and m.joined ~= false then list[#list + 1] = m.id end
    end
    return list
  end

  local function leave()
    if not out then return end
    out = nil
    try(game.party.companion_set, {})
    try(game.render.bar_remove, {id = "invader"})
  end

  local function bar(hp, most)
    try(game.render.bar_register, {id = "invader", label = out.name:upper():sub(1, 24), current = math.max(0, hp), max = most, boss = true})
  end

  local function invade()
    local a = armed
    armed = nil
    local p = try(game.player.get)
    if type(p) ~= "table" or type(p.max_hp) ~= "number" then return end
    local others = joined_heroes(p.character)
    local h = a.hash
    local who = #others > 0 and others[h % #others + 1] or p.character
    if not NAMES[who] then who = HEROES[h % #HEROES + 1] end
    -- As tough as a named elite for your life, a blow worth a sixth of it; more on each NG+ cycle.
    local cycle = later.cycle_now and later.cycle_now() or 0
    local most = math.floor(p.max_hp * 1.4 * (1 + 0.5 * cycle))
    local blow = math.max(4, math.floor(p.max_hp / 6 * (1 + 0.25 * cycle)))
    local ok = call(game.party.companion_set, {character = who, stance = "passive",
                                               hostile = {hp = most, damage = blow, tint = {r = 40, g = 20, b = 70}}})
    if not ok then return end
    out = {key = a.key, name = "Dark " .. NAMES[who], max = most}
    bar(most, most)
    toast(string.format("Vigil: %s has invaded!", out.name), 240)
  end

  moonmod.on("game.companion.struck", function(e)
    if not out or type(e) ~= "table" then return end
    bar(tonumber(e.hp) or 0, tonumber(e.max_hp) or out.max)
    if not e.killed then return end
    local seeds = floor_seeds()
    seeds[out.key] = true
    if floors.key then try(game.save.set, floors.key, seeds) end
    toast(string.format("Vigil: %s is driven out.", out.name), 240)
    local bounty = 300 * (1 + (later.cycle_now and later.cycle_now() or 0))
    try(game.economy.add, {amount = bounty})
    if later.elite_gear then later.elite_gear(floor_now and floor_now.dungeon_id or 1, out.name .. " left") end
    out = nil
    try(game.render.bar_remove, {id = "invader"})
  end)

  moonmod.on("game.dungeon.zone_entered", function(e)
    armed = nil
    if out or in_sandbox or floors.trial or type(e) ~= "table" or type(e.zone) ~= "number" or e.previous == -1 or not floor_now or
       not zoned_floor(floor_now) or not setting("invaders", true) then
      return
    end
    local key = string.format("%s:%d:invader", place_key(floor_now.dungeon_id, floor_now.floor_id), e.zone)
    if floor_seeds()[key] then return end
    -- The same hash the ambushes use, so a zone is one or the other.
    local akey = string.format("%s:%d:ambush", place_key(floor_now.dungeon_id, floor_now.floor_id), e.zone)
    local h, g = 0, 0
    for i = 1, #akey do h = (h * 31 + akey:byte(i)) % 1000003 end
    for i = 1, #key do g = (g * 31 + key:byte(i)) % 1000003 end
    if h % 3 ~= 0 and g % 5 == 0 then armed = {key = key, at = clock + 150, hash = g} end
  end)
  moonmod.on("game.dungeon.generating", function() armed = nil leave() end)
  moonmod.on("game.world.location_changed", function(e)
    if type(e) == "table" and e.context ~= "dungeon" then armed = nil leave() end
  end)
  moonmod.on("game.tick", function()
    clock = clock + 1
    if armed and clock >= armed.at then invade() end
  end)
end

-- Darkness and miasma (§12, stretch goal 9): the dungeons' own hazards. In the Gallery of Time a zone whose shrine
-- isn't lit lies in darkness: the fog closes in and little shows past a few steps. Light its shrine and the dark lifts
-- there for good. In the Moon Sea some cells of a kept map hold a foul mist (the same cells every visit): it puffs
-- where you can see it, and standing in it poisons you. The first shrine lit in the Gallery gives a Shrine Lantern, a
-- pouch: while anyone in the party wears it, the dark there is a ring of warm light some way round you, not a few steps.
do
  local DARK_DUNGEON, FOUL_DUNGEON = 5, 4
  local LANTERN = "Shrine Lantern"
  local base, dark, clock, warned = nil, false, 0, false

  local function lantern_worn()
    if not setting("lantern", true) then return false end
    local gear = try(game.items.gear)
    if type(gear) ~= "table" or type(gear.pieces) ~= "table" or type(gear.worn) ~= "table" then return false end
    local named = {}
    for _, p in ipairs(gear.pieces) do if p.name == LANTERN then named[p.uid] = true end end
    for _, w in pairs(gear.worn) do
      if type(w) == "table" and type(w.slots) == "table" and w.slots.pouch and named[w.slots.pouch] then return true end
    end
    return false
  end

  -- Once a save: the lantern, the first time a Gallery shrine's light lifts the dark.
  local function give_lantern()
    if not setting("lantern", true) or not setting("gear", true) then return end
    local slot = try(game.save.slot_id)
    local key = type(slot) == "table" and slot.slot_id and ("lantern:" .. slot.slot_id .. ":" .. tostring(slot.slot_generation)) or nil
    if not key or try(game.save.get, key) then return end
    local piece = call(game.items.gear_give, {kind = "pouch", name = LANTERN, rarity = 4, value = 600, icon = "gear_pouch",
                                              effects = {bag = 10}, color = {r = 255, g = 196, b = 96}})
    if piece then
      try(game.save.set, key, true)
      toast("Vigil: the shrine's flame catches in an old lantern. Wear it as a pouch to see in the dark.", 260)
    end
  end

  local function zone_lit(zone)
    if not floor_now then return false end
    local seeds = floor_seeds()
    for _, sh in ipairs(type(seeds[place_key(floor_now.dungeon_id, floor_now.floor_id) .. ":shrines"]) == "table" and
                        seeds[place_key(floor_now.dungeon_id, floor_now.floor_id) .. ":shrines"] or {}) do
      if type(sh) == "table" and sh.zone == zone then return true end
    end
    return false
  end

  local function restore()
    if not dark then return end
    dark = false
    if type(base) == "table" and type(base.front) == "table" then
      local f = base.front
      try(game.dungeons.lighting_set, {side = "front", fog = f.fog, background = f.background, ambient = f.ambient,
                                       view_scale = base.view_scale})
    end
  end

  local function darken()
    local lit = lantern_worn()
    if dark == (lit and "lantern" or true) then return end
    dark = lit and "lantern" or true
    if lit then
      try(game.dungeons.lighting_set, {side = "front", fog = {near = 160, far = 820, r = 24, g = 16, b = 8},
                                       background = {r = 0, g = 0, b = 0}, ambient = {r = 92, g = 80, b = 64}})
    else
      try(game.dungeons.lighting_set, {side = "front", fog = {near = 40, far = 360, r = 4, g = 4, b = 10},
                                       background = {r = 0, g = 0, b = 0}, ambient = {r = 40, g = 40, b = 56}})
    end
  end

  local function check_dark()
    if in_sandbox or floors.trial or not floor_now or floor_now.dungeon_id ~= DARK_DUNGEON or not zoned_floor(floor_now) or
       not setting("darkness", true) then
      restore()
      return
    end
    local z = try(game.dungeons.zones_get)
    local zone = type(z) == "table" and tonumber(z.current) or 0
    if zone_lit(zone) then
      if dark then
        toast("Vigil: the shrine's light holds back the dark.", 180)
        give_lantern()
      end
      restore()
    else
      if not dark then toast("Vigil: darkness. Light this zone's shrine to lift it.", 200) end
      darken()
    end
  end

  -- A foul cell: picked from the floor's key and the cell, so the same cells every visit.
  local function foul(key, cx, cy)
    local h = 7
    local s = key .. ":" .. cx .. ":" .. cy
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
    return h % 11 == 0
  end

  moonmod.on("game.dungeon.generated", function()
    dark, warned = false, false
    base = try(game.dungeons.lighting_get)
  end)
  moonmod.on("game.dungeon.zone_entered", function() check_dark() end)
  moonmod.on("game.world.location_changed", function(e)
    if type(e) == "table" and e.context ~= "dungeon" then dark = false end
  end)
  moonmod.on("game.tick", function()
    clock = clock + 1
    if clock % 60 == 0 and floor_now and floor_now.dungeon_id == DARK_DUNGEON then check_dark() end
    if clock % 30 ~= 0 or in_sandbox or floors.trial or not floor_now or floor_now.dungeon_id ~= FOUL_DUNGEON or
       not zoned_floor(floor_now) or not setting("miasma", true) then
      return
    end
    local p = try(game.player.get)
    local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
    if not at then return end
    local key = place_key(floor_now.dungeon_id, floor_now.floor_id)
    local cx, cy = math.floor(at.x / 160 + 0.5), math.floor(at.z / 160 + 0.5)
    if clock % 90 == 0 then
      for dy = -1, 1 do
        for dx = -1, 1 do
          if foul(key, cx + dx, cy + dy) then
            try(game.effects.burst, {kind = "smoke", position = {x = 160 * (cx + dx), y = at.y + 4, z = 160 * (cy + dy)}, scale = 2.2})
          end
        end
      end
    end
    if foul(key, cx, cy) then
      if not warned then
        warned = true
        toast("Vigil: the mist here is foul. Don't linger in it.", 200)
      end
      try(game.player.status_add, {status = "poison"})
    end
  end)
end

-- The death ghost (§12, stretch goal 14): the last five seconds before you fell are kept with the save. Come back near
-- where you fell and your ghost walks them again: the hero, pale and see-through, doing what you did (world.ghost_play),
-- or, without the engine's record, a wisp of light that ends in a puff where you went down. A warning of what got you,
-- each time you come back to the spot.
do
  local STEP, KEEP = 10, 30
  local trail, clock, playing, near = {}, 0, nil, false

  moonmod.on("game.dungeon.generated", function() trail, playing, near = {}, nil, false end)

  moonmod.on("game.dungeon.defeated", function(e)
    if in_sandbox or not setting("ghost", true) or type(e) ~= "table" or not floor_now or e.dungeon_id ~= floor_now.dungeon_id or
       not zoned_floor(floor_now) or #trail < 3 then
      return
    end
    local seeds = floor_seeds()
    seeds.ghost = {key = place_key(floor_now.dungeon_id, floor_now.floor_id), path = trail}
    -- The engine's own record of those seconds (world.ghost_get): the hero's place and motion every other frame, so the
    -- ghost can be the hero, pale and see-through, doing what you did.
    local kept = try(game.world.ghost_get)
    if type(kept) == "table" and type(kept.character) == "string" and type(kept.frames) == "table" and #kept.frames > 0 then
      seeds.ghost.hero = {character = kept.character, frames = kept.frames}
    end
    if floors.key then try(game.save.set, floors.key, seeds) end
    trail = {}
  end)

  moonmod.on("game.tick", function()
    clock = clock + 1
    if clock % STEP ~= 0 or in_sandbox or floors.trial or not in_dungeon or not floor_now or not setting("ghost", true) then return end
    local p = try(game.player.get)
    local at = type(p) == "table" and type(p.position) == "table" and p.position or nil
    if not at then return end
    trail[#trail + 1] = {x = math.floor(at.x), y = math.floor(at.y), z = math.floor(at.z)}
    if #trail > KEEP then table.remove(trail, 1) end

    local g = floor_seeds().ghost
    if type(g) ~= "table" or type(g.path) ~= "table" or #g.path == 0 or g.key ~= place_key(floor_now.dungeon_id, floor_now.floor_id) then
      return
    end
    if playing then
      local point = g.path[playing]
      if point then
        local last = playing == #g.path
        try(game.effects.burst, {kind = last and "smoke" or "heal", position = {x = point.x, y = point.y + 8, z = point.z},
                                 scale = last and 1.6 or 0.8})
      end
      playing = playing < #g.path and playing + 1 or nil
      return
    end
    local fell = g.path[#g.path]
    local d = math.sqrt((at.x - fell.x) ^ 2 + (at.z - fell.z) ^ 2)
    if d < 240 and not near then
      near, playing = true, 1
      -- The hero's ghost when the engine kept one; the wisp of light otherwise.
      if type(g.hero) == "table" and try(game.world.ghost_play, {character = g.hero.character, frames = g.hero.frames}) then
        playing = nil
      end
      toast("Vigil: your ghost walks its last steps.", 160)
    elseif d > 600 then
      near = false
    end
  end)
end

-- One-way drops (§12, stretch goal 11): beside about one locked zone gate in three of a kept map there is a ledge.
-- Reach the gate without its key and you may drop down past it, into the zone beyond by its shrine, for a share of
-- your life. There is no climbing back: the gate stays locked behind you until you find its key or travel by a
-- shrine. DC1's floors are flat, so the drop is a fall through the dark (a warp with the escape item's light), not a
-- height step.
do
  local offered -- the gate a drop is on offer at: {zone, x, y}

  local function has_ledge(zone)
    if not floor_now then return false end
    local key = string.format("%s:%d:drop", place_key(floor_now.dungeon_id, floor_now.floor_id), zone)
    local h = 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 1000003 end
    return h % 3 == 0
  end

  moonmod.on("game.dungeon.zone_gate_locked", function(e)
    offered = nil
    if in_sandbox or floors.trial or type(e) ~= "table" or type(e.zone) ~= "number" or not floor_now or not zoned_floor(floor_now) or
       not setting("drops", true) or not has_ledge(e.zone) then
      return
    end
    local z = try(game.dungeons.zones_get)
    local below
    for _, sh in ipairs(type(z) == "table" and type(z.shrines) == "table" and z.shrines or {}) do
      if type(sh) == "table" and sh.zone == e.zone then below = sh end
    end
    if not below then return end
    offered = {zone = e.zone, x = below.x, y = below.y + 1}
    try(game.ui.choice_open, {id = "vigil.drop", title = "A ledge", subtitle = "Beside the gate the floor falls away into the dark.",
                              cancel = true, options = {
      {title = "Drop down", lines = {"Past the gate, by", "the next shrine.", {text = "No climbing back.", tone = "bad"}}},
      {title = "Stay", lines = {"Find the key."}},
    }})
  end)

  moonmod.on("ui.choice_made", function(e)
    if type(e) ~= "table" or e.id ~= "vigil.drop" or not offered then return end
    local at = offered
    offered = nil
    if e.cancelled or e.index ~= 1 then return end
    if not try(game.dungeons.warp, {x = at.x, y = at.y, teleport = true}) then return end
    local p = try(game.player.get)
    local most = type(p) == "table" and type(p.max_hp) == "number" and p.max_hp or 0
    local hp = type(p) == "table" and type(p.hp) == "number" and p.hp or 0
    -- The fall takes a tenth of your life, but never the last of it.
    local fall = math.min(math.floor(most / 10), hp - 1)
    if fall > 0 then try(game.player.damage, {amount = fall, character = "active"}) end
    toast("Vigil: you drop into the dark, and land hard. The way back is shut.", 220)
  end)
  moonmod.on("game.dungeon.generated", function() offered = nil end)
end

-- Ranged and casting enemies (§13, item 7): a family that shoots keeps its distance instead of standing to fire as
-- the game had it. Too close, it backs off; too far, it comes in; in between it steps aside now and then. Every couple
-- of seconds it stops, turns to you, glints (the telegraph) and a beat later plays its shot and fires its own
-- projectile at where you stand (SET_SHOT from its own frame, as its script does), then waits to fire again. Two
-- shooters never fire in the same moment. Each row is {shot motion, the frame it fires from, motion speed, walk}.
-- Idle is motion 0 and walking 1 for every row (the shot frames and motions from each family's .stb, read with
-- tools/stb/stbdis.py). Rows are keyed by native model id (MonstorTable's index in monstorunit.cpp), and the comment
-- names that model's file: past the early dungeons the two differ, and a story boss (Dran is 78) must never get a row.
do
  local SHOOTERS = {
    [5] = {motion = 16, from = "dcol0", speed = 0.30},  -- e08a
    [7] = {motion = 15, from = "dcol1", speed = 0.25},  -- e10a
    [9] = {motion = 16, from = "dcol0", speed = 0.20},  -- e12a
    [12] = {motion = 13, from = "dcol0", speed = 0.20}, -- e16a
    [20] = {motion = 14, from = "dcol1", speed = 0.25, walk = 2}, -- e24a
    [21] = {motion = 13, from = "dcol0", speed = 0.25, walk = 2}, -- e25a
    [25] = {motion = 15, from = "dcol2", speed = 0.25}, -- e30a
    [26] = {motion = 13, from = "dcol1", speed = 0.30, second = {motion = 16, from = "dcol2", speed = 0.25}}, -- e31a
    [28] = {motion = 15, from = "dcol2", speed = 0.25}, -- e33a
    -- The later dungeons' shooters (each family's walk read from the motion its script moves in).
    [14] = {motion = 13, from = "dcol0", speed = 0.25},  -- e18a
    [51] = {motion = 13, from = "dcol1", speed = 0.28},  -- e59a
    [56] = {motion = 15, from = "dcol2", speed = 0.25},  -- e64a
    [57] = {motion = 15, from = "dcol2", speed = 0.25},  -- e65a
    [58] = {motion = 16, from = "dcol0", speed = 0.20},  -- e66a
    [64] = {motion = 14, from = "dcol1", speed = 0.25, walk = 2}, -- e72a
    [65] = {motion = 13, from = "dcol1", speed = 0.28},  -- e73a
    [66] = {motion = 13, from = "dcol1", speed = 0.28},  -- e74a
    [67] = {motion = 16, from = "dcol01", speed = 0.28, walk = 2}, -- e75a
    [77] = {motion = 16, from = "dcol2", speed = 0.25, walk = 2, second = {motion = 13, from = "bcol0", speed = 0.30}}, -- e86a
    [94] = {motion = 15, from = "dcol2", speed = 0.25},  -- e90a
    [95] = {motion = 15, from = "dcol2", speed = 0.25},  -- e91a
    [98] = {motion = 13, from = "dcol1", speed = 0.25},  -- e104a
    [112] = {motion = 16, from = "dcol2", speed = 0.25},  -- e108a
    [115] = {motion = 15, from = "dcol2", speed = 0.25},  -- e127a
    [116] = {motion = 15, from = "dcol1", speed = 0.25},  -- e128a
    [127] = {motion = 15, from = "dcol2", speed = 0.25}, -- e137a
    [133] = {motion = 16, from = "dcol1", speed = 0.25, walk = 2, second = {motion = 16, from = "dcol1", speed = 0.25}}, -- e116a
    [135] = {motion = 15, from = "dcol2", speed = 0.25}, -- e141a
    [136] = {motion = 16, from = "dcol01", speed = 0.28, walk = 2}, -- e142a
    [137] = {motion = 14, from = "dcol1", speed = 0.25, walk = 2}, -- e143a
    [144] = {motion = 16, from = "dcol0", speed = 0.25, walk = 2}, -- e118a
    [150] = {motion = 13, from = "dcol0", speed = 0.25, walk = 2}, -- e154a
    [151] = {motion = 14, from = "dcol1", speed = 0.25, walk = 2}, -- e155a
    [161] = {motion = 15, from = "dcol2", speed = 0.25}, -- e163a
    -- Fliers: they keep their height (every move goes to a point at their own), and shoot down at you.
    [17] = {motion = 12, from = "dcol0", speed = 0.25},  -- e21a
    [18] = {motion = 12, from = "dcol0", speed = 0.25},  -- e22a
    [36] = {motion = 16, from = "dcol2", speed = 0.20},  -- e42a
    [45] = {motion = 16, from = "dcol2", speed = 0.20},  -- e51a
    [126] = {motion = 12, from = "dcol0", speed = 0.25}, -- e136a
    [160] = {motion = 16, from = "dcol2", speed = 0.20}, -- e162a
  }
  local NEAR, FAR, RANGE = 70, 190, 260
  local last_shot = -1000

  local function shooter_think(ctx, kind, mind, me, you, dist, ux, uz, dt)
    local e, r = ctx.entity, kind.ranged
    if mind.state == "aim" then
      halt(e)
      face(e, you, 0.4)
      if mind.t >= 18 then
        -- The second shot's own motion, when the next shot is the second one.
        local second = r.second and ((mind.shots or 0) + 1) % 2 == 0
        play(e, mind, second and r.second.motion or r.motion, second and r.second.speed or r.speed, true)
        to(mind, "shoot")
      end
      return
    end
    if mind.state == "shoot" then
      if not mind.fired and mind.t >= 6 then
        mind.fired = true
        last_shot = ctx.frame
        -- A family with a second shot (SET_SHOT2, a caster's other spell) alternates the two.
        mind.shots = (mind.shots or 0) + 1
        local second = r.second and mind.shots % 2 == 0
        native(e, second and "SET_SHOT2" or "SET_SHOT", {second and r.second.from or r.from, you[1], you[2] + 7.4, you[3]})
      end
      if mind.t >= 50 then
        play(e, mind, kind.idle)
        mind.reload, mind.step_until, mind.aside = math.random(100, 170), nil, nil
        to(mind, "keep")
      end
      return
    end
    if mind.state ~= "keep" then
      mind.reload, mind.step_until, mind.aside = mind.reload or math.random(40, 90), nil, nil
      to(mind, "keep")
    end
    mind.reload = mind.reload - dt
    if mind.reload <= 0 and dist <= RANGE and dist >= 20 and ctx.frame - last_shot > 40 then
      halt(e)
      play(e, mind, kind.idle)
      mind.fired = false
      to(mind, "aim")
      if setting("telegraphs", true) then
        try(game.effects.burst, {kind = "guard", position = {x = me[1] + ux * 10, y = me[2] + 22, z = me[3] + uz * 10}, scale = 0.7})
        try(game.audio and game.audio.se_play, {se = 370, volume = 64})
      end
      return
    end
    local at
    if dist < NEAR then
      at = {me[1] - ux * 30, me[2], me[3] - uz * 30} -- back off
      local clear = native(e, "CHK_MOVE_INFO", {at[1], at[2], at[3], I})
      if clear and clear[1] == 0 then at = nil end
    elseif dist > FAR then
      at = way(e, me, ux, uz)
    elseif mind.t >= (mind.step_until or 0) then
      -- A step aside, then a beat standing.
      mind.side = mind.side or 1
      if math.random() < 0.4 then mind.side = -mind.side end
      mind.aside = {me[1] - uz * mind.side * 40, me[2], me[3] + ux * mind.side * 40}
      local clear = native(e, "CHK_MOVE_INFO", {mind.aside[1], mind.aside[2], mind.aside[3], I})
      if clear and clear[1] == 0 then mind.aside = nil end
      mind.step_until = mind.t + math.random(60, 120)
      mind.aside_until = mind.t + 30
    end
    if not at and mind.aside and mind.t < (mind.aside_until or 0) then at = mind.aside end
    if at then
      play(e, mind, kind.walk)
      face(e, at, 0.2)
      go(e, at, kind.walk_speed)
      mind.walking = true
    else
      mind.aside = nil
      halt(e)
      play(e, mind, kind.idle)
      face(e, you, 0.2)
    end
  end

  for model, r in pairs(SHOOTERS) do
    r.think = shooter_think
    BRAINS[model] = BRAINS[model] or {idle = 0, walk = r.walk or 1, walk_speed = 0.5, ranged = r}
  end
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
  -- Another mod's run lays its own floors out (the Gauntlet's Confluence asks for zones): hand them over.
  if in_sandbox and zones_asked then
    try(game.dungeons.set_zones, {})
    try(game.dungeons.set_exits, {town = "any"})
    zones_asked = false
  end
end)
moonmod.on("game.session.ended", function() set_sandbox(false) end)

-- Gear (VIGIL_PLAN.md section 11, G4 and G5) -----------------------------------------------------------------------
-- Hats, tunics, gloves, boots and pouches, each character wearing one of each (items.gear*: the engine keeps them beside
-- the save and reads their effects where the game decides). Pieces turn up in chests and, now and then, on a monster you
-- beat, with a rarity that sets how many effects they have and how strong: a chance to shrug off an ailment, stamina,
-- lightness (cheaper swings), defence, a cheaper run, on a tunic poise (hits taken without a stagger) and on a pouch
-- room in the item bag (the largest pouch anyone in the party wears counts, on top of the game's Pockets). They live in
-- the item page's Equipment tab (items.gear_page_set), each piece its kind's icon in the colour of what it does best.
local apply_gear -- called again at Start
do
  local GEAR_KINDS = {"hat", "tunic", "gloves", "boots", "pouch"}
  -- Each hero's own clothes in the slots, by the frames of their menu model, turned to show them best. Toan: the tunic
  -- is his vest (front and back, as the model hangs it) with the belt, the gloves the cuff with the hand, the boot seen
  -- from the side: his shoes are part of his body, so the boot slot draws that, cut off a third of the way down his
  -- ankle wrap and fitted to what is left, the shoes alone. The others the same way where they have the piece: Xiao's
  -- paw and her shoes under her leg wraps, Goro's bear mantle, Ruby's tiara, hand and slippers, Ungaga's feathered cap,
  -- sash and bracer, Osmond's goggles, glove, boots (under his ankle joint) and bag. A kind a hero has nothing for keeps
  -- the drawn icon. With no hat on Toan goes bareheaded (the hat and its tail left out), and with no tunic his vest comes
  -- off to the shirt; nobody has bare hands or feet, so those stay. His pouch is the satchel at his hip, gone while he
  -- wears none; Goro's mantle, Ungaga's cap and sash and Osmond's bag come off the same way.
  local GEAR_PARTS = {
    toan = {hat = {draw = {"boushi"}, turn = 40, bare = {"boushi", "cloth1"}},
            tunic = {draw = {"cloth2", "cloth3", "beruto"}, bare = {"cloth2", "cloth3"}},
            gloves = {draw = {"l_g", "l_hand"}, turn = 40},
            boots = {draw = {"skin"}, below = {"l_f"}, turn = 63, tilt = 10},
            pouch = {draw = {"kaban"}, turn = 77, bare = {"kaban"}}},
    xiao = {gloves = {draw = {"l_hand"}},
            boots = {draw = {"skin"}, below = {"l_asi"}, turn = 63, tilt = 10}},
    goro = {tunic = {draw = {"mant"}, turn = 150, bare = {"mant"}}},
    ruby = {hat = {draw = {"cube37"}, turn = 20},
            gloves = {draw = {"body5"}, turn = 40},
            boots = {draw = {"skin", "cube40", "cube60"}, below = {"cube40"}, turn = 63, tilt = 10}},
    ungaga = {hat = {draw = {"cap"}, turn = 40, bare = {"cap"}},
              tunic = {draw = {"cloth1", "cloth2"}, turn = 20, bare = {"cloth1", "cloth2"}},
              gloves = {draw = {"r_hand4", "l_udewa_2"}, turn = 40}},
    osmond = {hat = {draw = {"face"}, turn = 30},
              gloves = {draw = {"l_hand4"}, turn = 40},
              boots = {draw = {"skin"}, below = {"l_foot"}, turn = 63, tilt = 10},
              pouch = {draw = {"bag"}, turn = 77, bare = {"bag"}}},
  }
  local GEAR_BASES = {hat = {"Cap", "Hood", "Helm"}, tunic = {"Tunic", "Vest", "Mail"},
                      gloves = {"Gloves", "Bracers", "Gauntlets"}, boots = {"Sandals", "Boots", "Greaves"},
                      pouch = {"Pouch", "Satchel", "Pack"}}
  -- Each kind's first effect, so a piece's kind says something about it; the rest are drawn from them all.
  -- A tunic's is poise, which only a tunic has: hits taken without a stagger (light 1 point, heavy 2). A pouch's is bag,
  -- which only a pouch has: 5 more item slots a tier, 25 for a legendary.
  local GEAR_SIGNATURE = {hat = "guard", tunic = "poise", gloves = "lightness", boots = "run_cost", pouch = "bag"}
  local GEAR_EFFECTS = {"guard", "stamina", "lightness", "defence", "run_cost"}
  local AILMENTS = {"freeze", "poison", "curse", "goo"}
  local GEAR_PREFIX = {freeze = "Warm", poison = "Viper's", curse = "Blessed", goo = "Clean",
                       stamina = "Tireless", lightness = "Nimble", defence = "Sturdy", run_cost = "Swift", poise = "Stalwart",
                       bag = "Roomy"}
  -- A piece is tinted by its first effect: you can tell a poison hood from a curse hood at a glance.
  local GEAR_COLOR = {freeze = {r = 140, g = 210, b = 255}, poison = {r = 110, g = 196, b = 90}, curse = {r = 170, g = 124, b = 220},
                      goo = {r = 196, g = 160, b = 92}, stamina = {r = 244, g = 160, b = 64}, lightness = {r = 244, g = 222, b = 110},
                      defence = {r = 176, g = 188, b = 204}, run_cost = {r = 232, g = 92, b = 76},
                      poise = {r = 206, g = 146, b = 92}, bag = {r = 196, g = 150, b = 104}}
  -- The Gauntlet's five rarities, as weapons have them (Weapon rarity, above): effects on a piece and its price.
  -- Each effect is as strong as the tier's number (a legendary's five times a common's).
  local RARITY = {
    {name = "Common", effects = 1, value = 60},
    {name = "Uncommon", effects = 2, value = 180},
    {name = "Rare", effects = 3, value = 450},
    {name = "Epic", effects = 3, value = 900},
    {name = "Legendary", effects = 4, value = 1600},
  }
  local GEAR_STRENGTH = {guard = 15, stamina = 6, lightness = 5, defence = 2, run_cost = 8, poise = 1, bag = 5}
  local GEAR_CHEST_CHANCE, GEAR_KILL_CHANCE = 0.2, 0.03

  local function gear_on() return setting("gear", true) and not in_sandbox end

  -- A rarity from 1 to 5: deeper dungeons lean rarer.
  local function roll_rarity(dungeon_id)
    local r = math.random(100) + 4 * (tonumber(dungeon_id) or 0)
    if r > 99 then return 5 elseif r > 94 then return 4 elseif r > 82 then return 3 elseif r > 56 then return 2 end
    return 1
  end

  local function roll_gear(dungeon_id)
    local kind = GEAR_KINDS[math.random(#GEAR_KINDS)]
    local tier = roll_rarity(dungeon_id)
    local effects, picked = {}, {}
    local first
    for i = 1, RARITY[tier].effects do
      local e = i == 1 and GEAR_SIGNATURE[kind] or nil
      while not e or picked[e] do e = GEAR_EFFECTS[math.random(#GEAR_EFFECTS)] end
      picked[e] = true
      local amount = GEAR_STRENGTH[e] * tier
      if e == "guard" then
        local ailment = AILMENTS[math.random(#AILMENTS)]
        effects.guard = {[ailment] = amount}
        first = first or ailment
      else
        effects[e] = amount
        first = first or e
      end
    end
    local bases = GEAR_BASES[kind]
    return {kind = kind, rarity = tier - 1, value = RARITY[tier].value, effects = effects, icon = "gear_" .. kind,
            color = GEAR_COLOR[first], name = GEAR_PREFIX[first] .. " " .. bases[math.min(tier, #bases)]}
  end

  -- The icons, once, and the Equipment tab while gear is on.
  local gear_icons, gear_page = false, false
  apply_gear = function()
    -- The locked enemy's wider bar, its poise under it (the poise block, above).
    local bar = setting("target_bar", true) and not in_sandbox
    if bar ~= later.target_bar then
      if call(game.render and game.render.target_bar_set, {on = bar}) then later.target_bar = bar end
    end
    -- The weapon cards' stat labels, redrawn one size and evenly spaced on the Status tab (tools/vigil/make_stat_labels.py);
    -- under Lightness (§11 G3) a weapon's Speed sets what a swing costs, so it reads Lt.
    local labels = game.weapons and game.weapons.stat_label_set
    local speed = in_sandbox and "" or (setting("lightness", true) and "lightness" or "speed")
    if speed ~= later.stat_labels then
      if speed == "" then
        try(labels, {})
      else
        local set = {}
        for _, stat in ipairs({"attack", "endurance", speed, "magic"}) do
          try(game.resources.override, {path = "resources/label_" .. stat .. ".png", game_path = "icons/label_" .. stat .. ".png"})
          set[stat == "lightness" and "speed" or stat] = "label_" .. stat
        end
        if not call(labels, set) then speed = nil end
      end
      later.stat_labels = speed
    end
    if gear_on() then
      if not gear_icons then
        for _, kind in ipairs(GEAR_KINDS) do
          try(game.resources.override, {path = "resources/gear_" .. kind .. ".png", game_path = "icons/gear_" .. kind .. ".png"})
        end
        gear_icons = true
      end
      local ok, err = call(game.items.gear_page_set, {icons = {hat = "gear_hat", tunic = "gear_tunic", gloves = "gear_gloves", boots = "gear_boots",
                                                               pouch = "gear_pouch"},
                                                      parts = GEAR_PARTS})
      gear_page = ok ~= nil
      if not ok then moonmod.log("warn", "gear page: " .. message(err)) end
    elseif gear_page then
      try(game.items.gear_page_set, {})
      gear_page = false
    end
  end

  local function give_gear(dungeon_id, where)
    if not gear_on() then return end
    local piece = roll_gear(dungeon_id)
    local made, err = call(game.items.gear_give, piece)
    if not made then
      if err and err.code ~= "unsupported" then toast("Vigil: " .. message(err)) end
      return
    end
    toast(string.format("%s: %s (%s %s). It's in the Equipment tab.", where, piece.name, RARITY[piece.rarity + 1].name:lower(), piece.kind))
  end

  -- A named elite's drop (Named elites, below): always a piece, the best of a few rolls.
  later.elite_gear = function(dungeon_id, who)
    if not gear_on() then return end
    local piece = roll_gear(dungeon_id)
    for _ = 1, 3 + (later.cycle_now and later.cycle_now() or 0) do
      local other = roll_gear(dungeon_id)
      if other.rarity > piece.rarity then piece = other end
    end
    local made, err = call(game.items.gear_give, piece)
    if not made then
      if err and err.code ~= "unsupported" then toast("Vigil: " .. message(err)) end
      return
    end
    toast(string.format("%s dropped %s (%s %s). It's in the Equipment tab.", who, piece.name, RARITY[piece.rarity + 1].name:lower(), piece.kind))
  end

  moonmod.on("game.chest.opened", function(e)
    if type(e) ~= "table" or type(e.chest) ~= "number" then return end
    if math.random() < GEAR_CHEST_CHANCE then give_gear(e.dungeon_id or (floor_now and floor_now.dungeon_id), "In the chest") end
  end)

  moonmod.on("game.enemy_defeated", function(e)
    if type(e) ~= "table" or e.attacker == nil then return end
    if math.random() < GEAR_KILL_CHANCE then give_gear(floor_now and floor_now.dungeon_id, "Dropped") end
  end)

  -- Each trip home every town shop puts out a few pieces beside its own goods, at twice what a piece sells for, rolled
  -- as deep as the last dungeon. What's bought stays gone until the next trip; a piece sells on the Equipment tab.
  moonmod.on("game.world.location_changed", function(e)
    if not gear_on() or type(e) ~= "table" or e.context ~= "town" then return end
    if later.shops_stocked and not (type(e.previous) == "table" and e.previous.context == "dungeon") then return end
    for shop = 0, 17 do
      local goods = {}
      for i = 1, 3 do
        goods[i] = roll_gear(floor_now and floor_now.dungeon_id)
        goods[i].price = goods[i].value * 2
      end
      if not call(game.items.gear_stock_set, {shop = shop, goods = goods}) then return end
    end
    later.shops_stocked = true
  end)

  -- Each hero's own clothes that come off (bare, above), worn from the start: an empty slot takes them off, so each save
  -- dresses each hero once, the first time they are in the party, in plain pieces with nothing to them. A slot already
  -- filled keeps what is worn.
  moonmod.on("game.world.location_changed", function()
    local STARTER_CLOTHES = {
      toan = {{kind = "hat", name = "Toan's Cap", color = {r = 120, g = 170, b = 80}},
              {kind = "tunic", name = "Toan's Vest", color = {r = 236, g = 140, b = 56}},
              {kind = "pouch", name = "Toan's Satchel", color = {r = 176, g = 120, b = 72}}},
      goro = {{kind = "tunic", name = "Goro's Mantle", color = {r = 120, g = 92, b = 64}}},
      ungaga = {{kind = "hat", name = "Ungaga's Cap", color = {r = 150, g = 150, b = 80}},
                {kind = "tunic", name = "Ungaga's Sash", color = {r = 214, g = 84, b = 48}}},
      osmond = {{kind = "pouch", name = "Osmond's Bag", color = {r = 160, g = 104, b = 60}}},
    }
    local STARTER_ORDER = {"toan", "goro", "ungaga", "osmond"}
    if not gear_on() then return end
    local gear = try(game.items.gear)
    if type(gear) ~= "table" or type(gear.pieces) ~= "table" then return end
    local slot = try(game.save.slot_id)
    local key = type(slot) == "table" and slot.slot_id and ("dressed:" .. slot.slot_id .. ":" .. tostring(slot.slot_generation)) or nil
    -- Toan's are kept by kind (a save dressed before the satchel came, true, had the cap and vest); the others' by
    -- "hero:kind".
    local given = key and try(game.save.get, key)
    given = given == true and {hat = true, tunic = true} or (type(given) == "table" and given or {})
    local joined = {toan = true}
    local members = try(game.party and game.party.list)
    for _, m in ipairs(type(members) == "table" and (members.members or members) or {}) do
      if type(m) == "table" and type(m.id) == "string" then joined[m.id] = true end
    end
    local had, changed = {}, false
    for _, p in ipairs(gear.pieces) do had[p.name] = true end
    for _, hero in ipairs(STARTER_ORDER) do
      local worn = (type(gear.worn) == "table" and type(gear.worn[hero]) == "table" and gear.worn[hero].slots) or {}
      for _, s in ipairs(joined[hero] and STARTER_CLOTHES[hero] or {}) do
        local mark = hero == "toan" and s.kind or (hero .. ":" .. s.kind)
        if not given[mark] and not had[s.name] and worn[s.kind] == nil then
          local piece = call(game.items.gear_give, {kind = s.kind, name = s.name, rarity = 0, value = 20, icon = "gear_" .. s.kind, color = s.color})
          if piece then try(game.items.gear_equip, {uid = piece.uid, character = hero}) end
        end
        changed = changed or not given[mark]
        given[mark] = true
      end
    end
    if key and changed then try(game.save.set, key, given) end
  end)

  moonmod.on("settings.changed", function() apply_gear() end)
  moonmod.on("game.session.started", function() apply_gear() end)
  moonmod.on("game.session.ended", function() apply_gear() end)
end

-- Mod Manager: what Vigil has asked the engine for right now.
try(game.ui.register, {id = "check", label = "Check", description = "Show what Vigil has set right now."})
moonmod.on("ui.action", function(action)
  if type(action) ~= "table" or action.id ~= "check" then return end
  if in_sandbox then toast("Vigil sits out this game mode.") return end
  local t = applied.tuning or {}
  toast(string.format("Vigil: evades %s, Toan's attacks %s, enemy brain %s, guard rules %s, gauge rules %s, enemy damage x%.2f, recoil x%.2f, gauge refill x%.2f%s",
    tostring(applied.evades), tostring(applied.toan_attacks), tostring(applied.enemy_brain), tostring(applied.guard_rules),
    tostring(applied.gauge_rules), applied.enemy_damage or 1, t.recoil_scale or 1, t.gauge_refill or 1,
    guarding and " (guarding)" or ""))
end)

-- Start -----------------------------------------------------------------------------------------------------------
local session = try(game.session.get)
in_sandbox = type(session) == "table" and session.kind == "sandbox" and session.owner ~= ID
if in_sandbox then stand_down() else apply() end
apply_gear()

local mod = {}
function mod.on_load() moonmod.log("info", ID .. " ready" .. (in_sandbox and " (sitting out a game mode)" or "")) end
function mod.on_unload() moonmod.log("info", ID .. " unloaded") end
return mod
