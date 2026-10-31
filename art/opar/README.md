# Opar

The Gauntlet's seventh playable character: a frog mage with a staff, spit attacks, and a jump-slam that turns him
into the game's own Opar monster (`e104a`). The concept is `concept.jpg`; how he plays is
[docs/OPAR_PLAN.md](../../docs/OPAR_PLAN.md).

- `make_opar.py`: makes the model, its paint and its weights in `opar.blend`. Shapes, colours and gear are in the
  script, so a change is an edit and a rerun:
  ```bash
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b art/opar/opar.blend --python art/opar/make_opar.py
  ```
  - **One skin.** The body's volumes are fused by a voxel remesh, smoothed, and its detail is carved into the
    surface (belly folds, the crease under the pecs, nubs, nostrils) before it is decimated to about 5,400
    triangles. Brows and eyelids are part of it; nothing is stacked on the belly.
  - **Gear** sits on that skin, placed by rays: lips, eyes, gill frills, domed and plated pauldrons with a straw
    fringe and moss, round-edged straps and belt, buckle, pouch, gourd, sash, a draped ragged loincloth, a leather
    bracer, and cloth wraps wound as two crossing spiral strips with a loose tail.
  - **Feet** (reworked 2026-10-30; they were flat paddles): a thick ankle over a round heel, an instep sloping down
    to the ball, turned out 20 degrees; four toes fanned wide, each arched at a knuckle and ending on a round pad on
    the floor, webbed between their bases only (`previews/opar_feet.png`, before and after).
  - **Wide hips** (2026-10-30): `proportions.json` moves his hip frames (`chn5`, `chn22`) 0.7 out from Toan's, so
    the legs stand apart with a gap below the belly. `make_opar.py` moves the bones in `opar.blend` to match (once:
    the applied offsets are kept on the armature), and the build moves the pack's frames and bind pose
    (`tools/chr/README.md`). Toan's motions only turn those frames, so every motion keeps the wider stance.
  - **Paint** is baked by Cycles at 1024 and scaled to the pack's 256 x 256 pictures: dense spots of varied size with
    lighter rims, the tan front worked out per pixel, lips, leather grain, iron, cloth weave, the creases' shade and a
    light from above.
  - About 15,000 triangles in all.
- `opar.blend`: collection **Character** (the armature and the body `skin`, exported) and **Template reference**
  (Toan's meshes and the concept picture, not exported). It can be edited by hand too; rerunning `make_opar.py`
  replaces the body.
- `textures/`: the baked pictures, by the pack's texture names: `c07d02` the head, `c07d03` torso and arms, `c07d05`
  legs and feet, `c07d04` the gear.
- `make_staffs.py`: his six staffs (plan §4), each modelled and baked into a 128 x 128 picture in the weapon pack's
  own space (the hand at the origin, the shaft along +Z), written to `staffs/<stem>.json` and `.png`:
  `opst01` Driftwood (a bleached hook), `opst02` Reed (a tied bundle with fronds), `opst03` Coral (branching coral
  crown), `opst04` Bog Oak (two twisted black stems, a root knot, moss), `opst05` Moonpearl (a silver claw holding
  a pearl), `opst06` Tidecaller (the concept's spiral hook round a glowing teal disc with a coral rune, rope, moss).
  Written out 1.45 times their modelled size (`SCALE`), so in his hand each reaches from the ground to past his head
  as in the concept; the mod registers them with `menu_scale = 0.7` so the weapon menu still fits them.
  1,000 to 3,400 triangles each. Built into weapon packs by `tools/chr/build_weapon.py` on Toan's sword `c01w05`
  (template 262): `build/weapons/<stem>.chr`, each 90-255 KB.
- `previews/`: lit renders beside the concept (`opar_v3_lit.png`: T-pose, arms down, three-quarter) and the staffs
  (`staffs.png`, with Tidecaller in Toan's hand in game).
- `build/` (not kept): the template, the exports and `c07d.chr`.

```bash
python tools/chr/build_character.py build E:/Gauntlet-build/run/data/dun/mainchara
python tools/chr/chrtool.py export art/opar/build/c07d.chr art/opar/build/rig        # his skeleton, for the motions
python tools/anim/opar_moves.py art/opar/build/c07d_template.chr art/opar/build/rig/c07d.gltf art/opar/build/c07d.chr
```

**Motions** (`tools/anim/opar_moves.py`): his pack's motion file rewritten from Toan's. Every frame gets his posture
(the pelvis 2.0 lower, a 9 degree forward lean, the feet wider with the knees bowed out) and, outside his attacks,
the staff stands upright in his right hand; his idle (squatting, breathing, looking round), walk (a waddle) and run
(two low hops a loop, both feet together) are his own. The script saves `build/c07d.mot`, which later builds put back,
so it only needs rerunning when the motions or the skeleton change.

**State, 2026-10-29.** The pack builds and checks out exactly (every triangle, UV and weight; the textures within 2
levels of the paint), and the Gauntlet ships it (`mods/moonmod.roguelike/resources/opar/c07d.chr`). In his own slot
(phase 3, `darkcloud_slot7.exe`) it loads at 207,891 quadwords of the character model buffer, and he idles, walks and
fights with the body following the bones. In shadow the hide reads nearly black.

Tidecaller was checked in game in Toan's hand (registered on template 262 with `model = "opst06"`, given and
equipped): it draws at the right size and swings with the hand. Held at rest it points forward as Toan's sword does,
end-on to the camera; the angle in the hand is set with his own motions (phase 5).

Still to do: the staffs' spit effects and the rest of phase 4, his own shadow model (the ground shadow is Toan's silhouette), the rest of his proportions
(Toan's long legs; phase 5), and the eye-blink lines in `base.cfg`, which still write into `c07d01` (unused).
