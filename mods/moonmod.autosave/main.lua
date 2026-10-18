local function apply()
  local enabled = moonmod.settings.get("enabled") ~= false
  local result, err = game.save.autosave_set({enabled = enabled})
  if not result then
    moonmod.log("warn", "Autosave setting could not be applied: " .. tostring(type(err) == "table" and err.message or err))
  end
end

apply()
moonmod.on("settings.changed", function(event)
  if event.id == "enabled" then apply() end
end)
