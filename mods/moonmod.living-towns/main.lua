-- Living Towns: bounties from the villagers, and stores that keep up with the story. See README.md.
--
-- The board: each adventure day (world.get().day) the towns post up to three bounties, each in a dungeon the story
-- has reached: hunt (fell monsters there), chests (open chests there), deeper (reach a floor past your deepest) or
-- fetch (bring an item, handed in at the board). Progress is kept per save slot. A bounty done is paid by its
-- villager, who waits by the exit gate on that dungeon's floors (or at the board in the Mod Manager).
-- The stores: a general store (a shop selling mostly goods) gains goods for each dungeon reached, through
-- shops.register_item, which claims no shop, so Dungeon+ and the Randomizer still own their lists.

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil, a
end
local function setting(id, fallback)
  local v = moonmod.settings.get(id)
  if v == nil then return fallback end
  return v
end
local function notify(message, frames) try(game.ui.notify, {message = message:sub(1, 200), duration_frames = frames or 300}) end

local DUNGEONS = {[0] = "Divine Beast Cave", [1] = "Wise Owl Forest", [2] = "Shipwreck", [3] = "Sun and Moon Temple",
                  [4] = "Moon Sea", [5] = "Gallery of Time"}
-- Who asks, by the dungeon the bounty is in (each dungeon's own town)
local ASKERS = {
  [0] = {"Macho of Norune", "Paige of Norune", "Laura of Norune", "Norune's Mayor"},
  [1] = {"Pao of Matataki", "Cacao of Matataki", "a Matataki fisherman"},
  [2] = {"the Sheriff of Queens", "a Queens merchant", "a sailor of Queens"},
  [3] = {"the Chief of Muska Lacka", "a Muska Lacka shepherd"},
  [4] = {"a Yellow Drops farmer", "the Yellow Drops chief"},
  [5] = {"a voice from Brownboo"},
}
local FETCH = {{148, "Bread"}, {146, "Tasty Water"}, {155, "Cheese"}, {151, "Antidote Drink"}, {152, "Holy Water"},
               {177, "Repair Powder"}, {150, "Stamina Drink"}}
local REWARD_ITEMS = {{149, "Premium Chicken"}, {147, "Premium Water"}, {154, "Mighty Healing"}, {176, "Revival Powder"},
                      {183, "Auto Repair Powder"}, {178, "Powerup Powder"}, {95, "Garnet"}, {91, "Attack +1"}}

-- Goods a general store adds once each dungeon has been reached (cumulative)
local STOCK = {
  [1] = {147, 155, 151},           -- Wise Owl Forest: Premium Water, Cheese, Antidote Drink
  [2] = {149, 152, 150, 81, 82},   -- Shipwreck: Premium Chicken, Holy Water, Stamina Drink, Fire, Ice
  [3] = {154, 183, 83, 84},        -- Sun and Moon Temple: Mighty Healing, Auto Repair Powder, Thunder, Wind
  [4] = {176, 178, 85},            -- Moon Sea: Revival Powder, Powerup Powder, Holy
}

-- Per save slot -------------------------------------------------------------------------------------------------------
local in_sandbox, slot_key, slot = false, nil, nil
local function slots() local d = moonmod.storage.get("slots"); return type(d) == "table" and d or {} end
local function save()
  if not slot_key or not slot then return end
  local d = slots(); d[slot_key] = slot; moonmod.storage.set("slots", d)
end

-- How far the story has gone: the dungeons reached and how deep in each
local function progress()
  local reached, deepest = {}, {}
  for _, d in ipairs(try(game.dungeons.list) or {}) do
    local id, floor = tonumber(d.native_id), tonumber(d.deepest_floor_reached)
    if id and id <= 5 and floor and floor > 0 then reached[#reached + 1] = id; deepest[id] = floor end
  end
  table.sort(reached)
  return reached, deepest
end
local function tier() local r = progress(); return #r end

-- The board -----------------------------------------------------------------------------------------------------------
local function describe(b)
  local where = DUNGEONS[b.dungeon] or "a dungeon"
  local task
  if b.kind == "hunt" then task = string.format("Fell %d monsters in %s (%d/%d)", b.need, where, math.min(b.have, b.need), b.need)
  elseif b.kind == "chests" then task = string.format("Open %d chests in %s (%d/%d)", b.need, where, math.min(b.have, b.need), b.need)
  elseif b.kind == "deeper" then task = string.format("Reach floor %d of %s", b.need, where)
  else task = string.format("Bring %d %s", b.need, b.item_name) end
  return b.asker .. ": " .. task .. (b.done and " - done, collect it!" or "") .. string.format(" [%d Gilda]", b.gilda)
end

local function post_board(day)
  local reached, deepest = progress()
  slot.board, slot.day = {}, day
  if #reached == 0 then return end
  -- the same board for the same day of the same save: a seed from both
  math.randomseed(day * 7919 + #reached * 104729 + (slot.seed or 0))
  local kinds = {"hunt", "chests", "deeper", "fetch"}
  for i = 1, setting("bounty_count", 3) do
    local dungeon = reached[math.random(#reached)]
    local kind = kinds[math.random(#kinds)]
    local t = #reached
    local b = {id = day .. ":" .. i, kind = kind, dungeon = dungeon, have = 0, done = false, claimed = false,
               asker = ASKERS[dungeon][math.random(#ASKERS[dungeon])]}
    if kind == "hunt" then b.need = 8 + 4 * t + math.random(0, 6)
    elseif kind == "chests" then b.need = 3 + math.random(0, 2)
    elseif kind == "deeper" then b.need = math.max(2, (deepest[dungeon] or 1) + math.random(1, 2))
    else
      local f = FETCH[math.random(#FETCH)]
      b.item, b.item_name, b.need = f[1], f[2], math.random(1, 3)
    end
    b.gilda = math.floor((150 + 120 * t + (kind == "deeper" and 150 or 0)) * setting("reward", 100) / 100)
    local r = REWARD_ITEMS[math.random(math.min(#REWARD_ITEMS, 2 + t))]
    b.reward_item, b.reward_name = r[1], r[2]
    slot.board[i] = b
  end
  save()
end

local function complete(b)
  if b.done then return end
  b.done = true
  save()
  notify(b.asker .. "'s bounty is done. Collect it from the villager at a floor's exit, or at the board.", 360)
end

local function pay(b)
  if not b.done or b.claimed then return false end
  b.claimed = true
  try(game.economy.add, {amount = b.gilda})
  try(game.items.give, {id = "chronicle:item:" .. b.reward_item, count = 1})
  save()
  notify(string.format("%s thanks you: %d Gilda and a %s.", b.asker, b.gilda, b.reward_name), 360)
  return true
end

local function show_board()
  if not slot then notify("Load a game first"); return end
  if not slot.board or #slot.board == 0 then notify("The board is empty: the towns ask once a dungeon is reached."); return end
  for _, b in ipairs(slot.board) do if not b.claimed then notify(describe(b), 480) end end
  local any = false
  for _, b in ipairs(slot.board) do if not b.claimed then any = true end end
  if not any then notify("Every bounty on today's board is done. New ones tomorrow.") end
end

-- Stores ---------------------------------------------------------------------------------------------------------------
local stocked = {} -- "shop:item" added this session
local function general_stores()
  local out = {}
  for shop = 0, 17 do
    local got = try(game.shops.get, {shop_no = shop})
    local goods, weapons = 0, 0
    for _, e in ipairs(got and got.items or {}) do
      if (tonumber(e.item_no) or 0) >= 257 then weapons = weapons + 1 else goods = goods + 1 end
    end
    if goods >= 3 and goods > weapons then out[#out + 1] = {shop = shop, items = got.items} end
  end
  return out
end
local function restock()
  if not setting("stock", true) then return end
  local t = tier()
  if t <= 1 then return end
  for _, store in ipairs(general_stores()) do
    local have = {}
    for _, e in ipairs(store.items) do have[tonumber(e.item_no) or -1] = true end
    for level = 1, math.min(t - 1, 4) do
      for _, item in ipairs(STOCK[level]) do
        local key = store.shop .. ":" .. item
        if not have[item] and not stocked[key] and try(game.shops.register_item, {shop_no = store.shop, item_id = item}) then
          stocked[key] = true
        end
      end
    end
  end
end

-- Loading a save -------------------------------------------------------------------------------------------------------
local function load_slot()
  if in_sandbox then return end
  local identity = try(game.save.slot_id)
  local key = identity and identity.slot_id and (tostring(identity.slot_id) .. ":" .. tostring(identity.slot_generation)) or nil
  if not key and try(game.player.get) then key = "unsaved" end
  if key == slot_key then return end
  local previous = slot_key
  slot_key = key
  if not key then slot = nil; return end
  local d = slots()
  if previous == "unsaved" and key ~= "unsaved" and type(d[key]) ~= "table" and type(d.unsaved) == "table" then
    d[key], d.unsaved = d.unsaved, nil
  end
  slot = type(d[key]) == "table" and d[key] or {board = {}, day = -1, seed = math.random(0, 99999)}
  d[key] = slot
  moonmod.storage.set("slots", d)
  restock()
end

-- Events ---------------------------------------------------------------------------------------------------------------
local function bounty_here(kind)
  local w = try(game.world.get)
  if not (slot and w and w.context == "dungeon") then return {} end
  local out = {}
  for _, b in ipairs(slot.board or {}) do
    if b.dungeon == w.dungeon_id and not b.done and (kind == nil or b.kind == kind) then out[#out + 1] = b end
  end
  return out, w
end

moonmod.on("game.enemy_defeated", function()
  if in_sandbox then return end
  for _, b in ipairs(bounty_here("hunt")) do
    b.have = b.have + 1
    if b.have >= b.need then complete(b) end
  end
  save()
end)

moonmod.on("game.chest.opened", function(e)
  if in_sandbox or not e or e.chest == nil then return end
  for _, b in ipairs(bounty_here("chests")) do
    b.have = b.have + 1
    if b.have >= b.need then complete(b) end
  end
  save()
end)

moonmod.on("game.dungeon.generating", function(e)
  if in_sandbox or not slot or not e or e.back_floor or e.prebuild then return end
  -- deeper: the floor being built is floor_id + 1 in the game's counting
  for _, b in ipairs(slot.board or {}) do
    if b.kind == "deeper" and not b.done and b.dungeon == e.dungeon_id and (tonumber(e.floor_id) or 0) + 1 >= b.need then complete(b) end
  end
  -- a bounty of this dungeon waiting to be paid, or still open: its villager stands by the exit gate
  if setting("villager", true) then
    for _, b in ipairs(slot.board or {}) do
      if b.dungeon == e.dungeon_id and not b.claimed then
        try(game.world.dungeon_npc_set, {id = "bounty", model = "gedit/e01/chara/p02a.chr", place = "exit"})
        break
      end
    end
  end
end)

moonmod.on("game.dungeon_npc.near", function(e)
  if in_sandbox or not slot or not e or e.id ~= "bounty" then return end
  local w = try(game.world.get)
  local paid = false
  for _, b in ipairs(slot.board or {}) do
    if w and b.dungeon == w.dungeon_id and b.done and not b.claimed then paid = pay(b) or paid end
  end
  if not paid then
    for _, b in ipairs(slot.board or {}) do
      if w and b.dungeon == w.dungeon_id and not b.claimed then notify(describe(b), 360) end
    end
  end
end)

-- Actions --------------------------------------------------------------------------------------------------------------
for _, a in ipairs({{"board", "Bounty Board", "Today's bounties and how far along each is"},
                    {"hand_in", "Hand In and Collect", "Hand in fetched items, and collect every bounty that is done"}}) do
  try(game.ui.register, {id = a[1], label = a[2], description = a[3]})
end
moonmod.on("ui.action", function(a)
  if not a then return end
  load_slot()
  if in_sandbox then notify("Living Towns sits out challenge runs."); return end
  if a.id == "board" then show_board()
  elseif a.id == "hand_in" then
    if not slot then notify("Load a game first"); return end
    local any = false
    for _, b in ipairs(slot.board or {}) do
      if b.kind == "fetch" and not b.done then
        local r = try(game.items.remove, {id = "chronicle:item:" .. b.item, count = b.need})
        if r and (r.removed or 0) >= b.need then complete(b)
        elseif r and (r.removed or 0) > 0 then try(game.items.give, {id = "chronicle:item:" .. b.item, count = r.removed}) end
      end
      if pay(b) then any = true end
    end
    if not any then notify("Nothing to collect yet.") end
  end
end)

moonmod.on("game.session.started", function() in_sandbox = true; slot_key, slot = nil, nil end)
moonmod.on("game.session.ended", function() in_sandbox = false end)
do
  local s = try(game.session.get)
  in_sandbox = type(s) == "table" and s.kind == "sandbox"
end

local frame = 0
moonmod.on("game.tick", function()
  frame = frame + 1
  if in_sandbox or frame % 60 ~= 0 then return end
  load_slot()
  if not slot or not setting("bounties", true) then return end
  local w = try(game.world.get)
  local day = w and tonumber(w.day)
  if day and day ~= slot.day then
    post_board(day)
    if slot.board and #slot.board > 0 then notify("New bounties are posted in town (Mod Manager: Bounty Board).", 360) end
    restock()
  end
end)

load_slot()
moonmod.log("info", "Living Towns ready")
