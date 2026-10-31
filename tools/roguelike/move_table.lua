-- The Gauntlet's mod moves side by side, for balancing: each character's moves as the mod gives them (the fake
-- adapter, tools/tests/roguelike/fake_game.lua), with what they deal and how long they take.
-- Usage, from the repository root:  lua tools/roguelike/move_table.lua
--
-- For each move: its trigger, the damage it deals in multiples of the weapon's attack (every hit, a shot's count
-- times its damage), how long it plays in game steps (a mod animation's length, or a native motion stretch taken as
-- 30 frames, over the move's speed), its cooldown and gauge cost, and the damage per second if it were used back to
-- back (steps at 30 a second). A splash or a pull the mod adds on top (Opar's Bubble, Tongue Lash) is noted, not
-- counted.
local here = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local root = here .. "/../.."
package.path = root .. "/tools/tests/roguelike/?.lua;" .. package.path
local F = require("fake_game")
local MOD = root .. "/mods/moonmod.roguelike/main.lua"

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
defaults.opar = true
local S = F.new({settings = defaults, storage = {meta = {start_char = "opar", eternal = {fullparty = 1}}}})
F.load_mod(S, MOD)
S.open_title_mode()
S.select("start")
S.tick(60)

-- a mod animation's length (frames), read from its file
local function anim_length(id)
  local f = io.open(root .. "/mods/moonmod.roguelike/resources/anims/" .. id .. ".json")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return tonumber(text:match('"length":%s*(%d+)'))
end

local rows = {}
for _, m in ipairs(S.moves or {}) do
  local dmg, notes = 0, {}
  for _, h in ipairs(m.hits or {}) do
    dmg = dmg + (h.damage or 1) * (h.shot and (h.count or 1) or 1)
    if h.shot then notes.shots = (notes.shots or 0) + (h.count or 1) end
  end
  local frames = m.animation and anim_length(m.animation) or 30
  frames = frames * ((m.to or 1) - (m.from or 0))
  local steps = frames / (m.speed or 1)
  local cycle = steps + (m.cooldown or 0)
  rows[#rows + 1] = {who = m.character, id = m.id, trigger = m.trigger .. (m.chain and (" " .. m.chain) or ""), dmg = dmg,
                     steps = steps, cd = m.cooldown or 0, gauge = m.gauge or 0, dps = dmg / cycle * 30,
                     ranged = notes.shots ~= nil}
end
table.sort(rows, function(a, b) if a.who ~= b.who then return a.who < b.who end return a.trigger < b.trigger end)
print(string.format("%-8s %-22s %-18s %6s %6s %5s %5s %7s %s", "who", "move", "trigger", "dmg", "steps", "cd", "gauge", "dmg/s", "range"))
for _, r in ipairs(rows) do
  print(string.format("%-8s %-22s %-18s %6.2f %6.1f %5d %5d %7.2f %s", r.who, r.id:gsub("^.*:", ""), r.trigger, r.dmg, r.steps,
                      r.cd, r.gauge, r.dps, r.ranged and "shot" or ""))
end
