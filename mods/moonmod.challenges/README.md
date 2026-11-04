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
