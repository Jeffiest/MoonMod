-- Open World (docs/plans/OPEN_WORLD_PLAN.md): Dark Cloud as one world to walk, built in steps.
--
-- OW0, this file so far: the two rules Vigil held for its own saves, for any story save.
--   * The passage: no trip from one place to another shows the loading card, and a town's dungeon is seen through
--     its door (dungeons.set_quick_passage).
--   * The road: a town's gate asks which way along the road (world.set_roads), not the world map. Only ways the save's
--     world map would show are offered; a town with none yet keeps its gate as the world map.
-- Each rule has one holder in the engine. If another mod holds one, this mod leaves that rule to it and answers
-- nothing for it. The road is asked for only once the party stands in a town, so a mod whose own game sets the roads
-- as a place loads (Vigil, on a Vigil World save: every road open) is always there first.

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil, {code = "unsupported", message = "operation missing"} end
  local ok, value, err = pcall(fn, ...)
  if not ok then return nil, {code = "error", message = tostring(value)} end
  return value, err
end

local function op(group, name)
  local g = type(game) == "table" and game[group] or nil
  return type(g) == "table" and g[name] or nil
end

local function message(err) return type(err) == "table" and tostring(err.message) or tostring(err) end

local function setting(id, fallback)
  local ok, value = pcall(moonmod.settings.get, id)
  if not ok or type(value) ~= type(fallback) then return fallback end
  return value
end

local function toast(text, frames) try(op("ui", "notify"), {message = text, duration_frames = frames or 240}) end

-- The towns along the road, by the game's town number, and the dungeons only the world map reached. Divine Beast Cave
-- and Wise Owl Forest are walked into through their towns' own doors.
local TOWNS = {[0] = {name = "Norune Village", id = "norune-village"},
               [1] = {name = "Matataki Village", id = "matataki-village"},
               [2] = {name = "Queens", id = "queens"},
               [3] = {name = "Muska Lacka", id = "muska-lacka"},
               [4] = {name = "Yellow Drops", id = "yellow-drops"}}
local DUNGEONS = {[2] = {name = "Shipwreck", id = "shipwreck"},
                  [3] = {name = "Sun and Moon Temple", id = "sun-and-moon-temple"},
                  [4] = {name = "Moon Sea", id = "moon-sea"},
                  [5] = {name = "Gallery of Time", id = "gallery-of-time"}}
local ROAD = {[0] = {{town = 1}},
              [1] = {{town = 0}, {town = 2}},
              [2] = {{town = 1}, {town = 3}, {dungeon = 2}},
              [3] = {{town = 2}, {town = 4}, {dungeon = 3}},
              [4] = {{town = 3}, {dungeon = 4}, {dungeon = 5}}}

local holds = {passage = false, roads = false} -- the rules this mod holds in the engine now
local road_from, road_ways = nil, nil          -- the town the road panel is open in, and the ways it offered
local clock = 0

-- Only in the story: not at the title, not in another mod's game mode (the Gauntlet: its floors are its own), not
-- as a guest in a friend's world.
local function playing_story()
  local s = try(op("session", "get"))
  return type(s) ~= "table" or s.kind == "story"
end

-- Would the save's world map show this place? (The story opens a place there before the party has been to it.)
local function opened(place)
  if not setting("story_gates", true) then return true end
  local l = try(op("locations", "get"), {id = "chronicle:location:" .. place.id})
  return type(l) == "table" and l.visited == true
end

local function ways_from(town)
  local out = {}
  for _, way in ipairs(ROAD[town] or {}) do
    local place = way.town and TOWNS[way.town] or DUNGEONS[way.dungeon]
    if opened(place) then out[#out + 1] = {town = way.town, dungeon = way.dungeon, name = place.name, id = place.id} end
  end
  return out
end

-- The town the party walks in, or nil.
local function town_now()
  local w = try(op("world", "get"))
  if type(w) ~= "table" or w.context ~= "georama" or math.type(w.area_id) ~= "integer" then return nil end
  return TOWNS[w.area_id] and w.area_id or nil
end

local function hold(key, fn, want)
  if want then
    -- asked again each time: it is free once its other holder lets go
    holds[key] = call(fn, {enabled = true}) ~= nil
  elseif holds[key] then
    try(fn, {enabled = false})
    holds[key] = false
  end
end

local function passage()
  hold("passage", op("dungeons", "set_quick_passage"), playing_story() and setting("passage", true))
end

local function roads()
  if not (playing_story() and setting("roads", true)) then
    hold("roads", op("world", "set_roads"), false)
    return
  end
  local town = town_now()
  if town == nil then return end -- on a floor or between places: nothing to decide until the next town
  -- A town with no way open yet keeps its gate as the world map, so an early save can still leave by it.
  hold("roads", op("world", "set_roads"), #ways_from(town) > 0)
end

local function release()
  hold("passage", op("dungeons", "set_quick_passage"), false)
  hold("roads", op("world", "set_roads"), false)
  if road_from then try(op("ui", "choice_close"), {}) end
  road_from, road_ways = nil, nil
end

-- The passage before a place is made, too: a town builds its dungeon's first floor unseen as it loads, and the rule
-- must stand by then.
moonmod.on("game.scene.will_enter", passage)
moonmod.on("game.world.location_changed", passage)
moonmod.on("game.session.started", passage)
moonmod.on("game.session.ended", release) -- the next game asks anew, after any mod whose game it is
moonmod.on("settings.changed", function() passage() roads() end)
moonmod.on("runtime.unloaded", release)

-- The road twice a second, in play: the story opens ways while the party stands in a town.
moonmod.on("game.tick", function()
  clock = clock + 1
  if clock % 30 ~= 0 or road_from then return end
  passage()
  roads()
end)

local function take(way)
  local ok, err
  if way.town then
    ok, err = call(op("world", "transition"), {id = "chronicle:location:" .. way.id})
  else
    -- in at its entrance, floor 1, as through a town's door
    ok, err = call(op("dungeons", "enter_floor"), {dungeon_id = way.dungeon, floor_id = 0})
  end
  if not ok then toast("Open World: the road is closed: " .. message(err)) end
end

moonmod.on("game.town.road", function(e)
  if type(e) ~= "table" or not ROAD[e.town_id] or not holds.roads or not playing_story() then return end
  local ways = ways_from(e.town_id)
  if #ways == 0 then return end
  local options = {}
  for _, way in ipairs(ways) do
    if way.town then
      options[#options + 1] = {title = way.name, lines = {way.town < e.town_id and "Back along the road." or "On along the road."}}
    else
      options[#options + 1] = {title = way.name, lines = {"Into the dungeon, at floor 1."}}
    end
  end
  options[#options + 1] = {title = "Stay", lines = {{text = "Not yet.", tone = "dim"}}}
  local shown = call(op("ui", "choice_open"), {id = "openworld.road", title = "The road", subtitle = "Out of " .. TOWNS[e.town_id].name,
                                             cancel = true, cursor = 1, town = true, options = options})
  if shown then road_from, road_ways = e.town_id, ways end
end)

moonmod.on("ui.choice_made", function(e)
  if type(e) ~= "table" or e.id ~= "openworld.road" or not road_from then return end
  local way = not e.cancelled and road_ways[e.index] or nil
  road_from, road_ways = nil, nil
  if way then take(way) end
end)

passage()
