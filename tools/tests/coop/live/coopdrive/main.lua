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

local OPS = {}
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
    end
  end
  if not best then return nil, "no monster" end
  return try(game.combat.damage, {entity = best.entity_id, amount = step.amount or 1000000})
end
function OPS.leave() return try(game.session.finish) end
function OPS.mark(step) return true end

moonmod.on("game.tick", function(e)
  frame = e and e.frame or frame + 1
  if frame % 60 == 0 then
    local w = try(game.world.get) or {}
    local p = try(game.player.get) or {}
    local s = try(game.session.get) or {}
    local _, alive, hp = monsters()
    local pos = p.position and string.format("%.0f,%.0f,%.0f", p.position.x, p.position.y, p.position.z) or "-"
    log(string.format("state frame=%d session=%s context=%s dungeon=%s floor=%s seed=%s walking=%s town=%s map=%s pos=%s monsters=%d hp=%d step=%d",
      frame, tostring(s.kind), tostring(w.context), tostring(w.dungeon_id), tostring(w.floor_id), tostring(w.floor_seed), tostring(w.walking), tostring(w.town_map),
      tostring(w.map_no), pos, alive, hp, at))
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
