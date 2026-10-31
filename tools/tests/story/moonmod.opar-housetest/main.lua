-- For testing only (docs/OPAR_PLAN.md §8): baby Opar's Atla found (game flag 7001) and item 237 in the bag, on the
-- first frame a save is in play, so --jump house:i01h01@150 plays the cat's scene with him in it.
local done = false
moonmod.on("game.tick", function()
  if done then return end
  local ok, r = pcall(game.world.story_flag_set, {id = 7001, value = true})
  if not (ok and r) then return end
  done = true
  pcall(game.items.give, {id = "chronicle:item:237"})
  moonmod.log("info", "opar house test: baby Opar found, item 237 given")
end)
