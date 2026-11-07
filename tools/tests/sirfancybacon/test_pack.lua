-- SirFancyBacon Mod Pack (mods/moonmod.sirfancybacon) in a fake game.
-- Usage, from the repository root:  lua tools/tests/sirfancybacon/test_pack.lua
local root = arg and arg[0] and arg[0]:match("^(.*)/tools/tests/sirfancybacon/") or "."
local MOD = root .. "/mods/moonmod.sirfancybacon/main.lua"

local passed, failed = 0, 0
local function check(ok, what, detail)
  if ok then passed = passed + 1; print("  ok   " .. what)
  else failed = failed + 1; print("  FAIL " .. what .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or "")) end
end

local function make_game(opts)
  opts = opts or {}
  local S = {handlers = {}, settings = opts.settings or {}, toasts = {}, layers = {}, keys = {}, frame = 0, se = {},
             bag = opts.bag or {}, quick = opts.quick or {}, selection = nil, rules = opts.rules or {},
             player = {character = "toan", weapon = {id = "chronicle:weapon:1", slot = 1, durability = 30, durability_max = 30}},
             binds = {}}
  local env = setmetatable({}, {__index = _G})
  env.moonmod = {
    on = function(event, fn) S.handlers[event] = S.handlers[event] or {}; table.insert(S.handlers[event], fn) end,
    log = function() end,
    settings = {get = function(k) return S.settings[k] end},
  }
  env.game = {
    ui = {notify = function(n) S.toasts[#S.toasts + 1] = n.message end},
    audio = {se_play = function(a) S.se[#S.se + 1] = a.se; return {} end},
    render = {layer_register = function(l) S.layers[l.id] = l.text end, layer_remove = function(l) S.layers[l.id] = nil end},
    input = {bind = function(a) S.binds[a.id] = a.keys; return true end,
             consume = function(a) local p = S.keys[a.id]; S.keys[a.id] = nil; return {pressed = p} end},
    player = {get = function() return S.player end},
    weapons = {durability_set = function(a)
      assert(a.id == S.player.weapon.id and a.character == S.player.character and a.slot == S.player.weapon.slot)
      S.player.weapon.durability = a.durability
      return {}
    end},
    items = {
      remove = function(a)
        local no = tonumber(a.id:match("^chronicle:item:(%d+)$"))
        local have = S.bag[no] or 0
        local n = math.min(have, a.count)
        S.bag[no] = have - n
        return {removed = n}
      end,
      quick_slots = function() return S.quick end,
    },
    dungeons = {
      selection = function() return S.selection end,
      floor_rules_get = function(a)
        return {dungeon_id = a.dungeon_id, floor_id = a.floor_id,
                limit_zone_name = (S.rules[a.dungeon_id] or {})[a.floor_id] or "none"}
      end,
    },
  }
  S.mod = assert(loadfile(MOD, "t", env))()
  function S.tick(n)
    for _ = 1, n or 1 do
      S.frame = S.frame + 1
      for _, fn in ipairs(S.handlers["game.tick"] or {}) do fn({frame = S.frame}) end
    end
  end
  function S.last_toast() return S.toasts[#S.toasts] or "" end
  return S
end

print("Auto Repair Powder from the bag")
do
  local g = make_game({bag = {[183] = 2}})
  g.player.weapon.durability = 3
  g.tick(10)
  check(g.player.weapon.durability == 30 and g.bag[183] == 1, "a weapon about to break is mended from the bag", g.player.weapon.durability)
  check(g.se[1] == 24 and g.last_toast():find("Auto Repair Powder"), "with the repair sound and a word")
  g.player.weapon.durability = 10
  g.tick(10)
  check(g.bag[183] == 1, "a weapon with wear left is left alone")

  local q = make_game({bag = {[183] = 1}, quick = {{slot = 1, item_no = 183, count = 1}}})
  q.player.weapon.durability = 2
  q.tick(10)
  check(q.bag[183] == 1 and q.player.weapon.durability == 2, "one in a quick slot is left to the game")

  local off = make_game({bag = {[183] = 1}, settings = {auto_repair = false}})
  off.player.weapon.durability = 2
  off.tick(10)
  check(off.bag[183] == 1, "the setting turns it off")

  local none = make_game({bag = {[177] = 3}})
  none.player.weapon.durability = 2
  none.tick(10)
  check(none.bag[177] == 3 and none.player.weapon.durability == 2, "a plain Repair Powder is never spent by itself")

  local town = make_game({bag = {[183] = 1}})
  town.player = {character = "toan"}
  town.tick(10)
  check(town.bag[183] == 1, "no weapon out (in town): nothing happens")
end

print("Repair Powder on a key")
do
  local g = make_game({bag = {[177] = 1}})
  check(g.binds.repair and g.binds.repair[1] == "T", "T is the key (R is R2, G the Gauntlet's curse)", g.binds.repair and g.binds.repair[1])
  g.player.weapon.durability = 12
  g.keys.repair = true
  g.tick()
  check(g.player.weapon.durability == 30 and g.bag[177] == 0 and g.se[1] == 24, "T mends the weapon with a Repair Powder")
  g.player.weapon.durability = 12
  g.keys.repair = true
  g.tick()
  check(g.player.weapon.durability == 12 and g.last_toast() == "You have no Repair Powder.", "none left: it says so")
  g.bag[177] = 1
  g.player.weapon.durability = 30
  g.keys.repair = true
  g.tick()
  check(g.bag[177] == 1 and g.last_toast() == "Your weapon needs no repair.", "a whole weapon takes none")
  g.settings.repair_key = false
  g.player.weapon.durability = 5
  g.keys.repair = true
  g.tick()
  check(g.bag[177] == 1, "the setting turns the key off")
end

print("The floor list's warning")
do
  local g = make_game({rules = {[2] = {[8] = "thirst"}, [4] = {[7] = "ruby_only"}}})
  g.tick(10)
  check(g.layers.floor_limit == nil, "nothing shown outside the floor list")
  g.selection = {dungeon_id = 0, floor_id = 10}
  g.tick(10)
  check(g.layers.floor_limit == "! Only Xiao can go on this floor", "Divine Beast Cave B11: only Xiao (fixed)", g.layers.floor_limit)
  g.selection = {dungeon_id = 0, floor_id = 6}
  g.tick(10)
  check(g.layers.floor_limit == "! Weapons can't be changed on this floor", "B7: weapons locked", g.layers.floor_limit)
  g.selection = {dungeon_id = 2, floor_id = 8}
  g.tick(10)
  check(g.layers.floor_limit == "! Thirst comes faster on this floor", "a rolled limit from the save", g.layers.floor_limit)
  g.selection = {dungeon_id = 4, floor_id = 7}
  g.tick(10)
  check(g.layers.floor_limit == "! Only Ruby can go on this floor", "only Ruby", g.layers.floor_limit)
  g.selection = {dungeon_id = 2, floor_id = 3}
  g.tick(10)
  check(g.layers.floor_limit == nil, "a free floor shows nothing")
  g.selection = {dungeon_id = 1, floor_id = 11}
  g.tick(10)
  check(g.layers.floor_limit == "! Only Goro can go on this floor", "Wise Owl 12: only Goro", g.layers.floor_limit)
  g.selection = nil
  g.tick(10)
  check(g.layers.floor_limit == nil, "leaving the list takes the warning away")
  g.settings.limit_warning = false
  g.selection = {dungeon_id = 0, floor_id = 10}
  g.tick(10)
  check(g.layers.floor_limit == nil, "the setting turns it off")
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed > 0 and 1 or 0)
