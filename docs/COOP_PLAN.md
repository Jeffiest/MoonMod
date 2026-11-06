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
| Accounts | `save.account_*`, kept in the host's slot folder with each save; tested |
| Visits | `session.start {visit}`: the host's world and the guest's things in a fresh game, in the host's town; no save writes |
| The mod: joining | Host (F8 or Mod Manager), join from the title screen's Online Co-op by code; the world and the account cross in pieces; a new account for someone new; the guest's things go to the host every minute and on leaving (F10); the host leaving ends the visits. `tools/tests/coop/test_coop.lua` |

## Next

1. **Seeing each other.** Remote players drawn as characters of their own (the engine's death ghost plays back one
   recording; this needs up to three live ones), position, heading and motion sent ten times a second, in the same
   scene only. The fork's `dc.ghost` and its own-texture tints (host natural, guests blue).
2. **Georama.** A guest's edit becomes a request to the host, which places it (`georama.place/remove`) and tells
   everyone; each game applies it to its loaded town; a player standing where a part lands goes back to the entrance.
3. **Dungeons.** The floor seed from whoever enters first (`dungeons.set_seed`); monsters mirrored from the host
   (the fork's puppets), guests' hits sent to the host, monster hits on guests sent back; loot on each machine; the
   shared pause; doors and key rooms opened for everyone (the fork's `MpEventPoll`).
4. **Accounts, wider.** Gear and charm slots (MoonMod's own, beside the save) in a guest's things; mods' levels
   (RPG, Ascension) the same way; the host's view of its guests in the Mod Manager (list, forget).
5. **Joining.** A picker for the code on a keyboard; the server setting on the title page; friends' names on the HUD.
