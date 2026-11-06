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

local PROTOCOL = 1
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
local S = {role = nil, code = nil, players = {}, pieces = {}, guest = nil, frame = 0, kept_at = 0}
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
  if not S.role then hud(nil) return end
  local count = 1
  for _ in pairs(S.players) do count = count + 1 end
  hud(string.format("CO-OP %s  %d of 4", S.code or "....", count))
end

local function stop(reason)
  try(game.net.leave)
  if reason then toast("Co-op: " .. reason) end
  S.role, S.code, S.players, S.pieces, S.guest = nil, nil, {}, {}, nil
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
    "Cross on a letter steps it on; Square steps it back.",
    S.status or ("You are " .. (my_name() or "nameless (set a name in the mod's settings)") .. "."),
  }
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

moonmod.on("game.title.opened", function() S.status = nil; show(0) end)
moonmod.on("game.title.selected", function(e)
  local entry = e and e.entry
  local i = entry and tonumber(entry:match("^c(%d)$"))
  if i then
    step(i, e.action == "square" and -1 or 1)
    show(i - 1)
  elseif entry == "join" then
    join()
    show(5)
  elseif entry == "clear" then
    code = "-----"
    moonmod.storage.set("code", code)
    show(0)
  end
end)
-- While waiting on the title page, the status line follows the join.
moonmod.on("game.tick", function()
  if S.role == "guest" and S.guest and not S.guest.visiting and S.frame % 30 == 0 then show(5) end
end)

-- For the tests: the state, and the pieces' size.
return {state = S, me = me, piece = PIECE}
