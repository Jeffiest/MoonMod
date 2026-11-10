# Seda: the eighth hero

Seda, the swordsman who fought the Dark Genie four hundred years ago, as a playable hero in three places: Seda's
Chronicle (his own prologue), Dark Genie's Gauntlet and the story game. He is built the way Opar was
([OPAR_PLAN.md](OPAR_PLAN.md)), on Toan's skeleton, so he plays Toan's motions and fights with Toan's swords.

## Where he stands (2026-11-04)

| Piece | State |
|---|---|
| Model | His own, from the game's pack `c07a` (his floor 8 fight): `build_character.py retail` finds it, and `make_seda.py --retail` fits it onto Toan's skeleton with his weights and bakes his pictures into the pack's pages. Checked on a test model (raised arms, a fifth larger: back on Toan's skeleton to 0.01); not yet run on the real pack. A look-alike stand-in fills `seda.blend` until then. |
| Pack (`c08d.chr`) | **Not built.** It needs the DC1 toolkit and the disc's data, which the cloud session that wrote the pipeline did not have. Two commands on a machine that has them (`art/seda/README.md`). |
| Registration | Done: the Gauntlet registers him when `resources/seda/c08d.chr` is in it, right after Opar (engine indices 6 and 7; one mod owns an id) |
| Gauntlet | Done: the **Seda** setting adds him to new runs, alongside Opar's roster (a party of eight; a session's party reaches index 7 only past Opar). He drafts, leads and appears in the Party tab like the others. Headless: scenario 30 |
| Seda's Chronicle | Done: four chapters and an epilogue (Challenges row). He takes the field when registered; Toan stands in until then |
| Story | Done: after his Chronicle is seen to its end, the Challenges mod's **Seda Joins the Party** action calls `party.join`, with a Dagger in hand |

## Still to do, in order

1. **Run `retail`, build the pack** and look at him in game: idle, run, swing, hurt, the item menu. If his joints
   are not named as Toan's (the log says "scaled and weighted by distance"), map his names onto Toan's in
   `retail_model`. Expect his coat to need its weights eased between the hips and thighs.
2. **Portrait**: a 128 x 128 face for the switch wheel and the weapon page (`portrait` on `register_playable`).
3. **His own motions**: a taller, straighter idle and run than Toan's (the `tools/anim` pipeline Opar's motions used).
4. **A kit of his own** on Toan's controls (`player.moves_set`), as Opar has: a rising slash, a moonlit thrust that
   pierces, and a guard counter. Ideas for his Signature sky in the Gauntlet: Moonlit Blade (charged hits stop the
   enemy), Old Soldier (less recoil), Four Hundred Years (survive one fatal blow a floor).
5. **His sword**: the broken blade of the epilogue, as a weapon of his own (`weapons.register` with a model), rebuilt
   by building it up.
6. **Voice**: none of the game's voices is his; a set like Opar's in `art/seda/sounds`.
7. **A story join with a reason**: today the action is offered once his Chronicle is done. Better: after the story's
   floor 8 fight, find the flag the game sets there and have him join when the Dark Genie falls.
