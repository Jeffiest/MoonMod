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

local PROTOCOL = 7
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
local function toast(message)
  try(game.ui.notify, {message = tostring(message):sub(1, 196), duration_frames = 300})
  moonmod.log("info", "toast " .. tostring(message):sub(1, 196)) -- in the log too, for bug reports and the live tests
end
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
local S = {role = nil, code = nil, players = {}, pieces = {}, guest = nil, frame = 0, kept_at = 0, names = {}, guest_mods = {}}
local code = moonmod.storage.get("code") or "-----" -- the code being typed on the title page
-- A live test run (tools/tests/coop/live) puts its wishes here: {role = "host"|"guest", code?, follow?, where?, at?}. Players never
-- have it: nothing but that harness writes this storage key.
local AUTOTEST = moonmod.storage.get("autotest")
if type(AUTOTEST) ~= "table" then AUTOTEST = nil end

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
  -- everyone in the room: the host knows its guests, a guest the players it has heard from
  local count, seen = 1, {}
  for peer in pairs(S.players) do seen[peer] = true end
  for peer in pairs(S.names) do seen[peer] = true end
  for _ in pairs(seen) do count = count + 1 end
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
    -- in transit (the floor select, a floor not built yet): nowhere yet, so no one is offered to follow there
    if not w.floor_id or w.floor_id < 0 or not w.floor_seed or w.floor_seed == 0 then return nil end
    return string.format("D%d:%d:%s", w.dungeon_id, w.floor_id, tostring(w.floor_seed))
  end
  if w.town_map then return "T" .. w.town_map end -- walking (or in a menu) in a town
  if w.map_no then return "H" .. w.map_no end     -- a house (or another of a town's maps)
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
  local moved = o.scene ~= scene
  o.scene = scene
  if moved and S.moved then S.moved(peer, scene) end
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

-- A new place counts once the player has stood there SETTLE frames, playing (where the game says so): changing floors
-- passes through a floor that is only loading (its number and seed not settled), and no one should follow there.
local SETTLE = 30
local settling = {scene = nil, since = 0}
local function settled_scene(w)
  local scene = scene_of(w)
  if scene == nil or scene == my_scene then settling.scene = nil return scene end
  if scene:sub(1, 1) == "D" and type(w) == "table" and w.walking == false then settling.scene = nil return nil end
  if settling.scene ~= scene then settling.scene, settling.since = scene, S.frame end
  if S.frame - settling.since < SETTLE then return nil end
  settling.scene = nil
  return scene
end

local last_sent = nil
local function send_position()
  if not S.role or not S.code then return end
  local w = try(game.world.get)
  my_scene = settled_scene(w)
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
  local alive = 0
  for _, m in ipairs(got.monsters or {}) do if m.hp > 0 then alive = alive + 1 end end
  mon.count = alive -- for the live tests' report
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
  local alive = 0
  for _, m in ipairs(monsters) do if m.hp > 0 then alive = alive + 1 end end
  mon.count = alive -- for the live tests' report
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
  if not setting("shared_doors", true) then
    try(game.dungeons and game.dungeons.shared_events_get) -- this game's are kept to itself
    door.waiting = {}
    return
  end
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

-- The clock: the host's ------------------------------------------------------------------------------------------
-- Every ten seconds the host sends where its day is ("C fraction"); a guest whose clock has drifted from it is set to
-- it (world.set_time), so the towns' light and their people's hours match.
local CLOCK_EVERY = 600
local function send_clock()
  local w = try(game.world.get)
  if type(w) == "table" and type(w.time) == "table" and w.time.fraction then
    send("all", "C", string.format("%.4f", w.time.fraction))
  end
end
local function hear_clock(rest)
  local host = tonumber(rest)
  local w = try(game.world.get)
  if not host or host < 0 or host >= 1 or type(w) ~= "table" or type(w.time) ~= "table" or not w.time.fraction then return end
  local drift = math.abs(host - w.time.fraction)
  if math.min(drift, 1 - drift) > 0.005 then try(game.world.set_time, {fraction = host}) end
end

-- Together: joining each other, and giving -------------------------------------------------------------------------
-- When another player goes somewhere else (another dungeon floor, town or house), a panel asks this player whether to
-- join them there (setting "follow_offers"); joining walks them in (dungeons.enter_floor, world.enter_map). And any
-- player can give another Gilda or items from their bag (F7, or the Mod Manager's "Give to a player"): whom, what,
-- how much. The giver's game takes it first, then sends it ("V g amount" / "V i id count name"); the other game puts it
-- in its wallet or bag and sends back whatever didn't fit ("V back ..."), which comes back to the giver.

local DUNGEONS = {[0] = "Divine Beast Cave", "Wise Owl Forest", "Shipwreck", "Sun and Moon Temple", "Moon Sea",
                  "Gallery of Time", "Demon Shaft"}
local TOWN_NAMES = {[0] = "Norune", "Matataki", "Queens", "Muska Lacka", "Yellow Drops"}
local together = {queue = {}, open = nil}

function together.name(peer)
  local o = others[peer]
  return (o and o.name) or S.names[peer] or (peer == 0 and "The host") or ("Player " .. tostring(peer))
end

function together.place(scene)
  local d, f = scene:match("^D(%d+):(%-?%d+):")
  if d then return string.format("%s, floor %d", DUNGEONS[tonumber(d)] or "a dungeon", tonumber(f) + 1) end
  local t = scene:match("^T(%d+)$")
  if t then return TOWN_NAMES[tonumber(t)] or "a town" end
  if scene:match("^H%d+$") then return "a house" end
  return "somewhere"
end

-- One panel at a time, in turn (a follow offer, a step of a gift).
function together.ask(panel) table.insert(together.queue, panel) end
function together.tick()
  if together.open or not together.queue[1] then return end
  local p = table.remove(together.queue, 1)
  if p.still and not p.still() then return end -- stale (they moved on, or we're there already)
  if AUTOTEST and p.follow then
    local yes = AUTOTEST.follow ~= false
    moonmod.log("info", "COOPTEST offer " .. p.title .. (yes and " -> join" or " -> stay"))
    if yes and p.options[1].pick then p.options[1].pick() end
    return
  end
  local cards = {}
  for i, o in ipairs(p.options) do cards[i] = {title = o.title:sub(1, 48), subtitle = o.subtitle and o.subtitle:sub(1, 64) or nil} end
  local ok, err = call(game.ui.choice_open, {id = "coop_together", title = p.title:sub(1, 64), subtitle = p.subtitle and p.subtitle:sub(1, 96) or nil,
                                          cancel = true, town = true, options = cards})
  if ok then together.open = p else moonmod.log("warn", "co-op panel: " .. errmsg(err)) end
end
moonmod.on("ui.choice_made", function(e)
  if type(e) ~= "table" or not tostring(e.id or ""):find("coop_together", 1, true) or not together.open then return end
  local p = together.open
  together.open = nil
  local option = not e.cancelled and e.index and p.options[e.index] or nil
  if option and option.pick then option.pick() end
end)

-- Following -----------------------------------------------------------------------------------------------------------
-- A join the game can't do yet (busy: a talk, a menu, a floor still loading) waits and is tried again for a while.
local JOIN_WAIT = 1800 -- frames: half a minute
function together.join(peer, scene, waiting)
  local o = others[peer]
  if not (o and o.scene == scene) then
    if not waiting then toast("Co-op: " .. together.name(peer) .. " has moved on") end
    together.waiting = nil
    return
  end
  local ok, err
  local d, f = scene:match("^D(%d+):(%-?%d+):")
  if d then
    -- arrive beside them (their cell, 160 units to a cell), in the escape light rather than down the stairs; a cell
    -- that can't be stood on falls back to the stairs
    local at = o.state
    local where = {dungeon_id = tonumber(d), floor_id = tonumber(f)}
    if at and at.x and at.z and (at.x ~= 0 or at.z ~= 0) then
      where.x, where.y, where.teleport = math.floor(at.x / 160 + 0.5), math.floor(at.z / 160 + 0.5), true
    end
    ok, err = call(game.dungeons and game.dungeons.enter_floor, where)
    if not ok and where.x and not errmsg(err):find("busy", 1, true) then
      ok, err = call(game.dungeons.enter_floor, {dungeon_id = where.dungeon_id, floor_id = where.floor_id})
    end
  else
    local map = tonumber(scene:match("^[TH](%d+)$"))
    if map then ok, err = call(game.world and game.world.enter_map, {map_no = map}) end
  end
  if ok then together.waiting = nil return end
  local why = errmsg(err)
  local busy = why:find("busy", 1, true) or why:find("not in a dungeon or a town", 1, true)
  if busy and not waiting then
    together.waiting = {peer = peer, scene = scene, since = S.frame}
    toast("Co-op: joining " .. together.name(peer) .. " as soon as you're free")
  elseif busy and S.frame - waiting.since < JOIN_WAIT then
    return -- still busy: tried again shortly
  else
    together.waiting = nil
    toast("Co-op: can't go there right now (" .. why:sub(1, 80) .. ")")
  end
end
function together.retry()
  local w = together.waiting
  if w and S.frame % 30 == 0 then together.join(w.peer, w.scene, w) end
end

function S.moved(peer, scene)
  if not scene or scene == my_scene or not setting("follow_offers", true) then return end
  -- a guest still on the title page (its visit not begun) has nowhere to follow from
  if S.role == "guest" and not (S.guest and S.guest.visiting) then return end
  -- one offer per player: a newer move replaces one not yet shown
  for i = #together.queue, 1, -1 do
    if together.queue[i].follow == peer then table.remove(together.queue, i) end
  end
  local who = together.name(peer)
  together.ask({
    follow = peer, title = who .. " went to " .. together.place(scene), subtitle = "Join them there?",
    still = function() local o = others[peer]; return o ~= nil and o.scene == scene and scene ~= my_scene end,
    options = {
      {title = "Join " .. who, subtitle = together.place(scene), pick = function() together.join(peer, scene) end},
      {title = "Stay here", subtitle = "You can follow later from the Mod Manager"},
    },
  })
end

-- Joining a player from the Mod Manager: whoever is somewhere else, by name and place.
function together.follow_menu()
  if not (S.role and S.code) then toast("Co-op: join or host a room first") return end
  local options = {}
  for peer, o in pairs(others) do
    if o.scene and o.scene ~= my_scene then
      local scene = o.scene
      options[#options + 1] = {title = together.name(peer), subtitle = together.place(scene), pick = function() together.join(peer, scene) end}
    end
  end
  if #options == 0 then toast("Co-op: everyone is here, or nowhere to join yet") return end
  together.ask({title = "Join whom?", options = options})
end

-- Giving -------------------------------------------------------------------------------------------------------------
local function peers_here()
  local ids, seen = {}, {}
  for peer in pairs(S.names) do if not seen[peer] then seen[peer] = true; ids[#ids + 1] = peer end end
  for peer in pairs(S.players) do if not seen[peer] then seen[peer] = true; ids[#ids + 1] = peer end end
  table.sort(ids)
  return ids
end
together.peers = peers_here

local function wallet()
  local w = try(game.economy and game.economy.get)
  return type(w) == "table" and tonumber(w.amount) or 0
end

function together.give_gilda(peer, amount)
  local spent = 0
  while spent < amount do
    local chunk = math.min(32767, amount - spent)
    if not try(game.economy.spend, {amount = chunk}) then break end
    spent = spent + chunk
  end
  if spent <= 0 then toast("Co-op: you don't have that much Gilda") return end
  send(peer, "V", "g " .. spent)
  toast(string.format("Co-op: you gave %s %d Gilda", together.name(peer), spent))
end

function together.give_item(peer, item, count)
  local got = try(game.items.remove, {id = item.id, count = count})
  local removed = type(got) == "table" and tonumber(got.removed) or 0
  if removed <= 0 then toast("Co-op: you no longer have " .. item.name) return end
  send(peer, "V", string.format("i %s %d %s", item.id, removed, item.name))
  toast(string.format("Co-op: you gave %s %d x %s", together.name(peer), removed, item.name))
end

function together.pick_count(peer, item)
  local options, seen = {}, {}
  for _, n in ipairs({1, 5, 10, item.count}) do
    if n <= item.count and not seen[n] then
      seen[n] = true
      options[#options + 1] = {title = n == item.count and ("All " .. n) or tostring(n),
                               pick = function() together.give_item(peer, item, n) end}
    end
  end
  together.ask({title = "How many " .. item.name .. "?", subtitle = "You have " .. item.count, options = options})
end

function together.pick_item(peer, page)
  local got = try(game.items.owned)
  local items = type(got) == "table" and got.items or {}
  if #items == 0 then toast("Co-op: your bag is empty") return end
  local first = (page - 1) * 5 + 1
  local options = {}
  for i = first, math.min(#items, first + 4) do
    local item = items[i]
    options[#options + 1] = {title = item.name, subtitle = "x" .. item.count, pick = function() together.pick_count(peer, item) end}
  end
  if #items > first + 4 then
    options[#options + 1] = {title = "More...", subtitle = "The next items", pick = function() together.pick_item(peer, page + 1) end}
  end
  together.ask({title = "Give " .. together.name(peer) .. " which item?", options = options})
end

function together.pick_gilda(peer)
  local have = wallet()
  if have <= 0 then toast("Co-op: you have no Gilda to give") return end
  local options = {}
  for _, n in ipairs({100, 500, 1000, 5000, 10000}) do
    if n < have then options[#options + 1] = {title = n .. " Gilda", pick = function() together.give_gilda(peer, n) end} end
  end
  options[#options + 1] = {title = "All " .. have .. " Gilda", pick = function() together.give_gilda(peer, have) end}
  together.ask({title = "Give " .. together.name(peer) .. " how much?", subtitle = "You have " .. have .. " Gilda", options = options})
end

function together.pick_what(peer)
  together.ask({title = "Give " .. together.name(peer) .. "...", options = {
    {title = "Gilda", subtitle = "You have " .. wallet(), pick = function() together.pick_gilda(peer) end},
    {title = "An item", subtitle = "From your bag", pick = function() together.pick_item(peer, 1) end},
  }})
end

function together.give()
  if not (S.role and S.code) then toast("Co-op: join or host a room first") return end
  local ids = peers_here()
  if #ids == 0 then toast("Co-op: no one else is in the room") return end
  if #ids == 1 then together.pick_what(ids[1]) return end
  local options = {}
  for _, peer in ipairs(ids) do
    options[#options + 1] = {title = together.name(peer), pick = function() together.pick_what(peer) end}
  end
  together.ask({title = "Give to whom?", options = options})
end

-- Receiving (and taking back what didn't fit)
function together.hear(peer, rest)
  local back, kind, tail = rest:match("^(back) (%a) (.+)$")
  if not back then kind, tail = rest:match("^(%a) (.+)$") end
  if kind == "g" then
    local amount = math.floor(tonumber(tail) or 0)
    if amount <= 0 or amount > 1000000 then return end
    local before, left = wallet(), amount
    while left > 0 do
      local chunk = math.min(32767, left)
      if not try(game.economy.add, {amount = chunk}) then break end
      left = left - chunk
    end
    local got = wallet() - before
    if back then toast(string.format("Co-op: %d Gilda came back (their wallet was full)", got)) return end
    if got < amount then send(peer, "V", "back g " .. (amount - got)) end
    toast(string.format("Co-op: %s gave you %d Gilda%s", together.name(peer), got, got < amount and " (your wallet is full)" or ""))
  elseif kind == "i" then
    local id, count, name = tail:match("^(%S+) (%d+) ?(.*)$")
    count = tonumber(count)
    if not id or not count or count <= 0 or count > 999 then return end
    local got = try(game.items.give, {id = id, count = count})
    local added = type(got) == "table" and tonumber(got.added) or 0
    name = name ~= "" and name or id
    if back then toast(string.format("Co-op: %d x %s came back (their bag was full)", added, name)) return end
    if added < count then send(peer, "V", string.format("back i %s %d %s", id, count - added, name)) end
    toast(string.format("Co-op: %s gave you %d x %s%s", together.name(peer), added, name, added < count and " (your bag is full)" or ""))
  end
end

-- Georama: the host's world -----------------------------------------------------------------------------------------
-- When a player leaves Georama's edit mode, their game sends that town (georama.town_export) to the host, which takes
-- it into its world and sends it on to everyone else; the host's own edits go straight out. Each game takes the town
-- (georama.town_import); a player walking in it is walked into it again, at the town's entrance, so no one stands in
-- a house that just went up. A town arriving while its player is busy in it (editing, a menu) waits and is tried again.

local TOWNS = {[0] = "Norune", "Matataki", "Queens", "Muska Lacka", "Yellow Drops"}
local editing_town = nil
local editing_base = nil  -- that town when the editor opened
local waiting_towns = {} -- town -> {data, from}

local function take_town(data, from, base)
  local town = tonumber(data:match("^DCT1(%d+):"))
  if not town then return end
  if not base then
    -- already so here (the merged town coming back to the one who built it): nothing to take, no walk back
    local now = try(game.georama and game.georama.town_export, {town_id = town})
    if now and now.data == data then waiting_towns[town] = nil return true end
  end
  local ok, err = call(game.georama and game.georama.town_import, {town_id = town, data = data, base = base})
  if not ok then
    if errmsg(err):find("busy") then waiting_towns[town] = {data = data, from = from, base = base} end
    if not errmsg(err):find("busy") then moonmod.log("warn", "co-op town: " .. errmsg(err)) end
    return false
  end
  waiting_towns[town] = nil
  local who = from == 0 and "The host" or (S.players[from] and S.players[from].name) or "A player"
  if from ~= nil then toast(who .. " changed " .. (TOWNS[town] or "a town") .. (ok.reloaded and "; back to its entrance" or "")) end
  return true
end

-- A guest's edit comes with the town as it was when they opened the editor ("edited\nbase"): the host merges only
-- what they changed into its own town (georama.town_import with base), so two building at once both keep their work,
-- and sends the merged town to everyone, the editor too. The host's word is the whole town.
local function send_merged(town)
  local export = try(game.georama and game.georama.town_export, {town_id = town})
  if not (export and export.data) then return end
  for id in pairs(S.players) do send_pieces(id, "TOWN", export.data) end
end

local function town_from(peer, payload)
  local cut = payload:find("\n", 1, true)
  local data = cut and payload:sub(1, cut - 1) or payload
  local base = cut and payload:sub(cut + 1) or nil
  local town = tonumber(data:match("^DCT1(%d+):"))
  if S.role == "host" then
    if take_town(data, peer, base) and town then send_merged(town) end
  elseif peer == 0 then
    take_town(data, 0)
  end
end

-- Who is building where ("B town 1" on opening the editor, "B town 0" on leaving it): two building in one town are
-- told, since where both change the same plot, chip or building the last to leave wins.
local builders = {} -- peer -> town
local function name_of(peer)
  local o = others[peer]
  return (o and o.name) or (peer == 0 and "The host") or (S.players[peer] and S.players[peer].name) or "Another player"
end
local function warn_builders(town, peer)
  toast(name_of(peer) .. " is building in " .. (TOWNS[town] or "this town") ..
        " too: you both keep your work, but where you change the same spot the last to leave wins")
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
      -- the town as it is now: what this player changes is measured from it
      local start = try(game.georama and game.georama.town_export, {town_id = editing_town})
      editing_base = start and start.data or nil
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
    send_pieces(0, "TOWN", export.data .. (editing_base and ("\n" .. editing_base) or ""))
  end
  editing_base = nil
end

-- A town that came while its player was busy is tried again (the host sent it on when it first came).
local function retry_towns()
  for town, w in pairs(waiting_towns) do
    if take_town(w.data, w.from, w.base) and S.role == "host" and w.base then send_merged(town) end
  end
end

-- The room's mods ---------------------------------------------------------------------------------------------------
-- Every game in a room plays the same mods at the same versions, and the guests play them with the host's settings.
-- A mod's manifest says where it belongs (its "coop" key, through game.mods.list):
--   "required"   (the default) every player has it enabled at the host's version; the host's settings apply to all
--   "host_only"  only the host needs it (its state lives in the host's save); a guest may have it or not
--   "local"      each player's own (controls, the camera, autosave): never asked for, never sent
-- The guest says its mods first ("MODS id version role;..."), then hello. The host compares: anything missing, at
-- another version, or a world-changing mod the host doesn't play is sent back as "NEEDMODS" (one "what\tid\tversion
-- \tname" a line: what is enable, version or disable), and the world is not sent. Otherwise "SETTINGS" (the host's
-- values for its required mods, one "id\tkey\tvalue" a line, value typed "b:", "i:", "n:" or "s:") comes before the
-- world, and the guest's game holds them for the visit only (game.mods.settings_overlay): never saved, dropped when
-- the visit ends. A guest turned away keeps the list (storage "needed") and the title page shows it until it joins.
local rm = {}

function rm.loaded()
  local got = try(game.mods and game.mods.list)
  if type(got) ~= "table" or type(got.mods) ~= "table" then return nil end
  local out = {}
  for _, m in ipairs(got.mods) do
    if type(m) == "table" and type(m.id) == "string" then
      local role = m.coop
      if role ~= "host_only" and role ~= "local" then role = "required" end
      out[m.id] = {id = m.id, version = tostring(m.version or "?"), name = tostring(m.name or m.id), role = role}
    end
  end
  return out
end

function rm.encode_list(mods)
  local parts = {}
  for id, m in pairs(mods) do parts[#parts + 1] = id .. " " .. m.version .. " " .. m.role end
  table.sort(parts)
  return table.concat(parts, ";")
end

function rm.decode_list(text)
  local out = {}
  for entry in tostring(text):gmatch("[^;]+") do
    local id, version, role = entry:match("^(%S+) (%S+) (%S+)$")
    if id then out[id] = {id = id, version = version, role = role} end
  end
  return out
end

-- What the guest must change before it can join: a list of {what, id, version, name}, sorted, empty when none.
function rm.compare(host_mods, guest_mods)
  local need = {}
  for id, m in pairs(host_mods) do
    if m.role == "required" then
      local g = guest_mods[id]
      if not g then need[#need + 1] = {what = "enable", id = id, version = m.version, name = m.name}
      elseif g.version ~= m.version then need[#need + 1] = {what = "version", id = id, version = m.version, name = m.name, have = g.version} end
    end
  end
  for id, g in pairs(guest_mods) do
    if g.role == "required" and not host_mods[id] then
      need[#need + 1] = {what = "disable", id = id, version = g.version, name = id}
    end
  end
  table.sort(need, function(a, b) if a.what ~= b.what then return a.what < b.what end return a.id < b.id end)
  return need
end

local function clean(text) return (tostring(text):gsub("[\t\n]", " ")) end

function rm.encode_need(need)
  local lines = {}
  for _, n in ipairs(need) do
    lines[#lines + 1] = table.concat({n.what, n.id, n.version, clean(n.name)}, "\t")
  end
  return table.concat(lines, "\n")
end

function rm.decode_need(text)
  local out = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local what, id, version, name = line:match("^(%a+)\t([^\t]+)\t([^\t]+)\t(.*)$")
    if what then out[#out + 1] = {what = what, id = id, version = version, name = name} end
  end
  return out
end

local function escape(s) return (s:gsub("[%%\t\n]", function(c) return string.format("%%%02X", c:byte()) end)) end
local function unescape(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

function rm.encode_value(v)
  if type(v) == "boolean" then return "b:" .. tostring(v) end
  if type(v) == "number" then
    if math.type and math.type(v) == "integer" then return "i:" .. tostring(v) end
    return "n:" .. string.format("%.17g", v)
  end
  if type(v) == "string" then return "s:" .. escape(v) end
  return nil
end

function rm.decode_value(text)
  local t, rest = tostring(text):match("^(%a):(.*)$")
  if t == "b" then return rest == "true" end
  if t == "i" then return math.tointeger and math.tointeger(tonumber(rest)) or tonumber(rest) end
  if t == "n" then return tonumber(rest) end
  if t == "s" then return unescape(rest) end
  return nil
end

-- The host's settings for the mods every guest plays (its own, this mod, stay each player's).
function rm.host_settings(host_mods)
  local lines, ids = {}, {}
  for id, m in pairs(host_mods) do if m.role == "required" and id ~= "moonmod.coop" then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local got = try(game.mods.settings_get, {id = id})
    local values = type(got) == "table" and got.values or nil
    if type(values) == "table" then
      local keys = {}
      for k in pairs(values) do keys[#keys + 1] = k end
      table.sort(keys)
      for _, k in ipairs(keys) do
        local v = rm.encode_value(values[k])
        if v then lines[#lines + 1] = id .. "\t" .. k .. "\t" .. v end
      end
    end
  end
  return table.concat(lines, "\n")
end

-- A guest takes the host's settings for the visit. Returns how many mods took them.
rm.overlaid = false
function rm.apply_settings(text)
  local by_mod = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local id, key, value = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
    if id and id ~= "moonmod.coop" then
      local v = rm.decode_value(value)
      if v ~= nil then by_mod[id] = by_mod[id] or {}; by_mod[id][key] = v end
    end
  end
  local count = 0
  for id, values in pairs(by_mod) do
    local ok, err = call(game.mods and game.mods.settings_overlay, {id = id, values = values})
    if ok then count = count + 1; rm.overlaid = true
    else moonmod.log("warn", "co-op: the host's settings for " .. id .. ": " .. errmsg(err)) end
  end
  return count
end

function rm.clear_settings()
  if not rm.overlaid then return end
  rm.overlaid = false
  try(game.mods and game.mods.settings_overlay_clear, {})
end

-- The list a turned-away guest keeps, struck off as this game's mods come to match it.
function rm.needed()
  local kept = moonmod.storage.get("needed")
  if type(kept) ~= "table" or type(kept.list) ~= "table" or #kept.list == 0 then return nil end
  local mods = rm.loaded() or {}
  local left = {}
  for _, n in ipairs(kept.list) do
    local have = mods[n.id]
    local done
    if n.what == "disable" then done = not (have and have.role == "required")
    else done = have ~= nil and have.version == n.version end
    if not done then left[#left + 1] = n end
  end
  return left, kept.code
end

function rm.describe(n)
  if n.what == "enable" then return "enable " .. n.name .. " " .. n.version end
  if n.what == "version" then return n.name .. ": version " .. n.version .. " needed" end
  return "disable " .. n.name
end

function rm.summary(list)
  local parts = {}
  for _, n in ipairs(list) do parts[#parts + 1] = rm.describe(n) end
  return table.concat(parts, "; ")
end

local function stop(reason)
  rm.clear_settings()
  try(game.net.leave)
  forget_all()
  mon.release()
  door.log, door.done, door.waiting = {}, {}, {}
  builders = {}
  if reason then toast("Co-op: " .. reason) end
  S.role, S.code, S.players, S.pieces, S.guest, S.names, S.guest_mods = nil, nil, {}, {}, nil, {}, {}
  together.queue = {}
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
  -- the room's mods first: a guest without them is sent the list instead of the world
  local host_mods = rm.loaded()
  if host_mods then
    local guest_mods = S.guest_mods[peer]
    if not guest_mods then
      send(peer, "REFUSE", "your game didn't say which mods it plays; update MoonFactory and the co-op mod")
      return
    end
    local need = rm.compare(host_mods, guest_mods)
    if #need > 0 then
      send_pieces(peer, "NEEDMODS", rm.encode_need(need))
      toast(string.format("Co-op: %s can't join yet: %d mod%s to change", name, #need, #need == 1 and "" or "s"))
      return
    end
    send_pieces(peer, "SETTINGS", rm.host_settings(host_mods))
  end
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
  -- another room's list of mods needed is that room's: joining this one starts afresh
  local kept = moonmod.storage.get("needed")
  if type(kept) == "table" and kept.code ~= code then moonmod.storage.set("needed", nil) end
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
  if kind == "V" then together.hear(peer, rest) return end
  if kind == "C" then if S.role == "guest" and peer == 0 then hear_clock(rest) end return end
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
    if kind == "MODS" then
      local whole = take_piece(peer, kind, rest)
      if whole then S.guest_mods[peer] = rm.decode_list(whole) end
    elseif kind == "HELLO" then
      local id, name = rest:match("^(%S+) ?(.*)$")
      welcome(peer, {id = id, name = name})
    elseif kind == "KEEP" then
      local whole = take_piece(peer, kind, rest)
      if whole then keep(peer, whole) end
    end
  elseif S.role == "guest" and peer == 0 then
    local g = S.guest
    if kind == "NEEDMODS" then
      local whole = take_piece(peer, kind, rest)
      if whole then
        local list = rm.decode_need(whole)
        local mine = rm.loaded() or {}
        for _, n in ipairs(list) do if n.what == "disable" and mine[n.id] then n.name = mine[n.id].name end end
        moonmod.storage.set("needed", {list = list, code = S.code})
        S.status = string.format("This room needs %d mod change%s first.", #list, #list == 1 and "" or "s")
        stop("this room needs mods you don't have: " .. rm.summary(list))
        S.refresh_title = true
      end
      return
    elseif kind == "SETTINGS" then
      local whole = take_piece(peer, kind, rest)
      if whole then
        local n = rm.apply_settings(whole)
        if n > 0 then toast(string.format("Co-op: the host's settings for %d mod%s, for this visit", n, n == 1 and "" or "s")) end
      end
    elseif kind == "WORLD" then
      g.world = take_piece(peer, kind, rest) or g.world
      if g.world then moonmod.storage.set("needed", nil) end
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
        -- the mods this game plays, then "HELLO id name": the player id first, then the name, which may hold spaces
        local mine = rm.loaded()
        if mine then send_pieces(0, "MODS", rm.encode_list(mine)) end
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
      S.guest_mods[e.peer] = nil
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
  if S.role then together.tick(); together.retry() end
  if S.role and S.code and S.frame % 10 == 0 then door.step() end
  if S.role == "host" and S.code and S.frame % CLOCK_EVERY == 0 then send_clock() end
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
  {"guests", "Guests this save keeps", "The friends whose things this save keeps, by name"},
  {"give", "Give to a player", "Give another player in the room Gilda or items from your bag (F7)"},
  {"follow", "Join a player", "Go to where another player in the room is now"},
  {"forget", "Forget guests not here", "Press twice: this save stops keeping the things of guests not in the room now"},
  {"needed", "Mods needed to join", "The mods a room asked this game to enable, update or turn off, still to do"},
}) do try(game.ui.register, {id = a[1], label = a[2], description = a[3]}) end

-- The host's guests: listed, and forgotten (all but those in the room) on a second press within five seconds.
local forget_armed = -1000
local function guests_here()
  local here = {}
  for _, p in pairs(S.players) do if p.id then here[p.id] = true end end
  return here
end
local function list_guests()
  local got = try(game.save.account_list)
  local accounts = type(got) == "table" and got.accounts or nil
  if not accounts then toast("Co-op: no save's guests to show (a visit keeps none)") return end
  if #accounts == 0 then toast("Co-op: this save keeps no guests yet") return end
  local names = {}
  for _, a in ipairs(accounts) do names[#names + 1] = a.name ~= "" and a.name or a.id:sub(1, 8) end
  table.sort(names)
  toast(string.format("Co-op: this save keeps %d guest%s: %s", #accounts, #accounts == 1 and "" or "s", table.concat(names, ", ")))
end
local function forget_guests()
  local got = try(game.save.account_list)
  local accounts = type(got) == "table" and got.accounts or {}
  local here, gone = guests_here(), {}
  for _, a in ipairs(accounts) do if not here[a.id] then gone[#gone + 1] = a end end
  if #gone == 0 then toast("Co-op: no guests to forget") return end
  if S.frame - forget_armed > 300 then
    forget_armed = S.frame
    toast(string.format("Co-op: press again to forget %d guest%s (their things go when the game is saved)", #gone, #gone == 1 and "" or "s"))
    return
  end
  forget_armed = -1000
  for _, a in ipairs(gone) do try(game.save.account_remove, {id = a.id}) end
  toast(string.format("Co-op: %d guest%s forgotten; save to make it last", #gone, #gone == 1 and "" or "s"))
end

moonmod.on("ui.action", function(a)
  if not a then return end
  if a.id == "host" then host() elseif a.id == "leave" then leave()
  elseif a.id == "guests" then list_guests() elseif a.id == "forget" then forget_guests()
  elseif a.id == "give" then together.give() elseif a.id == "follow" then together.follow_menu()
  elseif a.id == "needed" then
    local left, room = rm.needed()
    if not left then toast("Co-op: no room has asked this game for mods")
    elseif #left == 0 then toast("Co-op: the mods room " .. tostring(room) .. " needed are all in place")
    else toast("Co-op: room " .. tostring(room) .. " needs: " .. rm.summary(left)) end
  end
end)
try(game.input.bind, {id = "host_key", keys = {"F8"}})
try(game.input.bind, {id = "leave_key", keys = {"F10"}})
try(game.input.bind, {id = "give_key", keys = {"F7"}})
moonmod.on("game.tick", function()
  local g = try(game.input.consume, {id = "give_key"})
  if g and g.pressed then together.give() end
end)
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
  -- a room that turned this game away: what is still to change, enabled in the Mod Manager and the game restarted
  local left, room = rm.needed()
  if room ~= nil and room ~= code then left = nil end -- the list is another room's, not the one about to be joined
  if left and #left > 0 then
    lines[#lines + 1] = string.format("Room %s needs %d mod change%s (Mod Manager, then restart):", tostring(room or "?"),
                                      #left, #left == 1 and "" or "s")
    for i = 1, math.min(#left, 4) do lines[#lines + 1] = "  " .. rm.describe(left[i]):sub(1, 56) end
    if #left > 4 then lines[#lines + 1] = string.format("  ...and %d more (Mod Manager > Online Co-op > Mods needed)", #left - 4) end
  elseif left then
    lines[#lines + 1] = "The mods the room needed are all in place: join again."
  end
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
  if S.refresh_title then S.refresh_title = false; show(5) end
end)

-- Live tests (tools/tests/coop/live): the harness's game hosts or joins by itself, and says what it sees once a
-- second as "COOPTEST" lines in the log, which the harness reads.
if AUTOTEST then
  local said = {}
  local function report()
    local w = try(game.world.get) or {}
    local p = try(game.player and game.player.get) or {}
    local peers = {}
    for peer, o in pairs(others) do
      peers[#peers + 1] = string.format("%d:%s:%s:%d:%s", peer, tostring(o.scene or "-"), o.state and "seen" or "-",
                                        S.frame - (o.heard or 0), o.slot and ("slot" .. o.slot) or "-")
    end
    table.sort(peers)
    local pos = p.position and string.format("%.0f,%.0f,%.0f", p.position.x, p.position.y, p.position.z) or "-"
    moonmod.log("info", string.format("COOPTEST state frame=%d role=%s code=%s visiting=%s scene=%s context=%s pos=%s puppets=%s mons=%s peers=[%s]",
      S.frame, tostring(S.role), tostring(S.code), tostring(S.guest and S.guest.visiting or false), tostring(my_scene),
      tostring(w.context), pos, tostring(mon.puppets), tostring(mon.count or "-"), table.concat(peers, " ")))
  end
  moonmod.on("game.tick", function()
    if S.frame % 60 == 0 then report() end
    if my_scene ~= said.scene then
      said.scene = my_scene
      moonmod.log("info", "COOPTEST scene " .. tostring(my_scene) .. " frame=" .. S.frame)
    end
    if S.code and not said[S.code] then
      said[S.code] = true
      moonmod.log("info", "COOPTEST room " .. tostring(S.code) .. " role=" .. tostring(S.role))
    end
    if S.status and S.status ~= said.status then
      said.status = S.status
      moonmod.log("info", "COOPTEST status " .. S.status)
    end
    -- a guest that should leave: once it has been on a dungeon floor this long, it leaves as a player does (F10)
    if AUTOTEST.leave_after and S.role == "guest" and S.guest and S.guest.visiting and on_floor() then
      said.floor_since = said.floor_since or S.frame
      if S.frame - said.floor_since >= AUTOTEST.leave_after and not said.left then
        said.left = true
        moonmod.log("info", "COOPTEST leaving")
        leave()
      end
    end
    -- a host that should close its room: once a guest has stood on its floor this long, it closes as a player does
    if AUTOTEST.close_after and S.role == "host" and on_floor() and not said.closed then
      for _, o in pairs(others) do
        if o.scene == my_scene then said.host_since = said.host_since or S.frame end
      end
      if said.host_since and S.frame - said.host_since >= AUTOTEST.close_after then
        said.closed = true
        moonmod.log("info", "COOPTEST closing")
        leave()
      end
    end
    if S.role or said.started then return end
    if AUTOTEST.role == "host" and S.frame >= (AUTOTEST.at or 120) then
      local w = try(game.world.get) or {}
      local here = AUTOTEST.where == "town" and w.town_map ~= nil and w.walking or
                   AUTOTEST.where == "dungeon" and w.context == "dungeon" or
                   AUTOTEST.where == nil and (w.context == "dungeon" or w.town_map or w.map_no)
      if here then
        said.started = true
        moonmod.log("info", "COOPTEST hosting")
        host()
      end
    end
  end)
  -- the guest joins once its input has opened this mod's title page (a visit starts only from there)
  moonmod.on("game.title.opened", function()
    if AUTOTEST.role ~= "guest" or type(AUTOTEST.code) ~= "string" or S.role or said.started then return end
    said.started = true
    code = AUTOTEST.code
    moonmod.log("info", "COOPTEST joining " .. code)
    join()
    show(5)
  end)
  moonmod.on("game.session.started", function(e)
    moonmod.log("info", "COOPTEST session " .. tostring(type(e) == "table" and e.kind) .. " " .. tostring(type(e) == "table" and e.owner))
  end)
  moonmod.on("game.session.ended", function(e)
    moonmod.log("info", "COOPTEST session_ended " .. tostring(type(e) == "table" and e.kind))
  end)
  moonmod.on("game.session.failed", function(e)
    moonmod.log("info", "COOPTEST session_failed " .. tostring(type(e) == "table" and e.reason))
  end)
end

-- For the tests: the state, and the pieces' size.
return {state = S, me = me, piece = PIECE, mods = rm}
