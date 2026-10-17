local mod = {}

function mod.on_load()
  if moonmod.settings.get("greeting") then
    moonmod.log("info", "Hello from " .. moonmod.game.id)
  end
end

moonmod.on("game.tick", function(tick)
  if tick.frame == 1 then
    moonmod.storage.set("last_seen_frame", tick.frame)
  end
end)

return mod
