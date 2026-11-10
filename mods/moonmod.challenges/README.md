# Challenges

Boss fights worth the name, and the title menu's **Challenges** row.

## Boss phases (the story game)

When a story boss comes into sight it gets a name card and an HP bar at the top left. Below half its health it is
**enraged**: it hits 40% harder, its defense rises by a fifth, it glows red and grows a little, with a burst of smoke
and a notice. Below a fifth it is **desperate**: harder still, and purple. Every number is a setting.

The bosses are Dran, Master Utan, the Ice Queen, the King's Curse, Minotaur Joe and both forms of the Dark Genie,
known by their native model numbers. Challenges leaves Dark Genie's Gauntlet alone: its Wardens are its own.

## Boss Rush (title menu > Challenges)

Every story boss, one after another, in one sealed arena. The run starts on a small registered floor with no
monsters and no chests. Its Warden room stands open; walk in, the doors shut, and Dran rises. Each boss comes in the
story's order where the last one fell, and the party grows to that boss's place in the story: more max HP, and a
damage multiplier on the starting weapons. Every hero can hurt every boss, so the Ice Queen is not Ruby's alone.

Between fights a panel offers a boon: **Mend** (full heal and a mended weapon), **Whet** (+15% damage for the rest of
the run and half a heal) or **Supplies** (two Bread, a Tasty Water, a Repair Powder and half a heal). The Dark Genie's
true form rises straight out of his first, with no rest between.

The clock runs from the moment you walk in to the last blow. The best time, clears and the furthest boss reached are
kept and shown on the Boss Rush page. *Boss Rush party* in the settings chooses the whole party or Toan alone, and
*Boss Rush boss life* scales every boss.

## The Shaft (title menu > Challenges)

An endless descent. The Shaft has one floor in each of the Divine Beast Cave, Wise Owl Forest and the Moon Sea, and
each floor's gate leads back to itself, built anew, so the floors never run out. The gate always leads down and the
Escape menu is refused; Start opens a menu with **End the descent**.

- **Depth.** Every monster grows with each floor: +15% life, +6% damage and +1 defense a floor. The party grows a
  little slower: +10% damage and +6 max HP a floor. A stratum also adds monsters.
- **Guardians.** Every tenth floor's exit room is sealed until the rest of the floor is clear. Inside waits the floor's
  toughest monster, grown huge, with six times its life.
- **Pacts.** A felled guardian heals the party and offers three pacts, each a harder rule that pays: Swarm (more
  monsters, more Gilda), Glass (they hit harder, so do you), Iron (tougher monsters, slower wear), Drought (thirst,
  more chests), Darkness (no map, more ABS) and Hunger (no heal between strata, a Fruit of Eden). Pacts stack. Then the
  descent moves to the next dungeon.
- **Records.** The deepest floor reached is kept and shown on the Shaft's page.

The party starts with three Bread, two Tasty Water and two Repair Powder. *The Shaft party* in the settings chooses
everyone or Toan alone.

## Seda's Chronicle (title menu > Challenges)

A prologue, four hundred years before Dark Cloud: Seda, a swordsman, goes down after the Dark Genie. Four chapters, each
opening with a card and a page of story and closing with another:

1. **The Moonlit Cave**: cut down twelve of the Genie's creatures.
2. **The Wise Owl's Wood**: find three relics in the forest's chests (more chests than usual).
3. **The Moon Sea**: clear the floor, then fell the guardian in the sealed room, grown from the floor's toughest monster.
4. **The Genie's Lair**: the pink Dark Genie and then his true form, in the Boss Rush arena.

An epilogue of four pages ties it to the game: the Genie survives, Seda is cursed to wait in the cave for a boy from
Norune. A wanderer by each floor's exit gate repeats the chapter's task, and Start opens a menu to leave. The
chapters reached and the end are kept on the page.

The Chronicle uses the Shaft's floors and the Boss Rush arena, so it takes no floor slot of its own. Seda is a
playable character once his pack is built (`docs/plans/SEDA_PLAN.md`): with `resources/seda/c08d.chr` in this mod he
registers as the Chronicle starts and takes the field. Until then Toan walks in his place.

## Floor slots

A dungeon holds 25 floors, and the Gauntlet takes seven in each of the five, which fills the Shipwreck and the Sun and
Moon Temple. Boss Rush's arena goes in the Divine Beast Cave (or the Moon Sea) and the Shaft takes one floor each in the
Cave, Wise Owl Forest and the Moon Sea, so everything fits beside the Gauntlet.

The title menu has room for two mod rows, and the Gauntlet holds one, so later challenge modes join this row's pages.

Tests: `lua tools/tests/challenges/test_challenges.lua`.

## Playtest

- [ ] Story: meet Dran on Divine Beast Cave's boss floor. The card shows without breaking his entrance scene.
- [ ] Story: Dran turns red at half health and purple at a fifth, and hits visibly harder.
- [ ] Boss Rush: the arena floor is small, the Warden room is open, and walking in shuts it.
- [ ] Boss Rush: each boss and its helpers fight properly in the Warden room (the Ice Queen's spells, the King's
      Curse rising, Joe's kegs, both Genies).
- [ ] Boss Rush: the party's damage feels right at each tier. Tune `TIER_POWER` and `TIER_HP` in `main.lua`.
- [ ] Boss Rush: the boon panel appears between fights, and a clear goes back to the title with the time.
- [ ] Shaft: the gate on floor 1 leads to a new floor 2; Escape is refused; Start offers End the descent.
- [ ] Shaft: floor 10's room opens once the floor is clear, the guardian is huge, and its fall offers the pacts.
- [ ] Shaft: after a pact, the descent arrives in Wise Owl Forest at floor 11.
- [ ] Seda's Chronicle: each chapter's card and story page show on arrival, the wanderer repeats the task, and
      the epilogue leads back to the title.
- [ ] Shaft: monsters by floor 20 feel hard but fair. Tune the growth numbers in `shaft_scale` and `shaft_tuning`.
