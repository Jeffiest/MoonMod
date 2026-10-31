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
--   Warden        the Warden floor's exit room is sealed until the rest of the floor is cleared; walking in
--                 shuts it behind you and the Warden appears: the dungeon's own boss, or its toughest monster
--                 grown into one, with a HUD bar.
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
-- A notice pops up in the game's message window for five seconds; `icon` is a status badge or a registered png.
local NOTICE_FRAMES = 300
local function toast(message, icon)
  local notice = {message = tostring(message):sub(1, 196), duration_frames = NOTICE_FRAMES}
  if icon then
    notice.icon = icon
    if call(game.ui.notify, notice) then return end
    notice.icon = nil -- an engine without notice icons
  end
  try(game.ui.notify, notice)
end
local function title(id) return (tostring(id):gsub("^%l", string.upper)) end
local function pick(list) if type(list) == "table" and #list > 0 then return list[math.random(#list)] end end
local function contains(list, value) for _, v in ipairs(list or {}) do if v == value then return true end end; return false end
local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepcopy(x) end
  return out
end

-- Data ------------------------------------------------------------------------------------------------
-- Source floors are 0-based native floors whose enemy layouts the run floors copy. They avoid the floors
-- that hold story bosses (Divine Beast Cave floor 8 is Dran's; each dungeon's last floor is its boss).
local BIOMES = {
  {key = "dbc", dungeon = 0, name = "Divine Beast Cave", sources = {2, 5, 10, 7}, warden = 12},
  {key = "wof", dungeon = 1, name = "Wise Owl Forest", sources = {2, 5, 10, 8}, warden = 13},
  {key = "ship", dungeon = 2, name = "Shipwreck", sources = {2, 5, 11, 8}, warden = 14},
  {key = "temple", dungeon = 3, name = "Sun and Moon Temple", sources = {2, 5, 11, 8}, warden = 14}, -- the overlay font has no "&"
  {key = "sea", dungeon = 4, name = "Moon Sea", sources = {2, 5, 10, 7}, warden = 12},
}
local FLOOR_LABEL = {"I", "II", "III", "IV"}
-- The Warden's floor: 4, or 5 in a run with Endless Maze (set whenever a run starts, loads or ends).
local WARDEN_SLOT = 4
-- The heroes a run can draft, in engine order. Opar (Gauntlet only, still in development) is the first playable
-- character past the six, registered below (characters.register_playable, engine index 6); he is in the roster with
-- the Opar setting, and a run keeps the roster it started with (run.opar). ROSTER maps the engine's character
-- numbers; until his staffs (Opar plan phase 4) Opar fights as Toan, so Toan's weapons are his (ROSTER.fights_as).
local ROSTER = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond", "opar", fights_as = {opar = "toan"}}
local CHARACTERS = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond"}
function ROSTER.set(opar)
  opar = opar and ROSTER.registered
  for i = 1, #ROSTER do CHARACTERS[i] = (i <= 6 or opar) and ROSTER[i] or nil end
end
local MODE = "gauntlet"
local HUD_CACHE_IMAGE = "moonmod/roguelike/hud/cache.png" -- resources/hud/cache.png, the Miracle cache chest

-- Item numbers from Chronicle's item table (ps2/include/itemdata.hpp).
local ITEM = {bread = 148, water = 146, repair = 177, antidote = 151, holy_water = 152, auto_repair = 183}
-- The shortcut doors' keys (items 216-222), each door tinted to match.
local DOOR_KEYS = {[216] = "Bone Key", [217] = "Moustache Key", [218] = "Shipcabin Key", [219] = "Stone Key",
                   [220] = "Handle", [221] = "Pitchdark Key", [222] = "Silver Key"}
local function door_key_name(id) return DOOR_KEYS[tonumber(tostring(id):match("(%d+)$")) or 0] or "its key" end
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
  atla = {name = "Atla Sight", text = "every floor mapped, monsters shown"},
}
local BLESSING_IDS = {"moonlit", "stride", "ward", "tempered", "flask", "breath", "lucky", "scholar", "mender", "atla"}

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

-- Norune Eternal: the sky of unlocks -------------------------------------------------------------------------
-- Seven constellations around Norune Eternal, each a trunk that forks into build paths ending in a Keystone, and a
-- Signature sky per character. A node needs one of its links owned. Costs are Moon Shards, Genie Sigils (Keystones
-- and the deep nodes) or Character Marks (Signature skies). Every owned node can be switched off and set to any rank
-- owned; two Keystones can be on at once (three with Third Star). Pact nodes make runs harder and add Heat, and each
-- point of Heat pays +10% Moon Shards. ETERNAL_TREE.md is the design. Nodes marked soon are shown but not sold yet:
-- they need engine work still to come.
local SKY_GROUPS = {
  {id = "norune", name = "Norune Eternal", colour = {255, 240, 190}, angle = nil},
  {id = "arms", name = "Arms", colour = {248, 206, 92}, angle = -90},
  {id = "allies", name = "Allies", colour = {150, 214, 255}, angle = -39},
  {id = "fortune", name = "Fortune", colour = {196, 160, 255}, angle = 13},
  {id = "diorama", name = "Diorama", colour = {140, 226, 160}, angle = 64},
  {id = "pacts", name = "Dark Genie's Pacts", colour = {236, 92, 118}, angle = 116},
  {id = "provisions", name = "Provisions", colour = {120, 220, 200}, angle = 167},
  {id = "spirit", name = "Spirit", colour = {255, 170, 120}, angle = 219},
}
-- Opar's sky is shown once a run has met him (beating the Moon Sea Warden) or with the Opar setting on (`reveal`).
local SIGNATURE_CHARS = {"toan", "xiao", "goro", "ruby", "ungaga", "osmond", "opar"}
for i, c in ipairs(SIGNATURE_CHARS) do
  SKY_GROUPS[#SKY_GROUPS + 1] = {id = "sig_" .. c, name = (c:gsub("^%l", string.upper)) .. "'s Sky", colour = {230, 230, 255},
                                 angle = -90 + (i - 1) * 360 / #SIGNATURE_CHARS, signature = c, reveal = c == "opar" and "opar_met" or nil}
end
local SKY_GROUP = {}
for _, g in ipairs(SKY_GROUPS) do SKY_GROUP[g.id] = g end

-- {id, group, path (0 trunk), title, ranks, costs, needs, icon, text, extra}; extra: cur = "sigil"|"mark",
-- key (a Keystone), heat (per rank), soon, pos = {x, y} (relative to the constellation), path_name.
local ETERNAL = {}
local function N(id, group, path, title, ranks, costs, needs, icon, text, extra)
  local n = {id = id, group = group, path = path, title = title, max_rank = ranks, costs = costs, needs = needs or {},
             icon = icon, text = text}
  for k, v in pairs(extra or {}) do n[k] = v end
  ETERNAL[#ETERNAL + 1] = n
end
local S = {cur = "sigil"}
local function K(extra) local t = {cur = "sigil", key = true}; for k, v in pairs(extra or {}) do t[k] = v end; return t end

N("norune", "norune", 0, "Norune Eternal", 0, {}, {}, "crystal",
  "Moon Shards from every run, Genie Sigils from Wardens and wins at Heat 5+, Marks for the character who ran.")
N("third_star", "norune", 1, "Third Star", 1, {5}, {}, "crystal", "A third Keystone can be on at once.", {cur = "sigil", pos = {-120, 60}})
N("loadouts", "norune", 1, "Loadouts", 1, {20}, {}, "map", "Four saved sets of switches and ranks. Cross on Loadouts opens them.", {pos = {120, 60}})

-- Arms
N("whetstone", "arms", 0, "Whetstone", 3, {2, 4, 6}, {}, "sword", "+10 maximum durability on the starting weapon per rank.")
N("keen", "arms", 1, "Keen Edge", 3, {5, 10, 15}, {"whetstone"}, "sword", "+5% damage per rank.", {path_name = "Edge"})
N("smith", "arms", 1, "Smith's Start", 3, {5, 10, 15}, {"keen"}, "sword", "The starting weapon starts one level up per rank.")
N("charged", "arms", 1, "Charged Fury", 1, {12}, {"smith"}, "sword", "Charged attacks deal 30% more.")
N("moonstrike", "arms", 1, "Moon Strike", 2, {15, 25}, {"smith", "charged"}, "crystal", "5% of hits deal double damage per rank.")
N("moonblade", "arms", 1, "Moonblade", 1, {3}, {"moonstrike"}, "sword", "The first hit on each enemy deals triple damage.", K())
N("oil", "arms", 2, "Gaffer's Oil", 2, {3, 6}, {"whetstone"}, "drop", "Weapons wear 10% slower per rank.", {path_name = "Endurance"})
N("field", "arms", 2, "Field Repair", 1, {10}, {"oil"}, "flask", "Clearing a floor restores 10% of the weapon's durability.")
N("grip", "arms", 2, "Tempered Grip", 1, {12}, {"field"}, "shield", "No weapon wear for the first 30 seconds of each floor.")
N("charm", "arms", 2, "Auto-Repair Charm", 1, {12}, {"grip"}, "flask", "Start with an Auto Repair Powder.")
N("unbreakable", "arms", 2, "Unbreakable Bond", 1, {3}, {"charm"}, "shield", "Each biome begins with an Auto Repair Powder: one break saved per biome.", K())
N("macho", "arms", 3, "Macho's Forge", 3, {4, 8, 12}, {"whetstone"}, "shield", "The starting weapon gets one random attachment per rank.", {path_name = "Craft"})
N("gem", "arms", 3, "Gem Pouch", 1, {8}, {"macho"}, "crystal", "Start with a random gem.")
N("socket", "arms", 3, "Socket Sense", 1, {12}, {"gem"}, "map", "Found weapons arrive with one more attachment.")
N("synth", "arms", 3, "Synth Mastery", 2, {15, 25}, {"socket"}, "crystal", "Absorbing a weapon takes 35% of its stats; rank 2, 45%.")
N("master", "arms", 3, "Master's Gift", 1, {4}, {"synth"}, "sword", "Start with your character's second weapon.", K())
N("vault", "arms", 4, "Heirloom Vault", 1, {10}, {"gem", "lens"}, "crystal",
  "Each Warden gives a charge: bank half your weapon's stats for every new run's weapon.", {pos = {300, 30}})

-- Allies
N("embassy", "allies", 0, "Matataki Embassy", 1, {12}, {}, "heart", "A second ally is drafted when the run starts.")
N("golden", "allies", 1, "Golden Atla's Call", 1, {8}, {"embassy"}, "heart", "A Golden Atla also drafts an ally in biomes 2 and 4.", {path_name = "Draft"})
N("spoils", "allies", 1, "Shared Spoils", 2, {4, 8}, {"golden"}, "heart", "Benched allies take 25% more of each kill's ABS per rank.")
N("rally", "allies", 1, "Rally", 1, {10}, {"spoils"}, "heart", "Switching characters heals the new one 10%.")
N("fullparty", "allies", 1, "Full Party", 1, {3}, {"rally"}, "heart", "All six are drafted from the start; Moon Shards -10%.", K())
N("companion", "allies", 2, "Companion", 1, {25}, {"embassy"}, "heart",
  "With the Companion setting on, a drafted ally fights beside you: can't be hurt, its weapon's base damage. Switch to trade places.",
  {path_name = "Companion"})
N("stances", "allies", 2, "Stances", 1, {8}, {"companion"}, "heart", "Actions > Companion Stance: lock-on target, aggressive or passive.")
N("keenpartner", "allies", 2, "Keen Partner", 1, {12}, {"stances"}, "sword", "Companion damage +25%.")
N("twinstrike", "allies", 2, "Twin Strike", 1, {15}, {"keenpartner"}, "sword", "Hitting what the companion hits: +10% damage.")
N("soulbond", "allies", 2, "Soul Bond", 1, {3}, {"twinstrike"}, "heart", "Each of the companion's kills restores 3% of your HP.", K())
N("benchrest", "allies", 3, "Bench Rest", 1, {6}, {"embassy"}, "flask", "Benched allies regain 5% HP on each floor cleared.", {path_name = "Bench"})
N("swift", "allies", 3, "Swift Swap", 1, {10}, {"benchrest"}, "drop", "No wait between switches.", {})
N("relay", "allies", 3, "Relay", 1, {2}, {"benchrest", "swift"}, "shield", "Each switch gives the new character 3 seconds of invincibility.", K())
-- Opar's star (docs/OPAR_PLAN.md section 6): rises the first time a run beats the Moon Sea Warden (meta.opar_met);
-- bought, he is in every run's party, as the Opar setting puts him there.
N("oparstar", "allies", 4, "Opar of the Moon Sea", 1, {30}, {"embassy"}, "heart",
  "Opar, the frog mage met in the Moon Sea, joins every run's party.", {path_name = "Opar", reveal = "opar_met"})

-- Fortune
N("shrine", "fortune", 0, "Dran's Shrine", 3, {5, 10, 15}, {}, "crystal", "+10% weapon ABS per rank.")
N("lens", "fortune", 1, "Shard Lens", 3, {6, 12, 18}, {"shrine"}, "crystal", "+10% Moon Shards per rank.", {path_name = "Shards"})
N("cachesense", "fortune", 1, "Cache Sense", 1, {8}, {"lens"}, HUD_CACHE_IMAGE, "Miracle caches hold a third treasure.")
N("luckyfind", "fortune", 1, "Lucky Find", 1, {15}, {"cachesense"}, "crystal", "5% of kills drop a Moon Shard.")
N("tithe", "fortune", 1, "Moon Tithe", 1, {3}, {"luckyfind"}, "crystal", "Wardens pay double Moon Shards.", K())
N("moon", "fortune", 2, "Moon Blessing", 1, {15}, {"shrine"}, "crystal", "Every run starts with a random blessing.", {path_name = "Blessings"})
N("choice", "fortune", 2, "Blessed Choice", 1, {15}, {"moon"}, "crystal", "Choose the starting blessing from three.", {})
N("second", "fortune", 2, "Second Blessing", 1, {20}, {"moon", "choice"}, "crystal", "A second blessing at the start.")
N("chosen", "fortune", 2, "Chosen of the Moon", 1, {4}, {"second"}, "crystal", "Every blessing counts twice.", K({}))
N("purse", "fortune", 3, "Coin Purse", 1, {5}, {"shrine"}, "map", "Start with 300 Gilda.", {path_name = "Gilda"})
N("carts", "fortune", 3, "Carts Count", 1, {10}, {"purse"}, "map", "Carts pay 40% each instead of 20%.")
N("floorspay", "fortune", 3, "Gilda Floors", 1, {12}, {"carts"}, "map", "Floors pay 60 Gilda per depth instead of 40.")
N("hoard", "fortune", 3, "Treasure Hoard", 1, {3}, {"floorspay"}, HUD_CACHE_IMAGE, "Chests are worth 50% more.", K())

-- Diorama
N("well", "diorama", 0, "Deep Well", 3, {5, 9, 13}, {}, "map", "+1 Diorama plot per rank.")
N("houses", "diorama", 1, "Sturdy Houses", 1, {8}, {"well"}, "shield", "Houses cut damage taken by 9% each instead of 6%.", {path_name = "Hearth"})
N("trees", "diorama", 1, "Old Trees", 1, {10}, {"houses"}, "heart", "Trees heal twice as often.")
N("living", "diorama", 1, "Living Norune", 1, {3}, {"trees"}, "map", "Start each run with two random tiles placed.", K())
N("mills", "diorama", 2, "Mill Rights", 1, {10}, {"well"}, "crystal", "Windmill pairs give 35% ABS instead of 25%.", {path_name = "Industry"})
N("smiths", "diorama", 2, "Smithy Guild", 1, {10}, {"mills"}, "shield", "Smithies cut wear by 18% each instead of 12%.")
N("industrious", "diorama", 2, "Industrious", 1, {2}, {"smiths"}, "map", "Every sixth tile earned comes with a free extra.", K())
N("lampoil", "diorama", 3, "Lamp Oil", 1, {8}, {"well"}, "crystal", "One Lamp maps the floor and shows monsters.", {path_name = "Light"})
N("plots", "diorama", 3, "Moonlit Plots", 1, {12}, {"lampoil"}, "map", "+2 Diorama plots.")
N("beacon", "diorama", 3, "Beacon", 1, {2}, {"plots"}, "crystal", "Lamps add 8% damage each instead of 4%.", K())

-- Spirit
N("heart", "spirit", 0, "Steady Heart", 3, {4, 8, 12}, {}, "heart", "+10 maximum HP per rank.")
N("thick", "spirit", 1, "Thick Skin", 2, {8, 14}, {"heart"}, "shield", "-5% damage taken per rank.", {path_name = "Guard"})
N("secondwind", "spirit", 1, "Second Wind", 1, {20}, {"thick"}, "heart", "Once a floor, a fatal hit leaves 1 HP.", {})
N("laststand", "spirit", 1, "Last Stand", 1, {3}, {"thick", "secondwind"}, "sword", "Below 25% HP you deal double damage.", K())
N("lightstep", "spirit", 2, "Light Step", 1, {8}, {"heart"}, "drop", "Run 8% faster.", {path_name = "Speed"})
N("gauge", "spirit", 2, "Quick Gauge", 1, {12}, {"lightstep"}, "sword", "The attack gauge refills 20% faster.")
N("moonwalker", "spirit", 2, "Moonwalker", 1, {4}, {"gauge"}, "drop", "L2: a quick dodge the way you face, with a moment of invincibility.", K())
N("antidote", "spirit", 3, "Antidote Kit", 1, {4}, {"heart"}, "flask", "Start with two Antidotes.", {path_name = "Ailments"})
N("hardy", "spirit", 3, "Hardy", 1, {10}, {"antidote"}, "shield", "Freeze and Stamina wear off twice as fast.", {})
N("clearmind", "spirit", 3, "Clear Mind", 1, {2}, {"hardy"}, "crystal", "Immune to Freeze and Stamina.", K({}))

-- Provisions
N("kit", "provisions", 0, "Repair Kit", 2, {2, 4}, {}, "flask", "+1 Repair Powder in the starter kit per rank.")
N("waterskin", "provisions", 1, "Full Waterskin", 2, {3, 6}, {"kit"}, "drop", "Water drains 10% slower per rank.", {path_name = "Water"})
N("spring", "provisions", 1, "Spring Sense", 1, {10}, {"waterskin"}, "drop", "Start each run with a River tile in stock.")
N("rain", "provisions", 1, "Moon Rain", 1, {12}, {"spring"}, "drop", "Clearing a floor refills a quarter of your water.")
N("endless", "provisions", 1, "Endless Spring", 1, {2}, {"rain"}, "drop", "Water drains half as fast.", K())
N("baker", "provisions", 2, "Baker's Bundle", 1, {3}, {"kit"}, "flask", "+2 Bread in the starter kit.", {path_name = "Food"})
N("hearty", "provisions", 2, "Hearty Bread", 1, {8}, {"baker"}, "heart", "Clearing a floor gives a Bread (up to five a run).")
N("helping", "provisions", 2, "Second Helping", 1, {10}, {"hearty"}, "heart", "+2 Bread on each biome's first floor.")
N("feast", "provisions", 2, "Feast", 1, {2}, {"helping"}, "heart", "Each floor starts with a 20% heal.", K())
N("gaffer", "provisions", 3, "Gaffer's Wagon", 2, {6, 10}, {"kit"}, "map",
  "Gaffer brings one more ware. Rank 2: a third cheaper.", {path_name = "Merchant"})
N("haggler", "provisions", 3, "Haggler", 1, {8}, {"gaffer"}, "map", "Gaffer is 20% cheaper.")
N("stock", "provisions", 3, "Gaffer's Stock", 1, {15}, {"haggler"}, "crystal", "Gaffer also sells attachments.")
N("partner", "provisions", 3, "Gaffer's Partner", 1, {3}, {"stock"}, "map", "Gaffer is waiting on every floor from the start, not only once it's swept.", K())

-- The Dark Genie's Pacts (Heat)
N("crowded", "pacts", 0, "Crowded Halls", 2, {3, 6}, {}, "stamina", "+25% monsters on every floor per rank.", {heat = 1})
N("hardened", "pacts", 1, "Hardened Hide", 3, {4, 8, 12}, {"crowded"}, "poison", "Enemies +25% HP per rank.", {heat = 1, path_name = "Beasts"})
N("claws", "pacts", 1, "Sharp Claws", 2, {5, 10}, {"hardened"}, "curse", "Enemies hit 20% harder per rank.", {heat = 1})
N("deeper", "pacts", 1, "Deeper Dark", 1, {15}, {"claws"}, "goo", "Enemies are as strong as five floors deeper.", {heat = 3})
N("champions", "pacts", 1, "Genie's Champions", 1, {2}, {"deeper"}, "freeze", "Every floor's key holder is a lesser Warden.", K({heat = 3, pact = true}))
N("sprawl", "pacts", 2, "Sprawling Floors", 2, {5, 10}, {"crowded"}, "map", "Floors have 30% more rooms per rank.", {heat = 1, path_name = "Labyrinth"})
N("blind", "pacts", 2, "Blind Halls", 1, {8}, {"sprawl"}, "map", "No floor map.", {heat = 1})
N("twinkeys", "pacts", 2, "Twin Keys", 1, {12}, {"sprawl", "blind"}, "map", "Two monsters carry the gate key on floors I to III; the gate needs both.", {heat = 2})
N("maze", "pacts", 2, "Endless Maze", 1, {2}, {"twinkeys"}, "map", "Every biome has a fourth floor before its Warden.", K({heat = 3, pact = true}))
N("parched", "pacts", 3, "Parched Road", 1, {6}, {"crowded"}, "drop", "Water drains twice as fast.", {heat = 1, path_name = "Scarcity"})
N("brittle", "pacts", 3, "Brittle Steel", 1, {6}, {"parched"}, "shield", "Weapons wear 50% faster.", {heat = 2})
N("lean", "pacts", 3, "Lean Start", 1, {4}, {"brittle"}, "flask", "No starter kit.", {heat = 1})
N("barren", "pacts", 3, "Barren", 1, {2}, {"lean"}, "curse", "No chests on floors I to III.", K({heat = 3, pact = true}))
N("twinwardens", "pacts", 4, "Twin Wardens", 2, {8, 16}, {"crowded"}, "goo", "Warden floors hold two Wardens; rank 2, three.", {heat = 2, path_name = "Wardens"})
N("rage", "pacts", 4, "Warden's Rage", 1, {12}, {"crowded", "twinwardens"}, "curse", "On Warden floors enemies hit 50% harder.", {heat = 2})
N("mark", "pacts", 4, "The Genie's Mark", 1, {10}, {"rage"}, "curse", "Every third floor is cursed, chosen or not.", {heat = 2})
N("court", "pacts", 4, "Warden's Court", 1, {3}, {"mark"}, "goo", "The last Warden floor holds five Wardens at once.", K({heat = 4, pact = true}))

-- Signature skies (Character Marks): one per character, a fork after the second node.
local SIGNATURES = {
-- A third field `true` marks a node still waiting on engine work.
  toan = {{"Dagger Dance", "Toan's swings recover 15% faster."}, {"Lightning Fang", "Toan's charged attacks stun for a second."},
          {"Swordsman", "+1 attachment slot on Toan's weapons."}, {"Wanderer", "Toan runs 8% faster."},
          {"Atlamillia's Chosen", "Runs with Toan start with Atla Sight: every floor mapped, monsters shown."}},
  xiao = {{"Quick Draw", "Xiao's action gauge refills 50% faster."}, {"Pebble Storm", "Xiao's slingshot fires two pebbles."},
          {"Sniper", "Xiao deals 20% more damage."}, {"Tumbler", "Xiao gets the L2 dodge, as a tumbling hop."}, {"Cat's Nine Lives", "Once each biome, a fatal hit leaves Xiao on 1 HP."}},
  goro = {{"Iron Grip", "Goro takes half the recoil from hits."}, {"Ground Pound", "Goro's charged swings shake the room: half their damage to enemies nearby."},
          {"Bulwark", "Goro takes 15% less damage."}, {"Berserker", "Goro deals 15% more damage."},
          {"Mountain's Might", "Goro's charged swings stagger Wardens for a second and a half."}},
  ruby = {{"Flame Rings", "Ruby deals 10% more damage."}, {"Orb Split", "Ruby's orbs fly out in pairs."},
          {"Pyromancer", "Ruby deals 20% more damage."}, {"Moonsinger", "Ruby's hits heal her 1 HP, once a second."},
          {"Genie's Daughter", "Ruby's orbs fly on through enemies."}},
  ungaga = {{"Spear Reach", "Ungaga's spear reaches 20% further."}, {"Totem Guard", "Every 15 seconds a totem's ward turns aside one hit on Ungaga."},
            {"Warrior", "Ungaga deals 15% more damage."}, {"Shaman", "Ungaga regains 3% HP every 5 seconds."},
            {"Spirit of the Woods", "With Ungaga drafted, everyone takes 10% less damage."}},
  osmond = {{"Steady Aim", "10% of Osmond's hits deal double."}, {"Rocket Boost", "Osmond gets the L2 dodge, as a jetpack dash twice as far."},
            {"Gunner", "Osmond deals 20% more damage."}, {"Scholar", "Osmond's weapon gains 20% more ABS."},
            {"Moon People's Gift", "Runs with Osmond start with an extra blessing."}},
  opar = {{"Big Mouth", "Opar's Gob fires five globs."}, {"Bog Hop", "Opar's Frog Hop leaves a puddle that slows enemies."},
          {"Spitter", "Opar deals 20% more damage."}, {"Old Toad", "Opar's Jump Slam heals him a quarter of his HP."},
          {"King of the Moon Sea", "Opar's Jump Slam is back in 30 seconds, its slam 50% wider."}},
}
for _, c in ipairs(SIGNATURE_CHARS) do
  local sig = SIGNATURES[c]
  local g = "sig_" .. c
  N(c .. "_1", g, 0, sig[1][1], 1, {1}, {}, "sword", sig[1][2], {cur = "mark", char = c, soon = sig[1][3] == true, pos = {0, 110}})
  N(c .. "_2", g, 0, sig[2][1], 1, {2}, {c .. "_1"}, "sword", sig[2][2], {cur = "mark", char = c, soon = sig[2][3] == true, pos = {0, 50}})
  N(c .. "_3", g, 0, sig[3][1], 1, {3}, {c .. "_2"}, "sword", sig[3][2], {cur = "mark", char = c, soon = sig[3][3] == true, pos = {-120, -10}})
  N(c .. "_4", g, 0, sig[4][1], 1, {3}, {c .. "_2"}, "drop", sig[4][2], {cur = "mark", char = c, soon = sig[4][3] == true, pos = {120, -10}})
  N(c .. "_5", g, 0, sig[5][1], 1, {6}, {c .. "_3", c .. "_4"}, "crystal", sig[5][2],
    {cur = "mark", char = c, soon = sig[5][3] == true, key = true, signature_key = true, pos = {0, -80}})
end

local ETERNAL_NODE = {}
for _, n in ipairs(ETERNAL) do ETERNAL_NODE[n.id] = n end

-- Layout: constellations on a ring around Norune Eternal, Signature skies on an outer ring; each path fans out from
-- its trunk at the bottom of the view to its Keystone at the top.
do
  local paths = {}
  for _, n in ipairs(ETERNAL) do
    paths[n.group] = paths[n.group] or {}
    if n.path > 0 and not n.pos then
      paths[n.group][n.path] = paths[n.group][n.path] or {}
      table.insert(paths[n.group][n.path], n)
    end
  end
  local SPREAD = {[1] = {0}, [2] = {-170, 170}, [3] = {-230, 0, 230}, [4] = {-255, -85, 85, 255}}
  for _, g in ipairs(SKY_GROUPS) do
    local radius = g.signature and 1500 or 820
    local a = g.angle and math.rad(g.angle) or nil
    g.x = a and math.floor(math.cos(a) * radius * 1.25) or 0
    g.y = a and math.floor(math.sin(a) * radius) or 0
    g.texts = {}
    local gp = paths[g.id] or {}
    local count = 0
    for p in pairs(gp) do count = math.max(count, p) end
    for p = 1, count do
      local list = gp[p] or {}
      local x_end = (SPREAD[count] or SPREAD[3])[p] or 0
      for k, n in ipairs(list) do
        local f = #list > 1 and (k - 1) / (#list - 1) or 1
        local base = count >= 4 and 0.75 or 0.42 -- four paths start wider apart, so the first row of labels fits
        n.pos = {math.floor(x_end * (base + (1 - base) * f)), 62 - (k - 1) * 40}
      end
      local last = list[#list]
      if last and list[1].path_name then
        g.texts[#g.texts + 1] = {text = list[1].path_name:upper(), x = last.pos[1], y = last.pos[2] - 36}
      end
    end
  end
  for _, n in ipairs(ETERNAL) do
    local g = SKY_GROUP[n.group]
    n.pos = n.pos or {0, n.group == "norune" and 0 or 108}
    n.x, n.y = g.x + n.pos[1], g.y + n.pos[2]
  end
end

-- Skill tree: the Diorama (placed tiles, per run) ------------------------------------------------------------
do
  local nodes = {}
  for _, t in ipairs(TILES) do nodes[#nodes + 1] = {id = t.id, title = t.title, description = t.description, max_rank = 9} end
  local ok, err = call(game.skills.register, {id = "diorama", title = "DIORAMA", description = "Georama tiles placed for this run.", skills = nodes})
  if not ok then moonmod.log("warn", "diorama tree: " .. errmsg(err)) end
end
local function node_id(tree, node) return ID .. ":" .. tree .. "." .. node end

-- Gauntlet floors ---------------------------------------------------------------------------------------
local run -- the run in progress (loaded from storage further down)
-- The roster: the run's own while one is in progress, else the Opar setting's.
function ROSTER.sync() ROSTER.set(run and run.opar == true or (not run and ROSTER.wanted())) end
-- Each biome has five floors: I, II, III, IV and the Warden, after a Rest floor between biomes (registered first,
-- so its exit gate leads on to floor I in the same dungeon). A run without Endless Maze skips IV (its gate on
-- floor III is redirected to the Warden) and counts the Warden as slot 4. A sixth, the Genie's Lair, is the run's
-- finale after the last biome's Warden (the genie_finale setting): a Warden floor of its own, in that biome's dungeon.
-- ROUTE[biome index] = {floors = {{id, native}, x5}, lair = {id, native}, rest = {id, native}};
-- FLOOR_AT["dungeon:native floor"] = {biome, floor 0-6} (0 the Rest floor).
local ROUTE, FLOOR_AT = {}, {}
local function adopt_floors(index, record)
  local floors = {}
  for n, f in ipairs(type(record) == "table" and record.floors or {}) do
    if type(f) == "table" and type(f.id) == "string" and type(f.native_floor_id) == "number" and n <= 7 then
      floors[n - 1] = {id = f.id, native = f.native_floor_id}
    end
  end
  if not (floors[0] and #floors >= 5) then return false end
  ROUTE[index] = {floors = {table.unpack(floors, 1, 5)}, lair = floors[6], rest = floors[0]}
  for n = 0, #floors do FLOOR_AT[BIOMES[index].dungeon .. ":" .. floors[n].native] = {biome = index, floor = n} end
  return true
end
for index, biome in ipairs(BIOMES) do
  local local_id = "gauntlet-" .. biome.key
  local definition = {id = local_id, name = "Moon Gauntlet: " .. biome.name, dungeon = biome.dungeon, floors = {
    {id = "rest", name = biome.name .. " Rest", source_floor = biome.sources[1], enemies = {}},
    {id = "i", name = biome.name .. " I", source_floor = biome.sources[1]},
    {id = "ii", name = biome.name .. " II", source_floor = biome.sources[2]},
    {id = "iii", name = biome.name .. " III", source_floor = biome.sources[3]},
    {id = "iv", name = biome.name .. " IV", source_floor = biome.sources[4]},
    {id = "warden", name = biome.name .. " Warden", source_floor = biome.warden},
    {id = "lair", name = "Genie's Lair", source_floor = biome.warden},
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
-- The run's floors by slot: all five with Endless Maze, else I, II, III and the Warden.
local function route(index)
  local r = ROUTE[index]
  if not r or (run and run.maze) then return r end
  return {floors = {r.floors[1], r.floors[2], r.floors[3], r.floors[5]}, lair = r.lair, rest = r.rest}
end
-- A native floor's place in the run: {biome, slot}, or nil for floor IV in a run that skips it. The Lair counts as
-- a Warden floor ({slot = the Warden's, lair = true}); the Rest floor is slot 0 ({slot = 0, rest = true}).
local function floor_at(dungeon_id, floor_id)
  local h = FLOOR_AT[tostring(dungeon_id) .. ":" .. tostring(floor_id)]
  if not h then return nil end
  if h.floor == 0 then return {biome = h.biome, slot = 0, rest = true} end
  if h.floor == 6 then return {biome = h.biome, slot = (run and run.maze) and 5 or 4, lair = true} end
  if run and run.maze then return {biome = h.biome, slot = h.floor} end
  if h.floor == 4 then return nil end
  return {biome = h.biome, slot = h.floor == 5 and 4 or h.floor}
end
-- Floor III's gate leads past floor IV unless the run has Endless Maze.
local function set_redirects(maze)
  for index, r in pairs(ROUTE) do
    try(game.dungeons.floor_redirect, {dungeon_id = BIOMES[index].dungeon, floor_id = r.floors[4].native,
                                       to_floor_id = (maze == false) and r.floors[5].native or nil})
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
  m.eternal = type(m.eternal) == "table" and m.eternal or {} -- ranks owned
  m.sigils = math.floor(tonumber(m.sigils) or 0)
  m.marks = type(m.marks) == "table" and m.marks or {}           -- character -> Character Marks
  m.off = type(m.off) == "table" and m.off or {}                 -- node -> true while switched off
  m.set = type(m.set) == "table" and m.set or {}                 -- node -> the rank in use, when below the rank owned
  m.best_heat = math.floor(tonumber(m.best_heat) or 0)
  m.loadouts = type(m.loadouts) == "table" and m.loadouts or {}
  m.stance = (m.stance == "aggressive" or m.stance == "passive") and m.stance or "target" -- the companion's, kept between runs
  m.start_char = type(m.start_char) == "string" and m.start_char or "toan"
  if type(m.heirloom) ~= "table" then m.heirloom = nil end
  return m
end
local meta = load_meta()
local function save_meta() moonmod.storage.set("meta", meta) end
local function owned(id) return math.floor(tonumber(meta.eternal[id]) or 0) end
-- The rank of an unlock in use this run: what is owned, unless switched off or set lower.
local function eternal(id)
  local r = owned(id)
  if r == 0 or meta.off[id] then return 0 end
  local set = tonumber(meta.set[id])
  return set and math.max(1, math.min(r, math.floor(set))) or r
end
-- Opar in the roster: the Opar setting, or his star bought (oparstar). A hidden node or sky (`reveal`) is shown once
-- meta[reveal] is set, or with the Opar setting on.
function ROSTER.wanted() return setting("opar", false) or eternal("oparstar") > 0 end
local function revealed(key) return key == nil or meta[key] == true or setting("opar", false) end
local function heat()
  local h = 0
  for _, n in ipairs(ETERNAL) do if n.heat then h = h + n.heat * eternal(n.id) end end
  return h
end
local function keystone_slots() return 2 + eternal("third_star") end
local function counts_as_keystone(n) return n.key and not n.pact and not n.signature_key end
local function keystones_on(except)
  local k = 0
  for _, n in ipairs(ETERNAL) do if counts_as_keystone(n) and n.id ~= except and eternal(n.id) > 0 then k = k + 1 end end
  return k
end

-- A run lives only inside its sandbox session. One still in storage at start-up was cut short when the
-- game closed; it is closed below as a retreat once the helpers exist.
run = moonmod.storage.get("run")
WARDEN_SLOT = (type(run) == "table" and run.maze) and 5 or 4
if type(run) ~= "table" or run.active ~= true then run = nil end
local function save_run() moonmod.storage.set("run", run or false) end

-- Per-floor state (not saved) --------------------------------------------------------------------------
local frame = 0
local floor = nil          -- {token, biome, slot, back, cursed, curses, scaled, warden, warden_max, seen, swept, entered, atla}
local pending_transition = nil   -- {id, at, tries, why}
local effects_on = false
local hud_text = nil
local hud_native = nil       -- the engine draws the floor label and HUD icons (false: fall back to a text line)
local offer = nil          -- a pick of three blessings: {ids, pick, shown, more}
local choice = nil         -- a weapon choice: {character, keep, take, pick = 1 keep | 2 take, shown}

local function on_route() return run and run.phase == "active" and floor ~= nil and not run.suspended end
local function biome_def(pos) return run and BIOMES[run.biomes[pos]] end
-- Shuffled floors: run.plan[pos][slot] is the dungeon (a BIOMES index) that floor is in. The Warden floor is always
-- in the biome's own dungeon; a run without a plan (an older save) keeps every floor there.
local function planned(pos, slot)
  local row = run and run.plan and run.plan[pos]
  if slot < WARDEN_SLOT and row and row[slot] then return row[slot] end
  return run and run.biomes[pos]
end
local function total_floors() return run and (#run.biomes * WARDEN_SLOT + (run.finale and 1 or 0)) or 0 end

-- Effects ------------------------------------------------------------------------------------------------
local function placed(id) return run and math.floor(tonumber(run.diorama[id]) or 0) or 0 end
local function blessed(id) return run and contains(run.blessings, id) end
-- How strongly a blessing counts: 0 not held, 1 held, 2 with Chosen of the Moon.
local function bp(id) return blessed(id) and (eternal("chosen") > 0 and 2 or 1) or 0 end
-- A Signature node at work: owned, switched on, and its character in this run's draft.
local function sig(c, n) return run ~= nil and eternal(c .. "_" .. n) > 0 and contains(run.drafted, c) end
-- The companion fights beside you only with its Eternal unlock and the Companion setting (off by default).
local function companion_on() return eternal("companion") > 0 and setting("companion", false) end
local CHAR_NO = {toan = 0, xiao = 1, goro = 2, ruby = 3, ungaga = 4, osmond = 5, opar = 6}
local function cursed(id) return floor and floor.cursed and contains(floor.curses, id) end
local function plots() return BASE_PLOTS + eternal("well") + (eternal("plots") > 0 and 2 or 0) end
local function placed_total() local n = 0; for _, id in ipairs(TILE_IDS) do n = n + placed(id) end; return n end
local function stock_total() local n = 0; for _, id in ipairs(TILE_IDS) do n = n + math.floor(tonumber(run and run.stock[id]) or 0) end; return n end

-- Enemy-side scale of a late biome rolled early by Biome Shuffle.
local function shuffle_scale()
  if not (run and floor) then return 1 end
  local native = floor.dungeon or run.biomes[floor.biome]
  if native == floor.biome then return 1 end
  -- a late dungeon met early is eased; an early one met late is toughened
  if native > floor.biome then return math.max(0.35, floor.biome / native) end
  return math.min(3, 1 + 0.45 * (floor.biome - native))
end

local function abs_multiplier()
  local pairs_built = math.min(placed("windmill"), placed("storehouse"))
  local m = setting("abs_rate", 6) * (1 + (eternal("mills") > 0 and 0.35 or 0.25) * pairs_built) * (1 + 0.1 * eternal("shrine"))
  m = m * (1 + 0.25 * bp("scholar"))
  local p = try(game.player.get)
  if p and p.character == "osmond" and sig("osmond", 4) then m = m * 1.2 end -- Scholar
  if floor and floor.cursed then m = m * 1.5 end
  if floor and floor.back then m = m * 1.5 end
  return m
end

-- Weapon wear: Smithy tiles, Tempered Steel and the Brittle curse.
local function wear_scale()
  -- Tempered Grip: no wear for the first 30 seconds of a floor
  if eternal("grip") > 0 and floor and frame - (floor.entered or 0) < 1800 then return 0 end
  return clamp(((eternal("smiths") > 0 and 0.82 or 0.88) ^ placed("smithy")) * (0.9 ^ eternal("oil")) * (0.75 ^ bp("tempered")) *
      (cursed("brittle") and 2 or 1) * (eternal("brittle") > 0 and 1.5 or 1), 0.25, 4)
end

local function apply_effects()
  local active = on_route()
  if not active then
    if effects_on then
      try(game.player.tuning_clear)
      try(game.combat.register_formula, {id = "gauntlet_out", operation = "multiply", value = 1, priority = 120})
      try(game.combat.register_formula, {id = "gauntlet_lucky", operation = "chance_multiply", value = 2, chance = 0, priority = 121})
      try(game.combat.register_player_formula, {id = "gauntlet_in", operation = "multiply", value = 1, priority = 120})
      for c, n in pairs(CHAR_NO) do
        try(game.combat.register_formula, {id = "gauntlet_sig_" .. c, operation = "multiply", value = 1, priority = 122, character_id = n})
      end
      try(game.combat.register_player_formula, {id = "gauntlet_sig_bulwark", operation = "multiply", value = 1, priority = 122, character_id = CHAR_NO.goro})
      try(game.combat.register_formula, {id = "gauntlet_sig_aim", operation = "chance_multiply", value = 2, chance = 0, priority = 123, character_id = CHAR_NO.osmond})
      try(game.combat.register_formula, {id = "gauntlet_charged", operation = "multiply", value = 1, priority = 124, charged = true})
      effects_on = false
    end
    return
  end
  local out = (1 + (eternal("beacon") > 0 and 0.08 or 0.04) * placed("lamp")) * (1 + 0.15 * bp("moonlit")) *
      (1 + 0.05 * eternal("keen"))
  local p = try(game.player.get)
  if eternal("laststand") > 0 and p and (p.max_hp or 0) > 0 and (p.hp or 0) * 4 < p.max_hp then out = out * 2 end
  local incoming = ((eternal("houses") > 0 and 0.91 or 0.94) ^ placed("house")) * (0.85 ^ bp("ward")) * (sig("ungaga", 5) and 0.9 or 1) * (cursed("glass") and 1.5 or 1) *
      (0.95 ^ eternal("thick")) * (1.2 ^ eternal("claws")) * ((eternal("rage") > 0 and floor and floor.slot == WARDEN_SLOT) and 1.5 or 1) *
      ((floor and floor.back) and 1.6 or 1)
  local shuffle = shuffle_scale()
  if shuffle < 1 then incoming = incoming * math.max(0.5, shuffle) end
  try(game.combat.register_formula, {id = "gauntlet_out", operation = "multiply", value = clamp(out, 0, 100), priority = 120})
  try(game.combat.register_formula, {id = "gauntlet_lucky", operation = "chance_multiply", value = 2, chance = 10 * bp("lucky") + 5 * eternal("moonstrike"), priority = 121})
  try(game.combat.register_player_formula, {id = "gauntlet_in", operation = "multiply", value = clamp(incoming, 0, 100), priority = 120})
  local who = p and p.character
  local toan_up = who == "toan"
  local sig_out = {toan = 1, xiao = sig("xiao", 3) and 1.2 or 1, goro = sig("goro", 4) and 1.15 or 1,
                   ruby = (sig("ruby", 1) and 1.1 or 1) * (sig("ruby", 3) and 1.2 or 1), ungaga = sig("ungaga", 3) and 1.15 or 1,
                   osmond = sig("osmond", 3) and 1.2 or 1, opar = sig("opar", 3) and 1.2 or 1}
  for c, v in pairs(sig_out) do
    try(game.combat.register_formula, {id = "gauntlet_sig_" .. c, operation = "multiply", value = v, priority = 122, character_id = CHAR_NO[c]})
  end
  try(game.combat.register_player_formula, {id = "gauntlet_sig_bulwark", operation = "multiply", value = sig("goro", 3) and 0.85 or 1,
      priority = 122, character_id = CHAR_NO.goro})
  try(game.combat.register_formula, {id = "gauntlet_sig_aim", operation = "chance_multiply", value = 2,
      chance = sig("osmond", 1) and 10 or 0, priority = 123, character_id = CHAR_NO.osmond})
  try(game.combat.register_formula, {id = "gauntlet_charged", operation = "multiply", value = eternal("charged") > 0 and 1.3 or 1,
      priority = 124, charged = true})
  local tuning = {
    thirst_drain = clamp((0.88 ^ placed("river")) * (0.75 ^ bp("flask")) * (cursed("parched") and 3 or 1) *
        (0.9 ^ eternal("waterskin")) * (eternal("endless") > 0 and 0.5 or 1) * (eternal("parched") > 0 and 2 or 1) *
        (who == "opar" and 0.7 or 1), 0.25, 4), -- Opar, a frog, thirsts 30% slower
    durability_wear = wear_scale(),
    run_speed = (1 + 0.15 * bp("stride")) * (eternal("lightstep") > 0 and 1.08 or 1) * ((toan_up and sig("toan", 4)) and 1.08 or 1),
    attack_anim_speed = (toan_up and sig("toan", 1)) and 1.15 or 1,
    recoil_scale = (who == "goro" and sig("goro", 1)) and 0.5 or 1,
    gauge_refill = (eternal("gauge") > 0 and 1.2 or 1) * ((who == "xiao" and sig("xiao", 1)) and 1.5 or 1),
    extra_shots = ((who == "xiao" and sig("xiao", 2)) or (who == "ruby" and sig("ruby", 2))) and 1 or 0,
    shots_pierce = who == "ruby" and sig("ruby", 5),
    reach_scale = (who == "ungaga" and sig("ungaga", 1)) and 1.2 or 1,
    map_hidden = eternal("blind") > 0,
    status_duration = eternal("hardy") > 0 and 0.5 or 1,
    status_immune = eternal("clearmind") > 0 and {"freeze", "stamina"} or nil,
    swap_delay = eternal("swift") > 0 and 0 or 1,
    -- Moonwalker's dodge; Tumbler and Rocket Boost give Xiao and Osmond their own
    dodge_power = (who == "osmond" and sig("osmond", 2)) and 2 or ((eternal("moonwalker") > 0 or (who == "xiao" and sig("xiao", 4))) and 1 or 0),
    dodge_invincible_frames = 20,
    dodge_hop = who == "xiao" and sig("xiao", 4),
    invincible_bonus_frames = 12 * bp("breath"),
    map_reveal = placed("lamp") >= 1 or blessed("atla"),
    monster_reveal = placed("lamp") >= 2 or (eternal("lampoil") > 0 and placed("lamp") >= 1) or blessed("atla"),
    -- R2's first-person view has no use in a run; it only got in the way of the fight.
    first_person = false,
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
  if not setting("journal_page", false) then try(game.ui.sheet_clear); return end
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
      progress_label = ("Depth " .. run.depth .. " / " .. total_floors()), trees = {"diorama"}})
end

-- The HUD in the game's own art: the floor plate reads "2-3" (a Warden floor keeps the native "Boss") and the floor
-- card the run's depth ("B6"), a cursed
-- floor shows a small Curse badge and the chest its Miracle cache pays, and a curse waiting for the next floor
-- blinks. A Vault needs nothing: the native plate turns purple on a back floor. An engine without these draws a
-- text line instead.
local function hud_state()
  if not (run and run.phase == "active" and floor) or run.suspended then return nil end
  -- Digits: the game font's capital I reads as a lower-case l.
  local s = {label = floor.rest and "Rest" or (run.slot < WARDEN_SLOT and (run.pos .. "-" .. run.slot) or nil), icons = {}}
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
  return string.format("GAUNTLET %d-%s%s%s", run.pos, floor.rest and "REST" or FLOOR_LABEL[run.slot] or "?",
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
  local text = not choice and not offer and hud_line() or nil -- a choice needs the room
  if text == hud_text then return end
  hud_text = text
  if text then try(game.render.layer_register, {id = "gauntlet", text = text})
  else try(game.render.layer_remove, {id = "gauntlet"}) end
end

-- The run menu: Start during a run opens it in place of the pause (ui.run_menu_set). Its rows act through
-- ui.run_menu_action (handled with the Diorama and curse code further down).
local update_menu
do
local STANCE_TEXT = {target = "Attacks what you lock on to.", aggressive = "Attacks anything near you.", passive = "Holds back and follows."}
local menu_key = nil -- what was last sent, so an unchanged menu isn't sent again
local function menu_tabs()
  local b = (floor and BIOMES[floor.dungeon or 0]) or biome_def(run.pos)
  local run_rows = {}
  local can_curse = on_route() and run.slot ~= WARDEN_SLOT - 1 and run.slot > 0 and run.cursed_biome ~= run.pos
  run_rows[#run_rows + 1] = {id = "curse", label = "Curse the next floor", value = run.next_cursed and "On" or "Off",
      tone = run.next_cursed and "bad" or nil, enabled = can_curse,
      detail = "A cursed floor brings curses on you and more, richer chests, and a Miracle cache if you survive it. The Warden's floor can't be cursed."}
  if eternal("stances") > 0 and companion_on() then
    local stance = meta.stance or "target"
    run_rows[#run_rows + 1] = {id = "stance", label = "Companion stance", value = title(stance),
        detail = STANCE_TEXT[stance] .. " Cross changes it: lock-on target, aggressive, passive."}
  end
  run_rows[#run_rows + 1] = {id = "abandon", label = "Abandon the run", tone = "bad",
      detail = "Ends the run here. You keep the Moon Shards earned so far."}
  local curses = floor and floor.cursed and names_of(floor.curses, CURSES) or nil
  local lines = {
    floor and floor.lair and "The Genie's Lair" or
        string.format("%s %s", b and b.name or "?", floor and floor.rest and "Rest" or (run.slot < WARDEN_SLOT and (run.pos .. "-" .. run.slot) or "Warden")),
    string.format("Depth %d of %d", run.depth, total_floors()),
    "Next gate: " .. ((run.next_cursed or run.cursed_biome == run.pos) and "CURSED" or "normal"),
  }
  if run.cursed_biome == run.pos then lines[#lines + 1] = "On the Cursed Path: every floor here is cursed" end
  if curses then lines[#lines + 1] = ("Curses here: " .. curses):sub(1, 96) end
  lines[#lines + 1] = string.format("Moon Shards %d (+%d this run)", meta.shards, run.shards)

  local free = plots() - placed_total()
  local tile_rows = {}
  for _, id in ipairs(TILE_IDS) do
    local stock = math.floor(tonumber(run.stock[id]) or 0)
    tile_rows[#tile_rows + 1] = {id = id, label = TILE[id].title, value = string.format("%d placed, %d left", placed(id), stock),
        enabled = stock > 0 and free > 0, tone = stock > 0 and free > 0 and "good" or nil,
        detail = TILE[id].description .. (stock > 0 and (free > 0 and " Cross places one." or " The Diorama is full.") or " None in stock.")}
  end
  tile_rows[#tile_rows + 1] = {id = "clear", label = "Clear the Diorama", enabled = placed_total() > 0,
      detail = "Every placed tile goes back into stock, to place again as you like."}

  local blessing_rows = {}
  for _, id in ipairs(run.blessings) do
    blessing_rows[#blessing_rows + 1] = {id = id, label = BLESSINGS[id].name, detail = BLESSINGS[id].text:gsub("^%l", string.upper) .. "."}
  end

  local party_rows = {}
  for _, c in ipairs(run.drafted) do
    local role = c == run.leader and "Leading" or (c == run.companion and companion_on() and "Companion" or "Benched")
    party_rows[#party_rows + 1] = {id = c, label = title(c), value = role,
        detail = role == "Leading" and "The character you play." or (role == "Companion" and "Fights beside you. Switch to them and you trade places."
            or "Waits on the bench. Switch with Select.")}
  end
  local tabs = {
    {id = "run", title = "RUN", lines = lines, rows = run_rows},
    {id = "diorama", title = "DIORAMA", lines = {string.format("Plots used %d of %d", placed_total(), plots()),
        string.format("%d tiles in stock", stock_total()), "Atla, swept floors and caches give tiles."}, rows = tile_rows},
    {id = "blessings", title = "BLESSINGS", lines = {#run.blessings > 0 and string.format("%d held this run", #run.blessings)
        or "None yet. Wardens and Blessed Choice give them."}, rows = blessing_rows},
    {id = "party", title = "PARTY", lines = {string.format("%d drafted", #run.drafted)}, rows = party_rows},
  }
  if floor and floor.gaffer then
    local wares = {}
    for _, w in ipairs(floor.gaffer.wares) do
      wares[#wares + 1] = {id = w.id, label = w.label, value = w.price .. " G", detail = w.detail, enabled = not w.sold,
          tone = w.sold and "dim" or (w.staple and nil or "gold")}
    end
    table.insert(tabs, 1, {id = "gaffer", title = "GAFFER", rows = wares,
        lines = {"\"Step right up! Everything here is for this run only.\"", "Gilda comes from floors and enemies."}})
  end
  return tabs
end

local function menu_signature(tabs)
  local parts = {}
  for _, t in ipairs(tabs) do
    parts[#parts + 1] = t.id .. "|" .. table.concat(t.lines or {}, "/")
    for _, r in ipairs(t.rows or {}) do
      parts[#parts + 1] = table.concat({r.id, r.label, r.value or "", r.detail or "", r.tone or "", tostring(r.enabled ~= false)}, "|")
    end
  end
  return table.concat(parts, "\n")
end

update_menu = function()
  if not (run and run.phase == "active") or run.suspended then
    if menu_key then try(game.ui.run_menu_clear); menu_key = nil end
    return
  end
  local tabs = menu_tabs()
  for _, t in ipairs(tabs) do if #t.rows == 0 then t.rows = nil end end -- an empty table would reach the engine as an object
  local key = menu_signature(tabs)
  if key == menu_key then return end
  local ok, err = call(game.ui.run_menu_set, {title = "DARK GENIE'S GAUNTLET", tabs = tabs})
  if ok then menu_key = key else moonmod.log("warn", "run menu: " .. errmsg(err)) end
end
end

local function refresh()
  ROSTER.sync()
  apply_effects()
  update_sheet()
  update_hud()
  update_menu()
end

-- Diorama and rewards ------------------------------------------------------------------------------
local function push_diorama_ranks()
  for _, id in ipairs(TILE_IDS) do try(game.skills.set_rank, {id = node_id("diorama", id), rank = placed(id)}) end
end

local function give_tiles(n, why)
  if not run then return end
  local got = {}
  for _ = 1, n do
    local id = pick(TILE_IDS)
    run.stock[id] = (tonumber(run.stock[id]) or 0) + 1
    got[#got + 1] = TILE[id].title
    run.tiles_earned = (run.tiles_earned or 0) + 1
    if eternal("industrious") > 0 and run.tiles_earned % 6 == 0 then
      local extra = pick(TILE_IDS)
      run.stock[extra] = (tonumber(run.stock[extra]) or 0) + 1
      got[#got + 1] = TILE[extra].title
      n = n + 1
    end
  end
  toast((why and (why .. ": ") or "") .. "+" .. n .. " Diorama tile" .. (n > 1 and "s" or "") .. " (" .. table.concat(got, ", ") .. ").")
end

local function earn_shards(n)
  if not run or n <= 0 then return end
  run.shards = run.shards + n
end

local open_offer -- Blessed Choice's pick, defined with the weapon choice
local gaffer_arrive -- Gaffer pulls up on the floor, defined with his shop
local set_guards -- the floor's fatal-guard charges, defined beside the Warden code
local function bless(why, opts)
  if not run then return end
  opts = opts or {}
  local open = {}
  for _, id in ipairs(BLESSING_IDS) do if not contains(run.blessings, id) then open[#open + 1] = id end end
  if opts.id then
    if contains(run.blessings, opts.id) then return end
    open = {opts.id}
  elseif opts.start and eternal("choice") > 0 and #open > 1 then
    if offer then offer.more = (offer.more or 0) + 1; return end
    local three = {}
    while #three < 3 and #open > 0 do table.insert(three, table.remove(open, math.random(#open))) end
    open_offer(three)
    return
  end
  local id = pick(open)
  if not id then earn_shards(2); toast("Every blessing held: +2 Moon Shards."); return end
  run.blessings[#run.blessings + 1] = id
  toast("Blessing: " .. BLESSINGS[id].name .. ". " .. BLESSINGS[id].text:gsub("^%l", string.upper) .. ".")
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
  if eternal("cachesense") > 0 then
    local c = try(game.items.give, {id = "chronicle:item:" .. pick(ATTACHMENTS), count = 1})
    n = n + ((c and (c.added or 0) > 0) and 1 or 0)
  end
  toast("Miracle cache! " .. n .. " treasure" .. (n == 1 and "" or "s") .. " added to the bag." .. (n < 2 and " Is it full?" or ""), HUD_CACHE_IMAGE)
end

local MOVES = {}
-- Opar's Jump Slam (docs/OPAR_PLAN.md section 3): a charge held to the top and let go with a full gauge. He leaps,
-- and at the top of it a cloud of smoke: he is the giant Opar (the monster's own model, resources/opar/c07f.chr:
-- player.form_set), who slams down on everything round him and heaves himself back up; a puff of smoke and he is
-- himself again. The slam comes back a minute later. FORM.tick runs it a step at a time: the leap (his own move), the
-- change, the big slam (the monster's press, player.move_play), the change back.
local FORM = {kit = {}, active = false, ready_at = 0, COOLDOWN = 3600, PACK = "dun/mainchara/c07f.chr", SCALE = 0.5,
              FRAMES = {weapon = "r_hand", item = "l_hand", tukene1 = "karada", jnt2_1 = "karada", jnt12_1 = "shita"}}

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
    if type(def) == "table" and def.owner == (ROSTER.fights_as[character] or character) then
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

-- Loot: rarity, touches and legendaries ----------------------------------------------------------------------
-- A found weapon rolls a rarity (Common, Uncommon, Rare, Epic, Legendary): its stats grow by the tier's multiplier,
-- its name shows in the tier's colour in the weapon menu and its swing trail glows in it. Rare and better carry
-- touches, mechanics that fire on hits and kills (Vampire, Poison, Goo, Frost, Thunder, Echo, ...); Epic and
-- Legendary get a generated name from them ("Dracula's Baselard"). Six fixed legendaries, one per character, carry a
-- signature; finding one unlocks it as a starting weapon on the title screen.
local LOOT = {}
do
  local function rgb(r, g, b) return {r = r, g = g, b = b} end
  local TIERS = {
    {key = "common", name = "Common", mult = 1.0, color = rgb(235, 235, 235), touches = 0},
    {key = "uncommon", name = "Uncommon", mult = 1.15, color = rgb(120, 230, 120), glow = rgb(70, 210, 70), touches = 0},
    {key = "rare", name = "Rare", mult = 1.3, color = rgb(110, 170, 255), glow = rgb(70, 130, 255), touches = 1},
    {key = "epic", name = "Epic", mult = 1.5, color = rgb(205, 125, 255), glow = rgb(175, 70, 255), touches = 2},
    {key = "legendary", name = "Legendary", mult = 1.8, color = rgb(255, 170, 60), glow = rgb(255, 150, 30), touches = 2},
  }
  LOOT.TIERS = TIERS
  -- adj: a Rare's word; own: an Epic's owner; of: an Epic's ending; roots: a Legendary's own name is made of two.
  local TOUCHES = {
    vampire = {name = "Vampire Touch", text = "Heals you 8% of the damage it deals.", adj = "Vampiric", own = "Dracula's",
               of = "of the Hungry Night", roots = {"Blood", "Night", "Crimson"}, ends = {"fang", "thirst", "kiss"}},
    poison = {name = "Poison Touch", text = "A third of hits poison: 3% of max HP a second for 5 s.", adj = "Venomous", own = "Viper's",
              of = "of Slow Rot", roots = {"Venom", "Blight", "Rot"}, ends = {"sting", "bite", "kiss"}},
    goo = {name = "Goo Touch", text = "Hits gum enemies up, slowing them.", adj = "Gooey", own = "the Slime King's",
           of = "of Clinging Muck", roots = {"Muck", "Ooze", "Mire"}, ends = {"grip", "drip", "maw"}},
    frost = {name = "Frost Touch", text = "Hits may freeze enemies solid for a moment.", adj = "Frozen", own = "the Ice Queen's",
             of = "of the Long Winter", roots = {"Frost", "Rime", "Winter"}, ends = {"bite", "song", "heart"}},
    thunder = {name = "Thunder Chain", text = "A quarter of hits arc to the nearest other enemy for half damage.", adj = "Stormcalled",
               own = "Raijin's", of = "of the Seventh Storm", roots = {"Storm", "Thunder", "Volt"}, ends = {"call", "crack", "fury"}},
    echo = {name = "Echo", text = "A third of hits land again as a ghost a moment later.", adj = "Echoing", own = "the Phantom's",
            of = "of Twice-Told Blows", roots = {"Echo", "Ghost", "Shade"}, ends = {"song", "step", "call"}},
    ember = {name = "Ember Burst", text = "Kills explode, burning the enemies around.", adj = "Blazing", own = "the Salamander's",
             of = "of Ash", roots = {"Ember", "Ash", "Cinder"}, ends = {"heart", "brand", "fall"}},
    gravity = {name = "Gravity Well", text = "Charged hits drag nearby enemies to the one you struck.", adj = "Abyssal", own = "the Black Star's",
               of = "of the Undertow", roots = {"Void", "Abyss", "Star"}, ends = {"pull", "well", "maw"}},
    quake = {name = "Quake", text = "Charged hits throw the enemies around you back.", adj = "Quaking", own = "the Titan's",
             of = "of Broken Earth", roots = {"Quake", "Stone", "Titan"}, ends = {"fall", "break", "heart"}},
    reaper = {name = "Reaper", text = "Hits finish off enemies under 15% HP.", adj = "Grim", own = "the Reaper's",
              of = "of the Final Hour", roots = {"Grave", "Dusk", "Death"}, ends = {"knell", "reap", "end"}},
    gilded = {name = "Gilded", text = "Kills drop gilda.", adj = "Gilded", own = "Midas'", of = "of Fortune",
              roots = {"Gold", "Coin", "Sun"}, ends = {"gleam", "purse", "crown"}},
    thorns = {name = "Thorns", text = "Hits you take come back on the nearest enemy, harder.", adj = "Thorned", own = "the Briar Witch's",
              of = "of Bramble", roots = {"Thorn", "Briar", "Bramble"}, ends = {"guard", "spite", "kiss"}},
    frenzy = {name = "Frenzy", text = "Each kill adds 8% damage for 6 s (up to five).", adj = "Frenzied", own = "the Berserker's",
              of = "of Red Mist", roots = {"Rage", "Red", "Wild"}, ends = {"fury", "howl", "fang"}},
    -- the legendaries' signatures
    lunar = {name = "Lunar Arc", text = "Charged hits arc lightning to three more enemies.", signature = true},
    ricochet = {name = "Ricochet", text = "Every shot bounces on to two more enemies.", signature = true},
    earthsplit = {name = "Earthsplitter", text = "Charged hits explode on the target.", signature = true},
    phoenix = {name = "Phoenix", text = "Kills explode and heal you 4% of your HP.", signature = true},
    venomtotem = {name = "Venom Totem", text = "Every hit poisons; poisoned enemies under 25% HP die.", signature = true},
    starfall = {name = "Starfall", text = "Every fifth hit calls down an explosion.", signature = true},
    riptide = {name = "Riptide", text = "A glob that hits splits into three that seek new targets.", signature = true},
  }
  LOOT.TOUCHES = TOUCHES
  local POOL = {"vampire", "poison", "goo", "frost", "thunder", "echo", "ember", "gravity", "quake", "reaper", "gilded", "thorns", "frenzy"}
  -- The fixed legendaries: base weapon, name, two touches and a signature.
  local LEGENDS = {
    toan = {key = "moonfang", name = "Moonfang", item = 266, touches = {"thunder", "echo", "lunar"}},
    xiao = {key = "ninefold", name = "Ninefold", item = 304, touches = {"vampire", "frost", "ricochet"}},
    goro = {key = "titanfall", name = "Titanfall", item = 322, touches = {"quake", "gravity", "earthsplit"}},
    ruby = {key = "emberheart", name = "Emberheart", item = 337, touches = {"ember", "thunder", "phoenix"}},
    ungaga = {key = "gaiasting", name = "Gaia's Sting", item = 352, touches = {"poison", "reaper", "venomtotem"}},
    osmond = {key = "starfall", name = "Starfall", item = 365, touches = {"echo", "gilded", "starfall"}},
  }
  LOOT.LEGENDS = LEGENDS
  -- Opar's staffs (docs/OPAR_PLAN.md section 4): his weapons, registered at load on Toan's sixth weapon (their models,
  -- art/opar/make_staffs.py, hold its c01w05.cfg), each with its own model, icon and attack, and one thing of its own.
  -- He starts with the Driftwood Staff; whatever weapon comes to him becomes the staff of the dungeon it came in
  -- (LOOT.roll); Tidecaller is his legendary, with the signature Riptide.
  local STAFFS = {
    {key = "driftwood", name = "Driftwood Staff", stem = "opst01", attack = 8, durability = 40, own = "A staff to start with.",
     about = "A bleached hook of driftwood off the shore."},
    {key = "reed", name = "Reed Staff", stem = "opst02", attack = 18, durability = 45, own = "Globs fly 20% faster.",
     about = "Marsh reeds bound tight, fronds at the top."},
    {key = "coral", name = "Coral Staff", stem = "opst03", attack = 28, durability = 50, own = "Globs go through to one more foe.",
     about = "A crown of branching coral on a sea-worn stem."},
    {key = "bogoak", name = "Bog Oak Staff", stem = "opst04", attack = 38, durability = 60, own = "The Bubble's splash is 40% wider.",
     about = "Black bog oak twisted round a mossy root knot."},
    {key = "moonpearl", name = "Moonpearl Staff", stem = "opst05", attack = 50, durability = 65, own = "The Jump Slam is back 20 s sooner.",
     about = "A silver claw holding a pearl of the Moon Sea."},
    {key = "tidecaller", name = "Tidecaller", stem = "opst06", attack = 56, durability = 70,
     own = "Riptide: a glob that hits splits into three.", about = "The tide's own staff, its rune disc aglow."},
  }
  LOOT.STAFFS = STAFFS
  LEGENDS.opar = {key = "tidecaller", name = "Tidecaller", staff = 6, touches = {"frost", "echo", "riptide"}}
  -- The staff a dungeon gives (by its native number): Wise Owl Forest's Reed, the Shipwreck's Coral, the Sun and
  -- Moon Temple's Bog Oak, the Moon Sea's Moonpearl and on; the first cave another Driftwood.
  local DUNGEON_STAFF = {[0] = 1, 2, 3, 4, 5, 5, 5}
  function LOOT.staff_of(id)
    for _, st in ipairs(STAFFS) do if st.id and st.id == id then return st end end
  end
  function LOOT.opar_staff()
    local w = equipped_weapon("opar")
    return w and LOOT.staff_of(w.id)
  end
  -- A weapon traded for staff n: the staff given, the weapon taken away. Returns the staff's id and slot.
  function LOOT.to_staff(c, id, slot, n)
    local st = STAFFS[n]
    if not (st and st.id) then return id, slot end
    local given = call(game.weapons.give, {id = st.id, character = c})
    if not (given and given.slot) then return id, slot end
    try(game.weapons.remove, {id = id, character = c, slot = slot})
    return st.id, given.slot
  end
  local QUALITY = {"Fine", "Keen", "Honed", "Sturdy", "Polished", "Tempered"}

  local function wid(item) return "chronicle:weapon:" .. item end
  function LOOT.legend_id(legend) return legend.staff and STAFFS[legend.staff].id or wid(legend.item) end
  local function key(c, slot, id) return c .. ":" .. tostring(slot) .. ":" .. tostring(id) end
  local function base_name(id)
    local w = try(game.weapons.get, id)
    return type(w) == "table" and type(w.name) == "string" and w.name ~= "" and w.name or "Weapon"
  end
  -- Names stay short enough for the weapon menu's name plates.
  local NAME_CAP = 22
  LOOT.NAME_CAP = NAME_CAP
  local function fits(s) return #s <= NAME_CAP end
  -- The first of the candidates that fits; the shortest when none does.
  local function first_fit(...)
    local shortest
    for _, s in ipairs({...}) do
      if fits(s) then return s end
      if not shortest or #s < #shortest then shortest = s end
    end
    return shortest
  end

  -- The name a rolled weapon goes by.
  local function make_name(tier, base, touches)
    local t1, t2, t3 = TOUCHES[touches[1] or ""], TOUCHES[touches[2] or ""], TOUCHES[touches[3] or ""]
    if tier == 2 then return first_fit(pick(QUALITY) .. " " .. base, "Fine " .. base, base) end
    if tier == 3 and t1 then return first_fit(t1.adj .. " " .. base, base) end
    if tier == 4 and t1 then
      local long = t2 and (t1.adj .. " " .. base .. " " .. t2.of)
      if long and fits(long) and math.random(2) == 1 then return long end
      return first_fit(t1.own .. " " .. base, t1.adj .. " " .. base, base)
    end
    if tier == 5 and t1 then
      local a, b = t1, t2 or t1
      local proper = pick(a.roots) .. pick(b.ends)
      return first_fit(proper .. ", " .. (t3 or a).own .. " " .. base, proper .. " " .. base, proper)
    end
    return base
  end

  -- The rarity a weapon rolls: deeper floors, Vaults and Wardens lean rarer; `least` is the lowest tier allowed.
  local function roll_tier(least)
    local forced = setting("loot_tier", 0) -- tests only: always this tier
    if forced >= 1 and forced <= 5 then return forced end
    local d = run and run.depth or 0
    local weights = {math.max(8, 52 - 2 * d), 28, 14 + d, 5 + 0.6 * d, 1 + 0.25 * d}
    if floor and floor.back then least = math.max(least or 1, 2) end
    local total = 0
    for t = least or 1, 5 do total = total + weights[t] end
    local r = math.random() * total
    for t = least or 1, 5 do
      r = r - weights[t]
      if r <= 0 then return t end
    end
    return 5
  end

  local function draw_touches(n)
    local bag, out = {}, {}
    for _, id in ipairs(POOL) do bag[#bag + 1] = id end
    for _ = 1, n do
      if #bag == 0 then break end
      out[#out + 1] = table.remove(bag, math.random(#bag))
    end
    return out
  end

  function LOOT.record(c, slot, id) return run and run.loot and run.loot[key(c, slot, id)] end

  -- What each touch does, short enough for the weapon menu's card.
  local SHORT = {
    vampire = "heals 8% of damage dealt", poison = "1 in 3 hits poisons", goo = "hits slow enemies",
    frost = "hits may freeze", thunder = "1 in 4 hits arc to another", echo = "1 in 3 hits strike again",
    ember = "kills explode in flame", gravity = "charged hits pull foes in", quake = "charged hits throw foes back",
    reaper = "finishes foes under 15% HP", gilded = "kills drop gilda", thorns = "returns the hits you take",
    frenzy = "kills stack +8% damage", lunar = "charged hits chain to 3 foes", ricochet = "shots bounce to 2 more foes",
    earthsplit = "charged hits explode", phoenix = "kills explode and heal you", venomtotem = "poisons; kills under 25%",
    starfall = "every 5th hit calls a star", riptide = "a glob that hits splits to 3 foes",
  }
  LOOT.SHORT = SHORT
  local TOUCH_RGB, SIGNATURE_RGB = rgb(240, 215, 150), rgb(255, 225, 120)

  -- Shows a rolled weapon's name, colour and glow in the game, and its card in the weapon menu: the tier and its
  -- multiplier on the left, what each touch does on the right.
  function LOOT.style(c, slot, id)
    local r = LOOT.record(c, slot, id)
    if not r then return end
    local tier = TIERS[r.tier]
    local badge = {{text = tier.name:upper(), color = tier.color, scale = 1.15},
                   {text = string.format("Stats x%.2f", tier.mult):gsub("0$", ""), color = rgb(200, 195, 185), scale = 0.75}}
    local details = {}
    for _, t in ipairs(r.touches or {}) do
      local d = TOUCHES[t]
      if d then
        details[#details + 1] = {text = (d.signature and "* " or "") .. d.name .. ": " .. (SHORT[t] or d.text),
                                 color = d.signature and SIGNATURE_RGB or TOUCH_RGB}
      end
    end
    local staff = LOOT.staff_of(id)
    if staff and staff.own and staff.key ~= "tidecaller" then table.insert(details, 1, {text = staff.own, color = rgb(150, 220, 230)}) end
    if #details == 0 then details[1] = {text = "No touches. Stronger than its plain kind.", color = rgb(200, 195, 185)} end
    try(game.weapons.style_set, {character = c, slot = slot, name = r.name, color = tier.color, glow = tier.glow,
                                 badge = badge, details = details})
  end
  function LOOT.restyle()
    for k in pairs(run and run.loot or {}) do
      local c, slot, id = k:match("^([^:]+):(%d+):(.+)$")
      if c then LOOT.style(c, tonumber(slot), id) end
    end
  end
  function LOOT.forget(c, slot, id)
    if run and run.loot then run.loot[key(c, slot, id)] = nil end
    try(game.weapons.style_clear, {character = c, slot = slot})
  end

  -- Grows the weapon's stats by the tier and keeps its record.
  local function apply(c, slot, id, tier, touches, name, legend)
    local w = weapon_info(id, c, slot)
    if w then
      local mult = TIERS[tier].mult
      local request = {id = id, character = c, slot = slot}
      for _, k in ipairs({"attack", "endurance", "speed", "magic"}) do
        request[k] = math.floor(clamp((tonumber(w.stats[k]) or 0) * mult + 0.5, 0, 32767))
      end
      try(game.weapons.stats_set, request)
    end
    run.loot = run.loot or {}
    run.loot[key(c, slot, id)] = {tier = tier, touches = touches, name = name, legend = legend}
    LOOT.style(c, slot, id)
  end

  -- A found weapon rolls its rarity. A Legendary may be the character's own fixed legendary: the found weapon is
  -- traded for it, and finding it unlocks it as a starting weapon. Returns the weapon's (possibly new) id and slot.
  function LOOT.roll(c, id, slot, least)
    if c == "opar" and not LOOT.staff_of(id) then
      id, slot = LOOT.to_staff(c, id, slot, DUNGEON_STAFF[floor and floor.dungeon or 0] or 1)
    end
    if not setting("loot_rarity", true) then LOOT.force_tier = nil; return id, slot end
    local tier = LOOT.force_tier or roll_tier(least)
    LOOT.force_tier = nil
    local legend = LEGENDS[c]
    if tier == 5 and legend and math.random(100) <= 35 then
      local given = call(game.weapons.give, {id = LOOT.legend_id(legend), character = c})
      if given and given.slot then
        try(game.weapons.remove, {id = id, character = c, slot = slot})
        id, slot = LOOT.legend_id(legend), given.slot
        apply(c, slot, id, 5, legend.touches, legend.name, legend.key)
        meta.legends = meta.legends or {}
        if not meta.legends[legend.key] then
          meta.legends[legend.key] = true
          save_meta()
          toast(legend.name .. " found! It can now be " .. title(c) .. "'s starting weapon.")
        end
        return id, slot
      end
    end
    local touches = draw_touches(TIERS[tier].touches + (tier == 5 and 1 or 0))
    apply(c, slot, id, tier, touches, (make_name(tier, base_name(id), touches):gsub("^%l", string.upper)))
    return id, slot
  end

  -- Opar in the party holds a staff: his first weapon traded for the Driftwood Staff, equipped, named.
  function LOOT.staff_start(c, w)
    local st = STAFFS[1]
    if c ~= "opar" or not w or LOOT.staff_of(w.id) or not st.id then return w end
    local given = call(game.weapons.give, {id = st.id, character = c})
    if not (given and given.slot and call(game.weapons.equip, {id = st.id, character = c, slot = given.slot})) then return w end
    try(game.weapons.remove, {id = w.id, character = c, slot = w.slot})
    apply(c, given.slot, st.id, 1, {}, st.name)
    return {id = st.id, slot = given.slot}
  end

  -- A run that starts with an unlocked legendary: the character's weapon is traded for it.
  function LOOT.start_weapon(c, w)
    local legend = LEGENDS[c]
    if not (legend and meta.start_legend and meta.start_legend[c] == legend.key and meta.legends and meta.legends[legend.key]) then return w end
    local given = call(game.weapons.give, {id = LOOT.legend_id(legend), character = c})
    if not (given and given.slot and call(game.weapons.equip, {id = LOOT.legend_id(legend), character = c, slot = given.slot})) then return w end
    try(game.weapons.remove, {id = w.id, character = c, slot = w.slot})
    local nw = {id = LOOT.legend_id(legend), slot = given.slot}
    apply(c, nw.slot, nw.id, 5, legend.touches, legend.name, legend.key)
    return nw
  end

  -- The title screen's starting weapon: the character's own, or its legendary once found.
  function LOOT.start_label(c)
    local legend = LEGENDS[c]
    if legend and meta.start_legend and meta.start_legend[c] == legend.key and meta.legends and meta.legends[legend.key] then return legend.name end
    if legend and not (meta.legends and meta.legends[legend.key]) then return "Standard (find " .. legend.name .. " to unlock)" end
    return "Standard"
  end
  function LOOT.cycle_start(c)
    local legend = LEGENDS[c]
    if not (legend and meta.legends and meta.legends[legend.key]) then return end
    meta.start_legend = meta.start_legend or {}
    meta.start_legend[c] = meta.start_legend[c] ~= legend.key and legend.key or nil
  end

  -- A felled Warden leaves a weapon, Rare or better, for one of the drafted characters.
  local RANGES = {toan = {258, 272}, xiao = {300, 311}, goro = {315, 325}, ruby = {332, 340}, ungaga = {348, 357}, osmond = {364, 368},
                  opar = {258, 272}}
  function LOOT.warden_drop()
    if not (run and LOOT.found) then return end
    local c = pick(run.drafted)
    local range = RANGES[c or ""]
    if not range then return end
    local given = call(game.weapons.give, {id = wid(math.random(range[1], range[2])), character = c})
    if not (given and given.slot) then return end
    LOOT.force_tier = roll_tier(3)
    toast("The Warden leaves a weapon behind for " .. title(c) .. ".")
    LOOT.found(c, given.id or wid(given.native_item_no), given.slot)
  end

  -- What the weapon card shows of a weapon's rarity: its title, a tier tag and the touches.
  function LOOT.card(c, w, card)
    local r = LOOT.record(c, w.slot, w.id)
    if not r then return card end
    card.title = r.name or card.title
    card.subtitle = TIERS[r.tier].name .. "  |  " .. card.subtitle
    for _, t in ipairs(r.touches or {}) do
      local d = TOUCHES[t]
      if d then card.lines[#card.lines + 1] = {text = d.name .. ": " .. d.text, tone = "gold"} end
    end
    return card
  end

  -- Touches in play ------------------------------------------------------------------------------------------------
  local dots, echoes, last_pos, frenzy = {}, {}, {}, {stacks = 0, until_ = 0}
  local hits = 0
  local function touches_of(p)
    local w = p and p.weapon
    local r = w and w.id and LOOT.record(p.character, w.slot, w.id)
    local set = {}
    for _, t in ipairs(r and r.touches or {}) do set[t] = true end
    return set
  end
  local function position_of(entity)
    local m = try(game.entities.get, entity)
    if m and m.position then last_pos[tostring(entity)] = m.position end
    return m
  end
  local function others(center, radius, except)
    local near = try(game.physics.query, {shape = "sphere", center = {x = center.x, y = center.y, z = center.z}, radius = radius})
    local out = {}
    for _, m in ipairs(near and near.matches or {}) do
      if tostring(m.entity) ~= tostring(except) then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return (a.distance or 0) < (b.distance or 0) end)
    return out
  end
  local function burst(kind, at, scale) if at then try(game.effects.burst, {kind = kind, position = {x = at.x, y = (at.y or 0) + 8, z = at.z}, scale = scale}) end end
  local function poison(entity, m, frames)
    local max = m and m.health and tonumber(m.health.maximum) or 40
    dots[tostring(entity)] = {entity = entity, until_ = frame + frames, next = frame + 60, amount = math.max(1, math.floor(max * 0.03))}
    try(game.entities.tint, {entity = entity, color = rgb(90, 255, 90), frames = frames})
  end
  local function chain(at, except, count, amount)
    local struck = 0
    for _, o in ipairs(others(at, 150, except)) do
      if struck >= count then break end
      if try(game.combat.damage, {entity = o.entity, amount = amount}) then
        struck = struck + 1
        burst("sparks", (position_of(o.entity) or {}).position, 0.8)
      end
    end
  end
  local function explode(at, except, amount)
    burst("explosion", at, 0.8)
    for _, o in ipairs(others(at, 100, except)) do try(game.combat.damage, {entity = o.entity, amount = amount}) end
  end

  -- Opar's globs (MOVES): a Bubble bursts on what it hits and splashes those round it (wider from the Bog Oak
  -- Staff); the Coral Staff's globs go through to one more foe; Tidecaller's split into three (Riptide, below).
  local SPITS = {opar_spit = true, opar_gob = true, opar_bubble = true, opar_back_hop = true, opar_leap_strike = true}
  function FORM.spat() return FORM.kit.move and SPITS[FORM.kit.move] and frame - (FORM.kit.since or 0) <= 90 end
  local function glob_hit(e, staff, damage)
    local m = position_of(e.entity)
    local at = m and m.position
    if not at then return end
    if FORM.kit.move == "opar_bubble" and not FORM.kit.splashed then
      FORM.kit.splashed = true
      local radius = (staff and staff.key == "bogoak") and 84 or 60
      for _, o in ipairs(others(at, radius, e.entity)) do try(game.combat.damage, {entity = o.entity, amount = math.max(1, math.floor(damage * 0.5))}) end
      burst("heal", at, radius / 30)
    end
    if staff and staff.key == "coral" then chain(at, e.entity, 1, math.max(1, math.floor(damage * 0.7))) end
  end

  -- A hit by the active character's weapon.
  function LOOT.on_hit(e)
    local damage = tonumber(e.damage) or 0
    if damage <= 0 or not e.entity then return end
    local p = try(game.player.get)
    if p and p.character == "opar" and FORM.spat() then glob_hit(e, p.weapon and LOOT.staff_of(p.weapon.id), damage) end
    local set = touches_of(p)
    if next(set) == nil then return end
    hits = hits + 1
    local m = position_of(e.entity)
    local at = m and m.position
    local hp, max = m and m.health and tonumber(m.health.current) or 0, m and m.health and tonumber(m.health.maximum) or 1
    if set.vampire and p then
      try(game.player.heal, {amount = math.max(1, math.floor(damage * 0.08))})
      if hits % 4 == 0 then burst("heal", p.position, 1) end
    end
    if set.frenzy and frenzy.stacks > 0 and frame < frenzy.until_ then
      try(game.combat.damage, {entity = e.entity, amount = math.max(1, math.floor(damage * 0.08 * frenzy.stacks))})
    end
    if (set.poison and math.random(3) == 1) or set.venomtotem then poison(e.entity, m, 300) end
    if set.goo then
      try(game.combat.status_add, {entity = e.entity, status = "slow", duration_frames = 150})
      try(game.entities.tint, {entity = e.entity, color = rgb(190, 100, 255), frames = 150})
    end
    if set.frost and math.random(100) <= 15 then
      try(game.combat.status_add, {entity = e.entity, status = "stop", duration_frames = 75})
      try(game.entities.tint, {entity = e.entity, color = rgb(160, 225, 255), frames = 75})
      burst("guard", at, 1)
    end
    if at and set.thunder and math.random(4) == 1 then chain(at, e.entity, 1, math.max(1, math.floor(damage * 0.5))) end
    if at and set.ricochet then chain(at, e.entity, 2, math.max(1, math.floor(damage * 0.35))) end
    if at and set.riptide and FORM.spat() then chain(at, e.entity, 3, math.max(1, math.floor(damage * 0.5))) end
    if at and set.lunar and e.charged then chain(at, e.entity, 3, math.max(1, math.floor(damage * 0.6))) end
    if set.echo and math.random(3) == 1 then echoes[#echoes + 1] = {at = frame + 30, entity = e.entity, amount = math.max(1, math.floor(damage * 0.6))} end
    if at and set.gravity and e.charged then
      for _, o in ipairs(others(at, 170, e.entity)) do
        local om = try(game.entities.get, o.entity)
        local op = om and om.position
        if op then try(game.entities.knockback, {entity = o.entity, direction = {x = at.x - op.x, z = at.z - op.z}, speed = 9}) end
      end
      burst("guard", at, 1.4)
    end
    if set.quake and e.charged and p and p.position then
      for _, o in ipairs(others(p.position, 130, nil)) do
        local om = try(game.entities.get, o.entity)
        local op = om and om.position
        if op then try(game.entities.knockback, {entity = o.entity, direction = {x = op.x - p.position.x, z = op.z - p.position.z}, speed = 12}) end
      end
      burst("sparks", p.position, 1.5)
    end
    if at and set.earthsplit and e.charged then explode(at, nil, math.max(1, math.floor(damage * 1.2))) end
    if at and set.starfall and hits % 5 == 0 then explode(at, nil, math.max(1, math.floor(damage * 2))) end
    -- finishers last, on what is left after the hit
    if hp > 0 and ((set.reaper and hp < max * 0.15) or (set.venomtotem and dots[tostring(e.entity)] and hp < max * 0.25)) then
      try(game.combat.damage, {entity = e.entity, amount = hp})
      burst("guard", at, 1)
    end
  end

  -- A kill by anyone while the active weapon has kill touches.
  function LOOT.on_kill(e)
    if not e.entity then return end
    local id = tostring(e.entity)
    dots[id] = nil
    local at = last_pos[id]
    last_pos[id] = nil
    local p = try(game.player.get)
    local set = touches_of(p)
    if set.frenzy then frenzy.stacks, frenzy.until_ = math.min(5, (frame < frenzy.until_ and frenzy.stacks or 0) + 1), frame + 360 end
    if set.gilded then try(game.economy.add, {amount = math.random(5, 15) * math.max(1, run.pos or 1)}) end
    if at and (set.ember or set.phoenix) then
      local w = p and p.weapon
      explode(at, e.entity, math.max(4, math.floor((tonumber(w and w.attack) or 20) * 1.5)))
    end
    if set.phoenix and p and p.max_hp then try(game.player.heal, {amount = math.max(1, math.floor(p.max_hp * 0.04))}) end
  end

  -- Each tick: poison and echoes land, and Thorns answers the hits taken.
  function LOOT.tick(p)
    for id, d in pairs(dots) do
      if frame >= d.until_ then dots[id] = nil
      elseif frame >= d.next then
        d.next = frame + 60
        if not try(game.combat.damage, {entity = d.entity, amount = d.amount}) then dots[id] = nil end
      end
    end
    for i = #echoes, 1, -1 do
      local q = echoes[i]
      if frame >= q.at then
        table.remove(echoes, i)
        local m = position_of(q.entity)
        if try(game.combat.damage, {entity = q.entity, amount = q.amount}) then burst("sparks", m and m.position, 1.2) end
      end
    end
    if p and p.hp then
      local was = LOOT.hp_seen
      LOOT.hp_seen = p.hp
      if was and p.hp < was and p.character == LOOT.hp_who and touches_of(p).thorns and p.position then
        local o = others(p.position, 130, nil)[1]
        if o then try(game.combat.damage, {entity = o.entity, amount = math.floor((was - p.hp) * 1.5) + 2}) end
      end
      LOOT.hp_who = p.character
    end
  end

  -- A new floor: the touches' timers start over, and the styles are shown again.
  function LOOT.floor()
    dots, echoes, last_pos = {}, {}, {}
    LOOT.restyle()
  end
  function LOOT.reset()
    dots, echoes, last_pos, frenzy = {}, {}, {}, {stacks = 0, until_ = 0}
    try(game.weapons.style_clear, {})
  end
end

-- New moves (player.moves_set) ------------------------------------------------------------------------------------
-- Toan's own animations (resources/anims, authored with tools/anim): the Dash Slash (attack out of a run: a low
-- lunging thrust, untouchable), the Spinning Sweep (a charge held past the jump slash and let go: arms flung wide,
-- two full turns, then a slam) and the Counter Slash (attack while guarding: a rising cut out of a crouch). The
-- sweep's hits count as charged, so Gravity Well, Quake and Lunar Arc work with it. If the animations can't be
-- registered, the moves fall back to Toan's native swings.
do
  local ANIMS = {"toan_dash_thrust", "toan_whirlwind", "toan_rising_slash", "toan_roll", "toan_backstep",
                 "toan_heavy_chop", "toan_launcher", "toan_spin_finisher", "toan_back_slash", "toan_roll_slash",
                 "xiao_triple_shot", "xiao_tumble", "xiao_hop_shot", "xiao_heavy_shot", "xiao_volley"}
  -- Goro, Ungaga, Ruby and Osmond: one recipe per kind of fighter (tools/anim/party_moves.py).
  local MELEE_ANIMS = {"dash", "counter", "roll", "backstep", "heavy", "launcher", "spin_finisher", "back_slash", "roll_slash"}
  local CASTER_ANIMS = {"rush", "tumble", "hop_shot", "heavy_cast", "volley"}
  for _, who in ipairs({"goro", "ungaga"}) do
    for _, a in ipairs(MELEE_ANIMS) do ANIMS[#ANIMS + 1] = who .. "_" .. a end
  end
  for _, who in ipairs({"ruby", "osmond"}) do
    for _, a in ipairs(CASTER_ANIMS) do ANIMS[#ANIMS + 1] = who .. "_" .. a end
  end
  local animated
  local function register()
    if animated ~= nil then return animated end
    animated = true
    for _, id in ipairs(ANIMS) do
      if not try(game.animations.player_register, {id = id, file = "resources/anims/" .. id .. ".json"}) then animated = false end
    end
    return animated
  end
  local function with(move, anim, native)
    local m = {}
    for k, v in pairs(move) do m[k] = v end
    if animated then m.animation = anim else m.motion = native end
    return m
  end
  local DASH = {id = "dash_slash", character = "toan", trigger = "run_attack", run_frames = 20, speed = 1.0,
    lunge = 3.4, lunge_decay = 0.2, invincible = true, cooldown = 30,
    hits = {{at = 0.36, radius = 10, reach = 9, damage = 1.4, knockback = 3}, {at = 0.5, radius = 10, reach = 11, damage = 1.0, knockback = 2}},
    cues = {{at = 0.15, sound = "voice_2"}, {at = 0.3, sound = "swing", trail = "wide"}}}
  local SWEEP = {id = "spin_sweep", character = "toan", trigger = "charge_release", min_charge = 0.9, max_charge = 1.5,
    speed = 0.9, spin = 2, spin_from = 0.22, spin_to = 0.62,
    hits = {{at = 0.28, radius = 16, reach = 0, damage = 0.8, charged = true}, {at = 0.38, radius = 16, reach = 0, damage = 0.8, charged = true},
            {at = 0.48, radius = 16, reach = 0, damage = 0.8, charged = true}, {at = 0.58, radius = 16, reach = 0, damage = 0.8, charged = true},
            {at = 0.77, radius = 14, reach = 6, damage = 1.8, knockback = 5, heavy = true, charged = true, burst = "sparks", burst_scale = 2}},
    cues = {{at = 0, sound = "shout"}, {at = 0.25, sound = "swing", trail = "heavy"}, {at = 0.45, sound = "swing_heavy", trail = "heavy"},
            {at = 0.7, sound = "shout_2", trail = "slam"}}}
  local COUNTER = {id = "counter_slash", character = "toan", trigger = "guard_attack", speed = 1.0, invincible = true, cooldown = 20,
    hits = {{at = 0.34, radius = 10, reach = 7, height = 8, damage = 1.8, knockback = 4, heavy = true},
            {at = 0.46, radius = 10, reach = 5, height = 12, damage = 1.0, knockback = 2}},
    cues = {{at = 0.1, sound = "voice"}, {at = 0.3, sound = "swing_heavy", trail = "wide"}}}
  -- L2: a roll the way the stick points, or with the stick at rest a hop back; he can't be hit during either.
  -- Either also cuts an attack short once its blow has landed (cancel_after steps later), a swing of the combo or one
  -- of the moves above. The Eternal tree's Moonwalker sends the roll further.
  -- The roll plays over about 0.8 seconds (its 24 frames at 0.5 a drawn frame) and carries him about 37 units (a lunge
  -- of p fading by d travels about p * p / (2 * d)); Moonwalker 51.
  local ROLL = {id = "evade_roll", character = "toan", trigger = "dodge", speed = 0.5, lunge = 2.7, lunge_decay = 0.1,
    invincible = true, cooldown = 18, wear = 0, cancel = true, cancel_after = 2, cues = {{at = 0, sound = "action"}}}
  local BACKSTEP = {id = "evade_backstep", character = "toan", trigger = "dodge_back", speed = 1.1, lunge = 2.4,
    lunge_decay = 0.2, lunge_angle = 180, invincible = true, cooldown = 14, wear = 0, cancel = true, cancel_after = 2,
    cues = {{at = 0, sound = "action"}}}
  -- Xiao (resources/anims/xiao_*, tools/anim/xiao_moves.py): attack out of a run skids into a Triple Shot (three
  -- shots fanned at once, a full gauge like her own shot); L2 tumbles the way the stick points (further with Moonwalker
  -- or her Tumbler signature) or, with the stick at rest, hops back loosing a shot. Either evade cuts her shot short
  -- once it's away.
  local TRIPLE = {id = "triple_shot", character = "xiao", trigger = "run_attack", run_frames = 20, speed = 1.0, gauge = 100,
    cooldown = 20, hits = {{at = 0.42, shot = true, count = 3, spread = 12, damage = 0.8}},
    cues = {{at = 0.1, sound = "voice"}}}
  local TUMBLE = {id = "evade_tumble", character = "xiao", trigger = "dodge", speed = 1.2, lunge = 2.4, lunge_decay = 0.11,
    invincible = true, cooldown = 16, wear = 0, cancel = true, cancel_after = 2, cues = {{at = 0, sound = "action"}}}
  local HOP_SHOT = {id = "evade_hop_shot", character = "xiao", trigger = "dodge_back", speed = 1.1, lunge = 2.2,
    lunge_decay = 0.2, lunge_angle = 180, invincible = true, cooldown = 18, wear = 0, cancel = true, cancel_after = 2,
    hits = {{at = 0.35, shot = true, damage = 0.7}}, cues = {{at = 0, sound = "action"}}}
  -- The combo set. A is the light attack (the native combo, unchanged); R2 the heavy attack; R2 partway through the
  -- combo a finisher (after two blows, or three, the longer chain winning); locked on, A with the stick toward the
  -- target lunges and away from it strikes while backing off; A late in an evade or just after it follows it up.
  local HEAVY_CHOP = {id = "heavy_chop", character = "toan", trigger = "heavy", speed = 0.9, lunge = 1.2, lunge_decay = 0.15,
    cooldown = 30, wear = 1.5,
    hits = {{at = 0.43, radius = 11, reach = 8, damage = 2.4, knockback = 5, heavy = true, burst = "impact", burst_scale = 1.5}},
    cues = {{at = 0.05, sound = "voice"}, {at = 0.36, sound = "swing_heavy", trail = "slam"}}}
  local LAUNCHER = {id = "launcher", character = "toan", trigger = "combo_finisher", chain = 2, speed = 1.1, lunge = 1.0,
    lunge_decay = 0.15, cooldown = 20,
    hits = {{at = 0.29, radius = 10, reach = 6, height = 8, damage = 1.6, knockback = 6, heavy = true},
            {at = 0.4, radius = 10, reach = 5, height = 14, damage = 0.8, knockback = 2}},
    cues = {{at = 0.1, sound = "voice_2"}, {at = 0.25, sound = "swing", trail = "wide"}}}
  local SPIN_FINISHER = {id = "spin_finisher", character = "toan", trigger = "combo_finisher", chain = 3, speed = 1.0,
    spin = 1, spin_from = 0.24, spin_to = 0.44, cooldown = 30,
    hits = {{at = 0.28, radius = 15, reach = 0, damage = 0.9}, {at = 0.36, radius = 15, reach = 0, damage = 0.9},
            {at = 0.44, radius = 15, reach = 0, damage = 0.9},
            {at = 0.59, radius = 11, reach = 9, damage = 2.0, knockback = 5, heavy = true, burst = "sparks", burst_scale = 1.5}},
    cues = {{at = 0.05, sound = "shout"}, {at = 0.25, sound = "swing", trail = "heavy"}, {at = 0.55, sound = "shout_2", trail = "wide"}}}
  local LUNGE = {id = "lunge_thrust", character = "toan", trigger = "lock_attack", direction = "toward", speed = 1.0,
    lunge = 3.0, lunge_decay = 0.22, cooldown = 24,
    hits = {{at = 0.36, radius = 10, reach = 9, damage = 1.3, knockback = 3}, {at = 0.5, radius = 10, reach = 11, damage = 0.8, knockback = 2}},
    cues = {{at = 0.15, sound = "voice_2"}, {at = 0.3, sound = "swing", trail = "wide"}}}
  local BACK_SLASH = {id = "back_slash", character = "toan", trigger = "lock_attack", direction = "away", speed = 1.0,
    lunge = 2.2, lunge_decay = 0.2, lunge_angle = 180, cooldown = 16,
    hits = {{at = 0.3, radius = 11, reach = 7, damage = 1.2, knockback = 3}},
    cues = {{at = 0.1, sound = "voice"}, {at = 0.22, sound = "swing", trail = "light"}}}
  local ROLL_SLASH = {id = "roll_slash", character = "toan", trigger = "evade_attack", speed = 1.0, lunge = 2.0,
    lunge_decay = 0.15, cooldown = 20,
    hits = {{at = 0.32, radius = 11, reach = 8, height = 6, damage = 1.6, knockback = 4}},
    cues = {{at = 0.05, sound = "voice_2"}, {at = 0.25, sound = "swing", trail = "wide"}}}
  -- Xiao has no combo of her own: each shot is a blow, so two or three shots in quick succession make the chain. Her
  -- finishers take no gauge (her shots have just spent it); the others take a full gauge, as her own shot does.
  local HEAVY_SHOT = {id = "heavy_shot", character = "xiao", trigger = "heavy", speed = 0.9, gauge = 100, cooldown = 30,
    hits = {{at = 0.53, shot = true, damage = 2.6, speed = 7}}, cues = {{at = 0.05, sound = "voice"}, {at = 0.5, sound = "shout"}}}
  local FAN = {id = "fan_shot", character = "xiao", trigger = "combo_finisher", chain = 2, from = 0.15, speed = 1.0, cooldown = 24,
    hits = {{at = 0.31, shot = true, count = 5, spread = 14, damage = 0.7}}, cues = {{at = 0.05, sound = "voice_2"}}}
  local VOLLEY = {id = "volley", character = "xiao", trigger = "combo_finisher", chain = 3, speed = 1.0, cooldown = 30,
    hits = {{at = 0.23, shot = true, count = 3, spread = 12, damage = 0.7}, {at = 0.42, shot = true, count = 3, spread = 12, damage = 0.7},
            {at = 0.62, shot = true, count = 3, spread = 12, damage = 0.7}},
    cues = {{at = 0.05, sound = "shout"}}}
  local DASH_SHOT = {id = "dash_shot", character = "xiao", trigger = "lock_attack", direction = "toward", from = 0.15, speed = 1.0,
    gauge = 100, lunge = 2.6, lunge_decay = 0.2, cooldown = 20,
    hits = {{at = 0.31, shot = true, damage = 1.4, speed = 7}}, cues = {{at = 0.05, sound = "voice"}}}
  local RETREAT_SHOT = {id = "retreat_shot", character = "xiao", trigger = "lock_attack", direction = "away", speed = 1.1,
    gauge = 100, lunge = 2.2, lunge_decay = 0.2, lunge_angle = 180, cooldown = 18,
    hits = {{at = 0.35, shot = true, count = 2, spread = 8, damage = 0.8}}, cues = {{at = 0, sound = "action"}}}
  local TUMBLE_SHOT = {id = "tumble_shot", character = "xiao", trigger = "evade_attack", from = 0.25, speed = 1.0, cooldown = 20,
    hits = {{at = 0.22, shot = true, count = 2, spread = 6, damage = 1.0}}, cues = {{at = 0.05, sound = "voice_2"}}}
  -- The same set for Goro and Ungaga (a melee recipe) and for Ruby and Osmond (a caster's), each with its own reach and
  -- gauge. Goro's slam and Ruby's casts take a full gauge each, so their chains come slower; Ungaga's spear combo
  -- chains like Toan's. Osmond's gun drains the gauge as it fires, so his moves take half of it.
  local function hit(t) t.radius = t.radius or 10; return t end
  local function melee_set(who, reach, power)
    local function d(x) return x * power end
    local function id(n) return who .. "_" .. n end
    return {
      {{id = id("dash"), character = who, trigger = "run_attack", run_frames = 20, speed = 1.0, lunge = 3.2, lunge_decay = 0.2,
        invincible = true, cooldown = 30, hits = {hit({at = 0.375, reach = 8 * reach, damage = d(1.4), knockback = 3})},
        cues = {{at = 0.15, sound = "voice_2"}, {at = 0.3, sound = "swing", trail = "wide"}}}, id("dash")},
      {{id = id("counter"), character = who, trigger = "guard_attack", speed = 1.0, invincible = true, cooldown = 20,
        hits = {hit({at = 0.33, reach = 6 * reach, height = 8, damage = d(1.8), knockback = 4, heavy = true})},
        cues = {{at = 0.1, sound = "voice"}, {at = 0.3, sound = "swing_heavy", trail = "wide"}}}, id("counter")},
      {{id = id("roll"), character = who, trigger = "dodge", speed = 0.5, lunge = 2.7, lunge_decay = 0.1, invincible = true,
        cooldown = 18, wear = 0, cancel = true, cancel_after = 2, cues = {{at = 0, sound = "action"}}}, id("roll")},
      {{id = id("backstep"), character = who, trigger = "dodge_back", speed = 1.1, lunge = 2.4, lunge_decay = 0.2, lunge_angle = 180,
        invincible = true, cooldown = 14, wear = 0, cancel = true, cancel_after = 2, cues = {{at = 0, sound = "action"}}}, id("backstep")},
      {{id = id("heavy"), character = who, trigger = "heavy", speed = 0.9, lunge = 1.2, lunge_decay = 0.15, cooldown = 30, wear = 1.5,
        hits = {hit({at = 0.43, radius = 11, reach = 8 * reach, damage = d(2.4), knockback = 5, heavy = true, burst = "impact", burst_scale = 1.5})},
        cues = {{at = 0.05, sound = "voice"}, {at = 0.36, sound = "swing_heavy", trail = "slam"}}}, id("heavy")},
      {{id = id("launcher"), character = who, trigger = "combo_finisher", chain = 2, speed = 1.1, lunge = 1.0, lunge_decay = 0.15,
        cooldown = 20, hits = {hit({at = 0.29, reach = 6 * reach, height = 8, damage = d(1.6), knockback = 6, heavy = true}),
                               hit({at = 0.4, reach = 5 * reach, height = 14, damage = d(0.8), knockback = 2})},
        cues = {{at = 0.1, sound = "voice_2"}, {at = 0.25, sound = "swing", trail = "wide"}}}, id("launcher")},
      {{id = id("spin_finisher"), character = who, trigger = "combo_finisher", chain = 3, speed = 1.0, spin = 1, spin_from = 0.24,
        spin_to = 0.44, cooldown = 30,
        hits = {hit({at = 0.28, radius = 15, reach = 0, damage = d(0.9)}), hit({at = 0.36, radius = 15, reach = 0, damage = d(0.9)}),
                hit({at = 0.44, radius = 15, reach = 0, damage = d(0.9)}),
                hit({at = 0.59, radius = 11, reach = 9 * reach, damage = d(2.0), knockback = 5, heavy = true, burst = "sparks", burst_scale = 1.5})},
        cues = {{at = 0.05, sound = "shout"}, {at = 0.25, sound = "swing", trail = "heavy"}, {at = 0.55, sound = "shout_2", trail = "wide"}}},
       id("spin_finisher")},
      {{id = id("lunge"), character = who, trigger = "lock_attack", direction = "toward", speed = 1.0, lunge = 3.0, lunge_decay = 0.22,
        cooldown = 24, hits = {hit({at = 0.375, reach = 8 * reach, damage = d(1.3), knockback = 3})},
        cues = {{at = 0.15, sound = "voice_2"}, {at = 0.3, sound = "swing", trail = "wide"}}}, id("dash")},
      {{id = id("back_slash"), character = who, trigger = "lock_attack", direction = "away", speed = 1.0, lunge = 2.2, lunge_decay = 0.2,
        lunge_angle = 180, cooldown = 16, hits = {hit({at = 0.3, radius = 11, reach = 7 * reach, damage = d(1.2), knockback = 3})},
        cues = {{at = 0.1, sound = "voice"}, {at = 0.22, sound = "swing", trail = "light"}}}, id("back_slash")},
      {{id = id("roll_slash"), character = who, trigger = "evade_attack", speed = 1.0, lunge = 2.0, lunge_decay = 0.15, cooldown = 20,
        hits = {hit({at = 0.32, radius = 11, reach = 8 * reach, height = 6, damage = d(1.6), knockback = 4})},
        cues = {{at = 0.05, sound = "voice_2"}, {at = 0.25, sound = "swing", trail = "wide"}}}, id("roll_slash")},
    }
  end
  local function caster_set(who, gauge)
    local function id(n) return who .. "_" .. n end
    return {
      {{id = id("rush"), character = who, trigger = "run_attack", run_frames = 20, speed = 1.0, gauge = gauge, cooldown = 20,
        hits = {{at = 0.42, shot = true, count = 3, spread = 12, damage = 0.8}}, cues = {{at = 0.1, sound = "voice"}}}, id("rush")},
      {{id = id("tumble"), character = who, trigger = "dodge", speed = 1.2, lunge = 2.4, lunge_decay = 0.11, invincible = true,
        cooldown = 16, wear = 0, cancel = true, cancel_after = 2, cues = {{at = 0, sound = "action"}}}, id("tumble")},
      {{id = id("hop_shot"), character = who, trigger = "dodge_back", speed = 1.1, lunge = 2.2, lunge_decay = 0.2, lunge_angle = 180,
        invincible = true, cooldown = 18, wear = 0, cancel = true, cancel_after = 2,
        hits = {{at = 0.3, shot = true, damage = 0.7}}, cues = {{at = 0, sound = "action"}}}, id("hop_shot")},
      {{id = id("heavy"), character = who, trigger = "heavy", speed = 0.9, gauge = gauge, cooldown = 30,
        hits = {{at = 0.53, shot = true, damage = 2.6, speed = 7}}, cues = {{at = 0.05, sound = "voice"}, {at = 0.5, sound = "shout"}}},
       id("heavy_cast")},
      {{id = id("fan"), character = who, trigger = "combo_finisher", chain = 2, from = 0.15, speed = 1.0, cooldown = 24,
        hits = {{at = 0.31, shot = true, count = 5, spread = 14, damage = 0.7}}, cues = {{at = 0.05, sound = "voice_2"}}}, id("rush")},
      {{id = id("volley"), character = who, trigger = "combo_finisher", chain = 3, speed = 1.0, cooldown = 30,
        hits = {{at = 0.23, shot = true, count = 3, spread = 12, damage = 0.7}, {at = 0.42, shot = true, count = 3, spread = 12, damage = 0.7},
                {at = 0.62, shot = true, count = 3, spread = 12, damage = 0.7}}, cues = {{at = 0.05, sound = "shout"}}}, id("volley")},
      {{id = id("dash_shot"), character = who, trigger = "lock_attack", direction = "toward", from = 0.15, speed = 1.0, gauge = gauge,
        lunge = 2.6, lunge_decay = 0.2, cooldown = 20, hits = {{at = 0.31, shot = true, damage = 1.4, speed = 7}},
        cues = {{at = 0.05, sound = "voice"}}}, id("rush")},
      {{id = id("retreat_shot"), character = who, trigger = "lock_attack", direction = "away", speed = 1.1, gauge = gauge, lunge = 2.2,
        lunge_decay = 0.2, lunge_angle = 180, cooldown = 18, hits = {{at = 0.3, shot = true, count = 2, spread = 8, damage = 0.8}},
        cues = {{at = 0, sound = "action"}}}, id("hop_shot")},
      {{id = id("tumble_shot"), character = who, trigger = "evade_attack", from = 0.25, speed = 1.0, cooldown = 20,
        hits = {{at = 0.22, shot = true, count = 2, spread = 6, damage = 1.0}}, cues = {{at = 0.05, sound = "voice_2"}}}, id("rush")},
    }
  end
  local PARTY = {melee_set("goro", 0.9, 1.1), melee_set("ungaga", 1.3, 1.0), caster_set("ruby", 100), caster_set("osmond", 50)}
  -- Opar (docs/OPAR_PLAN.md): he swings his staff on Toan's controls and spits on top of them. His spit is a blue glob
  -- from his mouth that splashes where it lands. A,A,R2 Spit (two globs), A,A,A,R2 Gob (a fan of three), a charge
  -- let go Bubble (one slow fat glob that bursts), L2 at rest Back Hop (a hop back with a glob at the top). Only when
  -- his registration took; his motions are his own (tools/anim/opar_moves.py).
  -- His kit (docs/OPAR_PLAN.md section 3): run+attack Belly Slide, guard+attack Staff Swat, L2 with the stick Frog Hop,
  -- attack late in a hop Leap Strike, locked on with the stick away + attack Tongue Lash (its hit yanks the enemy in,
  -- FORM.kit below), R2 at rest Croak (half the gauge; what it hits is stunned).
  local OPAR_ANIMS = {"opar_spit", "opar_gob", "opar_bubble", "opar_back_hop", "opar_belly_slide", "opar_staff_swat",
                      "opar_frog_hop", "opar_tongue_lash", "opar_croak", "opar_leap_strike", "opar_jump_slam"}
  local function glob(at, extra)
    local h = {at = at, shot = true, damage = 0.8, from = "jnt12_1", from_ahead = 2.6, from_rise = -0.4, cell = 8, size = 2.2,
               burst = "heal", burst_scale = 0.9}
    for k, v in pairs(extra or {}) do h[k] = v end
    return h
  end
  local OPAR = {
    {id = "opar_spit", character = "opar", trigger = "combo_finisher", chain = 2, animation = "opar_spit", speed = 1.0, cooldown = 20,
     hits = {glob(0.4, {damage = 1.3}), glob(0.52, {damage = 1.3})}, cues = {{at = 0.05, sound = "voice_2"}}},
    {id = "opar_gob", character = "opar", trigger = "combo_finisher", chain = 3, animation = "opar_gob", speed = 1.0, cooldown = 28,
     hits = {glob(0.46, {count = 3, spread = 14, damage = 1.5})}, cues = {{at = 0.05, sound = "voice"}}},
    {id = "opar_bubble", character = "opar", trigger = "charge_release", min_charge = 0.4, max_charge = 1.5, animation = "opar_bubble",
     speed = 0.9, cooldown = 30, hits = {glob(0.59, {damage = 3.0, speed = 2.5, size = 4.0, charged = true, burst = "heal", burst_scale = 2.0})},
     cues = {{at = 0.05, sound = "voice"}, {at = 0.55, sound = "shout"}}},
    {id = "opar_back_hop", character = "opar", trigger = "dodge_back", animation = "opar_back_hop", speed = 1.1, lunge = 2.2,
     lunge_decay = 0.2, lunge_angle = 180, invincible = true, cooldown = 18, wear = 0, cancel = true, cancel_after = 2,
     hits = {glob(0.32, {damage = 0.7})}, cues = {{at = 0, sound = "action"}}},
    {id = "opar_belly_slide", character = "opar", trigger = "run_attack", run_frames = 20, animation = "opar_belly_slide",
     speed = 0.9, lunge = 4.5, lunge_decay = 0.12, invincible = true, cooldown = 30,
     hits = {{at = 0.3, radius = 10, reach = 5, height = 2, damage = 1.6, knockback = 6},
             {at = 0.55, radius = 10, reach = 5, height = 2, damage = 1.2, knockback = 6}},
     cues = {{at = 0.1, sound = "voice_2"}, {at = 0.25, trail = "slam"}}},
    {id = "opar_staff_swat", character = "opar", trigger = "guard_attack", animation = "opar_staff_swat", speed = 1.0,
     spin = 1, spin_from = 0.3, spin_to = 0.72, invincible = true, cooldown = 24,
     hits = {{at = 0.35, radius = 14, reach = 0, damage = 1.3, knockback = 6}, {at = 0.6, radius = 14, reach = 0, damage = 1.1, knockback = 6}},
     cues = {{at = 0.05, sound = "voice"}, {at = 0.28, sound = "swing", trail = "wide"}}},
    {id = "opar_frog_hop", character = "opar", trigger = "dodge", animation = "opar_frog_hop", speed = 0.6, lunge = 3.0,
     lunge_decay = 0.12, invincible = true, cooldown = 18, wear = 0, cancel = true, cancel_after = 2,
     cues = {{at = 0, sound = "action"}}},
    {id = "opar_leap_strike", character = "opar", trigger = "evade_attack", animation = "opar_leap_strike", speed = 1.0,
     lunge = 2.0, lunge_decay = 0.15, cooldown = 24,
     hits = {{at = 0.47, radius = 12, reach = 4, damage = 1.6, knockback = 4, heavy = true, burst = "impact", burst_scale = 1.4},
             glob(0.61)},
     cues = {{at = 0.05, sound = "voice_2"}, {at = 0.38, sound = "swing_heavy", trail = "slam"}}},
    {id = "opar_tongue_lash", character = "opar", trigger = "lock_attack", direction = "away", animation = "opar_tongue_lash",
     speed = 1.0, cooldown = 30,
     hits = {{at = 0.33, radius = 5, reach = 34, height = 6, damage = 0.6, burst = "sparks", burst_scale = 0.8},
             {at = 0.72, radius = 10, reach = 7, damage = 1.4, knockback = 2, heavy = true}},
     cues = {{at = 0.05, sound = "voice"}, {at = 0.65, sound = "swing_heavy", trail = "heavy"}}},
    {id = "opar_croak", character = "opar", trigger = "heavy", animation = "opar_croak", speed = 1.0, gauge = 50, cooldown = 45,
     hits = {{at = 0.5, radius = 30, reach = 0, damage = 0.2, knockback = 4, burst = "guard", burst_scale = 2.5}},
     cues = {{at = 0.05, sound = "voice_2"}, {at = 0.46, sound = "shout"}}},
  }
  -- The leap: listed ahead of the Bubble, so a charge at the top is the slam and a shorter one the Bubble. No
  -- cooldown of its own (the big slam follows at once); its minute is FORM.ready_at's.
  local JUMP_SLAM = {id = "opar_jump_slam", character = "opar", trigger = "charge_release", min_charge = 1.5, max_charge = 10,
    animation = "opar_jump_slam", speed = 1.0, gauge = 100, cooldown = 0, invincible = true,
    cues = {{at = 0.05, sound = "shout"}}}
  -- The big slam, the monster's: its pack's motion 24 is its press and getting up (art/opar/make_form.py), joined in
  -- the air. Only his move while he is the monster, started by FORM.tick (its trigger never comes into it).
  local FORM_MOVES = {
    {id = "opar_form_slam", character = "opar", trigger = "heavy", motion = 24, from = 0.24, speed = 0.7, invincible = true,
     cooldown = 0, hits = {{at = 0.28, radius = 34, reach = 4, damage = 3.0, knockback = 9, heavy = true, charged = true,
                            burst = "explosion", burst_scale = 0.9}},
     cues = {{at = 0.24, sound = "swing_heavy", trail = "slam"}}},
  }
  local opar_animated
  local function register_opar()
    if opar_animated ~= nil then return opar_animated end
    opar_animated = ROSTER.registered and true or false
    if not opar_animated then return false end
    for _, id in ipairs(OPAR_ANIMS) do
      if not try(game.animations.player_register, {id = id, file = "resources/anims/" .. id .. ".json"}) then opar_animated = false end
    end
    return opar_animated
  end
  function MOVES.list()
    register()
    local list = {with(DASH, "toan_dash_thrust", 0x25), with(SWEEP, "toan_whirlwind", 0x28)}
    if animated then
      list[#list + 1] = with(COUNTER, "toan_rising_slash", nil)
      local roll = with(ROLL, "toan_roll", nil)
      if eternal("moonwalker") > 0 then roll.lunge = 3.2 end
      list[#list + 1] = roll
      list[#list + 1] = with(BACKSTEP, "toan_backstep", nil)
      list[#list + 1] = with(TRIPLE, "xiao_triple_shot", nil)
      local tumble = with(TUMBLE, "xiao_tumble", nil)
      if eternal("moonwalker") > 0 or sig("xiao", 4) then tumble.lunge = 2.9 end
      list[#list + 1] = tumble
      list[#list + 1] = with(HOP_SHOT, "xiao_hop_shot", nil)
      for _, m in ipairs({{HEAVY_CHOP, "toan_heavy_chop"}, {LAUNCHER, "toan_launcher"}, {SPIN_FINISHER, "toan_spin_finisher"},
                          {LUNGE, "toan_dash_thrust"}, {BACK_SLASH, "toan_back_slash"}, {ROLL_SLASH, "toan_roll_slash"},
                          {HEAVY_SHOT, "xiao_heavy_shot"}, {FAN, "xiao_triple_shot"}, {VOLLEY, "xiao_volley"},
                          {DASH_SHOT, "xiao_triple_shot"}, {RETREAT_SHOT, "xiao_hop_shot"}, {TUMBLE_SHOT, "xiao_triple_shot"}}) do
        list[#list + 1] = with(m[1], m[2], nil)
      end
      for _, set in ipairs(PARTY) do
        for _, m in ipairs(set) do
          local move = with(m[1], m[2], nil)
          if move.trigger == "dodge" and eternal("moonwalker") > 0 then move.lunge = move.lunge + 0.5 end
          list[#list + 1] = move
        end
      end
    end
    if not animated then list[2].spin_from, list[2].spin_to = nil, nil end
    if register_opar() then
      if FORM.active then
        for _, m in ipairs(FORM_MOVES) do
          if sig("opar", 5) then -- King of the Moon Sea: the slam 50% wider
            m = MOVES.faster(m, 1)
            m.hits[1].radius = math.min(40, m.hits[1].radius * 1.5)
          end
          list[#list + 1] = m
        end
      else
        if frame >= FORM.ready_at then list[#list + 1] = JUMP_SLAM end
        local fast = (LOOT.opar_staff() or {}).key == "reed"
        for _, m in ipairs(OPAR) do
          m = fast and MOVES.faster(m, 1.2) or m
          if m.id == "opar_gob" and sig("opar", 1) then -- Big Mouth
            m = MOVES.faster(m, 1)
            m.hits[1].count, m.hits[1].spread, m.hits[1].damage = 5, 12, 1.1
          end
          list[#list + 1] = m
        end
      end
    end
    return list
  end
  -- A move with its shots that much faster (the Reed Staff's globs).
  function MOVES.faster(m, k)
    local copy = {}
    for f, v in pairs(m) do copy[f] = v end
    copy.hits = {}
    for i, h in ipairs(m.hits or {}) do
      local hc = {}
      for f, v in pairs(h) do hc[f] = v end
      if hc.shot then hc.speed = math.min(10, (hc.speed or 5) * k) end
      copy.hits[i] = hc
    end
    return copy
  end
  function MOVES.apply()
    if not setting("new_moves", true) then try(game.player.moves_clear); return end
    try(game.player.moves_set, {moves = MOVES.list()})
    -- each drafted character's controls, once a run (the Move tips setting)
    if not setting("move_tips", true) then return end
    if run and not run.moves_told and contains(run.drafted, "toan") then
      run.moves_told = true
      toast("Toan: run+attack Dash, long charge Spin, guard+attack Counter.")
      toast("Toan: L2 rolls or backsteps, even out of a swing.")
      toast("Toan: R2 heavy Chop. A,A,R2 Launcher; A,A,A,R2 Spin Finisher.")
      toast("Toan: locked on, toward+A Lunge, away+A Back Slash.")
      toast("Toan: A as a roll ends: Roll Slash.")
    end
    if run and not run.xiao_moves_told and contains(run.drafted, "xiao") then
      run.xiao_moves_told = true
      toast("Xiao: run+attack Triple Shot. L2 tumbles, or hops back firing.")
      toast("Xiao: R2 Heavy Shot. A,A,R2 Fan Shot; A,A,A,R2 Volley.")
      toast("Xiao: locked on, toward+A Dash Shot, away+A Retreat Shot.")
      toast("Xiao: A as a tumble ends: Tumble Shot.")
    end
    if run and not run.opar_moves_told and contains(run.drafted, "opar") and ROSTER.registered then
      run.opar_moves_told = true
      toast("Opar: A swings the staff. A,A,R2 Spit; A,A,A,R2 Gob.")
      toast("Opar: let a charge go to blow a Bubble. L2 at rest hops back spitting.")
      toast("Opar: run+attack Belly Slide, guard+attack Staff Swat, R2 Croak stuns.")
      toast("Opar: L2 Frog Hop, A as it lands Leap Strike. Locked on, away+A Tongue Lash.")
      toast("Opar: full gauge, hold a charge to the top: he leaps and slams down as the giant Opar.")
    end
    -- The other four share the same controls, so one notice each.
    for _, who in ipairs({"goro", "ungaga", "ruby", "osmond"}) do
      if run and contains(run.drafted, who) and not (run.party_moves_told or {})[who] then
        run.party_moves_told = run.party_moves_told or {}
        run.party_moves_told[who] = true
        local name = who:sub(1, 1):upper() .. who:sub(2)
        toast(name .. ": R2 heavy; A,A,R2 and A,A,A,R2 finishers; L2 evades.")
        toast(name .. ": locked on, toward or away+A; A as an evade ends follows up.")
      end
    end
  end
  function MOVES.clear() try(game.player.moves_clear) end
end

-- Shared ABS: benched drafted allies' equipped weapons get a share of each kill's ABS. Their level-ups are quiet (they
-- came up on screen with every few kills); the weapon simply arrives stronger when that ally steps in.
local function share_abs(amount, active)
  local share = math.floor(amount * setting("ally_abs_share", 50) / 100 * (1 + 0.25 * eternal("spoils")))
  if share <= 0 or not run or not run.weapons then return end
  for _, c in ipairs(run.drafted) do
    local w = c ~= active and run.weapons[c]
    if w then
      local selector = {id = w.id, character = c, slot = w.slot}
      local added = try(game.weapons.abs_add, {id = w.id, character = c, slot = w.slot, amount = math.min(32767, share)})
      if added and (added.abs or 0) >= (added.abs_max or math.huge) then
        try(game.weapons.upgrade, selector)
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
    for _, f in ipairs(route(index).floors) do
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
  ROSTER.sync()
  local start = contains(CHARACTERS, meta.start_char) and meta.start_char or "toan" -- Opar only with his setting
  return {title = "DARK GENIE'S GAUNTLET", subtitle = "Five biomes. No saves. No way back.", root = true, hint = "",
          lines = lines, entries = {
            {id = "start", label = "Start Run", enabled = ready > 0},
            {id = "character", label = "Starting Character: " .. title(start)},
            {id = "legend", label = "Starting Weapon: " .. LOOT.start_label(start)},
            {id = "eternal", label = "Norune Eternal"},
            {id = "records", label = "Records"},
          }}
end

local eternal_msg = nil -- {id, text}: the answer to the last Cross or Square, shown on that node
local function eternal_open(n)
  if n.group == "norune" and n.path == 0 then return true end
  if #n.needs == 0 then return true end
  for _, id in ipairs(n.needs) do if owned(id) > 0 then return true end end
  return false
end
local function purse(n)
  if n.cur == "sigil" then return meta.sigils, "Genie Sigil" end
  if n.cur == "mark" then return math.floor(tonumber(meta.marks[n.char]) or 0), title(n.char) .. " Mark" end
  return meta.shards, "Moon Shard"
end
local function spend(n, amount)
  if n.cur == "sigil" then meta.sigils = meta.sigils - amount
  elseif n.cur == "mark" then meta.marks[n.char] = math.floor(tonumber(meta.marks[n.char]) or 0) - amount
  else meta.shards = meta.shards - amount end
end
local function plural(count, word) return count .. " " .. word .. (count == 1 and "" or "s") end
local function node_names(ids)
  local t = {}
  for _, id in ipairs(ids) do t[#t + 1] = ETERNAL_NODE[id] and ETERNAL_NODE[id].title or id end
  return table.concat(t, " or ")
end
-- The lines drawn between nodes: each node to what it needs (a trunk to the heart of the sky).
local function sky_links(n)
  local links = {}
  for _, id in ipairs(n.needs) do if ETERNAL_NODE[id] and #links < 4 then links[#links + 1] = id end end
  if #links == 0 and n.path == 0 and n.group ~= "norune" and not SKY_GROUP[n.group].signature then links[1] = "norune" end
  return #links > 0 and links or nil -- an empty table would reach the engine as an object, not a list
end
local function eternal_sky()
  local groups, nodes, texts = {}, {}, {}
  for _, g in ipairs(SKY_GROUPS) do
    if not revealed(g.reveal) then goto hidden_group end
    groups[#groups + 1] = {id = g.id, name = g.name, colour = g.colour, x = g.x, y = g.y}
    for _, t in ipairs(g.texts or {}) do
      if #texts < 24 then texts[#texts + 1] = {text = t.text, x = g.x + t.x, y = g.y + t.y, colour = g.colour} end
    end
    ::hidden_group::
  end
  local opens = {}
  for _, n in ipairs(ETERNAL) do for _, need in ipairs(n.needs) do opens[need] = opens[need] or {}; table.insert(opens[need], n.title) end end
  for _, n in ipairs(ETERNAL) do
    if not (revealed(n.reveal) and revealed(SKY_GROUP[n.group].reveal)) then goto hidden_node end
    local r = owned(n.id)
    local state = (r > 0 or n.group == "norune" and n.path == 0) and "owned" or (eternal_open(n) and not n.soon and "open" or "locked")
    local rank = n.max_rank > 1 and (r .. "/" .. n.max_rank) or ""
    if n.max_rank > 1 and r > 0 and eternal(n.id) > 0 and eternal(n.id) < r then rank = eternal(n.id) .. "/" .. r .. " of " .. n.max_rank end
    local cost
    if n.soon then cost = "Coming soon"
    elseif n.max_rank == 0 then cost = ""
    elseif r >= n.max_rank then cost = "Complete"
    else
      local price = n.costs[r + 1]
      local _, unit = purse(n)
      cost = "Next: " .. plural(price, unit)
    end
    if eternal_msg and eternal_msg.id == n.id then cost = eternal_msg.text end
    local text = n.text
    if n.heat then text = text .. " Heat +" .. n.heat .. (n.max_rank > 1 and " per rank." or ".") end
    if n.key then text = text .. (n.pact and " (A Pact Keystone.)" or (n.signature_key and "" or " (A Keystone.)")) end
    local needs = {}
    if #n.needs > 0 then needs[#needs + 1] = "Needs: " .. node_names(n.needs) end
    if opens[n.id] then needs[#needs + 1] = "Opens: " .. table.concat(opens[n.id], ", ") end
    local g = SKY_GROUP[n.group]
    nodes[#nodes + 1] = {id = n.id, group = n.group, x = n.x, y = n.y, label = n.title, rank = rank, icon = n.icon,
      title = n.title, tag = (n.path_name or ((n.path > 0 or g.name == n.title) and "" or g.name)), text = text:sub(1, 160),
      needs = table.concat(needs, "    "):sub(1, 96), cost = cost:sub(1, 48), state = state,
      on = r > 0 and not meta.off[n.id] or n.group == "norune" and n.path == 0, keystone = n.key == true, links = sky_links(n)}
    ::hidden_node::
  end
  -- the path names: each path's first node carries it
  for _, n in ipairs(nodes) do
    local spec = ETERNAL_NODE[n.id]
    if spec.path > 0 and n.tag == "" then
      for _, m in ipairs(ETERNAL) do if m.group == spec.group and m.path == spec.path and m.path_name then n.tag = m.path_name end end
    end
  end
  local h = heat()
  return {groups = groups, nodes = nodes, texts = texts,
          top = {"Moon Shards " .. meta.shards,
                 "Genie Sigils " .. meta.sigils .. "    " .. title(meta.start_char) .. " Marks " .. math.floor(tonumber(meta.marks[meta.start_char]) or 0),
                 string.format("Heat %d  x%.1f    Keystones %d/%d", h, 1 + 0.1 * h, keystones_on(), keystone_slots())}}
end
local function eternal_page()
  return {title = "NORUNE ETERNAL", root = false, sky = eternal_sky()}
end
local function eternal_say(n, text) eternal_msg = {id = n.id, text = text} end
local function eternal_action(id, action)
  local n = ETERNAL_NODE[id]
  eternal_msg = nil
  if not n then return end
  local r = owned(id)
  if action == "buy" then
    if n.max_rank == 0 then eternal_say(n, "The heart of the sky"); return end
    if n.soon then eternal_say(n, "Coming soon: not in this build yet"); return end
    if not (revealed(n.reveal) and revealed(SKY_GROUP[n.group].reveal)) then return end
    if r >= n.max_rank then eternal_say(n, "Complete"); return end
    if not eternal_open(n) then eternal_say(n, "Needs " .. node_names(n.needs) .. " first"); return end
    local price = n.costs[r + 1]
    local have, unit = purse(n)
    if have < price then eternal_say(n, "Needs " .. plural(price, unit) .. ", you have " .. have); return end
    spend(n, price)
    meta.eternal[id] = r + 1
    meta.set[id] = nil
    if r == 0 and counts_as_keystone(n) and keystones_on(id) >= keystone_slots() then
      meta.off[id] = true
      eternal_say(n, "Bought: Keystone slots full, switched off")
    else
      eternal_say(n, (r + 1 < n.max_rank) and ("Rank " .. (r + 1) .. " bought") or "Bought")
    end
    try(game.audio.se_play, {se = 20})
  elseif action == "toggle" then
    if r == 0 then eternal_say(n, n.max_rank == 0 and "The heart of the sky" or "Buy it first"); return end
    if meta.off[id] then
      if counts_as_keystone(n) and keystones_on(id) >= keystone_slots() then
        eternal_say(n, "Keystone slots full (" .. keystones_on(id) .. "/" .. keystone_slots() .. ")")
        return
      end
      meta.off[id] = nil
      eternal_say(n, "Switched on")
    else
      meta.off[id] = true
      eternal_say(n, "Switched off")
    end
  elseif action == "rank_up" or action == "rank_down" then
    if r < 2 then eternal_say(n, "Only one rank"); return end
    local now = eternal(id) > 0 and eternal(id) or r
    local want = math.max(1, math.min(r, now + (action == "rank_up" and 1 or -1)))
    meta.set[id] = want < r and want or nil
    eternal_say(n, "Using rank " .. want .. " of " .. r)
  end
  save_meta()
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

local loadout_saving = false -- the Loadouts page's Cross: false loads, true saves
local function loadouts_page()
  local entries = {}
  for k = 1, 4 do
    local l = meta.loadouts[k] or meta.loadouts[tostring(k)]
    entries[k] = {id = "l" .. k, label = l and string.format("Loadout %d: %d on, Heat %d", k, l.on or 0, l.heat or 0) or ("Loadout " .. k .. ": empty")}
  end
  entries[5] = {id = "mode", label = loadout_saving and "Cross saves the sky's switches" or "Cross loads a loadout"}
  return {title = "LOADOUTS", subtitle = "Norune Eternal", root = false, hint = "{cross} Choose   {circle} Back",
          lines = {"A loadout keeps which nodes are on and the rank each is set to.", eternal_msg and eternal_msg.text or ""},
          entries = entries}
end
local function loadout_action(entry)
  eternal_msg = nil
  if entry == "mode" then loadout_saving = not loadout_saving; return end
  local k = tonumber(entry:match("^l(%d)$")); if not k then return end
  if loadout_saving then
    local on = 0
    for _, n in ipairs(ETERNAL) do if n.max_rank > 0 and eternal(n.id) > 0 then on = on + 1 end end
    meta.loadouts[k] = {off = deepcopy(meta.off), set = deepcopy(meta.set), on = on, heat = heat()}
    eternal_msg = {text = "Saved to Loadout " .. k}
  else
    local l = meta.loadouts[k] or meta.loadouts[tostring(k)]
    if not l then eternal_msg = {text = "Loadout " .. k .. " is empty"}; return end
    meta.off, meta.set = deepcopy(l.off or {}), deepcopy(l.set or {})
    -- a Keystone bought after the save stays off if the slots are full
    for _, n in ipairs(ETERNAL) do
      if counts_as_keystone(n) and eternal(n.id) > 0 and keystones_on(n.id) >= keystone_slots() then meta.off[n.id] = true end
    end
    eternal_msg = {text = "Loaded Loadout " .. k}
  end
  save_meta()
end

local function show_page(name, cursor)
  page = name
  local data = name == "eternal" and eternal_page() or (name == "records" and records_page() or
               (name == "loadouts" and loadouts_page() or root_page()))
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
  eternal_msg = nil
  show_page("root")
end)

moonmod.on("game.title.selected", function(e)
  local entry = e and e.entry
  if page == "root" then
    if entry == "start" then start_run()
    elseif entry == "character" then
      ROSTER.sync()
      local index = 1
      for i, c in ipairs(CHARACTERS) do if c == meta.start_char then index = i end end
      meta.start_char = CHARACTERS[index % #CHARACTERS + 1]
      save_meta()
      show_page("root", 1)
    elseif entry == "legend" then
      LOOT.cycle_start(meta.start_char)
      save_meta()
      show_page("root", 2)
    elseif entry == "eternal" then eternal_msg = nil; show_page("eternal", 0)
    elseif entry == "records" then show_page("records", 0)
    end
  elseif page == "eternal" then
    if entry == "back" then eternal_msg = nil; show_page("root", 3); return end
    if entry == "loadouts" and e.action == "buy" and owned("loadouts") > 0 then
      eternal_msg, loadout_saving = nil, false
      show_page("loadouts", 0)
      return
    end
    eternal_action(entry, e.action)
    show_page("eternal", 0)
  elseif page == "loadouts" then
    if entry == "back" then eternal_msg = nil; show_page("eternal", 0); return end
    loadout_action(entry)
    show_page("loadouts", cursor_of(loadouts_page().entries, entry))
  elseif page == "records" then
    show_page("root", 4)
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
  ROSTER.set(ROSTER.wanted())
  local start = contains(CHARACTERS, meta.start_char) and meta.start_char or "toan"
  run = {active = true, phase = "launch", biomes = biomes, pos = 1, slot = 1, depth = 0, next_cursed = false,
         stock = {}, diorama = {}, blessings = {}, drafted = {start}, shards = 0,
         heirloom_charges = 0, kills = 0, weapons = {}, opar = CHARACTERS[7] ~= nil}
  -- Endless Maze: the five-floor biomes, when every one of them registered
  run.maze = eternal("maze") > 0
  WARDEN_SLOT = run.maze and 5 or 4
  set_redirects(run.maze)
  -- Shuffled floors: after 1-1 (always the first biome's own dungeon) each floor before a Warden is in a dungeon
  -- drawn at random.
  if setting("floor_shuffle", true) and #available > 1 then
    run.plan = {}
    for p = 1, #biomes do
      run.plan[p] = {}
      for slot = 1, WARDEN_SLOT - 1 do run.plan[p][slot] = (p == 1 and slot == 1) and biomes[1] or pick(available) end
    end
  end
  if eternal("fullparty") > 0 then
    for _, c in ipairs(CHARACTERS) do if c ~= start then run.drafted[#run.drafted + 1] = c end end
  elseif eternal("embassy") > 0 then
    local others = {}
    for _, c in ipairs(CHARACTERS) do if c ~= start then others[#others + 1] = c end end
    run.drafted[#run.drafted + 1] = pick(others)
  end
  run.heat = heat()
  -- The Genie's Lair after the last Warden
  run.finale = setting("genie_finale", true)
  for _, id in ipairs(TILE_IDS) do run.diorama[id] = 0; run.stock[id] = 0 end
  local result, err = call(game.session.start, {floor = route(biomes[1]).floors[1].id, party_size = #CHARACTERS, character = start})
  if not result then
    run = nil
    WARDEN_SLOT = 4
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
  for i = 2, #run.drafted do
    if run.drafted[i] == "opar" then LOOT.staff_start("opar", equipped_weapon("opar")) end
  end
  local w = equipped_weapon(start)
  if w then
    w = LOOT.staff_start(start, w)
    local before = w.id
    w = LOOT.start_weapon(start, w)
    if w.id ~= before then notes[#notes + 1] = LOOT.LEGENDS[start].name .. " in hand" end
    local selector = {id = w.id, character = start, slot = w.slot}
    if apply_heirloom(start, w) then notes[#notes + 1] = "Heirloom applied" end
    if eternal("master") > 0 then
      -- Master's Gift: the character's second weapon in place of the first
      local second = "chronicle:weapon:" .. ((tonumber(tostring(w.id):match("(%d+)$")) or 0) + 1)
      local given = call(game.weapons.give, {id = second, character = start})
      if given and call(game.weapons.equip, {id = second, character = start, slot = given.slot}) then
        try(game.weapons.remove, {id = w.id, character = start, slot = w.slot})
        w = {id = second, slot = given.slot}
        selector = {id = w.id, character = start, slot = w.slot}
        notes[#notes + 1] = "Master's Gift"
      end
    end
    local leveled = eternal("smith") > 0 and level_up(selector, eternal("smith")) or 0
    if leveled > 0 then notes[#notes + 1] = "+" .. leveled .. " level" .. (leveled == 1 and "" or "s") end
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
  if setting("starter_kit", true) and eternal("lean") == 0 then
    try(game.items.give, {id = "chronicle:item:" .. ITEM.bread, count = 2 + (eternal("baker") > 0 and 2 or 0)})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.water, count = 2})
    try(game.items.give, {id = "chronicle:item:" .. ITEM.repair, count = 2 + eternal("kit")})
  end
  if eternal("charm") > 0 or eternal("unbreakable") > 0 then try(game.items.give, {id = "chronicle:item:" .. ITEM.auto_repair, count = 1}) end
  if eternal("gem") > 0 then try(game.items.give, {id = "chronicle:item:" .. pick(GEMS), count = 1}) end
  if eternal("antidote") > 0 then try(game.items.give, {id = "chronicle:item:" .. ITEM.antidote, count = 2}) end
  if eternal("purse") > 0 then try(game.economy.add, {amount = 300}) end
  if eternal("heart") > 0 then
    for _, c in ipairs(run.drafted) do
      local hp = max_hp_of(c)
      if hp then try(game.player.set, {max_hp = hp + 10 * eternal("heart"), character = c}); try(game.player.set, {hp = hp + 10 * eternal("heart"), character = c}) end
    end
  end
  if eternal("spring") > 0 then run.stock.river = (tonumber(run.stock.river) or 0) + 1 end
  if eternal("living") > 0 then
    for _ = 1, 2 do local id = pick(TILE_IDS); run.diorama[id] = placed(id) + 1 end
  end
  if sig("toan", 5) then bless("Atlamillia's Chosen", {id = "atla"}) end
  if eternal("moon") > 0 then bless("Moon Blessing", {start = true}) end
  if eternal("second") > 0 then bless("Second Blessing", {start = true}) end
  if sig("osmond", 5) then bless("Moon People's Gift", {start = true}) end
  -- Swordsman: Toan's weapons take one more attachment for the run
  if sig("toan", 3) then
    run.sockets = {}
    for _, def in ipairs(try(game.weapons.list) or {}) do
      if type(def) == "table" and def.owner == "toan" and (def.socket_count or 0) < 6 and not def.mod_owned then
        local no = tonumber(def.native_item_no or def.item_no)
        if no and try(game.weapons.definition_set, {id = no, hole_num = def.socket_count + 1}) then run.sockets[tostring(no)] = def.socket_count end
      end
    end
  end
  cache_weapons()
  prepare_floor_rules()
  push_diorama_ranks()
  toast(biome_def(1).name .. " 1-1. " .. title(start) .. (#run.drafted > 1 and (" and " .. title(run.drafted[2]) .. " set") or " sets") .. " out.")
  if #notes > 0 then toast(table.concat(notes, ". ") .. ".") end
end

local function end_run(outcome)
  if not run then return end
  try(game.dungeons.set_shortcuts, {count = 0})
  try(game.dungeons.set_weapon_drops, {})
  try(game.dungeons.set_backrooms, {free = false})
  try(game.dungeons.set_warden_room, {enabled = false})
  try(game.dungeons.set_rest_room, {enabled = false})
  try(game.dungeons.set_character_blocks, {})
  try(game.entities.set_active_limit, {active = 4})
  LOOT.reset()
  MOVES.clear()
  companion_out = nil
  try(game.party.companion_set, {})
  try(game.player.fatal_guard, {charges = 0})
  for no, count in pairs(run.sockets or {}) do try(game.weapons.definition_set, {id = tonumber(no), hole_num = count}) end
  local depth = run.depth
  local earned = run.shards
  if outcome == "victory" then earned = earned + 10 end
  local h = run.heat or 0
  earned = math.floor(earned * (1 + 0.1 * h) * (1 + 0.1 * eternal("lens")) * (eternal("fullparty") > 0 and 0.9 or 1) + 0.5)
  local sigils = run.sigils or 0
  if outcome == "victory" then
    sigils = sigils + 3 + (h >= 10 and 1 or 0) + (h >= 15 and 1 or 0) + (h >= 20 and 1 or 0)
    meta.best_heat = math.max(meta.best_heat, h)
  end
  meta.sigils = meta.sigils + sigils
  local cleared = outcome == "victory" and #run.biomes or (run.pos - 1)
  local starter = run.drafted[1]
  if cleared > 0 and starter then meta.marks[starter] = math.floor(tonumber(meta.marks[starter]) or 0) + cleared end
  meta.shards = math.min(SHARD_LIMIT, meta.shards + earned)
  meta.best_depth = math.max(meta.best_depth, depth)
  if outcome == "victory" then meta.wins = meta.wins + 1
  elseif outcome == "death" or outcome == "broken" then meta.deaths = meta.deaths + 1
  else meta.retreats = meta.retreats + 1 end
  save_meta()
  local b = biome_def(run.pos)
  local where = run.lair == "in" and "the Genie's Lair" or
      b and (b.name .. (run.slot >= WARDEN_SLOT and " Warden" or (run.slot == 0 and " Rest" or (" " .. run.pos .. "-" .. run.slot)))) or "?"
  local headline = outcome == "victory" and "CONQUERED" or (outcome == "death" and "Fell in " .. where or
      (outcome == "broken" and "Weapon broke in " .. where or "Left at " .. where))
  last_result = string.format("Last run: %s, depth %d, +%d", headline, depth, earned):sub(1, 64) -- Moon Shards are on the line above
  run = nil
  WARDEN_SLOT = 4
  set_redirects(nil)
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
  if not ally then earn_shards(2); toast("No one left to draft: +2 Moon Shards."); return end
  run.drafted[#run.drafted + 1] = ally
  try(game.player.set, {hp = max_hp_of(ally), character = ally})
  LOOT.staff_start(ally, equipped_weapon(ally))
  run.weapons[ally] = equipped_weapon(ally)
  toast(why .. ": " .. title(ally) .. " joins the run!")
end

local function complete_floor(prev)
  run.floors_done = (run.floors_done or 0) + 1
  local depth = run.depth
  earn_shards(1)
  pay((eternal("floorspay") > 0 and 60 or 40) * depth)
  local p = try(game.player.get)
  if p and eternal("field") > 0 and p.weapon and p.weapon.id and (p.weapon.durability_max or 0) > 0 then
    try(game.weapons.durability_set, {id = p.weapon.id, character = p.character, slot = p.weapon.slot,
        durability = math.min(p.weapon.durability_max, math.floor(p.weapon.durability + p.weapon.durability_max / 10))})
  end
  if p and eternal("rain") > 0 and p.max_water then
    try(game.player.set, {water = math.min(p.max_water, math.floor((p.water or 0) + p.max_water / 4)), character = p.character})
  end
  if eternal("hearty") > 0 and (run.hearty or 0) < 5 then
    run.hearty = (run.hearty or 0) + 1
    try(game.items.give, {id = "chronicle:item:" .. ITEM.bread, count = 1})
  end
  if eternal("benchrest") > 0 and p then
    for _, c in ipairs(run.drafted) do
      local hp = max_hp_of(c)
      if c ~= p.character and hp then try(game.player.heal, {amount = math.max(1, math.floor(hp / 20)), character = c}) end
    end
  end
  local tiles = 1 + (prev.swept and 1 or 0) + (prev.cursed and 1 or 0)
  if prev.cursed then
    earn_shards(2)
    miracle_cache()
    if math.random(100) <= 35 then bless("Cursed floor survived") end
  end
  if prev.back then earn_shards(2); bless("Vault cleared") end
  give_tiles(tiles, (prev.swept and "Floor swept" or "Floor cleared"))
end

-- Guard charges for the floor: Second Wind gives each drafted character one; Cat's Nine Lives one more for
-- Xiao until it is spent in the biome.
set_guards = function()
  if not run then return end
  for _, c in ipairs(CHARACTERS) do
    local n = 0
    if contains(run.drafted, c) then
      if eternal("secondwind") > 0 and not (floor and floor.winded and floor.winded[c]) then n = n + 1 end
      if c == "xiao" and run.nine_lives then n = n + 1 end
    end
    try(game.player.fatal_guard, {charges = n, character = c})
  end
end

moonmod.on("game.player.guarded", function(e)
  if not on_route() then return end
  local c = e.character
  if eternal("secondwind") > 0 and floor and floor.winded and not floor.winded[c] then
    floor.winded[c] = true
    toast("Second Wind! " .. title(c) .. " hangs on.")
  elseif c == "xiao" and run.nine_lives then
    run.nine_lives = false
    toast("Cat's Nine Lives! Xiao lands on her feet.")
  end
  save_run()
end)

local function warden_cleared()
  if not (run and floor) or floor.warden_done then return end
  -- A boss fades out with its cast; the prize panel pauses the game, so it waits until they are gone (it is asked
  -- again every tick).
  if floor.warden_boss and not floor.back then
    floor.warden_fall = floor.warden_fall or frame + 120
    if frame < floor.warden_fall then return end
  end
  floor.warden_done = true
  try(game.render.bar_remove, {id = "warden"})
  if not floor.back then try(game.dungeons.warden_room_release) end
  if floor.back then
    earn_shards(eternal("tithe") > 0 and 8 or 5)
    give_tiles(2, "Vault Warden felled")
    bless("Vault Warden felled")
    toast("The Vault's Warden falls! Its hoard is yours.")
    save_run()
    refresh()
    return
  end
  if floor.lair then
    earn_shards(eternal("tithe") > 0 and 20 or 12)
    if (run.heat or 0) >= 5 then run.sigils = (run.sigils or 0) + 1 end
    run.phase = "victory"
    toast("The Dark Genie is vanquished. The Gauntlet is conquered!")
    queue_transition("end", 360, "victory")
    save_run()
    refresh()
    return
  end
  earn_shards(eternal("tithe") > 0 and 6 or 3)
  if (run.heat or 0) >= 5 then run.sigils = (run.sigils or 0) + 1 end
  if floor.dungeon == 4 and not meta.opar_met and ROSTER.registered then
    -- the Moon Sea's Warden: Opar is met, and his star rises in Norune Eternal's Allies (and his Signature sky)
    meta.opar_met = true
    save_meta()
    toast("A new star rises in the Allies: Opar of the Moon Sea.")
  end
  LOOT.warden_drop()
  give_tiles(1, "Warden felled")
  bless("Warden felled")
  if eternal("vault") > 0 then run.heirloom_charges = run.heirloom_charges + 1 end
  local last = run.pos >= #run.biomes
  local lair = last and run.finale and route(run.biomes[run.pos]).lair
  if lair then
    -- The finale: the floor below the last Warden is the Genie's Lair.
    run.lair = "pending"
    toast("The last Warden falls, and the ground shakes. The Genie's Lair awaits!")
    queue_transition(lair.id, 300, "genie's lair")
  elseif last then
    run.phase = "victory"
    toast("The last Warden falls. The Gauntlet is conquered!")
    queue_transition("end", 300, "victory")
  else
    local next_biome = BIOMES[run.biomes[run.pos + 1]]
    local rest = setting("rest_rooms", true) and route(run.biomes[run.pos + 1]).rest
    run.awaiting = run.pos + 1
    if floor.cursed_path then
      -- the Cursed Path walked to its end: its own prize on top of the Warden's
      miracle_cache()
      bless("Cursed Path conquered")
      earn_shards(3)
    end
    toast("Warden felled! " .. (rest and "A rest before " or "On to ") .. next_biome.name .. "." ..
        (run.heirloom_charges > 0 and " Heirloom charge ready." or ""))
    queue_transition(rest and rest.id or route(planned(run.pos + 1, 1)).floors[1].id, 300, rest and "rest floor" or "next biome")
  end
  save_run()
  refresh()
end

-- The Rest floor between biomes (REST.arrive, REST.tick, REST.cursed, after Gaffer's shop).
local REST = {}

local function enter_floor(world)
  -- Retail keeps only the 4 nearest monsters awake; the others stand dormant (still, and no hit lands on them) until
  -- one of those dies. A run's crowded rooms, or 4 awake ones stuck out of reach, could leave the rest asleep and the
  -- floor uncleared, so a run keeps 12 awake.
  try(game.entities.set_active_limit, {active = 12})
  local hit = floor_at(world.dungeon_id, world.floor_id)
  -- The native exit gate led on in the same dungeon while the plan has the next floor elsewhere: send the run there.
  if hit and run.phase == "active" and not run.shuffle_to and not world.back_floor and floor and floor.dungeon == hit.biome and
      hit.slot == run.slot + 1 then
    local want = planned(run.pos, hit.slot)
    local r = want and route(want)
    if want and want ~= hit.biome and r and r.floors[hit.slot] then
      run.shuffle_to = {biome = want, slot = hit.slot}
      queue_transition(r.floors[hit.slot].id, 1, "shuffled floor")
      return
    end
  end
  local pos = nil
  if hit and hit.rest then
    -- the Rest floor before the biome being moved to (or this one's, reloaded)
    pos = run.awaiting or (run.slot == 0 and run.pos) or nil
    if pos and run.biomes[pos] ~= hit.biome then pos = nil end
  elseif hit then
    -- the floor the plan expects here (this biome, or the next one being moved to), else the dungeon's own biome
    for _, p in ipairs({run.pos, run.awaiting or 0}) do
      if not pos and p >= 1 and planned(p, hit.slot) == hit.biome then pos = p end
    end
    if not pos then for p, index in ipairs(run.biomes) do if index == hit.biome then pos = p end end end
  end
  -- The native exit gate led on in the same dungeon while the plan has the next floor elsewhere: the move there
  -- is under way, so a stop anywhere but the planned floor doesn't count.
  if run.shuffle_to then
    if not (hit and hit.biome == run.shuffle_to.biome and hit.slot == run.shuffle_to.slot) then return end
    run.shuffle_to = nil
  end
  local prev = floor
  -- The engine reports the new floor a few frames before it builds it and sets its seed: the second sighting
  -- of the same floor is the same arrival.
  if prev and pos and pos == prev.biome and hit.slot == prev.slot and (world.back_floor == true) == prev.back and
      (hit.lair == true) == (prev.lair == true) and frame - (prev.entered or 0) < 120 then
    prev.token = world.token
    return
  end
  local expected = false
  if pos then
    if run.phase == "launch" then expected = pos == 1 and hit.slot == 1
    elseif hit.lair then expected = run.lair ~= nil and pos == run.pos                     -- the finale (or a reload of it)
    elseif run.lair == "in" then expected = false                                          -- nothing leads back up from the Lair
    elseif hit.rest then expected = true                                                    -- between biomes (pos checked above)
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
    toast("Off the Gauntlet route: the run is paused here.")
    save_run()
    refresh()
    return
  end
  run.suspended = false
  local advanced = run.phase == "launch" or pos ~= run.pos or hit.slot ~= run.slot or (hit.lair and run.lair == "pending")
  if hit.lair then run.lair = "in" end
  if run.phase == "active" and advanced and prev and prev.biome == run.pos and prev.slot > 0 then complete_floor(prev) end
  local first = run.phase == "launch"
  if first then run.phase = "active" end
  if advanced and not hit.rest then run.depth = run.depth + 1 end
  run.pos, run.slot, run.awaiting = pos, hit.slot, nil
  -- on the Cursed Path every floor of the biome but the Warden's is cursed
  local path = run.cursed_biome == pos and hit.slot >= 1
  local cursing = advanced and (run.next_cursed or path) and hit.slot >= 1 and hit.slot < WARDEN_SLOT
  floor = {token = world.token, biome = pos, dungeon = hit.biome, slot = hit.slot, back = world.back_floor == true, scaled = {}, seen = 0,
           lair = hit.lair and world.back_floor ~= true, rest = hit.rest == true, cursed_path = path,
           entered = frame, swept = false, atla = nil,
           cursed = cursing or (not advanced and prev and prev.cursed) or false,
           curses = cursing and roll_curses() or (not advanced and prev and prev.curses) or {}}
  if advanced then run.next_cursed = false end
  if advanced and hit.slot == 1 then run.nine_lives = sig("xiao", 5) end
  floor.winded = {}
  set_guards()
  meta.best_depth = math.max(meta.best_depth, run.depth)
  local b = BIOMES[hit.biome] or biome_def(pos)
  local intro = hit.lair and "The Genie's Lair. Clear it; the Dark Genie waits behind the last door." or
      hit.rest and (b.name .. " Rest: a spring, Gaffer, and two ways on.") or
      hit.slot == WARDEN_SLOT and (b.name .. " Warden. Clear the floor to open the Warden's door.") or
      string.format("%s %d-%d.", b.name, pos, hit.slot)

  if floor.back then intro = intro .. " A Vault: brutal monsters, a Warden of its own, rich rewards." end
  if floor.cursed then
    local list = {}
    for _, c in ipairs(floor.curses) do list[#list + 1] = CURSES[c].name end
    intro = intro .. " Cursed: " .. table.concat(list, ", ") .. "."
  end
  if advanced and hit.slot == 2 and eternal("gaffer") > 0 then intro = intro .. " Gaffer's Wagon is here." end
  if hit.rest then REST.arrive() end
  -- Re-entering the dungeon (the launch, the next biome) loads Toan: switch back quietly, so the draft
  -- check has nothing to bounce. Not under the floor's entry scene, which would wait on Toan's motions for good:
  -- the tick asks again until the game lets it.
  local p = try(game.player.get)
  local keep = run.leader or run.drafted[1]
  if p and p.character ~= keep and not try(game.party.set_active, {id = keep}) then floor.switch_to = keep end
  if first then first_floor_setup() else toast(intro, floor.cursed and "curse" or nil) end
  if advanced and not hit.rest and hit.slot == 2 and (pos == 1 or pos == 3 or (eternal("golden") > 0 and (pos == 2 or pos == 4))) then
    draft_ally("GOLDEN ATLA")
  end
  if advanced and not first and not hit.rest then
    if eternal("feast") > 0 then
      local pl = try(game.player.get)
      if pl and pl.max_hp then try(game.player.heal, {amount = math.max(1, math.floor(pl.max_hp / 5))}) end
    end
    if hit.slot == 1 and eternal("helping") > 0 then try(game.items.give, {id = "chronicle:item:" .. ITEM.bread, count = 2}) end
    if hit.slot == 1 and eternal("unbreakable") > 0 then try(game.items.give, {id = "chronicle:item:" .. ITEM.auto_repair, count = 1}) end
  end
  -- The Genie's Mark: every third floor is cursed, chosen or not
  if advanced and eternal("mark") > 0 and (run.depth + 1) % 3 == 0 and hit.slot + 1 < WARDEN_SLOT then run.next_cursed = true end
  if advanced and hit.slot == 1 then cache_weapons() end
  LOOT.floor()
  MOVES.apply()
  save_meta()
  save_run()
  refresh()
end

-- Floor generation: cursed floors hold more and richer chests.
moonmod.on("game.dungeon.generating", function(e)
  if not run then return end
  local hit = floor_at(e.dungeon_id, e.floor_id)
  -- The floor may be built just after the run has arrived on it (and spent next_cursed).
  local arrived = floor and floor.cursed and floor.slot == (hit and hit.slot) and floor.dungeon == (hit and hit.biome)
  local rest = hit and hit.rest
  local cursing = hit and not rest and hit.slot < WARDEN_SLOT and (run.next_cursed or arrived or (run.cursed_biome == run.pos and hit.slot >= 1))
  local mods = cursing and {chests = 50, chest_value = 100} or {}
  if eternal("barren") > 0 and hit and hit.slot < WARDEN_SLOT then mods.chests = -100 end
  if eternal("crowded") > 0 then mods.monsters = 25 * eternal("crowded") end
  if eternal("sprawl") > 0 then mods.rooms = 30 * eternal("sprawl") end
  if eternal("hoard") > 0 then mods.chest_value = math.min(300, (mods.chest_value or 0) + 50) end
  -- The Rest floor: a hall with a healing spring and an antechamber with the Cursed Path's stairs; nothing to fight.
  if rest then mods = {chests = -100} end
  try(game.dungeons.set_modifiers, mods)
  try(game.dungeons.set_rest_room, {enabled = rest == true})
  -- Shortcut doors: dead ends loop back, locked from the far side; one a floor, one more per Sprawling Floors rank.
  try(game.dungeons.set_shortcuts, {count = hit and not rest and hit.slot < WARDEN_SLOT and math.min(3, 1 + eternal("sprawl")) or 0})
  -- Chest weapons: never one the party already holds, and often a stronger one, so there is always something to
  -- upgrade to; a few more chests are the large ones weapons come in.
  if hit then try(game.dungeons.set_weapon_drops, {unique = true, rare = 40, large_chests = 22}) end
  -- Vaults (back floors) are free: the stairs ask whether to go down instead of taking the gate key.
  if rest then
    -- the Rest floor's stairs are the Cursed Path: they lead on to the next biome, every floor of it cursed
    try(game.dungeons.set_backrooms, {free = true, stay = true, title = "TAKE THE CURSED PATH?",
        text = "Every floor of " .. BIOMES[hit.biome].name .. " before its Warden is cursed.",
        lines = {"Two curses on every floor.", "Richer chests, a cache each floor, a Warden that pays twice."}})
  elseif hit then try(game.dungeons.set_backrooms, {free = true, title = "ENTER THE VAULT?",
      text = "Enter at your own risk: brutal monsters, a Warden of its own, and rich rewards."}) end
  -- The Warden waits behind the exit gate's room, sealed until every monster outside it is dead; walking in shuts
  -- the doors behind you until it falls.
  try(game.dungeons.set_warden_room, {enabled = hit ~= nil and hit.slot == WARDEN_SLOT, lock_in = true})
  -- A door or jump only one character opens goes on the floor only for a character you have drafted.
  if hit then try(game.dungeons.set_character_blocks, {characters = run.drafted}) end
end)

-- Enemies ------------------------------------------------------------------------------------------------
local function drop_of(e)
  local d = (e.combat and e.combat.drop_item) or (e.definition and e.definition.drop_item)
  return tonumber(d)
end

-- Wardens are true bosses: base HP times x10 in the first biome rising to x100 in the fifth (scaled by the
-- warden_hp_scale setting). A Vault's own Warden has 40% of that.
local function warden_hp_mult()
  local table_ = {10, 20, 35, 60, 100}
  return (table_[math.min(#table_, run.pos)] or 100) * setting("warden_hp_scale", 100) / 100
end

local function enemy_hp_mult()
  local depth = run.depth + (eternal("deeper") > 0 and 5 or 0)
  local hp_mult = (1 + setting("depth_hp", 6) / 100 * math.max(0, depth - 1)) * shuffle_scale() * (1.25 ^ eternal("hardened"))
  if floor.cursed then hp_mult = hp_mult * setting("curse_hp", 160) / 100 end
  if floor.back then hp_mult = hp_mult * 2.5 end -- a Vault: enter at your own risk
  return hp_mult
end

local function scale_enemies(roster)
  local hp_mult = enemy_hp_mult()
  local abs_mult = abs_multiplier()
  local money_mult = 1 + (eternal("carts") > 0 and 0.4 or 0.2) * placed("cart")
  local defense_add = math.floor(run.depth / 2)
  for _, e in ipairs(roster) do
    local handle = e.entity_id or e.id
    local key = tostring(handle)
    if handle and e.revealed == true and not floor.scaled[key] then
      local hp = e.health and tonumber(e.health.maximum) or 0
      local combat = e.combat or {}
      if hp > 0 then
        -- The floor's toughest monster: the Warden grows out of one like it if the dungeon's boss doesn't come.
        local model = tonumber(e.native_model_id)
        if model and (not floor.toughest or hp > floor.toughest.hp) then
          local name = (e.definition and e.definition.name) or e.name
          floor.toughest = {model = model, hp = hp, name = type(name) == "string" and name ~= "" and name or nil}
        end
        -- A Vault's Warden is the first of its monsters to show itself (a Warden floor's waits in its room).
        local warden = not floor.warden and floor.back
        floor.extra = floor.extra or {}
        -- Genie's Champions: every other floor's key holder is a lesser Warden (twice the HP)
        local champion = not warden and eternal("champions") > 0 and (drop_of(e) or -1) >= 0
        local boss = warden_hp_mult() * 0.4
        local mult = hp_mult * (warden and boss or (champion and 2 or 1))
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
            try(game.entities.scale_set, {entity = handle, scale = floor.back and 1.7 or 1.8})
            local b = biome_def(run.pos)
            local name = (e.definition and e.definition.name) or e.name
            name = type(name) == "string" and name ~= "" and name or "The Warden"
            try(game.ui.boss_card, {kicker = floor.back and "THE VAULT'S KEEPER" or ("WARDEN OF " .. (b and b.name or "THE DEPTHS"):upper()):sub(1, 48),
                name = name:sub(1, 40), epithet = string.format("%d HP", request.max_hp), frames = 170})
            toast(floor.back and "The Vault's Warden awakens!" or "The Warden awakens!")
          end
        end
      end
    end
  end
end

-- Moonblade: the first hit on each enemy lands twice more (seen as its first drop from full health, after scaling).
local function moonblade(roster)
  if eternal("moonblade") == 0 then return end
  floor.struck = floor.struck or {}
  for _, e in ipairs(roster) do
    local handle = e.entity_id or e.id
    local key = tostring(handle)
    local now, full = e.health and tonumber(e.health.current) or 0, e.health and tonumber(e.health.maximum) or 0
    if handle and floor.scaled[key] and not floor.struck[key] and now > 0 and now < full then
      floor.struck[key] = true
      try(game.entities.set_stats, {entity = handle, hp = math.max(1, math.floor(now - 2 * (full - now)))})
    end
  end
end

-- The companion: the first drafted ally who isn't the active character comes out beside them. Switching to the
-- companion trades places: the character you were becomes the companion. It needs the Eternal tree's Companion and
-- the Companion setting, which is off by default (players found it got in the way).
local STANCES = {"target", "aggressive", "passive"}
local companion_out = nil -- what the engine was last asked for: "character/stance/scale"
local function update_companion(p)
  local want = nil
  if run and on_route() and companion_on() and p then
    local c = run.companion
    if not c or c == p.character or not contains(run.drafted, c) then
      c = nil
      for _, d in ipairs(run.drafted) do if d ~= p.character then c = d; break end end
      run.companion = c
    end
    if c then
      local stance = eternal("stances") > 0 and (meta.stance or "target") or "target"
      want = {character = c, stance = stance, damage_scale = eternal("keenpartner") > 0 and 1.25 or 1}
      -- Opar as the companion spits his blue glob at the target from range (and never transforms)
      if c == "opar" then want.shot = {cell = 8, size = 2.0} end
    end
  end
  local key = want and (want.character .. "/" .. want.stance .. "/" .. want.damage_scale .. (want.shot and "/shot" or "")) or "none"
  if key == companion_out then return end
  companion_out = key
  try(game.party.companion_set, want or {})
end

moonmod.on("game.companion.hit", function(e)
  if not on_route() then return end
  run.companion_target = e.entity
  -- Soul Bond: the companion's kills restore a little of your HP. The companion is there to help, so its kills
  -- never feed a weapon (the game gives a kill's ABS only to the weapon that struck it).
  if e.killed and eternal("soulbond") > 0 then
    local p = try(game.player.get)
    if p and (p.hp or 0) > 0 and p.max_hp and p.hp < p.max_hp then
      try(game.player.heal, {amount = math.max(1, math.floor(p.max_hp * 3 / 100))})
    end
  end
end)

-- Twin Strike: the player's hits on the companion's target land 10% harder.
moonmod.on("game.enemy_hit", function(e)
  if not on_route() or eternal("twinstrike") == 0 or not run.companion_target then return end
  if tostring(e.entity) == tostring(run.companion_target) and (tonumber(e.damage) or 0) >= 10 then
    try(game.combat.damage, {entity = e.entity, amount = math.floor(e.damage / 10)})
  end
end)

moonmod.on("game.dungeon.door_locked", function(e)
  if on_route() then toast("Locked. The " .. door_key_name(e.key) .. " is somewhere on the far side.") end
end)
moonmod.on("game.dungeon.door_opened", function(e)
  if on_route() then toast("The " .. door_key_name(e.key) .. " opens a shortcut.") end
end)

-- Twin Keys: on floors I to III a second monster carries the gate key too; the first key found is not enough.
local function twin_keys(roster)
  if eternal("twinkeys") == 0 or not floor or floor.slot >= WARDEN_SLOT or floor.second_key then return end
  for _, e in ipairs(roster) do
    local d = drop_of(e)
    if e.revealed == true and d and d >= 0 then floor.key_item = d end
  end
  if not floor.key_item then return end
  for _, e in ipairs(roster) do
    local handle = e.entity_id or e.id
    local d = drop_of(e)
    if e.revealed == true and floor.scaled[tostring(handle)] and not (d and d >= 0) then
      if try(game.entities.set_stats, {entity = handle, drop_item = floor.key_item}) then
        floor.second_key = handle
        toast("Twin Keys: two monsters carry this gate's key.")
      end
      return
    end
  end
end

moonmod.on("game.item_picked_up", function(e)
  if not on_route() or not floor or not floor.key_item or tonumber(e.native_item_no) ~= floor.key_item then return end
  if eternal("twinkeys") == 0 or floor.slot >= WARDEN_SLOT then return end
  floor.keys = (floor.keys or 0) + 1
  if floor.keys == 1 then
    try(game.items.remove, {id = e.id, count = 1})
    toast("One of two keys. The other is still out there.")
  else
    toast("Both keys found. The gate will open.")
  end
end)

-- The Wardens' spawning, defined further down: WARDENS.spawn(center), WARDENS.kin (a boss roaming a floor as a
-- regular monster) and WARDENS.genie_next (the Genie's next form, once the one before it has fallen: the Lair).
local WARDENS = {}
local function update_warden_bar()
  if not floor.warden or floor.warden_done then return end
  if floor.warden_fall then warden_cleared(); return end -- felled, fading out
  -- Every Warden on the floor (the key holder and any Twin Wardens) shares one bar.
  local current, max, alive = 0, 0, 0
  local list = {{entity = floor.warden, max = floor.warden_max}}
  for _, w in ipairs(floor.extra or {}) do list[#list + 1] = w end
  for _, w in ipairs(list) do
    local e = try(game.entities.get, w.entity)
    max = max + (w.max or 0)
    if (floor.fallen or {})[tostring(w.entity)] then
      -- felled (game.enemy_defeated): its handle reads expired from then on
    elseif e and e.status == "alive" then
      alive = alive + 1
      current = current + (e.health and tonumber(e.health.current) or 0)
    elseif not e or e.status ~= "dead" then
      return -- an expired handle: wait for the floor to settle
    end
  end
  if alive == 0 then
    if not WARDENS.genie_next() then warden_cleared() end
    return
  end
  try(game.render.bar_register, {id = "warden", label = floor.back and "VAULT WARDEN" or floor.lair and "DARK GENIE" or
      (#list > 1 and ("WARDENS " .. alive) or "WARDEN"),
      current = current, max = math.max(1, max)})
end

local function is_warden(entity)
  if not floor or not entity then return false end
  if tostring(entity) == tostring(floor.warden) then return true end
  for _, w in ipairs(floor.extra or {}) do if tostring(w.entity) == tostring(entity) then return true end end
  return false
end

-- The Warden appears in the middle of its room as the player walks in. With the boss_wardens chance it is the
-- dungeon's own boss, whose script works in its arena's coordinates: the engine centres that arena on the room
-- (Dran kept on the ground), and the boss brings its native cast. Otherwise the floor's toughest monster grows into
-- a Warden. Twin Wardens and the Warden's Court stand beside it. Returns false while the engine can't place them
-- yet (try again next tick).
do
  -- A boss fights with the cast its arena places beside it, in the slots by which their scripts name each other:
  -- the boss in slot 0, then `cast` from slot 1. The Ice Queen's spells are monsters of their own; the King's Curse
  -- rises from its coffin, which is what dies; Minotaur Joe drinks from his wine kegs.
  -- `tier` is the boss's place in the story (its dungeon, 1-5): its hits are made for a party that far along.
  local BOSSES = {
    dbc = {model = 78, name = "Dran", epithet = "Lord of the Divine Beast Cave", grounded = true, tier = 1, blow = 20, life = 737,
           scale = 0.65},
    wof = {model = 79, name = "Master Utan", epithet = "Elder of the Wise Owl Forest", tier = 2, blow = 45, life = 2065},
    ship = {model = 80, name = "Ice Queen", epithet = "Mistress of the Shipwreck", cast = {101, 76, 102, 103, 92, 104, 104, 104},
            tier = 3, blow = 74, life = 2065},
    temple = {model = 81, name = "King's Curse", epithet = "The Sun and Moon Temple's Shadow", cast = {82}, tier = 4, blow = 62, life = 5899},
    sea = {model = 83, name = "Minotaur Joe", epithet = "Brute of the Moon Sea", cast = {91, 91, 91}, tier = 5, blow = 125, life = 5899},
  }
  -- `blow` is a boss's heaviest native blow (or its spells', for the Ice Queen). The native bosses' blows grow unevenly
  -- (Dran 20, Minotaur Joe 125), so a boss hits as hard as the native boss whose place in the run it takes, by
  -- their blows: Joe as the first Warden hits like Dran, Dran as the last like Joe. The Lair keeps the last place's.
  -- The cast hits alike.
  -- `life` is a boss's native HP as the Warden table grows it in the first biome (Dran's is an eighth of Joe's): a
  -- boss gets the life of the one whose place it takes, so Joe as the first Warden is no sponge.
  local function story_place() return BOSSES[BIOMES[math.min(run.pos, #BIOMES)].key] end
  local function boss_damage(boss)
    local place = story_place()
    return clamp(place.blow / (boss.blow or place.blow), 0.15, 6)
  end
  local CAST_NAMES = {[76] = "Ice Arrow", [82] = "King's Curse", [91] = "Wine Keg", [92] = "Ice Aura", [101] = "Ice Barrier",
                      [102] = "Ice Prison", [103] = "Ice Meteor", [104] = "Ice Tornado",
                      [85] = "Genie's Hand", [86] = "Genie's Hand", [87] = "Genie's Light", [88] = "Genie's Wind",
                      [89] = "Genie's Beam", [90] = "Genie's Beam", [93] = "Genie's Shockwave", [105] = "Shade",
                      [107] = "Dark Pillar", [108] = "Dark Shockwave", [109] = "Dark Beam", [110] = "Dark Beam"}
  -- The Dark Genie's two forms, the finale in the Genie's Lair: the pink Genie (his casts by their native slots: the
  -- hands, light, wind, beam and shockwave) and his dark elemental form (shades, pillars, shockwaves and beam).
  -- `groups` are the helpers that come together (a pillar raises its shade; a beam's second half follows the first);
  -- `keep` always comes: the pink Genie's eye opens to blows only once both his hands are broken (each sets its
  -- script integer, 0 and 1, to -1 as it dies), and he waits on his beam's motion before he moves on. `hp` brings each
  -- form's own HP to the same footing. Its hits are made for the end of the story (`tier` 6).
  local GENIE = {
    pink = {model = 84, name = "Dark Genie", epithet = "The Wish-Granter's Shadow", tier = 6, blow = 85, hp = 1 / 5,
            cast = {[1] = 85, [2] = 86, [3] = 87, [4] = 88, [5] = 89, [6] = 90, [7] = 93},
            keep = {1, 2, 5, 6}, groups = {{3}, {4}, {7}}, hands = {[1] = 0, [2] = 1}, reach = 48},
    dark = {model = 106, name = "Dark Genie", epithet = "Darkness Unbound", tier = 6, blow = 85, hp = 1 / 10,
            cast = {[1] = 105, [2] = 105, [3] = 107, [4] = 107, [5] = 108, [6] = 108, [7] = 109, [8] = 110},
            keep = {}, groups = {{1, 3}, {2, 4}, {5}, {6}, {7, 8}}},
  }
  -- The fight's shape, rolled once a run: the pink Genie then his dark form, the other way round, or both at once
  -- with fewer helpers each. Each form brings a random share of its helpers (at least two of its groups).
  local function genie_roll()
    local shape = ({"pink_dark", "dark_pink", "both"})[math.random(3)]
    local share = shape == "both" and 40 or 70
    local plan = {shape = shape, forms = {}}
    for _, key in ipairs(shape == "dark_pink" and {"dark", "pink"} or {"pink", "dark"}) do
      local g, slots = GENIE[key], {}
      local order = {}
      for i in ipairs(g.groups) do order[i] = i end
      for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
      for n, i in ipairs(order) do
        if n <= 2 or math.random(100) <= share then
          for _, slot in ipairs(g.groups[i]) do slots[#slots + 1] = slot end
        end
      end
      for _, slot in ipairs(g.keep) do slots[#slots + 1] = slot end
      table.sort(slots)
      plan.forms[#plan.forms + 1] = {key = key, slots = slots}
    end
    return plan
  end
  local variants = {}
  local function variant(model, name)
    if variants[model] then return variants[model] end
    local r = try(game.characters.register, {id = "warden-" .. model, kind = "enemy", name = (name or "Warden"):sub(1, 30),
                                             template_monster_id = model})
    variants[model] = r and r.id or ("moonmod.roguelike:warden-" .. model)
    return variants[model]
  end
  local function place(model, name, at, hp_scale, opts)
    local s = try(game.characters.spawn, {character = variant(model, name), position = at, arena_origin = opts.origin,
                                          grounded = opts.grounded, arena_slot = opts.origin and 0 or nil})
    local handle = s and (s.entity_handle or s.id)
    if not handle then return nil end
    local base = s.stats and tonumber(s.stats.hp) or s.health and tonumber(s.health.maximum) or 100
    local hp = math.floor(clamp(base * hp_scale, 1, 1000000))
    local abs_mult = abs_multiplier()
    try(game.entities.set_stats, {entity = handle, max_hp = hp, hp = hp,
        defense = math.floor(clamp(((s.stats and tonumber(s.stats.defense)) or 0) * 1.5 + run.depth, 0, 32767)),
        reward_exp = math.floor(clamp(120 * run.pos * abs_mult, 0, 32767)),
        reward_money = math.floor(clamp(400 * run.pos, 0, 2147483647))})
    -- a story boss is hurt only by the heroes its story brought (the Ice Queen by Ruby alone): with hit_share every
    -- hero hurts each part of it as much as the hero it suits best, so any drafted party can win
    if opts.damage then try(game.entities.set_stats, {entity = handle, damage_scale = opts.damage, hit_share = opts.origin ~= nil}) end
    floor.scaled[tostring(handle)] = true
    return handle, hp
  end
  -- The rest of a boss's cast at `at`, its arena's centre: their own scripts take them to their places. A member
  -- that can't come leaves its part of the fight out. They keep their native stats and die with the boss.
  local function spawn_cast(boss, at, damage, slots)
    local handles = {} -- by native slot
    if not slots then
      slots = {}
      for n in ipairs(boss.cast or {}) do slots[n] = n end
    end
    for _, n in ipairs(slots) do
      local model = boss.cast[n]
      local s = model and try(game.characters.spawn, {character = variant(model, CAST_NAMES[model]), position = at,
                                                      arena_origin = at, grounded = boss.grounded, arena_slot = n})
      local h = s and (s.entity_handle or s.id)
      if h then
        handles[n] = h
        floor.scaled[tostring(h)] = true
        try(game.entities.set_stats, {entity = h, damage_scale = damage, hit_share = true})
      end
    end
    return handles
  end
  -- Boss-kin: on some floors (roaming_bosses, 25% by default) one of the dungeons' bosses roams as a regular monster,
  -- with its cast: 60-100% of its size and a modest HP pool, about four of the floor's toughest monster. Never on a
  -- Warden floor. It is put where an awake monster (the game wakes only those near the player) at least 260 units
  -- off already stands, so it starts in a room.
  local KIN = {BOSSES.dbc, BOSSES.wof, BOSSES.ship, BOSSES.temple, BOSSES.sea}
  WARDENS.kin = function(roster, player)
    if floor.kin ~= nil or floor.slot >= WARDEN_SLOT or frame - floor.entered < 240 or not floor.toughest then return end
    if math.random(100) > setting("roaming_bosses", 25) then floor.kin = false; return end
    local pp = player and player.position
    if not pp then return end
    local at
    for _, m in ipairs(roster) do
      local pos = m.position
      -- 260 units off; after 40 seconds on the floor with none that far, 120 will do
      local far = frame - floor.entered > 2400 and 120 or 260
      if pos and m.revealed == true and (pos.x - pp.x) ^ 2 + (pos.z - pp.z) ^ 2 > far * far then
        at = {x = pos.x + 20, y = pos.y or 0, z = pos.z + 20}
        break
      end
    end
    if not at then return end -- everyone is close: look again next tick
    local kin = KIN[math.random(#KIN)]
    local s, err = call(game.characters.spawn, {character = variant(kin.model, kin.name), position = at, arena_origin = at,
                                                grounded = kin.grounded, arena_slot = 0})
    if not s then
      if not errmsg(err):find("try again", 1, true) then
        floor.kin = false
        moonmod.log("warn", "boss-kin " .. kin.name .. " could not come: " .. errmsg(err))
      end
      return
    end
    local handle = s.entity_handle or s.id
    floor.kin = handle
    floor.scaled[tostring(handle)] = true
    local hp = math.floor(clamp(floor.toughest.hp * 4 * enemy_hp_mult(), 40, 1000000))
    try(game.entities.set_stats, {entity = handle, max_hp = hp, hp = hp,
        defense = math.floor(clamp(((s.stats and tonumber(s.stats.defense)) or 0) * 0.5 + run.depth, 0, 32767)),
        reward_exp = math.floor(clamp(40 * run.pos * abs_multiplier(), 0, 32767)),
        reward_money = math.floor(clamp(150 * run.pos, 0, 2147483647)),
        damage_scale = boss_damage(kin) * 0.75, hit_share = true})
    try(game.entities.scale_set, {entity = handle, scale = 0.6 + 0.4 * math.random()})
    spawn_cast(kin, at, boss_damage(kin) * 0.75)
    toast(kin.name .. " prowls this floor.")
  end
  -- One of the Genie's forms at `at`: the form, then its share of the helpers. Returns its handle and HP.
  local function spawn_form(form, at, hp_scale)
    local g = GENIE[form.key]
    local handle, hp = place(g.model, g.name, at, hp_scale * g.hp, {origin = at, damage = boss_damage(g)})
    if handle then
      -- the pink Genie's eye floats some 50 units over the floor, out of any blade's reach: widen it so a blow
      -- struck from beneath his face lands (it opens only once both hands are broken)
      if g.reach then try(game.entities.set_stats, {entity = handle, hit_reach = g.reach}) end
      local cast = spawn_cast(g, at, boss_damage(g), form.slots)
      for n, index in pairs(g.hands or {}) do
        if cast[n] then
          floor.genie_hands = floor.genie_hands or {}
          floor.genie_hands[#floor.genie_hands + 1] = {entity = cast[n], index = index, boss = handle}
        end
      end
    end
    return handle, hp
  end
  -- A broken hand tells the pink Genie by its script integer (-1), which he reads before each blow he orders it to
  -- strike. A hand broken outside its own blow (poison, a splash, a chain of thunder) may be ordered again over its
  -- -1, and his eye would never open: while he stands, each broken hand's integer is held at -1.
  WARDENS.genie_tick = function()
    if not (floor.lair and floor.genie_hands) or frame % 15 ~= 0 then return end
    local fallen = floor.fallen or {}
    for _, hand in ipairs(floor.genie_hands) do
      if fallen[tostring(hand.entity)] and not fallen[tostring(hand.boss)] then
        try(game.entities.script_int_set, {entity = hand.boss, index = hand.index, value = -1})
      end
    end
  end
  local function genie_card(form, kicker)
    local g = GENIE[form.key]
    try(game.ui.boss_card, {kicker = kicker, name = g.name, epithet = g.epithet, frames = 170})
  end
  local function spawn_genie(center)
    run.genie = run.genie or genie_roll()
    local plan = run.genie
    local mult = enemy_hp_mult() * warden_hp_mult()
    floor.extra, floor.genie_at = {}, 1
    if plan.shape == "both" then
      -- Side by side, each its own arena (its own script integers): two thirds of the HP each.
      local a = {x = center.x - 45, y = center.y or 0, z = center.z}
      local handle, hp = spawn_form(plan.forms[1], a, mult * 2 / 3)
      if not handle then return false end
      floor.warden, floor.warden_max = handle, hp
      local h2, hp2 = spawn_form(plan.forms[2], {x = center.x + 45, y = center.y or 0, z = center.z}, mult * 2 / 3)
      if h2 then floor.extra[1] = {entity = h2, max = hp2} end
      floor.genie_at = #plan.forms
      try(game.ui.boss_card, {kicker = "THE GENIE'S LAIR", name = "Dark Genie", epithet = "Both his faces at once", frames = 170})
      toast("The doors slam shut. The Dark Genie comes in both his forms!")
    else
      local handle, hp = spawn_form(plan.forms[1], {x = center.x, y = center.y or 0, z = center.z}, mult)
      if not handle then return false end
      floor.warden, floor.warden_max = handle, hp
      genie_card(plan.forms[1], "THE GENIE'S LAIR")
      toast("The doors slam shut. The Dark Genie awakens!")
    end
    floor.genie_center = {x = center.x, y = center.y or 0, z = center.z}
    save_run()
    return true
  end
  -- The form before has fallen: once it has faded, the next rises in its place. False when there is none (or the
  -- engine can't place it yet: asked again next tick).
  WARDENS.genie_next = function()
    local plan = run.genie
    if not (floor.lair and plan and floor.genie_at and floor.genie_at < #plan.forms) then return false end
    floor.genie_rise = floor.genie_rise or frame + 150
    if frame < floor.genie_rise then return true end
    local form = plan.forms[floor.genie_at + 1]
    local handle, hp = spawn_form(form, floor.genie_center, enemy_hp_mult() * warden_hp_mult())
    if not handle then return true end
    floor.genie_at, floor.genie_rise = floor.genie_at + 1, nil
    floor.warden, floor.warden_max, floor.extra = handle, hp, {}
    floor.fallen = {}
    genie_card(form, form.key == "dark" and "HIS TRUE FORM RISES" or "THE GENIE REFORMS")
    toast(form.key == "dark" and "The Genie's body bursts... and darkness itself rises!" or
          "The darkness gathers... into the Genie once more!")
    return true
  end
  WARDENS.spawn = function(center)
    if floor.lair then return spawn_genie(center) end
    local b = biome_def(run.pos)
    if floor.warden_boss == nil then
      local boss = BOSSES[b and b.key or ""]
      floor.warden_boss = (boss and math.random(100) <= setting("boss_wardens", 50)) and b.key or false
    end
    local boss = floor.warden_boss and BOSSES[floor.warden_boss]
    local toughest = floor.toughest
    if not boss and not toughest then warden_cleared(); return true end -- nothing to grow a Warden from
    local mult = enemy_hp_mult() * warden_hp_mult()
    local at = {x = center.x, y = center.y or 0, z = center.z}
    local handle, hp, name
    if boss then
      -- a boss already has a boss's HP (as the boss whose place it takes, which stands in for the shuffled dungeon's
      -- easing): a quarter of the Warden table on top of it
      handle, hp = place(boss.model, boss.name, at, mult / shuffle_scale() / 4 * story_place().life / boss.life,
                         {origin = at, grounded = boss.grounded, damage = boss_damage(boss)})
      if handle then spawn_cast(boss, at, boss_damage(boss)) end
      -- Dran's story arena dwarfs a Warden room, where he would fill the camera: he comes smaller
      if handle and boss.scale then try(game.entities.scale_set, {entity = handle, scale = boss.scale}) end
      name = boss.name
    else
      handle, hp = place(toughest.model, toughest.name, at, mult, {})
      name = toughest.name or "The Warden"
      if handle then try(game.entities.scale_set, {entity = handle, scale = 1.8}) end
    end
    if not handle then return false end
    floor.warden, floor.warden_max = handle, hp
    -- Twin Wardens adds one or two; Warden's Court makes the last Warden floor a court of five.
    floor.extra = {}
    local court = (eternal("court") > 0 and run.pos >= #run.biomes) and 4 or 0
    local twins = math.max(eternal("twinwardens"), court)
    for n = 1, toughest and twins or 0 do
      local angle = n * 2 * math.pi / (twins + 1)
      local h, max = place(toughest.model, toughest.name, {x = at.x + 70 * math.cos(angle), y = at.y, z = at.z + 70 * math.sin(angle)}, mult, {})
      if h then
        floor.extra[#floor.extra + 1] = {entity = h, max = max}
        try(game.entities.scale_set, {entity = h, scale = 1.6})
      end
    end
    try(game.ui.boss_card, {kicker = ("WARDEN OF " .. (b and b.name or "THE DEPTHS"):upper()):sub(1, 48), name = name:sub(1, 40),
        epithet = boss and boss.epithet or string.format("%d HP", hp), frames = 170})
    toast(#floor.extra > 0 and (#floor.extra == 4 and "The Warden's Court is gathered!" or "The Warden is not alone!")
          or "The doors slam shut. The Warden awakens!")
    save_run()
    return true
  end
end

moonmod.on("game.dungeon.warden_room", function(e)
  if not on_route() or floor.back or floor.slot ~= WARDEN_SLOT or floor.warden_done then return end
  if e.state == "open" then
    toast("The last monster falls. The Warden's door grinds open.")
  elseif e.state == "entered" and not floor.warden and type(e.center) == "table" then
    floor.warden_at = {x = tonumber(e.center.x) or 0, y = tonumber(e.center.y) or 0, z = tonumber(e.center.z) or 0}
  end
end)

moonmod.on("game.enemy_hit", function(e)
  if not on_route() then return end
  LOOT.on_hit(e)
  local who = type(e.attacker) == "number" and ROSTER[e.attacker + 1] or e.attacker
  -- Moonsinger: Ruby's hits heal her 1 HP, at most once a second.
  if who == "ruby" and sig("ruby", 4) and frame - (run.sung or -60) >= 60 then
    run.sung = frame
    try(game.player.heal, {amount = 1, character = "ruby"})
  end
  if not e.charged then return end
  -- Lightning Fang: Toan's charged hits stun.
  if who == "toan" and sig("toan", 2) then try(game.combat.status_add, {entity = e.entity, status = "stop", duration_frames = 60}) end
  if who == "goro" then
    -- Mountain's Might: a charged swing staggers a Warden.
    if sig("goro", 5) and is_warden(e.entity) then try(game.combat.status_add, {entity = e.entity, status = "stop", duration_frames = 90}) end
    -- Ground Pound: half the swing's damage to the other enemies close by (once per swing).
    if sig("goro", 2) and frame - (run.pounded or -45) >= 45 and (tonumber(e.damage) or 0) >= 2 then
      run.pounded = frame
      local p = try(game.player.get)
      local at = p and p.position
      local near = at and try(game.physics.query, {shape = "sphere", center = {x = at.x, y = at.y, z = at.z}, radius = 90})
      for _, m in ipairs(near and near.matches or {}) do
        if tostring(m.entity) ~= tostring(e.entity) then try(game.combat.damage, {entity = m.entity, amount = math.floor(e.damage / 2)}) end
      end
    end
  end
end)

-- Opar's kit (MOVES above): the Tongue Lash's first hit yanks the enemy it caught in to him, and the Croak stuns what
-- it reaches. game.player.move says which move is playing; its hits arrive as enemy_hit within the move.
moonmod.on("game.player.move", function(e)
  local id = tostring(e and e.id or ""):gsub("^.*:", "")
  FORM.kit.move, FORM.kit.since, FORM.kit.pulled, FORM.kit.splashed = id, frame, nil, nil
  if id == "opar_jump_slam" and not FORM.active then FORM.pending = frame end
  if id == "opar_frog_hop" and sig("opar", 2) then FORM.puddle_at = frame + 24 end -- Bog Hop, as he lands
end)

-- The Jump Slam a step a frame (FORM above). Each change waits for the game to let the model change (the leap, then
-- the big slam, must have let go of him). A new floor gives every character his own model back (the engine), so one
-- cut short there ends quietly; so does one he is switched out of.
function FORM.smoke(p, scale)
  if p and p.position then
    try(game.effects.burst, {kind = "smoke", position = {x = p.position.x, y = p.position.y + 8, z = p.position.z}, scale = scale})
  end
end
function FORM.finish(p)
  if not try(game.player.form_clear) then return false end
  local sooner = ((LOOT.opar_staff() or {}).key == "moonpearl" and 1200 or 0) + (sig("opar", 5) and 1800 or 0)
  if sig("opar", 4) then -- Old Toad
    try(game.player.heal, {amount = math.max(1, math.floor((tonumber(p and p.max_hp) or 90) / 4)), character = "opar"})
  end
  FORM.active, FORM.slammed, FORM.ready_at, FORM.cooling = false, false, frame + FORM.COOLDOWN - sooner, true
  FORM.smoke(p, 0.9)
  MOVES.apply()
  return true
end
function FORM.tick(p)
  if FORM.puddle_at and frame >= FORM.puddle_at then
    FORM.puddle_at = nil
    local at = p.position
    if at then
      try(game.effects.burst, {kind = "heal", position = {x = at.x, y = at.y + 2, z = at.z}, scale = 1.6})
      local near = try(game.physics.query, {shape = "sphere", center = {x = at.x, y = at.y, z = at.z}, radius = 70})
      for _, m in ipairs(near and near.matches or {}) do
        try(game.combat.status_add, {entity = m.entity, status = "slow", duration_frames = 240})
        try(game.entities.tint, {entity = m.entity, color = {r = 110, g = 170, b = 120}, frames = 240})
      end
    end
  end
  if FORM.pending and not FORM.active then
    -- the leap is over: the cloud, and he is the monster, his only move the big slam
    if p.character ~= "opar" or frame - FORM.pending > 300 then FORM.pending = nil; return end
    if try(game.player.form_set, {pack = FORM.PACK, frames = FORM.FRAMES, scale = FORM.SCALE}) then
      FORM.pending, FORM.active, FORM.since, FORM.slammed = nil, true, frame, false
      FORM.smoke(p, 1.2)
      MOVES.apply()
    end
  elseif FORM.active and not FORM.slammed and p.character == "opar" and frame - FORM.since < 120 then
    FORM.slammed = try(game.player.move_play, {id = "opar_form_slam"}) ~= nil
  elseif FORM.active then
    FORM.finish(p) -- once the slam has let go of him (or it never started)
  elseif FORM.cooling and frame >= FORM.ready_at then
    FORM.cooling = false
    MOVES.apply()
  end
end
moonmod.on("game.enemy_hit", function(e)
  if not on_route() or not FORM.kit.move or frame - (FORM.kit.since or 0) > 60 then return end
  if FORM.kit.move == "opar_tongue_lash" and frame - FORM.kit.since <= 30 and not FORM.kit.pulled then
    FORM.kit.pulled = true
    local p = try(game.player.get)
    local m = try(game.entities.get, e.entity)
    local at, me = m and m.position, p and p.position
    if at and me then
      try(game.entities.knockback, {entity = e.entity, direction = {x = me.x - at.x, z = me.z - at.z},
        speed = math.min(30, math.max(8, math.sqrt((me.x - at.x) ^ 2 + (me.z - at.z) ^ 2) * 0.22))})
    end
  elseif FORM.kit.move == "opar_croak" then
    try(game.combat.status_add, {entity = e.entity, status = "stop", duration_frames = 90})
    try(game.entities.tint, {entity = e.entity, color = {r = 170, g = 230, b = 120}, frames = 90})
  end
end)

moonmod.on("game.enemy_defeated", function(e)
  if not on_route() then return end
  LOOT.on_kill(e)
  run.kills = run.kills + 1
  local exp = tonumber(e.reward_exp) or 0
  local p = try(game.player.get)
  if exp > 0 then share_abs(exp, p and p.character) end
  if eternal("luckyfind") > 0 and math.random(100) <= 5 then earn_shards(1) end
  if floor.warden and e.entity then
    floor.fallen = floor.fallen or {}
    floor.fallen[tostring(e.entity)] = true
    if tostring(e.entity) == tostring(floor.warden) and #(floor.extra or {}) == 0 and not WARDENS.genie_next() then warden_cleared() end
  end
end)

-- One weapon each -------------------------------------------------------------------------------------------
-- Each character carries one weapon for the whole run. A found weapon opens a choice: keep the one in hand or
-- take the new one; the other is absorbed into the keeper (a quarter of its attack, endurance, speed, magic and
-- elements). A weapon for someone outside the draft is absorbed into the active character's weapon. A weapon
-- that breaks ends the run.
local function absorb_share() return eternal("synth") >= 2 and 0.45 or (eternal("synth") >= 1 and 0.35 or 0.25) end
local STAT_KEYS = {"attack", "endurance", "speed", "magic"}
local BROKEN = {[257] = true, [299] = true, [314] = true, [331] = true, [347] = true, [363] = true} -- the broken starters


-- What `into` becomes after absorbing `from`.
local function absorbed(into, from)
  local out = {elem = {}}
  for _, k in ipairs(STAT_KEYS) do
    out[k] = math.floor(clamp((tonumber(into.stats[k]) or 0) + (tonumber(from.stats[k]) or 0) * absorb_share(), 0, 32767))
  end
  for e = 1, 5 do
    out.elem[e] = math.floor(clamp((tonumber(into.elements[e]) or 0) + (tonumber(from.elements[e]) or 0) * absorb_share(), 0, 127))
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

-- The weapon choice and Blessed Choice's pick are the engine's choice panel (ui.choice_open): the dungeon
-- pauses on cards side by side until the player takes one. A panel that can't open yet (another is up, or play
-- isn't ready) is tried again each tick.
local show_choice
do
local function weapon_name(id)
  local w = try(game.weapons.get, id)
  return type(w) == "table" and type(w.name) == "string" and w.name ~= "" and w.name or "Weapon"
end

local function stat_line(label, now, after)
  local gain = after - now
  return {text = string.format("%s %d%s", label, now, gain > 0 and string.format("  (+%d)", gain) or ""), tone = gain > 0 and "good" or nil}
end

local function weapon_card(tag, w, after)
  local d = w.stats
  return LOOT.card(choice.character, w, {title = weapon_name(w.id), subtitle = string.format("%s  |  LV %d", tag, w.level), lines = {
    stat_line("ATK", tonumber(d.attack) or 0, after.attack),
    stat_line("MAG", tonumber(d.magic) or 0, after.magic),
    stat_line("END", tonumber(d.endurance) or 0, after.endurance),
    stat_line("SPD", tonumber(d.speed) or 0, after.speed),
    {text = string.format("DUR %d/%d", math.floor(tonumber(d.durability_current) or 0), math.floor(tonumber(d.durability) or 0)), tone = "dim"},
  }})
end

show_choice = function()
  if choice.shown then return end
  local k, t = choice.keep, choice.take
  local ok = call(game.ui.choice_open, {id = "weapon", title = "ONE WEAPON FOR " .. choice.character:upper(),
      subtitle = string.format("The one you leave melts into the one you keep (%d%% of its stats).", math.floor(absorb_share() * 100)),
      options = {weapon_card("In hand", k, absorbed(k, t)), weapon_card("Found", t, absorbed(t, k))}})
  if ok then choice.shown = true end
end
end

local function open_choice(character, keep, take)
  choice = {character = character, keep = keep, take = take, pick = 1}
  refresh() -- hides the HUD line while the choice is up
  show_choice()
end

local function close_choice()
  choice = nil
  refresh()
end

local function confirm_choice()
  local c, k, t = choice.character, choice.keep, choice.take
  if choice.pick == 2 then
    local ok, err = call(game.weapons.equip, {id = t.id, character = c, slot = t.slot})
    if not ok then toast("Can't change weapons right now; kept the one in hand.") choice.pick = 1 else k, t = t, k end
  end
  local s = absorb(c, k, c, t)
  LOOT.forget(c, t.slot, t.id)
  LOOT.style(c, k.slot, k.id)
  run.weapons[c] = {id = k.id, slot = k.slot}
  save_run()
  toast(string.format("%s %s the %s weapon. ATK %d, MAG %d, END %d.", title(c), choice.pick == 2 and "takes" or "keeps",
      choice.pick == 2 and "found" or "held", s.attack, s.magic, s.endurance))
  close_choice()
end

local function show_offer()
  if offer.shown then return end
  local options = {}
  for _, id in ipairs(offer.ids) do options[#options + 1] = {title = BLESSINGS[id].name, lines = {BLESSINGS[id].text:gsub("^%l", string.upper) .. "."}} end
  if call(game.ui.choice_open, {id = "blessing", title = "PICK A BLESSING", subtitle = "It lasts for the whole run.", options = options}) then
    offer.shown = true
  end
end

open_offer = function(ids)
  offer = {ids = ids, pick = 1}
  refresh()
  show_offer()
end

local function confirm_offer()
  local id, more = offer.ids[offer.pick] or offer.ids[1], offer.more or 0
  offer = nil
  run.blessings[#run.blessings + 1] = id
  save_run()
  toast("Blessing: " .. BLESSINGS[id].name .. ". " .. BLESSINGS[id].text:gsub("^%l", string.upper) .. ".")
  apply_effects()
  refresh()
  for _ = 1, more do bless("Blessed Choice", {start = true}) end
end

moonmod.on("ui.choice_made", function(e)
  if e.id == "weapon" and choice then
    choice.pick = tonumber(e.index) == 2 and 2 or 1
    confirm_choice()
  elseif e.id == "blessing" and offer then
    offer.pick = tonumber(e.index) or 1
    confirm_offer()
  end
end)

-- Totem Guard: a ward turns aside one hit on Ungaga (checked every frame), then recharges for 15 seconds.
local function totem_guard(p)
  if p.character ~= "ungaga" or not sig("ungaga", 2) or (p.hp or 0) <= 0 then run.ungaga_hp = nil; return end
  local was = run.ungaga_hp
  if was and p.hp < was and frame >= (run.ward_at or 0) then
    run.ward_at = frame + 900
    try(game.player.heal, {amount = was - p.hp})
    p.hp = was
  end
  run.ungaga_hp = p.hp
end

local function poll_choice()
  if offer then show_offer() return end
  if choice then show_choice() end
end

local found_weapon
moonmod.on("game.item_picked_up", function(e)
  if not on_route() or e.kind ~= "weapon" then return end
  local character = type(e.character) == "number" and ROSTER[e.character + 1] or e.character
  if type(character) ~= "string" or type(e.slot) ~= "number" then return end
  found_weapon(character, e.id, e.slot)
end)

-- A weapon that came to the party (a chest, or Gaffer): pre-leveled, then the choice (or absorbed, if it belongs to
-- someone outside the draft). The choice panel shows its levels, so no notice is needed for them.
found_weapon = function(character, id, slot)
  if setting("preroll_weapons", true) then
    local selector = {id = id, character = character, slot = slot}
    local roll = math.random(100)
    local levels = roll <= 10 and 4 or (roll <= 30 and 3 or (roll <= 60 and 2 or 1))
    level_up(selector, levels)
    insert_attachments(selector, (math.random(100) <= 35 and 2 or 1) + (eternal("socket") > 0 and 1 or 0))
  end
  id, slot = LOOT.roll(character, id, slot)
  local e = {id = id, slot = slot}
  local found = weapon_info(e.id, character, e.slot)
  if not found then return end
  if choice or not contains(run.drafted, character) then
    local p = try(game.player.get)
    local w = p and p.weapon
    local into = w and w.id and weapon_info(w.id, p.character, w.slot)
    if not into then return end
    local s = absorb(p.character, into, character, found)
    LOOT.forget(character, found.slot, found.id)
    toast(string.format("%s's weapon was absorbed into %s's. ATK %d, MAG %d.", title(character), title(p.character), s.attack, s.magic))
    return
  end
  local held = equipped_weapon(character)
  local keep = held and weapon_info(held.id, character, held.slot)
  if not keep or keep.slot == found.slot then return end
  open_choice(character, keep, found)
end
LOOT.found = found_weapon

-- A broken weapon ends the run.
local function check_break(p)
  local w = p.weapon
  if run.broken or not w or choice then return end
  if not (BROKEN[tonumber(w.item_no) or 0] or (tonumber(w.durability) or 1) <= 0) then return end
  run.broken = true
  save_run()
  toast(title(p.character) .. "'s weapon broke! The run is over.")
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
      toast(title(p.character) .. " is not drafted. Back to " .. title(c) .. ".")
      return
    end
  end
end

-- Cursed Gate toggle -------------------------------------------------------------------------------------
local function toggle_curse()
  if not on_route() then toast("The Cursed Gate works on Gauntlet floors."); return end
  if run.slot == WARDEN_SLOT - 1 then toast("The Warden's floor can't be cursed.", "curse"); return end
  if floor.rest then toast("Take the stairs in the side room for the Cursed Path.", "curse"); return end
  if run.cursed_biome == run.pos then toast("You walk the Cursed Path: every floor here is cursed already.", "curse"); return end
  run.next_cursed = not run.next_cursed
  if run.next_cursed then toast("Next floor is cursed. Survive it for a Miracle cache.", "curse")
  else toast("The curse is lifted. The next floor is normal.") end
  save_run()
  refresh()
end
local _, bind_err = call(game.input.bind, {id = "curse_key", keys = {setting("curse_key", "G")}})
if bind_err then moonmod.log("warn", "bind curse_key: " .. errmsg(bind_err)) end
call(game.input.bind, {id = "curse_pad_l1", keys = {"Gamepad:leftshoulder"}})
call(game.input.bind, {id = "curse_pad_back", keys = {"Gamepad:back"}})
-- The HUD's cache chest: our own art, under a game path the engine draws HUD icons from.
call(game.resources.override, {path = "resources/hud/cache.png", game_path = HUD_CACHE_IMAGE})
-- Opar's pack and portrait: game paths no retail file has, which his registration names. He takes engine index 6
-- (the first past the six) and starts as Ruby's health with a tenth less defence (docs/OPAR_PLAN.md).
call(game.resources.override, {path = "resources/opar/c07d.chr", game_path = "dun/mainchara/c07d.chr"})
-- his portrait: his face in the round medallion the six have (art/opar/make_medallion.py, from face.png)
call(game.resources.override, {path = "resources/opar/medallion.png", game_path = "dun/mainchara/c07d_face.png"})
call(game.resources.override, {path = "resources/opar/c07f.chr", game_path = "dun/mainchara/c07f.chr"})
-- his model in the item menu, beside his status (art/opar/make_menu_pack.py), as the six have theirs
call(game.resources.override, {path = "resources/opar/c07model.pak", game_path = "commenu/dungeon/c07model.pak"})
-- his voice: croaks for his voice cues in place of Toan's (art/opar/make_voice.py from CC0 frog sounds,
-- art/opar/sounds/CREDITS.md); 106 is 100 plus his character index
call(game.resources.override, {path = "resources/opar/voice106.snd", game_path = "sound/voice/voice106.snd"})
do
  local registered = call(game.characters.register_playable, {id = "opar", name = "Opar", pack = "dun/mainchara/c07d.chr",
    portrait = "dun/mainchara/c07d_face.png", title = "Moon Sea Frog Mage", fights_as = ROSTER.fights_as.opar, hp = 90,
    defense = 21})
  ROSTER.registered = type(registered) == "table" and registered.character_id == 6
  -- his staffs (LOOT.STAFFS), only with him: their models and icons (art/opar/make_staff_icons.py) and definitions
  if ROSTER.registered then
    for _, st in ipairs(LOOT.STAFFS) do
      call(game.resources.override, {path = "resources/opar/" .. st.stem .. ".chr", game_path = "commenu/weapon/" .. st.stem .. ".chr"})
      call(game.resources.override, {path = "resources/opar/" .. st.stem .. "_icon.png", game_path = "icons/" .. st.stem .. "_icon.png"})
      local reg = call(game.weapons.register, {id = "opar_" .. st.key, name = st.name, template_weapon = 262, owner = "opar",
        model = st.stem, icon = st.stem .. "_icon", stats = {attack = st.attack, durability = st.durability},
        description = {st.about, st.own}, menu_scale = 0.7})  -- made 1.45x a sword's size, so shrunk to fit the menu
      st.id = type(reg) == "table" and reg.id or nil
    end
  end
end
-- The shortcut doors' keys, each drawn in the colour its door is lit with (tools/roguelike/make_keys.ps1). Only a
-- floor with more than one lock colours its doors (the first stays native), so only those keys take the coloured
-- art; every other key keeps the game's own icon.
local refresh_key_icons
do
local KEY_ART = {[216] = "key_bone", [217] = "key_moustache", [218] = "key_shipcabin", [219] = "key_stone",
                 [220] = "key_handle", [221] = "key_pitchdark", [222] = "key_silver"}
local key_art_ready = {}
for item, stem in pairs(KEY_ART) do
  key_art_ready[item] = call(game.resources.override, {path = "resources/keys/" .. stem .. ".png", game_path = "icons/" .. stem .. ".png"}) and true
end
refresh_key_icons = function()
  local got = try(game.dungeons.shortcuts_get)
  local coloured = {}
  for i, door in ipairs(got and got.doors or {}) do
    if i > 1 then coloured[tonumber(door.key_item) or 0] = true end
  end
  for item, stem in pairs(KEY_ART) do
    if coloured[item] and key_art_ready[item] then try(game.items.icon_set, {id = "chronicle:item:" .. item, icon = stem})
    else try(game.items.icon_set, {id = "chronicle:item:" .. item}) end
  end
end
end
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
  -- A weapon choice or a blessing pick still open (a Warden's prize) holds the run here until it's made: moving on
  -- first lost the prize. Victory's end waits the same way.
  if choice or offer then
    t.at = frame + 30
    return
  end
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
    if run then run.shuffle_to = nil end
    toast("The run could not move on. Take the exit to leave.")
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
    if p then check_break(p); totem_guard(p); FORM.tick(p) end
  end
  if frame % 15 ~= 0 then return end
  local session = try(game.session.get)
  if not (session and session.kind == "sandbox" and session.owner == ID) then return end
  watch_floor()
  if not run or not on_route() then return end
  local p = try(game.player.get)
  if p then
    if p.character == "opar" then
      local held = (p.weapon and LOOT.staff_of(p.weapon.id) or {}).key
      if held ~= LOOT.held_staff then LOOT.held_staff = held; MOVES.apply() end
    end
    -- not while the run moves on: the native entrance loads Toan for a moment, and arrival switches back quietly
    -- (once its scene lets it)
    if floor.switch_to then
      if p.character == floor.switch_to or try(game.party.set_active, {id = floor.switch_to}) then floor.switch_to = nil end
    elseif frame % 60 == 0 and not pending_transition and not run.awaiting then
      enforce_draft(p)
    end
    if p.weapon and p.weapon.id then run.weapons[p.character] = {id = p.weapon.id, slot = p.weapon.slot} end
    -- the run menu's Party tab marks the leader: rebuild it when the leader changes
    if contains(run.drafted, p.character) and run.leader ~= p.character then run.leader = p.character; update_menu() end
    local regen = placed("tree") + 2 * bp("mender")
    if regen > 0 and frame % (eternal("trees") > 0 and 90 or 180) == 0 and (p.hp or 0) > 0 and p.hp < p.max_hp then try(game.player.heal, {amount = regen}) end
    -- Rally and Relay: a switch heals the new character and gives a moment of invincibility
    if run.last_active and run.last_active ~= p.character and contains(run.drafted, p.character) then
      if eternal("rally") > 0 and p.max_hp then try(game.player.heal, {amount = math.max(1, math.floor(p.max_hp / 10))}) end
      if eternal("relay") > 0 then try(game.player.invincible, {frames = 180}) end
    end
    if run.last_active ~= p.character then
      if run.companion == p.character then run.companion = run.last_active end
      run.last_active = p.character
      apply_effects()
    end
    update_companion(p)
    -- Shaman: Ungaga regains 3% HP every 5 seconds.
    if p.character == "ungaga" and sig("ungaga", 4) and frame % 300 == 0 and (p.hp or 0) > 0 and p.max_hp and p.hp < p.max_hp then
      try(game.player.heal, {amount = math.max(1, math.floor(p.max_hp * 3 / 100))})
    end
    if frame % 60 == 0 and (eternal("laststand") > 0 or eternal("grip") > 0) then apply_effects() end
  end
  local result = try(game.entities.query, {type = "monster"})
  scale_enemies(result and result.entities or {})
  moonblade(result and result.entities or {})
  twin_keys(result and result.entities or {})
  if frame % 30 == 0 then WARDENS.kin(result and result.entities or {}, try(game.player.get)) end
  update_warden_bar()
  WARDENS.genie_tick()
  LOOT.tick(try(game.player.get))
  if floor.warden_at and not floor.warden and not floor.warden_done and WARDENS.spawn(floor.warden_at) then floor.warden_at = nil end
  -- The Lair is steeped in the Genie's dark: violet fog over the dungeon's own, once the floor's script has set its own
  -- (and again a little later, in case it set it late).
  if floor.lair and (floor.lit or 0) < 2 and frame - floor.entered > ((floor.lit or 0) == 0 and 60 or 240) then
    floor.lit = (floor.lit or 0) + 1
    try(game.dungeons.lighting_set, {side = "both", fog = {near = 120, far = 900, r = 90, g = 30, b = 120},
        background = {r = 25, g = 5, b = 40}, ambient = {r = 110, g = 80, b = 140}})
  end
  if not floor.key_icons and frame - floor.entered > 30 then floor.key_icons = true; refresh_key_icons() end
  if floor.rest then REST.tick(p) end
  if eternal("partner") > 0 and not floor.gaffer and frame - floor.entered > 90 then gaffer_arrive() end
  if frame % 60 == 0 then poll_atla() end
  if frame - floor.entered > 180 and not floor.swept then
    local combat = try(game.combat.get)
    local alive = combat and tonumber(combat.remaining)
    if alive then floor.seen = math.max(floor.seen, alive) end
    if alive and floor.seen > 0 and alive == 0 then
      floor.swept = true
      if floor.slot == WARDEN_SLOT and not floor.back then
        -- The sealed room opens now (game.dungeon.warden_room); a floor without one has its Warden come out here.
        local room = try(game.dungeons.warden_room_get)
        local p = try(game.player.get)
        if not floor.warden and (not room or room.state == "none") and p and p.position then
          floor.warden_at = {x = p.position.x, y = p.position.y, z = p.position.z + 60}
        end
      elseif floor.slot == WARDEN_SLOT and not floor.warden then warden_cleared()
      else toast("Floor swept! An extra Diorama tile awaits."); gaffer_arrive() end
    end
  end
end)

-- Diorama placement and Eternal purchases from the Journal page / Skills tab ---------------------------
local function place_tile(node)
  if not run then toast("Tiles are placed during a run."); return end
  if (tonumber(run.stock[node]) or 0) < 1 then toast("No " .. TILE[node].title .. " tiles in stock."); return end
  if placed_total() >= plots() then toast("The Diorama is full (" .. plots() .. " plots). Clear it to rearrange."); return end
  run.stock[node] = run.stock[node] - 1
  run.diorama[node] = placed(node) + 1
  try(game.skills.set_rank, {id = node_id("diorama", node), rank = run.diorama[node]})
  toast(TILE[node].title .. " placed on the Diorama (" .. placed_total() .. " of " .. plots() .. ").")
  save_run()
  refresh()
end

local function clear_diorama()
  if not run then toast("No run is under way."); return end
  for _, id in ipairs(TILE_IDS) do run.stock[id] = (tonumber(run.stock[id]) or 0) + placed(id); run.diorama[id] = 0 end
  push_diorama_ranks()
  save_run(); refresh()
  toast("Diorama cleared: every tile is back in stock.")
end

local function cycle_stance()
  if eternal("stances") == 0 then toast("Unlock Stances in Norune Eternal first."); return end
  if not companion_on() then toast("The companion is off: turn on its setting in the Gauntlet's mod settings."); return end
  local now = meta.stance or "target"
  local i = 1
  for k, v in ipairs(STANCES) do if v == now then i = k end end
  meta.stance = STANCES[i % #STANCES + 1]
  save_meta()
  refresh()
  toast(({target = "Companion: attacks your lock-on target.", aggressive = "Companion: attacks anything near.",
          passive = "Companion: holds back."})[meta.stance])
end

moonmod.on("skills.train_requested", function(event)
  local id = type(event.id) == "string" and event.id or ""
  local prefix = ID .. ":"
  if id:sub(1, #prefix) ~= prefix then return end
  local tree, node = id:sub(#prefix + 1):match("^([%w_]+)%.([%w_]+)$")
  if tree == "diorama" and TILE[node] then place_tile(node) end
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
  {"gaffer_attach", "Gaffer: Attachments", "With Gaffer's Stock: two random attachments (400 G)"},
  {"stance", "Companion Stance", "With Stances: the companion attacks your lock-on target, anything near, or nothing"},
  {"abandon", "Abandon Run", "Leave the Gauntlet now (a retreat): back to its title screen"},
  {"records", "Eternal Records", "Moon Shards, runs, wins, best depth and the Heirloom"},
}
for _, a in ipairs(ACTIONS) do try(game.ui.register, {id = a[1], label = a[2], description = a[3]}) end

-- Gaffer's Buggy: once a floor is swept (from the start with Gaffer's Partner) Gaffer stands inside the exit gate.
-- Walking up to him opens the run menu on his wares: four staples always, and a spread of run-only wares.
local function gaffer_price(price)
  if eternal("gaffer") >= 2 then price = price * 2 / 3 end
  if eternal("haggler") > 0 then price = price * 0.8 end
  return math.max(1, math.floor(price))
end

do
local function gaffer_wares()
  local depth = run.depth
  local wares = {
    {id = "antidote", label = "Antidote", price = 40, staple = true, items = {{ITEM.antidote, 1}}, detail = "Cures poison."},
    {id = "bread", label = "Bread", price = 30, staple = true, items = {{ITEM.bread, 1}}, detail = "Restores some HP."},
    {id = "water", label = "Water", price = 30, staple = true, items = {{ITEM.water, 1}}, detail = "Refills your thirst gauge."},
    {id = "repair", label = "Repair Powder", price = 60, staple = true, items = {{ITEM.repair, 1}}, detail = "Restores your weapon's durability."},
    {id = "cure", label = "Cure ailments", price = 50 + 10 * depth, staple = true, kind = "cure",
     detail = "Gaffer's tonic: Goo, poison, curse, freeze and stamina gone from the one you play. No charge if you're well."},
  }
  local pool = {
    {id = "tuneup", label = "Weapon tune-up", price = 150 + 30 * depth, kind = "tuneup", detail = "Your weapon gains a level."},
    {id = "tile", label = "Diorama tile", price = 180, kind = "tile", detail = "A random Diorama tile, ready to place."},
    {id = "auto", label = "Auto Repair Powder", price = 220, items = {{ITEM.auto_repair, 1}}, detail = "Repairs your weapon when it runs low."},
    {id = "holy", label = "Holy Water", price = 80, items = {{ITEM.holy_water, 1}}, detail = "Lifts a curse."},
    {id = "weapon", label = "A new weapon", price = 250 + 40 * depth, kind = "weapon", detail = "A weapon for the one you play, one you don't hold. Keep it or melt it into yours."},
  }
  local others = 0
  for _, c in ipairs(CHARACTERS) do if not contains(run.drafted, c) then others = others + 1 end end
  if others > 0 then
    pool[#pool + 1] = {id = "ally", label = "Ally contract", price = 300 + 40 * depth, kind = "ally", detail = "Someone new joins the run."}
  end
  if eternal("stock") > 0 then
    pool[#pool + 1] = {id = "attach", label = "Attachments", price = 160, kind = "attach", detail = "Two attachments for your weapon's sockets."}
  end
  for _ = 1, math.min(#pool, 3 + (eternal("gaffer") >= 1 and 1 or 0)) do
    wares[#wares + 1] = table.remove(pool, math.random(#pool))
  end
  for _, w in ipairs(wares) do w.price = gaffer_price(w.price) end
  return wares
end

gaffer_arrive = function(quiet)
  if not (floor and run) or floor.gaffer or floor.slot >= WARDEN_SLOT then return end
  floor.gaffer = {wares = gaffer_wares()}
  try(game.world.dungeon_npc_set, {id = "gaffer", model = "gedit/e01/chara/p02a.chr", place = "exit"})
  if not quiet then toast("Gaffer's Buggy pulls up by the exit. Walk up to him to trade.") end
  refresh()
end
end

local function buy_ware(id)
  local ware
  for _, w in ipairs(floor and floor.gaffer and floor.gaffer.wares or {}) do if w.id == id then ware = w end end
  if not ware or ware.sold then return end
  local p = try(game.player.get)
  if ware.kind == "weapon" then
    local c = p and p.character
    local held = c and equipped_weapon(c)
    local candidates = {}
    for _, def in ipairs(try(game.weapons.list) or {}) do
      if type(def) == "table" and def.owner == (ROSTER.fights_as[c] or c) and not (held and def.id == held.id) and #weapon_instances(def.id) == 0 and
         not LOOT.staff_of(def.id) then
        candidates[#candidates + 1] = def.id
      end
    end
    if #candidates == 0 then toast("Gaffer: \"Nothing new for " .. title(c or "you") .. ", sorry.\""); return end
    local spent, err = call(game.economy.spend, {amount = ware.price})
    if not spent then toast("Gaffer wants " .. ware.price .. " Gilda (" .. errmsg(err) .. ")."); return end
    local got = try(game.weapons.give, {id = pick(candidates), character = c})
    if not got then return end
    ware.sold = true
    try(game.ui.run_menu_close)
    found_weapon(c, got.id, got.slot)
    refresh()
    return
  end
  if ware.kind == "ally" then
    local any = false
    for _, c in ipairs(CHARACTERS) do if not contains(run.drafted, c) then any = true end end
    if not any then toast("Gaffer: \"Everyone's already with you.\""); return end
  end
  local spent, err = call(game.economy.spend, {amount = ware.price})
  if not spent then toast("Gaffer wants " .. ware.price .. " Gilda (" .. errmsg(err) .. ")."); return end
  if not ware.staple then ware.sold = true end
  if ware.kind == "cure" then
    local cured = {}
    for _, ailment in ipairs({"goo", "poison", "curse", "freeze", "stamina"}) do
      local r = try(game.player.status_remove, {status = ailment})
      if r and r.removed then cured[#cured + 1] = ailment end
    end
    if #cured == 0 then
      try(game.economy.add, {amount = ware.price})
      toast("Gaffer: \"You look fine to me. Keep your Gilda.\"")
    else
      toast("Gaffer's tonic clears " .. table.concat(cured, ", ") .. ". " .. ware.price .. " Gilda.")
    end
  elseif ware.items then
    for _, it in ipairs(ware.items) do try(game.items.give, {id = "chronicle:item:" .. it[1], count = it[2]}) end
    toast("Gaffer: \"Pleasure doing business!\" " .. ware.label .. " for " .. ware.price .. " Gilda.")
  elseif ware.kind == "tuneup" then
    local w = p and p.weapon
    if w and w.id then level_up({id = w.id, character = p.character, slot = w.slot}, 1) end
    toast("Gaffer tunes up " .. title(p and p.character or "your") .. "'s weapon: one level up.")
  elseif ware.kind == "tile" then
    local tile = pick(TILE_IDS)
    run.stock[tile] = (tonumber(run.stock[tile]) or 0) + 1
    toast("Gaffer: a " .. TILE[tile].title .. " tile, ready to place.")
  elseif ware.kind == "ally" then
    draft_ally("Gaffer's contract")
  elseif ware.kind == "attach" then
    for _ = 1, 2 do try(game.items.give, {id = "chronicle:item:" .. pick(ATTACHMENTS), count = 1}) end
    toast("Gaffer: two attachments for " .. ware.price .. " Gilda.")
  end
  save_run()
  refresh()
end

-- The Rest floor: Gaffer waits by the exit, the spring heals the party once, the exit gate leads on to the biome's
-- first floor and the antechamber's stairs take the Cursed Path there instead (dungeons.set_backrooms stay).
function REST.arrive()
  floor.rest_keys = floor.rest_keys or {}
  gaffer_arrive(true)
end

function REST.tick(p)
  if frame - floor.entered < 60 then return end
  if not floor.rest_ready then
    -- the floor is built a few frames after it is reported: wait for its spring
    local room = try(game.dungeons.rest_room_get)
    if not (room and room.state == "rest") then return end
    floor.rest_ready = true
    floor.spring = room.spring
  end
  -- No monster carries the gate key here: it waits in the bag. The floor's key can still change while the floor
  -- settles, so a key given for an earlier read is taken back (a spare one would open a later floor's gate), and the
  -- floor's start clears the bag's keys, so it is given again until it is seen there (never after: then the gate
  -- may have taken it).
  if frame % 30 == 0 and not floor.rest_left and not floor.rest_key_held then
    local key = (try(game.dungeons.back_floor_get) or {}).gate_key
    local id = key and type(key.id) == "string" and key.id ~= "" and key.id or nil
    for given in pairs(floor.rest_keys) do
      if given ~= id then try(game.items.remove, {id = given, count = 1}); floor.rest_keys[given] = nil end
    end
    if id and key.held and floor.rest_keys[id] then floor.rest_key_held = frame - floor.entered > 300
    elseif id and not key.held and try(game.items.give, {id = id, count = 1}) then floor.rest_keys[id] = true end
  end
  if run.spring_used == run.pos or not (p and p.position and floor.spring) then return end
  local dx, dz = p.position.x - floor.spring.x, p.position.z - floor.spring.z
  if dx * dx + dz * dz > 260 * 260 then return end
  run.spring_used = run.pos
  for _, c in ipairs(run.drafted) do try(game.player.heal, {amount = max_hp_of(c), character = c}) end
  if p.max_water then try(game.player.set, {water = math.floor(p.max_water), character = p.character}) end
  for _, ailment in ipairs({"goo", "poison", "curse", "freeze", "stamina"}) do try(game.player.status_remove, {status = ailment}) end
  try(game.effects.burst, {kind = "heal", position = {x = p.position.x, y = (p.position.y or 0) + 2, z = p.position.z}, scale = 1.6})
  toast("The spring restores the party: health, thirst and ailments.")
  save_run()
end

-- The stairs' panel answered Proceed: on to the next biome's first floor, the whole biome cursed.
function REST.cursed()
  if floor.rest_left then return end
  floor.rest_left = true
  run.cursed_biome = run.pos
  for given in pairs(floor.rest_keys) do try(game.items.remove, {id = given, count = 1}) end
  floor.rest_keys = {}
  toast("The Cursed Path: every floor of " .. biome_def(run.pos).name .. " is cursed.", "curse")
  queue_transition(route(planned(run.pos, 1)).floors[1].id, 30, "cursed path")
  save_run()
  refresh()
end

moonmod.on("game.dungeon.backroom", function(e)
  if e and e.entered and on_route() and floor.rest then REST.cursed() end
end)

moonmod.on("game.dungeon_npc.near", function(e)
  if e.id == "gaffer" and floor and floor.gaffer and on_route() then
    refresh()
    try(game.ui.run_menu_open, {tab = "gaffer"})
  end
end)

local function gaffer(items, price)
  if not (on_route() and floor.gaffer) then toast("Gaffer isn't on this floor. His Buggy pulls up once a floor is swept."); return end
  price = gaffer_price(price)
  local spent, err = call(game.economy.spend, {amount = price})
  if not spent then toast("Gaffer wants " .. price .. " Gilda (" .. errmsg(err) .. ")."); return end
  local n = 0
  for _, it in ipairs(items) do
    local got = try(game.items.give, {id = "chronicle:item:" .. it[1], count = it[2]})
    n = n + (got and got.added or 0)
  end
  toast("Gaffer: \"Pleasure doing business!\" " .. n .. " item" .. (n == 1 and "" or "s") .. " for " .. price .. " Gilda.")
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
  toast(string.format("Heirloom banked: +%d attack, +%d magic for every new run.", h.attack, h.magic))
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
    toast(string.format("%s %d-%d, depth %d of %d. Curses: %s. Diorama %d of %d, %d blessings, +%d shards.",
        b and b.name or "?", run.pos, run.slot, run.depth, total_floors(), curses, placed_total(), plots(), #run.blessings, run.shards))
  elseif a.id == "curse" then toggle_curse()
  elseif a.id == "heirloom" then bank_heirloom()
  elseif a.id == "gaffer_repair" then gaffer({{ITEM.repair, 2}}, 300)
  elseif a.id == "gaffer_food" then gaffer({{ITEM.bread, 2}, {ITEM.water, 2}}, 240)
  elseif a.id == "stance" then cycle_stance()
  elseif a.id == "gaffer_attach" then
    if eternal("stock") < 1 then toast("Unlock Gaffer's Stock in Norune Eternal first."); return end
    gaffer({{pick(ATTACHMENTS), 1}, {pick(ATTACHMENTS), 1}}, 400)
  elseif a.id == "diorama_clear" then clear_diorama()
  elseif a.id == "records" then
    local h = meta.heirloom
    toast(string.format("Moon Shards %d. Runs %d, wins %d. Best depth %d. Heirloom: %s.", meta.shards, meta.runs, meta.wins,
        meta.best_depth, h and string.format("+%d atk +%d mag", h.attack or 0, h.magic or 0) or "none"))
  elseif a.id == "page" then
    update_sheet()
    local ok, err = call(game.ui.sheet_open)
    if not ok then
      local nav = try(game.ui.navigate, {mod_id = ID, tab = "skills"})
      if not nav then toast("Open Journal > Character, or this mod's Skills tab (" .. errmsg(err) .. ").") end
    end
  end
end)

moonmod.on("ui.run_menu_action", function(e)
  if not run then return end
  if e.tab == "gaffer" then buy_ware(e.row)
  elseif e.tab == "diorama" then
    if e.row == "clear" then clear_diorama() elseif TILE[e.row] then place_tile(e.row) end
  elseif e.tab == "run" then
    if e.row == "curse" then toggle_curse()
    elseif e.row == "stance" then cycle_stance()
    elseif e.row == "abandon" then
      try(game.ui.run_menu_close)
      call(game.ui.choice_open, {id = "abandon", title = "ABANDON THE RUN?", cancel = true,
          options = {{title = "Keep going", lines = {"Back to the floor."}},
                     {title = "Abandon", subtitle = "The run ends here", lines = {{text = "You keep the Moon Shards earned so far.", tone = "dim"}}}}})
    end
  end
end)
moonmod.on("ui.choice_made", function(e)
  if e.id ~= "abandon" or tonumber(e.index) ~= 2 or not run then return end
  local ok, err = call(game.session.finish)
  if not ok then toast("Could not leave now (" .. errmsg(err) .. ").") end
end)

moonmod.on("settings.changed", function() refresh() end)

-- Other mods can ask about the run (e.g. to stand down their own enemy scaling).
try(game.scripts.register_function, {id = "run_state", description = "Moon Gauntlet run: active, biome, floor, depth, cursed"}, function()
  return {active = run ~= nil and run.phase == "active" and not run.suspended, biome = run and run.pos or 0, floor = run and run.slot or 0,
          depth = run and run.depth or 0, cursed = floor and floor.cursed or false}
end)

-- Start-up: a run still in storage was cut short when the game closed mid-run: it counts as a retreat.
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
