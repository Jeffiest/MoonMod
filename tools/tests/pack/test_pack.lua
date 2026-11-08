-- MoonMod Pack (mods/moonmod.pack, built by tools/pack/build_pack.py) in a fake game.
-- Usage, from the repository root:  lua tools/tests/pack/test_pack.lua
-- (python tools/pack/build_pack.py --check says whether the pack matches its parts' sources.)
local root = arg and arg[0] and arg[0]:match("^(.*)/tools/tests/pack/") or "."
local PACK = root .. "/mods/moonmod.pack/main.lua"

local passed, failed = 0, 0
local function check(ok, what, detail)
  if ok then passed = passed + 1; print("  ok   " .. what)
  else failed = failed + 1; print("  FAIL " .. what .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or "")) end
end

local function read(path)
  local file = assert(io.open(path, "rb"))
  local text = file:read("a")
  file:close()
  return text
end

local manifest_text = read(root .. "/mods/moonmod.pack/mod.json")
local part_ids = {}
for id in manifest_text:gmatch('"id": "(moonmod%.[%w%-%.]+)"') do
  if id ~= "moonmod.pack" then part_ids[#part_ids + 1] = id end
end

-- A fake game: every part off but the ones named; part.run records what the script hands over.
local function run_pack(enabled)
  local S = {handed = {}, ran = {}, logs = {}, named = {}, autosave = nil}
  local env = setmetatable({}, {__index = _G})
  local current
  env.moonmod = {
    game = {id = "chronicle", api_major = 1, mod_id = "moonmod.pack"},
    on = function() end,
    log = function(_, message) S.logs[#S.logs + 1] = (current or "moonmod.pack") .. "|" .. tostring(message) end,
    settings = {get = function() return nil end},
    part = {
      run = function(id, fn, part_env, name)
        S.handed[#S.handed + 1] = id
        if type(fn) == "string" then -- the part's source: a chunk of its own, as the engine compiles it
          S.named[id] = name
          fn = assert(load(fn, "=" .. name, "t", part_env))
        end
        assert(type(fn) == "function", "part.run needs a function or the part's source")
        if not enabled[id] then return false, "off" end
        local previous = current
        current = id
        local ok, err = pcall(fn)
        current = previous
        S.ran[id] = ok or err
        return ok, err
      end,
    },
  }
  env.game = {
    save = {autosave_set = function(a) S.autosave = a.enabled; return {} end},
  }
  local chunk = assert(loadfile(PACK, "t", env))
  chunk()
  return S, env
end

print("MoonMod Pack")
check(#part_ids == 12, "the manifest lists 12 parts", #part_ids)

local S, env = run_pack({})
check(#S.handed == #part_ids, "the script hands over every part", #S.handed)
for index, id in ipairs(part_ids) do
  check(S.handed[index] == id, "part " .. index .. " is " .. id, S.handed[index])
end
check(next(S.ran) == nil, "a part that is off never runs")
for _, id in ipairs(part_ids) do
  check(S.named[id] == id .. "/main.lua", id .. " compiles as a chunk named after its file", S.named[id])
end
check(#S.logs == 0, "nothing runs with every part off")

S, env = run_pack({["moonmod.autosave"] = true})
check(S.ran["moonmod.autosave"] == true, "an enabled part runs", S.ran["moonmod.autosave"])
check(S.autosave == true, "Autosave applied its default through the game")
check(rawget(env, "apply") == nil, "a part's globals stay its own (none leak into the pack)")

-- Each part's code is its own mod's script, between markers the engine reads.
local script = (read(PACK):gsub("\r\n", "\n"))
for _, id in ipairs(part_ids) do
  local source = (read(root .. "/mods/" .. id .. "/main.lua"):gsub("\r\n", "\n"))
  local begin = script:find("-- moonmod:part " .. id .. "\n", 1, true)
  local finish = begin and script:find("-- moonmod:end", begin, true)
  check(begin ~= nil and finish ~= nil, id .. " has its markers")
  if begin and finish then
    check(script:sub(begin, finish):find(source, 1, true) ~= nil, id .. "'s code is its own script, unchanged")
  end
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
