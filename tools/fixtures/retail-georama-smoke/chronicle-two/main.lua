local piece = assert(game.georama.register({
  id = "retail-moonstone-variant",
  name = "Retail Moonstone Variant",
  template_part_id = 70
}))

assert(piece.id == "moonfactory.retail-georama-probe:retail-moonstone-variant")
assert(piece.status == "pending" and piece.template_part_id == 70)

local completed = false
local ready = false
local candidates = {}
local candidate_index = 1
local attempts = 0
local last_error = "no native placement candidate was accepted"
local first_error = ""
local first_unexpected_error = ""
local town_entered = false
local registration_checks = 0
local last_registration_status = "not observed"

local function append_candidate(position, x_offset, z_offset)
  if #candidates >= 1024 then return end
  candidates[#candidates + 1] = {
    x = position.x + x_offset,
    y = position.y,
    z = position.z + z_offset
  }
end

local function begin_placement(town, registered)
  local centers = {}
  for _, anchor in ipairs(town.placement_anchors or {}) do
    if anchor.position and anchor.surface_y ~= nil and #centers < 12 then
      centers[#centers + 1] = {x = anchor.position.x, y = anchor.surface_y, z = anchor.position.z}
    end
    if anchor.position and anchor.surface_y ~= nil and anchor.footprint and #candidates < 1024 then
      local step = 64
      for x = anchor.footprint.min_x + step / 2, anchor.footprint.max_x - step / 2, step do
        for z = anchor.footprint.min_z + step / 2, anchor.footprint.max_z - step / 2, step do
          append_candidate(anchor.position, x, z)
          if #candidates >= 1024 then break end
        end
        if #candidates >= 1024 then break end
      end
    end
  end
  for _, placed in ipairs(town.placed_parts or {}) do
    if placed.position and #centers < 13 then
      centers[#centers + 1] = placed.position
    end
  end
  if #centers == 0 then centers[1] = {x = 0, y = 0, z = 0} end

  local directions = {
    {1, 0}, {-1, 0}, {0, 1}, {0, -1},
    {1, 1}, {1, -1}, {-1, 1}, {-1, -1}
  }
  for _, center in ipairs(centers) do
    append_candidate(center, 0, 0)
    for radius = 2, 24, 2 do
      for _, direction in ipairs(directions) do
        append_candidate(center, direction[1] * radius, direction[2] * radius)
        if #candidates >= 1024 then break end
      end
      if #candidates >= 1024 then break end
    end
    if #candidates >= 1024 then break end
  end

  moonmod.log("info", "MOONFACTORY_RETAIL_GEORAMA_REGISTERED|" .. registered.id .. "|" ..
    registered.native_part_id .. "|" .. registered.status)
  ready = true
end

local function place_remove_probe()
  if completed or not town_entered then return end

  if not ready then
    registration_checks = registration_checks + 1
    local town, town_error = game.georama.get({town_id = 0})
    if town ~= nil then
      assert(type(town.placement_anchors) == "table" and #town.placement_anchors > 0,
             "active retail town must expose loaded native placement surfaces")
      for _, registered in ipairs(town.mod_pieces or {}) do
        if registered.id == piece.id then
          last_registration_status = tostring(registered.status) .. ":" .. tostring(registered.reason or "")
          if registered.status == "registered" and registered.native_part_id ~= nil and registered.native_part_id > 0 then
            assert(registered.template_part_id == 70 and registered.name == "Retail Moonstone Variant")
            piece.native_part_id = registered.native_part_id
            begin_placement(town, registered)
            return
          end
        end
      end
    else
      last_registration_status = tostring(town_error and town_error.message or "town state unavailable")
    end

    if registration_checks >= 120 then
      completed = true
      moonmod.log("error", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|registered variant did not materialize|" ..
        last_registration_status)
    end
    return
  end

  local limit = math.min(candidate_index + 11, #candidates)
  for index = candidate_index, limit do
    local candidate = candidates[index]
    attempts = attempts + 1
    local placed, place_error = game.georama.place({
      id = piece.id,
      position = candidate,
      rotation_steps = 0
    })
    if placed ~= nil then
      assert(placed.part_id > 0 and placed.part_id == piece.native_part_id,
             "placement must use the registered variant's native part id")
      local after_place = assert(game.georama.get({town_id = 0}))
      local found = false
      for _, current in ipairs(after_place.placed_parts or {}) do
        if current.id == placed.placement_id and current.part_id == placed.part_id then
          found = true
        end
      end
      if not found then
        local saved_entries = {}
        for _, current in ipairs(after_place.placed_parts or {}) do
          saved_entries[#saved_entries + 1] = current.id .. "=" .. tostring(current.part_id) ..
            "@" .. tostring(current.position.x) .. "," .. tostring(current.position.y) .. "," .. tostring(current.position.z)
        end
        moonmod.log("error", "MOONFACTORY_RETAIL_GEORAMA_READBACK_DIAG|wanted=" .. placed.placement_id .. "=" ..
          tostring(placed.part_id) .. "|save_count=" .. tostring(after_place.save_count) .. "|entries=" ..
          table.concat(saved_entries, ";"))
        completed = true
        return
      end

      local removed = assert(game.georama.remove({placement_id = placed.placement_id}))
      assert(removed.removed and removed.part_id == placed.part_id,
             "native removal must remove the just-placed variant")
      local after_remove = assert(game.georama.get({town_id = 0}))
      for _, current in ipairs(after_remove.placed_parts or {}) do
        assert(current.id ~= placed.placement_id,
               "removed variant must disappear from the saved town layout")
      end
      completed = true
      moonmod.log("info", "MOONFACTORY_RETAIL_GEORAMA_VARIANT_PLACE_REMOVE_OK|" .. piece.id .. "|" ..
        placed.part_id .. "|" .. placed.placement_id .. "|" .. placed.remaining_built)
      return
    end
    last_error = tostring(place_error and place_error.message or "native placement rejected")
    if attempts == 1 then first_error = last_error end
    if first_unexpected_error == "" and last_error ~= "the native Georama placement rules reject the requested position" then
      first_unexpected_error = last_error
    end
  end

  candidate_index = limit + 1
  if candidate_index > #candidates or attempts >= 1024 then
    completed = true
    moonmod.log("error", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|native variant placement failed after " ..
      attempts .. " candidates|first=" .. first_error .. "|unexpected=" .. first_unexpected_error ..
      "|last=" .. last_error)
  end
end

game.events.subscribe("game.scene.entered", function(scene)
  if not completed and scene.scene_id == "town" then town_entered = true end
end)

game.events.subscribe("game.tick", place_remove_probe)

return {}
