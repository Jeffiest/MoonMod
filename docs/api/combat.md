# Monsters, entities and combat

Part of the [MoonFactory API reference](../API.md). Reading the monsters on a floor, changing and spawning them, damage,
statuses and formulas, enemy definitions, and driving a monster's script from Lua.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Combat snapshot (`combat.get`)](#combat-snapshot-combatget)
- [Dungeon entities: query, stats, spawn and despawn
  (`entities.*`)](#dungeon-entities-query-stats-spawn-and-despawn-entities)
- [Entity velocity (`physics.velocity_get`,
  `physics.velocity_set`)](#entity-velocity-physicsvelocity_get-physicsvelocity_set)
- [Spatial query (`physics.query`)](#spatial-query-physicsquery)
- [Monster slots and the awake limit](#monster-slots-and-the-awake-limit)
- [Enemy healing (`combat.heal`)](#enemy-healing-combatheal)
- [Scripted enemy damage (`combat.damage`)](#scripted-enemy-damage-combatdamage)
- [Enemy timed statuses (`combat.status_add`, Chronicle)](#enemy-timed-statuses-combatstatus_add-chronicle)
- [Mod attacks on the player and combat feel (Chronicle)](#mod-attacks-on-the-player-and-combat-feel-chronicle)
- [Damage formulas (`combat.register_formula`)](#damage-formulas-combatregister_formula)
- [Effect bursts, tints and shoves (Chronicle)](#effect-bursts-tints-and-shoves-chronicle)
- [Data-defined enemy variants (Chronicle)](#data-defined-enemy-variants-chronicle)
- [Data-defined enemy variants (Chronicle Two)](#data-defined-enemy-variants-chronicle-two)
- [Monster AI from Lua (`monsters.natives`, `monsters.call`,
  Chronicle)](#monster-ai-from-lua-monstersnatives-monsterscall-chronicle)

## Combat snapshot (`combat.get`)

```lua
local combat = assert(game.combat.get())
print(combat.in_combat, combat.enemy_count)
for _, enemy in ipairs(combat.enemies) do
  print(enemy.id, enemy.hp, enemy.max_hp)
end
```

`combat.get()` takes no arguments and reads the current dungeon monster tables on both games. It returns `in_combat`,
`enemy_count`, and live `enemies`; `in_combat` is true while at least one living monster participates on the current
floor. Chronicle includes the monster family/name and poison, slow, and stun timers. ChronicleTwo includes its monster
definition id, status flags, and target slot. Slot IDs identify entries only for the current floor and are not
persistent entity handles. Outside an active dungeon context the call fails with `failed` rather than returning an empty
success snapshot.

## Dungeon entities: query, stats, spawn and despawn (`entities.*`)

```lua
local result = assert(game.entities.query({type = "monster"}))
for _, entity in ipairs(result.entities) do
  print(entity.id, entity.health.current, entity.health.maximum)
end
```

Both adapters currently support only `type = "monster"` while a dungeon is active. The query returns living monster
slots with native definition, health, status, and position data. Chronicle also includes each actor's reveal state,
combat stats and drop item, plus `native_model_id` when the floor's native model mapping is known. Chronicle keeps `id`
as a slot label and returns a separate generation-checked `entity_id`; ChronicleTwo's `id` is already the
generation-checked actor handle. Use those stable handles with `entities.get` to detect slot reuse.

Chronicle updates actor generations from the native setup and floor-clear paths. ChronicleTwo assigns each returned
entity a slot generation. Chronicle's `entities.set_stats({entity, hp?, max_hp?, defense?, reward_exp?, reward_money?,
drop_item?, damage_scale?, hit_reach?, hit_share?, vulnerable?})` changes one or more stats on a live revealed enemy.

`hp` and `max_hp` are 1–1,000,000, and `hp` cannot exceed the resulting `max_hp`; `defense` is 0–32,767; `reward_exp` is
0–32,767; and `reward_money` is 0–2,147,483,647; `drop_item` is `-1` to clear or a valid built-in native item number; on
Chronicle, `damage_scale` (0–100) multiplies what that enemy's own attacks and the shots it fires take off the player,
before the player's defense and `combat.register_player_formula` (a new actor in the slot, or a new floor, sets it back
to 1); and `hit_reach` (0–200 game units) is added to each of that enemy's body hit-spheres when the player's blows are
checked against it, for a weak point a blade cannot otherwise reach (it resets to 0 the same way); and `hit_share =
true` makes each of the enemy's body hit-spheres take from every character the share of a blow it takes from the
character it suits best.

A story boss's scripts set a per-character damage percentage on each sphere, and many shut out whole heroes (the Ice
Queen takes nothing from anyone but Ruby), so a boss met by a different party needs this to be beatable. It resets to
false the same way. `vulnerable = true` lets blows land through the enemy's own script invincibility (the native
`STATUS_SET_MUTEKI`), and a body sphere that no hero's blow hurts takes the blow whole; `combat.damage` and a
companion's blow land too. The King's Curse is invincible by its script (only its coffin dies in its fight), so the
Gauntlet sets this on it when it roams a floor alone. It resets to false the same way.

Chronicle also supports `entities.script_int_set({entity, index, value})` on a live member of a boss's cast (the boss or
a helper it spawned through `characters.spawn` with `arena_slot`): it writes integer `index` (0–255) of the global block
that cast's native scripts share, and returns `{entity, index, previous, value}`. A cast's scripts pass signals through
that block (the pink Genie reads each hand's integer to learn it is broken), so a mod can hold one when its own spawning
bypasses the native path.

Chronicle also supports `entities.scale_set({entity, scale})`, an owner-scoped uniform visual multiplier from 0.5 to
3.0; it captures the native scale and restores it on actor reuse or mod unload. This operation only changes the live
enemy model and shadow. If only `max_hp` changes, current HP keeps the same fraction. The operation rejects stale
handles, unrevealed actors, and actors outside an active Chronicle dungeon; ChronicleTwo does not support it.

Both ports support `entities.spawn` for registered enemy definitions; it shares the `characters.spawn` request shape and
returns a mod-owned actor handle. Chronicle only spawns when the definition's exact native template has already been
loaded for the current dungeon floor. ChronicleTwo reuses an already-loaded compatible template model/script; if the
template is not loaded on the current floor, spawn returns a clean failure rather than loading assets dynamically. The
`entities.despawn` API in both ports removes a live enemy spawned by the calling mod and clears per-actor runtime state
and native collision/projectile references. It invalidates the generation-checked handle, updates floor alive counts,
and skips kill credit and drops.

Chronicle rejects mimics because the dungeon map retains their chest trigger; ChronicleTwo rejects actors held by a
native interaction. Both adapters also attempt to despawn safe, live owned actors when their Lua mod unloads; native
safety guards leave actors in place if despawn is unsafe. NPC/world-object spawning remains unsupported. Query calls
outside an active dungeon fail instead of returning an empty list; handle lookups after leaving a dungeon return `status
= "expired"`.

## Entity velocity (`physics.velocity_get`, `physics.velocity_set`)

```lua
local enemies = assert(game.entities.query({type = "monster"}))
local enemy = enemies.entities[1]
local motion = assert(game.physics.velocity_get({entity = enemy.id}))
print(motion.velocity.x, motion.velocity.y, motion.velocity.z)
local changed = assert(game.physics.velocity_set({
  entity = enemy.id, velocity = {x = 0, y = 4, z = 0}
}))
print(changed.changed, changed.velocity.y)
```

Chronicle Two exposes the native `CCharacter2` velocity vector for a live dungeon-monster handle. Chronicle reads
movement intent from its live native monster record. Components are game units per frame and use the game's world axes.
The handle must still identify the same live actor; dead, stale, stopped, or out-of-dungeon handles fail for writes.
`game.physics.velocity_set({entity, velocity})` writes a finite vector and returns the previous value, the resulting
value, and whether it changed.

Chronicle converts the requested vector into the native direction and speed fields, accounts for its falling term, and
clears an active knockback so the requested movement takes effect. Chronicle Two writes its actor's native velocity
vector. Either game can replace the value during its next AI or movement update; this does not bypass collision
resolution.

Chronicle's `game.physics.velocity_get({entity})` result includes `source` (`native_movement`, `knockback`, or
`stopped`) and `semantics = "native movement intent before collision resolution"`; when the enemy is falling, the native
per-frame gravity term is included. The snapshot and setter operate on movement intent before collision resolution.

## Spatial query (`physics.query`)

```lua
local nearby = assert(game.physics.query({
  shape = "sphere",
  center = {x = 0, y = 0, z = 0},
  radius = 250
}))
for _, match in ipairs(nearby.matches) do
  print(match.entity, match.distance, match.position.x, match.position.y, match.position.z)
end
```

Both games support this read-only query during an active dungeon. It returns live monster actor origins inside or on the
sphere, with generation-checked entity handles, positions, and distances in game units. The center coordinates are
bounded to +/-1,000,000 and the radius to 0-10,000. Results follow native actor-slot order. This does not test enemy
collider size, walls, floor geometry, or line of sight; those collision queries remain unsupported.

## Monster slots and the awake limit

Retail Chronicle has 16 monster actor slots per floor and keeps only the 4 nearest monsters awake; the rest wait dormant
until they come closer. The Chronicle PC port raises the slot table to 256 (`MONSTOR_SLOT_MAX`), so `characters.spawn`
can keep placing enemies until 256 actors exist on the floor. Chronicle Two has 32 active monster slots
(`MONSTER_ACTIVE_MAX`) and defaults to keeping the 5 highest-priority monsters awake (`priority_limit = 5`). In both
games, `entities.set_active_limit({active = 1..slots})` sets how many stay awake at once and returns `{active, previous,
slots}`:

```lua
local limits = assert(game.entities.set_active_limit({active = 16}))
```

The limit is global, takes effect on the next simulation step (updating any live `CMonsterMan` priority limit
immediately in Chronicle Two), and stays until a mod changes it again (unloading the mod does not reset it). High awake
counts cost CPU and draw time. Chronicle's nine-kind model table per floor is unchanged, so a floor can still hold at
most nine different monster models.

## Enemy healing (`combat.heal`)

```lua
local combat = assert(game.combat.get())
local target = combat.enemies[1]
local result = assert(game.combat.heal({entity = target.entity_id, amount = 25}))
print(result.hp_before, result.hp_after, result.restored, result.changed)
```

`combat.heal` takes the `entity_id` returned by `combat.get` or `entities.query`, checks its generation, clamps at the
monster's native maximum HP, and returns before/after health. Both games accept `{entity = generation_checked_handle,
amount = 1..1000000}`. ChronicleTwo also accepts its former `{slot = live_enemy_slot, amount = 1..1000000}` form for
existing mods. Dead, stale, invalid, or out-of-dungeon targets fail without changing state. Healing changes HP directly
and does not simulate an attack or trigger rewards.

## Scripted enemy damage (`combat.damage`)

```lua
local combat = assert(game.combat.get())
local target = combat.enemies[1]
local result = assert(game.combat.damage({entity = target.entity_id, amount = 25}))
print(result.hp_before, result.hp_after, result.damage, result.death_queued)
```

`combat.damage` accepts the generation-checked `entity_id` returned by `combat.get` or `entities.query` and an exact HP
amount from 1 to 1,000,000. A mod's registered combat formulas are applied to the requested amount before the native
hit/death path. Chronicle respects its native invulnerability timer and hidden-enemy state; a surviving enemy enters the
native hit script and lethal damage queues the native death script and floor kill accounting.

ChronicleTwo respects the enemy's native no-damage flag, invulnerability timer, and catch state, then routes surviving
and lethal damage through the native damage/death script requests. No player or weapon is credited for a scripted kill,
and the operation does not create a collision hit, status proc, knockback, or weapon experience reward. Stale handles,
dead enemies, and out-of-dungeon calls fail without changing state.

## Enemy timed statuses (`combat.status_add`, Chronicle)

```lua
local combat = assert(game.combat.get())
local target = combat.enemies[1]
local result = assert(game.combat.status_add({
  entity = target.entity_id,
  status = "slow", -- or "stop"
  duration_frames = 300
}))
```

`combat.status_add` supports `slow`, `stop` and `haste` for live, revealed Chronicle enemies. `haste` is not a native
status: while it lasts the enemy's scripted motions and moves play 1.4 times as fast (the inverse of `slow`, and the two
multiply), and it ends with the enemy's slot. The generation-checked handle prevents a delayed hit event from affecting
a new enemy that reuses the same slot. Duration is 1–32767 native simulation steps, and an existing timer is only
extended. ChronicleTwo does not expose this operation.

## Mod attacks on the player and combat feel (Chronicle)

`combat.strike_player({x, y, z, radius = 2..120, damage = 0..9999, kind = "light" | "heavy"})` lays one native hit at
that point that only the player can be struck by, as a monster's blow would be: the game's own hit test takes it on the
next frame (the player's defence comes off), so a guard, a parry, a dodge's invincibility and poise all work on it, and
`game.player.hit` reports it with no `entity`. Light flinches; heavy knocks back. It is for a mod's own attacks (a
boss's new move after a telegraph, a trap). Dungeon only.

`combat.feel_set({hit_stop = {light, heavy, critical, hurt}, shake = {light, heavy, hurt}, rumble = true})` gives
blows weight. `hit_stop` values are frames (0-12) the whole floor holds still when one of the player's blows lands
(`heavy` for a heavy hit or a charged one, `critical` as a critical begins) or when the player is hurt (`hurt` for a
knockback, half of it for a flinch). It is drawn, not stepped, and a swing that strikes several monsters in one frame
freezes once. `shake` values (0-10) are the camera shake's strength for the same moments, and `rumble` turns the pad's
vibration on for landed blows and criticals. Every field is optional and missing ones are 0. One mod's feel is set at
a time (another mod's call fails until it clears). `combat.feel_clear()` takes it off; unloading the mod does too.

## Damage formulas (`combat.register_formula`)

```lua
local formula = assert(game.combat.register_formula({
  id = "heavy-hits",
  operation = "multiply", -- "add", "multiply", "set", "chance_multiply", "random_multiply", or Chronicle-only "ramp_multiply"
  value = 1.5,
  priority = 10
}))
```

`combat.register_formula` registers an owner-scoped damage modifier. The accepted fields are `id`, `operation`, `value`,
optional integer `priority`, optional `chance` for `chance_multiply`, optional `min_value`/`max_value` for
`random_multiply`, and optional native `weapon_id`, `native_model_id`, and `character_id` filters.

`ramp_multiply` is Chronicle-only and additionally requires `rate_per_second` (0–10) and `reset_after_frames`
(1–36,000); it ramps the multiplier from 1.0 up to `value` at the specified rate, based on matching-hit frame
timestamps, then restarts after a gap longer than the reset interval. Chronicle also accepts `target_hp_below_percent`
(0–100), which only matches a live weapon target whose current HP percentage is strictly below the threshold; non-hit
calls lack this context and skip such a formula.

`random_multiply` chooses a uniform multiplier from its inclusive bounds for each matching hit.
`combat.register_player_formula` accepts optional `weapon_id` and `character_id` filters. These filters are native
numeric IDs; when present, a formula only applies when every supplied filter matches. Chronicle supplies weapon,
enemy-model, attacker-character, and target-HP context for real weapon hits, and weapon and character context for native
incoming player damage. Unfiltered formulas retain their previous behavior. IDs are local 1–64 character ASCII
identifiers; each mod may own up to 64 formulas, and the game retains at most 512.

`add` accepts −1,000,000 through 1,000,000, `multiply`, `chance_multiply`, and `random_multiply` accept multipliers from
0 through 100, and `set` accepts 0 through 1,000,000. `chance_multiply` also requires a finite chance from 0 through 100
and independently rolls for each matching hit. Modifiers run in ascending priority, then owner ID and formula ID order;
random effects roll independently. Re-registering an owned formula ID updates its definition; an identical definition is
idempotent. Unloading a mod removes its formulas.

Formulas modify positive damage after each game's native defense, elemental, and damage-block calculations in the native
enemy-hit pipeline. Chronicle also publishes `game.enemy_hit` after an accepted positive native weapon hit. That event
includes the generation-checked enemy `entity`, `slot`, player `attacker`, stable `weapon_id`, `native_weapon_id`, final
`damage`, `element`, `frame`, and `native_model_id` when known. The event is informational and delivered on the next
runtime pump; use the formula filters for damage changes. Chronicle's `game.enemy_hit` also carries `charged`: true when
the hit lands within a second of a charged move (Toan's held charge, Xiao's full-gauge shot, Goro's swing held into a
second spin, Ruby's full charge, Osmond's charged shot; Ungaga's combo has no charge). A formula with `charged = true`
(or `false`) applies only to such (or other) real weapon hits; calls without hit context skip it. Formulas also modify
explicit `combat.damage` requests when unfiltered. A zero or blocked base hit remains zero; final damage is clamped to
0–1,000,000, then rounded upward to a whole HP for scripted `combat.damage`. These formulas do not create new attack,
animation, or collision behavior.

## Effect bursts, tints and shoves (Chronicle)

- `effects.burst({kind, position = {x, y, z}, scale?})` plays one of the game's own effects at a point: `explosion` (the
  bomb's), `heal` (the healing sparkles), `sparks` or `guard` (hit marks), `impact` (Osmond's bullet), `smoke` (a cloud
  of dust: the bomb's smoke puffs without the fire). Scale 0.1-4.
- `entities.tint({entity, color = {r, g, b}, frames})` draws a live enemy in a colour for up to 3600 frames (0 ends it).
- `entities.knockback({entity, direction = {x, z}, speed})` shoves a live enemy along a direction, slowing to a stop
  (speed 0.5-40); pointing it at another enemy pulls it in.

## Data-defined enemy variants (Chronicle)

```lua
local jacket = assert(game.characters.register({
  id = "moon-jacket",
  kind = "enemy",
  name = "Moon Jacket",
  template_monster_id = 0, -- inherit Master Jacket model, AI, effects, and drops
  stats = {hp = 500, defense = 23, reward_exp = 17, reward_money = 91},
  assets = {}
}))
local resolved = assert(game.characters.get(jacket.id))
print(resolved.native_monster_id, resolved.model, resolved.script)
```

Chronicle registers up to 128 enemy variants through its native monster-model resolver. A variant can inherit the
selected template's model, AI script, effects, family, and drop rules while overriding `hp`, `defense`, `reward_exp`,
and `reward_money`, or it can select a package-owned model binding through `models.register`. Chronicle's monster table
has no per-definition display string, so `name` is returned by the API while the in-game lock-on label still uses the
template's localized name.

`characters.spawn({character = id, position = {x, y, z}, rotation = optional {x, y, z}})` and its `entities.spawn` alias
use the native actor initializer and inherited AI. Data-only variants require their exact template to be loaded on the
current floor. A character using a registered custom model can load that model into a free slot of the floor's model
table (48 models; the native game had 9); spawning fails with a reason when the floor loader is not ready or all slots
are occupied. The registering mod owns the definition and is the only mod allowed to spawn it. Nearby mod-owned enemies
enter Chronicle's active native state immediately, and the view budget (4 awake enemies by default) prioritizes
mod-owned enemies before filling remaining slots with vanilla actors.

The response includes a generation-checked `entity_handle`, slot, position, and supported stats. Resolve it with
`entities.get`; it reports `dead` after death and `expired` after native slot reuse or dungeon cleanup.
`entities.despawn({id = entity_handle})` removes a live owned non-mimic enemy without kill credit or drops.

A data-only variant whose template the floor didn't load (a boss on an ordinary floor) has the template loaded into a
free slot of the floor's model table when it spawns. The retail bosses (Dran 78, Master Utan 79, Ice Queen 80, King's
Curse 81/82, Minotaur Joe 83, Dark Genie 84) run scripts written for their own arenas, centred on the world origin;
`arena_origin = {x, y, z}` tells the engine where that arena's centre lies on this floor, and every position the
boss's script reads or sets is moved by it. `grounded = true` (with `arena_origin`) also keeps every height the script
asks for at the floor (Dran stays on the ground).

`arena_slot = 0..15` (with `arena_origin`) makes the spawn a member of a boss's cast: the monsters its arena places
beside it, whose scripts name each other by the slots they hold there (the boss in 0). Spawn the boss with `arena_slot =
0` and each helper with its native slot and the same `arena_origin`; the engine maps those slot numbers (monster
positions, links, references, script IDs) onto the slots the cast holds on this floor, and the shared script values
(`SET_GLOBAL_INT`) are the cast's own bank, apart from the floor's other monsters, which use the same numbers for their
own ends, and start cleared for the cast's first member, as the arena's floor load leaves them. A boss (`arena_slot =
0`) always opens a new cast, even at an origin where another cast still stands (a second boss rising where the first
fell, while it fades out): the helpers spawned after it at that origin join it, and the two casts never fade or name
each other. A missing member leaves its part of the fight out. The native casts: Ice Queen 80 with Ice Barrier 101, Ice
Arrow 76, Ice Prison 102, Ice Meteor 103, Ice Aura 92 and three Ice Tornadoes 104 (slots 1-8); King's Curse coffin 81
(the part that dies) with the Curse 82 in slot 1; Minotaur Joe 83 with three Wine Kegs 91; the pink Dark Genie 84 with
his hands 85 and 86, light 87, wind 88, beam 89 and 90 and shockwave 93 (slots 1-7; his eye opens to blows only once
both hands are broken, and he waits on his beam, slot 5, so leave those in); the dark Genie 106 with shades 105 (slots
1-2), pillars 107 (3-4, each raising the shade below it), shockwaves 108 (5-6) and beam 109 and 110 (7-8). The Genie's
casts load more textures than a floor's share of the PS2's 4 MB; Chronicle's texture count, which is bookkeeping only,
goes to four times that.

The story scenes a boss's fight asks for don't run away from its arena. When a boss in an arena (any `arena_origin`
spawn) asks for its defeat scene with its life gone, it fades out over a second and a half in its place and dies;
other scene requests are skipped. When a cast's slot-0 member is defeated, by its scene request or its own script,
the rest of its cast fades out with it.

## Data-defined enemy variants (Chronicle Two)

```lua
local sentinel = assert(game.characters.register({
  id = "sentinel",
  kind = "enemy",
  name = "Bright Sentinel",
  template_monster_id = 0, -- reuse the native Sewer Rat model and AI script
  stats = {hp = 300, attack = 75, defense = 41, reward_exp = 90, reward_money = 55},
  assets = {}
}))
assert(sentinel.status == "registered")
local definition = assert(game.characters.get(sentinel.id))
print(definition.native_monster_id, definition.model, definition.script)
```

`characters.register` creates a distinct native enemy definition from an existing ChronicleTwo monster template. The
stable id is qualified with the registering mod's id. `stats` may override `hp`, `attack`, `defense`, `reward_exp`, and
`reward_money`; omitted values inherit from the template. The model, AI script, drops, and other behavior continue to
use the chosen native template, and non-empty asset overrides are rejected. Names are limited to 31 UTF-8 bytes for the
native table. A port session can register up to 32 variants.

`characters.spawn({character = id, position = {x, y, z}, rotation = optional {x, y, z}})` uses a compatible native
template model/script reference loaded during floor initialization and places the variant through the native actor setup
path. Register the character before entering the target floor so Chronicle Two's native floor loader can preload its
template; spawning returns a clean failure if the needed template is absent. Positions are game units; rotations are
radians. The registering mod owns the definition and is the only mod allowed to spawn it. The response includes a
session entity handle, native slot, and generation.

`characters.get(handle)` and `characters.list()` report its live position and combat stats; handles report `dead` after
the native actor dies and `expired` when its slot is reused or its dungeon closes. The actor continues its inherited
native AI until death or dungeon teardown, including after its owner mod unloads. Enemy definitions and their loaded
resources stay reserved until the game process exits so active actors never retain pointers to cleared definitions.

The retail headless probes reuse retail models and AI, so they do not prove authored model assets, standalone animation
data, or custom AI. Both verify embedded motion playback and cleanup; Chronicle's probe also verifies native velocity
write/read-back. Chronicle Two's item-and-dungeon smoke enters a newly registered floor, spawns the data-only enemy, and
resolves the live entity handle.

## Monster AI from Lua (`monsters.natives`, `monsters.call`, Chronicle)

Every monster runs a compiled script (`dun/monstor/<name>.stb`), and that script calls natives such as `SET_MOTION`,
`GET_POSITION` and `SET_MOVE`. `game.monsters.natives()` lists the 86 natives a mod can run, each with its `name` and
`op`, under the names dc1tk's decompiler uses without the leading `_`. `game.monsters.call{entity, native, args?}` runs
one of them on a living monster, as that monster's own script would. `entity` is the generation-checked `entity_id`
from `game.entities.query`. `native` is a name or an op number. `args` is a list:
- a number (whole numbers go in as integers, the rest as floats) or a boolean;
- a string, for a model frame's name (1-31 letters, digits or `_`), such as `SET_SHOT`'s `"dcol0"`: `{"dcol0", x, y, z}`
  fires the monster's own projectile from that frame at a point;
- `{out = "int"}` or `{out = "float"}` for a value the native writes back. These come back in order in `out`.

`_RUN_SCRIPT`, `_PUSH_IGLOBAL`/`_POP_IGLOBAL` and `_SET_REFERENCE`/`_DEL_REFERENCE` need a running script, so they are
not offered. Requires `game.write`.

```lua
local m = game.entities.query({type = "monster"}).entities[1]
local pos = game.monsters.call({entity = m.entity_id, native = "GET_POSITION",
                                args = {-1, {out = "float"}, {out = "float"}, {out = "float"}}})
print(pos.out[1], pos.out[2], pos.out[3])
game.monsters.call({entity = m.entity_id, native = "SET_MOTION", args = {3}})
```

The `native.monster.run` script hook (`game.scripts.override`) runs before a monster's script program. The context is
`entity`, `slot`, `program_no` and `model`; the programs are 1 (spawn), 50 (revealed), 100 (its idle loop), 110 (hit)
and 120 (killed). Calling `game.scripts.call({id = "native.monster.run"})` runs the retail program. A callback that
does not call it takes the monster over for that program. The program then counts as finished, so the hook runs again
on the next frame, and a mod can drive the monster each frame with `monsters.call`.

`ctx.model` is the floor's model slot (0-2, the order the floor loads its monsters in), not the monster's kind: find
the kind from `entities.query`'s `native_model_id` for `ctx.entity`. The hook runs when a program starts. A monster's
retail idle loop (100) never ends on its own, so when a mod installs or removes a `native.monster.run` override, every
monster then in its retail idle loop starts it again once: the new override takes it over on the next frame. A
monster's spawn script may set up things its other programs rely on: a Skeleton Soldier's opens a guard window over
its guard motions (`SET_GUARD_FRAME` 100-120), so a brain that plays those motions blocks. Vigil's enemy brain is a
full example: Dashers and Skeleton Soldiers that circle, feint, block, punish a whiff and wait their turn
(`mods/moonmod.vigil/main.lua`, *Enemies that fight like it*).

```lua
game.scripts.override({id = "native.monster.run"}, function(ctx)
  if ctx.program_no == 100 and ctx.model == 3 then
    game.monsters.call({entity = ctx.entity, native = "SET_ROTATION", args = {(ctx.frame * 4) % 360}})
    return {handled = true}                       -- this model now only spins
  end
  return game.scripts.call({id = "native.monster.run"})
end)
```
