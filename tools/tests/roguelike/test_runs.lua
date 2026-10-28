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
local function settings(over) local s = F.deepcopy(defaults); for k, v in pairs(over or {}) do s[k] = v end; return s end
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
local function finish_biome(S)
  for _ = 2, 4 do S.exit_gate(); run_floor(S) end
  S.reveal_all(); S.tick(30)
  S.kill(S.monsters[6]); S.tick(2)
  S.tick(350)
end
local function entry_ids(S) local t = {}; for _, e in ipairs(S.page().entries or {}) do t[#t + 1] = e.id end; return table.concat(t, ",") end

-- 1. The title mode and a full five-biome victory ------------------------------------------------
print("Scenario 1: title mode, full run to victory")
local S = boot()
local regs = 0; for _ in pairs(S.registered) do regs = regs + 1 end
check(regs == 5, "five gauntlet dungeons registered", regs)
check(S.page() and S.page().label == "Dark Genie's Gauntlet" and S.page().title == "DARK GENIE'S GAUNTLET", "title mode registered")
check(entry_ids(S) == "start,character,eternal,records", "root page entries", entry_ids(S))
S.open_title_mode()
S.select("character")
check(S.storage.meta.start_char == "xiao" and S.page().entries[2].label:find("Xiao"), "Starting Character cycles", S.page().entries[2].label)
for _ = 1, 5 do S.select("character") end
check(S.storage.meta.start_char == "toan", "and wraps back to Toan")
S.select("start")
check(S.session and S.session.owner == "moonmod.roguelike", "Start Run began a sandbox session")
check(#S.party == 6 and S.slot_id and S.game.save.slot_id().slot_id == nil, "all six joined, no save slot")
S.tick(40)
check(S.context == "dungeon" and S.dungeon == 0 and S.floor == 15, "dropped onto DBC run floor I", tostring(S.dungeon) .. ":" .. tostring(S.floor))
run_floor(S, {atla = true})
local run = S.storage.run
check(run.phase == "active" and run.depth == 1, "run active at depth 1")
check(S.hp.xiao == 0 and S.hp.ruby == 0 and S.hp.toan > 0, "undrafted allies start knocked out")
check((S.items["chronicle:item:177"] or 0) == 2, "starter kit given in the fresh save")
check(S.monsters[1].exp == 36, "ABS x6 on floor I", S.monsters[1].exp)
check(S.floor_label == "1-1" and S.floor_number == 1 and not S.layers.gauntlet and next(S.hud_icons) == nil,
      "the floor plate reads 1-1 and the card B1, no text line", S.floor_label)
local intros = 0; for _, t in ipairs(S.toasts) do if t:find("^DIVINE BEAST CAVE I  %(depth") then intros = intros + 1 end end
check(intros == 1, "the floor intro shows once, though the floor is built after it is reported", intros)
check(S.sheet and S.sheet.title == "MOON GAUNTLET", "Journal page set")
local stock = 0; for _, n in pairs(S.storage.run.stock) do stock = stock + n end
check(stock == 1, "Atla pickup gave a Diorama tile", stock)
S.monsters[1].alive = true; S.kill(S.monsters[1]); S.tick(2)
S.input_pressed["curse_key"] = true; S.tick(1)
check(S.storage.run.next_cursed == true, "G toggles the Cursed Gate")
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
check(S.find_toast("MIRACLE CACHE"), "cursed floor paid a Miracle cache on exit")
S.input_pressed["curse_key"] = true; S.tick(1)
check(S.storage.run.next_cursed == false and S.last_toast():find("Warden"), "the Warden floor cannot be cursed")
S.exit_gate(); S.tick(20)
S.reveal_all(); S.tick(30)
local warden = S.monsters[6]
check(warden.max_hp >= 40 * 6 and S.bars.warden, "key holder became the Warden with a HUD bar", warden.max_hp)
check(S.floor_label == nil and next(S.hud_icons) == nil, "the Warden floor keeps the native Boss plate", S.floor_label)
S.kill(warden); S.tick(2); S.tick(350)
check(S.dungeon == 1 and S.floor == 17, "Warden death moved the run to Wise Owl Forest", tostring(S.dungeon) .. ":" .. tostring(S.floor))
S.tick(20)
check(S.storage.run.pos == 2 and S.storage.run.depth == 5, "biome 2, depth 5", S.storage.run.depth)
local tile; for id, n in pairs(S.storage.run.stock) do if n > 0 then tile = id end end
S.emit("skills.train_requested", {id = "moonmod.roguelike:diorama." .. tile})
check(S.storage.run.diorama[tile] == 1, "placed a " .. tile .. " tile from the Diorama tree")
run_floor(S); finish_biome(S)
for _ = 4, 5 do S.tick(20); run_floor(S); finish_biome(S) end
S.tick(20); run_floor(S); finish_biome(S)
S.tick(30)
check(S.context == "title" and not S.session, "the last Warden ended the session and returned to the title", S.context)
check(S.storage.run == false and S.storage.meta.wins == 1, "victory recorded", S.storage.meta.wins)
check(S.storage.meta.best_depth == 20, "best depth 20", S.storage.meta.best_depth)
check(S.page().lines[#S.page().lines]:find("CONQUERED"), "title screen shows the last run", S.page().lines[#S.page().lines])
check(S.tuning == nil and S.floor_label == nil and next(S.hud_icons) == nil and S.sheet == nil, "run effects, HUD and Journal page cleared")
local won = S.storage.meta.shards
check(won >= 30, "Moon Shards banked", won)

-- 2. Norune Eternal from the title screen ----------------------------------------------------------
print("Scenario 2: Norune Eternal on the title screen")
S.select("eternal")
check(entry_ids(S) == "gaffer,macho,vault,shrine,well,embassy,more", "eternal page lists the first six unlocks and More", entry_ids(S))
check(S.page().root == false, "eternal page is a sub-page")
S.select("gaffer")
check(S.storage.meta.eternal.gaffer == nil and S.page().lines[2]:find("Gaffer"), "first Cross shows the unlock", S.page().lines[2])
S.select("gaffer")
check(S.storage.meta.eternal.gaffer == 1 and S.storage.meta.shards == won - 6, "second Cross buys it", S.storage.meta.shards)
S.select("vault"); S.select("vault")
S.select("macho"); S.select("macho")
check(S.storage.meta.eternal.vault == 1 and S.storage.meta.eternal.macho == 1, "bought Heirloom Vault and Macho's Forge")
for _ = 1, 3 do S.select("shrine"); S.select("shrine") end
check(S.page().lines[2] and (S.page().lines[2]:find("needs") or (S.storage.meta.eternal.shrine or 0) >= 1), "unaffordable unlock says what it needs", S.page().lines[2])
S.select("back")
check(entry_ids(S) == "start,character,eternal,records", "Circle on a sub-page goes back to the root page")
S.select("records")
check(S.page().lines[1]:find("Wins 1"), "records page", S.page().lines[1])
S.select("done")
check(entry_ids(S) == "start,character,eternal,records", "back from records")

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
check(S2.gilda == 700 and S2.last_toast():find("Gaffer"), "Gaffer sells on floor II", S2.last_toast())
-- a found weapon: pre-leveled, then the choice between it and the held one
local held_slot = S2.equipped.toan
local held_attack = S2.weapons.toan[held_slot].attack
local found_slot = S2.pickup_weapon("toan", 259)
check(S2.weapons.toan[found_slot].level >= 1 and #S2.weapons.toan[found_slot].attach >= 1, "found weapon arrived pre-leveled with an attachment")
check(S2.layers.choice_b and S2.layers.choice_c and not S2.layers.gauntlet, "the weapon choice opened in place of the HUD line", S2.layers.choice_b)
check(S2.layers.choice_b:find("^%[KEEP HELD%]"), "the held weapon is picked first", S2.layers.choice_b)
local found_attack = S2.weapons.toan[found_slot].attack
S2.input_pressed.choice_ok = true; S2.tick(1)
check(S2.layers.choice_b, "Cross from the chest does not answer the choice at once")
S2.tick(25); S2.input_pressed.choice_ok = true; S2.tick(1)
check(S2.weapons.toan[found_slot] == nil and S2.equipped.toan == held_slot, "kept the held weapon; the found one is gone")
check(S2.weapons.toan[held_slot].attack == held_attack + math.floor(found_attack / 4), "and a quarter of its attack went into the held one",
      S2.weapons.toan[held_slot].attack)
check(not S2.layers.choice_b and S2.floor_label and #S2.contexts == 0, "the choice closed")
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
S4.enter(0, 15); S4.tick(20)
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
check(not S9.find_toast("off the Gauntlet route"), "the dungeon entrance is not called off route")
finish_biome(S9)
check(S9.dungeon == 1 and S9.active == "xiao" and not S9.find_toast("not drafted"), "the next biome opens as Xiao too",
      tostring(S9.dungeon) .. " " .. S9.active)
check(not S9.find_toast("off the Gauntlet route") and not S9.storage.run.suspended, "and its entrance is not off route either")

-- 9. One weapon each: take the found one, an outsider's weapon, a broken weapon ends the run ------------
print("Scenario 9: one weapon each, and a broken weapon ends the run")
local S10 = boot()
start_run(S10)
run_floor(S10)
local old_slot = S10.equipped.toan
local old_magic = S10.weapons.toan[old_slot].magic
local new_slot = S10.pickup_weapon("toan", 260, {magic = 9})
S10.tick(25); S10.input_pressed.choice_next = true; S10.tick(1)
check(S10.layers.choice_c and S10.layers.choice_c:find("^%[TAKE FOUND%]"), "R1 picks the found weapon", S10.layers.choice_c)
S10.input_pressed.choice_ok = true; S10.tick(1)
check(S10.equipped.toan == new_slot and S10.weapons.toan[old_slot] == nil, "took the found weapon; the held one is gone")
check(S10.weapons.toan[new_slot].magic == 9 + math.floor(old_magic / 4), "and it absorbed a quarter of the old one",
      S10.weapons.toan[new_slot].magic)
check(S10.storage.run.weapons.toan.slot == new_slot, "the run follows the new weapon")
local attack = S10.weapons.toan[new_slot].attack
local goro_slot = S10.pickup_weapon("goro", 316, {attack = 40})
check(S10.weapons.goro[goro_slot] == nil and not S10.layers.choice_b, "a weapon for an undrafted ally is absorbed, no choice")
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
print("Scenario 10: Whetstone, Repair Kit and the Eternal pages")
S10.storage.meta.eternal.whetstone = 2
S10.storage.meta.eternal.kit = 1
local S11 = boot({storage = S10.storage})
S11.open_title_mode()
S11.select("eternal")
local ids = entry_ids(S11)
check(#S11.page().entries == 7 and ids:find("more$"), "the Eternal page holds six unlocks and More", ids)
S11.select("more")
check(entry_ids(S11) == "moon,whetstone,oil,kit,more", "More shows the rest", entry_ids(S11))
S11.select("back")
start_run(S11)
local starter11 = S11.weapons.toan[S11.equipped.toan]
check(starter11.durability == 30 + 20 and starter11.durability_f == 50, "Whetstone 2/3: +20 durability, full", starter11.durability)
check((S11.items["chronicle:item:177"] or 0) == 3, "Repair Kit 1/2: a third Repair Powder", S11.items["chronicle:item:177"])

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  print("Last toasts:"); for i = math.max(1, #S.toasts - 5), #S.toasts do print("  " .. S.toasts[i]) end
  os.exit(1)
end
