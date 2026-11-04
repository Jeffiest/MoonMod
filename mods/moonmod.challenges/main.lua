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
-- The title menu has room for two mod rows (each pushes the copyright banner down), and the Gauntlet holds one, so
-- every challenge mode lives on this one row's pages.

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
for dungeon = 0, 4 do
  -- Each dungeon holds 25 floors at most and other mods add their own, so the arena goes where there is room.
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
  if not (rush and rush.live) or rush.center or not e then return end
  if e.state == "entered" and type(e.center) == "table" then
    rush.center = {x = tonumber(e.center.x) or 0, y = tonumber(e.center.y) or 0, z = tonumber(e.center.z) or 0}
    rush.next_at = frame + 60
  end
end)

moonmod.on("game.dungeon.generating", function()
  if not rush then return end
  try(game.dungeons.set_modifiers, {chests = -100})
  try(game.dungeons.set_warden_room, {enabled = true, lock_in = true})
end)

local function rush_cleanup()
  try(game.dungeons.set_warden_room, {enabled = false})
  try(game.dungeons.set_modifiers, {})
  try(game.dungeons.set_layout, {})
  try(game.combat.register_formula, {id = "rush_power", operation = "multiply", priority = 60, value = 1})
  remove_bar()
end

-- Title pages --------------------------------------------------------------------------------------------------------
local page = "root"
local function best_line()
  if records.best then return string.format("Best time %s, %d clear%s", clock(records.best), records.clears, records.clears == 1 and "" or "s") end
  if (records.furthest or 0) > 0 then return string.format("Furthest: %d of %d bosses", records.furthest, #RUSH_ORDER) end
  return "Not yet cleared"
end

local message = nil
local function show(name)
  page = name
  if name == "root" then
    try(game.title.mode_set, {id = MODE, title = "CHALLENGES", subtitle = "Tests for a seasoned adventurer",
        lines = {message or "Choose a challenge."}, root = true,
        entries = {{id = "boss_rush", label = "Boss Rush", enabled = arena ~= nil}}})
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
  elseif entry == "rush_start" then start_rush() end
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
