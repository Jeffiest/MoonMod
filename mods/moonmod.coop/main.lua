-- Online Co-op (moonmod.coop): play together, up to four, through the co-op relay (game.net.*).
--
-- The host plays their own save and opens a room (Mod Manager > Online Co-op > Host, or F8); the relay gives it a
-- five-letter code. A friend picks Online Co-op on the title screen, sets the code and joins. Their game says hello
-- with its player id; the host's game answers with its world (save.world_export) and the things its save keeps for
-- that player (save.account_get), or nothing for someone new, and the town to arrive in. The friend's game then starts
-- a visit (session.start {visit}): the host's story, towns, Georama and dungeons, with the friend's own weapons,
-- items and Gilda, and the friend's own saves untouched. Every so often, and on leaving, the friend's game sends its
-- things back (save.player_export), and the host's save keeps them (save.account_set) the next time the host saves.
--
-- Messages are text, "KIND rest". Large ones (a world is about 64 KB, a player's things about 37 KB) go in pieces:
-- "KIND i n piece", reassembled per sender. PROTOCOL is net.host/join's version: change it when the messages change.

local PROTOCOL = 4
local MODE = "coop"
local PIECE = 12000 -- characters of one piece; net.send takes 16 KiB
local DUNGEON_TOWN = {[0] = 0, [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 4, [6] = 0} -- the town each dungeon is reached from
local LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end
local function call(fn, ...)
  if type(fn) ~= "function" then return nil, {code = "unsupported", message = "this engine has no such operation"} end
  local ok, value, err = pcall(fn, ...)
  if not ok then return nil, {code = "error", message = tostring(value)} end
  return value, err
end
local function errmsg(err) return type(err) == "table" and tostring(err.message) or tostring(err) end
local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= type(fallback) then return fallback end
  return value
end
local function toast(message) try(game.ui.notify, {message = tostring(message):sub(1, 196), duration_frames = 300}) end
local function hud(text)
  if text then try(game.render.layer_register, {id = "coop", text = text:sub(1, 48)})
  else try(game.render.layer_remove, {id = "coop"}) end
end

-- This player's id, made once and kept: the host keeps their things under it.
local me = moonmod.storage.get("me")
if type(me) ~= "table" or type(me.id) ~= "string" then
  local hex = {}
  for i = 1, 16 do hex[i] = string.format("%x", math.random(0, 15)) end
  me = {id = "p" .. table.concat(hex)}
  moonmod.storage.set("me", me)
end
local function my_name()
  local name = setting("name", "")
  return name ~= "" and name or nil
end

-- The session: role "host" or "guest" (nil when none), the room code, the players by id, and the pieces arriving.
local S = {role = nil, code = nil, players = {}, pieces = {}, guest = nil, frame = 0, kept_at = 0, names = {}}
local code = moonmod.storage.get("code") or "-----" -- the code being typed on the title page

local function net_open(kind, args)
  args.version = PROTOCOL
  args.name = my_name()
  local server = setting("server", "")
  if server ~= "" then args.relay = server end
  return call(kind == "host" and game.net.host or game.net.join, args)
end

local function send(to, kind, text)
  local ok, err = call(game.net.send, {to = to, data = kind .. (text and (" " .. text) or "")})
  if not ok then moonmod.log("warn", "co-op send " .. kind .. ": " .. errmsg(err)) end
  return ok
end

local function send_pieces(to, kind, text)
  local n = math.max(1, math.ceil(#text / PIECE))
  for i = 1, n do
    if not send(to, kind, i .. " " .. n .. " " .. text:sub((i - 1) * PIECE + 1, i * PIECE)) then return false end
  end
  return true
end

-- One piece in; the whole text once the last has come, else nil.
local function take_piece(from, kind, rest)
  local i, n, piece = rest:match("^(%d+) (%d+) (.*)$")
  i, n = tonumber(i), tonumber(n)
  if not i or not n or n < 1 or n > 64 or i < 1 or i > n then return nil end
  local key = from .. ":" .. kind
  local p = S.pieces[key]
  if not p or p.n ~= n or i == 1 then p = {n = n, got = 0, parts = {}}; S.pieces[key] = p end
  if not p.parts[i] then p.parts[i] = piece; p.got = p.got + 1 end
  if p.got < n then return nil end
  S.pieces[key] = nil
  return table.concat(p.parts)
end

local function show_room()
  if not S.role then
    hud(nil)
    try(game.render.layer_remove, {id = "coop_who"})
    return
  end
  local count = 1
  for _ in pairs(S.players) do count = count + 1 end
  hud(string.format("CO-OP %s  %d of 4", S.code or "....", count))
  -- the others in the room, by name, under it
  local names = {}
  for _, name in pairs(S.names) do names[#names + 1] = name end
  table.sort(names)
  if #names > 0 then try(game.render.layer_register, {id = "coop_who", text = table.concat(names, ", "):sub(1, 48)})
  else try(game.render.layer_remove, {id = "coop_who"}) end
end

-- Seeing each other ------------------------------------------------------------------------------------------------
-- Ten times a second each game sends where its player is on a dungeon floor ("P scene character weapon x y z heading
-- motion"); each game shows the others on the same floor as heroes of their own (world.avatar_set), the host in its
-- own colours and guests in blue, and takes away one that has gone quiet for three seconds or is elsewhere. Every game
-- builds each floor from a seed made of the room's code, the dungeon and the floor (dungeons.set_seed), so the floors
-- are the same for everyone, whoever comes first.

local SEND_EVERY = 6     -- frames between reports
local QUIET = 180        -- frames without a report before a player's hero goes
local GUEST_TINT = {64, 84, 128}
local others = {}        -- peer -> {scene, state, heard, slot}
local my_scene = nil

local function scene_of(w)
  if type(w) ~= "table" then return nil end
  if w.context == "dungeon" and w.dungeon_id then
    return string.format("D%d:%d:%s", w.dungeon_id, w.floor_id or -1, tostring(w.floor_seed or "-"))
  end
  if w.town_map then return "T" .. w.town_map end -- walking (or in a menu) in a town
  return nil
end
local function on_floor() return my_scene ~= nil and my_scene:sub(1, 1) == "D" end

local function slot_of(peer)
  -- the others in id order take slots 1, 2, 3
  local ids = {}
  for id in pairs(others) do ids[#ids + 1] = id end
  table.sort(ids)
  for i, id in ipairs(ids) do if id == peer then return i <= 3 and i or nil end end
  return nil
end

local function show_others()
  for peer, o in pairs(others) do
    local slot = slot_of(peer)
    local here = slot and o.state and my_scene and o.scene == my_scene and S.frame - o.heard < QUIET
    if here then
      local st = o.state
      try(game.world and game.world.avatar_set, {slot = slot, character = st.character, weapon = st.weapon, x = st.x, y = st.y, z = st.z,
                                  heading = st.heading, motion = st.motion, tint = peer ~= 0 and GUEST_TINT or nil,
                                  name = o.name or (peer == 0 and "Host" or ("Player " .. peer))})
      o.slot = slot
    elseif o.slot then
      try(game.world and game.world.avatar_clear, {slot = o.slot})
      o.slot = nil
    end
  end
end

local function hear_position(peer, rest)
  local scene, character, weapon, x, y, z, heading, motion =
    rest:match("^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)$")
  local o = others[peer] or {}
  others[peer] = o
  o.heard = S.frame
  if not scene or scene == "-" then o.scene, o.state = nil, nil return end
  o.scene = scene
  o.state = {character = character, weapon = tonumber(weapon), x = tonumber(x) or 0, y = tonumber(y) or 0,
             z = tonumber(z) or 0, heading = tonumber(heading) or 0, motion = math.floor(tonumber(motion) or 0)}
end

-- Names: each game says its player's name ("N name") on joining, and the others answer with theirs.
local function say_name(to)
  send(to, "N", (my_name() or ("Player " .. tostring(S.me_peer or "?"))):sub(1, 24))
end

local function hear_name(peer, rest)
  local o = others[peer] or {}
  others[peer] = o
  local first = o.name == nil
  o.name = rest ~= "" and rest:sub(1, 24) or nil
  S.names[peer] = o.name or ("Player " .. peer)
  if first then say_name(peer) end
  show_room()
end

local function forget(peer)
  local o = others[peer]
  if o and o.slot then try(game.world and game.world.avatar_clear, {slot = o.slot}) end
  others[peer] = nil
  S.names[peer] = nil
end

local function forget_all()
  others = {}
  try(game.world and game.world.avatar_clear)
end

local last_sent = nil
local function send_position()
  if not S.role or not S.code then return end
  local w = try(game.world.get)
  my_scene = scene_of(w)
  local text = "-"
  if my_scene then
    local p = try(game.player and game.player.get)
    if p and p.position then
      text = string.format("%s %s %s %.1f %.1f %.1f %.3f %d", my_scene, p.town_character or p.character,
                           tostring(p.weapon and p.weapon.item_no or "-"), p.position.x, p.position.y, p.position.z,
                           p.heading or 0, p.motion or 0)
    elseif last_sent and last_sent:sub(1, #my_scene + 1) == my_scene .. " " then
      text = last_sent -- in a menu or a talk: still standing there
    end
  end
  if text == "-" and last_sent == "-" then return end -- out of the dungeon it is said once
  last_sent = text
  send("all", "P", text)
end

-- The room's floors: the same seed for a floor in every game in the room.
local function floor_seed(dungeon, floor)
  local h = 5381
  for c in (tostring(S.code) .. ":" .. dungeon .. ":" .. floor):gmatch(".") do h = (h * 33 + c:byte()) % 2147483647 end
  return h
end
moonmod.on("game.dungeon.generating", function(e)
  if not (S.role and S.code and type(e) == "table") or e.back_floor then return end
  try(game.dungeons and game.dungeons.set_seed, {seed = floor_seed(e.dungeon_id or 0, e.floor_id or 0)})
end)

-- Monsters: the host's -------------------------------------------------------------------------------------------
-- The host's game runs a floor's monsters for everyone. There they see every player on the floor and go for the
-- nearest; a blow, shot or spell that lands on another player comes back from monsters.mirror_get and goes to that player's game
-- ("D damage kind flags"), which takes it as a monster's blow (combat.strike_player), guard and dodge and all. Fifteen
-- times a second the host sends where its monsters are ("M scene slot,kind,state,hp,max_hp,x,y,z,heading,motion;..."),
-- and a guest on that floor makes its own monsters copies of them (monsters.puppet_set): they stand, move and die as
-- the host's do. A guest's blow on one (puppet_set returns them) goes to the host ("H slot damage"), whose monster
-- takes it.

local MIRROR_EVERY = 4    -- frames between the host's monster reports
local mon = {puppets = false, scene = nil, said_none = false}

function mon.peer_with_avatar(slot)
  for peer, o in pairs(others) do if o.slot == slot then return peer end end
  return nil
end

function mon.host_step()
  if not on_floor() then
    -- off the floors: the guests' copies are theirs again
    if not mon.said_none then send("all", "M", "- -") end
    mon.said_none = true
    return
  end
  mon.said_none = false
  local anyone = false
  for _, o in pairs(others) do if o.slot then anyone = true break end end
  if not anyone then return end
  local got = try(game.monsters and game.monsters.mirror_get)
  if type(got) ~= "table" then return end
  local parts = {}
  for _, m in ipairs(got.monsters or {}) do
    parts[#parts + 1] = string.format("%d,%d,%d,%d,%d,%.1f,%.1f,%.1f,%.3f,%d", m.slot, m.kind, m.state, m.hp, m.max_hp,
                                      m.x, m.y, m.z, m.heading, m.motion)
  end
  send("all", "M", my_scene .. " " .. (#parts > 0 and table.concat(parts, ";") or "-"))
  for _, hit in ipairs(got.hits or {}) do
    local peer = mon.peer_with_avatar(hit.avatar)
    if peer then send(peer, "D", string.format("%d %d %d", hit.damage, hit.kind or 0, hit.flags or 0)) end
  end
end

function mon.release()
  if mon.puppets then try(game.monsters and game.monsters.puppet_clear) end
  mon.puppets = false
end

function mon.hear(peer, rest)
  if S.role ~= "guest" or peer ~= 0 then return end
  local scene, list = rest:match("^(%S+) (%S+)$")
  if not scene or scene ~= my_scene then mon.release() return end
  local monsters = {}
  if list ~= "-" then
    for item in list:gmatch("[^;]+") do
      local f = {}
      for v in item:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
      if #f == 10 then
        monsters[#monsters + 1] = {slot = math.floor(f[1]), kind = math.floor(f[2]), state = math.floor(f[3]),
                                   hp = math.floor(f[4]), max_hp = math.floor(f[5]), x = f[6], y = f[7], z = f[8],
                                   heading = f[9], motion = math.floor(f[10])}
      end
    end
  end
  local got = try(game.monsters and game.monsters.puppet_set, {monsters = monsters})
  if got then
    mon.puppets = true
    mon.scene = scene
    -- every blow this guest landed on a copy (a weapon's, a bomb's, a thrown item's) goes to the host's monster
    for _, hit in ipairs(type(got) == "table" and got.hits or {}) do
      send(0, "H", string.format("%d %d", hit.slot, math.floor(hit.damage)))
    end
  end
end

-- A guest's blow on a copy of the host's monster: the host's takes it.
function mon.hit_on_host(peer, rest)
  local o = others[peer]
  if not (o and o.scene and o.scene == my_scene) then return end
  local slot, damage = rest:match("^(%d+) (%d+)$")
  if slot then try(game.monsters and game.monsters.mirror_hit, {slot = tonumber(slot), damage = tonumber(damage)}) end
end

-- The host's monster struck this guest.
function mon.struck(rest)
  local damage, kind, flags = rest:match("^(%d+) (%-?%d+) (%-?%d+)$")
  local p = try(game.player and game.player.get)
  if not (damage and my_scene and p and p.position) then return end
  -- kind as the host's hit list has it: 2 a small hit (a flinch), 3 or 4 a blow (a knock-back)
  try(game.combat and game.combat.strike_player, {x = p.position.x, y = p.position.y + 8, z = p.position.z, radius = 12,
      damage = math.min(9999, tonumber(damage)), kind = tonumber(kind) >= 3 and "heavy" or "light"})
end

function mon.tick()
  if S.role == "host" and S.frame % MIRROR_EVERY == 0 then mon.host_step() end
  -- A host that stops sending (paused, in a menu) leaves its monsters held where they are; a guest who leaves the
  -- floor has its own monsters on the next.
  if S.role == "guest" and mon.puppets and (mon.scene ~= my_scene or not on_floor()) then mon.release() end
end

-- Doors: opened for everyone ----------------------------------------------------------------------------------------
-- A script that changes the floor without leaving it (a door or gate opens, a switch turns) comes from
-- dungeons.shared_events_get and goes to the others ("E scene script mode ext px py pz dx dy dz"); a game on that floor
-- runs it there (dungeons.shared_event_run) once its player is free, the key it asks for taken as given. Each game
-- keeps the floor's opened doors and hands them to a player who arrives later, so the floor is the same for everyone.

local door = {log = {}, done = {}, waiting = {}}

function door.key(scene, text) return scene .. "|" .. text:match("^(%S+ %S+ %S+ %S+ %S+)") end

function door.remember(scene, text)
  local key = door.key(scene, text)
  if door.done[key] then return false end
  door.done[key] = true
  door.log[scene] = door.log[scene] or {}
  table.insert(door.log[scene], text)
  return true
end

function door.step()
  if not on_floor() then return end
  local got = try(game.dungeons and game.dungeons.shared_events_get)
  for _, e in ipairs(type(got) == "table" and got.events or {}) do
    if my_scene then
      local text = string.format("%d %d %d %.2f %.2f %.2f %.2f %.2f %.2f", e.script, e.mode, e.ext,
                                 e.pos[1], e.pos[2], e.pos[3], e.dir[1], e.dir[2], e.dir[3])
      door.remember(my_scene, text)
      send("all", "E", my_scene .. " " .. text)
    end
  end
  -- a player newly on this floor gets the doors already open here
  for peer, o in pairs(others) do
    if o.scene and o.scene == my_scene and o.doors_for ~= my_scene then
      o.doors_for = my_scene
      for _, text in ipairs(door.log[my_scene] or {}) do send(peer, "E", my_scene .. " " .. text) end
    elseif o.scene ~= my_scene then
      o.doors_for = nil
    end
  end
  -- one waits at a time in the game: the next goes when it is taken
  while door.waiting[1] and door.waiting[1].scene ~= my_scene do table.remove(door.waiting, 1) end -- left that floor
  local nextone = door.waiting[1]
  if nextone then
    local f = {}
    for v in nextone.text:gmatch("%S+") do f[#f + 1] = tonumber(v) end
    local ok, err = call(game.dungeons and game.dungeons.shared_event_run,
                         {script = f[1], mode = f[2], ext = f[3], pos = {f[4], f[5], f[6]}, dir = {f[7], f[8], f[9]}})
    if ok or not tostring(errmsg(err)):find("busy") then table.remove(door.waiting, 1) end
  end
end

function door.hear(rest)
  local scene, text = rest:match("^(%S+) (.+)$")
  if not scene or select(2, text:gsub("%S+", "")) ~= 9 then return end
  if scene ~= my_scene or not door.remember(scene, text) then return end -- elsewhere, or opened here already
  table.insert(door.waiting, {scene = scene, text = text})
end

-- Georama: the host's world -----------------------------------------------------------------------------------------
-- When a player leaves Georama's edit mode, their game sends that town (georama.town_export) to the host, which takes
-- it into its world and sends it on to everyone else; the host's own edits go straight out. Each game takes the town
-- (georama.town_import); a player walking in it is walked into it again, at the town's entrance, so no one stands in
-- a house that just went up. A town arriving while its player is busy in it (editing, a menu) waits and is tried again.

local TOWNS = {[0] = "Norune", "Matataki", "Queens", "Muska Lacka", "Yellow Drops"}
local editing_town = nil
local waiting_towns = {} -- town -> {data, from}

local function take_town(data, from)
  local town = tonumber(data:match("^DCT1(%d+):"))
  if not town then return end
  local ok, err = call(game.georama and game.georama.town_import, {town_id = town, data = data})
  if not ok then
    if errmsg(err):find("busy") then waiting_towns[town] = {data = data, from = from} end
    if not errmsg(err):find("busy") then moonmod.log("warn", "co-op town: " .. errmsg(err)) end
    return false
  end
  waiting_towns[town] = nil
  local who = from == 0 and "The host" or (S.players[from] and S.players[from].name) or "A player"
  if from ~= nil then toast(who .. " changed " .. (TOWNS[town] or "a town") .. (ok.reloaded and "; back to its entrance" or "")) end
  return true
end

local function town_from(peer, data)
  if S.role == "host" then
    -- the host's world takes it first, then everyone else gets it
    if take_town(data, peer) ~= false or waiting_towns[tonumber(data:match("^DCT1(%d+):"))] then
      for id in pairs(S.players) do if id ~= peer then send_pieces(id, "TOWN", data) end end
    end
  elseif peer == 0 then
    take_town(data, 0)
  end
end

-- Who is building where ("B town 1" on opening the editor, "B town 0" on leaving it): two building in one town are
-- told, since the last of them to leave keeps their changes.
local builders = {} -- peer -> town
local function name_of(peer)
  local o = others[peer]
  return (o and o.name) or (peer == 0 and "The host") or (S.players[peer] and S.players[peer].name) or "Another player"
end
local function warn_builders(town, peer)
  toast(name_of(peer) .. " is building in " .. (TOWNS[town] or "this town") ..
        " too: whoever leaves the editor last keeps their changes")
end
local function hear_builder(peer, rest)
  local town, on = rest:match("^(%d+) ([01])$")
  if not town then return end
  town = tonumber(town)
  builders[peer] = on == "1" and town or nil
  if on == "1" and editing_town == town then warn_builders(town, peer) end
end

local function watch_editing()
  local w = try(game.world.get)
  if type(w) == "table" and w.editing then
    if editing_town ~= w.town_map then
      editing_town = w.town_map
      send("all", "B", editing_town .. " 1")
      for peer, town in pairs(builders) do if town == editing_town then warn_builders(town, peer) end end
    end
    return
  end
  if editing_town == nil then return end
  local town = editing_town
  editing_town = nil
  send("all", "B", town .. " 0")
  local export = try(game.georama and game.georama.town_export, {town_id = town})
  if not (export and export.data) then return end
  if S.role == "host" then
    for id in pairs(S.players) do send_pieces(id, "TOWN", export.data) end
  elseif S.role == "guest" then
    send_pieces(0, "TOWN", export.data)
  end
end

-- A town that came while its player was busy is tried again (the host sent it on when it first came).
local function retry_towns()
  for _, w in pairs(waiting_towns) do take_town(w.data, w.from) end
end

local function stop(reason)
  try(game.net.leave)
  forget_all()
  mon.release()
  door.log, door.done, door.waiting = {}, {}, {}
  builders = {}
  if reason then toast("Co-op: " .. reason) end
  S.role, S.code, S.players, S.pieces, S.guest, S.names = nil, nil, {}, {}, nil, {}
  show_room()
end

-- Host --------------------------------------------------------------------------------------------------------------

local function host()
  if S.role then toast("Co-op: a room is already open (" .. tostring(S.code) .. ")") return end
  local session = try(game.session.get)
  if type(session) == "table" and session.kind ~= "story" then
    toast("Co-op: host from your own save, in a town or a dungeon")
    return
  end
  local ok, err = net_open("host", {})
  if not ok then toast("Co-op: can't host: " .. errmsg(err)) return end
  S.role = "host"
  toast("Co-op: opening a room...")
end

-- The town a guest arrives in: the host's, or the one its dungeon is reached from.
local function arrival_town()
  local w = try(game.world.get) or {}
  if w.context == "dungeon" and w.dungeon_id then return DUNGEON_TOWN[w.dungeon_id] or 0 end
  local map = tonumber(w.map_id)
  if map and map >= 0 and map <= 4 then return map end
  return 0
end

local function welcome(peer, hello)
  local id = type(hello) == "table" and hello.id
  if type(id) ~= "string" or not id:match("^[a-z0-9-]+$") then send(peer, "REFUSE", "your game sent no player id") return end
  local name = type(hello.name) == "string" and hello.name ~= "" and hello.name or ("Player " .. (peer + 1))
  S.players[peer] = {id = id, name = name}
  local world = try(game.save.world_export)
  if not world or not world.data then send(peer, "REFUSE", "the host's game can't share its world right now") return end
  local account = try(game.save.account_get, {id = id})
  send_pieces(peer, "WORLD", world.data)
  if type(account) == "table" and account.data then
    send_pieces(peer, "PLAYER", account.data)
    toast("Co-op: " .. name .. " is back")
  else
    send(peer, "NEW")
    toast("Co-op: " .. name .. " joins for the first time")
  end
  send(peer, "START", tostring(arrival_town()))
  show_room()
end

local function keep(peer, data)
  local player = S.players[peer]
  if not player then return end
  local ok, err = call(game.save.account_set, {id = player.id, name = player.name, data = data})
  if not ok then
    moonmod.log("warn", "co-op: keeping " .. player.name .. "'s things: " .. errmsg(err))
    return
  end
  if not player.kept_once then
    player.kept_once = true
    toast("Co-op: " .. player.name .. "'s things are kept; save your game to keep them for good")
  end
end

-- Guest -------------------------------------------------------------------------------------------------------------

local function join()
  if S.role then return end
  if not code:match("^[" .. LETTERS .. "]+$") or #code ~= 5 then
    S.status = "Set the room's five letters first."
    return
  end
  local ok, err = net_open("join", {code = code})
  if not ok then S.status = "Can't join: " .. errmsg(err):sub(1, 60) return end
  S.role = "guest"
  S.guest = {world = nil, player = nil, new = false, map = nil, started = false}
  S.status = "Joining " .. code .. "..."
end

-- Every piece of the host's answer has come: the visit begins.
local function begin_visit()
  local g = S.guest
  if not g or g.started or not g.world or not g.map or not (g.player or g.new) then return end
  g.started = true
  local ok, err = call(game.session.start, {visit = {world = g.world, player = g.player, map = g.map}})
  if not ok then
    S.status = "The visit could not start: " .. errmsg(err):sub(1, 60)
    stop()
    return
  end
  S.status = "Off to the host's world..."
  g.world, g.player = nil, nil -- the engine has them now
end

local function send_things()
  if S.role ~= "guest" or not (S.guest and S.guest.visiting) then return end
  local things = try(game.save.player_export)
  if things and things.data then send_pieces(0, "KEEP", things.data) end
end

-- Messages ----------------------------------------------------------------------------------------------------------

local function message(peer, data)
  local kind, rest = data:match("^(%u+) ?(.*)$")
  if not kind then return end
  if kind == "P" then hear_position(peer, rest) return end
  if kind == "N" then hear_name(peer, rest) return end
  if kind == "B" then hear_builder(peer, rest) return end
  if kind == "M" then mon.hear(peer, rest) return end
  if kind == "E" then door.hear(rest) return end
  if kind == "H" then if S.role == "host" then mon.hit_on_host(peer, rest) end return end
  if kind == "D" then if S.role == "guest" and peer == 0 then mon.struck(rest) end return end
  if kind == "TOWN" then
    local whole = take_piece(peer, kind, rest)
    if whole then town_from(peer, whole) end
    return
  end
  if S.role == "host" then
    if kind == "HELLO" then
      local id, name = rest:match("^(%S+) ?(.*)$")
      welcome(peer, {id = id, name = name})
    elseif kind == "KEEP" then
      local whole = take_piece(peer, kind, rest)
      if whole then keep(peer, whole) end
    end
  elseif S.role == "guest" and peer == 0 then
    local g = S.guest
    if kind == "WORLD" then g.world = take_piece(peer, kind, rest) or g.world
    elseif kind == "PLAYER" then g.player = take_piece(peer, kind, rest) or g.player
    elseif kind == "NEW" then g.new = true
    elseif kind == "START" then g.map = tonumber(rest)
    elseif kind == "REFUSE" then stop("the host turned the visit away: " .. rest) return
    end
    begin_visit()
  end
end

local function pump()
  if not S.role then return end
  local got = try(game.net.receive, {max = 64})
  for _, e in ipairs(got and got.events or {}) do
    if e.kind == "connected" then
      S.code = e.code
      S.me_peer = e.peer
      say_name("all")
      if S.role == "host" then
        toast("Co-op room " .. tostring(e.code) .. ": friends join with this code from the title screen")
      else
        -- "HELLO id name": the player id first, then the name, which may hold spaces
        send(0, "HELLO", me.id .. " " .. (my_name() or ""))
        S.status = "Joined " .. tostring(e.code) .. "; the host is sending their world..."
      end
      show_room()
    elseif e.kind == "joined" then
      if S.role == "host" then S.players[e.peer] = S.players[e.peer] or {id = nil, name = e.name} end
      show_room()
    elseif e.kind == "left" then
      local p = S.players[e.peer]
      S.players[e.peer] = nil
      forget(e.peer)
      builders[e.peer] = nil
      if S.role == "host" and p then toast("Co-op: " .. tostring(p.name or "a player") .. " left") end
      show_room()
    elseif e.kind == "message" then
      message(e.peer, e.data)
    elseif e.kind == "closed" then
      local visiting = S.role == "guest" and S.guest and S.guest.visiting
      S.status = "The room closed: " .. tostring(e.reason)
      stop("the room closed: " .. tostring(e.reason))
      -- The host's world went with the host: back to the title.
      if visiting then try(game.session.finish) end
    end
  end
end

-- Events ------------------------------------------------------------------------------------------------------------

moonmod.on("game.tick", function(e)
  S.frame = e and e.frame or S.frame + 1
  pump()
  if S.role and S.code and S.frame % SEND_EVERY == 0 then
    send_position()
    show_others()
  end
  if S.role and S.code then mon.tick() end
  if S.role and S.code and S.frame % 10 == 0 then door.step() end
  if S.role and S.code and S.frame % 30 == 0 then
    watch_editing()
    retry_towns()
  end
  if S.role == "guest" and S.guest and S.guest.visiting then
    local every = math.max(15, math.min(600, setting("keep_every", 60))) * 60
    if S.frame - S.kept_at >= every then
      S.kept_at = S.frame
      send_things()
    end
  end
end)

moonmod.on("game.session.started", function(e)
  if type(e) == "table" and e.kind == "visit" and e.owner == "moonmod.coop" and S.guest then
    S.guest.visiting = true
    S.kept_at = S.frame
    toast("Co-op: you are in the host's world. Your own saves stay as they are.")
  end
end)

moonmod.on("game.session.ended", function(e)
  if type(e) == "table" and e.kind == "visit" and S.role == "guest" then stop() end
end)

moonmod.on("game.session.failed", function(e)
  if type(e) == "table" and e.kind == "visit" then
    S.status = "The visit could not start: " .. tostring(e.reason):sub(1, 60)
    stop()
  end
end)

-- Leaving a visit: the things go to the host first, then the session ends.
local function leave()
  if S.role == "guest" and S.guest and S.guest.visiting then
    send_things()
    toast("Co-op: your things went to the host; leaving...")
    try(game.session.finish)
  elseif S.role then
    stop("you closed the room")
  end
end

-- Mod Manager actions and keys --------------------------------------------------------------------------------------

for _, a in ipairs({
  {"host", "Host a co-op room", "Open a room for friends to join with its code (F8)"},
  {"leave", "Leave or close co-op", "A guest's things go to the host first (F10)"},
}) do try(game.ui.register, {id = a[1], label = a[2], description = a[3]}) end
moonmod.on("ui.action", function(a)
  if not a then return end
  if a.id == "host" then host() elseif a.id == "leave" then leave() end
end)
try(game.input.bind, {id = "host_key", keys = {"F8"}})
try(game.input.bind, {id = "leave_key", keys = {"F10"}})
moonmod.on("game.tick", function()
  local h = try(game.input.consume, {id = "host_key"})
  if h and h.pressed then host() end
  local l = try(game.input.consume, {id = "leave_key"})
  if l and l.pressed then leave() end
end)

-- The title screen: Online Co-op ----------------------------------------------------------------------------------

local function page()
  local entries = {}
  for i = 1, 5 do
    entries[#entries + 1] = {id = "c" .. i, label = "Letter " .. i .. ":  " .. code:sub(i, i)}
  end
  entries[#entries + 1] = {id = "join", label = "Join room " .. code, enabled = not S.role}
  entries[#entries + 1] = {id = "clear", label = "Clear the code"}
  local lines = {
    "Join a friend's world with their room's five letters.",
    "Type the letters, or Cross on one steps it on, Square back.",
    S.status or ("You are " .. (my_name() or "nameless (set a name in the mod's settings)") .. "."),
  }
  -- which server: the public relay, or the private one the settings name (its host only)
  local server = setting("server", "")
  lines[#lines + 1] = server == "" and "Server: the public relay." or
                      ("Server: " .. (server:match("^wss?://([^/]+)") or server):sub(1, 48) .. " (private).")
  return {title = "ONLINE CO-OP", subtitle = "Visit a friend's Dark Cloud", root = true, hint = "", lines = lines,
          entries = entries}
end

local function show(cursor)
  local data = page()
  data.id = MODE
  data.cursor = cursor
  try(game.title.mode_set, data)
end

do
  local data = page()
  data.id, data.label = MODE, "Online Co-op"
  local ok, err = call(game.title.mode_register, data)
  if not ok then moonmod.log("warn", "co-op title mode: " .. errmsg(err)) end
end

local function step(i, way)
  local c = code:sub(i, i)
  local at = LETTERS:find(c, 1, true) or 0
  local nxt = LETTERS:sub((at - 1 + way) % #LETTERS + 1, (at - 1 + way) % #LETTERS + 1)
  code = code:sub(1, i - 1) .. nxt .. code:sub(i + 1)
  moonmod.storage.set("code", code)
end

-- Typing the code: on this page a letter or digit key fills the next letter, Backspace takes the last one back. (The
-- keyboard's E is also Square, which steps a letter back here: a Square while E is down is the typing's, not a step.)
local typing = {open = false, at = 1}
for i = 1, #LETTERS do
  local c = LETTERS:sub(i, i)
  try(game.input.bind, {id = "type_" .. c, keys = {c}})
end
try(game.input.bind, {id = "type_back", keys = {"Backspace"}})
moonmod.on("game.tick", function()
  for i = 1, #LETTERS do
    local c = LETTERS:sub(i, i)
    local key = try(game.input.consume, {id = "type_" .. c})
    if key and key.pressed and typing.open and not S.role then
      code = code:sub(1, typing.at - 1) .. c .. code:sub(typing.at + 1)
      moonmod.storage.set("code", code)
      typing.at = typing.at % 5 + 1
      show(code:find("-", 1, true) and typing.at - 1 or 5) -- all five typed: on Join
    end
  end
  local back = try(game.input.consume, {id = "type_back"})
  if back and back.pressed and typing.open and not S.role then
    typing.at = typing.at == 1 and 5 or typing.at - 1
    code = code:sub(1, typing.at - 1) .. "-" .. code:sub(typing.at + 1)
    moonmod.storage.set("code", code)
    show(typing.at - 1)
  end
end)
moonmod.on("game.session.started", function() typing.open = false end)

moonmod.on("game.title.opened", function()
  S.status = nil
  typing.open = true
  typing.at = code:find("-", 1, true) or 1
  show(0)
end)
moonmod.on("game.title.selected", function(e)
  local entry = e and e.entry
  local i = entry and tonumber(entry:match("^c(%d)$"))
  if entry == "back" then typing.open = false end
  if i and e.action == "square" then
    local held = try(game.input.state, {id = "type_E"})
    if held and held.down then show(typing.at - 1) return end
  end
  if i then
    typing.at = i
    step(i, e.action == "square" and -1 or 1)
    show(i - 1)
  elseif entry == "join" then
    join()
    show(5)
  elseif entry == "clear" then
    code = "-----"
    moonmod.storage.set("code", code)
    typing.at = 1
    show(0)
  end
end)
-- While waiting on the title page, the status line follows the join.
moonmod.on("game.tick", function()
  if S.role == "guest" and S.guest and not S.guest.visiting and S.frame % 30 == 0 then show(5) end
end)

-- For the tests: the state, and the pieces' size.
return {state = S, me = me, piece = PIECE}
