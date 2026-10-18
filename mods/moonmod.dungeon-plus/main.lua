-- Dungeon+ folds the compatible Windows dungeon suite into MoonFactory.
-- Status, bestiary and progression are shown through manager Actions and Journal.
local MAX_TIER=5
local function checked(v,e) if v==nil then error(type(e)=="table" and e.message or tostring(e)) end return v end
local function save(k,v) checked(moonmod.storage.set(k,v)) end
local function notify(s) game.ui.notify({message=s:sub(1,190)}) end
local function setting(k,d) local v=moonmod.settings.get(k);return type(v)==type(d) and v or d end
local function integer(v,lo,hi) if type(v)~="number" or v~=v then return lo end return math.max(lo,math.min(hi,math.floor(v))) end
-- Enemy labels used by the legacy Dungeon Feats bestiary and notifications.
-- The table is keyed by Chronicle's native monster-table index.
local ENEMY_NAMES={
 [0]="Master Jacket",[1]="Skeleton Soldier",[2]="Statue",[3]="Dasher",[4]="Werewolf",[5]="FliFli",[6]="Hornet",[7]="Halloween",
 [8]="Cannibal Plant",[9]="Earth Digger",[10]="Sunday",[11]="Monday",[12]="Tuesday",[13]="Wednesday",[14]="Thursday",[15]="Friday",[16]="Saturday",
 [17]="Witch Hellza",[18]="Witch Illza",[19]="Gunny",[20]="Gyon",[21]="Pirate's Chariot",[22]="Auntie Medu",[23]="Captain",[24]="Corcea",[25]="Golem",
 [26]="Mr. Blare",[27]="Dune",[28]="Titan",[29]="King Mimic (Divine Beast Cave)",[30]="Mimic (Divine Beast Cave)",
 [31]="King Mimic (Sun & Moon Temple)",[32]="Mimic (Sun & Moon Temple)",[33]="King Mimic (Moon Sea)",[34]="Mimic (Moon Sea)",
 [35]="Arthur",[36]="Ghost",[37]="Alexander",[38]="Heart",[39]="Club",[40]="Diamond",[41]="Spade",[42]="Joker",[43]="Bomber Head",
 [44]="Mummy",[45]="Lich",[46]="Curse Dancer",[47]="Living Armor",[48]="White Fang",[49]="Moon Bug",[50]="Phantom",[51]="Dragon",
 [52]="Cave Bat",[53]="Evil Bat",[54]="Hell Pockle",[55]="Rash Dasher",[56]="Steel Giant",[57]="Blizzard",[58]="Moon Digger",
 [59]="Dark Flower",[60]="Cursed Rose",[61]="Billy",[62]="Vulcan",[63]="Crabby Hermit",[64]="Space Gyon",[65]="Blue Dragon",[66]="Black Dragon",
 [67]="Mask of Prajna",[68]="Crescent Baron",[69]="Rockanoff",[70]="King Mimic (Wise Owl Forest)",[71]="Mimic (Wise Owl Forest)",
 [72]="King Mimic (Shipwreck)",[73]="Mimic (Shipwreck)",[74]="King Mimic (Gallery of Time)",[75]="Mimic (Gallery of Time)",
 [76]="Ice Arrow",[77]="Sam",[78]="Dran",[79]="Master Utan",[80]="Ice Queen",[81]="King's Curse Coffin",[82]="King's Curse",
 [83]="Minotaur Joe",[84]="Dark Genie",[85]="Dark Genie Right Hand",[86]="Dark Genie Left Hand",[87]="(DG effect c17_)",
 [88]="(DG companion c17_)",[89]="(DG companion c17_)",[90]="(DG companion c17_)",[91]="Wine Keg",[92]="Ice Aura",
 [93]="(DG companion c17_)",[94]="Gol",[95]="Sil",[96]="Yammich",[97]="Statue Dog",[98]="Opar",[99]="Haley Holey",
 [100]="King Prickly",[101]="Ice Barrier",[102]="Ice Prison",[103]="Ice Meteor",[104]="Ice Tornado",[105]="Gacious",[106]="Dark Genie (Final Form)",
 [111]="Gemron (Fire)",[112]="Nikapous",[113]="White Fang (Enhanced)",[114]="Arthur (Enhanced)",[115]="Sil (Enhanced)",[116]="Halloween (Enhanced)"
}
local function apply_generation_settings()
 local monster_min=integer(setting("monsters_per_room_min",150),0,300)/100
 local monster_max=math.max(monster_min,integer(setting("monsters_per_room_max",300),0,300)/100)
 local chest_min=integer(setting("chests_per_room_min",75),0,150)/100
 local chest_max=math.max(chest_min,integer(setting("chests_per_room_max",150),0,150)/100)
 checked(game.dungeons.set_population({monsters_per_room={min=monster_min,max=monster_max},chests_per_room={min=chest_min,max=chest_max}}))
 checked(game.dungeons.set_enemy_survival({chance_percent=integer(setting("enemy_revive_chance",25),0,100)}))
end
local function scaled_feat_reward(amount)
 return integer(math.floor(amount*integer(setting("feats_reward_scale",100),0,300)/100+0.5),0,32767)
end
-- Harder AI's five checked enemy-script edits are bundled as native STB
-- overrides. Owner-scoped resource registration removes them when Dungeon+
-- unloads, and the native reader retains its size and format safeguards.
local HARDER_AI_SCRIPTS={"e01a.stb","e118a.stb","e119a.stb","e124a.stb","e50a.stb"}
for _,name in ipairs(HARDER_AI_SCRIPTS) do
 local override,err=game.resources.override({path="resources/dun/monstor/"..name,game_path="dun/monstor/"..name})
 if not override then moonmod.log("warn","Harder AI script override "..name..": "..(type(err)=="table" and err.message or tostring(err))) end
end
local function default_tier() return integer(moonmod.storage.get("default_tier") or 0,0,MAX_TIER) end
local function floor_key(d,f) return tostring(d)..":"..tostring(f) end
local function tier_of(d,f)
 if d==nil or f==nil then return 0 end
 local t=(moonmod.storage.get("floor_tiers") or {})[floor_key(d,f)]
 return integer(t==nil and default_tier() or t,0,MAX_TIER)
end
local function layout(t)
 checked(game.dungeons.set_layout(t==0 and {} or {rooms=24+t*4,area=30+t*2,room_min=3,room_max=math.min(5,3+math.floor((t-1)/2))}))
 apply_generation_settings()
end
moonmod.on("settings.changed",function(event)
 if event.id=="monsters_per_room_min" or event.id=="monsters_per_room_max" or
    event.id=="chests_per_room_min" or event.id=="chests_per_room_max" or
    event.id=="enemy_revive_chance" then
  apply_generation_settings()
 end
end)
local function visit_key(w) return floor_key(w.dungeon_id,w.floor_id)..":"..tostring(w.floor_seed)..":"..tostring(w.back_floor) end
local function hash(s) local h=5381;for i=1,#s do h=(h*33+s:byte(i))%2147483647 end;return h end

local MUTATORS={
 glass={name="Glass Cannon",text="Deal and take 50% more damage"},
 iron={name="Iron Hide",text="Enemies take 25% less damage and pay double Gilda"},
 bounty={name="Bounty",text="Enemies carry 2.5 times the Gilda"},
 spring={name="Fountain",text="Water slowly refills"},
 scorched={name="Scorched",text="Water drains faster"},
 lucky={name="Lucky Day",text="15% chance to deal double damage"}
}
local MUTATOR_IDS={"glass","iron","bounty","spring","scorched","lucky"}
local function mutator_for(dungeon)
 local world=game.world.get() or {}
 -- Match the legacy mod: town and floor zero never roll a mutator.
 if (dungeon or 0)<0 or (world.floor_id or 0)<=0 then return nil end
 local chance=integer(setting("mutator_chance",35)+3*math.max(0,dungeon or 0),0,100)
 if math.random(100)>chance then return nil end
 return MUTATOR_IDS[math.random(#MUTATOR_IDS)]
end

local active_tier,reward_tier=0,0
local token,entered_frame,seen,cleared=nil,0,0,false
local current_mutator,current_frame=nil,0
local defeated,speed_variants={},{}
local mutator_rewards,tier_scale_records={},{}
local streak,streak_last=0,-10000
local bounty_cursor,bestiary_cursor=0,0
local badges_dirty=true
local function update_combat()
 checked(game.combat.register_formula({id="dungeon-plus-lucky-day",operation="chance_multiply",value=2,
  chance=current_mutator=="lucky" and 15 or 0,priority=90}))
 local out=current_mutator=="glass" and 1.5 or (current_mutator=="iron" and 0.75 or 1)
 local incoming=current_mutator=="glass" and 1.5 or 1
 checked(game.combat.register_formula({id="dungeon-plus-mutator-outgoing",operation="multiply",value=out,priority=110}))
 checked(game.combat.register_player_formula({id="dungeon-plus-mutator-incoming",operation="multiply",value=incoming,priority=110}))
end
local function bounty_records() return moonmod.storage.get("floor_bounties_v1") or {} end
local function bounty_state()
 if not token then return nil end
 local all=bounty_records();local state=all[token]
 if not state then state={target=false,count=0,paid=false};all[token]=state;save("floor_bounties_v1",all) end
 if state.target==false then state.target=nil end
 return state
end
local function save_bounty(state) local all=bounty_records();all[token]=state;save("floor_bounties_v1",all) end
local function sync(world)
 local next_token=world and world.context=="dungeon" and type(world.dungeon_id)=="number" and type(world.floor_id)=="number" and visit_key(world) or nil
 if next_token==token then return end
 local entering_floor=next_token~=nil
 token=next_token;entered_frame=current_frame;seen=0;cleared=false;defeated={};speed_variants={};mutator_rewards={};tier_scale_records={};streak=0;streak_last=-10000
 active_tier=token and tier_of(world.dungeon_id,world.floor_id) or 0;reward_tier=active_tier
 current_mutator=token and mutator_for(world.dungeon_id) or nil
 -- Legacy Floor Bounty resets on every floor_change, including a revisit to
 -- the same dungeon/floor/seed after leaving it. Do not resume stale progress.
 if entering_floor then save_bounty({target=false,count=0,paid=false}) end
 bounty_state();update_combat()
 if not token then layout(default_tier())
 elseif current_mutator then notify("FLOOR MUTATOR: "..MUTATORS[current_mutator].name.." — "..MUTATORS[current_mutator].text) end
end
moonmod.on("game.dungeon.generating",function(e) layout(tier_of(e.dungeon_id,e.floor_id)) end)
moonmod.on("game.world.location_changed",function() sync(game.world.get()) end)

-- Native quest state is the Dungeon Feats/Trophies journal in the manager.
local QUESTS={
 {"first_blood","First Blood",1,100,true},{"hunter","Hunter",100,500,true},
 {"slayer","Slayer",500,2000,true},{"exterminator","Exterminator",2000,10000,true},
 {"streak_10","On a Roll",1,500},{"streak_25","Unstoppable",1,2500},
 {"clear_5","Floor Sweeper",5,500},{"clear_25","Dungeon Cleaner",25,3000},{"clear_100","Purifier",100,12000},
 {"species_20","Collector",20,1500},{"species_60","Completionist",60,8000},{"bounty_25","Bounty Hunter",25,5000}
}
for _,q in ipairs(QUESTS) do
 checked(game.quests.register({id=q[1],title=q[2],description="Dungeon Feats",
  objectives={{id="progress",title=q[5] and (q[3].." enemy defeats") or q[2],target=q[3],event=q[5] and "game.enemy_defeated" or nil}},
  rewards={{kind="currency",amount=q[4]}}}))
 local state=checked(game.quests.get({id=q[1]}))
 if state.status=="registered" then checked(game.quests.start({id=q[1]})) end
end
game.events.subscribe("quests.completed",function(event)
 local prefix="moonmod.dungeon-plus:"
 if type(event.id)~="string" or event.id:sub(1,#prefix)~=prefix then return end
 local adjusted=moonmod.storage.get("feats_reward_scaled_v1") or {}
 if adjusted[event.id] then return end
 local scale=integer(setting("feats_reward_scale",100),0,300)
 for _,reward in ipairs(event.rewards or {}) do
  if reward.kind=="currency" then
   local requested=integer(reward.requested or 0,0,32767)
   local result=type(reward.result)=="table" and reward.result or {}
   local actual=integer(result.added or 0,0,32767)
   local wallet=game.economy.get()
   if wallet and type(wallet.amount)=="number" and type(wallet.max_amount)=="number" then
    local prior=math.max(0,wallet.amount-actual)
    local target=math.min(math.floor(requested*scale/100+0.5),math.max(0,wallet.max_amount-prior))
    local delta=target-actual
    if delta>0 then
     while delta>0 do local chunk=math.min(32767,delta);checked(game.economy.add({amount=chunk}));delta=delta-chunk end
    elseif delta<0 then
     while delta<0 do local chunk=math.min(32767,-delta);checked(game.economy.spend({amount=chunk}));delta=delta+chunk end
    end
   end
   break
  end
 end
 adjusted[event.id]=true;save("feats_reward_scaled_v1",adjusted)
end)
local function advance_quest(id)
 local q=game.quests.get({id=id})
 if q and q.status=="active" then local o=q.objectives and q.objectives[1];if o and (o.progress or 0)<o.target then checked(game.quests.advance({id=id,objective="progress"})) end end
end
local function stats() return moonmod.storage.get("dungeon_feats_v1") or {kills=0,best_streak=0,floors=0,species={},bounties=0} end
local function save_stats(s) save("dungeon_feats_v1",s) end
local function species_total(s) local n=0;for _ in pairs(s) do n=n+1 end;return n end
local function rewards() local r=moonmod.storage.get("clear_rewards_v2");if type(r)~="table" then return {pending={},paid={}} end;r.pending=r.pending or {};r.paid=r.paid or {};return r end
local gems={96,97,98,99,100,101,102,103,104,105,106,107}
local slayers={112,113,114,115,116,117,118,119,120,121}
local function claim(verbose)
 local r=rewards();local count=0
 while #r.pending>0 do local got=game.items.give({id="chronicle:item:"..r.pending[1],count=1});if not got or (got.added or 0)<1 then break end;table.remove(r.pending,1);count=count+1;save("clear_rewards_v2",r) end
 if verbose or count>0 then notify(string.format("Dungeon+ rewards: %d delivered, %d pending",count,#r.pending)) end
end
local function clear_tier_reward()
 local r=rewards();for _,paid in ipairs(r.paid) do if paid==token then return end end
 for _=1,reward_tier do r.pending[#r.pending+1]=gems[math.random(#gems)] end
 if reward_tier>=3 then r.pending[#r.pending+1]=slayers[math.random(#slayers)] end
 r.paid[#r.paid+1]=token;if #r.paid>128 then table.remove(r.paid,1) end;save("clear_rewards_v2",r);claim(true)
end
local function floor_clear()
 if cleared then return end;cleared=true
 local s=stats();s.floors=(s.floors or 0)+1;save_stats(s)
 advance_quest("clear_5");advance_quest("clear_25");advance_quest("clear_100")
 local w=game.world.get() or {}
 -- Match Dungeon Feats' legacy clear payout: (50 + 25 * floor) *
 -- (1 + dungeon), bounded to the native per-call currency limit.
 local clear_reward=scaled_feat_reward((50+25*math.max(0,w.floor_id or 0))*(1+math.max(0,w.dungeon_id or 0)))
 if clear_reward>0 then game.economy.add({amount=clear_reward}) end
 notify("FLOOR CLEARED: +"..clear_reward.." Gilda")
 if reward_tier>0 then clear_tier_reward() end
end
local function set_current(t)
 local w=game.world.get();if not w or w.context~="dungeon" then notify("Enter a dungeon to change this floor's tier");return end
 sync(w);local all=moonmod.storage.get("floor_tiers") or {};all[floor_key(w.dungeon_id,w.floor_id)]=t;save("floor_tiers",all)
 active_tier=t;reward_tier=math.min(reward_tier,t);update_combat();badges_dirty=true;notify("Floor tier "..t.."; layout changes on next generation")
end

local function model_label(id)
 local n=tonumber(id);return n and (ENEMY_NAMES[n] or ("Enemy "..n)) or tostring(id or "Unknown enemy")
end
local function bounty_reward(w)
 local d,f=math.max(0,w.dungeon_id or 0),math.max(0,w.floor_id or 0)
 -- Match the legacy math.floor exactly; in particular, odd dungeon IDs can
 -- produce half-Gilda rewards before the configured percentage is applied.
 return integer(math.floor((150+60*f)*(1+0.5*d)*integer(setting("bounty_reward_percent",100),0,300)/100),0,32767)
end
local function record_defeat(e)
 if e.entity and defeated[e.entity] then return end;if e.entity then defeated[e.entity]=true end
 local s=stats();s.kills=(s.kills or 0)+1
 local frame=type(e.frame)=="number" and e.frame or current_frame
 if frame-streak_last<=480 then streak=streak+1 else streak=1 end;streak_last=frame
 if streak>(s.best_streak or 0) then s.best_streak=streak end
 local key=type(e.native_model_id)=="number" and tostring(e.native_model_id) or (type(e.character_id)=="string" and ("mod:"..e.character_id) or nil)
 local species=s.species or {}
 if key then
  local fresh=species[key]==nil;species[key]=(species[key] or 0)+1;s.species=species
  local species_kills=species[key]
  if fresh then advance_quest("species_20");advance_quest("species_60");notify("Bestiary: "..model_label(key:gsub("^mod:","")).." discovered") end
  if species_kills==10 or species_kills==50 or species_kills==150 then
   local reward=scaled_feat_reward(species_kills*2)
   if reward>0 then game.economy.add({amount=reward}) end
   notify("Bestiary: "..model_label(key:gsub("^mod:","")).." x"..species_kills.."  +"..reward.." Gilda")
  end
 end
 save_stats(s)
 if streak==5 or streak==10 or streak%20==0 then local w=game.world.get() or {};local bonus=scaled_feat_reward(math.min(32767,streak*5*(1+math.max(0,w.dungeon_id or 0))));if bonus>0 then game.economy.add({amount=bonus}) end;notify("KILL STREAK x"..streak.."! +"..bonus.." Gilda") end
 if streak>=10 then advance_quest("streak_10") end;if streak>=25 then advance_quest("streak_25") end
 local b=bounty_state()
 if b and not b.paid and key then
  if not b.target then b.target=key end
  if b.target==key then
   b.count=(b.count or 0)+1;local need=integer(setting("bounty_kills",6),1,20)
   if b.count>=need then
    b.paid=true;b.payout=bounty_reward(game.world.get() or {});save_bounty(b);game.economy.add({amount=b.payout})
    s=stats();s.bounties=(s.bounties or 0)+1;save_stats(s);advance_quest("bounty_25");notify("BOUNTY COMPLETE: +"..b.payout.." Gilda")
   else save_bounty(b) end
  end
 end
 if active_tier>0 then game.economy.add({amount=5*active_tier}) end
end
moonmod.on("game.enemy_defeated",function(e) sync(game.world.get());record_defeat(e) end)

-- Give each native movement actor a stable speed roll. Knockback and falling are left alone.
local function update_speeds()
 local variance=integer(setting("enemy_speed_variance",25),0,50);if not token then return end
 local base_speed=integer(setting("enemy_base_speed_percent",100),60,200)/100
 local q=game.entities.query({type="monster"});if not q or type(q.entities)~="table" then return end
 local alive={}
 for _,enemy in ipairs(q.entities) do
  local h=enemy.entity_id or enemy.id
  if h~=nil then
   local k=type(h)=="string" and h or tostring(h);alive[k]=true
   local m=game.physics.velocity_get({entity=h})
   if m and m.source=="native_movement" and m.velocity then
    local v=m.velocity;local speed=math.sqrt(v.x*v.x+v.z*v.z)
    if speed>0.0001 then
     local r=speed_variants[k]
     if not r and variance>0 then r={roll=(hash(token..":speed:"..k)%20001)/10000-1,base=speed};speed_variants[k]=r
     elseif r and (not r.last or math.abs(speed-r.last)>0.0005) then r.base=speed end
     if r then
      local target=r.base*base_speed*(1+r.roll*variance/100)
      if math.abs(target-speed)>0.0005 then local scale=target/speed;local changed=game.physics.velocity_set({entity=h,velocity={x=v.x*scale,y=v.y,z=v.z*scale}});if changed then r.last=target end end
     end
    end
   end
  end
 end
 for k in pairs(speed_variants) do if not alive[k] then speed_variants[k]=nil end end
end

-- Legacy mutators changed each living enemy's native payout once per life.
-- Apply that through the generation-checked stat API so the game's normal
-- reward path (including wallet caps) remains authoritative.
local function update_mutator_rewards()
 if not token or (current_mutator~="iron" and current_mutator~="bounty") then return end
 local multiplier=current_mutator=="iron" and 2 or 2.5
 local q=game.entities.query({type="monster"});if not q or type(q.entities)~="table" then return end
 local alive={}
 for _,enemy in ipairs(q.entities) do
  local handle=enemy.entity_id or enemy.id
  if handle~=nil then
   local key=type(handle)=="string" and handle or tostring(handle);alive[key]=true
   local reward=enemy.combat and enemy.combat.reward_money
   if enemy.revealed==true and type(reward)=="number" and not mutator_rewards[key] then
    local target=math.min(2147483647,math.floor(reward*multiplier+0.5))
    local changed=game.entities.set_stats({entity=handle,reward_money=target})
    if changed then mutator_rewards[key]=true end
   end
  end
 end
 for key in pairs(mutator_rewards) do if not alive[key] then mutator_rewards[key]=nil end end
end

-- Ascension owns tier stat writes when loaded so its champion and dungeon
-- multipliers share the same unmodified enemy baseline. Dungeon+ still works
-- by itself and applies these legacy per-tier native stats here.
local function update_tier_enemy_stats()
 if not token or active_tier<=0 then return end
 local ok,owner=pcall(game.scripts.call_function,{id="moonmod.ascension:owns_dungeon_tier_scaling"})
 if ok and type(owner)=="table" and owner.active==true then return end
 local q=game.entities.query({type="monster"});if not q or type(q.entities)~="table" then return end
 local alive={}
 for _,enemy in ipairs(q.entities) do
  local handle=enemy.entity_id or enemy.id
  if handle~=nil then
   local key=type(handle)=="string" and handle or tostring(handle);alive[key]=true
   if enemy.revealed==true and not tier_scale_records[key] then
    local hp=enemy.health and tonumber(enemy.health.maximum) or 0
    local combat=enemy.combat or {}
    if hp>0 then
     local request={entity=handle,hp=math.min(1000000,math.floor(hp*(1+setting("tier_hp_percent",35)*active_tier/100)+0.5)),
      max_hp=math.min(1000000,math.floor(hp*(1+setting("tier_hp_percent",35)*active_tier/100)+0.5)),
      defense=math.min(32767,(tonumber(combat.defense) or 0)+setting("tier_defense",2)*active_tier),
      reward_money=math.min(2147483647,math.floor(math.max(0,tonumber(combat.reward_money) or 0)*(1+setting("tier_gilda_percent",40)*active_tier/100)+0.5))}
     local changed=game.entities.set_stats(request)
     if changed then tier_scale_records[key]=true end
    end
   end
  end
 end
 for key in pairs(tier_scale_records) do if not alive[key] then tier_scale_records[key]=nil end end
end

-- Keep UI inside the existing manager's Actions, Skills, Quests and Journal pages.
for _,a in ipairs({
 {"tier_up","This Floor: Raise Tier","Cycle this floor's tier from 0 to 5"},
 {"tier_reset","This Floor: Normal","Set the current floor's tier to zero"},
 {"default_up","Future Floors: Raise Default","Cycle the default tier for floors without an override"},
 {"claim_rewards","Claim Clear Rewards","Collect queued gems and slayers when attachment space is available"},
 {"status","Dungeon+ Status","Show tier, mutator, bounty, and pending rewards"},
 {"population_status","Room Population Status","Show realized rooms, target density, and native placement limits"},
 {"feats_status","Dungeon Feats Status","Show kill, streak, clear, bestiary, and bounty totals"},
 {"bestiary","Browse Bestiary","Cycle known and unseen native enemy types and mod enemies"},
 {"bounty_status","Floor Bounty Status","Inspect this floor's bounty target and progress"},
 {"mutator_status","Floor Mutator Status","Inspect this floor's mutator and effect"}
}) do checked(game.ui.register({id=a[1],label=a[2],description=a[3]})) end
local function publish_badges()
 local b=moonmod.storage.get("floor_tiers") or {};b.default=default_tier();checked(game.dungeons.set_badges(b))
end
moonmod.on("ui.action",function(a)
 if a.id=="tier_up" then local w=game.world.get();if not w or w.context~="dungeon" then notify("Enter a dungeon first");return end;set_current((tier_of(w.dungeon_id,w.floor_id)+1)%6)
 elseif a.id=="tier_reset" then set_current(0)
 elseif a.id=="default_up" then local t=(default_tier()+1)%6;save("default_tier",t);layout(t);notify("Future floors default to Tier "..t)
 elseif a.id=="claim_rewards" then claim(true)
 elseif a.id=="status" then sync(game.world.get());local b=bounty_state();notify(string.format("DUNGEON+ T%d; default T%d; %s; bounty %s; pending %d",active_tier,default_tier(),current_mutator and MUTATORS[current_mutator].name or "no mutator",b and b.target and ((b.count or 0).."/"..integer(setting("bounty_kills",6),1,20)) or "unassigned",#rewards().pending))
 elseif a.id=="population_status" then
  local w=game.world.get();if not w or w.context~="dungeon" then notify("Enter a dungeon to inspect room population");return end
  local rooms=integer(w.room_count or 0,0,10000);local mmin=integer(setting("monsters_per_room_min",150),0,300)/100;local mmax=math.max(mmin,integer(setting("monsters_per_room_max",300),0,300)/100)
  local cmin=integer(setting("chests_per_room_min",75),0,150)/100;local cmax=math.max(cmin,integer(setting("chests_per_room_max",150),0,150)/100)
  local back=w.back_floor==true
  local native_monsters=back and 8 or 15
  local monster_bonus=integer(w.monster_bonus_percent or 0,0,300)
  local chest_bonus=integer(w.chest_bonus_percent or 0,0,300)
  local native_monster_target=math.ceil(native_monsters*(100+monster_bonus)/100)
  local native_chest_min=math.ceil(4*(100+chest_bonus)/100)
  local native_chest_max=math.ceil(7*(100+chest_bonus)/100)
  local monster_scale=(100+monster_bonus)/100
  local chest_scale=(100+chest_bonus)/100
  local monster_target=math.min(255,math.max(native_monster_target,math.ceil(rooms*mmin*monster_scale)))
  -- Native code reserves 16 of 64 physical box slots for mimics/specials; regular
  -- generated chest targets therefore cap at 48. The event table has 384 slots.
  local chest_target=math.min(48,math.max(native_chest_min,math.ceil(rooms*cmin*chest_scale)))
  local monster_high=math.min(255,math.max(native_monster_target,math.ceil(rooms*mmax*monster_scale)))
  local chest_high=math.min(48,math.max(native_chest_max,math.ceil(rooms*cmax*chest_scale)))
  notify(string.format("ROOMS %d | MONSTER TARGET %d-%d (native %d +%d%%; cap 255) | CHEST TARGET %d-%d (native 4-7 +%d%%; cap 48; placements may fall short)",rooms,monster_target,monster_high,native_monsters,monster_bonus,chest_target,chest_high,chest_bonus))
 elseif a.id=="feats_status" then local s=stats();notify(string.format("KILLS %d; STREAK %d (BEST %d); CLEARS %d; SPECIES %d; BOUNTIES %d",s.kills or 0,streak,s.best_streak or 0,s.floors or 0,species_total(s.species or {}),s.bounties or 0))
 elseif a.id=="bestiary" then
  local records=stats().species or {};local keys={}
  for id in pairs(ENEMY_NAMES) do keys[#keys+1]=tostring(id) end
  for key,count in pairs(records) do
   local stable=tostring(key);local numeric=tonumber(stable)
   if count>0 and (stable:sub(1,4)=="mod:" or (numeric~=nil and ENEMY_NAMES[numeric]==nil)) then keys[#keys+1]=stable end
  end
  table.sort(keys,function(left,right)
   local a_num,b_num=tonumber(left),tonumber(right)
   if a_num and b_num then return a_num<b_num end
   if a_num then return true end;if b_num then return false end
   return left<right
  end)
  if #keys==0 then notify("Bestiary is empty");return end
  bestiary_cursor=bestiary_cursor%#keys+1;local key=keys[bestiary_cursor];local count=records[key] or 0
  local progress=count==0 and "not seen yet" or (count.." defeats; "..(count<10 and "next reward at 10" or count<50 and "next reward at 50" or count<150 and "next reward at 150" or "milestones complete"))
  notify(model_label(key:gsub("^mod:",""))..": "..progress)
 elseif a.id=="bounty_status" then sync(game.world.get());local b=bounty_state();if not b or not b.target then notify("Bounty target is assigned when the floor's enemy roster is available");return end;notify("BOUNTY "..model_label(b.target)..": "..(b.count or 0).."/"..integer(setting("bounty_kills",6),1,20)..(b.paid and " COMPLETE" or ""))
 elseif a.id=="mutator_status" then sync(game.world.get());if not current_mutator then notify("No mutator on this floor");return end;notify(MUTATORS[current_mutator].name..": "..MUTATORS[current_mutator].text)
 end
 if a.id=="tier_up" or a.id=="tier_reset" or a.id=="default_up" then badges_dirty=true end
end)
checked(game.scripts.register_function({id="current_tier",description="Current floor's Dungeon+ tier and scaling settings"},function()
 sync(game.world.get())
 return {tier=active_tier,mutator=current_mutator or "",hp_per_tier_percent=setting("tier_hp_percent",35),
  defense_per_tier=setting("tier_defense",2),gilda_per_tier_percent=setting("tier_gilda_percent",40),
  xp_per_tier_percent=setting("tier_xp_percent",25),champion_chance_per_tier=setting("tier_champion_chance",4)}
end))

moonmod.on("game.tick",function(e)
 current_frame=type(e.frame)=="number" and e.frame or current_frame+1
 if current_frame%15~=0 then return end
 if badges_dirty then publish_badges() end
 local w=game.world.get();sync(w)
 if streak>0 and current_frame-streak_last>480 then streak=0 end
 if token then
  local bounty=bounty_state()
  if bounty and not bounty.target then
   local roster=game.entities.query({type="monster"})
   for _,enemy in ipairs(roster and roster.entities or {}) do
    local key=type(enemy.native_model_id)=="number" and tostring(enemy.native_model_id) or
      (type(enemy.character)=="string" and ("mod:"..enemy.character) or nil)
    -- Legacy Floor Bounty skips key carriers and chooses the first living
    -- ordinary enemy in native slot order.
    local drop=enemy.definition and enemy.definition.drop_item
    if key and (type(drop)~="number" or drop<0) then
     bounty.target=key;save_bounty(bounty);break
    end
   end
  end
 end
 if token and not cleared then
  local p=game.player.get();local c=game.combat.get()
  if p and p.hp>0 and c then
   seen=math.max(seen,c.enemy_count or 0)
   if current_frame-entered_frame>180 and seen>0 and c.enemy_count==0 then floor_clear() end
  end
 end
 if token and current_mutator and current_frame%60==0 then
  if current_mutator=="spring" then game.player.thirst_set({restore=1.5}) elseif current_mutator=="scorched" then game.player.thirst_set({restore=-1.0}) end
 end
 update_speeds()
 update_mutator_rewards()
 update_tier_enemy_stats()
end)

-- Weapon table edits from the legacy Expanded Data package (DarkCloud-Expanded, BSD-2-Clause).
local LEGACY_WEAPON_BALANCE = {
  [259] = {endurance=30},
  [263] = {elem={15,0,0,0,20}, speed=70},
  [265] = {attack=25, durability=50, elem={0,0,8,0,0}, endurance=30, vs_monster={0,0,90,0,0,0,0,0,0,0}},
  [266] = {endurance=33, speed=80},
  [269] = {flags=8192},
  [271] = {attack_max=180, buildup_mask0=65536, hole={2,1,1,0,0,0}, magic_max=180},
  [272] = {hole={2,1,1,0,0,0}},
  [274] = {hole={2,1,1,0,0,0}},
  [275] = {speed=70},
  [281] = {attack_max=190, buildup_mask0=524288},
  [282] = {flags=4},
  [283] = {durability=35, magic=17, vs_monster={0,0,0,0,0,0,0,10,0,0}},
  [284] = {durability=45, endurance=25, hole={2,1,1,0,0,0}},
  [285] = {durability=60},
  [286] = {speed=60},
  [287] = {attack=45, buildup_mask0=2147483648, durability=57, elem={0,10,15,0,0}, hole={2,1,1,0,0,0}, speed=70, vs_monster={0,15,0,0,0,15,0,15,0,20}},
  [288] = {vs_monster={0,10,0,15,0,10,10,10,10,10}},
  [289] = {elem={0,15,15,0,15}, endurance=44, magic=45, speed=70, vs_monster={0,15,0,0,0,15,0,15,10,55}},
  [290] = {durability=38, magic=26},
  [291] = {elem={6,0,10,0,0}, speed=60, vs_monster={0,0,0,0,10,0,10,0,10,0}},
  [292] = {durability=47, endurance=47, magic=37, vs_monster={7,7,7,7,7,8,7,10,7,8}},
  [294] = {endurance=50, magic=32, speed=70},
  [298] = {attack_max=999},
  [300] = {attack=6, elem={4,0,0,0,0}, magic=2},
  [304] = {attack=11, endurance=30},
  [305] = {speed=60},
  [311] = {flags=4096},
  [319] = {magic=10},
  [320] = {buildup_mask0=8},
  [321] = {attack_max=100, buildup_mask0=0, durability=65, flags=64, hole={2,1,0,1,0,0}, magic_max=678},
  [322] = {endurance=25},
  [328] = {attack=30, endurance=25},
  [332] = {attack=15, magic=30},
  [333] = {attack=30, attack_max=50, magic=20},
  [335] = {attack=23},
  [336] = {flags=2048},
  [340] = {flags=8192},
  [343] = {attack=28, buildup_mask0=8256, elem={0,0,0,10,0}, magic=28},
  [344] = {attack_max=90, buildup_mask0=128, magic_max=72, vs_monster={0,0,0,20,0,20,0,0,0,0}},
  [348] = {attack=45, attack_max=65, endurance=35},
  [349] = {attack=48, attack_max=95, endurance=40},
  [350] = {attack=54, attack_max=90, endurance=43},
  [351] = {attack=56, attack_max=120, endurance=50, flags=1024},
  [352] = {attack=60, attack_max=109, endurance=50},
  [353] = {attack=65, attack_max=105, endurance=60},
  [354] = {attack=73, attack_max=160, endurance=60},
  [355] = {attack=130, attack_max=230, endurance=65},
  [356] = {attack=120, attack_max=266, endurance=85},
  [357] = {hole={2,1,1,1,0,0}},
  [358] = {attack=15, attack_max=15, endurance=20},
  [359] = {attack=50, attack_max=89, endurance=60},
  [360] = {attack=80, attack_max=165, endurance=60},
  [364] = {attack=37, attack_max=47},
  [365] = {attack=45, attack_max=70, buildup_mask0=4096},
  [366] = {attack=35, attack_max=55},
  [367] = {attack=45, attack_max=75},
  [368] = {attack=49, attack_max=102, magic_max=80},
  [369] = {attack=63, attack_max=158, buildup_mask0=0, magic_max=105},
  [370] = {attack=65, attack_max=114},
  [371] = {attack=79, attack_max=143},
  [372] = {attack=85, attack_max=135},
  [373] = {attack=143, attack_max=271},
  [374] = {attack=49, attack_max=80, buildup_mask0=256},
  [375] = {attack=63, attack_max=87},
}
local legacy_weapon_changes, legacy_weapon_failures = 0, 0
for item, fields in pairs(LEGACY_WEAPON_BALANCE) do
  local request = {id = tonumber(item)}
  for key, value in pairs(fields) do request[key] = value end
  local result, err = game.weapons.definition_set(request)
  if result then legacy_weapon_changes = legacy_weapon_changes + 1
  else
    legacy_weapon_failures = legacy_weapon_failures + 1
    moonmod.log("warn", "Expanded Data weapon " .. item .. " was not applied: " .. (type(err) == "table" and err.message or tostring(err)))
  end
end
if legacy_weapon_failures > 0 then moonmod.log("warn", string.format("Expanded Data applied %d of %d weapon definitions", legacy_weapon_changes, legacy_weapon_changes + legacy_weapon_failures)) end
-- Legacy Expanded Data prices (DarkCloud-Expanded, BSD-2-Clause).
-- Daily rotations below use the native adventure-day counter from game.world.get().
local LEGACY_PRICES={
  [133]={buy=400,sell=200},
  [134]={buy=400,sell=200},
  [181]={buy=400,sell=200},
  [186]={sell=75},
  [187]={sell=112},
  [188]={sell=100},
  [189]={sell=105},
  [190]={sell=95},
  [193]={sell=75},
  [197]={sell=100},
  [199]={sell=100},
  [224]={buy=600,sell=300},
  [225]={buy=750,sell=375},
  [226]={buy=300,sell=150},
  [228]={buy=900,sell=450},
  [229]={buy=1200,sell=600},
  [230]={buy=1500,sell=750},
  [231]={buy=5000,sell=2500},
  [259]={buy=500,sell=167},
  [260]={buy=650,sell=217},
  [261]={sell=833},
  [262]={buy=900,sell=300},
  [263]={buy=5000,sell=1667},
  [264]={buy=1800,sell=600},
  [265]={buy=3000,sell=1000},
  [266]={buy=4500,sell=1500},
  [267]={buy=9000,sell=3000},
  [268]={buy=3000,sell=1000},
  [269]={buy=5500,sell=1833},
  [270]={buy=1250,sell=417},
  [271]={buy=12000,sell=4000},
  [272]={buy=7888,sell=2629},
  [273]={buy=3642,sell=1214},
  [274]={buy=9500,sell=3167},
  [275]={buy=12726,sell=4242},
  [276]={buy=18000,sell=6000},
  [278]={buy=12000,sell=4000},
  [279]={buy=18000,sell=6000},
  [280]={buy=30000,sell=10000},
  [281]={buy=9021,sell=3007},
  [282]={buy=4500,sell=1500},
  [283]={buy=1900,sell=633},
  [284]={buy=2250,sell=750},
  [285]={buy=11500,sell=3833},
  [286]={buy=2500,sell=833},
  [287]={buy=5000,sell=1667},
  [288]={buy=6000,sell=2000},
  [289]={buy=8000,sell=2667},
  [290]={buy=1001,sell=334},
  [291]={buy=2150,sell=717},
  [292]={buy=9507,sell=3169},
  [293]={buy=5300,sell=1767},
  [294]={buy=10000,sell=3333},
  [295]={buy=23331,sell=7777},
  [296]={buy=32767,sell=12345},
  [297]={buy=32767,sell=13337},
  [298]={buy=32767,sell=15000},
  [301]={buy=900,sell=300},
  [302]={buy=4200,sell=1400},
  [303]={buy=1999,sell=666},
  [304]={buy=750,sell=250},
  [305]={buy=2800,sell=933},
  [306]={buy=3100,sell=1033},
  [307]={buy=5525,sell=1842},
  [308]={buy=9015,sell=3005},
  [309]={buy=18000,sell=6000},
  [310]={buy=2552,sell=851},
  [311]={buy=6666,sell=2222},
  [312]={buy=14000,sell=4667},
  [313]={buy=32767,sell=11111},
  [316]={buy=1700,sell=567},
  [317]={buy=7035,sell=2345},
  [318]={buy=6000,sell=2000},
  [319]={buy=2704,sell=901},
  [320]={buy=3250,sell=1083},
  [321]={buy=1701,sell=567},
  [322]={buy=8000,sell=2667},
  [323]={buy=12000,sell=4000},
  [324]={buy=21816,sell=7272},
  [325]={buy=19998,sell=6666},
  [327]={buy=2600,sell=867},
  [328]={buy=2300,sell=767},
  [329]={buy=32767,sell=11009},
  [330]={buy=2,sell=1},
  [333]={buy=3800,sell=1267},
  [334]={buy=4300,sell=1433},
  [335]={buy=2500,sell=833},
  [336]={buy=8000,sell=2667},
  [337]={buy=5000,sell=1667},
  [338]={buy=9000,sell=3000},
  [339]={buy=8000,sell=2667},
  [340]={buy=16314,sell=5438},
  [341]={buy=24000,sell=8000},
  [343]={buy=2007,sell=669},
  [344]={buy=3500,sell=1167},
  [345]={buy=32767,sell=12000},
  [346]={buy=2,sell=1},
  [349]={buy=3400,sell=1133},
  [350]={buy=4000,sell=1333},
  [351]={buy=4700,sell=1567},
  [352]={buy=6000,sell=2000},
  [353]={buy=5000,sell=1667},
  [354]={buy=7000,sell=2333},
  [355]={buy=13500,sell=4500},
  [356]={buy=21036,sell=7012},
  [357]={buy=32767,sell=11941},
  [359]={buy=5555,sell=1852},
  [360]={buy=6500,sell=2167},
  [361]={buy=2,sell=1},
  [362]={buy=2,sell=1},
  [365]={buy=4000,sell=1333},
  [368]={buy=6000,sell=2000},
  [369]={buy=10450,sell=3483},
  [370]={buy=11943,sell=3981},
  [371]={buy=12018,sell=4006},
  [372]={buy=24000,sell=8000},
  [373]={buy=24000,sell=8000},
  [374]={buy=3000,sell=1000},
  [375]={buy=9000,sell=3000},
}
local price_changes,price_failures=0,0
for item,price in pairs(LEGACY_PRICES) do
 local args={item_id=tonumber(item)};if price.buy then args.buy_price=price.buy end;if price.sell then args.sell_price=price.sell end
 if game.shops.set_price(args) then price_changes=price_changes+1 else price_failures=price_failures+1 end
end
if price_failures>0 then moonmod.log("warn",string.format("Dungeon+ shop rebalance rejected %d of %d item prices",price_failures,price_changes+price_failures)) end

-- Legacy Expanded Data daily stock (five adventure-day cycle).
-- Item IDs and pools are from the source Windows package; Chronicle restores changed lists on unload.
local SHOP_ROTATION={
 [0]={{181,181,224}, {95,96,97,98,99,100,101,102,103,104,105,106}, {197,199}, {132,133,134,135,150,154}, {259,260,262,270,290,301,304}},
 [1]={{186,188,189}, {132,133,134,135,150,154}, {264,270,283,284,286,291,301,303,304,316,321,328}, {181,181,225}, {95,96,97,98,99,100,101,102,103,104,105,106}},
 [8]={{261,265,282,284,286,302,305,319,327,328,333,335,343}, {261,265,282,284,286,302,305,319,327,328,333,335,343}, {261,265,282,284,286,302,305,319,327,328,333,335,343}, {261,265,282,284,286,302,305,319,327,328,333,335,343}, {261,265,282,284,286,302,305,319,327,328,333,335,343}},
 [12]={{95,96,97,98,99,100,101,102,103,104,105,106}, {186,188,189,197,199}, {132,133,134,135,150,154}, {111,112,113,114,115,116,117,118,119,120}, {181}},
 [9]={{132,133,134,135,150}, {263,272,282,288,293,306,318,334,337,344,349,350,359}, {181,181,228}, {95,96,97,98,99,100,101,102,103,104,105,106}, {169,186,188,189,193,197,199}},
 [10]={{181,181,229}, {95,96,97,98,99,100,101,102,103,104,105,106}, {118,119}, {132,133,134,135,150,154}, {272,288,281,307,322,334,344,351,352,353}},
 [11]={{274,281,285,292,294,308,322,336,338,339,354,360,368,375}, {181,181,230}, {169,186,187,188,189,193,197,199}, {132,133,134,135,150,154}, {181,181,230}},
}
local base_shop_items,last_shop_day,last_shop_attempt_frame=nil,nil,nil
local function without_item(list,item)
 local out={};for _,value in ipairs(list) do if value~=item then out[#out+1]=value end end;return out
end
local function load_shop_baseline()
 local base={}
 for shop=0,17 do
  local result,err=game.shops.get({shop_no=shop})
  if not result or type(result.items)~="table" then
   moonmod.log("warn","Expanded Data could not read shop "..shop..": "..(type(err)=="table" and err.message or tostring(err)));return nil
  end
  base[shop]={};for _,entry in ipairs(result.items) do base[shop][#base[shop]+1]=entry.item_no end
 end
 base[0]=without_item(base[0],92)
 for _,item in ipairs({118,119}) do
  local found=false;for _,value in ipairs(base[17]) do if value==item then found=true end end
  if not found then base[17][#base[17]+1]=item end
 end
 return base
end
local function update_daily_shops(day)
 if last_shop_attempt_frame and current_frame-last_shop_attempt_frame<300 then return end
 last_shop_attempt_frame=current_frame
 if not base_shop_items then base_shop_items=load_shop_baseline();if not base_shop_items then return end end
 local cycle=(day%5)+1
 local complete=true
 for shop=0,17 do
  local items={};for _,item in ipairs(base_shop_items[shop]) do items[#items+1]=item end
  local rotation=SHOP_ROTATION[shop];local pool=rotation and rotation[cycle]
  if pool and #pool>0 and #items<20 then
   -- Duplicate IDs in the source pools preserve their weighted selection.
   local index=((day*7919+shop*104729)%#pool)+1
   items[#items+1]=pool[index]
  end
  local current,read_err=game.shops.get({shop_no=shop})
  if current and type(current.items)=="table" then
   local same=#current.items==#items
   if same then for index,item in ipairs(items) do if current.items[index].item_no~=item then same=false;break end end end
   if not same then
    local result,err=game.shops.set_items({shop_no=shop,items=items})
    if not result then
     complete=false
     moonmod.log("warn","Expanded Data could not update shop "..shop..": "..(type(err)=="table" and err.message or tostring(err)))
    end
   end
  else
   complete=false
   moonmod.log("warn","Expanded Data could not refresh shop "..shop..": "..(type(read_err)=="table" and read_err.message or tostring(read_err)))
  end
 end
 if complete then last_shop_day=day else last_shop_day=nil end
end
moonmod.on("game.tick",function()
 local ok,world=pcall(game.world.get)
 if not ok or type(world)~="table" or type(world.day)~="number" then return end
 if world.day~=last_shop_day then update_daily_shops(math.floor(world.day)) end
end)
moonmod.on("game.world.location_changed",function() last_shop_day=nil end)

checked(game.input.bind({id="entrance_tier_down",keys={"["}}))
checked(game.input.bind({id="entrance_tier_up",keys={"]"}}))
moonmod.on("game.tick",function()
 local down=game.input.consume({id="entrance_tier_down"});local up=game.input.consume({id="entrance_tier_up"})
 if not ((down and down.pressed) or (up and up.pressed)) then return end
 local s=game.dungeons.selection();if not s then return end
 local t=moonmod.storage.get("floor_tiers") or {};local delta=up and up.pressed and 1 or -1
 t[floor_key(s.dungeon_id,s.floor_id)]=(tier_of(s.dungeon_id,s.floor_id)+delta)%6;save("floor_tiers",t);badges_dirty=true
end)
sync(game.world.get());update_combat();layout(default_tier())
moonmod.log("info",string.format("Dungeon+ initialized: %d weapon definitions, %d legacy prices, daily stock rotation, feats, bounties, mutators, tiers, room-scaled population and enemy variety",legacy_weapon_changes,price_changes))
