-- Model Icons: the menus' item and weapon icons drawn from each item's own 3D model (render.item_icons_3d_set).
-- Disabling the mod in the Mod Manager puts the original icon sheets back.

local function setting(id, default)
  local value = moonmod.settings.get(id)
  if value == nil then return default end
  return value
end

local function apply()
  local result, err = game.render.item_icons_3d_set({
    enabled = true,
    key_light = setting("key_light", 120),
    fill_light = setting("fill_light", 36),
    ambient = setting("ambient", 70),
    smoothing = setting("smoothing", 60),
    outline = setting("outline", true),
  })
  if not result then
    moonmod.log("warn", "Model icons could not be turned on: " .. tostring(type(err) == "table" and err.message or err))
  end
end

if game.render.item_icons_3d_set then
  apply()
  moonmod.on("settings.changed", apply)
else
  moonmod.log("warn", "This Chronicle build cannot draw model icons (render.item_icons_3d_set is missing).")
end
