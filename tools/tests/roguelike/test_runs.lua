-- Plays Moon Gauntlet runs against a fake Chronicle adapter.
-- Usage, from the repository root:  lua tools/tests/roguelike/test_runs.lua
-- (any Lua 5.4+ works; the vendored vendor/lua-5.5.1 builds with `make linux` / `make mingw`).
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = here .. "/?.lua;" .. package.path
local F = require("fake_game")
local root = here .. "/../../.."
local MOD = root .. "/mods/moonmod.roguelike/main.lua"
-- Setting defaults straight from the manifest (one setting object per line there).
local defaults = {}
for line in io.lines(root .. "/mods/moonmod.roguelike/mod.json") do
  local id = line:match('"id":%s*"([%w_]+)"')
  local default = line:match('"default":%s*([^,}]+)')
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
  else failed = failed + 1; print("  FAIL " .. label .. (extra and ("  [" .. tostring(extra) .. "]") or "")) end
end
-- The scenarios walk each biome's own floors; shuffled floors have a scenario of their own.
local function settings(over) local s = F.deepcopy(defaults); s.floor_shuffle = false; s.boss_wardens = 0; s.loot_rarity = false; s.genie_finale = false; for k, v in pairs(over or {}) do s[k] = v end; return s end
local function boot(opts)
  opts = opts or {}
  opts.settings = settings(opts.overrides)
  local S = F.new(opts)
  math.randomseed(opts.seed or 42)
  F.load_mod(S, MOD)
  return S
end
local function start_run(S)
  S.open_title_mode()
  S.select("start")
  S.tick(40)
  S.tick(20)
end
local function run_floor(S, opts)
  opts = opts or {}
  S.tick(20)
  S.reveal_all()
  S.tick(30)
  if opts.atla then S.atla = {}; S.tick(60) end
  if opts.sweep then S.kill_all(); S.tick(250) end
end
-- The Rest floor between biomes: on through its exit gate to the next biome's first floor.
local function pass_rest(S)
  local run = S.storage.run
  if not (run and run.phase == "active" and run.slot == 0) then return end
  S.tick(80)
  S.exit_gate()
  S.tick(20)
end
local function finish_biome(S)
  for _ = 2, 4 do S.exit_gate(); run_floor(S) end
  for _, w in ipairs(S.enter_warden_room()) do if w.alive then S.kill(w) end end
  S.tick(2)
  S.tick(350)
  S.tick(20)
  pass_rest(S)
end
local function entry_ids(S) local t = {}; for _, e in ipairs(S.page().entries or {}) do t[#t + 1] = e.id end; return table.concat(t, ",") end

-- 1. The title mode and a full five-biome victory ------------------------------------------------
print("Scenario 1: title mode, full run to victory")
local S = boot({overrides = {genie_finale = true}})
local regs = 0; for _ in pairs(S.registered) do regs = regs + 1 end
check(regs == 5, "five gauntlet dungeons registered", regs)
check(S.page() and S.page().label == "Dark Genie's Gauntlet" and S.page().title == "DARK GENIE'S GAUNTLET", "title mode registered")
check(entry_ids(S) == "start,character,legend,eternal,records", "root page entries", entry_ids(S))
S.open_title_mode()
S.select("character")
check(S.storage.meta.start_char == "xiao" and S.page().entries[2].label:find("Xiao"), "Starting Character cycles", S.page().entries[2].label)
for _ = 1, 5 do S.select("character") end
check(S.storage.meta.start_char == "toan", "and wraps back to Toan")
S.select("start")
check(S.session and S.session.owner == "moonmod.roguelike", "Start Run began a sandbox session")
check(#S.party == 6 and S.slot_id and S.game.save.slot_id().slot_id == nil, "all six joined, no save slot")
S.tick(40)
check(S.context == "dungeon" and S.dungeon == 0 and S.floor == 16, "dropped onto DBC run floor I", tostring(S.dungeon) .. ":" .. tostring(S.floor))
run_floor(S, {atla = true})
local run = S.storage.run
check(run.phase == "active" and run.depth == 1, "run active at depth 1")
check(S.hp.xiao == 0 and S.hp.ruby == 0 and S.hp.toan > 0, "undrafted allies start knocked out")
check((S.items["chronicle:item:177"] or 0) == 2, "starter kit given in the fresh save")
check(S.monsters[1].exp == 36, "ABS x6 on floor I", S.monsters[1].exp)
check(S.floor_label == "1-1" and S.floor_number == 1 and not S.layers.gauntlet and next(S.hud_icons) == nil,
      "the floor plate reads 1-1 and the card B1, no text line", S.floor_label)
local intros = 0; for _, t in ipairs(S.toasts) do if t:find("^Divine Beast Cave 1%-1") then intros = intros + 1 end end
check(intros == 1, "the floor intro shows once, though the floor is built after it is reported", intros)
check(S.menu and S.menu.tabs[1].id == "run" and S.menu_row("diorama", "river") and S.sheet == nil,
      "Start opens the run menu (run, Diorama, blessings, party); the Journal page stays off", S.menu and #S.menu.tabs)
local stock = 0; for _, n in pairs(S.storage.run.stock) do stock = stock + n end
check(stock == 1, "Atla pickup gave a Diorama tile", stock)
S.monsters[1].alive = true; S.kill(S.monsters[1]); S.tick(2)
S.input_pressed["curse_key"] = true; S.tick(1)
check(S.storage.run.next_cursed == true, "G toggles the Cursed Gate")
check(S.last_toast():find("^Next floor is cursed") and S.toast_icons[#S.toasts] == "curse", "with a short notice and the Curse badge", S.last_toast())
check(S.hud_icons.curse and S.hud_icons.curse.blink and not S.hud_icons.cache, "a waiting curse blinks its badge")
S.exit_gate(); run_floor(S, {sweep = true})
run = S.storage.run
check(run.slot == 2 and run.depth == 2 and run.kills == 1, "native exit moved the run to floor II", run.slot)
check(S.modifiers.chest_value == 100, "cursed floor generated with richer chests")
check(S.floor_label == "1-2" and S.floor_number == 2 and S.hud_icons.curse and not S.hud_icons.curse.blink and S.hud_icons.cache and
      S.hud_icons.cache.image == "moonmod/roguelike/hud/cache.png", "a cursed floor shows the Curse badge and the cache chest")
check(#run.drafted == 2, "Golden Atla drafted an ally", #run.drafted)
local ally = run.drafted[2]
check(S.hp[ally] == S.max_hp[ally], "the drafted ally is revived", ally .. " " .. S.hp[ally])
local before = S.weapons[ally][0].abs + S.weapons[ally][0].level * 1000
S.monsters[2].alive = true; S.monsters[2].exp = 40; S.kill(S.monsters[2]); S.tick(2)
check(S.weapons[ally][0].abs + S.weapons[ally][0].level * 1000 > before, "benched ally's weapon gained shared ABS")
-- an undrafted, knocked-out character cannot be switched to; a drafted one bounces back
S.exit_gate(); run_floor(S)
check(S.char_blocks and #S.char_blocks == 2 and S.char_blocks[2] == run.drafted[2],
      "a floor holds only the drafted characters' own doors and jumps", S.char_blocks and table.concat(S.char_blocks, ","))
local cache_at; for i, t in ipairs(S.toasts) do if t:find("^Miracle cache!") then cache_at = i end end
check(cache_at and S.toast_icons[cache_at] == "moonmod/roguelike/hud/cache.png", "cursed floor paid a Miracle cache on exit, with the chest")
S.input_pressed["curse_key"] = true; S.tick(1)
check(S.storage.run.next_cursed == false and S.last_toast():find("Warden"), "the Warden floor cannot be cursed")
S.exit_gate(); S.tick(20)
check(S.warden_room and S.warden_room.lock_in and S.warden_room_state == "sealed", "the Warden floor seals its room, with lock-in")
S.reveal_all(); S.tick(30)
check(not S.bars.warden and #S.spawned == 0, "no Warden before the room opens")
local warden = S.enter_warden_room()[1]
check(S.find_toast("Warden's door grinds open"), "clearing the floor opens the Warden's door")
check(warden and warden.max_hp >= 40 * 10 and S.bars.warden and warden.arena_origin == nil,
      "the floor's toughest monster grows into the Warden (x10 base HP) in its room, with a HUD bar", warden and warden.max_hp)
check(S.boss_cards and S.boss_cards[#S.boss_cards].kicker == "WARDEN OF DIVINE BEAST CAVE", "the Warden makes a boss's entrance",
      S.boss_cards and S.boss_cards[#S.boss_cards].kicker)
check(S.backrooms and S.backrooms.free and S.backrooms.title == "ENTER THE VAULT?", "Vaults are free, behind an enter-at-your-own-risk prompt")
check(S.floor_label == nil and next(S.hud_icons) == nil, "the Warden floor keeps the native Boss plate", S.floor_label)
S.kill(warden); S.tick(2)
check(S.warden_released == 1, "the Warden's fall opens the room's doors")
S.tick(350)
-- the Rest floor between biomes, in the next biome's dungeon
check(S.dungeon == 1 and S.floor == 17, "Warden death moved the run to Wise Owl Forest's Rest floor", tostring(S.dungeon) .. ":" .. tostring(S.floor))
S.tick(20)
check(S.storage.run.pos == 2 and S.storage.run.slot == 0 and S.storage.run.depth == 4, "biome 2's Rest floor, depth still 4", S.storage.run.depth)
check(#S.monsters == 0 and S.modifiers and S.modifiers.chests == -100 and S.rest_built, "a rest floor: nothing to fight, no chests")
check(S.npc and S.npc.id == "gaffer" and S.floor_label == "Rest", "Gaffer waits there, the plate reads Rest", S.floor_label)
check(S.backrooms and S.backrooms.stay and S.backrooms.title == "TAKE THE CURSED PATH?", "its stairs are the Cursed Path")
S.tick(60)
check((S.items["chronicle:item:194"] or 0) == 1, "the gate key waits in the bag")
S.gate_key = 196; S.tick(60)
check((S.items["chronicle:item:194"] or 0) == 0 and (S.items["chronicle:item:196"] or 0) == 1,
      "a key the floor changes while it settles is swapped for the new one")
S.hp.toan = 5; S.player_pos = {x = 2000, y = 0, z = 2000}; S.tick(30)
check(S.hp.toan == 5, "the spring does nothing from across the room")
S.player_pos = {x = 960, y = 0, z = 600}; S.tick(30)
check(S.hp.toan == S.max_hp.toan and S.find_toast("The spring restores"), "the spring heals the party", S.hp.toan)
S.hp.toan = 5; S.tick(30)
check(S.hp.toan == 5, "once a visit")
S.hp.toan = S.max_hp.toan; S.player_pos = nil
check(S.menu_row("run", "curse").enabled == false, "the Cursed Gate stays shut on the Rest floor")
S.exit_gate(); S.tick(20)
check(S.dungeon == 1 and S.floor == 18 and S.storage.run.pos == 2 and S.storage.run.slot == 1 and not S.rest_room,
      "its exit gate leads on to 2-1", tostring(S.dungeon) .. ":" .. tostring(S.floor))
check(S.storage.run.depth == 5 and #S.monsters > 0, "biome 2, depth 5", S.storage.run.depth)
local tile; for id, n in pairs(S.storage.run.stock) do if n > 0 then tile = id end end
local left = tonumber(S.menu_row("diorama", tile).value:match("(%d+) left"))
check(S.menu_row("diorama", tile).enabled ~= false and left and left >= 1, "the menu offers the tile in stock", S.menu_row("diorama", tile).value)
S.menu_use("diorama", tile)
check(S.storage.run.diorama[tile] == 1, "placed a " .. tile .. " tile from the run menu")
check(S.menu_row("diorama", tile).value == string.format("1 placed, %d left", left - 1), "and the menu shows it placed",
      S.menu_row("diorama", tile).value)
S.menu_use("run", "curse"); S.tick(1)
check(S.storage.run.next_cursed and S.menu_row("run", "curse").value == "On", "the run menu curses the next floor")
S.menu_use("run", "curse"); S.tick(1)
check(not S.storage.run.next_cursed and S.menu_row("run", "curse").value == "Off", "and lifts it")
run_floor(S); finish_biome(S)
for _ = 4, 5 do S.tick(20); run_floor(S); finish_biome(S) end
S.tick(20); run_floor(S); finish_biome(S)
-- the finale: the Genie's Lair, below the last Warden
check(S.find_toast("The Genie's Lair awaits"), "the last Warden opens the Genie's Lair")
S.tick(20)
run = S.storage.run
check(S.context ~= "title" and run.lair == "in" and run.pos == 5 and run.depth == 21, "the run goes down to the Lair", run.depth)
check(S.warden_room and S.warden_room.lock_in, "the Lair seals its room like a Warden floor")
local forms = {}
local function genie_form()
  for _, m in ipairs(S.spawned) do if m.alive and m.arena_slot == 0 and (m.model == 84 or m.model == 106) then return m end end
end
S.enter_warden_room()
check(S.lighting and S.lighting.fog and S.lighting.fog.b > S.lighting.fog.g, "the Lair is steeped in violet fog")
check(S.boss_cards[#S.boss_cards].kicker == "THE GENIE'S LAIR" and S.bars.warden and S.bars.warden.label == "DARK GENIE",
      "the Dark Genie makes his entrance, with his own bar", S.bars.warden and S.bars.warden.label)
local shape = S.storage.run.genie and S.storage.run.genie.shape
check(shape == "pink_dark" or shape == "dark_pink" or shape == "both", "the fight's shape was rolled", shape)
for _ = 1, 3 do
  local cast = {}
  for _, m in ipairs(S.spawned) do if m.alive and m.arena_slot and m.arena_slot > 0 then cast[#cast + 1] = m end end
  if not genie_form() then break end
  for _, m in ipairs(S.spawned) do if m.alive and m.arena_slot == 0 then forms[#forms + 1] = m.model end end
  check(#cast >= 2, "each form brings some of its helpers", #cast)
  for _, m in ipairs(S.spawned) do if m.alive and m.arena_slot == 0 then S.kill(m) end end
  for _, m in ipairs(cast) do m.alive = false end -- the engine fades a cast out with its boss
  S.tick(200)
end
check(#forms == 2 and forms[1] ~= forms[2], "the pink Genie and his dark form both fight", table.concat(forms, ","))
S.tick(400)
check(S.find_toast("Dark Genie is vanquished"), "the Genie's fall wins the run")
check(S.context == "title" and not S.session, "the Genie's fall ended the session and returned to the title", S.context)
check(S.storage.run == false and S.storage.meta.wins == 1, "victory recorded", S.storage.meta.wins)
check(S.storage.meta.best_depth == 21, "best depth 21, the Lair included", S.storage.meta.best_depth)
check(S.page().lines[#S.page().lines]:find("CONQUERED"), "title screen shows the last run", S.page().lines[#S.page().lines])
check(S.tuning == nil and S.floor_label == nil and next(S.hud_icons) == nil and S.sheet == nil and S.menu == nil,
      "run effects, HUD, Journal page and run menu cleared")
local won = S.storage.meta.shards
check(won >= 52 and won <= 64, "a win banks about 58 Moon Shards", won)

-- every notice of the run fits the message window: three lines of about 24 characters
local longest = ""; for _, t in ipairs(S.toasts) do if #t > #longest then longest = t end end
check(#longest <= 72, "every notice fits three lines of the message window", #longest .. ": " .. longest)

-- 2. Norune Eternal from the title screen ----------------------------------------------------------
print("Scenario 2: Norune Eternal on the title screen")
S.select("eternal")
local sky = S.page().sky
check(sky and #sky.nodes >= 100 and #sky.groups >= 8, "eternal page is the sky", sky and #sky.nodes)
check(S.page().root == false, "eternal page is a sub-page")
check(S.sky_node("norune").state == "owned" and S.sky_node("kit").state == "open" and S.sky_node("gaffer").state == "locked",
      "the heart is lit, trunks open, the rest locked", S.sky_node("gaffer").state)
S.sky_act("gaffer", "buy")
check(S.storage.meta.eternal.gaffer == nil and S.sky_node("gaffer").cost:find("^Needs Repair Kit"), "a locked node says what it needs",
      S.sky_node("gaffer").cost)
S.sky_act("kit", "buy")
check(S.storage.meta.eternal.kit == 1 and S.storage.meta.shards == won - 2, "Cross on an open node buys it", S.storage.meta.shards)
check(S.sky_node("kit").rank == "1/2" and S.sky_node("gaffer").state == "open", "its rank shows and the next node opens")
for _, id in ipairs({"gaffer", "whetstone", "macho", "gem", "vault"}) do S.sky_act(id, "buy") end
local m = S.storage.meta.eternal
check(m.gaffer == 1 and m.whetstone == 1 and m.macho == 1 and m.gem == 1 and m.vault == 1, "bought along Craft to the Heirloom Vault")
check(S.storage.meta.shards == won - 32, "and paid for each", S.storage.meta.shards)
S.sky_act("moonblade", "buy")
check(S.sky_node("moonblade").cost:find("Needs"), "a Keystone far down a path stays out of reach", S.sky_node("moonblade").cost)
-- switching off and ranks
S.sky_act("whetstone", "toggle")
check(S.storage.meta.off.whetstone == true and S.sky_node("whetstone").on == false and S.sky_node("macho").state == "owned",
      "Square switches a node off and keeps what follows it")
S.sky_act("whetstone", "toggle")
check(S.storage.meta.off.whetstone == nil and S.sky_node("whetstone").on, "and back on")
S.sky_act("whetstone", "buy")
S.sky_act("whetstone", "rank_down")
check(S.storage.meta.eternal.whetstone == 2 and S.storage.meta.set.whetstone == 1 and S.sky_node("whetstone").rank == "1/2 of 3",
      "L1 sets a lower rank in use", S.sky_node("whetstone").rank)
S.sky_act("whetstone", "rank_up")
check(S.storage.meta.set.whetstone == nil and S.sky_node("whetstone").rank == "2/3", "R1 back to the rank owned")
S.sky_act("feast", "toggle")
check(S.sky_node("feast").cost == "Buy it first", "Square on an unbought node")
S.select("back")
check(entry_ids(S) == "start,character,legend,eternal,records", "Circle on a sub-page goes back to the root page")
-- Keystone slots, Heat and prices, from a prepared save
do
  local store = F.deepcopy(S.storage)
  store.meta.shards, store.meta.sigils = 2, 20
  for _, id in ipairs({"charm", "unbreakable", "laststand", "rain", "endless", "helping", "feast"}) do store.meta.eternal[id] = 1 end
  store.meta.eternal.crowded, store.meta.eternal.hardened = 2, 1
  store.meta.off = {feast = true}
  local SK = boot({storage = store})
  SK.open_title_mode(); SK.select("eternal")
  SK.sky_act("shrine", "buy")
  check(SK.sky_node("shrine").cost == "Needs 5 Moon Shards, you have 2", "unaffordable node says what it costs", SK.sky_node("shrine").cost)
  check(SK.page().sky.top[3] == "Heat 3  x1.3    Keystones 3/2" or SK.page().sky.top[3]:find("^Heat 3"), "Pacts add Heat to the top line",
        SK.page().sky.top[3])
  SK.sky_act("feast", "toggle")
  check(SK.storage.meta.off.feast == true and SK.sky_node("feast").cost:find("Keystone slots full"), "a third Keystone does not fit two slots",
        SK.sky_node("feast").cost)
  SK.sky_act("laststand", "toggle"); SK.sky_act("endless", "toggle"); SK.sky_act("feast", "toggle")
  check(SK.storage.meta.off.feast == nil and SK.storage.meta.off.laststand == true, "switch one off to make room")
  SK.sky_act("hardened", "toggle")
  check(SK.page().sky.top[3]:find("^Heat 2"), "a Pact switched off takes its Heat with it", SK.page().sky.top[3])
end
S.select("records")
check(S.page().lines[1]:find("Wins 1"), "records page", S.page().lines[1])
S.select("done")
check(entry_ids(S) == "start,character,legend,eternal,records", "back from records")

-- 3. Second run: heirloom, forge, gaffer, a found weapon, retreat ------------------------------
print("Scenario 3: second run with unlocks, a found weapon, retreat")
S.storage.meta.heirloom = {attack = 20, endurance = 0, speed = 0, magic = 5, elem = {0, 10, 0, 0, 0}}
local S2 = boot({storage = S.storage, overrides = {biome_count = 2}})
start_run(S2)
local starter = S2.weapons.toan[S2.equipped.toan]
check(starter.attack >= 30, "heirloom added attack to the starting weapon", starter.attack)
check(#starter.attach == 1, "Macho's Forge inserted an attachment", #starter.attach)
run_floor(S2)
S2.exit_gate(); run_floor(S2)
S2.gilda = 1000
S2.action("gaffer_repair")
check(S2.gilda == 1000 and S2.last_toast():find("isn't on this floor"), "Gaffer isn't here before the floor is swept", S2.last_toast())
S2.tick(200); S2.kill_all(); S2.tick(30)
check(S2.npc and S2.npc.id == "gaffer" and S2.npc.model:find("p02a") and S2.npc.place == "exit" and S2.find_toast("Buggy pulls up"),
      "a swept floor brings Gaffer to the exit", S2.npc and S2.npc.model)
check(S2.menu and S2.menu.tabs[1].id == "gaffer" and S2.menu_row("gaffer", "antidote") and S2.menu_row("gaffer", "bread")
      and S2.menu_row("gaffer", "water") and S2.menu_row("gaffer", "repair") and #S2.menu.tabs[1].rows >= 7,
      "his wares: the four staples and a spread of others", S2.menu and #S2.menu.tabs[1].rows)
S2.emit("game.dungeon_npc.near", {id = "gaffer"}); S2.tick(1)
check(S2.menu_open == "gaffer", "walking up to him opens the run menu on his wares", tostring(S2.menu_open))
local repair_price = tonumber(S2.menu_row("gaffer", "repair").value:match("%d+"))
local before = S2.items["chronicle:item:177"] or 0
S2.menu_use("gaffer", "repair")
check(S2.gilda == 1000 - repair_price and (S2.items["chronicle:item:177"] or 0) == before + 1, "bought Repair Powder", S2.gilda)
check(S2.menu_row("gaffer", "repair").enabled ~= false, "a staple stays on sale")
local cure_row = S2.menu_row("gaffer", "cure")
check(cure_row ~= nil, "Gaffer sells a cure for ailments")
if cure_row then
  local cash = S2.gilda
  S2.menu_use("gaffer", "cure")
  check(S2.gilda == cash and S2.last_toast():find("look fine"), "a cure costs nothing when there's nothing to cure", S2.last_toast())
  S2.ailments = {goo = true, poison = true}
  local price = tonumber(cure_row.value:match("%d+"))
  S2.menu_use("gaffer", "cure")
  check(S2.gilda == cash - price and next(S2.ailments) == nil and S2.last_toast():find("goo"), "his tonic clears Goo and poison for its price",
        S2.last_toast())
end
local special; for _, r in ipairs(S2.menu.tabs[1].rows) do if r.tone == "gold" and r.id ~= "weapon" and r.id ~= "ally" then special = r.id end end
if special then
  S2.gilda = 5000
  S2.menu_use("gaffer", special); S2.tick(1)
  check(S2.menu_row("gaffer", special).enabled == false, "a run-only ware sells once", special)
end
-- a found weapon: pre-leveled, then the choice between it and the held one
local held_slot = S2.equipped.toan
local held_attack = S2.weapons.toan[held_slot].attack
local found_slot = S2.pickup_weapon("toan", 259)
check(S2.weapons.toan[found_slot].level >= 1 and #S2.weapons.toan[found_slot].attach >= 1, "found weapon arrived pre-leveled with an attachment")
check(S2.choice and S2.choice.id == "weapon" and #S2.choice.options == 2 and not S2.layers.gauntlet,
      "the weapon choice pauses on two cards, the HUD line out of the way", S2.choice and S2.choice.title)
check(S2.choice.options[1].subtitle:find("^In hand") and S2.choice.options[2].subtitle:find("^Found"), "held first, found second",
      S2.choice.options[1].subtitle)
local found_attack = S2.weapons.toan[found_slot].attack
S2.pick(1)
check(S2.weapons.toan[found_slot] == nil and S2.equipped.toan == held_slot, "kept the held weapon; the found one is gone")
check(S2.weapons.toan[held_slot].attack == held_attack + math.floor(found_attack / 4), "and a quarter of its attack went into the held one",
      S2.weapons.toan[held_slot].attack)
check(not S2.choice and S2.floor_label, "the choice closed")
-- a drafted ally switched to an undrafted one bounces back
local drafted = S2.storage.run.drafted
local outsider; for _, c in ipairs(S2.party) do local d = false; for _, x in ipairs(drafted) do if x == c then d = true end end; if not d then outsider = c end end
S2.hp[outsider] = 50; S2.active = outsider; S2.tick(60)
check(S2.active ~= outsider and S2.find_toast("not drafted"), "undrafted " .. outsider .. " sent back", S2.active)
S2.exit_gate(); S2.tick(5)
S2.to_town(); S2.tick(30)
check(S2.context == "title" and S2.storage.run == false and S2.storage.meta.retreats == 1, "leaving the dungeon ended the run as a retreat")
check(S2.page().lines[#S2.page().lines]:find("Left at"), "title shows where the run was left", S2.page().lines[#S2.page().lines])

-- 4. Defeat and Abandon ---------------------------------------------------------------------------
print("Scenario 4: defeat and Abandon Run")
local S3 = boot({storage = S2.storage})
start_run(S3); run_floor(S3)
S3.game_over(); S3.tick(30)
check(S3.storage.run == false and S3.storage.meta.deaths == 1, "a game over ended the run as a defeat")
check(S3.page().lines[#S3.page().lines]:find("Fell in"), "title shows where the run fell", S3.page().lines[#S3.page().lines])
start_run(S3); run_floor(S3)
S3.action("abandon"); S3.tick(10); S3.tick(30)
check(S3.storage.run == false and S3.storage.meta.retreats == 2, "Abandon Run leaves the Gauntlet as a retreat", S3.storage.meta.retreats)

-- 5. Off route, quitting mid-run, reload ----------------------------------------------------------
print("Scenario 5: off route, quit mid-run, reload")
local S4 = boot({storage = S3.storage})
start_run(S4); run_floor(S4)
S4.enter(0, 3); S4.tick(20)
check(S4.storage.run.suspended == true and S4.floor_label == nil, "a native floor pauses the run and the plate shows its number")
S4.enter(0, 16); S4.tick(20)
check(S4.storage.run.suspended == false, "back on route resumes it")
-- the game closes mid-run; on the next start the run counts as a retreat
local S5 = F.new({storage = S4.storage, settings = settings()}); S5.registered = S4.registered; S5.floor_counts = S4.floor_counts
F.load_mod(S5, MOD)
check(S5.storage.run == false and S5.storage.meta.retreats == 3, "a run cut short by quitting closes as a retreat", S5.storage.meta.retreats)
local ready_line; for _, l in ipairs(S5.log) do if l:find("Moon Gauntlet ready") then ready_line = l end end
check(ready_line and ready_line:find("5 of 5"), "reload re-adopted all five biomes", ready_line)

-- 6. Older engine: no title modes ------------------------------------------------------------------
print("Scenario 6: engine without title modes or tuning")
local S7 = boot({fail_ops = {["title.mode_register"] = true, ["player.tuning_set"] = true}})
local warned = false; for _, l in ipairs(S7.log) do if l:find("no title modes") then warned = true end end
check(warned, "logs that the engine has no title modes")
check(S7.page() == nil, "no title mode registered")
-- an engine without the floor label and HUD icons gets the text line
local S7b = boot({fail_ops = {["render.floor_label_set"] = true, ["render.floor_label_clear"] = true}})
start_run(S7b); run_floor(S7b)
check(S7b.layers.gauntlet == "GAUNTLET 1-I", "without HUD icons the run falls back to a text line", S7b.layers.gauntlet)

-- 7. Biome shuffle ---------------------------------------------------------------------------------
print("Scenario 7: biome shuffle")
local S8
for seed = 1, 40 do
  S8 = boot({overrides = {biome_shuffle = true}, seed = seed})
  start_run(S8)
  if S8.dungeon > 0 then break end
end
S8.reveal_all(); S8.tick(30)
check(S8.dungeon > 0 and S8.monsters[1].max_hp < 40, "a late biome rolled first has weaker enemies", tostring(S8.dungeon) .. " hp " .. S8.monsters[1].max_hp)

-- 8. A starting character other than Toan ---------------------------------------------------------
print("Scenario 8: Xiao starts the run")
local S9 = boot()
S9.open_title_mode()
S9.select("character")
S9.select("start")
S9.tick(120)
check(S9.active == "xiao" and not S9.find_toast("not drafted"), "the run opens as Xiao with no draft bounce", S9.active)
check(not S9.find_toast("Off the Gauntlet route"), "the dungeon entrance is not called off route")
finish_biome(S9)
check(S9.dungeon == 1 and S9.active == "xiao" and not S9.find_toast("not drafted"), "the next biome opens as Xiao too",
      tostring(S9.dungeon) .. " " .. S9.active)
check(not S9.find_toast("Off the Gauntlet route") and not S9.storage.run.suspended, "and its entrance is not off route either")

-- 9. One weapon each: take the found one, an outsider's weapon, a broken weapon ends the run ------------
print("Scenario 9: one weapon each, and a broken weapon ends the run")
local S10 = boot()
start_run(S10)
run_floor(S10)
local old_slot = S10.equipped.toan
local old_magic = S10.weapons.toan[old_slot].magic
local new_slot = S10.pickup_weapon("toan", 260, {magic = 9})
check(S10.choice and S10.choice.id == "weapon", "the choice is up")
S10.pick(2)
check(S10.equipped.toan == new_slot and S10.weapons.toan[old_slot] == nil, "took the found weapon; the held one is gone")
check(S10.weapons.toan[new_slot].magic == 9 + math.floor(old_magic / 4), "and it absorbed a quarter of the old one",
      S10.weapons.toan[new_slot].magic)
check(S10.storage.run.weapons.toan.slot == new_slot, "the run follows the new weapon")
local attack = S10.weapons.toan[new_slot].attack
local goro_slot = S10.pickup_weapon("goro", 316, {attack = 40})
check(S10.weapons.goro[goro_slot] == nil and not S10.choice, "a weapon for an undrafted ally is absorbed, no choice")
check(S10.weapons.toan[new_slot].attack >= attack + 10, "into the active character's weapon", S10.weapons.toan[new_slot].attack)
S10.weapons.toan[new_slot].durability_f = 0; S10.tick(1)
check(S10.find_toast("weapon broke"), "a weapon at 0 durability breaks the run", S10.last_toast())
S10.tick(200)
check(S10.context == "title" and S10.storage.run == false and S10.storage.meta.deaths == 1, "and ends it as a death")
check(S10.page().lines[#S10.page().lines]:find("Weapon broke"), "the title says the weapon broke", S10.page().lines[#S10.page().lines])
-- the broken starter (Broken Dagger) counts too
start_run(S10); run_floor(S10)
S10.weapons.toan[S10.equipped.toan].item_no = 257; S10.tick(1)
check(S10.storage.run.broken == true, "a starter turned into its broken version ends the run")
S10.tick(200)

-- 10. The durability unlocks and the paged Norune Eternal -----------------------------------------------
print("Scenario 10: Whetstone, Repair Kit and the sky")
S10.storage.meta.eternal.whetstone = 2
S10.storage.meta.eternal.kit = 1
local S11 = boot({storage = S10.storage})
S11.open_title_mode()
S11.select("eternal")
check(S11.sky_node("whetstone").rank == "2/3" and S11.sky_node("kit").rank == "1/2", "the sky shows the ranks owned",
      S11.sky_node("whetstone").rank)
S11.select("back")
start_run(S11)
local starter11 = S11.weapons.toan[S11.equipped.toan]
check(starter11.durability == 30 + 20 and starter11.durability_f == 50, "Whetstone 2/3: +20 durability, full", starter11.durability)
check((S11.items["chronicle:item:177"] or 0) == 3, "Repair Kit 1/2: a third Repair Powder", S11.items["chronicle:item:177"])

-- 11. The Moon Shard table: a fall in the third biome pays about 15 ------------------------------------
print("Scenario 11: Moon Shards for a fall in the third biome")
local S12 = boot()
start_run(S12); run_floor(S12); finish_biome(S12)
S12.tick(20); run_floor(S12); finish_biome(S12)
S12.tick(20); run_floor(S12); S12.exit_gate(); run_floor(S12)
S12.game_over(); S12.tick(30)
check(S12.storage.run == false and S12.storage.meta.deaths == 1, "fell on the third biome's second floor")
check(S12.storage.meta.shards >= 12 and S12.storage.meta.shards <= 18, "a fall in the third biome banks about 15 Moon Shards",
      S12.storage.meta.shards)

-- 12. Sky effects: a start loaded with unlocks, the Pacts, and the Heat payout ------------------------------
print("Scenario 12: sky effects and Heat")
local S14 = boot({storage = {meta = {eternal = {fullparty = 1, purse = 1, heart = 2, baker = 1, gem = 1, antidote = 1,
                                                 crowded = 2, sprawl = 1, hardened = 1}}}})
start_run(S14)
check(#S14.storage.run.drafted == 6, "Full Party drafts all six", #S14.storage.run.drafted)
check(S14.storage.run.heat == 4, "the run carries its Heat: Crowded 2, Sprawling 1, Hardened 1", S14.storage.run.heat)
check(S14.gilda >= 300, "Coin Purse: 300 Gilda", S14.gilda)
check(S14.max_hp.toan == 75 + 20, "Steady Heart 2/3: +20 maximum HP", S14.max_hp.toan)
check((S14.items["chronicle:item:148"] or 0) == 4 and (S14.items["chronicle:item:151"] or 0) == 2, "Baker's Bundle and Antidote Kit",
      S14.items["chronicle:item:148"])
run_floor(S14)
check(S14.modifiers and S14.modifiers.monsters == 50 and S14.modifiers.rooms == 30, "Crowded Halls and Sprawling Floors reach the floor",
      S14.modifiers and S14.modifiers.monsters)
-- Moonblade: a first hit lands three times over, a second hit only once
do
  local SM = boot({storage = {meta = {eternal = {moonblade = 1}}}})
  start_run(SM); run_floor(SM)
  local m; for _, x in ipairs(SM.monsters) do if x.alive then m = x; break end end
  local full = m.max_hp
  m.hp = full - 10; SM.tick(30)
  check(m.hp == full - 30, "Moonblade: the first hit lands three times", full .. " -> " .. m.hp)
  m.hp = m.hp - 10; SM.tick(30)
  check(m.hp == full - 40, "and a second hit only once", m.hp)
end
local before = S14.storage.meta.shards
S14.exit_gate(); run_floor(S14)
S14.game_over(); S14.tick(30)
local banked = S14.storage.meta.shards - before
check(S14.storage.run == false and banked >= 1, "a fall at Heat 4 still banks shards", banked)
check((S14.storage.meta.marks.toan or 0) == 0, "no Marks for a run that cleared no biome")

-- 13. Mod-built sky nodes: Blessed Choice, Chosen of the Moon, Signatures, Twin Wardens, Loadouts --------------
print("Scenario 13: Blessed Choice, Signatures, Twin Wardens and Loadouts")
do
  local marks = {toan = 20, goro = 20, ungaga = 20, osmond = 20, ruby = 20}
  local S15 = boot({storage = {meta = {start_char = "goro", marks = marks, eternal = {
    moon = 1, choice = 1, chosen = 1, fullparty = 1, twinwardens = 1,
    toan_1 = 1, toan_3 = 1, toan_4 = 1, toan_5 = 1, goro_1 = 1, goro_3 = 1, goro_4 = 1, ruby_1 = 1, ruby_3 = 1, ruby_4 = 1,
    ungaga_2 = 1, ungaga_4 = 1, ungaga_5 = 1, osmond_1 = 1, osmond_3 = 1, osmond_4 = 1, osmond_5 = 1}}}})
  start_run(S15)
  check(S15.choice and S15.choice.id == "blessing" and #S15.choice.options == 3, "Blessed Choice offers three blessings on cards",
        S15.choice and S15.choice.title)
  local picked = S15.choice.options[2].title
  S15.pick(2); S15.tick(1)
  check(S15.choice and S15.choice.id == "blessing", "Osmond's extra blessing offers three more")
  for _, o in ipairs(S15.choice.options) do check(o.title ~= picked, "without the one already taken", o.title) end
  S15.pick(1); S15.tick(1)
  check(not S15.choice and S15.find_toast(picked), "the pick is taken and the offer closes", picked)
  local held = S15.storage.run.blessings
  check(#held == 3 and held[1] == "atla", "Atla Sight from Atlamillia's Chosen, then two picked", table.concat(held, ","))
  check(S15.tuning and S15.tuning.map_reveal == true and S15.tuning.monster_reveal == true, "Atla Sight maps the floor and shows monsters")
  check(S15.formulas.gauntlet_sig_goro.value == 1.15 and S15.formulas.gauntlet_sig_goro.character_id == 2, "Berserker: Goro +15%")
  check(math.abs(S15.formulas.gauntlet_sig_ruby.value - 1.32) < 1e-9, "Flame Rings and Pyromancer: Ruby x1.32", S15.formulas.gauntlet_sig_ruby.value)
  check(S15.player_formulas.gauntlet_sig_bulwark.value == 0.85, "Bulwark: Goro takes 15% less")
  check(S15.formulas.gauntlet_sig_aim.chance == 10, "Steady Aim: 10% double for Osmond")
  check(S15.tuning.recoil_scale == 0.5, "Iron Grip: Goro, active, takes half the recoil", S15.tuning.recoil_scale)
  local sockets = 0; for _, d in ipairs(S15.catalog) do if d.owner == "toan" and not d.mod_owned then sockets = d.socket_count end end
  check(sockets == 4, "Swordsman: Toan's weapons take a fourth attachment", sockets)
  S15.active = "toan"; S15.tick(16)
  check(S15.tuning.attack_anim_speed == 1.15 and math.abs(S15.tuning.run_speed - 1.08) < 1e-9 and S15.tuning.recoil_scale == 1,
        "Dagger Dance and Wanderer when Toan is out", S15.tuning.run_speed)
  -- Totem Guard: the first hit on Ungaga is turned aside, the next lands
  S15.active = "ungaga"; S15.hp.ungaga = S15.max_hp.ungaga; S15.tick(2)
  S15.hp.ungaga = S15.hp.ungaga - 20; S15.tick(1)
  check(S15.hp.ungaga == S15.max_hp.ungaga, "Totem Guard turns aside a hit", S15.hp.ungaga)
  S15.hp.ungaga = S15.hp.ungaga - 20; S15.tick(1)
  check(S15.hp.ungaga == S15.max_hp.ungaga - 20, "and recharges before the next", S15.hp.ungaga)
  -- Moonsinger
  S15.active = "ruby"; S15.hp.ruby = 10; S15.tick(70)
  S15.emit("game.enemy_hit", {attacker = 3, damage = 5}); S15.tick(1)
  S15.emit("game.enemy_hit", {attacker = 3, damage = 5}); S15.tick(1)
  check(S15.hp.ruby == 11, "Moonsinger: Ruby's hit heals 1, once a second", S15.hp.ruby)
  -- Twin Wardens: the floor clears only when both have fallen
  S15.active = "goro"
  run_floor(S15)
  for _ = 2, 4 do S15.exit_gate(); run_floor(S15) end
  local placed = S15.enter_warden_room()
  local key, twin = placed[1], placed[2]
  check(key and twin and #placed == 2 and S15.find_toast("not alone"), "Twin Wardens: a second Warden stands beside it", #placed)
  local biome = S15.storage.run.pos
  S15.kill(key); S15.tick(30)
  check(S15.storage.run.pos == biome and S15.bars.warden, "one Warden down: the floor holds", S15.bars.warden and S15.bars.warden.label)
  S15.kill(twin); S15.tick(30)
  check(S15.find_toast("Warden felled") or S15.storage.run.awaiting, "both down: the Warden floor is cleared")
  -- Swordsman's sockets go back when the run ends
  S15.game_over(); S15.tick(30)
  for _, d in ipairs(S15.catalog) do if d.owner == "toan" then sockets = d.socket_count end end
  check(sockets == 3, "the run's end restores Toan's sockets", sockets)
  -- Loadouts: save the switches, change them, load them back
  local store = F.deepcopy(S15.storage)
  store.meta.eternal.loadouts = 1
  local SL = boot({storage = store})
  SL.open_title_mode(); SL.select("eternal")
  SL.sky_act("chosen", "toggle")
  check(SL.storage.meta.off.chosen == true, "Chosen switched off")
  SL.sky_act("loadouts", "buy")
  check(entry_ids(SL) == "l1,l2,l3,l4,mode", "Cross on Loadouts opens its page", entry_ids(SL))
  SL.select("mode"); SL.select("l2")
  check(SL.page().entries[2].label:find("^Loadout 2: %d+ on, Heat 2"), "saved to Loadout 2", SL.page().entries[2].label)
  SL.select("back")
  check(SL.page().sky, "Circle goes back to the sky")
  SL.sky_act("chosen", "toggle")
  check(SL.storage.meta.off.chosen == nil, "Chosen back on")
  SL.sky_act("loadouts", "buy"); SL.select("l2")
  check(SL.storage.meta.off.chosen == true, "loading Loadout 2 switches Chosen off again")
end

-- 14. Engine-backed nodes: Blind Halls, Hardy, Clear Mind, Swift Swap, Barren, Second Wind, Cat's Nine Lives ---
print("Scenario 14: tuning nodes, Barren and the fatal guards")
do
  local SG = boot({storage = {meta = {start_char = "xiao", marks = {xiao = 20}, eternal = {
    blind = 1, hardy = 1, clearmind = 1, swift = 1, barren = 1, secondwind = 1, embassy = 1, xiao_5 = 1}}}})
  start_run(SG); run_floor(SG)
  check(SG.tuning.map_hidden == true and SG.tuning.status_duration == 0.5 and SG.tuning.swap_delay == 0,
        "Blind Halls, Hardy and Swift Swap reach the tuning")
  check(SG.tuning.status_immune and table.concat(SG.tuning.status_immune, ",") == "freeze,stamina", "Clear Mind: immune to Freeze and Stamina")
  check(SG.modifiers and SG.modifiers.chests == -100, "Barren: no chests on floor I", SG.modifiers and SG.modifiers.chests)
  check(SG.guards.xiao == 2 and SG.guards.toan == 0, "Xiao: Second Wind and Cat's Nine Lives; undrafted Toan none",
        SG.guards.xiao .. "/" .. SG.guards.toan)
  check(SG.fatal_hit("xiao") and SG.hp.xiao == 1 and SG.find_toast("Second Wind"), "a fatal hit: Second Wind first")
  check(SG.fatal_hit("xiao") and SG.find_toast("Nine Lives"), "then Cat's Nine Lives")
  SG.exit_gate(); run_floor(SG)
  check(SG.guards.xiao == 1, "the next floor: Second Wind again, the life spent for the biome", SG.guards.xiao)
  for _ = 3, 4 do SG.exit_gate(); run_floor(SG) end
  check(SG.modifiers.chests == nil, "Barren spares the Warden floor", SG.modifiers.chests)
  for _, w in ipairs(SG.enter_warden_room()) do SG.kill(w) end; SG.tick(2); SG.tick(350)
  SG.tick(20); pass_rest(SG); run_floor(SG)
  check(SG.guards.xiao == 2, "a new biome gives Xiao her life back", SG.guards.xiao)
  SG.game_over(); SG.tick(30)
  check(SG.guards.xiao == 0 and SG.guards.toan == 0, "the run's end clears the guards")
end

-- 15. Charged hits: Charged Fury, Lightning Fang, Ground Pound, Mountain's Might --------------------------------
print("Scenario 15: charged hits")
do
  local SC = boot({storage = {meta = {start_char = "goro", marks = {goro = 20, toan = 20}, eternal = {
    charged = 1, fullparty = 1, toan_2 = 1, goro_2 = 1, goro_5 = 1}}}})
  start_run(SC); run_floor(SC)
  check(SC.formulas.gauntlet_charged.value == 1.3 and SC.formulas.gauntlet_charged.charged == true, "Charged Fury: x1.3 on charged hits")
  local a, b = SC.monsters[1], SC.monsters[2]
  local hp_b = b.hp
  SC.emit("game.enemy_hit", {entity = a.handle, attacker = 2, damage = 20, charged = false}); SC.tick(1)
  check(b.hp == hp_b and not a.stopped, "a plain swing does nothing more")
  SC.emit("game.enemy_hit", {entity = a.handle, attacker = 2, damage = 20, charged = true}); SC.tick(1)
  check(b.hp == hp_b - 10, "Ground Pound: half the charged swing to the enemies nearby", b.hp)
  SC.emit("game.enemy_hit", {entity = a.handle, attacker = 0, damage = 20, charged = true}); SC.tick(1)
  check(a.stopped == 60, "Lightning Fang: Toan's charged hit stuns", a.stopped)
  for _ = 2, 4 do SC.exit_gate(); run_floor(SC) end
  local w = SC.enter_warden_room()[1]
  SC.tick(50)
  SC.emit("game.enemy_hit", {entity = w.handle, attacker = 2, damage = 20, charged = true}); SC.tick(1)
  check(w.stopped == 90, "Mountain's Might: a charged swing staggers the Warden", w.stopped)
end

-- 16. Per-character tuning: the dodges, Quick Draw, Pebble Storm, Orb Split, Genie's Daughter, Spear Reach -------
print("Scenario 16: each character's own tuning")
do
  local marks = {xiao = 20, ruby = 20, ungaga = 20, osmond = 20}
  local ST = boot({storage = {meta = {start_char = "goro", marks = marks, eternal = {fullparty = 1,
    xiao_1 = 1, xiao_2 = 1, xiao_4 = 1, ruby_2 = 1, ruby_5 = 1, ungaga_1 = 1, osmond_2 = 1}}}})
  start_run(ST); run_floor(ST)
  check(ST.tuning.dodge_power == 0 and ST.tuning.extra_shots == 0 and ST.tuning.reach_scale == 1, "Goro: none of them")
  local function as(c) ST.active = c; ST.tick(16); return ST.tuning end
  local t = as("xiao")
  check(t.gauge_refill == 1.5 and t.extra_shots == 1 and t.dodge_power == 1 and t.dodge_hop == true,
        "Xiao: Quick Draw, Pebble Storm and the Tumbler hop")
  t = as("ruby")
  check(t.extra_shots == 1 and t.shots_pierce == true and t.dodge_power == 0, "Ruby: Orb Split and Genie's Daughter")
  t = as("ungaga")
  check(t.reach_scale == 1.2 and t.extra_shots == 0, "Ungaga: Spear Reach")
  t = as("osmond")
  check(t.dodge_power == 2 and t.dodge_hop == false and t.dodge_invincible_frames == 20, "Osmond: Rocket Boost, twice as far")
end

-- 17. Twin Keys ------------------------------------------------------------------------------------------------
print("Scenario 17: Twin Keys")
do
  local SK2 = boot({storage = {meta = {eternal = {twinkeys = 1}}}})
  start_run(SK2); run_floor(SK2)
  local key = SK2.monsters[6].drop
  local carriers = 0
  for _, m in ipairs(SK2.monsters) do if m.drop == key then carriers = carriers + 1 end end
  check(carriers == 2 and SK2.find_toast("Twin Keys"), "two monsters carry the gate key", carriers)
  SK2.pickup_item(key); SK2.tick(1)
  check((SK2.items["chronicle:item:" .. key] or 0) == 0 and SK2.find_toast("One of two keys"), "the first key is not enough")
  SK2.pickup_item(key); SK2.tick(1)
  check((SK2.items["chronicle:item:" .. key] or 0) == 1 and SK2.find_toast("Both keys"), "the second opens the gate")
  for _ = 2, 4 do SK2.exit_gate(); run_floor(SK2) end
  carriers = 0
  for _, m in ipairs(SK2.monsters) do if m.alive and m.drop and m.drop >= 0 then carriers = carriers + 1 end end
  check(carriers == 1, "the Warden floor keeps one key", carriers)
end

-- 18. Endless Maze: a fourth floor before each Warden --------------------------------------------------------
print("Scenario 18: Endless Maze")
do
  local SM2 = boot({storage = {meta = {sigils = 0, eternal = {maze = 1}}}})
  start_run(SM2); run_floor(SM2)
  check(SM2.storage.run.maze == true and SM2.storage.run.heat == 3, "the run has Endless Maze, Heat 3", SM2.storage.run.heat)
  for _ = 2, 4 do SM2.exit_gate(); run_floor(SM2) end
  check(SM2.storage.run.slot == 4 and SM2.floor_label == "1-4", "a fourth floor: 1-4",
        SM2.floor_label)
  check(not SM2.find_toast("Warden awakens"), "no Warden yet")
  SM2.exit_gate(); run_floor(SM2)
  local mw = SM2.enter_warden_room()[1]
  check(SM2.storage.run.slot == 5 and mw and SM2.find_toast("Warden awakens"), "the Warden waits on the fifth", SM2.storage.run.slot)
  SM2.kill(mw); SM2.tick(2); SM2.tick(350); SM2.tick(20); pass_rest(SM2); run_floor(SM2)
  check(SM2.storage.run.pos == 2 and SM2.storage.run.depth == 6, "on to biome 2 after five floors", SM2.storage.run.depth)
  SM2.game_over(); SM2.tick(30)
  check(next(SM2.redirects or {}) == nil, "the run's end takes the redirects back")
  -- without the Maze, floor III's gate leads past IV
  local SN = boot()
  start_run(SN); run_floor(SN)
  for _ = 2, 4 do SN.exit_gate(); run_floor(SN) end
  SN.enter_warden_room()
  check(SN.storage.run.slot == 4 and SN.find_toast("Warden awakens") and SN.storage.run.depth == 4, "no Maze: III's gate goes to the Warden")
end

-- 19. Warden's Court: five Wardens on the last Warden floor -------------------------------------------------------
print("Scenario 19: Warden's Court")
do
  local SC2 = boot({storage = {meta = {sigils = 0, eternal = {court = 1}}, settings = nil}, overrides = {biome_count = 2}})
  start_run(SC2); run_floor(SC2); finish_biome(SC2)
  check(SC2.storage.run.pos == 2 and not SC2.find_toast("second Warden"), "the first biome's Warden stands alone")
  SC2.tick(20); run_floor(SC2)
  for _ = 2, 4 do SC2.exit_gate(); run_floor(SC2) end
  local court = SC2.enter_warden_room()
  check(#court == 5 and SC2.find_toast("Court is gathered"), "the last Warden floor holds five", #court)
  check(SC2.bars.warden and SC2.bars.warden.label == "WARDENS 5", "one bar for the court", SC2.bars.warden and SC2.bars.warden.label)
  for _, m in ipairs(court) do if m.alive then SC2.kill(m) end end
  SC2.tick(30)
  check(SC2.find_toast("Gauntlet is conquered"), "the court falls: the Gauntlet is won")
end

-- 20. The Companion path ------------------------------------------------------------------------------------------
print("Scenario 20: the companion")
do
  local SO = boot({storage = {meta = {start_char = "toan", sigils = 0, eternal = {fullparty = 1, companion = 1}}}})
  start_run(SO); run_floor(SO)
  check(SO.companion == nil, "the Companion setting is off by default: no ally comes out, even with the unlock")
  local SP = boot({overrides = {companion = true}, storage = {meta = {start_char = "toan", sigils = 0, eternal = {
    fullparty = 1, companion = 1, stances = 1, keenpartner = 1, twinstrike = 1, soulbond = 1}}}})
  start_run(SP); run_floor(SP)
  local second = SP.storage.run.drafted[2]
  check(SP.companion and SP.companion.character == second and SP.companion.stance == "target" and SP.companion.damage_scale == 1.25,
        "the first drafted ally comes out, after your lock-on target, Keen Partner x1.25", SP.companion and SP.companion.character)
  SP.action("stance"); SP.tick(16)
  check(SP.companion.stance == "aggressive" and SP.find_toast("anything near"), "Stances: aggressive")
  SP.action("stance"); SP.tick(16)
  check(SP.companion.stance == "passive", "then passive")
  SP.active = second; SP.tick(16)
  check(SP.companion.character == "toan", "switching to the companion trades places", SP.companion.character)
  -- Twin Strike and Soul Bond
  local m = SP.monsters[1]
  SP.emit("game.companion.hit", {entity = m.handle, character = "toan", damage = 5, killed = false, reward_exp = 6}); SP.tick(1)
  local before = m.hp
  SP.emit("game.enemy_hit", {entity = m.handle, attacker = 1, damage = 20}); SP.tick(1)
  check(m.hp == before - 2, "Twin Strike: +10% on the companion's target", before - m.hp)
  local w = SP.weapons[second][SP.equipped[second]]
  local abs = w.abs or 0
  SP.hp[second] = 50
  SP.emit("game.companion.hit", {entity = SP.monsters[2].handle, character = "toan", damage = 40, killed = true, reward_exp = 6}); SP.tick(1)
  check(SP.hp[second] > 50, "Soul Bond: the companion's kill restores some HP", SP.hp[second])
  check((w.abs or 0) == abs, "the companion's kill doesn't feed your weapon", (w.abs or 0) - abs)
  SP.game_over(); SP.tick(30)
  check(SP.companion == nil, "the run's end sends the companion back")
end

-- 20b. Shuffled floors --------------------------------------------------------------------------------------
print("Scenario 20b: shuffled floors")
do
  local SS
  for seed = 1, 40 do
    SS = boot({seed = seed, overrides = {floor_shuffle = true}})
    start_run(SS)
    local plan = SS.storage.run.plan
    if plan and plan[1] and plan[1][2] and plan[1][2] ~= 1 then break end
  end
  local plan = SS.storage.run.plan
  check(plan and plan[1][1] == 1, "1-1 is always the first biome's own dungeon", plan and plan[1][1])
  check(plan[1][2] ~= 1, "and later floors are drawn from any dungeon", plan[1][2])
  run_floor(SS)
  SS.exit_gate(); SS.tick(120); run_floor(SS)
  local run = SS.storage.run
  check(run.pos == 1 and run.slot == 2 and not run.suspended, "the gate led to 1-2, in another dungeon", run.slot)
  check(SS.dungeon == ({0, 1, 2, 3, 4})[plan[1][2]], "the run moved to the planned dungeon", SS.dungeon)
  check(not SS.find_toast("Off the Gauntlet route"), "without counting the stop on the way as off route")
end

-- 21. Shortcut doors ------------------------------------------------------------------------------------------
print("Scenario 21: shortcut doors")
do
  local SD = boot({storage = {meta = {eternal = {sprawl = 2}}}})
  start_run(SD); run_floor(SD)
  check(SD.shortcuts == 3, "floor I asks for shortcuts: one, plus one per Sprawling Floors rank", SD.shortcuts)
  check(SD.weapon_drops and SD.weapon_drops.unique == true and SD.weapon_drops.rare > 0,
        "chests never hold a weapon the party has, and often a stronger one", SD.weapon_drops and SD.weapon_drops.rare)
  SD.emit("game.dungeon.door_locked", {key = "chronicle:item:221", x = 2, y = 13}); SD.tick(1)
  check(SD.find_toast("Pitchdark Key is somewhere"), "a locked door names its key")
  SD.emit("game.dungeon.door_opened", {key = "chronicle:item:216", x = 2, y = 13}); SD.tick(1)
  check(SD.find_toast("Bone Key opens a shortcut"), "and its opening says so")
  local icons = 0; for id, stem in pairs(SD.item_icons or {}) do if stem:match("^key_") then icons = icons + 1 end end
  SD.tick(60)
  icons = 0; for id, stem in pairs(SD.item_icons or {}) do if stem:match("^key_") then icons = icons + 1 end end
  check(icons == 2 and SD.item_icons["chronicle:item:218"] == "key_shipcabin" and SD.item_icons["chronicle:item:217"] == nil,
        "only the second and later locks' keys wear colours; the first key stays native", icons)
  for _ = 2, 4 do SD.exit_gate(); run_floor(SD) end
  check(SD.shortcuts == 0, "the Warden floor has none", SD.shortcuts)
  SD.game_over(); SD.tick(30)
  check(SD.shortcuts == 0, "the run's end asks for none")
end

-- 22. A real boss as the Warden, in its sealed room ---------------------------------------------------------------
print("Scenario 22: boss Wardens")
do
  local SB = boot({overrides = {boss_wardens = 100}})
  start_run(SB); run_floor(SB)
  for _ = 2, 4 do SB.exit_gate(); run_floor(SB) end
  local placed = SB.enter_warden_room()
  local dran = placed[1]
  check(dran and dran.model == 78 and dran.grounded == true and dran.arena_slot == 0,
        "Divine Beast Cave's Warden is Dran, on the ground, in his arena's boss slot", dran and dran.model)
  local beside = 0
  for _, m in ipairs(placed) do if m ~= dran and dran and m.arena_origin == dran.arena_origin then beside = beside + 1 end end
  check(beside == 0, "Dran fights alone", beside)
  check(dran and dran.damage_scale == 1, "in the first biome Dran hits as hard as in his own story", dran and dran.damage_scale)
  check(dran and dran.hit_share == true, "any hero can hurt a Warden boss as the hero it suits best", dran and dran.hit_share)
  check(dran and dran.scale == 0.65, "Dran comes smaller, to fit his room and the camera", dran and dran.scale)
  -- shuffled so the Moon Sea comes first: Minotaur Joe takes Dran's place, with Dran's blows and life
  local joe, SJ
  for seed = 1, 60 do
    SJ = boot({overrides = {boss_wardens = 100, biome_shuffle = true}, seed = seed})
    start_run(SJ)
    if SJ.storage.run.biomes[1] == 5 then break end
  end
  if SJ.storage.run.biomes[1] == 5 then
    run_floor(SJ)
    for _ = 2, 4 do SJ.exit_gate(); run_floor(SJ) end
    joe = SJ.enter_warden_room()[1]
  end
  check(joe and joe.model == 83 and math.abs(joe.damage_scale - 20 / 125) < 1e-9,
        "Minotaur Joe as the first Warden hits as hard as Dran", joe and joe.damage_scale)
  -- (the fake gives every boss the same native HP, so Joe's own would be Dran's; floors may differ by a curse)
  local ratio = joe and dran and joe.max_hp / (dran.max_hp * 737 / 5899)
  check(ratio and ratio > 0.8 and ratio < 1.7, "and has the life Dran would have there, not his own", ratio)
  SB.auto_pick = false
  SB.kill(dran); SB.tick(2)
  check((SB.warden_released or 0) == 0 and not SB.find_toast("Warden felled"), "Dran fades out before his prize pauses the game",
        SB.warden_released)
  SB.tick(130)
  check(SB.warden_released == 1 and SB.find_toast("Warden felled"), "Dran falls: the doors open and the run moves on")
  local held = SB.dungeon
  SB.tick(600)
  check(SB.choice ~= nil and SB.dungeon == held and SB.pending_jump == nil,
        "the Warden's prize waits on its panel and the run stays put until it's taken", SB.choice and SB.choice.id)
  for _ = 1, 4 do if SB.choice then SB.pick(1); SB.tick(40) end end
  SB.auto_pick = nil
  SB.tick(120)
  check(SB.dungeon ~= held or SB.floor == 0, "once it's taken, the run moves on", SB.dungeon)
  SB.tick(350); SB.tick(20); pass_rest(SB); run_floor(SB)
  for _ = 2, 4 do SB.exit_gate(); run_floor(SB) end
  local utan = SB.enter_warden_room()[1]
  check(utan and utan.model == 79 and utan.grounded == nil, "Wise Owl Forest's Warden is Master Utan, free to leap", utan and utan.model)
  SB.game_over(); SB.tick(30)
  check(SB.warden_room == nil, "the run's end stops sealing Warden rooms")
end

print("Scenario 22b: bosses roaming as regular monsters")
do
  local SK = boot({overrides = {roaming_bosses = 100}})
  start_run(SK); SK.tick(20); SK.reveal_all(); SK.tick(400)
  local kin
  for _, m in ipairs(SK.spawned or {}) do if m.arena_slot == 0 and m.model >= 78 and m.model <= 83 then kin = m end end
  check(kin ~= nil and SK.find_toast("prowls this floor"), "a boss roams the floor as a regular monster", kin and kin.model)
  local CASTS = {[78] = 0, [79] = 0, [80] = 8, [81] = 1, [83] = 3}
  local cast = 0
  for _, m in ipairs(SK.spawned or {}) do
    if kin and m ~= kin and m.arena_origin == kin.arena_origin and (m.arena_slot or 0) >= 1 then cast = cast + 1 end
  end
  check(kin and CASTS[kin.model] == cast, "with its native cast beside it", kin and kin.model, cast)
  check(kin and kin.max_hp < 2000 and kin.max_hp >= 40 and kin.arena_origin ~= nil, "a modest HP pool, its arena where it stands",
        kin and kin.max_hp)
  check(kin and (kin.scale or 1) >= 0.6 and (kin.scale or 1) <= 1.0, "60-100% of its size", kin and kin.scale)
  -- in biome 1, a boss from further along hits as hard as Dran (by their heaviest native blows), a little less roaming
  local BLOW = {[78] = 20, [79] = 45, [80] = 74, [81] = 62, [83] = 125}
  local want = kin and math.max(0.15, math.min(6, 20 / BLOW[kin.model])) * 0.75
  local even = true
  for _, m in ipairs(SK.spawned or {}) do
    if kin and m.arena_origin == kin.arena_origin and math.abs((m.damage_scale or -1) - want) > 1e-9 then even = false end
  end
  check(kin and math.abs((kin.damage_scale or -1) - want) < 1e-9 and even, "its hits, and its cast's, scale to the run's biome",
        kin and kin.damage_scale, want)
  local shared = kin and kin.hit_share == true
  for _, m in ipairs(SK.spawned or {}) do
    if kin and m.arena_origin == kin.arena_origin and m.hit_share ~= true then shared = false end
  end
  check(shared, "any hero can hurt it and its cast")
  local SN = boot({overrides = {roaming_bosses = 0}})
  start_run(SN); SN.tick(20); SN.reveal_all(); SN.tick(400)
  local none = true
  for _, m in ipairs(SN.spawned or {}) do if m.model >= 78 then none = false end end
  check(none, "the setting at 0 keeps them away")
  check(SK.active_limit == 12, "a run keeps 12 monsters awake, not retail's 4", SK.active_limit)
  SK.game_over(); SK.tick(30)
  check(SK.active_limit == 4, "the run's end puts retail's 4 back", SK.active_limit)
end

-- 24. New moves --------------------------------------------------------------------------------------------------
print("Scenario 24: new moves")
do
  local SM = boot({overrides = {new_moves = true}, seed = 5})
  start_run(SM); run_floor(SM)
  local ids = {}
  for _, m in ipairs(SM.moves or {}) do ids[m.id] = m end
  check(ids.dash_slash and ids.spin_sweep and ids.counter_slash, "a run gives Toan the Dash Slash, the Spinning Sweep and the Counter Slash")
  check(ids.dash_slash and ids.dash_slash.animation == "toan_dash_thrust" and ids.spin_sweep.animation == "toan_whirlwind" and
        ids.counter_slash.animation == "toan_rising_slash", "each plays its own new animation")
  check(SM.animations.toan_whirlwind == "resources/anims/toan_whirlwind.json", "the animations are registered from the package")
  check(ids.evade_roll and ids.evade_roll.trigger == "dodge" and ids.evade_roll.animation == "toan_roll" and ids.evade_roll.invincible,
        "L2 with the stick pushed rolls, untouchable")
  check(ids.evade_backstep and ids.evade_backstep.trigger == "dodge_back" and ids.evade_backstep.lunge_angle == 180,
        "L2 with the stick at rest hops back")
  check(ids.evade_roll and ids.evade_roll.cancel and ids.evade_backstep.cancel and ids.evade_roll.cancel_after == 2,
        "either evade cancels an attack's recovery after its blow")
  check(SM.tuning and SM.tuning.first_person == false, "R2's first-person view is off in a run")
  check(ids.dash_slash.run_frames == 20 and ids.triple_shot.run_frames == 20, "a run attack needs a real run first")
  check(ids.triple_shot and ids.triple_shot.character == "xiao" and ids.triple_shot.animation == "xiao_triple_shot" and
        ids.triple_shot.hits[1].shot and ids.triple_shot.hits[1].count == 3, "Xiao's run attack is a three-shot fan")
  check(ids.evade_tumble and ids.evade_tumble.trigger == "dodge" and ids.evade_hop_shot and ids.evade_hop_shot.trigger == "dodge_back" and
        ids.evade_hop_shot.hits[1].shot, "Xiao's L2 tumbles, or hops back firing")
  local charged = 0
  for _, h in ipairs(ids.spin_sweep and ids.spin_sweep.hits or {}) do if h.charged then charged = charged + 1 end end
  check(charged == 5, "the sweep's hits count as charged", charged)
  -- The combo set: R2 heavy, R2 finishers after two and three blows, lock-on toward/away attacks, evade follow-ups.
  for _, c in ipairs({{"toan", {heavy = "heavy_chop", launcher = "launcher", spin = "spin_finisher", toward = "lunge_thrust",
                                away = "back_slash", evade = "roll_slash"}},
                      {"xiao", {heavy = "heavy_shot", launcher = "fan_shot", spin = "volley", toward = "dash_shot",
                                away = "retreat_shot", evade = "tumble_shot"}}}) do
    local who, set = c[1], c[2]
    local function is(id, trigger) return ids[id] and ids[id].character == who and ids[id].trigger == trigger end
    check(is(set.heavy, "heavy"), who .. ": R2 is a heavy attack")
    check(is(set.launcher, "combo_finisher") and ids[set.launcher].chain == 2, who .. ": A, A, R2 is a finisher")
    check(is(set.spin, "combo_finisher") and ids[set.spin].chain == 3, who .. ": A, A, A, R2 is a bigger finisher")
    check(is(set.toward, "lock_attack") and ids[set.toward].direction == "toward" and (ids[set.toward].lunge or 0) > 0,
          who .. ": locked on, toward + A lunges in")
    check(is(set.away, "lock_attack") and ids[set.away].direction == "away" and ids[set.away].lunge_angle == 180,
          who .. ": locked on, away + A strikes backing off")
    check(is(set.evade, "evade_attack"), who .. ": A out of an evade follows it up")
  end
  check(ids.spin_finisher and ids.spin_finisher.spin == 1, "Toan's three-blow finisher spins him round")
  check(ids.heavy_chop and ids.heavy_chop.animation == "toan_heavy_chop" and ids.roll_slash.animation == "toan_roll_slash" and
        ids.volley.animation == "xiao_volley" and ids.heavy_shot.animation == "xiao_heavy_shot", "the combo moves have their own animations")
  check(ids.fan_shot and ids.fan_shot.hits[1].count == 5 and (ids.fan_shot.gauge or 0) == 0 and (ids.volley.gauge or 0) == 0,
        "Xiao's finishers fan their shots and take no gauge")
  check(#SM.moves <= 160, "the moves fit the engine's 160", #SM.moves)
  -- Goro and Ungaga (melee) and Ruby and Osmond (casters) get the same controls from shared recipes.
  for who, kind in pairs({goro = "melee", ungaga = "melee", ruby = "caster", osmond = "caster"}) do
    local by = {}
    for _, m in ipairs(SM.moves or {}) do
      if m.character == who then by[m.trigger .. (m.chain and tostring(m.chain) or "") .. (m.direction or "")] = m end
    end
    for _, t in ipairs({"run_attack", "dodge", "dodge_back", "heavy", "combo_finisher2", "combo_finisher3", "lock_attacktoward",
                        "lock_attackaway", "evade_attack"}) do
      check(by[t] ~= nil and by[t].animation ~= nil and SM.animations[by[t].animation] ~= nil,
            who .. " has an animated " .. t .. " move")
    end
    if kind == "melee" then
      check(by.guard_attack ~= nil, who .. " has a guard counter")
    else
      check(by.heavy and by.heavy.hits[1].shot and by.combo_finisher2.hits[1].count == 5, who .. "'s attacks are casts")
    end
  end
  SM.game_over(); SM.tick(30)
  check(SM.moves == nil, "the run's end takes the moves back")
  local SN = boot({overrides = {new_moves = false}, seed = 5})
  start_run(SN); run_floor(SN)
  check(SN.moves == nil, "with the setting off there are no new moves")
end

-- 23. Weapon rarity, touches and legendaries ----------------------------------------------------------------------
print("Scenario 23: weapon rarity and touches")
do
  local SL = boot({overrides = {loot_rarity = true}, seed = 7})
  start_run(SL); run_floor(SL)
  -- found weapons roll a tier each: the name and colour on the weapon, the tier and touches on the card
  local tiers = {}
  for n = 1, 12 do
    local slot = SL.pickup_weapon("toan", 259 + (n % 3))
    SL.tick(2)
    local style = SL.weapon_styles and SL.weapon_styles["toan:" .. slot]
    local card = SL.choice and SL.choice.options[2]
    if style and card then
      tiers[card.subtitle:match("^(%a+)")] = true
      check(style.name == card.title and #style.name <= 22, "the found weapon's name is its style's", style.name)
      local tier = card.subtitle:match("^(%a+)")
      check(style.badge and style.badge[1].text == tier:upper() and style.details and #style.details >= 1,
            "its menu card shows the tier and what it does", style.badge and style.badge[1].text)
    end
    if SL.choice then SL.pick(1) end
    SL.tick(2)
  end
  local seen = 0; for _ in pairs(tiers) do seen = seen + 1 end
  check(seen >= 2, "found weapons roll different rarities", seen)
  SL.game_over(); SL.tick(30)
  check(next(SL.weapon_styles) == nil, "the run's end takes the styles back")

  -- Legendaries: Toan finds Moonfang, which unlocks it as a starting weapon
  local SG = boot({overrides = {loot_rarity = true, loot_tier = 5}, seed = 3})
  start_run(SG); run_floor(SG)
  local legendary_name, gold
  for _ = 1, 40 do
    local slot = SG.pickup_weapon("toan", 259)
    SG.tick(2)
    local style = SG.weapon_styles and SG.weapon_styles["toan:" .. slot]
    if style and style.name ~= "Moonfang" then legendary_name, gold = style.name, style.color end
    if SG.find_toast("Moonfang found") then SG.pick(2); SG.tick(2); break end
    if SG.choice then SG.pick(1) end
    SG.tick(2)
  end
  check(legendary_name and gold and gold.r == 255 and gold.g == 170 and #legendary_name <= 22,
        "a rolled Legendary has its own name, in orange", legendary_name)
  check(SG.find_toast("Moonfang found"), "Moonfang turned up and unlocked")
  local held = SG.weapons.toan[SG.equipped.toan]
  check(held and held.item_no == 266, "and Toan took it", held and held.item_no)
  -- Lunar Arc: a charged hit arcs to three more enemies
  SG.reveal_all(); SG.tick(15)
  local hp = {}; for n = 2, 5 do hp[n] = SG.monsters[n].hp end
  local bursts = #SG.bursts
  SG.emit("game.enemy_hit", {entity = SG.monsters[1].handle, attacker = 0, damage = 20, charged = true}); SG.tick(1)
  local struck = 0; for n = 2, 5 do if SG.monsters[n].hp < hp[n] then struck = struck + 1 end end
  check(struck == 3 and #SG.bursts > bursts, "Lunar Arc: a charged hit arcs to three more enemies, sparking", struck)
  -- the next run starts with it
  SG.game_over(); SG.tick(30)
  SG.open_title_mode()
  check(SG.page().entries[3].id == "legend" and SG.page().entries[3].label == "Starting Weapon: Standard", "the title screen offers a starting weapon",
        SG.page().entries[3].label)
  SG.select("legend")
  check(SG.page().entries[3].label == "Starting Weapon: Moonfang", "Moonfang chosen", SG.page().entries[3].label)
  SG.select("start"); SG.tick(40); SG.tick(20)
  held = SG.weapons.toan[SG.equipped.toan]
  local style = SG.weapon_styles["toan:" .. SG.equipped.toan]
  check(held and held.item_no == 266 and style and style.name == "Moonfang" and style.color.r == 255, "the run starts with Moonfang in hand, in gold",
        held and held.item_no)
end

-- 25. Opar, the seventh hero (the Opar setting): a party of seven through a whole run ----------------------------
print("Scenario 25: Opar and a party of seven")
do
  -- off by default: six heroes, and a remembered Opar start falls back to Toan
  local SN = boot({storage = {meta = {start_char = "opar"}}})
  SN.open_title_mode()
  check(SN.page().entries[2].label == "Starting Character: Toan", "with Opar off, the title offers Toan", SN.page().entries[2].label)
  SN.select("start"); SN.tick(60)
  check(#SN.party == 6 and SN.active == "toan" and SN.storage.run.opar == false, "and the run is a party of six", #SN.party)

  -- an engine without registered characters keeps the six, the Opar setting or not
  local SU = boot({overrides = {opar = true}, fail_ops = {["characters.register_playable"] = true}})
  SU.open_title_mode(); SU.select("start"); SU.tick(60)
  check(#SU.party == 6 and SU.storage.run.opar == false, "without his registration the Opar setting adds no one", #SU.party)

  local SP = boot({overrides = {opar = true}, storage = {meta = {eternal = {fullparty = 1}}}})
  SP.open_title_mode()
  for _ = 1, 6 do SP.select("character") end
  check(SP.storage.meta.start_char == "opar" and SP.page().entries[2].label == "Starting Character: Opar", "the title cycles on to Opar",
        SP.page().entries[2].label)
  SP.select("character")
  check(SP.storage.meta.start_char == "toan", "and wraps back to Toan after him")
  for _ = 1, 6 do SP.select("character") end
  SP.select("start")
  check(#SP.party == 7 and SP.party[7] == "opar", "Start Run asks for a party of seven", #SP.party)
  SP.tick(60)
  local run = SP.storage.run
  check(SP.active == "opar" and run.opar == true and run.drafted[1] == "opar" and #run.drafted == 7,
        "the run opens as Opar with all seven drafted (Full Party)", SP.active .. " " .. #run.drafted)
  check(SP.overrides["dun/mainchara/c07d.chr"] and SP.overrides["dun/mainchara/c07d_face.png"], "his pack and portrait are registered")
  check(SP.overrides["dun/mainchara/c07d_face.png"] == "resources/opar/medallion.png", "his portrait is his round medallion")
  check(SP.overrides["commenu/dungeon/c07model.pak"] == "resources/opar/c07model.pak", "his item-menu model pack is registered")
  check(SP.overrides["sound/voice/voice106.snd"] == "resources/opar/voice106.snd", "his own voice set (croaks) is registered")
  check(SP.game.characters.register_playable({id = "opar", name = "Opar", pack = "dun/mainchara/c07d.chr"}).character_id == 6,
        "he is registered as the first playable character past the six (engine index 6)")
  run_floor(SP)
  local row = SP.menu_row("party", "opar")
  check(row and row.value == "Leading" and SP.menu_row("party", "toan").value == "Benched", "the run menu's Party tab shows him leading",
        row and row.value)
  -- his staffs: six registered on Toan's sixth weapon, each with its own model and icon; he starts with Driftwood
  local staffs = {}
  for _, d in ipairs(SP.catalog) do if d.mod_owned and tostring(d.id):match("opar_") then staffs[#staffs + 1] = d end end
  local looks = true
  for i, d in ipairs(staffs) do looks = looks and d.model == ("opst0%d"):format(i) and d.icon == ("opst0%d_icon"):format(i) and d.owner == "toan" end
  check(#staffs == 6 and looks and staffs[6].name == "Tidecaller", "his six staffs are registered, each with its own model and icon", #staffs)
  local described = true
  for _, d in ipairs(staffs) do described = described and type(d.description) == "table" and #d.description == 2 end
  check(described, "each staff has its own two-line description for the weapon menu")
  local held = SP.weapons.opar[SP.equipped.opar]
  check(held and held.item_no == staffs[1].native_item_no, "he starts with the Driftwood Staff in hand", held and held.item_no)
  check(not SP.weapons.opar[0] or SP.weapons.opar[0].item_no ~= 258, "Toan's dagger is gone from his bag")
  local style = SP.weapon_styles and SP.weapon_styles["opar:" .. SP.equipped.opar]
  check(style and style.name == "Driftwood Staff", "it goes by its own name", style and style.name)
  -- his spits, on top of Toan's controls: each plays its own motion, and every glob leaves his mouth as a blue blob
  local omoves = {}
  for _, m in ipairs(SP.moves or {}) do if m.character == "opar" then omoves[m.id] = m end end
  check(omoves.opar_spit and omoves.opar_spit.trigger == "combo_finisher" and omoves.opar_spit.chain == 2 and
        omoves.opar_gob and omoves.opar_gob.chain == 3 and omoves.opar_bubble and omoves.opar_bubble.trigger == "charge_release" and
        omoves.opar_back_hop and omoves.opar_back_hop.trigger == "dodge_back", "Opar gets Spit, Gob, Bubble and Back Hop")
  local mouth = true
  for _, m in pairs(omoves) do
    check(SP.animations[m.animation] == "resources/anims/" .. m.animation .. ".json", "his " .. m.id .. " plays its own motion")
    for _, h in ipairs(m.hits or {}) do
      if h.shot then mouth = mouth and h.from == "jnt12_1" and h.cell == 8 and h.burst ~= nil end
    end
  end
  for _, id in ipairs({"opar_spit", "opar_gob", "opar_bubble", "opar_back_hop"}) do
    for _, h in ipairs(omoves[id].hits) do mouth = mouth and h.shot end
  end
  check(mouth, "every glob leaves his mouth, drawn as the blue blob, and splashes")
  check(omoves.opar_gob.hits[1].count == 3 and omoves.opar_bubble.hits[1].size > 2, "Gob fans three globs; Bubble is a big one")
  -- his frog kit
  local kit = {opar_belly_slide = "run_attack", opar_staff_swat = "guard_attack", opar_frog_hop = "dodge",
               opar_leap_strike = "evade_attack", opar_tongue_lash = "lock_attack", opar_croak = "heavy"}
  for id, trigger in pairs(kit) do check(omoves[id] and omoves[id].trigger == trigger, "Opar's " .. id .. " is on " .. trigger) end
  check(omoves.opar_croak.gauge == 50 and omoves.opar_staff_swat.spin == 1 and omoves.opar_leap_strike.hits[2].shot,
        "the Croak takes half the gauge, the Swat spins, the Leap Strike spits off the top")
  -- the Tongue Lash's first hit yanks its enemy in; the Croak stuns what it reaches
  local lashed = SP.monsters[2] or SP.monsters[1]
  local knocks = #SP.knocks
  SP.emit("game.player.move", {id = "moonmod.roguelike:opar_tongue_lash", owner = "moonmod.roguelike", character = "opar"}); SP.tick(1)
  SP.emit("game.enemy_hit", {entity = lashed.handle, attacker = 6, damage = 3}); SP.tick(1)
  SP.emit("game.enemy_hit", {entity = lashed.handle, attacker = 6, damage = 3}); SP.tick(1)
  check(#SP.knocks == knocks + 1 and SP.knocks[#SP.knocks] == lashed.handle, "the Tongue Lash yanks the enemy it caught, once",
        #SP.knocks - knocks)
  SP.emit("game.player.move", {id = "moonmod.roguelike:opar_croak", owner = "moonmod.roguelike", character = "opar"}); SP.tick(1)
  lashed.stopped = nil
  SP.emit("game.enemy_hit", {entity = lashed.handle, attacker = 6, damage = 1}); SP.tick(1)
  check((lashed.stopped or 0) >= 90 or not lashed.alive, "the Croak stuns what it reaches", lashed.stopped)
  -- the Jump Slam: a top charge with a full gauge; he leaps, a cloud of smoke, the giant Opar slams down and gets up,
  -- a puff of smoke and he is himself; the slam back a minute later
  local order = {}
  for i, m in ipairs(SP.moves) do order[m.id] = i end
  check(omoves.opar_jump_slam and omoves.opar_jump_slam.trigger == "charge_release" and omoves.opar_jump_slam.gauge == 100 and
        order.opar_jump_slam < order.opar_bubble, "the Jump Slam takes a top charge and the full gauge, ahead of the Bubble")
  local function has(id) for _, m in ipairs(SP.moves or {}) do if m.id == id then return true end end end
  local smokes = 0
  for _, k in ipairs(SP.bursts) do if k == "smoke" then smokes = smokes - 1 end end
  SP.emit("game.player.move", {id = "moonmod.roguelike:opar_jump_slam", owner = "moonmod.roguelike", character = "opar"})
  SP.tick(6)
  for _, k in ipairs(SP.bursts) do if k == "smoke" then smokes = smokes + 1 end end
  local slam = SP.played and SP.played[#SP.played]
  check(SP.last_form and SP.last_form.pack == "dun/mainchara/c07f.chr" and SP.last_form.frames.weapon == "r_hand" and SP.last_form.scale < 1,
        "after the leap he becomes the monster's model (smaller, its right hand for his grip)")
  check(slam and slam.id == "opar_form_slam" and slam.form == "dun/mainchara/c07f.chr", "as the monster he slams down at once")
  check(SP.form == nil and smokes == 2 and has("opar_spit") and not has("opar_jump_slam") and not has("opar_form_slam"),
        "then a puff of smoke and he is himself, the slam cooling down", smokes)
  SP.tick(3600)
  check(has("opar_jump_slam"), "a minute later the Jump Slam is back")
  local named, err = SP.game.weapons.give({id = "chronicle:weapon:261", character = "opar"})
  check(named and named.added and SP.weapons.opar[named.slot].item_no == 261, "Toan's weapons can be given to Opar by name", err)
  if named then SP.weapons.opar[named.slot] = nil end
  check(not SP.game.weapons.give({id = "chronicle:weapon:301", character = "opar"}), "Xiao's cannot")
  -- a chest weapon for him (engine character 6) is his, and his hits count as his
  local slot = SP.pickup_weapon("opar", 259); SP.tick(2)
  local found_staff
  for s2 = 0, 10 do
    local w = SP.weapons.opar[s2]
    if w and s2 ~= SP.equipped.opar then found_staff = w end
  end
  check(not SP.weapons.opar[slot] or SP.weapons.opar[slot].item_no ~= 259, "a weapon he finds is not Toan's sword...")
  check(found_staff and found_staff.item_no >= staffs[1].native_item_no and found_staff.item_no <= staffs[5].native_item_no,
        "...but the staff of the dungeon it came in", found_staff and found_staff.item_no)
  check(SP.choice and SP.choice.id, "a weapon he finds offers the keep-or-melt choice", SP.choice and SP.choice.id)
  if SP.choice then SP.pick(1); SP.tick(2) end
  SP.emit("game.enemy_hit", {entity = SP.monsters[1].handle, attacker = 6, damage = 5}); SP.tick(1)
  check(not SP.find_toast("not drafted"), "his hits and switches raise no draft bounce")
  -- a Bubble that hits splashes the enemies round it
  local function damaged() local n = 0; for _, m in ipairs(SP.monsters) do n = n + ((m.max_hp or 0) - (m.hp or 0)) end; return n end
  local before = damaged()
  SP.emit("game.player.move", {id = "moonmod.roguelike:opar_bubble", owner = "moonmod.roguelike", character = "opar"}); SP.tick(1)
  SP.emit("game.enemy_hit", {entity = SP.monsters[1].handle, attacker = 6, damage = 10, charged = true}); SP.tick(1)
  check(damaged() > before, "a Bubble splashes the enemies round what it hits", damaged() - before)

  -- every weapon the run hands out (Warden drops among them) names its holder, and each one fits
  local given, refused = 0, 0
  local give = SP.game.weapons.give
  SP.game.weapons.give = function(a)
    local r, err = give(a)
    if type(a) == "table" and a.character then given = given + 1; if not r then refused = refused + 1 end end
    return r, err
  end
  for _ = 1, 5 do run_floor(SP); finish_biome(SP); SP.tick(20) end
  check(given >= 5 and refused == 0, "the Wardens' weapons go to a named holder, and fit", given .. " given, " .. refused .. " refused")
  SP.tick(30)
  check(SP.context == "title" and SP.storage.meta.wins == 1, "the party of seven wins the whole run", SP.context)
  check(SP.storage.run == false, "and no run is left in storage")
end

-- 26. The floor's entry scene plays out before the drafted leader comes back --------------------------------------
print("Scenario 25b: Opar's Signature sky")
do
  local SS = boot({overrides = {opar = true}, storage = {meta = {start_char = "opar",
    eternal = {fullparty = 1, opar_1 = 1, opar_2 = 1, opar_3 = 1, opar_4 = 1, opar_5 = 1}}}})
  SS.open_title_mode()
  SS.select("start")
  SS.tick(60)
  run_floor(SS)
  local m = {}
  for _, mv in ipairs(SS.moves or {}) do if mv.character == "opar" then m[mv.id] = mv end end
  check(m.opar_gob and m.opar_gob.hits[1].count == 5, "Big Mouth: the Gob fires five globs", m.opar_gob and m.opar_gob.hits[1].count)
  check(SS.formulas.gauntlet_sig_opar and math.abs(SS.formulas.gauntlet_sig_opar.value - 1.2) < 1e-9 and
        SS.formulas.gauntlet_sig_opar.character_id == 6, "Spitter: Opar deals 20% more")
  -- Bog Hop: the hop leaves a puddle that slows those near where he lands
  local slowed = SS.monsters[1]
  slowed.slowed = nil
  SS.emit("game.player.move", {id = "moonmod.roguelike:opar_frog_hop", owner = "moonmod.roguelike", character = "opar"})
  SS.tick(30)
  local any = 0
  for _, k in ipairs(SS.bursts) do if k == "heal" then any = any + 1 end end
  check(any > 0, "Bog Hop: a puddle as he lands")
  -- Old Toad and the Keystone: the slam heals him and comes back in half the time, wider
  SS.game.player.set({hp = 10, character = "opar"})
  SS.emit("game.player.move", {id = "moonmod.roguelike:opar_jump_slam", owner = "moonmod.roguelike", character = "opar"})
  SS.tick(2)
  local slam
  for _, mv in ipairs(SS.moves or {}) do if mv.id == "opar_form_slam" then slam = mv end end
  check(slam and slam.hits[1].radius == 40, "King of the Moon Sea: the big slam reaches wider", slam and slam.hits[1].radius)
  SS.tick(6)
  check(SS.hp.opar > 10, "Old Toad: the slam heals him", SS.hp.opar)
  local function has(id) for _, mv in ipairs(SS.moves or {}) do if mv.id == id then return true end end end
  SS.tick(1800)
  check(has("opar_jump_slam"), "King of the Moon Sea: the Jump Slam is back within half a minute")
end

print("Scenario 25c: Opar's star")
do
  -- without the Opar setting: no star and no sky of his until a run has met him
  local SA = boot({storage = {meta = {shards = 100, eternal = {embassy = 1}}}})
  SA.open_title_mode(); SA.select("eternal")
  check(SA.sky_node("oparstar") == nil and SA.sky_node("opar_1") == nil, "before he is met, neither his star nor his sky shows")
  SA.sky_act("oparstar", "buy")
  check(SA.storage.meta.eternal.oparstar == nil, "a hidden star cannot be bought")
  -- met (the Moon Sea Warden beaten): his star and sky show, and bought he joins every run
  local SB = boot({storage = {meta = {shards = 100, opar_met = true, eternal = {embassy = 1}}}})
  SB.open_title_mode(); SB.select("eternal")
  check(SB.sky_node("oparstar") and SB.sky_node("oparstar").state == "open" and SB.sky_node("opar_1"),
        "once he is met his star rises, open to buy, and his sky shows")
  SB.sky_act("oparstar", "buy")
  check(SB.storage.meta.eternal.oparstar == 1 and SB.storage.meta.shards == 70, "his star costs 30 Moon Shards", SB.storage.meta.shards)
  local SC = boot({storage = {meta = {shards = 100, opar_met = true, eternal = {embassy = 1, fullparty = 1, oparstar = 1}}}})
  SC.open_title_mode()
  SC.select("start")
  SC.tick(60)
  check(SC.storage.run.opar == true and #SC.party == 7, "with his star a run has Opar in its party, no setting needed", #SC.party)
  -- Opar as the companion: switched out, he comes out beside you and spits his blue glob from range
  local SD = boot({overrides = {opar = true, companion = true}, storage = {meta = {start_char = "opar", eternal = {fullparty = 1, companion = 1}}}})
  SD.open_title_mode()
  SD.select("start")
  SD.tick(60)
  run_floor(SD)
  SD.game.party.set_active({id = "toan"}); SD.tick(20)
  check(SD.companion and SD.companion.character == "opar" and SD.companion.shot and SD.companion.shot.cell == 8,
        "switched out, Opar is the companion and spits his glob", SD.companion and SD.companion.character)
end

print("Scenario 26: entry scene")
do
  local SE = boot({storage = {meta = {start_char = "ruby"}}})
  SE.entry_scene = 90
  start_run(SE)
  local leader = SE.storage.run.leader or SE.storage.run.drafted[1]
  if leader ~= "toan" then
    check(SE.active == "toan" and not SE.find_toast("not drafted"), "under the entry scene Toan stays, and nothing bounces",
          SE.active)
    SE.tick(120)
    check(SE.active == leader and not SE.find_toast("not drafted"), "once it ends, the leader is back quietly", SE.active)
  else
    check(true, "the leader is Toan (nothing to switch)")
  end
end

-- 27. The Genie's Lair: each shape of the finale, with the Court on the last Warden floor before it ------------------
print("Scenario 27: the Genie's Lair")
do
  local seen, slots_ok, hands_checked = {}, true, false
  for seed = 1, 40 do
    local SG = boot({seed = seed, overrides = {biome_count = 1, genie_finale = true}, storage = {meta = {sigils = 0, eternal = {court = 1}}}})
    start_run(SG); run_floor(SG); finish_biome(SG)
    SG.tick(20)
    local plan
    if SG.storage.run and SG.storage.run.lair == "in" then
      SG.enter_warden_room()
      plan = SG.storage.run.genie
      -- a pink Genie's hand broken outside its own blow: its integer is held at -1 while he stands, so his eye opens
      if plan and plan.forms[1].key == "pink" and not hands_checked then
        local pink, hand
        for _, m in ipairs(SG.spawned) do
          if m.alive and m.model == 84 then pink = m elseif m.alive and m.model == 86 then hand = m end
        end
        check(pink.hit_reach == 48, "the pink Genie's eye is widened so a blade can reach it", pink.hit_reach)
        SG.kill(hand); SG.tick(40)
        local held = 0
        for _, w in ipairs(SG.script_ints or {}) do if w.entity == pink.handle and w.index == 1 and w.value == -1 then held = held + 1 end end
        check(held >= 2, "a broken hand's integer is held at -1 on the pink Genie", held)
        hands_checked = true
      end
      local bosses = 0
      for _ = 1, 3 do
        local live = {}
        for _, m in ipairs(SG.spawned) do if m.alive and (m.model == 84 or m.model == 106) and m.arena_slot == 0 then live[#live + 1] = m end end
        if #live == 0 then break end
        bosses = bosses + #live
        for _, m in ipairs(SG.spawned) do if m.alive and m.arena_slot then m.alive = false; if m.arena_slot == 0 then m.alive = true; SG.kill(m) end end end
        SG.tick(200)
      end
      SG.tick(400)
      -- the pink Genie's hands (his eye opens once both are broken) and beam (he waits on it) always come; a dark pillar
      -- always raises its shade
      for _, form in ipairs(plan and plan.forms or {}) do
        local has = {}
        for _, n in ipairs(form.slots) do has[n] = true end
        if form.key == "pink" and not (has[1] and has[2] and has[5] and has[6]) then slots_ok = false end
        if form.key == "dark" and ((has[3] and not has[1]) or (has[7] ~= has[8])) then slots_ok = false end
      end
      if plan and bosses == 2 and SG.context == "title" and SG.storage.meta.wins == 1 then seen[plan.shape] = (seen[plan.shape] or 0) + 1 end
    end
    if seen.pink_dark and seen.dark_pink and seen.both then break end
  end
  check(seen.pink_dark and seen.dark_pink and seen.both, "every shape of the finale is fought to a win: pink then dark, dark then pink, both at once",
        string.format("%s/%s/%s", seen.pink_dark, seen.dark_pink, seen.both))
  check(slots_ok, "each form's helpers keep what its scripts wait on")
  local SN = boot({overrides = {biome_count = 1}})
  start_run(SN); run_floor(SN); finish_biome(SN); SN.tick(30)
  check(SN.find_toast("Gauntlet is conquered") and SN.context == "title", "without the finale the last Warden wins the run")
end

-- 28. The Rest floor's other way on: the Cursed Path --------------------------------------------------------------
print("Scenario 28: the Cursed Path")
do
  local SC = boot({overrides = {biome_count = 3}})
  start_run(SC); run_floor(SC)
  for _ = 2, 4 do SC.exit_gate(); run_floor(SC) end
  for _, w in ipairs(SC.enter_warden_room()) do if w.alive then SC.kill(w) end end
  SC.tick(2); SC.tick(350); SC.tick(20)
  check(SC.storage.run.pos == 2 and SC.storage.run.slot == 0, "the first Warden leads to the Rest floor", SC.storage.run.slot)
  SC.tick(60)
  local key = "chronicle:item:194"
  check((SC.items[key] or 0) == 1, "with the gate key in the bag")
  SC.take_stairs(); SC.tick(120); run_floor(SC)
  local r = SC.storage.run
  check(r.cursed_biome == 2 and (SC.items[key] or 0) == 0 and SC.find_toast("Cursed Path: every floor"),
        "the stairs take the Cursed Path, and the unused gate key goes back", SC.items[key])
  check(r.pos == 2 and r.slot == 1 and SC.dungeon == 1 and SC.floor == 18 and not SC.back, "on to 2-1, not down to a back floor",
        tostring(SC.dungeon) .. ":" .. tostring(SC.floor))
  local all = true
  for slot = 1, 3 do
    if slot > 1 then SC.exit_gate(); run_floor(SC) end
    if not (SC.hud_icons.curse and SC.modifiers and SC.modifiers.chests == 50) then all = false end
  end
  check(all, "every floor before the Warden is cursed, with richer chests")
  check(SC.menu_row("run", "curse").enabled == false, "the Cursed Gate has nothing left to curse there")
  SC.exit_gate(); run_floor(SC)
  check(not SC.hud_icons.curse and SC.storage.run.slot == 4, "the Warden's floor is not cursed")
  local blessings = #SC.storage.run.blessings
  for _, w in ipairs(SC.enter_warden_room()) do if w.alive then SC.kill(w) end end
  SC.tick(2); SC.tick(350); SC.tick(20)
  check(SC.find_toast("Miracle cache") and #SC.storage.run.blessings == blessings + 2,
        "the Cursed Path's Warden pays out twice: a cache and a second blessing", #SC.storage.run.blessings - blessings)
  check(SC.storage.run.pos == 3 and SC.storage.run.slot == 0, "then the next Rest floor")
  pass_rest(SC); run_floor(SC)
  check(SC.storage.run.slot == 1 and not SC.hud_icons.curse, "and the next biome is back to normal")
  -- with the setting off, a Warden leads straight on
  local SO = boot({overrides = {rest_rooms = false}})
  start_run(SO); run_floor(SO)
  for _ = 2, 4 do SO.exit_gate(); run_floor(SO) end
  for _, w in ipairs(SO.enter_warden_room()) do if w.alive then SO.kill(w) end end
  SO.tick(2); SO.tick(350); SO.tick(20)
  check(SO.storage.run.pos == 2 and SO.storage.run.slot == 1 and SO.floor == 18, "with Rest floors off the Warden leads straight to 2-1",
        tostring(SO.dungeon) .. ":" .. tostring(SO.floor))
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  print("Last toasts:"); for i = math.max(1, #S.toasts - 5), #S.toasts do print("  " .. S.toasts[i]) end
  os.exit(1)
end
