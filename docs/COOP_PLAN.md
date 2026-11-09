# Online Co-op: plan

Up to four play Dark Cloud together online, web and PC alike, through the co-op relay (DC_Web's `coop/relay`: the
public Cloudflare Worker, or anyone's private server). The engine's side is `net.*` (online play), `save.*`'s split and
accounts, and visits (`docs/API.md`); the game's side is the Online Co-op mod, `mods/moonmod.coop`. It ports the co-op
of Jeffiest/Chronicle's `windows` branch (`win/docs/MULTIPLAYER.md`): ghosts, shared floors, mirrored monsters, the
shared pause and doors.

## The rules (decided 2026-11-06)

- **The host's save is the authority.** The world is always the host's: the story, the characters it has brought,
  the towns and their Georama, dungeon progress. Guests come in at the host's story progress.
- **Guests' things live in the host's save.** On joining, the host's game looks the guest up by the id the guest's
  game made: someone it knows gets their things back, someone new starts a new account. A guest's things are their
  own: inventory, weapons, levels, Gilda. The host's save keeps them (`coop_accounts.json` beside the slot); they last
  when the host saves.
- **A guest's own save is never touched.** A visit is a session of its own: it never writes a save slot.
- **Georama edits apply to the host's world**, whoever makes them, and reach everyone. A player displaced by an edit
  is put back at the town's entrance.

## Built

| | |
| :-- | :-- |
| Relay | Cloudflare Worker and private server (`server.mjs`, Docker), one protocol (`coop/relay/README.md`); live at `wss://chronicle-coop-relay.jeffery-s-rose.workers.dev`, the builds' default; tested |
| `net.*` | Rooms by code, text messages, 4 players; web WebSocket, Windows WinHTTP, Linux/macOS libcurl; tested against both relays (Windows compiled, not run) |
| The save's split | `save.world_export/import`, `save.player_export/import`; tested |
| Accounts | `save.account_*`, kept in the host's slot folder with each save; the Mod Manager lists them and forgets those not in the room (two presses); a guest's things carry their gear and charm slots, and mods' own (`save.player_extra_*`): RPG's and Adventurer's levels; tested |
| Other mods in a visit | RPG and Adventurer level the guest from their account; Dungeon Plus and Modern Cloud play on; Randomizer and Living Towns, whose state is the host's save's, sit out (`"coop": "host_only"`). Every game in a room plays the same mods at the host's versions and settings: see "The room's mods" |
| Visits | `session.start {visit}`: the host's world and the guest's things in a fresh game, in the host's town; no save writes |
| The mod: joining | Host (F8 or Mod Manager), join from the title screen's Online Co-op by code (typed, or letter by letter on a pad); the world and the account cross in pieces; a new account for someone new; the guest's things go to the host every minute and on leaving (F10); the host leaving ends the visits. `tools/tests/coop/test_coop.lua` |
| Seeing each other | `world.avatar_set`: up to three other players on the dungeon floor, with their weapons, easing between reports sent ten times a second; the host in its own colours, guests in blue; only on the same floor; gone after three quiet seconds. Every game builds each floor from the room's seed, so floors match whoever arrives first |
| Monsters | The host's game runs each floor's monsters: they wake for and chase the nearest player, a remote one too, and a blow, shot or spell on a guest's hero goes to that guest as a monster's blow (`combat.strike_player`, so guard and dodge work; a small hit flinches, a blow knocks back). A guest's monsters are copies of the host's (`monsters.puppet_set`), fifteen reports a second; a guest's blow (a weapon's, a bomb's, a thrown item's) goes to the host's monster (`monsters.mirror_hit`); a kill on the host is a death on every game. Loot stays each game's own: a chest or a drop is every player's to take, in their own game |
| Doors | (A setting, on by default.) A door, gate or switch one player opens (a script that changes the floor without leaving it) opens in every game on that floor (`dungeons.shared_events_get/run`), the key taken as given; each game keeps the floor's opened doors for a player who arrives later |
| Towns | Players walking in the same town see each other there, as the town's hero each walks as; one in a menu, a talk or Georama's editor still stands where they were, and a player in the editor sees the others walking about |
| The clock | The host's time of day, every ten seconds, to a guest whose clock has drifted (`world.set_time`) |
| Together | When another player goes to another floor, town or house, a panel offers to join them there (setting, on by default); the Mod Manager's "Join a player" does it later. Players give each other Gilda or items from their bag (F7 or "Give to a player"): what doesn't fit in the other's wallet or bag comes back |
| Names | Each player's name over their hero on the floor or in town, and the others' names on the HUD under the room's code (the mod's "name" setting), the guests' in blue |
| Pausing | A pause or menu holds only that player's game. The host's holds the floor's monsters for everyone (the guests' copies wait where they are); a guest's holds nothing of the others' |
| The link (0.10.0, protocol 8) | Each player's ping by their name on the HUD (a PING/PONG every two seconds); a player unheard for eight seconds is "no signal", and the others are told. A guest whose connection drops keeps playing and gets back into the room by itself, every five seconds for two minutes ("BACK", answered "RESUME": no world sent again); the host hears "connection dropped", not "left". The host closing says "BYE" first: every guest's things go to it, then the room closes (ten seconds at most; F10 again closes at once). Every five seconds the host says its floor and how many doors it has opened there ("K"): a guest on that floor built differently, or whose copies of the host's monsters can't be made for five seconds, is offered to walk in again beside the host; one with fewer doors asks for them ("SYNC"), as does the Mod Manager's "Resync with the host". A join the host never answers ends after half a minute |
| Monster copies | A guest's copy leads along the host's monster's movement (its speed between reports, a fifth of a second ahead at most) instead of trailing it; a guest's blow lowers the copy's HP at once, until the host's report has it (or three quarters of a second) |
| Georama | A player's edit goes, once they leave the editor, to the host's world (`georama.town_export/import`), merged into it (only what they changed, so two building in one town at once both keep their work; they are told of each other), and from there to everyone; a player walking in that town is walked back to its entrance; a player busy in that town's editor gets it once free |

## The room's mods (0.9.0, protocol 7)

Every game in a room plays the same mods, at the same versions, with the host's settings.

- **Roles.** Each mod's manifest says where it belongs in a room (`"coop"`, read through `mods.list`): `required`
  (the default) every player has it at the host's version; `host_only` only the host needs it (Randomizer and Living
  Towns, whose state is the host's save's); `local` each player's own (Autosave, Controls, Expanded Town, the Hub).
- **The check.** A joining game sends its mods (`MODS id version role;...`) before its hello. The host compares
  them with its own: a required mod the guest lacks (enable), has at another version (the host's version), or a
  required mod of the guest's that the host doesn't play (turn it off, since it would change the world under the
  guest). Any of these and the host sends the list (`NEEDMODS`) instead of its world. Host-only and local mods are
  never asked for. A game whose engine can't list its mods is turned away with "update MoonFactory".
- **Turned away.** The guest leaves the room and keeps the list. The title page's Online Co-op shows what is still to
  change ("Room ABCDE needs 2 mod changes (Mod Manager, then restart)") and strikes off what is done; the Mod
  Manager's "Mods needed to join" says it in full. Enabling a mod takes effect at the next launch, so it is enable,
  restart, join again. The list is forgotten once a join gets the world.
- **The host's settings.** With the mods matching, the host sends its values for every required mod but co-op's own
  (`SETTINGS`, before the world). The guest's game holds them for the visit (`mods.settings_overlay`): never written
  to the guest's profile, dropped when the visit ends (by the mod, and by the engine on `game.session.ended`). A mod
  that reads a setting live, or listens to `settings.changed`, follows them at once; one that reads a setting only
  when it loads keeps the guest's own value for that setting.

What it can't do: enable a mod for the guest (the engine loads only what the player enabled), and co-op inside a
Gauntlet run or a Vigil World (co-op hosts only from a story save; a visit carries the story save's world, not a
run's).

Tests: `tools/tests/coop/test_coop.lua` ("The room's mods") and the engine's `moonmod_mods_api_test.cpp`.

## Next

The plan for co-op that plays well, with what the best co-op games do mapped to Dark Cloud: `docs/COOP_V2_PLAN.md`.

Playing it: everything above is built and tested in the mod's script tests and the engine's unit tests, not yet in two
real games together.
