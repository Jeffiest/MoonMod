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
| Relay | Cloudflare Worker and private server (`server.mjs`, Docker), one protocol (`coop/relay/README.md`); tested |
| `net.*` | Rooms by code, text messages, 4 players; web WebSocket, Windows WinHTTP, Linux/macOS libcurl; tested against both relays (Windows compiled, not run) |
| The save's split | `save.world_export/import`, `save.player_export/import`; tested |
| Accounts | `save.account_*`, kept in the host's slot folder with each save; the Mod Manager lists them and forgets those not in the room (two presses); a guest's things carry their gear and charm slots, and mods' own (`save.player_extra_*`): RPG's and Adventurer's levels; tested |
| Other mods in a visit | RPG and Adventurer level the guest from their account; Dungeon Plus and Modern Cloud play on; Randomizer and Living Towns, whose state is the host's save's, sit out |
| Visits | `session.start {visit}`: the host's world and the guest's things in a fresh game, in the host's town; no save writes |
| The mod: joining | Host (F8 or Mod Manager), join from the title screen's Online Co-op by code (typed, or letter by letter on a pad); the world and the account cross in pieces; a new account for someone new; the guest's things go to the host every minute and on leaving (F10); the host leaving ends the visits. `tools/tests/coop/test_coop.lua` |
| Seeing each other | `world.avatar_set`: up to three other players on the dungeon floor, with their weapons, easing between reports sent ten times a second; the host in its own colours, guests in blue; only on the same floor; gone after three quiet seconds. Every game builds each floor from the room's seed, so floors match whoever arrives first |
| Monsters | The host's game runs each floor's monsters: they wake for and chase the nearest player, a remote one too, and a blow, shot or spell on a guest's hero goes to that guest as a monster's blow (`combat.strike_player`, so guard and dodge work; a small hit flinches, a blow knocks back). A guest's monsters are copies of the host's (`monsters.puppet_set`), fifteen reports a second; a guest's blow (a weapon's, a bomb's, a thrown item's) goes to the host's monster (`monsters.mirror_hit`); a kill on the host is a death on every game. Loot stays each game's own: a chest or a drop is every player's to take, in their own game |
| Doors | A door, gate or switch one player opens (a script that changes the floor without leaving it) opens in every game on that floor (`dungeons.shared_events_get/run`), the key taken as given; each game keeps the floor's opened doors for a player who arrives later |
| Towns | Players walking in the same town see each other there, as the town's hero each walks as; one in a menu or a talk still stands where they were |
| The clock | The host's time of day, every ten seconds, to a guest whose clock has drifted (`world.set_time`) |
| Names | Each player's name over their hero on the floor or in town, and the others' names on the HUD under the room's code (the mod's "name" setting), the guests' in blue |
| Pausing | A pause or menu holds only that player's game. The host's holds the floor's monsters for everyone (the guests' copies wait where they are); a guest's holds nothing of the others' |
| Georama | A player's edit goes, once they leave the editor, to the host's world (`georama.town_export/import`) and from there to everyone; a player walking in that town is walked back to its entrance; a player busy in that town's editor gets it once free |

## Next

1. **Seeing each other in Georama's edit mode** (walking in a town is done): the editor's camera and cursor.
2. **Georama, finer.** Two players editing one town at once are told so (the last to leave the editor keeps their
   changes); merging the two edits chip by chip would keep both.
