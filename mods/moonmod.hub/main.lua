local destinations = {
  {id="ascension_skills", label="Ascension: Skill Tree", mod_id="moonmod.ascension", tab="skills"},
  {id="ascension_actions", label="Ascension: Progression and Mastery", mod_id="moonmod.ascension", tab="actions"},
  {id="dungeon_actions", label="Dungeon+: Floors and Rewards", mod_id="moonmod.dungeon-plus", tab="actions"},
  {id="dungeon_journal", label="Dungeon+: Trophy Journal", mod_id="moonmod.dungeon-plus", tab="journal"},
  {id="controls_settings", label="Controls: Shortcuts", mod_id="moonmod.controls", tab="settings"},
  {id="autosave_settings", label="Autosave: Settings", mod_id="moonmod.autosave", tab="settings"},
  {id="town_camera_settings", label="Expanded Town: Settings", mod_id="moonmod.expanded-town", tab="settings"},
  {id="town_camera_actions", label="Expanded Town: Actions", mod_id="moonmod.expanded-town", tab="actions"}
}

local by_action = {}
for _, destination in ipairs(destinations) do
  local ok, err = game.ui.register({
    id=destination.id,
    label=destination.label,
    description="Open this package page in the current Mod Manager"
  })
  if not ok then error(type(err)=="table" and err.message or tostring(err)) end
  by_action[destination.id] = destination
end

moonmod.on("ui.action", function(action)
  local destination = action and by_action[action.id]
  if not destination then return end
  local opened, err = game.ui.navigate({mod_id=destination.mod_id, tab=destination.tab})
  if not opened then
    game.ui.notify({message=destination.label .. ": " .. tostring(type(err)=="table" and err.message or err)})
  end
end)
