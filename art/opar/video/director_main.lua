-- Test-only: the Opar showcase's director. Opar takes over, stays unhurt, and the camera and the scene follow
-- video_shot.txt (beside the game's exe): "distance height [angle]" on the first line, then flags, one a line:
-- pull (the floor's monsters are drawn in round him), hurt (no invincibility), nohud.
local function log(s) moonmod.log("info", "VIDEO " .. s) end
local function call(fn, ...) local ok, r, e = pcall(fn, ...); if ok then return r, e end; return nil, r end
local function errs(e) return type(e) == "table" and tostring(e.message) or tostring(e) end
local arrived, frame, shot = nil, 0, nil
local function read_shot()
  local f = io and io.open and io.open("video_shot.txt") or nil
  local s = {distance = 160, height = 30, flags = {}}
  if not f then return s end
  local first = f:read("*l") or ""
  local d, h, a = first:match("([%d%.%-]+)%s+([%d%.%-]+)%s*([%d%.%-]*)")
  s.distance, s.height, s.angle = tonumber(d) or 160, tonumber(h) or 30, tonumber(a)
  for line in f:lines() do s.flags[line:gsub("%s+", "")] = true end
  f:close()
  return s
end
moonmod.on("game.tick", function(e)
  frame = e and e.frame or frame + 1
  local w = call(game.world.get) or {}
  if w.context ~= "dungeon" or (w.floor_id or 0) == 0 then return end
  if not arrived then arrived = frame; shot = read_shot(); log("ARRIVED at " .. frame) end
  local dt = frame - arrived
  if not shot.flags.hurt and dt % 15 == 0 then call(game.player.invincible, {frames = 120}) end
  local p = call(game.player.get) or {}
  if dt % 30 == 0 and p.character ~= "opar" then
    call(game.player.set, {max_hp = 120, character = "opar"})
    call(game.player.set, {hp = 120, character = "opar"})
    local s, serr = call(game.party.set_active, {id = "opar"})
    if s then log("ACTIVE opar at " .. frame) end
  end
  -- every frame: set only now and then, the follow camera eases back toward its own reach in between and the view pulses
  if not shot.flags.free then call(game.render.camera_set, {distance = shot.distance, height = shot.height, angle = shot.angle}) end
  if shot.flags.pull and p.position and dt % 2 == 0 then
    if dt == 0 then call(game.entities.set_active_limit, {active = 16}) end
    local found = call(game.entities.query, {type = "monster"})
    for _, m in ipairs(found and found.entities or {}) do
      local at = m.position
      if at then
        local dx, dz = p.position.x - at.x, p.position.z - at.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d > 60 and d < 2000 then
          local ok, err = call(game.physics.velocity_set, {entity = m.entity_id or m.id, velocity = {x = dx / d * 3, y = 0, z = dz / d * 3}})
          if not ok and dt % 300 == 0 then log("PULL " .. errs(err)) end
        end
      end
    end
  end
  if dt % 300 == 0 then
    local found = call(game.entities.query, {type = "monster"})
    local near = {}
    for _, m in ipairs(found and found.entities or {}) do
      if m.position and p.position then
        near[#near + 1] = math.floor(math.sqrt((m.position.x - p.position.x) ^ 2 + (m.position.z - p.position.z) ^ 2))
      end
    end
    log("AT " .. frame .. " " .. tostring(p.character) .. " monsters " .. table.concat(near, ","))
  end
end)
