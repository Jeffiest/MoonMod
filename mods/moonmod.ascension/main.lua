local function checked(value, err)
  if value == nil then error(type(err) == "table" and err.message or tostring(err)) end
  return value
end
local function saved_number(value, fallback, low, high)
  if type(value) ~= "number" or value ~= value then return fallback end
  return math.max(low, math.min(high, math.floor(value)))
end
-- moonmod.ascension: A modern RPG progression layer for Dark Cloud (Chronicle).
-- Features character XP, leveling up to level 40, Paragon ranks, custom skill tree with
-- combat bonuses, defensive Toughness, and native maximum HP gains on level-up.

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
  local progression = moonmod.storage.get("progression_v2") or {}
  local data = progression[tostring(char_idx)] or {}
  local level = data.level or moonmod.storage.get(get_char_key(char_idx, "level"))
  local xp = data.xp or moonmod.storage.get(get_char_key(char_idx, "xp"))
  local paragon = data.paragon or moonmod.storage.get(get_char_key(char_idx, "paragon"))
  return saved_number(level,1,1,40), saved_number(xp,0,0,1000000), saved_number(paragon,0,0,50)
end
local function set_char_progression(char_idx, level, xp, paragon)
  local progression = moonmod.storage.get("progression_v2") or {}
  progression[tostring(char_idx)] = {level=level,xp=xp,paragon=paragon}
  checked(moonmod.storage.set("progression_v2", progression))
end

local might_tree = checked(game.skills.register({
  id = "might",
  title = "MIGHT",
  description = "Weapon damage, finishing attacks, and recovery.",
  skills = {
    { id="keen_edge", title="Keen Edge", description="+5% damage dealt per rank.", max_rank=5,
      effects={enemy_damage_per_rank=0.05} },
    { id="ruthless", title="Ruthless", description="+8% damage dealt per rank; requires Keen Edge rank 2.", max_rank=3,
      prerequisites={{id="keen_edge",rank=2}}, effects={enemy_damage_per_rank=0.08} },
    { id="executioner", title="Executioner", description="+15% damage dealt; requires Ruthless rank 3.", max_rank=1,
      prerequisites={{id="ruthless",rank=3}}, effects={enemy_damage_per_rank=0.15} },
    { id="deadly_aim", title="Deadly Aim", description="+3% damage dealt per rank; requires Keen Edge rank 1.", max_rank=5,
      prerequisites={{id="keen_edge",rank=1}}, effects={enemy_damage_per_rank=0.03} },
    { id="siphon", title="Siphon", description="Heal for 2% of the final hit damage when you defeat an enemy per rank; requires Ruthless rank 1.", max_rank=3,
      prerequisites={{id="ruthless",rank=1}}, effects={} },
    { id="shockwave", title="SHOCKWAVE", description="Active: damage every living enemy on the floor. Costs 30 Focus; requires Keen Edge rank 2.", max_rank=1,
      prerequisites={{id="keen_edge",rank=2}}, effects={} }
  }
}))

local vitality_tree = checked(game.skills.register({
  id = "vitality",
  title = "VITALITY",
  description = "Health, damage reduction, and healing.",
  skills = {
    { id="toughness", title="Toughness", description="-5% incoming damage per rank. Character levels grant +3 max HP.", max_rank=5,
      effects={} },
    { id="iron_skin", title="Iron Skin", description="-2% incoming damage per rank; requires Toughness rank 1.", max_rank=5,
      prerequisites={{id="toughness",rank=1}}, effects={} },
    { id="regeneration", title="Regeneration", description="Restore 0.4% max HP per second per rank; requires Iron Skin rank 2.", max_rank=3,
      prerequisites={{id="iron_skin",rank=2}}, effects={} },
    { id="survivalist", title="Survivalist", description="Return 6% of native thirst lost per rank while in a dungeon; requires Toughness rank 1.", max_rank=5,
      prerequisites={{id="toughness",rank=1}}, effects={} },
    { id="last_stand", title="Last Stand", description="+25% damage dealt while below 25% HP; requires Iron Skin rank 3.", max_rank=1,
      prerequisites={{id="iron_skin",rank=3}}, effects={} },
    { id="second_wind", title="SECOND WIND", description="Active: heal 30% of max HP. Costs 40 Focus; requires Toughness rank 2.", max_rank=1,
      prerequisites={{id="toughness",rank=2}}, effects={} }
  }
}))

local focus_tree = checked(game.skills.register({
  id = "focus",
  title = "FOCUS",
  description = "Focus resource, active skills, rewards, and cooldowns.",
  skills = {
    { id="deep_focus", title="Deep Focus", description="+10 maximum Focus per rank.", max_rank=5, effects={} },
    { id="quick_recovery", title="Quick Recovery", description="+8% Focus regeneration per rank; requires Deep Focus rank 1.", max_rank=5,
      prerequisites={{id="deep_focus",rank=1}}, effects={} },
    { id="berserk", title="BERSERK", description="Active: 10 seconds of +40% damage dealt and +20% damage taken. Costs 25 Focus; requires Deep Focus rank 2.", max_rank=1,
      prerequisites={{id="deep_focus",rank=2}}, effects={} },
    { id="treasure_hunter", title="Treasure Hunter", description="+10% bonus Gilda from enemy money drops per rank; requires Quick Recovery rank 1.", max_rank=3,
      prerequisites={{id="quick_recovery",rank=1}}, effects={} },
    { id="scholar", title="Scholar", description="+5% Ascension XP per rank; requires Quick Recovery rank 2.", max_rank=3,
      prerequisites={{id="quick_recovery",rank=2}}, effects={} },
    { id="cooldown_mastery", title="Cooldown Mastery", description="-8% active-skill cooldowns per rank; requires Berserk.", max_rank=3,
      prerequisites={{id="berserk",rank=1}}, effects={} }
  }
}))

local function skill_ranks()
  local result=game.skills.list()
  local ranks={}
  for _,skill in ipairs((result and result.skills) or {}) do ranks[skill.id]=skill.rank end
  return ranks
end
local function skill_rank(id) return skill_ranks()["moonmod.ascension:"..id] or 0 end

local current_frame, focus, berserk_until = 0, 100, 0
local cooldown_until = {}
local last_focus_frame = 0
local function focus_max() return 100+10*skill_rank("focus.deep_focus") end
local function berserk_active() return current_frame < berserk_until end

-- Weapon mastery is stored by stable weapon ID, so every copy and built-up
-- weapon of the same type shares its earned ranks.
local MASTERY_THRESHOLDS={25,75,150,300,600}
local mastery_seen={}
local function mastery_data() return moonmod.storage.get("weapon_mastery_v1") or {} end
local function mastery_rank(kills)
  local rank=0
  for i,threshold in ipairs(MASTERY_THRESHOLDS) do if kills>=threshold then rank=i end end
  return rank
end
local function mastery_bonus(weapon_id)
  if type(weapon_id)~="string" or weapon_id=="" then return 0 end
  local kills=mastery_data()[weapon_id] or 0
  local per_rank=(moonmod.settings.get("mastery_damage_per_rank") or 2)/100
  return mastery_rank(kills)*per_rank
end
local function mastery_record(event)
  if event.entity and mastery_seen[event.entity] then return end
  if event.entity then mastery_seen[event.entity]=true end
  local weapon_id=event.weapon_id
  if type(weapon_id)~="string" or weapon_id=="" then
    local player=game.player.get()
    if player and player.character_id==event.attacker and player.weapon then weapon_id=player.weapon.id end
  end
  if type(weapon_id)~="string" or weapon_id=="" then return end
  local data=mastery_data()
  local before=data[weapon_id] or 0
  data[weapon_id]=before+1
  checked(moonmod.storage.set("weapon_mastery_v1",data))
  local before_rank,after_rank=mastery_rank(before),mastery_rank(before+1)
  if after_rank>before_rank then
    local percent=math.floor(after_rank*(moonmod.settings.get("mastery_damage_per_rank") or 2)+0.5)
    game.ui.notify({message=string.format("WEAPON MASTERY %d/5: %s +%d%%",after_rank,weapon_id,percent)})
  end
end

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
  if not player then return end
  local char_idx = player.character_id or 0
  local level, _, paragon = get_char_progression(char_idx)
  local ranks=skill_ranks()
  local bonus=1.0+(level-1)*DAMAGE_PER_LEVEL+paragon*PARAGON_DAMAGE_PER_RANK
  bonus=bonus+mastery_bonus(player.weapon and player.weapon.id)
  local hp_fraction=(player.max_hp or 0)>0 and (player.hp or 0)/player.max_hp or 1
  if hp_fraction<=0.25 then bonus=bonus+0.25*(ranks["moonmod.ascension:vitality.last_stand"] or 0) end
  if berserk_active() then bonus=bonus+0.40 end
  checked(game.combat.register_formula({
    id = formula_id,
    operation = "multiply",
    value = bonus,
    priority = 50
  }))
end

-- Import kills saved by the previous standalone Weapon Mastery package. The
-- manager's Skills and Actions pages now own mastery presentation.
checked(game.scripts.register_function({
  id = "import_legacy_mastery",
  description = "Merge weapon mastery kills from the previous standalone package"
}, function(args)
  local incoming = args and args.mastery
  if type(incoming) ~= "table" then error("mastery must be a table keyed by stable weapon id") end
  local data, imported = mastery_data(), 0
  for id, kills in pairs(incoming) do
    if type(id) == "string" and id ~= "" and type(kills) == "number" and kills == kills then
      kills = math.max(0, math.min(1000000, math.floor(kills)))
      if kills > (data[id] or 0) then data[id] = kills; imported = imported + 1 end
    end
  end
  if imported > 0 then checked(moonmod.storage.set("weapon_mastery_v1", data)) end
  update_combat_damage()
  return { imported = imported }
end))

local function add_xp(char_idx, amount)
  if amount <= 0 or char_idx < 0 or char_idx > 5 then return end
  amount=math.max(1,math.floor(amount*(1+0.05*skill_rank("focus.scholar"))))
  local level, xp, paragon = get_char_progression(char_idx)
  local leveled = false
  local paragon_up = false

  xp = xp + amount

  while level < MAX_LEVEL and xp >= xp_needed_for_level(level) do
    xp = xp - xp_needed_for_level(level)
    level = level + 1
    leveled = true
    local player = game.characters.get({id=CHARACTERS[char_idx]})
    if player then
      game.player.set({character = CHARACTERS[char_idx], max_hp = math.min(999, player.max_hp + HP_PER_LEVEL)})
    end
    if player and player.hp > 0 then game.player.heal({ character = CHARACTERS[char_idx], amount = HP_PER_LEVEL * 10 }) end
  end

  if level >= MAX_LEVEL then
    while paragon < 50 and xp >= paragon_needed_for_rank(paragon) do
      xp = xp - paragon_needed_for_rank(paragon)
      paragon = paragon + 1
      paragon_up = true
      local player = game.characters.get({id=CHARACTERS[char_idx]})
      if player then
        game.player.set({character = CHARACTERS[char_idx], max_hp = math.min(999, player.max_hp + PARAGON_HP_PER_RANK)})
      end
      if player and player.hp > 0 then game.player.heal({ character = CHARACTERS[char_idx], amount = PARAGON_HP_PER_RANK * 10 }) end
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
  local char_idx = saved_number(args and args.character,0,0,5)
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
checked(game.ui.register({
  id = "open_skills",
  label = "Open Ascension Skills",
  description = "Go directly to Ascension's skill trees in the manager"
}))

moonmod.on("ui.action", function(action)
  if action.id == "open_skills" then
    checked(game.ui.open_skills())
  elseif action.id == "ascension_inspect" then
    local player = game.player.get()
    local char_idx = 0
    if player and player.character then
      for idx, name in pairs(CHARACTERS) do
        if name == player.character then char_idx = idx; break end
      end
    end
    local level, xp, paragon = get_char_progression(char_idx)
    local need = level < MAX_LEVEL and xp_needed_for_level(level) or paragon_needed_for_rank(paragon)
    local msg = string.format("%s L%d XP %d/%d P%d; skill points %d; Focus %d/%d", CHARACTERS[char_idx]:upper(), level, xp, need, paragon, math.max(0, skill_budget()), math.floor(focus), focus_max())
    game.ui.notify({ message = msg })
  end
end)

-- Award XP on enemy defeat
moonmod.on("game.enemy_defeated", function(event)
  -- Native death events capture the killer's character slot before the monster is recycled.
  local char_idx=event.attacker
  if type(char_idx)~="number" or char_idx<0 or char_idx>5 then
    local player=game.player.get()
    char_idx=player and player.character_id or nil
  end
  if type(char_idx)~="number" or char_idx<0 or char_idx>5 then return end
  mastery_record(event)
  -- Use the native monster's listed reward when available, with a reliable
  -- floor so custom/scripted kills also advance progression.
  local reward=type(event.reward_exp)=="number" and event.reward_exp>0 and event.reward_exp or 20
  add_xp(char_idx,math.max(20,reward))
  local ranks=skill_ranks()
  local siphon=ranks["moonmod.ascension:might.siphon"] or 0
  local damage=type(event.damage)=="number" and event.damage or 0
  if siphon>0 and damage>0 then
    game.player.heal({character=CHARACTERS[char_idx],amount=math.max(1,math.floor(damage*0.02*siphon))})
  end
  local hunter=ranks["moonmod.ascension:focus.treasure_hunter"] or 0
  local money=type(event.reward_money)=="number" and event.reward_money or 0
  local extra=math.floor(money*0.10*hunter)
  if extra>0 then game.economy.add({amount=extra}) end
end)

moonmod.on("game.world.location_changed", function(_)
  mastery_seen = {}
  update_combat_damage()
end)

moonmod.log("info", "moonmod.ascension initialized.")

-- Shared party skill budget: one point per level/rank earned by any character.
-- Deriving the budget preserves existing XP and avoids granting points twice on reload.
local skill_costs={["might.shockwave"]=2,["vitality.second_wind"]=2,["focus.berserk"]=2}
local function skill_budget()
  local earned, spent = 0, 0
  for i = 0, 5 do
    local level, _, paragon = get_char_progression(i)
    earned = earned + (level-1) + math.floor((level-1)/5) + paragon
  end
  local listed=game.skills.list()
  for _, skill in ipairs((listed and listed.skills) or {}) do
    local local_id=(skill.id or ""):gsub("^moonmod.ascension:","")
    spent=spent+skill.rank*(skill_costs[local_id] or 1)
  end
  return earned - spent
end

-- The manager's generic Skills page can also increase ranks: enforce the same budget.
local restoring_rank = false
moonmod.on("skills.rank_changed", function(event)
  if restoring_rank or event.rank <= event.previous_rank or skill_budget() >= 0 then return end
  restoring_rank = true
  game.skills.set_rank({id = event.id, rank = event.previous_rank})
  restoring_rank = false
  game.ui.notify({message = "No skill points available"})
end)
moonmod.on("skills.train_requested", function(event)
  local id = event.id
  local prefix = "moonmod.ascension:"
  if type(id) ~= "string" or id:sub(1, #prefix) ~= prefix then return end
  local listed = game.skills.list()
  for _, skill in ipairs((listed and listed.skills) or {}) do
    if skill.id == id then
      if skill.rank >= skill.max_rank then game.ui.notify({message = "This skill is at maximum rank"}); return end
      local local_id = id:sub(#prefix + 1)
      if skill_budget() < (skill_costs[local_id] or 1) then game.ui.notify({message = "Not enough skill points for this rank"}); return end
      local changed, err = game.skills.set_rank({id = id, rank = skill.rank + 1})
      if not changed then
        game.ui.notify({message = type(err) == "table" and err.message or "Skill prerequisites are not met"})
      else
        game.ui.notify({message = skill.title .. " rank " .. (skill.rank + 1)})
      end
      return
    end
  end
  game.ui.notify({message = "Skill is no longer available"})
end)
local last_frame = -60
moonmod.on("game.tick", function(event)
  local frame = event.frame or 0
  if frame - last_frame < 30 then return end
  last_frame = frame
  local player = game.player.get()
  if not player then return end
  update_combat_damage()
end)

-- Use the highest earned character level so switching party members never shrinks a run.
-- Additive native modifiers compose with Dungeon+'s base layout without replacing it.
local last_floor_bonuses, generation_tick = nil, -50
local function update_floor_bonuses()
  local highest = 1
  for i = 0, 5 do local level = get_char_progression(i); highest = math.max(highest, level) end
  local cap = moonmod.settings.get("floor_bonus_cap") or 100
  local bonuses, signature = {}, ""
  for _, key in ipairs({"rooms", "monsters", "chests", "chest_value"}) do
    bonuses[key] = math.min(cap, (highest - 1) * (moonmod.settings.get(key .. "_per_level") or 10))
    signature = signature .. ":" .. bonuses[key]
  end
  if signature ~= last_floor_bonuses then
    local result, err = game.dungeons.set_modifiers(bonuses)
    if result then last_floor_bonuses = signature
    else moonmod.log("warn", "Floor modifiers: " .. err.message) end
  end
end
game.ui.register({id = "floor_bonuses", label = "Ascension Floor Bonuses", description = "Room, monster, chest and loot bonuses for future floors"})
moonmod.on("ui.action", function(action)
  if action.id ~= "floor_bonuses" then return end
  update_floor_bonuses()
  local highest = 1
  for i = 0, 5 do local level = get_char_progression(i); highest = math.max(highest, level) end
  local cap = moonmod.settings.get("floor_bonus_cap") or 100
  local function bonus(key) return math.min(cap, (highest - 1) * (moonmod.settings.get(key .. "_per_level") or 10)) end
  game.ui.notify({message = string.format("NEXT FLOOR: Rooms +%d%% Monsters +%d%% Chests +%d%% Chest Gilda +%d%%", bonus("rooms"), bonus("monsters"), bonus("chests"), bonus("chest_value"))})
end)
moonmod.on("game.tick", function(event)
  if event.frame - generation_tick >= 50 then generation_tick = event.frame; update_floor_bonuses() end
end)
moonmod.on("game.enemy_defeated", function() update_floor_bonuses() end)
update_floor_bonuses()

local function update_defense()
  local listed = game.skills.list()
  local toughness, iron_skin = 0, 0
  for _, skill in ipairs((listed and listed.skills) or {}) do
    if skill.id == "moonmod.ascension:vitality.toughness" then toughness=skill.rank end
    if skill.id == "moonmod.ascension:vitality.iron_skin" then iron_skin=skill.rank end
  end
  local multiplier=math.max(0.65,1-0.05*toughness-0.02*iron_skin)
  if berserk_active() then multiplier=multiplier*1.20 end
  checked(game.combat.register_player_formula({id="toughness",operation="multiply",value=multiplier,priority=50}))
end
local function update_weapon_guard()
  local player=game.player.get()
  local weapon_id=player and player.weapon and player.weapon.id or ""
  -- Hero Aga's Sword reduces incoming hits by 15, matching its original mod effect.
  checked(game.combat.register_player_formula({id="agas-sword-guard",operation="add",value=weapon_id=="chronicle:weapon:281" and -15 or 0,priority=60}))
end
moonmod.on("skills.rank_changed",function() update_defense(); update_weapon_guard(); update_combat_damage(); focus=math.min(focus,focus_max()) end)
update_defense()
update_weapon_guard()
moonmod.on("game.player.thirst_changed",function(event)
  if event.source~="native" or not event.previous_water or not event.water then return end
  local world=game.world.get()
  if not world or world.context~="dungeon" then return end
  local rank=skill_rank("vitality.survivalist")
  local lost=math.max(0,event.previous_water-event.water)
  local restore=lost*rank*0.06
  if restore>0 then
    checked(game.player.thirst_set({restore=restore,character=event.character or "active"}))
  end
end)
moonmod.on("game.tick",function(event)
  current_frame=event.frame or (current_frame+1)
  local elapsed=math.max(0,current_frame-last_focus_frame)
  last_focus_frame=current_frame
  focus=math.min(focus_max(),focus+1.5*(1+0.08*skill_rank("focus.quick_recovery"))*elapsed/60)
  if current_frame%30==0 then update_combat_damage(); update_defense(); update_weapon_guard() end
  if current_frame%60==0 then
    local rank=skill_rank("vitality.regeneration")
    local player=game.player.get()
    if rank>0 and player and player.hp>0 then
      game.player.heal({character=player.character,amount=math.max(1,math.floor((player.max_hp or 1)*0.004*rank))})
    end
  end
end)
-- The native adapter emits a unique generation-qualified actor handle per defeat.
-- XP handler above is retained; the adapter guarantees one native death transition per actor.
local party_cursor = -1
local mastery_cursor = 0
checked(game.ui.register({id="party_progress",label="Party Levels (Next Character)",description="Cycle joined party members and inspect their level, XP, Paragon and HP"}))
checked(game.ui.register({id="ascension_help",label="How Ascension Works",description="Explain progression, skill training and the floor generation bonuses"}))
checked(game.ui.register({id="respec",label="Refund All Skill Ranks",description="Free respec: refunds earned skill points; preserves levels, XP and maximum HP"}))
checked(game.ui.register({id="mastery_equipped",label="Equipped Weapon Mastery",description="Inspect kills, rank, and damage bonus for your equipped weapon"}))
checked(game.ui.register({id="mastery_browse",label="Browse Weapon Mastery",description="Cycle weapon types with recorded mastery"}))
for _,action in ipairs({
  {"cast_shockwave","Cast Shockwave","Damage all living enemies on the floor. Requires Shockwave; costs 30 Focus."},
  {"cast_second_wind","Cast Second Wind","Heal 30% max HP. Requires Second Wind; costs 40 Focus."},
  {"cast_berserk","Cast Berserk","Gain +40% damage for 10 seconds and take +20% damage. Requires Berserk; costs 25 Focus."}
}) do checked(game.ui.register({id=action[1],label=action[2],description=action[3]})) end

local function cast_ability(action_id)
  local definitions={
    cast_shockwave={skill="might.shockwave",cost=30,cooldown=360},
    cast_second_wind={skill="vitality.second_wind",cost=40,cooldown=1200},
    cast_berserk={skill="focus.berserk",cost=25,cooldown=1500}
  }
  local ability=definitions[action_id]
  if not ability or skill_rank(ability.skill)<1 then game.ui.notify({message="Learn this active skill first"});return end
  if current_frame<(cooldown_until[action_id] or 0) then
    game.ui.notify({message="Skill cooling down: "..math.ceil((cooldown_until[action_id]-current_frame)/60).."s"});return
  end
  if focus<ability.cost then game.ui.notify({message="Not enough Focus"});return end
  focus=focus-ability.cost
  local cooldown=math.floor(ability.cooldown*(1-0.08*skill_rank("focus.cooldown_mastery")))
  cooldown_until[action_id]=current_frame+cooldown
  if action_id=="cast_shockwave" then
    local player=game.player.get()
    local attack=player and player.weapon and player.weapon.attack or 10
    local query=game.entities.query({type="monster"})
    local hits=0
    for _,enemy in ipairs((query and query.entities) or {}) do
      if enemy.entity_id then
        local result=game.combat.damage({entity=enemy.entity_id,amount=math.max(1,math.floor(attack*1.5+20))})
        if result and result.changed then hits=hits+1 end
      end
    end
    game.ui.notify({message="SHOCKWAVE hit "..hits.." enemies"})
  elseif action_id=="cast_second_wind" then
    local player=game.player.get()
    if not player then focus=focus+ability.cost;return end
    game.player.heal({character=player.character,amount=math.max(1,math.floor((player.max_hp or 1)*0.30))})
    game.ui.notify({message="SECOND WIND restored health"})
  else
    berserk_until=current_frame+600
    update_combat_damage();update_defense()
    game.ui.notify({message="BERSERK active for 10 seconds"})
  end
end

moonmod.on("ui.action",function(action)
  if action.id=="cast_shockwave" or action.id=="cast_second_wind" or action.id=="cast_berserk" then
    cast_ability(action.id);return
  end
end)

moonmod.on("ui.action",function(action)
  if action.id == "party_progress" then
    local party=game.party.list()
    if not party or #party==0 then game.ui.notify({message="Load a game first"}); return end
    party_cursor=(party_cursor+1)%#party
    local i=party[party_cursor+1].character_id
    local level,xp,paragon=get_char_progression(i)
    local char=game.characters.get({id=CHARACTERS[i]})
    game.ui.notify({message=string.format("%s L%d XP%d Paragon%d HP%d/%d; shared skill points %d",CHARACTERS[i]:upper(),level,xp,paragon,char.hp,char.max_hp,math.max(0,skill_budget()))})
  elseif action.id == "mastery_equipped" then
    local player=game.player.get()
    local weapon_id=player and player.weapon and player.weapon.id or nil
    if not weapon_id then game.ui.notify({message="Equip a weapon to inspect its mastery"}); return end
    local kills=mastery_data()[weapon_id] or 0
    local rank=mastery_rank(kills)
    local next_kill=MASTERY_THRESHOLDS[rank+1]
    game.ui.notify({message=string.format("%s: MASTERY %d/5, %d kills, +%d%% damage. %s",weapon_id,rank,kills,math.floor(rank*(moonmod.settings.get("mastery_damage_per_rank") or 2)+0.5),next_kill and ("Next rank at "..next_kill) or "Maximum mastery")})
  elseif action.id == "mastery_browse" then
    local records=mastery_data()
    local ids={}
    for id,kills in pairs(records) do if type(id)=="string" and type(kills)=="number" and kills>0 then ids[#ids+1]=id end end
    table.sort(ids)
    if #ids==0 then game.ui.notify({message="No weapon mastery yet. Defeat enemies with a weapon to begin."}); return end
    mastery_cursor=mastery_cursor%#ids+1
    local id=ids[mastery_cursor]
    local kills=records[id]
    local rank=mastery_rank(kills)
    game.ui.notify({message=string.format("%s: MASTERY %d/5, %d kills, +%d%% damage",id,rank,kills,math.floor(rank*(moonmod.settings.get("mastery_damage_per_rank") or 2)+0.5))})
  elseif action.id == "ascension_help" then
    game.ui.notify({message="Defeat enemies for XP. Levels grant +3 max HP, +2.5% damage and shared skill points. Skills tab: Confirm trains; Actions tab casts learned skills using Focus. Paragon starts at level 40."})
  elseif action.id == "respec" then
    local listed=game.skills.list()
    local owned={}
    for _,skill in ipairs((listed and listed.skills) or {}) do
      if type(skill.id)=="string" and skill.id:sub(1,18)=="moonmod.ascension:" then owned[#owned+1]=skill.id end
    end
    for _,id in ipairs(owned) do checked(game.skills.set_rank({id=id,rank=0})) end
    focus=focus_max(); cooldown_until={}; berserk_until=0
    update_defense()
    update_combat_damage()
    game.ui.notify({message="Skills refunded. Available points: " .. math.max(0,skill_budget())})
  end
end)
moonmod.on("game.dungeon.generating",function() update_floor_bonuses() end)

