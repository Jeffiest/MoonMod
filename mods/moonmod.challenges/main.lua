-- Challenges: boss fights worth the name, and challenge modes under one title-menu row.
--
-- Boss phases (story game and Boss Rush): a story boss in sight gets a name card, an HP bar (top left, with the game's
-- other bars) and two more phases. Below `enraged_at` it is enraged: it hits harder, takes a little less, glows red
-- and grows. Below `desperate_at` it is desperate: harder still, purple. Each phase starts with a burst of smoke and a
-- notice. Bosses are known by their native model number (entities.query's native_model_id).
--
-- Boss Rush (title menu > Challenges): a sandbox session on one registered arena floor with no monsters and no chests.
-- Its Warden room opens at once; walk in, the doors shut, and the story's bosses come one after another, in story
-- order, each rising where the last fell: Dran, Master Utan, the Ice Queen, the King's Curse, Minotaur Joe and both
-- forms of the Dark Genie. The party grows to each boss's place in the story (max HP and a damage multiplier), and
-- between bosses a panel offers a boon. The clock runs from the first step to the last blow; the best time is kept.
--
-- The Shaft (title menu > Challenges): an endless descent. One registered floor in each of three dungeons leads back
-- to itself, built anew each time, so the floors never run out. Monsters grow with depth, and so does the party.
-- Every tenth floor is a guardian's: its room is sealed until the rest of the floor is clear, and inside waits the
-- floor's toughest monster grown huge. Felling it heals the party and offers a pact (a harder rule with a reward);
-- then the descent moves on to the next dungeon. Start opens a menu to end the descent; the deepest floor is kept.
--
-- The title menu has room for two mod rows (each pushes the copyright banner down), and the Gauntlet holds one, so
-- every challenge mode lives on this one row's pages.
--
-- Floor slots: a dungeon holds 25 floors and the Gauntlet takes seven in each of the five, which fills the Shipwreck
-- (18 of its own) and the Sun and Moon Temple (18). The arena goes in the Divine Beast Cave or the Moon Sea and the
-- Shaft in the Cave, Wise Owl Forest and the Moon Sea, so both fit beside the Gauntlet.

local ID = "moonmod.challenges"
local MODE = "challenges"

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil, a
end
local function errmsg(err) return tostring(type(err) == "table" and (err.message or err.code) or err or "unknown") end
local function setting(id, fallback)
  local v = moonmod.settings.get(id)
  if v == nil then return fallback end
  return v
end
local function notify(message) try(game.ui.notify, {message = message}) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local frame = 0

-- The story's bosses, by native model ------------------------------------------------------------------------------
-- `cast` lists the monsters each boss's arena places beside it, by the slots their scripts name each other by (the
-- boss holds 0). `hp` brings the Genie's forms, whose native life is far above the others', to the same footing.
local BOSS = {
  [78] = {name = "Dran", epithet = "Lord of the Divine Beast Cave", grounded = true, scale = 0.65},
  [79] = {name = "Master Utan", epithet = "Elder of the Wise Owl Forest"},
  [80] = {name = "Ice Queen", epithet = "Mistress of the Shipwreck", cast = {101, 76, 102, 103, 92, 104, 104, 104}},
  [81] = {name = "King's Curse", epithet = "The Sun and Moon Temple's Shadow", cast = {82}},
  [83] = {name = "Minotaur Joe", epithet = "Brute of the Moon Sea", cast = {91, 91, 91}},
  [84] = {name = "Dark Genie", epithet = "The Wish-Granter's Shadow", hp = 1 / 5,
          cast = {[1] = 85, [2] = 86, [3] = 87, [4] = 88, [5] = 89, [6] = 90, [7] = 93}},
  [106] = {name = "Dark Genie", epithet = "Darkness Unbound", hp = 1 / 10,
           cast = {[1] = 105, [2] = 105, [3] = 107, [4] = 107, [5] = 108, [6] = 108, [7] = 109, [8] = 110}},
}
local CAST_NAMES = {[76] = "Ice Arrow", [82] = "Curse", [85] = "Genie's Hand", [86] = "Genie's Hand", [87] = "Genie's Light",
                    [88] = "Genie's Wind", [89] = "Genie's Beam", [90] = "Genie's Beam", [91] = "Wine Keg", [92] = "Ice Aura",
                    [93] = "Genie's Shockwave", [101] = "Ice Barrier", [102] = "Ice Prison", [103] = "Ice Meteor",
                    [104] = "Ice Tornado", [105] = "Shade", [107] = "Dark Pillar", [108] = "Dark Shockwave",
                    [109] = "Dark Beam", [110] = "Dark Beam"}

-- Sessions: another mod's sandbox run (the Gauntlet) is its own game, and its Wardens are its own.
local session_owner = nil -- the owner of the running sandbox session, nil in the story
local function other_session() return session_owner ~= nil and session_owner ~= ID end

-- Boss phases --------------------------------------------------------------------------------------------------------
local tracked = {}     -- by entity handle: {model, phase, base, defense, carded}
local floor_token = nil
local bar_shown = false
local rush = nil       -- the Boss Rush run, while one is going (below)
local shaft = nil      -- the Shaft's descent, while one is going (below)
local shaft_generating -- the Shaft's floor setup (below)

local function phase_mult(phase)
  local enraged = setting("phase_damage", 140) / 100
  if phase == 2 then return enraged end
  if phase == 3 then return math.min(3, enraged * 1.3) end
  return 1
end

local PHASE = {
  [2] = {tint = {r = 255, g = 60, b = 40}, grow = 1.1, line = "%s is enraged!"},
  [3] = {tint = {r = 170, g = 60, b = 255}, grow = 1.18, line = "%s fights with the last of its strength!"},
}

local function set_phase(t, phase, e)
  t.phase = phase
  local def = BOSS[t.model]
  local p = PHASE[phase]
  local request = {entity = t.handle, damage_scale = clamp(t.base * phase_mult(phase), 0, 100)}
  if phase == 2 and t.defense then request.defense = math.floor(clamp(t.defense * 1.2, 0, 32767)) end
  try(game.entities.set_stats, request)
  try(game.entities.tint, {entity = t.handle, color = p.tint, frames = 3600})
  try(game.entities.scale_set, {entity = t.handle, scale = clamp((def.scale or 1) * p.grow, 0.5, 3)})
  if e and e.position then try(game.effects.burst, {kind = "smoke", position = e.position, scale = 2}) end
  notify(string.format(p.line, def.name))
end

local function remove_bar()
  if bar_shown then try(game.render.bar_remove, {id = "boss"}); bar_shown = false end
end

local function watch_bosses()
  local q = try(game.entities.query, {type = "monster"})
  local main = nil
  for _, e in ipairs(q and q.entities or {}) do
    local model = tonumber(e.native_model_id)
    local def = model and BOSS[model]
    local handle = e.entity_id or e.id
    local max = e.health and tonumber(e.health.maximum) or 0
    local cur = e.health and tonumber(e.health.current) or 0
    if def and handle and e.revealed ~= false and max > 0 and cur > 0 then
      local key = tostring(handle)
      local t = tracked[key]
      if not t then
        t = {model = model, handle = handle, phase = 1, base = 1,
             defense = e.combat and tonumber(e.combat.defense) or nil}
        if rush and rush.boss and tostring(rush.boss) == key then t.base, t.carded = rush.damage or 1, true end
        tracked[key] = t
        if not t.carded and setting("boss_card", true) then
          t.carded = true
          try(game.ui.boss_card, {kicker = "BOSS", name = def.name, epithet = def.epithet, frames = 150})
        end
      end
      if setting("phases", true) then
        local pct = cur * 100 / max
        if t.phase < 3 and pct <= setting("desperate_at", 20) then set_phase(t, 3, e)
        elseif t.phase < 2 and pct <= setting("enraged_at", 50) then set_phase(t, 2, e) end
      end
      if not main or main.max < max then main = {name = def.name, cur = cur, max = max} end
    end
  end
  if main and setting("boss_bar", true) then
    try(game.render.bar_register, {id = "boss", label = main.name:upper():sub(1, 24), current = clamp(main.cur, 0, main.max), max = main.max})
    bar_shown = true
  else
    remove_bar()
  end
end

-- Boss Rush ----------------------------------------------------------------------------------------------------------
local RUSH_ORDER = {78, 79, 80, 81, 83, 84, 106}
-- The party at each boss's place in the story: max HP and a damage multiplier on the starting weapons (a session
-- starts each hero with their first weapon).
local TIER_HP = {120, 170, 230, 290, 360, 430, 430}
local TIER_POWER = {1.5, 2.6, 3.8, 5.0, 6.4, 8.0, 8.0}
local ITEM = {bread = 148, water = 146, repair = 177}

local records = moonmod.storage.get("records")
if type(records) ~= "table" then records = {runs = 0, clears = 0, best = nil, furthest = 0} end
local function save_records() moonmod.storage.set("records", records) end

local arena = nil -- the arena floor's stable id
local function adopt(r)
  local f = r and r.floors and r.floors[1]
  if f and f.id then arena = f.id; return true end
  return false
end
for _, dungeon in ipairs({0, 4}) do
  local r = try(game.dungeons.register, {id = "boss-rush", name = "Boss Rush", dungeon = dungeon,
      floors = {{id = "arena", name = "Boss Rush Arena", source_floor = 1, enemies = {}}}})
  if adopt(r) then break end
end
if not arena then adopt(try(game.dungeons.get, "boss-rush")) end
if not arena then moonmod.log("warn", "Boss Rush: no dungeon had room for the arena floor") end

local variants = {}
local function variant(model, name)
  if variants[model] then return variants[model] end
  local r = try(game.characters.register, {id = "rush-" .. model, kind = "enemy", name = (name or "Boss"):sub(1, 30),
                                           template_monster_id = model})
  variants[model] = r and r.id or (ID .. ":rush-" .. model)
  return variants[model]
end

local function members()
  local list = {}
  for _, m in ipairs(try(game.party.list) or {}) do
    if type(m) == "table" and type(m.id) == "string" then list[#list + 1] = m.id end
  end
  if #list == 0 then list[1] = "toan" end
  return list
end

local function heal_party(fraction)
  for _, c in ipairs(members()) do
    local hp = TIER_HP[rush.stage] or TIER_HP[#TIER_HP]
    try(game.player.heal, {amount = math.max(1, math.floor(hp * fraction)), character = c})
  end
end

local function apply_tier()
  local stage = math.min(rush.stage, #TIER_HP)
  for _, c in ipairs(members()) do try(game.player.set, {max_hp = TIER_HP[stage], character = c}) end
  try(game.combat.register_formula, {id = "rush_power", operation = "multiply", priority = 60,
      value = clamp(TIER_POWER[stage] * (rush.whet or 1), 0, 100)})
end

local function mend_weapon()
  local p = try(game.player.get)
  local w = p and p.weapon
  if w and w.id and (w.durability_max or 0) > 0 then
    try(game.weapons.durability_set, {id = w.id, character = p.character, slot = w.slot, durability = w.durability_max})
  end
end

local function clock(frames)
  local s = math.floor((frames or 0) / 60)
  return string.format("%d:%02d", s // 60, s % 60)
end

local function spawn_stage()
  local model = RUSH_ORDER[rush.stage]
  local def = BOSS[model]
  local at = rush.center
  apply_tier()
  local s = try(game.characters.spawn, {character = variant(model, def.name), position = at, arena_origin = at,
                                        grounded = def.grounded, arena_slot = 0})
  local handle = s and (s.entity_handle or s.id)
  if not handle then return false end -- the floor isn't ready to place it: asked again next tick
  local base = s.stats and tonumber(s.stats.hp) or 1000
  local hp = math.floor(clamp(base * (def.hp or 1) * setting("rush_life", 100) / 100, 1, 1000000))
  -- with hit_share every hero hurts each part of a boss as much as the hero it suits best (the Ice Queen is
  -- otherwise Ruby's alone)
  try(game.entities.set_stats, {entity = handle, max_hp = hp, hp = hp, hit_share = true})
  if def.scale then try(game.entities.scale_set, {entity = handle, scale = def.scale}) end
  for slot, m in pairs(def.cast or {}) do
    local c = try(game.characters.spawn, {character = variant(m, CAST_NAMES[m]), position = at, arena_origin = at,
                                          grounded = def.grounded, arena_slot = slot})
    local h = c and (c.entity_handle or c.id)
    if h then try(game.entities.set_stats, {entity = h, hit_share = true}) end
  end
  rush.boss, rush.seen_alive, rush.damage = handle, false, 1
  try(game.ui.boss_card, {kicker = string.format("BOSS RUSH  %d OF %d", rush.stage, #RUSH_ORDER),
                          name = def.name, epithet = def.epithet, frames = 150})
  return true
end

local function finish_records(cleared)
  records.furthest = math.max(records.furthest or 0, cleared and #RUSH_ORDER or (rush.stage - 1))
  if cleared then
    records.clears = (records.clears or 0) + 1
    if not records.best or rush.frames < records.best then records.best = rush.frames end
  end
  save_records()
end

local BOONS = {
  {id = "mend", title = "Mend", lines = {"Heal the whole party fully.", "Mend your weapon."}},
  {id = "whet", title = "Whet", lines = {{text = "+15% damage for the rest of the run.", tone = "good"}, "Heal half."}},
  {id = "supplies", title = "Supplies", lines = {"Two Bread, a Tasty Water", "and a Repair Powder.", "Heal half."}},
}

local function stage_cleared()
  rush.boss = nil
  if rush.stage >= #RUSH_ORDER then
    rush.won = true
    finish_records(true)
    try(game.ui.boss_card, {kicker = "BOSS RUSH CLEARED", name = clock(rush.frames),
                            epithet = records.best == rush.frames and "A new best time" or ("Best " .. clock(records.best)), frames = 300})
    rush.finish_at = frame + 330
    return
  end
  rush.stage = rush.stage + 1
  if RUSH_ORDER[rush.stage] == 106 then
    -- the Genie's true form rises from the first at once: no rest between them
    notify("The Genie's body bursts... and darkness itself rises!")
    rush.next_at = frame + 150
    return
  end
  local options = {}
  for i, b in ipairs(BOONS) do options[i] = {title = b.title, lines = b.lines} end
  rush.choosing = true
  try(game.ui.choice_open, {id = "rush_boon", title = "A MOMENT'S REST",
      subtitle = string.format("%d of %d fallen. Next: %s", rush.stage - 1, #RUSH_ORDER, BOSS[RUSH_ORDER[rush.stage]].name),
      options = options})
end

moonmod.on("ui.choice_made", function(e)
  if not (rush and rush.choosing and e and e.id == "rush_boon") then return end
  local boon = BOONS[tonumber(e.index) or 1] or BOONS[1]
  rush.choosing = false
  apply_tier()
  if boon.id == "mend" then heal_party(1); mend_weapon()
  elseif boon.id == "whet" then rush.whet = (rush.whet or 1) * 1.15; apply_tier(); heal_party(0.5)
  else
    try(game.items.give, {id = "chronicle:item:" .. ITEM.bread, count = 2})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.water, count = 1})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.repair, count = 1})
    heal_party(0.5)
  end
  rush.next_at = frame + 120
end)

local function rush_tick()
  if not rush.live then return end
  if rush.center and not rush.won then rush.frames = rush.frames + 1 end
  if rush.finish_at and frame >= rush.finish_at then
    rush.finish_at = nil
    try(game.session.finish)
    return
  end
  if rush.next_at and frame >= rush.next_at and rush.center then
    if spawn_stage() then rush.next_at = nil end
  end
  if rush.boss then
    local e = try(game.entities.get, rush.boss)
    if e and e.status == "alive" then rush.seen_alive = true
    elseif rush.seen_alive or (e and e.status == "dead") then stage_cleared() end
  end
end

moonmod.on("game.dungeon.warden_room", function(e)
  if shaft and shaft.live and e and e.state == "entered" and type(e.center) == "table" and shaft.guardian_floor and not shaft.room then
    shaft.room = {x = tonumber(e.center.x) or 0, y = tonumber(e.center.y) or 0, z = tonumber(e.center.z) or 0}
    return
  end
  if not (rush and rush.live) or rush.center or not e then return end
  if e.state == "entered" and type(e.center) == "table" then
    rush.center = {x = tonumber(e.center.x) or 0, y = tonumber(e.center.y) or 0, z = tonumber(e.center.z) or 0}
    rush.next_at = frame + 60
  end
end)

moonmod.on("game.dungeon.generating", function(e)
  if rush then
    try(game.dungeons.set_modifiers, {chests = -100})
    try(game.dungeons.set_warden_room, {enabled = true, lock_in = true})
  elseif shaft and e then
    shaft_generating(e)
  end
end)

local function rush_cleanup()
  try(game.dungeons.set_warden_room, {enabled = false})
  try(game.dungeons.set_modifiers, {})
  try(game.dungeons.set_layout, {})
  try(game.combat.register_formula, {id = "rush_power", operation = "multiply", priority = 60, value = 1})
  remove_bar()
end

local page, message = "root", nil
local show -- the title pages, below

-- The Shaft ----------------------------------------------------------------------------------------------------------
local SHAFT_DUNGEONS = {0, 1, 4}
local SHAFT_NAMES = {[0] = "Divine Beast Cave", [1] = "Wise Owl Forest", [4] = "Moon Sea"}
local shaft_floors = {}  -- in descent order: {dungeon, id, native}
for _, dungeon in ipairs(SHAFT_DUNGEONS) do
  local local_id = "shaft-" .. dungeon
  local r = try(game.dungeons.register, {id = local_id, name = "The Shaft", dungeon = dungeon,
      floors = {{id = "depth", name = "The Shaft", source_floor = dungeon == 0 and 5 or 6}}})
  r = r or try(game.dungeons.get, local_id)
  local f = r and r.floors and r.floors[1]
  if f and f.id then
    local native = tonumber(f.native_floor_id)
    shaft_floors[#shaft_floors + 1] = {dungeon = dungeon, id = f.id, native = native}
    -- its exit gate leads back to itself, built anew: the floors never run out
    if native then try(game.dungeons.floor_redirect, {dungeon_id = dungeon, floor_id = native, to_floor_id = native}) end
  end
end
if #shaft_floors == 0 then moonmod.log("warn", "The Shaft: no dungeon had room for its floor") end

-- Pacts: one is offered three at a time after each guardian. Each makes the descent harder and pays for it.
local PACTS = {
  {id = "swarm", title = "Swarm", lines = {{text = "+40% monsters", tone = "bad"}, {text = "+50% Gilda from kills", tone = "good"}}},
  {id = "glass", title = "Glass", lines = {{text = "Monsters hit 30% harder", tone = "bad"}, {text = "You hit 25% harder", tone = "good"}}},
  {id = "iron", title = "Iron", lines = {{text = "Monsters +40% life", tone = "bad"}, {text = "Weapons wear half as fast", tone = "good"}}},
  {id = "drought", title = "Drought", lines = {{text = "Thirst twice as fast", tone = "bad"}, {text = "+50% chests", tone = "good"}}},
  {id = "dark", title = "Darkness", lines = {{text = "No map", tone = "bad"}, {text = "+60% weapon ABS from kills", tone = "good"}}},
  {id = "hunger", title = "Hunger", lines = {{text = "No healing between strata", tone = "bad"}, {text = "+1 Fruit of Eden now", tone = "good"}}},
}
local PACT = {}
for _, pact in ipairs(PACTS) do PACT[pact.id] = pact end

-- shaft: {depth, stratum, pacts, scaled, toughest, room, guardian, ...}

local function pact_count(id)
  local n = 0
  for _, p in ipairs(shaft and shaft.pacts or {}) do if p == id then n = n + 1 end end
  return n
end

local function shaft_floor() return shaft_floors[((shaft.stratum - 1) % #shaft_floors) + 1] end

local function shaft_tuning()
  try(game.player.tuning_set, {thirst_drain = clamp(2 ^ pact_count("drought"), 0.25, 4),
                               durability_wear = clamp(0.5 ^ pact_count("iron"), 0.25, 4),
                               map_hidden = pact_count("dark") > 0})
  -- the party grows with depth: a little less than the monsters do
  local power = (1 + 0.1 * math.max(0, shaft.depth - 1)) * (1.25 ^ pact_count("glass"))
  try(game.combat.register_formula, {id = "shaft_power", operation = "multiply", priority = 60, value = clamp(power, 0, 100)})
  local hp = math.min(999, 100 + 6 * math.max(0, shaft.depth - 1))
  for _, c in ipairs(members()) do try(game.player.set, {max_hp = hp, character = c}) end
end

local function shaft_heal()
  for _, c in ipairs(members()) do try(game.player.heal, {amount = 999, character = c}) end
end

local function shaft_menu()
  local lines = {string.format("Floor %d, stratum %d: %s", shaft.depth, shaft.stratum, SHAFT_NAMES[shaft_floor().dungeon] or "?")}
  local names = {}
  for _, p in ipairs(shaft.pacts) do names[#names + 1] = PACT[p].title end
  lines[#lines + 1] = "Pacts: " .. (#names > 0 and table.concat(names, ", ") or "none yet")
  lines[#lines + 1] = string.format("Deepest: floor %d", math.max(records.shaft_deepest or 0, shaft.depth))
  try(game.ui.run_menu_set, {title = "THE SHAFT", tabs = {{id = "descent", title = "Descent", lines = lines,
      rows = {{id = "end", label = "End the descent", detail = "Back to the title. The floor you reached is kept."}}}}})
end

local function shaft_records()
  records.shaft_deepest = math.max(records.shaft_deepest or 0, shaft.depth)
  save_records()
end

-- Every monster grows with depth (and the pacts) the first time it is seen.
local function shaft_scale()
  local q = try(game.entities.query, {type = "monster"})
  local d = shaft.depth - 1
  local life = (1 + 0.15 * d) * (1.4 ^ pact_count("iron"))
  local hits = (1 + 0.06 * d) * (1.3 ^ pact_count("glass"))
  local gilda = 1.5 ^ pact_count("swarm")
  for _, e in ipairs(q and q.entities or {}) do
    local handle = e.entity_id or e.id
    local key = tostring(handle)
    local max = e.health and tonumber(e.health.maximum) or 0
    if handle and e.revealed ~= false and max > 0 and not shaft.scaled[key] and key ~= tostring(shaft.guardian) then
      shaft.scaled[key] = true
      local model = tonumber(e.native_model_id)
      if model and not BOSS[model] and (not shaft.toughest or max > shaft.toughest.hp) then shaft.toughest = {model = model, hp = max} end
      local hp = math.floor(clamp(max * life, 1, 1000000))
      local combat = e.combat or {}
      try(game.entities.set_stats, {entity = handle, max_hp = hp, hp = hp, damage_scale = clamp(hits, 0, 100),
          defense = math.floor(clamp((tonumber(combat.defense) or 0) + d, 0, 32767)),
          reward_money = math.floor(clamp((tonumber(combat.reward_money) or 0) * gilda, 0, 2147483647))})
    end
  end
end

local function spawn_guardian()
  local t = shaft.toughest
  if not t then shaft.guardian_done = true; return true end -- nothing to grow one from: the floor is its own reward
  local s = try(game.characters.spawn, {character = variant(t.model, "Guardian"), position = shaft.room})
  local handle = s and (s.entity_handle or s.id)
  if not handle then return false end
  local hp = math.floor(clamp(t.hp * 6 * (1 + 0.15 * (shaft.depth - 1)), 1, 1000000))
  try(game.entities.set_stats, {entity = handle, max_hp = hp, hp = hp,
      damage_scale = clamp(1.3 * (1 + 0.06 * (shaft.depth - 1)) * (1.3 ^ pact_count("glass")), 0, 100)})
  try(game.entities.scale_set, {entity = handle, scale = 1.8})
  shaft.guardian, shaft.guardian_alive = handle, false
  try(game.ui.boss_card, {kicker = string.format("THE SHAFT  FLOOR %d", shaft.depth), name = "Guardian of the Stratum",
                          epithet = SHAFT_NAMES[shaft_floor().dungeon], frames = 150})
  return true
end

local function offer_pacts()
  local pool = {}
  for _, p in ipairs(PACTS) do pool[#pool + 1] = p end
  local options, ids = {}, {}
  for i = 1, 3 do
    local j = math.random(#pool)
    local p = table.remove(pool, j)
    options[i] = {title = p.title, lines = p.lines}
    ids[i] = p.id
  end
  shaft.offer = ids
  try(game.ui.choice_open, {id = "shaft_pact", title = "A PACT FOR THE DEPTHS",
      subtitle = string.format("Stratum %d is behind you. Choose one to go on.", shaft.stratum), options = options})
end

local function guardian_fallen()
  shaft.guardian = nil
  shaft.guardian_done = true
  notify("The guardian falls. The way down opens.")
  offer_pacts()
end

local function shaft_tick()
  if not shaft.live then return end
  if shaft.next_at and frame >= shaft.next_at then
    local f = shaft_floor()
    if try(game.world.transition, {id = f.id}) then shaft.next_at = nil else shaft.next_at = frame + 90 end
  end
  if shaft.finish_at and frame >= shaft.finish_at then
    shaft.finish_at = nil
    try(game.session.finish)
  end
  if frame % 20 == 0 then shaft_scale() end
  if shaft.room and not shaft.guardian and not shaft.guardian_done and shaft.guardian_floor then spawn_guardian() end
  if shaft.guardian then
    local e = try(game.entities.get, shaft.guardian)
    if e and e.status == "alive" then shaft.guardian_alive = true
    elseif shaft.guardian_alive or (e and e.status == "dead") then guardian_fallen() end
  end
end

shaft_generating = function(e)
  if e.back_floor or e.prebuild then return end
  shaft.depth = shaft.depth + 1
  shaft.scaled, shaft.toughest, shaft.room, shaft.guardian, shaft.guardian_done = {}, nil, nil, nil, false
  shaft.guardian_floor = shaft.depth % 10 == 0
  local swarm = pact_count("swarm")
  try(game.dungeons.set_modifiers, {monsters = math.min(200, 5 * (shaft.stratum - 1) + 40 * swarm),
                                     chests = math.min(200, 50 * pact_count("drought"))})
  try(game.dungeons.set_warden_room, {enabled = shaft.guardian_floor, lock_in = true})
  shaft_tuning()
  shaft_records()
  shaft_menu()
end

moonmod.on("ui.choice_made", function(e)
  if not (shaft and shaft.offer and e and e.id == "shaft_pact") then return end
  local id = shaft.offer[tonumber(e.index) or 1] or shaft.offer[1]
  shaft.offer = nil
  shaft.pacts[#shaft.pacts + 1] = id
  if id == "hunger" then try(game.items.give, {id = "chronicle:item:180", count = 1}) end
  if pact_count("hunger") == 0 then shaft_heal() end
  shaft.stratum = shaft.stratum + 1
  notify(string.format("Pact of %s. Down to stratum %d.", PACT[id].title, shaft.stratum))
  shaft.next_at = frame + 60
end)

moonmod.on("ui.run_menu_action", function(e)
  if not (shaft and shaft.live and e and e.row == "end") then return end
  try(game.ui.run_menu_close)
  shaft.finish_at = frame + 10
end)

local function start_shaft()
  if #shaft_floors == 0 then message = "The Shaft has no floors this session."; show("root"); return end
  shaft = {depth = 0, stratum = 1, pacts = {}, scaled = {}, live = false}
  local everyone = setting("shaft_party", "Everyone") == "Everyone"
  local ok, err = try(game.session.start, {floor = shaft_floors[1].id, party_size = everyone and 6 or 1, character = "toan"})
  if not ok then
    shaft = nil
    message = ("The Shaft could not start: " .. errmsg(err)):sub(1, 64)
    show("root")
    return
  end
  records.shaft_runs = (records.shaft_runs or 0) + 1
  save_records()
end

local function shaft_cleanup()
  try(game.dungeons.set_warden_room, {enabled = false})
  try(game.dungeons.set_modifiers, {})
  try(game.dungeons.set_exits, {})
  try(game.player.tuning_clear)
  try(game.combat.register_formula, {id = "shaft_power", operation = "multiply", priority = 60, value = 1})
  try(game.ui.run_menu_clear)
end

-- Title pages --------------------------------------------------------------------------------------------------------
local function best_line()
  if records.best then return string.format("Best time %s, %d clear%s", clock(records.best), records.clears, records.clears == 1 and "" or "s") end
  if (records.furthest or 0) > 0 then return string.format("Furthest: %d of %d bosses", records.furthest, #RUSH_ORDER) end
  return "Not yet cleared"
end

show = function(name)
  page = name
  if name == "root" then
    try(game.title.mode_set, {id = MODE, title = "CHALLENGES", subtitle = "Tests for a seasoned adventurer",
        lines = {message or "Choose a challenge."}, root = true,
        entries = {{id = "boss_rush", label = "Boss Rush", enabled = arena ~= nil},
                   {id = "shaft", label = "The Shaft", enabled = #shaft_floors > 0}}})
  elseif name == "shaft" then
    try(game.title.mode_set, {id = MODE, title = "THE SHAFT", subtitle = "How deep can you go?", root = false,
        lines = {"An endless descent. Monsters grow with every floor.", "Every tenth floor, a guardian; then a pact,",
                 "a harder rule that pays, and a new stratum.", string.format("Deepest: floor %d", records.shaft_deepest or 0),
                 "Party: " .. setting("shaft_party", "Everyone") .. " (Mod Manager settings)"},
        entries = {{id = "shaft_start", label = "Descend"}}})
  elseif name == "boss_rush" then
    try(game.title.mode_set, {id = MODE, title = "BOSS RUSH", subtitle = "Every story boss, one after another", root = false,
        lines = {"Seven fights in one sealed arena, in the story's order.", "The party grows to each boss's place in the story.",
                 "Between fights, choose a boon.", best_line(),
                 "Party: " .. setting("rush_party", "Everyone") .. " (Mod Manager settings)"},
        entries = {{id = "rush_start", label = "Begin"}}})
  end
  message = nil
end

try(game.title.mode_register, {id = MODE, label = "Challenges", title = "CHALLENGES", subtitle = "Tests for a seasoned adventurer",
    lines = {"Choose a challenge."}, root = true, entries = {{id = "boss_rush", label = "Boss Rush", enabled = arena ~= nil}}})

local function start_rush()
  if not arena then message = "Boss Rush has no arena floor this session."; show("root"); return end
  rush = {stage = 1, frames = 0, whet = 1, live = false}
  -- a small floor: the arena room is the point
  try(game.dungeons.set_layout, {rooms = 3, area = 14, room_min = 3, room_max = 4})
  local everyone = setting("rush_party", "Everyone") == "Everyone"
  local ok, err = try(game.session.start, {floor = arena, party_size = everyone and 6 or 1, character = "toan"})
  if not ok then
    rush = nil
    rush_cleanup()
    message = ("Boss Rush could not start: " .. errmsg(err)):sub(1, 64)
    show("root")
    return
  end
  records.runs = (records.runs or 0) + 1
  save_records()
end

moonmod.on("game.title.opened", function() show("root") end)
moonmod.on("game.title.selected", function(e)
  local entry = e and e.entry
  if entry == "back" then
    if page ~= "root" then show("root") end
    return
  end
  if entry == "boss_rush" then show("boss_rush")
  elseif entry == "rush_start" then start_rush()
  elseif entry == "shaft" then show("shaft")
  elseif entry == "shaft_start" then start_shaft() end
end)

-- Sessions -----------------------------------------------------------------------------------------------------------
moonmod.on("game.session.started", function(e)
  session_owner = e and e.owner or "?"
  tracked, floor_token = {}, nil
  remove_bar()
  if session_owner == ID and rush then
    rush.live = true
    apply_tier()
    heal_party(1)
  elseif session_owner == ID and shaft then
    shaft.live = true
    -- the gate always leads down and the Escape menu is refused: the run menu ends a descent
    try(game.dungeons.set_exits, {town = "shrines"})
    shaft_tuning()
    shaft_heal()
    try(game.items.give, {id = "chronicle:item:" .. ITEM.bread, count = 3})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.water, count = 2})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.repair, count = 2})
  end
end)

moonmod.on("game.session.ended", function(e)
  local mine = e and e.owner == ID
  session_owner = nil
  if mine and rush then
    if not rush.won then finish_records(false) end
    rush = nil
    rush_cleanup()
  end
  if mine and shaft then
    shaft_records()
    shaft = nil
    shaft_cleanup()
  end
  tracked, floor_token = {}, nil
  remove_bar()
end)

do
  local s = try(game.session.get)
  if type(s) == "table" and s.kind == "sandbox" then session_owner = s.owner or "?" end
end

-- Tick ---------------------------------------------------------------------------------------------------------------
moonmod.on("game.tick", function()
  frame = frame + 1
  if rush then rush_tick() end
  if shaft then shaft_tick() end
  if other_session() then return end
  local world = try(game.world.get)
  if not (world and world.context == "dungeon") then
    if floor_token then tracked, floor_token = {}, nil; remove_bar() end
    return
  end
  local token = tostring(world.dungeon_id) .. ":" .. tostring(world.floor_id) .. ":" .. tostring(world.floor_seed)
  if token ~= floor_token then tracked, floor_token = {}, token; remove_bar() end
  if frame % 10 == 0 then watch_bosses() end
end)

moonmod.log("info", "Challenges ready" .. (arena and "" or " (Boss Rush unavailable: no arena floor)"))
