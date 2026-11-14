# Open World

Dark Cloud as one world to walk, built in steps. The whole plan is in
[docs/plans/OPEN_WORLD_PLAN.md](../../docs/plans/OPEN_WORLD_PLAN.md); this page says what the mod does today.

It works on any story save. It does nothing at the title, in Dark Genie's Gauntlet or another mod's game mode, or
while you are a guest in a friend's world.

## What it does now

**No loading card on the way from one place to another.** Town to town, town to dungeon, a floor to the next, a
scene that takes you somewhere: the picture you left stays up for the moment the next place takes to load (about half
a second), then you are there. The game's own card stayed up 6.6 seconds whatever the load took. Loading a save,
from the title or the pause menu, has no card either: you are in the save's town or on its floor a moment after
you pick it. Starting a new game keeps the card.

**Out of a dungeon with no card.** Knocked out, or leaving by the escape item: the screen fades to black as the
game always did, and the town is there a moment later, with the party in front of the dungeon.

**Floors you walk through.** The floors of a dungeon between two of its special floors are one map, a stretch of
rooms to a floor, joined by locked gates. A monster on your side of a gate carries its key; take the key to the
gate and walk on into the next floor, with no stairs, no scene and no load. "Floor 2" shows as you step through,
and the floor number on screen follows where you stand. Atla, chests and monsters are each floor's own. Pick a
later floor at the dungeon's entrance and you start there, the gates behind you open.

**The stairs that are left have no scene.** A map still ends where the game needs one of its own: a boss, a story
floor, a floor that takes the party down to one character, a floor whose opening scene you have not seen yet (it
joins its neighbours once you have), and where the dungeon's walls change. At that last gate the "next floor or
leave" question comes up right where you stand: no walk out. Circle steps back. Answer, and you are standing on
the next floor a fraction of a second later with control: no walk in, no black. The game played over a second of
walking out, went black around the question and over the build, and played four and a half seconds of walking
in. Leave takes you to the town the same way, in front of the dungeon.

| Dungeon | Floors on one map |
| --- | --- |
| Divine Beast Cave | 1-3, 5-6, 9-10, 12-14 once their scenes are seen |
| Wise Owl Forest | 1-3, 5-8, 10-11, 13-16 |
| Shipwreck | 1-4, 6-8, 10-11, 13-16 |
| Sun and Moon Temple | 1-4, 6-8, 10-12, 14-17 once its scenes are seen |
| Moon Sea | 1-3, 5-7, 9-10, 12-14 |
| Gallery of Time | 1-6, 7-12, 13-18 |
| Demon Shaft | 1-20, 21-40, 41-60, 61-80, 81-98 |

A floor your save puts a rule on (one character only, no healing) stands alone as well, so a stretch can be
shorter than the table says. In the Gallery of Time and the Demon Shaft the last gate is its own lock: it plays as the game
has it until you have used its key, and asks where you stand from then on.

**Into a house and out with no fade.** Press at a door and the party opens it; the room is there about a second
later, and the town as quickly on the way back out. The game faded to black and in again each way: close to three
seconds going in, three and a half coming out.

**A town and its dungeon are one place.** Norune and the Divine Beast Cave, Matataki and the Wise Owl Forest: walk
through the door and you are there, and you can see the other place through the doorway before you step in.

**A town's gate is the road.** Walk out of a town's gate and a panel asks which way: on to the next town, back to the
last one, or into a dungeon that the world map used to reach (the Shipwreck from Queens, the Sun and Moon Temple from
Muska Lacka, the Moon Sea and the Gallery of Time from Yellow Drops). Pick **Stay** or back out to stay in town.

| From | The road leads to |
| --- | --- |
| Norune Village | Matataki Village |
| Matataki Village | Norune Village, Queens |
| Queens | Matataki Village, Muska Lacka, Shipwreck |
| Muska Lacka | Queens, Yellow Drops, Sun and Moon Temple |
| Yellow Drops | Muska Lacka, Moon Sea, Gallery of Time |

**The story still opens the way.** The road only offers places your save's world map would show. A town with nowhere
open yet (Norune before the story sends you to Matataki) keeps its gate as the world map, so nothing is shut that was
open before.

The trip along a road still loads the next place, behind the held picture. Walking the road itself is a later step
of the plan.

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| No loading card on the way from one place to another | on | The held picture on every trip, the passage through a town's dungeon door, house doors with no fade, and the exit gate with no black |
| Walk from floor to floor: no stairs scenes, floors joined by gates | on | Floors on one map joined by locked gates, and no walk out or walk in at the stairs that are left. Off: every floor is its own map and the stairs play their scenes (still with no black) |
| A town's gate is the road to the next town, not the world map | on | The road panel at the gate |
| The road only leads where the story has opened the way | on | Off: every road is open from the start |

## With other mods

The engine gives each of these rules to one mod at a time (`dungeons.set_quick_passage`, `world.set_roads`,
`dungeons.set_zones`). Open World takes a rule only when nobody else holds it, and answers nothing for a rule it
doesn't hold.

- **Vigil.** On a Vigil World save, Vigil sets the roads as the town loads and its own road panel answers the gate. On
  any other save Vigil leaves the gate alone and Open World answers it. Either way one panel opens, never two.
- Open World asks for the road only once you stand in a town, so a mod that sets the roads as a place loads is always
  first.
- **Floors.** Open World asks for its joined floors as a request that gives way (`yield = true`): a mod that lays
  floors out its own way (Vigil World's whole dungeon on one map, the Gauntlet) gets its layout, whichever asked
  first.
- When a game ends, or the mod is switched off, it lets go of all three rules.

## For modders

The pattern here works for any one-owner rule: ask for it each time you need it, treat a refusal as "someone else has
it", act on the rule's event only while your own claim stands, and release it on `game.session.ended` and
`runtime.unloaded`. `main.lua` is short and shows all four. The `FLOORS` table in it says, per dungeon, which
floors stand alone and where the walls change; `region_of` turns that into the floors built as one map.

Tests: `lua tools/tests/openworld/test_openworld.lua`.

## Playtest

- [ ] Norune: walk into the Divine Beast Cave and back out with no loading card.
- [ ] Any trip (the world map, a road, a story scene that moves you): no "Now Loading" card; the last picture holds
      for a moment, then the next place is there. An arrival scene plays from its start.
- [ ] Load a save from the title: no "Now Loading" card; the town (or the floor) is there within a second. The same
      from the pause menu's load.
- [ ] In a dungeon, use the escape item, and get knocked out (pick Leave): each fades to black and cuts to the town
      with no card; the party stands in front of the dungeon.
- [ ] Divine Beast Cave from floor 1: find the monster with the key, open the gate and walk into floor 2, then
      floor 3. No stairs, no load; "Floor 2" shows; the floor number, the atla and the monsters are each floor's
      own. Leave and come back in at floor 2 from the entrance's list: you start on floor 2, the gate behind open.
- [ ] At the last gate of the map (floor 3's): the question comes up where you stand, with no walk out. Circle:
      you step back and can walk away. Answer next floor: you are on floor 4 at once, in control, with no walk in
      and no black. Pick Leave at a gate: the town is there, the party in front of the dungeon.
- [ ] The same in each dungeon you can reach. Gallery of Time or Demon Shaft: the last gate plays as the game has
      it until its key is used.
- [ ] A floor that opens with a story scene you have not seen: the scene plays; afterwards that floor is joined to
      its neighbours.
- [ ] Sound at a gate with no scene: the door and the window sound right, nothing cut short or left playing.
- [ ] Turn **Walk from floor to floor** off: every floor its own map again, the stairs' scenes play, still no black.
- [ ] Norune: go into a house and come out again. The party opens the door, then the room (or the town) is there,
      with no fade to black; the door's sound plays as it did. Try a house in another town as well.
- [ ] Norune before Matataki is on the world map: the gate still opens the world map.
- [ ] Once Matataki is open: the gate shows **The road** with Matataki Village and Stay; the party stands still while
      the panel is up.
- [ ] Take the road to Matataki; its gate offers Norune (and Queens once open).
- [ ] Queens: the road offers the Shipwreck, and taking it starts at floor 1.
- [ ] With Vigil on and a Vigil World save: Vigil's road panel shows, not this one, and the dungeon is Vigil's
      whole map, not this mod's stretches.
- [ ] Dark Genie's Gauntlet: nothing changes.
