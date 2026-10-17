-- moonmod.dungeon-plus: Replay dungeon floors at custom difficulty tiers (1 to 5).
-- Tiered floors feature scaled procedural room layouts (via game.dungeons.set_layout),
-- increased enemy health/defense/gilda, and gem/slayer bonus attachments upon total floor clear.

local MAX_TIER = 5
local DUNGEON_NAMES = {
  [0] = "Divine Beast Cave",
  [1] = "Wise Owl Forest",
  [2] = "Shipwreck",
  [3] = "Sun and Moon Temple",
  [4] = "Moon Sea",
  [5] = "Gallery of Time",
  [6] = "Demon Shaft"
}

-- Native gem item ids (Ruby, Sapphire, Garnet, Amethyst, etc.)
local GEM_ITEM_IDS = { 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106 }
-- Slayer attachments (Undead Buster, Beast Buster, etc.)
local SLAYER_ITEM_IDS = { 111, 112, 113, 114, 115, 116, 117, 118, 119, 120 }

local function get_floor_key(dungeon_id, floor_id)
  return tostring(dungeon_id) .. ":" .. tostring(floor_id)
end

local function get_saved_tiers()
  return moonmod.storage.get("floor_tiers") or {}
end

local function get_tier(dungeon_id, floor_id)
  if dungeon_id == nil or floor_id == nil then return 0 end
  local tiers = get_saved_tiers()
  return tiers[get_floor_key(dungeon_id, floor_id)] or 0
end

local function set_tier(dungeon_id, floor_id, tier)
  if dungeon_id == nil or floor_id == nil then return end
  local tiers = get_saved_tiers()
  local key = get_floor_key(dungeon_id, floor_id)
  if tier and tier > 0 then
    tiers[key] = math.min(MAX_TIER, tier)
  else
    tiers[key] = nil
  end
  moonmod.storage.set("floor_tiers", tiers)
end

-- Exported function so other mods (e.g. Ascension) can query the active floor tier
game.scripts.register_function({
  id = "current_tier",
  description = "Get the Dungeon+ tier of the current floor"
}, function(_)
  local world = game.world.get()
  if not world or world.context ~= "dungeon" then return { tier = 0 } end
  return { tier = get_tier(world.dungeon_id, world.floor_id) }
end)

-- UI actions to set or cycle tiers for testing and manager UI
game.ui.register({
  id = "tier_up",
  label = "Dungeon+ Tier Up (+1)",
  description = "Increase the difficulty tier for the current floor"
})

game.ui.register({
  id = "tier_reset",
  label = "Dungeon+ Reset Tier",
  description = "Reset the current floor to normal difficulty"
})

-- Track floor clearing state
local current_active_tier = 0
local floor_cleared = false
local enemies_seen = 0

local function apply_floor_scaling(tier)
  if tier <= 0 then
    -- Reset to default layout
    game.dungeons.set_layout({})
    current_active_tier = 0
    return
  end

  current_active_tier = tier
  -- Scaled rooms: Tiers 1-2 expand room spans; Tiers 3-5 build larger multi-cell chambers
  local room_size = math.min(5, 3 + math.floor((tier - 1) / 2))
  game.dungeons.set_layout({
    rooms = 24 + tier * 4,
    area = 30 + tier * 2,
    room_min = 3,
    room_max = room_size
  })
  game.ui.notify({ message = "Dungeon+ Tier " .. tier .. " active! (Enemies and layout scaled)" })
end

-- Register combat damage modifier for Dungeon+ scaling
local formula_id = "dungeon-plus-scaling"
game.combat.register_formula({
  id = formula_id,
  operation = "multiply",
  value = 1.0,
  priority = 100
})

local function update_combat_modifier(tier)
  -- Higher tiers give monsters higher resilience (effectively lower damage received or more health)
  local factor = 1.0 / (1.0 + 0.25 * tier)
  game.combat.register_formula({
    id = formula_id,
    operation = "multiply",
    value = factor,
    priority = 100
  })
end

moonmod.on("ui.action", function(action)
  local world = game.world.get()
  if not world or world.context ~= "dungeon" then
    game.ui.notify({ message = "Must be inside a dungeon floor to configure Dungeon+ tiers" })
    return
  end
  local cur = get_tier(world.dungeon_id, world.floor_id)
  if action.id == "tier_up" then
    local next_tier = (cur >= MAX_TIER) and 0 or (cur + 1)
    set_tier(world.dungeon_id, world.floor_id, next_tier)
    apply_floor_scaling(next_tier)
    update_combat_modifier(next_tier)
  elseif action.id == "tier_reset" then
    set_tier(world.dungeon_id, world.floor_id, 0)
    apply_floor_scaling(0)
    update_combat_modifier(0)
  end
end)

moonmod.on("game.world.location_changed", function(event)
  if event.context ~= "dungeon" then
    current_active_tier = 0
    floor_cleared = false
    enemies_seen = 0
    update_combat_modifier(0)
    return
  end

  local tier = get_tier(event.dungeon_id, event.floor_id)
  floor_cleared = false
  enemies_seen = 0
  apply_floor_scaling(tier)
  update_combat_modifier(tier)
  moonmod.log("info", "Dungeon+: entered dungeon " .. tostring(event.dungeon_id) .. " floor " .. tostring(event.floor_id) .. " (Tier " .. tier .. ")")
end)

-- Monitor living monsters to detect floor clears
moonmod.on("game.tick", function()
  if current_active_tier <= 0 or floor_cleared then return end
  local combat = game.combat.get()
  if not combat then return end

  local living = combat.enemy_count or 0
  if living > enemies_seen then
    enemies_seen = living
  end

  if enemies_seen > 0 and living == 0 and not floor_cleared then
    floor_cleared = true
    moonmod.log("info", "Dungeon+: floor cleared at Tier " .. current_active_tier .. "! Awarding clear bonus.")
    -- Award gems proportional to tier
    for _ = 1, current_active_tier do
      local gem = GEM_ITEM_IDS[math.random(#GEM_ITEM_IDS)]
      game.items.give({ id = "chronicle:item:" .. gem, count = 1 })
    end
    -- Award slayer attachment at tier 3+
    if current_active_tier >= 3 then
      local slayer = SLAYER_ITEM_IDS[math.random(#SLAYER_ITEM_IDS)]
      game.items.give({ id = "chronicle:item:" .. slayer, count = 1 })
    end
    game.ui.notify({ message = "Dungeon+ Tier " .. current_active_tier .. " Clear Bonus Granted!" })
  end
end)

moonmod.log("info", "moonmod.dungeon-plus initialized.")
