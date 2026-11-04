-- Plays mods/moonmod.challenges/main.lua against a small fake Chronicle adapter: story boss phases and a whole Boss Rush.
-- Usage, from the repository root:  lua tools/tests/challenges/test_challenges.lua   (Lua 5.4 or newer)
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."
local MOD_DIR = root .. "/mods/moonmod.challenges"
local ID = "moonmod.challenges"

local defaults = {}
for line in io.lines(MOD_DIR .. "/mod.json") do
  local id = line:match('"id":%s*"([%w_]+)"')
  local default = line:match('"default":%s*([^,}]+)')
  local name = line:match('"name":%s*"([^"]*)"')
  assert(not (id and name) or #name <= 96, "setting " .. tostring(id) .. ": its name is over 96 bytes")
  if id and default then
    default = default:gsub("%s+$", "")
    if default == "true" then defaults[id] = true
    elseif default == "false" then defaults[id] = false
    elseif default:match('^"') then defaults[id] = default:match('^"(.*)"$')
    else defaults[id] = math.tointeger(tonumber(default)) or tonumber(default) end
  end
end

local passed, failed = 0, 0
local function check(cond, label, extra)
  if cond then passed = passed + 1; print("  ok   " .. label)
  else failed = failed + 1; print("  FAIL " .. label .. (extra ~= nil and ("  [" .. tostring(extra) .. "]") or "")) end
end
local function fail(code, msg) return nil, {code = code, message = msg} end
local function only(a, fields, what)
  for k in pairs(a) do assert(fields[k], what .. ": unknown field " .. tostring(k)) end
end
local function set(list) local t = {} for _, k in ipairs(list) do t[k] = true end return t end

local function boot(overrides, opts)
  opts = opts or {}
  local S = {settings = {}, handlers = {}, storage = opts.storage or {}, notices = {}, cards = {}, bars = {}, tints = {},
             monsters = {}, next_handle = 1, spawns = {}, context = opts.context or "title", session = nil,
             title = nil, choice = nil, formula = {}, max_hp = {}, healed = {}, given = {}, layout = nil,
             warden_room = false, modifiers = nil, dungeon_full = opts.dungeon_full or {}, finished = 0,
             party = opts.party or {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}}
  for k, v in pairs(defaults) do S.settings[k] = v end
  for k, v in pairs(overrides or {}) do S.settings[k] = v end
  S.registered_floor = nil
  _G.moonmod = {
    settings = {get = function(id) return S.settings[id] end},
    storage = {get = function(k) return S.storage[k] end, set = function(k, v) S.storage[k] = v end},
    on = function(name, fn) S.handlers[name] = S.handlers[name] or {}; table.insert(S.handlers[name], fn) end,
    log = function() end,
  }
  S.registered_playable = nil
  local function entity_list()
    local list = {}
    for _, m in ipairs(S.monsters) do
      if m.hp > 0 then
        list[#list + 1] = {entity_id = m.handle, native_model_id = m.model, revealed = true, position = {x = 0, y = 0, z = 0},
                           health = {current = m.hp, maximum = m.max}, combat = {defense = m.defense}}
      end
    end
    return list
  end
  local function find(handle) for _, m in ipairs(S.monsters) do if m.handle == handle then return m end end end
  _G.game = {
    dungeons = {
      register = function(a)
        only(a, set({"id", "name", "dungeon", "floors"}), "dungeons.register")
        assert(#a.floors >= 1 and #a.floors <= 8)
        if S.dungeon_full[a.dungeon] then return fail("failed", "the dungeon has 25 floors") end
        assert(a.floors[1].source_floor and a.floors[1].id)
        assert(a.dungeon == 0 or a.dungeon == 1 or a.dungeon == 4, "Challenges keeps out of the Shipwreck and the Temple")
        if a.id == "boss-rush" then
          S.registered_floor = {dungeon = a.dungeon, id = ID .. ":boss-rush/arena"}
          return {id = ID .. ":boss-rush", floors = {{id = S.registered_floor.id}}}
        end
        S.shaft_floors = S.shaft_floors or {}
        local f = {dungeon = a.dungeon, id = ID .. ":" .. a.id .. "/depth", native_floor_id = 20 + a.dungeon}
        table.insert(S.shaft_floors, f)
        return {id = ID .. ":" .. a.id, floors = {f}}
      end,
      floor_redirect = function(a)
        for k in pairs(a) do assert(k == "dungeon_id" or k == "floor_id" or k == "to_floor_id") end
        S.redirects = S.redirects or {}; S.redirects[a.dungeon_id .. ":" .. a.floor_id] = a.to_floor_id; return {}
      end,
      set_exits = function(a) S.exits = a.town; return {} end,
      get = function() return fail("not_found", "no") end,
      set_layout = function(a)
        if next(a) ~= nil then assert(a.rooms >= 2 and a.rooms <= 64 and a.area > a.room_max and a.room_min >= 3) end
        S.layout = a; return a
      end,
      set_modifiers = function(a)
        only(a, set({"rooms", "monsters", "chests", "chest_value"}), "set_modifiers")
        for _, v in pairs(a) do assert(v >= -100 and v <= 300) end
        S.modifiers = a; return a
      end,
      set_warden_room = function(a) only(a, set({"enabled", "lock_in"}), "set_warden_room"); S.warden_room = a.enabled; return a end,
    },
    characters = {
      register_playable = function(a)
        assert(a.id == "seda" and a.pack and #a.name <= 10 and a.fights_as == "toan")
        S.registered_playable = a; return {id = a.id, character_id = 7, count = 2}
      end,
      register = function(a)
        only(a, set({"id", "kind", "name", "template_monster_id"}), "characters.register")
        assert(a.kind == "enemy" and #a.name <= 30)
        return {id = ID .. ":" .. a.id, template = a.template_monster_id}
      end,
      spawn = function(a)
        only(a, set({"character", "position", "arena_origin", "grounded", "arena_slot"}), "characters.spawn")
        if S.spawn_refuse then S.spawn_refuse = S.spawn_refuse - 1; if S.spawn_refuse >= 0 then return fail("failed", "not ready") end end
        local model = tonumber(a.character:match("rush%-(%d+)$"))
        assert((a.arena_origin == nil) == (a.arena_slot == nil), "arena_slot goes with arena_origin")
        assert(a.arena_slot == nil or (a.arena_slot >= 0 and a.arena_slot <= 15), "arena spawn")
        local h = "e" .. S.next_handle; S.next_handle = S.next_handle + 1
        local m = {handle = h, model = model, hp = 1000, max = 1000, defense = 20, slot = a.arena_slot or -1}
        table.insert(S.monsters, m); table.insert(S.spawns, m)
        return {entity_handle = h, stats = {hp = 1000, defense = 20}}
      end,
    },
    entities = {
      query = function(a) assert(a.type == "monster"); if S.context ~= "dungeon" then return fail("failed", "no dungeon") end return {entities = entity_list()} end,
      get = function(h) local m = find(h); if not m then return {status = "expired"} end return {status = m.hp > 0 and "alive" or "dead"} end,
      set_stats = function(a)
        only(a, set({"entity", "hp", "max_hp", "defense", "damage_scale", "hit_share", "reward_money"}), "set_stats")
        local m = find(a.entity); if not m then return fail("expired", "gone") end
        if a.damage_scale then assert(a.damage_scale >= 0 and a.damage_scale <= 100); m.damage = a.damage_scale end
        if a.max_hp then assert(a.max_hp >= 1 and a.max_hp <= 1000000); m.max = a.max_hp end
        if a.hp then assert(a.hp <= m.max); m.hp = a.hp end
        if a.defense then m.defense = a.defense end
        if a.hit_share ~= nil then m.hit_share = a.hit_share end
        return {}
      end,
      tint = function(a) assert(a.frames <= 3600); S.tints[a.entity] = a.color; return {} end,
      scale_set = function(a) assert(a.scale >= 0.5 and a.scale <= 3); local m = find(a.entity); if m then m.scale = a.scale end return {} end,
    },
    effects = {burst = function(a) assert(a.kind == "smoke" and a.scale <= 4); return {} end},
    ui = {
      notify = function(a) assert(#a.message <= 200); table.insert(S.notices, a.message); return true end,
      boss_card = function(a)
        only(a, set({"name", "kicker", "epithet", "frames"}), "boss_card")
        assert(a.frames >= 30 and a.frames <= 600 and #a.name <= 40 and (not a.kicker or #a.kicker <= 48))
        table.insert(S.cards, a); return true
      end,
      run_menu_set = function(a)
        assert(a.title and #a.tabs >= 1 and #a.tabs <= 6)
        for _, t in ipairs(a.tabs) do assert(t.rows == nil or #t.rows > 0, "an empty rows table reaches the engine as an object") end
        S.run_menu = a; return {}
      end,
      run_menu_close = function() return {} end,
      run_menu_clear = function() S.run_menu = nil; return {} end,
      choice_open = function(a)
        assert(#a.options >= 1 and #a.options <= 4)
        S.choice = a; return true
      end,
    },
    render = {
      bar_register = function(a)
        only(a, set({"id", "label", "current", "max"}), "bar_register")
        assert(#a.label >= 1 and #a.label <= 24 and a.max > 0 and a.current >= 0 and a.current <= a.max)
        S.bars[a.id] = a; return {}
      end,
      bar_remove = function(a) S.bars[a.id] = nil; return {} end,
    },
    title = {
      mode_register = function(a) assert(a.id and #a.label <= 32); S.title = a; return {} end,
      mode_set = function(a)
        for _, l in ipairs(a.lines or {}) do assert(#l <= 64, "title line over 64 bytes: " .. l) end
        assert(not a.lines or #a.lines <= 6)
        for k, v in pairs(a) do S.title[k] = v end; return {}
      end,
    },
    session = {
      start = function(a)
        only(a, set({"floor", "party_size", "character"}), "session.start")
        S.started = a; return {queued = true}
      end,
      get = function() return S.session and {kind = "sandbox", owner = S.session} or {kind = "story"} end,
      finish = function() S.finished = S.finished + 1; return {} end,
    },
    party = {list = function() local l = {} for i, c in ipairs(S.party) do l[i] = {id = c} end return l end,
             set_active = function(a) S.active_hero = a.id; return {} end},
    resources = {override = function(a)
      assert(a.path and a.game_path)
      if not S.seda_pack then return fail("not_found", "no such package file") end
      return {game_path = a.game_path}
    end},
    player = {
      set = function(a)
        local n = 0 for k in pairs(a) do if k ~= "character" then n = n + 1 end end
        assert(n == 1); if a.max_hp then assert(a.max_hp >= 1 and a.max_hp <= 999); S.max_hp[a.character] = a.max_hp end
        return {}
      end,
      heal = function(a) assert(a.amount >= 1 and a.amount <= 32767); S.healed[a.character] = (S.healed[a.character] or 0) + a.amount; return {} end,
      get = function() return {character = "toan", weapon = {id = "w", slot = 0, durability = 3, durability_max = 30}} end,
      tuning_set = function(t)
        for k, v in pairs(t) do
          assert(k == "thirst_drain" or k == "durability_wear" or k == "map_hidden", "tuning field " .. k)
          if type(v) == "number" then assert(v >= 0.25 and v <= 4, k) end
        end
        S.tuning = t; return {}
      end,
      tuning_clear = function() S.tuning = nil; return {} end,
    },
    weapons = {durability_set = function(a) S.mended = a.durability; return {} end},
    items = {give = function(a) S.given[a.id] = (S.given[a.id] or 0) + a.count; return {} end},
    combat = {register_formula = function(a)
      only(a, set({"id", "operation", "value", "priority"}), "register_formula")
      assert(a.value >= 0 and a.value <= 100); S.formula[a.id] = a.value; return {}
    end},
    world = {dungeon_npc_set = function(a) S.npc = a.id; return {} end, dungeon_npc_clear = function() S.npc = nil; return {} end,
             transition = function(a) S.transitions = S.transitions or {}; table.insert(S.transitions, a.id); return {queued = true} end,
             get = function() return {context = S.context, dungeon_id = 0, floor_id = S.floor or 20, floor_seed = 1} end},
  }
  assert(loadfile(MOD_DIR .. "/main.lua"))()
  function S.emit(name, ...) for _, fn in ipairs(S.handlers[name] or {}) do fn(...) end end
  function S.tick(n) for _ = 1, n or 1 do S.emit("game.tick") end end
  function S.boss() for i = #S.monsters, 1, -1 do if S.monsters[i].slot == 0 and S.monsters[i].hp > 0 then return S.monsters[i] end end end
  return S
end

print("Story boss phases")
local S = boot(nil, {context = "dungeon"})
S.monsters = {{handle = "d1", model = 78, hp = 737, max = 737, defense = 30}, {handle = "m1", model = 3, hp = 50, max = 50}}
S.tick(10)
check(#S.cards == 1 and S.cards[1].name == "Dran", "Dran in sight: his name card")
check(S.bars.boss and S.bars.boss.label == "DRAN" and S.bars.boss.current == 737, "and his HP bar")
S.monsters[1].hp = 360; S.tick(10)
check(math.abs((S.monsters[1].damage or 0) - 1.4) < 1e-9 and S.monsters[1].defense == 36, "below half: enraged, hits 40% harder, defense +20%")
check(S.tints.d1 and S.tints.d1.r == 255 and S.monsters[1].scale and S.monsters[1].scale > 0.65, "glows red and grows")
check(S.notices[1] == "Dran is enraged!", "with a notice", S.notices[1])
S.tick(30)
check(#S.notices == 1 and #S.cards == 1, "once")
S.monsters[1].hp = 100; S.tick(10)
check(math.abs(S.monsters[1].damage - 1.82) < 1e-9 and S.tints.d1.b == 255, "below a fifth: desperate, purple")
S.monsters[1].hp = 0; S.tick(10)
check(S.bars.boss == nil, "the bar goes when he falls")
S.monsters = {{handle = "x", model = 3, hp = 50, max = 50}}; S.tick(10)
check(#S.cards == 1 and S.bars.boss == nil, "an ordinary monster gets nothing")

S = boot({phases = false, boss_card = false}, {context = "dungeon"})
S.monsters = {{handle = "u", model = 79, hp = 100, max = 1000}}; S.tick(10)
check(#S.cards == 0 and S.monsters[1].damage == nil and S.bars.boss, "phases and card off: only the bar")

S = boot(nil, {context = "dungeon"})
S.session = "moonmod.roguelike"; S.emit("game.session.started", {owner = "moonmod.roguelike"})
S.monsters = {{handle = "w", model = 80, hp = 100, max = 1000}}; S.tick(20)
check(#S.cards == 0 and S.bars.boss == nil and S.monsters[1].damage == nil, "a Gauntlet Warden is the Gauntlet's own")

print("Boss Rush: the arena and the title page")
S = boot()
check(S.registered_floor and S.registered_floor.dungeon == 0, "the arena floor is registered in the Divine Beast Cave")
S = boot(nil, {dungeon_full = {[0] = true, [1] = true}})
check(S.registered_floor and S.registered_floor.dungeon == 4, "a full Divine Beast Cave passes it on to the Moon Sea")
check(S.title and S.title.label == "Challenges" and S.title.entries[1].id == "boss_rush" and S.title.entries[1].enabled, "the Challenges row with Boss Rush")
S.emit("game.title.opened")
S.emit("game.title.selected", {entry = "boss_rush"})
check(S.title.title == "BOSS RUSH" and S.title.root == false and S.title.entries[1].id == "rush_start", "the Boss Rush page")
S.emit("game.title.selected", {entry = "back"})
check(S.title.title == "CHALLENGES" and S.title.root == true, "Circle goes back")

print("Boss Rush: a whole run")
S = boot()
S.emit("game.title.selected", {entry = "boss_rush"}); S.emit("game.title.selected", {entry = "rush_start"})
check(S.started and S.started.floor == ID .. ":boss-rush/arena" and S.started.party_size == 6 and S.started.character == "toan", "Begin starts a session on the arena with everyone")
check(S.layout and S.layout.rooms == 3, "a small floor")
check(S.storage.records.runs == 1, "the run is counted")
S.session = ID; S.emit("game.session.started", {owner = ID, mode = "challenges"})
S.context = "dungeon"
check(S.max_hp.toan == 120 and S.max_hp.osmond == 120 and S.formula.rush_power == 1.5, "the party at Dran's place in the story")
S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 20})
check(S.warden_room == true and S.modifiers.chests == -100, "an arena: a Warden room and no chests")
S.tick(100)
check(#S.spawns == 0, "nothing comes before the party walks in")
S.emit("game.dungeon.warden_room", {state = "entered", center = {x = 800, y = 0, z = 640}})
S.spawn_refuse = 1
S.tick(60)
check(#S.spawns == 0, "a spawn the floor can't take yet is tried again")
S.tick(2)
local dran = S.boss()
check(dran and dran.model == 78 and dran.hit_share == true and dran.scale == 0.65, "Dran rises in the arena, every hero can hurt him")
check(S.cards[#S.cards].kicker == "BOSS RUSH  1 OF 7" and S.cards[#S.cards].name == "Dran", "with the run's card")
S.tick(10)
check(#S.cards == 1, "the phase watcher doesn't card him twice")
dran.hp = 0; S.tick(1)
check(S.choice and S.choice.id == "rush_boon" and #S.choice.options == 3, "he falls: a boon to choose")
S.emit("ui.choice_made", {id = "rush_boon", index = 2})
check(math.abs(S.formula.rush_power - 2.6 * 1.15) < 1e-9 and S.max_hp.toan == 170, "Whet: +15% on top of Master Utan's tier")
S.tick(121)
local utan = S.boss()
check(utan and utan.model == 79, "Master Utan rises")
utan.hp = 0; S.tick(1)
S.emit("ui.choice_made", {id = "rush_boon", index = 3})
check(S.given["chronicle:item:148"] == 2 and S.given["chronicle:item:177"] == 1, "Supplies: Bread and a Repair Powder")
local before = #S.spawns
S.tick(121)
check(S.boss().model == 80 and #S.spawns - before == 9, "the Ice Queen comes with her eight helpers")
local queen_helpers = 0
for i = before + 1, #S.spawns do if S.spawns[i].slot > 0 and S.spawns[i].hit_share then queen_helpers = queen_helpers + 1 end end
check(queen_helpers == 8, "in their own slots, all hurtable")
for _, model in ipairs({80, 81, 83}) do
  local b = S.boss(); check(b and b.model == model, "boss " .. model .. " fights")
  b.hp = 0; S.tick(1)
  S.emit("ui.choice_made", {id = "rush_boon", index = 1}); S.tick(121)
end
check(S.mended == 30, "Mend mends the weapon")
local pink = S.boss()
check(pink and pink.model == 84 and pink.max == 200, "the pink Genie, his life brought to the others' footing")
pink.hp = 0; S.tick(1)
check(S.choice.subtitle:find("4 of 7") == nil and S.notices[#S.notices]:find("darkness itself"), "no rest before his true form")
S.tick(151)
local dark = S.boss()
check(dark and dark.model == 106 and dark.max == 100, "the dark Genie rises where he fell")
dark.hp = 0; S.tick(1)
check(S.cards[#S.cards].kicker == "BOSS RUSH CLEARED", "the last falls: cleared, with the time")
check(S.storage.records.clears == 1 and S.storage.records.best and S.storage.records.furthest == 7, "the clear and the best time are kept")
S.tick(331)
check(S.finished == 1, "the session finishes")
S.session = nil; S.emit("game.session.ended", {owner = ID, reason = "ended"})
check(S.warden_room == false and next(S.layout) == nil and S.formula.rush_power == 1 and next(S.modifiers) == nil, "everything is put back")

print("Boss Rush: a defeat")
local kept = S.storage
S = boot({rush_party = "Toan alone"}, {storage = kept})
S.emit("game.title.selected", {entry = "boss_rush"}); S.emit("game.title.selected", {entry = "rush_start"})
check(S.started.party_size == 1, "Toan alone")
S.session = ID; S.emit("game.session.started", {owner = ID}); S.context = "dungeon"
S.emit("game.dungeon.warden_room", {state = "entered", center = {x = 0, y = 0, z = 0}}); S.tick(61)
S.boss().hp = 0; S.tick(1); S.emit("ui.choice_made", {id = "rush_boon", index = 1}); S.tick(121)
S.session = nil; S.emit("game.session.ended", {owner = ID, reason = "defeat"})
check(S.storage.records.runs == 2 and S.storage.records.clears == 1 and S.storage.records.furthest == 7, "a defeat keeps the records")
S.emit("game.title.opened"); S.emit("game.title.selected", {entry = "boss_rush"})
local found = false
for _, l in ipairs(S.title.lines) do if l:find("Best time") then found = true end end
check(found, "the page shows the best time")


print("The Shaft")
S = boot()
check(#S.shaft_floors == 3 and S.shaft_floors[1].dungeon == 0 and S.shaft_floors[2].dungeon == 1 and S.shaft_floors[3].dungeon == 4,
      "one floor each in the Cave, the Forest and the Moon Sea")
check(S.redirects["0:20"] == 20 and S.redirects["1:21"] == 21, "each floor's gate leads back to itself")
S.emit("game.title.opened")
check(S.title.entries[2].id == "shaft" and S.title.entries[2].enabled, "the Challenges page lists the Shaft")
S.emit("game.title.selected", {entry = "shaft"})
check(S.title.title == "THE SHAFT" and S.title.entries[1].id == "shaft_start", "its page")
S.emit("game.title.selected", {entry = "shaft_start"})
check(S.started.floor == S.shaft_floors[1].id and S.started.party_size == 6, "Descend starts on the Cave's floor")
S.session = ID; S.emit("game.session.started", {owner = ID}); S.context = "dungeon"
check(S.exits == "shrines" and S.tuning and S.formula.shaft_power == 1, "the gate only leads down; no escape to town")
local function floor_n(dungeon)
  S.floor = (S.floor or 0) + 1
  S.emit("game.dungeon.generating", {dungeon_id = dungeon or 0, floor_id = 20})
end
floor_n()
check(S.run_menu and S.run_menu.tabs[1].lines[1]:find("Floor 1, stratum 1"), "the run menu shows the floor")
S.monsters = {{handle = "a", model = 3, hp = 100, max = 100, defense = 10}, {handle = "b", model = 1, hp = 200, max = 200, defense = 10}}
S.tick(20)
check(S.monsters[1].max == 100 and S.monsters[1].damage == 1, "floor 1: monsters as they are")
for _ = 2, 9 do floor_n() end
S.monsters = {{handle = "c", model = 3, hp = 100, max = 100, defense = 10}, {handle = "d", model = 1, hp = 200, max = 200, defense = 10}}
S.tick(20)
check(S.monsters[1].max == 220 and math.abs(S.monsters[1].damage - 1.48) < 1e-9 and S.monsters[1].defense == 18, "floor 9: more life, harder hits, more defense", S.monsters[1].max)
check(S.formula.shaft_power and math.abs(S.formula.shaft_power - 1.8) < 1e-9 and S.max_hp.toan == 148, "and the party grows too")
check(S.storage.records.shaft_deepest == 9, "the deepest floor is kept as you go")
floor_n()
check(S.warden_room == true, "floor 10 is a guardian's: its room is sealed")
S.monsters = {{handle = "e", model = 3, hp = 100, max = 100, defense = 10}, {handle = "f", model = 1, hp = 200, max = 200, defense = 10}}
S.tick(20)
S.emit("game.dungeon.warden_room", {state = "entered", center = {x = 1, y = 0, z = 2}})
S.tick(1)
local guardian = S.spawns[#S.spawns]
check(guardian and guardian.model == 1 and guardian.scale == 1.8 and math.abs(guardian.max - 2820) <= 1, "the floor's toughest monster waits inside, grown huge", guardian and guardian.max)
check(S.cards[#S.cards].name == "Guardian of the Stratum", "with a card")
guardian.hp = 0; S.tick(1)
check(S.choice and S.choice.id == "shaft_pact" and #S.choice.options == 3, "felled: three pacts to choose from")
local chosen = S.choice.options[1].title
S.emit("ui.choice_made", {id = "shaft_pact", index = 1})
S.tick(61)
check(S.transitions and S.transitions[1] == S.shaft_floors[2].id, "then down to the Forest's stratum")
floor_n(1)
check(S.run_menu.tabs[1].lines[1]:find("Floor 11, stratum 2: Wise Owl Forest") and S.run_menu.tabs[1].lines[2]:find(chosen), "the menu shows the stratum and the pact", S.run_menu.tabs[1].lines[2])
check(S.warden_room == false, "an ordinary floor again")
S.emit("ui.run_menu_action", {tab = "descent", row = "end"})
S.tick(11)
check(S.finished == 1, "End the descent finishes the session")
S.session = nil; S.emit("game.session.ended", {owner = ID, reason = "ended"})
check(S.storage.records.shaft_deepest == 11 and S.tuning == nil and S.exits == nil and S.run_menu == nil and S.formula.shaft_power == 1,
      "the record is kept and everything is put back")


print("Seda's Chronicle")
S = boot()
S.emit("game.title.opened")
check(S.title.entries[3].id == "seda" and S.title.entries[3].enabled, "the Challenges page lists Seda's Chronicle")
S.emit("game.title.selected", {entry = "seda"})
check(S.title.title == "SEDA'S CHRONICLE" and S.title.entries[1].id == "seda_start", "its page")
S.emit("game.title.selected", {entry = "seda_start"})
check(S.started.floor == S.shaft_floors[1].id and S.started.party_size == 1 and S.registered_playable == nil, "no pack: Toan alone starts in the cave")
S.session = ID; S.emit("game.session.started", {owner = ID}); S.context = "dungeon"
check(S.cards[#S.cards].kicker == "CHAPTER I" and S.formula.seda_power == 3 and S.max_hp.toan == 220, "Chapter I's card, and a veteran's strength")
S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 20})
check(S.npc == "wanderer", "a wanderer stands by the exit gate")
S.tick(161)
check(S.choice and S.choice.id == "seda_story" and S.choice.options[1].title == "Begin", "the chapter's story page")
S.emit("ui.choice_made", {id = "seda_story", index = 1})
for _ = 1, 11 do S.emit("game.enemy_defeated", {}) end
check(S.run_menu.tabs[1].lines[2]:find("11 of 12"), "the run menu counts the task", S.run_menu.tabs[1].lines[2])
S.emit("game.enemy_defeated", {})
check(S.choice.title == "CHAPTER I ENDS", "twelve felled: the chapter ends")
S.emit("ui.choice_made", {id = "seda_story", index = 1})
S.tick(31)
check(S.transitions and S.transitions[#S.transitions] == S.shaft_floors[2].id, "on to the forest")
S.emit("game.dungeon.generating", {dungeon_id = 1, floor_id = 21})
check(S.cards[#S.cards].kicker == "CHAPTER II" and S.modifiers.chests == 60, "Chapter II opens on its floor, with more chests")
S.tick(161); S.emit("ui.choice_made", {id = "seda_story", index = 1})
for chest = 1, 3 do S.emit("game.chest.opened", {chest = chest, item_id = 148}) end
check(S.choice.title == "CHAPTER II ENDS", "three relics found")
S.emit("ui.choice_made", {id = "seda_story", index = 1}); S.tick(31)
check(S.transitions[#S.transitions] == S.shaft_floors[3].id, "on to the Moon Sea")
S.emit("game.dungeon.generating", {dungeon_id = 4, floor_id = 24})
check(S.warden_room == true and S.cards[#S.cards].kicker == "CHAPTER III", "Chapter III: a sealed room")
S.tick(161); S.emit("ui.choice_made", {id = "seda_story", index = 1})
S.monsters = {{handle = "s1", model = 30, hp = 300, max = 300, defense = 10}, {handle = "s2", model = 31, hp = 500, max = 500, defense = 10}}
S.tick(20)
S.monsters = {}
S.emit("game.dungeon.warden_room", {state = "entered", center = {x = 5, y = 0, z = 5}})
S.tick(1)
local gate = S.spawns[#S.spawns]
check(gate and gate.model == 31 and gate.max == 4000 and gate.scale == 1.9, "the gate's guardian rises from the toughest monster")
gate.hp = 0; S.tick(1)
check(S.choice.title == "CHAPTER III ENDS", "it falls: the chapter ends")
S.emit("ui.choice_made", {id = "seda_story", index = 1}); S.tick(31)
check(S.transitions[#S.transitions] == ID .. ":boss-rush/arena", "on to the Genie's lair, in the arena")
S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 15})
check(S.modifiers.chests == -100 and S.warden_room == true and S.cards[#S.cards].kicker == "CHAPTER IV", "Chapter IV")
S.tick(161); S.emit("ui.choice_made", {id = "seda_story", index = 1})
local before = #S.spawns
S.emit("game.dungeon.warden_room", {state = "entered", center = {x = 9, y = 0, z = 9}})
S.tick(1)
local pink = S.boss()
check(pink and pink.model == 84 and #S.spawns - before == 8, "the pink Genie with his seven helpers")
pink.hp = 0; S.tick(1)
check(S.notices[#S.notices]:find("darkness itself"), "his body bursts")
S.tick(151)
local dark = S.boss()
check(dark and dark.model == 106, "and his true form rises")
dark.hp = 0; S.tick(1)
check(S.choice.title == "EPILOGUE", "the epilogue")
for _ = 1, 4 do S.emit("ui.choice_made", {id = "seda_story", index = 1}) end
check(S.cards[#S.cards].name == "The End" and S.storage.records.seda_clears == 1 and S.storage.records.seda_chapter == 4, "the end, kept in the records")
S.tick(261)
check(S.finished == 1, "back to the title")
S.session = nil; S.emit("game.session.ended", {owner = ID, reason = "ended"})
check(S.npc == nil and S.exits == nil and S.formula.seda_power == 1 and S.warden_room == false, "everything put back")

print("Seda's Chronicle with Seda's pack")
S = boot()
S.seda_pack = true
S.emit("game.title.selected", {entry = "seda"}); S.emit("game.title.selected", {entry = "seda_start"})
check(S.registered_playable and S.registered_playable.pack == "dun/mainchara/c08d.chr", "Seda registers as the Chronicle starts")
check(S.started.party_size == 8, "the party reaches his place")
S.session = ID; S.emit("game.session.started", {owner = ID})
check(S.active_hero == "seda", "and Seda takes the field")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
