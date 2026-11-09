# Co-op 2: a plan for co-op that plays well

`docs/COOP_PLAN.md` covers what is built: rooms, visits, the host's world, ghosts, mirrored monsters, doors, towns,
Georama and the room's mods. That all works in tests, but playing it still feels half done. Players are in the same
place without really playing together. This plan takes what the best co-op games in Dark Cloud's style do and puts
each of those things in, mapped to Dark Cloud's own systems.

## Where it stands

The pieces that work:
- Joining by code, matching the room's mods, and the host's world for everyone.
- Seeing each other on floors and in towns, with names over heads.
- The host's monsters copied to the guests, hits from either side counting, and kills ending on every game.
- Doors and switches shared, Georama shared, follow offers, and giving Gilda and items.
- The live two-game harness: basic, floors, host_leaves.

What's missing, the things that make it feel half done:
- **No life and death rules.** Nothing in co-op handles a player falling, a revive, or a whole party falling. Each
  game runs its own rule.
- **Shared progress isn't shared.** The host's world owns Atla, Geostones, keys, floor clears and back floors. A
  guest who picks one up does so in their own game, which never reaches the host's save. (Check this first.)
- **No party view.** There's no HP for the others, no markers on the map, no arrows to a player off screen, and no
  way to say "here" or "help".
- **The same game for one or four.** Monsters, bosses and drops don't change with the number of players.
- **Everyone plays Toan.** Dark Cloud's six heroes and their field abilities aren't part of co-op.
- **Story scenes and bosses only happen to the host.** Guests aren't brought in.
- **Hard to find each other.** There's no room list, and a dropped player can't get back to where they were.
- **Lag is felt.** A guest's hits and the monsters' moves wait on the host, with no smoothing or ping shown.

## The reference games

Games with Dark Cloud's shape: a hero party, a town hub, randomly built dungeon floors, real-time action, gear that
grows.

| Game | Why it's close | What we take |
| :-- | :-- | :-- |
| **Phantasy Star Online** (DC/GC/PC) | Town hub plus 4-player dungeon floors, gear that grows, played on pads | Lobbies and a room list; Word Select and Symbol Chat (talking from a pad); Telepipe (a portal home and back for the party); Moon Atomizer (revive an ally) and Scape Doll (revive yourself, like Revival Powder); the whole party stands on the warp to go on; drops of your own |
| **Diablo III / IV** | Drop-in online action RPG, town plus dungeons, loot | Monster HP and drops scale with players; your own loot; banner teleport (warp to an ally); hold to revive, with a death timer growing per death; party portraits with HP; "X joined" with scaling at once; rejoining a game in progress |
| **Monster Hunter World / Rise** | Host-run monsters copied to the others, the closest model to ours | SOS flare (call for help mid-hunt: a public room); a shared faint limit (three carts, then the quest fails); monster HP scaled for a party; gestures, stickers and quick chat; damage numbers in each player's colour; everyone rewarded for a hunt |
| **Elden Ring and its Seamless Co-op mod** | Guests in the host's world, with the host's progress, like our visits | Boss fog walls: the fight starts when the party walks in, and late players can join; boss HP scaled per player; a fallen guest becomes a spectator until the boss dies or the party rests, instead of the visit ending; the party travels together |
| **Minecraft Dungeons** | Simple 4-player action dungeon crawler on pads | Revive a downed friend; teleport to a friend who is far away; your own loot; difficulty that follows the party |
| **Baldur's Gate: Dark Alliance / Champions of Norrath** (PS2) | Same era and feel as Dark Cloud, co-op on PS2 | Drop in and out; shared kills (XP for everyone); camera and screen space kept for the whole party; local couch co-op |
| **Secret of Mana** | Party action RPG with drop-in players and a menu that pauses | Every party member a different hero; the AI plays heroes no one is playing; your menu pauses only for you (we have this) |
| **Divinity: Original Sin 2 / Baldur's Gate 3** | Story-heavy co-op | Story scenes the others can watch ("listen in"); the party sees who is talking; votes on choices |
| **Deep Rock Galactic** | Co-op made for strangers | Pings (point at a monster, item or spot); hold to revive; resupply; an end-of-mission summary with each player's numbers |
| **Torchlight II** | Town hub, floors, loot, modding | Your own loot; a shared town portal; party bars; a pet that runs loot to town (Dark Cloud's allies could) |

## The plan

Seven phases, in order. Each one lands on its own, gets a live-harness scenario, and gets a hand playtest before the
next starts. "From" says which game the idea comes from.

### Phase 1: Solid ground (before anything new)

Nothing below matters if a session drifts or drops.

**Built 2026-11-08 (co-op 0.10.0):** ping on the HUD, "no signal", a guest's rejoin after a drop, the host closing
with every guest's things kept first, the out-of-step check with the offer to walk in again, "Resync with the host",
the join timeout, monster copies that lead instead of trailing, a guest's hits shown at once, and readable failures.
Live scenario `rejoin` and the checklist `tools/tests/coop/live/PLAYTEST.md`. Not done: the host can't rejoin after
its own connection drops (the relay closes a room whose host goes; it would need the relay to hold the room for a
moment), and the monster send rate isn't raised on a busy floor.

| What | From | Dark Cloud detail |
| :-- | :-- | :-- |
| **Desync check and resync** | Every online game | Every few seconds each game sends a short checksum: floor seed, the monster list, opened doors, the clock. On a mismatch, the guest asks the host for the floor's state again (a "resync" a player can also press). Log the cause. |
| **Rejoin after a drop** | Diablo, MHW | A dropped guest has 2 minutes to come back and is put on the same floor and cell, with their things. The room keeps their slot, and the others see "X lost connection, waiting". |
| **The host leaving** | Diablo, PSO | A 10-second "the host is leaving" warning; every guest's things are saved to the host first, then each guest goes back to their title screen with a clear message. Today it just ends. |
| **Smooth monsters and fast hits for guests** | MHW, Diablo | Guests draw the host's monsters a little behind, eased between reports, and predict a monster's own movement. A guest's hit shows at once (spark, sound, damage number) and the host confirms it. If the host rejects it, the number is taken back. Raise the monster send rate when the floor is busy. |
| **Ping and connection shown** | Every online game | Each player's ping on the party panel, and a warning icon when a player's reports stop. |
| **Errors players can read** | — | Every co-op failure gives a toast in plain words and a line in the log, never silence. |
| **Tests** | — | Live scenarios: rejoin, a desync forced by the harness, and the host leaving mid-fight. A hand playtest checklist in `tools/tests/coop/live/PLAYTEST.md`. |

### Phase 2: The party you can see

| What | From | Dark Cloud detail |
| :-- | :-- | :-- |
| **Party panel** | Diablo, PSO, Torchlight II | Under your own HP: each other player's hero portrait, name, HP, thirst, their weapon's WHP, and where they are ("B4", "Norune"). It goes red when they're down and grey when they're away. |
| **Map markers and arrows** | Diablo, MC Dungeons | Each player as a coloured dot on the floor map and the town map, and an arrow at the screen's edge for a player off screen on the same floor. |
| **Pings** | Deep Rock Galactic | One button: ping what you're looking at. A monster ("Here"), an item or chest ("Look"), Atla ("Atla!"), a door, or a spot ("Go"). The others get a marker for 8 seconds and a sound. Pad-friendly. |
| **Quick chat and gestures** | PSO Word Select, MHW | A ring of short phrases on a pad (Thanks, Help!, Wait, Go on, Good game, Back to town, Need water). Text chat on a keyboard. Gestures like waving and cheering, played as the hero's motions. |
| **Damage numbers in each player's colour** | MHW | Optional (a setting): the numbers on monsters in the colour of whoever hit them. |
| **Join and leave notices** | Diablo | "X joined (3 players)". Scaling (Phase 5) applies at once. |
| **Warp to a friend** | Diablo banner, MC Dungeons | From the menu or the party panel, warp to a player on the same floor, or join them on another floor (this exists as a follow offer). Not while fighting, as in Diablo. |

### Phase 3: Falling and getting back up

Dark Cloud's own rule is that HP at 0 means game over, unless Revival Powder brings you back. Co-op needs a kinder rule.

| What | From | Dark Cloud detail |
| :-- | :-- | :-- |
| **Down, not out** | Diablo, MC Dungeons, DRG | At 0 HP a player falls down for 30 seconds and can crawl. Monsters leave them alone. |
| **Revive a friend** | Diablo, DRG, PSO Moon Atomizer | Hold a button next to them for 3 seconds, which a hit interrupts. They get up with a third of their HP. Using Revival Powder on a downed friend revives them at once. |
| **Revival Powder still works** | PSO Scape Doll | Revival Powder in your own bag revives you as in the original, before you go down. |
| **Out, then back** | Elden Ring Seamless, Diablo | A player whose down timer ends is out. They watch the others (spectate, swapping between them) and come back at the floor's entrance when the floor is cleared, the party leaves the floor, or after a timer (30 s, growing 15 s per death, as Diablo). |
| **Whole party down** | MHW faint limit | Everyone is sent back to the town they came from, keeping their things, and the floor resets. A setting gives a shared faint limit instead (3 faints a floor, then back to town). The host's save is never lost. |
| **Tests** | — | A live scenario: guest down, host revives; both down, both back in town. |

### Phase 4: Shared progress (one world, really shared)

The host's save is the world. Anything that is the world's has to land there, whoever picks it up.

| What | From | Dark Cloud detail |
| :-- | :-- | :-- |
| **Atla for the world** | — (Dark Cloud's own) | Atla picked up by anyone goes to the host's world. It's gone from the floor in every game, the floor-select counts it, and the host's save keeps it. Whoever picked it up sees "X found Atla: <part>" and opens it at the town as now. The host's world holds the result. |
| **Geostones, keys, maps and crystals** | PSO, Elden Ring | A floor's key opens its gate for the whole party (doors already open for everyone; the key itself should too). The map and the crystal are revealed for everyone on the floor. Geostone goes to the world, like Atla. |
| **Floor cleared and back floors** | — | A floor counts as cleared, with its back-floor progress, in the host's world when any player clears it. |
| **The way down needs the party** | PSO warp, Elden Ring fog | Taking the gate to the next floor or the Back Door asks everyone on the floor: "Go down? 2/3 ready". A player can stay behind and follow later (a follow offer). A setting turns this off for free roam. |
| **Kills count for everyone nearby** | Dark Alliance, Diablo | When a monster dies, each player on the floor within range gets the ABS (weapon growth) and the drops their own game rolls, whoever landed the last hit. Today only a kill in your own game grows your weapon. |
| **Story scenes for everyone** | DOS2 / BG3 listen-in | A story scene the host starts plays for every player in that town or on that floor. A guest elsewhere gets "Story scene in Norune: watch?". Skipping needs everyone, or the host. A guest's own story scene doesn't play, since the story is the host's. |
| **Bosses as a party fight** | Elden Ring, MHW | A boss room's entrance (Dran, the Wardens and the rest) shows "Fight X with the party? 3/3 ready". The fight starts for everyone who walked in, and late players can join for a short while. Boss HP scales (Phase 5). The win and its scene go to everyone. |

### Phase 5: Balance for a party

| What | From | Dark Cloud detail |
| :-- | :-- | :-- |
| **Monster HP scales with players** | Diablo, MHW, Elden Ring | Each monster's max HP is multiplied by 1 + 0.6 × (players on the floor − 1), changing as players come and go (current HP keeps its share). Bosses use 1 + 0.75 per extra player. The numbers are settings. |
| **More drops for more players** | Diablo | Each player rolls their own drops (built), and a floor gets a few more monsters with more players (a setting). |
| **A difficulty setting for the room** | Diablo | Normal, Hard, or Brutal: the host picks, and the room's mods carry it. |
| **No friendly fire** | Most co-op games | Bombs, thrown items and magic never hurt the other players. |
| **Supplies for a party** | DRG resupply | A setting: water springs give water to the whole party. |

### Phase 6: Every hero in play

Dark Cloud has six heroes with field abilities: Toan, Xiao, Goro, Ruby, Ungaga and Osmond. Party co-op games use
that.

| What | From | Dark Cloud detail |
| :-- | :-- | :-- |
| **Each player picks a hero** | Secret of Mana, Dark Alliance | From the heroes the host's story has brought in. Two players can't be the same hero (a setting allows it). Each player's own things hold their gear for each hero. |
| **Field abilities across players** | Secret of Mana | Goro breaks the rock, Xiao hits the switch, and Ruby and Ungaga do their part, whoever plays them. The door and switch sharing already carries the result. |
| **Heroes no one plays** | Secret of Mana | Out of reach as allies (the engine has one active hero per game). Later, maybe. |
| **Your hero shown right to the others** | — | Avatars already send the hero and weapon. Check every hero's motions on avatars. |

### Phase 7: Finding each other and staying

| What | From | Dark Cloud detail |
| :-- | :-- | :-- |
| **Room list** | PSO lobbies, MHW SOS | A host can make a room public, listed with its name, the host's chapter, mods and player count, on the relay. "Help wanted on B8" while on a floor (SOS). Private by code stays the default. |
| **Recent players** | Diablo | The title page's Online Co-op lists rooms of players you've played with, if open. |
| **A party portal to town** | PSO Telepipe, Torchlight II | Leaving a floor by Gun/escape lets the others take the same way back and return with you. |
| **End-of-floor summary** | DRG | On leaving a floor: each player's kills, damage, revives, Atla found, and time. |
| **Trade window** | PSO, Diablo | A proper trade: both put things in, both confirm (replacing today's one-way give). |
| **Building together** | — | In the Georama editor, see the others' cursors and what they're placing (live), not only after leaving. |
| **Local couch co-op** | Dark Alliance, Champions | A stretch goal: a second pad on the same PC, as a second player in the same game. It needs the engine to run two heroes and a shared camera, so it is a big piece. Online play comes first. |

## Choices for you

These decide how some pieces work:

1. **Death rule.** Down-then-revive with the party sent to town on a wipe (suggested), or the shared faint limit as
   the default.
2. **Two players as the same hero.** Allowed, or one each (suggested: one each, with a setting).
3. **The way down.** Everyone ready (suggested), or the first player there takes everyone.
4. **Scaling numbers.** +60% monster HP and +75% boss HP per extra player (suggested), or another number.
5. **Public rooms.** Do you want a room list on the public relay at all, or codes only.

## Order and size

| Phase | Size | Engine work |
| :-- | :-- | :-- |
| 1 Solid ground | Medium | Floor checksum, monster interpolation, a guest's hit shown before the host confirms |
| 2 The party you can see | Medium | HUD panel, map markers, ping markers, gestures as motions |
| 3 Falling and getting back up | Medium | A downed state for the player, spectate camera |
| 4 Shared progress | Large | Atla, Geostone, key and floor-clear events to the host; story scene triggers on guests; boss entry |
| 5 Balance | Small | Monster max HP set; floor monster count |
| 6 Every hero | Medium | Hero choice in a visit; check field abilities on guests |
| 7 Finding each other | Medium | Room list on the relay; trade window; Georama live |

Phase 1 comes first, then 3 and 4 (the ones that make it a game), then 2, 5, 6 and 7.
Each phase ends with its live scenarios passing and a hand playtest.
