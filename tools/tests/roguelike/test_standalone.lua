-- Checks that RPG, Ascension and Dungeon+ sit out a Dark Genie's Gauntlet run (a sandbox session) and come back
-- after it. Each mod runs against a recording stub of the game API.
-- Usage, from the repository root:  lua tools/tests/roguelike/test_standalone.lua
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."

local passed, failed = 0, 0
local function check(cond, label, extra)
  if cond then passed = passed + 1; print("  ok   " .. label)
  else failed = failed + 1; print("  FAIL " .. label .. (extra and ("  [" .. tostring(extra) .. "]") or "")) end
end

-- A recording game: every call is logged as "ns.fn"; a few calls answer with game-shaped data.
local function boot(mod, opts)
  local S = {calls = {}, callbacks = {}, storage = {}, writes = 0, formulas = {}, player_formulas = {}, frame = 0,
             sandbox = opts and opts.sandbox or false}
  local weapon = {id = "chronicle:weapon:257", item_no = 257, slot = 0, durability = 30, durability_max = 30, speed = 5}
  local answers = {
    ["player.get"] = function() return {character = "toan", hp = 100, max_hp = 120, weapon = weapon, position = {x = 0, y = 0, z = 0}} end,
    ["save.slot_id"] = function() if S.sandbox then return {} end; return {slot_id = 1, slot_generation = 1} end,
    ["session.get"] = function() return {kind = S.sandbox and "sandbox" or "story"} end,
    ["characters.get"] = function() return {max_hp = 120} end,
    ["party.list"] = function() return {{id = "toan"}} end,
    ["world.get"] = function() return {context = "dungeon", dungeon_id = 0, floor_id = 2, floor_seed = 1, back_floor = false} end,
    ["entities.query"] = function() return {entities = {}} end,
    ["weapons.get"] = function() return {id = weapon.id, instances = {{character = "toan", slot = 0, stats = {attack = 10}}}} end,
    ["input.state"] = function() return nil end,
    ["input.consume"] = function() return nil end,
    ["quests.get"] = function() return nil end,
    ["combat.register_formula"] = function(a) S.formulas[a.id] = a; return {id = a.id} end,
    ["combat.register_player_formula"] = function(a) S.player_formulas[a.id] = a; return {id = a.id} end,
  }
  local function namespace(ns)
    return setmetatable({}, {__index = function(t, fn)
      local path = ns .. "." .. fn
      local f = function(...)
        S.calls[#S.calls + 1] = path
        if answers[path] then return answers[path](...) end
        return {}
      end
      rawset(t, fn, f)
      return f
    end})
  end
  local game = setmetatable({}, {__index = function(t, ns) local n = namespace(ns); rawset(t, ns, n); return n end})
  game.events = {subscribe = function(name, cb) S.callbacks[name] = S.callbacks[name] or {}; table.insert(S.callbacks[name], cb) end}
  local moonmod = {
    on = game.events.subscribe,
    log = function() end,
    storage = {get = function(k) return S.storage[k] end, set = function(k, v) S.storage[k] = v; S.writes = S.writes + 1 end},
    settings = {get = function() return nil end},
  }
  function S.emit(name, payload) for _, cb in ipairs(S.callbacks[name] or {}) do cb(payload or {}) end end
  function S.tick(n) for _ = 1, n do S.frame = S.frame + 1; S.emit("game.tick", {frame = S.frame}) end end
  function S.start() S.sandbox = true; S.emit("game.session.started", {owner = "moonmod.roguelike", mode = "gauntlet"}) end
  function S.finish() S.sandbox = false; S.emit("game.session.ended", {owner = "moonmod.roguelike", mode = "gauntlet", reason = "defeat"}) end
  function S.reset() S.calls, S.writes = {}, 0 end
  function S.called(path) for _, c in ipairs(S.calls) do if c == path then return true end end; return false end
  function S.count(path) local n = 0; for _, c in ipairs(S.calls) do if c == path then n = n + 1 end end; return n end
  local env = setmetatable({game = game, moonmod = moonmod}, {__index = _G})
  assert(loadfile(root .. "/mods/" .. mod .. "/main.lua", "t", env))()
  return S
end

-- Everything a run throws at a mod: kills, hits, a weapon pickup, a chest, water, a new floor, a manager action.
local function play_run(S)
  S.tick(120)
  S.emit("game.enemy_defeated", {entity = 5, max_hp = 80, reward_exp = 10, native_model_id = 3})
  S.emit("game.enemy_hit", {entity = 5, damage = 30, native_item_no = 257, element = 0})
  S.emit("game.item_picked_up", {kind = "weapon", native_item_no = 260, character = 0, slot = 1})
  S.emit("game.chest.opened", {})
  S.emit("game.player.thirst_changed", {previous = 50, current = 45})
  S.emit("game.dungeon.generating", {dungeon_id = 0, floor_id = 2})
  S.emit("game.world.location_changed", {context = "dungeon"})
  S.emit("skills.train_requested", {id = "moonmod.rpg:swordsman.keen_edge"})
  S.emit("ui.action", {id = "progress"})
  S.tick(120)
end
local function only_notices(S)
  for _, c in ipairs(S.calls) do if c ~= "ui.notify" then return false, c end end
  return true
end
local function neutral(f) return f and f.operation == "multiply" and f.value == 1 and f.weapon_id == nil and f.native_model_id == nil end

for _, case in ipairs({
  {mod = "moonmod.rpg", name = "RPG", formulas = {"level", "crit", "variance", "mastery", "mobius_ring", "cross_hinder_0"},
   player_formulas = {"toughness", "agas_sword"}, tuning = true},
  {mod = "moonmod.adventurer", name = "Ascension", formulas = {"level", "crit", "variance", "executioner", "mastery", "mobius_ring", "cross_hinder_0"},
   player_formulas = {"toughness", "agas_sword"}},
}) do
  print(case.name .. ": a run in the middle of a story game")
  local S = boot(case.mod)
  S.tick(60)
  check(S.formulas.level and S.formulas.level.value > 0 and S.formulas.level.priority == 50, "story game: level formula registered")
  check(S.formulas.cross_hinder_0 and S.formulas.cross_hinder_0.value == 2, "story game: Cross Hinder bonus registered")
  S.reset()
  S.start()
  local all = true
  for _, id in ipairs(case.formulas) do if not neutral(S.formulas[id]) then all = false; print("    not x1: " .. id) end end
  for _, id in ipairs(case.player_formulas) do if not neutral(S.player_formulas[id]) then all = false; print("    not x1: " .. id) end end
  check(all, "run start: every damage formula is x1")
  check(S.called("render.bar_remove"), "run start: HUD bars removed")
  if case.tuning then check(S.called("player.tuning_clear"), "run start: player tuning cleared") end
  S.reset()
  play_run(S)
  local quiet, stray = only_notices(S)
  check(quiet, "during the run: no game calls besides the sits-out notice", stray)
  check(S.writes == 0, "during the run: nothing stored", S.writes)
  check(S.storage.slots == nil or S.storage.slots.unsaved == nil, "during the run: no \"unsaved\" progress")
  check(neutral(S.formulas.level), "during the run: level formula stays x1")
  S.finish()
  S.tick(60)
  check(S.formulas.level and S.formulas.level.priority == 50, "run over: level formula back")
  check(S.formulas.cross_hinder_0 and S.formulas.cross_hinder_0.value == 2 and S.formulas.cross_hinder_0.weapon_id,
        "run over: weapon formulas back")
  check(S.formulas.mobius_ring and S.formulas.mobius_ring.operation == "ramp_multiply", "run over: Mobius Ring ramp back")

  print(case.name .. ": loaded while a run is already going")
  local R = boot(case.mod, {sandbox = true})
  R.reset()
  play_run(R)
  local quiet2, stray2 = only_notices(R)
  check(quiet2, "no game calls besides the sits-out notice", stray2)
  check(R.writes == 0, "nothing stored", R.writes)
  R.finish()
  R.tick(60)
  check(R.formulas.level and R.formulas.level.priority == 50, "run over: level formula registered")
end

print("Dungeon+: a run in the middle of a story game")
local D = boot("moonmod.dungeon-plus")
D.tick(60)
check(D.count("resources.override") >= 5, "story game: Harder AI scripts overridden")
D.reset()
D.start()
check(D.called("dungeons.set_layout") and D.called("dungeons.set_population") and D.called("dungeons.set_enemy_survival"),
      "run start: native layout, population and enemy survival")
check(D.count("resources.unoverride") == 5, "run start: Harder AI scripts restored", D.count("resources.unoverride"))
check(D.formulas.lucky and D.formulas.lucky.chance == 0 and D.formulas.mutator_out.value == 1 and D.player_formulas.mutator_in.value == 1,
      "run start: no mutator")
D.reset()
play_run(D)
local dquiet, dstray = only_notices(D)
check(dquiet, "during the run: no game calls besides the sits-out notice", dstray)
check(D.writes == 0, "during the run: no stats, bestiary or streaks stored", D.writes)
D.reset()
D.finish()
D.tick(60)
check(D.count("resources.override") == 5, "run over: Harder AI back", D.count("resources.override"))
check(D.called("dungeons.set_population") and D.called("dungeons.set_enemy_survival"), "run over: tiers and population back")
check(D.called("entities.query"), "run over: floor bookkeeping runs again")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
