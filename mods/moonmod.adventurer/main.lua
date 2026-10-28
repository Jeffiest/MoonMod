-- Ascension 3: each character grows on their own. Kills give XP, levels give max HP, damage, toughness
-- and skill points. Points are spent with Cross in the Skills tab (K). Hold L2 and press Square, Triangle
-- or Circle for the active powers (Shockwave, Second Wind, Berserk), paid for with Focus. Also weapon
-- mastery, critical hits, weapon loot rolls and the DarkCloud-Expanded weapon abilities (BSD-2-Clause).
-- Progress is kept per save slot.

local ID = "moonmod.adventurer"
local CHARACTERS = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
local MAX_LEVEL = 40
local MASTERY_KILLS = {10, 30, 75, 150, 300}
local UNDEAD = {0, 1, 23, 24, 36, 44, 45, 67, 81, 82, 96, 105, 122, 144}
local WEAPON = {agas_sword = 281, heavens_cloud = 271, brave_ark = 274, cross_hinder = 294,
                frozen_tuna = 321, mobius_ring = 341, cactus = 360, snail = 374}

local function try(fn, ...)
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end
local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= type(fallback) then return fallback end
  return value
end
local function toast(message, frames) try(game.ui.notify, {message = message, duration_frames = frames or 240}) end
local function title(id) return id:sub(1, 1):upper() .. id:sub(2) end
local function must(value, err, what)
  if value == nil then error(what .. ": " .. tostring(type(err) == "table" and err.message or err), 0) end
  return value
end

-- Skill tree (the original Ascension tree) -------------------------------------------------------------
local TREES = {
  {id = "asc_might", title = "MIGHT", description = "Hit harder, finish fights, drain life.", skills = {
    {id = "keen_edge", title = "Keen Edge", description = "+4% damage per rank.", max_rank = 5, effects = {enemy_damage_per_rank = 0.04}},
    {id = "deadly_aim", title = "Deadly Aim", description = "+3% critical chance per rank. Needs Keen Edge 1.", max_rank = 5,
     prerequisites = {{id = "keen_edge", rank = 1}}},
    {id = "ruthless", title = "Ruthless", description = "+20% critical damage per rank. Needs Deadly Aim 2.", max_rank = 3,
     prerequisites = {{id = "deadly_aim", rank = 2}}},
    {id = "executioner", title = "Executioner", description = "+30% damage to enemies below 30% HP. Needs Keen Edge 3.", max_rank = 1,
     prerequisites = {{id = "keen_edge", rank = 3}}},
    {id = "siphon", title = "Siphon", description = "Heal 2% of damage dealt per rank. Needs Ruthless 1.", max_rank = 3,
     prerequisites = {{id = "ruthless", rank = 1}}},
    {id = "shockwave", title = "SHOCKWAVE", description = "POWER  L2+Square: blast every nearby enemy. 30 Focus, 2 points. Needs Keen Edge 2.",
     max_rank = 1, prerequisites = {{id = "keen_edge", rank = 2}}}}},
  {id = "asc_vitality", title = "VITALITY", description = "Stay standing.", skills = {
    {id = "toughness", title = "Toughness", description = "+4% max HP per rank.", max_rank = 5},
    {id = "iron_skin", title = "Iron Skin", description = "-3% damage taken per rank. Needs Toughness 1.", max_rank = 5,
     prerequisites = {{id = "toughness", rank = 1}}},
    {id = "second_wind", title = "SECOND WIND", description = "POWER  L2+Triangle: heal 30% max HP. 40 Focus, 2 points. Needs Toughness 2.",
     max_rank = 1, prerequisites = {{id = "toughness", rank = 2}}},
    {id = "regeneration", title = "Regeneration", description = "Recover 0.5% max HP per second per rank. Needs Iron Skin 2.", max_rank = 3,
     prerequisites = {{id = "iron_skin", rank = 2}}},
    {id = "last_stand", title = "Last Stand", description = "+25% damage while below 25% HP. Needs Iron Skin 3.", max_rank = 1,
     prerequisites = {{id = "iron_skin", rank = 3}}}}},
  {id = "asc_focus", title = "FOCUS", description = "Power the active skills and earn more.", skills = {
    {id = "deep_focus", title = "Deep Focus", description = "+10 max Focus per rank.", max_rank = 5},
    {id = "quick_recovery", title = "Quick Recovery", description = "+10% Focus regeneration per rank. Needs Deep Focus 1.", max_rank = 5,
     prerequisites = {{id = "deep_focus", rank = 1}}},
    {id = "berserk", title = "BERSERK", description = "POWER  L2+Circle: 10 s of +40% damage, +20% damage taken. 25 Focus, 2 points. Needs Deep Focus 2.",
     max_rank = 1, prerequisites = {{id = "deep_focus", rank = 2}}},
    {id = "treasure_hunter", title = "Treasure Hunter", description = "+15% Gilda from kills per rank. Needs Quick Recovery 1.", max_rank = 3,
     prerequisites = {{id = "quick_recovery", rank = 1}}},
    {id = "scholar", title = "Scholar", description = "+8% XP per rank. Needs Quick Recovery 2.", max_rank = 3,
     prerequisites = {{id = "quick_recovery", rank = 2}}},
    {id = "cooldown_mastery", title = "Cooldown Mastery", description = "-10% power cooldowns per rank. Needs Berserk.", max_rank = 3,
     prerequisites = {{id = "berserk", rank = 1}}}}}
}
local SKILL_IDS, SKILL_MAX, SKILL_TITLE = {}, {}, {}
local SKILL_COST = {["might.shockwave"] = 2, ["vitality.second_wind"] = 2, ["focus.berserk"] = 2}
for _, tree in ipairs(TREES) do
  local registered, register_err = game.skills.register(tree)
  must(registered, register_err, "skill tree " .. tree.id)
  local short = tree.id:gsub("^asc_", "")
  for _, s in ipairs(tree.skills) do
    local key = short .. "." .. s.id
    SKILL_IDS[#SKILL_IDS + 1] = key
    SKILL_MAX[key] = s.max_rank
    SKILL_TITLE[key] = s.title
  end
end

-- Per-save-slot, per-character state -------------------------------------------------------------------
-- slots[key] = {chars = {[id] = {level, xp, ranks, base_hp}}, mastery = {[item_no] = kills}}
local slot_key, slot = nil, nil
local active = nil      -- active character id
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
local function xp_needed(level) return 40 + 22 * level + 3 * level * level end
local function points_earned(level) return (level - 1) + math.floor((level - 1) / 5) end
local function points_free(id)
  local c = char(id or active)
  if not c then return 0 end
  local spent = 0
  for _, skill in ipairs(SKILL_IDS) do spent = spent + (c.ranks[skill] or 0) * (SKILL_COST[skill] or 1) end
  return points_earned(c.level) - spent
end

-- The framework keeps one rank per node; show the active character's ranks in the Skills tab.
local function node_id(skill) return ID .. ":asc_" .. skill end
local function push_ranks()
  for _, skill in ipairs(SKILL_IDS) do try(game.skills.set_rank, {id = node_id(skill), rank = rank(skill)}) end
end

-- Max HP: the game's own value grows from items; Ascension adds +3 per level and Toughness on top.
local function apply_max_hp(id)
  local c = char(id)
  local info = c and try(game.characters.get, {id = id})
  if not info or type(info.max_hp) ~= "number" then return end
  local bonus_now = c.hp_bonus or 0
  local base = info.max_hp - bonus_now
  local want = math.floor((base + 3 * (c.level - 1)) * (1 + 0.04 * (c.ranks["vitality.toughness"] or 0)) + 0.5) - base
  if want ~= bonus_now and try(game.player.set, {character = id, max_hp = math.max(1, math.min(999, base + want))}) then
    c.hp_bonus = want
  end
end

-- Focus and powers --------------------------------------------------------------------------------------
local focus = 100
local cooldown = {square = 0, triangle = 0, circle = 0}
local berserk_until = 0
local frame = 0
local function focus_max() return 100 + 10 * rank("focus.deep_focus") end

-- HUD: XP bar labelled with the level, and the Focus bar under it once a power is learned.
local hud = {}
local function update_hud()
  local c = char(active)
  if not c then return end
  local need = c.level >= MAX_LEVEL and 1 or xp_needed(c.level)
  local xp = c.level >= MAX_LEVEL and 1 or math.min(c.xp, need)
  local key = c.level .. ":" .. xp .. ":" .. need
  if hud.xp ~= key then hud.xp = key; try(game.render.bar_register, {id = "xp", label = "LV" .. c.level, current = xp, max = need}) end
  local has_power = rank("might.shockwave") + rank("vitality.second_wind") + rank("focus.berserk") > 0
  local fkey = has_power and (math.floor(focus) .. ":" .. focus_max()) or "off"
  if hud.focus ~= fkey then
    hud.focus = fkey
    if has_power then try(game.render.bar_register, {id = "focus", label = "FOCUS", current = math.floor(focus), max = focus_max()})
    else try(game.render.bar_remove, {id = "focus"}) end
  end
end

-- Combat formulas ---------------------------------------------------------------------------------------
local mastery_weapon = nil
local function mastery_rank(kills)
  local r = 0
  for i, need in ipairs(MASTERY_KILLS) do if kills >= need then r = i end end
  return r
end
local last_stand_on = false
local function update_formulas()
  local c = char(active)
  if not c then return end
  local level_bonus = 1 + 0.025 * (c.level - 1)
  local berserk = frame < berserk_until
  try(game.combat.register_formula, {id = "level", operation = "multiply", value = level_bonus * (berserk and 1.4 or 1) * (last_stand_on and 1.25 or 1), priority = 50})
  local player = try(game.player.get)
  local weapon = player and player.weapon
  mastery_weapon = weapon and weapon.item_no or nil
  local speed = weapon and tonumber(weapon.speed) or 0
  try(game.combat.register_formula, {id = "crit", operation = "chance_multiply",
      value = 1.75 + 0.2 * rank("might.ruthless"),
      chance = math.min(100, 8 + 3 * rank("might.deadly_aim") + speed * 0.05), priority = 47})
  try(game.combat.register_formula, {id = "variance", operation = "random_multiply", value = 1, min_value = 0.9, max_value = 1.1, priority = 46})
  try(game.combat.register_formula, {id = "executioner", operation = "multiply", value = rank("might.executioner") > 0 and 1.3 or 1,
      priority = 55, target_hp_below_percent = 30})
  local taken = (1 - math.min(0.4, 0.008 * (c.level - 1))) * (1 - 0.03 * rank("vitality.iron_skin")) * (berserk and 1.2 or 1)
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

-- Loading a save slot and switching characters -----------------------------------------------------
local function load_slot()
  local identity = try(game.save.slot_id)
  local key = identity and identity.slot_id and (tostring(identity.slot_id) .. ":" .. tostring(identity.slot_generation)) or nil
  if key == slot_key then return end
  slot_key, active, hud = key, nil, {}
  if not key then slot = nil; try(game.render.bar_remove, {id = "xp"}); try(game.render.bar_remove, {id = "focus"}); return end
  local saved = all_slots()[key]
  slot = type(saved) == "table" and saved or {}
  slot.mastery = type(slot.mastery) == "table" and slot.mastery or {}
  if type(slot.chars) ~= "table" then
    -- From Adventurer 2 (one party level) or the Ascension import: every joined character starts there.
    slot.chars = {}
    local import = moonmod.storage.get("import")
    local old = type(import) == "table" and type(import[key]) == "table" and import[key] or {}
    local level = math.max(tonumber(slot.level) or 1, tonumber(old.level) or 1)
    local party = try(game.party.list) or {}
    for _, member in ipairs(party) do
      if type(member) == "table" and member.id then slot.chars[member.id] = {level = math.min(MAX_LEVEL, math.floor(level)), xp = 0, ranks = {}} end
    end
    if type(old.mastery) == "table" then for k, v in pairs(old.mastery) do slot.mastery[tostring(k)] = math.max(slot.mastery[tostring(k)] or 0, v) end end
    slot.level, slot.xp, slot.ranks, slot.imported = nil, nil, nil, nil
    toast("Ascension 3: each character now levels on their own. Skill points are refunded to spend again (K)", 480)
  end
  save_slot()
end
local function set_active(id)
  if id == active then return end
  active = id
  hud = {}
  push_ranks()
  apply_max_hp(id)
  update_formulas()
  update_hud()
end

-- XP ----------------------------------------------------------------------------------------------------
local function gain_xp(id, amount, quiet)
  local c = char(id)
  if not c or amount <= 0 then return end
  amount = math.max(1, math.floor(amount * setting("xp_rate", 100) / 100 * (1 + 0.08 * (c.ranks["focus.scholar"] or 0)) + 0.5))
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
    toast(title(id):upper() .. " reached LEVEL " .. c.level .. "!  " .. free .. " skill point" .. (free == 1 and "" or "s") .. " (K)", 360)
    if id == active then update_formulas() end
  end
end

moonmod.on("game.enemy_defeated", function(event)
  load_slot()
  if not slot or not active then return end
  local hp = type(event.enemy_max_hp) == "number" and event.enemy_max_hp or 0
  local exp = type(event.reward_exp) == "number" and event.reward_exp or 0
  local reward = hp > 0 and (hp * 0.45 + exp) or math.max(3, exp)
  -- Dungeon+ champions and tiers give more.
  local info = event.entity and try(game.scripts.call_function, {id = "moonmod.dungeon-plus:enemy_bonus", arguments = {entity = event.entity}})
  if type(info) == "table" and type(info.xp_multiplier) == "number" then reward = reward * info.xp_multiplier end
  gain_xp(active, reward)
  for _, id in ipairs(CHARACTERS) do
    if id ~= active and slot.chars[id] then gain_xp(id, reward * 0.25, true) end
  end
  -- Weapon mastery
  local item = type(event.native_weapon_id) == "number" and event.native_weapon_id or mastery_weapon
  if item and item >= 257 then
    local key = tostring(item)
    local before = mastery_rank(slot.mastery[key] or 0)
    slot.mastery[key] = (slot.mastery[key] or 0) + 1
    local after = mastery_rank(slot.mastery[key])
    if after > before then toast("Weapon mastery " .. after .. "/5: +" .. (after * 2) .. "% damage with this weapon", 300); update_formulas() end
  end
  -- Treasure Hunter
  local hunter = rank("focus.treasure_hunter")
  local money = type(event.reward_money) == "number" and event.reward_money or 0
  if hunter > 0 and money > 0 then try(game.economy.add, {amount = math.min(32767, math.floor(money * 0.15 * hunter + 0.5))}) end
  save_slot()
  update_hud()
end)

-- Skills: Cross in the Skills tab trains the active character -----------------------------------------
moonmod.on("skills.train_requested", function(event)
  load_slot()
  local id = type(event.id) == "string" and event.id or ""
  local skill = id:sub(#ID + 2):gsub("^asc_", "")
  if id:sub(1, #ID + 1) ~= ID .. ":" or not SKILL_MAX[skill] then return end
  local c = char(active)
  if not c then toast("Load a game first"); return end
  if (c.ranks[skill] or 0) >= SKILL_MAX[skill] then toast("Already at maximum rank"); return end
  local cost = SKILL_COST[skill] or 1
  if points_free() < cost then toast("Needs " .. cost .. " skill point" .. (cost == 1 and "" or "s") .. ". Next point at level " .. (c.level + 1)); return end
  local changed, err = game.skills.set_rank({id = node_id(skill), rank = (c.ranks[skill] or 0) + 1})
  if not changed then toast(type(err) == "table" and err.message or "Prerequisites are not met"); return end
  c.ranks[skill] = (c.ranks[skill] or 0) + 1
  save_slot()
  apply_max_hp(active)
  update_formulas()
  update_hud()
  toast(title(active) .. ": " .. SKILL_TITLE[skill] .. " " .. c.ranks[skill] .. "/" .. SKILL_MAX[skill] .. "  (" .. points_free() .. " points left)")
end)

-- Powers ------------------------------------------------------------------------------------------------
local _ = (function() local ok, err = game.input.bind({id = "power_hold", keys = {"Gamepad:L2"}}); if not ok then moonmod.log("warn", "bind power_hold: " .. tostring(type(err) == "table" and err.message or err)) end end)()
local _ = (function() local ok, err = game.input.bind({id = "power_square", keys = {"Gamepad:x"}}); if not ok then moonmod.log("warn", "bind power_square: " .. tostring(type(err) == "table" and err.message or err)) end end)()
local _ = (function() local ok, err = game.input.bind({id = "power_triangle", keys = {"Gamepad:y"}}); if not ok then moonmod.log("warn", "bind power_triangle: " .. tostring(type(err) == "table" and err.message or err)) end end)()
local _ = (function() local ok, err = game.input.bind({id = "power_circle", keys = {"Gamepad:b"}}); if not ok then moonmod.log("warn", "bind power_circle: " .. tostring(type(err) == "table" and err.message or err)) end end)()
local _ = (function() local ok, err = game.input.bind({id = "key_square", keys = {moonmod.settings.get("shockwave_key") or "F4"}}); if not ok then moonmod.log("warn", "bind key_square: " .. tostring(type(err) == "table" and err.message or err)) end end)()
local _ = (function() local ok, err = game.input.bind({id = "key_triangle", keys = {moonmod.settings.get("second_wind_key") or "F5"}}); if not ok then moonmod.log("warn", "bind key_triangle: " .. tostring(type(err) == "table" and err.message or err)) end end)()
local _ = (function() local ok, err = game.input.bind({id = "key_circle", keys = {moonmod.settings.get("berserk_key") or "F6"}}); if not ok then moonmod.log("warn", "bind key_circle: " .. tostring(type(err) == "table" and err.message or err)) end end)()
local POWERS = {
  square = {skill = "might.shockwave", name = "Shockwave", cost = 30, cooldown = 360},
  triangle = {skill = "vitality.second_wind", name = "Second Wind", cost = 40, cooldown = 1200},
  circle = {skill = "focus.berserk", name = "Berserk", cost = 25, cooldown = 1500}
}
local function cast(button, player)
  local power = POWERS[button]
  if rank(power.skill) < 1 then return end
  if cooldown[button] > frame then toast(power.name .. " ready in " .. math.ceil((cooldown[button] - frame) / 60) .. " s", 90); return end
  if focus < power.cost then toast("Not enough Focus", 90); return end
  focus = focus - power.cost
  cooldown[button] = frame + math.floor(power.cooldown * (1 - 0.1 * rank("focus.cooldown_mastery")))
  if button == "square" then
    local pos = player.position
    local found = pos and try(game.physics.query, {shape = "sphere", center = pos, radius = setting("shockwave_radius", 220)})
    local attack = player.weapon and tonumber(player.weapon.attack) or 10
    local hits = 0
    for _, match in ipairs(found and found.matches or {}) do
      if try(game.combat.damage, {entity = match.entity, amount = math.max(1, math.floor(attack * 1.5 + 20))}) then hits = hits + 1 end
    end
    toast("SHOCKWAVE!  " .. hits .. " hit", 150)
  elseif button == "triangle" then
    try(game.player.heal, {amount = math.max(1, math.floor(player.max_hp * 0.3))})
    toast("SECOND WIND", 150)
  elseif button == "circle" then
    berserk_until = frame + 600
    update_formulas()
    toast("BERSERK!  10 s", 150)
  end
  update_hud()
end

-- Siphon and the Expanded weapon effects after a hit --------------------------------------------------
moonmod.on("game.enemy_hit", function(event)
  if type(event.damage) ~= "number" or event.damage <= 0 then return end
  local siphon = rank("might.siphon")
  if siphon > 0 then try(game.player.heal, {amount = math.max(1, math.floor(event.damage * 0.02 * siphon + 0.5))}) end
  local item, roll = event.native_weapon_id, math.random()
  if item == WEAPON.brave_ark then
    for _, status in ipairs({"freeze", "poison", "curse", "goo"}) do try(game.player.status_remove, {status = status}) end
  elseif item == WEAPON.heavens_cloud and roll < 0.5 then try(game.combat.status_add, {entity = event.entity, status = "slow", duration_frames = 300})
  elseif item == WEAPON.snail and roll < 0.05 then try(game.combat.status_add, {entity = event.entity, status = "slow", duration_frames = 300})
  elseif item == WEAPON.frozen_tuna and event.element ~= 1 and roll < 0.05 then try(game.combat.status_add, {entity = event.entity, status = "stop", duration_frames = 180})
  elseif item == WEAPON.cactus then try(game.player.thirst_set, {restore = event.damage / 10}) end
end)

-- Weapon loot rolls ----------------------------------------------------------------------------------
moonmod.on("game.item_picked_up", function(event)
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

-- Thirst refund (Sturdy) -------------------------------------------------------------------------------
moonmod.on("game.player.thirst_changed", function(event)
  if event.source ~= "native" or type(event.previous_water) ~= "number" or type(event.water) ~= "number" then return end
  local lost = event.previous_water - event.water
  local share = setting("water_refund", 20) / 100
  if lost > 0 and lost < 5 and share > 0 then try(game.player.thirst_set, {restore = lost * share, character = event.character or "active"}) end
end)

-- Per frame: powers input; every 10 frames: Focus, regeneration, durability, HUD ----------------------
local durability_key, durability_last = nil, nil
moonmod.on("game.tick", function(event)
  frame = event and event.frame or frame + 1
  if slot and active then
    local hold = game.input.state({id = "power_hold"})
    local held = hold and hold.down
    if held then try(game.input.block_native, {buttons = {"square", "triangle", "circle"}, frames = 2}) end
    for _, button in ipairs({"square", "triangle", "circle"}) do
      -- Gamepad face buttons cast only with L2 held; the keyboard keys (F4/F5/F6) cast on their own.
      local pad = game.input.consume({id = "power_" .. button})
      local key = game.input.consume({id = "key_" .. button})
      if (pad and pad.pressed and held) or (key and key.pressed) then
        local player = try(game.player.get)
        if player and player.position then cast(button, player) end
      end
    end
  end
  if frame % 10 ~= 0 then return end
  if frame % 30 == 0 then load_slot() end
  if not slot then return end
  local player = try(game.player.get)
  if not player then return end
  set_active(player.character)
  -- Focus regenerates 6 per second, faster with Quick Recovery.
  focus = math.min(focus_max(), focus + 1.0 * (1 + 0.1 * rank("focus.quick_recovery")))
  -- Berserk ending, Last Stand switching.
  local stand = rank("vitality.last_stand") > 0 and player.max_hp > 0 and player.hp < player.max_hp * 0.25
  if stand ~= last_stand_on or (berserk_until > 0 and frame >= berserk_until) then
    last_stand_on = stand
    if frame >= berserk_until then berserk_until = 0 end
    update_formulas()
  end
  if (player.weapon and player.weapon.item_no) ~= mastery_weapon then update_formulas() end
  -- Regeneration, once a second.
  local regen = rank("vitality.regeneration")
  if regen > 0 and frame % 60 == 0 and player.hp > 0 and player.hp < player.max_hp then
    try(game.player.heal, {amount = math.max(1, math.floor(player.max_hp * 0.005 * regen + 0.5))})
  end
  -- Durability refund (Sturdy).
  local weapon = player.weapon
  if weapon and type(weapon.durability) == "number" and player.position then
    local key = player.character .. ":" .. weapon.slot .. ":" .. weapon.item_no
    local now = math.floor(weapon.durability)
    if key == durability_key and durability_last and now < durability_last and durability_last - now <= 3 then
      local back = 0
      for _ = 1, durability_last - now do if math.random() < setting("durability_refund", 30) / 100 then back = back + 1 end end
      if back > 0 then
        now = math.min(weapon.durability_max or now + back, now + back)
        try(game.weapons.durability_set, {id = weapon.id, character = player.character, slot = weapon.slot, durability = now})
      end
    end
    durability_key, durability_last = key, now
  end
  update_hud()
end)

-- Manager actions ---------------------------------------------------------------------------------------
for _, action in ipairs({
  {"progress", "Party Levels", "Every character's level, XP and free skill points"},
  {"mastery", "Equipped Weapon Mastery", "Kills with the equipped weapon and its mastery bonus"},
  {"respec", "Reset Active Character's Skills", "Refund every point (100 Gilda per level)"}
}) do try(game.ui.register, {id = action[1], label = action[2], description = action[3]}) end
moonmod.on("ui.action", function(action)
  load_slot()
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
  elseif action.id == "respec" then
    local c = char(active)
    if not c then return end
    local cost = math.min(32767, 100 * c.level)
    if not try(game.economy.spend, {amount = cost}) then toast("Reset costs " .. cost .. " Gilda"); return end
    c.ranks = {}
    save_slot(); push_ranks(); apply_max_hp(active); update_formulas(); update_hud()
    toast(title(active) .. "'s skills reset. " .. points_free() .. " points to spend")
  end
end)

moonmod.on("settings.changed", function() update_formulas() end)
load_slot()
moonmod.log("info", "Ascension 3 ready")
