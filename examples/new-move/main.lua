-- Toan's Overhead Chop: a motion of our own (resources/anims/toan_overhead_chop.json, written by make_anims.py)
-- played as a move when he attacks out of a run.

-- 1. Register the motion. The engine appends it to Toan's motions whenever his model loads in a dungeon.
assert(game.animations.player_register({id = "toan_overhead_chop", file = "resources/anims/toan_overhead_chop.json"}))

-- 2. A move that plays it: what starts it, how fast, how far it carries him, and when its hits land.
assert(game.player.moves_set({moves = {
  {id = "overhead_chop", character = "toan", trigger = "run_attack", run_frames = 12,
   animation = "toan_overhead_chop", speed = 0.9,
   lunge = 1.6, lunge_decay = 0.2, cooldown = 20,
   hits = {{at = 0.4, radius = 10, reach = 7, damage = 1.6, knockback = 4, heavy = true, burst = "sparks"}},
   cues = {{at = 0.1, sound = "voice"}, {at = 0.3, sound = "swing_heavy", trail = "heavy"}}},
}}))

moonmod.on("game.player.move", function(e)
  moonmod.log("info", "move started: " .. tostring(e.id) .. " (" .. tostring(e.character) .. ")")
end)
