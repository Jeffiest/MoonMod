-- Challenges: boss fights worth the name, and challenge modes under one title-menu row.
--
-- Boss phases (story game and Boss Rush): a story boss in sight gets a name card, an HP bar (along the bottom with its
-- name; top left with the game's other bars on an engine without the boss bar) and two more phases. Below `enraged_at` it is enraged: it hits harder, takes a little less, glows red
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
local boss_bar = true   -- false once the engine has refused render.bar_register's boss flag (an older engine)
local rush = nil       -- the Boss Rush run, while one is going (below)
local seda = nil       -- Seda's Chronicle, while it is being played (below)
local seda_generating  -- its floor setup (below)
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
    local bar = {id = "boss", label = main.name:upper():sub(1, 24), current = clamp(main.cur, 0, main.max), max = main.max}
    if boss_bar then
      bar.boss = true
      if not try(game.render.bar_register, bar) then boss_bar, bar.boss = false, nil end
    end
    if not boss_bar then try(game.render.bar_register, bar) end
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

-- A story boss and its cast at `at`, its arena's centre, with `life` times its native life (and the Genie's
-- footing). Returns its handle, or nil while the floor can't place it yet.
local function spawn_boss(model, at, life)
  local def = BOSS[model]
  local s = try(game.characters.spawn, {character = variant(model, def.name), position = at, arena_origin = at,
                                        grounded = def.grounded, arena_slot = 0})
  local handle = s and (s.entity_handle or s.id)
  if not handle then return false end -- the floor isn't ready to place it: asked again next tick
  local base = s.stats and tonumber(s.stats.hp) or 1000
  local hp = math.floor(clamp(base * (def.hp or 1) * life, 1, 1000000))
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
  return handle
end

local function spawn_stage()
  local model = RUSH_ORDER[rush.stage]
  local def = BOSS[model]
  apply_tier()
  local handle = spawn_boss(model, rush.center, setting("rush_life", 100) / 100)
  if not handle then return false end -- the floor isn't ready to place it: asked again next tick
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
  -- The Boss Rush arena and the Genie's lair hold nothing but their room: no walk to find it, the player is put in
  -- the middle of it as it opens, and walking in shuts its doors as before.
  local arena_floor = (rush and rush.live and not rush.center) or (seda and seda.live and seda.arena and not seda.room)
  if arena_floor and e and e.state == "open" and type(e.center) == "table" then
    try(game.dungeons.warp, {x = math.floor((tonumber(e.center.x) or 0) / 160 + 0.5), y = math.floor((tonumber(e.center.z) or 0) / 160 + 0.5)})
    return
  end
  if seda and seda.live and e and e.state == "entered" and type(e.center) == "table" and not seda.room then
    seda.room = {x = tonumber(e.center.x) or 0, y = tonumber(e.center.y) or 0, z = tonumber(e.center.z) or 0}
    return
  end
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
  elseif seda and e then
    seda_generating(e)
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
  try(game.render.floor_label_set, {text = tostring(math.min(shaft.depth, 999999)), number = clamp(shaft.depth, 1, 99)})
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
  if seda and seda.live and e and e.row == "end" then try(game.ui.run_menu_close); seda.finish_at = frame + 10; return end
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
  try(game.render.floor_label_clear)
  try(game.dungeons.set_warden_room, {enabled = false})
  try(game.dungeons.set_modifiers, {})
  try(game.dungeons.set_exits, {})
  try(game.player.tuning_clear)
  try(game.combat.register_formula, {id = "shaft_power", operation = "multiply", priority = 60, value = 1})
  try(game.ui.run_menu_clear)
end

-- Seda's Chronicle -----------------------------------------------------------------------------------------------------
-- A prologue, four hundred years before the game: Seda, a swordsman, goes down after the Dark Genie. Four chapters on
-- floors the other modes already hold (the Shaft's three and the Boss Rush arena), so it takes no floor slot of its
-- own. Each chapter opens with a card and a page of story, sets a task, and closes with another page.
--
-- Seda himself is a playable character once his pack is built (docs/SEDA_PLAN.md). The Gauntlet registers him, right
-- after Opar so their engine indices stay 6 and 7 (one mod owns an id), and the Chronicle plays him when he is there.
-- Until then Toan walks in his place.
local function seda_floor(dungeon)
  for _, f in ipairs(shaft_floors) do if f.dungeon == dungeon then return f.id end end
end
local CHAPTERS = {
  {key = "cave", dungeon = 0, title = "THE MOONLIT CAVE", kicker = "CHAPTER I", goal = "kill", count = 12,
   intro = {"Four hundred years ago. The Dark Genie's shadow", "lies over the land, and its creatures crawl", "up from the deep places.",
            "Seda, a swordsman with nothing left to lose,", "goes down into the cave beneath the village."},
   task = "Cut down twelve of the Genie's creatures.",
   outro = {"The creatures thin. Deeper in, the stone hums", "with a moonlit voice: the Genie hides where", "the old forest grows over the ruins."}},
  {key = "forest", dungeon = 1, title = "THE WISE OWL'S WOOD", kicker = "CHAPTER II", goal = "chests", count = 3,
   intro = {"The owls of the forest keep the old sayings.", "One of them is a warning: the Genie cannot be", "struck down by any blade of this world.",
            "But the forest remembers three relics", "of the Moon People, hidden in its roots."},
   task = "Find three relics in the forest's chests.",
   outro = {"Three relics, and in each a shard of moonlight.", "Bound to Seda's sword they burn cold and blue.", "The owls fall silent. They know where he goes."}},
  {key = "sea", dungeon = 4, title = "THE MOON SEA", kicker = "CHAPTER III", goal = "guardian",
   intro = {"Under the dry sea floor the Genie's gate is", "guarded by a beast grown fat on its darkness.",
            "Clear the way, and the sealed room will open."},
   task = "Clear the floor, then fell the guardian of the gate.",
   outro = {"The guardian falls, and the gate stands open.", "Beyond it the air is thick and warm,", "and something laughs in the dark."}},
  {key = "lair", arena = true, title = "THE GENIE'S LAIR", kicker = "CHAPTER IV", goal = "genie",
   intro = {"The Dark Genie waits, as if it had been", "expecting him. It always has been.", "Seda raises the moonlit sword."},
   task = "Defeat the Dark Genie.",
   outro = {}},
}
local EPILOGUE = {
  {"The Genie's body breaks apart in the moonlight.", "For a moment, there is only silence."},
  {"Then the darkness laughs again. Its body is", "gone, but the Genie itself cannot die by a blade.", "It sinks into the earth to wait."},
  {"Seda's sword is shattered. The curse of the", "Genie's last breath is on him: he will not rest", "while the Genie lives."},
  {"He will wait in the cave, four hundred years,", "for someone who carries the Atlamillia.", "For a boy from Norune."},
}

local CARD_WIDTH = 34 -- characters a story card's line holds before it wraps on its own
local function reflow(lines)
  local out, line = {}, ""
  for word in table.concat(lines, " "):gmatch("%S+") do
    if line ~= "" and #line + 1 + #word > CARD_WIDTH then out[#out + 1], line = line, word
    else line = line == "" and word or (line .. " " .. word) end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end

local function seda_page(title, subtitle, lines, label)
  seda.page = true
  try(game.ui.choice_open, {id = "seda_story", title = title, subtitle = subtitle,
      options = {{title = label or "Onward", lines = reflow(lines)}}})
end

local function seda_chapter() return CHAPTERS[seda.chapter] end

local function seda_menu()
  local c = seda_chapter()
  local progress = c.count and string.format(" (%d of %d)", math.min(seda.progress, c.count), c.count) or ""
  try(game.ui.run_menu_set, {title = "SEDA'S CHRONICLE", tabs = {{id = "chronicle", title = "Chronicle",
      lines = {c.kicker .. ": " .. c.title, c.task .. progress, seda.hero == "seda" and "Seda walks." or "Toan walks in Seda's place."},
      rows = {{id = "end", label = "Leave the Chronicle", detail = "Back to the title. The chapters you finished are kept."}}}}})
end

local function seda_open_chapter()
  local c = seda_chapter()
  seda.progress, seda.done, seda.room, seda.boss, seda.boss_alive, seda.toughest, seda.genie = 0, false, nil, nil, false, nil, nil
  try(game.ui.boss_card, {kicker = c.kicker, name = c.title, epithet = "Seda's Chronicle", frames = 150})
  seda.story_at = frame + 160
  seda_menu()
end

local function seda_chapter_done()
  if seda.done then return end
  seda.done = true
  local c = seda_chapter()
  records.seda_chapter = math.max(records.seda_chapter or 0, seda.chapter)
  save_records()
  if c.goal == "genie" then
    seda.epilogue = 1
    seda_page("EPILOGUE", "Four hundred years ago", EPILOGUE[1])
    return
  end
  seda.leaving = true
  seda_page(c.kicker .. " ENDS", c.title, c.outro)
end

local function seda_spawn_genie(model)
  local h = spawn_boss(model, seda.room, 0.6)
  if not h then return false end
  seda.boss, seda.boss_alive, seda.genie = h, false, model
  try(game.ui.boss_card, {kicker = "SEDA'S CHRONICLE", name = BOSS[model].name, epithet = BOSS[model].epithet, frames = 150})
  return true
end

local function seda_tick()
  if not seda.live then return end
  if seda.story_at and frame >= seda.story_at then
    seda.story_at = nil
    local c = seda_chapter()
    seda_page(c.kicker, c.title, c.intro, "Begin")
  end
  if seda.next_at and frame >= seda.next_at then
    local c = seda_chapter()
    local id = c.arena and arena or seda_floor(c.dungeon)
    if id and try(game.world.transition, {id = id}) then seda.next_at = nil else seda.next_at = frame + 90 end
  end
  if seda.finish_at and frame >= seda.finish_at then seda.finish_at = nil; try(game.session.finish) end
  local c = seda_chapter()
  if c.goal == "guardian" and seda.room and not seda.boss and not seda.done then
    local t = seda.toughest
    if not t then seda_chapter_done()
    else
      local s = try(game.characters.spawn, {character = variant(t.model, "Gate Guardian"), position = seda.room})
      local h = s and (s.entity_handle or s.id)
      if h then
        local hp = math.floor(clamp(t.hp * 8, 1, 1000000))
        try(game.entities.set_stats, {entity = h, max_hp = hp, hp = hp, damage_scale = 1.5})
        try(game.entities.scale_set, {entity = h, scale = 1.9})
        seda.boss, seda.boss_alive = h, false
        try(game.ui.boss_card, {kicker = "CHAPTER III", name = "Guardian of the Gate", epithet = "Fat on the Genie's darkness", frames = 150})
      end
    end
  end
  if c.goal == "genie" and seda.room and not seda.boss and not seda.done then seda_spawn_genie(seda.genie_next or 84) end
  if seda.boss then
    local e = try(game.entities.get, seda.boss)
    if e and e.status == "alive" then seda.boss_alive = true
    elseif seda.boss_alive or (e and e.status == "dead") then
      seda.boss = nil
      if c.goal == "genie" and seda.genie == 84 then
        notify("The Genie's body bursts... and darkness itself rises!")
        seda.genie_next, seda.room_hold = 106, seda.room
        seda.room = nil
        seda.rise_at = frame + 150
      else
        seda_chapter_done()
      end
    end
  end
  if seda.rise_at and frame >= seda.rise_at then seda.rise_at, seda.room = nil, seda.room_hold end
  -- the guardian grows from the floor's toughest monster
  if c.goal == "guardian" and frame % 20 == 0 then
    local q = try(game.entities.query, {type = "monster"})
    for _, e in ipairs(q and q.entities or {}) do
      local model, max = tonumber(e.native_model_id), e.health and tonumber(e.health.maximum) or 0
      if model and not BOSS[model] and tostring(e.entity_id or e.id) ~= tostring(seda.boss) and
         (not seda.toughest or max > seda.toughest.hp) then seda.toughest = {model = model, hp = max} end
    end
  end
end

seda_generating = function(e)
  if e.back_floor or e.prebuild then return end
  if seda.opening then seda.opening = false; seda_open_chapter() end
  local c = seda_chapter()
  seda.arena = c.arena
  try(game.dungeons.set_modifiers, c.arena and {chests = -100} or (c.goal == "chests" and {chests = 60} or {}))
  try(game.dungeons.set_warden_room, {enabled = c.goal == "guardian" or c.goal == "genie", lock_in = true})
  -- a figure by the exit gate tells the chapter's task again
  if not c.arena then try(game.world.dungeon_npc_set, {id = "wanderer", model = "gedit/e01/chara/p02a.chr", place = "exit"}) end
end

-- Seda's engine index when another mod has registered him, else nil.
local function seda_hero()
  local r = try(game.characters.get, {id = "seda"})
  return type(r) == "table" and tonumber(r.character_id) or nil
end

local function start_seda()
  local first = seda_floor(0)
  if not first then message = "Seda's Chronicle needs the Shaft's floors."; show("root"); return end
  local index = seda_hero()
  seda = {chapter = 1, live = false, hero = index and "seda" or "toan"}
  local ok, err = try(game.session.start, {floor = first, party_size = index and (index + 1) or 1, character = "toan"})
  if not ok then
    seda = nil
    message = ("The Chronicle could not start: " .. errmsg(err)):sub(1, 64)
    show("root")
    return
  end
end

local function seda_cleanup()
  try(game.dungeons.set_warden_room, {enabled = false})
  try(game.dungeons.set_modifiers, {})
  try(game.dungeons.set_exits, {})
  try(game.world.dungeon_npc_clear)
  try(game.combat.register_formula, {id = "seda_power", operation = "multiply", priority = 60, value = 1})
  try(game.ui.run_menu_clear)
end

moonmod.on("game.enemy_defeated", function()
  if not (seda and seda.live) or seda.done or seda_chapter().goal ~= "kill" then return end
  seda.progress = seda.progress + 1
  if seda.progress >= seda_chapter().count then seda_chapter_done() else seda_menu() end
end)

moonmod.on("game.chest.opened", function(e)
  if not (seda and seda.live) or seda.done or seda_chapter().goal ~= "chests" or not e or e.chest == nil then return end
  seda.progress = seda.progress + 1
  notify(string.format("A relic of the Moon People (%d of 3).", math.min(seda.progress, 3)))
  if seda.progress >= seda_chapter().count then seda_chapter_done() else seda_menu() end
end)

moonmod.on("game.dungeon_npc.near", function(e)
  if not (seda and seda.live) or not e or e.id ~= "wanderer" then return end
  notify("A wanderer: \"" .. seda_chapter().task .. "\"")
end)

moonmod.on("ui.choice_made", function(e)
  if not (seda and seda.page and e and e.id == "seda_story") then return end
  seda.page = false
  if seda.epilogue then
    seda.epilogue = seda.epilogue + 1
    if EPILOGUE[seda.epilogue] then seda_page("EPILOGUE", "Four hundred years ago", EPILOGUE[seda.epilogue])
    else
      records.seda_clears = (records.seda_clears or 0) + 1
      save_records()
      try(game.ui.boss_card, {kicker = "SEDA'S CHRONICLE", name = "The End", epithet = "Dark Cloud begins", frames = 240})
      seda.finish_at = frame + 260
    end
    return
  end
  if seda.leaving then
    seda.leaving = false
    seda.chapter = seda.chapter + 1
    seda.next_at = frame + 30
    seda.opening = true -- the chapter opens on its own floor
  end
end)

-- Seda in the story: once his Chronicle has been seen to the end, he can join a story party (a Mod Manager action).
-- He comes with a Dagger in hand, as the story's own joins come with a first weapon.
try(game.ui.register, {id = "seda_join", label = "Seda Joins the Party",
    description = "After Seda's Chronicle: Seda joins your story party, fighting with Toan's swords"})
moonmod.on("ui.action", function(a)
  if not a or a.id ~= "seda_join" then return end
  if (records.seda_clears or 0) == 0 then notify("See Seda's Chronicle to its end first (title menu > Challenges)."); return end
  if session_owner then notify("Seda joins a story game, not a challenge run."); return end
  if not seda_hero() then notify("Seda can't join yet: his model isn't installed."); return end
  local r, err = try(game.party.join, {character = "seda"})
  if not r then notify("Seda can't join now: " .. errmsg(err)); return end
  if r.changed then try(game.weapons.give, {id = "chronicle:weapon:258", character = "seda"}) end
  notify(r.changed and "Seda joins the party. Four hundred years, and he fights again." or "Seda is already in the party.")
end)

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
                   {id = "shaft", label = "The Shaft", enabled = #shaft_floors > 0},
                   {id = "seda", label = "Seda's Chronicle", enabled = #shaft_floors > 0 and arena ~= nil}}})
  elseif name == "seda" then
    try(game.title.mode_set, {id = MODE, title = "SEDA'S CHRONICLE", subtitle = "Four hundred years before Dark Cloud", root = false,
        lines = {"A swordsman goes down after the Dark Genie.", "Four chapters, from the cave to the Genie's lair.",
                 string.format("Chapters finished: %d of 4%s", records.seda_chapter or 0, (records.seda_clears or 0) > 0 and ", the end seen" or ""),
                 seda_hero() and "Seda walks it." or "Toan stands in for Seda."},
        entries = {{id = "seda_start", label = "Begin the Chronicle"}}})
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
  elseif entry == "shaft_start" then start_shaft()
  elseif entry == "seda" then show("seda")
  elseif entry == "seda_start" then start_seda() end
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
  elseif session_owner == ID and seda then
    seda.live = true
    try(game.dungeons.set_exits, {town = "shrines"})
    if seda.hero == "seda" then try(game.party.set_active, {id = "seda"}) end
    -- Seda is a veteran: a strong blade and a deep well of life from the start
    try(game.combat.register_formula, {id = "seda_power", operation = "multiply", priority = 60, value = 3})
    for _, c in ipairs(members()) do try(game.player.set, {max_hp = 220, character = c}); try(game.player.heal, {amount = 999, character = c}) end
    try(game.items.give, {id = "chronicle:item:" .. ITEM.bread, count = 4})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.water, count = 3})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.repair, count = 3})
    seda_open_chapter()
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
  if mine and seda then
    seda = nil
    seda_cleanup()
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
  if seda then seda_tick() end
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
