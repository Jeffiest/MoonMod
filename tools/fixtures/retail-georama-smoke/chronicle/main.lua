local finished = false
local attempts = 0
local last_error = ""
local registered = false
local candidate_index = 1
local candidates
local piece_id = "moonfactory.retail-georama-probe:retail-post-variant"

local function probe()
  if finished then return end
  attempts = attempts + 1
  local town, town_error = game.georama.get({town_id = 0})
  if town == nil then
    if attempts >= 90 then
      finished = true
      moonmod.log("warning", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|town read failed|" .. tostring(town_error and town_error.message))
    end
    return
  end
  if type(town.placement_areas) ~= "table" or type(town.native_pieces) ~= "table" then
    if attempts >= 90 then
      finished = true
      moonmod.log("warning", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|native placement metadata unavailable")
    end
    return
  end

  if not registered then
    local template
    for _, piece in ipairs(town.native_pieces) do
      if piece.loaded and piece.subtype == 0 and piece.width_cells > 0 and piece.height_cells > 0 then
        template = piece
        break
      end
    end
    if template == nil then
      if attempts >= 180 then
        finished = true
        moonmod.log("warning", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|no loaded solid template was available")
      end
      return
    end
    local variant, register_error = game.georama.register({
      id = "retail-post-variant",
      name = "Retail Post Variant",
      template_part_id = template.part_id,
      town_id = 0,
      stock = 1
    })
    if variant == nil then
      finished = true
      moonmod.log("warning", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|variant registration failed|" ..
                  tostring(register_error and register_error.message))
      return
    end
    assert(variant.id == piece_id and variant.materialized)
    registered = true
    moonmod.log("info", "MOONFACTORY_RETAIL_GEORAMA_REGISTERED|" .. variant.id .. "|" ..
                variant.native_part_id .. "|" .. template.part_id)
    town = assert(game.georama.get({town_id = 0}))
  end

  local variant
  for _, piece in ipairs(town.mod_pieces or {}) do
    if piece.id == piece_id and piece.loaded and piece.available_built > 0 then
      variant = piece
      break
    end
  end
  if variant == nil then
    if attempts >= 180 then
      finished = true
      moonmod.log("warning", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|registered variant is not materialized with stock")
    end
    return
  end

  if candidates == nil or #candidates == 0 then
    candidates = {}
    for _, area in ipairs(town.placement_areas) do
      for cell_z = 0, area.height_cells - 1 do
        for cell_x = 0, area.width_cells - 1 do
          candidates[#candidates + 1] = {area = area, x = cell_x, z = cell_z}
          if #candidates >= 2048 then break end
        end
        if #candidates >= 2048 then break end
      end
      if #candidates >= 2048 then break end
    end
    if #candidates == 0 and attempts >= 180 then
      finished = true
      moonmod.log("warning", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|town has no placement cells")
      return
    end
  end

  if #candidates == 0 then return end
  local limit = math.min(candidate_index + 15, #candidates)
  for index = candidate_index, limit do
    local candidate = candidates[index]
    local area = candidate.area
    local position = {
      x = area.origin.x + (candidate.x + 0.5) * area.cell_size,
      y = area.origin.y,
      z = area.origin.z + (candidate.z + 0.5) * area.cell_size
    }
    local placed, place_error = game.georama.place({
      town_id = 0,
      part_id = piece_id,
      position = position,
      rotation_quarter_turns = 0
    })
    if placed ~= nil then
      local listed = assert(game.georama.get({town_id = 0}))
      local found = false
      for _, current in ipairs(listed.placed_parts) do
        if current.placement_id == placed.placement_id and current.id == piece_id then found = true end
      end
      assert(found, "mod piece must appear in georama.get after native save")
      local removed = assert(game.georama.remove({placement_id = placed.placement_id}))
      assert(removed.removed and removed.id == piece_id)
      local after = assert(game.georama.get({town_id = 0}))
      for _, current in ipairs(after.placed_parts) do
        assert(current.placement_id ~= placed.placement_id, "removed mod piece must disappear from saved layout")
      end
      finished = true
      moonmod.log("info", "MOONFACTORY_RETAIL_GEORAMA_PLACE_REMOVE_OK|" .. placed.part_id .. "|" ..
                  placed.placement_id .. "|" .. area.area_index .. "|" .. candidate.x .. "|" .. candidate.z)
      return
    end
    last_error = tostring(place_error and place_error.message or "native placement rejected")
  end
  candidate_index = limit + 1
  if candidate_index > #candidates or attempts >= 180 then
    finished = true
    moonmod.log("warning", "MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|all native positions rejected|" .. last_error)
  end
end

game.events.subscribe("game.tick", probe)
return {}
