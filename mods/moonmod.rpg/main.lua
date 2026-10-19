-- RPG: Character Paths 1.0. Kills give XP; levels give max HP, damage, toughness and skill points.
-- Toan spends points on three paths (Swordsman, Survivor, Explorer) in the Journal's Character page
-- (Journal > Character, or the Hub's K key). Hold L2 and press Square, Triangle or Circle for the powers
-- (Sword Dance, Second Wind, Battle Cry), paid with Focus. Weapon mastery, critical hits, weapon loot
-- rolls and the DarkCloud-Expanded weapon abilities (BSD-2-Clause) stay from Ascension 3.
-- Progress is kept per save slot. Other characters level up too; their own paths come later.
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

-- Engine support: player tuning (run speed, swing speed, invincibility...) arrives with engine Phase 2.
local TUNING = false
do
  local player = game.player
  if type(player) == "table" and type(player.tuning_set) == "function" then
    local _, err = call(player.tuning_set, {})
    TUNING = err == nil or err.code == "invalid_argument"
  end
end

-- Toan's paths ---------------------------------------------------------------------------------------
local PATHS = {
  {id = "swordsman", title = "SWORDSMAN", description = "Hit harder, hit faster.", skills = {
    {id = "keen_edge", title = "Keen Edge", description = "+3% damage per rank.", max_rank = 5},
    {id = "quick_blade", title = "Quick Blade", description = "Sword swings 6% faster per rank.", max_rank = 3,
     prerequisites = {{id = "keen_edge", rank = 1}}, engine = true},
    {id = "precise_strike", title = "Precise Strike", description = "+3% critical chance per rank; a critical hit does x1.75.",
     max_rank = 5, prerequisites = {{id = "keen_edge", rank = 1}}},
    {id = "overwhelm", title = "Overwhelm", description = "+20% critical damage per rank.", max_rank = 3,
     prerequisites = {{id = "precise_strike", rank = 2}}},
    {id = "riposte", title = "Riposte", description = "For 3 s after you take a hit, your next swing does +50%.", max_rank = 1,
     prerequisites = {{id = "keen_edge", rank = 2}}},
    {id = "blade_study", title = "Blade Study", description = "+10% weapon ABS per rank from every kill.", max_rank = 3,
     prerequisites = {{id = "keen_edge", rank = 2}}},
    {id = "sword_dance", title = "SWORD DANCE", max_rank = 3, prerequisites = {{id = "keen_edge", rank = 3}}, power = true,
     description = "POWER  L2+Square: 2.5 s of spinning strikes, enemies slowed. 30 Focus. R2: +20 Focus, cheaper. R3: faster cooldown."}}},
  {id = "survivor", title = "SURVIVOR", description = "Stay alive, stay supplied.", skills = {
    {id = "toughness", title = "Toughness", description = "+4% max HP per rank.", max_rank = 5},
    {id = "iron_skin", title = "Iron Skin", description = "-3% damage taken per rank.", max_rank = 5,
     prerequisites = {{id = "toughness", rank = 1}}},
    {id = "sure_footing", title = "Sure Footing", description = "Recoil after a hit 25% shorter per rank.", max_rank = 3,
     prerequisites = {{id = "iron_skin", rank = 1}}, engine = true},
    {id = "evasion", title = "Evasion", description = "+8 invincibility frames after a hit per rank.", max_rank = 3,
     prerequisites = {{id = "iron_skin", rank = 2}}, engine = true},
    {id = "camel", title = "Camel", description = "Water drains 12% slower per rank.", max_rank = 3,
     prerequisites = {{id = "toughness", rank = 2}}},
    {id = "careful_hands", title = "Careful Hands", description = "Weapons wear 12% slower per rank.", max_rank = 3,
     prerequisites = {{id = "toughness", rank = 2}}},
    {id = "second_wind", title = "SECOND WIND", max_rank = 3, prerequisites = {{id = "toughness", rank = 3}}, power = true,
     description = "POWER  L2+Triangle: heal 30% of max HP at once. 40 Focus. R2: +20 Focus, cheaper. R3: faster cooldown."}}},
  {id = "explorer", title = "EXPLORER", description = "The dungeon itself.", skills = {
    {id = "fleet_foot", title = "Fleet Foot", description = "Run 6% faster per rank.", max_rank = 4, engine = true},
    {id = "keen_eyes", title = "Keen Eyes", description = "Rank 1: the floor map is always yours. Rank 2: monsters show on it.",
     max_rank = 2, prerequisites = {{id = "fleet_foot", rank = 1}}, engine = true},
    {id = "treasure_hunter", title = "Treasure Hunter", description = "+15% Gilda from kills per rank.", max_rank = 3},
    {id = "scholar", title = "Scholar", description = "+8% XP per rank.", max_rank = 3,
     prerequisites = {{id = "treasure_hunter", rank = 1}}},
    {id = "lucky_find", title = "Lucky Find", description = "10% chance per rank that a chest also holds a supply item.",
     max_rank = 3, prerequisites = {{id = "treasure_hunter", rank = 1}}},
    {id = "atla_sense", title = "Atla Sense", description = "Feel how far the nearest Atla is when a floor starts and as you explore.",
     max_rank = 1, prerequisites = {{id = "scholar", rank = 1}}},
    {id = "battle_cry", title = "BATTLE CRY", max_rank = 3, prerequisites = {{id = "treasure_hunter", rank = 2}}, power = true,
     description = "POWER  L2+Circle: 10 s of +40% damage, +20% taken. 25 Focus. R2: +20 Focus, cheaper. R3: faster cooldown."}}}
}
local SKILL_IDS, SKILL, PATH_OF = {}, {}, {}
for _, path in ipairs(PATHS) do
  local registered, err = call(game.skills.register, {id = path.id, title = path.title, description = path.description,
    skills = (function()
      local out = {}
      for _, s in ipairs(path.skills) do
        out[#out + 1] = {id = s.id, title = s.title, description = s.description, max_rank = s.max_rank, prerequisites = s.prerequisites}
      end
      return out
    end)()})
  if not registered then moonmod.log("warn", "skill tree " .. path.id .. ": " .. errmsg(err)) end
  for _, s in ipairs(path.skills) do
    local key = path.id .. "." .. s.id
    SKILL_IDS[#SKILL_IDS + 1] = key
    SKILL[key] = s
    PATH_OF[key] = path
  end
end
local function node_id(skill) return ID .. ":" .. skill end
local function cost_of(skill, rank) return (SKILL[skill].power and rank == 1) and 2 or 1 end

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
    for r = 1, (c.ranks[skill] or 0) do spent = spent + cost_of(skill, r) end
  end
  return points_earned(c.level) - spent
end

-- The framework keeps one rank per node: show Toan's ranks (the only character with paths so far).
local function push_ranks()
  for _, skill in ipairs(SKILL_IDS) do try(game.skills.set_rank, {id = node_id(skill), rank = rank(skill, "toan")}) end
end

-- Max HP: the game's own value grows from items; +3 per level and Toughness on top.
local function apply_max_hp(id)
  local c = char(id)
  local info = c and try(game.characters.get, {id = id})
  if not info or type(info.max_hp) ~= "number" then return end
  local bonus_now = c.hp_bonus or 0
  local base = info.max_hp - bonus_now
  local want = math.floor((base + 3 * (c.level - 1)) * (1 + 0.04 * rank("survivor.toughness", id)) + 0.5) - base
  if want ~= bonus_now and try(game.player.set, {character = id, max_hp = math.max(1, math.min(999, base + want))}) then
    c.hp_bonus = want
  end
end

-- Focus, powers and timers ---------------------------------------------------------------------------
local focus = 100
local cooldown = {square = 0, triangle = 0, circle = 0}
local frame = 0
local cry_until, riposte_until, dance_until, dance_next, dance_first = 0, 0, 0, 0, false
local POWERS = {
  square = {skill = "swordsman.sword_dance", name = "Sword Dance", cost = 30, cooldown = 480},
  triangle = {skill = "survivor.second_wind", name = "Second Wind", cost = 40, cooldown = 1200},
  circle = {skill = "explorer.battle_cry", name = "Battle Cry", cost = 25, cooldown = 1500}
}
local function power_count() local n = 0; for _, p in pairs(POWERS) do if rank(p.skill) >= 2 then n = n + 1 end end; return n end
local function has_power() for _, p in pairs(POWERS) do if rank(p.skill) >= 1 then return true end end; return false end
local function focus_max() return 100 + 20 * power_count() end
local function power_cost(p) return p.cost - (rank(p.skill) >= 2 and 10 or 0) end
local function power_cooldown(p) return math.floor(p.cooldown * (rank(p.skill) >= 3 and 0.7 or 1)) end

-- Engine tuning (Phase 2): one owner-scoped call with every knob the ENGINE nodes use.
local tuning_key = nil
local function apply_tuning()
  if not TUNING then return end
  local key = table.concat({rank("swordsman.quick_blade"), rank("survivor.sure_footing"), rank("survivor.evasion"),
                            rank("explorer.fleet_foot"), rank("explorer.keen_eyes")}, ":")
  if key == tuning_key then return end
  tuning_key = key
  try(game.player.tuning_set, {
    attack_anim_speed = 1 + 0.06 * rank("swordsman.quick_blade"),
    recoil_scale = 1 - 0.25 * rank("survivor.sure_footing"),
    invincible_bonus_frames = 8 * rank("survivor.evasion"),
    run_speed = 1 + 0.06 * rank("explorer.fleet_foot"),
    map_reveal = rank("explorer.keen_eyes") >= 1,
    monster_reveal = rank("explorer.keen_eyes") >= 2
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
  try(game.combat.register_formula, {id = "level", operation = "multiply", priority = 50,
      value = (1 + 0.025 * (c.level - 1)) * (1 + 0.03 * rank("swordsman.keen_edge")) * (cry and 1.4 or 1) * (riposte and 1.5 or 1)})
  local player = try(game.player.get)
  local weapon = player and player.weapon
  mastery_weapon = weapon and weapon.item_no or nil
  local speed = weapon and tonumber(weapon.speed) or 0
  try(game.combat.register_formula, {id = "crit", operation = "chance_multiply", priority = 47,
      value = 1.75 + 0.2 * rank("swordsman.overwhelm"),
      chance = math.min(100, 5 + 3 * rank("swordsman.precise_strike") + speed * 0.05)})
  try(game.combat.register_formula, {id = "variance", operation = "random_multiply", value = 1, min_value = 0.9, max_value = 1.1, priority = 46})
  local taken = (1 - math.min(0.4, 0.008 * (c.level - 1))) * (1 - 0.03 * rank("survivor.iron_skin")) * (cry and 1.2 or 1)
  try(game.combat.register_player_formula, {id = "toughness", operation = "multiply", value = taken, priority = 50})
  if mastery_weapon then
    local bonus = mastery_rank(slot.mastery[tostring(mastery_weapon)] or 0) * 0.02
    try(game.combat.register_formula, {id = "mastery", operation = "multiply", value = 1 + bonus, priority = 52, weapon_id = mastery_weapon})
  end
end
for _, model in ipairs(UNDEAD) do
  try(game.combat.register_formula, {id = "cross_hinder_" .. model, operation = "multiply", value = 2, priority = 40,
      weapon_id = WEAPON.cross_hinder, native_model_id = model})
end
try(game.combat.register_formula, {id = "mobius_ring", operation = "ramp_multiply", value = 1.6, rate_per_second = 0.025,
    reset_after_frames = 360, priority = 45, weapon_id = WEAPON.mobius_ring})
try(game.combat.register_player_formula, {id = "agas_sword", operation = "add", value = -15, priority = 60, weapon_id = WEAPON.agas_sword})

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
    string.format("Damage +%d%%   Crit %d%%", math.floor(((1 + 0.025 * (c.level - 1)) * (1 + 0.03 * rank("swordsman.keen_edge")) - 1) * 100 + 0.5),
                  math.min(100, 5 + 3 * rank("swordsman.precise_strike"))),
    string.format("Damage taken -%d%%", math.floor((1 - (1 - math.min(0.4, 0.008 * (c.level - 1))) * (1 - 0.03 * rank("survivor.iron_skin"))) * 100 + 0.5))
  }
  if powers then lines[#lines + 1] = string.format("Focus %d / %d", math.floor(focus), focus_max()) end
  if mastery_weapon then lines[#lines + 1] = string.format("Mastery %d/5  (%d kills)", mrank, kills) end
  local hint
  if active ~= "toan" then hint = "Paths for " .. title(active) .. " come in a later update; Toan's are shown."
  elseif free > 0 then hint = "Cross trains the selected skill."
  else hint = "Next point: level " .. (c.level + 1) end
  local skey = table.concat(lines, "|") .. "|" .. hint
  if hud.sheet ~= skey then
    hud.sheet = skey
    try(game.ui.sheet_set, {title = title(active):upper(), lines = lines, hint = hint, trees = {"swordsman", "survivor", "explorer"},
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
    toast("RPG: Character Paths. Kills give XP; Toan spends skill points in Journal > Character (K)", 480)
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
  amount = math.max(1, math.floor(amount * setting("xp_rate", 100) / 100 * (1 + 0.08 * rank("explorer.scholar", id)) + 0.5))
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

moonmod.on("game.enemy_defeated", function(event)
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
    local study = rank("swordsman.blade_study")
    if study > 0 and exp > 0 then
      local player = try(game.player.get)
      local weapon = player and player.weapon
      if weapon and weapon.id then
        try(game.weapons.abs_add, {id = weapon.id, character = player.character, slot = weapon.slot, amount = math.max(1, math.floor(exp * 0.1 * study + 0.5))})
      end
    end
  end
  -- Treasure Hunter.
  local hunter = rank("explorer.treasure_hunter")
  local money = type(event.reward_money) == "number" and event.reward_money or 0
  if hunter > 0 and money > 0 then try(game.economy.add, {amount = math.min(32767, math.floor(money * 0.15 * hunter + 0.5))}) end
  save_slot()
  update_hud()
end)

-- Training: Cross on a node in the Journal's Character page (or the Mod Manager's Skills tab) -------
moonmod.on("skills.train_requested", function(event)
  load_slot()
  local id = type(event.id) == "string" and event.id or ""
  local skill = id:sub(#ID + 2)
  if id:sub(1, #ID + 1) ~= ID .. ":" or not SKILL[skill] then return end
  local c = char(active)
  if not c then toast("Load a game first"); return end
  if active ~= "toan" then toast("Only Toan has paths yet. Switch to Toan to train"); return end
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
local function cast(button, player)
  local power = POWERS[button]
  if rank(power.skill) < 1 then return end
  if cooldown[button] > frame then toast(power.name .. " ready in " .. math.ceil((cooldown[button] - frame) / 60) .. " s", 90); return end
  local cost = power_cost(power)
  if focus < cost then toast("Not enough Focus (" .. cost .. ")", 90); return end
  focus = focus - cost
  cooldown[button] = frame + power_cooldown(power)
  if button == "square" then
    dance_until, dance_next, dance_first = frame + 150, frame, true
    local hits = dance_strike(player)
    toast("SWORD DANCE!  " .. hits .. " hit", 150)
  elseif button == "triangle" then
    try(game.player.heal, {amount = math.max(1, math.floor(player.max_hp * 0.3))})
    try(game.player.invincible, {frames = 90})
    toast("SECOND WIND", 150)
  elseif button == "circle" then
    cry_until = frame + 600
    update_formulas()
    toast("BATTLE CRY!  10 s", 150)
  end
  update_hud()
end

-- After a hit: Riposte is spent, the Expanded weapon effects fire -------------------------------------
moonmod.on("game.enemy_hit", function(event)
  if type(event.damage) ~= "number" or event.damage <= 0 then return end
  if riposte_until > frame then riposte_until = 0; update_formulas() end
  local item, roll = event.native_weapon_id, math.random()
  if item == WEAPON.brave_ark then
    for _, status in ipairs({"freeze", "poison", "curse", "goo"}) do try(game.player.status_remove, {status = status}) end
  elseif item == WEAPON.heavens_cloud and roll < 0.5 then try(game.combat.status_add, {entity = event.entity, status = "slow", duration_frames = 300})
  elseif item == WEAPON.snail and roll < 0.05 then try(game.combat.status_add, {entity = event.entity, status = "slow", duration_frames = 300})
  elseif item == WEAPON.frozen_tuna and event.element ~= 1 and roll < 0.05 then try(game.combat.status_add, {entity = event.entity, status = "stop", duration_frames = 180})
  elseif item == WEAPON.cactus then try(game.player.thirst_set, {restore = event.damage / 10}) end
end)

-- Weapon loot rolls ------------------------------------------------------------------------------------
moonmod.on("game.item_picked_up", function(event)
  if event.kind ~= "weapon" or setting("weapon_loot_rolls", true) == false then return end
  local item, owner, where = tonumber(event.native_item_no), event.character, tonumber(event.slot)
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
moonmod.on("game.chest.opened", function()
  local lucky = rank("explorer.lucky_find")
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
moonmod.on("game.player.thirst_changed", function(event)
  if event.source ~= "native" or type(event.previous_water) ~= "number" or type(event.water) ~= "number" then return end
  local lost = event.previous_water - event.water
  local share = 0.12 * rank("survivor.camel")
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
moonmod.on("game.world.location_changed", function(event)
  if event and event.context == "dungeon" and rank("explorer.atla_sense") > 0 then atla_next = frame + 180 end
end)

-- Per frame: powers; every 10 frames: Focus, Riposte, durability, HUD and the sheet -----------------------
local durability_key, durability_last, last_hp, last_hp_char = nil, nil, nil, nil
moonmod.on("game.tick", function(event)
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
  if rank("swordsman.riposte") > 0 and last_hp and last_hp_char == player.character and player.hp < last_hp and player.hp > 0 then
    riposte_until = frame + 180
    update_formulas()
  end
  last_hp, last_hp_char = player.hp, player.character
  if (cry_until > 0 and frame >= cry_until) or (riposte_until > 0 and frame >= riposte_until) then
    if frame >= cry_until then cry_until = 0 end
    if frame >= riposte_until then riposte_until = 0 end
    update_formulas()
  end
  if (player.weapon and player.weapon.item_no) ~= mastery_weapon then update_formulas() end
  -- Careful Hands: part of each point of wear comes back.
  local weapon = player.weapon
  if weapon and type(weapon.durability) == "number" and player.position then
    local key = player.character .. ":" .. weapon.slot .. ":" .. weapon.item_no
    local now = math.floor(weapon.durability)
    local chance = 0.12 * rank("survivor.careful_hands")
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
  if rank("explorer.atla_sense") > 0 and player.position and atla_next > 0 and frame >= atla_next then
    atla_next = frame + 900
    sense_atla(player)
  end
  update_hud()
end)

-- Manager actions --------------------------------------------------------------------------------------
for _, action in ipairs({
  {"open", "Character Page", "Open Journal > Character (Toan's paths)"},
  {"progress", "Party Levels", "Every character's level, XP and free skill points"},
  {"mastery", "Equipped Weapon Mastery", "Kills with the equipped weapon and its mastery bonus"},
  {"respec", "Reset Toan's Skills", "Refund every point (100 Gilda per level)"},
  {"test_levels", "Grant test levels", "Testing: give the active character 5 levels of XP"}
}) do try(game.ui.register, {id = action[1], label = action[2], description = action[3]}) end
moonmod.on("ui.action", function(action)
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
    local scale = setting("xp_rate", 100) / 100 * (1 + 0.08 * rank("explorer.scholar", active))
    gain_xp(active, need / math.max(0.01, scale) + 1, true)
    save_slot()
    toast(string.format("TEST: %s is now LEVEL %d with %d skill points", title(active), c.level, points_free(active)), 360)
  elseif action.id == "respec" then
    local c = char("toan")
    if not c then return end
    local cost = math.min(32767, 100 * c.level)
    if not try(game.economy.spend, {amount = cost}) then toast("Reset costs " .. cost .. " Gilda"); return end
    c.ranks = {}
    save_slot(); push_ranks(); apply_max_hp("toan"); apply_tuning(); update_formulas(); hud = {}; update_hud()
    toast("Toan's skills reset. " .. points_free("toan") .. " points to spend")
  end
end)

moonmod.on("settings.changed", function() update_formulas() end)
load_slot()
moonmod.log("info", "RPG: Character Paths ready" .. (TUNING and " (engine tuning on)" or " (engine tuning not available yet: Quick Blade, Sure Footing, Evasion, Fleet Foot, Keen Eyes wait)"))
