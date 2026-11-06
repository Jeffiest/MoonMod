-- Plays mods/moonmod.rpg/main.lua against a small fake Chronicle adapter: every hero's paths, powers and effects.
-- Usage, from the repository root:  lua tools/tests/rpg/test_rpg.lua   (Lua 5.4 or newer)
math.randomseed(3)
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../../.."
local MOD_DIR = root .. "/mods/moonmod.rpg"
local ID = "moonmod.rpg"

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

local HEROES = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}

local function boot(storage)
  local S = {settings = {}, handlers = {}, storage = storage or {}, notices = {}, trees = {}, ranks = {}, sheet = nil,
             formulas = {}, player_formulas = {}, tuning = nil, active = "toan", hp = 100, max_hp = 100, healed = 0,
             invincible = 0, statuses = {}, damaged = {}, bursts = {}, keys = {}, held = false, gilda = 0}
  for k, v in pairs(defaults) do S.settings[k] = v end
  _G.moonmod = {
    settings = {get = function(id) return S.settings[id] end},
    storage = {get = function(k) return S.storage[k] end, set = function(k, v) S.storage[k] = v end},
    on = function(name, fn) S.handlers[name] = S.handlers[name] or {}; table.insert(S.handlers[name], fn) end,
    log = function(level, msg) if level == "warn" then S.warned = (S.warned or "") .. msg .. ";" end end,
  }
  local count_trees = 0
  _G.game = {
    skills = {
      register = function(a)
        count_trees = count_trees + 1
        assert(count_trees <= 32, "a mod registers at most 32 trees")
        assert(#a.skills <= 128 and #a.title > 0)
        local ids = {}
        for _, s in ipairs(a.skills) do ids[s.id] = s end
        for _, s in ipairs(a.skills) do
          assert(s.max_rank >= 1 and s.max_rank <= 99)
          for k in pairs(s) do assert(({id = 1, title = 1, description = 1, max_rank = 1, prerequisites = 1})[k], "skill field " .. k) end
          for _, p in ipairs(s.prerequisites or {}) do
            assert(ids[p.id], a.id .. "." .. s.id .. ": prerequisite " .. p.id .. " not in the tree")
            assert(p.rank <= ids[p.id].max_rank, a.id .. "." .. s.id .. ": prerequisite rank over its max")
          end
        end
        assert(not S.trees[a.id], "tree " .. a.id .. " registered twice")
        S.trees[a.id] = a
        return {id = ID .. ":" .. a.id}
      end,
      set_rank = function(a) S.ranks[a.id] = a.rank; return {rank = a.rank} end,
    },
    save = {slot_id = function() return {slot_id = 1, slot_generation = 1} end,
            player_extra_get = function() return S.extra ~= nil and {data = S.extra} or {} end,
            player_extra_set = function(a) S.extra = a.data; S.extra_sets = (S.extra_sets or 0) + 1; return {kept = true} end},
    player = {
      get = function() return {character = S.active, hp = S.hp, max_hp = S.max_hp, position = {x = 0, y = 0, z = 0},
                               weapon = {id = "w", item_no = 258, slot = 0, attack = 20, speed = 10, durability = 30, durability_max = 30}} end,
      set = function(a) if a.max_hp then S.max_hp = a.max_hp end return {} end,
      heal = function(a) S.healed = S.healed + a.amount; return {} end,
      invincible = function(a) S.invincible = a.frames; return {} end,
      tuning_set = function(t)
        for k in pairs(t) do
          assert(({attack_anim_speed = 1, recoil_scale = 1, invincible_bonus_frames = 1, run_speed = 1, map_reveal = 1, monster_reveal = 1,
                   extra_shots = 1, shots_pierce = 1, reach_scale = 1})[k], "tuning field " .. k)
        end
        if t.extra_shots then assert(math.type(t.extra_shots) == "integer" and t.extra_shots >= 0 and t.extra_shots <= 2, "extra_shots") end
        if t.reach_scale then assert(t.reach_scale >= 0.25 and t.reach_scale <= 4) end
        if t.recoil_scale then assert(t.recoil_scale >= 0.25 and t.recoil_scale <= 4) end
        if t.invincible_bonus_frames then assert(t.invincible_bonus_frames <= 120) end
        S.tuning = t; return {}
      end,
      tuning_clear = function() S.tuning = nil; return {} end,
      status_remove = function() return {} end,
      thirst_set = function() return {} end,
    },
    characters = {get = function(a) return {max_hp = S.max_hp} end},
    party = {list = function() local l = {} for i, h in ipairs(HEROES) do l[i] = {id = h} end return l end},
    combat = {
      register_formula = function(a)
        if a.target_hp_below_percent then assert(a.target_hp_below_percent >= 0 and a.target_hp_below_percent <= 100) end
        S.formulas[a.id] = a; return {}
      end,
      register_player_formula = function(a) S.player_formulas[a.id] = a; return {} end,
      damage = function(a) S.damaged[#S.damaged + 1] = a; return {} end,
      status_add = function(a) S.statuses[#S.statuses + 1] = a; return {} end,
    },
    physics = {query = function() return {matches = {{entity = "m1"}, {entity = "m2"}}} end},
    effects = {burst = function(a) S.bursts[#S.bursts + 1] = a; return {} end},
    economy = {add = function(a) S.gilda = S.gilda + a.amount; return {} end, spend = function() return {} end},
    render = {bar_register = function() return {} end, bar_remove = function() return {} end},
    ui = {
      notify = function(a) S.notices[#S.notices + 1] = a.message; return true end,
      sheet_set = function(a)
        assert(#a.title <= 32 and #a.trees <= 32 and #a.lines <= 6 and #(a.hint or "") <= 80, "sheet limits")
        for _, l in ipairs(a.lines) do assert(#l <= 48, "sheet line over 48 bytes: " .. l) end
        S.sheet = a; return {}
      end,
      sheet_clear = function() S.sheet = nil; return {} end,
      register = function() return {} end,
    },
    input = {
      bind = function(a) return {id = a.id} end,
      state = function(a) if a.id == "power_hold" then return {down = S.held} end return {down = false} end,
      consume = function(a) local p = S.keys[a.id]; S.keys[a.id] = nil; return {pressed = p or false} end,
      block_native = function() return {} end,
    },
    weapons = {get = function() return nil end, durability_set = function() return {} end, abs_add = function(a) S.abs = a.amount; return {} end},
    items = {give = function() return {} end},
    session = {get = function() return {kind = "story"} end},
    scripts = {call_function = function() return nil end},
  }
  assert(loadfile(MOD_DIR .. "/main.lua"))()
  function S.emit(name, ...) for _, fn in ipairs(S.handlers[name] or {}) do fn(...) end end
  local f = 0
  function S.tick(n) for _ = 1, n or 1 do f = f + 1; S.emit("game.tick", {frame = f}) end end
  function S.levels(hero, n)
    local was = S.active; S.active = hero; S.tick(10)
    for _ = 1, n do S.emit("ui.action", {id = "test_levels"}) end
    S.active = was; S.tick(10)
  end
  function S.train(node, times) for _ = 1, times or 1 do S.emit("skills.train_requested", {id = ID .. ":" .. node}) end end
  function S.cast(button) S.keys["key_" .. button] = true; S.tick(1) end
  return S
end

print("Every hero's trees")
local S = boot()
local n = 0
for _ in pairs(S.trees) do n = n + 1 end
check(n == 18, "18 trees, three per hero", n)
check(S.warned == nil, "all register cleanly", S.warned)
for _, id in ipairs({"swordsman", "survivor", "explorer"}) do
  check(S.trees[id] ~= nil, "Toan keeps his tree " .. id)
end
local sk = S.trees.swordsman.skills
check(sk[1].id == "keen_edge" and sk[#sk].id == "sword_dance" and sk[#sk].description:find("^POWER  L2%+Square"), "with RPG 1's node ids and descriptions")
local powers = 0
for _, t in pairs(S.trees) do
  local last = t.skills[#t.skills]
  if last.description:find("^POWER") then powers = powers + 1 end
end
check(powers == 18, "every path ends in a power")

print("The sheet follows the active hero")
S.tick(10)
check(S.sheet and S.sheet.title == "TOAN" and S.sheet.trees[1] == "swordsman", "Toan's page")
S.active = "ruby"; S.tick(10)
check(S.sheet.title == "RUBY" and S.sheet.trees[1] == "ruby_arcana" and S.sheet.trees[3] == "ruby_fortune", "Ruby's page shows her own paths")
check(not S.sheet.hint:find("later"), "with no 'later update' hint")

print("Training")
S.levels("ruby", 2)
S.active = "ruby"; S.tick(10)
S.train("ruby_arcana.spellcraft", 2)
check(S.ranks[ID .. ":ruby_arcana.spellcraft"] == 2, "Ruby trains Spellcraft")
check(math.abs(S.formulas.level.value - (1 + 0.025 * 10) * 1.06) < 1e-6, "+3% damage a rank on top of her level", S.formulas.level.value)
S.train("swordsman.keen_edge")
check((S.ranks[ID .. ":swordsman.keen_edge"] or 0) == 0 and S.notices[#S.notices]:find("Toan.s"), "Toan's node can't be trained as Ruby", S.notices[#S.notices])
S.active = "toan"; S.tick(10)
check(math.abs(S.formulas.level.value - 1) < 1e-6, "Ruby's ranks don't help Toan")
check(S.ranks[ID .. ":ruby_arcana.spellcraft"] == 2, "her rank stays on her node")

print("Engine effects")
S.active = "ruby"; S.tick(10)
S.train("ruby_arcana.spellcraft"); S.train("ruby_arcana.twin_orbs", 2); S.train("ruby_arcana.piercing_orbs")
check(S.tuning.extra_shots == 2 and S.tuning.shots_pierce == true, "Twin Orbs and Piercing Orbs reach the engine", S.tuning.extra_shots)
S.levels("ungaga", 1)
S.active = "ungaga"; S.tick(10)
S.train("ungaga_spear.long_reach", 3)
check(S.tuning.reach_scale and math.abs(S.tuning.reach_scale - 1.3) < 1e-9, "Long Reach lengthens Ungaga's spear")
S.active = "toan"; S.tick(10)
check(S.tuning.extra_shots == 0 and S.tuning.reach_scale == 1, "and none of it carries to Toan")

print("Powers")
S = boot()
S.levels("goro", 2); S.active = "goro"; S.tick(10)
S.train("goro_might.heavy_hand", 3); S.train("goro_might.earthquake")
check(S.ranks[ID .. ":goro_might.earthquake"] == 1, "Goro learns Earthquake")
S.cast("square")
check(S.bursts[1] and S.bursts[1].kind == "explosion" and #S.damaged == 2 and S.statuses[1].status == "stop", "Earthquake: a blast that hurts and stops what it hits")
S.cast("square")
check(#S.damaged == 2 and S.notices[#S.notices]:find("ready in"), "then a cooldown")

S = boot()
S.levels("osmond", 2); S.active = "osmond"; S.tick(10)
S.train("osmond_armor.plating", 3); S.train("osmond_armor.barrier")
S.cast("triangle")
check(S.invincible == 120, "Barrier: two seconds untouchable")
local shielded = S.player_formulas.toughness.value
S.tick(700)
check(S.player_formulas.toughness.value > shielded * 1.9, "then half damage taken, ending after ten seconds")

S = boot()
S.levels("xiao", 2); S.active = "xiao"; S.tick(10)
S.train("xiao_hunter.sharp_eye", 3); S.train("xiao_hunter.volley")
check(S.tuning.extra_shots == 0, "no extra stones before the Volley")
S.cast("square")
check(S.tuning.extra_shots == 2, "Volley: two more stones")
S.tick(500)
check(S.tuning.extra_shots == 0, "for eight seconds")

print("Hits and time")
S = boot()
S.levels("goro", 1); S.active = "goro"; S.tick(10)
S.train("goro_might.heavy_hand"); S.train("goro_might.crushing_blow", 2)
S.emit("game.enemy_hit", {damage = 30, entity = "m9", charged = true})
check(S.statuses[1] and S.statuses[1].entity == "m9" and S.statuses[1].duration_frames == 60, "Crushing Blow: a charged hit stops the enemy")
S.emit("game.enemy_hit", {damage = 30, entity = "m9", charged = false})
check(#S.statuses == 1, "an ordinary hit doesn't")
S = boot()
S.levels("ruby", 1); S.active = "ruby"; S.tick(10)
S.train("ruby_grace.moon_thirst", 3)
local before = S.healed
S.emit("game.enemy_hit", {damage = 50, entity = "m1"})
check(S.healed - before == 3, "Moon Thirst heals 6% of the damage dealt", S.healed - before)
S = boot()
S.levels("goro", 1); S.active = "goro"; S.tick(10)
S.train("goro_appetite.hearty", 3)
S.hp = 50; S.max_hp = 200; before = S.healed
S.tick(120)
check(S.healed - before >= 2, "Hearty regenerates a little each second", S.healed - before)
S = boot()
S.levels("osmond", 1); S.active = "osmond"; S.tick(10)
S.train("osmond_gunner.steady_aim"); S.train("osmond_gunner.finisher", 3)
check(S.formulas.execute and math.abs(S.formulas.execute.value - 1.3) < 1e-9 and S.formulas.execute.target_hp_below_percent == 30, "Finisher: +30% against an enemy under 30% life")

print("Old saves")
S = boot({slots = {["1:1"] = {chars = {toan = {level = 10, xp = 0, ranks = {["swordsman.keen_edge"] = 5, ["survivor.toughness"] = 2}}}, mastery = {}}}})
S.tick(10)
check(S.ranks[ID .. ":swordsman.keen_edge"] == 5, "Toan's RPG 1 ranks are read from the save")
check(math.abs(S.formulas.level.value - (1 + 0.025 * 9) * 1.15) < 1e-6, "and still work", S.formulas.level.value)

print("A co-op visit")
S = boot({slots = {["1:1"] = {chars = {toan = {level = 10, xp = 0, ranks = {}}}, mastery = {}}}})
S.tick(10)
local own = S.formulas.level.value
S.extra = {chars = {toan = {level = 4, xp = 0, ranks = {}}}, mastery = {}}
S.emit("game.session.started", {kind = "visit", owner = "moonmod.coop", map = 0})
S.tick(40)
check(S.formulas.level.value < own and math.abs(S.formulas.level.value - (1 + 0.025 * 3)) < 1e-6,
      "in the host's world the guest's own level (4) counts, not this game's save (10)", S.formulas.level.value)
S.levels("toan", 2)
check(S.extra.chars.toan.level > 4, "levels earned there go with the guest's things", S.extra.chars.toan.level)
check(S.storage.slots["1:1"].chars.toan.level == 10 and S.storage.slots.visit == nil, "and never into this game's saves")
S.emit("game.session.ended", {kind = "visit"})
S.tick(40)
check(math.abs(S.formulas.level.value - own) < 1e-6, "back home, the save's own level again")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
