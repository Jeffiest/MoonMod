-- Dungeon+ folds the compatible Windows dungeon suite into MoonFactory.
-- Status, bestiary and progression are shown through manager Actions and Journal.
local MAX_TIER=5
local function checked(v,e) if v==nil then error(type(e)=="table" and e.message or tostring(e)) end return v end
local function save(k,v) checked(moonmod.storage.set(k,v)) end
local function notify(s) game.ui.notify({message=s:sub(1,190)}) end
local function setting(k,d) local v=moonmod.settings.get(k);return type(v)==type(d) and v or d end
local function integer(v,lo,hi) if type(v)~="number" or v~=v then return lo end return math.max(lo,math.min(hi,math.floor(v))) end
local function default_tier() return integer(moonmod.storage.get("default_tier") or 1,0,MAX_TIER) end
local function floor_key(d,f) return tostring(d)..":"..tostring(f) end
local function tier_of(d,f)
 if d==nil or f==nil then return 0 end
 local t=(moonmod.storage.get("floor_tiers") or {})[floor_key(d,f)]
 return integer(t==nil and default_tier() or t,0,MAX_TIER)
end
local function layout(t)
 checked(game.dungeons.set_layout(t==0 and {} or {rooms=24+t*4,area=30+t*2,room_min=3,room_max=math.min(5,3+math.floor((t-1)/2))}))
end
local function visit_key(w) return floor_key(w.dungeon_id,w.floor_id)..":"..tostring(w.floor_seed)..":"..tostring(w.back_floor) end
local function hash(s) local h=5381;for i=1,#s do h=(h*33+s:byte(i))%2147483647 end;return h end

local MUTATORS={
 glass={name="Glass Cannon",text="Deal and take 50% more damage"},
 iron={name="Iron Hide",text="Enemies take 25% less damage and pay double Gilda"},
 bounty={name="Bounty",text="Enemies carry 2.5 times the Gilda"},
 spring={name="Fountain",text="Water slowly refills"},
 scorched={name="Scorched",text="Water drains faster"}
}
local MUTATOR_IDS={"glass","iron","bounty","spring","scorched"}
local function mutator_for(token,dungeon)
 local all=moonmod.storage.get("floor_mutators") or {}
 if all[token]~=nil then return all[token]~=false and all[token] or nil end
 local chance=integer(setting("mutator_chance",35)+3*math.max(0,dungeon or 0),0,100)
 if hash(token..":chance")%100>=chance then all[token]=false;save("floor_mutators",all);return nil end
 local id=MUTATOR_IDS[hash(token..":type")%#MUTATOR_IDS+1]
 all[token]=id;save("floor_mutators",all);return id
end

local active_tier,reward_tier=0,0
local token,entered_frame,seen,zero_frames,cleared=nil,0,false,0,false
local current_mutator,current_frame=nil,0
local defeated,speed_variants={},{}
local streak,streak_last=0,-10000
local bounty_cursor,bestiary_cursor=0,0
local badges_dirty=true
local function update_combat()
 checked(game.combat.register_formula({id="dungeon-plus-scaling",operation="multiply",value=1/(1+0.25*active_tier),priority=100}))
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
 token=next_token;entered_frame=current_frame;seen=false;zero_frames=0;cleared=false;defeated={};speed_variants={}
 active_tier=token and tier_of(world.dungeon_id,world.floor_id) or 0;reward_tier=active_tier
 current_mutator=token and mutator_for(token,world.dungeon_id) or nil
 bounty_state();update_combat()
 if not token then layout(default_tier())
 elseif current_mutator then notify("FLOOR MUTATOR: "..MUTATORS[current_mutator].name) end
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
 return integer(math.floor((150+60*f)*(1+0.5*d)*setting("bounty_reward_percent",100)/100+0.5),1,32767)
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
  if fresh then advance_quest("species_20");advance_quest("species_60") end
 end
 save_stats(s)
 if streak==5 or streak==10 or streak%20==0 then local w=game.world.get() or {};local bonus=math.min(32767,streak*5*(1+math.max(0,w.dungeon_id or 0)));game.economy.add({amount=math.max(1,bonus)}) end
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
 if current_mutator=="iron" or current_mutator=="bounty" then
  local base=type(e.reward_money)=="number" and e.reward_money or 0;local mul=current_mutator=="iron" and 2 or 2.5
  local extra=math.min(32767,math.floor(base*(mul-1)+0.5));if extra>0 then game.economy.add({amount=extra}) end
 end
 if active_tier>0 then game.economy.add({amount=5*active_tier}) end
end
moonmod.on("game.enemy_defeated",function(e) sync(game.world.get());record_defeat(e) end)

-- Give each native movement actor a stable speed roll. Knockback and falling are left alone.
local function update_speeds()
 local variance=integer(setting("enemy_speed_variance",25),0,50);if not token then return end
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
      local target=r.base*(1+r.roll*variance/100)
      if math.abs(target-speed)>0.0005 then local scale=target/speed;local changed=game.physics.velocity_set({entity=h,velocity={x=v.x*scale,y=v.y,z=v.z*scale}});if changed then r.last=target end end
     end
    end
   end
  end
 end
 for k in pairs(speed_variants) do if not alive[k] then speed_variants[k]=nil end end
end

-- Keep UI inside the existing manager's Actions, Skills, Quests and Journal pages.
for _,a in ipairs({
 {"tier_up","This Floor: Raise Tier","Cycle this floor's tier from 0 to 5"},
 {"tier_reset","This Floor: Normal","Set the current floor's tier to zero"},
 {"default_up","Future Floors: Raise Default","Cycle the default tier for floors without an override"},
 {"claim_rewards","Claim Clear Rewards","Collect queued gems and slayers when attachment space is available"},
 {"status","Dungeon+ Status","Show tier, mutator, bounty, and pending rewards"},
 {"feats_status","Dungeon Feats Status","Show kill, streak, clear, bestiary, and bounty totals"},
 {"bestiary","Browse Bestiary","Cycle enemy types recorded by Dungeon Feats"},
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
 elseif a.id=="feats_status" then local s=stats();notify(string.format("KILLS %d; BEST STREAK %d; CLEARS %d; SPECIES %d; BOUNTIES %d",s.kills or 0,s.best_streak or 0,s.floors or 0,species_total(s.species or {}),s.bounties or 0))
 elseif a.id=="bestiary" then local records=stats().species or {};local keys={};for k,v in pairs(records) do if v>0 then keys[#keys+1]=k end end;table.sort(keys);if #keys==0 then notify("No bestiary entries yet");return end;bestiary_cursor=bestiary_cursor%#keys+1;local k=keys[bestiary_cursor];notify(model_label(k:gsub("^mod:",""))..": "..records[k].." defeats")
 elseif a.id=="bounty_status" then sync(game.world.get());local b=bounty_state();if not b or not b.target then notify("Bounty target appears after the first enemy type is defeated");return end;notify("BOUNTY "..model_label(b.target)..": "..(b.count or 0).."/"..integer(setting("bounty_kills",6),1,20)..(b.paid and " COMPLETE" or ""))
 elseif a.id=="mutator_status" then sync(game.world.get());if not current_mutator then notify("No mutator on this floor");return end;notify(MUTATORS[current_mutator].name..": "..MUTATORS[current_mutator].text)
 end
 if a.id=="tier_up" or a.id=="tier_reset" or a.id=="default_up" then badges_dirty=true end
end)
checked(game.scripts.register_function({id="current_tier",description="Current floor's Dungeon+ tier"},function() sync(game.world.get());return {tier=active_tier,mutator=current_mutator or ""} end))

moonmod.on("game.tick",function(e)
 current_frame=type(e.frame)=="number" and e.frame or current_frame+1
 if current_frame%15~=0 then return end
 if badges_dirty then publish_badges() end
 local w=game.world.get();sync(w)
 if token and not cleared and current_frame-entered_frame>=180 then
  local p=game.player.get();local c=game.combat.get()
  if p and p.hp>0 and c then if c.enemy_count>0 then seen=true;zero_frames=0 elseif seen then zero_frames=zero_frames+15 end;if zero_frames>=45 then floor_clear() end end
 end
 if token and current_mutator and current_frame%60==0 then
  if current_mutator=="spring" then game.player.thirst_set({restore=1.5}) elseif current_mutator=="scorched" then game.player.thirst_set({restore=-1.0}) end
 end
 update_speeds()
end)

-- Legacy Expanded Data prices (DarkCloud-Expanded, BSD-2-Clause).
-- Daily stock rotations need a native day counter, which this API does not expose.
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
moonmod.log("info",string.format("Dungeon+ initialized: %d legacy prices, feats, bounties, mutators, tiers and speed variation",price_changes))

