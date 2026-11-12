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

**Out of a dungeon with no card.** Knocked out, or leaving by the escape item or the floor's exit: the screen fades
to black as the game always did, and the town is there a moment later, with the party in front of the dungeon.

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
| No loading card on the way from one place to another | on | The held picture on every trip, the passage through a town's dungeon door, and house doors with no fade |
| A town's gate is the road to the next town, not the world map | on | The road panel at the gate |
| The road only leads where the story has opened the way | on | Off: every road is open from the start |

## With other mods

The engine gives each of these two rules to one mod at a time (`dungeons.set_quick_passage`, `world.set_roads`). Open
World takes a rule only when nobody else holds it, and answers nothing for a rule it doesn't hold.

- **Vigil.** On a Vigil World save, Vigil sets the roads as the town loads and its own road panel answers the gate. On
  any other save Vigil leaves the gate alone and Open World answers it. Either way one panel opens, never two.
- Open World asks for the road only once you stand in a town, so a mod that sets the roads as a place loads is always
  first.
- When a game ends, or the mod is switched off, it lets go of both rules.

## For modders

The pattern here works for any one-owner rule: ask for it each time you need it, treat a refusal as "someone else has
it", act on the rule's event only while your own claim stands, and release it on `game.session.ended` and
`runtime.unloaded`. `main.lua` is short and shows all four.

Tests: `lua tools/tests/openworld/test_openworld.lua`.

## Playtest

- [ ] Norune: walk into the Divine Beast Cave and back out with no loading card.
- [ ] Any trip (the world map, a road, a story scene that moves you): no "Now Loading" card; the last picture holds
      for a moment, then the next place is there. An arrival scene plays from its start.
- [ ] Load a save from the title: no "Now Loading" card; the town (or the floor) is there within a second. The same
      from the pause menu's load.
- [ ] In a dungeon, use the escape item, leave by the floor's exit, and get knocked out (pick Leave): each fades to
      black and cuts to the town with no card; the party stands in front of the dungeon.
- [ ] Norune: go into a house and come out again. The party opens the door, then the room (or the town) is there,
      with no fade to black; the door's sound plays as it did. Try a house in another town as well.
- [ ] Norune before Matataki is on the world map: the gate still opens the world map.
- [ ] Once Matataki is open: the gate shows **The road** with Matataki Village and Stay; the party stands still while
      the panel is up.
- [ ] Take the road to Matataki; its gate offers Norune (and Queens once open).
- [ ] Queens: the road offers the Shipwreck, and taking it starts at floor 1.
- [ ] With Vigil on and a Vigil World save: Vigil's road panel shows, not this one.
- [ ] Dark Genie's Gauntlet: nothing changes.
