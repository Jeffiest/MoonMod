-- Online Co-op (mods/moonmod.coop) as two games: a host and a guest, each the mod in its own fake game, talking
-- through a fake relay. Usage, from the repository root:  lua tools/tests/coop/test_coop.lua
local root = arg and arg[0] and arg[0]:match("^(.*)/tools/tests/coop/") or "."
local MOD = root .. "/mods/moonmod.coop/main.lua"

local passed, failed = 0, 0
local function check(ok, what, detail)
  if ok then passed = passed + 1; print("  ok   " .. what)
  else failed = failed + 1; print("  FAIL " .. what .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or "")) end
end

-- The relay: rooms by code, players by id, messages queued for each game's net.receive.
local relay = {rooms = {}}
local function queue(game_state, event) game_state.net_events[#game_state.net_events + 1] = event end

local function make_game(name)
  local S = {name = name, handlers = {}, storage = {}, settings = {name = name}, toasts = {}, layers = {},
             net_events = {}, net = nil, session = {kind = "story"}, accounts = {}, frame = 0, keys = {},
             world = "DCW1" .. string.rep("w", 30000) .. name, things = "DCP1" .. string.rep("p", 20000) .. name,
             map = {context = "georama", map_id = 2}, title = nil, started = nil, imported = {},
             avatars = {}, seeds = {}, player = {character = "toan"},
             monsters = {}, avatar_hits = {}, puppets = nil, mirror_hits = {}, strikes = {},
             doors_out = {}, doors_run = {}, door_busy = false,
             towns = {[0] = "DCT10:start", "DCT11:start", "DCT12:start", "DCT13:start", "DCT14:start"}}
  local env = setmetatable({}, {__index = _G})
  env.moonmod = {
    on = function(event, fn) S.handlers[event] = S.handlers[event] or {}; table.insert(S.handlers[event], fn) end,
    log = function() end,
    storage = {get = function(k) return S.storage[k] end, set = function(k, v) S.storage[k] = v end},
    settings = {get = function(k) return S.settings[k] end},
  }
  local function net_send(args)
    local room = S.net and relay.rooms[S.net.code]
    if not room then return nil, {message = "not in a session"} end
    local to = args.to
    for id, other in pairs(room.players) do
      if id ~= S.net.id and (to == "all" or to == id) then queue(other, {kind = "message", peer = S.net.id, data = args.data}) end
    end
    return {sent = true}
  end
  env.game = {
    ui = {notify = function(n) S.toasts[#S.toasts + 1] = n.message end, register = function() return true end},
    render = {layer_register = function(l) S.layers[l.id] = l.text end, layer_remove = function(l) S.layers[l.id] = nil end},
    input = {bind = function() return true end, consume = function(a) local p = S.keys[a.id]; S.keys[a.id] = nil; return {pressed = p} end},
    title = {mode_register = function(d) S.title = d; return true end, mode_set = function(d) S.title = d; return true end},
    world = {
      get = function() return S.map end,
      avatar_set = function(a) S.avatars[a.slot] = a; return {slot = a.slot, shown = true} end,
      avatar_clear = function(a) if a and a.slot then S.avatars[a.slot] = nil else S.avatars = {} end; return {cleared = true} end,
    },
    player = {get = function() return S.player end},
    monsters = {
      mirror_get = function()
        local hits = S.avatar_hits
        S.avatar_hits = {}
        return {monsters = S.monsters, hits = hits}
      end,
      puppet_set = function(a) S.puppets = a.monsters; return {followed = {}, refused = {}} end,
      puppet_clear = function() S.puppets = nil; return {cleared = true} end,
      mirror_hit = function(a) S.mirror_hits[#S.mirror_hits + 1] = a; return {slot = a.slot, damage = a.damage} end,
    },
    combat = {strike_player = function(a) S.strikes[#S.strikes + 1] = a; return {} end},
    dungeons = {
      set_seed = function(a) S.seeds[#S.seeds + 1] = a.seed; return {seed = a.seed} end,
      shared_events_get = function() local out = S.doors_out; S.doors_out = {}; return {events = out} end,
      shared_event_run = function(a)
        if S.door_busy then return nil, {code = "failed", message = "busy: another player's door is already waiting"} end
        S.doors_run[#S.doors_run + 1] = a
        return {queued = true}
      end,
    },
    georama = {
      town_export = function(a) return {town_id = a.town_id, data = S.towns[a.town_id]} end,
      town_import = function(a)
        if S.busy_town == a.town_id then return nil, {code = "failed", message = "busy: the player is editing"} end
        S.towns[a.town_id] = a.data
        return {town_id = a.town_id, imported = true, reloaded = S.map.town_map == a.town_id}
      end,
    },
    session = {
      get = function() return S.session end,
      start = function(args)
        assert(args.visit and args.visit.world and args.visit.map, "a visit needs a world and a map")
        S.started = args.visit
        S.session = {kind = "visit", owner = "moonmod.coop"}
        S.pending_event = {"game.session.started", {kind = "visit", owner = "moonmod.coop", map = args.visit.map}}
        return {queued = true}
      end,
      finish = function() S.session = {kind = "title"}; S.pending_event = {"game.session.ended", {kind = "visit"}}; return {} end,
    },
    save = {
      world_export = function() return {data = S.world} end,
      player_export = function() return {data = S.things} end,
      account_get = function(a) local x = S.accounts[a.id]; return x and {id = a.id, name = x.name, data = x.data} or {} end,
      account_set = function(a) S.accounts[a.id] = {name = a.name, data = a.data}; return {kept = true} end,
    },
    net = {
      host = function(a)
        local code = "AB" .. tostring(#relay.rooms + 3) .. "CD"
        code = ("ABCDE"):sub(1, 5)
        relay.rooms[code] = {players = {[0] = S}, version = a.version}
        S.net = {code = code, id = 0}
        queue(S, {kind = "connected", peer = 0, code = code})
        return {state = "connecting"}
      end,
      join = function(a)
        local room = relay.rooms[a.code]
        if not room or room.version ~= a.version then
          queue(S, {kind = "closed", reason = not room and "no room with that code" or "another version"})
          return {state = "connecting"}
        end
        local id = 1
        while room.players[id] do id = id + 1 end
        room.players[id] = S
        S.net = {code = a.code, id = id}
        queue(S, {kind = "connected", peer = id, code = a.code})
        queue(room.players[0], {kind = "joined", peer = id, name = a.name})
        return {state = "connecting"}
      end,
      send = net_send,
      receive = function()
        local out = S.net_events
        S.net_events = {}
        return {events = out}
      end,
      leave = function()
        local room = S.net and relay.rooms[S.net.code]
        if room then
          room.players[S.net.id] = nil
          for id, other in pairs(room.players) do
            if S.net.id == 0 then queue(other, {kind = "closed", reason = "the host left"}); other.net = nil
            else queue(other, {kind = "left", peer = S.net.id}) end
          end
          if S.net.id == 0 then relay.rooms[S.net.code] = nil end
        end
        S.net = nil
        return {left = true}
      end,
    },
  }
  local chunk = assert(loadfile(MOD, "t", env))
  S.mod = chunk()
  function S.emit(event, payload) for _, fn in ipairs(S.handlers[event] or {}) do fn(payload) end end
  function S.tick(n)
    for _ = 1, n or 1 do
      S.frame = S.frame + 1
      S.emit("game.tick", {frame = S.frame})
      if S.pending_event then local e = S.pending_event; S.pending_event = nil; S.emit(e[1], e[2]) end
    end
  end
  function S.last_toast() return S.toasts[#S.toasts] or "" end
  return S
end

local function both(a, b, n) for _ = 1, n or 1 do a.tick(); b.tick() end end
local function find_toast(g, pattern) for _, t in ipairs(g.toasts) do if t:find(pattern) then return true end end return false end

print("A first visit")
local host = make_game("Toan")
local guest = make_game("Xiao")
check(guest.title and guest.title.title == "ONLINE CO-OP", "the title screen has Online Co-op")
check(guest.storage.me and guest.storage.me.id:match("^p%x+$") and guest.storage.me.id ~= host.storage.me.id, "each game makes its own player id")
host.keys.host_key = true
both(host, guest, 2)
check(host.net and host.net.code == "ABCDE" and host.layers.coop == "CO-OP ABCDE  1 of 4", "F8 opens a room and shows its code", host.layers.coop)
check(find_toast(host, "Co%-op room ABCDE"), "the host is told the code")
-- the guest types the code on the title page
for i = 1, 5 do
  local target = ("ABCDE"):sub(i, i)
  for _ = 1, 40 do
    if guest.title.entries[i].label:sub(-1) == target then break end
    guest.emit("game.title.selected", {entry = "c" .. i})
  end
end
check(guest.title.entries[6].label == "Join room ABCDE", "the guest sets the code letter by letter", guest.title.entries[6].label)
guest.emit("game.title.selected", {entry = "join"})
both(host, guest, 6)
check(guest.started and guest.started.world == host.world, "the guest's visit takes the host's whole world (in pieces)",
      guest.started and #tostring(guest.started.world))
check(guest.started and guest.started.player == nil and guest.started.map == 2, "a first-timer is a new account, in the host's town",
      guest.started and guest.started.map)
check(find_toast(host, "Xiao joins for the first time"), "the host hears who joined")
check(host.layers.coop == "CO-OP ABCDE  2 of 4", "the host's HUD counts two", host.layers.coop)
check(find_toast(guest, "host's world"), "the guest is told it is in the host's world")

print("The guest's things go to the host")
guest.things = "DCP1" .. string.rep("q", 30000) .. "after a fight"
both(host, guest, 60 * 60 + 2)
local kept = host.accounts[guest.storage.me.id]
check(kept and kept.data == guest.things and kept.name == "Xiao", "after a minute the host keeps the guest's things, under its id",
      kept and #kept.data)
check(find_toast(host, "save your game"), "and says to save to keep them")

print("Leaving and coming back")
guest.things = "DCP1 the very last things"
guest.keys.leave_key = true
both(host, guest, 3)
check(host.accounts[guest.storage.me.id].data == "DCP1 the very last things", "leaving sends the last things first")
check(guest.session.kind == "title" and not guest.net, "and the guest is back at the title, out of the room")
check(find_toast(host, "Xiao left"), "the host hears the guest leave")
guest.emit("game.title.selected", {entry = "join"})
both(host, guest, 6)
check(guest.started and guest.started.player == "DCP1 the very last things", "back again, the guest gets their own things from the host")
check(find_toast(host, "Xiao is back"), "and the host knows them")

print("A dungeon host, a second guest, the host leaving")
host.map = {context = "dungeon", dungeon_id = 5, floor_id = 3}
local third = make_game("Goro")
for i = 1, 5 do
  for _ = 1, 40 do
    if third.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
    third.emit("game.title.selected", {entry = "c" .. i})
  end
end
third.emit("game.title.selected", {entry = "join"})
for _ = 1, 6 do host.tick(); guest.tick(); third.tick() end
check(third.started and third.started.map == 4, "a host in the Gallery of Time sends guests to Yellow Drops", third.started and third.started.map)
host.keys.leave_key = true
for _ = 1, 3 do host.tick(); guest.tick(); third.tick() end
check(guest.session.kind == "title" and third.session.kind == "title", "the host leaving sends the guests back to the title")
check(find_toast(third, "room closed"), "and tells them why")

print("Seeing each other")
do
  relay.rooms = {}
  local h = make_game("Toan")
  local g = make_game("Xiao")
  h.keys.host_key = true
  both(h, g, 2)
  for i = 1, 5 do
    for _ = 1, 40 do
      if g.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
      g.emit("game.title.selected", {entry = "c" .. i})
    end
  end
  g.emit("game.title.selected", {entry = "join"})
  both(h, g, 8)
  -- both on Divine Beast Cave floor 3, built from the room's seed
  h.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 3, back_floor = false})
  g.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 3, back_floor = false})
  check(#h.seeds == 1 and h.seeds[1] == g.seeds[1], "the host's and the guest's floor 3 come from one seed", h.seeds[1])
  g.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 4, back_floor = false})
  check(g.seeds[2] ~= g.seeds[1], "another floor, another seed")
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 4242}
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 4242}
  h.player = {character = "toan", weapon = {item_no = 258}, position = {x = 100, y = 0, z = 200}, heading = 1.5, motion = 2}
  g.player = {character = "xiao", position = {x = 160, y = 0, z = 220}, heading = 0.5, motion = 0}
  both(h, g, 12)
  local seen = g.avatars[1]
  check(seen and seen.character == "toan" and seen.weapon == 258 and seen.x == 100 and seen.z == 200 and seen.motion == 2 and
        seen.tint == nil, "the guest sees the host on the floor, with its weapon, in the host's own colours")
  local host_sees = h.avatars[1]
  check(host_sees and host_sees.character == "xiao" and host_sees.weapon == nil and host_sees.tint and host_sees.tint[3] == 128,
        "the host sees the guest, in blue")
  check(seen and seen.name == "Toan" and host_sees and host_sees.name == "Xiao", "each hero has its player's name over it",
        tostring(seen and seen.name) .. "/" .. tostring(host_sees and host_sees.name))
  h.player.position = {x = 300, y = 0, z = 200}
  both(h, g, 12)
  check(g.avatars[1] and g.avatars[1].x == 300, "the host's moves reach the guest")
  -- the guest goes down a floor: each is out of the other's sight
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 4, floor_seed = 99}
  both(h, g, 12)
  check(g.avatars[1] == nil and h.avatars[1] == nil, "on different floors neither sees the other")
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 4242}
  both(h, g, 12)
  check(h.avatars[1] ~= nil, "back on the same floor, the host sees the guest again")
  -- the guest's game goes quiet (a lost connection the relay hasn't noticed yet)
  for _ = 1, 200 do h.tick() end
  check(h.avatars[1] == nil, "a player quiet for three seconds is taken away")
  both(h, g, 12)
  check(h.avatars[1] ~= nil, "and comes back when heard again")
  g.keys.leave_key = true
  both(h, g, 3)
  check(h.avatars[1] == nil, "a guest who leaves is taken away")
  h.keys.leave_key = true
  h.tick()
end

print("Monsters: the host's")
do
  relay.rooms = {}
  local h = make_game("Toan")
  local g = make_game("Xiao")
  h.keys.host_key = true
  both(h, g, 2)
  for i = 1, 5 do
    for _ = 1, 40 do
      if g.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
      g.emit("game.title.selected", {entry = "c" .. i})
    end
  end
  g.emit("game.title.selected", {entry = "join"})
  both(h, g, 8)
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 7}
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 7}
  h.player = {character = "toan", position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  g.player = {character = "xiao", position = {x = 50, y = 0, z = 0}, heading = 0, motion = 0}
  h.monsters = {{slot = 0, kind = 3, state = 2, hp = 40, max_hp = 60, x = 10.5, y = 0, z = -20, heading = 1.25, motion = 4},
                {slot = 5, kind = 7, state = 1, hp = 90, max_hp = 90, x = 300, y = 5, z = 80, heading = 0, motion = 0}}
  both(h, g, 16)
  local p = g.puppets
  check(p and #p == 2 and p[1].slot == 0 and p[1].hp == 40 and p[1].x == 10.5 and p[1].motion == 4 and p[2].kind == 7,
        "a guest on the host's floor copies the host's monsters", p and #p)
  h.monsters = {}
  both(h, g, 8)
  check(g.puppets and #g.puppets == 0, "the host's last monster gone, the guest's copies go too")
  -- a guest's blow on a copy reaches the host's monster
  h.monsters = {{slot = 0, kind = 3, state = 2, hp = 40, max_hp = 60, x = 10, y = 0, z = 0, heading = 0, motion = 0}}
  both(h, g, 8)
  g.emit("game.enemy_hit", {slot = 0, damage = 17, attacker = 1})
  both(h, g, 2)
  check(h.mirror_hits[1] and h.mirror_hits[1].slot == 0 and h.mirror_hits[1].damage == 17, "a guest's blow lands on the host's monster")
  -- the host's monster strikes the guest's hero
  h.avatar_hits = {{avatar = 1, slot = 0, damage = 12, kind = 0, flags = 1}}
  both(h, g, 6)
  local strike = g.strikes[1]
  check(strike and strike.damage == 12 and strike.kind == "heavy" and strike.x == 50, "a monster's blow on a guest's hero strikes the guest", strike and strike.damage)
  check(#g.strikes == 1, "once")
  -- the host pauses (its game sends nothing): the copies hold
  for _ = 1, 120 do g.tick() end
  check(g.puppets ~= nil, "while the host is paused the guest's monsters stay held as the host's")
  -- the host goes back to town: the guest's monsters think for themselves
  h.map = {context = "town", map_id = 0}
  both(h, g, 12)
  check(g.puppets == nil, "the host off the floor, the guest's monsters are its own")
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 7}
  both(h, g, 12)
  check(g.puppets ~= nil, "and copies again when the host is back")
  -- the guest goes down the stairs: its monsters are its own again
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 8}
  both(h, g, 12)
  check(g.puppets == nil, "on another floor the guest's monsters think for themselves")
  g.emit("game.enemy_hit", {slot = 0, damage = 5})
  both(h, g, 2)
  check(#h.mirror_hits == 1, "and its blows there stay its own")
  h.keys.leave_key = true
  both(h, g, 2)
end

print("Doors: opened for everyone")
do
  relay.rooms = {}
  local h, g, k = make_game("Toan"), make_game("Xiao"), make_game("Goro")
  local function all(n) for _ = 1, n or 1 do h.tick(); g.tick(); k.tick() end end
  h.keys.host_key = true
  all(2)
  for _, guest in ipairs({g, k}) do
    for i = 1, 5 do
      for _ = 1, 40 do
        if guest.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
        guest.emit("game.title.selected", {entry = "c" .. i})
      end
    end
    guest.emit("game.title.selected", {entry = "join"})
    all(8)
  end
  local floor = {context = "dungeon", dungeon_id = 1, floor_id = 4, floor_seed = 77}
  for i, game_ in ipairs({h, g}) do
    game_.map = floor
    game_.player = {character = "toan", position = {x = i * 10, y = 0, z = 0}, heading = 0, motion = 0}
  end
  k.map = {context = "dungeon", dungeon_id = 1, floor_id = 3, floor_seed = 76}
  k.player = {character = "goro", position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  all(25)
  -- Xiao opens a gate with a key
  g.doors_out = {{script = 31, mode = 1, ext = 0, pos = {120.5, 0, -40}, dir = {0, 0, 1}}}
  all(25)
  local run = h.doors_run[1]
  check(run and run.script == 31 and run.mode == 1 and run.pos[1] == 120.5 and run.dir[3] == 1, "a guest's opened gate opens in the host's game")
  check(#k.doors_run == 0, "a player on another floor doesn't run it")
  check(#g.doors_run == 0, "and the one who opened it doesn't run it again")
  -- Goro comes down to that floor later: the gate is opened for him too, once
  k.map = floor
  all(40)
  check(#k.doors_run == 1 and k.doors_run[1].script == 31, "a player who arrives later finds it open", #k.doors_run)
  -- a game busy with another door takes the next one when free
  h.door_busy = true
  k.doors_out = {{script = 40, mode = 2, ext = 0, pos = {1, 2, 3}, dir = {0, 0, 0}}}
  all(25)
  check(#h.doors_run == 1, "a busy game waits")
  h.door_busy = false
  all(25)
  check(#h.doors_run == 2 and h.doors_run[2].script == 40, "and opens it once free")
  check(#g.doors_run == 1 and #k.doors_run == 1, "each door runs once in each game")
  h.keys.leave_key = true
  all(2)
end

print("Georama: the host's world")
do
  relay.rooms = {}
  local h, g, k = make_game("Toan"), make_game("Xiao"), make_game("Goro")
  local function all(n) for _ = 1, n or 1 do h.tick(); g.tick(); k.tick() end end
  h.keys.host_key = true
  all(2)
  for _, guest in ipairs({g, k}) do
    for i = 1, 5 do
      for _ = 1, 40 do
        if guest.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
        guest.emit("game.title.selected", {entry = "c" .. i})
      end
    end
    guest.emit("game.title.selected", {entry = "join"})
    all(8)
  end
  -- Xiao edits Matataki's Georama, then leaves the editor
  g.map = {context = "georama", map_id = 1, town_map = 1, editing = true}
  all(30)
  g.towns[1] = "DCT11:" .. string.rep("x", 20000) .. " Xiao's new mill"
  g.map = {context = "georama", map_id = 1, town_map = 1, editing = false}
  all(40)
  check(h.towns[1] == g.towns[1], "a guest's Georama edit reaches the host's world (in pieces)")
  check(k.towns[1] == g.towns[1], "and the host sends it on to the other guest")
  check(find_toast(h, "Xiao changed Matataki"), "the host is told who changed which town")
  -- the host edits Norune while Goro stands in Norune's Georama editor: Goro's game waits, then takes it
  k.map = {context = "georama", map_id = 0, town_map = 0, editing = false}
  k.busy_town = 0
  h.map = {context = "georama", map_id = 0, town_map = 0, editing = true}
  all(30)
  h.towns[0] = "DCT10: the host's new house"
  h.map = {context = "georama", map_id = 0, town_map = 0, editing = false}
  all(40)
  check(g.towns[0] == h.towns[0], "the host's own edit goes straight to the guests")
  check(k.towns[0] == "DCT10:start", "a guest busy in that town doesn't have it changed under them")
  k.busy_town = nil
  all(40)
  check(k.towns[0] == h.towns[0], "and takes it once free")
  check(find_toast(k, "The host changed Norune; back to its entrance"), "walked back to the entrance of the town that changed")
  h.keys.leave_key = true
  all(2)
end

print("Refusals")
local lost = make_game("Ruby")
lost.storage.code = nil
lost.emit("game.title.selected", {entry = "join"})
lost.tick()
check(lost.title.lines[3]:find("five letters"), "joining without a code says to set it", lost.title.lines[3])
host.keys.host_key = true
host.tick()
local version_two = make_game("Ungaga")
for i = 1, 5 do
  for _ = 1, 40 do
    if version_two.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
    version_two.emit("game.title.selected", {entry = "c" .. i})
  end
end
relay.rooms.ABCDE.version = 99
version_two.emit("game.title.selected", {entry = "join"})
version_two.tick(2)
check(version_two.started == nil and find_toast(version_two, "another version"), "another version is turned away")
host.session = {kind = "visit"}
host.keys.leave_key = true
host.tick()
host.keys.host_key = true
host.tick()
check(find_toast(host, "host from your own save"), "a visitor can't host")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed > 0 and 1 or 0)
