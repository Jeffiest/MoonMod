-- Opar in the story (docs/OPAR_PLAN.md §8). Baby Opar's Atla lies on the Divine Beast Cave's 8th floor, as the cat's
-- does. Picked up (game flag 7001), he waits in Toan's house beside the cat once her element is in; in her scene he
-- turns into Opar beside Xiao, and when the scene makes the party two the house's script sets game flag 7002, and he
-- joins with his Driftwood Staff. Should he come after her scene has played, standing by him is his own short join.
-- The house is its script patched (art/opar/story/patch_house.py); the flags are the save's, so each save keeps its
-- own. In a Gauntlet run (a sandbox session) none of this runs.

local FOUND, JOINED = 7001, 7002
local CAVE, SPHERE_FLOOR = 0, 7 -- the Divine Beast Cave (dungeon 0), floor 8 counted from 0
local SPHERE = {id = "babyopar", name = "Baby Opar"}

local function try(f, a)
  if type(f) ~= "function" then return nil end
  local ok, r, e
  if a == nil then ok, r, e = pcall(f) else ok, r, e = pcall(f, a) end
  if not ok then moonmod.log("warn", tostring(r)) return nil end
  if r == nil and e ~= nil then moonmod.log("info", tostring(type(e) == "table" and e.message or e)) end
  return r
end

-- His files, and Toan's house with him in it. The Gauntlet supplies his pack and portrait too: whichever loads first
-- keeps them (both are the same files).
local FILES = {
  {"resources/opar/c07d.chr", "dun/mainchara/c07d.chr"},
  {"resources/opar/c07f.chr", "dun/mainchara/c07f.chr"},
  {"resources/opar/medallion.png", "dun/mainchara/c07d_face.png"},
  {"resources/opar/c07model.pak", "commenu/dungeon/c07model.pak"},
  {"resources/opar/voice106.snd", "sound/voice/voice106.snd"},
  {"resources/opar/c07baby.chr", "gedit/e01/chara/c07baby.chr"},
  {"resources/opar/e04c07baby.chr", "gedit/e01/chara/e04c07baby.chr"},
  {"resources/opar/e04c07opar.chr", "gedit/e01/chara/e04c07opar.chr"},
  {"resources/story/i01h01_event.stb", "gedit/e01/in/i01h01/event.stb"},
}
for _, f in ipairs(FILES) do try(game.resources.override, {path = f[1], game_path = f[2]}) end

-- He is registered once: by the Gauntlet when it is loaded (its own Opar), else here.
local registered = try(game.characters.register_playable, {id = "opar", name = "Opar", pack = "dun/mainchara/c07d.chr",
  portrait = "dun/mainchara/c07d_face.png", title = "Moon Sea Frog Mage", fights_as = "toan", hp = 90, defense = 21})
moonmod.log("info", "opar: " .. (registered and "registered" or "registered by another mod"))

-- His six staffs (art/opar/make_staffs.py), the story's: Driftwood when he joins, the next ones sold in the weapon
-- shops as the story goes on (shops 1, 8 and 10: the ones selling Toan's swords), each building up into the next, and
-- the Tidecaller only by building up the Moonpearl. Once he has joined, chests can hold them too (chest = {dungeon,
-- first floor}: Reed from the Divine Beast Cave's 8th floor, then one per dungeon). Their models are this mod's own copies (opsz01-06), as a
-- registered weapon's model must be its own mod's file.
local STAFFS = {
  {key = "driftwood", name = "Driftwood Staff", attack = 8, durability = 40,
   about = {"A bleached hook of driftwood off the shore.", "A staff to start with."}},
  {key = "reed", name = "Reed Staff", attack = 18, durability = 45, shop = 1, price = 900, chest = {0, 8},
   about = {"Marsh reeds bound tight, fronds at the top."}},
  {key = "coral", name = "Coral Staff", attack = 28, durability = 50, shop = 8, price = 2400, chest = {1, 0},
   about = {"A crown of branching coral on a sea-worn stem."}},
  {key = "bogoak", name = "Bog Oak Staff", attack = 38, durability = 60, shop = 8, price = 4200, chest = {2, 0},
   about = {"Black bog oak twisted round a mossy root knot."}},
  {key = "moonpearl", name = "Moonpearl Staff", attack = 50, durability = 65, shop = 10, price = 7000, chest = {3, 0},
   about = {"A silver claw holding a pearl of the Moon Sea."}},
  {key = "tidecaller", name = "Tidecaller", attack = 56, durability = 70,
   about = {"The tide's own staff, its rune disc aglow.", "Built up from the Moonpearl Staff."}},
}
for i, st in ipairs(STAFFS) do
  local stem = string.format("opsz%02d", i)
  try(game.resources.override, {path = "resources/opar/" .. stem .. ".chr", game_path = "commenu/weapon/" .. stem .. ".chr"})
  try(game.resources.override, {path = "resources/opar/" .. stem .. "_icon.png", game_path = "icons/" .. stem .. "_icon.png"})
  local reg = try(game.weapons.register, {id = st.key, name = st.name, template_weapon = 262, owner = "opar", model = stem,
    icon = stem .. "_icon", stats = {attack = st.attack, durability = st.durability}, description = st.about, menu_scale = 0.7})
  st.id = reg and reg.id or nil
end
for i = 1, #STAFFS - 1 do
  if STAFFS[i].id and STAFFS[i + 1].id then try(game.weapons.build_up_register, {from = STAFFS[i].id, to = STAFFS[i + 1].id}) end
end
for _, st in ipairs(STAFFS) do
  if st.id and st.shop then
    try(game.shops.register_item, {shop_no = st.shop, item_id = st.id})
    try(game.shops.set_price, {item_id = st.id, buy_price = st.price, sell_price = st.price // 4})
  end
end
local staff = STAFFS[1].id and {id = STAFFS[1].id} or nil

local function story()
  local s = try(game.session.get)
  return not (s and s.kind == "sandbox")
end

local function flag(id)
  local r = try(game.world.story_flag_get, {id = id})
  return r ~= nil and r.value == true
end

local tick = 0

-- His sphere: on the 8th floor until he is found.
local sphere_floor -- the floor (dungeon .. floor) it was put on
local function place_sphere()
  if not story() or flag(FOUND) then return end
  local w = try(game.world.get)
  if not (w and w.dungeon_id == CAVE and w.floor_id == SPHERE_FLOOR and not w.back_floor) then
    sphere_floor = nil
    return
  end
  local here = tostring(w.dungeon_id) .. ":" .. tostring(w.floor_id) .. ":" .. tostring(w.floor_seed)
  if sphere_floor == here then return end
  local put = try(game.georama.atla_spawn, SPHERE)
  if put then
    sphere_floor = here
    moonmod.log("info", "opar: baby Opar's Atla put on floor " .. (w.floor_id + 1))
  end
end

moonmod.on("game.georama.atla_collected", function(e)
  if e.id ~= SPHERE.id or e.owner ~= "moonmod.opar" then return end
  try(game.world.story_flag_set, {id = FOUND, value = true})
  moonmod.log("info", "opar: baby Opar's Atla picked up (game flag " .. FOUND .. ")")
  try(game.ui.notify, {message = "Baby Opar's Atla! Put the cat in Toan's house and he will be there too.", duration_frames = 300})
end)

-- The scene's words for two (only while he is in the house with the cat).
local TEXT = {
  ["gedit.e01.in.i01h01.i01h01.205"] = "Oh, are those new friends?\nI haven't seen them around here.",
  ["gedit.e01.in.i01h01.i01h01.20402"] = "{name2} and Opar have become allies.",
}
local text_on = false
local function words()
  local want = story() and flag(FOUND) and not flag(JOINED)
  if want == text_on then return end
  text_on = want
  for key, text in pairs(TEXT) do
    if want then try(game.text.set, {key = key, text = text}) else try(game.text.clear, {key = key}) end
  end
end

-- He joins once the house has said so (flag 7002), with his staff in hand.
local function join()
  if not story() or not flag(JOINED) then return end
  local me = try(game.characters.get, {id = "opar"})
  if not me or me.in_party then return end
  if not try(game.party.join, {character = "opar"}) then return end
  if staff then try(game.weapons.give, {id = staff.id, character = "opar"}) end
  try(game.ui.notify, {message = "Opar has become an ally.", duration_frames = 240})
end

-- his staffs in chests while he is in the story's party, not in a run's
local chests_on = false
local function chests()
  local want = (story() and flag(JOINED)) and true or false
  if want == chests_on then return end
  chests_on = want
  if not want then try(game.dungeons.chest_weapons_clear) return end
  for _, st in ipairs(STAFFS) do
    if st.id and st.chest then
      try(game.dungeons.chest_weapons_add, {item_id = st.id, dungeon_id = st.chest[1], floor_from = st.chest[2], percent = 15})
    end
  end
end

-- His kit in the story: the Gauntlet's (mods/moonmod.roguelike, MOVES and FORM), without its run perks. Set only
-- outside a run (a run's moves are the Gauntlet's own, and two mods can't hold one character's trigger), and taken
-- back as a run starts. A,A,R2 Spit, A,A,A,R2 Gob, a charge let go Bubble, a full charge with a full gauge the Jump
-- Slam (the giant Opar slams down, once a minute), L2 at rest Back Hop, L2 Frog Hop, A late in it Leap Strike,
-- run+attack Belly Slide, guard+attack Staff Swat, locked on away+A Tongue Lash (yanks the enemy in), R2 Croak (stuns).
local KIT = {anims = {"opar_spit", "opar_gob", "opar_bubble", "opar_back_hop", "opar_belly_slide", "opar_staff_swat",
                      "opar_frog_hop", "opar_tongue_lash", "opar_croak", "opar_leap_strike", "opar_jump_slam"},
             set = nil, -- "kit", "kit+slam" or "form" while ours are set
             form = {active = false, pending = nil, since = 0, slammed = false, ready_at = 0},
             move = nil, move_at = 0, pulled = false,
             PACK = "dun/mainchara/c07f.chr", SCALE = 0.5, COOLDOWN = 3600,
             FRAMES = {weapon = "r_hand", item = "l_hand", tukene1 = "karada", jnt2_1 = "karada", jnt12_1 = "shita"}}
local function glob(at, extra)
  local h = {at = at, shot = true, damage = 0.8, from = "jnt12_1", from_ahead = 2.6, from_rise = -0.4, cell = 8, size = 2.2,
             burst = "heal", burst_scale = 0.9}
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end
KIT.moves = {
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
-- the leap, ahead of the Bubble so a charge at the top is the slam
KIT.jump_slam = {id = "opar_jump_slam", character = "opar", trigger = "charge_release", min_charge = 1.5, max_charge = 10,
  animation = "opar_jump_slam", speed = 1.0, gauge = 100, cooldown = 0, invincible = true, cues = {{at = 0.05, sound = "shout"}}}
-- the giant Opar's press (his form pack's motion 24), his only move while he is it
KIT.form_slam = {id = "opar_form_slam", character = "opar", trigger = "heavy", motion = 24, from = 0.24, speed = 0.7, invincible = true,
  cooldown = 0, hits = {{at = 0.28, radius = 34, reach = 4, damage = 3.0, knockback = 9, heavy = true, charged = true,
                         burst = "explosion", burst_scale = 0.9}},
  cues = {{at = 0.24, sound = "swing_heavy", trail = "slam"}}}

function KIT.animated()
  if KIT.registered ~= nil then return KIT.registered end
  KIT.registered = true
  for _, id in ipairs(KIT.anims) do
    if not try(game.animations.player_register, {id = id, file = "resources/anims/" .. id .. ".json"}) then KIT.registered = false end
  end
  return KIT.registered
end

-- the set he should have now: his kit, with the slam once its minute is up, or the giant's press while he is it
function KIT.want()
  if not story() or not KIT.animated() then return nil end
  if KIT.form.active then return "form" end
  return tick >= KIT.form.ready_at and "kit+slam" or "kit"
end

function KIT.apply()
  local want = KIT.want()
  if want == KIT.set then return end
  KIT.set = want
  if not want then try(game.player.moves_clear) return end
  local list = {}
  if want == "form" then
    list[1] = KIT.form_slam
  else
    if want == "kit+slam" then list[#list + 1] = KIT.jump_slam end
    for _, m in ipairs(KIT.moves) do list[#list + 1] = m end
  end
  local r = try(game.player.moves_set, {moves = list})
  moonmod.log("info", "opar: his moves (" .. want .. ") " .. (r and "set" or "refused"))
end

function KIT.smoke(p, scale)
  if p and p.position then
    try(game.effects.burst, {kind = "smoke", position = {x = p.position.x, y = p.position.y + 8, z = p.position.z}, scale = scale})
  end
end

-- The Jump Slam a step a frame: after the leap, the smoke and the giant Opar; his press; the smoke and Opar again.
function KIT.slam(p)
  local f = KIT.form
  if f.pending and not f.active then
    if p.character ~= "opar" or tick - f.pending > 300 then f.pending = nil return end
    if try(game.player.form_set, {pack = KIT.PACK, frames = KIT.FRAMES, scale = KIT.SCALE}) then
      f.pending, f.active, f.since, f.slammed = nil, true, tick, false
      KIT.smoke(p, 1.2)
      KIT.apply()
    end
  elseif f.active and not f.slammed and p.character == "opar" and tick - f.since < 120 then
    f.slammed = try(game.player.move_play, {id = "opar_form_slam"}) ~= nil
  elseif f.active then
    if not try(game.player.form_clear) then return end
    f.active, f.slammed, f.ready_at = false, false, tick + KIT.COOLDOWN
    KIT.smoke(p, 0.9)
    KIT.apply()
  end
end

moonmod.on("game.player.move", function(e)
  local id = tostring(e and e.id or ""):gsub("^.*:", "")
  KIT.move, KIT.move_at, KIT.pulled = id, tick, false
  if id == "opar_jump_slam" and not KIT.form.active and story() then KIT.form.pending = tick end
end)

-- the Tongue Lash's first hit yanks the enemy in; the Croak stuns what it reaches
moonmod.on("game.enemy_hit", function(e)
  if not story() or not KIT.move or tick - KIT.move_at > 60 then return end
  if KIT.move == "opar_tongue_lash" and tick - KIT.move_at <= 30 and not KIT.pulled then
    KIT.pulled = true
    local p = try(game.player.get)
    local m = try(game.entities.get, e.entity)
    local at, me = m and m.position, p and p.position
    if at and me then
      try(game.entities.knockback, {entity = e.entity, direction = {x = me.x - at.x, z = me.z - at.z},
        speed = math.min(30, math.max(8, math.sqrt((me.x - at.x) ^ 2 + (me.z - at.z) ^ 2) * 0.22))})
    end
  elseif KIT.move == "opar_croak" then
    try(game.combat.status_add, {entity = e.entity, status = "stop", duration_frames = 90})
    try(game.entities.tint, {entity = e.entity, color = {r = 170, g = 230, b = 120}, frames = 90})
  end
end)

-- a run starts: his story kit goes (the run's moves are the Gauntlet's); it comes back after
moonmod.on("game.session.started", function()
  KIT.set = nil
  try(game.player.moves_clear)
end)

moonmod.on("game.tick", function()
  tick = tick + 1
  if KIT.form.pending or KIT.form.active then
    local p = try(game.player.get)
    if p then KIT.slam(p) end
  end
  if tick % 30 ~= 0 then return end
  place_sphere()
  words()
  join()
  chests()
  KIT.apply()
end)
