# New Move (animation example)

Gives Toan an animated attack of his own: run, then attack, for an Overhead Chop. The motion was authored with
`tools/anim` and is walked through step by step in [docs/ANIMATION_GUIDE.md](../../docs/ANIMATION_GUIDE.md).

- `make_anims.py`: writes `resources/anims/toan_overhead_chop.json` from Toan's own skeleton
  (`python examples/new-move/make_anims.py <data>/dun/mainchara [sheet.png]`).
- `main.lua`: registers the motion and binds it to a move with a hit, a sound and a trail.

Chronicle only. If the Gauntlet's New moves setting is on, it already owns Toan's run attack and this move is refused;
turn that setting off to try the example.
