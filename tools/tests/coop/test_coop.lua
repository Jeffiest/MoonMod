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

local function make_game(name, opts)
  opts = opts or {}
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
  S.mods_list, S.mod_settings, S.overlay = opts.mods, opts.mod_settings or {}, {}
  env.game = {
    mods = opts.mods and {
      list = function() return {mods = S.mods_list} end,
      settings_get = function(a) return {id = a.id, values = S.mod_settings[a.id] or {}} end,
      settings_overlay = function(a) S.overlay[a.id] = a.values; return {id = a.id, applied = true} end,
      settings_overlay_clear = function() S.overlay = {}; S.overlay_cleared = (S.overlay_cleared or 0) + 1; return {cleared = true} end,
    } or nil,
    ui = {notify = function(n) S.toasts[#S.toasts + 1] = n.message end, register = function() return true end},
    render = {layer_register = function(l) S.layers[l.id] = l.text end, layer_remove = function(l) S.layers[l.id] = nil end},
    input = {bind = function() return true end, consume = function(a) local p = S.keys[a.id]; S.keys[a.id] = nil; return {pressed = p} end,
             state = function(a) return {down = S.keys[a.id] == true} end},
    title = {mode_register = function(d) S.title = d; return true end, mode_set = function(d) S.title = d; return true end},
    world = {
      get = function()
        local w = {}
        for k, v in pairs(S.map) do w[k] = v end
        w.time = {fraction = S.clock or 0.25}
        return w
      end,
      set_time = function(a) S.clock = a.fraction; S.clock_sets = (S.clock_sets or 0) + 1; return {time = {fraction = a.fraction}} end,
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
      puppet_set = function(a)
        S.puppets = a.monsters
        local hits = S.puppet_hits or {}
        S.puppet_hits = {}
        return {followed = {}, refused = {}, hits = hits}
      end,
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
        S.last_base = a.base
        return {town_id = a.town_id, imported = true, merged = a.base ~= nil, reloaded = S.map.town_map == a.town_id}
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
      account_list = function()
        local out = {}
        for id, x in pairs(S.accounts) do out[#out + 1] = {id = id, name = x.name or ""} end
        return {accounts = out}
      end,
      account_remove = function(a) local had = S.accounts[a.id] ~= nil; S.accounts[a.id] = nil; return {removed = had} end,
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
check(guest.title.lines[4] == "Server: the public relay.", "and says which server it uses", guest.title.lines[4])
do
  local private = make_game("Pip")
  private.settings.server = "wss://coop.example.net/room"
  private.emit("game.title.opened", {})
  check(private.title.lines[4] == "Server: coop.example.net (private).", "a private server by its host", private.title.lines[4])
end
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
check(host.layers.coop_who == "Xiao" and guest.layers.coop_who == "Toan", "and each HUD names the others",
      tostring(host.layers.coop_who) .. "/" .. tostring(guest.layers.coop_who))
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
  -- both walk in Norune: the town's heroes
  h.map = {context = "georama", map_id = 0, town_map = 0, editing = false, walking = true}
  g.map = {context = "georama", map_id = 0, town_map = 0, editing = false, walking = true}
  h.player = {character = "toan", town_character = "goro", position = {x = 5, y = 0, z = 6}, heading = 0, motion = 1}
  g.player = {character = "xiao", position = {x = 9, y = 0, z = 6}, heading = 0, motion = 0}
  both(h, g, 12)
  check(g.avatars[1] and g.avatars[1].character == "goro" and g.avatars[1].x == 5, "in town each sees the other, as the town's hero they walk as")
  -- the host opens a menu: no position, but it still stands there
  h.player = {character = "toan"}
  for _ = 1, 200 do both(h, g) end
  check(g.avatars[1] and g.avatars[1].x == 5, "a player in a menu still stands where they were")
  h.map = {context = "georama", map_id = 1, town_map = 1, editing = false, walking = true}
  h.player = {character = "toan", position = {x = 5, y = 0, z = 6}, heading = 0, motion = 0}
  both(h, g, 12)
  check(g.avatars[1] == nil, "in another town they don't")
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
  g.puppet_hits = {{slot = 0, damage = 17}, {slot = 0, damage = 30}} -- a sword's, then a bomb's
  both(h, g, 8)
  check(h.mirror_hits[1] and h.mirror_hits[1].slot == 0 and h.mirror_hits[1].damage == 17 and h.mirror_hits[2] and
        h.mirror_hits[2].damage == 30, "a guest's blows, a bomb's too, land on the host's monster")
  -- the host's monster strikes the guest's hero
  h.avatar_hits = {{avatar = 1, slot = 0, damage = 12, kind = 3, flags = 0}}
  both(h, g, 6)
  local strike = g.strikes[1]
  check(strike and strike.damage == 12 and strike.kind == "heavy" and strike.x == 50, "a monster's blow on a guest's hero strikes the guest", strike and strike.damage)
  check(#g.strikes == 1, "once")
  h.avatar_hits = {{avatar = 1, slot = 4, damage = 5, kind = 2, flags = 0}} -- a shot
  both(h, g, 6)
  check(g.strikes[2] and g.strikes[2].kind == "light" and g.strikes[2].damage == 5, "a small hit (a shot) flinches")
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
  g.puppet_hits = {{slot = 0, damage = 5}}
  both(h, g, 12)
  check(#h.mirror_hits == 2, "and its blows there stay its own")
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
  -- with the setting off, a game keeps its doors to itself and takes none
  h.settings.shared_doors = false
  k.doors_out = {{script = 41, mode = 1, ext = 0, pos = {5, 0, 5}, dir = {0, 0, 1}}}
  h.doors_out = {{script = 42, mode = 1, ext = 0, pos = {6, 0, 6}, dir = {0, 0, 1}}}
  all(25)
  check(#h.doors_run == 2 and #k.doors_run == 1 and #g.doors_run == 2, "a game with shared doors off neither sends nor takes them",
        #h.doors_run .. "/" .. #k.doors_run .. "/" .. #g.doors_run)
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
  check(h.last_base == "DCT11:start", "with the town as it was when they opened the editor, for the host to merge", tostring(h.last_base):sub(1, 40))
  check(k.towns[1] == g.towns[1], "and the host sends it on to the other guest")
  check(find_toast(h, "Xiao changed Matataki"), "the host is told who changed which town")
  -- two building in one town are told
  g.map = {context = "georama", map_id = 2, town_map = 2, editing = true}
  all(31)
  k.map = {context = "georama", map_id = 2, town_map = 2, editing = true}
  all(62)
  check(find_toast(k, "Xiao is building in Queens too"), "a player opening a town's editor hears who else builds there")
  check(find_toast(g, "Goro is building in Queens too"), "and the other hears it too")
  g.map = {context = "georama", map_id = 2, town_map = 2, editing = false}
  k.map = {context = "georama", map_id = 2, town_map = 2, editing = false}
  all(62)
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

print("The host's clock")
do
  relay.rooms = {}
  local h, g = make_game("Toan"), make_game("Xiao")
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
  h.clock, g.clock = 0.62, 0.40
  both(h, g, 610)
  check(g.clock == 0.62, "a guest's clock is set to the host's", g.clock)
  local sets = g.clock_sets
  both(h, g, 610)
  check(g.clock_sets == sets, "and left alone while it keeps time")
  h.keys.leave_key = true
  both(h, g, 2)
end

print("The host's guests")
do
  local h = make_game("Toan")
  h.accounts = {["p1111111111111111"] = {name = "Xiao", data = "DCP1x"}, ["p2222222222222222"] = {name = "Goro", data = "DCP1y"}}
  h.emit("ui.action", {id = "guests"})
  check(h.last_toast() == "Co-op: this save keeps 2 guests: Goro, Xiao", "the host sees the guests its save keeps", h.last_toast())
  h.emit("ui.action", {id = "forget"})
  check(h.accounts["p1111111111111111"] ~= nil and h.last_toast():find("press again"), "forgetting asks for a second press")
  h.emit("ui.action", {id = "forget"})
  check(next(h.accounts) == nil and h.last_toast():find("2 guests forgotten"), "and then forgets them", h.last_toast())
end

print("Typing the code")
do
  local t = make_game("Typer")
  t.emit("game.title.opened", {})
  for c in ("QR7KM"):gmatch(".") do t.keys["type_" .. c] = true; t.tick() end
  check(t.title.entries[6].label == "Join room QR7KM", "a code typed on the keyboard fills the letters", t.title.entries[6].label)
  t.keys.type_back = true; t.tick()
  t.keys.type_back = true; t.tick()
  t.keys.type_Z = true; t.tick()
  check(t.title.entries[6].label == "Join room QR7Z-", "Backspace takes letters back, and typing goes on from there", t.title.entries[6].label)
  t.keys.type_E = true -- a key that is also Square: no letter steps, only the typing
  t.emit("game.title.selected", {entry = "c4", action = "square"})
  check(t.title.entries[6].label == "Join room QR7Z-", "Square with E down is typing, not a step back", t.title.entries[6].label)
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

print("The room's mods")
relay.rooms = {}
local function type_code(g)
  for i = 1, 5 do
    for _ = 1, 40 do
      if g.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
      g.emit("game.title.selected", {entry = "c" .. i})
    end
  end
end
local function mod(id, version, coop)
  local name = id:gsub("^moonmod%.", ""):gsub("^%l", string.upper)
  return {id = id, name = name, version = version, coop = coop}
end
local host_mods = {mod("moonmod.coop", "0.8.0"), mod("moonmod.roguelike", "0.3.0"), mod("moonmod.vigil", "0.1.0"),
                   mod("moonmod.randomizer", "1.0.0", "host_only"), mod("moonmod.controls", "1.0.0", "local")}
local mhost = make_game("Goro", {mods = host_mods, mod_settings = {
  ["moonmod.roguelike"] = {companion = true, floors = 12, tint = 0.25, motto = "tab\there, 100%"},
  ["moonmod.vigil"] = {run_cost = 20},
  ["moonmod.coop"] = {name = "Goro", server = ""},
  ["moonmod.randomizer"] = {seed = "HOSTONLY"},
  ["moonmod.controls"] = {hotkeys = false}}})
local mguest = make_game("Ruby", {mods = {mod("moonmod.coop", "0.8.0"), mod("moonmod.roguelike", "0.2.0"),
                                          mod("moonmod.controls", "1.0.0", "local"), mod("moonmod.dungeon-plus", "2.1.1")}})
mhost.keys.host_key = true
both(mhost, mguest, 2)
type_code(mguest)
mguest.emit("game.title.selected", {entry = "join"})
both(mhost, mguest, 6)
local kept = mguest.storage.needed
check(mguest.started == nil, "a guest without the room's mods doesn't get the world")
check(kept and #kept.list == 3 and kept.code == "ABCDE", "and keeps the room's list", kept and #kept.list)
local whats = {}
for _, n in ipairs(kept and kept.list or {}) do whats[n.id] = n.what .. " " .. n.version end
check(whats["moonmod.vigil"] == "enable 0.1.0", "a mod it lacks: enable, at the host's version", whats["moonmod.vigil"])
check(whats["moonmod.roguelike"] == "version 0.3.0", "a mod at another version: the host's version", whats["moonmod.roguelike"])
check(whats["moonmod.dungeon-plus"] == "disable 2.1.1", "a world-changing mod the host doesn't play: turn it off", whats["moonmod.dungeon-plus"])
check(whats["moonmod.randomizer"] == nil and whats["moonmod.controls"] == nil, "host-only and local mods are never asked for")
check(find_toast(mguest, "needs mods you don't have: disable Dungeon%-plus"), "the guest is told what to change", mguest.last_toast())
check(find_toast(mhost, "Ruby can't join yet: 3 mods"), "the host is told why", mhost.last_toast())
check(mguest.net == nil and mguest.mod.state.role == nil, "and the guest leaves the room")
local joined = table.concat(mguest.title.lines, "|")
check(joined:find("Room ABCDE needs 3 mod changes") and joined:find("enable Vigil 0.1.0"), "the title page lists them", joined)
-- half done: the list shrinks
mguest.mods_list = {mod("moonmod.coop", "0.8.0"), mod("moonmod.roguelike", "0.3.0"), mod("moonmod.controls", "1.0.0", "local"),
                    mod("moonmod.dungeon-plus", "2.1.1", "local")}
mguest.emit("game.title.opened", {})
joined = table.concat(mguest.title.lines, "|")
check(joined:find("needs 1 mod change") and joined:find("enable Vigil"), "what's done drops off the list", joined)
mguest.emit("ui.action", {id = "needed"})
check(mguest.last_toast():find("room ABCDE needs: enable Vigil"), "the Mod Manager action lists what's left", mguest.last_toast())
-- all done (a host-only mod the guest also has does no harm)
mguest.mods_list = {mod("moonmod.coop", "0.8.0"), mod("moonmod.roguelike", "0.3.0"), mod("moonmod.vigil", "0.1.0"),
                    mod("moonmod.randomizer", "1.0.0"), mod("moonmod.controls", "1.0.0", "local")}
mguest.emit("game.title.opened", {})
check(table.concat(mguest.title.lines, "|"):find("all in place"), "the page says when all is in place")
mguest.emit("game.title.selected", {entry = "join"})
both(mhost, mguest, 8)
check(mguest.started ~= nil, "with the room's mods the guest joins")
check(mguest.storage.needed == nil, "and the list is forgotten")
local rogue = mguest.overlay["moonmod.roguelike"] or {}
check(rogue.companion == true and rogue.floors == 12 and math.type(rogue.floors) == "integer" and rogue.tint == 0.25 and
      rogue.motto == "tab\there, 100%", "the host's settings apply to the guest, types and text intact")
check((mguest.overlay["moonmod.vigil"] or {}).run_cost == 20, "for every required mod")
check(mguest.overlay["moonmod.coop"] == nil, "but not co-op's own (name, server)")
check(mguest.overlay["moonmod.randomizer"] == nil and mguest.overlay["moonmod.controls"] == nil, "nor host-only or local mods' settings")
check(find_toast(mguest, "the host's settings for 2 mods"), "the guest is told")
mguest.keys.leave_key = true
both(mhost, mguest, 3)
check(next(mguest.overlay) == nil and (mguest.overlay_cleared or 0) >= 1, "leaving the visit drops the host's settings")

-- an engine without game.mods can't join a host that checks
local old = make_game("Osmond")
type_code(old)
old.emit("game.title.selected", {entry = "join"})
both(mhost, old, 6)
check(old.started == nil and find_toast(old, "update MoonFactory"), "a game that can't say its mods is turned away")

do
  local rm = mhost.mod.mods
  for _, v in ipairs({true, false, 0, -7, 3.5, 1e-9, "", "a\tb\nc%41"}) do
    local back = rm.decode_value(rm.encode_value(v))
    check(back == v and math.type(back) == math.type(v), "a setting value crosses intact: " .. tostring(v):gsub("%c", "?"))
  end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed > 0 and 1 or 0)
