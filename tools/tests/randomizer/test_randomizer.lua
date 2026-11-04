-- Plays mods/moonmod.randomizer/main.lua against a small fake Chronicle adapter.
-- Usage, from the repository root:  lua tools/tests/randomizer/test_randomizer.lua   (Lua 5.4 or newer)
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."
local MOD_DIR = root .. "/mods/moonmod.randomizer"

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

-- The retail shops: each a short list of goods and a few weapons.
local function retail_shops()
  local shops = {}
  for shop = 0, 17 do
    local list = {}
    for i = 1, 6 do list[i] = 145 + (shop + i) % 10 end
    if shop % 3 == 0 then list[#list + 1] = 258 + shop end
    shops[shop] = list
  end
  return shops
end

local function boot(overrides, opts)
  opts = opts or {}
  local S = {settings = {}, handlers = {}, storage = opts.storage or {}, notices = {}, shops = retail_shops(), defs = {},
             drops = {}, seeds = {}, bag = {[148] = 1, [95] = 1, [222] = 1}, slot = opts.slot, date = opts.date,
             shops_held = opts.shops_held, weapons_held = opts.weapons_held, session = opts.session}
  for k, v in pairs(defaults) do S.settings[k] = v end
  for k, v in pairs(overrides or {}) do S.settings[k] = v end
  for no = 258, 376 do S.defs[no] = {attack = 10 + no % 50, endurance = 20, speed = 30, magic = 5, durability = 40, attack_max = 60 + no % 50} end
  for id = 0, 160 do S.drops[id] = {rare_item = id % 4 == 0 and -1 or 150, steal_item = id % 5 == 0 and -1 or 151} end
  _G.moonmod = {
    settings = {get = function(id) return S.settings[id] end},
    storage = {get = function(k) return S.storage[k] end, set = function(k, v) S.storage[k] = v end},
    on = function(name, fn) S.handlers[name] = S.handlers[name] or {}; table.insert(S.handlers[name], fn) end,
    log = function() end,
  }
  local function item_no(id) return tonumber(tostring(id):match("^chronicle:item:(%d+)$")) end
  _G.game = {
    info = {get = function() return {id = "chronicle", date = S.date} end},
    save = {slot_id = function() if S.slot then return {slot_id = S.slot, slot_generation = 7} end return {} end},
    player = {get = function() return {character = "toan"} end},
    session = {get = function() return {kind = S.session and "sandbox" or "story"} end},
    shops = {
      get = function(a)
        assert(a.shop_no >= 0 and a.shop_no <= 17)
        local items = {}
        for i, no in ipairs(S.shops[a.shop_no]) do items[i] = {item_no = no} end
        return {items = items}
      end,
      set_items = function(a)
        if S.shops_held then return fail("failed", "another mod holds this shop") end
        assert(#a.items >= 1 and #a.items <= 20)
        S.shops[a.shop_no] = a.items; return {}
      end,
    },
    weapons = {
      get = function(id)
        local no = tonumber(tostring(id):match("(%d+)$"))
        local d = S.defs[no]
        if not d then return nil end
        return {stats = {attack = d.attack, endurance = d.endurance, speed = d.speed, magic = d.magic, durability = d.durability},
                stat_caps = {attack = d.attack_max}}
      end,
      definition_set = function(a)
        if S.weapons_held then return fail("failed", "owned by another mod") end
        for k, v in pairs(a) do
          assert(({id = 1, attack = 1, endurance = 1, speed = 1, magic = 1, durability = 1, attack_max = 1})[k], "field " .. k)
          if k ~= "id" then assert(math.type(v) == "integer" and v >= 0 and v <= 32767, k) end
        end
        assert(a.attack_max == nil or a.attack_max >= a.attack)
        for k, v in pairs(a) do if k ~= "id" then S.defs[a.id][k] = v end end
        return {}
      end,
    },
    dungeons = {
      loot_get = function(a) local d = S.drops[a.monster_id]; if not d then return fail("invalid_argument", "no monster") end
                             return {rare_item = d.rare_item, steal_item = d.steal_item} end,
      loot_override = function(a)
        for k, v in pairs(a) do if k ~= "monster_id" then assert(v >= -1 and v <= 450) end end
        local d = S.drops[a.monster_id]
        d.rare_item = a.rare_item or d.rare_item; d.steal_item = a.steal_item or d.steal_item
        return {}
      end,
      set_seed = function(a) assert(math.type(a.seed) == "integer" and a.seed >= 0 and a.seed <= 2147483647); S.seeds[#S.seeds + 1] = a.seed; return {} end,
    },
    items = {
      remove = function(a) local no = item_no(a.id); if (S.bag[no] or 0) < a.count then return {removed = 0} end
                           S.bag[no] = S.bag[no] - a.count; return {removed = a.count} end,
      give = function(a) local no = item_no(a.id); S.bag[no] = (S.bag[no] or 0) + a.count; return {} end,
    },
    ui = {notify = function(a) assert(#a.message <= 200); S.notices[#S.notices + 1] = a.message; return true end,
          register = function() return {} end},
  }
  assert(loadfile(MOD_DIR .. "/main.lua"))()
  function S.emit(name, ...) for _, fn in ipairs(S.handlers[name] or {}) do fn(...) end end
  function S.tick(n) for _ = 1, n or 1 do S.emit("game.tick") end end
  function S.snapshot()
    local t = {}
    for shop = 0, 17 do t[#t + 1] = table.concat(S.shops[shop], ",") end
    for no = 258, 376 do t[#t + 1] = S.defs[no].attack .. "/" .. S.defs[no].durability end
    for id = 0, 160 do t[#t + 1] = S.drops[id].rare_item .. "/" .. S.drops[id].steal_item end
    return table.concat(t, ";")
  end
  return S
end

local TODAY = {year = 2026, month = 11, day = 4}

print("Seeds")
local A = boot(nil, {slot = 1, date = TODAY})
check(A.storage.slots and A.storage.slots["1:7"].seed == 261104, "a new save takes today's seed", A.storage.slots and A.storage.slots["1:7"].seed)
check(A.notices[1]:find("261104%-SWDF5"), "and announces its share code", A.notices[1])
local B = boot(nil, {slot = 3, date = TODAY})
check(A.snapshot() == B.snapshot(), "two players on the same day get the same game")
local C = boot(nil, {slot = 1, date = {year = 2026, month = 11, day = 5}, storage = A.storage})
check(C.storage.slots["1:7"].seed == 261104 and C.snapshot() == A.snapshot(), "a save keeps its seed the next day")
local D = boot(nil, {slot = 2, date = {year = 2026, month = 11, day = 5}})
check(D.snapshot() ~= A.snapshot(), "another day is another game")
local F = boot({seed_mode = "Fixed", seed = 261104}, {slot = 4})
check(F.snapshot() == A.snapshot(), "a friend with the Fixed seed plays the same game")
local G = boot(nil, {slot = 5})
check(G.storage.slots["5:7"].seed == 1, "an engine without a date falls back to the Fixed seed")
local U = boot(nil, {date = TODAY})
U.slot = nil; U.tick(30)
check(U.storage.slots.unsaved and U.storage.slots.unsaved.seed == 261104, "a new game keeps its seed as unsaved")
U.slot = 6; U.tick(30)
check(U.storage.slots["6:7"] and U.storage.slots["6:7"].seed == 261104 and U.storage.slots.unsaved == nil, "and carries it into the slot it is saved to")

print("Shops")
local base = retail_shops()
local changed, sizes, weapons_ok = 0, true, true
for shop = 0, 17 do
  if #A.shops[shop] ~= #base[shop] then sizes = false end
  if table.concat(A.shops[shop], ",") ~= table.concat(base[shop], ",") then changed = changed + 1 end
  for i, no in ipairs(A.shops[shop]) do if (no >= 258) ~= (base[shop][i] >= 258) then weapons_ok = false end end
end
check(changed >= 15 and sizes, "every shop restocked, the same size", changed)
check(weapons_ok, "weapons stay weapons, goods stay goods")
local H = boot(nil, {slot = 1, date = TODAY, shops_held = true})
H.emit("ui.action", {id = "check"})
check(H.notices[#H.notices]:find("shops: held by another mod") and H.notices[#H.notices]:find("119 weapons"), "a shop another mod holds is left alone, and Check says so", H.notices[#H.notices])

print("Weapons")
local within, moved = true, 0
for no = 258, 376 do
  local d, b = A.defs[no], 10 + no % 50
  if d.attack < b * 0.69 or d.attack > b * 1.31 + 1 then within = false end
  if d.attack ~= b then moved = moved + 1 end
end
check(within and moved > 80, "attack moves within the 30% spread", moved)
local W = boot({weapon_spread = 5}, {slot = 1, date = TODAY})
local narrow = true
for no = 258, 376 do local b = 10 + no % 50; if math.abs(W.defs[no].attack - b) > b * 0.05 + 1 then narrow = false end end
check(narrow, "a 5% spread stays close")
local NS = boot({shops = false}, {slot = 1, date = TODAY})
local same_weapons = true
for no = 258, 376 do if NS.defs[no].attack ~= A.defs[no].attack then same_weapons = false end end
check(same_weapons and table.concat(NS.shops[0], ",") == table.concat(base[0], ","), "turning shops off leaves the weapon shuffle as it was")

print("Drops")
local none_kept, moved_drops = true, 0
for id = 0, 160 do
  if id % 4 == 0 and A.drops[id].rare_item ~= -1 then none_kept = false end
  if A.drops[id].rare_item ~= -1 and A.drops[id].rare_item ~= 150 then moved_drops = moved_drops + 1 end
end
check(none_kept, "a monster with no drop still has none")
check(moved_drops > 100, "the others drop something new", moved_drops)

print("Floors")
local FA = boot(nil, {slot = 1, date = TODAY})
FA.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2})
FA.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2})
FA.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2, back_floor = true})
FA.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 1, prebuild = true})
check(#FA.seeds == 2 and FA.seeds[1] ~= FA.seeds[2], "each visit to a floor gets its own seed")
check(#FA.seeds == 2, "back floors and prebuilt floors are left to the game")
local first = FA.seeds[1]
local FB = boot(nil, {slot = 3, date = TODAY})
FB.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2})
check(FB.seeds[1] == first, "and the same first visit for everyone on the seed")
local NF = boot({floors = false}, {slot = 1, date = TODAY})
NF.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2})
check(#NF.seeds == 0, "Floors off leaves the layouts alone")

print("Chests")
local swapped = 0
for chest = 0, 39 do
  local S = boot(nil, {slot = 1, date = TODAY})
  S.bag[148] = 1
  S.emit("game.chest.opened", {dungeon_id = 0, floor_id = 3, chest = chest, item_id = 148})
  if S.bag[148] == 0 then swapped = swapped + 1 end
  local total = 0
  for _, n in pairs(S.bag) do total = total + n end
  assert(total == 3, "a swap keeps the item count")
end
check(swapped >= 12 and swapped <= 28, "about half the chests' Bread is swapped", swapped)
local K = boot({chests = 100}, {slot = 1, date = TODAY})
K.emit("game.chest.opened", {dungeon_id = 0, floor_id = 3, chest = 1, item_id = 222})
check(K.bag[222] == 1, "a story key is never swapped")
K.emit("game.chest.opened", {dungeon_id = 0, floor_id = 3, chest = 2, item_id = 95})
check(K.bag[95] == 0, "an attachment becomes another")
local K2 = boot({chests = 100}, {slot = 1, date = TODAY})
K2.emit("game.chest.opened", {dungeon_id = 0, floor_id = 3, chest = 2, item_id = 95})
local same = true
for no, n in pairs(K.bag) do if (K2.bag[no] or 0) ~= n then same = false end end
check(same, "the same chest swaps the same way on the same seed")

print("Sandbox sessions")
local Z = boot(nil, {slot = 1, date = TODAY, session = true})
check(Z.storage.slots == nil and table.concat(Z.shops[0], ",") == table.concat(base[0], ","), "a Gauntlet run is not shuffled")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
