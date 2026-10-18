-- Keyboard conveniences for Chronicle dungeon play. Native options remain
-- responsible for the game's own controller/keyboard bindings.
local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  return type(value) == "string" and value or fallback
end

local actions = {}
local quick_keys = {
  setting("quick_1_key", "1"),
  setting("quick_2_key", "2"),
  setting("quick_3_key", "3")
}
local party_ids = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}

for slot = 1, 3 do actions[#actions + 1] = {id = "quick_item_" .. slot, kind = "item", slot = slot} end
for index, character in ipairs(party_ids) do
  actions[#actions + 1] = {id = "party_member_" .. index, kind = "party", character = character}
end
actions[#actions + 1] = {id = "first_person_toggle", kind = "camera"}
actions[#actions + 1] = {id = "town_cycle", kind = "town_cycle"}

local function bind_actions()
  for slot = 1, 3 do
    assert(game.input.bind({id = "quick_item_" .. slot, keys = {setting("quick_" .. slot .. "_key", tostring(slot))}}))
  end
  for index = 1, #party_ids do
    assert(game.input.bind({id = "party_member_" .. index,
      keys = {setting("party_" .. index .. "_key", tostring(index + 3))}}))
  end
  assert(game.input.bind({id = "first_person_toggle", keys = {setting("first_person_key", "V")}}))
  -- Select is left to the game (it opens Georama); Backspace cycles town characters.
  assert(game.input.bind({id = "town_cycle", keys = {"Backspace"}}))
end
bind_actions()
moonmod.on("settings.changed", bind_actions)

local function notify(message)
  game.ui.notify({message = message:sub(1, 190)})
end

moonmod.on("game.tick", function()
  local world = game.world.get()
  local in_dungeon = world ~= nil and world.context == "dungeon"
  local in_town = world ~= nil and world.context == "georama" and type(world.map_id) == "number" and world.map_id >= 0 and world.map_id < 200
  game.input.wheel_mode_set({mode = in_dungeon and 0 or 1})
  for _, action in ipairs(actions) do
    local press = game.input.consume({id = action.id})
    if press and press.pressed then
      if action.kind == "item" and in_dungeon then
        local selected, err = game.items.quick_slot_use({slot = action.slot})
        if not selected then notify("Quick item unavailable: " .. tostring(type(err) == "table" and err.message or err)) end
      elseif action.kind == "party" and (in_dungeon or in_town) then
        local changed, err
        if in_dungeon then changed, err = game.party.set_active({id = action.character})
        else changed, err = game.party.town_set_active({id = action.character}) end
        if not changed then notify("Party switch unavailable: " .. tostring(type(err) == "table" and err.message or err)) end
      elseif action.kind == "camera" and in_dungeon then
        local toggled, err = game.render.first_person_toggle()
        if not toggled then notify("First-person view unavailable: " .. tostring(type(err) == "table" and err.message or err)) end
      elseif action.kind == "town_cycle" and in_town then
        local current = game.party.town_active()
        if current and type(current.id) == "string" then
          local index = 1
          for i, id in ipairs(party_ids) do if id == current.id then index = i;break end end
          local switched = false
          -- Only characters who have joined the party.
          local joined = {}
          local roster = game.party.list()
          for _, member in ipairs(roster and (roster.members or roster) or {}) do
            if type(member) == "table" and member.id then joined[member.id] = true end
          end
          for step = 1, #party_ids - 1 do
            local candidate = party_ids[((index - 1 + step) % #party_ids) + 1]
            local result = joined[candidate] and game.party.town_set_active({id = candidate})
            if result then switched = true;break end
          end
          if not switched then notify("No other joined town character is available") end
        end
      end
    end
  end
end)
