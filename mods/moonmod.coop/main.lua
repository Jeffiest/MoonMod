-- Online Co-op (moonmod.coop): play Dark Cloud (up to four) or Dark Cloud 2 (two) together through the co-op relay (game.net.*).
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

local PROTOCOL = 10
local MODE = "coop"
local PIECE = 12000 -- characters of one piece; net.send takes 16 KiB
local LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- Which game this is: Dark Cloud (Chronicle) or Dark Cloud 2 (Chronicle Two). The messages are the same; the names,
-- the towns each dungeon is reached from and the save texts' tags differ.
local GAME = (function()
  local info = try(game.info and game.info.get)
  return type(info) == "table" and info.id == "chronicle-two" and "chronicle-two" or "chronicle"
end)()
local DC2 = GAME == "chronicle-two"
local GAME_NAME = DC2 and "Dark Cloud 2" or "Dark Cloud"
local TOWN_TAG = DC2 and "DCT2" or "DCT1" -- georama.town_export's tag: "DCT1<town>:" or "DCT2<town>:"
local THINGS_TAG = DC2 and "DCP2" or "DCP1" -- save.player_export's tag
local DUNGEON_TOWN = {[0] = 0, [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 4, [6] = 0} -- the town each dungeon is reached from (both games: seven dungeons, five towns)
local DUNGEONS = DC2 and {[0] = "Underground Channel", "Rainbow Butterfly Wood", "Starlight Canyon", "Ocean's Roar Cave", "Mount Gundor",
                          "Moon Flower Palace", "Zelmite Mine"}
                     or {[0] = "Divine Beast Cave", "Wise Owl Forest", "Shipwreck", "Sun and Moon Temple", "Moon Sea",
                         "Gallery of Time", "Demon Shaft"}
-- The towns with Georama, by the number their Georama goes by (georama.town_export's town_id): Chronicle's five
-- towns; Chronicle Two's five Georama maps (Palm Brinks has none).
local TOWN_NAMES = DC2 and {[0] = "Sindain", "Balance Valley", "Veniccio", "Heim Rada", "Moon Flower Palace"}
                       or {[0] = "Norune", "Matataki", "Queens", "Muska Lacka", "Yellow Drops"}
local function call(fn, ...)
  if type(fn) ~= "function" then return nil, {code = "unsupported", message = "this engine has no such operation"} end
  local ok, value, err = pcall(fn, ...)
  if not ok then return nil, {code = "error", message = tostring(value)} end
  return value, err
end
local function errmsg(err) return type(err) == "table" and tostring(err.message) or tostring(err) end
-- At most n bytes of a text, and never half a character (a name may be in any script).
local function cut(text, n)
  text = tostring(text)
  if #text <= n then return text end
  while n > 0 do
    local b = text:byte(n + 1)
    if not b or b < 0x80 or b >= 0xC0 then break end
    n = n - 1
  end
  return text:sub(1, n)
end
local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= type(fallback) then return fallback end
  return value
end
local function toast(message)
  -- (Chronicle Two shows a notice in the game's own message window, where the game speaks for itself: no "Co-op:")
  local shown = DC2 and (tostring(message):gsub("^Co%-op: ", "", 1)) or message
  try(game.ui.notify, {message = cut(shown, 196), duration_frames = 300})
  moonmod.log("info", "toast " .. cut(message, 196)) -- in the log too, for bug reports and the live tests
end
local function hud(text)
  if text then try(game.render.layer_register, {id = "coop", text = cut(text, 48)})
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
-- The link to the others (section "The link" below): when each was last heard, their ping, who has gone quiet, a
-- guest's way back in after its connection drops, a host closing its room.
local link = {heard = {}, ping = {}, quiet = {}, fails = 0, fails_since = 0, warned_at = -100000, refused_since = nil,
              out_of_step = {}}
-- What another game sends is a friend's, but never taken as well made: nothing in a message may stop this game,
-- fill its memory, or hand out more than a player could give. A number from a message: finite and in the world.
function S.num(v)
  v = tonumber(v)
  if not v or v ~= v or v > 1000000 or v < -1000000 then return 0 end
  return v
end
-- A place as scene_of writes it: a town "T2", a house "H14", a dungeon floor "D0:3:seed".
function S.scene_ok(scene)
  if type(scene) ~= "string" or #scene > 32 then return false end
  return scene:match("^[TH]%d+$") ~= nil or scene:match("^D%d+:%d+:%-?%d+$") ~= nil
end
S.greeted = {} -- peer -> true once it has said hello on this connection
S.ROOM_FOR = DC2 and 2 or 4 -- the players a room holds, the host among them
S.guest_own = {} -- peer -> the story progress of the save it brings (Chronicle Two), said before its hello
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
  if not ok then
    moonmod.log("warn", "co-op send " .. kind .. ": " .. errmsg(err))
    -- many failing in a short while: the player hears it, once a minute at most
    if S.frame - link.fails_since > 120 then link.fails, link.fails_since = 0, S.frame end
    link.fails = link.fails + 1
    if link.fails >= 10 and S.frame - link.warned_at > 3600 then
      link.warned_at = S.frame
      toast("Co-op: messages aren't getting through (" .. errmsg(err):sub(1, 60) .. ")")
    end
  end
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
  p.at = S.frame -- half a text that stops coming is let go (link.step)
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
  -- the others in the room, by name: each with their ping, or "no signal"
  local names, troubled = {}, S.rejoin ~= nil
  for peer, name in pairs(S.names) do
    local ms = link.ping[peer]
    names[#names + 1] = link.quiet[peer] and (name .. " (no signal)") or ms and string.format("%s %.0fms", name, ms) or name
    troubled = troubled or (link.quiet[peer] and true or false) or (ms ~= nil and ms > 250)
  end
  table.sort(names)
  -- Chronicle Two keeps its screen its own: the room's line shows for a while after someone comes or goes, and while
  -- the link is in trouble (a reconnect, no signal, a slow ping); the code is in the Mod Manager all along.
  if DC2 then
    local who = count .. ":" .. table.concat(names, ","):gsub("%d+ms", "")
    if who ~= S.hud_who then S.hud_who, S.hud_until = who, S.frame + 360 end
    if not troubled and S.frame >= (S.hud_until or 0) then
      hud(nil)
      try(game.render.layer_remove, {id = "coop_who"})
      return
    end
  end
  if S.rejoin then hud(string.format("CO-OP %s  reconnecting...", S.code or "....")) return end
  hud(string.format("CO-OP %s  %d of %d", S.code or "....", count, S.ROOM_FOR))
  if #names > 0 then try(game.render.layer_register, {id = "coop_who", text = cut(table.concat(names, ", "), 48)})
  else try(game.render.layer_remove, {id = "coop_who"}) end
end

-- Seeing each other ------------------------------------------------------------------------------------------------
-- Fifteen times a second each game sends where its player is ("P scene character weapon x y z heading motion flags step
-- frame": the motion as its game plays it, looping or held, and how fast, and the sending game's frame); each game
-- shows the others in the same place as heroes of their own (world.avatar_set), and takes away one that has gone quiet
-- for three seconds or is elsewhere. In Chronicle the host is in its own colours and guests in blue (they may be the
-- same hero); Chronicle Two's two heroes are told apart by themselves. Every game builds each floor from a seed made of
-- the room's code, the dungeon and the floor (dungeons.set_seed), so the floors are the same for everyone, whoever
-- comes first.
--
-- Each game is shown on its own clock: a report, a shot or a monster's move carries the frame it was made on, and
-- the others show it as many frames behind as the quickest of that game's recent reports took to come (S.age), so its
-- moves, swings, shots and sounds keep their order and spacing however unevenly the network brings them.

local SEND_EVERY = 4     -- frames between reports
local QUIET = 180        -- frames without a report before a player's hero goes
local GUEST_TINT = {64, 84, 128}
local others = {}        -- peer -> {scene, state, heard, slot, lag}
local my_scene = nil

-- Chronicle Two's heroes by name, for a player who gave none: the ridepod is Max's, a monster's form Monica's.
S.HERO_NAMES = {max = "Max", monica = "Monica", ridepod = "Max", monster = "Monica"}

-- How long a peer's messages take: the frames between a message's frame and this game's when it came, the least of
-- the last thirty-two (the others came slower). A message's age is then how far behind that quickest it is shown.
function S.clock_heard(peer, sent)
  sent = tonumber(sent)
  if not sent then return end
  local o = others[peer] or {}
  others[peer] = o
  o.lag = o.lag or {}
  o.lag[#o.lag + 1] = S.frame - sent
  if #o.lag > 32 then table.remove(o.lag, 1) end
  local least = o.lag[1]
  for _, v in ipairs(o.lag) do if v < least then least = v end end
  o.least = least
end
function S.age(peer, sent)
  local o = others[peer]
  sent = tonumber(sent)
  if not (o and o.least and sent) then return nil end
  return math.max(0, math.min(3600, math.floor(S.frame - sent - o.least)))
end
-- Chronicle Two shows another game's reports this many frames behind its clock (the engine's kDelay,
-- coop_world_moonmod.cpp). A blow between the games is kept for that moment too, so it lands as the swing that dealt
-- it lands on this screen, not before.
S.SHOWN_BEHIND = 8
S.later = {}
function S.at_moment(peer, sent, fn)
  local age = sent and S.age(peer, sent)
  local wait = age and S.SHOWN_BEHIND - age or 0
  if wait <= 0 then fn() return end
  if #S.later >= 64 then table.remove(S.later, 1) end
  S.later[#S.later + 1] = {due = S.frame + wait, fn = fn}
end
function S.later_step()
  if #S.later == 0 then return end
  local due, keep = {}, {}
  for _, l in ipairs(S.later) do
    if l.due <= S.frame then due[#due + 1] = l else keep[#keep + 1] = l end
  end
  S.later = keep
  for _, l in ipairs(due) do pcall(l.fn) end
end

local function scene_of(w)
  if type(w) ~= "table" then return nil end
  if w.context == "dungeon" and w.dungeon_id then
    -- in transit (the floor select, a floor not built yet): nowhere yet, so no one is offered to follow there
    if not w.floor_id or w.floor_id < 0 or not w.floor_seed or w.floor_seed == 0 then return nil end
    return string.format("D%d:%d:%s", w.dungeon_id, w.floor_id, tostring(w.floor_seed))
  end
  if DC2 then
    -- Chronicle Two numbers its maps across the whole game, and a town's area is not a place (Palm Brinks is five
    -- maps in one area): a place is the map the town runs (scene_map), "T12", or inside a house that map and the
    -- house in one number (map * 1000 + house), "H12034".
    local map, house = tonumber(w.scene_map), tonumber(w.house)
    if not map or map < 0 or map > 999 or map ~= math.floor(map) then return nil end
    if house and house >= 0 and house <= 999 and house == math.floor(house) then return "H" .. (map * 1000 + house) end
    return "T" .. map
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
      try(game.world and game.world.avatar_set, {slot = slot, character = st.character, weapon = st.weapon, outfit = o.outfit,
                                  ridepod = st.character == "ridepod" and o.ridepod or nil,
                                  form = st.character == "monster" and o.form or nil,
                                  x = st.x, y = st.y, z = st.z,
                                  heading = st.heading, motion = st.motion,
                                  motion_flags = DC2 and st.flags or nil, motion_step = DC2 and st.step or nil,
                                  age = DC2 and S.age(peer, st.sent) or nil,
                                  tint = peer ~= 0 and not DC2 and GUEST_TINT or nil,
                                  -- (with no name of their own, Chronicle Two's say whose hero it is, as the game would)
                                  name = o.name or (DC2 and S.HERO_NAMES[st.character]) or (peer == 0 and "Host" or ("Player " .. peer)),
                                  down = o.down ~= nil and o.down ~= "up" or nil,
                                  away = DC2 and o.away or nil})
      o.slot = slot
    elseif o.slot then
      try(game.world and game.world.avatar_clear, {slot = o.slot})
      o.slot = nil
    end
  end
end

local function hear_position(peer, rest)
  local scene, character, weapon, x, y, z, heading, motion, flags, step, sent =
    rest:match("^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%d) (%S+) (%d+)$")
  local o = others[peer] or {}
  others[peer] = o
  o.heard = S.frame
  -- a place that isn't one (or a report too long to be one) is nowhere
  if not scene or #rest > 160 or not S.scene_ok(scene) then o.scene, o.state = nil, nil return end
  local moved = o.scene ~= scene
  o.scene = scene
  if moved and S.moved then S.moved(peer, scene) end
  S.clock_heard(peer, sent)
  step = S.num(step)
  o.state = {character = character, weapon = tonumber(weapon), x = S.num(x), y = S.num(y),
             z = S.num(z), heading = S.num(heading), motion = math.floor(S.num(motion)),
             flags = math.floor(S.num(flags)) % 8, step = step >= 0 and step <= 16 and step or nil, sent = tonumber(sent)}
  if DC2 then show_others() end -- (at once, so the avatar has each report on its clock)
end

-- Shots and spells (Chronicle Two): what a player's hero fires on a floor (Max's guns, Monica's magic, her magic
-- sword's charge), the trails of their blade's swings and the sounds their hero makes are sent as they happen ("F
-- scene kind x y z dx dy dz value amount target frame frames", player.effects_take's entries and the frame they went
-- on), and the others draw them from
-- that player's hero (world.avatar_effect): the same shot flying the same way, striking nothing there, since its hits
-- are the firing game's and reach the monsters as that game's other hits do. A sound (kind 9) names its bank in
-- frames ("CH_000,CH_000"), as a trail names its two frames; so does a looped one (kind 10: a charge, an engine),
-- told again every few frames while the hero keeps it going.
S.shots = {MOST = 8} -- shots sent in one frame at most (a machine gun fires one a frame)
function S.shots.send()
  if not (game.player and game.player.effects_take) then return end
  local taken = try(game.player.effects_take) -- (taken every frame, so none wait to be sent late)
  local list = type(taken) == "table" and taken.effects or nil
  if type(list) ~= "table" or not on_floor() or not next(others) then return end
  for i, f in ipairs(list) do
    if i > S.shots.MOST then break end
    if type(f) == "table" then
      -- (a blade's trail names its two frames, "frame0,frame1"; a shot has none, "-")
      local frames = "-"
      if type(f.frame0) == "string" and type(f.frame1) == "string" and f.frame0:match("^[%w_]+$") and f.frame1:match("^[%w_]+$") then
        frames = f.frame0 .. "," .. f.frame1
      end
      send("all", "F", string.format("%s %d %.1f %.1f %.1f %.4f %.4f %.4f %d %.3f %d %d %s", my_scene, math.floor(S.num(f.kind)),
                                     S.num(f.x), S.num(f.y), S.num(f.z), S.num(f.dx), S.num(f.dy), S.num(f.dz),
                                     math.floor(S.num(f.value)), S.num(f.amount), math.floor(S.num(f.target or -1)),
                                     math.floor(S.frame), frames))
    end
  end
end
function S.shots.hear(peer, rest)
  if #rest > 200 then return end
  local scene, kind, x, y, z, dx, dy, dz, value, amount, target, sent, frames =
    rest:match("^(%S+) (%d%d?) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%-?%d+) (%S+) (%-?%d+) (%d+) ?(%S*)$")
  local frame0, frame1 = (frames or ""):match("^([%w_]+),([%w_]+)$")
  local o = others[peer]
  -- (a shot on a floor this game is not on, or from a hero not shown here, is not drawn)
  if not scene or not o or not o.slot or scene ~= my_scene or o.scene ~= scene then return end
  value, target = tonumber(value), tonumber(target)
  if not value or value < -1 or value > 65535 or not target or target < -1 or target > 255 then return end
  S.clock_heard(peer, sent)
  -- (drawn when the avatar, shown on its game's clock, comes to the moment it was fired)
  try(game.world and game.world.avatar_effect, {slot = o.slot, kind = tonumber(kind), x = S.num(x), y = S.num(y), z = S.num(z),
                                                 dx = S.num(dx), dy = S.num(dy), dz = S.num(dz), value = value,
                                                 amount = S.num(amount), target = target, frame0 = frame0, frame1 = frame1,
                                                 age = S.age(peer, sent)})
end

-- Places' names (Chronicle Two, whose maps have names of their own): a game says what the place it stands in is
-- called ("W scene name") when it gets there and to a player who joins, so an offer can say "Sindain" or "Max's
-- House" for a map only the other game has seen.
S.places, S.places_n, S.my_place = {}, 0, nil
local function say_place(to)
  if S.my_place then send(to, "W", S.my_place) end
end
local function note_place(scene, w)
  local title = DC2 and scene and type(w) == "table" and type(w.map_title) == "string" and w.map_title or nil
  local name = title and cut((title:gsub("%c", " ")), 40):match("^%s*(.-)%s*$") or ""
  local said = scene and name ~= "" and (scene .. " " .. name) or nil
  if said == S.my_place then return end
  S.my_place = said
  if said then
    if not S.places[scene] then S.places_n = S.places_n + 1 end
    S.places[scene] = name
    say_place("all")
  end
end
local function hear_place(rest)
  if #rest > 80 then return end
  local scene, name = rest:match("^(%S+) (.+)$")
  if not scene or not S.scene_ok(scene) then return end
  name = cut((name:gsub("%c", " ")), 40):match("^%s*(.-)%s*$")
  if name == "" then return end
  if not S.places[scene] then
    if S.places_n >= 96 then S.places, S.places_n = {}, 0 end -- no game has that many places to name
    S.places_n = S.places_n + 1
  end
  S.places[scene] = name
end

-- What a hero wears (Chronicle Two, whose heroes change hats, clothes and shoes): a game says its hero's outfit
-- ("O head clothes feet sub", item numbers, 0 for none) when it changes and to a player who joins, and the others
-- draw that player's hero in it (world.avatar_set's outfit) instead of in their own hero's.
S.my_outfit = nil
local function say_outfit(to)
  if S.my_outfit then send(to, "O", S.my_outfit) end
end
local function note_outfit(p)
  local o = type(p) == "table" and type(p.outfit) == "table" and p.outfit or nil
  if not o then return end
  local function item(v)
    v = tonumber(v)
    return v and v > 0 and v < 4096 and math.floor(v) or 0
  end
  -- (and the ridepod's four parts, leg arm body pack, and the monster's form plus one: what the others draw when this
  -- player rides the ridepod or wears a form; 0 for none)
  local r = type(p.ridepod) == "table" and p.ridepod or {}
  local form = tonumber(p.form)
  form = form and form >= 0 and form < 4095 and math.floor(form) + 1 or 0
  local text = string.format("%d %d %d %d %d %d %d %d %d", item(o.head), item(o.clothes), item(o.feet), item(o.sub),
                             item(r.leg), item(r.arm), item(r.body), item(r.pack), form)
  if text == S.my_outfit then return end
  S.my_outfit = text
  say_outfit("all")
end
local function hear_outfit(peer, rest)
  local o = others[peer]
  if not o or #rest > 48 then return end
  -- four numbers from a game that says no more, nine from one that says the ridepod's parts and the form too
  local head, clothes, feet, sub, more = rest:match("^(%d+) (%d+) (%d+) (%d+)(.*)$")
  if not head then return end
  local function item(v)
    v = tonumber(v)
    return v and v > 0 and v < 4096 and v or nil
  end
  o.outfit = {head = item(head), clothes = item(clothes), feet = item(feet), sub = item(sub)}
  local leg, arm, body, pack, form = more:match("^ (%d+) (%d+) (%d+) (%d+) (%d+)$")
  o.ridepod, o.form = nil, nil
  if leg and item(leg) and item(arm) and item(body) and item(pack) then
    o.ridepod = {leg = item(leg), arm = item(arm), body = item(body), pack = item(pack)}
  end
  if form and item(form) then o.form = item(form) - 1 end
end

-- The story's scenes (Chronicle Two): a game whose player watches one says so ("SC 1", and "SC 0" when it is over),
-- and to a player who joins while it plays; the others fade that player's hero from sight where it stands and back in
-- where it is after (world.avatar_set's away), as the game's own scenes keep their cast to themselves. (A scene this
-- game plays hides the others' heroes from it by itself.) A game that says nothing of scenes is never away.
S.in_scene = false
local function say_scene(to)
  if S.in_scene then send(to, "SC", "1") end
end
local function note_scene(w)
  local now = DC2 and type(w) == "table" and w.story_scene == true or false
  if now == S.in_scene then return end
  S.in_scene = now
  send("all", "SC", now and "1" or "0")
end
local function hear_scene(peer, rest)
  local o = others[peer]
  if not o or (rest ~= "1" and rest ~= "0") then return end
  local away = rest == "1" or nil
  if o.away == away then return end
  o.away = away
  if DC2 then show_others() end
end

-- Names: each game says its player's name ("N name") on joining, and the others answer with theirs.
local function say_name(to)
  send(to, "N", cut(my_name() or ("Player " .. tostring(S.me_peer or "?")), 24))
  say_place(to)
  say_outfit(to)
  say_scene(to)
end

local function hear_name(peer, rest)
  local o = others[peer] or {}
  others[peer] = o
  local first = not o.named
  o.named = true
  -- a name is a line of text: no control characters, 24 bytes, and "the host" is the host's alone
  local name = cut((rest:gsub("%c", " ")), 24):match("^%s*(.-)%s*$")
  local lower = name:lower()
  if peer ~= 0 and (lower == "host" or lower == "the host") then name = "" end
  for other, taken in pairs(S.names) do
    if other ~= peer and name ~= "" and taken == name then name = cut(name, 20) .. " (" .. peer .. ")" break end
  end
  o.name = name ~= "" and name or nil
  S.names[peer] = o.name or ("Player " .. peer)
  if first then say_name(peer) end
  show_room()
end

local function forget(peer)
  local o = others[peer]
  if o and o.slot then try(game.world and game.world.avatar_clear, {slot = o.slot}) end
  others[peer] = nil
  S.names[peer] = nil
  link.heard[peer], link.ping[peer], link.quiet[peer] = nil, nil, nil
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
  if S.place_step then S.place_step() end -- (the monsters' section, below: who runs this floor)
  note_place(my_scene, w)
  note_scene(w)
  local text = "-"
  if my_scene then
    local p = try(game.player and game.player.get)
    note_outfit(p)
    if p and p.position then
      text = string.format("%s %s %s %.1f %.1f %.1f %.3f %d %d %.2f", my_scene, p.town_character or p.character,
                           tostring(p.weapon and p.weapon.item_no or "-"), p.position.x, p.position.y, p.position.z,
                           p.heading or 0, p.motion or 0, math.floor(S.num(p.motion_flags)) % 8,
                           p.motion_step ~= nil and S.num(p.motion_step) or -1)
    elseif last_sent and last_sent:sub(1, #my_scene + 1) == my_scene .. " " then
      text = last_sent -- in a menu or a talk: still standing there
    end
  end
  if text == "-" and last_sent == "-" then return end -- out of the dungeon it is said once
  last_sent = text
  send("all", "P", text == "-" and text or (text .. " " .. S.frame)) -- (stamped with this game's frame as it goes)
end

-- The room's floors: the same seed for a floor in every game in the room.
local function floor_seed(dungeon, floor)
  local h = 5381
  for c in (tostring(S.code) .. ":" .. dungeon .. ":" .. floor):gmatch(".") do h = (h * 33 + c:byte()) % 2147483647 end
  return h
end
moonmod.on("game.dungeon.generating", function(e)
  if not (S.role and S.code and type(e) == "table") or e.back_floor then return end
  -- (a live test may name the seed, so a scenario meets the same floor every run)
  local seed = AUTOTEST and tonumber(AUTOTEST.seed) or floor_seed(e.dungeon_id or 0, e.floor_id or 0)
  try(game.dungeons and game.dungeons.set_seed, {seed = seed})
end)

-- Monsters: the host's -------------------------------------------------------------------------------------------
-- The host's game runs a floor's monsters for everyone. There they see every player on the floor and go for the
-- nearest; a blow, shot or spell that lands on another player comes back from monsters.mirror_get and goes to that player's game
-- ("D damage kind flags"), which takes it as a monster's blow (combat.strike_player), guard and dodge and all. Fifteen
-- times a second the host sends where its monsters are ("M scene frame
-- slot,kind,state,hp,max_hp,x,y,z,heading,motion,motion_flags,motion_step;..."),
-- and a guest on that floor makes its own monsters copies of them (monsters.puppet_set): they stand, move and die as
-- the host's do. A guest's blow on one (puppet_set returns them) goes to the host ("H slot damage"), whose monster
-- takes it.

local MIRROR_EVERY = 4    -- frames between the host's monster reports
local mon = {puppets = false, scene = nil, said_none = false}

-- Chronicle Two: a floor's monsters are run by whoever was on the floor first (its leader), host or joiner, since
-- either may go into a dungeon alone and be joined there. The one who comes second copies them as they stand (what
-- the first already struck down stays down), and takes the floor over when the first leaves it. Two who take one
-- floor in the same moment both think they lead: the host's stands, and the joiner gives way when it hears the
-- host's monsters. In Chronicle the host's game runs every floor it is on.
mon.lead = nil -- the floor this game leads (Chronicle Two)
mon.at = nil   -- the floor it last took stock of
function mon.others_here()
  for peer, o in pairs(others) do
    if o.scene and o.scene == my_scene and S.frame - (o.heard or 0) < QUIET then return peer end
  end
  return nil
end
function mon.leading()
  if not DC2 then return S.role == "host" end
  return my_scene ~= nil and mon.lead == my_scene
end
function S.place_step() -- as often as this game looks where it is
  if not DC2 then return end
  if not on_floor() then mon.lead, mon.at = nil, nil return end
  if mon.at ~= my_scene then
    mon.at = my_scene
    mon.lead = mon.others_here() == nil and my_scene or nil -- first on the floor: it is this game's to run
    if AUTOTEST then moonmod.log("info", "COOPTEST floor " .. (mon.lead and "led" or "followed") .. " " .. my_scene) end
  elseif mon.lead ~= my_scene and mon.others_here() == nil then
    mon.lead = my_scene -- the one who ran it left: the monsters go on from where they stand, as this game's
    mon.release()
    if AUTOTEST then moonmod.log("info", "COOPTEST floor taken over " .. my_scene) end
  end
end

function mon.peer_with_avatar(slot)
  for peer, o in pairs(others) do if o.slot == slot then return peer end end
  return nil
end

function mon.host_step()
  if not on_floor() or not mon.leading() then
    -- off the floors (or, in Chronicle Two, on one another player runs): the others' copies are theirs again
    if not mon.said_none and not (DC2 and on_floor()) then send("all", "M", "- -") end
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
    parts[#parts + 1] = string.format("%d,%d,%d,%d,%d,%.1f,%.1f,%.1f,%.3f,%d,%d,%.2f", m.slot, m.kind, m.state, m.hp, m.max_hp,
                                      m.x, m.y, m.z, m.heading, m.motion, math.floor(S.num(m.motion_flags)) % 8,
                                      m.motion_step ~= nil and S.num(m.motion_step) or -1)
  end
  send("all", "M", my_scene .. " " .. math.floor(S.frame) .. " " .. (#parts > 0 and table.concat(parts, ";") or "-"))
  local alive = 0
  for _, m in ipairs(got.monsters or {}) do if m.hp > 0 then alive = alive + 1 end end
  mon.count = alive -- for the live tests' report
  for _, hit in ipairs(got.hits or {}) do
    local peer = mon.peer_with_avatar(hit.avatar)
    if peer then
      send(peer, "D", string.format("%d %d %d", hit.damage, hit.kind or 0, hit.flags or 0) .. mon.blow_told(hit))
      if AUTOTEST then moonmod.log("info", string.format("COOPTEST blow on peer %d strength %d kind %d", peer, hit.damage, hit.kind or 0)) end
    end
  end
end

function mon.release()
  if mon.puppets then try(game.monsters and game.monsters.puppet_clear) end
  mon.puppets = false
end

-- Chronicle Two: how a blow landed goes with it, so the game it lands in takes it as one of its own (the hero's guard,
-- the stun and stagger, poison and the rest) and shows it so (the flash, the cry, the spark, the damage). On "D":
-- " stun stagger guard_rate status at_x at_y at_z toward_x toward_z" (where it struck, from the hero's feet); on
-- "H": " kind element flags stagger stun guard at_x at_y at_z" (from the monster's). Last comes the frame it was
-- dealt on, and the other game lands it when the swing that dealt it comes to that moment on its screen
-- (S.at_moment). Chronicle's blows say only how much, at once.
local function n(v) return math.floor(S.num(v)) end
local function at_of(v) return type(v) == "table" and v or {} end
function mon.blow_told(hit)
  if not DC2 then return "" end
  local when = " " .. math.floor(S.frame)
  if hit.stun == nil then return when end
  local at, toward = at_of(hit.at), at_of(hit.toward)
  return string.format(" %d %d %d %d %.1f %.1f %.1f %.2f %.2f", n(hit.stun), n(hit.stagger), n(hit.guard_rate), n(hit.status) % 0x200000,
                       S.num(at.x), S.num(at.y), S.num(at.z), S.num(toward.x), S.num(toward.z)) .. when
end
function mon.hit_told(hit)
  if not DC2 then return "" end
  local when = " " .. math.floor(S.frame)
  if hit.kind == nil then return when end
  local at = at_of(hit.at)
  return string.format(" %d %d %d %d %d %d %.1f %.1f %.1f", n(hit.kind), n(hit.element), n(hit.flags), n(hit.stagger), n(hit.stun),
                       hit.guard and 1 or 0, S.num(at.x), S.num(at.y), S.num(at.z)) .. when
end
-- The numbers after a message's first ones, or nil when there are not want of them.
local function numbers(rest, want)
  local out = {}
  for v in tostring(rest or ""):gmatch("%S+") do out[#out + 1] = tonumber(v) end
  if #out ~= want then return nil end
  for i = 1, want do if out[i] == nil or out[i] ~= out[i] then return nil end end
  return out
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function mon.hear(peer, rest)
  if #rest > 12000 then return end
  if DC2 then
    local theirs = rest:match("^(%S+) ")
    if mon.leading() then
      -- both took this floor at once: the host's monsters stand, and the joiner gives way
      if S.role == "host" or theirs ~= my_scene then return end
      mon.lead = nil
      if AUTOTEST then moonmod.log("info", "COOPTEST floor given to the host " .. my_scene) end
    end
  elseif S.role ~= "guest" or peer ~= 0 then
    return
  end
  local scene, sent, list = rest:match("^(%S+) (%d+) (%S+)$")
  if not scene or scene ~= my_scene then mon.release() return end
  mon.from = peer
  S.clock_heard(peer, sent)
  local monsters = {}
  if list ~= "-" then
    for item in list:gmatch("[^;]+") do
      local f = {}
      for v in item:gmatch("[^,]+") do f[#f + 1] = tonumber(v) end
      if #f == 12 then
        -- (in Chronicle Two each plays its motion as the leader's does, looping or held, at its pace)
        local step = f[12] >= 0 and f[12] <= 16 and f[12] or nil
        monsters[#monsters + 1] = {slot = math.floor(f[1]), kind = math.floor(f[2]), state = math.floor(f[3]),
                                   hp = math.floor(f[4]), max_hp = math.floor(f[5]), x = f[6], y = f[7], z = f[8],
                                   heading = f[9], motion = math.floor(f[10]),
                                   motion_flags = DC2 and math.floor(f[11]) % 8 or nil, motion_step = DC2 and step or nil}
      end
    end
  end
  -- (Chronicle Two: shown on the leader's clock, a little behind and eased, as the players' heroes are)
  local got = try(game.monsters and game.monsters.puppet_set, {monsters = monsters, age = DC2 and S.age(peer, sent) or nil})
  local alive = 0
  for _, m in ipairs(monsters) do if m.hp > 0 then alive = alive + 1 end end
  mon.count = alive -- for the live tests' report
  -- copies this floor can't make (no such monster here): a floor out of step with the host's, once it lasts
  local refused = type(got) == "table" and type(got.refused) == "table" and #got.refused or 0
  if refused >= 2 then
    link.refused_since = link.refused_since or S.frame
    if S.frame - link.refused_since > 300 and link.out_of_step_here then
      link.out_of_step_here(string.format("%d of %s monsters aren't on your floor", refused, link.whose(peer)), peer)
    end
  else
    link.refused_since = nil
  end
  if got then
    mon.puppets = true
    mon.scene = scene
    -- every blow this guest landed on a copy (a weapon's, a bomb's, a thrown item's) goes to the host's monster
    for _, hit in ipairs(type(got) == "table" and got.hits or {}) do
      send(DC2 and peer or 0, "H", string.format("%d %d", hit.slot, math.floor(hit.damage)) .. mon.hit_told(hit))
    end
  end
end

-- A guest's blow on a copy of the host's monster: the host's takes it.
function mon.hit_on_host(peer, rest)
  local slot, damage, told = rest:match("^(%d+) (%d+)(.*)$")
  slot, damage = tonumber(slot), tonumber(damage)
  if not (slot and damage and slot <= 255) then return end
  local hit = {slot = slot, damage = math.min(9999, damage)} -- one blow is a blow: never more than the game's most
  local f = DC2 and numbers(told, 10)
  if f then
    -- (Chronicle Two: taken and shown as this game's own hero's blow would be)
    hit.kind, hit.element, hit.flags = clamp(math.floor(f[1]), -1, 31), clamp(math.floor(f[2]), -1, 3), clamp(math.floor(f[3]), 0, 255)
    hit.stagger, hit.stun, hit.guard = clamp(math.floor(f[4]), 0, 16), clamp(math.floor(f[5]), 0, 255), f[6] == 1
    hit.at = {x = clamp(f[7], -200, 200), y = clamp(f[8], -200, 200), z = clamp(f[9], -200, 200)}
  end
  local sent = f and f[10] or (DC2 and numbers(told, 1) or {})[1]
  S.at_moment(peer, sent, function()
    local o = others[peer]
    if not (o and o.scene and o.scene == my_scene) then return end
    try(game.monsters and game.monsters.mirror_hit, hit)
  end)
end

-- The host's monster struck this guest.
function mon.struck(peer, rest)
  local damage, kind, flags, told = rest:match("^(%d+) (%-?%d+) (%-?%d+)(.*)$")
  if not damage then return end
  local f = DC2 and numbers(told, 10)
  local sent = f and f[10] or (DC2 and numbers(told, 1) or {})[1]
  S.at_moment(peer, sent, function() mon.struck_now(damage, kind, flags, f) end)
end
function mon.struck_now(damage, kind, flags, f)
  local p = try(game.player and game.player.get)
  if not (my_scene and p and p.position) then return end
  -- kind as the host's hit list has it: 2 a small hit (a flinch), 3 or 4 a blow (a knock-back)
  local blow = {x = p.position.x, y = p.position.y + 8, z = p.position.z, radius = 12,
                damage = math.max(1, math.min(9999, tonumber(damage))), kind = tonumber(kind) >= 3 and "heavy" or "light"}
  if f then
    -- (Chronicle Two: the monster's damage row, and where on the hero it struck, a little way from the feet)
    blow.flags = clamp(math.floor(tonumber(flags) or 0), 0, 255)
    blow.stun, blow.stagger, blow.guard_rate = clamp(math.floor(f[1]), 0, 255), clamp(math.floor(f[2]), 0, 16), clamp(math.floor(f[3]), 0, 100)
    blow.status = clamp(math.floor(f[4]), 0, 0x1FFFFF)
    blow.x, blow.y, blow.z = p.position.x + clamp(f[5], -10, 10), p.position.y + clamp(f[6], 0, 30), p.position.z + clamp(f[7], -10, 10)
    blow.toward = {x = clamp(f[8], -1, 1), z = clamp(f[9], -1, 1)}
  end
  local took = try(game.combat and game.combat.strike_player, blow)
  if AUTOTEST and type(took) == "table" then
    moonmod.log("info", string.format("COOPTEST struck hit=%s damage=%s hp=%s%s", tostring(took.hit), tostring(took.damage), tostring(took.hp),
                                      took.reason and (" reason=" .. tostring(took.reason)) or ""))
  end
end

function mon.tick()
  S.later_step() -- (blows kept for their moment)
  if (S.role == "host" or (DC2 and S.role)) and S.frame % MIRROR_EVERY == 0 then mon.host_step() end
  -- A host that stops sending (paused, in a menu) leaves its monsters held where they are; a guest who leaves the
  -- floor has its own monsters on the next.
  if (S.role == "guest" or DC2) and mon.puppets and (mon.scene ~= my_scene or not on_floor()) then mon.release() end
end

-- Doors: opened for everyone ----------------------------------------------------------------------------------------
-- A script that changes the floor without leaving it (a door or gate opens, a switch turns) comes from
-- dungeons.shared_events_get and goes to the others ("E scene script mode ext px py pz dx dy dz"); a game on that floor
-- runs it there (dungeons.shared_event_run) once its player is free, the key it asks for taken as given. Each game
-- keeps the floor's opened doors and hands them to a player who arrives later, so the floor is the same for everyone.

local door = {log = {}, done = {}, waiting = {}}

door.MOST = 256 -- doors remembered on one floor: far more than a floor has

function door.key(scene, text) return scene .. "|" .. (text:match("^(%S+ %S+ %S+ %S+ %S+)") or text) end

function door.remember(scene, text)
  local key = door.key(scene, text)
  if door.done[key] then return false end
  local log = door.log[scene] or {}
  if #log >= door.MOST then return false end
  door.done[key] = true
  door.log[scene] = log
  table.insert(log, text)
  return true
end

function door.step()
  -- somewhere new: the doors of the place left are let go (that floor is built afresh when walked onto again)
  if my_scene and door.scene ~= my_scene then
    door.scene = my_scene
    local mine = my_scene .. "|"
    for scene in pairs(door.log) do if scene ~= my_scene then door.log[scene] = nil end end
    for key in pairs(door.done) do if key:sub(1, #mine) ~= mine then door.done[key] = nil end end
  end
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
  if #rest > 200 then return end
  local scene, text = rest:match("^(%S+) (.+)$")
  if not scene or scene ~= my_scene then return end -- elsewhere
  -- exactly a script, a mode, an ext and six numbers, each as this game would write them
  if not text:match("^%d+ %d+ %d+ [%d%.%-]+ [%d%.%-]+ [%d%.%-]+ [%d%.%-]+ [%d%.%-]+ [%d%.%-]+$") then return end
  local f = {}
  for v in text:gmatch("%S+") do
    local n = tonumber(v)
    if not n or n ~= n or n > 1000000 or n < -1000000 then return end
    f[#f + 1] = n
  end
  if #f ~= 9 or f[1] > 9999 or f[2] > 2 or f[3] > 1 then return end
  if not door.remember(scene, text) then return end -- opened here already
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

local together = {queue = {}, open = nil, owed = {}, got = {}}
-- A gift's bounds: no more Gilda than a wallet holds, no more of an item than a bag's slot; and from one player in a
-- minute, no more than two wallets and forty gifts. What is over goes back to the giver.
together.GILDA_MAX, together.GILDA_MINUTE, together.ITEM_MAX, together.GIFTS_MINUTE, together.OWED_FOR = 65535, 131070, 99, 40, 600

function together.name(peer)
  local o = others[peer]
  return (o and o.name) or S.names[peer] or (peer == 0 and "The host") or ("Player " .. tostring(peer))
end

function together.place(scene)
  local d, f = scene:match("^D(%d+):(%-?%d+):")
  -- Chronicle counts a dungeon's floors from zero; Chronicle Two's own numbers start at one
  if d then return string.format("%s, floor %s", DUNGEONS[tonumber(d)] or "a dungeon", tostring((tonumber(f) or 0) + (DC2 and 0 or 1))) end
  if S.places[scene] then return S.places[scene] end -- Chronicle Two: the name the game there gave it
  local t = scene:match("^T(%d+)$")
  if t then return not DC2 and TOWN_NAMES[tonumber(t)] or "a town" end
  if scene:match("^H%d+$") then return "a house" end
  return "somewhere"
end

-- One panel at a time, in turn (a follow offer, a step of a gift). A question of yes or no (yes_no: its first option
-- is yes, its second no) is asked in Chronicle Two's own message window with the game's Yes and No, its subtitle (or
-- ask, when the panel's subtitle is no question) the question; elsewhere, and in Chronicle, it is the panel.
function together.ask(panel) table.insert(together.queue, panel) end
local function autotest_answer(p)
  local yes = AUTOTEST.follow ~= false
  moonmod.log("info", "COOPTEST offer " .. p.title .. (yes and " -> join" or " -> stay"))
  if yes and p.options[1].pick then p.options[1].pick() end
end
function together.tick()
  -- the live test holds a follow offer open a while (offer_hold, frames) so a screenshot shows it, then answers it
  if together.open and together.held and S.frame >= together.held then
    local p = together.open
    together.open, together.held = nil, nil
    try(game.ui.choice_close, {})
    autotest_answer(p)
  end
  -- A question gone stale is taken back: it may wait out a whole scene before it is asked (the engine holds it while
  -- the player is in one), and the friend may have moved on by then, or while it stood open.
  if together.open and not together.held and together.open.still and not together.open.still() then
    together.open = nil
    try(game.ui.choice_close, {})
  end
  if together.open or not together.queue[1] then return end
  local p = table.remove(together.queue, 1)
  if p.still and not p.still() then return end -- stale (they moved on, or we're there already)
  local hold = AUTOTEST and p.follow and tonumber(AUTOTEST.offer_hold)
  if AUTOTEST and p.follow and not hold then autotest_answer(p) return end
  local cards = {}
  for i, o in ipairs(p.options) do cards[i] = {title = cut(o.title, 48), subtitle = o.subtitle and cut(o.subtitle, 64) or nil} end
  local yes_no = DC2 and p.yes_no and #p.options == 2
  local subtitle = yes_no and (p.ask or p.subtitle) or p.subtitle
  local ok, err = call(game.ui.choice_open, {id = "coop_together", title = cut(p.title, 64), subtitle = subtitle and cut(subtitle, 96) or nil,
                                          cancel = true, town = true, style = yes_no and "yes_no" or nil, options = cards})
  if ok then
    together.open = p
    if hold then together.held = S.frame + hold end
  else
    moonmod.log("warn", "co-op panel: " .. errmsg(err))
    if hold then autotest_answer(p) end
  end
end
moonmod.on("ui.choice_made", function(e)
  if type(e) ~= "table" or not tostring(e.id or ""):find("coop_together", 1, true) or not together.open then return end
  local p = together.open
  together.open, together.held = nil, nil
  local option = not e.cancelled and e.index and p.options[e.index] or nil
  if option and option.pick then option.pick() end
  if not option and p.on_cancel then p.on_cancel() end -- backed out of: a question another player waits on is answered
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
    local kind, number = scene:match("^([TH])(%d+)$")
    local map = tonumber(number)
    -- Chronicle Two: a house's number holds its town's map too; the way in is the town's, to its entrance
    if map and DC2 and kind == "H" then map = math.floor(map / 1000) end
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
  -- Chronicle Two: the question is asked when the other player goes onto a dungeon floor, and only then. Its towns
  -- are many maps each (Palm Brinks alone is five districts, and every house is one more), so asking at each would
  -- ask at every door; a player in a town is joined from the Mod Manager.
  if DC2 and scene:sub(1, 1) ~= "D" then return end
  -- six offers from one player in half a minute at most: more is no one walking
  local o = others[peer]
  if o then
    if S.frame - (o.offers_since or -100000) > 1800 then o.offers_since, o.offers = S.frame, 0 end
    o.offers = o.offers + 1
    if o.offers > 6 then return end
  end
  -- a guest still on the title page (its visit not begun) has nowhere to follow from
  if S.role == "guest" and not (S.guest and S.guest.visiting) then return end
  -- Chronicle Two: a house on the street this player stands in is no place to be walked to (joining one walks to its
  -- town map's entrance); its door is right there
  local house = DC2 and tonumber(scene:match("^H(%d+)$"))
  if house and my_scene == "T" .. math.floor(house / 1000) then return end
  -- one offer per player: a newer move replaces one not yet shown
  for i = #together.queue, 1, -1 do
    if together.queue[i].follow == peer then table.remove(together.queue, i) end
  end
  local who = together.name(peer)
  together.ask({
    follow = peer, yes_no = true, title = who .. " went to " .. together.place(scene), subtitle = "Join them there?",
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

-- Someone to give to: still in the room, and this game in touch with it (a gift is taken from the giver first).
function together.can_give(peer)
  if S.rejoin or not (S.role and S.code) then
    toast("Co-op: you're out of the room right now; give once you're back in")
    return false
  end
  if not (S.names[peer] or S.players[peer]) then toast("Co-op: they have left the room") return false end
  return true
end

-- What this game gave a player a moment ago: only that much is taken back from them as "didn't fit".
function together.owe(peer, id, n)
  local o = together.owed[peer]
  if not o or S.frame - o.at > together.OWED_FOR then o = {g = 0, items = {}}; together.owed[peer] = o end
  o.at = S.frame
  if id then o.items[id] = (o.items[id] or 0) + n else o.g = o.g + n end
end

-- What a player gave this game in the last minute.
function together.from(peer)
  local a = together.got[peer]
  if not a or S.frame - a.since > 3600 then a = {since = S.frame, gilda = 0, gifts = 0}; together.got[peer] = a end
  return a
end

function together.add_gilda(amount)
  local left = amount
  while left > 0 do
    local chunk = math.min(32767, left)
    if not try(game.economy.add, {amount = chunk}) then break end
    left = left - chunk
  end
end

function together.give_gilda(peer, amount)
  if not together.can_give(peer) then return end
  amount = math.min(amount, together.GILDA_MAX)
  local spent = 0
  while spent < amount do
    local chunk = math.min(32767, amount - spent)
    if not try(game.economy.spend, {amount = chunk}) then break end
    spent = spent + chunk
  end
  if spent <= 0 then toast("Co-op: you don't have that much Gilda") return end
  if not send(peer, "V", "g " .. spent) then -- it never left: back in the wallet
    together.add_gilda(spent)
    toast("Co-op: the Gilda couldn't be sent; you still have it")
    return
  end
  together.owe(peer, nil, spent)
  S.keep_soon = S.frame + 30 -- a guest's things go to the host soon after, so a drop doesn't undo the gift
  toast(string.format("Co-op: you gave %s %d Gilda", together.name(peer), spent))
end

function together.give_item(peer, item, count)
  if not together.can_give(peer) then return end
  local got = try(game.items.remove, {id = item.id, count = math.min(count, together.ITEM_MAX)})
  local removed = type(got) == "table" and tonumber(got.removed) or 0
  if removed <= 0 then toast("Co-op: you no longer have " .. item.name) return end
  if not send(peer, "V", string.format("i %s %d %s", item.id, removed, item.name)) then
    try(game.items.give, {id = item.id, count = removed})
    toast("Co-op: " .. item.name .. " couldn't be sent; you still have it")
    return
  end
  together.owe(peer, item.id, removed)
  S.keep_soon = S.frame + 30
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
function together.over(peer, a)
  moonmod.log("warn", "co-op: more than a gift from player " .. tostring(peer) .. "; the rest went back")
  if not a.warned then
    a.warned = true
    toast("Co-op: " .. together.name(peer) .. " sent more than a gift can hold; the rest went back to them")
  end
end

function together.hear(peer, rest)
  if #rest > 160 then return end
  local back, kind, tail = rest:match("^(back) (%a) (.+)$")
  if not back then kind, tail = rest:match("^(%a) (.+)$") end
  if kind ~= "g" and kind ~= "i" then return end
  -- only from a player of this room, and only into a save that is in it (a guest's visit, the host's story)
  local known = S.names[peer] ~= nil or S.players[peer] ~= nil or (S.role == "guest" and peer == 0)
  local playing = S.role == "host" or (S.role == "guest" and S.guest and S.guest.visiting)
  local owed = together.owed[peer]
  if owed and S.frame - owed.at > together.OWED_FOR then owed, together.owed[peer] = nil, nil end
  local a = together.from(peer)
  if kind == "g" then
    local amount = tonumber(tail)
    if not amount or amount ~= amount or amount < 1 then return end
    amount = math.floor(math.min(amount, 1000000))
    if back then
      -- no more comes back than was given
      amount = math.min(amount, owed and owed.g or 0)
      if amount <= 0 then return end
      owed.g = owed.g - amount
    else
      local take = (known and playing) and math.min(amount, together.GILDA_MAX, math.max(0, together.GILDA_MINUTE - a.gilda)) or 0
      if take < amount then
        send(peer, "V", string.format("back g %d", amount - take))
        if known and playing then together.over(peer, a) end
      end
      if take <= 0 then return end
      amount, a.gilda = take, a.gilda + take
    end
    local before = wallet()
    together.add_gilda(amount)
    local got = wallet() - before
    S.keep_soon = S.frame + 30
    if back then toast(string.format("Co-op: %d Gilda came back (it didn't fit)", got)) return end
    if got < amount then send(peer, "V", "back g " .. (amount - got)) end
    toast(string.format("Co-op: %s gave you %d Gilda%s", together.name(peer), got, got < amount and " (your wallet is full)" or ""))
  else
    local id, count, name = tail:match("^(%S+) (%d+) ?(.*)$")
    count = tonumber(count)
    if not id or #id > 64 or not count or count < 1 then return end
    count = math.floor(math.min(count, 999))
    name = cut((name:gsub("%c", " ")), 40)
    name = name ~= "" and name or id
    if back then
      count = math.min(count, owed and owed.items[id] or 0)
      if count <= 0 then return end
      owed.items[id] = owed.items[id] - count
    else
      local take = (known and playing and a.gifts < together.GIFTS_MINUTE) and math.min(count, together.ITEM_MAX) or 0
      if take < count then
        send(peer, "V", string.format("back i %s %d %s", id, count - take, name))
        if known and playing then together.over(peer, a) end
      end
      if take <= 0 then return end
      count, a.gifts = take, a.gifts + 1
    end
    local got = try(game.items.give, {id = id, count = count})
    local added = type(got) == "table" and tonumber(got.added) or 0
    S.keep_soon = S.frame + 30
    if back then toast(string.format("Co-op: %d x %s came back (it didn't fit)", added, name)) return end
    if added < count then send(peer, "V", string.format("back i %s %d %s", id, count - added, name)) end
    toast(string.format("Co-op: %s gave you %d x %s%s", together.name(peer), added, name, added < count and " (your bag is full)" or ""))
  end
end

-- Georama: the host's world -----------------------------------------------------------------------------------------
-- When a player leaves Georama's edit mode, their game sends that town (georama.town_export) to the host, which takes
-- it into its world and sends it on to everyone else; the host's own edits go straight out. Each game takes the town
-- (georama.town_import); a player walking in it is walked into it again, at the town's entrance, so no one stands in
-- a house that just went up. A town arriving while its player is busy in it (editing, a menu) waits and is tried again.

local TOWNS = TOWN_NAMES
local editing_town = nil
local editing_base = nil  -- that town when the editor opened
local waiting_towns = {} -- town -> {data, from}
-- Chronicle Two takes a town into its editor while its player builds there, so a joiner placing parts one after
-- another must not take a host's town that does not yet hold its newest part (that part would blink out until the
-- host's answer to it came). A joiner numbers each town it sends (a "#n" line before it); the host's towns say the
-- last number of that joiner's it has taken, and a joiner holds a host town that is behind for tn.HOLD frames at
-- most: the host's answer is on the way, and after that the host's word stands.
-- (one table, not seven locals: the main chunk is at Luau's 200-local limit)
local tn = {
  seq = {},   -- joiner: town -> the number of the last town it sent
  acked = {}, -- host: peer -> town -> the last number of theirs taken
  held = {},  -- joiner: town -> {data, since}
  HOLD = 600,
}
function tn.numbered(n, data) return "#" .. tostring(n) .. "\n" .. data end
function tn.for_peer(peer, town, data) -- the host's town for one player, with what of theirs it holds
  return tn.numbered(tn.acked[peer] and tn.acked[peer][town] or 0, data)
end
function tn.took(peer, town, n)
  if not (peer and town and n) then return end
  tn.acked[peer] = tn.acked[peer] or {}
  if n > (tn.acked[peer][town] or 0) then tn.acked[peer][town] = n end
end

local function take_town(data, from, base)
  local town = tonumber(data:match("^" .. TOWN_TAG .. "(%d+):"))
  if not town then return end
  if not base then
    -- already so here (the merged town coming back to the one who built it): nothing to take, no walk back
    local now = try(game.georama and game.georama.town_export, {town_id = town})
    if now and now.data == data then waiting_towns[town] = nil return true end
  end
  local ok, err = call(game.georama and game.georama.town_import, {town_id = town, data = data, base = base})
  if not ok then
    if errmsg(err):find("busy") then
      -- a builder sends a town at every part, each measured from the one before: what waits is the newest town,
      -- measured from the oldest town not yet taken
      local was = waiting_towns[town]
      waiting_towns[town] = {data = data, from = from, base = (base and was and was.base and was.from == from) and was.base or base,
                             seq = was and was.from == from and was.seq or nil}
    end
    if not errmsg(err):find("busy") then moonmod.log("warn", "co-op town: " .. errmsg(err)) end
    return false
  end
  waiting_towns[town] = nil
  if S.town_taken then S.town_taken(town) end
  local who = from == 0 and "The host" or (S.players[from] and S.players[from].name) or "A player"
  if DC2 and from ~= nil then who = together.name(from) end -- a room of two: the other player, by name
  -- a town that comes part by part (Chronicle Two) is announced once in a while, not at every part
  local quiet = S.towns_watched and S.town_told and S.town_told[town] and S.frame - S.town_told[town] < 60 * 60
  if S.towns_watched then S.town_told = S.town_told or {} S.town_told[town] = S.frame end
  if from ~= nil and not quiet then
    toast(who .. (S.towns_watched and " is building in " or " changed ") .. (TOWNS[town] or "a town") ..
          (ok.reloaded and "; back to its entrance" or ""))
  end
  return true
end

-- A guest's edit comes with the town as it was when they opened the editor ("edited\nbase"): the host merges only
-- what they changed into its own town (georama.town_import with base), so two building at once both keep their work,
-- and sends the merged town to everyone, the editor too. The host's word is the whole town.
local function send_merged(town)
  local export = try(game.georama and game.georama.town_export, {town_id = town})
  if not (export and export.data) then return end
  for id in pairs(S.players) do send_pieces(id, "TOWN", tn.for_peer(id, town, export.data)) end
end

local function town_from(peer, payload)
  local n, rest = payload:match("^#(%d+)\n(.*)$")
  if n then payload, n = rest, tonumber(n) end
  local cut = payload:find("\n", 1, true)
  local data = cut and payload:sub(1, cut - 1) or payload
  local base = cut and payload:sub(cut + 1) or nil
  local town = tonumber(data:match("^" .. TOWN_TAG .. "(%d+):"))
  if S.role == "host" then
    -- a guest's word is only what it changed (it comes with the town it started from): the whole town is the host's
    -- to say, so one without that is not taken, and the guest gets the host's town back
    if not base then
      moonmod.log("warn", "co-op: a town from player " .. tostring(peer) .. " came without what it was changed from; not taken")
      if town then send_merged(town) end
      return
    end
    local took = take_town(data, peer, base)
    if AUTOTEST then moonmod.log("info", string.format("COOPTEST town %s from %s #%s took=%s", tostring(town), tostring(peer), tostring(n), tostring(took))) end
    if not took and town and waiting_towns[town] and waiting_towns[town].from == peer then
      -- busy: the number goes with the newest town waiting, and is said when it is taken
      if n and n > (waiting_towns[town].seq or 0) then waiting_towns[town].seq = n end
      return
    end
    tn.took(peer, town, n) -- taken, or not to be taken: either way the host's town that follows is its answer
    if town then send_merged(town) end
  elseif peer == 0 then
    if town and n and n < (tn.seq[town] or 0) then
      tn.held[town] = {data = data, since = tn.held[town] and tn.held[town].since or S.frame}
      if AUTOTEST then moonmod.log("info", string.format("COOPTEST town %d from the host #%d held (sent #%d)", town, n, tn.seq[town])) end
      return
    end
    tn.held[town or -1] = nil
    local took = take_town(data, 0)
    if AUTOTEST then moonmod.log("info", string.format("COOPTEST town %s from the host #%s took=%s", tostring(town), tostring(n), tostring(took))) end
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
  -- (Chronicle Two sends a town at every part placed, so there the last change to a spot stands, not the last to leave)
  toast(name_of(peer) .. " is building in " .. (TOWNS[town] or "this town") ..
        (DC2 and " too: you both keep your work, but where you change the same spot the last change wins" or
         " too: you both keep your work, but where you change the same spot the last to leave wins"))
end
local function hear_builder(peer, rest)
  local town, on = rest:match("^(%d+) ([01])$")
  if not town then return end
  town = tonumber(town)
  builders[peer] = on == "1" and town or nil
  if on == "1" and editing_town == town then warn_builders(town, peer) end
end

-- The town being edited, by the number its Georama goes by: Chronicle's town map; Chronicle Two's Georama town
-- (world.get().georama_town: its town_map is an area, which is not that number).
local function town_edited(w)
  if DC2 then return tonumber(w.georama_town) end
  return w.town_map
end

local function watch_editing()
  local w = try(game.world.get)
  if type(w) == "table" and w.editing and town_edited(w) ~= nil then
    if editing_town ~= town_edited(w) then
      editing_town = town_edited(w)
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
  -- Chronicle Two with the world watched: the town goes out whenever the engine says it changed (S.town_changed),
  -- at every part placed and at what the town works out once the building is done; leaving the editor only makes
  -- sure of it
  if S.towns_watched then editing_base = nil S.town_changed(town) return end
  local export = try(game.georama and game.georama.town_export, {town_id = town})
  if not (export and export.data) then return end
  if S.role == "host" then
    for id in pairs(S.players) do send_pieces(id, "TOWN", tn.for_peer(id, town, export.data)) end
  elseif S.role == "guest" then
    send_pieces(0, "TOWN", export.data .. (editing_base and ("\n" .. editing_base) or ""))
  end
  editing_base = nil
end

-- A town that came while its player was busy is tried again (the host sent it on when it first came).
local function retry_towns()
  for town, w in pairs(waiting_towns) do
    local took = take_town(w.data, w.from, w.base)
    if AUTOTEST and took then moonmod.log("info", string.format("COOPTEST town %d waited and was taken (#%s)", town, tostring(w.seq))) end
    if took and S.role == "host" and w.base then
      tn.took(w.from, town, w.seq)
      send_merged(town)
    end
  end
  -- a host town held for an answer that never came: the host's word stands
  for town, h in pairs(tn.held) do
    if S.frame - h.since >= tn.HOLD then
      tn.held[town] = nil
      if AUTOTEST then moonmod.log("info", string.format("COOPTEST town %d held too long: the host's word stands", town)) end
      take_town(h.data, 0)
    end
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
local rm = {MOST = 256}

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
  local out, n = {}, 0
  for entry in tostring(text):gmatch("[^;]+") do
    n = n + 1
    if n > rm.MOST then break end -- no game plays that many
    local id, version, role = entry:match("^(%S+) (%S+) (%S+)$")
    if id and #id <= 64 and #version <= 32 and #role <= 12 then out[id] = {id = id, version = version, role = role} end
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
  local out, n = {}, 0
  for line in tostring(text):gmatch("[^\n]+") do
    n = n + 1
    if n > rm.MOST then break end
    local what, id, version, name = line:match("^(%a+)\t([^\t]+)\t([^\t]+)\t(.*)$")
    if (what == "enable" or what == "version" or what == "disable") and #id <= 64 and #version <= 32 then
      out[#out + 1] = {what = what, id = id, version = version, name = cut((name:gsub("%c", " ")), 64)}
    end
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
  -- only for the mods this game plays as the room's (never one that is each player's own), and no more than a
  -- mod's settings could be
  local mine = rm.loaded()
  local by_mod, keys = {}, {}
  for line in tostring(text):gmatch("[^\n]+") do
    local id, key, value = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
    if id and id ~= "moonmod.coop" and (not mine or (mine[id] and mine[id].role == "required")) and #key <= 64 and #value <= 4096 then
      local v = rm.decode_value(value)
      keys[id] = (keys[id] or 0) + 1
      if v ~= nil and keys[id] <= 256 then by_mod[id] = by_mod[id] or {}; by_mod[id][key] = v end
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
  local visiting = S.role == "guest" and S.guest and S.guest.visiting
  rm.clear_settings()
  try(game.net.leave)
  forget_all()
  mon.release()
  door.log, door.done, door.waiting = {}, {}, {}
  builders = {}
  if reason then toast("Co-op: " .. reason) end
  S.role, S.code, S.players, S.pieces, S.guest, S.names, S.guest_mods = nil, nil, {}, {}, nil, {}, {}
  S.guest_own = {}
  if S.own_reset then S.own_reset() end
  if S.heroes_reset then S.heroes_reset() end
  if S.shared_reset then S.shared_reset() end
  S.rejoin, S.closing, S.host_bye, S.joined_at = nil, nil, nil, nil
  link.heard, link.ping, link.quiet, link.refused_since, link.out_of_step = {}, {}, {}, nil, {}
  S.greeted, S.keep_soon = {}, nil
  together.queue, together.owed, together.got, together.waiting = {}, {}, {}, nil
  if together.open then -- a panel of the room's goes with the room
    together.open = nil
    try(game.ui.choice_close, {})
  end
  waiting_towns, editing_town, editing_base = {}, nil, nil
  tn.seq, tn.acked, tn.held = {}, {}, {}
  door.scene = nil
  if S.stopped then S.stopped() end
  show_room()
  -- A visit is the host's world: it ends with the room, however the room ended (the session's end comes back here
  -- with no room left to stop).
  if visiting then try(game.session.finish) end
end

-- A player's own save (Chronicle Two) -------------------------------------------------------------------------------
-- In Dark Chronicle a player who joins brings one of their own saves: its things come along (save.slot_player_export)
-- and are written back into it as they play (save.slot_player_import), things only: its story stays its own, and the
-- host keeps nothing of theirs. Co-op opens once a save's story is past the talk with Donny at the Channel Entrance
-- (story progress own.GATE): for the save the host plays, and for the save a joiner picks. An engine without these
-- operations keeps the older way, the joiner's things kept by the host.
local own = {GATE = 2, slot = nil, things = nil, progress = nil, warned = nil}
own.CLOSED = "Co-op opens once you have talked to Donny at the Channel Entrance."

-- The saves a joiner may bring, those past the gate: {slot, progress, chapter}. nil: this engine has no such list.
function own.saves()
  if not DC2 then return nil end
  local got = try(game.save and game.save.slots_list)
  if type(got) ~= "table" or type(got.slots) ~= "table" then return nil end
  local list = {}
  for _, s in ipairs(got.slots) do
    local slot, progress = type(s) == "table" and tonumber(s.slot), type(s) == "table" and tonumber(s.progress)
    if slot and progress and s.ready == true and progress >= own.GATE and slot >= 0 and slot < 10000 then
      list[#list + 1] = {slot = math.floor(slot), progress = math.floor(progress), chapter = math.floor(tonumber(s.chapter) or 0)}
    end
  end
  table.sort(list, function(a, b) return a.slot < b.slot end)
  return list
end

-- The save picked (remembered between runs), else the first that may join.
function own.picked(list)
  local want = tonumber(moonmod.storage.get("own_slot"))
  for _, s in ipairs(list) do if s.slot == want then return s end end
  return list[1]
end

function own.pick_next()
  local list = own.saves()
  local now = list and own.picked(list)
  if not now then return end
  for i, s in ipairs(list) do
    if s.slot == now.slot then moonmod.storage.set("own_slot", list[i % #list + 1].slot) return end
  end
end

function own.label(s) return string.format("File %d (chapter %d)", s.slot + 1, s.chapter) end
function S.own_reset() own.slot, own.things, own.progress, own.warned, own.unused = nil, nil, nil, nil, nil end -- with the room (stop)

-- The save's things, read before the room is joined: nothing is asked of a room that can't be entered.
function own.take()
  own.slot, own.things, own.progress = nil, nil, nil
  local list = own.saves()
  if not list then return true end -- the older way
  local pick = own.picked(list)
  if not pick then return false, own.CLOSED end
  local got, err = call(game.save.slot_player_export, {slot = pick.slot})
  if not got or type(got.data) ~= "string" then return false, "Can't read " .. own.label(pick) .. ": " .. cut(errmsg(err), 40) end
  own.slot, own.things, own.progress = pick.slot, got.data, pick.progress
  return true
end

-- The player's things as they stand, into their save. True when written.
function own.write()
  local things = try(game.save.player_export)
  if not (things and things.data) then return false end
  local ok, err = call(game.save.slot_player_import, {slot = own.slot, data = things.data})
  if ok then return true end
  moonmod.log("warn", "co-op: writing your things into your save: " .. errmsg(err))
  if not own.warned then
    own.warned = true
    toast("Co-op: your things could not be written into your save: " .. cut(errmsg(err), 60))
  end
  return false
end

-- The world as it changes (Chronicle Two) ---------------------------------------------------------------------------
-- The host's save is the world, and in Dark Chronicle either player may change it while they play apart: a scene
-- seen, a floor cleared, a townsperson won over. Each game asks its engine to tell it of the changes it makes to the
-- shared parts of the save (world.watch_set, game.world.changed: story flags and counters, the story's progress, the
-- story's party, joinable townsfolk, dungeon floor records) and sends each one ("X kind id value"); the other game
-- writes it into its own save (world.change_apply), which does not tell it back. A joiner's changes go to the host,
-- which passes them to any other joiner; the host's go to every joiner. Only the host's game saves the world.
local shared = {on = false, KINDS = {flag = 1, counter = 1, progress = 1, party = 1, recruit = 2, floor = 9, stock = 1, gift = 1}}

function shared.watch()
  if not DC2 or shared.on or not S.role then return end
  if call(game.world and game.world.watch_set, {enabled = true}) then
    shared.on = true
    if shared.towns_begin then shared.towns_begin() end
  end
end

function S.shared_reset() -- with the room (stop)
  if shared.on then try(game.world and game.world.watch_set, {enabled = false}) end
  shared.on = false
  S.towns_watched = nil
  shared.held, shared.held_towns, shared.told, shared.told_n = {}, {}, {}, 0
end

-- A change as text: "kind id value", a list's numbers joined with commas, a flag 1 or 0.
function shared.encode(e)
  local count = type(e) == "table" and shared.KINDS[e.kind]
  local id = count and tonumber(e.id)
  if not id then return nil end
  local v = e.value
  if e.kind == "flag" then return string.format("flag %d %d", id, v and 1 or 0) end
  if count == 1 then
    v = tonumber(v)
    return v and string.format("%s %d %d", e.kind, id, v) or nil
  end
  if type(v) ~= "table" or #v ~= count then return nil end
  local parts = {}
  for i = 1, count do
    local n = tonumber(v[i])
    if not n then return nil end
    parts[i] = string.format("%d", n)
  end
  return string.format("%s %d %s", e.kind, id, table.concat(parts, ","))
end

function shared.decode(text)
  if #text > 160 then return nil end
  local kind, id, values = text:match("^(%l+) (%d+) ([%-%d,]+)$")
  local count = kind and shared.KINDS[kind]
  if not count then return nil end
  local list = {}
  for n in values:gmatch("[^,]+") do
    local v = tonumber(n)
    if not v or v ~= math.floor(v) or v < -2147483648 or v > 2147483647 then return nil end
    list[#list + 1] = math.floor(v)
  end
  if #list ~= count then return nil end
  local value = list
  if kind == "flag" then value = list[1] == 1 elseif count == 1 then value = list[1] end
  return {kind = kind, id = tonumber(id), value = value}
end

function shared.tell(text, but)
  if S.role == "host" then
    for peer, p in pairs(S.players) do
      if p.in_visit and peer ~= but then send(peer, "X", text) end
    end
  elseif S.role == "guest" and S.guest and S.guest.visiting and but ~= 0 then
    send(0, "X", text)
  end
end

-- A town's Georama: the engine says only that it changed (kind "town"); the town itself goes as it always has
-- ("TOWN"): the host's whole, a joiner's with the town it was changed from, which the host merges and sends on.
-- shared.towns holds each town as the games last agreed it, a joiner's "changed from". The engine writes a town
-- being built into its record part by part, so a town goes at every part placed, moved or taken away, and a game
-- whose player stands in that town builds it again where they stand.
shared.towns = {}
function shared.town_now(town)
  local export = try(game.georama and game.georama.town_export, {town_id = town})
  return export and export.data or nil
end
function shared.towns_begin()
  shared.towns = {}
  for town = 0, 4 do shared.towns[town] = shared.town_now(town) end
  S.towns_watched = true
end
function S.town_taken(town) -- a town that came from another game: what stands now is agreed
  if shared.on then shared.towns[town] = shared.town_now(town) end
end
function S.town_changed(town)
  if not shared.on or town < 0 or town > 4 then return end
  if S.role == "guest" and not (S.guest and S.guest.visiting) then return end
  local now = shared.town_now(town)
  if not now or now == shared.towns[town] then return end
  local base = shared.towns[town]
  shared.towns[town] = now
  if S.role == "host" then
    for peer, p in pairs(S.players) do if p.in_visit then send_pieces(peer, "TOWN", tn.for_peer(peer, town, now)) end end
  elseif base then
    tn.seq[town] = (tn.seq[town] or 0) + 1
    send_pieces(0, "TOWN", tn.numbered(tn.seq[town], now .. "\n" .. base))
  end
  if AUTOTEST then moonmod.log("info", "COOPTEST town " .. town .. " sent" .. (S.role == "host" and "" or " #" .. tostring(tn.seq[town]))) end
end

-- Two games changing one flag or counter in the same moment would each take the other's value and end crossed: the
-- host's word stands. The host remembers what it told of each flag and counter, and a joiner's change of the same one
-- within shared.CROSS frames of it is not taken; the host's is sent to that joiner again. (The story's progress keeps
-- the higher value and a floor's record merges in the engine, so those two need no rule here.)
shared.told, shared.told_n, shared.CROSS = {}, 0, 180
function shared.mine(text) -- a change this game made, as told
  if S.role ~= "host" then return end
  local kind, id = text:match("^(%l+) (%d+) ")
  if kind ~= "flag" and kind ~= "counter" then return end
  if shared.told_n >= 512 then -- no more than a moment's worth is ever needed
    for key, t in pairs(shared.told) do if S.frame - t.at > shared.CROSS then shared.told[key] = nil; shared.told_n = shared.told_n - 1 end end
  end
  local key = kind .. " " .. id
  if not shared.told[key] then shared.told_n = shared.told_n + 1 end
  shared.told[key] = {at = S.frame, text = text}
end

moonmod.on("game.world.changed", function(e)
  if not shared.on or type(e) ~= "table" then return end
  if e.kind == "town" then
    local town = tonumber(e.id)
    if town then S.town_changed(math.floor(town)) end
    return
  end
  local text = shared.encode(e)
  if text then
    shared.mine(text)
    shared.tell(text)
  end
end)

-- A joiner's game hears the host's changes from the moment the host has sent its world, which is before its own visit
-- has begun: those are held (the newest shared.HOLD) and taken, in order, as the visit begins, as are the newest
-- towns the host sent in that time. Dropped, they would never come again: the host has moved on from them.
shared.held, shared.held_towns, shared.HOLD = {}, {}, 300
function shared.hold(rest)
  if #rest > 160 then return end
  if #shared.held >= shared.HOLD then table.remove(shared.held, 1) end
  shared.held[#shared.held + 1] = rest
end
function shared.hold_town(data)
  data = data:match("^#%d+\n(.*)$") or data -- a joiner not yet in has sent nothing: the number says nothing
  local town = tonumber(data:match("^" .. TOWN_TAG .. "(%d+):"))
  if town and town >= 0 and town <= 4 then shared.held_towns[town] = data end
end
function shared.take_held() -- as the visit begins, once the world is watched
  local held, towns = shared.held, shared.held_towns
  shared.held, shared.held_towns = {}, {}
  for _, rest in ipairs(held) do shared.hear(0, rest) end
  for town = 0, 4 do if towns[town] then take_town(towns[town], 0) end end
end

function shared.hear(peer, rest)
  if not shared.on then return end
  if S.role == "guest" and peer ~= 0 then return end -- a joiner's world comes from the host alone
  local change = shared.decode(rest)
  if not change then return end
  if S.role == "host" then
    local told = shared.told[change.kind .. " " .. change.id]
    if told and S.frame - told.at <= shared.CROSS and told.text ~= rest then
      send(peer, "X", told.text) -- crossed with the host's own change: the host's stands, in both games
      return
    end
  end
  if not call(game.world.change_apply, change) then return end
  if S.role == "host" then shared.tell(rest, peer) end
  -- what a scene gave the other player it gave this one too (each has a bag of their own)
  if change.kind == "gift" then
    toast("Co-op: " .. ((S.names and S.names[peer]) or (peer == 0 and "the host" or "your friend")) ..
          " was given something in a scene; it is in your bag too")
  end
end

-- Heroes (Chronicle Two) --------------------------------------------------------------------------------------------
-- In Dark Chronicle a room gives each game one hero (party.room_hero_set): the host plays Max and a joiner Monica,
-- from the gate on, long before the story has her. Either may ask to swap ("SW ask", the Mod Manager's "Ask to swap
-- heroes" or F9); the other is asked on a panel and answers ("SW yes" / "SW no"); on yes both games change the hero
-- they play, each to its own copy of the other hero with its own gear. The engine makes the change once the player is
-- free (walking a town or a floor). The host tells a joiner how the room stands ("SW is0" / "SW is1").
local heroes = {swapped = false, asked = nil, offered = nil, set = nil}

function heroes.mine()
  local host_plays = heroes.swapped and "monica" or "max"
  if S.role == "host" then return host_plays end
  return host_plays == "max" and "monica" or "max"
end

function heroes.name(hero) return hero == "max" and "Max" or "Monica" end

function heroes.apply()
  if not DC2 or not S.role then return end
  local hero = heroes.mine()
  if heroes.set == hero then return end
  if call(game.party and game.party.room_hero_set, {hero = hero}) then heroes.set = hero end
end

function S.heroes_reset() -- with the room (stop)
  if heroes.set then try(game.party and game.party.room_hero_clear) end
  heroes.swapped, heroes.asked, heroes.offered, heroes.set = false, nil, nil, nil
end

-- The one other player of a two-player room: a swap is between two.
function heroes.other()
  if S.role == "guest" then return S.guest and S.guest.visiting and 0 or nil end
  local found
  for peer, p in pairs(S.players) do
    if p.in_visit then
      if found then return nil end
      found = peer
    end
  end
  return found
end

function heroes.ask()
  if not DC2 then return end
  if not S.role or not heroes.set then toast("Co-op: heroes are swapped in a room, with another player") return end
  local peer = heroes.other()
  if not peer then toast("Co-op: swapping heroes takes exactly two players") return end
  if heroes.asked and S.frame - heroes.asked < 600 then toast("Co-op: you asked already; waiting for " .. together.name(peer)) return end
  heroes.asked = S.frame
  send(peer, "SW", "ask")
  toast("Co-op: asked " .. together.name(peer) .. " to swap heroes")
end

-- How the room stands is the host's word: after every swap the host says it again ("SW is0" / "SW is1"), so two games
-- that crossed (both asked at once, or an answer to a question given up on) end on the host's heroes, never both
-- playing one hero.
function heroes.tell()
  local peer = S.role == "host" and heroes.other()
  if peer then send(peer, "SW", heroes.swapped and "is1" or "is0") end
end

function heroes.swap()
  heroes.swapped = not heroes.swapped
  heroes.asked = nil
  heroes.apply()
  toast("Co-op: heroes swapped; you play " .. heroes.name(heroes.mine()) .. " now")
  heroes.tell()
end

function heroes.hear(peer, rest)
  if not DC2 then return end
  if S.role == "guest" and peer == 0 and (rest == "is0" or rest == "is1") then -- how the room stands, from its host
    local was = heroes.set and heroes.mine()
    heroes.swapped = rest == "is1"
    heroes.asked = nil
    heroes.apply()
    if was and was ~= heroes.mine() then toast("Co-op: you play " .. heroes.name(heroes.mine()) .. ", as the room has it") end
    return
  end
  if not heroes.set or peer ~= heroes.other() then return end
  if rest == "ask" then
    -- both asked at once: each takes the other's question as the answer to its own
    if heroes.asked and S.frame - heroes.asked < 600 then
      send(peer, "SW", "yes")
      heroes.swap()
      return
    end
    if heroes.offered and S.frame - heroes.offered < 300 then return end -- one panel, however often it is asked
    heroes.offered = S.frame
    local would = heroes.name(heroes.mine() == "max" and "monica" or "max")
    local function answer(yes)
      send(peer, "SW", yes and "yes" or "no")
      if yes then heroes.swap() end
    end
    if AUTOTEST and AUTOTEST.swap_answer ~= nil then -- the live test answers by itself
      moonmod.log("info", "COOPTEST swap asked -> " .. (AUTOTEST.swap_answer and "yes" or "no"))
      answer(AUTOTEST.swap_answer == true)
      return
    end
    together.ask({title = together.name(peer) .. " wants to swap heroes", subtitle = "You would play " .. would .. ".",
                  yes_no = true, ask = "Swap, and play " .. would .. "?",
                  options = {{title = "Swap", subtitle = "Play " .. would, pick = function() answer(true) end},
                             {title = "Not now", pick = function() answer(false) end}},
                  on_cancel = function() answer(false) end})
  elseif rest == "yes" then
    if heroes.asked then heroes.swap() -- only the answer to this game's own question
    else heroes.tell() end -- an answer to a question given up on: the joiner hears how the room stands
  elseif rest == "no" then
    if heroes.asked then
      heroes.asked = nil
      toast("Co-op: " .. together.name(peer) .. " would rather not swap now")
    end
  end
end

-- Host --------------------------------------------------------------------------------------------------------------

local function host()
  if S.role then toast("Co-op: a room is already open (" .. tostring(S.code) .. ")") return end
  local session = try(game.session.get)
  if type(session) == "table" and session.kind ~= "story" then
    toast("Co-op: host from your own save, in a town or a dungeon")
    return
  end
  if DC2 then
    local w = try(game.world.get)
    local progress = type(w) == "table" and tonumber(w.progress)
    if progress and progress < own.GATE then toast(own.CLOSED) return end
  end
  local ok, err = net_open("host", {})
  if not ok then toast("Co-op: can't host: " .. errmsg(err)) return end
  S.role = "host"
  toast("Co-op: opening a room...")
end

-- The town a guest arrives in: the host's, or the one its dungeon is reached from. Chronicle names a town by its map
-- (0-4); Chronicle Two by its area (world.get().town_map), its maps being numbered across the whole game.
local function arrival_town()
  local w = try(game.world.get) or {}
  if w.context == "dungeon" and w.dungeon_id then return DUNGEON_TOWN[w.dungeon_id] or 0 end
  if DC2 then
    local town = tonumber(w.town_map)
    if town and town >= 0 and town <= 4 then return town end
    return 0
  end
  local map = tonumber(w.map_id)
  if map and map >= 0 and map <= 4 then return map end
  return 0
end

-- Chronicle Two: the map itself. Palm Brinks has no Georama map, so its area names no map to start in; its own
-- number does (world.get().map_no). On a floor that number is still the town the host walked in from, which is
-- where a joiner arrives; the floor is offered to them from there.
local function arrival_map()
  if not DC2 then return nil end
  local w = try(game.world.get) or {}
  local map = tonumber(w.map_no)
  if map and map >= 0 and map == math.floor(map) and map < 10000 then return map end
  return nil
end

local function welcome(peer, hello)
  local id = type(hello) == "table" and hello.id
  if type(id) ~= "string" or not id:match("^[a-z0-9-]+$") then send(peer, "REFUSE", "your game sent no player id") return end
  if #id > 64 then send(peer, "REFUSE", "your game sent no player id") return end
  -- one player, one place in the room: a second game saying the same id waits until the first has gone (a guest
  -- coming back after a drop may be here before the host has seen its old connection go)
  for other, p in pairs(S.players) do
    if other ~= peer and p.id == id then
      if S.frame - (link.heard[other] or -100000) < 45 then
        S.greeted[peer] = nil
        send(peer, "REFUSE", "that player is already in the room")
        return
      end
      p.id, p.in_visit = nil, nil -- gone quiet: the newcomer is that player now
    end
  end
  -- Chronicle Two is played by two: one is Max and the other Monica (S.ROOM_FOR; a player who has gone quiet for
  -- ten seconds is no longer counted, so their place is free if they do not come back)
  local here = 1
  for other, p in pairs(S.players) do
    if other ~= peer and p.id and S.frame - (link.heard[other] or -100000) < 600 then here = here + 1 end
  end
  if here >= S.ROOM_FOR then
    S.greeted[peer] = nil
    send(peer, "REFUSE", DC2 and "this room already has its two players (Dark Cloud 2 is played by two)" or "this room is full")
    return
  end
  local name = type(hello.name) == "string" and cut((hello.name:gsub("%c", " ")), 24):match("^%s*(.-)%s*$") or ""
  if name == "" then name = "Player " .. (peer + 1) end
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
  -- Chronicle Two: a joiner brings a save of their own, whose story must be past the gate as the host's is
  local brings = S.guest_own[peer]
  if brings and brings < own.GATE then
    send(peer, "REFUSE", "your save has not talked to Donny at the Channel Entrance yet")
    return
  end
  S.players[peer].own = brings ~= nil
  -- back after a dropped connection: their visit went on, so no world, only "carry on"
  if hello.back then
    S.players[peer].in_visit = true
    if DC2 then send(peer, "SW", heroes.swapped and "is1" or "is0") end -- the heroes as they stand now
    send(peer, "RESUME")
    toast("Co-op: " .. name .. " is back in (reconnected)")
    show_room()
    return
  end
  local world, world_err = call(game.save.world_export)
  if not world or not world.data then
    moonmod.log("warn", "co-op: the world can't be shared: " .. errmsg(world_err)) -- the reason, for bug reports
    send(peer, "REFUSE", "the host's game can't share its world right now")
    return
  end
  local account = not S.players[peer].own and try(game.save.account_get, {id = id}) or nil
  send_pieces(peer, "WORLD", world.data)
  if S.players[peer].own then
    send(peer, "OWN")
    toast("Co-op: " .. name .. " joins with their own save")
  elseif type(account) == "table" and account.data then
    send_pieces(peer, "PLAYER", account.data)
    toast("Co-op: " .. name .. " is back")
  else
    send(peer, "NEW")
    toast("Co-op: " .. name .. " joins for the first time")
  end
  S.players[peer].in_visit = true
  if DC2 then send(peer, "SW", heroes.swapped and "is1" or "is0") end -- before START: the hero the joiner begins as
  local arrival = arrival_map()
  send(peer, "START", tostring(arrival_town()) .. (arrival and (" " .. arrival) or ""))
  show_room()
end

local function keep(peer, data)
  local player = S.players[peer]
  -- only a guest whose visit this host began, and only what a game's things look like
  if not (player and player.id and player.in_visit) or player.own or data:sub(1, 4) ~= THINGS_TAG then return end
  local ok, err = call(game.save.account_set, {id = player.id, name = player.name, data = data})
  if not ok then
    moonmod.log("warn", "co-op: keeping " .. player.name .. "'s things: " .. errmsg(err))
    return
  end
  if S.closing then S.closing.waiting[peer] = nil end
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
  local ready, why = own.take()
  if not ready then S.status = why return end
  local ok, err = net_open("join", {code = code})
  if not ok then S.status = "Can't join: " .. cut(errmsg(err), 60) return end
  S.role = "guest"
  S.guest = {world = nil, player = nil, new = false, map = nil, started = false}
  S.joined_at = S.frame
  S.status = "Joining " .. code .. "..."
end

-- Every piece of the host's answer has come: the visit begins.
local function begin_visit()
  local g = S.guest
  if not g or g.started or not g.world or not g.map or not (g.player or g.new) then return end
  g.started = true
  -- Only things that came out of this player's own save go back into it. A host that answered with things of its
  -- own keeping, or a new player's (PLAYER, NEW: an older host, or one that did not take the save), leaves the save
  -- alone: those things are the host's to keep, as in Chronicle.
  if own.slot and not g.own then
    moonmod.log("warn", "co-op: the host didn't take File " .. (own.slot + 1) .. "; it is left as it is")
    own.unused, own.slot, own.progress = own.slot + 1, nil, nil
  end
  heroes.apply() -- before the visit: it starts as the hero the room gives this game
  local ok, err = call(game.session.start, {visit = {world = g.world, player = g.player, map = g.map, map_no = g.map_no}})
  if not ok then
    S.status = "The visit could not start: " .. errmsg(err):sub(1, 60)
    stop()
    return
  end
  S.status = "Off to the host's world..."
  g.world, g.player = nil, nil -- the engine has them now
  own.things = nil
end

local function send_things()
  if S.role ~= "guest" or not (S.guest and S.guest.visiting) then return end
  if own.slot then -- a save of their own: the things go into it, not to the host
    if own.write() then S.kept_at = S.frame end
    return
  end
  local things = try(game.save.player_export)
  if things and things.data and send_pieces(0, "KEEP", things.data) then S.kept_at = S.frame end
end

-- The link ----------------------------------------------------------------------------------------------------------
-- Ping: every two seconds each game sends "PING frame" to the others, which answer "PONG frame" at once; the round
-- trip is that player's ping, on the HUD by their name. Any message is a sign of life: a player unheard for eight
-- seconds is "no signal" on the HUD, and the others are told once, and again when they're back.
--
-- A guest whose connection drops (not the host leaving) keeps playing its visit alone and joins the room again, every
-- five seconds for two minutes, saying "BACK id name": the host checks its mods as for a first join and answers
-- "RESUME" instead of its world. A host closing its room first says "BYE": every guest sends its things at once, and
-- the room closes when all have come (or after ten seconds).
--
-- Out of step: every five seconds the host says which floor it's on and how many doors it has opened there ("K scene
-- doors"). A guest on that floor built differently (another seed), or whose copies of the host's monsters can't be
-- made for a while, is offered to walk onto the floor again beside the host; one with fewer doors open asks for them
-- ("SYNC scene"), as does the Mod Manager's "Resync with the host".
local PING_EVERY, QUIET_LINK, REJOIN_EVERY, REJOIN_WAIT, CLOSE_WAIT, CHECK_EVERY = 120, 480, 300, 7200, 600, 300

local function peer_name(peer)
  return S.names[peer] or (S.players[peer] and S.players[peer].name) or (peer == 0 and "the host") or ("Player " .. tostring(peer))
end

function link.heard_from(peer)
  link.heard[peer] = S.frame
  if link.quiet[peer] then
    link.quiet[peer] = nil
    toast("Co-op: " .. peer_name(peer) .. " is back in touch")
    show_room()
  end
end

function link.pong(peer, rest)
  local at = tonumber(rest)
  -- a frame this game sent, not long ago: anything else is no answer
  if at and at <= S.frame and at >= S.frame - 36000 then link.ping[peer] = math.floor((S.frame - at) * 1000 / 60 + 0.5) end
end

function link.step()
  if S.frame % PING_EVERY == 0 then send("all", "PING", string.format("%d", S.frame)) end
  if S.frame % 600 == 0 then
    for key, p in pairs(S.pieces) do if S.frame - (p.at or 0) > 1800 then S.pieces[key] = nil end end
  end
  for peer, at in pairs(link.heard) do
    if not link.quiet[peer] and S.frame - at > QUIET_LINK then
      link.quiet[peer] = true
      toast(string.format("Co-op: no word from %s for %d seconds", peer_name(peer), QUIET_LINK // 60))
      show_room()
    end
  end
  if S.frame % 30 == 0 then show_room() end -- the pings on the HUD
end

-- How long ago a guest's things last went to the host, for the messages.
local function kept_ago()
  local s = math.floor((S.frame - (S.kept_at or 0)) / 60)
  return s < 2 and "just now" or (s .. " seconds ago")
end

-- A guest's things, as the visit ends under it: a save of its own (Chronicle Two) takes them now, while the visit
-- still runs; the host has them as last kept. Said as the end of a message: "; your things ...".
local function things_at_end()
  if own.slot and own.write() then return "; your things are in your save" end
  if own.slot then return "; your save has your things as of " .. kept_ago() end
  return "; your things were last kept " .. kept_ago()
end

-- A guest's connection dropped with the room still open: carry on alone and try to get back in.
function link.lost(reason)
  forget_all()
  mon.release()
  door.waiting = {}
  S.players, S.pieces, S.names = {}, {}, {}
  link.heard, link.ping, link.quiet, link.refused_since = {}, {}, {}, nil
  S.rejoin = {since = S.frame, next_try = S.frame + 60, tries = 0}
  moonmod.log("warn", "co-op: connection lost: " .. tostring(reason))
  toast("Co-op: the connection dropped; getting back into room " .. tostring(S.code) .. "...")
  show_room()
end

function link.give_up(why)
  S.status = "Couldn't get back into the room."
  stop(why .. things_at_end()) -- and the visit ends with it
end

function link.rejoin_step()
  local r = S.rejoin
  if S.frame - r.since > REJOIN_WAIT then link.give_up("couldn't get back into the room") return end
  if S.frame < r.next_try then return end
  -- in the room again and waiting for the host's word: no new try on top of it, for ten seconds
  if r.linked and S.frame - r.linked < 600 then return end
  if r.linked then r.linked = nil; try(game.net.leave) end
  r.next_try, r.tries = S.frame + REJOIN_EVERY, r.tries + 1
  local ok, err = net_open("join", {code = S.code})
  if not ok then moonmod.log("warn", "co-op rejoin: " .. errmsg(err)) end
end

-- The room closed under a guest: the host left (said goodbye or not), or this game's connection dropped.
function link.closed(reason)
  local visiting = S.role == "guest" and S.guest and S.guest.visiting
  reason = tostring(reason)
  if S.rejoin then
    -- a try that failed: the room is gone, or the next try may do it
    S.rejoin.linked = nil
    if reason:find("no room", 1, true) or reason:find("host left", 1, true) then link.give_up("the room is gone") end
    return
  end
  if visiting and not S.host_bye and not reason:find("host left", 1, true) then link.lost(reason) return end
  local why
  if S.host_bye then why = "the host closed the room" .. (own.slot and visiting and things_at_end() or "; your things were kept")
  elseif visiting then why = "the host's game left the room" .. things_at_end()
  else why = "the room closed: " .. reason end
  S.status = "The room closed: " .. cut(reason, 80)
  stop(why) -- the host's world went with the host: a visit ends, back to the title
  S.refresh_title = true
end

-- The host closing: guests' things first.
function link.close_room()
  if S.closing then stop("you closed the room") return end -- a second press: at once
  local waiting, any = {}, false
  for peer, p in pairs(S.players) do if p.id and not p.own then waiting[peer], any = true, true end end -- a save of their own needs no keeping
  if not any then
    -- a joiner with a save of their own is still told first, so their game writes their things into it before the
    -- visit ends with the room
    for _, p in pairs(S.players) do if p.id and p.in_visit then send("all", "BYE") break end end
    stop("you closed the room")
    return
  end
  S.closing = {since = S.frame, waiting = waiting}
  send("all", "BYE")
  toast("Co-op: closing the room; keeping your guests' things first (F10 again: close now)")
end

function link.closing_step()
  local c = S.closing
  local left = 0
  for _ in pairs(c.waiting) do left = left + 1 end
  if left == 0 then stop("you closed the room; save your game to keep your guests' things") return end
  if S.frame - c.since > CLOSE_WAIT then
    stop(string.format("you closed the room; %d guest%s didn't answer, so their things are as last kept",
                       left, left == 1 and "" or "s"))
  end
end

-- Whose floor this game is measured against: in Chronicle the host's; in Chronicle Two that of the player who runs
-- it, host or joiner, by name.
function link.whose(peer)
  if not DC2 then return "the host's" end
  return together.name(peer or 0) .. "'s"
end

-- Out of step with the host (Chronicle Two: with the player who runs the floor, either way round): offered once per
-- floor.
function link.out_of_step_here(why, peer)
  peer = DC2 and peer or 0
  if not (S.role == "guest" or (DC2 and S.role)) or not my_scene or link.out_of_step[my_scene] then return end
  link.out_of_step[my_scene] = true
  local host_scene = others[peer] and others[peer].scene
  moonmod.log("warn", "co-op: out of step on " .. my_scene .. ": " .. why)
  if not host_scene or host_scene:sub(1, 1) ~= "D" then toast("Co-op: " .. why) return end
  local who = DC2 and together.name(peer) or "the host"
  -- (Chronicle Two asks in its own message window, where only the question fits: the why is told on its own first)
  if DC2 then toast("Co-op: " .. why) end
  together.ask({title = "Out of step with " .. who, subtitle = why:sub(1, 96), yes_no = true, ask = "Walk in again beside " .. who .. "?", options = {
    {title = "Walk in again beside " .. who, subtitle = together.place(host_scene), pick = function() together.join(peer, host_scene) end},
    {title = "Stay as I am", subtitle = DC2 and "Mod Manager: Resync the floor" or "Mod Manager: Resync with the host"},
  }})
end

function link.host_check()
  if not (on_floor() and my_scene) then return end
  -- anyone on this dungeon floor, built like this one or not
  local floor = my_scene:match("^(D%d+:%-?%d+:)")
  local anyone = false
  for _, o in pairs(others) do if o.scene and o.scene:sub(1, #floor) == floor then anyone = true break end end
  if anyone then send("all", "K", my_scene .. " " .. #(door.log[my_scene] or {})) end
end

-- (Chronicle Two: either game checks against the other, since either may run the floor; peer is who said "K".)
function link.guest_check(rest, peer)
  peer = peer or 0
  local scene, doors = rest:match("^(%S+) (%d+)$")
  if not (scene and my_scene) then return end
  local hd, hf, hs = scene:match("^D(%d+):(%-?%d+):(%S+)$")
  local md, mf, ms = my_scene:match("^D(%d+):(%-?%d+):(%S+)$")
  if not (hd and md) or hd ~= md or hf ~= mf then return end -- not on the host's floor
  local w = try(game.world.get)
  if hs ~= ms then
    -- two games that built one floor apart each run their own (neither sees the other on it): the host's stands, as
    -- when two take one floor at once, and the joiner is the one offered to walk in again
    if DC2 and S.role == "host" then return end
    -- a back floor is built by the game itself, not from the room's seed: that one can't match
    if not (type(w) == "table" and w.back_floor) then link.out_of_step_here("your floor isn't built like " .. link.whose(peer), peer) end
  elseif tonumber(doors) > #(door.log[my_scene] or {}) then
    send(peer, "SYNC", my_scene)
  end
end

-- The host answers a guest's "SYNC scene": the doors opened there, and the clock (the host's alone to give).
function link.resync_for(peer, scene)
  for _, text in ipairs(door.log[scene] or {}) do send(peer, "E", scene .. " " .. text) end
  if S.role == "host" then send_clock() end
end

function link.resync()
  -- Chronicle Two: the host asks its joiner too, since a floor may be the joiner's to run
  local peer = S.role == "guest" and 0 or (DC2 and S.role == "host" and heroes.other()) or nil
  if not peer or not S.code or S.rejoin then
    toast(DC2 and "Co-op: there is no one in the room to resync with" or "Co-op: only a guest in a room resyncs with the host")
    return
  end
  send(peer, "SYNC", my_scene or "-")
  link.out_of_step[my_scene or "-"] = nil
  toast(DC2 and ("Co-op: asked " .. together.name(peer) .. " for this floor's open doors again") or
        "Co-op: asked the host for the doors and the time again")
end

-- Falling and getting back up -----------------------------------------------------------------------------------------
-- In a room, a player whose party is knocked out on a floor goes down rather than out (player.down_rule_set): they lie
-- there, the monsters pass them by, and their game says so ("DN down", then "DN out", "DN up"), which the others show
-- on that player's hero. Another player standing beside them holds Revive (R, or the right stick; in Dark Cloud 2 V,
-- or the left stick) for three seconds, which a hit breaks, or presses it once with a Revival Powder (Dark Cloud 2's
-- Resurrection Powder) in their bag, which it uses: the fallen player gets up with a third of their HP (half with the
-- powder). Their own Revival Powder still works first, as in the game.
--
-- Dark Cloud 2's pad gives R3 to the ridepod and the monster forms (and R, the keyboard's R2, to the first-person
-- view); L3 changes hero, which does nothing in a room, where each game plays one hero (party.room_hero_set). So
-- Revive is L3 there, and V, the keyboard's L3.
--
-- Down lasts fall.DOWN_FOR; then they're out: still lying there, back on their feet beside another player after a wait that
-- grows with each fall on the floor (30 seconds, then 15 more each time), or at once when no one else is left on the
-- floor. When everyone on the floor is down or out, the party has fallen: every game on it stands its player up and
-- walks them back to the town the dungeon is reached from, with all their things (the game's own knockout would have
-- halved their Gilda).
local fall = {state = "up", since = 0, deaths = 0, floor = nil, rule = nil, hold = nil, wiping = nil,
              TOWNS = {[0] = "chronicle:location:norune-village", "chronicle:location:matataki-village",
                       "chronicle:location:queens", "chronicle:location:muska-lacka", "chronicle:location:yellow-drops"}}
fall.DOWN_FOR, fall.OUT_FIRST, fall.OUT_MORE, fall.REVIVE_HOLD, fall.REVIVE_REACH, fall.WIPE_AFTER = 1800, 1800, 900, 180, 48, 120
fall.KEYS = DC2 and {"V", "Gamepad:leftstick"} or {"R", "Gamepad:rightstick"} -- Revive's keys, and as the player reads them
fall.KEYS_SAID = DC2 and "V / left stick" or "R / right stick"
fall.POWDER = DC2 and "Resurrection Powder" or "Revival Powder"

-- The rule follows the room: on while in one (and the setting is on), off otherwise.
-- A guest whose connection dropped keeps the rule while it gets back in (a blip is not a knockout): alone on the
-- floor it is down, then out, then up again by itself.
function fall.rule_step()
  local want = S.role ~= nil and S.code ~= nil and setting("down_not_out", true)
  if want ~= fall.rule then
    if not want then
      fall.release() -- out of the room while down: the game's own knockout
      fall.off_at = S.frame
    end
    local ok = call(game.player and game.player.down_rule_set, {enabled = want})
    if ok or not want then fall.rule = want end
  end
  -- Just off: a player knocked out in the very frame the room went is lying under a rule no one keeps any more.
  if not fall.rule and fall.off_at then
    if S.frame - fall.off_at > 120 then fall.off_at = nil else fall.release() end
  end
end

-- No one will revive a player once the rule is off: whoever is down then gets the game's own knockout. What the
-- game says counts (player.get's down), not only what this mod last saw.
function fall.release()
  local p = try(game.player and game.player.get)
  if fall.state ~= "up" or (type(p) == "table" and p.down == true) then
    call(game.player and game.player.give_up)
    fall.state = "up"
  end
end

function fall.say(state)
  fall.state, fall.since = state, S.frame
  if not S.rejoin then send("all", "DN", state) end -- out of the room: no one to tell
end

function fall.hear(peer, rest)
  local o = others[peer]
  if not o or not (rest == "down" or rest == "out" or rest == "up" or rest == "fell") then return end
  local was = o.down
  o.down = (rest == "down" or rest == "out") and rest or "up"
  -- the party fell: this one goes too. Only the word of a player who lay here themselves, to one who lies here.
  if rest == "fell" and was and was ~= "up" and fall.state ~= "up" and o.scene and o.scene == my_scene and not fall.wiping then
    fall.forced = true
  end
  if o.down ~= "up" and (was == nil or was == "up") and o.scene and o.scene == my_scene then
    toast("Co-op: " .. peer_name(peer) .. " is down! Stand beside them and hold Revive (" .. fall.KEYS_SAID .. ")")
  end
end

-- Get up: in place, or at a spot (beside another player).
function fall.get_up(hp_share, at, why, say)
  local p = try(game.player and game.player.get) or {}
  local hp = math.max(1, math.floor((tonumber(p.max_hp) or 3) * hp_share))
  local args = {hp = hp}
  if at then args.x, args.y, args.z = at.x, at.y, at.z end
  local ok, err = call(game.player and game.player.revive, args)
  if not ok and at then ok, err = call(game.player.revive, {hp = hp}) end -- that spot refused: in place
  if not ok then moonmod.log("warn", "co-op revive: " .. errmsg(err)) return false end
  fall.say(say or "up")
  fall.state = "up"
  fall.rising = S.frame + 20 -- the game stands the hero up on its next frames: still "down" until then
  if why then toast("Co-op: " .. why) end
  return true
end

-- The players on this floor besides this one, and whether any of them is on their feet.
function fall.floor_mates()
  local mates, standing = {}, nil
  for peer, o in pairs(others) do
    if o.scene and my_scene and o.scene == my_scene and S.frame - (o.heard or 0) < QUIET then
      mates[#mates + 1] = peer
      if (o.down or "up") == "up" and o.state then standing = standing or o end
    end
  end
  return mates, standing
end

-- This player: down, out, and back.
function fall.self_step()
  local p = try(game.player and game.player.get)
  local down = type(p) == "table" and p.down == true and not (fall.rising and S.frame < fall.rising)
  if my_scene ~= fall.floor then fall.floor, fall.deaths = my_scene, 0 end
  if not down then
    if fall.state ~= "up" then fall.say("up") end -- revived by the game itself (or left the floor)
    return
  end
  local mates, standing = fall.floor_mates()
  if fall.state == "up" then
    fall.deaths = fall.deaths + 1
    fall.say("down")
    toast(#mates > 0 and "Co-op: you're down. A friend can revive you; hold on"
                      or "Co-op: you're down, with no one else on this floor")
    return
  end
  if fall.state == "down" and S.frame - fall.since >= fall.DOWN_FOR then
    fall.say("out")
    toast(string.format("Co-op: you're out; back on your feet in %d seconds", (fall.OUT_FIRST + fall.OUT_MORE * (fall.deaths - 1)) // 60))
    return
  end
  if fall.state == "out" then
    local wait = fall.OUT_FIRST + fall.OUT_MORE * (fall.deaths - 1)
    if #mates == 0 then fall.get_up(1 / 3, nil, "no one else is on the floor: you get back up") return end
    if S.frame - fall.since >= wait and standing then
      -- beside them, where that is on this floor; a spot far off anything here is no spot: up in place
      local at = {x = standing.state.x, y = standing.state.y, z = standing.state.z}
      local here = type(p) == "table" and p.position or nil
      if here and (math.abs(at.x - here.x) > 4000 or math.abs(at.z - here.z) > 4000 or math.abs(at.y - here.y) > 1000) then at = nil end
      fall.get_up(1 / 3, at, "back on your feet beside the others")
    end
  end
end

-- The party has fallen: everyone on this floor down or out, for a moment (so the reports have come).
function fall.wipe_step()
  if fall.wiping then
    if S.frame >= fall.wiping.at then
      local town, map = fall.wiping.town, fall.wiping.map
      fall.wiping = nil
      local ok, err
      if DC2 then
        -- Chronicle Two: out of the dungeon by the map its own way out leads to (world.get().exit_map), or the
        -- town this player came into it from
        ok, err = call(game.world and game.world.enter_map, {map_no = map})
      else
        ok, err = call(game.world and game.world.transition, {id = town})
      end
      if not ok then toast("Co-op: can't walk back to town (" .. errmsg(err):sub(1, 60) .. ")") end
    end
    return
  end
  if fall.state == "up" or not on_floor() then fall.wipe_since, fall.forced = nil, nil return end
  if fall.forced then
    fall.forced, fall.wipe_since = nil, -1000000
  else
    for _, peer in ipairs(fall.floor_mates()) do
      if (others[peer].down or "up") == "up" then fall.wipe_since = nil return end
    end
  end
  fall.wipe_since = fall.wipe_since or S.frame
  if S.frame - fall.wipe_since < fall.WIPE_AFTER then return end
  fall.wipe_since = nil
  local d = tonumber(my_scene:match("^D(%d+):"))
  local town = fall.TOWNS[DUNGEON_TOWN[d or 0] or 0]
  local w = DC2 and try(game.world.get) or nil
  local map = type(w) == "table" and (tonumber(w.exit_map) or tonumber(w.map_no)) or nil
  if fall.get_up(1 / 2, nil, "the party fell; back to town, with all your things", "fell") then
    fall.wiping = {town = town, map = map, at = S.frame + 30}
  end
end

-- This player reviving another: Revive held beside a fallen player for three seconds, a hit breaking it; or pressed once
-- with a Revival Powder, which it uses.
function fall.powder()
  local got = try(game.items and game.items.owned)
  for _, it in ipairs(type(got) == "table" and got.items or {}) do
    local name = tostring(it.name):lower() -- (Chronicle's Revival Powder, Chronicle Two's Resurrection Powder)
    if (name == "revival powder" or name == "resurrection powder") and (tonumber(it.count) or 0) > 0 then return it end
  end
  return nil
end

function fall.bar(text)
  if text then try(game.render.layer_register, {id = "coop_revive", text = cut(text, 48)})
  else try(game.render.layer_remove, {id = "coop_revive"}) end
end

-- The room stopped: nothing of a fall is left to happen in the next one.
function S.stopped()
  fall.wiping, fall.forced, fall.wipe_since, fall.pending = nil, nil, nil, nil
  if fall.hold then fall.bar(nil) end
  fall.hold = nil
end

function fall.reviver_step()
  if fall.state ~= "up" or not on_floor() then fall.hold = nil return end
  local p = try(game.player and game.player.get)
  if type(p) ~= "table" or not p.position then fall.hold = nil return end
  -- the nearest fallen player within reach
  local target, best = nil, fall.REVIVE_REACH
  for peer, o in pairs(others) do
    if o.down and o.down ~= "up" and o.scene == my_scene and o.state then
      local d = math.sqrt((o.state.x - p.position.x) ^ 2 + (o.state.z - p.position.z) ^ 2)
      if d <= best then target, best = peer, d end
    end
  end
  local key = try(game.input.state, {id = "revive"})
  if AUTOTEST and AUTOTEST.hold_revive then key = {down = true} end -- the live test holds Revive
  local press = try(game.input.consume, {id = "revive"})
  if not target then
    if fall.hold then fall.bar(nil) end
    fall.hold = nil
    return
  end
  if press and press.pressed then
    -- the powder is used when the fallen player says it worked ("THX powder"), so none is lost on someone who
    -- got up, or left, in the meantime
    local powder = fall.powder()
    if powder and not (fall.pending and S.frame - fall.pending.at < 120) then
      if send(target, "RV", "powder") then
        fall.pending = {peer = target, id = powder.id, at = S.frame}
        fall.hold = nil
        return
      end
    end
  end
  if not (key and key.down) then
    if fall.hold then fall.bar(nil) end
    fall.hold = nil
    return
  end
  if not fall.hold or fall.hold.peer ~= target then fall.hold = {peer = target, since = S.frame, hp = p.hp} end
  if (tonumber(p.hp) or 0) < (tonumber(fall.hold.hp) or 0) then -- struck: start over
    fall.hold = {peer = target, since = S.frame, hp = p.hp}
    toast("Co-op: hit! Hold Revive again")
    return
  end
  local done = S.frame - fall.hold.since
  fall.bar(string.format("Reviving %s... %d%%", peer_name(target), math.min(100, done * 100 // fall.REVIVE_HOLD)))
  if done >= fall.REVIVE_HOLD then
    send(target, "RV", "hold")
    fall.hold = nil
    fall.bar(nil)
  end
end

-- Another player revived this one.
function fall.revived(peer, rest)
  if fall.state == "up" then return end
  -- only a player standing on this floor, and beside this one where both games know where they stand
  local o = others[peer]
  if not (o and o.scene and o.scene == my_scene and (o.down or "up") == "up") then return end
  local p = try(game.player and game.player.get)
  if type(p) == "table" and p.position and o.state then
    local d = math.sqrt((o.state.x - p.position.x) ^ 2 + (o.state.z - p.position.z) ^ 2)
    if d > fall.REVIVE_REACH + 400 then return end -- (what each game knows of the other is a moment old)
  end
  local powder = rest == "powder"
  if fall.get_up(powder and 1 / 2 or 1 / 3, nil, peer_name(peer) .. " revived you") then
    send(peer, "THX", powder and "powder" or nil)
  end
end

-- The player this one revived is up.
function fall.thanked(peer, rest)
  local w = fall.pending
  if rest == "powder" and w and w.peer == peer and S.frame - w.at <= 600 then
    fall.pending = nil
    local took = try(game.items.remove, {id = w.id, count = 1})
    if type(took) == "table" and (tonumber(took.removed) or 0) > 0 then
      toast("Co-op: you used a " .. fall.POWDER .. " on " .. peer_name(peer))
    end
  end
  toast("Co-op: " .. peer_name(peer) .. " is back on their feet")
end

function fall.step()
  fall.rule_step()
  if not fall.rule then return end
  fall.self_step()
  fall.reviver_step()
  fall.wipe_step()
end

-- Messages ----------------------------------------------------------------------------------------------------------

-- What a host takes from a game that has joined the room but whose visit it hasn't begun, and what a guest leaves
-- alone until its own visit has.
S.BEFORE_VISIT = {PING = true, PONG = true, N = true, P = true, MODS = true, OWN = true, HELLO = true, BACK = true, LEAVING = true}
S.VISIT_ONLY = {TOWN = true, C = true, RV = true, M = true, D = true, E = true, B = true, X = true}

local function message(peer, data)
  local kind, rest = data:match("^(%u+) ?(.*)$")
  if not kind then return end
  link.heard_from(peer)
  if S.role == "host" then
    local p = S.players[peer]
    if not (p and p.in_visit) and not S.BEFORE_VISIT[kind] then return end
  elseif S.VISIT_ONLY[kind] and not (S.guest and S.guest.visiting) then
    -- Chronicle Two: the host's changes to the world, and its towns, are held until the visit begins (shared.hold)
    if DC2 and peer == 0 and S.role == "guest" and S.guest and kind == "X" then shared.hold(rest) end
    if DC2 and peer == 0 and S.role == "guest" and S.guest and kind == "TOWN" then
      local whole = take_piece(peer, kind, rest)
      if whole then shared.hold_town(whole) end
    end
    return
  end
  if kind == "PING" then if #rest <= 12 and rest:match("^%d+$") then send(peer, "PONG", rest) end return end
  if kind == "PONG" then link.pong(peer, rest) return end
  if kind == "DN" then fall.hear(peer, rest) return end
  if kind == "RV" then fall.revived(peer, rest) return end
  if kind == "THX" then fall.thanked(peer, rest) return end
  if kind == "P" then hear_position(peer, rest) return end
  if kind == "F" then S.shots.hear(peer, rest) return end
  if kind == "N" then hear_name(peer, rest) return end
  if kind == "W" then hear_place(rest) return end
  if kind == "O" then hear_outfit(peer, rest) return end
  if kind == "SC" then hear_scene(peer, rest) return end
  if kind == "B" then hear_builder(peer, rest) return end
  if kind == "V" then together.hear(peer, rest) return end
  if kind == "SW" then heroes.hear(peer, rest) return end
  if kind == "X" then shared.hear(peer, rest) return end
  if kind == "C" then if S.role == "guest" and peer == 0 then hear_clock(rest) end return end
  if kind == "M" then mon.hear(peer, rest) return end
  if kind == "E" then door.hear(rest) return end
  if kind == "H" then if mon.leading() then mon.hit_on_host(peer, rest) end return end
  if kind == "D" then
    -- a blow from the game that runs this floor's monsters: the host's, or in Chronicle Two the leader's
    if DC2 and (mon.puppets and mon.from == peer) or (not DC2 and S.role == "guest" and peer == 0) then mon.struck(peer, rest) end
    return
  end
  if kind == "TOWN" then
    local whole = take_piece(peer, kind, rest)
    if whole then town_from(peer, whole) end
    return
  end
  -- Chronicle Two: a floor is checked and resynced either way round (Chronicle: a guest against the host, below)
  if DC2 and kind == "K" then link.guest_check(rest, peer) return end
  if DC2 and kind == "SYNC" then link.resync_for(peer, rest) return end
  if S.role == "host" then
    if kind == "MODS" then
      local whole = take_piece(peer, kind, rest)
      if whole then S.guest_mods[peer] = rm.decode_list(whole) end
    elseif kind == "OWN" then
      local progress = #rest <= 6 and tonumber(rest:match("^%d+$"))
      if progress and not S.greeted[peer] then S.guest_own[peer] = progress end
    elseif kind == "HELLO" or kind == "BACK" then
      if S.greeted[peer] then return end -- once a connection: a second hello would send the world again
      S.greeted[peer] = true
      local id, name = rest:match("^(%S+) ?(.*)$")
      welcome(peer, {id = id, name = name, back = kind == "BACK"})
    elseif kind == "LEAVING" then
      if S.players[peer] then S.players[peer].leaving = true end
    elseif kind == "SYNC" then
      link.resync_for(peer, rest)
    elseif kind == "KEEP" then
      local whole = take_piece(peer, kind, rest)
      if whole then keep(peer, whole) end
    end
  elseif S.role == "guest" and peer == 0 then
    local g = S.guest
    if kind == "K" then link.guest_check(rest) return end
    if kind == "BYE" then
      S.host_bye = S.frame
      send_things()
      toast(own.slot and "Co-op: the host is closing the room; your things are in your save" or
            "Co-op: the host is closing the room; your things are going to them")
      return
    end
    if kind == "RESUME" then
      S.rejoin = nil
      S.kept_at = -100000 -- the things go to the host again at once
      toast("Co-op: back in the room")
      show_room()
      return
    end
    if kind == "NEEDMODS" then
      local whole = take_piece(peer, kind, rest)
      if whole then
        local list = rm.decode_need(whole)
        local mine = rm.loaded() or {}
        for _, n in ipairs(list) do if n.what == "disable" and mine[n.id] then n.name = mine[n.id].name end end
        moonmod.storage.set("needed", {list = list, code = S.code})
        S.status = string.format("This room needs %d mod change%s first.", #list, #list == 1 and "" or "s")
        -- (back after a drop, with mods changed since: the visit ends with the room)
        stop("this room needs mods you don't have: " .. rm.summary(list))
        S.refresh_title = true
      end
      return
    elseif kind == "SETTINGS" then
      local whole = take_piece(peer, kind, rest)
      if whole then
        local n = rm.apply_settings(whole)
        if n > 0 and not S.rejoin then toast(string.format("Co-op: the host's settings for %d mod%s, for this visit", n, n == 1 and "" or "s")) end
      end
    elseif kind == "WORLD" then
      g.world = take_piece(peer, kind, rest) or g.world
      if g.world then moonmod.storage.set("needed", nil) end
    elseif kind == "PLAYER" then g.player = take_piece(peer, kind, rest) or g.player
    elseif kind == "NEW" then g.new = true
    elseif kind == "OWN" then -- the host took this player's own save: its things are the ones read before joining
      g.player = own.things
      g.new = g.player == nil
      g.own = own.slot ~= nil and own.things ~= nil
    elseif kind == "START" then
      -- "town" or "town map_no": the town's number, and (Chronicle Two) the map to start in
      local town, map_no = rest:match("^(%d+) ?(%d*)$")
      g.map = tonumber(town)
      g.map_no = tonumber(map_no)
      if g.map_no and g.map_no >= 10000 then g.map_no = nil end
    elseif kind == "REFUSE" then
      if S.rejoin and rest:find("already in the room", 1, true) then
        -- the host hasn't seen this game's old connection go yet: the next try may do it
        try(game.net.leave)
        S.rejoin.linked = nil
        return
      end
      S.status = "The host turned the visit away: " .. cut(rest, 80)
      stop("the host turned the visit away: " .. rest)
      S.refresh_title = true
      return
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
        heroes.apply()
        shared.watch()
        toast("Co-op room " .. tostring(e.code) .. ": friends join with this code from the title screen")
      else
        -- the mods this game plays, then "HELLO id name": the player id first, then the name, which may hold spaces
        local mine = rm.loaded()
        if mine then send_pieces(0, "MODS", rm.encode_list(mine)) end
        if own.slot then send(0, "OWN", tostring(own.progress)) end -- before hello: the save this player brings
        send(0, S.rejoin and "BACK" or "HELLO", me.id .. " " .. (my_name() or ""))
        if not S.rejoin then S.status = "Joined " .. tostring(e.code) .. "; the host is sending their world..." end
        if S.rejoin then S.rejoin.linked = S.frame end
      end
      if S.role == "guest" then link.heard_from(0) end -- the host is there from the start; a host doesn't hear itself
      show_room()
    elseif e.kind == "joined" then
      if S.role == "host" then S.players[e.peer] = S.players[e.peer] or {id = nil, name = e.name} end
      if e.peer ~= nil then S.greeted[e.peer] = nil end
      show_room()
    elseif e.kind == "left" then
      local p = S.players[e.peer]
      S.players[e.peer] = nil
      S.guest_mods[e.peer] = nil
      forget(e.peer)
      builders[e.peer] = nil
      if e.peer ~= nil then
        S.greeted[e.peer], together.owed[e.peer], together.got[e.peer] = nil, nil, nil
        local mine = tostring(e.peer) .. ":"
        for key in pairs(S.pieces) do if key:sub(1, #mine) == mine then S.pieces[key] = nil end end
      end
      if S.closing then S.closing.waiting[e.peer] = nil end
      if S.role == "host" and p then
        if p.leaving or not p.id then toast("Co-op: " .. tostring(p.name or "a player") .. " left")
        else toast("Co-op: " .. tostring(p.name or "a player") .. "'s connection dropped; they can come back in for two minutes") end
      end
      show_room()
    elseif e.kind == "message" then
      -- one message that can't be read costs that message, never the rest of this frame's (a gift among them)
      if type(e.data) == "string" and type(e.peer) == "number" then
        local ok, err = pcall(message, e.peer, e.data)
        if not ok then
          link.unread = (link.unread or 0) + 1
          if link.unread <= 20 then
            moonmod.log("warn", "co-op: a message from player " .. tostring(e.peer) .. " couldn't be read: " .. tostring(err):sub(1, 160))
          end
        end
      end
    elseif e.kind == "closed" then
      if S.role == "host" then
        S.status = "The room closed: " .. tostring(e.reason)
        -- (guests who bring a save of their own, Chronicle Two's, leave nothing in the host's to keep)
        local keeps = not DC2
        for _, p in pairs(S.players) do if p.id and not p.own then keeps = true end end
        stop(S.closing and "you closed the room" or
             ("the room closed (" .. tostring(e.reason) .. ")" .. (keeps and "; save your game to keep your guests' things" or "")))
      else
        link.closed(e.reason)
      end
    end
  end
end

-- Events ------------------------------------------------------------------------------------------------------------

moonmod.on("game.tick", function(e)
  S.frame = e and e.frame or S.frame + 1
  pump()
  fall.step()
  -- a guest getting back in after a drop plays on alone meanwhile
  if S.rejoin then link.rejoin_step() return end
  if S.closing then link.closing_step() end
  if S.role and S.code then link.step() end
  -- A room is one save's: a host whose game leaves its story (to the title, to another mode) closes it, so no
  -- guest's things or town reach whatever loads next.
  if S.role == "host" and S.frame % 60 == 0 then
    local session = try(game.session.get)
    if type(session) == "table" and session.kind ~= nil and session.kind ~= "story" then
      stop("your game left its story, so the room is closed")
      return
    end
  end
  -- (Chronicle Two: both games say their floor, since either may run it)
  if (S.role == "host" or (DC2 and S.role == "guest" and S.guest and S.guest.visiting)) and S.code and S.frame % CHECK_EVERY == 0 then
    link.host_check()
  end
  -- a host that never answers a join
  if S.role == "guest" and S.guest and not S.guest.started and S.joined_at and S.frame - S.joined_at > 1800 then
    S.status = "The host didn't send their world; try again."
    stop("the host didn't answer")
    S.refresh_title = true
    return
  end
  if S.role and S.code and S.frame % SEND_EVERY == 0 then
    send_position()
    show_others()
  end
  if S.role and S.code then mon.tick(); S.shots.send() end
  if S.role then together.tick(); together.retry() end
  if S.role and S.code and S.frame % 10 == 0 then door.step() end
  if S.role == "host" and S.code and S.frame % CLOCK_EVERY == 0 then send_clock() end
  if S.role and S.code and S.frame % 30 == 0 then
    watch_editing()
    retry_towns()
  end
  if S.role == "guest" and S.guest and S.guest.visiting then
    local every = math.max(15, math.min(600, setting("keep_every", 60))) * 60
    local soon = S.keep_soon and S.frame >= S.keep_soon -- after a gift, given or got
    if soon then S.keep_soon = nil end
    if soon or S.frame - S.kept_at >= every then
      S.kept_at = S.frame
      send_things()
    end
    -- a host that said goodbye and then didn't go
    if S.host_bye and S.frame - S.host_bye > 1200 then S.host_bye = nil end
  elseif S.keep_soon then
    S.keep_soon = nil -- the host's things are in its own save
  end
end)

moonmod.on("game.session.started", function(e)
  if type(e) == "table" and e.kind == "visit" and e.owner == "moonmod.coop" and S.guest then
    S.guest.visiting = true
    S.kept_at = S.frame
    shared.watch() -- from here on: the world this visit began with is what the two games share
    if shared.on then shared.take_held() end -- and what the host changed while it began
    toast(own.slot and ("Co-op: you are in the host's world. Your things are saved to File " .. (own.slot + 1) ..
                        " as you play; its story stays your own.") or
          own.unused and ("Co-op: you are in the host's world. The host's game didn't take your save, so File " ..
                          own.unused .. " stays as it is; your things here are kept by the host.") or
          "Co-op: you are in the host's world. Your own saves stay as they are.")
    own.unused = nil
  end
end)

moonmod.on("game.session.ended", function(e)
  if type(e) == "table" and e.kind == "visit" and S.role == "guest" then
    -- ended from the game's own menu: the host hears it was a leave, not a drop. (This game's things can't go with
    -- it any more: the visit they were in is over. They are as last kept.)
    if S.guest and S.guest.visiting and S.code and not S.rejoin then try(game.net.send, {to = 0, data = "LEAVING"}) end
    if S.guest then S.guest.visiting = false end
    stop()
  end
end)

-- This mod switched off (or the game closing) with a room open: the room closes, and no one is left lying under a
-- rule that nothing keeps.
moonmod.on("runtime.unloaded", function()
  if S.role then stop() end
  fall.release()
  if fall.rule then call(game.player and game.player.down_rule_set, {enabled = false}) end
  fall.rule, fall.off_at = false, nil
end)

moonmod.on("game.session.failed", function(e)
  if type(e) == "table" and e.kind == "visit" then
    S.status = "The visit could not start: " .. cut(tostring(e.reason), 60)
    stop()
    S.refresh_title = true
  end
end)

-- Leaving a visit: the things go to the host first, then the session ends.
local function leave()
  if S.role == "guest" and S.guest and S.guest.visiting then
    if S.rejoin then
      stop("you left while out of the room" .. things_at_end()) -- the visit ends with it
      return
    end
    send(0, "LEAVING")
    send_things()
    toast(own.slot and "Co-op: your things are in your save; leaving..." or "Co-op: your things went to the host; leaving...")
    try(game.session.finish)
  elseif S.role == "host" then
    link.close_room()
  elseif S.role then
    stop("you closed the room")
  end
end

-- Mod Manager actions and keys --------------------------------------------------------------------------------------

-- Chronicle Two with saves of their own (save.slots_list): a joiner's things go into their save, and the host's save
-- keeps no one's, so the buttons about kept guests are not there; a floor is resynced with whoever runs it.
local OWN_SAVES = DC2 and type(game.save) == "table" and type(game.save.slots_list) == "function"
for _, a in ipairs({
  {"host", "Host a co-op room", "Open a room for friends to join with its code (F8)"},
  OWN_SAVES and {"leave", "Leave or close co-op", "A joiner's things go into their own save first (F10)"}
             or {"leave", "Leave or close co-op", "A guest's things go to the host first (F10)"},
  not OWN_SAVES and {"guests", "Guests this save keeps", "The friends whose things this save keeps, by name"} or false,
  {"give", "Give to a player", "Give another player in the room Gilda or items from your bag (F7)"},
  {"follow", "Join a player", "Go to where another player in the room is now"},
  DC2 and {"resync", "Resync the floor", "Ask the other player again for this floor's open doors"}
       or {"resync", "Resync with the host", "A guest asks the host again for the floor's open doors and the time"},
  not OWN_SAVES and {"forget", "Forget guests not here", "Press twice: this save stops keeping the things of guests not in the room now"} or false,
  {"needed", "Mods needed to join", "The mods a room asked this game to enable, update or turn off, still to do"},
}) do if a then try(game.ui.register, {id = a[1], label = a[2], description = a[3]}) end end
if DC2 then
  try(game.ui.register, {id = "swap", label = "Ask to swap heroes", description = "Ask the other player to trade Max and Monica with you (F9)"})
  try(game.input.bind, {id = "swap_key", keys = {"F9"}})
  moonmod.on("game.tick", function()
    local k = try(game.input.consume, {id = "swap_key"})
    if k and k.pressed then heroes.ask() end
  end)
end

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
  elseif a.id == "resync" then link.resync()
  elseif a.id == "swap" then heroes.ask()
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
try(game.input.bind, {id = "revive", keys = fall.KEYS})
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
  -- Chronicle Two: the save this player brings, one of theirs past the gate
  local saves = own.saves()
  local pick = saves and own.picked(saves)
  entries[#entries + 1] = {id = "join", label = "Join room " .. code, enabled = not S.role and (saves == nil or pick ~= nil)}
  entries[#entries + 1] = {id = "clear", label = "Clear the code"}
  if saves then
    entries[#entries + 1] = {id = "save", label = pick and ("Your save: " .. own.label(pick)) or "Your save: none yet",
                             enabled = not S.role and #saves > 1}
  end
  local lines = {
    "Join a friend's world with their room's five letters.",
    "Type the letters, or Cross on one steps it on, Square back.",
    S.status or ("You are " .. (my_name() or "nameless (set a name in the mod's settings)") .. "."),
  }
  if saves then
    lines[#lines + 1] = pick and "Your things come from your save and go back into it." or own.CLOSED
  end
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
  if DC2 then -- Chronicle Two's page takes eight lines of 96 bytes, and refuses the whole page past that
    while #lines > 8 do table.remove(lines) end
    for i = 1, #lines do lines[i] = cut(lines[i], 96) end
  end
  return {title = "ONLINE CO-OP", subtitle = "Visit a friend's " .. GAME_NAME, root = true, hint = "", lines = lines,
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
  elseif entry == "save" then
    own.pick_next()
    show(7)
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
  if tonumber(AUTOTEST.revive_reach) then fall.REVIVE_REACH = tonumber(AUTOTEST.revive_reach) end -- headless heroes can't walk over
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
    local pings = {}
    for peer, ms in pairs(link.ping) do pings[#pings + 1] = peer .. ":" .. ms end
    table.sort(pings)
    moonmod.log("info", string.format("COOPTEST state frame=%d role=%s code=%s visiting=%s scene=%s context=%s pos=%s puppets=%s mons=%s link=%s pings=[%s] peers=[%s]",
      S.frame, tostring(S.role), tostring(S.code), tostring(S.guest and S.guest.visiting or false), tostring(my_scene),
      tostring(w.context), pos, tostring(mon.puppets), tostring(mon.count or "-"), S.rejoin and "rejoin" or "ok",
      table.concat(pings, " "), table.concat(peers, " ")))
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
    -- a guest whose connection should drop: once it has been on a floor this long, its link goes as a cable pulled
    if AUTOTEST.drop_after and S.role == "guest" and S.guest and S.guest.visiting and on_floor() and not said.dropped then
      said.drop_since = said.drop_since or S.frame
      if S.frame - said.drop_since >= AUTOTEST.drop_after then
        said.dropped = true
        moonmod.log("info", "COOPTEST dropping")
        try(game.net.leave)
        link.lost("the live test pulled the cable")
      end
    end
    -- knocked out (down, not out): at these frames after first standing on a floor with another player
    if AUTOTEST.knocks and S.role and on_floor() then
      for _, o in pairs(others) do
        if o.scene == my_scene then said.together_since = said.together_since or S.frame end
      end
      said.knocked = said.knocked or 0
      local at = AUTOTEST.knocks[said.knocked + 1]
      if at and said.together_since and S.frame - said.together_since >= at then
        said.knocked = said.knocked + 1
        local hit = try(game.player.damage, {amount = 32767})
        moonmod.log("info", "COOPTEST knocked " .. said.knocked .. " hp=" .. tostring(type(hit) == "table" and hit.hp))
      end
    end
    if fall.state ~= said.fall then
      said.fall = fall.state
      moonmod.log("info", "COOPTEST fall " .. fall.state .. " frame=" .. S.frame)
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
    if AUTOTEST.swap_after and not said.swapped and heroes.set and heroes.other() then
      said.swap_since = said.swap_since or S.frame
      if S.frame - said.swap_since >= AUTOTEST.swap_after then
        said.swapped = true
        moonmod.log("info", "COOPTEST swap asking")
        heroes.ask()
      end
    end
    if S.frame % 60 == 0 then
      local w = try(game.world.get) or {}
      local p = try(game.player and game.player.get) or {}
      local hero = tostring(w.room_hero) .. "/" .. tostring(p.town_character or p.character)
      if hero ~= said.hero then
        said.hero = hero
        moonmod.log("info", "COOPTEST hero " .. hero .. " frame=" .. S.frame)
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
return {state = S, me = me, piece = PIECE, mods = rm, link = link, fall = fall, together = together, door = door, own = own,
        heroes = heroes, shared = shared,
        game = GAME, town_tag = TOWN_TAG, dungeons = DUNGEONS, towns = TOWN_NAMES}
