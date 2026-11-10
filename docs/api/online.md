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
