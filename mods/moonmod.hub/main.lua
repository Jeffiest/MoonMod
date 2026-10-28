local destinations = {
  {id="rpg_skills", label="RPG: Skill Paths (manager view)", mod_id="moonmod.rpg", tab="skills"},
  {id="rpg_actions", label="RPG: Progress and Reset", mod_id="moonmod.rpg", tab="actions"},
  {id="dungeon_actions", label="Dungeon+: Floors and Rewards", mod_id="moonmod.dungeon-plus", tab="actions"},
  {id="dungeon_journal", label="Dungeon+: Trophy Journal", mod_id="moonmod.dungeon-plus", tab="journal"},
  {id="controls_settings", label="Controls: Shortcuts", mod_id="moonmod.controls", tab="settings"},
  {id="autosave_settings", label="Autosave: Settings", mod_id="moonmod.autosave", tab="settings"},
  {id="town_camera_settings", label="Expanded Town: Settings", mod_id="moonmod.expanded-town", tab="settings"},
  {id="town_camera_actions", label="Expanded Town: Actions", mod_id="moonmod.expanded-town", tab="actions"},
  {id="gauntlet_actions", label="Gauntlet: Run Actions", mod_id="moonmod.roguelike", tab="actions"},
  {id="gauntlet_skills", label="Gauntlet: Diorama and Eternal", mod_id="moonmod.roguelike", tab="skills"}
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

-- Hotkey: K, or L1+R1+R3 on a gamepad, opens the Journal's Character page (RPG paths); the Mod
-- Manager's Skills tab is the fallback on an engine without that page.
assert(game.input.bind({id = "hub_key", keys = {"K"}}))
assert(game.input.bind({id = "hub_journal_key", keys = {"J"}}))
assert(game.input.bind({id = "hub_l1", keys = {"Gamepad:leftshoulder"}}))
assert(game.input.bind({id = "hub_r1", keys = {"Gamepad:rightshoulder"}}))
assert(game.input.bind({id = "hub_r3", keys = {"Gamepad:rightstick"}}))
local chord_down = false
moonmod.on("game.tick", function()
  local journal = game.input.consume({id = "hub_journal_key"})
  if journal and journal.pressed then
    local opened = game.ui.navigate({mod_id = "moonmod.dungeon-plus", tab = "journal"})
    if not opened then game.ui.navigate({mod_id = "moonmod.dungeon-plus", tab = "actions"}) end
  end
  local key = game.input.consume({id = "hub_key"})
  local l1 = game.input.state({id = "hub_l1"})
  local r1 = game.input.state({id = "hub_r1"})
  local r3 = game.input.state({id = "hub_r3"})
  local chord = (l1 and l1.down and r1 and r1.down and r3 and r3.down) or false
  if (key and key.pressed) or (chord and not chord_down) then
    local opened, err = false, nil
    if type(game.ui.sheet_open) == "function" then
      local result, open_err = game.ui.sheet_open()
      opened, err = result ~= nil, open_err
    end
    if not opened then opened, err = game.ui.navigate({mod_id = "moonmod.rpg", tab = "skills"}) end
    if not opened then
      opened = game.ui.navigate({mod_id = "moonmod.rpg", tab = "actions"})
      if not opened then game.ui.notify({message = "Hub: " .. tostring(type(err) == "table" and err.message or err)}) end
    end
  end
  chord_down = chord
end)
moonmod.log("info", "MoonMod Hub ready (K or L1+R1+R3 character page, J journal)")
