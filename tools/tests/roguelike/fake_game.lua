-- Fake Chronicle adapter for tools/tests/roguelike/test_runs.lua.
-- A fake Chronicle adapter for exercising mods/moonmod.roguelike/main.lua outside the game.
-- Shapes and refusals follow ports/chronicle/moonfactory-chronicle.patch (the real adapter source).
local F = {}

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = deepcopy(x) end
  return t
end
F.deepcopy = deepcopy

local function fail(code, msg) return nil, {code = code, message = msg} end

function F.new(opts)
  opts = opts or {}
  local S = {
    frame = 0,
    context = "title", dungeon = nil, floor = nil, back = false, seed = 1,
    floor_counts = {[0] = 15, 17, 18, 18, 15},
    registered = {},           -- qualified id -> record
    party = {"toan"},          -- a fresh session's party size grows to session.start's party_size
    active = opts.start or "toan",
    hp = {}, max_hp = {},
    gilda = 1000,
    items = {},
    weapons = {},              -- weapons[char][slot] = {item_no, level, abs, attack, endurance, speed, magic, durability, durability_f, elem, attach}
    equipped = {},
    monsters = {},             -- list of {handle, hp, max_hp, defense, exp, money, drop, revealed, alive, model}
    next_handle = 1,
    callbacks = {},
    log = {},
    toasts = {},
    storage = opts.storage or {},
    settings = opts.settings,
    tuning = nil, formulas = {}, player_formulas = {},
    sheet = nil, layers = {}, bars = {},
    pending_jump = nil,
    atla = {},
    ranks = {},
    slot_id = {slot_id = 1, slot_generation = 7},
    modifiers = {},
    limit_zones = {},
    input_pressed = {}, input_down = {},
    calls = {},
    fail_ops = opts.fail_ops or {},
  }
  for _, c in ipairs({"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}) do
    S.hp[c], S.max_hp[c] = 120, 120
    S.weapons[c] = {}
  end
  -- weapon catalog: per character three weapons, item numbers by character
  local catalog = {}
  local base = {toan = 257, xiao = 270, goro = 280, ruby = 290, ungaga = 300, osmond = 310}
  for c, no in pairs(base) do
    for i = 0, 2 do
      catalog[#catalog + 1] = {id = "chronicle:weapon:" .. (no + i), native_item_no = no + i, owner = c, mod_owned = false,
        stats = {attack = 10 + i * 15, endurance = 5, speed = 5, magic = 2, durability = 30 + i * 10}, socket_count = 3}
    end
  end
  S.catalog = catalog
  local function def_of(no) for _, d in ipairs(catalog) do if d.native_item_no == no then return d end end end
  local function wid(no) return "chronicle:weapon:" .. no end
  local function parse_wid(id) return tonumber(tostring(id):match("(%d+)$")) end
  local function new_weapon(no, level)
    local d = def_of(no)
    return {item_no = no, level = level or 0, abs = 0, attack = d.stats.attack, endurance = 5, speed = 5, magic = 2,
            durability = d.stats.durability, durability_f = d.stats.durability, elem = {0, 0, 0, 0, 0}, attach = {}}
  end
  -- A new game's save: everyone has start HP, only Toan a weapon (his first). session.start gives the rest theirs.
  local function fresh_save(party_size, start)
    S.party = {}
    for i, c in ipairs({"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}) do
      S.weapons[c] = {}
      S.equipped[c] = nil
      S.hp[c], S.max_hp[c] = 70 + i * 5, 70 + i * 5
      if i <= party_size then
        S.party[#S.party + 1] = c
        S.weapons[c][0] = new_weapon(base[c], 0)
        S.equipped[c] = 0
      end
    end
    S.items, S.gilda, S.active = {}, 0, start or "toan"
  end
  S.fresh_save = fresh_save
  fresh_save(1)

  local function find_weapon(sel)
    local no = parse_wid(sel.id)
    if not no then return fail("invalid_argument", "bad weapon id") end
    for _, c in ipairs(sel.character and {sel.character} or S.party) do
      for slot = 0, 10 do
        local w = S.weapons[c] and S.weapons[c][slot]
        if w and w.item_no == no and (sel.slot == nil or sel.slot == slot) then return w, c, slot end
      end
    end
    return fail("failed", "no owned weapon matches")
  end
  local function abs_max(w) return 50 + w.level * 30 end

  local function emit(name, payload)
    for _, cb in ipairs(S.callbacks[name] or {}) do
      local ok, err = pcall(cb, payload)
      if not ok then error("callback " .. name .. " failed: " .. tostring(err)) end
    end
  end
  S.emit = emit

  local function in_dungeon() return S.context == "dungeon" end

  local function record(op) S.calls[op] = (S.calls[op] or 0) + 1 end
  local function wrap(domain, ops)
    local t = {}
    for name, fn in pairs(ops) do
      t[name] = function(...)
        local op = domain .. "." .. name
        record(op)
        if S.fail_ops[op] then return fail("unsupported", op .. " disabled in harness") end
        return fn(...)
      end
    end
    return t
  end

  local game = {}
  game.ui = wrap("ui", {
    notify = function(a) S.toasts[#S.toasts + 1] = a.message; return {queued = true} end,
    register = function(a) S.actions = S.actions or {}; S.actions[#S.actions + 1] = a.id; assert(#S.actions <= 12, "more than 12 actions"); assert(#a.label <= 48 and #a.description <= 120, "action text too long: " .. a.id); return {id = a.id} end,
    sheet_set = function(a)
      assert(a.title and #a.title <= 32, "sheet title")
      assert(#(a.lines or {}) <= 6, "sheet lines")
      for _, l in ipairs(a.lines or {}) do assert(#l <= 48, "sheet line too long: " .. l) end
      assert(not a.hint or #a.hint <= 80, "hint too long")
      assert(not a.progress_label or #a.progress_label <= 32, "progress label too long")
      S.sheet = deepcopy(a); return {set = true}
    end,
    sheet_clear = function() S.sheet = nil; return {cleared = true} end,
    sheet_open = function() return fail("failed", "not in play") end,
    navigate = function() return {opened = true} end,
  })
  S.title_modes = {}
  S.open_mode = nil
  S.session = nil            -- {owner, mode}
  game.title = wrap("title", {
    mode_register = function(a)
      assert(a.id and a.label and a.title, "mode_register needs id, label, title")
      S.title_modes[a.id] = deepcopy(a)
      return {id = "moonmod.roguelike:" .. a.id}
    end,
    mode_set = function(a)
      local m = S.title_modes[a.id]
      if not m then return fail("failed", "no such mode") end
      assert(#(a.entries or m.entries or {}) <= 7, "at most 7 entries")
      assert(#(a.lines or m.lines or {}) <= 6, "at most 6 lines")
      for _, l in ipairs(a.lines or {}) do assert(#l <= 64, "line too long: " .. l) end
      for _, e in ipairs(a.entries or {}) do assert(#e.label <= 64 and e.id ~= "back", "entry " .. tostring(e.id)) end
      for k, v in pairs(a) do m[k] = deepcopy(v) end
      if a.entries and a.cursor == nil then m.cursor = 0 end
      return {id = a.id}
    end,
  })
  game.session = wrap("session", {
    get = function()
      if S.session then return {kind = "sandbox", owner = S.session.owner, mode = S.session.mode} end
      return {kind = S.context == "title" and "title" or "story"}
    end,
    start = function(a)
      if S.context ~= "title" or not S.open_mode then return fail("failed", "start from the open title mode screen") end
      local floor
      for _, rec in pairs(S.registered) do for _, f in ipairs(rec.floors) do if f.id == a.floor then floor = {rec.dungeon, f.native_floor_id} end end end
      if not floor then return fail("failed", "no registered dungeon floor has that id") end
      local ids = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
      local index = 1; for i, c in ipairs(ids) do if c == a.character then index = i end end
      if index > (a.party_size or 1) then return fail("invalid_argument", "character beyond party") end
      S.session_request = {floor = floor, party_size = a.party_size or 1, character = a.character}
      return {queued = true}
    end,
    finish = function()
      if not S.session then return fail("failed", "no sandbox session") end
      if S.context ~= "dungeon" then return fail("failed", "from its dungeon") end
      S.session.ending = S.session.ending or "ended"
      S.pending_jump = {town = true}
      return {queued = true}
    end,
  })
  game.save = wrap("save", {slot_id = function() if S.session then return {} end; return deepcopy(S.slot_id) end})
  game.skills = wrap("skills", {
    register = function(a) for _, n in ipairs(a.skills) do assert(n.max_rank >= 1 and n.max_rank <= 99) end; return {id = a.id} end,
    set_rank = function(a) assert(type(a.rank) == "number" and a.rank >= 0, "rank"); S.ranks[a.id] = a.rank; return {rank = a.rank} end,
  })
  game.dungeons = wrap("dungeons", {
    register = function(def)
      local q = "moonmod.roguelike:" .. def.id
      if S.registered[q] then return fail("invalid_argument", "a mod dungeon with this stable id is already registered") end
      local count = S.floor_counts[def.dungeon]
      if count + #def.floors > 25 then return fail("failed", "at most 25 floors") end
      local rec = {id = q, floors = {}}
      for i, f in ipairs(def.floors) do
        assert(type(f.source_floor) == "number" and f.source_floor >= 0 and f.source_floor < count, "source floor out of range")
        rec.floors[i] = {id = q .. ":" .. f.id, native_floor_id = count + i - 1, name = f.name}
      end
      S.floor_counts[def.dungeon] = count + #def.floors
      rec.dungeon = def.dungeon
      S.registered[q] = rec
      return deepcopy(rec)
    end,
    get = function(id) local r = S.registered["moonmod.roguelike:" .. id] or S.registered[id]; if not r then return fail("failed", "unknown") end; return deepcopy(r) end,
    floor_rules_get = function(a) local k = a.dungeon_id .. ":" .. a.floor_id; local z = S.limit_zones[k] or 0; return {limit_zone = z, limit_zone_name = z == -1 and "none" or "toan_only"} end,
    floor_rules_set = function(a) S.limit_zones[a.dungeon_id .. ":" .. a.floor_id] = a.limit_zone; return {limit_zone = a.limit_zone, limit_zone_name = a.limit_zone == -1 and "none" or "custom"} end,
    set_modifiers = function(a) S.modifiers = deepcopy(a); return {} end,
  })
  game.world = wrap("world", {
    get = function()
      if S.context == "title" then return fail("failed", "no save") end
      local r = {context = S.context, day = 3}
      if in_dungeon() then r.dungeon_id = S.dungeon; r.floor_id = S.floor; r.floor_seed = S.seed; r.back_floor = S.back end
      return r
    end,
    transition = function(a)
      if S.context ~= "dungeon" and S.context ~= "georama" then return fail("failed", "requires town or dungeon") end
      if S.pending_jump then return fail("failed", "a native map transition is already pending") end
      for _, rec in pairs(S.registered) do
        for _, f in ipairs(rec.floors) do
          if f.id == a.id then S.pending_jump = {dungeon = rec.dungeon, floor = f.native_floor_id}; return {queued = true} end
        end
      end
      if a.id == "chronicle:location:norune-village" or a.id == "norune-village" then S.pending_jump = {town = true}; return {queued = true} end
      return fail("invalid_argument", "unknown destination " .. tostring(a.id))
    end,
  })
  game.player = wrap("player", {
    get = function()
      if S.context == "title" then return fail("failed", "no save") end
      local c = S.active
      local r = {character = c, hp = S.hp[c], max_hp = S.max_hp[c], water = 50, max_water = 100}
      local slot = S.equipped[c]
      local w = slot and S.weapons[c][slot]
      if w then r.weapon = {id = wid(w.item_no), item_no = w.item_no, slot = slot, attack = w.attack, speed = w.speed, durability = w.durability_f, durability_max = w.durability} end
      if in_dungeon() then r.position = {x = 0, y = 0, z = 0} end
      return r
    end,
    set = function(a)
      local c = a.character or S.active
      assert(a.hp and math.type(a.hp) == "integer" and a.hp >= 0, "player.set hp")
      if not S.max_hp[c] then return fail("invalid_argument", "character") end
      S.hp[c] = math.min(a.hp, S.max_hp[c]); return {hp = S.hp[c]}
    end,
    tuning_set = function(a)
      for k, v in pairs(a) do
        if k == "map_reveal" or k == "monster_reveal" then assert(type(v) == "boolean")
        elseif k == "invincible_bonus_frames" then assert(math.type(v) == "integer" and v >= 0 and v <= 120, "inv frames")
        else assert(type(v) == "number" and v >= 0.25 and v <= 4, "tuning " .. k .. "=" .. tostring(v)) end
      end
      S.tuning = deepcopy(a); return {tuning = a}
    end,
    tuning_clear = function() S.tuning = nil; return {} end,
    invincible = function(a) if not in_dungeon() then return fail("failed", "town") end; return {frames = a.frames} end,
    heal = function(a) local c = S.active; S.hp[c] = math.min(S.max_hp[c], S.hp[c] + a.amount); return {hp = S.hp[c]} end,
  })
  game.combat = wrap("combat", {
    register_formula = function(a) assert(a.value >= 0 and a.value <= 100); S.formulas[a.id] = deepcopy(a); return {id = a.id} end,
    get = function()
      if not in_dungeon() then return fail("failed", "not in dungeon") end
      local n = 0; for _, m in ipairs(S.monsters) do if m.alive then n = n + 1 end end
      return {in_combat = n > 0, enemy_count = n, remaining = n, enemies = {}}
    end,
    damage = function(a)
      for _, m in ipairs(S.monsters) do
        if m.handle == a.entity and m.alive then
          m.hp = m.hp - a.amount
          if m.hp <= 0 then S.kill(m, true) end
          return {damage = a.amount}
        end
      end
      return fail("failed", "stale")
    end,
    register_player_formula = function(a) assert(a.value >= 0 and a.value <= 100); S.player_formulas[a.id] = deepcopy(a); return {id = a.id} end,
  })
  game.entities = wrap("entities", {
    query = function()
      if not in_dungeon() then return fail("failed", "not in dungeon") end
      local out = {}
      for _, m in ipairs(S.monsters) do
        if m.alive then
          out[#out + 1] = {id = "slot" .. m.handle, entity_id = m.handle, revealed = m.revealed, native_model_id = m.model,
            health = {current = m.hp, maximum = m.max_hp}, combat = {defense = m.defense, reward_exp = m.exp, reward_money = m.money, drop_item = m.drop}}
        end
      end
      return {entities = out}
    end,
    get = function(h)
      for _, m in ipairs(S.monsters) do
        if m.handle == h then
          if not m.alive then return {status = "dead"} end
          return {status = "alive", health = {current = m.hp, maximum = m.max_hp}}
        end
      end
      return {status = "expired"}
    end,
    set_stats = function(a)
      for _, m in ipairs(S.monsters) do
        if m.handle == a.entity then
          if not m.revealed then return fail("failed", "unrevealed") end
          assert(a.max_hp >= 1 and a.max_hp <= 1000000 and a.hp <= a.max_hp, "hp bounds")
          assert(a.defense >= 0 and a.defense <= 32767, "defense bounds")
          assert(a.reward_exp >= 0 and a.reward_exp <= 32767, "exp bounds")
          assert(math.type(a.max_hp) == "integer" and math.type(a.reward_exp) == "integer" and math.type(a.defense) == "integer", "integers")
          m.max_hp, m.hp, m.defense, m.exp, m.money = a.max_hp, a.hp, a.defense, a.reward_exp, a.reward_money
          m.scaled = (m.scaled or 0) + 1
          return {changed = true}
        end
      end
      return fail("failed", "stale")
    end,
    scale_set = function(a) assert(a.scale >= 0.5 and a.scale <= 3); return {scale = a.scale} end,
  })
  game.physics = wrap("physics", {
    query = function()
      local out = {}
      for _, m in ipairs(S.monsters) do if m.alive and m.revealed then out[#out + 1] = {entity = m.handle, distance = 50} end end
      return {matches = out}
    end,
  })
  game.economy = wrap("economy", {
    add = function(a) assert(a.amount >= 1 and a.amount <= 32767, "economy.add amount"); S.gilda = math.min(65535, S.gilda + a.amount); return {gilda = S.gilda} end,
    spend = function(a) if S.gilda < a.amount then return fail("failed", "insufficient") end; S.gilda = S.gilda - a.amount; return {gilda = S.gilda} end,
  })
  game.items = wrap("items", {
    give = function(a)
      assert(a.count >= 1 and a.count <= 999)
      S.items[a.id] = (S.items[a.id] or 0) + a.count
      return {added = a.count}
    end,
  })
  game.party = wrap("party", {
    list = function() local out = {}; for _, c in ipairs(S.party) do out[#out + 1] = {id = c, active = c == S.active, hp = S.hp[c], max_hp = S.max_hp[c]} end; return out end,
    set_active = function(a)
      if not in_dungeon() then return fail("failed", "requires dungeon") end
      local ok = false; for _, c in ipairs(S.party) do if c == a.id then ok = true end end
      if not ok then return fail("failed", "not joined") end
      if S.hp[a.id] <= 0 then return fail("failed", "the target is knocked out") end
      S.active = a.id; return {changed = true}
    end,
  })
  game.weapons = wrap("weapons", {
    list = function() return deepcopy(S.catalog) end,
    get = function(id)
      local no = parse_wid(type(id) == "table" and id.id or id)
      local d = def_of(no)
      if not d then return fail("failed", "unknown weapon") end
      local r = deepcopy(d)
      r.instances = {}
      for _, c in ipairs({"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}) do
        for slot = 0, 10 do
          local w = S.weapons[c][slot]
          if w and w.item_no == no then
            r.instances[#r.instances + 1] = {character = c, slot = slot, equipped = S.equipped[c] == slot, level = w.level,
              stats = {attack = w.attack, endurance = w.endurance, speed = w.speed, magic = w.magic, durability = w.durability, durability_current = w.durability_f},
              elements = deepcopy(w.elem)}
          end
        end
      end
      return r
    end,
    give = function(a)
      local no = parse_wid(a.id)
      local d = def_of(no)
      local c = d.owner
      local joined = false; for _, p in ipairs(S.party) do if p == c then joined = true end end
      if not joined then return fail("failed", "not joined") end
      for slot = 0, 10 do
        if not S.weapons[c][slot] then S.weapons[c][slot] = new_weapon(no, 0); return {id = a.id, native_item_no = no, slot = slot, added = true} end
      end
      return fail("failed", "no free slot")
    end,
    equip = function(a)
      if S.context ~= "georama" then return fail("failed", "weapons.equip can change the saved loadout only in an active Georama town") end
      local w, c, slot = find_weapon(a)
      if not w then return nil, c end
      S.equipped[c] = slot; return {equipped = true, changed = true}
    end,
    abs_get = function(sel) local w, c, slot = find_weapon(sel); if not w then return nil, c end; return {level = w.level, abs = w.abs, abs_max = abs_max(w), character = c, slot = slot} end,
    abs_add = function(a)
      assert(math.type(a.amount) == "integer" and a.amount >= 1 and a.amount <= 32767, "abs_add amount " .. tostring(a.amount))
      local w, c = find_weapon(a); if not w then return nil, c end
      w.abs = w.abs + a.amount
      return {abs = w.abs, abs_max = abs_max(w), level = w.level}
    end,
    upgrade = function(sel)
      local w, c = find_weapon(sel); if not w then return nil, c end
      if w.abs < abs_max(w) then return {upgraded = false, changed = false} end
      w.abs = w.abs - abs_max(w); w.level = w.level + 1; w.attack = w.attack + 2
      return {upgraded = true, changed = true, level = w.level}
    end,
    attachment_insert = function(a)
      assert(a.attachment_id >= 90 and a.attachment_id <= 149, "attachment range")
      local w, c = find_weapon(a); if not w then return nil, c end
      if #w.attach >= 3 then return fail("failed", "all attachment slots on this weapon are full") end
      w.attach[#w.attach + 1] = a.attachment_id; return {inserted = true}
    end,
    stats_set = function(a)
      local w, c = find_weapon(a); if not w then return nil, c end
      for _, k in ipairs({"attack", "endurance", "speed", "magic"}) do
        if a[k] ~= nil then assert(math.type(a[k]) == "integer" and a[k] >= 0 and a[k] <= 32767, "stat " .. k); w[k] = a[k] end
      end
      if a.durability then
        local frac = w.durability_f / w.durability
        w.durability = a.durability; w.durability_f = a.durability * frac
      end
      if a.elem then for i = 1, 5 do assert(a.elem[i] >= 0 and a.elem[i] <= 127); w.elem[i] = a.elem[i] end end
      return {changed = true}
    end,
    durability_set = function(a)
      local w, c = find_weapon(a); if not w then return nil, c end
      assert(a.durability >= 0 and a.durability <= w.durability, "durability above max")
      w.durability_f = a.durability; return {durability = a.durability}
    end,
    synthesize = function(a)
      local w, c, slot = find_weapon(a); if not w then return nil, c end
      if S.equipped[c] == slot then return fail("failed", "cannot status-break the currently equipped weapon") end
      if w.level < 5 then return fail("failed", "weapon must be at least level 5") end
      S.weapons[c][slot] = nil; S.items["sphere"] = (S.items["sphere"] or 0) + 1
      return {synthesized = true}
    end,
  })
  game.georama = wrap("georama", {
    atla_list = function()
      if not in_dungeon() then return fail("failed", "no floor") end
      local out = {}; for _, a in ipairs(S.atla) do out[#out + 1] = {slot = a, atla_id = a} end
      return {atla = out}
    end,
  })
  game.input = wrap("input", {
    bind = function(a) return {id = a.id} end,
    consume = function(a) local p = S.input_pressed[a.id]; S.input_pressed[a.id] = nil; return {pressed = p == true} end,
    state = function(a) return {down = S.input_down[a.id] == true} end,
  })
  game.render = wrap("render", {
    layer_register = function(a)
      assert(#a.text >= 1 and #a.text <= 48, "layer text length")
      assert(a.text:match("^[%w %-%:%.]+$"), "layer text charset: " .. a.text)
      S.layers[a.id] = a.text; return {}
    end,
    layer_remove = function(a) S.layers[a.id] = nil; return {} end,
    bar_register = function(a)
      for k in pairs(a) do assert(k == "id" or k == "label" or k == "current" or k == "max", "bar field " .. k) end
      S.bars[a.id] = deepcopy(a); return {}
    end,
    bar_remove = function(a) S.bars[a.id] = nil; return {} end,
  })
  game.audio = wrap("audio", {se_play = function() return {} end})
  game.scripts = wrap("scripts", {register_function = function(def, fn) S.exported = fn; return {id = def.id} end})

  local moonmod = {
    log = function(level, msg) S.log[#S.log + 1] = level .. ": " .. msg end,
    on = function(name, cb) S.callbacks[name] = S.callbacks[name] or {}; table.insert(S.callbacks[name], cb) end,
    settings = {get = function(id) return S.settings[id] end},
    storage = {
      get = function(k) return deepcopy(S.storage[k]) end,
      set = function(k, v) S.storage[k] = deepcopy(v) end,
    },
  }

  -- Harness controls ------------------------------------------------------------------
  function S.kill(m, scripted)
    m.alive = false
    m.hp = 0
    -- native ABS goes to the active weapon
    local c = S.active
    local w = S.weapons[c][S.equipped[c]]
    if w and not scripted then w.abs = w.abs + m.exp end
    S.pending_events = S.pending_events or {}
    S.pending_events[#S.pending_events + 1] = {"game.enemy_defeated", {entity = m.handle, reward_exp = m.exp, reward_money = m.money, native_model_id = m.model}}
  end
  function S.spawn_floor(warden_floor)
    S.monsters = {}
    local n = 6
    for i = 1, n do
      local h = "m" .. S.next_handle; S.next_handle = S.next_handle + 1
      S.monsters[i] = {handle = h, hp = 40, max_hp = 40, defense = 4, exp = 6, money = 10, drop = (i == n) and 180 or -1, revealed = false, alive = true, model = i}
    end
    S.atla = {"a1"}
  end
  function S.reveal_all() for _, m in ipairs(S.monsters) do m.revealed = true end end
  function S.enter(dungeon, floor_no, back)
    S.emit("game.dungeon.generating", {dungeon_id = dungeon, floor_id = floor_no, back_floor = back or false})
    S.context, S.dungeon, S.floor, S.back = "dungeon", dungeon, floor_no, back or false
    S.seed = S.seed + 1
    S.spawn_floor()
  end
  -- The engine's sandbox redirect: leaving the dungeon goes to the title and ends the session.
  function S.to_town()
    S.monsters = {}
    if S.session then
      local reason = S.session.ending or "left_dungeon"
      local owner, mode = S.session.owner, S.session.mode
      S.session = nil
      S.context, S.dungeon, S.floor = "title", nil, nil
      S.fresh_save(1)
      S.pending_events = S.pending_events or {}
      S.pending_events[#S.pending_events + 1] = {"game.session.ended", {kind = "sandbox", owner = owner, mode = mode, reason = reason}}
      S.open_mode = mode   -- the title reopens the mode's screen
      S.emit("game.title.opened", {mode = "gauntlet"})
      return
    end
    S.context, S.dungeon, S.floor = "georama", nil, nil
  end
  function S.game_over() if S.session then S.session.ending = S.session.ending or "defeat" end; S.to_town() end
  function S.open_title_mode()
    S.context = "title"
    S.open_mode = "moonmod.roguelike:gauntlet"
    S.emit("game.title.opened", {mode = "gauntlet"})
  end
  function S.page() return S.title_modes.gauntlet end
  function S.select(entry)
    S.emit("game.title.selected", {mode = "gauntlet", entry = entry})
    if S.session_request then
      local r = S.session_request; S.session_request = nil
      S.fresh_save(r.party_size, r.character)
      S.session = {owner = "moonmod.roguelike", mode = S.open_mode}
      S.open_mode = nil
      S.context = "loading"
      S.pending_jump = {dungeon = r.floor[1], floor = r.floor[2]}
    end
  end
  function S.tick(n)
    for _ = 1, (n or 1) do
      S.frame = S.frame + 1
      if S.pending_jump and S.frame % 5 == 0 then
        local j = S.pending_jump; S.pending_jump = nil
        if j.town then S.to_town() else S.enter(j.dungeon, j.floor) end
      end
      if S.pending_events then
        local ev = S.pending_events; S.pending_events = nil
        for _, e in ipairs(ev) do S.emit(e[1], e[2]) end
      end
      S.emit("game.tick", {frame = S.frame})
    end
  end
  function S.exit_gate() S.enter(S.dungeon, S.floor + 1) end
  function S.kill_all(scripted) for _, m in ipairs(S.monsters) do if m.alive then S.kill(m, scripted) end end end
  function S.action(id) S.emit("ui.action", {id = id}) end
  function S.last_toast() return S.toasts[#S.toasts] end
  function S.find_toast(pat) for i = #S.toasts, 1, -1 do if S.toasts[i]:find(pat) then return S.toasts[i] end end end

  S.game, S.moonmod = game, moonmod
  return S
end

function F.load_mod(S, path)
  local env = setmetatable({game = S.game, moonmod = S.moonmod}, {__index = _G})
  local chunk = assert(loadfile(path, "t", env))
  chunk()
  return env
end

return F
