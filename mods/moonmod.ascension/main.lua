-- moonmod.ascension: A modern RPG progression layer for Dark Cloud (Chronicle).
-- Features character XP, leveling up to level 40, Paragon ranks, custom skill tree with
-- combat bonuses, and automatic max HP scaling upon level-ups.

local MAX_LEVEL = 40
local HP_PER_LEVEL = 3
local DAMAGE_PER_LEVEL = 0.025
local PARAGON_HP_PER_RANK = 4
local PARAGON_DAMAGE_PER_RANK = 0.015

local CHARACTERS = {
  [0] = "toan",
  [1] = "xiao",
  [2] = "goro",
  [3] = "ruby",
  [4] = "ungaga",
  [5] = "osmond"
}

local function xp_needed_for_level(lvl)
  return 40 + 22 * lvl + 3 * lvl * lvl
end

local function paragon_needed_for_rank(p)
  return 1500 + 150 * p
end

local function get_char_key(char_idx, key)
  return tostring(char_idx) .. "_" .. key
end

local function get_char_progression(char_idx)
  local level = moonmod.storage.get(get_char_key(char_idx, "level")) or 1
  local xp = moonmod.storage.get(get_char_key(char_idx, "xp")) or 0
  local paragon = moonmod.storage.get(get_char_key(char_idx, "paragon")) or 0
  return level, xp, paragon
end

local function set_char_progression(char_idx, level, xp, paragon)
  moonmod.storage.set(get_char_key(char_idx, "level"), level)
  moonmod.storage.set(get_char_key(char_idx, "xp"), xp)
  moonmod.storage.set(get_char_key(char_idx, "paragon"), paragon)
end

-- Register Ascension skill trees (Might, Vitality, Focus)
local might_tree = game.skills.register({
  id = "might",
  title = "Might",
  description = "Physical and offensive weapon mastery.",
  skills = {
    {
      id = "keen_edge",
      title = "Keen Edge",
      description = "+5% damage dealt per rank.",
      max_rank = 5,
      effects = { enemy_damage_per_rank = 0.05 }
    },
    {
      id = "ruthless",
      title = "Ruthless",
      description = "Crush wounded enemies with extra force.",
      max_rank = 3,
      prerequisites = { { id = "keen_edge", rank = 2 } },
      effects = { enemy_damage_per_rank = 0.08 }
    },
    {
      id = "executioner",
      title = "Executioner",
      description = "Devastating finish.",
      max_rank = 1,
      prerequisites = { { id = "ruthless", rank = 3 } },
      effects = { enemy_damage_per_rank = 0.15 }
    }
  }
})

local vitality_tree = game.skills.register({
  id = "vitality",
  title = "Vitality",
  description = "Survivability, stamina and resilience.",
  skills = {
    {
      id = "toughness",
      title = "Toughness",
      description = "Fortify defense and damage mitigation.",
      max_rank = 5,
      effects = { enemy_damage_per_rank = 0.02 }
    }
  }
})

-- Dynamic combat damage formula based on active character level and paragon
local formula_id = "ascension-damage-modifier"
game.combat.register_formula({
  id = formula_id,
  operation = "multiply",
  value = 1.0,
  priority = 50
})

local function update_combat_damage()
  local player = game.player.get()
  if not player or not player.active_character then return end
  local char_idx = 0
  for idx, name in pairs(CHARACTERS) do
    if name == player.active_character then
      char_idx = idx
      break
    end
  end

  local level, _, paragon = get_char_progression(char_idx)
  local bonus = 1.0 + (level - 1) * DAMAGE_PER_LEVEL + paragon * PARAGON_DAMAGE_PER_RANK
  game.combat.register_formula({
    id = formula_id,
    operation = "multiply",
    value = bonus,
    priority = 50
  })
end

local function add_xp(char_idx, amount)
  if amount <= 0 or char_idx < 0 or char_idx > 5 then return end
  local level, xp, paragon = get_char_progression(char_idx)
  local leveled = false
  local paragon_up = false

  xp = xp + amount

  while level < MAX_LEVEL and xp >= xp_needed_for_level(level) do
    xp = xp - xp_needed_for_level(level)
    level = level + 1
    leveled = true
    -- Increase max HP
    local cur_player = game.player.get({ character = CHARACTERS[char_idx] })
    if cur_player and cur_player.max_hp then
      game.player.set({
        character = CHARACTERS[char_idx],
        max_hp = cur_player.max_hp + HP_PER_LEVEL,
        hp = cur_player.hp + HP_PER_LEVEL
      })
    end
  end

  if level >= MAX_LEVEL then
    while paragon < 50 and xp >= paragon_needed_for_rank(paragon) do
      xp = xp - paragon_needed_for_rank(paragon)
      paragon = paragon + 1
      paragon_up = true
      local cur_player = game.player.get({ character = CHARACTERS[char_idx] })
      if cur_player and cur_player.max_hp then
        game.player.set({
          character = CHARACTERS[char_idx],
          max_hp = cur_player.max_hp + PARAGON_HP_PER_RANK,
          hp = cur_player.hp + PARAGON_HP_PER_RANK
        })
      end
    end
    if paragon >= 50 then xp = 0 end
  end

  set_char_progression(char_idx, level, xp, paragon)
  update_combat_damage()

  local char_name = CHARACTERS[char_idx]:upper()
  if leveled then
    game.ui.notify({ message = "LEVEL UP! " .. char_name .. " is now Level " .. level .. "!" })
    moonmod.log("info", "Ascension: " .. char_name .. " leveled up to " .. level)
  end
  if paragon_up then
    game.ui.notify({ message = "PARAGON RANK! " .. char_name .. " reached Paragon " .. paragon .. "!" })
    moonmod.log("info", "Ascension: " .. char_name .. " reached Paragon rank " .. paragon)
  end
end

-- Exported functions for cross-mod query or debugging
game.scripts.register_function({
  id = "get_level",
  description = "Get character level, XP, and Paragon rank"
}, function(args)
  local char_idx = (args and args.character) or 0
  local level, xp, paragon = get_char_progression(char_idx)
  return {
    character = CHARACTERS[char_idx] or "unknown",
    level = level,
    xp = xp,
    paragon = paragon
  }
end)

-- UI Actions in manager
game.ui.register({
  id = "ascension_inspect",
  label = "Ascension Status",
  description = "Inspect character levels and progression"
})

moonmod.on("ui.action", function(action)
  if action.id == "ascension_inspect" then
    local player = game.player.get()
    local char_idx = 0
    if player and player.active_character then
      for idx, name in pairs(CHARACTERS) do
        if name == player.active_character then char_idx = idx; break end
      end
    end
    local level, xp, paragon = get_char_progression(char_idx)
    local msg = (CHARACTERS[char_idx]:upper()) .. " - Level " .. level .. " (XP: " .. xp .. "/" .. xp_needed_for_level(level) .. ") Paragon: " .. paragon
    game.ui.notify({ message = msg })
  end
end)

-- Award XP on enemy defeat
moonmod.on("game.enemy_defeated", function(event)
  local player = game.player.get()
  if not player or not player.active_character then return end
  local char_idx = 0
  for idx, name in pairs(CHARACTERS) do
    if name == player.active_character then
      char_idx = idx
      break
    end
  end

  -- Calculate XP based on floor and damage or base rate
  local world = game.world.get()
  local floor = (world and world.floor_id) or 1
  local earned_xp = 15 + floor * 5
  add_xp(char_idx, earned_xp)
end)

moonmod.on("game.world.location_changed", function(_)
  update_combat_damage()
end)

moonmod.log("info", "moonmod.ascension initialized.")
