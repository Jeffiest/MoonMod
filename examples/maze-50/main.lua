-- Maze 50: floors built after load use 50 small rooms spread over the
-- 48 x 48 PC floor grid (rooms use 46 x 46; the last column is the back-floor road) instead of the native 6 rooms in a 16 x 16 corner.

local layout, err = game.dungeons.set_layout({rooms = 50, area = 46, room_min = 2, room_max = 3})
if layout then
  moonmod.log("info", "MAZE|layout set: " .. layout.rooms .. " rooms, area " .. layout.area ..
              ", room size " .. layout.room_min .. "-" .. layout.room_max .. ", grid " .. layout.grid)
else
  moonmod.log("error", "MAZE|set_layout failed: " .. tostring(err and err.message))
end

local reported = {}
moonmod.on("game.tick", function()
  local world = game.world.get()
  if not world or world.context ~= "dungeon" or not world.room_count or world.room_count == 0 then return end
  local key = tostring(world.dungeon_id) .. ":" .. tostring(world.floor_id) .. ":" .. world.room_count
  if reported[key] then return end
  reported[key] = true
  moonmod.log("info", "MAZE|floor " .. tostring(world.floor_id) .. " built with " .. world.room_count .. " rooms")
  game.ui.notify({message = "Maze: " .. world.room_count .. " rooms on this floor"})
end)
