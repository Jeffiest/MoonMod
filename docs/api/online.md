# Online play and co-op

Part of the [MoonFactory API reference](../API.md). Rooms through the co-op relay, the split save co-op uses, the mods a
room needs, and messages players leave for each other.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Online play (`net.*`, Chronicle)](#online-play-net-chronicle)
- [Co-op: the host's world, a guest's things, visits (`save.*`, `session.start {visit}`,
  Chronicle)](#co-op-the-hosts-world-a-guests-things-visits-save-sessionstart-visit-chronicle)
- [Mods in a session and their co-op roles (`mods.*`)](#mods-in-a-session-and-their-co-op-roles-mods)
- [Messages players leave for each other (`messages.*`,
  Chronicle)](#messages-players-leave-for-each-other-messages-chronicle)

## Online play (`net.*`, Chronicle)

```lua
local ok = game.net.host({version = 1, name = "Toan"})        -- a room through the co-op relay
-- or: game.net.join({code = "AB3CD", version = 1, name = "Xiao"})
for _, e in ipairs(game.net.receive().events) do            -- each tick
  if e.kind == "connected" then moonmod.log("info", "room " .. e.code .. ", I am " .. e.peer)
  elseif e.kind == "message" then handle(e.peer, e.data) end
end
game.net.send({to = "all", data = "P 120 0 340"})           -- or to = a player's id (the host is 0)
```

One online session for the game at a time, owned by the mod that opens it; another mod's calls fail while it is open,
and it closes when its mod unloads. The relay (DC_Web's `coop/relay`, a Cloudflare Worker) passes messages between up
to four players and keeps no game state: the host's game is the world, and the mod decides what its messages mean.

- `net.host({version, name?, relay?})` opens a room; `net.join({code, version, name?, relay?})` joins one by its five
  letters and digits (any case). `version` (1-9999) is the mod's message protocol: a room takes only players on the same
  number, so change it when the messages change. `name` is at most 24 bytes. `relay` is a `wss://` or `ws://` address (a
  private server, DC_Web's `coop/relay/server.mjs`, may be plain `ws://` on a home network or a VPN; browsers need
  `wss://`); without it the game uses `DC_COOP_RELAY` from its environment, else the one the build names
  (`DC_COOP_RELAY_DEFAULT`). Both return the status at once; the result arrives through `net.receive`.
- `net.receive({max?})` takes waiting events, oldest first (256 by default, up to 1024): `connected` `{peer = this
  player's id, code}`, `joined` `{peer, name}`, `left` `{peer}`, `message` `{peer = the sender, data}`, and `closed`
  `{reason}`, which ends the session (the relay refused, the host left, the connection dropped). At most 4096 wait;
  past that the oldest messages go first.
- `net.send({to, data})`: `to` a player's id or `"all"` (everyone else); `data` text (UTF-8) of at most 16 KiB.
  A guest can send to another guest. The relay drops a player's frames past 240 a second.
- `net.status()` gives `{state = "idle" | "connecting" | "hosting" | "joined", available, id?, code?, peers = {{id,
  name}}, owner?}`; any mod with the permission can read it.
- `net.leave()` leaves; a host leaving ends the room for everyone.

The web build uses the browser's WebSocket, Windows WinHTTP, Linux and macOS libcurl; a build without libcurl reports
`net.*` unsupported.

## Co-op: the host's world, a guest's things, visits (`save.*`, `session.start {visit}`, Chronicle)

Co-op splits a save in two (`moonmod/coop_save.hpp`): the **world**, which is the host's (Georama in every town, the
story and map flags, the day and time, dungeon progress, and the party the story has brought), and a **player's own
things** (each character's life, defense, water, weapons and equipped weapon; the item pack, quick slots, stored
items and stock; Gilda; fishing points). Both travel as text a mod passes along.

- `save.world_export()` and `save.player_export()` give `{data}`: `"DCW1..."` and `"DCP1..."`, about 64 KB and 37 KB.
  A player's things carry MoonMod's own beside the save after them (`|DCX1` and a JSON object): the gear and the charm
  slots, as `gear.json` and `charms.json` hold them; an import without them leaves none. A visit for a new account
  (no `player`) starts with no gear or charms.
- `save.player_extra_set({data})` keeps a value of this mod's (any table or value, 32 KB as JSON at most; `{}` drops
  it) with the player's things, so it travels with them: a co-op guest's levels go to the host's save with the rest,
  and come back on the next visit, where `save.player_extra_get()` gives `{data}` (or `{}`). A visit for a new account
  starts with none. The bundled RPG and Adventurer keep a guest's levels this way during a visit, and never in the
  guest's own slots.
- `save.world_import({data})` and `save.player_import({data})` work only during this mod's own visit, so no mod can
  write another game's world or things into a player's save. Data from another build (a field sized differently) is
  refused whole, and a refused import changes nothing.
- `save.account_get({id})`, `save.account_set({id, name?, data})`, `save.account_list()`, `save.account_remove({id})`:
  the guests the host's save keeps, each a player's things under the id the guest's game made (8-64 of `a-z 0-9 -`),
  at most 64. They are written as `coop_accounts.json` in the slot's folder with every save of the slot, read with its
  load, and gone with the slot; a new game has none. Not during a visit.
- `session.start({visit = {world, player?, map}})`, from the mod's open title mode screen, starts a **visit**: a new
  game takes the host's world and the guest's things (without `player`, a new account keeps the new game's), every
  character in the host's party has a weapon, and it walks into town `map` (0-4). A visit goes wherever the world goes;
  the way to the title (or `session.finish`, from a town or a dungeon) ends it. It never writes a save slot: saving
  refuses, and autosave skips it. `session.get()`, `game.session.started` and `game.session.ended` say
  `kind = "visit"`; `game.session.failed` `{kind = "visit", reason}` comes to the mod when the data didn't fit.

- `world.avatar_set({slot, character, weapon?, x, y, z, heading, motion, tint?, name?, down?})` shows another player
  (slot 1-3) on the dungeon floor, or walking in the town the player walks in (without a weapon there, and with the
  town's motions): `character` a character id, `weapon` an `item_no` (as `player.get().weapon.item_no`), the position
  and `heading` as `player.get()` reports them, `motion` its `motion`, and `tint` `{r, g, b}` (each 0-128) the ambient
  it draws in. Set it as reports come (several a second): between them the hero eases there and turns the shortest way,
  and it jumps when far away (a warp, the stairs). Each has its own model and texture arenas, loaded on the next dungeon
  frame and let go out of the dungeon (the slot is kept for the next floor). `world.avatar_clear({slot})` takes one
  away, `world.avatar_clear()` every one. `player.get()` reports the `motion` the hero plays, and in a town, walking,
  its `position`, `heading`, `motion` and `town_character` (the hero it walks as, `party.town_set_active`).
  `world.get()` in a town reports `walking` too, and on a dungeon floor `walking` is true only while the player plays
  there (false while the floor loads, when its `floor_id` and `floor_seed` aren't settled yet, and in a menu or a
  scene). `name` (24 bytes at most) is drawn over the hero's head, in blue for a tinted one, fading out toward where
  monsters stop being drawn. `down = true` lays the hero down (it holds its motion's last frame, so send the knockout
  motion): the monsters pass it by and no blow lands on it.

- Shots, spells and trails (co-op, Chronicle Two). `player.effects_take()` (`game.read`) gives what this game's own
  hero fired on the floor since the last call, oldest first, and forgets them: `{effects = {{kind, x, y, z, dx, dy, dz,
  value, amount, target, frame0?, frame1?}, ...}}`. `kind` 1 Max's pistol, 2 a machine gun's bullet (his or the
  ridepod's), 3 a grenade, 4 a laser (`value` its look: 0-2 Max's, 3 the ridepod's laser, 4 its beam), 7 the ridepod's
  rocket (`value` 0) or missile (1), 8 an item to throw (`value` its `item_no`; `amount` 0 held up, 1 thrown to `x, y,
  z`, 2 put away), 5 Monica's magic or her magic sword's charge (`value`
  the effect's number, `amount` its tint, `target` the monster's scene slot it was aimed at), 6 the blade's trail
  (`frame0` and `frame1` the weapon's frames it runs between, `value` its length, `amount` the steps it fades over,
  `target` the steps it holds first), 9 a sound the hero's own actions played (`value` its number in the hero's sound
  bank, `frame0` and `frame1` that bank's name, such as `CH_000` for Max or `CH_020` for Monica; a monster form has
  none), 10 a looped sound (a charge, an engine: `_SE_LOOP_PLAY`; `value` and the frames as a sound's, `amount` the
  frames it goes on after this word, 0 to stop it), given again every 8 frames at most while the hero keeps it going.
  Up to 64 are kept between calls. `world.avatar_effect({slot, ...one of those})`
  (`game.write`) draws another player's from their avatar: the same effect, flying the same way, striking nothing in
  this game (it makes no attack, and an effect's own script makes none either). `{shown = false}` when that avatar is
  not on this floor or the effect can't be made; an effect this game hasn't loaded is loaded on first use. A sound
  is heard from where the avatar stands, quieter and to one side as it is further off; each avatar loads the bank it
  names into a sound port of its own (game ports 12 to 14) the first time, and again only when the name changes. A
  looped sound goes on from the avatar, following it as it moves, until `amount` frames (plus the 8 between words)
  pass with no word for it, as the game's own loops are kept; up to four at once per avatar, stopped off the field.

- Down, not out (co-op). `player.down_rule_set({enabled})` (`game.write`): while it is on, a party knocked out on a
  dungeon floor (no one left to switch to, and no Revival Powder: the powder still works first) doesn't get the game
  over. The hero lies on its knockout motion, the monsters pass it by, and `player.get().down` is true, until the mod
  calls `player.revive({hp = 1-999, x?, y?, z?})`, which stands the hero up with that HP (no more than its max, its
  ailments cleared, a moment of invincibility), at `x, y, z` if all three are given; or `player.give_up()`, which plays
  the game's own knockout after all. Both fail with "the player isn't down" otherwise, and leaving the dungeon ends
  being down. The rule is off until a mod turns it on.

- `monsters.mirror_get()` (co-op's host) gives the floor's monsters, `{monsters = {{slot, kind, state, hp, max_hp, x,
  y, z, heading, motion}, ...}, hits}`, and what struck other players' heroes since the last call (anything that would
  strike the player: a monster's blow, its shot or spell, a trap, measured on each hero as the game measures it on the
  player), `hits = {{avatar, slot, damage, kind, flags}, ...}` (`avatar` as `world.avatar_set` numbers it, `slot` the
  monster or -1, `kind` 2 a small hit, 3 a blow, 4 a heavy blow). While heroes are on
  the floor, the host's monsters see them as players: each wakes for the nearest player and chases it.
  `monsters.puppet_set({monsters})` (a guest) makes this floor's monsters copies of those, by slot: a copy has no
  thoughts or blows of its own and stands, turns and moves as the host's does; a slot left out, or one with `hp` 0, is
  gone on the host, and a copy still up dies, its own death and drops playing out. A slot holding another kind here is
  `refused`. It returns, as `hits = {{slot, damage}, ...}`, the blows this player landed on the copies since the last
  call (any blow: a weapon's, a bomb's, a thrown item's), for the host's monsters; a copy keeps a sliver of life until
  the host's dies. `monsters.puppet_clear()` gives them their own thoughts back (leaving the floor does too).
  `monsters.mirror_hit({slot, damage})` (the host) lands another player's blow on a monster: the life goes, and a kill
  dies on the host as the host's own would.

- `dungeons.shared_events_get()` gives the system scripts this player ran since the last call that changed the floor
  without leaving it (a door or gate opened, a switch turned: an object moved or an event switched), as `{events =
  {{script, mode, ext, pos = {x, y, z}, dir = {x, y, z}}, ...}}`; one that leaves the floor or changes the character is
  never listed, nor one this game ran for another player, nor one every game runs by itself (a room cleared of its
  monsters, a monster's death). `dungeons.shared_event_run(event)` runs one here, at its
  place, once the player is free (not in a menu, a script or held still; it waits up to half a minute), the key it asks
  for taken as given. One waits at a time: another fails `busy` until it is taken.

- `world.enter_map({map_no})` walks the player into a town or one of its houses by its map number, as `world.get()`
  reports it (`map_no`, in a town or house), from walking in a town or playing on a dungeon floor. `items.owned()` lists
  what the player carries (the bag and the quick slots) as `{items = {{id, item_no, name, count}, ...}}`, names as the
  menus show them. A town imported while the player stands in it is no longer written back over by the town on screen
  when they leave it.

- `georama.town_export({town_id})` gives one town's Georama (its record and chips) as `{data}` text, and
  `georama.town_import({town_id, data, base?})` takes it. With `base` (the town as the editing game had it when its
  player opened the editor), only what they changed comes across, merged into this game's town: a plot, villager, chip
  or request they changed takes their value, the buildings they put up are added and those they took down taken away,
  and the rest stays as it is here (`merged = true`). A town open in Georama's editor or a menu is not imported over:
  the call fails with a reason starting `busy`, to be tried again. A player walking in that town is walked into it
  again, at its entrance (`reloaded = true`), so no one stands where a building just went. `world.get()` in a town
  reports `town_map` and `editing` (Georama's edit mode or its menu).

The bundled Online Co-op mod (`mods/moonmod.coop`) is built on these and `net.*`; `docs/plans/COOP_PLAN.md` has what is
built and what comes next.

## Mods in a session and their co-op roles (`mods.*`)

```lua
for _, m in ipairs(game.mods.list().mods) do print(m.id, m.version, m.coop) end   -- what this session loaded
local s = game.mods.settings_get({id = "moonmod.roguelike"})                      -- {id, values, overlaid}
game.mods.settings_overlay({id = "moonmod.roguelike", values = {companion = true}}) -- for this session only
game.mods.settings_overlay_clear({})                                              -- every mod's, or {id = ...}
```

- `mods.list()` (`game.read`) gives `{mods = {{id, name, version, author, coop}}}`: the Lua mods running now, in
  load order, a merged pack's running parts right after the pack (each with its own version and role). A mod switched
  on or off live is listed, or not, at once; one whose change waits for a restart keeps its current state.
- `coop` comes from the mod's manifest key of that name: `"required"` (the default when the key is absent) every
  player in an online room has the mod at the host's version and plays with the host's settings; `"host_only"` only
  the host needs it (a mod whose state lives in the host's save, such as Randomizer and Living Towns); `"local"` each
  player's own, never asked for and never sent (controls, the camera, autosave, the hub). Any other value refuses the
  manifest.
- `mods.settings_get({id?})` (`game.read`) gives `{id, values, overlaid}`: each declared setting's effective value
  (an overlay's, else the profile's, else the default). Without `id` it reads the caller's own; another mod's need the
  `mods.settings` permission.
- `mods.settings_overlay({id, values})` (`mods.settings`) gives a mod setting values for this session only. Each value
  is checked against its setting (type, range, choices); those refused are named in `refused`, the rest returned as
  `applied`. The values are never written to the profile, and the Mod Manager's own changes stay underneath them.
  The mod gets `settings.changed {id, value}` at the next tick for each setting whose value changed, and
  `moonmod.settings.get` returns the overlay's value at once. A mod that reads a setting only when it loads should
  also listen to `settings.changed` to follow an overlay.
- `mods.settings_overlay_clear({id?})` (`mods.settings`) drops one mod's overlay, or every mod's; each mod is told
  its own values again through `settings.changed`. Every overlay also ends by itself when `game.session.ended` or
  `game.session.failed` is published (a visit ends) and when the runtime stops or reloads its mods.

Online Co-op uses these to make every game in a room play the same mods with the host's settings: see
`docs/plans/COOP_PLAN.md`, "The room's mods".

## Chronicle Two's co-op (what differs from Chronicle)

The same operations and events with Dark Chronicle's records, in the ChronicleTwo engine (`port/docs/COOP.md`
there). It runs on the real game since 2026-11-14 (`tools/coop/live.py` in ChronicleTwo: two games on the disc's
data); the plan for Dark Chronicle's own co-op is `docs/plans/DC2_COOP_PLAN.md`.

- The relay `game` id is `chronicle-two`; a room is one game at one protocol number.
- `save.world_export` is `DCW2...`: the story flags and counters, each map's flags, the time and day, where the host
  is, the Georama parts held, each town's record and its layout, dungeon progress, quests, the monster book and the
  fishing tournament. `save.player_export` is `DCP2...`: Max, Monica and the ridepod, the bag and bait, the
  aquarium, badges, the townsfolk in the party, inventions and photos, Gilda, medals, fishing records and costumes.
  `georama.town_export` is `DCT2<town>:...`. The bytes are packed before they become text (what repeats is written once; `!` after the tag): a
  save's records are mostly empty, and unpacked a world is several hundred kilobytes, over the 64 KiB an operation
  answers. Imports read packed and plain text alike. Accounts live in `<save root>/moonmod/coop_accounts.json`.
- `session.start {visit = {world, player?, map_no}}` starts in a map by its own number (the host's
  `world.get().map_no`); `map`, a Georama town's area (0-4), still works for a town that has a Georama map. Palm
  Brinks has none, so `map_no` is the only way to join a host there.
- `world.get` adds, in a town: `town_map` (the area), `scene_map` (the map the town runs: a district of Palm Brinks
  is a map of its own while `map_no` stays the town's), `house` (the sub map the hero is inside, if any),
  `map_title` (the place's name as the game shows it), `editing` and `walking`; on a floor: `floor_seed`,
  `floor_layout` and `walking`; always: `map_no`, `progress` (how far the story is) and `chapter`.
- `dungeons.set_seed` decides the whole floor: its layout (a preset floor's pick too), then its chests, then its
  monsters each start from a number made of the seed, whatever the game drew in between. `floor_layout` is a number
  for the floor as built (cells, chests and what they hold, monsters and where), equal in two games that built the
  same floor.
- `dungeons.enter_floor {dungeon_id, floor_id}` lands on the floor itself (the dungeon's floor load event), not on
  its floor list. `x`, `y` and `teleport` are accepted and not used: the way in is the floor's own.
- `player.get` adds `heading`, `motion`, the melee `weapon`, `outfit` (`{head, clothes, feet, sub}`, the item
  numbers of what the hero wears and of the second weapon) and, in a town, `town_character` and the position. With
  `motion` come `motion_flags` (how the game plays it: 0 loops, as a run, a walk or a stand does; 2 stops on its last
  frame, as a swing or a fall does) and `motion_step` (how fast: frames a step; a walk's follows the stick).
  `monsters.mirror_get`'s monsters carry the same two.
- `world.avatar_set` takes `motion_flags` and `motion_step` as `player.get` gives them, and plays the motion so; left
  out, the motion loops at its own pace. It takes `age` too: how many frames ago the report was made, on the
  reporting game's clock as this game reckons it (the frames since its message came, plus how much slower it came
  than the quickest of that game's recent ones). An avatar given ages is shown 8 frames behind on that clock, eased
  between the reports it has kept, so a report that comes late or early still takes its own place. Without an age it
  eases toward each report as it comes. `world.avatar_effect`'s `age` is the same for a shot, spell, trail or sound:
  it is drawn when the avatar comes to that moment (`shown` then says it was kept for it), so a swing's trail and its
  sound come with the swing. `monsters.puppet_set({monsters, age})` takes the leader's report's age, and each
  monster's `motion_flags` and `motion_step`: the copies are shown the same way, behind and eased.
- On a floor whose monsters are copies, their own thinking rests but the floor's effects go on (torches, a door's
  sparkle, the other player's shots: they had stood frozen); what a copy's motion starts is drawn only and strikes no
  one (the leader's monster strikes).
- `ui.notify` (any mod's) shows the notice in the game's own field message window too, on a dungeon floor, as an
  item found is told: in lines of about forty letters, three to a window, a letter outside ASCII as the game writes
  one (`[UNIxxxx]`), a bracket as a parenthesis. Walking in a town it shows in a window of the same kind (a town has
  none of the floor's, so the engine keeps one, made as the floor makes its own). A notice that comes anywhere else
  (a menu, the Georama editor, while a question is asked) waits for a floor or a town, ten seconds at most; one that
  comes during a scene or a talk, a photo, a door or a map loading waits it out however long it lasts (those ten
  seconds count only while the player walks free), as the game never tells anything over its own scenes.
- The story's scenes keep their cast to themselves. `world.get()` always says `story_scene`: true while one plays
  in this game, in the town or on the floor (a drama scene, the kind Start skips; not a talk, a menu or a door).
  While one plays here the other players' heroes fade from sight where they stand, and back in after. Their names
  fade with them. `world.avatar_set`'s `away = true` says that player watches one in their own game: their hero
  fades from sight here and is nobody this game's monsters go for, until it is set without `away` (it fades back in
  where it is). The co-op mod tells the others when its player's scene starts and ends (`SC 1`, `SC 0`, and to a
  player who joins during one). A game that says nothing of scenes is never away.
- `world.avatar_set` shows `"max"` or `"monica"`, tinted through the ambient light if `tint` is given, in the `outfit` given (`{head,
  clothes, feet, sub}`, each left out at will: then as this game's own hero has it) with the hat or hair piece and
  the weapons on the body; no name over the head yet. It takes `"ridepod"` and `"monster"` too (what `player.get`
  says of a player in the ridepod or a monster's form), drawn as Max or Monica standing in for them.
- `monsters.mirror_get`'s `hits` are the blows the host's monsters landed on other players' heroes:
  `{avatar, monster, damage, kind, flags, stun, stagger, guard_rate, status, at = {x, y, z}, toward = {x, z}}`,
  `damage` the blow's strength, `kind` 2 (a flinch) or 3 (a knock-down), and the rest the monster's damage row as the
  game keeps it (`flags`: 1 stuns, 2 knocks down, 4 never staggers, 8 goes through a guard; `guard_rate` the share in
  hundredths a guard lets through; `status` the blow's specials, poison and the rest), where it struck from the hero's
  feet and which way it drove. The game it lands on shows a spark and plays the floor's hit sound there.
- `combat.strike_player`'s `damage` is that strength: the struck hero's own defence comes off it. It takes `flags`,
  `stun`, `stagger`, `guard_rate`, `status` and `toward = {x, z}` as those give them, and takes the blow as a monster's
  own blow on the hero is taken: a guard lets `guard_rate` of it through and rings, a knock-down knocks the hero the
  way it drove, a flinch comes once the stagger builds, poison, goo, stone, stop, curse and thirst take as they do
  (amulets ward them off), and a Resurrection Powder held brings the hero back. It looks, sounds and feels so: the red
  flash, the shake, the pad's rumble, the hero's cry, a spark at `x, y, z` and the damage over the head. It returns
  `{hit, damage, hp, kind, guarded}`, or `{hit = false, reason}` (`busy`, `away`, or `grace` while the hero can't be
  hit). Without `stagger` every blow makes the hero flinch, as before.
- `monsters.puppet_set`'s `hits` say how each blow on a copy landed: `{slot, damage, kind, element, flags, stagger,
  stun, guard, at = {x, y, z}}` (`kind` the damage row's, the weapon's: 0 Max's blade, 1 his gun, 4 Monica's blade, 5
  her magic and so on; `element` -1 or 0-3; `at` from the monster's feet). A blow that took nothing (the monster
  guarded, or can't be hurt by it) is listed too, with `damage` 0. `monsters.mirror_hit` takes them all and lands the
  blow as this game's own hero's would: the monster flashes in the element's colour, shakes, is knocked back a little
  by a blade or a fist, the weapon's hit sound plays, a spark and the damage show where it struck, and it flinches,
  falls, guards or sees stars as its stagger and the blow's flags say. `damage` 0 needs `kind`: it rings off as a
  guard or as no damage.
- `ui.choice_open` does not pause the game; while the panel is open the pad's buttons are the panel's (the press
  that picks an option does not also act in the game) and the sticks stay the game's. `style = "yes_no"` (two
  options: yes, then no) asks the question in the game's own message window instead, on a floor or in a town: the
  title and subtitle are its text (at most four lines), the game's Yes and No are chosen with left and right, and the
  cursor, the pick and backing out make the menus' own sounds. Elsewhere (the title page) it is the panel.
  A question waits out whatever holds the player: a scene or a talk, the floor's menu, a photo, a door, a minigame, a
  map loading, the Georama editor mid-action. Meanwhile it is not drawn and the buttons stay the game's, so the scene
  goes on. It is asked once the player walks free, after a moment's grace, so the press that ended the scene's last
  line does not answer it. Asked during a map load, a `yes_no` is asked in the game's window on the floor or in the
  town the player comes to.
- A player's own saves: `save.slots_list()` gives this game's numbered saves and how far each one's story is,
  `{slots = {{slot, ready, progress, chapter, play_time}}}`. `save.slot_player_export({slot})` reads a player's
  things (`save.player_export` text) out of one without loading it: `{slot, data, progress, chapter}`.
  `save.slot_player_import({slot, data})`, during this mod's visit only, writes the player's things back into that
  save and nothing else of it: its story, towns and dungeon records stay as they are. Before the first write to a
  save in a run of the game the file is copied to `<save root>/moonmod/coop-own-saves/`.
- The operations that carry a save's text (`save.world_export/import`, `save.player_export/import`,
  `save.slot_player_export/import`, `save.account_get/set`, `session.start`, `georama.town_export/import`) take
  and answer up to 2 MiB; every other operation keeps the 64 KiB limit.
- One hero each: `party.room_hero_set({hero = "max" | "monica"})` makes this game play that hero whatever the
  story's party says, until `party.room_hero_clear()` (or the mod that set it unloads). Monica can be played before
  the story has her; the other hero cannot be changed to; the hero's own second shape (the ridepod, a monster form)
  is open when the story has opened it; sealed floors carry no seal. Nothing is written into the save: the rule is a
  filter where the game reads its party, and the story's own scripts still hear the story's party. A visit begun
  after it starts as that hero; set while playing, the game changes hero as soon as the player is free (walking a
  town or a floor). `world.get().room_hero` says which. The story's party fields (who is in the party, who can be
  changed to) travel with the world, not with a player's things.
- The world as it changes: `world.watch_set({enabled})` has this mod told, as `game.world.changed {kind, id,
  value}`, of each change this game makes to the parts of the save two games share: `flag` (a story flag, true or
  false), `counter` (a story counter), `progress` (id 0), `party` (id 0 the members, 1 who can be changed to, 2 the
  mask), `recruit` (a townsperson who can join, `{chara_no, status}`), `floor` (a dungeon floor's record, nine
  numbers), `stock` (how many of a Georama part are built and waiting to be placed, id the part's number),
  `gift` (an item one of the story's scripts gave this player, id the item's number, value how many; a chest's
  content and a floor's prize are not told: `world.change_apply` adds a gift to the other player's own bag) and
  `town` (id 0-4: that town's Georama changed; the value is only a number for the town as it stands, the town
  itself is `georama.town_export`'s). A town or a floor beginning is where the games start from and tells nothing.
  `world.change_apply({kind, id, value})` writes another game's change into the save without telling it back (every
  kind but `town`, which goes through `georama.town_import`); a floor's record is merged (flags together, higher
  counts, the better time). Each map's own flags are not shared.
- A Georama town is a number 0-4 (Sindain, Balance Valley, Veniccio, Heim Rada, Moon Flower Palace): its map's
  number, which is what `georama.town_export/import`'s `town_id` means. It is not `world.get().town_map`, which
  is the area; `world.get().georama_town` gives the number when the town on screen is one of the five (Palm
  Brinks has no Georama).
- A town as it is built: while the world is watched, a town in its editor is written into its record as its
  player builds, so `town` is told at each part placed, moved or taken away, not only on leaving the editor. The
  town a player walks in is written into its record too, whenever they walk free: the game itself writes a town only
  as its player leaves it or its editor, so a town loaded and changed since (by the story, or loaded before the game
  first saved it) stood ahead of its record. `georama.town_export`, `save.world_export` and a `georama.town_import`
  with `base` into the town on screen take the town as it stands, never an older record (except while a town taken
  from another game waits to be built here, when the record is the newer). A part both games put up in the same spot
  since the `base` stands once after the merge.
  `georama.town_import` into a town this game's player stands in answers `reloaded = false, rebuilding = true`:
  nobody is walked back to the entrance; the town on screen is built again from its record where the player
  stands, as soon as they walk free (after a scene or a menu, or on coming out of a house). A player in that town's
  editor gets it too, between the editor's actions: their own parts are written into the record first, the town is
  merged into that, and the editor's map is built again at once (`rebuilt = true`). Mid-action (a part held against
  a wall, a part, river or removal animating, the menu opening) it is refused as `busy`, to be tried again. The co-op
  mod numbers a joiner's towns ("#n" before the town) and the host's towns say the last of that joiner's they hold, so
  a joiner still building never takes a host town that lacks its newest part.
- Who runs a floor: in Chronicle Two the co-op mod has a floor's monsters run by whoever was on it first, host or
  joiner (`monsters.mirror_get` there, `monsters.puppet_set` in the other game), and by the other when the first
  leaves. The engine's operations do not care which game is the host.
- Down, not out: `player.down_rule_set({enabled})`. While it holds, a hero whose life runs out on a floor plays
  their death and stays lying (`player.get().down == true`): the game's own death (change hero, or Game Over) does
  not run, nothing strikes them, and this game's monsters go for the other players first.
  `player.revive({hp, x?, y?, z?})` stands them up with that much life, where they lie or at the place given;
  `player.give_up()` lets the game's own death run after all. The rule goes when the mod that set it unloads (a
  hero who is down then gets the game's death). `world.avatar_set`'s `down = true` marks another player's hero as
  down: this game's monsters neither go for it nor strike it.
- `world.get()` on a floor adds `exit_map`, the map the dungeon's own way out leads to (for
  `world.enter_map`), and the floor's clear as the game decides it: `monsters_counted` (the monsters still counted
  against the clear), `mimic_chests` and `floor_cleared`; in a Georama town, `georama_live_parts`, how many parts
  stand in the town as it is on screen.
- A panel from `ui.choice_open` stays until the player picks or backs out (a load or a scene between, it waits, as
  above). `ui.choice_close {}` closes the calling
  mod's own panel quietly, with no `ui.choice_made`, and answers `{closed}`; another mod's panel stays open.
- On a follower's floor a monster the leader gains after the floor was built (a late spawn) is made in the same
  slot here, from the floor's loaded kinds, a mod enemy or the game's own refer; a kind this game cannot make is
  refused for that slot only and logged once. A monster the leader no longer lists is gone here too, so it stops
  counting against the clear.
- A Georama part that lands where this game's player stands moves the player to the nearest walkable spot.
- Down, not out in the co-op mod: Revive is the left stick (L3) or V, not Chronicle's right stick or R. In a
  Dark Chronicle dungeon R3 changes to the ridepod or a monster form and R (the keyboard's R2) is the first-person
  view; L3 changes hero, which a room's one hero each turns off. The powder a reviver may use is the Resurrection
  Powder.
- The co-op mod in a room of two, either way round: the floor's check ("K", "SYNC": the doors opened there) goes
  both ways, so a host following a joiner's floor is offered to walk in again beside the joiner when that floor's
  monsters can't be copied; two floors built apart leave the host's standing. Where two games change one story flag
  or counter within three seconds of each other, the host's value stands: the host does not take the joiner's and
  tells its own again. After every swap of heroes the host says how the room stands ("SW is0" / "SW is1"), so two
  swaps that cross end on two heroes. A joiner's game holds the host's changes of the world ("X") and its towns
  that arrive between the host sending its world and the visit beginning, and takes them as it begins.
- A joiner who brings a save of their own writes into it only things that came out of it: a host that answers
  with things of its own keeping (an older host, or one that did not take the save) leaves the save as it is, and
  the joiner is told so. A room closing (the host closing it, the host's game gone) writes the joiner's things
  into their save before the visit ends.
- A headless game runs unpaced; `DC2_HEADLESS_BOUNDED=1` keeps it at the real tick rate (the live tests).

## Messages players leave for each other (`messages.*`, Chronicle)

The `messages.*` operations need `storage.read` / `storage.write`. There is no server: each
message is a small file in the **messages folder**, and a player who points that folder at one a sync service
shares (OneDrive, Dropbox, a LAN share) reads the messages of everyone else who does. The folder is the player's
choice, never a mod's, and no call takes a path: `DC_MESSAGES_DIR` when set, else the path on the first line of
`<save>/moonmod/messages-folder.txt`, else `<save>/moonmod/messages` (the player's own messages only). Each player
writes only their own fixed file names there (`<player>-<id>.json`, `<player>.ratings.json`); another player's files
are read as untrusted data (at most 2 KB a message, 4000 files a list, links not followed, anything malformed left
out). Anyone with the folder can read what is left in it.
- `messages.post({place, text})` leaves a message: `place` is 1-64 characters of `a-z 0-9 : _ . -` that the mod
  names (a spot every player's game has, such as a shrine), `text` 1-120 characters of printable ASCII. Returns `{id,
  shared}` (`shared`: the folder is one the player chose). A player keeps 300 messages at most.
- `messages.list({place})` or `({places = {...}})` (up to 32): the mod's messages there, best rated first, then
  newest, at most 50: `{messages = {{id, place, text, at, good, poor, mine, rated}, ...}, shared}`. Only messages
  the same mod left are listed. Show text as text: a mod that builds its messages from fixed phrases (as Vigil does)
  should show only those that parse back into them.
- `messages.rate({id, rating})`: 1 good, -1 poor, 0 takes it back; not one's own.
- `messages.remove({id})` takes back one of the player's own.
