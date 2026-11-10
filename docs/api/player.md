# Player, party and playable characters

Part of the [MoonFactory API reference](../API.md). The controlled character's health and state, tuning, mod-made moves
and forms, the companion, the party, playable-character records and the wallet.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Active player health (`player.get`, `player.set`)](#active-player-health-playerget-playerset)
- [Player tuning (Chronicle)](#player-tuning-chronicle)
- [More tuning: input buffer, dodge cost, lock camera, chain cancel
  (Chronicle)](#more-tuning-input-buffer-dodge-cost-lock-camera-chain-cancel-chronicle)
- [Guard, action gauge and player state (Chronicle)](#guard-action-gauge-and-player-state-chronicle)
- [Thirst (`player.thirst_*`, Chronicle)](#thirst-playerthirst_-chronicle)
- [Companion (Chronicle)](#companion-chronicle)
- [Party queries (`party.*`)](#party-queries-party)
- [Playable character records (`characters.*`)](#playable-character-records-characters)
- [Mod moves (`player.moves_set`, Chronicle)](#mod-moves-playermoves_set-chronicle)
- [Criticals and played moves (`player.critical_set`, `player.move_play`,
  Chronicle)](#criticals-and-played-moves-playercritical_set-playermove_play-chronicle)
- [Player forms (`player.form_set`, Chronicle)](#player-forms-playerform_set-chronicle)
- [Ridepod and monster badges (Chronicle Two)](#ridepod-and-monster-badges-chronicle-two)
- [Wallet and currency (`economy.*`)](#wallet-and-currency-economy)

## Active player health (`player.get`, `player.set`)

```lua
local player = assert(game.player.get())
local set_hp = assert(game.player.set({hp = 50, character = "active"}))
local healed = assert(game.player.heal({amount = 15, character = "active"}))
local bench_heal = assert(game.player.heal({amount = 10, character = "monica"})) -- Chronicle Two
local damaged = assert(game.player.damage({amount = 5, character = "active"}))
local status = assert(game.player.status_add({status = "power", character = "max", duration_frames = 300})) -- Chronicle Two
assert(game.player.status_remove({status = "power", character = "max"}))
```

`player.get()` returns the active character id plus current and maximum HP and water. Chronicle also returns
`character_id` (the native party slot) and the equipped `weapon` object when present (`id`, `item_no`, `slot`, `attack`,
`endurance`, `speed`, `durability` and `durability_max`; a hit wears `(1.5 - endurance / 100)` times the swing's weight,
up to 3 for a charged attack). During an active dungeon it also returns the active player's native world `position`
(`x`, `y`, `z`) in both games. In a Chronicle dungeon it also returns `heading`, the way the player faces in radians (0
looks along +z, as `sin(heading)`, `cos(heading)` on x and z).

`player.set({hp = integer, character = optional_id})` sets current HP exactly through the native HP update path;
`player.set({max_hp = integer, character = optional_id}) changes Chronicle's maximum HP from 1 through 999 and clamps
current and pending HP down if needed; player.set({water = integer, character = optional_id}) sets Chronicle's current
water gauge within its native range and clears any pending gauge interpolation. Each call sets exactly one field.
Attempts to set max_water, multiple fields together, or unknown fields are rejected. Chronicle Two does not support
max_hp or water. This call can target a benched character without switching the active character. `player.heal` and
`player.damage` accept integer amounts from 1 through 32767 and use the game's native health state, which clamps at
maximum and zero HP. The optional `character` accepts `"active"` or a playable character id: Chronicle supports Toan,
Xiao, Goro, Ruby, Ungaga, Osmond and the registered playable characters in the party (`characters.register_playable`);
ChronicleTwo supports Max, Monica, and the ridepod. These calls can update a benched character without switching the
active character. Omitting `character` targets the active character, including ChronicleTwo's transformed monster when
its live gauge is available. `player.damage` changes HP only; it does not synthesize damage formulas or knockback.
`player.status_add/remove` use native ailment/status rules: Chronicle accepts `freeze`, `stamina`, `poison`, `curse`,
and `goo` for the active character; ChronicleTwo accepts `poison`, `slow`, `curse`, `stop`, `power`, `stone`, and `dry`
for Max or Monica. ChronicleTwo requires `duration_frames` from 1 through 32767 when adding a timed status (`slow`,
`stop`, `power`, or `stone`) and rejects a duration for untimed statuses. Native interactions can reject a status (for
example, ChronicleTwo power wards off poison and slow). Unsupported player mutations remain unsupported.

## Player tuning (Chronicle)

```lua
assert(game.player.tuning_set({run_speed = 1.24, attack_anim_speed = 1.18, invincible_bonus_frames = 24,
                               recoil_scale = 0.5, gauge_refill = 1.0, thirst_drain = 0.64, durability_wear = 0.64,
                               map_reveal = true, monster_reveal = true}))
assert(game.player.invincible({frames = 90}))   -- one-shot, in a dungeon
assert(game.player.tuning_clear())
local supported = select(2, game.player.tuning_set({})) == nil   -- an empty table is valid: "no change"
```

`player.tuning_set` gives a mod one owner-scoped set of knobs on the dungeon player that the Lua formulas cannot
reach. Every field is optional and a field left out means the retail value for that owner; each call replaces the
owner's whole set, `player.tuning_clear` takes it back, and unloading the mod restores it. Several mods can hold
tuning at once: multipliers multiply, `invincible_bonus_frames` add (capped at 120) and the reveal flags OR, and the
combined multipliers are kept inside 0.25 to 4. The result carries the owner's `tuning` and the combined `effective`
set. Fields, all validated (a bad field rejects the whole call with `invalid_argument` and changes nothing):

| field | range | what it does in Chronicle |
|---|---|---|
| `run_speed` | 0.25 to 4 | multiplies the dungeon walk speed (1.45 per frame) and the dash speed (3.0) |
| `attack_anim_speed` | 0.25 to 4 | plays the recovery of Toan's sword swings (combo actions 0x24 to 0x28, after each swing's last hit and sound frame) at this speed; the hit frames keep their one-frame steps because the game tests them in half-frame windows, so a bigger number shortens the time to the next swing rather than the swing itself. Other characters are unchanged |
| `invincible_bonus_frames` | 0 to 120, integer | after a hit lands, the player stays invincible this many frames past the recoil |
| `recoil_scale` | 0.25 to 4 | scales the recoil (stun) frames a hit sets (160 for a heavy hit, 80 light, 8 from traps), never below 1 |
| `gauge_refill` | 0.25 to 4 | scales the action gauge's refill per frame |
| `thirst_drain` | 0.25 to 4 | scales the water gauge drain per frame; `player.thirst_get`'s `drain_per_frame` includes it |
| `durability_wear` | 0.25 to 4 | scales the weapon wear per hit, after the weapon's own halving or doubling flags |
| `map_reveal` | boolean | the floor map draws every cell as if the Map item were held (the HUD shows the Map icon too) |
| `monster_reveal` | boolean | monsters show on the map as if the Magical Crystal were held |
| `map_hidden` | boolean | no floor map or minimap at all (wins over `map_reveal`) |
| `map_window` | boolean | the minimap is always the framed square that scrolls around the player, as on a region's map, however small the floor (the Gauntlet's map) |
| `status_duration` | 0.25 to 4 | scales how long Freeze (300 frames) and Stamina (1800) last |
| `status_immune` | list of `freeze`, `stamina`, `poison`, `curse`, `goo` | the active player never takes these ailments (owners' lists combine) |
| `swap_delay` | 0 to 4 | scales the two 20-frame waits of a battle-menu character switch; 0 switches as soon as the model loads |
| `dodge_power` | 0, or 0.25 to 4 | with a value, L2 throws the player forward (the push an attack lunge uses, so walls stop it); 45-frame cooldown; owners take the strongest |
| `dodge_invincible_frames` | 0 to 60, integer | invincibility a dodge gives |
| `dodge_hop` | boolean | the dodge leaves the ground |
| `dodge_run` | 0 to 200 | with a value, L2 runs as in Souls: held past 12 ticks (0.2 s) with the stick pushed it runs at the dash speed Dran's Feather gave (3.0 a tick against the walk's 1.45, times `run_speed`), draining this much action gauge a second, with no refill while running; an empty gauge walks until L2 is let go. A tap dodges as it is let go (the `dodge` moves and `dodge_power` alike), not on the press. L2 no longer swings the camera behind, and Dran's Feather in a quick slot no longer boosts: it is a charm, and in the Feather's charm slot (`items.charm_slots_set` `feather`) halves the drain, spending a use a tick of running. Owners take the largest |
| `lightness` | boolean | a weapon's Speed no longer sets the refill (every weapon refills as Speed 60 does); it scales what a swing costs instead, 60 / Speed held between half and double: a Speed 99 weapon swings for 0.61 of the game's cost, a Speed 30 club for double. It covers the game's own combo costs and a mod's attack moves (`moves`); evades (`dodge`, `dodge_back`) cost what they say. Any owner turns it on |
| `stamina` | {character id = 0 to 600} | that character's own refill, in gauge a second, whatever the weapon: it replaces Speed / 30 and the character's factor (Toan's and Ungaga's quarter, Xiao's and Ruby's half again). A swing frame still refills nothing for Toan and Ungaga, Goo still halves it, Osmond's gun rules still apply, and `gauge_refill` still scales it. 0 leaves the game's. Owners take the largest per character |
| `extra_shots` | 0 to 2, integer | Xiao's slingshot and Ruby's orbs fire this many more, fanned 8 degrees either side (owners add, capped at 2) |
| `shots_pierce` | boolean | Ruby's orbs fly on through monsters (walls still stop them) |
| `first_person` | boolean | `false` turns off R2's first-person view in dungeons |
| `reach_scale` | 0.25 to 4 | Ungaga's spear hit points sit this much further out from him |
| `item_heal_lock` | 0 to 400, integer | an HP-healing item (from the item menu or eaten from a quick slot) is refused while a live, revealed enemy is within this distance of the active character (a floor cell is 160); a mod's own `items.use` is not. Owners take the largest |
| `lock_flick` | boolean | while locked on, a flick of the right stick (from near the middle to three quarters out) moves the lock to the nearest enemy on that side of the target, within lock range. Any owner turns it on |
| `lock_sight` | boolean | the lock drops (with the refuse sound) after half a second with a wall between the player and the target: a straight line crossing an empty cell of the random floor's map. Any owner turns it on |
| `soft_lock` | 0 to 90 degrees, integer | not locked on, a swing (a native swing, or a mod move started by the attack button) turns to the nearest live, revealed enemy within 64 units and this many degrees of the way the player faces or the stick points. Owners take the largest; 0 is off |

`player.invincible({frames = 1..600})` sets the active player's native invincibility counter to at least `frames`
during an active dungeon (it fails in town) and reports the counter and its previous value; it never shortens a
longer run and counts down with the game. All three need `game.write`. Chronicle Two has no binding for them yet.

`player.fatal_guard({charges = 0..99, character = optional id})` (Chronicle, `game.write`) sets how many fatal hits a
character survives: an animated hit that would take its HP to 0 leaves 1 HP instead, spends a charge, gives 90
invincible frames and sends `game.player.guarded` `{character, charges}` (the charges left). Without `character` it
sets all six. Charges are not saved; the result lists every character's.

## More tuning: input buffer, dodge cost, lock camera, chain cancel (Chronicle)

`player.tuning_set` also takes `input_buffer` (0-20 steps): a roll or R2 move (`player.moves_set` dodge, dodge_back,
heavy, combo_finisher, art) pressed when it can't start, such as late in a swing before its cancel point, mid-roll or in
a hit-stop, is kept that long and starts at the first step it can. 0 is the game's own (tried on its frame only).
`dodge_gauge` (0-100) is what the `dodge_power` shove costs of the weapon gauge (refused with less); the shove is only
for a character with no dodge move of a mod's. And `lock_camera` (boolean): locked on, the camera turns to keep the
target straight beyond the player, with 8 degrees of slack far off and 30 close up, where the game lets it drift up to
90 degrees off first; locked on to a large monster (body radius or half its height past 15 units) the camera may also
sit up to 60 units further out, walls still pulling it in. And `chain_cancel` (0-30 steps, 0 off): R2 pressed in an
attack's recovery, its last blow that many steps past, cuts into the heavy (a native swing, or one of the mod's own
attack moves, a heavy among them); attack pressed in a mod attack move's recovery ends it so the native combo starts on
that press. Several mods asking: the earliest wins.

## Guard, action gauge and player state (Chronicle)

The game's guard (lock on, then hold R1) blocks every hit from every side for nothing, and any hit, blocked or not,
fills the action gauge to 100. Two owner-scoped rule sets change that. Each has one owner at a time: a second mod's
set fails until the first clears it or unloads. A set replaces the owner's whole rule set, and fields left out take
the defaults below. With neither set, hits play exactly as in retail.

```lua
assert(game.player.guard_rules_set({arc = 120, cost_base = 10, cost_per_damage = 1.5, chip = 0.15,
                                    break_recoil = 120, parry_frames = 6, without_lock = true}))
assert(game.player.gauge_rules_set({hit_refill = -15, first_swing_cost = 25, min_to_swing = 10, refill_delay = 36}))
```

`player.guard_rules_set` (`game.write`):

| Field | Range (default) | Does |
| --- | --- | --- |
| `arc` | 0 to 360 degrees (360) | only a hit from within this arc, centred on where the player faces, is blocked; a hit from the side or behind lands in full |
| `cost_base` | 0 to 100 (0) | gauge a blocked hit costs |
| `cost_per_damage` | 0 to 10 (0) | gauge a blocked hit costs for each point of its damage (after defence) |
| `chip` | 0 to 1 (0) | share of a blocked hit's damage that still gets through |
| `break_recoil` | integer 0 to 600 (0) | recoil frames a guard break leaves; 0 keeps the game's recoil for the hit |
| `parry_frames` | integer 0 to 60 (0) | a hit within this many frames of R1 is parried: no damage, no cost, heavy hits too, even while the guard is still rising. 0 is no parry |
| `without_lock` | boolean (false) | R1 guards with no lock-on target; R1 no longer turns the camera while unlocked |

A blocked hit that would cost more than the gauge holds **breaks the guard**: the hit lands in full, the gauge empties,
and the player is knocked down (a light hit included) for `break_recoil` frames. Outside a parry, a heavy hit is
still blocked only once the guard is fully up, as in the game. The ailment rolls (poison, curse and the rest) happen
before the guard, so a guard never stops them. `player.guard_rules_clear()` turns the caller's rules off.

`player.gauge_rules_set` (`game.write`):

| Field | Range (default) | Does |
| --- | --- | --- |
| `hit_refill` | -100 to 100 (0) | a hit that lands adds this to the gauge (negative drains) instead of filling it; a block under the game's guard leaves it alone |
| `first_swing_cost` | 0 to 100 (0) | gauge the first swing of a native combo costs (follow-ups keep their own costs) |
| `min_to_swing` | 0 to 100 (0) | gauge the first swing needs; below it the attack button does nothing |
| `swing_cost_scale` | 0 to 4 (1) | scales what the combo's later swings and a mod's attack moves cost, on top of `lightness` and gear |
| `refill_delay` | integer 0 to 600 (0) | frames the refill waits after the gauge last went down, from any spend: a swing, an evade, a block, a run, a hit |

`player.gauge_rules_clear()` turns the caller's rules off. Both clears return `{cleared, rules}`; unloading the owner
clears both.

`player.gauge_get()` (`game.read`, dungeon only) returns `{gauge, max = 100, exhausted, guard_rules, gauge_rules}`
(`exhausted` is Osmond's emptied gun; each rules table is `{on = false}` or the fields in force and their `owner`).
`player.gauge_set({gauge = 0..100})` or `player.gauge_set({add = -100..100})` (`game.write`, dungeon only, exactly
one of the two) sets the gauge or adds to it and returns `{gauge, previous}`; use it for refunds, or to charge for
something the game doesn't.

`player.state()` (`game.read`) is what the active player is doing this frame. Away from a dungeon it is
`{active = false}`; in one: `{active = true, character, hp, max_hp, action_on, action_no, motion, attacking,
guarding, guard_held, guard_frames, locked_on, target?, recoil_frames, invincible_frames, running, in_water, gauge,
exhausted}`. `guard_frames` counts from R1; `target` is the lock-on enemy's entity handle. `action_on`, `action_no`
and `motion` are the game's own numbers (`action_on` 1 is a swing, 6 the guard; see
[Dark Cloud engine notes](../modding/DARK_CLOUD_NOTES.md)).

Every hit that reaches the player, with or without rules, sends **`game.player.hit`** `{character, entity?, kind,
damage, incoming, blocked, parried, broke, poised, angle, gauge}`: `kind` is `light`, `heavy`, `trap` or `other`;
`damage` is what got through (before the player damage formulas and `fatal_guard`), `incoming` the hit's damage after
defence; `angle` the degrees from the player's facing to the attacker (0 ahead, 180 behind); `gauge` the gauge after the
hit; `entity` the attacker's handle when a monster landed it; `poised` that it landed but the worn gear's `poise` took
the stagger. A parry's riposte, a guard break's effect or a death drop hang off it.

`player.tuning_set`'s `recoil_scale` and `invincible_bonus_frames` apply to every landed hit; a guard break's
`break_recoil` replaces the scaled recoil.

Chronicle Two doesn't have these operations or the event yet.

## Thirst (`player.thirst_*`, Chronicle)

Chronicle's per-character water gauge. Chronicle Two has none, so these are unsupported there.

- `game.player.thirst_get()` reads the active character, current and maximum water, the current per-frame drain, whether
  drain is enabled, the empty state, and the native restriction-zone/step flags.
- `game.player.thirst_set({water = number, character = optional})` sets the absolute gauge;
  `game.player.thirst_set({restore = number, character = optional})` adds to it. Both clamp to the native capacity (0
  through `max_water`) and clear pending gauge interpolation. Exactly one of `water` or `restore` is required. A changed
  write queues `game.player.thirst_changed`.
- `game.player.thirst_changed` carries `character`, `character_id`, `previous_water`, `water`, `max_water`,
  `drain_per_frame`, `drained_out`, `dried_out`, `source` (`api` or `native`), `reason`, and `frame`. The adapter polls
  the native gauge once per runtime pump, so native drain, drinking, and drying out are observed even when no API call
  made the change. Native observations are emitted on whole-unit gauge boundaries and on dry-out rather than for every
  fractional frame, and a transition that starts and ends between two pumps is not reported.

## Companion (Chronicle)

```lua
assert(game.party.companion_set({character = "ruby", stance = "target", damage_scale = 1.0}))
assert(game.party.companion_set({}))   -- send it back
local out = game.party.companion_get() -- {character = "ruby" or nil, out = boolean}
```

`party.companion_set` (`game.write`) brings a party member out beside the player in a dungeon. The engine loads its
model and equipped weapon into arenas of their own and drives it: it follows the player, runs to and attacks the
player's lock-on target (`stance = "target"`, the default), any monster within 150 units of the player (`"aggressive"`),
or nothing (`"passive"`). It cannot be hurt and monsters never target it; each blow deals its equipped weapon's base
attack times `damage_scale` (0 to 10), with no damage formulas (Xiao, Ruby and Osmond fire a visible shot that lands on
arrival), and is reported as `game.companion.hit` `{entity, character, damage, killed, reward_exp, frame}`. It catches
up at once if it falls far behind. A companion can't be the active character: switching to it sends it back until the
mod names another. Only one mod's companion is out at a time, and unloading the mod sends it back.

`hostile = {hp = 1..9999, damage = 1..999, defense = optional 0..999, tint = optional {r, g, b}}` makes it an invader:
it hunts the player instead (stance is ignored), and may be the active character. Each swing lays a native hit on the
player in front of it (kind light, every third heavy at x1.5 and slower to come; a ranged hero's shot lands where it
arrives), so guard rules, dodge invincibility and poise take it, and `game.player.hit` reports it with no `entity`.
A player weapon hit that reaches its body (a hit that strikes monsters, dealt by no monster) takes `damage - defense`,
at least 1, and sends **`game.companion.struck`** `{character, damage, hp, max_hp, killed}`. At 0 it plays its down
motion and goes 1.5 seconds later. `tint` is the colour it is drawn in; it flashes white when hit. `companion_get`
adds `hostile` and, for an invader, `hp` and `max_hp`. The player's lock-on takes it when it's nearer than the nearest
monster (the cursor shows over it; its bar is the mod's). Between swings it circles the player on its lock-on strafe;
it guards or dashes aside from swings started close by (the dash doesn't go through walls); below a third of its life
it backs off and drinks one of two flasks, healing two fifths, which sends `game.companion.struck` with `damage`
negative (the heal) and the new `hp`. A hit while it drinks spills the flask.

## Party queries (`party.*`)

```lua
local members = assert(game.party.list())
local active = assert(game.party.active())
local npc = assert(game.party.recruit({npc_id = 7})) -- Chronicle Two
```

These read party membership and the active character from the current save. ChronicleTwo reads the native membership
mask and reports stable ids (`max`, `monica`, `ridepod`, or `monster`), the native character id, and an `active` flag;
`party.list()` also reports townspeople with stable ids such as `chronicle-two:npc:7` and their joined/in-party status.
Chronicle reports its joined playable roster from the native party-size field and fixed character order, plus the active
member.

`party.set_active({id = "toan"|"xiao"|"goro"|"ruby"|"ungaga"|"osmond"|<registered id>})` changes Chronicle's active
member through its native character and weapon loading routine. It requires an active dungeon, a joined and living
target, no current player action or movement lock, no scene playing (a floor's entry scene, a gate: it picks its motions
by the character it began with), and compliance with the game's restricted-zone and Osmond ground rules.

ChronicleTwo's `party.set_active({id = "max"|"monica"|"ridepod"})` checks the game's native quick-change state and
changes the active character through the native setter; the game can reject a switch when the character is unavailable,
locked, at zero HP, blocked by status, or barred by the current floor. A successful changed switch emits
`game.party.active_changed` with `previous`, `active`, and `changed`. `party.recruit({npc_id = 1..32})` runs
ChronicleTwo's native townsperson join and in-party routines. The game allows one townsperson companion at a time;
recruiting another moves the previous one to the joined/waiting state. Re-recruiting the current companion is an
idempotent no-op.

Successful recruitment emits `game.party.recruited` with `id`, `npc_id`, `recruited`, `changed`, and `replaced`.
Chronicle recruitment remains unsupported because its playable cast has no separate NPC companion roster.

**Playable characters past the six (Chronicle, sandbox sessions only).** A mod can add playable characters with
`characters.register_playable` (`content.register`), usually while it loads:

```lua
game.characters.register_playable({
  id = "opar", name = "Opar",                    -- API id (1-15 of a-z, 0-9, _); name 1-10 letters
  pack = "dun/mainchara/c07d.chr",               -- his character pack, a file the mod supplies (resources.override)
  portrait = "dun/mainchara/c07d_face.png",      -- optional 128 x 128 PNG for the menus' faces
  title = "Moon Sea Frog Mage",                  -- optional: what the item menu says under his picture (default: name)
  fights_as = "toan",                            -- optional (default toan): whose action, motions, weapons, voice
  hp = 90, defense = 21,                         -- optional: start values (default: those of fights_as)
})                                               -- returns {id, character_id, count}
```

Each takes the next native index from 6 (`character_id`) and keeps it while the game runs; there is room for ten
(sixteen characters in all). Registering the same id again updates him in place; another mod's id is refused. A party
holds the first `party_size` characters and every registered one who has joined. A sandbox party that reaches his index
holds him by its size: `session.start({party_size = 7})` takes the first registered, 8 the first two. A story party
takes him with `party.join({character = id})` (`game.write`), whatever its size (Opar joining with Xiao, at two), and
`party.leave({character = id})` lets him go (not while he leads, nor from a party that holds him by its size); both
return `{character, joined, changed, party_count}`. A new game has nobody joined. The save itself never holds one: it
keeps its six (its layout is unchanged, so it loads without the mod), and writing a save image counts a party of six
with Toan active. What is his goes beside it, in the save's folder as `characters.json` (written with the save and the
autosave, read when it loads, deleted with it): for each registered character by id, whether he joined, led the party,
his life, water, defence, ailments, skill, weapons and equipped slot. One the file names that no mod registers now is
kept as it was; one it does not name starts afresh, out of the party. A weapon given to a character with nothing in hand
(one just joined) goes in his hand (`weapons.give` returns `equipped = true`), as the story's own joins equip a first
weapon. They appear in `party.list`, `characters.list` and `characters.get` (with `name`, `fights_as`, and `in_party`
false outside a party that reaches them), `player.*`, `party.set_active`, `player.fatal_guard`,
`dungeons.set_character_blocks`, the combat events' `attacker` and `game.item_picked_up`'s `character` (their index). A
registered character fights as `fights_as`: that character's weapons (`weapons.give` with `character`), action, voice,
motions, weapon models and menu poses. His pack is built on that character's skeleton (up to 16 MiB); his portrait is
drawn on the switch wheel, the Allies ring and the weapon page, or the face of `fights_as` without one. The companion
(`party.companion_set`) takes them too: his own model, moving and fighting as `fights_as`, and with `shot = {cell =
0..15, size = 0.3..4}` from range, throwing that `basefx01` cell (any companion can take one). The Gauntlet registers
Opar this way (its **Opar** setting, or his star in Norune Eternal's Allies).

Chronicle also provides `party.town_active()` and `party.town_set_active({id =
"toan"|"xiao"|"goro"|"ruby"|"ungaga"|"osmond"})` for the visible town avatar. These calls require an active Chronicle
town scene. Toan is always available; other characters require a positive native maximum-HP value, matching the legacy
town selection check. Switching loads the character's native town-compatible model and animation resources, preserves
position and rotation, and maps town motion IDs onto the selected character's motions. It does not change the saved
dungeon-active character.

`town_set_active` queues the model reload until the native scene is walking safely. These are Chronicle-only;
ChronicleTwo does not expose town-avatar replacement.

## Playable character records (`characters.*`)

```lua
for _, character in ipairs(game.characters.list()) do
  print(character.id, character.kind, character.in_party, character.hp, character.max_hp)
end

local monica = assert(game.characters.get({id = "monica"})) -- Chronicle Two
local xiao = assert(game.characters.get({id = "xiao"})) -- Chronicle
```

`characters.list()` returns the game's known playable character records; `characters.get()` accepts one stable id as a
string or `{id = ...}`. Records include native character ids, party/active flags, and health where the save has a
corresponding gauge. Chronicle lists its six party characters. ChronicleTwo lists Max, Monica, the ridepod, and the
monster transformation; the latter exposes health only while transformed. ChronicleTwo also appends mod-registered enemy
definitions to this list and resolves their namespaced ids through `characters.get`.

## Mod moves (`player.moves_set`, Chronicle)

`player.moves_set({moves = {...}})` gives characters this mod's own attacks, up to 160, replacing the mod's earlier set;
`player.moves_clear()` takes them back (and unloading does). A move replays a stretch of one of the character's own
native motions at its own speed and brings its own lunge, spin, hits, bursts, sounds and trail, in place of the native
action. Mods hear `game.player.move` ({id, owner, character, cancel, variant, frames}) as one starts (`variant` is the
number of the variant that played, or nil; `frames` how many steps it runs).

- `id` (1-40 bytes), `character` (one of the six), `trigger`:
  - `run_attack`: the attack button after running for `run_frames` (1-300 game steps, two drawn frames each),
    still running as attack is pressed (stick pushed hard, nothing locked on; locking on doesn't count as running).
  - `guard_attack`: the attack button while guarding (locked on, R1 held).
  - `dodge` / `dodge_back`: L2 with the stick pushed (the move turns the way it points) / at rest (he keeps his facing).
    A `dodge` can take a `direction`: `any` (the default), or, while locked on, `toward` or `away` (the stick within 45
    degrees of the way to the target, or of the way from it) or `left` or `right` (the stick between them). A `left` or
    `right` dodge keeps him facing the target and carries him the way the stick points: a side roll. The dodge for the
    stick's way wins, and an `any` dodge takes the rest. An evade takes L2 ahead of the tuning dodge (`dodge_power`). It
    also cuts an attack short: a swing of the character's own combo, or one of the mod's attack moves, once its last
    blow is `cancel_after` steps past (0-60, default 2). `cancel = false` turns that off. Specials (the jump slash, the
    wave), a charge being held and another evade can't be cut. Evades keep their own cooldown, apart from the attack
    moves'. `game.player.move` carries `cancel = true` for an evade that cut an attack short.
  - `heavy`: R2 pressed at rest (the heavy attack). A character with an R2 move (`heavy` or `combo_finisher`) gives
    up R2's first-person view in dungeons.
  - `combo_finisher` with `chain` (1-6): R2 pressed partway through the attack combo, once `chain` swings in a row
    have laid their blow (each within 150 steps of the last; a blow counts for a new swing when the action changes
    or more than 6 steps have passed, so a long swing's several blows count once; for Xiao, Ruby and Osmond each
    shot or cast counts). R2 cuts any native attack short while the chain is live, even the next swing before its
    blow, or comes at rest within 60 steps of the last blow. Combo swings that run with the act flag down
    (Ungaga's) can still be cut. The finisher with the
    longest chain reached wins, so `chain = 2` and `chain = 3` sit side by side. A move (any of the mod's) ends the
    chain.
  - `lock_attack` with `direction` (`toward` or `away`): the attack button at rest while locked on, the stick pushed
    (half way or more) within 60 degrees of the way to the target, or of the way from it. The move faces the target;
    `lunge_angle = 180` carries an `away` move back off it.
  - `evade_attack`: the attack button late in an evade (60% through or more; it cuts the rest short, with `cancel =
    true` on `game.player.move`) or within 20 steps after one ends.
  - `charge_release` (Toan): his charge let go at `min_charge` or more on the game's charge count (0-10; the native
    jump slash comes at 0.5 and the wave at 1.5, a count of 1 being about two seconds held), ahead of the jump slash.
    While Toan has the wave's skill, a charge at `max_charge` or more is left to the wave. His charge flashes orange
    as it reaches `min_charge`.
  - `art`: R2 while guarding (the guard's own state, locked on or not with `guard_rules` `without_lock`). `weapons`
    (up to 64 native weapon item numbers, 257 and up; none means any) and `min_level` (1-99, default 1) say which
    equipped weapon it is for: the first of the character's arts whose list holds the weapon he holds, at that level
    or higher, plays. Any number sit side by side, another mod's too. Vigil gives each of Toan's blades one.
  - `played`: no button; only `player.move_play` starts it. Any number of a character's `played` moves sit side by
    side, another mod's too. Vigil's flask drink is one (each hero's native drinking motion, 28, at half speed).
  - `critical` with `critical = "backstab"` or `"riposte"`: the attack button at rest, tried ahead of every other
    trigger. A backstab takes the nearest live enemy within `reach` (4-60, default 24; the lock target first) whose
    back he stands at, within `arc` degrees of straight behind it (20-180, default 90). A riposte takes the enemy the
    mod armed with `player.critical_set`, while it is armed and within `reach`. He is drawn in to `gap` (2-40, default
    12) of it if farther, and faces it; it stops where it is, is turned to him (a riposte) or away (a backstab), any
    `stop` on it ends, and it plays its half from `pairs` (up to 32 `{model (a native model id), animation (a motion
    registered on that model with `animations.monster_register`: the mod's id or `"mod:id"`), speed? (0.05-4, default
    0.5)}`). Its script waits `hold` steps (0-600; 0 is its pair's length at that speed, else the move's), hits and
    all; its flinch is skipped and its death still plays. An enemy without a pair is held standing.
- `motion` (native motion number 0-63) or `animation` (a motion registered with `animations.player_register`: the
  mod's own id, or `"mod:id"`), `from`/`to` (the stretch, fractions 0-1), `speed` (0.2-4, motion units a step).
- `variants` (up to 4, for a move with an `animation`): `{animation, motion, from?, to?}`, another registered motion
  that plays instead when the move starts while the character is in native motion `motion` (0-63), between the
  fractions `from` and `to` of it (default 0 and 1). The first that matches wins. Vigil's roll pushes off whichever
  foot leads: Toan's run is his native motion 1, his right foot ahead for its first 30% and its last 20%:

  ```lua
  {id = "roll", character = "toan", trigger = "dodge", animation = "toan_dive_roll", -- off his left foot
   variants = {{animation = "toan_dive_roll_right", motion = 1, from = 0, to = 0.3},
               {animation = "toan_dive_roll_right", motion = 1, from = 0.8, to = 1}}}
  ```
- `lunge` (0-6) and `lunge_decay` (0.01-2): a push the way the stick points (else the way the character faces). Every
  move but `run_attack` and the evades faces the lock target if there is one (and pushes that way). `lunge_angle` (-180
  to 180): the push's angle from the way he faces (180 pushes him backward). `blend_in` (1-30 frames): how quickly the
  move takes over from the pose he is in. The engine fades from it over 10 ticks otherwise, which smears the first
  frames of a quick move; Vigil fades its evades in over 3 and its attacks over 4. `camera` (1-14 steps): how quickly
  the follow camera closes on the character while the move plays. The game's own is 8 (14 locked on), which leaves the
  camera trailing a roll by 20 units; Vigil gives Toan's evades 3. `spin` (-4 to 4): whole turns, made between
  `spin_from` and `spin_to` (fractions of the move, default the whole). `invincible`: no hits land during it. `gauge`
  (0-100): action gauge spent, and the move needs that much. `wear` (0-5): weapon wear, as a swing's. `cooldown` (0-600
  steps).
- `hits` (up to 12): `{at (0-1 through the move), radius (1-40), reach (-20 to 40, ahead of the character), height,
  damage (times the weapon's attack, 0-10), knockback (0-10), heavy?, charged? (enemy_hit reports it charged),
  burst? (an effects.burst kind), burst_scale?}`. A hit strikes every enemy in its reach once.
  A hit with `shot = true` fires projectiles instead: `count` (1-5) shots fanned `spread` degrees apart (0-45,
  default 10) at `speed` (1-10, default 5), from the slingshot's tip (Xiao) or the weapon hand, toward the locked-on
  target or the way the move faces, each for `damage` times the weapon's attack. Xiao fires her slingshot shots,
  Ruby her magic orbs (damage on her attack and magic averaged) and Osmond his gun's bullets; a melee character's
  shots are Xiao-style. They use the game's player shots
  (12 at a time). A shot, the move's or a native one, counts as a blow for an evade's cancel. A Xiao-style shot can
  have its own start and look: `from` (a frame of the character's model, e.g. `"jnt12_1"` the head; default the
  weapon's tip), `from_ahead` and `from_rise` (-10 to 10: moved that far the way the move faces, and up), `cell` (0-15:
  the `dun/effect/basefx01` picture's 32 x 32 cell it is drawn with, row by row; 8 is a glowing blue blob) and `size`
  (0.3-4). A `burst` on a shot plays where each one lands (a wall, the floor or an enemy). Opar's spit is
  `{shot = true, from = "jnt12_1", from_ahead = 2.6, from_rise = -0.4, cell = 8, size = 2.2, burst = "heal"}`.
- `cues` (up to 12): `{at, sound? (swing, swing_heavy, voice, voice_2, voice_3, shout, shout_2, action),
  trail? (light, wide, heavy, wave, slam)}`.

Another mod's move on the same character and trigger is refused. Of a mod's own `charge_release` moves, the first in
its list that the charge reaches plays, so a high `min_charge` listed ahead of a lower one takes the longer charges.

## Criticals and played moves (`player.critical_set`, `player.move_play`, Chronicle)

`player.critical_set({entity, frames?})` opens one enemy (a live monster handle) to the mod's `riposte` criticals
for `frames` steps (1-600, default 120), as after a parry or a stagger; one at a time, a new one replaces it, and a
critical on it spends it. `player.critical_clear()` closes it. Each critical that starts sends
**`game.player.critical`** `{id, owner, kind (backstab or riposte), entity, native_model_id?, hold}`: a mod's
critical damage hangs off it (Vigil raises its blows on that kind of enemy for `hold` ticks with a formula).

`player.move_play({id})` starts one of the mod's own moves (`player.moves_set`) now, whatever its trigger: a
chained move, such as the move a form makes as soon as it is taken. The move must be the active character's; like
a trigger it needs him free to act and the move's gauge, but it doesn't wait on the moves' cooldown. It fails while
he is in an action (try again).

## Player forms (`player.form_set`, Chronicle)

`player.form_set({pack, frames?, hide_weapon?})` turns the active character into another model where he stands: his
model reloads from `pack` (`dun/mainchara/<stem>.chr`, a mod's `resources.override`), a pack laid out like a player's (a
`base.cfg` whose motion table lists the character's motions by the numbers his action plays; a monster's pack works once
its `info.cfg` is renamed and its table remapped, see `art/opar/make_form.py`). His action, weapon stats, moves and
health stay his. `frames` (up to 16) names stand-ins for the frames the player code looks up by name that the form's
model lacks (`weapon` the grip, `item` the hand items are held in, `tukene1`, `jnt2_1`, and a shot's `from`), e.g.
`{weapon = "r_hand"}`. `hide_weapon` (default true) leaves the weapon undrawn; its hits still swing from the grip.
`scale` (0.1-4, default 1) draws the model that much its size (a monster's model is far bigger than a hero's). Mod
motions (`animations.player_register`) are not added to a form's model; its moves use native `motion` numbers.
`player.form_clear()` gives him his own model back. Either fails (try again) while an action or a scene holds the model,
as a character switch does. A new floor, switching the character in and out, and unloading the mod also end it. Opar's
Jump Slam turns him into the Opar monster this way, for one slam.

## Ridepod and monster badges (Chronicle Two)

The ridepod's gauges and parts, and Monica's monster badges. Chronicle has neither, so these are unsupported there.

- `game.player.ridepod_get()` returns fuel and maximum, core capacity and used capacity, defence, shield-kit count,
  ridepod name, voice-unit/voice-enabled state, and the arm/body/leg/battery parts with item ids, item numbers,
  durability, energy, and capacity use.
- `game.player.ridepod_set({fuel|restore|max_fuel|shield_kits|voice_enabled|voice_unit|parts})` adjusts the native
  gauges and voice state. `parts = {arm, body, leg, battery}` requires an owned part of the matching native type and
  performs the game's equipment swap, returning the previous part to the inventory. Defence is derived from the body and
  shield kits; set `shield_kits` (0..999) rather than writing defence directly.
- `game.player.transform_get()` returns the active monster form, unlocked count, and all 64 badges with monster id,
  enabled state, level, class, progress, degree, health, experience and threshold, attack, defence, and class-change
  eligibility.
- `game.player.transform_set({badge = 1..64 | monster_id, enabled|level|experience})` updates one badge. Level is
  bounded to 0..98 and recomputes the native experience threshold; experience is clamped to that threshold. This changes
  saved badge state, not the live transformation actor.

## Wallet and currency (`economy.*`)

```lua
local wallet = assert(game.economy.get())
local credit = assert(game.economy.add({amount = 50}))
local purchase = assert(game.economy.spend({amount = 25}))
```

`economy.get()` returns Gilda and the native wallet limit. `economy.add()` accepts 1-32767 Gilda and calls the game's
native credit rule, clamping at the game's cap. `economy.spend()` accepts the same range and fails without changing the
wallet when funds are insufficient. Chronicle's wallet holds at most 65535; ChronicleTwo's holds at most 999999. Shop
pricing, transaction callbacks, and reward hooks beyond direct wallet updates remain game-owned.
