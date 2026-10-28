-- Dungeon+: replay floors at Tiers 1-5 (Square/Triangle on the floor list), floor mutators, a bounty
-- on every floor, kill streaks, a bestiary and trophies in the Journal tab, enemies that get back up,
-- and the DarkCloud-Expanded weapon, price and shop data (BSD-2-Clause, (c) Gundorada Workshop).
-- Storage keys and trophy ids are the same as the previous version, so progress carries over.

local MAX_TIER = 5
local function try(fn, ...)
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end
local function toast(message, frames) try(game.ui.notify, {message = message:sub(1, 190), duration_frames = frames or 240}) end

-- Sandbox modes (Dark Genie's Gauntlet) are their own game: during one, every handler below sits out.
local in_sandbox = false
local function on(name, handler)
  moonmod.on(name, function(...)
    if not in_sandbox then return handler(...) end
    if name == "ui.action" then toast("Dungeon+ sits out Dark Genie's Gauntlet runs") end
  end)
end
local function setting(id, fallback)
  local value = moonmod.settings.get(id)
  if type(value) ~= type(fallback) then return fallback end
  return value
end
local function clamp(v, lo, hi) v = tonumber(v) or lo; return math.max(lo, math.min(hi, math.floor(v))) end
local function store(key, value) moonmod.storage.set(key, value) end

-- Difficulty preset: scales the tunables below instead of replacing them.
local PRESETS = {
  relaxed  = {mutator = 0.6, revive = 0.4, tier_hp = 0.7, reward = 1.5, speed = 0.9},
  normal   = {mutator = 1.0, revive = 1.0, tier_hp = 1.0, reward = 1.0, speed = 1.0},
  hardcore = {mutator = 1.6, revive = 1.6, tier_hp = 1.4, reward = 0.75, speed = 1.15}
}
local function preset() return PRESETS[setting("difficulty_preset", "normal")] or PRESETS.normal end
local function reward(amount) return clamp(amount * setting("feats_reward_scale", 100) / 100 * preset().reward + 0.5, 0, 32767) end
local function pay(amount) if amount > 0 then try(game.economy.add, {amount = amount}) end end

-- Enemy labels used by the legacy Dungeon Feats bestiary and notifications.
-- The table is keyed by Chronicle's native monster-table index.
local ENEMY_NAMES={
 [0]="Master Jacket",[1]="Skeleton Soldier",[2]="Statue",[3]="Dasher",[4]="Werewolf",[5]="FliFli",[6]="Hornet",[7]="Halloween",
 [8]="Cannibal Plant",[9]="Earth Digger",[10]="Sunday",[11]="Monday",[12]="Tuesday",[13]="Wednesday",[14]="Thursday",[15]="Friday",[16]="Saturday",
 [17]="Witch Hellza",[18]="Witch Illza",[19]="Gunny",[20]="Gyon",[21]="Pirate's Chariot",[22]="Auntie Medu",[23]="Captain",[24]="Corcea",[25]="Golem",
 [26]="Mr. Blare",[27]="Dune",[28]="Titan",[29]="King Mimic (Divine Beast Cave)",[30]="Mimic (Divine Beast Cave)",
 [31]="King Mimic (Sun & Moon Temple)",[32]="Mimic (Sun & Moon Temple)",[33]="King Mimic (Moon Sea)",[34]="Mimic (Moon Sea)",
 [35]="Arthur",[36]="Ghost",[37]="Alexander",[38]="Heart",[39]="Club",[40]="Diamond",[41]="Spade",[42]="Joker",[43]="Bomber Head",
 [44]="Mummy",[45]="Lich",[46]="Curse Dancer",[47]="Living Armor",[48]="White Fang",[49]="Moon Bug",[50]="Phantom",[51]="Dragon",
 [52]="Cave Bat",[53]="Evil Bat",[54]="Hell Pockle",[55]="Rash Dasher",[56]="Steel Giant",[57]="Blizzard",[58]="Moon Digger",
 [59]="Dark Flower",[60]="Cursed Rose",[61]="Billy",[62]="Vulcan",[63]="Crabby Hermit",[64]="Space Gyon",[65]="Blue Dragon",[66]="Black Dragon",
 [67]="Mask of Prajna",[68]="Crescent Baron",[69]="Rockanoff",[70]="King Mimic (Wise Owl Forest)",[71]="Mimic (Wise Owl Forest)",
 [72]="King Mimic (Shipwreck)",[73]="Mimic (Shipwreck)",[74]="King Mimic (Gallery of Time)",[75]="Mimic (Gallery of Time)",
 [76]="Ice Arrow",[77]="Sam",[78]="Dran",[79]="Master Utan",[80]="Ice Queen",[81]="King's Curse Coffin",[82]="King's Curse",
 [83]="Minotaur Joe",[84]="Dark Genie",[85]="Dark Genie Right Hand",[86]="Dark Genie Left Hand",[87]="(DG effect c17_)",
 [88]="(DG companion c17_)",[89]="(DG companion c17_)",[90]="(DG companion c17_)",[91]="Wine Keg",[92]="Ice Aura",
 [93]="(DG companion c17_)",[94]="Gol",[95]="Sil",[96]="Yammich",[97]="Statue Dog",[98]="Opar",[99]="Haley Holey",
 [100]="King Prickly",[101]="Ice Barrier",[102]="Ice Prison",[103]="Ice Meteor",[104]="Ice Tornado",[105]="Gacious",[106]="Dark Genie (Final Form)",
 [111]="Gemron (Fire)",[112]="Nikapous",[113]="White Fang (Enhanced)",[114]="Arthur (Enhanced)",[115]="Sil (Enhanced)",[116]="Halloween (Enhanced)"
}
local function enemy_name(key)
  local n = tonumber(key)
  return n and (ENEMY_NAMES[n] or ("Enemy " .. n)) or tostring(key or "?")
end

-- Harder AI: five enemy scripts whose get-up chance is raised to 45%.
local HARDER_AI = {"e01a.stb", "e118a.stb", "e119a.stb", "e124a.stb", "e50a.stb"}
local function apply_harder_ai()
  for _, name in ipairs(HARDER_AI) do
    local ok, err = game.resources.override({path = "resources/dun/monstor/" .. name, game_path = "dun/monstor/" .. name})
    if not ok then moonmod.log("warn", "Harder AI " .. name .. ": " .. tostring(type(err) == "table" and err.message or err)) end
  end
end
apply_harder_ai()

-- Tiers -----------------------------------------------------------------------------------------------
local function tiers() local t = moonmod.storage.get("floor_tiers"); return type(t) == "table" and t or {} end
local function default_tier() return clamp(moonmod.storage.get("default_tier") or 0, 0, MAX_TIER) end
local function floor_key(d, f) return tostring(d) .. ":" .. tostring(f) end
local function tier_of(d, f)
  if d == nil or f == nil then return 0 end
  local t = tiers()[floor_key(d, f)]
  return clamp(t == nil and default_tier() or t, 0, MAX_TIER)
end
local function publish_badges()
  local b = tiers()
  b.default = default_tier()
  try(game.dungeons.set_badges, b)
end
local function apply_generation(tier)
  try(game.dungeons.set_layout, tier == 0 and {} or
      {rooms = 24 + tier * 4, area = 30 + tier * 2, room_min = 3, room_max = math.min(5, 3 + math.floor((tier - 1) / 2))})
  local mmin = clamp(setting("monsters_per_room_min", 150), 0, 300) / 100
  local mmax = math.max(mmin, clamp(setting("monsters_per_room_max", 300), 0, 300) / 100)
  local cmin = clamp(setting("chests_per_room_min", 75), 0, 150) / 100
  local cmax = math.max(cmin, clamp(setting("chests_per_room_max", 150), 0, 150) / 100)
  try(game.dungeons.set_population, {monsters_per_room = {min = mmin, max = mmax}, chests_per_room = {min = cmin, max = cmax}})
  try(game.dungeons.set_enemy_survival, {chance_percent = clamp(setting("enemy_revive_chance", 25) * preset().revive, 0, 100)})
end
on("game.dungeon.generating", function(e) apply_generation(tier_of(e.dungeon_id, e.floor_id)) end)

-- Square / Triangle (or [ ]) on the floor list change that floor's tier.
assert(game.input.bind({id = "tier_down", keys = {"[", "E", "Gamepad:x"}}))
assert(game.input.bind({id = "tier_up", keys = {"]", "Tab", "Gamepad:y"}}))
local function step_selected_tier()
  local down = game.input.consume({id = "tier_down"})
  local up = game.input.consume({id = "tier_up"})
  if not ((down and down.pressed) or (up and up.pressed)) then return end
  local s = try(game.dungeons.selection)
  if not s then return end
  local t = tiers()
  local next_tier = (tier_of(s.dungeon_id, s.floor_id) + ((up and up.pressed) and 1 or -1)) % (MAX_TIER + 1)
  t[floor_key(s.dungeon_id, s.floor_id)] = next_tier
  store("floor_tiers", t)
  publish_badges()
end

-- Mutators ----------------------------------------------------------------------------------------------
local MUTATORS = {
  glass    = {name = "Glass Cannon", text = "you deal and take 50% more damage"},
  iron     = {name = "Iron Hide", text = "enemies take 25% less damage but carry double Gilda"},
  bounty   = {name = "Gold Rush", text = "enemies carry 2.5x Gilda"},
  spring   = {name = "Fountain", text = "water slowly refills"},
  scorched = {name = "Scorched", text = "water drains faster"},
  lucky    = {name = "Lucky Day", text = "15% chance to deal double damage"}
}
local MUTATOR_IDS = {"glass", "iron", "bounty", "spring", "scorched", "lucky"}
local function apply_mutator_formulas(m)
  try(game.combat.register_formula, {id = "lucky", operation = "chance_multiply", value = 2, chance = m == "lucky" and 15 or 0, priority = 90})
  try(game.combat.register_formula, {id = "mutator_out", operation = "multiply", value = m == "glass" and 1.5 or (m == "iron" and 0.75 or 1), priority = 110})
  try(game.combat.register_player_formula, {id = "mutator_in", operation = "multiply", value = m == "glass" and 1.5 or 1, priority = 110})
end

-- Trophies (Journal tab) and stats ------------------------------------------------------------------
local TROPHIES = {
  {"first_blood", "First Blood", 1, 100, true}, {"hunter", "Hunter", 100, 500, true},
  {"slayer", "Slayer", 500, 2000, true}, {"exterminator", "Exterminator", 2000, 10000, true},
  {"streak_10", "On a Roll", 1, 500}, {"streak_25", "Unstoppable", 1, 2500},
  {"clear_5", "Floor Sweeper", 5, 500}, {"clear_25", "Dungeon Cleaner", 25, 3000}, {"clear_100", "Purifier", 100, 12000},
  {"species_20", "Collector", 20, 1500}, {"species_60", "Completionist", 60, 8000}, {"bounty_25", "Bounty Hunter", 25, 5000}
}
for _, q in ipairs(TROPHIES) do
  try(game.quests.register, {id = q[1], title = q[2], description = "Dungeon+ trophy",
      objectives = {{id = "progress", title = q[5] and (q[3] .. " enemy defeats") or q[2], target = q[3], event = q[5] and "game.enemy_defeated" or nil}},
      rewards = {{kind = "currency", amount = q[4]}}})
  local s = try(game.quests.get, {id = q[1]})
  if s and s.status == "registered" then try(game.quests.start, {id = q[1]}) end
end
local function advance(id)
  local q = try(game.quests.get, {id = id})
  local o = q and q.status == "active" and q.objectives and q.objectives[1]
  if o and (o.progress or 0) < o.target then try(game.quests.advance, {id = id, objective = "progress"}) end
end
game.events.subscribe("quests.completed", function(event)
  if type(event.id) == "string" and event.id:find("^moonmod%.dungeon%-plus:") then
    for _, q in ipairs(TROPHIES) do
      if event.id:sub(-#q[1]) == q[1] then toast("TROPHY: " .. q[2] .. "  +" .. q[4] .. " Gilda", 360) end
    end
  end
end)
local function stats()
  local s = moonmod.storage.get("dungeon_feats_v1")
  if type(s) ~= "table" then s = {} end
  s.kills, s.floors, s.bounties, s.best_streak = s.kills or 0, s.floors or 0, s.bounties or 0, s.best_streak or 0
  s.species = type(s.species) == "table" and s.species or {}
  return s
end
local function count_keys(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- Current floor ----------------------------------------------------------------------------------------
local floor = nil   -- {token, dungeon, number, tier, mutator, entered, seen, cleared, bounty, scaled = {}, speeds = {}}
local frame = 0
local streak, streak_last = 0, -100000

local function enter_floor(world)
  local token = world and world.context == "dungeon" and type(world.dungeon_id) == "number" and type(world.floor_id) == "number" and
      (floor_key(world.dungeon_id, world.floor_id) .. ":" .. tostring(world.floor_seed) .. ":" .. tostring(world.back_floor)) or nil
  if (floor and floor.token) == token then return end
  if not token then
    floor = nil
    apply_mutator_formulas(nil)
    apply_generation(default_tier())
    return
  end
  floor = {token = token, dungeon = world.dungeon_id, number = world.floor_id, tier = tier_of(world.dungeon_id, world.floor_id),
           entered = frame, seen = 0, cleared = false, scaled = {}, speeds = {}, champions = {}}
  streak = 0
  local chance = clamp((setting("mutator_chance", 35) + 3 * world.dungeon_id) * preset().mutator, 0, 100)
  if world.floor_id > 0 and math.random(100) <= chance then floor.mutator = MUTATOR_IDS[math.random(#MUTATOR_IDS)] end
  apply_mutator_formulas(floor.mutator)
  local intro = floor.tier > 0 and ("TIER " .. floor.tier .. " FLOOR") or nil
  if floor.mutator then
    local m = MUTATORS[floor.mutator]
    intro = (intro and intro .. "  |  " or "") .. m.name:upper() .. ": " .. m.text
  end
  if intro then toast(intro, 420) end
end

-- Ported from DarkCloud-Expanded (BSD-2-Clause, (c) Gundorada Workshop): mini-boss loot. Generated by port_loot.py.
-- Enemy keys are indexes of this game's monster table (dc.monster_model(i)); item and weapon ids are the game's.
local LEGACY_LOOT = {
  attachmentsTableLucky = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106},
  attachmentsTableUnlucky = {81, 82, 83, 84, 85, 91, 92, 93, 94, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120},
  itemTableLucky = {178, 183},
  itemTableUnlucky = {150, 235},
  dungeons = {
    [0] = {  -- Divine Beast Cavern
      rare = {[0] = {260}, [96] = {282}, [97] = {303}},
      common = {[0] = {260}, [1] = {290, 304}, [2] = {301}, [3] = {105}, [29] = {192, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [30] = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [51] = {101, 95}, [69] = {98}, [96] = {96}, [97] = {106}, [98] = {104}},
      boosts = {[260] = {attack = 15, elem = {0, 0, 0, 0, 50}, vs = {[1] = 50}}},
      weapons_early = {259, 260, 262, 290}, weapons_late = {259, 260, 262, 270, 290, 301, 304}, split_floor = 8,
      back_key = 224,
    },
    [1] = {  -- Wise Owl Forest
      rare = {[4] = {272}, [7] = {303}, [9] = {328}, [10] = {302}, [11] = {302}, [12] = {302}, [13] = {302}, [14] = {302}, [15] = {302}, [16] = {302}},
      common = {[9] = {327}, [10] = {183}, [11] = {183}, [12] = {183}, [13] = {183}, [14] = {183}, [15] = {183}, [16] = {183}, [70] = {192, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [71] = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [99] = {103, 310}, [100] = {316}},
      boosts = {[272] = {attack = 60, durability = 99, magic = 30}, [302] = {attack = 35, elem = {0, 0, 0, 40, 0}, vs = {[8] = 40}}},
      weapons_early = {264, 270, 283, 284, 286, 291, 301, 303, 304}, weapons_late = {264, 270, 283, 284, 286, 291, 301, 303, 304, 316, 321, 328}, split_floor = 9,
      back_key = 225,
    },
    [2] = {  -- Shipwreck
      rare = {[22] = {268}, [23] = {192}, [24] = {293}, [67] = {283}},
      common = {[19] = {100}, [20] = {321, 97}, [21] = {316, 178}, [22] = {106, 95}, [23] = {310}, [24] = {286}, [60] = {344}, [67] = {96}, [72] = {192, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [73] = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [77] = {334}},
      boosts = {[283] = {attack = 40, elem = {0, 0, 40, 0, 0}, vs = {[9] = 40}}, [293] = {s1 = 128}},
      weapons_early = {261, 265, 282, 284, 286, 302, 305, 316, 319, 327, 328}, weapons_late = {261, 265, 282, 284, 286, 302, 305, 319, 327, 328, 333, 335, 343}, split_floor = 9,
      back_key = 226,
    },
    [3] = {  -- Sun & Moon
      rare = {[25] = {267, 266}, [27] = {360}, [44] = {288}, [56] = {335}, [65] = {307}},
      common = {[25] = {183}, [26] = {368}, [27] = {178}, [31] = {192, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [32] = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [43] = {178}, [44] = {176, 102}, [56] = {104, 98}, [63] = {104}, [65] = {96, 97, 106}},
      boosts = {[335] = {attack = 30, elem = {0, 40, 0, 0, 0}, s2 = 2, vs = {[3] = 40}}},
      weapons_early = {263, 272, 282, 288, 293, 306, 318, 334, 337, 344}, weapons_late = {263, 272, 282, 288, 293, 306, 318, 334, 337, 344, 349, 350, 359}, split_floor = 9,
      back_key = 228,
    },
    [4] = {  -- Moon Sea
      rare = {[28] = {322}, [48] = {351}, [54] = {339}, [58] = {328}, [62] = {368}, [64] = {321}, [68] = {266, 354}},
      common = {[28] = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [33] = {192, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [34] = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [35] = {375, 359}, [48] = {105}, [49] = {178}, [54] = {343}, [58] = {317}, [62] = {102, 95, 105, 98}, [64] = {349}, [68] = {100}},
      boosts = {[321] = {durability = 99, elem = {0, 99, 0, 0, 0}, endurance = 99, s1 = 2, s2 = 1, vs = {[2] = 99}}, [343] = {s1 = 128}, [351] = {s2 = 4}, [368] = {attack = 50, elem = {40, 0, 0, 0, 0}, magic = 30, vs = {[0] = 40, [4] = 20}}},
      weapons_early = {272, 288, 281, 307, 322, 334, 344, 351, 352, 353}, weapons_late = {272, 288, 281, 307, 322, 334, 344, 351, 352, 353, 365, 374}, split_floor = 8,
      back_key = 229,
    },
    [5] = {  -- Gallery of Time
      rare = {[38] = {309}, [39] = {360}, [40] = {275}, [41] = {273}, [42] = {312}, [59] = {344}, [66] = {307}},
      common = {[37] = {285}, [38] = {336}, [39] = {316}, [40] = {98}, [41] = {274}, [42] = {312}, [46] = {289, 294}, [57] = {97, 96, 106}, [59] = {344, 292}, [61] = {328}, [66] = {102}, [74] = {192, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [75] = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}},
      boosts = {[273] = {durability = 99, elem = {40, 0, 0, 0, 40}, s1 = 64, s2 = 4, vs = {[9] = 30}}, [275] = {durability = 99, s2 = 2}, [307] = {elem = {0, 0, 40, 0, 0}, vs = {[5] = 40, [6] = 40}}, [309] = {durability = 99, elem = {40, 0, 40, 0, 40}}, [312] = {attack = 80, durability = 99, magic = 50, s1 = 128, s2 = 32}, [328] = {elem = {0, 0, 50, 0, 0}}, [344] = {s2 = 32}, [360] = {durability = 99, elem = {0, 0, 0, 50, 0}, endurance = 99, s2 = 16, vs = {[2] = 40, [4] = 40}}},
      weapons_early = {274, 281, 285, 292, 294, 308, 322, 336, 338, 339, 354, 360, 368, 375}, weapons_late = {274, 281, 285, 292, 294, 308, 322, 336, 338, 339, 354, 360, 368, 375}, split_floor = 99,
      back_key = 230,
    },
    [6] = {  -- Demon Shaft
      rare = {[111] = {339}, [112] = {269}, [121] = {334}, [122] = {325}, [132] = {328}, [143] = {271}, [144] = {338}, [154] = {336}},
      common = {[111] = {107, 101}, [121] = {107, 97}, [122] = {311, 290}, [130] = {95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [131] = {192, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106}, [132] = {107, 100}, [133] = {310}, [143] = {107, 103}, [144] = {304}, [154] = {107, 102}},
      boosts = {[271] = {elem = {0, 0, 0, 50, 0}}, [310] = {s2 = 32}, [328] = {elem = {0, 0, 50, 0, 0}}, [334] = {elem = {0, 50, 0, 0, 0}}},
      weapons_early = {276, 273, 275, 281, 285, 309, 311, 323, 325, 340, 338, 355, 359, 370, 371}, weapons_late = {276, 273, 275, 281, 285, 309, 311, 323, 325, 340, 338, 355, 359, 370, 371}, split_floor = 99,
      back_key = 231,
    },
  },
}

-- Champions: about one regular enemy in twelve (more at higher tiers) grows larger and tougher, pays
-- triple Gilda and XP, and drops its DarkCloud-Expanded themed loot.
local function pick(list) if type(list) == "table" and #list > 0 then return list[math.random(#list)] end end
local function champion_loot(dungeon, number, model)
  local data = LEGACY_LOOT.dungeons[dungeon]
  if not data then return nil end
  if data.rare[model] and math.random(100) <= 8 then return pick(data.rare[model]) end
  if data.common[model] and math.random(100) <= 40 then return pick(data.common[model]) end
  if math.random(100) <= 20 then return pick(number <= data.split_floor and data.weapons_early or data.weapons_late) end
  return pick(math.random(100) <= 60 and LEGACY_LOOT.attachmentsTableLucky or LEGACY_LOOT.attachmentsTableUnlucky)
end

-- Enemy stats for tiers and Gilda mutators: applied once per living enemy.
local function scale_enemies(roster)
  local tier, m = floor.tier, floor.mutator
  local money = (m == "iron" and 2 or (m == "bounty" and 2.5 or 1)) * (1 + setting("tier_gilda_percent", 40) * tier / 100)
  local hp_scale = 1 + setting("tier_hp_percent", 35) * preset().tier_hp * tier / 100
  local alive = {}
  for _, e in ipairs(roster) do
    local handle = e.entity_id or e.id
    local key = tostring(handle)
    alive[key] = true
    if handle and e.revealed == true and not floor.scaled[key] then
      local hp = e.health and tonumber(e.health.maximum) or 0
      local combat = e.combat or {}
      if hp > 0 then
        local drop = e.definition and e.definition.drop_item
        local champion = hp < 600 and (type(drop) ~= "number" or drop < 0) and
            math.random(100) <= clamp(setting("champion_chance", 8) + 2 * tier, 0, 100)
        local scale = champion and 3 or 1
        local request = {entity = handle, reward_money = math.min(2147483647, math.floor(math.max(0, tonumber(combat.reward_money) or 0) * money * scale + 0.5))}
        if tier > 0 or champion then
          request.max_hp = math.min(1000000, math.floor(hp * hp_scale * scale + 0.5))
          request.hp = request.max_hp
          request.defense = math.min(32767, math.floor(((tonumber(combat.defense) or 0) + setting("tier_defense", 2) * tier) * (champion and 1.5 or 1)))
        end
        if (tier > 0 or champion or money ~= 1) and not try(game.entities.set_stats, request) then
          request = nil
        end
        if request or (tier == 0 and not champion and money == 1) then floor.scaled[key] = true end
        if request and champion then
          floor.champions[key] = e.native_model_id
          try(game.entities.scale_set, {entity = handle, scale = 1.5})
          toast("A CHAMPION " .. enemy_name(e.native_model_id):upper() .. " stalks this floor!", 300)
        end
      end
    end
  end
  for key in pairs(floor.scaled) do if not alive[key] then floor.scaled[key] = nil end end
end

-- Enemy speed: each enemy keeps its own random speed roll.
local function vary_speeds(roster)
  local variance = clamp(setting("enemy_speed_variance", 25), 0, 50)
  local base = clamp(setting("enemy_base_speed_percent", 100), 60, 200) / 100 * preset().speed
  if variance == 0 and base == 1 then return end
  for _, e in ipairs(roster) do
    local handle = e.entity_id or e.id
    local motion = handle and try(game.physics.velocity_get, {entity = handle})
    if motion and motion.source == "native_movement" and motion.velocity then
      local v = motion.velocity
      local speed = math.sqrt(v.x * v.x + v.z * v.z)
      if speed > 0.0001 then
        local key = tostring(handle)
        local r = floor.speeds[key]
        if not r then r = {roll = math.random() * 2 - 1, base = speed}; floor.speeds[key] = r
        elseif not r.last or math.abs(speed - r.last) > 0.0005 then r.base = speed end
        local target = r.base * base * (1 + r.roll * variance / 100)
        if math.abs(target - speed) > 0.0005 and try(game.physics.velocity_set, {entity = handle, velocity = {x = v.x * target / speed, y = v.y, z = v.z * target / speed}}) then
          r.last = target
        end
      end
    end
  end
end

local function pick_bounty(roster)
  for _, e in ipairs(roster) do
    local drop = e.definition and e.definition.drop_item
    if type(e.native_model_id) == "number" and (type(drop) ~= "number" or drop < 0) then
      floor.bounty = {target = tostring(e.native_model_id), count = 0, need = clamp(setting("bounty_kills", 6), 1, 20)}
      toast("BOUNTY: defeat " .. floor.bounty.need .. " " .. enemy_name(floor.bounty.target), 300)
      return
    end
  end
end

-- Clear rewards: gems (and a slayer from Tier 3) per tier, delivered when there is room.
local GEMS = {96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107}
local SLAYERS = {112, 113, 114, 115, 116, 117, 118, 119, 120, 121}
local function pending_rewards()
  local r = moonmod.storage.get("clear_rewards_v2")
  if type(r) ~= "table" then r = {} end
  r.pending, r.paid = type(r.pending) == "table" and r.pending or {}, type(r.paid) == "table" and r.paid or {}
  return r
end
local function deliver_rewards(verbose)
  local r, count = pending_rewards(), 0
  while #r.pending > 0 do
    local got = try(game.items.give, {id = "chronicle:item:" .. r.pending[1], count = 1})
    if not got or (got.added or 0) < 1 then break end
    table.remove(r.pending, 1)
    count = count + 1
  end
  store("clear_rewards_v2", r)
  if count > 0 or verbose then toast("Clear rewards: " .. count .. " delivered" .. (#r.pending > 0 and (", " .. #r.pending .. " waiting for space") or "")) end
end

local function floor_cleared()
  floor.cleared = true
  local s = stats()
  s.floors = s.floors + 1
  store("dungeon_feats_v1", s)
  advance("clear_5"); advance("clear_25"); advance("clear_100")
  local gilda = reward((50 + 25 * math.max(0, floor.number)) * (1 + math.max(0, floor.dungeon)))
  pay(gilda)
  toast("FLOOR CLEARED  +" .. gilda .. " Gilda", 300)
  if floor.tier > 0 then
    local r = pending_rewards()
    for _, paid in ipairs(r.paid) do if paid == floor.token then return end end
    for _ = 1, floor.tier do r.pending[#r.pending + 1] = GEMS[math.random(#GEMS)] end
    if floor.tier >= 3 then r.pending[#r.pending + 1] = SLAYERS[math.random(#SLAYERS)] end
    r.paid[#r.paid + 1] = floor.token
    if #r.paid > 128 then table.remove(r.paid, 1) end
    store("clear_rewards_v2", r)
    deliver_rewards(true)
  end
end

-- Kills: bestiary, streaks, bounty, tier bonus -------------------------------------------------------
local counted = {}
on("game.enemy_defeated", function(e)
  if e.entity then
    if counted[e.entity] then return end
    counted[e.entity] = true
  end
  enter_floor(try(game.world.get))
  local s = stats()
  s.kills = s.kills + 1
  local key = type(e.native_model_id) == "number" and tostring(e.native_model_id) or nil
  if key then
    local fresh = s.species[key] == nil
    s.species[key] = (s.species[key] or 0) + 1
    local n = s.species[key]
    if fresh then
      advance("species_20"); advance("species_60")
      toast("Bestiary: " .. enemy_name(key) .. " discovered (" .. count_keys(s.species) .. " known)")
    elseif n == 10 or n == 50 or n == 150 then
      local g = reward(n * 2)
      pay(g)
      toast("Bestiary: " .. enemy_name(key) .. " x" .. n .. "  +" .. g .. " Gilda")
    end
  end
  local now = type(e.frame) == "number" and e.frame or frame
  streak = (now - streak_last <= 480) and streak + 1 or 1
  streak_last = now
  s.best_streak = math.max(s.best_streak, streak)
  if streak == 5 or streak == 10 or streak % 20 == 0 then
    local g = reward(streak * 5 * (1 + math.max(0, floor and floor.dungeon or 0)))
    pay(g)
    toast("KILL STREAK x" .. streak .. "  +" .. g .. " Gilda", 240)
  end
  if streak >= 10 then advance("streak_10") end
  if streak >= 25 then advance("streak_25") end
  if floor and floor.bounty and not floor.bounty.paid and key == floor.bounty.target then
    local b = floor.bounty
    b.count = b.count + 1
    if b.count >= b.need then
      b.paid = true
      local g = clamp(math.floor((150 + 60 * math.max(0, floor.number)) * (1 + 0.5 * math.max(0, floor.dungeon)) *
          setting("bounty_reward_percent", 100) / 100 * preset().reward), 0, 32767)
      pay(g)
      s.bounties = s.bounties + 1
      advance("bounty_25")
      toast("BOUNTY COMPLETE  +" .. g .. " Gilda", 300)
    else
      toast("Bounty " .. b.count .. "/" .. b.need, 120)
    end
  end
  if floor and floor.tier > 0 then pay(5 * floor.tier) end
  local champion = floor and e.entity and floor.champions[tostring(e.entity)]
  if champion then
    floor.champions[tostring(e.entity)] = nil
    local item = champion_loot(floor.dungeon, floor.number, champion)
    local given = item and (item >= 257 and try(game.weapons.give, {id = "chronicle:weapon:" .. item}) or
        try(game.items.give, {id = "chronicle:item:" .. item, count = 1}))
    toast("CHAMPION DEFEATED" .. (given and "  -  loot added to your bag" or ""), 300)
  end
  store("dungeon_feats_v1", s)
end)


-- Periodic work: one handler. Input every frame, floor bookkeeping every 15, enemy speeds every 30.
local badges_published = false
on("game.tick", function(e)
  frame = e and e.frame or frame + 1
  step_selected_tier()
  if frame % 15 ~= 0 then return end
  if not badges_published then publish_badges(); badges_published = true end
  enter_floor(try(game.world.get))
  if streak > 0 and frame - streak_last > 480 then streak = 0 end
  if not floor then return end
  local roster_result = try(game.entities.query, {type = "monster"})
  local roster = roster_result and roster_result.entities or {}
  if not floor.bounty then pick_bounty(roster) end
  scale_enemies(roster)
  if frame % 30 == 0 then vary_speeds(roster) end
  if not floor.cleared and frame - floor.entered > 180 then
    -- combat.remaining counts living monsters in every slot, awake or dormant.
    local combat = try(game.combat.get)
    local alive = combat and tonumber(combat.remaining)
    if alive then floor.seen = math.max(floor.seen, alive) end
    if alive and floor.seen > 0 and alive == 0 then
      local p = try(game.player.get)
      if p and p.hp > 0 then floor_cleared() end
    end
  end
  if floor.mutator and frame % 60 == 0 then
    if floor.mutator == "spring" then try(game.player.thirst_set, {restore = 1.5})
    elseif floor.mutator == "scorched" then try(game.player.thirst_set, {restore = -1.0}) end
  end
end)

-- Manager actions -------------------------------------------------------------------------------------
local bestiary_cursor = 0
for _, a in ipairs({
  {"status", "This Floor", "Tier, mutator, bounty and streak"},
  {"feats", "Stats", "Kills, clears, bounties, best streak and bestiary size"},
  {"bestiary", "Browse Bestiary", "Step through every enemy type and your defeats"},
  {"default_up", "Default Tier for New Floors", "Cycle the tier used by floors you have not set (0-5)"},
  {"claim", "Deliver Clear Rewards", "Hand out gems and slayers that were waiting for inventory space"}
}) do try(game.ui.register, {id = a[1], label = a[2], description = a[3]}) end
on("ui.action", function(a)
  if a.id == "status" then
    if not floor then toast("Not in a dungeon"); return end
    local b = floor.bounty
    toast(string.format("TIER %d  |  %s  |  BOUNTY %s  |  STREAK %d", floor.tier,
        floor.mutator and MUTATORS[floor.mutator].name or "no mutator",
        b and (enemy_name(b.target) .. " " .. b.count .. "/" .. b.need .. (b.paid and " done" or "")) or "none yet", streak), 480)
  elseif a.id == "feats" then
    local s = stats()
    toast(string.format("KILLS %d  |  CLEARS %d  |  BOUNTIES %d  |  BEST STREAK %d  |  BESTIARY %d", s.kills, s.floors, s.bounties,
        s.best_streak, count_keys(s.species)), 480)
  elseif a.id == "bestiary" then
    local keys = {}
    for id in pairs(ENEMY_NAMES) do keys[#keys + 1] = id end
    table.sort(keys)
    bestiary_cursor = bestiary_cursor % #keys + 1
    local id = keys[bestiary_cursor]
    local n = stats().species[tostring(id)] or 0
    toast(bestiary_cursor .. "/" .. #keys .. "  " .. (n > 0 and enemy_name(id) or "???") .. "  -  " .. (n > 0 and (n .. " defeated") or "not seen yet"), 360)
  elseif a.id == "default_up" then
    local t = (default_tier() + 1) % (MAX_TIER + 1)
    store("default_tier", t)
    publish_badges()
    apply_generation(t)
    toast("New floors start at Tier " .. t)
  elseif a.id == "claim" then
    deliver_rewards(true)
  end
end)

-- Ascension asks how much an enemy is worth: champions triple XP, each tier adds 25%.
try(game.scripts.register_function, {id = "enemy_bonus", description = "XP multiplier for a defeated enemy"}, function(args)
  local champion = floor and args and args.entity and floor.champions[tostring(args.entity)] ~= nil
  return {xp_multiplier = (champion and 3 or 1) * (1 + 0.25 * (floor and floor.tier or 0)), champion = champion}
end)
-- Other mods (Adventurer) can ask for the current tier.
try(game.scripts.register_function, {id = "current_tier", description = "Current floor's Dungeon+ tier"}, function()
  return {tier = floor and floor.tier or 0, mutator = floor and floor.mutator or ""}
end)

on("settings.changed", function() apply_generation(floor and floor.tier or default_tier()) end)

-- Sandbox sessions: native layout, population and enemy AI, no mutator, bounty, streak or champions for the
-- run; tiers and mutators come back afterwards. The Expanded Data weapon and price edits stay (the engine only
-- restores a weapon definition when this mod unloads).
local function set_sandbox(now)
  if now == in_sandbox then return end
  in_sandbox = now
  floor, streak = nil, 0
  apply_mutator_formulas(nil)
  if now then
    try(game.dungeons.set_layout, {}); try(game.dungeons.set_population, {}); try(game.dungeons.set_enemy_survival, {})
    for _, name in ipairs(HARDER_AI) do try(game.resources.unoverride, {game_path = "dun/monstor/" .. name}) end
  else
    apply_harder_ai()
    apply_generation(default_tier())
  end
end
moonmod.on("game.session.started", function() set_sandbox(true) end)
moonmod.on("game.session.ended", function() set_sandbox(false) end)
apply_mutator_formulas(nil)
apply_generation(default_tier())
local session = try(game.session.get)
set_sandbox(type(session) == "table" and session.kind == "sandbox")

-- Weapon table edits from the legacy Expanded Data package (DarkCloud-Expanded, BSD-2-Clause).
local LEGACY_WEAPON_BALANCE = {
  [259] = {endurance=30},
  [263] = {elem={15,0,0,0,20}, speed=70},
  [265] = {attack=25, durability=50, elem={0,0,8,0,0}, endurance=30, vs_monster={0,0,90,0,0,0,0,0,0,0}},
  [266] = {endurance=33, speed=80},
  [269] = {flags=8192},
  [271] = {attack_max=180, buildup_mask0=65536, hole={2,1,1,0,0,0}, magic_max=180},
  [272] = {hole={2,1,1,0,0,0}},
  [274] = {hole={2,1,1,0,0,0}},
  [275] = {speed=70},
  [281] = {attack_max=190, buildup_mask0=524288},
  [282] = {flags=4},
  [283] = {durability=35, magic=17, vs_monster={0,0,0,0,0,0,0,10,0,0}},
  [284] = {durability=45, endurance=25, hole={2,1,1,0,0,0}},
  [285] = {durability=60},
  [286] = {speed=60},
  [287] = {attack=45, buildup_mask0=2147483648, durability=57, elem={0,10,15,0,0}, hole={2,1,1,0,0,0}, speed=70, vs_monster={0,15,0,0,0,15,0,15,0,20}},
  [288] = {vs_monster={0,10,0,15,0,10,10,10,10,10}},
  [289] = {elem={0,15,15,0,15}, endurance=44, magic=45, speed=70, vs_monster={0,15,0,0,0,15,0,15,10,55}},
  [290] = {durability=38, magic=26},
  [291] = {elem={6,0,10,0,0}, speed=60, vs_monster={0,0,0,0,10,0,10,0,10,0}},
  [292] = {durability=47, endurance=47, magic=37, vs_monster={7,7,7,7,7,8,7,10,7,8}},
  [294] = {endurance=50, magic=32, speed=70},
  [298] = {attack_max=999},
  [300] = {attack=6, elem={4,0,0,0,0}, magic=2},
  [304] = {attack=11, endurance=30},
  [305] = {speed=60},
  [311] = {flags=4096},
  [319] = {magic=10},
  [320] = {buildup_mask0=8},
  [321] = {attack_max=100, buildup_mask0=0, durability=65, flags=64, hole={2,1,0,1,0,0}, magic_max=678},
  [322] = {endurance=25},
  [328] = {attack=30, endurance=25},
  [332] = {attack=15, magic=30},
  [333] = {attack=30, attack_max=50, magic=20},
  [335] = {attack=23},
  [336] = {flags=2048},
  [340] = {flags=8192},
  [343] = {attack=28, buildup_mask0=8256, elem={0,0,0,10,0}, magic=28},
  [344] = {attack_max=90, buildup_mask0=128, magic_max=72, vs_monster={0,0,0,20,0,20,0,0,0,0}},
  [348] = {attack=45, attack_max=65, endurance=35},
  [349] = {attack=48, attack_max=95, endurance=40},
  [350] = {attack=54, attack_max=90, endurance=43},
  [351] = {attack=56, attack_max=120, endurance=50, flags=1024},
  [352] = {attack=60, attack_max=109, endurance=50},
  [353] = {attack=65, attack_max=105, endurance=60},
  [354] = {attack=73, attack_max=160, endurance=60},
  [355] = {attack=130, attack_max=230, endurance=65},
  [356] = {attack=120, attack_max=266, endurance=85},
  [357] = {hole={2,1,1,1,0,0}},
  [358] = {attack=15, attack_max=15, endurance=20},
  [359] = {attack=50, attack_max=89, endurance=60},
  [360] = {attack=80, attack_max=165, endurance=60},
  [364] = {attack=37, attack_max=47},
  [365] = {attack=45, attack_max=70, buildup_mask0=4096},
  [366] = {attack=35, attack_max=55},
  [367] = {attack=45, attack_max=75},
  [368] = {attack=49, attack_max=102, magic_max=80},
  [369] = {attack=63, attack_max=158, buildup_mask0=0, magic_max=105},
  [370] = {attack=65, attack_max=114},
  [371] = {attack=79, attack_max=143},
  [372] = {attack=85, attack_max=135},
  [373] = {attack=143, attack_max=271},
  [374] = {attack=49, attack_max=80, buildup_mask0=256},
  [375] = {attack=63, attack_max=87},
}
local legacy_weapon_changes, legacy_weapon_failures = 0, 0
for item, fields in pairs(LEGACY_WEAPON_BALANCE) do
  local request = {id = tonumber(item)}
  for key, value in pairs(fields) do request[key] = value end
  local result, err = game.weapons.definition_set(request)
  if result then legacy_weapon_changes = legacy_weapon_changes + 1
  else
    legacy_weapon_failures = legacy_weapon_failures + 1
    moonmod.log("warn", "Expanded Data weapon " .. item .. " was not applied: " .. (type(err) == "table" and err.message or tostring(err)))
  end
end
if legacy_weapon_failures > 0 then moonmod.log("warn", string.format("Expanded Data applied %d of %d weapon definitions", legacy_weapon_changes, legacy_weapon_changes + legacy_weapon_failures)) end
-- Legacy Expanded Data prices (DarkCloud-Expanded, BSD-2-Clause).
-- Daily rotations below use the native adventure-day counter from game.world.get().
local LEGACY_PRICES={
  [133]={buy=400,sell=200},
  [134]={buy=400,sell=200},
  [181]={buy=400,sell=200},
  [186]={sell=75},
  [187]={sell=112},
  [188]={sell=100},
  [189]={sell=105},
  [190]={sell=95},
  [193]={sell=75},
  [197]={sell=100},
  [199]={sell=100},
  [224]={buy=600,sell=300},
  [225]={buy=750,sell=375},
  [226]={buy=300,sell=150},
  [228]={buy=900,sell=450},
  [229]={buy=1200,sell=600},
  [230]={buy=1500,sell=750},
  [231]={buy=5000,sell=2500},
  [259]={buy=500,sell=167},
  [260]={buy=650,sell=217},
  [261]={sell=833},
  [262]={buy=900,sell=300},
  [263]={buy=5000,sell=1667},
  [264]={buy=1800,sell=600},
  [265]={buy=3000,sell=1000},
  [266]={buy=4500,sell=1500},
  [267]={buy=9000,sell=3000},
  [268]={buy=3000,sell=1000},
  [269]={buy=5500,sell=1833},
  [270]={buy=1250,sell=417},
  [271]={buy=12000,sell=4000},
  [272]={buy=7888,sell=2629},
  [273]={buy=3642,sell=1214},
  [274]={buy=9500,sell=3167},
  [275]={buy=12726,sell=4242},
  [276]={buy=18000,sell=6000},
  [278]={buy=12000,sell=4000},
  [279]={buy=18000,sell=6000},
  [280]={buy=30000,sell=10000},
  [281]={buy=9021,sell=3007},
  [282]={buy=4500,sell=1500},
  [283]={buy=1900,sell=633},
  [284]={buy=2250,sell=750},
  [285]={buy=11500,sell=3833},
  [286]={buy=2500,sell=833},
  [287]={buy=5000,sell=1667},
  [288]={buy=6000,sell=2000},
  [289]={buy=8000,sell=2667},
  [290]={buy=1001,sell=334},
  [291]={buy=2150,sell=717},
  [292]={buy=9507,sell=3169},
  [293]={buy=5300,sell=1767},
  [294]={buy=10000,sell=3333},
  [295]={buy=23331,sell=7777},
  [296]={buy=32767,sell=12345},
  [297]={buy=32767,sell=13337},
  [298]={buy=32767,sell=15000},
  [301]={buy=900,sell=300},
  [302]={buy=4200,sell=1400},
  [303]={buy=1999,sell=666},
  [304]={buy=750,sell=250},
  [305]={buy=2800,sell=933},
  [306]={buy=3100,sell=1033},
  [307]={buy=5525,sell=1842},
  [308]={buy=9015,sell=3005},
  [309]={buy=18000,sell=6000},
  [310]={buy=2552,sell=851},
  [311]={buy=6666,sell=2222},
  [312]={buy=14000,sell=4667},
  [313]={buy=32767,sell=11111},
  [316]={buy=1700,sell=567},
  [317]={buy=7035,sell=2345},
  [318]={buy=6000,sell=2000},
  [319]={buy=2704,sell=901},
  [320]={buy=3250,sell=1083},
  [321]={buy=1701,sell=567},
  [322]={buy=8000,sell=2667},
  [323]={buy=12000,sell=4000},
  [324]={buy=21816,sell=7272},
  [325]={buy=19998,sell=6666},
  [327]={buy=2600,sell=867},
  [328]={buy=2300,sell=767},
  [329]={buy=32767,sell=11009},
  [330]={buy=2,sell=1},
  [333]={buy=3800,sell=1267},
  [334]={buy=4300,sell=1433},
  [335]={buy=2500,sell=833},
  [336]={buy=8000,sell=2667},
  [337]={buy=5000,sell=1667},
  [338]={buy=9000,sell=3000},
  [339]={buy=8000,sell=2667},
  [340]={buy=16314,sell=5438},
  [341]={buy=24000,sell=8000},
  [343]={buy=2007,sell=669},
  [344]={buy=3500,sell=1167},
  [345]={buy=32767,sell=12000},
  [346]={buy=2,sell=1},
  [349]={buy=3400,sell=1133},
  [350]={buy=4000,sell=1333},
  [351]={buy=4700,sell=1567},
  [352]={buy=6000,sell=2000},
  [353]={buy=5000,sell=1667},
  [354]={buy=7000,sell=2333},
  [355]={buy=13500,sell=4500},
  [356]={buy=21036,sell=7012},
  [357]={buy=32767,sell=11941},
  [359]={buy=5555,sell=1852},
  [360]={buy=6500,sell=2167},
  [361]={buy=2,sell=1},
  [362]={buy=2,sell=1},
  [365]={buy=4000,sell=1333},
  [368]={buy=6000,sell=2000},
  [369]={buy=10450,sell=3483},
  [370]={buy=11943,sell=3981},
  [371]={buy=12018,sell=4006},
  [372]={buy=24000,sell=8000},
  [373]={buy=24000,sell=8000},
  [374]={buy=3000,sell=1000},
  [375]={buy=9000,sell=3000},
}
local price_changes,price_failures=0,0
for item,price in pairs(LEGACY_PRICES) do
 local args={item_id=tonumber(item)};if price.buy then args.buy_price=price.buy end;if price.sell then args.sell_price=price.sell end
 if game.shops.set_price(args) then price_changes=price_changes+1 else price_failures=price_failures+1 end
end
if price_failures>0 then moonmod.log("warn",string.format("Dungeon+ shop rebalance rejected %d of %d item prices",price_failures,price_changes+price_failures)) end

-- Legacy Expanded Data daily stock (five adventure-day cycle).
-- Item IDs and pools are from the source Windows package; Chronicle restores changed lists on unload.
local SHOP_ROTATION={
 [0]={{181,181,224}, {95,96,97,98,99,100,101,102,103,104,105,106}, {197,199}, {132,133,134,135,150,154}, {259,260,262,270,290,301,304}},
 [1]={{186,188,189}, {132,133,134,135,150,154}, {264,270,283,284,286,291,301,303,304,316,321,328}, {181,181,225}, {95,96,97,98,99,100,101,102,103,104,105,106}},
 [8]={{261,265,282,284,286,302,305,319,327,328,333,335,343}, {261,265,282,284,286,302,305,319,327,328,333,335,343}, {261,265,282,284,286,302,305,319,327,328,333,335,343}, {261,265,282,284,286,302,305,319,327,328,333,335,343}, {261,265,282,284,286,302,305,319,327,328,333,335,343}},
 [12]={{95,96,97,98,99,100,101,102,103,104,105,106}, {186,188,189,197,199}, {132,133,134,135,150,154}, {111,112,113,114,115,116,117,118,119,120}, {181}},
 [9]={{132,133,134,135,150}, {263,272,282,288,293,306,318,334,337,344,349,350,359}, {181,181,228}, {95,96,97,98,99,100,101,102,103,104,105,106}, {169,186,188,189,193,197,199}},
 [10]={{181,181,229}, {95,96,97,98,99,100,101,102,103,104,105,106}, {118,119}, {132,133,134,135,150,154}, {272,288,281,307,322,334,344,351,352,353}},
 [11]={{274,281,285,292,294,308,322,336,338,339,354,360,368,375}, {181,181,230}, {169,186,187,188,189,193,197,199}, {132,133,134,135,150,154}, {181,181,230}},
}
local base_shop_items,last_shop_day,last_shop_attempt_frame=nil,nil,nil
local function without_item(list,item)
 local out={};for _,value in ipairs(list) do if value~=item then out[#out+1]=value end end;return out
end
local function load_shop_baseline()
 local base={}
 for shop=0,17 do
  local result,err=game.shops.get({shop_no=shop})
  if not result or type(result.items)~="table" then
   moonmod.log("warn","Expanded Data could not read shop "..shop..": "..(type(err)=="table" and err.message or tostring(err)));return nil
  end
  base[shop]={};for _,entry in ipairs(result.items) do base[shop][#base[shop]+1]=entry.item_no end
 end
 base[0]=without_item(base[0],92)
 for _,item in ipairs({118,119}) do
  local found=false;for _,value in ipairs(base[17]) do if value==item then found=true end end
  if not found then base[17][#base[17]+1]=item end
 end
 return base
end
local function update_daily_shops(day)
 if last_shop_attempt_frame and frame-last_shop_attempt_frame<300 then return end
 last_shop_attempt_frame=frame
 if not base_shop_items then base_shop_items=load_shop_baseline();if not base_shop_items then return end end
 local cycle=(day%5)+1
 local complete=true
 for shop=0,17 do
  local items={};for _,item in ipairs(base_shop_items[shop]) do items[#items+1]=item end
  local rotation=SHOP_ROTATION[shop];local pool=rotation and rotation[cycle]
  if pool and #pool>0 and #items<20 then
   -- Duplicate IDs in the source pools preserve their weighted selection.
   local index=((day*7919+shop*104729)%#pool)+1
   items[#items+1]=pool[index]
  end
  local current,read_err=game.shops.get({shop_no=shop})
  if current and type(current.items)=="table" then
   local same=#current.items==#items
   if same then for index,item in ipairs(items) do if current.items[index].item_no~=item then same=false;break end end end
   if not same then
    local result,err=game.shops.set_items({shop_no=shop,items=items})
    if not result then
     complete=false
     moonmod.log("warn","Expanded Data could not update shop "..shop..": "..(type(err)=="table" and err.message or tostring(err)))
    end
   end
  else
   complete=false
   moonmod.log("warn","Expanded Data could not refresh shop "..shop..": "..(type(read_err)=="table" and read_err.message or tostring(read_err)))
  end
 end
 if complete then last_shop_day=day else last_shop_day=nil end
end

-- Shops: check the daily stock on arrival somewhere new and every 10 seconds, not every frame.
on("game.world.location_changed", function() last_shop_day = nil end)
on("game.tick", function(e)
  if (e and e.frame or 0) % 600 ~= 0 and last_shop_day ~= nil then return end
  if (e and e.frame or 0) % 30 ~= 0 then return end
  local world = try(game.world.get)
  if world and type(world.day) == "number" and world.day ~= last_shop_day then update_daily_shops(math.floor(world.day)) end
end)
moonmod.log("info", string.format("Dungeon+ ready: %d weapon definitions, %d prices", legacy_weapon_changes, price_changes))
