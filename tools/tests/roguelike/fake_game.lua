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

-- The seven playable ids in engine order; Opar (6) joins only a party of seven and fights as Toan (his weapons).
-- The playable characters in engine order: the six, then those characters.register_playable adds (Opar's the first).
local IDS = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
local FIGHTS_AS = {}

function F.new(opts)
  opts = opts or {}
  local S = {
    frame = 0,
    context = "title", dungeon = nil, floor = nil, back = false, seed = 1,
    floor_counts = {[0] = 15, 17, 18, 18, 15},
    registered = {},           -- qualified id -> record
    empty_floors = {},         -- "dungeon:native floor" registered with nothing to fight
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
    bind_context = {}, contexts = {}, blocked = nil,
    floor_label = nil, hud_icons = {}, overrides = {},
    toast_icons = {},
    atla = {},
    ranks = {},
    slot_id = {slot_id = 1, slot_generation = 7},
    modifiers = {},
    limit_zones = {},
    input_pressed = {}, input_down = {},
    calls = {},
    fail_ops = opts.fail_ops or {},
  }
  for i = #IDS, 7, -1 do FIGHTS_AS[IDS[i]] = nil; IDS[i] = nil end -- a fresh game has only the six until a mod registers more
  for _, c in ipairs(IDS) do
    S.hp[c], S.max_hp[c] = 120, 120
    S.weapons[c] = {}
  end
  -- weapon catalog: per character three weapons, item numbers by character
  local catalog = {}
  local base = {toan = 258, xiao = 300, goro = 315, ruby = 332, ungaga = 348, osmond = 364} -- each character's first weapon
  for c, no in pairs(base) do
    for i = 0, (c == "osmond" and 5 or 14) do
      catalog[#catalog + 1] = {id = "chronicle:weapon:" .. (no + i), native_item_no = no + i, owner = c, mod_owned = false, name = "Blade" .. (no + i),
        stats = {attack = 10 + i * 15, endurance = 5, speed = 5, magic = 2, durability = 30 + i * 10}, socket_count = 3}
    end
  end
  S.catalog = catalog
  local function def_of(no) for _, d in ipairs(catalog) do if d.native_item_no == no then return d end end end
  -- registered weapons (weapons.register) go by the mod's id, the game's by chronicle:weapon:<n>
  S.reg_ids, S.reg_nos = {}, {}
  local function wid(no) return S.reg_nos[no] or "chronicle:weapon:" .. no end
  local function parse_wid(id) return S.reg_ids[tostring(id)] or tonumber(tostring(id):match("(%d+)$")) end
  local function new_weapon(no, level)
    local d = def_of(no)
    return {item_no = no, level = level or 0, abs = 0, attack = d.stats.attack, endurance = 5, speed = 5, magic = 2,
            durability = d.stats.durability, durability_f = d.stats.durability, elem = {0, 0, 0, 0, 0}, attach = {}}
  end
  -- A new game's save: everyone has start HP, only Toan a weapon (his first). session.start gives the rest theirs.
  local function fresh_save(party_size, start)
    S.party = {}
    for i, c in ipairs(IDS) do
      S.weapons[c] = {}
      S.equipped[c] = nil
      S.hp[c], S.max_hp[c] = 70 + i * 5, 70 + i * 5
      if i <= party_size then
        S.party[#S.party + 1] = c
        S.weapons[c][0] = new_weapon(base[FIGHTS_AS[c] or c], 0)
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
  function S.menu_row(tab, row)
    for _, t in ipairs(S.menu and S.menu.tabs or {}) do
      if t.id == tab then for _, r in ipairs(t.rows or {}) do if r.id == row then return r end end end
    end
  end
  function S.menu_use(tab, row)
    local r = assert(S.menu_row(tab, row), "no menu row " .. tab .. "/" .. row)
    assert(r.enabled ~= false, "menu row is disabled: " .. tab .. "/" .. row)
    emit("ui.run_menu_action", {tab = tab, row = row})
  end
  function S.pick(index)
    local c = assert(S.choice, "no choice panel open")
    S.choice = nil
    emit("ui.choice_made", {id = c.id, index = index, cancelled = index == nil})
  end

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
    notify = function(a)
      assert(a.duration_frames == 300, "notices show for five seconds: " .. tostring(a.duration_frames))
      assert(a.icon == nil or a.icon == "curse" or S.overrides[a.icon], "notice icon: " .. tostring(a.icon))
      -- the message window's font has no slash (it shows "?")
      assert(not a.message:find("/", 1, true), "a notice has a slash: " .. a.message)
      S.toasts[#S.toasts + 1] = a.message; S.toast_icons[#S.toasts] = a.icon; return {queued = true}
    end,
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
    -- The choice panel: one at a time, in a dungeon; S.pick(n) answers it as the player would.
    choice_open = function(a)
      assert(type(a.id) == "string" and #a.id >= 1 and #a.id <= 48, "choice id")
      assert(type(a.title) == "string" and #a.title >= 1 and #a.title <= 64, "choice title")
      assert(a.subtitle == nil or #a.subtitle <= 96, "choice subtitle")
      assert(type(a.options) == "table" and #a.options >= 1 and #a.options <= 4, "choice options 1-4")
      for _, o in ipairs(a.options) do
        assert(type(o.title) == "string" and #o.title >= 1 and #o.title <= 48, "option title")
        assert(o.subtitle == nil or #o.subtitle <= 64, "option subtitle")
        assert(#(o.lines or {}) <= 10, "option lines")
        for _, l in ipairs(o.lines or {}) do
          local text = type(l) == "table" and l.text or l
          assert(type(text) == "string" and #text <= 96, "option line")
          assert(type(l) ~= "table" or l.tone == nil or ({good = 1, bad = 1, dim = 1, gold = 1})[l.tone], "line tone")
        end
      end
      if S.context ~= "dungeon" then return fail("failed", "not in a dungeon") end
      if S.choice then return fail("failed", "a choice panel is already open") end
      S.choice = deepcopy(a); S.choice_opened = S.frame; return {id = a.id}
    end,
    choice_close = function() S.choice = nil; return {closed = true} end,
    boss_card = function(a)
      assert(type(a.name) == "string" and #a.name >= 1 and #a.name <= 40, "boss card name")
      assert(a.kicker == nil or #a.kicker <= 48, "boss card kicker")
      assert(a.epithet == nil or #a.epithet <= 64, "boss card epithet")
      assert(a.frames == nil or (a.frames >= 30 and a.frames <= 600), "boss card frames")
      S.boss_cards = S.boss_cards or {}; S.boss_cards[#S.boss_cards + 1] = deepcopy(a); return {frames = a.frames or 180}
    end,
    -- The run menu: S.menu holds the last one set; S.menu_use(tab, row) is the player using a row.
    run_menu_set = function(a)
      assert(type(a.title) == "string" and #a.title >= 1 and #a.title <= 48, "menu title")
      assert(type(a.tabs) == "table" and #a.tabs >= 1 and #a.tabs <= 6, "menu tabs 1-6")
      for _, t in ipairs(a.tabs) do
        assert(type(t.id) == "string" and #t.id <= 32 and type(t.title) == "string" and #t.title <= 24, "tab id/title")
        assert(#(t.lines or {}) <= 8, "tab lines")
        for _, l in ipairs(t.lines or {}) do assert(type(l) == "string" and #l <= 96, "tab line: " .. tostring(l)) end
        assert(#(t.rows or {}) <= 64, "tab rows")
        for _, r in ipairs(t.rows or {}) do
          assert(type(r.id) == "string" and #r.id >= 1 and #r.id <= 32, "row id")
          assert(type(r.label) == "string" and #r.label >= 1 and #r.label <= 48, "row label: " .. tostring(r.label))
          assert(r.value == nil or #r.value <= 24, "row value: " .. tostring(r.value))
          assert(r.detail == nil or #r.detail <= 240, "row detail too long: " .. tostring(r.label))
          assert(r.tone == nil or ({good = 1, bad = 1, dim = 1, gold = 1})[r.tone], "row tone")
        end
      end
      S.menu = deepcopy(a); S.menu_sets = (S.menu_sets or 0) + 1; return {set = true}
    end,
    run_menu_clear = function() S.menu = nil; return {cleared = true} end,
    run_menu_open = function(a) if not S.menu then return fail("failed", "no run menu") end; S.menu_open = a and a.tab or true; return {opening = true} end,
    run_menu_close = function() S.menu_open = nil; return {closing = true} end,
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
      if a.sky then
        -- the engine's limits (moonmod/title_modes.cpp ReadSky)
        local sky = a.sky
        assert(#sky.groups >= 1 and #sky.groups <= 16, "sky groups 1-16: " .. #sky.groups)
        assert(#sky.nodes >= 1 and #sky.nodes <= 200, "sky nodes 1-200: " .. #sky.nodes)
        assert(#(sky.texts or {}) <= 24, "sky texts at most 24")
        assert(#(sky.top or {}) <= 3, "sky top at most 3 lines")
        local groups, ids = {}, {}
        for _, g in ipairs(sky.groups) do assert(#g.name <= 32 and not groups[g.id], "sky group " .. g.id); groups[g.id] = true end
        for _, n in ipairs(sky.nodes) do assert(not ids[n.id], "duplicate sky node " .. n.id); ids[n.id] = true end
        local limits = {label = 32, rank = 12, icon = 240, title = 64, tag = 32, text = 160, needs = 96, cost = 48}
        for _, n in ipairs(sky.nodes) do
          assert(groups[n.group], "sky node " .. n.id .. " names no group")
          assert(n.state == "locked" or n.state == "open" or n.state == "owned", "sky node state " .. tostring(n.state))
          for k, limit in pairs(limits) do assert(n[k] == nil or #n[k] <= limit, "sky node " .. n.id .. " " .. k .. " too long") end
          assert(#(n.links or {}) <= 4, "sky node " .. n.id .. " has more than 4 links")
          -- an empty Lua table is encoded as a JSON object, which the engine refuses as links
          assert(n.links == nil or #n.links > 0, "sky node " .. n.id .. " sends empty links")
          for _, l in ipairs(n.links or {}) do assert(ids[l], "sky node " .. n.id .. " links to unknown " .. l) end
          assert(math.abs(n.x) <= 8000 and math.abs(n.y) <= 8000, "sky node " .. n.id .. " off the sky")
        end
        for _, l in ipairs(sky.top or {}) do assert(#l <= 64, "sky top line too long: " .. l) end
      elseif a.entries then
        m.sky = nil -- a list page in place of the sky
      end
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
      local ids = IDS
      local index = 1; for i, c in ipairs(ids) do if c == a.character then index = i end end
      if (a.party_size or 1) > #ids then return fail("invalid_argument", "party_size beyond the playable characters") end
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
        -- an empty `enemies` list registers a floor with nothing to fight
        if type(f.enemies) == "table" and #f.enemies == 0 then S.empty_floors[def.dungeon .. ":" .. (count + i - 1)] = true end
      end
      S.floor_counts[def.dungeon] = count + #def.floors
      rec.dungeon = def.dungeon
      S.registered[q] = rec
      return deepcopy(rec)
    end,
    get = function(id) local r = S.registered["moonmod.roguelike:" .. id] or S.registered[id]; if not r then return fail("failed", "unknown") end; return deepcopy(r) end,
    set_character_blocks = function(a)
      for k in pairs(a) do assert(k == "characters", "set_character_blocks field " .. k) end
      if a.characters then
        assert(#a.characters <= 6, "set_character_blocks up to six")
        for _, c in ipairs(a.characters) do assert(S.max_hp[c], "set_character_blocks names a character: " .. tostring(c)) end
      end
      S.char_blocks = a.characters and deepcopy(a.characters) or nil
      return {characters = a.characters}
    end,
    set_warden_room = function(a)
      for k in pairs(a) do assert(k == "enabled" or k == "lock_in", "set_warden_room field " .. k) end
      assert(type(a.enabled) == "boolean", "set_warden_room enabled")
      S.warden_room = a.enabled and {lock_in = a.lock_in == true} or nil
      return {enabled = a.enabled, state = "none"}
    end,
    lighting_set = function(a)
      for k in pairs(a) do assert(k == "side" or k == "fog" or k == "background" or k == "ambient", "lighting_set field " .. k) end
      assert(a.side == nil or a.side == "front" or a.side == "back" or a.side == "both", "lighting_set side")
      S.lighting = a
      return {side = "front"}
    end,
    warden_room_get = function() return {state = S.warden_room_state or "none", center = {x = 800, y = 0, z = 800}} end,
    set_rest_room = function(a)
      for k in pairs(a) do assert(k == "enabled", "set_rest_room field " .. k) end
      assert(type(a.enabled) == "boolean", "set_rest_room enabled")
      S.rest_room = a.enabled
      return {enabled = a.enabled, state = "none"}
    end,
    -- the rest floor's spring stands against the hall's top wall
    rest_room_get = function()
      local r = S.rest_built
      if not (r and r.dungeon == S.dungeon and r.floor == S.floor and not S.back and not S.building) then return {enabled = S.rest_room == true, state = "none"} end
      return {enabled = S.rest_room == true, state = "rest", spring = {x = 960, y = 0, z = 480}, stairs = {x = 2240, y = 0, z = 640},
              center = {x = 880, y = 0, z = 880}, size = {x = 960, z = 960}}
    end,
    back_floor_get = function()
      local id = "chronicle:item:" .. (S.gate_key or 194)
      return {active = S.back, available = true, gate_key = {id = id, native_item_no = S.gate_key or 194, held = (S.items[id] or 0) > 0, count = S.items[id] or 0}}
    end,
    warden_room_release = function()
      if not S.warden_room then return fail("failed", "not sealing") end
      S.warden_room_state = "released"; S.warden_released = (S.warden_released or 0) + 1
      return {state = "released"}
    end,
    set_backrooms = function(a)
      assert(type(a.free) == "boolean", "set_backrooms free")
      assert(a.title == nil or #a.title <= 64, "set_backrooms title")
      assert(a.text == nil or #a.text <= 96, "set_backrooms text")
      for k in pairs(a) do assert(k == "free" or k == "title" or k == "text" or k == "stay" or k == "lines", "set_backrooms field " .. k) end
      assert(a.stay == nil or type(a.stay) == "boolean", "set_backrooms stay")
      assert(a.lines == nil or #a.lines <= 2, "set_backrooms up to two lines")
      for _, line in ipairs(a.lines or {}) do assert(type(line) == "string" and #line >= 1 and #line <= 64, "set_backrooms line 1-64 bytes: " .. tostring(line)) end
      S.backrooms = a.free and deepcopy(a) or nil
      return {free = a.free}
    end,
    set_weapon_drops = function(a)
      for k in pairs(a) do assert(k == "unique" or k == "rare" or k == "large_chests", "set_weapon_drops field " .. k) end
      S.weapon_drops = next(a) and deepcopy(a) or nil
      return {unique = a.unique == true, rare = a.rare or 0, large_chests = a.large_chests or 12}
    end,
    set_shortcuts = function(a)
      assert(math.type(a.count) == "integer" and a.count >= 0 and a.count <= 7, "set_shortcuts count 0-7")
      S.shortcuts = a.count
      return {count = a.count, effective = a.count}
    end,
    shortcuts_get = function()
      local doors = {}
      for i = 1, S.shortcuts or 0 do doors[i] = {x = i, y = i, key = "chronicle:item:" .. (216 + i), key_item = 216 + i, locked = true} end
      return {requested = S.shortcuts or 0, doors = doors}
    end,
    floor_redirect = function(a)
      assert(math.type(a.dungeon_id) == "integer" and math.type(a.floor_id) == "integer", "floor_redirect ids")
      assert(a.floor_id >= ((S.retail_floors or {})[a.dungeon_id] or 0), "floor_redirect: a registered floor")
      S.redirects = S.redirects or {}
      S.redirects[a.dungeon_id .. ":" .. a.floor_id] = a.to_floor_id
      return {floor_id = a.floor_id, to_floor_id = a.to_floor_id}
    end,
    floor_rules_get = function(a) local k = a.dungeon_id .. ":" .. a.floor_id; local z = S.limit_zones[k] or 0; return {limit_zone = z, limit_zone_name = z == -1 and "none" or "toan_only"} end,
    floor_rules_set = function(a) S.limit_zones[a.dungeon_id .. ":" .. a.floor_id] = a.limit_zone; return {limit_zone = a.limit_zone, limit_zone_name = a.limit_zone == -1 and "none" or "custom"} end,
    set_modifiers = function(a) S.modifiers = deepcopy(a); return {} end,
  })
  game.world = wrap("world", {
    dungeon_npc_set = function(a)
      assert(type(a.id) == "string" and #a.id <= 32 and type(a.model) == "string" and a.model:match("%.chr$"), "dungeon_npc_set")
      assert(a.place == nil or a.place == "exit" or a.place == "player", "dungeon_npc_set place")
      if not in_dungeon() then return fail("failed", "not in a dungeon") end
      S.npc = deepcopy(a); return {id = a.id}
    end,
    dungeon_npc_clear = function() S.npc = nil; return {cleared = true} end,
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
    status_remove = function(a)
      assert(({freeze = 1, stamina = 1, poison = 1, curse = 1, goo = 1})[a.status], "player.status_remove: a Chronicle ailment")
      S.ailments = S.ailments or {}
      local had = S.ailments[a.status] == true
      S.ailments[a.status] = nil
      return {status = a.status, removed = had, active = false}
    end,
    get = function()
      if S.context == "title" then return fail("failed", "no save") end
      local c = S.active
      local r = {character = c, hp = S.hp[c], max_hp = S.max_hp[c], water = 50, max_water = 100}
      local slot = S.equipped[c]
      local w = slot and S.weapons[c][slot]
      if w then r.weapon = {id = wid(w.item_no), item_no = w.item_no, slot = slot, attack = w.attack, endurance = w.endurance, speed = w.speed, durability = w.durability_f, durability_max = w.durability} end
      if in_dungeon() then r.position = deepcopy(S.player_pos or {x = 0, y = 0, z = 0}) end
      return r
    end,
    set = function(a)
      local c = a.character or S.active
      local fields = (a.hp and 1 or 0) + (a.max_hp and 1 or 0) + (a.water and 1 or 0)
      assert(fields == 1, "player.set takes exactly one field")
      if not S.max_hp[c] then return fail("invalid_argument", "character") end
      if a.max_hp then
        assert(math.type(a.max_hp) == "integer" and a.max_hp >= 1 and a.max_hp <= 999, "player.set max_hp")
        S.max_hp[c] = a.max_hp; S.hp[c] = math.min(S.hp[c], a.max_hp); return {max_hp = a.max_hp}
      end
      if a.water then assert(math.type(a.water) == "integer" and a.water >= 0, "player.set water"); return {water = a.water} end
      assert(math.type(a.hp) == "integer" and a.hp >= 0, "player.set hp")
      S.hp[c] = math.min(a.hp, S.max_hp[c]); return {hp = S.hp[c]}
    end,
    tuning_set = function(a)
      for k, v in pairs(a) do
        if k == "map_reveal" or k == "monster_reveal" or k == "map_hidden" then assert(type(v) == "boolean")
        elseif k == "swap_delay" then assert(type(v) == "number" and v >= 0 and v <= 4, "swap_delay 0-4")
        elseif k == "dodge_power" then assert(v == 0 or (type(v) == "number" and v >= 0.25 and v <= 4), "dodge_power 0 or 0.25-4")
        elseif k == "dodge_invincible_frames" then assert(math.type(v) == "integer" and v >= 0 and v <= 60, "dodge frames")
        elseif k == "dodge_hop" or k == "shots_pierce" or k == "first_person" then assert(type(v) == "boolean")
        elseif k == "extra_shots" then assert(math.type(v) == "integer" and v >= 0 and v <= 2, "extra_shots 0-2")
        elseif k == "status_immune" then
          assert(type(v) == "table" and #v > 0, "status_immune: a non-empty list (an empty table is a JSON object)")
          for _, n in ipairs(v) do assert(({freeze = 1, stamina = 1, poison = 1, curse = 1, goo = 1})[n], "ailment " .. tostring(n)) end
        elseif k == "invincible_bonus_frames" then assert(math.type(v) == "integer" and v >= 0 and v <= 120, "inv frames")
        else assert(type(v) == "number" and v >= 0.25 and v <= 4, "tuning " .. k .. "=" .. tostring(v)) end
      end
      S.tuning = deepcopy(a); return {tuning = a}
    end,
    tuning_clear = function() S.tuning = nil; return {} end,
    fatal_guard = function(a)
      assert(math.type(a.charges) == "integer" and a.charges >= 0 and a.charges <= 99, "fatal_guard charges")
      S.guards = S.guards or {}
      for _, c in ipairs(IDS) do if not a.character or a.character == c then S.guards[c] = a.charges end end
      return {charges = deepcopy(S.guards)}
    end,
    invincible = function(a) if not in_dungeon() then return fail("failed", "town") end; return {frames = a.frames} end,
    moves_set = function(a)
      assert(type(a.moves) == "table" and #a.moves <= 160, "moves_set takes up to 160 moves")
      local seen = {}
      for _, m in ipairs(a.moves) do
        assert(type(m.id) == "string" and #m.id <= 40, "move id")
        assert(m.trigger == "run_attack" or m.trigger == "guard_attack" or m.trigger == "dodge" or m.trigger == "dodge_back" or
               m.trigger == "heavy" or m.trigger == "combo_finisher" or m.trigger == "lock_attack" or m.trigger == "evade_attack" or
               (m.trigger == "charge_release" and (m.character == "toan" or m.character == "opar")),  -- Opar fights as Toan
               "move trigger " .. tostring(m.trigger))
        if m.trigger == "combo_finisher" then
          assert(math.type(m.chain) == "integer" and m.chain >= 1 and m.chain <= 6, "a combo_finisher's chain is 1..6")
        else
          assert(m.chain == nil, "chain is for a combo_finisher")
        end
        if m.trigger == "lock_attack" then
          assert(m.direction == "toward" or m.direction == "away", "a lock_attack's direction is toward or away")
        else
          assert(m.direction == nil, "direction is for a lock_attack")
        end
        assert((m.from or 0) < (m.to or 1), "move from below to")
        -- the engine plays the first move of a kind it finds, so the mod gives each (character, trigger, variant) one
        -- (a charge_release by its least charge: the first listed that the charge reaches plays)
        local key = table.concat({m.character, m.trigger, tostring(m.chain), tostring(m.direction),
                                  tostring(m.trigger == "charge_release" and m.min_charge or nil)}, "/")
        assert(not seen[key], "two moves on " .. key)
        seen[key] = true
        if m.animation then
          assert(S.animations[m.animation], "move animation not registered: " .. m.animation)
        else
          assert(math.type(m.motion) == "integer" and m.motion >= 0 and m.motion <= 63, "move motion")
        end
        assert((m.spin_from == nil) == (m.spin_to == nil) and (m.spin_from or 0) < (m.spin_to or 1), "move spin window")
        if m.cancel ~= nil or m.cancel_after ~= nil then
          assert(m.trigger == "dodge" or m.trigger == "dodge_back", "cancel is for evades")
          assert(m.cancel == nil or type(m.cancel) == "boolean", "move cancel")
          assert(m.cancel_after == nil or (m.cancel_after >= 0 and m.cancel_after <= 60), "move cancel_after")
        end
        assert(#(m.hits or {}) <= 12 and #(m.cues or {}) <= 12, "move hits and cues")
        for _, h in ipairs(m.hits or {}) do
          assert(h.at >= 0 and h.at <= 1 and (h.radius or 8) <= 40, "move hit")
          assert(h.shot or (h.count == nil and h.spread == nil and h.speed == nil), "count, spread and speed are for a shot")
          assert((h.count or 1) >= 1 and (h.count or 1) <= 5 and (h.spread or 0) <= 45, "move shot")
          assert(h.shot or (h.from == nil and h.from_ahead == nil and h.from_rise == nil and h.cell == nil and h.size == nil),
                 "from, from_ahead, from_rise, cell and size are for a shot")
          assert(h.from == nil or (type(h.from) == "string" and #h.from >= 1 and #h.from <= 15), "a shot's from is a frame name")
          assert(math.abs(h.from_ahead or 0) <= 10 and math.abs(h.from_rise or 0) <= 10, "a shot's from_ahead and from_rise")
          assert(h.cell == nil or (math.type(h.cell) == "integer" and h.cell >= 0 and h.cell <= 15), "a shot's cell is 0..15")
          assert(h.size == nil or (h.size >= 0.3 and h.size <= 4), "a shot's size is 0.3..4")
        end
      end
      S.moves = deepcopy(a.moves)
      return {moves = #a.moves}
    end,
    moves_clear = function() S.moves = nil; return {} end,
    -- a form (player.form_set): the active character's model from a mod pack, frames standing in for his own
    form_set = function(a)
      assert(type(a.pack) == "string" and a.pack:match("^dun/mainchara/[%w_]+%.chr$"), "form_set pack")
      assert(S.overrides == nil or S.overrides[a.pack], "form_set pack is not a resource override: " .. a.pack)
      for k, v in pairs(a.frames or {}) do assert(type(k) == "string" and type(v) == "string", "form_set frames") end
      assert(a.scale == nil or (a.scale >= 0.1 and a.scale <= 4), "form_set scale")
      if not in_dungeon() then return fail("failed", "a form needs an active dungeon scene") end
      if S.form_busy then return fail("failed", "the native game is in an action") end
      S.form = {character = S.active, pack = a.pack, frames = deepcopy(a.frames), scale = a.scale}
      S.forms_taken = (S.forms_taken or 0) + 1
      S.last_form = deepcopy(S.form)
      return {character = S.active, pack = a.pack}
    end,
    form_clear = function() local had = S.form ~= nil; S.form = nil; return {changed = had} end,
    -- a chained move (player.move_play): one of the mod's own, started at once
    move_play = function(a)
      local found
      for _, m in ipairs(S.moves or {}) do if m.id == a.id then found = m end end
      assert(found, "move_play: no such move " .. tostring(a.id))
      S.played = S.played or {}
      S.played[#S.played + 1] = {id = a.id, form = S.form and S.form.pack}
      return {id = a.id}
    end,
    heal = function(a) local c = a.character or S.active; S.hp[c] = math.min(S.max_hp[c], S.hp[c] + a.amount); return {hp = S.hp[c]} end,
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
    status_add = function(a)
      assert(a.status == "slow" or a.status == "stop", "combat.status_add: slow or stop")
      assert(math.type(a.duration_frames) == "integer" and a.duration_frames >= 1 and a.duration_frames <= 32767, "duration_frames")
      for _, m in ipairs(S.monsters) do
        if m.handle == a.entity and m.alive and m.revealed then m.stopped = math.max(m.stopped or 0, a.duration_frames); return {status = a.status} end
      end
      return fail("failed", "stale")
    end,
  })
  game.entities = wrap("entities", {
    query = function()
      if not in_dungeon() then return fail("failed", "not in dungeon") end
      local out = {}
      for _, m in ipairs(S.monsters) do
        if m.alive then
          out[#out + 1] = {id = "slot" .. m.handle, entity_id = m.handle, revealed = m.revealed, native_model_id = m.model,
            position = m.position or {x = 600 * (tonumber(tostring(m.handle):match("%d+")) or 0), y = 0, z = 0},
            health = {current = m.hp, maximum = m.max_hp}, combat = {defense = m.defense, reward_exp = m.exp, reward_money = m.money, drop_item = m.drop}}
        end
      end
      return {entities = out}
    end,
    get = function(h)
      for _, m in ipairs(S.monsters) do
        if m.handle == h then
          -- As Chronicle: a defeat moves the slot's handle on at once, so a fallen monster's handle reads expired.
          if not m.alive then return {status = "expired"} end
          return {status = "alive", health = {current = m.hp, maximum = m.max_hp}, position = {x = 20 * (tonumber(m.handle:match("%d+")) or 0), y = 0, z = 0}}
        end
      end
      return {status = "expired"}
    end,
    set_stats = function(a)
      for _, m in ipairs(S.monsters) do
        if m.handle == a.entity then
          if not m.revealed then return fail("failed", "unrevealed") end
          -- any subset of the stats, as the engine takes them
          local max_hp = a.max_hp or m.max_hp
          assert(max_hp >= 1 and max_hp <= 1000000 and (a.hp or 0) <= max_hp, "hp bounds")
          for _, k in ipairs({"max_hp", "hp", "defense", "reward_exp"}) do assert(a[k] == nil or math.type(a[k]) == "integer", k .. " integer") end
          assert(a.defense == nil or (a.defense >= 0 and a.defense <= 32767), "defense bounds")
          assert(a.reward_exp == nil or (a.reward_exp >= 0 and a.reward_exp <= 32767), "exp bounds")
          m.max_hp, m.hp = max_hp, a.hp or (a.max_hp and math.max(1, m.hp * a.max_hp // m.max_hp)) or m.hp
          m.defense, m.exp, m.money = a.defense or m.defense, a.reward_exp or m.exp, a.reward_money or m.money
          if a.drop_item then m.drop = a.drop_item end
          if a.hit_reach ~= nil then
            assert(type(a.hit_reach) == "number" and a.hit_reach >= 0 and a.hit_reach <= 200, "hit_reach 0-200")
            m.hit_reach = a.hit_reach
          end
          if a.hit_share ~= nil then
            assert(type(a.hit_share) == "boolean", "hit_share boolean")
            m.hit_share = a.hit_share
          end
          if a.damage_scale ~= nil then
            assert(type(a.damage_scale) == "number" and a.damage_scale >= 0 and a.damage_scale <= 100, "damage_scale 0-100")
            m.damage_scale = a.damage_scale
          end
          if a.max_hp then m.scaled = (m.scaled or 0) + 1 end
          return {changed = true}
        end
      end
      return fail("failed", "stale")
    end,
    set_active_limit = function(a)
      assert(math.type(a.active) == "integer" and a.active >= 1 and a.active <= 256, "active limit")
      local previous = S.active_limit or 4; S.active_limit = a.active
      return {active = a.active, previous = previous, slots = 256}
    end,
    scale_set = function(a)
      assert(a.scale >= 0.5 and a.scale <= 3)
      local m = S.monster_by_handle and S.monster_by_handle(a.entity)
      if m then m.scale = a.scale end
      return {scale = a.scale}
    end,
    script_int_set = function(a)
      for k in pairs(a) do assert(k == "entity" or k == "index" or k == "value", "script_int_set field " .. k) end
      assert(math.type(a.index) == "integer" and a.index >= 0 and a.index <= 255 and math.type(a.value) == "integer", "script_int_set")
      local m = S.monster_by_handle and S.monster_by_handle(a.entity)
      if not (m and m.alive and m.arena_origin) then return fail("failed", "not a live cast member") end
      S.script_ints = S.script_ints or {}
      S.script_ints[#S.script_ints + 1] = {entity = a.entity, index = a.index, value = a.value}
      return {index = a.index, value = a.value}
    end,
    tint = function(a)
      assert(math.type(a.frames) == "integer" and a.frames >= 0 and a.frames <= 3600, "tint frames")
      S.tints[a.entity] = deepcopy(a.color); return {frames = a.frames}
    end,
    knockback = function(a)
      assert(type(a.direction) == "table" and a.speed >= 0.5 and a.speed <= 40, "knockback")
      S.knocks[#S.knocks + 1] = a.entity; return {speed = a.speed}
    end,
  })
  -- Enemy variants a mod registers and spawns (the Warden in its room)
  S.characters, S.spawned = {}, {}
  game.characters = wrap("characters", {
    -- A playable character past the six: the next engine index, kept; registering the same id again updates him.
    register_playable = function(a)
      assert(type(a.id) == "string" and type(a.name) == "string" and a.pack:match("^dun/mainchara/[%w_]+%.chr$"), "register_playable fields")
      for i, c in ipairs(IDS) do
        if c == a.id then
          if i <= 6 then return fail("invalid_argument", "id names one of the game's own characters") end
          FIGHTS_AS[c] = a.fights_as or "toan"
          return {id = c, character_id = i - 1, count = #IDS}
        end
      end
      if #IDS >= 16 then return fail("invalid_argument", "every playable character index is taken") end
      IDS[#IDS + 1] = a.id
      FIGHTS_AS[a.id] = a.fights_as or "toan"
      S.hp[a.id], S.max_hp[a.id], S.weapons[a.id] = a.hp or 70, a.hp or 70, {}
      return {id = a.id, character_id = #IDS - 1, count = #IDS}
    end,
    register = function(a)
      assert(a.kind == "enemy" and type(a.id) == "string" and math.type(a.template_monster_id) == "integer", "characters.register enemy")
      assert(#a.name <= 63, "name length")
      local q = "moonmod.roguelike:" .. a.id
      if S.characters[q] then return fail("invalid", "already registered") end
      S.characters[q] = deepcopy(a)
      return {id = q}
    end,
    spawn = function(a)
      if not in_dungeon() then return fail("failed", "not in dungeon") end
      local def = S.characters[a.character]
      if not def then return fail("invalid", "unknown character") end
      assert(type(a.position) == "table" and a.position.x and a.position.z, "spawn position")
      assert(a.grounded == nil or a.arena_origin ~= nil, "grounded goes with arena_origin")
      assert(a.arena_slot == nil or (a.arena_origin ~= nil and math.type(a.arena_slot) == "integer" and a.arena_slot >= 0 and
             a.arena_slot < 16), "arena_slot is 0-15 and goes with arena_origin")
      local model = def.template_monster_id
      local hp = model >= 78 and 2000 or 40
      local h = "m" .. S.next_handle; S.next_handle = S.next_handle + 1
      local m = {handle = h, hp = hp, max_hp = hp, defense = 4, exp = 0, money = 0, drop = -1, revealed = true, alive = true, model = model,
                 spawned = true, arena_origin = a.arena_origin, grounded = a.grounded, arena_slot = a.arena_slot}
      S.monsters[#S.monsters + 1] = m
      S.spawned[#S.spawned + 1] = m
      return {entity_handle = h, stats = {hp = hp, defense = 4}}
    end,
  })
  S.bursts, S.tints, S.knocks = {}, {}, {}
  game.effects = wrap("effects", {
    burst = function(a)
      assert(a.kind == "explosion" or a.kind == "heal" or a.kind == "sparks" or a.kind == "guard" or a.kind == "impact" or a.kind == "smoke", "burst kind")
      assert(type(a.position) == "table" and a.position.x, "burst position")
      S.bursts[#S.bursts + 1] = a.kind
      return {kind = a.kind}
    end,
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
    icon_set = function(a)
      assert(type(a.id) == "string" and a.id:match("^chronicle:item:%d+$"), "icon_set id")
      assert(a.icon == nil or (type(a.icon) == "string" and not a.icon:find("[/%.\\]")), "icon_set stem")
      S.item_icons = S.item_icons or {}
      S.item_icons[a.id] = a.icon
      return {id = a.id}
    end,
    remove = function(a)
      assert(a.count >= 1 and a.count <= 999)
      local had = S.items[a.id] or 0
      local n = math.min(had, a.count)
      S.items[a.id] = had - n
      return {removed = n}
    end,
  })
  game.party = wrap("party", {
    companion_set = function(a)
      for k in pairs(a) do assert(k == "character" or k == "stance" or k == "damage_scale" or k == "shot", "companion_set field " .. k) end
      assert(a.shot == nil or (a.shot.cell >= 0 and a.shot.cell <= 15 and (a.shot.size or 1) >= 0.3 and (a.shot.size or 1) <= 4), "companion shot")
      assert(a.stance == nil or a.stance == "target" or a.stance == "aggressive" or a.stance == "passive", "stance")
      assert(a.damage_scale == nil or (a.damage_scale >= 0 and a.damage_scale <= 10), "damage_scale")
      S.companion = a.character and deepcopy(a) or nil
      return {character = a.character}
    end,
    companion_get = function() return {character = S.companion and S.companion.character, out = S.companion ~= nil} end,
    list = function() local out = {}; for _, c in ipairs(S.party) do out[#out + 1] = {id = c, active = c == S.active, hp = S.hp[c], max_hp = S.max_hp[c]} end; return out end,
    set_active = function(a)
      if not in_dungeon() then return fail("failed", "requires dungeon") end
      local ok = false; for _, c in ipairs(S.party) do if c == a.id then ok = true end end
      if not ok then return fail("failed", "not joined") end
      if S.hp[a.id] <= 0 then return fail("failed", "the target is knocked out") end
      if S.scene_until and S.frame < S.scene_until then return fail("failed", "a scene plays") end
      S.active = a.id; return {changed = true}
    end,
  })
  game.weapons = wrap("weapons", {
    list = function() return deepcopy(S.catalog) end,
    -- a mod's own weapon on a native template: appended item numbers from 377, its model and icon its own files
    register = function(a)
      for k in pairs(a) do
        assert(k == "id" or k == "name" or k == "template_weapon" or k == "owner" or k == "stats" or k == "stat_caps" or
               k == "model" or k == "icon" or k == "description" or k == "menu_scale", "weapons.register field " .. k)
      assert(a.menu_scale == nil or (type(a.menu_scale) == "number" and a.menu_scale >= 0.1 and a.menu_scale <= 4), "menu_scale 0.1-4")
      end
      if a.description then
        local lines = type(a.description) == "string" and {a.description} or a.description
        assert(#lines >= 1 and #lines <= 4, "description is 1-4 lines")
        for _, l in ipairs(lines) do assert(type(l) == "string" and #l >= 1 and #l <= 64, "description line 1-64 bytes: " .. tostring(l)) end
      end
      assert(a.model == nil or (S.overrides or {})[("commenu/weapon/%s.chr"):format(a.model)], "weapon model is not a resource override: " .. tostring(a.model))
      assert(a.icon == nil or (S.overrides or {})[("icons/%s.png"):format(a.icon)], "weapon icon is not a resource override: " .. tostring(a.icon))
      local id = "moonmod.roguelike:" .. a.id
      local no = S.reg_ids[id]
      if not no then
        no = 377 + #S.reg_nos
        while S.reg_nos[no] do no = no + 1 end
        S.reg_ids[id], S.reg_nos[no] = no, id
        local t = def_of(tonumber(a.template_weapon))
        assert(t, "template_weapon")
        -- `owner` a registered character makes him the weapon's holder (its row on the weapon page); to the combat code
        -- and weapons.get it stays the weapon of the character he fights as
        local owner = a.owner and (FIGHTS_AS[a.owner] or a.owner) or t.owner
        catalog[#catalog + 1] = {id = id, native_item_no = no, owner = owner, holder = a.owner, mod_owned = true, name = a.name,
          stats = {attack = a.stats and a.stats.attack or t.stats.attack, endurance = 5, speed = 5, magic = 2,
                   durability = a.stats and a.stats.durability or t.stats.durability}, socket_count = 3, model = a.model, icon = a.icon, description = a.description, menu_scale = a.menu_scale}
      end
      return {id = id, native_item_no = no}
    end,
    definition_set = function(a)
      local d = def_of(tonumber(a.id))
      if not d then return fail("invalid_argument", "id") end
      if a.hole_num then assert(math.type(a.hole_num) == "integer" and a.hole_num >= 0 and a.hole_num <= 6, "hole_num 0-6"); d.socket_count = a.hole_num end
      return {id = d.id}
    end,
    get = function(id)
      local no = parse_wid(type(id) == "table" and id.id or id)
      local d = def_of(no)
      if not d then return fail("failed", "unknown weapon") end
      local r = deepcopy(d)
      r.instances = {}
      for _, c in ipairs(IDS) do
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
      local c = a.character or d.owner
      if d.owner ~= c and d.owner ~= FIGHTS_AS[c] then return fail("failed", "the weapon is not compatible with the selected character") end
      local joined = false; for _, p in ipairs(S.party) do if p == c then joined = true end end
      if not joined then return fail("failed", "not joined") end
      for slot = 0, 10 do
        if not S.weapons[c][slot] then S.weapons[c][slot] = new_weapon(no, 0); return {id = a.id, native_item_no = no, slot = slot, added = true} end
      end
      return fail("failed", "no free slot")
    end,
    equip = function(a)
      if S.context ~= "georama" and not in_dungeon() then return fail("failed", "weapons.equip works only in an active Georama town or dungeon") end
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
    style_set = function(a)
      for k in pairs(a) do assert(k == "character" or k == "slot" or k == "name" or k == "color" or k == "glow" or k == "badge" or k == "details", "style_set field " .. k) end
      local function lines(t, most, what)
        if t == nil then return end
        assert(type(t) == "table" and #t <= most, what .. " is up to " .. most .. " lines")
        for _, l in ipairs(t) do
          local text = type(l) == "table" and l.text or l
          assert(type(text) == "string" and #text <= 64, what .. " line up to 64 bytes: " .. tostring(text))
          assert(type(l) ~= "table" or l.scale == nil or (l.scale >= 0.5 and l.scale <= 1.6), what .. " scale 0.5..1.6")
        end
      end
      lines(a.badge, 3, "badge"); lines(a.details, 5, "details")
      assert(S.weapons[a.character] and S.weapons[a.character][a.slot], "style_set: that slot holds no weapon")
      assert(a.name == nil or #a.name <= 40, "style_set name up to 40 bytes: " .. tostring(a.name))
      for _, k in ipairs({"color", "glow"}) do
        if a[k] then for _, ch in ipairs({"r", "g", "b"}) do assert(math.type(a[k][ch]) == "integer" and a[k][ch] >= 0 and a[k][ch] <= 255, k .. " channel") end end
      end
      S.weapon_styles = S.weapon_styles or {}
      S.weapon_styles[a.character .. ":" .. a.slot] = deepcopy(a)
      return {character = a.character, slot = a.slot}
    end,
    style_clear = function(a)
      S.weapon_styles = S.weapon_styles or {}
      if a and a.character then S.weapon_styles[a.character .. ":" .. a.slot] = nil else S.weapon_styles = {} end
      return {cleared = true}
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
    remove = function(a)
      local w, c, slot = find_weapon(a); if not w then return nil, c end
      if S.equipped[c] == slot then return fail("failed", "the equipped weapon cannot be removed; equip another first") end
      S.weapons[c][slot] = nil; return {removed = true}
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
  game.resources = wrap("resources", {
    override = function(a)
      assert(a.path:match("^resources/") and a.game_path, "resources.override path")
      S.overrides[a.game_path] = a.path; return {game_path = a.game_path}
    end,
  })
  game.input = wrap("input", {
    bind = function(a) S.bind_context[a.id] = a.context or "default"; return {id = a.id} end,
    -- Only actions bound to the context on top report presses; others drop theirs.
    consume = function(a)
      local p = S.input_pressed[a.id]; S.input_pressed[a.id] = nil
      local top = S.contexts[#S.contexts] or "default"
      return {pressed = p == true and (S.bind_context[a.id] or "default") == top}
    end,
    context_push = function(a) S.contexts[#S.contexts + 1] = a.id; return {token = #S.contexts, id = a.id} end,
    context_pop = function(a) table.remove(S.contexts, a.token); return {removed = true} end,
    block_native = function(a) S.blocked = deepcopy(a.buttons); return {frames = a.frames} end,
    state = function(a) return {down = S.input_down[a.id] == true} end,
  })
  game.render = wrap("render", {
    layer_register = function(a)
      assert(#a.text >= 1 and #a.text <= 48, "layer text length")
      assert(a.text:match("^[%w %.,:;/%(%)%+%-_%%'%[%]%?~]+$"), "layer text charset: " .. a.text)
      S.layers[a.id] = a.text; return {}
    end,
    layer_remove = function(a) S.layers[a.id] = nil; return {} end,
    bar_register = function(a)
      for k in pairs(a) do assert(k == "id" or k == "label" or k == "current" or k == "max", "bar field " .. k) end
      S.bars[a.id] = deepcopy(a); return {}
    end,
    bar_remove = function(a) S.bars[a.id] = nil; return {} end,
    floor_label_set = function(a)
      assert(type(a.text) == "string" and #a.text >= 1 and #a.text <= 6, "floor label length: " .. tostring(a.text))
      assert(a.number == nil or (math.type(a.number) == "integer" and a.number >= 1 and a.number <= 99), "floor number")
      S.floor_label, S.floor_number = a.text, a.number; return {text = a.text}
    end,
    floor_label_clear = function(a) assert(a == nil, "floor_label_clear takes no arguments"); S.floor_label, S.floor_number = nil, nil; return {cleared = true} end,
    hud_icon_set = function(a)
      assert((a.icon == nil) ~= (a.image == nil), "exactly one of icon or image")
      if a.image then assert(S.overrides[a.image], "hud image not registered: " .. a.image) end
      S.hud_icons[a.id] = {icon = a.icon, image = a.image, blink = a.blink == true}; return {id = a.id}
    end,
    hud_icon_remove = function(a) local had = S.hud_icons[a.id] ~= nil; S.hud_icons[a.id] = nil; return {removed = had} end,
  })
  game.audio = wrap("audio", {se_play = function() return {} end})
  -- Mod motions: the file has to be a moonmod-motion document in the package.
  S.animations = {}
  game.animations = wrap("animations", {
    player_register = function(a)
      assert(type(a.id) == "string" and #a.id <= 48 and not a.id:find(":"), "animation id")
      assert(type(a.file) == "string" and a.file:match("^resources/.+%.json$"), "animation file")
      local f = io.open(S.mod_root .. "/" .. a.file, "rb")
      if not f then return fail("failed", "the motion file was not found") end
      local text = f:read("a"); f:close()
      assert(text:find('"format":"moonmod-motion"', 1, true) and text:find('"version":1', 1, true), "not a moonmod-motion file: " .. a.file)
      local count = 0
      for id in pairs(S.animations) do if id ~= a.id then count = count + 1 end end
      if count >= 64 then return fail("failed", "a mod registers up to 64 motions") end
      S.animations[a.id] = a.file
      return {id = a.id}
    end,
    player_unregister = function(a) S.animations[a.id] = nil; return {removed = true} end,
  })
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
    S.atla = {}
    if S.empty_floors[tostring(S.dungeon) .. ":" .. tostring(S.floor)] then return end
    local n = 6
    for i = 1, n do
      local h = "m" .. S.next_handle; S.next_handle = S.next_handle + 1
      S.monsters[i] = {handle = h, hp = 40, max_hp = 40, defense = 4, exp = 6, money = 10, drop = (i == n) and 180 or -1, revealed = false, alive = true, model = i}
    end
    S.atla = {"a1"}
  end
  function S.reveal_all() for _, m in ipairs(S.monsters) do m.revealed = true end end
  -- Like the engine, the new floor number shows before the floor is built (generating, a new seed, monsters).
  function S.enter(dungeon, floor_no, back)
    S.context, S.dungeon, S.floor, S.back, S.monsters = "dungeon", dungeon, floor_no, back or false, {}
    S.building = {dungeon = dungeon, floor = floor_no, back = back or false, at = S.frame + 16}
  end
  function S.build_floor()
    local b = S.building; S.building = nil
    S.emit("game.dungeon.generating", {dungeon_id = b.dungeon, floor_id = b.floor, back_floor = b.back})
    S.warden_room_state = S.warden_room and "sealed" or "none"
    S.rest_built = S.rest_room and {dungeon = b.dungeon, floor = b.floor} or nil
    S.spawned = {}
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
  -- Cross (buy), Square (toggle), L1/R1 (rank_down/rank_up) on a sky page's node.
  function S.sky_act(entry, action)
    S.emit("game.title.selected", {mode = "gauntlet", entry = entry, action = action})
  end
  function S.sky_node(id)
    for _, n in ipairs(S.page().sky and S.page().sky.nodes or {}) do if n.id == id then return n end end
  end
  function S.select(entry)
    S.emit("game.title.selected", {mode = "gauntlet", entry = entry})
    if S.session_request then
      local r = S.session_request; S.session_request = nil
      S.fresh_save(r.party_size, "toan") -- the native dungeon start always loads Toan
      S.session = {owner = "moonmod.roguelike", mode = S.open_mode}
      S.open_mode = nil
      S.context = "loading"
      S.pending_jump = {dungeon = r.floor[1], floor = r.floor[2]}
    end
  end
  function S.tick(n)
    for _ = 1, (n or 1) do
      S.frame = S.frame + 1
      -- A player answers a panel eventually: one left open for 250 frames takes its first option, unless a test
      -- turns that off to watch the run wait (S.auto_pick = false).
      if S.auto_pick ~= false and S.choice and S.choice.id ~= "abandon" and S.frame - (S.choice_opened or S.frame) >= 250 then
        S.pick(1)
      end
      if S.pending_jump and S.frame % 5 == 0 then
        local j = S.pending_jump; S.pending_jump = nil
        if j.town then S.to_town()
        else
          -- A queued jump re-enters the dungeon: its entrance reads as floor 0, with Toan loaded, for a while.
          S.context, S.dungeon, S.floor, S.back, S.active, S.monsters = "dungeon", j.dungeon, 0, false, "toan", {}
          S.seed = S.seed + 1
          S.entrance = {dungeon = j.dungeon, floor = j.floor, at = S.frame + 30}
        end
      elseif S.entrance and S.frame >= S.entrance.at then
        local j = S.entrance; S.entrance = nil
        S.enter(j.dungeon, j.floor)
        -- A test can have the floor's entry scene hold the game for a while (no character switching).
        if S.entry_scene then S.scene_until = S.frame + S.entry_scene end
      end
      if S.building and S.frame >= S.building.at then S.build_floor() end
      if S.pending_events then
        local ev = S.pending_events; S.pending_events = nil
        for _, e in ipairs(ev) do S.emit(e[1], e[2]) end
      end
      S.emit("game.tick", {frame = S.frame})
    end
  end
  -- A free back floor's stairs, answered Proceed: the engine reports it (with `stay` it goes nowhere itself).
  function S.take_stairs()
    S.emit("game.dungeon.backroom", {entered = true, frame = S.frame})
    if S.backrooms and not S.backrooms.stay then S.enter(S.dungeon, S.floor, true) end
  end
  -- The exit gate leads to the next floor, unless a mod redirected it (dungeons.floor_redirect).
  function S.exit_gate()
    local to = S.floor + 1
    to = (S.redirects or {})[S.dungeon .. ":" .. to] or to
    S.enter(S.dungeon, to)
  end
  -- A chest hands `character` a weapon: it lands in a free slot and the engine reports the pickup.
  local ORDER = setmetatable({}, {__index = function(_, c) for i, id in ipairs(IDS) do if id == c then return i - 1 end end end})
  function S.pickup_weapon(character, item_no, stats)
    local slot = 0
    while S.weapons[character][slot] do slot = slot + 1 end
    local w = new_weapon(item_no, 0)
    for k, v in pairs(stats or {}) do w[k] = v end
    S.weapons[character][slot] = w
    S.emit("game.item_picked_up", {id = wid(item_no), kind = "weapon", native_item_no = item_no, character = ORDER[character], slot = slot})
    return slot, w
  end
  -- The Warden floor: clear everything outside the sealed room (the floor is swept and the room opens), then walk
  -- in; returns the Wardens the mod placed.
  function S.enter_warden_room()
    S.reveal_all(); S.tick(30)
    S.kill_all(); S.tick(250)
    if S.warden_room_state == "sealed" then
      S.warden_room_state = "open"
      S.emit("game.dungeon.warden_room", {state = "open", center = {x = 800, y = 0, z = 800}}); S.tick(2)
      S.warden_room_state = S.warden_room.lock_in and "shut" or "released"
      S.emit("game.dungeon.warden_room", {state = "entered", center = {x = 800, y = 0, z = 800}, size = {x = 640, z = 640},
                                          shut = S.warden_room.lock_in}); S.tick(30)
    end
    S.tick(5)
    return S.spawned
  end
  function S.monster_by_handle(h) for _, m in ipairs(S.monsters) do if m.handle == h then return m end end end
  function S.kill_all(scripted) for _, m in ipairs(S.monsters) do if m.alive then S.kill(m, scripted) end end end
  function S.action(id) S.emit("ui.action", {id = id}) end
  function S.pickup_item(item_no)
    local id = "chronicle:item:" .. item_no
    S.items[id] = (S.items[id] or 0) + 1
    S.emit("game.item_picked_up", {id = id, kind = "item", native_item_no = item_no, count = 1, source = "native"})
  end
  function S.fatal_hit(c)
    c = c or S.active
    if (S.guards or {})[c] and S.guards[c] > 0 then
      S.guards[c] = S.guards[c] - 1
      S.hp[c] = 1
      S.emit("game.player.guarded", {character = c, charges = S.guards[c]})
      return true
    end
    S.hp[c] = 0
    return false
  end
  function S.last_toast() return S.toasts[#S.toasts] end
  function S.find_toast(pat) for i = #S.toasts, 1, -1 do if S.toasts[i]:find(pat) then return S.toasts[i] end end end

  S.game, S.moonmod = game, moonmod
  return S
end

function F.load_mod(S, path)
  S.mod_root = path:match("^(.*)[/\\]main%.lua$") or "."
  local env = setmetatable({game = S.game, moonmod = S.moonmod}, {__index = _G})
  local chunk = assert(loadfile(path, "t", env))
  chunk()
  return env
end

return F
