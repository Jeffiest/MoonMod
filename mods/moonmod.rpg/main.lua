-- RPG: Character Paths 2.0. Kills give XP; levels give max HP, damage, toughness and skill points.
-- Every hero spends points on three paths of their own in the Journal's Character page (Journal > Character,
-- or the Hub's K key), which shows the active hero's. Hold L2 and press Square, Triangle or Circle for the
-- hero's three powers, paid with Focus. Weapon mastery, critical hits, weapon loot rolls and the
-- DarkCloud-Expanded weapon abilities (BSD-2-Clause) stay from Ascension 3. Progress is kept per save slot.
--
-- Nodes marked ENGINE need game.player.tuning_set (engine Phase 2). Until the engine has it they can be
-- seen but not trained.

local ID = "moonmod.rpg"
local CHARACTERS = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
local MAX_LEVEL = 40
local MASTERY_KILLS = {10, 30, 75, 150, 300}
local UNDEAD = {0, 1, 23, 24, 36, 44, 45, 67, 81, 82, 96, 105, 122, 144}
local WEAPON = {agas_sword = 281, heavens_cloud = 271, brave_ark = 274, cross_hinder = 294,
                frozen_tuna = 321, mobius_ring = 341, cactus = 360, snail = 374}
-- Lucky Find table: {item number (ps2/include/itemdata.hpp), name, weight}. Cheap supplies come up most.
local LUCKY_ITEMS = {{148, "Bread", 20}, {146, "Tasty Water", 20}, {155, "Cheese", 16}, {177, "Repair Powder", 14},
                     {151, "Antidote Drink", 12}, {152, "Holy Water", 8}, {149, "Premium Chicken", 6}, {175, "Escape Powder", 4}}

local function try(fn, ...)
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end
local function call(fn, ...)
  local ok, value, err = pcall(fn, ...)
  if not ok then return nil, {code = "error", message = tostring(value)} end
  return value, err
end
local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= type(fallback) then return fallback end
  return value
end
local function toast(message, frames) try(game.ui.notify, {message = message, duration_frames = frames or 240}) end
local function title(id) return id:sub(1, 1):upper() .. id:sub(2) end
local function errmsg(err) return type(err) == "table" and err.message or tostring(err) end

-- Sandbox modes (Dark Genie's Gauntlet) are their own game: during one, every handler below sits out.
local in_sandbox = false
local function on(name, handler)
  moonmod.on(name, function(...)
    if not in_sandbox then return handler(...) end
    if name == "ui.action" then toast("RPG sits out Dark Genie's Gauntlet runs") end
  end)
end

-- Engine support: player tuning (run speed, swing speed, invincibility...) arrives with engine Phase 2.
local TUNING = false
do
  local player = game.player
  if type(player) == "table" and type(player.tuning_set) == "function" then
    local _, err = call(player.tuning_set, {})
    TUNING = err == nil or err.code == "invalid_argument"
  end
end

-- Every hero's paths ---------------------------------------------------------------------------------
-- Each hero has three paths, each ending in a POWER (L2 + Square, Triangle or Circle, in path order). A node's
-- `effect` says what its ranks do, `per` how much per rank; the same effect kinds serve every hero, so the code
-- below asks for an effect's total for the active hero (eff) rather than for a named node. Toan's node ids are the
-- ones RPG 1 shipped, so saved ranks carry over.
--
-- Effects: damage (x per rank), crit_chance (points), crit_damage, riposte, abs_study, max_hp, taken (less damage
-- taken), thirst, wear, gilda, xp, lucky, atla, execute (more damage to an enemy under 30% life), charged_stun
-- (frames a charged hit stops an enemy), lifesteal (share of damage dealt healed), regen (share of max HP a second),
-- and the ENGINE ones, which need player tuning: attack_speed (Toan's swings), recoil, evasion, run_speed, reveal,
-- shots (Xiao's and Ruby's extra shots), pierce (Ruby's orbs), reach (Ungaga's spear).
-- Powers: dance (spinning strikes around you), heal, cry (+40% damage, +20% taken), quake (one great blast that
-- stops what it hits), shield (invulnerable a moment, then half damage taken) and volley (two more shots and +20%
-- damage).
local function S(id, title, effect, per, max_rank, description, extra)
  local s = {id = id, title = title, effect = effect, per = per, max_rank = max_rank, description = description}
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local function P(id, title, kind, cost, cooldown, description, prereq)
  return {id = id, title = title, power = kind, cost = cost, cooldown = cooldown, max_rank = 3, prerequisites = prereq,
          description = "POWER  " .. description .. " R2: +20 Focus, cheaper. R3: faster cooldown."}
end
local function needs(id, r) return {{id = id, rank = r or 1}} end
local ENGINE = {engine = true}

local HEROES = {
  toan = {
    {id = "swordsman", title = "SWORDSMAN", description = "Hit harder, hit faster.", skills = {
      S("keen_edge", "Keen Edge", "damage", 0.03, 5, "+3% damage per rank."),
      S("quick_blade", "Quick Blade", "attack_speed", 0.06, 3, "Sword swings 6% faster per rank.", {prerequisites = needs("keen_edge"), engine = true}),
      S("precise_strike", "Precise Strike", "crit_chance", 3, 5, "+3% critical chance per rank; a critical hit does x1.75.", {prerequisites = needs("keen_edge")}),
      S("overwhelm", "Overwhelm", "crit_damage", 0.2, 3, "+20% critical damage per rank.", {prerequisites = needs("precise_strike", 2)}),
      S("riposte", "Riposte", "riposte", 1, 1, "For 3 s after you take a hit, your next swing does +50%.", {prerequisites = needs("keen_edge", 2)}),
      S("blade_study", "Blade Study", "abs_study", 0.1, 3, "+10% weapon ABS per rank from every kill.", {prerequisites = needs("keen_edge", 2)}),
      P("sword_dance", "SWORD DANCE", "dance", 30, 480, "L2+Square: 2.5 s of spinning strikes, enemies slowed. 30 Focus.", needs("keen_edge", 3))}},
    {id = "survivor", title = "SURVIVOR", description = "Stay alive, stay supplied.", skills = {
      S("toughness", "Toughness", "max_hp", 0.04, 5, "+4% max HP per rank."),
      S("iron_skin", "Iron Skin", "taken", 0.03, 5, "-3% damage taken per rank.", {prerequisites = needs("toughness")}),
      S("sure_footing", "Sure Footing", "recoil", 0.25, 3, "Recoil after a hit 25% shorter per rank.", {prerequisites = needs("iron_skin"), engine = true}),
      S("evasion", "Evasion", "evasion", 8, 3, "+8 invincibility frames after a hit per rank.", {prerequisites = needs("iron_skin", 2), engine = true}),
      S("camel", "Camel", "thirst", 0.12, 3, "Water drains 12% slower per rank.", {prerequisites = needs("toughness", 2)}),
      S("careful_hands", "Careful Hands", "wear", 0.12, 3, "Weapons wear 12% slower per rank.", {prerequisites = needs("toughness", 2)}),
      P("second_wind", "SECOND WIND", "heal", 40, 1200, "L2+Triangle: heal 30% of max HP at once. 40 Focus.", needs("toughness", 3))}},
    {id = "explorer", title = "EXPLORER", description = "The dungeon itself.", skills = {
      S("fleet_foot", "Fleet Foot", "run_speed", 0.06, 4, "Run 6% faster per rank.", ENGINE),
      S("keen_eyes", "Keen Eyes", "reveal", 1, 2, "Rank 1: the floor map is always yours. Rank 2: monsters show on it.", {prerequisites = needs("fleet_foot"), engine = true}),
      S("treasure_hunter", "Treasure Hunter", "gilda", 0.15, 3, "+15% Gilda from kills per rank."),
      S("scholar", "Scholar", "xp", 0.08, 3, "+8% XP per rank.", {prerequisites = needs("treasure_hunter")}),
      S("lucky_find", "Lucky Find", "lucky", 0.10, 3, "10% chance per rank that a chest also holds a supply item.", {prerequisites = needs("treasure_hunter")}),
      S("atla_sense", "Atla Sense", "atla", 1, 1, "Feel how far the nearest Atla is when a floor starts and as you explore.", {prerequisites = needs("scholar")}),
      P("battle_cry", "BATTLE CRY", "cry", 25, 1500, "L2+Circle: 10 s of +40% damage, +20% taken. 25 Focus.", needs("treasure_hunter", 2))}},
  },
  xiao = {
    {id = "xiao_hunter", title = "HUNTER", description = "Every stone finds its mark.", skills = {
      S("sharp_eye", "Sharp Eye", "crit_chance", 3, 5, "+3% critical chance per rank; a critical hit does x1.75."),
      S("twin_stones", "Twin Stones", "shots", 1, 2, "Each rank fires one more stone, fanned out.", {prerequisites = needs("sharp_eye"), engine = true}),
      S("deadly_aim", "Deadly Aim", "crit_damage", 0.2, 3, "+20% critical damage per rank.", {prerequisites = needs("sharp_eye", 2)}),
      S("hunters_mark", "Hunter's Mark", "execute", 0.1, 3, "+10% damage per rank to an enemy under 30% life.", {prerequisites = needs("sharp_eye", 2)}),
      S("power_shot", "Power Shot", "damage", 0.03, 5, "+3% damage per rank.", {prerequisites = needs("sharp_eye")}),
      P("volley", "VOLLEY", "volley", 30, 900, "L2+Square: 8 s of two more stones and +20% damage. 30 Focus.", needs("sharp_eye", 3))}},
    {id = "xiao_nimble", title = "NIMBLE", description = "A cat lands on her feet.", skills = {
      S("tough_fur", "Tough Fur", "max_hp", 0.04, 5, "+4% max HP per rank."),
      S("nine_lives", "Nine Lives", "taken", 0.03, 5, "-3% damage taken per rank.", {prerequisites = needs("tough_fur")}),
      S("cats_grace", "Cat's Grace", "evasion", 8, 3, "+8 invincibility frames after a hit per rank.", {prerequisites = needs("nine_lives"), engine = true}),
      S("light_paws", "Light Paws", "run_speed", 0.06, 4, "Run 6% faster per rank.", ENGINE),
      S("always_ready", "Always Ready", "recoil", 0.25, 3, "Recoil after a hit 25% shorter per rank.", {prerequisites = needs("light_paws"), engine = true}),
      P("catnap", "CATNAP", "heal", 40, 1200, "L2+Triangle: heal 30% of max HP at once. 40 Focus.", needs("tough_fur", 3))}},
    {id = "xiao_forager", title = "FORAGER", description = "A nose for good things.", skills = {
      S("keen_nose", "Keen Nose", "lucky", 0.10, 3, "10% chance per rank that a chest also holds a supply item."),
      S("shiny_things", "Shiny Things", "gilda", 0.15, 3, "+15% Gilda from kills per rank."),
      S("whiskers", "Whiskers", "reveal", 1, 2, "Rank 1: the floor map is always yours. Rank 2: monsters show on it.", {prerequisites = needs("keen_nose"), engine = true}),
      S("small_sips", "Small Sips", "thirst", 0.12, 3, "Water drains 12% slower per rank.", {prerequisites = needs("shiny_things")}),
      S("curious", "Curious", "xp", 0.08, 3, "+8% XP per rank.", {prerequisites = needs("shiny_things")}),
      P("wild_instinct", "WILD INSTINCT", "cry", 25, 1500, "L2+Circle: 10 s of +40% damage, +20% taken. 25 Focus.", needs("keen_nose", 2))}},
  },
  goro = {
    {id = "goro_might", title = "MIGHT", description = "One swing, one answer.", skills = {
      S("heavy_hand", "Heavy Hand", "damage", 0.03, 5, "+3% damage per rank."),
      S("crushing_blow", "Crushing Blow", "charged_stun", 30, 3, "A charged hit stops an enemy for half a second per rank.", {prerequisites = needs("heavy_hand")}),
      S("bone_breaker", "Bone Breaker", "crit_damage", 0.2, 3, "+20% critical damage per rank.", {prerequisites = needs("heavy_hand", 2)}),
      S("finish_it", "Finish It", "execute", 0.1, 3, "+10% damage per rank to an enemy under 30% life.", {prerequisites = needs("heavy_hand", 2)}),
      S("hammer_study", "Hammer Study", "abs_study", 0.1, 3, "+10% weapon ABS per rank from every kill.", {prerequisites = needs("heavy_hand")}),
      P("earthquake", "EARTHQUAKE", "quake", 35, 900, "L2+Square: the ground bursts around you; all it hits are stopped. 35 Focus.", needs("heavy_hand", 3))}},
    {id = "goro_stone", title = "STONE", description = "Nothing moves him.", skills = {
      S("thick_hide", "Thick Hide", "max_hp", 0.04, 5, "+4% max HP per rank."),
      S("rock_steady", "Rock Steady", "taken", 0.03, 5, "-3% damage taken per rank.", {prerequisites = needs("thick_hide")}),
      S("unmoved", "Unmoved", "recoil", 0.25, 3, "Recoil after a hit 25% shorter per rank.", {prerequisites = needs("rock_steady"), engine = true}),
      S("strong_grip", "Strong Grip", "wear", 0.12, 3, "Weapons wear 12% slower per rank.", {prerequisites = needs("thick_hide", 2)}),
      S("grudge", "Grudge", "riposte", 1, 1, "For 3 s after you take a hit, your next swing does +50%.", {prerequisites = needs("rock_steady", 2)}),
      P("stone_skin", "STONE SKIN", "shield", 40, 1500, "L2+Triangle: 2 s untouchable, then 8 s of half damage taken. 40 Focus.", needs("thick_hide", 3))}},
    {id = "goro_appetite", title = "APPETITE", description = "Fed and happy.", skills = {
      S("big_belly", "Big Belly", "thirst", 0.12, 3, "Water drains 12% slower per rank."),
      S("hearty", "Hearty", "regen", 0.003, 3, "Regain 0.3% of max HP a second per rank."),
      S("bargain", "Bargain Hunter", "gilda", 0.15, 3, "+15% Gilda from kills per rank.", {prerequisites = needs("big_belly")}),
      S("seconds", "Seconds", "lucky", 0.10, 3, "10% chance per rank that a chest also holds a supply item.", {prerequisites = needs("big_belly")}),
      S("practice", "Practice", "xp", 0.08, 3, "+8% XP per rank.", {prerequisites = needs("hearty")}),
      P("second_helping", "SECOND HELPING", "heal", 40, 1200, "L2+Circle: heal 30% of max HP at once. 40 Focus.", needs("hearty", 2))}},
  },
  ruby = {
    {id = "ruby_arcana", title = "ARCANA", description = "Fire, and more fire.", skills = {
      S("spellcraft", "Spellcraft", "damage", 0.03, 5, "+3% damage per rank."),
      S("twin_orbs", "Twin Orbs", "shots", 1, 2, "Each rank casts one more orb, fanned out.", {prerequisites = needs("spellcraft"), engine = true}),
      S("piercing_orbs", "Piercing Orbs", "pierce", 1, 1, "Your orbs fly on through monsters.", {prerequisites = needs("twin_orbs"), engine = true}),
      S("focus_flame", "Focused Flame", "crit_chance", 3, 5, "+3% critical chance per rank; a critical hit does x1.75.", {prerequisites = needs("spellcraft")}),
      S("searing", "Searing", "crit_damage", 0.2, 3, "+20% critical damage per rank.", {prerequisites = needs("focus_flame", 2)}),
      P("starfall", "STARFALL", "dance", 30, 600, "L2+Square: 2.5 s of falling stars around you, enemies slowed. 30 Focus.", needs("spellcraft", 3))}},
    {id = "ruby_grace", title = "GRACE", description = "A genie is hard to pin down.", skills = {
      S("moon_thirst", "Moon Thirst", "lifesteal", 0.02, 3, "Heal 2% of the damage you deal per rank."),
      S("drift", "Drift", "evasion", 8, 3, "+8 invincibility frames after a hit per rank.", {prerequisites = needs("moon_thirst"), engine = true}),
      S("veil", "Veil", "taken", 0.03, 5, "-3% damage taken per rank."),
      S("lamp_born", "Lamp-Born", "max_hp", 0.04, 5, "+4% max HP per rank.", {prerequisites = needs("veil")}),
      S("float", "Float", "run_speed", 0.06, 4, "Run 6% faster per rank.", {prerequisites = needs("drift"), engine = true}),
      P("blessing", "GENIE'S BLESSING", "heal", 40, 1200, "L2+Triangle: heal 30% of max HP at once. 40 Focus.", needs("veil", 3))}},
    {id = "ruby_fortune", title = "FORTUNE", description = "Wishes have a price, and pay.", skills = {
      S("golden_touch", "Golden Touch", "gilda", 0.15, 3, "+15% Gilda from kills per rank."),
      S("wishes", "Three Wishes", "lucky", 0.10, 3, "10% chance per rank that a chest also holds a supply item.", {prerequisites = needs("golden_touch")}),
      S("old_soul", "Old Soul", "xp", 0.08, 3, "+8% XP per rank."),
      S("moon_sense", "Moon Sense", "atla", 1, 1, "Feel how far the nearest Atla is when a floor starts and as you explore.", {prerequisites = needs("old_soul")}),
      S("lamp_light", "Lamp Light", "reveal", 1, 2, "Rank 1: the floor map is always yours. Rank 2: monsters show on it.", {prerequisites = needs("old_soul"), engine = true}),
      P("enchant", "ENCHANT", "cry", 25, 1500, "L2+Circle: 10 s of +40% damage, +20% taken. 25 Focus.", needs("golden_touch", 2))}},
  },
  ungaga = {
    {id = "ungaga_spear", title = "SPEARMAN", description = "Keep them at the point.", skills = {
      S("long_reach", "Long Reach", "reach", 0.1, 3, "The spear's point reaches 10% further per rank.", ENGINE),
      S("keen_point", "Keen Point", "damage", 0.03, 5, "+3% damage per rank."),
      S("true_thrust", "True Thrust", "crit_chance", 3, 5, "+3% critical chance per rank; a critical hit does x1.75.", {prerequisites = needs("keen_point")}),
      S("counter_thrust", "Counter Thrust", "riposte", 1, 1, "For 3 s after you take a hit, your next swing does +50%.", {prerequisites = needs("keen_point", 2)}),
      S("champion_blow", "Champion's Blow", "charged_stun", 30, 3, "A charged hit stops an enemy for half a second per rank.", {prerequisites = needs("true_thrust")}),
      P("whirling_spear", "WHIRLING SPEAR", "dance", 30, 480, "L2+Square: 2.5 s of spinning strikes, enemies slowed. 30 Focus.", needs("keen_point", 3))}},
    {id = "ungaga_shaman", title = "SHAMAN", description = "The spirits keep him.", skills = {
      S("spirit_ward", "Spirit Ward", "taken", 0.03, 5, "-3% damage taken per rank."),
      S("old_bones", "Old Bones", "max_hp", 0.04, 5, "+4% max HP per rank."),
      S("mending", "Mending", "regen", 0.003, 3, "Regain 0.3% of max HP a second per rank.", {prerequisites = needs("old_bones")}),
      S("desert_born", "Desert-Born", "thirst", 0.12, 3, "Water drains 12% slower per rank.", {prerequisites = needs("spirit_ward")}),
      S("steady_feet", "Steady Feet", "recoil", 0.25, 3, "Recoil after a hit 25% shorter per rank.", {prerequisites = needs("spirit_ward", 2), engine = true}),
      P("ancestral_ward", "ANCESTRAL WARD", "shield", 40, 1500, "L2+Triangle: 2 s untouchable, then 8 s of half damage taken. 40 Focus.", needs("spirit_ward", 3))}},
    {id = "ungaga_champion", title = "CHAMPION", description = "The arena taught him.", skills = {
      S("killer", "Killer Instinct", "execute", 0.1, 3, "+10% damage per rank to an enemy under 30% life."),
      S("crowd", "Crowd Pleaser", "gilda", 0.15, 3, "+15% Gilda from kills per rank."),
      S("veteran", "Veteran", "xp", 0.08, 3, "+8% XP per rank.", {prerequisites = needs("crowd")}),
      S("showman", "Showman", "crit_damage", 0.2, 3, "+20% critical damage per rank.", {prerequisites = needs("killer")}),
      S("spear_study", "Spear Study", "abs_study", 0.1, 3, "+10% weapon ABS per rank from every kill.", {prerequisites = needs("veteran")}),
      P("war_chant", "WAR CHANT", "cry", 25, 1500, "L2+Circle: 10 s of +40% damage, +20% taken. 25 Focus.", needs("killer", 2))}},
  },
  osmond = {
    {id = "osmond_gunner", title = "GUNNER", description = "Measured, then fired.", skills = {
      S("calibrated", "Calibrated", "crit_chance", 3, 5, "+3% critical chance per rank; a critical hit does x1.75."),
      S("steady_aim", "Steady Aim", "damage", 0.03, 5, "+3% damage per rank."),
      S("hollow_point", "Hollow Point", "crit_damage", 0.2, 3, "+20% critical damage per rank.", {prerequisites = needs("calibrated", 2)}),
      S("finisher", "Finisher", "execute", 0.1, 3, "+10% damage per rank to an enemy under 30% life.", {prerequisites = needs("steady_aim")}),
      S("ballistics", "Ballistics", "abs_study", 0.1, 3, "+10% weapon ABS per rank from every kill.", {prerequisites = needs("steady_aim", 2)}),
      P("moon_bomb", "MOON BOMB", "quake", 35, 900, "L2+Square: a blast around you; all it hits are stopped. 35 Focus.", needs("calibrated", 3))}},
    {id = "osmond_armor", title = "ARMOR", description = "Moon steel holds.", skills = {
      S("plating", "Plating", "taken", 0.03, 5, "-3% damage taken per rank."),
      S("reinforced", "Reinforced", "max_hp", 0.04, 5, "+4% max HP per rank."),
      S("servos", "Servo Joints", "recoil", 0.25, 3, "Recoil after a hit 25% shorter per rank.", {prerequisites = needs("plating"), engine = true}),
      S("self_repair", "Self-Repair", "regen", 0.003, 3, "Regain 0.3% of max HP a second per rank.", {prerequisites = needs("reinforced")}),
      S("sealed", "Sealed Joints", "wear", 0.12, 3, "Weapons wear 12% slower per rank.", {prerequisites = needs("plating", 2)}),
      P("barrier", "BARRIER", "shield", 40, 1500, "L2+Triangle: 2 s untouchable, then 8 s of half damage taken. 40 Focus.", needs("plating", 3))}},
    {id = "osmond_surveyor", title = "SURVEYOR", description = "He came to study this world.", skills = {
      S("scanner", "Scanner", "reveal", 1, 2, "Rank 1: the floor map is always yours. Rank 2: monsters show on it.", ENGINE),
      S("survey", "Survey", "xp", 0.08, 3, "+8% XP per rank."),
      S("samples", "Samples", "lucky", 0.10, 3, "10% chance per rank that a chest also holds a supply item.", {prerequisites = needs("survey")}),
      S("atla_probe", "Atla Probe", "atla", 1, 1, "Feel how far the nearest Atla is when a floor starts and as you explore.", {prerequisites = needs("scanner")}),
      S("thrusters", "Thrusters", "run_speed", 0.06, 4, "Run 6% faster per rank.", {prerequisites = needs("scanner"), engine = true}),
      P("overclock", "OVERCLOCK", "cry", 25, 1500, "L2+Circle: 10 s of +40% damage, +20% taken. 25 Focus.", needs("survey", 2))}},
  },
}
local BUTTONS = {"square", "triangle", "circle"}
local SKILL_IDS, SKILL, PATH_OF, HERO_OF = {}, {}, {}, {}
local POWER_OF = {} -- [hero][button] = the power node's key
for _, hero in ipairs(CHARACTERS) do
  POWER_OF[hero] = {}
  for p, path in ipairs(HEROES[hero]) do
    local out = {}
    for _, s in ipairs(path.skills) do
      out[#out + 1] = {id = s.id, title = s.title, description = s.description, max_rank = s.max_rank, prerequisites = s.prerequisites}
      local key = path.id .. "." .. s.id
      SKILL_IDS[#SKILL_IDS + 1] = key
      SKILL[key], PATH_OF[key], HERO_OF[key] = s, path, hero
      if s.power then POWER_OF[hero][BUTTONS[p]] = key end
    end
    local registered, err = call(game.skills.register, {id = path.id, title = path.title, description = path.description, skills = out})
    if not registered then moonmod.log("warn", "skill tree " .. path.id .. ": " .. errmsg(err)) end
  end
end
local function node_id(skill) return ID .. ":" .. skill end
local function cost_of(skill, rank) return (SKILL[skill].power and rank == 1) and 2 or 1 end
local function trees_of(hero)
  local ids = {}
  for i, path in ipairs(HEROES[hero] or HEROES.toan) do ids[i] = path.id end
  return ids
end

-- Per-save-slot, per-character state ---------------------------------------------------------------
-- slots[key] = {chars = {[id] = {level, xp, ranks, hp_bonus}}, mastery = {[item_no] = kills}}
local slot_key, slot = nil, nil
local active = nil
local function all_slots() local d = moonmod.storage.get("slots"); return type(d) == "table" and d or {} end
local function save_slot()
  if not slot_key or not slot then return end
  local data = all_slots()
  data[slot_key] = slot
  moonmod.storage.set("slots", data)
end
local function char(id)
  if not slot or not id then return nil end
  local c = slot.chars[id]
  if type(c) ~= "table" then c = {}; slot.chars[id] = c end
  c.level = math.max(1, math.min(MAX_LEVEL, math.floor(tonumber(c.level) or 1)))
  c.xp = math.max(0, math.floor(tonumber(c.xp) or 0))
  c.ranks = type(c.ranks) == "table" and c.ranks or {}
  return c
end
local function rank(skill, id) local c = char(id or active); return c and (c.ranks[skill] or 0) or 0 end
-- The total of one effect kind over a hero's nodes (the active hero's by default).
local function eff(kind, id)
  local hero = id or active
  local total = 0
  if not hero or not HEROES[hero] then return 0 end
  for _, path in ipairs(HEROES[hero]) do
    for _, sk in ipairs(path.skills) do
      if sk.effect == kind then total = total + (sk.per or 1) * rank(path.id .. "." .. sk.id, hero) end
    end
  end
  return total
end
-- XP curve: kills pay 0.45 x enemy max HP + reward_exp, so a cave-tier kill is about 18-30 XP.
-- With xp_needed(L) = 40 + 22L + 3L^2 that reaches roughly L6-8 at 50 kills, L10-13 at 150, L16-19 at 400;
-- level 10 takes about 75-125 kills and level 40 about 2,700-4,500, so the curve stays as is.
local function xp_needed(level) return 40 + 22 * level + 3 * level * level end
local function points_earned(level) return (level - 1) + math.floor((level - 1) / 5) end
local function points_free(id)
  local c = char(id or active)
  if not c then return 0 end
  local spent = 0
  for _, skill in ipairs(SKILL_IDS) do
    if HERO_OF[skill] == (id or active) then
      for r = 1, (c.ranks[skill] or 0) do spent = spent + cost_of(skill, r) end
    end
  end
  return points_earned(c.level) - spent
end

-- The framework keeps one rank per node, and each hero's nodes are their own.
local function push_ranks()
  for _, skill in ipairs(SKILL_IDS) do try(game.skills.set_rank, {id = node_id(skill), rank = rank(skill, HERO_OF[skill])}) end
end

-- Max HP: the game's own value grows from items; +3 per level and Toughness on top.
local function apply_max_hp(id)
  local c = char(id)
  local info = c and try(game.characters.get, {id = id})
  if not info or type(info.max_hp) ~= "number" then return end
  local bonus_now = c.hp_bonus or 0
  local base = info.max_hp - bonus_now
  local want = math.floor((base + 3 * (c.level - 1)) * (1 + eff("max_hp", id)) + 0.5) - base
  if want ~= bonus_now and try(game.player.set, {character = id, max_hp = math.max(1, math.min(999, base + want))}) then
    c.hp_bonus = want
  end
end

-- Focus, powers and timers ---------------------------------------------------------------------------
local focus = 100
local cooldown = {square = 0, triangle = 0, circle = 0}
local frame = 0
local cry_until, riposte_until, dance_until, dance_next, dance_first = 0, 0, 0, 0, false
local volley_until, shield_until = 0, 0
-- The active hero's power on a button: {skill = node key, def = its node}.
local function power_on(button)
  local key = active and POWER_OF[active] and POWER_OF[active][button]
  return key and {skill = key, def = SKILL[key]} or nil
end
local function power_count()
  local n = 0
  for _, b in ipairs(BUTTONS) do local p = power_on(b); if p and rank(p.skill) >= 2 then n = n + 1 end end
  return n
end
local function has_power()
  for _, b in ipairs(BUTTONS) do local p = power_on(b); if p and rank(p.skill) >= 1 then return true end end
  return false
end
local function focus_max() return 100 + 20 * power_count() end
local function power_cost(p) return p.def.cost - (rank(p.skill) >= 2 and 10 or 0) end
local function power_cooldown(p) return math.floor(p.def.cooldown * (rank(p.skill) >= 3 and 0.7 or 1)) end

-- Engine tuning (Phase 2): one owner-scoped call with every knob the ENGINE nodes use.
local tuning_key = nil
local function apply_tuning()
  if not TUNING then return end
  local volley = frame < volley_until
  local shots = math.min(2, math.floor(eff("shots") + 0.5) + (volley and 2 or 0))
  local key = table.concat({active or "", eff("attack_speed"), eff("recoil"), eff("evasion"), eff("run_speed"), eff("reveal"),
                            shots, eff("pierce"), eff("reach")}, ":")
  if key == tuning_key then return end
  tuning_key = key
  try(game.player.tuning_set, {
    attack_anim_speed = 1 + eff("attack_speed"),
    recoil_scale = math.max(0.25, 1 - eff("recoil")),
    invincible_bonus_frames = math.min(120, math.floor(eff("evasion"))),
    run_speed = 1 + eff("run_speed"),
    map_reveal = eff("reveal") >= 1,
    monster_reveal = eff("reveal") >= 2,
    extra_shots = shots,
    shots_pierce = eff("pierce") >= 1,
    reach_scale = 1 + eff("reach")
  })
end

-- Combat formulas ------------------------------------------------------------------------------------
local mastery_weapon = nil
local function mastery_rank(kills)
  local r = 0
  for i, need in ipairs(MASTERY_KILLS) do if kills >= need then r = i end end
  return r
end
local function update_formulas()
  local c = char(active)
  if not c then return end
  local cry = frame < cry_until
  local riposte = frame < riposte_until
  local volley = frame < volley_until
  try(game.combat.register_formula, {id = "level", operation = "multiply", priority = 50,
      value = (1 + 0.025 * (c.level - 1)) * (1 + eff("damage")) * (cry and 1.4 or 1) * (riposte and 1.5 or 1) * (volley and 1.2 or 1)})
  try(game.combat.register_formula, {id = "execute", operation = "multiply", priority = 51, value = 1 + eff("execute"),
      target_hp_below_percent = 30})
  local player = try(game.player.get)
  local weapon = player and player.weapon
  mastery_weapon = weapon and weapon.item_no or nil
  local speed = weapon and tonumber(weapon.speed) or 0
  try(game.combat.register_formula, {id = "crit", operation = "chance_multiply", priority = 47,
      value = 1.75 + eff("crit_damage"),
      chance = math.min(100, 5 + eff("crit_chance") + speed * 0.05)})
  try(game.combat.register_formula, {id = "variance", operation = "random_multiply", value = 1, min_value = 0.9, max_value = 1.1, priority = 46})
  local taken = (1 - math.min(0.4, 0.008 * (c.level - 1))) * (1 - eff("taken")) * (cry and 1.2 or 1) * (frame < shield_until and 0.5 or 1)
  try(game.combat.register_player_formula, {id = "toughness", operation = "multiply", value = taken, priority = 50})
  if mastery_weapon then
    local bonus = mastery_rank(slot.mastery[tostring(mastery_weapon)] or 0) * 0.02
    try(game.combat.register_formula, {id = "mastery", operation = "multiply", value = 1 + bonus, priority = 52, weapon_id = mastery_weapon})
  end
end
local function register_weapon_formulas()
  for _, model in ipairs(UNDEAD) do
    try(game.combat.register_formula, {id = "cross_hinder_" .. model, operation = "multiply", value = 2, priority = 40,
        weapon_id = WEAPON.cross_hinder, native_model_id = model})
  end
  try(game.combat.register_formula, {id = "mobius_ring", operation = "ramp_multiply", value = 1.6, rate_per_second = 0.025,
      reset_after_frames = 360, priority = 45, weapon_id = WEAPON.mobius_ring})
  try(game.combat.register_player_formula, {id = "agas_sword", operation = "add", value = -15, priority = 60, weapon_id = WEAPON.agas_sword})
end
register_weapon_formulas()

-- HUD: XP bar labelled with the level, the Focus bar once a power is learned; the Journal's sheet.
local hud = {}
local function update_hud()
  local c = char(active)
  if not c then return end
  local need = c.level >= MAX_LEVEL and 1 or xp_needed(c.level)
  local xp = c.level >= MAX_LEVEL and 1 or math.min(c.xp, need)
  local key = c.level .. ":" .. xp .. ":" .. need
  if hud.xp ~= key then hud.xp = key; try(game.render.bar_register, {id = "xp", label = "LV" .. c.level, current = xp, max = need}) end
  local powers = has_power()
  local fkey = powers and (math.floor(focus) .. ":" .. focus_max()) or "off"
  if hud.focus ~= fkey then
    hud.focus = fkey
    if powers then try(game.render.bar_register, {id = "focus", label = "FOCUS", current = math.floor(focus), max = focus_max()})
    else try(game.render.bar_remove, {id = "focus"}) end
  end
  -- Character sheet (Journal > Character).
  local free = points_free(active)
  local kills = mastery_weapon and (slot.mastery[tostring(mastery_weapon)] or 0) or 0
  local mrank = mastery_rank(kills)
  local lines = {
    c.level >= MAX_LEVEL and ("Level " .. c.level .. "  (max)") or string.format("Level %d   XP %d / %d", c.level, c.xp, need),
    string.format("Skill points: %d", free),
    string.format("Damage +%d%%   Crit %d%%", math.floor(((1 + 0.025 * (c.level - 1)) * (1 + eff("damage")) - 1) * 100 + 0.5),
                  math.min(100, 5 + math.floor(eff("crit_chance")))),
    string.format("Damage taken -%d%%", math.floor((1 - (1 - math.min(0.4, 0.008 * (c.level - 1))) * (1 - eff("taken"))) * 100 + 0.5))
  }
  if powers then lines[#lines + 1] = string.format("Focus %d / %d", math.floor(focus), focus_max()) end
  if mastery_weapon then lines[#lines + 1] = string.format("Mastery %d/5  (%d kills)", mrank, kills) end
  local hint
  if not HEROES[active] then hint = title(active) .. " has no paths of their own; Toan's are shown."
  elseif free > 0 then hint = "Cross trains the selected skill."
  else hint = "Next point: level " .. (c.level + 1) end
  local skey = table.concat(lines, "|") .. "|" .. hint
  if hud.sheet ~= skey then
    hud.sheet = skey
    try(game.ui.sheet_set, {title = title(active):upper(), lines = lines, hint = hint, trees = trees_of(active),
        progress = c.level >= MAX_LEVEL and 1 or math.min(1, c.xp / need),
        progress_label = c.level >= MAX_LEVEL and "MAX LEVEL" or string.format("XP %d / %d", c.xp, need)})
  end
end

-- Loading a save slot and switching characters -------------------------------------------------------
-- A game that has not been saved yet (a new game, or a --jump test) keeps its progress under "unsaved"
-- and carries it into the slot it is first saved to.
local function load_slot()
  local identity = try(game.save.slot_id)
  local key = identity and identity.slot_id and (tostring(identity.slot_id) .. ":" .. tostring(identity.slot_generation)) or nil
  local player = try(game.player.get)
  if not key and not player then key = nil elseif not key then key = "unsaved" end
  if key == slot_key then return end
  local previous = slot_key
  slot_key, active, hud = key, nil, {}
  if not key then
    slot = nil
    try(game.render.bar_remove, {id = "xp"}); try(game.render.bar_remove, {id = "focus"}); try(game.ui.sheet_clear)
    return
  end
  local data = all_slots()
  if previous == "unsaved" and key ~= "unsaved" and type(data[key]) ~= "table" and type(data.unsaved) == "table" then
    data[key], data.unsaved = data.unsaved, nil
    moonmod.storage.set("slots", data)
  end
  local saved = data[key]
  slot = type(saved) == "table" and saved or {}
  slot.mastery = type(slot.mastery) == "table" and slot.mastery or {}
  if type(slot.chars) ~= "table" then
    slot.chars = {}
    local party = try(game.party.list) or {}
    for _, member in ipairs(party) do
      if type(member) == "table" and member.id then slot.chars[member.id] = {level = 1, xp = 0, ranks = {}} end
    end
    toast("RPG: Character Paths. Kills give XP; every hero spends skill points in Journal > Character (K)", 480)
  end
  save_slot()
end
local function set_active(id)
  if id == active then return end
  active = id
  hud = {}
  push_ranks()
  apply_max_hp(id)
  apply_tuning()
  update_formulas()
  update_hud()
end

-- XP --------------------------------------------------------------------------------------------------
local function gain_xp(id, amount, quiet)
  local c = char(id)
  if not c or amount <= 0 then return end
  amount = math.max(1, math.floor(amount * setting("xp_rate", 100) / 100 * (1 + eff("xp", id)) + 0.5))
  c.xp = c.xp + amount
  local leveled = false
  while c.level < MAX_LEVEL and c.xp >= xp_needed(c.level) do
    c.xp = c.xp - xp_needed(c.level)
    c.level = c.level + 1
    leveled = true
  end
  if c.level >= MAX_LEVEL then c.xp = 0 end
  if not quiet and setting("xp_toasts", true) then toast("+" .. amount .. " XP", 90) end
  if leveled then
    apply_max_hp(id)
    try(game.player.heal, {character = id, amount = 30})
    local free = points_free(id)
    toast(title(id):upper() .. " reached LEVEL " .. c.level .. "!  " .. free .. " skill point" .. (free == 1 and "" or "s") .. " (Journal > Character)", 360)
    if id == active then update_formulas() end
  end
end

on("game.enemy_defeated", function(event)
  load_slot()
  if not slot or not active then return end
  local hp = type(event.enemy_max_hp) == "number" and event.enemy_max_hp or 0
  local exp = type(event.reward_exp) == "number" and event.reward_exp or 0
  local reward = hp > 0 and (hp * 0.45 + exp) or math.max(3, exp)
  local info = event.entity and try(game.scripts.call_function, {id = "moonmod.dungeon-plus:enemy_bonus", arguments = {entity = event.entity}})
  if type(info) == "table" and type(info.xp_multiplier) == "number" then reward = reward * info.xp_multiplier end
  gain_xp(active, reward)
  for _, id in ipairs(CHARACTERS) do
    if id ~= active and slot.chars[id] then gain_xp(id, reward * 0.25, true) end
  end
  -- Weapon mastery and Blade Study.
  local item = type(event.native_weapon_id) == "number" and event.native_weapon_id or mastery_weapon
  if item and item >= 257 then
    local key = tostring(item)
    local before = mastery_rank(slot.mastery[key] or 0)
    slot.mastery[key] = (slot.mastery[key] or 0) + 1
    local after = mastery_rank(slot.mastery[key])
    if after > before then toast("Weapon mastery " .. after .. "/5: +" .. (after * 2) .. "% damage with this weapon", 300); update_formulas() end
    local study = eff("abs_study")
    if study > 0 and exp > 0 then
      local player = try(game.player.get)
      local weapon = player and player.weapon
      if weapon and weapon.id then
        try(game.weapons.abs_add, {id = weapon.id, character = player.character, slot = weapon.slot, amount = math.max(1, math.floor(exp * study + 0.5))})
      end
    end
  end
  -- Treasure Hunter.
  local hunter = eff("gilda")
  local money = type(event.reward_money) == "number" and event.reward_money or 0
  if hunter > 0 and money > 0 then try(game.economy.add, {amount = math.min(32767, math.floor(money * hunter + 0.5))}) end
  save_slot()
  update_hud()
end)

-- Training: Cross on a node in the Journal's Character page (or the Mod Manager's Skills tab) -------
on("skills.train_requested", function(event)
  load_slot()
  local id = type(event.id) == "string" and event.id or ""
  local skill = id:sub(#ID + 2)
  if id:sub(1, #ID + 1) ~= ID .. ":" or not SKILL[skill] then return end
  local c = char(active)
  if not c then toast("Load a game first"); return end
  if HERO_OF[skill] ~= active then toast(SKILL[skill].title .. " is " .. title(HERO_OF[skill]) .. "'s. Switch to " .. title(HERO_OF[skill]) .. " to train it"); return end
  local def = SKILL[skill]
  local current = c.ranks[skill] or 0
  if current >= def.max_rank then toast(def.title .. " is at its maximum rank"); return end
  if def.engine and not TUNING then toast(def.title .. " needs the next engine update (player tuning). Pick another skill for now"); return end
  local cost = cost_of(skill, current + 1)
  if points_free() < cost then
    toast("Needs " .. cost .. " skill point" .. (cost == 1 and "" or "s") .. ". Next point at level " .. (c.level + 1)); return
  end
  local changed, err = game.skills.set_rank({id = node_id(skill), rank = current + 1})
  if not changed then toast(errmsg(err)); return end
  c.ranks[skill] = current + 1
  save_slot()
  apply_max_hp(active)
  apply_tuning()
  update_formulas()
  update_hud()
  toast(def.title .. " " .. c.ranks[skill] .. "/" .. def.max_rank .. "   (" .. points_free() .. " point" .. (points_free() == 1 and "" or "s") .. " left)")
end)

-- Powers ----------------------------------------------------------------------------------------------
local function bind(id, keys)
  local ok, err = game.input.bind({id = id, keys = keys})
  if not ok then moonmod.log("warn", "bind " .. id .. ": " .. errmsg(err)) end
end
bind("power_hold", {"Gamepad:L2"})
bind("power_square", {"Gamepad:x"})
bind("power_triangle", {"Gamepad:y"})
bind("power_circle", {"Gamepad:b"})
bind("key_square", {moonmod.settings.get("sword_dance_key") or "F4"})
bind("key_triangle", {moonmod.settings.get("second_wind_key") or "F5"})
bind("key_circle", {moonmod.settings.get("battle_cry_key") or "F6"})

local function dance_strike(player)
  local pos = player and player.position
  local found = pos and try(game.physics.query, {shape = "sphere", center = pos, radius = setting("sword_dance_radius", 180)})
  local attack = player and player.weapon and tonumber(player.weapon.attack) or 10
  local hits = 0
  for _, match in ipairs(found and found.matches or {}) do
    if try(game.combat.damage, {entity = match.entity, amount = math.max(1, math.floor(attack * 0.6 + 10))}) then hits = hits + 1 end
    if dance_first then try(game.combat.status_add, {entity = match.entity, status = "slow", duration_frames = 120}) end
  end
  dance_first = false
  return hits
end
local function blast(player, radius, amount, status, frames)
  local pos = player and player.position
  local found = pos and try(game.physics.query, {shape = "sphere", center = pos, radius = radius})
  local hits = 0
  for _, match in ipairs(found and found.matches or {}) do
    if try(game.combat.damage, {entity = match.entity, amount = amount}) then hits = hits + 1 end
    if status then try(game.combat.status_add, {entity = match.entity, status = status, duration_frames = frames}) end
  end
  return hits
end
local function cast(button, player)
  local power = power_on(button)
  if not power or rank(power.skill) < 1 then return end
  local name = power.def.title
  if cooldown[button] > frame then toast(name .. " ready in " .. math.ceil((cooldown[button] - frame) / 60) .. " s", 90); return end
  local cost = power_cost(power)
  if focus < cost then toast("Not enough Focus (" .. cost .. ")", 90); return end
  focus = focus - cost
  cooldown[button] = frame + power_cooldown(power)
  local kind = power.def.power
  if kind == "dance" then
    dance_until, dance_next, dance_first = frame + 150, frame, true
    local hits = dance_strike(player)
    toast(name .. "!  " .. hits .. " hit", 150)
  elseif kind == "heal" then
    try(game.player.heal, {amount = math.max(1, math.floor(player.max_hp * 0.3))})
    try(game.player.invincible, {frames = 90})
    toast(name, 150)
  elseif kind == "cry" then
    cry_until = frame + 600
    update_formulas()
    toast(name .. "!  10 s", 150)
  elseif kind == "quake" then
    local attack = player.weapon and tonumber(player.weapon.attack) or 10
    if player.position then try(game.effects.burst, {kind = "explosion", position = player.position, scale = 2}) end
    local hits = blast(player, setting("sword_dance_radius", 180) + 40, math.max(1, math.floor(attack * 1.5 + 20)), "stop", 120)
    toast(name .. "!  " .. hits .. " hit", 150)
  elseif kind == "shield" then
    try(game.player.invincible, {frames = 120})
    shield_until = frame + 600
    update_formulas()
    toast(name .. "  (10 s)", 150)
  elseif kind == "volley" then
    volley_until = frame + 480
    apply_tuning()
    update_formulas()
    toast(name .. "!  8 s", 150)
  end
  update_hud()
end

local lifesteal_next = 0
-- After a hit: Riposte is spent, the Expanded weapon effects fire -------------------------------------
on("game.enemy_hit", function(event)
  if type(event.damage) ~= "number" or event.damage <= 0 then return end
  if riposte_until > frame then riposte_until = 0; update_formulas() end
  local stun = eff("charged_stun")
  if stun > 0 and event.charged and event.entity then
    try(game.combat.status_add, {entity = event.entity, status = "stop", duration_frames = math.floor(stun)})
  end
  local steal = eff("lifesteal")
  if steal > 0 and frame >= lifesteal_next then
    lifesteal_next = frame + 30
    try(game.player.heal, {amount = math.max(1, math.floor(event.damage * steal + 0.5))})
  end
  local item, roll = event.native_weapon_id, math.random()
  if item == WEAPON.brave_ark then
    for _, status in ipairs({"freeze", "poison", "curse", "goo"}) do try(game.player.status_remove, {status = status}) end
  elseif item == WEAPON.heavens_cloud and roll < 0.5 then try(game.combat.status_add, {entity = event.entity, status = "slow", duration_frames = 300})
  elseif item == WEAPON.snail and roll < 0.05 then try(game.combat.status_add, {entity = event.entity, status = "slow", duration_frames = 300})
  elseif item == WEAPON.frozen_tuna and event.element ~= 1 and roll < 0.05 then try(game.combat.status_add, {entity = event.entity, status = "stop", duration_frames = 180})
  elseif item == WEAPON.cactus then try(game.player.thirst_set, {restore = event.damage / 10}) end
end)

-- Weapon loot rolls ------------------------------------------------------------------------------------
on("game.item_picked_up", function(event)
  if event.kind ~= "weapon" or setting("weapon_loot_rolls", true) == false then return end
  local item, owner, where = tonumber(event.native_item_no), event.character, tonumber(event.slot)
  if type(owner) == "number" then owner = CHARACTERS[owner + 1] end  -- the event gives 0-5; instances use ids
  if not item or item < 257 or not owner or not where then return end
  local roll = math.random(100)
  local rarity = roll <= 1 and {"Legendary", 0.35, 0.45} or roll <= 5 and {"Exquisite", 0.20, 0.30} or
                 roll <= 15 and {"Superior", 0.10, 0.20} or roll <= 40 and {"Fine", 0.05, 0.10} or nil
  if not rarity then return end
  local weapon = try(game.weapons.get, "chronicle:weapon:" .. item)
  for _, owned in ipairs(weapon and weapon.instances or {}) do
    if owned.character == owner and owned.slot == where then
      local stats, factor = owned.stats or {}, 1 + rarity[2] + math.random() * (rarity[3] - rarity[2])
      local request = {id = weapon.id, character = owner, slot = where}
      for _, k in ipairs({"attack", "endurance", "speed", "magic", "durability"}) do
        request[k] = math.max(0, math.min(32767, math.floor((stats[k] or 0) * factor + 0.5)))
      end
      if try(game.weapons.stats_set, request) then toast(rarity[1]:upper() .. " weapon!  +" .. math.floor((factor - 1) * 100 + 0.5) .. "% stats", 300) end
      return
    end
  end
end)

-- Lucky Find: a chest may also hold a supply item --------------------------------------------------------
on("game.chest.opened", function()
  local lucky = math.floor(eff("lucky") * 10 + 0.5)
  if lucky <= 0 or math.random() >= 0.10 * lucky then return end
  local pick = nil
  if lucky >= 3 and math.random() < 0.02 then pick = {180, "Fruit of Eden"}
  else
    local total = 0
    for _, it in ipairs(LUCKY_ITEMS) do total = total + it[3] end
    local roll = math.random() * total
    for _, it in ipairs(LUCKY_ITEMS) do
      roll = roll - it[3]
      if roll < 0 then pick = it; break end
    end
    pick = pick or LUCKY_ITEMS[1]
  end
  if try(game.items.give, {id = "chronicle:item:" .. pick[1], count = 1}) then toast("Lucky Find: " .. pick[2], 240) end
end)

-- Camel: part of each sip of water lost comes back --------------------------------------------------------
on("game.player.thirst_changed", function(event)
  if event.source ~= "native" or type(event.previous_water) ~= "number" or type(event.water) ~= "number" then return end
  local lost = event.previous_water - event.water
  local share = eff("thirst")
  if lost > 0 and lost < 5 and share > 0 then try(game.player.thirst_set, {restore = lost * share, character = event.character or "active"}) end
end)

-- Atla Sense ----------------------------------------------------------------------------------------------
local atla_next = 0
-- Direction to (dx, dz): relative to the camera's view (eye -> target) when a dungeon camera is readable,
-- else a compass word with north = -z.
local function atla_direction(dx, dz)
  local cam = try(game.render.camera_get)
  local fx, fz = nil, nil
  if type(cam) == "table" and type(cam.eye) == "table" and type(cam.target) == "table" then
    fx, fz = (cam.target.x or 0) - (cam.eye.x or 0), (cam.target.z or 0) - (cam.eye.z or 0)
    if fx * fx + fz * fz < 1e-6 then fx = nil end
  end
  if fx then
    local fl = math.sqrt(fx * fx + fz * fz)
    local dl = math.sqrt(dx * dx + dz * dz)
    if dl < 1e-6 then return "right here" end
    local fwd = (fx * dx + fz * dz) / (fl * dl)
    local side = (fx * dz - fz * dx) / (fl * dl) -- sign picks left/right in the x/z plane
    local ahead = fwd > 0.38 and "ahead" or (fwd < -0.38 and "behind" or nil)
    local lr = side > 0.38 and "right" or (side < -0.38 and "left" or nil)
    if ahead and lr then return ahead .. "-" .. lr end
    return ahead or lr or "ahead"
  end
  local names = {"north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"}
  local angle = math.atan(dx, -dz) -- 0 = north (-z), clockwise toward east (+x)
  return names[(math.floor(angle / (math.pi / 4) + 0.5) % 8) + 1]
end
local function sense_atla(player)
  local list = try(game.georama.atla_list)
  local pos = player and player.position
  if type(list) ~= "table" or not pos then return end
  local spheres = list.atla or list.spheres or list
  local best, bx, bz = nil, 0, 0
  for _, a in ipairs(spheres) do
    local p = type(a) == "table" and (a.position or a.world_position) or nil
    if type(p) == "table" and type(p.x) == "number" and type(p.z) == "number" then
      local d = math.sqrt((p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2)
      if not best or d < best then best, bx, bz = d, p.x - pos.x, p.z - pos.z end
    end
  end
  if best then toast(string.format("Atla Sense: %d units, %s", math.floor(best), atla_direction(bx, bz)), 240)
  else toast("Atla Sense: no Atla left on this floor", 180) end
end
on("game.world.location_changed", function(event)
  if event and event.context == "dungeon" and eff("atla") > 0 then atla_next = frame + 180 end
end)

-- Per frame: powers; every 10 frames: Focus, Riposte, durability, HUD and the sheet -----------------------
local durability_key, durability_last, last_hp, last_hp_char = nil, nil, nil, nil
on("game.tick", function(event)
  frame = event and event.frame or frame + 1
  if slot and active then
    local hold = game.input.state({id = "power_hold"})
    local held = hold and hold.down
    if held then try(game.input.block_native, {buttons = {"square", "triangle", "circle"}, frames = 2}) end
    for _, button in ipairs({"square", "triangle", "circle"}) do
      local pad = game.input.consume({id = "power_" .. button})
      local key = game.input.consume({id = "key_" .. button})
      if (pad and pad.pressed and held) or (key and key.pressed) then
        local player = try(game.player.get)
        if player and player.position then cast(button, player) end
      end
    end
    if frame < dance_until and frame >= dance_next then
      dance_next = frame + 30
      dance_strike(try(game.player.get))
    end
  end
  if frame % 10 ~= 0 then return end
  if frame % 30 == 0 then load_slot() end
  if not slot then return end
  local player = try(game.player.get)
  if not player then return end
  set_active(player.character)
  focus = math.min(focus_max(), focus + 1.0)
  -- Riposte: a lost hit point arms the next swing.
  if eff("riposte") > 0 and last_hp and last_hp_char == player.character and player.hp < last_hp and player.hp > 0 then
    riposte_until = frame + 180
    update_formulas()
  end
  last_hp, last_hp_char = player.hp, player.character
  if (cry_until > 0 and frame >= cry_until) or (riposte_until > 0 and frame >= riposte_until) or
     (volley_until > 0 and frame >= volley_until) or (shield_until > 0 and frame >= shield_until) then
    if frame >= cry_until then cry_until = 0 end
    if frame >= riposte_until then riposte_until = 0 end
    if frame >= shield_until then shield_until = 0 end
    if frame >= volley_until then volley_until = 0; apply_tuning() end
    update_formulas()
  end
  -- Regeneration: a share of max HP each second.
  local regen = eff("regen")
  if regen > 0 and frame % 60 == 0 and player.hp and player.max_hp and player.hp > 0 and player.hp < player.max_hp then
    try(game.player.heal, {amount = math.max(1, math.floor(player.max_hp * regen + 0.5))})
  end
  if (player.weapon and player.weapon.item_no) ~= mastery_weapon then update_formulas() end
  -- Careful Hands: part of each point of wear comes back.
  local weapon = player.weapon
  if weapon and type(weapon.durability) == "number" and player.position then
    local key = player.character .. ":" .. weapon.slot .. ":" .. weapon.item_no
    local now = math.floor(weapon.durability)
    local chance = eff("wear")
    if chance > 0 and key == durability_key and durability_last and now < durability_last and durability_last - now <= 3 then
      local back = 0
      for _ = 1, durability_last - now do if math.random() < chance then back = back + 1 end end
      if back > 0 then
        now = math.min(weapon.durability_max or now + back, now + back)
        try(game.weapons.durability_set, {id = weapon.id, character = player.character, slot = weapon.slot, durability = now})
      end
    end
    durability_key, durability_last = key, now
  end
  -- Atla Sense: on arrival, then every 15 s while exploring.
  if eff("atla") > 0 and player.position and atla_next > 0 and frame >= atla_next then
    atla_next = frame + 900
    sense_atla(player)
  end
  update_hud()
end)

-- Manager actions --------------------------------------------------------------------------------------
for _, action in ipairs({
  {"open", "Character Page", "Open Journal > Character (the active hero's paths)"},
  {"progress", "Party Levels", "Every character's level, XP and free skill points"},
  {"mastery", "Equipped Weapon Mastery", "Kills with the equipped weapon and its mastery bonus"},
  {"respec", "Reset the Active Hero's Skills", "Refund every point (100 Gilda per level)"},
  {"test_levels", "Grant test levels", "Testing: give the active character 5 levels of XP"}
}) do try(game.ui.register, {id = action[1], label = action[2], description = action[3]}) end
on("ui.action", function(action)
  load_slot()
  if action.id == "open" then
    local opened, err = call(game.ui.sheet_open)
    if not opened then toast("Character page: " .. errmsg(err)) end
    return
  end
  if not slot then toast("Load a game first"); return end
  if action.id == "progress" then
    local parts = {}
    for _, id in ipairs(CHARACTERS) do
      local c = slot.chars[id] and char(id)
      if c then parts[#parts + 1] = string.format("%s L%d (%d/%d, %d pts)", title(id), c.level, c.xp, xp_needed(c.level), points_free(id)) end
    end
    toast(table.concat(parts, "  |  "), 600)
  elseif action.id == "mastery" then
    local kills = mastery_weapon and slot.mastery[tostring(mastery_weapon)] or 0
    local r = mastery_rank(kills)
    toast(string.format("WEAPON MASTERY %d/5  (%d kills%s)  +%d%% damage", r, kills,
        MASTERY_KILLS[r + 1] and (", next at " .. MASTERY_KILLS[r + 1]) or "", r * 2), 480)
  elseif action.id == "test_levels" then
    local player = try(game.player.get)
    if player and player.character then set_active(player.character) end
    local c = active and char(active)
    if not c then toast("Load a game first"); return end
    if c.level >= MAX_LEVEL then toast(title(active) .. " is already at the level cap"); return end
    local need, target = -c.xp, math.min(MAX_LEVEL, c.level + 5)
    for l = c.level, target - 1 do need = need + xp_needed(l) end
    -- gain_xp scales by xp_rate and Scholar, so divide that back out (plus 1 to beat rounding).
    local scale = setting("xp_rate", 100) / 100 * (1 + eff("xp", active))
    gain_xp(active, need / math.max(0.01, scale) + 1, true)
    save_slot()
    toast(string.format("TEST: %s is now LEVEL %d with %d skill points", title(active), c.level, points_free(active)), 360)
  elseif action.id == "respec" then
    local player = try(game.player.get)
    local hero = player and player.character or active
    local c = hero and char(hero)
    if not c then return end
    local cost = math.min(32767, 100 * c.level)
    if not try(game.economy.spend, {amount = cost}) then toast("Reset costs " .. cost .. " Gilda"); return end
    c.ranks = {}
    save_slot(); push_ranks(); apply_max_hp(hero); tuning_key = nil; apply_tuning(); update_formulas(); hud = {}; update_hud()
    toast(title(hero) .. "'s skills reset. " .. points_free(hero) .. " points to spend")
  end
end)

on("settings.changed", function() update_formulas() end)

-- Sandbox sessions: drop every bonus, tuning knob and HUD element for the run (formulas cannot be removed,
-- so each one is replaced with x1), keep nothing under "unsaved", and pick the save back up afterwards.
local function stand_down()
  local neutral = {"level", "execute", "crit", "variance", "mastery", "mobius_ring"}
  for _, model in ipairs(UNDEAD) do neutral[#neutral + 1] = "cross_hinder_" .. model end
  for _, id in ipairs(neutral) do try(game.combat.register_formula, {id = id, operation = "multiply", value = 1}) end
  for _, id in ipairs({"toughness", "agas_sword"}) do try(game.combat.register_player_formula, {id = id, operation = "multiply", value = 1}) end
  try(game.player.tuning_clear)
  try(game.render.bar_remove, {id = "xp"}); try(game.render.bar_remove, {id = "focus"}); try(game.ui.sheet_clear)
  slot_key, slot, active, hud, tuning_key, mastery_weapon = nil, nil, nil, {}, nil, nil
  focus, cooldown = 100, {square = 0, triangle = 0, circle = 0}
  cry_until, riposte_until, dance_until, dance_next, atla_next, volley_until, shield_until = 0, 0, 0, 0, 0, 0, 0
  durability_key, durability_last, last_hp, last_hp_char = nil, nil, nil, nil
end
local function set_sandbox(now)
  if now == in_sandbox then return end
  in_sandbox = now
  if now then stand_down() else register_weapon_formulas(); load_slot() end
end
moonmod.on("game.session.started", function() set_sandbox(true) end)
moonmod.on("game.session.ended", function() set_sandbox(false) end)
local session = try(game.session.get)
set_sandbox(type(session) == "table" and session.kind == "sandbox")
if not in_sandbox then load_slot() end
moonmod.log("info", "RPG: Character Paths ready" .. (TUNING and " (engine tuning on)" or " (engine tuning not available yet: Quick Blade, Sure Footing, Evasion, Fleet Foot, Keen Eyes wait)"))
