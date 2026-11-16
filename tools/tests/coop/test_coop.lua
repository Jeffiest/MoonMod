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
  -- opts.game: "chronicle" (Dark Cloud, the default) or "chronicle-two" (Dark Cloud 2), as game.info.get names it.
  local dc2 = opts.game == "chronicle-two"
  local S = {name = name, handlers = {}, storage = {}, settings = {name = name}, toasts = {}, layers = {},
             net_events = {}, net = nil, session = {kind = "story"}, accounts = {}, frame = 0, keys = {},
             world = (dc2 and "DCW2" or "DCW1") .. string.rep("w", 30000) .. name,
             things = (dc2 and "DCP2" or "DCP1") .. string.rep("p", 20000) .. name,
             map = dc2 and {context = "georama", map_id = 23, town_map = 2, scene_map = 23, map_no = 23, map_title = "Balance Valley"} or {context = "georama", map_id = 2},
             title = nil, started = nil, imported = {},
             avatars = {}, seeds = {}, player = {character = "toan"},
             monsters = {}, avatar_hits = {}, puppets = nil, mirror_hits = {}, strikes = {},
             doors_out = {}, doors_run = {}, door_busy = false,
             panel = nil, entered = {}, gilda = 1000, bag = {}, follows = {},
             towns = {[0] = "DCT10:start", "DCT11:start", "DCT12:start", "DCT13:start", "DCT14:start"}}
  if dc2 then
    S.towns = {[0] = "DCT20:start", "DCT21:start", "DCT22:start", "DCT23:start", "DCT24:start"}
  end
  S.slot_writes = {}
  S.applied = {}
  S.hero_log = {}
  S.shots_out, S.shots_drawn = {}, {} -- the hero's shots (player.effects_take), and the others' drawn here
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
    info = {get = function() return {id = opts.game or "chronicle", name = dc2 and "Chronicle Two" or "Chronicle", api_major = 1} end},
    mods = opts.mods and {
      list = function() return {mods = S.mods_list} end,
      settings_get = function(a) return {id = a.id, values = S.mod_settings[a.id] or {}} end,
      settings_overlay = function(a) S.overlay[a.id] = a.values; return {id = a.id, applied = true} end,
      settings_overlay_clear = function() S.overlay = {}; S.overlay_cleared = (S.overlay_cleared or 0) + 1; return {cleared = true} end,
    } or nil,
    ui = {notify = function(n) S.toasts[#S.toasts + 1] = n.message end,
          register = function(a) S.actions = S.actions or {}; S.actions[a.id] = a; return true end,
          choice_open = function(a) if S.panel then return nil, {message = "a panel is open"} end; S.panel = a; return {} end},
    render = {layer_register = function(l) S.layers[l.id] = l.text end, layer_remove = function(l) S.layers[l.id] = nil end},
    input = {bind = function(a) S.binds = S.binds or {}; S.binds[a.id] = a.keys; return true end, consume = function(a) local p = S.keys[a.id]; S.keys[a.id] = nil; return {pressed = p} end,
             state = function(a) return {down = S.keys[a.id] == true} end},
    title = {mode_register = function(d) S.title = d; return true end, mode_set = function(d) S.title = d; return true end},
    world = {
      get = function()
        local w = {}
        for k, v in pairs(S.map) do w[k] = v end
        w.time = {fraction = S.clock or 0.25}
        return w
      end,
      enter_map = function(a) S.entered[#S.entered + 1] = "map " .. a.map_no; return {queued = true} end,
      transition = function(a) S.entered[#S.entered + 1] = "to " .. a.id; return {queued = true} end,
      set_time = function(a) S.clock = a.fraction; S.clock_sets = (S.clock_sets or 0) + 1; return {time = {fraction = a.fraction}} end,
      avatar_set = function(a) S.avatars[a.slot] = a; return {slot = a.slot, shown = true} end,
      avatar_effect = function(a) S.shots_drawn[#S.shots_drawn + 1] = a; return {shown = true} end,
      avatar_clear = function(a) if a and a.slot then S.avatars[a.slot] = nil else S.avatars = {} end; return {cleared = true} end,
      -- Chronicle Two's shared world (opts.shared): what the game is asked to watch, and the changes it is given
      watch_set = opts.shared and function(a) S.watching = a.enabled; return {enabled = a.enabled} end or nil,
      change_apply = opts.shared and function(a)
        if a.kind == "flag" and type(a.value) ~= "boolean" then return nil, {message = "a flag is true or false"} end
        S.applied[#S.applied + 1] = a
        return {applied = true}
      end or nil,
    },
    player = {
      get = function() return S.player end,
      effects_take = function() local out = S.shots_out; S.shots_out = {}; return {effects = out} end,
      down_rule_set = function(a) S.down_rule = a.enabled; return {enabled = a.enabled} end,
      revive = function(a)
        if not S.player.down then return nil, {message = "the player isn't down"} end
        S.player.down = false
        S.player.hp = a.hp
        if a.x then S.player.position = {x = a.x, y = a.y, z = a.z} end
        S.revives = (S.revives or 0) + 1
        return {queued = true}
      end,
      give_up = function() if not S.player.down then return nil, {message = "the player isn't down"} end; S.gave_up = true; return {queued = true} end,
    },
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
        return {followed = {}, refused = S.refused or {}, hits = hits}
      end,
      puppet_clear = function() S.puppets = nil; return {cleared = true} end,
      mirror_hit = function(a) S.mirror_hits[#S.mirror_hits + 1] = a; return {slot = a.slot, damage = a.damage} end,
    },
    items = {
      owned = function()
        local out = {}
        for _, it in ipairs(S.bag) do if it.count > 0 then out[#out + 1] = {id = it.id, name = it.name, count = it.count} end end
        return {items = out}
      end,
      remove = function(a)
        for _, it in ipairs(S.bag) do
          if it.id == a.id then local n = math.min(it.count, a.count); it.count = it.count - n; return {removed = n} end
        end
        return {removed = 0}
      end,
      give = function(a)
        local cap = S.bag_room or 99
        local n = math.min(cap, a.count)
        S.bag_room = cap - n
        for _, it in ipairs(S.bag) do if it.id == a.id then it.count = it.count + n; return {added = n} end end
        S.bag[#S.bag + 1] = {id = a.id, name = a.id, count = n}
        return {added = n}
      end,
    },
    economy = {
      get = function() return {currency = "gilda", amount = S.gilda, max_amount = 65535} end,
      add = function(a) local room = 65535 - S.gilda; S.gilda = S.gilda + math.min(room, a.amount); return {} end,
      spend = function(a) if a.amount > S.gilda then return nil, {message = "not enough"} end; S.gilda = S.gilda - a.amount; return {} end,
    },
    combat = {strike_player = function(a) S.strikes[#S.strikes + 1] = a; return {} end},
    dungeons = {
      set_seed = function(a) S.seeds[#S.seeds + 1] = a.seed; return {seed = a.seed} end,
      enter_floor = function(a)
        if S.busy then return nil, {code = "failed", message = "busy: the player isn't walking in a town or playing on a floor"} end
        S.entered[#S.entered + 1] = "floor " .. a.dungeon_id .. ":" .. a.floor_id; return {queued = true}
      end,
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
    party = opts.heroes and {
      room_hero_set = function(a)
        if a.hero ~= "max" and a.hero ~= "monica" then return nil, {message = "hero must be 'max' or 'monica'"} end
        S.room_hero = a.hero
        S.hero_log[#S.hero_log + 1] = a.hero .. (S.session.kind == "visit" and " in the visit" or "")
        return {hero = a.hero}
      end,
      room_hero_clear = function() local had = S.room_hero ~= nil; S.room_hero = nil; return {cleared = had} end,
    } or nil,
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
      slots_list = opts.slots and function() return {slots = opts.slots} end or nil,
      slot_player_export = opts.slots and function(a)
        for _, slot in ipairs(opts.slots) do
          if slot.slot == a.slot and slot.ready then return {slot = a.slot, data = "DCP2 own " .. a.slot, progress = slot.progress} end
        end
        return nil, {message = "no save has the number " .. tostring(a.slot)}
      end or nil,
      slot_player_import = opts.slots and function(a)
        if S.session.kind ~= "visit" then return nil, {message = "only this mod's co-op visit writes a player's things into a save"} end
        S.slot_writes[#S.slot_writes + 1] = {slot = a.slot, data = a.data}
        return {slot = a.slot, written = true}
      end or nil,
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
  -- the panel on screen: pick an option (index from 1), or back out
  function S.choose(index)
    local p = S.panel
    S.panel = nil
    S.emit("ui.choice_made", {id = "moonmod.coop:coop_together", index = index, cancelled = index == nil})
    return p
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
check(find_toast(third, "closed the room"), "and tells them why")

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
  both(h, g, 48)
  local seen = g.avatars[1]
  check(seen and seen.character == "toan" and seen.weapon == 258 and seen.x == 100 and seen.z == 200 and seen.motion == 2 and
        seen.tint == nil, "the guest sees the host on the floor, with its weapon, in the host's own colours")
  local host_sees = h.avatars[1]
  check(host_sees and host_sees.character == "xiao" and host_sees.weapon == nil and host_sees.tint and host_sees.tint[3] == 128,
        "the host sees the guest, in blue")
  check(seen and seen.name == "Toan" and host_sees and host_sees.name == "Xiao", "each hero has its player's name over it",
        tostring(seen and seen.name) .. "/" .. tostring(host_sees and host_sees.name))
  h.player.position = {x = 300, y = 0, z = 200}
  both(h, g, 48)
  check(g.avatars[1] and g.avatars[1].x == 300, "the host's moves reach the guest")
  -- the host fires: the guest draws the shot from the host's hero, as it flew
  h.shots_out = {{kind = 5, x = 300, y = 10, z = 200, dx = 0, dy = 0, dz = 1, value = 41, amount = 0.75, target = 25}}
  both(h, g, 4)
  local shot = g.shots_drawn[1]
  check(#g.shots_drawn == 1 and shot.slot == 1 and shot.kind == 5 and shot.x == 300 and shot.dz == 1 and shot.value == 41 and
        math.abs(shot.amount - 0.75) < 0.001 and shot.target == 25 and #h.shots_drawn == 0,
        "a shot the host fires is drawn on the guest's floor from the host's hero, once")
  h.shots_out = {{kind = 6, x = 0, y = 0, z = 0, dx = 0, dy = 0, dz = 0, value = 12, amount = 8, target = 2, frame0 = "sw_00", frame1 = "sw01"}}
  both(h, g, 4)
  local swing = g.shots_drawn[2]
  check(#g.shots_drawn == 2 and swing.kind == 6 and swing.frame0 == "sw_00" and swing.frame1 == "sw01" and swing.value == 12,
        "and the trail of the host's blade, between the same two frames")
  table.remove(g.shots_drawn)
  -- the guest goes down a floor: each is out of the other's sight
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 4, floor_seed = 99}
  both(h, g, 48)
  check(g.avatars[1] == nil and h.avatars[1] == nil, "on different floors neither sees the other")
  h.shots_out = {{kind = 1, x = 300, y = 10, z = 200, dx = 0, dy = 0, dz = 1}}
  both(h, g, 4)
  check(#g.shots_drawn == 1, "and the host's shots aren't drawn on another floor")
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 4242}
  both(h, g, 48)
  check(h.avatars[1] ~= nil, "back on the same floor, the host sees the guest again")
  -- the guest's game goes quiet (a lost connection the relay hasn't noticed yet)
  for _ = 1, 200 do h.tick() end
  check(h.avatars[1] == nil, "a player quiet for three seconds is taken away")
  both(h, g, 48)
  check(h.avatars[1] ~= nil, "and comes back when heard again")
  -- both walk in Norune: the town's heroes
  h.map = {context = "georama", map_id = 0, town_map = 0, editing = false, walking = true}
  g.map = {context = "georama", map_id = 0, town_map = 0, editing = false, walking = true}
  h.player = {character = "toan", town_character = "goro", position = {x = 5, y = 0, z = 6}, heading = 0, motion = 1}
  g.player = {character = "xiao", position = {x = 9, y = 0, z = 6}, heading = 0, motion = 0}
  both(h, g, 48)
  check(g.avatars[1] and g.avatars[1].character == "goro" and g.avatars[1].x == 5, "in town each sees the other, as the town's hero they walk as")
  -- the host opens a menu: no position, but it still stands there
  h.player = {character = "toan"}
  for _ = 1, 200 do both(h, g) end
  check(g.avatars[1] and g.avatars[1].x == 5, "a player in a menu still stands where they were")
  h.map = {context = "georama", map_id = 1, town_map = 1, editing = false, walking = true}
  h.player = {character = "toan", position = {x = 5, y = 0, z = 6}, heading = 0, motion = 0}
  both(h, g, 48)
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
  both(h, g, 48)
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
  both(h, g, 48)
  check(g.puppets == nil, "the host off the floor, the guest's monsters are its own")
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 7}
  both(h, g, 48)
  check(g.puppets ~= nil, "and copies again when the host is back")
  -- the guest goes down the stairs: its monsters are its own again
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 8}
  both(h, g, 48)
  check(g.puppets == nil, "on another floor the guest's monsters think for themselves")
  g.puppet_hits = {{slot = 0, damage = 5}}
  both(h, g, 48)
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
  all(60)
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

print("Together: joining, and giving")
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
  check(g.layers.coop == "CO-OP ABCDE  2 of 4", "a guest's HUD counts the host too", g.layers.coop)
  h.map = {context = "georama", map_id = 0, town_map = 0, map_no = 0, walking = true}
  g.map = {context = "georama", map_id = 0, town_map = 0, map_no = 0, walking = true}
  h.player = {character = "toan", position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  g.player = {character = "xiao", position = {x = 5, y = 0, z = 0}, heading = 0, motion = 0}
  both(h, g, 48)
  g.panel = nil
  -- the host changes floors: on the way the game passes through a floor only loading (its number and seed not
  -- settled), and no one is asked to follow there
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 0, floor_seed = 3, walking = false}
  both(h, g, 90)
  check(g.panel == nil, "a floor still loading is offered to no one", g.panel and g.panel.title)
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 3, walking = true}
  both(h, g, 10)
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 11, walking = true}
  both(h, g, 10)
  check(g.panel == nil, "nor one held only a moment", g.panel and g.panel.title)
  -- the host goes down into Divine Beast Cave, floor 3
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 11}
  both(h, g, 48)
  check(g.panel and g.panel.title == "Toan went to Divine Beast Cave, floor 3", "the guest is asked to join the host on the floor it went to",
        g.panel and g.panel.title)
  -- the guest is in a talk when it says yes: it goes once it's free
  g.busy = true
  g.choose(1)
  both(h, g, 2)
  check(#g.entered == 0 and find_toast(g, "as soon as you're free"), "a busy guest's join waits", g.toasts[#g.toasts])
  both(h, g, 60)
  check(#g.entered == 0, "while it's busy")
  g.busy = false
  both(h, g, 32)
  check(g.entered[1] == "floor 0:2", "joining walks the guest onto that floor once it can", g.entered[1])
  -- the host walks into a house; the guest stays
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 11}
  h.map = {context = "georama", map_id = 0, map_no = 23, walking = true}
  both(h, g, 48)
  check(g.panel and g.panel.title == "Toan went to a house", "a house too", g.panel and g.panel.title)
  g.choose(2)
  both(h, g, 2)
  check(#g.entered == 1, "staying stays")
  g.emit("ui.action", {id = "follow"})
  both(h, g, 2)
  g.choose(1)
  both(h, g, 2)
  check(g.entered[2] == "map 23", "and the Mod Manager can join them later", g.entered[2])

  -- giving Gilda: the host has 1000, the guest 65000 (its wallet holds 65535)
  g.gilda = 65000
  check(h.panel and h.panel.title == "Xiao went to Divine Beast Cave, floor 3", "the host is asked to join the guest too",
        h.panel and h.panel.title)
  while h.panel do h.choose(2); both(h, g, 2) end -- stays
  h.emit("ui.action", {id = "give"})
  both(h, g, 2)
  check(h.panel and h.panel.title == "Give Xiao...", "with one other player the gift goes straight to them", h.panel and h.panel.title)
  h.choose(1)                -- Gilda
  both(h, g, 2)
  h.choose(#h.panel.options) -- all 1000
  both(h, g, 6)
  check(h.gilda == 465 and g.gilda == 65535, "what doesn't fit in the other's wallet comes back", h.gilda .. "/" .. g.gilda)
  check(find_toast(g, "Toan gave you 535 Gilda"), "the other is told what came", g.toasts[#g.toasts])

  -- giving an item: 3 of 4 Breads
  h.bag = {{id = "chronicle:item:148", name = "Bread", count = 4}, {id = "chronicle:item:146", name = "Tasty Water", count = 1}}
  h.emit("ui.action", {id = "give"})
  both(h, g, 2)
  h.choose(2)                -- an item
  both(h, g, 2)
  check(h.panel and h.panel.options[1].title == "Bread", "the bag's items, by name", h.panel and h.panel.options[1].title)
  h.choose(1)                -- Bread
  both(h, g, 2)
  h.choose(1)                -- 1
  both(h, g, 6)
  check(h.bag[1].count == 3 and g.bag[1] and g.bag[1].count == 1 and find_toast(g, "Toan gave you 1 x Bread"), "an item goes from one bag to the other")
  h.keys.leave_key = true
  both(h, g, 2)
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
-- another room's list isn't the typed room's (a friend's new room, after an older one turned this game away)
local real = mguest.storage.needed
mguest.storage.needed = {list = real.list, code = "ZZZZZ"}
mguest.emit("game.title.opened", {})
check(not table.concat(mguest.title.lines, "|"):find("needs"), "another room's list isn't shown for the code typed",
      table.concat(mguest.title.lines, "|"))
mguest.storage.needed = real
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

print("The link: ping, drops, closing, out of step")
do
  relay.rooms = {}
  -- a cable pulled: the relay drops the player, the others hear it leave, and its own game hears the connection close
  local function drop(game_)
    local room = relay.rooms[game_.net.code]
    room.players[game_.net.id] = nil
    for _, other in pairs(room.players) do queue(other, {kind = "left", peer = game_.net.id}) end
    queue(game_, {kind = "closed", reason = "the connection to the relay closed"})
    game_.net = nil
  end
  local function enter(g)
    for i = 1, 5 do
      for _ = 1, 40 do
        if g.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
        g.emit("game.title.selected", {entry = "c" .. i})
      end
    end
    g.emit("game.title.selected", {entry = "join"})
  end
  local h, g = make_game("Toan"), make_game("Xiao")
  h.keys.host_key = true
  both(h, g, 2)
  enter(g)
  both(h, g, 10)
  check(g.session.kind == "visit", "a guest is in")
  both(h, g, 160)
  check(tostring(h.layers.coop_who):match("^Xiao %d+ms$") and tostring(g.layers.coop_who):match("^Toan %d+ms$"),
        "each HUD shows the others' ping", tostring(h.layers.coop_who) .. " / " .. tostring(g.layers.coop_who))

  -- a guest gone quiet (a long load, a stalled connection), then back
  h.tick(500)
  check(not find_toast(h, "no word from the host"), "the host never waits to hear from itself")
  check(find_toast(h, "no word from Xiao") and tostring(h.layers.coop_who):find("no signal", 1, true),
        "the host notices a guest gone quiet", h.layers.coop_who)
  both(h, g, 3)
  check(find_toast(h, "Xiao is back in touch"), "and when they're back")

  -- the guest's connection drops: its visit goes on, and it gets back in
  local starts = g.started
  drop(g)
  both(h, g, 2)
  check(g.mod.state.rejoin ~= nil and g.session.kind == "visit", "a guest whose connection drops keeps playing")
  check(g.layers.coop == "CO-OP ABCDE  reconnecting...", "and its HUD says it is reconnecting", g.layers.coop)
  check(find_toast(h, "Xiao's connection dropped"), "the host hears the connection dropped, not a goodbye")
  g.things = "DCP1 after the drop"
  both(h, g, 70)
  check(g.mod.state.rejoin == nil and find_toast(g, "back in the room"), "it gets back into the room by itself")
  check(find_toast(h, "Xiao is back in %(reconnected%)"), "the host hears it is back")
  check(g.started == starts, "without a new visit: no world sent again")
  both(h, g, 4)
  check(h.accounts[g.storage.me.id] and h.accounts[g.storage.me.id].data == "DCP1 after the drop",
        "and its things go to the host at once")

  -- the host closes: every guest's things are kept first
  g.things = "DCP1 the last of it"
  h.keys.leave_key = true
  h.tick()
  check(h.mod.state.closing ~= nil and find_toast(h, "keeping your guests' things first"), "closing the room waits for the guests' things")
  both(h, g, 6)
  check(h.accounts[g.storage.me.id].data == "DCP1 the last of it", "the guest's last things reach the host before it closes")
  check(h.mod.state.role == nil and find_toast(h, "save your game to keep your guests' things"), "then the room closes")
  check(g.session.kind == "title" and find_toast(g, "the host closed the room; your things were kept"),
        "and the guest is told its things were kept")

  -- a drop while the room goes away: it gives up and says so
  relay.rooms = {}
  h, g = make_game("Toan"), make_game("Xiao")
  h.keys.host_key = true
  both(h, g, 2)
  enter(g)
  both(h, g, 10)
  drop(g)
  both(h, g, 2)
  h.keys.leave_key = true
  both(h, g, 2)
  h.keys.leave_key = true -- the guest is gone: closes at once
  both(h, g, 80)
  check(g.mod.state.role == nil and g.session.kind == "title" and find_toast(g, "the room is gone"),
        "a guest can't get back into a room that closed meanwhile")

  -- out of step: the same floor built another way, and doors the guest missed
  relay.rooms = {}
  h, g = make_game("Toan"), make_game("Xiao")
  h.keys.host_key = true
  both(h, g, 2)
  enter(g)
  both(h, g, 10)
  g.settings.follow_offers = false
  h.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 500}
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 501}
  h.player = {character = "toan", position = {x = 320, y = 0, z = 480}, heading = 0, motion = 0}
  g.player = {character = "xiao", position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  both(h, g, 330)
  local panel = g.panel
  check(panel and panel.title == "Out of step with the host", "a guest on the host's floor built differently is told", panel and panel.title)
  g.choose(1)
  both(h, g, 2)
  check(g.entered[#g.entered] == "floor 0:2", "and can walk in again beside the host", g.entered[#g.entered])
  g.map = {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 500}
  both(h, g, 60)
  -- a door the host opened that the guest missed (a message lost on the way)
  h.doors_out = {{script = 50, mode = 1, ext = 0, pos = {1, 0, 1}, dir = {0, 0, 1}}}
  h.tick(11)
  g.net_events = {} -- lost on the way
  local before = #g.doors_run
  both(h, g, 320)
  check(#g.doors_run == before + 1 and g.doors_run[#g.doors_run].script == 50, "a guest with fewer doors open asks for them and gets them",
        #g.doors_run - before)
  g.emit("ui.action", {id = "resync"})
  check(find_toast(g, "asked the host for the doors"), "the Mod Manager's Resync asks the host again")

  -- a host that never answers a join
  relay.rooms = {}
  local silent, lone = make_game("Toan"), make_game("Xiao")
  silent.keys.host_key = true
  silent.tick(2)
  enter(lone)
  lone.tick(1805)
  check(lone.mod.state.role == nil and lone.title.lines[3]:find("didn't send their world", 1, true),
        "a join the host never answers ends after half a minute", lone.title.lines[3])
end

print("The mod's manifest")
do
  local f = assert(io.open(root .. "/mods/moonmod.coop/mod.json", "rb"))
  local text = f:read("a")
  f:close()
  local settings = text:match('"settings": %[(.*)%]')
  local long = {}
  for name in (settings or ""):gmatch('"name": "(.-)"') do if #name > 96 then long[#long + 1] = name:sub(1, 30) end end
  check(settings and #long == 0, "every setting's name fits the engine's 96 bytes (else the game refuses the whole mod)",
        table.concat(long, " / "))
end

print("Falling and getting back up")
do
  relay.rooms = {}
  local function enter(g)
    for i = 1, 5 do
      for _ = 1, 40 do
        if g.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
        g.emit("game.title.selected", {entry = "c" .. i})
      end
    end
    g.emit("game.title.selected", {entry = "join"})
  end
  local h, g = make_game("Toan"), make_game("Xiao")
  h.tick(2)
  check(not h.down_rule, "out of a room the game's own knockout stands")
  h.keys.host_key = true
  both(h, g, 2)
  enter(g)
  both(h, g, 10)
  check(h.down_rule == true and g.down_rule == true, "in a room every game lies down instead")
  g.settings.follow_offers = false
  h.map = {context = "dungeon", dungeon_id = 1, floor_id = 2, floor_seed = 77}
  g.map = {context = "dungeon", dungeon_id = 1, floor_id = 2, floor_seed = 77}
  h.player = {character = "toan", hp = 40, max_hp = 60, position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  g.player = {character = "xiao", hp = 30, max_hp = 45, position = {x = 30, y = 0, z = 0}, heading = 0, motion = 0}
  both(h, g, 60)

  -- the guest falls: the host sees it lying there and revives it by holding Revive
  g.player.down, g.player.hp = true, 0
  both(h, g, 30)
  check(find_toast(g, "you're down"), "a fallen player is told they're down")
  check(find_toast(h, "Xiao is down"), "and the others that they can revive them")
  check(h.avatars[1] and h.avatars[1].down == true, "the host's screen shows Xiao's hero lying down")
  for _ = 1, 100 do h.keys.revive = true; both(h, g, 1) end
  check(tostring(h.layers.coop_revive):find("Reviving Xiao", 1, true), "holding Revive shows how far along it is",
        tostring(h.layers.coop_revive))
  h.player.hp = 30 -- struck while holding
  for _ = 1, 5 do h.keys.revive = true; both(h, g, 1) end
  check(find_toast(h, "hit! Hold Revive again") and g.player.down == true, "a hit starts the revive over")
  for _ = 1, 185 do h.keys.revive = true; both(h, g, 1) end
  both(h, g, 4)
  check(g.player.down == false and g.player.hp == 15, "held for three seconds, the guest gets up with a third of its HP", g.player.hp)
  check(find_toast(g, "Toan revived you") and find_toast(h, "Xiao is back on their feet"), "and both hear it")
  do
    local downs = 0
    for _, t in ipairs(h.toasts) do if t:find("Xiao is down", 1, true) then downs = downs + 1 end end
    g.player.down = true -- the game stands the hero up a frame late
    both(h, g, 1)
    g.player.down = false
    both(h, g, 10)
    local after = 0
    for _, t in ipairs(h.toasts) do if t:find("Xiao is down", 1, true) then after = after + 1 end end
    check(after == downs and g.mod.fall.state == "up", "the frame before the game stands the hero up isn't another fall")
  end
  both(h, g, 30)
  check(h.avatars[1] and not h.avatars[1].down, "Xiao's hero stands up on the host's screen")

  -- too far away: nothing happens; a Revival Powder revives at once, at half HP
  g.player.down, g.player.hp = true, 0
  g.player.position = {x = 400, y = 0, z = 0}
  both(h, g, 30)
  for _ = 1, 200 do h.keys.revive = true; both(h, g, 1) end
  check(g.player.down == true, "a player too far away can't revive")
  h.player.position = {x = 390, y = 0, z = 0}
  h.bag = {{id = "chronicle:item:revival-powder", name = "Revival Powder", count = 1}}
  h.keys.revive = true
  both(h, g, 4)
  check(g.player.down == false and g.player.hp == 22 and h.bag[1].count == 0, "a Revival Powder revives at once, at half HP, and is used",
        tostring(g.player.hp) .. "/" .. h.bag[1].count)

  -- down too long: out, and back up beside the host after the wait (longer with each fall on the floor)
  both(h, g, 30)
  g.player.down, g.player.hp = true, 0
  both(h, g, 1800 + 10)
  check(find_toast(g, "you're out; back on your feet in 60 seconds"), "after half a minute down, out; the wait grows each fall")
  h.player.position = {x = 500, y = 0, z = 80}
  both(h, g, 60 * 60 + 10)
  check(g.player.down == false and g.player.position.x == 500 and g.player.position.z == 80 and g.player.hp == 15,
        "then back on its feet beside the host", g.player.position.x)

  -- everyone down: the party walks back to Matataki with its things
  both(h, g, 30)
  h.player.down, h.player.hp = true, 0
  g.player.down, g.player.hp = true, 0
  both(h, g, 200)
  check(h.player.down == false and g.player.down == false and not h.gave_up and not g.gave_up, "a fallen party all stand up, no knockout")
  check(h.entered[#h.entered] == "to chronicle:location:matataki-village" and g.entered[#g.entered] == "to chronicle:location:matataki-village",
        "and walk back to the town the dungeon is reached from", h.entered[#h.entered])
  check(find_toast(h, "the party fell"), "and are told why")

  -- leaving the room while down: the game's own knockout after all
  both(h, g, 30)
  g.player.down = true
  both(h, g, 10)
  g.keys.leave_key = true
  both(h, g, 3)
  check(g.gave_up == true and g.down_rule == false, "a player who leaves while down gets the game's knockout")
end

print("Hardening: nothing another game sends is taken on trust")
do
  relay.rooms = {}
  local function enter(g)
    for i = 1, 5 do
      for _ = 1, 40 do
        if g.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
        g.emit("game.title.selected", {entry = "c" .. i})
      end
    end
    g.emit("game.title.selected", {entry = "join"})
  end
  local function said(to, from, data) queue(to, {kind = "message", peer = from, data = data}) end
  local h, g = make_game("Toan"), make_game("Xiao")
  h.keys.host_key = true
  both(h, g, 2)
  enter(g)
  both(h, g, 10)
  g.settings.follow_offers, h.settings.follow_offers = false, false
  h.map = {context = "dungeon", dungeon_id = 1, floor_id = 2, floor_seed = 77}
  g.map = {context = "dungeon", dungeon_id = 1, floor_id = 2, floor_seed = 77}
  h.player = {character = "toan", hp = 40, max_hp = 60, position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  g.player = {character = "xiao", hp = 30, max_hp = 45, position = {x = 30, y = 0, z = 0}, heading = 0, motion = 0}
  both(h, g, 60)
  local scene = "D1:2:77"

  -- messages no game would write, and one honest gift behind them in the same answer
  said(h, 1, "E " .. scene .. " 1  2 3")
  said(h, 1, "E " .. scene .. " " .. string.rep("9 ", 4000))
  said(h, 1, "PONG -1e300")
  said(h, 1, "PONG 1e300")
  said(h, 1, "PING " .. string.rep("7", 5000))
  said(h, 1, "P D0:99999999999999999999:1 xiao - 0 0 0 0 0")
  said(h, 1, "P D1:2:77 xiao - nan inf -inf 1e300 1e300")
  said(h, 1, "M " .. string.rep("x", 20000))
  said(h, 1, "DN " .. string.rep("down", 100))
  said(h, 1, "N " .. string.rep("\255", 300))
  said(h, 1, "V g nan")
  said(h, 1, "V i")
  said(h, 1, "H 1 2 3")
  said(h, 1, "KEEP 1 1 garbage")
  said(h, 1, "TOWN 9 2 x")
  said(h, 1, "")
  queue(h, {kind = "message", peer = 1})
  queue(h, {kind = "message", peer = "one", data = "V g 5"})
  said(h, 1, "V g 500")
  local ok = pcall(both, h, g, 90)
  check(ok and h.gilda == 1500, "an honest gift behind a batch of nonsense still arrives, and the game plays on", h.gilda)
  check(next(h.accounts) == nil or not (function() for _, a in pairs(h.accounts) do if a.data == "garbage" then return true end end end)(),
        "what isn't a game's things is never kept as a guest's")
  check(#h.doors_run == 0, "a door no game would write opens nothing")
  both(h, g, 30)
  check(h.mod.state.names[1] ~= nil and #h.mod.state.names[1] <= 24, "a name stays a name", h.mod.state.names[1])

  -- gifts: no more than a wallet, twice a minute; what is over goes back, and nothing "comes back" that wasn't given
  h.gilda = 0
  local before = g.gilda
  said(h, 1, "V g 1000000")
  both(h, g, 4)
  check(h.gilda == 65535, "one gift of Gilda is a wallet at most", h.gilda)
  check(g.gilda == before, "the rest sent back is only taken by a game that gave it", g.gilda)
  h.gilda = 0
  said(h, 1, "V g 65535")
  both(h, g, 2)
  h.gilda = 0
  said(h, 1, "V g 65535")
  both(h, g, 2)
  check(h.gilda == 0 and find_toast(h, "more than a gift can hold"), "and two wallets a minute from one player", h.gilda)
  said(h, 1, "V back g 5000")
  said(h, 7, "V g 100")
  both(h, g, 2)
  check(h.gilda == 0, "Gilda never given doesn't come back, and a stranger gives nothing", h.gilda)
  h.bag, h.bag_room = {}, 100000
  said(h, 1, "V i chronicle:item:bread 999 Bread")
  both(h, g, 2)
  check(h.bag[1] and h.bag[1].count == 99, "an item gift is a slot's worth at most", h.bag[1] and h.bag[1].count)
  for _ = 1, 60 do said(h, 1, "V i chronicle:item:bread 1 Bread") end
  both(h, g, 2)
  check(h.bag[1].count == 99 + 39, "and forty gifts a minute", h.bag[1].count)
  said(h, 1, "V back i chronicle:item:bread 50 Bread")
  both(h, g, 2)
  check(h.bag[1].count == 99 + 39, "items never given don't come back")
  -- a minute on, the same player can give again
  both(h, g, 3700)
  h.gilda = 0
  said(h, 1, "V g 250")
  both(h, g, 2)
  check(h.gilda == 250, "a minute later gifts are gifts again", h.gilda)

  -- a gift that can't leave stays with its giver
  do
    local net = h.net
    h.gilda = 800
    h.net = nil
    h.mod.together.give_gilda(1, 300)
    h.net = net
    check(h.gilda == 800 and find_toast(h, "couldn't be sent; you still have it"), "Gilda that couldn't be sent is still the giver's", h.gilda)
    h.mod.together.give_gilda(7, 300)
    check(h.gilda == 800 and find_toast(h, "they have left the room"), "and none goes to a player who has left", h.gilda)
    g.gilda = 100
    h.mod.together.give_gilda(1, 300)
    both(h, g, 4)
    check(h.gilda == 500 and g.gilda == 400, "an honest gift still goes through", h.gilda .. "/" .. g.gilda)
    g.gilda = 65535
    h.mod.together.give_gilda(1, 200)
    both(h, g, 6)
    check(h.gilda == 500, "and what doesn't fit comes back to the one who gave it", h.gilda)
  end

  -- a second hello on one connection sends no second world
  g.net_events = {}
  said(h, 1, "HELLO " .. g.storage.me.id .. " Xiao")
  said(h, 1, "BACK " .. g.storage.me.id .. " Xiao")
  h.tick()
  local big = 0
  for _, e in ipairs(g.net_events) do if e.kind == "message" and (e.data:match("^WORLD") or e.data:match("^PLAYER") or e.data:match("^RESUME")) then big = big + 1 end end
  check(big == 0, "a game says hello once: a second hello gets no second world", big)
  both(h, g, 4)

  -- a blow is a blow; a town is the host's; "the host" is the host's name
  h.mirror_hits = {}
  said(h, 1, "H 3 1000000")
  said(h, 1, "H 4000 5")
  h.tick()
  check(#h.mirror_hits == 1 and h.mirror_hits[1].damage == 9999, "a guest's blow is never more than the game's most",
        h.mirror_hits[1] and h.mirror_hits[1].damage)
  local town = h.towns[0]
  said(h, 1, "TOWN 1 1 DCT10:flattened")
  both(h, g, 4)
  check(h.towns[0] == town, "a whole town from a guest (not what it changed) is not taken", h.towns[0])
  said(h, 1, "N The Host")
  h.tick()
  check(h.mod.state.names[1] ~= "The Host", "a guest can't call itself the host", h.mod.state.names[1])
  said(h, 1, "N " .. string.rep("a", 23) .. "\195\169\195\169")
  h.tick()
  check(h.mod.state.names[1] == string.rep("a", 23), "a long name is cut between characters, not through one", h.mod.state.names[1])
  both(h, g, 40)

  -- doors: only as many as a floor could have are remembered, and those of a floor left are let go
  for i = 1, 400 do said(h, 1, string.format("E %s %d 0 0 1.0 2.0 3.0 0 0 0", scene, i)) end
  both(h, g, 4)
  local log = h.mod.door.log[scene] or {}
  check(#log <= 256, "no more doors are remembered than a floor could have", #log)
  said(h, 1, "E " .. scene .. " 99999 0 0 1 2 3 0 0 0")
  said(h, 1, "E " .. scene .. " 5 7 0 1 2 3 0 0 0")
  said(h, 1, "E D1:3:78 6 0 0 1 2 3 0 0 0")
  h.tick()
  check(#(h.mod.door.log[scene] or {}) == #log and h.mod.door.log["D1:3:78"] == nil, "a door out of the game's range, or on another floor, is no door")

  -- reviving: only a player standing here; the party's fall only from one who fell
  h.player.down, h.player.hp = true, 0
  both(h, g, 10)
  said(h, 7, "RV hold")
  said(h, 1, "DN fell")
  both(h, g, 4)
  check(h.player.down == true and #h.entered == 0, "a stranger revives no one, and a standing player can't call the party's fall")
  g.player.position = {x = 30000, y = 0, z = 0}
  both(h, g, 12)
  said(h, 1, "RV powder")
  both(h, g, 2)
  check(h.player.down == true, "nor does a player far across the floor")
  g.player.position = {x = 30, y = 0, z = 0}
  both(h, g, 12)
  -- a powder is only used when it worked: the fallen player got up before it reached them
  g.bag = {{id = "chronicle:item:revival-powder", name = "Revival Powder", count = 1}}
  h.player.down, h.player.hp = false, 20
  h.tick() -- up again, its word not yet with the guest
  g.keys.revive = true
  g.tick()
  both(h, g, 700)
  check(g.bag[1].count == 1, "a Revival Powder that revived no one is not used up", g.bag[1].count)

  -- the host's game leaves its story: the room closes, so nothing of a guest's reaches another save
  h.session = {kind = "title"}
  both(h, g, 70)
  check(h.mod.state.role == nil and h.net == nil and h.down_rule == false, "a host whose game leaves its story closes the room")
  check(g.mod.state.role == nil, "and its guests are let go")

  -- a refusal in the middle of a visit ends the visit (the player isn't left in a world with no room)
  do
    relay.rooms = {}
    local h2, g2 = make_game("Toan"), make_game("Xiao")
    h2.keys.host_key = true
    both(h2, g2, 2)
    enter(g2)
    both(h2, g2, 10)
    check(g2.session.kind == "visit", "(a visit, to refuse)")
    said(g2, 0, "REFUSE the host changed its mind")
    g2.tick(3)
    check(g2.session.kind == "title" and g2.mod.state.role == nil, "a refusal mid-visit ends the visit", g2.session.kind)
    check(tostring(g2.mod.state.status):find("turned the visit away", 1, true), "and the title page says why", g2.mod.state.status)
  end

  -- the mod switched off with a room open, its player down
  do
    relay.rooms = {}
    local h3 = make_game("Toan")
    h3.keys.host_key = true
    h3.tick(3)
    h3.player = {character = "toan", hp = 0, max_hp = 60, down = true, position = {x = 0, y = 0, z = 0}}
    h3.emit("runtime.unloaded", {})
    check(h3.net == nil and h3.down_rule == false and h3.gave_up == true, "switched off in a room: the room closes and no one is left lying down")
  end
end

print("Chronicle Two: the same mod in Dark Cloud 2")
do
  relay.rooms = {}
  local h = make_game("Max", {game = "chronicle-two"})
  local g = make_game("Monica", {game = "chronicle-two"})
  check(h.mod.game == "chronicle-two" and h.mod.town_tag == "DCT2", "the mod knows which game it is in", h.mod.game)
  check(h.mod.dungeons[0] == "Underground Channel" and h.mod.towns[4] == "Moon Flower Palace" and h.mod.towns[0] == "Sindain",
        "and names Dark Cloud 2's dungeons and its Georama towns")
  check(g.title.subtitle == "Visit a friend's Dark Cloud 2", "the title page says whose world", g.title.subtitle)
  h.keys.host_key = true
  both(h, g, 2)
  for i = 1, 5 do
    for _ = 1, 40 do
      if g.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
      g.emit("game.title.selected", {entry = "c" .. i})
    end
  end
  g.emit("game.title.selected", {entry = "join"})
  both(h, g, 6)
  check(g.started and g.started.world == h.world and g.started.world:sub(1, 4) == "DCW2", "the guest's visit takes the host's Dark Cloud 2 world",
        g.started and g.started.world:sub(1, 4))
  check(g.started and g.started.map == 2, "and arrives in the host's town by its area (world.get().town_map), not its map number",
        g.started and g.started.map)
  check(g.started and g.started.map_no == 23, "and at the host's own map (world.get().map_no): Palm Brinks has no other name",
        g.started and g.started.map_no)
  check(h.layers.coop_who == "Monica" and g.layers.coop_who == "Max", "the HUDs name each other")
  -- a place is the map the town runs; inside a house, the map and the house in one number
  g.map = h.map
  both(h, g, 40)
  check(h.mod.state.places["T23"] == "Balance Valley" and g.mod.state.places["T23"] == "Balance Valley",
        "each game says what its place is called", tostring(g.mod.state.places["T23"]))
  -- the guest's things are Dark Cloud 2's, and the host keeps them
  g.things = "DCP2" .. string.rep("q", 30000) .. "after a fight"
  both(h, g, 60 * 60 + 2)
  local kept = h.accounts[g.storage.me.id]
  check(kept and kept.data == g.things, "after a minute the host keeps the guest's Dark Cloud 2 things", kept and #kept.data)
  -- the host in a dungeon: the guest arrives in the town that dungeon is reached from
  local k = make_game("Donny", {game = "chronicle-two"})
  h.mod.state.ROOM_FOR = 4 -- (a third game, to see what the host passes on: by itself a Dark Cloud 2 room is for two)
  h.map = {context = "dungeon", dungeon_id = 5, floor_id = 2, floor_seed = 77, map_no = 40}
  for i = 1, 5 do
    for _ = 1, 40 do
      if k.title.entries[i].label:sub(-1) == ("ABCDE"):sub(i, i) then break end
      k.emit("game.title.selected", {entry = "c" .. i})
    end
  end
  k.emit("game.title.selected", {entry = "join"})
  both(h, k, 6)
  check(k.started and k.started.map == 4, "Moon Flower Palace is reached from Heim Rada (area 4)", k.started and k.started.map)
  -- a Dark Cloud 2 town goes across with its own tag
  -- (the town's Georama goes by its own number, 1, which is neither its area nor the map the test stands on)
  g.map = {context = "georama", map_id = 23, town_map = 2, georama_town = 1, scene_map = 23, map_no = 23, map_title = "Balance Valley", editing = true}
  both(h, g, 31)
  g.towns[1] = "DCT21:" .. "a windmill"
  g.map = {context = "georama", map_id = 23, town_map = 2, georama_town = 1, scene_map = 23, map_no = 23, map_title = "Balance Valley", editing = false}
  both(h, g, 31)
  check(h.towns[1] == "DCT21:a windmill" and h.last_base == "DCT21:start", "the guest's edit of Balance Valley reaches the host, merged over the town as it was",
        tostring(h.towns[1]))
  check(find_toast(h, "changed Balance Valley"), "and the host is told by the town's name")
  -- the follow offer names Dark Cloud 2's places (the offer for the host's earlier move is answered first)
  g.settings.follow_offers = true
  if g.panel then g.choose(nil) end
  h.map = {context = "dungeon", dungeon_id = 6, floor_id = 9, floor_seed = 1, map_no = 40}
  h.player = {character = "max", weapon = {item_no = 300}, position = {x = 10, y = 0, z = 20}, heading = 0.5, motion = 1}
  both(h, g, 48) -- a new place is offered once it has settled (the floor's number and seed held for a moment)
  check(g.panel and g.panel.title:find("Zelmite Mine, floor 9", 1, true) ~= nil, "a follow offer names the Zelmite Mine floor by the game's own number", g.panel and g.panel.title)
  -- the host walks into a house in another town: no question is asked (Dark Cloud 2 asks only at a dungeon floor),
  -- but the Mod Manager's "Join a player" names the house as the host's game does, and the way there is the town's map
  if g.panel then g.choose(nil) end
  h.map = {context = "georama", map_id = 12, town_map = 1, scene_map = 12, house = 34, map_no = 10, map_title = "Max's House", walking = true}
  both(h, g, 48)
  check(g.panel == nil, "a friend walking about the towns is not asked after at every door", g.panel and g.panel.title)
  g.emit("ui.action", {id = "follow"})
  both(h, g, 2)
  check(g.panel and g.panel.options[1] and tostring(g.panel.options[1].subtitle):find("Max's House", 1, true) ~= nil,
        "the Mod Manager's Join a player names a house by the name its game gave", g.panel and g.panel.options[1] and g.panel.options[1].subtitle)
  g.entered = {}
  if g.panel then g.choose(1) end
  both(h, g, 4)
  check(g.entered[1] == "map 12", "and joining walks into the town map the house stands in", g.entered[1])
end

print("Chronicle Two: a joiner's own save, and the gate")
do
  relay.rooms = {}
  local function entry(g, id) for _, e in ipairs(g.title.entries) do if e.id == id then return e end end end
  local function has_line(g, text) for _, l in ipairs(g.title.lines) do if l:find(text, 1, true) then return true end end return false end
  local function type_code(g, room)
    for i = 1, 5 do
      for _ = 1, 40 do
        if g.title.entries[i].label:sub(-1) == room:sub(i, i) then break end
        g.emit("game.title.selected", {entry = "c" .. i})
      end
    end
  end
  -- the host's own story has to be past the talk with Donny
  local h = make_game("Max", {game = "chronicle-two", slots = {}})
  h.map.progress = 1
  h.keys.host_key = true
  h.tick(3)
  check(h.mod.state.role == nil and find_toast(h, "talked to Donny"), "a host whose story has not reached Donny opens no room")
  h.map.progress = 2
  h.keys.host_key = true
  h.tick(3)
  check(h.mod.state.role == "host", "at the gate the room opens")
  local room = h.mod.state.code
  -- a joiner whose only save is before the gate
  local early = make_game("Early", {game = "chronicle-two", slots = {{slot = 0, ready = true, progress = 1, chapter = 0}}})
  early.emit("game.title.opened", {})
  check(has_line(early, "talked to Donny") and entry(early, "join").enabled == false and entry(early, "save").label == "Your save: none yet",
        "a joiner with no save past the gate is told so, and Join is closed")
  type_code(early, room)
  early.emit("game.title.selected", {entry = "join"})
  both(h, early, 6)
  check(early.mod.state.role == nil and early.started == nil, "and joining does nothing")
  -- a joiner with saves: the ones past the gate can be picked, and the pick's things come along
  local g = make_game("Monica", {game = "chronicle-two", slots = {
    {slot = 0, ready = true, progress = 1, chapter = 0}, {slot = 2, ready = true, progress = 2, chapter = 1},
    {slot = 5, ready = true, progress = 7, chapter = 5}, {slot = 6, ready = false, progress = 0, chapter = 0}}})
  g.emit("game.title.opened", {})
  check(entry(g, "save").label == "Your save: File 3 (chapter 1)" and entry(g, "save").enabled == true and #g.title.entries == 8,
        "the page names the first save past the gate", entry(g, "save").label)
  g.emit("game.title.selected", {entry = "save"})
  check(entry(g, "save").label == "Your save: File 6 (chapter 5)", "and steps to the next one", entry(g, "save").label)
  g.emit("game.title.selected", {entry = "save"})
  g.emit("game.title.selected", {entry = "save"})
  check(entry(g, "save").label == "Your save: File 6 (chapter 5)" and g.storage.own_slot == 5, "round the saves and back; the pick is remembered",
        entry(g, "save").label)
  type_code(g, room)
  g.emit("game.title.selected", {entry = "join"})
  both(h, g, 6)
  check(g.started and g.started.player == "DCP2 own 5" and g.started.world == h.world, "the visit starts with the things of the save picked",
        g.started and g.started.player)
  check(find_toast(h, "joins with their own save") and next(h.accounts) == nil, "and the host keeps nothing for that player")
  g.things = "DCP2" .. string.rep("q", 500) .. "after a fight"
  both(h, g, 60 * 60 + 2)
  local wrote = g.slot_writes[#g.slot_writes]
  check(wrote and wrote.slot == 5 and wrote.data == g.things, "after a minute the things are written into that save", wrote and wrote.slot)
  check(next(h.accounts) == nil, "not sent to the host")
  -- the host closing its room does not wait on a joiner who keeps their own things
  h.keys.leave_key = true
  both(h, g, 6)
  check(h.mod.state.role == nil and g.started ~= nil and find_toast(g, "host"), "the host closes at once: there is nothing of that player's to keep")
  -- a game that says its save is past the gate when it is not: the host turns it away
  relay.rooms = {}
  local h2 = make_game("Max", {game = "chronicle-two", slots = {}})
  h2.map.progress = 4
  h2.keys.host_key = true
  h2.tick(3)
  local liar = make_game("Liar", {game = "chronicle-two", slots = {{slot = 1, ready = true, progress = 1, chapter = 0}}})
  liar.mod.own.GATE = 0
  liar.emit("game.title.opened", {})
  type_code(liar, h2.mod.state.code)
  liar.emit("game.title.selected", {entry = "join"})
  both(h2, liar, 8)
  check(liar.started == nil and next(h2.mod.state.players) == nil or not (h2.mod.state.players[1] and h2.mod.state.players[1].in_visit),
        "a save before the gate is refused by the host, whatever its game says")
  check(liar.started == nil, "and no visit starts")
end

print("Chronicle Two: one hero each, and the swap")
do
  relay.rooms = {}
  local function type_code(g, room)
    for i = 1, 5 do
      for _ = 1, 40 do
        if g.title.entries[i].label:sub(-1) == room:sub(i, i) then break end
        g.emit("game.title.selected", {entry = "c" .. i})
      end
    end
  end
  -- alone in a room there is nobody to swap with
  local alone = make_game("Solo", {game = "chronicle-two", heroes = true})
  alone.keys.host_key = true
  alone.tick(3)
  alone.emit("ui.action", {id = "swap"})
  check(find_toast(alone, "exactly two players"), "a host alone is told a swap takes two")
  relay.rooms = {} -- the fake relay gives every host the same code: one room at a time
  local h = make_game("Jeffie", {game = "chronicle-two", heroes = true})
  local g = make_game("April", {game = "chronicle-two", heroes = true})
  h.keys.host_key = true
  both(h, g, 3)
  check(h.room_hero == "max", "the host's game plays Max once its room is open", tostring(h.room_hero))
  g.emit("game.title.opened", {})
  type_code(g, h.mod.state.code)
  g.emit("game.title.selected", {entry = "join"})
  both(h, g, 8)
  check(g.started ~= nil and g.room_hero == "monica" and g.hero_log[1] == "monica",
        "the joiner's game is given Monica before its visit starts, so it starts as her", table.concat(g.hero_log, ", "))
  -- each game draws the other's hero in what that player's own hero wears
  h.player = {character = "max", town_character = "max", outfit = {head = 301, clothes = 302, feet = 303, sub = 304},
              position = {x = 10, y = 0, z = 20}, heading = 0, motion = 0}
  g.player = {character = "monica", town_character = "monica", outfit = {head = 0, clothes = 402, feet = 403, sub = 404},
              position = {x = 14, y = 0, z = 20}, heading = 0, motion = 0}
  g.map = h.map
  both(h, g, 48)
  local sees_host, sees_guest = g.avatars[1], h.avatars[1]
  check(sees_host and sees_host.character == "max" and sees_host.outfit and sees_host.outfit.head == 301 and sees_host.outfit.sub == 304,
        "the joiner's game is told what the host's Max wears", sees_host and sees_host.outfit and sees_host.outfit.head)
  check(sees_guest and sees_guest.character == "monica" and sees_guest.outfit and sees_guest.outfit.clothes == 402 and sees_guest.outfit.head == nil,
        "and the host's what the joiner's Monica wears (nothing on her head)", sees_guest and sees_guest.outfit and sees_guest.outfit.clothes)
  h.player.outfit.head = 311
  both(h, g, 12)
  check(g.avatars[1] and g.avatars[1].outfit.head == 311, "a change of hat reaches the other game", g.avatars[1] and g.avatars[1].outfit.head)
  -- riding the ridepod, the other game is told its four parts and draws it; in a monster form, that monster
  -- (on a floor, where the game gives no town_character)
  h.player.town_character = nil
  h.player.character, h.player.ridepod = "ridepod", {leg = 155, arm = 145, body = 135, pack = 165}
  both(h, g, 12)
  local rp = g.avatars[1] and g.avatars[1].ridepod
  check(rp and rp.leg == 155 and rp.arm == 145 and rp.body == 135 and rp.pack == 165 and g.avatars[1].form == nil,
        "the host's ridepod is drawn with its own four parts in the joiner's game", rp and rp.leg)
  h.player.character, h.player.ridepod, h.player.form = "monster", nil, 0
  both(h, g, 12)
  check(g.avatars[1] and g.avatars[1].form == 0 and g.avatars[1].ridepod == nil,
        "a monster form (even form 0) is drawn as that monster", g.avatars[1] and g.avatars[1].form)
  h.player.character, h.player.form = "max", nil
  both(h, g, 12)
  check(g.avatars[1] and g.avatars[1].form == nil and g.avatars[1].ridepod == nil and g.avatars[1].outfit.head == 311,
        "back on foot, Max is drawn in his own clothes again", g.avatars[1] and g.avatars[1].form)
  -- the joiner asks; the host is asked on a panel and says no
  g.emit("ui.action", {id = "swap"})
  both(h, g, 4)
  check(h.panel and h.panel.title == "April wants to swap heroes" and h.panel.subtitle == "You would play Monica.",
        "the other player is asked on a panel", h.panel and h.panel.title)
  h.choose(2)
  both(h, g, 4)
  check(h.room_hero == "max" and g.room_hero == "monica" and find_toast(g, "would rather not swap"), "a no changes nothing, and the asker is told")
  -- asked again (after the wait between two panels), the host says yes: both change
  both(h, g, 300)
  g.emit("ui.action", {id = "swap"})
  both(h, g, 4)
  check(h.panel ~= nil, "asked again, the panel comes again")
  h.choose(1)
  both(h, g, 4)
  check(h.room_hero == "monica" and g.room_hero == "max", "on yes the two games trade heroes", tostring(h.room_hero) .. "/" .. tostring(g.room_hero))
  check(find_toast(h, "you play Monica now") and find_toast(g, "you play Max now"), "and each is told who they play")
  -- and back, asked by the host
  both(h, g, 300)
  h.emit("ui.action", {id = "swap"})
  both(h, g, 4)
  check(g.panel and g.panel.title == "Jeffie wants to swap heroes" and g.panel.subtitle == "You would play Monica.", "either player can ask",
        g.panel and g.panel.title)
  g.choose(1)
  both(h, g, 4)
  check(h.room_hero == "max" and g.room_hero == "monica", "and a second swap puts them back")
  -- a yes nobody asked for is not a swap
  h.mod.heroes.hear(1, "yes")
  check(h.room_hero == "max", "an answer to no question changes nothing")
  -- a joiner into a swapped room starts as the hero the room gives it
  both(h, g, 300)
  g.emit("ui.action", {id = "swap"})
  both(h, g, 4)
  h.choose(1)
  both(h, g, 4)
  g.keys.leave_key = true
  both(h, g, 8)
  check(g.room_hero == nil, "leaving the room gives the party back to the story", tostring(g.room_hero))
  local late = make_game("Late", {game = "chronicle-two", heroes = true})
  late.emit("game.title.opened", {})
  type_code(late, h.mod.state.code)
  late.emit("game.title.selected", {entry = "join"})
  both(h, late, 8)
  check(late.started ~= nil and late.hero_log[1] == "max", "a joiner into a swapped room starts as Max", table.concat(late.hero_log, ", "))
  -- the room's end is the rule's end
  h.keys.leave_key = true
  both(h, late, 12)
  h.keys.leave_key = true
  both(h, late, 12)
  check(h.room_hero == nil and late.room_hero == nil, "when the room closes both parties are the story's again",
        tostring(h.room_hero) .. "/" .. tostring(late.room_hero))
end

print("Chronicle Two: the world as it changes")
do
  relay.rooms = {}
  local function type_code(g, room)
    for i = 1, 5 do
      for _ = 1, 40 do
        if g.title.entries[i].label:sub(-1) == room:sub(i, i) then break end
        g.emit("game.title.selected", {entry = "c" .. i})
      end
    end
  end
  local function join(g, h)
    g.emit("game.title.opened", {})
    type_code(g, h.mod.state.code)
    g.emit("game.title.selected", {entry = "join"})
    both(h, g, 8)
  end
  local function last(g) return g.applied[#g.applied] end
  local h = make_game("Max", {game = "chronicle-two", shared = true})
  local g = make_game("Monica", {game = "chronicle-two", shared = true})
  local k = make_game("Donny", {game = "chronicle-two", shared = true})
  h.mod.state.ROOM_FOR = 4 -- (a third game, to see what the host passes on: by itself a Dark Cloud 2 room is for two)
  h.keys.host_key = true
  h.tick(3)
  check(h.watching == true, "the host's game watches its world once the room is open")
  check(g.watching == nil, "a game at the title watches nothing")
  join(g, h)
  check(g.started ~= nil and g.watching == true, "a joiner's game watches from the start of its visit")
  join(k, h)
  for _ = 1, 4 do h.tick(); g.tick(); k.tick() end
  -- the joiner sees a scene alone: its flag reaches the host's world, and the other joiner's
  g.emit("game.world.changed", {kind = "flag", id = 100, value = true})
  for _ = 1, 4 do h.tick(); g.tick(); k.tick() end
  check(last(h) and last(h).kind == "flag" and last(h).id == 100 and last(h).value == true, "a flag a joiner sets reaches the host's world",
        last(h) and last(h).id)
  check(last(k) and last(k).id == 100 and last(k).value == true, "and the host passes it to the other joiner")
  check(#g.applied == 0, "and it is not told back to the game that set it", #g.applied)
  -- the host moves the story on: every joiner hears
  h.emit("game.world.changed", {kind = "progress", id = 0, value = 4})
  h.emit("game.world.changed", {kind = "counter", id = 12, value = -3})
  for _ = 1, 4 do h.tick(); g.tick(); k.tick() end
  check(#g.applied == 2 and g.applied[1].kind == "progress" and g.applied[1].value == 4 and g.applied[2].kind == "counter" and g.applied[2].value == -3,
        "the host's story progress and a counter reach a joiner", #g.applied)
  check(#k.applied == 3, "and the other", #k.applied)
  -- a flag cleared, a townsperson won over, a floor's record
  g.emit("game.world.changed", {kind = "flag", id = 4, value = false})
  g.emit("game.world.changed", {kind = "recruit", id = 2, value = {14, 1}})
  g.emit("game.world.changed", {kind = "floor", id = 40, value = {0, 3000, 0, 0, 0, 1, 3, 9, 2}})
  for _ = 1, 4 do h.tick(); g.tick(); k.tick() end
  local n = #h.applied
  check(n == 4 and h.applied[2].kind == "flag" and h.applied[2].value == false, "a flag cleared is told as cleared", n)
  check(h.applied[3].kind == "recruit" and h.applied[3].value[1] == 14 and h.applied[3].value[2] == 1, "a townsperson who can join now")
  check(h.applied[4].kind == "floor" and #h.applied[4].value == 9 and h.applied[4].value[2] == 3000 and h.applied[4].value[7] == 3,
        "and a floor's record, all nine numbers")
  -- what a scene gives one player goes into the others' bags too
  h.toasts, k.toasts = {}, {}
  g.emit("game.world.changed", {kind = "gift", id = 231, value = 1})
  for _ = 1, 4 do h.tick(); g.tick(); k.tick() end
  n = #h.applied
  check(h.applied[n].kind == "gift" and h.applied[n].id == 231 and h.applied[n].value == 1, "an item a scene gave the joiner goes into the host's bag too",
        h.applied[n].kind)
  check(last(k) and last(k).kind == "gift" and last(k).id == 231, "and the other joiner's")
  check(find_toast(h, "was given something in a scene") and find_toast(k, "was given something in a scene"), "and each is told")
  -- nothing another game sends is taken on trust
  h.mod.shared.hear(1, "gilda 0 999999")
  h.mod.shared.hear(1, "flag 5 1,2")
  h.mod.shared.hear(1, "floor 3 1,2,3")
  h.mod.shared.hear(1, "flag 5 " .. string.rep("1", 200))
  check(#h.applied == n, "what is not a change of the world is dropped", #h.applied)
  local before = #g.applied
  g.mod.shared.hear(2, "flag 7 1")
  check(#g.applied == before, "a joiner takes the world's changes from the host alone")
  -- a town's Georama: the game says only that it changed, and the town goes across as towns do
  local function town_tick() for _ = 1, 8 do h.tick(); g.tick(); k.tick() end end
  h.toasts, k.toasts = {}, {}
  g.towns[2] = "DCT22:a bridge over the canal"
  g.emit("game.world.changed", {kind = "town", id = 2, value = 77})
  town_tick()
  check(h.towns[2] == "DCT22:a bridge over the canal" and h.last_base == "DCT22:start",
        "a town a joiner's game says changed reaches the host, with the town it was changed from", tostring(h.towns[2]))
  check(k.towns[2] == g.towns[2], "and the other joiner")
  check(find_toast(h, "is building in Veniccio"), "named as the Georama town it is (2 is Veniccio)")
  g.emit("game.world.changed", {kind = "town", id = 2, value = 77})
  h.last_base = nil
  town_tick()
  check(h.last_base == nil, "a town that is as the games agreed is not sent again")
  -- a second change is measured from the first, not from the visit's start
  g.towns[2] = "DCT22:a bridge and a pier"
  g.emit("game.world.changed", {kind = "town", id = 2, value = 78})
  town_tick()
  check(h.towns[2] == "DCT22:a bridge and a pier" and h.last_base == "DCT22:a bridge over the canal", "the next change is measured from the last",
        tostring(h.last_base))
  -- the host's own change is the whole town, to every joiner; what a joiner then changes is measured from that
  h.towns[0] = "DCT20:the host's new road"
  h.emit("game.world.changed", {kind = "town", id = 0, value = 5})
  town_tick()
  check(g.towns[0] == h.towns[0] and k.towns[0] == h.towns[0], "the host's change of a town reaches every joiner")
  k.towns[0] = "DCT20:the host's new road, and a tree"
  k.emit("game.world.changed", {kind = "town", id = 0, value = 6})
  town_tick()
  check(h.towns[0] == k.towns[0] and h.last_base == "DCT20:the host's new road", "and a joiner's change after it is measured from the host's town",
        tostring(h.last_base))
  check(g.towns[0] == k.towns[0], "and reaches the other joiner")
  -- in the editor a town goes part by part (the engine writes the town being built into its record)
  g.map = {context = "georama", map_id = 3, town_map = 5, georama_town = 3, scene_map = 3, map_no = 3, map_title = "Heim Rada", editing = true}
  for _ = 1, 4 do town_tick() end -- (the editor is looked for every half second)
  h.toasts = {}
  g.towns[3] = "DCT23:one house"
  g.emit("game.world.changed", {kind = "town", id = 3, value = 1})
  town_tick()
  check(h.towns[3] == "DCT23:one house" and h.last_base == "DCT23:start", "a town being built goes at the first part", tostring(h.towns[3]))
  check(k.towns[3] == "DCT23:one house", "to the other joiner too")
  g.towns[3] = "DCT23:two houses"
  g.emit("game.world.changed", {kind = "town", id = 3, value = 2})
  town_tick()
  check(h.towns[3] == "DCT23:two houses" and h.last_base == "DCT23:one house", "and at the next, measured from the part before", tostring(h.last_base))
  local told = 0
  for _, t in ipairs(h.toasts) do if t:find("is building in Heim Rada") then told = told + 1 end end
  check(told == 1, "the host is told once who builds there, not at every part", told)
  h.last_base = nil
  g.map = {context = "georama", map_id = 3, town_map = 5, georama_town = 3, scene_map = 3, map_no = 3, map_title = "Heim Rada", editing = false}
  for _ = 1, 4 do town_tick() end
  check(h.last_base == nil, "leaving the editor sends nothing more when nothing more changed")
  -- the host busy in a town's editor: a joiner's parts wait, and what is taken at last is measured from the first
  h.busy_town = 4
  k.towns[4] = "DCT24:a windmill"
  k.emit("game.world.changed", {kind = "town", id = 4, value = 1})
  town_tick()
  k.towns[4] = "DCT24:a windmill and a well"
  k.emit("game.world.changed", {kind = "town", id = 4, value = 2})
  town_tick()
  check(h.towns[4] == "DCT24:start", "a town the host is building in is not changed under them", tostring(h.towns[4]))
  h.busy_town = nil
  for _ = 1, 8 do town_tick() end
  check(h.towns[4] == "DCT24:a windmill and a well" and h.last_base == "DCT24:start",
        "once free the host takes the newest town, measured from the town before the first part that waited", tostring(h.last_base))
  check(g.towns[4] == "DCT24:a windmill and a well", "and sends it on")
  -- a part built is in the world's stock for either player to place
  h.emit("game.world.changed", {kind = "stock", id = 12, value = 2})
  town_tick()
  check(last(g) and last(g).kind == "stock" and last(g).id == 12 and last(g).value == 2, "a Georama part built goes into both games' stock")
  -- a town number that is none of the five is nothing
  h.last_base = nil
  g.emit("game.world.changed", {kind = "town", id = 9, value = 1})
  g.emit("game.world.changed", {kind = "town", id = -1, value = 1})
  town_tick()
  check(h.last_base == nil, "a town number that is not a Georama town is dropped")

  -- the room's end is the watching's end
  h.keys.leave_key = true
  for _ = 1, 12 do h.tick(); g.tick(); k.tick() end
  h.keys.leave_key = true
  for _ = 1, 12 do h.tick(); g.tick(); k.tick() end
  check(h.watching == false and g.watching == false, "when the room closes nobody watches", tostring(h.watching) .. "/" .. tostring(g.watching))
end

print("Chronicle Two: a floor is run by whoever was there first")
do
  relay.rooms = {}
  local h = make_game("Max", {game = "chronicle-two"})
  local g = make_game("Monica", {game = "chronicle-two"})
  h.keys.host_key = true
  both(h, g, 2)
  g.emit("game.title.opened", {})
  for i = 1, 5 do
    for _ = 1, 40 do
      if g.title.entries[i].label:sub(-1) == h.mod.state.code:sub(i, i) then break end
      g.emit("game.title.selected", {entry = "c" .. i})
    end
  end
  g.emit("game.title.selected", {entry = "join"})
  both(h, g, 8)
  check(g.started ~= nil, "(the joiner is in the host's world)")
  local FLOOR = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 91, map_no = 0, walking = true}
  local function rat(hp) return {slot = 0, kind = 3, state = 2, hp = hp, max_hp = 60, x = 10, y = 0, z = 0, heading = 0, motion = 0} end
  h.player = {character = "max", position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  g.player = {character = "monica", position = {x = 50, y = 0, z = 0}, heading = 0, motion = 0}
  -- the joiner goes into the dungeon alone: the floor's monsters are its own
  g.map = FLOOR
  g.monsters = {rat(25)} -- one of two already struck down, the other hurt
  both(h, g, 60)
  check(g.puppets == nil and h.puppets == nil, "a joiner alone on a floor runs its monsters itself")
  -- the host follows: the floor is still the joiner's to run, and the host's monsters copy the joiner's
  h.map = FLOOR
  h.monsters = {rat(60), {slot = 1, kind = 3, state = 2, hp = 60, max_hp = 60, x = 0, y = 0, z = 0, heading = 0, motion = 0}}
  both(h, g, 60)
  check(h.puppets and #h.puppets == 1 and h.puppets[1].hp == 25, "the host, coming second, copies the joiner's monsters as they stand",
        h.puppets and #h.puppets)
  check(g.puppets == nil, "and the joiner's stay its own")
  -- the host's blow on a copy lands on the joiner's monster; the joiner's monster strikes the host
  h.puppet_hits = {{slot = 0, damage = 11}}
  both(h, g, 8)
  check(g.mirror_hits[1] and g.mirror_hits[1].slot == 0 and g.mirror_hits[1].damage == 11, "the host's blow lands on the joiner's monster",
        #g.mirror_hits)
  check(#h.mirror_hits == 0, "not on its own")
  g.avatar_hits = {{avatar = 1, slot = 0, damage = 9, kind = 3, flags = 0}}
  both(h, g, 8)
  check(h.strikes[1] and h.strikes[1].damage == 9, "the joiner's monster strikes the host's hero", #h.strikes)
  -- the joiner leaves the floor: the host runs it from where the monsters stand
  g.map = {context = "town", scene_map = 10, map_no = 10, town_map = 1, walking = true}
  both(h, g, 60)
  check(h.puppets == nil, "when the first leaves, the floor is the second's to run")
  -- and the joiner, coming back, is the one who copies
  h.monsters = {rat(7)}
  g.map = FLOOR
  both(h, g, 60)
  check(g.puppets and #g.puppets == 1 and g.puppets[1].hp == 7, "the joiner, back on the floor, copies the host's", g.puppets and #g.puppets)
  check(h.puppets == nil, "and the host's stay its own")
  g.puppet_hits = {{slot = 0, damage = 4}}
  both(h, g, 8)
  check(h.mirror_hits[1] and h.mirror_hits[1].damage == 4, "its blows go to the host's monsters now", #h.mirror_hits)
  -- both take a floor in the same moment: the host's stands
  local NEXT = {context = "dungeon", dungeon_id = 0, floor_id = 4, floor_seed = 92, map_no = 0, walking = true}
  h.map, g.map = NEXT, NEXT
  h.monsters, g.monsters = {rat(33)}, {rat(60)}
  both(h, g, 80)
  check(h.puppets == nil and g.puppets and g.puppets[1] and g.puppets[1].hp == 33, "two taking one floor at once: the host's monsters stand",
        tostring(h.puppets ~= nil) .. "/" .. tostring(g.puppets ~= nil))
  -- a Dark Cloud 2 room is for two: a third is told so, and no visit starts
  do
    local third = make_game("Donny", {game = "chronicle-two"})
    third.emit("game.title.opened", {})
    for i = 1, 5 do
      for _ = 1, 40 do
        if third.title.entries[i].label:sub(-1) == h.mod.state.code:sub(i, i) then break end
        third.emit("game.title.selected", {entry = "c" .. i})
      end
    end
    third.emit("game.title.selected", {entry = "join"})
    for _ = 1, 10 do h.tick(); g.tick(); third.tick() end
    check(third.started == nil, "a third player is not let into a Dark Cloud 2 room")
    check(tostring(third.mod.state.status):find("two players", 1, true), "and is told the room is for two", third.mod.state.status)
  end
  -- a third thing a joiner must not do: strike a host that leads with a blow of its own making
  local before = #h.strikes
  g.avatar_hits = {{avatar = 1, slot = 0, damage = 500, kind = 3, flags = 0}}
  both(h, g, 8)
  check(#h.strikes == before, "a game that does not run the floor lands no monster's blows on the other")
  h.keys.leave_key = true
  both(h, g, 2)
end

-- Two Dark Cloud 2 games in one room: the host, then the joiner in its visit. opts go to both games; g_opts to the
-- joiner's alone (its saves, say).
local function dc2_room(opts, g_opts)
  relay.rooms = {}
  local function with(extra)
    local o = {game = "chronicle-two"}
    for k, v in pairs(opts or {}) do o[k] = v end
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
  end
  local h = make_game("Max", with())
  local g = make_game("Monica", with(g_opts))
  h.keys.host_key = true
  both(h, g, 3)
  g.emit("game.title.opened", {})
  for i = 1, 5 do
    for _ = 1, 40 do
      if g.title.entries[i].label:sub(-1) == h.mod.state.code:sub(i, i) then break end
      g.emit("game.title.selected", {entry = "c" .. i})
    end
  end
  g.emit("game.title.selected", {entry = "join"})
  both(h, g, 8)
  return h, g
end
local function count_toasts(g, text)
  local n = 0
  for _, t in ipairs(g.toasts) do if t:find(text, 1, true) then n = n + 1 end end
  return n
end

print("Chronicle Two: what a player reads")
do
  local h, g = dc2_room({slots = {{slot = 5, ready = true, progress = 7, chapter = 5}}})
  check(g.started ~= nil, "(the joiner is in the host's world)")
  check(h.layers.coop == "CO-OP ABCDE  2 of 2", "the HUD counts a Dark Cloud 2 room's players out of two", h.layers.coop)
  -- Revive is L3 (V): R3 is the ridepod's in a Dark Cloud 2 dungeon, and R (R2) its first-person view
  check(h.binds.revive and h.binds.revive[1] == "V" and h.binds.revive[2] == "Gamepad:leftstick", "Revive is V or the left stick in Dark Cloud 2",
        h.binds.revive and table.concat(h.binds.revive, ","))
  do
    local one = make_game("Toan")
    check(one.binds.revive[1] == "R" and one.binds.revive[2] == "Gamepad:rightstick", "and R or the right stick in Dark Cloud, as before")
  end
  -- the Mod Manager: no buttons about a host's kept guests where joiners keep their own saves
  check(h.actions.guests == nil and h.actions.forget == nil, "with saves of their own there are no kept-guests buttons")
  check(h.actions.leave.description:find("own save", 1, true) ~= nil, "Leave says a joiner's things go into their own save", h.actions.leave.description)
  check(h.actions.resync.label == "Resync the floor", "and resync is with the other player, not only the host", h.actions.resync.label)
  do
    local older = make_game("Old", {game = "chronicle-two"})
    check(older.actions.guests ~= nil and older.actions.forget ~= nil, "an engine without saves of their own keeps the kept-guests buttons")
  end
  -- down: the toast names Dark Cloud 2's keys; the powder is the Resurrection Powder
  local FLOOR = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 91, map_no = 0, walking = true}
  g.settings.follow_offers, h.settings.follow_offers = false, false
  h.map, g.map = FLOOR, FLOOR
  h.player = {character = "max", hp = 40, max_hp = 60, position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  g.player = {character = "monica", hp = 30, max_hp = 45, position = {x = 30, y = 0, z = 0}, heading = 0, motion = 0}
  both(h, g, 60)
  g.player.down, g.player.hp = true, 0
  both(h, g, 30)
  check(count_toasts(h, "Monica is down! Stand beside them and hold Revive (V / left stick)") == 1, "the down toast names V and the left stick",
        h.last_toast())
  h.bag = {{id = "chronicle-two:item:resurrection-powder", name = "Resurrection Powder", count = 1}}
  h.keys.revive = true
  both(h, g, 4)
  check(g.player.down == false and find_toast(h, "you used a Resurrection Powder on Monica"), "and the powder used is called Resurrection Powder",
        h.last_toast())
  -- two building in one town: in Dark Cloud 2 the last change to a spot stands, not the last to leave
  h.map = {context = "georama", georama_town = 1, scene_map = 23, map_no = 23, editing = true}
  both(h, g, 31)
  g.map = {context = "georama", georama_town = 1, scene_map = 23, map_no = 23, editing = true}
  both(h, g, 31)
  check(find_toast(g, "the last change wins") and not find_toast(g, "last to leave"), "two builders are told the last change wins", g.last_toast())
  -- the host's town as the joiner hears it: by the host's name
  g.map = {context = "georama", georama_town = 1, scene_map = 23, map_no = 23, editing = false}
  h.map = {context = "georama", georama_town = 1, scene_map = 23, map_no = 23, editing = false}
  h.towns[1] = "DCT21:the host's mill"
  both(h, g, 31)
  check(g.towns[1] == "DCT21:the host's mill" and find_toast(g, "Max changed Balance Valley"), "a town the host built is told by the host's name",
        g.last_toast())
  -- a friend walking into a house on this player's street is no offer to walk anywhere
  g.settings.follow_offers = true
  g.map = {context = "georama", map_id = 23, town_map = 2, scene_map = 23, map_no = 23, map_title = "Balance Valley", walking = true}
  h.map = {context = "georama", map_id = 23, town_map = 2, scene_map = 23, house = 4, map_no = 23, map_title = "Gaffer's Shop", walking = true}
  both(h, g, 48)
  check(g.panel == nil, "no offer when the other walks into a house on this player's street", g.panel and g.panel.title)
  h.map = {context = "georama", map_id = 12, town_map = 1, scene_map = 12, house = 34, map_no = 10, map_title = "Max's House", walking = true}
  both(h, g, 48)
  check(g.panel == nil, "nor when they walk into a house in another town: only a dungeon floor is asked about", g.panel and g.panel.title)
  h.map = {context = "dungeon", dungeon_id = 1, floor_id = 3, floor_seed = 5, map_no = 23, walking = true}
  both(h, g, 48)
  check(g.panel and g.panel.title:find("went to", 1, true) ~= nil, "going onto a dungeon floor is asked about", g.panel and g.panel.title)
end

print("Chronicle Two: closing a room under a joiner with their own save")
do
  local SLOTS = {{slot = 5, ready = true, progress = 7, chapter = 5}}
  local h, g = dc2_room({}, {slots = SLOTS})
  check(g.started and g.started.player == "DCP2 own 5", "(the joiner brings File 6)")
  g.things = "DCP2 the very last things"
  local writes = #g.slot_writes
  h.keys.leave_key = true
  both(h, g, 6)
  check(#g.slot_writes > writes and g.slot_writes[#g.slot_writes].data == "DCP2 the very last things",
        "the host closing at once still tells the joiner, whose things go into their save first")
  check(find_toast(g, "the host closed the room; your things are in your save"), "and the joiner is told so", g.last_toast())
  check(not find_toast(h, "save your game"), "the host is not told to save for guests it keeps nothing of")
  -- the host's game gone without a word: the joiner's things still go into their save as the visit ends
  local h2, g2 = dc2_room({}, {slots = SLOTS})
  g2.things = "DCP2 after the host vanished"
  h2.net = nil -- (the host's game is simply gone: the relay says so)
  relay.rooms[g2.net.code] = nil
  g2.net_events[#g2.net_events + 1] = {kind = "closed", reason = "the host left"}
  both(h2, g2, 3)
  check(g2.slot_writes[#g2.slot_writes] and g2.slot_writes[#g2.slot_writes].data == "DCP2 after the host vanished",
        "a host that vanishes: the joiner's things go into their save before the visit ends")
  check(find_toast(g2, "the host's game left the room; your things are in your save"), "and the joiner is told they are there", g2.last_toast())
  -- the room closing under the host itself: nothing to save for joiners who keep their own things
  local h3, g3 = dc2_room({}, {slots = SLOTS})
  h3.net_events[#h3.net_events + 1] = {kind = "closed", reason = "the relay restarted"}
  both(h3, g3, 2)
  check(count_toasts(h3, "the room closed (the relay restarted)") == 1 and not find_toast(h3, "save your game"),
        "a host whose room closes is not told to save for joiners with their own saves", h3.last_toast())
end

print("Chronicle Two: a joiner's save is written only with its own things (M1)")
do
  relay.rooms = {}
  local h = make_game("Max", {game = "chronicle-two"})
  local g = make_game("Monica", {game = "chronicle-two", slots = {{slot = 5, ready = true, progress = 7, chapter = 5}}})
  h.keys.host_key = true
  both(h, g, 3)
  -- a host that drops the joiner's "OWN" (an older copy, or a stale greeting): it answers as for a new player
  setmetatable(h.mod.state.guest_own, {__newindex = function() end})
  g.emit("game.title.opened", {})
  for i = 1, 5 do
    for _ = 1, 40 do
      if g.title.entries[i].label:sub(-1) == h.mod.state.code:sub(i, i) then break end
      g.emit("game.title.selected", {entry = "c" .. i})
    end
  end
  g.emit("game.title.selected", {entry = "join"})
  both(h, g, 8)
  check(g.started ~= nil and g.started.player == nil, "(the host answered NEW: the visit starts with a new player's things)")
  check(g.mod.own.slot == nil, "then the joiner's own save is not the visit's to write")
  check(find_toast(g, "didn't take your save, so File 6 stays as it is"), "and the joiner is told why", g.last_toast())
  g.things = "DCP2" .. string.rep("q", 200) .. "a new player's things"
  both(h, g, 60 * 60 + 2)
  check(#g.slot_writes == 0, "a minute on, nothing has been written into File 6", #g.slot_writes)
  check(h.accounts[g.storage.me.id] and h.accounts[g.storage.me.id].data == g.things, "the things went to the host to keep, as in Dark Cloud")
end

print("Chronicle Two: the world's changes while a joiner's visit begins (M4)")
do
  relay.rooms = {}
  local h = make_game("Max", {game = "chronicle-two", shared = true})
  local g = make_game("Monica", {game = "chronicle-two", shared = true})
  h.keys.host_key = true
  both(h, g, 3)
  g.emit("game.title.opened", {})
  for i = 1, 5 do
    for _ = 1, 40 do
      if g.title.entries[i].label:sub(-1) == h.mod.state.code:sub(i, i) then break end
      g.emit("game.title.selected", {entry = "c" .. i})
    end
  end
  g.emit("game.title.selected", {entry = "join"})
  g.tick() -- the joiner says hello
  h.tick() -- the host sends its world, and counts the joiner in
  -- the host changes the world before the joiner's visit has begun
  h.emit("game.world.changed", {kind = "flag", id = 300, value = true})
  h.emit("game.world.changed", {kind = "counter", id = 7, value = 12})
  h.towns[2] = "DCT22:built while you loaded"
  h.emit("game.world.changed", {kind = "town", id = 2, value = 3})
  check(g.started == nil and #g.applied == 0, "(the joiner's visit has not begun yet)")
  both(h, g, 4)
  check(g.started ~= nil, "(now it has)")
  check(#g.applied == 2 and g.applied[1].kind == "flag" and g.applied[1].id == 300 and g.applied[2].kind == "counter" and g.applied[2].value == 12,
        "changes the host made while the visit began are kept and taken, in order", #g.applied)
  check(g.towns[2] == "DCT22:built while you loaded", "and so is a town the host built then", tostring(g.towns[2]))
end

print("Chronicle Two: one value changed by both at once (M6)")
do
  local h, g = dc2_room({shared = true})
  local function last_of(game, kind, id)
    for i = #game.applied, 1, -1 do local a = game.applied[i]; if a.kind == kind and a.id == id then return a end end
  end
  h.emit("game.world.changed", {kind = "flag", id = 50, value = true})
  g.emit("game.world.changed", {kind = "flag", id = 50, value = false})
  h.emit("game.world.changed", {kind = "counter", id = 9, value = 4})
  g.emit("game.world.changed", {kind = "counter", id = 9, value = 6})
  both(h, g, 6)
  check(last_of(h, "flag", 50) == nil and last_of(h, "counter", 9) == nil, "the host does not take a joiner's change that crossed its own")
  check(last_of(g, "flag", 50) and last_of(g, "flag", 50).value == true and last_of(g, "counter", 9).value == 4,
        "and the joiner ends with the host's values", tostring(last_of(g, "flag", 50) and last_of(g, "flag", 50).value))
  -- a moment later the joiner's change is the world's again
  both(h, g, 200)
  g.emit("game.world.changed", {kind = "flag", id = 50, value = false})
  both(h, g, 4)
  check(last_of(h, "flag", 50) and last_of(h, "flag", 50).value == false, "a joiner's change long after the host's is taken")
end

print("Chronicle Two: the swap, crossed")
do
  local h, g = dc2_room({heroes = true})
  -- backed out of: the asker hears no, rather than waiting on nothing
  g.emit("ui.action", {id = "swap"})
  both(h, g, 4)
  check(h.panel ~= nil, "(the host is asked)")
  h.choose(nil)
  both(h, g, 4)
  check(find_toast(g, "would rather not swap") and g.mod.heroes.asked == nil, "a panel backed out of answers no")
  -- both ask at once: one swap, never both playing one hero
  both(h, g, 700)
  h.emit("ui.action", {id = "swap"})
  g.emit("ui.action", {id = "swap"})
  both(h, g, 6)
  if h.panel then h.choose(1) end
  if g.panel then g.choose(1) end
  both(h, g, 6)
  check(h.room_hero ~= g.room_hero and h.room_hero == "monica", "two asking at once swap once, and play two heroes",
        tostring(h.room_hero) .. "/" .. tostring(g.room_hero))
  -- an answer to a question given up on: the room ends as the host has it
  both(h, g, 700)
  h.emit("ui.action", {id = "swap"})
  both(h, g, 4)
  check(g.panel ~= nil, "(the joiner is asked)")
  h.mod.heroes.asked = nil -- the host's question is long over
  g.choose(1)
  both(h, g, 6)
  check(h.room_hero ~= g.room_hero, "a late yes leaves the two games on two heroes", tostring(h.room_hero) .. "/" .. tostring(g.room_hero))
  check(find_toast(g, "as the room has it"), "and the joiner is told which hero it plays", g.last_toast())
end

print("Chronicle Two: out of step, either way round")
do
  local h, g = dc2_room({})
  h.settings.follow_offers, g.settings.follow_offers = false, false
  local FLOOR = {context = "dungeon", dungeon_id = 0, floor_id = 3, floor_seed = 91, map_no = 0, walking = true}
  local function rat(slot) return {slot = slot, kind = 3, state = 2, hp = 50, max_hp = 60, x = 10, y = 0, z = 0, heading = 0, motion = 0} end
  h.player = {character = "max", position = {x = 0, y = 0, z = 0}, heading = 0, motion = 0}
  g.player = {character = "monica", position = {x = 50, y = 0, z = 0}, heading = 0, motion = 0}
  -- the joiner runs the floor; the host, coming second, can't make two of its monsters
  g.map = FLOOR
  g.monsters = {rat(0), rat(1)}
  g.doors_out = {{script = 7, mode = 0, ext = 0, pos = {1, 2, 3}, dir = {0, 0, 1}}}
  both(h, g, 60)
  h.map = FLOOR
  h.refused = {0, 1}
  both(h, g, 400)
  check(h.panel and h.panel.title == "Out of step with Monica", "the host following the joiner's floor is offered to walk in again beside her",
        h.panel and h.panel.title)
  check(h.panel and h.panel.subtitle:find("of Monica's monsters", 1, true), "and told whose monsters are missing", h.panel and h.panel.subtitle)
  h.choose(2)
  h.refused = nil
  -- the host resyncs with the joiner: the floor's doors come again
  local runs = #h.doors_run
  h.mod.door.log, h.mod.door.done = {}, {}
  h.emit("ui.action", {id = "resync"})
  both(h, g, 12)
  check(find_toast(h, "asked Monica for this floor's open doors again"), "the host can resync with its joiner", h.last_toast())
  check(#h.doors_run > runs, "and the joiner sends the floor's doors", #h.doors_run - runs)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed > 0 and 1 or 0)
