-- The live co-op test's driver (tools/tests/coop/live/run_live.py): plays one game from the script the harness puts
-- under storage "script", a list of steps done in turn. A step waits for its `when` (see ready() below) and then
-- `after` more frames, then does its `op`. Every step logs "DRIVE step <n> <op> ok|<error>", and once a second the
-- driver logs "DRIVE state ..." (where the player is, the monsters on the floor), which the harness reads.

local script = moonmod.storage.get("script")
if type(script) ~= "table" then script = {} end

local frame, at, since = 0, 1, nil
local last_query_error
local playing_for = 0

local function try(fn, ...)
  if type(fn) ~= "function" then return nil, "unsupported" end
  local ok, value, err = pcall(fn, ...)
  if not ok then return nil, tostring(value) end
  if value == nil and err ~= nil then return nil, type(err) == "table" and tostring(err.message or err.code) or tostring(err) end
  return value
end
local function log(text) moonmod.log("info", "DRIVE " .. text) end

local function monsters()
  local got, err = try(game.entities.query, {type = "monster"})
  if not got and err ~= last_query_error then
    last_query_error = err
    log("entities.query failed " .. tostring(err))
  end
  local list = type(got) == "table" and got.entities or {}
  local alive, hp = 0, 0
  for _, m in ipairs(list) do
    m.hp = type(m.health) == "table" and m.health.current or m.hp
    if (m.hp or 0) > 0 then alive = alive + 1; hp = hp + (m.hp or 0) end
  end
  return list, alive, hp
end

local function ready(step)
  local when = step.when
  if when == nil then return true end
  local w = try(game.world.get) or {}
  local s = try(game.session.get) or {}
  if when == "visit" then return s.kind == "visit" end
  if when == "dungeon" then return w.context == "dungeon" end
  -- playing on a floor (its walk-in over), where the engine says so
  if when == "playing" then
    -- steadily: a floor still loading can say so for a frame
    if w.context == "dungeon" and w.walking == true then playing_for = playing_for + 1 else playing_for = 0 end
    return playing_for >= 60
  end
  if when == "town" then return w.context ~= "dungeon" and (w.town_map ~= nil or w.map_no ~= nil) end
  if when == "walking" then return w.context == "dungeon" or w.walking == true end
  if when == "monster" then
    if w.context ~= "dungeon" then return false end
    local _, alive = monsters()
    return alive > 0
  end
  return true
end

-- Chronicle Two: a foe the test can put beside the player (characters.spawn), a sewer rat in all but name and
-- strength, for the scenario where a monster's blow has to land (a floor's own monsters may never come).
local foe = nil
do
  local info = try(game.info and game.info.get)
  if type(info) == "table" and info.id == "chronicle-two" then
    -- (how hard it hits is a scenario's to say: the first spawn_foe step's `attack`)
    local attack = 6
    for _, step in ipairs(script) do
      if type(step) == "table" and step.op == "spawn_foe" and step.attack then attack = step.attack break end
    end
    local made, err = try(game.characters and game.characters.register,
                          {id = "live-foe", name = "Live Foe", kind = "enemy", template_monster_id = 0, stats = {hp = 100000, attack = attack}})
    foe = type(made) == "table" and made.id or nil
    if not foe then log("foe not registered: " .. tostring(err)) end
  end
end

-- Chronicle Two: a Georama part of the test's own, made from one of a town's parts (a step's `template`, with its
-- `town`), so a game can place a part without its editor (georama.place). Both games register it, as both must
-- know a part one of them places; it is registered here, before any town loads, since a town takes its parts in
-- as it loads.
local parts = {} -- template -> the registered part's id
for _, step in ipairs(script) do
  if type(step) == "table" and step.template and not parts[step.template] then
    local made, err = try(game.georama and game.georama.register,
                          {id = "live-part-" .. step.template, name = "Live Part " .. step.template, template_part_id = step.template,
                           town_id = step.town or 0, stock = step.stock or 5})
    parts[step.template] = type(made) == "table" and made.id or nil
    log(parts[step.template] and ("part registered " .. tostring(made.id)) or ("part not registered: " .. tostring(err)))
  end
end

local OPS = {}
-- The test's part put down around the player, on each of four sides (so one stands where the other game's camera
-- looks, wherever that is): on each side the first distance the town's own placement rules take.
function OPS.part_place(step)
  local part = parts[step.template or 0]
  if not part then return nil, "no part registered" end
  local p = try(game.player.get) or {}
  if not p.position then return nil, "the player has no position" end
  -- (around the player, or around a spot the scenario names: a town's way in is not ground to build on)
  local cx, cz = step.at and step.at[1] or p.position.x, step.at and step.at[2] or p.position.z
  -- A part rests on another's floor, at that floor's height: the widest floor the town has standing (its ground).
  local town = try(game.georama.get, {town_id = step.town or 0}) or {}
  local ground = nil
  for _, a in ipairs(town.placement_anchors or {}) do
    if not ground or (a.floor_area or 0) > (ground.floor_area or 0) then ground = a end
  end
  local height = ground and ground.surface_y or p.position.y
  log(string.format("part ground=%s surface_y=%s", tostring(ground and ground.name), tostring(ground and ground.surface_y)))
  local placed_n, last = 0, nil
  -- (a scenario that knows the town names its spots: {x, z} each, every one tried)
  for _, spot in ipairs(step.spots or {}) do
    local placed, err = try(game.georama.place, {id = part, position = {x = spot[1], y = height, z = spot[2]}, rotation_steps = spot[3] or 0})
    if type(placed) == "table" then
      placed_n = placed_n + 1
      log(string.format("part placed at %.0f,%.0f,%.0f", placed.position.x, placed.position.y, placed.position.z))
    else
      last = err
    end
  end
  for turn = 0, step.spots and -1 or 3 do
    local angle = turn * math.pi / 2
    for _, r in ipairs(step.radii or {140, 200, 280, 360}) do
      local at = {x = cx + r * math.cos(angle), y = height, z = cz + r * math.sin(angle)}
      local placed, err = try(game.georama.place, {id = part, position = at, rotation_steps = 0})
      if type(placed) == "table" then
        placed_n = placed_n + 1
        log(string.format("part placed at %.0f,%.0f,%.0f (player at %.0f,%.0f,%.0f)", placed.position.x, placed.position.y,
            placed.position.z, p.position.x, p.position.y, p.position.z))
        break
      end
      last = err
    end
  end
  if placed_n == 0 then return nil, "no spot took the part: " .. tostring(last) end
  return true
end
function OPS.spawn_foe(step)
  if not foe then return nil, "no foe registered" end
  local p = try(game.player.get) or {}
  if not p.position then return nil, "the player has no position" end
  return try(game.characters.spawn, {character = foe, position = {x = p.position.x + (step.dx or 40), y = p.position.y,
                                                                    z = p.position.z + (step.dz or 0)}})
end
function OPS.transition(step) return try(game.world.transition, {id = step.id}) end
function OPS.enter_map(step) return try(game.world.enter_map, {map_no = step.map_no}) end
function OPS.enter_floor(step)
  return try(game.dungeons.enter_floor, {dungeon_id = step.dungeon_id, floor_id = step.floor_id or 0})
end
function OPS.warp(step) return try(game.dungeons.warp, {x = step.x, y = step.y}) end
function OPS.strike(step)
  -- the nearest living monster takes `amount`
  local list = monsters()
  local p = try(game.player.get) or {}
  local best, dist
  for _, m in ipairs(list) do
    if (m.hp or 0) > 0 and m.position and p.position then
      local d = math.abs(m.position.x - p.position.x) + math.abs(m.position.z - p.position.z)
      if not dist or d < dist then best, dist = m, d end
    elseif (m.hp or 0) > 0 and not m.position and not best then
      best = m -- an engine that says no positions (Chronicle Two): the first living one
    end
  end
  if not best then return nil, "no monster" end
  return try(game.combat.damage, {entity = best.entity_id or best.id, amount = step.amount or 1000000})
end
-- Every living monster on the floor struck down (the live test of a floor cleared for both).
function OPS.strike_all(step)
  local n = 0
  for _, m in ipairs((monsters())) do
    if (m.hp or 0) > 0 and try(game.combat.damage, {entity = m.entity_id or m.id, amount = step.amount or 1000000}) then n = n + 1 end
  end
  log("struck down " .. n)
  return n > 0 or nil, "no monster"
end
-- A save's text far over the 64 KiB of a plain operation goes in and comes back whole (the limit lifted for the
-- operations that carry a world or a player's things).
function OPS.big_text(step)
  local tag = step.tag or "DCP1"
  local data = tag .. string.rep("QUJD", math.floor((step.size or 240000) / 4))
  local kept, err = try(game.save.account_set, {id = "live-big-text", name = "Big", data = data})
  if not kept then return nil, "account_set " .. tostring(err) end
  local got, get_err = try(game.save.account_get, {id = "live-big-text"})
  try(game.save.account_remove, {id = "live-big-text"})
  if type(got) ~= "table" or got.data ~= data then
    return nil, "account_get " .. tostring(get_err or (type(got) == "table" and #tostring(got.data or "")) or "nothing")
  end
  return true
end
-- The player gains Gilda (the live test of a joiner's own save: what changes in a visit goes back into it).
function OPS.gilda(step) return try(game.economy and game.economy.add, {amount = step.amount or 100}) end
-- A story flag set as the game's own scripts set one, and read back (the live test of the shared world).
function OPS.flag_set(step) return try(game.world.story_flag_set, {id = step.id, value = step.value ~= false}) end
function OPS.flag_log(step)
  local got, err = try(game.world.story_flag_get, {id = step.id})
  if type(got) ~= "table" then return nil, err end
  log(string.format("flag %d is %s", step.id, tostring(got.value)))
  return true
end
-- A town's Georama changed as the game changes it out of the editor (an analysis condition met), and a number for
-- the town as it stands (the live test of a town going from one game to the other).
function OPS.condition_set(step)
  return try(game.georama.condition_set, {town_id = step.town, condition_id = step.id, met = step.met ~= false})
end
function OPS.town_log(step)
  local got, err = try(game.georama.town_export, {town_id = step.town})
  if type(got) ~= "table" or type(got.data) ~= "string" then return nil, err end
  local sum = 0
  for i = 1, #got.data do sum = (sum * 31 + got.data:byte(i)) % 2147483647 end
  log(string.format("town %d is %d (%d chars)", step.town, sum, #got.data))
  return true
end
-- What a town's Georama offers and holds (a look for writing a scenario: the parts a mod's part can be made from,
-- the mod's own parts as this town has them, what is placed).
local function flat(t)
  local parts = {}
  for k, v in pairs(t) do
    if type(v) ~= "table" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
  end
  table.sort(parts)
  return table.concat(parts, " ")
end
function OPS.georama_probe(step)
  local got, err = try(game.georama.get, {town_id = step.town or 0})
  if type(got) ~= "table" then return nil, err end
  local p = try(game.player.get) or {}
  local w = try(game.world.get) or {}
  log(string.format("georama town=%d placed=%d standing=%s anchors=%d templates=%d pos=%s", step.town or 0, #(got.placed_parts or {}),
      tostring(w.georama_live_parts), #(got.placement_anchors or {}), #(got.native_piece_templates or {}),
      p.position and string.format("%.0f,%.0f,%.0f", p.position.x, p.position.y, p.position.z) or "-"))
  if step.list then
    for _, t in ipairs(got.native_piece_templates or {}) do log("georama template " .. flat(t)) end
    for _, a in ipairs(got.placement_anchors or {}) do
      local f = a.footprint or {}
      log(string.format("georama anchor %s at %.0f,%.0f,%.0f area=%.0f x %.0f..%.0f z %.0f..%.0f", tostring(a.name), a.position.x, a.position.y,
          a.position.z, a.floor_area or 0, f.min_x or 0, f.max_x or 0, f.min_z or 0, f.max_z or 0))
    end
  end
  for _, m in ipairs(got.mod_pieces or {}) do
    log("georama mod piece " .. flat(m) .. (type(m.extras) == "table" and (" extras: " .. flat(m.extras)) or ""))
  end
  return true
end
function OPS.leave() return try(game.session.finish) end
function OPS.mark(step) return true end
-- The ridepod's fuel (a ridepod the Core has just brought has none, and an empty one cannot be climbed into).
function OPS.ridepod_fuel(step)
  return try(game.player.ridepod_set, {max_fuel = step.amount or 300, fuel = step.amount or 300})
end
-- Who plays, who is in the party and what the ridepod is made of (scenarios that change shape: ridepod).
function OPS.player_log(step)
  local p = try(game.player.get) or {}
  local ids = {}
  for _, m in ipairs(try(game.party.list) or {}) do ids[#ids + 1] = tostring(m.id) end
  local r = try(game.player.ridepod_get) or {}
  local parts = type(r.parts) == "table" and r.parts or {}
  local function no(part) return type(part) == "table" and tostring(part.item_no) or "-" end
  log(string.format("player character=%s party=%s ridepod=%s,%s,%s,%s fuel=%s/%s", tostring(p.character), table.concat(ids, ","),
    no(parts.leg), no(parts.arm), no(parts.body), no(parts.battery), tostring(r.fuel), tostring(r.max_fuel)))
  return true
end

moonmod.on("game.tick", function(e)
  frame = e and e.frame or frame + 1
  if frame % 60 == 0 then
    local w = try(game.world.get) or {}
    local p = try(game.player.get) or {}
    local s = try(game.session.get) or {}
    local _, alive, hp = monsters()
    local pos = p.position and string.format("%.0f,%.0f,%.0f", p.position.x, p.position.y, p.position.z) or "-"
    -- (counted, mimics, cleared: the floor's clear as the game itself decides it, where the engine says so)
    log(string.format("state frame=%d session=%s context=%s dungeon=%s floor=%s seed=%s layout=%s walking=%s town=%s map=%s pos=%s monsters=%d hp=%d counted=%s mimics=%s cleared=%s step=%d character=%s",
      frame, tostring(s.kind), tostring(w.context), tostring(w.dungeon_id), tostring(w.floor_id), tostring(w.floor_seed), tostring(w.floor_layout), tostring(w.walking), tostring(w.town_map),
      tostring(w.map_no), pos, alive, hp, tostring(w.monsters_counted), tostring(w.mimic_chests), tostring(w.floor_cleared), at, tostring(p.character)))
  end
  if frame == 300 then
    local w, werr = try(game.world.get)
    if not w then log("world.get failed " .. tostring(werr)) end
    w = w or {}
    local keys = {}
    for k, v in pairs(w) do if type(v) ~= "table" then keys[#keys + 1] = k .. "=" .. tostring(v) end end
    table.sort(keys)
    log("world " .. table.concat(keys, " "))
  end
  local step = script[at]
  if not step then return end
  if not since then
    if not ready(step) then return end
    since = frame
  end
  if frame - since < (step.after or 0) then return end
  local ok, err
  if OPS[step.op] then ok, err = OPS[step.op](step) else err = "no such op" end
  log(string.format("step %d %s %s%s", at, tostring(step.op), ok and "ok" or ("failed " .. tostring(err)), step.text and (" " .. step.text) or ""))
  at, since, playing_for = at + 1, nil, 0
  if not script[at] then log("done") end
end)

log("loaded, " .. #script .. " steps")
