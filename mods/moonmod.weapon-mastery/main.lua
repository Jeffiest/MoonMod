-- One-time bridge for saves from the earlier standalone Weapon Mastery package.
-- Ascension now owns mastery progression, combat bonuses, and the manager UI.
local function checked(value, err)
  if value == nil then error(type(err) == "table" and err.message or tostring(err)) end
  return value
end

local function import_saved_mastery()
  if moonmod.storage.get("migration_complete") then return 0 end
  local legacy = moonmod.storage.get("mastery") or {}
  if type(legacy) ~= "table" then
    moonmod.log("warn", "Weapon Mastery migration skipped: saved data was not a table")
    return nil
  end
  local result, err = game.scripts.call_function({
    id = "moonmod.ascension:import_legacy_mastery",
    arguments = { mastery = legacy }
  })
  if not result then
    moonmod.log("warn", "Weapon Mastery migration failed: " ..
      (type(err) == "table" and err.message or tostring(err)))
    return nil
  end
  checked(moonmod.storage.set("migration_complete", true))
  return result.imported or 0
end

local imported = import_saved_mastery()
if imported ~= nil then
  moonmod.log("info", "Weapon Mastery migration finished; merged " .. imported .. " weapon records")
end

checked(game.ui.register({
  id = "import_saved_mastery",
  label = "Import Saved Weapon Mastery",
  description = "Merge saved kills from this older package into Ascension"
}))
moonmod.on("ui.action", function(action)
  if action.id ~= "import_saved_mastery" then return end
  checked(moonmod.storage.set("migration_complete", false))
  local count = import_saved_mastery()
  if count == nil then
    game.ui.notify({message = "Could not import mastery. Check that Ascension is enabled."})
  else
    game.ui.notify({message = "Ascension imported " .. count .. " mastery records"})
  end
end)

