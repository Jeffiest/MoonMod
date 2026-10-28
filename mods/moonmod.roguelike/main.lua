-- Dark Genie's Gauntlet: a roguelike game mode for Chronicle, started from the title menu.
--
-- The mod adds a title mode (game.title.mode_register): a row under NEW GAME / LOAD / OPTION that opens
-- the Gauntlet's own title screen, with Start Run, the starting character, Norune Eternal (the unlocks
-- bought with Moon Shards) and Records. Start Run begins a sandbox session (game.session.start): a fresh
-- game that belongs to no save slot, dropped straight onto the first run floor. Nothing in any save file
-- is read or written; the Gauntlet's own progress (Moon Shards, unlocks, Heirloom, records) is this mod's
-- storage. Leaving the dungeon, a game over or the last Warden brings the player back to the Gauntlet's
-- title screen.
--
-- A run is five biomes (Divine Beast Cave, Wise Owl Forest, Shipwreck, Sun and Moon Temple, Moon Sea), each
-- three floors and a Warden floor. The mod appends those four floors to each dungeon with dungeons.register,
-- so the native exit gate carries the player from floor I to II to III to the Warden; the Warden's death
-- moves the run to the next biome with world.transition.
--
--   Cursed Gate   toggle on a floor (G / Actions): the next floor is cursed (tougher enemies and two curses)
--                 and pays a Miracle cache, extra Diorama tiles and Moon Shards.
--   Warden        the gate-key holder on the Warden floor grows into a boss with a HUD bar.
--   Fast ABS      revealed enemies carry several times their ABS, so a weapon builds up inside one run;
--                 benched drafted allies take a share; found weapons arrive pre-leveled with attachments.
--   One weapon    each character carries one weapon all run. A found weapon means a choice: keep the held one
--                 or take the new one, and the other is absorbed into it. A weapon that breaks ends the run.
--   Diorama       Atla, floors and caches give Georama tiles; place them on Journal > Character (Diorama tree)
--                 for run buffs: Rivers, Windmills + Storehouses, Lamps, Trees, Houses, Carts, Smithies.
--   Drafting      the run starts solo (the others start knocked out); a Golden Atla drafts and revives an
--                 ally on floor II of the first and third biome.
--   Eternal       Moon Shards from every run (kept on defeat) buy the Norune Eternal unlocks: Gaffer's Wagon,
--                 Macho's Forge, Heirloom Vault, Dran's Shrine, Deep Well, Matataki Embassy, Moon Blessing,
--                 Whetstone, Gaffer's Oil, Repair Kit.
--
-- API notes: everything here is a Chronicle adapter operation; calls go through try() so an operation the
-- running engine lacks fails quietly. Without title modes (an older engine) the mode cannot start.

local ID = "moonmod.roguelike"
local SHARD_LIMIT = 99999

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end
local function call(fn, ...)
  if type(fn) ~= "function" then return nil, {code = "unsupported", message = "operation missing"} end
  local ok, value, err = pcall(fn, ...)
  if not ok then return nil, {code = "error", message = tostring(value)} end
  return value, err
end
local function errmsg(err) return type(err) == "table" and tostring(err.message) or tostring(err) end
local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= type(fallback) then return fallback end
  return value
end
local function clamp(v, lo, hi) v = tonumber(v) or lo; return math.max(lo, math.min(hi, v)) end
local function toast(message, frames) try(game.ui.notify, {message = tostring(message):sub(1, 196), duration_frames = frames or 240}) end
local function title(id) return (tostring(id):gsub("^%l", string.upper)) end
local function pick(list) if type(list) == "table" and #list > 0 then return list[math.random(#list)] end end
local function contains(list, value) for _, v in ipairs(list or {}) do if v == value then return true end end; return false end

-- Data ------------------------------------------------------------------------------------------------
-- Source floors are 0-based native floors whose enemy layouts the run floors copy. They avoid the floors
-- that hold story bosses (Divine Beast Cave floor 8 is Dran's; each dungeon's last floor is its boss).
local BIOMES = {
  {key = "dbc", dungeon = 0, name = "Divine Beast Cave", sources = {2, 5, 10}, warden = 12},
  {key = "wof", dungeon = 1, name = "Wise Owl Forest", sources = {2, 5, 10}, warden = 13},
  {key = "ship", dungeon = 2, name = "Shipwreck", sources = {2, 5, 11}, warden = 14},
  {key = "temple", dungeon = 3, name = "Sun and Moon Temple", sources = {2, 5, 11}, warden = 14}, -- the overlay font has no "&"
  {key = "sea", dungeon = 4, name = "Moon Sea", sources = {2, 5, 10}, warden = 12},
}
local FLOOR_LABEL = {"I", "II", "III", "WARDEN"}
local WARDEN_SLOT = 4
local CHARACTERS = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
local MODE = "gauntlet"
local HUD_CACHE_IMAGE = "moonmod/roguelike/hud/cache.png" -- resources/hud/cache.png, the Miracle cache chest

-- Item numbers from Chronicle's item table (ps2/include/itemdata.hpp).
local ITEM = {bread = 148, water = 146, repair = 177, antidote = 151, holy_water = 152}
local GEMS = {96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107}
local ATTACHMENTS = {91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120}

local CURSES = {
  parched = {name = "Parched", text = "water drains 3x"},
  brittle = {name = "Brittle", text = "weapons wear 2x"},
  glass = {name = "Glass", text = "you take +50% damage"},
}
local CURSE_IDS = {"parched", "brittle", "glass"}

local BLESSINGS = {
  moonlit = {name = "Moonlit Edge", text = "+15% damage"},
  stride = {name = "Dran's Stride", text = "run 15% faster"},
  ward = {name = "Fairy Ward", text = "-15% damage taken"},
  tempered = {name = "Tempered Steel", text = "weapons wear 25% slower"},
  flask = {name = "Bottomless Flask", text = "water drains 25% slower"},
  breath = {name = "Second Breath", text = "+12 invincible frames after a hit"},
  lucky = {name = "Lucky Star", text = "10% of hits deal double"},
  scholar = {name = "Scholar's Eye", text = "+25% weapon ABS"},
  mender = {name = "Mender's Charm", text = "regain 2 HP every 3 s"},
}
local BLESSING_IDS = {"moonlit", "stride", "ward", "tempered", "flask", "breath", "lucky", "scholar", "mender"}

local TILES = {
  {id = "river", title = "River", description = "Water drains 12% slower per River."},
  {id = "windmill", title = "Windmill", description = "Each Windmill paired with a Storehouse: +25% weapon ABS."},
  {id = "storehouse", title = "Storehouse", description = "Pairs with a Windmill for +25% weapon ABS."},
  {id = "lamp", title = "Lamp", description = "+4% damage per Lamp. One Lamp maps every floor; two show the monsters too."},
  {id = "tree", title = "Tree", description = "Regain 1 HP every 3 seconds per Tree."},
  {id = "house", title = "House", description = "-6% damage taken per House."},
  {id = "cart", title = "Cart", description = "+20% Gilda from enemies per Cart."},
  {id = "smithy", title = "Smithy", description = "Weapons wear 12% slower per Smithy."},
}
local TILE = {}
local TILE_IDS = {}
for _, t in ipairs(TILES) do TILE[t.id] = t; TILE_IDS[#TILE_IDS + 1] = t.id end
local BASE_PLOTS = 6

local ETERNAL = {
  {id = "gaffer", title = "Gaffer's Wagon", max_rank = 2, costs = {6, 10},
   description = "Gaffer's buggy waits on floor II of every biome: buy Repair Powder and food in Actions. Rank 2: a third cheaper."},
  {id = "macho", title = "Macho's Forge", max_rank = 3, costs = {4, 8, 12},
   description = "The starting weapon gets one random attachment per rank."},
  {id = "vault", title = "Heirloom Vault", max_rank = 1, costs = {10},
   description = "Each Warden gives a charge: bank half your weapon's stats as the Heirloom, added to every new run's weapon."},
  {id = "shrine", title = "Dran's Shrine", max_rank = 3, costs = {5, 10, 15},
   description = "+10% weapon ABS per rank."},
  {id = "well", title = "Deep Well", max_rank = 3, costs = {5, 9, 13},
   description = "+1 Diorama plot per rank."},
  {id = "embassy", title = "Matataki Embassy", max_rank = 1, costs = {12},
   description = "A second ally is drafted when the run starts."},
  {id = "moon", title = "Moon Blessing", max_rank = 1, costs = {15},
   description = "Every run starts with a random blessing."},
  {id = "whetstone", title = "Whetstone", max_rank = 3, costs = {2, 4, 6},
   description = "+10 maximum durability on the starting weapon per rank."},
  {id = "oil", title = "Gaffer's Oil", max_rank = 2, costs = {3, 6},
   description = "Weapons wear 10% slower per rank."},
  {id = "kit", title = "Repair Kit", max_rank = 2, costs = {2, 4},
   description = "+1 Repair Powder in the starter kit per rank."},
}
local ETERNAL_NODE = {}
for _, n in ipairs(ETERNAL) do ETERNAL_NODE[n.id] = n end

-- Skill trees: the Diorama (placed tiles, per run) and Norune Eternal (bought with Moon Shards) -------
do
  local nodes = {}
  for _, t in ipairs(TILES) do nodes[#nodes + 1] = {id = t.id, title = t.title, description = t.description, max_rank = 9} end
  local ok, err = call(game.skills.register, {id = "diorama", title = "DIORAMA", description = "Georama tiles placed for this run.", skills = nodes})
  if not ok then moonmod.log("warn", "diorama tree: " .. errmsg(err)) end
  nodes = {}
  for _, n in ipairs(ETERNAL) do nodes[#nodes + 1] = {id = n.id, title = n.title, description = n.description, max_rank = n.max_rank} end
  ok, err = call(game.skills.register, {id = "eternal", title = "NORUNE ETERNAL", description = "Unlocks bought with Moon Shards.", skills = nodes})
  if not ok then moonmod.log("warn", "eternal tree: " .. errmsg(err)) end
end
local function node_id(tree, node) return ID .. ":" .. tree .. "." .. node end

-- Gauntlet floors ---------------------------------------------------------------------------------------
-- ROUTE[biome index] = {floors = {{id, native}, x4}}; FLOOR_AT["dungeon:native floor"] = {biome, slot}.
local ROUTE, FLOOR_AT = {}, {}
local function adopt_floors(index, record)
  local floors = {}
  for slot, f in ipairs(type(record) == "table" and record.floors or {}) do
    if type(f) == "table" and type(f.id) == "string" and type(f.native_floor_id) == "number" and slot <= WARDEN_SLOT then
      floors[slot] = {id = f.id, native = f.native_floor_id}
    end
  end
  if #floors ~= WARDEN_SLOT then return false end
  ROUTE[index] = {floors = floors}
  for slot, f in ipairs(floors) do FLOOR_AT[BIOMES[index].dungeon .. ":" .. f.native] = {biome = index, slot = slot} end
  return true
end
for index, biome in ipairs(BIOMES) do
  local local_id = "gauntlet-" .. biome.key
  local definition = {id = local_id, name = "Moon Gauntlet: " .. biome.name, dungeon = biome.dungeon, floors = {
    {id = "i", name = biome.name .. " I", source_floor = biome.sources[1]},
    {id = "ii", name = biome.name .. " II", source_floor = biome.sources[2]},
    {id = "iii", name = biome.name .. " III", source_floor = biome.sources[3]},
    {id = "warden", name = biome.name .. " Warden", source_floor = biome.warden},
  }}
  local registered, err = call(game.dungeons.register, definition)
  if not (registered and adopt_floors(index, registered)) then
    -- Already registered this session (the mod was reloaded): read the floors back.
    local existing = try(game.dungeons.get, local_id)
    if not adopt_floors(index, existing) then
      moonmod.log("warn", "gauntlet floors for " .. biome.name .. " unavailable: " .. errmsg(err))
    end
  end
end
local function route_ready(index) return ROUTE[index] ~= nil end

-- Meta (kept across runs and saves) and run state -----------------------------------------------------
local function load_meta()
  local m = moonmod.storage.get("meta")
  if type(m) ~= "table" then m = {} end
  m.shards = math.floor(tonumber(m.shards) or 0)
  m.runs, m.wins, m.deaths, m.retreats = tonumber(m.runs) or 0, tonumber(m.wins) or 0, tonumber(m.deaths) or 0, tonumber(m.retreats) or 0
  m.best_depth = tonumber(m.best_depth) or 0
  m.eternal = type(m.eternal) == "table" and m.eternal or {}
  m.start_char = type(m.start_char) == "string" and m.start_char or "toan"
  if type(m.heirloom) ~= "table" then m.heirloom = nil end
  return m
end
local meta = load_meta()
local function save_meta() moonmod.storage.set("meta", meta) end
local function eternal(id) return math.floor(tonumber(meta.eternal[id]) or 0) end

-- A run lives only inside its sandbox session. One still in storage at start-up was cut short when the
-- game closed; it is closed below as a retreat once the helpers exist.
local run = moonmod.storage.get("run")
if type(run) ~= "table" or run.active ~= true then run = nil end
local function save_run() moonmod.storage.set("run", run or false) end

-- Per-floor state (not saved) --------------------------------------------------------------------------
local frame = 0
local floor = nil          -- {token, biome, slot, back, cursed, curses, scaled, warden, warden_max, seen, swept, entered, atla}
local pending_transition = nil   -- {id, at, tries, why}
local effects_on = false
local hud_text = nil
local hud_native = nil       -- the engine draws the floor label and HUD icons (false: fall back to a text line)
local choice = nil         -- an open weapon choice: {character, keep, take, pick = 1 keep | 2 take, armed, token}

local function on_route() return run and run.phase == "active" and floor ~= nil and not run.suspended end
local function biome_def(pos) return run and BIOMES[run.biomes[pos]] end
local function total_floors() return run and (#run.biomes * WARDEN_SLOT) or 0 end

-- Effects ------------------------------------------------------------------------------------------------
local function placed(id) return run and math.floor(tonumber(run.diorama[id]) or 0) or 0 end
local function blessed(id) return run and contains(run.blessings, id) end
local function cursed(id) return floor and floor.cursed and contains(floor.curses, id) end
local function plots() return BASE_PLOTS + eternal("well") end
local function placed_total() local n = 0; for _, id in ipairs(TILE_IDS) do n = n + placed(id) end; return n end
local function stock_total() local n = 0; for _, id in ipairs(TILE_IDS) do n = n + math.floor(tonumber(run and run.stock[id]) or 0) end; return n end

-- Enemy-side scale of a late biome rolled early by Biome Shuffle.
local function shuffle_scale()
  if not (run and floor) then return 1 end
  local native = run.biomes[floor.biome]
  if native <= floor.biome then return 1 end
  return math.max(0.35, floor.biome / native)
end

local function abs_multiplier()
  local pairs_built = math.min(placed("windmill"), placed("storehouse"))
  local m = setting("abs_rate", 6) * (1 + 0.25 * pairs_built) * (1 + 0.1 * eternal("shrine"))
  if blessed("scholar") then m = m * 1.25 end
  if floor and floor.cursed then m = m * 1.5 end
  if floor and floor.back then m = m * 1.5 end
  return m
end

-- Weapon wear: Smithy tiles, Tempered Steel and the Brittle curse.
local function wear_scale()
  return clamp((0.88 ^ placed("smithy")) * (0.9 ^ eternal("oil")) * (blessed("tempered") and 0.75 or 1) * (cursed("brittle") and 2 or 1), 0.25, 4)
end

local function apply_effects()
  local active = on_route()
  if not active then
    if effects_on then
      try(game.player.tuning_clear)
      try(game.combat.register_formula, {id = "gauntlet_out", operation = "multiply", value = 1, priority = 120})
      try(game.combat.register_formula, {id = "gauntlet_lucky", operation = "chance_multiply", value = 2, chance = 0, priority = 121})
      try(game.combat.register_player_formula, {id = "gauntlet_in", operation = "multiply", value = 1, priority = 120})
      effects_on = false
    end
    return
  end
  local out = (1 + 0.04 * placed("lamp")) * (blessed("moonlit") and 1.15 or 1)
  local incoming = (0.94 ^ placed("house")) * (blessed("ward") and 0.85 or 1) * (cursed("glass") and 1.5 or 1)
  local shuffle = shuffle_scale()
  if shuffle < 1 then incoming = incoming * math.max(0.5, shuffle) end
  try(game.combat.register_formula, {id = "gauntlet_out", operation = "multiply", value = clamp(out, 0, 100), priority = 120})
  try(game.combat.register_formula, {id = "gauntlet_lucky", operation = "chance_multiply", value = 2, chance = blessed("lucky") and 10 or 0, priority = 121})
  try(game.combat.register_player_formula, {id = "gauntlet_in", operation = "multiply", value = clamp(incoming, 0, 100), priority = 120})
  local tuning = {
    thirst_drain = clamp((0.88 ^ placed("river")) * (blessed("flask") and 0.75 or 1) * (cursed("parched") and 3 or 1), 0.25, 4),
    durability_wear = wear_scale(),
    run_speed = blessed("stride") and 1.15 or 1,
    invincible_bonus_frames = blessed("breath") and 12 or 0,
    map_reveal = placed("lamp") >= 1,
    monster_reveal = placed("lamp") >= 2,
  }
  local _, err = call(game.player.tuning_set, tuning)
  if err and err.code ~= "unsupported" then moonmod.log("warn", "tuning: " .. errmsg(err)) end
  effects_on = true
end

-- Journal page and HUD -------------------------------------------------------------------------------
local function names_of(ids, table_of)
  local out = {}
  for _, id in ipairs(ids or {}) do out[#out + 1] = table_of[id] and table_of[id].name or title(id) end
  return table.concat(out, ", ")
end

local function update_sheet()
  if not setting("journal_page", true) then return end
  if not run then try(game.ui.sheet_clear); return end
  local b = biome_def(run.pos)
  local lines = {
    string.format("Biome %d/%d  %s", run.pos, #run.biomes, b and b.name or "?"),
    string.format("Floor %s  |  Next gate: %s", FLOOR_LABEL[run.slot] or "-", run.next_cursed and "CURSED" or "normal"),
    string.format("Diorama %d/%d plots  |  %d tiles in stock", placed_total(), plots(), stock_total()),
    ("Blessings: " .. (#run.blessings > 0 and names_of(run.blessings, BLESSINGS) or "none")):sub(1, 48),
    string.format("Moon Shards %d (+%d this run)", meta.shards, run.shards),
    ("Allies: " .. table.concat((function() local t = {}; for _, c in ipairs(run.drafted) do t[#t + 1] = title(c) end; return t end)(), ", ")):sub(1, 48),
  }
  local stock = {}
  for _, id in ipairs(TILE_IDS) do
    local n = math.floor(tonumber(run.stock[id]) or 0)
    if n > 0 then stock[#stock + 1] = TILE[id].title .. " x" .. n end
  end
  local hint = #stock > 0 and ("Cross places a tile. Stock: " .. table.concat(stock, ", ")) or "Atla, cleared floors and caches give tiles."
  try(game.ui.sheet_set, {title = "MOON GAUNTLET", lines = lines, hint = hint:sub(1, 80),
      progress = clamp(run.depth / math.max(1, total_floors()), 0, 1),
      progress_label = ("Depth " .. run.depth .. " / " .. total_floors()), trees = {"diorama", "eternal"}})
end

-- The HUD in the game's own art: the floor plate reads "2-3" (a Warden floor keeps the native "Boss") and the floor
-- card the run's depth ("B6"), a cursed
-- floor shows a small Curse badge and the chest its Miracle cache pays, and a curse waiting for the next floor
-- blinks. A Vault needs nothing: the native plate turns purple on a back floor. An engine without these draws a
-- text line instead.
local function hud_state()
  if not (run and run.phase == "active" and floor) or run.suspended then return nil end
  -- Digits: the game font's capital I reads as a lower-case l.
  local s = {label = run.slot < WARDEN_SLOT and (run.pos .. "-" .. run.slot) or nil, icons = {}}
  if floor.cursed then
    s.icons[#s.icons + 1] = {id = "curse", icon = "curse"}
    s.icons[#s.icons + 1] = {id = "cache", image = HUD_CACHE_IMAGE}
  elseif run.next_cursed then
    s.icons[#s.icons + 1] = {id = "curse", icon = "curse", blink = true}
  end
  return s
end

local function hud_line()
  if not (run and run.phase == "active" and floor) then return nil end
  if run.suspended then return "GAUNTLET: OFF ROUTE" end
  return string.format("GAUNTLET %d-%s%s%s", run.pos, FLOOR_LABEL[run.slot] or "?",
      floor.cursed and " CURSED" or (floor.back and " VAULT" or ""), run.next_cursed and " NEXT CURSED" or "")
end

local function update_hud()
  local s = hud_state()
  local key = s and ((s.label or "-") .. "|" .. run.depth .. "|" .. #s.icons .. "|" .. tostring(s.icons[1] and s.icons[1].blink)) or ""
  if hud_native ~= false then
    if key == hud_text then return end
    hud_text = key
    local err
    if not (game.render.floor_label_set and game.render.hud_icon_set) then err = {code = "unsupported"}
    elseif s and s.label then _, err = call(game.render.floor_label_set, {text = s.label, number = math.min(99, run.depth)})
    else _, err = call(game.render.floor_label_clear) end
    if err and (err.code == "unsupported" or err.code == "not_found") then hud_native = false; hud_text = nil
    else
      hud_native = true
      local wanted = {}
      for _, icon in ipairs(s and s.icons or {}) do
        wanted[icon.id] = true
        try(game.render.hud_icon_set, {id = icon.id, icon = icon.icon, image = icon.image, blink = icon.blink})
      end
      for _, id in ipairs({"curse", "cache"}) do if not wanted[id] then try(game.render.hud_icon_remove, {id = id}) end end
      return
    end
  end
  local text = not choice and hud_line() or nil -- the weapon choice needs the room
  if text == hud_text then return end
  hud_text = text
  if text then try(game.render.layer_register, {id = "gauntlet", text = text})
  else try(game.render.layer_remove, {id = "gauntlet"}) end
end

local function refresh()
  apply_effects()
  update_sheet()
  update_hud()
end

-- Diorama and rewards ------------------------------------------------------------------------------
local function push_diorama_ranks()
  for _, id in ipairs(TILE_IDS) do try(game.skills.set_rank, {id = node_id("diorama", id), rank = placed(id)}) end
end
local function push_eternal_ranks()
  for _, n in ipairs(ETERNAL) do try(game.skills.set_rank, {id = node_id("eternal", n.id), rank = math.min(n.max_rank, eternal(n.id))}) end
end

local function give_tiles(n, why)
  if not run then return end
  local got = {}
  for _ = 1, n do
    local id = pick(TILE_IDS)
    run.stock[id] = (tonumber(run.stock[id]) or 0) + 1
    got[#got + 1] = TILE[id].title
  end
  toast((why and (why .. ": ") or "") .. "Diorama tile" .. (n > 1 and "s " or " ") .. table.concat(got, ", ") .. "  (Journal > Character)", 300)
end

local function earn_shards(n)
  if not run or n <= 0 then return end
  run.shards = run.shards + n
end

local function bless(why)
  if not run then return end
  local open = {}
  for _, id in ipairs(BLESSING_IDS) do if not contains(run.blessings, id) then open[#open + 1] = id end end
  local id = pick(open)
  if not id then earn_shards(2); toast((why or "Blessing") .. ": every blessing held, +2 Moon Shards"); return end
  run.blessings[#run.blessings + 1] = id
  toast((why and (why .. "  -  ") or "") .. "BLESSING: " .. BLESSINGS[id].name .. " (" .. BLESSINGS[id].text .. ")", 360)
end

local function pay(amount)
  amount = math.floor(amount)
  while amount > 0 do
    local part = math.min(amount, 32767)
    if not try(game.economy.add, {amount = part}) then return end
    amount = amount - part
  end
end

local function miracle_cache()
  local gem, attach = pick(GEMS), pick(ATTACHMENTS)
  local a = try(game.items.give, {id = "chronicle:item:" .. gem, count = 1})
  local b = try(game.items.give, {id = "chronicle:item:" .. attach, count = 1})
  local n = ((a and (a.added or 0) > 0) and 1 or 0) + ((b and (b.added or 0) > 0) and 1 or 0)
  toast("MIRACLE CACHE: " .. n .. " treasure" .. (n == 1 and "" or "s") .. " added to your bag" .. (n < 2 and " (bag full?)" or ""), 300)
end

-- Weapons ------------------------------------------------------------------------------------------------
local function weapon_instances(id)
  local w = try(game.weapons.get, id)
  return w and type(w.instances) == "table" and w.instances or {}, w
end

-- One owned weapon instance: {id, slot, level, stats, elements}.
local function weapon_info(id, character, slot)
  local w = try(game.weapons.get, id)
  for _, i in ipairs(w and w.instances or {}) do
    if i.character == character and i.slot == slot then
      return {id = id, slot = slot, level = tonumber(i.level) or 0, stats = i.stats or {}, elements = i.elements or {}}
    end
  end
end

-- The equipped weapon of a joined character: {id, slot} (scans the weapons that character can use).
local function equipped_weapon(character)
  local p = try(game.player.get)
  if p and p.character == character and p.weapon and p.weapon.id then return {id = p.weapon.id, slot = p.weapon.slot} end
  for _, def in ipairs(try(game.weapons.list) or {}) do
    if type(def) == "table" and def.owner == character then
      for _, inst in ipairs(weapon_instances(def.id)) do
        if inst.character == character and inst.equipped then return {id = def.id, slot = inst.slot} end
      end
    end
  end
  return nil
end

local function cache_weapons()
  if not run then return end
  run.weapons = {}
  for _, c in ipairs(run.drafted) do run.weapons[c] = equipped_weapon(c) end
end

local function level_up(selector, times)
  local levels = 0
  for _ = 1, times do
    local abs = try(game.weapons.abs_get, selector)
    if not abs or (abs.level or 0) >= 99 then break end
    local need = math.max(0, (tonumber(abs.abs_max) or 0) - (tonumber(abs.abs) or 0))
    if need > 0 then try(game.weapons.abs_add, {id = selector.id, character = selector.character, slot = selector.slot, amount = math.min(32767, need)}) end
    local up = try(game.weapons.upgrade, selector)
    if not (up and up.upgraded) then break end
    levels = levels + 1
  end
  return levels
end

local function insert_attachments(selector, n)
  local inserted = 0
  for _ = 1, n do
    local ok = try(game.weapons.attachment_insert, {id = selector.id, character = selector.character, slot = selector.slot, attachment_id = pick(ATTACHMENTS)})
    if ok then inserted = inserted + 1 else break end
  end
  return inserted
end

-- Shared ABS: benched drafted allies' equipped weapons get a share of each kill's ABS.
local function share_abs(amount, active)
  local share = math.floor(amount * setting("ally_abs_share", 50) / 100)
  if share <= 0 or not run or not run.weapons then return end
  for _, c in ipairs(run.drafted) do
    local w = c ~= active and run.weapons[c]
    if w then
      local selector = {id = w.id, character = c, slot = w.slot}
      local added = try(game.weapons.abs_add, {id = w.id, character = c, slot = w.slot, amount = math.min(32767, share)})
      if added and (added.abs or 0) >= (added.abs_max or math.huge) then
        local up = try(game.weapons.upgrade, selector)
        if up and up.upgraded then toast(title(c) .. "'s weapon leveled up from the shared ABS", 180) end
      end
    end
  end
end

-- Run lifecycle -----------------------------------------------------------------------------------------
local function max_hp_of(character)
  for _, member in ipairs(try(game.party.list) or {}) do
    if type(member) == "table" and member.id == character then return math.max(1, math.floor(tonumber(member.max_hp) or 60)) end
  end
  return 60
end

local function queue_transition(id, delay, why)
  pending_transition = {id = id, at = frame + (delay or 0), tries = 0, why = why}
end

local function prepare_floor_rules()
  -- Run floors start without a native Limited Zone (their table entries are new).
  for _, index in ipairs(run.biomes) do
    for _, f in ipairs(ROUTE[index].floors) do
      local rules = try(game.dungeons.floor_rules_get, {dungeon_id = BIOMES[index].dungeon, floor_id = f.native})
      if rules and rules.limit_zone_name ~= "none" then
        try(game.dungeons.floor_rules_set, {dungeon_id = BIOMES[index].dungeon, floor_id = f.native, limit_zone = -1})
      end
    end
  end
end

local function apply_heirloom(character, w)
  local h = meta.heirloom
  if not (h and w) then return false end
  local inst = nil
  for _, i in ipairs(weapon_instances(w.id)) do if i.character == character and i.slot == w.slot then inst = i end end
  if not inst then return false end
  local s = inst.stats or {}
  local request = {id = w.id, character = character, slot = w.slot}
  for _, k in ipairs({"attack", "endurance", "speed", "magic"}) do
    request[k] = math.floor(clamp((tonumber(s[k]) or 0) + (tonumber(h[k]) or 0), 0, 32767))
  end
  if type(h.elem) == "table" and type(inst.elements) == "table" then
    request.elem = {}
    for e = 1, 5 do request.elem[e] = math.floor(clamp((tonumber(inst.elements[e]) or 0) + (tonumber(h.elem[e]) or 0), 0, 127)) end
  end
  return try(game.weapons.stats_set, request) ~= nil
end

-- Title screen pages ------------------------------------------------------------------------------------
-- The Gauntlet's title screen is a page the engine draws: heading, up to six lines, up to seven entries.
local page = "root"          -- "root", "eternal" or "records"
local eternal_pending = nil  -- the unlock waiting for a second Cross
local ETERNAL_PER_PAGE = 6   -- a title page holds 7 entries: six unlocks and "More unlocks"
local eternal_from = 1        -- the first unlock on the Eternal page shown
local last_result = nil      -- a line about the run that just ended
local title_ready = false
local start_run              -- defined below

local function shards_line() return string.format("Moon Shards %d   |   Runs %d   Wins %d", meta.shards, meta.runs, meta.wins) end

local function root_page()
  local h = meta.heirloom
  local lines = {shards_line(), string.format("Best depth %d / %d", meta.best_depth, setting("biome_count", 5) * WARDEN_SLOT)}
  if h then lines[#lines + 1] = string.format("Heirloom: +%d attack  +%d magic  +%d endurance", h.attack or 0, h.magic or 0, h.endurance or 0) end
  if last_result then lines[#lines + 1] = last_result end
  local ready = 0
  for index in ipairs(BIOMES) do if route_ready(index) then ready = ready + 1 end end
  if ready == 0 then lines[#lines + 1] = "The Gauntlet floors could not be registered (see the log)." end
  return {title = "DARK GENIE'S GAUNTLET", subtitle = "Five biomes. No saves. No way back.", root = true, hint = "",
          lines = lines, entries = {
            {id = "start", label = "Start Run", enabled = ready > 0},
            {id = "character", label = "Starting Character: " .. title(meta.start_char)},
            {id = "eternal", label = "Norune Eternal"},
            {id = "records", label = "Records"},
          }}
end

local function eternal_page()
  local entries = {}
  for i = eternal_from, math.min(#ETERNAL, eternal_from + ETERNAL_PER_PAGE - 1) do
    local n = ETERNAL[i]
    local rank = eternal(n.id)
    local label = rank >= n.max_rank and string.format("%s  %d/%d  complete", n.title, rank, n.max_rank) or
        string.format("%s  %d/%d  -  %d shards", n.title, rank, n.max_rank, n.costs[rank + 1])
    entries[#entries + 1] = {id = n.id, label = label, enabled = rank < n.max_rank}
  end
  if #ETERNAL > ETERNAL_PER_PAGE then
    local pages = math.ceil(#ETERNAL / ETERNAL_PER_PAGE)
    entries[#entries + 1] = {id = "more", label = string.format("More unlocks  (page %d/%d)", (eternal_from - 1) // ETERNAL_PER_PAGE + 1, pages)}
  end
  local lines = {string.format("Moon Shards %d", meta.shards)}
  if eternal_pending then
    local n = ETERNAL_NODE[eternal_pending]
    lines[#lines + 1] = n.title .. ":"
    local text = n.description
    while #text > 0 and #lines < 5 do
      local cut_at = #text <= 62 and #text or (text:sub(1, 62):match(".*() ") or 62)
      lines[#lines + 1] = text:sub(1, cut_at):gsub("%s+$", "")
      text = text:sub(cut_at + 1):gsub("^%s+", "")
    end
    lines[#lines + 1] = "Cross again to buy it."
  else
    lines[#lines + 1] = "Cross on an unlock shows what it does; Cross again buys it."
  end
  return {title = "NORUNE ETERNAL", subtitle = "Unlocks kept for every run", root = false, lines = lines, entries = entries,
          hint = "{cross} Choose    {circle} Back"}
end

local function records_page()
  local h = meta.heirloom
  return {title = "RECORDS", subtitle = "Dark Genie's Gauntlet", root = false, hint = "{circle} Back", lines = {
            shards_line(),
            string.format("Defeats %d   Retreats %d", meta.deaths, meta.retreats),
            string.format("Best depth %d", meta.best_depth),
            "Heirloom: " .. (h and string.format("+%d attack, +%d magic, +%d endurance, +%d speed", h.attack or 0, h.magic or 0, h.endurance or 0, h.speed or 0) or "none"),
            last_result or "",
          }, entries = {{id = "done", label = "Back"}}}
end

local function show_page(name, cursor)
  page = name
  local data = name == "eternal" and eternal_page() or (name == "records" and records_page() or root_page())
  data.id = MODE
  data.cursor = cursor
  local _, err = call(game.title.mode_set, data)
  if err then moonmod.log("warn", "title page: " .. errmsg(err)) end
end

do
  local data = root_page()
  data.id, data.label = MODE, "Dark Genie's Gauntlet"
  local ok, err = call(game.title.mode_register, data)
  title_ready = ok ~= nil
  if not ok then moonmod.log("warn", "title mode: " .. errmsg(err) .. " (this engine has no title modes; update the port)") end
end

local function cursor_of(list, id)
  for i, e in ipairs(list) do if e.id == id then return i - 1 end end
  return 0
end

moonmod.on("game.title.opened", function()
  page = "root"
  eternal_pending = nil
  show_page("root")
end)

moonmod.on("game.title.selected", function(e)
  local entry = e and e.entry
  if page == "root" then
    if entry == "start" then start_run()
    elseif entry == "character" then
      local index = 1
      for i, c in ipairs(CHARACTERS) do if c == meta.start_char then index = i end end
      meta.start_char = CHARACTERS[index % #CHARACTERS + 1]
      save_meta()
      show_page("root", 1)
    elseif entry == "eternal" then eternal_pending = nil; eternal_from = 1; show_page("eternal", 0)
    elseif entry == "records" then show_page("records", 0)
    end
  elseif page == "eternal" then
    if entry == "back" then eternal_pending = nil; show_page("root", 2); return end
    if entry == "more" then
      eternal_pending = nil
      eternal_from = eternal_from + ETERNAL_PER_PAGE
      if eternal_from > #ETERNAL then eternal_from = 1 end
      show_page("eternal", math.min(ETERNAL_PER_PAGE, #ETERNAL - eternal_from + 1))
      return
    end
    local n = ETERNAL_NODE[entry]
    if not n then return end
    local cursor = cursor_of(ETERNAL, entry) - (eternal_from - 1)
    if eternal_pending ~= entry then eternal_pending = entry; show_page("eternal", cursor); return end
    local rank = eternal(entry)
    local cost = n.costs[rank + 1]
    if rank < n.max_rank and meta.shards >= cost then
      meta.shards = meta.shards - cost
      meta.eternal[entry] = rank + 1
      save_meta()
      try(game.skills.set_rank, {id = node_id("eternal", entry), rank = rank + 1})
      eternal_pending = nil
      try(game.audio.se_play, {se = 20})
    else
      eternal_pending = nil
    end
    show_page("eternal", cursor)
    if meta.eternal[entry] == rank then
      try(game.title.mode_set, {id = MODE, lines = {string.format("Moon Shards %d", meta.shards),
          n.title .. " needs " .. cost .. " Moon Shards."}})
    end
  elseif page == "records" then
    show_page("root", 3)
  end
end)

start_run = function()
  if run then run = nil; save_run() end
  local available = {}
  for index in ipairs(BIOMES) do if route_ready(index) then available[#available + 1] = index end end
  if #available == 0 then return end
  if setting("biome_shuffle", false) then
    for i = #available, 2, -1 do local j = math.random(i); available[i], available[j] = available[j], available[i] end
  end
  local biomes = {}
  for i = 1, math.min(#available, setting("biome_count", 5)) do biomes[i] = available[i] end
  local start = contains(CHARACTERS, meta.start_char) and meta.start_char or "toan"
  run = {active = true, phase = "launch", biomes = biomes, pos = 1, slot = 1, depth = 0, next_cursed = false,
         stock = {}, diorama = {}, blessings = {}, drafted = {start}, shards = 0,
         heirloom_charges = 0, kills = 0, weapons = {}}
  if eternal("embassy") > 0 then
    local others = {}
    for _, c in ipairs(CHARACTERS) do if c ~= start then others[#others + 1] = c end end
    run.drafted[#run.drafted + 1] = pick(others)
  end
  for _, id in ipairs(TILE_IDS) do run.diorama[id] = 0; run.stock[id] = 0 end
  local result, err = call(game.session.start, {floor = ROUTE[biomes[1]].floors[1].id, party_size = 6, character = start})
  if not result then
    run = nil
    save_run()
    try(game.title.mode_set, {id = MODE, lines = {shards_line(), "The run could not start: " .. errmsg(err):sub(1, 30)}})
    return
  end
  meta.runs = meta.runs + 1
  save_meta()
  save_run()
end

-- First arrival on floor I: the fresh session's party, kit and unlocks.
local function first_floor_setup()
  for _, c in ipairs(CHARACTERS) do
    if not contains(run.drafted, c) then try(game.player.set, {hp = 0, character = c}) end
  end
  local notes = {}
  local start = run.drafted[1]
  local w = equipped_weapon(start)
  if w then
    local selector = {id = w.id, character = start, slot = w.slot}
    if apply_heirloom(start, w) then notes[#notes + 1] = "Heirloom applied" end
    local forged = eternal("macho") > 0 and insert_attachments(selector, eternal("macho")) or 0
    if forged > 0 then notes[#notes + 1] = forged .. " forged attachment" .. (forged == 1 and "" or "s") end
    local whet = eternal("whetstone") * 10
    local d = whet > 0 and weapon_info(w.id, start, w.slot)
    if d then
      local max = math.floor((tonumber(d.stats.durability) or 0) + whet)
      try(game.weapons.stats_set, {id = w.id, character = start, slot = w.slot, durability = max})
      try(game.weapons.durability_set, {id = w.id, character = start, slot = w.slot, durability = max})
      notes[#notes + 1] = "Whetstone +" .. whet .. " durability"
    end
  end
  if setting("starter_kit", true) then
    try(game.items.give, {id = "chronicle:item:" .. ITEM.bread, count = 2})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.water, count = 2})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.repair, count = 2 + eternal("kit")})
  end
  if eternal("moon") > 0 then bless("Moon Blessing") end
  cache_weapons()
  prepare_floor_rules()
  push_diorama_ranks()
  toast("THE GAUNTLET OPENS: " .. #run.biomes .. " biome" .. (#run.biomes == 1 and "" or "s") .. ", " .. title(start) ..
      (#run.drafted > 1 and (" and " .. title(run.drafted[2])) or "") .. (#notes > 0 and ("  (" .. table.concat(notes, "; ") .. ")") or ""), 480)
end

local function end_run(outcome)
  if not run then return end
  local depth = run.depth
  local earned = run.shards
  if outcome == "victory" then earned = earned + 10 end
  meta.shards = math.min(SHARD_LIMIT, meta.shards + earned)
  meta.best_depth = math.max(meta.best_depth, depth)
  if outcome == "victory" then meta.wins = meta.wins + 1
  elseif outcome == "death" or outcome == "broken" then meta.deaths = meta.deaths + 1
  else meta.retreats = meta.retreats + 1 end
  save_meta()
  local b = biome_def(run.pos)
  local where = b and (b.name .. " " .. (FLOOR_LABEL[run.slot] or "")) or "?"
  local headline = outcome == "victory" and "CONQUERED" or (outcome == "death" and "Fell in " .. where or
      (outcome == "broken" and "Weapon broke in " .. where or "Left at " .. where))
  last_result = string.format("Last run: %s, depth %d, +%d", headline, depth, earned):sub(1, 64) -- Moon Shards are on the line above
  run = nil
  floor = nil
  pending_transition = nil
  save_run()
  try(game.render.bar_remove, {id = "warden"})
  try(game.dungeons.set_modifiers, {})
  for _, id in ipairs(TILE_IDS) do try(game.skills.set_rank, {id = node_id("diorama", id), rank = 0}) end
  refresh()
  if title_ready then show_page("root", 0) end
end

-- Floors --------------------------------------------------------------------------------------------------
local function roll_curses()
  local pool = {table.unpack(CURSE_IDS)}
  local out = {}
  for _ = 1, 2 do
    local i = math.random(#pool)
    out[#out + 1] = table.remove(pool, i)
  end
  return out
end

local function draft_ally(why)
  local others = {}
  for _, c in ipairs(CHARACTERS) do if not contains(run.drafted, c) then others[#others + 1] = c end end
  local ally = pick(others)
  if not ally then earn_shards(2); toast(why .. ": no one left to draft, +2 Moon Shards"); return end
  run.drafted[#run.drafted + 1] = ally
  try(game.player.set, {hp = max_hp_of(ally), character = ally})
  run.weapons[ally] = equipped_weapon(ally)
  toast(why .. ": " .. title(ally):upper() .. " JOINS THE RUN", 360)
end

local function complete_floor(prev)
  run.floors_done = (run.floors_done or 0) + 1
  local depth = run.depth
  earn_shards(1)
  pay(40 * depth)
  local tiles = 1 + (prev.swept and 1 or 0) + (prev.cursed and 1 or 0)
  if prev.cursed then
    earn_shards(2)
    miracle_cache()
    if math.random(100) <= 35 then bless("Cursed floor survived") end
  end
  if prev.back then earn_shards(2); bless("Vault cleared") end
  give_tiles(tiles, (prev.swept and "Floor swept" or "Floor cleared"))
end

local function warden_cleared()
  if not (run and floor) or floor.warden_done then return end
  floor.warden_done = true
  try(game.render.bar_remove, {id = "warden"})
  earn_shards(3)
  give_tiles(1, "Warden felled")
  bless("Warden felled")
  if eternal("vault") > 0 then run.heirloom_charges = run.heirloom_charges + 1 end
  local last = run.pos >= #run.biomes
  if last then
    run.phase = "victory"
    toast("THE LAST WARDEN FALLS. The Gauntlet is conquered.", 360)
    queue_transition("end", 300, "victory")
  else
    local next_biome = BIOMES[run.biomes[run.pos + 1]]
    run.awaiting = run.pos + 1
    toast("WARDEN FELLED. On to " .. next_biome.name .. " in 5 seconds" .. (run.heirloom_charges > 0 and "  (Heirloom charge ready: Actions)" or ""), 360)
    queue_transition(ROUTE[run.biomes[run.pos + 1]].floors[1].id, 300, "next biome")
  end
  save_run()
  refresh()
end

local function enter_floor(world)
  local hit = FLOOR_AT[tostring(world.dungeon_id) .. ":" .. tostring(world.floor_id)]
  local pos = nil
  if hit then for p, index in ipairs(run.biomes) do if index == hit.biome then pos = p end end end
  local prev = floor
  -- The engine reports the new floor a few frames before it builds it and sets its seed: the second sighting
  -- of the same floor is the same arrival.
  if prev and pos and pos == prev.biome and hit.slot == prev.slot and (world.back_floor == true) == prev.back and
      frame - (prev.entered or 0) < 120 then
    prev.token = world.token
    return
  end
  local expected = false
  if pos then
    if run.phase == "launch" then expected = pos == 1 and hit.slot == 1
    elseif pos == run.pos and hit.slot == run.slot then expected = true                 -- same floor (its back side, or a reload)
    elseif pos == run.pos and hit.slot == run.slot + 1 then expected = true             -- the native exit gate
    elseif run.awaiting and pos == run.awaiting and hit.slot == 1 then expected = true  -- the next biome
    end
  end
  -- The launch and a move to the next biome re-enter the dungeon through its entrance, which reads as
  -- floor 0 until the floor loads: wait it out instead of calling it off route.
  if not expected and not hit and (run.phase == "launch" or run.awaiting) then return end
  if not expected then
    run.suspended = true
    floor = {token = world.token, biome = 0, slot = 0, scaled = {}}
    toast("This floor is off the Gauntlet route: run effects are paused until you return to it.", 360)
    save_run()
    refresh()
    return
  end
  run.suspended = false
  local advanced = run.phase == "launch" or pos ~= run.pos or hit.slot ~= run.slot
  if run.phase == "active" and advanced and prev and prev.biome == run.pos and prev.slot > 0 then complete_floor(prev) end
  local first = run.phase == "launch"
  if first then run.phase = "active" end
  if advanced then run.depth = run.depth + 1 end
  run.pos, run.slot, run.awaiting = pos, hit.slot, nil
  local cursing = advanced and run.next_cursed and hit.slot < WARDEN_SLOT
  floor = {token = world.token, biome = pos, slot = hit.slot, back = world.back_floor == true, scaled = {}, seen = 0,
           entered = frame, swept = false, atla = nil,
           cursed = cursing or (not advanced and prev and prev.cursed) or false,
           curses = cursing and roll_curses() or (not advanced and prev and prev.curses) or {}}
  if advanced then run.next_cursed = false end
  meta.best_depth = math.max(meta.best_depth, run.depth)
  local b = biome_def(pos)
  local intro = string.format("%s %s  (depth %d/%d)", b.name:upper(), FLOOR_LABEL[hit.slot], run.depth, total_floors())
  if floor.back then intro = intro .. "  VAULT: tougher, richer, a blessing when you leave" end
  if floor.cursed then
    local list = {}
    for _, c in ipairs(floor.curses) do list[#list + 1] = CURSES[c].name .. " (" .. CURSES[c].text .. ")" end
    intro = intro .. "  CURSED: " .. table.concat(list, ", ")
  end
  if hit.slot == WARDEN_SLOT then intro = intro .. "  The gate-key holder is the Warden." end
  if advanced and hit.slot == 2 and eternal("gaffer") > 0 then intro = intro .. "  Gaffer's Wagon is here (Actions)." end
  -- Re-entering the dungeon (the launch, the next biome) loads Toan: switch back quietly, so the draft
  -- check has nothing to bounce.
  local p = try(game.player.get)
  local keep = run.leader or run.drafted[1]
  if p and p.character ~= keep then try(game.party.set_active, {id = keep}) end
  if first then first_floor_setup() end
  toast(intro, 420)
  if advanced and hit.slot == 2 and (pos == 1 or pos == 3) then draft_ally("GOLDEN ATLA") end
  if advanced and hit.slot == 1 then cache_weapons() end
  save_meta()
  save_run()
  refresh()
end

-- Floor generation: cursed floors hold more and richer chests.
moonmod.on("game.dungeon.generating", function(e)
  if not run then return end
  local hit = FLOOR_AT[tostring(e.dungeon_id) .. ":" .. tostring(e.floor_id)]
  -- The floor may be built just after the run has arrived on it (and spent next_cursed).
  local arrived = floor and floor.cursed and floor.slot == (hit and hit.slot) and run.biomes[floor.biome] == (hit and hit.biome)
  local cursing = hit and hit.slot < WARDEN_SLOT and (run.next_cursed or arrived)
  try(game.dungeons.set_modifiers, cursing and {chests = 50, chest_value = 100} or {})
end)

-- Enemies ------------------------------------------------------------------------------------------------
local function drop_of(e)
  local d = (e.combat and e.combat.drop_item) or (e.definition and e.definition.drop_item)
  return tonumber(d)
end

local function scale_enemies(roster)
  local hp_mult = (1 + setting("depth_hp", 6) / 100 * math.max(0, run.depth - 1)) * shuffle_scale()
  if floor.cursed then hp_mult = hp_mult * setting("curse_hp", 160) / 100 end
  if floor.back then hp_mult = hp_mult * 1.5 end
  local abs_mult = abs_multiplier()
  local money_mult = 1 + 0.2 * placed("cart")
  local defense_add = math.floor(run.depth / 2)
  for _, e in ipairs(roster) do
    local handle = e.entity_id or e.id
    local key = tostring(handle)
    if handle and e.revealed == true and not floor.scaled[key] then
      local hp = e.health and tonumber(e.health.maximum) or 0
      local combat = e.combat or {}
      if hp > 0 then
        local warden = floor.slot == WARDEN_SLOT and not floor.warden and (drop_of(e) or -1) >= 0
        local mult = hp_mult * (warden and setting("warden_hp", 6) or 1)
        local request = {entity = handle,
          max_hp = math.floor(clamp(hp * mult, 1, 1000000)),
          defense = math.floor(clamp(((tonumber(combat.defense) or 0) + defense_add) * (warden and 1.5 or 1), 0, 32767)),
          reward_exp = math.floor(clamp((tonumber(combat.reward_exp) or 0) * abs_mult * (warden and 5 or 1), 0, 32767)),
          reward_money = math.floor(clamp((tonumber(combat.reward_money) or 0) * money_mult * (warden and 5 or 1), 0, 2147483647))}
        request.hp = request.max_hp
        if try(game.entities.set_stats, request) then
          floor.scaled[key] = true
          if warden then
            floor.warden, floor.warden_max = handle, request.max_hp
            try(game.entities.scale_set, {entity = handle, scale = 1.8})
            toast("THE WARDEN OF " .. biome_def(floor.biome).name:upper() .. " AWAKENS", 300)
          end
        end
      end
    end
  end
end

local function update_warden_bar()
  if not floor.warden or floor.warden_done then return end
  local e = try(game.entities.get, floor.warden)
  if not e or e.status ~= "alive" then
    if e and e.status == "dead" then warden_cleared() end
    return
  end
  local current = e.health and tonumber(e.health.current) or 0
  try(game.render.bar_register, {id = "warden", label = "WARDEN", current = current, max = floor.warden_max or current})
end

moonmod.on("game.enemy_defeated", function(e)
  if not on_route() then return end
  run.kills = run.kills + 1
  local exp = tonumber(e.reward_exp) or 0
  local p = try(game.player.get)
  if exp > 0 then share_abs(exp, p and p.character) end
  if floor.warden and e.entity and tostring(e.entity) == tostring(floor.warden) then warden_cleared() end
end)

-- One weapon each -------------------------------------------------------------------------------------------
-- Each character carries one weapon for the whole run. A found weapon opens a choice: keep the one in hand or
-- take the new one; the other is absorbed into the keeper (a quarter of its attack, endurance, speed, magic and
-- elements). A weapon for someone outside the draft is absorbed into the active character's weapon. A weapon
-- that breaks ends the run.
local ABSORB = 0.25
local STAT_KEYS = {"attack", "endurance", "speed", "magic"}
local BROKEN = {[257] = true, [299] = true, [314] = true, [331] = true, [347] = true, [363] = true} -- the broken starters


-- What `into` becomes after absorbing `from`.
local function absorbed(into, from)
  local out = {elem = {}}
  for _, k in ipairs(STAT_KEYS) do
    out[k] = math.floor(clamp((tonumber(into.stats[k]) or 0) + (tonumber(from.stats[k]) or 0) * ABSORB, 0, 32767))
  end
  for e = 1, 5 do
    out.elem[e] = math.floor(clamp((tonumber(into.elements[e]) or 0) + (tonumber(from.elements[e]) or 0) * ABSORB, 0, 127))
  end
  return out
end

local function absorb(into_character, into, from_character, from)
  local s = absorbed(into, from)
  try(game.weapons.stats_set, {id = into.id, character = into_character, slot = into.slot, attack = s.attack,
      endurance = s.endurance, speed = s.speed, magic = s.magic, elem = s.elem})
  try(game.weapons.remove, {id = from.id, character = from_character, slot = from.slot})
  return s
end

local function choice_line(tag, chosen, w, s)
  local d = w.stats
  return string.format("%s%s LV%d ATK%d MAG%d END%d DUR%d/%d", chosen and "[" or " ", tag .. (chosen and "]" or " "), w.level,
      s.attack, s.magic, s.endurance, math.floor(tonumber(d.durability_current) or 0), math.floor(tonumber(d.durability) or 0)):sub(1, 48)
end

local function draw_choice()
  local k, t = choice.keep, choice.take
  try(game.render.layer_register, {id = "choice_a", text = ("ONE WEAPON FOR " .. choice.character:upper() .. ": L1/R1 PICK, X KEEPS"):sub(1, 48)})
  try(game.render.layer_register, {id = "choice_b", text = choice_line("KEEP HELD", choice.pick == 1, k, absorbed(k, t))})
  try(game.render.layer_register, {id = "choice_c", text = choice_line("TAKE FOUND", choice.pick == 2, t, absorbed(t, k))})
end

local function open_choice(character, keep, take)
  choice = {character = character, keep = keep, take = take, pick = 1, armed = frame + 20}
  local ctx = try(game.input.context_push, {id = "choice"})
  choice.token = ctx and ctx.token
  for _, id in ipairs({"choice_prev", "choice_next", "choice_ok"}) do try(game.input.consume, {id = id}) end
  refresh() -- hides the HUD line to make room
  draw_choice()
end

local function close_choice()
  for _, id in ipairs({"choice_a", "choice_b", "choice_c"}) do try(game.render.layer_remove, {id = id}) end
  if choice.token then try(game.input.context_pop, {token = choice.token}) end
  choice = nil
  refresh()
end

local function confirm_choice()
  local c, k, t = choice.character, choice.keep, choice.take
  if choice.pick == 2 then
    local ok, err = call(game.weapons.equip, {id = t.id, character = c, slot = t.slot})
    if not ok then toast("Cannot change weapons right now (" .. errmsg(err) .. "). Try again in a moment.", 180); return end
    k, t = t, k
  end
  local s = absorb(c, k, c, t)
  run.weapons[c] = {id = k.id, slot = k.slot}
  save_run()
  toast(string.format("%s %s the %s weapon and absorbs the other: ATK %d, MAG %d, END %d", title(c), choice.pick == 2 and "takes" or "keeps",
      choice.pick == 2 and "found" or "held", s.attack, s.magic, s.endurance), 300)
  close_choice()
end

local function poll_choice()
  if not choice then return end
  try(game.input.block_native, {buttons = {"l1", "r1", "cross"}, frames = 4})
  try(game.player.invincible, {frames = 30})
  local prev, nxt = try(game.input.consume, {id = "choice_prev"}), try(game.input.consume, {id = "choice_next"})
  local ok = try(game.input.consume, {id = "choice_ok"})
  if (prev and prev.pressed) or (nxt and nxt.pressed) then choice.pick = 3 - choice.pick; draw_choice() end
  if ok and ok.pressed and frame >= choice.armed then confirm_choice() end
end

-- A found weapon: pre-leveled, then the choice (or absorbed, if it belongs to someone outside the draft).
moonmod.on("game.item_picked_up", function(e)
  if not on_route() or e.kind ~= "weapon" then return end
  local character = type(e.character) == "number" and CHARACTERS[e.character + 1] or e.character
  if type(character) ~= "string" or type(e.slot) ~= "number" then return end
  if setting("preroll_weapons", true) then
    local selector = {id = e.id, character = character, slot = e.slot}
    local roll = math.random(100)
    local levels = roll <= 10 and 4 or (roll <= 30 and 3 or (roll <= 60 and 2 or 1))
    local gained = level_up(selector, levels)
    local attached = insert_attachments(selector, math.random(100) <= 35 and 2 or 1)
    if gained > 0 or attached > 0 then
      toast(string.format("Found weapon: +%d level%s, %d attachment%s", gained, gained == 1 and "" or "s", attached, attached == 1 and "" or "s"), 240)
    end
  end
  local found = weapon_info(e.id, character, e.slot)
  if not found then return end
  if choice or not contains(run.drafted, character) then
    local p = try(game.player.get)
    local w = p and p.weapon
    local into = w and w.id and weapon_info(w.id, p.character, w.slot)
    if not into then return end
    local s = absorb(p.character, into, character, found)
    toast(string.format("A weapon for %s, who is not in this run: absorbed into %s's. ATK %d, MAG %d, END %d", title(character),
        title(p.character), s.attack, s.magic, s.endurance), 300)
    return
  end
  local held = equipped_weapon(character)
  local keep = held and weapon_info(held.id, character, held.slot)
  if not keep or keep.slot == found.slot then return end
  open_choice(character, keep, found)
end)

-- A broken weapon ends the run.
local function check_break(p)
  local w = p.weapon
  if run.broken or not w or choice then return end
  if not (BROKEN[tonumber(w.item_no) or 0] or (tonumber(w.durability) or 1) <= 0) then return end
  run.broken = true
  save_run()
  toast(title(p.character) .. "'s weapon broke. The run is over.", 360)
  queue_transition("end", 180, "weapon broke")
end

-- Atla: each sphere picked up on a run floor gives a Diorama tile ----------------------------------------
local function atla_ids()
  local list = try(game.georama.atla_list)
  local entries = type(list) == "table" and (list.atla or list.spheres or list.entries or list) or {}
  local ids = {}
  for _, a in ipairs(entries) do
    if type(a) == "table" then ids[tostring(a.atla_id or a.id or a.registry_index or a.slot)] = true end
  end
  return ids
end
local function poll_atla()
  local now = atla_ids()
  if floor.atla then
    for id in pairs(floor.atla) do
      if not now[id] then give_tiles(1, "Atla"); save_run(); update_sheet() end
    end
  end
  floor.atla = now
end

-- Draft enforcement: only drafted allies fight ------------------------------------------------------------
local bounce_at = 0
local function enforce_draft(p)
  if not setting("enforce_draft", true) or contains(run.drafted, p.character) or frame < bounce_at then return end
  bounce_at = frame + 120
  for _, c in ipairs(run.drafted) do
    if try(game.party.set_active, {id = c}) then
      toast(title(p.character) .. " is not drafted for this run. Back to " .. title(c) .. ".", 240)
      return
    end
  end
end

-- Cursed Gate toggle -------------------------------------------------------------------------------------
local function toggle_curse()
  if not on_route() then toast("Toggle the Cursed Gate on a Gauntlet floor."); return end
  if run.slot == WARDEN_SLOT - 1 then toast("The next floor is the Warden's: it cannot be cursed."); return end
  run.next_cursed = not run.next_cursed
  toast(run.next_cursed and "CURSED GATE: the next floor is cursed (tougher, two curses) and pays a Miracle cache." or
        "Cursed Gate closed: the next floor is normal.", 300)
  save_run()
  refresh()
end
local _, bind_err = call(game.input.bind, {id = "curse_key", keys = {setting("curse_key", "G")}})
if bind_err then moonmod.log("warn", "bind curse_key: " .. errmsg(bind_err)) end
call(game.input.bind, {id = "curse_pad_l1", keys = {"Gamepad:leftshoulder"}})
call(game.input.bind, {id = "curse_pad_back", keys = {"Gamepad:back"}})
-- The HUD's cache chest: our own art, under a game path the engine draws HUD icons from.
call(game.resources.override, {path = "resources/hud/cache.png", game_path = HUD_CACHE_IMAGE})
-- The weapon choice reads these only while its context is on top.
call(game.input.bind, {id = "choice_prev", context = "choice", keys = {"Gamepad:leftshoulder", "Left"}})
call(game.input.bind, {id = "choice_next", context = "choice", keys = {"Gamepad:rightshoulder", "Right"}})
call(game.input.bind, {id = "choice_ok", context = "choice", keys = {"Gamepad:a", "Return"}})
local function poll_input()
  local key = try(game.input.consume, {id = "curse_key"})
  local back = try(game.input.consume, {id = "curse_pad_back"})
  local l1 = try(game.input.state, {id = "curse_pad_l1"})
  if (key and key.pressed) or (back and back.pressed and l1 and l1.down) then toggle_curse() end
end

-- Transitions ----------------------------------------------------------------------------------------------
-- Between biomes the run moves with world.transition; the last Warden ends the session with session.end.
local function pump_transition()
  local t = pending_transition
  if not t or frame < t.at then return end
  local result, err
  if t.id == "end" then result, err = call(game.session.finish)
  else result, err = call(game.world.transition, {id = t.id}) end
  if result then
    pending_transition = nil
    return
  end
  t.tries = t.tries + 1
  t.at = frame + 90
  if t.tries >= 20 then
    pending_transition = nil
    toast("Could not move the run on (" .. errmsg(err) .. "). Take the floor exit to leave the Gauntlet.", 480)
  end
end

-- Session: the engine reports how the sandbox session ended -----------------------------------------------
moonmod.on("game.session.ended", function(e)
  if not run or not e or e.owner ~= ID then return end
  if run.phase == "victory" then end_run("victory")
  elseif run.broken then end_run("broken")
  elseif e.reason == "defeat" then end_run("death")
  else end_run("retreat") end
end)

local function watch_floor()
  local world = try(game.world.get)
  if not (world and world.context == "dungeon" and type(world.dungeon_id) == "number" and type(world.floor_id) == "number") then return end
  world.token = world.dungeon_id .. ":" .. world.floor_id .. ":" .. tostring(world.floor_seed) .. ":" .. tostring(world.back_floor)
  if not floor or floor.token ~= world.token then enter_floor(world) end
end

-- Tick ---------------------------------------------------------------------------------------------------------
moonmod.on("game.tick", function(e)
  frame = e and e.frame or frame + 1
  if not run then return end
  pump_transition()
  poll_input()
  poll_choice()
  if run.phase == "active" and floor then
    local p = try(game.player.get)
    if p then check_break(p) end
  end
  if frame % 15 ~= 0 then return end
  local session = try(game.session.get)
  if not (session and session.kind == "sandbox" and session.owner == ID) then return end
  watch_floor()
  if not run or not on_route() then return end
  local p = try(game.player.get)
  if p then
    if frame % 60 == 0 then enforce_draft(p) end
    if p.weapon and p.weapon.id then run.weapons[p.character] = {id = p.weapon.id, slot = p.weapon.slot} end
    if contains(run.drafted, p.character) then run.leader = p.character end
    local regen = placed("tree") + (blessed("mender") and 2 or 0)
    if regen > 0 and frame % 180 == 0 and (p.hp or 0) > 0 and p.hp < p.max_hp then try(game.player.heal, {amount = regen}) end
  end
  local result = try(game.entities.query, {type = "monster"})
  scale_enemies(result and result.entities or {})
  update_warden_bar()
  if frame % 60 == 0 then poll_atla() end
  if frame - floor.entered > 180 and not floor.swept then
    local combat = try(game.combat.get)
    local alive = combat and tonumber(combat.remaining)
    if alive then floor.seen = math.max(floor.seen, alive) end
    if alive and floor.seen > 0 and alive == 0 then
      floor.swept = true
      if floor.slot == WARDEN_SLOT and not floor.warden then warden_cleared()
      else toast("Floor swept: an extra Diorama tile when you take the exit.", 240) end
    end
  end
end)

-- Diorama placement and Eternal purchases from the Journal page / Skills tab ---------------------------
moonmod.on("skills.train_requested", function(event)
  local id = type(event.id) == "string" and event.id or ""
  local prefix = ID .. ":"
  if id:sub(1, #prefix) ~= prefix then return end
  local tree, node = id:sub(#prefix + 1):match("^([%w_]+)%.([%w_]+)$")
  if tree == "diorama" and TILE[node] then
    if not run then toast("Tiles are placed during a run."); return end
    if (tonumber(run.stock[node]) or 0) < 1 then toast("No " .. TILE[node].title .. " tiles in stock."); return end
    if placed_total() >= plots() then toast("The Diorama is full (" .. plots() .. " plots). Clear it in Actions to rearrange."); return end
    run.stock[node] = run.stock[node] - 1
    run.diorama[node] = placed(node) + 1
    try(game.skills.set_rank, {id = node_id("diorama", node), rank = run.diorama[node]})
    toast(TILE[node].title .. " placed (" .. placed_total() .. "/" .. plots() .. "). " .. TILE[node].description, 300)
    save_run()
    refresh()
  elseif tree == "eternal" and ETERNAL_NODE[node] then
    local n = ETERNAL_NODE[node]
    local rank = eternal(node)
    if rank >= n.max_rank then toast(n.title .. " is complete."); return end
    local cost = n.costs[rank + 1]
    if meta.shards < cost then toast(n.title .. " needs " .. cost .. " Moon Shards (you have " .. meta.shards .. ")."); return end
    meta.shards = meta.shards - cost
    meta.eternal[node] = rank + 1
    save_meta()
    try(game.skills.set_rank, {id = node_id("eternal", node), rank = rank + 1})
    toast(n.title .. " " .. (rank + 1) .. "/" .. n.max_rank .. " unlocked  (" .. meta.shards .. " Moon Shards left)", 300)
    refresh()
  end
end)

-- Manager actions -----------------------------------------------------------------------------------------
local ACTIONS = {
  {"status", "Run Status", "Biome, floor, depth, curses, Diorama and blessings"},
  {"curse", "Toggle Cursed Gate", "Curse the next floor for a Miracle cache (also G, or L1+Select)"},
  {"page", "Open Run Page", "Journal > Character: the Diorama and Norune Eternal trees"},
  {"diorama_clear", "Clear Diorama", "Take every placed tile back into stock to rearrange"},
  {"heirloom", "Bank Heirloom", "Spend a Warden charge: keep half your weapon's stats for future runs"},
  {"gaffer_repair", "Gaffer: Repair Powder", "Floor II of each biome with Gaffer's Wagon: 2 Repair Powder"},
  {"gaffer_food", "Gaffer: Bread & Water", "Floor II of each biome with Gaffer's Wagon: 2 Bread, 2 Tasty Water"},
  {"abandon", "Abandon Run", "Leave the Gauntlet now (a retreat): back to its title screen"},
  {"records", "Eternal Records", "Moon Shards, runs, wins, best depth and the Heirloom"},
}
for _, a in ipairs(ACTIONS) do try(game.ui.register, {id = a[1], label = a[2], description = a[3]}) end

local function gaffer(items, price)
  if eternal("gaffer") < 1 then toast("Unlock Gaffer's Wagon in Norune Eternal first."); return end
  if not on_route() or run.slot ~= 2 then toast("Gaffer's Wagon stops on floor II of each biome."); return end
  if eternal("gaffer") >= 2 then price = math.floor(price * 2 / 3) end
  local spent, err = call(game.economy.spend, {amount = price})
  if not spent then toast("Gaffer wants " .. price .. " Gilda (" .. errmsg(err) .. ")."); return end
  local n = 0
  for _, it in ipairs(items) do
    local got = try(game.items.give, {id = "chronicle:item:" .. it[1], count = it[2]})
    n = n + (got and got.added or 0)
  end
  toast("Gaffer: \"Pleasure doing business!\"  " .. n .. " item" .. (n == 1 and "" or "s") .. " for " .. price .. " Gilda", 240)
end


local function bank_heirloom()
  if not run or (run.heirloom_charges or 0) < 1 then toast("Heirloom charges come from Wardens once Heirloom Vault is unlocked."); return end
  local p = try(game.player.get)
  local w = p and p.weapon
  if not (w and w.id) then toast("Equip a weapon first."); return end
  local inst = nil
  for _, i in ipairs(weapon_instances(w.id)) do if i.character == p.character and i.slot == w.slot then inst = i end end
  if not inst then toast("Could not read the weapon."); return end
  local s = inst.stats or {}
  local h = {weapon = w.id, attack = math.floor((tonumber(s.attack) or 0) / 2), endurance = math.floor((tonumber(s.endurance) or 0) / 2),
             speed = math.floor((tonumber(s.speed) or 0) / 2), magic = math.floor((tonumber(s.magic) or 0) / 2), elem = {}}
  for e = 1, 5 do h.elem[e] = math.floor((tonumber(inst.elements and inst.elements[e]) or 0) / 2) end
  meta.heirloom = h
  run.heirloom_charges = run.heirloom_charges - 1
  save_meta(); save_run()
  toast(string.format("HEIRLOOM banked: +%d attack, +%d magic, +%d endurance, +%d speed for every new run's weapon", h.attack, h.magic, h.endurance, h.speed), 420)
end

moonmod.on("ui.action", function(a)
  if a.id == "abandon" then
    if not run then toast("No run is under way. Start one from the title menu: Dark Genie's Gauntlet."); return end
    local ok, err = call(game.session.finish)
    if not ok then toast("Could not leave now (" .. errmsg(err) .. ").") end
  elseif a.id == "status" then
    if not run then toast(string.format("No run. Moon Shards %d. Start one from the title menu: Dark Genie's Gauntlet.", meta.shards)); return end
    local b = biome_def(run.pos)
    local curses = floor and floor.cursed and names_of(floor.curses, CURSES) or "none"
    toast(string.format("%s %s | depth %d/%d | %s | curses: %s | Diorama %d/%d | blessings %d | kills %d | +%d shards",
        b and b.name or "?", FLOOR_LABEL[run.slot] or "-", run.depth, total_floors(), run.suspended and "OFF ROUTE" or run.phase,
        curses, placed_total(), plots(), #run.blessings, run.kills, run.shards), 600)
  elseif a.id == "curse" then toggle_curse()
  elseif a.id == "heirloom" then bank_heirloom()
  elseif a.id == "gaffer_repair" then gaffer({{ITEM.repair, 2}}, 300)
  elseif a.id == "gaffer_food" then gaffer({{ITEM.bread, 2}, {ITEM.water, 2}}, 240)
  elseif a.id == "diorama_clear" then
    if not run then toast("No run is under way."); return end
    for _, id in ipairs(TILE_IDS) do run.stock[id] = (tonumber(run.stock[id]) or 0) + placed(id); run.diorama[id] = 0 end
    push_diorama_ranks()
    save_run(); refresh()
    toast("Diorama cleared: every tile is back in stock.")
  elseif a.id == "records" then
    local h = meta.heirloom
    toast(string.format("Moon Shards %d | runs %d, wins %d, deaths %d, retreats %d | best depth %d | Heirloom: %s", meta.shards, meta.runs, meta.wins,
        meta.deaths, meta.retreats, meta.best_depth, h and string.format("+%d atk +%d mag", h.attack or 0, h.magic or 0) or "none"), 600)
  elseif a.id == "page" then
    update_sheet()
    local ok, err = call(game.ui.sheet_open)
    if not ok then
      local nav = try(game.ui.navigate, {mod_id = ID, tab = "skills"})
      if not nav then toast("Open Journal > Character, or this mod's Skills tab (" .. errmsg(err) .. ").") end
    end
  end
end)

moonmod.on("settings.changed", function() refresh() end)

-- Other mods can ask about the run (e.g. to stand down their own enemy scaling).
try(game.scripts.register_function, {id = "run_state", description = "Moon Gauntlet run: active, biome, floor, depth, cursed"}, function()
  return {active = run ~= nil and run.phase == "active" and not run.suspended, biome = run and run.pos or 0, floor = run and run.slot or 0,
          depth = run and run.depth or 0, cursed = floor and floor.cursed or false}
end)

-- Start-up: a run still in storage was cut short when the game closed mid-run: it counts as a retreat.
push_eternal_ranks()
if run then
  run.biomes = type(run.biomes) == "table" and run.biomes or {1}
  run.shards = tonumber(run.shards) or 0
  run.depth = tonumber(run.depth) or 0
  run.kills = tonumber(run.kills) or 0
  if run.phase == "launch" then run = nil; save_run() else end_run("retreat") end
end
refresh()
local ready = 0
for index in ipairs(BIOMES) do if route_ready(index) then ready = ready + 1 end end
moonmod.log("info", string.format("Moon Gauntlet ready: %d of %d biomes registered, %d Moon Shards%s", ready, #BIOMES, meta.shards, run and ", a run is in progress" or ""))
