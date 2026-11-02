# tools/anim

Motion authoring for the Chronicle port's playable characters (`animations.player_register`) and native monsters
(`animations.monster_register`). To make your own,
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
  or monster (`python tools/anim/editor/server.py`; see its README). `editor/mcp_server.py` lets an MCP client
  (Claude Code reads the repository's `.mcp.json`) list, pose, retime, save and screenshot on the open page.
- `reference/`: reads Elden Ring animations from your own install and downloaded repositories into a local cache, for
  the editor's Reference panel to show beside a character (C#, .NET 9, built against DSAnimStudio's libraries; see its
  README). Nothing of it is committed or shipped. `reference/import_motion.py` retargets one onto Toan in place of a
  mod's motion, in a player's own save only, and prints what `motion_checks.py` finds in what it wrote.
- `vigil_moves.py`: Vigil's evades (Toan's dive roll).
- `vigil_lead_foot.py`: the dive roll pushing off his right foot, mirrored from the left-foot one.
- `vigil_side_rolls.py`: the side rolls, the dive roll with his whole body turned into the way he goes.
- `vigil_monster_moves.py`: Vigil's monster motions: a roll each way and a new attack (the Skeleton's whirl, the
  Dasher's pounce) built from each monster's own poses (`python vigil_monster_moves.py <dun/monstor folder>`).
- `motion_checks.py`: what an animator would catch in a motion: a limb snapping round against the body (a fail), and
  in an evade a whipping blade, a push-off later than 0.15 s, and the foot it pushes off. Toan's rig so far.
- `hold_bone.py`: eases a bone's turn against another across a span of frames, the fix for a snap the checks find.
- `verify.py`: checks the conventions and the authored files against the game's data (any of the six characters),
  and runs `motion_checks.py` over them.

Python 3.11, no packages needed (the editor's page loads three.js from jsDelivr).
