-- Plays mods/moonmod.living-towns/main.lua against a small fake Chronicle adapter.
-- Usage, from the repository root:  lua tools/tests/living-towns/test_living_towns.lua   (Lua 5.4 or newer)
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."
local MOD_DIR = root .. "/mods/moonmod.living-towns"

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

local function boot(overrides, opts)
  opts = opts or {}
  local S = {settings = {}, handlers = {}, storage = opts.storage or {}, notices = {}, gilda = 0, bag = {}, npc = nil,
             day = opts.day or 1, context = "georama", dungeon = 0, reached = opts.reached or {[0] = 4},
             shops = {}, added = {}, session = opts.session}
  for k, v in pairs(defaults) do S.settings[k] = v end
  for k, v in pairs(overrides or {}) do S.settings[k] = v end
  for shop = 0, 17 do
    S.shops[shop] = shop % 3 == 0 and {148, 146, 151, 177} or {258, 259, 260}
  end
  _G.moonmod = {
    settings = {get = function(id) return S.settings[id] end},
    storage = {get = function(k) return S.storage[k] end, set = function(k, v) S.storage[k] = v end},
    on = function(name, fn) S.handlers[name] = S.handlers[name] or {}; table.insert(S.handlers[name], fn) end,
    log = function() end,
  }
  local function item_no(id) return tonumber(tostring(id):match("(%d+)$")) end
  _G.game = {
    save = {slot_id = function() return {slot_id = 1, slot_generation = 3} end},
    player = {get = function() return {character = "toan"} end},
    session = {get = function() return {kind = S.session and "sandbox" or "story"} end},
    world = {
      get = function() return {context = S.context, day = S.day, dungeon_id = S.context == "dungeon" and S.dungeon or nil,
                               floor_id = S.context == "dungeon" and 1 or nil} end,
      dungeon_npc_set = function(a) assert(a.id and a.model and (a.place == "exit" or a.place == "player")); S.npc = a.id; return {} end,
    },
    dungeons = {list = function()
      local out = {}
      for id = 0, 6 do out[#out + 1] = {id = "d" .. id, native_id = id, deepest_floor_reached = S.reached[id] or 0} end
      return out
    end},
    shops = {
      get = function(a) local items = {} for i, no in ipairs(S.shops[a.shop_no]) do items[i] = {item_no = no} end return {items = items} end,
      register_item = function(a)
        assert(a.shop_no and a.item_id)
        if #S.shops[a.shop_no] >= 20 then return fail("failed", "full") end
        table.insert(S.shops[a.shop_no], a.item_id); S.added[#S.added + 1] = a; return {}
      end,
    },
    economy = {add = function(a) assert(a.amount > 0); S.gilda = S.gilda + a.amount; return {} end},
    items = {
      give = function(a) local no = item_no(a.id); S.bag[no] = (S.bag[no] or 0) + a.count; return {} end,
      remove = function(a)
        local no = item_no(a.id); local have = S.bag[no] or 0; local n = math.min(have, a.count)
        S.bag[no] = have - n; return {removed = n}
      end,
    },
    ui = {notify = function(a) assert(#a.message <= 200); S.notices[#S.notices + 1] = a.message; return true end,
          register = function() return {} end},
  }
  assert(loadfile(MOD_DIR .. "/main.lua"))()
  function S.emit(name, ...) for _, fn in ipairs(S.handlers[name] or {}) do fn(...) end end
  function S.tick(n) for _ = 1, n or 1 do S.emit("game.tick") end end
  function S.board() return S.storage.slots["1:3"].board end
  function S.find(kind) for _, b in ipairs(S.board()) do if b.kind == kind then return b end end end
  return S
end

-- a board with every kind on it: try days until one comes up
local function board_with(kinds, reached)
  for day = 1, 400 do
    local S = boot(nil, {day = day, reached = reached})
    S.tick(60)
    local have = {}
    for _, b in ipairs(S.board()) do have[b.kind] = true end
    local ok = true
    for _, k in ipairs(kinds) do ok = ok and have[k] end
    if ok then return S end
  end
end

print("The board")
local S = boot(nil, {reached = {}})
S.tick(60)
check(#S.board() == 0, "before any dungeon is reached, nobody asks")
S = boot()
S.tick(60)
check(#S.board() == 3 and S.notices[#S.notices]:find("New bounties"), "a dungeon reached: three bounties, announced")
local all_cave = true
for _, b in ipairs(S.board()) do all_cave = all_cave and b.dungeon == 0 and b.asker:find("Norune") ~= nil end
check(all_cave, "all in the Divine Beast Cave, asked by Norune's villagers")
local first = S.board()[1].id .. S.board()[1].kind
S.tick(120)
check(S.board()[1].id .. S.board()[1].kind == first, "the same board all day")
S.day = 2; S.tick(60)
check(S.board()[1].id:find("^2:"), "a new board the next day")
local S2 = boot(nil, {storage = {slots = {["1:3"] = {board = {}, day = -1, seed = 5}}}})
S2.tick(60)
local S3 = boot(nil, {storage = {slots = {["1:3"] = {board = {}, day = -1, seed = 5}}}})
S3.tick(60)
check(S2.board()[1].kind == S3.board()[1].kind and S2.board()[1].need == S3.board()[1].need, "a save's board for a day is always the same")
S = boot({bounty_count = 1}); S.tick(60)
check(#S.board() == 1, "Bounties a day: one")

print("Hunts and chests")
S = board_with({"hunt", "chests"})
check(S ~= nil, "a board with a hunt and a chests bounty")
local hunt, chests = S.find("hunt"), S.find("chests")
S.context = "dungeon"; S.dungeon = 0
for _ = 1, hunt.need - 1 do S.emit("game.enemy_defeated", {}) end
check(not S.find("hunt").done and S.find("hunt").have == hunt.need - 1, "hunt: each kill in the cave counts")
S.dungeon = 1; S.emit("game.enemy_defeated", {})
check(not S.find("hunt").done, "kills in another dungeon don't")
S.dungeon = 0; S.emit("game.enemy_defeated", {})
check(S.find("hunt").done and S.notices[#S.notices]:find("done"), "the last kill: done")
for c = 1, chests.need do S.emit("game.chest.opened", {chest = c}) end
check(S.find("chests").done, "chests: opened in the cave")

print("The villager")
S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2})
check(S.npc == "bounty", "a villager stands by the exit gate on the bounty's floors")
local before = S.gilda
S.emit("game.dungeon_npc.near", {id = "bounty"})
check(S.gilda > before and S.find("hunt").claimed and S.find("chests").claimed, "walking up to him pays the bounties done")
local paid = S.gilda
S.emit("game.dungeon_npc.near", {id = "bounty"})
check(S.gilda == paid, "once")

print("Deeper")
S = board_with({"deeper"})
local deeper = S.find("deeper")
check(deeper.need >= 5, "deeper asks past your deepest floor (4)", deeper.need)
S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = deeper.need - 2})
check(not S.find("deeper").done, "a floor short of it: not yet")
S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = deeper.need - 1})
check(S.find("deeper").done, "that floor: done")
S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 0, back_floor = true})
S.emit("ui.action", {id = "hand_in"})
check(S.find("deeper").claimed, "collected at the board too")

print("Fetch")
S = board_with({"fetch"})
local fetch = S.find("fetch")
S.bag[fetch.item] = fetch.need - 1
S.emit("ui.action", {id = "hand_in"})
check(not S.find("fetch").done and S.bag[fetch.item] == fetch.need - 1, "too few: nothing taken")
S.bag[fetch.item] = fetch.need + 2
S.emit("ui.action", {id = "hand_in"})
check(S.find("fetch").claimed and S.bag[fetch.item] == 2, "enough: taken and paid")
S.emit("ui.action", {id = "board"})
check(S.notices[#S.notices] ~= nil, "the board action shows what is left")

print("Stores")
S = boot(nil, {reached = {[0] = 15, [1] = 17, [2] = 3}})
S.tick(60)
local general, weapon_shop = 0, 0
for _, a in ipairs(S.added) do if a.shop_no % 3 == 0 then general = general + 1 else weapon_shop = weapon_shop + 1 end end
check(general > 0 and weapon_shop == 0, "the general stores gain goods; the weapon shops don't")
local has = {}
for _, no in ipairs(S.shops[0]) do has[no] = true end
check(has[147] and has[149] and has[81] and not has[154], "three dungeons reached: the Forest's and the Shipwreck's goods, not the Temple's")
local count = #S.added
S.day = 2; S.tick(60)
check(#S.added == count, "nothing is added twice")
S = boot({stock = false}, {reached = {[0] = 15, [1] = 17, [2] = 3}}); S.tick(60)
check(#S.added == 0, "Stores setting off: no new goods")

print("Sandbox sessions")
S = boot(nil, {session = true}); S.tick(60)
check(S.storage.slots == nil, "a challenge run gets no board")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
