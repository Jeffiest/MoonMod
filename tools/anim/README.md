# tools/anim

Motion authoring for the Chronicle port's playable characters (`animations.player_register`). To make your own,
follow [docs/ANIMATION_GUIDE.md](../../docs/ANIMATION_GUIDE.md) (a full walkthrough with the example mod in
`examples/new-move`). How the engine side works and Toan's Gauntlet set are in
[docs/GAUNTLET_ANIMATIONS.md](../../docs/GAUNTLET_ANIMATIONS.md).

- `moonanim.py`: the library: read a character pack and its converted glTF, sample native poses, pose in world space
  (body turn, leg/arm IK, aim), bake keyposes, write `moonmod-motion` files, draw stick-figure sheets, convert a glTF
  action.
- `inspect_rig.py`: a character's native motions, its bones with where they sit at idle, and a stick sheet of every
  native motion.
- `toan_moves.py`: Toan's Dash Thrust, Whirlwind, Rising Slash, Roll, Backstep, Heavy Chop, Launcher, Spin Finisher,
  Back Slash and Roll Slash.
- `xiao_moves.py`: Xiao's Triple Shot, Tumble, Hop Shot, Heavy Shot and Volley (a second character's rig: her own bones, `c_ctr`).
- `party_moves.py`: Goro's and Ungaga's melee set and Ruby's and Osmond's caster set from one spec per rig and one
  recipe per kind of fighter (`python party_moves.py <mainchara> <out> [sheets] [goro,ungaga,ruby,osmond]`).
- `editor/`: the animation editor, a page in your browser to pose, time and save motions by hand on any character
  or monster (`python tools/anim/editor/server.py`; see its README).
- `vigil_moves.py`: Vigil's evades (Toan's dive roll).
- `verify.py`: checks the conventions and the authored files against the game's data (any of the six characters).

Python 3.11, no packages needed (the editor's page loads three.js from jsDelivr).
