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
--
-- OW1 item 5, floors: a dungeon's floors are walked, with no stairs between them.
--   * Floors that follow one another on the same ground are built as one map, a zone each, joined by the game's
--     locked gates (dungeons.set_zones, asked for with yield = true: any other mod that lays floors out its own way
--     takes its place). The party walks from floor to floor through a gate; nothing loads and no scene plays.
--   * Where the ground changes (a story floor's own map, a floor that hands the party to one character, a floor that
--     opens with a scene not seen yet, a new set of walls) the exit gate is still the way on. It asks "next floor or
--     leave" over the floor and cuts to the next floor: no walk out and no walk in (set_quick_passage walks = false).

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

local function hold(key, fn, want, args)
  if want then
    -- asked again each time: it is free once its other holder lets go
    holds[key] = call(fn, args or {enabled = true}) ~= nil
  elseif holds[key] then
    try(fn, {enabled = false})
    holds[key] = false
  end
end

local function floors_on() return playing_story() and setting("floors", true) end

local function passage()
  -- with the floors walked, the stairs left (a region's last gate) have no walk out and no walk in
  hold("passage", op("dungeons", "set_quick_passage"), playing_story() and setting("passage", true),
       {enabled = true, walks = not floors_on()})
end

-- Floors ----------------------------------------------------------------------------------------------------------
-- Each dungeon by the game's number, floors counted from 0. `alone`: floors that stay maps of their own (a story
-- floor's fixed map, a boss, a floor that gives the party to one character, a floor on a map of its own). `starts`:
-- floors where the walls change (the game loads another set), so the floor before ends a map. `scenes`: floors whose
-- opening script plays a story scene until its story flag is set; such a floor stays alone until the scene is seen.
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end
local FLOORS = {
  [0] = {last = 14, alone = set{3, 6, 7, 10, 14}, starts = set{},
         scenes = {[0] = 103, [1] = 100, [2] = 106, [4] = 104, [5] = 101, [6] = 105}}, -- Divine Beast Cave
  [1] = {last = 16, alone = set{3, 8, 11, 16}, starts = set{9}},                        -- Wise Owl Forest
  [2] = {last = 17, alone = set{4, 8, 11, 16, 17}, starts = set{9}},                    -- Shipwreck
  [3] = {last = 17, alone = set{4, 8, 12, 17}, starts = set{9}, scenes = {[3] = 130, [6] = 131}}, -- Sun and Moon Temple
  [4] = {last = 14, alone = set{3, 7, 10, 14}, starts = set{8}},                        -- Moon Sea
  [5] = {last = 24, alone = set{18, 19, 20, 21, 22, 23, 24}, starts = set{6, 12, 18}},  -- Gallery of Time
  [6] = {last = 99, alone = set{98, 99}, starts = set{20, 40, 60, 80}},                 -- Demon Shaft
}
local ZONE_ROOMS = 5 -- rooms to a floor's zone
local MAX_ZONES = 24 -- the most floors on one map

local function alone(d, f)
  local t = FLOORS[d]
  if t.alone[f] then return true end
  local flag = t.scenes and t.scenes[f]
  if flag then
    local seen = try(op("world", "story_flag_get"), {id = flag})
    if type(seen) ~= "table" or seen.value ~= true then return true end
  end
  -- a floor the save puts a limit on (one character, no healing...) starts as the game starts it
  if d <= 5 and f <= 24 then
    local rules = try(op("dungeons", "floor_rules_get"), {dungeon_id = d, floor_id = f})
    if type(rules) == "table" and math.type(rules.limit_zone) == "integer" and rules.limit_zone >= 0 then return true end
  end
  return false
end

-- The floors built as one map with floor f: first and last. A floor alone is its own first and last.
local function region_of(d, f)
  local t = FLOORS[d]
  if not t or math.type(f) ~= "integer" or f < 0 or f > t.last then return nil end
  if alone(d, f) then return f, f end
  local first, last = f, f
  while first > 0 and not t.starts[first] and f - first + 1 < MAX_ZONES and not alone(d, first - 1) do first = first - 1 end
  while last < t.last and not t.starts[last + 1] and last - first + 1 < MAX_ZONES and not alone(d, last + 1) do last = last + 1 end
  return first, last
end

local walked = false -- the floor being built is one of several on its map, by this mod's asking

-- {yield = true} alone lets go of this mod's own request and of no other mod's.
local function floors_let_go()
  walked = false
  try(op("dungeons", "set_zones"), {yield = true})
end

moonmod.on("game.dungeon.generating", function(e)
  if type(e) ~= "table" or e.back_floor then return end
  local first, last
  if floors_on() then first, last = region_of(e.dungeon_id, e.floor_id) end
  if not first or first == last then
    floors_let_go()
    return
  end
  local zones, open = {}, {}
  for f = first, last do zones[#zones + 1] = {rooms = ZONE_ROOMS, source_floor = f} end
  -- come in at a later floor (the entrance's floor list): the gates behind it stand open
  for z = 1, e.floor_id - first do open[#open + 1] = z end
  walked = call(op("dungeons", "set_zones"), {yield = true, zones = zones, exit_floor = last + 1,
                                              open = #open > 0 and open or nil}) ~= nil
  if walked and e.floor_id ~= first then
    try(op("dungeons", "set_arrival"), {zone = e.floor_id - first, teleport = true})
  end
end)

moonmod.on("game.dungeon.zone_entered", function(e)
  if not walked or type(e) ~= "table" or math.type(e.floor_id) ~= "integer" then return end
  if math.type(e.previous) ~= "integer" or e.previous < 0 then return end -- arriving on the map
  toast(string.format("Floor %d", e.floor_id + 1), 150)
end)

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
  floors_let_go()
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
